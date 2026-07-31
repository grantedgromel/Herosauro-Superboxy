extends Node3D
## Main: the root scene. At startup it shows ONLY the UI (so the menu is a real
## screen, not an overlay on a live arena). The gameplay world — bridge, camera,
## heroes and boss — is built on the MENU->PLAYING transition and torn down when
## we return to the menu. Kept code-driven so each sub-scene stays self-contained.
##
## TWO-PLAYER LOCAL CO-OP. Herosauro is player 1 and Super Boxy is player 2, and
## the roster comes from `GameManager.active_player_ids()` — the one place that
## turns `player_count` / `human_hero` into a list of heroes. A solo run spawns
## exactly the hero the menu chose and nothing else; there is no AI ally.

const HeroScenes := {
	1: preload("res://scenes/players/herosauro.tscn"),
	2: preload("res://scenes/players/superboxy.tscn"),
}

## Both heroes start on the Gaia side of the deck, a couple of metres apart and
## clear of the tram rails, facing the giant down the bridge. prop_spawner.gd's
## KEEP_OUT list mirrors these two points and BOSS_SPAWN, so nothing materialises
## inside a hero on the first frame.
const P1_SPAWN := Vector3(-12.0, 4.0, 0.0)
const P2_SPAWN := Vector3(-8.0, 4.0, 2.0)
const BOSS_SPAWN := Vector3(16.0, 2.0, 0.0)   # matches Adamastor.SPAWN

const WorldScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")
const AdamastorScene: PackedScene = preload("res://scenes/boss/adamastor.tscn")
const PropSpawnerScene: PackedScene = preload("res://scenes/props/prop_spawner.tscn")
const MainMenuScene: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const HUDScene: PackedScene = preload("res://scenes/ui/hud.tscn")
const GameOverScene: PackedScene = preload("res://scenes/ui/game_over.tscn")

var _menu: Control
var _hud: CanvasItem
var _game_over: CanvasItem
var _world_root: Node3D    # holds bridge + camera + heroes + boss; freed on return to menu
var _spawn_root: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	_menu = MainMenuScene.instantiate()
	_hud = HUDScene.instantiate()
	_game_over = GameOverScene.instantiate()
	ui.add_child(_hud)
	ui.add_child(_game_over)
	ui.add_child(_menu)

	GameManager.state_changed.connect(_on_state_changed)
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_over.connect(_on_game_over)

	GameManager.change_state(GameManager.State.MENU)


# --- World lifecycle -------------------------------------------------------

## Build the gameplay world. Idempotent: a no-op if a world with the RIGHT
## ROSTER already exists (so PLAY AGAIN, which goes VICTORY->PLAYING without
## passing MENU, reuses the live world and just resets it via game_started).
##
## The roster test is the co-op half of that: a world built for one hero is not
## reusable for a session the menu has since switched to two, and returning early
## on "a world exists" would have left the second player without a body.
func _build_world() -> void:
	if _world_root and is_instance_valid(_world_root):
		if _roster_matches():
			return
		_teardown_world()

	_world_root = Node3D.new()
	_world_root.name = "World"
	add_child(_world_root)

	_world_root.add_child(WorldScene.instantiate())

	_spawn_root = Node3D.new()
	_spawn_root.name = "Spawned"
	_spawn_root.add_to_group("spawn_root")
	_world_root.add_child(_spawn_root)

	var first: PlayerBase = null
	for id in GameManager.active_player_ids():
		var hero := _spawn_player(id)
		if first == null:
			first = hero

	# Knockable barrels, crates and rubble along the deck. It keeps clear of the
	# hero and boss spawns itself, so it goes in before they matter.
	var props := PropSpawnerScene.instantiate()
	props.name = "Props"
	_world_root.add_child(props)

	var boss := AdamastorScene.instantiate()
	_world_root.add_child(boss)
	boss.global_position = BOSS_SPAWN

	# Last, so the rig's opening frame already knows where the heroes and the
	# giant are. `target` only matters in solo, where the rig orbits one hero;
	# in co-op it reads the whole "players" group and frames the group instead.
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	rig.target = first
	_world_root.add_child(rig)


func _teardown_world() -> void:
	if _world_root and is_instance_valid(_world_root):
		# Detach FIRST, then free. queue_free() alone leaves the old heroes in the
		# tree for the rest of the frame, so a rebuild in the same frame (a roster
		# change) would see four nodes in the "players" group and frame a camera
		# on the average of two worlds.
		remove_child(_world_root)
		_world_root.queue_free()
	_world_root = null
	_spawn_root = null


func _spawn_player(id: int) -> PlayerBase:
	var scene: PackedScene = HeroScenes[id]
	var spawn := P1_SPAWN if id == 1 else P2_SPAWN
	var p: PlayerBase = scene.instantiate()
	p.player_id = id
	p.spawn_position = spawn
	_world_root.add_child(p)
	p.global_position = spawn
	return p


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		GameManager.toggle_pause()


func _on_state_changed(new_state: int) -> void:
	match new_state:
		GameManager.State.MENU:
			_teardown_world()
			_menu.visible = true
			_hud.visible = false
			_game_over.visible = false
		GameManager.State.PLAYING:
			_build_world()
			_menu.visible = false
			_hud.visible = true
			_game_over.visible = false
		GameManager.State.PAUSED:
			pass  # HUD shows its own pause overlay in response to the signal.
		GameManager.State.VICTORY, GameManager.State.DEFEAT:
			pass  # game_over UI is shown by _on_game_over; world stays for the pose.


func _on_game_started() -> void:
	# state_changed(PLAYING) has already built (or rebuilt) the world by now; this
	# is belt and braces for anything that starts a run without a state change.
	_build_world()

	for p in get_tree().get_nodes_in_group("players"):
		if p.has_method("reset_state"):
			p.reset_state()
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss and boss.has_method("reset_boss"):
		boss.reset_boss()
	# Clear any leftover projectiles / fx from a previous run.
	if is_instance_valid(_spawn_root):
		for c in _spawn_root.get_children():
			c.queue_free()


## Do the heroes in the tree match the roster this session is about to play?
func _roster_matches() -> bool:
	var want := GameManager.active_player_ids()
	var have: Array[int] = []
	for p in get_tree().get_nodes_in_group("players"):
		have.append(int(p.player_id))
	if have.size() != want.size():
		return false
	for id in want:
		if not have.has(id):
			return false
	return true


func _on_game_over(_victory: bool) -> void:
	_hud.visible = false
