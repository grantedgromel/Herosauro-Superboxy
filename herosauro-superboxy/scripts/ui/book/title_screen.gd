class_name TitleScreen
extends Control
## "Toca para começar": the key art, the game's name, and one big pulsing
## invitation. Any key, click, tap or pad button continues.
##
## That first gesture is also what lets a browser start audio (autoplay is
## blocked until the page has been touched), so nothing on this screen needs
## sound and the very next screen can speak.

signal started()

const BackdropScript := preload("res://scripts/ui/menu/menu_backdrop.gd")
const TitleLogoScript := preload("res://scripts/ui/menu/title_logo.gd")

var _backdrop: Control
var _logo: Control
var _tap: PanelContainer
var _tap_label: Label
var _clock := 0.0
var _armed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = BackdropScript.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	_logo = TitleLogoScript.new()
	_logo.name = "TitleLogo"
	add_child(_logo)

	_tap = PanelContainer.new()
	_tap.name = "TapToStart"
	_tap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := BookKit._box(BookKit.SUN, 6.0, 44, false)
	sb.content_margin_left = 34
	sb.content_margin_right = 40
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_tap.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	row.add_child(KidIcon.make(KidIcon.Kind.TAP, 64, UIStyle.TEXT_PRIMARY))
	_tap_label = UIStyle.label(Loc.t("tap_to_start"), 44, UIStyle.TEXT_PRIMARY, true)
	row.add_child(_tap_label)
	_tap.add_child(row)
	add_child(_tap)

	resized.connect(_layout)
	GameManager.settings_changed.connect(_refresh_text)
	_layout.call_deferred()


func enter() -> void:
	_armed = false
	_clock = 0.0
	_refresh_text()
	_layout()
	if _logo.has_method("play_entry"):
		_logo.play_entry(0.05)


func _refresh_text() -> void:
	_tap_label.text = Loc.t("tap_to_start")
	if _logo.has_method("refresh_text"):
		_logo.refresh_text()
	_layout()


func _layout() -> void:
	if size.x <= 1.0:
		return
	var margin := clampf(size.x * 0.06, 60.0, 168.0)
	var logo_w := minf(size.x * 0.46, 620.0)
	var h: float = _logo.relayout(logo_w, 1.0)
	_logo.position = Vector2(margin, size.y * 0.065)
	_logo.size = Vector2(logo_w, h)
	_tap.reset_size()
	_tap.pivot_offset = _tap.size * 0.5
	_tap.position = Vector2((size.x - _tap.size.x) * 0.5, size.y - _tap.size.y - size.y * 0.08)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	# A short grace so the press that brought us here does not skip straight past.
	if _clock > 0.4:
		_armed = true
	if not BookKit.reduce_motion():
		var k := 1.0 + 0.05 * sin(_clock * 3.2)
		_tap.scale = Vector2(k, k)


func _go() -> void:
	if not _armed:
		return
	_armed = false
	BookKit.sfx(&"ui_tap")
	started.emit()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		_go()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or event.is_echo():
		return
	if (event is InputEventKey and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		_go()
		get_viewport().set_input_as_handled()
