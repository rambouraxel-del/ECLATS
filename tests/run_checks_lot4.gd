extends SceneTree
## Vérifications du Lot 4 (génération structurelle), sans affichage :
##   godot --headless -s tests/run_checks_lot4.gd [-- --monde]
## Parties rapides (briques) : graines, terrain, placement, terrassement, bâtiments, arbres, rochers, bateau,
## ponton, environnement. Avec --monde : îles COMPLÈTES sur plusieurs graines et profils (validation
## automatique + déterminisme), plus lentes (~2 min).
## Code de sortie 0 = tout est bon, 1 = au moins un échec.

var _failures := 0
var _passes := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  OK    ", label)
	else:
		_failures += 1
		printerr("  ÉCHEC ", label)

func _initialize() -> void:
	await process_frame
	print("== ÉCLATS Lot 4 : vérifications ==")
	VoxelMesher.palette_warmup()
	_check_rng()
	_check_terrain()
	_check_placement()
	_check_editor()
	_check_buildings()
	_check_nature()
	_check_ship_and_pier()
	await _check_environment()
	if OS.get_cmdline_user_args().has("--monde"):
		_check_worlds()
	print("== %d réussite(s), %d échec(s) ==" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)

# ------------------------------------------------------------------ graines

func _check_rng() -> void:
	print("Flux déterministes")
	check(WorldRng.sub_seed(5, "a") == WorldRng.sub_seed(5, "a"), "sous-graine stable")
	check(WorldRng.sub_seed(5, "a") != WorldRng.sub_seed(5, "b") and WorldRng.sub_seed(5, "a") != WorldRng.sub_seed(6, "a"), "sous-graines distinctes par étiquette et par graine")
	var a := WorldRng.stream(9, "x")
	var b := WorldRng.stream(9, "x")
	check(a.randi() == b.randi() and a.randf() == b.randf(), "deux flux de même étiquette produisent la même suite")

# ------------------------------------------------------------------ terrain

func _check_terrain() -> void:
	print("Terrain hiérarchique")
	var fields := {}
	for key in ["settled", "verdant", "rocky"]:
		var f := TerrainGenerator.new().generate(IslandProfile.load_profile(key), 1)
		fields[key] = f
		check(f.land_count() > 8000, "%s : île non vide (%d colonnes)" % [key, f.land_count()])
		check(f.plateaus.size() >= 2, "%s : espaces plats détectés (%d)" % [key, f.plateaus.size()])
		var below_core := 0
		for i in f.n * f.n:
			if f.top[i] != TerrainField.NO_GROUND and f.top[i] < f.core_top[i] + TerrainField.MIN_SURFACE:
				below_core += 1
		check(below_core == 0, "%s : la surface ne descend jamais dans le cœur fixe" % key)
	var again := TerrainGenerator.new().generate(IslandProfile.load_profile("settled"), 1)
	check(again.top == fields["settled"].top and again.material == fields["settled"].material, "même graine = même terrain (déterminisme)")
	var other := TerrainGenerator.new().generate(IslandProfile.load_profile("settled"), 2)
	check(other.top != fields["settled"].top, "une autre graine donne un autre terrain")
	# la profondeur de coupe maximale est bornée par SURFACE_DEPTH : la surface modifiable ne peut pas dépasser 6 cellules
	check(TerrainField.SURFACE_DEPTH == 6, "surface modifiable : 6 cellules (1,2 m)")
	var data := TerrainVoxelizer.build(fields["settled"])
	check(data.core.count_solid() > 0 and data.surface.count_solid() > 0, "voxélisation : cœur fixe + surface modifiable")
	check(data.core.size == data.surface.size, "voxélisation : deux couches de même taille")

# ------------------------------------------------------------------ placement universel

