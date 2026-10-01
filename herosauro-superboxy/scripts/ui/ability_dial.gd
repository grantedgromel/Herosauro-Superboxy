class_name AbilityDial
extends Control
## Radial cooldown readout for a hero ability.
##
## A cooldown is a countdown, and a ring reads a countdown better than a bar:
## the sweep tells you how long is left without needing a scale to measure
## against. The important state is READY, so that is the one that moves — the
## ring snaps to a full gold circle, throws one expanding pulse, and then keeps a
## slow breathing glow until the ability is spent again.

## Thick enough that the sweep is a moulded band rather than a drawn line. The
## dial is 62 px across in the HUD, so a 6 px ring was 10% of its diameter and
## disappeared against a bright frame; 9 px is a machined collar.
const RING_WIDTH := 8.0
## The ink keyline drawn around the disc and the ring, in the same weight the
## rest of the kit uses.
const KEY_WIDTH := 3.0
const READY_FLASH_TIME := 0.45
## 64 rather than 48: at RING_WIDTH the facets of a 48-segment circle are
## visible on the outer edge of the arc.
const ARC_POINTS := 64

var accent: Color = UIStyle.GOLD
var glyph: String = "E"

var _fraction: float = 1.0
var _shown: float = 1.0
var _ready_flash: float = 0.0
var _was_ready: bool = true
var _pulse: float = 0.0
var _glyph_label: InkText
var _key_label: Label
var _halo: TextureRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_glyph_label = UIStyle.ink(glyph, UIStyle.Scale.SUBHEAD, UIStyle.TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_CENTER)
	_glyph_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glyph_label.offset_bottom = -2.0
	add_child(_glyph_label)
	resized.connect(_fit_glyph)
	_fit_glyph()
	set_process(true)


## The key cap inside the ring is sized off the dial, not off the type scale.
## The ring and its keyline eat a fixed number of pixels, so a glyph at a fixed
## step fits a 68 px dial and collides with the collar on a 48 px one.
func _fit_glyph() -> void:
	if _glyph_label == null:
		return
	var px := maxi(13, roundi(minf(size.x, size.y) * 0.32))
	_glyph_label.add_theme_font_size_override("font_size", px)
	_glyph_label.add_theme_constant_override("outline_size", maxi(3, px / 5))


## `key` is the binding shown inside the ring (e.g. "E"). `tint` colours the
## sweep — usually the hero's colour.
func setup(key: String, tint: Color) -> void:
	glyph = key
	accent = tint
	if _glyph_label:
		_glyph_label.text = key
	queue_redraw()


## 0.0 = just spent, 1.0 = ready. Fed straight from PlayerBase.get_ability_fraction().
func set_fraction(f: float) -> void:
	var v := clampf(f, 0.0, 1.0)
	var now_ready := v >= 0.999
	if now_ready and not _was_ready:
		_ready_flash = 1.0
	_was_ready = now_ready
	_fraction = v
	set_process(true)


func is_ready() -> bool:
	return _was_ready


func _process(delta: float) -> void:
	var moving := false
	var redraw := false
	if absf(_shown - _fraction) > 0.002:
		_shown = lerpf(_shown, _fraction, clampf(1.0 - exp(-18.0 * delta), 0.0, 1.0))
		moving = true
		redraw = true
	elif _shown != _fraction:
		_shown = _fraction
		redraw = true
	if _ready_flash > 0.0:
		_ready_flash = maxf(0.0, _ready_flash - delta / READY_FLASH_TIME)
		moving = true
		redraw = true
	_ensure_halo()
	if _was_ready:
		# Slow breathing halo, the "you can use this" state. It is a stamp
		# whose alpha moves, so breathing costs no redraw at all.
		_pulse += delta
		moving = true
		if _halo != null:
			_halo.visible = true
			_halo.modulate.a = 0.16 + 0.30 * (0.5 + 0.5 * sin(_pulse * 3.4))
	elif _halo != null:
		_halo.visible = false
	if _glyph_label:
		_glyph_label.modulate.a = 1.0 if _was_ready else 0.55
	if redraw:
		queue_redraw()
	if not moving:
		set_process(false)


