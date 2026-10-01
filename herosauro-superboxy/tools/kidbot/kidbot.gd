extends Node
## Kidbot: a clumsy five-year-old plays one chapter from start to VICTORY.
##
##   godot --headless --path . tools/kidbot/kidbot.tscn --fixed-fps 60 -- \
##       --chapter=dragao --seed=2 [--minutes=15] [--log=30]
##
## Boots main.tscn, picks the chapter, solo with the companion and Ajudas on, and
## starts the game. Hero 1 is then driven ONLY through InputManager's virtual
## channel (set_virtual_move / press_virtual), the way small hands do it:
##
##   * heads roughly toward the nearest goal (the level's hint_target(), else
##     the "boss" node, else the level's camera focus), but only re-reads where
##     it is every REREAD_MIN..REREAD_MAX s, over-steers when it does, and carries
##     a slowly drifting heading error on top;
##   * now and then stops, or wanders off in a random direction, for 1-4 s;
##   * mashes attack in bursts within MASH_RADIUS of a "targets"/"boss" node, and
##     sometimes when nothing is near;
##   * jumps and uses the power at random.
##
## It never teleports and never calls game logic: the only writes are the two
## InputManager virtual-input calls. Everything is seeded from --seed.
##
## Game time is the physics frame count (run with --fixed-fps 60), never the wall
## clock. The run ends at VICTORY or after --minutes of game time (default 15).
## A "stuck" event is SAMPLE_STUCK s without hero 1 moving more than 1 m.
##
## Prints a final machine-readable line:
##   KIDBOT chapter=<id> seed=<n> completed=<0|1> minutes=<m> stuck=<n> stuck_idle=<n>
## and exits 0 on VICTORY, 1 otherwise.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const FPS := 60.0
const REREAD_MIN := 0.25
const REREAD_MAX := 0.7
## Over-steer: the new heading lands this many times past the correction.
const OVERSTEER_MIN := 0.7
const OVERSTEER_MAX := 1.7
## Heading noise (radians): per re-read jitter, and a slow drifting bias.
const JITTER := 0.45
const DRIFT_SIGMA := 0.35
const DRIFT_PULL := 0.25
## Chance per second of stopping/wandering for 1-4 s.
const WANDER_RATE := 0.07
const WANDER_MIN := 1.0
const WANDER_MAX := 4.0
const MASH_RADIUS := 4.0
## The giant is a 5 x 4 m body: its node sits at its feet in the middle.
const BOSS_MASH_RADIUS := 5.5
const MASH_GAP_MIN := 0.12
const MASH_GAP_MAX := 0.3
const BURST_MIN := 3
const BURST_MAX := 8
const BURST_REST_MIN := 0.3
const BURST_REST_MAX := 1.4
## Chance per second of a mash burst at nothing.
const IDLE_MASH_RATE := 0.12
const JUMP_RATE := 0.18
const POWER_RATE := 0.1
## When this close to the goal, a kid stops pushing so hard (but still wobbles).
const ARRIVE := 1.2
const STUCK_WINDOW := 10.0
const STUCK_DIST := 1.0

var _rng := RandomNumberGenerator.new()
var _chapter: String = "dragao"
var _seed: int = 1
var _cap_frames: int = int(15.0 * 60.0 * FPS)
var _log_every: int = int(30.0 * FPS)

var _main: Node = null
var _frame: int = 0
var _running: bool = false
var _done: bool = false
var _victory_frame: int = -1

# Steering state
var _heading: float = 0.0           # world yaw the stick points at (radians, atan2(x, z))
var _drift: float = 0.0
var _reread: float = 0.0
var _push: float = 1.0
var _wander_left: float = 0.0
var _wander_dir: float = 0.0
var _wander_still: bool = false
# Mash state
var _burst_left: int = 0
var _mash_gap: float = 0.0
var _burst_rest: float = 0.0

# Stuck tracking
var _anchor: Vector3 = Vector3.INF
var _anchor_frame: int = 0
var _stuck: int = 0
var _stuck_idle: int = 0           # stuck with nothing to hit nearby (the bad kind)
var _stuck_spots: Array[String] = []

