extends Control
## Victory / Defeat screen — a polished centred card with the result, run stats
## and replay options. Appears a beat after the fight ends.

var _dim: ColorRect
var _title: Label
var _subtitle: Label
var _stats: Label
var _again_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.02, 0.06, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.panel(Color(0.07, 0.06, 0.11, 0.96), 22, 34))
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -300.0
	card.offset_right = 300.0
	card.offset_top = -220.0
	card.offset_bottom = 220.0
	add_child(card)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)

	_title = UIStyle.title("", 76, UIStyle.VICTORY)
	box.add_child(_title)
	_subtitle = UIStyle.label("", 24, UIStyle.CREAM)
	box.add_child(_subtitle)

	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(0, 2)
	var dsb := StyleBoxFlat.new(); dsb.bg_color = Color(1, 1, 1, 0.12)
	divider.add_theme_stylebox_override("panel", dsb)
	box.add_child(divider)

	_stats = UIStyle.label("", 26, UIStyle.GOLD, true)
	box.add_child(_stats)

	var spacer := Control.new(); spacer.custom_minimum_size = Vector2(0, 14)
	box.add_child(spacer)

	_again_btn = UIStyle.button("▶  PLAY AGAIN", true)
	_again_btn.pressed.connect(_on_play_again)
	box.add_child(_again_btn)
	var menu_btn := UIStyle.button("MAIN MENU")
	menu_btn.pressed.connect(_on_main_menu)
	box.add_child(menu_btn)

	GameManager.game_over.connect(_on_game_over)
	GameManager.game_started.connect(_hide_now)


func _on_game_over(victory: bool) -> void:
	await get_tree().create_timer(2.0 if victory else 1.0).timeout
	if GameManager.state != GameManager.State.VICTORY and GameManager.state != GameManager.State.DEFEAT:
		return
	if victory:
		_title.text = "VICTORY!"
		_title.add_theme_color_override("font_color", UIStyle.VICTORY)
		_subtitle.text = "Porto is safe — the brothers triumph!"
		AudioManager.play_victory()
	else:
		_title.text = "DEFEAT"
		_title.add_theme_color_override("font_color", UIStyle.DEFEAT)
		_subtitle.text = "Adamastor stands unbroken…"
		AudioManager.play_defeat()
	var m := int(GameManager.fight_time) / 60
	var s := int(GameManager.fight_time) % 60
	_stats.text = "SCORE  %d        TIME  %d:%02d" % [GameManager.score, m, s]
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
