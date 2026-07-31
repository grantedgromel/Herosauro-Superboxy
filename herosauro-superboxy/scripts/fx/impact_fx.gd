class_name ImpactFX
extends Node3D
## Leg one of the impact contract: **the visual FX at the point of contact.**
##
## ARCHITECTURE.md, "Weight — every action": every hit, land, smash and spin
## needs a visual FX at the point of contact, a camera response, an audio
## transient, a hit-stop, and a UI acknowledgement. Four of the five already have
## owners — `GameManager.request_shake`, `AudioManager`, `GameManager.hit_stop`
## and the HUD — and every impact in the game reaches at least three of them.
## Leg one had two implementations in the whole project (the shockwave's torus,
## and Dino Energy's burst, which renders nothing at all — see the report), so
## it is the leg that was missing everywhere. This class is it.
##
## ONE CALL PER IMPACT. Three shapes, because impacts genuinely come in three:
##
##   `spark()`   a blow landing ON something. Chips fly away from the attacker
##               and a bright core flashes. Hero jabs, Boxy's dash connect, a
##               rock catching a hero, an orb bursting on the giant.
##   `ground()`  something heavy arriving on a surface. A dust ring rolls
##               outward and chips are kicked up off the deck. The slam, a rock
##               landing, a hero landing from a fall, the giant's corpse.
##   `smash()`   a body coming apart. A fan of shards with real size, shape and
##               colour variety, a dust cloud, a ground ring, and optionally a
##               second material for trim (a barrel's iron hoops) and a liquid
##               (a barrel's port). This is the Crash crate-smash.
##
## --- THE SURFACE IMPACT TABLE -----------------------------------------------
##
## `ToonFactory.Surface` is the vocabulary `materials`, `fx` and `audio` share,
## and ARCHITECTURE.md requires that adding a surface adds a case in the fx
## impact table in the same commit. `impact_row()` IS that table.
##
## It is a `match` with one case per surface and no silent default: the fallback
## pushes an error and echoes `Surface.FLAT` back in the row's own `surface`
## key, and `_fx_probe` fails the build when `impact_row(s)["surface"] != s`. A
## surface added to the enum therefore cannot quietly inherit granite's chips —
## it fails the probe on the next run.
##
## What the table varies, and why each one is load-bearing:
##
##   * SHARD SHAPE. Wood splinters (long, thin), granite chips (blocky),
##     terracotta and plaster flake (flat plates), iron curls off in slivers.
##     One shard proportion per surface is the single biggest reason a rock
##     hitting wood does not look like a rock hitting granite.
##   * DUST VOLUME. Limewashed plaster powders enormously; painted steel does
##     not powder at all and throws sparks instead. Stone and calçada sit
##     between, and the loose lime grout between setts is why the deck dusts
##     more than the granite kerb beside it.
##   * COLOUR, at two levels. The row's own tints, plus a per-shard modulation
##     (`tint_var`) so no two chips in a burst are the same value — the RUBRIC's
##     first material rule, applied to something that only exists for a second.
##   * BOUNCE and SPIN. Iron rings off hard and spins fast; plaster flakes drop
##     dead where they land.
##
## --- COST -------------------------------------------------------------------
##
## Particles are cheap per instance and ruinous in aggregate, so nothing here is
## a particle system. Every burst is MultiMesh — one draw call for up to 24
## shards, one for up to 14 puffs — plus a single annulus baked once for the
## whole process, and it is bounded twice over:
##
##   * `MAX_LIVE` bursts exist at once, process-wide, counted the way
##     `DebrisPiece` counts shards. A caller past the budget gets `null`, which
##     means "draw fewer", never an error.
##   * `MAX_SHARDS` / `MAX_DUST` cap one burst.
##
## Worst case is 10 bursts x 4 draw calls = 40, and 380 instances, for about a
## second, and only when a slam catches five barrels at once. Typical is one
## burst of three. `_fx_probe` measures the peak across a scripted fight rather
## than trusting this note.
##
## --- DETERMINISM ------------------------------------------------------------
##
## Every burst owns a `RandomNumberGenerator` seeded from its own arguments (or,
## when the caller passes 0, from its world position), never the global
## `randf()` family, and every animation is a closed-form function of an
## accumulated `delta` and never reads a clock. ARCHITECTURE.md rules 4 and 5,
## and `_fx_probe` asserts both by building the same burst twice and comparing
## every shard transform.
##
## --- SPACE ------------------------------------------------------------------
##
## The simulation runs in the BURST'S OWN LOCAL SPACE, origin at the point of
## contact. That is not a detail: Godot derives a MultiMesh's bounding box from
## its instance buffer, our instances move every frame, and a MultiMesh whose
## bounds are stale or centred somewhere else is a burst that vanishes the
## moment the camera turns — a bug that only ever shows up in a capture. Local
## space lets `custom_aabb` be one fixed box around the origin that is always
## right.

# --- Budget ------------------------------------------------------------------

## Bursts alive at once, process-wide. Six is the worst case the game can
## actually produce in one frame — a slam catching five barrels plus its own
## ground burst — so ten leaves room for the tail of the previous beat without
## letting a phase-two volley into a crowd open the door to forty of them.
const MAX_LIVE := 10
## Shards in one burst. Past about twenty the fan stops reading as pieces and
## starts reading as noise, and it is one draw call either way, so the count is
## a legibility decision rather than a cost one.
const MAX_SHARDS := 24
## Dust puffs in one burst. These are the alpha-pass half and the only part of a
## burst that costs overdraw, so they are capped tighter than the shards.
const MAX_DUST := 14

# --- Public vocabulary -------------------------------------------------------

## Passed as `trim` to `smash()` for a prop whose furniture is a different
## material from its body — a wine barrel's iron hoops against its wood staves.
const TRIM_NONE := -1
## Passed as `liquid` to `smash()` for a prop that was full of something. Costs
## no extra draw call: the droplets ride the dust MultiMesh with their own
## colour and their own (ballistic, not drifting) motion.
const NO_LIQUID := Color(0.0, 0.0, 0.0, 0.0)
## Ruby port, for the Douro barrels stacked along the deck. Dark, red-black in
## shadow, and the reason a barrel bursting on this bridge is a Porto moment
## rather than a generic crate smash.
const PORT_WINE := Color(0.30, 0.045, 0.09, 0.9)

enum Kind {
	SPARK,   ## a blow landing on something: chips away from the attacker, a core flash
	GROUND,  ## something heavy arriving on a surface: a dust ring and kicked-up chips
	SMASH,   ## a body coming apart: shards, dust, ring, optional trim and liquid
}

