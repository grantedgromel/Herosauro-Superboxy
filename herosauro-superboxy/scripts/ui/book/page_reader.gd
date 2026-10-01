class_name PageReader
extends Control
## The book, one page at a time: a chapter's intro before play, its outro after
## the win. Full screen. The picture fills the frame (PageArt), the words sit on
## a sheet of paper along the bottom in big Fredoka, and the page is read
## aloud with each word lit as it is spoken.
##
## Kid rules this follows (docs/story/ADAPTATION.md):
##   * voice first: every page is spoken when Narração is on, and the speaker
##     button reads it again at any time;
##   * big targets: Next, Back and Skip are well over 76 px;
##   * anything advances: a tap or click anywhere, Enter, Space, the arrow
##     keys, any pad button. Left, Esc and pad B go back a page. Start skips;
##   * pages are skippable, and narration stops on every page change and skip.
##
## The reader is screen furniture only; it never touches GameManager state.
## Its owner decides what finishing means (start the run, award the sticker).

signal finished(skipped: bool)
## Back pressed on the first page: the owner may step out of the book.
signal back_requested()
signal page_changed(index: int)

const TURN_TIME := 0.5
const INPUT_GRACE := 0.35
const TEXT_PX := 34
const TEXT_PX_MIN := 26
const SIDE := 136.0          # room for the round buttons beside the paper
const NEXT_D := 116.0
const PAPER_PAD_X := 26.0
const PAPER_PAD_Y := 18.0
const BACK_D := 96.0

var chapter_id: String = ""
var part: String = "intro"
var pages: Array = []
var index: int = 0

var _narrator: Narrator
var _art_host: Control
var _art: PageArt
var _paper: Panel
var _text: RichTextLabel
var _plain: String = ""
var _word := -1
var _next: Button
var _back: Button
var _skip: Button
var _listen: Button
var _dots: HBoxContainer
var _grace := 0.0
var _idle := 0.0
var _open := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_relayout)
	GameManager.settings_changed.connect(_on_settings_changed)
	visible = false


func _build() -> void:
	var ground := ColorRect.new()
	ground.color = Color("1b1420")
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground)

	_art_host = Control.new()
	_art_host.name = "ArtHost"
	_art_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_art_host)

	# A soft darkening under the paper and under the top bar, so the buttons
	# and the words always sit on something calm, whatever the art does.
	add_child(UIStyle.scrim(false, 300.0, 0.42))
	add_child(UIStyle.scrim(true, 130.0, 0.30))

	_paper = Panel.new()
	_paper.name = "Paper"
	_paper.add_theme_stylebox_override("panel", BookKit.paper_box(30, 22))
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paper)
	_text = RichTextLabel.new()
	_text.name = "PageText"
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_override("normal_font", UIStyle.UI_FONT)
	_text.add_theme_font_override("bold_font", UIStyle.UI_BOLD)
	_text.add_theme_color_override("default_color", BookKit.PRINT)
	_text.add_theme_constant_override("line_separation", 4)
	_text.position = Vector2(PAPER_PAD_X, PAPER_PAD_Y)
	_paper.add_child(_text)

	_listen = BookKit.round_button(KidIcon.Kind.SPEAKER, BookKit.SKY, 80.0)
	_listen.name = "Listen"
	_listen.focus_mode = Control.FOCUS_NONE
	_listen.pressed.connect(_on_listen)
	add_child(_listen)

	_back = BookKit.round_button(KidIcon.Kind.BACK, BookKit.PLUM, BACK_D)
	_back.name = "Back"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(prev_page)
	add_child(_back)

	_next = BookKit.round_button(KidIcon.Kind.NEXT, BookKit.SUN, NEXT_D, UIStyle.TEXT_PRIMARY)
	_next.name = "Next"
	_next.focus_mode = Control.FOCUS_NONE
	_next.pressed.connect(next_page)
	add_child(_next)

	_skip = BookKit.button(Loc.t("skip"), KidIcon.Kind.SKIP, BookKit.CHERRY, Vector2(200, 84))
	_skip.name = "Skip"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(skip)
	add_child(_skip)

	_dots = HBoxContainer.new()
	_dots.name = "Dots"
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.add_theme_constant_override("separation", 12)
	add_child(_dots)

	_narrator = Narrator.new()
	_narrator.name = "Narrator"
	add_child(_narrator)
	_narrator.word_changed.connect(_on_word)
	_narrator.finished.connect(_on_narration_done)


# --- Public ----------------------------------------------------------------------

