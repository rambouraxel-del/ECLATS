@tool
class_name PlacementSystem
extends RefCounted
## Système UNIVERSEL de placement : arbres, rochers, bâtiments, objets, meubles, infrastructures,
## et (plus tard) constructions du joueur passent par les mêmes vérifications.
##
## Pour chaque tentative il contrôle :
##   emprise dans l'île · distance au vide · zone et matière · espace réservé · pente et enfoncement ·
##   support réel sous l'objet · intersection avec le cœur fixe · collisions (volumes durs, clearance) ·
##   volumes mous (couronnes) contre constructions · accessibilité.
## Les exceptions volontaires sont DÉCLARÉES dans le spec (overhang_void, in_building, on_road…).
## Un placement invalide n'est jamais accepté : il est refusé avec ses raisons.

const V := VoxelGrid.VOXEL_SIZE

var field: TerrainField
var occ: OccupancyMap
var access_mask := PackedByteArray()      # colonnes de circulation (chemins, place) : 1 = marchable
var stats := {"attempts": 0, "accepted": 0, "rejected": {}, "by_kind": {}}
var _material_ids := {}

func _init(p_field: TerrainField, p_occ: OccupancyMap = null) -> void:
	field = p_field
	occ = p_occ if p_occ != null else OccupancyMap.new(p_field)
	access_mask.resize(field.n * field.n)
	var pal := VoxelPalette.get_default()
	for i in pal.count():
		_material_ids[pal.keys[i]] = i

func mark_access(rect: Rect2i) -> void:
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if field.has_ground(cx, cz):
				access_mask[cx + cz * field.n] = 1

# ------------------------------------------------------------------ évaluation (sans effet)

func _snap(spec: PlacementSpec, pos: Vector2, half: Vector2) -> Vector2:
	if spec.snap_m <= 0.0:
		return pos
	var lo := (pos - half) / spec.snap_m
	return Vector2(roundf(lo.x), roundf(lo.y)) * spec.snap_m + half

func footprint_rect(p: Vector2, half: Vector2) -> Rect2i:
	var x0 := floori((p.x - half.x) / V + 1e-4)
	var x1 := ceili((p.x + half.x) / V - 1e-4)
	var z0 := floori((p.y - half.y) / V + 1e-4)
	var z1 := ceili((p.y + half.y) / V - 1e-4)
	return Rect2i(x0 - field.origin.x, z0 - field.origin.y, maxi(x1 - x0, 1), maxi(z1 - z0, 1))

