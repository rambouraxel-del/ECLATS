@tool
class_name SettlementGenerator
extends RefCounted
## Colonie d'une île : place centrale, parcelles, bâtiments, chemins, port, potagers, décor de place,
## sanctuaire de l'Ancre. Tout passe par le même système de placement que le reste du monde :
##   1. la place s'installe sur le meilleur espace plat (terrassement mesuré, coût minimal) ;
##   2. chaque bâtiment cherche son SITE (relief le moins coûteux, distance voulue de la place, façade
##      tournée vers la place), le terrain est aménagé (plateforme + talus ou soutènement), la parcelle est
##      réservée, puis le placement est validé ; un refus fait essayer un autre site ;
##   3. une route relie la porte à la place (pente maîtrisée, marches si nécessaire) ;
##   4. les objets de décor sont posés par le même système (zones et réservations).
## Rien ici ne dépend d'une graine ou d'une île particulière : le programme vient du profil.

const V := VoxelGrid.VOXEL_SIZE
const ORDER := ["community_hall", "shop", "workshop", "house_large", "warehouse", "house_small"]

var field: TerrainField
var occ: OccupancyMap
var placement: PlacementSystem
var paths: PathNetwork
var profile: IslandProfile
var seed := 0
var rng: RandomNumberGenerator
var pal: VoxelPalette

var plaza := {}                      # {center, radius, level, rect, owner}
var buildings: Array[Dictionary] = []   # {type, plan, res, door, door_col, xform, owner, plot_rect}
var props: Array[Dictionary] = []    # {id, xform, kind, item}
var gardens: Array[Dictionary] = []
var port := {}                       # {pad_rect, dir, rim, deck, ...} (PortBuilder)
var shrine := {}
var failures: Array[Dictionary] = [] # {what, reason}
var stats := {"sites_tried": 0, "site_reasons": {}}

func _init(p_field: TerrainField, p_occ: OccupancyMap, p_placement: PlacementSystem, p_paths: PathNetwork, p_profile: IslandProfile, p_seed: int) -> void:
	field = p_field
	occ = p_occ
	placement = p_placement
	paths = p_paths
	profile = p_profile
	seed = p_seed
	rng = WorldRng.stream(p_seed, "settlement")
	pal = VoxelPalette.get_default()

func fail(what: String, reason: String) -> void:
	failures.append({"what": what, "reason": reason})

# ------------------------------------------------------------------ orchestration

func generate() -> void:
	if not profile.has_settlement():
		return
	if not _plaza():
		fail("place", "aucun espace plat trouvé")
		return
	_port_site()
	_shrine()
	var program: Array = profile.g("settlement.buildings", [])
	var counts := {}
	for e in program:
		counts[e["type"]] = WorldRng.range_i(rng, e["count"])
	var idx := 0
	for type in ORDER:
		for i in int(counts.get(type, 0)):
			_building(type, idx)
			idx += 1
	_gardens()
	_plaza_props()
	_market_props()

# ------------------------------------------------------------------ place

