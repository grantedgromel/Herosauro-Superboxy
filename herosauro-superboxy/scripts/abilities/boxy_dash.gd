extends MeshInstance3D
## Boxy Dash ghost trail: a translucent red after-image left behind as Super Boxy
## dashes. Super Boxy sets the ghost's global_transform when spawning it; this
## script fades the silhouette out and frees itself.

const FADE_TIME := 0.3
const START_ALPHA := 0.55
const GHOST_COLOR := Color(0.86, 0.12, 0.12)   # red

var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(GHOST_COLOR.r, GHOST_COLOR.g, GHOST_COLOR.b, START_ALPHA)
	_mat.emission_enabled = true
	_mat.emission = GHOST_COLOR
	_mat.emission_energy_multiplier = 1.5
	material_override = _mat

	var tween := create_tween()
	tween.tween_property(_mat, "albedo_color:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)
