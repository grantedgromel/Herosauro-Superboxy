extends RefCounted
## The stadium chapter's shared materials. Built once, cached by name, never
## mutated after creation (ARCHITECTURE rule 7): anything that changes look at
## runtime swaps between two of these instead of editing one.
##
## Most of the chapter is vertex-coloured (vc_baker.gd), so a handful of
## materials covers every character and the whole stadium.

const PitchShader := preload("res://scripts/levels/dragao/pitch.gdshader")
const BallShader := preload("res://scripts/levels/dragao/football.gdshader")
const LedShader := preload("res://scripts/levels/dragao/led_board.gdshader")

static var _cache: Dictionary = {}


static func _cached(key: String) -> Material:
	return _cache.get(key) as Material


static func _store(key: String, m: Material) -> Material:
	_cache[key] = m
	return m


## Characters: clean cartoon plastic with a cool rim, so a green goblin still
## separates from green grass under night lighting.
static func skin() -> StandardMaterial3D:
	var m := _cached("skin") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.52
	m.metallic_specular = 0.45
	m.rim_enabled = true
	m.rim = 0.55
	m.rim_tint = 0.35
	return _store("skin", m) as StandardMaterial3D


## Stadium concrete, seats, boards: rough, with a soft world-space grain so a
## long run of seats is never one flat colour.
static func structure() -> StandardMaterial3D:
	var m := _cached("structure") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.78
	m.albedo_texture = _grain()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return _store("structure", m) as StandardMaterial3D


## The stands and roof: the same, a little dimmer and cooler so the floodlit
## pitch stays the brightest thing in frame and the bowl sits back.
static func structure_far() -> StandardMaterial3D:
	var m := _cached("structure_far") as StandardMaterial3D
	if m:
		return m
	m = structure().duplicate() as StandardMaterial3D
	m.albedo_color = Color(0.74, 0.77, 0.9)
	return _store("structure_far", m) as StandardMaterial3D


## Glossy plastic seats and painted steel (a sharper highlight than concrete).
static func gloss() -> StandardMaterial3D:
	var m := _cached("gloss") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.34
	m.metallic_specular = 0.6
	m.albedo_color = Color(0.8, 0.82, 0.92)
	return _store("gloss", m) as StandardMaterial3D


## Self-lit vertex colour: lamp heads, lit windows, the energy pterodactyl.
static func lit(energy: float = 1.0) -> StandardMaterial3D:
	var key := "lit%.2f" % energy
	var m := _cached(key) as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(energy, energy, energy)
	return _store(key, m) as StandardMaterial3D


## Translucent glowing (the energy pterodactyl, the cup halo).
static func glow_alpha(color: Color, alpha: float) -> StandardMaterial3D:
	var key := "ga%s%.2f" % [color.to_html(false), alpha]
	var m := _cached(key) as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return _store(key, m) as StandardMaterial3D


## Plain unlit colour (no vertex colours): shelf strips, stake rings.
static func flat_lit(color: Color) -> StandardMaterial3D:
	var key := "fl%s" % color.to_html(true)
	var m := _cached(key) as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return _store(key, m) as StandardMaterial3D


## Polished trophy metal. Not fully metallic: under a night sky a pure metal
## reflects the dark and goes black, so it keeps some diffuse and a glint of
## emission to stay the brightest thing on the pitch.
static func trophy() -> StandardMaterial3D:
	var m := _cached("trophy") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = 0.55
	m.roughness = 0.22
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = Color(0.32, 0.28, 0.2)
	m.emission_energy_multiplier = 0.6
	m.rim_enabled = true
	m.rim = 0.8
	m.rim_tint = 0.1
	return _store("trophy", m) as StandardMaterial3D


## Soot: the van after the dragon's puff.
static func soot() -> StandardMaterial3D:
	var m := _cached("soot") as StandardMaterial3D
	if m:
		return m
	m = skin().duplicate() as StandardMaterial3D
	m.albedo_color = Color(0.32, 0.3, 0.3)
	m.roughness = 0.95
	return _store("soot", m) as StandardMaterial3D


