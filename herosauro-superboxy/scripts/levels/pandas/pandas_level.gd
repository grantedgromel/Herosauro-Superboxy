extends LevelBase
## Chapter 3, "Os Turistas Panda": the gentle, creative chapter. No enemies.
##
## Every hotel in Porto is full, so the heroes bring a panda family to an old,
## forgotten street. Stage 1: clear each house's rubbish and hit its magic door
## star until the house turns into a bright, tiled, flowery home (8 houses; the
## light warms and the lamps come on as they do). Stage 2: find the pandas' four
## suitcases. Finale: string lights unfurl, the fountain sprays, the pandas wave
## and walk into the prettiest house, and the chapter is won.
##
## Built once in _ready (pandas_square.gd for the set, house.gd for the houses);
## begin() resets everything, so PLAY AGAIN reuses the level. Progress goes out
## ONLY through GameManager.set_objective / advance_objective /
## request_story_beat / complete_chapter.
##
## The camera: the co-op rig yaws to look from the heroes toward
## camera_focus(). This square is ringed by tall houses, so a fixed focus would
## put the camera inside whichever facade the heroes stand in front of. Instead
## the focus is anchored on the fountain and leans toward the thing the heroes
## should look at (the nearest unfinished house, suitcase, or the finale door),
## so the camera always stands in the open square looking at the action. See
## `_update_aim`.

const Kit := preload("res://scripts/levels/pandas/pandas_kit.gd")
const Square := preload("res://scripts/levels/pandas/pandas_square.gd")
const House := preload("res://scripts/levels/pandas/house.gd")
const Panda := preload("res://scripts/levels/pandas/panda.gd")
const Suitcase := preload("res://scripts/levels/pandas/suitcase.gd")
const RubbishPile := preload("res://scripts/levels/pandas/rubbish_pile.gd")
const MagicFX := preload("res://scripts/levels/pandas/magic_fx.gd")

const OBJECTIVE_HOUSES := {"pt": "Repara as casas!", "en": "Fix up the houses!"}
const OBJECTIVE_CASES := {"pt": "Encontra as malas dos pandas!", "en": "Find the pandas' suitcases!"}

enum Stage { HOUSES, CASES, FINALE, DONE }

const FOUNTAIN := Square.FOUNTAIN
const SPAWNS := {1: Vector3(12.5, 1.2, -1.6), 2: Vector3(12.5, 1.2, 1.6)}
## Where the panda family stands when the run starts (on the terrace).
const PANDA_STARTS: Array[Vector3] = [Vector3(15.2, 0.0, -3.0), Vector3(15.6, 0.0, -1.7),
	Vector3(14.6, 0.0, 3.1), Vector3(15.4, 0.0, 2.2)]
## Formation offsets (across, along the camera aim), metres.
const FORMATION: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.45), Vector2(-0.5, -0.9), Vector2(0.7, -1.2)]
const BOUNDS_MIN := Vector2(-16.6, -11.2)
const BOUNDS_MAX := Vector2(18.8, 11.2)
const HERO_SPACE := 1.9
const STAGE2_DELAY := 2.6
## How fast the camera's aim may swing, radians per second.
const AIM_TURN_RATE := 1.7
const PRETTIEST := 1
const CASE_TINTS: Array[Color] = [Color(0.25, 0.5, 0.95), Color(0.95, 0.35, 0.5), Color(0.3, 0.75, 0.35), Color(1.0, 0.8, 0.2)]
## Lamp i comes on once this many houses are fixed (all of them at the finale).
const LAMP_ON_AT: Array[int] = [2, 3, 4, 5, 6, 7, 1, 8]

## The eight houses: north row west to east, then south row west to east.
const HOUSES := [
	{"row": -1, "w": 6.4, "f": 4, "paint": Color(0.8, 0.68, 0.94), "sh": Color(0.25, 0.42, 0.8), "door": Color(0.95, 0.85, 0.3), "ts": 0, "tl": 1, "ds": -1.0},
	{"row": -1, "w": 6.2, "f": 4, "paint": Color(1.0, 0.7, 0.72), "sh": Color(0.98, 0.98, 0.95), "door": Color(0.2, 0.45, 0.85), "ts": 0, "tl": 2, "ds": 1.0},
	{"row": -1, "w": 6.6, "f": 3, "paint": Color(1.0, 0.82, 0.38), "sh": Color(0.18, 0.52, 0.44), "door": Color(0.75, 0.22, 0.2), "ts": 2, "tl": 0, "ds": -1.0},
	{"row": -1, "w": 6.2, "f": 3, "paint": Color(0.62, 0.88, 0.7), "sh": Color(0.95, 0.5, 0.3), "door": Color(0.2, 0.35, 0.65), "ts": 1, "tl": 1, "ds": 1.0},
	{"row": 1, "w": 6.6, "f": 3, "paint": Color(0.6, 0.78, 0.98), "sh": Color(0.98, 0.95, 0.85), "door": Color(0.85, 0.3, 0.25), "ts": 0, "tl": 0, "ds": 1.0},
	{"row": 1, "w": 6.4, "f": 4, "paint": Color(0.98, 0.6, 0.36), "sh": Color(0.2, 0.5, 0.36), "door": Color(0.25, 0.3, 0.6), "ts": 1, "tl": 1, "ds": -1.0},
	{"row": 1, "w": 6.4, "f": 3, "paint": Color(1.0, 0.93, 0.62), "sh": Color(0.3, 0.45, 0.85), "door": Color(0.2, 0.55, 0.4), "ts": 0, "tl": 1, "ds": 1.0},
	{"row": 1, "w": 6.2, "f": 4, "paint": Color(0.95, 0.48, 0.45), "sh": Color(0.98, 0.95, 0.88), "door": Color(0.2, 0.3, 0.55), "ts": 2, "tl": 0, "ds": -1.0},
]
## The house whose heap is tiny (the first one the kids reach), and the one with
## the low balcony a suitcase waits on.
const FIRST_HOUSE := 3
const BALCONY_HOUSE := 5

