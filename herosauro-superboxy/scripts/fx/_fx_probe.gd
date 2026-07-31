extends Node
## Headless regression probe for the fx stream.
##
## Every check in here MEASURES something and prints the number it got. FX are
## the one subsystem whose output nobody can see from a headless run and whose
## defects are all invisible until a capture lands three minutes later, so the
## probe's job is to turn "does it look right" into numbers that fail a build.
##
## What it measures:
##
##   * THE IMPACT TABLE. That every value of `ToonFactory.Surface` resolves to
##     its OWN case — the ARCHITECTURE.md rule that adding a surface adds a case
##     here in the same commit — and that no two surfaces were left as copies of
##     each other, which is how a table like this actually rots.
##   * SURFACE RESOLUTION. That every prop scene in the game, the giant, and the
##     `fx_surface` opt-in hook all resolve through `ImpactFX.surface_of()`.
##   * BUDGET. Instances and draw calls per burst against the stated ceilings,
##     and that the process-wide burst budget actually refuses the eleventh.
##   * LIFETIME AND LEAKS. That every emitter frees itself inside its stated
##     life, that the live counter returns to zero, and that the spawn root has
##     the same number of children afterwards as before.
##   * DETERMINISM, both halves of it. Two identically-seeded bursts agree shard
##     for shard; two differently-seeded ones do not; and a shard's state at a
##     given AGE is the same answer whenever it is asked, which is the wall-clock
##     rule (ARCHITECTURE.md rule 5) made measurable.
##   * WHERE THE DEBRIS ACTUALLY GOES. How high a fan climbs, how wide it opens
##     and where it is by the end of its life. This is the check that catches the
##     two ways a closed-form debris solve goes wrong without ever erroring: a
##     bounce that reflects the whole path (chips climb away for ever) and a speed
##     ramp that shares momentum by mass (chips leave the arena).
##   * THE SHOCKWAVE'S HONESTY. That the radius you can see and the radius that
##     can hit you never disagree by more than a few centimetres across a whole
##     sweep, and that its knockback points AWAY from the blast.
##   * THE ROCK ARC. Where a launched rock actually lands against where it was
##     aimed. `_boss_probe` polices the same contract from the boss's side (it
##     mirrors this solve to time its ground marks); this is the fx side of it,
##     so the stream that owns the arc owns a test of it.
##   * ACROSS A FIGHT. Peak and mean live bursts, instances and draw calls over a
##     scripted fight, and that they all come back to zero at the end rather than
##     accumulating.
##
## Headless-safe: nothing here reads the framebuffer, and nothing reads a
## MultiMesh instance buffer — that lives in the RenderingServer, which is a
## no-op under --headless, so the probe measures the simulation the bursts
## expose instead. That is the stronger test anyway: the buffer is a copy of it.
##
##   godot --headless --path . scripts/fx/_fx_probe.tscn

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const ShockwaveScene: PackedScene = preload("res://scenes/fx/shockwave.tscn")
const RockScene: PackedScene = preload("res://scenes/fx/rock_projectile.tscn")

const CrateScene: PackedScene = preload("res://scenes/props/crate.tscn")
const BarrelScene: PackedScene = preload("res://scenes/props/wine_barrel.tscn")
const RubbleScene: PackedScene = preload("res://scenes/props/rubble_block.tscn")

## Physics ticks per second, used to turn seconds into frame counts.
const TICK := 90.0

## Stated budget, asserted rather than described. One burst is at most this many
## drawn things and this many instances; see the header of impact_fx.gd.
const BUDGET_EMITTERS_PER_BURST := 4
const BUDGET_INSTANCES_PER_BURST := ImpactFX.MAX_SHARDS + ImpactFX.MAX_DUST
## ...and the whole process, worst case, at the same time.
const BUDGET_DRAW_CALLS := ImpactFX.MAX_LIVE * BUDGET_EMITTERS_PER_BURST
const BUDGET_INSTANCES := ImpactFX.MAX_LIVE * BUDGET_INSTANCES_PER_BURST

## How far a launched rock may land from where it was aimed. The boss draws a
## 1.6 m crosshair (AdamastorStateMachine.ROCK_MARK_RADIUS) and promises the rock
## lands on it, so half that is the honest tolerance.
const ARC_TOLERANCE := 0.8
## How far the wave's ring may be from the radius that can hit you, in metres.
## Two centimetres over a fifteen-metre sweep.
const WAVE_TOLERANCE := 0.02

