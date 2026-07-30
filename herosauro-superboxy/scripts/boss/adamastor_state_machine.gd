class_name AdamastorStateMachine
extends RefCounted
## Attack + movement brain for Adamastor.
##
## Owned by the boss node, ticked every physics frame via update(delta) while the
## game is PLAYING. The boss FSM is the single source of horizontal velocity (the
## boss zeroes velocity.x/.z each frame, then we drive it here).
##
## State graph:
##   IDLE       -> brief reposition hub, immediately commits to CHASE
##   CHASE      -> stride toward the hero he is angriest at (with a strafe weave),
##                 facing them; slam in melee range, lob a volley when held off
##   SLAM       -> AOE mark on the deck, wind-up, forward lunge, feet shockwave
##   ROCK_THROW -> one MARKER per rock, planted the instant the throw is
##                 committed, then the volley
##   ROAR       -> the phase-two entrance: coil, a wide AOE mark, then the blast
##   RETREAT    -> back away briefly so he doesn't simply stand on the heroes
##   PHASE_TWO  -> one-shot hand-off into ROAR
##
## ---------------------------------------------------------------------------
## ROSTER TUNING
##
## Every heavy move the giant makes is aimed at ONE hero. With two on the deck
## that halves the pressure each of them feels while the team's health pool
## doubles and gains a revive loop, so the same numbers that make a solo fight
## tense make a co-op fight limp. Three things are derived from
## GameManager.active_player_ids() (never from an assumed [1, 2]) rather than
## simply being made bigger:
##
##   * CADENCE. `_pressure` = 1 + ROSTER_CADENCE * (n - 1), and the gaps that are
##     the GIANT'S OWN HESITATION are divided by it: the decision interval and
##     the slam gap. At n = 2 that is 1.45, so the pair together face 45% more
##     decisions and each of them — if he split his attention evenly — faces 72%
##     of the solo rate instead of 50%.
##
##     The two gaps that belong to the PLAYER are pointedly not divided by it.
##     The wind-up is the tell, and a tell that shrinks because your friend
##     turned up is a tell that lies. The retreat is the punish window, and in
##     co-op it is a SHARED one — the giant backing off is the moment both heroes
##     get to swing, so shortening it takes time away from two people at once.
##     Measured: dividing the retreat as well raised the slam rate 16% and cost
##     the heroes enough ground that the co-op stream's own melee assertions
##     started failing three runs in five. The rule that came out of it is worth
##     more than the number — a gap the player acts in is not the giant's to take.
##
##   * COVERAGE. A volley is one rock per hero still standing, so flanking is no
##     longer free; the giant can only slam one of them, and the volley is the
##     attack that answers the second. Phase two adds a lead rock at where the
##     hero he is angriest at is HEADING, so the answer to it is to change
##     direction rather than to keep running in a straight line.
##
##   * FOCUS. He targets by threat, not by distance alone (Adamastor.
##     target_player()), so out-damaging your partner pulls him onto you. A hero
##     who takes the giant's whole attention faces a slam roughly every 1.9 s
##     against solo's 2.2 s — MORE than they would face alone. That is the point:
##     in co-op, threat is a resource the pair trade rather than a coin flip on
##     who happened to be nearer.
##
## Per-attack DAMAGE is deliberately not part of this; see the note on
## Adamastor.CONTACT_DAMAGE.
##
## Phase two then multiplies two things, and only two, which is enough to
## reproduce every hand-tuned phase-two number the file used to carry as its own
## constant: PHASE2_CADENCE on the gaps between attacks and PHASE2_RECOVERY on
## the wind-up and recovery inside one. He gets angrier, not busier.

enum { IDLE, CHASE, SLAM, ROCK_THROW, RETREAT, PHASE_TWO, ROAR }

const ShockwaveScene: PackedScene = preload("res://scenes/fx/shockwave.tscn")
const RockScene: PackedScene = preload("res://scenes/fx/rock_projectile.tscn")

