extends SceneTree
## Throwaway budget + correctness probe for the atmosphere stream. Not shipped.
##
## Covers the three files that stream owns: the Environment resource, the sky
## shader it drives, LightingRig's renderer tiering, and everything RiverLife
## builds. None of it can be judged without a render — what this CAN prove is that
## the shaders parse, the numbers are the numbers the comments claim, the fallback
## tier tracks the Forward+ one, the budget is what was promised, and nothing new
## is standing in the playable corridor or inside a landmark.
##
## Run:
##   godot --headless --path . --script scripts/world/_atmosphere_probe.gd

const ENV_PATH := "res://assets/environments/porto_daylight.tres"
const RiverLifeScript := preload("res://scripts/world/river_life.gd")
const RigScript := preload("res://scripts/world/lighting_rig.gd")

## SunLight's +Z basis column in bridge_arena.tscn — the direction the key comes
## from. Duplicated here on purpose: this probe's whole job is to catch the numbers
## and the comments drifting apart, and three files reason about this vector
## (porto_sky.gdshader through LIGHT0_*, lighting_rig.gd's fill derivation, and
## water_wave.gdshader's glint). If the scene's sun moves and this is not updated,
## the check below fails, which is the point.
const SUN_FROM := Vector3(0.54501, 0.77715, 0.31466)
const SUN_ELEVATION_DEG := 51.0
const ARENA_PATH := "res://scenes/world/bridge_arena.tscn"
## The deck surface: the single most-looked-at material in the game, and the one the
## tonemap's exposure is graded against.
const DECK_MATERIAL_PATH := "res://assets/materials/toon_bridge.tres"
const WATER_SHADER_PATH := "res://assets/shaders/water_wave.gdshader"

var _fails := 0


func _initialize() -> void:
	print("=== shaders parse ===")
	_check_shaders()
	print("=== key light ===")
	_check_sun()
	print("=== environment ===")
	var env: Environment = load(ENV_PATH)
	_check_env(env)
	print("=== materials ===")
	_check_materials()
	print("=== aerial perspective ===")
	_check_fog(env)
	print("=== compatibility tier ===")
	_check_compat_tier(env)
	print("=== river life budget ===")
	var life := _build_life()
	_budget(life)
	print("=== corridor containment ===")
	_check_corridor(life)
	print("=== flight envelopes ===")
	_check_flight(life)
	print("=== vessel paths ===")
	_check_vessels(life)
	print("=== animation stability ===")
	_check_animation(life)
	print("=== determinism ===")
	_check_determinism(life)
	print("=== FAILURES: %d ===" % _fails)
	quit(1 if _fails > 0 else 0)


func _fail(msg: String) -> void:
	_fails += 1
	print("  FAIL  " + msg)


# --- Shaders -----------------------------------------------------------------

## get_shader_uniform_list() only returns anything once the ShaderLanguage parser
## has accepted the source, so a non-empty list is proof the code compiles at
## least as far as the frontend. That is the whole check available without a GPU.
func _check_shaders() -> void:
	var sky: Environment = load(ENV_PATH)
	var sky_mat := sky.sky.sky_material as ShaderMaterial
	# 27 after the Belt of Venus, the Earth-shadow wedge and counter_spread were
	# deleted — eight uniforms of evening phenomena that a 51-degree sun does not
	# have. Margin as before: the floor is the real count less about 10%.
	_uniforms("porto_sky.gdshader", sky_mat.shader, 24)

	var gull := Shader.new()
	gull.code = RiverLifeScript.GULL_SHADER
	_uniforms("RiverLife.GULL_SHADER", gull, 8)

	var foam := Shader.new()
	foam.code = RiverLifeScript.FOAM_SHADER
	_uniforms("RiverLife.FOAM_SHADER", foam, 6)

	# 16 after mirror_albedo was added. The Douro is a third of the frame in three
	# shots and this shader had no parse check at all before this pass.
	var wave: Shader = load(WATER_SHADER_PATH)
	_uniforms("water_wave.gdshader", wave, 14)
	# The glint direction is a copy of the sun, and a copy is a thing that goes stale.
	# Read out of the SOURCE, not out of the RenderingServer: headless runs the dummy
	# backend, where shader_get_parameter_default() returns null for everything.
	#
	# Only the DEFAULT is checkable at all. Mat_river in bridge_arena.tscn overrides
	# every uniform in this shader, that scene belongs to the world stream, and its
	# copy of this vector is still the old sunset one — which is why the shader now
	# carries mirror_albedo, so a stale warm mirror colour cannot own a third of the
	# frame on its own. See the header of water_wave.gdshader.
	var glint_dir := _shader_vec3_default(wave.code, "sun_direction")
	print("  water sun_direction default %s" % str(glint_dir.snapped(Vector3.ONE * 0.001)))
	if glint_dir.distance_to(SUN_FROM) > 0.01:
		_fail("water_wave.gdshader's sun_direction default %s is not the scene's sun %s"
				% [str(glint_dir), str(SUN_FROM)])


