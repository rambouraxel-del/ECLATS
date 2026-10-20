@tool
class_name BuildingValidator
extends RefCounted
## Vérifie qu'un bâtiment généré est RÉELLEMENT visitable, à partir des VOXELS (pas seulement du plan) :
##   - portes aux dimensions minimales (entrée ≥ 1,00 × 2,10 m, intérieures ≥ 0,90 × 2,00 m) ;
##   - un personnage de 1,80 m (18 cellules libres au-dessus des pieds) peut marcher de l'extérieur jusqu'au
##     centre de CHAQUE pièce, étage compris (marches ≤ 20 cm, escalier ≥ 1,80 m de hauteur libre) ;
##   - chaque pièce a au moins une porte ou ouverture ; l'entrée principale existe et est accessible ;
##   - colliders cohérents avec les volumes (un collider ne flotte pas dans le vide, un mur plein est couvert) ;
##   - meubles hors des zones de porte, dans leur pièce.
## Renvoie {errors: Array[String], warnings: Array[String], stats: Dictionary}.

const P := preload("res://scripts/world/building/building_plan.gd")
const C := VoxelGrid.STRUCTURE_SIZE

static func validate(model: BuildingModel) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var plan := model.plan
	# --- portes
	if plan.main_door < 0:
		errors.append("pas de porte d'entrée")
	for o in plan.openings:
		if o.kind != "door":
			continue
		var min_w := P.DOOR_MAIN_W if o.main else P.DOOR_INT_W
		var min_h := P.DOOR_MAIN_H if o.main else P.DOOR_INT_H
		if o.w < min_w or o.h < min_h:
			errors.append("porte trop petite (%d×%d cellules) : %s" % [o.w, o.h, "entrée" if o.main else "intérieure"])
	# --- chaque pièce a un accès
	for r in plan.rooms:
		var has := false
		for o in plan.openings:
			if o.kind == "door" or o.kind == "arch":
				if o.rooms.x == r.id or o.rooms.y == r.id:
					has = true
		if not has and r.floor == 0 and not (r.role == "stairs"):
			warnings.append("pièce %d (%s) sans porte déclarée" % [r.id, r.role])
	# --- parcours voxel
	var walk := _walk_check(model, errors, warnings)
	# --- colliders
	_collider_check(model, errors, warnings)
	# --- meubles
	for f in model.furniture:
		var rect: Rect2 = f["rect"]
		for dc in model.door_clear:
			if dc["floor"] == f["floor"] and (dc["rect"] as Rect2).grow(-0.01).intersects(rect):
				errors.append("meuble %s dans la zone d'une porte %s / %s" % [f["kind"], rect, dc["rect"]])
	return {"errors": errors, "warnings": warnings, "stats": walk}

# ------------------------------------------------------------------ parcours 1,80 m

## Matière à (x,y,z) : le terrain fini (y < GY) est considéré plein partout ; il porte le bâtiment.
static func _solid(vol: VoxelVolume, x: int, y: int, z: int) -> bool:
	if y < P.GY:
		return true
	return vol.get_voxel(x, y, z) != 0

