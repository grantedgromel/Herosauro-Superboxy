extends Node3D
## One of the four panda tourists: Dad (tallest, sunglasses pushed up, a
## tourist camera), Mum (sun hat), the boy (blue cap) and the girl (pink bow).
##
## Round, soft and procedural: a body, a head, two arms and two legs, each its
## own MeshInstance3D so they can waddle, look about, jump and clap. Meshes are
## built once per kind and shared. No collision at all: a panda can never block
## a hero, and the level steers them round the heroes, the fountain and the
## rubbish (pandas_level.gd `panda_steer`).
##
## The level sets `goal` (where to stand, a polite distance from the heroes)
## and `interest` (what to look at) every frame; the panda walks, turns and
## animates itself from accumulated delta.

const Kit := preload("res://scripts/levels/pandas/pandas_kit.gd")

enum Kind { DAD, MUM, BOY, GIRL }

const SCALES := [0.95, 0.86, 0.6, 0.56]
const HEAD_SCALES := [1.0, 1.0, 1.2, 1.22]
const WALK_SPEED := 3.0
const HURRY_SPEED := 6.8
const ARRIVE := 0.35
const GRAVITY := 22.0
const CHEER_TIME := 1.9
const HUG_TIME := 1.1
const WHITE := Color(0.96, 0.96, 0.94)
const BLACK := Color(0.13, 0.12, 0.14)

var kind: int = Kind.DAD
var level: Node = null
var goal := Vector3.ZERO
var interest := Vector3.ZERO
var carry_anchor: Node3D

var _yaw: float = 0.0
var _vel := Vector3.ZERO
var _t: float = 0.0
var _phase: float = 0.0
var _hop_y: float = 0.0
var _hop_v: float = 0.0
var _squash: float = 0.0
var _squash_v: float = 0.0
var _cheer_t: float = -100.0
var _hops_done: int = 0
var _hug_t: float = -1.0
var _carrying: bool = false
var _waving: bool = false
var _enter_t: float = -1.0
var _enter_from := Vector3.ZERO
var _enter_to := Vector3.ZERO

var _turn: Node3D
var _bob: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D

static var _meshes: Dictionary = {}


func _ready() -> void:
	_build()
	goal = position
	interest = position + Vector3.FORWARD


func reset_to(p: Vector3, yaw: float) -> void:
	position = p
	goal = p
	_yaw = yaw
	_vel = Vector3.ZERO
	_hop_y = 0.0
	_hop_v = 0.0
	_squash = 0.0
	_squash_v = 0.0
	_cheer_t = -100.0
	_hug_t = -1.0
	_carrying = false
	_waving = false
	_enter_t = -1.0
	visible = true
	_turn.scale = Vector3.ONE * float(SCALES[kind])
	carry_anchor.position = Vector3(0.0, 0.78, 0.56)
	_pose(0.0, 0.0)


func is_busy() -> bool:
	return _cheer_t >= 0.0 and _cheer_t < CHEER_TIME or _hug_t >= 0.0 or _enter_t >= 0.0


func is_inside() -> bool:
	return _enter_t >= 1.0 or (not visible and _enter_t >= 0.0)


## Jump and clap. `delay` staggers the family so they do not move as one.
func cheer(delay: float = 0.0) -> void:
	if _enter_t >= 0.0:
		return
	_cheer_t = -delay
	_hops_done = 0


## The suitcase has arrived: hug it, then carry it at the side.
func receive_suitcase() -> void:
	_hug_t = 0.0
	_carrying = true
	carry_anchor.position = Vector3(0.0, 0.78, 0.56)
	_kick(0.3)


func wave(on: bool) -> void:
	_waving = on


## Finale: walk in through `door` (global) and disappear inside.
func enter(door: Vector3) -> void:
	_enter_t = 0.0
	_enter_from = position
	_enter_to = door


