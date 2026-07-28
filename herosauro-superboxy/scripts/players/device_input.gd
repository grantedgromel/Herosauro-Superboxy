class_name DeviceInput
extends InputSource
## A human on real hardware, reading one named action set out of the Input Map.
##
## The set is chosen by prefix. With the default empty prefix this reads
## `move_left`, `jump`, `attack` and so on — the actions the project has today,
## and byte-for-byte the behaviour the InputManager autoload had before heroes
## carried their own input. A second player would be constructed with "p2_" and
## read `p2_move_left`, `p2_jump`, and so on.
##
## Those p2_ actions do NOT exist in project.godot right now, and adding them is
## a config change, not a code change — which is the point. Until they are
## added, a DeviceInput("p2_") reports neutral and warns once at construction
## rather than throwing on every frame: an unbound second player stands still,
## which is a legible failure, instead of taking the game down.
##
## Splitting by prefix rather than by device id is deliberate. Godot's
## `Input.is_action_*` reads every device at once, so "keyboard for P1, pad for
## P2" cannot be expressed by filtering devices — but it falls straight out of
## two action sets, each with its own bindings. It also lets one player use
## keyboard and pad interchangeably, which is what a solo player expects.

## Below this the stick is treated as centred. The Input Map deadzone already
## clips each axis; this second gate kills the diagonal creep you get when both
## axes sit just above their individual deadzones.
const STICK_DEADZONE := 0.18

## Every action this class reads, unprefixed. Used to validate a prefix up
## front, so the check is one InputMap lookup at construction rather than a
## `has_action` guard on every read.
const ACTIONS: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"look_left", "look_right", "look_up", "look_down",
	"jump", "sprint", "attack", "ability",
]

var _prefix: String
var _bound: bool


func _init(prefix: String = "") -> void:
	_prefix = prefix
	_bound = true
	var missing: Array[String] = []
	for a in ACTIONS:
		if not InputMap.has_action(prefix + a):
			missing.append(prefix + a)
	if not missing.is_empty():
		_bound = false
		push_warning(
			"DeviceInput('%s'): %d action(s) are not in the Input Map, so this "
			% [prefix, missing.size()]
			+ "player will not respond. First missing: %s" % missing[0])


## True when every action this source needs exists. A roster can check it before
## spawning rather than discovering a motionless hero on the deck.
func is_bound() -> bool:
	return _bound


func get_move_vector() -> Vector2:
	if not _bound:
		return Vector2.ZERO
	var v := Vector2(
		Input.get_axis(_prefix + "move_left", _prefix + "move_right"),
		Input.get_axis(_prefix + "move_down", _prefix + "move_up"))
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v.limit_length(1.0)


func get_look_vector() -> Vector2:
	if not _bound:
		return Vector2.ZERO
	var v := Vector2(
		Input.get_axis(_prefix + "look_left", _prefix + "look_right"),
		Input.get_axis(_prefix + "look_down", _prefix + "look_up"))
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v.limit_length(1.0)


func is_jump_just_pressed() -> bool:
	return _bound and Input.is_action_just_pressed(_prefix + "jump")


func is_jump_held() -> bool:
	return _bound and Input.is_action_pressed(_prefix + "jump")


func is_ability_just_pressed() -> bool:
	return _bound and Input.is_action_just_pressed(_prefix + "ability")


func is_attack_just_pressed() -> bool:
	return _bound and Input.is_action_just_pressed(_prefix + "attack")


func is_sprinting() -> bool:
	return _bound and Input.is_action_pressed(_prefix + "sprint")
