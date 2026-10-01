class_name LevelBase
extends Node3D
## The root of every storybook level that is not the bridge
## (docs/story/ADAPTATION.md, "Levels").
##
## main.gd load()s `res://scenes/levels/<id>/<id>_level.tscn`, instances it under
## World, spawns the heroes at `spawn_point()` and the CameraRig, and on
## `game_started` (after the heroes exist) calls `begin()`. Hero and camera code
## that used to key on the giant falls back to this node when there is no boss:
## the co-op camera aims at `camera_focus()`, a hero below `kill_y()` bubbles
## back, landing dust uses `ground_surface()`.
##
## A level owns its WorldEnvironment, lights, geometry, colliders, enemies, NPCs
## and objective logic. It reports progress ONLY through the GameManager
## mutators (`set_objective`, `advance_objective`, `complete_chapter`,
## `request_story_beat`) and parents anything it spawns at runtime to the
## "spawn_root" group node, which main.gd clears at the start of every run.
##
## Override what you need; every default below is safe. See
## scripts/levels/sandbox/sandbox_level.gd for the smallest complete example.


func _init() -> void:
	# In _init, not _ready, so a subclass that overrides _ready and forgets
	# super._ready() is still found. Groups set before entering the tree are
	# registered when the node enters it.
	add_to_group("level")


## Where hero `player_id` (1 or 2) appears, in global coordinates. REQUIRED in
## practice: the default just puts the pair side by side at the level origin.
func spawn_point(player_id: int) -> Vector3:
	return global_position + Vector3(0.0, 1.2, -1.5 + 3.0 * float(player_id - 1))


## Where the co-op camera looks when there is no boss. The rig yaws to look from
## the heroes' midpoint toward this point, so put it AHEAD of where play happens
## (outside the arena is fine). Heroes face +X at spawn, like on the bridge.
func camera_focus() -> Vector3:
	return global_position + Vector3(30.0, 0.0, 0.0)


## Below this height a hero bubbles back next to their partner.
func kill_y() -> float:
	return -20.0


## ToonFactory.Surface used for landing and recovery dust.
func ground_surface() -> int:
	return ToonFactory.Surface.COBBLE


## AudioManager music track id, played on game_started.
func music_track() -> String:
	return "battle_phase1"


## Called on every game_started, after the heroes exist and the spawn root has
## been cleared. Reset the level's own state here (PLAY AGAIN reuses the level)
## and set the objective.
func begin() -> void:
	pass


## Where the idle hint arrow points. Vector3.INF = no hint.
func hint_target() -> Vector3:
	return Vector3.INF


## The level in the tree, or null on the bridge. For hero and camera code.
static func current(tree: SceneTree) -> LevelBase:
	if tree == null:
		return null
	return tree.get_first_node_in_group("level") as LevelBase
