extends Control
## HeroStage — the cast, composited over the live Porto as foreground art.
##
## The three character sheets are the game's identity, so they are staged rather
## than decorated with: Adamastor looms enormous and dark on the right, cropped
## by the frame edge because a giant that fits on screen is not a giant; the two
## heroes stand in front of him, small, lit and facing his way. The whole reason
## the logo and the menu live on the LEFT margin is to leave this half of the
## frame to them.
##
## Each figure is three stacked copies of the same texture:
##
##   shadow  a sepia displaced copy. Alpha-keyed line art dropped straight onto
##           the sheet reads as a sticker; a displaced dark copy is the cheapest
##           thing that seats it, and it suits hand-drawn cartoon art in a way a
##           soft blur would not.
##   rim     a slightly enlarged copy behind the body, in ink — so it reads as
##           the outline of a drawing rather than as a glow around a photo.
##   body    the art itself, tinted.
##
## THE PLATES WERE BUILT FOR A SUNSET AND ARE NOW ON PAPER. That inverts two of
## them. The rim used to be a hot orange edge, because the sun in that world was
## low and behind the Ribeira and everything in the foreground was backlit; on
## parchment a warm halo is invisible at best and a muddy fringe at worst, and
## what the figure actually needs is the dark contour every inked chart figure
## has. The pocket of dusk beneath each figure was there to stop a dark cut-out
## floating over a bright sky — the crimson wash in chart_backdrop.gd does that
## job now, and a second grey pool on top of it only dirties the paper.
##
## Motion is deliberately tiny. Two things drive it: a slow breath per figure on
## its own period, and a parallax shear taken from the live camera's own azimuth
## (plus a little from the pointer). Tying the foreground to the 3D move is what
## makes the cut-outs feel like they are standing IN Porto rather than on top of
## a picture of it — and it costs one float per frame.

# --- Composition -------------------------------------------------------------
#
# Everything is expressed in "stage units". One unit is the viewport height,
# capped against its width so a tall window (4:3 letterboxed by the project's
# `expand` stretch) cannot inflate the art until it runs into the menu column.

## Tuned against the four-aspect sweep in _flow_probe.gd. It has to be low
## enough that the WIDTH binds at 16:9 rather than the height: once it does,
## 1280x720 and 1280x960 resolve to the same stage unit, and the composition
## stops changing when the window gets taller. 0.58 left the height binding at
## 16:9 and let a 4:3 window inflate the cast to 30 px off the menu column;
## 0.56 pulls 16:9 in by 3 px and holds every taller aspect at that same size.
const WIDTH_CAP := 0.56

## Per figure: how tall it stands, where its centre sits measured back from the
## right edge, and how far its feet drop past the bottom of the frame. Adamastor
## is both the biggest and the highest-footed, which is exactly the read we want:
## further away, and still twice everyone's height.
const ADAMASTOR_SIZE := 0.88
const ADAMASTOR_X := 0.2085           # centre, back from the right edge
const ADAMASTOR_FEET := -0.055        # negative lifts the feet up into the frame
const HEROSAURO_SIZE := 0.60
## Moved out from 0.72 when Super Boxy's real width appeared. The two heroes
## have to be far enough apart that the smaller one isn't half-eaten by the
## larger; the room for it comes from letting Herosauro's shoulder cross
## Adamastor's leg, which is the read we want anyway — heroes in FRONT of him.
const HEROSAURO_X := 0.65
const HEROSAURO_FEET := 0.012
## Retuned when superboxy.png was re-extracted. The sheet is a 2x2 grid of poses
## and the first extraction sliced a column spanning both rows, so the texture
## was the front pose with the BACK pose stacked under it: the menu drew a
## second Super Boxy, half off the bottom of the frame, and the front pose only
## ever filled the top 47% of its own box. These numbers are for a texture that
## is one figure edge to edge — hence the smaller height and the much wider art.
const SUPERBOXY_SIZE := 0.50
const SUPERBOXY_X := 0.82
## Feet a few pixels shy of Herosauro's ground line, so he reads as standing
## just behind his brother rather than beside him on the same mark.
const SUPERBOXY_FEET := 0.005

## Requested texture heights are rounded to this so that dragging a window edge
## cannot fire a Lanczos resample of a 900 px sheet on every single frame.
const RESAMPLE_STEP := 32

# --- Treatment ---------------------------------------------------------------

