extends Node3D
## The goblins' white getaway van, parked across a corner of the pitch by the
## gate it drove in through. In the finale the dragon's puff turns it sooty and
## it smokes, cartoon-style (nothing burns, nobody is hurt: the goblins sit down
## dazed and the pterodactyls take them for a bath in the river).
##
## Faces +Z (its nose); the level places and turns it. A solid on BLOCKERS (heroes
## walk round it, the camera arm passes) and a low one on WORLD for balls.

const VC := preload("res://scripts/levels/dragao/vc_baker.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")
const L := preload("res://scripts/levels/dragao/dragao_layout.gd")

var level = null  # the dragao level (untyped: no cyclic preload)
var sooty: bool = false
var _body: MeshInstance3D
var _wheels: MeshInstance3D
var _smoke: CPUParticles3D
var _rock: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	_build()
	reset()


func reset() -> void:
	sooty = false
	_body.material_override = M.gloss()
	_smoke.emitting = false
	_rock = 0.0
	_body.rotation = Vector3.ZERO


## Where the goblins pile in and out: just behind the back doors.
func door_point() -> Vector3:
	return to_global(Vector3(0, 0, -L.VAN_LEN * 0.5 - 0.9))


## Spots in a little crowd round the back of the van for the finale.
func huddle_point(i: int) -> Vector3:
	var a := -1.3 + 0.52 * float(i % 6)
	var r := 2.2 + 0.7 * float(i / 6)
	return to_global(Vector3(sin(a) * r * 1.2, 0, -L.VAN_LEN * 0.5 - cos(a) * r * 0.6 - 0.4))


func scorch() -> void:
	sooty = true
	_body.material_override = M.soot()
	_smoke.emitting = true
	_rock = 1.0


func _physics_process(delta: float) -> void:
	_clock += delta
	if _rock > 0.001:
		_rock = maxf(0.0, _rock - delta * 0.6)
		_body.rotation = Vector3(sin(_clock * 14.0) * 0.03 * _rock, 0, sin(_clock * 11.0) * 0.04 * _rock)


