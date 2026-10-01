extends MultiMeshInstance3D
## Transient magic for chapter "pandas": one MultiMesh per effect, so a burst of
## thirty sparkles is one draw call. Three shapes:
##
##   burst()  sparkles thrown out of a point (a hit on a door star, a pile
##            clearing, a suitcase found);
##   ring()   a ring of green sparkles sweeping UP a facade (the repair);
##   petals() a shower of petals falling and fluttering (the house pops).
##
## Deterministic: every effect takes a seed, positions integrate accumulated
## delta, and nothing allocates per frame (the state arrays are sized once).
## Parented to the "spawn_root" group, which main.gd clears every run.

const Kit := preload("res://scripts/levels/pandas/pandas_kit.gd")

enum Kind { BURST, RING, PETALS }

const GRAVITY := 9.0

var kind: int = Kind.BURST
var life: float = 1.0
var _t: float = 0.0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _spin := PackedFloat32Array()
var _size := PackedFloat32Array()
var _cols := PackedColorArray()
# Ring parameters.
var _rx: float = 1.0
var _rz: float = 1.0
var _height: float = 1.0
var _z_front: float = 0.0


static func burst(from: Node, at: Vector3, color: Color, count: int = 18,
		speed: float = 4.5, rng_seed: int = 1, size: float = 0.16) -> Node3D:
	var fx := _make(from, Kind.BURST, count, Kit.sparkle_mesh(), Kit.unshaded(), 0.9)
	if fx == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in count:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 1.3),
			rng.randf_range(-1.0, 1.0)).normalized()
		fx._pos[i] = Vector3.ZERO
		fx._vel[i] = dir * speed * rng.randf_range(0.55, 1.1)
		fx._spin[i] = rng.randf_range(-9.0, 9.0)
		fx._size[i] = size * rng.randf_range(0.7, 1.35)
		var tint := color.lerp(Color(1.0, 1.0, 0.85), rng.randf_range(0.0, 0.45))
		fx._cols[i] = tint
		fx.multimesh.set_instance_color(i, tint)
	fx.global_position = at
	return fx


## `centre` is the foot of the facade's middle, `basis_yaw` its facing. The
## ring is an ellipse rx wide and rz deep, rising to `height` over `duration`.
static func ring(from: Node, centre: Vector3, yaw: float, rx: float, rz: float,
		height: float, duration: float = 1.1, rng_seed: int = 2) -> Node3D:
	var count := 30
	var fx := _make(from, Kind.RING, count, Kit.sparkle_mesh(), Kit.unshaded(), duration + 0.35)
	if fx == null:
		return null
	fx._rx = rx
	fx._rz = rz
	fx._height = height
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in count:
		fx._spin[i] = TAU * float(i) / float(count) + rng.randf_range(-0.08, 0.08)
		fx._size[i] = rng.randf_range(0.16, 0.3)
		var c := Color(0.45, 1.0, 0.45).lerp(Color(0.95, 1.0, 0.6), rng.randf_range(0.0, 0.6))
		fx._cols[i] = c
		fx.multimesh.set_instance_color(i, c)
	fx.global_position = centre
	fx.rotation.y = yaw
	return fx


## Petals bursting off a facade `width` wide, from `at` (the facade's middle).
static func petals(from: Node, at: Vector3, yaw: float, width: float, height: float,
		rng_seed: int = 3) -> Node3D:
	var count := 44
	var fx := _make(from, Kind.PETALS, count, Kit.petal_mesh(), Kit.petal_material(), 2.8)
	if fx == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var palette := [Color(1.0, 0.55, 0.7), Color(1.0, 0.85, 0.3), Color(1.0, 1.0, 0.95),
		Color(0.95, 0.4, 0.45), Color(0.75, 0.55, 1.0)]
	for i in count:
		fx._pos[i] = Vector3(rng.randf_range(-width * 0.5, width * 0.5),
			rng.randf_range(height * 0.25, height), 0.3)
		fx._vel[i] = Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(1.5, 4.0),
			rng.randf_range(1.5, 4.5))
		fx._spin[i] = rng.randf_range(0.0, TAU)
		fx._size[i] = rng.randf_range(0.09, 0.15)
		var c: Color = palette[i % palette.size()]
		fx._cols[i] = c
		fx.multimesh.set_instance_color(i, c)
	fx.global_position = at
	fx.rotation.y = yaw
	return fx


