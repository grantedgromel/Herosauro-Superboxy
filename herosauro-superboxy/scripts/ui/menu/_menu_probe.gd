extends Node
## Headless diagnostics for the title screen. Nothing in the game loads this; it
## exists so the things about the menu that cannot be eyeballed without a GPU can
## at least be measured:
##
##   1. THE PROPERTY WORTH LOCKING DOWN: the menu does not build the arena. It
##      used to instance a whole second copy of `bridge_arena.tscn` as a backdrop,
##      which cost SECONDS of blocking main-thread work and a few hundred nodes
##      before the player could read the title. This probe times the real screen
##      end to end and then walks its subtree asserting that there is no arena, no
##      Camera3D and no WorldEnvironment anywhere in it. The cost is printed
##      alongside what the arena costs, so the two numbers sit next to each other
##      and the regression is obvious the moment it happens.
##   2. that the cinematic key art has somewhere to land, and that the composed
##      fallback is what is on screen until it does;
##   3. that the runtime-authored logo shader compiles (a broken shader would eat
##      the single most visible element on the screen);
##   4. font coverage, and the two modal panels' real text.
##
## What is NOT here any more: the cinematic camera path's clearance sweep. There
## is no camera on this screen to keep out of the parapet.
##
## It runs as a SCENE, not with --script, for the same reason _ui_probe does:
## autoload singletons are only instantiated on the normal startup path, and the
## menu reads GameManager for its difficulty and InputManager for the controls
## panel. Under --script neither identifier resolves at parse time and the
## preloads below fail to compile.
##
## Run:
##   godot --headless --path . scripts/ui/menu/_menu_probe.tscn

const MainMenuScene: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const Backdrop := preload("res://scripts/ui/menu/menu_backdrop.gd")
const TitleLogo := preload("res://scripts/ui/menu/title_logo.gd")
const MenuModal := preload("res://scripts/ui/menu/menu_modal.gd")

## The size the menu is measured at. A Control takes its rect from the viewport
## it is under, so the screen is built inside a SubViewport of exactly the design
## size — otherwise the layout, the portrait resample and therefore the whole
## build cost would be measured at whatever the headless window happens to be.
const VIEW := Vector2i(1280, 720)

## What a title screen is allowed to cost. Generous by an order of magnitude
## against what it actually measures, because this is a floor-of-the-cliff
## assertion — the failure it exists to catch is a return to seconds, not a
## regression of a millisecond or two on a shared build machine.
const BUILD_BUDGET_MS := 250.0

## Every non-ASCII character the title screen wants to render. A glyph the font
## does not carry falls back to a system face, and the web export has no system
## faces — so a missing one is a tofu box in the middle of the menu.
const GLYPH_CHECK := "—–·×•▶◀‹›«»↑↓↵⏎©íúãç"

var _fails := 0


