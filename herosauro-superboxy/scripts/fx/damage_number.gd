extends Label3D
## Floating damage number: pops above a hit, drifts up with a little sideways
## scatter, and fades out. Billboarded so it always faces the camera. Purely
## cosmetic. Spawn it, position it, then call play(amount). Self-frees.

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	font_size = 120
	outline_size = 28
	outline_modulate = Color(0, 0, 0, 0.85)
	pixel_size = 0.02


func play(amount: int, color: Color = Color(1.0, 0.95, 0.55)) -> void:
	text = str(amount)
	modulate = color
	var start := position
	var end := start + Vector3(randf_range(-1.2, 1.2), 4.5, 0.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "position", end, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, 0.55).set_delay(0.25)
	t.chain().tween_callback(queue_free)
