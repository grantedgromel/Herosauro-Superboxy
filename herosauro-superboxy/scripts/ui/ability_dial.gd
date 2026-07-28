class_name AbilityDial
extends Control
## Radial cooldown readout for a hero ability.
##
## A cooldown is a countdown, and a ring reads a countdown better than a bar:
## the sweep tells you how long is left without needing a scale to measure
## against. The important state is READY, so that is the one that moves — the
## ring snaps to a full gold circle, throws one expanding pulse, and then keeps a
## slow breathing glow until the ability is spent again.

const RING_WIDTH := 6.0
const READY_FLASH_TIME := 0.45
const ARC_POINTS := 48

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
	_glyph_label = UIStyle.text(UIStyle.Scale.SUBHEAD, glyph, UIStyle.TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_CENTER)
	_glyph_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glyph_label.offset_bottom = -2.0
	add_child(_glyph_label)
	set_process(true)


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

	# Drop shadow, then the recessed disc the ring sits in.
	draw_circle(c + Vector2(0, 3), r, Color(0.01, 0.005, 0.02, 0.45))
	draw_circle(c, r, Color(0.07, 0.05, 0.10, 0.94))
	draw_arc(c, r - 0.5, 0.0, TAU, ARC_POINTS, UIStyle.HAIRLINE, 1.0, true)

	var ring_r := r - RING_WIDTH * 0.5 - 2.0

	# Empty track.
	draw_arc(c, ring_r, 0.0, TAU, ARC_POINTS, Color(0, 0, 0, 0.45), RING_WIDTH, true)

	# Sweep, clockwise from twelve o'clock.
	if _shown > 0.001:
		var start := -PI * 0.5
		var col := accent if _was_ready else accent.lerp(UIStyle.TEXT_SECONDARY, 0.38)
		draw_arc(c, ring_r, start, start + TAU * _shown, ARC_POINTS, col, RING_WIDTH, true)

	# Inner face so the glyph has something to sit on.
	draw_circle(c, ring_r - RING_WIDTH * 0.5 - 1.0, Color(0.10, 0.07, 0.14, 0.92))

	if _was_ready:
		# Slow breathing halo — the "you can use this" state.
		var breathe := 0.5 + 0.5 * sin(_pulse * 3.4)
		draw_arc(c, r - 1.0, 0.0, TAU, ARC_POINTS,
			Color(accent.r, accent.g, accent.b, 0.12 + 0.22 * breathe), 2.0, true)

	if _ready_flash > 0.0:
		# One expanding ring at the instant it comes off cooldown.
		var k := 1.0 - _ready_flash
		draw_arc(c, r + 10.0 * k, 0.0, TAU, ARC_POINTS,
			Color(accent.r, accent.g, accent.b, 0.75 * _ready_flash), 3.0, true)
