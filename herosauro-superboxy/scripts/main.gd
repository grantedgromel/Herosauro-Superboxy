extends Node3D
## Main: the root gameplay scene. Composes the world, camera, players, boss and
## UI at runtime and reacts to GameManager state transitions. Kept as code-driven
## composition so each sub-scene stays self-contained and independently testable.

const P1_SPAWN := Vector3(-30.0, 4.0, 0.0)
const P2_SPAWN := Vector3(-25.0, 4.0, 2.0)
const BOSS_SPAWN := Vector3(35.0, 2.0, 0.0)

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
var _spawn_root: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	add_child(WorldScene.instantiate())

	_spawn_root = Node3D.new()
	_spawn_root.name = "Spawned"
	_spawn_root.add_to_group("spawn_root")
	add_child(_spawn_root)

	var rig: Node3D = CameraRigScript.new()
	rig.name = "CameraRig"
	add_child(rig)

	_spawn_player(HerosauroScene, 1, P1_SPAWN)
	_spawn_player(SuperBoxyScene, 2, P2_SPAWN)

	var boss := AdamastorScene.instantiate()
	boss.global_position = BOSS_SPAWN
	add_child(boss)

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


func _spawn_player(scene: PackedScene, id: int, spawn: Vector3) -> void:
	var p: PlayerBase = scene.instantiate()
	p.player_id = id
	p.spawn_position = spawn
	p.global_position = spawn
	add_child(p)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		GameManager.toggle_pause()


func _on_state_changed(new_state: int) -> void:
	match new_state:
		GameManager.State.MENU:
			_menu.visible = true
			_hud.visible = false
			_game_over.visible = false
		GameManager.State.PLAYING:
			_menu.visible = false
			_hud.visible = true
			_game_over.visible = false
		GameManager.State.PAUSED:
			pass  # HUD shows its own pause overlay in response to the signal.
		GameManager.State.VICTORY, GameManager.State.DEFEAT:
			pass  # game_over UI is shown by _on_game_over.


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
