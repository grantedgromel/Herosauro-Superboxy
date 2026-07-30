extends Node3D
## LightingRig: renderer tiering for the Porto environment, the three fill lights the
## key light needs, and the bridge practicals.
##
## One resource — assets/environments/porto_daylight.tres — authors the full
## Forward+ look, and the reasoning behind every number in it lives in that file's
## own `;` comments. GL Compatibility, which is what the web export runs, supports
## none of SSR / SSIL / SDFGI / volumetric fog, and pulls glow out of the already
## tonemapped buffer rather than an HDR one. Rather than maintain two Environments
## that drift apart, this strips whatever the live renderer cannot do at boot and
## pays back what was lost — see COMPAT_* below, which are derived to *match* the
## Forward+ image rather than to approximate it.
##
## (One caveat on those `;` comments: the text resource format keeps them on load,
## but Godot's inspector does NOT round-trip them. If porto_daylight.tres is ever
## re-saved from the editor, every comment in it is gone. Edit it as text.)
##
## Three things here are not tiering:
##
##   1. Three fill lights. A constant ambient term bright enough to keep the faces
##      the key misses off the floor is also bright enough to flatten the ones it
##      hits, which is the trade an early render pass caught as "deck blowing out
##      while parapets crush". The answer is not more ambient, it is DIRECTIONAL
##      fill. Which faces the key misses changed completely when the sun went from
##      11.5 to 51 degrees, so all three are derived below from scratch rather than
##      re-aimed. None casts a shadow map.
##
##   2. The sun's light_volumetric_fog_energy. That is a fog-only multiplier — it
##      cannot touch surface lighting — and it is the right lever for light shafts,
##      because the alternative (more volumetric density) is extinction, which is
##      uniform in every direction and is exactly the milkiness to avoid.
##
##   3. OmniLight3Ds on the lamppost globes — off by default now that the arena is
##      lit at 10:50 in the morning. See spawn_lamp_lights.
##
## The key light itself is not here: SunLight lives in bridge_arena.tscn, and this
## only reads it. The sky shader reads it too, through LIGHT0_*, so moving or
## recolouring SunLight drags the sun disk and both scatter lobes along with it and
## nothing here needs editing. All three fills are created with
## sky_mode = LIGHT_ONLY precisely so they can never displace it as LIGHT0.

# --- Key light ---------------------------------------------------------------

## Fog-only multiplier on the sun, on Forward+. The shafts through the arch lattice
## are the difference between lit and shadowed froxels, and 1.0 makes that
## difference about as visible as the fog's own per-metre extinction — i.e. not.
## Shaft brightness goes as (this * volumetric_fog_density), but extinction — the
## part that veils the playable deck — goes as density alone, so buying the shafts
## here instead of there is strictly the better trade.
## 2.4 -> 2.0 alongside volumetric_fog_density 0.0016 -> 0.0011. A 51-degree sun
## through the lattice throws short steep shafts onto the deck rather than long
## horizontal ones down the gorge: they are worth having, they are not worth what
## the old pair cost in haze on the playable surface.
const SUN_FOG_ENERGY := 2.0

# --- Fill lights -------------------------------------------------------------
#
# Directions are the direction light comes FROM, unit length. The sun's is the +Z
# column of SunLight's basis in bridge_arena.tscn, (0.545, 0.777, 0.315): 51 degrees
# up, 30 degrees east of +x. In this arena's compass +x is Gaia (south), -x is Porto
# (north) and -z is downstream toward the Atlantic (west).
#
# Raising the sun from 11.5 to 51 degrees moved the problem, it did not shrink it.
# At 11.5 the key missed almost everything: only surfaces facing -x/-z saw it at all,
# and the deck itself was at 0.20 of normal incidence. At 51 the deck, the parapet
# copings, the roofs and the whole sunward side of the city are properly lit, and
# what the key now misses is a much smaller, much more specific set:
#
#   * everything facing DOWN — the deck soffit, the inside of the arch truss, the
#     underside of every handrail, cornice, balcony and eave. A high sun makes more
#     of these and makes them darker, because nothing about the key reaches them.
#   * the -x half of every vertical surface: the north faces of the piers, the shaded
#     side of every baluster, the whole Gaia waterfront, which faces -x.
#   * the deep interior of every crease the SSAO radius is too small to have found.
#
# Three lights, and the split between them is the RUBRIC's, not an arbitrary one:
# "bounce that carries the colour of what it bounced off". A single grey fill from
# nowhere is exactly the failure mode it names.

