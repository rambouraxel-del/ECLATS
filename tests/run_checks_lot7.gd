extends SceneTree
## Contrôles ciblés du Lot 7 (sans rendu) : plan généré → terrain, déterminisme, chemins praticables, départ sûr,
## format de carte versionné, éditeur (pinceaux, masque, régénération, annulation, export / ouverture).
##   godot --headless -s tests/run_checks_lot7.gd
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
	_run.call_deferred()

func _run() -> void:
	print("== Lot 7 : du plan 2D à l'île 3D ==")
	_plan_checks()
	_terrain_checks()
	_format_checks()
	if FileAccess.file_exists("res://tests/lot7_editeur.gd"):
		var ed := load("res://tests/lot7_editeur.gd")
		await ed.run(self)
	print("\n%d contrôles réussis, %d échecs" % [ok, ko])
	quit(1 if ko > 0 else 0)

# ------------------------------------------------------------------ plan

func _plan_checks() -> void:
	var a := PlanGenerator.generate(42, 56, 48)
	var b := PlanGenerator.generate(42, 56, 48)
	check(a.to_json() == b.to_json(), "même graine, mêmes dimensions : même plan (JSON identique)")
	var c := PlanGenerator.generate(43, 56, 48)
	check(a.to_json() != c.to_json() and a.outline != c.outline, "graine différente : le plan varie (contour et zones)")
	var cz_a := a.zone_by_id("sommet")["c"] as Vector2
	var cz_c := c.zone_by_id("sommet")["c"] as Vector2
	check(cz_a.distance_to(cz_c) > 1.0 or (a.zone_by_id("plateau")["c"] as Vector2).distance_to(c.zone_by_id("plateau")["c"]) > 1.0, "les zones changent de place avec la graine")
	var d := PlanGenerator.generate(42, 80, 64)
	check(d.to_json() != a.to_json() and d.width == 80.0 and d.length == 64.0, "dimensions différentes : autre plan, aux dimensions demandées")
	var kinds := {}
	for z in a.zones:
		kinds[z["kind"]] = true
	check(kinds.has("arrivee") and kinds.has("plateau") and kinds.has("bois") and kinds.has("sommet"), "profil d'arrivée : arrivée, plateau, zone boisée, point haut")
	check(a.paths.size() == 3 and a.landmarks.size() >= 3, "trois chemins en chaîne et des repères : %d chemins, %d repères" % [a.paths.size(), a.landmarks.size()])
	var links_ok := true
	for p in a.paths:
		if a.zone_by_id(p["from"]).is_empty() or a.zone_by_id(p["to"]).is_empty():
			links_ok = false
		if (p["pts"][0] as Vector2).distance_to(a.zone_by_id(p["from"])["c"]) > 0.05 or (p["pts"][-1] as Vector2).distance_to(a.zone_by_id(p["to"])["c"]) > 0.05:
			links_ok = false
	check(links_ok, "chaque chemin est relié, à ses deux bouts, à une zone du plan (points de liaison)")
	# robustesse : plusieurs graines et formats, plan seul
	var bad: Array[String] = []
	var sizes := [Vector2(32, 32), Vector2(40, 60), Vector2(56, 48), Vector2(90, 70), Vector2(120, 120)]
	for sd in range(1, 41):
		for sz: Vector2 in sizes:
			var p := PlanGenerator.generate(sd, sz.x, sz.y)
			var pr := p.problems()
			if not pr.is_empty():
				bad.append("graine %d %s : %s" % [sd, sz, pr[0]])
			for i in p.zones.size():
				for j in range(i + 1, p.zones.size()):
					var za: Dictionary = p.zones[i]
					var zb: Dictionary = p.zones[j]
					if za["kind"] == "bois" and zb["kind"] == "bois":
						continue
					if (za["c"] as Vector2).distance_to(zb["c"]) < float(za["r"]) + float(zb["r"]) - 0.5:
						bad.append("graine %d %s : zones %s et %s se chevauchent" % [sd, sz, za["id"], zb["id"]])
	check(bad.is_empty(), "200 plans (40 graines × 5 formats) cohérents, sans chevauchement de zones%s" % ("" if bad.is_empty() else " — " + bad[0]))
	var pr_bad := IslandPlan.new()
	pr_bad.outline = [Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)]
	check(not pr_bad.problems().is_empty(), "un contour qui se croise est signalé")

