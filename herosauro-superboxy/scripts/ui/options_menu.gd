extends Control
## Reusable options panel: audio mix + accessibility + window, backed by Settings.
## Shown as an overlay from the main menu and the pause menu. Applies every change
## live and persists on close. Processes while paused so it works from the pause
## overlay. Emits `closed` and frees itself when the player backs out.

signal closed

const OPTS_SHAKE_MAX := 1.5   # UI 0..1 maps to Settings.shake_scale 0..OPTS_SHAKE_MAX


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.80)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel(UIStyle.PANEL_BG, 18, 30))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.offset_top = -260.0
	panel.offset_bottom = 260.0
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	col.add_child(UIStyle.title("OPTIONS", 46))
	col.add_child(_spacer(8))
	col.add_child(_slider("Master Volume", Settings.master_volume, func(v: float) -> void: Settings.set_master(v)))
	col.add_child(_slider("Music Volume", Settings.music_volume, func(v: float) -> void: Settings.set_music(v)))
	col.add_child(_slider("SFX Volume", Settings.sfx_volume, func(v: float) -> void: Settings.set_sfx(v)))
	col.add_child(_slider("Screen Shake", Settings.shake_scale / OPTS_SHAKE_MAX,
		func(v: float) -> void: Settings.set_shake_scale(v * OPTS_SHAKE_MAX)))
	col.add_child(_toggle("Hit-Stop (freeze frames)", Settings.hit_stop, func(b: bool) -> void: Settings.set_hit_stop(b)))
	col.add_child(_toggle("Fullscreen", Settings.fullscreen, func(b: bool) -> void: Settings.set_fullscreen(b)))
	col.add_child(_spacer(10))

	var back := UIStyle.button("◀  BACK", true)
	back.pressed.connect(_on_back)
	col.add_child(back)
	back.call_deferred("grab_focus")


func _slider(text: String, initial: float, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lbl := UIStyle.label(text, 20, UIStyle.CREAM, true, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.custom_minimum_size = Vector2(280, 0)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = clampf(initial, 0.0, 1.0)
	sl.custom_minimum_size = Vector2(230, 26)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(v: float) -> void: cb.call(v))
	row.add_child(sl)
	return row


func _toggle(text: String, initial: bool, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lbl := UIStyle.label(text, 20, UIStyle.CREAM, true, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.custom_minimum_size = Vector2(280, 0)
	row.add_child(lbl)
	var chk := CheckButton.new()
	chk.button_pressed = initial
	chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chk.toggled.connect(func(b: bool) -> void: cb.call(b))
	row.add_child(chk)
	return row


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _on_back() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()