## `uniform vec3 <name> = vec3(a, b, c);` out of shader source, as a Vector3.
func _shader_vec3_default(code: String, uniform_name: String) -> Vector3:
	var re := RegEx.new()
	re.compile("uniform\\s+vec3\\s+%s\\s*=\\s*vec3\\(([^)]*)\\)" % uniform_name)
	var m := re.search(code)
	if m == null:
		_fail("no vec3 uniform named %s with a default" % uniform_name)
		return Vector3.ZERO
	var parts := m.get_string(1).split(",")
	if parts.size() != 3:
		_fail("%s's default is not three components" % uniform_name)
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _uniforms(label: String, shader: Shader, expect_min: int) -> void:
	var n := shader.get_shader_uniform_list(true).size()
	print("  %-28s %d uniforms" % [label, n])
	if n < expect_min:
		_fail("%s parsed to %d uniforms, expected at least %d" % [label, n, expect_min])


# --- Key light ---------------------------------------------------------------

## The one number nothing else in the stream can derive for itself. SunLight is the
## world stream's node in the world stream's scene — this stream is only allowed to
## set its transform, colour and energy — so the reasoning in three separate files
## hangs off a vector that lives somewhere else entirely. Read it back out of the
## scene and check it is still what those files say it is.
func _check_sun() -> void:
	var packed: PackedScene = load(ARENA_PATH)
	if packed == null:
		_fail("could not load %s" % ARENA_PATH)
		return
	var state := packed.get_state()
	var found := false
	for i in state.get_node_count():
		if state.get_node_name(i) != "SunLight":
			continue
		found = true
		var xf := Transform3D.IDENTITY
		var color := Color.WHITE
		var energy := 1.0
		for p in state.get_node_property_count(i):
			match state.get_node_property_name(i, p):
				"transform": xf = state.get_node_property_value(i, p)
				"light_color": color = state.get_node_property_value(i, p)
				"light_energy": energy = state.get_node_property_value(i, p)
		# A DirectionalLight3D shines down its own -Z, so the direction light comes
		# FROM is the basis's +Z column.
		var from := xf.basis.z.normalized()
		var elev := rad_to_deg(asin(clampf(from.y, -1.0, 1.0)))
		print("  SunLight from %s   elevation %.1f deg   %s @ %.2f"
				% [str(from.snapped(Vector3.ONE * 0.001)), elev, color.to_html(false), energy])
		if from.distance_to(SUN_FROM) > 0.01:
			_fail("SunLight points %s; this stream's files are written for %s"
					% [str(from), str(SUN_FROM)])
		if absf(elev - SUN_ELEVATION_DEG) > 1.0:
			_fail("sun elevation %.1f deg, not the %.1f the comments claim"
					% [elev, SUN_ELEVATION_DEG])
		# Warm WHITE, not orange. A 5400 K sun has R-B around 0.12; the 3200 K
		# golden-hour one had 0.46.
		var warmth := color.r - color.b
		print("  sun colour   R-B %+.3f (want < 0.2, i.e. warm white not orange)" % warmth)
		if warmth >= 0.2:
			_fail("sun colour R-B %+.3f is a sunset, not daylight" % warmth)
		# Deck irradiance: energy * sin(elevation) * effective albedo, read off the
		# real material rather than hard-coded, because the deck is the surface the
		# tonemap is graded around and a number copied by hand here is a number that
		# goes stale the first time someone retints the granite. "Effective" is the
		# authored albedo times the fine detail layer's mean, which is what actually
		# reaches the light.
		var deck_mat: StandardMaterial3D = load(DECK_MATERIAL_PATH)
		var a := deck_mat.albedo_color
		var albedo := (a.r + a.g + a.b) / 3.0 / ToonFactory.DETAIL_ALBEDO_GAIN
		var deck := energy * sin(deg_to_rad(elev)) * albedo
		print("  sunlit deck  %.3f scene-referred (energy %.2f x sin(%.0f) x albedo %.3f)"
				% [deck, energy, elev, albedo])
		if deck < 0.28 or deck > 0.60:
			_fail("sunlit deck at %.3f is outside the range the tonemap is graded for" % deck)
	if not found:
		_fail("no SunLight node in %s" % ARENA_PATH)


