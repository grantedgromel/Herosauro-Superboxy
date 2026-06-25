extends Node
## Settings (autoload singleton "Settings")
##
## Audio bus setup + player-facing options (volumes, fullscreen) with ConfigFile
## persistence. Inspired by crystal-bit/godot-game-template's ggt-core settings,
## reimplemented small and tailored to this project. Pure GDScript -> web-safe.
##
## Creates two buses ("SFX", "Music") routed to Master so the AudioManager and
## MusicManager can be mixed independently. Must initialise BEFORE those two
## autoloads (ordered first in project.godot) so the buses exist when they bind.

signal changed

const CONFIG_PATH := "user://settings.cfg"
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

var master_volume: float = 0.9
var sfx_volume: float = 0.9
var music_volume: float = 0.65
var fullscreen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(SFX_BUS)
	_ensure_bus(MUSIC_BUS)
	load_settings()
	_apply_all()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


# --- Setters (called by the options menu) ----------------------------------

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_bus("Master", master_volume)
	changed.emit()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus(SFX_BUS, sfx_volume)
	changed.emit()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_bus(MUSIC_BUS, music_volume)
	changed.emit()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()


func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)
	save_settings()


# --- Apply / persist -------------------------------------------------------

func _apply_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, -80.0 if v <= 0.001 else linear_to_db(v))


func _apply_all() -> void:
	_apply_bus("Master", master_volume)
	_apply_bus(SFX_BUS, sfx_volume)
	_apply_bus(MUSIC_BUS, music_volume)
	# Only force fullscreen if the user saved it on (don't fight the browser on web).
	if fullscreen:
		set_fullscreen(true)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(CONFIG_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
