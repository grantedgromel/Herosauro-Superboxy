extends SceneTree
## Headless diagnostics for the title screen. Nothing in the game loads this; it
## exists so the three things about the menu that cannot be eyeballed without a
## GPU can at least be measured:
##
##   1. what the live Porto backdrop costs to build, since the menu now pays that
##      price at boot AND main.gd pays it again when the match starts;
##   2. that the runtime-authored logo shader compiles (a broken shader would eat
##      the single most visible element on the screen);
##   3. that the cinematic camera path stays inside the modelled world.
##
## Run:
##   godot --headless --path . --script res://scripts/ui/menu/_menu_probe.gd

const CameraPath := preload("res://scripts/ui/menu/menu_camera_path.gd")
const TitleLogo := preload("res://scripts/ui/menu/title_logo.gd")
const MenuModal := preload("res://scripts/ui/menu/menu_modal.gd")

## Everything the camera must not fly into, as world-space AABBs. The deck slab,
## the arch, the piers and the abutments are one box (bridge_arena.gd's own
## cross-section constants); the water is a half-space handled separately.
const BRIDGE_MIN := Vector3(-58.5, -19.0, -7.5)
const BRIDGE_MAX := Vector3(58.5, 7.0, 7.5)
const WAVE_CREST := -14.65        # river plane at -15 plus the shader's amplitude
## The procedural banks stop here; anything past it is open water and sky.
const CHANNEL_HALF_X := 50.0


## Every non-ASCII character the title screen wants to render. A glyph the font
## does not carry falls back to a system face, and the web export has no system
## faces — so a missing one is a tofu box in the middle of the menu.
const GLYPH_CHECK := "—–·×•▶◀‹›«»↑↓↵⏎©íúãç"


func _initialize() -> void:
	_probe_world_cost()
	_probe_fonts()
	_probe_logo_shader()
	_probe_camera_path()
	_probe_panels()
	quit()


# --- CONTROLS / CREDITS ------------------------------------------------------

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


# --- Font coverage -----------------------------------------------------------

func _probe_fonts() -> void:
	for pair in [["Bangers", UIStyle.TITLE_FONT], ["Chillax-Medium", UIStyle.UI_FONT],
			["Chillax-Bold", UIStyle.UI_BOLD]]:
		var font: Font = pair[1]
		var missing := ""
		for i in GLYPH_CHECK.length():
			if not font.has_char(GLYPH_CHECK.unicode_at(i)):
				missing += GLYPH_CHECK[i]
		print("[probe] %s missing: %s" % [pair[0], "(none)" if missing.is_empty() else missing])


# --- 1. Backdrop build cost --------------------------------------------------

func _probe_world_cost() -> void:
	var scene: PackedScene = load("res://scenes/world/bridge_arena.tscn")
	var t0 := Time.get_ticks_usec()
	var world: Node = scene.instantiate()
	var t1 := Time.get_ticks_usec()
	root.add_child(world)
	var t2 := Time.get_ticks_usec()
	print("[probe] bridge_arena instantiate %.1f ms, _ready cascade %.1f ms, total %.1f ms"
			% [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t2 - t0) / 1000.0])
	print("[probe] nodes in backdrop: %d" % _count(world))
	world.queue_free()


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n


# --- 2. Logo shader ----------------------------------------------------------

## Godot's headless build uses the dummy rasteriser, so a compile error here may
## simply never be raised. The check is still worth running: if it DOES print,
## the shader is broken; if it does not, we have learned nothing and the flag in
## title_logo.gd is the escape hatch.
func _probe_logo_shader() -> void:
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


# --- 3. Camera path ----------------------------------------------------------

func _probe_camera_path() -> void:
	var samples := 4000
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var min_bridge := INF
	var min_water := INF
	var max_edge := -INF
	var max_x := 0.0
	for i in samples:
		var shot := CameraPath.sample(float(i) / float(samples))
		var p: Vector3 = shot.position
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		min_bridge = minf(min_bridge, _box_distance(p, BRIDGE_MIN, BRIDGE_MAX))
		min_water = minf(min_water, p.y - WAVE_CREST)
		max_x = maxf(max_x, absf(p.x))
		# Worst horizontal frustum edge, measured off -Z, at a 21:9 letterbox —
		# the widest the `expand` stretch mode can hand us. Past 90 degrees the
		# frame would start to include the unmodelled water downstream.
		var flat := Vector2(shot.target.x - p.x, shot.target.z - p.z)
		var yaw := absf(rad_to_deg(atan2(flat.x, -flat.y)))
		var half_h := rad_to_deg(atan(tan(deg_to_rad(shot.fov * 0.5)) * 21.0 / 9.0))
		max_edge = maxf(max_edge, yaw + half_h)

	print("[probe] camera x [%.1f, %.1f]  y [%.1f, %.1f]  z [%.1f, %.1f]"
			% [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
	print("[probe] clearance: bridge %.1f u, wave crest %.1f u, channel wall %.1f u"
			% [min_bridge, min_water, CHANNEL_HALF_X - max_x])
	print("[probe] widest frustum edge off -Z at 21:9: %.1f deg (must stay under 90)" % max_edge)


func _box_distance(p: Vector3, lo: Vector3, hi: Vector3) -> float:
	var d := Vector3(
		maxf(maxf(lo.x - p.x, 0.0), p.x - hi.x),
		maxf(maxf(lo.y - p.y, 0.0), p.y - hi.y),
		maxf(maxf(lo.z - p.z, 0.0), p.z - hi.z))
	return d.length()