func _physics_process(delta: float) -> void:
	_t += delta
	if _enter_t >= 0.0:
		_process_enter(delta)
		return
	var busy := is_busy()
	var to := goal - position
	to.y = 0.0
	var d := to.length()
	var want := Vector3.ZERO
	if d > ARRIVE and not busy:
		var speed := WALK_SPEED if d < 6.0 else HURRY_SPEED
		want = to / d * minf(speed, d * 2.2)
	if level != null:
		want = level.panda_steer(position, want)
	_vel = _vel.lerp(want, clampf(7.0 * delta, 0.0, 1.0))
	position += _vel * delta
	if level != null:
		position = level.panda_clamp(position)
	position.y = 0.0
	var speed_now := _vel.length()

	# Face where we walk; when standing, turn to what is interesting.
	var look := interest - position
	look.y = 0.0
	var want_yaw := _yaw
	if speed_now > 0.4:
		want_yaw = atan2(_vel.x, _vel.z)
	elif look.length() > 0.5:
		want_yaw = atan2(look.x, look.z)
	_yaw = lerp_angle(_yaw, want_yaw, clampf(6.0 * delta, 0.0, 1.0))
	_turn.rotation.y = _yaw

	# Cheer: two hops with a clap over the head.
	if _cheer_t > -100.0:
		var was := _cheer_t
		_cheer_t += delta
		if was < 0.0 and _cheer_t >= 0.0 or was < 0.8 and _cheer_t >= 0.8:
			if _cheer_t >= 0.0 and _hops_done < 2:
				_hops_done += 1
				_hop_v = 4.2
				_kick(0.28)
		if _cheer_t > CHEER_TIME:
			_cheer_t = -100.0
	if _hug_t >= 0.0:
		_hug_t += delta
		if _hug_t > HUG_TIME:
			_hug_t = -1.0
			carry_anchor.position = Vector3(-0.55, 0.5, 0.1)

	_integrate_hop(delta)
	var moving := clampf(speed_now / 2.5, 0.0, 1.0)
	_phase += delta * (4.0 + speed_now * 2.4)
	_pose(moving, delta)

	# The head looks at what the heroes are doing.
	var rel := wrapf(atan2(look.x, look.z) - _yaw, -PI, PI) if look.length() > 0.3 else 0.0
	_head.rotation.y = lerpf(_head.rotation.y, clampf(rel, -1.1, 1.1), clampf(5.0 * delta, 0.0, 1.0))
	_head.rotation.x = -0.12 + 0.05 * sin(_t * 1.7 + float(kind))


func _integrate_hop(delta: float) -> void:
	if _hop_y > 0.0 or _hop_v > 0.0:
		_hop_v -= GRAVITY * delta
		_hop_y += _hop_v * delta
		if _hop_y <= 0.0:
			_hop_y = 0.0
			_hop_v = 0.0
			_kick(-0.32)
	# Squash spring.
	_squash_v += (-170.0 * _squash - 11.0 * _squash_v) * delta
	_squash += _squash_v * delta


func _kick(amount: float) -> void:
	_squash_v += amount * 12.0


## Arms, legs, bob and squash for this frame.
func _pose(moving: float, _delta: float) -> void:
	var sw := sin(_phase)
	var bob := absf(sw) * 0.06 * moving + 0.012 * sin(_t * 2.3 + float(kind)) * (1.0 - moving)
	var s := clampf(_squash, -0.35, 0.35) - 0.03 * absf(cos(_phase)) * moving
	_bob.position.y = _hop_y + bob
	_bob.scale = Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5)
	_bob.rotation.z = sw * 0.13 * moving
	_leg_l.rotation.x = sw * 0.65 * moving
	_leg_r.rotation.x = -sw * 0.65 * moving
	var al := Vector3(-sw * 0.45 * moving, 0.0, 0.32)
	var ar := Vector3(sw * 0.45 * moving, 0.0, -0.32)
	if _cheer_t >= 0.0 and _cheer_t < CHEER_TIME:
		var clap := absf(sin(_cheer_t * 13.0))
		al = Vector3(-0.25, 0.0, 2.45 + 0.5 * clap)
		ar = Vector3(-0.25, 0.0, -2.45 - 0.5 * clap)
	elif _hug_t >= 0.0:
		al = Vector3(-1.25, -0.55, 0.25)
		ar = Vector3(-1.25, 0.55, -0.25)
	elif _waving:
		ar = Vector3(0.0, 0.0, -2.5 + 0.35 * sin(_t * 9.0))
	if _carrying and _hug_t < 0.0:
		ar = Vector3(0.1, 0.0, -0.12)
	_arm_l.rotation = al
	_arm_r.rotation = ar


func _process_enter(delta: float) -> void:
	_enter_t += delta * 0.9
	var k := clampf(_enter_t, 0.0, 1.0)
	position = _enter_from.lerp(_enter_to, k)
	var to := _enter_to - _enter_from
	if to.length() > 0.1:
		_yaw = lerp_angle(_yaw, atan2(to.x, to.z), clampf(8.0 * delta, 0.0, 1.0))
	_turn.rotation.y = _yaw
	_phase += delta * 9.0
	_integrate_hop(delta)
	_pose(1.0, delta)
	var shrink := clampf((k - 0.55) / 0.45, 0.0, 1.0)
	_turn.scale = Vector3.ONE * float(SCALES[kind]) * maxf(0.001, 1.0 - shrink)
	if k >= 1.0:
		visible = false


# --- Build -----------------------------------------------------------------------

