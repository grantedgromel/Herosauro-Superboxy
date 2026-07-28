class_name HitVignette
extends Control
## Screen-edge feedback for the hero's condition.
##
## Two layers over the same radial gradient:
##   FLASH    a single red bloom at the edges when a hit lands. Damage taken in a
##            third-person game is easy to miss when the camera is behind you and
##            the health bar is in a corner — this puts it in the centre of vision
##            without covering anything.
##   SUSTAIN  a slow throb that fades in below a health threshold and stays. It is
##            the ambient "you are about to die" signal.
##
## Both are pure alpha over a gradient texture, so this costs one extra
## transparent quad and works identically on Forward+ and gl_compatibility.

const FLASH_IN := 0.05
const FLASH_OUT := 0.42
const SUSTAIN_MAX_ALPHA := 0.34

var _flash: TextureRect
var _sustain: TextureRect
var _sustain_level: float = 0.0
var _pulse: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_sustain = _layer(UIStyle.DANGER.darkened(0.25), 0.30)
	_flash = _layer(UIStyle.DANGER, 0.38)

	set_process(false)


func _layer(tint: Color, inner_stop: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = UIStyle.vignette_texture(tint, inner_stop)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = 0.0
	add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


## One bloom. `strength` in 0..1 — scale it by the size of the hit so a chip and
## a slam do not read the same.
func flash(strength: float = 1.0, tint: Color = UIStyle.DANGER) -> void:
	if _flash == null:
		return
	var gt := _flash.texture as GradientTexture2D
	if gt and gt.gradient:
		var g := gt.gradient
		g.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
		g.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
		g.set_color(2, Color(tint.r, tint.g, tint.b, 1.0))
	var peak := clampf(strength, 0.0, 1.0) * 0.72
	var t := create_tween()
	t.tween_property(_flash, "modulate:a", peak, FLASH_IN)
	t.tween_property(_flash, "modulate:a", 0.0, FLASH_OUT).set_trans(Tween.TRANS_SINE)


## 0 = healthy (no edge glow), 1 = critical. Drives the sustained throb.
func set_danger(level: float) -> void:
	_sustain_level = clampf(level, 0.0, 1.0)
	set_process(_sustain_level > 0.0)
	if _sustain_level <= 0.0 and _sustain:
		_sustain.modulate.a = 0.0


func _process(delta: float) -> void:
	_pulse += delta
	if _sustain:
		var throb := 0.55 + 0.45 * sin(_pulse * 3.6)
		_sustain.modulate.a = SUSTAIN_MAX_ALPHA * _sustain_level * throb
