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
## Each surface writes two maps, and four of the six write a third:
##   detail_<name>_normal.tres   tangent-space normal, bump-converted from the noise
##   detail_<name>_mask.tres     R = roughness multiplier, G = ambient occlusion
##   detail_<name>_albedo.tres   surface-scale COLOUR variation
##                               (granite, iron, cobble, plaster)
##
## Packing roughness and AO into one texture is deliberate: the scenery samples
## everything triplanar (3 taps per map), so halving the map count halves the
## tap count and keeps both channels in the same cache line.
##
## --- Why four surfaces carry an albedo map, and why hue is the point --------
##
## Round 1 measured the deck cobble contrast-stretched and found every sett the
## identical pinkish-mauve: no stone-to-stone albedo variation, no dirt in the low
## points, no polished crown. The same measurement on the ironwork returned mean
## RGB (11, 16, 27) with a standard deviation of 3 — a black cutout, not a material.
##
## The shared fine layer could not fix either. It tiles at 0.28 m: it delivers grit
## and damp-patch variation at arm's length, and by four metres it has gone sub-pixel
## and stopped saying anything at all. What was missing is variation at the scale of
## the object itself — one sett against the next, a rust bloom across a whole gusset —
## riding uv1 at the material's own tile size. So it is a third map rather than a
## stronger second one.
##
## Round 2 shipped those maps and measured what was still wrong, which is the finding
## this round is spent on: five stone surfaces across two frames came back with
## channel-deviation correlations of 0.88-0.995. Every one was one flat albedo
## multiplied by a grey mask, because every ramp was MONOTONE — all three channels
## rising or falling together, so the variation was luminance and never became colour.
## The surfaces carried plenty of variance (granite sd 19.6, walkway sd 40.6) and
## still read as cardboard. More grunge could not have helped and would have measured
## as progress; see the note on _report() below for the arithmetic.
##
## Every stone-family ramp here is now non-monotone. Iron alone is untouched, and the
## _report() line explains why it is right that it is.
##
## These ride BaseMaterial3D.albedo_texture, which multiplies albedo_color, so an
## authored call-site colour still sets the surface's identity and this only
## modulates it. ToonFactory divides that modulation's mean back out PER CHANNEL (see
## _albedo_map_gain there) so forty call sites' palettes keep meaning what they say
## even though the maps now average different amounts of red, green and blue.
##
## Terracotta and wood still get none. Three more triplanar taps is a real cost and
## neither has been named in a finding yet.
##
## Plus one shared pair that is not per-surface:
##   detail_fine_normal.tres     grit, at ~1 mm per texel
##   detail_fine_albedo.tres     patchy albedo modulation, alpha = blend weight.
##                               No longer greyscale — see _fine_ramp() for the two
##                               constraints a SHARED chromatic layer has to meet.
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
	var recipes := _recipes()
	for recipe in recipes:
		_write_pair(recipe)
	_write_fine()
	_report(recipes)
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
		# difference between one block and the next.
		#
		# ROUND 3: the ramp is now NON-MONOTONE, and that is the entire change.
		# What it was, and it reads perfectly sensibly:
		#     0.00 (0.800, 0.820, 0.860)   cool damp grey
		#     0.45 (0.940, 0.940, 0.935)
		#     1.00 (1.000, 0.990, 0.965)   sun-bleached feldspar
		# and it measured r-g +1.000, r-b +0.999 — see _report() at the end of a run.
		# Round 2 measured the same thing in the render, on every stone surface in the
		# game: cobbles 0.945/0.894, granite 0.987/0.882, kerb 0.995/0.975, parapet
		# 0.994/0.964, walkway 0.995/0.952, and called it "one flat albedo multiplied
		# by a grey mask". That reading is exactly right.
		#
		# The trap is arithmetic rather than artistic, which is why widening the hue
		# swing between the end stops — the obvious fix, and the one the old ramp
		# already IS — cannot move it. A NoiseTexture2D carries ONE scalar field, so
		# R, G and B are all functions of the same t; if all three are MONOTONE in t
		# their correlation is ~1 however far apart the ends are pitched. Only a ramp
		# whose channels REVERSE against each other decorrelates.
		#
		# So value and hue are separate terms now. Value still means weathering — the
		# stop luminances climb 0.72 -> 0.88, monotonically, and the normal and the
		# mask stay registered to that. Hue no longer rides along, because in real
		# granite it does not:
		# brightness says how weathered a patch is, hue says which mineral is showing,
		# and biotite, hornblende, quartz and feldspar are not ordered by brightness.
		# Concretely the warm/cool axis flips at EVERY stop (+-0.086 linear) and the
		# green/magenta axis every two (+-0.038), against one rising pass of value:
		# three near-orthogonal terms squeezed out of one scalar field. Read as stone,
		# in order: iron-stained dark granite, damp blue-grey, pink feldspar, quartz
		# blue-white, warm bleached, lichen grey-green, hot bleached feldspar.
		#
		# The value RANGE came in deliberately, 0.60-1.00 linear down to 0.69-0.89 —
		# half the monochrome swing, spent on hue instead. That is the trade Round 3
		# was briefed to make: this surface already carried sd=19.6 in the render and
		# still read as cardboard, because monochrome variance is not material
		# information. Nor is anything actually lost by it. The DELIVERED per-channel
		# standard deviation went UP, (0.073, 0.062, 0.039) to (0.074, 0.063, 0.071),
		# because the hue terms add variance to each channel while cancelling between
		# them — the map varies more than it used to and correlates less. And the
		# normal, the mask's 0.52-1.00 roughness and 0.72-1.00 AO, and the fine
		# layer's 0.65-1.00 all still carry value variation, none of which can ever
		# carry colour.
		#
		# STOP OFFSETS ARE THE FIELD'S OWN QUANTILES, not even sixths. A normalised
		# fBm field is bell-shaped: its deciles run 0.00 .26 .33 .40 .45 .51 .56 .62
		# .67 .75 1.00, so 80% of texels sit inside t = 0.26..0.75 and stops spaced
		# evenly across 0..1 deliver only the three in the middle. 0/.31/.42/.51/.60/
		# .70/1.00 are the k/6 quantiles of that measured histogram, so each segment
		# covers a sixth of the surface and the whole ramp actually reaches the frame.
		{
			"name": "granite",
			"noise": _fbm(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.060, 5, 0.55, 2.2, 1301),
			"bump": 5.0,
			"rough": Vector2(0.52, 1.00),
			"ao": Vector2(0.72, 1.00),
			"albedo_noise": _fbm(FastNoiseLite.TYPE_SIMPLEX, 0.011, 3, 0.55, 2.1, 1307),
			"albedo_ramp": [
				[0.00, Color(0.884, 0.869, 0.789)],
				[0.31, Color(0.808, 0.886, 0.901)],
				[0.42, Color(0.936, 0.863, 0.848)],
				[0.51, Color(0.865, 0.881, 0.951)],
				[0.60, Color(0.949, 0.935, 0.862)],
				[0.70, Color(0.880, 0.950, 0.964)],
				[1.00, Color(0.996, 0.929, 0.915)],
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
			# SIX STONES, laid out as a 3 x 2 factorial: three value levels crossed
			# with warm and cool. That is not a decorative choice, it is the only
			# arrangement that makes the value axis and the warm-cool axis exactly
			# orthogonal over an equal-share cell field — [-1,-1,0,0,+1,+1] dotted with
			# [+1,-1,+1,-1,+1,-1] is zero — which is what drives the channel
			# correlation to nothing. Measured delivery: r-g +0.52, r-b +0.04, from
			# +1.000 / +0.999 before. Read as stone: dark warm (oil-stained basalt),
			# dark cool (fresh blue basalt), mid warm (buff granite), mid cool (grey
			# granite), pale warm (cream limestone), pale cool (white limestone).
			#
			# THE VALUE RATIO IS DELIBERATELY LOWER THAN ROUND 2'S, and Round 2's own
			# retune is why. Its first attempt ran 0.68 -> 1.00 sRGB with the dark stop
			# pitched cool, on the reasoning that Portuguese calcada really is black
			# basalt beside white limestone, and in the frame that came back as a blue
			# and white broken mosaic: a 2.4x albedo ratio between neighbouring setts
			# is a huge signal to begin with, the grade's steepest slope (1.54) sits in
			# the band the deck occupies and expands it further, and a dark sett at a
			# grazing angle is dominated by its own sky reflection, so the dark stops
			# rendered far bluer than authored. Round 2 pulled it back to 1.6x and made
			# every stop warm-neutral, which fixed the mosaic and produced the flat
			# monochrome this round has to undo.
			#
			# So the ratio comes down again, to 1.5x (0.632 -> 0.947 linear), and the
			# room that frees goes into hue instead: +-0.055 to +-0.080 linear on the
			# warm-cool axis, tapered so the DARK pair carries the least of it. That
			# taper is the direct answer to Round 2's measured failure — a dark sett is
			# the one that picks up sky, so it is the one that must not also be
			# authored cool. Tapering does not cost the orthogonality; the dot product
			# above is zero for any per-level amplitude.
			#
			# NO CALCADA MOSAIC. The black-and-white geometric paving is Porto's
			# signature and it is not being built here, for three reasons written out
			# in the pass report: it is a laid GEOMETRIC design (waves, compass roses)
			# that no NoiseTexture2D descriptor can express and this repo ships no
			# bitmaps; Round 2 already measured what high-contrast two-tone setts do to
			# this exact surface; and calcada is the paving of the Ribeira quays and
			# squares, not of a tram-and-carriageway bridge deck, so laying it here
			# would be a Porto identity error dressed as Porto identity.
			"albedo_ramp": [
				[0.00, Color(0.877, 0.863, 0.816)],
				[0.16, Color(0.816, 0.863, 0.877)],
				[0.32, Color(0.946, 0.879, 0.871)],
				[0.50, Color(0.871, 0.879, 0.946)],
				[0.68, Color(0.976, 0.953, 0.900)],
				[0.85, Color(0.900, 0.953, 0.976)],
			],
		},
		# Limewash: very low frequency, almost flat, just enough to kill the plastic.
		#
		# It gained an albedo map in Round 2, after the world stream gave the Ribeira
		# facades real depth — reveals, sills, shutters, downpipes, azulejo panels —
		# and reported that they STILL read as flat-coloured cards at 60-120 m. That is
		# the correct report and it is a material problem rather than a geometry one:
		# at a hundred metres the fine layer is long gone (0.28 m tiles go sub-pixel by
		# about four), so a wall was one authored colour with a whisper of bump on it,
		# and one flat colour is one flat colour whether or not it has a window in it.
		#
		# The frequency is the whole design here and it is much lower than the other
		# three: 0.006 against a 2.0 m tile is roughly 1.3 m blotches, which is a
		# STOREY-scale mark. At 100 m that subtends about 13 px, which is what it takes
		# to still be visible; the 0.011-0.03 the other recipes use would be sub-pixel
		# there and would buy nothing at the distance the finding is about. Four octaves
		# so it streaks vertically-ish rather than reading as even mottling — the shape
		# damp actually makes running down a limewashed wall.
		#
		# The VALUE range stays the tightest of the four (linear 0.845 -> 0.958 against
		# cobble's 0.63 -> 0.95), and for the same two reasons it always had: uneven
		# limewash is a subtle mark and not a mosaic, and plaster carries the brightest
		# authored colours in the game (PLASTER_CREAM 0.88, the Ribeira walls up to
		# 0.80), which already sit against ALBEDO_CEILING after DETAIL_ALBEDO_GAIN, so
		# a large gain here would be eaten by the clamp rather than applied.
		#
		# ROUND 3 gives it the same non-monotone treatment as granite, at half the
		# amplitude: warm-cool flips at every stop (+-0.046 linear), green-magenta
		# every two (+-0.021), against a value trend that still climbs. Delivered
		# r-g +0.57, r-b +0.25 against +1.000 / +1.000 before. Damp streaks on lime
		# render go grey-green and sun-baked panels go warm-ochre, and the two are next
		# to each other on every Ribeira facade — which is also the answer to a second
		# critic's independent measurement that saturation on those facades RISES with
		# distance (0.265 -> 0.301 -> 0.323 near to far). A near wall that carries its
		# own hue variation cannot be the least saturated thing in its own frame.
		#
		# The MEAN is held at 0.900 linear, within 0.6% of the ramp it replaces, so the
		# per-channel gain barely moves and the facade palette another stream authored
		# keeps meaning what it says. Chroma peaks at 0.092 linear — a third of what
		# granite carries, because a painted wall is a manufactured surface and a
		# mineral mixture is not.
		{
			"name": "plaster",
			"noise": _fbm(FastNoiseLite.TYPE_SIMPLEX, 0.020, 3, 0.50, 2.0, 4517),
			"bump": 1.6,
			"rough": Vector2(0.80, 1.00),
			"ao": Vector2(0.90, 1.00),
			"albedo_noise": _fbm(FastNoiseLite.TYPE_SIMPLEX, 0.006, 4, 0.55, 2.3, 4523),
			# Quantiles of the fBm histogram, as granite; see the note there.
			"albedo_ramp": [
				[0.00, Color(0.946, 0.939, 0.901)],
				[0.33, Color(0.912, 0.950, 0.956)],
				[0.45, Color(0.977, 0.941, 0.934)],
				[0.56, Color(0.945, 0.951, 0.987)],
				[0.67, Color(0.988, 0.981, 0.946)],
				[1.00, Color(0.955, 0.991, 0.997)],
			],
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
## The albedo values are sRGB (the shader's detail sampler carries source_color) and
## run 0.36 -> 0.99 in linear per channel, 0.48 -> 0.95 in luminance. At the 0.55
## blend weight that lands as a 0.65-1.00 multiplier on albedo: deep enough to see
## across a facade and shallow enough that no surface loses its identity. Since
## Round 3 it also carries hue — see _fine_ramp() for what that costs and what it
## may not break.
func _write_fine() -> void:
	var normal := _base_texture()
	normal.as_normal_map = true
	normal.bump_strength = 2.2
	normal.noise = _fbm(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.110, 4, 0.50, 2.1, 7717)
	_save(normal, "detail_fine_normal.tres")

	var albedo := _base_texture()
	albedo.color_ramp = _fine_ramp()
	albedo.noise = _fine_noise()
	_save(albedo, "detail_fine_albedo.tres")


## Factored out of _write_fine() only so _report() can measure the ramp over the
## same field the map is written from. Two copies of a seed is how two copies
## drift apart.
func _fine_noise() -> FastNoiseLite:
	return _fbm(FastNoiseLite.TYPE_SIMPLEX, 0.032, 3, 0.55, 2.0, 8821)


## Biased high so the average surface keeps most of its authored value, with a long
## dark tail for the crevices and damp patches. Alpha is constant and is the blend
## weight for the whole detail layer — see the header.
##
## NO LONGER GREYSCALE. It was, and being greyscale is a large part of why Round 2
## measured every stone surface in the game at a channel correlation of 0.88-0.995:
## at arm's length this layer is most of what varies, and a grey multiplier on a flat
## colour is the definition of variation that never becomes albedo. The same
## non-monotone treatment as granite is applied here — warm-cool flips at every stop
## (+-0.070 linear), green-magenta every two (+-0.032) — so damp reads cool-green,
## dust and old dirt read warm, and the two sit a few centimetres apart. That is what
## 03_rail_macro exists to test.
##
## TWO CONSTRAINTS THIS RAMP CANNOT VIOLATE, both because it is SHARED by every
## textured material in the game and, unlike the surface maps, is corrected by ONE
## SCALAR (ToonFactory.DETAIL_ALBEDO_GAIN) rather than a per-channel gain:
##
##   * its three channel means must be EQUAL. A fine layer averaging even 2% warm
##     tints the ironwork, the azulejos, the terracotta and forty facade colours at
##     once, and nothing downstream divides it back out. Measured spread 0.54%;
##     _atmosphere_probe.gd fails past 2%.
##   * its NET mean — 0.45 + 0.55*c, since FINE_BLEND is the weight of the whole
##     detail pass — must stay where it was, because DETAIL_ALBEDO_GAIN is its
##     reciprocal and moving it rescales every authored colour in the game. Measured
##     0.8759 against the old ramp's 0.8734, a 0.3% drift, so the constant stays at
##     1.13 and no call site's palette shifts.
##
## Those two are also why this layer's correlation only comes down to +0.91 / +0.80
## rather than to granite's +0.43 / +0.06: its VALUE swing (0.45-0.94 in luminance)
## is load-bearing for "damp in the crevices, dry on the face" and cannot be spent,
## and matching that much variance with chroma would need +-0.14 linear of hue on
## every material in the game — including the ironwork, which is the one surface a
## critic has named as working. The surface-scale maps carry the decorrelation; this
## one contributes to it and is deliberately not pushed further.
##
## Stops sit at the fBm field's quantiles, not at even fifths — see the granite note.
func _fine_ramp() -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.45, 0.56, 0.67, 1.0])
	g.colors = PackedColorArray([
		Color(0.738, 0.723, 0.637, FINE_BLEND),
		Color(0.779, 0.847, 0.859, FINE_BLEND),
		Color(0.929, 0.869, 0.858, FINE_BLEND),
		Color(0.899, 0.910, 0.967, FINE_BLEND),
		Color(0.979, 0.969, 0.912, FINE_BLEND),
		Color(0.933, 0.988, 0.997, FINE_BLEND),
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


# --- Measurement ------------------------------------------------------------

## Print, for every albedo map this script writes, the quantity Round 3 is judged
## on: the per-channel correlation of the colour it actually delivers.
##
## WHY THIS EXISTS. Round 2 measured every stone surface in the game and found
## channel-deviation correlations of 0.88-0.995 — cobbles rg 0.945 / rb 0.894,
## granite 0.987 / 0.882, kerb 0.995 / 0.975, parapet 0.994 / 0.964, walkway
## 0.995 / 0.952. A correlation that close to 1 is the signature of ONE flat
## albedo multiplied by a grey mask: whatever the mask does, it does it to all
## three channels at once, so the variation never becomes colour and the surface
## never becomes matter. Real granite decorrelates — feldspar warm, quartz
## near-neutral, biotite dark, lichen green — and that decorrelation is a large
## part of why stone reads as stone.
##
## The trap this measures around: a NoiseTexture2D carries ONE scalar field, so
## every channel is a function of the same t. If R(t), G(t) and B(t) are all
## MONOTONE the correlation is ~1 however much hue swing the ramp carries — which
## is exactly what the old ramps were, and exactly why "make the dark end cooler
## and the bright end warmer" did not move the number. Only a ramp whose channels
## REVERSE against each other decorrelates. That is not a trick: it is what a
## mineral mixture is, because grain brightness and grain hue are independent.
##
## Rendering to find that out costs ~6 minutes a shot. This costs 400 ms, so the
## ramps can be tuned against the real noise histogram instead of against a guess.
##
## The numbers are LINEAR and post-ramp, i.e. what actually multiplies ALBEDO —
## the albedo sampler carries a source_color hint, so an sRGB stop is linearised
## on read. Sampled through ToonFactory.sample_noise() so the frequency-scaling
## rule that keeps the sample over the whole field has one implementation.
const REPORT_SAMPLES := 192

func _report(recipes: Array[Dictionary]) -> void:
	print("")
	print("-- delivered albedo, LINEAR, over the real noise histogram --")
	print("   map          mean rgb              sd rgb            corr r-g  r-b   max chroma")
	for recipe in recipes:
		if not recipe.has("albedo_ramp"):
			continue
		var tex: NoiseTexture2D = _base_texture()
		tex.noise = recipe.get("albedo_noise", recipe["noise"])
		tex.color_ramp = _stops(recipe["albedo_ramp"], recipe.get("albedo_constant", false))
		_measure(recipe["name"], tex, 1.0, 0.0)

	# The shared fine layer is reported through its NET multiplier, 0.45 + 0.55*c,
	# because that is what reaches ALBEDO once the detail pass has mixed it. Its
	# three channel means must stay EQUAL: DETAIL_ALBEDO_GAIN is one scalar, so a
	# fine layer whose channels average differently tints every material in the
	# game and no per-channel gain divides it back out.
	var fine := _base_texture()
	fine.noise = _fine_noise()
	fine.color_ramp = _fine_ramp()
	_measure("fine(net)", fine, FINE_BLEND, 1.0 - FINE_BLEND)


## Rasterise one albedo descriptor and report mean / sd / channel correlation of
## `bias + scale * ramp(noise)`, all in linear.
func _measure(label: String, tex: NoiseTexture2D, scale: float, bias: float) -> void:
	var img := ToonFactory.sample_noise(tex, REPORT_SAMPLES)
	if img == null:
		print("   %-12s (no noise field)" % label)
		return
	var ramp: Gradient = tex.color_ramp
	var n := 0
	var s := [0.0, 0.0, 0.0]
	var ss := [0.0, 0.0, 0.0]
	var s_rg := 0.0
	var s_rb := 0.0
	var chroma := 0.0
	for y in REPORT_SAMPLES:
		for x in REPORT_SAMPLES:
			var c := ramp.sample(img.get_pixel(x, y).r).srgb_to_linear()
			var v := [bias + scale * c.r, bias + scale * c.g, bias + scale * c.b]
			for ch in 3:
				s[ch] += v[ch]
				ss[ch] += v[ch] * v[ch]
			s_rg += v[0] * v[1]
			s_rb += v[0] * v[2]
			chroma = maxf(chroma, maxf(v[0], maxf(v[1], v[2])) - minf(v[0], minf(v[1], v[2])))
			n += 1
	var fn := float(n)
	var m := [s[0] / fn, s[1] / fn, s[2] / fn]
	var sd: Array[float] = []
	for ch in 3:
		sd.append(sqrt(maxf(ss[ch] / fn - m[ch] * m[ch], 0.0)))
	var rg: float = (s_rg / fn - m[0] * m[1]) / maxf(sd[0] * sd[1], 1e-9)
	var rb: float = (s_rb / fn - m[0] * m[2]) / maxf(sd[0] * sd[2], 1e-9)
	print("   %-12s %.4f %.4f %.4f   %.4f %.4f %.4f   %+.3f %+.3f   %.3f"
			% [label, m[0], m[1], m[2], sd[0], sd[1], sd[2], rg, rb, chroma])

	# Where t actually lands, which is where the stops have to be. An fBm field
	# normalised to 0..1 is bell-shaped, not uniform: half its area sits inside
	# roughly t = 0.4..0.6, so stops spaced evenly across 0..1 spend most of their
	# range on texels that barely exist and deliver only the two or three stops in
	# the middle. That is not hypothetical — it is why the first pass at the fine
	# ramp measured r-b +0.858 with three hue reversals authored into it: the
	# reversals were outside the window. Cellular RETURN_CELL_VALUE is the one
	# field here that really is uniform, which is why the cobble ramp can space its
	# six stones evenly and get six equal shares.
	var ts := PackedFloat32Array()
	for y in REPORT_SAMPLES:
		for x in REPORT_SAMPLES:
			ts.append(img.get_pixel(x, y).r)
	ts.sort()
	var q := "                deciles of t:"
	for i in 11:
		q += " %.2f" % ts[mini(int(float(i) / 10.0 * float(ts.size())), ts.size() - 1)]
	print(q)


func _save(tex: NoiseTexture2D, file_name: String) -> void:
	var path := OUT_DIR + file_name
	var err := ResourceSaver.save(tex, path)
	if err != OK:
		push_error("Failed to write %s (error %d)" % [path, err])
	else:
		print("wrote ", path)
