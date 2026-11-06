extends SceneTree
## Contrôles ciblés du Lot 8 (sans rendu) : construction joueur (coûts, ouvertures, pièces, toits, étages), format de maison,
## placement sur une carte. godot --headless -s tests/run_checks_lot8.gd
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
	print("== Lot 8 : construction joueur, atelier, maisons ==")
	_cost_checks()
	_wall_checks()
	_room_checks()
	_roof_checks()
	_level_checks()
	_format_checks()
	for f in ["res://tests/lot8_atelier.gd", "res://tests/lot8_carte.gd"]:
		if FileAccess.file_exists(f):
			await load(f).run(self)
	print("\n%d contrôles réussis, %d échecs" % [ok, ko])
	quit(1 if ko > 0 else 0)

func _cost_checks() -> void:
	var c := Construction.new()
	var r := ConstructionOps.add_slab(c, "floor", 0, Vector2i(0, 0), Vector2i(2, 2))
	check(r["ok"] and r["delta"] == 1, "1 m² (2 × 2 u) coûte 1 unité")
	r = ConstructionOps.add_slab(c, "floor", 0, Vector2i(0, 0), Vector2i(3, 3))
	check(r["ok"] and r["delta"] == 3, "1,50 × 1,50 m coûte 3 unités (2,25 m² arrondis à l'unité supérieure)")
	r = ConstructionOps.add_slab(c, "foundation", 0, Vector2i(0, 0), Vector2i(1, 1))
	check(r["ok"] and r["delta"] == 1, "0,25 m² coûte 1 unité (jamais 0)")
	check(String(r["text"]).find(".") < 0 and "coût 1 unité" in String(r["text"]), "le texte du coût n'affiche que des entiers")
	var w := ConstructionOps.add_wall(c, 0, Vector2i(0, 0), Vector2i(7, 0), 2.5)
	check(w["ok"] and w["delta"] == 9, "mur de 3,5 m × 2,5 m : 8,75 m² → 9 unités")
	check(not w["ok"] or c.elements.is_empty(), "la préparation ne modifie pas la construction (aucun débit sans confirmation)")
	var mod := ConstructionOps.add_wall(c, 0, Vector2i(0, 0), Vector2i(0, 1), 2.5)
	check(not mod["ok"], "mur de 0,5 m refusé (trop court)")

func _wall_checks() -> void:
	var c := Construction.new()
	c = ConstructionOps.add_wall(c, 0, Vector2i(0, 0), Vector2i(10, 0), 2.5)["cand"]
	var wid: int = c.elements[0]["id"]
	var boxes_full := c.wall_boxes(c.elements[0]).size()
	check(boxes_full == 1, "mur plein : une seule boîte de collision")
	var d := ConstructionOps.add_opening(c, wid, "door", 5.0)
	check(d["ok"] and d["delta"] == 4, "porte posée au milieu : forfait de 4 unités")
	c = d["cand"]
	var bx := c.wall_boxes(c.elements[0])
	check(bx.size() == 3, "la porte découpe le mur : 2 pans + 1 linteau (%d boîtes)" % bx.size())
	var door_free := true
	for b in bx:
		# le passage de 1,0 m de large et de 2,0 m de haut ne doit contenir aucune matière
		var pass_box := AABB(Vector3(2.1, 0.0, -0.05), Vector3(0.8, 1.9, 0.1))
		if b.intersects(pass_box):
			door_free = false
	check(door_free, "le passage de la porte est réellement vide (collisions mises à jour)")
	var win := ConstructionOps.add_opening(c, wid, "window", 2.0)
	check(win["ok"] and win["delta"] == 2, "fenêtre voisine acceptée (forfait de 2 unités)")
	var too_close := ConstructionOps.add_opening(c, wid, "window", 5.5)
	check(not too_close["ok"] and "Trop près" in String(too_close["reasons"][0]), "fenêtre collée à la porte refusée avec explication")
	var edge := ConstructionOps.add_opening(c, wid, "window", 0.5)
	check(not edge["ok"], "ouverture au bout du mur refusée")
	# modification qui rend l'ouverture incompatible
	var before := c.signature()
	var cut := ConstructionOps.modify_wall(c, wid, Vector2i(0, 0), Vector2i(6, 0), 2.5)
	check(not cut["ok"] and "ne tiendrait plus" in String(cut["reasons"][0]), "raccourcir le mur sous la porte est refusé et expliqué")
	check(c.signature() == before, "construction intacte après un refus")
	var low := ConstructionOps.modify_wall(c, wid, Vector2i(0, 0), Vector2i(10, 0), 2.0)
	check(low["ok"], "mur abaissé à 2,0 m : la porte de 2,0 m tient encore")
	var longer := ConstructionOps.modify_wall(c, wid, Vector2i(0, 0), Vector2i(12, 0), 2.5)
	check(longer["ok"] and longer["delta"] == 2, "règle de redimensionnement : mur 5 → 6 m, différence de 2 unités à payer (15 − 13)")
	var shorter := ConstructionOps.modify_wall(c, wid, Vector2i(0, 0), Vector2i(8, 0), 2.5)
	check(shorter["ok"] and shorter["delta"] == -3, "mur raccourci 5 → 4 m : les ouvertures tiennent, 3 unités remboursées (15 − 12)")
	var shorter2 := ConstructionOps.modify_wall(c, wid, Vector2i(4, 0), Vector2i(10, 0), 2.5)
	check(not shorter2["ok"], "début du mur avancé de 2 m : la porte touche l'extrémité, refusé")
	var rm := ConstructionOps.remove_opening(c, wid, int(c.elements[0]["ops"][0]["id"]))
	check(rm["ok"] and rm["delta"] < 0, "retirer une ouverture la rembourse")
	var wall_no_win := ConstructionOps.add_wall(Construction.new(), 0, Vector2i(0, 0), Vector2i(10, 0), 2.0)["cand"] as Construction
	var wn := ConstructionOps.add_opening(wall_no_win, int(wall_no_win.elements[0]["id"]), "window", 5.0)
	check(not wn["ok"] and "trop bas" in String(wn["reasons"][0]), "fenêtre sur un mur de 2,0 m refusée (trop bas)")

