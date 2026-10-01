extends Node

var _root: Control

class Drawer extends Control:
	var kind := ""
	func _draw() -> void:
		match kind:
			"rects4":
				for i in 4:
					draw_rect(Rect2(i * 10, 0, 8, 8), Color.RED)
			"circles4":
				for i in 4:
					draw_circle(Vector2(i * 20 + 10, 10), 8, Color.RED)
			"circles4_aa":
				for i in 4:
					draw_circle(Vector2(i * 20 + 10, 10), 8, Color.RED, true, -1.0, true)
			"poly4":
				for i in 4:
					draw_colored_polygon(PackedVector2Array([Vector2(i*20,0), Vector2(i*20+10,0), Vector2(i*20+5,10)]), Color.RED)
			"lines4":
				for i in 4:
					draw_line(Vector2(i * 10, 0), Vector2(i * 10, 20), Color.RED, 3.0)
			"lines4_aa":
				for i in 4:
					draw_line(Vector2(i * 10, 0), Vector2(i * 10, 20), Color.RED, 3.0, true)
			"sbf4":
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color.RED
				sb.set_corner_radius_all(8)
				for i in 4:
					draw_style_box(sb, Rect2(i * 30, 0, 24, 24))
			"sbf4_shadow":
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color.RED
				sb.set_corner_radius_all(8)
				sb.shadow_size = 8
				sb.shadow_color = Color.BLACK
				sb.set_border_width_all(3)
				for i in 4:
					draw_style_box(sb, Rect2(i * 30, 0, 24, 24))
			"text4":
				var f: Font = UIStyle.UI_BOLD
				for i in 4:
					draw_string(f, Vector2(0, 20 + i * 20), "HELLO 12", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			"text4_outline":
				var f: Font = UIStyle.UI_BOLD
				for i in 4:
					draw_string_outline(f, Vector2(0, 20 + i * 20), "HELLO 12", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
					draw_string(f, Vector2(0, 20 + i * 20), "HELLO 12", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			"text_outline_all_then_fill":
				var f: Font = UIStyle.UI_BOLD
				for i in 4:
					draw_string_outline(f, Vector2(0, 20 + i * 20), "HELLO 12", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
				for i in 4:
					draw_string(f, Vector2(0, 20 + i * 20), "HELLO 12", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_root)
	var cases := {}
	cases["empty"] = func() -> Array: return []
	cases["label1"] = func() -> Array: return [UIStyle.text("HEROSAURO", UIStyle.Scale.SUBHEAD)]
	cases["label4"] = func() -> Array:
		var a := []
		for i in 4:
			var l := UIStyle.text("HEROSAURO", UIStyle.Scale.SUBHEAD)
			l.position = Vector2(0, i * 40)
			a.append(l)
		return a
	cases["label1_plain"] = func() -> Array:
		var l := Label.new()
		l.text = "HEROSAURO"
		return [l]
	cases["label1_outline_only"] = func() -> Array:
		var l := Label.new()
		l.text = "HEROSAURO"
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		return [l]
	cases["plate1"] = func() -> Array:
		var p := UIStyle.plate(UIStyle.HERO_GREEN, 0.13)
		p.size = Vector2(400, 120)
		return [p]
	cases["panel_flat1"] = func() -> Array:
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.RED
		p.add_theme_stylebox_override("panel", sb)
		p.size = Vector2(100, 100)
		return [p]
	cases["panel_flat4"] = func() -> Array:
		var a := []
		for i in 4:
			var p := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color.RED
			p.add_theme_stylebox_override("panel", sb)
			p.size = Vector2(50, 50)
			p.position = Vector2(i * 60, 0)
			a.append(p)
		return a
	cases["star1"] = func() -> Array:
		var s := KidIcon.make(KidIcon.Kind.STAR, 40.0, UIStyle.GOLD)
		return [s]
	cases["portrait1"] = func() -> Array:
		var pf := PortraitFrame.new()
		pf.actor = UIStyle.Actor.HEROSAURO
		pf.size = Vector2(84, 84)
		return [pf]
	cases["dial1"] = func() -> Array:
		var d := AbilityDial.new()
		d.size = Vector2(62, 62)
		d.setup("E", UIStyle.HERO_GREEN)
		return [d]
	cases["statbar1"] = func() -> Array:
		var b := StatBar.new()
		b.setup(StatBar.Variant.HERO, 100.0, UIStyle.HERO_GREEN, 4)
		b.size = Vector2(240, 28)
		return [b]
	cases["texrect2"] = func() -> Array:
		var a := []
		for i in 2:
			var t := TextureRect.new()
			t.texture = UIStyle.PORTRAIT_HEROSAURO
			t.size = Vector2(60, 60)
			t.position = Vector2(i * 70, 0)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			a.append(t)
		return a
	for k in ["rects4", "circles4", "circles4_aa", "poly4", "lines4", "lines4_aa", "sbf4", "sbf4_shadow", "text4", "text4_outline", "text_outline_all_then_fill"]:
		var kk: String = k
		cases["draw_" + kk] = func() -> Array:
			var d := Drawer.new()
			d.kind = kk
			d.size = Vector2(200, 200)
			return [d]
	cases["atlas_stars5"] = func() -> Array:
		var a := []
		for i in 5:
			var t := IconAtlas.sprite(IconAtlas.icon(KidIcon.Kind.STAR, 40.0, UIStyle.GOLD), Vector2(40, 40))
			t.position = Vector2(300 + i * 44, 300)
			a.append(t)
		var r := IconAtlas.sprite(IconAtlas.icon(KidIcon.Kind.ROBOT, 34.0, Color("bfe3ff"), Color("f2564a")), Vector2(34, 34))
		r.position = Vector2(300, 350)
		a.append(r)
		var s1 := KidIcon.make(KidIcon.Kind.STAR, 40.0, UIStyle.GOLD)
		s1.position = Vector2(300, 400)
		a.append(s1)
		var r1 := KidIcon.make(KidIcon.Kind.ROBOT, 34.0, Color("bfe3ff"), Color("f2564a"))
		r1.position = Vector2(350, 400)
		a.append(r1)
		var big := IconAtlas.sprite(IconAtlas.icon(KidIcon.Kind.STAR, 40.0, UIStyle.GOLD), Vector2(120, 120))
		big.position = Vector2(500, 350)
		a.append(big)
		return a
	if OS.get_cmdline_user_args().has("--atlas"):
		var only := {"atlas_stars5": cases["atlas_stars5"]}
		cases = only
	for name in cases.keys():
		for c in _root.get_children():
			_root.remove_child(c)
			c.queue_free()
		for n in (cases[name] as Callable).call():
			_root.add_child(n)
		for i in 4:
			await get_tree().process_frame
		var worst := 0
		for i in 3:
			await RenderingServer.frame_post_draw
			worst = maxi(worst, int(get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		print("[bench] %-28s %d" % [name, worst])
		if name == "atlas_stars5":
			var img := get_viewport().get_texture().get_image()
			img.save_png("/tmp/claude-0/-home-user-Herosauro-Superboxy/5cdb02a4-673a-562e-935a-b50af713c506/scratchpad/atlas.png")
	get_tree().quit()