## The open dome. Anti-solar in azimuth (so it lands where the key does not) and 60
## degrees up, which is roughly the centroid of the sky hemisphere as a vertical wall
## sees it — a fill aimed level with the horizon lights the wrong half of the wall.
##
## Blue, but a good deal paler than the zenith colour it stands for: a wall does not
## see the zenith, it sees the whole dome including the pale hem near the horizon,
## and that integral is much less saturated than any single sample of the sky. The
## sky-lit-shadow is the single most recognisable signature of real daylight, and
## overshooting its chroma is how a scene ends up looking like night-for-day.
const SKY_FILL_DIR := Vector3(-0.433, 0.866, -0.250)
const SKY_FILL_COLOR := Color(0.55, 0.70, 1.00)

## Up-bounce off the river and the quays. 70 degrees below horizontal — not straight
## up, because it leans 30 degrees east of +x to follow the sun's own azimuth, which
## is where the brightest water is.
##
## Green-grey, and both halves of that are measured: the deck granite is
## Color(0.312, 0.307, 0.298) and the quay setts Color(0.58, 0.56, 0.51), which is
## neutral, while the Douro under it is deep_color Color(0.115, 0.205, 0.245) and the
## terraced banks are FOLIAGE_LIT Color(0.255, 0.315, 0.150). Weighted by how much of
## the lower hemisphere each occupies, the mixture leans green. This is what should
## be arriving under the deck, and it reads as somewhere rather than as ambient.
const QUAY_BOUNCE_DIR := Vector3(0.296, -0.940, 0.171)
const QUAY_BOUNCE_COLOR := Color(0.86, 0.90, 0.78)

## The Ribeira, bouncing back at the bridge. The Porto terraces stand at -x and face
## the water, i.e. face +x, so the new sun hits them square: about 8000 square metres
## of sunlit ochre plaster and terracotta roof, low and slightly upstream of the deck.
## Ten degrees above horizontal, from -x/-z.
##
## Warm, and warm on purpose in a frame that is otherwise being pushed away from
## warmth: this is not a leftover of the sunset, it is the one direction in this world
## from which coloured light genuinely arrives. Its colour is ROOF_TERRACOTTA
## Color(0.60, 0.30, 0.21) and the ochre end of RIBEIRA_WALLS multiplied by a 5400 K
## sun and renormalised. It lands on exactly the faces SKY_FILL misses — the -x side
## of every baluster, pier and lamp casting — so the shaded side of the ironwork gets
## a cool top and a warm bottom instead of one flat value, which is the whole reason
## for spending a third light here.
const RIBEIRA_BOUNCE_DIR := Vector3(-0.807, 0.174, -0.565)
const RIBEIRA_BOUNCE_COLOR := Color(1.00, 0.68, 0.42)

## Far enough out that the shadow-map framing (unused — none casts) and any
## future debug gizmo sit outside the geometry.
const FILL_DISTANCE := 90.0

# --- Practical lamps ---------------------------------------------------------
#
# Kept whole and kept working, but no longer spawned by default: see
# spawn_lamp_lights. The numbers below are the dusk numbers and are the right ones
# for a dusk arena; nothing here is tuned for a sun 51 degrees up, because at 10:50
# in the morning a street lamp is switched off.

const LAMP_COLOR := Color(1.0, 0.78, 0.47)
const LAMP_ENERGY := 2.4
const LAMP_RANGE := 9.0            # a pool roughly the width of the deck
const LAMP_ATTENUATION := 1.7      # >1 falls off faster than inverse-square
const LAMP_SPECULAR := 0.35        # five lamps' worth of hotspots gets noisy at 1.0
const LAMP_FADE_BEGIN := 55.0
const LAMP_FADE_LENGTH := 18.0
const LAMP_MERGE_RADIUS := 0.6      # globes closer than this are one lamp head
const LAMP_GROUP_NAME := "Lamps"    # the node bridge_arena.gd parks its lampposts under
## Each globe gets a small halo in the volumetric fog. Cheap — an omni only touches
## the froxels inside its range — and it is most of what makes a dusk lamp read.
const LAMP_FOG_ENERGY := 1.6

## Compatibility shades at most 8 omnis per mesh and the deck is a single mesh, so
## any lamp past the eighth would simply pop out on web. Refuse to spawn them.
const LAMP_BUDGET := 8

## Used only if the lamp group cannot be found at all — mirrors bridge_arena.gd's
## LAMP_XS_FAR at rail top (4.0) + pole (2.55) on the far (-z) rail.
const FALLBACK_LAMP_SPOTS := [
	Vector3(-40.0, 6.55, -6.0),
	Vector3(-20.0, 6.55, -6.0),
	Vector3(0.0, 6.55, -6.0),
	Vector3(20.0, 6.55, -6.0),
	Vector3(40.0, 6.55, -6.0),
]

# --- Fallback renderer tier --------------------------------------------------
#
# Depth fog has to carry the aerial perspective alone once volumetric fog is gone,
# and the naive answer — multiply fog_density — is wrong twice over. It only scales
# the far end (density IS the blend at fog_depth_end), and the resource already runs
# density 1.0, so there is nothing to scale. What the volumetric fog actually
# contributes is a *near* term: an extinction floor of 1 - exp(-0.0011 * d) that
# saturates at 8.4% by the end of the 80-unit froxel volume, and which therefore
# dominates the composite from 0 to about 120 m and is flat beyond it.
#
# So the fallback reproduces the composite curve instead of the depth term. Both
# constants were re-solved against the resource's current fog (begin 40, end 640,
# curve 0.9, density 1.0) and the new volumetric density, by anchoring on 100 m —
# where the Ribeira terraces are, and the distance the eye actually judges depth at —
# and on 410 m, where the backdrop scan is. Pulling the ramp all the way to the
# camera and flattening the exponent hard is what reproduces a curve that rises fast,
# flattens, then rises again with a single smoothstep.
#
# Worst error against the Forward+ composite is 3.7 points at 280 m; from 0 to 130 m
# the two agree to within 1.8 points, which is the range everything playable is in.
# _atmosphere_probe.gd prints both curves side by side.
const COMPAT_FOG_BEGIN := 0.0
const COMPAT_FOG_CURVE := 0.75
const COMPAT_FOG_DENSITY := 0.94

## Compatibility extracts glow after tonemapping, so nothing ever exceeds ~1.0 and
## an HDR threshold above it would stop the sun and the water's glint blooming
## entirely. 0.82 -> 0.86 because the daylight grade lifts the whole upper mid-range:
## at 0.82 ordinary sunlit plaster would now cross it, and screen-blending that is a
## mid-tone lift across the frame rather than a bloom.
const COMPAT_GLOW_THRESHOLD := 0.86

## Buys back the indirect that SSIL and SDFGI were providing. 1.7 -> 1.8 because both
## of those went up with the brighter sky (sdfgi_energy 0.85 -> 0.95, ssil_intensity
## 0.55 -> 0.60), so Compatibility is now missing slightly more than it was.
## 0.45 * 1.8 = 0.81, i.e. roughly where Forward+ sits with SDFGI and SSIL folded back
## into a single directionless term.
const COMPAT_AMBIENT_SCALE := 1.8

## Same argument, one tier up: Forward+ with SDFGI switched off keeps SSIL, so it
## needs less of the ambient back than Compatibility does.
const NO_SDFGI_AMBIENT_SCALE := 1.35

## An upper clamp, not a downgrade — and it used to be a downgrade, from the
## resource's 256 to 128. That is the wrong saving here: the river is a near-mirror
## (the water shader runs ROUGHNESS 0.07) covering a third of the frame, and with
## no SSR on this tier the sky cubemap is the ONLY thing it can reflect. A 128px
## cubemap sampled at mip 0 is a visibly blocky sky, and it is a worse trade now than
## it was: the thing being reflected is a hard blue dome with a sun disk and a bright
## horizon hem in it, which shows banding far more readily than a soft warm gradient
## did. It costs nothing per frame
## either way: the Sky is PROCESS_MODE_QUALITY and the sun never moves, so the
## radiance map is generated once at load.
const COMPAT_RADIANCE_SIZE := Sky.RADIANCE_SIZE_256

## Decorative groups in sky_background.gd that move every frame. Left as static GI
## geometry they get voxelised into the SDFGI cascades as drifting occluders, which
## smears light across the whole arena as the clouds pass over. (river_life.gd
## disables GI on its own movers as it builds them, so it is not listed here.)
const MOVING_DECOR := ["Clouds", "Gulls", "Rabelos"]

@export var world_environment: WorldEnvironment
## SDFGI is the one effect here with a real chance of hurting: the scene is thin
## procedural boxes under wide open sky, which is the leak-prone case. Single
## switch so it can be dropped without touching the resource.
@export var use_sdfgi: bool = true
## Off by default: the arena is lit at about 10:50 in the morning and a street lamp
## that time of day is switched off. Warm pools on a sunlit deck are the RUBRIC's
## "anything lit from nowhere" defect, and eight of them would also be eight lights
## that Compatibility's per-mesh omni budget has to find room for. The whole lamp
## path below still works and is still tuned — flip this to reinstate a dusk arena.
## (bridge_arena.gd still builds the globes as emissive geometry; that is the world
## stream's to dim, and it is noted in this pass's report.)
@export var spawn_lamp_lights: bool = false
@export var spawn_fill_lights: bool = true
## Leave null to find the scene's shadow-casting DirectionalLight3D automatically.
@export var sun: DirectionalLight3D
## Fill energies, exposed because they are the three numbers most likely to want a
## nudge once someone has actually looked at a frame. As ratios to the key (2.0):
## sky fill 19%, quay bounce 10%, Ribeira bounce 7%.
##
## The sky fill is by far the largest and that is not a stylistic choice — on a clear
## day the illuminance a vertical surface receives from the open dome really is on the
## order of a fifth of what it receives from the sun. The two bounces are sized as
## bounces: albedo (0.3-0.5) times the fraction of the hemisphere the bouncing surface
## covers, which lands both under a tenth.
##
## The sky fill came down 0.38 -> 0.32 after a render measured a 5th-percentile
## luminance of 0.21 across three shots, i.e. a frame with no shadows in it. The
## environment's flat ambient took the larger part of that cut (0.45 -> 0.32) because
## it is the term with no direction; this one only lost the difference, since a fill
## that shapes is worth keeping and a fill that fills is not.
@export_range(0.0, 2.0, 0.01) var sky_fill_energy: float = 0.32
@export_range(0.0, 2.0, 0.01) var bounce_energy: float = 0.20
@export_range(0.0, 2.0, 0.01) var ribeira_bounce_energy: float = 0.14


func _ready() -> void:
	var env := _environment()
	if env == null:
		push_warning("LightingRig: no Environment found; render tiering skipped.")
		return

	_apply_renderer_tier(env)

	# All of these read nodes that other _ready() calls have not made yet: the
	# lamps come from BridgeArena (a parent, so it runs after this), the decor from
	# SkyBackground (this node's own parent), and the sun is a sibling of the arena
	# root. Defer past the whole pass.
	_build_light_rig.call_deferred(env)
	if spawn_lamp_lights:
		_attach_lamp_lights.call_deferred()
	if env.sdfgi_enabled:
		_exclude_moving_decor_from_gi.call_deferred()


func _environment() -> Environment:
	if world_environment != null:
		return world_environment.environment
	var parent := get_parent()
	if parent == null:
		return null
	var sibling := parent.find_child("WorldEnvironment", false, false) as WorldEnvironment
	return sibling.environment if sibling != null else null


# --- Renderer tiering --------------------------------------------------------

func _apply_renderer_tier(env: Environment) -> void:
	var method := RenderingServer.get_current_rendering_method()
	if method == "forward_plus":
		if not use_sdfgi:
			env.sdfgi_enabled = false
			env.ambient_light_energy *= NO_SDFGI_AMBIENT_SCALE
		return

	_strip_forward_plus(env)
	if method == "mobile":
		env.ssao_enabled = false   # Mobile has no SSAO either; Compatibility does.
		env.ambient_light_energy *= COMPAT_AMBIENT_SCALE
		return
	_tune_for_compatibility(env)


