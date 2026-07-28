class_name UIProgress
extends RefCounted
## Tiny persistent record of the player's best run.
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

static var _cache: ConfigFile = null


static func _cfg() -> ConfigFile:
	if _cache != null:
		return _cache
	_cache = ConfigFile.new()
	# A missing file on a first run is the normal case, not an error.
	_cache.load(PATH)
	return _cache


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
	cfg.save(PATH)
	return beat


## m:ss, the format used everywhere a duration is shown.
static func format_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]
