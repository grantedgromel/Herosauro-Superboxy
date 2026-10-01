class_name InkText
extends Control
## A Label that draws its ink keyline and drop shadow in two batches, not four.
##
## The kit's text treatment (UIStyle._legible) is a near-opaque ink outline
## plus a drop shadow. A Label draws that in four passes per line: shadow
## outline, shadow, outline, fill. On GL Compatibility the outline glyphs and
## the fill glyphs live in different cache textures, so those four passes are
## four draw calls for every label, every frame: the old HUD's dozen labels
## cost about fifty.
##
## Here the shadow is drawn with the OUTLINE glyphs, offset: the outlined shape
## cast down, which is what _legible's comment asks for ("the shadow sits under
## the whole ink-outlined shape"), and it shares the outline's texture, so the
## shadow and the keyline are one batch and the fill is the second.
##
## It reads the same theme keys a Label does (font, font_size, font_color,
## font_outline_color, outline_size, font_shadow_color, shadow_offset_x/y,
## line_spacing), so UIStyle's factories and every add_theme_*_override call
## already written against a Label keep working: see `from_label()`.

var text: String = "":
	set(v):
		if v == text:
			return
		text = v
		_dirty = true
		update_minimum_size()
		queue_redraw()
var horizontal_alignment: int = HORIZONTAL_ALIGNMENT_LEFT:
	set(v):
		horizontal_alignment = v
		_dirty = true
		queue_redraw()
var vertical_alignment: int = VERTICAL_ALIGNMENT_CENTER:
	set(v):
		vertical_alignment = v
		queue_redraw()
## Word wrap (Label's AUTOWRAP_WORD_SMART) at the control's width.
var autowrap: bool = false:
	set(v):
		autowrap = v
		_dirty = true
		update_minimum_size()
		queue_redraw()

var _para := TextParagraph.new()
var _dirty := true
var _shaped_for := Vector3(-1, -1, -1)   # width, font size, alignment
var _shaped_font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Theme lookups fall back to the Label entries (and a typed lookup would
	# skip this node's own overrides, which is where UIStyle puts the look).
	theme_type_variation = &"Label"
	resized.connect(func() -> void:
		if autowrap:
			_dirty = true
			queue_redraw())


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_dirty = true
		update_minimum_size()
		queue_redraw()


## The Label's text, look and placement, in an InkText. The label is freed.
static func from_label(l: Label) -> InkText:
	var t := InkText.new()
	t.text = l.text
	t.horizontal_alignment = l.horizontal_alignment
	t.vertical_alignment = l.vertical_alignment
	t.autowrap = l.autowrap_mode != TextServer.AUTOWRAP_OFF
	t.mouse_filter = l.mouse_filter
	if not String(l.name).is_empty():
		t.name = l.name
	for key in ["font"]:
		if l.has_theme_font_override(key):
			t.add_theme_font_override(key, l.get_theme_font(key))
	for key in ["font_size"]:
		if l.has_theme_font_size_override(key):
			t.add_theme_font_size_override(key, l.get_theme_font_size(key))
	for key in ["font_color", "font_outline_color", "font_shadow_color"]:
		if l.has_theme_color_override(key):
			t.add_theme_color_override(key, l.get_theme_color(key))
	for key in ["outline_size", "shadow_offset_x", "shadow_offset_y", "line_spacing"]:
		if l.has_theme_constant_override(key):
			t.add_theme_constant_override(key, l.get_theme_constant(key))
	l.free()
	return t


func get_line_count() -> int:
	_shape()
	return maxi(1, _para.get_line_count())


func _font() -> Font:
	return get_theme_font("font")


func _font_size() -> int:
	return get_theme_font_size("font_size")


func _shape() -> void:
	var font := _font()
	var fs := _font_size()
	var key := Vector3(size.x if autowrap else -1.0, fs, horizontal_alignment)
	if not _dirty and key == _shaped_for and font == _shaped_font:
		return
	_dirty = false
	_shaped_for = key
	_shaped_font = font
	_para.clear()
	if font == null:
		return
	_para.add_string(text, font, fs)
	_para.alignment = horizontal_alignment
	if autowrap:
		_para.width = maxf(1.0, size.x)
		_para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND \
			| TextServer.BREAK_ADAPTIVE
	else:
		_para.width = -1.0
		_para.break_flags = TextServer.BREAK_MANDATORY


## Unwrapped: the text's own box. Wrapped: nothing; the caller sets the box
## (a width-less wrap would measure one glyph per line and grow the control
## hundreds of pixels tall, pushing the centred text out of its box).
func _get_minimum_size() -> Vector2:
	if autowrap:
		return Vector2.ZERO
	_shape()
	var n := _para.get_line_count()
	var spacing := float(get_theme_constant("line_spacing"))
	var h := 0.0
	var w := 0.0
	for i in n:
		var ls := _para.get_line_size(i)
		h += ls.y + (spacing if i > 0 else 0.0)
		w = maxf(w, ls.x)
	return Vector2(0.0 if autowrap else w, h)


func _draw() -> void:
	if text.is_empty():
		return
	_shape()
	var n := _para.get_line_count()
	if n == 0:
		return
	var spacing := float(get_theme_constant("line_spacing"))
	var heights := PackedFloat32Array()
	var widths := PackedFloat32Array()
	var total := 0.0
	for i in n:
		var ls := _para.get_line_size(i)
		heights.append(ls.y)
		widths.append(ls.x)
		total += ls.y + (spacing if i > 0 else 0.0)
	var y := 0.0
	match vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y = floorf((size.y - total) * 0.5)
		VERTICAL_ALIGNMENT_BOTTOM:
			y = size.y - total
	var at := PackedVector2Array()
	for i in n:
		var x := 0.0
		# Unwrapped lines are shaped with no width, so align them here.
		if not autowrap:
			match horizontal_alignment:
				HORIZONTAL_ALIGNMENT_CENTER:
					x = floorf((size.x - widths[i]) * 0.5)
				HORIZONTAL_ALIGNMENT_RIGHT:
					x = size.x - widths[i]
		at.append(Vector2(x, y))
		y += heights[i] + spacing

	var ci := get_canvas_item()
	var outline := get_theme_constant("outline_size")
	var ink := get_theme_color("font_outline_color")
	var shadow := get_theme_color("font_shadow_color")
	var drop := Vector2(get_theme_constant("shadow_offset_x"),
		get_theme_constant("shadow_offset_y"))
	# Batch one: shadow and keyline, both from the outline glyph texture.
	if outline > 0:
		if shadow.a > 0.0:
			for i in n:
				_para.draw_line_outline(ci, at[i] + drop, i, outline, shadow)
		if ink.a > 0.0:
			for i in n:
				_para.draw_line_outline(ci, at[i], i, outline, ink)
	elif shadow.a > 0.0:
		for i in n:
			_para.draw_line(ci, at[i] + drop, i, shadow)
	# Batch two: the fill.
	var fill := get_theme_color("font_color")
	for i in n:
		_para.draw_line(ci, at[i], i, fill)