func _build() -> void:
	var mat := Kit.vc("soft")
	_turn = Node3D.new()
	_turn.name = "Turn"
	_turn.scale = Vector3.ONE * float(SCALES[kind])
	add_child(_turn)
	_bob = Node3D.new()
	_bob.name = "Bob"
	_turn.add_child(_bob)
	_part(_bob, "Body", _mesh("body", kind), mat, Vector3.ZERO)
	_head = Node3D.new()
	_head.name = "HeadPivot"
	_head.position = Vector3(0.0, 1.2, 0.02)
	_head.scale = Vector3.ONE * float(HEAD_SCALES[kind])
	_bob.add_child(_head)
	_part(_head, "Head", _mesh("head", kind), mat, Vector3.ZERO).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arm_l = _pivot(_bob, "ArmL", Vector3(0.43, 1.04, 0.05))
	_arm_r = _pivot(_bob, "ArmR", Vector3(-0.43, 1.04, 0.05))
	_leg_l = _pivot(_bob, "LegL", Vector3(0.21, 0.32, 0.0))
	_leg_r = _pivot(_bob, "LegR", Vector3(-0.21, 0.32, 0.0))
	# Only the body casts: it is the contact shadow that plants the panda; the
	# limbs and head would double the shadow pass for a few pixels.
	for limb: Node3D in [_arm_l, _arm_r, _leg_l, _leg_r]:
		var is_arm := limb == _arm_l or limb == _arm_r
		var mi := _part(limb, "Limb", _mesh("arm" if is_arm else "leg", 0), mat, Vector3.ZERO)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	carry_anchor = Node3D.new()
	carry_anchor.name = "Carry"
	carry_anchor.position = Vector3(0.0, 0.78, 0.56)
	_bob.add_child(carry_anchor)


