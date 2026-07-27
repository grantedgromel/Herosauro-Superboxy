extends SceneTree
## Authoring tool: regenerates the procedural PBR detail maps in this folder.
##
## The project ships zero bitmap textures. Every surface map here is a
## NoiseTexture2D *descriptor* — a few hundred bytes of text that Godot
## rasterises on a worker thread at load time — so the repo stays free of binary
## art while the world still gets real normal / roughness / AO detail.
##
## This script is not part of the running game. Re-run it from the project root
## after tweaking a recipe:
##   godot --headless --path . --script res://assets/textures/generate_detail_maps.gd
##
## Each surface writes two maps:
##   detail_<name>_normal.tres   tangent-space normal, bump-converted from the noise
##   detail_<name>_mask.tres     R = roughness multiplier, G = ambient occlusion
##
## Packing roughness and AO into one texture is deliberate: the scenery samples
## everything triplanar (3 taps per map), so halving the map count halves the
## tap count and keeps both channels in the same cache line.

const OUT_DIR := "res://assets/textures/"
const TEX_SIZE := 256
const BLEND_SKIRT := 0.15   # seamless wrap band — wider hides the tile seam better


func _initialize() -> void:
	for recipe in _recipes():
		_write_pair(recipe)
	quit()


# --- Recipes ----------------------------------------------------------------

## One entry per material family the factory knows about. `rough`/`ao` are
## [low, high] pairs read at noise value 0 and 1 respectively, so a recipe can
## invert either channel simply by ordering the pair backwards (cobble does:
## its low values are the grout lines, which are the rough, dark bits).
func _recipes() -> Array[Dictionary]:
	return [
		# Igneous speckle — dense, high-frequency, barely any large-scale shape.
		{
			"name": "granite",
			"noise": _fbm(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.060, 5, 0.55, 2.2, 1301),
			"bump": 5.0,
			"rough": Vector2(0.74, 1.00),
			"ao": Vector2(1.00, 0.82),
		},
		# Weathered plate: broad corrosion blooms, not grain.
		{
			"name": "iron",
			"noise": _fbm(FastNoiseLite.TYPE_VALUE_CUBIC, 0.030, 4, 0.60, 2.0, 2207),
			"bump": 3.2,
			"rough": Vector2(0.48, 0.96),
			"ao": Vector2(1.00, 0.84),
		},
		# Cell borders become the grout between setts; interiors stay smooth.
		{
			"name": "cobble",
			"noise": _cellular(0.028, 0.90, 3413),
			"bump": 14.0,
			"rough": Vector2(1.00, 0.80),
			"ao": Vector2(0.55, 1.00),
		},
		# Limewash: very low frequency, almost flat, just enough to kill the plastic.
		{
			"name": "plaster",
			"noise": _fbm(FastNoiseLite.TYPE_SIMPLEX, 0.020, 3, 0.50, 2.0, 4517),
			"bump": 1.6,
			"rough": Vector2(0.88, 1.00),
			"ao": Vector2(1.00, 0.93),
		},
		# Barrel roof tiles: rounded cells with a gritty clay surface.
		{
			"name": "terracotta",
			"noise": _cellular(0.050, 0.60, 5623, FastNoiseLite.RETURN_DISTANCE),
			"bump": 7.0,
			"rough": Vector2(0.72, 0.96),
			"ao": Vector2(0.86, 1.00),
		},
		# Grain: ping-pong folding gives parallel bands, domain warp bends them
		# around knots. Closest we get to anisotropic grain without a real map.
		{
			"name": "wood",
			"noise": _grain(0.018, 6733),
			"bump": 3.5,
			"rough": Vector2(0.62, 0.92),
			"ao": Vector2(1.00, 0.88),
		},
	]


# --- Noise builders ---------------------------------------------------------

func _fbm(type: int, freq: float, octaves: int, gain: float, lacunarity: float,
		noise_seed: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.seed = noise_seed
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = lacunarity
	return n


func _cellular(freq: float, jitter: float, noise_seed: int,
		ret: int = FastNoiseLite.RETURN_DISTANCE2_SUB) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.seed = noise_seed
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.cellular_return_type = ret
	n.cellular_jitter = jitter
	return n


func _grain(freq: float, noise_seed: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.seed = noise_seed
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_PING_PONG
	n.fractal_octaves = 3
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	n.fractal_ping_pong_strength = 2.4
	n.domain_warp_enabled = true
	n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	n.domain_warp_amplitude = 28.0
	n.domain_warp_frequency = 0.04
	return n


# --- Texture writers --------------------------------------------------------

func _write_pair(recipe: Dictionary) -> void:
	var name: String = recipe["name"]
	var noise: FastNoiseLite = recipe["noise"]

	var normal := _base_texture()
	normal.as_normal_map = true
	normal.bump_strength = recipe["bump"]
	normal.noise = noise
	_save(normal, "detail_%s_normal.tres" % name)

	# The mask shares the same noise instance intentionally: crevices that bump
	# inward are the same crevices that read rough and occluded.
	var mask := _base_texture()
	mask.color_ramp = _ramp(recipe["rough"], recipe["ao"])
	mask.noise = noise
	_save(mask, "detail_%s_mask.tres" % name)


func _base_texture() -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = TEX_SIZE
	t.height = TEX_SIZE
	t.seamless = true
	t.seamless_blend_skirt = BLEND_SKIRT
	t.generate_mipmaps = true
	t.normalize = true
	return t


## R carries the roughness multiplier, G the AO term. B is unused; both channels
## are data, never colour, so the ramp is authored in linear values.
func _ramp(rough: Vector2, ao: Vector2) -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([
		Color(rough.x, ao.x, 0.0, 1.0),
		Color(rough.y, ao.y, 0.0, 1.0),
	])
	return g


func _save(tex: NoiseTexture2D, file_name: String) -> void:
	var path := OUT_DIR + file_name
	var err := ResourceSaver.save(tex, path)
	if err != OK:
		push_error("Failed to write %s (error %d)" % [path, err])
	else:
		print("wrote ", path)
