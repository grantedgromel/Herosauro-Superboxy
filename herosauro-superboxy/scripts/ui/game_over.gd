extends Control
## The end of a chapter's play, in the storybook frame.
##
## VICTORY: the heroes hold their pose for a moment, then the book opens again
## for the chapter's last pages (the outro, read aloud like the intro), then a
## sticker lands on the chapter's cover ("Muito bem! Ganhaste um
## autocolante!") and Continue goes back to the bookshelf, where the next
## story is waiting, highlighted. The sticker is recorded the moment the
## chapter is won, so skipping the pages never loses it.
##
## DEFEAT only exists with Ajudas off. It is never called a defeat: "Vamos
## tentar outra vez!", the two brothers smiling, Try again and Back to the
## book. No loss language anywhere (docs/story/ADAPTATION.md, kid rule 5).
##
## The outro runs while GameManager is in VICTORY; Continue calls go_to_menu.

const POSE_WAIT := 2.6   # long enough to watch Adamastor's Douro splash land
const RETRY_WAIT := 1.0

var phase: String = ""            # "", "pose", "outro", "sticker", "retry"
var chapter_id: String = ""

var _reader: PageReader
var _dim: ColorRect
var _sticker_card: Panel
var _retry_card: Panel
var _cover: BookCover
var _well_done: Label
var _sticker_line: Label
var _stars: Array[KidIcon] = []
var _continue: Button
var _retry_title: Label
var _retry_body: Label
var _again: Button
var _to_book: Button
var _voice: Narrator
var _token := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.03, 0.08, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_reader = PageReader.new()
	_reader.name = "Outro"
	add_child(_reader)
	_reader.finished.connect(func(_skipped: bool) -> void: _show_sticker())

	_build_sticker_card()
	_build_retry_card()

	_voice = Narrator.new()
	_voice.name = "Voice"
	add_child(_voice)

	resized.connect(_layout)
	GameManager.game_over.connect(_on_game_over)
	GameManager.game_started.connect(_hide_now)
	GameManager.settings_changed.connect(_refresh_text)


func _build_sticker_card() -> void:
	_sticker_card = Panel.new()
	_sticker_card.name = "StickerCard"
	_sticker_card.add_theme_stylebox_override("panel", BookKit.paper_box(36, 0))
	_sticker_card.visible = false
	add_child(_sticker_card)
	_well_done = BookKit.loud_label("", 70, BookKit.SUN)
	_sticker_card.add_child(_well_done)
	_sticker_line = BookKit.print_label("", 32, true)
	_sticker_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sticker_card.add_child(_sticker_line)
	for i in 3:
		var st := KidIcon.make(KidIcon.Kind.STAR, 72, BookKit.SUN)
		_sticker_card.add_child(st)
		_stars.append(st)
	_continue = BookKit.button(Loc.t("continue"), KidIcon.Kind.NEXT, BookKit.LEAF, Vector2(300, 92))
	_continue.name = "Continue"
	_continue.pressed.connect(_on_continue)
	_sticker_card.add_child(_continue)


func _build_retry_card() -> void:
	_retry_card = Panel.new()
	_retry_card.name = "RetryCard"
	_retry_card.add_theme_stylebox_override("panel", BookKit.paper_box(36, 0))
	_retry_card.visible = false
	add_child(_retry_card)
	var heads := HBoxContainer.new()
	heads.name = "Heads"
	heads.add_theme_constant_override("separation", 18)
	heads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for actor in [UIStyle.Actor.HEROSAURO, UIStyle.Actor.SUPERBOXY]:
		var f := PortraitFrame.new()
		f.actor = actor
		f.custom_minimum_size = Vector2(132, 132)
		heads.add_child(f)
	_retry_card.add_child(heads)
	_retry_title = BookKit.loud_label("", 60, BookKit.SUN)
	_retry_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_retry_card.add_child(_retry_title)
	_retry_body = BookKit.print_label("", 28, false)
	_retry_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_retry_card.add_child(_retry_body)
	_again = BookKit.button(Loc.t("try_again"), KidIcon.Kind.RETRY, BookKit.SUN, Vector2(300, 92))
	_again.name = "TryAgain"
	_again.pressed.connect(_on_try_again)
	_retry_card.add_child(_again)
	_to_book = BookKit.button(Loc.t("back_to_book"), KidIcon.Kind.BOOK, BookKit.PLUM, Vector2(300, 92))
	_to_book.name = "BackToBook"
	_to_book.pressed.connect(_on_back_to_book)
	_retry_card.add_child(_to_book)


# --- Flow ----------------------------------------------------------------------------

func _on_game_over(victory: bool) -> void:
	_token += 1
	var mine := _token
	chapter_id = GameManager.chapter_id
	UIProgress.submit(GameManager.score, GameManager.fight_time, victory)
	if victory:
		UIProgress.complete_chapter(chapter_id)
	phase = "pose"
	await get_tree().create_timer(POSE_WAIT if victory else RETRY_WAIT, true, false, true).timeout
	if mine != _token or phase != "pose":
		return
	if victory:
		_show_outro()
	else:
		_show_retry()


func _show_outro() -> void:
	phase = "outro"
	visible = true
	_dim.visible = false
	_sticker_card.visible = false
	_retry_card.visible = false
	var pages: Array = StoryData.chapter(chapter_id).get("outro", [])
	if pages.is_empty():
		_show_sticker()
		return
	_reader.modulate.a = 0.0
	_reader.open(chapter_id, "outro")
	create_tween().tween_property(_reader, "modulate:a", 1.0, 0.4)


