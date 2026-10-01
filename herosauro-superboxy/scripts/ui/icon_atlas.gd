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

const OVERSAMPLE := 2.0
const SIZE := Vector2i(1024, 1024)
const GAP := 4

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
