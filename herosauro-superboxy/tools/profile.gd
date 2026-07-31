extends Node
## Gameplay profiler and budget gate.
##
## Replaces the single-snapshot tools/budget.gd with a run over a live match,
## because the two answer different questions and only one of them is the
## question that matters.
##
## A snapshot of a static scene reports the cost of the *best* frame. Games are
## killed by their worst ones: the frame that builds a wave of debris, the frame
## that compiles a shader it has not needed yet, the frame the boss lands his
## slam and forty particles, a shockwave and a hit-stop all start at once. A
## median hides every one of those. So this samples every frame of a scripted
## fight and reports the DISTRIBUTION — p50, p95, p99, worst, and which frame the
## worst was — plus the hardware-independent budget counters.
##
## This container has no GPU. lavapipe frame times say nothing about a real card,
## so no framerate is reported and none should be inferred. What IS meaningful
## and is reported:
##
##   * CPU-side script and physics time per frame. Those run on the CPU on real
##     hardware too, and a GDScript spike is a spike everywhere.
##   * Draw calls, primitives, node count, memory. Counts and bytes, not
##     milliseconds — hardware-independent by construction.
##
##   godot --path . tools/profile.tscn --rendering-driver vulkan --fixed-fps 60 \
##         -- --frames=600 --out=/abs/report.json

const MainScene: PackedScene = preload("res://scenes/main.tscn")

## Budget ceilings, keyed on the rendering method, because one number cannot
## serve both tiers. `scripts/world/world_tier.gd` builds a genuinely different
## world on GL Compatibility — 406,179 triangles against 1,106,039, two shadow
## cascades against four — and the same static arena measures 3,261,457
## primitives a frame on Forward+ and 574,730 on Compatibility. A ceiling loose
## enough for desktop is six times the web tier's entire frame.
##
## READ THESE AS A RATCHET, NOT AS A TARGET. They are set just above what the
## build measures today, so that a regression trips them; they are NOT a
## statement that this is what the frame should cost. It should cost less. The
## desktop tier in particular submits about 2.9x the world's whole triangle
## count every frame and is documented in docs/PERFORMANCE_BUDGET.md as an open
## problem. Loosening one of these to make a run pass is how the ratchet turns
## into a rubber stamp — if a change needs more, it needs a measurement and a
## line in the round doc saying what was bought.
##
## Measured with tools/budget.tscn (static arena) and this file (live fight) on
## llvmpipe. Every counter here is hardware-independent, so the numbers hold on
## a real card even though the frame times would not.
const BUDGETS := {
	"forward_plus": {
		"draw_calls_p99": 1400,
		"primitives_p99": 5_000_000,
		"nodes_max": 6000,
		"static_memory_mib": 900.0,
	},
	"gl_compatibility": {
		"draw_calls_p99": 700,
		"primitives_p99": 900_000,
		"nodes_max": 6000,
		"static_memory_mib": 500.0,
	},
}


## The tier whose budget applies. Unknown renderers fall back to the strict one:
## a gate that does not recognise where it is running should not be the loose
## gate.
func _tier() -> String:
	var method := RenderingServer.get_current_rendering_method()
	return method if BUDGETS.has(method) else "gl_compatibility"


func _budget() -> Dictionary:
	return BUDGETS[_tier()]

## Beats driven while profiling, chosen to cover the expensive moments rather
## than a quiet stroll: closing on the giant, swinging, taking the slam.
const ROUTE: Array = [
	["", 40],
	["move_up", 220],
	["attack", 40],
	["", 30],
	["attack", 40],
	["ability", 30],
	["", 60],
	["move_up", 120],
	["attack", 40],
	["", 80],
]

var _frames: int = 600
var _out: String = ""
var _n: int = 0
var _step: int = 0
var _held: int = 0
var _held_action: String = ""
var _started: bool = false

var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _draw_calls: Array[float] = []
var _primitives: Array[float] = []
var _nodes: Array[float] = []
var _peak_static_mib: float = 0.0


func _ready() -> void:
	seed(1881)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--out="):
			_out = a.substr(6)

	add_child(MainScene.instantiate())
	await get_tree().process_frame
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		push_error("profile: GameManager autoload missing")
		get_tree().quit(2)
		return
	gm.start_game()
	_started = true
	print("profile: renderer=%s, %d frames" % [RenderingServer.get_video_adapter_name(), _frames])


func _process(_delta: float) -> void:
	if not _started:
		return

	_sample()
	_drive()

	_n += 1
	if _n >= _frames:
		set_process(false)
		# EXIT CODE, not just stdout. This used to quit(0) unconditionally, so a
		# run that printed "BUDGET EXCEEDED" three times still reported success
		# to whatever launched it. A gate that cannot fail is not a gate; it is
		# a log line. Same class of defect as tools/budget.gd's zeros.
		get_tree().quit(0 if _report() else 1)


