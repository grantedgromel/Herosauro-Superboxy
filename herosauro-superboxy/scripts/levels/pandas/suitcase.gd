extends Node3D
## A panda's lost suitcase (stage 2). Bright, bobbing, with sparkles circling
## it. Touching it with either hero collects it: it hops, arcs through the air
## to its panda and the panda hugs it, then carries it.
##
## The pickup is an Area3D masking PLAYERS (the heroes' bodies), so "touch" means
## a real overlap: walking into it, or jumping up to the one on the balcony.

signal collected(case: Node3D)

const Kit := preload("res://scripts/levels/pandas/pandas_kit.gd")
const MagicFX := preload("res://scripts/levels/pandas/magic_fx.gd")

enum State { HIDDEN, APPEARING, WAITING, FLYING, CARRIED }

## Big on purpose (kid rule 10): the balcony case sits at 1.8 m behind a
## pilaster, and a child pressing toward it from the ground stands 1.6-1.8 m
## away with the capsule top 0.7 m below it (kidbot pandas seed 3 was stuck
## there 4 minutes at 0.8). 1.5 reaches it from the ground; a jump still works.
const PICK_RADIUS := 1.5
const FLY_TIME := 0.9
const FLY_ARC := 2.6

var tint := Color(0.95, 0.3, 0.3)
var panda: Node3D = null
var rng_seed: int = 1

var _state: int = State.HIDDEN
var _home := Vector3.ZERO
var _home_parent: Node = null
var _t: float = 0.0
var _appear_delay: float = 0.0
var _fly_t: float = 0.0
var _fly_from := Vector3.ZERO
var _visual: Node3D
var _glints: MultiMeshInstance3D
var _area: Area3D


func _ready() -> void:
	_build()
	_home_parent = get_parent()
	_home = position
	reset()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _area != null and _area.get_parent() == null:
		_area.free()


func place(p: Vector3) -> void:
	_home = p
	position = p


func reset() -> void:
	if get_parent() != _home_parent and _home_parent != null:
		reparent(_home_parent, false)
	transform = Transform3D(Basis(), _home)
	if _area.get_parent() == null:
		add_child(_area)
	_state = State.HIDDEN
	visible = false
	_visual.scale = Vector3.ONE
	_visual.position = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	_area.set_deferred("monitoring", false)


func is_collected() -> bool:
	return _state == State.FLYING or _state == State.CARRIED


func is_waiting() -> bool:
	return _state == State.WAITING


func appear(delay: float) -> void:
	_state = State.APPEARING
	_appear_delay = delay
	_t = 0.0
	visible = false


func _on_body_entered(body: Node3D) -> void:
	if _state != State.WAITING or not body.is_in_group("players"):
		return
	_state = State.FLYING
	_fly_t = 0.0
	_fly_from = global_position + _visual.position
	_area.set_deferred("monitoring", false)
	MagicFX.burst(self, _fly_from + Vector3.UP * 0.3, tint.lightened(0.4), 20, 4.5, rng_seed + 3)
	AudioManager.play_sfx(&"suitcase", global_position)
	GameManager.request_shake(0.08, 0.1)
	collected.emit(self)


func _physics_process(delta: float) -> void:
	_t += delta
	match _state:
		State.APPEARING:
			if _t >= _appear_delay:
				_state = State.WAITING
				_t = 0.0
				visible = true
				_area.set_deferred("monitoring", true)
				MagicFX.burst(self, global_position + Vector3.UP * 0.4, Color(1.0, 0.95, 0.5), 16, 3.5, rng_seed + 1)
		State.WAITING:
			var pop := clampf(_t / 0.45, 0.0, 1.0)
			var over := 1.0 + 0.35 * sin(pop * PI) * (1.0 - pop)
			_visual.scale = Vector3.ONE * maxf(0.001, pop * over)
			_visual.position.y = 0.55 + 0.1 * sin(_t * 3.0)
			_visual.rotation.y += 1.2 * delta
			_tick_glints(true)
		State.FLYING:
			_fly_t += delta
			var k := clampf(_fly_t / FLY_TIME, 0.0, 1.0)
			var to: Vector3 = panda.carry_anchor.global_position if panda != null else _fly_from
			var p := _fly_from.lerp(to, k) + Vector3.UP * FLY_ARC * 4.0 * k * (1.0 - k)
			global_position = p - _visual.position
			_visual.rotation.y += 9.0 * delta
			_visual.rotation.x = sin(k * TAU) * 0.4
			_tick_glints(false)
			if k >= 1.0:
				_arrive()


