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
##   * Bangers (the comic face) is DISPLAY ONLY — titles, verdicts, the combo
##     splash. Its all-caps rhythm and hand-inked weight make it unreadable as
##     body copy and unscannable as a tabular readout, so score, timers, health
##     and every sentence use Fredoka instead. It is chosen for impact, not text.
##   * Every piece of text carries BOTH a hard ink outline and a soft drop
##     shadow, because the UI sits over a live BRIGHT DAYLIGHT Porto — blue sky,
##     sunlit granite, white-hot river highlights. There is no backdrop tone we
##     can assume, and every one of them is brighter than our text, so the glyph
##     has to carry its own contrast with it.

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

## Sizes are a step up from a web scale on purpose. This is a console action game
## read from a sofa over a busy 3D frame, not a document read at 60 cm — MICRO is
## the smallest thing on screen and it still has to survive a sunlit granite
## parapet scrolling behind it.
const _SIZE := [92, 60, 32, 24, 30, 18, 15, 14, 12]
const _TRACK := [3, 2, 1, 1, 1, 0, 2, 0, 2]
## Outlines are roughly 12% of the cap height at every step. Over bright daylight
## a 2 px rim is a suggestion; this is the ink line a comic letterform is drawn
## with, and it is what lets cream text cross a white river highlight.
const _OUTLINE := [11, 9, 7, 6, 7, 5, 4, 4, 3]
const _LEAD := [-8, -5, 0, 0, 0, 3, 1, 2, 1]
## 0 = display face, 1 = UI bold, 2 = UI regular.
const _FACE := [0, 0, 1, 1, 1, 2, 1, 2, 1]


# --- Palette -----------------------------------------------------------------
#
# PORTO AT MIDDAY. The golden-hour treatment is gone: the world behind this UI is
# now bright, saturated, high-key daylight — blue sky, sunlit granite, terracotta
# roofs, white glare off the Douro. The palette this system used to carry (a warm
# plum ink chosen to sit under a low orange sun) reads over that as a dark
# generic UI kit pasted onto a colourful game, so the ink has been re-grounded.
#
# THE INK IS THE RIVER. Everything dark here is the deep blue-green the Douro
# goes in the bridge's own shadow at noon. Three reasons that specific dark and
# not a neutral one:
#   * it is a colour the daylight scene actually contains, so the chrome reads as
#     an object cut from the same world rather than a UI layer floating over it;
#   * it is the complement of the sunlit terracotta and granite that fill most of
#     the frame, which is what buys separation without buying brightness;
#   * a SATURATED dark reads as moulded plastic. A neutral one reads as a web
#     dashboard, and that is the single fastest way to fail this brief.
#
# PLATES ARE NEAR-OPAQUE, NOT GLASS. The old surfaces let the world ghost through
# by 4-5%, which worked over a dim sunset and does not work over noon: the thing
# ghosting through is now the brightest thing in the frame and it eats the text.
# The answer a first-party console game uses is the opposite one — a thick opaque
# plate with a hard keyline — and it is also cheaper to read at a glance. The
# scene is never dimmed to make the UI legible; the UI is made solid instead.
const BASE := Color("071320")              # furthest back — curtains, veils, ink
const SURFACE := Color("13273ffa")         # standard panel
const SURFACE_RAISED := Color("1b3550fc")  # card sitting on a panel
const SURFACE_HIGH := Color("24476bfd")    # popovers, selected states
const OVERLAY := Color(0.016, 0.043, 0.078, 0.72)   # dim behind a modal

## The hard outer stroke every physical UI object is drawn with. Chunky comic art
## is defined by its keyline, and a panel that has one reads as a moulded object
## at any size; one edged with a 1 px 10% rim reads as a CSS border.
const KEYLINE := Color(0.016, 0.043, 0.078, 0.94)

## Bevel highlights — the warm key light landing on the top edge of a plate.
## These are warm even though the ink is cool, and deliberately so: the sun is the
## warm source and the sky is the cool fill, so a neutral or cold top rim would
## light the UI from the wrong place and immediately look like a stock widget kit.
const HAIRLINE := Color(1.0, 0.94, 0.82, 0.16)
const HAIRLINE_STRONG := Color(1.0, 0.94, 0.82, 0.34)
const SHADOW := Color(0.012, 0.031, 0.055, 0.85)

