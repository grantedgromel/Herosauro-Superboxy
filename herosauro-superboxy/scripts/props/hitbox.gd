class_name Hitbox
extends ShapeCast3D
## A damage-dealing volume with an explicit active window.
##
## This replaces the four incompatible hit tests the project grew — a
## distance+dot-product cone, a flat 2D distance, RigidBody3D.body_entered and
## Area3D.body_entered — with one shape query that only runs while armed.
##
## A ShapeCast3D rather than an Area3D on purpose: force_shapecast_update()
## reports overlaps on the same frame the window opens, whereas an Area3D needs
## a physics step to warm its overlap list up and so silently drops every target
## that was ALREADY standing inside the volume when the swing started. That is
## exactly the case a boss slam has to get right.
##
## Leave `target_position` at zero for a stationary volume; set it to the frame's
## displacement to sweep, which is what makes a fast mover tunnel-proof.
##
## Routing, in order: an explicit Hurtbox, then the "players" / "boss" groups,
## then PropBody. `damage == 0` is meaningful — it means "shove, don't hurt", so
## the same component doubles as the boss's push-out volume without firing hit
## reactions, i-frames or the hurt sound.

## Fires once per target per activation, after the hit is actually delivered.
signal landed(target: Node3D)

@export var damage: int = 10
## Horizontal knockback speed handed to the target's take_hit / apply_knockback.
@export var knockback: float = 8.0
## Vertical component of that knockback — the pop that sells a heavy hit.
@export var lift: float = 4.0
## Impulse handed to any PropBody the volume catches. Above a breakable's
## break_impulse this shatters it.
@export var prop_impulse: float = 6.0
## 0 => one hit per target per activation. > 0 => the same target may be hit
## again after this many seconds, which is what a persistent contact volume
## (the giant's body) needs.
@export var rehit_delay: float = 0.0
## Passed to GameManager.damage_boss so the combo counter attributes correctly.
@export var source_player: int = 1

## Knockback points away from this node. Defaults to the hitbox itself; set it
## to the attacker's root so a forward-offset volume still pushes outward from
## the body rather than sideways off the volume's own centre.
var origin_node: Node3D = null

var _timed: bool = false
var _window: float = 0.0
var _clock: float = 0.0
## target instance id -> _clock value before which it may not be hit again.
var _next_ok: Dictionary = {}


func _ready() -> void:
	max_results = 8
	collide_with_bodies = true
	collide_with_areas = true
	enabled = false
	set_physics_process(false)


## Open the window. `duration <= 0` stays open until disarm() — that is the mode
## the persistent contact / push-out volumes use.
func arm(duration: float = 0.0) -> void:
	_next_ok.clear()
	_timed = duration > 0.0
	_window = duration
	enabled = true
	set_physics_process(true)
	# Deliberate: catch anything already inside on the very frame we open.
	_sweep()


func disarm() -> void:
	_timed = false
	_window = 0.0
	enabled = false
	set_physics_process(false)


func is_armed() -> bool:
	return enabled


func _physics_process(delta: float) -> void:
	_clock += delta
	if _timed:
		_window -= delta
		if _window <= 0.0:
			disarm()
			return
	_sweep()


# --- Query -----------------------------------------------------------------

func _sweep() -> void:
	if shape == null or not is_inside_tree():
		return
	force_shapecast_update()
	for i in get_collision_count():
		var node := get_collider(i) as Node3D
		if node == null:
			continue
		var id := node.get_instance_id()
		if _clock < float(_next_ok.get(id, -1.0)):
			continue
		if not _deliver(node):
			continue   # blocked by i-frames: leave the slot open and retry next frame
		# INF, not a huge number: a hitbox armed for a whole fight must never wrap.
		_next_ok[id] = (_clock + rehit_delay) if rehit_delay > 0.0 else INF
		landed.emit(node)


func _deliver(node: Node3D) -> bool:
	var impulse := _impulse_toward(node)

	if node is Hurtbox:
		return (node as Hurtbox).receive(damage, impulse, source_player)

	if node.is_in_group("players"):
		if damage <= 0:
			# Pure shove: apply_knockback skips i-frames, the hurt sound and the
			# zero-damage player_damaged the HUD would otherwise flinch at.
			if node.has_method("apply_knockback"):
				node.apply_knockback(impulse)
				return true
			return false
		if node.has_method("take_hit"):
			return bool(node.take_hit(damage, impulse))
		return false

	if node.is_in_group("boss"):
		if damage <= 0:
			return false
		GameManager.damage_boss(damage, source_player)
		if node.has_method("nudge"):
			node.nudge(impulse.normalized(), knockback * 0.05)
		return true

	if node is PropBody:
		if prop_impulse <= 0.0:
			return false
		var dir := impulse
		dir.y = maxf(dir.y, 0.0)
		if dir.length() < 0.01:
			dir = Vector3.UP
		(node as PropBody).apply_hit_impulse(dir.normalized() * prop_impulse, node.global_position)
		return true

	return false


func _impulse_toward(node: Node3D) -> Vector3:
	var from: Node3D = origin_node if origin_node != null else self
	var dir := node.global_position - from.global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		# Dead-centre overlap: push along the hitbox's own forward so the result
		# is still deterministic instead of a random jitter direction.
		dir = -global_transform.basis.z
		dir.y = 0.0
		if dir.length() < 0.01:
			dir = Vector3.RIGHT
	return dir.normalized() * knockback + Vector3.UP * lift


# --- Construction helpers ---------------------------------------------------
# The boss and its projectiles are assembled in code, so these keep the call
# sites free of five lines of shape boilerplate each.

## Build a sphere hitbox parented to `parent` at a local offset.
static func sphere(parent: Node3D, radius: float, offset: Vector3, mask: int,
		hitbox_name: String = "Hitbox") -> Hitbox:
	var s := SphereShape3D.new()
	s.radius = radius
	return _make(parent, s, offset, mask, hitbox_name)


## Build a box hitbox parented to `parent` at a local offset.
static func box(parent: Node3D, size: Vector3, offset: Vector3, mask: int,
		hitbox_name: String = "Hitbox") -> Hitbox:
	var s := BoxShape3D.new()
	s.size = size
	return _make(parent, s, offset, mask, hitbox_name)


static func _make(parent: Node3D, s: Shape3D, offset: Vector3, mask: int,
		hitbox_name: String) -> Hitbox:
	var hb := Hitbox.new()
	hb.name = hitbox_name
	hb.shape = s
	hb.position = offset
	hb.collision_mask = mask
	hb.origin_node = parent
	parent.add_child(hb)
	return hb
