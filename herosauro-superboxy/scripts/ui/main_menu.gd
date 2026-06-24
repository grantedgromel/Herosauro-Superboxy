extends Control
## Main menu overlay. Sits transparently over the live 3D arena (the bridge and
## a menacingly idling Adamastor show through behind it). ENTER starts the game.

const GOLD := Color(1.0, 0.84, 0.2)
const CREAM := Color(1.0, 0.97, 0.9)
const SHADOW := Color(0.1, 0.05, 0.0, 0.9)

var _prompt: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# A soft dark banner behind the title for legibility over the bright sky.
	var banner := ColorRect.new()
	banner.color = Color(0.05, 0.05, 0.1, 0.45)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 70.0
	banner.offset_bottom = 290.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)

	var title := _label("HEROSAURO & SUPER BOXY", 64, GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 96.0
	add_child(title)

	var subtitle := _label("Legends of Porto", 36, CREAM)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 178.0
	add_child(subtitle)

	var crest := _label("⚔  Defend the Dom Luís Bridge  ⚔", 22, Color(0.95, 0.7, 0.45))
	crest.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	crest.offset_top = 232.0
	add_child(crest)

	_prompt = _label("Press ENTER to Start", 34, CREAM)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_top = 60.0
	_prompt.offset_bottom = 110.0
	add_child(_prompt)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_prompt, "modulate:a", 0.15, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_prompt, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

	var controls := _label(
		"HEROSAURO (P1):  WASD move   ·   Shift jump   ·   E = Dino Energy\n" +
		"SUPER BOXY (P2):  Arrows move   ·   / jump   ·   Space = Boxy Dash",
		20, CREAM)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -110.0
	controls.offset_bottom = -30.0
	add_child(controls)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", SHADOW)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_confirm"):
		GameManager.start_game()
		get_viewport().set_input_as_handled()
