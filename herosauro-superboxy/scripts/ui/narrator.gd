class_name Narrator
extends Node
## Reads text aloud and reports which word is being said, for the read-along
## highlight. Voice first: most players cannot read the page themselves.
##
## Three sources, best first:
##   1. a recorded file, res://assets/story/voice/<lang>/<page_id>.ogg, when
##      one exists (the owner's own voice beats any synthesiser);
##   2. the platform's text-to-speech, preferring a European Portuguese voice
##      (then Brazilian) for "pt" and British (then American) English for "en",
##      at a slightly slow rate;
##   3. nothing audible, but the highlight still walks the words at a reading
##      pace, so the page behaves the same with the sound off.
##
## The highlight follows the TTS word-boundary callback where the platform
## sends one. Where it does not (or for a recorded file) the word timing is an
## estimate weighted by word length and punctuation.
##
## TTS needs the project setting audio/general/text_to_speech. Without it,
## every DisplayServer.tts_* call prints an engine error, so this checks the
## setting first and degrades silently to source 3.
##
## Timing is accumulated from `delta`, never read off the wall clock
## (ARCHITECTURE.md rule 5).

signal word_changed(index: int)
signal finished()

const VOICE_DIR := "res://assets/story/voice/%s/%s.ogg"
const RATE := 0.88
## Estimated pace at RATE, in seconds per character of a word, plus fixed
## costs per word and per pause. Tuned so a 30-word page reads in ~12 s.
const SEC_PER_CHAR := 0.062
const SEC_PER_WORD := 0.14
const PAUSE_COMMA := 0.30
const PAUSE_STOP := 0.55

## Starts of each word in the spoken text, as character offsets.
var word_starts: PackedInt32Array = PackedInt32Array()
var words: PackedStringArray = PackedStringArray()

var _speaking := false
var _mode := 0   # 0 none, 1 tts, 2 recorded, 3 silent estimate
var _utterance := 0
var _clock := 0.0
var _times: PackedFloat32Array = PackedFloat32Array()   # estimated start of each word
var _total := 0.0
var _word := -1
var _got_boundary := false
var _player: AudioStreamPlayer

static var _next_id := 1000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	add_child(_player)
	set_process(false)


func _exit_tree() -> void:
	stop()


## True when the platform can actually speak.
static func tts_available() -> bool:
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return false
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


## Best voice id for a language, or "" if the platform has none for it.
static func pick_voice(lang: String) -> String:
	if not tts_available():
		return ""
	var prefs: Array = ["pt_pt", "pt_br", "pt"] if lang == "pt" else ["en_gb", "en_us", "en"]
	var voices: Array = DisplayServer.tts_get_voices()
	for want: String in prefs:
		for v: Dictionary in voices:
			var code := str(v.get("language", "")).to_lower().replace("-", "_")
			if code == want or (want.length() == 2 and code.begins_with(want)):
				return str(v.get("id", ""))
	return ""


static func voice_path(lang: String, page_id: String) -> String:
	return VOICE_DIR % [lang, page_id]


## Speak `text` in `lang`. `page_id`, when given, lets a recorded file stand
## in for TTS. `audible` false walks the highlight without making a sound
## (narration switched off in Settings still gets the read-along pace).
func speak(text: String, lang: String, page_id: String = "", audible: bool = true) -> void:
	stop()
	_split(text)
	_estimate()
	_clock = 0.0
	_word = -1
	_got_boundary = false
	_speaking = true
	_mode = 3

	if audible:
		var path := voice_path(lang, page_id) if not page_id.is_empty() else ""
		if not path.is_empty() and ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				_player.stream = stream
				_player.play()
				_mode = 2
				var length := stream.get_length()
				if length > 0.5 and _total > 0.0:
					var k := length / _total
					for i in _times.size():
						_times[i] *= k
					_total = length
		if _mode == 3:
			var voice := pick_voice(lang)
			if not voice.is_empty():
				_hook_callbacks()
				_next_id += 1
				_utterance = _next_id
				DisplayServer.tts_speak(text, voice, 100, 1.0, RATE, _utterance, true)
				_mode = 1
	set_process(true)
	_set_word(0)


func stop() -> void:
	if _mode == 1 and tts_available():
		DisplayServer.tts_stop()
	if _player != null and _player.playing:
		_player.stop()
	var was := _speaking
	_speaking = false
	_mode = 0
	_utterance = 0
	set_process(false)
	if was:
		_word = -1


func is_speaking() -> bool:
	return _speaking


func current_word() -> int:
	return _word


## How long the estimate says this text takes, in seconds.
func estimated_length() -> float:
	return _total


func _process(delta: float) -> void:
	if not _speaking:
		return
	_clock += delta
	# The boundary callback, when it arrives, owns the highlight; the estimate
	# only drives it until the first boundary (or forever, on platforms that
	# never send one).
	if not _got_boundary:
		var i := _word
		while i + 1 < _times.size() and _clock >= _times[i + 1]:
			i += 1
		_set_word(i)
	match _mode:
		2:
			if not _player.playing and _clock > 0.2:
				_finish()
		1:
			# Safety net: some platforms never report the end of an utterance.
			if _clock > _total * 1.8 + 3.0:
				_finish()
		3:
			if _clock >= _total + 0.4:
				_finish()


func _finish() -> void:
	if not _speaking:
		return
	_speaking = false
	_mode = 0
	set_process(false)
	_set_word(words.size() - 1)
	finished.emit()


func _set_word(i: int) -> void:
	if i == _word or i < 0 or i >= words.size():
		return
	_word = i
	word_changed.emit(i)


func _split(text: String) -> void:
	words = PackedStringArray()
	word_starts = PackedInt32Array()
	var i := 0
	var n := text.length()
	while i < n:
		while i < n and _is_space(text.unicode_at(i)):
			i += 1
		if i >= n:
			break
		var start := i
		while i < n and not _is_space(text.unicode_at(i)):
			i += 1
		words.append(text.substr(start, i - start))
		word_starts.append(start)


static func _is_space(c: int) -> bool:
	return c == 32 or c == 9 or c == 10 or c == 13 or c == 0xA0


func _estimate() -> void:
	_times = PackedFloat32Array()
	var t := 0.25
	for w in words:
		_times.append(t)
		t += SEC_PER_WORD + SEC_PER_CHAR * w.length()
		var last := w.right(1)
		if last in [",", ";", ":", "—"]:
			t += PAUSE_COMMA
		elif last in [".", "!", "?", "…", "\""]:
			t += PAUSE_STOP
	_total = t


# --- TTS callbacks -----------------------------------------------------------------
#
# The callbacks are global to the DisplayServer, so whichever Narrator spoke
# last owns them; the utterance id filters out anything from an older one.

func _hook_callbacks() -> void:
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_BOUNDARY,
		_on_tts_boundary)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_tts_ended)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED,
		_on_tts_canceled)


func _on_tts_boundary(pos: int, id: int) -> void:
	if id != _utterance or not _speaking:
		return
	_got_boundary = true
	var lo := 0
	for i in word_starts.size():
		if word_starts[i] <= pos:
			lo = i
		else:
			break
	_set_word.call_deferred(lo)


func _on_tts_ended(id: int) -> void:
	if id == _utterance and _speaking:
		_finish.call_deferred()


func _on_tts_canceled(id: int) -> void:
	if id == _utterance:
		_speaking = false
