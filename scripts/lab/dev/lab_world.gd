class_name LabWorld
extends Node3D
## Monde ÉDITABLE du laboratoire développeur (Lot 6) : un terrain du Lot 4 (TerrainField, colonnes de 20 cm), sa mise en
## volume par tuiles de 16 m, ses collisions, et des OPÉRATIONS réversibles :
##   arbre / rocher en un point · maison dans un rectangle (avec raccord au sol) · aplanissement d'une zone peinte.
## Chaque opération se PRÉPARE (vérification complète, aperçu, raison du refus, terrain INTACT) puis s'APPLIQUE ;
## annuler = restaurer l'état d'avant (terrain, réservations, objets, collisions, maillages), raccord au sol compris.
## Réutilise le Lot 4 : TerrainEditor (plateforme + talus), PlacementSystem, BuildingPlanner/Builder, TreeGenerator,
## RockGenerator, et le Lot 5 : AuthoredTerrain, AuthoredIslandBuilder (tuiles), AuthoredIslandView (collisions).

signal changed(op: Dictionary, what: String)       # what : "applique" | "annule"

const V := VoxelGrid.VOXEL_SIZE
const TILE := 80                       # colonnes par tuile (16 m)
const HOUSE_YARD := 3                  # colonnes de cour autour de l'emprise (60 cm) ramenées au niveau de la maison
const HOUSE_CUT := 3                   # terrassement maximal sous l'emprise : 3 cellules (60 cm) en déblai…
const HOUSE_FILL := 3                  # … et autant en remblai (dénivelé admis : 1,20 m)
const BRUSH_CUT := 3                   # aplanissement : déblai maximal 60 cm, remblai maximal 1 m
const BRUSH_FILL := 5
const MIN_W := 26                      # plus petite cabane : bloc de 2,6 m
const MIN_D := 22
const MAX_DIM := 120

var kind := "room"
var world: WorldData
var field: TerrainField
var occ: OccupancyMap
var placement: PlacementSystem
var pal: VoxelPalette
var terrain_root: Node3D
var objects_root: Node3D
var ground_shape: HeightMapShape3D
var ground_body: StaticBody3D
var stack: Array[Dictionary] = []      # opérations appliquées (la dernière s'annule en premier)
var busy := false
var version := 0                       # incrémenté à chaque application / annulation
var spawn := Vector3.ZERO
var build_ms := 0
var last_rebuild_ms := 0
var _bld: AuthoredIslandBuilder
var _nat: NatureGenerator
var _counter := 0

# ------------------------------------------------------------------ cartes des deux environnements

static func lab_map(env_kind: String) -> Dictionary:
	if env_kind == "room":
		return {"id": "labo-salle", "seed": 7, "terrain": {"outline": [[-15, -15], [15, -15], [15, 15], [-15, 15]],
			"base_m": 2.0, "noise_m": 0.0, "shapes": [], "core_depth_cells": 20}}
	# île vide : ovale irrégulier d'environ 54 × 50 m ; versant ouest plat (4 m), pente de 20 % (≈ 11°) de x = -6 à x = 14,
	# replat est à 8 m. Aucun objet : tout est posé par les outils.
	return {"id": "labo-ile", "seed": 7, "terrain": {"outline": [[-27, 2], [-23, -12], [-12, -22], [3, -26], [17, -22], [25, -10],
			[27, 4], [22, 17], [10, 24], [-4, 26], [-17, 22], [-25, 14]],
		"base_m": 4.0, "noise_m": 0.05, "noise_freq": 0.05,
		"shapes": [{"type": "line", "hw": 60.0, "pts": [[-6, 0, 4.0], [14, 0, 8.0]], "blend": 0.0, "op": "set"}],
		"core_depth_cells": 20}}

# ------------------------------------------------------------------ construction

func setup(env_kind: String) -> void:
	var map := lab_map(env_kind)
	var f := AuthoredTerrain.build_field(map)
	if env_kind == "room":
		var gray := VoxelPalette.get_default().id("stone_light")
		for i in f.n * f.n:
			if f.top[i] != TerrainField.NO_GROUND:
				f.material[i] = gray
	var sx := -9.0 if env_kind == "island" else 0.0
	var sz := 4.0 if env_kind == "island" else 10.0
	setup_field(f, env_kind, int(map["seed"]), Vector2(sx, sz))

