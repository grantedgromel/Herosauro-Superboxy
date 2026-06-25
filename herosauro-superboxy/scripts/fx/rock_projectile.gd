extends RigidBody3D
## Rock Projectile: a chunk of bridge masonry Adamastor lobs at the heroes.
##
## Spawned by the boss state machine into the "spawn_root". launch() sets a
## ballistic arc toward a target; on touching a player it deals damage and pops.

@export var damage: int = 18
@export var lifetime: float = 5.0
@export var arc_height: float = 6.0   # extra upward velocity for the lob

const ImpactMarker: GDScript = preload("res://scripts/fx/impact_marker.gd")
const DECK_Y := 2.05   # bridge deck top (y=2) + a hair, so the marker lies on the deck

var _spin: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("projectiles")
	collision_layer = 16          # hazards
	collision_mask = 3            # world (1) + players (2)
	contact_monitor = true
	max_contacts_reported = 4
	gravity_scale = 1.0

	_apply_visuals()

	# Tumble as it flies for a bit of weighty character.
	_spin = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	angular_velocity = _spin

	body_entered.connect(_on_body_entered)

	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(_on_lifetime_timeout)


func _apply_visuals() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		mesh.material_override = ToonFactory.solid(Color(0.38, 0.37, 0.36))


## Lob from the current position toward target_pos with an upward arc.
func launch(target_pos: Vector3) -> void:
	var here := global_position
	var to := target_pos - here
	var horiz := Vector3(to.x, 0.0, to.z)

	# Choose a flight time scaled to the throw distance, then solve the
	# projectile equations for the launch velocity under our world gravity.
	var g := 30.0   # match the world's heavy gravity feel
	var dist := horiz.length()
	var t_flight: float = clampf(0.35 + dist * 0.03, 0.5, 1.6)

	var vel := horiz / t_flight
	# Vertical solve: reach the target height in t_flight, plus an upward bias
	# (arc_height) so the rock visibly lobs over the players' heads.
	vel.y = (to.y + 0.5 * g * t_flight * t_flight) / t_flight + arc_height

	linear_velocity = vel

	# Telegraph the landing spot on the deck for the duration of the flight so the
	# lob is dodgeable on reaction, matching the slam's danger-zone treatment.
	_spawn_landing_marker(target_pos, t_flight)


func _spawn_landing_marker(target_pos: Vector3, flight: float) -> void:
	var parent := get_parent()   # spawn_root (rocks are spawned there by the boss FSM)
	if parent == null:
		return
	var mk: Node3D = ImpactMarker.new()
	mk.setup(3.0, flight)
	parent.add_child(mk)
	mk.global_position = Vector3(target_pos.x, DECK_Y, target_pos.z)


func _on_lifetime_timeout() -> void:
	if is_instance_valid(self):
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		var dir := global_position.direction_to(body.global_position)
		body.take_hit(damage, dir * 6.0 + Vector3.UP * 4.0)
		queue_free()
	elif not body.is_in_group("boss") and not body.is_in_group("projectiles"):
		# Shattered on the deck / world - crumble away shortly after landing.
		var t := get_tree().create_timer(0.3)
		t.timeout.connect(func() -> void:
			if is_instance_valid(self):
				queue_free())
