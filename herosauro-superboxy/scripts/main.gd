extends Node3D
## Main: the root scene. At startup it shows ONLY the UI (so the menu is a real
## screen, not an overlay on a live arena). The gameplay world — bridge, camera,
## hero and boss — is built on the MENU->PLAYING transition and torn down when we
## return to the menu. Kept code-driven so each sub-scene stays self-contained.
##
## WHO IS PLAYING is a roster, not a constant. MatchConfig.solo() returns one
## slot and that is what ships, but the spawn loop below does not know that —
## hand it two slots and it spawns two heroes, each with its own InputSource.
## See match_config.gd for what co-op still needs beyond this file (a p2_ action
## set, a two-subject camera rule, a second HUD row).

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
var _world_root: Node3D    # holds bridge + camera + hero + boss; freed on return to menu
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
	GameManager.player_damaged.connect(_on_player_damaged)

	GameManager.change_state(GameManager.State.MENU)


# --- World lifecycle -------------------------------------------------------

## Build the gameplay world. Idempotent: a no-op if it already exists (so PLAY
## AGAIN, which goes VICTORY->PLAYING without passing MENU, reuses the live world
## and just resets it via game_started).
func _build_world() -> void:
	if _world_root and is_instance_valid(_world_root):
		return

	_world_root = Node3D.new()
	_world_root.name = "World"
	add_child(_world_root)

	_world_root.add_child(WorldScene.instantiate())

	_spawn_root = Node3D.new()
	_spawn_root.name = "Spawned"
	_spawn_root.add_to_group("spawn_root")
	_world_root.add_child(_spawn_root)

	# The first slot is the one the camera follows and the HUD reads. With a
	# one-slot roster that is simply "the hero".
	var heroes: Array[PlayerBase] = []
	for slot in MatchConfig.solo():
		heroes.append(_spawn_player(slot))
	var hero: PlayerBase = heroes[0]

	# Knockable barrels, crates and rubble along the deck. It keeps clear of the
	# hero and boss spawns itself, so it goes in before they matter.
	var props := PropSpawnerScene.instantiate()
	props.name = "Props"
	_world_root.add_child(props)

	var boss := AdamastorScene.instantiate()
	_world_root.add_child(boss)
	boss.global_position = BOSS_SPAWN

	# Last, so the rig's opening frame already knows where both hero and giant are.
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	rig.target = hero
	_world_root.add_child(rig)


func _teardown_world() -> void:
	if _world_root and is_instance_valid(_world_root):
		_world_root.queue_free()
	_world_root = null
	_spawn_root = null


func _spawn_player(slot: MatchConfig.Slot) -> PlayerBase:
	var p: PlayerBase = slot.scene.instantiate()
	p.player_id = slot.player_id
	p.spawn_position = slot.spawn
	# Before add_child, so _ready() already sees the right source rather than
	# reading a frame of the default one.
	p.input = slot.input
	_world_root.add_child(p)
	p.global_position = slot.spawn
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


func _on_game_over(_victory: bool) -> void:
	_hud.visible = false


## Solo defeat bridge. GameManager seeds its health dict {1, 2} whatever the
## roster is, so with only slot 1 spawned the "both down" test can never fire and
## the fight could never be lost.
##
## Guarded on the roster rather than on a hardcoded id: with two heroes actually
## in the scene this must NOT end the run when one of them falls, and
## GameManager's own _all_heroes_down() — which counts live players — is already
## correct for that case.
func _on_player_damaged(_id: int, _amount: int, new_health: int) -> void:
	if new_health > 0:
		return
	if get_tree().get_nodes_in_group("players").size() > 1:
		return   # co-op: let GameManager decide, it counts the live heroes
	_force_defeat.call_deferred()


func _force_defeat() -> void:
	if GameManager.state == GameManager.State.PLAYING:
		GameManager._end_game(false)
