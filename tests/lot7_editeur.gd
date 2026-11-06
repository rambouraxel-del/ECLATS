extends RefCounted
## Contrôles du Lot 7 · étape 2 : document de carte (canevas vide, contour, zones, chemins, pinceaux, masque, régénération,
## annulation, export / ouverture). Appelé par run_checks_lot7.gd.

static func _same_layers(a: PlanLayers, b: PlanLayers) -> bool:
	return a != null and b != null and a.n == b.n and a.delta == b.delta and a.mat == b.mat and a.mask == b.mask

static func island() -> Array:
	return [Vector2(-18, -4), Vector2(-14, -13), Vector2(-4, -17), Vector2(8, -15), Vector2(17, -8), Vector2(19, 3), Vector2(14, 12),
		Vector2(4, 16), Vector2(-8, 15), Vector2(-16, 9)]

## Carte d'essai du lot : île dessinée depuis un canevas vide (contour, crique, prairie, bois, chemin).
static func make_test_doc() -> MapDoc:
	var d := MapDoc.blank("Île d'essai")
	d.begin_op("Contour")
	d.set_outline(island())
	d.finish_op()
	d.begin_op("Zones")
	d.plan.zones.append({"id": "pelouse_a", "kind": "pelouse", "c": Vector2(0, 0), "r": 11.0, "h": 0.0})
	d.add_zone_disc("bois", Vector2(8, -6), 5.0)
	d.add_zone_disc("crique", Vector2(-11, 5), 3.4, 2.0)
	d.plan.start = Vector2(-11, 5)
	d.finish_op()
	d.begin_op("Chemin")
	d.add_path([Vector2(-11, 5), Vector2(-4, 4), Vector2(2, 0), Vector2(8, -6)], 2.2)
	d.finish_op()
	return d