# ------------------------------------------------------------------ terrain issu du plan

func _terrain_checks() -> void:
	var a := PlanGenerator.generate(42, 56, 48)
	var ba := PlanTerrain.build(a)
	var bb := PlanTerrain.build(PlanGenerator.generate(42, 56, 48))
	check(PlanTerrain.fingerprint(ba.field) == PlanTerrain.fingerprint(bb.field) and ba.field.top == bb.field.top, "même plan : même terrain de base (hauteurs et matières identiques)")
	var bc := PlanTerrain.build(PlanGenerator.generate(43, 56, 48))
	check(ba.field.top != bc.field.top, "autre graine : autre terrain")
	var f := ba.field
	check(f.land_count() > 5000, "île de %.0f m² de sol" % (float(f.land_count()) * 0.04))
	# les zones plates sont plates, à la hauteur du plan ; les matières suivent les zones
	var pal := VoxelPalette.get_default()
	var arr: Dictionary = a.zone_by_id("arrivee")
	var y := f.ground_at_m((arr["c"] as Vector2).x, (arr["c"] as Vector2).y)
	check(absf(y - float(arr["h"])) <= 0.21, "arrivée : sol à %.2f m (plan : %.2f m)" % [y, float(arr["h"])])
	var pla: Dictionary = a.zone_by_id("plateau")
	var pc: Vector2 = pla["c"]
	var lo := 1e9
	var hi := -1e9
	for k in 40:
		var q := pc + Vector2.from_angle(float(k) * 0.157) * float(pla["r"]) * 0.7
		var yy := f.ground_at_m(q.x, q.y)
		lo = minf(lo, yy)
		hi = maxf(hi, yy)
	check(hi - lo < 0.01 and absf(hi - float(pla["h"])) <= 0.21, "plateau plat (écart %.2f m) à %.2f m (plan : %.2f m)" % [hi - lo, hi, float(pla["h"])])
	var ci := f.col_of_m((arr["c"] as Vector2).x + 1.0, (arr["c"] as Vector2).y + 1.0)
	check(f.material[f.idx(ci.x, ci.y)] == pal.id("gravel"), "matière de l'arrivée = celle du plan (gravier)")
	var som: Dictionary = a.zone_by_id("sommet")
	var higher := true
	for z in a.zones:
		if z["kind"] != "sommet" and f.ground_at_m((som["c"] as Vector2).x, (som["c"] as Vector2).y) <= f.ground_at_m((z["c"] as Vector2).x, (z["c"] as Vector2).y):
			higher = false
	check(higher, "le point haut domine l'île, l'arrivée est en contrebas")
	# chemins : tracés du plan = colonnes de chemin du terrain, matière « sentier », sans rupture
	var dirt := pal.id("path_dirt")
	var on_path := 0
	var good := 0
	for p in a.paths:
		var pts: Array = p["pts"]
		for k in range(pts.size() - 1):
			var m := ((pts[k] as Vector2) + (pts[k + 1] as Vector2)) * 0.5
			var cc := f.col_of_m(m.x, m.y)
			on_path += 1
			if f.material[f.idx(cc.x, cc.y)] == dirt and f.zone_at(cc.x, cc.y) == TerrainField.Zone.ROAD:
				good += 1
	check(good == on_path, "les chemins du plan sont des colonnes de chemin (matière sentier) du terrain : %d/%d" % [good, on_path])
	var reps := PlanTerrain.path_reports(a, f)
	var all_ok := true
	var worst := 0.0
	for r in reps:
		all_ok = all_ok and bool(r["ok"])
		worst = maxf(worst, float(r["max_grade"]))
	check(all_ok, "chemins praticables : aucune rupture, pente maximale %d %% (fenêtre de 2 m)" % roundi(worst * 100.0))
	var sr := PlanTerrain.start_report(a, f)
	check(bool(sr["ok"]), "point de départ sûr : sol plat, à %.1f m du bord" % float(sr.get("edge_m", 0.0)))
	# robustesse : relief et chemins sur des formats variés (terrain complet)
	var fails: Array[String] = []
	var t_ms := 0
	for combo in [[1, 56, 48], [2, 40, 60], [5, 90, 70], [9, 120, 100], [11, 32, 32], [17, 64, 64], [23, 100, 50], [31, 48, 80]]:
		var p := PlanGenerator.generate(combo[0], combo[1], combo[2])
		var b := PlanTerrain.build(p)
		t_ms = maxi(t_ms, b.ms)
		for r in PlanTerrain.path_reports(p, b.field):
			if not bool(r["ok"]):
				fails.append("graine %d %dx%d : %s rupture(s) %d, pentes fortes %d" % [combo[0], combo[1], combo[2], r["id"], r["breaks"].size(), r["steep"].size()])
		var s2 := PlanTerrain.start_report(p, b.field)
		if not bool(s2["ok"]):
			fails.append("graine %d %dx%d : départ %s" % [combo[0], combo[1], combo[2], s2["reason"]])
	check(fails.is_empty(), "8 îles de formats variés : chemins praticables et départ sûr (génération ≤ %d ms)%s" % [t_ms, "" if fails.is_empty() else " — " + fails[0]])
	# une rupture de pente est SIGNALÉE : chemin très court entre l'arrivée basse et le point haut
	var rough := a.copy()
	rough.paths.clear()
	var za: Dictionary = rough.zone_by_id("arrivee")
	var zs: Dictionary = rough.zone_by_id("sommet")
	var pa := (za["c"] as Vector2)
	var pb := pa + ((zs["c"] as Vector2) - pa).normalized() * 9.0
	rough.paths.append({"id": "raide", "width": 2.0, "pts": [pa, pb], "from": "arrivee", "to": ""})
	var br := PlanTerrain.build(rough)
	var rr := PlanTerrain.path_reports(rough, br.field)
	check(rr.size() == 1 and not bool(rr[0]["ok"]), "un chemin trop raide est SIGNALÉ (pente maximale %d %%, %d rupture(s))" % [roundi(float(rr[0]["max_grade"]) * 100.0), rr[0]["breaks"].size()])
	# le profil du chemin est monotone, palier à chaque bout
	var prof := PlanTerrain.path_profile(a, a.paths[0], func(_q: Vector2) -> float: return 4.0)
	var mono := true
	var prev := -1.0
	for k in 60:
		var hh := PlanTerrain.profile_h(prof, float(prof["total"]) * float(k) / 59.0)
		if hh < prev - 0.001:
			mono = false
		prev = hh
	check(mono and absf(PlanTerrain.profile_h(prof, 0.0) - float(a.zone_by_id("arrivee")["h"])) < 0.01 and absf(PlanTerrain.profile_h(prof, float(prof["total"])) - float(a.zone_by_id("plateau")["h"])) < 0.01, "profil de hauteur d'un chemin : palier de départ, montée régulière, palier d'arrivée")

