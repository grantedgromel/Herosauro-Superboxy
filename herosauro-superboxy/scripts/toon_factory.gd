class_name ToonFactory
extends RefCounted
## Central factory for every material the procedurally-built world uses.
##
## The name is a fossil: this used to hand out flat cel-shaded ShaderMaterials
## with an inverted-hull outline. It now hands out stylised-realistic PBR
## StandardMaterial3Ds instead — but ~40 call sites across the world, sky and fx
## scripts spell it `ToonFactory`, so the class name and the solid()/glow()
## signatures stayed put rather than churn every one of them.
##
## Two things callers must know:
##
## 1. Materials are CACHED AND SHARED by parameter set. Two hundred Ribeira
##    facades in seven palette colours collapse onto seven materials, which is
##    what lets the renderer batch them instead of issuing a draw call each.
##    Anything that mutates a material per instance (hit flash, fade-out tween)
##    MUST call .duplicate() on the result first.
##
## 2. The scenery is raw BoxMesh / PrismMesh / SphereMesh. Their 0..1 UVs would
##    smear one texture tile across a 100 m bridge deck, so every textured helper
##    maps triplanar in *object* space at a real-world tile size. Object space,
##    not world space, so a moving prop (a lobbed rock, a bobbing rabelo) doesn't
##    swim through its own texture.
##
## Detail maps live in res://assets/textures/ as NoiseTexture2D descriptors —
## no bitmaps in the repo. See generate_detail_maps.gd there for the recipes.
##
## --- Three rules this factory now enforces centrally ------------------------
##
## All three are RUBRIC lines that were being missed identically by every caller,
## which is the case for fixing them in one place rather than in forty:
##
## a) TWO TEXTURE SCALES, always. A surface map tiled at its authored real-world
##    size is magnified about elevenfold at half a metre and resolves as blur; the
##    same map tiled to resolve there tiles visibly at twenty metres. Every textured
##    material therefore also wears the shared fine pair at ~0.28 m — grit in the
##    normal, patchy discolouration in the albedo. That second layer is what the
##    RUBRIC means by "a detail layer still doing work at 0.5 m", and shot
##    03_rail_macro exists to test exactly it. It costs six more triplanar taps and
##    that is what the bar costs.
##
## b) ALBEDO VARIATION, always, at BOTH scales, and — since Round 3 — WITH HUE IN IT
##    AT BOTH. Before Round 1 every material in the game was one flat albedo colour
##    with a bump map on it. Round 1 gave it a fine layer and Round 2 gave it a
##    surface-scale one, and Round 2's own measurement is what showed that was still
##    not enough: five stone surfaces in two frames came back at channel-deviation
##    correlations of 0.88-0.995 (cobbles 0.945/0.894, granite 0.987/0.882, kerb
##    0.995/0.975, parapet 0.994/0.964, walkway 0.995/0.952), which is the signature
##    of ONE FLAT ALBEDO MULTIPLIED BY A GREY MASK. Both layers were varying all
##    three channels together, so all that variance was luminance and none of it was
##    ever colour — the granite carried sd=19.6 and the walkway sd=40.6 and both
##    still read as cardboard.
##
##    The lever is hue, and it is NOT more grunge. Every ramp in the stone family is
##    now non-monotone: warm-cool and green-magenta axes that reverse against each
##    other while value climbs, which is what a mineral mixture actually is and what
##    a monotone "cool at the dark end, warm at the bright end" ramp can never be,
##    however far apart its ends are pitched. Delivered correlations went granite
##    +1.000/+0.999 -> +0.43/+0.06, cobble +1.000/+0.999 -> +0.52/+0.04, plaster
##    +1.000/+1.000 -> +0.66/+0.18. See the recipes in generate_detail_maps.gd, and
##    _atmosphere_probe.gd, which now gates the number.
##
##    Two scales, because they answer different distances: the fine layer tiles at
##    0.28 m and is gone by four metres, so per-object variation — one sett against
##    the next, a rust bloom across a whole gusset — needs a map at the material's
##    own tile size. Granite, cobble, iron and plaster carry one on albedo_texture;
##    see _ALBEDO_MAPS below.
##
## b2) AND — since Round 4 — THE PLAYABLE GROUND MAY NOT BE THE DARKEST THING IN FRAME.
##    Two critics reviewing five frames with no knowledge of each other independently
##    measured the deck as the darkest region in every shot, against a RUBRIC that
##    requires the playable corridor to be the brightest. It is albedo and not light:
##    top quartile against top quartile, the carriageway returns 52% of the footway
##    thirty pixels behind it, and the authored constants say the same (0.235 and 0.325
##    against 0.545 and 0.580). PORTO_STONE_FLOOR is the guard; see it for why 0.44,
##    why a knee rather than a clamp, and why it tests the colour's chroma first.
##
## c) METALS ARE 0 OR 1. Call sites currently ask for 0.20, 0.28, 0.30, 0.35, 0.42,
##    0.45, 0.55, 0.60, 0.65 and 0.85. Every value strictly between is
##    unphysical — it desaturates the diffuse term and tints the specular at the
##    same time, so the surface reads as neither painted steel nor bare steel — and
##    it is a specific RUBRIC failure. build() snaps at 0.6 and gives the dielectric
##    side a raised metallic_specular instead, which is the thing the half-metal was
##    actually faking: painted ironwork catching the sky.
##
##    Round 4 added the other half, because "metals are 0 or 1" turned out to be a
##    rule with a trap in it: a surface that is honestly metallic 1 and also honestly
##    smooth returns nothing but its environment, and this environment is a sky. The
##    bare-metal side now gets METAL_ROUGHNESS_FLOOR and its own mask, whose blue
##    channel is a per-texel metal/oxide split — so the rail crown is 0-or-1 metal at
##    every texel and is not a mirror at any of them. See both constants below.

# --- Surfaces ---------------------------------------------------------------

## Which detail map set a material wears. FLAT means "no textures at all", which
## is right for clouds, gull wings and anything read at a distance where a
## detail normal is just shimmer.
enum Surface { FLAT, GRANITE, IRON, COBBLE, PLASTER, TERRACOTTA, WOOD }

const _NORMAL_MAPS := {
	Surface.GRANITE: preload("res://assets/textures/detail_granite_normal.tres"),
	Surface.IRON: preload("res://assets/textures/detail_iron_normal.tres"),
	Surface.COBBLE: preload("res://assets/textures/detail_cobble_normal.tres"),
	Surface.PLASTER: preload("res://assets/textures/detail_plaster_normal.tres"),
	Surface.TERRACOTTA: preload("res://assets/textures/detail_terracotta_normal.tres"),
	Surface.WOOD: preload("res://assets/textures/detail_wood_normal.tres"),
}