# --- Simulation constants ----------------------------------------------------

## Gravity on shards, well above the world's 9.8. Debris that falls at the real
## rate reads as floaty at this scale — the same reason PlayerBase runs the
## heroes at 30 — and a chip that snaps back down to the deck is what sells the
## blow that threw it.
const SHARD_GRAVITY := 26.0
## Air drag on dust, as a rate. The closed-form integral of a damped drift,
## `v0 * (1 - exp(-k t)) / k`, is used instead of stepping a velocity, so a
## puff's path is a pure function of its age and two runs of the same frame
## cannot disagree.
const DUST_DRAG := 2.6
## Fraction of a shard's life spent shrinking out. A shard that vanishes at full
## size pops; one that shrinks over its last quarter recedes — the same trick
## DebrisPiece uses on its rigid bodies, for the same reason (a fade would need
## a per-piece material and an alpha-pass draw).
const SHARD_SHRINK := 0.26
## Segments in the shared ground ring. 40 is smooth at the fifteen metres the
## shockwave scales it out to, and still only 160 triangles.
const RING_SEGMENTS := 40
## Ring wall as a fraction of its radius, and how far its inner lip stands
## proud. The lip is what stops the ring reading as a decal: it makes a shallow
## cone, so the key light catches one side of it and not the other.
const RING_WALL := 0.22
const RING_LIP := 0.26
## How far above the surface the ring floats. Same reasoning as
## `BossTelegraph.LIFT` — enough to clear z-fighting on granite at a grazing
## angle, not enough to read as a card hovering over the deck.
const RING_LIFT := 0.06

## Per-kind node lifetimes, in seconds. The node frees itself at the end of the
## longest thing it is drawing; `_fx_probe` measures that it actually does.
const SPARK_LIFE := 0.45
const GROUND_LIFE := 1.05
const SMASH_LIFE := 1.35
## The ring is punctuation on the front of a burst, not the whole burst, so it
## always finishes well before the dust does — and it frees itself when it does,
## rather than sitting at zero alpha still costing a draw call.
const RING_LIFE := 0.42
## The core flash. Eight frames at 90 Hz: long enough to register, short enough
## that it can never sit in a screenshot as a white blob.
const FLASH_LIFE := 0.09

## Shard material tile size, in metres. The named ToonFactory helpers tile
## granite at 2.4 m and wood at 1.1 m, which across a 10 cm chip is one flat
## colour — the RUBRIC's first material failure. At 0.22 m the surface map and
## the shared fine layer both still resolve on something the size of a thumbnail.
const CHIP_TILE := 0.22

## The prop half-extent the table's shard sizes are authored against — a wine
## barrel's radius. `smash()` scales chips by the real extent over this, so a
## crate and a barrel throw proportionate pieces.
const REFERENCE_EXTENT := 0.45

static var _live: int = 0
static var _ring_mesh: Mesh = null
static var _shard_mesh: Mesh = null
static var _dust_mesh: Mesh = null
static var _flash_mesh: Mesh = null
static var _shard_mats: Dictionary = {}
static var _dust_mat: StandardMaterial3D = null

var kind: int = Kind.GROUND
var life: float = GROUND_LIFE

var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _counted: bool = false
## In LOCAL space, so zero is the contact plane for a ground burst.
var _floor_y: float = -1.0e9

# Shards. Parallel packed arrays rather than an array of objects: this is the
# hot loop, it runs over up to 24 pieces every frame, and a burst that allocates
# is a burst that hitches the frame it was supposed to decorate.
var _sh_pos: PackedVector3Array = PackedVector3Array()
var _sh_vel: PackedVector3Array = PackedVector3Array()
var _sh_size: PackedVector3Array = PackedVector3Array()
var _sh_axis: PackedVector3Array = PackedVector3Array()
var _sh_rate: PackedFloat32Array = PackedFloat32Array()
var _sh_phase: PackedFloat32Array = PackedFloat32Array()
var _sh_life: PackedFloat32Array = PackedFloat32Array()
var _sh_bounce: float = 0.25
## Index at which the trim shards start; `_sh_split == _sh_pos.size()` means no
## trim. Trim pieces live in the same simulation arrays and are drawn by a
## second MultiMesh, so a barrel's hoops obey exactly the same physics as its
## staves and cost one extra draw call rather than a whole second burst.
var _sh_split: int = 0

# Dust and droplets.
var _du_pos: PackedVector3Array = PackedVector3Array()
var _du_vel: PackedVector3Array = PackedVector3Array()
var _du_size: PackedVector2Array = PackedVector2Array()   # (start, end) radius
var _du_life: PackedFloat32Array = PackedFloat32Array()
var _du_tint: PackedColorArray = PackedColorArray()
## 0 = dust (damped drift, grows, fades), 1 = droplet (ballistic, keeps its size).
var _du_kind: PackedByteArray = PackedByteArray()

var _shards: MultiMeshInstance3D = null
var _trim: MultiMeshInstance3D = null
var _dust: MultiMeshInstance3D = null
var _ring: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _ring_radius: float = 2.0
var _ring_alpha: float = 0.4
var _flash: MeshInstance3D = null
var _flash_mat: StandardMaterial3D = null
var _flash_radius: float = 0.28


# --- The surface impact table -------------------------------------------------