# --- Shape of one attack (solo, Normal, phase one) --------------------------
## Seconds the slam's active-frames window stays open.
const SLAM_WINDOW := 0.16
## The tell. Long enough to read the ring filling and step off it.
const SLAM_WINDUP := 0.55
const SLAM_RECOVER := 0.45
const SLAM_SETTLE := 0.25
## Minimum gap between slams — the hero's punish window.
const SLAM_GAP := 1.3
const RETREAT_TIME := 0.55
const ROCK_WINDUP := 0.5
const ROCK_RECOVER := 0.35
const ROCK_SETTLE := 0.2

const SHOCKWAVE_DAMAGE := 14
const SHOCKWAVE_DAMAGE_P2 := 20
const ROCK_DAMAGE := 15
const ROCK_DAMAGE_P2 := 18
## How far ahead of a moving hero the phase-two lead rock is aimed.
const ROCK_LEAD := 0.55

# --- Movement / decision baselines ------------------------------------------
const BASE_SPEED := 5.8
const BASE_AGGRESSION := 0.5
const MELEE_RANGE := 7.0
const ROCK_RANGE := 16.0
const DECIDE_BASE := 3.4
## Floor and ceiling on the decision interval. The floor is what HARD co-op in
## phase two lands on (3.4 / (1.4 * 1.45) * 0.65 = 1.52), and below about 1.5 s
## the giant cannot finish an attack before wanting the next one.
const DECIDE_MIN := 1.6
const DECIDE_MAX := 4.4

# --- Roster scaling ---------------------------------------------------------
## Cadence each hero beyond the first adds. See the ROSTER TUNING note above.
const ROSTER_CADENCE := 0.45
## Ground speed each extra hero adds. Small on purpose: two heroes can put the
## full 16 m of PlayerBase's leash between them, so a target swap costs him real
## walking, and without a little more speed he spends the co-op fight commuting.
const ROSTER_SPEED := 0.10
## ...and the hard ceiling on all of it, which is not a feel number. A hero walks
## at 8.0 m/s and sprints at 8.0 * 1.3 = 10.4 (PlayerBase). A giant who matches a
## sprint is a giant you cannot break away from, and "run" stops being an answer
## to anything. 9.6 leaves most of a metre per second of escape, and it is what
## HARD co-op in phase two would otherwise blow through: 5.8 * 1.4 * 1.1 * 1.2 is
## 10.7 m/s.
const SPEED_CAP := 9.6
## And how much more willing he is to throw. Ranged is the answer to a spread.
const ROSTER_AGGRESSION := 0.20

# --- Phase two --------------------------------------------------------------
## Multiplies the GAPS between attacks (decision interval, slam gap).
## 1.3 * 0.65 = 0.85 s, which is the slam gap this file used to hard-code.
const PHASE2_CADENCE := 0.65
## Multiplies the wind-up and recovery INSIDE an attack.
## 0.55 * 0.76 = 0.42 s, which is the wind-up and the retreat it used to
## hard-code. He commits faster; the shape of the fight is unchanged.
const PHASE2_RECOVERY := 0.76
const PHASE2_SPEED := 1.2
const PHASE2_AGGRESSION := 0.2

# --- The roar ---------------------------------------------------------------
## Crossing 50% used to be a stat change nobody could see. It is now an attack:
## he plants, coils, paints an amber ring the width of the fighting space and
## blows everyone off it.
const ROAR_RADIUS := 11.0
## Longer than a slam's tell, because it is bigger and because the beat of
## anticipation is the whole point of the moment.
const ROAR_WINDUP := 0.85
const ROAR_RECOVER := 0.5
const ROAR_DAMAGE := 16
const ROAR_KNOCKBACK := 18.0
## The wave sweeps out fast — a pressure wave, not the slam's rolling ring — so
## the mark's fill and the wave's rim are never more than this far apart.
const ROAR_WAVE_GROW := 0.3
const ROAR_SHAKE := 0.95
const ROAR_SHAKE_TIME := 0.7
const ROAR_HIT_STOP := 0.12

