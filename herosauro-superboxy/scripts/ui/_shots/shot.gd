extends Node
## Screenshot helper for the storybook screens. Not shipped, not a probe.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##       --rendering-method gl_compatibility scripts/ui/_shots/shot.tscn \
##       -- --screen=page:adamastor:intro:3 --out=/tmp/shot.png [--size=1024x768] [--lang=en]
##
## Screens: title, shelf, who, who_hero, page:<chapter>:<part>:<index>,
## pages:<chapter> (a contact sheet of every page), settings, hud, pause,
## victory, sticker, tryagain.

var _out := "/tmp/shot.png"
var _screen := "shelf"
var _root: Control


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--screen="):
			_screen = a.substr(9)
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			get_window().size = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--lang="):
			GameManager.language = a.substr(7)
	UIProgress.use_memory_only()
	if _screen.contains("done"):
		UIProgress.complete_chapter("adamastor")
		UIProgress.fresh_sticker = ""
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_root)
	await get_tree().process_frame
	_build()
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("[shot] saved %s %s" % [_out, str(img.get_size())])
	get_tree().quit()


func _build() -> void:
	var parts := _screen.split(":")
	match parts[0]:
		"page":
			var art := PageArt.new()
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_root.add_child(art)
			var ch := StoryData.chapter(parts[1])
			var pg: Dictionary = ch[parts[2]][int(parts[3])]
			art.setup(parts[1], pg, parts[2], Loc.pick(pg))
		"pages":
			_contact_sheet(parts[1])
		"reader":
			var r := PageReader.new()
			r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_root.add_child(r)
			r.open(parts[1], parts[2], int(parts[3]) if parts.size() > 3 else 0)
		_:
			var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
			_root.add_child(menu)
			await get_tree().process_frame
			if menu.has_method("debug_show"):
				menu.debug_show(_screen)


func _contact_sheet(chapter: String) -> void:
	var ch := StoryData.chapter(chapter)
	var pages: Array = []
	for part in ["intro", "outro"]:
		for pg in ch[part]:
			pages.append([part, pg])
	var cols := 4
	var vp := get_viewport().get_visible_rect().size
	var w := vp.x / cols
	var h := w * 9.0 / 16.0
	for i in pages.size():
		var art := PageArt.new()
		art.position = Vector2((i % cols) * w, (i / cols) * h)
		art.size = Vector2(w - 4, h - 4)
		_root.add_child(art)
		art.setup(chapter, pages[i][1], pages[i][0], Loc.pick(pages[i][1]))
		var tag := UIStyle.label(str(pages[i][1]["id"]), 18, Color.WHITE, true)
		tag.position = art.position + Vector2(8, 4)
		_root.add_child(tag)
