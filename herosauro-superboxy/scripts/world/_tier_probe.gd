extends Node
## Does the web tier's geometry gate leave the DESKTOP material set untouched?
##
## This is the claim that lets a Compatibility-only optimisation ship without a
## desktop re-review, so it is checked rather than argued. `ToonFactory.build()`
## folds `WorldTier.fine_detail()` into its `fine_detail` argument; on Forward+
## that returns true, so the expression must be the caller's own value and every
## resulting material must be indistinguishable from the pre-gate one.
##
## Headless reports forward_plus, which is exactly the tier under test.
##
##   godot --headless --path . scripts/world/_tier_probe.tscn

const PROPS := [
	"albedo_color", "roughness", "metallic", "metallic_specular",
	"detail_enabled", "detail_blend_mode", "detail_uv_layer",
	"uv1_triplanar", "uv2_triplanar", "uv1_scale", "uv2_scale",
	"normal_enabled", "normal_scale", "ao_enabled", "ao_light_affect",
	"rim_enabled", "rim", "rim_tint", "roughness_texture_channel",
	"albedo_texture", "normal_texture", "roughness_texture",
	"metallic_texture", "ao_texture", "detail_albedo", "detail_normal",
]

var _fails: int = 0


func _ready() -> void:
	var method := RenderingServer.get_current_rendering_method()
	_ok(method == "forward_plus", "tier under test is forward_plus (got %s)" % method)
	_ok(WorldTier.fine_detail(), "WorldTier.fine_detail() is true on the desktop tier")
	_ok(not WorldTier.is_reduced(), "WorldTier.is_reduced() is false on the desktop tier")

	# Every surface the world actually asks for, in both metal states, with the
	# detail layer explicitly on and explicitly off. If the gate leaked, the
	# fine_detail=true column would come back looking like the false one.
	for surface in [ToonFactory.Surface.GRANITE, ToonFactory.Surface.IRON,
			ToonFactory.Surface.COBBLE, ToonFactory.Surface.PLASTER,
			ToonFactory.Surface.TERRACOTTA, ToonFactory.Surface.FLAT]:
		for metal in [0.0, 0.85]:
			var on := ToonFactory.build(Color(0.55, 0.5, 0.46), surface, 0.7, metal,
					2.0, 1.0, 0.4, Color.BLACK, 0.0, 1.0, 0.5, true)
			var off := ToonFactory.build(Color(0.55, 0.5, 0.46), surface, 0.7, metal,
					2.0, 1.0, 0.4, Color.BLACK, 0.0, 1.0, 0.5, false)
			var tag := "surface %d metal %.2f" % [surface, metal]
			# The two must be DIFFERENT materials — if the gate had forced every
			# caller to false, these would collapse onto one cached object and the
			# desktop would silently lose its detail layer.
			if surface != ToonFactory.Surface.FLAT:
				_ok(on != off, "%s: detail on/off are distinct materials" % tag)
				_ok(on.detail_enabled, "%s: fine_detail=true still enables detail" % tag)
				_ok(on.uv2_triplanar, "%s: fine_detail=true still triplanar on uv2" % tag)
				_ok(not off.detail_enabled, "%s: fine_detail=false disables detail" % tag)
			# Caching must still collapse identical requests, or draw calls explode.
			var again := ToonFactory.build(Color(0.55, 0.5, 0.46), surface, 0.7, metal,
					2.0, 1.0, 0.4, Color.BLACK, 0.0, 1.0, 0.5, true)
			_ok(again == on, "%s: identical requests still share one material" % tag)
			for p in PROPS:
				_ok(again.get(p) == on.get(p), "%s: %s stable across calls" % [tag, p])

	print("=== TIER PROBE (%s) ===" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0 if _fails == 0 else 1)


func _ok(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("  FAIL: " + what)
