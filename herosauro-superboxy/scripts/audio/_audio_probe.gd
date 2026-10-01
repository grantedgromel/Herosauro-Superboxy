extends Node
## Headless regression probe for AudioManager.
##
## THIS CONTAINER HAS NO AUDIO DEVICE. Godot falls back to the dummy driver, so
## nothing here can be verified by listening and nothing here tries. Every check
## MEASURES THE BUFFER: `AudioStreamWAV.data` is readable, so a synthesised
## effect's waveform can be decoded back to floats and interrogated — its peak,
## its energy, where in the stream that energy sits, how fast it decays, how
## bright it is, whether it starts or ends on a discontinuity.
##
## That matters more here than it would in another stream. Audio is the one part
## of the impact contract with no visual trace at all: a `play_*` call that
## silently resolves to nothing looks exactly like a call that worked, in the
## capture gate and in every other probe in this project. The props probe can
## only ask "did the pool get handed A stream" — it cannot ask whether that
## stream contains a sound.
##
## What it measures:
##
##   * REACHABILITY — every public play_* entry point, called for real, lands a
##     stream of non-zero length on a pooled voice. No entry point resolves to
##     silence.
##   * WAVEFORM — for every synthesised stream in the library: peak inside
##     [-1, 1], no clipped run, non-zero energy, and no click at either end.
##   * THE ROAR — length, where the crest sits against ROAR_CREST (which is the
##     boss FSM's own ROAR_WINDUP), that it BUILDS rather than bangs, that its
##     energy is where a nine-metre giant's would be, and that the 29 Hz growl is
##     actually present in the envelope. Measured with a Goertzel, not asserted.
##   * MATERIAL — that the seven surfaces are genuinely different sounds and not
##     one sound with seven names: the full ring-down / brightness / length table
##     is printed, and iron-against-wood is asserted as a ratio.
##   * THE FALL — that it is two events with a hole between them, which is what
##     makes the height legible.
##   * THE POOL under twenty simultaneous requests, both distinct and identical,
##     against the round-robin it replaces.
##   * DISTANCE attenuation, against a real Camera3D.
##   * THE MIX — bus layout, limiters, and that the pause duck and the phase-two
##     event duck compose instead of erasing each other.
##   * DETERMINISM — the library rebuilt from the same seed is byte-identical.
##
## Time is read with Time.get_ticks_usec() in one place, to report the cost of
## building the library. Probes are the documented exception to the wall-clock
## rule; nothing here animates off it.
##
##   godot --headless --path . scripts/audio/_audio_probe.tscn

## Frequencies the brightness analysis samples, log-spaced 250 Hz -> 6 kHz.
## Sixteen Goertzel bins is a coarse spectrum, but it is more than enough to
## separate a granite crack from a terracotta one and it costs one pass over the
## buffer per bin.
##
## It starts at 250 Hz to match the high-pass the ring-down uses, and for the
## same reason: below that is the body sweep every impact puts into the deck, and
## that is a property of the blow rather than of the material.
const BANDS := 16
const BAND_LO := 250.0
const BAND_HI := 6000.0

## How much of a stream the brightness analysis looks at. The attack is where the
## material identity lives; a long iron ring-down would otherwise drag every
## centroid towards its fundamental.
const ANALYSIS_WINDOW := 0.30

var _pass: int = 0
var _fail: int = 0
var _am: Node = null


