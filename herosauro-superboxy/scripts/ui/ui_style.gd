class_name UIStyle
extends RefCounted
## The game's design system: one type scale, one palette, one elevation model and
## the widget factories every screen is assembled from.
##
## Everything here is static — no instancing, no scene tree. Screens call the
## factories and get controls that already carry the right font, tracking,
## outline, colour and depth, so no call site has to invent a font size again.
##
## Two rules the whole system rests on:
##   * Bangers (the comic face) is DISPLAY ONLY. It has no numerals worth reading
##     and no lowercase rhythm, so it never touches body copy, stats or timers.
##   * Every piece of text carries BOTH a dark outline and a soft drop shadow,
##     because the UI now sits over a live golden-hour sky that is brighter than
##     any of our text colours.

# --- Fonts -------------------------------------------------------------------

const TITLE_FONT: Font = preload("res://assets/fonts/Bangers.woff2")
const UI_FONT: Font = preload("res://assets/fonts/Fredoka.woff2")
const UI_BOLD: Font = preload("res://assets/fonts/Fredoka-Bold.woff2")


# --- Type scale --------------------------------------------------------------
#
# Nine deliberate steps. Call sites name a step; they never pick a number.
#   DISPLAY  the game's name, the one-per-screen hero moment
#   TITLE    screen verdicts — VICTORY, DEFEAT, PAUSED
#   HEADING  card headings, the boss name
#   SUBHEAD  hero name, section labels
#   READOUT  live numbers — score, timer, damage (bold, lightly tracked)
#   BODY     sentences
#   LABEL    small all-caps UI labels
#   CAPTION  secondary sentences, footnotes
#   MICRO    tick labels, key hints, units

enum Scale { DISPLAY, TITLE, HEADING, SUBHEAD, READOUT, BODY, LABEL, CAPTION, MICRO }

## First value that is read as a literal pixel size rather than a Scale.
## The enum tops out at 8 and no readable text is under 9 px, so the two ranges
## can share one parameter — which lets `title()`/`label()` take a scale while
## older pixel-size call sites keep working untouched.
const RAW_PX := 9

const _SIZE := [88, 56, 28, 21, 26, 17, 14, 13, 11]
const _TRACK := [3, 2, 1, 1, 1, 0, 2, 0, 2]
const _OUTLINE := [9, 7, 5, 4, 5, 4, 3, 3, 2]
const _LEAD := [-8, -5, 0, 0, 0, 3, 1, 2, 1]
## 0 = display face, 1 = UI bold, 2 = UI regular.
const _FACE := [0, 0, 1, 1, 1, 2, 1, 2, 1]


# --- Palette -----------------------------------------------------------------
#
# Porto at golden hour: a warm plum ink lit from above by a low orange sun.
# Surfaces climb in lightness as they climb in elevation.

const BASE := Color("100c18")            # furthest back — full-screen scrims
const SURFACE := Color("1d1526")         # standard panel
const SURFACE_RAISED := Color("281e34")  # card sitting on a panel
const SURFACE_HIGH := Color("342847")    # popovers, selected states
const OVERLAY := Color(0.035, 0.025, 0.055, 0.74)   # dim behind a modal

## Hairlines are warm, never neutral — a cold 1 px white rim is the fastest way
## to make a warm scene look like a generic dark UI kit.
const HAIRLINE := Color(1.0, 0.88, 0.72, 0.10)
const HAIRLINE_STRONG := Color(1.0, 0.88, 0.72, 0.20)
const SHADOW := Color(0.02, 0.01, 0.03, 0.80)

const TEXT_PRIMARY := Color("fbf1df")
const TEXT_SECONDARY := Color("bcae9e")
const TEXT_DISABLED := Color("7a6f7f")

const GOLD := Color("ffc64d")
const GOLD_DEEP := Color("ef8f2c")
const EMBER := Color("ff7a3c")

const SUCCESS := Color("6fd06a")
const DANGER := Color("e8483c")
const WARNING := Color("ffb03a")
const INFO := Color("59b6e8")

# Character identity.
const HERO_GREEN := Color("57c25c")      # Herosauro
const BOXY_RED := Color("ef5a52")        # Super Boxy
const BOSS_AMBER := Color("d98a3a")      # Adamastor, phase 1
const BOSS_RAGE := Color("e0392f")       # Adamastor, phase 2