# --- Materials ---------------------------------------------------------------

## ToonFactory is this pass's other half. None of the look can be judged here, but
## the three rules it enforces centrally can be, and all three are RUBRIC lines that
## the frame fails outright if they regress.
func _check_materials() -> void:
	var granite := ToonFactory.stone()
	var painted := ToonFactory.iron()
	var railhead := ToonFactory.iron(ToonFactory.IRON_GREY, 1.0, 0.85, 0.26)
	var glaze := ToonFactory.ceramic()

	print("  stone()      albedo %s  rough %.2f  metal %.1f  F0 %.2f  detail %s @ %.2f m"
			% [granite.albedo_color.to_html(false), granite.roughness, granite.metallic,
				granite.metallic_specular, "yes" if granite.detail_enabled else "NO",
				1.0 / maxf(granite.uv2_scale.x, 0.001)])
	print("  iron()       metal %.1f -> F0 %.2f   railhead(0.85) metal %.1f"
			% [painted.metallic, painted.metallic_specular, railhead.metallic])

	# (a) two texture scales on every textured surface.
	for pair in [["stone", granite], ["iron", painted], ["ceramic", glaze]]:
		var m: StandardMaterial3D = pair[1]
		if not m.detail_enabled:
			_fail("%s() has no close-range detail layer" % pair[0])
		elif not m.uv2_triplanar:
			_fail("%s()'s detail layer is not triplanar, so it has no UVs to ride" % pair[0])
		elif m.detail_albedo == null:
			_fail("%s() has no detail albedo, so its albedo is a flat colour" % pair[0])
		if m.normal_texture == null:
			_fail("%s() has no surface normal map" % pair[0])
		if m.roughness_texture == null:
			_fail("%s() has a constant roughness across the surface" % pair[0])

	# (b) the detail layer must MODULATE albedo, not replace it, and must not wipe
	# out the surface normal — which is what its alpha channel is for.
	var fine: NoiseTexture2D = granite.detail_albedo
	var blend: float = fine.color_ramp.colors[0].a
	print("  fine layer   blend alpha %.2f   albedo ramp %.2f..%.2f (sRGB)"
			% [blend, fine.color_ramp.colors[0].r,
				fine.color_ramp.colors[fine.color_ramp.colors.size() - 1].r])
	if granite.detail_blend_mode != BaseMaterial3D.BLEND_MODE_MUL:
		_fail("detail blend is not MUL, so the layer replaces the authored colour")
	if blend > 0.85:
		_fail("detail alpha %.2f: the fine normal is replacing the surface normal" % blend)
	if blend < 0.2:
		_fail("detail alpha %.2f is too weak to be albedo variation" % blend)

	# (c) metals are 0 or 1.
	for pair in [["stone", granite], ["iron", painted], ["ceramic", glaze],
			["railhead", railhead]]:
		var m: StandardMaterial3D = pair[1]
		if m.metallic > 0.001 and m.metallic < 0.999:
			_fail("%s() is %.2f metallic; metals are 0 or 1" % [pair[0], m.metallic])
	if railhead.metallic < 0.999:
		_fail("a call site asking for 0.85 metallic did not get bare metal")
	if painted.metallic_specular <= 0.5:
		_fail("painted iron got no specular back for the metallic it lost")

	# Physical albedo range, checked on the two worst offenders in the codebase.
	for c in [Color(0.95, 0.90, 0.84), Color(0.93, 0.91, 0.85), Color(0.01, 0.01, 0.01)]:
		var m := ToonFactory.solid(c)
		var peak: float = maxf(m.albedo_color.r, maxf(m.albedo_color.g, m.albedo_color.b))
		var dim: float = minf(m.albedo_color.r, minf(m.albedo_color.g, m.albedo_color.b))
		if peak > ToonFactory.ALBEDO_CEILING + 0.001 or dim < ToonFactory.ALBEDO_FLOOR - 0.001:
			_fail("solid(%s) -> albedo %s is outside %.2f..%.2f"
					% [c.to_html(false), m.albedo_color.to_html(false),
						ToonFactory.ALBEDO_FLOOR, ToonFactory.ALBEDO_CEILING])

	# The cache is what collapses two hundred facades onto a handful of materials.
	# Snapping metallic before the key is built is supposed to make it collapse
	# harder, not softer: two call sites asking for different half-metals now share.
	var a := ToonFactory.iron(ToonFactory.IRON_GREY, 1.6, 0.30, 0.62)
	var b := ToonFactory.iron(ToonFactory.IRON_GREY, 1.6, 0.45, 0.62)
	print("  cache        iron(0.30) and iron(0.45) share a material: %s"
			% ["yes" if a == b else "NO"])
	if a != b:
		_fail("metallic snap happens after the cache key, so it costs a draw call")


