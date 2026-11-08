@tool
class_name AuthoredIslandBuilder
extends RefCounted
## Construction d'une île FIXE (Lot 5) à partir de sa carte (IslandMap). Le Lot 4 sert de bibliothèque :
## TerrainField / TerrainEditor (plateformes, talus), PathNetwork (taille des chemins, marches), PlacementSystem
## (emprises, hauteurs, réservations), BuildingPlanner/Builder (maisons visitables), PortBuilder (quai, navire),
## TreeGenerator, RockGenerator, NatureGenerator (plantes), TerrainVoxelizer (voxels par tuiles).
## Rien n'est tiré au hasard : chaque élément est posé là où la carte le dit (les seules graines servent au
## détail des modèles et au semis des herbes, toujours identiques). Les écarts (objet décalé, posé de force)
## sont journalisés dans w.events.

const V := VoxelGrid.VOXEL_SIZE
const BUILD_VERSION := 5            # à incrémenter quand le constructeur change (invalide le cache)
const TILE := 160                  # colonnes par tuile de terrain (32 m)
const CHUNK := 80                  # colonnes par maillage (16 m)

## Clé de cache : carte + palette + version du constructeur. Modifier l'une d'elles reconstruit l'île.
static func signature(map: Dictionary) -> String:
	var pal_hash := WorldRng.fnv(FileAccess.get_file_as_string(VoxelPalette.PALETTE_PATH))
	return "%s_%s_%08x_v%d" % [String(map.get("id", "ile")), String(map.get("_hash", "0")), pal_hash, BUILD_VERSION]

static func build(map: Dictionary, opts := {}) -> WorldData:
	var w := WorldData.new()
	var seed := int(map.get("seed", 1))
	w.seed = seed
	var clock := [Time.get_ticks_msec()]
	var lap := func(label: String) -> void:
		var now := Time.get_ticks_msec()
		w.timings[label] = now - int(clock[0])
		clock[0] = now
	VoxelMesher.palette_warmup()
	w.profile = IslandProfile.load_profile("settled")
	w.field = AuthoredTerrain.build_field(map)
	lap.call("relief")
	w.occ = OccupancyMap.new(w.field)
	w.placement = PlacementSystem.new(w.field, w.occ)
	w.paths = PathNetwork.new(w.field, w.occ, w.placement)
	var st := SettlementGenerator.new(w.field, w.occ, w.placement, w.paths, w.profile, seed)
	w.settlement = st
	var b := AuthoredIslandBuilder.new()
	b.w = w
	b.st = st
	b.map = map
	b.field = w.field
	b.pal = VoxelPalette.get_default()
	b._plaza()
	b._anchor_pad()
	b._buildings()
	b._pier()
	b._paths()
	b._door_paths()
	lap.call("amenagements")
	b._props()
	b._anchor()
	b._rocks()
	b._trees()
	st._soften_edges()
	w.field.remove_small_blocks(6, w.occ.tag)
	w.field.fill_hollows(48, 3, w.occ.tag)
	lap.call("objets")
	if not opts.get("no_plants", false):
		b._plants()
	lap.call("plantes")
	w.props = st.props
	w.authored = {"map": map, "spawn": b._spawn(), "anchor": b.anchor_info, "plaza": st.plaza, "signature": signature(map),
		"interiors": [], "route": b.route_points}
	if opts.get("no_models", false):
		return w
	var ctx := WorldBuilder._start_models(w)
	if not opts.get("no_voxels", false):
		b._voxels()
	lap.call("voxelisation")
	WorldBuilder._finish_models(w, ctx)
	lap.call("modeles")
	w.authored["interiors"] = b._interiors()
	w.failures = st.failures.duplicate()
	return w

var w: WorldData
var st: SettlementGenerator
var map: Dictionary
var field: TerrainField
var pal: VoxelPalette
var anchor_info := {}
var route_points: Array = []

func log_event(msg: String) -> void:
	w.log_event(msg)

# ------------------------------------------------------------------ plateformes

func _pad_target(rect: Rect2i) -> int:
	var tops: Array[int] = []
	for cz in range(rect.position.y, rect.end.y, 2):
		for cx in range(rect.position.x, rect.end.x, 2):
			if field.has_ground(cx, cz):
				tops.append(field.top_at(cx, cz))
	if tops.is_empty():
		return 0
	tops.sort()
	return tops[tops.size() / 2]

