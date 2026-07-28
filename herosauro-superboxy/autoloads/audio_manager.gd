extends Node
## AudioManager (autoload singleton "AudioManager")
##
## Two independent halves on two buses:
##
##   SFX    shipped samples from res://assets/audio/sfx/, each falling back to a
##          synthesised AudioStreamWAV when its file is absent — so a missing or
##          unimported sample degrades to a blip rather than to silence. Entities
##          call the named play_* helpers; a round-robin pool lets sounds overlap.
##   Music  the shipped soundtrack, on a small pool of players so one track can
##          crossfade into another. Driven entirely from GameManager's signals,
##          so no scene has to remember to start or stop it.

const MIX_RATE := 22050
const POOL_SIZE := 10

const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

# --- SFX ---------------------------------------------------------------------

const SFX_DIR := "res://assets/audio/sfx/"

## Logical name -> file. Loaded over the synthesised library, so a name missing
## here (or whose file is absent) keeps its procedural fallback. `dino_fire` is
## deliberately absent: its upload was a corrupt MP3 and it rides the synth.
const SFX_FILES := {
	"jump": "jump.wav",
	"land": "land.wav",
	"hurt": "hurt.wav",
	"dash": "dash.wav",
	"dino_hit": "dino_hit.wav",
	"boss_hit": "boss_hit.wav",
	"boss_slam": "boss_slam.wav",
	"rock_throw": "rock_throw.wav",
	"rock_impact": "rock_impact.wav",
	"super_boxy_hit": "super_boxy_hit.wav",
}

## Per-sound headroom. The shipped samples are peak-normalised to -1 dBFS, while
## the synthesis they replace baked its level into the generator calls. These
## trim the ones that are both hot and frequent so a flurry of hits does not
## swamp the music. Anything unlisted plays flat.
const SFX_GAIN_DB := {
	"boss_hit": -4.0,
	"dino_hit": -4.0,
	"jump": -3.0,
	"land": -3.0,
}

# --- Music -------------------------------------------------------------------

const MUSIC_DIR := "res://assets/audio/music/"

## Logical name -> file. Only title is mp3; the rest were 48 kHz stereo PCM WAV
## (42 MB in total) and are shipped as OGG Vorbis at about 8% of that.
const MUSIC_TRACKS := {
	"title": "title.mp3",
	"battle_phase1": "battle_phase1.ogg",
	"battle_phase2": "battle_phase2.ogg",
	"victory": "victory.ogg",
	"defeat": "defeat.ogg",
}

const MUSIC_FADE := 1.6          ## default crossfade, seconds
const MUSIC_DUCK_DB := -12.0     ## how far the Music bus drops while paused
const MUSIC_DUCK_TIME := 0.35

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0

## Three, not two: a transition arriving inside the previous fade needs a player
## that is not still audible. See _pick_music_player().
const MUSIC_PLAYERS := 3

var _music: Array[AudioStreamPlayer] = []
var _music_active: int = 0
var _music_track: String = ""
var _music_base_db: float = 0.0             ## the Music bus level before ducking
var _music_tween: Tween
var _duck_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)

	for i in MUSIC_PLAYERS:
		var m := AudioStreamPlayer.new()
		m.name = "Music%d" % i
		# Music must keep playing while the tree is paused — the pause menu ducks
		# it rather than cutting it.
		m.process_mode = Node.PROCESS_MODE_ALWAYS
		m.bus = MUSIC_BUS
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)

	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus >= 0:
		_music_base_db = AudioServer.get_bus_volume_db(bus)

	_build_library()
	# After the synth pass, so a shipped sample wins and anything without one
	# silently keeps its fallback.
	_load_sfx_files()
	_connect_game_signals()


# --- Public API ------------------------------------------------------------

func play_jump() -> void: _play("jump")
func play_dino_fire() -> void: _play("dino_fire")
func play_dino_hit() -> void: _play("dino_hit")
func play_dash() -> void: _play("dash")
func play_boss_slam() -> void: _play("boss_slam")
func play_boss_hit() -> void: _play("boss_hit")
func play_victory() -> void: _play("victory")
func play_defeat() -> void: _play("defeat")
func play_hurt() -> void: _play("hurt")
func play_land() -> void: _play("land")
func play_rock_throw() -> void: _play("rock_throw")
func play_rock_impact() -> void: _play("rock_impact")
func play_super_boxy_hit() -> void: _play("super_boxy_hit")