func open(chapter: String, which_part: String, start_index: int = 0) -> void:
	chapter_id = chapter
	part = which_part
	var ch := StoryData.chapter(chapter)
	pages = ch.get(which_part, [])
	index = clampi(start_index, 0, maxi(0, pages.size() - 1))
	_open = true
	visible = true
	modulate.a = 1.0
	_rebuild_dots()
	_relayout()
	if pages.is_empty():
		_finish(false)
		return
	_show_page(0)


func close() -> void:
	_open = false
	_narrator.stop()
	visible = false


func page_count() -> int:
	return pages.size()


func current_page() -> Dictionary:
	return pages[index] if index >= 0 and index < pages.size() else {}


func current_text() -> String:
	return _plain


func is_open() -> bool:
	return _open


func narrator() -> Narrator:
	return _narrator


func next_page() -> void:
	if not _open or _grace > 0.0:
		return
	if index >= pages.size() - 1:
		_finish(false)
		return
	index += 1
	_show_page(1)


func prev_page() -> void:
	if not _open or _grace > 0.0:
		return
	if index <= 0:
		back_requested.emit()
		return
	index -= 1
	_show_page(-1)


func skip() -> void:
	if not _open:
		return
	_finish(true)


func _finish(skipped: bool) -> void:
	_narrator.stop()
	_open = false
	finished.emit(skipped)


# --- Pages -------------------------------------------------------------------------

## dir: 0 first page (no turn), 1 forward, -1 back.
func _show_page(dir: int) -> void:
	_narrator.stop()
	_grace = INPUT_GRACE
	_idle = 0.0
	var pg := current_page()
	_plain = Loc.pick(pg)

	var old := _art
	_art = PageArt.new()
	_art.name = "Page_%s" % str(pg.get("id", index))
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_host.add_child(_art)
	_art.setup(chapter_id, pg, part, _plain)
	if dir != 0:
		BookKit.sfx(&"page_turn")
	_turn(old, _art, dir)

	_word = -1
	_render_text()
	_update_chrome()
	_relayout()
	page_changed.emit(index)
	_narrate()


