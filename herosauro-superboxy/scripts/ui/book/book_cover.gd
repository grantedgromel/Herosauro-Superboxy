class_name BookCover
extends Button
## One chapter as a picture book standing on the shelf: a hard cover in the
## chapter's colour with a spine and page edges, the cover picture, the
## chapter number, the title, the heroes' faces, and, once the story has been
## played to the end, a star sticker slapped on the corner.
##
## The cover picture is the chapter's `cover` file when it exists (chapter 1's
## is the key art); otherwise the chapter's own composed scene (PageScene).
##
## A Button, so keyboard, pad, mouse and touch all reach it the same way; it
## draws itself rather than using a stylebox.

const SPINE := 26.0
const PAGES := 12.0

var chapter_id: String = ""
var accent: Color = Color("33a056")
## The next story to read: it glows and breathes on the shelf.
var suggested := false

var _face: Control
var _window: Control
var _title: Label
var _number: Label
var _badge: Panel
var _sticker: Control
var _new_tag: PanelContainer
var _clock := 0.0
var _hover := false


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	clip_contents = false
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


func setup(id: String) -> void:
	chapter_id = id
	var ch := StoryData.chapter(id)
	accent = ch.get("accent", accent)
	name = "Cover_" + id
	_build(ch)
	refresh()
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	focus_entered.connect(func() -> void: _set_hover(true))
	focus_exited.connect(func() -> void: _set_hover(false))
	pressed.connect(func() -> void: BookKit.sfx(&"ui_tap"))
	resized.connect(_layout)


func _build(ch: Dictionary) -> void:
	_face = Control.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)

	_window = Control.new()
	_window.name = "Picture"
	_window.clip_contents = true
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_child(_window)
	var cover_path := str(ch.get("cover", ""))
	if not cover_path.is_empty() and ResourceLoader.exists(cover_path):
		var tr := TextureRect.new()
		tr.name = "CoverArt"
		tr.texture = load(cover_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window.add_child(tr)
	else:
		var scene := PageScene.new()
		scene.name = "ComposedCover"
		var props := ["cups", "sparkles"] if chapter_id == "dragao" else \
			(["pandas", "sparkles"] if chapter_id == "pandas" else ["sparkles"])
		scene.configure(chapter_id, "outro", props, 77)
		_window.add_child(scene)
		_window.set_meta("scene", scene)
		# The heroes' faces along the bottom of the picture.
		for i in 2:
			var head := TextureRect.new()
			head.name = "Head%d" % i
			head.texture = UIStyle.portrait_head(UIStyle.Actor.HEROSAURO if i == 0
				else UIStyle.Actor.SUPERBOXY, 256)
			head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			head.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			head.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_window.add_child(head)

	_title = BookKit.loud_label("", 34, UIStyle.TEXT_PRIMARY)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_face.add_child(_title)

	_badge = UIStyle.chip(BookKit.SUN, 58.0)
	_badge.name = "Number"
	_face.add_child(_badge)
	_number = UIStyle.title(str(int(ch.get("number", 1))), 40, BookKit.PRINT)
	_number.add_theme_constant_override("outline_size", 0)
	_number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_badge.add_child(_number)

	_sticker = _StarSticker.new()
	_sticker.name = "Sticker"
	_sticker.visible = false
	add_child(_sticker)

	_new_tag = UIStyle.pill("", BookKit.CHERRY, UIStyle.TEXT_PRIMARY, 22)
	_new_tag.name = "NewTag"
	_new_tag.visible = false
	add_child(_new_tag)


## Re-read progress and language.
func refresh() -> void:
	var ch := StoryData.chapter(chapter_id)
	_title.text = Loc.pick(ch.get("title", {}))
	var done := UIProgress.is_complete(chapter_id)
	_sticker.visible = done
	(_new_tag.get_child(0) as Label).text = Loc.t("new_story")
	_new_tag.visible = suggested and not done
	tooltip_text = ""
	_layout()


func is_complete() -> bool:
	return UIProgress.is_complete(chapter_id)


func has_sticker() -> bool:
	return _sticker.visible


func set_suggested(on: bool) -> void:
	suggested = on
	refresh()
	queue_redraw()


## The sticker lands: a slap, a wobble and a sparkle sound.
func play_sticker() -> void:
	_sticker.visible = true
	if BookKit.reduce_motion():
		return
	_sticker.scale = Vector2(2.4, 2.4)
	_sticker.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(_sticker, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT).set_delay(0.35)
	t.tween_property(_sticker, "modulate:a", 1.0, 0.2).set_delay(0.35)
	t.chain().tween_callback(func() -> void: BookKit.sfx(&"star"))


func _set_hover(on: bool) -> void:
	_hover = on
	pivot_offset = size * 0.5
	if not is_inside_tree():
		return
	var t := create_tween()
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE * (1.07 if on else 1.0), 0.18)
	queue_redraw()