func _sample() -> void:
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_peak_static_mib = maxf(_peak_static_mib,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)


func _drive() -> void:
	if _step >= ROUTE.size():
		return
	var beat: Array = ROUTE[_step]
	var action := String(beat[0])
	var hold := int(beat[1])
	if _held == 0 and action != "" and InputMap.has_action(action):
		Input.action_press(action)
		_held_action = action
	_held += 1
	if _held >= hold:
		if _held_action != "":
			Input.action_release(_held_action)
			_held_action = ""
		_held = 0
		_step += 1


# --- Statistics --------------------------------------------------------------

func _pct(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var idx := int(round(p * (sorted.size() - 1)))
	return sorted[clampi(idx, 0, sorted.size() - 1)]


func _worst_frame(values: Array[float]) -> int:
	var best := -1
	var best_v := -INF
	for i in values.size():
		if values[i] > best_v:
			best_v = values[i]
			best = i
	return best


func _dist(label: String, values: Array[float]) -> Dictionary:
	var d := {
		"p50": _pct(values, 0.50),
		"p95": _pct(values, 0.95),
		"p99": _pct(values, 0.99),
		"max": _pct(values, 1.0),
		"worst_frame": _worst_frame(values),
	}
	print("  %-16s p50 %10.2f   p95 %10.2f   p99 %10.2f   max %10.2f  @frame %d"
			% [label, d["p50"], d["p95"], d["p99"], d["max"], d["worst_frame"]])
	return d


## Returns true if every budget held.
func _report() -> bool:
	print("=== PROFILE (%d frames, %s) ===" % [_n, RenderingServer.get_current_rendering_method()])
	print("  --- CPU cost per frame, milliseconds ---")
	var proc := _dist("script process", _process_ms)
	var phys := _dist("physics", _physics_ms)
	print("  --- per-frame counts ---")
	var draws := _dist("draw calls", _draw_calls)
	var prims := _dist("primitives", _primitives)
	var nodes := _dist("nodes", _nodes)
	print("  peak static memory : %.1f MiB" % _peak_static_mib)

	# Hitch attribution. A frame far above p50 is the one worth chasing, and
	# saying WHICH frame and what was running lets someone reproduce it.
	var spikes: Array = []
	# Explicitly typed, not inferred. `:=` off a Dictionary subscript is a hard
	# parse error in GDScript — the value is a Variant and has no set type — and
	# this line is why tools/profile.gd has never once run. The profiler that
	# owns the frame-cost distribution and the budget gate has been dead code
	# since it was written, which is the real reason the budget "kept passing".
	var p50: float = proc["p50"]
	for i in _process_ms.size():
		if _process_ms[i] > maxf(p50 * 4.0, p50 + 4.0):
			spikes.append({"frame": i, "process_ms": snappedf(_process_ms[i], 0.01)})
	print("  script-time spikes  : %d" % spikes.size())
	for s in spikes.slice(0, 8):
		print("     frame %5d  %.2f ms" % [s["frame"], s["process_ms"]])

	var budget := _budget()
	print("  budget applied      : %s" % _tier())
	var failures: Array[String] = []
	if draws["p99"] > budget["draw_calls_p99"]:
		failures.append("draw calls p99 %d > %d" % [draws["p99"], budget["draw_calls_p99"]])
	if prims["p99"] > budget["primitives_p99"]:
		failures.append("primitives p99 %d > %d" % [prims["p99"], budget["primitives_p99"]])
	if nodes["max"] > budget["nodes_max"]:
		failures.append("nodes max %d > %d" % [nodes["max"], budget["nodes_max"]])
	if _peak_static_mib > budget["static_memory_mib"]:
		failures.append("static memory %.1f MiB > %.1f" % [_peak_static_mib, budget["static_memory_mib"]])

	for f in failures:
		print("  BUDGET EXCEEDED: " + f)
	print("=== END PROFILE (%s) ===" % ("PASS" if failures.is_empty() else "FAIL"))

	if _out != "":
		var payload := {
			"frames": _n,
			"renderer": RenderingServer.get_current_rendering_method(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"script_process_ms": proc,
			"physics_ms": phys,
			"draw_calls": draws,
			"primitives": prims,
			"nodes": nodes,
			"peak_static_mib": snappedf(_peak_static_mib, 0.1),
			"spikes": spikes,
			"tier": _tier(),
			"budget": budget,
			"failures": failures,
			"pass": failures.is_empty(),
		}
		var fh := FileAccess.open(_out, FileAccess.WRITE)
		if fh:
			fh.store_string(JSON.stringify(payload, "  "))
			fh.close()
			print("profile: wrote " + _out)

	return failures.is_empty()
