extends Node3D
## The big friendly blue dragon who guards the stadium: about 7 m nose to tail,
## round body, a pale belly with soft plates, little wings, soft cream horns,
## huge friendly eyes. Built from vertex-coloured parts so it can move: body,
## neck, head, jaw, eyelids, two wings, four legs, four tail segments.
##
## TIED: lies in the centre circle under the goblins' ropes, breathing, looking
## at the heroes, now and then wriggling; cheer() when a rope snaps.
## free(): stands up and ROARS (dragon_roar, a gentle shake), then FOLLOWs the
## heroes about. In stage 2 it roars at goblin carriers near it so they drop
## their cups (a helping paw for small players). breathe_fire_at(): walks over,
## faces the van and lets out one big cartoon puff of fire.
##
## Its solid is on BLOCKERS: heroes bump into it, the camera arm and the balls do
## not. All motion from an accumulated clock; one seeded RNG.

signal roared
signal fired

const VC := preload("res://scripts/levels/dragao/vc_baker.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")
const L := preload("res://scripts/levels/dragao/dragao_layout.gd")

enum S { TIED, RISING, ROAR, FOLLOW, HELP_ROAR, TO_VAN, FIRE, PROUD }

const BLUE := Color(0.13, 0.42, 0.95)
const BLUE_DARK := Color(0.08, 0.28, 0.75)
const BELLY := Color(0.72, 0.87, 1.0)
const BELLY_LINE := Color(0.6, 0.77, 0.97)
const CREAM := Color(1.0, 0.95, 0.82)
const WING := Color(0.45, 0.72, 1.0)
const WALK_SPEED := 3.6
const HELP_RADIUS := 7.5
const HELP_COOLDOWN := 9.0
const RISE_TIME := 1.3
const ROAR_TIME := 1.7

var level = null  # the dragao level (untyped: no cyclic preload)
var state: int = S.TIED
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _clock: float = 0.0
var _yaw: float = 0.0
var _pose: float = 0.0          # 0 lying, 1 standing
var _walk: float = 0.0
var _speed: float = 0.0
var _cheer: float = 0.0
var _struggle_in: float = 4.0
var _struggle: float = 0.0
var _blink_in: float = 2.0
var _blink: float = 0.0
var _help_cd: float = HELP_COOLDOWN
var _no_help_for: float = 0.0
var _goal := Vector3.ZERO
var _fire_target := Vector3.ZERO
var _fire_spot := Vector3.ZERO
var _fired: bool = false
var _look := 0.0
var _side := 1.0
var _blob: int = -1
var _blockers: Array = [[Vector3.ZERO, 1.6], [Vector3.ZERO, 1.6], [Vector3.ZERO, 1.0]]

var _root: Node3D
var _body: MeshInstance3D
var _neck: MeshInstance3D
var _head: MeshInstance3D
var _jaw: MeshInstance3D
var _lids: MeshInstance3D
var _wing_l: MeshInstance3D
var _wing_r: MeshInstance3D
var _legs: Array[MeshInstance3D] = []
var _tail: Array[MeshInstance3D] = []
var _fire: CPUParticles3D
var _solid: AnimatableBody3D


func _ready() -> void:
	_rng.seed = 0xD7A60
	_build()
	if level != null:
		_blob = level.fx.blob_alloc()
	reset()


func reset() -> void:
	_rng.seed = 0xD7A60
	state = S.TIED
	_t = 0.0
	_pose = 0.0
	_yaw = 0.0
	_speed = 0.0
	_cheer = 0.0
	_struggle = 0.0
	_fired = false
	_help_cd = HELP_COOLDOWN
	_no_help_for = 0.0
	position = L.DRAGON_POS
	_fire.emitting = false
	_apply_pose(0.0)


func is_tied() -> bool:
	return state == S.TIED


## A rope just snapped: a happy wriggle and a little cheer.
func cheer() -> void:
	_cheer = 1.0
	AudioManager.play_sfx(&"dragon_roar", global_position)
	if level != null:
		level.fx.sparkle(_head.global_position + Vector3.UP * 0.6, Color(0.6, 0.85, 1.0), 1.0)


func free_dragon() -> void:
	state = S.RISING
	_t = 0.0


func breathe_fire_at(target: Vector3) -> void:
	_fire_target = target
	var from_van := Vector3(-target.x, 0, -target.z).normalized()
	_fire_spot = L.clamp_to_pitch(target + from_van * 6.5, 2.5)
	state = S.TO_VAN
	_t = 0.0


