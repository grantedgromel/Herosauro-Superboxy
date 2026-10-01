extends Node
## Screenshot helper for the storybook screens. Not shipped, not a probe.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##       --rendering-method gl_compatibility scripts/ui/_shots/shot.tscn \
##       -- --screen=page:adamastor:intro:3 --out=/tmp/shot.png [--size=1024x768] [--lang=en]
##       [--touch]   (hud/pause: the compact touch layout)
##
## Screens: title, shelf, who, who_hero, page:<chapter>:<part>:<index>,
## pages:<chapter> (a contact sheet of every page), settings, hud, pause,
## victory, sticker, tryagain, coach (controls card; --touch for the rings),
## coach_pad, hint (idle arrow at the edge), hint_on (idle arrow over a goal).

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
		elif a == "--touch":
			TouchControls.force = TouchControls.Force.ON
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
		"hud", "pause", "hud_nb":
			var cam := Camera3D.new()
			add_child(cam)
			cam.current = true
			if parts[0] != "hud_nb":
				var boss := Node3D.new()
				boss.add_to_group("boss")
				add_child(boss)
			var hud: Control = load("res://scenes/ui/hud.tscn").instantiate()
			_root.add_child(hud)
			GameManager.player_count = 1
			GameManager.human_hero = 1
			GameManager.companion = true
			GameManager.chapter_id = "adamastor" if parts[0] != "hud_nb" else "dragao"
			GameManager.start_game()
			GameManager.set_objective(StoryData.chapter(GameManager.chapter_id)["objective"], 4)
			GameManager.advance_objective(2)
			GameManager.request_story_beat("a09" if parts[0] != "hud_nb" else "d10")
			GameManager.damage_player(1, 30)
			if parts[0] == "pause":
				GameManager.change_state(GameManager.State.PAUSED)
		"coach", "coach_pad", "hint", "hint_on":
			_coach_scene(parts[0])
		"victory", "tryagain":
			var over: Control = load("res://scenes/ui/game_over.tscn").instantiate()
			_root.add_child(over)
			over.chapter_id = parts[1] if parts.size() > 1 else "adamastor"
			if parts[0] == "victory":
				over.call("_show_sticker")
			else:
				over.call("_show_retry")
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


## A stand-in street: floor, light, a crate as the goal, the live HUD on top.
func _coach_scene(kind: String) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fc8ec")
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c9a77a")
	plane.material = mat
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var goal := Vector3(-2.5, 0.0, -1.0) if kind == "hint_on" else Vector3(30.0, 0.0, -4.0)
	var crate := MeshInstance3D.new()
	var box := BoxMesh.new()
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color("d0473a")
	box.material = cmat
	crate.mesh = box
	add_child(crate)
	crate.position = goal + Vector3(0.0, 0.5, 0.0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 5.0, 11.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0))
	cam.current = true
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar target := Vector3.INF\nfunc hint_target() -> Vector3:\n\treturn target\n"
	gs.reload()
	var lv := Node3D.new()
	lv.set_script(gs)
	lv.set("target", goal)
	lv.add_to_group("level")
	add_child(lv)
	GameManager.player_count = 1
	GameManager.human_hero = 1
	GameManager.companion = true
	GameManager.chapter_id = "pandas"
	if kind.begins_with("hint"):
		UIProgress.set_pref(ControlsCard.PREF % "pandas", true)
	var hud: Control = load("res://scenes/ui/hud.tscn").instantiate()
	_root.add_child(hud)
	var card: ControlsCard = hud.get("_coach")
	if kind == "coach_pad":
		card.force_device = ControlsCard.Device.PAD
	elif kind == "coach" and TouchControls.force != TouchControls.Force.ON:
		card.force_device = ControlsCard.Device.KEYS
	GameManager.start_game()
	GameManager.set_objective(StoryData.chapter("pandas")["objective"], 8)
	GameManager.advance_objective(3)
	if kind.begins_with("coach"):
		card.done[ControlsCard.Act.MOVE] = true
		card.queue_redraw()
	else:
		var hint: IdleHint = hud.get("_hint")
		hint.step(IdleHint.SHOW_AT + 0.5)
