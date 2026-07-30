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
## Each surface writes two maps, and three of the six write a third:
##   detail_<name>_normal.tres   tangent-space normal, bump-converted from the noise
##   detail_<name>_mask.tres     R = roughness multiplier, G = ambient occlusion
##   detail_<name>_albedo.tres   surface-scale COLOUR variation (granite, cobble, iron)
##
## Packing roughness and AO into one texture is deliberate: the scenery samples
## everything triplanar (3 taps per map), so halving the map count halves the
## tap count and keeps both channels in the same cache line.
##
## --- Why three surfaces now carry an albedo map too ------------------------
##
## Round 1 measured the deck cobble contrast-stretched and found every sett the
## identical pinkish-mauve: no stone-to-stone albedo variation, no dirt in the low
## points, no polished crown. The same measurement on the ironwork returned mean
## RGB (11, 16, 27) with a standard deviation of 3 — a black cutout, not a material.
##
## The shared fine layer could not fix either, and it is worth being precise about
## why rather than adding another octave to it. The fine pair is GREYSCALE and it
## tiles at 0.28 m: it delivers grit and damp-patch VALUE variation at arm's length,
## and by four metres it has gone sub-pixel and stopped saying anything at all. What
## was missing is variation at the scale of the object itself — one sett against the
## next, a rust bloom across a whole gusset — and that is a surface-scale map with
## real HUE in it, riding uv1 at the material's own tile size. So it is a third map
## rather than a stronger second one.
##
## These ride BaseMaterial3D.albedo_texture, which multiplies albedo_color, so an
## authored call-site colour still sets the surface's identity and this only
## modulates it. ToonFactory divides that modulation's mean back out (see
## _albedo_map_gain there) so forty call sites' palettes keep meaning what they say.
##
## The other three surfaces (plaster, terracotta, wood) deliberately get none. Three
## more triplanar taps is a real cost, the fine layer is already doing enough on a
## limewashed wall, and nothing in Round 1's findings named them.
##
## Plus one shared pair that is not per-surface:
##   detail_fine_normal.tres     grit, at ~1 mm per texel
##   detail_fine_albedo.tres     patchy albedo modulation, alpha = blend weight
##
## Those two are the RUBRIC's "detail layer still doing work at 0.5 m", and they are
## SHARED rather than per-surface on purpose. A surface map tiled at its authored
## real-world size (2.4 m for granite) is magnified about elevenfold at half a metre
## and resolves as blur; the same map tiled small enough to resolve there tiles
## visibly at twenty. The stack is the only way out, and the second layer of a
## two-layer stack is grit — which is the same grit on stone, iron and plaster, so
## paying for six more of them would buy nothing but texture memory.
##
## The one that needs explaining is detail_fine_albedo's ALPHA. BaseMaterial3D's
## detail pass is
##     detail     = mix(ALBEDO, ALBEDO * detail_tex.rgb, detail_tex.a);
##     detail_nrm = mix(NORMAL_MAP, detail_norm_tex.rgb, detail_tex.a);
## so the albedo map's alpha is the blend weight for BOTH layers, and at alpha = 1
## the fine normal does not stack with the surface normal, it REPLACES it — granite,
## iron and cobble would all end up wearing the same grit and nothing else. 0.55 is
## a half-and-half stack: both scales survive, and each one is dominant at the
## distance where the other has stopped resolving.

const OUT_DIR := "res://assets/textures/"
const TEX_SIZE := 256
const BLEND_SKIRT := 0.15   # seamless wrap band — wider hides the tile seam better

## Blend weight baked into detail_fine_albedo's alpha. See the note above.
const FINE_BLEND := 0.55


func _initialize() -> void:
	for recipe in _recipes():
		_write_pair(recipe)
	_write_fine()
	quit()


# --- Recipes ----------------------------------------------------------------

