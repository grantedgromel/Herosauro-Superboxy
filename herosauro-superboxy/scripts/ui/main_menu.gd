extends Control
## The storybook frame around the game: everything the player sees while
## GameManager is in MENU. (main.gd instances this scene and shows it in MENU;
## the outro after a win runs in game_over.gd, in VICTORY.)
##
##   Toca para começar ─► Estante (3 books) ─► who's playing (1 or 2)
##      ─► intro pages ─► set_chapter + start_game ─► (the level)
##
## Screens are siblings under this node, shown one at a time with a short
## cross-fade. The title appears once per session; coming back from a run
## (pause ▸ back to the book, or after the outro) lands on the shelf with the
## next story highlighted and any new sticker landing on its cover.
##
## Every screen is 2D. The menu builds no 3D world at all (see
## scripts/ui/menu/_menu_probe.gd for why that is locked down), and the
## curtain still covers main.gd's blocking arena build on the way in.
##
## Voice first: each screen says what it wants out loud when Narração is on.

const FADE := 0.22
const CURTAIN_TIME := 0.28

var screen: String = ""
var chapter_id: String = ""

var title: TitleScreen
var shelf: Bookshelf
var who: WhoPlays
var reader: PageReader
var settings: SettingsPanel

var _curtain: ColorRect
var _voice: Narrator
var _title_done := false
var _leaving := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	title = TitleScreen.new()
	title.name = "Title"
	add_child(title)
	title.started.connect(func() -> void:
		_title_done = true
		go("shelf"))

	shelf = Bookshelf.new()
	shelf.name = "Shelf"
	add_child(shelf)
	shelf.chapter_chosen.connect(choose_chapter)
	shelf.settings_requested.connect(open_settings)

	who = WhoPlays.new()
	who.name = "Who"
	add_child(who)
	who.chosen.connect(choose_players)
	who.back_requested.connect(func() -> void: go("shelf"))

	reader = PageReader.new()
	reader.name = "Reader"
	add_child(reader)
	reader.finished.connect(func(_skipped: bool) -> void: start_chapter())
	reader.back_requested.connect(func() -> void: go("who"))

	settings = SettingsPanel.new()
	settings.name = "Settings"
	add_child(settings)
	settings.closed.connect(_on_settings_closed)

	_voice = Narrator.new()
	_voice.name = "Voice"
	add_child(_voice)

	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = UIStyle.BASE
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.modulate.a = 0.0
	add_child(_curtain)

	for s in [title, shelf, who]:
		s.visible = false
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if not visible:
		_voice.stop()
		reader.close()
		return
	_leaving = false
	_curtain.modulate.a = 0.0
	go("shelf" if _title_done else "title", true)


# --- Navigation --------------------------------------------------------------------

## Show one screen. `instant` skips the cross-fade (boot, coming back from play).
func go(which: String, instant: bool = false) -> void:
	var prev := screen
	screen = which
	_voice.stop()
	if which != "reader":
		reader.close()
	var target: Control = _screen_node(which)
	for s: Control in [title, shelf, who]:
		if s != target:
			s.visible = false
	if target == null:
		return
	target.visible = true
	if not instant and prev != which:
		target.modulate.a = 0.0
		create_tween().tween_property(target, "modulate:a", 1.0, FADE)
	else:
		target.modulate.a = 1.0
	if target.has_method("enter"):
		target.call("enter")
	match which:
		"shelf":
			_say("shelf_prompt")
		"who":
			_say("who_title")


func _screen_node(which: String) -> Control:
	match which:
		"title":
			return title
		"shelf":
			return shelf
		"who":
			return who
		"reader":
			return reader
	return null


func choose_chapter(id: String) -> void:
	chapter_id = id
	go("who")


## From the who's-playing screen. Solo always brings the other brother along
## as the AI companion; the choice is remembered for next time.
func choose_players(players: int, hero: int) -> void:
	GameManager.set_player_count(players)
	GameManager.set_human_hero(hero)
	if players <= 1 and not GameManager.companion:
		GameManager.set_companion(true)
	UIProgress.set_pref("players", players)
	UIProgress.set_pref("hero", hero)
	open_reader()


func open_reader() -> void:
	if chapter_id.is_empty():
		chapter_id = shelf.suggested_chapter()
	go("reader")
	reader.modulate.a = 0.0
	reader.open(chapter_id, "intro")
	create_tween().tween_property(reader, "modulate:a", 1.0, FADE)


## The intro is over (read or skipped): pick the chapter and start the run.
## The curtain covers main.gd's arena build, which blocks the main thread.
func start_chapter() -> void:
	if _leaving:
		return
	_leaving = true
	_voice.stop()
	reader.close()
	if chapter_id.is_empty():
		chapter_id = shelf.suggested_chapter()
	shelf.return_focus = ""
	var tw := create_tween()
	tw.tween_property(_curtain, "modulate:a", 1.0, CURTAIN_TIME)
	tw.tween_callback(func() -> void:
		GameManager.set_chapter(chapter_id)
		GameManager.start_game())


func open_settings() -> void:
	settings.open()


func _on_settings_closed() -> void:
	if screen == "shelf":
		shelf.enter()


func _say(loc_id: String) -> void:
	if GameManager.narration:
		_voice.speak(Loc.t(loc_id), Loc.lang())


## Shots and probes: jump straight to a screen.
func debug_show(which: String) -> void:
	_title_done = true
	match which:
		"title":
			_title_done = false
			go("title", true)
		"shelf", "shelf_done":
			go("shelf", true)
		"who":
			chapter_id = "adamastor"
			go("who", true)
		"who_hero":
			chapter_id = "adamastor"
			go("who", true)
			who.show_step(1)
		"settings":
			go("shelf", true)
			open_settings()
		_:
			go("shelf", true)
