class_name UIStyle
extends RefCounted
## Shared visual language for menus + HUD: fonts, a cohesive palette, and styled
## widget builders so every screen reads like one polished, professional game.

const TITLE_FONT: Font = preload("res://assets/fonts/Bangers.woff2")
const UI_FONT: Font = preload("res://assets/fonts/Fredoka.woff2")
const UI_BOLD: Font = preload("res://assets/fonts/Fredoka-Bold.woff2")

# --- Palette: warm Porto golden-hour over a deep, slightly purple ink ---
const INK := Color("191522")
const CREAM := Color("fbf1df")
const MUTED := Color("b6aac4")
const GOLD := Color("ffc64d")
const GOLD_DEEP := Color("ef8f2c")
const P1 := Color("57c25c")           # Herosauro green
const P2 := Color("ef5a52")           # Super Boxy red
const BOSS := Color("d98a3a")         # Adamastor amber
const BOSS_RED := Color("e0392f")
const VICTORY := Color("7ad06b")
const DEFEAT := Color("ef6157")
const SHADOW := Color(0, 0, 0, 0.8)
const PANEL_BG := Color(0.055, 0.045, 0.085, 0.84)


static func title(text: String, size: int, color: Color = GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", TITLE_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", SHADOW)
	l.add_theme_constant_override("outline_size", maxi(6, int(size / 9.0)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func label(text: String, size: int, color: Color = CREAM, bold: bool = false,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UI_BOLD if bold else UI_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", SHADOW)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func bar(fill: Color, max_val: float = 100.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = max_val
	pb.value = max_val
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.025, 0.05, 0.92)
	bg.set_corner_radius_all(8)
	bg.set_border_width_all(2)
	bg.border_color = Color(1, 1, 1, 0.12)
	bg.content_margin_left = 2.0
	bg.content_margin_right = 2.0
	bg.content_margin_top = 2.0
	bg.content_margin_bottom = 2.0
	var fl := StyleBoxFlat.new()
	fl.bg_color = fill
	fl.set_corner_radius_all(6)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fl)
	return pb


static func panel(color: Color = PANEL_BG, radius: int = 16, margin: int = 20) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


static func _btn_box(c: Color, border: Color, lift: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(13)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = int(lift)
	sb.shadow_offset = Vector2(0, lift)
	return sb


static func button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", UI_BOLD)
	b.add_theme_font_size_override("font_size", 27)
	var fg := INK if primary else CREAM
	var base := GOLD if primary else Color(0.16, 0.14, 0.21, 0.96)
	var hover := GOLD.lightened(0.08) if primary else Color(0.22, 0.19, 0.28, 0.98)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_stylebox_override("normal", _btn_box(base, Color(0, 0, 0, 0.25), 4))
	b.add_theme_stylebox_override("hover", _btn_box(hover, GOLD if not primary else Color(1, 1, 1, 0.4), 6))
	b.add_theme_stylebox_override("pressed", _btn_box(base.darkened(0.12), Color(0, 0, 0, 0.3), 1))
	b.add_theme_stylebox_override("focus", _btn_box(hover, GOLD, 5))
	return b


## A small rounded colour chip — clean stand-in for emoji on HUD labels.
static func chip(color: Color, size: float = 14.0) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(size / 3.0))
	p.add_theme_stylebox_override("panel", sb)
	return p