func _arrive() -> void:
	_state = State.CARRIED
	if panda == null:
		visible = false
		return
	# The pickup goes away while carried: under a squashing panda its sphere
	# would be scaled non-uniformly, which the physics engine rejects.
	remove_child(_area)
	reparent(panda.carry_anchor, false)
	transform = Transform3D.IDENTITY
	_visual.position = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	_visual.scale = Vector3.ONE * 0.85
	panda.receive_suitcase()
	MagicFX.burst(self, global_position, Color(1.0, 0.7, 0.85), 14, 3.0, rng_seed + 7)
	AudioManager.play_sfx(&"panda_cheer", global_position)


func _tick_glints(on: bool) -> void:
	var mm := _glints.multimesh
	for i in 3:
		var a := _t * 2.4 + TAU * float(i) / 3.0
		var s := (0.09 + 0.05 * sin(_t * 8.0 + float(i) * 2.0)) if on else 0.0001
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s),
			Vector3(cos(a) * 0.55, 0.55 + 0.25 * sin(a * 1.5), sin(a) * 0.55)))


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var b := Kit.VBaker.new()
	# Origin at the handle, so a panda's hand can hold it.
	var body := Vector3(0.58, 0.44, 0.24)
	var c := Vector3(0.0, -0.3, 0.0)
	b.box(body, c, tint)
	b.box(Vector3(body.x + 0.02, 0.06, body.z + 0.02), c + Vector3(0.0, 0.08, 0.0), tint.darkened(0.25))
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			b.box(Vector3(0.09, 0.09, body.z + 0.03), c + Vector3(sx * (body.x * 0.5 - 0.035), sy * (body.y * 0.5 - 0.035), 0.0),
				Color(0.95, 0.85, 0.4))
	# Handle.
	b.beam(Vector3(-0.12, -0.08, 0.0), Vector3(-0.1, 0.0, 0.0), 0.04, Color(0.25, 0.2, 0.2))
	b.beam(Vector3(0.12, -0.08, 0.0), Vector3(0.1, 0.0, 0.0), 0.04, Color(0.25, 0.2, 0.2))
	b.beam(Vector3(-0.1, 0.0, 0.0), Vector3(0.1, 0.0, 0.0), 0.05, Color(0.25, 0.2, 0.2))
	# Travel stickers.
	b.box(Vector3(0.14, 0.12, 0.01), c + Vector3(-0.13, -0.06, body.z * 0.5 + 0.005), Color(1.0, 1.0, 0.95), Vector3(0.0, 0.0, 0.2))
	b.box(Vector3(0.08, 0.06, 0.012), c + Vector3(-0.13, -0.06, body.z * 0.5 + 0.01), Color(0.2, 0.6, 0.95), Vector3(0.0, 0.0, 0.2))
	b.box(Vector3(0.12, 0.12, 0.01), c + Vector3(0.14, 0.05, body.z * 0.5 + 0.005), Color(0.3, 0.8, 0.4), Vector3(0.0, 0.0, -0.3))
	b.star(0.06, 0.028, 0.01, Transform3D(Basis(), c + Vector3(0.14, 0.05, body.z * 0.5 + 0.02)), Color(1.0, 0.9, 0.3))
	var mi := b.bake(Kit.vc("glossy"), "Case")
	_visual.add_child(mi)

	_glints = Kit.multimesh(Kit.sparkle_mesh(), 3, Kit.unshaded(),
		AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 3.0, 2.0)), "Glints")
	for i in 3:
		_glints.multimesh.set_instance_color(i, Color(1.0, 0.95, 0.6))
	add_child(_glints)

	_area = Area3D.new()
	_area.name = "Pickup"
	_area.collision_layer = 0
	_area.collision_mask = PhysicsLayers.PLAYERS
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICK_RADIUS
	cs.shape = sphere
	cs.position = Vector3(0.0, 0.45, 0.0)
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