# Legacy aliases. Kept so existing screens keep compiling while they migrate to
# the semantic names above.
const INK := BASE
const CREAM := TEXT_PRIMARY
const MUTED := TEXT_SECONDARY
const P1 := HERO_GREEN
const P2 := BOXY_RED
const BOSS := BOSS_AMBER
const BOSS_RED := BOSS_RAGE
const VICTORY := Color("7ad06b")
const DEFEAT := Color("ef6157")
const PANEL_BG := SURFACE


# --- Spacing and radius ------------------------------------------------------

const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 20
const SPACE_XL := 32
const SPACE_XXL := 48
## Every screen keeps this clear of the viewport edge.
const SCREEN_MARGIN := 28

const RADIUS_SM := 8
const RADIUS_MD := 14
const RADIUS_LG := 22


# --- Elevation ---------------------------------------------------------------
#
# Depth is fill + hairline + shadow moving together. A panel that only changes
# colour reads as a flat rectangle; one that also gains a shadow reads as an
# object above the scene.

enum Elev { FLAT, LOW, MEDIUM, HIGH, MODAL }

const _ELEV_FILL := [SURFACE, SURFACE, SURFACE_RAISED, SURFACE_RAISED, SURFACE_HIGH]
const _ELEV_SHADOW := [0, 8, 16, 26, 40]
const _ELEV_DROP := [0, 3, 6, 10, 16]
const _ELEV_BORDER := [1, 1, 1, 2, 2]


# --- Character actors --------------------------------------------------------

enum Actor { HEROSAURO, SUPERBOXY, ADAMASTOR }

const PORTRAIT_HEROSAURO: Texture2D = preload("res://assets/ui/portraits/herosauro.png")
const PORTRAIT_SUPERBOXY: Texture2D = preload("res://assets/ui/portraits/superboxy.png")
const PORTRAIT_ADAMASTOR: Texture2D = preload("res://assets/ui/portraits/adamastor.png")

## Square head crops, measured from the alpha bounds of each sheet, so an avatar
## shows a face rather than a randomly centred slice of torso.
const _HEAD_REGION := [
	Rect2i(43, 0, 230, 230),     # Herosauro  (282 x 900)
	Rect2i(19, 4, 190, 190),     # Super Boxy (209 x 900)
	Rect2i(136, 0, 360, 360),    # Adamastor  (631 x 900)
]

const _ACTOR_NAME := ["HEROSAURO", "SUPER BOXY", "ADAMASTOR"]
const _ACTOR_EPITHET := [
	"THE LITTLE DINO OF THE RIBEIRA",
	"THE RED GLOVE",
	"THE GIANT OF THE DOURO",
]
const _ACTOR_COLOR := [HERO_GREEN, BOXY_RED, BOSS_AMBER]

static var _font_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


# --- Text --------------------------------------------------------------------

## Primary text factory. `scale` is a Scale entry.
static func text(scale: int, body: String, color: Color = TEXT_PRIMARY,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return _make_label(body, scale, color, false, align, false)


## Display/comic face. `scale_or_px` takes a Scale entry, or a literal pixel size
## for call sites that have not migrated yet (see RAW_PX).
static func title(body: String, scale_or_px: int = Scale.TITLE, color: Color = GOLD) -> Label:
	return _make_label(body, scale_or_px, color, false, HORIZONTAL_ALIGNMENT_CENTER, true)


## UI face. `scale_or_px` takes a Scale entry or a literal pixel size.
static func label(body: String, scale_or_px: int = Scale.BODY, color: Color = TEXT_PRIMARY,
		bold: bool = false, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	return _make_label(body, scale_or_px, color, bold, align, false)


static func _make_label(body: String, scale_or_px: int, color: Color, force_bold: bool,
		align: int, force_display: bool) -> Label:
	var l := Label.new()
	l.text = body
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var px: int
	var track: int
	var outline: int
	var lead: int
	var base: Font
	if scale_or_px < RAW_PX:
		var i := clampi(scale_or_px, 0, _SIZE.size() - 1)
		px = _SIZE[i]
		track = _TRACK[i]
		outline = _OUTLINE[i]
		lead = _LEAD[i]
		base = _face(_FACE[i], force_bold, force_display)
	else:
		# Literal pixel size: derive a proportionate treatment so ad-hoc sizes
		# still get the same legibility pass as the named steps.
		px = scale_or_px
		track = 1 if force_display else 0
		outline = clampi(int(round(px / 9.0)), 2, 10)
		lead = -int(px / 11.0) if force_display else 0
		base = TITLE_FONT if force_display else (UI_BOLD if force_bold else UI_FONT)

	l.add_theme_font_override("font", _tracked(base, track))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", lead)
	_legible(l, outline)
	return l


## Outline + drop shadow. Both, always: the outline holds the glyph apart from a
## bright sky, the shadow keeps it from floating when the backdrop is mid-tone.
static func _legible(l: Label, outline: int) -> void:
	l.add_theme_color_override("font_outline_color", SHADOW)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, outline / 2))


