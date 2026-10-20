@tool
class_name PathNetwork
extends RefCounted
## Réseau de chemins : A* sur les colonnes de 20 cm (coût de pente, réemploi des chemins existants,
## évitement des parcelles), puis TERRASSEMENT du tracé pour qu'il soit réellement praticable :
## marches de 20 cm au plus, jamais plus d'une marche tous les 40 cm (≈ 27°), largeur constante,
## raccord de pente sur les côtés. Les tronçons à marches sont marqués STAIR.

const V := VoxelGrid.VOXEL_SIZE

var field: TerrainField
var occ: OccupancyMap
var placement: PlacementSystem
var road_cells := {}            # index de colonne → hauteur du tracé
var routes: Array = []          # [{from, to, cells, width, material, ok}]
var failures: Array = []

func _init(p_field: TerrainField, p_occ: OccupancyMap, p_placement: PlacementSystem) -> void:
	field = p_field
	occ = p_occ
	placement = p_placement

# ------------------------------------------------------------------ A*

func _cost(i: int, from_i: int) -> float:
	var t := field.top[i]
	if t == TerrainField.NO_GROUND or field.edge_dist[i] < 1.0:
		return -1.0
	var tg := occ.tag[i]
	if tg == PlacementSpec.TAG_PLOT or tg == PlacementSpec.TAG_ITEM or tg == PlacementSpec.TAG_PORT or tg == PlacementSpec.TAG_GARDEN:
		return -1.0
	var c := 1.0
	if road_cells.has(i):
		c = 0.3
	else:
		var d := absi(t - field.top[from_i])
		c += 5.0 * float(d * d)
		var m := int(field.material[i])
		if field.zone[i] == TerrainField.Zone.RETAIN:
			c += 8.0
	return c

## Chemin entre deux colonnes (listes de colonnes) ou [] si aucun.
func find_route(a: Vector2i, b: Vector2i) -> Array:
	var n := field.n
	var start := a.x + a.y * n
	var goal := b.x + b.y * n
	var g := {}
	var came := {}
	var heap: Array = []   # tas binaire de [f, index]
	g[start] = 0.0
	_heap_push(heap, [_h(a, b), start])
	var closed := {}
	var expansions := 0
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var i: int = top[1]
		if closed.has(i):
			continue
		if i == goal:
			var path: Array[Vector2i] = []
			var k := goal
			while k != start:
				path.append(Vector2i(k % n, k / n))
				k = came[k]
			path.append(a)
			path.reverse()
			return path
		closed[i] = true
		expansions += 1
		if expansions > 60000:
			break
		var cx := i % n
		var cz := i / n
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var x: int = cx + dx
				var z: int = cz + dz
				if not field.in_bounds(x, z):
					continue
				var j := x + z * n
				if closed.has(j):
					continue
				var c := _cost(j, i)
				if c < 0.0 and j != goal:
					continue
				if c < 0.0:
					c = 1.0
				if dx != 0 and dz != 0:
					c *= 1.4142
				var ng: float = g[i] + c
				if not g.has(j) or ng < g[j]:
					g[j] = ng
					came[j] = i
					_heap_push(heap, [ng + _h(Vector2i(x, z), b), j])
	return []

static func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(a.x - b.x)
	var dz := absf(a.y - b.y)
	return maxf(dx, dz) + 0.4142 * minf(dx, dz)

static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if heap[p][0] <= heap[i][0]:
			break
		var t = heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p

static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < heap.size() and heap[l][0] < heap[m][0]:
				m = l
			if r < heap.size() and heap[r][0] < heap[m][0]:
				m = r
			if m == i:
				break
			var t = heap[m]
			heap[m] = heap[i]
			heap[i] = t
			i = m
	return top

# ------------------------------------------------------------------ construction du tracé