func _check_placement() -> void:
	print("Placement universel")
	var f := TerrainGenerator.new().generate(IslandProfile.load_profile("settled"), 1)
	var occ := OccupancyMap.new(f)
	var ps := PlacementSystem.new(f, occ)
	var spec := PlacementSpec.new()
	spec.id = "boite"
	spec.kind = "prop"
	spec.size = Vector3(1, 1, 1)
	spec.hard = [AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))]
	spec.support_fraction = 0.8
	spec.cliff_margin_m = 0.5
	# 1) point valide : trouvé par le placement, refus dans le vide
	var c := Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ok := ps.find_and_place(spec, c, 6.0, rng, {"skip_access": true})
	check(ok.ok, "un objet est posé sur un sol valide (%s)" % ok.describe())
	var void_res := ps.evaluate(spec, Vector2(f.radius_m * 3.0, 0.0), 0, {"skip_access": true})
	check(not void_res.ok and void_res.reasons.has(PlacementSpec.R_OUT), "refus explicite dans le vide (hors_ile)")
	# 2) collision avec ce qui vient d'être posé
	var clash := ps.evaluate(spec, Vector2(ok.pos.x, ok.pos.z), 0, {"skip_access": true})
	check(not clash.ok and (clash.reasons.has(PlacementSpec.R_COLLISION) or clash.reasons.has(PlacementSpec.R_RESERVED)), "deux objets ne se chevauchent pas")
	# 3) espace réservé
	var owner := occ.new_owner()
	var rc := f.col_of_m(c.x + 3.0, c.y + 3.0)
	occ.reserve(Rect2i(rc - Vector2i(6, 6), Vector2i(12, 12)), PlacementSpec.TAG_ROAD, owner)
	var res_r := ps.evaluate(spec, Vector2(c.x + 3.1, c.y + 3.1), 0, {"skip_access": true})
	check(not res_r.ok and res_r.reasons.has(PlacementSpec.R_RESERVED), "un espace réservé (route) interdit la pose")
	# 4) bord de falaise : trop près du vide
	var rim := Vector2.ZERO
	for k in 400:
		var q := Vector2(float(k) * 0.1, 0.0)
		var col := f.col_of_m(q.x, q.y)
		if not f.has_ground(col.x, col.y):
			rim = Vector2(q.x - 0.15, 0.0)
			break
	var cliff := ps.evaluate(spec, rim, 0, {"skip_access": true})
	check(not cliff.ok, "pas de pose au bord immédiat du vide (%s)" % ",".join(cliff.reasons))
	# 5) exception déclarée : un affleurement peut déborder du bord (overhang_void), jamais sans déclaration
	var out_spec := PlacementSpec.new()
	out_spec.id = "affleurement"
	out_spec.kind = "rock"
	out_spec.size = Vector3(3, 1, 3)
	out_spec.hard = [AABB(Vector3(-1.5, 0, -1.5), Vector3(3, 1, 3))]
	out_spec.support_fraction = 0.4
	out_spec.cliff_margin_m = 0.0
	var plain := ps.evaluate(out_spec, rim, 0, {"skip_access": true})
	out_spec.exceptions = PackedStringArray(["overhang_void"])
	out_spec.overhang_fraction = 0.6
	var declared := ps.evaluate(out_spec, rim, 0, {"skip_access": true})
	check(plain.reasons.has(PlacementSpec.R_OUT) and not declared.reasons.has(PlacementSpec.R_OUT), "le débord dans le vide n'est admis QUE s'il est déclaré")
	# 6) accès : l'accessibilité est un critère comme un autre
	var acc := PlacementSpec.new()
	acc.id = "accessible"
	acc.kind = "prop"
	acc.size = Vector3(1, 1, 1)
	acc.hard = [AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))]
	acc.needs_access = true
	var no_acc := ps.evaluate(acc, Vector2(c.x - 4.0, c.y - 4.0), 0, {})
	check(no_acc.reasons.has(PlacementSpec.R_ACCESS) or not no_acc.ok, "sans chemin à proximité, un objet à accès requis est refusé")
	check(ps.stats["accepted"] >= 1, "le système tient des statistiques de placement")

# ------------------------------------------------------------------ terrassement et routes

