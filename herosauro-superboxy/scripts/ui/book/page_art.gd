class_name PageArt
extends Control
## One page's picture, filling this control.
##
## If the book's painted page exists at the StoryData `art` path it is shown,
## cropped to cover. Until the owner drops those files in, the page is
## COMPOSED: the chapter's place drawn in code (PageScene), the characters on
## the page from the committed portrait art, the story's props, and a big comic
## sound-word when the text has one. Never an error for a missing file.
##
## The composition table below says who and what is on each page. A page it
## does not know (a new id in StoryData) still gets a sensible picture: the
## cast is read out of the text and the props default per chapter.

const HERO_H := 400.0     # design px, Herosauro standing
const BOXY_H := 330.0     # Kiko is the younger brother
const GIANT_H := 900.0

## Who and what is on each page. cast entries: [who, x, scale, tilt_deg, lift].
## `lift` raises the feet off the ground line (flying) or, negative, sinks them
## (Adamastor rising out of the river).
const PAGES := {
	"a01": {"cast": [["herosauro", 600, 1.0, 0, 0], ["superboxy", 860, 1.0, 0, 0]]},
	"a02": {"cast": [["herosauro", 560, 1.12, -4, 0], ["superboxy", 860, 1.12, 4, 0]],
		"props": ["sparkles"]},
	"a03": {"cast": [["adamastor", 1080, 1.0, 0, -170]], "props": ["splashes"]},
	"a04": {"cast": [["adamastor", 1180, 1.0, 6, -40], ["herosauro", 300, 0.82, 0, 0],
		["superboxy", 500, 0.82, 0, 0]]},
	"a05": {"cast": [["superboxy", 700, 1.15, -12, 60], ["adamastor", 1280, 0.9, 4, -60]]},
	"a07": {"cast": [["superboxy", 760, 1.25, -6, 30]], "props": ["sparkles"]},
	"a08": {"cast": [["herosauro", 380, 0.95, -14, 170], ["superboxy", 620, 0.95, -14, 230],
		["adamastor", 1230, 1.0, -4, -30]]},
	"a14": {"cast": [["adamastor", 1120, 1.0, 28, -330]], "front": ["splash"]},
	"a15": {"cast": [["herosauro", 620, 1.08, 0, 0], ["superboxy", 900, 1.08, 0, 0]],
		"props": ["sparkles"]},
	"d01": {"props": ["van"]},
	"d02": {"props": ["goblin_chief"]},
	"d03": {"props": ["cups", "goblins"]},
	"d04": {"props": ["dragon_sleep", "goblins"]},
	"d05": {"props": ["dragon_tied", "goblins"]},
	"d06": {"props": ["dragon_tied", "goblin_sack"]},
	"d07": {"cast": [["herosauro", 560, 0.95, 0, 0], ["superboxy", 820, 0.95, 0, 0]],
		"props": ["window", "signals"]},
	"d08": {"cast": [["herosauro", 560, 1.0, -14, 200], ["superboxy", 880, 1.0, -14, 250]],
		"props": ["sparkles"]},
	"d11": {"props": ["dragon", "van", "fire"]},
	"d12": {"cast": [["herosauro", 480, 1.0, 0, 0]], "props": ["goblins"]},
	"d13": {"scene": "adamastor", "props": ["splashes", "goblins"], "word": "SPLASH!"},
	"d14": {"cast": [["herosauro", 420, 1.0, 0, 0], ["superboxy", 660, 1.0, 0, 0]],
		"props": ["cup_pair", "sparkles"]},
	"p01": {"props": ["pandas", "suitcases"]},
	"p02": {"scene": "adamastor", "props": ["pandas", "nata"]},
	"p03": {"props": ["pandas_sad", "suitcases"]},
	"p04": {"props": ["pandas_sad", "suitcases"]},
	"p05": {"cast": [["herosauro", 560, 0.95, 0, 0], ["superboxy", 820, 0.95, 0, 0]],
		"props": ["window"]},
	"p06": {"cast": [["herosauro", 360, 0.95, 0, 0], ["superboxy", 600, 0.95, 0, 0]],
		"props": ["pandas_sad"]},
	"p09": {"cast": [["herosauro", 360, 0.95, 0, 0], ["superboxy", 600, 0.95, 0, 0]],
		"props": ["pandas", "sparkles"]},
	"p10": {"props": ["pandas", "icecream"]},
	"p11": {"cast": [["herosauro", 420, 1.0, 0, 0], ["superboxy", 680, 1.0, 0, 0]],
		"props": ["pandas"]},
}

## Sound-words worth a burst, as they appear in the book's text.
const WORDS := ["RROOAAARRR", "CRASH", "SPLASH", "PUMBA", "WHAM", "BOOM", "POW"]

var page: Dictionary = {}
var chapter_id: String = ""
var has_painted_art := false
var word: String = ""

var _scene: PageScene
var _cast: Array[Control] = []
var _cast_base: Array[Vector2] = []
var _burst: Control
var _clock := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _ready() -> void:
	resized.connect(_relayout)
	_relayout()


