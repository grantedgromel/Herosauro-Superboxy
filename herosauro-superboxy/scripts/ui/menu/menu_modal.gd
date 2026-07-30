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
## It also shows ONE SECTION PER HERO. The two slots share no bindings — slot one
## is keyboard and mouse, slot two is a pad or the right-hand key cluster — so a
## single list would be correct for at most one of the two players sitting there.
## The event-to-caption tables live in UIStyle (`binding_caps`, `event_caption`)
## because the pause overlay needs exactly the same answers.
##
## CREDITS carries the CC BY 4.0 attribution for the photogrammetry city scan.
## That is a licence condition, not a courtesy — see
## assets/models/backdrop/ATTRIBUTION.md.

signal closed

const CARD_MAX := Vector2(800.0, 600.0)
const CARD_MARGIN := 48.0
const OPEN_TIME := 0.22
const SCROLL_STEP := 46.0

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

## Caption, any literal entries to show first, then the BARE actions to read
## live. Bare: `UIStyle.binding_caps()` puts each one through
## `InputManager.action_name(player, action)`, which is the only thing that knows
## slot 2's actions carry a "p2_" prefix.
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
	]


## Actions that are not per-slot. Either player's Esc pauses, and the menu is
## driven by one pair of hands whoever is holding them, so repeating these under
## every hero would be noise dressed as information.
static func _system_group() -> Array:
	return [
		["Confirm", [], ["ui_confirm"]],
		["Back", [], ["ui_cancel"]],
		["Pause / release pointer", [], ["ui_pause"]],
	]


## The full controls reference — ONE SECTION PER HERO ON THE ROSTER.
##
## The game is two-player local co-op and the two heroes share no bindings at
## all: slot one is WASD and the mouse, slot two is a pad or the IJKL cluster on
## a pad-less couch. A single control list is therefore not a simplification, it
## is wrong for whichever player is not slot one — so the roster drives the
## headings and every glyph under them comes from that slot's real Input Map
## entries. In a solo run there is one hero and one section, and it is labelled
## with that hero's name rather than "PLAYER 1".
static func build_controls() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIStyle.SPACE_LG)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var roster := GameManager.active_player_ids()
	for pid in roster:
		var actor := UIStyle.actor_for_player(pid)
		for group in _control_groups():
			column.add_child(_section("P%d  %s  %s" % [pid, UIStyle.actor_name(actor),
					String(group[0])], UIStyle.actor_color(actor)))
			column.add_child(_binding_grid(pid, group[1]))

	column.add_child(_section("SYSTEM"))
	column.add_child(_binding_grid(1, _system_group()))

	var note := UIStyle.text(
			"The pointer is captured while you fight. Esc releases it and pauses.",
			UIStyle.Scale.CAPTION, UIStyle.TEXT_DISABLED, HORIZONTAL_ALIGNMENT_LEFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(note)
	return column


static func _binding_grid(player: int, rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UIStyle.SPACE_LG)
	grid.add_theme_constant_override("v_separation", UIStyle.SPACE_MD)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row in rows:
		var caption := UIStyle.text(String(row[0]), UIStyle.Scale.BODY,
				UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
		caption.custom_minimum_size = Vector2(190, 0)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(caption)
		grid.add_child(_cap_strip(_bindings(player, row[1], row[2])))
	return grid


## Literal lead entries (things the Input Map cannot describe, like "Mouse")
## followed by the slot's real bindings. Every binding, not a capped subset, so
## the full table shows each key an action answers to — the compact pause hint is
## the one that asks for one apiece.
##
## The literals are SLOT ONE'S HARDWARE and are shown only where they apply:
## mouse-look is read straight off the event stream by CameraRig for the keyboard
## player, and telling the pad player their camera is on the mouse would be
## exactly the kind of confident falsehood this panel exists to avoid. In a solo
## run the two sets merge (see InputManager._slots_for), so the lone hero gets
## them whichever id they are.
static func _bindings(player: int, lead: Array, actions: Array) -> PackedStringArray:
	var caps := PackedStringArray()
	if player == 1 or GameManager.player_count <= 1:
		for entry in lead:
			caps.append(String(entry))
	for cap in UIStyle.binding_caps(player, actions):
		if not caps.has(cap):
			caps.append(cap)
	return caps


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
			"A boss fight on the Ponte de Dom Luís I, in the midday sun, over the Douro."))

	column.add_child(_section("THE CAST"))
	for actor in [UIStyle.Actor.HEROSAURO, UIStyle.Actor.SUPERBOXY, UIStyle.Actor.ADAMASTOR]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UIStyle.SPACE_MD)
		line.add_child(UIStyle.chip(UIStyle.actor_color(actor), 14.0))
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
			"Typefaces: Bangers and Fredoka, SIL Open Font License 1.1."))

	column.add_child(_section("BUILT WITH"))
	column.add_child(_paragraph("Godot Engine 4 — MIT License."))
	return column


# --- Shared bits -------------------------------------------------------------

static func _section(heading: String, tint: Color = UIStyle.GOLD) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIStyle.SPACE_XS)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UIStyle.text(heading, UIStyle.Scale.LABEL, tint,
			HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(UIStyle.divider(2, 0.18))
	return box


static func _paragraph(body: String) -> Label:
	var l := UIStyle.text(body, UIStyle.Scale.CAPTION, UIStyle.TEXT_SECONDARY,
			HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
