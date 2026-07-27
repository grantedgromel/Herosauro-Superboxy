extends Node3D
## LightingRig: renderer tiering for the Porto environment, the two fill lights the
## key light needs, and the bridge practicals.
##
## One resource — assets/environments/porto_golden_hour.tres — authors the full
## Forward+ look, and the reasoning behind every number in it lives in that file's
## own `;` comments. GL Compatibility, which is what the web export runs, supports
## none of SSR / SSIL / SDFGI / volumetric fog, and pulls glow out of the already
## tonemapped buffer rather than an HDR one. Rather than maintain two Environments
## that drift apart, this strips whatever the live renderer cannot do at boot and
## pays back what was lost — see COMPAT_* below, which are derived to *match* the
## Forward+ image rather than to approximate it.
##
## (One caveat on those `;` comments: the text resource format keeps them on load,
## but Godot's inspector does NOT round-trip them. If porto_golden_hour.tres is
## ever re-saved from the editor, every comment in it is gone. Edit it as text.)
##
## Three things here are not tiering:
##
##   1. Two fill lights. At an 11.5 degree sun everything not facing -x/-z is lit
##      by ambient alone, and a constant ambient term bright enough to keep those
##      faces off the floor is also bright enough to flatten the ones the sun does
##      hit. That is the trade the render pass caught as "deck blowing out while
##      parapets crush". The answer is not more ambient, it is DIRECTIONAL fill:
##      a cool anti-solar sky light and a warm up-bounce off the river. Both are
##      free of shadow maps, and between them the environment's flat ambient could
##      come down from 0.95 to 0.55.
##
##   2. The sun's light_volumetric_fog_energy. That is a fog-only multiplier — it
##      cannot touch surface lighting — and it is the right lever for god rays,
##      because the alternative (more volumetric density) is extinction, which is
##      uniform in every direction and is exactly the milkiness to avoid.
##
##   3. Real OmniLight3Ds on the lamppost globes. bridge_arena.gd builds those as
##      emissive spheres that light nothing, which at dusk is the difference
##      between a lamp and a sticker.
##
## The key light itself is not here: SunLight lives in bridge_arena.tscn, and this
## only reads it. The sky shader reads it too, through LIGHT0_*, so moving or
## recolouring SunLight drags the sun disk and both scatter lobes along with it and
## nothing here needs editing. Both fill lights are created with
## sky_mode = LIGHT_ONLY precisely so they can never displace it as LIGHT0.

# --- Key light ---------------------------------------------------------------

## Fog-only multiplier on the sun, on Forward+. The shafts through the arch lattice
## are the difference between lit and shadowed froxels, and 1.0 makes that
## difference about as visible as the fog's own 0.16% per-metre extinction — i.e.
## not. Shaft brightness goes as (this * volumetric_fog_density), but extinction —
## the part that veils the playable deck — goes as density alone, so buying the
## shafts here instead of there is strictly the better trade. 2.4 * 0.0016 is the
## same shaft as 1.8 * 0.0022 for 27% less haze on the bridge.
## Sized against volumetric_fog_anisotropy = 0.75, which already delivers ~3.4x
## isotropic along a sightline 30 degrees off the sun (the down-gorge view).
const SUN_FOG_ENERGY := 2.4

# --- Fill lights -------------------------------------------------------------
#
# Directions are the direction light comes FROM, unit length. The sun's is the +Z
# column of SunLight's basis in bridge_arena.tscn, (-0.860, 0.200, -0.470): low
# over the -x/-z quadrant, 11.5 degrees up.

## Cool sky fill, opposite the sun in azimuth and 42 degrees up. This is the open
## dome doing what the open dome actually does, and it is what puts a readable
## value on every surface the key misses — the far parapet, the underside of the
## handrail, the shaded half of every Ribeira facade.
const SKY_FILL_DIR := Vector3(0.652, 0.669, 0.356)
const SKY_FILL_COLOR := Color(0.52, 0.66, 0.92)

## Warm bounce up off the river. The deck soffit and the whole inside of the arch
## truss face straight down at water that is mirroring a sunset, and without this
## they are the largest black holes in the frame. Leaning slightly toward the sun
## (-x/-z) because that is where the glitter path is.
const BOUNCE_DIR := Vector3(-0.30, -0.94, -0.16)
const BOUNCE_COLOR := Color(1.0, 0.72, 0.46)

## Far enough out that the shadow-map framing (unused — neither casts) and any
## future debug gizmo sit outside the geometry.
const FILL_DISTANCE := 90.0