func _disc_pad(center: Vector2, radius: float, zone: int, mat_key: String, tag: int, level := -999999) -> Dictionary:
	var half := int(ceil(radius / V))
	var col := field.col_of_m(center.x, center.y)
	var rect := Rect2i(col - Vector2i(half, half), Vector2i(half, half) * 2)
	var target := level if level != -999999 else _pad_target(rect)
	TerrainEditor.stamp_pad(field, rect, target, zone, pal.id(mat_key), true)
	var owner := w.occ.new_owner()
	w.occ.reserve_disc(center, radius, tag, owner)
	w.placement.mark_access(rect)
	return {"center": center, "radius": radius, "level": target, "rect": rect, "owner": owner, "col": col}

## Place centrale : disque pavé (médaillon et couronne plus sombres), le reste du carré redevient herbe rase.
func _plaza() -> void:
	var pz: Dictionary = map.get("plaza", {})
	if pz.is_empty():
		return
	var c := IslandMap.v2(pz["center"])
	var pr := float(pz["radius"])
	var d := _disc_pad(c, pr, TerrainField.Zone.PLAZA, "cobble", PlacementSpec.TAG_PLAZA)
	var rect: Rect2i = d["rect"]
	var dark := pal.id("cobble_dark")
	var cob := pal.id("cobble")
	var grass := pal.id("grass_trim")
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if not field.has_ground(cx, cz):
				continue
			var i := field.idx(cx, cz)
			var dd := field.center_m(cx, cz).distance_to(c)
			if dd > pr:
				field.zone[i] = TerrainField.Zone.NATURAL
				field.material[i] = grass
			else:
				field.material[i] = dark if (dd < 1.3 or dd > pr - 0.45 or (dd > 2.6 and dd < 3.0)) else cob
	st.plaza = d

## Esplanade du sanctuaire (dallage sombre) autour de l'Ancre.
func _anchor_pad() -> void:
	var a: Dictionary = map.get("anchor", {})
	if a.is_empty():
		return
	var c := IslandMap.v2(a["pos"])
	var d := _disc_pad(c, float(a.get("pad_radius_m", 6.0)), TerrainField.Zone.PLOT, "cobble_dark", PlacementSpec.TAG_PLOT)
	st.shrine = {"center": c, "rect": d["rect"], "level": d["level"], "owner": d["owner"], "col": d["col"]}

# ------------------------------------------------------------------ bâtiments

func _buildings() -> void:
	for e: Dictionary in map.get("buildings", []):
		var type: String = e["type"]
		var plan := BuildingPlanner.plan(type, int(e["seed"]))
		var spec := BuildingPlacement.spec_for(plan)
		var yaw := int(e.get("yaw", 0))
		var half := spec.half_extents(yaw)
		var p := IslandMap.v2(e["pos"])
		var sp := Vector2(roundf((p.x - half.x) / spec.snap_m), roundf((p.y - half.y) / spec.snap_m)) * spec.snap_m + half
		var rect := w.placement.footprint_rect(sp, half)
		var yard := Rect2i(rect.position - Vector2i(3, 3), rect.size + Vector2i(6, 6))
		var target := _pad_target(rect)
		var owner := w.occ.new_owner()
		TerrainEditor.stamp_pad(field, yard, target, TerrainField.Zone.PLOT, pal.id("path_dirt"), true)
		w.occ.reserve(yard, PlacementSpec.TAG_ROAD, owner)
		w.occ.reserve(rect, PlacementSpec.TAG_PLOT, owner)
		var res := _place_or_force(spec, sp, yaw, {"owner": owner})
		var door := BuildingPlacement.door_world(plan, res)
		var dc := field.col_of_m(door.x, door.y)
		st.buildings.append({"type": type, "plan": plan, "res": res, "door": door, "door_col": dc,
			"xform": BuildingPlacement.node_transform(res), "owner": owner, "plot_rect": rect, "yard": yard,
			"id": e.get("id", type), "visitable": bool(e.get("visitable", false)), "door_path": e.get("door_path", [])})

