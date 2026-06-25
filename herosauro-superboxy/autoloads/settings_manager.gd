extends Node
## Settings (autoload singleton "Settings")
##
## Owns the player-facing options — audio mix, accessibility, window mode — and
## persists them to user://settings.cfg. Builds the audio bus layout
## (Master > Music + SFX) so the volume sliders have something to drive.
##
## Other systems read the live values: AudioManager routes its players to the
## SFX/Music buses, CameraRig scales screen shake by `shake_scale`, and
## GameManager skips hit-stop when `hit_stop` is off. Listed first in the autoload
## order so the buses exist before AudioManager wires its players to them.

const SAVE_PATH := "user://settings.cfg"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

signal settings_changed

var master_volume: float = 0.9
var music_volume: float = 0.55
var sfx_volume: float = 0.9
var shake_scale: float = 1.0      # accessibility: 0 = no screen shake, 1 = full
var hit_stop: bool = true         # accessibility: brief freeze-frames on big hits
var fullscreen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_settings()
	apply_all()


# --- Audio buses -----------------------------------------------------------

func _ensure_buses() -> void:
	# Master always exists (index 0). Add Music + SFX routed to it, idempotently
	# (so a fresh instance — e.g. in tests — never double-adds).
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)


func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))


func apply_all() -> void:
	_apply_bus(BUS_MASTER, master_volume)
	_apply_bus(BUS_MUSIC, music_volume)
	_apply_bus(BUS_SFX, sfx_volume)
	apply_window()
	settings_changed.emit()


func apply_window() -> void:
	# Headless has a dummy DisplayServer; these calls are safe no-ops there.
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


# --- Live setters (the options menu calls these as the player adjusts) ------

func set_master(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_bus(BUS_MASTER, master_volume)

func set_music(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_bus(BUS_MUSIC, music_volume)

func set_sfx(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus(BUS_SFX, sfx_volume)

func set_shake_scale(v: float) -> void:
	shake_scale = clampf(v, 0.0, 1.5)

func set_hit_stop(b: bool) -> void:
	hit_stop = b

func set_fullscreen(b: bool) -> void:
	fullscreen = b
	apply_window()


# --- Persistence -----------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("access", "shake_scale", shake_scale)
	cfg.set_value("access", "hit_stop", hit_stop)
	cfg.set_value("window", "fullscreen", fullscreen)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	shake_scale = float(cfg.get_value("access", "shake_scale", shake_scale))
	hit_stop = bool(cfg.get_value("access", "hit_stop", hit_stop))
	fullscreen = bool(cfg.get_value("window", "fullscreen", fullscreen))
