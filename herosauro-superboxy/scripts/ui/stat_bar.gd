class_name StatBar
extends Control
## A health bar that behaves like a physical object rather than a rectangle.
##
## Six things separate this from a ProgressBar, and all six are read by the
## player without them noticing:
##   * a SPRING, not a lerp. The fill is integrated as a damped harmonic
##     oscillator, so a hit throws it past the new value and it settles back.
##     A number that eases to its target reads as a variable being animated; one
##     that overshoots and recovers reads as mass being moved.
##   * a CHIP BAR — a pale ghost that hangs at the old value for a beat and then
##     drains down to the new one. It is the fighting-game answer to "how much
##     did that hit actually cost me", and it works at a glance where a number
##     does not.
##   * a PUNCH — the whole widget squashes vertically and springs back on a hit,
##     so damage registers even when the bar barely moves.
##   * a HIT FLASH — a white wash over the fill for ~0.18 s, on top of the punch.
##   * a LOW PULSE — a slow warm throb below LOW_RATIO, so the danger state is
##     visible in peripheral vision.
##   * SEGMENT TICKS — the bar is divided into equal notches, which turns "some
##     health" into a countable quantity.
##
## Drawn by hand rather than themed, because a chip bar needs two independent
## fills over one track and StyleBoxFlat cannot express that — and because the
## punch has to deform the drawn rect without disturbing the layout that placed
## the widget.
##
## Everything here integrates `delta`. Nothing reads the wall clock, so two runs
## of the same fixed-fps capture produce the same bar.

enum Variant { HERO, BOSS }

## How long the ghost hangs at the old value before it starts draining.
const GHOST_HOLD := 0.32
## Ghost drain rate, as a fraction of the full bar per second.
const GHOST_SPEED := 0.55

## Spring constants for the real fill. STIFFNESS sets how fast it gets there,
## DAMPING sets how much it overshoots on the way. These land at a damping ratio
## of about 0.62 — roughly 9% overshoot, settled inside a third of a second.
## Critically damped (ratio 1.0) is the "correct" answer and is exactly the lerp
## this replaced; the overshoot is the entire point.
const STIFFNESS := 460.0
const DAMPING := 26.0
## Below this the spring is considered arrived. Sized so the last fraction of a
## pixel never keeps the widget redrawing forever.
const REST := 0.0008

const FLASH_TIME := 0.18
## Vertical squash at the peak of a hit punch, as a fraction of the bar height.
const PUNCH_SQUASH := 0.30
## Punch decay rate. Fast — the punch is an accent on the hit, not an animation.
const PUNCH_LAMBDA := 9.0
## Ringing frequency of the punch, in radians/second. Two visible bounces.
const PUNCH_HZ := 22.0

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
## Spring velocity of `_shown`, in bar-fractions per second.
var _vel: float = 0.0
var _ghost: float = 1.0
var _hold: float = 0.0
var _flash: float = 0.0
var _punch: float = 0.0
var _punch_phase: float = 0.0
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
	_vel = 0.0
	_ghost = 1.0
	_rage = 0.0
	_rage_target = 0.0
	_rebuild_boxes()
	queue_redraw()


## New value. `hit` drives the flash, the punch and the chip bar; pass false for
## a heal or a silent resync so the bar does not pretend damage happened.
func set_value(v: float, hit: bool = true) -> void:
	var clamped := clampf(v, 0.0, max_value)
	var dropped := clamped < value - EPS * max_value
	var bite := (value - clamped) / max_value
	value = clamped
	if dropped and hit:
		_flash = 1.0
		_hold = GHOST_HOLD
		# Punch scales with the size of the bite, floored so even a chip reads.
		# A hit that always punches the same amount trains the player to ignore it.
		_punch = clampf(0.45 + bite * 4.0, 0.45, 1.0)
		_punch_phase = 0.0
		# Kick the spring downward as well as retargeting it. Without this the
		# overshoot is a function of distance alone, so a 4 damage graze and a 30
		# damage slam settle with the same character.
		_vel -= bite * 2.2
	elif not dropped:
		# Healing: the ghost has nothing to show, so let it catch up immediately.
		_ghost = minf(_ghost, clamped / max_value)
	set_process(true)
	queue_redraw()


## Snap everything to `v` with no animation — for a fresh run.
func reset_to(v: float) -> void:
	value = clampf(v, 0.0, max_value)
	_shown = value / max_value
	_vel = 0.0
	_ghost = _shown
	_hold = 0.0
	_flash = 0.0
	_punch = 0.0
	_punch_phase = 0.0
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
	_punch = 1.0
	_punch_phase = 0.0
	set_process(true)
	queue_redraw()


func fraction() -> float:
	return _shown


