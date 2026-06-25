extends Node
## MusicManager (autoload singleton "MusicManager")
##
## Fully procedural, looping background music on the "Music" bus — synthesised the
## same way the AudioManager makes SFX (no audio files shipped). Three tracks
## (menu / battle / phase-2 battle) crossfade in response to GameManager state.
## Each track is a bar-aligned loop of bass + arpeggio + pad (+ drums for battle).
##
## The voice helpers mutate the member buffer `_buf` directly (rather than a passed
## PackedFloat32Array) to avoid copy-on-write losing the writes.

const MIX_RATE := 22050

# A natural-minor flavour: roots are MIDI notes, one chord per bar.
const PROG_BATTLE := [45, 41, 43, 40]   # A2  F2  G2  E2
const PROG_MENU := [45, 52, 48, 43]     # A2  E3  C3  G2 (gentler)

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _streams: Dictionary = {}
var _current: String = ""
var _buf: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = Settings.MUSIC_BUS
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)

	GameManager.state_changed.connect(_on_state_changed)
	GameManager.boss_phase_changed.connect(_on_phase_changed)
	GameManager.game_over.connect(func(_v: bool) -> void: stop())

	# Pre-build the tracks so there's no stutter when the fight starts.
	_get("menu")
	call_deferred("_prewarm")
	_on_state_changed(GameManager.state)


func _prewarm() -> void:
	_get("battle")
	_get("battle2")


func _on_state_changed(state: int) -> void:
	match state:
		GameManager.State.MENU:
			play("menu")
		GameManager.State.PLAYING:
			# Don't downgrade phase-2 music back to battle on unpause.
			if _current != "battle2":
				play("battle")
		GameManager.State.VICTORY, GameManager.State.DEFEAT:
			stop()


func _on_phase_changed(phase: int) -> void:
	if phase >= 2 and GameManager.state == GameManager.State.PLAYING:
		play("battle2")


# --- Playback / crossfade --------------------------------------------------

func play(track: String) -> void:
	if track == _current:
		return
	_current = track
	var stream := _get(track)
	if stream == null:
		return
	var new_p := _players[1 - _active]
	var old_p := _players[_active]
	_active = 1 - _active

	new_p.stream = stream
	new_p.volume_db = -80.0
	new_p.play()

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(new_p, "volume_db", 0.0, 1.0)
	t.tween_property(old_p, "volume_db", -80.0, 1.0)
	t.set_parallel(false)
	t.tween_callback(old_p.stop)


func stop() -> void:
	_current = ""
	for p in _players:
		if not p.playing:
			continue
		var t := create_tween()
		t.tween_property(p, "volume_db", -80.0, 0.7)
		t.tween_callback(p.stop)


func _get(track: String) -> AudioStreamWAV:
	if not _streams.has(track):
		_streams[track] = _build(track)
	return _streams[track]


# --- Synthesis -------------------------------------------------------------

func _build(track: String) -> AudioStreamWAV:
	var bpm := 132.0
	var prog := PROG_BATTLE
	var intensity := 0.6
	match track:
		"menu":
			bpm = 88.0
			prog = PROG_MENU
			intensity = 0.0
		"battle":
			bpm = 132.0
			intensity = 0.6
		"battle2":
			bpm = 152.0
			intensity = 1.0

	var beat := 60.0 / bpm
	var bars := prog.size()
	var total := beat * 4.0 * float(bars)
	_buf = PackedFloat32Array()
	_buf.resize(int(total * MIX_RATE))

	for bar in bars:
		var root: int = prog[bar]
		var bar_t := beat * 4.0 * float(bar)

		# Soft sustained pad (root + fifth) under the whole bar.
		_tone(bar_t, beat * 4.0, _midi(root), 0.07, "sine")
		_tone(bar_t, beat * 4.0, _midi(root + 7), 0.05, "sine")

		# Bass pulse on the eighths.
		for e in 8:
			_tone(bar_t + float(e) * beat * 0.5, beat * 0.42, _midi(root - 12), 0.24, "square")

		# Arpeggio over the chord tones (sixteenths), brighter when intense.
		var chord := [root + 12, root + 15, root + 19, root + 24]
		for s in 16:
			_tone(bar_t + float(s) * beat * 0.25, beat * 0.2, _midi(chord[s % 4]), 0.09 + 0.05 * intensity, "tri")

		# Drums for the battle tracks.
		if intensity > 0.0:
			_kick(bar_t, 0.55)
			_kick(bar_t + beat * 2.0, 0.55)
			_snare(bar_t + beat, 0.4 * intensity)
			_snare(bar_t + beat * 3.0, 0.4 * intensity)
			if intensity >= 1.0:
				for e in 8:
					_hat(bar_t + float(e) * beat * 0.5, 0.1)

	_normalize(0.85)
	return _to_wav()


func _midi(m: int) -> float:
	return 440.0 * pow(2.0, (float(m) - 69.0) / 12.0)


## Trapezoidal attack/release envelope over the note's normalised lifetime.
func _adsr(t: float) -> float:
	if t < 0.04:
		return t / 0.04
	if t > 0.8:
		return (1.0 - t) / 0.2
	return 1.0


func _tone(start_s: float, dur_s: float, freq: float, vol: float, wave: String) -> void:
	var n := _buf.size()
	var s0 := int(start_s * MIX_RATE)
	var dn := int(dur_s * MIX_RATE)
	if dn <= 0:
		return
	var phase := 0.0
	var inc := TAU * freq / MIX_RATE
	for i in dn:
		var idx := s0 + i
		phase += inc
		if idx < 0 or idx >= n:
			continue
		var env := _adsr(float(i) / float(dn))
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			"tri":
				s = asin(sin(phase)) * (2.0 / PI)
			_:
				s = sin(phase)
		_buf[idx] += s * env * vol


func _kick(start_s: float, vol: float) -> void:
	var n := _buf.size()
	var s0 := int(start_s * MIX_RATE)
	var dn := int(0.18 * MIX_RATE)
	var phase := 0.0
	for i in dn:
		var idx := s0 + i
		if idx < 0 or idx >= n:
			continue
		var t := float(i) / float(dn)
		phase += TAU * (120.0 * (1.0 + 2.2 * exp(-32.0 * t))) / MIX_RATE
		_buf[idx] += sin(phase) * exp(-12.0 * t) * vol


func _snare(start_s: float, vol: float) -> void:
	var n := _buf.size()
	var s0 := int(start_s * MIX_RATE)
	var dn := int(0.15 * MIX_RATE)
	for i in dn:
		var idx := s0 + i
		if idx < 0 or idx >= n:
			continue
		var t := float(i) / float(dn)
		_buf[idx] += (randf_range(-1.0, 1.0) * 0.8 + sin(TAU * 180.0 * t) * 0.2) * exp(-18.0 * t) * vol


func _hat(start_s: float, vol: float) -> void:
	var n := _buf.size()
	var s0 := int(start_s * MIX_RATE)
	var dn := int(0.04 * MIX_RATE)
	for i in dn:
		var idx := s0 + i
		if idx < 0 or idx >= n:
			continue
		_buf[idx] += randf_range(-1.0, 1.0) * exp(-60.0 * float(i) / float(dn)) * vol


func _normalize(target: float) -> void:
	var peak := 0.0001
	for i in _buf.size():
		peak = maxf(peak, absf(_buf[i]))
	var g := target / peak
	for i in _buf.size():
		_buf[i] *= g


func _to_wav() -> AudioStreamWAV:
	var n := _buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, clampi(int(clampf(_buf[i], -1.0, 1.0) * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav
