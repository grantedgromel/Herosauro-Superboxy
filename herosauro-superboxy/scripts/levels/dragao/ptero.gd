extends Node3D
## One of Herosauro's glowing green energy pterodactyls: his dino magic in a
## friendlier shape. Summoned by the level when a goblin has been bowled over
## twice: it swoops down out of the night sky, scoops the dizzy goblin up in
## its feet and flaps away with it, off toward the river for the bath the book
## promises (pages d12-d13), shrinking into a twinkle.
##
## Body, two wings and a crest as a few self-lit parts; the wings flap from an
## accumulated clock. Pooled by the level, so summoning never allocates.

const VC := preload("res://scripts/levels/dragao/vc_baker.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")

const IN_TIME := 1.1
const OUT_TIME := 2.4
const ENERGY := Color(0.36, 0.95, 0.42)
const ENERGY_DEEP := Color(0.08, 0.62, 0.24)

static var _body_mesh: Mesh
static var _wing_mesh: Mesh

var level = null  # the dragao level (untyped: no cyclic preload)
var busy: bool = false
var _goblin: Node3D = null
var _t: float = 0.0
var _clock: float = 0.0
var _phase: int = 0
var _from := Vector3.ZERO
var _grab := Vector3.ZERO
var _to := Vector3.ZERO
var _visual: Node3D
var _wing_l: MeshInstance3D
var _wing_r: MeshInstance3D
var _trail_in: float = 0.0


func _ready() -> void:
	_build()
	visible = false
	set_physics_process(false)


func swoop(goblin: Node3D) -> void:
	busy = true
	_goblin = goblin
	_t = 0.0
	_phase = 0
	_grab = goblin.global_position + Vector3.UP * 1.55
	var away := Vector3(_grab.x, 0, _grab.z).normalized()
	if away.length() < 0.5:
		away = Vector3.RIGHT
	_from = _grab + Vector3(-away.x * 14.0, 15.0, -away.z * 14.0 + 6.0)
	_to = _grab + Vector3(away.x * 30.0, 28.0, away.z * 30.0 + 12.0)
	global_position = _from
	scale = Vector3.ONE
	visible = true
	set_physics_process(true)


## Back to the pool mid-flight (PLAY AGAIN).
func cancel() -> void:
	busy = false
	_goblin = null
	visible = false
	set_physics_process(false)


## Where a carried goblin hangs.
func talon_global() -> Vector3:
	return global_position + Vector3.DOWN * 1.45


func _physics_process(delta: float) -> void:
	_t += delta
	_clock += delta
	var flap := sin(_clock * (9.0 if _phase == 1 else 6.0))
	_wing_l.rotation = Vector3(0, 0, 0.15 + flap * 0.75)
	_wing_r.rotation = Vector3(0, 0, -0.15 - flap * 0.75)
	_visual.position = Vector3.UP * flap * -0.12
	var prev := global_position
	if _phase == 0:
		var k := clampf(_t / IN_TIME, 0.0, 1.0)
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		var mid := (_from + _grab) * 0.5 + Vector3.DOWN * 3.0
		global_position = _from.lerp(mid, e).lerp(mid.lerp(_grab, e), e)
		if k >= 1.0:
			_phase = 1
			_t = 0.0
			if _goblin != null and is_instance_valid(_goblin):
				_goblin.call("lift_by", self)
				AudioManager.play_sfx(&"goblin_giggle", global_position)
			if level != null:
				level.fx.sparkle(_grab, ENERGY, 1.3)
	else:
		var k2 := clampf(_t / OUT_TIME, 0.0, 1.0)
		var e2 := k2 * k2
		global_position = _grab.lerp(_to, e2) + Vector3.UP * sin(k2 * PI) * 2.0
		var s := 1.0 - smoothstep(0.55, 1.0, k2) * 0.9
		scale = Vector3.ONE * s
		if k2 >= 1.0:
			if _goblin != null and is_instance_valid(_goblin):
				_goblin.call("carry_done")
			if level != null:
				level.fx.sparkle(global_position, ENERGY, 1.0)
			_goblin = null
			busy = false
			visible = false
			set_physics_process(false)
			return
	var v := global_position - prev
	if v.length() > 0.001:
		var yaw := atan2(v.x, v.z)
		var pitch := -atan2(v.y, Vector2(v.x, v.z).length()) * 0.5
		rotation = Vector3(pitch, yaw, sin(_clock * 3.0) * 0.12)
	_trail_in -= delta
	if _trail_in <= 0.0 and level != null:
		_trail_in = 0.28
		level.fx.sparkle(global_position, ENERGY, 0.35)


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if _body_mesh == null:
		var b := VC.new()
		b.sphere(Vector3(0, 0, 0), Vector3(0.38, 0.36, 0.85), ENERGY, Basis(), 14, 10)
		b.sphere(Vector3(0, 0.25, 0.85), Vector3(0.3, 0.28, 0.34), ENERGY, Basis(), 12, 8)       # head
		b.cylinder(0.0, 0.16, 0.85, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.15), Vector3(0, 0.18, 1.45)),
			ENERGY.lightened(0.3), 10)                                                          # beak
		b.cylinder(0.0, 0.14, 0.7, Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0, 0.6, 0.55)), ENERGY_DEEP, 8)  # crest
		b.cylinder(0.0, 0.12, 0.9, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 - 0.2), Vector3(0, 0.0, -1.1)), ENERGY_DEEP, 8)
		for sx in [-1.0, 1.0]:
			b.sphere(Vector3(sx * 0.17, 0.36, 1.0), Vector3.ONE * 0.08, Color(1, 1, 1), Basis(), 8, 6)
			b.sphere(Vector3(sx * 0.19, 0.37, 1.05), Vector3.ONE * 0.04, Color(0.05, 0.25, 0.1), Basis(), 6, 4)
			b.cylinder(0.03, 0.05, 0.9, Transform3D(Basis(), Vector3(sx * 0.18, -0.75, 0.1)), ENERGY_DEEP, 6)  # legs
			b.sphere(Vector3(sx * 0.18, -1.2, 0.18), Vector3(0.1, 0.06, 0.16), ENERGY_DEEP, Basis(), 8, 4)
		_body_mesh = b.mesh()
		var w := VC.new()
		# A broad membrane wing along +X, three finger points at the trailing edge.
		var root_f := Vector3(0, 0.05, 0.45)
		var root_b := Vector3(0, 0.0, -0.45)
		var tip := Vector3(2.6, 0.25, 0.1)
		var mid1 := Vector3(1.8, 0.0, -0.75)
		var mid2 := Vector3(0.9, 0.0, -0.7)
		w.tri2(root_f, tip, mid1, ENERGY)
		w.tri2(root_f, mid1, mid2, ENERGY.darkened(0.05))
		w.tri2(root_f, mid2, root_b, ENERGY.darkened(0.1))
		w.capsule(0.07, 2.7, Transform3D(Basis(Vector3.BACK, PI * 0.5 - 0.1), Vector3(1.3, 0.13, 0.28)), ENERGY.lightened(0.35), 8)
		_wing_mesh = w.mesh()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body_mesh
	body.material_override = M.lit(1.15)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(body)
	_wing_r = MeshInstance3D.new()
	_wing_r.name = "WingR"
	_wing_r.mesh = _wing_mesh
	_wing_r.material_override = M.lit(1.15)
	_wing_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wing_r.position = Vector3(0.3, 0.15, 0.1)
	_visual.add_child(_wing_r)
	_wing_l = MeshInstance3D.new()
	_wing_l.name = "WingL"
	_wing_l.mesh = _wing_mesh
	_wing_l.material_override = M.lit(1.15)
	_wing_l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wing_l.position = Vector3(-0.3, 0.15, 0.1)
	_wing_l.scale = Vector3(-1, 1, 1)
	_visual.add_child(_wing_l)
	var halo := MeshInstance3D.new()
	halo.name = "Aura"
	var q := QuadMesh.new()
	q.size = Vector2(3.6, 3.6)
	halo.mesh = q
	halo.material_override = M.halo(Color(0.35, 1.0, 0.45, 0.22))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(halo)
