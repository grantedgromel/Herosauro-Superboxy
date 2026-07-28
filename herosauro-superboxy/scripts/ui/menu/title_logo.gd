extends Control
## The game's logo lockup: two stacked display lines, a gold rule and a
## letterspaced strapline, treated so it survives being laid over a bright
## golden-hour sky.
##
## Four things do that work, in order of how much they matter:
##
##   1. A hard drop shadow behind every display line. The outline UIStyle already
##      puts on its titles holds an edge against mid tones; it does not hold one
##      against a blown-out sun, and a displaced dark copy does.
##   2. A heavy outline on top of that, sized off the font size so it stays
##      proportional when the lockup auto-fits down on a narrow window.
##   3. A vertical warm gradient over the letterforms — pale at the top where the
##      sky would catch them, deep amber at the baseline. This is the one part
##      that needs a shader, and it is written as a *multiplier* over the label's
##      own font colour rather than as an absolute fill, precisely so that
##      turning USE_SHINE_SHADER off degrades to flat UIStyle.GOLD and not to
##      white text or, worse, an unshaded magenta rectangle.
##   4. A slow specular sweep across the lockup every few seconds. Cheap, and it
##      is what stops a static title screen reading as a screenshot.
##
## The lockup is left-aligned and stacked rather than centred on one line. Porto
## is on the right of the frame and Adamastor looms there, so the composition
## hangs everything readable — logo, menu, hints — off the left margin and leaves
## the right two thirds to the art.

## Single switch, kept for the integrator: this project has no GPU in CI, so the
## gradient shader below has never been compiled anywhere it could be seen. If it
## misbehaves, set this false and the lockup falls back to flat gold — still
## outlined, still shadowed, still legible, just without the gradient and sweep.
const USE_SHINE_SHADER := true

const LINE_ONE := "HEROSAURO"
const LINE_TWO := "& SUPER BOXY"
## Spaced by hand as well as by FontVariation: the wide gaps between words are
## what make a strapline read as a strapline rather than as a caption.
const STRAPLINE := "LEGENDS OF PORTO"

# --- Type scale (at design height; main_menu.gd scales these) ----------------

const SIZE_ONE := 84
const SIZE_TWO := 63
const SIZE_STRAP := 21
const GAP_LINES := -12.0          # display faces overlap slightly; Bangers has deep bearing
const GAP_RULE := 16.0
const GAP_STRAP := 12.0
const RULE_HEIGHT := 3.0
const SHADOW_OFFSET := Vector2(5.0, 6.0)

# --- Shine -------------------------------------------------------------------

const SHINE_SWEEP := 1.05         # seconds for the band to cross the lockup
const SHINE_PAUSE := 6.4          # seconds of nothing between sweeps
const SHINE_REST := -0.40         # parked off the left edge, i.e. invisible

## Warm gradient, expressed as a per-channel multiplier over the label's own
## colour so the shader can be removed without changing the design intent.
const TINT_TOP := Vector3(1.20, 1.12, 0.88)
const TINT_BOTTOM := Vector3(0.84, 0.58, 0.30)

## Authored here rather than in assets/shaders/ deliberately — this stream owns
## scripts/ui/menu/ and nothing else, and a two-uniform canvas shader is not
## worth reaching into another agent's directory for. It is also plain
## canvas_item with no renderer-specific features, so it runs identically on
## Forward+ and on the web build's GL Compatibility.
const SHINE_SHADER := """
shader_type canvas_item;

uniform vec3 tint_top = vec3(1.0);
uniform vec3 tint_bottom = vec3(1.0);
uniform vec2 rect_size = vec2(1.0, 1.0);
uniform float shine_pos = -1.0;
uniform float shine_width = 0.17;
uniform float shine_gain = 0.5;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV) * COLOR;
	float v = clamp(local_pos.y / max(rect_size.y, 1.0), 0.0, 1.0);
	src.rgb *= mix(tint_top, tint_bottom, v);
	float h = clamp(local_pos.x / max(rect_size.x, 1.0), 0.0, 1.0);
	float band = 1.0 - smoothstep(0.0, shine_width, abs(h - shine_pos));
	src.rgb += band * shine_gain * src.a;
	COLOR = src;
}
"""

var _rows: Array[Dictionary] = []      # {face: Label, shadow: Label, size: int}
var _rule: ColorRect
var _strap: Label
var _strap_font: FontVariation
var _materials: Array[ShaderMaterial] = []
var _shine_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.append(_display_row(LINE_ONE, SIZE_ONE))
	_rows.append(_display_row(LINE_TWO, SIZE_TWO))

	_rule = ColorRect.new()
	_rule.color = UIStyle.GOLD
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)

	_strap_font = FontVariation.new()
	_strap_font.base_font = UIStyle.UI_BOLD
	_strap = UIStyle.label(STRAPLINE, SIZE_STRAP, UIStyle.CREAM, true, HORIZONTAL_ALIGNMENT_LEFT)
	_strap.add_theme_font_override("font", _strap_font)
	add_child(_strap)

	_start_shine()