## Drop everything Forward+ only and re-shape the depth fog to stand in for the
## volumetric pass it just lost. Split out from the tier switch above so
## _atmosphere_probe.gd can exercise it — headless always reports forward_plus, so
## the fallback would otherwise never run anywhere it could be checked.
func _strip_forward_plus(env: Environment) -> void:
	env.ssr_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false

	env.fog_enabled = true
	env.fog_depth_begin = COMPAT_FOG_BEGIN
	env.fog_depth_curve = COMPAT_FOG_CURVE
	env.fog_density = COMPAT_FOG_DENSITY


func _tune_for_compatibility(env: Environment) -> void:
	env.glow_hdr_threshold = minf(env.glow_hdr_threshold, COMPAT_GLOW_THRESHOLD)
	# The two widest glow levels are two more full blur passes for spread nobody
	# resolves at web resolution. set_glow_level() is 0-based against the 1-based
	# glow_levels/N properties, so these two are glow_levels/5 and /6.
	env.set_glow_level(4, 0.0)
	env.set_glow_level(5, 0.0)
	env.ambient_light_energy *= COMPAT_AMBIENT_SCALE
	if env.sky != null:
		env.sky.radiance_size = mini(env.sky.radiance_size, COMPAT_RADIANCE_SIZE)


# --- Key + fill --------------------------------------------------------------

func _build_light_rig(env: Environment) -> void:
	if sun == null:
		sun = _find_sun()
	if sun != null and env.volumetric_fog_enabled:
		sun.light_volumetric_fog_energy = SUN_FOG_ENERGY
	if spawn_fill_lights:
		_spawn_fill_lights()


## The brightest shadow-casting DirectionalLight3D in the scene. Matching on
## "casts shadows" rather than on the node name is what keeps this from picking up
## either of the fills below — they deliberately cast none — if it is ever re-run.
##
## Searched from the top of the tree rather than from get_tree().current_scene:
## bridge_arena.tscn is instantiated into main.tscn, and anything that loads the
## arena on its own (a probe, a test harness, a future level select) leaves
## current_scene null or pointing somewhere else entirely, at which point the sun
## is silently never found and the god rays silently never happen.
func _find_sun() -> DirectionalLight3D:
	var root: Node = self
	while root.get_parent() != null:
		root = root.get_parent()

	var best: DirectionalLight3D = null
	for light in _directional_lights(root):
		if not light.shadow_enabled:
			continue
		if best == null or light.light_energy > best.light_energy:
			best = light
	if best == null:
		push_warning("LightingRig: no shadow-casting DirectionalLight3D found; god rays will be flat.")
	return best


func _directional_lights(node: Node) -> Array[DirectionalLight3D]:
	var found: Array[DirectionalLight3D] = []
	if node == null:
		return found
	if node is DirectionalLight3D:
		found.append(node as DirectionalLight3D)
	for child in node.get_children():
		found.append_array(_directional_lights(child))
	return found


func _spawn_fill_lights() -> void:
	var holder := Node3D.new()
	holder.name = "Fills"
	add_child(holder)

	_fill_light(holder, "SkyFill", SKY_FILL_DIR, SKY_FILL_COLOR, sky_fill_energy, Vector3.UP)
	# The quay bounce points within 20 degrees of straight up, so Vector3.UP is a
	# degenerate reference for the basis. Any horizontal axis will do — a
	# directional light's roll about its own beam is unobservable.
	_fill_light(holder, "QuayBounce", QUAY_BOUNCE_DIR, QUAY_BOUNCE_COLOR,
			bounce_energy, Vector3.BACK)
	_fill_light(holder, "RibeiraBounce", RIBEIRA_BOUNCE_DIR, RIBEIRA_BOUNCE_COLOR,
			ribeira_bounce_energy, Vector3.UP)


