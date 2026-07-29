extends Control
## The title screen's ground: a navigator's chart of the Douro estuary, drawn
## rather than painted.
##
## Everything here is _draw() calls over a two-stop parchment ramp — no texture,
## no import, nothing to re-export when the window changes size. That is worth a
## note because the obvious alternative, a painted 4K parchment PNG, would cost
## about 3 MB in a 16 MB web build to say something a dozen lines of geometry
## already say, and would band or stretch at aspect ratios it was not authored
## for. This resolves crisply at any size.
##
## WHY A CHART AT ALL. Porto is a port on the Douro and Adamastor is the Cape of
## Storms giant out of Camões — Portuguese Age-of-Discovery myth. Rhumb lines,
## compass roses and a sea monster inked in the margin are this game's own
## iconography, not a borrowed aesthetic. The previous backdrop was a live
## golden-hour render of the gorge, which was a picture of the place; this is the
## map of it, which is the register the whole title screen now speaks in.
##
## RESTRAINT IS THE WHOLE JOB. Every line here is between 13% and 22% opacity.
## Cartography that competes with the menu has stopped being a backdrop, and the
## failure mode of this screen is a busy one, not an empty one.

## Rhumb lines radiate from compass roses on a real portolan chart. Two roses,
## one off each side of the frame, so the lines crossing the middle read as part
## of a larger sheet the frame happens to be cropping.
const ROSE_LEFT := Vector2(-0.18, 0.30)     # in viewport fractions
const ROSE_RIGHT := Vector2(1.12, 0.74)
const RHUMB_COUNT := 16
const GRID_SPACING := 118.0
## Sits in the gap between the menu column (which ends around x=0.34) and the
## cast (which starts around x=0.45). Bottom-right — the reference's position —
## put it squarely behind Adamastor's legs, where none of it was visible.
const ROSE_VISIBLE := Vector2(0.395, 0.795)
const ROSE_RADIUS := 108.0

## The wash the cast stands on, straight off the reference. Without it, alpha-cut
## art on a flat sheet reads as a sticker someone put on the map; with it, the
## cast reads as inked into the chart. Drawn as one organic blob rather than an
## ellipse — a perfect ellipse reads as a UI element, not as spilled ink.
const SPLASH_CENTRE := Vector2(0.655, 0.84)
const SPLASH_RADIUS := Vector2(0.235, 0.145)   # in viewport fractions
const SPLASH_LOBES := 46


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 2.0 or h < 2.0:
		return

	_draw_sheet(w, h)
	_draw_grid(w, h)
	_draw_rhumbs(w, h)
	_draw_rose(Vector2(w * ROSE_VISIBLE.x, h * ROSE_VISIBLE.y), ROSE_RADIUS)
	_draw_route(w, h)
	_draw_splash(w, h)


## The sheet. Lightest a third of the way in from the left — where the menu
## column sits — and ageing toward every edge, so the type always has the
## cleanest paper under it and the corners carry the wear.
func _draw_sheet(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), UIStyle.PAPER)
	# Vignette as four edge bands rather than a radial texture: a radial gradient
	# centred on a 16:9 frame ages the short edges far more than the long ones,
	# which reads as a spotlight instead of as a worn sheet.
	var band := minf(w, h) * 0.42
	_edge_band(Rect2(0, 0, w, band), Vector2(0, 1))
	_edge_band(Rect2(0, h - band, w, band), Vector2(0, -1))
	_edge_band(Rect2(0, 0, band, h), Vector2(1, 0))
	_edge_band(Rect2(w - band, 0, band, h), Vector2(-1, 0))


func _edge_band(r: Rect2, inward: Vector2) -> void:
	var steps := 14
	for i in steps:
		var t := float(i) / float(steps)
		var a := (1.0 - t) * 0.5
		var c := Color(UIStyle.PAPER_EDGE.r, UIStyle.PAPER_EDGE.g, UIStyle.PAPER_EDGE.b, a * 0.16)
		var slab := r
		if absf(inward.y) > 0.0:
			slab.size.y = r.size.y / float(steps)
			slab.position.y = r.position.y + (r.size.y - slab.size.y * (i + 1) if inward.y > 0.0 else slab.size.y * i)
		else:
			slab.size.x = r.size.x / float(steps)
			slab.position.x = r.position.x + (r.size.x - slab.size.x * (i + 1) if inward.x > 0.0 else slab.size.x * i)
		draw_rect(slab, c)


