class_name StatBar
extends Control
## A health bar that behaves like a physical object rather than a rectangle.
##
## Four things separate this from a ProgressBar, and all four are read by the
## player without them noticing:
##   * a LAG BAR — a pale ghost that hangs at the old value for a beat and then
##     drains down to the new one. It is the fighting-game answer to "how much
##     did that hit actually cost me", and it works at a glance where a number
##     does not.
##   * a HIT FLASH — a white wash over the fill for ~0.18 s, so damage registers
##     even when the bar barely moves.
##   * a LOW PULSE — a slow warm throb below LOW_RATIO, so the danger state is
##     visible in peripheral vision.
##   * SEGMENT TICKS — the bar is divided into equal notches, which turns "some
##     health" into a countable quantity.
##
## Drawn by hand rather than themed, because a lag bar needs two independent
## fills over one track and StyleBoxFlat cannot express that.

enum Variant { HERO, BOSS }

## How long the ghost hangs at the old value before it starts draining.
const GHOST_HOLD := 0.30
## Ghost drain rate, as a fraction of the full bar per second.
const GHOST_SPEED := 0.55
## Exponential smoothing on the real fill. High enough to feel immediate,
## low enough that the two bars visibly separate on a hit.
const FILL_LAMBDA := 22.0
const FLASH_TIME := 0.18
const LOW_RATIO := 0.28
const EPS := 0.0015

var variant: int = Variant.HERO
var max_value: float = 100.0
var value: float = 100.0
var fill_color: Color = UIStyle.HERO_GREEN
## Number of equal notches drawn across the bar. 0 disables them.
var segments: int = 4
## Draws a distinct gold notch at this fraction (e.g. the phase-2 threshold).
## Negative disables it.
var phase_marker: float = -1.0

var _shown: float = 1.0
var _ghost: float = 1.0
var _hold: float = 0.0
var _flash: float = 0.0
var _pulse: float = 0.0
var _rage: float = 0.0          # 0 = normal, 1 = fully recoloured (boss phase 2)
var _rage_target: float = 0.0

# Reused so drawing never allocates.
var _frame_box := StyleBoxFlat.new()
var _track_box := StyleBoxFlat.new()
var _fill_box := StyleBoxFlat.new()
var _sheen_box := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_rebuild_boxes()
	set_process(true)


## Configure in one call. Safe to call before or after the node enters the tree.
func setup(bar_variant: int, maximum: float, color: Color, notches: int = 4) -> void:
	variant = bar_variant
	max_value = maxf(1.0, maximum)
	value = max_value
	fill_color = color
	segments = notches
	_shown = 1.0
	_ghost = 1.0
	_rage = 0.0
	_rage_target = 0.0
	_rebuild_boxes()
	queue_redraw()


## New value. `hit` drives the flash and the lag bar; pass false for a heal or a
## silent resync so the bar does not pretend damage happened.
func set_value(v: float, hit: bool = true) -> void:
	var clamped := clampf(v, 0.0, max_value)
	var dropped := clamped < value - EPS * max_value
	value = clamped
	if dropped and hit:
		_flash = 1.0
		_hold = GHOST_HOLD
	elif not dropped:
		# Healing: the ghost has nothing to show, so let it catch up immediately.
		_ghost = minf(_ghost, clamped / max_value)
	set_process(true)
	queue_redraw()


## Snap everything to `v` with no animation — for a fresh run.
func reset_to(v: float) -> void:
	value = clampf(v, 0.0, max_value)
	_shown = value / max_value
	_ghost = _shown
	_hold = 0.0
	_flash = 0.0
	_rage = 0.0
	_rage_target = 0.0
	_rebuild_boxes()
	queue_redraw()


func set_fill_color(c: Color) -> void:
	fill_color = c
	queue_redraw()


## Boss phase change: cross-fade the fill to the rage colour over ~0.5 s and
## punch a flash through it so the change is impossible to miss.
func enrage(on: bool = true) -> void:
	_rage_target = 1.0 if on else 0.0
	_flash = 1.0
	set_process(true)
	queue_redraw()


func fraction() -> float:
	return _shown


func _process(delta: float) -> void:
	var target := value / max_value
	var moving := false

	if absf(_shown - target) > EPS:
		_shown = lerpf(_shown, target, clampf(1.0 - exp(-FILL_LAMBDA * delta), 0.0, 1.0))
		moving = true
	else:
		_shown = target

	if _ghost > _shown + EPS:
		if _hold > 0.0:
			_hold -= delta
		else:
			_ghost = maxf(_shown, _ghost - GHOST_SPEED * delta)
		moving = true
	else:
		_ghost = _shown

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / FLASH_TIME)
		moving = true

	if absf(_rage - _rage_target) > EPS:
		_rage = move_toward(_rage, _rage_target, delta * 2.0)
		moving = true

	var low := _shown <= LOW_RATIO and _shown > 0.0
	if low:
		_pulse += delta
		moving = true

	if moving:
		queue_redraw()
	else:
		# Nothing is animating; stop burning a redraw every frame until the next
		# signal wakes us. Health bars are static for most of a fight.
		set_process(false)