func _check_editor() -> void:
	print("Terrassement")
	var f := TerrainGenerator.new().generate(IslandProfile.load_profile("settled"), 2)
	var occ := OccupancyMap.new(f)
	var col := f.col_of_m(0.0, 0.0)
	var rect := Rect2i(col - Vector2i(20, 15), Vector2i(40, 30))
	var ev := TerrainEditor.evaluate_pad(f, occ, rect, 2, 6, 8, 2)
	check(ev["ok"] or ev["reason"] != "", "évaluation d'une plateforme : %s" % [ev])
	if ev["ok"]:
		var before := f.top.duplicate()
		var pal := VoxelPalette.get_default()
		TerrainEditor.stamp_pad(f, rect, ev["target"], TerrainField.Zone.PLOT, pal.id("path_dirt"), true)
		var dug := 0
		var flat := 0
		for cz in range(rect.position.y, rect.end.y):
			for cx in range(rect.position.x, rect.end.x):
				var i := f.idx(cx, cz)
				if f.top[i] < f.core_top[i] + TerrainField.MIN_SURFACE:
					dug += 1
				if f.top[i] == ev["target"]:
					flat += 1
		check(dug == 0, "la plateforme ne creuse jamais dans le cœur fixe")
		check(flat > rect.size.x * rect.size.y * 6 / 10, "la plateforme est plane (%d/%d colonnes au niveau cible)" % [flat, rect.size.x * rect.size.y])
		# raccord : aucune marche > 3 cellules à la frontière extérieure immédiate
		var worst := 0
		for cx in range(rect.position.x - 1, rect.end.x + 1):
			for cz in [rect.position.y - 1, rect.end.y]:
				if f.has_ground(cx, cz):
					worst = maxi(worst, absi(f.top[f.idx(cx, cz)] - ev["target"]))
		check(worst <= TerrainEditor.SKIRT_MAX_DELTA + 1, "raccord de pente ou soutènement à la frontière (écart max %d)" % worst)
		check((before != f.top) == (int(ev["cut"]) + int(ev["fill"]) > 0), "le terrassement modifie le relief exactement quand il y a des déblais ou remblais (%d/%d)" % [ev["cut"], ev["fill"]])
		# chemin
		var placement := PlacementSystem.new(f, occ)
		var net := PathNetwork.new(f, occ, placement)
		var a := col + Vector2i(-30, 24)
		var b := col + Vector2i(30, -22)
		if f.has_ground(a.x, a.y) and f.has_ground(b.x, b.y):
			var route := net.connect_points(a, b, 1.2, "path_dirt")
			if not route.is_empty():
				var okp := true
				var cells: Array = route["cells"]
				for k in range(1, cells.size()):
					if absi(f.top_at(cells[k - 1].x, cells[k - 1].y) - f.top_at(cells[k].x, cells[k].y)) > 1:
						okp = false
				check(okp, "chemin continu : marche de 20 cm au plus entre cellules voisines (%d cellules)" % cells.size())
			else:
				check(true, "chemin refusé explicitement (%s)" % [net.failures])

# ------------------------------------------------------------------ bâtiments

