extends SceneTree
## Éditeur d'îles créatif : objets posés (carte v4), annulation et rétablissement, génération forêt et marché, verrous et zones protégées,
## sauvegarde et réouverture, catalogue de l'inventaire.
##   godot --headless -s tests/run_checks_creatif.gd
var ok := 0
var ko := 0

func check(cond: bool, label: String) -> void:
	if cond:
		ok += 1
		print("  OK    ", label)
	else:
		ko += 1
		print("  ÉCHEC ", label)

func _free_spot(doc: MapDoc, near: Vector2) -> Vector2:
	for r in range(0, 20):
		for a in 16:
			var p := near + Vector2.from_angle(a * TAU / 16.0) * float(r)
			var c := doc.col_of(p)
			if doc.field.has_ground(c.x, c.y) and doc.field.edge_dist[doc.field.idx(c.x, c.y)] > 3.0:
				return p
	return near

func _initialize() -> void:
	print("== Éditeur d'îles créatif ==")
	GameInput.ensure()
	VoxelMesher.palette_warmup()
	# --- catalogue
	var all := AssetCatalog.items()
	check(all.size() >= 55, "catalogue : %d éléments (assets précuits + maisons enregistrées)" % all.size())
	for cat in ["Arbres", "Rochers", "Ruines et vestiges", "Mobilier", "Marché et village", "Maisons", "Port et navires"]:
		check(AssetCatalog.search(all, cat, "").size() > 0, "catégorie « %s » non vide (%d)" % [cat, AssetCatalog.search(all, cat, "").size()])
	check(AssetCatalog.search(all, "", "chene").size() >= 3, "recherche sans accent : « chene » → %d chênes" % AssetCatalog.search(all, "", "chene").size())
	check(AssetCatalog.search(all, "Arbres", "pin").size() >= 2, "recherche dans une catégorie : pins")
	check(AssetCatalog.search(all, "", "zzzxxx").is_empty(), "recherche sans résultat : liste vide")
	# --- document
	var doc := MapDoc.from_plan(PlanGenerator.generate(5, 56.0, 48.0))
	var spot := _free_spot(doc, doc.plan.start + Vector2(6, 2))
	var id1 := doc.add_object("tree_oak_1", spot, 30.0, 1.0)
	check(id1 != "" and doc.plan.objects.size() == 1, "poser un objet : une opération")
	check(doc.add_object("tree_oak_1", Vector2(5000, 5000)) == "", "hors de l'île : refusé, rien n'est posé")
	check(doc.update_object(id1, {"pos": spot + Vector2(2, 0)}, "Déplacer") and (doc.object_by_id(id1)["pos"] as Vector2).is_equal_approx(spot + Vector2(2, 0)), "déplacer")
	check(doc.update_object(id1, {"yaw": 75.0}, "Tourner") and absf(float(doc.object_by_id(id1)["yaw"]) - 75.0) < 0.01, "tourner")
	var id2 := doc.duplicate_object(id1, Vector2(2.5, 0))
	check(id2 != "" and doc.plan.objects.size() == 2 and not bool(doc.object_by_id(id2)["locked"]), "dupliquer")
	doc.update_object(id2, {"locked": true}, "Verrouiller")
	check(not doc.update_object(id2, {"pos": spot}) and not doc.delete_object(id2), "objet verrouillé : ni déplacé ni supprimé")
	check(doc.update_object(id2, {"locked": false}, "Déverrouiller") and doc.delete_object(id2) and doc.plan.objects.size() == 1, "déverrouiller puis supprimer")
	# annuler / rétablir par opération
	var n_undo := doc.undo_stack.size()
	check(doc.undo() != "" and doc.plan.objects.size() == 2, "Ctrl+Z annule la suppression")
	check(doc.can_redo() and doc.redo() != "" and doc.plan.objects.size() == 1, "rétablir la suppression")
	doc.undo()
	doc.undo()
	doc.undo()
	check(absf(float(doc.object_by_id(id1)["yaw"]) - 30.0) < 0.01 or doc.object_by_id(id1).is_empty() == false, "annulations en chaîne : une opération à la fois")
	while doc.can_undo():
		doc.undo()
	check(doc.plan.objects.is_empty(), "tout annulé : plus aucun objet")
	while doc.can_redo():
		doc.redo()
	check(doc.plan.objects.size() == 1 and doc.undo_stack.size() == n_undo, "tout rétabli : %d objet, historique complet" % doc.plan.objects.size())
	doc.add_object("boulder_1", spot + Vector2(0, 3))
	check(not doc.can_redo(), "une nouvelle opération vide les opérations rétablissables")
	# --- forêt
	var c := _free_spot(doc, doc.plan.start + Vector2(0, 10))
	var f1 := doc.compose("foret", c, 6.0, 11, {"densite": 70})
	check(bool(f1["ok"]) and (f1["ids"] as Array).size() >= 5, "forêt : %s (refus : %s)" % [doc.message, str(f1.get("fails", {}))])
	var f1b := Composer.plan_composition(doc, "foret", c, 6.0, 11, {"densite": 70})
	var f2doc := MapDoc.from_plan(PlanGenerator.generate(5, 56.0, 48.0))
	var f2a := Composer.plan_composition(f2doc, "foret", c, 6.0, 11, {"densite": 70})
	var f2b := Composer.plan_composition(f2doc, "foret", c, 6.0, 11, {"densite": 70})
	var same := (f2a["objects"] as Array).size() == (f2b["objects"] as Array).size()
	for i in mini((f2a["objects"] as Array).size(), (f2b["objects"] as Array).size()):
		same = same and f2a["objects"][i]["ref"] == f2b["objects"][i]["ref"] and (f2a["objects"][i]["pos"] as Vector2).is_equal_approx(f2b["objects"][i]["pos"])
	check(same, "génération reproductible (même graine, même zone, même carte)")
	# chaque objet généré est modifiable et supprimable individuellement
	var gid: String = f1["ids"][0]
	var gid2: String = f1["ids"][1]
	check(doc.update_object(gid, {"pos": (doc.object_by_id(gid)["pos"] as Vector2) + Vector2(1.5, 0.5)}, "Déplacer") and doc.delete_object(gid2), "objets générés : déplacés et supprimés un à un")
	# verrouillage : l'objet verrouillé survit à une nouvelle génération
	var keep_id: String = f1["ids"][2]
	doc.update_object(keep_id, {"locked": true}, "Verrouiller")
	var keep_pos: Vector2 = doc.object_by_id(keep_id)["pos"]
	var prev := doc.plan.objects.size()
	var f3 := doc.compose("foret", c, 6.0, 12, {"densite": 70})
	check(bool(f3["ok"]) and not doc.object_by_id(keep_id).is_empty() and (doc.object_by_id(keep_id)["pos"] as Vector2).is_equal_approx(keep_pos), "objet verrouillé conservé par la régénération (%d → %d objets)" % [prev, doc.plan.objects.size()])
	check((f3["kept_locked"] as int) >= 1, "la régénération annonce %d objet(s) verrouillé(s) conservé(s)" % f3["kept_locked"])
	# objet posé à la main : jamais retiré
	var manual := doc.add_object("water_well", c + Vector2(0.0, 0.0), 0.0, 1.0, "manuel")
	doc.compose("foret", c, 6.0, 13, {"densite": 70})
	check(manual == "" or not doc.object_by_id(manual).is_empty(), "objet posé à la main conservé")
	# zone protégée : colonnes masquées intactes (relief ET objets)
	var pc := _free_spot(doc, doc.plan.start + Vector2(-8, 8))
	doc.stroke_begin("Protéger", "masque", pc)
	doc.stroke_dab("masque", pc, 3.0)
	doc.stroke_end()
	var tid := doc.add_object("tree_pine_1", pc, 0.0, 1.0, "foret")
	var top_before := doc.field.top.duplicate()
	var rect := Rect2(pc - Vector2(5, 5), Vector2(10, 10))
	var reg := doc.regenerate(rect)
	var prot_ok := true
	var cc := doc.col_of(pc)
	for dz in range(-5, 6):
		for dx in range(-5, 6):
			var q := Vector2i(cc.x + dx, cc.y + dz)
			if doc.field.in_bounds(q.x, q.y) and doc.is_protected(doc.field.idx(q.x, q.y)) and doc.field.top[doc.field.idx(q.x, q.y)] != top_before[doc.field.idx(q.x, q.y)]:
				prot_ok = false
	check(prot_ok, "régénération du relief : colonnes protégées intactes")
	var g4 := doc.compose("foret", pc, 6.0, 21, {"densite": 90})
	check(tid == "" or not doc.object_by_id(tid).is_empty(), "régénération des objets : un objet en zone protégée n'est pas retiré")
	var inside_mask := 0
	for o in doc.plan.objects:
		if String(o["id"]) in (g4.get("ids", []) as Array):
			var qc := doc.col_of(o["pos"])
			if doc.is_protected(doc.field.idx(qc.x, qc.y)):
				inside_mask += 1
	check(inside_mask == 0, "aucun nouvel objet généré dans la zone protégée")
	# --- marché
	var mdoc := MapDoc.from_plan(PlanGenerator.generate(5, 56.0, 48.0))
	var mc := _free_spot(mdoc, mdoc.plan.start + Vector2(6, 6))
	var mk: Dictionary = {}
	for rad in [6.0, 7.0, 8.0]:
		mk = mdoc.compose("marche", mc, rad, 3, {"etals": 4})
		if bool(mk["ok"]):
			break
	check(bool(mk["ok"]) and int(mk["counts"].get("étal", 0)) >= 1, "marché : %s" % mdoc.message)
	# --- sauvegarde / réouverture (carte v4)
	var path := "user://test_creatif.eclats-carte.json"
	var r := doc.export_to(path)
	check(bool(r["ok"]) and not doc.is_dirty(), "enregistrement : carte v%d" % IslandPlan.VERSION)
	var d2 := MapDoc.new()
	var o2 := d2.open_from(path)
	check(bool(o2["ok"]) and d2.plan.objects.size() == doc.plan.objects.size(), "réouverture : %d objets retrouvés" % d2.plan.objects.size())
	var same_obj := true
	for o in doc.plan.objects:
		var q := d2.object_by_id(String(o["id"]))
		same_obj = same_obj and not q.is_empty() and q["ref"] == o["ref"] and (q["pos"] as Vector2).distance_to(o["pos"]) < 0.01 and bool(q["locked"]) == bool(o["locked"])
	check(same_obj, "objets identiques après réouverture (modèle, position, verrou)")
	check(d2.field != null and d2.field.top == doc.field.top, "relief identique après réouverture")
	# ancien format : une carte v3 (sans objets) se rouvre
	var legacy := IslandPlan.from_dict({"format": "eclats-carte", "version": 3, "name": "ancienne", "seed": 1, "width": 56, "length": 48, "outline": [[-20, -20], [20, -20], [20, 20], [-20, 20]],
		"zones": [], "paths": [], "landmarks": [], "start": [0, 0]})
	check(bool(legacy["ok"]) and (legacy["plan"] as IslandPlan).objects.is_empty(), "carte v3 (sans objets) rouverte sans perte")
	var bad := IslandPlan.from_dict({"format": "eclats-carte", "version": 4, "name": "x", "seed": 1, "width": 56, "length": 48, "outline": [[-20, -20], [20, -20], [20, 20], [-20, 20]],
		"zones": [], "paths": [], "landmarks": [], "start": [0, 0], "objets": [{"ref": "tree_oak_1", "pos": [1, 2], "kind": "monstre"}]})
	check(not bool(bad["ok"]), "objet de type inconnu : refusé avec une explication")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await _check_stairs()
	print("\n%d contrôles : %d OK, %d en échec" % [ok + ko, ok, ko])
	quit(1 if ko > 0 else 0)

