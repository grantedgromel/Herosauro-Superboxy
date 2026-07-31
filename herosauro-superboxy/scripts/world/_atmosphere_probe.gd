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
const SUN_FROM := Vector3(0.337181, 0.559193, 0.757364)
const SUN_ELEVATION_DEG := 34.0
## Azimuth of that vector, degrees east of +x. Checked separately from the elevation
## because Round 2 moved BOTH and they buy different things: the elevation buys shadow
## length, the azimuth buys shadow DIRECTION across a deck that runs along x, plus 2.4x
## the key on the ironwork's broad +-z faces.
const SUN_AZIMUTH_DEG := 66.0
## What the re-key exists for, and therefore the thing worth asserting rather than
## describing. Parapet height above the footway it stands on, in metres.
const PARAPET_HEIGHT := 1.20
## Footway width from the kerb line to the parapet: bridge_arena.gd's
## WALKWAY_OUTER - ROADWAY_HALF. A parapet shadow shorter than this dies on the
## pavement, invisible from a deck-level camera, which is exactly the defect the
## re-key is for.
const FOOTWAY_WIDTH := 1.55
const CLOUD_SHADER_PATH := "res://assets/shaders/soft_cloud.gdshader"
const ARENA_PATH := "res://scenes/world/bridge_arena.tscn"
## The deck surface: the single most-looked-at material in the game, and the one the
## tonemap's exposure is graded against.
const DECK_MATERIAL_PATH := "res://assets/materials/toon_bridge.tres"
## The surface-scale albedo map that material wears. Named here because it is NOT a
## ToonFactory.Surface — it is a one-material map set (see the `masonry` recipe in
## generate_detail_maps.gd), so nothing in the factory can hand the probe its mean and
## the invariant below has to load the descriptor itself.
const DECK_ALBEDO_MAP_PATH := "res://assets/textures/detail_masonry_albedo.tres"
const DECK_NORMAL_MAP_PATH := "res://assets/textures/detail_masonry_normal.tres"

## What the deck fascia's colour is a claim about, before either texture layer
## multiplies it. Duplicated from the material's own header on purpose, exactly as
## SUN_FROM is duplicated from the scene: the whole job of this file is to catch a
## number and the sentence next to it drifting apart.
const DECK_AUTHORED := Color(0.315, 0.312, 0.305)

## bridge_arena.gd's deck palette, duplicated. The world stream owns those constants and
## this stream may not preload its script, but the RUBRIC line they violate —
## "the playable corridor is the brightest, highest-contrast thing in frame" — is a
## MATERIAL property and the guard that enforces it is ToonFactory's. So the four
## colours the guard exists for are named here and asserted against each other. If the
## world stream re-authors them, this check keeps meaning the same thing: it compares
## what the factory DELIVERS for the corridor against what it delivers for the walkway.
const ROADWAY_COLOR := Color(0.325, 0.315, 0.300)
const TRAMBED_COLOR := Color(0.235, 0.225, 0.215)
const FLAG_COLOR := Color(0.545, 0.525, 0.485)
const KERB_COLOR := Color(0.580, 0.560, 0.510)
## How far under the footway the carriageway may sit, as a fraction. Measured in the
## Round 3 render: the flags' lit top quartile was L 146.1 and the carriageway's L 76.3
## thirty pixels in front of it, a ratio of 0.52 on surfaces that are both in full sun.
## 0.85 is the brief's "within about 15% of the slab walkway".
const CORRIDOR_MIN_RATIO := 0.85
const WATER_SHADER_PATH := "res://assets/shaders/water_wave.gdshader"

var _fails := 0

## What ToonFactory delivers for the three large playable ground surfaces, filled in
## by _check_materials() and read by _check_exposure_anchor(). Measured end to end
## through _presents() there rather than re-derived here, for the reason spelt out
## above the corridor check: the factory chains a ceiling, a floor, a knee and two
## per-channel texture gains, and anything that recomputed that chain would agree with
## a bug in it. The kerb is deliberately absent — it is a 30 cm trim and is SUPPOSED to
## be the brightest line on the deck.
var _corridor_presents: Dictionary = {}


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
	print("=== exposure anchor ===")
	_check_exposure_anchor(env)
	print("=== aerial perspective ===")
	_check_fog(env)
	print("=== the river reflects ===")
	_check_reflection(env)
	print("=== the river meets a bank ===")
	_check_shoreline()
	print("=== contact darkening budget ===")
	_check_occlusion_budget(env)
	print("=== cloud field framing ===")
	_check_cloud_framing()
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

	# The clouds are a shader now rather than a StandardMaterial3D, for the reasons at
	# the top of soft_cloud.gdshader. Its sun_direction default is only a compile-time
	# placeholder -- sky_background.gd overwrites it from the real SunLight at load --
	# but a placeholder that is silently wrong is how Mat_river ended up two rounds
	# stale, so it is checked exactly as the water shader's is.
	var cloud: Shader = load(CLOUD_SHADER_PATH)
	_uniforms("soft_cloud.gdshader", cloud, 7)
	var cloud_sun := _shader_vec3_default(cloud.code, "sun_direction")
	print("  cloud sun_direction default %s" % str(cloud_sun.snapped(Vector3.ONE * 0.001)))
	if cloud_sun.distance_to(SUN_FROM) > 0.01:
		_fail("soft_cloud.gdshader's sun_direction default %s is not the scene's sun %s"
				% [str(cloud_sun), str(SUN_FROM)])
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
## Least shadow reach that still covers the Ribeira terraces. Below this the far
## bank has no inter-building occlusion at all, which reads as every background
## object floating on ambient no matter how good the near-field shadows are.
const SHADOW_REACH_MIN := 200.0


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
		# Godot's default is 100 m and the property is absent from the scene when
		# unset — which is exactly how this sat at 100 through three rounds while
		# critics correctly reported the whole mid-ground floating on ambient.
		var shadow_far := 100.0
		for p in state.get_node_property_count(i):
			match state.get_node_property_name(i, p):
				"transform": xf = state.get_node_property_value(i, p)
				"light_color": color = state.get_node_property_value(i, p)
				"light_energy": energy = state.get_node_property_value(i, p)
				"directional_shadow_max_distance": shadow_far = state.get_node_property_value(i, p)
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
		var azim := rad_to_deg(atan2(from.z, from.x))
		print("  azimuth      %.1f deg east of +x (want %.1f)" % [azim, SUN_AZIMUTH_DEG])
		print("  shadow reach %.0f m" % shadow_far)
		if shadow_far < SHADOW_REACH_MIN:
			_fail("directional_shadow_max_distance is %.0f m; the Ribeira stack sits at "
					% shadow_far + "60-150 m and receives no shadow below %.0f"
					% SHADOW_REACH_MIN)
		_check_water_sun(state, from)
		if absf(azim - SUN_AZIMUTH_DEG) > 2.0:
			_fail("sun azimuth %.1f deg, not the %.1f this stream's files are written for"
					% [azim, SUN_AZIMUTH_DEG])

		# The whole point of Round 2's re-key, and the reason it is an assertion rather
		# than a paragraph. At 51 degrees a 1.2 m parapet threw 0.97 m of shadow, and
		# with the old azimuth only half of that was ACROSS the deck -- so it landed
		# inside its own 1.55 m footway, where a deck-level camera never sees it. That
		# is Round 1's "nothing in frame is planted by a shadow the player can see",
		# and it is a property of the light vector, so it belongs here.
		var throw_total := PARAPET_HEIGHT / tan(deg_to_rad(elev))
		var horiz := Vector2(from.x, from.z).length()
		var across := throw_total * (absf(from.z) / maxf(horiz, 0.0001))
		print("  shadow throw %.2f m total, %.2f m ACROSS the deck (footway %.2f m)"
				% [throw_total, across, FOOTWAY_WIDTH])
		if across < FOOTWAY_WIDTH:
			_fail("a %.2f m parapet throws %.2f m across the deck; it dies on its own footway"
					% [PARAPET_HEIGHT, across])
		# The other side of the same requirement. The brief asks for a bright clear
		# day, not a slide back toward the sunset this project already removed once.
		if elev < 22.0:
			_fail("elevation %.1f deg is sliding back toward sunset" % elev)
		# Warm WHITE, not orange. A 5100 K sun has R-B around 0.15; the 3200 K
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
		# albedo_color is the value the BRIGHTEST texel reaches, because it carries the
		# pre-division for both texture layers' means. Undo both to recover what the
		# surface actually reflects on average.
		#
		# MEASURED off the two descriptors rather than divided by ToonFactory's own
		# gains, and Round 4 is why: the fascia's surface map is no longer one of the
		# factory's four, so there is no _albedo_map_gain(GRANITE) to divide by and the
		# old form would have quietly used the wrong map's mean. The two means are the
		# same quantity _check_materials() asserts the .tres against, so if this line
		# and that one disagree, one of them is reading a descriptor that is not on the
		# surface.
		var deck_map: Variant = _map_stats(load(DECK_ALBEDO_MAP_PATH))
		var fine_net: Variant = _fine_net_mean()
		var albedo := (a.r + a.g + a.b) / 3.0
		if deck_map != null and fine_net != null:
			var mm: Color = (deck_map as Dictionary)["mean"]
			var fn: Color = fine_net
			albedo = (a.r * mm.r * fn.r + a.g * mm.g * fn.g + a.b * mm.b * fn.b) / 3.0
		else:
			_fail("the deck material's texture means could not be measured; its irradiance would be overstated by ~30%")
		var deck := energy * sin(deg_to_rad(elev)) * albedo
		print("  sunlit deck  %.3f scene-referred (energy %.2f x sin(%.0f) x albedo %.3f)"
				% [deck, energy, elev, albedo])
		_check_fill_rig(color, energy, elev)
		if deck < 0.28 or deck > 0.60:
			_fail("sunlit deck at %.3f is outside the range the tonemap is graded for" % deck)
	if not found:
		_fail("no SunLight node in %s" % ARENA_PATH)