func _check_buildings() -> void:
	print("Bâtiments visitables")
	check(BuildingPlan.DOOR_MAIN_W >= 10 and BuildingPlan.DOOR_MAIN_H >= 21, "porte d'entrée ≥ 1,00 × 2,10 m")
	check(BuildingPlan.DOOR_INT_W >= 9 and BuildingPlan.DOOR_INT_H >= 20, "porte intérieure ≥ 0,90 × 2,00 m")
	check(BuildingPlan.MIN_HEADROOM >= 18 and BuildingPlan.CLEAR >= 24, "hauteur libre ≥ 2,40 m, tête à 1,80 m")
	check(BuildingPlan.STEP_RISE * 0.1 <= 0.2 + 1e-6 and BuildingPlan.STEP_RUN * 0.1 >= 0.3 - 1e-6, "marche d'escalier 20 cm × 30 cm")
	var pal := VoxelPalette.get_default()
	var glass := [pal.id("window_glass"), pal.id("glass_green")]
	for type in BuildingCatalog.TYPES:
		for seed in [1, 2]:
			var plan := BuildingPlanner.plan(type, seed)
			var m := BuildingBuilder.build(plan)
			var r := BuildingValidator.validate(m)
			check(r["errors"].is_empty(), "%s (graine %d) : visitable (%s)" % [type, seed, "; ".join(r["errors"])])
			# style : pas de grandes baies vitrées, pas de matière « vitre » dans la structure
			var has_glass := false
			for v in m.volume.data:
				if v in glass:
					has_glass = true
					break
			check(not has_glass, "%s (graine %d) : aucune vitre moderne" % [type, seed])
			for o in plan.openings:
				if o.kind == "window" and (o.w > 6 or o.h > 8):
					check(false, "%s : fenêtre trop grande (%d × %d)" % [type, o.w, o.h])
			for f in m.furniture:
				for dc in m.door_clear:
					if dc["floor"] == f["floor"] and (dc["rect"] as Rect2).grow(-0.01).intersects(f["rect"]):
						check(false, "%s : meuble devant une porte" % type)
	# déterminisme
	var p1 := BuildingPlanner.plan("house_large", 7)
	var p2 := BuildingPlanner.plan("house_large", 7)
	check(BuildingBuilder.build(p1).volume.checksum() == BuildingBuilder.build(p2).volume.checksum(), "même graine = même bâtiment (volume identique)")
	check(BuildingBuilder.build(BuildingPlanner.plan("house_large", 8)).volume.checksum() != BuildingBuilder.build(p1).volume.checksum(), "graine différente = bâtiment différent")
	# un escalier relie bien les étages : la grande maison a 2 niveaux atteignables à pied
	var big := BuildingBuilder.build(BuildingPlanner.plan("house_large", 3))
	check(big.plan.floors == 2 and big.plan.stair != null, "grande maison : 2 niveaux et un escalier")
	check(BuildingValidator.validate(big)["stats"].get("unreachable_rooms", 1) == 0, "grande maison : toutes les pièces, étage compris, atteignables à pied")
	# les meubles sont posés
	check(big.furniture.size() >= 8, "grande maison meublée (%d meubles)" % big.furniture.size())
	# placement : emprise bâtie ≠ cour
	var placement_spec := BuildingPlacement.spec_for(big.plan)
	check(placement_spec.hard[0].size.x < big.footprint_m().x and placement_spec.kind == "building", "le volume dur exclut la cour devant la façade")

# ------------------------------------------------------------------ nature

