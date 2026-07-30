class_name DamageNumbers
extends Control
## Floating combat numbers.
##
## The impact contract asks for a UI acknowledgement on every hit. A bar twitching
## in the corner of the screen is not one — the player never learns which of their
## moves is worth using — and a number that pops where the blow landed answers
## that in a single frame for the cost of a Label and a tween.
##
## Every pop is a four-beat move, not a fade:
##   1. PUNCH IN from 40% with a back overshoot, over four frames. The number
##      arrives already too big and settles, which is the same squash-and-stretch
##      contract the characters are held to.
##   2. HANG. It sits still for a moment at full size. A number that starts
##      drifting the instant it appears is unreadable at speed.
##   3. ARC. It rises and drifts sideways on a quartic ease-out, so it decelerates
##      like something thrown.
##   4. FALL AWAY. The fade is paired with a slight shrink, so it recedes rather
##      than dissolving.
##
## Crits get their own treatment throughout: bigger step on the scale, a warmer
## tint, a hard overshoot, and a shadow copy behind them so the number reads as
## embossed metal rather than as coloured text.
##
## DETERMINISM. The scatter runs off a seeded RandomNumberGenerator owned by this
## node, never the global `randf()` family, because the capture gate compares
## frames pixel for pixel — see ARCHITECTURE.md.

const RISE := 74.0
const DRIFT := 40.0
const LIFETIME := 0.86
## How long the number holds still at full size before it starts to travel.
const HANG := 0.14
## Sized to the largest step a crit uses, so the glyph is never clipped by its
## own box and the pivot is always the centre of the number.
const BOX := Vector2(220.0, 68.0)
## Hard cap. A dash through a crowd can queue a lot of these at once and there is
## no reading more than a handful anyway.
const MAX_ACTIVE := 16
## Explicit seed. Any fixed value works; this one is arbitrary and must not
## change, because the stored capture baseline was taken with it.
const SEED := 0x0DA3A6E5

var _active: Array[Label] = []
var _side: int = 1
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = SEED


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Pop `body` at a viewport position. `crit` uses the larger, warmer treatment
## for heavy hits.
func pop(body: String, at: Vector2, color: Color = UIStyle.GOLD, crit: bool = false) -> void:
	_prune()
	if _active.size() >= MAX_ACTIVE:
		var oldest := _active.pop_front() as Label
		if is_instance_valid(oldest):
			oldest.queue_free()

	var scale_step: int = UIStyle.Scale.TITLE if crit else UIStyle.Scale.HEADING
	var l := UIStyle.text(body, scale_step, color, HORIZONTAL_ALIGNMENT_CENTER)
	# Heavier than the type scale's own step. These sit directly on the 3D frame
	# with no plate under them, over whatever the camera is pointing at, so the
	# ink keyline has to do the whole job on its own.
	l.add_theme_constant_override("outline_size",
		maxi(roundi(UIStyle.size_of(scale_step) * 0.24), 7))
	l.size = BOX
	l.pivot_offset = BOX * 0.5
	l.position = at - BOX * 0.5
	add_child(l)
	_active.append(l)

	# The side alternates so a fast combo fans out instead of stacking into a
	# smear; the magnitude is jittered so the fan is not a metronome.
	_side = -_side
	var end := l.position + Vector2(
		DRIFT * _side * _rng.randf_range(0.6, 1.25),
		-RISE * _rng.randf_range(0.85, 1.25))

	var settled := Vector2(1.18, 1.18) if crit else Vector2.ONE
	l.scale = Vector2(0.4, 0.4)
	# Bound to the label, not to this layer: clear_all() frees the labels, and a
	# tween bound to a freed target dies with it instead of erroring on a ghost.
	var t := l.create_tween()
	t.set_parallel(true)
	# Beat 1: the punch. Deliberately over-shot past `settled` and pulled back,
	# which is what makes it read as struck rather than as faded in.
	t.tween_property(l, "scale", settled * 1.35, 0.07).set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT)
	t.chain().tween_property(l, "scale", settled, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Beats 2-4: hang, then arc away while shrinking and fading.
	t.parallel().tween_property(l, "position", end, LIFETIME) \
		.set_delay(HANG).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "scale", settled * 0.72, LIFETIME * 0.5) \
		.set_delay(HANG + LIFETIME * 0.45).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(l, "modulate:a", 0.0, LIFETIME * 0.5) \
		.set_delay(HANG + LIFETIME * 0.45)
	t.chain().tween_callback(func() -> void:
		_active.erase(l)
		l.queue_free())


## Convenience: project a world point through the active 3D camera and pop there.
## Returns false when there is no camera or the point is behind it.
func pop_at_world(body: String, world_pos: Vector3, color: Color = UIStyle.GOLD,
		crit: bool = false) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		return false
	pop(body, cam.unproject_position(world_pos), color, crit)
	return true


func clear_all() -> void:
	for l in _active:
		if is_instance_valid(l):
			l.queue_free()
	_active.clear()
	# Reseeded with the run, so restarting a fight replays the same scatter it
	# did the first time. Without this the numbers would depend on how many hits
	# the previous run happened to land.
	_rng.seed = SEED
	_side = 1


func _prune() -> void:
	var keep: Array[Label] = []
	for l in _active:
		if is_instance_valid(l):
			keep.append(l)
	_active = keep
