extends Control
## The game's logo lockup: two stacked display lines, a gold rule and a
## letterspaced strapline, treated so it survives being laid over a bright,
## saturated, MOVING midday sky. There is no tone behind it we can rely on: over
## seventy-four seconds of camera move the same letter crosses blue sky, white
## river glare and sunlit granite, so the lockup has to carry its own contrast.
##
## Five things do that work, in order of how much they matter:
##
##   1. A HARD INK KEYLINE around every letterform, drawn as its own pass. This
##      is what makes the lockup a moulded sticker rather than coloured text: a
##      comic logo is defined by the black line around it, and against a blue
##      midday sky a warm outline alone has nothing to hold on to. It is a
##      separate Label because Godot draws exactly one outline per Label, and the
##      face needs its own, thinner, warmer one on top of this.
##   2. A hard drop shadow behind that. The keyline holds the edge; the displaced
##      dark copy is what gives the whole lockup thickness.
##   3. A heavy outline on the face, sized off the font size so it stays
##      proportional when the lockup auto-fits down on a narrow window.
##   4. A vertical warm gradient over the letterforms — pale at the top where the
##      sky would catch them, deep amber at the baseline. This is the one part
##      that needs a shader, and it is written as a *multiplier* over the label's
##      own font colour rather than as an absolute fill, precisely so that
##      turning USE_SHINE_SHADER off degrades to flat UIStyle.GOLD and not to
##      white text or, worse, an unshaded magenta rectangle.
##   5. A slow specular sweep across the lockup every few seconds. Cheap, and it
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
## Tracked out at run time through a FontVariation rather than by padding the
## string with spaces: spacing_glyph widens the word gaps in proportion too, so
## the strapline stays a strapline instead of collapsing into a caption when the
## lockup auto-fits down.
const STRAPLINE := "THE GUARDIAN BROTHERS OF PORTO"

# --- Type scale (at design height; main_menu.gd scales these) ----------------

## Both lines set at the SAME size, deliberately. The lockup used to run
## HEROSAURO at 92 over & SUPER BOXY at 68, which is a 35% difference — and a
## title that sets one hero larger than the other is making a claim about the
## game. This is a two-player co-op game with two equally playable heroes, so
## the type has to say that. `relayout()` derives a single shared `fit` scalar
## across every row, so equal sizes here stay equal at every window width.
const SIZE_ONE := 84
const SIZE_TWO := 84
const SIZE_STRAP := 20
const GAP_LINES := -12.0          # display faces overlap slightly; Bangers has deep bearing
const GAP_RULE := 22.0
const GAP_STRAP := 12.0
const RULE_HEIGHT := 4.0
const SHADOW_OFFSET := Vector2(6.0, 7.0)
## Outline weights, as fractions of the font size. The keyline is the outer black
## stroke that defines the letterform; the face's own rim sits inside it and is a
## warm burnt amber rather than black, which is what gives the gold a lit edge
## instead of a second dead one.
const OUTLINE_KEYLINE := 0.15
const OUTLINE_FACE := 0.075

# --- Shine -------------------------------------------------------------------

const SHINE_SWEEP := 1.05         # seconds for the band to cross the lockup
const SHINE_PAUSE := 6.4          # seconds of nothing between sweeps
const SHINE_REST := -0.40         # parked off the left edge, i.e. invisible

