class_name WhoPlays
extends Control
## "Who's playing?" Two big pictures, not a menu: one child, or two.
##
## One child then picks a brother; the other brother comes along as the AI
## helper (he wears a little robot-and-heart badge in the HUD). Two children
## play Herosauro and Super Boxy side by side. The last choice is remembered
## and is where focus starts next time.

signal chosen(players: int, hero: int)
signal back_requested()

var step := 0            # 0 = how many players, 1 = which hero (solo)

var _wall: PaperWall
var _title: Label
var _back: Button
var _cards: Array[Button] = []
var _note: HBoxContainer
var _note_label: Label
var _host: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_wall = PaperWall.new()
	_wall.seed_value = 19
	add_child(_wall)
	_title = BookKit.loud_label("", 66, BookKit.SUN)
	_title.name = "Title"
	add_child(_title)
	_host = Control.new()
	_host.name = "Cards"
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_host)
	_back = BookKit.round_button(KidIcon.Kind.BACK, BookKit.PLUM, 96.0)
	_back.name = "Back"
	_back.pressed.connect(go_back)
	add_child(_back)

	_note = HBoxContainer.new()
	_note.name = "HelperNote"
	_note.alignment = BoxContainer.ALIGNMENT_CENTER
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.add_theme_constant_override("separation", 12)
	_note.add_child(KidIcon.make(KidIcon.Kind.ROBOT, 54, Color("bfe3ff"), BookKit.CHERRY))
	_note.add_child(KidIcon.make(KidIcon.Kind.HEART, 44, BookKit.CHERRY))
	_note_label = BookKit.print_label("", 30, true)
	_note.add_child(_note_label)
	add_child(_note)

	resized.connect(_layout)
	GameManager.settings_changed.connect(_refresh_text)
	show_step(0)


func enter() -> void:
	show_step(0)


func go_back() -> void:
	if step == 1:
		show_step(0)
	else:
		back_requested.emit()


func show_step(which: int) -> void:
	step = which
	for c in _cards:
		_host.remove_child(c)
		c.queue_free()
	_cards.clear()
	if step == 0:
		_cards.append(_card_players(1))
		_cards.append(_card_players(2))
	else:
		_cards.append(_card_hero(1))
		_cards.append(_card_hero(2))
	for c in _cards:
		_host.add_child(c)
	_note.visible = step == 1
	_refresh_text()
	_layout()
	var last_players := int(UIProgress.get_pref("players", 1))
	var last_hero := int(UIProgress.get_pref("hero", 1))
	var focus_i := (last_players - 1) if step == 0 else (last_hero - 1)
	var target := _cards[clampi(focus_i, 0, 1)]
	(func() -> void:
		if is_instance_valid(target) and target.is_inside_tree():
			target.grab_focus()).call_deferred()


func pick_players(n: int) -> void:
	if n >= 2:
		chosen.emit(2, 1)
	else:
		show_step(1)


func pick_hero(hero: int) -> void:
	chosen.emit(1, hero)


func _refresh_text() -> void:
	_title.text = Loc.t("who_title") if step == 0 else Loc.t("pick_hero")
	_note_label.text = Loc.t("helper_note")
	for c in _cards:
		var l := (c.get_meta("caption") if c.has_meta("caption") else null) as Label
		if l != null:
			l.text = Loc.t(str(c.get_meta("loc_id")))
	_layout()


func _card(fill: Color) -> Button:
	var b := Button.new()
	b.clip_contents = false
	BookKit.style_button(b, fill, 36)
	return b


