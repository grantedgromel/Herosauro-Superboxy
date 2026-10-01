class_name PortraitFrame
extends Control
## A framed character avatar for the HUD and results card.
##
## The concept art is alpha-keyed, so a square head crop drops straight onto a
## rounded plate with no masking needed — the corners of the crop are already
## transparent. That gets us the classic fighting-game portrait for the cost of
## a Panel, a TextureRect and a rim.
##
## The frame is not decoration: it carries the character's colour, so the player
## learns "green cluster = me, amber banner = the giant" before reading a word.

## Thick on purpose. The rim is the character's colour and it is the piece the
## player reads before any text, so it has to survive being 84 px across on a
## screen full of sunlit granite. Three pixels was a border; six is a bezel.
const RIM_WIDTH := 6
## The ink stroke around the outside of the plate, under the colour rim.
const PLATE_KEYLINE := 3
## Room around a stamped frame for its plate's drop shadow (14 px, 5 down).
## A stamp must never draw outside its own cell: the shadow used to spill
## into the neighbouring cell of the atlas and sat on whatever used it.
const STAMP_PAD := 20.0

var actor: int = UIStyle.Actor.HEROSAURO
var accent: Color = UIStyle.HERO_GREEN

## Stamped (the in-game HUD): the whole framed portrait is drawn once into the
## IconAtlas and shown as one textured rect, which batches with the plate and
## bar around it; live, it is a shadowed StyleBox polygon, the art and a rim
## polygon, three draw calls. A hit flash then brightens the whole stamp rather
## than only the art and the rim. Set before the frame enters the tree.
var stamped: bool = false

var _sprite: TextureRect
var _stamped_for := ""
var _plate: Panel
var _art: TextureRect
var _rim: Panel
var _plate_box := StyleBoxFlat.new()
var _rim_box := StyleBoxFlat.new()
var _flash: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if stamped:
		_sprite = TextureRect.new()
		_sprite.name = "Stamp"
		_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_sprite.stretch_mode = TextureRect.STRETCH_SCALE
		# The stamp carries the plate's drop shadow, so it overhangs the frame.
		_sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_sprite.offset_left = -STAMP_PAD
		_sprite.offset_top = -STAMP_PAD
		_sprite.offset_right = STAMP_PAD
		_sprite.offset_bottom = STAMP_PAD
		add_child(_sprite)
		resized.connect(_restamp)
		_restamp()
		set_process(false)
		return
	_plate = Panel.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate.add_theme_stylebox_override("panel", _plate_box)
	add_child(_plate)

	_art = TextureRect.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Clear of the keyline AND the colour rim, or the crop's shoulders are cut
	# off by the bezel it is supposed to sit inside.
	var inset := float(RIM_WIDTH + PLATE_KEYLINE + 2)
	_art.offset_left = inset
	_art.offset_top = inset
	_art.offset_right = -inset
	_art.offset_bottom = -inset
	add_child(_art)

	_rim = Panel.new()
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Inset by the plate's keyline so both strokes are visible at once — a
	# coloured rim drawn flush with a dark one just hides it.
	_rim.offset_left = PLATE_KEYLINE
	_rim.offset_top = PLATE_KEYLINE
	_rim.offset_right = -PLATE_KEYLINE
	_rim.offset_bottom = -PLATE_KEYLINE
	_rim.add_theme_stylebox_override("panel", _rim_box)
	add_child(_rim)

	_apply(actor)
	set_process(false)


## Point the frame at a character. Pulls the head crop, the accent colour and the
## plate tint from UIStyle so nothing here hard-codes an asset path.
func set_actor(which: int, resolution: int = 256) -> void:
	actor = which
	if stamped:
		_restamp()
	elif is_inside_tree():
		_apply(which, resolution)


## The live frame at this size, rendered into the atlas once per actor and size.
func _restamp() -> void:
	if _sprite == null:
		return
	var d := size.floor()
	if d.x < 8.0 or d.y < 8.0:
		return
	var key := "%d:%dx%d" % [actor, int(d.x), int(d.y)]
	if key == _stamped_for:
		return
	_stamped_for = key
	accent = UIStyle.actor_color(actor)
	_sprite.texture = stamp_for(actor, d)


## The stamp for `which` at size `d`. Call it ahead of time for a frame whose
## actor changes mid-run (the story toast), so the atlas never has to redraw
## itself in the middle of play.
static func stamp_for(which: int, d: Vector2) -> AtlasTexture:
	var key := "portrait:%d:%dx%d" % [which, int(d.x), int(d.y)]
	var dims := d + Vector2.ONE * STAMP_PAD * 2.0
	return IconAtlas.shared().stamp(key, dims, func(root: Control) -> void:
		var live := PortraitFrame.new()
		live.actor = which
		live.position = Vector2.ONE * STAMP_PAD
		live.size = d
		root.add_child(live))


func _apply(which: int, resolution: int = 256) -> void:
	accent = UIStyle.actor_color(which)
	if _art:
		_art.texture = UIStyle.portrait_head(which, resolution)

	# Plate: an opaque ink wash tinted toward the character so the line art
	# separates. Fully opaque now — over bright daylight, a 92% plate is a window
	# onto whatever is blowing out behind the hero's face.
	_plate_box.bg_color = UIStyle.SURFACE.lerp(accent, 0.22)
	_plate_box.bg_color.a = 1.0
	_plate_box.set_corner_radius_all(UIStyle.RADIUS_MD)
	_plate_box.corner_detail = 16
	# The dark keyline lives on the PLATE and the colour rim sits inside it, so
	# the avatar reads as a coloured bezel set into an ink surround — two strokes,
	# which is what stops a bright accent rim dissolving into a bright backdrop.
	_plate_box.set_border_width_all(PLATE_KEYLINE)
	_plate_box.border_color = UIStyle.KEYLINE
	_plate_box.shadow_color = UIStyle.SHADOW
	_plate_box.shadow_size = 14
	_plate_box.shadow_offset = Vector2(0, 5)

	_rim_box.bg_color = Color(0, 0, 0, 0)
	_rim_box.set_corner_radius_all(UIStyle.RADIUS_MD)
	_rim_box.corner_detail = 16
	_rim_box.set_border_width_all(RIM_WIDTH)
	_rim_box.border_color = accent.lerp(UIStyle.TEXT_PRIMARY, 0.25)


## Brief white wash on the portrait when its owner is hit.
func hit_flash() -> void:
	_flash = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 5.0)
	if _sprite != null:
		var lift := 1.0 + 0.9 * _flash
		_sprite.self_modulate = Color(lift, lift, lift, 1.0)
		if _flash <= 0.0:
			set_process(false)
		return
	var wash := 1.0 + 1.6 * _flash
	if _art:
		_art.modulate = Color(wash, wash, wash, 1.0)
	_rim_box.border_color = accent.lerp(Color.WHITE, 0.25 + 0.7 * _flash)
	if _flash <= 0.0:
		set_process(false)


## Dim + desaturate toward the plate colour, for a downed or inactive character.
func set_dimmed(on: bool) -> void:
	modulate = Color(0.55, 0.55, 0.6, 0.8) if on else Color.WHITE