# --- Telegraphs -------------------------------------------------------------
## How big a rock's crosshair is drawn. The rock itself is under a metre; the
## mark is wider so it is legible from across the deck, and it is the ring
## CLOSING, not its size, that says when.
const ROCK_MARK_RADIUS := 1.6
## Where a rock leaves his hands, above his origin.
const ROCK_HAND := Vector3(0.0, 6.0, 0.0)
## Seconds a thrown rock spends in the air, so a MARKER closes on the frame the
## rock LANDS rather than on the frame it leaves his hand.
##
## This mirrors the ballistic solve inside rock_projectile.gd — arc_time plus
## 0.03 s per metre of throw, clamped — because the projectile belongs to the fx
## stream and a boss does not reach into another subsystem's script
## (ARCHITECTURE.md rule 2). A mirror can drift, so `_boss_probe` measures the
## gap between a mark closing and that rock's first contact and fails the build
## when it exceeds its tolerance: if fx retunes the arc, the probe says so on the
## next run instead of the tell quietly starting to lie.
const ROCK_ARC_TIME := 0.35
const ROCK_ARC_PER_METRE := 0.03
const ROCK_FLIGHT_MIN := 0.5
const ROCK_FLIGHT_MAX := 1.8

# --- Impact contract --------------------------------------------------------
## The slam landing on granite. Adamastor.SLAM_HIT_STOP is the heavier freeze for
## the slam catching a HERO; this is the one for it merely arriving, and it
## no-ops itself when the heavy one has already fired.
const SLAM_GROUND_STOP := 0.04
## The heave. A nine-metre giant hurling masonry has to move the frame even
## before the rock lands.
const THROW_SHAKE := 0.22
const THROW_SHAKE_TIME := 0.16
## The rock landing. On a hero it is a hit and gets a freeze; on granite it is
## still an impact, and it still gets a camera response.
const ROCK_HIT_STOP := 0.05
const ROCK_HIT_SHAKE := 0.30
const ROCK_GROUND_SHAKE := 0.12

## Seeded, because ARCHITECTURE.md rule 4 bans the global randf()/randi() family
## anywhere that reaches the screen and the giant's choice of attack certainly
## does. Re-seeded to the same value in reset(), so two runs of the same fight
## make the same decisions and the capture gate keeps working.
const RNG_SEED := 0x4144414D   # "ADAM"

var boss: Node3D
var state: int = IDLE

# Tunables (derived from difficulty AND roster in reset(), tightened in phase two).
var _move_speed: float = BASE_SPEED
var _aggression: float = BASE_AGGRESSION   # 0..1: bias toward closing/attacking
var _melee_range: float = MELEE_RANGE      # within this -> slam
var _rock_range: float = ROCK_RANGE        # beyond this -> prefer ranged rock
var _decide_interval: float = DECIDE_BASE
var _decide_timer: float = DECIDE_BASE
var _slam_gap: float = SLAM_GAP
var _retreat_time: float = RETREAT_TIME
var _pressure: float = 1.0                 # roster cadence multiplier
var _escalated: bool = false               # phase two: faster, angrier, wider volley

# Busy flag: while an attack tween chain runs we don't pick a new action.
var _busy: bool = false
var _retreat_timer: float = 0.0
var _slam_cd: float = 0.0
var _strafe: float = 0.0
var _attack_tween: Tween = null
var _rng := RandomNumberGenerator.new()

## Where this volley will land. Resolved when the throw is COMMITTED, not when
## the rock leaves his hand, because the marks on the deck promise these points
## and a promise that follows you is not a promise.
var _volley: Array[Vector3] = []
## Every mark currently on the deck, so a cancelled attack can take its own
## telegraph with it.
var _marks: Array[BossTelegraph] = []