static func glass() -> StandardMaterial3D:
	var m := _cached("glass") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.88, 1.0, 0.16)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _store("glass", m) as StandardMaterial3D


static func net() -> StandardMaterial3D:
	var m := _cached("net") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.albedo_texture = _net_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return _store("net", m) as StandardMaterial3D


static func pitch() -> ShaderMaterial:
	var m := _cached("pitch") as ShaderMaterial
	if m:
		return m
	m = ShaderMaterial.new()
	m.shader = PitchShader
	return _store("pitch", m) as ShaderMaterial


static func football() -> ShaderMaterial:
	var m := _cached("ball") as ShaderMaterial
	if m:
		return m
	m = ShaderMaterial.new()
	m.shader = BallShader
	return _store("ball", m) as ShaderMaterial


static func led() -> ShaderMaterial:
	var m := _cached("led") as ShaderMaterial
	if m:
		return m
	m = ShaderMaterial.new()
	m.shader = LedShader
	return _store("led", m) as ShaderMaterial


## Soft round contact shadow (multiplied darkness, no depth write).
static func blob() -> StandardMaterial3D:
	var m := _cached("blob") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 1)
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _radial(64, false)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = -1
	return _store("blob", m) as StandardMaterial3D


## A soft round additive halo (floodlight glare, the cup's beacon).
static func halo(color: Color) -> StandardMaterial3D:
	var key := "halo%s" % color.to_html(true)
	var m := _cached(key) as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.albedo_texture = _radial(64, false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _store(key, m) as StandardMaterial3D


## Particle sprite: a four-point twinkle star, additive, tinted by the
## particle colour (CPUParticles3D colour ramp).
static func sparkle() -> StandardMaterial3D:
	var m := _cached("sparkle") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _star_texture()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _store("sparkle", m) as StandardMaterial3D


## Particle puff (fire and smoke): soft round sprite tinted by particle colour,
## normal alpha blend so smoke can be darker than what is behind it.
static func puff() -> StandardMaterial3D:
	var m := _cached("puff") as StandardMaterial3D
	if m:
		return m
	m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _radial(64, true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _store("puff", m) as StandardMaterial3D


# --- Procedural textures (seeded / analytic; built once) --------------------------

static func _grain() -> Texture2D:
	var key := "tex_grain"
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.seed = 0xD2A6
	n.frequency = 0.06
	n.fractal_octaves = 3
	var img := Image.create(128, 128, true, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := 0.9 + 0.1 * n.get_noise_2d(float(x), float(y))
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func _radial(size: int, soft_edge: bool) -> Texture2D:
	var key := "tex_rad%d%s" % [size, soft_edge]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a) if not soft_edge else pow(a, 0.8)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func _star_texture() -> Texture2D:
	var key := "tex_star"
	if _cache.has(key):
		return _cache[key]
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := float(s - 1) * 0.5
	for y in s:
		for x in s:
			var p := Vector2(float(x) - c, float(y) - c) / c
			var core := clampf(1.0 - p.length() * 2.2, 0.0, 1.0)
			var arm := clampf(1.0 - absf(p.x) * 9.0, 0.0, 1.0) * clampf(1.0 - absf(p.y), 0.0, 1.0)
			arm = maxf(arm, clampf(1.0 - absf(p.y) * 9.0, 0.0, 1.0) * clampf(1.0 - absf(p.x), 0.0, 1.0))
			var a := clampf(core + arm * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func _net_texture() -> Texture2D:
	var key := "tex_net"
	if _cache.has(key):
		return _cache[key]
	var s := 32
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var on := x < 3 or y < 3
			img.set_pixel(x, y, Color(0.95, 0.96, 1.0, 1.0 if on else 0.0))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