# --- Environment -------------------------------------------------------------

func _check_env(env: Environment) -> void:
	if env == null:
		_fail("environment did not load")
		return
	print("  tonemap AgX  exposure %.2f  white %.2f  contrast %.2f"
			% [env.tonemap_exposure, env.tonemap_agx_white, env.tonemap_agx_contrast])
	print("  ambient      energy %.2f  sky %.2f  colour %s"
			% [env.ambient_light_energy, env.ambient_light_sky_contribution,
				env.ambient_light_color.to_html(false)])
	print("  grade        contrast %.2f  saturation %.2f  LUT %s"
			% [env.adjustment_contrast, env.adjustment_saturation,
				"yes" if env.adjustment_color_correction != null else "NO"])

	if env.fog_sky_affect != 0.0:
		_fail("fog_sky_affect %.2f fogs the sky itself" % env.fog_sky_affect)
	if env.volumetric_fog_sky_affect != 0.0:
		_fail("volumetric_fog_sky_affect %.2f fogs the sky itself" % env.volumetric_fog_sky_affect)

	# The sky is what every shaded surface in the arena is filled by
	# (ambient_light_sky_contribution 0.92), so a warm sky is a warm frame no matter
	# what the key does. Checked as a channel relationship rather than as literal
	# values so a retune does not have to come here, but a slide back toward sunset
	# does. Zenith must be the most saturated blue in the dome; the horizon haze must
	# still be blue-biased rather than cream.
	var sky_mat := env.sky.sky_material as ShaderMaterial
	var zenith: Color = sky_mat.get_shader_parameter("zenith_color")
	var horizon: Color = sky_mat.get_shader_parameter("horizon_color")
	var haze: Color = sky_mat.get_shader_parameter("haze_color")
	print("  sky          zenith B-R %+.3f   horizon B-R %+.3f   haze B-R %+.3f  (all want > 0)"
			% [zenith.b - zenith.r, horizon.b - horizon.r, haze.b - haze.r])
	for pair in [["zenith", zenith], ["horizon", horizon], ["haze", haze]]:
		var c: Color = pair[1]
		if c.b - c.r <= 0.0:
			_fail("sky %s_color is warm (B-R %+.3f); this is a daylight sky"
					% [pair[0], c.b - c.r])
	if zenith.b - zenith.r < 0.4:
		_fail("zenith_color B-R %+.3f is not a genuinely blue sky" % (zenith.b - zenith.r))

	# The grade LUT must be monotonic per channel or it inverts tonal order.
	var lut := env.adjustment_color_correction as GradientTexture1D
	if lut == null:
		_fail("adjustment_color_correction is not a GradientTexture1D")
		return
	var prev := Color(-1.0, -1.0, -1.0)
	for i in 65:
		var c := lut.gradient.sample(float(i) / 64.0)
		if c.r < prev.r or c.g < prev.g or c.b < prev.b:
			_fail("grade LUT is not monotonic at t = %.3f" % (float(i) / 64.0))
			break
		prev = c
	# Split-toning is gone. Shadows may stay faintly cool — under a high sun they are
	# literally lit by a blue sky, so that is the colour of a shadow rather than a
	# look — but the highlights must be neutral, because a midday sun clips white and
	# a warm clip is the single most golden-hour thing a frame can still be doing.
	var shadow := lut.gradient.sample(0.07)
	var high := lut.gradient.sample(0.8)
	var clip := lut.gradient.sample(1.0)
	print("  grade tone   shadow R-B %+.3f (want <= 0)   highlight R-B %+.3f (want ~0)   clip %s"
			% [shadow.r - shadow.b, high.r - high.b, clip.to_html(false)])
	if shadow.r - shadow.b > 0.0:
		_fail("grade LUT warms the shadows; sky-lit shadows are cool or neutral")
	if absf(high.r - high.b) > 0.02:
		_fail("grade LUT split-tones the highlights by %+.3f" % (high.r - high.b))
	if absf(clip.r - clip.b) > 0.01 or clip.r < 0.99:
		_fail("grade LUT clips to %s, not to neutral white" % clip.to_html(false))

	# The contrast has to live somewhere. It is in the LUT's low mids now, so the
	# stop below the neutral pivot must sit under identity.
	var crunch := lut.gradient.sample(0.06)
	print("  grade shape  LUT(0.06) = %.3f (want < 0.06)   LUT(0.50) = %.3f (want > 0.50)"
			% [crunch.g, lut.gradient.sample(0.5).g])
	if crunch.g >= 0.06:
		_fail("grade LUT has no shadow crunch; the frame will read flat")
	if lut.gradient.sample(0.5).g <= 0.5:
		_fail("grade LUT does not lift the upper mids; this is not a high-key grade")