func _init(p_boss: Node3D) -> void:
	boss = p_boss
	_rng.seed = RNG_SEED


func reset() -> void:
	state = IDLE
	var ds: float = GameManager.difficulty_scalar()
	# THE roster authority. Never range(1, player_count + 1): a solo run driven as
	# hero 2 has a roster of [2], and counting a hero who does not exist would
	# tune the giant for a fight nobody is having.
	var n: float = float(maxi(1, GameManager.active_player_ids().size()))

	_pressure = 1.0 + ROSTER_CADENCE * (n - 1.0)
	_move_speed = minf(SPEED_CAP, BASE_SPEED * ds * (1.0 + ROSTER_SPEED * (n - 1.0)))
	_aggression = clampf(BASE_AGGRESSION * ds * (1.0 + ROSTER_AGGRESSION * (n - 1.0)), 0.3, 0.95)
	_melee_range = MELEE_RANGE
	_rock_range = ROCK_RANGE
	_decide_interval = clampf(DECIDE_BASE / (ds * _pressure), DECIDE_MIN, DECIDE_MAX)
	_decide_timer = _decide_interval
	_slam_gap = SLAM_GAP / _pressure
	# NOT divided by _pressure. See the ROSTER TUNING note: the retreat is the
	# heroes' punish window, and in co-op it is a SHARED one, so shortening it
	# takes time away from both of them at once.
	_retreat_time = RETREAT_TIME
	_escalated = false
	_busy = false
	_retreat_timer = 0.0
	_slam_cd = 0.0
	_strafe = 0.0
	_volley.clear()
	_rng.seed = RNG_SEED
	_kill_attack_tween()
	cancel_telegraphs()


## Everything this run actually derived. Read by `_boss_probe`, which is how the
## difficulty ladder and the roster scaling stay regression-tested — a tuning
## table nobody can measure is a tuning table that quietly rots.
func tuning() -> Dictionary:
	return {
		"pressure": _pressure,
		"move_speed": _move_speed,
		"aggression": _aggression,
		"decide_interval": _decide_interval,
		"slam_gap": _slam_gap,
		"retreat_time": _retreat_time,
		"slam_windup": _recovery(SLAM_WINDUP),
		"escalated": _escalated,
	}


## Called by the boss when GameManager.boss_phase_changed(2) fires.
func enter_phase_two() -> void:
	if _escalated:
		return
	# The phase flip takes precedence over whatever he was in the middle of —
	# including the mark for a slam that is now never going to land.
	_kill_attack_tween()
	cancel_telegraphs()
	_volley.clear()
	_apply_escalation()
	_busy = false
	state = PHASE_TWO


func stop() -> void:
	# Used on death: park and stay quiet.
	_busy = true
	state = IDLE
	_kill_attack_tween()
	cancel_telegraphs()


## Take every mark off the deck now. A telegraph must never outlive the attack it
## was promising — that is worse than showing no telegraph at all, because the
## player has already been taught to trust it.
func cancel_telegraphs() -> void:
	for tg in _marks:
		if is_instance_valid(tg):
			tg.cancel()
	_marks.clear()


func _kill_attack_tween() -> void:
	if _attack_tween and _attack_tween.is_valid():
		_attack_tween.kill()
	_attack_tween = null


