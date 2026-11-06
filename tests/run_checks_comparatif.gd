extends SceneTree
## Comparatif de génération du terrain (A actuel · B FastNoiseLite · S = squelette pour C) — sans rendu :
##   godot --headless -s tests/run_checks_comparatif.gd
## Les contrôles de C (Voxel Tools) exigent le moteur qui embarque le module : tools/comparatif_terrain.gd (mode verif).
var ok := 0
var ko := 0

func check(cond: bool, label: String) -> void:
	if cond:
		ok += 1
		print("  OK    ", label)
	else:
		ko += 1
		print("  ÉCHEC ", label)

func _initialize() -> void:
	print("== Comparatif de génération du terrain ==")
	for seed in [21, 7]:
		var plan := PlanGenerator.generate(seed, 56, 48)
		var bA := PlanTerrain.build(plan, {"method": "A"})
		var bB := PlanTerrain.build(plan, {"method": "B"})
		var bS := PlanTerrain.build(plan, {"method": "S"})
		var bB2 := PlanTerrain.build(PlanGenerator.generate(seed, 56, 48), {"method": "B"})
		check(PlanTerrain.fingerprint(bB.field) == PlanTerrain.fingerprint(bB2.field), "graine %d : méthode B reproductible" % seed)
		check(PlanTerrain.fingerprint(bA.field) != PlanTerrain.fingerprint(bB.field), "graine %d : B diffère de A (relief enrichi)" % seed)
		check(bA.field.n == bB.field.n and bA.field.n == bS.field.n and bA.field.origin == bB.field.origin, "graine %d : même grille pour A, B et le squelette" % seed)
		# même plan : les colonnes de chemin et les zones plates (arrivée, plateau) sont identiques
		check(bA.path_cols == bB.path_cols and bA.path_cols == bS.path_cols, "graine %d : mêmes colonnes de chemin" % seed)
		for id in ["arrivee", "plateau"]:
			var z := plan.zone_by_id(id)
			var f_a := bA.field
			var f_b := bB.field
			var c := f_a.col_of_m((z["c"] as Vector2).x, (z["c"] as Vector2).y)
			check(f_a.top_at(c.x, c.y) == f_b.top_at(c.x, c.y), "graine %d : le centre de la zone « %s » est à la même hauteur (A = B)" % [seed, id])
		for m in [["A", bA], ["B", bB]]:
			var f: TerrainField = (m[1] as PlanTerrain.Build).field
			var reps := PlanTerrain.path_reports(plan, f)
			var all_ok := true
			for r in reps:
				all_ok = all_ok and bool(r["ok"])
			check(all_ok, "graine %d, méthode %s : chemins praticables (pente ≤ 30 %%, aucune marche ≥ 40 cm)" % [seed, m[0]])
			check(bool(PlanTerrain.start_report(plan, f)["ok"]), "graine %d, méthode %s : point de départ sûr" % [seed, m[0]])
		# B : amplitude plus grande que A, sans NO_GROUND créé
		var lo_a := 9999
		var hi_a := -9999
		var lo_b := 9999
		var hi_b := -9999
		var holes := 0
		for i in bA.field.top.size():
			if bA.field.top[i] == TerrainField.NO_GROUND:
				if bB.field.top[i] != TerrainField.NO_GROUND:
					holes += 1
				continue
			if bB.field.top[i] == TerrainField.NO_GROUND:
				holes += 1
				continue
			lo_a = mini(lo_a, bA.field.top[i])
			hi_a = maxi(hi_a, bA.field.top[i])
			lo_b = mini(lo_b, bB.field.top[i])
			hi_b = maxi(hi_b, bB.field.top[i])
		check(holes == 0, "graine %d : B garde exactement le même contour (aucune colonne gagnée ni perdue)" % seed)
		check(hi_b - lo_b > hi_a - lo_a, "graine %d : B a plus de dénivelé que A (%.1f m contre %.1f m)" % [seed, (hi_b - lo_b) * 0.2, (hi_a - lo_a) * 0.2])
		# squelette (C) : poids du détail nul sur le chemin
		var on_path := 0
		var bad := 0
		for i in bS.path_cols.size():
			if bS.path_cols[i] == 1:
				on_path += 1
				if bS.detail_w[i] > 0.001:
					bad += 1
		check(on_path > 0 and bad == 0, "graine %d : squelette — détail nul sur les %d colonnes de chemin" % [seed, on_path])
	# la méthode voyage avec la carte (v3) : enregistrement, réouverture, refus d'une méthode inconnue
	var p := PlanGenerator.generate(5, 56, 48)
	p.settings["method"] = "B"
	var d := p.to_dict()
	var back := IslandPlan.from_dict(d)
	check(back["ok"] and String((back["plan"] as IslandPlan).settings.get("method", "")) == "B", "la méthode B est conservée dans la carte")
	var b1 := PlanTerrain.build(p)
	var b2 := PlanTerrain.build(back["plan"] as IslandPlan)
	check(PlanTerrain.fingerprint(b1.field) == PlanTerrain.fingerprint(b2.field), "carte rouverte : même terrain (méthode lue dans la carte)")
	d["settings"]["method"] = "Z"
	check(not IslandPlan.from_dict(d)["ok"], "méthode inconnue : carte refusée avec explication")
	var old := PlanGenerator.generate(5, 56, 48).to_dict()
	check(IslandPlan.from_dict(old)["ok"] and not (old["settings"] as Dictionary).has("method"), "carte sans méthode (avant ce lot) : rouverte, méthode A par défaut")
	print("== %d réussite(s), %d échec(s) ==" % [ok, ko])
	quit(1 if ko > 0 else 0)