## Round 1's single most precise finding, turned into arithmetic.
##
## It measured the deck cobble at normalised lit (1.00, 0.877, 0.949) against
## normalised shadow (1.00, 0.818, 0.892) -- a shadow going REDDER than its own lit
## stone under a sky at (66, 151, 211) -- and, in the same band, the cobble's
## normal-map relief vanishing: standard deviation 8.5 outside, 2.4 inside.
##
## Both are properties of what is left when the key is occluded, so both can be
## computed here from the rig's own constants rather than waited for in a render. Two
## things are asserted about an UP-FACING surface (the deck, i.e. the surface the game
## is played on) with the key removed:
##
##   1. CHROMA. The remaining light must be bluer than the key, or a shadow reads as
##      a warm decal. This is a ratio, so it is checked as B/R.
##   2. DIRECTIONALITY. At least two thirds of the remaining light must come from a
##      directional source, because a normal map can only respond to light that has a
##      direction. A shadow filled by ambient is a shadow you cannot see relief in,
##      which is a black sticker.
##
## What this CANNOT see is SSIL and SDFGI, which are screen-space and world-space
## respectively and have no closed form. They are the terms Round 1's warm shadow
## actually came from -- the analytic sum below was already blue before this round --
## so their cuts (ssil_intensity 0.60 -> 0.32, radius 4.0 -> 2.4, sdfgi_energy
## 0.95 -> 0.80, bounce_feedback 0.3 -> 0.2) have to be confirmed in a render. The
## numbers printed here are the floor those cuts are landing on top of.
## The river's own copy of the sun vector must equal the real one.
##
## Mat_river is a ShaderMaterial sub-resource inside bridge_arena.tscn, and
## water_wave.gdshader takes `sun_direction` as a uniform rather than reading
## LIGHT0 — so the glint path is authored by hand and nothing connects it to the
## light it is supposed to be reflecting. It was left at the original sunset
## vector through the daylight conversion and TWO subsequent rounds, 121 degrees
## of azimuth away from where SunLight actually points, and this probe passed the
## whole time because it was only ever checking the shader's DEFAULT value.
##
## A hand-copied constant that names another node's property is exactly the thing
## a gate is for: it cannot drift silently, and nobody has to remember it.
func _check_water_sun(state: SceneState, sun_from: Vector3) -> void:
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			var mat = state.get_node_property_value(i, p)
			if not (mat is ShaderMaterial):
				continue
			var shader: Shader = (mat as ShaderMaterial).shader
			if shader == null:
				continue
			var names := PackedStringArray()
			for u in shader.get_shader_uniform_list():
				names.append(String(u.get("name", "")))
			if not names.has("sun_direction"):
				continue
			var authored = (mat as ShaderMaterial).get_shader_parameter("sun_direction")
			var node_name := state.get_node_name(i)
			if authored == null:
				print("  %s.sun_direction unset — inherits the shader default" % node_name)
				_fail("%s leaves sun_direction unset; it must name SunLight's own vector"
						% node_name)
				continue
			var v: Vector3 = (authored as Vector3).normalized()
			var off := rad_to_deg(acos(clampf(v.dot(sun_from), -1.0, 1.0)))
			print("  %s.sun_direction %s   %.1f deg off SunLight"
					% [node_name, str(v.snapped(Vector3.ONE * 0.001)), off])
			if off > 2.0:
				_fail("%s.sun_direction is %.1f deg from SunLight — the glint path points "
						% [node_name, off] + "somewhere the sun is not")


func _check_fill_rig(sun_color: Color, sun_energy: float, elev: float) -> void:
	var env: Environment = load(ENV_PATH)
	var sky_mat := env.sky.sky_material as ShaderMaterial
	# ambient_light_sky_contribution is 0.92, so the ambient term is essentially the
	# dome. upper_color is the band a horizontal surface sees most of.
	var ambient_hue: Color = sky_mat.get_shader_parameter("upper_color")

	# Energies off a live LightingRig rather than copied: three numbers duplicated here
	# would be three numbers that stop tracking the thing they are checking, which is
	# the same failure as Mat_river's stale sun.
	var rig: Node3D = RigScript.new()
	var up := Vector3.UP
	var directional := Color(0.0, 0.0, 0.0)
	for fill in [
		[RigScript.SKY_FILL_DIR, RigScript.SKY_FILL_COLOR, rig.sky_fill_energy],
		[RigScript.QUAY_BOUNCE_DIR, RigScript.QUAY_BOUNCE_COLOR, rig.bounce_energy],
		[RigScript.RIBEIRA_BOUNCE_DIR, RigScript.RIBEIRA_BOUNCE_COLOR,
			rig.ribeira_bounce_energy],
	]:
		var dir: Vector3 = fill[0]
		var c: Color = fill[1]
		var e: float = fill[2]
		var ndl: float = maxf(dir.normalized().dot(up), 0.0)
		directional += Color(c.r * e * ndl, c.g * e * ndl, c.b * e * ndl)

	var flat := Color(ambient_hue.r, ambient_hue.g, ambient_hue.b) * env.ambient_light_energy
	var shadow := directional + flat
	var key := Color(sun_color.r, sun_color.g, sun_color.b) * sun_energy * sin(deg_to_rad(elev))

	var shadow_ratio := shadow.b / maxf(shadow.r, 0.0001)
	var key_ratio := key.b / maxf(key.r, 0.0001)
	print("  shadow term  %s   B/R %.3f   (key B/R %.3f)"
			% [shadow.to_html(false), shadow_ratio, key_ratio])
	if shadow_ratio <= key_ratio:
		_fail("shadow B/R %.3f is not cooler than the key's %.3f; shadows will read warm"
				% [shadow_ratio, key_ratio])

	var dir_lum := _luma(directional)
	var total_lum := maxf(_luma(shadow), 0.0001)
	print("  shadow fill  %.0f%% directional / %.0f%% flat  (want >= 65%% directional)"
			% [dir_lum / total_lum * 100.0, _luma(flat) / total_lum * 100.0])
	if dir_lum / total_lum < 0.65:
		_fail("only %.0f%% of the shadow term has a direction; a normal map cannot respond to the rest"
				% (dir_lum / total_lum * 100.0))
	# The shadow also has to stay a shadow. Too much fill and the frame has no
	# contrast at all, which is the failure the ambient cuts were reacting against.
	var ratio := total_lum / maxf(_luma(key) + total_lum, 0.0001)
	print("  shadow / lit %.2f  (want 0.12 - 0.40 on a bright clear day)" % ratio)
	if ratio > 0.40:
		_fail("shadows sit at %.2f of lit; that is not a bright day, it is an overcast one" % ratio)
	if ratio < 0.12:
		_fail("shadows sit at %.2f of lit; nothing in them will read at all" % ratio)
	rig.free()


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# --- Exposure anchor ---------------------------------------------------------
#
# ROUND 5, and this is the gate for the defect the OWNER found by looking at the
# running build: "everything is just so bright to the point of being white". The deck
# fascia — the single largest surface in 01_deck_mid, 16.9% of the frame — rendered at
# L 187 out of 255, level with the far river's fog band at L 176, so the bridge and the
# sky read as one white mass. Nothing in the atmosphere had changed: the sky rows of
# that frame are identical to Round 3's, block for block.
#
# WHAT ACTUALLY HAPPENED, because it is a class of failure rather than an incident.
# Five separate, individually-correct changes raised what the arena reflects — the
# stone albedo floor (carriageway 0.325 -> 0.490, tram bed 0.235 -> 0.476), the deck
# fascia's albedo_color climbing 0.283 -> 0.452 over six rounds, new surface maps, the
# detail-blend fix that made the fascia render at all. Not one of them touched the
# tonemap. But porto_daylight.tres says in its own first line that the daylight is made
# in the tonemap and not in any albedo, and the RUBRIC says "exposure-driven, not
# multiplier-driven" — and the corollary nobody had written down is that an exposure
# has to be RE-SOLVED when the multipliers move. Six rounds of multipliers moved and
# the exposure sat at the value that was solved for the first one.
#
# So this does not gate a picture, it gates an identity, and it fires on whichever
# stream breaks it. Two halves:
#
#   1. THE GREY CARD. A Lambertian 18% grey card lying flat on the deck, lit by this
#      rig, must land on the tonemapper's own middle grey. That is the textbook
#      definition of a correctly exposed frame and it makes tonemap_exposure derived
#      rather than dialled: exposure = 1 / E_h.
#
#   2. THE KNEE. The three large playable ground surfaces, at whatever albedo the
#      materials stream is currently delivering, must stay off the flat part of the
#      display transform. Measured through the shipped resource with a full-frame
#      unshaded quad at known scene-referred values (the table is in the tonemap block
#      of porto_daylight.tres): the curve carries 64-70 levels per stop below u = 0.18
#      and only 33-45 above u = 0.5. A surface pushed past the knee pays for its
#      brightness in its own texture and its own chroma, because both are DIFFERENCES
#      and the curve has stopped spending levels on differences up there. That is the
#      measured signature of the regression and not a guess: the near deck in
#      02_deck_eye lost 41% of its local contrast (CoV 0.199 -> 0.117) and 41% of its
#      saturation (0.124 -> 0.073) while gaining 55 levels of luminance.
#
# Both would have caught this the round it landed. At the shipped exposure of 0.72 the
# grey card sat +0.50 EV hot and all three ground surfaces sat at u = 0.64-0.74,
# a third of a stop past the knee.