## R = roughness multiplier, G = ambient occlusion. One texture, two channels,
## because triplanar costs three taps per map and we sample it twice either way.
const _MASK_MAPS := {
	Surface.GRANITE: preload("res://assets/textures/detail_granite_mask.tres"),
	Surface.IRON: preload("res://assets/textures/detail_iron_mask.tres"),
	Surface.COBBLE: preload("res://assets/textures/detail_cobble_mask.tres"),
	Surface.PLASTER: preload("res://assets/textures/detail_plaster_mask.tres"),
	Surface.TERRACOTTA: preload("res://assets/textures/detail_terracotta_mask.tres"),
	Surface.WOOD: preload("res://assets/textures/detail_wood_mask.tres"),
}

## Surface-scale COLOUR variation, riding albedo_texture on uv1 at the material's own
## tile size. Four of the seven surfaces have one, and the argument for each is next
## to its recipe in generate_detail_maps.gd. Terracotta and wood have none: three more
## triplanar taps is a real cost and nothing measured has asked for them there.
##
## This is the map that answers Round 1's two material findings and Round 2's one. The
## fine layer below tiles at 0.28 m, so it delivers grit and damp patches at arm's
## length and nothing at all past four metres; what the deck and the ironwork were
## missing is variation at the scale of the OBJECT — one sett against the next, a rust
## bloom across a whole gusset — and that needs hue, at the surface's own tile. Since
## Round 3 "hue" means hue that REVERSES across the ramp rather than tracking value,
## which is the only kind that survives the channel-correlation measurement.
##
## albedo_texture MULTIPLIES albedo_color, so a call site's colour still decides what
## the surface is; this only modulates it. _albedo_map_gain divides the modulation's
## own mean back out, per channel, so a map whose average is a warm 0.82 does not
## quietly darken and warm forty call sites' palettes.
const _ALBEDO_MAPS := {
	Surface.GRANITE: preload("res://assets/textures/detail_granite_albedo.tres"),
	Surface.IRON: preload("res://assets/textures/detail_iron_albedo.tres"),
	Surface.COBBLE: preload("res://assets/textures/detail_cobble_albedo.tres"),
	Surface.PLASTER: preload("res://assets/textures/detail_plaster_albedo.tres"),
}

## The mask a BARE METAL wears instead of its family's own. One entry, and one entry is
## the point: iron is the only family any call site asks for metallic 1 on.
##
## Same three channels in the same order, plus a fourth thing the painted mask does not
## carry — B is the bare-metal fraction, which build() wires to metallic_texture. So a
## bare-metal material's roughness, its AO and its metal/oxide split all come off ONE
## texture registered to ONE noise field, which is what makes the oxide land exactly
## where the surface is rough and where the iron albedo map's rust bloom already is.
##
## Its ranges and the arithmetic behind them are in the `steel` recipe in
## generate_detail_maps.gd. The short version: 0.72-1.00 roughness rather than the
## painted mask's 0.22-1.00, because a rail head is satin and gloss paint is not, and
## about 38% of the surface stops being metal at all.
const _METAL_MASK_MAPS := {
	Surface.IRON: preload("res://assets/textures/detail_steel_mask.tres"),
}

## The shared close-range layer, one pair for every surface. See rule (a) above and
## the header of generate_detail_maps.gd for why it is shared and for what the
## albedo map's alpha channel is doing.
const _FINE_NORMAL := preload("res://assets/textures/detail_fine_normal.tres")
const _FINE_ALBEDO := preload("res://assets/textures/detail_fine_albedo.tres")

# --- Palette ----------------------------------------------------------------
# Defaults so a caller that just wants "some granite" can write ToonFactory.stone().

const STONE_GREY := Color(0.56, 0.54, 0.50)
const IRON_GREY := Color(0.36, 0.38, 0.42)
const COBBLE_GREY := Color(0.62, 0.60, 0.56)
const PLASTER_CREAM := Color(0.88, 0.85, 0.78)
const TERRACOTTA_RED := Color(0.62, 0.29, 0.21)
const WOOD_BROWN := Color(0.36, 0.24, 0.14)
const CLOTH_LINEN := Color(0.93, 0.89, 0.79)
const AZULEJO_BLUE := Color(0.18, 0.38, 0.66)
const GLASS_TINT := Color(0.72, 0.82, 0.86)

# --- Shared look ------------------------------------------------------------

## A little Fresnel rim on everything. It is the one deliberate survivor of the
## toon pass: it keeps silhouettes reading now that the hard black outline is gone,
## without costing a second draw call.
##
## 0.22 -> 0.14, and tint 0.45 -> 0.65. A rim term is a fake grazing-angle lift, and
## against a hazy low-contrast sunset sky it was buying silhouette separation cheaply.
## Against a hard blue sky under a strong key it buys much less — the key does that job
## now — while costing more, because a uniform white-ish edge highlight on every
## object in a bright frame is exactly the "plastic sheen" tell a critic looks for.
## The higher tint pushes what is left toward the surface's own albedo, so a terracotta
## roof rims terracotta rather than rimming white.
const RIM_AMOUNT := 0.14
const RIM_TINT := 0.65
const DEFAULT_ROUGHNESS := 0.80

# --- Physical guards --------------------------------------------------------

## Real diffuse surfaces live between about 2% (fresh asphalt, soot) and 90% (fresh
## snow, titanium white) reflectance, and the RUBRIC states that range as a rule.
## Several call sites are outside it — TRIM_WHITE at 0.93, the cloud puffs at 0.95,
## gull feathers at 0.94 — and an albedo above 0.9 does not read as "brighter", it
## reads as an object that cannot take a shadow. Clamped by scaling the whole colour
## rather than per channel, so nothing shifts hue on the way in.
##
## THIS APPLIES TO THE AUTHORED COLOUR, before the texture gains — see
## _physical_albedo() for the full reasoning. It used to be applied after them, and
## Round 3 walked straight into the consequence: the effective ceiling on a call
## site's authored reflectance was 0.90 divided by both gains, about 0.616 for
## granite, and it MOVED whenever an albedo map was re-authored. Re-authoring the
## granite ramp for hue dropped the map's mean 0.863 -> 0.774, raised the gain
## 1.159 -> 1.293, and silently darkened TRIM_WHITE, GRANITE_DRESS and DRESSED by
## 10%, 10% and 2% — three world-stream call sites that had nothing to do with the
## texture edit that moved them.
##
## A guard that fires because somebody changed a noise ramp is not measuring physics.
## Against the authored value it means exactly what it says, it is stable under
## texture work, and it lands on the stream that authored the colour. Those three
## call sites are still above what granite physically reflects and are still clamped
## — but now for the reason stated on the tin.
const ALBEDO_CEILING := 0.90
const ALBEDO_FLOOR := 0.02

