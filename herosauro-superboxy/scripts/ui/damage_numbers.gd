class_name DamageNumbers
extends Control
## Floating combat numbers.
##
## The fight currently gives no per-hit feedback beyond a bar twitching at the
## top of the screen, which means the player never learns which of their moves
## is worth using. A number that pops where the hit landed answers that in one
## frame, and it costs nothing but a Label and a tween.
##
## Each pop arcs up and sideways, overshoots its scale, then fades. The sideways
## drift alternates so a fast combo fans out instead of stacking into a smear.

const RISE := 62.0
const DRIFT := 34.0
const LIFETIME := 0.78
const BOX := Vector2(200.0, 44.0)
## Hard cap. A dash through a crowd can queue a lot of these at once and there is
## no reading more than a handful anyway.
const MAX_ACTIVE := 16

var _active: Array[Label] = []
var _side: int = 1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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

	var scale_step: int = UIStyle.Scale.HEADING if crit else UIStyle.Scale.READOUT
	var l := UIStyle.text(scale_step, body, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.size = BOX
	l.pivot_offset = BOX * 0.5
	l.position = at - BOX * 0.5
	add_child(l)
	_active.append(l)

	_side = -_side
	var end := l.position + Vector2(DRIFT * _side * randf_range(0.6, 1.2), -RISE * randf_range(0.85, 1.2))

	l.scale = Vector2(0.55, 0.55)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "scale", Vector2(1.22, 1.22) if crit else Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position", end, LIFETIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, LIFETIME * 0.55).set_delay(LIFETIME * 0.45)
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


func _prune() -> void:
	var keep: Array[Label] = []
	for l in _active:
		if is_instance_valid(l):
			keep.append(l)
	_active = keep