func has_fired() -> bool:
	return _fired


## Soft circles goblins and loose cups keep out of (level space).
func blockers() -> Array:
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	_blockers[0][0] = position + fwd * 1.3
	_blockers[1][0] = position - fwd * 1.0
	_blockers[2][0] = position - fwd * 3.0
	return _blockers


func head_position() -> Vector3:
	return _head.global_position


func _physics_process(delta: float) -> void:
	_t += delta
	_clock += delta
	_cheer = maxf(0.0, _cheer - delta * 0.9)
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = _rng.randf_range(2.5, 5.0)
		_blink = 0.14
	_blink = maxf(0.0, _blink - delta)
	var want_speed := 0.0
	var look_at := Vector3.INF
	var hero: Node3D = level.nearest_hero(global_position) if level != null else null

	match state:
		S.TIED:
			_struggle_in -= delta
			if _struggle_in <= 0.0:
				_struggle_in = _rng.randf_range(4.5, 7.5)
				_struggle = 1.0
			_struggle = maxf(0.0, _struggle - delta * 0.8)
			if hero != null:
				look_at = hero.global_position
		S.RISING:
			_pose = clampf(_t / RISE_TIME, 0.0, 1.0)
			if _t >= RISE_TIME:
				state = S.ROAR
				_t = 0.0
				AudioManager.play_sfx(&"dragon_roar", global_position)
				GameManager.request_shake(0.45, 0.7)
				if level != null:
					for k in 3:
						var a := TAU * float(k) / 3.0
						level.fx.sparkle(global_position + Vector3(cos(a) * 2.0, 2.5, sin(a) * 2.0), Color(0.6, 0.85, 1.0), 1.6)
				roared.emit()
		S.ROAR:
			if _t >= ROAR_TIME:
				state = S.FOLLOW
				_t = 0.0
				_pick_follow_goal(hero)
		S.FOLLOW:
			_help_cd -= delta
			_no_help_for += delta
			if _t > 1.2:
				_t = 0.0
				_pick_follow_goal(hero)
			var carrier: Node3D = level.nearest_carrier(global_position)
			if carrier != null:
				var cd := _flat(carrier.global_position - global_position).length()
				if _help_cd <= 0.0 and cd < HELP_RADIUS:
					state = S.HELP_ROAR
					_t = 0.0
					_fire_target = carrier.global_position
				elif _no_help_for > 14.0:
					# Nobody near for a while: go and help on purpose.
					_goal = carrier.global_position
			want_speed = _walk_to(_goal, delta)
			if hero != null and want_speed < 0.5:
				look_at = hero.global_position
		S.HELP_ROAR:
			_turn_to(_fire_target, delta, 4.0)
			if _t > 0.35 and _t - delta <= 0.35:
				AudioManager.play_sfx(&"dragon_roar", global_position)
				GameManager.request_shake(0.22, 0.4)
				if level != null:
					level.dragon_helped(global_position, HELP_RADIUS + 0.5)
					level.fx.sparkle(_head.global_position + Vector3.UP * 0.5, Color(0.6, 0.85, 1.0), 1.2)
			if _t > 1.3:
				state = S.FOLLOW
				_t = 0.0
				_help_cd = HELP_COOLDOWN
				_no_help_for = 0.0
		S.TO_VAN:
			want_speed = _walk_to(_fire_spot, delta, 6.5)
			if _flat(_fire_spot - position).length() < 1.7 or _t > 6.0:
				state = S.FIRE
				_t = 0.0
		S.FIRE:
			_turn_to(_fire_target, delta, 5.0)
			if _t > 0.5 and not _fire.emitting and not _fired:
				_fire.emitting = true
				AudioManager.play_sfx(&"dragon_fire", global_position)
				GameManager.request_shake(0.35, 0.8)
			if _t > 1.1 and not _fired:
				_fired = true
				fired.emit()
			if _t > 2.0:
				_fire.emitting = false
				state = S.PROUD
				_t = 0.0
		S.PROUD:
			if hero != null:
				look_at = hero.global_position

	_speed = lerpf(_speed, want_speed, minf(1.0, delta * 6.0))
	_walk += delta * _speed * 1.1
	if look_at.is_finite():
		var to := _flat(look_at - global_position)
		var rel := wrapf(atan2(to.x, to.z) - _yaw, -PI, PI)
		_look = lerpf(_look, clampf(rel, -0.8, 0.8), minf(1.0, delta * 3.0))
	else:
		_look = lerpf(_look, 0.0, minf(1.0, delta * 3.0))
	_apply_pose(delta)
	_solid.global_transform = Transform3D(Basis(Vector3.UP, _yaw), global_position + Vector3.UP * (0.9 + 0.5 * _pose))
	if level != null:
		level.fx.blob_set(_blob, global_position + Vector3(sin(_yaw), 0, cos(_yaw)) * 0.2, 2.6, 0.9)


