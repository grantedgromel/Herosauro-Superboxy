class_name Bookshelf
extends Control
## The Estante: the book's chapters as picture books standing on a shelf.
## Pick one to read and play it. Finished stories wear a star sticker; the
## next unfinished one breathes gently so the eye goes there first. Nothing is
## locked: a child (or a parent) can open any story at any time.
##
## Keyboard, pad, mouse and touch all work: the covers are Buttons, and focus
## moves between them with the arrows / d-pad. The gear opens Settings.

signal chapter_chosen(chapter_id: String)
signal settings_requested()

var covers: Array[BookCover] = []
## The book to focus the next time the shelf comes on screen, instead of the
## suggested one. Set when a book is opened, so backing out of "who's playing"
## lands on the book the child picked; cleared when a run starts (coming back
## from a story, the next unfinished book is the one to offer).
var return_focus: String = ""

var _wall: PaperWall
var _title: Label
var _prompt: Label
var _gear: Button
var _row: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_wall = PaperWall.new()
	_wall.name = "Wall"
	add_child(_wall)

	_title = BookKit.loud_label(Loc.t("shelf_title"), 66, BookKit.SUN)
	_title.name = "Title"
	add_child(_title)
	_prompt = BookKit.print_label(Loc.t("shelf_prompt"), 30, true, BookKit.PRINT)
	_prompt.name = "Prompt"
	add_child(_prompt)

	_row = Control.new()
	_row.name = "Books"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for id: String in StoryData.ORDER:
		var cover := BookCover.new()
		_row.add_child(cover)
		cover.setup(id)
		cover.pressed.connect(func() -> void:
			return_focus = id
			chapter_chosen.emit(id))
		covers.append(cover)

	_gear = BookKit.round_button(KidIcon.Kind.GEAR, BookKit.SKY, 96.0)
	_gear.name = "Gear"
	_gear.pressed.connect(func() -> void: settings_requested.emit())
	add_child(_gear)

	resized.connect(_layout)
	GameManager.settings_changed.connect(refresh)
	refresh()


## Re-read progress and language; highlight the next unfinished story.
func refresh() -> void:
	_title.text = Loc.t("shelf_title")
	_prompt.text = Loc.t("shelf_prompt")
	var next := UIProgress.next_unfinished()
	for c in covers:
		c.set_suggested(c.chapter_id == next)
	_layout()


func suggested_chapter() -> String:
	var next := UIProgress.next_unfinished()
	return next if not next.is_empty() else str(StoryData.ORDER[0])


func cover_for(id: String) -> BookCover:
	for c in covers:
		if c.chapter_id == id:
			return c
	return null


## Called when the shelf comes on screen.
func enter() -> void:
	refresh()
	var fresh := UIProgress.fresh_sticker
	if not fresh.is_empty():
		var c := cover_for(fresh)
		if c != null:
			c.play_sticker()
		UIProgress.fresh_sticker = ""
	var focus := cover_for(return_focus) if not return_focus.is_empty() else null
	if focus == null:
		focus = cover_for(suggested_chapter())
	if focus != null:
		focus.call_deferred("grab_focus")


func _layout() -> void:
	if size.x <= 1.0 or covers.is_empty():
		return
	var m := 28.0
	_title.reset_size()
	_title.position = Vector2((size.x - _title.size.x) * 0.5, m + 4)
	_prompt.reset_size()
	_prompt.position = Vector2((size.x - _prompt.size.x) * 0.5, _title.position.y + _title.size.y - 2)
	_gear.position = Vector2(size.x - m - _gear.size.x, m)

	var top := _prompt.position.y + _prompt.size.y + 34.0
	var avail_h := size.y - top - 110.0
	var h := clampf(avail_h, 300.0, 520.0)
	var w := h * 0.74
	var gap := w * 0.20
	var total := w * covers.size() + gap * (covers.size() - 1)
	if total > size.x - 2.0 * m - 40.0:
		var k := (size.x - 2.0 * m - 40.0) / total
		w *= k
		h *= k
		gap *= k
		total *= k
	var x0 := (size.x - total) * 0.5
	var y0 := top + (avail_h - h) * 0.5
	for i in covers.size():
		var c := covers[i]
		c.position = Vector2(x0 + i * (w + gap), y0)
		c.size = Vector2(w, h)
		c.custom_minimum_size = Vector2(w, h)
	_wall.set_shelf((y0 + h - BookCover.PAGES + 2.0) / size.y)
