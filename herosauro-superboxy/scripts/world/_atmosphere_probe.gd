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
		# surface actually reflects on average. The second divisor is new this round --
		# the deck now wears a surface-scale granite albedo map as well as the shared
		# fine one, and forgetting it here would overstate the deck by 19%.
		var map_gain := ToonFactory._albedo_map_gain(ToonFactory.Surface.GRANITE)
		var mean_gain := (map_gain.r + map_gain.g + map_gain.b) / 3.0
		var albedo := (a.r + a.g + a.b) / 3.0 / ToonFactory.DETAIL_ALBEDO_GAIN / mean_gain
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
	var authored := Color(0.283, 0.2788, 0.2708)
	var deck_map: Variant = _map_stats(ToonFactory._ALBEDO_MAPS[ToonFactory.Surface.GRANITE])
	var fine_net: Variant = _fine_net_mean()
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
				% [presented.r, presented.g, presented.b, authored.r, authored.g, authored.b])
		for pair in [["R", presented.r, authored.r], ["G", presented.g, authored.g],
				["B", presented.b, authored.b]]:
			var got: float = pair[1]
			var want: float = pair[2]
			if absf(got - want) > want * 0.03:
				_fail("the deck fascia presents %s = %.4f where %.4f was authored (%.1f%% off). albedo_color %s no longer carries both texture layers' means."
						% [pair[0], got, want, 100.0 * (got / want - 1.0),
							deck.albedo_color.to_html(false)])

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

	# The cache is what collapses two hundred facades onto a handful of materials.
	# Snapping metallic before the key is built is supposed to make it collapse
	# harder, not softer: two call sites asking for different half-metals now share.
	var a := ToonFactory.iron(ToonFactory.IRON_GREY, 1.6, 0.30, 0.62)
	var b := ToonFactory.iron(ToonFactory.IRON_GREY, 1.6, 0.45, 0.62)
	print("  cache        iron(0.30) and iron(0.45) share a material: %s"
			% ["yes" if a == b else "NO"])
	if a != b:
		_fail("metallic snap happens after the cache key, so it costs a draw call")


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
