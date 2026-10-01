class_name PaperWall
extends Control
## The bedroom wall behind the bookshelf and the "who's playing" screen: warm
## painted plaster with a little star wallpaper, a wooden shelf to stand the
## books on, and a soft vignette. Drawn once; nothing here moves.

const WALL_TOP := Color("ffd9a0")
const WALL_BOTTOM := Color("ffb98a")
const STAR := Color(1.0, 1.0, 1.0, 0.30)
const WOOD := Color("a8673a")
const WOOD_LIGHT := Color("c98a52")
const INK := Color(0.10, 0.07, 0.10, 0.92)

## Shelf top as a fraction of the height; < 0 hides the shelf.
var shelf_y: float = -1.0
var seed_value: int = 7


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func set_shelf(y: float) -> void:
	shelf_y = y
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([WALL_TOP, WALL_TOP, WALL_BOTTOM, WALL_BOTTOM]))
	# Wallpaper: a loose grid of small stars and dots.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var step := 88.0
	var row := 0
	var y := 30.0
	while y < h:
		var x := 30.0 + (step * 0.5 if row % 2 == 1 else 0.0)
		while x < w:
			var c := Vector2(x + rng.randf_range(-6, 6), y + rng.randf_range(-6, 6))
			if (row + int(x / step)) % 3 == 0:
				_star(c, 11.0, STAR)
			else:
				draw_circle(c, 4.0, STAR)
			x += step
		y += step * 0.8
		row += 1
	if shelf_y > 0.0:
		var sy := h * shelf_y
		# Shadow the books throw on the wall, the plank, its front lip.
		draw_rect(Rect2(0, sy - 30, w, 30), Color(0.3, 0.15, 0.05, 0.10))
		draw_rect(Rect2(0, sy, w, 26), WOOD_LIGHT)
		draw_rect(Rect2(0, sy + 26, w, 22), WOOD)
		draw_line(Vector2(0, sy), Vector2(w, sy), INK, 4.0, true)
		draw_line(Vector2(0, sy + 48), Vector2(w, sy + 48), INK, 4.0, true)
		draw_rect(Rect2(0, sy + 50, w, 26), Color(0.3, 0.12, 0.04, 0.22))
		for k in int(w / 160.0) + 1:
			var gx := 40.0 + k * 160.0
			draw_line(Vector2(gx, sy + 8), Vector2(gx + 60, sy + 12), Color(0.45, 0.25, 0.1, 0.35),
				2.0, true)
	# Vignette.
	var edge := Color(0.35, 0.12, 0.05, 0.0)
	var dark := Color(0.35, 0.12, 0.05, 0.28)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.12, 0), Vector2(w * 0.12, h),
		Vector2(0, h)]), PackedColorArray([dark, edge, edge, dark]))
	draw_polygon(PackedVector2Array([Vector2(w * 0.88, 0), Vector2(w, 0), Vector2(w, h),
		Vector2(w * 0.88, h)]), PackedColorArray([edge, dark, dark, edge]))


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