func update(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return

	_slam_cd = maxf(0.0, _slam_cd - delta)

	match state:
		PHASE_TWO:
			_start_roar()
		IDLE:
			_update_idle(delta)
		CHASE:
			_update_chase(delta)
		RETREAT:
			_update_retreat(delta)
		SLAM, ROCK_THROW, ROAR:
			# Attacks run as tween chains; the boss plants (velocity stays zeroed),
			# apart from the slam's nudge-driven lunge.
			pass


# --- Escalation ------------------------------------------------------------

## The stat half of phase two. Split out from the roar so the ceremony and the
## numbers can never disagree about whether he is escalated.
##
## Phase two DOES shorten the retreat, where the roster deliberately does not,
## and the two are not in tension. The roster taking that window would be a
## silent tax for having a friend; phase two taking it is the escalation the
## whole half of the fight is built on, it is announced by a roar, and it lands
## on solo and co-op alike. 0.55 * 0.76 = 0.42 s, which is exactly the number
## this file used to carry as a hand-tuned RETREAT_TIME_P2.
func _apply_escalation() -> void:
	_decide_interval = maxf(DECIDE_MIN, _decide_interval * PHASE2_CADENCE)
	_decide_timer = minf(_decide_timer, _decide_interval)
	_slam_gap *= PHASE2_CADENCE
	_retreat_time *= PHASE2_RECOVERY
	_move_speed = minf(SPEED_CAP, _move_speed * PHASE2_SPEED)
	_aggression = clampf(_aggression + PHASE2_AGGRESSION, 0.3, 0.95)
	_escalated = true


## Wind-ups and recoveries shorten in phase two; gaps are handled separately.
func _recovery(seconds: float) -> float:
	return seconds * (PHASE2_RECOVERY if _escalated else 1.0)


# --- IDLE ------------------------------------------------------------------

func _update_idle(_delta: float) -> void:
	# Brief hub: commit to chasing the heroes.
	if _busy:
		return
	state = CHASE


# --- CHASE -----------------------------------------------------------------

func _update_chase(delta: float) -> void:
	if _busy:
		return
	var target: Node3D = boss.target_player()
	if target == null:
		return

	var to: Vector3 = target.global_position - boss.global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.ZERO

	boss.face_toward(target.global_position)

	# Stride toward the hero with a sideways weave so it doesn't simply beeline.
	_strafe += delta
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var weave := perp * sin(_strafe * 2.2) * 0.35
	boss.velocity.x = (dir.x + weave.x) * _move_speed
	boss.velocity.z = (dir.z + weave.z) * _move_speed

	# Commit to an attack. The gap is what gives the hero a window to actually
	# swing back instead of being slammed the instant they close.
	if dist <= _melee_range and _slam_cd <= 0.0:
		_start_slam()
		return
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide_timer = _decide_interval
		# Held off at distance, or rolling aggression -> lob a volley. The roll is
		# lifted by how far the pair have spread, because two heroes on opposite
		# sides of the deck are exactly the case a slam cannot answer and a volley
		# can. Solo the spread is zero and this is the roll it always was.
		if dist >= _rock_range or _rng.randf() < _aggression * (0.5 + _spread_bias()):
			_start_rock_throw()


## 0 when the heroes are on top of each other, 0.5 when they are at the far end
## of their leash (PlayerBase.LEASH_RADIUS + LEASH_SLACK = 16 m, which is the
## widest the shared camera can hold and therefore the widest they can ever be).
func _spread_bias() -> float:
	var live: Array[Vector3] = []
	for p in boss.get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		if body == null:
			continue
		if body.has_method("is_downed") and body.is_downed():
			continue
		live.append(body.global_position)
	if live.size() < 2:
		return 0.0
	var widest := 0.0
	for i in live.size():
		for j in range(i + 1, live.size()):
			widest = maxf(widest, live[i].distance_to(live[j]))
	return clampf(widest / 16.0, 0.0, 1.0) * 0.5


# --- RETREAT ---------------------------------------------------------------

func _begin_retreat() -> void:
	_busy = false
	_retreat_timer = _retreat_time
	state = RETREAT


func _update_retreat(delta: float) -> void:
	var target: Node3D = boss.target_player()
	if target:
		var away: Vector3 = boss.global_position - target.global_position
		away.y = 0.0
		if away.length() > 0.01:
			away = away.normalized()
			boss.velocity.x = away.x * _move_speed * 0.8
			boss.velocity.z = away.z * _move_speed * 0.8
		boss.face_toward(target.global_position)
	_retreat_timer -= delta
	if _retreat_timer <= 0.0:
		state = CHASE


# --- SLAM ------------------------------------------------------------------

func _start_slam() -> void:
	state = SLAM
	_busy = true
	_slam_cd = _slam_gap
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0

	# Telegraphed forward lunge toward the target as the giant winds up.
	var target: Node3D = boss.target_player()
	if target:
		boss.face_toward(target.global_position, 1.0)
		var dir: Vector3 = target.global_position - boss.global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			boss.nudge(dir.normalized(), 2.0)

	# The ground read. Parented to the giant and offset onto the slam volume, so
	# it tracks his feet through the lunge and marks where the blast WILL be
	# rather than where he was when he started winding up. lead == the wind-up, so
	# the disc arriving at the ring IS the impact frame.
	var windup := _recovery(SLAM_WINDUP)
	_plant_aoe(boss.slam_radius(), windup, BossTelegraph.SLAM_TINT,
		Vector3(boss.slam_offset().x, 0.0, boss.slam_offset().z), &"slam")

	_attack_tween = boss.create_tween()
	# Windup: raise both arms.
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(true))
	_attack_tween.tween_interval(windup)
	# Slam down.
	_attack_tween.tween_callback(_do_slam_impact)
	_attack_tween.tween_interval(_recovery(SLAM_RECOVER))
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(false))
	_attack_tween.tween_interval(_recovery(SLAM_SETTLE))
	_attack_tween.tween_callback(_finish_attack)