func _play(key: String, volume_db: float = 0.0) -> void:
	# `key`, not `name`: a parameter called `name` shadows Node.name.
	if not _streams.has(key):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _streams[key]
	p.volume_db = volume_db + SFX_GAIN_DB.get(key, 0.0)
	p.play()


## Overlay the shipped samples on top of the synthesised library.
func _load_sfx_files() -> void:
	for key in SFX_FILES:
		var path: String = SFX_DIR + SFX_FILES[key]
		if not ResourceLoader.exists(path):
			continue
		var s := load(path) as AudioStream
		if s != null:
			_streams[key] = s


# --- Music API ---------------------------------------------------------------

## Start `track` (a key of MUSIC_TRACKS), crossfading from whatever is playing.
##
## Re-requesting the track already playing is a no-op, so it is safe to call
## from a signal that can fire more than once.
func play_music(track: String, loop: bool = true, fade: float = MUSIC_FADE) -> void:
	if track == _music_track and _music[_music_active].playing:
		return
	var stream := _load_music(track)
	if stream == null:
		return
	_set_stream_loop(stream, loop)

	_music_active = _pick_music_player()
	var incoming := _music[_music_active]

	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	_music_track = track

	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, fade)
	# Fade out EVERY other live player, not just the previous one. Killing the
	# tween above also cancelled its stop-callback, so an earlier transition can
	# still have a player running; without this it stays audible behind the new
	# track forever.
	for i in _music.size():
		if i != _music_active and _music[i].playing:
			_music_tween.tween_property(_music[i], "volume_db", -80.0, fade)
	_music_tween.chain().tween_callback(_stop_idle_music)


## Retire every player that is not the live one. Safe to run late: it reads
## _music_active at call time, so a transition that landed in the meantime keeps
## its player.
func _stop_idle_music() -> void:
	for i in _music.size():
		if i != _music_active:
			_music[i].stop()


## A player that is not currently audible, so starting a track never cuts one
## off mid-sample.
##
## Alternating between two players looked fine but was not: tweens do not
## advance until the next frame, so a player whose fade-out was only just
## scheduled is still sitting at full volume. Reusing it called play() on a live
## node and killed the track mid-sample with a click — audible on menu -> START
## inside the fade, and on phase two landing near the end of a fight.
func _pick_music_player() -> int:
	for i in _music.size():
		if not _music[i].playing:
			return i
	# All busy (three transitions inside one fade): take the quietest, which is
	# the one closest to being retired anyway.
	var best := 0
	for i in _music.size():
		if _music[i].volume_db < _music[best].volume_db:
			best = i
	return best


## Fade the soundtrack out entirely.
func stop_music(fade: float = MUSIC_FADE) -> void:
	_music_track = ""
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	for m in _music:
		if m.playing:
			_music_tween.tween_property(m, "volume_db", -80.0, fade)
	_music_tween.chain().tween_callback(func() -> void:
		for m in _music:
			m.stop())


## Music bus level in dB, for an options screen.
func set_music_volume_db(db: float) -> void:
	_music_base_db = db
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, db)


func set_sfx_volume_db(db: float) -> void:
	var bus := AudioServer.get_bus_index(SFX_BUS)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, db)


## Drop the whole Music bus while paused, and lift it again on resume. Done on
## the bus rather than the players so a crossfade in flight is unaffected.
func duck_music(ducked: bool) -> void:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0:
		return
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	var target := _music_base_db + MUSIC_DUCK_DB if ducked else _music_base_db
	_duck_tween = create_tween()
	_duck_tween.tween_method(
		func(v: float) -> void: AudioServer.set_bus_volume_db(bus, v),
		AudioServer.get_bus_volume_db(bus), target, MUSIC_DUCK_TIME)