func _fill_light(parent: Node3D, node_name: String, from_dir: Vector3, color: Color,
		energy: float, up: Vector3) -> void:
	if energy <= 0.0:
		return
	var light := DirectionalLight3D.new()
	light.name = node_name
	light.light_color = color
	light.light_energy = energy
	# A fill with its own specular lobe is three extra suns' worth of highlights on
	# every iron member; these exist to raise diffuse values, nothing else. It also
	# keeps the ironwork's specular response honest now that ToonFactory snaps metallic
	# to 0 or 1 — a metal lit by four speculars cannot be read as one material.
	light.light_specular = 0.0
	light.shadow_enabled = false
	# All three of these ARE the indirect. Letting SDFGI treat them as sources to
	# bounce again is how a fake fill turns into a compounding wash.
	light.light_bake_mode = Light3D.BAKE_DISABLED
	# Uniform fill inside the fog is milk with no directional payoff, and the
	# anisotropy that makes the sun's shafts read would work against it anyway.
	light.light_volumetric_fog_energy = 0.0
	# The single most important line in this function. LIGHT0 in porto_sky.gdshader
	# is whichever directional light the renderer hands the sky first, and the sun
	# disk and both scatter lobes are hung off it. LIGHT_ONLY keeps these three out
	# of that list entirely.
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(light)

	var dir := from_dir.normalized()
	light.global_transform = Transform3D(Basis.looking_at(-dir, up), dir * FILL_DISTANCE)


# --- Practical lamps ---------------------------------------------------------

func _attach_lamp_lights() -> void:
	var holder := Node3D.new()
	holder.name = "Practicals"
	add_child(holder)

	var spots := _lamp_globe_positions()
	for i in mini(spots.size(), LAMP_BUDGET):
		var lamp := OmniLight3D.new()
		lamp.name = "LampLight%d" % i
		lamp.light_color = LAMP_COLOR
		lamp.light_energy = LAMP_ENERGY
		lamp.light_specular = LAMP_SPECULAR
		lamp.light_volumetric_fog_energy = LAMP_FOG_ENERGY
		lamp.omni_range = LAMP_RANGE
		lamp.omni_attenuation = LAMP_ATTENUATION
		# Five shadow-casting omnis cost far more than they read against a sky
		# that is still bright; the globes are set dressing, not key lights.
		lamp.shadow_enabled = false
		# Static so SDFGI folds them into the bounce instead of rescanning them.
		lamp.light_bake_mode = Light3D.BAKE_STATIC
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = LAMP_FADE_BEGIN
		lamp.distance_fade_length = LAMP_FADE_LENGTH
		holder.add_child(lamp)
		lamp.global_position = spots[i]


## Read the globe positions off whatever bridge_arena.gd actually built, so the
## practicals follow if the props stream re-spaces the lampposts. Matching on mesh
## type inside the lamp group rather than on node name is deliberate: every globe
## is added under the same name, and Godot renames all but the first to an opaque
## @MeshInstance3D@N, so a name pattern only ever finds one of them.
func _lamp_globe_positions() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var arena := get_parent().get_parent() if get_parent() != null else null
	var lamps := arena.find_child(LAMP_GROUP_NAME, false, false) if arena != null else null
	if lamps != null:
		for child in lamps.get_children():
			var globe := child as MeshInstance3D
			if globe == null or not (globe.mesh is SphereMesh):
				continue
			# A lamp head built from nested shells would otherwise stack two or
			# three omnis on one spot and blow that lamp out.
			if not _has_spot_near(spots, globe.global_position):
				spots.append(globe.global_position)
	if spots.is_empty():
		for fallback in FALLBACK_LAMP_SPOTS:
			spots.append(fallback)
	return spots


func _has_spot_near(spots: Array[Vector3], candidate: Vector3) -> bool:
	for spot in spots:
		if spot.distance_squared_to(candidate) < LAMP_MERGE_RADIUS * LAMP_MERGE_RADIUS:
			return true
	return false


# --- GI hygiene --------------------------------------------------------------

func _exclude_moving_decor_from_gi() -> void:
	var sky_root := get_parent()
	if sky_root == null:
		return
	for group_name in MOVING_DECOR:
		var group := sky_root.find_child(group_name, false, false)
		if group != null:
			_disable_gi(group)


func _disable_gi(node: Node) -> void:
	var geometry := node as GeometryInstance3D
	if geometry != null:
		geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children():
		_disable_gi(child)