## Monte le monde éditable sur un terrain déjà construit (laboratoire ou île issue d'un plan, Lot 7).
func setup_field(p_field: TerrainField, env_kind: String, p_seed: int, spawn_xz: Vector2) -> void:
	var t0 := Time.get_ticks_msec()
	kind = env_kind
	pal = VoxelPalette.get_default()
	VoxelMesher.palette_warmup()
	world = WorldData.new()
	world.seed = p_seed
	world.profile = IslandProfile.load_profile("settled")
	field = p_field
	world.field = field
	occ = OccupancyMap.new(field)
	placement = PlacementSystem.new(field, occ)
	world.occ = occ
	world.placement = placement
	_bld = AuthoredIslandBuilder.new()
	_bld.field = field
	_bld.w = world
	_bld.pal = pal
	_nat = NatureGenerator.new()
	_nat.w = world
	_nat.field = field
	_nat.occ = occ
	_nat.placement = placement
	_nat.rng = WorldRng.stream(world.seed, "lab")
	_nat.pal = pal
	# vue : terrain par tuiles + sous-face (île) ; collisions du sol
	var blocks := AuthoredTerrain.finalize_bottoms(field)
	var rects := _all_tiles()
	var task := _start_tiles(rects)
	world.authored["underside_meshes"] = _underside(blocks) if env_kind != "room" else []
	var tiles := _finish_tiles(task)
	world.authored["terrain_meshes"] = tiles
	var refs := AuthoredIslandView.create(world, self)
	terrain_root = (refs["root"] as Node3D).get_node("Terrain")
	ground_body = (refs["root"] as Node3D).get_node("Physics/Ground") as StaticBody3D
	ground_shape = (ground_body.get_child(0) as CollisionShape3D).shape as HeightMapShape3D
	objects_root = Node3D.new()
	objects_root.name = "Objets"
	add_child(objects_root)
	spawn = Vector3(spawn_xz.x, field.ground_at_m(spawn_xz.x, spawn_xz.y) + 0.1, spawn_xz.y)
	build_ms = Time.get_ticks_msec() - t0

func _all_tiles() -> Array:
	var rects: Array = []
	for tz in range(0, field.n, TILE):
		for tx in range(0, field.n, TILE):
			var r := Rect2i(tx, tz, mini(TILE, field.n - tx), mini(TILE, field.n - tz))
			if _has_land(r):
				rects.append(r)
	return rects

func _has_land(r: Rect2i) -> bool:
	for cz in range(r.position.y, r.end.y):
		for cx in range(r.position.x, r.end.x):
			if field.has_ground(cx, cz):
				return true
	return false

func _start_tiles(rects: Array) -> Dictionary:
	var jobs: Array = []
	for r in rects:
		jobs.append({"rect": r, "out": []})
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		_bld._tile_job(jobs[i]), maxi(jobs.size(), 1), -1, true, "Tuiles du laboratoire")
	return {"task": task, "jobs": jobs}

func _finish_tiles(t: Dictionary) -> Array:
	WorkerThreadPool.wait_for_group_task_completion(t["task"])
	var out: Array = []
	for j in t["jobs"]:
		out.append_array(j["out"])
	return out

func _underside(blocks: Dictionary) -> Array:
	var under := AuthoredTerrain.build_underside(field, blocks, world.seed)
	var meshes: Array = []
	if under.is_empty():
		return meshes
	var vol: VoxelVolume = under["volume"]
	var uj: Array = []
	for cz in range(0, vol.size.z, 64):
		for cx in range(0, vol.size.x, 64):
			uj.append({"min": Vector3i(cx, 0, cz), "max": Vector3i(mini(cx + 64, vol.size.x), vol.size.y, mini(cz + 64, vol.size.z)) - Vector3i.ONE, "arrays": []})
	var t2 := WorkerThreadPool.add_group_task(func(i: int) -> void:
		uj[i]["arrays"] = VoxelMesher.build_arrays(vol, 1.0, uj[i]["min"], uj[i]["max"], PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.STYLIZED),
		uj.size(), -1, true, "Sous-face du laboratoire")
	WorkerThreadPool.wait_for_group_task_completion(t2)
	for j in uj:
		if not (j["arrays"] as Array).is_empty():
			meshes.append({"arrays": j["arrays"], "origin": under["origin"]})
	return meshes

## Reconstruit les tuiles qui touchent le rectangle de colonnes (sans bloquer : on attend en rendant la main au jeu).
func rebuild_rect(cols: Rect2i) -> void:
	if cols.size.x <= 0 or cols.size.y <= 0:
		return
	var t0 := Time.get_ticks_msec()
	var grown := cols.grow(2)
	var rects: Array = []
	for tz in range(0, field.n, TILE):
		for tx in range(0, field.n, TILE):
			var r := Rect2i(tx, tz, mini(TILE, field.n - tx), mini(TILE, field.n - tz))
			if r.intersects(grown) and _has_land(r):
				rects.append(r)
	var t := _start_tiles(rects)
	while not WorkerThreadPool.is_group_task_completed(t["task"]):
		await get_tree().process_frame
	var tiles := _finish_tiles(t)
	for r: Rect2i in rects:
		for mi in terrain_root.get_children():
			var nm := String(mi.name)
			var parts := nm.split("_")
			if parts.size() >= 3 and nm.begins_with("T_") and int(parts[1]) >= r.position.x and int(parts[1]) < r.end.x \
					and int(parts[2]) >= r.position.y and int(parts[2]) < r.end.y:
				terrain_root.remove_child(mi)
				mi.queue_free()
	for tl in tiles:
		var mesh := VoxelMesher.arrays_to_mesh(tl["arrays"], VoxelMesher.Style.STYLIZED)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = tl["name"]
		mi.mesh = mesh
		mi.position = tl["origin"]
		terrain_root.add_child(mi)
	update_ground()
	last_rebuild_ms = Time.get_ticks_msec() - t0

## Carte de hauteurs de collision (une valeur par colonne) : relue après chaque modification du relief.
func update_ground() -> void:
	var n := field.n
	var data := PackedFloat32Array()
	data.resize(n * n)
	for i in n * n:
		var t := field.top[i]
		data[i] = (-400.0 if t == TerrainField.NO_GROUND else float(t + 1) * V) / V
	ground_shape.map_data = data

