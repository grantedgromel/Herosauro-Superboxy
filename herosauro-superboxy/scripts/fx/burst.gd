class_name Burst
extends Node
## One-shot particle bursts via CPUParticles3D (CPU-driven -> GL Compatibility /
## web safe, unlike GPUParticles3D). Static helpers spawn a short burst into the
## "spawn_root" and free it when finished. Used for hit sparks and landing dust.

const _SPARK := Color(1.0, 0.86, 0.34)


## Bright spark burst at an impact point (hero hits, dash bonk, projectile hit).
static func hit(host: Node, pos: Vector3, color: Color = _SPARK) -> void:
	_burst(host, pos, 16, 0.4, 4.0, 9.0, 0.16, color, Vector3(0, -16, 0), 180.0)


## Soft dust puff at a landing point.
static func dust(host: Node, pos: Vector3) -> void:
	_burst(host, pos, 10, 0.5, 1.4, 3.2, 0.22, Color(0.82, 0.77, 0.68), Vector3(0, -2, 0), 70.0)


static func _burst(host: Node, pos: Vector3, amount: int, lifetime: float,
		vmin: float, vmax: float, psize: float, color: Color, gravity: Vector3, spread: float) -> void:
	if host == null or not host.is_inside_tree():
		return
	var root: Node = host.get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = host.get_tree().current_scene
	if root == null:
		return

	var p := CPUParticles3D.new()
	root.add_child(p)
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = gravity
	p.scale_amount_min = psize * 0.5
	p.scale_amount_max = psize
	p.color = color

	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mesh.material = mat
	p.mesh = mesh

	p.emitting = true
	var timer := host.get_tree().create_timer(lifetime + 0.25)
	timer.timeout.connect(p.queue_free)