func _plaza() -> bool:
	var pr := WorldRng.range_f(rng, profile.g("settlement.plaza_radius_m", [4.2, 5.2]))
	var max_cut: int = profile.g("settlement.max_cut_cells", 6)
	var max_fill: int = mini(int(profile.g("settlement.max_fill_cells", 14)), 8)
	var half := int(ceil(pr / V))
	var center0: Vector2 = field.landmarks.get("center", Vector2.ZERO)
	var cands: Array[Vector2] = []
	for k in mini(field.plateaus.size(), 4):
		cands.append(field.plateaus[k]["center"] if field.plateaus[k].has("center") else field.plateaus[k]["centroid"])
	for i in 28:
		var a := float(i) * 2.399963
		var r := 1.0 + float(i) * 0.45
		cands.append(center0 + Vector2(cos(a), sin(a)) * r)
	var best := {}
	var best_score := 1.0e18
	for c in cands:
		var col := field.col_of_m(c.x, c.y)
		var rect := Rect2i(col - Vector2i(half, half), Vector2i(half, half) * 2)
		var ev := TerrainEditor.evaluate_pad(field, occ, rect, 4, max_cut, max_fill, 2)
		if not ev["ok"]:
			continue
		var score: float = float(ev["cost"]) * 3.0 + c.distance_to(center0) * 0.25
		if score < best_score:
			best_score = score
			best = {"col": col, "rect": rect, "ev": ev, "c": c}
	if best.is_empty():
		return false
	var rect: Rect2i = best["rect"]
	var target: int = best["ev"]["target"]
	var cobble := pal.id("cobble")
	TerrainEditor.stamp_pad(field, rect, target, TerrainField.Zone.PLAZA, cobble, true)
	var center_col: Vector2i = best["col"]
	var center_m := field.center_m(center_col.x, center_col.y)
	# Disque pavé (médaillon central et couronne extérieure plus sombres) ; hors disque : herbe plane.
	var dark := pal.id("cobble_dark")
	var grass := pal.id("grass_trim")
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if not field.has_ground(cx, cz):
				continue
			var i := field.idx(cx, cz)
			var d := field.center_m(cx, cz).distance_to(center_m)
			if d > pr:
				field.zone[i] = TerrainField.Zone.NATURAL
				field.material[i] = grass
			else:
				field.material[i] = dark if (d < 1.3 or d > pr - 0.45 or (d > 2.6 and d < 3.0)) else cobble
	var owner := occ.new_owner()
	occ.reserve_disc(center_m, pr, PlacementSpec.TAG_PLAZA, owner)
	placement.mark_access(rect)
	plaza = {"center": center_m, "radius": pr, "level": target, "rect": rect, "owner": owner, "col": center_col}
	return true

# ------------------------------------------------------------------ port (emplacement)

func _port_site() -> void:
	if not bool(profile.g("settlement.port", false)):
		return
	port = PortBuilder.find_site(field, occ, plaza, rng, profile)
	if port.is_empty():
		fail("port", "aucun rivage utilisable")
		return
	PortBuilder.prepare_land(field, occ, placement, port)
	if _connect_pad(port["pad_rect"], "cobble").is_empty():
		fail("port", "route impossible")

# ------------------------------------------------------------------ bâtiments

static func _dir_of_yaw(k: int) -> Vector2:
	match k % 4:
		0: return Vector2(0, 1)
		1: return Vector2(1, 0)
		2: return Vector2(0, -1)
	return Vector2(-1, 0)

func _yaw_toward(p: Vector2, target: Vector2) -> int:
	var d := (target - p).normalized()
	var best := 0
	var bd := -2.0
	for k in 4:
		var s := d.dot(_dir_of_yaw(k))
		if s > bd:
			bd = s
			best = k
	return best

func _ring_for(type: String) -> Vector2:
	var pr: float = plaza["radius"]
	match type:
		"community_hall": return Vector2(pr + 3.0, pr + 8.0)
		"shop", "workshop": return Vector2(pr + 3.5, pr + 11.0)
		"house_large": return Vector2(pr + 5.0, pr + 15.0)
		"warehouse": return Vector2(pr + 4.0, pr + 18.0)
	return Vector2(pr + 4.5, pr + 17.0)

func _building(type: String, index: int) -> void:
	var plan := BuildingPlanner.plan(type, WorldRng.sub_seed(seed, "bld:%s:%d" % [type, index]))
	var spec := BuildingPlacement.spec_for(plan)
	var ring := _ring_for(type)
	var anchor: Vector2 = plaza["center"]
	if type == "warehouse" and not port.is_empty():
		anchor = (port["landing"] as Vector2).lerp(plaza["center"], 0.4)
		ring = Vector2(0.5, 9.0)
	var max_cut: int = profile.g("settlement.max_cut_cells", 6)
	var max_fill: int = mini(int(profile.g("settlement.max_fill_cells", 14)), 8)
	var tries: Array[Dictionary] = []
	var rings: Array = [[anchor, ring]]
	# repli : si le secteur voulu est plein, on cherche sur toute l'île autour de la place
	rings.append([plaza["center"], Vector2(float(plaza["radius"]) + 3.0, field.radius_m * 0.9)])
	for rr_def in rings:
		tries.append_array(_candidates(spec, plan, rr_def[0], rr_def[1], max_cut, max_fill))
		if tries.size() >= 3:
			break
	tries.sort_custom(func(a, b): return a["score"] < b["score"])
	var attempts := 0
	for t in tries:
		attempts += 1
		if attempts > 24:
			break
		if _commit_building(type, plan, spec, t):
			return
	fail("bâtiment:" + type, "aucun site valide (%d candidats, %d essais)" % [tries.size(), attempts])

