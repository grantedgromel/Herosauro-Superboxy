class_name SettingsPanel
extends Control
## The gear: a parent-friendly settings sheet that a child can also work.
## Every row is a picture first (globe, bubble, speech, turtle, music note,
## speaker) and a word second. Changes apply live and persist through the
## GameManager setters (user://settings.cfg); nothing here keeps its own copy.
##
##   Língua           Português / English, with a globe; never flags
##   Ajudas           on: no losing, softer hits (the default)
##   Narração         the story and the goals are read aloud
##   Menos movimento  calmer camera, no flashes
##   Música / Sons    five steps each, in dB through set_music/sfx_volume
##   Créditos         the old main menu's credits panel
##
## Opened from the bookshelf's gear and from the pause menu. Esc, pad B or the
## big tick closes it.

signal closed()

const MenuModalScript := preload("res://scripts/ui/menu/menu_modal.gd")
const STEPS := 5

var _dim: ColorRect
var _card: Panel
var _heading: Label
var _lang_pt: Button
var _lang_en: Button
var _tiles: Dictionary = {}      # setting -> Button
var _vol: Dictionary = {}        # "music"/"sfx" -> {pips: Array, minus, plus, label}
var _credits: Button
var _close: Button
var _credits_modal: Control
var _labels: Dictionary = {}     # loc id -> Label
var _open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.03, 0.08, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_card = Panel.new()
	_card.name = "Card"
	_card.add_theme_stylebox_override("panel", BookKit.paper_box(36, 0))
	add_child(_card)

	_heading = BookKit.loud_label("", 54, BookKit.SUN)
	_card.add_child(_heading)
	var gear := KidIcon.make(KidIcon.Kind.GEAR, 58, BookKit.SKY)
	gear.name = "HeadingIcon"
	_card.add_child(gear)

	# Language.
	var globe := KidIcon.make(KidIcon.Kind.GLOBE, 64)
	globe.name = "Globe"
	_card.add_child(globe)
	_lang_pt = _toggle_button("lang_pt")
	_lang_pt.pressed.connect(func() -> void: GameManager.set_language("pt"))
	_lang_en = _toggle_button("lang_en")
	_lang_en.pressed.connect(func() -> void: GameManager.set_language("en"))

	# Three on/off tiles.
	for spec in [["assists", KidIcon.Kind.BUBBLE, BookKit.SKY],
			["narration", KidIcon.Kind.SPEECH, BookKit.SUN],
			["reduce_motion", KidIcon.Kind.TURTLE, BookKit.LEAF]]:
		_tiles[spec[0]] = _tile(spec[0], spec[1], spec[2])

	# Volumes.
	_vol["music"] = _volume_row("music", KidIcon.Kind.MUSIC)
	_vol["sfx"] = _volume_row("sounds", KidIcon.Kind.SPEAKER)

	_credits = BookKit.button(Loc.t("credits"), KidIcon.Kind.INFO, BookKit.PLUM, Vector2(240, 84))
	_credits.name = "Credits"
	_credits.pressed.connect(_open_credits)
	_card.add_child(_credits)
	_close = BookKit.button(Loc.t("close"), KidIcon.Kind.CHECK, BookKit.LEAF, Vector2(240, 84))
	_close.name = "Close"
	_close.pressed.connect(close)
	_card.add_child(_close)

	_credits_modal = MenuModalScript.new()
	_credits_modal.name = "CreditsModal"
	add_child(_credits_modal)

	resized.connect(_layout)
	GameManager.settings_changed.connect(_sync)
	_sync()