## The tonemapper's own middle grey. Measured, not assumed: a full-frame flat field at
## u = 0.18 through this exact resource comes back at 125/255, which is where middle
## grey belongs. So the CURVE is not the problem and never was — only where the scene
## was being placed on it.
const AGX_MIDDLE_GREY := 0.18
## Reflectance of a photographic grey card. The reference surface, chosen because it is
## the one albedo in photography that means "correctly exposed" rather than "bright".
const GREY_CARD_ALBEDO := 0.18
## How far the grey card may drift from middle grey before this is a different picture,
## in stops. A third of a stop is under half the smallest exposure step anyone would
## make deliberately, and the fault this gate exists for was half a stop.
const GREY_CARD_TOLERANCE_EV := 0.33
## Tonemapper input above which the measured transfer falls under 45 levels per stop.
## See the table in porto_daylight.tres's tonemap block.
const TRANSFER_KNEE := 0.55


## The total irradiance an up-facing surface on the deck receives, from this stream's
## own constants and nothing else.
##
## The two bounce fills contribute exactly zero here and that is structural rather than
## incidental — QuayBounce arrives from below and RibeiraBounce is pinned to elevation
## 0.000 precisely so no warm term can reach a horizontal surface — so this asserts it
## rather than assuming it.
##
## SDFGI and SSIL are deliberately excluded. They are occluded terms that vary across
## the deck, so exposing for them means exposing for whichever patch of paving happens
## to be gathering the most bounce. They land on top of everything computed here, which
## is why the render is still checked rather than trusted.
func _horizontal_irradiance(env: Environment, sun_color: Color, sun_energy: float,
		elev: float) -> Dictionary:
	var key := _luma(sun_color) * sun_energy * sin(deg_to_rad(elev))
	var fill_total := 0.0
	var rig: Node3D = RigScript.new()
	for fill in [
		[RigScript.SKY_FILL_DIR, RigScript.SKY_FILL_COLOR, rig.sky_fill_energy, "SkyFill"],
		[RigScript.QUAY_BOUNCE_DIR, RigScript.QUAY_BOUNCE_COLOR, rig.bounce_energy,
			"QuayBounce"],
		[RigScript.RIBEIRA_BOUNCE_DIR, RigScript.RIBEIRA_BOUNCE_COLOR,
			rig.ribeira_bounce_energy, "RibeiraBounce"],
	]:
		var dir: Vector3 = (fill[0] as Vector3).normalized()
		var contribution: float = _luma(fill[1]) * float(fill[2]) * maxf(dir.dot(Vector3.UP), 0.0)
		if fill[3] != "SkyFill" and contribution > 0.0:
			_fail("%s reaches a horizontal deck at %.4f; both bounces are aimed so that they cannot"
					% [fill[3], contribution])
		fill_total += contribution
	rig.free()
	# ambient_light_energy as an upper bound on the flat term: with source SKY it is
	# that energy times the dome's own average radiance, which is under 1.
	return {
		"key": key,
		"fill": fill_total,
		"ambient": env.ambient_light_energy,
		"total": key + fill_total + env.ambient_light_energy,
	}


func _check_exposure_anchor(env: Environment) -> void:
	var packed: PackedScene = load(ARENA_PATH)
	if packed == null:
		_fail("could not load %s to re-derive the exposure anchor" % ARENA_PATH)
		return
	var state := packed.get_state()
	var sun_color := Color.WHITE
	var sun_energy := 0.0
	var elev := 0.0
	for i in state.get_node_count():
		if state.get_node_name(i) != "SunLight":
			continue
		var xf := Transform3D.IDENTITY
		for p in state.get_node_property_count(i):
			match state.get_node_property_name(i, p):
				"transform": xf = state.get_node_property_value(i, p)
				"light_color": sun_color = state.get_node_property_value(i, p)
				"light_energy": sun_energy = state.get_node_property_value(i, p)
		elev = rad_to_deg(asin(clampf(xf.basis.z.normalized().y, -1.0, 1.0)))
	if sun_energy <= 0.0:
		_fail("no SunLight energy found; the exposure anchor cannot be derived")
		return

	var terms := _horizontal_irradiance(env, sun_color, sun_energy, elev)
	var e_h: float = terms["total"]
	var solved := 1.0 / maxf(e_h, 1e-4)
	print("  horizontal E %.3f  (key %.3f + directional fill %.3f + ambient %.3f)"
			% [e_h, terms["key"], terms["fill"], terms["ambient"]])

	var card := GREY_CARD_ALBEDO * e_h * env.tonemap_exposure
	var drift := log(card / AGX_MIDDLE_GREY) / log(2.0)
	print("  grey card    18%% card on the deck lands at u %.3f, want %.3f  (%+.2f EV)"
			% [card, AGX_MIDDLE_GREY, drift])
	print("  exposure     %.3f shipped, %.3f solved as 1 / E   (tolerance %.2f EV)"
			% [env.tonemap_exposure, solved, GREY_CARD_TOLERANCE_EV])
	if absf(drift) > GREY_CARD_TOLERANCE_EV:
		_fail(("an 18%% grey card on the deck lands %+.2f EV off the tonemapper's middle "
				+ "grey. Something raised what the arena reflects and nobody re-solved "
				+ "tonemap_exposure; it wants %.3f, not %.3f.")
				% [drift, solved, env.tonemap_exposure])

	if _corridor_presents.is_empty():
		_fail("the corridor's delivered albedos were not measured; the knee cannot be checked")
		return
	for name in _corridor_presents:
		var u: float = float(_corridor_presents[name]) * e_h * env.tonemap_exposure
		print("  knee         %-12s presents %.3f -> u %.3f  (knee %.2f)"
				% [name, _corridor_presents[name], u, TRANSFER_KNEE])
		if u > TRANSFER_KNEE:
			_fail(("the %s sits at u %.3f, past the transfer's knee at %.2f. Above it the "
					+ "curve carries under 45 levels per stop, so the surface the game is "
					+ "played on is spending its own texture and chroma on being bright.")
					% [name, u, TRANSFER_KNEE])


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

	# (d) SURFACE-SCALE ALBEDO, new this round, and the answer to two of Round 1's
	# material findings: the deck cobble measured as one identical pinkish-mauve sett
	# repeated, and the ironwork as mean RGB (11, 16, 27) with a standard deviation of
	# 3. The fine layer is greyscale and gone by four metres, so neither could be fixed
	# there.
	for pair in [["stone", granite], ["cobblestone", ToonFactory.cobblestone()],
			["iron", painted], ["plaster", ToonFactory.plaster()]]:
		var m: StandardMaterial3D = pair[1]
		if m.albedo_texture == null:
			_fail("%s() has no surface-scale albedo map; its colour is one flat value"
					% pair[0])

	# The gain that keeps those maps a modulation rather than a tint. ToonFactory
	# measures it off a 96-square rasterisation of the noise field; this recomputes it
	# at 160, so a mismatch means either the factory's sample resolution has stopped
	# converging or the descriptors on disk have been regenerated into something it is
	# no longer reasoning about. Both have already happened once each -- see the note
	# above _albedo_map_gain in toon_factory.gd.
	#
	# Round 3 added the second half of this table: the CHANNEL CORRELATION each map
	# delivers. That is the property the round was spent buying, and without a gate on
	# it the next edit that quietly re-flattens a ramp passes silently -- which is
	# precisely how the game arrived at five stone surfaces measuring 0.88-0.995 in a
	# render with nothing in the tree saying anything was wrong.
	#
	# WHY THE THRESHOLDS ARE LOOSE. These are regression gates, not pins. A monotone
	# ramp -- every channel rising or falling together, which is what all five maps
	# were -- lands at +0.99 or above however wide its hue swing is, because R, G and
	# B are then all monotone functions of one scalar field. Anything under about 0.8
	# has real reversals in it. So the gate sits where the two populations separate,
	# and leaves a retune free to move inside it.
	for entry in [[ToonFactory.Surface.GRANITE, "granite", 0.80, 0.50],
			[ToonFactory.Surface.COBBLE, "cobble", 0.80, 0.50],
			[ToonFactory.Surface.IRON, "iron", 1.01, 1.01],
			[ToonFactory.Surface.PLASTER, "plaster", 0.85, 0.55]]:
		var surface: int = entry[0]
		var label: String = entry[1]
		var max_rg: float = entry[2]
		var max_rb: float = entry[3]
		var gain := ToonFactory._albedo_map_gain(surface)
		var measured: Variant = _map_stats(ToonFactory._ALBEDO_MAPS[surface])
		if measured == null:
			print("  %-10s gain %s   (texture not rasterised; mean unchecked)"
					% [label, gain.to_html(false)])
			continue
		var st: Dictionary = measured
		var mean: Color = st["mean"]
		var net := Color(gain.r * mean.r, gain.g * mean.g, gain.b * mean.b)
		print("  %-10s gain (%.3f %.3f %.3f) x mean (%.3f %.3f %.3f) = (%.3f %.3f %.3f)   corr r-g %+.3f r-b %+.3f   chroma %.3f"
				% [label, gain.r, gain.g, gain.b, mean.r, mean.g, mean.b, net.r, net.g,
					net.b, st["rg"], st["rb"], st["chroma"]])
		for ch in [net.r, net.g, net.b]:
			if absf(ch - 1.0) > 0.04:
				_fail("%s albedo map's gain leaves a net %.3f; it tints every %s surface in the game"
						% [label, ch, label])
		if absf(st["rg"]) > max_rg or absf(st["rb"]) > max_rb:
			_fail("%s albedo map is monochrome: channel correlation r-g %+.3f r-b %+.3f (limits %.2f / %.2f). Its variation multiplies all three channels together, so it is a grey mask and never becomes colour."
					% [label, st["rg"], st["rb"], max_rg, max_rb])

	# IRON IS DELIBERATELY EXEMPT from the correlation gate above (limits 1.01), and
	# it is the one map that should be. Its ramp runs intact paint -> chalked edge ->
	# oxide bloom, all three channels falling together, so it measures r-g +0.995 --
	# and it is also the only surface in either Round 2 frame the critic named as
	# behaving like real matter. The reason is amplitude, not correlation: rust is a
	# 0.41-linear chroma event between one end of the ramp and the other, three times
	# any stone's, so the hue difference is enormous even though the channels are
	# ordered. That is what a real oxide does and it is what gets asserted here
	# instead. Nothing about this pass touched the iron maps.
	var iron_st: Variant = _map_stats(ToonFactory._ALBEDO_MAPS[ToonFactory.Surface.IRON])
	if iron_st != null and (iron_st as Dictionary)["chroma"] < 0.25:
		_fail("the iron albedo map's chroma range is %.3f; rust has stopped being a colour event"
				% (iron_st as Dictionary)["chroma"])

	# (e) THE DECK MATERIAL. It is hand-written rather than built by the factory, and
	# Round 1 found out what that costs: detail_blend_mode was 2, the comment beside it
	# said 2 was MUL, and BlendMode 2 is SUB. ALBEDO - detail went negative across the
	# whole surface and clamped to black, which is why 14% of 01_deck_mid measured as
	# constant RGB (0, 1, 2) at standard deviation 0.0. Asserted by NAME so the enum
	# cannot be mis-copied again.
	var deck: StandardMaterial3D = load(DECK_MATERIAL_PATH)
	print("  deck .tres   detail blend %d (MUL is %d)  albedo %s  surface map %s"
			% [deck.detail_blend_mode, BaseMaterial3D.BLEND_MODE_MUL,
				deck.albedo_color.to_html(false),
				"yes" if deck.albedo_texture != null else "NO"])
	if deck.detail_blend_mode != BaseMaterial3D.BLEND_MODE_MUL:
		_fail("the deck material's detail blend is %d, not MUL (%d); its albedo will clamp to black"
				% [deck.detail_blend_mode, BaseMaterial3D.BLEND_MODE_MUL])
	if not deck.detail_enabled or deck.detail_albedo == null:
		_fail("the deck material lost its close-range detail layer")
	if deck.albedo_texture == null:
		_fail("the deck material has no surface-scale albedo map; the fascia is one flat value")

	# (e2) THE TWO NUMBERS THE 214-PIXEL TILE WAS HIDING IN, asserted because both were
	# invisible to every check this file had.
	#
	# The fascia autocorrelated at lag 214 px with r = 0.849 on G/R — six repeats across
	# 01_deck_mid, on the largest surface in the frame — while carrying a 7% non-monotone
	# vertical swing, i.e. no normal doing any work at all. Both are properties of THIS
	# material rather than of the map it wears, and both are one number:
	#
	#   uv1_scale must be ANISOTROPIC. The repeat period in metres IS 1/uv1_scale.x, and
	#   a square tile on a 100 m x 1.96 m band can only be as long as it is tall. Making
	#   x and y independent is what buys a 8.0 m horizontal period (about 580 px in that
	#   shot, 2.2 repeats) with 0.5 m courses on a 4.0 m vertical tile the band only
	#   shows half of.
	#
	#   normal_scale must be enough to survive the fine layer stacking at 0.55. The old
	#   0.34 was correct for the granite normal — 19 cm igneous speckle, which is gravel
	#   at deck scale — and is nowhere near enough for a masonry joint, which is form.
	print("  deck tiling  uv1_scale %s -> %.1f m across, %.1f m up   normal_scale %.2f"
			% [str(deck.uv1_scale), 1.0 / maxf(deck.uv1_scale.x, 0.001),
				1.0 / maxf(deck.uv1_scale.y, 0.001), deck.normal_scale])
	if absf(deck.uv1_scale.y / maxf(deck.uv1_scale.x, 0.0001) - 1.0) < 0.2:
		_fail("the deck fascia tiles isotropically at %.2f m; a square tile on a 100 x 1.96 m band repeats every %.2f m, which measured as a visible 214 px period"
				% [1.0 / maxf(deck.uv1_scale.x, 0.001), 1.0 / maxf(deck.uv1_scale.x, 0.001)])
	if 1.0 / maxf(deck.uv1_scale.x, 0.001) < 6.0:
		_fail("the deck fascia's horizontal tile is %.1f m; the measured visible repeat was at 2.94 m and the frame holds six of them"
				% (1.0 / maxf(deck.uv1_scale.x, 0.001)))
	if deck.normal_scale < 0.6:
		_fail("the deck fascia's normal_scale is %.2f; the fine layer blends over it at 0.55, so the masonry joints do not survive to the frame and the band is a colour wash again"
				% deck.normal_scale)
	if deck.normal_texture != load(DECK_NORMAL_MAP_PATH):
		_fail("the deck fascia is not wearing the masonry normal; its relief is speckle, which is sub-pixel at the 14 m the band sits from the camera")

	# WHAT THIS ASSERTION IS FOR, restated in Round 3 because the old form stopped
	# being the honest test.
	#
	# It used to compare albedo_color against authored x DETAIL_ALBEDO_GAIN x
	# _albedo_map_gain, on the red channel only. That checked that the hand-written
	# .tres agreed with the factory's arithmetic -- but the factory's arithmetic was
	# also the thing under test, so the two could drift together and still pass, and
	# a single-channel compare could not see a map that had gone chromatic. It also
	# failed the moment the albedo maps stopped being monochrome, which is the change
	# this round exists to make: the three gains now differ by 3%, so albedo_color is
	# deliberately warmer than the colour it stands for and no hex constant means
	# anything on its own.
	#
	# The property that actually matters is end-to-end and survives hue-varying
	# albedo: THE MEAN ALBEDO THE SURFACE PRESENTS EQUALS THE COLOUR THAT WAS
	# AUTHORED, per channel. albedo_color is multiplied by two texture layers before
	# it reaches the frame, so
	#
	#     albedo_color[c] x surface_map_mean[c] x fine_net_mean  ==  authored[c]
	#
	# is the invariant, and it is measured from the live descriptors on both sides
	# rather than recomputed from the same constants the material was built with.
	# That is strictly stronger: it fails if the .tres drifts, if a ramp is
	# regenerated darker or lighter, if the per-channel gain stops being per-channel,
	# or if DETAIL_ALBEDO_GAIN stops being the reciprocal of what the fine layer
	# actually does -- none of which the old form could see.
	#
	# 3% tolerance: the two means are Monte-Carlo'd off 160-square and 128-square
	# rasterisations of different noise fields, and the factory's own gain is measured
	# at 96, so a couple of percent is sampling noise rather than drift. A real
	# mistake here is 10% or more -- every one this file has caught was.
	# ROUND 4 EXTENDS IT TO THE FACTORY PATH, which is the half that was missing and the
	# half that now carries a guard. The invariant below was only ever asserted on the
	# ONE hand-written material, so ToonFactory's own arithmetic — three chained
	# corrections, two of them per-channel — was checked nowhere. That mattered less
	# when the corrections were only the two texture gains; PORTO_STONE_FLOOR is a third
	# one that changes the colour a call site gets, so "what does a call site actually
	# get" has to be a measured quantity rather than a described one. _presents() is the
	# same end-to-end measurement and both callers use it.
	var fine_net: Variant = _fine_net_mean()
	var deck_map: Variant = _map_stats(load(DECK_ALBEDO_MAP_PATH))
	if deck_map == null or fine_net == null:
		_fail("the deck material's texture means could not be measured; the check would pass vacuously")
	else:
		var map_mean: Color = (deck_map as Dictionary)["mean"]
		var fnet: Color = fine_net
		var presented := Color(
			deck.albedo_color.r * map_mean.r * fnet.r,
			deck.albedo_color.g * map_mean.g * fnet.g,
			deck.albedo_color.b * map_mean.b * fnet.b)
		print("  deck mean    albedo_color x surface map x fine layer = (%.4f %.4f %.4f)  vs authored (%.4f %.4f %.4f)"
				% [presented.r, presented.g, presented.b,
					DECK_AUTHORED.r, DECK_AUTHORED.g, DECK_AUTHORED.b])
		for pair in [["R", presented.r, DECK_AUTHORED.r], ["G", presented.g, DECK_AUTHORED.g],
				["B", presented.b, DECK_AUTHORED.b]]:
			var got: float = pair[1]
			var want: float = pair[2]
			if absf(got - want) > want * 0.03:
				_fail("the deck fascia presents %s = %.4f where %.4f was authored (%.1f%% off). albedo_color %s no longer carries both texture layers' means."
						% [pair[0], got, want, 100.0 * (got / want - 1.0),
							deck.albedo_color.to_html(false)])
		# The masonry map is a one-material map set, so nothing in the factory's own
		# table gates it. It is the largest single surface in 01_deck_mid and the round
		# was partly spent on it, so it gets the same correlation gate the four factory
		# maps get, at the same limits.
		var mst: Dictionary = deck_map
		print("  masonry map  mean (%.3f %.3f %.3f)   corr r-g %+.3f r-b %+.3f   chroma %.3f"
				% [map_mean.r, map_mean.g, map_mean.b, mst["rg"], mst["rb"], mst["chroma"]])
		if absf(mst["rg"]) > 0.80 or absf(mst["rb"]) > 0.50:
			_fail("the deck fascia's masonry map is monochrome: r-g %+.3f r-b %+.3f. Its variation multiplies all three channels together, so it is a grey mask and never becomes colour."
					% [mst["rg"], mst["rb"]])
		# ...and the other way round, which is this surface's OWN measurement rather
		# than Round 3's: the critic measured (R-G) sd 8.08 against L sd 10.74 on this
		# band and called it a camouflage pattern. Decorrelating the channels must not
		# be paid for with more colour on the one surface that was already too colourful,
		# so this map's per-texel chroma is held under the granite map it replaced.
		var granite_chroma: Variant = _map_stats(
				ToonFactory._ALBEDO_MAPS[ToonFactory.Surface.GRANITE])
		if granite_chroma != null and mst["chroma"] > (granite_chroma as Dictionary)["chroma"]:
			_fail("the masonry map's chroma %.3f now exceeds granite's %.3f; the fascia's variation was already 75%% hue and this makes it more so"
					% [mst["chroma"], (granite_chroma as Dictionary)["chroma"]])

	# THE FINE LAYER'S THREE CHANNEL MEANS MUST BE EQUAL, and this is new because the
	# layer is new: Round 3 made it chromatic, and it is SHARED by every textured
	# material in the game while being corrected by ONE SCALAR
	# (ToonFactory.DETAIL_ALBEDO_GAIN) rather than by a per-channel gain. So a fine
	# ramp that averages 2% warm tints the ironwork, the azulejos, the terracotta and
	# forty facade colours at once, and nothing downstream divides it back out. The
	# surface maps are free to average any colour they like; this one is not.
	if fine_net != null:
		var fnet2: Color = fine_net
		var lo: float = minf(fnet2.r, minf(fnet2.g, fnet2.b))
		var hi: float = maxf(fnet2.r, maxf(fnet2.g, fnet2.b))
		print("  fine mean    net multiplier (%.4f %.4f %.4f)   spread %.2f%%   1/mean %.4f vs DETAIL_ALBEDO_GAIN %.4f"
				% [fnet2.r, fnet2.g, fnet2.b, 100.0 * (hi / lo - 1.0),
					3.0 / (fnet2.r + fnet2.g + fnet2.b), ToonFactory.DETAIL_ALBEDO_GAIN])
		if hi / lo - 1.0 > 0.02:
			_fail("the shared fine layer averages %.2f%% off neutral; it tints every textured material in the game and one scalar gain cannot undo it"
					% (100.0 * (hi / lo - 1.0)))
		# ...and DETAIL_ALBEDO_GAIN must be its reciprocal, which nothing asserted
		# before. If it is not, every authored colour in the game is off by the
		# difference -- silently, because the error is a uniform scale.
		var ideal: float = 3.0 / (fnet2.r + fnet2.g + fnet2.b)
		if absf(ToonFactory.DETAIL_ALBEDO_GAIN / ideal - 1.0) > 0.03:
			_fail("DETAIL_ALBEDO_GAIN is %.4f but the fine layer's measured mean wants %.4f; every authored colour is scaled %.1f%% wrong"
					% [ToonFactory.DETAIL_ALBEDO_GAIN, ideal,
						100.0 * (ToonFactory.DETAIL_ALBEDO_GAIN / ideal - 1.0)])

	# (f) THE PLAYABLE CORRIDOR MAY NOT BE THE DARKEST THING IN FRAME, and this is the
	# gate for the strongest converging finding this project has had: two critics, five
	# frames, no knowledge of each other, both measuring the deck as the darkest region
	# in every shot they were given, against a RUBRIC line that requires it to be the
	# brightest.
	#
	# It is albedo and not light. Top quartile against top quartile — which removes the
	# parapet's shadow bands from both populations — the carriageway returned 52% of the
	# footway thirty pixels behind it, and the authored constants agree: 0.325 and 0.235
	# against 0.545 and 0.580.
	#
	# Measured END TO END through _presents(), not by reading PORTO_STONE_FLOOR back out
	# of the factory and doing its arithmetic here. That distinction is the whole value
	# of the check: the guard is three chained corrections deep (ceiling, then the knee,
	# then two per-channel texture gains), and a version of this that recomputed the
	# knee would pass while the gains quietly undid it. This one fails if ANY of the
	# five stages stops composing.
	if fine_net != null:
		var walk := _presents(ToonFactory.cobblestone(FLAG_COLOR), ToonFactory.Surface.COBBLE,
				fine_net)
		var kerb := _presents(ToonFactory.stone(KERB_COLOR), ToonFactory.Surface.GRANITE,
				fine_net)
		var road := _presents(ToonFactory.stone(ROADWAY_COLOR), ToonFactory.Surface.GRANITE,
				fine_net)
		var tram := _presents(ToonFactory.cobblestone(TRAMBED_COLOR),
				ToonFactory.Surface.COBBLE, fine_net)
		# THE FOOTWAY is the reference, not the kerb, and the distinction is the
		# critic's rather than a convenience. What was measured was "the near cobble
		# apron at L 53.7 against the SLAB PAVING thirty pixels behind it at L 133.4" —
		# two large coplanar surfaces. The kerbstone is a 30 cm trim on the edge between
		# them and it is SUPPOSED to be the brightest line on the deck: it is freshly
		# dressed granite that nothing drives over. Holding a hundred square metres of
		# carriageway to within 15% of a kerb would be asking for a deck with no tonal
		# structure left in it at all. Printed anyway, because a kerb that stops leading
		# is its own defect.
		var reference := _luma(walk)
		# Handed to _check_exposure_anchor(): these three are the ground the game is
		# played on, and what the tonemap has to be solved against.
		_corridor_presents = {
			"carriageway": _luma(road),
			"tram bed": _luma(tram),
			"footway": reference,
		}
		print("  corridor     carriageway %.3f  tram bed %.3f  vs footway %.3f (kerb trim %.3f)"
				% [_luma(road), _luma(tram), reference, _luma(kerb)])
		print("               ratios %.2f and %.2f (want >= %.2f; measured 0.52 in the render before the floor)"
				% [_luma(road) / maxf(reference, 1e-4), _luma(tram) / maxf(reference, 1e-4),
					CORRIDOR_MIN_RATIO])
		if _luma(kerb) <= reference:
			_fail("the kerb presents %.3f against the footway's %.3f; the kerb line is the deck's brightest edge and it has stopped leading"
					% [_luma(kerb), reference])
		for pair in [["carriageway", _luma(road)], ["tram bed", _luma(tram)]]:
			var got: float = pair[1]
			if got / maxf(reference, 1e-4) < CORRIDOR_MIN_RATIO:
				_fail("the %s presents %.3f against the walkway's %.3f — %.0f%% of it. The playable corridor is the darkest surface in the frame and the RUBRIC requires it to be the brightest."
						% [pair[0], got, reference, 100.0 * got / maxf(reference, 1e-4)])
		# And the guard has to be a FLOOR rather than a repaint: it must leave the
		# walkway exactly where its author put it, or it is just a global brightness
		# knob with a physics comment on it.
		var walk_authored := _presents_target(FLAG_COLOR)
		if absf(_luma(walk) / maxf(_luma(walk_authored), 1e-4) - 1.0) > 0.03:
			_fail("the stone floor moved the footway by %.0f%%; it is meant to be exactly the identity at and above PORTO_STONE_KNEE"
					% (100.0 * (_luma(walk) / maxf(_luma(walk_authored), 1e-4) - 1.0)))
		# The other side of the same requirement, and the reason for the chroma test:
		# stone() is also how the terrain stream dresses bare EARTH, which really is
		# darker than granite. Lifting it would be inventing a claim rather than
		# enforcing one.
		var earth := ToonFactory.stone(Color(0.33, 0.28, 0.21))
		var earth_authored := _presents_target(Color(0.33, 0.28, 0.21))
		var earth_got := _presents(earth, ToonFactory.Surface.GRANITE, fine_net)
		print("  earth        presents %.3f vs authored %.3f (the chroma test must exempt it)"
				% [_luma(earth_got), _luma(earth_authored)])
		if absf(_luma(earth_got) / maxf(_luma(earth_authored), 1e-4) - 1.0) > 0.03:
			_fail("the stone floor lifted bare earth by %.0f%%; dry earth reflects 0.20-0.35 and the floor is a claim about quarried grey stone"
					% (100.0 * (_luma(earth_got) / maxf(_luma(earth_authored), 1e-4) - 1.0)))

	# (g) NOTHING ON THIS BRIDGE IS A MIRROR. The tram rail head has been named as the
	# frame's single blind-test tell in Round 1, rebuilt as real grooved track in
	# Round 2, and measured still pure blue in Round 3: RGB (32, 64, 109) at saturation
	# 0.70 against warm-grey neighbours at 0.19-0.33.
	#
	# The cause is two properties of the material and both are asserted here. A metal
	# has no diffuse term, so a smooth one returns its environment and nothing else, and
	# the only thing in a rail crown's environment at a grazing view down the deck is
	# sky. So: bare metal gets a roughness floor, and it gets a per-texel metal/oxide
	# split so part of the crown is a dielectric with a diffuse term in its own iron
	# colour. Neither is visible from the scalar `metallic` the old rule (c) checked.
	var crown := ToonFactory.iron(Color(0.560, 0.545, 0.520), 0.6, 1.0, 0.30)
	print("  bare metal   rough %.2f (floor %.2f)  metallic map %s ch %d  mask %s"
			% [crown.roughness, ToonFactory.METAL_ROUGHNESS_FLOOR,
				"yes" if crown.metallic_texture != null else "NO",
				crown.metallic_texture_channel,
				"" if crown.roughness_texture == null
					else crown.roughness_texture.resource_path.get_file()])
	if crown.roughness < ToonFactory.METAL_ROUGHNESS_FLOOR - 0.001:
		_fail("a bare metal came out at roughness %.2f; below %.2f its specular lobe is narrow enough that the only thing in it is sky, which is the rail head defect verbatim"
				% [crown.roughness, ToonFactory.METAL_ROUGHNESS_FLOOR])
	if crown.metallic_texture == null:
		_fail("bare metal has no metal/oxide split; the whole crown is a mirror and a mirror over a deck returns the sky")
	elif crown.metallic_texture_channel != BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
		_fail("the metal/oxide split reads channel %d; it is authored into the mask's BLUE channel"
				% crown.metallic_texture_channel)
	if crown.roughness_texture == crown.metallic_texture and crown.metallic_texture != null:
		var steel: NoiseTexture2D = crown.metallic_texture
		var ramp: Gradient = steel.color_ramp
		# "Metals are 0 or 1" applies to the MAP as well as to the scalar, at the only
		# resolution a map can obey it: every stop is 0 or 1, and the crossing is narrow
		# enough that the mip chain, not the ramp, is what blurs it.
		var lo := 1.0
		var hi := 0.0
		var metal_frac := 0.0
		for i in ramp.colors.size():
			var v: float = ramp.colors[i].b
			if v > 0.001 and v < 0.999:
				_fail("the metal/oxide ramp has a stop at %.3f; a metallic map is 0 or 1 per texel"
						% v)
			if v > 0.5:
				metal_frac = maxf(metal_frac, ramp.offsets[i])
			lo = minf(lo, ramp.offsets[i] if v > 0.5 else lo)
			hi = maxf(hi, v)
		if hi < 0.999:
			_fail("the metal/oxide ramp never reaches 1; a bare metal that is nowhere metal is a dielectric with a lie on it")
		print("  metal split  bare steel below t = %.2f, oxide above; ramp stops %s"
				% [metal_frac, str(ramp.offsets)])
	# Painted iron must NOT pick any of this up. It is metallic 0, so the map would be
	# multiplied by zero anyway, but paying for three triplanar taps to do that is the
	# kind of thing that is never noticed.
	if painted.metallic_texture != null:
		_fail("painted iron carries a metallic map it multiplies by zero; that is three triplanar taps for nothing")
	if painted.roughness_texture == crown.roughness_texture:
		_fail("painted iron is wearing the steel mask; its 0.22-1.00 gloss spread is the ironwork's specular return and the steel mask does not have one")

	# The cache is what collapses two hundred facades onto a handful of materials.
	# Snapping metallic before the key is built is supposed to make it collapse
	# harder, not softer: two call sites asking for different half-metals now share.
	var a := ToonFactory.iron(ToonFactory.IRON_GREY, 1.6, 0.30, 0.62)
	var b := ToonFactory.iron(ToonFactory.IRON_GREY, 1.6, 0.45, 0.62)
	print("  cache        iron(0.30) and iron(0.45) share a material: %s"
			% ["yes" if a == b else "NO"])
	if a != b:
		_fail("metallic snap happens after the cache key, so it costs a draw call")