func _candidates(spec: PlacementSpec, _plan: BuildingPlan, anchor: Vector2, ring: Vector2, max_cut: int, max_fill: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# balayage régulier (pas de 1 m, léger décalage) de la couronne, dans un ordre mélangé : toute la couronne
	# est examinée, pas seulement quelques tirages (les derniers bâtiments trouvent les espaces restants)
	var points: Array[Vector2] = []
	var span := ring.y
	var x := -span
	while x <= span:
		var z := -span
		while z <= span:
			var d := Vector2(x, z).length()
			if d >= ring.x and d <= ring.y:
				points.append(anchor + Vector2(x, z) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)))
			z += 1.0
		x += 1.0
	for i in range(points.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := points[i]
		points[i] = points[j]
		points[j] = t
	var evaluated := 0
	for p in points:
		if evaluated > 900 or out.size() >= 40:
			break
		var col := field.col_of_m(p.x, p.y)
		if not field.has_ground(col.x, col.y) or occ.tag_at(col.x, col.y) != PlacementSpec.TAG_FREE:
			continue
		evaluated += 1
		var yaw := _yaw_toward(p, plaza["center"])
		var half := spec.half_extents(yaw)
		var sp: Vector2 = Vector2(roundf((p.x - half.x) / spec.snap_m), roundf((p.y - half.y) / spec.snap_m)) * spec.snap_m + half
		var rect := placement.footprint_rect(sp, half)
		var yard := Rect2i(rect.position - Vector2i(2, 2), rect.size + Vector2i(4, 4))
		stats["sites_tried"] += 1
		# refus rapide (cinq colonnes) avant l'évaluation complète : hors de l'île, trop près du vide, déjà réservé
		var quick := _quick_reject(yard)
		if quick != "":
			stats["site_reasons"][quick] = int(stats["site_reasons"].get(quick, 0)) + 1
			continue
		var ev := TerrainEditor.evaluate_pad(field, occ, yard, 2, max_cut, max_fill, 2)
		if not ev["ok"]:
			var rs: String = ev["reason"]
			stats["site_reasons"][rs] = int(stats["site_reasons"].get(rs, 0)) + 1
			continue
		var rr := sp.distance_to(anchor)
		var dist_to_plaza := sp.distance_to(plaza["center"]) - float(plaza["radius"])
		var score: float = float(ev["cost"]) * 2.5 + absf(rr - (ring.x + ring.y) * 0.5) * 0.12 + rng.randf() * 0.5 + maxf(dist_to_plaza - 12.0, 0.0) * 0.3
		out.append({"score": score, "pos": sp, "yaw": yaw, "rect": rect, "yard": yard, "target": ev["target"]})
	return out

func _quick_reject(r: Rect2i) -> String:
	for c in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE, r.get_center()]:
		if not field.has_ground(c.x, c.y):
			return "hors_ile"
		var i := field.idx(c.x, c.y)
		if field.edge_dist[i] < 0.8:
			return "trop_pres_du_bord"
		if occ.tag[i] != PlacementSpec.TAG_FREE:
			return "reserve"
	return ""

