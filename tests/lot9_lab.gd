extends RefCounted
## Habitations et composition dans le laboratoire (Lot 9), sans rendu.

static func _make(t: SceneTree, kind: String) -> LabWorld:
	var l := LabWorld.new()
	t.root.add_child(l)
	l.setup(kind)
	return l

static func _same(a: LabWorld, snap: Dictionary) -> bool:
	return a.field.top == snap["top"] and a.field.zone == snap["zone"] and a.field.material == snap["mat"] and a.occ.tag == snap["tag"] and a.occ.owner == snap["own"] and a.occ.items.size() == int(snap["items"])

static func run(t: SceneTree) -> void:
	print("-- laboratoire : habitations et composition --")
	var room := _make(t, "room")
	var isl := _make(t, "island")
	var rect_room := Rect2(Vector2(-4.0, -4.5), Vector2(7.5, 9.0))
	var rect_isl := Rect2(Vector2(1.0, -4.5), Vector2(7.5, 9.0))
	for v in ["cabane", "deux_pieces", "en_L"]:
		var s0 := room.snapshot()
		var op := room.prepare_dwelling(rect_room, {"variante": v, "seed": 7, "yaw": 0})
		t.check(bool(op["ok"]) and _same(room, s0), "salle : %s — aperçu valide, terrain intact" % DwellingGenerator.variant_name(v))
	# même recette sur les deux terrains : même habitation ; le raccord au sol n'existe que sur la pente
	var op_r := room.prepare_dwelling(rect_room, {"variante": "en_L", "seed": 7, "yaw": 0})
	var op_i := isl.prepare_dwelling(rect_isl, {"variante": "en_L", "seed": 7, "yaw": 0})
	t.check(bool(op_r["ok"]) and bool(op_i["ok"]) and (op_r["model"] as Construction).signature() == (op_i["model"] as Construction).signature(), "même recette sur la salle et sur l'île : même habitation")
	t.check(bool(op_i["ok"]) and int(op_i["terrain_cells"]) > int(op_r["terrain_cells"]) and int(op_i["terrain_cells"]) > 200, "sur la pente : %d colonnes raccordées contre %d dans la salle" % [op_i["terrain_cells"], op_r["terrain_cells"]])
	# application et annulation sur la pente
	var snap := isl.snapshot()
	if not bool(op_i["ok"]):
		print("   refus île : ", op_i["reasons"])
	var r := await isl.apply(op_i)
	t.check(r["ok"] and isl.stack.size() == 1 and not _same(isl, snap), "habitation posée sur la pente")
	var hr := isl.field.height_range(op_i["rect"])
	t.check(hr.x == hr.y, "plateforme plate sous l'habitation")
	var node: Node3D = null
	for ch in isl.objects_root.get_children():
		if String(ch.name).begins_with("habitation"):
			node = ch
	t.check(node != null and node.get_node_or_null("Collisions") != null, "l'habitation a ses collisions réelles")
	await isl.undo()
	t.check(_same(isl, snap) and isl.objects_root.get_child_count() == 0, "Ctrl+Z : habitation retirée, relief, réservations et objets restaurés")
	# refus : emprise trop petite, et emprise hors de l'île
	var snap2 := isl.snapshot()
	var bad := isl.prepare_dwelling(Rect2(Vector2(1, -4), Vector2(2.5, 2.5)), {"variante": "auto", "seed": 1, "yaw": 0})
	t.check(not bad["ok"] and "Emprise trop petite" in String(bad["reasons"][0]) and _same(isl, snap2), "emprise 2,5 × 2,5 m : refus expliqué, terrain intact")
	var out := isl.prepare_dwelling(Rect2(Vector2(60, 60), Vector2(9, 8)), {"variante": "cabane", "seed": 1, "yaw": 0})
	t.check(not out["ok"] and _same(isl, snap2), "emprise hors de l'île : refus, terrain intact")
	# ---- composition marché + végétation sur une zone peinte
	var cells := _disc(isl, Vector2(-14.0, 6.0), 4.2)
	var s3 := isl.snapshot()
	var c1 := isl.prepare_composition(cells, {"seed": 7, "etals": 3, "vegetation": 60})
	t.check(bool(c1["ok"]) and _same(isl, s3), "composition : aperçu prêt (%s), monde intact" % String(c1["summary"]).left(80))
	var cn: Dictionary = c1["counts"]
	t.check(cn["étal"] >= 2 and cn["arbre"] >= 1 and (cn["caisses"] + cn["tonneaux"]) >= 1, "marché (étals, caisses, tonneaux) et végétation (arbres) présents")
	var painted := {}
	for i in cells:
		painted[int(i)] = true
	var all_on := true
	for it in c1["items"]:
		var p: Vector3 = (it["res"] as PlacementResult).pos if String(it["kind"]) == "prop" else ((it["op"]["res"]) as PlacementResult).pos
		var cc := isl.field.col_of_m(p.x, p.z)
		all_on = all_on and painted.has(isl.field.idx(cc.x, cc.y))
	t.check(all_on, "tous les objets sont posés sur la zone peinte")
	var c1b := isl.prepare_composition(cells, {"seed": 7, "etals": 3, "vegetation": 60})
	t.check(_pos_list(c1) == _pos_list(c1b), "même graine, mêmes réglages : même composition")
	var c2 := isl.prepare_composition(cells, {"seed": 7, "etals": 1, "vegetation": 0})
	t.check(bool(c2["ok"]) and c2["counts"]["étal"] == 1 and c2["counts"]["arbre"] == 0, "réglages ajustables : 1 étal, aucune végétation (%s)" % String(c2["summary"]).left(70))
	var c3 := isl.prepare_composition(cells, {"seed": 8, "etals": 3, "vegetation": 60})
	t.check(_pos_list(c3) != _pos_list(c1), "une autre graine change la disposition")
	# application = UNE opération ; annulation en une fois
	var depth := isl.stack.size()
	var snap4 := isl.snapshot()
	var ra := await isl.apply(c1)
	t.check(ra["ok"] and isl.stack.size() == depth + 1, "composition appliquée : une seule opération (%d objets)" % (c1["items"] as Array).size())
	var n_nodes := isl.objects_root.get_child_count()
	t.check(n_nodes >= (c1["items"] as Array).size() + 1 and isl.occ.items.size() >= (c1["items"] as Array).size(), "objets et collisions posés (%d nœuds, %d objets réservés)" % [n_nodes, isl.occ.items.size()])
	await isl.undo()
	t.check(_same(isl, snap4) and isl.objects_root.get_child_count() == 0 and isl.stack.size() == depth, "Ctrl+Z : toute la composition disparaît en une opération")
	# refus : zone trop petite
	var tiny := isl.prepare_composition(_disc(isl, Vector2(-14.0, 6.0), 0.8), {"seed": 1})
	t.check(not tiny["ok"] and "Zone trop petite" in String(tiny["reasons"][0]), "zone trop petite : refus expliqué")
	# commande texte
	var pc := LabCommands.parse("/generer composition --etals 2 --vegetation 30 --graine 4 --rayon 2 --trace 0,0;1,0")
	t.check(pc["ok"] and pc["gen"] == "composition" and pc["opts"]["etals"] == 2 and pc["opts"]["vegetation"] == 30, "commande /generer composition lue")
	var rec := LabCommands.recipe_string({"gen": "composition", "opts": {"seed": 4, "etals": 2, "vegetation": 30, "rayon": 2.0, "trace": [Vector2(0, 0), Vector2(1, 0)]}})
	t.check(rec == "/generer composition --graine 4 --etals 2 --vegetation 30 --rayon 2 --trace 0,0;1,0", "recette de composition : %s" % rec)
	room.queue_free()
	isl.queue_free()

static func _disc(l: LabWorld, c: Vector2, r: float) -> Array:
	var out: Array = []
	var lo := l.field.col_of_m(c.x - r, c.y - r)
	var hi := l.field.col_of_m(c.x + r, c.y + r)
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if l.field.has_ground(cx, cz) and l.field.center_m(cx, cz).distance_to(c) <= r:
				out.append(l.field.idx(cx, cz))
	return out

static func _pos_list(op: Dictionary) -> Array:
	var out: Array = []
	for it in op["items"]:
		var res: PlacementResult = (it["res"] as PlacementResult) if String(it["kind"]) == "prop" else (it["op"]["res"] as PlacementResult)
		out.append(snappedf(res.pos.x, 0.01))
		out.append(snappedf(res.pos.z, 0.01))
	return out