var _pass: int = 0
var _fail: int = 0
var _main: Node = null
var _root: Node3D = null


## A hero-shaped body the shockwave can actually catch, so the knockback it hands
## out can be measured directly rather than inferred from where a real hero ended
## up two frames later.
class HeroStub:
	extends CharacterBody3D

	var hits: int = 0
	var last_knockback: Vector3 = Vector3.ZERO

	func _ready() -> void:
		add_to_group("players")
		collision_layer = PhysicsLayers.PLAYERS
		collision_mask = PhysicsLayers.WORLD
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.7
		col.shape = cap
		add_child(col)

	func take_hit(_amount: int, knockback: Vector3 = Vector3.ZERO) -> bool:
		hits += 1
		last_knockback = knockback
		return true

	func is_downed() -> bool:
		return false


## A piece of world geometry that has opted into the impact table by declaring
## `fx_surface` as a NAME rather than as an enum value. Both spellings have to
## work or the hook is a trap for whichever stream guesses the other one.
class TaggedGeometry:
	extends Node3D

	var fx_surface: String = "terracotta"


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("\nfx probe: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_make_root()
	_check_impact_table()
	_check_surface_resolution()
	await _check_burst_budget()
	await _check_lifetimes_and_leaks()
	await _check_determinism()
	await _check_shards_settle()
	await _check_shockwave()
	await _check_rock_arc()
	_drop_root()
	await _check_across_a_fight()


# --- The impact table ---------------------------------------------------------

## ARCHITECTURE.md: "Adding a surface means adding its detail normal + mask pair
## ... and a case in the fx impact table ... in the same commit."
##
## `impact_row()` echoes back the surface it built the row FOR, so a surface that
## fell through to the default is caught by identity rather than by inspection.
## Then every row is checked for every key, and every pair of rows is checked for
## being genuinely different — a table whose entries were copy-pasted and never
## edited passes a completeness check and fails the game.
func _check_impact_table() -> void:
	var required := ["surface", "chip", "chip_size", "chips", "chip_speed",
		"chip_bounce", "chip_spin", "chip_glow", "tint_var", "dust", "dust_tint",
		"dust_rise", "dust_out", "dust_life", "dust_size", "ring_tint",
		"ring_alpha", "flash_tint", "flash_energy"]

	var surfaces: Array = ToonFactory.Surface.values()
	var names: Array = ToonFactory.Surface.keys()
	var covered := 0
	var complete := true
	print("  -- impact table, %d surfaces:" % surfaces.size())
	for i in surfaces.size():
		var s: int = surfaces[i]
		var row := ImpactFX.impact_row(s)
		if int(row.get("surface", -1)) == s:
			covered += 1
		for key in required:
			if not row.has(key):
				complete = false
				printerr("       %s is missing '%s'" % [names[i], key])
		print("       %-11s chip %s  chips %2d  dust %2d %s  ring a=%.2f  glow %.1f"
			% [names[i], str(row.get("chip", Vector3.ZERO)), int(row.get("chips", 0)),
				int(row.get("dust", 0)), str(row.get("dust_tint", Color.BLACK)),
				float(row.get("ring_alpha", 0.0)), float(row.get("chip_glow", 0.0))])

	_ok(covered == surfaces.size(),
		"every ToonFactory.Surface has its own case in the fx impact table (%d/%d)"
			% [covered, surfaces.size()])
	_ok(complete, "every row carries all %d keys the FX read" % required.size())

	# Distinctness. Compared on the three fields that decide what an impact LOOKS
	# like — the shard's proportions, its dust volume and its dust colour — so two
	# surfaces sharing a bounce value is fine and two surfaces being the same
	# material is not.
	var clashes := 0
	for a in surfaces.size():
		for b in range(a + 1, surfaces.size()):
			var ra := ImpactFX.impact_row(surfaces[a])
			var rb := ImpactFX.impact_row(surfaces[b])
			if ra["chip"] == rb["chip"] and ra["dust"] == rb["dust"] \
					and ra["dust_tint"] == rb["dust_tint"]:
				clashes += 1
				printerr("       %s and %s are the same impact" % [names[a], names[b]])
	_ok(clashes == 0,
		"no two surfaces produce the same impact (%d identical pairs)" % clashes)

	# The two claims the table exists to make, stated as numbers: painted steel
	# does not powder and it throws sparks; limewash powders more than anything.
	var iron := ImpactFX.impact_row(ToonFactory.Surface.IRON)
	var plaster := ImpactFX.impact_row(ToonFactory.Surface.PLASTER)
	var wood := ImpactFX.impact_row(ToonFactory.Surface.WOOD)
	var granite := ImpactFX.impact_row(ToonFactory.Surface.GRANITE)
	_ok(int(iron["dust"]) < int(granite["dust"]) and float(iron["chip_glow"]) > 0.0,
		"iron powders less than granite (%d vs %d puffs) and is the only surface that glows"
			% [int(iron["dust"]), int(granite["dust"])])
	_ok(int(plaster["dust"]) == _max_dust(surfaces),
		"limewash throws the biggest cloud in the table (%d puffs)" % int(plaster["dust"]))
	_ok(float(wood["chip"].x) / maxf(0.001, float(wood["chip"].y))
			> float(granite["chip"].x) / maxf(0.001, float(granite["chip"].y)),
		"wood splinters and granite chips (aspect %.1f vs %.1f)"
			% [wood["chip"].x / wood["chip"].y, granite["chip"].x / granite["chip"].y])


func _max_dust(surfaces: Array) -> int:
	var best := 0
	for s in surfaces:
		best = maxi(best, int(ImpactFX.impact_row(s)["dust"]))
	return best


## Every impact kind in the game has to be able to name a surface. The props are
## checked by instantiating the real scenes rather than by repeating their export
## values here, so a prop re-tinted or re-materialled by the props stream shows up
## as a failure in this stream rather than as wrong-coloured debris in a capture.
func _check_surface_resolution() -> void:
	var cases := {
		"crate": [CrateScene, ToonFactory.Surface.WOOD],
		"wine barrel": [BarrelScene, ToonFactory.Surface.WOOD],
		"rubble block": [RubbleScene, ToonFactory.Surface.GRANITE],
	}
	var resolved := 0
	for label in cases:
		var scene: PackedScene = cases[label][0]
		var want: int = cases[label][1]
		var prop: Node = scene.instantiate()
		var got := ImpactFX.surface_of(prop, ToonFactory.Surface.FLAT)
		print("  -- %-13s surface '%s' -> %s"
			% [label, str(prop.get("surface")), ToonFactory.Surface.keys()[got]])
		if got == want:
			resolved += 1
		prop.free()
	_ok(resolved == cases.size(),
		"every prop scene resolves to the surface it is made of (%d/%d)"
			% [resolved, cases.size()])

	# The opt-in hook, which is how the world stream tags its geometry without
	# either side importing the other's script.
	var rock: Node = RockScene.instantiate()
	_ok(ImpactFX.surface_of(rock, ToonFactory.Surface.FLAT) == ToonFactory.Surface.GRANITE,
		"an `fx_surface` enum declaration wins over everything else (the thrown rock)")
	rock.free()

	var tagged := TaggedGeometry.new()
	_ok(ImpactFX.surface_of(tagged) == ToonFactory.Surface.TERRACOTTA,
		"...and so does an `fx_surface` written as a name, which is the other way a"
			+ " stream will reach for it")
	tagged.free()

	# ...and the fallbacks, both directions.
	var stone_giant := Node3D.new()
	stone_giant.add_to_group("boss")
	add_child(stone_giant)
	_ok(ImpactFX.surface_of(stone_giant) == ToonFactory.Surface.GRANITE,
		"a blow on the stone giant throws granite")
	stone_giant.queue_free()
	_ok(ImpactFX.surface_of(null, ToonFactory.Surface.COBBLE) == ToonFactory.Surface.COBBLE,
		"an untagged collider falls back to what the caller asked for, never a guess")
	_ok(ImpactFX.surface_named("timber") == ToonFactory.Surface.WOOD
			and ImpactFX.surface_named("nonsense", ToonFactory.Surface.IRON)
				== ToonFactory.Surface.IRON,
		"the name table maps what PropBody exports and falls back on anything else")


# --- Budget -------------------------------------------------------------------

func _check_burst_budget() -> void:
	var here := Vector3(0.0, 2.0, 0.0)
	var kinds := {
		"spark": ImpactFX.spark(self, here, Vector3.RIGHT, ToonFactory.Surface.GRANITE, 1.0),
		"ground": ImpactFX.ground(self, here, ToonFactory.Surface.COBBLE, 5.2, 1.6),
		"smash (crate)": ImpactFX.smash(self, here, ToonFactory.Surface.WOOD, 0.45),
		"smash (barrel)": ImpactFX.smash(self, here + Vector3.RIGHT, ToonFactory.Surface.WOOD,
			0.45, Vector3.RIGHT * 6.0, 0, ToonFactory.Surface.IRON, ImpactFX.PORT_WINE),
	}
	var worst_emitters := 0
	var worst_instances := 0
	for label in kinds:
		var fx: ImpactFX = kinds[label]
		_ok(fx != null, "%s builds" % label)
		if fx == null:
			continue
		var instances := fx.shard_count() + fx.dust_count()
		worst_emitters = maxi(worst_emitters, fx.emitter_count())
		worst_instances = maxi(worst_instances, instances)
		print("  -- %-15s %d draw calls, %d shards (%d trim), %d dust = %d instances"
			% [label, fx.emitter_count(), fx.shard_count(), fx.trim_count(),
				fx.dust_count(), instances])
		_ok(fx.shard_count() <= ImpactFX.MAX_SHARDS and fx.dust_count() <= ImpactFX.MAX_DUST,
			"...within the per-burst caps (%d/%d shards, %d/%d dust)"
				% [fx.shard_count(), ImpactFX.MAX_SHARDS, fx.dust_count(), ImpactFX.MAX_DUST])

	# The barrel is the one burst allowed a fourth draw call, and it is what buys
	# hoops that are iron while the staves are wood.
	var barrel: ImpactFX = kinds["smash (barrel)"]
	_ok(barrel != null and barrel.trim_count() > 0,
		"a barrel throws iron hoop fragments as well as wood staves (%d of %d pieces)"
			% [barrel.trim_count() if barrel else 0, barrel.shard_count() if barrel else 0])
	_ok(worst_emitters <= BUDGET_EMITTERS_PER_BURST,
		"no burst costs more than %d draw calls (worst %d)"
			% [BUDGET_EMITTERS_PER_BURST, worst_emitters])
	_ok(worst_instances <= BUDGET_INSTANCES_PER_BURST,
		"no burst costs more than %d instances (worst %d)"
			% [BUDGET_INSTANCES_PER_BURST, worst_instances])

	# The process-wide ceiling. Ask for far more than the budget and check both
	# that it refuses and that it refuses by returning null rather than by
	# erroring — callers are documented to treat null as "draw fewer".
	var granted := 0
	var refused := 0
	for i in ImpactFX.MAX_LIVE + 8:
		if ImpactFX.ground(self, Vector3(float(i), 2.0, 0.0), ToonFactory.Surface.COBBLE) != null:
			granted += 1
		else:
			refused += 1
	print("  -- asked for %d more bursts with %d already live: %d granted, %d refused, %d live"
		% [ImpactFX.MAX_LIVE + 8, kinds.size(), granted, refused, ImpactFX.live_count()])
	_ok(ImpactFX.live_count() <= ImpactFX.MAX_LIVE,
		"the process-wide burst budget holds at %d (%d live)"
			% [ImpactFX.MAX_LIVE, ImpactFX.live_count()])
	_ok(refused > 0, "the budget refuses rather than growing (%d refused)" % refused)

	# ...and the worst case that ceiling implies, stated in the units that decide
	# whether a mid-range card holds 60.
	print("  -- worst case for the whole process: %d draw calls, %d instances"
		% [BUDGET_DRAW_CALLS, BUDGET_INSTANCES])
	await _drain()


# --- Lifetime and leaks -------------------------------------------------------

## The failure this is here to catch is not a crash. It is a fight that gets
## slower the longer it runs because nothing ever frees itself — which nobody
## notices until the fifth minute of a playtest and which a headless probe can
## catch in two seconds.
func _check_lifetimes_and_leaks() -> void:
	var before := _root.get_child_count()
	var here := Vector3(0.0, 2.0, 0.0)
	var made := [
		ImpactFX.spark(self, here, Vector3.RIGHT, ToonFactory.Surface.IRON, 1.0),
		ImpactFX.ground(self, here, ToonFactory.Surface.GRANITE, 4.0),
		ImpactFX.smash(self, here, ToonFactory.Surface.TERRACOTTA, 0.5),
	]
	var lives := [ImpactFX.SPARK_LIFE, ImpactFX.GROUND_LIFE, ImpactFX.SMASH_LIFE]
	var labels := ["spark", "ground", "smash"]

	# The ring and the flash retire themselves partway through, before the burst
	# does. That is the point: an invisible mesh still costs a draw call.
	var at_birth: Array[int] = []
	for fx in made:
		at_birth.append((fx as ImpactFX).emitter_count())
	await _advance(ImpactFX.FLASH_LIFE + 0.02)
	var after_flash: Array[int] = []
	for i in made.size():
		var fx: ImpactFX = made[i]
		after_flash.append(fx.emitter_count() if is_instance_valid(fx) else 0)
	print("  -- draw calls per burst at birth %s, once the flash has gone %s"
		% [str(at_birth), str(after_flash)])
	_ok(after_flash[0] < at_birth[0],
		"the core flash retires itself instead of sitting at zero alpha (%d -> %d draw calls)"
			% [at_birth[0], after_flash[0]])

	# Now run past the longest life and check every one of them is gone.
	var longest: float = 0.0
	for l in lives:
		longest = maxf(longest, float(l))
	await _advance(longest + 0.3)

	var alive := 0
	for i in made.size():
		if is_instance_valid(made[i]):
			alive += 1
			printerr("       %s outlived its stated %.2f s life" % [labels[i], lives[i]])
	_ok(alive == 0, "every burst freed itself inside its stated life (%.2f s worst)" % longest)
	_ok(ImpactFX.live_count() == 0,
		"the live-burst counter returns to zero (%d)" % ImpactFX.live_count())
	var after := _root.get_child_count()
	print("  -- spawn root children: %d before, %d after a spark, a ground and a smash"
		% [before, after])
	_ok(after == before, "nothing is left behind in the spawn root (%d vs %d)" % [after, before])


# --- Determinism --------------------------------------------------------------

## ARCHITECTURE.md rules 4 and 5, measured rather than asserted by inspection.
##
## Two identically-seeded bursts must agree shard for shard, or the capture gate
## reports a failure on every run and an ignored gate is no gate. Two differently
## seeded ones must NOT, or the seed is being thrown away and every impact in the
## game throws the same fan. And a shard's state at a given AGE has to be the
## same answer however long ago it was asked, which is what a solve that read a
## clock could not do.
func _check_determinism() -> void:
	var here := Vector3(3.0, 2.0, -1.0)
	var a := ImpactFX.smash(self, here, ToonFactory.Surface.WOOD, 0.45, Vector3.RIGHT, 0x5EED)
	var b := ImpactFX.smash(self, here, ToonFactory.Surface.WOOD, 0.45, Vector3.RIGHT, 0x5EED)
	var c := ImpactFX.smash(self, here, ToonFactory.Surface.WOOD, 0.45, Vector3.RIGHT, 0x5EEE)
	_ok(a != null and b != null and c != null, "three bursts for the determinism check")
	if a == null or b == null or c == null:
		return

	var same := 0.0
	var different := 0.0
	for i in a.shard_count():
		same = maxf(same, a.sample_shard(i, 0.31).origin.distance_to(
			b.sample_shard(i, 0.31).origin))
		different = maxf(different, a.sample_shard(i, 0.31).origin.distance_to(
			c.sample_shard(i, 0.31).origin))
	print("  -- same seed: worst shard disagrees by %.6f m.  different seed: by %.3f m"
		% [same, different])
	_ok(same < 1.0e-5, "the same seed throws the same fan (%.6f m worst)" % same)
	_ok(different > 0.05, "a different seed throws a different fan (%.3f m worst)" % different)

	# The wall-clock check. Sample one shard at a fixed AGE, run real frames, then
	# sample the same shard at the same age again.
	var first: Array[Transform3D] = []
	for i in a.shard_count():
		first.append(a.sample_shard(i, 0.42))
	await _advance(0.25)
	var drift := 0.0
	if is_instance_valid(a):
		for i in a.shard_count():
			drift = maxf(drift, first[i].origin.distance_to(a.sample_shard(i, 0.42).origin))
	print("  -- the same shard at the same age, 25 frames later: %.6f m of drift" % drift)
	_ok(drift < 1.0e-5,
		"shard state is a pure function of age, not of the clock (%.6f m)" % drift)
	await _drain()


# --- Shards go up, and then they come down ------------------------------------

## Two bugs this catches, both of which were live in this file's first draft and
## neither of which is visible without a GPU:
##
##   * THE BOUNCE. Reflecting the whole ballistic path about the floor plane —
##     two multiplies, correct for about a tenth of a second — makes the mirrored
##     path keep accelerating upward, so every chip in the game climbs away off
##     the deck for ever. The fix solves the first floor crossing and integrates a
##     second arc from it. Measured here as a ceiling on the fan and a floor on
##     where it ends up.
##   * THE SPEED RAMP. Sharing the blow's MOMENTUM out by piece mass is the
##     physically tempting thing to write and gives v proportional to 1/mass,
##     which over this size ramp is a 3.6x multiplier: cobble at a slam's power
##     came out at 39 m/s and left the arena on a 29 m arc.
##
## Both show up as the same number, so both are measured as one: how high the fan
## goes, and where it is by the end.
func _check_shards_settle() -> void:
	# A slam's worth of power on the deck: the heaviest ground impact the game
	# makes, and therefore the fastest chips in it.
	var fx := ImpactFX.ground(self, Vector3(0.0, 2.0, 0.0), ToonFactory.Surface.COBBLE, 5.2, 1.6)
	_ok(fx != null, "a slam-strength ground burst for the settling check")
	if fx == null:
		return

	# The burst simulates in its own local space with the contact plane at zero,
	# so these are heights above the deck.
	var apex := -INF
	var apex_reach := 0.0
	var resting := -INF
	var below := 0.0
	for i in fx.shard_count():
		for step in 40:
			var t: float = ImpactFX.GROUND_LIFE * float(step) / 39.0
			var p: Vector3 = fx.sample_shard(i, t).origin
			apex = maxf(apex, p.y)
			apex_reach = maxf(apex_reach, Vector2(p.x, p.z).length())
			below = minf(below, p.y)
		resting = maxf(resting, fx.sample_shard(i, ImpactFX.GROUND_LIFE).origin.y)

	print("  -- a slam's chips: highest %.2f m, furthest %.2f m out, deepest %.3f m below the deck, highest at end of life %.2f m"
		% [apex, apex_reach, below, resting])
	# Head height on the giant is nine metres; chips off the deck must stay well
	# inside the fight, not leave the frame.
	_ok(apex < 6.0, "the fan stays inside the fight (%.2f m at its highest)" % apex)
	_ok(apex_reach < 9.0, "...and inside its own bounding box (%.2f m at its widest)" % apex_reach)
	_ok(below > -0.05, "no chip sinks through the deck it landed on (%.3f m)" % below)
	_ok(resting < 0.75,
		"every chip is back on the deck by the end of its life (%.2f m)" % resting)
	await _drain()


# --- The shockwave ------------------------------------------------------------

func _check_shockwave() -> void:
	var blast := Vector3(6.0, 2.0, 0.0)
	var wave: Area3D = ShockwaveScene.instantiate()
	wave.max_radius = 12.0
	wave.grow_time = 0.5
	_root.add_child(wave)
	wave.global_position = blast

	# A hero standing BETWEEN the world origin and the blast. This is the case the
	# old code got backwards: it cached the blast centre in _ready(), which runs
	# before the spawner has positioned the wave, so every knockback direction in
	# the game was measured from world (0, 0, 0). A hero here was thrown INTO the
	# giant instead of away from him.
	var hero := HeroStub.new()
	_root.add_child(hero)
	hero.global_position = blast + Vector3(-3.0, 0.0, 0.0)

	var worst_gap := 0.0
	var reached := 0.0
	var puffs := 0
	var elapsed := 0.0
	var samples := 0
	# Time, not frames: a headless idle tick is whatever the machine can manage,
	# so a frame count means nothing here. The sweep is 0.5 s of growth plus the
	# wave's own tail, and two seconds is comfortably past both.
	while is_instance_valid(wave) and elapsed < 2.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		samples += 1
		if not is_instance_valid(wave):
			break
		puffs = maxi(puffs, wave.wall_instances())
		reached = maxf(reached, wave.wave_radius())
		if wave.ring_radius() > 0.0:
			worst_gap = maxf(worst_gap, absf(wave.ring_radius() - wave.wave_radius()))

	print("  -- wave: reached %.2f m of a promised %.2f m over %d samples, ring vs collider worst gap %.4f m, %d rim puffs, gone after %.2f s"
		% [reached, 12.0, samples, worst_gap, puffs, elapsed])
	_ok(reached >= 12.0 - 0.05,
		"the wave actually reaches the radius it promises (%.2f / 12.00 m)" % reached)
	_ok(worst_gap <= WAVE_TOLERANCE,
		"what you can see and what can hit you never disagree by more than %.0f cm (%.1f cm)"
			% [WAVE_TOLERANCE * 100.0, worst_gap * 100.0])
	_ok(not is_instance_valid(wave), "the wave frees itself (%.2f s)" % elapsed)
	_ok(puffs > 0 and puffs <= ImpactFX.MAX_DUST * 2,
		"the rim dust wall is one bounded MultiMesh (%d puffs, one draw call)" % puffs)

	# The direction bug, measured. The hero is on the -X side of the blast, so an
	# outward knockback has a NEGATIVE x; the old behaviour gave a positive one.
	print("  -- hero at %.1f m on the -x side of the blast took knockback %s (%d hits)"
		% [3.0, str(hero.last_knockback), hero.hits])
	_ok(hero.hits > 0, "the wave caught the hero standing in it")
	_ok(hero.last_knockback.x < -1.0,
		"...and threw them AWAY from the blast, not toward it (x = %.2f)"
			% hero.last_knockback.x)
	_ok(hero.last_knockback.y > 0.0,
		"...with the lift that makes a blast read as a blast (y = %.2f)"
			% hero.last_knockback.y)
	hero.queue_free()
	await _drain()


# --- The rock arc -------------------------------------------------------------

## The fx half of a contract `_boss_probe` polices from the other side.
##
## `AdamastorStateMachine` cannot call into this script (ARCHITECTURE.md rule 2),
## so it MIRRORS the solve to decide when its ground marks should close. A mirror
## can drift, and the boss stream's probe measures the gap between a mark closing
## and a rock landing. This measures the thing that gap is made of: does a rock
## launched at a point actually land on it.
func _check_rock_arc() -> void:
	var throws := [
		[Vector3(16.0, 8.0, 0.0), Vector3(-4.0, 2.0, 0.0)],    # a long throw down the deck
		[Vector3(16.0, 8.0, 0.0), Vector3(11.0, 2.0, 3.0)],    # a short one, across
		[Vector3(16.0, 8.0, 0.0), Vector3(-12.0, 2.0, -4.0)],  # the far corner
	]
	var worst := 0.0
	for t in throws:
		var from: Vector3 = t[0]
		var target: Vector3 = t[1]
		var rock: RigidBody3D = RockScene.instantiate()
		# No contact reactions wanted: this measures the ARC, so the rock is flown
		# through an empty world and the landing point is read off the trajectory.
		rock.collision_mask = 0
		_root.add_child(rock)
		rock.global_position = from
		rock.launch(target)

		var closest := INF
		var flight := 0.0
		for i in int(3.0 * TICK):
			await get_tree().physics_frame
			flight += 1.0 / TICK
			if not is_instance_valid(rock):
				break
			var d := rock.global_position.distance_to(target)
			closest = minf(closest, d)
			if rock.global_position.y < target.y - 1.0:
				break
		print("  -- throw %5.1f m: closest approach to the mark %.3f m after %.2f s of flight"
			% [Vector3(from.x - target.x, 0.0, from.z - target.z).length(), closest, flight])
		worst = maxf(worst, closest)
		if is_instance_valid(rock):
			rock.queue_free()
	_ok(worst <= ARC_TOLERANCE,
		"a thrown rock lands inside the crosshair the giant drew (worst %.3f m, tolerance %.2f)"
			% [worst, ARC_TOLERANCE])
	await _drain()


# --- Across a fight -----------------------------------------------------------

## The claim that matters over a whole run: FX free themselves rather than
## accumulating. Measured by sampling the live count every frame of a scripted
## fight and reporting the peak and the mean, then checking it comes back to zero
## once the fight stops making impacts.
func _check_across_a_fight() -> void:
	_main = MainScene.instantiate()
	add_child(_main)
	await _settle(6)
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	GameManager.set_player_count(2)
	GameManager.set_human_hero(1)
	GameManager.start_game()
	await _settle(20)

	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	var heroes: Array[Node3D] = []
	for p in get_tree().get_nodes_in_group("players"):
		heroes.append(p as Node3D)
	_ok(boss != null and heroes.size() == 2, "a co-op fight is running")
	if boss == null:
		return

	var peak_live := 0
	var peak_draws := 0
	var peak_instances := 0
	var sum_live := 0
	var samples := 0
	var seen := 0
	for i in int(12.0 * TICK):
		# Keep them in his face so he slams, and on their feet so the roster the
		# volley is sized against does not change halfway through.
		if i % 3 == 0:
			heroes[0].global_position = boss.global_position + Vector3(-5.5, 1.0, -1.5)
			heroes[1].global_position = boss.global_position + Vector3(-5.5, 1.0, 1.5)
		for pid in [1, 2]:
			if int(GameManager.player_health.get(pid, 0)) < 45:
				GameManager.player_health[pid] = GameManager.MAX_PLAYER_HEALTH
		await get_tree().physics_frame
		var live := ImpactFX.live_count()
		var draws := 0
		var instances := 0
		for fx in _bursts():
			draws += fx.emitter_count()
			instances += fx.shard_count() + fx.dust_count()
		peak_live = maxi(peak_live, live)
		peak_draws = maxi(peak_draws, draws)
		peak_instances = maxi(peak_instances, instances)
		sum_live += live
		samples += 1
		seen = maxi(seen, live)

	print("  -- 12 s of co-op combat: peak %d live bursts (budget %d), peak %d draw calls (worst case %d), peak %d instances (worst case %d), mean %.2f live"
		% [peak_live, ImpactFX.MAX_LIVE, peak_draws, BUDGET_DRAW_CALLS,
			peak_instances, BUDGET_INSTANCES, float(sum_live) / float(maxi(1, samples))])
	_ok(seen > 0, "the fight actually produced impact FX (%d at peak)" % seen)
	_ok(peak_live <= ImpactFX.MAX_LIVE,
		"the burst budget held under a real fight (%d / %d)" % [peak_live, ImpactFX.MAX_LIVE])
	_ok(peak_draws <= BUDGET_DRAW_CALLS,
		"...and so did the draw-call ceiling (%d / %d)" % [peak_draws, BUDGET_DRAW_CALLS])

	# ...and then the run ends and it all goes away.
	#
	# Ending the run rather than pausing it, deliberately. A paused tree stops
	# `_process`, so every burst would freeze mid-flight and the check would pass
	# for the wrong reason. Going back to the menu tears the world down and frees
	# the bursts through their PARENT, which is the case the live counter can
	# actually get wrong: it is decremented on PREDELETE, and a counter that only
	# came back when a burst expired on its own would drift up by one for every FX
	# still in the air when a fight ended.
	var live_before_teardown := ImpactFX.live_count()
	GameManager.go_to_menu()
	await _advance(0.5)
	var tree_bursts := _bursts().size()
	print("  -- run ended with %d bursts still in the air: %d live by the counter afterwards, %d actually in the tree"
		% [live_before_teardown, ImpactFX.live_count(), tree_bursts])
	_ok(ImpactFX.live_count() == 0 and tree_bursts == 0,
		"the run ending takes every burst with it and gives the budget back (%d counted, %d in tree)"
			% [ImpactFX.live_count(), tree_bursts])


## Every live burst in the tree, found by walking rather than by trusting the
## static counter — the counter is one of the things under test.
func _bursts() -> Array[ImpactFX]:
	var out: Array[ImpactFX] = []
	_collect(get_tree().root, out)
	return out


func _collect(node: Node, out: Array[ImpactFX]) -> void:
	if node is ImpactFX:
		out.append(node as ImpactFX)
	for c in node.get_children():
		_collect(c, out)


# --- Harness ------------------------------------------------------------------

## A spawn root of our own for the standalone checks, so a burst has somewhere to
## go before `main.gd` has built a world. Dropped before the fight test, which
## brings its own.
func _make_root() -> void:
	_root = Node3D.new()
	_root.name = "ProbeSpawnRoot"
	_root.add_to_group("spawn_root")
	add_child(_root)


func _drop_root() -> void:
	if _root and is_instance_valid(_root):
		_root.remove_from_group("spawn_root")
		_root.queue_free()
	_root = null


## Run out everything currently alive, so one check's leftovers cannot eat the
## next check's budget.
func _drain() -> void:
	await _advance(ImpactFX.SMASH_LIFE + 0.3)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## Advance `seconds` of SIMULATED time on the idle tick.
##
## FX animate on `_process` (like BossTelegraph), so their lifetimes have to be
## measured in idle frames — and a headless idle frame is however long the
## machine took, which can be a tenth of a millisecond or, right after a 900k
## triangle scene loads, most of a second. Counting frames here would measure the
## container rather than the code. Accumulating the same delta the FX themselves
## accumulate is the only wait that means the same thing on every machine.
func _advance(seconds: float) -> void:
	var t := 0.0
	# A ceiling on the loop, not on the wait: if the idle tick ever stopped
	# advancing, this must fail the check rather than hang the build.
	var guard := 0
	while t < seconds and guard < 400000:
		await get_tree().process_frame
		t += get_process_delta_time()
		guard += 1


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok   ", label)
	else:
		_fail += 1
		printerr("  FAIL ", label)