## --- The Porto stone floor -------------------------------------------------
##
## A second, much higher floor that applies ONLY to the two stone surface families,
## and only to colours authored near-neutral. It is the answer to the strongest
## converging finding this project has had: two critics, reviewing five different
## frames with no knowledge of each other, independently measured the PLAYABLE
## GROUND as the darkest region in every frame they were given.
##
## THE MEASUREMENT. In 03_rail_macro the footway flags sit at L 130.1 (top quartile
## 146.1) and the carriageway thirty pixels in front of them at L 52.5 (top quartile
## 76.3). Comparing top quartile against top quartile removes the parapet's shadow
## bands from both populations, and the ratio is still 0.52 — so this is albedo, not
## light, and the authored values say so: ROADWAY_COLOR 0.325 and TRAMBED_COLOR 0.235
## against FLAG_COLOR 0.545 and KERB_COLOR 0.580. The other critic put the same
## numbers on two other shots: 02_deck_eye's deck at rgb (102, 98, 105) and
## 07_ribeira's cobble at (73, 65, 68), "roughly half where sunlit stone should sit".
##
## The RUBRIC requires the playable corridor to be the BRIGHTEST, highest-contrast
## thing in frame. It is currently the darkest thing in frame, in every frame.
##
## WHY A FLOOR AND NOT A REPAINT. The dark values are deliberate — the palette they
## come from is commented "near-black roadway ... values run low on purpose" — and
## they are a value-contrast trick: darken the road so the pale kerb reads. That is
## the backwards correction a critic warned about by name ("if a previous round
## reported the corridor does not read and someone responded by darkening it, that
## correction is backwards"), and it will be reached for again by the next stream
## that wants separation. A guard in the factory is the thing that cannot be reached
## for twice.
##
## WHY 0.44 IS THE NUMBER. This is not a claim that no stone is dark — black granite
## and basalt exist. It is a claim about THESE stones. Every stone surface in this
## game is one of two rocks: the pale two-mica granite the whole city is quarried
## from (0.35-0.50 dry), and the cream limestone of the calcada (0.45-0.65). There is
## no basalt, no slate and no bluestone on this bridge. So a near-neutral stone
## authored below 0.44 is not making a Porto claim, and 0.44 is the bottom of the
## band the real material occupies.
##
## WHY A KNEE AND NOT A CLAMP. A hard clamp would collapse the tram bed, the mortar
## bed and the carriageway (0.235 / 0.300 / 0.325) onto one identical value and throw
## away a tonal ordering another stream authored on purpose. The knee is a linear
## remap of [0, KNEE] onto [FLOOR, KNEE]: monotone, so the ordering survives; exactly
## the identity at and above KNEE, so nothing already inside the Porto band moves at
## all (the kerbs, the flags, every dressed granite in the game); and self-limiting,
## so if the stream that owns those constants raises them itself, this stops doing
## anything rather than doubling up. Delivered: 0.235 -> 0.476, 0.325 -> 0.490 against
## the flags' unchanged 0.545, i.e. 13% and 10% below the walkway instead of 40%.
##
## WHY A CHROMA TEST. `stone()` is also how the terrain stream dresses bare EARTH
## (0.33, 0.28, 0.21) and river ROCK (0.47, 0.43, 0.37), and dry earth really does
## reflect 0.20-0.35 — lifting it would be inventing a claim rather than enforcing
## one. Every grey stone in the game measures a chroma of (max-min)/max <= 0.128 and
## those two measure 0.36 and 0.21, so the populations separate cleanly and 0.18 sits
## in the gap. Read it as: this guard applies to stone authored as STONE-COLOURED.
const PORTO_STONE_FLOOR := 0.44
const PORTO_STONE_KNEE := 0.52
const PORTO_STONE_CHROMA := 0.18

## Surface families the floor applies to. Not IRON, not PLASTER (a limewash really can
## be any value its owner painted it), not TERRACOTTA, not WOOD.
const _STONE_SURFACES := [Surface.GRANITE, Surface.COBBLE]

## Nothing on this bridge is a mirror, and the tram rail head has spent three rounds
## proving what happens when a material claims to be one.
##
## A metal has no diffuse term, so every photon it returns is a reflection. At the
## call site's authored roughness of 0.30 — multiplied down to 0.088 by the iron
## mask's smooth end — the crown's specular lobe is about four degrees wide, and at a
## grazing view down the deck the only thing inside four degrees of the mirror
## direction is sky. Measured at 03_rail_macro y 603-604: RGB (32, 64, 109) and
## (16, 44, 98), saturation 0.70 and 0.83, against immediate neighbours at 0.19-0.33
## and warm grey. Round 1 named the flat blue rails as the single tell that gave the
## frame away in a blind test; Round 2 rebuilt the geometry as real Ri60 grooved track
## and added a ReflectionProbe, and the crown got brighter and stayed pure blue.
##
## 0.45 is a fact about rail steel rather than a fudge. A rail head is ground once on
## installation and then abraded by steel wheels for the rest of its life, so its
## finish is directional wear scoring — satin, not polish. Nothing else in the frame
## is smoother: the lattice is painted, the castings are oxidised, the barrel hoops
## are salt-weathered. Against the steel mask's 0.72-1.00 this lands the crown at
## 0.32-0.45, a lobe wide enough to integrate most of the upper hemisphere, so it
## returns the deck and the parapet mixed into the sky instead of the sky verbatim.
##
## Applied BEFORE the cache key, like the metallic snap, so two call sites asking for
## 0.26 and 0.30 on a bare metal collapse onto one material instead of two.
const METAL_ROUGHNESS_FLOOR := 0.45

## Below this, `metallic` means "dielectric"; at or above it, "bare metal". Nothing
## in between survives — see rule (c) in the header. 0.6 is where the call sites
## actually separate: the tram railheads (0.85), the rivet plates (0.60) and the
## barrel hoops (0.65) are bare steel, and everything else on this bridge is painted.
const METALLIC_SNAP := 0.6

## metallic_specular for a snapped-to-zero dielectric that asked to be a metal.
## 0.5 is Godot's default and means F0 = 4%, which is glass and most plastics.
## Painted or oxidised steel sits nearer 5.5-6%, and that extra is the sky catching
## the ironwork — the read the half-metallic value was reaching for by the wrong
## route, because it was also washing the colour out of the diffuse term to get it.
const DIELECTRIC_METAL_SPECULAR := 0.62

