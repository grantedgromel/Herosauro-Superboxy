extends Node
## What the HUD costs the renderer in a live level. Not shipped, not a probe.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##       --rendering-method gl_compatibility scripts/ui/_shots/hud_cost.tscn \
##       -- --chapter=dragao [--players=1|2] [--busy] [--touch] [--size=1024x768] \
##       [--out=/tmp/hud.png] [--frames=120] [--budget=90] [--breakdown]
##
## Boots main.tscn into the chapter, lets it settle, then reads the root
## viewport's CANVAS draw calls over several frames with the HUD shown and
## again with it hidden. The difference is the HUD's own cost; the rest of the
## 2D frame (the touch overlay, anything a level draws in 2D) is what is left.
## --busy puts every transient widget up at once (a combo on both heroes, a
## story toast, damage numbers, the invincible pill): the worst gameplay frame.
## --touch forces the touch overlay on, so its cost and its layout show too.

const MainScene := preload("res://scenes/main.tscn")

var _out := ""
var _chapter := "dragao"
var _players := 1
var _busy := false
var _touch := false
var _frames := 120


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--chapter="):
			_chapter = a.substr(10)
		elif a.begins_with("--players="):
			_players = int(a.substr(10))
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a == "--busy":
			_busy = true
		elif a == "--touch":
			_touch = true
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			get_window().size = Vector2i(int(p[0]), int(p[1]))
	UIProgress.use_memory_only()
	GameManager.assists = true
	GameManager.companion = true
	GameManager.narration = false
	GameManager.set_player_count(_players)
	GameManager.set_human_hero(1)
	if _touch:
		TouchControls.force = TouchControls.Force.ON
	var main := MainScene.instantiate()
	add_child(main)
	await _wait(4)
	GameManager.set_chapter(_chapter)
	GameManager.start_game()
	await _wait(_frames)
	var hud := _find_hud(main)
	if _busy:
		GameManager.combo_changed.emit(1, 7)
		GameManager.combo_changed.emit(2, 3)
		GameManager.damage_player(1, 12)
		var beats: Array = StoryData.chapter(_chapter).get("beats", [])
		if not beats.is_empty():
			GameManager.request_story_beat(str(beats[beats.size() - 1].get("id", "")))
		await _wait(20)
	var with_hud := await _sample(6)
	var items := _visible_items(hud)
	if OS.get_cmdline_user_args().has("--breakdown"):
		await _breakdown(hud, with_hud, 0)
	hud.visible = false
	var without := await _sample(6)
	hud.visible = true
	await _wait(2)
	var total := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("[hud cost] chapter=%s players=%d busy=%s touch=%s size=%s" % [
		_chapter, _players, str(_busy), str(_touch), str(get_viewport().get_visible_rect().size)])
	print("[hud cost] canvas draw calls: with HUD %d, without %d, HUD = %d; visible HUD canvas items %d; whole frame %d" % [
		with_hud, without, with_hud - without, items, total])
	print("[hud cost] icon atlas: %d stamps, %.0f%% full" % [IconAtlas.shared().stamp_count(),
		IconAtlas.shared().fill() * 100.0])
	if _out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out)
		print("[hud cost] saved %s" % _out)
		var sheet := IconAtlas.shared().get_texture().get_image()
		sheet.save_png(_out.replace(".png", "_atlas.png"))
	# --budget=N makes this a gate: exit 1 when the HUD costs more than N.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--budget=") and with_hud - without > int(a.substr(9)):
			print("[hud cost] OVER BUDGET: %d > %s" % [with_hud - without, a.substr(9)])
			get_tree().quit(1)
			return
	get_tree().quit()


func _sample(n: int) -> int:
	var worst := 0
	for i in n:
		await RenderingServer.frame_post_draw
		worst = maxi(worst, int(get_viewport().get_render_info(
			Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)))
	return worst


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find_hud(main: Node) -> Control:
	for c in main.get_node("UI").get_children():
		if c.get_script() == load("res://scripts/ui/hud.gd"):
			return c
	return null


## Hide each visible item in turn and print what the frame saves.
func _breakdown(n: Node, base: int, depth: int) -> void:
	for c in n.get_children():
		if not (c is CanvasItem) or not (c as CanvasItem).visible:
			continue
		(c as CanvasItem).visible = false
		var without := await _sample(2)
		(c as CanvasItem).visible = true
		var cost := base - without
		print("[hud cost] %s%s (%s) = %d over %d items" % [
			"  ".repeat(depth), c.name, c.get_class(), cost, _visible_items(c)])
		if cost > 6 and depth < 3:
			await _breakdown(c, base, depth + 1)


static func _visible_items(n: Node) -> int:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return 0
	var count := 1 if n is CanvasItem else 0
	for c in n.get_children():
		count += _visible_items(c)
	return count
