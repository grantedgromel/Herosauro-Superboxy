extends Control
## Main menu overlay — sits over the live 3D arena. Polished: comic-style title,
## soft scrims for legibility, a pulsing start prompt, and a clean controls bar.

var _prompt: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim(true, 380.0)
	_scrim(false, 240.0)

	var title := UIStyle.title("HEROSAURO & SUPER BOXY", 74)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 78.0
	add_child(title)

	var subtitle := UIStyle.label("LEGENDS OF PORTO", 30, UIStyle.CREAM, true)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 168.0
	add_child(subtitle)

	var tagline := UIStyle.label("Defend the Dom Luís Bridge", 20, UIStyle.GOLD)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tagline.offset_top = 210.0
	add_child(tagline)

	# Pulsing start prompt in a subtle pill.
	_prompt = _pill("PRESS ENTER TO START")
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -190.0
	_prompt.offset_right = 190.0
	_prompt.offset_top = 50.0
	_prompt.offset_bottom = 108.0
	add_child(_prompt)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_prompt, "modulate:a", 0.35, 0.75).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_prompt, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_SINE)

	# Controls footer.
	var p1 := UIStyle.label("HEROSAURO   ·   WASD move   ·   Shift jump   ·   E summon", 19, UIStyle.CREAM)
	p1.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	p1.offset_top = -98.0
	p1.offset_bottom = -68.0
	add_child(p1)
	var p2 := UIStyle.label("SUPER BOXY   ·   Arrows move   ·   / jump   ·   Space dash", 19, UIStyle.CREAM)
	p2.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	p2.offset_top = -64.0
	p2.offset_bottom = -34.0
	add_child(p2)


func _pill(text: String) -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIStyle.panel(Color(0.08, 0.06, 0.12, 0.6), 30, 12)
	sb.border_color = UIStyle.GOLD
	sb.border_width_left = 2; sb.border_width_right = 2; sb.border_width_top = 2; sb.border_width_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	var l := UIStyle.label(text, 28, UIStyle.GOLD, true)
	pc.add_child(l)
	return pc


func _scrim(top: bool, height: float) -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(0.05, 0.04, 0.09, 0.62), Color(0.05, 0.04, 0.09, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 8
	gt.height = 256
	gt.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
	gt.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	if top:
		tr.offset_bottom = height
	else:
		tr.offset_top = -height


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_confirm"):
		GameManager.start_game()
		get_viewport().set_input_as_handled()