# --- Drawing -----------------------------------------------------------------

func _rebuild_boxes() -> void:
	var boss := variant == Variant.BOSS
	var r := UIStyle.RADIUS_SM + (3 if boss else 0)

	_frame_box.bg_color = Color(0.05, 0.035, 0.07, 0.90)
	_frame_box.set_corner_radius_all(r + 2)
	_frame_box.corner_detail = 10
	_frame_box.set_border_width_all(2 if boss else 1)
	_frame_box.border_color = UIStyle.HAIRLINE_STRONG if boss else UIStyle.HAIRLINE
	_frame_box.shadow_color = Color(0.01, 0.005, 0.02, 0.55)
	_frame_box.shadow_size = 10 if boss else 6
	_frame_box.shadow_offset = Vector2(0, 3)

	# The track's dark top border is a cheap, convincing inner shadow: it reads as
	# the fill sitting down inside a channel rather than painted on a surface.
	_track_box.bg_color = Color(0.09, 0.06, 0.11, 0.95)
	_track_box.set_corner_radius_all(r)
	_track_box.corner_detail = 10
	_track_box.set_border_width_all(0)
	_track_box.border_width_top = 3
	_track_box.border_color = Color(0, 0, 0, 0.5)

	_fill_box.set_corner_radius_all(r - 1)
	_fill_box.corner_detail = 10

	_sheen_box.set_corner_radius_all(r - 1)
	_sheen_box.corner_detail = 10
	_sheen_box.bg_color = Color(1, 1, 1, 0.16)


func _draw() -> void:
	var boss := variant == Variant.BOSS
	var pad := 4.0 if boss else 3.0
	var whole := Rect2(Vector2.ZERO, size)
	if whole.size.x < 4.0 or whole.size.y < 4.0:
		return

	draw_style_box(_frame_box, whole)
	var inner := Rect2(whole.position + Vector2(pad, pad), whole.size - Vector2(pad, pad) * 2.0)
	if inner.size.x <= 1.0 or inner.size.y <= 1.0:
		return
	draw_style_box(_track_box, inner)

	var live := fill_color.lerp(UIStyle.BOSS_RAGE, _rage)

	# Lag bar. Warm and desaturated so it reads as "was here" rather than a
	# second resource.
	if _ghost > _shown + EPS:
		var g := inner
		g.size.x = inner.size.x * _ghost
		_fill_box.bg_color = Color(1.0, 0.62, 0.34, 0.55)
		draw_style_box(_fill_box, g)

	# Main fill, plus a lighter band across its top so it curves.
	if _shown > 0.001:
		var f := inner
		f.size.x = maxf(inner.size.x * _shown, 3.0)

		var body := live
		if _shown <= LOW_RATIO:
			# Slow warm throb in the danger band.
			var throb := 0.5 + 0.5 * sin(_pulse * 5.2)
			body = live.lerp(UIStyle.WARNING, 0.35 * throb)
		_fill_box.bg_color = body.darkened(0.12)
		draw_style_box(_fill_box, f)

		var top := f
		top.size.y = f.size.y * 0.46
		_sheen_box.bg_color = Color(
			minf(1.0, body.r + 0.28), minf(1.0, body.g + 0.28), minf(1.0, body.b + 0.28), 0.85)
		draw_style_box(_sheen_box, top)

		if _flash > 0.0:
			_fill_box.bg_color = Color(1, 1, 1, 0.70 * _flash)
			draw_style_box(_fill_box, f)

	_draw_notches(inner)

	# Bright rim along the top edge of the whole widget — the golden-hour key
	# light landing on the bezel.
	draw_line(whole.position + Vector2(pad + 2.0, 1.5),
		whole.position + Vector2(whole.size.x - pad - 2.0, 1.5),
		Color(1.0, 0.92, 0.78, 0.18), 1.0, true)


func _draw_notches(inner: Rect2) -> void:
	if segments > 1:
		var tick := Color(0, 0, 0, 0.42)
		for i in range(1, segments):
			var x := inner.position.x + inner.size.x * (float(i) / float(segments))
			draw_line(Vector2(x, inner.position.y + 1.0),
				Vector2(x, inner.position.y + inner.size.y - 1.0), tick, 2.0)
	if phase_marker > 0.0 and phase_marker < 1.0:
		var px := inner.position.x + inner.size.x * phase_marker
		draw_line(Vector2(px, inner.position.y - 1.0),
			Vector2(px, inner.position.y + inner.size.y + 1.0),
			Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.85), 2.0)