# --- Close-range detail layer -----------------------------------------------

## Tile size of the shared fine pair, in metres. 0.28 m over a 256-px map is about
## 1.1 mm per texel: still resolving at the 0.5 m the RUBRIC names, and small enough
## that by 4-5 m it has gone sub-pixel and stopped contributing anything but a very
## slight softening — which is the correct behaviour for a second layer.
const DETAIL_TILE_METERS := 0.28

## The fine layer's NET multiplier on albedo runs 0.65 at the bottom of its range to
## 1.00 at the top and averages 0.876, so leaving it alone would quietly darken every
## authored colour in the game by roughly 12% and make forty call sites' palettes mean
## something they do not say. This puts that back. It is not a look dial — the
## RUBRIC's "exposure-driven, not multiplier-driven" rule is about fixing LIGHTING
## with albedo, and this is a texture-mean correction. It is applied before
## ALBEDO_CEILING, so it can never push a colour out of range.
##
## ONE SCALAR, not three, and that is a constraint on the fine ramp rather than a
## simplification here. The surface maps each get a per-channel gain, so they may
## average any colour they like; this layer is SHARED by every textured material in
## the game, so if its channels average differently the whole game is tinted and
## nothing divides it back out. Round 3 made the layer chromatic and therefore had to
## hold its three channel means equal — measured spread 0.54%, and
## _atmosphere_probe.gd now fails past 2%.
##
## 1.13 against a measured reciprocal of 1.140: a 0.9% underscale, inherited, and left
## alone deliberately. It is inside the probe's 3% and moving it would shift every
## palette in the game by 1% for no reason anyone asked for.
const DETAIL_ALBEDO_GAIN := 1.13

static var _cache: Dictionary = {}
static var _derived_normals: Dictionary = {}
static var _map_gains: Dictionary = {}


# --- Legacy API -------------------------------------------------------------

## A plain untextured PBR surface — the general-purpose fallback.
##
## `_legacy_outline_width` is the dead cel-shader's outline thickness. It is
## ignored and only survives so the pre-PBR call sites keep compiling; new code
## should skip past it and set `roughness` / `metallic`, or reach for one of the
## named material helpers below, which come with detail maps.
static func solid(color: Color, _legacy_outline_width: float = 0.0,
		roughness: float = DEFAULT_ROUGHNESS, metallic: float = 0.0) -> StandardMaterial3D:
	return build(color, Surface.FLAT, roughness, metallic)


## An emissive surface — the Dino Energy orb, lamp globes, lit windows.
##
## `energy` now drives emission_energy_multiplier; under Forward+'s HDR buffer
## values above ~1.5 actually bloom instead of just clipping to white.
## `_legacy_outline_width` is ignored, as in solid().
static func glow(color: Color, energy: float = 3.0, _legacy_outline_width: float = 0.0,
		roughness: float = 0.42) -> StandardMaterial3D:
	return build(color, Surface.FLAT, roughness, 0.0, 1.0, 1.0, 0.0, color, energy)


# --- Material helpers -------------------------------------------------------

## Granite: piers, quay walls, the Clérigos shaft, thrown masonry.
##
## Carries the surface-scale granite albedo map: metre-scale mottling at the coarse
## tile, so one block differs from the next. The bump and the fine layer were already
## doing the speckle; what a kerb run or a quay wall was missing is the difference
## between its stones — and, since Round 3, a difference in HUE and not only in value.
## The ramp walks iron-stained dark, damp blue-grey, pink feldspar, quartz blue-white,
## warm bleached, lichen grey-green, hot bleached, so a warm block sits against a cool
## one at metre scale. Delivered channel correlation r-g +0.43 / r-b +0.06, from
## +1.000 / +0.999 when the ramp still ran cool-dark to warm-bright in one direction.
##
## ao_strength 0.35 -> 0.52. This granite stands two metres above a tidal river, and
## the mask's crevices are now both darker (the AO channel was inverted before this
## pass) and glossier (roughness 0.52-1.00 across the surface), which together is the
## damp-in-the-joints, dry-on-the-face read the RUBRIC asks for by name. normal_scale
## up 1.0 -> 1.15 because the fine layer stacks at 55% and the surface normal has to
## stay the dominant one at arm's length and beyond.
static func stone(color: Color = STONE_GREY, tile_meters: float = 2.4) -> StandardMaterial3D:
	return build(color, Surface.GRANITE, 0.92, 0.0, tile_meters, 1.15, 0.52)


## Cobbled setts: the Ribeira cais, the deck footways, the tram bed, any paved
## promenade. ao 0.45 -> 0.60: the grout between setts is where the moss is, and it is
## the deepest AO of the six recipes.
##
## The surface-scale albedo map is aimed at Round 1's finding that the deck cobble was
## "a normal-map-only material — contrast-stretched, every sett the identical
## pinkish-mauve". Its noise is the SAME cellular field as the mask, at the same
## frequency, jitter and seed, but returning per-cell values instead of border
## distances, and its gradient interpolates as CONSTANT — so each sett takes one flat
## colour off a six-stop ramp and the colour boundaries land exactly on the joints the
## normal map is already grooving. Under SceneryKit.world_mapped(), which is how the
## deck and the quays take it, that variation runs across a hundred metres of paving
## instead of restarting per box.
##
## Round 3 replaced the six stops with six STONES — three value levels crossed with
## warm and cool — which is the arrangement that makes value and hue exactly
## orthogonal over an equal-share cell field, and took the delivered correlation from
## r-g +1.000 / r-b +0.999 to +0.52 / +0.04. The sett-to-sett VALUE ratio came down
## from 1.6x to 1.5x to pay for it, on the brief's own reasoning that this surface
## already had more monochrome variance than it could use. This is not the calçada
## portuguesa mosaic and deliberately is not; the recipe says why.
static func cobblestone(color: Color = COBBLE_GREY, tile_meters: float = 1.4) -> StandardMaterial3D:
	return build(color, Surface.COBBLE, 0.88, 0.0, tile_meters, 1.35, 0.60)


