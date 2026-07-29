extends Button
## One row of the main menu: either a plain action or an inline segmented option.
##
## It is a Button underneath so that focus, hover, click, keyboard activation and
## the engine's own focus-neighbour navigation all come for free, but it draws
## none of Button's text — the caret, the label and the option pills are child
## controls, laid out by hand, so the focus state can move as one piece.
##
## NO ICON GLYPHS ANYWHERE. The obvious focus caret is a triangle, and neither
## Bangers nor Chillax carries one; a missing glyph on the web export is a
## tofu box in the most visible spot on the screen. The focus marker is therefore
## a drawn gold bar, and the difficulty control is three pills rather than a pair
## of chevrons — which is clearer anyway, because it shows the whole scale
## instead of only the current value.

enum Kind { ACTION, OPTION }

signal value_changed(index: int)

# --- Metrics -----------------------------------------------------------------

## Idle and focused sizes. The focused row growing is the clearest possible
## "you are here" — it survives colourblindness, a bright backdrop and a photo of
## the screen, none of which a colour change alone does. 25 -> 30 is a fifth
## larger, which reads as deliberate rather than as a wobble.
const TEXT_PX := 25
const TEXT_PX_FOCUS := 30
const PILL_PX := 13
const MARKER_WIDTH := 5.0
const MARKER_INSET := 4.0
const FOCUS_SHIFT := 12.0        # how far the content slides right when focused
const SHIFT_TIME := 0.16
const PILL_GAP := 6
const PAD_LEFT := 22.0
const PAD_RIGHT := 18.0

# --- Colour ------------------------------------------------------------------

## Pulled well down from the focused row. On the old backdrop every row had to
## stay bright enough to survive the sunlit water behind it, which flattened the
## whole column into one block of near-white. Against a flat dark field the idle
## rows can recede properly, so the focused one is the only thing the eye lands
## on — the single biggest reason a minimal menu reads as designed.
const IDLE_TEXT := Color(0.78, 0.75, 0.73, 0.58)
const HOT_FILL := Color(1.0, 0.86, 0.62, 0.11)
const DOWN_FILL := Color(1.0, 0.86, 0.62, 0.18)

var id: StringName = &""
var kind: int = Kind.ACTION
var index: int = 0

var _label: Label
var _content: HBoxContainer
var _marker: Panel
var _pills: Array[PanelContainer] = []
var _pill_labels: Array[Label] = []
var _pill_colors: Array[Color] = []
var _shift: Tween
## Held because _refresh has to resolve a font size and only the list knows the
## scale. Defaults to 1.0 so a row focused before the first rescale still sizes.
var _ui: float = 1.0


## Built through this rather than through _ready() so the caller can hand over
## the option set before the row is ever laid out.
func setup(row_id: StringName, caption: String, row_kind: int = Kind.ACTION,
		options: PackedStringArray = PackedStringArray(),
		colors: Array[Color] = [], start: int = 0) -> void:
	id = row_id
	kind = row_kind
	index = start
	name = String(row_id).capitalize().replace(" ", "")
	text = ""
	focus_mode = Control.FOCUS_ALL
	toggle_mode = false
	_style()

	_marker = Panel.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mk := StyleBoxFlat.new()
	mk.bg_color = UIStyle.GOLD
	mk.set_corner_radius_all(int(MARKER_WIDTH / 2.0))
	mk.corner_detail = 6
	_marker.add_theme_stylebox_override("panel", mk)
	_marker.modulate.a = 0.0
	add_child(_marker)

	_content = HBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", UIStyle.SPACE_MD)
	add_child(_content)

	_label = UIStyle.label(caption, TEXT_PX, IDLE_TEXT, true, HORIZONTAL_ALIGNMENT_LEFT)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_FILL
	_content.add_child(_label)

	if kind == Kind.OPTION:
		_build_pills(options, colors)

	mouse_entered.connect(_on_hover)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	resized.connect(_relayout)
	_refresh()


## Only `focus` carries the highlight fill, and `hover` is deliberately empty.
## Button draws the focus box ON TOP of whichever of normal/hover/pressed applies
## rather than instead of it, so putting the same fill on both would make a
## moused row (which takes focus on hover) exactly twice as bright as a
## keyboarded one. Pressed still stacks, which is what a press should do.
## The focused row carries NO fill. It used to have one, because on the old
## sunlit backdrop a plate was the only thing that reliably held the text apart
## from the water behind it. Against a flat field the plate is the thing that
## looks unfinished — it reads as a button in a screen that has no other buttons,
## and it boxes in a row whose whole job is to be a line of type. Focus is now
## carried by three things that cost nothing: the gold bar, the slide right, and
## the row growing a fifth larger.
##
## Pressed keeps its fill. A press is a moment, not a state, and a brief flash is
## the confirmation a click has landed.
func _style() -> void:
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", _fill(DOWN_FILL))
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())


func _fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(UIStyle.RADIUS_MD)
	sb.corner_detail = 10
	sb.set_border_width_all(0)
	return sb


# --- Option pills ------------------------------------------------------------

