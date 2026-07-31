extends Node
## Every .gd in the project compiles. One process, no rendering.
##
## WHY THIS EXISTS. `tools/profile.gd` — the profiler that owns the frame-cost
## distribution and the budget gate — did not parse. Not "was slow", not "had a
## stale ceiling": it could not be loaded, and had been in that state since it
## was written. One line, `var p50 := proc["p50"]`, which is a hard parse error
## in GDScript because a Dictionary subscript is a Variant with no set type.
##
## Nothing caught it, and the reason is worth writing down, because the same
## hole is there for anything else nobody happens to run:
##
##   * `godot --headless --import` compiles the scripts reachable from the
##     resources it imports. A script referenced only by a .tscn that no import
##     step loads is never compiled, so the import log stays clean. CI's "Import
##     must be error-free" step was checking a log that could not contain the
##     error.
##   * The probe loop runs `scripts/**/_*probe.gd`. tools/ has no probes.
##   * The render tier renders a shot. It never touches the profiler.
##
## So a measurement tool broke, reported nothing, and its silence read exactly
## like a passing budget. That is the third instance of the same failure shape
## in this project — after `_menu_probe` measuring a scene it had failed to add
## to the tree, and `tools/budget.gd` printing zeros for want of a camera. A
## thing that does not run looks identical to a thing that runs and finds
## nothing wrong, unless something checks.
##
## Run AS A SCENE, never with --script. Under --script no autoloads exist, so
## every reference to GameManager, AudioManager or InputManager fails to resolve
## and this reports the whole gameplay tree as broken:
##
##   godot --headless --path . tools/parsecheck.tscn

## Directories not walked. `.godot` holds the import cache — compiled copies of
## the same sources, so checking them is duplicate work on generated files.
const SKIP := [".godot", ".git"]


func _ready() -> void:
	var scripts: Array[String] = []
	_walk("res://", scripts)
	scripts.sort()

	# Scripts with a live instance in this process: the three autoloads and this
	# file. reload() cannot recompile a script that is currently bound to an
	# object and returns an error for it — measured, and it reported all four as
	# BROKEN on a clean tree before this exemption existed.
	#
	# Exempting them loses nothing. A script that is running has compiled; that
	# is a stronger proof than the one this gate applies to the rest.
	var live := _live_scripts()

	var broken: Array[String] = []
	for path in scripts:
		if live.has(path):
			continue
		# CACHE_MODE_REUSE (the default), deliberately, and it is the difference
		# between a 3-second gate and one that does not finish.
		#
		# CACHE_MODE_IGNORE was tried first, on the reasoning that a script
		# already pulled in by an autoload would return cached and go unchecked.
		# It did not return inside ten minutes. IGNORE applies to the whole
		# dependency graph, so every `class_name` reference recompiles its target
		# from source on every load — and with 94 scripts sharing UIStyle,
		# GameManager, PhysicsLayers and WorldTier, that is quadratic. The
		# explicit reload() below covers what REUSE would otherwise hide.
		var res := ResourceLoader.load(path, "Script")
		var script := res as GDScript
		if script == null:
			broken.append(path)
			continue
		# reload(), NOT `res == null`, and this distinction is the whole gate.
		#
		# Measured, with the real parse error put back into tools/profile.gd:
		#
		#   ResourceLoader.load()  ->  non-null       (a Script object exists)
		#   script.reload()        ->  43             (ERR_PARSE_ERROR)
		#
		# Godot hands back a Script resource for a file that did not compile, so
		# a null check passes every broken script in the project. The first
		# version of this file did exactly that: with the bug reintroduced on
		# purpose, it printed PASS. A gate has to be shown failing on the fault
		# it was written for, or it is decoration.
		if script.reload() != OK:
			broken.append(path)

	print("=== PARSE CHECK: %d scripts (%d already live) ===" % [scripts.size(), live.size()])
	for path in broken:
		printerr("  BROKEN: " + path)
	if broken.is_empty():
		print("  ok: every script compiles")
	else:
		print("  %d script(s) failed to compile — see the errors above" % broken.size())
	print("=== END PARSE CHECK (%s) ===" % ("PASS" if broken.is_empty() else "FAIL"))
	get_tree().quit(0 if broken.is_empty() else 1)


## Resource paths of every script bound to a node currently in the tree.
func _live_scripts() -> Dictionary:
	var out := {}
	_collect_live(get_tree().root, out)
	return out


func _collect_live(node: Node, out: Dictionary) -> void:
	var script := node.get_script() as Script
	if script != null and script.resource_path != "":
		out[script.resource_path] = true
	for child in node.get_children():
		_collect_live(child, out)


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not SKIP.has(name):
				_walk(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
