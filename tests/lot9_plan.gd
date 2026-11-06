extends RefCounted
## Placement automatique d'une habitation sur un plan (Lot 9), sans rendu.

static func run(t: SceneTree) -> void:
	print("-- plan : placement automatique --")
	for sd in [21, 64, 7]:
		var doc := MapDoc.from_plan(PlanGenerator.generate(sd, 56, 48))
		var top0 := doc.field.top.duplicate()
		var r := doc.auto_place_dwelling("cabane", sd, Vector2(5.0, 4.5), {}, false)
		t.check(bool(r["ok"]), "graine %d : parcelle compatible trouvée pour la cabane (parcelle « %s », porte côté %s)" % [sd, r.get("parcel", "?"), r.get("door_side", "?")])
		t.check(doc.field.top == top0 and doc.plan.houses.is_empty(), "graine %d : chercher ne pose rien" % sd)
		var r2 := doc.auto_place_dwelling("cabane", sd, Vector2(5.0, 4.5), {}, false)
		t.check(r["pos"] == r2["pos"] and r["yaw"] == r2["yaw"], "graine %d : même recherche, même résultat (déterminisme)" % sd)
	var doc := MapDoc.from_plan(PlanGenerator.generate(21, 56, 48))
	var top0 := doc.field.top.duplicate()
	var res := doc.auto_place_dwelling("deux_pieces", 4, Vector2(8.0, 7.0), {}, true)
	t.check(res["ok"] and doc.plan.houses.size() == 1 and doc.undo_stack.size() == 1, "habitation « deux pièces » posée automatiquement (une opération) : %s" % doc.message.left(100))
	var lk: Dictionary = res["placed"]["link"]
	t.check(float(lk["length"]) <= HousePad.LINK_MAX_M and float(lk["grade"]) <= HousePad.LINK_GRADE, "porte raccordée au chemin : %s m, %d %%" % [Construction.fm(float(lk["length"])), roundi(float(lk["grade"]) * 100.0)])
	# l'orientation retenue est la meilleure : aucune autre orientation au même endroit n'a un raccord plus court
	var model := Construction.from_dict(doc.plan.houses[0]["model"])["construction"] as Construction
	doc.undo()
	var best_len := float(lk["length"])
	var shorter := 0
	for yaw in 4:
		var ev := doc.evaluate_house(model, res["pos"], yaw)
		if ev["ok"] and float(ev["link"]["length"]) < best_len - 0.05:
			shorter += 1
	t.check(shorter == 0, "orientation choisie d'après l'accès : aucune autre orientation de cet emplacement n'est mieux raccordée")
	t.check(doc.field.top == top0, "Ctrl+Z : terrain restauré")
	# refus : toutes les parcelles protégées par le masque
	var pdoc := MapDoc.from_plan(PlanGenerator.generate(21, 56, 48))
	pdoc.begin_op("masque")
	for i in pdoc.plan.layers.mask.size():
		pdoc.plan.layers.mask[i] = 1
	pdoc.finish_op(false)
	var depth := pdoc.undo_stack.size()
	var top_p := pdoc.field.top.duplicate()
	var rp := pdoc.auto_place_dwelling("cabane", 1, Vector2(5.0, 4.5), {}, true)
	t.check(not rp["ok"] and "zone protégée" in String(rp["reasons"][0]) and "Rien n'est posé" in String(rp["reasons"][0]), "tout est protégé : refus expliqué (« %s »)" % String(rp["reasons"][0]).left(110))
	t.check(pdoc.plan.houses.is_empty() and pdoc.field.top == top_p and pdoc.undo_stack.size() == depth, "refus : rien n'est posé ni modifié (placement non forcé)")
	# refus : emprise trop petite pour la plus petite habitation (le générateur l'explique, rien n'est cherché ni posé)
	var rb := doc.auto_place_dwelling("auto", 1, Vector2(3.0, 3.0), {}, true)
	t.check(not rb["ok"] and doc.plan.houses.is_empty() and "Emprise trop petite" in String(rb["reasons"][0]), "emprise de 3 × 3 m : refus expliqué, rien n'est forcé")
	# refus : plan sans parcelle
	var np := PlanGenerator.generate(21, 56, 48)
	np.zones = np.zones.filter(func(z) -> bool: return z["kind"] != "plateau" and z["kind"] != "pelouse")
	var ndoc := MapDoc.from_plan(np)
	var rn := ndoc.auto_place_dwelling("cabane", 1, Vector2(5.0, 4.5), {}, true)
	t.check(not rn["ok"] and "aucune parcelle" in String(rn["reasons"][0]), "plan sans plateau ni pelouse : refus expliqué")
	# la maison posée automatiquement est visitable après export / réouverture
	var d3 := MapDoc.from_plan(PlanGenerator.generate(64, 56, 48))
	var r3 := d3.auto_place_dwelling("en_L", 3, Vector2(10.0, 9.0), {}, true)
	if not bool(r3["ok"]):
		r3 = d3.auto_place_dwelling("deux_pieces", 3, Vector2(8.0, 6.5), {}, true)
	t.check(bool(r3["ok"]), "graine 64 : une habitation tient quelque part (%s)" % String(r3.get("gen", {}).get("variant", "?")))
	var path := "user://cartes/essai_lot9.eclats-carte.json"
	d3.export_to(path)
	var d4 := MapDoc.new()
	d4.open_from(path)
	t.check(d4.plan.houses.size() == 1 and d4.field.top == d3.field.top, "export puis réouverture : habitation et terrain identiques")