## `text` is the page's words in the current language; it decides the
## sound-word and, for an unknown page, the cast.
func setup(chapter: String, entry: Dictionary, part: String, text: String) -> void:
	chapter_id = chapter
	page = entry
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_cast.clear()
	_cast_base.clear()
	_scene = null
	_burst = null
	word = ""

	var art_path := str(entry.get("art", ""))
	has_painted_art = not art_path.is_empty() and ResourceLoader.exists(art_path)
	if has_painted_art:
		var tex := load(art_path) as Texture2D
		has_painted_art = tex != null
		if has_painted_art:
			var tr := TextureRect.new()
			tr.name = "PaintedPage"
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(tr)
			return
	_compose(chapter, entry, part, text)
	_relayout()


func _compose(chapter: String, entry: Dictionary, part: String, text: String) -> void:
	var id := str(entry.get("id", ""))
	var spec: Dictionary = PAGES.get(id, {})
	var scene_id := str(spec.get("scene", chapter))
	var props: Array = spec.get("props", [])
	var cast: Array = spec.get("cast", [])
	if spec.is_empty():
		cast = _guess_cast(text)

	_scene = PageScene.new()
	_scene.name = "ComposedPage"
	_scene.configure(scene_id, part, props, hash(id) & 0xFFFF)
	add_child(_scene)

	for entry_cast in cast:
		_add_figure(str(entry_cast[0]), float(entry_cast[1]), float(entry_cast[2]),
			float(entry_cast[3]), float(entry_cast[4]))

	var front: Array = spec.get("front", [])
	if not front.is_empty():
		var over := PageScene.new()
		over.name = "FrontProps"
		over.backdrop = false
		over.configure(scene_id, part, front, hash(id) & 0xFFFF)
		over.position = Vector2.ZERO
		_scene.add_child(over)

	word = str(spec.get("word", "")) if spec.has("word") else find_word(text)
	if not word.is_empty():
		var burst := SoundBurst.new()
		burst.name = "SoundWord"
		burst.text = word
		_scene.add_child(burst)
		burst.position = Vector2(1220, 170) if not _cast_on_right() else Vector2(360, 160)
		burst.pop(BookKit.reduce_motion())
		_burst = burst


static func find_word(text: String) -> String:
	for w: String in WORDS:
		if text.contains(w):
			return w + "!"
	if text.to_lower().contains("boxy boxy"):
		return "BOXY BOXY!"
	return ""


func _guess_cast(text: String) -> Array:
	var who := BookKit.cast_in(text)
	var out: Array = []
	var x := 520.0
	for w in who:
		if w == "adamastor":
			out.append([w, 1180, 1.0, 0, -60])
		else:
			out.append([w, x, 1.0, 0, 0])
			x += 260.0
	return out


func _cast_on_right() -> bool:
	for c in _cast:
		if c.position.x + c.size.x * 0.5 > 1000.0 and c.position.y < 300.0:
			return true
	return false


func _add_figure(who: String, x: float, k: float, tilt: float, lift: float) -> void:
	var actor := BookKit.actor_of(who)
	var h := GIANT_H if who == "adamastor" else (BOXY_H if who == "superboxy" else HERO_H)
	h *= k
	var tex := UIStyle.portrait_scaled(actor, 560 if who != "adamastor" else 900)
	var aspect := float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	var w := h * aspect
	var feet := Vector2(x, PageScene.GROUND_Y + 28.0 - lift)

	# Contact shadow first, so the figure stands on it (a figure floating on
	# its own is the fastest way to look pasted in).
	if lift < 60.0 and lift > -60.0:
		var shadow := _Shadow.new()
		shadow.position = feet - Vector2(w * 0.55, 18)
		shadow.size = Vector2(w * 1.1, 36)
		_scene.add_child(shadow)

	var tr := TextureRect.new()
	tr.name = "Cast_" + who
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = Vector2(w, h)
	tr.position = feet - Vector2(w * 0.5, h)
	tr.pivot_offset = Vector2(w * 0.5, h)
	tr.rotation_degrees = tilt
	_scene.add_child(tr)
	_cast.append(tr)
	_cast_base.append(tr.position)
	tr.set_meta("flying", lift >= 60.0)


func cast_names() -> Array[String]:
	var out: Array[String] = []
	for c in _cast:
		out.append(str(c.name).trim_prefix("Cast_"))
	return out


func _relayout() -> void:
	if _scene == null:
		return
	var t := PageScene.cover_transform(size)
	_scene.scale = Vector2(t[0], t[0])
	_scene.position = t[1]


func _process(delta: float) -> void:
	if _cast.is_empty() or BookKit.reduce_motion():
		return
	_clock += delta
	for i in _cast.size():
		var flying: bool = _cast[i].get_meta("flying", false)
		var amp := 14.0 if flying else 4.0
		var speed := 1.6 if flying else 2.2
		_cast[i].position = _cast_base[i] + Vector2(0, sin(_clock * speed + i * 1.7) * amp)


## Soft contact shadow under a standing figure.
class _Shadow extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		for i in 3:
			var k := 1.0 - i * 0.22
			var pts := PackedVector2Array()
			for a in 24:
				var t := TAU * a / 24.0
				pts.append(c + Vector2(cos(t) * c.x * k, sin(t) * c.y * k))
			draw_colored_polygon(pts, Color(0.05, 0.03, 0.06, 0.16))
