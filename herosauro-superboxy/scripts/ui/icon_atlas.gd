class_name IconAtlas
extends SubViewport
## The HUD's and the touch overlay's drawn pictograms, rendered ONCE into one
## shared texture and then drawn as plain textured rects.
##
## WHY. On GL Compatibility (the web build) every filled polygon is its own
## draw call: the canvas batcher merges consecutive rects that share a texture
## and nothing else. A KidIcon star is eight polygons and AA rims, the robot
## badge is forty-odd, and the old HUD spent about 120 of its ~220 draw calls a
## frame redrawing the same unchanging pictures. Rendered here once, every
## stamp is one rect on one texture, so a row of goal stars, the AI badge and
## the three touch buttons each cost a single draw call, and consecutive stamps
## merge into one.
##
## The art is still KidIcon's vector code, run at OVERSAMPLE x the display size
## so it stays crisp when the canvas_items stretch scales the HUD up on a big
## tablet. Stamps are packed on shelves; a new stamp re-renders the atlas once.
##
## Alpha: the viewport clears to transparent black, so the stored colour is
## premultiplied. Every stamp is ink-keylined (KidIcon.INK is ~black), so the
## only pixels that differ from straight alpha are the outer AA ring, where the
## colour is ink either way; drawing with the default MIX blend is therefore
## indistinguishable from a premultiplied blend for this art, and the stamps
## need no material (a material would split them off every other HUD batch).
##
## In headless runs (probes) the dummy renderer draws nothing; the textures are
## still valid objects and the layout is unchanged.

## 1.5x: crisp at desktop size (bilinear from 1.5:1) and still about 1:1 on a
## tablet whose canvas_items stretch scales the HUD by 1.6, at under 4 MB for
## the whole sheet. (2x did not fit the HUD and the touch overlay in 1024^2.)
const OVERSAMPLE := 1.5
const SIZE := Vector2i(1024, 1024)
## Empty texels between cells, so linear filtering never reads a neighbour.
const GAP := 6

static var _shared: IconAtlas

var _stamps: Dictionary = {}       # key -> AtlasTexture
var _shelf_x := 0
var _shelf_y := 0
var _shelf_h := 0


## The one atlas. Created on first use and parked under the tree root for the
## rest of the session, so it outlives any HUD or menu that asks for stamps.
static func shared() -> IconAtlas:
	if _shared != null and is_instance_valid(_shared):
		return _shared
	_shared = IconAtlas.new()
	_shared.name = "IconAtlas"
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child.call_deferred(_shared)
	return _shared


func _init() -> void:
	size = SIZE
	transparent_bg = true
	disable_3d = true
	gui_disable_input = true
	render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_target_update_mode = SubViewport.UPDATE_ONCE


## A KidIcon pictogram at `px` display pixels.
static func icon(kind: int, px: float, main: Color = Color("fff3df"),
		second: Color = Color("ffc12b")) -> AtlasTexture:
	var key := "icon:%d:%d:%s:%s" % [kind, int(px), main.to_html(), second.to_html()]
	return shared().stamp(key, Vector2(px, px), func(root: Control) -> void:
		var ic := KidIcon.make(kind, px, main, second)
		root.add_child(ic))


## Any drawn picture: `build` fills a Control of `dims` display pixels, once.
## The same key always returns the same texture.
func stamp(key: String, dims: Vector2, build: Callable) -> AtlasTexture:
	if _stamps.has(key):
		return _stamps[key]
	var w := int(ceil(dims.x * OVERSAMPLE))
	var h := int(ceil(dims.y * OVERSAMPLE))
	if _shelf_x + w > SIZE.x:
		_shelf_x = 0
		_shelf_y += _shelf_h + GAP
		_shelf_h = 0
	if _shelf_y + h > SIZE.y:
		push_warning("IconAtlas is full; '%s' drawn blank" % key)
		var empty := AtlasTexture.new()
		empty.atlas = get_texture()
		_stamps[key] = empty
		return empty
	var at := Vector2(_shelf_x, _shelf_y)
	_shelf_x += w + GAP
	_shelf_h = maxi(_shelf_h, h)

	var root := Control.new()
	root.name = "Stamp%d" % _stamps.size()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = at
	root.size = dims
	root.scale = Vector2(OVERSAMPLE, OVERSAMPLE)
	add_child(root)
	build.call(root)

	var tex := AtlasTexture.new()
	tex.atlas = get_texture()
	tex.region = Rect2(at, Vector2(w, h))
	_stamps[key] = tex
	# Clear and draw again with the new stamp in; every earlier stamp redraws
	# into the same place, so textures already handed out stay valid.
	render_target_update_mode = SubViewport.UPDATE_ONCE
	return tex


