extends Node

func _ready() -> void:
	var p := CPUParticles3D.new()
	add_child(p)
	print("no-mesh warnings: ", p._get_configuration_warnings())
	p.mesh = SphereMesh.new()
	print("with-mesh warnings: ", p._get_configuration_warnings())
	get_tree().quit()
