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
##      fill. Which faces the key misses changes with the sun, so all three are
##      re-derived below whenever it moves rather than re-aimed. None casts a
##      shadow map.
##
##      Round 1 turned that argument from a preference into a measurement. On the
##      deck cobble it read normalised lit = (1.00, 0.877, 0.949) against normalised
##      shadow = (1.00, 0.818, 0.892): under a sky measuring (66, 151, 211) the
##      shadow was going REDDER, and inside the band the cobble's normal-map relief
##      disappeared entirely, standard deviation falling 8.5 -> 2.4. Both symptoms
##      have the same cause and it is the balance below -- see the block above
##      sky_fill_energy.
##
##   2. The sun's light_volumetric_fog_energy. That is a fog-only multiplier — it
##      cannot touch surface lighting — and it is the right lever for light shafts,
##      because the alternative (more volumetric density) is extinction, which is
##      uniform in every direction and is exactly the milkiness to avoid.
##
##   3. OmniLight3Ds on the lamppost globes — off by default now that the arena is
##      lit at 08:40 in the morning. See spawn_lamp_lights.
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
##
## 2.0 -> 2.6 alongside volumetric_fog_density 0.0011 -> 0.0008. That pairing holds
## the shafts at 0.94 of their previous brightness while the near haze they cost
## drops by 27%, and the near haze is the expensive half now: the depth fog's ramp
## was pulled all the way in to 18 m this pass to carry the aerial perspective, so
## the volumetric pass has to stop competing for the same 0-80 m the playable deck
## lives in. A 34-degree sun also rakes the lattice along its length instead of
## dropping through it, which makes the shafts longer and shallower — more of each
## one is in frame, so it needs less density to read.
const SUN_FOG_ENERGY := 2.6

# --- Fill lights -------------------------------------------------------------
#
# Directions are the direction light comes FROM, unit length. The sun's is the +Z
# column of SunLight's basis in bridge_arena.tscn, (0.337, 0.559, 0.757): 34 degrees
# up, 66 degrees east of +x. In this arena's compass +x is Gaia (south), -x is Porto
# (north) and -z is downstream toward the Atlantic (west).
#
# The sun came down 51 -> 34 degrees and swung 30 -> 66 degrees east of +x, so what
# the key misses changed shape again and all three fills are re-derived rather than
# re-aimed. What it misses now:
#
#   * everything facing DOWN — the deck soffit, the inside of the arch truss, the
#     underside of every handrail, cornice, balcony and eave. Nothing about the key
#     reaches these at any elevation.
#   * the -z half of every vertical surface, which is the big change: the key now
#     arrives 66 degrees round toward +z, so the inboard face of the far parapet, the
#     -z flank of every pier and the back of every lamp casting are the shaded ones.
#   * the -x half of every vertical surface: the Gaia waterfront, which faces -x, and
#     the shaded side of every baluster.
#   * the deep interior of every crease the SSAO radius is too small to have found.
#
# Three lights, and the split between them is the RUBRIC's, not an arbitrary one:
# "bounce that carries the colour of what it bounced off". A single grey fill from
# nowhere is exactly the failure mode it names.
#
# The three directions are also deliberately close to ORTHOGONAL in elevation — one
# from 60 degrees up, one from 70 degrees down, one exactly level — so that every
# surface in the arena is dominated by one of them rather than by an average of all
# three. An up-facing deck is lit by the sky and by nothing else; a soffit by the
# quay and by nothing else; a wall facing Porto by the terraces. That separation is
# what makes each one readable as a direction instead of as more ambient, and it is
# what Round 1's shadow-chroma measurement says was missing.

