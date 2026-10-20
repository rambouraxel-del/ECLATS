@tool
class_name TerrainEditor
extends RefCounted
## Aménagements du relief : plateformes (terrassement superficiel, remblai), raccords de pente,
## soutènements. TOUTES les modifications passent par TerrainField.set_top, qui refuse de descendre
## dans le cœur fixe : le terrassement ne peut jamais creuser plus que la couche superficielle.

const V := VoxelGrid.VOXEL_SIZE
const SKIRT_SLOPE := 2          # colonnes par cellule de dénivelé : pente 1:2 (≈ 27°)
const SKIRT_MAX_DELTA := 3      # au-delà, soutènement vertical plutôt que talus

## Évalue l'implantation d'une plateforme (rect en colonnes) : cibles, coûts, faisabilité.
static func evaluate_pad(field: TerrainField, occ: OccupancyMap, rect: Rect2i, margin_cols: int,
		max_cut: int, max_fill: int, step := 3, allow_tags := PackedInt32Array(), edge_min := 0.8) -> Dictionary:
	var out := {"ok": false, "reason": "", "target": 0, "cost": 1.0e9, "cut": 0, "fill": 0}
	var tops := []
	var lo_t := -(1 << 30)
	var hi_t := 1 << 30
	var cut_cells := 0
	var fill_cells := 0
	max_cut = mini(max_cut, TerrainField.SURFACE_DEPTH - TerrainField.MIN_SURFACE)
	var grown := Rect2i(rect.position - Vector2i(margin_cols, margin_cols), rect.size + Vector2i(margin_cols, margin_cols) * 2)
	var near := Rect2i(rect.position - Vector2i.ONE, rect.size + Vector2i(2, 2))
	# l'emprise (et sa frange d'une colonne) doit être sur l'île et à `edge_min` m du vide ;
	# la marge ne sert qu'à garder de l'espace libre vis-à-vis des autres réservations
	for cz in range(near.position.y, near.end.y, step):
		for cx in range(near.position.x, near.end.x, step):
			if not field.has_ground(cx, cz):
				out["reason"] = "hors_ile"
				return out
			if field.edge_dist[field.idx(cx, cz)] < edge_min:
				out["reason"] = "trop_pres_du_bord"
				return out
	for cz in range(grown.position.y, grown.end.y, step):
		for cx in range(grown.position.x, grown.end.x, step):
			if not field.has_ground(cx, cz):
				continue
			var i := field.idx(cx, cz)
			if occ.tag[i] != PlacementSpec.TAG_FREE and not allow_tags.has(occ.tag[i]):
				out["reason"] = "reserve"
				return out
	for cz in range(rect.position.y, rect.end.y, step):
		for cx in range(rect.position.x, rect.end.x, step):
			var i := field.idx(cx, cz)
			var t := field.top[i]
			tops.append(t)
			# cible admissible : on ne peut pas descendre sous cœur+MIN, ni creuser/remblayer au-delà des limites
			lo_t = maxi(lo_t, maxi(t - max_cut, field.core_top[i] + TerrainField.MIN_SURFACE))
			hi_t = mini(hi_t, t + max_fill)
	if lo_t > hi_t:
		out["reason"] = "relief_trop_accidente"
		return out
	tops.sort()
	var median: int = tops[tops.size() / 2]
	var target := clampi(median, lo_t, hi_t)
	var cost := 0.0
	for cz in range(rect.position.y, rect.end.y, step):
		for cx in range(rect.position.x, rect.end.x, step):
			var t := field.top[field.idx(cx, cz)]
			if t > target:
				cut_cells += t - target
				cost += pow(float(t - target), 1.3)
			else:
				fill_cells += target - t
				cost += pow(float(target - t), 1.1) * 1.4
	out["ok"] = true
	out["target"] = target
	out["cost"] = cost / float(tops.size())
	out["cut"] = cut_cells
	out["fill"] = fill_cells
	out["median"] = median
	return out