## opts : base_top (cellule imposée : intérieurs, étages), ignore_terrain (meubles), owner (propriétaire
## de la parcelle réservée), skip_access, free_tags (étiquettes supplémentaires admises).
func evaluate(spec: PlacementSpec, pos: Vector2, yaw: int, opts := {}) -> PlacementResult:
	var res := PlacementResult.new()
	res.spec = spec
	res.yaw = yaw
	var half := spec.half_extents(yaw)
	var p := _snap(spec, pos, half)
	var rect := footprint_rect(p, half)
	res.rect = rect
	var owner_id: int = opts.get("owner", 0)
	var ignore_terrain: bool = opts.get("ignore_terrain", false)
	var total := rect.size.x * rect.size.y
	var hmin := 1 << 30
	var hmax := -(1 << 30)
	var ground_cols := 0
	var void_cols := 0
	var min_core_margin := 1 << 30
	if not ignore_terrain:
		for cz in range(rect.position.y, rect.end.y):
			for cx in range(rect.position.x, rect.end.x):
				if not field.has_ground(cx, cz):
					void_cols += 1
					continue
				ground_cols += 1
				var i := field.idx(cx, cz)
				var t := field.top[i]
				hmin = mini(hmin, t)
				hmax = maxi(hmax, t)
				if field.edge_dist[i] < spec.cliff_margin_m and not spec.allows_exception("overhang_void"):
					res.fail(PlacementSpec.R_CLIFF)
				var z := field.zone[i]
				if spec.allowed_zones.is_empty():
					if z != TerrainField.Zone.NATURAL and z != TerrainField.Zone.GARDEN:
						res.fail(PlacementSpec.R_ZONE)
				elif not spec.allowed_zones.has(z):
					res.fail(PlacementSpec.R_ZONE)
				if not spec.forbidden_materials.is_empty():
					for key in spec.forbidden_materials:
						if int(field.material[i]) == int(_material_ids.get(key, -1)):
							res.fail(PlacementSpec.R_MATERIAL)
				var tg := occ.tag[i]
				if tg != PlacementSpec.TAG_FREE and not spec.allowed_tags.has(tg) and not opts.get("free_tags", PackedInt32Array()).has(tg):
					if not (owner_id != 0 and occ.owner[i] == owner_id):
						res.fail(PlacementSpec.R_RESERVED)
		if void_cols > 0 and not spec.allows_exception("overhang_void"):
			return res.fail(PlacementSpec.R_OUT)
		if ground_cols == 0:
			return res.fail(PlacementSpec.R_OUT)
		if spec.allows_exception("overhang_void") and float(void_cols) / float(total) > spec.overhang_fraction:
			res.fail(PlacementSpec.R_OUT)
		if not res.reasons.is_empty():
			return res
		# --- hauteur de base, pente, enfoncement ---
		var gap := int(round(spec.gap_tolerance_m / V))
		var embed_max := int(floor(spec.embed_max_m / V + 1e-4))
		var base := hmax
		var embed := 0
		if opts.has("base_top"):
			base = int(opts["base_top"])
			if base - hmin > gap:
				res.fail(PlacementSpec.R_SUPPORT)
			if hmax - base > embed_max:
				res.fail(PlacementSpec.R_SLOPE)
			embed = maxi(hmax - base, 0)
		elif spec.support == "none":
			base = hmax
		else:
			var e := hmax - hmin
			if e <= gap:
				base = hmax
			else:
				var s := e - gap
				if s > embed_max:
					res.range_cells = e
					return res.fail(PlacementSpec.R_SLOPE)
				base = hmax - s
				embed = s
		res.range_cells = hmax - hmin
		res.base_top = base
		res.embed_cells = embed
		# --- support réel et cœur fixe ---
		var supported := 0
		for cz in range(rect.position.y, rect.end.y):
			for cx in range(rect.position.x, rect.end.x):
				if not field.has_ground(cx, cz):
					continue
				var i := field.idx(cx, cz)
				if field.top[i] >= base - gap:
					supported += 1
				if base < field.core_top[i]:
					res.fail(PlacementSpec.R_CORE)
				min_core_margin = mini(min_core_margin, base - field.core_top[i])
		res.support = float(supported) / float(total)
		if spec.support != "none" and res.support < spec.support_fraction:
			res.fail(PlacementSpec.R_SUPPORT)
		if embed > 0 and min_core_margin < TerrainField.MIN_SURFACE:
			res.fail(PlacementSpec.R_DEPTH)
	else:
		res.base_top = int(opts.get("base_top", 0))
		res.support = 1.0
	var base_y := float(res.base_top + 1) * V
	res.pos = Vector3(p.x, base_y, p.y)
	if not res.reasons.is_empty():
		return res
	# --- collisions et volumes mous ---
	var hard_w := _world_boxes(spec.hard, res)
	var soft_w := _world_boxes(spec.soft, res)
	for k in occ.candidates(_union(hard_w + soft_w), maxf(spec.clearance_m, 1.0)):
		var other: Dictionary = occ.items[k]
		if opts.get("ignore_item", -1) == k:
			continue
		var oclear: float = other.get("clearance", 0.0)
		for a: AABB in hard_w:
			for b: AABB in other["hard"]:
				if _clash(a, spec.clearance_m, b, oclear):
					if spec.allows_exception("in_building") and other["kind"] == "building" and b.encloses(a):
						continue
					res.fail(PlacementSpec.R_COLLISION)
		for a: AABB in soft_w:
			if spec.soft_blocks_kinds.has(other["kind"]):
				for b: AABB in other["hard"]:
					if a.intersects(b):
						res.fail(PlacementSpec.R_SOFT)
			for b: AABB in other["soft"]:
				if _overlap_fraction(a, b) > spec.soft_overlap_max:
					res.fail(PlacementSpec.R_SOFT)
		var o_blocks: PackedStringArray = other.get("soft_blocks", PackedStringArray())
		if o_blocks.has(spec.kind):
			for b: AABB in other["soft"]:
				for a: AABB in hard_w:
					if a.intersects(b):
						res.fail(PlacementSpec.R_SOFT)
	# --- accessibilité ---
	if spec.needs_access and not opts.get("skip_access", false) and not ignore_terrain:
		var cell := _access_near(rect, spec.access_radius_m, res.base_top)
		if cell.x < 0:
			res.fail(PlacementSpec.R_ACCESS)
		res.access_cell = cell
	res.ok = res.reasons.is_empty()
	return res

func _world_boxes(local: Array[AABB], res: PlacementResult) -> Array[AABB]:
	var out: Array[AABB] = []
	for b in local:
		var r := PlacementSpec.rotate_box(b, res.yaw)
		out.append(AABB(r.position + res.pos, r.size))
	return out

static func _union(boxes: Array) -> AABB:
	if boxes.is_empty():
		return AABB()
	var u: AABB = boxes[0]
	for b: AABB in boxes:
		u = u.merge(b)
	return u

static func _clash(a: AABB, ca: float, b: AABB, cb: float) -> bool:
	var ga := a.grow(ca) if ca > 0.0 else a
	var gb := b.grow(cb) if cb > 0.0 else b
	# la marge ne s'applique pas en hauteur : deux objets l'un sur l'autre ne se « poussent » pas
	return ga.intersects(b) or gb.intersects(a)

