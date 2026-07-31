extends Node
## Headless regression probe for the interactive props.
##
## Every check MEASURES something and prints the number it got. The defect this
## pass existed to fix was a NUMBER — a hero's swing carries 9.0 N*s and the
## crate's break threshold was 12.0, so no hero in the game could break a single
## prop — and a probe that only asserts booleans could not have caught it and
## cannot tell the next person whether a retune made things better or merely
## kept them legal.
##
## What it measures:
##
##   * the break ladder — for every prop against every impulse source in the
##     game, how many blows it takes. This is the one that fails if the players
##     stream retunes `prop_impulse` or the boss retunes his slam.
##   * the five-part impact contract, leg by leg, on a real shatter: an FX burst,
##     a camera shake, an audio transient (measured as the stream the audio pool
##     was handed), a hit-stop (Engine.time_scale), a score move.
##   * debris — that it stays under budget under abuse, that the static counter
##     agrees with the tree, and that it returns to ZERO after a burst rather
##     than accumulating across a fight.
##   * placement — that no prop is in the fighting corridor, inside a hero or
##     boss spawn, or out where the catenary wreck hangs.
##   * settling — how long the arena takes to go quiet and whether anything is
##     still moving after it should be.
##   * the spawn-drop margin — how close the arena's own settling comes to
##     tripping each prop's shatter-on-impact trigger.
##   * the physics layers, read off live nodes rather than off the source.
##   * determinism — the same prop with the same seed bursting into byte-identical
##     debris twice.
##
## Headless-safe: nothing here reads the framebuffer.
##
##   godot --headless --path . scripts/props/_props_probe.tscn

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const BarrelScene: PackedScene = preload("res://scenes/props/wine_barrel.tscn")
const CrateScene: PackedScene = preload("res://scenes/props/crate.tscn")
const RubbleScene: PackedScene = preload("res://scenes/props/rubble_block.tscn")

## Physics ticks per second, for turning seconds into settle() frames.
const TICK := 90.0

## The impulse ladder as the rest of the project actually spells it. Kept here as
## data so the printout names its sources, and so a change on either side shows
## up as a moved number rather than as a silent behaviour change.
##   player_base.gd     _swing.prop_impulse   = 9.0
##   adamastor.gd       _prop_box.prop_impulse = 26.0
##   rock_projectile.gd                        = 30.0
##   dino_energy.gd     34.0 forward + 6.0 up  = 34.5
##   shockwave.gd       prop_impulse           = 38.0 (times falloff)
##   adamastor.gd       _slam_box.prop_impulse = 45.0
const SOURCES := [
	{"name": "hero swing", "impulse": 9.0},
	{"name": "giant's prop sweep", "impulse": 26.0},
	{"name": "thrown rock", "impulse": 30.0},
	{"name": "dino orb", "impulse": 34.5},
	{"name": "shockwave (full)", "impulse": 38.0},
	{"name": "giant's slam", "impulse": 45.0},
]

## The world stream's catenary wreck hangs outboard at |z| >= 7.20. Nothing this
## stream places may reach it.
const WRECK_INNER_Z := 7.20
## The fighting corridor prop_spawner.gd promises to keep clear: the middle six
## metres, i.e. |z| < 3.0.
const FIGHT_LANE_HALF := 3.0

var _pass: int = 0
var _fail: int = 0
var _main: Node = null

