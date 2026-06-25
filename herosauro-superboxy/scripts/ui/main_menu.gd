extends Control
## Main menu — a real, full-screen menu (NOT an overlay on a live arena). Draws its
## own opaque Porto golden-hour backdrop, then lets the player choose player count,
## difficulty and (in 1P) which hero to control before starting the fight. Every
## selection writes straight to GameManager, which the spawner + boss read at start.

var _hero_row: Control
var _start_btn: Button
var _hint: Label


func _ready() -> void:
	_build_backdrop()

	var title := UIStyle.title("HEROSAURO & SUPER BOXY", 68)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 56.0
	add_child(title)

	var subtitle := UIStyle.label("LEGENDS OF PORTO", 28, UIStyle.CREAM, true)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 140.0
	add_child(subtitle)

	var tagline := UIStyle.label("Defend the Dom Luís Bridge", 19, UIStyle.GOLD)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tagline.offset_top = 178.0
	add_child(tagline)

	# Centred column of selectors + start.
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.offset_left = -360.0
	col.offset_right = 360.0
	col.offset_top = -110.0
	col.offset_bottom = 200.0
	add_child(col)

	var on_players := func(i: int) -> void:
		GameManager.set_player_count(i + 1)
		_hero_row.visible = (i == 0)
	col.add_child(_segment("PLAYERS", ["1 PLAYER", "2 PLAYERS"], GameManager.player_count - 1, on_players))

	var on_difficulty := func(i: int) -> void:
		GameManager.set_difficulty(i)
	col.add_child(_segment("DIFFICULTY", ["EASY", "NORMAL", "HARD"], GameManager.difficulty, on_difficulty))

	var on_hero := func(i: int) -> void:
		GameManager.set_human_hero(i + 1)
	_hero_row = _segment("HERO (1P)", ["HEROSAURO", "SUPER BOXY"], GameManager.human_hero - 1, on_hero)
	_hero_row.visible = (GameManager.player_count == 1)
	col.add_child(_hero_row)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	col.add_child(spacer)

	_start_btn = UIStyle.button("▶  START", true)
	_start_btn.pressed.connect(_on_start)
	col.add_child(_start_btn)

	# Controls footer.
	_hint = UIStyle.label(_controls_text(), 17, UIStyle.MUTED)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -52.0
	_hint.offset_bottom = -22.0
	add_child(_hint)

	_start_btn.call_deferred("grab_focus")


func _controls_text() -> String:
	return "P1 Herosauro  ·  WASD  ·  Shift jump  ·  E special  ·  Q attack        " \
		+ "P2 Super Boxy  ·  Arrows  ·  / jump  ·  Space special  ·  . attack"


# --- Selectors -------------------------------------------------------------

## A labelled row of mutually-exclusive option buttons. `cb` is called with the
## chosen index; the chosen button is highlighted and the rest dimmed.
func _segment(label_text: String, options: Array, initial: int, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)

	var lbl := UIStyle.label(label_text, 20, UIStyle.MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)
	lbl.custom_minimum_size = Vector2(170, 0)
	row.add_child(lbl)

	var btns: Array = []
	for i in options.size():
		var b := UIStyle.button(options[i])
		b.custom_minimum_size = Vector2(160, 52)
		b.add_theme_font_size_override("font_size", 22)
		var idx := i
		var handler := func() -> void:
			cb.call(idx)
			_highlight(btns, idx)
		b.pressed.connect(handler)
		row.add_child(b)
		btns.append(b)

	_highlight(btns, initial)
	return row


func _highlight(btns: Array, selected: int) -> void:
	for i in btns.size():
		var b: Button = btns[i]
		b.modulate = Color(1, 1, 1, 1) if i == selected else Color(0.62, 0.6, 0.66, 0.8)


# --- Backdrop --------------------------------------------------------------

func _build_backdrop() -> void:
	# Opaque Porto golden-hour gradient so no gameplay (and nothing else) shows through.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(0.30, 0.20, 0.34),   # dusk purple (top)
		Color(0.55, 0.32, 0.34),   # warm rose
		Color(0.86, 0.55, 0.36),   # terracotta glow (bottom)
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 8
	gt.height = 256
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Soft dark scrims top and bottom for title / footer legibility.
	_scrim(true, 300.0)
	_scrim(false, 200.0)


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


# --- Start -----------------------------------------------------------------

func _on_start() -> void:
	GameManager.start_game()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_confirm"):
		GameManager.start_game()
		get_viewport().set_input_as_handled()