## Pose exacte ; si le placement universel refuse (carte dessinée à la main), l'objet est posé quand même
## à la hauteur du sol et l'écart est journalisé.
## `sink` : base au plus bas du sol sous l'emprise (rochers enfoncés) ; sinon à la hauteur médiane.
func _place_or_force(spec: PlacementSpec, pos: Vector2, yaw: int, opts := {}, sink := false) -> PlacementResult:
	var res := w.placement.evaluate(spec, pos, yaw, opts)
	if not res.ok:
		log_event("posé malgré refus : %s (%s) en (%.1f, %.1f)" % [spec.id, ",".join(res.reasons), pos.x, pos.y])
		var half := spec.half_extents(yaw)
		var sp := w.placement._snap(spec, pos, half)
		var rect := w.placement.footprint_rect(sp, half)
		var tops: Array[int] = []
		for cz in range(rect.position.y, rect.end.y):
			for cx in range(rect.position.x, rect.end.x):
				if field.has_ground(cx, cz):
					tops.append(field.top_at(cx, cz))
		tops.sort()
		var base := -(1 << 30)
		if not tops.is_empty():
			base = tops[0] if sink else tops[tops.size() / 2]
		if base == -(1 << 30):
			var c := field.col_of_m(sp.x, sp.y)
			base = field.top_at(c.x, c.y) if field.has_ground(c.x, c.y) else 0
		res.rect = rect
		res.base_top = base
		res.pos = Vector3(sp.x, float(base + 1) * V, sp.y)
		res.reasons.clear()
		res.ok = true
	w.placement.commit(res, opts)
	return res

# ------------------------------------------------------------------ quai

func _pier() -> void:
	var pm: Dictionary = map.get("pier", {})
	if pm.is_empty():
		return
	var landing := IslandMap.v2(pm["landing"])
	var axis := IslandMap.v2(pm["axis"]).normalized()
	var perp := Vector2(-axis.y, axis.x)
	var run := PortBuilder._ground_run(field, landing, axis, 60.0)
	var rim := landing + axis * run
	var pad_c := rim - axis * 2.6
	var half := Vector2(absf(axis.x) * 2.2 + absf(axis.y) * 2.6, absf(axis.y) * 2.2 + absf(axis.x) * 2.6)
	var lo := pad_c - half
	var hi := pad_c + half
	var rect := Rect2i(field.col_of_m(lo.x, lo.y), Vector2i(int(ceil((hi.x - lo.x) / V)), int(ceil((hi.y - lo.y) / V))))
	var port := {"axis": axis, "perp": perp, "yaw": PortBuilder.yaw_of_dir(axis), "rim": rim, "pad_center": pad_c, "pad_rect": rect,
		"eval_rect": rect, "target": _pad_target(rect), "ship_side": float(pm.get("ship_side", 1)), "landing": pad_c,
		"length": PortBuilder.PIER_LEN, "width": PortBuilder.PIER_W}
	PortBuilder.prepare_land(field, w.occ, w.placement, port)
	st.port = port

# ------------------------------------------------------------------ chemins

## Cellules (colonnes) d'une polyligne, 4-connexes, sans doublon.
func _cells_of(points: PackedVector2Array) -> Array:
	var cells: Array = []
	for k in points.size() - 1:
		var a := points[k]
		var b := points[k + 1]
		var steps := maxi(int(ceil(a.distance_to(b) / (V * 0.5))), 1)
		for s in range(steps + 1):
			var q := a.lerp(b, float(s) / float(steps))
			var c := field.col_of_m(q.x, q.y)
			if not cells.is_empty():
				var last: Vector2i = cells.back()
				if last == c:
					continue
				if last.x != c.x and last.y != c.y:
					cells.append(Vector2i(c.x, last.y))
			cells.append(c)
	return cells