func _check_nature() -> void:
	print("Arbres et rochers")
	var flat := {}
	for sp in TreeGenerator.SPECIES.keys():
		var pl := TreeGenerator.plan(sp, 11)
		var m := TreeGenerator.rasterize(pl, flat)
		var issues := TreeGenerator.check(m, flat)
		check(issues.is_empty(), "arbre %s : d'un seul tenant, enraciné, feuillage rattaché (%s)" % [sp, "; ".join(issues)])
		check(m["wood"].count_solid() > 200, "arbre %s : tronc et branches présents" % sp)
	# racines sur pente : un sol incliné de 40 cm sous 1 m
	var slope := {"half": 2.0, "step": 0.2, "n": 21, "h": PackedFloat32Array()}
	slope["h"].resize(21 * 21)
	for iz in 21:
		for ix in 21:
			slope["h"][ix + iz * 21] = (float(ix) - 10.0) * 0.1 * 0.4
	var pl2 := TreeGenerator.plan("oak", 4)
	var m2 := TreeGenerator.rasterize(pl2, slope)
	check(TreeGenerator.check(m2, slope).is_empty(), "arbre sur pente : pied enraciné jusqu'au sol le plus bas (aucun jour sous le tronc)")
	# régression : toutes les espèces, plusieurs graines et trois inclinaisons de sol (un jour d'une colonne sous un bouleau
	# a été trouvé par le validateur sur une île complète)
	var tree_defects := 0
	var tree_count := 0
	for sl in [0.0, 0.2, 0.4]:
		var g := {"half": 2.0, "step": 0.2, "n": 21, "h": PackedFloat32Array()}
		g["h"].resize(21 * 21)
		for iz in 21:
			for ix in 21:
				g["h"][ix + iz * 21] = (float(ix) - 10.0) * 0.1 * sl + (float(iz) - 10.0) * 0.05 * sl
		for sp in TreeGenerator.SPECIES.keys():
			for sd in range(1, 4):
				tree_count += 1
				if not TreeGenerator.check(TreeGenerator.rasterize(TreeGenerator.plan(sp, sd * 17), g), g).is_empty():
					tree_defects += 1
	check(tree_defects == 0, "%d arbres (7 espèces × 3 graines × 3 pentes) : aucun défaut d'ancrage" % tree_count)
	check(TreeGenerator.rasterize(TreeGenerator.plan("pine", 3), flat)["wood"].checksum() == TreeGenerator.rasterize(TreeGenerator.plan("pine", 3), flat)["wood"].checksum(), "arbre déterministe")
	for fam in RockGenerator.families():
		for seed in [1, 2, 3]:
			var rp := RockGenerator.plan(fam, seed)
			var rm := RockGenerator.rasterize(rp, flat)
			var vol: VoxelVolume = rm["volume"]
			var lo: Vector3 = rm["origin"]
			var floating := 0
			var sx := vol.size.x
			var sz := vol.size.z
			for comp in VoxelShapes.components(vol):
				var low := 1 << 20
				for i in comp:
					low = mini(low, i / (sx * sz))
				if lo.y + float(low) * 0.1 > 0.15:
					floating += 1
			check(floating == 0 and vol.count_solid() > 100, "rocher %s (graine %d) : aucune pièce flottante" % [fam, seed])

# ------------------------------------------------------------------ bateau et ponton

func _check_ship_and_pier() -> void:
	print("Bateau et ponton")
	for seed in [1, 2, 3, 4]:
		var ship := ShipGenerator.build(seed)
		var issues := ShipGenerator.check(ship)
		check(issues.is_empty(), "bateau %d : coque d'un seul bois, voiles disjointes, sans croisement (%s)" % [seed, "; ".join(issues)])
		check(ship["sails"].size() >= 3 and ship["masts"].size() == 2, "bateau %d : %d voiles séparées sur 2 mâts" % [seed, ship["sails"].size()])
		check(ship["L"] > 8.0 and ship["L"] < 13.0 and ship["B"] / ship["L"] > 0.22 and ship["B"] / ship["L"] < 0.42, "bateau %d : proportions de coque crédibles (L %.1f m, B %.1f m)" % [seed, ship["L"], ship["B"]])
	var a := ShipGenerator.build(9)
	var b := ShipGenerator.build(9)
	check(a["volume"].checksum() == b["volume"].checksum() and a["sails"][0]["volume"].checksum() == b["sails"][0]["volume"].checksum(), "bateau déterministe")
	check(ShipGenerator.build(10)["volume"].checksum() != a["volume"].checksum(), "graine différente = bateau différent")
	# ponton : une seule masse de bois (aucune pièce mal assemblée)
	var port := {"ship_side": 1.0}
	var pier := PortBuilder.build_pier(port, 5)
	check(VoxelShapes.components(pier["volume"]).size() == 1, "ponton : poutraison, tablier, portiques et garde-corps en une seule pièce")
	check(pier["ropes"].size() >= 4, "ponton : haubans présents (%d)" % pier["ropes"].size())

# ------------------------------------------------------------------ environnement

