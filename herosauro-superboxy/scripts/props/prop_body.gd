class_name PropBody
extends RigidBody3D
## Base for the arena's interactive props: port-wine barrels, crates, loose
## masonry. Real Jolt rigid bodies the heroes and the giant can knock around.
##
## Three things it takes care of that a bare RigidBody3D does not:
##
##  * Layering. Props sit on their own layer and mask WORLD | PROPS | PLAYERS.
##    They deliberately do NOT mask BOSS: a 45 kg barrel must never body-block a
##    nine-metre giant. The boss shoves and shatters them from its own hitbox.
##  * Sleeping. can_sleep plus a little damping so a settled prop leaves the
##    solver entirely and an untouched arena costs nothing.
##  * A kicker volume. CharacterBody3D.move_and_slide() does not push rigid
##    bodies — the engine only depenetrates them, which reads as a barrel
##    quivering rather than rolling. The kicker converts the toucher's approach
##    speed into a real force, so props respond without the player controller
##    (owned by another stream) needing to know props exist. It self-disables
##    the moment nothing is touching.

## Which ToonFactory surface the prop wears. Meshes in the "prop_trim" group get
## `trim_color` iron instead, which is how a barrel gets its hoops.
@export_enum("wood", "stone", "iron", "cobble") var surface: String = "wood"
@export var tint: Color = Color(0.36, 0.24, 0.14)
@export var trim_color: Color = Color(0.26, 0.27, 0.30)

@export_group("Physics")
@export var prop_mass: float = 40.0
@export var prop_friction: float = 0.85
@export var prop_bounce: float = 0.05
## Scales how hard a walking character shoves this prop. 0 disables the kicker.
@export var kick_strength: float = 1.0

## Anything that falls off the bridge is gone; the Douro surface is at y = -15
## and has no collider, so without this they fall forever.
const CULL_Y := -6.0
## Extra reach on the kicker volume, roughly a hero's capsule radius.
const KICK_MARGIN := 0.45
## Acceleration (m/s^2) applied per m/s of approach speed. Self-limiting: once
## the prop matches the pusher, approach hits zero and the force stops.
const KICK_GAIN := 4.5
const KICK_MAX_APPROACH := 9.0

var _kicker: Area3D = null
var _touching: Array[Node3D] = []


func _ready() -> void:
	add_to_group("props")
	collision_layer = PhysicsLayers.PROPS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PROPS | PhysicsLayers.PLAYERS

	mass = prop_mass
	var pm := PhysicsMaterial.new()
	pm.friction = prop_friction
	pm.bounce = prop_bounce
	physics_material_override = pm

	can_sleep = true
	# Props are slow and chunky; CCD is for the projectiles, not for these.
	continuous_cd = false
	# Enough damping that a shoved crate actually settles and sleeps instead of
	# creeping across the deck forever.
	linear_damp = 0.08
	angular_damp = 0.55

	_apply_materials()
	if kick_strength > 0.0:
		_build_kicker()

	sleeping_state_changed.connect(_on_sleep_changed)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if global_position.y < CULL_Y:
		queue_free()
		return
	_apply_kicks()
	if sleeping and _touching.is_empty():
		set_physics_process(false)


# --- Damage / impulse entry point -------------------------------------------

## The one way anything external moves a prop. `at_global` is where the blow
## landed, so an off-centre hit spins the prop.
func apply_hit_impulse(impulse: Vector3, at_global: Vector3 = Vector3.INF) -> void:
	sleeping = false
	set_physics_process(true)
	var offset := Vector3.ZERO
	if at_global != Vector3.INF:
		# Clamp the lever arm: a contact reported a body-length away turns a
		# shove into a helicopter.
		offset = (at_global - global_position).limit_length(0.5)
	apply_impulse(impulse, offset)
	_on_impact(impulse.length())


## Overridden by BreakableProp. `strength` is the impulse magnitude in N*s.
func _on_impact(_strength: float) -> void:
	pass


# --- Kicker -----------------------------------------------------------------

func _build_kicker() -> void:
	_kicker = Area3D.new()
	_kicker.name = "Kicker"
	_kicker.collision_layer = 0
	_kicker.collision_mask = PhysicsLayers.PLAYERS
	_kicker.monitorable = false
	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = _kick_radius()
	col.shape = s
	_kicker.add_child(col)
	add_child(_kicker)
	_kicker.body_entered.connect(_on_kicker_entered)
	_kicker.body_exited.connect(_on_kicker_exited)


func _on_kicker_entered(body: Node3D) -> void:
	if body in _touching:
		return
	_touching.append(body)
	sleeping = false
	set_physics_process(true)


func _on_kicker_exited(body: Node3D) -> void:
	_touching.erase(body)


func _apply_kicks() -> void:
	if _touching.is_empty():
		return
	for i in range(_touching.size() - 1, -1, -1):
		var body := _touching[i]
		if not is_instance_valid(body):
			_touching.remove_at(i)
			continue
		var v := Vector3.ZERO
		if body is CharacterBody3D:
			v = (body as CharacterBody3D).velocity
		v.y = 0.0
		var away := global_position - body.global_position
		away.y = 0.0
		if away.length() < 0.01:
			continue
		var n := away.normalized()
		var approach := clampf(v.dot(n), 0.0, KICK_MAX_APPROACH)
		if approach < 0.6:
			continue
		# Push slightly above the centre of mass so a crate tips as it slides.
		apply_force(n * mass * approach * KICK_GAIN * kick_strength, Vector3(0.0, 0.15, 0.0))


func _on_sleep_changed() -> void:
	if not sleeping:
		set_physics_process(true)


func _kick_radius() -> float:
	var s := _own_shape()
	if s is SphereShape3D:
		return (s as SphereShape3D).radius + KICK_MARGIN
	if s is BoxShape3D:
		return ((s as BoxShape3D).size * 0.5).length() + KICK_MARGIN
	if s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		return maxf(cyl.radius, cyl.height * 0.5) + KICK_MARGIN
	if s is CapsuleShape3D:
		return (s as CapsuleShape3D).height * 0.5 + KICK_MARGIN
	return 0.9


func _own_shape() -> Shape3D:
	for c in get_children():
		if c is CollisionShape3D:
			return (c as CollisionShape3D).shape
	return null


# --- Look -------------------------------------------------------------------

func _apply_materials() -> void:
	var body_mat := _surface_material()
	var trim_mat := ToonFactory.iron(trim_color, 0.6, 0.65, 0.5)
	for mi in _meshes(self):
		mi.material_override = trim_mat if mi.is_in_group("prop_trim") else body_mat


func _surface_material() -> StandardMaterial3D:
	match surface:
		"stone":
			return ToonFactory.stone(tint, 1.2)
		"iron":
			return ToonFactory.iron(tint, 0.9)
		"cobble":
			return ToonFactory.cobblestone(tint, 0.8)
		_:
			return ToonFactory.wood(tint, 0.55)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