static func _make(from: Node, p_kind: int, count: int, mesh: Mesh, mat: Material,
		p_life: float) -> Node3D:
	if from == null or not from.is_inside_tree():
		return null
	var parent := Kit.spawn_parent(from)
	if parent == null:
		return null
	var fx: MultiMeshInstance3D = (load("res://scripts/levels/pandas/magic_fx.gd") as GDScript).new()
	var bounds := AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 20.0, 24.0))
	var proto := Kit.multimesh(mesh, count, mat, bounds, "MagicFX")
	fx.multimesh = proto.multimesh
	fx.material_override = mat
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proto.free()
	fx.set("kind", p_kind)
	fx.set("life", p_life)
	fx.call("_alloc", count)
	parent.add_child(fx)
	return fx


func _alloc(count: int) -> void:
	_pos.resize(count)
	_vel.resize(count)
	_spin.resize(count)
	_size.resize(count)
	_cols.resize(count)


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	var mm := multimesh
	var n := _pos.size()
	match kind:
		Kind.BURST:
			var fade := clampf(1.0 - (_t - life * 0.55) / (life * 0.45), 0.0, 1.0)
			for i in n:
				var v := _vel[i]
				v.y -= GRAVITY * 0.55 * delta
				v *= maxf(0.0, 1.0 - 1.8 * delta)
				_vel[i] = v
				_pos[i] += v * delta
				var s := _size[i] * fade * (1.0 + 0.35 * sin(_t * 24.0 + float(i)))
				var b := Basis(Vector3.UP, _spin[i] * _t).scaled(Vector3.ONE * maxf(s, 0.0001))
				mm.set_instance_transform(i, Transform3D(b, _pos[i]))
		Kind.RING:
			var rise := clampf(_t / maxf(0.01, life - 0.35), 0.0, 1.0)
			var y := _height * (1.0 - pow(1.0 - rise, 2.0))
			var fade := clampf((life - _t) / 0.35, 0.0, 1.0)
			for i in n:
				var a := _spin[i] + _t * 2.2
				var wob := 0.15 * sin(_t * 9.0 + float(i) * 1.7)
				var p := Vector3(cos(a) * _rx, y + wob, sin(a) * _rz)
				var s := _size[i] * fade * (0.8 + 0.4 * sin(_t * 18.0 + float(i)))
				var b := Basis(Vector3.UP, a * 3.0).scaled(Vector3.ONE * maxf(s, 0.0001))
				mm.set_instance_transform(i, Transform3D(b, p))
		Kind.PETALS:
			var fade := clampf((life - _t) / 0.6, 0.0, 1.0)
			for i in n:
				var v := _vel[i]
				v.y = maxf(v.y - GRAVITY * 0.6 * delta, -1.3)
				v.x *= maxf(0.0, 1.0 - 0.9 * delta)
				v.z *= maxf(0.0, 1.0 - 0.9 * delta)
				_vel[i] = v
				var p := _pos[i] + v * delta
				p.x += sin(_t * 5.0 + _spin[i]) * 0.6 * delta
				if p.y < 0.03:
					p.y = 0.03
				_pos[i] = p
				var tilt := Basis(Vector3(1.0, 0.0, 0.3).normalized(), sin(_t * 6.0 + _spin[i]) * 0.9)
				var b := (Basis(Vector3.UP, _spin[i] + _t * 2.0) * tilt).scaled(Vector3.ONE * _size[i] * maxf(fade, 0.0001))
				mm.set_instance_transform(i, Transform3D(b, p))