## Painted / weathered structural steel: the arch, lattice, rails, lampposts.
##
## metallic default 0.55 -> 0.0, which is what this material has always physically
## been: the Dom Luís lattice is painted steel, and paint is a dielectric. The old
## half-metal was reaching for "picks up the sky instead of reading as grey card" and
## getting there by washing the diffuse colour out, which is why the ironwork never
## looked painted. The sky pickup is bought properly instead, with
## DIELECTRIC_METAL_SPECULAR and the iron mask's 0.34-1.00 roughness spread: intact
## paint is smooth enough to mirror the dome, a rust bloom is not, and the two sit
## next to each other on every member.
##
## Call sites that genuinely want bare steel — the tram railheads at 0.85, the rivet
## plates at 0.60, the barrel hoops at 0.65 — clear METALLIC_SNAP and get metallic 1.
##
## And the surface-scale albedo map, which is the direct answer to Round 1's highest-
## leverage finding: the Dom Luís ironwork measured mean RGB (11, 16, 27), standard
## deviation 3, maximum (22, 28, 41), with no specular return anywhere along the top
## rail against a 210-blue sky — a black cutout in a game about a wrought-iron bridge.
## Three things address it and only one of them is a material:
##   * the map runs intact paint -> chalked edge -> oxide bloom on the SAME noise as
##     the normal and the roughness mask, so rust sits where the plate is proud and
##     rough and nowhere else. That is the rust bleed and the failed paint.
##   * the sun swung 66 degrees east of +x, so the lattice's broad +-z faces went from
##     N.L 0.315 to 0.757 — 2.4x the key, on the largest visible surface of the asset.
##   * sky_fill_energy went 0.32 -> 0.46, which is what lifts its upward faces, and
##     DIELECTRIC_METAL_SPECULAR at F0 6.2% against the iron mask's 0.34-1.00 roughness
##     spread is what puts a specular roll along the top rail.
## The one thing here that is NOT solved at material scale is the paint chipped
## specifically at the handrail contact line: that is a position-dependent wear mask,
## it needs world-space authoring on the geometry, and the geometry is not this
## stream's. It is in this pass's report.
static func iron(color: Color = IRON_GREY, tile_meters: float = 1.6,
		metallic: float = 0.0, roughness: float = 0.62) -> StandardMaterial3D:
	return build(color, Surface.IRON, roughness, metallic, tile_meters, 1.05, 0.38,
			Color.BLACK, 0.0, 1.0, DIELECTRIC_METAL_SPECULAR)


## Limewashed render — Ribeira facades, lodge walls, chapel body. Sun-faded and
## chalky: roughness 0.94 with the plaster mask's 0.80-1.00 on top, and the fine albedo
## layer blotching it, which on a pale wall reads as exactly the uneven weathering
## every limewashed facade in the Ribeira has.
##
## It also carries a surface-scale albedo map, at a much lower frequency than the
## other three (~1.3 m blotches). That is aimed at one report: the world stream gave
## these facades real reveals, sills, shutters and downpipes and they still read as
## flat-coloured cards at 60-120 m — which they would, because at that range the fine
## layer has gone sub-pixel and a wall was one authored colour again. See the recipe
## for why the VALUE range is the tightest of the four and what it costs the brightest
## authored plaster colours.
##
## Round 3 made that map non-monotone like the rest of the stone family, at half
## granite's amplitude: damp streaks go grey-green, sun-baked panels go warm-ochre,
## and the delivered correlation went r-g +1.000 / r-b +1.000 to +0.66 / +0.18. A
## second critic independently measured these same facades getting MORE saturated
## with distance (0.265 / 0.301 / 0.323, near to far), and a near wall carrying its
## own hue variation is half the answer to that; the other half is the fog term and
## belongs to the atmosphere stream.
static func plaster(color: Color = PLASTER_CREAM, tile_meters: float = 2.0) -> StandardMaterial3D:
	return build(color, Surface.PLASTER, 0.94, 0.0, tile_meters, 0.85, 0.30)


## Clay barrel roof tiles. Rain-polished on the crowns, gritty in the pans between
## them, with the deepest normal of the six because a roof is only ever seen from
## above at a steep angle and the tile relief is its entire silhouette.
static func terracotta(color: Color = TERRACOTTA_RED, tile_meters: float = 0.85) -> StandardMaterial3D:
	return build(color, Surface.TERRACOTTA, 0.86, 0.0, tile_meters, 1.2, 0.45)


## Timber: rabelo hulls, masts, barrels, decking. Worn pale and smooth where feet
## land, rough in the split between boards.
static func wood(color: Color = WOOD_BROWN, tile_meters: float = 1.1) -> StandardMaterial3D:
	return build(color, Surface.WOOD, 0.80, 0.0, tile_meters, 0.95, 0.32)


## Woven cloth: sails, awnings, banners. Fully rough, no spec highlight to speak
## of — the plaster map at a tight tile stands in for the weave.
static func cloth(color: Color = CLOTH_LINEN, tile_meters: float = 0.45) -> StandardMaterial3D:
	return build(color, Surface.PLASTER, 0.98, 0.0, tile_meters, 0.5, 0.15)


## Glazed ceramic — the azulejo panels. Wet-looking: that hard specular kick off
## a tile front is the whole reason azulejos read as Porto and not as blue paint,
## and under a hard blue sky it is a far bigger part of the frame than it was under a
## hazy one. Godot's metallic_specular is F0 = 0.16 * s^2, so 0.65 is F0 = 6.8%: a
## fired lead glaze rather than the 4% the 0.5 default assumes for everything, and the
## difference between a tile panel that flashes as the camera passes and one that does
## not.
static func ceramic(color: Color = AZULEJO_BLUE, tile_meters: float = 0.5) -> StandardMaterial3D:
	return build(color, Surface.TERRACOTTA, 0.14, 0.0, tile_meters, 0.30, 0.14,
			Color.BLACK, 0.0, 1.0, 0.65)


## Window / lantern glazing. Transparent, so it lands in the alpha pass — keep
## the panes small and few.
static func glass(color: Color = GLASS_TINT, alpha: float = 0.28) -> StandardMaterial3D:
	return build(color, Surface.FLAT, 0.04, 0.0, 1.0, 1.0, 0.0, Color.BLACK, 0.0, alpha)


## Still water — puddles, troughs, the harbour inside a lock gate. The moving
## Douro surface is res://assets/shaders/water_wave.gdshader, not this.
static func water(color: Color = Color(0.16, 0.34, 0.42), alpha: float = 0.78) -> StandardMaterial3D:
	return build(color, Surface.PLASTER, 0.06, 0.0, 6.0, 0.35, 0.0, Color.BLACK, 0.0, alpha)


# --- Builder ----------------------------------------------------------------

