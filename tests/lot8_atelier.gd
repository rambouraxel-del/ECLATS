extends RefCounted
## Atelier de construction (Lot 8), sans rendu : BuildMode piloté par clics logiques sur une salle grise réelle (collisions comprises).

static func run(t: SceneTree) -> void:
	print("-- atelier : mode construction --")
	var lab := LabWorld.new()
	t.root.add_child(lab)
	lab.setup("room")
	var cam := Camera3D.new()
	t.root.add_child(cam)
	cam.global_position = Vector3(0, 3.6, 9)
	var player := Node3D.new()
	t.root.add_child(player)
	var b := BuildMode.new()
	t.root.add_child(b)
	b.setup(lab, cam, player, null, null)
	b.active = true
	await t.physics_frame
	var gy := lab.ground_y(0.0, 0.0)

	# --- sol 1,50 × 1,50 m : aperçu, coût, annulation puis confirmation
	b.set_tool("sol")
	_aim(b, 0, 0, gy)
	b.click()
	_aim(b, 3, 3, gy)
	t.check(b.has_corner and b.live.has("ok") and b.live["ok"] and b.live["delta"] == 3, "sol : l'aperçu en direct annonce 3 unités pour 1,50 × 1,50 m")
	t.check("1,50 × 1,50 m" in String(b.live["text"]) and "coût 3 unités" in String(b.live["text"]), "l'aperçu affiche les dimensions et le coût (« %s »)" % b.live["text"])
	b.click()
	t.check(not b.pending.is_empty() and b.stock == 200, "second clic : aperçu verrouillé, rien n'est débité")
	b.cancel_preview()
	t.check(b.pending.is_empty() and b.stock == 200 and b.c.is_empty(), "aperçu annulé avant confirmation : stock inchangé, rien posé")
	b.click()
	_aim(b, 3, 3, gy)
	b.click()
	var r := b.confirm()
	t.check(r["ok"] and b.stock == 197 and b.c.elements.size() == 1, "confirmation : 3 unités débitées (stock 197)")
	b.undo()
	t.check(b.stock == 200 and b.c.is_empty(), "Ctrl+Z : le sol disparaît et les 3 unités sont rendues")

	# --- stock insuffisant : refus, rien n'est débité
	b.stock = 5
	b.set_tool("mur")
	_aim(b, -4, 0, gy)
	b.click()
	_aim(b, 6, 0, gy)
	t.check(not b.live["ok"] and "Stock insuffisant" in String(b.live["reasons"][0]), "stock insuffisant : aperçu refusé et expliqué (%s)" % String(b.live["reasons"][0]).left(60))
	b.click()
	t.check(b.pending.is_empty() and b.stock == 5 and b.c.is_empty(), "pose refusée : rien posé, rien débité")
	b.cancel_preview()
	b.stock = Construction.TARIFF * 0 + BuildMode.DEMO_STOCK

	# --- mur de 4 m, porte, fenêtre : vraies découpes dans les collisions
	b.set_tool("mur")
	_aim(b, -6, 0, gy)
	b.click()
	_aim(b, 6, 0, gy)
	b.click()
	b.confirm()
	t.check(b.c.of_type("wall").size() == 1 and b.stock == 200 - 15, "mur de 6 m × 2,5 m posé (15 unités)")
	await t.physics_frame
	var probe := func(x: float, y: float) -> bool:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.28
		cap.height = 1.7
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y, 0.0))
		q.collision_mask = 1
		var hits := lab.get_world_3d().direct_space_state.intersect_shape(q, 4)
		var n := 0
		for h in hits:
			if h["collider"] is StaticBody3D and (h["collider"] as Node).name == "Collisions":
				n += 1
		return n > 0
	var mid_y := b.c.level_y(0) + 0.95
	t.check(probe.call(0.0, mid_y), "mur plein : le joueur est arrêté au milieu du mur")
	b.set_tool("porte")
	cam.global_position = Vector3(0.0, 1.6, 4.0)
	b.aim_override = Vector3(0.0, b.c.level_y(0) + 1.0, 0.0)
	b._process(0.0)
	t.check(b.live.has("ok") and b.live["ok"] and "Porte 1,0 × 2,0 m" in String(b.live["text"]), "porte : l'aperçu montre la découpe et le coût (« %s »)" % String(b.live.get("text", "")))
	b.click()
	b.confirm()
	await t.physics_frame
	t.check(b.c.count_openings() == 1 and b.stock == 200 - 15 - 4, "porte posée au point visé : 4 unités")
	t.check(not probe.call(0.0, mid_y), "collisions mises à jour : le passage de la porte est libre")
	t.check(probe.call(1.6, mid_y), "à côté de la porte, le mur arrête toujours le joueur")
	b.set_tool("fenetre")
	b.aim_override = Vector3(-2.0, b.c.level_y(0) + 1.0, 0.0)
	b._process(0.0)
	b.click()
	b.confirm()
	t.check(b.c.count_openings() == 2, "fenêtre posée dans le même mur")
	# --- modification qui rend une ouverture incompatible : refusée, construction intacte
	b.set_tool("modifier")
	b.aim_override = Vector3(2.0, b.c.level_y(0) + 1.0, 0.0)
	b._process(0.0)
	b.click()
	t.check(b.sel_id >= 0, "outil Modifier : le mur est sélectionné")
	var sig := b.c.signature()
	var stock_before := b.stock
	b.edit_end = "A"
	b.nudge_end(-1)
	t.check(b.pending.is_empty() or b.c.signature() == sig, "raccourcir le mur de 1,5 m par le début : la fenêtre ne tiendrait plus")
	t.check(b.c.signature() == sig and b.stock == stock_before, "refus : construction et stock intacts")
	t.check(not b._refusal.is_empty() and "ne tiendrait plus" in String(b._refusal["reasons"][0]), "le refus est expliqué dans l'aperçu (« %s »)" % String(b._refusal.get("reasons", [""])[0]).left(70))
	b.edit_end = "B"
	b.nudge_end(1)
	b.confirm()
	t.check(Construction.wall_len_u(b.c.of_type("wall")[0]) == 13 and b.stock == stock_before - 2, "prolonger le mur de 0,5 m : seule la différence est payée (2 unités : 15 → 17)")
	# --- pièce rapide, toit, étage
	b.leave_state_reset_for_test()
	b.stock = 200
	b.set_tool("piece")
	_aim(b, -4, 6, gy)
	b.click()
	_aim(b, 4, 12, gy)
	t.check(b.live["ok"] and "porte côté sud" in String(b.live["text"]), "pièce : plancher + 4 murs + porte côté sud (« %s »)" % String(b.live["text"]).left(80))
	b.click()
	b.confirm()
	t.check(b.c.of_type("wall").size() == 4 and b.c.of_type("floor").size() == 1, "pièce posée : 4 murs et un plancher modifiables")
	await t.physics_frame
	b.set_tool("toit")
	cam.global_position = Vector3(0.0, 1.6, 10.0)
	b.aim_override = Vector3(0.0, b.c.level_y(0) + 1.0, 6.0)
	b._process(0.0)
	t.check(b.live.has("ok") and b.live["ok"], "toit : l'aperçu s'ajuste à l'emprise des murs (« %s »)" % String(b.live.get("text", "")))
	b.click()
	b.confirm()
	t.check(b.c.of_type("roof").size() == 1, "toit posé")
	# sélecteur d'étage
	b.set_level(1)
	b.undo()
	b.set_level(1)
	t.check(b.level == 1, "sélecteur d'étage : niveau 1 atteint")
	b.set_tool("sol")
	cam.global_position = Vector3(0.0, 4.5, 10.0)
	b.aim_override = Vector3(-2.0, b.c.level_y(1), 3.0)
	b._process(0.0)
	b.click()
	b.aim_override = Vector3(2.0, b.c.level_y(1), 6.0)
	b._process(0.0)
	b.click()
	b.confirm()
	t.check(b.c.slabs(1).size() == 1, "sol d'étage posé au niveau 1")
	b.set_level(0)
	var fade_ok := false
	var lm: Dictionary = b.node.get_meta("level_mats", {})
	for m: StandardMaterial3D in lm.get(1, []):
		fade_ok = m.albedo_color.a < 0.5
	t.check(fade_ok, "les autres niveaux sont atténués quand le niveau 0 est actif")
	# --- enregistrement
	var sr := b.save_as("Essai atelier")
	t.check(sr["ok"] and FileAccess.file_exists(b.file_path_for("Essai atelier")), "enregistrement dans le dossier des maisons")
	var sig2 := b.c.normalized().signature()
	var back := Construction.load_file(b.file_path_for("Essai atelier"))
	t.check(back["ok"] and back["construction"].signature() == sig2, "la maison enregistrée se relit à l'identique")
	b.stock = 200
	b.queue_free()
	lab.queue_free()
	cam.queue_free()
	player.queue_free()

static func _aim(b: BuildMode, ux: int, uz: int, y: float) -> void:
	b.aim_override = Vector3(float(ux) * 0.5, y, float(uz) * 0.5)
	b._process(0.0)