func _ready() -> void:
	# Yield one frame before touching the tree. The measurements below add nodes
	# under get_tree().root, and during _ready() the root is still setting up its
	# own children, so the add_child() is refused outright — the probe then
	# measured a _ready cascade of 0.1 ms for a scene that was never in the tree.
	#
	# call_deferred() would also silence the error but would break the
	# measurement this function exists for: the whole point is timing the
	# SYNCHRONOUS _ready cascade between t1 and t2, which a deferred add moves
	# outside the window being timed.
	await get_tree().process_frame
	_probe_menu_cost()
	_probe_key_art()
	_probe_fonts()
	_probe_logo_shader()
	_probe_panels()

	print("")
	if _fails == 0:
		print("MENU PROBE: PASS")
	else:
		print("MENU PROBE: %d FAILURE(S)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok   %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)


# --- 1. What the title screen costs, and what it does not build --------------

func _probe_menu_cost() -> void:
	print("=== title screen build ===")
	var stage := SubViewport.new()
	stage.size = VIEW
	stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_tree().root.add_child(stage)

	var t0 := Time.get_ticks_usec()
	var menu: Control = MainMenuScene.instantiate()
	var t1 := Time.get_ticks_usec()
	# The scene is anchored full-rect, so it takes the SubViewport's size on the
	# way in and its _ready cascade lays out for real — logo fit, column, and the
	# Lanczos resample of the three character sheets all land inside this window.
	stage.add_child(menu)
	var t2 := Time.get_ticks_usec()

	var instantiate_ms := (t1 - t0) / 1000.0
	var ready_ms := (t2 - t1) / 1000.0
	var total_ms := (t2 - t0) / 1000.0
	print("[probe] main_menu instantiate %.1f ms, _ready cascade %.1f ms, total %.1f ms"
			% [instantiate_ms, ready_ms, total_ms])
	print("[probe] nodes in the title screen: %d" % _count(menu))
	_ok(total_ms < BUILD_BUDGET_MS,
		"title screen builds in %.1f ms (budget %.0f ms)" % [total_ms, BUILD_BUDGET_MS])

	# THE ASSERTION THIS FILE EXISTS FOR. Not "the menu is fast" — fast is a
	# consequence — but "the menu contains no 3D world". A Camera3D or a
	# WorldEnvironment in this subtree means the backdrop has grown a second
	# renderer again, and an arena means it has grown the whole thing.
	var cameras := _find_class(menu, "Camera3D")
	var envs := _find_class(menu, "WorldEnvironment")
	var visuals := _find_class(menu, "VisualInstance3D")
	_ok(cameras.is_empty(), "the menu owns no Camera3D %s" % str(cameras))
	_ok(envs.is_empty(), "the menu owns no WorldEnvironment %s" % str(envs))
	_ok(visuals.is_empty(), "the menu owns no 3D geometry at all %s" % str(visuals))
	_ok(menu.find_child("BridgeArena", true, false) == null
			and menu.find_child("Arena", true, false) == null
			and menu.find_child("MenuWorld", true, false) == null,
		"the menu does not instantiate the arena")

	# For scale: what the backdrop used to cost, measured the same way. This is
	# the number the title screen was paying before it went static, and it is
	# still what main.gd pays on START — which is why the curtain is still there.
	var arena_scene: PackedScene = load("res://scenes/world/bridge_arena.tscn")
	var a0 := Time.get_ticks_usec()
	var arena: Node = arena_scene.instantiate()
	get_tree().root.add_child(arena)
	var a1 := Time.get_ticks_usec()
	var arena_ms := (a1 - a0) / 1000.0
	print("[probe] for scale, bridge_arena still costs %.1f ms and %d nodes"
			% [arena_ms, _count(arena)])
	print("[probe] the title screen is %.0fx cheaper than the backdrop it dropped"
			% (arena_ms / maxf(total_ms, 0.001)))
	arena.queue_free()

	menu.queue_free()
	stage.queue_free()


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n


## Node paths of every descendant of `root` that is `type_name`, so a failure
## names the offender instead of only counting it.
func _find_class(root: Node, type_name: String, out: Array[String] = []) -> Array[String]:
	for c in root.get_children():
		if c.is_class(type_name):
			out.append(String(root.get_path_to(c)))
		_find_class(c, type_name, out)
	return out


# --- 2. Where the key art lands ----------------------------------------------

## The cinematic key art is a single full-bleed texture at one named path. This
## reports which of the two grounds is live so that "I dropped the file in and
## nothing changed" is answerable without a GPU — nine times out of ten it is the
## filename or the import, and both show up here.
func _probe_key_art() -> void:
	print("=== key art hook ===")
	var path: String = Backdrop.KEY_ART_PATH
	var present := ResourceLoader.exists(path)
	print("[probe] key art path: %s" % path)
	print("[probe] key art present: %s" % ("yes" if present else "no — composed fallback in use"))

	var backdrop: Control = Backdrop.new()
	var stage := SubViewport.new()
	stage.size = VIEW
	stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_tree().root.add_child(stage)
	stage.add_child(backdrop)

	_ok(backdrop.has_key_art() == present,
		"the backdrop agrees with the filesystem about the key art")
	var art := backdrop.find_child("KeyArt", true, false) as TextureRect
	var ground := backdrop.find_child("ComposedGround", true, false) as TextureRect
	if present:
		_ok(art != null and art.texture != null, "the key art is mounted")
		_ok(art != null and art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
			"the key art covers the frame rather than letterboxing it")
		_ok(art != null and is_equal_approx(art.size.x, float(VIEW.x))
				and is_equal_approx(art.size.y, float(VIEW.y)),
			"the key art is full-bleed %s" % (str(art.size) if art != null else "-"))
		_ok(art != null and backdrop.get_child(0) == art,
			"the key art is the backmost layer on the screen")
		_ok(ground == null, "the composed fallback stands down when the art is in")
	else:
		_ok(art == null, "no key art rect until there is key art to put in it")
		_ok(ground != null, "the composed fallback is standing in")
		_ok(ground != null and backdrop.get_child(0) == ground,
			"the composed ground is the backmost layer on the screen")
	# Either way the grade over the top is the same, because key art is a bright
	# busy image and the menu column has to stay readable when it lands.
	for named in ["LeftScrim", "Vignette"]:
		_ok(backdrop.find_child(named, true, false) != null,
			"%s survives the switch to key art" % named)

	backdrop.queue_free()
	stage.queue_free()


# --- 3. Font coverage --------------------------------------------------------

func _probe_fonts() -> void:
	print("=== fonts ===")
	for pair in [["Bangers", UIStyle.TITLE_FONT], ["Fredoka", UIStyle.UI_FONT],
			["Fredoka-Bold", UIStyle.UI_BOLD]]:
		var font: Font = pair[1]
		var missing := ""
		for i in GLYPH_CHECK.length():
			if not font.has_char(GLYPH_CHECK.unicode_at(i)):
				missing += GLYPH_CHECK[i]
		print("[probe] %s missing: %s" % [pair[0], "(none)" if missing.is_empty() else missing])


# --- 4. Logo shader ----------------------------------------------------------

## Godot's headless build uses the dummy rasteriser, so a compile error here may
## simply never be raised. The check is still worth running: if it DOES print,
## the shader is broken; if it does not, we have learned nothing and the flag in
## title_logo.gd is the escape hatch.
func _probe_logo_shader() -> void:
	print("=== logo shader ===")
	var sh := Shader.new()
	sh.code = TitleLogo.SHINE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var names: Array[String] = []
	for u in sh.get_shader_uniform_list():
		names.append(str(u.get("name", "?")))
	names.sort()
	print("[probe] logo shader uniforms: %s" % ", ".join(names))
	print("[probe] rendering method reported headless: %s"
			% RenderingServer.get_current_rendering_method())


# --- 5. CONTROLS / CREDITS ---------------------------------------------------

## Builds both modal bodies and reads the text back out. The controls panel
## derives every binding from the live InputMap, so this is the only way to see
## what it will actually say without running the game and clicking on it.
func _probe_panels() -> void:
	for pair in [["CONTROLS", MenuModal.build_controls()], ["CREDITS", MenuModal.build_credits()]]:
		var body: Control = pair[1]
		print("[probe] %s panel:" % pair[0])
		for line in _text_lines(body):
			print("    %s" % line)
		body.queue_free()


## Flattens a built panel into one line per grid/box row, so key badges stay
## next to the action they belong to instead of arriving as loose words.
func _text_lines(node: Node, depth: int = 0) -> Array[String]:
	var out: Array[String] = []
	if node is Label:
		out.append((node as Label).text)
		return out
	var parts: Array[String] = []
	for c in node.get_children():
		parts.append_array(_text_lines(c, depth + 1))
	if node is HBoxContainer or node is PanelContainer:
		return [" ".join(parts)] as Array[String]
	return parts
