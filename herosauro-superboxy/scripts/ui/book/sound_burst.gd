class_name SoundBurst
extends Control
## A comic sound-word, CRASH! POW! SPLASH!, on a jagged burst: the loudest
## thing on a picture-book page. Drawn in code with the display face.

const FILL := Color("ffd84d")
const RIM := Color("ff6a2c")
const INK := Color(0.10, 0.07, 0.10, 0.95)

var text: String = "POW!"
var font_px: int = 96
var tilt: float = -9.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_fit()


func _fit() -> void:
	var f := UIStyle.TITLE_FONT
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	size = Vector2(maxf(260.0, w + 150.0), font_px * 2.1)
	pivot_offset = size * 0.5
	rotation_degrees = tilt
	queue_redraw()


## Bounce in. With reduced motion it simply appears.
func pop(reduced: bool) -> void:
	_fit()
	position -= size * 0.5
	if reduced:
		return
	scale = Vector2(0.2, 0.2)
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var c := size * 0.5
	var pts := PackedVector2Array()
	var spikes := 18
	for i in spikes * 2:
		var a := TAU * i / (spikes * 2)
		var r := 1.0 if i % 2 == 0 else 0.74
		# Uneven spikes, deterministically, so it looks drawn rather than generated.
		r *= 1.0 + 0.08 * sin(i * 2.3)
		pts.append(c + Vector2(cos(a) * c.x, sin(a) * c.y) * r)
	var outer := pts.duplicate()
	for i in outer.size():
		outer[i] = c + (outer[i] - c) * 1.06
	draw_colored_polygon(outer, RIM)
	draw_colored_polygon(pts, FILL)
	var closed := outer.duplicate()
	closed.append(outer[0])
	draw_polyline(closed, INK, 6.0, true)

	var f := UIStyle.TITLE_FONT
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px)
	var at := c + Vector2(-sz.x * 0.5, font_px * 0.36)
	draw_string_outline(f, at + Vector2(5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px,
		16, Color(0, 0, 0, 0.35))
	draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 16, INK)
	draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Color("e8402e"))