# --- Fog ---------------------------------------------------------------------

## Godot's depth fog is pow(smoothstep(begin, end, d), curve) * density, and the
## volumetric pass composites over it as (depth * (1 - vol) + vol). Both are
## reproduced here so the table in the .tres can be checked rather than believed.
func _check_fog(env: Environment) -> void:
	print("  %6s  %8s  %11s  %10s  %9s  %7s" %
			["dist", "depth", "volumetric", "forward+", "compat", "delta"])
	var worst := 0.0
	var worst_d := 0.0
	var prev := -1.0
	for d in [10.0, 25.0, 45.0, 50.0, 70.0, 100.0, 130.0, 168.0, 280.0, 340.0, 410.0]:
		var depth := _depth(d, env.fog_depth_begin, env.fog_depth_end,
				env.fog_depth_curve, env.fog_density)
		var vol := 1.0 - exp(-env.volumetric_fog_density * minf(d, env.volumetric_fog_length))
		var fwd := depth * (1.0 - vol) + vol
		var cmp := _depth(d, RigScript.COMPAT_FOG_BEGIN, env.fog_depth_end,
				RigScript.COMPAT_FOG_CURVE, RigScript.COMPAT_FOG_DENSITY)
		print("  %6.0f  %8.3f  %11.3f  %10.3f  %9.3f  %+7.3f" % [d, depth, vol, fwd, cmp, cmp - fwd])
		if absf(cmp - fwd) > worst:
			worst = absf(cmp - fwd)
			worst_d = d
		# A monotone ramp IS the depth cue; a dip anywhere means near geometry
		# would be hazier than something behind it.
		if fwd < prev - 1e-4:
			_fail("aerial perspective is not monotone at %.0f m" % d)
		prev = fwd
	print("  worst compat/forward+ mismatch %.3f at %.0f m" % [worst, worst_d])
	if worst > 0.06:
		_fail("compatibility fallback drifts %.3f from the Forward+ curve" % worst)

	# Two ends of the same requirement, and both are about the CURVE rather than
	# about any one parameter — the previous version asserted fog_depth_begin <= 30,
	# which is a proxy that stopped tracking the resource the moment the range was
	# widened to 640 m and then reported failure for four rounds.
	#
	# Anything the player stands on has to stay crisp...
	var deck := _depth(50.0, env.fog_depth_begin, env.fog_depth_end,
			env.fog_depth_curve, env.fog_density)
	var deck_v := 1.0 - exp(-env.volumetric_fog_density * 50.0)
	var deck_total := deck * (1.0 - deck_v) + deck_v
	print("  far parapet from mid-deck (50 m): %.1f%% haze" % (deck_total * 100.0))
	if deck_total > 0.20:
		_fail("%.0f%% haze across the playable deck" % (deck_total * 100.0))
	# ...and the mid-ground has to actually sit back, or there is no depth cue at all
	# and the bridge, the Ribeira and the hills read as one plane. 100 m is where the
	# terraces are; 168 m is the near edge of the backdrop scan.
	var mid := _depth(100.0, env.fog_depth_begin, env.fog_depth_end,
			env.fog_depth_curve, env.fog_density)
	var mid_v := 1.0 - exp(-env.volumetric_fog_density * minf(100.0, env.volumetric_fog_length))
	var mid_total := mid * (1.0 - mid_v) + mid_v
	var far := _depth(168.0, env.fog_depth_begin, env.fog_depth_end,
			env.fog_depth_curve, env.fog_density)
	var far_v := 1.0 - exp(-env.volumetric_fog_density * minf(168.0, env.volumetric_fog_length))
	var far_total := far * (1.0 - far_v) + far_v
	print("  Ribeira terraces (100 m): %.1f%%   backdrop (168 m): %.1f%%   step %+.1f points"
			% [mid_total * 100.0, far_total * 100.0, (far_total - mid_total) * 100.0])
	if mid_total < 0.08:
		_fail("only %.0f%% haze at 100 m; the mid-ground does not sit back" % (mid_total * 100.0))
	if far_total - mid_total < 0.05:
		_fail("only %.1f points of haze between the terraces and the backdrop"
				% ((far_total - mid_total) * 100.0))
	# Aerial perspective is the sky showing through the geometry. If the veil is
	# mostly fog_light_color instead, distance takes on a flat tint rather than the
	# sky's own colour, which is the milky-screen failure an earlier pass shipped.
	print("  aerial perspective %.2f, fog tint %s"
			% [env.fog_aerial_perspective, env.fog_light_color.to_html(false)])
	if env.fog_aerial_perspective < 0.8:
		_fail("aerial_perspective %.2f: the far field is fog, not sky"
				% env.fog_aerial_perspective)
	if env.fog_light_color.r - env.fog_light_color.b > 0.0:
		_fail("fog_light_color is warm; it tints every distant surface in a 5400 K frame")