var _presses_attack: int = 0
var _presses_power: int = 0
var _presses_jump: int = 0
var _bubbles: int = 0
var _last_progress: String = ""
## --diag: from this frame on, scan every physics body for a non-finite
## transform or velocity and report the first one (debugging aid, slow).
var _diag_from: int = -1
var _diag_seen: Dictionary = {}
var _diag_prev: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chapter="):
			_chapter = arg.substr(10)
		elif arg.begins_with("--seed="):
			_seed = int(arg.substr(7))
		elif arg.begins_with("--minutes="):
			_cap_frames = int(float(arg.substr(10)) * 60.0 * FPS)
		elif arg.begins_with("--diag="):
			_diag_from = int(float(arg.substr(7)) * FPS)
		elif arg.begins_with("--log="):
			_log_every = maxi(1, int(float(arg.substr(6)) * FPS))
	_rng.seed = hash("kidbot:%s:%d" % [_chapter, _seed])
	# Make the game's own seeded randomness differ per kid too.
	seed(_seed * 7919 + 13)

	_main = MainScene.instantiate()
	add_child(_main)
	for i in 4:
		await get_tree().physics_frame
	# Assigned, not set through the setters: the setters persist to
	# user://settings.cfg, and a test run must not change the next run's defaults.
	GameManager.assists = true
	GameManager.companion = true
	GameManager.set_chapter(_chapter)
	GameManager.set_player_count(1)
	GameManager.set_human_hero(1)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.objective_changed.connect(_on_objective_changed)
	GameManager.objective_progress.connect(_on_objective_progress)
	GameManager.start_game()
	for i in 8:
		await get_tree().physics_frame
	var h := _hero(1)
	_heading = 0.0
	if h != null:
		_anchor = h.global_position
	_running = true
	print("kidbot: chapter=%s seed=%d cap=%.1f min, heroes=%s, ai2=%s"
		% [_chapter, _seed, _cap_frames / FPS / 60.0, str(_hero_ids()), str(GameManager.is_ai(2))])


func _physics_process(delta: float) -> void:
	if not _running or _done:
		return
	_frame += 1
	var h := _hero(1)
	if h == null:
		InputManager.set_virtual_move(1, Vector2.ZERO)
		return
	if _diag_from >= 0 and _frame >= _diag_from:
		_diag()
	_drive(h, delta)
	_track_stuck(h)
	if _frame % _log_every == 0:
		_log_line(h)
	if GameManager.state == GameManager.State.VICTORY and _victory_frame < 0:
		_victory_frame = _frame
	if _victory_frame >= 0 or _frame >= _cap_frames:
		_finish()


# --- The child ------------------------------------------------------------------

func _drive(h: PlayerBase, delta: float) -> void:
	var pos := h.global_position
	var goal := _goal(pos)
	var to_goal := _flat(goal - pos) if goal.is_finite() else Vector3.ZERO
	var near := _nearest_hittable(pos)
	var near_d := INF
	if near != null:
		near_d = _flat(near.global_position - pos).length()
	var mash_r := BOSS_MASH_RADIUS if near != null and near.is_in_group("boss") else MASH_RADIUS

	# Stop-and-wander spells.
	if _wander_left > 0.0:
		_wander_left -= delta
	elif _rng.randf() < WANDER_RATE * delta:
		_wander_left = _rng.randf_range(WANDER_MIN, WANDER_MAX)
		_wander_still = _rng.randf() < 0.5
		_wander_dir = _rng.randf_range(-PI, PI)

	# Steering: re-read the goal only now and then, over-steer, drift.
	_drift += (-_drift * DRIFT_PULL) * delta + _rng.randfn(0.0, DRIFT_SIGMA) * sqrt(delta)
	_reread -= delta
	if _reread <= 0.0:
		_reread = _rng.randf_range(REREAD_MIN, REREAD_MAX)
		if to_goal.length() > 0.05:
			var want := atan2(to_goal.x, to_goal.z)
			var err := wrapf(want - _heading, -PI, PI)
			_heading = wrapf(_heading + err * _rng.randf_range(OVERSTEER_MIN, OVERSTEER_MAX)
				+ _rng.randfn(0.0, JITTER), -PI, PI)
		else:
			_heading = wrapf(_heading + _rng.randfn(0.0, 1.0), -PI, PI)
		_push = _rng.randf_range(0.7, 1.0)

	var stick := Vector3.ZERO
	if _wander_left > 0.0:
		if not _wander_still:
			var a := _wander_dir + _drift
			stick = Vector3(sin(a), 0.0, cos(a)) * 0.9
	else:
		var a2 := _heading + _drift
		var push := _push
		if to_goal.length() < ARRIVE:
			push *= 0.35
		stick = Vector3(sin(a2), 0.0, cos(a2)) * push
	InputManager.set_virtual_move(1, _to_pad(stick))

	# Attack: bursts when something is near, sometimes at nothing.
	if _burst_left <= 0:
		_burst_rest -= delta
		if _burst_rest <= 0.0:
			var want_burst := near_d <= mash_r or _rng.randf() < IDLE_MASH_RATE * delta
			if want_burst:
				_burst_left = _rng.randi_range(BURST_MIN, BURST_MAX)
				_mash_gap = 0.0
	if _burst_left > 0:
		_mash_gap -= delta
		if _mash_gap <= 0.0:
			InputManager.press_virtual(1, &"attack")
			_presses_attack += 1
			_burst_left -= 1
			_mash_gap = _rng.randf_range(MASH_GAP_MIN, MASH_GAP_MAX)
			if _burst_left <= 0:
				_burst_rest = _rng.randf_range(BURST_REST_MIN, BURST_REST_MAX)

	if _rng.randf() < JUMP_RATE * delta:
		InputManager.press_virtual(1, &"jump")
		_presses_jump += 1
	if _rng.randf() < POWER_RATE * delta:
		InputManager.press_virtual(1, &"ability")
		_presses_power += 1