func _commit_building(type: String, plan: BuildingPlan, spec: PlacementSpec, t: Dictionary) -> bool:
	var yard: Rect2i = t["yard"]
	var rect: Rect2i = t["rect"]
	# La route doit être possible AVANT d'aménager : écart de niveau compatible avec la distance (pente 1:2).
	var door_estimate: Vector2 = t["pos"] + _dir_of_yaw(t["yaw"]) * (spec.half_extents(t["yaw"]) + Vector2(0.8, 0.8))
	var dcol := field.col_of_m(door_estimate.x, door_estimate.y)
	if not field.has_ground(dcol.x, dcol.y):
		stats["site_reasons"]["porte_dans_le_vide"] = int(stats["site_reasons"].get("porte_dans_le_vide", 0)) + 1
		return false
	var plaza_level: int = plaza["level"]
	var dist_cols := int(Vector2(dcol - plaza["col"]).length())
	if absi(int(t["target"]) - plaza_level) * 2 + 4 > dist_cols:
		stats["site_reasons"]["route_trop_raide"] = int(stats["site_reasons"].get("route_trop_raide", 0)) + 1
		return false
	var owner := occ.new_owner()
	var yard_mat := pal.id("path_dirt")
	var snapshot := _snapshot(Rect2i(yard.position - Vector2i(16, 16), yard.size + Vector2i(32, 32)))
	TerrainEditor.stamp_pad(field, yard, t["target"], TerrainField.Zone.PLOT, yard_mat, true)
	occ.reserve(yard, PlacementSpec.TAG_ROAD, owner)           # cour praticable (les routes peuvent la traverser)
	occ.reserve(rect, PlacementSpec.TAG_PLOT, owner)           # emprise bâtie
	var res := placement.place(spec, t["pos"], t["yaw"], {"owner": owner})
	if not res.ok:
		_restore(snapshot)
		occ.release_owner(owner)
		stats["site_reasons"]["placement:" + ",".join(res.reasons)] = int(stats["site_reasons"].get("placement:" + ",".join(res.reasons), 0)) + 1
		return false
	var door := BuildingPlacement.door_world(plan, res)
	var dc := field.col_of_m(door.x, door.y)
	var route := _route_to_plaza(dc)
	if route.is_empty():
		# aménagement annulé : le terrain et la réservation reviennent à l'état précédent
		occ.remove_last_item()
		_restore(snapshot)
		occ.release_owner(owner)
		var why: String = paths.failures.back()["reason"] if not paths.failures.is_empty() else "?"
		stats["site_reasons"]["route:" + why] = int(stats["site_reasons"].get("route:" + why, 0)) + 1
		return false
	buildings.append({"type": type, "plan": plan, "res": res, "door": door, "door_col": dc, "xform": BuildingPlacement.node_transform(res),
		"owner": owner, "plot_rect": rect, "yard": yard, "route": route})
	return true

# ------------------------------------------------------------------ routes

func _route_to_plaza(dc: Vector2i) -> Dictionary:
	var pc: Vector2i = plaza["col"]
	var pr_cols := int(float(plaza["radius"]) / V)
	# point d'arrivée : cellule du bord de la place la plus proche de la porte
	var dir := Vector2(dc - pc)
	var end := pc
	if dir.length() > 0.5:
		end = pc + Vector2i((dir.normalized() * float(pr_cols - 2)).round())
	if not field.has_ground(end.x, end.y):
		end = pc
	var mat := "cobble" if rng.randf() < 0.35 else "path_dirt"
	var door_h := field.top_at(dc.x, dc.y)
	var r := paths.connect_points(dc, end, 1.4, mat, door_h, int(plaza["level"]))
	return r

# ------------------------------------------------------------------ sauvegarde de terrain (annulation)

func _snapshot(rect: Rect2i) -> Dictionary:
	var snap := {"rect": rect, "top": {}, "zone": {}, "mat": {}}
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if not field.in_bounds(cx, cz):
				continue
			var i := field.idx(cx, cz)
			snap["top"][i] = field.top[i]
			snap["zone"][i] = field.zone[i]
			snap["mat"][i] = field.material[i]
	snap["edits"] = field.edits.size()
	return snap

func _restore(snap: Dictionary) -> void:
	for i in snap["top"]:
		field.top[i] = snap["top"][i]
		field.zone[i] = snap["zone"][i]
		field.material[i] = snap["mat"][i]

# ------------------------------------------------------------------ sanctuaire de l'Ancre