## Adamastor is warmed toward the sheet rather than knocked back into it. The old
## value pushed him darker and cooler so the right half of the frame stayed quiet
## against a bright sky; on paper "quiet" runs the other way, and pushing him
## darker only made him the loudest thing on the page. Holding him near his own
## value and pulling the purple out lets him read as an inked chart monster.
const ADAMASTOR_TINT := Color(0.74, 0.68, 0.72, 0.96)
const HERO_TINT := Color(1.0, 1.0, 1.0, 1.0)
## Ink, not backlight. Same plate, opposite job — see the note at the top.
const ADAMASTOR_RIM := Color(0.16, 0.09, 0.06, 0.72)
const HERO_RIM := Color(0.16, 0.09, 0.06, 0.62)
## Sepia rather than plum-black: a cool shadow on warm paper reads as a hole in
## the sheet, a warm one reads as ink.
const SHADOW_TINT := Color(0.28, 0.16, 0.09, 0.30)
const SHADOW_OFFSET := Vector2(0.016, 0.010)   # in stage units, down and right
## The rim is a fixed width in screen pixels, not a percentage of the figure.
## Scaling it with the art would give Adamastor a fat halo and Super Boxy none,
## when what backlighting actually does is put the same thin edge on everything.
const RIM_PIXELS := 0.005                      # of the stage unit

# --- Motion ------------------------------------------------------------------

const BREATH := [4.9, 3.7, 4.3]        # seconds per breath, per figure
const BREATH_RISE := [0.0035, 0.0060, 0.0055]
## How much of the camera's swing each figure inherits. Near things move most.
const PARALLAX_DEPTH := [0.42, 1.0, 0.82]
const PARALLAX_CAMERA := 0.030
const PARALLAX_POINTER := 0.012
const POINTER_LAMBDA := 5.0

## Drives the parallax shear. main_menu.gd feeds this from the live camera's
## normalised azimuth, so the cut-outs slide against the world as it orbits.
var camera_sway: float = 0.0

var _figures: Array[Dictionary] = []
var _unit: float = 720.0
var _clock: float = 0.0
var _pointer: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Back to front. Adamastor first so both heroes stand in front of him.
	_figures.append(_build(UIStyle.Actor.ADAMASTOR, ADAMASTOR_SIZE, ADAMASTOR_X,
			ADAMASTOR_FEET, ADAMASTOR_TINT, ADAMASTOR_RIM, 0))
	_figures.append(_build(UIStyle.Actor.SUPERBOXY, SUPERBOXY_SIZE, SUPERBOXY_X,
			SUPERBOXY_FEET, HERO_TINT, HERO_RIM, 2))
	_figures.append(_build(UIStyle.Actor.HEROSAURO, HEROSAURO_SIZE, HEROSAURO_X,
			HEROSAURO_FEET, HERO_TINT, HERO_RIM, 1))
	resized.connect(relayout)
	relayout()


# --- Construction ------------------------------------------------------------

func _build(actor: int, height: float, from_right: float, feet: float,
		tint: Color, rim: Color, breath_slot: int) -> Dictionary:
	var holder := Control.new()
	holder.name = UIStyle.actor_name(actor).replace(" ", "")
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	# A pocket of dusk under each figure. Without it a dark cut-out over a bright
	# river has nothing to sit in and the silhouette shreds against the water.
	var pocket := TextureRect.new()
	pocket.texture = _pocket_texture()
	pocket.stretch_mode = TextureRect.STRETCH_SCALE
	pocket.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pocket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pocket)

	return {
		"actor": actor,
		"height": height,
		"from_right": from_right,
		"feet": feet,
		"holder": holder,
		"pocket": pocket,
		"shadow": _plate(holder, SHADOW_TINT),
		"rim": _plate(holder, rim),
		"body": _plate(holder, tint),
		"breath": BREATH[breath_slot],
		"rise": BREATH_RISE[breath_slot],
		"depth": PARALLAX_DEPTH[breath_slot],
		"base": Vector2.ZERO,
		"tex_h": 0,
	}