## The fx half of the `ToonFactory.Surface` contract. One case per surface, no
## silent default: `_fx_probe` asserts `impact_row(s)["surface"] == s` for every
## value of the enum, so adding `Surface.SLATE` without adding a case here fails
## the build rather than quietly shipping granite chips on a slate roof.
##
## Every number is a look decision and the argument for it sits next to it. The
## keys are stable public API — `shockwave.gd` reads `ring_tint` and `dust_tint`
## off the same rows, so a slam on the deck and a rock landing on it agree about
## what the deck is made of.
static func impact_row(surface: int) -> Dictionary:
	match surface:
		ToonFactory.Surface.GRANITE:
			# Porto granite: cool, damp, and it breaks into blocky angular chunks
			# rather than flakes. Bounces a little — a chip off a kerb skitters.
			return {
				"surface": ToonFactory.Surface.GRANITE,
				"chip": Vector3(1.00, 0.72, 0.86), "chip_size": 0.11, "chips": 10,
				"chip_speed": Vector2(3.2, 7.5), "chip_bounce": 0.28, "chip_spin": 11.0,
				"chip_glow": 0.0, "tint_var": 0.16,
				"dust": 8, "dust_tint": Color(0.72, 0.71, 0.68),
				"dust_rise": 1.5, "dust_out": 2.6, "dust_life": 0.95,
				"dust_size": Vector2(0.35, 1.50),
				"ring_tint": Color(0.80, 0.79, 0.75), "ring_alpha": 0.42,
				"flash_tint": Color(1.00, 0.94, 0.82), "flash_energy": 2.4,
			}
		ToonFactory.Surface.COBBLE:
			# Calçada setts: smaller cubes than the kerb granite, warmer, and
			# dustier — the grout between setts is loose lime and it is what comes
			# up first when anything lands on the deck.
			return {
				"surface": ToonFactory.Surface.COBBLE,
				"chip": Vector3(1.00, 0.90, 1.00), "chip_size": 0.09, "chips": 11,
				"chip_speed": Vector2(3.0, 6.8), "chip_bounce": 0.22, "chip_spin": 10.0,
				"chip_glow": 0.0, "tint_var": 0.20,
				"dust": 9, "dust_tint": Color(0.70, 0.67, 0.61),
				"dust_rise": 1.4, "dust_out": 3.0, "dust_life": 1.00,
				"dust_size": Vector2(0.32, 1.60),
				"ring_tint": Color(0.76, 0.73, 0.66), "ring_alpha": 0.40,
				"flash_tint": Color(1.00, 0.93, 0.78), "flash_energy": 2.0,
			}
		ToonFactory.Surface.IRON:
			# Painted structural steel does not powder, so it gets almost no dust —
			# the three puffs are chalked paint, not stone. What it does instead is
			# throw long fast slivers that spin hard, ring off whatever they land on
			# and GLOW: `chip_glow` puts emission on this surface's shard material,
			# which is why a blow on the lattice reads as sparks and the same blow
			# on the kerb does not, at no extra draw call.
			return {
				"surface": ToonFactory.Surface.IRON,
				"chip": Vector3(2.20, 0.14, 0.40), "chip_size": 0.10, "chips": 14,
				"chip_speed": Vector2(5.5, 11.0), "chip_bounce": 0.42, "chip_spin": 22.0,
				"chip_glow": 3.4, "tint_var": 0.10,
				"dust": 3, "dust_tint": Color(0.34, 0.33, 0.34),
				"dust_rise": 0.9, "dust_out": 1.6, "dust_life": 0.50,
				"dust_size": Vector2(0.20, 0.70),
				"ring_tint": Color(1.00, 0.62, 0.24), "ring_alpha": 0.30,
				"flash_tint": Color(1.00, 0.78, 0.36), "flash_energy": 4.2,
			}
		ToonFactory.Surface.PLASTER:
			# Limewash. Flat chalky flakes that drop dead where they land (the
			# lowest bounce of the seven) and an enormous amount of white dust — the
			# biggest cloud in the table, and the reason a blow on a Ribeira facade
			# reads completely differently from the same blow on the deck.
			return {
				"surface": ToonFactory.Surface.PLASTER,
				"chip": Vector3(1.30, 0.20, 1.20), "chip_size": 0.10, "chips": 8,
				"chip_speed": Vector2(2.4, 5.5), "chip_bounce": 0.12, "chip_spin": 8.0,
				"chip_glow": 0.0, "tint_var": 0.12,
				"dust": 13, "dust_tint": Color(0.92, 0.90, 0.85),
				"dust_rise": 2.1, "dust_out": 3.2, "dust_life": 1.25,
				"dust_size": Vector2(0.40, 2.10),
				"ring_tint": Color(0.94, 0.92, 0.87), "ring_alpha": 0.50,
				"flash_tint": Color(1.00, 1.00, 0.95), "flash_energy": 1.8,
			}
		ToonFactory.Surface.TERRACOTTA:
			# Fired roof tile: wide flat curved shards, and a red dust that settles
			# fast because the particles are heavy. The only warm ring in the table
			# apart from iron's sparks.
			return {
				"surface": ToonFactory.Surface.TERRACOTTA,
				"chip": Vector3(1.50, 0.16, 1.00), "chip_size": 0.12, "chips": 10,
				"chip_speed": Vector2(3.0, 7.0), "chip_bounce": 0.18, "chip_spin": 14.0,
				"chip_glow": 0.0, "tint_var": 0.18,
				"dust": 7, "dust_tint": Color(0.66, 0.38, 0.28),
				"dust_rise": 1.5, "dust_out": 2.6, "dust_life": 0.85,
				"dust_size": Vector2(0.30, 1.40),
				"ring_tint": Color(0.70, 0.36, 0.24), "ring_alpha": 0.42,
				"flash_tint": Color(1.00, 0.72, 0.50), "flash_energy": 2.2,
			}
		ToonFactory.Surface.WOOD:
			# Barrel staves and crate boards. The longest, thinnest shard in the
			# table (2.8 : 0.22 : 0.5), because a splinter IS the read; the widest
			# tint spread of the seven — pale sapwood inside against weathered
			# outside, which is what a broken board actually looks like — and very
			# little dust, because wood does not make any.
			return {
				"surface": ToonFactory.Surface.WOOD,
				"chip": Vector3(2.80, 0.22, 0.50), "chip_size": 0.13, "chips": 12,
				"chip_speed": Vector2(3.4, 7.8), "chip_bounce": 0.15, "chip_spin": 13.0,
				"chip_glow": 0.0, "tint_var": 0.22,
				"dust": 5, "dust_tint": Color(0.60, 0.48, 0.34),
				"dust_rise": 1.1, "dust_out": 2.2, "dust_life": 0.70,
				"dust_size": Vector2(0.25, 1.10),
				"ring_tint": Color(0.62, 0.48, 0.32), "ring_alpha": 0.30,
				"flash_tint": Color(1.00, 0.86, 0.60), "flash_energy": 1.6,
			}
		ToonFactory.Surface.FLAT:
			# The deliberate fallback, and the right answer for a blow that lands on
			# something not made of anything in particular — a hero, an orb, a
			# collider nobody has tagged yet. Neutral, small, short: it reads as
			# impact without claiming a material.
			return {
				"surface": ToonFactory.Surface.FLAT,
				"chip": Vector3(1.00, 0.60, 0.90), "chip_size": 0.08, "chips": 6,
				"chip_speed": Vector2(2.8, 6.0), "chip_bounce": 0.20, "chip_spin": 9.0,
				"chip_glow": 0.0, "tint_var": 0.14,
				"dust": 5, "dust_tint": Color(0.78, 0.77, 0.74),
				"dust_rise": 1.3, "dust_out": 2.0, "dust_life": 0.60,
				"dust_size": Vector2(0.30, 1.20),
				"ring_tint": Color(0.85, 0.85, 0.85), "ring_alpha": 0.30,
				"flash_tint": Color(1.00, 1.00, 1.00), "flash_energy": 2.0,
			}
		_:
			# No silent default. A surface added to the enum without a case here is
			# a bug the moment it ships, and this is the line that says so — plus
			# `_fx_probe` fails on the echoed `surface` not matching the argument.
			push_error("ImpactFX: no impact-table case for ToonFactory.Surface %d" % surface)
			return impact_row(ToonFactory.Surface.FLAT)


