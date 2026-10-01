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
## the giant, TARGETS for a level's goblins and dummies) and leave `monitoring`
## off — the Hitbox does the querying, this node only has to be findable.
##
## TARGETS (docs/story/ADAPTATION.md, "Things heroes can hit"): the Hurtbox's
## target implements `take_hit(amount: float, knockback: Vector3) -> void` and
## the target's root joins group "targets". Make the Hurtbox a little larger
## than any solid collider on the same object, so a projectile sweeping toward
## it meets the Hurtbox first.

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
		# A level target's take_hit is void by contract; only an explicit false
		# (a hero-style "refused") means the hit did not count.
		var r: Variant = target.call("take_hit", float(scaled), impulse)
		landed = r == null or bool(r)

	if landed:
		took_hit.emit(scaled, impulse, source_player)
	return landed


func _target() -> Node:
	if not target_path.is_empty():
		return get_node_or_null(target_path)
	return get_parent()


## The Hurtbox a hit on `node` should go through: `node` itself, the Hurtbox of
## the "targets" root it belongs to (a few levels up, e.g. its solid body), or
## null. Used by Dino Energy, whose sweep can meet a target's body.
static func resolve(node: Node) -> Hurtbox:
	var n := node
	for i in 4:
		if n == null:
			return null
		if n is Hurtbox:
			return n as Hurtbox
		if n.is_in_group("targets"):
			return first_in(n)
		n = n.get_parent()
	return null


## First Hurtbox under `root` (inclusive), or null.
static func first_in(root: Node) -> Hurtbox:
	if root is Hurtbox:
		return root as Hurtbox
	var found := root.find_children("*", "Hurtbox", true, false)
	return found[0] as Hurtbox if not found.is_empty() else null


## Hit a "targets" root without a sweep (Boxy Dash, scripted hits): through its
## Hurtbox when it has one, so damage_scale and absorbs still apply, otherwise
## straight to its take_hit.
static func strike(root: Node, amount: int, impulse: Vector3, source_player: int = 1) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	var hb := first_in(root)
	if hb != null:
		return hb.receive(amount, impulse, source_player)
	if root.has_method("take_hit"):
		var r: Variant = root.call("take_hit", float(amount), impulse)
		return r == null or bool(r)
	return false
