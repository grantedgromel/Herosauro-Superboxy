extends Control
## The title screen's backdrop. One image, composed once, then it holds still.
##
## WHAT THIS REPLACED, AND WHY. The menu used to render the real Douro gorge live
## behind the type: a second copy of `bridge_arena.tscn` plus a camera on a
## seventy-four second orbit. It looked expensive because it was — the arena's
## `_ready` cascade is several SECONDS of blocking main-thread work, paid before
## anyone can read the title, and it left a second WorldEnvironment and a second
## current Camera3D alive in the viewport for the whole time the menu was up. A
## title screen is the first thing anyone sees and the cheapest thing in the game
## to get right; it has no business being the most expensive screen in it.
##
## So the backdrop is now a picture. Nothing here allocates a mesh, samples a
## camera path or runs per frame, and the whole screen is standing in single-digit
## milliseconds. There is no RNG in this file, seeded or otherwise: a composed
## backdrop that varies between two runs of the same build is a backdrop nobody
## can review.
##
## THE KEY ART DROPS IN AT `KEY_ART_PATH` AND NOWHERE ELSE.
##
## Save the 16:9 cinematic as `res://assets/ui/key_art.png` (or point the constant
## at whatever it is actually called) and this screen picks it up on the next
## boot: `_build()` finds the file, mounts it in a full-bleed TextureRect that is
## already anchored, already layered behind every other element, and already set
## to cover rather than letterbox, and the composed fallback below is skipped
## entirely. No layout change, no second tuning pass, no other file to touch.
##
## Until then, the fallback is a deliberately flat, simply-graded sky-to-river
## wash in the game's own palette, dark enough that the lockup and the menu
## column hold over it with no help. It is not an attempt to imitate the render
## that was removed. It is a poster ground for the cast to stand on, and it says
## so honestly rather than pretending to be Porto.
##
## Layers, back to front:
##
##   ground     the key art, or the composed grade if there is no key art
##   sun        a warm radial off to the right — the light the cast is rimmed by
##   left scrim the menu column's contrast floor
##   bottom     seats the cast's feet and closes the lower edge
##   vignette   closes the corners so the eye stays in the frame

## Where the key art goes. One constant, one file, one line to change.
const KEY_ART_PATH := "res://assets/ui/key_art.png"

# --- Composed fallback -------------------------------------------------------
#
# Four stops down the frame: upper sky, the haze where the gorge meets it, the
# river taking the sky's colour, and the river in the bridge's own shadow at the
# bottom. Values are kept well under the type's — TEXT_PRIMARY is near-white and
# GOLD is the loudest thing on the screen, and both have to stay that way.

## Plain Array rather than PackedFloat32Array: a packed array built from a
## literal is not a constant expression in GDScript, so this is converted at the
## one call site instead of being folded here.
const GRADE_OFFSETS: Array[float] = [0.0, 0.46, 0.72, 1.0]
const GRADE_SKY_HIGH := Color("0d2a4a")
const GRADE_HAZE := Color("2c6489")
const GRADE_RIVER := Color("123049")
const GRADE_DEEP := Color("071320")     # UIStyle.BASE — the ink the kit is built from

## A warm radial where the sun would be, out over the gorge on the right. The
## cast's cut-outs carry a hot rim light (see hero_stage.gd) and a rim with no
## source in frame is the thing that makes composited art read as pasted on.
##
## Warm and radial rather than pale and full-width, on purpose. The removed
## atmosphere layer put an ADDITIVE near-white band right across the horizon,
## which is a large part of why the old menu read as one white mass behind the
## type; a small warm disc off to one side is a light source, a pale band across
## the middle of the frame is a fogged lens.
const SUN_COLOR := Color(1.0, 0.81, 0.56)
const SUN_ALPHA := 0.12
const SUN_CENTRE := Vector2(0.68, 0.40)
const SUN_RADIUS := 0.46                # of the frame's diagonal

# --- The title block ---------------------------------------------------------
#
# A dark field down the left edge that the lockup and the menu column sit in.
#
# THIS IS THE ONE PLACE THE KEY ART AND THE UI GENUINELY FIGHT, so it is worth
# writing down why it is shaped the way it is rather than leaving the next person
# to rediscover it with a screenshot.
#
# The cinematic is a CENTRE-WEIGHTED poster: Herosauro stands at 0.26-0.37 of the
# frame width with his head at 0.29-0.47 of its height, Adamastor fills the
# middle, Super Boxy is at 0.54-0.75 and the bridge closes the right. The UI is a
# left column running 0.06-0.40. Those overlap, and no reframing fixes it —
# panning Herosauro clear of the column needs a 1.54x blow-up, which throws away
# the bridge entirely and softens what is left. The art fits the frame almost
# exactly (1.777:1 against 1.778:1), so there is no crop headroom to spend either.
#
# So the column is given a field to sit in instead, and the shape of that field is
# doing three specific things:
#
#   * it HOLDS its full value right across Herosauro's head, not just across the
#     type. That is the whole trick, and the two renders it took to find it are
#     worth recording: a ramp that FALLS OFF over his face lights one cheek and
#     shadows the other with the strapline running along the join, which looks
#     like a mistake. A field that covers him evenly reads as shade;
#   * it is only HALF strength. At 0.58 he went to a silhouette, and a title that
#     says HEROSAURO over a hidden Herosauro is worse than the collision it was
#     fixing. At 0.50 his mask, cape and pose all still read — he is subordinate
#     to the type rather than removed by it, which is what a title block does to
#     the art behind it;
#   * it STOPS well short of the middle. Over half the frame — the giant, Super
#     Boxy, the bridge, the whole Ribeira right of centre — is untouched art.
#
# THAT LAST POINT IS THE ONE TO PROTECT. The complaint that started this work was
# a screen washed out to near-white, and the reflex correction is a full-frame
# scrim, which trades one flat frame for another. A local, shaped field over a
# third of the width is a title block; the same value spread over the whole frame
# is a fog. If this ever needs to move, move the SHAPE, not the coverage.
#
# If the art is ever recomposed with a quiet left third, all four numbers below
# should come down together — the field exists to solve this cinematic, not as a
# permanent tax on whatever is behind the column.

const LEFT_SCRIM := 0.48                # fraction of the width the field spans
const LEFT_STRENGTH := 0.50
## Where the field is still at full value, and where it has mostly let go, as
## fractions of LEFT_SCRIM. 0.77 of 0.48 is x = 0.371 — the right edge of
## Herosauro's head, so his whole face is in the field rather than half-lit by a
## ramp running across it. 0.91 is x = 0.437, past his shoulder.
const LEFT_HOLD := 0.77
const LEFT_RELEASE := 0.91
const LEFT_RELEASE_STRENGTH := 0.36     # fraction of LEFT_STRENGTH at the release

const BOTTOM_SCRIM := 0.26
const BOTTOM_STRENGTH := 0.36
const VIGNETTE_ALPHA := 0.34
const VIGNETTE_INNER := 0.38

var _key_art: Texture2D
var _bottom: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(relayout)
	relayout()


func relayout() -> void:
	if size.y <= 1.0:
		return
	_bottom.offset_top = -size.y * BOTTOM_SCRIM


## True when the key art file exists and is what is on screen. `hero_stage.gd`'s
## visibility hangs off this — see main_menu.gd — because the key art already has
## the cast in it and staging the cut-outs on top would draw Adamastor twice.
func has_key_art() -> bool:
	return _key_art != null


# --- Construction ------------------------------------------------------------

func _build() -> void:
	_key_art = _load_key_art()
	if _key_art != null:
		add_child(_key_art_rect())
	else:
		add_child(_composed_ground())
		add_child(_sun())

	add_child(_left_scrim())
	_bottom = UIStyle.scrim(false, 180.0, BOTTOM_STRENGTH)
	add_child(_bottom)
	add_child(_vignette())


## `ResourceLoader.exists()` first, and `load()` only then. A bare `load()` of a
## missing path prints an error every boot until the art lands, and an error the
## team is trained to ignore is worse than no check at all.
func _load_key_art() -> Texture2D:
	if not ResourceLoader.exists(KEY_ART_PATH):
		return null
	return load(KEY_ART_PATH) as Texture2D


## Full-bleed, cropped rather than letterboxed. The project stretches
## `canvas_items` with `expand`, so the frame is 16:9 or wider or taller
## depending on the window, and a 16:9 plate fitted inside it would show the
## clear colour down two edges. Covering crops the long axis instead, which is
## what a key art plate is composed to survive.
func _key_art_rect() -> TextureRect:
	var tr := TextureRect.new()
	tr.name = "KeyArt"
	tr.texture = _key_art
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


func _composed_ground() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array(GRADE_OFFSETS)
	grad.colors = PackedColorArray([
		GRADE_SKY_HIGH, GRADE_HAZE, GRADE_RIVER, GRADE_DEEP,
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	# Four wide, because the ramp only varies down the frame; the TextureRect
	# scales it across. A full-resolution gradient texture here would be a
	# megabyte of VRAM for four colours.
	gt.width = 4
	gt.height = 256
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.name = "ComposedGround"
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


func _sun() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	grad.colors = PackedColorArray([
		Color(SUN_COLOR.r, SUN_COLOR.g, SUN_COLOR.b, SUN_ALPHA),
		Color(SUN_COLOR.r, SUN_COLOR.g, SUN_COLOR.b, SUN_ALPHA * 0.45),
		Color(SUN_COLOR.r, SUN_COLOR.g, SUN_COLOR.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var tr := TextureRect.new()
	tr.name = "Sun"
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored as a fraction of the frame so the light stays in the same place in
	# the composition at every window shape, rather than in the same pixel.
	tr.anchor_left = SUN_CENTRE.x - SUN_RADIUS
	tr.anchor_right = SUN_CENTRE.x + SUN_RADIUS
	tr.anchor_top = SUN_CENTRE.y - SUN_RADIUS
	tr.anchor_bottom = SUN_CENTRE.y + SUN_RADIUS
	# Added, not mixed: light in a lens is additive, and a mixed warm disc over a
	# blue ground is a beige stain.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material = mat
	return tr


## Horizontal twin of UIStyle.scrim(). Not in UIStyle because only this screen has
## a column of UI running down one edge of a full-bleed image. See the note above
## the constants for the shape and why it is that shape.
func _left_scrim() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, LEFT_HOLD, LEFT_RELEASE, 1.0])
	grad.colors = PackedColorArray([
		Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, LEFT_STRENGTH),
		Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, LEFT_STRENGTH),
		Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b,
				LEFT_STRENGTH * LEFT_RELEASE_STRENGTH),
		Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var tr := TextureRect.new()
	tr.name = "LeftScrim"
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.anchor_right = LEFT_SCRIM
	tr.anchor_bottom = 1.0
	return tr


func _vignette() -> TextureRect:
	var tr := TextureRect.new()
	tr.name = "Vignette"
	tr.texture = UIStyle.vignette_texture(UIStyle.BASE, VIGNETTE_INNER)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(1, 1, 1, VIGNETTE_ALPHA)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr
