class_name PropSpawner
extends Node3D
## Scatters the arena's interactive props along the bridge deck.
##
## Drop this node into the world scene (or call populate() on it) and the deck
## gets barrels, crates and loose masonry the heroes and the giant can knock
## around. Placement is deterministic — same seed, same arena, every run — so a
## screenshot pass or a bug repro lands on identical geometry.
##
## Props hug the rails. The centre lane is where the fight happens and a barrel
## parked in it reads as an obstacle course, not as scenery. That constraint is
## structural, not advisory, and it is enforced in three separate places:
##
##   * placement keeps |z| in [edge_z - jitter, edge_z + jitter], well outside
##     the middle six metres, and clear of the hero and boss spawns;
##   * a barrel is laid down with its AXIS ACROSS THE DECK, so the direction it
##     rolls when something hits it is along the bridge, not into the fight;
##   * PropBody's deck-ring jolt only ever pushes outboard.
##
## The outer edge of the lane also has to stay clear of the world stream's
## catenary wreck, which hangs outboard at |z| >= 7.20. The furthest a prop is
## placed is |z| = 4.55, so there are 2.65 m of daylight between the two and
## _props_probe.gd asserts it.
##
## Budget: DEFAULTS put 14 rigid bodies on the deck, all asleep within a second
## of spawning, plus at most DebrisPiece.MAX_LIVE (40) shards while things are
## actively being smashed. Raise the counts knowing every prop is a live Jolt
## body the moment anything touches it.

const BarrelScene: PackedScene = preload("res://scenes/props/wine_barrel.tscn")
const CrateScene: PackedScene = preload("res://scenes/props/crate.tscn")
const RubbleScene: PackedScene = preload("res://scenes/props/rubble_block.tscn")

@export var barrel_count: int = 6
@export var crate_count: int = 4
@export var rubble_count: int = 4
@export var rng_seed: int = 20260727

@export_group("Placement")
## Deck span props may occupy. The deck itself runs x in [-50, 50]; keeping
## inside +-34 stops props spawning past the piers where nobody fights.
@export var x_min: float = -32.0
@export var x_max: float = 32.0
## Distance from the centreline. The rail walls are at |z| = 6, so 4.2 tucks
## props against them and leaves the middle six metres clear.
@export var edge_z: float = 4.2
## Deck top surface. Props are dropped a little above it and settle.
@export var deck_top_y: float = 2.0
## Keep-out radius around the hero and boss spawn points.
@export var spawn_clearance: float = 3.5

@export_group("Lifecycle")
## Repopulate on every game_started, so Play Again restores the props a previous
## run smashed. The world root is reused across runs, so nothing else would.
@export var refill_each_run: bool = true
@export var auto_populate: bool = true

## Matches main.gd's P1_SPAWN / P2_SPAWN / BOSS_SPAWN closely enough to keep
## props out of the three places something is guaranteed to materialise.
const KEEP_OUT := [Vector3(-12.0, 0.0, 0.0), Vector3(-8.0, 0.0, 2.0), Vector3(16.0, 0.0, 0.0)]

## How far a prop's LOWEST point starts above the deck.
##
## This used to be a flat 0.8 m above the deck surface regardless of the prop's
## own size, which is 0.55 m of free fall for a masonry block. At gravity 30 that
## is 5.7 m/s arriving in one physics frame, and BreakableProp's delta-v trigger
## fires at 6.5 — five per cent of margin between "the arena settles" and "the
## arena detonates itself on the first frame of the fight". Dropping every prop
## by the same small amount from its own resting height keeps the arrival speed
## at 2.7-4.0 m/s whatever the prop is, and _props_probe.gd measures the margin
## against each prop's own threshold rather than trusting this comment.
const SETTLE_DROP := 0.12

## Half-width of the jitter either side of `edge_z`.
const LANE_JITTER := 0.35

## How far a laid-down barrel's axis may stray from the deck's Z axis.
##
## The old code gave every prop a full random yaw and then rolled the barrels
## onto their bellies, with a comment claiming the axis ended up across the deck.
## It does not: rotate_object_local(RIGHT, PI/2) after a yaw of `a` leaves the
## cask's axis at (sin a, 0, cos a), so a full random yaw pointed it anywhere —
## and half the barrels in the arena rolled INTO the fighting corridor when hit,
## which is the exact failure the lane rule exists to prevent. 0.22 rad is 12.6
## degrees: enough that no two barrels look aligned, little enough that every one
## of them rolls along the bridge.
const BARREL_AXIS_JITTER := 0.22