var build_ms: float = 0.0
var houses: Array[Node3D] = []
var pandas: Array[Node3D] = []
var suitcases: Array[Node3D] = []
var last_pile: Node3D

var _stage: int = Stage.HOUSES
var _houses_done: int = 0
var _cases_done: int = 0
var _stage2_timer: float = -1.0
var _finale_t: float = -1.0
var _entered: int = 0
var _beat_half: bool = false
var _heroes: Array[Node3D] = []
var _hero_pos := PackedVector3Array()
var _human: Node3D = null
var _centroid := Vector3.ZERO
var _aim_dir := Vector3(-0.6, 0.0, -0.8)
var _side_sign: float = 1.0
var _avoid := PackedVector4Array()   # x, z, radius, active (1/0)
var _avoid_static: int = 0
var _t: float = 0.0

# Mood: 0 = golden afternoon, 1 = warm evening.
var _mood: float = 0.0
var _mood_target: float = 0.0
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _pools: Array[OmniLight3D] = []
var _globes: MultiMeshInstance3D
var _twinkles: MultiMeshInstance3D
var _bulbs: MultiMeshInstance3D
var _flags: MultiMeshInstance3D
var _strand_count: int = 0
var _water: MeshInstance3D
var _jet: Node3D
var _drops: MultiMeshInstance3D
var _water_on: float = 0.0
var _lamps: Array = []


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	_build_environment()
	var info := Square.build(self)
	_lamps = info["lamps"]
	_build_houses()
	last_pile = RubbishPile.new()
	last_pile.name = "LastRubbish"
	last_pile.size = 2
	last_pile.rng_seed = 99
	last_pile.position = Vector3(17.0, 0.0, -10.2)
	add_child(last_pile)
	_build_pandas()
	_build_suitcases()
	_build_lights()
	_build_fountain_water()
	_build_avoid()
	var c: Vector3 = (SPAWNS[1] + SPAWNS[2]) * 0.5
	_centroid = _flat(to_global(c))
	_aim_dir = _flat(houses[FIRST_HOUSE].work_point() - _centroid).normalized()
	_apply_mood()
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	print("[pandas] level built in %.0f ms" % build_ms)


# --- LevelBase ----------------------------------------------------------------------

func spawn_point(player_id: int) -> Vector3:
	return to_global(SPAWNS.get(player_id, SPAWNS[1]))


## The fountain is the anchor; the point leans toward what the heroes should be
## looking at, so the camera stays in the open square (see the header).
func camera_focus() -> Vector3:
	return _centroid + _aim_dir * 30.0


func kill_y() -> float:
	return global_position.y - 8.0


func ground_surface() -> int:
	return ToonFactory.Surface.COBBLE


func music_track() -> String:
	return "title"


func begin() -> void:
	_stage = Stage.HOUSES
	_houses_done = 0
	_cases_done = 0
	_stage2_timer = -1.0
	_finale_t = -1.0
	_entered = 0
	_beat_half = false
	for h in houses:
		h.reset()
	last_pile.reset()
	for i in pandas.size():
		pandas[i].reset_to(PANDA_STARTS[i], -PI * 0.5)
	for s in suitcases:
		s.reset()
	_mood = 0.0
	_mood_target = 0.0
	_water_on = 0.0
	_bulbs.multimesh.visible_instance_count = 0
	_flags.multimesh.visible_instance_count = 0
	_water.visible = false
	_jet.visible = false
	_drops.visible = false
	_apply_mood()
	_cache_heroes()
	_centroid = _flat(_hero_centroid())
	_aim_dir = _flat(houses[FIRST_HOUSE].work_point() - _centroid).normalized()
	GameManager.set_objective(OBJECTIVE_HOUSES, houses.size())


func hint_target() -> Vector3:
	var from := _human.global_position if _human != null and is_instance_valid(_human) else _centroid
	var p := _focus_point(from)
	if not p.is_finite():
		return Vector3.INF
	return p + Vector3.UP * (2.6 if _stage == Stage.HOUSES else 1.4)