## Taille un chemin le long d'une polyligne : profil lissé qui suit le relief (pente ≤ 1:2, marches de 20 cm au
## plus), raccords imposés sur les tracés existants, la place, les cours et le quai. `regular` : rampe linéaire
## entre deux points fixes (marches de même hauteur à intervalles égaux).
func carve_polyline(points: PackedVector2Array, width: float, material: String, regular := false, name := "", skirt := 12) -> bool:
	var cells := _cells_of(points)
	var keep: Array = []
	for c: Vector2i in cells:
		if field.has_ground(c.x, c.y):
			keep.append(c)
	cells = keep
	var k := cells.size()
	if k < 2:
		log_event("chemin %s : trop court ou hors de l'île" % name)
		return false
	var h := PackedInt32Array()
	h.resize(k)
	var locked := {}
	for i in k:
		var c: Vector2i = cells[i]
		var idx := c.x + c.y * field.n
		h[i] = field.top[idx]
		if w.paths.road_cells.has(idx):
			h[i] = w.paths.road_cells[idx]
			locked[i] = true
		else:
			var z := field.zone[idx]
			if z == TerrainField.Zone.PLAZA or z == TerrainField.Zone.PLOT or z == TerrainField.Zone.PORT:
				locked[i] = true
	# lissage (moyenne glissante sur ±6 cellules) des cellules libres
	var sm := h.duplicate()
	for i in k:
		if locked.has(i):
			continue
		var s := 0
		var cnt := 0
		for d in range(-6, 7):
			var j := clampi(i + d, 0, k - 1)
			s += h[j]
			cnt += 1
		sm[i] = int(round(float(s) / float(cnt)))
	h = sm
	if regular:
		var i0 := 0
		while i0 < k - 1 and not locked.has(i0):
			i0 += 1
		var first := 0 if not locked.has(0) else 0
		# extrémités : on fige le début et la fin pour une rampe régulière
		locked[0] = true
		locked[k - 1] = true
		i0 = first
		while i0 < k - 1:
			var j0 := i0 + 1
			while j0 < k - 1 and not locked.has(j0):
				j0 += 1
			if j0 - i0 > 1 and absi(h[j0] - h[i0]) <= j0 - i0:
				for mm in range(i0 + 1, j0):
					h[mm] = h[i0] + int(round(float(h[j0] - h[i0]) * float(mm - i0) / float(j0 - i0)))
					locked[mm] = true
			i0 = j0
	# contraintes : |Δ| ≤ 1 entre voisines et ≤ 1 sur deux pas
	for iteration in 60:
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
	var worst := 0
	for i in range(1, k):
		worst = maxi(worst, absi(h[i] - h[i - 1]))
	if worst > 1:
		log_event("chemin %s : marche de %d cellules à un raccord" % [name, worst])
	w.paths._carve(cells, h, width, material, skirt)
	w.paths.routes.append({"from": cells[0], "to": cells[k - 1], "cells": cells, "heights": h, "width": width, "material": material, "name": name})
	return true

func _paths() -> void:
	for p: Dictionary in map.get("paths", []):
		var pts := IslandMap.pts(p["pts"])
		carve_polyline(pts, float(p.get("width", 1.8)), String(p.get("material", "path_dirt")), bool(p.get("regular", false)), String(p.get("id", "")), int(p.get("skirt", 12)))
		if String(p.get("kind", "main")) == "main":
			for q in pts:
				if route_points.is_empty() or (route_points.back() as Vector2).distance_to(q) > 0.5:
					route_points.append(q)

## Allées des portes : de la cour (devant la porte) jusqu'au réseau (points donnés par la carte).
func _door_paths() -> void:
	for b in st.buildings:
		var wp: Array = b.get("door_path", [])
		if wp.is_empty():
			continue
		var res: PlacementResult = b["res"]
		var front := BuildingPlacement.front_dir(res)
		var door: Vector2 = b["door"]
		var pts := PackedVector2Array([door + front * 0.6, door + front * 2.2])
		for q in wp:
			pts.append(IslandMap.v2(q))
		carve_polyline(pts, 1.6, "cobble" if b["type"] != "warehouse" else "path_dirt", false, "allée " + String(b["id"]))

# ------------------------------------------------------------------ objets, ancre, rochers, arbres

func _prop_spec(id: String) -> PlacementSpec:
	var info := AssetLibrary.info(id)
	var s := PlacementSpec.from_asset_info(info, "prop")
	s.snap_m = 0.2
	s.clearance_m = 0.15
	s.cliff_margin_m = 0.2
	s.support_fraction = 0.5
	s.gap_tolerance_m = 0.3
	s.embed_max_m = 0.4
	s.allowed_zones = PackedInt32Array([TerrainField.Zone.NATURAL, TerrainField.Zone.PLAZA, TerrainField.Zone.PLOT, TerrainField.Zone.ROAD,
		TerrainField.Zone.STAIR, TerrainField.Zone.GARDEN, TerrainField.Zone.PORT, TerrainField.Zone.RETAIN])
	s.allowed_tags = PackedInt32Array([PlacementSpec.TAG_PLAZA, PlacementSpec.TAG_ROAD, PlacementSpec.TAG_PLOT, PlacementSpec.TAG_ITEM,
		PlacementSpec.TAG_GARDEN, PlacementSpec.TAG_PORT])
	return s