## Drawn from three IconAtlas stamps (base, full ring, inner face), which are
## consecutive rects on one texture and so ONE draw call while the power is
## ready. Only a recharging sweep (two arcs) and the instant-of-ready flash ring
## are drawn live. The old dial was four filled circles and four AA arcs every
## frame: about ten draw calls on GL Compatibility, twenty with its label.
func _draw() -> void:
	var d := minf(size.x, size.y)
	var r := d * 0.5 - 3.0
	if r <= 4.0:
		return
	var c := size * 0.5
	var box := Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d))
	var ring_r := r - KEY_WIDTH - RING_WIDTH * 0.5 - 2.0

	draw_texture_rect(_stamp(d, "base", accent), box, false)
	if _shown >= 0.999 and _was_ready:
		draw_texture_rect(_stamp(d, "ring", accent), box, false)
	elif _shown > 0.001:
		# Sweep, clockwise from twelve o'clock, plus a lighter band along its
		# outer half (the health bar's sheen trick: a curved surface).
		var start := -PI * 0.5
		var col := accent if _was_ready else accent.lerp(UIStyle.TEXT_DISABLED, 0.45)
		draw_arc(c, ring_r, start, start + TAU * _shown, ARC_POINTS, col, RING_WIDTH, true)
		draw_arc(c, ring_r + RING_WIDTH * 0.26, start, start + TAU * _shown, ARC_POINTS,
			Color(minf(1.0, col.r + 0.26), minf(1.0, col.g + 0.26), minf(1.0, col.b + 0.26), 0.7),
			RING_WIDTH * 0.34, true)
	draw_texture_rect(_stamp(d, "face", accent), box, false)

	if _ready_flash > 0.0:
		# One expanding ring at the instant it comes off cooldown.
		var k := 1.0 - _ready_flash
		draw_arc(c, r + 14.0 * k, 0.0, TAU, ARC_POINTS,
			Color(accent.r, accent.g, accent.b, 0.85 * _ready_flash), 4.0, true)


func _ensure_halo() -> void:
	var d := minf(size.x, size.y)
	if _halo != null or d <= 8.0:
		return
	_halo = IconAtlas.sprite(_stamp(d, "halo", accent), Vector2(d, d))
	_halo.name = "Halo"
	_halo.position = (size - Vector2(d, d)) * 0.5
	_halo.visible = false
	add_child(_halo)
	move_child(_halo, 0)


## One part of the dial at diameter `d`, drawn once into the IconAtlas. The
## geometry is exactly the old live drawing.
static func _stamp(d: float, part: String, tint: Color) -> AtlasTexture:
	var key := "dial:%s:%d:%s" % [part, int(d), tint.to_html() if part in ["ring", "halo"] else ""]
	return IconAtlas.shared().stamp(key, Vector2(d, d), func(root: Control) -> void:
		var art := _DialArt.new()
		art.part = part
		art.tint = tint
		art.size = Vector2(d, d)
		root.add_child(art))


class _DialArt extends Control:
	var part := "base"
	var tint := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 3.0
		var ring_r := r - KEY_WIDTH - RING_WIDTH * 0.5 - 2.0
		match part:
			"base":
				# Drop shadow, the ink keyline, the recessed disc and the empty
				# track sunk into it.
				# Inside the stamp's own cell (r + 4 would cut off at the bottom).
				draw_circle(c + Vector2(0, 3), r - 0.5, UIStyle.SHADOW)
				draw_circle(c, r, UIStyle.KEYLINE)
				draw_circle(c, r - KEY_WIDTH, UIStyle.BASE)
				draw_arc(c, ring_r, 0.0, TAU, ARC_POINTS, UIStyle.BASE.lerp(Color.BLACK, 0.55), RING_WIDTH, true)
			"ring":
				draw_arc(c, ring_r, 0.0, TAU, ARC_POINTS, tint, RING_WIDTH, true)
				draw_arc(c, ring_r + RING_WIDTH * 0.26, 0.0, TAU, ARC_POINTS,
					Color(minf(1.0, tint.r + 0.26), minf(1.0, tint.g + 0.26),
						minf(1.0, tint.b + 0.26)).lerp(tint, 0.3), RING_WIDTH * 0.34, true)
			"face":
				draw_circle(c, ring_r - RING_WIDTH * 0.5 - 1.5, UIStyle.SURFACE_RAISED)
			"halo":
				draw_arc(c, r + 1.5, 0.0, TAU, ARC_POINTS, tint, 3.0, true)