# --- Practical lamps ---------------------------------------------------------

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
# and the old answer — multiply fog_density by 1.5 — is wrong twice over. It only
# scales the far end (density IS the blend at fog_depth_end), and at the resource's
# new 0.72 it would clamp to 1.0 and erase the photogrammetry backdrop's silhouette
# into flat sky. What the volumetric fog actually contributes is a *near* term: an
# extinction floor of 1 - exp(-0.0016 * d) that saturates at 12% by the end of the
# 80-unit froxel volume.
#
# So the fallback reproduces the composite curve instead: pull the start of the
# ramp in (26 -> 14) and flatten the exponent (0.62 -> 0.55) to buy back the near
# haze, and lift the far end (0.72 -> 0.76) to cover the floor past it. Measured
# against the Forward+ composite the worst error is 2.4 points, at 70 m; from 130 m
# out the two agree to within one point. _atmosphere_probe.gd prints both curves.
const COMPAT_FOG_BEGIN := 14.0
const COMPAT_FOG_CURVE := 0.55
const COMPAT_FOG_DENSITY := 0.76

## Compatibility extracts glow after tonemapping, so nothing ever exceeds ~1.0 and
## an HDR threshold above it would stop the lamps and the sun blooming entirely.
const COMPAT_GLOW_THRESHOLD := 0.82

## Buys back the indirect that SSIL and SDFGI were providing. Much larger than it
## used to be because the environment's ambient came down by 42% on the strength of
## those two existing; 0.55 * 1.7 = 0.94, i.e. roughly where Forward+ sat before
## SDFGI and SSIL were subtracted from it.
const COMPAT_AMBIENT_SCALE := 1.7

## Same argument, one tier up: Forward+ with SDFGI switched off keeps SSIL, so it
## needs less of the ambient back than Compatibility does.
const NO_SDFGI_AMBIENT_SCALE := 1.3

## An upper clamp, not a downgrade — and it used to be a downgrade, from the
## resource's 256 to 128. That is the wrong saving here: the river is a near-mirror
## (the water shader runs ROUGHNESS 0.07) covering a third of the frame, and with
## no SSR on this tier the sky cubemap is the ONLY thing it can reflect. A 128px
## cubemap sampled at mip 0 is a visibly blocky sunset. It costs nothing per frame
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
@export var spawn_lamp_lights: bool = true
@export var spawn_fill_lights: bool = true
## Leave null to find the scene's shadow-casting DirectionalLight3D automatically.
@export var sun: DirectionalLight3D
## Fill energies, exposed because they are the two numbers most likely to want a
## nudge once someone has actually looked at a frame. Ratios to the key (2.4):
## sky fill is 19%, bounce is 9%.
@export_range(0.0, 2.0, 0.01) var sky_fill_energy: float = 0.45
@export_range(0.0, 2.0, 0.01) var bounce_energy: float = 0.22


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
	# The bounce points within 20 degrees of straight up, so Vector3.UP is a
	# degenerate reference for the basis. Any horizontal axis will do — a
	# directional light's roll about its own beam is unobservable.
	_fill_light(holder, "WaterBounce", BOUNCE_DIR, BOUNCE_COLOR, bounce_energy, Vector3.BACK)


func _fill_light(parent: Node3D, node_name: String, from_dir: Vector3, color: Color,
		energy: float, up: Vector3) -> void:
	if energy <= 0.0:
		return
	var light := DirectionalLight3D.new()
	light.name = node_name
	light.light_color = color
	light.light_energy = energy
	# A fill with its own specular lobe is two suns' worth of highlights on every
	# iron member; these exist to raise diffuse values, nothing else.
	light.light_specular = 0.0
	light.shadow_enabled = false
	# Both of these ARE the bounce. Letting SDFGI treat them as sources to bounce
	# again is how a fake fill turns into a compounding wash.
	light.light_bake_mode = Light3D.BAKE_DISABLED
	# Uniform fill inside the fog is milk with no directional payoff, and the
	# anisotropy that makes the sun's shafts read would work against it anyway.
	light.light_volumetric_fog_energy = 0.0
	# The single most important line in this function. LIGHT0 in porto_sky.gdshader
	# is whichever directional light the renderer hands the sky first, and the sun
	# disk, both scatter lobes and the whole anti-solar counter-glow are hung off
	# it. LIGHT_ONLY keeps these two out of that list entirely.
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