func _card_players(n: int) -> Button:
	var b := _card(BookKit.PAPER)
	b.name = "Players%d" % n
	b.set_meta("loc_id", "one_player" if n == 1 else "two_players")
	var icon := KidIcon.make(KidIcon.Kind.PERSON if n == 1 else KidIcon.Kind.TWO_PEOPLE,
		150, BookKit.SKY if n == 1 else BookKit.LEAF, BookKit.CHERRY)
	icon.name = "Icon"
	b.add_child(icon)
	var heads := HBoxContainer.new()
	heads.name = "Heads"
	heads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heads.alignment = BoxContainer.ALIGNMENT_CENTER
	heads.add_theme_constant_override("separation", -14 if n == 2 else 6)
	if n == 2:
		for actor in [UIStyle.Actor.HEROSAURO, UIStyle.Actor.SUPERBOXY]:
			var f := PortraitFrame.new()
			f.actor = actor
			f.custom_minimum_size = Vector2(96, 96)
			heads.add_child(f)
	else:
		# One child, and a helper: the robot-and-heart the AI brother wears.
		heads.add_child(KidIcon.make(KidIcon.Kind.ROBOT, 76, Color("bfe3ff"), BookKit.CHERRY))
		heads.add_child(KidIcon.make(KidIcon.Kind.HEART, 60, BookKit.CHERRY))
	b.add_child(heads)
	var l := UIStyle.label("", 40, UIStyle.TEXT_PRIMARY, true)
	l.add_theme_color_override("font_color", BookKit.PRINT)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	b.add_child(l)
	b.set_meta("caption", l)
	b.pressed.connect(func() -> void: pick_players(n))
	return b


func _card_hero(hero: int) -> Button:
	var actor := UIStyle.actor_for_player(hero)
	var b := _card(UIStyle.actor_color(actor).lightened(0.55))
	b.name = "Hero%d" % hero
	b.set_meta("loc_id", "helper")
	var fig := TextureRect.new()
	fig.name = "Figure"
	fig.texture = UIStyle.portrait_scaled(actor, 480)
	fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(fig)
	var name_l := UIStyle.title(UIStyle.actor_name(actor), 44, UIStyle.TEXT_PRIMARY)
	name_l.name = "Name"
	b.add_child(name_l)
	b.pressed.connect(func() -> void: pick_hero(hero))
	return b


func _layout() -> void:
	if size.x <= 1.0:
		return
	var m := 28.0
	_back.position = Vector2(m, m)
	_title.reset_size()
	_title.position = Vector2((size.x - _title.size.x) * 0.5, m + 8)
	var top := _title.position.y + _title.size.y + 24.0
	var bottom_room := 110.0 if step == 1 else 40.0
	var h := clampf(size.y - top - bottom_room - m, 300.0, 470.0)
	var w := clampf(h * (0.98 if step == 0 else 0.80), 260.0, minf(460.0, (size.x - 2.0 * m - 180.0) * 0.5))
	var gap := 80.0
	var x0 := (size.x - (w * 2.0 + gap)) * 0.5
	for i in _cards.size():
		var c := _cards[i]
		c.position = Vector2(x0 + i * (w + gap), top)
		c.size = Vector2(w, h)
		c.pivot_offset = c.size * 0.5
		if step == 0:
			var icon := c.get_node("Icon") as Control
			var ik := minf(h * 0.42, w * 0.5)
			icon.size = Vector2(ik, ik)
			icon.position = Vector2((w - ik) * 0.5, h * 0.08)
			var heads := c.get_node("Heads") as Control
			heads.reset_size()
			heads.position = Vector2((w - heads.size.x) * 0.5, h * 0.08 + ik - 10)
			var l := c.get_meta("caption") as Label
			l.position = Vector2(0, h - 90)
			l.size = Vector2(w, 70)
		else:
			var fig := c.get_node("Figure") as Control
			fig.position = Vector2(20, 16)
			fig.size = Vector2(w - 40, h - 96)
			var nm := c.get_node("Name") as Label
			nm.position = Vector2(0, h - 82)
			nm.size = Vector2(w, 64)
	_note.reset_size()
	_note.position = Vector2((size.x - _note.size.x) * 0.5, size.y - m - _note.size.y - 10)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()
