extends Node
## AudioManager (autoload singleton "AudioManager")
##
## Two independent halves on two buses:
##
##   SFX    shipped samples from res://assets/audio/sfx/, each falling back to a
##          synthesised AudioStreamWAV when its file is absent — so a missing or
##          unimported sample degrades to a blip rather than to silence. Entities
##          call the named play_* helpers; a pooled voice allocator lets sounds
##          overlap, and when it runs out it steals the voice closest to finishing
##          rather than whichever one the cursor happened to land on.
##   Music  the shipped soundtrack, on a small pool of players so one track can
##          crossfade into another. Driven entirely from GameManager's signals,
##          so no scene has to remember to start or stop it.
##
## FOUR THINGS HERE ARE SYNTHESISED OUTRIGHT rather than sampled, because the
## shipped library has ten transients and none of them is what was needed and no
## new file is coming:
##
##   the roar        Adamastor's phase-two bellow. A source-filter voice: a
##                   jittered glottal pulse train through three moving formants,
##                   with a growl AM, a sub octave and a rasp band. See _roar().
##   prop impacts    modal synthesis, one voice per `ToonFactory.Surface`, so
##                   wood knocks and dies in 110 ms while iron rings for 1.35 s.
##                   See surface_voice() — it is the audio half of the same
##                   contract `ImpactFX.impact_row()` is the fx half of.
##   the fall        going over the side of the Dom Luís: a receding doppler
##                   whistle, a hole, then the Douro taking it. See _fall().
##   the splash      the water on its own, for anything else that goes in.
##
## Everything else is a shipped sample, re-shaped at play time (gain, pitch) but
## not resynthesised.

## Sample rate of everything synthesised here. 22 050 puts Nyquist at 11 kHz,
## which is above the top partial of every voice in this file (the brightest is
## terracotta's 3.5 kHz mode), so raising it would cost memory and buy nothing.
const MIX_RATE := 22050

## Sixteen, not ten. The props stream measured twelve props destroyed in one
## frame; a destruction is two voices (the fracture and the debris that follows
## it), so that single frame asks for twenty-four. Ten meant the first fourteen
## requests were cut off by the last ten — including whatever the heroes and the
## giant were doing at the time, because the pool is shared. Sixteen plus the
## per-sound stacking limit below (which collapses twelve identical crates to
## three voices) covers four materials breaking at once with headroom left for
## the fight.
const POOL_SIZE := 16

const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

## Two explicitly seeded streams, because ARCHITECTURE.md bans the global
## randf()/randi() family and because a probe cannot measure a waveform that is
## different on every boot. `_synth_rng` draws the phases, detunings and debris
## scatter that shape the library at load; `_play_rng` draws the per-shot pitch
## and gain jitter and is re-seeded at the start of every fight, so two runs of
## the same fight sound identical sample for sample.
const SYNTH_SEED := 0x41756469
const PLAY_SEED := 0x726F6172

var _synth_rng := RandomNumberGenerator.new()
var _play_rng := RandomNumberGenerator.new()

# --- SFX ---------------------------------------------------------------------

const SFX_DIR := "res://assets/audio/sfx/"

## Logical name -> file. Loaded over the synthesised library, so a name missing
## here (or whose file is absent) keeps its procedural fallback. `dino_fire` is
## deliberately absent: its upload was a corrupt MP3 and it rides the synth. So
## are every `prop_*`, `boss_roar`, `fall` and `splash` key — those have no file
## and never will.
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
##
## The prop rows are the tightest in the table and deliberately so: a hit is a
## texture under the fight, not an event in it, and the debris tail is quieter
## still because it is the longest thing in the library and would otherwise sit
## under the mix for a second after every smash.
const SFX_GAIN_DB := {
	"boss_hit": -4.0,
	"dino_hit": -5.0,
	"jump": -3.0,
	"land": -3.0,
	"boss_roar": 0.0,
	"fall": -2.0,
	"splash": -3.5,
	"prop_hit": -7.0,
	"prop_break": -3.0,
	"prop_debris": -8.0,
}

## Permanent pitch offset applied before the per-shot jitter.
##
## `dino_hit` is here because `dino_hit.wav` and `boss_hit.wav` are THE SAME FILE
## — byte-identical, md5 c55375d8…, identical at source in the uploaded MP3s too.
## Two of the three most frequently fired transients in the game were literally
## one sound, which is why a hero's orb landing and the giant flinching read as
## the same event. A perfect fourth up separates them and suits the smaller,
## brighter thing an energy orb is; the real fix is a different recording, and
## this is what can be done without one.
const SFX_PITCH_BASE := {
	"dino_hit": 1.33,
}

## How far the per-shot pitch jitter may wander, as a fraction of unity. A jab
## that fires twice in a frame — which two heroes make routine — reads as a
## machine gun when both voices are the same sample at the same pitch, and as a
## double hit when they are not.
##
## `boss_slam` gets a narrow one because it is a promise the player reads timing
## off, and `boss_roar` gets none at all: it happens once per fight and it is the
## same event every time.
const SFX_PITCH_VAR := {
	"boss_hit": 0.09,
	"dino_hit": 0.09,
	"super_boxy_hit": 0.10,
	"dino_fire": 0.07,
	"hurt": 0.06,
	"land": 0.07,
	"jump": 0.05,
	"dash": 0.05,
	"rock_throw": 0.12,
	"rock_impact": 0.08,
	"boss_slam": 0.04,
	"fall": 0.05,
	"splash": 0.07,
}

## How long the same logical sound stays "already playing" for stacking purposes.
## 45 ms is about three physics ticks at 90 Hz: long enough to catch a frame in
## which twelve crates burst, short enough that a fast combo still gets one voice
## per swing.
const SFX_RETRIGGER := 0.045

## Voices one logical sound may hold inside that window, and what each extra one
## costs. Twelve identical crate fractures summing at full gain is +21 dB of
## perfectly correlated transient — it does not read as twelve crates, it reads
## as clipping. Three, at 0 / -4 / -8 dB, sums to about +2.5 dB over one: audibly
## bigger, still a crate.
const SFX_STACK_MAX := 3
const SFX_STACK_DB := -4.0

## Sounds that must never overlap a copy of themselves. A second roar layered on
## the first is not a louder roar, it is a phaser.
const SFX_SOLO := {
	"boss_roar": true,
	"fall": true,
}

## Distance attenuation for the entry points that are handed a world position.
##
## Nothing inside the reference distance is attenuated at all: the co-op camera
## boom runs 8.5–16 m (`camera_rig.gd`), so 18 m is "anywhere in the framed
## fight" and the mix there must not wobble as the pair walk about. Beyond it,
## -6 dB per doubling — a prop rattled loose forty metres down the deck arrives
## at -7 dB and one at the far abutment at the -20 dB floor, present but not
## competing with the fight in shot.
const SFX_REF_DIST := 18.0
const SFX_ROLLOFF_DB := 6.0
const SFX_MIN_DB := -20.0

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

