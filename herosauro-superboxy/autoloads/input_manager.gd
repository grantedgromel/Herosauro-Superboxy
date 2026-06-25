extends Node
## InputManager (autoload singleton "InputManager")
##
## Thin abstraction over the Input Map so gameplay code never hard-codes action
## names. Player id is 1 (Herosauro) or 2 (Super Boxy). Movement is returned in
## world-plane terms: x = strafe (+X), y = forward/back where -Y means "away
## from the camera" (-Z in world space).

func _prefix(player_id: int) -> String:
	return "p1_" if player_id == 1 else "p2_"


## Returns a Vector2 (x = left/right, y = up/down on the input pad).
## Map to world as: velocity.x = vec.x, velocity.z = vec.y.
func get_move_vector(player_id: int) -> Vector2:
	var p := _prefix(player_id)
	var x := Input.get_axis(p + "move_left", p + "move_right")
	var z := Input.get_axis(p + "move_up", p + "move_down")
	var v := Vector2(x, z)
	if v.length() > 1.0:
		v = v.normalized()
	return v


func is_jump_just_pressed(player_id: int) -> bool:
	return Input.is_action_just_pressed(_prefix(player_id) + "jump")


func is_jump_held(player_id: int) -> bool:
	return Input.is_action_pressed(_prefix(player_id) + "jump")


func is_ability_just_pressed(player_id: int) -> bool:
	return Input.is_action_just_pressed(_prefix(player_id) + "ability")


func is_attack_just_pressed(player_id: int) -> bool:
	return Input.is_action_just_pressed(_prefix(player_id) + "attack")