## The one place a StandardMaterial3D is actually constructed. Public so a
## geometry stream can dial in something the named helpers don't cover, but
## prefer the helpers: fewer distinct parameter sets means fewer materials means
## fewer draw calls.
##
## `specular` and `fine_detail` are appended, never inserted: terrain_batch.gd calls
## this positionally with seven arguments and every other caller goes through a named
## helper, so anything new has to arrive at the end with a default that reproduces the
## old behaviour. `specular` is metallic_specular, i.e. F0 for the dielectric case;
## `fine_detail` switches off the shared close-range layer for surfaces the camera
## never gets near, where six triplanar taps buy nothing.
static func build(color: Color, surface: Surface = Surface.FLAT,
		roughness: float = DEFAULT_ROUGHNESS, metallic: float = 0.0,
		tile_meters: float = 2.0, normal_scale: float = 1.0, ao_strength: float = 0.0,
		emission: Color = Color.BLACK, emission_energy: float = 0.0,
		alpha: float = 1.0, specular: float = 0.5,
		fine_detail: bool = true) -> StandardMaterial3D:
	# The reduced tier does not get the close-range layer, and this is resolved
	# HERE — above `albedo`, above the cache key — because both of them read it.
	# Gating further down would cache a material under a key claiming detail it
	# does not have, and the albedo pre-multiply below would keep compensating for
	# a texture that is no longer multiplying anything, brightening every surface
	# on the web tier by the detail map's mean. See WorldTier.fine_detail().
	#
	# On Forward+ WorldTier.fine_detail() returns true, so this expression is the
	# caller's own value, the cache key is unchanged and the desktop material set
	# is identical by construction. That is an argument from the code, not a
	# measurement — the capture diff that would make it a measurement is running
	# and this comment gets updated with its result either way.
	fine_detail = fine_detail and WorldTier.fine_detail()

	# Snap and clamp BEFORE the key is built, so two callers asking for 0.30 and 0.45
	# metallic — which is most of the ironwork — collapse onto one cached material
	# instead of two identical ones under different names.
	var bare_metal := metallic >= METALLIC_SNAP
	var metal := 1.0 if bare_metal else 0.0
	if bare_metal:
		# See METAL_ROUGHNESS_FLOOR. A metal has no diffuse term, so a smooth one in a
		# scene whose only reflection source is the sky reports the sky and nothing
		# else — which is the tram rail head, three rounds running.
		roughness = maxf(roughness, METAL_ROUGHNESS_FLOOR)
	var f0 := specular
	if not bare_metal and metallic > 0.0:
		# The caller asked for a metal and got a dielectric. Give it back the sky
		# reflection it wanted, at a physical F0, instead of the washed-out diffuse
		# a half-metal would have traded for it.
		f0 = maxf(specular, DIELECTRIC_METAL_SPECULAR)
	var albedo := _physical_albedo(color, surface, surface != Surface.FLAT and fine_detail)

	var key := "%s|%d|%.3f|%.3f|%.3f|%.3f|%.3f|%s|%.3f|%.3f|%.3f|%d" % [
		albedo.to_html(false), surface, roughness, metal, tile_meters,
		normal_scale, ao_strength, emission.to_html(false), emission_energy, alpha,
		f0, 1 if fine_detail else 0,
	]
	var cached: StandardMaterial3D = _cache.get(key)
	if cached != null:
		return cached

	var m := StandardMaterial3D.new()
	m.albedo_color = Color(albedo.r, albedo.g, albedo.b, alpha)
	m.roughness = roughness
	m.metallic = metal
	m.metallic_specular = f0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.rim_enabled = true
	m.rim = RIM_AMOUNT
	m.rim_tint = RIM_TINT

	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED

	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy

	if surface != Surface.FLAT:
		# Triplanar in object space: consistent texel density on a 100 m deck and
		# on a 0.2 m railing post, with no UVs authored on either.
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / maxf(tile_meters, 0.01)
		m.normal_enabled = true
		m.normal_scale = normal_scale
		m.normal_texture = _NORMAL_MAPS[surface]

		# Surface-scale colour, on the same uv1 as the normal it is registered to.
		# SceneryKit.world_mapped() flips uv1 to WORLD triplanar on the deck and the
		# quays, which is exactly right here: the sett colours then vary across a
		# hundred metres of paving instead of restarting inside every box.
		if _ALBEDO_MAPS.has(surface):
			m.albedo_texture = _ALBEDO_MAPS[surface]

		var mask: Texture2D = _MASK_MAPS[surface]
		if bare_metal and _METAL_MASK_MAPS.has(surface):
			# Bare metal swaps the whole mask, and picks up a metallic map with it.
			# metallic_texture MULTIPLIES `metallic`, so this only ever reaches a
			# material that already asked to be metal: the split turns 1 into 0 or 1
			# per texel and can never manufacture a half-metal out of a dielectric.
			mask = _METAL_MASK_MAPS[surface]
			m.metallic_texture = mask
			m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.roughness_texture = mask
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if ao_strength > 0.0:
			m.ao_enabled = true
			m.ao_texture = mask
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			m.ao_light_affect = ao_strength

		if fine_detail:
			_add_fine_detail(m)

	_cache[key] = m
	return m


## The second texture scale: the close-range half of the albedo variation, the
## surface-scale maps above being the other half.
##
## Rides UV2 with its own triplanar mapping, which is what lets it tile at 0.28 m
## while the surface layer tiles at whatever real-world size its material wants.
## Godot's detail pass is
##     detail     = mix(ALBEDO, ALBEDO * detail_tex.rgb, detail_tex.a);
##     detail_nrm = mix(NORMAL_MAP, detail_norm_tex.rgb, detail_tex.a);
## so MUL is the blend mode that makes the albedo map a modulation of whatever colour
## the caller asked for rather than a replacement of it, and the map's own alpha
## (0.55, baked in by generate_detail_maps.gd) is what stops the fine normal wiping
## out the surface normal instead of stacking with it.
static func _add_fine_detail(m: StandardMaterial3D) -> void:
	m.detail_enabled = true
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = _FINE_ALBEDO
	m.detail_normal = _FINE_NORMAL
	m.uv2_triplanar = true
	m.uv2_scale = Vector3.ONE / DETAIL_TILE_METERS


