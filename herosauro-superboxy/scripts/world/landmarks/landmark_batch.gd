extends RefCounted
## Groups landmark geometry by material so a monument costs a handful of draw
## calls, and so several monuments can share one set of them.
##
## A MeshBaker produces exactly one surface with exactly one material. A tower
## that mixes body granite, picked-out dressings, black openings, terracotta and
## an iron cross needs one baker per material — five draw calls whether the tower
## has forty triangles or four thousand, which is what pays for the detail.
##
## The bigger win is sharing the registry. Hand the same Batch to all five
## landmarks and the whole Porto skyline — tower, cathedral, monastery, church,
## lodges — commits to roughly nine draw calls total, because they are all built
## out of the same nine surfaces. ToonFactory caches by parameter set, so two
## calls with identical arguments hand back the identical Material object and the
## registry keys on that.
##
## Which is why every tile size below is a constant. Passing an ad-hoc tile size
## misses the factory cache, and one careless call site turns a shared granite
## into a private one plus a draw call.

# --- Palette -----------------------------------------------------------------
# Porto granite is a warm mid grey that goes almost gold under a low sun, and it
# is nearly everything here: tower, cathedral, quay, church dressings. The three
# tones are body, picked-out dressing and shadowed crown — the same stone at
# three ages of weathering, not three different rocks.

const GRANITE_BODY := Color(0.55, 0.53, 0.48)
const GRANITE_DRESS := Color(0.69, 0.67, 0.61)
const GRANITE_DARK := Color(0.42, 0.41, 0.38)
const LIMEWASH := Color(0.85, 0.83, 0.77)
## The second and last limewash tone. A row of sheds wants two ages of paint;
## every tone past that is another material and another draw call.
const LIMEWASH_WARM := Color(0.83, 0.79, 0.71)
const TERRACOTTA := Color(0.58, 0.29, 0.21)
const TILE_BLUE := Color(0.17, 0.36, 0.64)
const TILE_DEEP := Color(0.11, 0.24, 0.50)
const TILE_WHITE := Color(0.85, 0.88, 0.90)
const IRON_BLACK := Color(0.13, 0.13, 0.15)
const TIMBER_BROWN := Color(0.31, 0.20, 0.13)
## Openings have to read as an absence, not as a dark surface: no detail map,
## fully rough, nothing for the sun to catch.
const VOID_BLACK := Color(0.045, 0.045, 0.05)
const SIGN_CREAM := Color(0.93, 0.90, 0.82)

# Fixed tile sizes. Every landmark must pass these same numbers or the factory
# cache misses and the skyline fragments into one material per building.
const GRANITE_TILE := 1.8
const DRESS_TILE := 0.9
const LIMEWASH_TILE := 2.0
const ROOF_TILE := 0.8
const TILEWORK_TILE := 0.42
const IRON_TILE := 0.55
const TIMBER_TILE := 0.7

static var _sign_flat: StandardMaterial3D

## Distant landmarks cast a shadow the eye reads as a blob, and the shadow pass
## is the one cost baking does not remove. The placement stream turns this off
## for anything past the far bank.
var cast_shadows := true

var _bakers: Dictionary = {}
## Insertion order, so committed children come out identical run to run. A
## Dictionary does preserve order in GDScript, but leaning on that for scene
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
## The node is left at the origin: geometry is baked at whatever transform the
## caller passed in, so moving the returned node moves the whole skyline.
func commit(node_name: String = "Landmarks") -> Node3D:
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

## The body stone: tower shafts, cathedral mass, church walls.
static func granite(color: Color = GRANITE_BODY) -> StandardMaterial3D:
	return ToonFactory.stone(color, GRANITE_TILE)


## Dressings — cornices, pilasters, architraves, balustrades, quoins. A shade
## lighter than the body, because that contrast is what draws the architecture
## at a distance where no single moulding is resolvable.
static func dress() -> StandardMaterial3D:
	return ToonFactory.stone(GRANITE_DRESS, DRESS_TILE)


## Shadowed stone: plinths, crowns, the underside of everything.
static func dark_stone() -> StandardMaterial3D:
	return ToonFactory.stone(GRANITE_DARK, GRANITE_TILE)


## Limewashed render — monastery wings, lodge walls, church flanks.
static func limewash(color: Color = LIMEWASH) -> StandardMaterial3D:
	return ToonFactory.plaster(color, LIMEWASH_TILE)


## Barrel roof tiles.
static func roof(color: Color = TERRACOTTA) -> StandardMaterial3D:
	return ToonFactory.terracotta(color, ROOF_TILE)


## Glazed azulejo. The hard specular kick off a tile front is the entire reason
## these read as Porto and not as blue paint, which is why ceramic() is rough
## 0.14 while every other surface here is 0.8 and up.
static func tile_blue(color: Color = TILE_BLUE) -> StandardMaterial3D:
	return ToonFactory.ceramic(color, TILEWORK_TILE)


static func tile_white() -> StandardMaterial3D:
	return ToonFactory.ceramic(TILE_WHITE, TILEWORK_TILE)


## Wrought iron: crosses, weathervanes, sign frames, gallery rails.
static func iron() -> StandardMaterial3D:
	return ToonFactory.iron(IRON_BLACK, IRON_TILE, 0.45, 0.55)


## Doors, shutters, lodge gates.
static func timber(color: Color = TIMBER_BROWN) -> StandardMaterial3D:
	return ToonFactory.wood(color, TIMBER_TILE)


## Whatever is behind an opening.
static func void_dark() -> StandardMaterial3D:
	return ToonFactory.solid(VOID_BLACK, 0.0, 1.0)


## Painted lodge lettering. Single quads with no thickness, so culling is off —
## a back-face-culled letter vanishes the moment the sun swings behind the sign,
## and half the day the river bank is exactly that. Cached statically so every
## sign in Gaia still shares one material.
static func sign_face() -> StandardMaterial3D:
	if _sign_flat == null:
		_sign_flat = ToonFactory.plaster(SIGN_CREAM, 1.2).duplicate()
		_sign_flat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _sign_flat