## What a finished material's surface actually presents, per channel: albedo_color
## multiplied by the mean of both texture layers, measured off the live descriptors.
##
## This is the same quantity the deck fascia's invariant computes, factored out so the
## factory path can be held to it too. Doing it this way rather than re-deriving
## ToonFactory's arithmetic is the whole point — the factory chains a ceiling, a floor,
## a knee and two per-channel texture gains, and a check that recomputed that chain
## would agree with a bug in it.
func _presents(mat: StandardMaterial3D, surface: int, fine_net: Color) -> Color:
	var stats: Variant = _map_stats(ToonFactory._ALBEDO_MAPS[surface])
	var map_mean := Color(1.0, 1.0, 1.0)
	if stats != null:
		map_mean = (stats as Dictionary)["mean"]
	return Color(mat.albedo_color.r * map_mean.r * fine_net.r,
			mat.albedo_color.g * map_mean.g * fine_net.g,
			mat.albedo_color.b * map_mean.b * fine_net.b)


## What a call site's colour SHOULD present if no guard moved it: itself, with only the
## physical ceiling applied. The floor and the knee are the things under test, so they
## deliberately are not reproduced here.
func _presents_target(authored: Color) -> Color:
	var peak: float = maxf(authored.r, maxf(authored.g, authored.b))
	if peak > ToonFactory.ALBEDO_CEILING and peak > 0.0:
		return authored * (ToonFactory.ALBEDO_CEILING / peak)
	return authored


