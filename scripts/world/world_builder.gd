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
	var clock := [Time.get_ticks_msec()]      # tableau : une lambda ne modifie pas les variables capturées
	var lap := func(label: String) -> void:
		var now := Time.get_ticks_msec()
		w.timings[label] = now - int(clock[0])
		clock[0] = now
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
	# Les modèles (bâtiments, arbres, rochers, ponton, bateau) sont calculés par des fils d'exécution pendant que le
	# fil principal voxélise le terrain : les deux phases se recouvrent.
	var ctx := _start_models(w)
	w.island = TerrainVoxelizer.build(w.field)
	lap.call("voxelisation")
	_finish_models(w, ctx)
	lap.call("modeles")
	w.failures = w.settlement.failures.duplicate()
	w.props = w.settlement.props
	w.stats["placement"] = w.placement.stats
	w.stats["site_reasons"] = w.settlement.stats["site_reasons"]
	return w

## Un « travail » = un objet à modéliser. Chaque travail écrit uniquement dans son propre dictionnaire.
static func _start_models(w: WorldData) -> Dictionary:
	var jobs: Array[Dictionary] = []
	for b in w.settlement.buildings:
		jobs.append({"kind": "building", "src": b})
	if not w.settlement.port.is_empty():
		jobs.append({"kind": "ship", "seed": WorldRng.sub_seed(w.seed, "ship")})
		jobs.append({"kind": "pier", "port": w.settlement.port, "seed": w.seed})
	for t in w.trees:
		jobs.append({"kind": "tree", "src": t})
	for r in w.rocks:
		jobs.append({"kind": "rock", "src": r})
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		_run_job(jobs[i]),
		jobs.size(), -1, true, "Modèles")
	return {"task": task, "jobs": jobs, "t0": Time.get_ticks_msec()}

static func _run_job(job: Dictionary) -> void:
	match job["kind"]:
		"building":
			var model := BuildingBuilder.build(job["src"]["plan"])
			job["out"] = {"model": model, "arrays": BuildingView.make_arrays(model)}
		"ship":
			var ship := ShipGenerator.build(job["seed"])
			var parts := ShipView.parts(ship)
			ship["parts"] = parts
			ship["arrays"] = VoxelObjectView.make_arrays(parts)
			job["out"] = ship
		"pier":
			job["out"] = PortBuilder.build_pier(job["port"], job["seed"])
		"tree":
			var it: Dictionary = job["src"]
			var m := TreeGenerator.rasterize(it["plan"], it["ground"])
			it["model"] = m
			var parts: Array = [{"name": "wood", "volume": m["wood"], "origin": m["wood_origin"], "grid": TreeGenerator.C, "material": "props"}]
			if m["foliage"] != null:
				parts.append({"name": "leaves", "volume": m["foliage"], "origin": m["foliage_origin"], "grid": TreeGenerator.F, "material": "props"})
			it["parts"] = parts
			it["arrays"] = VoxelObjectView.make_arrays(parts)
		"rock":
			var it: Dictionary = job["src"]
			var m := RockGenerator.rasterize(it["plan"], it["ground"])
			it["model"] = m
			var parts: Array = [{"name": "rock", "volume": m["volume"], "origin": m["origin"], "grid": RockGenerator.C, "material": "props"}]
			it["parts"] = parts
			it["arrays"] = VoxelObjectView.make_arrays(parts)

static func _finish_models(w: WorldData, ctx: Dictionary) -> void:
	WorkerThreadPool.wait_for_group_task_completion(ctx["task"])
	var port: Dictionary = w.settlement.port
	for job in ctx["jobs"]:
		match job["kind"]:
			"building":
				var b: Dictionary = (job["src"] as Dictionary).duplicate()
				b["model"] = job["out"]["model"]
				b["arrays"] = job["out"]["arrays"]
				w.buildings.append(b)
			"ship":
				w.ship = job["out"]
			"pier":
				port["pier"] = job["out"]
	if not port.is_empty():
		port["mooring"] = PortBuilder.moor(port, w.ship)
		w.port = port
	w.timings["modeles_threads"] = Time.get_ticks_msec() - int(ctx["t0"])

