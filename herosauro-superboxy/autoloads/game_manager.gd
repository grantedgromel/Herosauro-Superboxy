extends Node
## GameManager (autoload singleton "GameManager")
##
## Authoritative hub for game state, score, health and the high-level state
## machine (MENU -> PLAYING -> PAUSED -> VICTORY/DEFEAT -> MENU).
##
## All cross-cutting game events flow through this node's signals so that
## entities and UI stay decoupled: gameplay nodes CALL the mutator methods
## (damage_boss, damage_player, ...) and everyone else REACTS to the signals.

signal state_changed(new_state: int)
signal game_started
signal game_over(victory: bool)

signal player_damaged(player_id: int, amount: int, new_health: int)
signal player_respawned(player_id: int)
signal boss_damaged(amount: int, new_health: int)
signal boss_phase_changed(phase: int)

signal score_changed(new_score: int)
signal combo_changed(player_id: int, combo: int)
signal timer_updated(seconds: float)

## Requests handled by the camera rig / engine for "game feel".
signal camera_shake_requested(strength: float, duration: float)

enum State { MENU, PLAYING, PAUSED, VICTORY, DEFEAT }
enum Difficulty { EASY, NORMAL, HARD }

const MAX_PLAYER_HEALTH := 100
const MAX_BOSS_HEALTH := 500
const FALL_PENALTY := 20
const BOSS_PHASE2_RATIO := 0.5
const COMBO_TIMEOUT := 2.5
const SCORE_PER_HIT := 10

## Health a hero comes back with after being helped up in co-op. Deliberately
## not full: going down has to cost something, or the pair just trade knockouts.
const REVIVE_HEALTH := int(MAX_PLAYER_HEALTH * 0.5)

var state: int = State.MENU
var score: int = 0
var fight_time: float = 0.0

# --- Session config (written by the main menu, read at spawn time) ---------
var difficulty: int = Difficulty.NORMAL
## 1 = solo (one hero, chosen by human_hero), 2 = two-player local co-op.
## There is no AI ally: a hero that is not a seat at the machine is not spawned.
var player_count: int = 2
var human_hero: int = 1       # in 1P: which hero the human drives (1 or 2)

var player_health := {1: MAX_PLAYER_HEALTH, 2: MAX_PLAYER_HEALTH}
var boss_health: int = MAX_BOSS_HEALTH
var boss_phase: int = 1

## Combo is PER HERO, with its own window each. `combo_changed` has always
## carried a player_id and it was a lie while one shared counter backed it — a
## two-hero HUD cannot draw two chains from one number. Each hero keeps their own
## chain alive, and the multiplier they earn is theirs.
var combo := {1: 0, 2: 0}
## Score is a single TEAM number (that is what `score_changed` carries), but the
## split is tracked so a results screen can say who did what.
var player_score := {1: 0, 2: 0}

var _combo_window := {1: 0.0, 2: 0.0}
var _last_scorer: int = 1


## Deprecated. Reports the combo of whoever last landed a hit, and exists only so
## the UI stream's in-flight probe keeps resolving while the HUD is rebuilt for
## two heroes. Call combo_for(player_id).
var p2_combo: int:
	get: return combo_for(_last_scorer)


func _ready() -> void:
	# Keep running (and listening for unpause input) even while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	fight_time += delta
	timer_updated.emit(fight_time)
	for pid in _combo_window.keys():
		if _combo_window[pid] <= 0.0:
			continue
		_combo_window[pid] -= delta
		if _combo_window[pid] <= 0.0 and int(combo[pid]) != 0:
			combo[pid] = 0
			combo_changed.emit(pid, 0)


## Hero ids this session actually spawns. The single source of truth for the
## roster: main.gd spawns exactly these, start_game syncs exactly these, and the
## defeat test falls back to exactly these.
func active_player_ids() -> Array[int]:
	if player_count <= 1:
		return [clampi(human_hero, 1, 2)] as Array[int]
	return [1, 2] as Array[int]


## Reset everything and begin a new fight.
func start_game() -> void:
	score = 0
	fight_time = 0.0
	player_health = {1: MAX_PLAYER_HEALTH, 2: MAX_PLAYER_HEALTH}
	player_score = {1: 0, 2: 0}
	boss_health = MAX_BOSS_HEALTH
	boss_phase = 1
	combo = {1: 0, 2: 0}
	_combo_window = {1: 0.0, 2: 0.0}
	_last_scorer = active_player_ids()[0]
	change_state(State.PLAYING)
	game_started.emit()
	# Push an initial sync so freshly-shown HUD elements start at the right value.
	# Only the heroes that exist: a solo run must not tell the HUD to draw a
	# second health bar for a hero nobody is going to spawn.
	boss_damaged.emit(0, boss_health)
	for pid in active_player_ids():
		player_damaged.emit(pid, 0, player_health[pid])
		combo_changed.emit(pid, 0)
	score_changed.emit(score)
	timer_updated.emit(0.0)


func change_state(new_state: int) -> void:
	state = new_state
	get_tree().paused = (new_state == State.PAUSED)
	state_changed.emit(new_state)