## Which surface a node is made of, for a caller who has a collider and not a
## material. Three routes, in order, and all three are duck-typed so no stream
## has to import another's script:
##
##   1. an `fx_surface` property (int) on the node. This is the opt-in hook: any
##      stream that wants its geometry to chip correctly declares one variable.
##   2. a `surface` String, which is what `PropBody` already exports —
##      "wood" / "stone" / "iron" / "cobble" — so every prop in the game
##      resolves today without the props stream changing a line.
##   3. group membership. Adamastor is literally a stone giant, so a blow that
##      lands on him throws granite.
##
## Falls back to `fallback` rather than guessing, and the caller picks that.
static func surface_of(node: Node, fallback: int = ToonFactory.Surface.FLAT) -> int:
	if node == null or not is_instance_valid(node):
		return fallback
	if "fx_surface" in node:
		return int(node.get("fx_surface"))
	if "surface" in node:
		var named := surface_named(str(node.get("surface")), -1)
		if named >= 0:
			return named
	if node.is_in_group("boss"):
		return ToonFactory.Surface.GRANITE
	return fallback


## String -> Surface, matching the names `PropBody.surface` exports and the names
## ToonFactory's helpers carry. Kept next to the table so the two cannot drift.
static func surface_named(name: String, fallback: int = ToonFactory.Surface.FLAT) -> int:
	match name.to_lower():
		"stone", "granite":
			return ToonFactory.Surface.GRANITE
		"iron", "steel", "metal":
			return ToonFactory.Surface.IRON
		"cobble", "cobblestone", "calcada":
			return ToonFactory.Surface.COBBLE
		"plaster", "render", "limewash":
			return ToonFactory.Surface.PLASTER
		"terracotta", "tile", "clay":
			return ToonFactory.Surface.TERRACOTTA
		"wood", "timber":
			return ToonFactory.Surface.WOOD
		"flat", "none":
			return ToonFactory.Surface.FLAT
		_:
			return fallback


# --- Budget -------------------------------------------------------------------

## How many more bursts may be spawned right now. Callers must treat 0 as "draw
## fewer", never as an error — the same contract as `DebrisPiece.budget_left()`.
static func budget_left() -> int:
	return maxi(0, MAX_LIVE - _live)


static func live_count() -> int:
	return _live


# --- Spawn API ----------------------------------------------------------------

## A blow landing ON something. `into` is the direction the blow was travelling,
## so the chips spray away from the attacker rather than in a symmetric ball —
## which is the one cue that says who hit whom.
##
## `power` scales the count and the launch speed: 1.0 is a hero's jab, 2.0 is
## Boxy's dash. Returns null when the budget is spent or there is nowhere to
## parent it, which callers must treat as "no FX this time".
static func spark(from: Node, at: Vector3, into: Vector3, surface: int,
		power: float = 1.0, rng_seed: int = 0) -> ImpactFX:
	var fx := _make(from, at, Kind.SPARK, rng_seed)
	if fx == null:
		return null
	var row := impact_row(surface)
	# No floor: a jab lands at chest height on a nine-metre giant, and chips that
	# stopped dead at the contact plane would hang in mid-air. They fall and shrink
	# out instead, long before they would reach the deck.
	fx._floor_y = -1.0e9
	fx.life = SPARK_LIFE
	var aim := into.normalized() if into.length() > 0.01 else Vector3.UP
	fx._build_shards(row, surface, aim, 0.62, power, 1.0, TRIM_NONE)
	fx._build_flash(row, power)
	fx._finish()
	return fx


## Something heavy arriving on a surface. `radius` is how wide the dust ring
## sweeps — the slam's blast radius, a rock's crater, a hero's landing footprint.
##
## The chips are kicked UP out of the surface in a shallow cone rather than a
## hemisphere, which is what distinguishes an arrival from a body coming apart.
static func ground(from: Node, at: Vector3, surface: int, radius: float = 2.0,
		power: float = 1.0, rng_seed: int = 0) -> ImpactFX:
	var fx := _make(from, at, Kind.GROUND, rng_seed)
	if fx == null:
		return null
	var row := impact_row(surface)
	# The burst's origin IS the contact plane, so the local floor is zero.
	fx._floor_y = 0.0
	fx.life = GROUND_LIFE
	# 0.15 puts most of the spray between 40 and 80 degrees off the deck, which is
	# where debris off a real impact goes.
	fx._build_shards(row, surface, Vector3.UP, 0.15, power, 1.0, TRIM_NONE)
	fx._build_dust(row, radius * 0.35, power, NO_LIQUID)
	fx._build_ring(row, radius)
	fx._finish()
	return fx


## A body coming apart. The Crash crate-smash, and the one call
## `breakable_prop.gd` should make.
##
##   `extent`  the prop's half-extent — `BreakableProp._extent()` already
##             computes exactly this. Shard size scales with it, so a crate and a
##             barrel throw proportionate pieces.
##   `push`    the direction the blow was travelling. Biases every shard's launch
##             cone, so a swing throws the debris downrange.
##   `trim`    a second surface for the prop's furniture — a barrel's iron hoops
##             against its wood staves. `TRIM_NONE` for a plain crate. Costs one
##             extra draw call and buys the difference between a barrel and a box.
##   `liquid`  what the prop was full of. `ImpactFX.PORT_WINE` for the Douro
##             barrels; `NO_LIQUID` for anything dry. The droplets come out of
##             the dust budget rather than adding to it, so this is free.
static func smash(from: Node, at: Vector3, surface: int, extent: float = REFERENCE_EXTENT,
		push: Vector3 = Vector3.ZERO, rng_seed: int = 0,
		trim: int = TRIM_NONE, liquid: Color = NO_LIQUID) -> ImpactFX:
	var fx := _make(from, at, Kind.SMASH, rng_seed)
	if fx == null:
		return null
	var row := impact_row(surface)
	var reach: float = maxf(0.12, extent)
	# The floor sits a body-radius below the burst centre, which is where the deck
	# is under a prop resting on it. Shards land and skitter instead of sailing
	# through the world.
	fx._floor_y = -reach * 0.95
	fx.life = SMASH_LIFE
	var size_scale: float = clampf(reach / REFERENCE_EXTENT, 0.55, 2.2)
	# 0.42 is a far wider cone than `ground()`'s: a prop coming apart throws pieces
	# in every direction, biased by the blow rather than aimed by it.
	fx._build_shards(row, surface, _push_dir(push), 0.42, 1.35, size_scale, trim)
	fx._build_dust(row, reach * 1.1, 1.2, liquid)
	fx._build_ring(row, reach * 3.4)
	fx._finish()
	return fx