## Two layers, and they cannot double-dip because the hero's i-frames swallow
## whichever lands second: the boss's slam hitbox is the heavy close hit, the
## shockwave is the wide, weaker ring that punishes a slow retreat.
##
## Ordering here is the impact contract, and it is deliberate. arm_slam() sweeps
## on the frame it opens, so a hero already inside is hit inside this call and
## Adamastor._on_slam_landed takes the heavy freeze first; the lighter freeze for
## the slam merely landing on granite is requested last and no-ops itself if the
## heavy one already fired (GameManager.hit_stop refuses to nest).
func _do_slam_impact() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	boss.slam_arms_down()
	boss.report_impact(&"slam")
	boss.arm_slam(SLAM_WINDOW)
	var wave := ShockwaveScene.instantiate()
	wave.damage = SHOCKWAVE_DAMAGE_P2 if _escalated else SHOCKWAVE_DAMAGE
	_spawn(wave, boss.global_position)
	GameManager.request_shake(0.5, 0.3)
	AudioManager.play_boss_slam()
	GameManager.hit_stop(SLAM_GROUND_STOP)


# --- ROAR (phase two) -------------------------------------------------------

## The phase flip as an ATTACK, not a stat change. Everything the impact contract
## asks for is here: the shockwave and the ring are the FX, request_shake is the
## camera, play_boss_slam is the transient, hit_stop is the freeze, and the UI
## acknowledgement is already in flight — GameManager emitted boss_phase_changed
## before this ran, and the HUD punches its whole boss banner on it.
func _start_roar() -> void:
	state = ROAR
	_busy = true
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0
	var target: Node3D = boss.target_player()
	if target:
		boss.face_toward(target.global_position, 1.0)

	_plant_aoe(ROAR_RADIUS, ROAR_WINDUP, BossTelegraph.ROAR_TINT, Vector3.ZERO, &"roar")
	boss.roar_coil(ROAR_WINDUP)

	_attack_tween = boss.create_tween()
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(true))
	_attack_tween.tween_interval(ROAR_WINDUP)
	_attack_tween.tween_callback(_do_roar)
	_attack_tween.tween_interval(ROAR_RECOVER)
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(false))
	_attack_tween.tween_callback(_begin_retreat)