func stamp_count() -> int:
	return _stamps.size()


## A TextureRect showing a stamp at its display size.
static func sprite(tex: Texture2D, dims: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size = dims
	r.size = dims
	return r


## How much of the atlas is spoken for (0..1, by shelf height).
func fill() -> float:
	return float(_shelf_y + _shelf_h) / float(SIZE.y)


# --- Nine-slice surfaces -------------------------------------------------------------
#
# Plates, bars, pills and pips are StyleBoxFlats, and every StyleBoxFlat is a
# filled polygon: one draw call each, never batched. Drawn once into the atlas
# and nine-sliced back out as nine textured rects, any number of them share
# the atlas's single batch with the pictograms around them.

## A drawn box ready to nine-slice: the stamp, the shadow overhang it carries
## outside the box (left, top, right, bottom) and its slice margins, all in
## display pixels.
class Box:
	var tex: AtlasTexture
	var pad := Vector4.ZERO
	var margin := Vector4.ZERO


static var _boxes: Dictionary = {}


## `layers` are drawn in order, each inset by the matching `insets` entry (the
## plate's shell and its face are two boxes). The first layer's shadow sets the
## overhang. Same key, same Box.
static func box(key: String, layers: Array, insets: Array = []) -> Box:
	if _boxes.has(key):
		var known: Box = _boxes[key]
		if known.tex != null and is_instance_valid(_shared) and known.tex.atlas == _shared.get_texture():
			return known
	# Copies: every stamp is redrawn whenever a new one is added, so the art
	# must not change under it (a caller recolouring its own box per frame
	# would recolour the stamp).
	layers = layers.map(func(sb: StyleBox) -> StyleBox: return sb.duplicate())
	var main: StyleBoxFlat = layers[0]
	# Per-side slice margins: as deep as that side's corners or border, so a
	# band rounded only at the bottom (the plate's shade) can be short without
	# squashing its corners.
	var edge := Vector4.ZERO   # left, top, right, bottom
	for sb: StyleBoxFlat in layers:
		edge.x = maxf(edge.x, maxf(maxf(sb.corner_radius_top_left, sb.corner_radius_bottom_left),
			sb.border_width_left))
		edge.y = maxf(edge.y, maxf(maxf(sb.corner_radius_top_left, sb.corner_radius_top_right),
			sb.border_width_top))
		edge.z = maxf(edge.z, maxf(maxf(sb.corner_radius_top_right, sb.corner_radius_bottom_right),
			sb.border_width_right))
		edge.w = maxf(edge.w, maxf(maxf(sb.corner_radius_bottom_left, sb.corner_radius_bottom_right),
			sb.border_width_bottom))
	edge = edge.ceil() + Vector4.ONE
	var sh := float(main.shadow_size) if main.shadow_color.a > 0.0 else 0.0
	var off := main.shadow_offset if sh > 0.0 else Vector2.ZERO
	var pad := Vector4(maxf(0.0, sh - off.x), maxf(0.0, sh - off.y),
		maxf(0.0, sh + off.x), maxf(0.0, sh + off.y)).ceil()
	var body := Vector2(edge.x + edge.z + 2.0, edge.y + edge.w + 2.0)
	var dims := body + Vector2(pad.x + pad.z, pad.y + pad.w)
	var b := Box.new()
	b.pad = pad
	b.margin = pad + edge
	b.tex = shared().stamp("box:" + key, dims, func(root: Control) -> void:
		var art := _BoxArt.new()
		art.layers = layers
		art.insets = insets
		art.body = Rect2(Vector2(pad.x, pad.y), body)
		art.size = dims
		root.add_child(art))
	_boxes[key] = b
	return b


## A white rounded rect of radius `r` (only the corners asked for), to tint.
static func round_box(r: int, top: bool = true, bottom: bool = true) -> Box:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.corner_detail = 16
	if top:
		sb.corner_radius_top_left = r
		sb.corner_radius_top_right = r
	if bottom:
		sb.corner_radius_bottom_left = r
		sb.corner_radius_bottom_right = r
	return box("round:%d:%s:%s" % [r, top, bottom], [sb])


## Draw `b` filling `rect` (the box itself; its shadow overhangs outside).
static func draw_box(ci: CanvasItem, b: Box, rect: Rect2, color: Color = Color.WHITE) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var dst := Rect2(rect.position - Vector2(b.pad.x, b.pad.y),
		rect.size + Vector2(b.pad.x + b.pad.z, b.pad.y + b.pad.w))
	draw_nine(ci, b.tex, dst, b.margin, color)


## Nine-slice `tex` into `dst`, keeping `m` (left, top, right, bottom display
## pixels of the stamp) unscaled. Margins shrink together when `dst` is smaller
## than they are, so a nearly empty health bar still draws a sliver.
static func draw_nine(ci: CanvasItem, tex: AtlasTexture, dst: Rect2, m: Vector4,
		color: Color = Color.WHITE) -> void:
	var src := tex.region
	var k := OVERSAMPLE
	# One factor for both axes, so a shrunk corner stays round (StyleBoxFlat
	# clamps its radii the same way when a box is smaller than its corners).
	var fx := minf(1.0, minf(dst.size.x / maxf(0.001, m.x + m.z), dst.size.y / maxf(0.001, m.y + m.w)))
	var fy := fx
	var xd := [dst.position.x, dst.position.x + m.x * fx, dst.end.x - m.z * fx, dst.end.x]
	var yd := [dst.position.y, dst.position.y + m.y * fy, dst.end.y - m.w * fy, dst.end.y]
	var xs := [src.position.x, src.position.x + m.x * k, src.end.x - m.z * k, src.end.x]
	var ys := [src.position.y, src.position.y + m.y * k, src.end.y - m.w * k, src.end.y]
	for j in 3:
		var h: float = yd[j + 1] - yd[j]
		if h <= 0.0:
			continue
		for i in 3:
			var w: float = xd[i + 1] - xd[i]
			if w <= 0.0:
				continue
			ci.draw_texture_rect_region(tex.atlas, Rect2(xd[i], yd[j], w, h),
				Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j]), color)


