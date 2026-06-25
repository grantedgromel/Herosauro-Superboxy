extends Node3D
## Impact marker: a converging ground telegraph that warns where an incoming
## hazard will land — a lobbed rock's landing spot, or each step of a charge lane.
## A bright ring shrinks inward to the point over `duration`, so the heroes can
## read the timing and clear the spot. Purely cosmetic; the hazard deals the
## damage. Self-frees when the wind-up elapses (≈ when the hazard arrives).

var radius: float = 2.5
var duration: float = 0.8

var _fill_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _ring: MeshInstance3D


func setup(p_radius: float, p_duration: float) -> void:
	radius = maxf(0.2, p_radius)
	duration = maxf(0.05, p_duration)


func _ready() -> void:
	_fill_mat = _make_mat(Color(0.95, 0.25, 0.12, 0.30))
	add_child(_flat_disc(radius, _fill_mat))

	# A bright ring that converges inward to mark the moment of impact.
	_ring_mat = _make_mat(Color(1.0, 0.55, 0.2, 0.9))
	_ring = _flat_disc(radius, _ring_mat)
	add_child(_ring)

	_play()


func _make_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	mesh.height = 0.05
	mesh.radial_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = 0.05
	return mi


func _play() -> void:
	_ring.scale = Vector3.ONE
	var t := create_tween()
	t.set_parallel(true)
	# Ring shrinks toward the centre as the hazard closes in.
	t.tween_property(_ring, "scale", Vector3(0.08, 1.0, 0.08), duration)
	# Danger fill ramps up so the warning peaks just before impact.
	t.tween_property(_fill_mat, "albedo_color:a", 0.6, duration)
	t.chain().tween_callback(queue_free)
