extends Node3D
## LightingRig: renderer tiering for the Porto environment, plus the bridge practicals.
##
## One resource — assets/environments/porto_golden_hour.tres — authors the full
## Forward+ look. GL Compatibility, which is what the web export runs, supports
## none of SSR / SSIL / SDFGI / volumetric fog, and pulls glow out of the already
## tonemapped buffer rather than an HDR one. Rather than maintain two Environments
## that drift apart, this strips whatever the live renderer cannot do at boot and
## pays back what was lost (thicker depth fog for the aerial perspective, more sky
## ambient for the missing bounce, a glow threshold the LDR buffer can reach).
##
## It also hangs real OmniLight3Ds on the lamppost globes. bridge_arena.gd builds
## those as emissive spheres that light nothing, which at dusk is the difference
## between a lamp and a sticker.
##
## Environment tuning notes (.tres files take no comments, so they live here):
##   - AgX with a 12.0 white point, not the 16.29 default: the default keeps so
##     much highlight headroom that a golden hour scene reads flat and grey.
##   - The old Filmic + tonemap_white 1.2 pairing is what actually washed the
##     baseline render out — everything above 1.2 luminance clipped to cream. The
##     depth fog took the blame but at the default density of 0.01 it could only
##     ever contribute 1%; the depth-mode formula multiplies by fog_density.
##   - Depth fog now runs at density 0.5 with aerial_perspective 0.88, so distant
##     geometry tends toward the actual sky behind it instead of a flat haze
##     colour. Begin 45 keeps the whole 100-unit deck out of it.
##   - Volumetric fog sits at density 0.002 over a 96-unit froxel volume — about
##     4% extinction at fighting range. volumetric_fog_sky_affect is 0: at the
##     default of 1.0 it fogs the sky itself, which is the milky-screen failure.
##   - SSAO radius 0.9 is tuned to the ~2-unit characters, not the 100-unit deck.
##   - SDFGI runs 5 cascades off a 0.2 min cell (12.8-unit cascade 0, ~205 units
##     total), enough to cover the bridge and the far bank. See use_sdfgi below.
##
## The key light itself is not here: SunLight lives in bridge_arena.tscn. The sky
## shader reads it through LIGHT0_*, so moving or recolouring it drags the sun
## disk and both scatter lobes along with it and nothing here needs editing.

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

## Depth fog carries the aerial perspective alone once volumetric fog is gone.
const COMPAT_FOG_DENSITY_SCALE := 1.5
## Compatibility extracts glow after tonemapping, so nothing ever exceeds ~1.0 and
## an HDR threshold above it would stop the lamps and the sun blooming entirely.
const COMPAT_GLOW_THRESHOLD := 0.82
## Buys back a little of the indirect fill that SSIL and SDFGI were providing.
const COMPAT_AMBIENT_SCALE := 1.15
const COMPAT_RADIANCE_SIZE := Sky.RADIANCE_SIZE_128

## Decorative groups in sky_background.gd that move every frame. Left as static GI
## geometry they get voxelised into the SDFGI cascades as drifting occluders, which
## smears light across the whole arena as the clouds pass over.
const MOVING_DECOR := ["Clouds", "Gulls", "Rabelos"]

@export var world_environment: WorldEnvironment
## SDFGI is the one effect here with a real chance of hurting: the scene is thin
## procedural boxes under wide open sky, which is the leak-prone case. Single
## switch so it can be dropped without touching the resource.
@export var use_sdfgi: bool = true
@export var spawn_lamp_lights: bool = true


func _ready() -> void:
	var env := _environment()
	if env == null:
		push_warning("LightingRig: no Environment found; render tiering skipped.")
		return

	_apply_renderer_tier(env)

	# Both of these read nodes that other _ready() calls have not made yet: the
	# lamps come from BridgeArena (a parent, so it runs after this) and the decor
	# from SkyBackground (this node's own parent). Defer past the whole pass.
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
		return

	# Everything below is Forward+ only; leaving it on just logs warnings.
	env.ssr_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_density = minf(env.fog_density * COMPAT_FOG_DENSITY_SCALE, 1.0)

	if method == "mobile":
		env.ssao_enabled = false   # Mobile has no SSAO either; Compatibility does.
		return

	_tune_for_compatibility(env)


func _tune_for_compatibility(env: Environment) -> void:
	env.glow_hdr_threshold = minf(env.glow_hdr_threshold, COMPAT_GLOW_THRESHOLD)
	# The two widest glow levels are two more full blur passes for spread nobody
	# resolves at web resolution. set_glow_level() is 0-based against the 1-based
	# glow_levels/N properties, so these two are glow_levels/5 and /6.
	env.set_glow_level(4, 0.0)
	env.set_glow_level(5, 0.0)
	env.ambient_light_energy *= COMPAT_AMBIENT_SCALE
	if env.sky != null:
		env.sky.radiance_size = COMPAT_RADIANCE_SIZE


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
