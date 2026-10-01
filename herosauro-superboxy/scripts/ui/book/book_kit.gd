class_name BookKit
extends RefCounted
## The storybook frame's half of the design system: picture-book paper, big
## icon-first buttons and the type treatments for pages and covers. Built on
## UIStyle (same fonts, same ink keyline, same moulded-plastic buttons), but
## warmer: the frame around the game is a book on a shelf, not a console menu.
##
## Sizes are the kid rules (docs/story/ADAPTATION.md): every target is at least
## TARGET_MIN px tall at 720p, text that has to be read is 28 px or more.

const TARGET_MIN := 84.0
const ROUND_BUTTON := 96.0

# --- Palette ----------------------------------------------------------------

const PAPER := Color("fff6e4")
const PAPER_SHADE := Color("f3e2c2")
const PAPER_EDGE := Color("d8bd8c")
## Body text on paper: a warm brown-black, the colour of printed picture-book
## ink, 14:1 on PAPER.
const PRINT := Color("2b1d12")
const PRINT_SOFT := Color("6b5340")
const INK := UIStyle.KEYLINE
const SUN := UIStyle.GOLD
const LEAF := UIStyle.HERO_GREEN
const CHERRY := UIStyle.BOXY_RED
const SKY := Color("3fa9f5")
const PLUM := Color("8e5bd8")
## The read-along highlight behind the word being spoken.
const HIGHLIGHT := Color("ffd84d")


# --- Type -------------------------------------------------------------------

## Text printed on paper: Fredoka, dark print colour, no outline (an outline
## on cream only thickens the letters and closes the counters).
static func print_label(body: String, px: int, bold: bool = false,
		color: Color = PRINT, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = body
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UIStyle.UI_BOLD if bold else UIStyle.UI_FONT)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	return l


## Loud display type (Bangers) with the kit's ink keyline, for titles that sit
## over art.
static func loud_label(body: String, px: int, color: Color = SUN) -> Label:
	return UIStyle.title(body, px, color)


# --- Surfaces -----------------------------------------------------------------

## A sheet of paper: cream, ink keyline, soft drop shadow.
static func paper_box(radius: int = 28, pad: int = 24, fill: Color = PAPER,
		border: int = 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 16
	sb.set_border_width_all(border)
	sb.border_color = INK
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.shadow_color = Color(0.05, 0.03, 0.01, 0.45)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 8)
	return sb


static func paper_panel(radius: int = 28, pad: int = 24) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", paper_box(radius, pad))
	return p


# --- Buttons --------------------------------------------------------------------

static func _box(fill: Color, lift: float, radius: int, focus: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 16
	sb.set_border_width_all(5)
	sb.border_color = INK
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if focus:
		# The focus ring is a fat gold rim outside the keyline: unmistakable
		# for a child steering with a pad. It is an overlay (Godot draws the
		# focus box over the normal one), so it has no fill of its own.
		sb.draw_center = false
		sb.set_border_width_all(7)
		sb.border_color = Color("ffd84d")
		sb.set_corner_radius_all(radius + 8)
		sb.expand_margin_left = 9
		sb.expand_margin_right = 9
		sb.expand_margin_top = 9
		sb.expand_margin_bottom = 9
	else:
		sb.shadow_color = Color(0.02, 0.02, 0.04, 0.55)
		sb.shadow_size = int(lift * 2.0)
		sb.shadow_offset = Vector2(0, lift)
	return sb


static func style_button(b: Button, fill: Color, radius: int) -> void:
	b.add_theme_stylebox_override("normal", _box(fill, 5.0, radius, false))
	b.add_theme_stylebox_override("hover", _box(fill.lightened(0.12), 8.0, radius, false))
	b.add_theme_stylebox_override("pressed", _box(fill.darkened(0.15), 1.0, radius, false))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), 0.0, radius, true))
	b.add_theme_stylebox_override("disabled", _box(fill.darkened(0.4), 0.0, radius, false))
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pop_on_hover(b)


## Recolour a styled button in place (a toggle's selected state), keeping its
## signals and its radius.
static func style_button_fill(b: Button, fill: Color) -> void:
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	var radius := sb.corner_radius_top_left if sb != null else 26
	b.add_theme_stylebox_override("normal", _box(fill, 5.0, radius, false))
	b.add_theme_stylebox_override("hover", _box(fill.lightened(0.12), 8.0, radius, false))
	b.add_theme_stylebox_override("pressed", _box(fill.darkened(0.15), 1.0, radius, false))