const TEXT_PRIMARY := Color("fff3df")
const TEXT_SECONDARY := Color("bfd2e4")
const TEXT_DISABLED := Color("7d93ab")

## Identity gold. Pushed hotter and more saturated than the sunset version: a
## soft ochre that read as "lit" against a dim plum plate reads as "muddy"
## against daylight, and the accent has to stay the loudest colour on screen.
const GOLD := Color("ffc12b")
const GOLD_DEEP := Color("ef8f1c")
const EMBER := Color("ff6a2c")

const SUCCESS := Color("5ed65c")
const DANGER := Color("f04437")
const WARNING := Color("ffb02e")
## The sky's own blue, reused as the informational accent so the one cool signal
## colour in the kit belongs to the same world as the backdrop.
const INFO := Color("3fb4f0")

# Character identity. The hues are unchanged — these three are the game's
# signature and re-grounding the ink is not licence to repaint the cast — but
# each is pushed up in chroma so it still reads as ITS colour when it is sitting
# next to a saturated daylight render instead of a dim one.
const HERO_GREEN := Color("4fc94e")      # Herosauro
const BOXY_RED := Color("f2564a")        # Super Boxy
const BOSS_AMBER := Color("e8902f")      # Adamastor, phase 1
const BOSS_RAGE := Color("e83226")       # Adamastor, phase 2

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

## Radii are generous on purpose. A 4 px corner is a web control; a corner you
## can see the curve of at a glance is a moulded one, and the whole kit is
## supposed to look injection-moulded.
const RADIUS_SM := 10
const RADIUS_MD := 18
const RADIUS_LG := 28


# --- Elevation ---------------------------------------------------------------
#
# Depth is fill + keyline + shadow moving together. A panel that only changes
# colour reads as a flat rectangle; one that also gains a shadow reads as an
# object above the scene.

enum Elev { FLAT, LOW, MEDIUM, HIGH, MODAL }

const _ELEV_FILL := [SURFACE, SURFACE, SURFACE_RAISED, SURFACE_RAISED, SURFACE_HIGH]
const _ELEV_SHADOW := [0, 10, 20, 32, 48]
const _ELEV_DROP := [0, 4, 8, 13, 20]
## Borders are the keyline, so they are measured in whole visible pixels rather
## than in hairlines. Three is the floor at which a stroke still reads as drawn
## rather than as an anti-aliasing artefact once the panel is scaled.
const _ELEV_BORDER := [3, 3, 3, 4, 5]


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

## Full-figure crops, also measured from alpha bounds.
##
## THE SUPER BOXY SHEET HAS TWO POSES ON IT — a front view at the top and a back
## view under it, separated by a 26 px empty band. Scaling the raw sheet, which
## is what every full-figure call site used to do, therefore drew Super Boxy at
## half height with a second Super Boxy standing behind him: on the title screen,
## and on the co-op victory card. Cropping to the front pose is the fix, and
## every actor gets a measured region rather than only the one that needed it,
## because "the sheet is the figure" is the assumption that caused this.
const _FIGURE_REGION := [
	Rect2i(6, 6, 276, 888),      # Herosauro  — one pose, full bleed
	Rect2i(4, 3, 205, 425),      # Super Boxy — front pose only; back view at y 454
	Rect2i(1, 6, 623, 886),      # Adamastor  — one pose
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

## Primary text factory: UI face, left-aligned, sized by a Scale entry.
## Every factory here takes the string first, then the scale.
static func text(body: String, scale: int = Scale.BODY, color: Color = TEXT_PRIMARY,
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


## Outline + drop shadow. Both, always, and both heavier than they were.
##
## The outline is a near-opaque ink keyline, not a soft dark halo: over daylight
## a translucent rim just blends the glyph edge into whatever is behind it, which
## is exactly the failure it was supposed to prevent. The shadow then sits under
## the whole ink-outlined shape and gives it thickness, which is what turns a
## label into a drawn object rather than a colour laid on glass.
static func _legible(l: Label, outline: int) -> void:
	l.add_theme_color_override("font_outline_color", KEYLINE)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0.01, 0.03, 0.05, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(3, outline * 2 / 3))


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
##
## Corner detail is high (16 segments) because the radii are now large enough
## that Godot's default segment count is visible as flats on the curve, and a
## faceted corner on a 28 px radius is the tell that gives away a hand-rolled UI.
static func surface(elev: int = Elev.MEDIUM, radius: int = RADIUS_MD, pad: int = SPACE_LG,
		fill: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var e := clampi(elev, 0, _ELEV_FILL.size() - 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill if fill.a > 0.0 else _ELEV_FILL[e]
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 16
	sb.set_border_width_all(_ELEV_BORDER[e])
	sb.border_color = KEYLINE
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	if _ELEV_SHADOW[e] > 0:
		sb.shadow_color = SHADOW
		sb.shadow_size = _ELEV_SHADOW[e]
		sb.shadow_offset = Vector2(0, _ELEV_DROP[e])
	return sb


## A chunky HUD plate: keyline shell, tinted face, warm top bevel, drop shadow.
##
## This is the piece `surface()` cannot express. A StyleBoxFlat has ONE border
## colour, and moulded plastic needs two — a dark keyline around the outside and
## a light bevel catching the sun along the top — so the plate is built as two
## stacked Panels plus a gradient strip instead. Everything in the HUD that has
## to stay readable over a bright, moving, high-contrast 3D frame is one of
## these, which is why the HUD needs no full-screen scrim.
##
## `tint` is mixed into the face at `tint_amount` so a hero's plate carries his
## colour without the fill ever leaving the ink family and losing its contrast.
static func plate(tint: Color = SURFACE, tint_amount: float = 0.0,
		radius: int = RADIUS_LG, elev: int = Elev.HIGH) -> Panel:
	var e := clampi(elev, 0, _ELEV_FILL.size() - 1)
	var shell := Panel.new()
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.clip_contents = true

	var outer := StyleBoxFlat.new()
	# Lighter than the face. The shell is almost entirely covered by its own
	# border and the inset face, so this only shows in the anti-aliased corner
	# sliver — which is exactly where a raised lip would catch the light.
	outer.bg_color = _ELEV_FILL[e].lightened(0.12).lerp(tint, tint_amount * 0.55)
	outer.bg_color.a = maxf(_ELEV_FILL[e].a, 0.97)
	outer.set_corner_radius_all(radius)
	outer.corner_detail = 16
	outer.set_border_width_all(_ELEV_BORDER[e])
	outer.border_color = KEYLINE
	outer.shadow_color = SHADOW
	outer.shadow_size = _ELEV_SHADOW[e]
	outer.shadow_offset = Vector2(0, _ELEV_DROP[e])
	shell.add_theme_stylebox_override("panel", outer)

	# Inner face, inset by the keyline. Darker than the shell, so the keyline
	# reads as a raised lip around a recessed face rather than as a drawn line.
	var face := Panel.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := float(_ELEV_BORDER[e])
	face.offset_left = inset
	face.offset_top = inset
	face.offset_right = -inset
	face.offset_bottom = -inset
	var face_radius := maxi(2, radius - _ELEV_BORDER[e])
	var inner := StyleBoxFlat.new()
	inner.bg_color = _ELEV_FILL[e].lerp(tint, tint_amount)
	inner.bg_color.a = maxf(_ELEV_FILL[e].a, 0.97)
	inner.set_corner_radius_all(face_radius)
	inner.corner_detail = 16
	face.add_theme_stylebox_override("panel", inner)
	shell.add_child(face)

	# Gloss over the top half and shade under the bottom quarter. Together they
	# are the whole "moulded" read, and they are drawn as PANELS with per-corner
	# radii rather than as a gradient rectangle for a specific reason: a gradient
	# quad laid over a rounded plate paints the transparent corners too, which
	# squares them off. A stylebox rounded on the top corners and square on the
	# bottom follows the plate exactly.
	face.add_child(_gloss(face_radius, 0.0, 0.52, Color(1.0, 0.96, 0.86, 0.13), true))
	face.add_child(_gloss(face_radius, 0.76, 1.0, Color(0.0, 0.02, 0.05, 0.20), false))
	return shell


## One half of a plate's shading. `top`/`bottom` are anchor fractions, so the
## band keeps its proportion whatever height the plate is given.
static func _gloss(radius: int, top: float, bottom: float, tint: Color,
		round_top: bool) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.0
	p.anchor_right = 1.0
	p.anchor_top = top
	p.anchor_bottom = bottom
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.corner_detail = 16
	if round_top:
		sb.corner_radius_top_left = radius
		sb.corner_radius_top_right = radius
	else:
		sb.corner_radius_bottom_left = radius
		sb.corner_radius_bottom_right = radius
	p.add_theme_stylebox_override("panel", sb)
	return p


## Legacy shape of `surface()`. Kept for screens that still pass a raw colour.
static func panel(color: Color = SURFACE, radius: int = RADIUS_MD, margin: int = SPACE_LG) -> StyleBoxFlat:
	return surface(Elev.MEDIUM, radius, margin, color)


## A ready-made PanelContainer at a given elevation.
static func card(elev: int = Elev.HIGH, radius: int = RADIUS_LG, pad: int = SPACE_XL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", surface(elev, radius, pad))
	return p


## Rule used to separate stat rows and card sections. Deliberately a solid warm
## bar rather than a 1 px tint: a hairline rule inside a chunky kit is the one
## piece that gives away that the chunkiness is a skin.
static func divider(thickness: int = 3, alpha: float = 0.22) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, thickness)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.92, 0.80, alpha)
	sb.set_corner_radius_all(thickness)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Edge scrim — a soft dark fade closing the frame edge.
##
## THIS IS A COMPOSITION TOOL, NOT A LEGIBILITY TOOL. The title screen uses it to
## close its corners and to seat the cast's feet, which is a photographic device
## and belongs there. The HUD does not: dimming a bright, saturated game to make
## chrome readable throws away the exact thing the art direction is buying, so
## every in-game readout sits on its own opaque `plate()` instead.
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

## `lift` is BOTH the drop shadow's offset and its blur, so a button that lifts on
## hover casts a longer, softer shadow exactly the way a real key would. The dark
## keyline is constant across every state — a physical object does not lose its
## outline when you look at it — and only the fill moves. The top-light bevel is
## a child gradient strip added by `button()`, because a StyleBoxFlat has one
## border colour and moulded plastic needs a dark one and a light one at once.
static func _btn_box(fill: Color, lift: float, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 16
	sb.set_border_width_all(4)
	sb.border_color = KEYLINE
	sb.content_margin_left = SPACE_LG
	sb.content_margin_right = SPACE_LG
	sb.content_margin_top = SPACE_MD + 2
	sb.content_margin_bottom = SPACE_MD + 2
	sb.shadow_color = SHADOW
	sb.shadow_size = int(lift * 2.2)
	sb.shadow_offset = Vector2(0, lift)
	return sb


## Primary buttons are the gold call to action; secondary are raised surfaces.
## Hover and focus both lift the button and warm its rim, so keyboard and mouse
## get the same affordance.
static func button(body: String, primary: bool = false,
		min_size: Vector2 = Vector2(300, 64)) -> Button:
	var b := Button.new()
	b.text = body
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", _tracked(UI_BOLD, 2))
	b.add_theme_font_size_override("font_size", 26)
	b.clip_contents = false

	var fg := BASE if primary else TEXT_PRIMARY
	var base_fill := GOLD if primary else SURFACE_RAISED
	var hover_fill := GOLD.lightened(0.14) if primary else SURFACE_HIGH

	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	# Ink text on a gold chip already has 11:1 and an outline there only muddies
	# the counters; cream text on an ink chip needs the same keyline as every
	# other label in the kit.
	b.add_theme_constant_override("outline_size", 0 if primary else 5)
	b.add_theme_color_override("font_outline_color", KEYLINE)

	b.add_theme_stylebox_override("normal", _btn_box(base_fill, 4.0, RADIUS_MD))
	b.add_theme_stylebox_override("hover", _btn_box(hover_fill, 8.0, RADIUS_MD))
	b.add_theme_stylebox_override("pressed", _btn_box(base_fill.darkened(0.18), 1.0, RADIUS_MD))
	b.add_theme_stylebox_override("focus", _btn_box(hover_fill, 7.0, RADIUS_MD))
	b.add_theme_stylebox_override("disabled", _btn_box(SURFACE, 0.0, RADIUS_MD))

	# The gloss. Added as a child rather than as a border because a StyleBoxFlat
	# has one border colour and a moulded key needs a dark keyline and a lit top
	# face at the same time. Inset by the keyline so it never paints over it.
	var gloss := _gloss(RADIUS_MD - 4, 0.0, 0.5, Color(1.0, 0.97, 0.90, 0.16), true)
	gloss.offset_left = 4.0
	gloss.offset_right = -4.0
	gloss.offset_top = 4.0
	b.add_child(gloss)

	_add_hover_lift(b)
	return b


## A 5% scale pop on hover/focus with a back-eased overshoot. Scale is visual
## only, so it never disturbs the container that laid the button out.
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
		t.tween_property(b, "scale", Vector2(target, target), 0.18)
	b.mouse_entered.connect(func() -> void: to.call(1.05))
	b.mouse_exited.connect(func() -> void: to.call(1.0))
	b.focus_entered.connect(func() -> void: to.call(1.05))
	b.focus_exited.connect(func() -> void: to.call(1.0))


## A small solid status pill — "P1", "INVINCIBLE", "DOWN". Filled rather than
## outlined: a status the player has to notice mid-fight cannot be a thin badge.
static func pill(body: String, fill: Color, fg: Color = BASE,
		scale: int = Scale.MICRO) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(RADIUS_SM)
	sb.corner_detail = 12
	sb.set_border_width_all(3)
	sb.border_color = KEYLINE
	sb.content_margin_left = SPACE_SM
	sb.content_margin_right = SPACE_SM
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var l := label(body, scale, fg, true, HORIZONTAL_ALIGNMENT_CENTER)
	# No outline on a filled pill: the fill already separates the glyph from the
	# world, and an ink rim inside a 15 px badge closes the counters up.
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	p.add_child(l)
	return p


## A small rounded colour chip — a clean stand-in for an icon. Keylined like
## everything else, so a 12 px dot still reads as a moulded bead rather than as
## an anti-aliased blob when it lands over a bright facade.
static func chip(color: Color, diameter: float = 16.0) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter / 2.0))
	sb.corner_detail = 12
	sb.set_border_width_all(2)
	sb.border_color = KEYLINE
	p.add_theme_stylebox_override("panel", sb)
	return p


## A keyboard key badge, for control hints that should read as keys not prose.
## Solid ink rather than a 10% white wash: a translucent cap over a sunlit quay
## is a rectangle of noise with a letter somewhere in it.
static func key_cap(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE_RAISED
	sb.bg_color.a = 0.95
	sb.set_corner_radius_all(RADIUS_SM)
	sb.corner_detail = 12
	sb.set_border_width_all(3)
	sb.border_color = KEYLINE
	sb.content_margin_left = SPACE_SM
	sb.content_margin_right = SPACE_SM
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	# A key cap is the one control that is literally a physical object, so it
	# gets the largest drop for its size in the kit.
	sb.shadow_color = SHADOW
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	p.add_theme_stylebox_override("panel", sb)
	var l := text(key.to_upper(), Scale.MICRO, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("outline_size", 0)
	l.custom_minimum_size = Vector2(20, 0)
	p.add_child(l)
	return p


# --- Live bindings -----------------------------------------------------------
#
# Every control hint in the game reads the Input Map rather than restating it. A
# hand-written key list is a lie waiting to happen — it is correct exactly until
# someone rebinds something — and in TWO-PLAYER CO-OP it is a lie twice over,
# because the two heroes are driven by two entirely different sets of hardware.
# `InputManager.action_name(player, action)` is public for exactly this, and it
# is the only thing that knows slot 2's actions carry a "p2_" prefix.

## Xbox-layout names for JoyButton indices 0..14, and axis names for 0..5.
## Spelled out rather than drawn as glyphs because neither font in this project
## carries controller symbols, and a missing glyph on the web export (which has
## no system font to fall back to) is a tofu box in a control hint.
const PAD_BUTTONS := ["A", "B", "X", "Y", "View", "Guide", "Menu", "L3", "R3",
		"LB", "RB", "D-Up", "D-Down", "D-Left", "D-Right"]
const PAD_AXES := ["L-Stick", "L-Stick", "R-Stick", "R-Stick", "LT", "RT"]


## One InputEvent as something a player can read. Empty for events with no useful
## caption, which the callers drop.
static func event_caption(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		var caption := OS.get_keycode_string(code)
		# The keypad twins of Enter and the arrows say nothing a player needs.
		return "" if caption.begins_with("Kp ") else caption
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			_:
				return ""
	if ev is InputEventJoypadButton:
		var i := int((ev as InputEventJoypadButton).button_index)
		return PAD_BUTTONS[i] if i >= 0 and i < PAD_BUTTONS.size() else ""
	if ev is InputEventJoypadMotion:
		var axis := int((ev as InputEventJoypadMotion).axis)
		return PAD_AXES[axis] if axis >= 0 and axis < PAD_AXES.size() else ""
	return ""


## What `actions` are actually bound to for local slot `player`, as captions.
##
## Keyboard and mouse first, then the pad. Reading the Input Map in declaration
## order would interleave them — "W, L-Stick, A, S, D" — which is unreadable.
## `per_action` caps how many captions each action contributes, so a compact hint
## row can ask for one apiece while a full controls table asks for all of them.
static func binding_caps(player: int, actions: Array, per_action: int = 0) -> PackedStringArray:
	var keys := PackedStringArray()
	var pads := PackedStringArray()
	for bare in actions:
		var action: StringName = InputManager.action_name(player, StringName(bare))
		if not InputMap.has_action(action):
			continue
		var taken := 0
		for ev in InputMap.action_get_events(action):
			var cap := event_caption(ev)
			if cap.is_empty():
				continue
			var into: PackedStringArray = pads if _is_pad_event(ev) else keys
			if into.has(cap):
				continue
			into.append(cap)
			taken += 1
			if per_action > 0 and taken >= per_action:
				break
	for p in pads:
		if not keys.has(p):
			keys.append(p)
	return keys


static func _is_pad_event(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


## `LABEL [key][key]` — one captioned binding, for a hint row that has to show a
## specific hero's real keys.
static func binding_pair(caption: String, caps: PackedStringArray) -> HBoxContainer:
	var pair := HBoxContainer.new()
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_theme_constant_override("separation", SPACE_XS)
	pair.add_child(text(caption, Scale.MICRO, TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT))
	if caps.is_empty():
		pair.add_child(text("unbound", Scale.MICRO, TEXT_DISABLED))
		return pair
	for cap in caps:
		pair.add_child(key_cap(cap))
	return pair


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
		pair.add_child(text(String(e[1]), Scale.CAPTION, TEXT_SECONDARY))
		row.add_child(pair)
	return row


## `LABEL ................ VALUE` — the row that makes a results card look
## authored instead of concatenated.
static func stat_row(name: String, value: String, value_color: Color = GOLD,
		emphasis: int = Scale.READOUT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", SPACE_MD)
	var n := text(name.to_upper(), Scale.LABEL, TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var v := text(value, emphasis, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
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


## GameManager keys every hero by `player_id` (1 or 2); the UI names them by
## Actor. One place owns that mapping so no screen has to remember which hero is
## which number, and adding a third hero would be a change here and nowhere else.
static func actor_for_player(player_id: int) -> int:
	return Actor.SUPERBOXY if player_id == 2 else Actor.HEROSAURO


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


## The character's front pose, resampled to `height` px tall with mipmaps. Use
## for large character art (menu, results card) so downscaling stays clean.
##
## Crops to _FIGURE_REGION rather than to the sheet — see the note there. The
## returned texture is `height` px tall and proportionally wide, so a call site
## can size against the height alone and never has to know the source aspect.
static func portrait_scaled(actor: int, height: int) -> Texture2D:
	var a := clampi(actor, 0, 2)
	var key := "full|%d|%d" % [a, height]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var src := portrait_full(a)
	# Explicitly typed: the const array is untyped, so `:=` cannot infer Rect2i
	# here and the whole design system fails to compile.
	var region: Rect2i = _FIGURE_REGION[a]
	var target := Vector2i(
		maxi(1, int(round(float(region.size.x) * height / maxf(float(region.size.y), 1.0)))),
		height)
	var out: Texture2D = _resample(src, region, target)
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
	bg.bg_color = BASE
	bg.set_corner_radius_all(RADIUS_SM)
	bg.set_border_width_all(3)
	bg.border_color = KEYLINE
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