func _pick_follow_goal(hero: Node3D) -> void:
	if hero == null:
		_goal = position
		return
	# Stand beside the heroes as the camera sees them, a little ahead: in the
	# shot, never between the camera and the children. Keep the same side
	# unless it runs out of pitch.
	var h := hero.global_position
	var f: Vector3 = level.view_forward() if level != null else Vector3.FORWARD
	var right := Vector3(-f.z, 0, f.x)
	var g := h + right * _side * 6.0 + f * 3.0
	var c := L.clamp_to_pitch(g, 3.0)
	if _flat(c - g).length() > 1.5:
		_side = -_side
		g = h + right * _side * 6.0 + f * 3.0
		c = L.clamp_to_pitch(g, 3.0)
	_goal = c


func _walk_to(p: Vector3, delta: float, speed: float = WALK_SPEED) -> float:
	var d := _flat(p - position)
	if d.length() < 1.6:
		return 0.0
	_turn_to(p, delta, 2.2)
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var s := minf(speed, d.length())
	var facing := clampf(fwd.dot(d.normalized()), 0.0, 1.0)
	position += fwd * _speed * facing * delta
	position = L.clamp_to_pitch(position, 2.5)
	return s


func _turn_to(p: Vector3, delta: float, rate: float) -> void:
	var d := _flat(p - position)
	if d.length() < 0.05:
		return
	_yaw = lerp_angle(_yaw, atan2(d.x, d.z), minf(1.0, delta * rate))


# --- Pose -------------------------------------------------------------------------

