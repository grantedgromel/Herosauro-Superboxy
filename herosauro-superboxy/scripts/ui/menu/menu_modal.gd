extends Control
## The CONTROLS and CREDITS overlays.
##
## One reusable modal — a dim, a raised card, a heading, a scrolling body and a
## close button — plus the two bodies that go in it.
##
## CONTROLS reads the live InputMap rather than restating it. The old menu's
## single cramped footer line was already drifting from the project's actual
## bindings, and a hand-written control list is a lie waiting to happen: it is
## correct exactly until someone rebinds something. Actions are grouped and
## captioned by hand (that part IS design), but every key, button and stick shown
## is whatever InputMap currently says.
##
## CREDITS carries the CC BY 4.0 attribution for the photogrammetry city scan.
## That is a licence condition, not a courtesy — see
## assets/models/backdrop/ATTRIBUTION.md.

signal closed

const CARD_MAX := Vector2(800.0, 600.0)
const CARD_MARGIN := 48.0
const OPEN_TIME := 0.22
const SCROLL_STEP := 46.0

## Xbox-layout names for JoyButton indices 0..14. Spelled out rather than drawn
## as glyphs because neither font in this project carries controller symbols.
const PAD_BUTTONS := ["A", "B", "X", "Y", "View", "Guide", "Menu", "L3", "R3",
		"LB", "RB", "D-Up", "D-Down", "D-Left", "D-Right"]
const PAD_AXES := ["L-Stick", "L-Stick", "R-Stick", "R-Stick", "LT", "RT"]

const ATTRIBUTION_TITLE := "Ponte de D. Luís (Porto/Portugal)"
const ATTRIBUTION_AUTHOR := "by EDUARDO SOETHE — CC BY 4.0"

var _card: PanelContainer
var _heading: Label
var _body_host: VBoxContainer
var _scroll: ScrollContainer
var _close: Button
var _open: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = UIStyle.OVERLAY
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_card = UIStyle.card(UIStyle.Elev.MODAL, UIStyle.RADIUS_LG, UIStyle.SPACE_XL)
	add_child(_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIStyle.SPACE_LG)
	_card.add_child(column)

	_heading = UIStyle.title("", UIStyle.Scale.HEADING, UIStyle.GOLD)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(_heading)
	column.add_child(UIStyle.divider())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)

	_body_host = VBoxContainer.new()
	_body_host.add_theme_constant_override("separation", UIStyle.SPACE_LG)
	_body_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body_host)

	_close = UIStyle.button("CLOSE", false, Vector2(190, 48))
	_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close.pressed.connect(close)
	column.add_child(_close)

	resized.connect(_fit_card)
	_fit_card()


func _fit_card() -> void:
	var w := minf(CARD_MAX.x, maxf(size.x - CARD_MARGIN * 2.0, 260.0))
	var h := minf(CARD_MAX.y, maxf(size.y - CARD_MARGIN * 2.0, 220.0))
	_card.size = Vector2(w, h)
	_card.position = ((size - Vector2(w, h)) * 0.5).round()
	_card.pivot_offset = Vector2(w, h) * 0.5


# --- Open / close ------------------------------------------------------------