func _build() -> void:
	var len := L.VAN_LEN
	var wid := L.VAN_WID
	var hgt := L.VAN_HGT
	var white := Color(0.95, 0.96, 0.97)
	var glass := Color(0.16, 0.22, 0.34)
	var dark := Color(0.12, 0.12, 0.14)
	var b := VC.new()
	var paint := Color(0.86, 0.88, 0.92)
	# Lower body the whole length, a taller cargo box behind the cab.
	b.box(Vector3(wid, 1.25, len), Transform3D(Basis(), Vector3(0, 0.45 + 0.625, 0)), paint)
	b.box(Vector3(wid, 0.95, len * 0.74), Transform3D(Basis(), Vector3(0, 1.7 + 0.475, -len * 0.13)), paint)
	# A slanted bonnet-to-roof wedge with the windscreen in it.
	var front_z := len * 0.24
	var wedge := Basis(Vector3.RIGHT, -0.62)
	var wedge_c := Vector3(0, 1.98, front_z + 0.05)
	b.box(Vector3(wid - 0.02, 0.95, 0.9), Transform3D(wedge, wedge_c), paint)
	b.box(Vector3(wid - 0.26, 0.78, 0.04), Transform3D(wedge, wedge_c + wedge * Vector3(0, 0.02, 0.46)), glass)
	# Blue roof rack bar and a little orange beacon (cheeky, not a siren).
	b.box(Vector3(wid - 0.3, 0.08, len * 0.6), Transform3D(Basis(), Vector3(0, 2.7, -len * 0.15)), Color(0.2, 0.25, 0.35))
	for sx in [-1.0, 1.0]:
		var side_x: float = sx * (wid * 0.5 + 0.012)
		b.box(Vector3(0.04, 0.55, 0.85), Transform3D(Basis(), Vector3(side_x, 2.1, len * 0.12)), glass)
		b.box(Vector3(0.04, 0.5, 0.6), Transform3D(Basis(), Vector3(side_x, 1.35, len * 0.36)), glass)
		# A blue and a red stripe down each side (no lettering).
		b.box(Vector3(0.04, 0.2, len * 0.9), Transform3D(Basis(), Vector3(side_x, 1.15, 0)), Color(0.1, 0.35, 0.85))
		b.box(Vector3(0.04, 0.09, len * 0.9), Transform3D(Basis(), Vector3(side_x, 0.98, 0)), Color(0.88, 0.15, 0.15))
		# Wheel arches.
		for sz in [-1.0, 1.0]:
			b.box(Vector3(0.05, 0.62, 1.05), Transform3D(Basis(), Vector3(side_x, 0.62, sz * len * 0.32)), dark)
		# Headlights, tail lights, back windows.
		b.box(Vector3(0.42, 0.24, 0.05), Transform3D(Basis(), Vector3(sx * 0.7, 0.95, len * 0.5 + 0.01)), Color(1.0, 0.95, 0.7))
		b.box(Vector3(0.22, 0.34, 0.05), Transform3D(Basis(), Vector3(sx * 0.92, 1.2, -len * 0.5 - 0.01)), Color(0.9, 0.12, 0.1))
		b.box(Vector3(0.75, 0.55, 0.05), Transform3D(Basis(), Vector3(sx * 0.45, 2.15, -len * 0.5 - 0.01)), glass)
	# Grille, door seam, bumpers.
	b.box(Vector3(0.9, 0.3, 0.05), Transform3D(Basis(), Vector3(0, 0.95, len * 0.5 + 0.01)), dark)
	b.box(Vector3(0.04, 2.0, 0.05), Transform3D(Basis(), Vector3(0, 1.6, -len * 0.5 - 0.02)), Color(0.55, 0.57, 0.6))
	b.box(Vector3(wid + 0.06, 0.22, 0.22), Transform3D(Basis(), Vector3(0, 0.5, len * 0.5)), dark)
	b.box(Vector3(wid + 0.06, 0.22, 0.22), Transform3D(Basis(), Vector3(0, 0.5, -len * 0.5)), dark)
	_body = b.commit(M.gloss(), "VanBody", true)
	add_child(_body)

	var wb := VC.new()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * (wid * 0.5 - 0.15), 0.42, sz * len * 0.32)
			wb.cylinder(0.42, 0.42, 0.32, Transform3D(Basis(Vector3.BACK, PI * 0.5), c), dark, 14)
			wb.cylinder(0.2, 0.2, 0.34, Transform3D(Basis(Vector3.BACK, PI * 0.5), c), Color(0.75, 0.77, 0.8), 10)
	_wheels = wb.commit(M.skin(), "Wheels", true)
	add_child(_wheels)

	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.emitting = false
	_smoke.amount = 26
	_smoke.lifetime = 2.6
	_smoke.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	_smoke.mesh = q
	_smoke.material_override = M.puff()
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_smoke.emission_box_extents = Vector3(wid * 0.4, 0.2, len * 0.35)
	_smoke.direction = Vector3.UP
	_smoke.spread = 25.0
	_smoke.gravity = Vector3(0.3, 0.9, 0)
	_smoke.initial_velocity_min = 0.8
	_smoke.initial_velocity_max = 1.8
	_smoke.scale_amount_min = 0.8
	_smoke.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 2.6))
	_smoke.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	ramp.colors = PackedColorArray([Color(0.35, 0.34, 0.36, 0.0), Color(0.42, 0.42, 0.45, 0.7), Color(0.62, 0.62, 0.68, 0.0)])
	_smoke.color_ramp = ramp
	_smoke.use_fixed_seed = true
	_smoke.seed = 0x5300
	_smoke.position = Vector3(0, hgt + 0.1, 0)
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_smoke)

	var heroes_block := StaticBody3D.new()
	heroes_block.name = "Solid"
	heroes_block.collision_layer = PhysicsLayers.BLOCKERS
	heroes_block.collision_mask = 0
	SceneryKit.solid_shape(heroes_block, Vector3(wid, hgt, len), Vector3(0, hgt * 0.5, 0))
	add_child(heroes_block)
	SceneryKit.solid(self, "BallStop", Vector3(wid, 1.0, len), Vector3(0, 0.5, 0))