## Plateforme à hauteur constante : terrassement dans le rect, talus 1:2 à l'extérieur (si l'écart est
## modeste) ou soutènement vertical (zone RETAIN sur la crête) sinon.
static func stamp_pad(field: TerrainField, rect: Rect2i, target: int, zone: int, material: int, skirt := true) -> Dictionary:
	var changed := 0
	var retained := 0
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if field.set_top(cx, cz, target, zone, material):
				changed += 1
			elif field.has_ground(cx, cz):
				var i := field.idx(cx, cz)
				field.zone[i] = zone
				field.material[i] = material
	if not skirt:
		return {"changed": changed, "retained": 0}
	var band := {}
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if field.has_ground(cx, cz):
				band[field.idx(cx, cz)] = target
	var sk := apply_skirt(field, band, 14)
	return {"changed": changed + sk["changed"], "retained": sk["retained"]}

## Raccorde le relief naturel à des colonnes aménagées (« band » : index de colonne → hauteur) :
## talus de pente 1:2 si l'écart est modeste, sinon soutènement vertical (zone RETAIN sur la crête).
## Ne touche jamais une colonne déjà aménagée ; passe toujours par set_top (cœur protégé).
static func apply_skirt(field: TerrainField, band: Dictionary, reach := 14) -> Dictionary:
	var dist := {}
	var src := {}
	var queue: Array = []
	for i in band:
		dist[i] = 0
		src[i] = band[i]
		queue.append(i)
	var head := 0
	var changed := 0
	var retained := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var d: int = dist[i]
		if d >= reach:
			continue
		var cx := i % field.n
		var cz := i / field.n
		for o in WorldNav.NEIGH:
			var x: int = cx + o.x
			var z: int = cz + o.y
			if not field.has_ground(x, z):
				continue
			var j := x + z * field.n
			if dist.has(j):
				continue
			dist[j] = d + 1
			src[j] = src[i]
			queue.append(j)
			if field.zone[j] != TerrainField.Zone.NATURAL:
				continue
			var h: int = src[j]
			var nat := field.top[j]
			var delta := nat - h
			if absi(delta) > SKIRT_MAX_DELTA and d + 1 <= 1:
				if delta > 0:
					field.zone[j] = TerrainField.Zone.RETAIN
					retained += 1
				continue
			var allowed := (d + 1) / SKIRT_SLOPE
			var wanted := clampi(nat, h - allowed, h + allowed)
			if wanted != nat and field.set_top(x, z, wanted):
				changed += 1
	return {"changed": changed, "retained": retained}

## Lisse les marches abruptes restantes autour d'une zone (garantit |Δ| ≤ max_step entre voisines
## NATURELLES voisines d'un aménagement), sans jamais toucher les zones aménagées.
static func relax_around(field: TerrainField, rect: Rect2i, reach: int, max_step: int) -> int:
	var changed := 0
	var grown := Rect2i(rect.position - Vector2i(reach, reach), rect.size + Vector2i(reach, reach) * 2)
	for iteration in 3:
		for cz in range(grown.position.y, grown.end.y):
			for cx in range(grown.position.x, grown.end.x):
				if not field.has_ground(cx, cz):
					continue
				var i := field.idx(cx, cz)
				if field.zone[i] != TerrainField.Zone.NATURAL:
					continue
				var t := field.top[i]
				var lo := -(1 << 30)
				var hi := 1 << 30
				for o in WorldNav.NEIGH:
					var j := field.idx(cx + o.x, cz + o.y) if field.in_bounds(cx + o.x, cz + o.y) else -1
					if j < 0 or field.top[j] == TerrainField.NO_GROUND:
						continue
					if field.zone[j] == TerrainField.Zone.NATURAL:
						continue
					lo = maxi(lo, field.top[j] - max_step)
					hi = mini(hi, field.top[j] + max_step)
				if lo <= hi and (t < lo or t > hi):
					if field.set_top(cx, cz, clampi(t, lo, hi)):
						changed += 1
	return changed
