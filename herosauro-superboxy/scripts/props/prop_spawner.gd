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
## parked in it reads as an obstacle course, not as scenery.
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

var _rng := RandomNumberGenerator.new()
var _live: Array[Node3D] = []


func _ready() -> void:
	if refill_each_run:
		GameManager.game_started.connect(populate)
	if auto_populate:
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


# --- Internals --------------------------------------------------------------

## Lay `count` copies down, alternating rails so both edges stay dressed.
## `lay_on_side` tips barrels over so they roll when something hits them.
func _place(scene: PackedScene, count: int, slot: int, lay_on_side: bool) -> int:
	for i in count:
		var pos := _pick_spot(slot)
		slot += 1
		var prop: Node3D = scene.instantiate()
		if prop is BreakableProp:
			# Pin each prop's shatter pattern off the shared stream, so adding a
			# barrel does not reshuffle every other prop's debris.
			(prop as BreakableProp).rng_seed = int(_rng.randi()) | 1
		add_child(prop)
		prop.global_position = pos
		prop.rotation = Vector3(0.0, _rng.randf_range(-PI, PI), 0.0)
		if lay_on_side:
			# Rolled onto its belly, axis across the deck: a hit sends it down
			# the bridge rather than into the rail.
			prop.rotate_object_local(Vector3.RIGHT, PI * 0.5)
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
	return Vector3(x, deck_top_y + 0.8, z + _rng.randf_range(-0.35, 0.35))


func _clear_of_spawns(x: float, z: float) -> bool:
	for k in KEEP_OUT:
		var dx: float = x - (k as Vector3).x
		var dz: float = z - (k as Vector3).z
		if sqrt(dx * dx + dz * dz) < spawn_clearance:
			return false
	return true