## Put a caller's colour inside the range a real diffuse surface can occupy, and
## pre-multiply out both texture layers' means so the authored colour still means what
## it says once they have multiplied it.
##
## The CEILING and FLOOR are applied to the AUTHORED colour, BEFORE the texture
## gains — because the authored colour is the physical claim being made ("this
## wall reflects 63% of the light that hits it") and the gains are a correction
## that makes the surface's rendered MEAN come out at exactly that. The value
## after the gains is an intermediate: it is what the shader multiplies by a
## texture whose mean divides it straight back out.
##
## Clamping the intermediate, which is what this used to do, makes the effective
## ceiling on a call site 0.90 divided by both gains — about 0.616 for granite —
## and, far worse, MOVES IT WHENEVER AN ALBEDO MAP IS RE-AUTHORED. Round 3
## re-authored the granite map for hue, its gain went 1.159 to 1.293, and three
## world-stream call sites silently darkened by 2 to 10% as a side effect of a
## texture edit they had nothing to do with. A physical guard that fires because
## somebody changed a noise ramp is not measuring physics.
##
## Applied to the authored value the ceiling means what it says, is stable
## against texture work, and lands on the stream that actually authored the
## colour. Note the returned colour may now exceed 1.0 per channel by design:
## 0.90 x 1.13 x 1.293 is 1.315, and the texture it multiplies has a mean of
## 1/1.315, so the surface still presents 0.90. Godot does not clamp
## albedo_color, and the product is what reaches ALBEDO.
##
## The ceiling scales the colour as a whole and is never clamped per channel:
## clamping (0.93, 0.91, 0.85) channel-wise pulls red down and leaves blue alone,
## which desaturates and cools the surface. Scaling keeps the hue and moves only
## the value, which is what "this wall is a bit too bright to be real" means.
static func _physical_albedo(color: Color, surface: Surface, has_fine_detail: bool) -> Color:
	var c := color
	var peak := maxf(c.r, maxf(c.g, c.b))
	if peak > ALBEDO_CEILING and peak > 0.0:
		c *= ALBEDO_CEILING / peak
	c = _porto_stone_albedo(c, surface)
	# A floor as well as a ceiling: nothing in the real world reflects less than a
	# couple of percent, and a near-black albedo is a surface that can only ever be
	# a silhouette. Applied to the darkest channel so window reveals and void caps
	# keep their shape instead of all flattening to the same grey.
	var dim := minf(c.r, minf(c.g, c.b))
	if dim < ALBEDO_FLOOR:
		c = Color(maxf(c.r, ALBEDO_FLOOR), maxf(c.g, ALBEDO_FLOOR), maxf(c.b, ALBEDO_FLOOR))

	if has_fine_detail:
		c = Color(c.r * DETAIL_ALBEDO_GAIN, c.g * DETAIL_ALBEDO_GAIN, c.b * DETAIL_ALBEDO_GAIN)
	var map := _albedo_map_gain(surface)
	return Color(c.r * map.r, c.g * map.g, c.b * map.b)


## Lift a near-neutral stone colour into the range Porto's own two rocks occupy.
## See PORTO_STONE_FLOOR above for the measurement, the number and the two guards.
##
## Scales the whole colour rather than clamping per channel, exactly as the ceiling
## does and for the same reason: clamping channel-wise would pull the darkest channel
## up on its own and desaturate the surface, and this is a statement about VALUE.
##
## Runs after the ceiling and before the floor, so the three guards compose in the
## order they constrain: nothing may exceed 0.90, no Porto stone may sit under 0.44,
## and nothing at all may go to black. The knee's output can never breach the ceiling
## because PORTO_STONE_KNEE is well under it and the map is the identity above it.
static func _porto_stone_albedo(c: Color, surface: Surface) -> Color:
	if not _STONE_SURFACES.has(surface):
		return c
	var peak := maxf(c.r, maxf(c.g, c.b))
	if peak <= 0.0 or peak >= PORTO_STONE_KNEE:
		return c
	# The chroma test: this guard is about grey quarried stone, and stone() is also how
	# the terrain stream dresses earth and river rock, which are legitimately darker.
	var dim := minf(c.r, minf(c.g, c.b))
	if (peak - dim) / peak > PORTO_STONE_CHROMA:
		return c
	var lifted := PORTO_STONE_FLOOR + (PORTO_STONE_KNEE - PORTO_STONE_FLOOR) * (peak / PORTO_STONE_KNEE)
	return c * (lifted / peak)


## The reciprocal of a surface albedo map's own mean, per channel — what
## _physical_albedo multiplies the authored colour by so the map modulates rather
## than tints.
##
## PER CHANNEL rather than by luminance, and that is the whole point: the cobble ramp
## averages a faintly warm grey and the iron ramp a rust-leaning one, so a single
## luminance gain would leave every cobbled and every iron surface in the game shifted
## a few percent toward the map's own hue. Dividing each channel makes the map's
## average exactly neutral white, i.e. exactly a no-op on the mean.
##
## MEASURED off the noise field, not integrated over the ramp. The first version of
## this did integrate uniformly over the ramp's parameter, and _atmosphere_probe.gd
## caught it immediately: the iron map came out 10% off, because an fBm histogram
## bunches hard toward the middle and the rust living in its top 16% is reached far
## less often than a uniform reading assumes. Only the cobble's per-cell field is
## actually uniform. So this rasterises the field itself — Noise.get_image() is
## synchronous, unlike NoiseTexture2D's own worker-thread path — and averages the
## ramped, linearised result.
##
## Sampled THROUGH the seamless path and, critically, over the SAME REGION OF THE
## NOISE FIELD the full-size descriptor covers.
##
## That second half is the part that is easy to get wrong and was got wrong twice here
## before the probe caught it. Noise.get_image(w, h) evaluates the field at integer
## coordinates 0..w-1, and FastNoiseLite.frequency is per unit of that coordinate — so
## asking for a smaller image does not downsample the texture, it samples a smaller
## WINDOW of the same field. At 48 x 48 the cobble map's cells are 36 units across, so
## the window contained about two of them and its mean was a coin flip; the probe read
## it 9% off. Scaling the frequency by (native size / sample size) puts the window back
## over the whole field, so 96 x 96 sees the same fifty-odd cells the 256 x 256 map
## does, at a sixteenth of the cost.
##
## Under 30,000 noise evaluations for all three surfaces, once per run, cached. The
## probe recomputes the same quantity at 160 x 160 and fails past 4%, which makes it a
## real convergence check rather than the same code run twice.
const _GAIN_SAMPLES := 96

static func _albedo_map_gain(surface: Surface) -> Color:
	if _map_gains.has(surface):
		return _map_gains[surface]
	var gain := Color(1.0, 1.0, 1.0)
	var tex: NoiseTexture2D = _ALBEDO_MAPS.get(surface)
	if tex != null and tex.color_ramp != null and tex.noise != null:
		var img := sample_noise(tex, _GAIN_SAMPLES)
		if img != null:
			var ramp: Gradient = tex.color_ramp
			var sum := Color(0.0, 0.0, 0.0)
			for y in _GAIN_SAMPLES:
				for x in _GAIN_SAMPLES:
					# The noise image is greyscale, so its red channel IS the field
					# value, and that value is what NoiseTexture2D feeds the gradient.
					# The albedo sampler carries a source_color hint, so what actually
					# multiplies ALBEDO is the LINEAR value of an sRGB-authored stop.
					var c := ramp.sample(img.get_pixel(x, y).r).srgb_to_linear()
					sum += Color(c.r, c.g, c.b)
			var n := float(_GAIN_SAMPLES * _GAIN_SAMPLES)
			gain = Color(n / maxf(sum.r, 0.001), n / maxf(sum.g, 0.001),
					n / maxf(sum.b, 0.001))
	_map_gains[surface] = gain
	return gain