## The phase-two moment, timed against the roar rather than across it.
##
## `boss_phase_changed` starts a 2.2 s crossfade into battle_phase2 at the exact
## instant the giant begins his bellow, and two things arriving together at full
## level is the one way to lose both. So the Music bus drops 9 dB in 120 ms, holds
## through the roar's crest (which lands at ROAR_CREST, 0.85 s in) and the
## shockwave that follows it, then comes back over 1.3 s — the incoming track has
## been fading up on a ducked bus the whole time, so phase two does not start,
## it BLOOMS out of the roar's tail. 0.12 + 0.95 + 1.30 = 2.37 s, which is where
## the crossfade finishes anyway.
const PHASE2_FADE := 2.2
const PHASE2_DUCK_DB := -9.0
const PHASE2_DUCK_IN := 0.12
const PHASE2_DUCK_HOLD := 0.95
const PHASE2_DUCK_OUT := 1.30

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0

## When each pooled voice is free again, on `_clock`. Playback position cannot be
## used for this: `AudioStreamPlayer.get_playback_position()` advances off the
## audio thread's wall clock, so under `--fixed-fps` it moves by a different
## amount every frame and the allocator would make a different decision on every
## run. This is accumulated `delta`, which is exactly reproducible.
var _voice_until: PackedFloat32Array = PackedFloat32Array()

## Which pooled voice currently holds each SFX_SOLO key.
var _solo_voice: Dictionary = {}

## Last time each logical sound was dispatched, and how many voices it is holding
## inside the retrigger window.
var _last_at: Dictionary = {}
var _stack: Dictionary = {}

## Accumulated delta. Never the wall clock — see ARCHITECTURE.md, rule 5.
##
## It stops during a hit-stop, because `_process` delta is scaled by
## `Engine.time_scale` and hit_stop sets that to zero. That makes voices look
## busy for up to the freeze's length (0.12 s at the very most) after they have
## actually finished, which errs towards not stealing a voice too early. The
## alternative — an unscaled clock — would have the allocator disagree with the
## game about how much time has passed, which is worse.
var _clock: float = 0.0

## Three, not two: a transition arriving inside the previous fade needs a player
## that is not still audible. See _pick_music_player().
const MUSIC_PLAYERS := 3

var _music: Array[AudioStreamPlayer] = []
var _music_active: int = 0
var _music_track: String = ""
var _music_base_db: float = 0.0             ## the Music bus level before ducking
var _music_tween: Tween
var _duck_tween: Tween
var _event_tween: Tween

## The two independent reasons the Music bus is turned down, kept apart and
## SUMMED rather than fought over. Both used to write the bus level directly, so
## unpausing during the phase-two duck lifted the phase-two duck too, and ducking
## for the roar while paused erased the pause duck.
var _pause_duck_db: float = 0.0
var _event_duck_db: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_synth_rng.seed = SYNTH_SEED
	_play_rng.seed = PLAY_SEED

	_voice_until.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)
		_voice_until[i] = -1.0

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


func _process(delta: float) -> void:
	_clock += delta


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


## Adamastor's phase-two bellow — the biggest single moment in the fight, and
## until now a borrowed copy of the sound his foot makes.
##
## CALL IT FROM `_start_roar()` in `adamastor_state_machine.gd`, not from
## `_do_roar()`. The stream is shaped around ROAR_CREST = 0.85 s, which is that
## file's own `ROAR_WINDUP`: the intake and the build fill the coil and the amber
## ring exactly, and the crest — where the bellow opens out and the shockwave
## blast is baked in — lands on the frame the wave leaves his feet. Called from
## `_do_roar()` instead it still works and still reads as a roar, but the giant
## draws breath after he has already hit you.
##
## `play_boss_slam()` may stay where it is in `_do_roar()`. It is the only
## layering in this file that pays: a synthesised voice plus a recorded impact is
## a giant roaring and something enormous landing, and the two occupy different
## parts of the spectrum (the roar's own blast is under 80 Hz, the slam's energy
## is centred at 1.2 kHz). Dropping it costs the release some body; keeping it
## costs one voice.
func play_boss_roar() -> void:
	_play("boss_roar")


## A blow a prop SURVIVED, keyed on `ToonFactory.Surface` — the same vocabulary
## `ImpactFX.impact_row()` is keyed on, so the chips that fly and the sound they
## make agree about what the thing is made of.
##
## Optional world position: pass it and the sound is attenuated by distance from
## the camera, leave it and it plays flat. `prop_body.gd` has the position at
## both call sites (`_impact_response`'s `at`, `_land_response`'s `at`) and
## passing it is what stops a barrel rolling into the far abutment sounding like
## one under the camera.
func play_prop_hit(surface: int, at: Vector3 = Vector3.INF) -> void:
	_play(_surface_key("prop_hit", surface), 0.0, at)


## The prop coming apart. TWO voices, and that is the contract: the material's
## own fracture, then the debris it becomes. One transient is a hit, and a hit is
## not a destruction — `_props_probe` asserts exactly this by counting the pool's
## dispatches, so a break must always be worth at least two of them.
func play_prop_break(surface: int, at: Vector3 = Vector3.INF) -> void:
	_play(_surface_key("prop_break", surface), 0.0, at)
	_play(_surface_key("prop_debris", surface), 0.0, at)


## Going over the side of the Dom Luís. The drop and the consequence, in one
## stream, because there is no gap to put a second call in: `player_base.gd`
## teleports the hero back on the same frame `_handle_fall()` decides they are
## gone, so a call site that wanted to sound the splash later would have nothing
## left to hang it on. The 30 ms hole at 0.52 s between the whistle and the water
## is what makes it two events instead of one noise.
##
## Call it from the top of `_respawn()` in `player_base.gd`, alongside the
## `damage_player(FALL_PENALTY)` that is currently the only thing that happens.
func play_fall() -> void:
	_play("fall")


## The water on its own, for anything that goes into the Douro without falling
## off the bridge first.
func play_splash(at: Vector3 = Vector3.INF) -> void:
	_play("splash", 0.0, at)


# --- Dispatch ----------------------------------------------------------------

