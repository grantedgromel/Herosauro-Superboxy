class_name AtlasPlate
extends Control
## UIStyle.plate()'s moulded HUD plate (drop shadow, keyline shell, tinted
## face, warm gloss over the top half, shade under the bottom quarter), drawn
## as IconAtlas nine-slices instead of four StyleBoxFlat polygons.
##
## The look is not re-described here: make() builds the real UIStyle.plate()
## once, takes its StyleBoxes and band anchors, and frees it, so the two can
## never drift apart. Every part is a textured rect on the atlas, so a plate
## costs no draw call of its own when the next thing drawn is also from the
## atlas (the portrait, the bar, the dial), where it used to cost four.

var _shell: IconAtlas.Box
var _bands: Array = []    # [IconAtlas.Box, Color, top fraction, bottom fraction]
var _inset := 0.0


static func make(tint: Color = UIStyle.SURFACE, tint_amount: float = 0.0,
		radius: int = UIStyle.RADIUS_LG, elev: int = UIStyle.Elev.HIGH) -> AtlasPlate:
	var p := AtlasPlate.new()
	var src := UIStyle.plate(tint, tint_amount, radius, elev)
	var outer := src.get_theme_stylebox("panel") as StyleBoxFlat
	var face := src.get_child(0) as Panel
	var inner := face.get_theme_stylebox("panel") as StyleBoxFlat
	p._inset = face.offset_left
	var key := "plate:%s:%.3f:%d:%d" % [tint.to_html(), tint_amount, radius, elev]
	p._shell = IconAtlas.box(key, [outer, inner], [0.0, p._inset])
	for band: Panel in face.get_children():
		var sb := (band.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		var tint_of := sb.bg_color
		sb.bg_color = Color.WHITE
		var b := IconAtlas.box("plate_band:%d:%d:%d" % [sb.corner_radius_top_left,
			sb.corner_radius_bottom_left, radius], [sb])
		p._bands.append([b, tint_of, band.anchor_top, band.anchor_bottom])
	src.free()
	return p


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if _shell == null:
		return
	IconAtlas.draw_box(self, _shell, Rect2(Vector2.ZERO, size))
	var face := Rect2(Vector2(_inset, _inset), size - Vector2(_inset, _inset) * 2.0)
	for band: Array in _bands:
		var top: float = face.position.y + face.size.y * float(band[2])
		var bottom: float = face.position.y + face.size.y * float(band[3])
		IconAtlas.draw_box(self, band[0], Rect2(face.position.x, top, face.size.x, bottom - top),
			band[1])
