extends SceneTree
## Bakes AudioManager's procedural library to WAV files, so the game LOADS it at
## boot instead of synthesising it.
##
##   godot --headless --path . -s scripts/audio/gen/bake_synth.gd
##   godot --headless --import .
##
## The roar, the fall, the splash and the twenty-one material voices are real
## DSP written in GDScript: about half a second of a desktop CPU at every boot,
## and several times that on the web build's single WASM thread, all of it
## spent while a child looks at a frozen screen. The code stays the source of
## truth (`_build_library()` is unchanged, and is still what runs if a baked
## file is missing); this just runs it once, here, and writes the result down.
##
## `_audio_probe` rebuilds the library and compares it with these files sample
## for sample, so editing a voice without re-running this fails the build
## rather than shipping the old sound.

const OUT_DIR := "res://assets/audio/sfx/synth/"


func _init() -> void:
	var am: Node = load("res://autoloads/audio_manager.gd").new()
	am.call("_build_library")
	var lib: Dictionary = am.get("_streams")
	var keys: Array = am.call("synth_keys")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failed := 0
	var bytes := 0
	for k in keys:
		var w := lib.get(k) as AudioStreamWAV
		if w == null:
			printerr("bake: _build_library made no '%s'" % k)
			failed += 1
			continue
		var path: String = OUT_DIR + str(k) + ".wav"
		if w.save_to_wav(path) != OK:
			printerr("bake: could not write " + path)
			failed += 1
			continue
		bytes += w.data.size()
	print("bake: %d streams, %.0f KB of PCM -> %s" % [keys.size() - failed, bytes / 1024.0, OUT_DIR])
	am.free()
	quit(1 if failed > 0 else 0)
