@tool
class_name WorldNav
extends RefCounted
## Accessibilité à hauteur de personnage (≈ 1,80 m) sur la carte de colonnes de 20 cm.
## Une marche est franchissable si la différence de hauteur entre deux colonnes voisines est de
## 1 cellule (20 cm) au plus. Les obstacles durs (bâtiments, rochers, tonneaux…) bloquent les cellules
## qu'ils couvrent au niveau du sol.

const MAX_STEP := 1
const NEIGH := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Cellules (index de colonne) marchables : zone de circulation + non bloquées par un volume dur.
static func blocked_mask(field: TerrainField, occ: OccupancyMap) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(field.n * field.n)
	for item in occ.items:
		if item["kind"] == "building" or item["kind"] == "rock" or item["kind"] == "tree" or item["kind"] == "prop" or item["kind"] == "structure":
			for b: AABB in item["hard"]:
				# Seuls les volumes qui touchent le niveau de marche (≤ 1,8 m au-dessus de la base) bloquent.
				var ground: float = item["pos"].y
				if b.position.y > ground + 1.8 or b.end.y < ground + 0.05:
					continue
				var c0 := field.col_of_m(b.position.x, b.position.z)
				var c1 := field.col_of_m(b.end.x - 1e-4, b.end.z - 1e-4)
				for cz in range(c0.y, c1.y + 1):
					for cx in range(c0.x, c1.x + 1):
						if field.in_bounds(cx, cz):
							mask[cx + cz * field.n] = 1
	return mask

## BFS de marche. `allowed` : masque (1 = cellule autorisée). Renvoie l'ensemble des index atteints.
static func flood(field: TerrainField, start: Vector2i, allowed: PackedByteArray, blocked := PackedByteArray()) -> Dictionary:
	var seen := {}
	if not field.has_ground(start.x, start.y):
		return seen
	var queue := [start]
	seen[start.x + start.y * field.n] = true
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var t := field.top_at(c.x, c.y)
		for o in NEIGH:
			var x: int = c.x + o.x
			var z: int = c.y + o.y
			if not field.has_ground(x, z):
				continue
			var i := x + z * field.n
			if seen.has(i) or allowed[i] == 0:
				continue
			if not blocked.is_empty() and blocked[i] != 0:
				continue
			if absi(field.top[i] - t) > MAX_STEP:
				continue
			seen[i] = true
			queue.append(Vector2i(x, z))
	return seen

## Les colonnes de circulation d'une île forment-elles une seule composante depuis `start` ?
static func network_components(field: TerrainField, allowed: PackedByteArray) -> Array:
	var comps := []
	var visited := {}
	for i in field.n * field.n:
		if allowed[i] == 0 or visited.has(i):
			continue
		var f := flood(field, Vector2i(i % field.n, i / field.n), allowed)
		for k in f:
			visited[k] = true
		comps.append(f.size())
	return comps