## The open dome. Anti-solar in azimuth (so it lands where the key does not) and 60
## degrees up, which is roughly the centroid of the sky hemisphere as a vertical wall
## sees it — a fill aimed level with the horizon lights the wrong half of the wall.
##
## Blue, but a good deal paler than the zenith colour it stands for: a wall does not
## see the zenith, it sees the whole dome including the pale hem near the horizon,
## and that integral is much less saturated than any single sample of the sky. The
## sky-lit-shadow is the single most recognisable signature of real daylight, and
## overshooting its chroma is how a scene ends up looking like night-for-day. Round 1
## flagged the frame as looking deliberately tinted; the answer is more of this light,
## not a more saturated one.
##
## (0.55, 0.70, 1.00) -> (0.72, 0.82, 1.00) and 0.46 -> 0.42, measured off a render
## rather than reasoned. Raising this fill's ENERGY to fix the shadow term was right;
## raising it at that chroma was not. The calcada on the deck footway came back at
## normalised (1.00, 1.04, 1.18) with saturation 0.32 against 0.21 before — blue-and-
## white broken mosaic rather than stone — because the cobble mask carries the deepest
## relief of the six recipes (bump 14, normal_scale 1.35), so every sett is a little
## dome presenting facets across the whole hemisphere, and each of those facets
## samples this light at a different N.L. A saturated fill turns that relief into
## chroma variation instead of value variation. Paling it keeps every guarantee the
## block above sky_fill_energy makes — the probe still reads the shadow term at B/R
## 1.61 against the key's 0.855, and 74% of it still has a direction — while taking
## the tint out of the frame. The energy comes down with it only to hold the fill's
## LUMINANCE where the retune put it; a paler colour at the same energy is a brighter
## light.
const SKY_FILL_DIR := Vector3(-0.203, 0.866, -0.457)
const SKY_FILL_COLOR := Color(0.72, 0.82, 1.00)

## Up-bounce off the river and the quays. 70 degrees below horizontal — not straight
## up, because it leans along the sun's own azimuth, 66 degrees east of +x, which is
## where the brightest water is.
##
## Green-grey, and both halves of that are measured: the deck granite is
## Color(0.312, 0.307, 0.298) and the quay setts Color(0.58, 0.56, 0.51), which is
## neutral, while the Douro under it is deep_color Color(0.115, 0.205, 0.245) and the
## terraced banks are FOLIAGE_LIT Color(0.255, 0.315, 0.150). Weighted by how much of
## the lower hemisphere each occupies, the mixture leans green. This is what should
## be arriving under the deck, and it reads as somewhere rather than as ambient.
##
## It matters more this round than last: the deck's outer fascia was rendering as a
## 100 m band of pure black (a detail-blend enum bug, see toon_bridge.tres) and is now
## a real surface, so the whole underside of the bridge has to be lit rather than
## merely not crash.
const QUAY_BOUNCE_DIR := Vector3(0.139, -0.940, 0.312)
const QUAY_BOUNCE_COLOR := Color(0.86, 0.90, 0.78)

## The Ribeira, bouncing back at the bridge. The Porto terraces stand at -x and face
## the water, i.e. face +x, so the key still hits them: about 8000 square metres of
## sunlit ochre plaster and terracotta roof, low and slightly upstream of the deck.
##
## EXACTLY LEVEL now, elevation 0.000, where it used to sit 10 degrees up. That is the
## single most important number in this file and it is Round 1's shadow-chroma finding
## made structural rather than dialled down. A directional light at zero elevation
## contributes N.L = 0 to every horizontal surface in the world, so this warm term can
## no longer reach the deck at all — not weakly, not at 3%, not at all — while losing
## nothing on the vertical faces it exists for. It is also the honest idealisation:
## the light arriving at a bridge from a distant wall of sunlit plaster arrives
## horizontally, and the 10-degree tilt it used to carry was the part with no physics
## behind it.
##
## Warm, and warm on purpose in a frame that is otherwise being pushed away from
## warmth: this is not a leftover of the sunset, it is the one direction in this world
## from which coloured light genuinely arrives. Its colour is ROOF_TERRACOTTA
## Color(0.60, 0.30, 0.21) and the ochre end of RIBEIRA_WALLS multiplied by the sun and
## renormalised. It lands on exactly the faces SKY_FILL misses — the -x side of every
## baluster, pier and lamp casting — so the shaded side of the ironwork gets a cool top
## and a warm flank instead of one flat value, which is the whole reason for spending a
## third light here.
const RIBEIRA_BOUNCE_DIR := Vector3(-0.871, 0.000, -0.491)
const RIBEIRA_BOUNCE_COLOR := Color(1.00, 0.68, 0.42)

## Far enough out that the shadow-map framing (unused — none casts) and any
## future debug gizmo sit outside the geometry.
const FILL_DISTANCE := 90.0

# --- Corridor reflection probe -----------------------------------------------
#
# One ReflectionProbe over the playable deck, and it exists for a specific measured
# failure: the tram rails.
#
# ToonFactory snaps metallic to 0 or 1, which is right, and a railhead asks for 0.85
# so it is bare steel. A metal has NO DIFFUSE TERM — every photon it returns is a
# reflection — so a rail crown is exactly as bright as whatever the renderer can tell
# it is reflecting, and nothing else. What the renderer could tell it, before this,
# was: screen-space reflections, and then the sky cubemap where those miss.
#
# Neither answers the question a rail asks. SSR at a grazing view down a hundred
# metres of deck marches along the deck and either leaves the screen or lands on more
# dark granite; the sky cubemap is the only fallback and it is the *whole dome* with
# no idea that this rail is lying in a trough between two dark parapets. Round 1's
# critics named the rails as the single tell that gave the frame away in a blind test,
# and the world stream has since rebuilt them as real grooved track — running head,
# gauge face, flangeway, check rail — and reports they still read near-black.
#
# A box-projected probe is the missing term. It gives every metal in the corridor a
# LOCAL environment with the parapets, the deck, the abutments and the sky in it, at
# the right parallax, so a rail crown returns the bright sky where it faces up and the
# dark parapet where it faces sideways — which is what makes a burnished rail read as
# a line of light rather than a painted stripe. It also helps every other bare metal
# on the bridge (rivet plates, barrel hoops, lamp castings), and it takes the edge off
# a second problem: at grazing angles the deck granite and the calçada were mirroring
# nothing but blue sky, which is part of why the footway measured blue.
#
# It costs one cubemap, rendered ONCE at load (UPDATE_ONCE) and never again, because
# nothing in this arena's static set moves.
const PROBE_CENTER := Vector3(0.0, 4.2, 0.0)
## Full box size, not extents. Covers the deck (x in [-52, 52]) with a little margin
## past both abutments, from under the soffit to well over the parapet, and 20 units
## across so both parapets and the air outside them are inside the projection box.
const PROBE_SIZE := Vector3(104.0, 14.0, 20.0)
## How far the probe's own render reaches. 160 takes in the Ribeira terraces and the
## Gaia bank, which is what a rail at the middle of the bridge can actually see.
const PROBE_MAX_DISTANCE := 160.0

# --- Practical lamps ---------------------------------------------------------
#
# Kept whole and kept working, but no longer spawned by default: see
# spawn_lamp_lights. The numbers below are the dusk numbers and are the right ones
# for a dusk arena; nothing here is tuned for a sun 34 degrees up, because at 08:40
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
# contributes is a *near* term: an extinction floor of 1 - exp(-0.0008 * d) that
# saturates at 6.2% by the end of the 80-unit froxel volume, and which therefore
# dominates the composite over the first tens of metres and is flat beyond it.
#
# So the fallback reproduces the composite curve instead of the depth term. All three
# constants are re-solved whenever the Forward+ fog moves, by brute force over eleven
# sample distances from 10 m to 410 m rather than by anchoring on two. This round's
# target is the resource's fog after fog_depth_end came in 640 -> 520 to carry the
# aerial perspective (begin 18, end 520, curve 0.62, density 1.0) composited with the
# volumetric density 0.0008.
#
# Worst error against the Forward+ composite is 0.65 points, anywhere from 10 m to
# 410 m — 7.0/0.56/0.98 against the old 640 m curve was 0.61, so the fallback tracks
# the new one just as closely. _atmosphere_probe.gd prints both curves side by side
# and fails past 0.06, which is what caught this needing re-solving at all: the compat
# tier reads fog_depth_end off the resource, so shortening the range moved the
# fallback and the target by different amounts.
const COMPAT_FOG_BEGIN := 9.0
const COMPAT_FOG_CURVE := 0.57
const COMPAT_FOG_DENSITY := 0.99