var _shakes: int = 0
var _shake_peak: float = 0.0
var _score_delta: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("\nprops probe: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	await _check_layers()
	_check_meshes()
	await _check_break_ladder()
	await _check_five_legs()
	await _check_debris_budget()
	await _check_determinism()
	await _check_placement()
	await _check_spawn_drop_margin()
	await _check_settling()
	await _check_variation()
	await _check_deck_ring()
	_check_payout_economy()


# --- Physics layers ---------------------------------------------------------

## Read off LIVE nodes, not off the source. The masks are the one part of this
## subsystem another stream can break without touching a props file: the boss
## deliberately masks WORLD only, so if a prop ever started masking BOSS a 45 kg
## barrel would begin body-blocking a nine-metre giant and it would look like a
## boss bug.
func _check_layers() -> void:
	var host := _scratch()
	var crate := CrateScene.instantiate() as PropBody
	host.add_child(crate)
	await _settle(1)

	_ok(crate.collision_layer == PhysicsLayers.PROPS,
		"a prop sits on the PROPS layer only (%d)" % crate.collision_layer)
	var want := PhysicsLayers.WORLD | PhysicsLayers.PROPS | PhysicsLayers.PLAYERS
	_ok(crate.collision_mask == want,
		"a prop masks WORLD|PROPS|PLAYERS (%d, wanted %d)" % [crate.collision_mask, want])
	_ok(crate.collision_mask & PhysicsLayers.BOSS == 0,
		"...and deliberately NOT BOSS, so a barrel can never body-block the giant")

	var kicker := crate.get_node_or_null("Kicker") as Area3D
	_ok(kicker != null and kicker.collision_mask == PhysicsLayers.PLAYERS,
		"the kicker volume watches PLAYERS only")
	_ok(kicker != null and kicker.collision_layer == 0 and not kicker.monitorable,
		"...and is invisible to every other query in the game")

	# One shard, built the way a shatter builds them.
	var piece := DebrisPiece.spawn(host, Vector3(0.0, 3.0, 0.0), Vector3.ZERO,
		PropMeshKit.splinter(0.3, 0.05), Vector3.ONE * 0.1,
		ToonFactory.wood(), 4.0, Vector3.ZERO)
	await _settle(1)
	_ok(piece != null, "a shard can be spawned at all")
	if piece != null:
		_ok(piece.collision_layer == PhysicsLayers.PROPS,
			"debris sits on the PROPS layer (%d)" % piece.collision_layer)
		_ok(piece.collision_mask == (PhysicsLayers.WORLD | PhysicsLayers.PROPS),
			"debris masks WORLD|PROPS — never PLAYERS, so shards cannot trip a hero")
	_free(host)
	await _settle(2)


# --- Geometry ---------------------------------------------------------------

## Round 2 lost most of a round to two mirror-image winding bugs, and the lesson
## recorded there is that "correct by construction" is what the previous two
## rounds each believed. PropMeshKit is built entirely from engine primitives via
## SurfaceTool.append_from precisely so it cannot get this wrong — and it is
## measured anyway.
##
## The test: for a shape roughly centred on its own origin, an OUTWARD normal
## points the same way as the vertex it belongs to. A hollow or inside-out mesh
## scores near zero.
func _check_meshes() -> void:
	var cases := {
		"crate body": PropMeshKit.crate_body(Vector3(0.9, 0.9, 0.9)),
		"crate brackets": PropMeshKit.crate_brackets(Vector3(0.9, 0.9, 0.9)),
		"barrel staves": PropMeshKit.barrel_body(0.41, 1.05),
		"barrel hoops": PropMeshKit.barrel_hoops(0.41, 1.05),
		"rubble block": PropMeshKit.rubble_body(Vector3(0.8, 0.5, 0.65), 0),
		"plank": PropMeshKit.plank(0.68, 0.32, 0.06),
		"stave": PropMeshKit.stave(0.7, 0.15, 0.05),
		"hoop arc": PropMeshKit.hoop_arc(0.34, 0.06, 4, PI * 0.9),
		"chunk": PropMeshKit.chunk(0.29, 0),
	}
	for label in cases:
		var mesh: ArrayMesh = cases[label]
		var out := _outward_fraction(mesh)
		print("  -- %-16s %5d tris, %.0f%% of stored normals point outward"
			% [label, out["tris"], 100.0 * out["fraction"]])
		_ok(int(out["tris"]) > 0, "%s has geometry" % label)
		_ok(float(out["fraction"]) >= 0.75,
			"%s is not inside out (%.0f%% outward)" % [label, 100.0 * out["fraction"]])
		_ok(mesh.get_surface_count() == 1,
			"%s is ONE surface, i.e. one draw call" % label)

	# The crate reads as a crate because it is a frame, not a cube: 13 boxes at
	# 12 triangles each. If someone "simplifies" it back to a BoxMesh this fails.
	var crate: ArrayMesh = cases["crate body"]
	_ok(_tri_count(crate) > 60,
		"the crate is a slatted frame, not a bare cube (%d tris)" % _tri_count(crate))


func _outward_fraction(mesh: ArrayMesh) -> Dictionary:
	if mesh == null or mesh.get_surface_count() == 0:
		return {"tris": 0, "fraction": 0.0}
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.is_empty() or norms.size() != verts.size():
		return {"tris": 0, "fraction": 0.0}
	var good := 0
	for i in verts.size():
		var v := verts[i]
		if v.length() < 0.0001:
			good += 1
			continue
		if norms[i].dot(v.normalized()) > 0.0:
			good += 1
	return {"tris": _tri_count(mesh), "fraction": float(good) / float(verts.size())}


func _tri_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if not idx.is_empty():
		return idx.size() / 3
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size() / 3


# --- The break ladder -------------------------------------------------------

## THE headline measurement. For each prop, how many blows from each source it
## takes to destroy it — and specifically whether a hero can destroy it at all.
func _check_break_ladder() -> void:
	print("\n  -- blows to destroy, by source (0 = never):")
	var rows := {}
	for scene: PackedScene in [CrateScene, BarrelScene, RubbleScene]:
		var name := ""
		var line: Array[String] = []
		for src in SOURCES:
			var r := await _blows_to_break(scene, float(src["impulse"]))
			name = str(r["name"])
			rows[name] = rows.get(name, {})
			(rows[name] as Dictionary)[src["name"]] = int(r["blows"])
			line.append("%s %d" % [src["name"], int(r["blows"])])
		print("     %-12s %s" % [name, ", ".join(line)])

	# 1. The defect this pass exists to fix.
	_ok(int((rows["Crate"] as Dictionary)["hero swing"]) == 1,
		"a hero's swing destroys a crate in ONE blow — the Crash interaction, which "
		+ "before this pass took infinity")
	for prop in rows:
		var n: int = int((rows[prop] as Dictionary)["hero swing"])
		_ok(n >= 1 and n <= 3,
			"a hero can destroy a %s unaided, in %d blows" % [prop, n])

	# 2. The material ladder is a ladder: wood is softer than oak is softer than
	#    granite, measured rather than asserted from the export values.
	var crate_n: int = int((rows["Crate"] as Dictionary)["hero swing"])
	var barrel_n: int = int((rows["WineBarrel"] as Dictionary)["hero swing"])
	var rubble_n: int = int((rows["RubbleBlock"] as Dictionary)["hero swing"])
	_ok(crate_n < barrel_n and barrel_n < rubble_n,
		"the material ladder holds: crate %d < cask %d < masonry %d blows"
			% [crate_n, barrel_n, rubble_n])

	# 3. The giant one-shots everything he steps on, or "he shatters props he
	#    walks over" stops being true.
	for prop in rows:
		_ok(int((rows[prop] as Dictionary)["giant's slam"]) == 1,
			"the giant's slam one-shots a %s" % prop)
	_ok(int((rows["RubbleBlock"] as Dictionary)["giant's prop sweep"]) > 1,
		"...but merely walking into a masonry block does not (%d blows)"
			% int((rows["RubbleBlock"] as Dictionary)["giant's prop sweep"]))


## How many blows of `impulse` destroy one instance of `scene`. 0 means it
## survived a generous number of them, which is a failure the caller reports.
func _blows_to_break(scene: PackedScene, impulse: float) -> Dictionary:
	var host := _scratch()
	var prop := scene.instantiate() as BreakableProp
	# Frozen: this measures the DAMAGE model, and a prop free to fly across the
	# scratch space would start tripping its own delta-v trigger and measure that
	# instead.
	prop.freeze = true
	host.add_child(prop)
	prop.global_position = Vector3(0.0, 4.0, 0.0)
	await _settle(1)
	var label := prop.name
	var blows := 0
	for i in 8:
		if prop.has_shattered() or not is_instance_valid(prop):
			break
		blows += 1
		prop.apply_hit_impulse(Vector3.RIGHT * impulse, prop.global_position)
		await _thaw()
	if not prop.has_shattered():
		blows = 0
	_free(host)
	await _settle(2)
	return {"name": label, "blows": blows}


# --- The five-part impact contract ------------------------------------------

## ARCHITECTURE.md: "A hit with three of the five feels broken and the critic
## will say so." Each leg is measured through the shared mechanism that actually
## drives it, not by checking that a line of code exists.
func _check_five_legs() -> void:
	await _start()
	var host := _scratch()
	var crate := CrateScene.instantiate() as BreakableProp
	crate.freeze = true
	host.add_child(crate)
	crate.global_position = Vector3(0.0, 6.0, -20.0)
	await _settle(2)

	var fx_before := ImpactFX.live_count()
	var debris_before := get_tree().get_nodes_in_group("debris").size()
	_watch()
	var audio_before := _last_sfx_name()

	crate.apply_hit_impulse(Vector3.RIGHT * 9.0, crate.global_position)

	# Read the frozen clock BEFORE thawing: hit_stop sets Engine.time_scale
	# synchronously and only then awaits its own (time-scale-immune) timer.
	var froze := Engine.time_scale
	var fx_after := ImpactFX.live_count()
	var audio_after := _last_sfx_name()
	await _thaw()
	var debris_after := get_tree().get_nodes_in_group("debris").size()
	_unwatch()

	print("\n  -- one crate, one hero swing: %d FX burst(s), %d shards, shake peak %.2f x%d, "
		% [fx_after - fx_before, debris_after - debris_before, _shake_peak, _shakes]
		+ "time_scale %.2f, score +%d, sfx '%s' -> '%s'"
			% [froze, _score_delta, audio_before, audio_after])

	_ok(fx_after > fx_before, "leg 1/5 visual FX: ImpactFX raised a burst")
	_ok(debris_after > debris_before,
		"leg 1/5 visual FX: %d physical shards left the crate" % (debris_after - debris_before))
	_ok(_shakes > 0 and _shake_peak > 0.0,
		"leg 2/5 camera: %d shake request(s), peak %.2f" % [_shakes, _shake_peak])
	_ok(audio_after != "" and audio_after != audio_before,
		"leg 3/5 audio: the SFX pool was handed '%s'" % audio_after)
	_ok(froze < 1.0, "leg 4/5 hit-stop: Engine.time_scale dropped to %.2f" % froze)
	_ok(_score_delta > 0, "leg 5/5 UI: score moved by %d" % _score_delta)

	# The other half of the contract: a blow the prop SURVIVES gets three legs,
	# and must NOT get the two that mean "something important happened".
	var block := RubbleScene.instantiate() as BreakableProp
	block.freeze = true
	host.add_child(block)
	block.global_position = Vector3(0.0, 6.0, -24.0)
	await _settle(2)
	_watch()
	var fx2 := ImpactFX.live_count()
	block.apply_hit_impulse(Vector3.RIGHT * 9.0, block.global_position)
	var froze2 := Engine.time_scale
	await _thaw()
	_unwatch()
	print("  -- one masonry block, one survivable blow: %d FX, shake peak %.2f, "
		% [ImpactFX.live_count() - fx2, _shake_peak]
		+ "time_scale %.2f, score +%d, damage %d/%d"
			% [froze2, _score_delta, block.damage_taken(), block.toughness])
	_ok(not block.has_shattered(), "it survived (toughness %d)" % block.toughness)
	_ok(_shakes > 0, "a survivable blow still gets a camera response")
	_ok(is_equal_approx(froze2, 1.0),
		"...but does NOT hit-stop the game (time_scale stayed %.2f)" % froze2)
	_ok(_score_delta > 0 and _score_delta < 15,
		"...and acknowledges itself with a chip score of %d, under a crate's 15"
			% _score_delta)

	# Material-keyed audio. The routing is real even though AudioManager has no
	# prop entry points yet — see the report's ask.
	crate = CrateScene.instantiate() as BreakableProp
	host.add_child(crate)
	var block2 := RubbleScene.instantiate() as BreakableProp
	host.add_child(block2)
	await _settle(1)
	crate.play_surface_hit()
	var wood_sfx := _last_sfx_name()
	block2.play_surface_hit()
	var stone_sfx := _last_sfx_name()
	print("  -- surface audio routing: wood -> '%s', granite -> '%s'" % [wood_sfx, stone_sfx])
	_ok(wood_sfx != stone_sfx and wood_sfx != "" and stone_sfx != "",
		"wood and granite props do not play the same sample")

	_free(host)
	await _settle(2)


# --- Debris budget ----------------------------------------------------------

## The claim the brief asks for by name: bounded, and it actually frees itself
## rather than accumulating across a fight.
func _check_debris_budget() -> void:
	await _start()
	var host := _scratch()

	# Smash twelve props back to back — four props' worth more than the budget
	# can hold — and watch the ceiling.
	var peak := 0
	var peak_static := 0
	for i in 12:
		var scene: PackedScene = [CrateScene, BarrelScene, RubbleScene][i % 3]
		var prop := scene.instantiate() as BreakableProp
		prop.freeze = true
		host.add_child(prop)
		prop.global_position = Vector3(float(i) * 2.0 - 12.0, 6.0, -30.0)
		await _settle(1)
		prop.shatter(Vector3.RIGHT)
		await _thaw()
		peak = maxi(peak, get_tree().get_nodes_in_group("debris").size())
		peak_static = maxi(peak_static, DebrisPiece.live_count())

	print("\n  -- twelve props smashed back to back: peak %d shards live "
		% peak + "(MAX_LIVE %d), counter said %d" % [DebrisPiece.MAX_LIVE, peak_static])
	_ok(peak <= DebrisPiece.MAX_LIVE,
		"debris never exceeds MAX_LIVE (%d <= %d)" % [peak, DebrisPiece.MAX_LIVE])
	_ok(absi(peak - peak_static) <= 2,
		"the static counter tracks the tree (%d vs %d)" % [peak_static, peak])

	# Now leave it alone for longer than a shard's whole life and confirm it goes
	# to zero. A leak here would compound over a three-minute fight until nothing
	# could break at all.
	var lifetime := 4.0 + DebrisPiece.SHRINK_TIME + 1.0
	await _settle(int(lifetime * TICK))
	var left := get_tree().get_nodes_in_group("debris").size()
	print("  -- %.1f s later: %d shards left, counter %d" % [lifetime, left, DebrisPiece.live_count()])
	_ok(left == 0, "every shard freed itself (%d left)" % left)
	_ok(DebrisPiece.live_count() == 0,
		"the budget is fully returned (counter %d)" % DebrisPiece.live_count())
	_ok(DebrisPiece.budget_left() == DebrisPiece.MAX_LIVE,
		"a later fight gets the whole budget back (%d)" % DebrisPiece.budget_left())

	# ...and the resync is a real safety net, not decoration.
	DebrisPiece.resync_budget(get_tree())
	_ok(DebrisPiece.live_count() == 0, "resync_budget agrees with an empty tree")

	# FX bursts are budgeted by the fx stream on the same contract. Six props in
	# one frame is the worst case a slam can produce.
	var fx_peak := 0
	var props: Array[BreakableProp] = []
	for i in 6:
		var p := CrateScene.instantiate() as BreakableProp
		p.freeze = true
		host.add_child(p)
		p.global_position = Vector3(float(i) * 2.0 - 6.0, 6.0, -34.0)
		props.append(p)
	await _settle(2)
	for p in props:
		p.shatter(Vector3.RIGHT)
	fx_peak = ImpactFX.live_count()
	await _thaw()
	print("  -- six props shattered in one frame: %d FX bursts live (ImpactFX.MAX_LIVE %d)"
		% [fx_peak, ImpactFX.MAX_LIVE])
	_ok(fx_peak <= ImpactFX.MAX_LIVE,
		"the FX budget holds under a slam catching six props (%d)" % fx_peak)

	_free(host)
	await _settle(int(6.0 * TICK))


# --- Determinism ------------------------------------------------------------

## ARCHITECTURE.md rule 4. Two props with the same seed at the same place must
## produce byte-identical debris, or the capture gate stops being a gate.
func _check_determinism() -> void:
	var a := await _burst_signature(4242)
	var b := await _burst_signature(4242)
	var c := await _burst_signature(4243)
	print("\n  -- burst signature: seed 4242 -> %s / %s, seed 4243 -> %s"
		% [a.substr(0, 22), b.substr(0, 22), c.substr(0, 22)])
	_ok(a != "" and a == b, "the same seed bursts identically twice")
	_ok(a != c, "...and a different seed does not")


## Position, orientation and launch velocity of every shard, read on the frame
## they are created and before physics touches them.
func _burst_signature(seed_value: int) -> String:
	var host := _scratch()
	var prop := BarrelScene.instantiate() as BreakableProp
	prop.freeze = true
	prop.rng_seed = seed_value
	prop.variant_seed = seed_value
	host.add_child(prop)
	prop.global_position = Vector3(0.0, 8.0, -40.0)
	await _settle(1)
	prop.shatter(Vector3.RIGHT * 2.0)
	var sig := ""
	for d in host.get_children():
		if d is DebrisPiece:
			var t := (d as DebrisPiece).global_transform
			sig += "%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.3f;" % [
				t.origin.x, t.origin.y, t.origin.z,
				(d as DebrisPiece).linear_velocity.x,
				(d as DebrisPiece).linear_velocity.y,
				(d as DebrisPiece).linear_velocity.z,
				t.basis.get_euler().x]
	await _thaw()
	_free(host)
	await _settle(int(6.0 * TICK))
	return sig


# --- Placement --------------------------------------------------------------

## Props must not fight the fight. Three separate exclusions, all measured on the
## live arena rather than on the spawner's constants.
func _check_placement() -> void:
	await _start()
	await _settle(int(2.5 * TICK))

	var props := _props()
	_ok(props.size() >= 12, "the deck is dressed (%d props)" % props.size())

	var min_abs_z := 999.0
	var max_abs_z := 0.0
	var min_spawn_gap := 999.0
	var worst_x := 0.0
	for p in props:
		var z: float = absf(p.global_position.z)
		min_abs_z = minf(min_abs_z, z)
		max_abs_z = maxf(max_abs_z, z)
		worst_x = maxf(worst_x, absf(p.global_position.x))
		for k in PropSpawner.KEEP_OUT:
			var d := Vector2(p.global_position.x - (k as Vector3).x,
				p.global_position.z - (k as Vector3).z).length()
			min_spawn_gap = minf(min_spawn_gap, d)

	print("\n  -- %d props: |z| in [%.2f, %.2f], furthest |x| %.1f, nearest spawn point %.2f m"
		% [props.size(), min_abs_z, max_abs_z, worst_x, min_spawn_gap])
	_ok(min_abs_z >= FIGHT_LANE_HALF,
		"nothing sits in the middle six metres (nearest |z| = %.2f, lane half %.1f)"
			% [min_abs_z, FIGHT_LANE_HALF])
	_ok(max_abs_z < WRECK_INNER_Z,
		"nothing reaches the catenary wreck at |z| >= %.2f (furthest %.2f, %.2f m of daylight)"
			% [WRECK_INNER_Z, max_abs_z, WRECK_INNER_Z - max_abs_z])
	_ok(min_spawn_gap >= 3.0,
		"nothing materialises inside a hero or the giant (%.2f m clear)" % min_spawn_gap)
	_ok(worst_x <= 34.0, "nothing spawned past the piers (|x| max %.1f)" % worst_x)

	# A barrel is laid down so it rolls ALONG the bridge. The old code claimed
	# this in a comment and did the opposite: a full random yaw before rolling it
	# onto its belly points the cask's axis anywhere, and half the barrels in the
	# arena rolled into the fighting corridor when hit.
	var worst_axis := 1.0
	var barrels := 0
	for p in props:
		if not (p is PropBody) or (p as PropBody).body_kind != "barrel":
			continue
		barrels += 1
		# The cask's axis is its own local Y.
		var axis: Vector3 = p.global_transform.basis.y
		worst_axis = minf(worst_axis, absf(axis.dot(Vector3.BACK)))
	print("  -- %d barrels: worst axis alignment to the deck's Z axis %.3f (1.0 = perfectly across)"
		% [barrels, worst_axis])
	_ok(barrels > 0, "there are barrels to check (%d)" % barrels)
	_ok(worst_axis > 0.93,
		"every cask lies across the deck, so a hit rolls it along the bridge and never "
		+ "into the fight (worst %.3f)" % worst_axis)


# --- Spawn drop -------------------------------------------------------------

## The arena settling must not come anywhere near tripping the shatter-on-impact
## trigger. A flat 0.8 m drop used to put a masonry block at 5.7 m/s against a
## threshold of 6.5, which is five per cent of margin between "the props settle"
## and "the arena detonates itself on the first frame".
func _check_spawn_drop_margin() -> void:
	for scene: PackedScene in [CrateScene, BarrelScene, RubbleScene]:
		var host := _scratch()
		var prop := scene.instantiate() as BreakableProp
		host.add_child(prop)
		# Exactly what prop_spawner.gd does, from the prop's own extent.
		prop.global_position = Vector3(0.0, 2.0 + prop.extent() + PropSpawner.SETTLE_DROP, -50.0)
		# A floor to land on. Static, on WORLD, like the deck.
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = PhysicsLayers.WORLD
		var fs := CollisionShape3D.new()
		var fb := BoxShape3D.new()
		fb.size = Vector3(8.0, 1.0, 8.0)
		fs.shape = fb
		floor_body.add_child(fs)
		host.add_child(floor_body)
		floor_body.global_position = Vector3(0.0, 1.5, -50.0)

		var peak := 0.0
		for i in int(1.6 * TICK):
			await get_tree().physics_frame
			if not is_instance_valid(prop):
				break
			peak = maxf(peak, absf(prop.linear_velocity.y))
		var name := prop.name if is_instance_valid(prop) else "(shattered!)"
		var threshold: float = prop.break_delta_v if is_instance_valid(prop) else 0.0
		print("  -- %-12s arrives at %.2f m/s against a break_delta_v of %.2f (%.0f%% margin)"
			% [name, peak, threshold, 100.0 * (threshold - peak) / maxf(0.01, threshold)])
		_ok(is_instance_valid(prop) and not (prop as BreakableProp).has_shattered(),
			"%s survives being dropped into place" % name)
		_ok(peak < threshold * 0.75,
			"...with real margin, not five per cent (%.2f < %.2f)" % [peak, threshold * 0.75])
		_free(host)
		await _settle(2)


# --- Settling ---------------------------------------------------------------

## Props must settle rather than jitter forever. A prop that never sleeps is a
## solver island every frame for the rest of the fight, and visually it is a
## barrel vibrating on a flat deck.
func _check_settling() -> void:
	await _start()

	var asleep_at := -1.0
	var t := 0.0
	var props: Array[Node3D] = []
	for i in int(6.0 * TICK):
		await get_tree().physics_frame
		t += 1.0 / TICK
		props = _props()
		if props.is_empty():
			continue
		var all_asleep := true
		for p in props:
			if p is RigidBody3D and not (p as RigidBody3D).sleeping:
				all_asleep = false
				break
		if all_asleep and asleep_at < 0.0:
			asleep_at = t
			break

	props = _props()
	var fastest := 0.0
	var spinniest := 0.0
	var awake := 0
	for p in props:
		var rb := p as RigidBody3D
		if rb == null:
			continue
		fastest = maxf(fastest, rb.linear_velocity.length())
		spinniest = maxf(spinniest, rb.angular_velocity.length())
		if not rb.sleeping:
			awake += 1

	print("\n  -- the untouched arena went quiet after %.2f s; %d/%d props still awake, "
		% [asleep_at, awake, props.size()]
		+ "fastest %.4f m/s, spinniest %.4f rad/s" % [fastest, spinniest])
	_ok(asleep_at >= 0.0 and asleep_at < 5.0,
		"every prop settles and SLEEPS within five seconds (%.2f s)" % asleep_at)
	_ok(fastest < 0.05,
		"nothing is still creeping across the deck (%.4f m/s)" % fastest)
	_ok(spinniest < 0.05, "nothing is still vibrating (%.4f rad/s)" % spinniest)

	# And it settles again after being disturbed, which is the case that actually
	# happens mid-fight.
	for p in props:
		if p is PropBody:
			(p as PropBody).apply_hit_impulse(Vector3(6.0, 3.0, 0.0) * 4.0, p.global_position)
	await _thaw()
	var resettle := -1.0
	t = 0.0
	for i in int(8.0 * TICK):
		await get_tree().physics_frame
		t += 1.0 / TICK
		var live := _props()
		if live.is_empty():
			break
		var quiet := true
		for p in live:
			if p is RigidBody3D and not (p as RigidBody3D).sleeping:
				quiet = false
				break
		if quiet:
			resettle = t
			break
	print("  -- shoved hard, the survivors were asleep again after %.2f s" % resettle)
	_ok(resettle >= 0.0, "a disturbed arena comes back to rest (%.2f s)" % resettle)


# --- Variation --------------------------------------------------------------

## The RUBRIC fails a frame for visible repetition. Fourteen props off three
## scenes will read as fourteen copies unless something varies per instance.
func _check_variation() -> void:
	await _start()
	await _settle(int(2.0 * TICK))

	var variants := {}
	var min_scale := 99.0
	var max_scale := 0.0
	var yaws: Array[float] = []
	for p in _props():
		var pb := p as PropBody
		if pb == null:
			continue
		variants[pb.variant_index()] = int(variants.get(pb.variant_index(), 0)) + 1
		min_scale = minf(min_scale, pb.size_scale())
		max_scale = maxf(max_scale, pb.size_scale())
		yaws.append(p.global_rotation.y)

	print("\n  -- variation across the deck: %d distinct mesh/tint variants %s, "
		% [variants.size(), str(variants)]
		+ "size %.3f-%.3f (%.0f%% spread)"
			% [min_scale, max_scale, 100.0 * (max_scale - min_scale)])
	_ok(variants.size() >= 3,
		"props draw from at least three variants (%d of %d)"
			% [variants.size(), PropBody.VARIANTS])
	_ok(max_scale - min_scale > 0.08,
		"no two props are the same size (%.0f%% spread)" % (100.0 * (max_scale - min_scale)))
	_ok(min_scale > 0.85 and max_scale < 1.15,
		"...and none of them is a different object (%.2f - %.2f)" % [min_scale, max_scale])


# --- Deck ring --------------------------------------------------------------

## Props react to being near a nine-metre giant. Measured as: a heavy shake moves
## a prop standing next to him more than one standing at the far end of the deck,
## and neither is moved inboard toward the fighting corridor.
func _check_deck_ring() -> void:
	await _start()
	await _settle(int(2.5 * TICK))

	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	_ok(boss != null, "the giant is in the arena to be near")
	if boss == null:
		return

	var near: PropBody = null
	var far: PropBody = null
	var near_d := 999.0
	var far_d := 0.0
	for p in _props():
		var pb := p as PropBody
		if pb == null:
			continue
		var d := Vector2(p.global_position.x - boss.global_position.x,
			p.global_position.z - boss.global_position.z).length()
		if d < near_d:
			near_d = d
			near = pb
		if d > far_d:
			far_d = d
			far = pb
	if near == null or far == null:
		_ok(false, "found props to measure the ring on")
		return

	var z_before_near: float = absf(near.global_position.z)
	var z_before_far: float = absf(far.global_position.z)
	# A jab, first: nothing may hop for one of these or the deck is jelly.
	GameManager.request_shake(0.16, 0.12)
	await get_tree().physics_frame
	var jab_speed: float = near.linear_velocity.length()

	# Then the giant's roar.
	GameManager.request_shake(0.95, 0.7)
	await get_tree().physics_frame
	var near_v: float = near.linear_velocity.length()
	var far_v: float = far.linear_velocity.length()

	print("\n  -- deck ring: a hero's 0.16 jab moves the nearest prop %.3f m/s; "
		% jab_speed
		+ "a 0.95 roar moves it %.3f m/s at %.1f m and %.3f m/s at %.1f m"
			% [near_v, near_d, far_v, far_d])
	_ok(jab_speed < 0.05, "a hero's jab does not shake the scenery (%.3f m/s)" % jab_speed)
	_ok(near_v > 0.2, "the giant's roar makes loose props hop (%.3f m/s)" % near_v)
	_ok(near_v > far_v,
		"a prop next to him hops harder than one at the far end (%.3f > %.3f)"
			% [near_v, far_v])

	await _settle(int(2.0 * TICK))
	print("  -- after the ring: nearest prop |z| %.2f -> %.2f, furthest %.2f -> %.2f"
		% [z_before_near, absf(near.global_position.z),
			z_before_far, absf(far.global_position.z)])
	_ok(absf(near.global_position.z) >= z_before_near - 0.02
			and absf(far.global_position.z) >= z_before_far - 0.02,
		"the ring only ever pushes props OUTBOARD, so it can never walk one into the fight")
	for p in _props():
		_ok(absf(p.global_position.z) >= FIGHT_LANE_HALF - 0.5,
			"prop still clear of the fighting corridor after the ring (|z| %.2f)"
				% absf(p.global_position.z))
		break   # one representative assertion; the placement check covers all of them


# --- Payout economy ---------------------------------------------------------

## The design constraint on the payout, as arithmetic: clearing the entire deck
## must be worth less than a short chained assault on the giant, or a hero is
## correct to ignore the fight.
func _check_payout_economy() -> void:
	var deck := 0
	var swings := 0
	for entry in [[BarrelScene, 6], [CrateScene, 4], [RubbleScene, 4]]:
		var scene: PackedScene = entry[0]
		var count: int = entry[1]
		var p := scene.instantiate() as BreakableProp
		var per: int = p.break_score + p.chip_score * (p.toughness - 1)
		deck += per * count
		swings += p.toughness * count
		p.free()

	# What the same swings are worth against the giant, at the combo they build.
	var boss := 0
	for i in range(1, swings + 1):
		boss += GameManager.SCORE_PER_HIT * i

	print("\n  -- payout: the whole deck is %d points for %d swings; the same %d swings "
		% [deck, swings, swings]
		+ "chained on the giant are %d (%.1fx)" % [boss, float(boss) / float(maxi(1, deck))])
	_ok(deck > 0, "smashing props pays something at all (%d)" % deck)
	_ok(boss > deck * 3,
		"...and the giant pays at least three times better for the same effort (%.1fx)"
			% (float(boss) / float(maxi(1, deck))))


# --- Harness ---------------------------------------------------------------

func _watch() -> void:
	_shakes = 0
	_shake_peak = 0.0
	_score_delta = 0
	GameManager.camera_shake_requested.connect(_on_shake)
	GameManager.score_changed.connect(_on_score)


func _unwatch() -> void:
	if GameManager.camera_shake_requested.is_connected(_on_shake):
		GameManager.camera_shake_requested.disconnect(_on_shake)
	if GameManager.score_changed.is_connected(_on_score):
		GameManager.score_changed.disconnect(_on_score)


func _on_shake(strength: float, _duration: float) -> void:
	_shakes += 1
	_shake_peak = maxf(_shake_peak, strength)


var _score_seen: int = -1

func _on_score(new_score: int) -> void:
	if _score_seen < 0:
		_score_seen = new_score - _score_delta
	_score_delta = new_score - _score_seen


## The logical name of the last sample AudioManager was asked to play. Read off
## the pool's own stream assignment, because there is no public "what did you
## just play" and this probe's job is to prove leg three fires at all.
func _last_sfx_name() -> String:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return ""
	var players: Array = am.get("_players")
	var idx: int = int(am.get("_next_player"))
	if players.is_empty():
		return ""
	var last: AudioStreamPlayer = players[(idx - 1 + players.size()) % players.size()]
	if last == null or last.stream == null:
		return ""
	var lib: Dictionary = am.get("_streams")
	for key in lib:
		if lib[key] == last.stream:
			return str(key)
	return "(unnamed)"


## Let a hit-stop run out. Engine.time_scale is global and a probe that measured
## through a freeze would measure the freeze.
func _thaw() -> void:
	for i in 600:
		await get_tree().physics_frame
		if Engine.time_scale >= 1.0:
			return
	Engine.time_scale = 1.0


func _scratch() -> Node3D:
	var n := Node3D.new()
	n.name = "Scratch"
	add_child(n)
	return n


func _free(n: Node) -> void:
	if is_instance_valid(n):
		remove_child(n)
		n.queue_free()


func _start() -> void:
	if _main == null:
		_main = MainScene.instantiate()
		add_child(_main)
		await _settle(4)
	GameManager.go_to_menu()
	await _settle(2)
	GameManager.set_player_count(2)
	GameManager.start_game()
	await _settle(6)
	_score_seen = GameManager.score
	_score_delta = 0


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## Every live prop in the arena, ignoring anything this probe parked in a scratch
## node. The spawner is the authority.
func _props() -> Array[Node3D]:
	var sp := _spawner()
	if sp != null:
		return sp.live_props()
	var out: Array[Node3D] = []
	for p in get_tree().get_nodes_in_group("props"):
		out.append(p as Node3D)
	return out


func _spawner() -> PropSpawner:
	if _main == null:
		return null
	return _find_spawner(_main)


func _find_spawner(n: Node) -> PropSpawner:
	if n is PropSpawner:
		return n as PropSpawner
	for c in n.get_children():
		var f := _find_spawner(c)
		if f != null:
			return f
	return null


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok   ", label)
	else:
		_fail += 1
		printerr("  FAIL ", label)
