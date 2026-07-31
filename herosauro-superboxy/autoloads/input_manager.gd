extends Node
## InputManager (autoload singleton "InputManager")
##
## Thin abstraction over the Input Map so gameplay code never hard-codes action
## names. The game is TWO-PLAYER LOCAL CO-OP, so there are two action sets and
## every query takes the slot it is asking about.
##
## Movement is returned in PAD space, NOT world space: x = strafe right,
## y = forward (away from the camera). PlayerBase rotates it through the camera's
## yaw, so nothing in here needs to know which way the world's axes point.
##
## ## The two sets
##
## Slot 1 keeps the BARE action names ("move_up", "attack", ...) and slot 2 gets
## a "p2_" prefix. That asymmetry is deliberate rather than tidy: `ui_*` and the
## lead-owned capture/playtest harnesses already drive the bare names, and
## renaming slot 1 to "p1_*" would have silently broken every one of them while
## buying nothing but symmetry. `_action()` is the only place either spelling
## exists, so a future rename is a one-line change here.
##
## ## Which hardware drives which hero
##
## Slot 1: keyboard + mouse. WASD, Space, Shift, LMB/Q, RMB/E, arrows to orbit.
## Slot 2: any gamepad (left stick, right stick, A/X/Y/L3), OR the right-hand
##         keyboard cluster IJKL + M/U/O/RShift for a pad-less couch.
##
## No joypad event is bound to slot 1 at all. The common co-op rig is one shared
## keyboard plus one pad, and the pad is the guest's seat — so the FIRST pad
## plugged in has to be player two, not player one. A pad that could also nudge
## player one would make both heroes walk on one stick, which is exactly the bug
## this file exists to prevent.
##
## ## Solo
##
## With `GameManager.player_count == 1` there is only one human, so the lone hero
## reads BOTH sets merged (see `_slots_for`). That is what keeps a solo player on
## a gamepad working after the pad bindings moved to slot 2, and it means
## `GameManager.human_hero` can point at either hero without a re-bind screen.

## Below this the stick is treated as centred. The Input Map deadzone already
## clips each axis; this second gate kills the diagonal creep you get when both
## axes sit just above their individual deadzones.
const STICK_DEADZONE := 0.18

## Action-name prefix per local slot. The only place either spelling lives.
const SLOT_PREFIX := {1: "", 2: "p2_"}


# --- Action naming ---------------------------------------------------------

## Full Input Map name of `action` for `player`. Public so UI can ask the Input
## Map for a slot's real bindings (`InputMap.action_get_events(...)`) instead of
## hard-coding a key glyph next to a control hint.
func action_name(player: int, action: StringName) -> StringName:
	return _action(player, action)


func _action(player: int, action: StringName) -> StringName:
	return StringName(String(SLOT_PREFIX.get(player, "")) + String(action))


## Slots whose bindings drive `player`.
##
## Co-op: exactly its own. Solo: both, because the one human at the machine may
## be holding a pad (slot 2's hardware) while driving hero 1, or sitting at the
## keyboard (slot 1's hardware) while driving hero 2.
func _slots_for(player: int) -> Array:
	if GameManager.player_count <= 1:
		return [1, 2]
	return [player]


## The slot a lone human occupies. Callers that genuinely need a single "the
## player" — the solo orbit camera's look input — ask for this rather than
## assuming 1, so `human_hero = 2` still steers the camera.
func solo_slot() -> int:
	return GameManager.human_hero if GameManager.player_count <= 1 else 1


# --- Movement / look -------------------------------------------------------

## x = strafe right, y = forward. Length is clamped to 1 so a diagonal on the
## keyboard is not faster than a cardinal.
##
## When two sets are merged (solo) the axes are summed before the deadzone, so a
## stick at half deflection is not cancelled by an idle keyboard.
func get_move_vector(player: int) -> Vector2:
	var v := Vector2.ZERO
	for slot in _slots_for(player):
		v += Vector2(
			Input.get_axis(_action(slot, &"move_left"), _action(slot, &"move_right")),
			Input.get_axis(_action(slot, &"move_down"), _action(slot, &"move_up")))
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v.limit_length(1.0)


## x = turn right, y = look up. Right stick and the arrow keys; mouse motion is
## read straight off the event stream by CameraRig.
func get_look_vector(player: int) -> Vector2:
	var v := Vector2.ZERO
	for slot in _slots_for(player):
		v += Vector2(
			Input.get_axis(_action(slot, &"look_left"), _action(slot, &"look_right")),
			Input.get_axis(_action(slot, &"look_down"), _action(slot, &"look_up")))
	if v.length() < STICK_DEADZONE:
		return Vector2.ZERO
	return v.limit_length(1.0)


# --- Buttons ---------------------------------------------------------------

func is_jump_just_pressed(player: int) -> bool:
	return _just_pressed(player, &"jump")


func is_jump_held(player: int) -> bool:
	return _held(player, &"jump")


func is_ability_just_pressed(player: int) -> bool:
	return _just_pressed(player, &"ability")


func is_attack_just_pressed(player: int) -> bool:
	return _just_pressed(player, &"attack")


func is_sprinting(player: int) -> bool:
	return _held(player, &"sprint")


func _just_pressed(player: int, action: StringName) -> bool:
	for slot in _slots_for(player):
		if Input.is_action_just_pressed(_action(slot, action)):
			return true
	return false


func _held(player: int, action: StringName) -> bool:
	for slot in _slots_for(player):
		if Input.is_action_pressed(_action(slot, action)):
			return true
	return false