# --- Objective flow --------------------------------------------------------------------

func _on_house_repaired(house: Node3D) -> void:
	if _stage != Stage.HOUSES:
		return
	_houses_done += 1
	GameManager.advance_objective(1)
	_mood_target = float(_houses_done) / float(houses.size())
	for i in pandas.size():
		pandas[i].cheer(0.35 + 0.12 * float(i))
	AudioManager.play_sfx(&"panda_cheer", house.global_position)
	if _houses_done * 2 >= houses.size() and not _beat_half:
		_beat_half = true
		GameManager.request_story_beat("p08")
	if _houses_done >= houses.size():
		_stage2_timer = STAGE2_DELAY


func _start_cases() -> void:
	_stage = Stage.CASES
	GameManager.set_objective(OBJECTIVE_CASES, suitcases.size())
	for i in suitcases.size():
		suitcases[i].appear(0.3 + 0.45 * float(i))
	AudioManager.play_sfx(&"star")


func _on_case_collected(_case: Node3D) -> void:
	if _stage != Stage.CASES:
		return
	_cases_done += 1
	GameManager.advance_objective(1)
	if _cases_done >= suitcases.size():
		_start_finale()


func _start_finale() -> void:
	_stage = Stage.FINALE
	_finale_t = 0.0
	_mood_target = 1.25
	_water.visible = true
	_jet.visible = true
	_drops.visible = true
	AudioManager.play_sfx(&"magic_repair", to_global(FOUNTAIN))
	AudioManager.play_sfx(&"objective_done")
	MagicFX.burst(self, to_global(FOUNTAIN + Vector3.UP * 3.0), Color(0.5, 1.0, 0.5), 36, 7.0, 777, 0.24)
	for i in pandas.size():
		pandas[i].cheer(0.2 * float(i))


func _tick_finale(delta: float) -> void:
	_finale_t += delta
	var n := _bulbs.multimesh.instance_count
	var k := clampf(_finale_t / 2.4, 0.0, 1.0)
	_bulbs.multimesh.visible_instance_count = int(round(k * float(n)))
	_flags.multimesh.visible_instance_count = int(round(k * float(_flags.multimesh.instance_count)))
	_water_on = clampf(_finale_t / 1.6, 0.0, 1.0)
	var house: Node3D = houses[PRETTIEST]
	var door: Vector3 = house.door_point()
	var out: Vector3 = house.global_basis.z
	if _finale_t > 2.2 and _finale_t - delta <= 2.2:
		house.open_door(true)
		for p in pandas:
			p.wave(true)
	if _finale_t > 2.2:
		for i in pandas.size():
			var across := house.global_basis.x * (float(i) - 1.5) * 0.95
			pandas[i].goal = door + out * (2.2 + 0.4 * float(i % 2)) + across
			pandas[i].interest = _centroid
	# One by one, in through the door.
	var enter_at := 5.0 + 0.7 * float(_entered)
	if _entered < pandas.size() and _finale_t >= enter_at:
		pandas[_entered].wave(false)
		pandas[_entered].enter(door - out * 0.8)
		if _entered == 0:
			AudioManager.play_sfx(&"panda_cheer", door)
		_entered += 1
	if _finale_t > 5.0 + 0.7 * float(pandas.size()) + 1.4 and _finale_t - delta <= 5.0 + 0.7 * float(pandas.size()) + 1.4:
		house.open_door(false)
		MagicFX.burst(self, door + Vector3.UP * 3.0 + out * 0.6, Color(1.0, 0.85, 0.4), 30, 5.0, 4242, 0.2)
	# Hold ~3 s on the happy house, then the chapter is won.
	if _finale_t >= 5.0 + 0.7 * float(pandas.size()) + 3.2:
		_stage = Stage.DONE
		GameManager.complete_chapter()


# --- Per frame -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	if GameManager.state != GameManager.State.PLAYING and _stage != Stage.DONE:
		_tick_lights(delta)
		return
	_refresh_hero_positions()
	_update_aim(delta)
	_update_avoid()
	_update_pandas()
	if _stage2_timer >= 0.0:
		_stage2_timer -= delta
		if _stage2_timer < 0.0:
			_stage2_timer = -1.0
			_start_cases()
	if _stage == Stage.FINALE:
		_tick_finale(delta)
	if absf(_mood - _mood_target) > 0.0005:
		_mood = move_toward(_mood, _mood_target, delta * 0.4)
		_apply_mood()
	_tick_lights(delta)