func _layout() -> void:
	if _face == null or size.x <= 1.0:
		return
	var face := Rect2(SPINE, 0, size.x - SPINE - PAGES, size.y - PAGES)
	_face.position = face.position
	_face.size = face.size
	var pad := 16.0
	var title_h := clampf(face.size.y * 0.24, 70.0, 110.0)
	_window.position = Vector2(pad, pad)
	_window.size = Vector2(face.size.x - pad * 2.0, face.size.y - pad * 2.5 - title_h)
	var scene := (_window.get_meta("scene") if _window.has_meta("scene") else null) as PageScene
	if scene != null:
		# Crop the 16:9 scene to the cover's portrait window, a touch right of
		# centre where the props are.
		var k := maxf(_window.size.x / PageScene.DESIGN.x, _window.size.y / PageScene.DESIGN.y)
		scene.scale = Vector2(k, k)
		scene.position = Vector2((_window.size.x - PageScene.DESIGN.x * k) * 0.5 - 60.0 * k,
			(_window.size.y - PageScene.DESIGN.y * k) * 0.5)
		var hs := _window.size.x * 0.44
		for i in 2:
			var head := _window.get_node("Head%d" % i) as TextureRect
			head.size = Vector2(hs, hs)
			head.position = Vector2(_window.size.x * (0.06 + i * 0.46), _window.size.y - hs * 0.92)
	BookKit.place(_title, Vector2(pad, face.size.y - pad - title_h),
		Vector2(face.size.x - pad * 2.0, title_h))
	_title.add_theme_font_size_override("font_size", int(clampf(face.size.x * 0.13, 26.0, 40.0)))
	_badge.position = Vector2(pad - 22, pad - 22)
	_sticker.size = Vector2(96, 96)
	_sticker.pivot_offset = _sticker.size * 0.5
	_sticker.position = Vector2(size.x - 84, -24)
	_new_tag.reset_size()
	_new_tag.position = Vector2(size.x - _new_tag.size.x - 4, -18)
	queue_redraw()


func _process(delta: float) -> void:
	if not suggested or BookKit.reduce_motion():
		return
	_clock += delta
	# A slow breath, so the eye goes to the next story without being told.
	var lift := sin(_clock * 2.2) * 5.0
	_face.position.y = lift
	queue_redraw()


func _draw() -> void:
	var lift := _face.position.y if _face != null else 0.0
	var body := Rect2(0, lift, size.x - PAGES, size.y - PAGES)
	var ink := Color(0.10, 0.07, 0.10, 0.95)
	# Glow behind the suggested book and the focused one.
	if suggested or has_focus() or _hover:
		var glow := Color(1.0, 0.86, 0.3, 0.55 if (has_focus() or _hover) else 0.35)
		for i in 4:
			var g := Rect2(body.position - Vector2(10 + i * 7, 10 + i * 7),
				body.size + Vector2(PAGES + 20 + i * 14, PAGES + 20 + i * 14))
			_round_rect(g, 30.0 + i * 7, Color(glow, glow.a * (1.0 - i * 0.24)))
	# Shadow on the shelf.
	_round_rect(Rect2(body.position + Vector2(8, 14), body.size + Vector2(PAGES, 0)), 18,
		Color(0.2, 0.08, 0.02, 0.35))
	# The page block, peeking out on the right and bottom.
	var pages := Rect2(body.position + Vector2(SPINE, PAGES), body.size - Vector2(SPINE - PAGES, 0))
	_round_rect(pages.grow(3), 14, ink)
	_round_rect(pages, 12, BookKit.PAPER)
	for i in 4:
		var x := pages.end.x - 3 - i * 3
		draw_line(Vector2(x, pages.position.y + 16), Vector2(x, pages.end.y - 8),
			BookKit.PAPER_EDGE, 1.5)
	# Hard cover with spine.
	_round_rect(body.grow(4), 20, ink)
	_round_rect(body, 18, accent)
	_round_rect(Rect2(body.position, Vector2(SPINE + 8, body.size.y)), 18, accent.darkened(0.30))
	for k in 3:
		var y := body.position.y + body.size.y * (0.18 + k * 0.32)
		draw_line(Vector2(body.position.x + 4, y), Vector2(body.position.x + SPINE, y),
			accent.lightened(0.25), 4.0, true)
	draw_line(Vector2(body.position.x + SPINE + 8, body.position.y + 6),
		Vector2(body.position.x + SPINE + 8, body.end.y - 6), Color(0, 0, 0, 0.25), 3.0)
	# Inner frame round the picture.
	if _window != null:
		var win := Rect2(_face.position + _window.position, _window.size).grow(6)
		_round_rect(win, 14, ink)
		_round_rect(Rect2(win.position + Vector2(3, 3), win.size - Vector2(6, 6)), 12,
			accent.lightened(0.35))
	# The gloss of a laminated cover.
	draw_rect(Rect2(body.position + Vector2(SPINE + 14, 6), Vector2(body.size.x * 0.18,
		body.size.y - 12)), Color(1, 1, 1, 0.07))
	if has_focus():
		var ring := body.grow(9)
		_round_rect_outline(ring, 26, Color("ffd84d"), 6.0)


func _round_rect(r: Rect2, radius: float, c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 10
	draw_style_box(sb, r)


func _round_rect_outline(r: Rect2, radius: float, c: Color, w: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(int(w))
	sb.border_color = c
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 10
	draw_style_box(sb, r)


## A shiny star sticker with a white die-cut border, slapped on at an angle.
class _StarSticker extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		rotation_degrees = 14.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_colored_polygon(_star(c + Vector2(3, 5), r, r * 0.5), Color(0, 0, 0, 0.30))
		draw_colored_polygon(_star(c, r, r * 0.5), Color.WHITE)
		draw_colored_polygon(_star(c, r * 0.82, r * 0.40), Color("ffc12b"))
		var hl := _star(c + Vector2(-r * 0.08, -r * 0.1), r * 0.5, r * 0.22)
		draw_colored_polygon(hl, Color(1.0, 0.95, 0.6, 0.85))
		var line := _star(c, r, r * 0.5)
		line.append(line[0])
		draw_polyline(line, Color(0.10, 0.07, 0.10, 0.5), 2.5, true)

	func _star(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + i * PI / 5.0
			var rr := outer if i % 2 == 0 else inner
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		return pts
