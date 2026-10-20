@tool
class_name TerrainField
extends RefCounted
## Carte de colonnes de l'île à la résolution de 20 cm : source de vérité du relief pour TOUS les
## générateurs (terrain, village, placement, végétation, validation). Tout est exprimé en cellules
## monde de 20 cm (y absolu) ; les mètres ne servent qu'aux interfaces.
##
## Invariants (vérifiés par WorldValidator) :
##   core_top[c]  = natural_top[c] − SURFACE_DEPTH : le cœur fixe est défini par le relief NATUREL.
##   top[c]       ≥ core_top[c] + MIN_SURFACE : aucune modification ne descend dans le cœur.
##   Les aménagements (plateformes, chemins, escaliers) ne changent que `top`, jamais le cœur.

const V := VoxelGrid.VOXEL_SIZE
const NO_GROUND := -32768
const SURFACE_DEPTH := IslandGenerator.SURFACE_DEPTH
const MIN_SURFACE := 2

enum Zone { NATURAL, PLAZA, PLOT, ROAD, STAIR, RETAIN, GARDEN, PORT }
const ZONE_NAMES := ["naturel", "place", "parcelle", "chemin", "escalier", "soutènement", "jardin", "port"]

var seed := 0
var profile_key := ""
var n := 0                         # colonnes par côté
var origin := Vector2i.ZERO       # cellule monde (x, z) de la colonne (0, 0)
var top := PackedInt32Array()
var natural_top := PackedInt32Array()
var core_top := PackedInt32Array()
var bottom := PackedInt32Array()   # cellule la plus basse de la sous-face
var material := PackedByteArray()  # matière du dessus (id de palette)
var zone := PackedByteArray()
var edge_dist := PackedFloat32Array()  # distance (m) au vide le plus proche
var plateaus: Array = []              # [{id, level, cells, centroid(Vector2 m), rect(Rect2i colonnes), edge_m}]
var radius_m := 0.0
var landmarks: Dictionary = {}        # positions utiles (m) : centre, extrémités…
var edits: Array = []                 # journal des modifications (type, rect, détails)

func init_size(p_n: int) -> void:
	n = p_n
	origin = Vector2i(-n / 2, -n / 2)
	var count := n * n
	top.resize(count)
	top.fill(NO_GROUND)
	natural_top.resize(count)
	natural_top.fill(NO_GROUND)
	core_top.resize(count)
	core_top.fill(NO_GROUND)
	bottom.resize(count)
	bottom.fill(NO_GROUND)
	material.resize(count)
	zone.resize(count)
	edge_dist.resize(count)

func idx(cx: int, cz: int) -> int:
	return cx + cz * n

func in_bounds(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < n and cz < n

func has_ground(cx: int, cz: int) -> bool:
	return in_bounds(cx, cz) and top[cx + cz * n] != NO_GROUND

func top_at(cx: int, cz: int) -> int:
	return top[cx + cz * n] if in_bounds(cx, cz) else NO_GROUND

## Colonne contenant le point (x, z) en mètres.
func col_of_m(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / V) - origin.x, floori(z / V) - origin.y)

func center_m(cx: int, cz: int) -> Vector2:
	return Vector2((origin.x + cx + 0.5) * V, (origin.y + cz + 0.5) * V)

## Altitude (m) de la surface au-dessus de la colonne ; NAN si vide.
func ground_y_m(cx: int, cz: int) -> float:
	var t := top_at(cx, cz)
	return NAN if t == NO_GROUND else float(t + 1) * V

func ground_at_m(x: float, z: float) -> float:
	var c := col_of_m(x, z)
	return ground_y_m(c.x, c.y)

func edge_at_m(x: float, z: float) -> float:
	var c := col_of_m(x, z)
	return edge_dist[idx(c.x, c.y)] if has_ground(c.x, c.y) else 0.0

func zone_at(cx: int, cz: int) -> int:
	return zone[idx(cx, cz)] if in_bounds(cx, cz) else Zone.NATURAL

## Plus grande différence de hauteur (cellules) avec les 4 voisines (vide = ignoré).
func step_at(cx: int, cz: int) -> int:
	var t := top_at(cx, cz)
	if t == NO_GROUND:
		return 0
	var m := 0
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var u := top_at(cx + o.x, cz + o.y)
		if u != NO_GROUND:
			m = maxi(m, absi(t - u))
	return m

## Écart de hauteur (cellules) sur un rectangle de colonnes.
func height_range(rect: Rect2i) -> Vector2i:
	var lo := 1 << 30
	var hi := -(1 << 30)
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			var t := top_at(cx, cz)
			if t == NO_GROUND:
				return Vector2i(NO_GROUND, NO_GROUND)
			lo = mini(lo, t)
			hi = maxi(hi, t)
	return Vector2i(lo, hi)

func land_count() -> int:
	var c := 0
	for t in top:
		if t != NO_GROUND:
			c += 1
	return c

## Modifie la hauteur d'une colonne EN PROTÉGEANT LE CŒUR : refuse toute descente sous
## core_top + MIN_SURFACE. Renvoie true si la colonne a changé.
func set_top(cx: int, cz: int, new_top: int, new_zone := -1, new_material := -1) -> bool:
	if not has_ground(cx, cz):
		return false
	var i := idx(cx, cz)
	if new_top < core_top[i] + MIN_SURFACE:
		return false
	var changed := top[i] != new_top
	top[i] = new_top
	if new_zone >= 0:
		zone[i] = new_zone
	if new_material >= 0:
		material[i] = new_material
	return changed

## Carte de contrôle (PNG) : altitude en teintes, zones en couleurs vives.
func to_image() -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var zone_colors := [Color(0, 0, 0, 0), Color("e8e0c8"), Color("d4a054"), Color("a09080"), Color("ffffff"), Color("606060"), Color("7bc86c"), Color("6fa8dc")]
	for cz in n:
		for cx in n:
			var t := top_at(cx, cz)
			if t == NO_GROUND:
				img.set_pixel(cx, cz, Color(0.08, 0.1, 0.18))
				continue
			var h := clampf(float(t) * V / 12.0, 0.0, 1.0)
			var c := Color(0.15 + h * 0.5, 0.3 + h * 0.6, 0.2 + h * 0.2)
			var z := zone[idx(cx, cz)]
			if z != Zone.NATURAL:
				c = c.lerp(zone_colors[z], 0.75)
			img.set_pixel(cx, cz, c)
	return img
