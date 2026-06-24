class_name ToonFactory
extends RefCounted
## Helper for building consistent toon-shaded materials at runtime.
##
## The character / boss / prop meshes are assembled procedurally in code, so
## rather than hand-author dozens of .tres files every part grabs a material
## from here. Guarantees a uniform cel-shaded + outlined look across the game.

const TOON_SHADER: Shader = preload("res://assets/shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/toon_outline.gdshader")
const OUTLINE_COLOR := Color(0.05, 0.05, 0.08, 1.0)


## A flat toon material with a silhouette outline.
static func solid(color: Color, outline_width: float = 0.025) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo_color", color)
	m.set_shader_parameter("bands", 3)
	m.set_shader_parameter("ambient_floor", 0.32)
	m.set_shader_parameter("rim_amount", 0.18)
	m.set_shader_parameter("rim_color", Color(1, 1, 1, 1))
	m.set_shader_parameter("emission_color", Color(0, 0, 0, 1))
	m.set_shader_parameter("emission_energy", 0.0)
	if outline_width > 0.0:
		m.next_pass = _outline(outline_width)
	return m


## A glowing toon material (emissive), e.g. the Dino Energy projectile.
static func glow(color: Color, energy: float = 3.0, outline_width: float = 0.0) -> ShaderMaterial:
	var m := solid(color, outline_width)
	m.set_shader_parameter("emission_color", color)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("ambient_floor", 0.6)
	return m


static func _outline(width: float) -> ShaderMaterial:
	var o := ShaderMaterial.new()
	o.shader = OUTLINE_SHADER
	o.set_shader_parameter("outline_color", OUTLINE_COLOR)
	o.set_shader_parameter("outline_width", width)
	return o