func _apply_pose(_delta: float) -> void:
	var k := _pose
	var breathe := sin(_clock * 2.0) * 0.5 + 0.5
	var walk_s := sin(_walk * 2.4)
	var walk_c := cos(_walk * 2.4)
	var moving := clampf(_speed / WALK_SPEED, 0.0, 1.0)
	var roar := 0.0
	if state == S.ROAR:
		roar = sin(clampf(_t / ROAR_TIME, 0.0, 1.0) * PI)
	elif state == S.HELP_ROAR:
		roar = sin(clampf(_t / 1.3, 0.0, 1.0) * PI) * 0.8
	var fire := 0.0
	if state == S.FIRE:
		fire = clampf((_t - 0.2) / 0.3, 0.0, 1.0) * (1.0 - clampf((_t - 1.8) / 0.3, 0.0, 1.0))
	var cheer := sin(_cheer * PI) if _cheer > 0.0 else 0.0
	var proud := 1.0 if state == S.PROUD else 0.0

	var lie := 1.0 - k
	var hop := cheer * 0.12 + proud * absf(sin(_clock * 4.0)) * 0.06
	var body_y := lerpf(-0.62, 0.0, k) + absf(walk_s) * 0.07 * moving + hop
	var roll := walk_s * 0.05 * moving + sin(_clock * 9.0) * 0.07 * _struggle
	var s_breath := 1.0 + breathe * 0.035
	_root.transform = Transform3D(Basis(Vector3.UP, _yaw) * Basis(Vector3.BACK, roll)
		* Basis.from_scale(Vector3(s_breath, 1.0 + breathe * 0.025 - roar * 0.04, 1.0)), Vector3(0, body_y, 0))

	# Neck down on the grass when lying, up when standing, way up to roar.
	var neck_pitch := lerpf(0.85, -0.05, k) - roar * 0.45 - cheer * 0.35 * lie + fire * 0.25 + walk_c * 0.04 * moving
	_neck.rotation = Vector3(neck_pitch, _look * 0.6, sin(_clock * 9.0) * 0.1 * _struggle)
	var head_pitch := lerpf(-0.75, 0.05, k) - roar * 0.3 + fire * 0.15 - cheer * 0.2
	_head.rotation = Vector3(head_pitch, _look * 0.4, sin(_clock * 1.3) * 0.05)
	_jaw.rotation = Vector3(0.12 + roar * 0.55 + fire * 0.6 + cheer * 0.35 + proud * 0.15, 0, 0)
	_lids.visible = _blink > 0.0 and roar <= 0.0 and fire <= 0.0

	var flap := sin(_clock * (12.0 if roar > 0.0 or cheer > 0.0 else 2.2))
	var spread := 0.5 + roar * 0.75 + cheer * 0.5 + proud * 0.35 * absf(sin(_clock * 3.0))
	var fold := lie * 0.55
	# The left wing is the right one mirrored (scale -1 on X), so its angle flips.
	var wing_a := (spread - fold) + flap * (0.08 + roar * 0.4 + cheer * 0.3)
	_wing_r.rotation = Vector3(0, 0, wing_a)
	_wing_l.rotation = Vector3(0, 0, -wing_a)

	# Legs: tucked when lying, a diagonal walk cycle when moving.
	var swing := walk_s * 0.55 * moving
	var legs := [
		Vector3(lerpf(-1.25, 0.0, k) + swing, 0, lerpf(-0.35, 0.0, k)),
		Vector3(lerpf(-1.25, 0.0, k) - swing, 0, lerpf(0.35, 0.0, k)),
		Vector3(lerpf(1.3, 0.0, k) - swing, 0, lerpf(-0.3, 0.0, k)),
		Vector3(lerpf(1.3, 0.0, k) + swing, 0, lerpf(0.3, 0.0, k)),
	]
	for i in 4:
		_legs[i].rotation = legs[i]

	# Tail: curled round when lying, a lazy wag otherwise, a thrash when struggling.
	for i in _tail.size():
		var fi := float(i)
		var wag := sin(_clock * (1.6 + proud * 3.0) - fi * 0.7) * (0.18 + proud * 0.12) + sin(_clock * 10.0 - fi) * 0.25 * _struggle
		var curl := lie * 0.32
		# The first segment droops from the rump, the rest curve gently back up,
		# so the tip rests on the grass standing or lying.
		var droop := lerpf(-0.22, -0.42, k) if i == 0 else 0.1
		_tail[i].rotation = Vector3(droop, curl + wag, 0)

	if _fire.emitting:
		var jaw_xf := _jaw.global_transform
		_fire.global_transform = Transform3D(_head.global_transform.basis.orthonormalized(),
			jaw_xf.origin + _head.global_transform.basis.z.normalized() * 1.3 + Vector3.UP * 0.1)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	_root = Node3D.new()
	_root.name = "Body"
	add_child(_root)
	var belly_fn := func(lp: Vector3) -> Color:
		# Pale belly underneath and up the chest, with soft plate lines.
		var under := -lp.y + lp.z * 0.35
		if under > 0.25:
			var band := int(floor((lp.z + 1.0) * 5.0)) % 2
			return BELLY if band == 0 else BELLY_LINE
		return BLUE
	var b := VC.new()
	b.sphere_fn(Vector3(0, 1.45, 0), Vector3(1.2, 1.05, 1.75), Basis(), belly_fn, 22, 16)
	# Rounded back spikes, cream, down the spine.
	for i in 5:
		var z := 1.1 - 0.62 * float(i)
		var y := 1.45 + 1.03 * sqrt(maxf(0.0, 1.0 - pow(z / 1.75, 2.0))) - 0.08
		var sh := 0.34 - 0.03 * float(i)
		b.cylinder(0.08, 0.22, sh, Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, y + 0.1, z)), CREAM, 10)
		b.sphere(Vector3(0, y + 0.1 + sh * 0.48, z - sh * 0.12), Vector3.ONE * 0.085, CREAM, Basis(), 8, 6)
	_body = _part(_root, "Torso", b.mesh(), Vector3.ZERO)

	# Neck pivots at the front-top of the body.
	var nb := VC.new()
	nb.capsule(0.46, 1.6, Transform3D(Basis(Vector3.RIGHT, 0.65), Vector3(0, 0.45, 0.35)), BLUE, 14)
	nb.sphere(Vector3(0, 0.35, 0.55), Vector3(0.36, 0.42, 0.32), BELLY, Basis(Vector3.RIGHT, 0.65), 12, 8)
	_neck = _part(_root, "Neck", nb.mesh(), Vector3(0, 1.95, 1.3))

	var hb := VC.new()
	hb.sphere(Vector3(0, 0.25, 0.3), Vector3(0.78, 0.66, 0.74), BLUE, Basis(), 20, 14)
	hb.sphere(Vector3(0, 0.05, 0.95), Vector3(0.56, 0.4, 0.58), BLUE, Basis(), 16, 10)
	hb.sphere(Vector3(0, -0.1, 0.9), Vector3(0.44, 0.2, 0.5), Color(0.55, 0.12, 0.2), Basis(), 12, 8)   # mouth
	for sx in [-1.0, 1.0]:
		hb.sphere(Vector3(sx * 0.2, 0.2, 1.46), Vector3(0.07, 0.05, 0.04), BLUE_DARK, Basis(), 8, 5)    # nostril
		hb.sphere(Vector3(sx * 0.34, 0.55, 0.72), Vector3(0.25, 0.27, 0.22), Color(1, 1, 1), Basis(), 16, 12)
		hb.sphere(Vector3(sx * 0.36, 0.53, 0.9), Vector3(0.15, 0.17, 0.07), Color(0.06, 0.1, 0.3), Basis(), 12, 8)
		hb.sphere(Vector3(sx * 0.31, 0.6, 0.96), Vector3.ONE * 0.05, Color(1, 1, 1), Basis(), 8, 5)
		hb.sphere(Vector3(sx * 0.5, 0.15, 0.85), Vector3(0.14, 0.09, 0.08), Color(0.62, 0.78, 1.0), Basis(), 10, 6)  # cheek
		# Soft horns and little fin ears.
		var horn := Basis(Vector3.RIGHT, -0.55) * Basis(Vector3.BACK, -sx * 0.3)
		hb.cylinder(0.09, 0.15, 0.36, Transform3D(horn, Vector3(sx * 0.32, 0.9, 0.08)), CREAM, 10)
		hb.sphere(Vector3(sx * 0.32, 0.9, 0.08) + horn * Vector3(0, 0.19, 0), Vector3.ONE * 0.1, CREAM, Basis(), 10, 6)
		hb.cylinder(0.0, 0.16, 0.4, Transform3D(Basis(Vector3.BACK, -sx * 1.25) * Basis.from_scale(Vector3(1, 1, 0.35)),
			Vector3(sx * 0.78, 0.4, 0.1)), WING, 8)
		# Friendly eyebrows: raised in the middle, never a frown.
		hb.box(Vector3(0.22, 0.045, 0.05), Transform3D(Basis(Vector3.BACK, -sx * 0.22), Vector3(sx * 0.34, 0.9, 0.8)), BLUE_DARK)
	# A wide smile along the snout, curling up at the ends.
	var smile := PackedVector3Array()
	for k in 11:
		var ph := -0.95 + 1.9 * float(k) / 10.0
		var kk := 0.93
		smile.append(Vector3(0.56 * sin(ph) * kk + 0.0, -0.1 + 0.09 * pow(ph / 0.95, 2.0), 0.95 + 0.58 * cos(ph) * kk + 0.015))
	hb.tube(smile, 0.03, BLUE_DARK, BLUE_DARK, 6)
	_head = _part(_neck, "Head", hb.mesh(), Vector3(0, 1.05, 0.95))

	var jb := VC.new()
	jb.sphere(Vector3(0, -0.12, 0.42), Vector3(0.48, 0.17, 0.5), BELLY, Basis(), 14, 8)
	jb.sphere(Vector3(0, -0.02, 0.45), Vector3(0.28, 0.06, 0.32), Color(1.0, 0.5, 0.6), Basis(), 10, 6)   # tongue
	_jaw = _part(_head, "Jaw", jb.mesh(), Vector3(0, -0.12, 0.5))

	var lb := VC.new()
	for sx in [-1.0, 1.0]:
		lb.sphere(Vector3(sx * 0.34, 0.56, 0.74), Vector3(0.27, 0.29, 0.24), BLUE, Basis(), 14, 10)
	_lids = _part(_head, "Eyelids", lb.mesh(), Vector3.ZERO)
	_lids.visible = false

	var wb := VC.new()
	# A little bat-wing: a blue arm bone and a scalloped pale membrane.
	var bone := Vector3(1.75, 1.1, -0.45)
	wb.capsule(0.09, bone.length() + 0.1, Transform3D(_aim_basis(bone), bone * 0.5), BLUE_DARK, 8)
	wb.sphere(bone, Vector3.ONE * 0.12, CREAM, Basis(), 8, 6)
	var edge := [bone, Vector3(1.55, 0.35, -1.0), Vector3(1.05, 0.25, -1.45), Vector3(0.55, 0.0, -1.35), Vector3(0.0, -0.1, -0.85)]
	for k in edge.size() - 1:
		var mid: Vector3 = (edge[k] as Vector3).lerp(edge[k + 1], 0.5) * 0.86
		wb.tri2(Vector3.ZERO, edge[k], mid, WING if k % 2 == 0 else WING.darkened(0.05))
		wb.tri2(Vector3.ZERO, mid, edge[k + 1], WING.darkened(0.08))
	var wing_mesh := wb.mesh()
	_wing_r = _part(_root, "WingR", wing_mesh, Vector3(0.75, 2.3, 0.45))
	_wing_l = _part(_root, "WingL", wing_mesh, Vector3(-0.75, 2.3, 0.45))
	_wing_l.scale = Vector3(-1, 1, 1)

	var lgb := VC.new()
	lgb.cylinder(0.27, 0.34, 0.85, Transform3D(Basis(), Vector3(0, -0.42, 0)), BLUE, 12)
	lgb.sphere(Vector3(0, -0.88, 0.12), Vector3(0.36, 0.2, 0.46), BLUE, Basis(), 12, 8)
	for t in 3:
		lgb.sphere(Vector3(-0.2 + 0.2 * float(t), -0.9, 0.52), Vector3(0.09, 0.08, 0.1), CREAM, Basis(), 8, 5)
	var leg_mesh := lgb.mesh()
	for p in [Vector3(-0.78, 1.05, 0.95), Vector3(0.78, 1.05, 0.95), Vector3(-0.82, 1.05, -0.95), Vector3(0.82, 1.05, -0.95)]:
		_legs.append(_part(_root, "Leg%d" % _legs.size(), leg_mesh, p))

	var parent: Node3D = _root
	var at := Vector3(0, 1.25, -1.45)
	var radii := [0.62, 0.48, 0.34, 0.22, 0.1]
	for i in 4:
		var tb := VC.new()
		var r0: float = radii[i]
		var r1: float = radii[i + 1]
		tb.cylinder(r1, r0, 1.15, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.55)), BLUE, 12)
		tb.sphere(Vector3(0, 0, -1.12), Vector3.ONE * r1, BLUE, Basis(), 10, 6)
		tb.cylinder(0.01, 0.1, 0.22 - 0.03 * float(i), Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(0, r0 * 0.9, -0.5)), CREAM, 6)
		if i == 3:
			# The spade at the tip: a soft cream diamond.
			tb.sphere(Vector3(0, 0, -1.4), Vector3(0.32, 0.07, 0.3), CREAM, Basis(Vector3.UP, PI * 0.25), 8, 4)
		var seg := _part(parent, "Tail%d" % i, tb.mesh(), at)
		_tail.append(seg)
		parent = seg
		at = Vector3(0, 0, -1.1)

	_fire = CPUParticles3D.new()
	_fire.name = "Fire"
	_fire.emitting = false
	_fire.amount = 70
	_fire.lifetime = 0.8
	_fire.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_fire.mesh = q
	_fire.material_override = M.puff()
	_fire.direction = Vector3(0, 0.08, 1)
	_fire.spread = 11.0
	_fire.gravity = Vector3(0, 2.5, 0)
	_fire.initial_velocity_min = 12.0
	_fire.initial_velocity_max = 15.5
	_fire.damping_min = 2.0
	_fire.damping_max = 3.0
	_fire.scale_amount_min = 0.7
	_fire.scale_amount_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(0.5, 2.0))
	grow.add_point(Vector2(1, 2.8))
	_fire.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 1.0, 0.75, 1.0), Color(1.0, 0.75, 0.15, 1.0),
		Color(1.0, 0.35, 0.1, 0.85), Color(0.35, 0.3, 0.32, 0.0)])
	_fire.color_ramp = ramp
	_fire.use_fixed_seed = true
	_fire.seed = 0xF1AE
	_fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fire)

	_solid = AnimatableBody3D.new()
	_solid.name = "Solid"
	_solid.sync_to_physics = false
	_solid.collision_layer = PhysicsLayers.BLOCKERS
	_solid.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 1.15
	cap.height = 4.6
	cs.shape = cap
	cs.rotation = Vector3(PI * 0.5, 0, 0)
	_solid.add_child(cs)
	_solid.top_level = true
	add_child(_solid)


func _part(parent: Node3D, n: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = M.skin()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	parent.add_child(mi)
	return mi


static func _aim_basis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.BACK).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