func _room_checks() -> void:
	var c := Construction.new()
	var r := ConstructionOps.add_room(c, 0, Vector2i(0, 0), Vector2i(8, 6), 2.5, "S")
	check(r["ok"], "pièce 4 × 3 m tracée")
	var cand: Construction = r["cand"]
	check(cand.of_type("wall").size() == 4 and cand.of_type("floor").size() == 1, "pièce = 1 plancher + 4 murs modifiables")
	var door_walls := 0
	for w in cand.of_type("wall"):
		door_walls += (w["ops"] as Array).size()
	check(door_walls == 1 and cand.entrance().size() > 0, "une porte, côté choisi")
	check(cand.entrance()["dir"] == Vector2i(0, 1), "porte côté sud : l'entrée regarde vers +z")
	var total := 12 + 2 * 5 * 4 / 2 * 2    # plancher 12 m² ; murs 4 + 4 + 3 + 3 m × 2,5 m = 35 m² (arrondis par mur)
	var expected := 12 + ceili(4.0 * 2.5) + ceili(4.0 * 2.5) + ceili(3.0 * 2.5) + ceili(3.0 * 2.5) + Construction.DOOR_COST
	check(int(r["delta"]) == expected, "coût de la pièce = %d (plancher + 4 murs arrondis + porte)" % expected)
	for side in ["N", "E", "W"]:
		var rr := ConstructionOps.add_room(Construction.new(), 0, Vector2i(0, 0), Vector2i(8, 6), 2.5, side)
		check(rr["ok"], "porte côté %s acceptée" % side)
	var tiny := ConstructionOps.add_room(c, 0, Vector2i(20, 20), Vector2i(22, 22))
	check(not tiny["ok"], "pièce de 1 m refusée")
	# changer la hauteur de toute la pièce
	var wid: int = cand.of_type("wall")[0]["id"]
	var hh := ConstructionOps.set_group_height(cand, wid, 3.0)
	check(hh["ok"] and hh["cand"].of_type("wall")[0]["h"] == 3.0 and hh["cand"].of_type("wall")[3]["h"] == 3.0, "hauteur réglable pour toute la pièce (3,0 m)")
	# deux pièces voisines partagent un mur
	var two := ConstructionOps.add_room(cand, 0, Vector2i(8, 0), Vector2i(14, 6), 2.5, "S")
	check(two["ok"] and two["cand"].of_type("wall").size() == 7, "deux pièces voisines partagent leur mur commun (7 murs)")