## Warm gradient, expressed as a per-channel multiplier over the label's own
## colour so the shader can be removed without changing the design intent.
## Against UIStyle.GOLD these land on pale sunlit gold at the cap line and burnt
## amber at the baseline — hot metal, which is what a comic logo wants.
const TINT_TOP := Vector3(1.15, 1.28, 1.36)
const TINT_BOTTOM := Vector3(0.90, 0.60, 0.28)
## The gradient is mapped over this multiple of the font size rather than over
## the label's box, because the box is 34% taller than the glyphs and mapping to
## it would leave the bottom of the letters only three quarters of the way down
## the ramp — a gradient that visibly stops short.
const GRADIENT_SPAN := 0.95

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
	// Gated on luminance so the sweep lights the gold face and leaves the
	// outline alone. Label emits its outline as its own quads through the same
	// material, and an ungated add turns a near-black rim mid-grey every time
	// the band crosses it — a flicker exactly where the contrast has to hold.
	float lit = smoothstep(0.15, 0.45, dot(src.rgb, vec3(0.299, 0.587, 0.114)));
	src.rgb += band * shine_gain * src.a * lit;
	COLOR = src;
}
"""

var _rows: Array[Dictionary] = []      # {face, shadow, size, px}
var _rule: TextureRect
var _strap: Label
var _strap_font: FontVariation
var _materials: Array[ShaderMaterial] = []
var _shine_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.append(_display_row(LINE_ONE, SIZE_ONE))
	_rows.append(_display_row(LINE_TWO, SIZE_TWO))

	_rule = _gold_rule()
	add_child(_rule)

	_strap_font = FontVariation.new()
	_strap_font.base_font = UIStyle.UI_BOLD
	_strap = UIStyle.label(STRAPLINE, SIZE_STRAP, UIStyle.TEXT_PRIMARY, true,
			HORIZONTAL_ALIGNMENT_LEFT)
	_strap.add_theme_font_override("font", _strap_font)
	add_child(_strap)

	_start_shine()


# --- Construction ------------------------------------------------------------

## One display line, back to front: a dark displaced copy, the ink keyline, then
## the lit face. Built as three plain Labels rather than one Label with a shadow
## constant because Godot's label shadow sits *under* the outline (which on a
## heavy outline makes it disappear entirely) and because a Label carries exactly
## one outline, so the keyline and the face's own rim cannot share a node.
func _display_row(text: String, size: int) -> Dictionary:
	var drop := Color(0.02, 0.05, 0.09, 0.55)
	var shadow := _face(text, size, drop, drop, false, OUTLINE_KEYLINE)
	add_child(shadow)
	var ink := _face(text, size, UIStyle.KEYLINE, UIStyle.KEYLINE, false, OUTLINE_KEYLINE)
	add_child(ink)
	var face := _face(text, size, UIStyle.GOLD, Color(0.35, 0.16, 0.03, 0.95),
			USE_SHINE_SHADER, OUTLINE_FACE)
	add_child(face)
	return {"face": face, "shadow": shadow, "ink": ink, "size": size, "px": size}


func _face(text: String, size: int, color: Color, outline: Color, shaded: bool,
		outline_fraction: float) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UIStyle.TITLE_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", maxi(6, roundi(size * outline_fraction)))
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
		var ink: Label = row["ink"]
		# The keyline passes keep the heavy stroke and the face keeps the light
		# one, at every fitted size — a keyline that stops scaling with the type
		# is the first thing that gives away an auto-fitted lockup.
		for l: Label in [shadow, ink]:
			l.add_theme_font_size_override("font_size", px)
			l.add_theme_constant_override("outline_size", maxi(5, roundi(px * OUTLINE_KEYLINE)))
			l.size = Vector2(max_width, px * 1.34)
		face.add_theme_font_size_override("font_size", px)
		face.add_theme_constant_override("outline_size", maxi(3, roundi(px * OUTLINE_FACE)))
		face.size = Vector2(max_width, px * 1.34)
		row["px"] = px
		var offset := SHADOW_OFFSET * ui_scale * fit
		face.position = Vector2(0.0, y)
		ink.position = Vector2(0.0, y)
		shadow.position = Vector2(0.0, y) + offset
		y += px * 1.34 + GAP_LINES * ui_scale * fit

	var rule_w := max_width * 0.88
	y += GAP_RULE * ui_scale
	_rule.position = Vector2(0.0, y)
	_rule.size = Vector2(rule_w, maxf(2.0, RULE_HEIGHT * ui_scale))

	# The strapline gets its own fit, separate from the display lines' shared one.
	# It is tracked out through spacing_glyph, and get_string_size() measures the
	# BASE font, so the rendered width is the measured width plus one space of
	# tracking per glyph gap — a strapline that fits on paper and overruns on
	# screen is exactly that difference. "THE GUARDIAN BROTHERS OF PORTO" is
	# nearly twice the length of the sixteen-character line this was designed
	# around, so the shortfall is real rather than theoretical.
	var strap_size := maxi(11, roundi(SIZE_STRAP * ui_scale))
	var track := maxi(2, roundi(strap_size * 0.34))
	var strap_w := UIStyle.UI_BOLD.get_string_size(
			STRAPLINE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, strap_size).x \
			+ float(track * maxi(0, STRAPLINE.length() - 1))
	if strap_w > max_width:
		var strap_fit := max_width / maxf(strap_w, 1.0)
		strap_size = maxi(9, roundi(strap_size * strap_fit))
		# Tracking is re-derived from the fitted size rather than scaled
		# separately, so the letter-spacing stays proportional to the letters.
		track = maxi(1, roundi(strap_size * 0.34))
	_strap_font.spacing_glyph = track
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
			(face.material as ShaderMaterial).set_shader_parameter("rect_size",
					Vector2(face.size.x, float(row["px"]) * GRADIENT_SPAN))


## The rule fades out to the right instead of stopping dead. A hard bar under a
## logo laid over a moving photographic backdrop reads as a UI divider; a fade
## reads as part of the lockup.
func _gold_rule() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		UIStyle.GOLD,
		Color(UIStyle.GOLD_DEEP.r, UIStyle.GOLD_DEEP.g, UIStyle.GOLD_DEEP.b, 0.55),
		Color(UIStyle.GOLD_DEEP.r, UIStyle.GOLD_DEEP.g, UIStyle.GOLD_DEEP.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 2
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


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
