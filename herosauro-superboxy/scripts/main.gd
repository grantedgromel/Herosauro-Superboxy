extends Node3D
## Main: the root scene. At startup it shows ONLY the UI (so the menu is a real
## screen, not an overlay on a live arena). The gameplay world — bridge, camera,
## players and boss — is built on the MENU->PLAYING transition and torn down when
## we return to the menu. Kept code-driven so each sub-scene stays self-contained.

const P1_SPAWN := Vector3(-12.0, 4.0, 0.0)
const P2_SPAWN := Vector3(-8.0, 4.0, 2.0)
const BOSS_SPAWN := Vector3(16.0, 2.0, 0.0)   # matches Adamastor.SPAWN

const WorldScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")
const HerosauroScene: PackedScene = preload("res://scenes/players/herosauro.tscn")
const SuperBoxyScene: PackedScene = preload("res://scenes/players/superboxy.tscn")
const AdamastorScene: PackedScene = preload("res://scenes/boss/adamastor.tscn")
const CameraRigScript: GDScript = preload("res://scripts/camera_rig.gd")
const MainMenuScene: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const HUDScene: PackedScene = preload("res://scenes/ui/hud.tscn")
const GameOverScene: PackedScene = preload("res://scenes/ui/game_over.tscn")

var _menu: Control
var _hud: CanvasItem
var _game_over: CanvasItem
var _world_root: Node3D    # holds bridge + camera + players + boss; freed on return to menu
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
	ui.add_child(Banter.new())
	ui.add_child(_game_over)
	ui.add_child(_menu)

	GameManager.state_changed.connect(_on_state_changed)
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_over.connect(_on_game_over)

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

	var rig: Node3D = CameraRigScript.new()
	rig.name = "CameraRig"
	_world_root.add_child(rig)

	# id 1 = Herosauro, id 2 = Super Boxy always, so HUD/camera/boss group code is unchanged.
	var p1 := _spawn_player(HerosauroScene, 1, P1_SPAWN)
	var p2 := _spawn_player(SuperBoxyScene, 2, P2_SPAWN)

	# 1-player: the human drives `human_hero`, the other hero gets an AI ally brain.
	if GameManager.player_count == 1:
		var bot: PlayerBase = p2 if GameManager.human_hero == 1 else p1
		bot.ai_controller = AllyController.new(bot)

	var boss := AdamastorScene.instantiate()
	_world_root.add_child(boss)
	boss.global_position = BOSS_SPAWN


func _teardown_world() -> void:
	if _world_root and is_instance_valid(_world_root):
		_world_root.queue_free()
	_world_root = null
	_spawn_root = null


func _spawn_player(scene: PackedScene, id: int, spawn: Vector3) -> PlayerBase:
	var p: PlayerBase = scene.instantiate()
	p.player_id = id
	p.spawn_position = spawn
	_world_root.add_child(p)
	p.global_position = spawn
	return p


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		GameManager.toggle_pause()
		return
	# Global / debug shortcuts (F11 fullscreen anywhere; R restarts the fight in debug builds).
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F11:
				Settings.toggle_fullscreen()
			KEY_R:
				if OS.is_debug_build() and GameManager.state == GameManager.State.PLAYING:
					GameManager.start_game()


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
