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
var _glyph_label: Label
var _key_label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_glyph_label = UIStyle.text(glyph, UIStyle.Scale.SUBHEAD, UIStyle.TEXT_PRIMARY,
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
	if absf(_shown - _fraction) > 0.002:
		_shown = lerpf(_shown, _fraction, clampf(1.0 - exp(-18.0 * delta), 0.0, 1.0))
		moving = true
	else:
		_shown = _fraction
	if _ready_flash > 0.0:
		_ready_flash = maxf(0.0, _ready_flash - delta / READY_FLASH_TIME)
		moving = true
	if _was_ready:
		_pulse += delta
		moving = true
	if _glyph_label:
		_glyph_label.modulate.a = 1.0 if _was_ready else 0.55
	if moving:
		queue_redraw()
	else:
		set_process(false)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 3.0
	if r <= 4.0:
		return

	# Drop shadow, then the ink keyline, then the recessed disc the ring sits in.
	# The keyline is drawn as a filled circle UNDER the face rather than as an
	# arc over it, so the outer edge stays perfectly round at any radius.
	draw_circle(c + Vector2(0, 4), r, UIStyle.SHADOW)
	draw_circle(c, r, UIStyle.KEYLINE)
	draw_circle(c, r - KEY_WIDTH, UIStyle.BASE)

	var ring_r := r - KEY_WIDTH - RING_WIDTH * 0.5 - 2.0

	# Empty track, sunk into the face.
	draw_arc(c, ring_r, 0.0, TAU, ARC_POINTS, Color(0, 0, 0, 0.55), RING_WIDTH, true)

	# Sweep, clockwise from twelve o'clock.
	if _shown > 0.001:
		var start := -PI * 0.5
		var col := accent if _was_ready else accent.lerp(UIStyle.TEXT_DISABLED, 0.45)
		draw_arc(c, ring_r, start, start + TAU * _shown, ARC_POINTS, col, RING_WIDTH, true)
		# A lighter band along the outer half of the sweep, the same trick the
		# health bar's sheen uses: it turns a flat arc into a curved surface.
		draw_arc(c, ring_r + RING_WIDTH * 0.26, start, start + TAU * _shown, ARC_POINTS,
			Color(minf(1.0, col.r + 0.26), minf(1.0, col.g + 0.26), minf(1.0, col.b + 0.26), 0.7),
			RING_WIDTH * 0.34, true)

	# Inner face so the glyph has something to sit on.
	draw_circle(c, ring_r - RING_WIDTH * 0.5 - 1.5, UIStyle.SURFACE_RAISED)

	if _was_ready:
		# Slow breathing halo — the "you can use this" state.
		var breathe := 0.5 + 0.5 * sin(_pulse * 3.4)
		draw_arc(c, r + 2.0, 0.0, TAU, ARC_POINTS,
			Color(accent.r, accent.g, accent.b, 0.16 + 0.30 * breathe), 3.0, true)

	if _ready_flash > 0.0:
		# One expanding ring at the instant it comes off cooldown.
		var k := 1.0 - _ready_flash
		draw_arc(c, r + 14.0 * k, 0.0, TAU, ARC_POINTS,
			Color(accent.r, accent.g, accent.b, 0.85 * _ready_flash), 4.0, true)