# --- Probe surface ------------------------------------------------------------
# Read by `_fx_probe`. A MultiMesh's instance buffer lives in the RenderingServer
# and is a no-op under --headless, so the probe cannot read it back; it measures
# the simulation these expose instead, which is the thing that actually varies.

func age() -> float:
	return _t


func shard_count() -> int:
	return _sh_pos.size()


func trim_count() -> int:
	return _sh_pos.size() - _sh_split


func dust_count() -> int:
	return _du_pos.size()


## Draw calls this burst costs right now: one per MultiMesh plus one per mesh.
## Falls as the ring and the flash retire themselves.
func emitter_count() -> int:
	var n := 0
	for e in [_shards, _trim, _dust, _ring, _flash]:
		if e != null and is_instance_valid(e):
			n += 1
	return n


## Where shard `i` is right now, in the burst's local space, with its rotation
## and per-piece scale. The determinism check compares these between two
## identically-seeded bursts.
func shard_transform(i: int) -> Transform3D:
	if i < 0 or i >= _sh_pos.size():
		return Transform3D.IDENTITY
	return _shard_xform(i, _t)


# --- Construction -------------------------------------------------------------

static func _make(from: Node, at: Vector3, p_kind: int, rng_seed: int) -> ImpactFX:
	if from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return null
	if budget_left() <= 0:
		return null
	var root := _spawn_root(from)
	if root == null:
		return null
	var fx := ImpactFX.new()
	fx.name = "ImpactFX"
	fx.kind = p_kind
	fx._rng.seed = rng_seed if rng_seed != 0 else _seed_from(at, p_kind)
	root.add_child(fx)
	fx.global_position = at
	return fx


## Transient FX go into the spawn root, like every other transient in the game,
## so `main.gd`'s between-runs sweep collects anything still alive when a fight
## restarts. Falls back exactly the way the boss and the props do.
static func _spawn_root(from: Node) -> Node3D:
	var root := from.get_tree().get_first_node_in_group("spawn_root") as Node3D
	if root != null:
		return root
	root = from.get_tree().current_scene as Node3D
	if root != null:
		return root
	return from.get_parent() as Node3D


## A seed derived from where the impact happened, so two runs of the same fight
## throw the same chips. Centimetre precision, because a physics solve is not
## bit-identical across builds and a millimetre of drift must not reshuffle a fan.
static func _seed_from(at: Vector3, p_kind: int) -> int:
	return hash("fx|%d|%.2f|%.2f|%.2f" % [p_kind, at.x, at.y, at.z])


static func _push_dir(push: Vector3) -> Vector3:
	if push.length() < 0.01:
		return Vector3.UP
	# Always some lift: a prop smashed by a horizontal swing still throws pieces
	# upward, and a purely flat fan reads as debris being swept rather than knocked
	# loose.
	return (push.normalized() + Vector3.UP * 0.55).normalized()


func _finish() -> void:
	set_process(true)
	_advance(0.0)


func _ready() -> void:
	_live += 1
	_counted = true


func _notification(what: int) -> void:
	# PREDELETE rather than _exit_tree, so a reparent cannot hand the budget back
	# for a burst that is still on screen. Same reasoning as DebrisPiece.
	if what == NOTIFICATION_PREDELETE and _counted:
		_counted = false
		_live = maxi(0, _live - 1)


# --- Shards -------------------------------------------------------------------

## Build the shard fan. `spread` is how far off `aim` the cone opens, as a
## fraction of the whole sphere: 0 is a needle, 1 is a ball.
func _build_shards(row: Dictionary, surface: int, aim: Vector3, spread: float,
		power: float, size_scale: float, trim: int) -> void:
	var want: int = mini(MAX_SHARDS, int(round(float(row["chips"]) * clampf(power, 0.3, 2.0))))
	if want <= 0:
		return
	# A prop with trim gives a bit over a quarter of its pieces to the trim
	# material — a barrel is two hoops and a dozen staves, and that ratio is what
	# makes the hoops read as furniture rather than as a second body.
	var trim_n: int = int(round(float(want) * 0.28)) if trim != TRIM_NONE else 0
	var body_n := want - trim_n

	_sh_bounce = float(row["chip_bounce"])
	var proportions: Vector3 = row["chip"]
	var base: float = float(row["chip_size"]) * size_scale
	var speed: Vector2 = row["chip_speed"]
	var spin: float = float(row["chip_spin"])
	var span: float = float(row["tint_var"])

	_sh_pos.resize(want)
	_sh_vel.resize(want)
	_sh_size.resize(want)
	_sh_axis.resize(want)
	_sh_rate.resize(want)
	_sh_phase.resize(want)
	_sh_life.resize(want)
	var body_tint := PackedColorArray()
	var trim_tint := PackedColorArray()

	for i in want:
		var is_trim := i >= body_n
		var dir := _cone(aim, spread)
		# Size varies by a factor of three across one burst, biased small. A fan of
		# identically sized pieces is the tell that says "particle system"; a real
		# break gives you two big pieces and a dozen small ones.
		var grade: float = _rng.randf()
		grade = grade * grade * 0.72 + 0.28
		var edge: float = base * grade * (0.7 if is_trim else 1.0)
		# Hoop fragments are their own shape whatever the trim material is: long,
		# very thin, and they keep the curve's proportion rather than the body's.
		var shape: Vector3 = proportions if not is_trim else Vector3(2.4, 0.12, 0.34)
		_sh_pos[i] = dir * base * _rng.randf_range(0.4, 1.6)
		# Slower for the bigger pieces: one blow's momentum is shared out by mass,
		# so the chips carrying least go furthest. That is what a break looks like.
		var v: float = _rng.randf_range(speed.x, speed.y) * power / grade
		_sh_vel[i] = dir * v
		_sh_size[i] = Vector3(shape.x * edge, shape.y * edge, shape.z * edge)
		_sh_axis[i] = _unit()
		_sh_rate[i] = _rng.randf_range(-spin, spin)
		_sh_phase[i] = _rng.randf_range(0.0, TAU)
		# Lives vary, so the fan thins out over time instead of vanishing at once.
		_sh_life[i] = life * _rng.randf_range(0.62, 1.0)
		# Per-piece albedo modulation around the material's own colour. The RUBRIC's
		# first material rule applies to a chip that exists for a second as much as
		# to a wall, and a fan in one flat colour is the fastest way to fail it.
		var k: float = 1.0 + _rng.randf_range(-span, span)
		var tint := Color(k, k * (1.0 + _rng.randf_range(-span, span) * 0.4), k, 1.0)
		if is_trim:
			trim_tint.append(tint)
		else:
			body_tint.append(tint)

	_sh_split = body_n
	if body_n > 0:
		_shards = _multimesh("Shards", _shard_geometry(),
			_shard_material(surface, row), body_n, body_tint)
	if trim_n > 0:
		_trim = _multimesh("Trim", _shard_geometry(),
			_shard_material(trim, impact_row(trim)), trim_n, trim_tint)