func _do_roar() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	boss.report_impact(&"roar")
	boss.roar_release()
	var wave := ShockwaveScene.instantiate()
	wave.damage = ROAR_DAMAGE
	# Explicit rather than left on the scene's defaults, because the mark on the
	# deck promises exactly this circle. The wave still needs ROAR_WAVE_GROW to
	# sweep it, so the tell is up to that early at the rim and exact at the
	# centre — early is the only direction a tell is allowed to be wrong in.
	wave.max_radius = ROAR_RADIUS
	wave.grow_time = ROAR_WAVE_GROW
	wave.knockback = ROAR_KNOCKBACK
	_spawn(wave, boss.global_position)
	GameManager.request_shake(ROAR_SHAKE, ROAR_SHAKE_TIME)
	AudioManager.play_boss_slam()
	GameManager.hit_stop(ROAR_HIT_STOP)


# --- ROCK_THROW ------------------------------------------------------------

func _start_rock_throw() -> void:
	state = ROCK_THROW
	_busy = true
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0

	var target: Node3D = boss.target_player()
	if target:
		boss.face_toward(target.global_position, 1.0)

	# COMMIT the volley here, at the top of the wind-up, and mark every landing
	# spot on the deck now. The rocks are launched at these same points later, so
	# stepping off a mark beats it — which is only true because the target is
	# resolved once, here, and never re-read.
	_volley = _rock_volley()
	var windup := _recovery(ROCK_WINDUP)
	for t in _volley:
		_plant_marker(t, windup + _rock_flight_time(t))

	_attack_tween = boss.create_tween()
	# Windup: cock one arm back.
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(true))
	_attack_tween.tween_interval(windup)
	_attack_tween.tween_callback(_do_rock_throw)
	_attack_tween.tween_interval(_recovery(ROCK_RECOVER))
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(false))
	_attack_tween.tween_interval(_recovery(ROCK_SETTLE))
	_attack_tween.tween_callback(_finish_attack)


func _do_rock_throw() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	var damage: int = ROCK_DAMAGE_P2 if _escalated else ROCK_DAMAGE
	for t in _volley:
		var rock := RockScene.instantiate()
		rock.damage = damage
		# Spawn up at the boss's hands, then arc toward the committed point.
		_spawn(rock, boss.global_position + ROCK_HAND)
		if rock.has_method("launch"):
			rock.launch(t)
		_watch_rock(rock)
	# One throw gesture, one sound and one shove of the frame — a phase-two
	# volley is still a single heave. Skipped on an empty volley (no target), so
	# there is never a heave without a rock.
	if not _volley.is_empty():
		AudioManager.play_rock_throw()
		GameManager.request_shake(THROW_SHAKE, THROW_SHAKE_TIME)
	_volley.clear()


## Where this volley lands. One rock per hero still standing, so a flank costs
## something; in phase two a further rock at where the hero he is angriest at is
## HEADING, so the answer is to change direction rather than to keep running in a
## straight line. The roster comes from the scene, so a downed hero is not thrown
## at and a solo run gets exactly the one-rock (two in phase two) volley it had.
func _rock_volley() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var focus: Node3D = boss.target_player()
	if focus == null:
		return out

	for p in boss.get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		if body == null:
			continue
		if body.has_method("is_downed") and body.is_downed():
			continue
		out.append(body.global_position)
	if out.is_empty() or not _escalated:
		return out

	out.append(_lead_point(focus))
	return out


## Where `who` will be by the time the rock arrives, or — if they are standing
## still — a step to the side of them, across the deck rather than along it, so
## there is still somewhere to dodge to.
func _lead_point(who: Node3D) -> Vector3:
	var here: Vector3 = who.global_position
	var drift := Vector3.ZERO
	if who is CharacterBody3D:
		drift = (who as CharacterBody3D).velocity
	drift.y = 0.0
	if drift.length() < 1.0:
		var side := here - boss.global_position
		side.y = 0.0
		drift = Vector3(-side.z, 0.0, side.x).normalized() * 4.0
		if drift.length() < 0.01:
			drift = Vector3(0.0, 0.0, 3.0)
	else:
		drift *= ROCK_LEAD
	return here + drift