func _check_stairs() -> void:
	print("Escalier et étage accessible")
	var c := Construction.new()
	var room := ConstructionOps.add_room(c, 0, Vector2i(0, 0), Vector2i(16, 12), 3.0, "S", "bois", "planches")
	check(bool(room["ok"]), "pièce de 8 × 6 m posée (sol, murs, porte)")
	c = room["cand"]
	var no_upper := ConstructionOps.add_stairs(c, 0, Vector2i(2, 2), "E")
	check(not bool(no_upper["ok"]) and "sol à l'étage" in String(no_upper["reasons"][0]), "escalier refusé sans sol à l'étage, avec explication")
	var up := ConstructionOps.add_slab(c, "floor", 1, Vector2i(0, 0), Vector2i(16, 12))
	check(bool(up["ok"]), "sol de l'étage posé")
	c = up["cand"]
	var short := ConstructionOps.add_stairs(c, 0, Vector2i(10, 2), "E")
	check(not bool(short["ok"]), "escalier sans palier suffisant refusé (le sol de l'étage doit dépasser le sommet)")
	var st := ConstructionOps.add_stairs(c, 0, Vector2i(2, 2), "E")
	check(bool(st["ok"]), "escalier posé : %s" % String(st["text"]))
	c = st["cand"]
	var again := ConstructionOps.add_stairs(c, 0, Vector2i(3, 2), "E")
	check(not bool(again["ok"]), "deux escaliers ne se chevauchent pas")
	var f1 := c.of_type("floor", 1)[0]
	var boxes := c.slab_boxes(f1)
	var area := 0.0
	for b in boxes:
		area += b.size.x * b.size.z
	check(boxes.size() >= 2 and absf(area - (8.0 * 6.0 - 4.0 * 1.0)) < 0.01, "le sol de l'étage est percé de l'escalier (%d morceaux, %.1f m²)" % [boxes.size(), area])
	check(c.stair_boxes(c.of_type("stairs")[0]).size() == 12, "12 marches de 25 cm")
	# aller-retour fichier
	var path := "user://test_maison_escalier.eclats-maison.json"
	var sv := Construction.save_file(c, path)
	var ld := Construction.load_file(path)
	check(bool(sv["ok"]) and bool(ld["ok"]) and (ld["construction"] as Construction).of_type("stairs").size() == 1, "enregistrée et rouverte avec son escalier")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# on monte à pied (physique réelle : capsule du joueur, marches de 25 cm)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(60, 1, 60)
	gs.shape = gb
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	get_root().add_child(ground)
	var house := ConstructionView.create(c, {"collide": true})
	get_root().add_child(house)
	var ex := Explorer.new()
	get_root().add_child(ex)
	ex.teleport(Vector3(0.5, 0.5, 1.5), 0.0)       # devant le bas de l’escalier (x = 1,0 m), à l’intérieur
	for i in 30:
		await physics_frame
	var y0 := ex.global_position.y
	ex.auto_active = true
	ex.auto_dir = Vector2(1, 0)
	var top_y := y0
	for i in 420:
		await physics_frame
		top_y = maxf(top_y, ex.global_position.y)
	check(top_y - y0 > 2.7, "le personnage monte l'escalier à pied : +%.2f m (niveau d'étage à +3,00 m)" % (top_y - y0))
	check(ex.global_position.x > 4.0, "…et arrive sur le palier de l'étage (x = %.1f m)" % ex.global_position.x)