func _process(delta: float) -> void:
	var target := value / max_value
	var moving := false

	# Semi-implicit Euler on a damped spring. Velocity is integrated first so the
	# step is stable at the stiffness above even when a frame runs long, which
	# an explicit step at this k is not.
	if absf(_shown - target) > REST or absf(_vel) > REST:
		# Sub-stepped at a fixed 240 Hz. A 460 N/m spring integrated once per
		# frame at 30 fps diverges; capping the sub-step keeps the same visible
		# curve at every frame rate, which the capture gate depends on. The outer
		# clamp bounds the work a single pathological frame (a level load, a
		# breakpoint) can ask for.
		var remaining := minf(delta, 0.25)
		while remaining > 0.0:
			var h := minf(remaining, 1.0 / 240.0)
			_vel += ((target - _shown) * STIFFNESS - _vel * DAMPING) * h
			_shown += _vel * h
			remaining -= h
		_shown = clampf(_shown, 0.0, 1.0)
		moving = true
	else:
		_shown = target
		_vel = 0.0

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

	if _punch > 0.0:
		_punch_phase += delta
		_punch = maxf(0.0, _punch - _punch * PUNCH_LAMBDA * delta - delta * 0.4)
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
	var r := UIStyle.RADIUS_SM + (4 if boss else 1)

	# The bezel is the chunky part. A 4 px keyline on the boss bar and 3 on a
	# hero bar is what makes them read as moulded channels bolted to the panel
	# rather than as coloured rectangles drawn on it.
	_frame_box.bg_color = UIStyle.BASE
	_frame_box.set_corner_radius_all(r + 3)
	_frame_box.corner_detail = 16
	_frame_box.set_border_width_all(4 if boss else 3)
	_frame_box.border_color = UIStyle.KEYLINE
	_frame_box.shadow_color = UIStyle.SHADOW
	_frame_box.shadow_size = 12 if boss else 8
	_frame_box.shadow_offset = Vector2(0, 4)

	# The track's dark top border is a cheap, convincing inner shadow: it reads as
	# the fill sitting down inside a channel rather than painted on a surface.
	_track_box.bg_color = Color(0.031, 0.075, 0.125, 0.98)
	_track_box.set_corner_radius_all(r)
	_track_box.corner_detail = 16
	_track_box.set_border_width_all(0)
	_track_box.border_width_top = 4
	_track_box.border_color = Color(0, 0, 0, 0.55)

	_fill_box.set_corner_radius_all(maxi(2, r - 1))
	_fill_box.corner_detail = 16

	_sheen_box.set_corner_radius_all(maxi(2, r - 1))
	_sheen_box.corner_detail = 16
	_sheen_box.bg_color = Color(1, 1, 1, 0.16)


## The punch, as a scale pair. Squashes vertically and stretches horizontally on
## the same envelope, which is the squash-and-stretch the rest of the game's
## characters use — a bar that only shrank would read as a glitch.
func _punch_scale() -> Vector2:
	if _punch <= 0.0:
		return Vector2.ONE
	var swing := sin(_punch_phase * PUNCH_HZ) * _punch * PUNCH_SQUASH
	return Vector2(1.0 + swing * 0.22, 1.0 - swing)


func _draw() -> void:
	var boss := variant == Variant.BOSS
	var pad := 5.0 if boss else 4.0
	var squash := _punch_scale()
	# Deform about the widget's own centre so a punch never moves the bar's
	# position — the layout that placed it is not consulted and never disturbed.
	var whole := Rect2(Vector2.ZERO, size)
	var centre := size * 0.5
	whole.size = size * squash
	whole.position = centre - whole.size * 0.5
	if whole.size.x < 4.0 or whole.size.y < 4.0:
		return

	draw_style_box(_frame_box, whole)
	var inner := Rect2(whole.position + Vector2(pad, pad), whole.size - Vector2(pad, pad) * 2.0)
	if inner.size.x <= 1.0 or inner.size.y <= 1.0:
		return
	draw_style_box(_track_box, inner)

	var live := fill_color.lerp(UIStyle.BOSS_RAGE, _rage)

	# Chip bar. Hot orange and desaturated so it reads as "was here a moment ago"
	# rather than as a second resource.
	if _ghost > _shown + EPS:
		var g := inner
		g.size.x = inner.size.x * _ghost
		_fill_box.bg_color = Color(1.0, 0.58, 0.26, 0.72)
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
		_fill_box.bg_color = body.darkened(0.18)
		draw_style_box(_fill_box, f)

		var top := f
		top.size.y = f.size.y * 0.48
		_sheen_box.bg_color = Color(
			minf(1.0, body.r + 0.30), minf(1.0, body.g + 0.30), minf(1.0, body.b + 0.30), 0.92)
		draw_style_box(_sheen_box, top)

		# Leading edge. A bright cap on the end of the fill turns the bar into an
		# object with a front face, and it is the part the eye tracks when the
		# spring overshoots.
		if f.size.x > 6.0:
			var cap := Rect2(Vector2(f.end.x - 4.0, f.position.y + 1.0), Vector2(4.0, f.size.y - 2.0))
			draw_rect(cap, Color(1.0, 1.0, 1.0, 0.55))

		if _flash > 0.0:
			_fill_box.bg_color = Color(1, 1, 1, 0.78 * _flash)
			draw_style_box(_fill_box, f)

	_draw_notches(inner)

	# Bright rim along the top edge of the whole widget — the key light landing
	# on the bezel. Warm, because the sun is the warm source; the sky fill is
	# what everything else in the palette is made of.
	draw_line(whole.position + Vector2(pad + 3.0, 2.5),
		whole.position + Vector2(whole.size.x - pad - 3.0, 2.5),
		Color(1.0, 0.94, 0.82, 0.30), 2.0, true)


func _draw_notches(inner: Rect2) -> void:
	if segments > 1:
		var tick := Color(0, 0, 0, 0.48)
		for i in range(1, segments):
			var x := inner.position.x + inner.size.x * (float(i) / float(segments))
			draw_line(Vector2(x, inner.position.y + 1.0),
				Vector2(x, inner.position.y + inner.size.y - 1.0), tick, 3.0)
	if phase_marker > 0.0 and phase_marker < 1.0:
		var px := inner.position.x + inner.size.x * phase_marker
		# Drawn proud of the channel top and bottom so it reads as a machined
		# notch in the bezel, not as a tick painted inside the track.
		draw_line(Vector2(px, inner.position.y - 3.0),
			Vector2(px, inner.position.y + inner.size.y + 3.0),
			UIStyle.KEYLINE, 5.0)
		draw_line(Vector2(px, inner.position.y - 2.0),
			Vector2(px, inner.position.y + inner.size.y + 2.0),
			Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.95), 3.0)