func open(heading: String, body: Control) -> void:
	for child in _body_host.get_children():
		_body_host.remove_child(child)
		child.queue_free()
	_heading.text = heading
	_body_host.add_child(body)
	_fit_card()

	visible = true
	_open = true
	modulate.a = 0.0
	_card.scale = Vector2(0.965, 0.965)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, OPEN_TIME)
	tw.tween_property(_card, "scale", Vector2.ONE, OPEN_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_close.call_deferred("grab_focus")


func close() -> void:
	if not _open:
		return
	_open = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, OPEN_TIME * 0.8)
	tw.tween_property(_card, "scale", Vector2(0.975, 0.975), OPEN_TIME * 0.8)
	tw.chain().tween_callback(func() -> void:
		visible = false
		closed.emit())


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down", true):
		_scroll.scroll_vertical += int(SCROLL_STEP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up", true):
		_scroll.scroll_vertical -= int(SCROLL_STEP)
		get_viewport().set_input_as_handled()


# --- CONTROLS ----------------------------------------------------------------

## Caption, any literal entries to show first, then the actions to read live.
static func _control_groups() -> Array:
	return [
		["MOVEMENT", [
			["Move", [], ["move_up", "move_left", "move_down", "move_right"]],
			["Look", ["Mouse"], ["look_up", "look_left", "look_down", "look_right"]],
			["Jump", [], ["jump"]],
			["Sprint", [], ["sprint"]],
		]],
		["COMBAT", [
			["Attack", [], ["attack"]],
			["Special", [], ["ability"]],
		]],
		["SYSTEM", [
			["Confirm", [], ["ui_confirm"]],
			["Back", [], ["ui_cancel"]],
			["Pause / release pointer", [], ["ui_pause"]],
		]],
	]


static func build_controls() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIStyle.SPACE_LG)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for group in _control_groups():
		column.add_child(_section(String(group[0])))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", UIStyle.SPACE_LG)
		grid.add_theme_constant_override("v_separation", UIStyle.SPACE_MD)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for row in group[1]:
			var caption := UIStyle.text(String(row[0]), UIStyle.Scale.BODY,
					UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
			caption.custom_minimum_size = Vector2(190, 0)
			caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(caption)
			grid.add_child(_cap_strip(_bindings(row[1], row[2])))
		column.add_child(grid)

	var note := UIStyle.text(
			"The pointer is captured while you fight. Esc releases it and pauses.",
			UIStyle.Scale.CAPTION, UIStyle.TEXT_DISABLED, HORIZONTAL_ALIGNMENT_LEFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(note)
	return column


## Keyboard and mouse first, then the pad. Reading the InputMap in declaration
## order would interleave them — "W, L-Stick, A, S, D" — which is unreadable.
static func _bindings(lead: Array, actions: Array) -> PackedStringArray:
	var keys := PackedStringArray()
	var pads := PackedStringArray()
	for entry in lead:
		keys.append(String(entry))
	for action_name in actions:
		var action := StringName(action_name)
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			var cap := _event_caption(ev)
			if cap.is_empty():
				continue
			var into: PackedStringArray = pads if _is_pad(ev) else keys
			if not into.has(cap):
				into.append(cap)
	for p in pads:
		keys.append(p)
	return keys


static func _is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


static func _event_caption(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		var caption := OS.get_keycode_string(code)
		# The keypad twins of Enter and the arrows say nothing a player needs.
		return "" if caption.begins_with("Kp ") else caption
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			_:
				return ""
	if ev is InputEventJoypadButton:
		var i := int((ev as InputEventJoypadButton).button_index)
		return PAD_BUTTONS[i] if i >= 0 and i < PAD_BUTTONS.size() else ""
	if ev is InputEventJoypadMotion:
		var axis := int((ev as InputEventJoypadMotion).axis)
		return PAD_AXES[axis] if axis >= 0 and axis < PAD_AXES.size() else ""
	return ""


static func _cap_strip(caps: PackedStringArray) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIStyle.SPACE_SM)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if caps.is_empty():
		row.add_child(UIStyle.text("unbound", UIStyle.Scale.CAPTION, UIStyle.TEXT_DISABLED))
		return row
	for cap in caps:
		row.add_child(UIStyle.key_cap(cap))
	return row


# --- CREDITS -----------------------------------------------------------------

static func build_credits() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIStyle.SPACE_LG)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	column.add_child(_paragraph(
			"A boss fight on the Ponte de Dom Luís I, at golden hour, over the Douro."))

	column.add_child(_section("THE CAST"))
	for actor in [UIStyle.Actor.HEROSAURO, UIStyle.Actor.SUPERBOXY, UIStyle.Actor.ADAMASTOR]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UIStyle.SPACE_MD)
		line.add_child(UIStyle.chip(UIStyle.actor_color(actor), 12.0))
		var who := UIStyle.text(UIStyle.actor_name(actor), UIStyle.Scale.LABEL,
				UIStyle.actor_color(actor), HORIZONTAL_ALIGNMENT_LEFT)
		who.custom_minimum_size = Vector2(150, 0)
		line.add_child(who)
		# Left in the palette's own casing rather than title-cased: the epithets
		# are set as small caps against the coloured name, which is a credits
		# convention, and Title Case Every Word Is Not.
		line.add_child(UIStyle.text(UIStyle.actor_epithet(actor),
				UIStyle.Scale.CAPTION, UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT))
		column.add_child(line)

	# --- The licence obligation. Do not quietly shorten this. ---
	column.add_child(_section("THIRD-PARTY ASSETS"))
	var scan := UIStyle.text(ATTRIBUTION_TITLE, UIStyle.Scale.BODY,
			UIStyle.TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT)
	column.add_child(scan)
	column.add_child(UIStyle.text(ATTRIBUTION_AUTHOR, UIStyle.Scale.BODY,
			UIStyle.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	column.add_child(_paragraph(
			"Used, in modified form, as the distant city backdrop. "
			+ "sketchfab.com/dusoethe · creativecommons.org/licenses/by/4.0/"))
	column.add_child(_paragraph(
			"Typefaces: Chillax by Indian Type Foundry, Fontshare Free Font "
			+ "License · fontshare.com. Bangers, SIL Open Font License 1.1."))

	column.add_child(_section("BUILT WITH"))
	column.add_child(_paragraph("Godot Engine 4 — MIT License."))
	return column


# --- Shared bits -------------------------------------------------------------

static func _section(heading: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIStyle.SPACE_XS)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UIStyle.text(heading, UIStyle.Scale.LABEL, UIStyle.GOLD,
			HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(UIStyle.divider(1, 0.09))
	return box


static func _paragraph(body: String) -> Label:
	var l := UIStyle.text(body, UIStyle.Scale.CAPTION, UIStyle.TEXT_SECONDARY,
			HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