## The thing the heroes should be looking at now, or INF.
func _focus_point(from: Vector3) -> Vector3:
	match _stage:
		Stage.HOUSES:
			var best := Vector3.INF
			var best_d := INF
			for h in houses:
				if h.is_repaired():
					continue
				var p: Vector3 = h.work_point()
				var d := _flat(p - from).length()
				if d < best_d:
					best_d = d
					best = p
			return best
		Stage.CASES:
			var best := Vector3.INF
			var best_d := INF
			for s in suitcases:
				if s.is_collected():
					continue
				var d := _flat(s.global_position - from).length()
				if d < best_d:
					best_d = d
					best = s.global_position
			if not best.is_finite() and _stage2_timer < 0.0:
				return to_global(FOUNTAIN)
			return best
		Stage.FINALE:
			return houses[PRETTIEST].door_point()
	return Vector3.INF


func _update_aim(delta: float) -> void:
	var c := _centroid
	var target := _focus_point(c)
	if _stage == Stage.HOUSES and _stage2_timer >= 0.0:
		target = to_global(FOUNTAIN)
	var want := Vector3.ZERO
	if target.is_finite():
		var to := _flat(target - c)
		if to.length() > 0.6:
			want = to.normalized() * clampf(to.length() / 4.0, 0.35, 1.0)
	var out := _flat(c - to_global(FOUNTAIN))
	var ol := out.length()
	if ol > 0.5:
		var on := out / ol
		var w := 0.45 * clampf(ol / 7.0, 0.0, 1.0)
		if want.length() > 0.01:
			w *= clampf(on.dot(want.normalized()) + 0.5, 0.0, 1.0)
		want += on * w
	if want.length() < 0.05:
		return
	want = want.normalized()
	# The camera stands `d` behind the heroes along -aim. Pick the aim closest to
	# what we want whose whole arm stays in the open (never inside a row of
	# houses or the chapel), then turn toward it along a path that is open too.
	var d := _cam_distance()
	var best := want
	if not _arm_clear(c, want, d):
		best = _aim_dir if _arm_clear(c, _aim_dir, d) else want
		for step in range(1, 19):
			var a := want.rotated(Vector3.UP, deg_to_rad(10.0 * float(step)))
			var b := want.rotated(Vector3.UP, -deg_to_rad(10.0 * float(step)))
			var ok_a := _arm_clear(c, a, d)
			var ok_b := _arm_clear(c, b, d)
			if ok_a and ok_b:
				best = a if a.dot(_aim_dir) >= b.dot(_aim_dir) else b
				break
			if ok_a or ok_b:
				best = a if ok_a else b
				break
	var ang := _aim_dir.signed_angle_to(best, Vector3.UP)
	var max_step := AIM_TURN_RATE * delta
	var turn := clampf(ang * clampf(3.0 * delta, 0.0, 1.0) * 3.0, -max_step, max_step)
	if absf(turn) > absf(ang):
		turn = ang
	var nd := _aim_dir.rotated(Vector3.UP, turn)
	if not _arm_clear(c, nd, d) and _arm_clear(c, _aim_dir.rotated(Vector3.UP, -signf(ang) * max_step), d):
		nd = _aim_dir.rotated(Vector3.UP, -signf(ang) * max_step)
	_aim_dir = _flat(nd).normalized()


## The spring arm's length right now (flat), padded; 14 m before a camera exists.
func _cam_distance() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 14.0
	return clampf(_flat(cam.global_position - _centroid).length() + 1.5, 9.0, 17.5)


## True if a camera anywhere on the arm from `c` back along -aim to `d` stands
## in the open: inside the square, over the terrace, or out over the river.
func _arm_clear(c: Vector3, aim: Vector3, d: float) -> bool:
	for k in 4:
		var p := c - aim * (d * float(k + 1) / 4.0)
		var local := to_local(p)
		if local.x < Square.ROW_X0 + 1.0:
			return false
		if absf(local.z) > Square.ROW_Z - 2.6 and local.x < Square.ROW_X1 + 1.5:
			return false
	return true


func _cache_heroes() -> void:
	_heroes.clear()
	_human = null
	for n in get_tree().get_nodes_in_group("players"):
		if n is Node3D:
			_heroes.append(n as Node3D)
			var pid := int(n.get("player_id")) if n.get("player_id") != null else 1
			if _human == null and not GameManager.is_ai(pid):
				_human = n as Node3D
	_hero_pos.resize(_heroes.size())
	_refresh_hero_positions()


func _refresh_hero_positions() -> void:
	for i in _heroes.size():
		var h := _heroes[i]
		if is_instance_valid(h):
			_hero_pos[i] = h.global_position
	_centroid = _flat(_hero_centroid())


func _hero_centroid() -> Vector3:
	if _hero_pos.is_empty():
		return to_global((SPAWNS[1] + SPAWNS[2]) * 0.5)
	var s := Vector3.ZERO
	for p in _hero_pos:
		s += p
	return s / float(_hero_pos.size())


# --- Pandas ---------------------------------------------------------------------------