## Compatibility extracts glow after tonemapping, so nothing ever exceeds ~1.0 and
## an HDR threshold above it would stop the sun and the water's glint blooming
## entirely. 0.82 -> 0.80, measured rather than reasoned: a render of the daylight
## grade put the 99th percentile of frame luminance at 0.82, so a Compatibility
## threshold at 0.86 would have selected nothing at all and the web build would have
## had no bloom on anything, sun included. 0.80 catches roughly the top 1.5% — the sun
## disk, the water's glint path and the glazed azulejo highlights — which is the same
## population Forward+ selects at its own (HDR, and therefore quite different) 1.00.
const COMPAT_GLOW_THRESHOLD := 0.80

## Buys back the indirect that SSIL and SDFGI were providing. 1.8 -> 1.6, and it went
## DOWN while the resource's own ambient also went down (0.32 -> 0.20), which is
## deliberate rather than a double cut. Forward+ deliberately spends less on the
## directionless indirect this round — ssil_intensity 0.60 -> 0.32, sdfgi_energy
## 0.95 -> 0.80 — because that is the term Round 1 measured killing the normal
## response inside shadows, so there is less of it for Compatibility to replace.
## 0.20 * 1.6 = 0.32, against the Forward+ 0.20 plus a thinner screen-space bounce.
const COMPAT_AMBIENT_SCALE := 1.6

## Same argument, one tier up: Forward+ with SDFGI switched off keeps SSIL, so it
## needs less of the ambient back than Compatibility does.
const NO_SDFGI_AMBIENT_SCALE := 1.30

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
##
## "Gulls" is gone from this list because the node is gone: sky_background.gd's five
## bent-quad gulls were deleted this round in favour of river_life.gd's flocks, which
## have a body, a mantle, dark primaries and a wingbeat. The clouds are transparent
## and unshaded now, so they could not contribute to GI anyway, but they are kept
## listed because the exclusion is about the SDFGI voxelisation rather than about
## whether the material writes to the GI buffer.
const MOVING_DECOR := ["Clouds", "Rabelos"]

@export var world_environment: WorldEnvironment
## SDFGI is the one effect here with a real chance of hurting: the scene is thin
## procedural boxes under wide open sky, which is the leak-prone case. Single
## switch so it can be dropped without touching the resource.
@export var use_sdfgi: bool = true
## Off by default: the arena is lit at about 08:40 in the morning and a street lamp
## that time of day is switched off. Warm pools on a sunlit deck are the RUBRIC's
## "anything lit from nowhere" defect, and eight of them would also be eight lights
## that Compatibility's per-mesh omni budget has to find room for. The whole lamp
## path below still works and is still tuned — flip this to reinstate a dusk arena.
## (bridge_arena.gd still builds the globes as emissive geometry; that is the world
## stream's to dim, and it is noted in this pass's report.)
@export var spawn_lamp_lights: bool = false
@export var spawn_fill_lights: bool = true
## The corridor reflection probe. See PROBE_CENTER for what it is for; single switch
## because it is the one thing here that can be judged only in a render, and a bad
## bake is easier to rule out than to reason about.
@export var spawn_corridor_probe: bool = true
## Leave null to find the scene's shadow-casting DirectionalLight3D automatically.
@export var sun: DirectionalLight3D
## Fill energies, exposed because they are the three numbers most likely to want a
## nudge once someone has actually looked at a frame. As ratios to the key (2.8):
## sky fill 16%, quay bounce 7%, Ribeira bounce 4%.
##
## --- What Round 1 measured, and what these three numbers now do about it ----
##
## The deck cobble came back with normalised lit = (1.00, 0.877, 0.949) and normalised
## shadow = (1.00, 0.818, 0.892). Under a sky measuring (66, 151, 211) a shadow has to
## go COOLER; this one went redder. The relief went with it: the cobble's normal map
## was visibly working outside the band (standard deviation 8.5) and gone inside it
## (2.4).
##
## Both are the same defect and it is not the shadow map. Where the key is occluded,
## an up-facing deck was seeing four terms, and they split into two kinds:
##
##   DIRECTIONAL, and therefore able to shade a normal map
##     sky fill    0.32 x N.L 0.866 = 0.277, cool
##     Ribeira     0.14 x N.L 0.174 = 0.024, warm
##   DIRECTIONLESS, and therefore able only to flatten it
##     ambient     0.32, weakly blue
##     SSIL/SDFGI  gathered from the sunlit granite and cobble all around, i.e.
##                 warm, because it has been through a bounce off a warm albedo
##
## Adding those up explains both symptoms at once. The directionless half was roughly
## half the shadow's total value, which is why relief died inside the band; and its
## screen-space part is warmer than the sun itself, which is why the chroma inverted
## even though the two directional fills together are decisively blue.
##
## So the fix is a ratio, in three places, and only one of them is here:
##   * sky fill 0.32 -> 0.42, at a paler chroma. The only cool DIRECTIONAL term on an
##     up-facing surface, and its illuminance there is now 23% of the key's own
##     (0.42 x 0.866 against 2.8 x 0.559), which is about what a clear sky really
##     delivers at 34 degrees. Every unit of it restores relief inside the shadow as
##     well as chroma. See SKY_FILL_COLOR for why the chroma came down when the
##     energy went up.
##   * ambient_light_energy 0.32 -> 0.20 and ssil_intensity 0.60 -> 0.32 in
##     porto_daylight.tres — the two terms with no direction, cut nearly in half
##     between them.
##   * RIBEIRA_BOUNCE_DIR to exactly level, so the warm term contributes zero to any
##     horizontal surface by construction rather than by being small.
##
## The sky fill being by far the largest is not a stylistic choice — on a clear day
## the illuminance a surface receives from the open dome really is on the order of a
## quarter of what it receives from the sun. The two bounces are sized as bounces:
## albedo (0.3-0.5) times the fraction of the hemisphere the bouncing surface covers,
## which lands both under a tenth. The Ribeira bounce came down 0.14 -> 0.11 with its
## re-aim; the quay bounce is unchanged, and is now lighting a deck fascia and soffit
## that were rendering black before this round.
@export_range(0.0, 2.0, 0.01) var sky_fill_energy: float = 0.42
@export_range(0.0, 2.0, 0.01) var bounce_energy: float = 0.20
@export_range(0.0, 2.0, 0.01) var ribeira_bounce_energy: float = 0.11


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
	if spawn_corridor_probe:
		_spawn_corridor_probe()


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


## The probe itself. Two settings carry all the meaning:
##
##   box_projection — a plain cubemap is sampled as if it were infinitely far away,
##     which is wrong for a 104 m corridor by exactly the amount that matters: a rail
##     twenty metres down the deck would reflect the same thing as a rail at the
##     camera's feet. Box projection re-projects the sample against the box, so the
##     reflection slides correctly as the eye moves down the rail. That sliding IS the
##     read — a highlight that does not travel is a painted stripe.
##
##   ambient_mode = DISABLED — and this one is load-bearing. A ReflectionProbe's
##     default is to supply AMBIENT as well as reflection inside its box, which would
##     quietly replace the ambient term this whole file has just spent a round
##     rebalancing (0.32 -> 0.20, with the difference moved into a directional fill)
##     across the entire playable deck. The probe is here to answer "what is this
##     metal reflecting", nothing else.
func _spawn_corridor_probe() -> void:
	var probe := ReflectionProbe.new()
	probe.name = "CorridorReflection"
	probe.size = PROBE_SIZE
	probe.max_distance = PROBE_MAX_DISTANCE
	probe.box_projection = true
	probe.interior = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	# Baked once at load and never updated: nothing in the static set moves, and the
	# things that do (clouds, gulls, boats) are decor that must not be smeared into a
	# reflection anyway.
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.enable_shadows = true
	add_child(probe)
	# global, not local: this node sits under SkyBackground, which is instanced into
	# the arena, and the corridor is defined in the arena's coordinates.
	probe.global_position = PROBE_CENTER


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
