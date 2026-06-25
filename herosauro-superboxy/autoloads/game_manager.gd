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

var state: int = State.MENU
var score: int = 0
var fight_time: float = 0.0

# --- Session config (written by the main menu, read at spawn time) ---------
var difficulty: int = Difficulty.NORMAL
var player_count: int = 2     # 1 = solo + AI ally, 2 = local co-op
var human_hero: int = 1       # in 1P: which hero the human drives (1 or 2)

var player_health := {1: MAX_PLAYER_HEALTH, 2: MAX_PLAYER_HEALTH}
var boss_health: int = MAX_BOSS_HEALTH
var boss_phase: int = 1
var p2_combo: int = 0

var _combo_window: float = 0.0


func _ready() -> void:
	# Keep running (and listening for unpause input) even while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	fight_time += delta
	timer_updated.emit(fight_time)
	if _combo_window > 0.0:
		_combo_window -= delta
		if _combo_window <= 0.0 and p2_combo != 0:
			p2_combo = 0
			combo_changed.emit(2, 0)


## Reset everything and begin a new fight.
func start_game() -> void:
	score = 0
	fight_time = 0.0
	player_health = {1: MAX_PLAYER_HEALTH, 2: MAX_PLAYER_HEALTH}
	boss_health = MAX_BOSS_HEALTH
	boss_phase = 1
	p2_combo = 0
	_combo_window = 0.0
	change_state(State.PLAYING)
	game_started.emit()
	# Push an initial sync so freshly-shown HUD elements start at the right value.
	boss_damaged.emit(0, boss_health)
	player_damaged.emit(1, 0, player_health[1])
	player_damaged.emit(2, 0, player_health[2])
	score_changed.emit(score)
	combo_changed.emit(2, 0)
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
	if state != State.PLAYING:
		return
	player_health[player_id] = max(0, int(player_health[player_id]) - amount)
	player_damaged.emit(player_id, amount, player_health[player_id])
	if int(player_health[1]) <= 0 and int(player_health[2]) <= 0:
		_end_game(false)


func notify_player_respawned(player_id: int) -> void:
	player_respawned.emit(player_id)


func damage_boss(amount: int, source_player: int) -> void:
	if state != State.PLAYING or boss_health <= 0:
		return
	boss_health = max(0, boss_health - amount)
	boss_damaged.emit(amount, boss_health)

	var points := SCORE_PER_HIT
	if source_player == 2:
		p2_combo += 1
		_combo_window = COMBO_TIMEOUT
		points = SCORE_PER_HIT * p2_combo
		combo_changed.emit(2, p2_combo)
	add_score(points)

	if boss_phase == 1 and float(boss_health) / float(MAX_BOSS_HEALTH) <= BOSS_PHASE2_RATIO:
		boss_phase = 2
		boss_phase_changed.emit(2)

	if boss_health <= 0:
		_end_game(true)


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
