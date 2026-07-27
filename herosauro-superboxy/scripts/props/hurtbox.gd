class_name Hurtbox
extends Area3D
## A damage-RECEIVING volume, and the opt-in half of the hit system.
##
## A Hitbox already routes to the "players" / "boss" groups on its own, so an
## entity only needs a Hurtbox when its damageable volume differs from its
## physics body: a boss weak point, a shield that eats the hit, a hitbox that
## should reach a limb sticking out past the capsule.
##
## Put it on the layer the attacking Hitbox masks (PLAYERS for a hero, BOSS for
## the giant) and leave `monitoring` off — the Hitbox does the querying, this
## node only has to be findable.

## Emitted after the hit is forwarded, so an entity can flash / play a sound
## without the Hitbox knowing anything about it.
signal took_hit(amount: int, impulse: Vector3, source_player: int)

## Node the hit is forwarded to. Empty => the parent.
@export var target_path: NodePath
## Scales incoming damage. 2.0 makes this a weak point, 0.0 a pure absorber.
@export var damage_scale: float = 1.0
## Swallow the hit entirely: it still counts as landed (so the attacker's
## hit-once bookkeeping fires) but nothing is forwarded.
@export var absorbs: bool = false


func _ready() -> void:
	# The Hitbox shape-casts for us; monitoring would just be a second broadphase
	# pass over the same volume every frame.
	monitoring = false
	monitorable = true


## Called by Hitbox. Returns true if the hit counted (false lets the attacker
## retry next frame, which is what makes i-frames read correctly).
func receive(amount: int, impulse: Vector3, source_player: int = 1) -> bool:
	var scaled := int(round(float(amount) * damage_scale))
	if absorbs:
		took_hit.emit(0, impulse, source_player)
		return true

	var target := _target()
	var landed := false
	if target == null:
		landed = false
	elif target.is_in_group("players") and target.has_method("take_hit"):
		landed = bool(target.take_hit(scaled, impulse))
	elif target.is_in_group("boss"):
		GameManager.damage_boss(scaled, source_player)
		landed = true
	elif target.has_method("take_hit"):
		landed = bool(target.take_hit(scaled, impulse))

	if landed:
		took_hit.emit(scaled, impulse, source_player)
	return landed


func _target() -> Node:
	if not target_path.is_empty():
		return get_node_or_null(target_path)
	return get_parent()
