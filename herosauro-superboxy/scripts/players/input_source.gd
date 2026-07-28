class_name InputSource
extends RefCounted
## One player's intent for one frame.
##
## This exists so that "who is driving this hero" is a property of the hero
## rather than a global fact about the process. PlayerBase used to call the
## InputManager autoload directly, which meant every hero in the scene read the
## same buttons — fine for exactly one hero, and unfixable without touching
## every call site once there were two.
##
## The three subclasses are the whole point:
##
##   DeviceInput  a real human on a keyboard and/or a gamepad
##   AgentInput   a virtual gamepad some other code writes into — an AI ally, a
##                scripted playtest, a replay
##   InputSource  this class, unsubclassed: neutral. A hero that should not be
##                controllable right now (cutscene, stunned, menu open).
##
## Because an AI ally is an InputSource and not a separate controller class,
## adding one does not mean writing a parallel movement path beside PlayerBase's
## — which is exactly what the old AllyController was, and why removing co-op
## meant deleting a class rather than dropping a roster entry.
##
## The base returns neutral for everything, so a subclass only overrides what it
## actually drives.

## x = strafe right, y = forward. PAD space, not world space — PlayerBase turns
## it through the camera yaw. Callers may assume length <= 1.
func get_move_vector() -> Vector2:
	return Vector2.ZERO


## x = turn right, y = look up. Length <= 1.
func get_look_vector() -> Vector2:
	return Vector2.ZERO


## Edge, not level: true on the frame the jump began. Read once per frame —
## AgentInput consumes the edge on read.
func is_jump_just_pressed() -> bool:
	return false


## Level. Releasing early cuts the jump short, so this is read every frame while
## rising.
func is_jump_held() -> bool:
	return false


## Edge. Read once per frame.
func is_ability_just_pressed() -> bool:
	return false


## Edge. Read once per frame.
func is_attack_just_pressed() -> bool:
	return false


## Level.
func is_sprinting() -> bool:
	return false