func _roof_checks() -> void:
	var r := ConstructionOps.add_room(Construction.new(), 0, Vector2i(0, 0), Vector2i(8, 6), 2.5, "S")
	var c: Construction = r["cand"]
	var wid: int = c.of_type("wall")[0]["id"]
	var rf := ConstructionOps.add_roof(c, wid)
	check(rf["ok"], "toit ajusté à l'emprise des murs")
	var roof: Dictionary = rf["cand"].of_type("roof")[0]
	check(roof["x0"] == 0 and roof["x1"] == 8 and roof["z0"] == 0 and roof["z1"] == 6, "le toit suit exactement le rectangle des murs")
	var sh: Dictionary = rf["cand"].roof_shape(roof)
	check(int(sh["ridge_axis"]) == 0 and float(sh["rise"]) > 0.5, "faîtage le long du grand côté, pente visible")
	check(rf["delta"] > 0, "le toit a un coût entier (%d)" % rf["delta"])
	var again := ConstructionOps.add_roof(rf["cand"], wid)
	check(not again["ok"], "second toit sur la même emprise refusé")

func _level_checks() -> void:
	var c: Construction = ConstructionOps.add_room(Construction.new(), 0, Vector2i(0, 0), Vector2i(8, 6), 3.0, "S")["cand"]
	var up := ConstructionOps.add_room(c, 1, Vector2i(0, 0), Vector2i(8, 6), 2.5, "S")
	check(up["ok"] and up["cand"].level_count() == 2, "étage posé sur le rez-de-chaussée")
	var up_door := 0
	for w in up["cand"].of_type("wall", 1):
		up_door += (w["ops"] as Array).size()
	check(up_door == 0, "pas de porte à l'étage")
	var fly := ConstructionOps.add_slab(Construction.new(), "floor", 1, Vector2i(0, 0), Vector2i(4, 4))
	check(not fly["ok"], "un étage sans rez-de-chaussée dessous est refusé")
	var rm := ConstructionOps.remove_element(c, int(c.of_type("floor")[0]["id"]))
	check(rm["ok"], "retirer le sol du rez-de-chaussée (sans étage) fonctionne")
	var rm2 := ConstructionOps.remove_element(up["cand"], int(up["cand"].of_type("floor", 0)[0]["id"]))
	check(not rm2["ok"], "retirer le sol du rez-de-chaussée sous un étage est refusé")
	var rf := ConstructionOps.add_roof(up["cand"], int(up["cand"].of_type("wall", 0)[0]["id"]))
	check(not rf["ok"], "toit refusé sur un niveau qui porte un étage")

func _format_checks() -> void:
	var c: Construction = ConstructionOps.add_room(Construction.new(), 0, Vector2i(4, 4), Vector2i(12, 10), 2.5, "E")["cand"]
	c = ConstructionOps.add_opening(c, int(c.of_type("wall")[0]["id"]), "window", 5.0)["cand"] if false else c
	c = ConstructionOps.add_roof(c, int(c.of_type("wall")[0]["id"]))["cand"]
	c.name = "Essai"
	var n := c.normalized()
	var bb := n.bbox_m()
	check(is_equal_approx(bb.position.x, -0.1) and is_equal_approx(bb.position.y, -0.1), "export normalisé : coin minimum à l'origine")
	var j := n.to_json()
	var r := Construction.from_json(j)
	check(r["ok"] and r["construction"].signature() == n.signature(), "export puis relecture : construction identique")
	var back: Construction = r["construction"]
	check(back.count_openings() == c.count_openings() and back.of_type("roof").size() == 1 and back.level_count() == 1, "ouvertures, toit et niveaux conservés")
	var bad := Construction.from_json("{pas du json")
	check(not bad["ok"] and "illisible" in String(bad["error"]), "fichier corrompu : erreur expliquée")
	var d := n.to_dict()
	d["format"] = "eclats-carte"
	check(not Construction.from_dict(d)["ok"] and "carte" in String(Construction.from_dict(d)["error"]), "un fichier de carte n'est pas pris pour une maison")
	d = n.to_dict()
	d["version"] = 99
	check(not Construction.from_dict(d)["ok"], "version plus récente refusée avec explication")
	d = n.to_dict()
	(d["elements"] as Array)[1]["ops"] = [{"id": 99, "k": "door", "at": 0, "w": 2}]
	check(not Construction.from_dict(d)["ok"], "ouverture incompatible dans un fichier : refusée")