static func _overlap_fraction(a: AABB, b: AABB) -> float:
	var i := a.intersection(b)
	if i.size.x <= 0.0 or i.size.y <= 0.0 or i.size.z <= 0.0:
		return 0.0
	var vi := i.size.x * i.size.y * i.size.z
	var vm := minf(a.size.x * a.size.y * a.size.z, b.size.x * b.size.y * b.size.z)
	return vi / maxf(vm, 0.0001)

## Cherche une colonne de circulation à moins de `radius` m de l'emprise, de hauteur compatible
## (marche ≤ 1 cellule de 20 cm avec la base de l'objet, ou même niveau).
func _access_near(rect: Rect2i, radius: float, base_top: int) -> Vector2i:
	var r := int(ceil(radius / V))
	var best := Vector2i(-1, -1)
	var best_d := 1.0e9
	var c := rect.get_center()
	for cz in range(rect.position.y - r, rect.end.y + r):
		for cx in range(rect.position.x - r, rect.end.x + r):
			if not field.in_bounds(cx, cz) or access_mask[cx + cz * field.n] == 0:
				continue
			var dx := maxi(maxi(rect.position.x - cx, cx - (rect.end.x - 1)), 0)
			var dz := maxi(maxi(rect.position.y - cz, cz - (rect.end.y - 1)), 0)
			var d := float(dx * dx + dz * dz)
			if d > float(r * r):
				continue
			if absi(field.top_at(cx, cz) - base_top) > 2 and absi(field.top_at(cx, cz) - base_top) < 1000:
				continue
			if d < best_d:
				best_d = d
				best = Vector2i(cx, cz)
	return best

# ------------------------------------------------------------------ pose

func _count(res: PlacementResult) -> void:
	stats["attempts"] += 1
	if res.ok:
		stats["accepted"] += 1
		var k: String = res.spec.kind
		stats["by_kind"][k] = int(stats["by_kind"].get(k, 0)) + 1
	else:
		for r in res.reasons:
			stats["rejected"][r] = int(stats["rejected"].get(r, 0)) + 1

## Pose l'élément si (et seulement si) le placement est valide. Réserve son emprise.
func place(spec: PlacementSpec, pos: Vector2, yaw: int, opts := {}) -> PlacementResult:
	var res := evaluate(spec, pos, yaw, opts)
	_count(res)
	if res.ok:
		commit(res, opts)
	return res

func commit(res: PlacementResult, opts := {}) -> void:
	var spec := res.spec
	var item := {
		"id": spec.id, "kind": spec.kind, "spec": spec, "pos": res.pos, "yaw": res.yaw, "rect": res.rect,
		"hard": _world_boxes(spec.hard, res), "soft": _world_boxes(spec.soft, res),
		"clearance": spec.clearance_m, "base_top": res.base_top, "owner": opts.get("owner", 0),
		"soft_blocks": spec.soft_blocks_kinds if not spec.soft.is_empty() else PackedStringArray(),
		"support": res.support, "embed_cells": res.embed_cells, "exceptions": spec.exceptions,
	}
	res.item_index = occ.add_item(item)
	if spec.kind != "plant" and not opts.get("ignore_terrain", false):
		var tag_to_use: int = opts.get("reserve_tag", PlacementSpec.TAG_ITEM)
		var oid: int = opts.get("owner", 0)
		occ.reserve(res.rect, tag_to_use, oid if oid != 0 else occ.new_owner(), true)

## Cherche un emplacement valide autour de `center` (spirale d'angle d'or) et le pose. Les tentatives
## refusées sont comptées. opts : samples, min_radius, best_of (nombre de candidats valides évalués),
## score (Callable(result) → coût, plus petit = meilleur), owner, skip_access…
func find_and_place(spec: PlacementSpec, center: Vector2, radius: float, rng: RandomNumberGenerator, opts := {}) -> PlacementResult:
	var samples: int = opts.get("samples", 60)
	var best_of: int = opts.get("best_of", 1)
	var min_r: float = opts.get("min_radius", 0.0)
	var score: Callable = opts.get("score", Callable())
	var valid: Array[PlacementResult] = []
	var last: PlacementResult
	for i in samples:
		var rr := lerpf(min_r, radius, sqrt((float(i) + 0.5) / samples))
		var a := float(i) * 2.399963 + rng.randf() * 0.4
		var p := center + Vector2(cos(a), sin(a)) * rr
		var yaws := spec.yaw_options
		var yaw: int = yaws[rng.randi() % yaws.size()]
		if opts.has("yaw"):
			yaw = opts["yaw"]
		var res := evaluate(spec, p, yaw, opts)
		last = res
		if res.ok:
			valid.append(res)
			if valid.size() >= best_of:
				break
		else:
			for r in res.reasons:
				stats["rejected"][r] = int(stats["rejected"].get(r, 0)) + 1
	if valid.is_empty():
		stats["attempts"] += 1
		return last if last != null else PlacementResult.new().fail(PlacementSpec.R_OUT)
	var best := valid[0]
	if score.is_valid():
		var best_cost := 1.0e18
		for v in valid:
			var c: float = score.call(v)
			if c < best_cost:
				best_cost = c
				best = v
	_count(best)
	commit(best, opts)
	return best