func _update_pandas() -> void:
	if _stage == Stage.FINALE or _stage == Stage.DONE:
		return
	var side := Vector3(-_aim_dir.z, 0.0, _aim_dir.x)
	var mid := Vector3((BOUNDS_MIN.x + BOUNDS_MAX.x) * 0.5, 0.0, 0.0)
	var to_mid := mid - _centroid
	if side.dot(to_mid) * _side_sign < -3.0:
		_side_sign = -_side_sign
	side *= _side_sign
	var anchor := _centroid + _aim_dir * 0.6 + side * 3.4
	anchor = panda_clamp(anchor)
	var interest := _centroid + Vector3.UP * 1.0
	var focus := _focus_point(_centroid)
	if focus.is_finite() and _flat(focus - _centroid).length() < 6.0:
		interest = focus + Vector3.UP * 1.5
	for i in pandas.size():
		var p: Node3D = pandas[i]
		var f := FORMATION[i]
		var g := panda_clamp(anchor + side * f.x + _aim_dir * f.y)
		if _flat(g - p.goal).length() > 1.4 or _flat(p.goal - p.position).length() < 0.4 and _flat(g - p.goal).length() > 0.6:
			p.goal = g
		p.interest = interest


## Steering for a panda at `pos` that wants velocity `want`: keep clear of the
## heroes (never block them), the fountain, uncleared heaps, benches and lamps.
func panda_steer(pos: Vector3, want: Vector3) -> Vector3:
	var v := want
	for i in _hero_pos.size():
		var d := _flat(pos - _hero_pos[i])
		var l := d.length()
		if l < HERO_SPACE and l > 0.001:
			v += d / l * (HERO_SPACE - l) * 4.0
	for a in _avoid:
		if a.w < 0.5:
			continue
		var d := Vector3(pos.x - a.x, 0.0, pos.z - a.y)
		var l := d.length()
		var r := a.z
		if l < r and l > 0.001:
			v += d / l * (r - l) * 5.0
	return v


func panda_clamp(p: Vector3) -> Vector3:
	var q := Vector3(clampf(p.x, BOUNDS_MIN.x, BOUNDS_MAX.x), 0.0, clampf(p.z, BOUNDS_MIN.y, BOUNDS_MAX.y))
	var d := Vector3(q.x - FOUNTAIN.x, 0.0, q.z - FOUNTAIN.z)
	var r := Square.FOUNTAIN_R + 0.7
	if d.length() < r:
		q = Vector3(FOUNTAIN.x, 0.0, FOUNTAIN.z) + (d.normalized() if d.length() > 0.01 else Vector3.BACK) * r
	return q


func _build_avoid() -> void:
	_avoid.clear()
	for b in Square.BENCHES:
		_avoid.append(Vector4(b.x, b.z, 1.4, 1.0))
	for l in Square.LAMPS:
		_avoid.append(Vector4(l.x, l.z, 0.7, 1.0))
	for p in Square.PLANTERS:
		_avoid.append(Vector4(p.x, p.z, 1.2, 1.0))
	_avoid_static = _avoid.size()
	for h in houses:
		_avoid.append(Vector4(h.pile.global_position.x, h.pile.global_position.z, 1.7, 1.0))
	_avoid.append(Vector4(last_pile.global_position.x, last_pile.global_position.z, 2.0, 1.0))


func _update_avoid() -> void:
	for i in houses.size():
		var a := _avoid[_avoid_static + i]
		a.w = 0.0 if houses[i].pile.is_cleared() else 1.0
		_avoid[_avoid_static + i] = a
	var la := _avoid[_avoid_static + houses.size()]
	la.w = 0.0 if last_pile.is_cleared() else 1.0
	_avoid[_avoid_static + houses.size()] = la


# --- Mood, lamps, twinkles, string lights, fountain -----------------------------------

func _apply_mood() -> void:
	var m := clampf(_mood, 0.0, 1.25)
	var e := clampf(m, 0.0, 1.0)
	var elev := deg_to_rad(lerpf(34.0, 13.0, clampf(m / 1.25, 0.0, 1.0)))
	var az := 0.32
	var sun_dir := Vector3(cos(elev) * cos(az), sin(elev), cos(elev) * sin(az))
	_sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	_sun.light_color = Color(1.0, 0.9, 0.74).lerp(Color(1.0, 0.64, 0.4), e)
	_sun.light_energy = lerpf(1.05, 0.9, e)
	_fill.light_color = Color(0.78, 0.84, 1.0).lerp(Color(0.98, 0.7, 0.75), e)
	_fill.light_energy = lerpf(0.3, 0.36, e)
	_env.ambient_light_color = Color(0.7, 0.74, 0.86).lerp(Color(0.86, 0.68, 0.72), e)
	_env.ambient_light_energy = lerpf(0.42, 0.46, e)
	_sky_mat.sky_top_color = Color(0.32, 0.55, 0.88).lerp(Color(0.36, 0.36, 0.7), e)
	_sky_mat.sky_horizon_color = Color(0.98, 0.84, 0.64).lerp(Color(1.0, 0.6, 0.46), e)
	_sky_mat.ground_horizon_color = Color(0.85, 0.75, 0.62).lerp(Color(0.85, 0.55, 0.45), e)
	_env.fog_light_color = Color(0.95, 0.85, 0.72).lerp(Color(0.95, 0.66, 0.58), e)
	Kit.window_glow().emission_energy_multiplier = lerpf(0.55, 1.35, e)
	for i in _pools.size():
		_pools[i].light_energy = 1.6 * clampf((m - 0.35) / 0.65, 0.0, 1.0)