## Hand `key` to a pooled voice.
##
## Four things happen here that did not used to, all of them because two heroes
## and twelve destructible props can put more transients into one frame than a
## fixed round-robin can spend without eating itself:
##
##   1. stacking — the same sound retriggering inside SFX_RETRIGGER is attenuated
##      and then refused, so a dozen identical fractures cost three voices;
##   2. allocation — a voice that has finished is preferred, and when none has,
##      the one CLOSEST TO FINISHING is stolen rather than whichever one the
##      cursor pointed at. Round-robin would cut a 5.1 s `rock_impact` two
##      hundred milliseconds in while a spent 0.15 s `rock_throw` sat idle;
##   3. pitch and gain jitter, seeded, so a repeated sound is not a loop;
##   4. distance, when the caller knows where the sound happened.
##
## `_next_player` still lands on "one past the voice just used" whatever the
## allocator decides, because that is the only observable the props probe has for
## "a transient fired" and it is a public contract now whether it meant to be or
## not.
func _play(key: String, volume_db: float = 0.0, at: Vector3 = Vector3.INF) -> void:
	# `key`, not `name`: a parameter called `name` shadows Node.name.
	if not _streams.has(key):
		return

	var since: float = _clock - float(_last_at.get(key, -1000.0))
	var stack: int = 0
	if since < SFX_RETRIGGER:
		stack = int(_stack.get(key, 0)) + 1
		if stack >= SFX_STACK_MAX:
			# Refused, and the window is NOT extended — three voices is the budget
			# for this sound and it expires SFX_RETRIGGER after the third, not
			# after the last thing that asked.
			return
	_stack[key] = stack
	_last_at[key] = _clock

	var stream: AudioStream = _streams[key]
	var idx := _take_voice(key, stream)
	var p := _players[idx]
	_next_player = (idx + 1) % _players.size()

	var pitch: float = float(SFX_PITCH_BASE.get(key, 1.0))
	var spread: float = float(SFX_PITCH_VAR.get(key, 0.0))
	# Level wanders with pitch, and only downwards. Two swings that differ in
	# pitch but not at all in level still read as a loop, and a symmetric gain
	# jitter would let a run of hits march up over the mix instead of sitting in
	# the headroom the gain table gave them.
	var jitter_db := 0.0
	if spread > 0.0:
		pitch *= 1.0 + _play_rng.randf_range(-spread, spread)
		jitter_db = _play_rng.randf_range(-1.5, 0.0)

	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db + jitter_db \
		+ float(SFX_GAIN_DB.get(key, 0.0)) \
		+ float(stack) * SFX_STACK_DB \
		+ _distance_db(at)
	p.play()

	# maxf: a stream that failed to import reports 0 s, and a voice that is free
	# the instant it starts would be handed out again immediately.
	_voice_until[idx] = _clock + maxf(0.02, stream.get_length() / maxf(0.05, pitch))
	if SFX_SOLO.has(key):
		_solo_voice[key] = idx


## Which pooled voice `key` should use.
func _take_voice(key: String, stream: AudioStream) -> int:
	var size := _players.size()

	# A sound that may not overlap itself reuses its own voice, which stops the
	# copy in flight instead of phasing against it.
	if SFX_SOLO.has(key) and _solo_voice.has(key):
		var held: int = int(_solo_voice[key])
		if held >= 0 and held < size and _players[held].stream == stream:
			return held

	# Scanning from the cursor keeps this exactly round-robin whenever the pool is
	# not under pressure, which is every case the other streams' probes measure.
	for k in size:
		var i: int = (_next_player + k) % size
		if _clock >= _voice_until[i]:
			return i

	# Everything is live. Steal the one with the least left to play.
	var best: int = 0
	for i in size:
		if _voice_until[i] < _voice_until[best]:
			best = i
	return best


## Attenuation for a sound that happened at `at`, relative to the camera.
## Vector3.INF means "the caller does not know", which plays flat.
func _distance_db(at: Vector3) -> float:
	if is_inf(at.x):
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var d: float = cam.global_position.distance_to(at)
	if d <= SFX_REF_DIST:
		return 0.0
	return maxf(SFX_MIN_DB, -SFX_ROLLOFF_DB * log(d / SFX_REF_DIST) / log(2.0))


## Stop every SFX voice and forget the retrigger history. Called when a fight
## starts so a new run never inherits the previous one's tails.
func stop_all_sfx() -> void:
	for i in _players.size():
		_players[i].stop()
		_voice_until[i] = -1.0
	_last_at.clear()
	_stack.clear()
	_solo_voice.clear()


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
	_apply_music_bus()


func set_sfx_volume_db(db: float) -> void:
	var bus := AudioServer.get_bus_index(SFX_BUS)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, db)


## The one place the Music bus level is written. Both ducks are offsets from the
## user's own level and they SUM, so the pause duck and a one-shot event duck can
## be in flight at the same time without either erasing the other.
func _apply_music_bus() -> void:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, _music_base_db + _pause_duck_db + _event_duck_db)


## Drop the whole Music bus while paused, and lift it again on resume. Done on
## the bus rather than the players so a crossfade in flight is unaffected.
func duck_music(ducked: bool) -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	var target: float = MUSIC_DUCK_DB if ducked else 0.0
	if is_equal_approx(target, _pause_duck_db):
		return
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_pause_duck, _pause_duck_db, target, MUSIC_DUCK_TIME)


## Pull the soundtrack down for one moment and let it back afterwards, on a
## channel of its own so the pause duck is untouched. Used for the roar; equally
## right for anything else that has to own the frame it lands on.
func duck_music_event(depth_db: float, attack: float, hold: float, release: float) -> void:
	if _event_tween and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = create_tween()
	_event_tween.tween_method(_set_event_duck, _event_duck_db, depth_db, attack)
	_event_tween.tween_interval(hold)
	_event_tween.tween_method(_set_event_duck, depth_db, 0.0, release)


func _set_pause_duck(db: float) -> void:
	_pause_duck_db = db
	_apply_music_bus()


func _set_event_duck(db: float) -> void:
	_event_duck_db = db
	_apply_music_bus()


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
	# A fight is the unit of reproducibility: the same run must sound the same
	# twice, so the play-time jitter starts from the same place every time.
	_play_rng.seed = PLAY_SEED
	stop_all_sfx()
	if _event_tween and _event_tween.is_valid():
		_event_tween.kill()
	_set_event_duck(0.0)
	play_music("battle_phase1")


## The soundtrack half of the phase flip. The roar itself is the boss stream's
## call (`play_boss_roar`); what is ours is making room for it — see the
## PHASE2_DUCK_* block for the timing and why it is shaped the way it is.
func _on_boss_phase_changed(phase: int) -> void:
	if phase < 2:
		return
	duck_music_event(PHASE2_DUCK_DB, PHASE2_DUCK_IN, PHASE2_DUCK_HOLD, PHASE2_DUCK_OUT)
	play_music("battle_phase2", true, PHASE2_FADE)


func _on_game_over(victory: bool) -> void:
	if _event_tween and _event_tween.is_valid():
		_event_tween.kill()
	_set_event_duck(0.0)
	if victory:
		play_music("victory", false, 0.8)
	else:
		play_music("defeat", true, 0.8)


# --- The surface voice table -------------------------------------------------

## The audio half of the `ToonFactory.Surface` contract, and the exact
## counterpart of `ImpactFX.impact_row()`: one case per surface, no silent
## default, and `_audio_probe` asserts `surface_voice(s)["surface"] == s` for
## every value of the enum — so adding `Surface.SLATE` without adding a case here
## fails the build rather than quietly shipping a wooden knock on a slate roof.
##
## Every impact built from this table is MODAL SYNTHESIS: a struck object rings
## at the modes its shape and stiffness give it, each mode dying at its own rate,
## over a broadband attack whose bandwidth is the other half of the material's
## identity. That is the only model that can key on material at all — the shipped
## library has three usable impact transients against seven surfaces, which is
## how wood ended up splintering at 90 Hz.
##
## The numbers are physics, not taste, and the argument for each sits next to it:
##
## EVERY DECAY IN THIS TABLE IS SECONDS TO -60 dB. All of them: the modes, the
## noise, the body, the debris grains. They were not, and the mismatch mattered —
## a 30 ms noise decay read as a 1/e time constant is 207 ms to -60 dB, which is
## slower than any mode granite has and slower than wood's, so granite's crack
## measured as ringing longer than a wooden crate's. One convention, stated once.
##
##   modes         [Hz, seconds to -60 dB, amplitude]. Inharmonic on purpose —
##                 a plate or a hoop is not a string and its partials are not
##                 integer multiples of anything. The summed ring is normalised
##                 to full scale, so these amplitudes are relative to each other
##                 and every other layer below is a fraction of the whole.
##   noise*        the attack's broadband part: its PEAK AS A FRACTION OF THE
##                 RING, what band it occupies, how resonant that band is, and
##                 how fast it dies.
##   body*         the sub the object's mass puts into the deck under the ring,
##                 again as a fraction of it.
##   hit_dur       how long a survivable blow lasts. This IS the material read:
##                 wood is done in a quarter of a second, iron is still going a
##                 second later.
##   break_drop    what happens to the modes when the thing FRACTURES. A cracked
##                 object is a bigger, looser object, so its modes fall — and the
##                 more brittle the material, the further they fall.
##   grain*        the debris that follows the fracture: how many pieces, over
##                 how long, in what pitch range, and how long each one rings.
##                 Granite makes thirty short ticks of gravel; iron makes twelve
##                 hoops that ring for a third of a second each as they roll.
static func surface_voice(surface: int) -> Dictionary:
	match surface:
		ToonFactory.Surface.GRANITE:
			# Porto kerb granite. Enormously stiff and enormously lossy at the
			# same time: the modes are there but they are gone in fifty
			# milliseconds, so what you actually hear is the broadband crack and
			# the weight. The highest noise content of the seven after cobble,
			# and the deepest body.
			return {
				"surface": ToonFactory.Surface.GRANITE,
				"modes": [[142.0, 0.055, 0.50], [356.0, 0.040, 0.40],
					[790.0, 0.028, 0.30], [1480.0, 0.018, 0.16]],
				"noise": 0.62, "noise_hz": 1500.0, "noise_q": 0.55, "noise_decay": 0.030,
				"body": 0.45, "body_hz": 58.0, "body_decay": 0.10,
				"hit_dur": 0.22, "break_dur": 0.55, "break_drop": 0.80,
				"grains": 26, "grain_spread": 1.10, "grain_hz": Vector2(220.0, 900.0),
				"grain_decay": 0.030, "tail_dur": 1.35,
			}
		ToonFactory.Surface.COBBLE:
			# Calçada setts: the same stone in much smaller cubes, so everything
			# moves up — modes half an octave higher, and more of them scattering
			# afterwards because a sett breaks into more pieces than a kerb does.
			return {
				"surface": ToonFactory.Surface.COBBLE,
				"modes": [[205.0, 0.045, 0.48], [520.0, 0.032, 0.40],
					[1120.0, 0.022, 0.28], [2050.0, 0.014, 0.15]],
				"noise": 0.66, "noise_hz": 2000.0, "noise_q": 0.50, "noise_decay": 0.026,
				"body": 0.34, "body_hz": 70.0, "body_decay": 0.08,
				"hit_dur": 0.20, "break_dur": 0.48, "break_drop": 0.84,
				"grains": 30, "grain_spread": 1.00, "grain_hz": Vector2(300.0, 1200.0),
				"grain_decay": 0.026, "tail_dur": 1.25,
			}
		ToonFactory.Surface.IRON:
			# Barrel hoops and bridge lattice. The only high-Q material in the
			# table and the reason it exists: a 1.35 s fundamental against wood's
			# 0.11 s is a difference nobody can mistake, at any volume, on any
			# speaker. Partials at 1 : 2.33 : 4.58 : 7.48 : 10.4 — a bar and a
			# hoop, not a harmonic series. Its debris rings too, which is what a
			# hoop rolling away actually does.
			return {
				"surface": ToonFactory.Surface.IRON,
				"modes": [[318.0, 1.35, 0.46], [742.0, 1.05, 0.38],
					[1455.0, 0.80, 0.30], [2380.0, 0.55, 0.20], [3310.0, 0.35, 0.12]],
				"noise": 0.22, "noise_hz": 3200.0, "noise_q": 1.20, "noise_decay": 0.010,
				"body": 0.18, "body_hz": 96.0, "body_decay": 0.05,
				"hit_dur": 1.15, "break_dur": 1.60, "break_drop": 0.93,
				"grains": 12, "grain_spread": 1.30, "grain_hz": Vector2(420.0, 2100.0),
				"grain_decay": 0.28, "tail_dur": 1.75,
			}
		ToonFactory.Surface.PLASTER:
			# Limewash render. The deadest thing in the game — three modes, all
			# gone inside 30 ms, and the rest is dust. If a hit on it rings at all
			# the material is wrong.
			#
			# The dust belongs in the TAIL, not in the attack. It carried a 45 ms
			# noise decay, which is the longest in the table and made a limewash
			# knock measure as ringing longer than a wooden one — the cloud is
			# real, but a cloud is something that happens after the blow, so it
			# lives in the twenty-four grains and the long tail instead.
			return {
				"surface": ToonFactory.Surface.PLASTER,
				"modes": [[158.0, 0.030, 0.42], [372.0, 0.022, 0.30], [700.0, 0.014, 0.18]],
				"noise": 0.70, "noise_hz": 1150.0, "noise_q": 0.45, "noise_decay": 0.026,
				"body": 0.40, "body_hz": 64.0, "body_decay": 0.09,
				"hit_dur": 0.18, "break_dur": 0.44, "break_drop": 0.78,
				"grains": 24, "grain_spread": 0.80, "grain_hz": Vector2(180.0, 700.0),
				"grain_decay": 0.035, "tail_dur": 1.15,
			}
		ToonFactory.Surface.TERRACOTTA:
			# Fired roof tile: a thin ceramic plate, so the fundamental sits an
			# octave and a half above stone and it genuinely rings — a third of a
			# second — before it dies. Brittle, so it is the second-largest
			# break_drop in the table.
			return {
				"surface": ToonFactory.Surface.TERRACOTTA,
				"modes": [[624.0, 0.34, 0.46], [1460.0, 0.25, 0.38],
					[2410.0, 0.17, 0.26], [3520.0, 0.11, 0.16]],
				"noise": 0.34, "noise_hz": 3300.0, "noise_q": 1.00, "noise_decay": 0.012,
				"body": 0.20, "body_hz": 88.0, "body_decay": 0.05,
				"hit_dur": 0.44, "break_dur": 0.70, "break_drop": 0.90,
				"grains": 22, "grain_spread": 0.95, "grain_hz": Vector2(700.0, 2600.0),
				"grain_decay": 0.09, "tail_dur": 1.20,
			}
		ToonFactory.Surface.WOOD:
			# Crate boards and barrel staves — and both of those are HOLLOW BOXES,
			# which is the thing that decides how this row sounds. Timber's loss
			# factor is an order of magnitude below stone's and there is a volume
			# of air inside to drive, so a crate is the second-longest ring in the
			# table: a struck cask knocks and keeps knocking for a fifth of a
			# second, where a granite kerb is finished in fifty milliseconds.
			# The fracture is the loudest attack in the table relative to its
			# ring — splintering is a broadband event and 2.1 kHz is where a
			# snapping board lives. Sixteen grains over 0.85 s is planks
			# clattering onto granite.
			return {
				"surface": ToonFactory.Surface.WOOD,
				"modes": [[186.0, 0.180, 0.55], [431.0, 0.140, 0.42],
					[910.0, 0.090, 0.30], [1640.0, 0.050, 0.18]],
				"noise": 0.40, "noise_hz": 2100.0, "noise_q": 0.80, "noise_decay": 0.020,
				"body": 0.30, "body_hz": 82.0, "body_decay": 0.06,
				"hit_dur": 0.26, "break_dur": 0.42, "break_drop": 0.88,
				"grains": 16, "grain_spread": 0.85, "grain_hz": Vector2(320.0, 1500.0),
				"grain_decay": 0.045, "tail_dur": 1.05,
			}
		ToonFactory.Surface.FLAT:
			# The deliberate fallback, and the right answer for a blow that lands
			# on something not made of anything in particular. Neutral, short, and
			# it claims no material — exactly what ImpactFX's FLAT row does. It is
			# deliberately DULLER and DEADER than wood: an untagged collider must
			# never be mistakable for a crate, or the fallback stops being a
			# fallback and starts being a wrong answer.
			return {
				"surface": ToonFactory.Surface.FLAT,
				"modes": [[210.0, 0.045, 0.48], [440.0, 0.030, 0.34], [820.0, 0.018, 0.20]],
				"noise": 0.45, "noise_hz": 1200.0, "noise_q": 0.70, "noise_decay": 0.022,
				"body": 0.28, "body_hz": 76.0, "body_decay": 0.06,
				"hit_dur": 0.22, "break_dur": 0.40, "break_drop": 0.86,
				"grains": 14, "grain_spread": 0.70, "grain_hz": Vector2(280.0, 1200.0),
				"grain_decay": 0.040, "tail_dur": 0.90,
			}
		_:
			# No silent default. A surface added to the enum without a case here
			# is a bug the moment it ships, and this is the line that says so.
			push_error("AudioManager: no surface voice for ToonFactory.Surface %d" % surface)
			return surface_voice(ToonFactory.Surface.FLAT)


## Library key for one (role, surface) pair. Out-of-range surfaces fall back to
## FLAT's key rather than to a key that does not exist, so a bad argument is a
## wrong-sounding hit and never silence.
static func _surface_key(role: String, surface: int) -> String:
	var names: Array = ToonFactory.Surface.keys()
	var s: int = surface
	if s < 0 or s >= names.size():
		push_error("AudioManager: %s given a non-Surface value %d" % [role, surface])
		s = ToonFactory.Surface.FLAT
	return "%s_%s" % [role, str(names[s]).to_lower()]


# --- Synthesis -------------------------------------------------------------

func _build_library() -> void:
	_synth_rng.seed = SYNTH_SEED
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

	_streams["boss_roar"] = _make(_roar())
	_streams["fall"] = _make(_fall())
	_streams["splash"] = _make(_splash(0.0))

	# One case per surface, driven off the enum rather than off a list here, so
	# the table and the library cannot drift apart.
	for s in ToonFactory.Surface.size():
		var row := surface_voice(s)
		_streams[_surface_key("prop_hit", s)] = _make(_impact(row, false))
		_streams[_surface_key("prop_break", s)] = _make(_impact(row, true))
		_streams[_surface_key("prop_debris", s)] = _make(_debris(row))


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


## Seeded, like everything else in this file. It used to call the global
## `randf_range()`, which meant the fallback for `rock_impact` and `dino_hit` was
## a different waveform on every boot — invisible to the capture gate because it
## never reaches a pixel, and fatal to any probe that tries to measure it.
func _rumble(freq: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var tone := sin(TAU * freq * t)
		var noise := _synth_rng.randf_range(-1.0, 1.0)
		out[i] = (tone * 0.6 + noise * 0.4) * _env(t, dur) * vol
	return out


func _whoosh(dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var raw := _synth_rng.randf_range(-1.0, 1.0)
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


# --- DSP primitives ----------------------------------------------------------
#
# Small, in-place and deliberately boring. Everything new in this file is built
# out of these five, which is what keeps a roar, a splintering crate and a splash
# describable in twenty lines each instead of three hundred.

func _buf(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(1, n))
	return out


func _noise(n: int) -> PackedFloat32Array:
	var out := _buf(n)
	for i in out.size():
		out[i] = _synth_rng.randf_range(-1.0, 1.0)
	return out


## One-pole low-pass at `hz`, in place.
func _lowpass(buf: PackedFloat32Array, hz: float, rate: float) -> void:
	var k: float = clampf(1.0 - exp(-TAU * hz / rate), 0.0, 1.0)
	var y := 0.0
	for i in buf.size():
		y += k * (buf[i] - y)
		buf[i] = y


## One-pole high-pass at `hz`, in place. (Input minus its own low-passed self.)
func _highpass(buf: PackedFloat32Array, hz: float, rate: float) -> void:
	var k: float = clampf(1.0 - exp(-TAU * hz / rate), 0.0, 1.0)
	var y := 0.0
	for i in buf.size():
		y += k * (buf[i] - y)
		buf[i] -= y


## Chamberlin state-variable band-pass, in place, normalised so the resonant peak
## sits at about unity whatever Q is.
##
## The centre frequency is clamped to rate/6 because that is where this topology
## stops being stable — 3.7 kHz at our 22 050, which is above every band any
## voice in this file asks for and is stated here so the next person does not
## discover it as a burst of noise.
func _bandpass(buf: PackedFloat32Array, hz: float, q: float, rate: float) -> void:
	var f: float = 2.0 * sin(PI * minf(hz, rate / 6.0) / rate)
	var damp: float = clampf(1.0 / maxf(0.4, q), 0.0, 1.9)
	var low := 0.0
	var band := 0.0
	for i in buf.size():
		var high: float = buf[i] - low - damp * band
		band += f * high
		low += f * band
		buf[i] = band * damp


## Scale a buffer so its loudest sample sits exactly at `peak`, in place.
func _scale_peak(buf: PackedFloat32Array, peak: float) -> void:
	var hi := 0.0
	for i in buf.size():
		hi = maxf(hi, absf(buf[i]))
	if hi <= 0.0:
		return
	var g: float = peak / hi
	for i in buf.size():
		buf[i] *= g


## Add `src * gain` into `dst` starting at sample `offset`.
func _mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int, gain: float) -> void:
	var start := maxi(0, offset)
	var n: int = mini(src.size(), dst.size() - start)
	for i in n:
		dst[start + i] += src[i] * gain


## Scale so the loudest sample sits exactly at `peak`, and taper the last
## `fade` seconds to zero.
##
## Every synthesised stream in this file ends here. That is what lets the probe
## assert, of anything it finds in the library, that the samples are non-zero,
## that |s| <= 1 with no run of clipped values, and that the stream does not stop
## on a discontinuity — three properties that are otherwise a matter of hoping
## the gain staging in each generator happened to add up.
func _finish(buf: PackedFloat32Array, peak: float = 0.94, fade: float = 0.012,
		rate: float = float(MIX_RATE)) -> PackedFloat32Array:
	_scale_peak(buf, peak)
	var f: int = mini(buf.size(), int(fade * rate))
	for i in f:
		buf[buf.size() - 1 - i] *= float(i) / float(maxi(1, f))
	return buf


## A sum of exponentially decaying sinusoids — the sound of a struck object.
##
## Generated with a two-pole resonator recurrence rather than sin()/exp() per
## sample. It is the same waveform to floating-point noise and it is roughly ten
## times faster, which matters: the material library is twenty-one streams and
## the naive form put well over a second onto every boot of a project that
## already takes a while to assemble its world.
##
##   y[n] = 2 r cos(w) y[n-1] - r^2 y[n-2],  y[0] = A sin(p),  y[1] = A r sin(w+p)
##
## `drop` multiplies every mode, for the same object after it has cracked.
func _modal(modes: Array, dur: float, drop: float) -> PackedFloat32Array:
	var rate := float(MIX_RATE)
	var n := int(dur * rate)
	var out := _buf(n)
	for m in modes:
		var mode: Array = m
		# Two crates never ring identically: the detune and the starting phase are
		# what stop sixteen wooden hits sounding like sixteen copies of one.
		var hz: float = float(mode[0]) * drop * _synth_rng.randf_range(0.985, 1.015)
		var decay: float = float(mode[1])
		var amp: float = float(mode[2])
		if hz <= 0.0 or hz >= rate * 0.5:
			continue
		var w: float = TAU * hz / rate
		var r: float = exp(-6.9078 / (maxf(0.004, decay) * rate))   # ln(1000): -60 dB at `decay`
		var c: float = 2.0 * r * cos(w)
		var r2: float = r * r
		var ph: float = _synth_rng.randf_range(0.0, TAU)
		var y1: float = amp * sin(ph)
		var y2: float = amp * r * sin(w + ph)
		if n > 0:
			out[0] += y1
		if n > 1:
			out[1] += y2
		for i in range(2, n):
			var y: float = c * y2 - r2 * y1
			y1 = y2
			y2 = y
			out[i] += y
	return out


# --- Material impacts --------------------------------------------------------

## One blow on one material. `broke` picks the fracture rather than the knock:
## longer, louder, with the modes dropped by the row's `break_drop` and a
## splintering rip laid over the attack.
func _impact(row: Dictionary, broke: bool) -> PackedFloat32Array:
	var rate := float(MIX_RATE)
	var dur: float = float(row["break_dur"]) if broke else float(row["hit_dur"])
	var drop: float = float(row["break_drop"]) if broke else 1.0
	var modes: Array = row["modes"]
	var n := int(dur * rate)

	# THE RING SETS THE SCALE, and every other layer is a stated fraction of it.
	#
	# This normalisation is not cosmetic. Without it `noise` was a gain on a
	# band-passed noise buffer whose own amplitude depended on the filter's Q and
	# on nothing the table could see — so the broadband attack came out louder
	# than the modes on every surface, the material's ring never rose above a
	# tenth of the peak, and MEASURED RING-DOWN REPORTED THE NOISE TAIL INSTEAD
	# OF THE MATERIAL. Granite read as ringing longer than wood, which is exactly
	# backwards. Scaled this way, `noise: 0.62` means "the broadband attack peaks
	# at 62% of the ring", which is a number a person can reason about.
	var out := _modal(modes, dur, drop)
	_scale_peak(out, 1.0)

	if broke:
		# One object becoming two. Both halves ring on, lower (they are looser
		# now) and out of step with each other, and that doubling is most of what
		# separates a crack from a knock. It is also where a break's extra ENERGY
		# comes from: everything here is peak-normalised at the end, so a bigger
		# event can only be made by adding sustain, never by adding gain.
		var halves := _modal(modes, dur, drop * 0.72)
		_scale_peak(halves, 0.70)
		_mix_into(out, halves, int(0.018 * rate), 1.0)

	# The broadband part of the attack. This is what actually tells stone from
	# wood in the first ten milliseconds, before any mode has had time to be
	# heard at all.
	var nz := _noise(n)
	_bandpass(nz, float(row["noise_hz"]), float(row["noise_q"]), rate)
	var nd: float = maxf(0.002, float(row["noise_decay"]))
	if broke:
		nd *= 2.2   # a fracture keeps tearing after a knock has stopped
	for i in n:
		nz[i] *= exp(-6.9078 * float(i) / rate / nd)
	_scale_peak(nz, float(row["noise"]) * (1.35 if broke else 1.0))
	_mix_into(out, nz, 0, 1.0)

	# The mass. A sine that starts an octave high and falls, which is what a heavy
	# thing puts into a deck.
	var body_hz: float = float(row["body_hz"])
	var body_decay: float = maxf(0.01, float(row["body_decay"]))
	var phase := 0.0
	for i in n:
		var t: float = float(i) / rate
		phase += TAU * body_hz * (1.0 + 1.2 * exp(-14.0 * t)) / rate
		out[i] += sin(phase) * exp(-6.9078 * t / body_decay) * float(row["body"])

	# Two milliseconds of full-band click at the very front, scaled with the
	# surface's own broadband content so stone ticks and iron does not. Without it
	# every impact starts with the filters' own rise time and reads as soft.
	var click := _noise(int(0.002 * rate))
	for i in click.size():
		click[i] *= 1.0 - float(i) / float(maxi(1, click.size()))
	_scale_peak(click, 0.15 + 0.45 * float(row["noise"]))
	_mix_into(out, click, 0, 1.0)

	return _finish(out, 0.92 if broke else 0.80)


## What the prop becomes: `grains` pieces landing over `grain_spread` seconds,
## each one a short ring of its own at a pitch drawn from the row's range.
##
## The distribution is deliberately front-loaded (`pow(u, 1.6)`) because debris
## does not arrive uniformly — most of it lands at once and then a few pieces
## skitter. Uniform scatter reads as a drum roll.
func _debris(row: Dictionary) -> PackedFloat32Array:
	var rate := float(MIX_RATE)
	var dur: float = float(row["tail_dur"])
	var out := _buf(int(dur * rate))
	var spread: float = float(row["grain_spread"])
	var band: Vector2 = row["grain_hz"]
	var decay: float = float(row["grain_decay"])
	var count: int = int(row["grains"])

	for g in count:
		var u: float = _synth_rng.randf()
		var at: float = spread * pow(u, 1.6)
		var hz: float = band.x * pow(band.y / band.x, _synth_rng.randf())
		var d: float = decay * _synth_rng.randf_range(0.6, 1.4)
		# Later pieces are smaller pieces.
		var amp: float = _synth_rng.randf_range(0.30, 1.0) * pow(1.0 - at / maxf(0.01, spread * 1.05), 0.6)
		var gn := int(minf(d * 3.5, dur - at) * rate)
		if gn <= 4:
			continue
		var grain := _modal([[hz, d, amp]], float(gn) / rate, 1.0)
		# Each piece hits something before it rings.
		var tick := _noise(int(0.0015 * rate))
		for i in tick.size():
			tick[i] *= 1.0 - float(i) / float(maxi(1, tick.size()))
		_mix_into(grain, tick, 0, amp * 0.5)
		_mix_into(out, grain, int(at * rate), 1.0)

	# A breath of dust under the first third of it, so the scatter has a floor
	# rather than sitting in silence between ticks.
	var dust := _noise(int(spread * 0.6 * rate))
	_bandpass(dust, float(row["noise_hz"]) * 0.6, 0.5, rate)
	for i in dust.size():
		dust[i] *= exp(-6.9078 * float(i) / rate / (spread * 0.5))
	_scale_peak(dust, float(row["noise"]) * 0.30)
	_mix_into(out, dust, 0, 1.0)

	return _finish(out, 0.72)


# --- The roar ----------------------------------------------------------------

## Where the bellow opens out and the shockwave leaves the ground. It mirrors
## `AdamastorStateMachine.ROAR_WINDUP`, which is the interval between
## `_start_roar()` and `_do_roar()`. Kept as a literal on purpose: reaching into
## the boss stream's script to read its constant is exactly what the ownership
## rules forbid, so the two are matched by hand and named on both sides.
const ROAR_CREST := 0.85
const ROAR_LEN := 2.45

## Adamastor's phase-two roar. SYNTHESISED, and not layered out of the shipped
## library, for a reason worth stating: the library contains ten impacts and no
## voice. Anything assembled out of `boss_slam` and `boss_hit` is a bigger slam,
## and a bigger slam is what the moment already had.
##
## This is a source-filter model, which is how a voice is actually made:
##
##   SOURCE   a glottal pulse train — one shaped pulse per cycle rather than a
##            sine, so a filter has something to work on — DIFFERENTIATED, which
##            is the radiation characteristic: what leaves a mouth is the rate of
##            change of the flow through it, not the flow, and that tilt is worth
##            6 dB per octave of brightness the formants would otherwise not get.
##            The fundamental runs 84 Hz to 126 Hz with effort and droops again
##            as the bellow dies, carries a 6.5 Hz vibrato and a couple of per
##            cent of cycle-to-cycle jitter, so it is a throat and not an
##            oscillator.
##   FILTER   three resonant formants that MOVE: F1 175->325, F2 520->990,
##            F3 1180->1500 as the mouth opens from a closed "uh" to an open
##            "aah". The motion is the whole trick — a static filter on a pulse
##            train reads as a synthesiser and a moving one reads as a mouth. The
##            frequencies are roughly a human's divided by 2.2, which is the
##            vocal tract of something about nine metres tall.
##   PLUS     a sub octave for the size, and a 2.4 kHz rasp band gated by the
##            glottal pulse itself so the noise pulses with the voice — that is a
##            torn throat, where noise added flat is just hiss.
##
## Then a 29 Hz growl across the whole thing (that is the chest rattle, and it is
## what stops this being a foghorn — below 25 Hz it reads as tremolo and above 35
## as a buzz), tanh saturation to glue the layers, and a blast at ROAR_CREST that
## is the wave leaving his feet.
##
## Two things that look like shortcuts and are not:
##
##   * The EFFORT ENVELOPE IS APPLIED AFTER THE SATURATION, not before. Driving a
##     tanh with an already-enveloped signal flattens the top of the roar — the
##     level stops following the envelope once it is in compression, and the
##     bellow becomes a two-second plateau. Measured: the crest drifted 190 ms
##     late and the level half a second after it was 0.56 of peak instead of
##     0.44. Saturate the voice, then shape it.
##   * It is generated at MIX_RATE with NO oversampling, which is safe here for a
##     specific reason rather than by luck. `(½(1+cos 2πφ))^20` is a finite
##     harmonic series — exactly twenty harmonics of f0, nothing above 20 × 126 =
##     2.5 kHz — so the source cannot alias at all. Differentiation, the SVFs, the
##     sub and the band-limited rasp add no harmonics either. The saturation is
##     the only generator of new ones, and it is acting on a signal that is
##     already almost all under 1 kHz.
func _roar() -> PackedFloat32Array:
	var rate := float(MIX_RATE)
	var n := int(ROAR_LEN * rate)
	var out := _buf(n)

	# Formant and rasp filter states, run inline because each sample's input
	# depends on the previous sample's source.
	var f_low := [0.0, 0.0, 0.0]
	var f_band := [0.0, 0.0, 0.0]
	var centres := [175.0, 520.0, 1180.0]
	var opens := [325.0, 990.0, 1500.0]
	var qs := [7.0, 9.0, 8.0]
	var mixes := [1.0, 0.62, 0.34]

	var rasp_low := 0.0
	var rasp_band := 0.0

	var phase := 0.0        # glottal cycle, 0..1
	var sub_phase := 0.0
	var jitter := 0.0
	var prev_pulse := 0.0

	for i in n:
		var t: float = float(i) / rate

		# Effort: silent for the intake, then a slightly accelerating climb to the
		# crest, then an exponential collapse.
		var eff := 0.0
		if t > 0.10:
			if t < ROAR_CREST:
				eff = pow((t - 0.10) / (ROAR_CREST - 0.10), 0.72)
			else:
				eff = exp(-(t - ROAR_CREST) * 1.55)
		eff = clampf(eff, 0.0, 1.0)

		# Fundamental. It rises with effort and droops as the bellow dies, which
		# is what a voice running out of air does.
		jitter = lerp(jitter, _synth_rng.randf_range(-1.0, 1.0), 0.35)
		var f0: float = (84.0 + 42.0 * eff) \
			* (1.0 + 0.045 * sin(TAU * 6.5 * t) + 0.02 * jitter)

		phase += f0 / rate
		phase -= floorf(phase)
		# The pulse, as five multiplies rather than pow(): this loop runs 54 000
		# times and pow() was the most expensive thing in it.
		var b: float = 0.5 * (1.0 + cos(TAU * phase))
		var b2: float = b * b
		var b4: float = b2 * b2
		var b8: float = b4 * b4
		var pulse: float = b8 * b8 * b4        # b^20
		var src: float = (pulse - prev_pulse) * 20.0
		prev_pulse = pulse

		var voice := 0.0
		var open: float = clampf(t / ROAR_CREST, 0.0, 1.0)
		for k in 3:
			var hz: float = lerp(float(centres[k]), float(opens[k]), open)
			var f: float = 2.0 * sin(PI * minf(hz, rate / 6.0) / rate)
			var damp: float = 1.0 / float(qs[k])
			var high: float = src - float(f_low[k]) - damp * float(f_band[k])
			f_band[k] = float(f_band[k]) + f * high
			f_low[k] = float(f_low[k]) + f * float(f_band[k])
			voice += float(f_band[k]) * damp * float(mixes[k])
		voice *= 6.0

		# Sub octave: the nine metres. Phase-accumulated so it stays continuous
		# through the fundamental's vibrato, and it leans in with effort rather
		# than sitting at a constant — a giant pushes harder as he opens up.
		sub_phase += TAU * (f0 * 0.5) / rate
		voice += sin(sub_phase) * 0.26 * (0.35 + 0.65 * eff)

		# Rasp, gated by the glottal pulse so it belongs to the voice.
		var rn: float = _synth_rng.randf_range(-1.0, 1.0)
		var rf: float = 2.0 * sin(PI * 2400.0 / rate)
		var rdamp := 0.45
		var rhigh: float = rn - rasp_low - rdamp * rasp_band
		rasp_band += rf * rhigh
		rasp_low += rf * rasp_band
		voice += rasp_band * rdamp * (0.35 + 0.65 * pulse) * 0.85 * pow(eff, 1.5)

		# The growl, across everything including the sub — a chest rattle shakes
		# the whole voice, not just the part of it that came out of the larynx.
		voice *= 1.0 - 0.45 * eff * (0.5 - 0.5 * cos(TAU * 29.0 * t))

		out[i] = tanh(1.3 * voice) / tanh(1.3) * eff

	# The intake: 300 ms of breath drawn in under the start of the voice, rising
	# in level and in brightness so it reads as filling rather than as noise.
	var inh := _noise(int(0.30 * rate))
	_bandpass(inh, 1500.0, 0.9, rate)
	for i in inh.size():
		var t: float = float(i) / rate
		var e: float = (t / 0.14) if t < 0.14 else maxf(0.0, 1.0 - (t - 0.14) / 0.16)
		inh[i] *= e
	_mix_into(out, inh, 0, 0.34)

	# The blast at the crest: the wave leaving his feet. Sub sweep plus a
	# closing-cutoff noise burst — deliberately under 100 Hz where the shipped
	# `boss_slam` (centroid 1.2 kHz) is not, so the two layer instead of masking.
	var blast_n := int(0.50 * rate)
	var blast := _buf(blast_n)
	var bp := 0.0
	for i in blast_n:
		var t: float = float(i) / rate
		var f: float = 78.0 * exp(-t * 2.6) + 30.0
		bp += TAU * f / rate
		var e: float = (t / 0.004) if t < 0.004 else exp(-(t - 0.004) * 7.0)
		blast[i] = sin(bp) * e * 0.9
	var brs := _noise(blast_n)
	_lowpass(brs, 900.0, rate)
	for i in blast_n:
		var t: float = float(i) / rate
		brs[i] *= exp(-t * 11.0)
	_mix_into(blast, brs, 0, 0.5)
	_mix_into(out, blast, int(ROAR_CREST * rate), 0.85)

	return _finish(out, 0.95, 0.05)


# --- Going over the side -----------------------------------------------------

const FALL_SPLASH_AT := 0.55   ## when the water arrives, seconds
const FALL_LEN := 1.45

## A hero going off the Dom Luís. Twenty health, and until now the only
## completely silent damage event in the game.
##
## SYNTHESISED, because the library has no water in it at all and nothing in it
## can be bent into any: the closest candidates are `dash` (a filtered noise
## swoosh, 1.8 s) and `rock_impact`, and a splash made of those is a swoosh
## followed by a rock.
##
## Two events with a hole between them, which is the whole point — 550 ms of
## receding whistle, 30 ms of nothing, then the river. The gap is what makes the
## height legible; without it the fall and the landing smear into one noise and
## the drop could be two metres.
func _fall() -> PackedFloat32Array:
	var rate := float(MIX_RATE)
	var out := _buf(int(FALL_LEN * rate))

	# The descent. An exponential pitch fall (980 -> 210 Hz) is what a receding
	# body sounds like; a linear one reads as a slide-whistle gag.
	var dn := int((FALL_SPLASH_AT - 0.03) * rate)
	var tone := _buf(dn)
	var phase := 0.0
	for i in dn:
		var u: float = float(i) / float(maxi(1, dn))
		var f: float = 980.0 * pow(210.0 / 980.0, u)
		phase += TAU * f / rate
		# Rises fast, then falls away as the hero gets further off — the level
		# curve IS the distance cue, the pitch alone is not enough.
		var t: float = float(i) / rate
		var e: float = minf(1.0, t / 0.03) * (1.0 - 0.62 * u)
		# A little second harmonic keeps it from being a pure test tone.
		tone[i] = (sin(phase) + 0.28 * sin(phase * 2.0)) * e * 0.55
	_mix_into(out, tone, 0, 1.0)

	# Wind past the ears, closing down as they recede.
	var wind := _noise(dn)
	for i in dn:
		var u: float = float(i) / float(maxi(1, dn))
		# Re-filtered in blocks would be cleaner; a single sweep of a one-pole
		# state is enough here and stays one pass.
		wind[i] *= 1.0 - 0.5 * u
	_lowpass(wind, 1400.0, rate)
	_highpass(wind, 180.0, rate)
	for i in dn:
		var t: float = float(i) / rate
		wind[i] *= minf(1.0, t / 0.06)
	_mix_into(out, wind, 0, 0.42)

	_mix_into(out, _splash(0.0), int(FALL_SPLASH_AT * rate), 1.0)
	return _finish(out, 0.93)


## The Douro taking something. Four layers, and the order they die in is what
## makes it water rather than a noise burst: the impact is broadband and gone in
## a quarter second, the displaced volume is a low sweep under it, the foam is a
## high hiss that outlives both, and then bubbles.
##
## `pre` is silence to leave at the head, for a caller assembling it into
## something longer.
func _splash(pre: float) -> PackedFloat32Array:
	var rate := float(MIX_RATE)
	var dur := 0.90
	var head := int(pre * rate)
	var n := int(dur * rate)
	var out := _buf(head + n)

	# Impact: a noise burst whose band collapses from 2.6 kHz to 300 Hz as the
	# hole in the water closes.
	var hit := _noise(n)
	_bandpass(hit, 1300.0, 0.8, rate)
	for i in n:
		var t: float = float(i) / rate
		hit[i] *= (t / 0.006) if t < 0.006 else exp(-(t - 0.006) / 0.12)
	_mix_into(out, hit, head, 0.90)

	# The volume displaced: a low sweep, 150 -> 55 Hz.
	var gulp := _buf(n)
	var phase := 0.0
	for i in n:
		var t: float = float(i) / rate
		var f: float = 55.0 + 95.0 * exp(-t * 9.0)
		phase += TAU * f / rate
		gulp[i] = sin(phase) * exp(-t / 0.16)
	_mix_into(out, gulp, head, 0.55)

	# Foam. Outlives the impact by half a second, which is the layer that says
	# "river" rather than "impact into something wet".
	var foam := _noise(n)
	_highpass(foam, 1800.0, rate)
	for i in n:
		var t: float = float(i) / rate
		foam[i] *= minf(1.0, t / 0.02) * exp(-t / 0.34)
	_mix_into(out, foam, head, 0.30)

	# Seven bubbles, rising in pitch as they surface and scattered through the
	# tail. Seeded, so the same fall sounds the same twice.
	for b in 7:
		var at: float = 0.16 + 0.62 * _synth_rng.randf()
		var bn := int(0.06 * rate)
		var bub := _buf(bn)
		var bp := 0.0
		var f0: float = _synth_rng.randf_range(240.0, 620.0)
		for i in bn:
			var u: float = float(i) / float(bn)
			bp += TAU * (f0 * (1.0 + 1.6 * u)) / rate
			bub[i] = sin(bp) * sin(PI * u) * _synth_rng.randf_range(0.10, 0.22)
		_mix_into(out, bub, head + int(at * rate), 1.0)

	return _finish(out, 0.88)
