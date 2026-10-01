extends Node3D
## The stadium chapter's shared effects, all built once and reused:
##
##   * sparkle(): a pool of one-shot star bursts (CPUParticles3D, one draw call
##     each while alive) for every success: a stake snapping, a goblin bowled
##     over, a cup collected, a shelf lighting up;
##   * blobs: ONE MultiMesh of soft contact shadows under every goblin, ball,
##     cup and the dragon, so nothing floats (characters do not cast real
##     shadows, which would double their draw calls in the shadow pass).
##
## Nothing here allocates per frame: bursts are recycled round-robin and the
## blob slots are fixed.

const M := preload("res://scripts/levels/dragao/dragao_mats.gd")

const POOL := 8
const BLOBS := 40
const BLOB_COLOUR := Color(0.02, 0.06, 0.03)

var _bursts: Array[CPUParticles3D] = []
var _next: int = 0
var _blob_mm: MultiMesh
var _blob_used: int = 0
var _hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	# Offsets and colours set as whole arrays: add_point() on a default
	# Gradient leaves its stock black/white end points in play.
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1.0, 0.92, 0.45, 1), Color(1.0, 0.6, 0.2, 0)])
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.15))
	for i in POOL:
		var p := CPUParticles3D.new()
		p.name = "Sparkle%d" % i
		p.emitting = false
		p.one_shot = true
		p.amount = 22
		p.lifetime = 0.95
		p.explosiveness = 0.92
		p.randomness = 0.4
		p.local_coords = false
		p.mesh = quad
		p.material_override = M.sparkle()
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.35
		p.direction = Vector3.UP
		p.spread = 180.0
		p.gravity = Vector3(0, -6.0, 0)
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 6.0
		p.damping_min = 2.0
		p.damping_max = 4.0
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.5
		p.scale_amount_curve = shrink
		p.color_ramp = ramp
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Seeded so two runs of the same frame burst identically.
		p.seed = 0xC0FFEE + i
		p.use_fixed_seed = true
		p.visible = false
		p.finished.connect(p.hide)
		add_child(p)
		_bursts.append(p)

	var plane := QuadMesh.new()
	plane.size = Vector2(1, 1)
	plane.orientation = PlaneMesh.FACE_Y
	_blob_mm = MultiMesh.new()
	_blob_mm.transform_format = MultiMesh.TRANSFORM_3D
	_blob_mm.use_colors = true
	_blob_mm.mesh = plane
	_blob_mm.instance_count = BLOBS
	for i in BLOBS:
		_blob_mm.set_instance_transform(i, _hidden)
		_blob_mm.set_instance_color(i, Color(BLOB_COLOUR, 0.0))
	_blob_mm.custom_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ContactShadows"
	mmi.multimesh = _blob_mm
	mmi.material_override = M.blob()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A burst of twinkling stars at `at`. `power` scales the speed and size.
func sparkle(at: Vector3, color: Color = Color(1, 1, 1), power: float = 1.0) -> void:
	var p := _bursts[_next]
	_next = (_next + 1) % POOL
	p.global_position = at
	p.color = color
	p.initial_velocity_min = 2.0 * power
	p.initial_velocity_max = 5.5 * power
	p.scale_amount_max = 1.2 + 0.4 * power
	p.visible = true
	p.restart()


## Reserve a contact-shadow slot. Returns -1 when the pool is spent.
func blob_alloc() -> int:
	if _blob_used >= BLOBS:
		return -1
	_blob_used += 1
	return _blob_used - 1


## Place shadow `id` on the ground under `pos`. It fades and shrinks with the
## height above the ground (`pos.y - ground`), so a tumbling goblin's shadow
## stays planted while the goblin flies.
func blob_set(id: int, pos: Vector3, radius: float, strength: float = 1.0, ground: float = 0.0) -> void:
	if id < 0:
		return
	var h := maxf(pos.y - ground, 0.0)
	var k := clampf(1.0 - h / 6.0, 0.15, 1.0)
	var r := radius * (0.7 + 0.3 * k) * 2.0
	_blob_mm.set_instance_transform(id, Transform3D(Basis().scaled(Vector3(r, 1, r)),
		Vector3(pos.x, ground + 0.025, pos.z)))
	_blob_mm.set_instance_color(id, Color(BLOB_COLOUR, 0.72 * k * strength))


func blob_hide(id: int) -> void:
	if id < 0:
		return
	_blob_mm.set_instance_transform(id, _hidden)