func _depth(d: float, begin: float, end: float, curve: float, density: float) -> float:
	var t: float = clampf((d - begin) / (end - begin), 0.0, 1.0)
	return pow(t * t * (3.0 - 2.0 * t), curve) * density


# --- Compatibility tier ------------------------------------------------------

## Headless always reports forward_plus, so the web tier can never be reached by
## just running the scene. Drive it directly on a copy of the resource instead and
## assert the things that would make the web build wrong rather than merely
## different: an effect left on that the renderer will warn about every frame, a
## glow threshold the LDR buffer can never reach, or a sky reflection so coarse
## the river stops being a mirror.
func _check_compat_tier(source: Environment) -> void:
	var env: Environment = source.duplicate(true)
	var rig: Node3D = RigScript.new()
	rig._strip_forward_plus(env)
	rig._tune_for_compatibility(env)

	print("  fog        begin %.0f  curve %.2f  density %.2f"
			% [env.fog_depth_begin, env.fog_depth_curve, env.fog_density])
	print("  ambient    %.2f -> %.2f  (x%.2f)"
			% [source.ambient_light_energy, env.ambient_light_energy,
				env.ambient_light_energy / source.ambient_light_energy])
	print("  glow       threshold %.2f  levels 5/6 %.1f/%.1f"
			% [env.glow_hdr_threshold, env.get_glow_level(4), env.get_glow_level(5)])
	print("  sky        radiance_size %d (256 = %d)" % [env.sky.radiance_size, Sky.RADIANCE_SIZE_256])

	for flag in ["ssr_enabled", "ssil_enabled", "sdfgi_enabled", "volumetric_fog_enabled"]:
		if env.get(flag):
			_fail("%s survived the Compatibility downgrade" % flag)
	if env.glow_hdr_threshold >= 1.0:
		_fail("glow threshold %.2f is unreachable in an LDR buffer" % env.glow_hdr_threshold)
	if env.sky.radiance_size < Sky.RADIANCE_SIZE_256:
		_fail("radiance_size %d leaves the water reflecting a blocky sky" % env.sky.radiance_size)
	if not env.fog_enabled:
		_fail("depth fog is off, so the web build has no aerial perspective at all")
	rig.free()


# --- River life --------------------------------------------------------------

func _build_life() -> Node3D:
	var life: Node3D = RiverLifeScript.new()
	life.name = "RiverLife"
	get_root().add_child(life)
	# A custom SceneTree main runs _initialize() before the root window is fully
	# in-tree, so add_child() here does not always propagate NOTIFICATION_READY.
	# In the game it always will; this only covers the probe's own harness.
	if life.get_child_count() == 0:
		life._ready()
	return life


