extends CPUParticles3D
## A one-shot spark burst on impact. CPUParticles3D (not GPUParticles3D) so it
## works under the GL Compatibility renderer the web build uses. Spawn it,
## position it, then call play(). Self-frees once the burst finishes.

func _ready() -> void:
	emitting = false
	one_shot = true
	explosiveness = 1.0
	amount = 16
	lifetime = 0.4
	local_coords = false
	direction = Vector3.UP
	spread = 75.0
	initial_velocity_min = 5.0
	initial_velocity_max = 11.0
	gravity = Vector3(0.0, -20.0, 0.0)
	scale_amount_min = 0.16
	scale_amount_max = 0.34

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.42)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.28)
	mat.emission_energy_multiplier = 2.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 0.18)
	bm.material = mat
	mesh = bm


func play() -> void:
	emitting = true
	get_tree().create_timer(lifetime + 0.25).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())