## The per-channel mean of a NoiseTexture2D's ramped output, in LINEAR.
##
## Rebuilt from the descriptor's own Noise and Gradient rather than read off
## tex.get_image(), and that is not stubbornness: NoiseTexture2D rasterises on the
## WorkerThreadPool and get_image() returns null until it lands, so headless — which is
## where this probe runs — would silently skip the check every single time.
##
## 160 x 160 against ToonFactory's 96 x 96, through ToonFactory.sample_noise() so the
## frequency-scaling rule that keeps the sample over the whole field has exactly one
## implementation. The check is therefore a convergence test on the factory's sample
## resolution, and it has already earned its place twice this round: it caught a
## uniform ramp integral that was 10% off on iron, and then a sample window that was 9%
## off on cobble.
##
## Returns null only if the descriptor is missing a piece, in which case the caller
## says so rather than passing vacuously.
## Returns { mean: Color, rg: float, rb: float, chroma: float } or null.
##
## `rg` / `rb` are the per-channel correlations of the linear colour the map
## delivers over its own noise histogram — the Round 3 metric. They are computed
## here rather than read from generate_detail_maps.gd's own report for the same
## reason the mean is: that script is an authoring tool that is not run in CI, and
## a gate that trusts the tool it is gating is not a gate.
func _map_stats(tex: NoiseTexture2D) -> Variant:
	if tex == null or tex.color_ramp == null:
		return null
	var size := 160
	var img := ToonFactory.sample_noise(tex, size)
	if img == null:
		return null
	var ramp: Gradient = tex.color_ramp
	var s := [0.0, 0.0, 0.0]
	var ss := [0.0, 0.0, 0.0]
	var s_rg := 0.0
	var s_rb := 0.0
	var chroma := 0.0
	for y in size:
		for x in size:
			# The noise image is greyscale, so its red channel IS the field value, and
			# that value is what NoiseTexture2D feeds the gradient. The albedo sampler
			# carries a source_color hint, so what multiplies ALBEDO is the LINEAR
			# value of an sRGB-authored stop.
			var c := ramp.sample(img.get_pixel(x, y).r).srgb_to_linear()
			s[0] += c.r
			s[1] += c.g
			s[2] += c.b
			ss[0] += c.r * c.r
			ss[1] += c.g * c.g
			ss[2] += c.b * c.b
			s_rg += c.r * c.g
			s_rb += c.r * c.b
			chroma = maxf(chroma, maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)))
	var n := float(size * size)
	var m := [s[0] / n, s[1] / n, s[2] / n]
	var sd: Array[float] = []
	for ch in 3:
		sd.append(sqrt(maxf(ss[ch] / n - m[ch] * m[ch], 0.0)))
	return {
		"mean": Color(m[0], m[1], m[2]),
		"rg": (s_rg / n - m[0] * m[1]) / maxf(sd[0] * sd[1], 1e-9),
		"rb": (s_rb / n - m[0] * m[2]) / maxf(sd[0] * sd[2], 1e-9),
		"chroma": chroma,
	}