func _place_prop(id: String, pos: Vector2, yaw: int, kind := "decor") -> PlacementResult:
	var spec := _prop_spec(id)
	var res := _place_or_force(spec, pos, yaw, {"skip_access": true})
	st._record_prop(id, res, kind, {})
	return res

func _props() -> void:
	for p: Dictionary in map.get("props", []):
		_place_prop(String(p["id"]), IslandMap.v2(p["pos"]), int(p.get("yaw", 0)), String(p.get("group", "decor")))

## L'Ancre : plateforme et socle au centre de l'esplanade ; le cristal est au sommet du socle.
func _anchor() -> void:
	var a: Dictionary = map.get("anchor", {})
	if a.is_empty():
		return
	var c := IslandMap.v2(a["pos"])
	var yaw := int(a.get("yaw", 0))
	var r1 := _place_prop("teleport_anchor", c, yaw, "shrine")
	var r2 := _place_prop("anchor_pedestal", c, yaw, "shrine")
	var info := AssetLibrary.info("anchor_pedestal")
	var crystal_y := r2.pos.y + 1.92
	if not (info.get("lights", []) as Array).is_empty():
		crystal_y = r2.pos.y + float(info["lights"][0]["position"][1])
	anchor_info = {"pos": Vector3(c.x, r2.pos.y, c.y), "crystal": Vector3(c.x, crystal_y, c.y), "platform_y": r1.pos.y,
		"radius_m": float(a.get("radius_m", 3.0)), "id": String(map.get("id", "ile"))}

func _rocks() -> void:
	var ng := _nature()
	for r: Dictionary in map.get("rocks", []):
		var fam: String = r["family"]
		var seed := int(r["seed"])
		var sub: String = r.get("sub", "")
		var pl := RockGenerator.plan(fam, seed, sub)
		var want: String = r.get("variant", "")
		if want != "" and fam == "boulder":
			var tries := 0
			while String(pl.get("variant", "")) != want and tries < 60:
				tries += 1
				pl = RockGenerator.plan(fam, seed + tries * 7919, sub)
			seed = int(pl["seed"])
		var k := float(r.get("scale", 1.0))
		if absf(k - 1.0) > 0.01 and fam != "ruin":
			RockGenerator.shrink(pl, k)
		var spec := ng._rock_spec(pl)
		spec.clearance_m = 0.3
		spec.allowed_zones = PackedInt32Array([TerrainField.Zone.NATURAL, TerrainField.Zone.RETAIN, TerrainField.Zone.PLOT])
		spec.forbidden_materials = PackedStringArray()
		var pos := IslandMap.v2(r["pos"])
		var yaw := int(r.get("yaw", (seed / 7) % 4))
		var res := w.placement.evaluate(spec, pos, yaw, {"skip_access": true})
		if res.ok:
			w.placement.commit(res, {})
		else:
			# un rocher ne se pose jamais de force sur un chemin : on cherche d'abord un peu à côté
			var near := w.placement.find_and_place(spec, pos, 3.0, WorldRng.stream(seed, "rock_nudge"), {"samples": 30, "skip_access": true, "yaw": yaw})
			res = near if near.ok else _place_or_force(spec, pos, yaw, {"skip_access": true}, true)
		var ground := TreeGenerator.ground_grid(field, res.pos, 3.4 * maxf(k, 1.0))
		w.rocks.append({"kind": "rock", "family": fam, "seed": seed, "plan": pl, "res": res, "ground": ground, "pos": res.pos,
			"xform": Transform3D(res.basis(), res.pos), "item": res.item_index})

func _trees() -> void:
	var ng := _nature()
	var rng := WorldRng.stream(w.seed, "authored_trees")
	for t: Dictionary in map.get("trees", []):
		var species: String = t["species"]
		var seed := int(t["seed"])
		var pl := TreeGenerator.plan(species, seed)
		var spec := ng._tree_spec(pl)
		spec.soft_overlap_max = 0.45
		var pos := IslandMap.v2(t["pos"])
		var res := w.placement.place(spec, pos, 0, {"skip_access": true})
		if not res.ok:
			var why := ",".join(res.reasons)
			res = w.placement.find_and_place(spec, pos, 1.6, rng, {"samples": 24, "skip_access": true})
			if not res.ok:
				log_event("arbre non posé : %s en (%.1f, %.1f) (%s)" % [species, pos.x, pos.y, why])
				continue
		var ground := TreeGenerator.ground_grid(field, res.pos, 2.0)
		w.trees.append({"kind": "tree", "species": species, "seed": seed, "plan": pl, "res": res, "ground": ground,
			"rot": float(seed % 628) * 0.01, "pos": res.pos, "item": res.item_index, "scale": clampf(float(t.get("scale", 1.0)), 0.5, 2.0)})