func open() -> void:
	_open = true
	visible = true
	_sync()
	_layout()
	modulate.a = 0.0
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.94, 0.94)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.18)
	t.tween_property(_card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	_close.call_deferred("grab_focus")


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


func is_open() -> bool:
	return _open


## Read every control's state back from GameManager.
func _sync() -> void:
	_heading.text = Loc.t("settings")
	_mark(_lang_pt, GameManager.language == "pt")
	_mark(_lang_en, GameManager.language == "en")
	for key: String in _tiles:
		var on := bool(GameManager.get(key))
		var b: Button = _tiles[key]
		(b.get_meta("title") as Label).text = Loc.t(key)
		(b.get_meta("hint") as Label).text = Loc.t(key + "_hint")
		var pill := b.get_meta("pill") as PanelContainer
		(pill.get_child(0) as Label).text = Loc.t("on") if on else Loc.t("off")
		var sb := pill.get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = BookKit.LEAF if on else Color("c9bba3")
		# Ink on both fills: cream on green or on the pale "off" fill was
		# under 2:1 and "Não"/"Off" all but vanished.
		(pill.get_child(0) as Label).add_theme_color_override("font_color", BookKit.PRINT)
		(b.get_meta("icon") as Control).modulate = Color.WHITE if on else Color(1, 1, 1, 0.45)
	for key: String in _vol:
		var row: Dictionary = _vol[key]
		(row["label"] as Label).text = Loc.t(str(row["loc"]))
		var step := _step_of(GameManager.music_volume_db if key == "music"
			else GameManager.sfx_volume_db)
		for i in STEPS:
			var pip: Panel = row["pips"][i]
			var psb := pip.get_theme_stylebox("panel") as StyleBoxFlat
			psb.bg_color = BookKit.SUN if i < step else Color(0.2, 0.15, 0.1, 0.18)
	for id: String in _labels:
		(_labels[id] as Label).text = Loc.t(id)
	BookKit.set_caption(_credits, Loc.t("credits"))
	BookKit.set_caption(_close, Loc.t("close"))
	_layout()


static func _step_of(db: float) -> int:
	if db <= -59.0:
		return 0
	return clampi(roundi(db_to_linear(db) * STEPS), 0, STEPS)


static func _db_of(step: int) -> float:
	if step <= 0:
		return -60.0
	return linear_to_db(float(step) / STEPS)


func _nudge(key: String, delta: int) -> void:
	var cur := _step_of(GameManager.music_volume_db if key == "music" else GameManager.sfx_volume_db)
	var nxt := clampi(cur + delta, 0, STEPS)
	if key == "music":
		GameManager.set_music_volume(_db_of(nxt))
	else:
		GameManager.set_sfx_volume(_db_of(nxt))
		BookKit.sfx(&"star")


# --- Builders --------------------------------------------------------------------

func _toggle_button(loc_id: String) -> Button:
	var b := BookKit.button(Loc.t(loc_id), -1, BookKit.PAPER_SHADE, Vector2(230, 84),
		BookKit.PRINT)
	var l := b.get_meta("caption") as Label
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.add_theme_color_override("font_color", BookKit.PRINT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.name = "Lang_" + loc_id
	_card.add_child(b)
	return b


func _mark(b: Button, selected: bool) -> void:
	var fill := BookKit.SUN if selected else BookKit.PAPER_SHADE
	BookKit.style_button_fill(b, fill)


func _tile(key: String, icon: int, tint: Color) -> Button:
	var b := Button.new()
	b.name = "Tile_" + key
	BookKit.style_button(b, BookKit.PAPER_SHADE, 28)
	var ic := KidIcon.make(icon, 66, tint, BookKit.CHERRY)
	b.add_child(ic)
	var title := BookKit.print_label(Loc.t(key), 28, true)
	b.add_child(title)
	var hint := BookKit.print_label(Loc.t(key + "_hint"), 20, false, BookKit.PRINT_SOFT)
	b.add_child(hint)
	var pill := UIStyle.pill("", BookKit.LEAF, BookKit.PRINT, 24)
	b.add_child(pill)
	b.set_meta("icon", ic)
	b.set_meta("title", title)
	b.set_meta("hint", hint)
	b.set_meta("pill", pill)
	b.pressed.connect(func() -> void: _flip(key))
	_card.add_child(b)
	return b


func _flip(key: String) -> void:
	var on := not bool(GameManager.get(key))
	match key:
		"assists":
			GameManager.set_assists(on)
		"narration":
			GameManager.set_narration(on)
		"reduce_motion":
			GameManager.set_reduce_motion(on)


func _volume_row(loc_id: String, icon: int) -> Dictionary:
	var key := "music" if loc_id == "music" else "sfx"
	var ic := KidIcon.make(icon, 56, BookKit.PLUM if key == "music" else BookKit.SKY)
	_card.add_child(ic)
	var label := BookKit.print_label(Loc.t(loc_id), 26, true, BookKit.PRINT,
		HORIZONTAL_ALIGNMENT_LEFT)
	_card.add_child(label)
	var minus := BookKit.round_button(KidIcon.Kind.MINUS, BookKit.PAPER_SHADE, 80.0)
	minus.name = "Minus_" + key
	minus.pressed.connect(func() -> void: _nudge(key, -1))
	_card.add_child(minus)
	var plus := BookKit.round_button(KidIcon.Kind.PLUS, BookKit.SUN, 80.0)
	plus.name = "Plus_" + key
	plus.pressed.connect(func() -> void: _nudge(key, 1))
	_card.add_child(plus)
	var pips: Array = []
	for i in STEPS:
		var pip := UIStyle.chip(BookKit.SUN, 26.0)
		_card.add_child(pip)
		pips.append(pip)
	return {"icon": ic, "label": label, "minus": minus, "plus": plus, "pips": pips, "loc": loc_id}


func _open_credits() -> void:
	_credits_modal.call("open", Loc.t("credits").to_upper(), MenuModalScript.build_credits())


# --- Layout ------------------------------------------------------------------------

func _layout() -> void:
	if size.x <= 1.0 or _card == null:
		return
	var cw := minf(size.x - 64.0, 1120.0)
	var ch := minf(size.y - 40.0, 600.0)
	_card.size = Vector2(cw, ch)
	_card.position = ((size - _card.size) * 0.5).round()
	var pad := 34.0
	var y := 22.0
	_heading.reset_size()
	var head_icon := _card.get_node("HeadingIcon") as Control
	var head_w := _heading.size.x + 70.0
	head_icon.position = Vector2((cw - head_w) * 0.5, y + 4)
	_heading.position = Vector2(head_icon.position.x + 70.0, y)
	y += 84.0

	# Language row.
	var globe := _card.get_node("Globe") as Control
	globe.position = Vector2(pad, y + 10)
	_lang_pt.reset_size()
	_lang_en.reset_size()
	var lang_w := _lang_pt.size.x + _lang_en.size.x + 24.0
	var lx := maxf(pad + 90.0, (cw - lang_w) * 0.5)
	_lang_pt.position = Vector2(lx, y)
	_lang_en.position = Vector2(lx + _lang_pt.size.x + 24.0, y)
	globe.position.x = lx - 84.0
	y += 106.0

	# Tiles.
	var keys := ["assists", "narration", "reduce_motion"]
	var gap := 22.0
	var tw := (cw - pad * 2.0 - gap * 2.0) / 3.0
	var th := clampf(ch * 0.22, 128.0, 150.0)
	for i in keys.size():
		var b: Button = _tiles[keys[i]]
		b.position = Vector2(pad + i * (tw + gap), y)
		b.size = Vector2(tw, th)
		b.pivot_offset = b.size * 0.5
		var ic := b.get_meta("icon") as Control
		ic.position = Vector2(18, 16)
		var title := b.get_meta("title") as Label
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.position = Vector2(96, 14)
		title.size = Vector2(tw - 104, 40)
		var hint := b.get_meta("hint") as Label
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hint.position = Vector2(96, 54)
		hint.size = Vector2(tw - 104, 30)
		var pill := b.get_meta("pill") as Control
		pill.reset_size()
		pill.position = Vector2(tw - pill.size.x - 18, th - pill.size.y - 16)
	y += th + 26.0

	# Volume rows, side by side.
	var half := (cw - pad * 2.0 - gap) * 0.5
	var i_row := 0
	for key in ["music", "sfx"]:
		var row: Dictionary = _vol[key]
		var x := pad + i_row * (half + gap)
		(row["icon"] as Control).position = Vector2(x, y + 12)
		var label := row["label"] as Label
		label.position = Vector2(x + 62, y + 22)
		label.size = Vector2(118, 36)
		var minus := row["minus"] as Control
		var plus := row["plus"] as Control
		minus.position = Vector2(x + 182, y)
		plus.position = Vector2(x + half - 80.0, y)
		var pips: Array = row["pips"]
		var span := plus.position.x - (minus.position.x + 80.0)
		for k in pips.size():
			var pip := pips[k] as Control
			pip.position = Vector2(minus.position.x + 80.0 + span * (k + 0.5) / STEPS - 13.0, y + 27)
		i_row += 1
	y += 128.0

	_credits.reset_size()
	_close.reset_size()
	var fy := ch - 84.0 - 26.0
	_credits.position = Vector2(pad, fy)
	_close.position = Vector2(cw - pad - _close.size.x, fy)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if _credits_modal.has_method("is_open") and _credits_modal.call("is_open"):
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_pause"):
		close()
		get_viewport().set_input_as_handled()