func _budget(root: Node3D) -> void:
	var calls := 0
	var tris := 0
	for node in _geometry(root):
		var mesh: Mesh
		var count := 1
		if node is MultiMeshInstance3D:
			var mm := (node as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			count = mm.instance_count
		else:
			mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		var per := 0
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			per += (idx.size() if idx.size() > 0 else verts.size()) / 3
			calls += 1
		tris += per * count
		print("  %-22s %5d tris x %2d = %6d   surfaces %d"
				% [node.name, per, count, per * count, mesh.get_surface_count()])
	var fog_volumes := 0
	for c in _all(root):
		if c is FogVolume:
			fog_volumes += 1
	print("  renderer: %s   fog volumes: %d" % [RenderingServer.get_current_rendering_method(), fog_volumes])
	print("  TOTAL %d draw calls, %d triangles" % [calls, tris])
	if calls > 20:
		_fail("%d draw calls is over the 20 this stream budgeted" % calls)


func _geometry(node: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		out.append(node as GeometryInstance3D)
	for c in node.get_children():
		out.append_array(_geometry(c))
	return out


func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out


## Nothing this stream builds may stand in the playable corridor: the deck runs
## x in [-50, 50], z in [-6, 6] with its walking surface at y = 2. The ceiling is
## put at y = 28 — well over the 9-unit boss and any jump — rather than at
## infinity, so a gull passing high over the arch is not counted as an intrusion.
func _check_corridor(life: Node3D) -> void:
	var corridor := AABB(Vector3(-50.0, 2.0, -6.0), Vector3(100.0, 26.0, 12.0))
	var breaches := 0
	for node in _geometry(life):
		var world: AABB
		if node is MultiMeshInstance3D:
			# custom_aabb is the whole flight envelope, so one test covers every
			# frame the flock will ever be in.
			world = _world_of(node, life) * (node as MultiMeshInstance3D).multimesh.custom_aabb
		elif _under_vessel(node):
			continue   # swept separately below, across a full run
		else:
			world = _world_of(node, life) * node.get_aabb()
		if world.intersects(corridor):
			breaches += 1
			_fail("%s overlaps the playable corridor: %s" % [node.name, str(world)])

	# Vessels move, so sweep a whole circuit rather than trusting the rest pose.
	var samples := 400
	for i in samples:
		life._animate_vessels(float(i) * 1.2)
		for v in life._vessels:
			var node: Node3D = v["node"]
			if not node.visible:
				continue
			for g in _geometry(node):
				if (_world_of(g, life) * g.get_aabb()).intersects(corridor):
					breaches += 1
					_fail("%s enters the corridor at t = %.1f" % [g.name, float(i) * 1.2])
					break
	print("  %d breaches over %d swept vessel positions" % [breaches, samples])


## global_transform needs the node to be inside a real tree, and a custom SceneTree
## main does not give it one. Compose the local transforms up to `root` instead.
func _world_of(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


func _check_flight(life: Node3D) -> void:
	# Everything the flocks fly past, as world AABBs read off sky_background.gd.
	# The two terrace rows are split per bank rather than spanned across, because
	# a box from -110 to +110 would claim the open river in between.
	var obstacles := {
		"Clerigos tower": AABB(Vector3(-65.0, 7.0, -41.0), Vector3(6.0, 39.0, 6.0)),
		"Serra do Pilar": AABB(Vector3(41.0, -15.0, -40.0), Vector3(20.0, 39.0, 20.0)),
		"Ribeira terrace (Porto)": AABB(Vector3(-82.0, 0.0, -27.0), Vector3(44.0, 23.0, 12.0)),
		"Ribeira terrace (Gaia)": AABB(Vector3(38.0, 0.0, -27.0), Vector3(44.0, 23.0, 12.0)),
		"upper terrace (Porto)": AABB(Vector3(-100.0, 7.0, -37.0), Vector3(53.0, 20.0, 11.0)),
		"upper terrace (Gaia)": AABB(Vector3(47.0, 7.0, -37.0), Vector3(53.0, 20.0, 11.0)),
		"bridge + boss volume": AABB(Vector3(-58.0, -2.0, -10.0), Vector3(116.0, 22.0, 20.0)),
	}
	for f in life._flocks:
		var period: float = f["period"]
		var lo := Vector3.INF
		var hi := -Vector3.INF
		# 240 samples over a full circuit, plus the widest per-bird scatter.
		for i in 240:
			var p: Vector3 = life._flock_point(f, period * float(i) / 240.0)
			lo = lo.min(p)
			hi = hi.max(p)
		var pad := 0.0
		for s in f["sides"]:
			pad = maxf(pad, absf(s))
		for r in f["rises"]:
			pad = maxf(pad, absf(r))
		pad += 0.8   # half a wingspan
		var env := AABB(lo - Vector3.ONE * pad, (hi - lo) + Vector3.ONE * pad * 2.0)
		print("  flock: x [%6.1f %6.1f]  y [%5.1f %5.1f]  z [%6.1f %6.1f]"
				% [env.position.x, env.end.x, env.position.y, env.end.y,
					env.position.z, env.end.z])
		for name in obstacles:
			if env.intersects(obstacles[name]):
				_fail("flock envelope %s intersects %s" % [str(env), name])


func _under_vessel(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if String(p.name).begins_with("Vessel"):
			return true
		p = p.get_parent()
	return false


func _check_vessels(life: Node3D) -> void:
	for v in life._vessels:
		var x: float = v["x"]
		var node: Node3D = v["node"]
		var box := AABB()
		var first := true
		for g in _geometry(node):
			if g.name == "Wake":
				continue   # 70 m of foam ribbon is not part of the hull
			var b := g.transform * g.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var half_beam := box.size.x * 0.5
		print("  vessel x %+6.1f  beam %.1f  length %.1f  masthead %+.2f above water"
				% [x, box.size.x, box.size.z, box.end.y + 0.10])
		if absf(x) + half_beam > RiverLifeScript.CHANNEL_HALF:
			_fail("vessel at x %.1f (half-beam %.1f) is outside the channel" % [x, half_beam])
		# The arch parabola drops ARCH_RISE = 18 below the deck over a half span
		# of 46; the vessel passes under it at its own x.
		var arch_y := 0.0 - 18.0 * pow(absf(x) / 46.0, 2.0)
		var masthead := RiverLifeScript.WATER_Y + 0.10 + box.end.y
		print("      arch soffit at this x: %+.2f   clearance %.2f m" % [arch_y, arch_y - masthead])
		if arch_y - masthead < 2.0:
			_fail("vessel at x %.1f has only %.1f m of air under the arch" % [x, arch_y - masthead])
		# Moored rabelos in sky_background.gd.
		for spot in [Vector3(-28.0, 0.0, -16.0), Vector3(8.0, 0.0, -24.0), Vector3(34.0, 0.0, -13.0)]:
			if absf(spot.x - x) < half_beam + 2.8:
				_fail("vessel lane x %.1f runs over the rabelo moored at x %.1f" % [x, spot.x])


## Basis.looking_at() blows up when the heading is parallel to the up reference,
## and the roll is a clamped ratio of two finite differences that both go to zero
## at a path's turning points. Neither can be reasoned about from the formulae
## alone, so drive an hour of flight and check every basis that comes out.
func _check_animation(life: Node3D) -> void:
	var worst_bank := 0.0
	var flat_bank := true
	var worst_scale := 0.0
	var samples := 3000
	var birds := 0
	for i in samples:
		var t := float(i) * 1.2
		for f in life._flocks:
			var mm: MultiMesh = f["mm"]
			for j in mm.instance_count:
				# gull_transform, NOT mm.get_instance_transform: MultiMesh data
				# lives in the RenderingServer and the headless dummy backend
				# returns identity, which would make this check pass vacuously.
				var xf: Transform3D = life.gull_transform(f, j, t)
				birds += 1
				if not xf.origin.is_finite():
					_fail("non-finite gull position at t = %.1f" % t)
					return
				# looking_at + rotated must stay a rigid rotation; a degenerate
				# reference axis shows up here as a collapsed or blown-up column.
				for axis in [xf.basis.x, xf.basis.y, xf.basis.z]:
					worst_scale = maxf(worst_scale, absf(axis.length() - 1.0))
				var bank := xf.basis.y.angle_to(Vector3.UP)
				worst_bank = maxf(worst_bank, bank)
				if bank > 0.02:
					flat_bank = false
	print("  %d samples: worst basis scale error %.9f, steepest bank %.1f deg"
			% [birds, worst_scale, rad_to_deg(worst_bank)])
	if worst_scale > 0.001:
		_fail("gull basis is not orthonormal (error %.9f)" % worst_scale)
	if worst_bank > deg_to_rad(75.0):
		_fail("gulls bank to %.0f degrees" % rad_to_deg(worst_bank))
	if flat_bank:
		_fail("no gull ever banks; the roll term is doing nothing")


func _check_determinism(first: Node3D) -> void:
	var second := _build_life()
	var a := _geometry(first)
	var b := _geometry(second)
	if a.size() != b.size():
		_fail("two builds produced %d and %d geometry nodes" % [a.size(), b.size()])
		return
	for i in a.size():
		if not a[i].get_aabb().is_equal_approx(b[i].get_aabb()):
			_fail("%s differs between builds" % a[i].name)
			return
	# The per-bird lags and offsets come off the same RNG as the geometry, so if
	# those drift the flocks fly differently even though the meshes match. Read
	# them from RiverLife's own arrays, not from the MultiMesh — its custom data
	# lives in the RenderingServer, which is a dummy here.
	for i in first._flocks.size():
		for key in ["lags", "sides", "rises"]:
			var pa: PackedFloat32Array = first._flocks[i][key]
			var pb: PackedFloat32Array = second._flocks[i][key]
			if pa != pb:
				_fail("flock %d re-seeded differently in %s" % [i, key])
				return
	print("  two builds identical across %d meshes and %d flock seeds"
			% [a.size(), first._flocks.size()])
	second.queue_free()
