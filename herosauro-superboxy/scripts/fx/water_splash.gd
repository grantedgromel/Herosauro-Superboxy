class_name WaterSplash
extends Node3D
## The Douro answering a nine-metre giant: the book's "SPLASH monumental".
##
## A tall white water column with a rounded cap, a wider sheath round its foot,
## a foam ring spreading on the surface, a crown of spray thrown outward and a
## spout of droplets that rains back down. Built for the web renderer: the whole
## splash is TWO MultiMesh draw calls (cylinders: column, sheath, foam ring;
## spheres: cap, crown, droplets), one shared unshaded material per mesh kind
## that is never mutated (per-instance alpha rides the MultiMesh colours), and
## every per-instance parameter is rolled once at spawn into packed arrays, so a
## frame allocates nothing. Seeded from where it lands, like ImpactFX.
##
## `at` is a point ON the water. Local +Y is up; nothing here collides with
## anything, so it can neither push nor hurt a hero.

const GRAVITY := 30.0          # the game's own gravity (adamastor.gd, player_base.gd)
const LIFE := 2.7

## Column: rises to COLUMN_PEAK in RISE_TIME, hangs, then slumps back into the
## river while it spreads. Peak is chosen so the top clears the deck (2 m over a
## river at -15) by about seven metres: from the deck you must SEE it.
const COLUMN_PEAK := 24.0
const COLUMN_RADIUS := 3.6
const RISE_TIME := 0.32
const HANG_TIME := 0.22
const SLUMP_TIME := 1.2
const SHEATH_PEAK := 8.0
const SHEATH_RADIUS := 4.8
const FOAM_FROM := 3.0
const FOAM_TO := 13.5

## Thinner spouts leaning out of the main column: they turn a pipe into the
## lumpy cartoon "SPLASH" silhouette. Each has its own rounded cap.
const SPOUTS := 4
const CROWN := 16
const DROPS := 30
## Sphere instances: 0 the column's cap, 1..SPOUTS the spouts' caps, then the
## crown, then the droplets (FLIGHT_FROM onward fly ballistically).
const FLIGHT_FROM := 1 + SPOUTS
const SPHERES := FLIGHT_FROM + CROWN + DROPS
## Cylinder instances: column, sheath, foam ring, then the spouts.
const CYLINDERS := 3 + SPOUTS

const WHITE := Color(1.0, 1.0, 1.0)
const FOAM := Color(0.90, 0.97, 1.0)
const SHEATH := Color(0.80, 0.93, 1.0)

static var _cyl_mesh: CylinderMesh = null
static var _ball_mesh: SphereMesh = null
static var _mat: StandardMaterial3D = null

var _power: float = 1.0
var _age: float = 0.0
var _col_h: float = 0.0
var _cyl: MultiMesh = null
var _ball: MultiMesh = null
# Per spray instance, rolled once: launch point, launch velocity, size, launch
# delay and how much it stretches along its flight.
var _p0 := PackedVector3Array()
var _v0 := PackedVector3Array()
var _size := PackedFloat32Array()
var _delay := PackedFloat32Array()
var _stretch := PackedFloat32Array()
# Per spout: the horizontal axis it leans about, the lean, height and radius.
var _sp_axis := PackedVector3Array()
var _sp_lean := PackedFloat32Array()
var _sp_h := PackedFloat32Array()
var _sp_r := PackedFloat32Array()


## Drop a splash onto the water at `at` (a point on the surface). `power` scales
## its size; 1.0 is the giant.
static func spawn(from: Node, at: Vector3, power: float = 1.0) -> WaterSplash:
	if from == null or not from.is_inside_tree():
		return null
	var root := from.get_tree().get_first_node_in_group("spawn_root") as Node3D
	if root == null:
		root = from.get_tree().current_scene as Node3D
	if root == null:
		return null
	var fx := WaterSplash.new()
	fx.name = "WaterSplash"
	fx._power = maxf(0.2, power)
	fx._roll(hash("splash|%.2f|%.2f|%.2f" % [at.x, at.y, at.z]))
	root.add_child(fx)
	fx.global_position = at
	return fx


# --- Probe surface ------------------------------------------------------------
# A MultiMesh's instance buffer lives in the RenderingServer and is a no-op under
# --headless (impact_fx.gd's note), so _fx_probe reads the simulation instead.

func age() -> float:
	return _age


## How tall the column stands right now, in metres over the water.
func column_height() -> float:
	return _col_h


func spray_count() -> int:
	return _v0.size()


## The rolled launch velocity of spray instance `i`: what the seed decides.
func spray_launch(i: int) -> Vector3:
	return _v0[i]