# ------------------------------------------------------------------ services

func ground_y(x: float, z: float) -> float:
	return field.ground_at_m(x, z)

func has_ground_m(x: float, z: float) -> bool:
	var c := field.col_of_m(x, z)
	return field.has_ground(c.x, c.y)

func snapshot() -> Dictionary:
	return {"top": field.top.duplicate(), "zone": field.zone.duplicate(), "mat": field.material.duplicate(),
		"tag": occ.tag.duplicate(), "own": occ.owner.duplicate(), "items": occ.items.size()}

func restore(s: Dictionary) -> void:
	field.top = s["top"]
	field.zone = s["zone"]
	field.material = s["mat"]
	occ.tag = s["tag"]
	occ.owner = s["own"]
	while occ.items.size() > int(s["items"]):
		occ.remove_last_item()

## Colonnes modifiées entre deux états (boîte englobante) ; vide si rien n'a changé.
func diff_rect(a: Dictionary, b_top: PackedInt32Array, b_zone: PackedByteArray, b_mat: PackedByteArray) -> Rect2i:
	var n := field.n
	var lo := Vector2i(n, n)
	var hi := Vector2i(-1, -1)
	var at: PackedInt32Array = a["top"]
	var az: PackedByteArray = a["zone"]
	var am: PackedByteArray = a["mat"]
	for i in n * n:
		if at[i] != b_top[i] or az[i] != b_zone[i] or am[i] != b_mat[i]:
			var cx := i % n
			var cz := i / n
			lo = Vector2i(mini(lo.x, cx), mini(lo.y, cz))
			hi = Vector2i(maxi(hi.x, cx), maxi(hi.y, cz))
	if hi.x < 0:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)

static func reason_text(key: String, ctx := {}) -> String:
	match key:
		PlacementSpec.R_OUT, "hors_ile": return "L'emprise sort de l'île."
		PlacementSpec.R_CLIFF, "trop_pres_du_bord": return "Trop près du bord de l'île (marge de sécurité non respectée)."
		PlacementSpec.R_RESERVED, "reserve": return "L'emprise touche un espace déjà occupé (construction, objet ou cour)."
		"relief_trop_accidente": return "Relief trop accidenté : dénivelé de %.2f m sur l'emprise, au plus %.2f m se raccordent." % [float(ctx.get("range_m", 0.0)), float(ctx.get("max_m", 1.2))]
		PlacementSpec.R_SLOPE: return "Pente trop forte pour cet emplacement."
		PlacementSpec.R_SUPPORT: return "Le sol ne porte pas toute l'emprise (vide ou creux dessous)."
		PlacementSpec.R_COLLISION: return "Un objet est trop proche (collision)."
		PlacementSpec.R_ZONE: return "Zone interdite : chemin, place ou parcelle voisine."
		PlacementSpec.R_MATERIAL: return "Matière de sol interdite (roche, pavés…)."
		PlacementSpec.R_CORE, PlacementSpec.R_DEPTH: return "Le terrassement entamerait le cœur de l'île."
		PlacementSpec.R_SOFT: return "Les couronnes ou volumes voisins se chevauchent."
	return key

# ------------------------------------------------------------------ opérations : arbre, rocher

func prepare_tree(p: Vector2, species: String, seed: int) -> Dictionary:
	var pl := TreeGenerator.plan(species, seed)
	var spec := _nat._tree_spec(pl)
	var res := placement.evaluate(spec, p, 0, {"skip_access": true})
	var op := {"kind": "tree", "ok": res.ok, "reasons": _reasons(res), "res": res, "plan": pl, "species": species, "seed": seed, "pos": p,
		"version": version, "summary": "Arbre « %s » (graine %d)" % [species, seed]}
	if res.ok:
		var ground := TreeGenerator.ground_grid(field, res.pos, 2.0)
		var it := {"kind": "tree", "species": species, "seed": seed, "plan": pl, "res": res, "ground": ground, "rot": float(seed % 628) * 0.01, "pos": res.pos}
		WorldBuilder._run_job({"kind": "tree", "src": it})
		op["item"] = it
		op["xform"] = Transform3D(Basis(Vector3.UP, it["rot"]), (res.pos as Vector3) + WorldView.DEZFIGHT)
		op["node_fn"] = func() -> Node3D:
			var n := VoxelObjectView.create_node("%s_%d" % [species, seed % 10000], it["parts"], it["arrays"], [40.0, 110.0])
			n.transform = op["xform"]
			return n
	return op

func prepare_rock(p: Vector2, family: String, seed: int, scale := 1.0) -> Dictionary:
	var pl := RockGenerator.plan(family, seed)
	if absf(scale - 1.0) > 0.01 and family != "ruin":
		RockGenerator.shrink(pl, scale)
	var spec := _nat._rock_spec(pl)
	var res := placement.evaluate(spec, p, int((seed / 7) % 4), {"skip_access": true})
	var op := {"kind": "rock", "ok": res.ok, "reasons": _reasons(res), "res": res, "plan": pl, "family": family, "seed": seed, "pos": p, "scale": scale,
		"version": version, "summary": "Rocher « %s » (graine %d)" % [family, seed]}
	if res.ok:
		var ground := TreeGenerator.ground_grid(field, res.pos, 3.4 * maxf(scale, 1.0))
		var it := {"kind": "rock", "family": family, "seed": seed, "plan": pl, "res": res, "ground": ground, "pos": res.pos,
			"xform": Transform3D(res.basis(), res.pos)}
		WorldBuilder._run_job({"kind": "rock", "src": it})
		op["item"] = it
		op["node_fn"] = func() -> Node3D:
			var n := VoxelObjectView.create_node("%s_%d" % [family, seed % 10000], it["parts"], it["arrays"], [45.0, 130.0], true)
			n.transform = (it["xform"] as Transform3D).translated(WorldView.DEZFIGHT)
			return n
	return op