func _shrine() -> void:
	# Sommet de l'île habitée : plateau le plus haut (hors place) ; sinon relief le plus haut.
	var best: Dictionary = {}
	var best_h := -(1 << 30)
	for pl in field.plateaus:
		var c: Vector2 = pl["centroid"]
		if c.distance_to(plaza["center"]) < float(plaza["radius"]) + 7.0:
			continue
		var h: int = pl["level"]
		if pl["inscribed_m"] >= 2.0 and h > best_h and occ.tag_at(field.col_of_m(c.x, c.y).x, field.col_of_m(c.x, c.y).y) == PlacementSpec.TAG_FREE:
			best_h = h
			best = pl
	var center: Vector2
	if best.is_empty():
		center = plaza["center"] + Vector2(0.0, -float(plaza["radius"]) - 9.0)
	else:
		center = best["centroid"]
	var half := int(ceil(4.0 / V))
	var col := field.col_of_m(center.x, center.y)
	var rect := Rect2i(col - Vector2i(half, half), Vector2i(half, half) * 2)
	var max_cut: int = profile.g("settlement.max_cut_cells", 6)
	var ev := TerrainEditor.evaluate_pad(field, occ, rect, 3, max_cut, 8, 2)
	if not ev["ok"]:
		# on cherche autour
		for i in 40:
			var a := float(i) * 2.399963
			var r := 3.0 + float(i) * 0.5
			var c2 := center + Vector2(cos(a), sin(a)) * r
			var col2 := field.col_of_m(c2.x, c2.y)
			var rect2 := Rect2i(col2 - Vector2i(half, half), Vector2i(half, half) * 2)
			var ev2 := TerrainEditor.evaluate_pad(field, occ, rect2, 3, max_cut, 8, 2)
			if ev2["ok"]:
				ev = ev2
				rect = rect2
				col = col2
				center = field.center_m(col2.x, col2.y)
				break
	if not ev["ok"]:
		fail("sanctuaire", "aucune plateforme trouvée")
		return
	var owner := occ.new_owner()
	TerrainEditor.stamp_pad(field, rect, ev["target"], TerrainField.Zone.PLOT, pal.id("cobble_dark"), true)
	occ.reserve(rect, PlacementSpec.TAG_PLOT, owner)
	shrine = {"center": center, "rect": rect, "level": ev["target"], "owner": owner, "col": col}
	if _connect_pad(rect, "path_dirt").is_empty():
		fail("sanctuaire", "route impossible")
	# L'Ancre, son socle et les ruines : posés par le placement universel, dans la parcelle réservée.
	_place_asset("teleport_anchor", center, 0, {"owner": owner, "free_tags": PackedInt32Array([PlacementSpec.TAG_PLOT]), "zones": [TerrainField.Zone.PLOT], "tags": [PlacementSpec.TAG_PLOT], "clearance": 0.0}, "shrine")
	_place_asset("anchor_pedestal", center, 0, {"owner": owner, "zones": [TerrainField.Zone.PLOT], "tags": [PlacementSpec.TAG_PLOT], "clearance": 0.0, "y_extra": 0.0}, "shrine")
	for k in 4:
		var ang := float(k) * PI * 0.5 + 0.8
		_place_asset_near("ruin_column", center + Vector2(cos(ang), sin(ang)) * 4.2, 1.2, {"owner": owner, "zones": [TerrainField.Zone.PLOT, TerrainField.Zone.NATURAL], "tags": [PlacementSpec.TAG_PLOT, PlacementSpec.TAG_FREE]}, "shrine")
	_place_asset_near("brazier", center + Vector2(-2.4, 2.4), 1.0, {"owner": owner, "zones": [TerrainField.Zone.PLOT], "tags": [PlacementSpec.TAG_PLOT]}, "shrine")
	_place_asset_near("brazier", center + Vector2(2.4, 2.4), 1.0, {"owner": owner, "zones": [TerrainField.Zone.PLOT], "tags": [PlacementSpec.TAG_PLOT]}, "shrine")

## Relie une plateforme réservée (sanctuaire, port) à la place : la route part de la première colonne
## libre au bord de la plateforme, du côté de la place.
func _connect_pad(rect: Rect2i, material: String) -> Dictionary:
	var pc: Vector2i = plaza["col"]
	var center := rect.get_center()
	var best := Vector2i(-1, -1)
	var best_d := 1.0e18
	for cz in range(rect.position.y - 1, rect.end.y + 1):
		for cx in range(rect.position.x - 1, rect.end.x + 1):
			if cx >= rect.position.x and cx < rect.end.x and cz >= rect.position.y and cz < rect.end.y:
				continue
			if not field.has_ground(cx, cz) or occ.tag_at(cx, cz) != PlacementSpec.TAG_FREE:
				continue
			var d := Vector2(cx - pc.x, cz - pc.y).length_squared()
			if d < best_d:
				best_d = d
				best = Vector2i(cx, cz)
	if best.x < 0:
		return {}
	return paths.connect_points(best, _nearest_plaza_col(best), 1.2, material)