func _load_music(track: String) -> AudioStream:
	if not MUSIC_TRACKS.has(track):
		push_warning("AudioManager: unknown music track '%s'" % track)
		return null
	var path: String = MUSIC_DIR + MUSIC_TRACKS[track]
	if not ResourceLoader.exists(path):
		# Missing audio should never take the game down with it.
		push_warning("AudioManager: music file missing: " + path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	# load() hands back the engine's cached resource, and _set_stream_loop writes
	# to it. Without this duplicate, playing victory as a one-shot would clear the
	# loop flag on the shared resource for every later looping use of the same
	# file — so each request gets its own copy of the (tiny) stream object.
	return stream.duplicate() as AudioStream


## Looping lives on the stream resource and each format spells it differently.
## The resource is shared, so duplicate before touching it or a one-shot and a
## looping use of the same file would fight over the flag.
func _set_stream_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = \
			AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED


# --- Game state -> soundtrack ------------------------------------------------

func _connect_game_signals() -> void:
	# Deferred: AudioManager may well be the first autoload up, and GameManager
	# might not exist yet when _ready() runs.
	await get_tree().process_frame
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		push_warning("AudioManager: GameManager not found; soundtrack idle")
		return
	gm.state_changed.connect(_on_state_changed)
	gm.game_started.connect(_on_game_started)
	gm.boss_phase_changed.connect(_on_boss_phase_changed)
	gm.game_over.connect(_on_game_over)
	_on_state_changed(gm.state)


func _on_state_changed(state: int) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return
	match state:
		gm.State.MENU:
			duck_music(false)
			play_music("title")
		gm.State.PAUSED:
			duck_music(true)
		gm.State.PLAYING:
			# Covers resuming from pause; the opening track is started by
			# game_started so a fresh match always restarts phase 1.
			duck_music(false)


func _on_game_started() -> void:
	duck_music(false)
	play_music("battle_phase1")


func _on_boss_phase_changed(phase: int) -> void:
	if phase >= 2:
		play_music("battle_phase2", true, 2.2)


func _on_game_over(victory: bool) -> void:
	if victory:
		play_music("victory", false, 0.8)
	else:
		play_music("defeat", true, 0.8)


# --- Synthesis -------------------------------------------------------------

func _build_library() -> void:
	_streams["jump"] = _make(_sweep(200.0, 600.0, 0.15, 0.6))
	_streams["dino_fire"] = _make(_pulse(440.0, 0.14, 0.5))
	_streams["dino_hit"] = _make(_rumble(80.0, 0.22, 0.7))
	_streams["dash"] = _make(_whoosh(0.26, 0.5))
	_streams["boss_slam"] = _make(_thud(40.0, 0.32, 0.9))
	_streams["boss_hit"] = _make(_thud(150.0, 0.13, 0.7))
	_streams["hurt"] = _make(_sweep(420.0, 160.0, 0.16, 0.5))
	_streams["land"] = _make(_thud(90.0, 0.12, 0.5))
	_streams["rock_throw"] = _make(_whoosh(0.2, 0.45))
	_streams["rock_impact"] = _make(_rumble(60.0, 0.28, 0.8))
	_streams["super_boxy_hit"] = _make(_thud(190.0, 0.12, 0.7))
	_streams["victory"] = _make(_fanfare([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.18, true))
	_streams["defeat"] = _make(_fanfare([659.25, 523.25, 440.0], 0.36, false))


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s := clampi(int(samples[i] * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _env(t: float, dur: float, attack: float = 0.01) -> float:
	if t < attack:
		return t / attack
	var r: float = (t - attack) / max(0.0001, dur - attack)
	return exp(-3.0 * r) * (1.0 - r)


func _sweep(f0: float, f1: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f: float = lerp(f0, f1, t / dur)
		phase += TAU * f / MIX_RATE
		out[i] = sin(phase) * _env(t, dur) * vol
	return out


func _pulse(freq: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var saw := signf(sin(TAU * freq * t)) * 0.5 + sin(TAU * freq * t) * 0.5
		out[i] = saw * _env(t, dur) * vol
	return out


func _rumble(freq: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var tone := sin(TAU * freq * t)
		var noise := randf_range(-1.0, 1.0)
		out[i] = (tone * 0.6 + noise * 0.4) * _env(t, dur) * vol
	return out


func _whoosh(dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var raw := randf_range(-1.0, 1.0)
		# One-pole low-pass whose cutoff opens then closes -> swoosh.
		var k: float = 0.05 + 0.4 * sin(PI * t / dur)
		prev = lerp(prev, raw, k)
		out[i] = prev * _env(t, dur, 0.04) * vol
	return out


func _thud(freq: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		# Pitch drops over the hit for a punchy "boom".
		var f: float = freq * (1.0 + 1.5 * exp(-12.0 * t))
		phase += TAU * f / MIX_RATE
		out[i] = sin(phase) * _env(t, dur) * vol
	return out


func _fanfare(notes: Array, note_dur: float, staccato: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for freq in notes:
		var n := int(note_dur * MIX_RATE)
		for i in n:
			var t := float(i) / MIX_RATE
			var gain := _env(t, note_dur, 0.015)
			if not staccato:
				gain = _env(t, note_dur, 0.04)
			var s := sin(TAU * float(freq) * t)
			# A little 2nd harmonic for a brighter, brassier note.
			s += 0.3 * sin(TAU * float(freq) * 2.0 * t)
			out.append(s * gain * 0.5)
	return out