## The graticule. Not square: charts of this period are drawn on a plate that is
## wider than tall, and an exactly square grid reads as graph paper.
func _draw_grid(w: float, h: float) -> void:
	var sx := GRID_SPACING
	var sy := GRID_SPACING * 0.86
	var x := fmod(w, sx) * 0.5
	while x < w:
		draw_line(Vector2(x, 0), Vector2(x, h), UIStyle.CHART_LINE, 1.0)
		x += sx
	var y := fmod(h, sy) * 0.5
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), UIStyle.CHART_LINE, 1.0)
		y += sy


## Rhumb lines from two off-screen roses. Long chords across the whole sheet,
## which is what gives a portolan its characteristic web.
func _draw_rhumbs(w: float, h: float) -> void:
	for origin in [Vector2(w * ROSE_LEFT.x, h * ROSE_LEFT.y),
			Vector2(w * ROSE_RIGHT.x, h * ROSE_RIGHT.y)]:
		var reach := (w + h) * 1.1
		for i in RHUMB_COUNT:
			var ang := TAU * float(i) / float(RHUMB_COUNT)
			draw_line(origin, origin + Vector2(cos(ang), sin(ang)) * reach,
					UIStyle.CHART_LINE, 1.0)


## The drawn compass rose. Eight points, alternating long and short, over two
## rings — the same construction every chart of the period uses.
func _draw_rose(centre: Vector2, r: float) -> void:
	draw_arc(centre, r, 0.0, TAU, 64, UIStyle.CHART_LINE_STRONG, 1.0)
	draw_arc(centre, r * 0.72, 0.0, TAU, 64, UIStyle.CHART_LINE, 1.0)
	draw_arc(centre, r * 0.18, 0.0, TAU, 32, UIStyle.CHART_LINE_STRONG, 1.0)
	for i in 16:
		var ang := TAU * float(i) / 16.0 - PI * 0.5
		var long := i % 2 == 0
		var outer := r * (1.0 if long else 0.72)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(centre + dir * r * 0.18, centre + dir * outer,
				UIStyle.CHART_LINE_STRONG if long else UIStyle.CHART_LINE, 1.0)
	# The four cardinal points get a filled lozenge, north longest.
	for i in 4:
		var ang := TAU * float(i) / 4.0 - PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x) * r * 0.075
		var tip := centre + dir * r * (1.16 if i == 0 else 1.0)
		draw_colored_polygon(PackedVector2Array([
			centre + dir * r * 0.18 + side,
			tip,
			centre + dir * r * 0.18 - side,
		]), UIStyle.CHART_LINE_STRONG)


## A plotted course, dashed, corner to corner. The one element that is not
## symmetric, which is what stops the sheet reading as wallpaper.
func _draw_route(w: float, h: float) -> void:
	var pts := PackedVector2Array([
		Vector2(-0.05, 0.16) * Vector2(w, h),
		Vector2(0.34, 0.33) * Vector2(w, h),
		Vector2(0.72, 0.30) * Vector2(w, h),
		Vector2(1.05, 0.55) * Vector2(w, h),
	])
	for i in pts.size() - 1:
		_dashed(pts[i], pts[i + 1], 15.0, 11.0)


func _dashed(a: Vector2, b: Vector2, dash: float, gap: float) -> void:
	var span := a.distance_to(b)
	if span < 1.0:
		return
	var dir := (b - a) / span
	var t := 0.0
	while t < span:
		var e := minf(t + dash, span)
		draw_line(a + dir * t, a + dir * e, UIStyle.CHART_LINE_STRONG, 1.6)
		t = e + gap


## The crimson ground under the cast. Two passes: a soft wide one for the bleed
## into the paper, then the body over it, so the edge reads as ink soaking rather
## than as a shape with a border.
func _draw_splash(w: float, h: float) -> void:
	var c := Vector2(w * SPLASH_CENTRE.x, h * SPLASH_CENTRE.y)
	var r := Vector2(w * SPLASH_RADIUS.x, h * SPLASH_RADIUS.y)
	_splash_pass(c, r * 1.14, Color(UIStyle.CHART_SPLASH, 0.16), 0.13)
	_splash_pass(c, r, Color(UIStyle.CHART_SPLASH, 0.82), 0.17)


## One lobed blob. The radius is modulated by two out-of-phase sines so the
## outline wanders without ever self-intersecting, which a noise function would
## eventually do at this amplitude.
func _splash_pass(centre: Vector2, r: Vector2, tint: Color, wobble: float) -> void:
	var pts := PackedVector2Array()
	for i in SPLASH_LOBES:
		var t := TAU * float(i) / float(SPLASH_LOBES)
		var k := 1.0 + sin(t * 3.0) * wobble + sin(t * 7.0 + 1.7) * wobble * 0.55
		pts.append(centre + Vector2(cos(t) * r.x * k, sin(t) * r.y * k))
	draw_colored_polygon(pts, tint)