## Position, rotation and scale of shard `i` at burst age `t`, in local space.
##
## Solved in closed form rather than stepped, so a shard's state is a pure
## function of its age: two runs of the same frame agree exactly, a dropped frame
## cannot move a piece, and there is no per-frame state to get out of step with
## the write into the MultiMesh.
func _shard_xform(i: int, t: float) -> Transform3D:
	var span: float = _sh_life[i]
	var k: float = clampf(t / maxf(0.001, span), 0.0, 1.0)
	var pos: Vector3 = _sh_pos[i] + _sh_vel[i] * t
	pos.y -= 0.5 * SHARD_GRAVITY * t * t

	# One bounce, reflected rather than stepped: below the floor the piece is
	# mirrored back through it and damped, which reads as a skitter and costs two
	# multiplies. A second bounce needs a second solve and is not legible at the
	# speed these live at.
	if pos.y < _floor_y:
		pos.y = _floor_y + (_floor_y - pos.y) * _sh_bounce
	var basis := Basis(_sh_axis[i], _sh_phase[i] + _sh_rate[i] * t)
	# Shrink out over the last quarter, so a piece recedes instead of popping.
	var shrink: float = 1.0
	if k > 1.0 - SHARD_SHRINK:
		shrink = clampf((1.0 - k) / SHARD_SHRINK, 0.0, 1.0)
		shrink = shrink * shrink
	return Transform3D(basis.scaled_local(_sh_size[i] * shrink), pos)


# --- Dust ---------------------------------------------------------------------

## Build the dust cloud. `ring` is the radius the puffs start on: dust does not
## appear at a point, it appears where the impact met the surface.
func _build_dust(row: Dictionary, ring: float, power: float, liquid: Color) -> void:
	var want: int = mini(MAX_DUST, int(round(float(row["dust"]) * clampf(power, 0.3, 2.0))))
	if want <= 0:
		return
	# Droplets come OUT of the dust budget rather than adding to it, so a barrel
	# full of port costs exactly what an empty crate costs.
	var drops: int = int(round(float(want) * 0.34)) if liquid.a > 0.0 else 0

	var tint: Color = row["dust_tint"]
	var rise: float = float(row["dust_rise"])
	var out: float = float(row["dust_out"])
	var span: float = float(row["dust_life"])
	var sizes: Vector2 = row["dust_size"]

	_du_pos.resize(want)
	_du_vel.resize(want)
	_du_size.resize(want)
	_du_life.resize(want)
	_du_tint.resize(want)
	_du_kind.resize(want)

	for i in want:
		var is_drop := i >= want - drops
		var ang: float = _rng.randf_range(0.0, TAU)
		var radial := Vector3(cos(ang), 0.0, sin(ang))
		_du_pos[i] = radial * (ring * _rng.randf_range(0.25, 1.0)) \
			+ Vector3.UP * _rng.randf_range(-0.05, 0.25)
		if is_drop:
			# Port goes UP and comes back down: a splash arcs, it does not billow.
			_du_vel[i] = radial * _rng.randf_range(1.2, 3.4) \
				+ Vector3.UP * _rng.randf_range(2.6, 5.4)
			# Droplets stay small and keep their size all the way down.
			var d: float = _rng.randf_range(0.035, 0.075)
			_du_size[i] = Vector2(d, d)
			_du_life[i] = span * _rng.randf_range(0.80, 1.15)
			var wet: float = _rng.randf_range(0.85, 1.25)
			_du_tint[i] = Color(liquid.r * wet, liquid.g * wet, liquid.b * wet, liquid.a)
			_du_kind[i] = 1
		else:
			_du_vel[i] = radial * out * _rng.randf_range(0.55, 1.35) \
				+ Vector3.UP * rise * _rng.randf_range(0.5, 1.4)
			_du_size[i] = Vector2(sizes.x * _rng.randf_range(0.7, 1.3),
				sizes.y * _rng.randf_range(0.75, 1.35))
			_du_life[i] = span * _rng.randf_range(0.70, 1.15)
			# Dust is never one colour either. The modulation is smaller than the
			# shards' because a cloud reads as a mass, and too much scatter inside
			# one reads as confetti.
			var g: float = _rng.randf_range(0.82, 1.14)
			_du_tint[i] = Color(tint.r * g, tint.g * g, tint.b * g, 1.0)
			_du_kind[i] = 0

	_dust = _multimesh("Dust", dust_mesh(), dust_material(), want, _du_tint)
	# Dust is the alpha half of a burst and the only part that costs overdraw; it
	# must never also cost a shadow-map pass.
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One puff's transform and colour at burst age `t`, in local space.
func _dust_state(i: int, t: float) -> Array:
	var span: float = _du_life[i]
	var k: float = clampf(t / maxf(0.001, span), 0.0, 1.0)
	var pos: Vector3
	var radius: float
	if _du_kind[i] == 1:
		# Ballistic, at a gentler gravity than the shards: liquid hangs.
		pos = _du_pos[i] + _du_vel[i] * t
		pos.y -= 0.5 * (SHARD_GRAVITY * 0.55) * t * t
		radius = _du_size[i].x
	else:
		# Damped drift in closed form. The integral of `v0 * exp(-DUST_DRAG * t)`
		# is what makes a puff shoot out and then hang, which is what dust does; a
		# constant velocity reads as smoke being blown across the deck.
		pos = _du_pos[i] + _du_vel[i] * ((1.0 - exp(-DUST_DRAG * t)) / DUST_DRAG)
		# Ease-out growth: the cloud opens fast and then settles into its size.
		radius = lerpf(_du_size[i].x, _du_size[i].y, 1.0 - pow(1.0 - k, 2.2))
	var tint: Color = _du_tint[i]
	# Fade in over the first eighth so a puff does not arrive at full opacity, then
	# out over the whole tail.
	var alpha: float = clampf(k / 0.12, 0.0, 1.0) * pow(1.0 - k, 1.6)
	return [Transform3D(Basis().scaled(Vector3.ONE * radius), pos),
		Color(tint.r, tint.g, tint.b, alpha)]