func _plate(parent: Control, tint: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = tint
	# The sheets are 900 px tall and get drawn at roughly half that, so mipmaps
	# are the difference between clean ink lines and a crawling edge.
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(tr)
	return tr


## Dark at the centre, gone at the rim — the inverse of a vignette.
func _pocket_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	# Kept as a node so the composition code below does not need a special case,
	# but fully transparent: chart_backdrop.gd's crimson wash is what grounds the
	# cast now, and a grey pool over it just dirties the paper. Restore these
	# stops if the backdrop ever goes dark again.
	grad.colors = PackedColorArray([
		Color(UIStyle.CHART_SPLASH, 0.0),
		Color(UIStyle.CHART_SPLASH, 0.0),
		Color(UIStyle.CHART_SPLASH, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt


# --- Layout ------------------------------------------------------------------

func relayout() -> void:
	_unit = minf(size.y, size.x * WIDTH_CAP)
	if _unit <= 1.0:
		return
	for fig in _figures:
		_fit(fig)
	_apply_motion()


func _fit(fig: Dictionary) -> void:
	var h := float(fig["height"]) * _unit
	# Quantised so the Lanczos resample in UIStyle is hit once per size, not once
	# per resize event — the cache in UIStyle keys on the exact pixel height.
	var want := maxi(RESAMPLE_STEP, roundi(h / RESAMPLE_STEP) * RESAMPLE_STEP)
	if int(fig["tex_h"]) != want:
		fig["tex_h"] = want
		var tex := UIStyle.portrait_scaled(int(fig["actor"]), want)
		for key in ["shadow", "rim", "body"]:
			(fig[key] as TextureRect).texture = tex

	var tex: Texture2D = (fig["body"] as TextureRect).texture
	var aspect := 1.0
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var w := h * aspect

	var centre_x := size.x - float(fig["from_right"]) * _unit
	var top := size.y + float(fig["feet"]) * _unit - h
	var origin := Vector2(centre_x - w * 0.5, top)
	fig["base"] = origin

	var holder: Control = fig["holder"]
	holder.position = origin
	holder.size = Vector2(w, h)

	var body: TextureRect = fig["body"]
	body.position = Vector2.ZERO
	body.size = Vector2(w, h)

	var shadow: TextureRect = fig["shadow"]
	shadow.position = Vector2(SHADOW_OFFSET.x, SHADOW_OFFSET.y) * _unit
	shadow.size = Vector2(w, h)

	# Grown about the centre so the halo is even, then pushed back behind the
	# body by the child order set up in _build().
	var rim: TextureRect = fig["rim"]
	var grow := Vector2.ONE * (RIM_PIXELS * _unit * 2.0)
	rim.position = -grow * 0.5
	rim.size = Vector2(w, h) + grow

	var pocket: TextureRect = fig["pocket"]
	var pad := Vector2(w * 0.75, h * 0.40)
	pocket.position = -pad * 0.5 + Vector2(0.0, h * 0.10)
	pocket.size = Vector2(w, h) + pad

	# Kept in step with the layout rather than set once in play_entry(): the
	# entry scale pivots on the figure's feet, and a stale pivot after a resize
	# would make it grow out of the wrong place.
	holder.pivot_offset = Vector2(w * 0.5, h)


# --- Motion ------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	var want := Vector2.ZERO
	if size.x > 1.0 and size.y > 1.0 and DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		want = (get_local_mouse_position() / size - Vector2(0.5, 0.5)).clamp(
				Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	_pointer = _pointer.lerp(want, 1.0 - exp(-POINTER_LAMBDA * delta))
	_apply_motion()


func _apply_motion() -> void:
	for fig in _figures:
		var depth := float(fig["depth"])
		var breathe := sin(TAU * _clock / float(fig["breath"]))
		var offset := Vector2(
			-camera_sway * depth * PARALLAX_CAMERA * _unit
					+ _pointer.x * depth * PARALLAX_POINTER * _unit * 2.0,
			breathe * float(fig["rise"]) * _unit
					+ _pointer.y * depth * PARALLAX_POINTER * _unit)
		(fig["holder"] as Control).position = (fig["base"] as Vector2) + offset


# --- Entry -------------------------------------------------------------------

## Rise and fade in, back to front, so the giant is already there when the heroes
## step in front of him.
func play_entry(delay: float, stagger: float) -> void:
	var i := 0
	for fig in _figures:
		var holder: Control = fig["holder"]
		holder.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		var wait := delay + stagger * float(i)
		tw.tween_property(holder, "modulate:a", 1.0, 0.72).set_delay(wait)
		# Rising is done with scale about the feet, not with position: position is
		# rewritten every frame by _apply_motion for the breath and the parallax,
		# and a tween on it would be overwritten before it drew.
		holder.scale = Vector2.ONE
		tw.tween_property(holder, "scale", Vector2.ONE, 0.9) \
				.from(Vector2(1.0, 0.955)).set_delay(wait) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1
