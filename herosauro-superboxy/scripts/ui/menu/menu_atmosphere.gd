extends Control
## The grade sitting between the live 3D and the UI.
##
## The backdrop is a real golden-hour render: the sky is brighter than every text
## colour in the palette, and the camera keeps moving, so there is no fixed patch
## of frame that can be relied on to stay dark. Rather than fight that with
## heavier and heavier text outlines, the whole left and top of the frame is
## given a graded pocket to sit in, and the frame edge is closed with a vignette.
##
## Five layers, back to front:
##
##   top scrim      the logo's contrast floor
##   bottom scrim   the hint row's, and it seats the heroes' feet
##   left scrim     the menu column's — the one that does the most work, because
##                  a vertical list of text runs down the brightest part of the
##                  river when the camera swings west
##   horizon glare  a wide warm band where the sun sits, added rather than mixed,
##                  so it reads as light in the lens and not as a beige rectangle
##   vignette       closes the corners and stops the eye leaving the frame
##
## Plus a slow drift of warm motes, which is the cheapest possible answer to "a
## static title screen looks like a screenshot". The gulls circling in-world do
## the rest.

# --- Proportions (fractions of the frame) ------------------------------------
#
# THESE EIGHT NUMBERS ARE THE VISUAL PASS. They were set by reasoning about the
# composite (top and left overlap in the corner where the logo sits, so their
# strengths multiply out to about 0.73 there and fall off fast from it) but
# nobody has yet seen them over a real render. If the menu comes back muddy,
# these are the dials — nothing else in this screen needs touching.

const TOP_SCRIM := 0.36
const TOP_STRENGTH := 0.48
const BOTTOM_SCRIM := 0.24
const BOTTOM_STRENGTH := 0.55
const LEFT_SCRIM := 0.50
const LEFT_STRENGTH := 0.52
const VIGNETTE_ALPHA := 0.50
const VIGNETTE_INNER := 0.36

## The sun in this world is low and off the left of the shot for most of the
## camera's swing, so the glare is a wide horizontal band rather than a disc:
## a disc would have to track the sun's screen position, and would be wrong the
## moment the camera pitched.
const GLARE_TOP := 0.30
const GLARE_BOTTOM := 0.82
const GLARE_COLOR := Color(1.0, 0.62, 0.30)
const GLARE_ALPHA := 0.085

# --- Motes -------------------------------------------------------------------

const MOTE_COUNT := 34
const MOTE_LIFETIME := 11.0
const MOTE_COLOR := Color(1.0, 0.85, 0.60, 0.34)

var _top: TextureRect
var _bottom: TextureRect
var _motes: CPUParticles2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_top = UIStyle.scrim(true, 240.0, TOP_STRENGTH)
	add_child(_top)
	_bottom = UIStyle.scrim(false, 180.0, BOTTOM_STRENGTH)
	add_child(_bottom)

	add_child(_side_scrim())
	add_child(_glare())
	add_child(_vignette())

	_motes = _build_motes()
	add_child(_motes)

	resized.connect(relayout)
	relayout()


func relayout() -> void:
	if size.y <= 1.0:
		return
	_top.offset_bottom = size.y * TOP_SCRIM
	_bottom.offset_top = -size.y * BOTTOM_SCRIM
	_motes.position = size * 0.5
	_motes.emission_rect_extents = Vector2(size.x * 0.5, size.y * 0.58)


# --- Layers ------------------------------------------------------------------

## Horizontal twin of UIStyle.scrim(). Not in UIStyle because only this screen
## has a column of UI running down one edge of a live 3D shot.
func _side_scrim() -> TextureRect:
	var grad := Gradient.new()
	# Holds most of its weight out to 60% of its span before letting go, so the
	# far end of the menu column — the difficulty pills — still has something
	# under it rather than sitting straight on the river.
	grad.offsets = PackedFloat32Array([0.0, 0.60, 1.0])
	grad.colors = PackedColorArray([
		Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, LEFT_STRENGTH),
		Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, LEFT_STRENGTH * 0.40),
		Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.anchor_right = LEFT_SCRIM
	tr.anchor_bottom = 1.0
	return tr


func _glare() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(GLARE_COLOR.r, GLARE_COLOR.g, GLARE_COLOR.b, 0.0),
		Color(GLARE_COLOR.r, GLARE_COLOR.g, GLARE_COLOR.b, GLARE_ALPHA),
		Color(GLARE_COLOR.r, GLARE_COLOR.g, GLARE_COLOR.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 4
	gt.height = 128
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.anchor_right = 1.0
	tr.anchor_top = GLARE_TOP
	tr.anchor_bottom = GLARE_BOTTOM
	# Added, not mixed: light in a lens is additive, and a mixed warm rectangle
	# over a sunset just lowers contrast.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material = mat
	return tr


func _vignette() -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = UIStyle.vignette_texture(UIStyle.BASE, VIGNETTE_INNER)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(1, 1, 1, VIGNETTE_ALPHA)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


# --- Motes -------------------------------------------------------------------

## CPUParticles2D rather than GPUParticles2D on purpose: this has to behave the
## same on the web build's GL Compatibility renderer, and thirty-four sprites is
## nowhere near enough work to be worth a compute dispatch anyway.
func _build_motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = MOTE_COUNT
	p.lifetime = MOTE_LIFETIME
	p.preprocess = MOTE_LIFETIME * 0.8   # the screen is already full on frame one
	p.texture = _mote_texture()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(640, 420)
	p.direction = Vector2(-0.30, -1.0)
	p.spread = 28.0
	p.gravity = Vector2(-3.0, -5.0)      # a slow warm updraught off the river
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 17.0
	p.angular_velocity_min = -18.0
	p.angular_velocity_max = 18.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.color = MOTE_COLOR

	# Fade in and out rather than popping: a mote that appears is litter, a mote
	# that resolves out of the haze is atmosphere.
	# CPUParticles2D takes the Gradient itself, not a GradientTexture1D — it
	# samples it on the CPU, which is also why the mote count stays small.
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.78, 1.0])
	ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0),
	])
	p.color_ramp = ramp

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p


func _mote_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 16
	gt.height = 16
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt
