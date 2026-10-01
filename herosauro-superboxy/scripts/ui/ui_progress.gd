class_name UIProgress
extends RefCounted
## Tiny persistent record: which storybook chapters are finished, the stickers
## they earned, the last "who is playing" choice, and the old best-run records.
##
## A results card that only shows the run you just finished has nothing to say;
## one that shows it against your best turns a loss into a target. This is UI
## state, not game state, so it lives here rather than in GameManager — no
## gameplay code has to know it exists.
##
## Written to user:// as a ConfigFile: a couple of ints, human-readable, and
## safe to delete.

const PATH := "user://progress.cfg"
const SECTION := "records"


## Per-chapter storybook state. Each chapter id from StoryData.ORDER gets a
## `completed` flag and a sticker count; reading the old `records` section is
## untouched, so a save written before the storybook still loads.
const CHAPTERS := "chapters"
## Remembered choices (who's playing), so the second session starts where the
## first one left off.
const PREFS := "prefs"

static var _cache: ConfigFile = null
## True while a probe runs against an in-memory file: nothing is written to
## user://, so a test run never changes a child's real stickers.
static var _volatile := false
## The chapter whose sticker was awarded most recently and has not been shown
## on the shelf yet. The shelf plays the sticker landing once, then clears it.
static var fresh_sticker: String = ""


static func _cfg() -> ConfigFile:
	if _cache != null:
		return _cache
	_cache = ConfigFile.new()
	# A missing file on a first run is the normal case, not an error.
	_cache.load(PATH)
	return _cache


static func _save() -> void:
	if not _volatile:
		_cfg().save(PATH)


## Probes only: swap in an empty, never-saved progress file.
static func use_memory_only() -> void:
	_cache = ConfigFile.new()
	_volatile = true
	fresh_sticker = ""


static func is_complete(chapter_id: String) -> bool:
	return bool(_cfg().get_value(CHAPTERS, chapter_id + "_done", false))


static func stickers(chapter_id: String) -> int:
	return int(_cfg().get_value(CHAPTERS, chapter_id + "_stickers", 0))


## Record a finished chapter: the flag goes up (never down) and the chapter
## earns one more sticker. Progress only ever increases.
static func complete_chapter(chapter_id: String) -> void:
	var cfg := _cfg()
	cfg.set_value(CHAPTERS, chapter_id + "_done", true)
	cfg.set_value(CHAPTERS, chapter_id + "_stickers", stickers(chapter_id) + 1)
	fresh_sticker = chapter_id
	_save()


static func completed_count() -> int:
	var n := 0
	for id: String in StoryData.ORDER:
		if is_complete(id):
			n += 1
	return n


## The first chapter in book order that is not finished yet; "" when the
## whole book is done.
static func next_unfinished() -> String:
	for id: String in StoryData.ORDER:
		if not is_complete(id):
			return id
	return ""


static func get_pref(key: String, default_value: Variant) -> Variant:
	return _cfg().get_value(PREFS, key, default_value)


static func set_pref(key: String, value: Variant) -> void:
	_cfg().set_value(PREFS, key, value)
	_save()


static func best_score() -> int:
	return int(_cfg().get_value(SECTION, "best_score", 0))


## Fastest winning time in seconds, or -1 when the boss has never been beaten.
static func best_time() -> float:
	return float(_cfg().get_value(SECTION, "best_time", -1.0))


static func wins() -> int:
	return int(_cfg().get_value(SECTION, "wins", 0))


## Record a finished run. Returns true when it set a new score record, so the
## results card can call it out.
static func submit(score: int, seconds: float, victory: bool) -> bool:
	var cfg := _cfg()
	var beat := score > best_score()
	if beat:
		cfg.set_value(SECTION, "best_score", score)
	if victory:
		cfg.set_value(SECTION, "wins", wins() + 1)
		var prev := best_time()
		if prev < 0.0 or seconds < prev:
			cfg.set_value(SECTION, "best_time", seconds)
	_save()
	return beat


## m:ss, the format used everywhere a duration is shown.
static func format_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]


## 1240 -> "1,240". A long score read as one run of digits is a number nobody
## can compare against their last one, which defeats the point of showing it.
static func format_score(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