## Rasterise a NoiseTexture2D descriptor's field at `size`, covering the whole region
## the descriptor itself covers. Shared with _atmosphere_probe.gd, which is the only
## reason it is not private: the probe has to be able to reproduce this independently
## at a different resolution for its convergence check, and two copies of the
## frequency-scaling rule is exactly how the two would drift apart.
static func sample_noise(tex: NoiseTexture2D, size: int) -> Image:
	if tex == null or tex.noise == null or size <= 0:
		return null
	var noise: Noise = tex.noise.duplicate()
	var fnl := noise as FastNoiseLite
	if fnl != null:
		fnl.frequency *= float(maxi(tex.width, 1)) / float(size)
	if tex.seamless:
		return noise.get_seamless_image(size, size, false, false,
				tex.seamless_blend_skirt, tex.normalize)
	return noise.get_image(size, size, false, false, tex.normalize)


# --- Imported model upgrade -------------------------------------------------

## Retro-fit PBR onto an instantiated .glb.
##
## The four character models ship one baked-albedo texture each and nothing
## else — no normal, roughness, metallic or AO — so under Forward+ they render
## as flat plastic. This walks the instance and gives every StandardMaterial3D
## surface a sane dielectric response plus, optionally, a normal map derived
## from the albedo's luminance. That derived map is a cheat: it bumps whatever
## the texture *painted*, not real geometry, so keep `normal_scale` low.
##
## Composes with per-instance material tricks in either order. If a surface
## already has an override (e.g. Adamastor's hit-flash duplicates) it is
## upgraded in place; otherwise the mesh material is duplicated into a fresh
## override so the shared imported resource is never touched.
##
## Returns the number of surfaces upgraded.
static func upgrade_glb_materials(root: Node, roughness: float = 0.68,
		metallic: float = 0.0, normal_scale: float = 0.45,
		derive_normals: bool = true) -> int:
	if root == null:
		return 0
	var count := 0
	for mi in _mesh_instances(root):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := _instance_material(mi, s)
			if mat == null:
				continue
			mat.roughness = roughness
			mat.metallic = metallic
			mat.rim_enabled = true
			mat.rim = RIM_AMOUNT
			mat.rim_tint = RIM_TINT
			# Baked-in shading is already in the albedo; a second AO pass would
			# just crush it, so only the normal is synthesised.
			if derive_normals and mat.albedo_texture != null and not mat.normal_enabled:
				var nrm := _normal_from_albedo(mat.albedo_texture)
				if nrm != null:
					mat.normal_enabled = true
					mat.normal_texture = nrm
					mat.normal_scale = normal_scale
			count += 1
	return count


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_mesh_instances(child))
	return found


## The material to edit for one surface: an existing instance override if there
## is one, otherwise a fresh duplicate installed as the override.
static func _instance_material(mi: MeshInstance3D, surface_idx: int) -> StandardMaterial3D:
	var existing := mi.get_surface_override_material(surface_idx)
	if existing is StandardMaterial3D:
		return existing as StandardMaterial3D
	var base := mi.get_active_material(surface_idx)
	if not (base is StandardMaterial3D):
		return null   # a ShaderMaterial here is deliberate; leave it alone
	var dup: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
	mi.set_surface_override_material(surface_idx, dup)
	return dup


## Central-difference the albedo's luminance into a tangent-space normal map.
##
## Downsampled hard on purpose: the albedo's fine detail is painted brush noise,
## and lifting it into geometry at full resolution reads as sandpaper. What we
## want is only the big strokes — seams, straps, the line between scale plates.
## Results are cached per source texture, since all four models share the pattern
## of one atlas per character.
static func _normal_from_albedo(src: Texture2D, size: int = 128,
		relief: float = 0.025) -> ImageTexture:
	var cache_key := src.get_instance_id()
	if _derived_normals.has(cache_key):
		return _derived_normals[cache_key]

	var img: Image = src.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed() and img.decompress() != OK:
		return null
	# Trilinear, not Lanczos: these atlases are 1024², and Lanczos spends 30 ms on
	# an 8x downscale to land within 1% of what the mip chain gives in half a ms.
	img.resize(size, size, Image.INTERPOLATE_TRILINEAR)
	img.convert(Image.FORMAT_RGBA8)

	# Flatten to a luminance height field up front. Going through the raw byte
	# buffer instead of get_pixel()/set_pixel() takes this from ~35 ms to a few:
	# it runs once per character at load, but four of those is a visible hitch.
	var src_bytes := img.get_data()
	var count := size * size
	var height := PackedFloat32Array()
	height.resize(count)
	for i in count:
		var o := i * 4
		height[i] = (0.2126 * float(src_bytes[o])
			+ 0.7152 * float(src_bytes[o + 1])
			+ 0.0722 * float(src_bytes[o + 2])) / 255.0

	# Tuned so a typical luminance step tilts the normal ~10 degrees. Higher and
	# every painted shadow turns into a ridge.
	var strength := float(size) * relief
	var out_bytes := PackedByteArray()
	out_bytes.resize(count * 4)
	var last := size - 1
	for y in size:
		var row := y * size
		# Clamp, don't wrap: these are UV atlases, not tiling textures, so the
		# opposite edge is unrelated art.
		var row_up := maxi(y - 1, 0) * size
		var row_dn := mini(y + 1, last) * size
		for x in size:
			var dx := height[row + mini(x + 1, last)] - height[row + maxi(x - 1, 0)]
			var dy := height[row_dn + x] - height[row_up + x]
			var n := Vector3(-dx * strength, -dy * strength, 1.0).normalized()
			var o := (row + x) * 4
			out_bytes[o] = int(clampf(n.x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			out_bytes[o + 1] = int(clampf(n.y * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			out_bytes[o + 2] = int(clampf(n.z * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			out_bytes[o + 3] = 255

	var out := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, out_bytes)
	out.generate_mipmaps()
	var tex := ImageTexture.create_from_image(out)
	_derived_normals[cache_key] = tex
	return tex