## Relie deux colonnes ; width_m = largeur ; end_heights : hauteurs imposées aux extrémités
## (cellules) ou -1 pour suivre le relief. Renvoie la route ou {} si impossible.
func connect_points(a: Vector2i, b: Vector2i, width_m: float, material_key: String, fixed_a := -1, fixed_b := -1) -> Dictionary:
	var cells := find_route(a, b)
	if cells.size() < 2:
		failures.append({"from": a, "to": b, "reason": "aucun_chemin"})
		return {}
	var k := cells.size()
	var h := PackedInt32Array()
	h.resize(k)
	for i in k:
		var idx: int = cells[i].x + cells[i].y * field.n
		h[i] = road_cells[idx] if road_cells.has(idx) else field.top[idx]
	# Lissage par moyenne glissante (suit le relief sans coller aux paliers).
	var sm := PackedInt32Array()
	sm.resize(k)
	for i in k:
		var s := 0
		var c := 0
		for d in range(-3, 4):
			var j := clampi(i + d, 0, k - 1)
			s += h[j]
			c += 1
		sm[i] = int(round(float(s) / c))
	h = sm
	var ha := fixed_a if fixed_a >= 0 else h[0]
	var hb := fixed_b if fixed_b >= 0 else h[k - 1]
	h[0] = ha
	h[k - 1] = hb
	# Les cellules déjà dans un tracé existant gardent leur hauteur.
	var locked := {}
	for i in k:
		var idx: int = cells[i].x + cells[i].y * field.n
		if road_cells.has(idx):
			h[i] = road_cells[idx]
			locked[i] = true
	locked[0] = true
	locked[k - 1] = true
	# Contraintes : |Δ| ≤ 1 entre cellules consécutives et ≤ 1 sur deux pas (pente 1:2).
	for iteration in 40:
		var changed := false
		for i in range(1, k):
			var lo := h[i - 1] - 1
			var hi := h[i - 1] + 1
			if i >= 2:
				lo = maxi(lo, h[i - 2] - 1)
				hi = mini(hi, h[i - 2] + 1)
			var v := clampi(h[i], lo, hi)
			if not locked.has(i) and v != h[i]:
				h[i] = v
				changed = true
		for i in range(k - 2, -1, -1):
			var lo := h[i + 1] - 1
			var hi := h[i + 1] + 1
			if i + 2 < k:
				lo = maxi(lo, h[i + 2] - 1)
				hi = mini(hi, h[i + 2] + 1)
			var v := clampi(h[i], lo, hi)
			if not locked.has(i) and v != h[i]:
				h[i] = v
				changed = true
		if not changed:
			break
	# Vérification : contraintes respectées, y compris sur les cellules verrouillées.
	for i in range(1, k):
		if absi(h[i] - h[i - 1]) > 1 or (i >= 2 and absi(h[i] - h[i - 2]) > 1):
			failures.append({"from": a, "to": b, "reason": "pente_trop_forte"})
			return {}
	# Protection du cœur : le tracé ne descend jamais sous cœur + MIN.
	for i in k:
		var idx: int = cells[i].x + cells[i].y * field.n
		if h[i] < field.core_top[idx] + TerrainField.MIN_SURFACE:
			failures.append({"from": a, "to": b, "reason": "tracé_dans_le_coeur"})
			return {}
	_carve(cells, h, width_m, material_key)
	var route := {"from": a, "to": b, "cells": cells, "heights": h, "width": width_m, "material": material_key}
	routes.append(route)
	return route

func _carve(cells: Array, h: PackedInt32Array, width_m: float, material_key: String) -> void:
	var pal := VoxelPalette.get_default()
	var mat := pal.id(material_key)
	var rad := maxf(width_m * 0.5 / V, 0.5)
	var best := {}      # colonne → [distance², hauteur, indice]
	var r := int(ceil(rad)) + 1
	for i in cells.size():
		var c: Vector2i = cells[i]
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var d2 := float(dx * dx + dz * dz)
				if d2 > rad * rad:
					continue
				var x := c.x + dx
				var z := c.y + dz
				if not field.has_ground(x, z):
					continue
				var j := x + z * field.n
				var tg := occ.tag[j]
				if tg == PlacementSpec.TAG_PLOT or tg == PlacementSpec.TAG_ITEM or tg == PlacementSpec.TAG_PORT or tg == PlacementSpec.TAG_GARDEN:
					continue
				if road_cells.has(j) and not (dx == 0 and dz == 0):
					continue
				if not best.has(j) or d2 < best[j][0]:
					best[j] = [d2, h[i], i]
	var band := {}
	for j in best:
		var hh: int = best[j][1]
		var x: int = j % field.n
		var z: int = j / field.n
		var steps := false
		var idx: int = best[j][2]
		if idx > 0 and h[idx] != h[idx - 1]:
			steps = true
		if idx + 1 < h.size() and h[idx] != h[idx + 1]:
			steps = true
		var zone := TerrainField.Zone.STAIR if steps else TerrainField.Zone.ROAD
		if field.zone[j] == TerrainField.Zone.PLAZA:
			continue
		field.set_top(x, z, hh, zone, mat)
		field.zone[j] = zone
		occ.tag[j] = PlacementSpec.TAG_ROAD
		placement.access_mask[j] = 1
		road_cells[j] = hh
		band[j] = hh
	TerrainEditor.apply_skirt(field, band, 8)
