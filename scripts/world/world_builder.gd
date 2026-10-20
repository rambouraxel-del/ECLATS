@tool
class_name WorldBuilder
extends RefCounted
## Orchestrateur de la génération d'une île. Pipeline déterministe (même profil + même graine = même île) :
##   1. terrain hiérarchique (silhouette → relief → plateaux → sous-face)
##   2. colonie : place, parcelles, routes, bâtiments, port, sanctuaire, potagers, décor
##   3. végétation, rochers, plantes (placement universel, zones et réservations respectées)
##   4. voxélisation du terrain final (cœur fixe + surface)
##   5. modèles de bâtiments, appontement, bateau (en parallèle)
##   6. validation (WorldValidator) — rapport lisible, aucun défaut silencieux
## Chaque phase est chronométrée (WorldData.timings).

static func build(profile_key: String, seed: int, opts := {}) -> WorldData:
	var w := WorldData.new()
	w.seed = seed
	var t0 := Time.get_ticks_msec()
	var lap := func(label: String) -> void:
		var now := Time.get_ticks_msec()
		w.timings[label] = now - t0
		t0 = now
	VoxelMesher.palette_warmup()
	w.profile = IslandProfile.load_profile(profile_key)
	var gen := TerrainGenerator.new()
	w.field = gen.generate(w.profile, seed)
	lap.call("terrain")
	w.occ = OccupancyMap.new(w.field)
	w.placement = PlacementSystem.new(w.field, w.occ)
	w.paths = PathNetwork.new(w.field, w.occ, w.placement)
	w.settlement = SettlementGenerator.new(w.field, w.occ, w.placement, w.paths, w.profile, seed)
	w.settlement.generate()
	lap.call("colonie")
	if not opts.get("no_nature", false):
		NatureGenerator.generate(w)
	lap.call("nature")
	if opts.get("no_models", false):
		w.failures = w.settlement.failures.duplicate()
		return w
	w.island = TerrainVoxelizer.build(w.field)
	lap.call("voxelisation")
	_build_models(w)
	lap.call("modeles")
	w.failures = w.settlement.failures.duplicate()
	w.props = w.settlement.props
	w.stats["placement"] = w.placement.stats
	w.stats["site_reasons"] = w.settlement.stats["site_reasons"]
	return w

## Modèles de bâtiments (volumes + maillages) calculés en parallèle : aucun nœud n'est touché.
static func _build_models(w: WorldData) -> void:
	var _t_models := Time.get_ticks_msec()
	var list: Array = w.settlement.buildings
	var out: Array = []
	out.resize(list.size())
	if list.size() > 0:
		var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
			var b: Dictionary = list[i]
			var model := BuildingBuilder.build(b["plan"])
			out[i] = {"model": model, "arrays": BuildingView.make_arrays(model)},
			list.size(), -1, true, "Bâtiments")
		WorkerThreadPool.wait_for_group_task_completion(task)
	for i in list.size():
		var b: Dictionary = list[i].duplicate()
		b["model"] = out[i]["model"]
		b["arrays"] = out[i]["arrays"]
		w.buildings.append(b)
	w.timings["modeles_batiments"] = Time.get_ticks_msec() - _t_models
	_build_nature_models(w)
	w.timings["modeles_nature"] = Time.get_ticks_msec() - _t_models - int(w.timings["modeles_batiments"])
	if not w.settlement.port.is_empty():
		var port: Dictionary = w.settlement.port
		port["pier"] = PortBuilder.build_pier(port, w.seed)
		w.ship = ShipGenerator.build(WorldRng.sub_seed(w.seed, "ship"))
		port["mooring"] = PortBuilder.moor(port, w.ship)
		w.port = port

## Arbres et rochers : rastérisation et maillages (3 niveaux de détail) en parallèle.
static func _build_nature_models(w: WorldData) -> void:
	var items: Array = []
	items.append_array(w.trees)
	items.append_array(w.rocks)
	if items.is_empty():
		return
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var it: Dictionary = items[i]
		var parts: Array = []
		if it["kind"] == "tree":
			var m := TreeGenerator.rasterize(it["plan"], it["ground"])
			it["model"] = m
			parts.append({"name": "wood", "volume": m["wood"], "origin": m["wood_origin"], "grid": TreeGenerator.C, "material": "props"})
			if m["foliage"] != null:
				parts.append({"name": "leaves", "volume": m["foliage"], "origin": m["foliage_origin"], "grid": TreeGenerator.F, "material": "props"})
		else:
			var m := RockGenerator.rasterize(it["plan"], it["ground"])
			it["model"] = m
			parts.append({"name": "rock", "volume": m["volume"], "origin": m["origin"], "grid": RockGenerator.C, "material": "props"})
		it["parts"] = parts
		it["arrays"] = VoxelObjectView.make_arrays(parts),
		items.size(), -1, true, "Nature")
	WorkerThreadPool.wait_for_group_task_completion(task)