func _turn(old: PageArt, incoming: PageArt, dir: int) -> void:
	if old == null:
		return
	var w := maxf(size.x, 1.0)
	if dir == 0 or BookKit.reduce_motion():
		incoming.modulate.a = 0.0
		var f := create_tween()
		f.tween_property(incoming, "modulate:a", 1.0, 0.25)
		f.tween_callback(old.queue_free)
		return
	# The old page lifts and slides off like a turned leaf; the new one slides
	# in under it from the other side.
	old.pivot_offset = Vector2(w * 0.5 if dir > 0 else w * 0.5, size.y)
	incoming.position.x = w * 0.30 * dir
	incoming.modulate.a = 0.0
	_art_host.move_child(old, -1)
	var t := create_tween().set_parallel(true)
	t.tween_property(old, "position:x", -w * 1.05 * dir, TURN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(old, "rotation_degrees", -7.0 * dir, TURN_TIME)
	t.tween_property(old, "modulate", Color(0.75, 0.7, 0.7, 0.0), TURN_TIME)
	t.tween_property(incoming, "position:x", 0.0, TURN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(incoming, "modulate:a", 1.0, TURN_TIME * 0.6)
	t.chain().tween_callback(old.queue_free)


func _narrate() -> void:
	var pg := current_page()
	if GameManager.narration:
		_narrator.speak(_plain, Loc.lang(), str(pg.get("id", "")), true)


func _on_listen() -> void:
	var pg := current_page()
	_narrator.speak(_plain, Loc.lang(), str(pg.get("id", "")), true)


func _on_word(i: int) -> void:
	_word = i
	_render_text()


func _on_narration_done() -> void:
	_word = -1
	_render_text()


## The page text as BBCode, with the word being spoken lit.
func _render_text() -> void:
	var px := _text_px()
	_text.add_theme_font_size_override("normal_font_size", px)
	_text.add_theme_font_size_override("bold_font_size", px)
	if _word < 0 or not _narrator.is_speaking():
		_text.text = "[center]%s[/center]" % _plain.replace("[", "[lb]")
		return
	var starts := _narrator.word_starts
	var words := _narrator.words
	var out := ""
	var cursor := 0
	for i in words.size():
		var s := starts[i]
		out += _plain.substr(cursor, s - cursor).replace("[", "[lb]")
		var w := words[i].replace("[", "[lb]")
		if i == _word:
			out += "[bgcolor=#%s][color=#%s]%s[/color][/bgcolor]" % [
				BookKit.HIGHLIGHT.to_html(false), BookKit.PRINT.to_html(false), w]
		elif i < _word:
			out += "[color=#%s]%s[/color]" % [BookKit.PRINT_SOFT.to_html(false), w]
		else:
			out += w
		cursor = s + words[i].length()
	out += _plain.substr(cursor)
	_text.text = "[center]%s[/center]" % out


## Long pages step the size down so the paper never covers the picture.
func _text_px() -> int:
	var chars := _plain.length()
	var width := maxf(400.0, _paper_width() - 44.0)
	var px := TEXT_PX
	while px > TEXT_PX_MIN:
		var per_line := width / (px * 0.52)
		var lines := ceilf(chars / per_line)
		if lines * px * 1.32 <= 210.0:
			break
		px -= 2
	return px


func _paper_width() -> float:
	return clampf(size.x - SIDE * 2.0, 520.0, 1180.0)


func _rebuild_dots() -> void:
	for c in _dots.get_children():
		_dots.remove_child(c)
		c.queue_free()
	for i in pages.size():
		var chip := UIStyle.chip(UIStyle.HAIRLINE_STRONG, 18.0)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_dots.add_child(chip)


func _update_chrome() -> void:
	for i in _dots.get_child_count():
		var chip := _dots.get_child(i) as Panel
		var sb := chip.get_theme_stylebox("panel") as StyleBoxFlat
		var on := i == index
		chip.custom_minimum_size = Vector2(26, 26) if on else Vector2(18, 18)
		if sb:
			sb.bg_color = BookKit.SUN if on else (Color(1, 1, 1, 0.85) if i < index
				else Color(1, 1, 1, 0.35))
			sb.set_corner_radius_all(13 if on else 9)
	var last := index >= pages.size() - 1
	var icon := _next.get_meta("icon") as KidIcon
	if icon:
		icon.set_kind(KidIcon.Kind.PLAY if last and part == "intro"
			else (KidIcon.Kind.CHECK if last else KidIcon.Kind.NEXT))
	_back.visible = index > 0 or part == "intro"
	BookKit.set_caption(_skip, Loc.t("skip"))
	_skip.visible = not last
	_relayout()


func _relayout() -> void:
	if size.x <= 1.0:
		return
	var m := 24.0
	var pw := _paper_width()
	_text.size = Vector2(pw - PAPER_PAD_X * 2.0, 0)
	_text.custom_minimum_size = Vector2(pw - PAPER_PAD_X * 2.0, 0)
	var th := maxf(_text.get_content_height(), float(_text_px()) * 1.3)
	var ph := maxf(th + PAPER_PAD_Y * 2.0 + 4.0, 124.0)
	_paper.size = Vector2(pw, ph)
	_paper.position = Vector2((size.x - pw) * 0.5, size.y - m - ph)
	_listen.position = _paper.position + Vector2(-30, -46)
	_next.position = Vector2(size.x - m - NEXT_D, size.y - m - NEXT_D)
	_back.position = Vector2(m, size.y - m - BACK_D)
	_skip.reset_size()
	_skip.position = Vector2(size.x - m - _skip.size.x, m)
	_dots.reset_size()
	_dots.position = Vector2((size.x - _dots.size.x) * 0.5, m + 30)


func _process(delta: float) -> void:
	if not _open:
		return
	_grace = maxf(0.0, _grace - delta)
	_idle += delta
	# Once the page has been read (or after a while), the Next button breathes
	# to say "tap me", the gentle half of the idle hint ladder.
	var invite := (not _narrator.is_speaking() and _idle > 1.0) or _idle > 14.0
	if invite and not BookKit.reduce_motion():
		var k := 1.0 + 0.06 * sin(_idle * 4.0)
		_next.pivot_offset = _next.size * 0.5
		_next.scale = Vector2(k, k)
	elif _next.scale != Vector2.ONE and not _next.is_hovered():
		_next.scale = Vector2.ONE


func _on_settings_changed() -> void:
	if not _open:
		return
	var was := _narrator.is_speaking()
	_plain = Loc.pick(current_page())
	_narrator.stop()
	_word = -1
	_render_text()
	_update_chrome()
	if was or GameManager.narration:
		_narrate()


# --- Input --------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		next_page()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not is_visible_in_tree():
		return
	if event.is_echo():
		return
	var pressed: bool = (event is InputEventKey and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if not pressed:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_cancel"):
		prev_page()
	elif event is InputEventJoypadButton and event.is_action_pressed("ui_pause"):
		skip()
	else:
		next_page()
	get_viewport().set_input_as_handled()
