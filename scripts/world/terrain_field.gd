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

## Copie indépendante (tableaux dupliqués) : la vue 3D travaille sur sa copie (elle y ajoute la sous-face, etc.) sans toucher
## le terrain de l'éditeur (Lot 11 : plus de recalcul du relief au passage éditeur → 3D).
func duplicate_field() -> TerrainField:
	var f := TerrainField.new()
	f.seed = seed
	f.profile_key = profile_key
	f.n = n
	f.origin = origin
	f.top = top.duplicate()
	f.natural_top = natural_top.duplicate()
	f.core_top = core_top.duplicate()
	f.bottom = bottom.duplicate()
	f.material = material.duplicate()
	f.zone = zone.duplicate()
	f.edge_dist = edge_dist.duplicate()
	f.plateaus = plateaus.duplicate(true)
	f.radius_m = radius_m
	f.landmarks = landmarks.duplicate(true)
	f.edits = edits.duplicate(true)
	return f

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

## Supprime les petits blocs isolés laissés par le nivellement : toute zone NATURELLE de colonnes de même hauteur,
## de `max_size` colonnes au plus, entourée de colonnes plus hautes ou plus basses, prend la hauteur de son voisinage
## le plus proche (jamais sous le cœur fixe : passe par set_top). Renvoie le nombre de colonnes modifiées.
func remove_small_blocks(max_size: int, reserved := PackedByteArray()) -> int:
	var seen := PackedByteArray()
	seen.resize(n * n)
	var changed := 0
	for s0 in n * n:
		if top[s0] == NO_GROUND or seen[s0] == 1 or zone[s0] != Zone.NATURAL:
			continue
		var h := top[s0]
		var comp: Array[int] = [s0]
		seen[s0] = 1
		var k := 0
		var ok := true
		var neigh := {}
		while k < comp.size():
			var i: int = comp[k]
			k += 1
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x: int = i % n + o.x
				var z: int = i / n + o.y
				if x < 0 or z < 0 or x >= n or z >= n:
					continue
				var j := x + z * n
				if top[j] == NO_GROUND:
					ok = false          # touche le vide : bord de falaise, on n'y touche pas
				elif top[j] == h and zone[j] == Zone.NATURAL:
					if seen[j] == 0:
						seen[j] = 1
						comp.append(j)
						if comp.size() > max_size:
							ok = false
				elif top[j] == h:
					ok = false          # touche une zone aménagée
				else:
					neigh[top[j]] = int(neigh.get(top[j], 0)) + 1
			if not ok and comp.size() > max_size:
				break
		if not ok or comp.size() > max_size or neigh.is_empty():
			continue
		if not reserved.is_empty():
			var held := false
			for i in comp:
				if reserved[i] != 0:
					held = true
					break
			if held:
				continue        # emprise réservée (objet posé) : le sol ne bouge plus
		var best := h
		var best_n := 0
		for v in neigh:
			if neigh[v] > best_n or (neigh[v] == best_n and absi(v - h) < absi(best - h)):
				best_n = neigh[v]
				best = v
		if absi(best - h) > 2:
			continue
		for i in comp:
			if set_top(i % n, i / n, best):
				changed += 1
	return changed

## Comble les petites cuvettes isolées des pelouses : plateau de colonnes NATURELLES de même hauteur (`max_size` colonnes au plus)
## dont tout le pourtour est plus haut. Il monte jusqu'au point de débordement (le plus bas voisin), de 2 cellules au plus ;
## plusieurs passes comblent une cuvette étagée. Les ravines (qui ont une sortie plus basse), les falaises (contact avec le vide),
## les marches, chemins, parcelles et emprises réservées ne sont jamais touchés. Renvoie le nombre de colonnes modifiées.
func fill_hollows(max_size := 48, passes := 3, reserved := PackedByteArray()) -> int:
	var changed := 0
	for pass_i in passes:
		var seen := PackedByteArray()
		seen.resize(n * n)
		var did := 0
		for s0 in n * n:
			if top[s0] == NO_GROUND or seen[s0] == 1 or zone[s0] != Zone.NATURAL:
				continue
			var h := top[s0]
			var comp: Array[int] = [s0]
			seen[s0] = 1
			var k := 0
			var ok := true
			var rim := 1 << 20
			while k < comp.size() and ok:
				var i: int = comp[k]
				k += 1
				if not reserved.is_empty() and reserved[i] != 0:
					ok = false
					break
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var x: int = i % n + o.x
					var z: int = i / n + o.y
					if x < 0 or z < 0 or x >= n or z >= n:
						ok = false
						break
					var j := x + z * n
					if top[j] == NO_GROUND or zone[j] != Zone.NATURAL or top[j] < h:
						ok = false          # vide, zone aménagée ou sortie plus basse (ravine)
						break
					if top[j] == h:
						if seen[j] == 0:
							seen[j] = 1
							comp.append(j)
							if comp.size() > max_size:
								ok = false
								break
					else:
						rim = mini(rim, top[j])
			if not ok or comp.size() > max_size or rim == 1 << 20:
				continue
			var target := mini(rim, h + 2)
			for i in comp:
				if set_top(i % n, i / n, target):
					changed += 1
					did += 1
		if did == 0:
			break
	return changed