## A big rounded button: icon on the left, word on the right. The word is
## support; the icon is what a pre-reader finds. `min_size` grows to fit the
## caption, never shrinks below TARGET_MIN tall.
static func button(caption: String, icon: int, fill: Color = SUN,
		min_size: Vector2 = Vector2(260, TARGET_MIN), text_color: Color = UIStyle.TEXT_PRIMARY,
		icon_color: Color = UIStyle.TEXT_PRIMARY) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(min_size.x, maxf(min_size.y, TARGET_MIN))
	b.clip_contents = false
	style_button(b, fill, 26)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -18
	b.add_child(row)

	var ic_px := clampf(b.custom_minimum_size.y * 0.56, 40.0, 64.0)
	if icon >= 0:
		var ic := KidIcon.make(icon, ic_px, icon_color)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := UIStyle.label(caption, 30, text_color, true, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_constant_override("outline_size", 7)
	row.add_child(l)
	b.set_meta("caption", l)
	b.set_meta("min_w", min_size.x)
	b.set_meta("icon_px", ic_px if icon >= 0 else 0.0)
	_fit(b)
	return b


## A round icon-only button (next page, back, settings, pause).
static func round_button(icon: int, fill: Color = SUN, diameter: float = ROUND_BUTTON,
		icon_color: Color = UIStyle.TEXT_PRIMARY) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.size = b.custom_minimum_size
	style_button(b, fill, int(diameter * 0.5))
	var ic := KidIcon.make(icon, diameter * 0.56, icon_color)
	ic.set_anchors_preset(Control.PRESET_CENTER)
	ic.offset_left = -diameter * 0.28
	ic.offset_top = -diameter * 0.28
	ic.offset_right = diameter * 0.28
	ic.offset_bottom = diameter * 0.28
	b.add_child(ic)
	b.set_meta("icon", ic)
	return b


## Change a button()'s word (on a language switch) and regrow it to fit.
static func set_caption(b: Button, caption: String) -> void:
	var l := (b.get_meta("caption") if b.has_meta("caption") else null) as Label
	if l == null:
		return
	l.text = caption
	_fit(b)


static func caption_of(b: Button) -> String:
	var l := (b.get_meta("caption") if b.has_meta("caption") else null) as Label
	return l.text if l != null else b.text


static func _fit(b: Button) -> void:
	var l := (b.get_meta("caption") if b.has_meta("caption") else null) as Label
	if l == null:
		return
	var w := l.get_minimum_size().x + float(b.get_meta("icon_px", 0.0)) + 14.0 + 36.0 + 16.0
	b.custom_minimum_size.x = maxf(float(b.get_meta("min_w", 0.0)), w)


static func _pop_on_hover(b: Button) -> void:
	var to := func(target: float) -> void:
		if not b.is_inside_tree():
			return
		b.pivot_offset = b.size * 0.5
		var t := b.create_tween()
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2(target, target), 0.16)
	b.mouse_entered.connect(func() -> void: to.call(1.06))
	b.mouse_exited.connect(func() -> void: to.call(1.0))
	b.focus_entered.connect(func() -> void: to.call(1.06))
	b.focus_exited.connect(func() -> void: to.call(1.0))
	# Every press says so out loud. A soft tap, never a buzzer.
	b.pressed.connect(func() -> void: BookKit.sfx(&"ui_tap"))


## Put a (possibly word-wrapped) label at `pos` in a box of `box`. The width
## goes in as a minimum first: a wrapped label sized before it knows its
## width measures itself one character per line, grows hundreds of pixels
## tall and then draws its vertically-centred text far below the box.
static func place(l: Control, pos: Vector2, box: Vector2) -> void:
	l.custom_minimum_size = Vector2(box.x, 0)
	l.position = pos
	# The first call sets the width, but the minimum height it clamps against
	# was shaped at the old width. Asking for the line count reshapes the text
	# at the new width, and the second call then clamps against the height the
	# text really needs.
	l.size = box
	if l is Label:
		(l as Label).get_line_count()
	l.size = box


# --- Small helpers ----------------------------------------------------------------

## AudioManager.play_sfx, guarded so a widget built outside the game (a
## --script tool) does not crash on a missing autoload.
static func sfx(id: StringName) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var am := tree.root.get_node_or_null("AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx(id)


static func reduce_motion() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var gm := tree.root.get_node_or_null("GameManager")
	return gm != null and bool(gm.get("reduce_motion"))


## The cast present in a stretch of story text, in reading order of
## importance. Used for the composed page art, the cover portraits and the
## story-beat toasts. Keyword-driven on both languages, because StoryData has
## no cast field and the reader must work for pages it has never seen.
static func cast_in(text: String) -> Array[String]:
	var lower := text.to_lower()
	var out: Array[String] = []
	if _has_word(lower, "adamastor|gigante|giant"):
		out.append("adamastor")
	if _has_word(lower, "rui|herosauro|t-rex"):
		out.append("herosauro")
	if _has_word(lower, "kiko|boxy"):
		out.append("superboxy")
	if _has_word(lower, "irmãos|brothers|heróis|heroes|super-heróis|superheroes"):
		for who in ["herosauro", "superboxy"]:
			if not out.has(who):
				out.append(who)
	return out


static var _word_res: Dictionary = {}


## Whole-word match, so "destruir" never summons Rui.
static func _has_word(lower: String, alternatives: String) -> bool:
	var re: RegEx = _word_res.get(alternatives)
	if re == null:
		re = RegEx.new()
		re.compile("(?<![\\p{L}])(" + alternatives + ")(?![\\p{L}])")
		_word_res[alternatives] = re
	return re.search(lower) != null


static func actor_of(who: String) -> int:
	match who:
		"superboxy":
			return UIStyle.Actor.SUPERBOXY
		"adamastor":
			return UIStyle.Actor.ADAMASTOR
		_:
			return UIStyle.Actor.HEROSAURO
