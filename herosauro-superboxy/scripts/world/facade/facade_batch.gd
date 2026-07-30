extends RefCounted
## Groups facade geometry by material so a whole terrace commits to a handful of
## draw calls.
##
## A MeshBaker produces exactly one surface with exactly one material, and a
## building that mixes render, granite, ironwork, glazed tile, timber and lit
## glass needs one baker per material. What makes that affordable is doing the
## grouping per *terrace* rather than per house: fourteen facades drawn from a
## seven-colour palette share seven plaster bakers, one granite baker, one iron
## baker and so on — call it a dozen draw calls for the whole row, against
## seventy for the box-and-prism version it replaces, at twenty times the detail.
##
## ToonFactory caches by parameter set, so two calls with the same arguments hand
## back the identical Material object. Keying the registry on that object is what
## makes the sharing automatic: callers just ask for "plaster in ochre" and
## whichever building asked first owns the baker.
##
## Two materials here are deliberately NOT from the factory's shared cache.
## Balusters, laundry and awnings are single quads with no thickness, and a
## back-face-culled quad vanishes when the sun swings behind it. Duplicating two
## materials with culling off buys every one of those a triangle instead of two
## and keeps them solid from both sides; they are cached statically so the whole
## city still shares one of each.

const REVEAL_BLACK := Color(0.055, 0.05, 0.055)
const TRIM_WHITE := Color(0.93, 0.91, 0.85)
const GRANITE_GREY := Color(0.53, 0.51, 0.47)
const IRON_BLACK := Color(0.13, 0.13, 0.145)
const TIMBER_BROWN := Color(0.34, 0.23, 0.15)
const ROOF_TERRACOTTA := Color(0.60, 0.30, 0.21)
const LIT_AMBER := Color(1.0, 0.80, 0.44)
const LINEN_WHITE := Color(0.90, 0.88, 0.83)
const AZULEJO_PALE := Color(0.83, 0.88, 0.92)
## The third tile value. A tiled front is a pale field, a coloured ground and a
## near-navy border, and two of those three read as one flat blue at 80 m —
## which is exactly what round 1 saw. The deep is what draws the panelling.
const AZULEJO_DEEP := Color(0.105, 0.205, 0.425)
## Louvred shutters. Porto paints them in a handful of dark colours against the
## painted render, never in the render's own colour, and that third value beside
## the white surround and the black opening is most of what draws a window at
## the distance these are actually seen from.
const SHUTTER_GREEN := Color(0.155, 0.235, 0.185)
## Zinc rainwater goods: gutters, hoppers, downpipes. Pale enough to draw a line
## down a dark facade and dark enough to draw one down a pale facade.
const ZINC_GREY := Color(0.415, 0.425, 0.435)

# Fixed tile sizes. Every facade must pass the *same* numbers or the factory
# cache misses and the terrace fragments into one material per building.
const WALL_TILE := 1.7
const TRIM_TILE := 0.9
const GRANITE_TILE := 1.3
const IRON_TILE := 0.55
const TIMBER_TILE := 0.7
const ROOF_TILE := 0.8
const TILEWORK_TILE := 0.42
const LINEN_TILE := 0.4

const LIT_ENERGY := 1.7

static var _iron_thin: StandardMaterial3D
static var _linen_thin: StandardMaterial3D

## Distant terraces cast a shadow the eye reads as a blob, and shadow passes are
## the one cost baking does not remove. The placement stream turns this off for
## the far hillside rows.
var cast_shadows := true

var _bakers: Dictionary = {}
## Insertion order, so the committed child nodes come out identical run to run.
## A Dictionary preserves order in GDScript, but leaning on that for scene
## structure is the kind of assumption that breaks quietly.
var _order: Array[Material] = []


# --- Registry ----------------------------------------------------------------

## The baker accumulating geometry for `mat`, created on first ask.
func baker(mat: Material) -> MeshBaker:
	var b: MeshBaker = _bakers.get(mat)
	if b == null:
		b = MeshBaker.new()
		_bakers[mat] = b
		_order.append(mat)
	return b


func triangle_count() -> int:
	var total := 0
	for mat in _order:
		total += (_bakers[mat] as MeshBaker).triangle_count()
	return total


## How many draw calls this batch will cost — one per material that got used.
func surface_count() -> int:
	var used := 0
	for mat in _order:
		if (_bakers[mat] as MeshBaker).triangle_count() > 0:
			used += 1
	return used


## Weld everything and return a Node3D holding one MeshInstance3D per material.
##
## The node is left at the origin: geometry is baked at each Spec's own
## position, so moving the returned node moves the whole row.
func commit(node_name: String = "Facades") -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var index := 0
	for mat in _order:
		var b: MeshBaker = _bakers[mat]
		if b.triangle_count() == 0:
			continue
		var mi := b.commit(mat, "%s_%d" % [node_name, index])
		if not cast_shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		index += 1
	return root


# --- Materials ---------------------------------------------------------------

## Painted render — the body of most Ribeira houses. Colour comes from the
## caller's palette; keep that palette short.
static func plaster(color: Color) -> StandardMaterial3D:
	return ToonFactory.plaster(color, WALL_TILE)


## Painted stone dressings: architraves, sills, cornices, chimney shafts. Porto
## picks these out in white against the colour, which is what draws the window
## grid at distance.
static func trim() -> StandardMaterial3D:
	return ToonFactory.stone(TRIM_WHITE, TRIM_TILE)


## Bare granite: the street-level plinth every one of these buildings stands on,
## and the whole wall on the unpainted ones.
static func granite(color: Color = GRANITE_GREY) -> StandardMaterial3D:
	return ToonFactory.stone(color, GRANITE_TILE)


## Wrought iron with thickness — balcony top rails, brackets.
static func iron() -> StandardMaterial3D:
	return ToonFactory.iron(IRON_BLACK, IRON_TILE, 0.45, 0.55)


## Wrought iron for single-quad members. See the header: culling off so a
## baluster stays a baluster from behind.
static func iron_thin() -> StandardMaterial3D:
	if _iron_thin == null:
		_iron_thin = iron().duplicate()
		_iron_thin.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _iron_thin


## Shutters, doors, shopfront stall risers, signboards.
static func timber(color: Color = TIMBER_BROWN) -> StandardMaterial3D:
	return ToonFactory.wood(color, TIMBER_TILE)


## Barrel roof tiles.
static func roof(color: Color = ROOF_TERRACOTTA) -> StandardMaterial3D:
	return ToonFactory.terracotta(color, ROOF_TILE)


## Glazed azulejo facing. The hard specular off a tile front is the entire
## reason these read as Porto and not as blue paint.
static func tilework(color: Color) -> StandardMaterial3D:
	return ToonFactory.ceramic(color, TILEWORK_TILE)


## Rainwater goods. Rolled zinc is a dielectric with a sheen, not bare metal, so
## it goes through iron() rather than getting its own recipe.
static func zinc() -> StandardMaterial3D:
	return ToonFactory.iron(ZINC_GREY, 0.5, 0.0, 0.42)


## Whatever is behind a window: no detail map, fully rough, no specular to
## catch. It has to read as an absence, not as a dark surface.
static func reveal_dark() -> StandardMaterial3D:
	return ToonFactory.solid(REVEAL_BLACK, 0.0, 1.0)


## A window with someone home. One colour and one energy for the whole city, so
## every lit pane in every terrace shares a single material.
static func lit() -> StandardMaterial3D:
	return ToonFactory.glow(LIT_AMBER, LIT_ENERGY)


## Hung washing and shopfront awnings — single quads, so culling off.
static func linen_thin() -> StandardMaterial3D:
	if _linen_thin == null:
		_linen_thin = ToonFactory.cloth(LINEN_WHITE, LINEN_TILE).duplicate()
		_linen_thin.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _linen_thin