func _build_pills(options: PackedStringArray, colors: Array[Color]) -> void:
	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_constant_override("separation", PILL_GAP)
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_content.add_child(strip)

	for i in options.size():
		var tint: Color = colors[i] if i < colors.size() else UIStyle.GOLD
		_pill_colors.append(tint)
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UIStyle.label(options[i], PILL_PX, UIStyle.TEXT_SECONDARY, true,
				HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(52, 0)
		pill.add_child(l)
		strip.add_child(pill)
		_pills.append(pill)
		_pill_labels.append(l)
	_paint_pills()


func _paint_pills() -> void:
	for i in _pills.size():
		var on := i == index
		var tint: Color = _pill_colors[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint if on else Color(1.0, 0.92, 0.82, 0.06)
		sb.set_corner_radius_all(UIStyle.RADIUS_SM)
		sb.corner_detail = 8
		sb.set_border_width_all(1)
		sb.border_color = tint.lightened(0.25) if on else UIStyle.HAIRLINE
		sb.content_margin_left = UIStyle.SPACE_SM
		sb.content_margin_right = UIStyle.SPACE_SM
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		_pills[i].add_theme_stylebox_override("panel", sb)
		_pill_labels[i].add_theme_color_override("font_color",
				UIStyle.BASE if on else UIStyle.TEXT_DISABLED)
		# The selected pill loses its outline: dark text on a bright gold chip
		# does not need one, and keeping it just makes the letters muddy.
		_pill_labels[i].add_theme_constant_override("outline_size", 0 if on else 2)


func set_index(i: int, notify: bool = true) -> void:
	if _pills.is_empty():
		return
	var next := clampi(i, 0, _pills.size() - 1)
	if next == index:
		return
	index = next
	_paint_pills()
	if notify:
		value_changed.emit(index)


func step(delta: int) -> void:
	if _pills.is_empty():
		return
	set_index(wrapi(index + delta, 0, _pills.size()))


# --- Interaction -------------------------------------------------------------

## Hovering takes focus. Mouse and keyboard then share one highlighted row, which
## is the only way a menu driven by both does not end up showing two.
func _on_hover() -> void:
	if not has_focus() and focus_mode != Control.FOCUS_NONE:
		grab_focus()


func _gui_input(event: InputEvent) -> void:
	if kind != Kind.OPTION:
		return
	if event.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# Clicking a specific pill picks it; clicking anywhere else on the row
		# advances, which is what the keyboard's activate does too.
		var hit := _pill_at((event as InputEventMouseButton).position)
		if hit >= 0:
			set_index(hit)
			accept_event()


func _pill_at(local: Vector2) -> int:
	for i in _pills.size():
		var r := Rect2(_pills[i].global_position - global_position, _pills[i].size)
		if r.grow(3.0).has_point(local):
			return i
	return -1


# --- Look --------------------------------------------------------------------

func _refresh() -> void:
	var hot := has_focus()
	_label.add_theme_color_override("font_color", UIStyle.TEXT_PRIMARY if hot else IDLE_TEXT)
	if _shift != null and _shift.is_valid():
		_shift.kill()
	_shift = create_tween().set_parallel(true)
	_shift.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shift.tween_property(_content, "position:x",
			PAD_LEFT + (FOCUS_SHIFT if hot else 0.0), SHIFT_TIME)
	_shift.tween_property(_marker, "modulate:a", 1.0 if hot else 0.0, SHIFT_TIME)
	_shift.tween_property(_marker, "size:y", size.y * (0.62 if hot else 0.18), SHIFT_TIME)
	_shift.tween_property(_marker, "position:y",
			size.y * (0.19 if hot else 0.41), SHIFT_TIME)
	# Font size is a theme override, not a property, so it needs tween_method.
	# Tweened rather than snapped because the row also slides right at the same
	# time, and a size that jumps while the position eases reads as two events.
	_shift.tween_method(_set_text_px, float(_label.get_theme_font_size("font_size")),
			_text_px(hot), SHIFT_TIME)


func _relayout() -> void:
	_content.position = Vector2(PAD_LEFT + (FOCUS_SHIFT if has_focus() else 0.0), 0.0)
	_content.size = Vector2(maxf(size.x - PAD_LEFT - PAD_RIGHT, 10.0), size.y)
	_marker.position = Vector2(MARKER_INSET, size.y * (0.19 if has_focus() else 0.41))
	_marker.size = Vector2(MARKER_WIDTH, size.y * (0.62 if has_focus() else 0.18))


func _text_px(hot: bool) -> float:
	return maxf(13.0, (TEXT_PX_FOCUS if hot else TEXT_PX) * _ui)


func _set_text_px(px: float) -> void:
	_label.add_theme_font_size_override("font_size", maxi(13, roundi(px)))


## Re-point the type at a new UI scale. Called by the list on resize.
func rescale(ui_scale: float) -> void:
	_ui = ui_scale
	_set_text_px(_text_px(has_focus()))
	for l in _pill_labels:
		l.add_theme_font_size_override("font_size", maxi(9, roundi(PILL_PX * ui_scale)))
		l.custom_minimum_size = Vector2(52.0 * ui_scale, 0)
