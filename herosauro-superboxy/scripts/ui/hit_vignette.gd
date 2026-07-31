class_name HitVignette
extends Control
## Screen-edge feedback for the party's condition.
##
## Three layers over the same radial gradient:
##   SLAM     a hard crimson ring that punches IN from outside the frame and
##            snaps back out. This is the impact-contract acknowledgement: the
##            frame edge is momentarily thicker, which the eye registers as a
##            blow even when it is watching the middle of the screen.
##   FLASH    the softer bloom the slam decays into, scaled by the size of the
##            hit so a graze and a slam do not read the same.
##   SUSTAIN  a slow throb that fades in below a health threshold and stays. It
##            is the ambient "someone is about to die" signal.
##
## AND THEN IT HAD TO COME BACK DOWN. What was here read:
##
##   "OVER DAYLIGHT THIS HAD TO GET LOUDER. The old values were tuned against a
##    dim golden-hour frame; a 34% crimson edge over a blown-out white river
##    simply is not visible."
##
## That was true when it was written and it stopped being true one commit later.
## The white-out was a bug, `56dec3b` fixed it, and nobody came back here — so a
## vignette calibrated to survive a broken frame kept running over a correct one.
## Driven in a real browser at full strength it covered roughly 95% of the screen
## in crimson: not feedback, a red filter you play the game through.
##
## THE GEOMETRY IS THE PART THAT WAS WRONG, not just the alpha. `inner_stop` is
## where the gradient starts ramping, as a fraction of the radial fill's radius,
## and the radius only reaches the frame EDGE — a screen corner sits at 1.41x
## that, well past the end, so it is fully opaque whatever happens in between.
## An inner_stop of 0.36 therefore leaves a clear ellipse about a fifth of the
## screen wide and tints everything outside it. A vignette wants to be clear
## across the whole area a player is actually looking at, which is most of the
## frame; these now hold transparent to two-thirds of the radius and do their
## work in the outer third, which is what the word means.
##
## All three are pure alpha over a gradient texture, so this costs three
## transparent quads and works identically on Forward+ and gl_compatibility.
## Every animation integrates `delta`; nothing reads the wall clock.

const FLASH_IN := 0.04
const FLASH_OUT := 0.46
## Peak alpha for a full-strength hit. 0.80 and 0.95 were the old values, and two
## near-opaque layers stack.
const FLASH_MAX_ALPHA := 0.42
const SLAM_MAX_ALPHA := 0.55
const SUSTAIN_MAX_ALPHA := 0.30
## How far the slam ring grows past the frame at its peak, as a fraction of the
## viewport. Scale, not alpha, is what carries the punch over a bright scene.
const SLAM_OVERSCAN := 0.16
const SLAM_IN := 0.05
const SLAM_OUT := 0.30

var _flash: TextureRect
var _slam: TextureRect
var _sustain: TextureRect
var _sustain_level: float = 0.0
var _pulse: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Back to front. The sustain sits deepest and holds the widest, softest band;
	# the slam is the tightest and the brightest, so it reads on top of it.
	_sustain = _layer(UIStyle.DANGER.darkened(0.18), 0.60)
	_flash = _layer(UIStyle.DANGER, 0.66)
	_slam = _layer(UIStyle.DANGER.lightened(0.15), 0.76)

	set_process(false)


func _layer(tint: Color, inner_stop: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = UIStyle.vignette_texture(tint, inner_stop)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = 0.0
	add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


## One hit. `strength` in 0..1 — scale it by the size of the hit so a chip and a
## slam do not read the same.
func flash(strength: float = 1.0, tint: Color = UIStyle.DANGER) -> void:
	if _flash == null:
		return
	var s := clampf(strength, 0.0, 1.0)
	_retint(_flash, tint)
	_retint(_slam, tint.lightened(0.15))

	var t := create_tween()
	t.tween_property(_flash, "modulate:a", s * FLASH_MAX_ALPHA, FLASH_IN)
	t.tween_property(_flash, "modulate:a", 0.0, FLASH_OUT).set_trans(Tween.TRANS_SINE)

	# The slam. Starts oversized and outside the frame, collapses to fit, then
	# lets go — a ring closing on the player rather than a red wash appearing.
	_slam.pivot_offset = _slam.size * 0.5
	var over := 1.0 + SLAM_OVERSCAN * (0.5 + 0.5 * s)
	_slam.scale = Vector2(over, over)
	var st := create_tween()
	st.set_parallel(true)
	st.tween_property(_slam, "modulate:a", s * SLAM_MAX_ALPHA, SLAM_IN)
	st.tween_property(_slam, "scale", Vector2.ONE, SLAM_IN + SLAM_OUT * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	st.chain().tween_property(_slam, "modulate:a", 0.0, SLAM_OUT) \
		.set_trans(Tween.TRANS_SINE)


## Repaint a layer's gradient in place. The three colour stops are the same
## shape for every tint — transparent centre, transparent hold, opaque edge — so
## only the RGB changes and the texture is never reallocated.
func _retint(layer: TextureRect, tint: Color) -> void:
	var gt := layer.texture as GradientTexture2D
	if gt == null or gt.gradient == null:
		return
	var g := gt.gradient
	g.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	g.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	g.set_color(2, Color(tint.r, tint.g, tint.b, 1.0))


## 0 = healthy (no edge glow), 1 = critical. Drives the sustained throb.
func set_danger(level: float) -> void:
	_sustain_level = clampf(level, 0.0, 1.0)
	set_process(_sustain_level > 0.0)
	if _sustain_level <= 0.0 and _sustain:
		_sustain.modulate.a = 0.0


func _process(delta: float) -> void:
	_pulse += delta
	if _sustain == null:
		return
	# Two beats per cycle rather than one: a heartbeat, not a sine fade. The
	# second, smaller beat is what makes it read as biological and urgent instead
	# of as an animating UI element.
	var beat := sin(_pulse * 3.6)
	var echo := 0.35 * sin(_pulse * 7.2)
	var throb := clampf(0.52 + 0.34 * beat + echo * 0.34, 0.0, 1.0)
	_sustain.modulate.a = SUSTAIN_MAX_ALPHA * _sustain_level * throb