func _nearest_plaza_col(c: Vector2i) -> Vector2i:
	var pc: Vector2i = plaza["col"]
	var pr_cols := int(float(plaza["radius"]) / V)
	var dir := Vector2(c - pc)
	if dir.length() < 0.5:
		return pc
	var e := pc + Vector2i((dir.normalized() * float(pr_cols - 2)).round())
	return e if field.has_ground(e.x, e.y) else pc

# ------------------------------------------------------------------ potagers

func _gardens() -> void:
	var n := WorldRng.range_i(rng, profile.g("settlement.gardens", [1, 2]))
	var houses: Array[Dictionary] = []
	for b in buildings:
		if b["type"] == "house_small" or b["type"] == "house_large":
			houses.append(b)
	if houses.is_empty():
		return
	var made := 0
	for h in houses:
		if made >= n:
			break
		if _garden_beside(h):
			made += 1

func _garden_beside(h: Dictionary) -> bool:
	var res: PlacementResult = h["res"]
	var plan: BuildingPlan = h["plan"]
	var half := res.spec.half_extents(res.yaw)
	var gw := 4.4
	var gd := 3.2
	var max_cut: int = profile.g("settlement.max_cut_cells", 6)
	for side in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1)]:
		# les côtés sont exprimés dans le repère du bâtiment (arrière = -z local)
		var d3 := res.basis() * Vector3(side.x, 0, side.y)
		var dir := Vector2(d3.x, d3.z)
		var reach := (absf(dir.x) * half.x + absf(dir.y) * half.y) + (absf(dir.x) * gw + absf(dir.y) * gd) * 0.5 + 1.2
		var center := Vector2(res.pos.x, res.pos.z) + dir * reach
		var hw := (gw if absf(dir.x) < 0.5 else gd) * 0.5
		var hd := (gd if absf(dir.x) < 0.5 else gw) * 0.5
		var rect := placement.footprint_rect(center, Vector2(hw, hd))
		var ev := TerrainEditor.evaluate_pad(field, occ, rect, 2, max_cut, 4, 2)
		if not ev["ok"]:
			continue
		var owner := occ.new_owner()
		TerrainEditor.stamp_pad(field, rect, ev["target"], TerrainField.Zone.GARDEN, pal.id("dirt_fertile"), true)
		occ.reserve(rect, PlacementSpec.TAG_GARDEN, owner)
		gardens.append({"rect": rect, "center": center, "owner": owner, "level": ev["target"], "house": h["plan"].seed})
		# lits de légumes (2 × 1 m) en rangées, posés par le placement universel
		var yaw := 0 if hw >= hd else 1
		var nrow := int(floor((hd * 2.0 if yaw == 0 else hw * 2.0) / 1.5))
		for r in nrow:
			var pos := center
			if yaw == 0:
				pos.y = center.y - hd + 0.75 + float(r) * 1.5
			else:
				pos.x = center.x - hw + 0.75 + float(r) * 1.5
			_place_asset("vegetable_bed", pos, yaw, {"owner": owner, "zones": [TerrainField.Zone.GARDEN], "tags": [PlacementSpec.TAG_GARDEN], "clearance": 0.0}, "garden")
		return true
	return false

# ------------------------------------------------------------------ décor de la place et du marché

func _plaza_props() -> void:
	var c: Vector2 = plaza["center"]
	var pr: float = plaza["radius"]
	var own: int = plaza["owner"]
	var opt := {"owner": own, "zones": [TerrainField.Zone.PLAZA], "tags": [PlacementSpec.TAG_PLAZA], "clearance": 0.3}
	_place_asset("pedestal_fountain", c, 0, opt, "plaza")
	for k in 4:
		var a := float(k) * PI * 0.5 + PI * 0.25
		_place_asset_near("crystal_lamp", c + Vector2(cos(a), sin(a)) * (pr - 0.9), 0.8, opt, "plaza")
	for k in 3:
		var a := float(k) * TAU / 3.0 + rng.randf() * 0.5
		_place_asset_near("decorative_bench", c + Vector2(cos(a), sin(a)) * (pr - 1.4), 1.0, opt, "plaza")

