class_name AgentInput
extends InputSource
## A virtual gamepad. Something else — an AI ally, a scripted playtest, a replay
## — writes intent into it each frame and the hero reads it back exactly as if a
## human were holding a controller.
##
## This is the class that makes "AI ally" cheap. An ally driven through here is
## a PlayerBase like any other: same acceleration, same coyote time, same jump
## arc, same attack windows, same contact shadow. It cannot drift out of sync
## with the player's own feel, because there is only one implementation of that
## feel. The alternative — the one this project had, and deleted — was an
## AllyController that reimplemented locomotion beside PlayerBase's, which is
## why removing co-op meant deleting a class instead of dropping a roster entry.
##
## EDGES ARE CONSUMED ON READ. press_jump() arms an edge that the next
## is_jump_just_pressed() returns and clears, mirroring how Godot's own
## is_action_just_pressed goes false on the following frame. PlayerBase reads
## each edge exactly once per physics frame, so this works — but it does mean a
## second reader in the same frame sees false. If you ever need to inspect the
## state without consuming it, add a peek, do not reorder the reads.

## Written directly by the controller. Both are clamped on read, so a controller
## may hand over an unnormalised vector.
var move := Vector2.ZERO
var look := Vector2.ZERO

## Levels. jump_held drives variable jump height, so an agent that wants a full
## jump must keep it true while rising and release it to cut the arc short.
var jump_held := false
var sprinting := false

var _jump_edge := false
var _ability_edge := false
var _attack_edge := false


## Arm a jump AND hold it. Call release_jump() to cut the arc short; leaving it
## held gives the full height.
func press_jump() -> void:
	_jump_edge = true
	jump_held = true


func release_jump() -> void:
	jump_held = false


func press_ability() -> void:
	_ability_edge = true


func press_attack() -> void:
	_attack_edge = true


## Drop every pending edge and level. Worth calling when an agent is detached or
## the hero dies, so a stale held jump does not survive the respawn.
func clear() -> void:
	move = Vector2.ZERO
	look = Vector2.ZERO
	jump_held = false
	sprinting = false
	_jump_edge = false
	_ability_edge = false
	_attack_edge = false


func get_move_vector() -> Vector2:
	return move.limit_length(1.0)


func get_look_vector() -> Vector2:
	return look.limit_length(1.0)


func is_jump_just_pressed() -> bool:
	var edge := _jump_edge
	_jump_edge = false
	return edge


func is_jump_held() -> bool:
	return jump_held


func is_ability_just_pressed() -> bool:
	var edge := _ability_edge
	_ability_edge = false
	return edge


func is_attack_just_pressed() -> bool:
	var edge := _attack_edge
	_attack_edge = false
	return edge


func is_sprinting() -> bool:
	return sprinting