var _ng: NatureGenerator
func _nature() -> NatureGenerator:
	if _ng == null:
		_ng = NatureGenerator.new()
		_ng.w = w
		_ng.field = field
		_ng.occ = w.occ
		_ng.placement = w.placement
		_ng.rng = WorldRng.stream(w.seed, "nature")
		_ng.pal = pal
		for k in ["grass_lush"]:
			_ng._mat_biome[pal.id(k)] = "lush"
		for k in ["grass_dry", "dirt_dry"]:
			_ng._mat_biome[pal.id(k)] = "dry"
		for k in ["rock_warm", "rock_grey", "stone", "stone_dark"]:
			_ng._mat_biome[pal.id(k)] = "rock"
	return _ng

func _plants() -> void:
	var ng := _nature()
	ng._reserve_corridors()
	ng._plants()

func _spawn() -> Dictionary:
	var s: Dictionary = map.get("spawn", {})
	var p := IslandMap.v2(s.get("pos", [0, 0]))
	var g := field.ground_at_m(p.x, p.y)
	# Lot 10 : `pier_m` pose le départ SUR le ponton, à cette distance (m) du bord de l'île, au milieu du tablier
	# (le joueur descend du navire : bateau à côté de lui, grève et sentier devant). `pos` reste un point de terre ferme voisin.
	if s.has("pier_m") and not st.port.is_empty():
		var rim: Vector2 = st.port["rim"]
		var axis: Vector2 = st.port["axis"]
		var q := rim + axis * float(s["pier_m"])
		return {"pos": Vector3(q.x, float(st.port["deck_top"]) + 0.1, q.y), "yaw_deg": float(s.get("yaw_deg", 0.0))}
	return {"pos": Vector3(p.x, (0.0 if is_nan(g) else g) + 0.1, p.y), "yaw_deg": float(s.get("yaw_deg", 0.0))}

## Volumes intérieurs des bâtiments (monde) : la caméra se rapproche quand le joueur y entre.
func _interiors() -> Array:
	var out: Array = []
	for b in w.buildings:
		var plan: BuildingPlan = b["plan"]
		var xf: Transform3D = b["xform"]
		var body := plan.body_rect()
		var lo := Vector3(float(body.position.x) * 0.1, 0.0, float(body.position.y) * 0.1)
		var hi := Vector3(float(body.end.x) * 0.1, float(plan.max_height_cells()) * 0.1, float(body.end.y) * 0.1)
		var a := xf * lo
		var c := xf * hi
		var box := AABB(a.min(c), (c - a).abs())
		var e := {"id": b.get("id", b["type"]), "type": b["type"], "aabb": box, "visitable": b.get("visitable", false),
			"floor0_y": xf.origin.y + float(plan.floor_y(0)) * 0.1, "floors": plan.floors}
		var door: Vector2 = b["door"]
		var front := BuildingPlacement.front_dir(b["res"])
		e["door"] = [door.x, door.y]
		e["front"] = [front.x, front.y]
		if plan.stair != null:
			# escalier : pied au sud (repère local), palier au nord à hauteur de l'étage
			var st: BuildingPlan.StairPlan = plan.stair
			var cx := (float(st.x0) + float(st.w) * 0.5) * 0.1
			var foot := xf * Vector3(cx, float(plan.floor_y(0)) * 0.1, (float(st.z0 + st.l) + 4.0) * 0.1)
			var top := xf * Vector3(cx, float(plan.floor_y(1)) * 0.1, (float(st.z0) + 1.0) * 0.1)
			e["stair_foot"] = [foot.x, foot.y, foot.z]
			e["stair_top"] = [top.x, top.y, top.z]
			e["floor1_y"] = top.y
		out.append(e)
	return out

# ------------------------------------------------------------------ voxels (tuiles) et sous-face