func _reasons(res: PlacementResult) -> Array:
	var out: Array = []
	for r in res.reasons:
		out.append(reason_text(r))
	return out

# ------------------------------------------------------------------ opération : maison dans un rectangle

## rect_m : rectangle sélectionné (mètres, x/z). params : seed, yaw (0-3), murs, toit. Le terrain est restauré avant de rendre.
func prepare_house(rect_m: Rect2, params: Dictionary, keep_terrain := false) -> Dictionary:
	var seed := int(params.get("seed", 1))
	var yaw := int(params.get("yaw", 0)) % 4
	var op := {"kind": "house", "ok": false, "reasons": [], "params": params.duplicate(), "version": version, "rect_m": rect_m}
	# emprise en cellules de 10 cm ; la rotation échange les dimensions du plan
	var rw := int(roundf(rect_m.size.x * 10.0))
	var rd := int(roundf(rect_m.size.y * 10.0))
	var fx := rw if yaw % 2 == 0 else rd
	var fz := rd if yaw % 2 == 0 else rw
	var W := fx - 4
	var D := fz - 8
	if W < MIN_W or D < MIN_D:
		op["reasons"] = ["Emprise trop petite : %.2f × %.2f m (minimum %.2f × %.2f m avec la cour devant la porte)." % [
			float(rw) / 10.0, float(rd) / 10.0, float(MIN_W + 4) / 10.0, float(MIN_D + 8) / 10.0]]
		return op
	if fx > MAX_DIM or fz > MAX_DIM:
		op["reasons"] = ["Emprise trop grande pour une maison simple (maximum 12 m)."]
		return op
	var type := "hut" if W < 48 else "house_small"
	var opts := {"W": W, "D": D, "annex": false}
	if params.has("murs"):
		opts["wall"] = params["murs"]
	if params.has("toit"):
		opts["roof"] = params["toit"]
	var plan := BuildingPlanner.plan(type, seed, opts)
	var spec := BuildingPlacement.spec_for(plan)
	op["plan"] = plan
	op["type"] = type
	var half := spec.half_extents(yaw)
	var center := rect_m.get_center()
	var sp := Vector2(roundf((center.x - half.x) / spec.snap_m), roundf((center.y - half.y) / spec.snap_m)) * spec.snap_m + half
	var rect := placement.footprint_rect(sp, half)
	var yard := Rect2i(rect.position - Vector2i(HOUSE_YARD, HOUSE_YARD), rect.size + Vector2i(HOUSE_YARD, HOUSE_YARD) * 2)
	op["rect"] = rect
	op["yard"] = yard
	var snap := snapshot()
	var ev := TerrainEditor.evaluate_pad(field, occ, rect, HOUSE_YARD, HOUSE_CUT, HOUSE_FILL, 2, PackedInt32Array(), 1.0)
	if not ev["ok"]:
		var hr := field.height_range(rect)
		var ctx := {"range_m": float(hr.y - hr.x) * V if hr.x != TerrainField.NO_GROUND else 0.0, "max_m": float(HOUSE_CUT + HOUSE_FILL) * V}
		op["reasons"] = [reason_text(String(ev["reason"]), ctx)]
		return op
	var target := int(ev["target"])
	var owner := occ.new_owner()
	TerrainEditor.stamp_pad(field, yard, target, TerrainField.Zone.PLOT, pal.id("path_dirt"), true)
	occ.reserve(yard, PlacementSpec.TAG_ROAD, owner)
	occ.reserve(rect, PlacementSpec.TAG_PLOT, owner)
	var res := placement.evaluate(spec, sp, yaw, {"owner": owner})
	op["res"] = res
	op["owner"] = owner
	op["target_m"] = float(target + 1) * V
	op["cut_cells"] = int(ev["cut"])
	op["fill_cells"] = int(ev["fill"])
	op["ok"] = res.ok
	op["reasons"] = _reasons(res)
	op["footprint_m"] = Vector2(plan.footprint) * 0.1
	if res.ok:
		# le modèle n'est construit que si la pose est valide
		var model := BuildingBuilder.build(plan)
		op["model"] = model
		op["arrays"] = BuildingView.make_arrays(model)
		op["xform"] = BuildingPlacement.node_transform(res)
		op["door"] = BuildingPlacement.door_world(plan, res)
	var after_top := field.top.duplicate()
	var after_zone := field.zone.duplicate()
	var after_mat := field.material.duplicate()
	op["changed_rect"] = diff_rect(snap, after_top, after_zone, after_mat)
	op["terrain_cells"] = _count_changed(snap["top"], after_top)
	if keep_terrain and res.ok:
		op["snap"] = snap
		return op
	restore(snap)
	return op

