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

const RIM_WIDTH := 3

var actor: int = UIStyle.Actor.HEROSAURO
var accent: Color = UIStyle.HERO_GREEN

var _plate: Panel
var _art: TextureRect
var _rim: Panel
var _plate_box := StyleBoxFlat.new()
var _rim_box := StyleBoxFlat.new()
var _flash: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
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
	var inset := float(RIM_WIDTH + 2)
	_art.offset_left = inset
	_art.offset_top = inset
	_art.offset_right = -inset
	_art.offset_bottom = -inset
	add_child(_art)

	_rim = Panel.new()
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rim.add_theme_stylebox_override("panel", _rim_box)
	add_child(_rim)

	_apply(actor)
	set_process(false)


## Point the frame at a character. Pulls the head crop, the accent colour and the
## plate tint from UIStyle so nothing here hard-codes an asset path.
func set_actor(which: int, resolution: int = 256) -> void:
	actor = which
	if is_inside_tree():
		_apply(which, resolution)


func _apply(which: int, resolution: int = 256) -> void:
	accent = UIStyle.actor_color(which)
	if _art:
		_art.texture = UIStyle.portrait_head(which, resolution)

	# Plate: a dark wash tinted toward the character so the line art separates.
	_plate_box.bg_color = UIStyle.SURFACE.lerp(accent, 0.16)
	_plate_box.bg_color.a = 0.92
	_plate_box.set_corner_radius_all(UIStyle.RADIUS_MD)
	_plate_box.corner_detail = 12
	_plate_box.set_border_width_all(0)
	_plate_box.shadow_color = Color(0.01, 0.005, 0.02, 0.55)
	_plate_box.shadow_size = 10
	_plate_box.shadow_offset = Vector2(0, 4)

	_rim_box.bg_color = Color(0, 0, 0, 0)
	_rim_box.set_corner_radius_all(UIStyle.RADIUS_MD)
	_rim_box.corner_detail = 12
	_rim_box.set_border_width_all(RIM_WIDTH)
	_rim_box.border_color = accent.lerp(UIStyle.TEXT_PRIMARY, 0.25)


## Brief white wash on the portrait when its owner is hit.
func hit_flash() -> void:
	_flash = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 5.0)
	var wash := 1.0 + 1.6 * _flash
	if _art:
		_art.modulate = Color(wash, wash, wash, 1.0)
	_rim_box.border_color = accent.lerp(Color.WHITE, 0.25 + 0.7 * _flash)
	if _flash <= 0.0:
		set_process(false)


## Dim + desaturate toward the plate colour, for a downed or inactive character.
func set_dimmed(on: bool) -> void:
	modulate = Color(0.55, 0.55, 0.6, 0.8) if on else Color.WHITE