func _goal(from: Vector3) -> Vector3:
	var level := LevelBase.current(get_tree())
	if level != null:
		var p := level.hint_target()
		if p.is_finite():
			return p
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	if boss != null and is_instance_valid(boss):
		return boss.global_position
	if level != null:
		return level.camera_focus()
	return from


func _nearest_hittable(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for group in [&"targets", &"boss"]:
		for n in get_tree().get_nodes_in_group(group):
			var n3 := n as Node3D
			if n3 == null or not n3.is_visible_in_tree():
				continue
			var d := _flat(n3.global_position - from).length()
			if d < best_d:
				best = n3
				best_d = d
	return best


var _diag_snap: String = ""
var _diag_after: int = 0


func _diag_hero_snap(h: PlayerBase) -> String:
	var col := h.get_last_slide_collision()
	var cname := "none"
	if col != null and col.get_collider() != null:
		var c := col.get_collider() as Node
		cname = str(c.get_path()) if c != null else str(col.get_collider())
	return "pos=%s vel=%s plat_v=%s floor=%s floor_n=%s wall=%s collider=%s kb=%s" % [
		str(h.global_position), str(h.velocity), str(h.get_platform_velocity()), str(h.is_on_floor()),
		str(h.get_floor_normal()), str(h.is_on_wall()), cname, str(h.get("_knockback"))]


func _diag() -> void:
	var h1 := _hero(1)
	if h1 != null:
		var snap := _diag_hero_snap(h1)
		if not h1.global_transform.is_finite() and _diag_after < 4:
			if _diag_after == 0:
				print("kidbot: DIAG hero1 before: ", _diag_snap)
			print("kidbot: DIAG hero1 now(%d): %s" % [_diag_after, snap])
			_diag_after += 1
		_diag_snap = snap
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var b := n as Node3D
		if not b.is_inside_tree():
			continue
		var key := b.get_instance_id()
		var bad := not b.global_transform.is_finite()
		var v: Variant = b.get("velocity") if b is CharacterBody3D else (b.get("linear_velocity") if b is RigidBody3D else Vector3.ZERO)
		if v is Vector3 and not (v as Vector3).is_finite():
			bad = true
		if bad and not _diag_seen.has(key):
			_diag_seen[key] = true
			var scr: Script = b.get_script()
			print("kidbot: DIAG t=%s f=%d non-finite %s (%s) prev=%s vel=%s"
				% [_mmss(_frame), _frame, str(b.get_path()), scr.resource_path if scr else b.get_class(),
				str(_diag_prev.get(key, "?")), str(v)])
		elif not bad and (b is PhysicsBody3D):
			_diag_prev[key] = b.global_transform.origin


# --- Measuring --------------------------------------------------------------------

func _track_stuck(h: PlayerBase) -> void:
	var pos := h.global_position
	if not _anchor.is_finite() or pos.distance_to(_anchor) > 8.0:
		# A bubble home or a fresh spawn: start over from here.
		if _anchor.is_finite():
			_bubbles += 1
		_anchor = pos
		_anchor_frame = _frame
		return
	if pos.distance_to(_anchor) > STUCK_DIST:
		_anchor = pos
		_anchor_frame = _frame
		return
	if _frame - _anchor_frame >= int(STUCK_WINDOW * FPS):
		_stuck += 1
		var near := _nearest_hittable(pos)
		var idle := near == null or _flat(near.global_position - pos).length() > MASH_RADIUS + 1.0
		if idle:
			_stuck_idle += 1
		var spot := "%.1f@(%.1f,%.1f,%.1f)%s" % [_frame / FPS / 60.0, pos.x, pos.y, pos.z, "" if not idle else "!"]
		_stuck_spots.append(spot)
		print("kidbot: STUCK t=%s obj=%s" % [_mmss(_frame), _progress()])
		_anchor = pos
		_anchor_frame = _frame


func _on_state_changed(s: int) -> void:
	if s == GameManager.State.VICTORY and _victory_frame < 0:
		_victory_frame = _frame
		print("kidbot: VICTORY t=%s" % _mmss(_frame))
	elif s == GameManager.State.DEFEAT:
		print("kidbot: DEFEAT t=%s (must never happen with Ajudas)" % _mmss(_frame))


func _on_objective_changed(label: Dictionary, done: int, total: int) -> void:
	print("kidbot: t=%s objective '%s' %d/%d" % [_mmss(_frame), str(label.get("en", "")), done, total])


func _on_objective_progress(done: int, total: int) -> void:
	print("kidbot: t=%s progress %d/%d" % [_mmss(_frame), done, total])


func _progress() -> String:
	var s := "%d/%d" % [GameManager.objective_done(), GameManager.objective_total()]
	if get_tree().get_first_node_in_group("boss") != null:
		s += " boss_hp=%d" % int(GameManager.boss_health)
	return s


func _log_line(h: PlayerBase) -> void:
	var p := h.global_position
	print("kidbot: t=%s obj=%s pos=(%.1f,%.1f,%.1f) atk=%d pow=%d stuck=%d"
		% [_mmss(_frame), _progress(), p.x, p.y, p.z, _presses_attack, _presses_power, _stuck])
	if _diag_from >= 0:
		var cam := get_viewport().get_camera_3d()
		print("kidbot: DIAG cam=%s goal=%s wander=%.1f" % [str(-cam.global_basis.z) if cam else "none", str(_goal(p)), _wander_left])
		print("kidbot: DIAG state downed=%s bubbled=%s wish=%s move=%s %s" % [str(h.get("_downed")), str(h.get("_bubbled")),
			str(h.get("_wish_dir")), str(InputManager.get_move_vector(1)), _diag_hero_snap(h)])


func _finish() -> void:
	_done = true
	InputManager.set_virtual_move(1, Vector2.ZERO)
	var completed := _victory_frame >= 0
	var frames := _victory_frame if completed else _frame
	var minutes := frames / FPS / 60.0
	print("kidbot: stuck spots (min@pos, ! = nothing to hit nearby): %s" % ", ".join(_stuck_spots))
	print("kidbot: presses attack=%d power=%d jump=%d, bubbles=%d, companion presses=%s"
		% [_presses_attack, _presses_power, _presses_jump, _bubbles, str(_companion_presses())])
	print("KIDBOT chapter=%s seed=%d completed=%d minutes=%.2f stuck=%d stuck_idle=%d obj=%s"
		% [_chapter, _seed, 1 if completed else 0, minutes, _stuck, _stuck_idle, _progress()])
	get_tree().quit(0 if completed else 1)


func _companion_presses() -> int:
	var ai := _main.get_node_or_null("World/CompanionAI2") if _main != null else null
	return int(ai.presses) if ai != null else -1


# --- Helpers ----------------------------------------------------------------------

func _to_pad(world: Vector3) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var fwd := Vector3.FORWARD
	if cam:
		# Same heading rule as PlayerBase._camera_forward: a camera aimed straight
		# down steers by its up vector, so the stick never maps to nothing.
		fwd = -cam.global_basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.0001:
			fwd = cam.global_basis.y
			fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() >= 0.0001 else Vector3.FORWARD
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	return Vector2(world.dot(right), world.dot(fwd)).limit_length(1.0)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _mmss(frame: int) -> String:
	var s := int(frame / FPS)
	return "%d:%02d" % [s / 60, s % 60]


func _hero(id: int) -> PlayerBase:
	for p in get_tree().get_nodes_in_group("players"):
		if p is PlayerBase and int(p.player_id) == id:
			return p as PlayerBase
	return null


func _hero_ids() -> Array[int]:
	var out: Array[int] = []
	for p in get_tree().get_nodes_in_group("players"):
		out.append(int(p.player_id))
	out.sort()
	return out