func _tick_lights(delta: float) -> void:
	# Lamp globes: off is a pale glass, on is warm and bright.
	var mm := _globes.multimesh
	for i in mm.instance_count:
		var on := _houses_done >= LAMP_ON_AT[i] or _stage == Stage.FINALE or _stage == Stage.DONE
		var c := Color(1.0, 0.86, 0.5) if on else Color(0.72, 0.72, 0.68)
		if mm.get_instance_color(i) != c:
			mm.set_instance_color(i, c)
	# Twinkles over every repaired house.
	var tw := _twinkles.multimesh
	for hi in houses.size():
		var h: Node3D = houses[hi]
		var fixed: bool = h.is_repaired()
		for k in 3:
			var idx := hi * 3 + k
			if not fixed:
				tw.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO))
				continue
			var phase := _t * 2.2 + float(idx) * 1.37
			var s := maxf(0.0, sin(phase)) * 0.28
			var p: Vector3 = h.get_meta("twinkle_%d" % k, Vector3.ZERO)
			tw.set_instance_transform(idx, Transform3D(Basis(Vector3.UP, phase).scaled(Vector3.ONE * maxf(s, 0.0001)), p))
	# String lights twinkle once unfurled.
	if _bulbs.multimesh.visible_instance_count > 0:
		var bm := _bulbs.multimesh
		for i in bm.visible_instance_count:
			var base: Color = bm.get_instance_custom_data(i)
			var f := 0.82 + 0.18 * sin(_t * 4.0 + float(i) * 0.9)
			bm.set_instance_color(i, Color(base.r * f, base.g * f, base.b * f))
	_tick_fountain(delta)


func _tick_fountain(_delta: float) -> void:
	if _water_on <= 0.0:
		return
	_water.scale = Vector3(1.0, maxf(0.01, _water_on), 1.0)
	var j := _water_on * (1.0 + 0.06 * sin(_t * 11.0))
	_jet.scale = Vector3(1.0 + 0.1 * sin(_t * 7.0), maxf(0.01, j), 1.0 + 0.1 * cos(_t * 6.0))
	var mm := _drops.multimesh
	var arcs := 8
	var per := mm.instance_count / arcs
	for a in arcs:
		var ang := TAU * float(a) / float(arcs)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		for k in per:
			var i := a * per + k
			var s := fposmod(_t * 0.9 + float(k) / float(per) + float(a) * 0.13, 1.0)
			var start := FOUNTAIN + dir * 1.15 + Vector3.UP * 1.72
			var p := start + dir * (1.35 * s) + Vector3.UP * (1.1 * s - 2.4 * s * s) * 1.0
			var sz := 0.9 * _water_on * (1.0 - 0.4 * s)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * maxf(sz, 0.0001)), p))


# --- Build --------------------------------------------------------------------------------

func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_curve = 0.12
	_sky_mat.ground_bottom_color = Color(0.3, 0.34, 0.36)
	_sky_mat.sun_angle_max = 12.0
	_sky_mat.sun_curve = 0.08
	sky.sky_material = _sky_mat
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 5.0
	_env.fog_enabled = true
	_env.fog_density = 0.0028
	_env.fog_sky_affect = 0.0
	_env.fog_sun_scatter = 0.15
	_env.glow_enabled = true
	_env.glow_intensity = 0.3
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.12
	_env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 55.0
	_sun.shadow_blur = 1.2
	_sun.light_angular_distance = 0.6
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.name = "Fill"
	_fill.shadow_enabled = false
	_fill.light_specular = 0.2
	_fill.basis = Basis.looking_at(Vector3(0.25, -0.45, 0.86).normalized(), Vector3.UP)
	add_child(_fill)
	for p: Vector3 in [FOUNTAIN + Vector3(0.0, 4.0, 0.0), Vector3(13.0, 4.0, 0.0)]:
		var o := OmniLight3D.new()
		o.name = "WarmPool"
		o.light_color = Color(1.0, 0.75, 0.45)
		o.omni_range = 14.0
		o.omni_attenuation = 1.4
		o.shadow_enabled = false
		o.light_energy = 0.0
		o.position = p
		add_child(o)
		_pools.append(o)


