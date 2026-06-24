extends Control
## Victory / Defeat screen. Appears a beat after the fight ends (letting the boss
## death + camera zoom play on a win), shows the result, score and time, and
## offers Play Again / Main Menu.

const SHADOW := Color(0.0, 0.0, 0.0, 0.9)
const VICTORY_COLOR := Color(0.45, 0.95, 0.4)
const DEFEAT_COLOR := Color(0.95, 0.35, 0.35)

var _dim: ColorRect
var _title: Label
var _subtitle: Label
var _stats: Label
var _again_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.02, 0.06, 0.7)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -300.0
	box.offset_right = 300.0
	box.offset_top = -200.0
	box.offset_bottom = 200.0
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	_title = _make_label("", 72, VICTORY_COLOR)
	box.add_child(_title)
	_subtitle = _make_label("", 26, Color(1, 0.97, 0.9))
	box.add_child(_subtitle)
	_stats = _make_label("", 28, Color(1, 0.9, 0.6))
	box.add_child(_stats)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(spacer)

	_again_btn = _make_button("▶  Play Again")
	_again_btn.pressed.connect(_on_play_again)
	box.add_child(_again_btn)

	var menu_btn := _make_button("≡  Main Menu")
	menu_btn.pressed.connect(_on_main_menu)
	box.add_child(menu_btn)

	GameManager.game_over.connect(_on_game_over)
	GameManager.game_started.connect(_hide_now)


func _on_game_over(victory: bool) -> void:
	# Let the death animation / camera zoom breathe before the screen appears.
	var delay := 2.0 if victory else 1.0
	await get_tree().create_timer(delay).timeout
	# Bail out if the player already restarted during the delay.
	if GameManager.state != GameManager.State.VICTORY and GameManager.state != GameManager.State.DEFEAT:
		return

	if victory:
		_title.text = "VICTORY!"
		_title.add_theme_color_override("font_color", VICTORY_COLOR)
		_subtitle.text = "Herosauro & Super Boxy saved Porto!"
		AudioManager.play_victory()
	else:
		_title.text = "DEFEAT"
		_title.add_theme_color_override("font_color", DEFEAT_COLOR)
		_subtitle.text = "Adamastor wins this round…"
		AudioManager.play_defeat()

	var m := int(GameManager.fight_time) / 60
	var s := int(GameManager.fight_time) % 60
	_stats.text = "Score: %d        Time: %d:%02d" % [GameManager.score, m, s]

	visible = true
	_again_btn.grab_focus()


func _hide_now() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_confirm"):
		_on_play_again()
		get_viewport().set_input_as_handled()


func _on_play_again() -> void:
	visible = false
	GameManager.start_game()


func _on_main_menu() -> void:
	visible = false
	GameManager.go_to_menu()


# --- Builders --------------------------------------------------------------

func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", SHADOW)
	l.add_theme_constant_override("outline_size", 8)
	return l


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 56)
	b.add_theme_font_size_override("font_size", 26)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b