func _pivot(parent: Node3D, n: String, at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = at
	parent.add_child(p)
	return p


func _part(parent: Node3D, n: String, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


static func _mesh(part: String, k: int) -> ArrayMesh:
	var key := "%s_%d" % [part, k]
	if _meshes.has(key):
		return _meshes[key]
	var b := Kit.VBaker.new()
	match part:
		"body":
			_body_mesh(b, k)
		"head":
			_head_mesh(b, k)
		"arm":
			b.blob(Vector3(0.125, 0.3, 0.135), _at(Vector3(0.0, -0.22, 0.0)), BLACK, 10, 6)
		"leg":
			b.blob(Vector3(0.17, 0.2, 0.19), _at(Vector3(0.0, -0.14, 0.03)), BLACK, 10, 6)
			b.blob(Vector3(0.1, 0.03, 0.1), _at(Vector3(0.0, -0.3, 0.12), Vector3(-0.5, 0.0, 0.0)),
				Color(0.42, 0.36, 0.38), 8, 4)
	var m := b.bake_mesh()
	_meshes[key] = m
	return m


static func _at(p: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), p)


static func _body_mesh(b: Kit.VBaker, k: int) -> void:
	b.blob(Vector3(0.5, 0.56, 0.46), _at(Vector3(0.0, 0.78, 0.0)), WHITE, 16, 10)
	b.blob(Vector3(0.525, 0.2, 0.485), _at(Vector3(0.0, 1.03, 0.0)), BLACK, 16, 6)
	b.blob(Vector3(0.12, 0.12, 0.1), _at(Vector3(0.0, 0.46, -0.44)), WHITE, 8, 5)
	match k:
		Kind.DAD:
			# A tourist's camera on a strap.
			b.box(Vector3(0.24, 0.16, 0.1), Vector3(0.0, 0.86, 0.47), Color(0.2, 0.22, 0.26), Vector3(-0.2, 0.0, 0.0))
			b.cyl(0.055, 0.08, _at(Vector3(0.0, 0.85, 0.54), Vector3(PI * 0.5 - 0.2, 0.0, 0.0)), Color(0.1, 0.1, 0.12), 10)
			b.box(Vector3(0.05, 0.05, 0.02), Vector3(0.08, 0.92, 0.53), Color(0.9, 0.3, 0.25))
			for sx: float in [-1.0, 1.0]:
				b.beam(Vector3(sx * 0.1, 0.9, 0.45), Vector3(sx * 0.22, 1.2, 0.3), 0.03, Color(0.8, 0.25, 0.2))
		Kind.MUM:
			# A flowery scarf.
			b.blob(Vector3(0.36, 0.08, 0.34), _at(Vector3(0.0, 1.16, 0.06)), Color(1.0, 0.5, 0.65), 12, 4)
			b.blob(Vector3(0.07, 0.07, 0.04), _at(Vector3(0.18, 1.12, 0.38)), Color(1.0, 0.9, 0.3), 6, 4)
		Kind.BOY:
			# A little green backpack.
			b.box(Vector3(0.42, 0.42, 0.18), Vector3(0.0, 0.88, -0.46), Color(0.3, 0.7, 0.35))
			b.box(Vector3(0.3, 0.16, 0.06), Vector3(0.0, 0.78, -0.56), Color(0.25, 0.6, 0.3))
		Kind.GIRL:
			# A pink tutu.
			b.blob(Vector3(0.56, 0.09, 0.52), _at(Vector3(0.0, 0.52, 0.0)), Color(1.0, 0.6, 0.78), 14, 4)


static func _head_mesh(b: Kit.VBaker, k: int) -> void:
	b.blob(Vector3(0.4, 0.36, 0.37), _at(Vector3(0.0, 0.34, 0.0)), WHITE, 16, 10)
	for sx: float in [-1.0, 1.0]:
		b.blob(Vector3(0.13, 0.13, 0.09), _at(Vector3(sx * 0.28, 0.62, -0.03)), BLACK, 10, 6)
		b.blob(Vector3(0.11, 0.145, 0.06), _at(Vector3(sx * 0.15, 0.37, 0.3), Vector3(0.0, sx * 0.35, sx * 0.5)), BLACK, 10, 6)
		b.blob(Vector3(0.056, 0.06, 0.03), _at(Vector3(sx * 0.15, 0.39, 0.345)), WHITE, 8, 5)
		b.blob(Vector3(0.036, 0.042, 0.02), _at(Vector3(sx * 0.145, 0.385, 0.372)), Color(0.05, 0.05, 0.07), 8, 5)
		b.blob(Vector3(0.014, 0.014, 0.01), _at(Vector3(sx * 0.132, 0.405, 0.388)), Color.WHITE, 6, 4)
		b.blob(Vector3(0.06, 0.035, 0.02), _at(Vector3(sx * 0.25, 0.26, 0.29), Vector3(0.0, sx * 0.6, 0.0)),
			Color(1.0, 0.62, 0.68), 8, 4)
	b.blob(Vector3(0.14, 0.1, 0.09), _at(Vector3(0.0, 0.25, 0.3)), WHITE, 10, 6)
	b.blob(Vector3(0.07, 0.045, 0.045), _at(Vector3(0.0, 0.29, 0.38)), BLACK, 8, 5)
	b.beam(Vector3(-0.05, 0.2, 0.385), Vector3(0.0, 0.185, 0.39), 0.016, BLACK)
	b.beam(Vector3(0.0, 0.185, 0.39), Vector3(0.05, 0.2, 0.385), 0.016, BLACK)
	match k:
		Kind.DAD:
			# Sunglasses pushed up on the forehead.
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(0.14, 0.08, 0.03), Vector3(sx * 0.12, 0.58, 0.29), Color(0.1, 0.1, 0.14), Vector3(-0.5, 0.0, 0.0))
			b.box(Vector3(0.1, 0.02, 0.02), Vector3(0.0, 0.59, 0.3), Color(0.1, 0.1, 0.14), Vector3(-0.5, 0.0, 0.0))
		Kind.MUM:
			# The sun hat: wide straw brim, a crown, a pink ribbon and a flower.
			var tilt := Vector3(-0.18, 0.0, 0.06)
			b.cyl(0.6, 0.04, _at(Vector3(0.0, 0.6, -0.02), tilt), Color(0.96, 0.84, 0.5), 18)
			b.blob(Vector3(0.3, 0.18, 0.3), _at(Vector3(0.0, 0.68, -0.04), tilt), Color(0.96, 0.84, 0.5), 14, 6)
			b.cyl(0.305, 0.07, _at(Vector3(0.0, 0.64, -0.03), tilt), Color(1.0, 0.45, 0.6), 18)
			b.blob(Vector3(0.08, 0.08, 0.05), _at(Vector3(0.2, 0.66, 0.2), tilt), Color(1.0, 0.95, 0.4), 6, 4)
		Kind.BOY:
			b.blob(Vector3(0.37, 0.19, 0.36), _at(Vector3(0.0, 0.59, -0.02)), Color(0.2, 0.45, 0.9), 14, 6)
			b.box(Vector3(0.34, 0.03, 0.24), Vector3(0.0, 0.56, 0.36), Color(0.2, 0.45, 0.9), Vector3(0.18, 0.0, 0.0))
			b.blob(Vector3(0.04, 0.03, 0.04), _at(Vector3(0.0, 0.78, -0.02)), Color(1.0, 0.85, 0.2), 6, 4)
		Kind.GIRL:
			for sx: float in [-1.0, 1.0]:
				b.blob(Vector3(0.11, 0.075, 0.05), _at(Vector3(0.16 + sx * 0.1, 0.66, 0.1), Vector3(0.0, 0.0, sx * 0.4)),
					Color(1.0, 0.4, 0.62), 8, 5)
			b.blob(Vector3(0.045, 0.045, 0.045), _at(Vector3(0.16, 0.66, 0.12)), Color(1.0, 0.55, 0.72), 6, 4)