func _build_houses() -> void:
	var cursor := {-1: Square.ROW_X0, 1: Square.ROW_X0}
	for i in HOUSES.size():
		var cfg: Dictionary = HOUSES[i]
		var row: int = cfg["row"]
		var w: float = cfg["w"]
		var cx: float = cursor[row] + w * 0.5
		cursor[row] = cursor[row] + w
		var h: Node3D = House.new()
		h.name = "House%d" % i
		h.index = i
		h.width = w
		h.floors = cfg["f"]
		h.paint = cfg["paint"]
		h.shutter_paint = cfg["sh"]
		h.door_paint = cfg["door"]
		h.tile_style = cfg["ts"]
		h.tile_layout = cfg["tl"]
		h.pile_size = 0 if i == FIRST_HOUSE else 1
		h.door_side = cfg["ds"]
		h.low_balcony = i == BALCONY_HOUSE
		h.has_door_leaf = i == PRETTIEST
		h.rng_seed = 101 + i * 17
		if row < 0:
			h.position = Vector3(cx, 0.0, -Square.ROW_Z)
		else:
			# The south row faces -Z; its local +X runs toward -X.
			h.position = Vector3(cx, 0.0, Square.ROW_Z)
			h.rotation.y = PI
		add_child(h)
		h.repaired.connect(_on_house_repaired)
		var pts: Array[Vector3] = h.twinkle_points()
		for k in pts.size():
			h.set_meta("twinkle_%d" % k, pts[k])
		houses.append(h)


func _build_pandas() -> void:
	for i in 4:
		var p: Node3D = Panda.new()
		p.name = ["PaiPanda", "MaePanda", "Menino", "Menina"][i]
		p.kind = i
		p.level = self
		p.position = PANDA_STARTS[i]
		add_child(p)
		pandas.append(p)


func _build_suitcases() -> void:
	var spots: Array[Vector3] = [
		FOUNTAIN + Vector3(-4.3, 0.0, -0.8),                 # behind the fountain
		houses[BALCONY_HOUSE].balcony_spot() - global_position, # on the low balcony
		Square.BENCHES[0] + Vector3(0.0, 0.52, 0.0),          # on the terrace bench
		last_pile.position + Vector3(-1.5, 0.0, 0.9),         # among the last rubbish
	]
	for i in 4:
		var s: Node3D = Suitcase.new()
		s.name = "Mala%d" % i
		s.tint = CASE_TINTS[i]
		s.panda = pandas[i]
		s.rng_seed = 500 + i * 11
		s.position = spots[i]
		add_child(s)
		s.collected.connect(_on_case_collected)
		suitcases.append(s)


func _build_lights() -> void:
	# Lamp globes: one MultiMesh, coloured per lamp.
	_globes = Kit.multimesh(Kit.bulb_mesh(), _lamps.size(), Kit.unshaded(),
		AABB(Vector3(-25.0, 0.0, -20.0), Vector3(50.0, 8.0, 40.0)), "LampGlobes")
	for i in _lamps.size():
		var p: Vector3 = _lamps[i]
		_globes.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.6, 1.9, 1.6)),
			p + Vector3.UP * Square.LAMP_GLOBE_Y))
		_globes.multimesh.set_instance_color(i, Color(0.72, 0.72, 0.68))
	add_child(_globes)
	_twinkles = Kit.multimesh(Kit.sparkle_mesh(), houses.size() * 3, Kit.unshaded(),
		AABB(Vector3(-25.0, 0.0, -20.0), Vector3(50.0, 20.0, 40.0)), "Twinkles")
	for i in houses.size() * 3:
		_twinkles.multimesh.set_instance_color(i, Color(1.0, 0.96, 0.75))
	add_child(_twinkles)
	# String lights and São João bunting across the street, revealed at the finale.
	var strands := [[Vector3(-14.0, 6.6, -13.3), Vector3(-11.0, 6.4, 13.3)],
		[Vector3(-6.0, 6.8, -13.3), Vector3(-2.0, 6.6, 13.3)],
		[Vector3(2.5, 6.4, -13.3), Vector3(5.5, 6.6, 13.3)],
		[Vector3(-17.6, 7.0, -8.0), Vector3(7.2, 6.8, 8.0)]]
	var per := 18
	_strand_count = strands.size()
	var bulb_cols := [Color(1.0, 0.85, 0.35), Color(1.0, 0.4, 0.4), Color(0.45, 0.85, 1.0),
		Color(0.5, 1.0, 0.5), Color(1.0, 0.6, 0.9)]
	var flag_cols := [Color(0.95, 0.25, 0.3), Color(1.0, 0.8, 0.2), Color(0.25, 0.55, 0.95),
		Color(0.3, 0.75, 0.4), Color(1.0, 1.0, 0.95), Color(0.9, 0.4, 0.85)]
	_bulbs = Kit.multimesh(Kit.bulb_mesh(), per * strands.size(), Kit.unshaded(),
		AABB(Vector3(-25.0, 0.0, -20.0), Vector3(50.0, 12.0, 40.0)), "StringLights", true)
	_flags = Kit.multimesh(Kit.flag_mesh(), per * strands.size(), Kit.petal_material(),
		AABB(Vector3(-25.0, 0.0, -20.0), Vector3(50.0, 12.0, 40.0)), "Bunting")
	for k in per:
		var t := (float(k) + 0.5) / float(per)
		for s in strands.size():
			var a: Vector3 = strands[s][0]
			var b: Vector3 = strands[s][1]
			var p := a.lerp(b, t) + Vector3.DOWN * 1.5 * 4.0 * t * (1.0 - t)
			var i := k * strands.size() + s
			var c: Color = bulb_cols[(k + s) % bulb_cols.size()]
			_bulbs.multimesh.set_instance_transform(i, Transform3D(Basis(), p))
			_bulbs.multimesh.set_instance_color(i, c)
			_bulbs.multimesh.set_instance_custom_data(i, c)
			var tangent := (b - a).normalized()
			var yaw := atan2(-tangent.z, tangent.x)
			var fp := a.lerp(b, t + 0.5 / float(per)) + Vector3.DOWN * 1.5 * 4.0 * (t + 0.5 / float(per)) * (1.0 - t - 0.5 / float(per)) + Vector3.DOWN * 0.08
			_flags.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.4, 1.3, 1.0)), fp))
			_flags.multimesh.set_instance_color(i, flag_cols[(k + 2 * s) % flag_cols.size()])
	_bulbs.multimesh.visible_instance_count = 0
	_flags.multimesh.visible_instance_count = 0
	add_child(_bulbs)
	add_child(_flags)