## The per-channel mean of what the shared fine layer actually multiplies ALBEDO by.
##
## Not the ramp's mean: Godot's detail pass is
##     detail = mix(ALBEDO, ALBEDO * detail_tex.rgb, detail_tex.a)
## so the NET multiplier is (1 - a) + a * c, with `a` the map's own alpha. That is
## the quantity DETAIL_ALBEDO_GAIN is the reciprocal of, and measuring the ramp
## without the blend would be 45% wrong.
##
## 128-square rather than 160: this field is a 3-octave simplex at 0.032, an order of
## magnitude smoother than the cellular maps, and it converges long before there.
func _fine_net_mean() -> Variant:
	var tex: NoiseTexture2D = ToonFactory._FINE_ALBEDO
	if tex == null or tex.color_ramp == null:
		return null
	var size := 128
	var img := ToonFactory.sample_noise(tex, size)
	if img == null:
		return null
	var ramp: Gradient = tex.color_ramp
	var a: float = ramp.colors[0].a
	var sum := Color(0.0, 0.0, 0.0)
	for y in size:
		for x in size:
			var c := ramp.sample(img.get_pixel(x, y).r).srgb_to_linear()
			sum += Color(1.0 - a + a * c.r, 1.0 - a + a * c.g, 1.0 - a + a * c.b)
	var n := float(size * size)
	return Color(sum.r / n, sum.g / n, sum.b / n)


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
	# The near end of the same requirement, and it is the one that matters now that the
	# ramp was pulled in from 40 m to 18 m to carry the aerial perspective. Everything
	# playable happens inside 40 m of the camera.
	var near := _depth(40.0, env.fog_depth_begin, env.fog_depth_end,
			env.fog_depth_curve, env.fog_density)
	var near_v := 1.0 - exp(-env.volumetric_fog_density * 40.0)
	var near_total := near * (1.0 - near_v) + near_v
	print("  playable corridor (40 m): %.1f%% haze" % (near_total * 100.0))
	if near_total > 0.09:
		_fail("%.1f%% haze at 40 m; the playable corridor is being veiled" % (near_total * 100.0))
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
	# 0.08 -> 0.16. Round 1 measured the background at twice the deck's luminance and
	# 2.5x its saturation with only 12% of veil on it at 100 m, so the old floor was
	# passing a frame whose focal hierarchy was inverted. Depth has to come from value
	# compression and desaturation toward the sky -- explicitly NOT from more distance
	# blur, which softens the arch (the identity anchor) while leaving the disposable
	# background sharp.
	if mid_total < 0.16:
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


# --- The river reflects ------------------------------------------------------

## Round 3's leading finding, as two invariants that can be checked without a GPU.
##
## Both critics measured that the Douro returns nothing: a three-band sample across
## shot 07 varied under 8% between water under bright terraces, open mid-span, and
## water under a dark cliff, and the trend ran BACKWARDS — brightest under the
## darkest bank. A large iron arch stood over calm water in shot 06 and did not
## appear in it.
##
## 1. THE RAY MARCH HAS TO SURVIVE ITS OWN LENGTH. Godot's SSR fades a hit by
##    pow(1 - progress, ssr_fade_out) where `progress` is how far along the march the
##    hit was found, so ssr_fade_out is an EXPONENT and not a distance. It was 6.0
##    under a comment calling it a distance and claiming it made "the far half of the
##    reflection survive": a hit at the halfway point was multiplied by 0.5^6 = 0.016,
##    i.e. deleted. Anything reflected off water seen at a grazing angle is found late
##    in the march by construction — the reflected ray is nearly parallel to the
##    surface — so this term selected against exactly the case it was tuned for.
##
## 2. THE BODY MUST NOT SWAMP THE MIRROR. A water surface returns 4-15% of what it
##    reflects at these view angles. If its own diffuse albedo returns more than that,
##    no reflection can be seen however well SSR works, and the water's brightness
##    stops depending on what is above it — which is precisely the flat 8% spread the
##    critics measured. Checked as a ratio against what the water is reflecting rather
##    than as an absolute, so a retune of the palette does not have to come here.
const SSR_MIDMARCH_MIN := 0.15
## Body albedo as a fraction of the mirror colour it sits under. Real river water is
## well under a tenth; 0.25 is a generous ceiling that still fails the 0.19-luminance
## blue-grey that shipped for three rounds.
const WATER_BODY_RATIO_MAX := 0.25


func _check_reflection(env: Environment) -> void:
	if not env.ssr_enabled:
		_fail("ssr_enabled is off; nothing can put the arch in the water on Forward+")
	var survives_mid := pow(0.5, env.ssr_fade_out)
	var survives_quarter := pow(0.75, env.ssr_fade_out)
	print("  ssr fade_out %.2f (an exponent): a hit 25%% along the march keeps %.3f, "
			% [env.ssr_fade_out, survives_quarter] + "50%% along keeps %.3f" % survives_mid)
	print("  ssr max_steps %d  fade_in %.2f  depth_tolerance %.2f"
			% [env.ssr_max_steps, env.ssr_fade_in, env.ssr_depth_tolerance])
	if survives_mid < SSR_MIDMARCH_MIN:
		_fail("ssr_fade_out %.2f deletes any reflection found past the first third of "
				% env.ssr_fade_out + "the march (%.3f survives at the midpoint); grazing "
				% survives_mid + "water finds everything late")

	var mat := _river_material()
	if mat == null:
		_fail("no ShaderMaterial in %s running water_wave.gdshader" % ARENA_PATH)
		return
	var body: Color = _water_param(mat, "deep_color", Color(0, 0, 0))
	var mirror: Color = _water_param(mat, "shallow_color", Color(1, 1, 1))
	var albedo_mix: float = float(_water_param(mat, "mirror_albedo", 0.14))
	var ratio := _luma(body) / maxf(_luma(mirror), 0.0001)
	print("  water body %s (luma %.3f) against mirror %s (luma %.3f) — ratio %.3f"
			% [body.to_html(false), _luma(body), mirror.to_html(false), _luma(mirror), ratio])
	print("  mirror carried in ALBEDO %.2f; the rest is SSR / the radiance cubemap"
			% albedo_mix)
	if ratio > WATER_BODY_RATIO_MAX:
		_fail("the water's own body returns %.0f%% of what it reflects; a reflection "
				% (ratio * 100.0) + "worth 4-15%% Fresnel cannot be seen over that")
	if albedo_mix > 0.25:
		_fail("mirror_albedo %.2f paints most of the mirror as flat colour, which is "
				% albedo_mix + "the term that made the water brightest under the darkest bank")


## Mat_river, found by shader identity rather than by node name.
func _river_material() -> ShaderMaterial:
	var packed: PackedScene = load(ARENA_PATH)
	if packed == null:
		return null
	var state := packed.get_state()
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			var mat = state.get_node_property_value(i, p)
			if not (mat is ShaderMaterial):
				continue
			var shader: Shader = (mat as ShaderMaterial).shader
			if shader != null and shader.resource_path == WATER_SHADER_PATH:
				return mat as ShaderMaterial
	return null


## A uniform as the RUNNING material sees it: the scene's override if it sets one,
## the shader's own default if it does not. Reading only one of the two is how
## Mat_river's sun vector stayed 121 degrees stale for three rounds while this probe
## passed.
func _water_param(mat: ShaderMaterial, uniform_name: String, fallback: Variant) -> Variant:
	var authored = mat.get_shader_parameter(uniform_name)
	if authored != null:
		return authored
	var value = _shader_default(mat.shader.code, uniform_name)
	return fallback if value == null else value


## `uniform <type> <name> [: hint] = <literal>;` out of shader source. Handles the
## float and vec4-as-colour forms this stream authors; returns null for anything
## else so the caller can fall back rather than assert on a parse it did not expect.
func _shader_default(code: String, uniform_name: String) -> Variant:
	var re := RegEx.new()
	re.compile("uniform\\s+(\\w+)\\s+%s\\s*(?::[^=]*)?=\\s*([^;]+);" % uniform_name)
	var m := re.search(code)
	if m == null:
		return null
	var kind := m.get_string(1)
	var body := m.get_string(2).strip_edges()
	if kind == "float":
		return float(body)
	if kind == "vec4" or kind == "vec3":
		var inner := body.substr(body.find("(") + 1)
		inner = inner.substr(0, inner.rfind(")"))
		var parts := inner.split(",")
		if parts.size() >= 3:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return null


# --- The river meets a bank --------------------------------------------------

## water_wave.gdshader draws its shore foam from an ANALYTIC description of the quay
## line, because a shader has no way to ask the terrain where the bank is. That is
## the same shape of dependency as Mat_river's hand-copied sun vector, which went
## stale for three rounds, so it gets the same treatment: the model is evaluated
## against TerrainBuilder's own front_x() along the whole modelled reach and fails
## when the two stop describing the same wall.
##
## The tolerance is the jog. front_x() wanders the wall in and out by up to `jog`
## metres per level (0.55 on Porto's cais, 0.50 on Gaia's) in piecewise-constant
## runs, and the shader deliberately models the straight line rather than the jog —
## a two-metre foam band does not need to follow a half-metre return. Anything
## larger than that means the channel itself moved.
const SHORE_TOLERANCE := 1.2