var _rng := RandomNumberGenerator.new()
var _live: Array[Node3D] = []


func _ready() -> void:
	if refill_each_run:
		GameManager.game_started.connect(_on_game_started)
	if auto_populate:
		populate()


func _on_game_started() -> void:
	# Before repopulating, not after: the budget has to be honest about the
	# shards left over from the previous run before this one starts asking for
	# more. See DebrisPiece.resync_budget for why a static counter needs this.
	DebrisPiece.resync_budget(get_tree())
	populate()


## Clear whatever is left and lay the props out again. Idempotent.
func populate() -> void:
	for n in _live:
		if is_instance_valid(n):
			n.queue_free()
	_live.clear()

	_rng.seed = rng_seed
	var slot := 0
	slot = _place(BarrelScene, barrel_count, slot, true)
	slot = _place(CrateScene, crate_count, slot, false)
	_place(RubbleScene, rubble_count, slot, false)


## The props currently on the deck. For the probe and for anything that wants to
## sweep them; nothing else should be reaching into this node.
func live_props() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in _live:
		if is_instance_valid(n):
			out.append(n)
	return out


## The innermost and outermost |z| a prop may be PLACED at. Rigid bodies move
## afterwards, which is the point of them; this is the placement contract.
func lane_bounds() -> Vector2:
	return Vector2(edge_z - LANE_JITTER, edge_z + LANE_JITTER)


# --- Internals --------------------------------------------------------------

## Lay `count` copies down, alternating rails so both edges stay dressed.
## `lay_on_side` tips barrels over so they roll when something hits them.
func _place(scene: PackedScene, count: int, slot: int, lay_on_side: bool) -> int:
	for i in count:
		var spot := _pick_spot(slot)
		slot += 1
		var prop: Node3D = scene.instantiate()
		# Both seeds are set BEFORE add_child, because _ready() reads them: the
		# variant decides the mesh and tint this instance wears, and it has to be
		# decided before anything is built. Drawn from the shared placement
		# stream so adding a barrel does not reshuffle every other prop.
		if prop is PropBody:
			(prop as PropBody).variant_seed = int(_rng.randi()) | 1
		if prop is BreakableProp:
			(prop as BreakableProp).rng_seed = int(_rng.randi()) | 1

		var yaw := _rng.randf_range(-PI, PI)
		if lay_on_side:
			# Nearly across the deck, so a hit sends it down the bridge rather
			# than into the fighting corridor. See BARREL_AXIS_JITTER.
			yaw = _rng.randf_range(-BARREL_AXIS_JITTER, BARREL_AXIS_JITTER)
			if _rng.randf() < 0.5:
				yaw += PI     # same axis, other end forward

		add_child(prop)
		prop.rotation = Vector3(0.0, yaw, 0.0)
		if lay_on_side:
			prop.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		# _ready() has run by now, so the prop's own (variant-scaled) extent is
		# available and every prop starts the same small distance off the deck
		# whatever size it is.
		var rest: float = (prop as PropBody).extent() if prop is PropBody else 0.5
		prop.global_position = Vector3(spot.x, deck_top_y + rest + SETTLE_DROP, spot.z)
		_live.append(prop)
	return slot


func _pick_spot(slot: int) -> Vector3:
	var z := edge_z if slot % 2 == 0 else -edge_z
	# 12 tries is plenty for a 64 m span with three small keep-out zones; the
	# fallback just accepts the last candidate rather than looping forever.
	var x := 0.0
	for attempt in 12:
		x = _rng.randf_range(x_min, x_max)
		if _clear_of_spawns(x, z):
			break
	return Vector3(x, 0.0, z + _rng.randf_range(-LANE_JITTER, LANE_JITTER))


func _clear_of_spawns(x: float, z: float) -> bool:
	for k in KEEP_OUT:
		var dx: float = x - (k as Vector3).x
		var dz: float = z - (k as Vector3).z
		if sqrt(dx * dx + dz * dz) < spawn_clearance:
			return false
	return true