func _build_fountain_water() -> void:
	_water = MeshInstance3D.new()
	_water.name = "FountainWater"
	var cyl := CylinderMesh.new()
	cyl.top_radius = Square.FOUNTAIN_R - 0.32
	cyl.bottom_radius = Square.FOUNTAIN_R - 0.32
	cyl.height = 0.5
	cyl.radial_segments = 24
	_water.mesh = cyl
	_water.position = FOUNTAIN + Vector3(0.0, 0.2, 0.0)
	_water.material_override = Kit.water(0.75)
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	# The jet: anchored at its foot so it grows upward.
	_jet = Node3D.new()
	_jet.name = "Jet"
	_jet.position = FOUNTAIN + Vector3(0.0, 3.0, 0.0)
	add_child(_jet)
	var jet_mi := MeshInstance3D.new()
	var jm := CylinderMesh.new()
	jm.top_radius = 0.05
	jm.bottom_radius = 0.16
	jm.height = 1.6
	jm.radial_segments = 10
	jet_mi.mesh = jm
	jet_mi.position = Vector3(0.0, 0.8, 0.0)
	jet_mi.material_override = Kit.water(0.6)
	jet_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jet.add_child(jet_mi)
	var drop_mat: StandardMaterial3D = ToonFactory.build(Color(0.7, 0.88, 1.0), ToonFactory.Surface.FLAT, 0.05)
	_drops = Kit.multimesh(Kit.droplet_mesh(), 96, drop_mat,
		AABB(FOUNTAIN + Vector3(-4.0, 0.0, -4.0), Vector3(8.0, 5.0, 8.0)), "Spray")
	add_child(_drops)


# --- Probe and test helpers ---------------------------------------------------------------

## What this level puts in front of the renderer right now: visible mesh and
## multimesh instances, their surfaces, the shadow casters among them, and an
## estimate of draw calls (one per visible surface, plus one per caster
## surface per shadow split). Counts only this level's own subtree.
func render_census() -> Dictionary:
	var out := {"mesh_instances": 0, "visible": 0, "surfaces": 0, "casters": 0, "draw_estimate": 0}
	var splits := 1 if _sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL else 2
	for n in find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g is MeshInstance3D:
			out["mesh_instances"] += 1
		if not g.is_visible_in_tree():
			continue
		var surfaces := 1
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			surfaces = (g as MeshInstance3D).mesh.get_surface_count()
		elif g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.visible_instance_count == 0:
				continue
		out["visible"] += 1
		out["surfaces"] += surfaces
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			out["casters"] += surfaces
	out["draw_estimate"] = out["surfaces"] + out["casters"] * splits
	return out


## Stage name for probes: "houses", "cases", "finale" or "done".
func stage_name() -> String:
	return ["houses", "cases", "finale", "done"][_stage]


func houses_done() -> int:
	return _houses_done


## Put the human hero (and the companion beside them) a couple of metres in
## front of `p`, on the open-square side. A test helper: the objective itself
## still needs real hits and real pickups.
func place_heroes_near(p: Vector3, gap: float = 2.4) -> void:
	var c := to_global(Vector3(FOUNTAIN.x + 6.0, 0.0, 0.0))
	var dir := _flat(c - p).normalized()
	var spot := panda_clamp(p + dir * gap)
	var side := Vector3(-dir.z, 0.0, dir.x)
	for h in _heroes:
		if not is_instance_valid(h):
			continue
		var at := spot if h == _human else spot + side * 2.2 + dir * 0.6
		h.global_position = Vector3(at.x, 1.2, at.z)
		if h is CharacterBody3D:
			(h as CharacterBody3D).velocity = Vector3.ZERO
	_refresh_hero_positions()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