## One entry per material family the factory knows about. `rough`/`ao` are
## [low, high] pairs read at noise value 0 and 1 respectively.
##
## The noise IS the height field the normal map is bump-converted from, so noise 0
## is the bottom of a crevice and noise 1 is an exposed high point. That fixes the
## direction of both channels and it is not a matter of taste:
##
##   AO must be DARKEST at noise 0. Four of these six recipes had it backwards —
##   granite, iron, plaster and wood all ran (1.00 -> 0.8-ish), i.e. they occluded
##   the exposed faces and left the crevices clean, which is the exact inverse of
##   what ambient occlusion is. Under a raking sun the sun's own shadowing hid it;
##   under a high sun that reaches into the creases, an inverted AO term reads
##   as a surface lit from inside. All four are corrected here and all six are
##   deepened, because AO is now doing more work: ssao_light_affect went up and the
##   key no longer draws the creases on its own.
##
##   ROUGHNESS is per-material. Cobble and terracotta are polished at the high
##   points (feet, rain) and rough in the joints; granite is the opposite, because
##   this granite is two metres above a tidal river and the crevices are where the
##   damp sits — damp stone is a smoother, glossier stone, and that contrast between
##   dry face and wet joint is most of what makes N. Sane's stone read as stone.
##   Every range is widened: the RUBRIC fails "uniform roughness" outright, and a
##   0.74-1.00 multiplier on an 0.92 base is a 0.68-0.92 spread that no one can see.
func _recipes() -> Array[Dictionary]:
	return [
		# Igneous speckle — dense, high-frequency, barely any large-scale shape.
		# River-damp: crevices go glossy (0.52), exposed faces stay fully rough.
		#
		# Its albedo map is a MUCH lower frequency than its normal (0.011 against
		# 0.060): the speckle is already carried by the bump and by the fine layer,
		# and what a granite kerb or a deck bay is missing is the metre-scale
		# difference between one block and the next. Cool damp grey at the bottom of
		# the range, sun-bleached feldspar pink at the top — the two ends of the same
		# stone rather than two different stones.
		{
			"name": "granite",
			"noise": _fbm(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.060, 5, 0.55, 2.2, 1301),
			"bump": 5.0,
			"rough": Vector2(0.52, 1.00),
			"ao": Vector2(0.72, 1.00),
			"albedo_noise": _fbm(FastNoiseLite.TYPE_SIMPLEX, 0.011, 3, 0.55, 2.1, 1307),
			"albedo_ramp": [
				[0.00, Color(0.800, 0.820, 0.860)],
				[0.45, Color(0.940, 0.940, 0.935)],
				[1.00, Color(1.000, 0.990, 0.965)],
			],
		},
		# Weathered plate: broad corrosion blooms, not grain. Intact paint is smooth,
		# a rust bloom is as rough as a surface gets — this is the whole read.
		#
		# The albedo map shares that reading and extends it into colour, which is the
		# half that was missing: noise 0 is intact paint (roughness 0.34, mirrors the
		# dome), noise 1 is a rust bloom (roughness 1.00). So the ramp runs from clean
		# paint through a chalked, hand-polished edge into raw oxide, and because it is
		# the SAME noise instance as the normal and the mask, the rust sits exactly
		# where the surface is rough and proud. That registration is the whole effect —
		# an oxide patch that is smooth, or that is not where the bump is, reads as a
		# stain printed on the paint rather than as the paint having failed.
		{
			"name": "iron",
			"noise": _fbm(FastNoiseLite.TYPE_VALUE_CUBIC, 0.030, 4, 0.60, 2.0, 2207),
			"bump": 3.2,
			"rough": Vector2(0.34, 1.00),
			"ao": Vector2(0.78, 1.00),
			"albedo_ramp": [
				[0.00, Color(1.000, 1.000, 1.000)],
				[0.62, Color(0.990, 0.985, 0.980)],
				[0.84, Color(0.955, 0.885, 0.815)],
				[1.00, Color(0.860, 0.690, 0.575)],
			],
		},
		# Cell borders become the grout between setts; interiors stay smooth.
		# The grout is also where the moss lives, hence the deepest AO of the six.
		#
		# Its albedo map is the one that had to be built differently from the other
		# two, and the reason is worth writing down. A NoiseTexture2D carries ONE noise
		# field, so a map driven off the same DISTANCE2_SUB field as the mask can only
		# ever say "joint" or "not joint" — which is what the AO and roughness channels
		# already say, and it is NOT what the deck was missing. What it was missing is
		# per-sett identity: Round 1 contrast-stretched the calçada and found every
		# stone the identical pinkish-mauve.
		#
		# RETURN_CELL_VALUE is the same cellular field at the same frequency, jitter and
		# seed, so its cells are exactly the mask's cells — but it returns one constant
		# per cell instead of a distance. With CONSTANT gradient interpolation on top,
		# each sett gets a flat colour off the ramp and the boundaries land precisely on
		# the joints the normal map is already grooving. That is a real Portuguese
		# calçada read: dark basalt setts scattered through pale limestone ones, with a
		# few bleached and a few dirt-stained, rather than one stone repeated.
		{
			"name": "cobble",
			"noise": _cellular(0.028, 0.90, 3413),
			"bump": 14.0,
			"rough": Vector2(1.00, 0.72),
			"ao": Vector2(0.45, 1.00),
			"albedo_noise": _cellular(0.028, 0.90, 3413, FastNoiseLite.RETURN_CELL_VALUE),
			"albedo_constant": true,
			# RETUNED against a render, and the render is the only reason these are
			# where they are. The first version ran 0.68 -> 1.00 in sRGB with the dark
			# stop pitched cool, on the reasoning that Portuguese calcada really is
			# black basalt next to white limestone. In the frame it came back as blue
			# and white broken mosaic: a 2.4x albedo ratio between neighbouring setts
			# is a huge signal to begin with, the grade's steepest slope (1.54) sits
			# exactly in the band the deck occupies and expands it further, and a dark
			# sett at a grazing angle is dominated by its own sky reflection, so the
			# dark stops came back far bluer than they were authored.
			#
			# So: 0.82 -> 1.00, a 1.6x ratio rather than 2.4x, and every stop warm-
			# neutral (R >= G >= B) so the only blue on this surface is the blue the
			# sky is actually putting there. Still unmistakably stone-to-stone
			# variation, which is the finding; no longer a mosaic, which was mine.
			"albedo_ramp": [
				[0.00, Color(0.820, 0.815, 0.805)],
				[0.19, Color(1.000, 0.995, 0.985)],
				[0.37, Color(0.895, 0.890, 0.880)],
				[0.55, Color(0.955, 0.950, 0.940)],
				[0.73, Color(0.855, 0.845, 0.830)],
				[0.88, Color(0.935, 0.930, 0.920)],
			],
		},
		# Limewash: very low frequency, almost flat, just enough to kill the plastic.
		{
			"name": "plaster",
			"noise": _fbm(FastNoiseLite.TYPE_SIMPLEX, 0.020, 3, 0.50, 2.0, 4517),
			"bump": 1.6,
			"rough": Vector2(0.80, 1.00),
			"ao": Vector2(0.90, 1.00),
		},
		# Barrel roof tiles: rounded cells with a gritty clay surface. Rain-polished
		# on the crowns, gritty and lichenous in the pan between them.
		{
			"name": "terracotta",
			"noise": _cellular(0.050, 0.60, 5623, FastNoiseLite.RETURN_DISTANCE),
			"bump": 7.0,
			"rough": Vector2(1.00, 0.62),
			"ao": Vector2(0.80, 1.00),
		},
		# Grain: ping-pong folding gives parallel bands, domain warp bends them
		# around knots. Closest we get to anisotropic grain without a real map.
		# Worn pale and smooth where feet land (the raised grain), rough in the
		# split between boards.
		{
			"name": "wood",
			"noise": _grain(0.018, 6733),
			"bump": 3.5,
			"rough": Vector2(1.00, 0.52),
			"ao": Vector2(0.82, 1.00),
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

	if not recipe.has("albedo_ramp"):
		return
	# Surface-scale colour. Defaults to the SAME noise instance as the normal and the
	# mask so the colour lands on the relief; granite and cobble override that with
	# their own field for the reasons written next to their recipes.
	var albedo := _base_texture()
	albedo.noise = recipe.get("albedo_noise", noise)
	albedo.color_ramp = _stops(recipe["albedo_ramp"], recipe.get("albedo_constant", false))
	_save(albedo, "detail_%s_albedo.tres" % name)


## The shared close-range pair. ToonFactory tiles these at ~0.28 m against the
## surface maps' 0.85-3.4 m, so they are the layer still resolving when the camera
## is a hand's width from a baluster.
##
## Two different frequencies on purpose, and the coarser one is the ALBEDO:
##
##   normal — 4-octave simplex at 0.11, i.e. features around 7 px. At a 0.28 m tile
##     over 256 px that is 8 mm: grit, pitting and the tooth of a stone face. Bump
##     kept low (2.2) because it stacks at 55% on top of a surface normal that
##     already has shape, and because the whole point of the fine layer is texture
##     rather than relief.
##   albedo — 3 octaves at 0.032, features around 30 px = 3 cm, i.e. blotches rather
##     than grit. This is the layer the RUBRIC's first material rule is actually
##     about: without it every surface in the game is one flat colour with a bump map
##     on it, which is the single most common way a stylised frame reads as cheap.
##     Damp patches, dirt runs, sun-bleaching, salt bloom — all of them are patchy
##     albedo at roughly this scale, and one multiplicative map delivers all four
##     because the base colour underneath decides which it reads as.
##
## The albedo values are sRGB (the shader's detail sampler carries source_color), and
## they run 0.68 -> 1.00, which is 0.42 -> 1.00 in linear. At the 0.55 blend weight
## that lands as a 0.68-1.00 multiplier on albedo: a 32% swing, deep enough to see
## across a facade and shallow enough that no surface loses its identity.
func _write_fine() -> void:
	var normal := _base_texture()
	normal.as_normal_map = true
	normal.bump_strength = 2.2
	normal.noise = _fbm(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.110, 4, 0.50, 2.1, 7717)
	_save(normal, "detail_fine_normal.tres")

	var albedo := _base_texture()
	albedo.color_ramp = _fine_ramp()
	albedo.noise = _fbm(FastNoiseLite.TYPE_SIMPLEX, 0.032, 3, 0.55, 2.0, 8821)
	_save(albedo, "detail_fine_albedo.tres")


## Greyscale, biased high so the average surface keeps most of its authored value,
## with a long dark tail for the crevices and damp patches. Alpha is constant and is
## the blend weight for the whole detail layer — see the header.
func _fine_ramp() -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	g.offsets = PackedFloat32Array([0.0, 0.40, 1.0])
	g.colors = PackedColorArray([
		Color(0.68, 0.68, 0.68, FINE_BLEND),
		Color(0.88, 0.88, 0.88, FINE_BLEND),
		Color(1.00, 1.00, 1.00, FINE_BLEND),
	])
	return g


## An arbitrary list of [offset, Color] stops as a Gradient.
##
## `constant` switches interpolation to GRADIENT_INTERPOLATE_CONSTANT, which is what
## turns a per-cell noise into flat-coloured tiles with hard boundaries instead of a
## smear across them. Only the cobble wants it; everything else bleeds.
##
## These colours are sRGB. BaseMaterial3D declares texture_albedo with a source_color
## hint, so the sampler linearises on read, exactly as it already does for
## detail_fine_albedo — see the note about that map's own range in _write_fine.
func _stops(stops: Array, constant: bool) -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = (Gradient.GRADIENT_INTERPOLATE_CONSTANT if constant
			else Gradient.GRADIENT_INTERPOLATE_LINEAR)
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in stops:
		offsets.append(float(stop[0]))
		colors.append(stop[1])
	g.offsets = offsets
	g.colors = colors
	return g


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