func _count_changed(a: PackedInt32Array, b: PackedInt32Array) -> int:
	var c := 0
	for i in a.size():
		if a[i] != b[i]:
			c += 1
	return c

# ------------------------------------------------------------------ opération : aplanir une zone peinte

## cells : indices de colonnes ; params : niveau (m, absolu, ou absent = médiane).
func prepare_flatten(cells: Array, params: Dictionary) -> Dictionary:
	var op := {"kind": "flatten", "ok": false, "reasons": [], "params": params.duplicate(), "version": version, "cells": cells}
	var land: Array[int] = []
	for i in cells:
		if field.top[int(i)] != TerrainField.NO_GROUND:
			land.append(int(i))
	if land.is_empty():
		op["reasons"] = ["Zone vide : peignez d'abord une zone sur le sol (clic maintenu)."]
		return op
	var tops: Array[int] = []
	for i in land:
		tops.append(field.top[i])
	tops.sort()
	var target: int = tops[tops.size() / 2]
	if params.has("niveau"):
		target = roundi(float(params["niveau"]) / V) - 1
	var cut := 0
	var fill := 0
	var cut_max := 0
	var fill_max := 0
	for i in land:
		var d := field.top[i] - target
		if d > 0:
			cut += 1
			cut_max = maxi(cut_max, d)
		elif d < 0:
			fill += 1
			fill_max = maxi(fill_max, -d)
		if occ.tag[i] != PlacementSpec.TAG_FREE:
			op["reasons"] = ["La zone peinte touche un espace occupé (construction, objet ou cour) : rien n'est modifié."]
			op["target_m"] = float(target + 1) * V
			op["land"] = land
			return op
	op["land"] = land
	op["target"] = target
	op["target_m"] = float(target + 1) * V
	op["cut_cells"] = cut
	op["fill_cells"] = fill
	op["cut_max_m"] = float(cut_max) * V
	op["fill_max_m"] = float(fill_max) * V
	if cut_max > BRUSH_CUT or fill_max > BRUSH_FILL:
		op["reasons"] = ["Dénivelé trop fort dans la zone : déblai de %.2f m (maximum %.2f m), remblai de %.2f m (maximum %.2f m). Réduisez la zone ou choisissez un niveau." % [
			float(cut_max) * V, float(BRUSH_CUT) * V, float(fill_max) * V, float(BRUSH_FILL) * V]]
		return op
	op["ok"] = true
	return op

# ------------------------------------------------------------------ opération : habitation générée (Lot 9)

## rect_m : emprise disponible (m). params : variante (auto|cabane|deux_pieces|en_L), seed, yaw (0-3), murs, toit.
## Même raccord au terrain que l'éditeur de cartes (HousePad). Le terrain est restauré avant de rendre sauf keep_terrain.
func prepare_dwelling(rect_m: Rect2, params: Dictionary, keep_terrain := false) -> Dictionary:
	var op := {"kind": "dwelling", "ok": false, "reasons": [], "params": params.duplicate(), "version": version, "rect_m": rect_m}
	var gopts := {}
	for k in ["murs", "toit"]:
		if params.has(k):
			gopts[k] = params[k]
	var gen := DwellingGenerator.generate(String(params.get("variante", "auto")), int(params.get("seed", 1)), rect_m.size, gopts)
	op["gen"] = gen
	if not bool(gen["ok"]):
		op["reasons"] = gen["reasons"]
		return op
	var model: Construction = gen["model"]
	op["model"] = model
	var yaw := posmod(int(params.get("yaw", 0)), 4)
	var pos := Vector2(snappedf(rect_m.get_center().x, 0.1), snappedf(rect_m.get_center().y, 0.1))
	var snap := snapshot()
	var ev := HousePad.evaluate(field, model, pos, yaw, {"occ": occ, "need_link": false}, true)
	op["eval"] = ev
	if not bool(ev["ok"]):
		op["reasons"] = ev["reasons"]
		restore(snap)
		return op
	op["ok"] = true
	op["pos"] = ev["pos"]
	op["yaw"] = yaw
	op["rect"] = ev["rect"]
	op["yard"] = ev["yard"]
	op["ground_m"] = ev["ground_m"]
	op["cut_cells"] = ev["cut"]
	op["fill_cells"] = ev["fill"]
	op["terrain_cells"] = (ev["changed"] as Array).size()
	op["xform"] = HousePad.node_transform(model, ev["pos"], yaw, float(ev["ground_m"]))
	op["door"] = ev.get("door", Vector2.ZERO)
	op["changed_rect"] = diff_rect(snap, field.top.duplicate(), field.zone.duplicate(), field.material.duplicate())
	if keep_terrain:
		op["snap"] = snap
		return op
	restore(snap)
	return op

# ------------------------------------------------------------------ opération : composition « marché + végétation » sur une zone peinte (Lot 9)

const COMPOSITION_PROPS := {"stall": "market_stall", "crate": "crate_stack", "barrel": "barrel_set"}
const COMPOSITION_TREES := ["oak", "birch", "parasol", "pine"]

func _prop_spec(id: String) -> PlacementSpec:
	var s := PlacementSpec.from_asset_info(AssetLibrary.info(id), "prop")
	s.snap_m = 0.2
	s.clearance_m = 0.35
	s.cliff_margin_m = 0.4
	s.support_fraction = 0.8
	s.gap_tolerance_m = 0.2
	return s