## A flat rect in the atlas's batch (a plain draw_rect would switch texture and
## break it). Samples the middle of a solid white stamp.
static func draw_flat(ci: CanvasItem, rect: Rect2, color: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var t := _white()
	var c := t.region.get_center()
	ci.draw_texture_rect_region(t.atlas, rect, Rect2(c - Vector2.ONE, Vector2(2, 2)), color)


static func _white() -> AtlasTexture:
	return shared().stamp("white", Vector2(4, 4), func(root: Control) -> void:
		var r := ColorRect.new()
		r.color = Color.WHITE
		r.size = Vector2(4, 4)
		root.add_child(r))


## A Control that fills its rect with one Box, tinted: the atlas stand-in for
## a Panel with a StyleBoxFlat.
class Tile extends Control:
	var box: Box
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if box != null:
			IconAtlas.draw_box(self, box, Rect2(Vector2.ZERO, size), color)


static func tile(b: Box, color: Color = Color.WHITE) -> Tile:
	var t := Tile.new()
	t.box = b
	t.color = color
	return t


## A ready-made Control (a pill, a badge) photographed into the atlas at its
## own minimum size, as a sprite. Static art only.
static func snapshot(key: String, build: Callable, at_least: Vector2 = Vector2.ZERO) -> TextureRect:
	var probe: Control = build.call()
	var dims := probe.get_combined_minimum_size().max(at_least).ceil()
	probe.free()
	var tex := shared().stamp(key, dims, func(root: Control) -> void:
		var c: Control = build.call()
		c.size = dims
		root.add_child(c))
	return sprite(tex, dims)


class _BoxArt extends Control:
	var layers: Array = []
	var insets: Array = []
	var body := Rect2()

	func _draw() -> void:
		for i in layers.size():
			var inset: float = insets[i] if i < insets.size() else 0.0
			(layers[i] as StyleBox).draw(get_canvas_item(), body.grow(-inset))
