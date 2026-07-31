extends RefCounted
## Groups landform geometry by material so a whole riverbank commits to a
## handful of draw calls.
##
## Same registry idea as the facade batcher next door, and for the same reason: a
## MeshBaker makes exactly one surface with exactly one material, and a bank made
## of coursed granite, cobbles, earth, rock, ironwork and foliage needs one baker
## per material. Doing the grouping per *reach* rather than per feature is what
## makes the detail affordable — every block in four hundred metres of quay wall,
## every buttress, every step of every escadaria lands in one granite surface.
##
## Two batches per world, not one. The near reach (the water either side of the
## bridge, where the camera actually is) casts shadows; the far reach up- and
## downstream does not. A baked mesh is culled and shadow-mapped as a unit, so a
## single surface spanning 190 m of river would push its whole triangle count
## through four shadow cascades on account of the near end alone. Splitting the
## bake at the point where the sun's shadow range ends costs a few extra draw
## calls and bounds that.
##
## MATERIAL SHARING. Four of the parameter sets below are byte-identical to the
## ones the facade batcher asks for. That is deliberate, not coincidence:
## ToonFactory caches by parameter set and hands back the same object, so the
## city's granite plinths and the quay wall are one material and one draw call's
## worth of state. Changing a number here silently forks them apart. There is no
## import between the two files on purpose — a shared constant would couple two
## streams for the sake of four colours.

# --- Palette -----------------------------------------------------------------

## Coursed masonry: quay walls, retaining walls, buttresses, abutment skirts.
## MATCHES the facade batcher's granite() — see the header.
const GRANITE := Color(0.53, 0.51, 0.47)
const GRANITE_TILE := 1.3

## Dressed granite: copings, kerbs, step treads, bollards, stair cheeks. Paler
## and smoother than the wall it sits on, which is the whole point — the coping
## line is what draws the top of a quay wall from across the river.
const DRESSED := Color(0.63, 0.61, 0.56)
const DRESSED_TILE := 0.85

## Setts. Porto's calçada is pale granite, and it is the brightest large surface
## on either bank — the promenade is what separates the dark water from the dark
## masonry above it.
const COBBLE := Color(0.58, 0.56, 0.51)
const COBBLE_TILE := 0.75

## Bare earth and hill fill: the slopes behind the top terrace, cut faces, the
## ground under the vegetation. Very large tile — these are 40 m surfaces and a
## tight noise on one is shimmer and nothing else.
const EARTH := Color(0.33, 0.28, 0.21)
const EARTH_TILE := 6.0

## Schist/granite bedrock of the Serra do Pilar bluff. Warmer and lighter than
## the earth so the cliff reads as rock breaking out of the hillside.
const ROCK := Color(0.47, 0.43, 0.37)
const ROCK_TILE := 2.8

## Wrought iron: handrails, mooring rings, area railings.
## MATCHES the facade batcher's iron().
const IRON := Color(0.13, 0.13, 0.145)
const IRON_TILE := 0.55

## Whatever is behind an opening: weep holes, alley mouths, the dark under an
## arch. No detail map, fully rough, nothing to catch a highlight — it has to
## read as an absence rather than as a dark surface.
## MATCHES the facade batcher's reveal_dark().
const VOID_DARK := Color(0.055, 0.05, 0.055)

## Cypress, ivy and the shaded underside of every canopy. Deep and desaturated:
## against a golden-hour sky the Porto bank's planting is very nearly silhouette,
## and anything greener than this reads as plastic.
const FOLIAGE_DARK := Color(0.115, 0.175, 0.115)
## Plane and jacaranda canopies catching the low sun — the one warm green.
const FOLIAGE_LIT := Color(0.255, 0.315, 0.150)
const FOLIAGE_TILE := 0.55

## Trunks, planter staves, mooring timbers.
const TIMBER := Color(0.28, 0.21, 0.15)
const TIMBER_TILE := 0.7

## Port pipes and packing crates on the Gaia cais. Its own tone, well up from
## TIMBER: a stack of casks in trunk-brown next to iron-black hoops reads at
## seventy metres as one amorphous dark blob, which is what the first render of
## the lodge yard produced. Coopered oak is a good deal paler than a plane tree,
## and the value gap against the hoops is the only thing that makes a barrel a
## barrel at that range.
const COOPERAGE := Color(0.475, 0.325, 0.185)
const COOPERAGE_TILE := 0.5

## Cafe parasols and shop awnings on the Ribeira. Two tones and no more: the
## whole point of a quayside terrace at forty metres is the RHYTHM of bright
## canopies against dark gaps, and two values give that a beat without turning
## fifty umbrellas into fifty materials. Cream is the common one; the red is the
## accent that stops a row of them reading as one long stripe.
const CANVAS_CREAM := Color(0.855, 0.815, 0.735)
const CANVAS_RED := Color(0.660, 0.285, 0.235)
const CANVAS_TILE := 0.4