func go_to_menu() -> void:
	change_state(State.MENU)


# --- Session config --------------------------------------------------------

func set_difficulty(d: int) -> void:
	difficulty = clampi(d, Difficulty.EASY, Difficulty.HARD)


func set_player_count(n: int) -> void:
	player_count = clampi(n, 1, 2)


func set_human_hero(h: int) -> void:
	human_hero = clampi(h, 1, 2)


## Aggression / speed multiplier the boss FSM and ally AI scale by.
## EASY is gentler, HARD is faster and more relentless.
func difficulty_scalar() -> float:
	match difficulty:
		Difficulty.EASY:
			return 0.75
		Difficulty.HARD:
			return 1.4
		_:
			return 1.0


func toggle_pause() -> void:
	if state == State.PLAYING:
		change_state(State.PAUSED)
	elif state == State.PAUSED:
		change_state(State.PLAYING)


# --- Combat mutators -------------------------------------------------------

func damage_player(player_id: int, amount: int) -> void:
	if state != State.PLAYING or not player_health.has(player_id):
		return
	player_health[player_id] = max(0, int(player_health[player_id]) - amount)
	player_damaged.emit(player_id, amount, player_health[player_id])
	if _all_heroes_down():
		_end_game(false)


## Help a downed hero back up. Called by PlayerBase once its revive timer runs
## out, which only happens while a partner is still standing — with nobody left
## to do the helping, `_all_heroes_down` has already ended the run.
##
## Re-uses `player_damaged` (with amount 0) rather than adding a signal: every
## listener already keys off the health it carries, so a bar that emptied refills
## and a portrait that dimmed lights back up with no new vocabulary.
func revive_player(player_id: int, health: int = REVIVE_HEALTH) -> void:
	if state != State.PLAYING or not player_health.has(player_id):
		return
	player_health[player_id] = clampi(health, 1, MAX_PLAYER_HEALTH)
	player_damaged.emit(player_id, 0, player_health[player_id])
	player_respawned.emit(player_id)


## True once every hero actually in the world is at zero health.
##
## This used to test `player_health[1] and player_health[2]` directly, which
## could never fire in the single-hero game — the absent second hero sat at full
## health forever, so the player simply could not lose. Ask the scene instead of
## assuming a roster, so solo and co-op both terminate correctly: in co-op one
## hero at zero is DOWN, not defeat, and the run only ends when the partner is
## down too.
func _all_heroes_down() -> bool:
	var found := false
	for p in get_tree().get_nodes_in_group("players"):
		found = true
		var pid := 1
		if "player_id" in p:
			pid = int(p.player_id)
		if int(player_health.get(pid, 0)) > 0:
			return false
	# No hero nodes yet (menu, teardown): fall back to the health table — but
	# only over the roster this session actually fields, or a solo run as hero 2
	# would be held up forever by hero 1's untouched 100 health.
	if not found:
		for pid in active_player_ids():
			if int(player_health.get(pid, 0)) > 0:
				return false
	return true


func notify_player_respawned(player_id: int) -> void:
	player_respawned.emit(player_id)


func damage_boss(amount: int, source_player: int) -> void:
	if state != State.PLAYING or boss_health <= 0:
		return
	boss_health = max(0, boss_health - amount)
	boss_damaged.emit(amount, boss_health)

	# Combo used to be hard-wired to source_player == 2, so it went dead the
	# moment the game became single-hero. It is now per hero: each of them keeps
	# their own chain alive and earns their own multiplier, which is the only way
	# the player_id on `combo_changed` means anything.
	var pid := source_player if combo.has(source_player) else 1
	combo[pid] = int(combo[pid]) + 1
	_combo_window[pid] = COMBO_TIMEOUT
	_last_scorer = pid
	var points := SCORE_PER_HIT * int(combo[pid])
	combo_changed.emit(pid, int(combo[pid]))
	player_score[pid] = int(player_score[pid]) + points
	add_score(points)

	if boss_phase == 1 and float(boss_health) / float(MAX_BOSS_HEALTH) <= BOSS_PHASE2_RATIO:
		boss_phase = 2
		boss_phase_changed.emit(2)

	if boss_health <= 0:
		_end_game(true)


func combo_for(player_id: int) -> int:
	return int(combo.get(player_id, 0))


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)


# --- Game feel helpers -----------------------------------------------------

## Brief engine-wide freeze on impactful hits ("hit-stop").
func hit_stop(duration: float = 0.1) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.0
	# 4th arg = ignore_time_scale, so the timer still fires while frozen.
	var t := get_tree().create_timer(duration, true, false, true)
	await t.timeout
	Engine.time_scale = 1.0


func request_shake(strength: float, duration: float = 0.3) -> void:
	camera_shake_requested.emit(strength, duration)


# --- Internal --------------------------------------------------------------

func _end_game(victory: bool) -> void:
	Engine.time_scale = 1.0
	change_state(State.VICTORY if victory else State.DEFEAT)
	game_over.emit(victory)