## cells : indices de colonnes peintes. params : seed, etals (0-5), vegetation (0-100 %).
## Réutilise les objets existants : étal de marchand, tas de caisses, tonneaux (assets cuits) et arbres du générateur. Chaque objet
## est posé par le système de placement (support, pente, collisions) et doit se trouver sur une colonne peinte. Le monde est
## restauré avant de rendre, sauf keep_state.
func prepare_composition(cells: Array, params: Dictionary, keep_state := false) -> Dictionary:
	var op := {"kind": "composition", "ok": false, "reasons": [], "params": params.duplicate(), "version": version, "cells": cells, "items": []}
	var land: Array[int] = []
	var painted := {}
	var sum := Vector2.ZERO
	for i in cells:
		var ii := int(i)
		if field.top[ii] != TerrainField.NO_GROUND:
			land.append(ii)
			painted[ii] = true
			sum += field.center_m(ii % field.n, ii / field.n)
	var area := float(land.size()) * V * V
	if area < 9.0:
		op["reasons"] = ["Zone trop petite pour une composition : %.1f m² peints, au moins 9 m² sont nécessaires (peignez une zone plus grande avec le pinceau)." % area]
		return op
	var center := sum / float(land.size())
	var radius := sqrt(area / PI)
	var seed := int(params.get("seed", 1))
	var n_stall := clampi(int(params.get("etals", 3)), 0, 5)
	var veg := clampf(float(params.get("vegetation", 50)), 0.0, 100.0) / 100.0
	var n_tree := clampi(roundi(veg * area / 9.0), 0, 12)
	var rng := WorldRng.stream(world.seed, "composition:%d" % seed)
	var snap := snapshot()
	var items: Array = []
	var fails := {}
	var cell_pos := func(i: int) -> Vector2:
		return field.center_m(i % field.n, i / field.n)
	var on_paint := func(p: Vector2) -> bool:
		var c := field.col_of_m(p.x, p.y)
		return painted.has(field.idx(c.x, c.y))
	var yaw_toward := func(from: Vector2, to: Vector2) -> int:
		var d := to - from
		var best := 0
		var bd := -2.0
		for y in 4:
			var f := Vector2(sin(y * PI * 0.5), cos(y * PI * 0.5))
			var dot := f.dot(d.normalized()) if d.length() > 0.01 else 0.0
			if dot > bd:
				bd = dot
				best = y
		return best
	# --- étals : en couronne autour du centre, ouverts vers lui
	var a0 := rng.randf() * TAU
	for k in n_stall:
		var placed := false
		for attempt in 14:
			var ang := a0 + float(k) * TAU / float(maxi(n_stall, 1)) + (rng.randf() - 0.5) * 0.5
			var rr := radius * (0.38 + 0.12 * float(attempt % 4) * 0.5)
			var p := center + Vector2(cos(ang), sin(ang)) * rr
			if not on_paint.call(p):
				continue
			var yaw: int = yaw_toward.call(p, center)
			var res := placement.evaluate(_prop_spec("market_stall"), p, yaw, {"skip_access": true})
			if res.ok:
				placement.commit(res, {})
				items.append({"kind": "prop", "id": "market_stall", "res": res, "role": "étal"})
				placed = true
				break
			else:
				fails[String(res.reasons[0]) if not res.reasons.is_empty() else "?"] = int(fails.get(String(res.reasons[0]) if not res.reasons.is_empty() else "?", 0)) + 1
		if not placed:
			pass
	# --- petits objets près des étals (une caisse ou des tonneaux par étal)
	var stalls := items.duplicate()
	for k in stalls.size():
		var sp: Vector3 = (stalls[k]["res"] as PlacementResult).pos
		for attempt in 8:
			var ang2 := rng.randf() * TAU
			var p2 := Vector2(sp.x, sp.z) + Vector2(cos(ang2), sin(ang2)) * (1.9 + 0.2 * float(attempt))
			if not on_paint.call(p2):
				continue
			var pid: String = "crate_stack" if (k + seed) % 2 == 0 else "barrel_set"
			var res2 := placement.evaluate(_prop_spec(pid), p2, int(rng.randi() % 4), {"skip_access": true})
			if res2.ok:
				placement.commit(res2, {})
				items.append({"kind": "prop", "id": pid, "res": res2, "role": "caisses" if pid == "crate_stack" else "tonneaux"})
				break
	# --- végétation : arbres sur le pourtour de la zone
	var tree_n := 0
	for k in n_tree:
		for attempt in 16:
			var ang3 := rng.randf() * TAU
			var p3 := center + Vector2(cos(ang3), sin(ang3)) * radius * rng.randf_range(0.62, 0.95)
			if not on_paint.call(p3):
				continue
			var sp_name: String = COMPOSITION_TREES[rng.randi() % COMPOSITION_TREES.size()]
			var top := prepare_tree(p3, sp_name, int(rng.randi() % 100000))
			if bool(top["ok"]):
				placement.commit(top["res"], {})
				(top["item"] as Dictionary)["item"] = (top["res"] as PlacementResult).item_index
				items.append({"kind": "tree", "op": top, "role": "arbre"})
				tree_n += 1
				break
	op["items"] = items
	var counts := {"étal": 0, "caisses": 0, "tonneaux": 0, "arbre": 0}
	for it in items:
		counts[String(it["role"])] += 1
	op["counts"] = counts
	op["center"] = center
	op["area_m2"] = area
	op["summary"] = "Marché + végétation : %d étal(s), %d caisses, %d tonneaux, %d arbre(s) sur %.0f m²" % [counts["étal"], counts["caisses"], counts["tonneaux"], counts["arbre"], area]
	if items.is_empty():
		var why := "aucun emplacement libre sur les colonnes peintes"
		if not fails.is_empty():
			why = String(fails.keys()[0])
		op["reasons"] = ["Aucun objet n'a pu être posé dans cette zone (%s). Agrandissez la zone, choisissez un sol plus plat ou moins d'objets." % why]
	else:
		op["ok"] = true
	if keep_state and op["ok"]:
		op["snap"] = snap
	else:
		restore(snap)
	return op