# --- Ring and flash -----------------------------------------------------------

func _build_ring(row: Dictionary, radius: float) -> void:
	_ring_radius = maxf(0.2, radius)
	_ring_alpha = float(row["ring_alpha"])
	_ring_mat = _decal_material(row["ring_tint"], _ring_alpha)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = ring_mesh()
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = RING_LIFT
	add_child(_ring)


func _build_flash(row: Dictionary, power: float) -> void:
	var tint: Color = row["flash_tint"]
	_flash_radius = 0.28 * clampf(power, 0.4, 2.2)
	_flash_mat = _decal_material(tint, 0.9)
	_flash_mat.emission = tint
	_flash_mat.emission_energy_multiplier = float(row["flash_energy"])
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.mesh = _flash_geometry()
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)


## Unshaded, double-sided, self-lit: the ring and the flash are light rather than
## matter, and they have to read against a bright saturated daylight frame from a
## grazing deck-level camera as well as from above. Built per burst rather than
## cached, because both animate their own alpha — ARCHITECTURE.md rule 7.
func _decal_material(colour: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 1.4
	mat.disable_receive_shadows = true
	return mat


# --- Frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	_advance(_t)


func _advance(t: float) -> void:
	_write_shards(_shards, 0, _sh_split, t)
	_write_shards(_trim, _sh_split, _sh_pos.size(), t)
	_write_dust(t)
	_write_ring(t)
	_write_flash(t)


func _write_shards(target: MultiMeshInstance3D, from: int, to: int, t: float) -> void:
	if target == null:
		return
	var mm := target.multimesh
	for i in range(from, to):
		mm.set_instance_transform(i - from, _shard_xform(i, t))


func _write_dust(t: float) -> void:
	if _dust == null:
		return
	var mm := _dust.multimesh
	for i in _du_pos.size():
		var s := _dust_state(i, t)
		mm.set_instance_transform(i, s[0])
		mm.set_instance_color(i, s[1])


func _write_ring(t: float) -> void:
	if _ring == null:
		return
	var k: float = clampf(t / RING_LIFE, 0.0, 1.0)
	if k >= 1.0:
		# Freed rather than left at zero alpha: an invisible mesh still costs a
		# draw call and a culling test for the rest of the burst.
		_ring.queue_free()
		_ring = null
		return
	# Ease-out cubic: the ring leaves fast and decelerates, which is how a pressure
	# front actually behaves and what makes the frame feel struck.
	var grown: float = 1.0 - pow(1.0 - k, 3.0)
	var r: float = _ring_radius * maxf(0.04, grown)
	# The lip flattens as the ring opens, so the wave lies down as it spends itself.
	_ring.scale = Vector3(r, 1.0 + grown * 0.6, r)
	_ring_mat.albedo_color.a = lerpf(_ring_alpha, 0.0, k * k)
	_ring_mat.emission_energy_multiplier = lerpf(2.6, 0.0, k)


func _write_flash(t: float) -> void:
	if _flash == null:
		return
	var k: float = clampf(t / FLASH_LIFE, 0.0, 1.0)
	if k >= 1.0:
		_flash.queue_free()
		_flash = null
		return
	# Arrives already big and collapses. A flash that grows reads as a light being
	# switched on; a flash that shrinks reads as something being struck.
	var s: float = _flash_radius * lerpf(1.35, 0.15, k * k)
	_flash.scale = Vector3(s, s, s)
	_flash_mat.albedo_color.a = 0.9 * (1.0 - k)


# --- Shared geometry and materials --------------------------------------------

## The ground ring, baked ONCE for the whole process and scaled per burst. A
## shallow cone: an annulus whose inner edge stands `RING_LIP` proud, so the key
## light catches one side of it and it is a wave front rather than a decal.
##
## Wound to `MeshBaker`'s contract — the right-hand cross product of a quad's
## vertex order points the way the surface faces. Walking the ring with theta
## INCREASING and going inner -> outer puts RH at +Y on the flat band and
## up-and-outward on the sloped one, which is what a ground ring needs from above
## and from a deck-level camera alike. Verified against the emitter: a quad
## (0,0,0) (0,0,1) (1,0,1) (1,0,0) commits a stored normal of +Y.
##
## Public because `shockwave.gd` scales this same annulus out to fifteen metres,
## and two copies of one winding rule is exactly how the two would drift apart.
static func ring_mesh() -> Mesh:
	if _ring_mesh != null:
		return _ring_mesh
	var b := MeshBaker.new()
	var inner: float = 1.0 - RING_WALL
	for i in RING_SEGMENTS:
		var t0: float = TAU * float(i) / float(RING_SEGMENTS)
		var t1: float = TAU * float(i + 1) / float(RING_SEGMENTS)
		var i0 := Vector3(cos(t0) * inner, RING_LIP, sin(t0) * inner)
		var i1 := Vector3(cos(t1) * inner, RING_LIP, sin(t1) * inner)
		var o0 := Vector3(cos(t0), 0.0, sin(t0))
		var o1 := Vector3(cos(t1), 0.0, sin(t1))
		b.add_quad(i0, i1, o1, o0, Vector2(TAU / float(RING_SEGMENTS), RING_WALL))
	# No LODs: it is 160 triangles and it is always within a few metres of the
	# camera, so generating them is pure load-time cost for nothing.
	var mi := b.commit(null, "RingMesh", false)
	_ring_mesh = mi.mesh
	mi.queue_free()
	return _ring_mesh


static func _shard_geometry() -> Mesh:
	if _shard_mesh == null:
		var m := BoxMesh.new()
		# A unit box, scaled non-uniformly per instance. One mesh serves splinters,
		# flakes, setts and slivers alike, which is what keeps a whole fan on one
		# draw call.
		m.size = Vector3.ONE
		_shard_mesh = m
	return _shard_mesh


## The dust puff. Public because `shockwave.gd` builds its own rim wall out of
## the same mesh and the same material — a wave's dust and a crater's dust are
## the same substance and must not be two different-looking things.
static func dust_mesh() -> Mesh:
	if _dust_mesh == null:
		var m := SphereMesh.new()
		# Chunky on purpose. N. Sane's dust is puffballs, not soft sprites, and a
		# lit low-poly sphere takes the key light and the sky fill the way the
		# RUBRIC asks — an unshaded billboard would be the flatter, cheaper and
		# more amateur read, and 42 triangles a puff is nothing.
		m.radial_segments = 7
		m.rings = 4
		m.radius = 1.0
		m.height = 2.0
		_dust_mesh = m
	return _dust_mesh


static func _flash_geometry() -> Mesh:
	if _flash_mesh == null:
		var m := SphereMesh.new()
		m.radial_segments = 8
		m.rings = 5
		m.radius = 1.0
		m.height = 2.0
		_flash_mesh = m
	return _flash_mesh


## One shard material per surface, process-wide.
##
## Taken from ToonFactory's named helpers so a granite chip wears the SAME detail
## normal, roughness mask and surface albedo map the kerb it came off does — but
## at `CHIP_TILE` rather than the helper's own tile, because granite authored at
## 2.4 m across a 10 cm chip is one flat colour, which is the RUBRIC's first
## material failure. Then `.duplicate()`, per ARCHITECTURE.md rule 7, because we
## switch vertex colours on and a shared cached material would recolour every
## other surface in the scene built from the same parameter set.
static func _shard_material(surface: int, row: Dictionary) -> StandardMaterial3D:
	if _shard_mats.has(surface):
		return _shard_mats[surface]
	var base: StandardMaterial3D
	match surface:
		ToonFactory.Surface.GRANITE:
			base = ToonFactory.stone(ToonFactory.STONE_GREY, CHIP_TILE)
		ToonFactory.Surface.COBBLE:
			base = ToonFactory.cobblestone(ToonFactory.COBBLE_GREY, CHIP_TILE)
		ToonFactory.Surface.IRON:
			base = ToonFactory.iron(ToonFactory.IRON_GREY, CHIP_TILE)
		ToonFactory.Surface.PLASTER:
			base = ToonFactory.plaster(ToonFactory.PLASTER_CREAM, CHIP_TILE)
		ToonFactory.Surface.TERRACOTTA:
			base = ToonFactory.terracotta(ToonFactory.TERRACOTTA_RED, CHIP_TILE)
		ToonFactory.Surface.WOOD:
			base = ToonFactory.wood(ToonFactory.WOOD_BROWN, CHIP_TILE)
		_:
			base = ToonFactory.solid(Color(0.62, 0.60, 0.57), 0.0, 0.85)
	var mat: StandardMaterial3D = base.duplicate()
	# Per-instance albedo variation. The MultiMesh's instance colour MULTIPLIES
	# albedo_color, so ToonFactory's physically-corrected colour still decides what
	# the chip is made of and the instance colour only modulates it.
	mat.vertex_color_use_as_albedo = true
	var glow: float = float(row.get("chip_glow", 0.0))
	if glow > 0.0:
		# Struck steel throws hot metal. This is what makes an iron impact read as
		# sparks without a second emitter, a second material or a second draw call.
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.55, 0.16)
		mat.emission_energy_multiplier = glow
	_shard_mats[surface] = mat
	return mat