func _show_sticker() -> void:
	phase = "sticker"
	visible = true
	_reader.close()
	_dim.visible = true
	_retry_card.visible = false
	if _cover != null:
		_cover.queue_free()
	_cover = BookCover.new()
	_cover.focus_mode = Control.FOCUS_NONE
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sticker_card.add_child(_cover)
	_cover.setup(chapter_id if StoryData.CHAPTERS.has(chapter_id) else "adamastor")
	_refresh_text()
	_layout()
	_sticker_card.visible = true
	_cover.play_sticker()
	_pop_card(_sticker_card)
	for i in _stars.size():
		_stars[i].pivot_offset = _stars[i].size * 0.5
		if BookKit.reduce_motion():
			_stars[i].scale = Vector2.ONE
			continue
		_stars[i].scale = Vector2.ZERO
		var t := create_tween()
		t.tween_interval(0.6 + i * 0.18)
		t.tween_callback(func() -> void: BookKit.sfx(&"star"))
		t.tween_property(_stars[i], "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
	_continue.call_deferred("grab_focus")
	_say([Loc.t("well_done"), Loc.t("sticker_won")])


func _show_retry() -> void:
	phase = "retry"
	visible = true
	_reader.close()
	_dim.visible = true
	_sticker_card.visible = false
	_refresh_text()
	_layout()
	_retry_card.visible = true
	_pop_card(_retry_card)
	_again.call_deferred("grab_focus")
	_say([Loc.t("try_again_title")])


func _pop_card(card: Control) -> void:
	card.pivot_offset = card.size * 0.5
	if BookKit.reduce_motion():
		return
	card.scale = Vector2(0.86, 0.86)
	card.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	t.tween_property(card, "modulate:a", 1.0, 0.25)


func _say(lines: Array) -> void:
	if GameManager.narration:
		_voice.speak(" ".join(lines), Loc.lang())


func _on_continue() -> void:
	_voice.stop()
	_hide_now()
	GameManager.go_to_menu()


func _on_try_again() -> void:
	_voice.stop()
	_hide_now()
	GameManager.start_game()


func _on_back_to_book() -> void:
	_voice.stop()
	_hide_now()
	GameManager.go_to_menu()


func _hide_now() -> void:
	_token += 1
	phase = ""
	_reader.close()
	_voice.stop()
	visible = false


func _refresh_text() -> void:
	_well_done.text = Loc.t("well_done")
	_sticker_line.text = Loc.t("sticker_won")
	_retry_title.text = Loc.t("try_again_title")
	_retry_body.text = Loc.t("try_again_body")
	BookKit.set_caption(_continue, Loc.t("continue"))
	BookKit.set_caption(_again, Loc.t("try_again"))
	BookKit.set_caption(_to_book, Loc.t("back_to_book"))
	if _cover != null:
		_cover.refresh()
	_layout()


func _layout() -> void:
	if size.x <= 1.0:
		return
	# Sticker card: the cover on the left, the cheer on the right.
	var cw := minf(size.x - 80.0, 960.0)
	var ch := minf(size.y - 80.0, 520.0)
	_sticker_card.size = Vector2(cw, ch)
	_sticker_card.position = ((size - _sticker_card.size) * 0.5).round()
	var cover_h := ch - 110.0
	var cover_w := cover_h * 0.74
	if _cover != null:
		_cover.position = Vector2(48, 56)
		_cover.size = Vector2(cover_w, cover_h)
	var rx := 48.0 + cover_w + 48.0
	var rw := cw - rx - 40.0
	BookKit.place(_well_done, Vector2(rx, 44), Vector2(rw, 90))
	BookKit.place(_sticker_line, Vector2(rx, 140), Vector2(rw, 90))
	for i in _stars.size():
		_stars[i].position = Vector2(rx + rw * 0.5 - 132.0 + i * 96.0, 238 - (16 if i == 1 else 0))
	_continue.reset_size()
	_continue.position = Vector2(rx + (rw - _continue.size.x) * 0.5, ch - _continue.size.y - 44)

	# Try-again card, centred column.
	var tw := minf(size.x - 80.0, 820.0)
	var th := minf(size.y - 80.0, 520.0)
	_retry_card.size = Vector2(tw, th)
	_retry_card.position = ((size - _retry_card.size) * 0.5).round()
	var heads := _retry_card.get_node("Heads") as Control
	heads.reset_size()
	heads.position = Vector2((tw - heads.size.x) * 0.5, 34)
	BookKit.place(_retry_title, Vector2(30, 186), Vector2(tw - 60, 80))
	BookKit.place(_retry_body, Vector2(40, 270), Vector2(tw - 80, 70))
	_again.reset_size()
	_to_book.reset_size()
	var bw := _again.size.x + _to_book.size.x + 36.0
	_again.position = Vector2((tw - bw) * 0.5, th - _again.size.y - 40)
	_to_book.position = Vector2(_again.position.x + _again.size.x + 36.0, _again.position.y)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if phase == "sticker" and event.is_action_pressed("ui_cancel"):
		_on_continue()
		get_viewport().set_input_as_handled()
	elif phase == "retry" and event.is_action_pressed("ui_cancel"):
		_on_back_to_book()
		get_viewport().set_input_as_handled()
