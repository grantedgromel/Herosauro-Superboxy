extends Node
## AudioManager (autoload singleton "AudioManager")
##
## Fully procedural SFX: every sound is synthesised into an AudioStreamWAV at
## startup (no audio files shipped). Entities call the named play_* helpers.
## A small round-robin pool of AudioStreamPlayer nodes lets sounds overlap.

const MIX_RATE := 22050
const POOL_SIZE := 10

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = Settings.SFX_BUS   # mix through the SFX bus so the options menu can control it
		add_child(p)
		_players.append(p)
	_build_library()


# --- Public API ------------------------------------------------------------

func play_jump() -> void: _play("jump")
func play_attack() -> void: _play("attack")
func play_ui() -> void: _play("ui", -4.0)
func play_dino_fire() -> void: _play("dino_fire")
func play_dino_hit() -> void: _play("dino_hit")
func play_dash() -> void: _play("dash")
func play_boss_slam() -> void: _play("boss_slam")
func play_boss_hit() -> void: _play("boss_hit")
func play_victory() -> void: _play("victory")
func play_defeat() -> void: _play("defeat")
func play_hurt() -> void: _play("hurt")


func _play(name: String, volume_db: float = 0.0) -> void:
	if not _streams.has(name):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.play()


# --- Synthesis -------------------------------------------------------------

func _build_library() -> void:
	_streams["jump"] = _make(_sweep(200.0, 600.0, 0.15, 0.6))
	_streams["attack"] = _make(_whoosh(0.16, 0.5))
	_streams["ui"] = _make(_pulse(660.0, 0.06, 0.35))
	_streams["dino_fire"] = _make(_pulse(440.0, 0.14, 0.5))
	_streams["dino_hit"] = _make(_rumble(80.0, 0.22, 0.7))
	_streams["dash"] = _make(_whoosh(0.26, 0.5))
	_streams["boss_slam"] = _make(_thud(40.0, 0.32, 0.9))
	_streams["boss_hit"] = _make(_thud(150.0, 0.13, 0.7))
	_streams["hurt"] = _make(_sweep(420.0, 160.0, 0.16, 0.5))
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