## Painted lettering on the Gaia sign frames. Off-white rather than pure: it sits
## against a bright sky and pure white would clip through the tonemapper's
## shoulder before the letterforms could read.
const SIGN_FACE := Color(0.900, 0.885, 0.845)

static var _canvas_two_sided: Dictionary = {}

static var _foliage_two_sided: Dictionary = {}

## Distant reaches drop out of the shadow pass; see the header.
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


## Shorthands, so call sites read as material names rather than as lookups.
func granite() -> MeshBaker:
	return baker(granite_mat())


func dressed() -> MeshBaker:
	return baker(dressed_mat())


func cobble() -> MeshBaker:
	return baker(cobble_mat())


func earth() -> MeshBaker:
	return baker(earth_mat())


func rock() -> MeshBaker:
	return baker(rock_mat())


func iron() -> MeshBaker:
	return baker(iron_mat())


func dark() -> MeshBaker:
	return baker(dark_mat())


func leaf_dark() -> MeshBaker:
	return baker(foliage_mat(FOLIAGE_DARK))


func leaf_lit() -> MeshBaker:
	return baker(foliage_mat(FOLIAGE_LIT))


func timber() -> MeshBaker:
	return baker(timber_mat())


func cooperage() -> MeshBaker:
	return baker(cooperage_mat())


func canvas(warm: bool = false) -> MeshBaker:
	return baker(canvas_mat(CANVAS_RED if warm else CANVAS_CREAM))


func sign_face() -> MeshBaker:
	return baker(sign_face_mat())


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
## The node belongs at the origin: every kit here bakes in world coordinates, so
## moving the returned node moves the riverbank off the river.
func commit(node_name: String = "Terrain") -> Node3D:
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

static func granite_mat() -> StandardMaterial3D:
	return ToonFactory.stone(GRANITE, GRANITE_TILE)


static func dressed_mat() -> StandardMaterial3D:
	return ToonFactory.stone(DRESSED, DRESSED_TILE)


static func cobble_mat() -> StandardMaterial3D:
	return ToonFactory.cobblestone(COBBLE, COBBLE_TILE)


static func earth_mat() -> StandardMaterial3D:
	return ToonFactory.stone(EARTH, EARTH_TILE)


static func rock_mat() -> StandardMaterial3D:
	return ToonFactory.stone(ROCK, ROCK_TILE)


static func iron_mat() -> StandardMaterial3D:
	return ToonFactory.iron(IRON, IRON_TILE, 0.45, 0.55)


static func dark_mat() -> StandardMaterial3D:
	return ToonFactory.solid(VOID_DARK, 0.0, 1.0)


static func timber_mat() -> StandardMaterial3D:
	return ToonFactory.wood(TIMBER, TIMBER_TILE)


static func cooperage_mat() -> StandardMaterial3D:
	return ToonFactory.wood(COOPERAGE, COOPERAGE_TILE)


## Awning and parasol cloth. Culling is OFF for the same reason the foliage is:
## a canopy is a single-thickness sheet, and a back-face-culled one disappears
## the moment the camera drops under its lip — which from a bridge deck twelve
## metres above the quay is exactly what happens to the near ones.
static func canvas_mat(color: Color) -> StandardMaterial3D:
	var cached: StandardMaterial3D = _canvas_two_sided.get(color)
	if cached != null:
		return cached
	var m: StandardMaterial3D = ToonFactory.cloth(color, CANVAS_TILE).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_canvas_two_sided[color] = m
	return m


## Painted sign lettering. Flat and chalky: it is house paint on a steel plate,
## and any specular on it at eighty metres is a sparkle, not a highlight.
static func sign_face_mat() -> StandardMaterial3D:
	return ToonFactory.plaster(SIGN_FACE, 0.9)


## Foliage. Culling is OFF: canopies and ivy are built from thin shells and open
## fans, and a back-face-culled leaf mass turns into a hole the moment the sun
## swings behind it. Two duplicates for the whole world, cached statically, so
## the saving in triangles does not come back as a material per tree.
static func foliage_mat(color: Color) -> StandardMaterial3D:
	var cached: StandardMaterial3D = _foliage_two_sided.get(color)
	if cached != null:
		return cached
	# Plaster grain at a tight tile is the cheapest thing that breaks a canopy
	# into something other than a flat blob; heavy AO does the rest.
	var m: StandardMaterial3D = ToonFactory.build(
			color, ToonFactory.Surface.PLASTER, 0.97, 0.0, FOLIAGE_TILE, 1.6, 0.55
	).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_foliage_two_sided[color] = m
	return m