# --- Construction ------------------------------------------------------------

## One display line: a dark displaced copy, then the lit face over it. Built as
## two plain Labels rather than one Label with a shadow constant because Godot's
## label shadow sits *under* the outline, which on a heavy outline like this one
## makes it disappear entirely.
func _display_row(text: String, size: int) -> Dictionary:
	var shadow := _face(text, size, Color(0.03, 0.02, 0.05, 0.62), false)
	add_child(shadow)
	var face := _face(text, size, UIStyle.GOLD, USE_SHINE_SHADER)
	add_child(face)
	return {"face": face, "shadow": shadow, "size": size}


func _face(text: String, size: int, color: Color, shaded: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UIStyle.TITLE_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.07, 0.92))
	l.add_theme_constant_override("outline_size", maxi(6, roundi(size * 0.11)))
	if shaded:
		var sh := Shader.new()
		sh.code = SHINE_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tint_top", TINT_TOP)
		mat.set_shader_parameter("tint_bottom", TINT_BOTTOM)
		mat.set_shader_parameter("shine_pos", SHINE_REST)
		l.material = mat
		_materials.append(mat)
	return l


# --- Layout ------------------------------------------------------------------

## Lay the lockup out at `ui_scale` inside `max_width`, and report the height it
## ended up needing so the caller can stack the menu under it.
##
## The auto-fit is not decoration. "HEROSAURO" set in Bangers at the design size
## is about a third of a 1280-wide frame; on a narrow window the same string at
## the same size would run under Adamastor, so every line is measured and the
## whole lockup shrinks together to keep its proportions.
func relayout(max_width: float, ui_scale: float) -> float:
	var fit := 1.0
	for row in _rows:
		var px: int = maxi(12, roundi(int(row["size"]) * ui_scale))
		var w: float = UIStyle.TITLE_FONT.get_string_size(
				(row["face"] as Label).text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		if w > max_width:
			fit = minf(fit, max_width / maxf(w, 1.0))

	var y := 0.0
	for row in _rows:
		var px := maxi(12, roundi(int(row["size"]) * ui_scale * fit))
		var face: Label = row["face"]
		var shadow: Label = row["shadow"]
		for l: Label in [face, shadow]:
			l.add_theme_font_size_override("font_size", px)
			l.add_theme_constant_override("outline_size", maxi(4, roundi(px * 0.11)))
			l.size = Vector2(max_width, px * 1.34)
		var offset := SHADOW_OFFSET * ui_scale * fit
		face.position = Vector2(0.0, y)
		shadow.position = Vector2(0.0, y) + offset
		y += px * 1.34 + GAP_LINES * ui_scale * fit

	var rule_w := max_width * 0.86
	y += GAP_RULE * ui_scale
	_rule.position = Vector2(0.0, y)
	_rule.size = Vector2(rule_w, maxf(2.0, RULE_HEIGHT * ui_scale))

	var strap_size := maxi(11, roundi(SIZE_STRAP * ui_scale))
	_strap_font.spacing_glyph = maxi(2, roundi(strap_size * 0.34))
	_strap.add_theme_font_size_override("font_size", strap_size)
	y += _rule.size.y + GAP_STRAP * ui_scale
	_strap.position = Vector2(0.0, y)
	_strap.size = Vector2(max_width, strap_size * 1.5)
	y += _strap.size.y

	size = Vector2(max_width, y)
	_push_rect_size()
	return y


## The gradient is driven off each label's own local height, so every label has
## to be told what that height is whenever the lockup is re-fitted.
func _push_rect_size() -> void:
	for row in _rows:
		var face: Label = row["face"]
		if face.material is ShaderMaterial:
			(face.material as ShaderMaterial).set_shader_parameter("rect_size", face.size)


# --- Shine -------------------------------------------------------------------

func _start_shine() -> void:
	if _materials.is_empty():
		return
	_shine_tween = create_tween()
	_shine_tween.set_loops()
	_shine_tween.tween_interval(SHINE_PAUSE)
	_shine_tween.tween_method(_set_shine, -0.30, 1.30, SHINE_SWEEP) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shine_tween.tween_callback(_set_shine.bind(SHINE_REST))


func _set_shine(v: float) -> void:
	for mat in _materials:
		mat.set_shader_parameter("shine_pos", v)


# --- Entry -------------------------------------------------------------------

## Settle the lockup in: a hair of overshoot on scale plus a fade, which reads as
## the logo landing rather than as it appearing.
func play_entry(delay: float) -> void:
	pivot_offset = Vector2(0.0, size.y * 0.5)
	modulate.a = 0.0
	scale = Vector2(1.045, 1.045)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.55).set_delay(delay)
	tw.tween_property(self, "scale", Vector2.ONE, 0.85) \
			.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