func _roll(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var k := _power
	_p0.resize(SPHERES)
	_v0.resize(SPHERES)
	_size.resize(SPHERES)
	_delay.resize(SPHERES)
	_stretch.resize(SPHERES)
	# 0: the cap; positioned by the column, not by flight.
	_size[0] = COLUMN_RADIUS * 0.75 * k
	_sp_axis.resize(SPOUTS)
	_sp_lean.resize(SPOUTS)
	_sp_h.resize(SPOUTS)
	_sp_r.resize(SPOUTS)
	for i in SPOUTS:
		var a := TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / float(SPOUTS)
		# Leaning away from the centre: about the horizontal axis at right angles.
		_sp_axis[i] = Vector3(-sin(a), 0.0, cos(a))
		_sp_lean[i] = rng.randf_range(0.22, 0.42)
		_sp_h[i] = rng.randf_range(0.48, 0.72)
		_sp_r[i] = rng.randf_range(0.30, 0.42) * COLUMN_RADIUS * k
		_size[1 + i] = _sp_r[i] * 0.95
	for i in CROWN:
		var j := FLIGHT_FROM + i
		var a := TAU * float(i) / float(CROWN) + rng.randf_range(-0.12, 0.12)
		var out := Vector3(cos(a), 0.0, sin(a))
		_p0[j] = out * COLUMN_RADIUS * 1.05 * k
		# High enough that the outer ring shows over a parapet 17 m up.
		_v0[j] = out * rng.randf_range(7.0, 11.0) * sqrt(k) + Vector3.UP * rng.randf_range(22.0, 29.0) * sqrt(k)
		_size[j] = rng.randf_range(1.1, 1.7) * k
		_delay[j] = rng.randf_range(0.0, 0.08)
		_stretch[j] = rng.randf_range(1.8, 2.6)
	for i in DROPS:
		var j := FLIGHT_FROM + CROWN + i
		var a := rng.randf_range(0.0, TAU)
		var out := Vector3(cos(a), 0.0, sin(a))
		_p0[j] = out * rng.randf_range(0.0, COLUMN_RADIUS * 0.8) * k
		_v0[j] = out * rng.randf_range(3.0, 10.0) * sqrt(k) + Vector3.UP * rng.randf_range(30.0, 46.0) * sqrt(k)
		_size[j] = rng.randf_range(0.55, 1.1) * k
		_delay[j] = rng.randf_range(0.02, 0.22)
		_stretch[j] = rng.randf_range(1.3, 1.9)


func _ready() -> void:
	_ensure_shared()
	_cyl = _multimesh(_cyl_mesh, CYLINDERS)
	_ball = _multimesh(_ball_mesh, SPHERES)
	_advance(0.0)


func _process(delta: float) -> void:
	_advance(delta)


func _advance(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	var t := _age
	var k := _power

	# --- Column ------------------------------------------------------------
	var h := 0.0
	var spread := 1.0
	if t < RISE_TIME:
		var u := t / RISE_TIME
		h = 1.0 - pow(1.0 - u, 3.0)
	elif t < RISE_TIME + HANG_TIME:
		h = 1.0 + 0.04 * sin(PI * (t - RISE_TIME) / HANG_TIME)
	else:
		var u := clampf((t - RISE_TIME - HANG_TIME) / SLUMP_TIME, 0.0, 1.0)
		h = 1.0 - u * u * (3.0 - 2.0 * u)
		spread = 1.0 + 0.6 * u
	var col_h := maxf(0.01, COLUMN_PEAK * k * h)
	_col_h = col_h
	var col_r := COLUMN_RADIUS * k * spread
	var col_a := 0.95 * (1.0 - _ramp(t, 1.0, 1.75))
	_cyl.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(col_r, col_h, col_r)),
		Vector3(0.0, col_h * 0.5, 0.0)))
	_cyl.set_instance_color(0, Color(WHITE, col_a))

	# Sheath: quicker and squatter, the skirt of water the impact throws first.
	var sh := 0.0
	if t < 0.2:
		sh = 1.0 - pow(1.0 - t / 0.2, 2.0)
	else:
		var u := clampf((t - 0.2) / 0.9, 0.0, 1.0)
		sh = 1.0 - u * u
	var sh_h := maxf(0.01, SHEATH_PEAK * k * sh)
	var sh_r := SHEATH_RADIUS * k * (1.0 + 0.35 * _ramp(t, 0.0, 1.1))
	_cyl.set_instance_transform(1, Transform3D(Basis.from_scale(Vector3(sh_r, sh_h, sh_r)),
		Vector3(0.0, sh_h * 0.5, 0.0)))
	_cyl.set_instance_color(1, Color(SHEATH, 0.8 * (1.0 - _ramp(t, 0.5, 1.2))))

	# Foam ring on the surface, spreading out and thinning.
	var fu := 1.0 - pow(1.0 - clampf(t / 2.3, 0.0, 1.0), 2.0)
	var foam_r := lerpf(FOAM_FROM, FOAM_TO, fu) * k
	_cyl.set_instance_transform(2, Transform3D(Basis.from_scale(Vector3(foam_r, 0.2, foam_r)),
		Vector3(0.0, 0.12, 0.0)))
	_cyl.set_instance_color(2, Color(FOAM, 0.85 * (1.0 - _ramp(t, 1.2, LIFE - 0.1))))

	# --- Spray ---------------------------------------------------------------
	# The cap sits on the column, so the top reads as a rounded cartoon spout
	# rather than a cut pipe.
	var cap_s := _size[0] * spread * (0.4 + 0.6 * h)
	_ball.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(cap_s, cap_s * 0.8, cap_s)),
		Vector3(0.0, col_h, 0.0)))
	_ball.set_instance_color(0, Color(WHITE, col_a))
	# Spouts ride the column's curve, a touch late, each leaning out.
	for i in SPOUTS:
		var sh_frac := h * _sp_h[i]
		var sp_h := maxf(0.01, COLUMN_PEAK * k * sh_frac)
		var lean := Basis(_sp_axis[i], _sp_lean[i] * (0.6 + 0.4 * spread))
		var sp_b := lean * Basis.from_scale(Vector3(_sp_r[i], sp_h, _sp_r[i]))
		_cyl.set_instance_transform(3 + i, Transform3D(sp_b, sp_b * Vector3(0.0, 0.5, 0.0)))
		_cyl.set_instance_color(3 + i, Color(SHEATH, col_a))
		var cs := _size[1 + i] * (0.4 + 0.6 * h)
		_ball.set_instance_transform(1 + i, Transform3D(lean * Basis.from_scale(Vector3(cs, cs * 0.85, cs)),
			sp_b * Vector3(0.0, 1.0, 0.0)))
		_ball.set_instance_color(1 + i, Color(SHEATH, col_a))
	for j in range(FLIGHT_FROM, SPHERES):
		var ft := t - _delay[j]
		if ft <= 0.0:
			_ball.set_instance_transform(j, _hidden())
			continue
		var v: Vector3 = _v0[j] + Vector3.DOWN * GRAVITY * ft
		var p: Vector3 = _p0[j] + _v0[j] * ft + Vector3.DOWN * (0.5 * GRAVITY * ft * ft)
		if p.y < -0.5:
			# Back in the river.
			_ball.set_instance_transform(j, _hidden())
			continue
		var s := _size[j] * (1.0 - 0.45 * _ramp(ft, 0.6, 2.0))
		# Stretched along its flight. A drop falling straight back down needs no
		# turn (and the arc quaternion is undefined for opposite vectors).
		var turn := Basis.IDENTITY
		if v.length() > 0.5:
			var along := v.normalized()
			if absf(along.y) < 0.999:
				turn = Basis(Quaternion(Vector3.UP, along))
		var b := turn * Basis.from_scale(Vector3(s, s * _stretch[j], s))
		_ball.set_instance_transform(j, Transform3D(b, p))
		_ball.set_instance_color(j, Color(WHITE if j < FLIGHT_FROM + CROWN else FOAM, 0.92 * (1.0 - _ramp(ft, 1.4, 2.3))))