func _ready() -> void:
	await get_tree().process_frame
	_am = get_node_or_null("/root/AudioManager")
	if _am == null:
		printerr("  FAIL AudioManager autoload is not present")
		get_tree().quit(1)
		return
	await _run()
	print("\naudio probe: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	# First, while the library is still the one boot loaded: every other check
	# below rebuilds it from code.
	_check_baked_library()
	_check_library_integrity()
	await _check_entry_points()
	_check_story_files()
	await _check_story_dispatch()
	_check_kid_safe()
	_check_roar()
	_check_surface_table()
	_check_surface_voices()
	_check_fall()
	await _check_pool_under_load()
	await _check_distance()
	_check_bus_layout()
	await _check_music_ducking()
	await _check_narration_duck()
	_check_volume_offsets()
	_check_determinism()


# --- Waveform tools ----------------------------------------------------------

## Decode a synthesised stream back to floats.
##
## Only FORMAT_16_BITS comes back: the SHIPPED samples import with
## `compress/mode=2`, so their `.data` is QOA frames rather than PCM and reading
## it as samples would produce confident nonsense. Those are checked for
## reachability and length instead, which is all that can honestly be said about
## them from here.
func _pcm(s: AudioStream) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var w := s as AudioStreamWAV
	if w == null or w.format != AudioStreamWAV.FORMAT_16_BITS:
		return out
	var d := w.data
	var n: int = d.size() / 2
	out.resize(n)
	for i in n:
		out[i] = float(d.decode_s16(i * 2)) / 32768.0
	return out


## RMS envelope at `window` seconds resolution.
func _envelope(pcm: PackedFloat32Array, rate: float, window: float) -> PackedFloat32Array:
	var step: int = maxi(1, int(window * rate))
	var out := PackedFloat32Array()
	out.resize(maxi(1, pcm.size() / step))
	for b in out.size():
		var acc := 0.0
		var from: int = b * step
		var to: int = mini(pcm.size(), from + step)
		for i in range(from, to):
			acc += pcm[i] * pcm[i]
		out[b] = sqrt(acc / float(maxi(1, to - from)))
	return out


## Magnitude of `hz` in `buf`, by Goertzel. One pass, two state variables, no FFT
## and no dependency — which is what makes it usable inside a probe.
func _goertzel(buf: PackedFloat32Array, hz: float, rate: float) -> float:
	var n := buf.size()
	if n < 4:
		return 0.0
	var w: float = TAU * hz / rate
	var c: float = 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for i in n:
		var s: float = buf[i] + c * s1 - s2
		s2 = s1
		s1 = s
	return sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / float(n)


## Energy-weighted mean frequency over BANDS log-spaced Goertzel bins — a
## spectral centroid, coarse but comparable between streams, which is all it is
## used for.
func _centroid(pcm: PackedFloat32Array, rate: float) -> float:
	var n: int = mini(pcm.size(), int(ANALYSIS_WINDOW * rate))
	if n < 64:
		return 0.0
	var win := pcm.slice(0, n)
	var num := 0.0
	var den := 0.0
	for b in BANDS:
		var hz: float = BAND_LO * pow(BAND_HI / BAND_LO, float(b) / float(BANDS - 1))
		var mag: float = _goertzel(win, hz, rate)
		num += mag * hz
		den += mag
	return num / maxf(1e-9, den)


## Seconds from the loudest point to 20 dB below it — the ring-down. This is the
## number that separates iron from wood and it is a property of the material, not
## of how hard the thing was hit.
func _decay_t20(pcm: PackedFloat32Array, rate: float) -> float:
	var env := _envelope(pcm, rate, 0.005)
	var peak := 0.0
	var at := 0
	for i in env.size():
		if env[i] > peak:
			peak = env[i]
			at = i
	if peak <= 0.0:
		return 0.0
	var target: float = peak * 0.1
	for i in range(at, env.size()):
		if env[i] <= target:
			return float(i - at) * 0.005
	return float(env.size() - at) * 0.005


## One-pole high-pass, on a copy.
##
## The ring-down measurement runs through this at 250 Hz, and that is not a
## detail. Every impact in the table also puts a low sweep into the deck under
## the ring — the object's mass — and on the stone surfaces that sweep is the
## longest thing in the sound. Measuring the raw envelope therefore reports
## granite as ringing longer than wood, which is the opposite of true: what is
## ringing is the deck. Above 250 Hz only the material's own modes are left.
func _hp(pcm: PackedFloat32Array, hz: float, rate: float) -> PackedFloat32Array:
	var out := pcm.duplicate()
	var k: float = clampf(1.0 - exp(-TAU * hz / rate), 0.0, 1.0)
	var y := 0.0
	for i in out.size():
		y += k * (out[i] - y)
		out[i] -= y
	return out


func _peak(pcm: PackedFloat32Array) -> float:
	var hi := 0.0
	for i in pcm.size():
		hi = maxf(hi, absf(pcm[i]))
	return hi


func _rms(pcm: PackedFloat32Array) -> float:
	var acc := 0.0
	for i in pcm.size():
		acc += pcm[i] * pcm[i]
	return sqrt(acc / float(maxi(1, pcm.size())))


## Total energy — sum of squares, NOT divided by length. How big an event is,
## rather than how dense it is.
func _energy(pcm: PackedFloat32Array) -> float:
	var acc := 0.0
	for i in pcm.size():
		acc += pcm[i] * pcm[i]
	return acc


## Longest run of samples pinned at full scale. One clipped sample is a rounding
## artefact; a RUN of them is a waveform that wanted to be louder than the format
## allows, and that is what audible distortion is.
func _clip_run(pcm: PackedFloat32Array) -> int:
	var worst := 0
	var run := 0
	for i in pcm.size():
		if absf(pcm[i]) >= 0.9999:
			run += 1
			worst = maxi(worst, run)
		else:
			run = 0
	return worst


func _synth_keys() -> Array:
	var lib: Dictionary = _am.get("_streams")
	var out: Array = []
	for k in lib:
		var w := lib[k] as AudioStreamWAV
		if w != null and w.format == AudioStreamWAV.FORMAT_16_BITS:
			out.append(str(k))
	out.sort()
	return out


# --- 1. Library integrity ----------------------------------------------------

## The claim: nothing in the library is silence, nothing in it clips, and nothing
## in it starts or ends on a step.
func _check_library_integrity() -> void:
	print("\n=== library ===")
	var lib: Dictionary = _am.get("_streams")
	var synth := _synth_keys()

	var dead: Array = []
	var clipped: Array = []
	var stepped: Array = []
	var out_of_range: Array = []
	var total_bytes := 0
	var worst_peak := 0.0

	for k in synth:
		var w: AudioStreamWAV = lib[k]
		total_bytes += w.data.size()
		var pcm := _pcm(w)
		var pk := _peak(pcm)
		worst_peak = maxf(worst_peak, pk)
		if _rms(pcm) <= 0.0005:
			dead.append(k)
		if _clip_run(pcm) > 2:
			clipped.append(k)
		if pk > 1.0:
			out_of_range.append(k)
		# The END is what matters. A stream that STARTS on a step is an attack —
		# every impact in the library deliberately begins with two milliseconds of
		# full-band click, because without it the filters' own rise time is the
		# fastest thing in the sound and the hit reads as soft. A stream that ENDS
		# on one is a click on every single play, with nothing to hide it.
		if pcm.size() > 4 and absf(pcm[pcm.size() - 1]) > 0.02:
			stepped.append(k)

	print("  -- %d synthesised streams, %d shipped, %.0f KB of generated PCM, worst peak %.3f"
		% [synth.size(), lib.size() - synth.size(), total_bytes / 1024.0, worst_peak])

	_ok(dead.is_empty(), "no synthesised stream is silence (%s)"
		% ("none dead" if dead.is_empty() else str(dead)))
	_ok(out_of_range.is_empty(), "every sample is inside [-1, 1] (%s)"
		% ("all" if out_of_range.is_empty() else str(out_of_range)))
	_ok(clipped.is_empty(), "no stream has a clipped run (%s)"
		% ("none" if clipped.is_empty() else str(clipped)))
	_ok(stepped.is_empty(), "no stream ends on a discontinuity (%s)"
		% ("none" if stepped.is_empty() else str(stepped)))

	# Every shipped sample must still resolve, or a play_* call that used to make
	# a recorded sound is silently making a synthesised one.
	var files: Dictionary = _am.get("SFX_FILES")
	var missing: Array = []
	for k in files:
		var s: AudioStream = lib.get(k)
		if s == null or s is AudioStreamWAV and (s as AudioStreamWAV).format == AudioStreamWAV.FORMAT_16_BITS:
			missing.append(k)
	_ok(missing.is_empty(),
		"all %d shipped samples imported and won over their fallback (%s)"
			% [files.size(), "all" if missing.is_empty() else str(missing)])

	# The library must not have lost a fallback either: a name in SFX_FILES whose
	# file vanished has to degrade to a blip, and the only way to know the blip is
	# still there is that _build_library made one for every one of them.
	var lib2: Dictionary = {}
	_am.call("_build_library")
	lib2 = _am.get("_streams")
	var no_fallback: Array = []
	for k in files:
		if not lib2.has(k):
			no_fallback.append(k)
	_ok(no_fallback.is_empty(),
		"every shipped name still has a procedural fallback under it (%s)"
			% ("all" if no_fallback.is_empty() else str(no_fallback)))
	# Put the shipped samples back on top.
	_am.call("_load_sfx_files")


# --- 1b. The baked library ---------------------------------------------------

## Boot loads the procedural library from `bake_synth.gd`'s files instead of
## synthesising it, and those files are exactly what the code makes today.
func _check_baked_library() -> void:
	print("\n=== baked library ===")
	var lib: Dictionary = _am.get("_streams")
	var keys: Array = _am.call("synth_keys")
	var dir: String = _am.get("SYNTH_DIR")
	var shipped: Dictionary = _am.get("SFX_FILES")

	# Boot. A key with a shipped sample shows the sample, so skip those.
	var built: Array = []
	for k in keys:
		if shipped.has(k):
			continue
		var s: AudioStream = lib.get(k)
		if s == null or not s.resource_path.begins_with(dir):
			built.append(k)
	_ok(built.is_empty(), "boot LOADED the procedural library instead of synthesising it (%s)"
		% ("all %d baked" % (keys.size() - shipped.size()) if built.is_empty()
			else "built at boot: " + str(built)))

	# The bake is current. Compared against the source WAV, sample for sample,
	# because the imported stream is QOA.
	_am.call("_build_library")
	var fresh: Dictionary = _am.get("_streams")
	var made: Array = []
	for k in fresh:
		var w := fresh[k] as AudioStreamWAV
		if w != null and w.format == AudioStreamWAV.FORMAT_16_BITS:
			made.append(str(k))
	made.sort()
	var listed: Array = keys.duplicate()
	listed.sort()
	_ok(made == listed, "synth_keys() names exactly what _build_library() makes (%d / %d)"
		% [listed.size(), made.size()])

	var stale: Array = []
	for k in keys:
		var disk := _read_wav(dir + str(k) + ".wav")
		var want := _pcm(fresh.get(k) as AudioStreamWAV)
		var have: PackedFloat32Array = disk.get("pcm", PackedFloat32Array())
		if want.is_empty() or have != want:
			stale.append(k)
	_ok(stale.is_empty(), "every baked file is sample-identical to what the code makes now (%s)"
		% ("all %d" % keys.size() if stale.is_empty()
			else "STALE, re-run scripts/audio/gen/bake_synth.gd: " + str(stale)))
	_am.call("_load_sfx_files")


# --- 2. Reachability ---------------------------------------------------------

## Call every public entry point for real and check what landed on the pool.
## A play_* that resolves to nothing is invisible everywhere else in this project.
func _check_entry_points() -> void:
	print("\n=== entry points ===")
	_am.call("stop_all_sfx")
	await get_tree().process_frame

	var simple := ["play_jump", "play_dino_fire", "play_dino_hit", "play_dash",
		"play_boss_slam", "play_boss_hit", "play_victory", "play_defeat",
		"play_hurt", "play_land", "play_rock_throw", "play_rock_impact",
		"play_super_boxy_hit", "play_boss_roar", "play_fall", "play_splash"]

	var silent: Array = []
	for m in simple:
		var name: String = m
		_am.call("stop_all_sfx")
		var before: int = _cursor()
		_am.call(name)
		if _dispatched(before) < 1 or _last_stream() == null \
				or _last_stream().get_length() <= 0.0:
			silent.append(name)
	_ok(silent.is_empty(), "all %d bare play_* entry points reach a real stream (%s)"
		% [simple.size(), "all" if silent.is_empty() else str(silent)])

	# The two surface-keyed ones, over the whole enum.
	var hit_silent: Array = []
	var break_voices: Array = []
	for s in ToonFactory.Surface.size():
		_am.call("stop_all_sfx")
		var b1: int = _cursor()
		_am.call("play_prop_hit", s)
		if _dispatched(b1) < 1 or _last_stream() == null:
			hit_silent.append(s)
		_am.call("stop_all_sfx")
		var b2: int = _cursor()
		_am.call("play_prop_break", s)
		break_voices.append(_dispatched(b2))

	_ok(hit_silent.is_empty(), "play_prop_hit reaches a stream for all %d surfaces"
		% ToonFactory.Surface.size())
	var two_each := true
	for v in break_voices:
		if int(v) < 2:
			two_each = false
	_ok(two_each,
		"play_prop_break dispatches two voices for every surface %s — the fracture "
			% str(break_voices) + "and the debris, which is what _props_probe counts")

	# The gain and pitch tables must actually REACH the material streams. They are
	# keyed `prop_hit_wood` and the tables are keyed `prop_hit`, and for a while
	# that meant all twenty-one played flat, at full level, with no variation —
	# a defect that is invisible from every angle except this one, because the
	# entries were there and simply never matched.
	_am.call("stop_all_sfx")
	var players: Array = _am.get("_players")
	var pool: int = players.size()
	var flat_gain := 0
	var flat_pitch := 0
	var seen: Array = []
	for s in ToonFactory.Surface.size():
		for i in 3:
			_am.call("stop_all_sfx")
			_am.call("_play", _am.call("_surface_key", "prop_hit", s), 0.0, Vector3.INF)
			var p: AudioStreamPlayer = players[(_cursor() - 1 + pool) % pool]
			if s == ToonFactory.Surface.WOOD:
				seen.append("%.1f dB / %.3fx" % [p.volume_db, p.pitch_scale])
			if is_equal_approx(p.volume_db, 0.0):
				flat_gain += 1
			if is_equal_approx(p.pitch_scale, 1.0):
				flat_pitch += 1
	print("  -- three wooden hits in a row: ", " | ".join(PackedStringArray(seen)))
	_ok(flat_gain == 0,
		"every material stream picks up its role's headroom (%d of %d played at 0 dB)"
			% [flat_gain, ToonFactory.Surface.size() * 3])
	_ok(flat_pitch == 0,
		"...and its role's pitch spread, so two crates in one frame are two crates "
			+ "(%d of %d played at unity)" % [flat_pitch, ToonFactory.Surface.size() * 3])

	_am.call("stop_all_sfx")
	await get_tree().process_frame


func _cursor() -> int:
	return int(_am.get("_next_player"))


func _dispatched(before: int) -> int:
	var players: Array = _am.get("_players")
	var size: int = players.size()
	if size <= 0:
		return 0
	var now := _cursor()
	if now == before:
		return 0
	return (now - before + size) % size


func _last_stream() -> AudioStream:
	var players: Array = _am.get("_players")
	if players.is_empty():
		return null
	var p: AudioStreamPlayer = _last_player()
	return p.stream if p != null else null


func _last_player() -> AudioStreamPlayer:
	var players: Array = _am.get("_players")
	if players.is_empty():
		return null
	return players[(_cursor() - 1 + players.size()) % players.size()]


# --- 2b. The storybook sounds ------------------------------------------------

## The contract, copied from docs/story/ADAPTATION.md on purpose rather than read
## back from AudioManager: a probe that asked the manager which ids it owes would
## pass a manager that quietly dropped one.
const RESERVED := ["ui_tap", "page_turn", "star", "objective_done", "bubble_pop",
	"cup_collect", "goblin_hit", "goblin_giggle", "ball_kick", "rope_snap",
	"dragon_roar", "dragon_fire", "magic_repair", "panda_cheer", "suitcase"]

## The ids that fire in bursts (every rubbish pile, every goblin, every football,
## every button) and so must not repeat themselves note for note.
const FREQUENT := ["star", "goblin_hit", "goblin_giggle", "ball_kick", "ui_tap"]

## What make_story_sfx.py promises for every file it writes.
const STORY_MAX_BYTES := 60 * 1024
const STORY_PEAK_LO_DB := -4.5
const STORY_PEAK_HI_DB := -2.0
const STORY_HF_HZ := 8000.0
## Fraction of a file's energy allowed above 8 kHz. White noise at this rate puts
## about 27% there; the generator's 4th-order low-pass leaves well under 0.1%.
const STORY_HF_MAX := 0.005


## Every reserved id resolves to a SHIPPED file, and every shipped storybook file
## is what the generator promises: mono 22 050 Hz 16-bit, small, peaking near
## -3 dBFS, nothing harsh above 8 kHz, and no click at the end. Read straight off
## the source WAV, because the imported stream is QOA and cannot be decoded here.
func _check_story_files() -> void:
	print("\n=== storybook sounds: files ===")
	var lib: Dictionary = _am.get("_streams")
	var table: Dictionary = _am.get("STORY_SFX")
	var dir: String = _am.get("SFX_DIR")

	var unresolved: Array = []
	for key in RESERVED:
		var s: AudioStream = lib.get(key)
		if not table.has(key) or s == null or s.get_length() <= 0.0 \
				or not s.resource_path.begins_with(dir):
			unresolved.append(key)
	_ok(unresolved.is_empty(), "all %d reserved ids resolve to a shipped file (%s)"
		% [RESERVED.size(), "all" if unresolved.is_empty() else "MISSING " + str(unresolved)])

	var bad_format: Array = []
	var too_big: Array = []
	var bad_peak: Array = []
	var harsh: Array = []
	var clicky: Array = []
	var files := 0
	var total := 0
	for key in table:
		for file in table[key]:
			var path: String = dir + str(file)
			var w := _read_wav(path)
			files += 1
			total += int(w.get("size", 0))
			var pcm: PackedFloat32Array = w.get("pcm", PackedFloat32Array())
			if w.get("channels", 0) != 1 or w.get("rate", 0) != 22050 \
					or w.get("bits", 0) != 16 or pcm.is_empty():
				bad_format.append(file)
				continue
			if int(w["size"]) > STORY_MAX_BYTES:
				too_big.append("%s %d KB" % [file, int(w["size"]) / 1024])
			var pk_db := linear_to_db(maxf(1e-9, _peak(pcm)))
			if pk_db < STORY_PEAK_LO_DB or pk_db > STORY_PEAK_HI_DB:
				bad_peak.append("%s %.1f dB" % [file, pk_db])
			var hf := _energy(_hp4(pcm, STORY_HF_HZ, 22050.0)) / maxf(1e-12, _energy(pcm))
			if hf > STORY_HF_MAX:
				harsh.append("%s %.2f%%" % [file, hf * 100.0])
			if absf(pcm[pcm.size() - 1]) > 0.002:
				clicky.append(file)
			print("  -- %-22s %.2f s  %5.1f KB  peak %5.1f dBFS  above 8 kHz %.3f%%"
				% [file, pcm.size() / 22050.0, int(w["size"]) / 1024.0, pk_db, hf * 100.0])
	print("  -- %d files, %.0f KB of source WAV" % [files, total / 1024.0])

	_ok(files >= RESERVED.size() and bad_format.is_empty(),
		"every storybook file is a readable mono 22 050 Hz 16-bit WAV (%s)"
			% ("all %d" % files if bad_format.is_empty() else str(bad_format)))
	_ok(too_big.is_empty(), "every file is under %d KB (%s)"
		% [STORY_MAX_BYTES / 1024, "all" if too_big.is_empty() else str(too_big)])
	_ok(bad_peak.is_empty(), "every file peaks between %.1f and %.1f dBFS — normalised, never hot (%s)"
		% [STORY_PEAK_LO_DB, STORY_PEAK_HI_DB, "all" if bad_peak.is_empty() else str(bad_peak)])
	_ok(harsh.is_empty(), "nothing harsh above 8 kHz: under %.1f%% of any file's energy (%s)"
		% [STORY_HF_MAX * 100.0, "all" if harsh.is_empty() else str(harsh)])
	_ok(clicky.is_empty(), "every file fades to silence instead of ending on a click (%s)"
		% ("all" if clicky.is_empty() else str(clicky)))


## play_sfx for real: every reserved id puts exactly one shipped stream on a
## voice, an unknown id puts nothing anywhere, and the frequent ones never play
## the same thing twice running.
func _check_story_dispatch() -> void:
	print("\n=== storybook sounds: play_sfx ===")
	var table: Dictionary = _am.get("STORY_SFX")
	var dir: String = _am.get("SFX_DIR")

	var silent: Array = []
	for key in RESERVED:
		_am.call("stop_all_sfx")
		var before := _cursor()
		_am.call("play_sfx", StringName(key))
		var s := _last_stream()
		if _dispatched(before) != 1 or s == null or not s.resource_path.begins_with(dir):
			silent.append(key)
	_ok(silent.is_empty(), "play_sfx(id) lands one shipped stream for every reserved id (%s)"
		% ("all" if silent.is_empty() else str(silent)))

	_am.call("stop_all_sfx")
	var players: Array = _am.get("_players")
	var streams_before: Array = []
	for p in players:
		streams_before.append((p as AudioStreamPlayer).stream)
	var b := _cursor()
	_am.call("play_sfx", &"no_such_sound")
	_am.call("play_sfx", &"")
	_am.call("play_sfx", &"Star")
	var touched := 0
	for i in players.size():
		if (players[i] as AudioStreamPlayer).stream != streams_before[i] \
				or (players[i] as AudioStreamPlayer).playing:
			touched += 1
	_ok(_dispatched(b) == 0 and touched == 0,
		"play_sfx on an unknown id is silent: no voice taken, nothing playing (%d dispatched, %d touched)"
			% [_dispatched(b), touched])

	# Variation. Each of these fires in bursts, and the same sample at the same
	# pitch three times in a row is the machine-gun this guards against.
	var repeats: Array = []
	var summary: Array = []
	for key in FREQUENT:
		var variants: int = (table.get(key, []) as Array).size()
		var last_stream: AudioStream = null
		var last_pitch := -1.0
		var same_variant_twice := false
		var identical_twice := false
		var seen := {}
		for k in 9:
			_am.call("stop_all_sfx")
			_am.call("play_sfx", StringName(key))
			var p := _last_player()
			if p == null:
				continue
			seen[p.stream] = true
			if variants > 1 and p.stream == last_stream:
				same_variant_twice = true
			if p.stream == last_stream and is_equal_approx(p.pitch_scale, last_pitch):
				identical_twice = true
			last_stream = p.stream
			last_pitch = p.pitch_scale
		summary.append("%s %d/%d" % [key, seen.size(), variants])
		if same_variant_twice or identical_twice or (variants > 1 and seen.size() < 2):
			repeats.append(key)
	print("  -- variants heard in nine plays: ", ", ".join(PackedStringArray(summary)))
	_ok(repeats.is_empty(),
		"the frequent ids never repeat the same variant (or the same sample at the same pitch) twice running (%s)"
			% ("none do" if repeats.is_empty() else str(repeats)))
	_am.call("stop_all_sfx")
	await get_tree().process_frame


## Kid rules 5 and 6 for the sounds that were already here. With Ajudas on a hurt
## hero says "oof", not a cry; and the Douro only exists under the bridge.
func _check_kid_safe() -> void:
	print("\n=== kid-safe ===")
	var gm := get_node_or_null("/root/GameManager")
	var lib: Dictionary = _am.get("_streams")
	if gm == null:
		_ok(false, "GameManager is present")
		return
	var was_assists: bool = gm.get("assists")
	var was_chapter: String = gm.get("chapter_id")

	var heard := func(method: String) -> AudioStream:
		_am.call("stop_all_sfx")
		_am.call(method)
		return _last_stream()

	gm.set("assists", true)
	var kid_hurt: AudioStream = heard.call("play_hurt")
	gm.set("assists", false)
	var big_hurt: AudioStream = heard.call("play_hurt")
	_ok(kid_hurt != null and kid_hurt == lib.get("hurt_soft"),
		"with Ajudas on a hurt hero plays the soft oof/boing (%s)"
			% (kid_hurt.resource_path if kid_hurt != null else "nothing"))
	_ok(big_hurt != null and big_hurt == lib.get("hurt") and big_hurt != kid_hurt,
		"...and with Ajudas off the original hurt (%s)"
			% (big_hurt.resource_path if big_hurt != null else "nothing"))

	gm.set("assists", true)
	gm.set("chapter_id", "adamastor")
	var bridge: AudioStream = heard.call("play_fall")
	var elsewhere: Array = []
	for ch in ["dragao", "pandas"]:
		gm.set("chapter_id", ch)
		elsewhere.append(heard.call("play_fall"))
	_ok(bridge != null and bridge == lib.get("fall"),
		"falling off the BRIDGE still ends in the Douro splash")
	var light := true
	for s in elsewhere:
		if s == null or s != lib.get("fall_whoosh") or s == bridge \
				or s.get_length() >= (bridge.get_length() if bridge != null else 0.0):
			light = false
	_ok(light, "...and anywhere else it is a light whoosh, shorter and with no river in it (%s)"
		% str(elsewhere.map(func(s: AudioStream) -> String:
			return s.resource_path.get_file() if s != null else "nothing")))

	gm.set("assists", was_assists)
	gm.set("chapter_id", was_chapter)
	_am.call("stop_all_sfx")


## A minimal RIFF reader: the fmt fields and the PCM, or as much as is there.
func _read_wav(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var bytes := f.get_buffer(f.get_length())
	out["size"] = bytes.size()
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return out
	var p := 12
	while p + 8 <= bytes.size():
		var id := bytes.slice(p, p + 4).get_string_from_ascii()
		var n: int = bytes.decode_u32(p + 4)
		var body := p + 8
		if id == "fmt " and body + 16 <= bytes.size():
			out["channels"] = bytes.decode_u16(body + 2)
			out["rate"] = bytes.decode_u32(body + 4)
			out["bits"] = bytes.decode_u16(body + 14)
		elif id == "data":
			var count: int = mini(n, bytes.size() - body) / 2
			var pcm := PackedFloat32Array()
			pcm.resize(count)
			for i in count:
				pcm[i] = float(bytes.decode_s16(body + i * 2)) / 32768.0
			out["pcm"] = pcm
		p = body + n + (n & 1)
	return out


## 4th-order Butterworth high-pass (two RBJ biquads), for "how much is up there".
func _hp4(pcm: PackedFloat32Array, hz: float, rate: float) -> PackedFloat32Array:
	return _biquad_hp(_biquad_hp(pcm, hz, 0.5412, rate), hz, 1.3066, rate)


func _biquad_hp(x: PackedFloat32Array, hz: float, q: float, rate: float) -> PackedFloat32Array:
	var w := TAU * hz / rate
	var cw := cos(w)
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := (1.0 + cw) / 2.0 / a0
	var b1 := -(1.0 + cw) / a0
	var b2 := b0
	var a1 := -2.0 * cw / a0
	var a2 := (1.0 - alpha) / a0
	var out := PackedFloat32Array()
	out.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var y := b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = y
		out[i] = y
	return out


# --- 3. The roar -------------------------------------------------------------

## The one sound in the game that has to carry a whole phase of the fight on its
## own. Everything asserted here is a property of the waveform.
func _check_roar() -> void:
	print("\n=== the roar ===")
	var lib: Dictionary = _am.get("_streams")
	var w: AudioStreamWAV = lib.get("boss_roar")
	if w == null:
		_ok(false, "boss_roar exists in the library")
		return
	var rate := float(w.mix_rate)
	var pcm := _pcm(w)
	var length: float = float(pcm.size()) / rate
	var crest: float = float(_am.get("ROAR_CREST"))

	var env := _envelope(pcm, rate, 0.010)
	var peak_at := 0
	var peak := 0.0
	for i in env.size():
		if env[i] > peak:
			peak = env[i]
			peak_at = i
	var peak_t: float = float(peak_at) * 0.010

	# Level at the quarter points, as a fraction of the crest.
	var at := func(t: float) -> float:
		var i: int = clampi(int(t / 0.010), 0, env.size() - 1)
		return env[i] / maxf(1e-9, peak)

	print("  -- roar: %.2f s, peak %.3f, crest at %.2f s (ROAR_CREST %.2f), "
		% [length, _peak(pcm), peak_t, crest]
		+ "levels 0.2s %.2f / 0.5s %.2f / crest 1.00 / +0.5s %.2f / +1.2s %.2f"
			% [at.call(0.20), at.call(0.50), at.call(crest + 0.5), at.call(crest + 1.2)])

	_ok(length > 2.0 and length < 3.0,
		"it is %.2f s long — long enough to be an event, short enough not to sit "
			% length + "under the next attack")
	_ok(absf(peak_t - crest) < 0.20,
		"its crest lands at %.2f s, within 200 ms of ROAR_CREST %.2f — which is the "
			% [peak_t, crest] + "boss FSM's own ROAR_WINDUP, so the shockwave leaves "
			+ "his feet on the loudest frame")
	_ok(at.call(0.20) < 0.55 and at.call(0.50) > at.call(0.20),
		"it BUILDS: %.2f of crest at 0.2 s rising to %.2f at 0.5 s. A roar that "
			% [at.call(0.20), at.call(0.50)] + "starts at full volume is a slam")
	_ok(at.call(crest + 1.2) < 0.30,
		"...and falls away to %.2f of crest 1.2 s later" % at.call(crest + 1.2))

	# Spectrum at the crest. A nine-metre giant lives underneath everything else
	# in the mix — but a roar that is ONLY sub is a rumble, and a rumble does not
	# survive a laptop speaker, a phone or a crossfade into the phase-two track.
	# The formant region is what carries it there.
	var win := pcm.slice(int(crest * rate), int(minf(length, crest + 0.45) * rate))
	var sub: float = _goertzel(win, 55.0, rate)
	var f1: float = _goertzel(win, 220.0, rate)
	var f1b: float = _goertzel(win, 300.0, rate)
	var f2: float = _goertzel(win, 600.0, rate)
	var mid: float = _goertzel(win, 900.0, rate)
	var hi: float = _goertzel(win, 2400.0, rate)
	var formants: float = f1 + f1b + f2 + mid
	print("  -- crest spectrum: 55 Hz %.4f | 220 %.4f  300 %.4f  600 %.4f  900 %.4f "
		% [sub, f1, f1b, f2, mid] + "| 2.4 kHz %.4f  (formant sum %.4f)" % [hi, formants])
	_ok(formants > sub,
		"the formant region 220-900 Hz (%.4f summed) outweighs the 55 Hz sub (%.4f) "
			% [formants, sub] + "— it is a voice with a giant under it, not a giant "
			+ "with a voice somewhere in it")
	_ok(mid > f1b * 0.10 and hi > 0.0001,
		"and it reaches up: 900 Hz is %.0f%% of 300 Hz and there is still %.4f at "
			% [100.0 * mid / maxf(1e-9, f1b), hi] + "2.4 kHz, which is the rasp band")

	# The growl. A 29 Hz amplitude modulation is what makes a filtered pulse train
	# read as a throat; without it the same synthesis is a foghorn. Measured on
	# the envelope itself, at 1 ms resolution.
	var fine := _envelope(pcm.slice(int((crest - 0.25) * rate), int((crest + 0.25) * rate)),
		rate, 0.001)
	var mean := 0.0
	for i in fine.size():
		mean += fine[i]
	mean /= float(maxi(1, fine.size()))
	for i in fine.size():
		fine[i] -= mean
	var growl: float = _goertzel(fine, 29.0, 1000.0)
	var away: float = _goertzel(fine, 7.0, 1000.0)
	print("  -- envelope modulation around the crest: 29 Hz %.5f, 7 Hz %.5f, mean level %.4f"
		% [growl, away, mean])
	_ok(growl / maxf(1e-9, mean) > 0.02,
		"the 29 Hz growl is %.1f%% of the mean envelope — the chest rattle is really "
			% (100.0 * growl / maxf(1e-9, mean)) + "in the waveform")
	_ok(growl > away,
		"...and it is stronger at 29 Hz (%.5f) than at 7 Hz (%.5f), so it is a growl "
			% [growl, away] + "and not a slow tremolo")

	# It must not be the slam it replaces — which is exactly what the moment used
	# to play, and the reason this whole entry point exists.
	var slam: AudioStream = lib.get("boss_slam")
	var files: Dictionary = _am.get("SFX_FILES")
	_ok(slam != null and w != slam,
		"boss_roar (%.2f s, synthesised) is a different resource from boss_slam "
			% w.get_length() + "(%.2f s, the shipped sample the phase flip borrowed)"
			% (slam.get_length() if slam != null else -1.0))
	_ok(not files.has("boss_roar"),
		"...and it is not a re-pointed sample either — there is no roar file in the "
			+ "project and none was invented")


# --- 4. The surface contract -------------------------------------------------

## The table half: every value of the enum has a case, and the case it has is its
## own. Exactly what `_fx_probe` asserts of `ImpactFX.impact_row()`.
func _check_surface_table() -> void:
	print("\n=== surface contract ===")
	var wrong: Array = []
	var required := ["modes", "noise", "noise_hz", "noise_q", "noise_decay",
		"body", "body_hz", "body_decay", "hit_dur", "break_dur", "break_drop",
		"grains", "grain_spread", "grain_hz", "grain_decay", "tail_dur"]
	var incomplete: Array = []
	for s in ToonFactory.Surface.size():
		var row: Dictionary = _am.call("surface_voice", s)
		if int(row.get("surface", -1)) != s:
			wrong.append(s)
		for f in required:
			if not row.has(f):
				incomplete.append("%d.%s" % [s, f])
	_ok(wrong.is_empty(),
		"surface_voice(s)['surface'] == s for all %d surfaces — no silent default"
			% ToonFactory.Surface.size())
	_ok(incomplete.is_empty(), "every row carries all %d fields (%s)"
		% [required.size(), "complete" if incomplete.is_empty() else str(incomplete)])

	# Keys are derived from the enum, so a renamed surface renames its streams.
	var lib: Dictionary = _am.get("_streams")
	var absent: Array = []
	for s in ToonFactory.Surface.size():
		for role in ["prop_hit", "prop_break", "prop_debris"]:
			var k: String = _am.call("_surface_key", role, s)
			if not lib.has(k):
				absent.append(k)
	_ok(absent.is_empty(), "all %d material streams are in the library (%s)"
		% [ToonFactory.Surface.size() * 3, "all" if absent.is_empty() else str(absent)])


## The audible half: the seven surfaces are seven different sounds.
##
## This is the check the props stream's request was really about. Routing wood to
## `land` and granite to `rock_impact` was already "two different samples"; what
## it was not was two different MATERIALS, and the difference between those is
## measurable — ring-down and brightness, printed here for all seven.
func _check_surface_voices() -> void:
	print("\n=== material voices ===")
	var lib: Dictionary = _am.get("_streams")
	var names: Array = ToonFactory.Surface.keys()

	var t20: Dictionary = {}
	var cen: Dictionary = {}
	print("  %-12s %8s %9s %9s %9s %9s"
		% ["surface", "hit s", "ring>250", "centroid", "break s", "tail s"])
	for s in ToonFactory.Surface.size():
		var hit: AudioStreamWAV = lib[_am.call("_surface_key", "prop_hit", s)]
		var brk: AudioStreamWAV = lib[_am.call("_surface_key", "prop_break", s)]
		var deb: AudioStreamWAV = lib[_am.call("_surface_key", "prop_debris", s)]
		var pcm := _pcm(hit)
		var rate := float(hit.mix_rate)
		# Both measured above 250 Hz, and for the same reason: below that is the
		# body sweep every surface puts into the deck, which is a property of the
		# blow rather than of the material. Left in, it dragged cobble's centroid
		# BELOW granite's — the opposite of the table, and an artefact.
		var ring := _hp(pcm, 250.0, rate)
		t20[s] = _decay_t20(ring, rate)
		cen[s] = _centroid(ring, rate)
		print("  %-12s %8.3f %9.3f %8.0fHz %9.3f %9.3f"
			% [str(names[s]).to_lower(), hit.get_length(), float(t20[s]), float(cen[s]),
				brk.get_length(), deb.get_length()])

	# Distinctness, pairwise. Two surfaces are allowed to be similar; none may be
	# the same sound. Compared as RATIOS rather than differences, because a 40 ms
	# gap between two 50 ms rings is an enormous difference and the same 40 ms
	# between two 400 ms rings is not.
	var same: Array = []
	var worst := 99.0
	var worst_pair := ""
	for a in ToonFactory.Surface.size():
		for b in range(a + 1, ToonFactory.Surface.size()):
			var rt: float = maxf(float(t20[a]), float(t20[b])) \
				/ maxf(1e-6, minf(float(t20[a]), float(t20[b])))
			var rc: float = maxf(float(cen[a]), float(cen[b])) \
				/ maxf(1e-6, minf(float(cen[a]), float(cen[b])))
			var sep: float = maxf(rt, rc)
			if sep < worst:
				worst = sep
				worst_pair = "%s/%s" % [str(names[a]).to_lower(), str(names[b]).to_lower()]
			if sep < 1.15:
				same.append("%s/%s" % [str(names[a]).to_lower(), str(names[b]).to_lower()])
	_ok(same.is_empty(),
		"all %d surface pairs are at least 15%% apart on ring-down or brightness "
			% (ToonFactory.Surface.size() * (ToonFactory.Surface.size() - 1) / 2)
			+ "(closest %s at %.0f%%%s)"
			% [worst_pair, (worst - 1.0) * 100.0,
				"" if same.is_empty() else "; too close: " + str(same)])

	var iron: float = float(t20[ToonFactory.Surface.IRON])
	var wood: float = float(t20[ToonFactory.Surface.WOOD])
	var plaster: float = float(t20[ToonFactory.Surface.PLASTER])
	var granite: float = float(t20[ToonFactory.Surface.GRANITE])
	_ok(iron > wood * 3.0,
		"iron rings %.3f s against wood's %.3f s — %.1fx, and it is that ratio a "
			% [iron, wood, iron / maxf(1e-6, wood)] + "player hears as 'metal'")
	_ok(plaster < wood and granite < wood,
		"plaster (%.3f s) and granite (%.3f s) are both deader than wood (%.3f s) — "
			% [plaster, granite, wood] + "limewash and stone do not ring, timber does")
	_ok(float(cen[ToonFactory.Surface.TERRACOTTA]) > float(cen[ToonFactory.Surface.GRANITE]),
		"terracotta (%.0f Hz) is brighter than granite (%.0f Hz)"
			% [float(cen[ToonFactory.Surface.TERRACOTTA]), float(cen[ToonFactory.Surface.GRANITE])])

	# A break must be a bigger event than a hit, on every surface, or the props
	# stream's two-tier destruction model has no audio counterpart.
	#
	# Compared against BOTH VOICES a break dispatches, because both of them play:
	# the fracture alone is only part of the event, and on the deadest materials
	# it is the smaller part — plaster's fracture is 1.1x its knock while plaster's
	# fracture plus the limewash coming down is 2.6x it.
	#
	# ENERGY, not RMS. A break is longer as well as louder and RMS divides by
	# length, so measured that way a stretched-out fracture reports as quieter
	# than the knock it is twice the size of — an artefact of the metric.
	var not_bigger: Array = []
	var ratios: Array = []
	for s in ToonFactory.Surface.size():
		var hit: AudioStreamWAV = lib[_am.call("_surface_key", "prop_hit", s)]
		var brk: AudioStreamWAV = lib[_am.call("_surface_key", "prop_break", s)]
		var deb: AudioStreamWAV = lib[_am.call("_surface_key", "prop_debris", s)]
		var he: float = _energy(_pcm(hit))
		var be: float = _energy(_pcm(brk)) + _energy(_pcm(deb))
		var r: float = be / maxf(1e-9, he)
		ratios.append("%s %.1fx" % [str(names[s]).to_lower(), r])
		if brk.get_length() <= hit.get_length() or r < 1.5:
			not_bigger.append("%s(%.2fx)" % [str(names[s]).to_lower(), r])
	print("  -- destruction against survival, by energy: ", " | ".join(PackedStringArray(ratios)))
	_ok(not_bigger.is_empty(),
		"a break is longer than a hit and carries at least half again its energy on "
			+ "every surface (%s)" % ("all" if not_bigger.is_empty() else str(not_bigger)))

	# The debris tail must actually be debris — many separate arrivals, not one
	# smear. Counted as peaks in the 5 ms envelope.
	var flat_tails: Array = []
	for s in ToonFactory.Surface.size():
		var deb: AudioStreamWAV = lib[_am.call("_surface_key", "prop_debris", s)]
		var env := _envelope(_pcm(deb), float(deb.mix_rate), 0.005)
		var hi := 0.0
		for i in env.size():
			hi = maxf(hi, env[i])
		var arrivals := 0
		for i in range(1, env.size() - 1):
			if env[i] > env[i - 1] and env[i] >= env[i + 1] and env[i] > hi * 0.08:
				arrivals += 1
		if arrivals < 5:
			flat_tails.append("%s:%d" % [str(names[s]).to_lower(), arrivals])
	_ok(flat_tails.is_empty(),
		"every debris tail has five or more separate arrivals in it (%s)"
			% ("all" if flat_tails.is_empty() else str(flat_tails)))


# --- 5. The fall -------------------------------------------------------------

## Two events with a hole between them. The hole is what makes the drop read as
## twenty metres rather than as a stumble.
func _check_fall() -> void:
	print("\n=== going over the side ===")
	var lib: Dictionary = _am.get("_streams")
	var w: AudioStreamWAV = lib.get("fall")
	if w == null:
		_ok(false, "fall exists in the library")
		return
	var rate := float(w.mix_rate)
	var pcm := _pcm(w)
	var env := _envelope(pcm, rate, 0.010)
	var splash_at: float = float(_am.get("FALL_SPLASH_AT"))

	var hi := 0.0
	for i in env.size():
		hi = maxf(hi, env[i])
	var at := func(t: float) -> float:
		var i: int = clampi(int(t / 0.010), 0, env.size() - 1)
		return env[i] / maxf(1e-9, hi)

	# The quietest point in the 120 ms leading up to the water.
	var gap := 1.0
	var gap_t := 0.0
	for i in range(maxi(0, int((splash_at - 0.12) / 0.010)), int(splash_at / 0.010)):
		if i < env.size() and env[i] / maxf(1e-9, hi) < gap:
			gap = env[i] / maxf(1e-9, hi)
			gap_t = float(i) * 0.010

	print("  -- fall: %.2f s. levels 0.05s %.2f / 0.30s %.2f / gap %.3f at %.2f s / "
		% [w.get_length(), at.call(0.05), at.call(0.30), gap, gap_t]
		+ "impact %.2f / +0.4s %.2f" % [at.call(splash_at + 0.02), at.call(splash_at + 0.4)])

	_ok(at.call(0.05) > 0.10, "the drop is audible from 50 ms in (%.2f of peak)" % at.call(0.05))
	_ok(at.call(0.30) < at.call(0.05),
		"...and RECEDES: %.2f at 0.30 s against %.2f at 0.05 s, which is the distance "
			% [at.call(0.30), at.call(0.05)] + "cue — pitch alone does not carry it")
	_ok(gap < at.call(0.05) * 0.6,
		"there is a real hole before the water (%.3f of peak at %.2f s) — without it "
			% [gap, gap_t] + "the fall and the landing smear into one noise")
	_ok(at.call(splash_at + 0.02) > 0.75,
		"the river is the loudest thing in it (%.2f of peak just after impact)"
			% at.call(splash_at + 0.02))
	_ok(at.call(splash_at + 0.4) > 0.02 and at.call(splash_at + 0.4) < 0.5,
		"...and it leaves foam behind rather than stopping dead (%.2f of peak 400 ms on)"
			% at.call(splash_at + 0.4))

	# The splash on its own must be the water and none of the whistle.
	var sp: AudioStreamWAV = lib.get("splash")
	_ok(sp != null and sp.get_length() < w.get_length(),
		"play_splash is the water alone (%.2f s against the fall's %.2f s)"
			% [sp.get_length() if sp != null else -1.0, w.get_length()])


# --- 6. The pool under load --------------------------------------------------

## Twenty voices asked for in one frame, which is what twelve props bursting
## actually costs, and what the old fixed round-robin could not survive.
func _check_pool_under_load() -> void:
	print("\n=== the pool under twenty requests in one frame ===")
	var players: Array = _am.get("_players")
	var pool: int = players.size()
	var lib: Dictionary = _am.get("_streams")

	# (a) Round-robin is preserved when the pool is NOT under pressure. The props
	# probe reads `_next_player` as its only "a transient fired" observable, so
	# this is a contract now whether it meant to be or not.
	_am.call("stop_all_sfx")
	await get_tree().process_frame
	var keys := _synth_keys()
	var start := _cursor()
	var used: Dictionary = {}
	for i in pool:
		_am.call("_play", keys[i], 0.0, Vector3.INF)
		used[(start + i) % pool] = true
	_ok(_cursor() == start and used.size() == pool,
		"%d distinct sounds into a %d-voice pool used every voice exactly once and "
			% [pool, pool] + "left the cursor where it started")

	# (b) Four more, with the pool completely full. The four evicted must be the
	# four with least left to play — NOT the four that were asked for first, which
	# is what a fixed round-robin would have taken.
	var before_until := PackedFloat32Array(_am.get("_voice_until"))
	var live_before: Array = []
	for i in pool:
		live_before.append((players[i] as AudioStreamPlayer).stream)
	# The four longest streams in the library, so a stolen voice is never the next
	# one stolen and the eviction order is unambiguous.
	var by_len := keys.duplicate()
	by_len.sort_custom(func(a: String, b: String) -> bool:
		return (lib[a] as AudioStream).get_length() > (lib[b] as AudioStream).get_length())
	var extra: Array = []
	for k in by_len:
		if not used.has(k) and live_before.find(lib[k]) < 0:
			extra.append(k)
		if extra.size() >= 4:
			break
	for k in extra:
		_am.call("_play", k, 0.0, Vector3.INF)

	var evicted: Array = []
	var survivors: Array = []
	for i in pool:
		var s: AudioStream = live_before[i]
		var still := false
		for j in pool:
			if (players[j] as AudioStreamPlayer).stream == s:
				still = true
		if still:
			survivors.append(before_until[i])
		else:
			evicted.append(before_until[i])

	var occupied := 0
	for i in pool:
		if (players[i] as AudioStreamPlayer).stream != null:
			occupied += 1

	var ev_mean := 0.0
	for v in evicted:
		ev_mean += float(v)
	ev_mean /= float(maxi(1, evicted.size()))
	var sv_mean := 0.0
	for v in survivors:
		sv_mean += float(v)
	sv_mean /= float(maxi(1, survivors.size()))

	print("  -- 20 distinct sounds, %d voices: %d occupied, %d evicted. "
		% [pool, occupied, evicted.size()]
		+ "mean free-at of evicted %.3f s vs survivors %.3f s" % [ev_mean, sv_mean])
	_ok(occupied == pool, "every voice is carrying a sound (%d/%d)" % [occupied, pool])
	_ok(evicted.size() == 4, "exactly four were displaced (%d)" % evicted.size())
	_ok(ev_mean < sv_mean,
		"the allocator took the voices CLOSEST TO FINISHING (%.3f s of audio left "
			% ev_mean + "on average, against %.3f s for the ones it left alone). "
			% sv_mean + "Round-robin would have cut the four oldest whatever was in them")

	# (c) Twelve identical crates. The stacking limit is the reason this does not
	# become +21 dB of perfectly correlated transient.
	_am.call("stop_all_sfx")
	await get_tree().process_frame
	var key: String = _am.call("_surface_key", "prop_break", ToonFactory.Surface.WOOD)
	var b := _cursor()
	var levels: Array = []
	var shown: Array = []
	for i in 20:
		var c := _cursor()
		_am.call("_play", key, 0.0, Vector3.INF)
		if _cursor() != c:
			var db: float = (players[(_cursor() - 1 + pool) % pool] as AudioStreamPlayer).volume_db
			levels.append(db)
			shown.append("%.1f" % db)
	var stack_max: int = int(_am.get("SFX_STACK_MAX"))
	print("  -- the same fracture asked for 20 times in one frame: %d voices at %s dB"
		% [_dispatched(b), " / ".join(PackedStringArray(shown))])
	_ok(_dispatched(b) == stack_max,
		"exactly SFX_STACK_MAX (%d) voices were spent; the other %d were refused"
			% [stack_max, 20 - stack_max])
	var descending := levels.size() >= 2
	for i in range(1, levels.size()):
		if float(levels[i]) >= float(levels[i - 1]):
			descending = false
	_ok(descending,
		"...and each one is quieter than the last (%s dB), so three crates sum to "
			% " / ".join(PackedStringArray(shown))
			+ "about 2.5 dB over one instead of twenty-one")

	# (d) And the window opens again, or a sustained fight would go quiet.
	_am.call("set", "_clock", float(_am.get("_clock")) + 1.0)
	var b2 := _cursor()
	_am.call("_play", key, 0.0, Vector3.INF)
	_ok(_dispatched(b2) == 1,
		"a second later the same sound plays at full level again — the limit is a "
			+ "retrigger window, not a mute")

	_am.call("stop_all_sfx")
	await get_tree().process_frame


# --- 7. Distance -------------------------------------------------------------

## A prop smashed at the far abutment must not arrive at the same level as one
## under the camera. Measured against a real Camera3D, because that is what the
## implementation reads.
func _check_distance() -> void:
	print("\n=== distance ===")
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3.ZERO
	await get_tree().process_frame

	var ref: float = float(_am.get("SFX_REF_DIST"))
	var floor_db: float = float(_am.get("SFX_MIN_DB"))
	var rows: Array = []
	for d in [0.0, ref * 0.5, ref, ref * 2.0, ref * 4.0, 400.0]:
		var db: float = _am.call("_distance_db", Vector3(float(d), 0.0, 0.0))
		rows.append("%.0fm %.1fdB" % [float(d), db])
	print("  -- ", " | ".join(PackedStringArray(rows)))

	_ok(is_equal_approx(float(_am.call("_distance_db", Vector3(ref * 0.5, 0.0, 0.0))), 0.0),
		"inside the reference distance (%.0f m) nothing is attenuated — the mix must "
			% ref + "not wobble as the pair walk about the framed fight")
	var two: float = _am.call("_distance_db", Vector3(ref * 2.0, 0.0, 0.0))
	_ok(absf(two + 6.0) < 0.5, "one doubling past it costs %.1f dB" % two)
	var four: float = _am.call("_distance_db", Vector3(ref * 4.0, 0.0, 0.0))
	_ok(absf(four + 12.0) < 0.5, "two doublings cost %.1f dB" % four)
	_ok(is_equal_approx(float(_am.call("_distance_db", Vector3(4000.0, 0.0, 0.0))), floor_db),
		"and it bottoms out at %.1f dB rather than vanishing" % floor_db)
	_ok(is_equal_approx(float(_am.call("_distance_db", Vector3.INF)), 0.0),
		"a caller that does not know where the sound happened gets it flat")

	cam.queue_free()
	await get_tree().process_frame


# --- 8. The mix --------------------------------------------------------------

func _check_bus_layout() -> void:
	print("\n=== buses ===")
	var names: Array = []
	for i in AudioServer.bus_count:
		names.append("%s(%.1f dB, %d fx)"
			% [AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i),
				AudioServer.get_bus_effect_count(i)])
	print("  -- ", " | ".join(PackedStringArray(names)))

	var sfx := AudioServer.get_bus_index("SFX")
	var music := AudioServer.get_bus_index("Music")
	var master := AudioServer.get_bus_index("Master")
	_ok(sfx >= 0 and music >= 0 and master >= 0, "Master / Music / SFX all exist")

	# The limiter is the answer to twenty transients in one frame that the voice
	# budget cannot give on its own — four different materials breaking at once
	# are four different sounds and none of them stacks with the others.
	var lim := AudioServer.get_bus_effect(sfx, 0) as AudioEffectHardLimiter
	_ok(lim != null, "the SFX bus carries a hard limiter")
	if lim != null:
		_ok(lim.ceiling_db < 0.0 and lim.ceiling_db > -3.0,
			"...ceiling %.1f dBFS, which leaves the Master something to work with"
				% lim.ceiling_db)
	var mlim := AudioServer.get_bus_effect(master, 0) as AudioEffectHardLimiter
	_ok(mlim != null and mlim.ceiling_db < 0.0,
		"the Master carries a safety limiter (%.1f dBFS)"
			% (mlim.ceiling_db if mlim != null else 99.0))


## The phase-two moment. The roar and a 2.2 s crossfade into battle_phase2 are
## triggered by the same signal on the same frame, and the brief's question was
## whether phase two lands WITH the roar or fights it.
func _check_music_ducking() -> void:
	print("\n=== phase two ===")
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		_ok(false, "GameManager is present")
		return

	# The wiring, first. A duck that works is no use if nothing calls it.
	var wired := 0
	for sig in ["state_changed", "game_started", "boss_phase_changed", "game_over"]:
		for c in (gm.get(sig) as Signal).get_connections():
			if (c["callable"] as Callable).get_object() == _am:
				wired += 1
	_ok(wired == 4, "AudioManager is on all four GameManager signals (%d)" % wired)

	var bus := AudioServer.get_bus_index("Music")
	var base: float = float(_am.get("_music_base_db"))

	_am.call("_set_event_duck", 0.0)
	_am.call("_set_pause_duck", 0.0)
	var flat := AudioServer.get_bus_volume_db(bus)

	_am.call("_on_boss_phase_changed", 2)
	# Past the 120 ms attack and inside the hold. Waited in SECONDS, not frames:
	# headless with no fps cap draws as fast as it can, so a frame count measures
	# the machine and every fade in AudioManager is specified in seconds.
	await _wait(0.45)
	var ducked := AudioServer.get_bus_volume_db(bus)

	# Now pause on top of it. The two used to write the bus directly and erase
	# each other; unpausing mid-roar lifted the roar's duck with it.
	_am.call("_duck_pause", true)
	await _wait(0.45)
	var both := AudioServer.get_bus_volume_db(bus)
	_am.call("_duck_pause", false)
	await _wait(0.45)
	var after_resume := AudioServer.get_bus_volume_db(bus)

	print("  -- Music bus: base %.1f, flat %.1f, roar duck %.1f, +pause %.1f, resumed %.1f dB"
		% [base, flat, ducked, both, after_resume])

	var depth: float = float(_am.get("PHASE2_DUCK_DB"))
	_ok(ducked < flat - 4.0,
		"the roar pulls the soundtrack down %.1f dB (asking for %.1f), so the bellow "
			% [ducked - flat, depth] + "owns the frame instead of sharing it")
	_ok(both < ducked - 4.0,
		"pausing DURING the roar ducks further (%.1f dB), it does not replace it"
			% (both - ducked))
	_ok(after_resume < flat - 2.0,
		"and un-pausing gives back only the pause duck (%.1f dB), leaving the roar's "
			% (after_resume - flat) + "own duck in flight — the two compose")

	_ok(_am.get("_music_track") == "battle_phase2",
		"phase two is the track that is playing (%s)" % str(_am.get("_music_track")))

	# Let the event duck run out so the probe leaves the mix where it found it.
	# 0.12 attack + 0.95 hold + 1.30 release = 2.37 s from the phase flip; 1.35 s
	# of that has already gone by above.
	await _wait(1.6)
	print("  -- after the release: %.1f dB" % AudioServer.get_bus_volume_db(bus))
	_ok(absf(AudioServer.get_bus_volume_db(bus) - flat) < 0.5,
		"the duck releases fully rather than leaving the soundtrack quiet for the "
			+ "rest of the fight")


## Narration first. duck_music(true/false) is what the Narrator calls around a
## spoken page; it must pull the soundtrack well down, survive the pause menu
## opening and closing over it, and give everything back afterwards.
func _check_narration_duck() -> void:
	print("\n=== narration ===")
	var bus := AudioServer.get_bus_index("Music")
	_am.call("duck_music", false)
	_am.call("_duck_pause", false)
	await _wait(1.0)
	_am.call("_set_event_duck", 0.0)
	_am.call("_set_pause_duck", 0.0)
	_am.call("_set_voice_duck", 0.0)
	var flat := AudioServer.get_bus_volume_db(bus)

	_am.call("duck_music", true)
	await _wait(0.35)
	var spoken := AudioServer.get_bus_volume_db(bus)
	_am.call("duck_music", true)   # said twice: still one duck
	await _wait(0.1)
	var twice := AudioServer.get_bus_volume_db(bus)
	_am.call("_duck_pause", true)
	await _wait(0.45)
	var paused := AudioServer.get_bus_volume_db(bus)
	_am.call("_duck_pause", false)
	await _wait(0.45)
	var resumed := AudioServer.get_bus_volume_db(bus)
	_am.call("duck_music", false)
	await _wait(1.0)
	var after := AudioServer.get_bus_volume_db(bus)
	print("  -- Music bus: flat %.1f, speaking %.1f, said twice %.1f, +pause %.1f, resumed %.1f, after %.1f dB"
		% [flat, spoken, twice, paused, resumed, after])

	_ok(spoken <= flat - 6.0, "narration ducks the soundtrack %.1f dB within 350 ms" % (spoken - flat))
	_ok(absf(twice - spoken) < 0.5, "duck_music(true) twice is still one duck (%.1f dB)" % (twice - flat))
	_ok(paused < spoken - 4.0 and absf(resumed - spoken) < 1.0,
		"the pause menu over a voice ducks further (%.1f) and un-pausing leaves the voice's duck alone (%.1f)"
			% [paused - flat, resumed - flat])
	_ok(absf(after - flat) < 0.5, "duck_music(false) gives the soundtrack back fully (%.1f dB)"
		% (after - flat))


## The player's volume settings are offsets from the mix, not replacements for it:
## GameManager hands over 0 dB for "full", and that must still leave the music
## UNDER the effects.
func _check_volume_offsets() -> void:
	print("\n=== volume settings ===")
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	var music_mix: float = float(_am.get("_music_mix_db"))
	var sfx_mix: float = float(_am.get("_sfx_mix_db"))
	var gm := get_node_or_null("/root/GameManager")
	_am.call("_set_event_duck", 0.0)
	_am.call("_set_pause_duck", 0.0)
	_am.call("_set_voice_duck", 0.0)

	_am.call("set_music_volume_db", 0.0)
	_am.call("set_sfx_volume_db", 0.0)
	var m_full := AudioServer.get_bus_volume_db(music)
	var s_full := AudioServer.get_bus_volume_db(sfx)
	_am.call("set_music_volume_db", -6.0)
	_am.call("set_sfx_volume_db", -6.0)
	var m_half := AudioServer.get_bus_volume_db(music)
	var s_half := AudioServer.get_bus_volume_db(sfx)
	print("  -- mix trims: Music %.1f, SFX %.1f dB. Full: %.1f / %.1f. Slider -6: %.1f / %.1f"
		% [music_mix, sfx_mix, m_full, s_full, m_half, s_half])

	_ok(absf(m_full - music_mix) < 0.01 and absf(s_full - sfx_mix) < 0.01,
		"full volume (0 dB from GameManager) keeps the mix's own bus trims")
	_ok(absf(m_half - (music_mix - 6.0)) < 0.01 and absf(s_half - (sfx_mix - 6.0)) < 0.01,
		"the sliders move the buses from those trims, dB for dB")
	_ok(music_mix <= sfx_mix - 5.0,
		"music sits under the effects: Music bus %.1f dB against SFX %.1f dB"
			% [music_mix, sfx_mix])

	var mdb: float = float(gm.get("music_volume_db")) if gm != null else 0.0
	var sdb: float = float(gm.get("sfx_volume_db")) if gm != null else 0.0
	_am.call("set_music_volume_db", mdb)
	_am.call("set_sfx_volume_db", sdb)


# --- 9. Determinism ----------------------------------------------------------

## Two builds from the same seed are the same bytes. The generators draw noise,
## grain scatter, modal detuning and starting phase from RandomNumberGenerator —
## and until this pass two of them (`_rumble`, `_whoosh`) drew from the GLOBAL
## unseeded generator instead, so the fallback for `rock_impact` was a different
## waveform on every boot. Invisible to the capture gate, because it never
## reaches a pixel, and fatal to a probe that measures it.
func _check_determinism() -> void:
	print("\n=== determinism ===")
	var lib: Dictionary = _am.get("_streams")
	var sample := ["boss_roar", "fall", "splash",
		_am.call("_surface_key", "prop_break", ToonFactory.Surface.WOOD),
		_am.call("_surface_key", "prop_debris", ToonFactory.Surface.GRANITE),
		"rock_impact_fallback"]

	var first: Dictionary = {}
	for k in sample:
		var w := lib.get(k) as AudioStreamWAV
		if w != null:
			first[k] = w.data

	var t0 := Time.get_ticks_usec()
	_am.call("_build_library")
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var lib2: Dictionary = _am.get("_streams")

	var differs: Array = []
	for k in first:
		var w := lib2.get(k) as AudioStreamWAV
		if w == null or w.data != first[k]:
			differs.append(k)

	# The unseeded-RNG fallbacks, checked by name rather than by hope.
	var r1 := (lib2.get("rock_impact") as AudioStreamWAV)
	_am.call("_build_library")
	var r2 := ((_am.get("_streams") as Dictionary).get("rock_impact") as AudioStreamWAV)
	var rumble_stable: bool = r1 != null and r2 != null and r1.data == r2.data

	var total := 0
	for k in lib2:
		var w := lib2[k] as AudioStreamWAV
		if w != null and w.format == AudioStreamWAV.FORMAT_16_BITS:
			total += w.data.size()
	print("  -- rebuilt %d streams (%.0f KB) in %.0f ms" % [lib2.size(), total / 1024.0, build_ms])

	_ok(differs.is_empty(), "the library rebuilds byte-identically (%s)"
		% ("identical" if differs.is_empty() else str(differs)))
	_ok(rumble_stable,
		"the noise-based fallbacks (_rumble / _whoosh) are seeded too — they used "
			+ "the global generator and were a different waveform on every boot")
	_ok(build_ms < 900.0,
		"the whole library, roar and twenty-one material voices included, synthesises "
			+ "in %.0f ms — the fallback cost if the bake is missing; boot loads the bake" % build_ms)

	_am.call("_load_sfx_files")


## Real seconds. Every fade and duck in AudioManager is specified in seconds and
## driven by a Tween, so a frame-counting wait measures how fast this machine
## draws rather than how long the fade takes — and headless with no fps cap it
## draws very fast indeed. Probes are the documented exception to the wall-clock
## rule; nothing in the game does this.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok   ", label)
	else:
		_fail += 1
		printerr("  FAIL ", label)