static func _face(role: int, force_bold: bool, force_display: bool) -> Font:
	if force_display:
		return TITLE_FONT
	match role:
		0:
			return TITLE_FONT
		1:
			return UI_BOLD
		_:
			return UI_BOLD if force_bold else UI_FONT


## Letter-spacing needs a FontVariation wrapper; cache them so a HUD rebuilt
## every frame would still only ever allocate nine of them.
static func _tracked(base: Font, tracking: int) -> Font:
	if tracking == 0:
		return base
	var key := "%s|%d" % [base.resource_path, tracking]
	if _font_cache.has(key):
		return _font_cache[key]
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = tracking
	_font_cache[key] = fv
	return fv


## Pixel size of a Scale entry — for code that draws its own text.
static func size_of(scale: int) -> int:
	return _SIZE[clampi(scale, 0, _SIZE.size() - 1)]


## The font (already tracked) a Scale entry uses — for `draw_string` call sites.
static func font_of(scale: int) -> Font:
	var i := clampi(scale, 0, _SIZE.size() - 1)
	return _tracked(_face(_FACE[i], false, false), _TRACK[i])


# --- Surfaces ----------------------------------------------------------------

## The elevation-aware panel box. Everything that needs to read as a physical
## layer goes through here rather than hand-rolling a StyleBoxFlat.
static func surface(elev: int = Elev.MEDIUM, radius: int = RADIUS_MD, pad: int = SPACE_LG,
		fill: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var e := clampi(elev, 0, _ELEV_FILL.size() - 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill if fill.a > 0.0 else _ELEV_FILL[e]
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 12
	sb.set_border_width_all(_ELEV_BORDER[e])
	sb.border_color = HAIRLINE_STRONG if e >= Elev.HIGH else HAIRLINE
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	if _ELEV_SHADOW[e] > 0:
		sb.shadow_color = Color(0.01, 0.005, 0.02, 0.55)
		sb.shadow_size = _ELEV_SHADOW[e]
		sb.shadow_offset = Vector2(0, _ELEV_DROP[e])
	return sb


## Legacy shape of `surface()`. Kept for screens that still pass a raw colour.
static func panel(color: Color = SURFACE, radius: int = RADIUS_MD, margin: int = SPACE_LG) -> StyleBoxFlat:
	return surface(Elev.MEDIUM, radius, margin, color)


## A ready-made PanelContainer at a given elevation.
static func card(elev: int = Elev.HIGH, radius: int = RADIUS_LG, pad: int = SPACE_XL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", surface(elev, radius, pad))
	return p


## Thin rule used to separate stat rows and card sections.
static func divider(thickness: int = 2, alpha: float = 0.12) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, thickness)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.9, 0.78, alpha)
	sb.set_corner_radius_all(thickness)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Edge scrim — a soft dark fade so text at the top or bottom of the screen stays
## readable over whatever the 3D camera happens to be pointing at.
static func scrim(from_top: bool, height: float, strength: float = 0.66) -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(BASE.r, BASE.g, BASE.b, strength),
		Color(BASE.r, BASE.g, BASE.b, strength * 0.28),
		Color(BASE.r, BASE.g, BASE.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 4
	gt.height = 256
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if from_top else Control.PRESET_BOTTOM_WIDE)
	if from_top:
		tr.offset_bottom = height
	else:
		tr.offset_top = -height
		tr.flip_v = true
	return tr


## Radial screen vignette, transparent at the centre. Used for the damage flash
## and for the sustained low-health edge glow.
static func vignette_texture(edge: Color, inner_stop: float = 0.42) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, inner_stop, 1.0])
	grad.colors = PackedColorArray([
		Color(edge.r, edge.g, edge.b, 0.0),
		Color(edge.r, edge.g, edge.b, 0.0),
		Color(edge.r, edge.g, edge.b, 1.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt


# --- Controls ----------------------------------------------------------------

static func _btn_box(fill: Color, border: Color, lift: float, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = SPACE_LG
	sb.content_margin_right = SPACE_LG
	sb.content_margin_top = SPACE_MD
	sb.content_margin_bottom = SPACE_MD
	sb.shadow_color = Color(0.01, 0.005, 0.02, 0.45)
	sb.shadow_size = int(lift * 2.0)
	sb.shadow_offset = Vector2(0, lift)
	return sb


## Primary buttons are the gold call to action; secondary are raised surfaces.
## Hover and focus both lift the button and warm its rim, so keyboard and mouse
## get the same affordance.
static func button(body: String, primary: bool = false,
		min_size: Vector2 = Vector2(300, 60)) -> Button:
	var b := Button.new()
	b.text = body
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", _tracked(UI_BOLD, 2))
	b.add_theme_font_size_override("font_size", 24)

	var fg := BASE if primary else TEXT_PRIMARY
	var base_fill := GOLD if primary else SURFACE_RAISED
	var hover_fill := GOLD.lightened(0.12) if primary else SURFACE_HIGH
	var rim := Color(1, 1, 1, 0.35) if primary else HAIRLINE_STRONG
	var rim_hot := Color(1, 1, 1, 0.55) if primary else GOLD

	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	b.add_theme_constant_override("outline_size", 0 if primary else 3)
	b.add_theme_color_override("font_outline_color", SHADOW)

	b.add_theme_stylebox_override("normal", _btn_box(base_fill, rim, 3.0, RADIUS_MD))
	b.add_theme_stylebox_override("hover", _btn_box(hover_fill, rim_hot, 6.0, RADIUS_MD))
	b.add_theme_stylebox_override("pressed", _btn_box(base_fill.darkened(0.16), rim, 1.0, RADIUS_MD))
	b.add_theme_stylebox_override("focus", _btn_box(hover_fill, GOLD, 5.0, RADIUS_MD))
	b.add_theme_stylebox_override("disabled", _btn_box(SURFACE, HAIRLINE, 0.0, RADIUS_MD))

	_add_hover_lift(b)
	return b


## A 3% scale pop on hover/focus. Scale is visual only, so it never disturbs the
## container that laid the button out.
static func _add_hover_lift(b: Button) -> void:
	var recentre := func() -> void:
		b.pivot_offset = b.size * 0.5
	b.resized.connect(recentre)
	var to := func(target: float) -> void:
		if not b.is_inside_tree():
			return
		b.pivot_offset = b.size * 0.5
		var t := b.create_tween()
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2(target, target), 0.14)
	b.mouse_entered.connect(func() -> void: to.call(1.03))
	b.mouse_exited.connect(func() -> void: to.call(1.0))
	b.focus_entered.connect(func() -> void: to.call(1.03))
	b.focus_exited.connect(func() -> void: to.call(1.0))


## A small rounded colour chip — a clean stand-in for an icon.
static func chip(color: Color, diameter: float = 14.0) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter / 2.0))
	sb.corner_detail = 8
	p.add_theme_stylebox_override("panel", sb)
	return p


## A keyboard key badge, for control hints that should read as keys not prose.
static func key_cap(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.95, 0.88, 0.10)
	sb.set_corner_radius_all(RADIUS_SM)
	sb.corner_detail = 8
	sb.set_border_width_all(1)
	sb.border_color = HAIRLINE_STRONG
	sb.content_margin_left = SPACE_SM
	sb.content_margin_right = SPACE_SM
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var l := text(Scale.MICRO, key.to_upper(), TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(18, 0)
	p.add_child(l)
	return p


## `entries` is an Array of ["KEY", "Action"] pairs; renders them as key badges
## with their action beside them, evenly spaced.
static func hint_row(entries: Array, gap: int = SPACE_LG) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", gap)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for e in entries:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", SPACE_SM)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(key_cap(String(e[0])))
		pair.add_child(text(Scale.CAPTION, String(e[1]), TEXT_SECONDARY))
		row.add_child(pair)
	return row


## `LABEL ................ VALUE` — the row that makes a results card look
## authored instead of concatenated.
static func stat_row(name: String, value: String, value_color: Color = GOLD,
		emphasis: int = Scale.READOUT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", SPACE_MD)
	var n := text(Scale.LABEL, name.to_upper(), TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var v := text(emphasis, value, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	v.name = "Value"
	row.add_child(v)
	return row


# --- Character art -----------------------------------------------------------

static func actor_name(actor: int) -> String:
	return _ACTOR_NAME[clampi(actor, 0, 2)]


static func actor_epithet(actor: int) -> String:
	return _ACTOR_EPITHET[clampi(actor, 0, 2)]


static func actor_color(actor: int) -> Color:
	return _ACTOR_COLOR[clampi(actor, 0, 2)]


static func portrait_full(actor: int) -> Texture2D:
	match clampi(actor, 0, 2):
		Actor.SUPERBOXY:
			return PORTRAIT_SUPERBOXY
		Actor.ADAMASTOR:
			return PORTRAIT_ADAMASTOR
		_:
			return PORTRAIT_HEROSAURO


## A square head crop, resampled to `px` with mipmaps.
##
## The source sheets are 900 px tall; dropping one straight into a 96 px avatar
## means an 8x minification that plain bilinear filtering turns to mush. Cropping
## and Lanczos-resampling once at build time costs a few milliseconds and gets
## us crisp line art at any HUD size, with no dependency on the .import settings.
static func portrait_head(actor: int, px: int = 256) -> Texture2D:
	var a := clampi(actor, 0, 2)
	var key := "head|%d|%d" % [a, px]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var src := portrait_full(a)
	var out: Texture2D = _resample(src, _HEAD_REGION[a], Vector2i(px, px))
	if out == null:
		out = src
	_tex_cache[key] = out
	return out


## The whole figure, resampled to `height` px tall with mipmaps. Use for large
## character art (menu, results card) so downscaling stays clean.
static func portrait_scaled(actor: int, height: int) -> Texture2D:
	var a := clampi(actor, 0, 2)
	var key := "full|%d|%d" % [a, height]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var src := portrait_full(a)
	var sz := src.get_size()
	var target := Vector2i(maxi(1, int(round(sz.x * height / maxf(sz.y, 1.0)))), height)
	var out: Texture2D = _resample(src, Rect2i(Vector2i.ZERO, Vector2i(sz)), target)
	if out == null:
		out = src
	_tex_cache[key] = out
	return out


## Crop + resample + mipmap. Returns null if the source image cannot be read
## (e.g. a VRAM-compressed import), so callers fall back to the raw texture.
static func _resample(src: Texture2D, region: Rect2i, target: Vector2i) -> Texture2D:
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return null
	if img.is_compressed() and img.decompress() != OK:
		return null
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	var clipped := region.intersection(bounds)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return null
	var cut := img.get_region(clipped)
	cut.convert(Image.FORMAT_RGBA8)
	# Bleeds edge colour into the transparent margin. Without it, downsampling
	# alpha-keyed line art pulls black out of the empty pixels and haloes it.
	cut.fix_alpha_edges()
	cut.resize(maxi(1, target.x), maxi(1, target.y), Image.INTERPOLATE_LANCZOS)
	cut.generate_mipmaps()
	return ImageTexture.create_from_image(cut)


# --- Deprecated --------------------------------------------------------------

## Plain ProgressBar. Superseded by StatBar, which has the lag bar, hit flash and
## low-health pulse. Kept so nothing breaks mid-migration.
static func bar(fill: Color, max_val: float = 100.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = max_val
	pb.value = max_val
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.025, 0.05, 0.92)
	bg.set_corner_radius_all(RADIUS_SM)
	bg.set_border_width_all(2)
	bg.border_color = HAIRLINE
	bg.content_margin_left = 2.0
	bg.content_margin_right = 2.0
	bg.content_margin_top = 2.0
	bg.content_margin_bottom = 2.0
	var fl := StyleBoxFlat.new()
	fl.bg_color = fill
	fl.set_corner_radius_all(RADIUS_SM - 2)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fl)
	return pb