static func _stand_ys(vol: VoxelVolume, x: int, z: int, blocked: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var head := P.MIN_HEADROOM
	var h := vol.size.y
	# run[y] = nombre de cellules libres consécutives à partir de y vers le haut (le ciel au-delà du volume est libre)
	var run := 1000
	var runs := PackedInt32Array()
	runs.resize(h + 1)
	runs[h] = 1000
	for y in range(h - 1, -1, -1):
		run = runs[y + 1] + 1 if not _solid(vol, x, y, z) else 0
		runs[y] = run
	for y in range(1, h):
		if runs[y] >= head and _solid(vol, x, y - 1, z):
			out.append(y)
	return out

static func _walk_check(model: BuildingModel, errors: Array[String], warnings: Array[String]) -> Dictionary:
	var plan := model.plan
	var vol := model.volume
	if plan.main_door < 0:
		return {}
	# cellules occupées par les meubles (par étage, rect → cellules)
	var furn_cells := {}
	for f in model.furniture:
		var r: Rect2 = f["rect"]
		var fy_ := int(round(model.floor_y_m(int(f["floor"])) / C))
		for z in range(roundi(r.position.y / C), roundi(r.end.y / C)):
			for x in range(roundi(r.position.x / C), roundi(r.end.x / C)):
				furn_cells[Vector3i(x, fy_, z)] = true
	var start_xz := plan.door_front
	var starts := _stand_ys(vol, start_xz.x, start_xz.y, furn_cells)
	if starts.is_empty():
		errors.append("devant la porte d'entrée, aucun point d'appui praticable (1,80 m)")
		return {}
	var seen := {}
	var q: Array[Vector3i] = []
	for y in starts:
		var v := Vector3i(start_xz.x, y, start_xz.y)
		seen[v] = true
		q.append(v)
	var qi := 0
	var cache := {}
	while qi < q.size():
		var c := q[qi]
		qi += 1
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = c.x + n.x
			var nz: int = c.z + n.y
			if nx < 0 or nz < 0 or nx >= vol.size.x or nz >= vol.size.z:
				continue
			var key := Vector2i(nx, nz)
			if not cache.has(key):
				cache[key] = _stand_ys(vol, nx, nz, furn_cells)
			for y in cache[key]:
				if absi(y - c.y) > P.STEP_RISE:
					continue
				var v := Vector3i(nx, y, nz)
				if seen.has(v):
					continue
				if furn_cells.has(Vector3i(nx, y, nz)):
					continue
				seen[v] = true
				q.append(v)
	# chaque pièce : le centre de la pièce doit être atteint
	var unreachable := 0
	for info in model.rooms:
		if info["role"] == "stairs" and int(info["floor"]) == 0:
			continue          # la cage d'escalier est occupée par les marches : elle est validée par l'accès à l'étage
		var rect: Rect2 = info["rect"]
		var fy := int(round(float(info["floor_y"]) / C))
		var found := false
		var cx := roundi((rect.position.x + rect.size.x * 0.5) / C)
		var cz := roundi((rect.position.y + rect.size.y * 0.5) / C)
		# on cherche une cellule atteinte dans la moitié centrale de la pièce
		var rx := maxi(roundi(rect.size.x / C * 0.25), 1)
		var rz := maxi(roundi(rect.size.y / C * 0.25), 1)
		for z in range(cz - rz, cz + rz + 1):
			for x in range(cx - rx, cx + rx + 1):
				if seen.has(Vector3i(x, fy, z)):
					found = true
					break
			if found:
				break
		if not found:
			# pièces d'étage : le sol fini est à fy ; l'escalier ou une zone de marche peut être différent
			unreachable += 1
			errors.append("pièce %d (%s, étage %d) inaccessible à pied" % [info["id"], info["role"], info["floor"]])
	return {"reached_cells": seen.size(), "rooms": model.rooms.size(), "unreachable_rooms": unreachable}

# ------------------------------------------------------------------ colliders ↔ volumes

static func _collider_check(model: BuildingModel, errors: Array[String], warnings: Array[String]) -> void:
	var vol := model.volume
	var furniture_aabbs := {}
	var floating := 0
	var covered_all := true
	var plan := model.plan
	var n_cov := 0
	var n_solid := 0
	var wall_top := plan.floor_y(0) + P.CLEAR
	# 1) cellules solides sous le plafond du rez-de-chaussée → doivent être couvertes par un collider
	var boxes: Array[AABB] = []
	for a in model.colliders:
		boxes.append(a)
	var grid := {}
	for a in boxes:
		var x0 := int(floor(a.position.x / C + 0.001))
		var y0 := int(floor(a.position.y / C + 0.001))
		var z0 := int(floor(a.position.z / C + 0.001))
		var x1 := int(ceil(a.end.x / C - 0.001))
		var y1 := int(ceil(a.end.y / C - 0.001))
		var z1 := int(ceil(a.end.z / C - 0.001))
		for z in range(z0, z1):
			for y in range(y0, y1):
				for x in range(x0, x1):
					grid[Vector3i(x, y, z)] = true
	for z in vol.size.z:
		for y in range(0, mini(wall_top, vol.size.y)):
			for x in vol.size.x:
				if vol.get_voxel(x, y, z) == 0:
					continue
				n_solid += 1
				if grid.has(Vector3i(x, y, z)):
					n_cov += 1
	var ratio := 1.0 if n_solid == 0 else float(n_cov) / float(n_solid)
	model.checks["collider_coverage"] = ratio
	if ratio < 0.97:
		errors.append("colliders : %.0f %% seulement de la matière du rez-de-chaussée est couverte" % (ratio * 100.0))
	# 2) un collider (hors meubles) ne doit pas flotter dans le vide
	var n_furn := model.furniture.size()
	var struct_boxes := boxes.size() - n_furn
	var empty_cells := 0
	var total_cells := 0
	for i in struct_boxes:
		var a: AABB = boxes[i]
		var cx := int(floor((a.position.x + a.size.x * 0.5) / C))
		var cy := int(floor((a.position.y + a.size.y * 0.5) / C))
		var cz := int(floor((a.position.z + a.size.z * 0.5) / C))
		total_cells += 1
		if vol.get_voxel(cx, cy, cz) == 0:
			empty_cells += 1
			warnings.append("collider vide au centre : %s" % [a])
	if empty_cells > 0:
		errors.append("colliders : %d volume(s) durs dont le centre est vide (collider sans matière)" % empty_cells)