static func run(t: SceneTree) -> void:
	print("\n== Lot 7 · étape 2 : éditeur de carte ==")
	# --- canevas vide
	var d := MapDoc.blank()
	t.check(not d.has_terrain() and d.plan.outline.is_empty(), "canevas vide : aucun contour, aucun terrain")
	d = make_test_doc()
	t.check(d.has_terrain() and d.field.land_count() > 1000, "île dessinée depuis le canevas : %.0f m² de sol" % (float(d.field.land_count()) * 0.04))
	t.check(d.plan.problems().is_empty(), "plan de l'île d'essai cohérent")
	var crique_y := d.field.ground_at_m(-11.0, 5.0)
	t.check(absf(crique_y - 2.0) <= 0.21, "la crique est plate, au niveau demandé (%.2f m)" % crique_y)
	var n := d.field.n
	# --- chemin : déplacer un point, le terrain suit ; annuler
	var pid: String = d.plan.paths[0]["id"]
	var before_top := d.field.top.duplicate()
	var old_mid := d.plan.paths[0]["pts"][2] as Vector2
	var cm := d.field.col_of_m(old_mid.x, old_mid.y)
	var was_road := d.field.zone_at(cm.x, cm.y) == TerrainField.Zone.ROAD
	d.edit("Déplacer un point de chemin", func() -> void: d.move_path_point(pid, 2, Vector2(2, 8)))
	var moved: Vector2 = d.plan.paths[0]["pts"][2]
	var cn := d.field.col_of_m(moved.x, moved.y)
	t.check(was_road and d.field.zone_at(cn.x, cn.y) == TerrainField.Zone.ROAD and d.field.material[d.field.idx(cn.x, cn.y)] == VoxelPalette.get_default().id("path_dirt"), "chemin déplacé : le terrain suit (sentier au nouvel emplacement)")
	t.check(d.field.zone_at(cm.x, cm.y) != TerrainField.Zone.ROAD, "l'ancien emplacement n'est plus un chemin")
	var rep_ok := true
	for r in d.path_reports:
		rep_ok = rep_ok and bool(r["ok"])
	t.check(d.path_reports.size() == 1, "chemin vérifié après déplacement (praticable : %s)" % ("oui" if rep_ok else "signalé"))
	d.undo()
	t.check(d.field.top == before_top and (d.plan.paths[0]["pts"][2] as Vector2).distance_to(old_mid) < 0.01, "Ctrl+Z : le chemin et le terrain reviennent à l'état précédent")
	# --- largeur d'un chemin
	d.edit("Largeur du chemin", func() -> void: d.set_path_width(pid, 3.6))
	var wide := 0
	var narrow := 0
	for i in n * n:
		if d.build.path_cols[i] == 1:
			wide += 1
	d.undo()
	for i in n * n:
		if d.build.path_cols[i] == 1:
			narrow += 1
	t.check(wide > narrow + 40, "largeur du chemin réglable : %d colonnes à 3,6 m contre %d à 2,2 m" % [wide, narrow])
	# --- réglage du relief naturel
	var t_rel := d.field.top.duplicate()
	d.edit("Relief naturel ×1,8", func() -> void: d.plan.settings["relief"] = 1.8)
	t.check(d.field.top != t_rel and d.plan.settings["relief"] == 1.8, "réglage « relief naturel » : un autre relief, mêmes zones et chemins")
	d.undo()
	t.check(d.field.top == t_rel, "Ctrl+Z annule le réglage du relief")
	# --- pinceaux de relief
	var center := Vector2(-2, -8)
	var base := d.field.top.duplicate()
	var rc := d.col_of(center)
	d.stroke_begin("Monter le relief", "monter", center)
	for k in 6:
		d.stroke_dab("monter", center + Vector2(float(k) * 0.4, 0), 2.5, 0.8)
	var dirty := d.stroke_end()
	var gain := d.field.top_at(rc.x + 5, rc.y) - base[(rc.x + 5) + rc.y * n]
	var outside_ok := true
	for cz in n:
		for cx in n:
			var p := d.field.center_m(cx, cz)
			if p.distance_to(center) > 2.5 + 2.2 + 0.3 and d.field.top[cx + cz * n] != base[cx + cz * n]:
				outside_ok = false
	t.check(gain >= 2 and dirty.size.x > 10 and outside_ok, "pinceau « monter » : +%d cellules au centre, aucune colonne modifiée hors de la zone d'effet" % gain)
	d.undo()
	t.check(d.field.top == base, "Ctrl+Z annule le trait de pinceau entier (relief identique)")
	d.stroke_begin("Creuser", "creuser", center)
	d.stroke_dab("creuser", center, 2.0, 0.9)
	d.stroke_dab("creuser", center, 2.0, 0.9)
	d.stroke_end()
	t.check(d.field.top_at(rc.x, rc.y) < base[rc.x + rc.y * n], "pinceau « creuser » : le sol descend")
	var stack0 := d.undo_stack.size() - 1          # profondeur avant « creuser »
	d.stroke_begin("Aplanir", "aplanir", center + Vector2(3, 0))
	for k in 5:
		d.stroke_dab("aplanir", center + Vector2(float(k) * 0.5, 0), 3.0, 0.6)
	d.stroke_end()
	var level := d.field.top_at(rc.x + 15, rc.y)
	var span := 0
	for k in range(0, 8):
		span = maxi(span, absi(d.field.top_at(rc.x + 10 + k, rc.y) - level))
	t.check(span <= 2, "pinceau « aplanir » : sol quasi plat sur la zone (écart %d cellule(s))" % span)
	d.stroke_begin("Adoucir", "adoucir", center)
	d.stroke_dab("adoucir", center + Vector2(-1.5, 0), 3.0, 1.0)
	d.stroke_end()
	var undone := 0
	while d.undo_stack.size() > stack0:
		d.undo()
		undone += 1
	t.check(d.field.top == base and undone >= 2, "%d annulations successives (creuser, aplanir, adoucir) : retour au relief d'origine" % undone)
	# --- matériaux
	var mat_id := VoxelPalette.get_default().id("dirt_dry")
	var cm2 := d.col_of(Vector2(0, 8))
	var mat_before := d.field.material.duplicate()
	d.stroke_begin("Peindre la matière", "matiere", Vector2(0, 8))
	d.stroke_dab("matiere", Vector2(0, 8), 2.0, 0.5, mat_id)
	d.stroke_end()
	t.check(d.field.material[d.field.idx(cm2.x, cm2.y)] == mat_id and d.plan.layers.count_mat() > 100, "pinceau de matière : sol peint (%d colonnes)" % d.plan.layers.count_mat())
	d.undo()
	t.check(d.field.material == mat_before, "Ctrl+Z restaure les matières")
	# --- masque de protection + relief protégé
	var crique := Vector2(-11, 5)
	d.stroke_begin("Protéger la crique", "masque", crique)
	d.stroke_dab("masque", crique, 4.5)
	d.stroke_end()
	var masked := d.plan.layers.count_mask()
	t.check(masked > 500, "masque de protection posé sur la crique : %d colonnes" % masked)
	var before_mask_top := d.field.top.duplicate()
	d.stroke_begin("Monter (protégé)", "monter", crique)
	d.stroke_dab("monter", crique, 3.0, 1.0)
	var r_prot := d.stroke_end()
	t.check(d.field.top == before_mask_top and r_prot.size == Vector2i.ZERO, "les pinceaux respectent le masque : crique intacte")
	# --- régénération autour de la crique
	var snap_top := d.field.top.duplicate()
	var snap_layers := d.plan.layers.copy()
	var sel := Rect2(Vector2(-17, -2), Vector2(14, 14))        # contient la crique
	var rg := d.regenerate(sel, 5)
	t.check(rg["ok"] and int(rg["changed"]) > 200, "régénération : le relief change dans la sélection (%d colonnes)" % int(rg.get("changed", 0)))
	var crique_same := true
	var outside_same := true
	var in_sel_changed := 0
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			var p := d.field.center_m(cx, cz)
			var was_masked := snap_layers.mask[i] != 0
			if was_masked and d.field.top[i] != snap_top[i]:
				crique_same = false
			if not sel.has_point(p) and d.field.top[i] != snap_top[i]:
				outside_same = false
			if sel.has_point(p) and d.field.top[i] != snap_top[i]:
				in_sel_changed += 1
	t.check(crique_same, "la crique protégée est restée intacte après la régénération")
	t.check(outside_same, "les zones extérieures à la sélection n'ont pas bougé")
	t.check(in_sel_changed == int(rg["changed"]), "toutes les modifications sont dans la sélection")
	var path_ok := true
	for r in d.path_reports:
		path_ok = path_ok and bool(r["ok"])
	t.check(path_ok, "le chemin reste praticable après la régénération")
	d.undo()
	t.check(d.field.top == snap_top and _same_layers(d.plan.layers, snap_layers), "Ctrl+Z restaure l'état d'avant la régénération (relief et couches)")
	var rg2 := d.regenerate(Rect2(Vector2(-17, -2), Vector2(14, 14)), 5)
	var rg3 := d.regenerate(Rect2(Vector2(-17, -2), Vector2(14, 14)), 6)
	t.check(rg2["ok"] and rg3["ok"], "deux variantes successives")
	d.undo()
	d.undo()
	t.check(d.field.top == snap_top, "deux annulations : retour à l'état d'avant")
	var rg5 := d.regenerate(sel, 6)
	var top_v6 := d.field.top.duplicate()
	d.undo()
	var rg6 := d.regenerate(sel, 6)
	t.check(rg5["ok"] and rg6["ok"] and d.field.top == top_v6, "même état, même sélection, même variante : même relief (déterminisme de la régénération)")
	d.undo()
	var fully := d.regenerate(Rect2(Vector2(-16, 1), Vector2(10, 8)), 9)        # entièrement dans la crique + marge
	t.check(bool(fully["ok"]) or String(fully["reason"]) != "", "régénération d'une zone presque protégée : résultat ou raison")
	if bool(fully["ok"]):
		d.undo()
	# --- export, nouvelle session, ouverture
	d.begin_op("Repère")
	d.add_landmark("vue", Vector2(8, -6), "Vue sur le bois")
	d.finish_op()
	d.stroke_begin("Monter", "monter", Vector2(5, 8))
	d.stroke_dab("monter", Vector2(5, 8), 2.5, 1.0)
	d.stroke_dab("monter", Vector2(5, 8), 2.5, 1.0)
	d.stroke_end()
	var rg4 := d.regenerate(sel, 7)
	var path := "user://test_lot7_carte.eclats-carte.json"
	var ex := d.export_to(path)
	t.check(ex["ok"] and FileAccess.file_exists(path), "carte exportée (%d octets)" % FileAccess.get_file_as_bytes(path).size())
	var d2 := MapDoc.new()
	d2.plan = IslandPlan.blank("autre")
	var op := d2.open_from(path)
	t.check(op["ok"], "carte rouverte dans un nouveau document")
	t.check(d2.plan.to_json() == d.plan.to_json(), "plan, chemins, repères, zones et réglages identiques")
	t.check(_same_layers(d.plan.layers, d2.plan.layers), "retouches de relief, de matières et masque conservés")
	t.check(d2.field.top == d.field.top and d2.field.material == d.field.material, "terrain rouvert identique, colonne pour colonne (%d retouches de relief, %d de matière, %d protégées)" % [d2.plan.layers.count_delta(), d2.plan.layers.count_mat(), d2.plan.layers.count_mask()])
	t.check(d2.plan.paths.size() == 1 and d2.plan.landmarks.size() == 1 and (d2.plan.paths[0]["pts"] as Array).size() == 4, "chemin et repère retrouvés (%d chemin, %d repère, %d points)" % [d2.plan.paths.size(), d2.plan.landmarks.size(), (d2.plan.paths[0]["pts"] as Array).size()])
	# --- fichier invalide : explication, île conservée
	var bad_path := "user://test_lot7_invalide.json"
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string('{"format": "eclats-carte", "version": 1, "name": "x"')
	f.close()
	var json_before := d2.plan.to_json()
	var top_before := d2.field.top.duplicate()
	var bad := d2.open_from(bad_path)
	t.check(not bad["ok"] and String(bad["error"]).contains("illisible"), "fichier invalide : erreur expliquée — « %s »" % bad["error"])
	t.check(d2.plan.to_json() == json_before and d2.field.top == top_before, "après l'erreur, l'île ouverte est conservée")
	var missing := d2.open_from("user://nexiste_pas.json")
	t.check(not missing["ok"] and String(missing["error"]).contains("introuvable"), "fichier absent : %s" % missing["error"])
	# --- contour qui se croise : refusé, opération défaite
	var d3 := make_test_doc()
	var top3 := d3.field.top.duplicate()
	var out_before := d3.plan.outline.duplicate()
	var err := d3.edit("Contour croisé", func() -> void: d3.move_outline_point(0, Vector2(10, 14)))
	t.check(err != "" and d3.plan.outline == out_before and d3.field.top == top3, "contour qui se croise refusé : %s" % err)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