## Nœud 3D d'un objet de composition (aperçu et application).
func composition_node(it: Dictionary, apply_body: StaticBody3D = null) -> Node3D:
	if String(it["kind"]) == "tree":
		var top: Dictionary = it["op"]
		var n: Node3D = (top["node_fn"] as Callable).call()
		if apply_body != null:
			AuthoredIslandView.add_tree(apply_body, top["item"])
		return n
	var id: String = it["id"]
	var res: PlacementResult = it["res"]
	var info := AssetLibrary.info(id)
	var xf := res.asset_transform()
	xf.origin.y -= float(info.get("ground_y", 0.0))
	var node := AssetLibrary.instantiate(id)
	AuthoredIslandView.strip_asset_collisions(node)
	node.transform = xf
	if apply_body != null:
		for c in info.get("colliders", []):
			var pos: Array = c["position"]
			var size: Array = c["size"]
			AuthoredIslandView._box(apply_body, AABB(Vector3(float(pos[0]), float(pos[1]), float(pos[2])), Vector3(float(size[0]), float(size[1]), float(size[2]))), xf)
	return node

# ------------------------------------------------------------------ application et annulation

func apply(op: Dictionary) -> Dictionary:
	if busy:
		return {"ok": false, "reason": "Une opération est déjà en cours."}
	busy = true
	var result := await _apply(op)
	busy = false
	return result

func _apply(op: Dictionary) -> Dictionary:
	var fresh := op
	if int(op.get("version", -1)) != version:
		# l'état a changé depuis l'aperçu : on recalcule (mêmes paramètres)
		fresh = _reprepare(op)
	if not bool(fresh.get("ok", false)):
		return {"ok": false, "reason": "; ".join(fresh.get("reasons", ["Refusé."]))}
	var snap := snapshot()
	var entry := {"kind": fresh["kind"], "snap": snap, "nodes": [], "recipe": op.get("recipe", {}), "summary": String(fresh.get("summary", fresh["kind"]))}
	_counter += 1
	match String(fresh["kind"]):
		"tree", "rock":
			var res: PlacementResult = fresh["res"]
			placement.commit(res, {})
			var it: Dictionary = fresh["item"]
			it["item"] = res.item_index
			var body := StaticBody3D.new()
			body.name = "Collision_%d" % _counter
			body.collision_layer = 1
			body.collision_mask = 0
			objects_root.add_child(body)
			if fresh["kind"] == "tree":
				AuthoredIslandView.add_tree(body, it)
			else:
				AuthoredIslandView.add_rock(body, it, occ)
			var node: Node3D = (fresh["node_fn"] as Callable).call()
			node.name = "%s_%d" % [fresh["kind"], _counter]
			objects_root.add_child(node)
			entry["nodes"] = [node, body]
			entry["changed_rect"] = Rect2i()
		"house":
			var t := prepare_house(fresh["rect_m"], fresh["params"], true)     # rejoue la transaction et GARDE le terrain
			if not bool(t["ok"]):
				restore(snap)
				return {"ok": false, "reason": "; ".join(t["reasons"])}
			var res: PlacementResult = t["res"]
			placement.commit(res, {"owner": t["owner"]})
			var rec := {"type": t["type"], "plan": t["plan"], "model": t["model"], "arrays": t["arrays"], "res": res, "xform": t["xform"],
				"door": t["door"], "id": "maison_%d" % _counter}
			var node := BuildingView.create_node(t["model"], t["arrays"], [30.0, 80.0])
			node.transform = t["xform"]
			node.name = rec["id"]
			objects_root.add_child(node)
			var body := StaticBody3D.new()
			body.name = "Collision_%d" % _counter
			body.collision_layer = 1
			body.collision_mask = 0
			objects_root.add_child(body)
			AuthoredIslandView.add_building(body, rec)
			entry["nodes"] = [node, body]
			entry["changed_rect"] = t["changed_rect"]
			entry["record"] = rec
			fresh = t
		"dwelling":
			var td := prepare_dwelling(fresh["rect_m"], fresh["params"], true)     # rejoue la transaction et GARDE le terrain
			if not bool(td["ok"]):
				restore(snap)
				return {"ok": false, "reason": "; ".join(td["reasons"])}
			var owner_d := occ.new_owner()
			occ.reserve(td["yard"], PlacementSpec.TAG_ROAD, owner_d)
			occ.reserve(td["rect"], PlacementSpec.TAG_PLOT, owner_d)
			var dnode := ConstructionView.create(td["model"], {"collide": true})
			dnode.transform = td["xform"]
			dnode.name = "habitation_%d" % _counter
			objects_root.add_child(dnode)
			entry["nodes"] = [dnode]
			entry["changed_rect"] = td["changed_rect"]
			entry["record"] = {"model": td["model"], "pos": td["pos"], "yaw": td["yaw"], "ground_m": td["ground_m"]}
			fresh = td
		"composition":
			var tc := prepare_composition(fresh["cells"], fresh["params"], true)
			if not bool(tc["ok"]):
				restore(snap)
				return {"ok": false, "reason": "; ".join(tc["reasons"])}
			var cbody := StaticBody3D.new()
			cbody.name = "Collision_%d" % _counter
			cbody.collision_layer = 1
			cbody.collision_mask = 0
			objects_root.add_child(cbody)
			var cnodes: Array = [cbody]
			for it in tc["items"]:
				var cn := composition_node(it, cbody)
				cn.name = "compo_%d_%d" % [_counter, cnodes.size()]
				objects_root.add_child(cn)
				cnodes.append(cn)
			entry["nodes"] = cnodes
			entry["changed_rect"] = Rect2i()
			entry["record"] = {"items": (tc["items"] as Array).size()}
			fresh = tc
		"flatten":
			var target: int = fresh["target"]
			var cells_changed := 0
			for i in fresh["land"]:
				var cx: int = int(i) % field.n
				var cz: int = int(i) / field.n
				if field.set_top(cx, cz, target):
					cells_changed += 1
			var lo := Vector2i(field.n, field.n)
			var hi := Vector2i(-1, -1)
			for i in fresh["land"]:
				lo = Vector2i(mini(lo.x, int(i) % field.n), mini(lo.y, int(i) / field.n))
				hi = Vector2i(maxi(hi.x, int(i) % field.n), maxi(hi.y, int(i) / field.n))
			entry["changed_rect"] = Rect2i(lo, hi - lo + Vector2i.ONE)
			entry["cells_changed"] = cells_changed
	var cr: Rect2i = entry["changed_rect"]
	if cr.size.x > 0:
		await rebuild_rect(cr)
	stack.append(entry)
	version += 1
	changed.emit(fresh, "applique")
	return {"ok": true, "reason": "", "op": fresh, "entry": entry}