## One dust material for the whole process. Every puff's colour AND its opacity
## ride the MultiMesh instance colour, so seven surfaces' worth of dust — and
## the shockwave's rim wall, which shares it — collapse onto one material.
static func dust_material() -> StandardMaterial3D:
	if _dust_mat != null:
		return _dust_mat
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Godot cannot depth-sort instances WITHIN one MultiMesh, so puffs would punch
	# holes in each other. Disabling depth WRITE (not the test) is the standard
	# answer and it is what lets a cloud blend into itself.
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	# Fully rough with a strong tinted rim, which is what stops a lit sphere
	# reading as a ball bearing and makes the edge of a puff glow against the sky.
	m.roughness = 1.0
	m.metallic = 0.0
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.9
	m.disable_receive_shadows = true
	_dust_mat = m
	return _dust_mat


func _multimesh(node_name: String, mesh: Mesh, material: Material, count: int,
		colours: PackedColorArray) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	# Order matters: mesh, then format, then colours, then the count. Setting
	# use_colors AFTER instance_count reallocates the buffer and throws away every
	# transform already written into it.
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = count
	for i in mini(count, colours.size()):
		mm.set_instance_color(i, colours[i])
	# An explicit AABB, in the burst's local space, because Godot derives a
	# MultiMesh's bounds from its instance buffer and ours move every frame. A
	# stale bound is a burst that vanishes the instant the camera turns slightly
	# away from where it started — a bug that only ever shows up in a capture.
	var reach: float = maxf(6.0, _ring_radius * 1.6)
	mm.custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
	return mmi


# --- Random helpers -----------------------------------------------------------

## A unit vector inside a cone around `aim`, with `spread` running 0 (a needle
## along the axis) to 1 (the whole sphere). Uniform on the spherical cap rather
## than uniform in angle, so a wide fan does not bunch up on its own axis.
func _cone(aim: Vector3, spread: float) -> Vector3:
	var axis := aim.normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.UP
	var cos_max: float = 1.0 - 2.0 * clampf(spread, 0.0, 1.0)
	var c: float = _rng.randf_range(cos_max, 1.0)
	var s: float = sqrt(maxf(0.0, 1.0 - c * c))
	var phi: float = _rng.randf_range(0.0, TAU)
	# Any stable basis perpendicular to the axis; UP unless the axis is near it.
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := axis.cross(up).normalized()
	var fwd := right.cross(axis).normalized()
	var v := axis * c + right * (s * cos(phi)) + fwd * (s * sin(phi))
	return v.normalized() if v.length() > 0.001 else axis


func _unit() -> Vector3:
	var v := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0))
	if v.length() < 0.01:
		return Vector3.UP
	return v.normalized()
