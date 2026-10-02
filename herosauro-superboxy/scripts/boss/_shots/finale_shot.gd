extends Node
## Two frames of the finale, for eyes rather than for a gate: the dizzy stagger
## and the splash. Run windowed (it needs a renderer), one process:
##
##   xvfb-run -a -s "-screen 0 960x540x24" godot --path . \
##     --rendering-method gl_compatibility --fixed-fps 60 \
##     scripts/boss/_shots/finale_shot.tscn -- --out=/abs/dir
##
## Writes finale_stagger.png and finale_splash.png into --out (default /tmp).
## Game time is accumulated delta, so under --fixed-fps both frames are the
## same frames every run.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
## Seconds after the killing blow (game time; the hit-stop freezes delta).
const STAGGER_AT := 0.25
const SPLASH_AT := 1.72

var _out := "/tmp"
var _clock := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	GameManager.assists = false
	GameManager.companion = false
	var main := MainScene.instantiate()
	add_child(main)
	await _frames(6)
	GameManager.set_player_count(2)
	GameManager.set_human_hero(1)
	GameManager.start_game()
	await _frames(40)
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	var heroes := get_tree().get_nodes_in_group("players")
	if boss == null or heroes.size() < 2:
		push_error("finale shot: no fight")
		get_tree().quit(1)
		return
	(heroes[0] as Node3D).global_position = boss.global_position + Vector3(-7.0, 0.5, -1.5)
	(heroes[1] as Node3D).global_position = boss.global_position + Vector3(-7.0, 0.5, 1.5)
	await _frames(20)
	GameManager.damage_boss(int(GameManager.boss_health), 1)
	_clock = 0.0
	await _until(STAGGER_AT)
	await _grab("finale_stagger.png")
	await _until(SPLASH_AT)
	await _grab("finale_splash.png")
	get_tree().quit(0)


func _process(delta: float) -> void:
	_clock += delta


func _until(t: float) -> void:
	while _clock < t:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _grab(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(file)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("finale shot: %s (%s) at %.2f s" % [path, error_string(err), _clock])
