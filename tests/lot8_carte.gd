extends RefCounted
## Maisons sur une carte (Lot 8), sans rendu : format versionné, implantation sur une pente, raccord seuil–chemin, masque,
## refus sans effet, annulation, export / réouverture.

static func _first_ok(doc: MapDoc, model: Construction) -> Dictionary:
	var z := doc.plan.zone_by_id("plateau")
	for r in [4.0, 7.0, 10.0, 13.0]:
		for yaw in 4:
			for k in 16:
				var p: Vector2 = (z["c"] as Vector2) + Vector2.from_angle(float(k) * TAU / 16.0) * r
				var res := doc.evaluate_house(model, p, yaw)
				if res["ok"]:
					return {"pos": p, "yaw": yaw, "res": res}
	return {}

static func run(t: SceneTree) -> void:
	print("-- maisons sur une carte --")
	var model: Construction = Construction.load_file("res://assets/maisons/maison_exemple.eclats-maison.json")["construction"]
	t.check(model.count_openings() == 3 and model.of_type("roof").size() == 1, "maison d'exemple : 3 ouvertures et un toit")
	var plan := PlanGenerator.generate(21, 56, 48)
	var doc := MapDoc.from_plan(plan)
	var top0 := doc.field.top.duplicate()
	var mat0 := doc.field.material.duplicate()
	var found := _first_ok(doc, model)
	t.check(not found.is_empty(), "une parcelle compatible existe près du plateau (graine 21)")
	var pos: Vector2 = found["pos"]
	var yaw: int = found["yaw"]
	var ev: Dictionary = found["res"]
	t.check(doc.field.top == top0 and doc.field.material == mat0 and doc.undo_stack.is_empty() and doc.plan.houses.is_empty(), "l'aperçu ne change rien (relief, matières, pile d'annulation, maisons)")
	var door: Vector2 = ev["door"]
	t.check(ev["link"].has("length") and float(ev["link"]["grade"]) <= 0.30 and float(ev["link"]["length"]) <= HousePad.LINK_MAX_M, "raccord seuil–chemin : %s m, pente %d %%" % [Construction.fm(float(ev["link"]["length"])), roundi(float(ev["link"]["grade"]) * 100.0)])
	# --- refus : hors de l'île
	var out := doc.evaluate_house(model, Vector2(200, 200), 0)
	t.check(not out["ok"] and "sort de l'île" in String(out["reasons"][0]), "hors de l'île : refus expliqué (« %s »)" % String(out["reasons"][0]).left(50))
	# --- refus : aucun chemin assez proche (on teste au bord de l'île, loin des chemins)
	var far_msg := ""
	for k in 40:
		var q: Vector2 = Vector2.from_angle(float(k) * 0.157) * 22.0
		var r2 := doc.evaluate_house(model, q, 0)
		if not r2["ok"] and "Aucun chemin à moins de" in String(r2["reasons"][0]):
			far_msg = String(r2["reasons"][0])
			break
	t.check(far_msg != "", "trop loin d'un chemin : refus expliqué (« %s »)" % far_msg.left(70))
	# --- refus : zone protégée (masque peint sous la parcelle)
	var mask_doc := MapDoc.from_plan(PlanGenerator.generate(21, 56, 48))
	mask_doc.begin_op("masque")
	var rc: Rect2 = ev["rect_m"]
	var c0 := mask_doc.field.col_of_m(rc.position.x + rc.size.x * 0.3, rc.position.y + rc.size.y * 0.3)
	for dz in 6:
		for dx in 6:
			var i := mask_doc.field.idx(c0.x + dx, c0.y + dz)
			mask_doc.plan.layers.mask[i] = 1
	mask_doc.finish_op(false)
	var depth0 := mask_doc.undo_stack.size()
	var top_m := mask_doc.field.top.duplicate()
	var rm := mask_doc.place_house(model, pos, yaw)
	t.check(not rm["ok"] and "protégée" in String(rm["reasons"][0]), "zone protégée sous la maison : refus expliqué (« %s »)" % String(rm["reasons"][0]).left(60))
	t.check(mask_doc.field.top == top_m and mask_doc.plan.houses.is_empty() and mask_doc.undo_stack.size() == depth0 and mask_doc.plan.layers.count_delta() == 0, "refus : relief, couches, maisons et annulation inchangés")
	# --- pose
	var fp0 := PlanTerrain.fingerprint(doc.field)
	var placed := doc.place_house(model, pos, yaw)
	t.check(placed["ok"] and doc.plan.houses.size() == 1 and doc.undo_stack.size() == 1, "maison posée : une opération annulable")
	var changed := 0
	var outside := 0
	var rect := (placed["rect_m"] as Rect2).grow(HousePad.YARD * 0.2 + 5.5)
	var lk: Dictionary = placed["link"]
	for i in doc.field.top.size():
		if doc.field.top[i] != top0[i]:
			changed += 1
			var c := doc.field.center_m(i % doc.field.n, i / doc.field.n)
			var near_link := false
			if not lk.is_empty():
				near_link = c.distance_to(_seg(c, lk["from"], lk["to"])) < 6.0
			if not rect.has_point(c) and not near_link:
				outside += 1
	t.check(changed > 50 and outside == 0, "le terrain n'est modifié que localement : %d colonnes, %d hors de la parcelle et du raccord" % [changed, outside])
	# le terrain sous la maison est plat
	var rr: Rect2i = placed["rect"]
	var hr := doc.field.height_range(rr)
	t.check(hr.x == hr.y, "plateforme plate sous l'emprise (fondations adaptées à la pente)")
	var again := doc.evaluate_house(model, pos, yaw)
	t.check(not again["ok"], "une seconde maison au même endroit est refusée (emprise occupée)")
	# le raccord rejoint le chemin sans marche
	var q: Vector2 = lk["to"]
	var d0: Vector2 = lk["from"]
	var worst := 0.0
	var prev := doc.field.ground_at_m(d0.x, d0.y)
	for k in range(1, 41):
		var p := d0.lerp(q, float(k) / 40.0)
		var g := doc.field.ground_at_m(p.x, p.y)
		worst = maxf(worst, absf(g - prev))
		prev = g
	t.check(not is_nan(prev) and worst <= 0.41, "raccord : aucune marche de plus de 40 cm entre le seuil et le chemin (%.2f m)" % worst)
	# --- Ctrl+Z
	doc.undo()
	t.check(doc.plan.houses.is_empty() and doc.field.top == top0 and doc.field.material == mat0, "Ctrl+Z : la maison disparaît et le terrain est restauré à l'identique")
	t.check(PlanTerrain.fingerprint(doc.field) == fp0, "empreinte du relief identique après annulation")
	# --- export / réouverture
	var p2 := doc.place_house(model, pos, yaw)
	t.check(p2["ok"], "maison reposée")
	var path := "user://cartes/essai_lot8.eclats-carte.json"
	var ex := doc.export_to(path)
	t.check(ex["ok"], "carte exportée avec sa maison")
	var top_saved := doc.field.top.duplicate()
	var doc2 := MapDoc.new()
	var op := doc2.open_from(path)
	t.check(op["ok"] and doc2.plan.houses.size() == 1, "carte rouverte : la maison est là")
	t.check(doc2.field.top == top_saved, "terrain identique colonne pour colonne après réouverture")
	var m2 := Construction.from_dict(doc2.plan.houses[0]["model"])["construction"] as Construction
	t.check(m2.count_openings() == 3 and m2.of_type("roof").size() == 1 and m2.signature() == model.signature(), "la maison rouverte garde ses 3 ouvertures et son toit")
	t.check(doc2.plan.houses[0]["pos"] == p2["pos"] and int(doc2.plan.houses[0]["yaw"]) == yaw and absf(float(doc2.plan.houses[0]["ground_m"]) - float(p2["ground_m"])) < 0.002, "position, orientation et niveau du sol conservés")
	# --- compatibilité : une carte v1 (sans maison) se rouvre
	var d1 := PlanGenerator.generate(5, 56, 48).to_dict()
	d1["version"] = 1
	t.check(IslandPlan.from_dict(d1)["ok"], "une carte v1 (Lot 7) se rouvre sans changement")
	d1["version"] = 99
	t.check(not IslandPlan.from_dict(d1)["ok"], "une carte plus récente que le jeu est refusée avec explication")
	var bad := doc.plan.to_dict()
	(bad["maisons"] as Array)[0]["model"]["elements"] = [{"t": "mur"}]
	var bres := IslandPlan.from_dict(bad)
	t.check(not bres["ok"] and "maison" in String(bres["error"]), "modèle de maison corrompu dans une carte : erreur expliquée (« %s »)" % String(bres["error"]).left(70))

static func _seg(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	return a + ab * clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