func _check_shoreline() -> void:
	var mat := _river_material()
	if mat == null:
		_fail("no river material; the shore model cannot be checked")
		return
	var half: float = float(_water_param(mat, "shore_half_width", 52.0))
	var taper: float = float(_water_param(mat, "shore_taper", 0.028))
	var z_min: float = float(_water_param(mat, "shore_z_min", -128.0))
	var z_max: float = float(_water_param(mat, "shore_z_max", 46.0))
	var band: float = float(_water_param(mat, "shore_band", 2.6))
	print("  shader models the quay at |x| = %.1f + %.4f z over z in [%.0f, %.0f], "
			% [half, taper, z_min, z_max] + "band %.1f m" % band)

	var worst := 0.0
	var worst_z := 0.0
	var worst_side := 0.0
	for side in [TerrainBuilder.PORTO, TerrainBuilder.GAIA]:
		var z := z_min
		while z <= z_max:
			var real: float = absf(TerrainBuilder.front_x(side, 0, z))
			var modelled := half + taper * clampf(z, z_min, z_max)
			var err: float = absf(real - modelled)
			if err > worst:
				worst = err
				worst_z = z
				worst_side = side
			z += 4.0
	print("  worst disagreement with TerrainBuilder.front_x  %.2f m at z = %.0f on %s"
			% [worst, worst_z, "Porto" if worst_side < 0.0 else "Gaia"])
	if worst > SHORE_TOLERANCE:
		_fail("the shore model is %.2f m off the quay TerrainBuilder actually builds at "
				% worst + "z = %.0f; the foam band is in open water" % worst_z)

	# The reach has to match too, or the band either stops short of the modelled
	# bank or lays foam across open river past the headland.
	if absf(z_min - TerrainBuilder.BANK_Z_FAR) > 1.0:
		_fail("shore_z_min %.0f is not TerrainBuilder.BANK_Z_FAR %.0f"
				% [z_min, TerrainBuilder.BANK_Z_FAR])
	if absf(z_max - TerrainBuilder.HEADLAND_Z) > 1.0:
		_fail("shore_z_max %.0f is not TerrainBuilder.HEADLAND_Z %.0f"
				% [z_max, TerrainBuilder.HEADLAND_Z])
	if band <= 0.5:
		_fail("shore_band %.2f m is under a pixel at the 60 m the quay sits at in shot 07"
				% band)


# --- Contact darkening -------------------------------------------------------

## Round 3 raised ssao_light_affect 0.15 -> 0.50 for contact darkening and a critic
## then measured no dip in the paving under either lamp standard or the bollard. This
## pass answered why, in an isolated render rather than by argument: a plane, three
## posts of 0.12 / 0.30 / 0.80 m diameter and a wall corner, the same key, ambient and
## grade as the arena, rendered with SSAO on and off and differenced.
##
##   ambient-only control (key off)   post 0.12 m  -2.55 L (3.0%)   corner  -7.90 L
##   the shipping rig                 post 0.12 m  -0.19 L (0.2%)   corner  -1.96 L
##   5x intensity, light_affect 1.0   post 0.12 m  -0.78 L (0.7%)   corner  -8.82 L (17%)
##
## So SSAO IS generating occlusion at radius 0.9, and its SHAPE is right — a contact
## halo is plainly visible at every post base when the difference is amplified. Its
## MAGNITUDE under this rig is 0.2% of the pixel, against paving whose own texture
## deviation is 10-15 L. It is a sixth of one standard deviation of the noise it is
## drawn on, which is why raising light_affect changed nothing measurable and why
## raising it further cannot: at the setting that finally plants a lamp post, every
## inside corner in the frame has become a dirt ring.
##
## The cause is structural rather than a value. SSAO occludes INDIRECT light, plus
## whatever fraction of DIRECT light light_affect concedes — and this rig has spent
## three rounds deliberately removing the indirect (ambient 0.55 -> 0.20, ssil 0.60 ->
## 0.32, sdfgi 0.95 -> 0.80) because directionless light is what killed normal-map
## relief inside shadows. Those cuts are right and are not being reversed. The
## consequence is that AO has almost nothing left to occlude: the same AO is 13x
## stronger in the ambient-only control purely because there is light there for it to
## take away.
##
## The obvious alternative was also tried and is worse: giving SkyFill a shadow map
## with a 30-degree angular diameter produces a second CAST SHADOW streaking away from
## every object in a different direction from the sun's, plus shadow acne across open
## paving. Two suns is a worse defect than no contact patch.
##
## What this leaves is a floor rather than a target. AO is inert if the indirect it
## occludes goes to zero, so that is what is asserted — nobody should cut the last of
## the indirect and then wonder where the crease darkening went.
const OCCLUDABLE_INDIRECT_MIN := 0.30


func _check_occlusion_budget(env: Environment) -> void:
	# Everything AO is allowed to touch, in units of the ambient it scales.
	var indirect := env.ambient_light_energy + env.ssil_intensity
	if env.sdfgi_enabled:
		indirect += env.sdfgi_energy * 0.25   # SDFGI arrives already occluded; count a quarter
	print("  ssao radius %.2f  intensity %.2f  power %.2f  light_affect %.2f"
			% [env.ssao_radius, env.ssao_intensity, env.ssao_power, env.ssao_light_affect])
	print("  occludable indirect %.2f (ambient %.2f + ssil %.2f + sdfgi/4 %.2f)"
			% [indirect, env.ambient_light_energy, env.ssil_intensity,
				env.sdfgi_energy * 0.25 if env.sdfgi_enabled else 0.0])
	if not env.ssao_enabled:
		_fail("ssao_enabled is off; nothing darkens a crease at all")
	if indirect < OCCLUDABLE_INDIRECT_MIN:
		_fail("only %.2f of occludable indirect light is left; SSAO is inert below "
				% indirect + "about %.2f and creases stop darkening entirely"
				% OCCLUDABLE_INDIRECT_MIN)
	if env.ssao_light_affect > 0.6:
		_fail("ssao_light_affect %.2f: AO on DIRECT light is not physical, and the "
				% env.ssao_light_affect + "measured return above 0.5 is dirt in every "
				+ "sunlit corner rather than contact under anything")


# --- Cloud field -------------------------------------------------------------

const SkyScript := preload("res://scripts/world/sky_background.gd")
## Every wide shot has to have weather in it. One hero frame with an empty sky is a
## composition defect even when the field is honestly somewhere else, because the
## critic scoring that frame sees a bare gradient and the frame next to it sees
## cumulus.
const CLOUDS_IN_FRAME_MIN := 2


## Is the cloud coverage difference between shots FRAMING or PLACEMENT?
##
## Measured on the round-3 captures: 02_deck_eye 0.9% of its sky is cloud, 07_ribeira
## 5.0%, 06_river_wide 1.8% (the critics' own metric put the spread wider still). The
## claim to test is whether twelve clusters are simply distributed so that one hero
## shot looks away from them — which is honest — or whether the field only occupies a
## band no hero shot can see, which is a placement bug.
##
## So: build the real field off its real seed, project every cluster into every world
## vantage in tools/shots.json, and count. Nothing here can be judged in a render,
## which is exactly why it belongs in a probe.
func _check_cloud_framing() -> void:
	var sky := SkyScript.new()
	sky._build_clouds()
	var clouds: Array = sky._clouds
	if clouds.is_empty():
		_fail("the cloud field built no clusters")
		sky.free()
		return

	var text := FileAccess.get_file_as_string("res://tools/shots.json")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("could not read tools/shots.json")
		sky.free()
		return

	var starved: Array[String] = []
	for shot in parsed.get("shots", []):
		if String(shot.get("kind", "world")) != "world":
			continue
		var pos := _shot_vec(shot["pos"])
		var look := _shot_vec(shot["look"])
		var fov: float = float(shot.get("fov", 55.0))
		var seen := 0
		for cloud in clouds:
			if _in_frustum(pos, look, fov, 16.0 / 9.0, (cloud as Node3D).position,
					_cluster_radius(cloud as Node3D)):
				seen += 1
		print("  %-16s fov %.0f  sees %2d of %d clusters"
				% [String(shot.get("name", "?")), fov, seen, clouds.size()])
		if seen < CLOUDS_IN_FRAME_MIN:
			starved.append(String(shot.get("name", "?")))
	if not starved.is_empty():
		_fail("%s frame%s empty sky: the cloud field does not reach the part of the "
				% [", ".join(starved), "s" if starved.size() > 1 else "s"]
				+ "dome those vantages look at")
	sky.free()


## Half-extent of a baked cluster in world units, from the mesh's own AABB through
## the cluster node's scale. Read rather than assumed: the puff count, span and
## three-axis stretch are all per-cluster.
func _cluster_radius(cloud: Node3D) -> float:
	var r := 6.0
	for child in cloud.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			var e: Vector3 = mi.mesh.get_aabb().size * 0.5
			r = maxf(r, (e * cloud.scale).length())
	return r


func _shot_vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Sphere against the four side planes of a KEEP_HEIGHT camera, plus the near plane.
## `fov` is vertical, which is Godot's default and what tools/baseline.gd hands the
## Camera3D unmodified.
func _in_frustum(eye: Vector3, target: Vector3, fov_deg: float, aspect: float,
		centre: Vector3, radius: float) -> bool:
	var fwd := (target - eye).normalized()
	var right := fwd.cross(Vector3.UP)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(fwd).normalized()
	var d := centre - eye
	var z := d.dot(fwd)
	if z + radius <= 0.05:
		return false
	var half_v := tan(deg_to_rad(fov_deg) * 0.5)
	var half_h := half_v * aspect
	# Distance from the sphere centre to each side plane, with the plane normals
	# built from the half-angles rather than from a projection, so a cluster that
	# straddles the edge still counts as visible.
	var cv := 1.0 / sqrt(1.0 + half_v * half_v)
	var ch := 1.0 / sqrt(1.0 + half_h * half_h)
	if absf(d.dot(up)) * cv - z * half_v * cv > radius:
		return false
	if absf(d.dot(right)) * ch - z * half_h * ch > radius:
		return false
	return true


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