# ------------------------------------------------------------------ format de carte

func _format_checks() -> void:
	var a := PlanGenerator.generate(42, 56, 48)
	var r := IslandPlan.from_json(a.to_json())
	check(r["ok"] and (r["plan"] as IslandPlan).to_json() == a.to_json(), "export puis relecture : plan identique")
	var bad1 := IslandPlan.from_json("{ pas du json")
	check(not bad1["ok"] and String(bad1["error"]).contains("illisible"), "fichier corrompu : erreur expliquée (« %s »)" % bad1["error"])
	var bad2 := IslandPlan.from_json('{"format": "autre", "version": 1}')
	check(not bad2["ok"] and String(bad2["error"]).contains("pas une carte"), "mauvais format refusé : %s" % bad2["error"])
	var d: Dictionary = a.to_dict()
	d["version"] = 99
	var bad3 := IslandPlan.from_dict(d)
	check(not bad3["ok"] and String(bad3["error"]).contains("plus récente"), "version trop récente refusée : %s" % bad3["error"])
	var d2: Dictionary = a.to_dict()
	d2.erase("paths")
	var bad4 := IslandPlan.from_dict(d2)
	check(not bad4["ok"] and String(bad4["error"]).contains("paths"), "champ manquant signalé : %s" % bad4["error"])
	var d3: Dictionary = a.to_dict()
	d3["zones"][0]["kind"] = "lave"
	var bad5 := IslandPlan.from_dict(d3)
	check(not bad5["ok"] and String(bad5["error"]).contains("lave"), "type de zone inconnu signalé : %s" % bad5["error"])