func _reprepare(op: Dictionary) -> Dictionary:
	match String(op["kind"]):
		"tree": return prepare_tree(op["pos"], op["species"], int(op["seed"]))
		"rock": return prepare_rock(op["pos"], op["family"], int(op["seed"]), float(op.get("scale", 1.0)))
		"house": return prepare_house(op["rect_m"], op["params"])
		"flatten": return prepare_flatten(op["cells"], op["params"])
		"dwelling": return prepare_dwelling(op["rect_m"], op["params"])
		"composition": return prepare_composition(op["cells"], op["params"])
	return op

func can_undo() -> bool:
	return not stack.is_empty() and not busy

## Annule la dernière opération ENTIÈRE : objets, réservations, relief et raccord au sol.
func undo() -> Dictionary:
	if busy or stack.is_empty():
		return {"ok": false, "reason": "Rien à annuler."}
	busy = true
	var e: Dictionary = stack.pop_back()
	var cr: Rect2i = e["changed_rect"]
	restore(e["snap"])
	for n in e["nodes"]:
		if is_instance_valid(n):
			(n as Node).get_parent().remove_child(n)
			(n as Node).queue_free()
	if cr.size.x > 0:
		await rebuild_rect(cr)
	version += 1
	busy = false
	changed.emit(e, "annule")
	return {"ok": true, "reason": "", "entry": e}

## Résumé lisible d'une opération préparée (aperçu).
static func describe(op: Dictionary) -> String:
	match String(op.get("kind", "")):
		"house":
			if not op.has("plan"):
				return ""
			var fp: Vector2 = op.get("footprint_m", Vector2.ZERO)
			return "Maison %s · emprise bâtie %.1f × %.1f m · niveau fini %.2f m · déblai %d / remblai %d cellules · %d colonnes de sol raccordées" % [
				"(cabane)" if op.get("type", "") == "hut" else "simple", fp.x, fp.y, float(op.get("target_m", 0.0)), int(op.get("cut_cells", 0)), int(op.get("fill_cells", 0)), int(op.get("terrain_cells", 0))]
		"dwelling":
			if not op.has("gen") or not bool((op["gen"] as Dictionary)["ok"]):
				return ""
			var ev: Dictionary = op.get("eval", {})
			return "%s\nTerrain : niveau fini %.2f m · déblai %d / remblai %d cellules · %d colonnes de sol raccordées" % [DwellingGenerator.describe(op["gen"]), float(op.get("ground_m", 0.0)), int(op.get("cut_cells", 0)), int(op.get("fill_cells", 0)), int(op.get("terrain_cells", 0))]
		"composition":
			return String(op.get("summary", ""))
		"flatten":
			return "Aplanir à %.2f m · %d colonnes · déblai max %.2f m · remblai max %.2f m" % [float(op.get("target_m", 0.0)), (op.get("land", []) as Array).size(), float(op.get("cut_max_m", 0.0)), float(op.get("fill_max_m", 0.0))]
	return String(op.get("summary", ""))