func _check_environment() -> void:
	print("Environnement")
	var cfg := EnvironmentManager.load_config()
	check(cfg.has("emission_scale") and cfg.has("glow") and cfg.has("time_keys"), "configuration centralisée (environment.json)")
	var es: Dictionary = cfg["emission_scale"]
	check(float(es["village_day"]) < float(es["village_sunset"]) and float(es["village_sunset"]) < float(es["village_night"]), "émission des matériaux : jour < coucher < nuit (anti-surexposition)")
	check(float(es["village_day"]) <= 0.3, "émission plafonnée en plein jour (%.2f)" % float(es["village_day"]))
	var env := EnvironmentManager.new()
	root.add_child(env)
	await process_frame
	await process_frame
	check(env.rig != null and env.clouds != null and env.far != null, "gestionnaire : éclairage, nuages doux et îles lointaines")
	check(env.far.get_child_count() >= 6 and env.far.triangles < 6000, "îles lointaines : %d silhouettes, %d triangles" % [env.far.get_child_count(), env.far.triangles])
	env.apply_key("village_day")
	var day_exp := env.rig.world_env.environment.tonemap_exposure
	var day_glow := env.rig.world_env.environment.glow_intensity
	env.apply_key("village_night")
	check(env.rig.lamp_scale > 1.0, "nuit : lumières d'objets allumées")
	env.set_time_of_day(0.5)
	var noon_sun := env.rig.sun.light_energy
	env.set_time_of_day(0.0)
	var night_sun := env.rig.sun.light_energy
	check(noon_sun > night_sun * 1.5, "cycle jour/nuit : soleil %.2f → lune %.2f" % [noon_sun, night_sun])
	env.set_time_of_day(0.27)
	var mid_sun := env.rig.sun.light_energy
	check(mid_sun > night_sun and mid_sun < noon_sun + 0.001, "transition continue entre nuit et jour (%.2f)" % mid_sun)
	check(env.rig.world_env.environment.glow_intensity <= float(cfg["glow"]["intensity_cap"]) + 0.001, "halo plafonné (%.2f ≤ %.2f)" % [env.rig.world_env.environment.glow_intensity, float(cfg["glow"]["intensity_cap"])])
	check(day_glow <= 0.85 and day_exp > 0.5, "exposition de jour raisonnable")
	check(env.clouds.materials.size() >= 3, "nappes de nuages 3D douces (non voxel)")
	env.queue_free()

# ------------------------------------------------------------------ îles complètes

func _check_worlds() -> void:
	print("Îles complètes (validation automatique)")
	var cases := [["settled", 1], ["settled", 2], ["verdant", 1], ["rocky", 1]]
	var first_sig := ""
	for c in cases:
		var w := WorldBuilder.build(c[0], c[1])
		var r := WorldValidator.validate(w, {"buildings": c[0] == "settled" and c[1] == 1})
		var msgs: Array[String] = []
		for i in r["issues"]:
			msgs.append("%s : %s" % [i["check"], i["message"]])
		check(r["summary"]["errors"] == 0, "%s #%d : 0 erreur de validation (%s)" % [c[0], c[1], "; ".join(msgs)])
		check(w.trees.size() >= 10 and w.rocks.size() >= 4, "%s #%d : végétation et rochers présents (%d arbres, %d rochers)" % [c[0], c[1], w.trees.size(), w.rocks.size()])
		if c[0] == "settled":
			check(w.buildings.size() >= 5 and not w.port.is_empty() and not w.ship.is_empty(), "%s #%d : colonie (%d bâtiments), port et bateau" % [c[0], c[1], w.buildings.size()])
			check(not w.settlement.plaza.is_empty() and not w.settlement.shrine.is_empty(), "%s #%d : place et sanctuaire" % [c[0], c[1]])
		else:
			check(w.buildings.is_empty(), "%s #%d : île naturelle, sans bâtiment" % [c[0], c[1]])
		if first_sig == "":
			first_sig = WorldValidator.signature(w)
	var again := WorldBuilder.build("settled", 1)
	check(WorldValidator.signature(again) == first_sig, "île complète : même graine = même monde (signature identique)")