static func _ramp(t: float, from: float, to: float) -> float:
	return clampf((t - from) / (to - from), 0.0, 1.0)


static func _hidden() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0.0, -2.0, 0.0))


func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = _mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The instances move every frame and a MultiMesh's own AABB is derived from
	# its buffer (impact_fx.gd's note), so give it one big enough for the spout.
	var reach := 24.0 * _power
	inst.custom_aabb = AABB(Vector3(-reach, -2.0, -reach),
		Vector3(reach * 2.0, (COLUMN_PEAK + 8.0) * _power, reach * 2.0))
	add_child(inst)
	return mm


static func _ensure_shared() -> void:
	if _mat != null:
		return
	# Unshaded, vertex-coloured white: a cartoon splash reads as a clean white
	# shape against the river and the sky, and per-instance alpha is a vertex
	# colour, so the one material is never touched again (ARCHITECTURE rule 7).
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Over 1.0 on purpose, like the giant's 2.2 hit flash: unshaded white goes
	# through the tonemapper, which renders a plain 1.0 as a dull grey pillar.
	_mat.albedo_color = Color(1.7, 1.75, 1.8)
	_mat.disable_receive_shadows = true
	# Fogless: the splash is twenty-odd metres out and the depth fog would grey
	# the one thing that has to read as bright white water.
	_mat.disable_fog = true
	_cyl_mesh = CylinderMesh.new()
	_cyl_mesh.top_radius = 0.7
	_cyl_mesh.bottom_radius = 1.0
	_cyl_mesh.height = 1.0
	_cyl_mesh.radial_segments = 14
	_cyl_mesh.rings = 1
	_cyl_mesh.cap_bottom = false
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = 1.0
	_ball_mesh.height = 2.0
	_ball_mesh.radial_segments = 10
	_ball_mesh.rings = 5