## Flight time for a rock thrown at `target`, mirroring rock_projectile.launch().
## See the note on ROCK_ARC_TIME for why this is a mirror and how it is policed.
func _rock_flight_time(target: Vector3) -> float:
	var from: Vector3 = boss.global_position + ROCK_HAND
	var horiz := Vector3(target.x - from.x, 0.0, target.z - from.z)
	return clampf(ROCK_ARC_TIME + horiz.length() * ROCK_ARC_PER_METRE,
		ROCK_FLIGHT_MIN, ROCK_FLIGHT_MAX)


## The giant owns the consequences of his own masonry. rock_projectile.gd does
## the damage and the thud; the camera response and the freeze are the boss's,
## because the five-part impact contract is per ATTACK, not per script — and this
## is a signal on a node the boss spawned, not a reach into another stream's code.
func _watch_rock(rock: Node) -> void:
	if rock == null or not rock.has_signal("body_entered"):
		return
	# A one-element array as a mutable cell: a bouncing rock reports a contact
	# every few frames and only the first of them is the impact.
	var once: Array[bool] = [false]
	rock.body_entered.connect(_on_rock_contact.bind(once))


func _on_rock_contact(body: Node, once: Array) -> void:
	if once[0]:
		return
	once[0] = true
	if is_instance_valid(boss):
		boss.report_impact(&"rock")
	if body != null and body.is_in_group("players"):
		GameManager.hit_stop(ROCK_HIT_STOP)
		GameManager.request_shake(ROCK_HIT_SHAKE, 0.22)
	else:
		# Masonry on granite is still an impact; it just is not a hit.
		GameManager.request_shake(ROCK_GROUND_SHAKE, 0.14)


# --- Telegraphs -------------------------------------------------------------

## An AOE ring on the giant himself, offset into his local frame so it rides his
## facing and his lunge.
func _plant_aoe(radius: float, lead: float, tint: Color, offset: Vector3,
		kind: StringName) -> void:
	var tg := BossTelegraph.aoe(boss, radius, lead, tint)
	if tg == null:
		return
	tg.position = offset
	_remember(tg)
	boss.report_telegraph(kind, lead)


## A crosshair pinned to a world point, in the spawn root rather than on the
## giant: a rock's landing spot is committed at wind-up time and must not follow
## anything afterwards.
func _plant_marker(where: Vector3, lead: float) -> void:
	# A mark has to be positioned in the world, so a spawn root that is not a
	# Node3D (a bare test harness) gets no mark rather than a crash.
	var root := _spawn_root() as Node3D
	if root == null:
		return
	var tg := BossTelegraph.marker(root, ROCK_MARK_RADIUS, lead, BossTelegraph.ROCK_TINT)
	if tg == null:
		return
	tg.global_position = where
	_remember(tg)
	boss.report_telegraph(&"rock", lead)


## Keep the live list live: marks free themselves once they have flashed out, so
## compact on the way in rather than growing an array of dead handles.
func _remember(tg: BossTelegraph) -> void:
	var kept: Array[BossTelegraph] = []
	for old in _marks:
		if is_instance_valid(old):
			kept.append(old)
	kept.append(tg)
	_marks = kept


# --- Shared ----------------------------------------------------------------

func _finish_attack() -> void:
	# Back off after committing to an attack so the giant doesn't stand on the heroes.
	_begin_retreat()


func _spawn_root() -> Node:
	var root := boss.get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = boss.get_tree().current_scene
	return root


func _spawn(node: Node3D, pos: Vector3) -> void:
	var root := _spawn_root()
	if root == null:
		node.queue_free()
		return
	root.add_child(node)
	node.global_position = pos