func _market_props() -> void:
	var c: Vector2 = plaza["center"]
	var pr: float = plaza["radius"]
	var own: int = plaza["owner"]
	var opt := {"owner": own, "zones": [TerrainField.Zone.PLAZA], "tags": [PlacementSpec.TAG_PLAZA], "clearance": 0.35}
	var n := WorldRng.range_i(rng, profile.g("settlement.market_props", [3, 5]))
	var kinds := ["market_stall", "canopy_kiosk", "barrel_set", "crate_stack", "utility_cart", "notice_board", "signpost", "water_well"]
	var side := rng.randf() * TAU
	for i in n:
		var id: String = kinds[i % kinds.size()]
		var a := side + float(i) * 0.7 - 0.7
		_place_asset_near(id, c + Vector2(cos(a), sin(a)) * (pr - 1.9), 2.2, opt, "market")
	# quelques tonneaux et caisses devant le port
	if not port.is_empty():
		var l: Vector2 = port["landing"]
		var own_p: int = port.get("owner", 0)
		var o2 := {"owner": own_p, "zones": [TerrainField.Zone.PORT], "tags": [PlacementSpec.TAG_PORT], "clearance": 0.3}
		for id in ["crate_stack", "barrel_set", "crate_stack", "utility_cart"]:
			_place_asset_near(id, l, 3.0, o2, "port")

# ------------------------------------------------------------------ pose d'assets cuits

func _spec_for_asset(id: String, opt: Dictionary) -> PlacementSpec:
	var info := AssetLibrary.info(id)
	var s := PlacementSpec.from_asset_info(info, "prop")
	if id.begins_with("tree_"):
		s.kind = "tree"
	s.snap_m = 0.2
	s.clearance_m = float(opt.get("clearance", 0.25))
	s.cliff_margin_m = 0.4
	s.support_fraction = 0.8
	s.gap_tolerance_m = 0.2
	var zones: Array = opt.get("zones", [])
	s.allowed_zones = PackedInt32Array(zones)
	var tags: Array = opt.get("tags", [])
	s.allowed_tags = PackedInt32Array(tags)
	if id == "teleport_anchor" or id == "anchor_pedestal":
		s.support_fraction = 0.6
		s.cliff_margin_m = 0.0
	if id == "ruin_column":
		s.embed_max_m = 0.2
	return s

func _place_asset(id: String, center: Vector2, yaw: int, opt: Dictionary, kind: String) -> PlacementResult:
	var spec := _spec_for_asset(id, opt)
	var o := {"owner": opt.get("owner", 0), "skip_access": true, "reserve_tag": opt.get("tags", [PlacementSpec.TAG_ITEM])[0] if opt.has("tags") else PlacementSpec.TAG_ITEM}
	var res := placement.place(spec, center, yaw, o)
	if res.ok:
		_record_prop(id, res, kind, opt)
	return res

func _place_asset_near(id: String, center: Vector2, radius: float, opt: Dictionary, kind: String) -> PlacementResult:
	var spec := _spec_for_asset(id, opt)
	var o := {"owner": opt.get("owner", 0), "skip_access": true, "samples": 40, "free_tags": opt.get("free_tags", PackedInt32Array()),
		"reserve_tag": opt.get("tags", [PlacementSpec.TAG_ITEM])[0] if opt.has("tags") else PlacementSpec.TAG_ITEM}
	var res := placement.find_and_place(spec, center, radius, rng, o)
	if res.ok:
		_record_prop(id, res, kind, opt)
	else:
		fail("objet:" + id, ",".join(res.reasons))
	return res

func _record_prop(id: String, res: PlacementResult, kind: String, opt: Dictionary) -> void:
	var info := AssetLibrary.info(id)
	var xf := res.asset_transform()
	xf.origin.y += float(opt.get("y_extra", 0.0)) - float(info.get("ground_y", 0.0))
	props.append({"id": id, "xform": xf, "kind": kind, "item": res.item_index})
