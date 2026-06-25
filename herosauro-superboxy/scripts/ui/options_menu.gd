class_name OptionsMenu
extends Control
## Options overlay — master / SFX / music volume sliders + fullscreen toggle,
## bound live to the Settings autoload and saved on Back. Full-screen card with
## its own dim so it cleanly covers whatever is behind it. Built in code to match
## the rest of the UI. Frees itself when closed.

signal closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.panel(Color(0.07, 0.06, 0.11, 0.97), 22, 32))
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -300.0
	card.offset_right = 300.0
	card.offset_top = -210.0
	card.offset_bottom = 210.0
	add_child(card)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)

	box.add_child(UIStyle.title("OPTIONS", 52))

	_add_slider(box, "MASTER", Settings.master_volume, Settings.set_master_volume)
	_add_slider(box, "SFX", Settings.sfx_volume, Settings.set_sfx_volume)
	_add_slider(box, "MUSIC", Settings.music_volume, Settings.set_music_volume)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	box.add_child(spacer)

	var fs := UIStyle.button("Toggle Fullscreen")
	fs.pressed.connect(_on_fullscreen)
	box.add_child(fs)

	var back := UIStyle.button("◀  BACK", true)
	back.pressed.connect(_on_back)
	box.add_child(back)
	back.call_deferred("grab_focus")


func _add_slider(box: VBoxContainer, label_text: String, value: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var lbl := UIStyle.label(label_text, 20, UIStyle.MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)
	lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(lbl)

	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = value
	sl.custom_minimum_size = Vector2(330, 28)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(v: float) -> void: setter.call(v))
	row.add_child(sl)

	box.add_child(row)


func _on_fullscreen() -> void:
	Settings.toggle_fullscreen()
	AudioManager.play_ui()


func _on_back() -> void:
	Settings.save_settings()
	AudioManager.play_ui()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_pause"):
		_on_back()
		get_viewport().set_input_as_handled()
