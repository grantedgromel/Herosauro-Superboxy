extends Node3D
## Slam telegraph: a flat danger-zone that flares on the deck during Adamastor's
## slam wind-up, warning the heroes of the incoming shockwave so the attack reads
## clearly and can be dodged on reaction. Purely cosmetic — the shockwave spawned
## on impact still deals the damage. Self-frees after `duration` (≈ the wind-up),
## right as the blast lands.
##
## Spawned by AdamastorStateMachine at the boss's feet, at the same position and
## radius the shockwave will use, so the warning footprint matches the blast.

var radius: float = 15.0
var duration: float = 0.5

var _fill_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _rim: MeshInstance3D


func setup(p_radius: float, p_duration: float) -> void:
	radius = p_radius
	duration = p_duration


func _ready() -> void:
	# Translucent red danger fill that ramps in over the wind-up.
	_fill_mat = _make_mat(Color(0.95, 0.2, 0.12, 0.0))
	add_child(_flat_disc(radius, _fill_mat))

	# A brighter rim that races outward to read as the incoming wavefront.
	_rim_mat = _make_mat(Color(1.0, 0.5, 0.18, 0.85))
	_rim = _flat_disc(radius, _rim_mat)
	_rim.scale = Vector3(0.05, 1.0, 0.05)
	add_child(_rim)

	_play()


func _make_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED        # visible whatever the camera angle
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = Color(col.r, col.g, col.b)
	m.emission_energy_multiplier = 1.6
	return m


## A thin coin lying flat on the deck (hovering a hair above it to avoid z-fighting).
func _flat_disc(r: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.06
	mesh.radial_segments = 48
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = 0.05
	return mi


func _play() -> void:
	var t := create_tween()
	t.set_parallel(true)
	# Fill ramps to a clear warning over most of the wind-up.
	t.tween_property(_fill_mat, "albedo_color:a", 0.5, duration * 0.6)
	# Rim sweeps out to the blast radius and fades, selling the wavefront.
	t.tween_property(_rim, "scale", Vector3.ONE, duration)
	t.tween_property(_rim_mat, "albedo_color:a", 0.0, duration)
	t.chain().tween_callback(queue_free)