func _voxels() -> void:
	var blocks := AuthoredTerrain.finalize_bottoms(field)
	var n := field.n
	var jobs: Array = []
	for tz in range(0, n, TILE):
		for tx in range(0, n, TILE):
			var rect := Rect2i(tx, tz, mini(TILE, n - tx), mini(TILE, n - tz))
			var any := false
			for cz in range(rect.position.y, rect.end.y, 4):
				for cx in range(rect.position.x, rect.end.x, 4):
					if field.has_ground(cx, cz):
						any = true
						break
				if any:
					break
			if not any:
				# bords de tuile : quelques colonnes de sol peuvent échapper à l'échantillonnage
				for cz in range(rect.position.y, rect.end.y):
					for cx in range(rect.position.x, rect.end.x):
						if field.has_ground(cx, cz):
							any = true
							break
					if any:
						break
			if any:
				jobs.append({"rect": rect, "out": []})
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		_tile_job(jobs[i]),
		jobs.size(), -1, true, "Tuiles de terrain")
	var under := AuthoredTerrain.build_underside(field, blocks, w.seed)
	var under_meshes: Array = []
	if not under.is_empty():
		var vol: VoxelVolume = under["volume"]
		var uj: Array = []
		for cz in range(0, vol.size.z, 64):
			for cx in range(0, vol.size.x, 64):
				uj.append({"min": Vector3i(cx, 0, cz), "max": Vector3i(mini(cx + 64, vol.size.x), vol.size.y, mini(cz + 64, vol.size.z)) - Vector3i.ONE, "arrays": []})
		var t2 := WorkerThreadPool.add_group_task(func(i: int) -> void:
			uj[i]["arrays"] = VoxelMesher.build_arrays(vol, 1.0, uj[i]["min"], uj[i]["max"], PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.STYLIZED),
			uj.size(), -1, true, "Sous-face")
		WorkerThreadPool.wait_for_group_task_completion(t2)
		for j in uj:
			if not (j["arrays"] as Array).is_empty():
				under_meshes.append({"arrays": j["arrays"], "origin": under["origin"]})
	WorkerThreadPool.wait_for_group_task_completion(task)
	var tiles: Array = []
	var tv := 0
	var tm := 0
	for j in jobs:
		tiles.append_array(j["out"])
		tv += int(j.get("t_vox", 0))
		tm += int(j.get("t_mesh", 0))
	w.timings["tuiles_voxels_cumul"] = tv / 1000
	w.timings["tuiles_maillage_cumul"] = tm / 1000
	w.authored["terrain_meshes"] = tiles
	w.authored["underside_meshes"] = under_meshes

## Une tuile : voxélisation (TerrainVoxelizer) puis maillages par morceaux de 16 m ; les volumes sont libérés.
func _tile_job(job: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var data := TerrainVoxelizer.build(field, job["rect"])
	if data == null:
		return
	var size := data.size()
	# Remplissage VIRTUEL (masque seulement) sous la croûte des colonnes intérieures : la sous-face grossière est
	# dessous, les faces cachées (dessous et flancs enterrés de la croûte) ne sont pas maillées.
	var rect: Rect2i = job["rect"]
	var y_off := -data.origin_cell.y
	var stride_y := size.x * size.z
	var solid := data.solid
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			var i := cx + cz * field.n
			if field.top[i] == TerrainField.NO_GROUND or field.edge_dist[i] < 3.0:
				continue
			var li := (cx - rect.position.x) + (cz - rect.position.y) * size.x
			for vy in range(0, field.bottom[i] + y_off):
				solid[li + vy * stride_y] = 1
	job["t_vox"] = Time.get_ticks_usec() - t0
	var origin := VoxelGrid.cell_to_world(data.origin_cell)
	for cz in range(0, size.z, CHUNK):
		for cx in range(0, size.x, CHUNK):
			var rmin := Vector3i(cx, 0, cz)
			var rmax := Vector3i(mini(cx + CHUNK, size.x), size.y, mini(cz + CHUNK, size.z)) - Vector3i.ONE
			for layer in [data.core, data.surface]:
				var arr := VoxelMesher.build_arrays(layer, V, rmin, rmax, data.solid, data.origin_cell, 0, VoxelMesher.Style.STYLIZED)
				if not arr.is_empty():
					(job["out"] as Array).append({"arrays": arr, "origin": origin, "name": "T_%d_%d_%s" % [(job["rect"] as Rect2i).position.x + cx, (job["rect"] as Rect2i).position.y + cz, "c" if layer == data.core else "s"]})
	job["t_mesh"] = Time.get_ticks_usec() - t0 - int(job["t_vox"])
