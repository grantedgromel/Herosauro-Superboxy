extends Node
## InputManager (autoload singleton "InputManager")
##
## Thin abstraction over the Input Map so gameplay code never hard-codes action
## names. The game is single-player solo, so there is one action set and no
## per-player prefix.
##
## Movement is returned in PAD space, NOT world space: x = strafe right,
## y = forward (away from the camera). PlayerBase rotates it through the camera's
## yaw, so nothing in here needs to know which way the world's axes point.

## Below this the stick is treated as centred. The Input Map deadzone already
## clips each axis; this second gate kills the diagonal creep you get when both
## axes sit just above their individual deadzones.
const STICK_DEADZONE := 0.18


# --- Movement / look -------------------------------------------------------

## x = strafe right, y = forward. Length is clamped to 1 so a diagonal on the
## keyboard is not faster than a cardinal.
func get_move_vector() -> Vector2:
	var v := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"))
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v.limit_length(1.0)


## x = turn right, y = look up. Right stick and the arrow keys; mouse motion is
## read straight off the event stream by CameraRig.
func get_look_vector() -> Vector2:
	var v := Vector2(
		Input.get_axis("look_left", "look_right"),
		Input.get_axis("look_down", "look_up"))
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v.limit_length(1.0)


# --- Buttons ---------------------------------------------------------------

func is_jump_just_pressed() -> bool:
	return Input.is_action_just_pressed("jump")


func is_jump_held() -> bool:
	return Input.is_action_pressed("jump")


func is_ability_just_pressed() -> bool:
	return Input.is_action_just_pressed("ability")


func is_attack_just_pressed() -> bool:
	return Input.is_action_just_pressed("attack")


func is_sprinting() -> bool:
	return Input.is_action_pressed("sprint")
