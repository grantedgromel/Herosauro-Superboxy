extends Area3D
## Shockwave: the expanding ground ring from Adamastor's slam.
##
## Spawned at the boss's feet into the "spawn_root". Its sphere collider grows
## outward; any player it sweeps over is knocked away once. A translucent brown
## ring mesh scales up to sell the blast, then the whole node frees itself.

@export var damage: int = 20
@export var max_radius: float = 15.0
@export var grow_time: float = 0.5
@export var knockback: float = 14.0

var _shape: SphereShape3D
var _ring: MeshInstance3D
var _hit: Array = []
var _origin: Vector3 = Vector3.ZERO


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2            # players

	_origin = global_position

	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col and col.shape is SphereShape3D:
		_shape = col.shape as SphereShape3D
	else:
		_shape = SphereShape3D.new()
		if col == null:
			col = CollisionShape3D.new()
			col.name = "CollisionShape3D"
			add_child(col)
		col.shape = _shape
	_shape.radius = 0.5

	_ring = get_node_or_null("Ring") as MeshInstance3D
	if _ring:
		_ring.material_override = _ring_material()

	body_entered.connect(_on_body_entered)

	# Catch anyone already standing on top of the boss when it slams.
	for b in get_overlapping_bodies():
		_on_body_entered(b)

	_grow()


func _ring_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 0.30, 0.15, 0.55)   # translucent brown
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.35, 0.15)
	mat.emission_energy_multiplier = 1.5
	return mat


func _grow() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	# Grow the collision sphere outward over the blast.
	tween.tween_method(_set_radius, 0.5, max_radius, grow_time)
	if _ring:
		# The TorusMesh sits flat on the deck; scale it out to ~max_radius.
		var end_scale := max_radius / maxf(0.1, _ring_base_radius())
		_ring.scale = Vector3(1.0, 1.0, 1.0)
		tween.tween_property(_ring, "scale",
			Vector3(end_scale, 1.0, end_scale), grow_time)
		tween.tween_property(_ring.material_override, "albedo_color:a", 0.0, grow_time + 0.2)
	tween.set_parallel(false)
	tween.tween_interval(0.2)
	tween.tween_callback(queue_free)


func _ring_base_radius() -> float:
	if _ring and _ring.mesh is TorusMesh:
		return (_ring.mesh as TorusMesh).outer_radius
	return 1.0


func _set_radius(r: float) -> void:
	if _shape:
		_shape.radius = r


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("players"):
		return
	if _hit.has(body):
		return
	_hit.append(body)
	var here: Vector3 = (body as Node3D).global_position
	var dir := (here - _origin)
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.RIGHT
	dir = dir.normalized()
	body.take_hit(damage, dir * knockback + Vector3.UP * 6.0)
