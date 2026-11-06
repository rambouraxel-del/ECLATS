extends Node
## Essai JOUÉ + captures du PLACEMENT D'UNE MAISON SUR UNE CARTE (Lot 8, étape 2), dans le VRAI jeu lancé au menu :
##   godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/lot8_recette_maison.gd
## menu → éditeur de carte → plan généré (graine 21) → outil Maisons : aperçu, orientation (R), refus sur zone protégée,
## pose, Ctrl+Z, nouvelle pose, export → « Vérifier en 3D » (marche du chemin jusque dans la maison) → nouvelle session, réouverture, même marche.
const OUT := "/tmp/claude-0/-home-user/a63a7b17-b085-5a47-af76-319612b62b36/scratchpad/l8"
const DT := 1.0 / 60.0

var ed: MapEditor
var cv: PlanCanvas
var isl: Node
var report := {"controles": []}

func _check(cond: bool, label: String) -> void:
	report["controles"].append({"ok": cond, "controle": label})
	print(("  OK    " if cond else "  ÉCHEC ") + label)

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("saved ", name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _key(code: int, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame

func _sp(world: Vector2) -> Vector2:
	return cv.global_position + cv.w2s(world)

func _mouse(world: Vector2, button := 0, pressed := false) -> void:
	if button == 0:
		var m := InputEventMouseMotion.new()
		m.position = _sp(world)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
		Input.parse_input_event(m)
	else:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = _sp(world)
		e.global_position = e.position
		e.button_mask = (1 << (button - 1)) if pressed else 0
		Input.parse_input_event(e)
	await get_tree().process_frame

func _click(world: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _mouse(world)
	await _mouse(world, button, true)
	await _mouse(world, button, false)
	await get_tree().process_frame

func _drag(pts: Array) -> void:
	await _mouse(pts[0])
	await _mouse(pts[0], MOUSE_BUTTON_LEFT, true)
	for i in range(1, pts.size()):
		await _mouse(pts[i])
	await _mouse(pts[pts.size() - 1], MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame

func _wait_scene(cls: String) -> Node:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 600000:
		var s := get_tree().current_scene
		if s != null and s.name == cls and (cls != "MapIsland" or bool(s.get("ready_to_play"))):
			await _frames(6)
			return s
		await get_tree().process_frame
		OS.delay_msec(5)
	return null

func _button(root: Node, text_start: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if (c as Button).text.begins_with(text_start):
			return c as Button
	return null

func _press_button(root: Node, text_start: String) -> bool:
	var b := _button(root, text_start)
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	await _frames(3)
	return true

func _look(center: Vector2, ppm: float) -> void:
	cv.view_center = center
	cv.px_per_m = ppm
	cv.queue_redraw()
	await _frames(2)

func _open_editor_from_menu() -> void:
	var menu := get_tree().current_scene
	menu.call("show_page", "dev")
	await _frames(3)
	for bt in menu.find_children("*", "Button", true, false):
		if (bt as Button).text.begins_with("Éditeur de carte"):
			(bt as Button).pressed.emit()
			break
	ed = await _wait_scene("MapEditor") as MapEditor
	cv = ed.canvas
	await _frames(10)

## Parcelle compatible la plus proche du plateau (même recherche que les tests).
func _find_spot(doc: MapDoc, model: Construction) -> Dictionary:
	var z := doc.plan.zone_by_id("plateau")
	for r in [4.0, 7.0, 10.0, 13.0]:
		for yaw in 4:
			for k in 16:
				var p: Vector2 = (z["c"] as Vector2) + Vector2.from_angle(float(k) * TAU / 16.0) * r
				p = Vector2(snappedf(p.x, 0.1), snappedf(p.y, 0.1))
				if doc.evaluate_house(model, p, yaw)["ok"]:
					return {"pos": p, "yaw": yaw}
	return {}

func _pos2(ex: Node3D) -> Vector2:
	return Vector2(ex.global_position.x, ex.global_position.z)

func _walk_to(ex: Explorer, target: Vector2, tol: float, label: String) -> bool:
	ex.auto_active = true
	var t := 0.0
	var stuck := 0.0
	var check_pos := _pos2(ex)
	var check_t := 0.0
	var falls0: int = isl.get("falls")
	while _pos2(ex).distance_to(target) > tol:
		ex.auto_dir = (target - _pos2(ex)).normalized()
		await get_tree().physics_frame
		t += DT
		check_t += DT
		if int(isl.get("falls")) != falls0:
			report["defauts"] = report.get("defauts", 0) + 1
			ex.auto_dir = Vector2.ZERO
			return false
		if check_t >= 1.0:
			if check_pos.distance_to(target) - _pos2(ex).distance_to(target) < 0.3:
				stuck += check_t
				ex.auto_jump = true
			else:
				stuck = 0.0
			check_t = 0.0
			check_pos = _pos2(ex)
		if stuck > 5.0 or t > 90.0:
			print("   blocage vers ", label, " en ", _pos2(ex))
			ex.auto_dir = Vector2.ZERO
			return false
	ex.auto_dir = Vector2.ZERO
	return true

func _probe(world: Vector3, r := 0.12) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, world)
	q.collision_mask = 1
	for h in isl.get("lab").get_world_3d().direct_space_state.intersect_shape(q, 8):
		if (h["collider"] as Node).name == "Collisions":
			return true
	return false

## Contrôles 3D d'une maison posée : ouvertures vides, murs pleins, marche du chemin jusqu'à l'intérieur.
func _visit(tag: String, shots: bool) -> void:
	var plan: IslandPlan = isl.get("plan")
	var h: Dictionary = plan.houses[0]
	var model: Construction = Construction.from_dict(h["model"])["construction"]
	_check((isl.get("house_nodes") as Array).size() == 1, "%s : la maison est dans l'île 3D" % tag)
	var fp := HousePad.footprint(model)
	var pos: Vector2 = h["pos"]
	var yaw: int = h["yaw"]
	var gm: float = h["ground_m"]
	var c: Vector2 = fp["center"]
	var door_free := 0
	var win_free := 0
	var wall_solid := 0
	for w in model.of_type("wall", 0):
		for o in w["ops"]:
			var mid := (float(o["at"]) + float(o["w"]) * 0.5) * Construction.U
			var line := float(Construction.wall_line(w)) * Construction.U
			var loc := Vector2(mid, line) if Construction.wall_axis(w) == 0 else Vector2(line, mid)
			var wp := pos + HousePad.rot(loc - c, yaw)
			var hy := gm + 0.2 + (1.0 if String(o["k"]) == "door" else Construction.WIN_SILL + Construction.WIN_H * 0.5)
			if not _probe(Vector3(wp.x, hy, wp.y)):
				if String(o["k"]) == "door":
					door_free += 1
				else:
					win_free += 1
		# plein mur : une extrémité du mur
		var sp := Construction.wall_span(w)
		var line2 := float(Construction.wall_line(w)) * Construction.U
		var loc2 := Vector2(float(sp.x) * Construction.U, line2) if Construction.wall_axis(w) == 0 else Vector2(line2, float(sp.x) * Construction.U)
		var wp2 := pos + HousePad.rot(loc2 - c, yaw)
		if _probe(Vector3(wp2.x, gm + 1.2, wp2.y)):
			wall_solid += 1
	_check(door_free == 1 and win_free == 2 and wall_solid == 4, "%s : porte et fenêtres vides dans la collision, quatre murs pleins (%d porte, %d fenêtres, %d murs)" % [tag, door_free, win_free, wall_solid])
	var ex: Explorer = isl.get("explorer")
	var qp := HousePad.nearest_path(plan.paths, h["door"])["q"] as Vector2
	isl.call("place_player", qp.x, qp.y, 0.0, 0.0)
	await get_tree().physics_frame
	await _frames(6)
	var door_front: Vector2 = h["door"]
	_check(await _walk_to(ex, door_front, 0.5, "seuil"), "%s : marche du chemin jusqu'au seuil par le raccord" % tag)
	var dir := HousePad.rot_i((fp["entrance"] as Dictionary)["dir"], yaw)
	var inside := pos + Vector2(dir) * -1.2
	var ok_in := await _walk_to(ex, inside, 0.7, "intérieur")
	var rm: Rect2 = h["rect"]
	_check(ok_in and rm.has_point(_pos2(ex)) and ex.global_position.y > gm + 0.1 and int(isl.get("falls")) == 0, "%s : le joueur entre dans la maison par la porte (x %.1f, z %.1f, y %.2f)" % [tag, ex.global_position.x, ex.global_position.z, ex.global_position.y])
	if shots:
		# vue extérieure : depuis le raccord, face à la porte
		var out_p := door_front + Vector2(dir) * 6.5
		var gy := (isl.get("lab") as LabWorld).ground_y(out_p.x, out_p.y)
		ex.auto_active = false
		(isl.get("explorer") as Explorer).teleport(Vector3(out_p.x, gy + 0.1, out_p.y), 0.0)
		var d := pos - out_p
		isl.get("camrig").yaw = atan2(-d.x, -d.y)
		isl.get("camrig").pitch = -0.05
		isl.get("camrig").snap()
		await get_tree().physics_frame
		await _frames(10)
		await _shot("11_maison_en_3d_sur_la_pente")
		# vue intérieure : face au mur du fond (fenêtres)
		var in_p := pos + Vector2(dir) * 1.2
		ex.teleport(Vector3(in_p.x, gm + 0.3, in_p.y), 0.0)
		var d2 := -Vector2(dir)
		isl.get("camrig").yaw = atan2(-d2.x, -d2.y)
		isl.get("camrig").pitch = 0.0
		isl.get("camrig").snap()
		await get_tree().physics_frame
		await _frames(10)
		await _shot("12_interieur_maison_ouvertures")

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(20)
	await _open_editor_from_menu()
	_check(ed != null, "éditeur de carte ouvert depuis le menu")
	ed._g_seed.value = 21
	await _press_button(ed, "Générer")
	await _frames(6)
	var doc := ed.doc
	await _key(KEY_9)
	_check(ed.tool == "maisons" and ed.house_model != null, "touche 9 : outil Maisons, modèle « %s » chargé" % (ed.house_model.name if ed.house_model != null else "?"))
	var spot := _find_spot(doc, ed.house_model)
	_check(not spot.is_empty(), "une parcelle compatible existe sur le plateau (graine 21)")
	var pos: Vector2 = spot["pos"]
	var yaw: int = spot["yaw"]
	var top0 := doc.field.top.duplicate()
	var mat0 := doc.field.material.duplicate()
	var depth0 := doc.undo_stack.size()
	await _look(pos, 15.0)
	# orientation par la touche R
	var guard := 0
	while ed.house_yaw != yaw and guard < 5:
		await _key(KEY_R)
		guard += 1
	_check(ed.house_yaw == yaw, "R : orientation choisie (porte côté %s)" % MapEditor.door_side_name(HousePad.rot_i(Vector2i(0, 1), yaw)))
	await _mouse(pos)
	await _frames(4)
	_check(bool(ed.house_eval.get("ok", false)), "aperçu : %s" % String(ed.house_eval.get("text", "")).left(110))
	_check(doc.field.top == top0 and doc.plan.houses.is_empty(), "l'aperçu ne modifie ni le relief ni la carte")
	await _shot("08_carte_apercu_implantation")
	# refus : on protège un morceau de la parcelle avec le pinceau de masque (vrai glissé), puis on essaie de poser
	await _key(KEY_7)
	var mk := ed.canvas
	var a := pos + Vector2(-0.8, -0.6)
	await _press_button(ed, "Protéger") if false else null
	ed.mask_mode = "peindre"
	ed.brush_radius = 1.2
	await _drag([a, a + Vector2(0.6, 0.0), a + Vector2(1.2, 0.0), a + Vector2(1.6, 0.3)])
	_check(doc.plan.layers.count_mask() > 20, "masque peint sous la parcelle (%d colonnes)" % doc.plan.layers.count_mask())
	var top_m := doc.field.top.duplicate()
	var depth_m := doc.undo_stack.size()
	await _key(KEY_9)
	await _mouse(pos)
	await _frames(4)
	_check(not bool(ed.house_eval.get("ok", true)) and "protégée" in " ".join(PackedStringArray(ed.house_eval["reasons"])), "aperçu refusé sur zone protégée : %s" % String(ed.house_eval["reasons"][0]).left(80))
	await _shot("09_carte_refus_zone_protegee")
	await _click(pos)
	_check(doc.plan.houses.is_empty() and doc.field.top == top_m and doc.undo_stack.size() == depth_m, "clic sur un refus : rien ne change (relief, maisons, historique)")
	# on retire la protection puis on pose
	await _key(KEY_7)
	await _press_button(ed, "Retirer tout le masque")
	await _frames(3)
	await _key(KEY_9)
	await _mouse(pos)
	await _frames(4)
	_check(bool(ed.house_eval.get("ok", false)), "masque retiré : l'implantation redevient possible")
	var top_pre := doc.field.top.duplicate()
	await _click(pos)
	_check(doc.plan.houses.size() == 1, "clic : maison posée")
	var changed := 0
	for i in top_pre.size():
		if top_pre[i] != doc.field.top[i]:
			changed += 1
	_check(changed > 100, "terrain adapté localement : %d colonnes (plateforme, talus, raccord)" % changed)
	await _look(pos, 15.0)
	await _frames(3)
	await _shot("10_carte_maison_posee_raccord")
	await _key(KEY_Z, true)
	_check(doc.plan.houses.is_empty(), "Ctrl+Z : la maison est retirée")
	_check(doc.field.top == top_pre, "Ctrl+Z : le terrain est restauré à l'identique (%d colonnes)" % changed)
	await _click(pos)
	_check(doc.plan.houses.size() == 1, "maison reposée")
	var top_final := doc.field.top.duplicate()
	var pos_final: Vector2 = doc.plan.houses[0]["pos"]
	# export
	_check(await _press_button(ed, "Exporter la carte"), "bouton « Exporter la carte »")
	await _frames(3)
	(ed._dialog.find_child("Nom", true, false) as LineEdit).text = "carte_maison_lot8"
	await _press_button(ed._dialog, "Enregistrer")
	var file := MapEditor.DIR + "carte_maison_lot8.eclats-carte.json"
	_check(FileAccess.file_exists(file), "carte exportée : %s" % ProjectSettings.globalize_path(file))
	report["fichier_carte"] = ProjectSettings.globalize_path(file)
	# 3D
	_check(await _press_button(ed, "Vérifier en 3D"), "bouton « Vérifier en 3D »")
	isl = await _wait_scene("MapIsland")
	_check(isl != null, "île 3D chargée")
	await _visit("île 3D", true)
	# NOUVELLE SESSION
	get_node("/root/App").call("open", App.MAP_EDITOR_SCENE, {})
	await _frames(5)
	ed = await _wait_scene("MapEditor") as MapEditor
	cv = ed.canvas
	await _frames(8)
	_check(ed.doc.plan.houses.is_empty(), "nouvelle session : carte vide")
	_check(await _press_button(ed, "Ouvrir une carte"), "bouton « Ouvrir une carte »")
	await _frames(3)
	var list := ed._dialog.find_child("Liste", true, false) as ItemList
	var names: Array = []
	for i in list.item_count:
		names.append(list.get_item_text(i))
	list.select(names.find("carte_maison_lot8.eclats-carte.json"))
	_check(await _press_button(ed._dialog, "Ouvrir la carte choisie"), "ouverture de la carte")
	await _frames(6)
	_check(ed.doc.plan.houses.size() == 1 and ed.doc.field.top == top_final, "carte rouverte : la maison est là, terrain identique colonne pour colonne")
	_check(ed.doc.plan.houses[0]["pos"] == pos_final and Construction.from_dict(ed.doc.plan.houses[0]["model"])["construction"].count_openings() == 3, "position conservée, 3 ouvertures conservées")
	await _look(pos_final, 15.0)
	await _shot("13_carte_rouverte_avec_maison")
	_check(await _press_button(ed, "Vérifier en 3D"), "bouton « Vérifier en 3D » (carte rouverte)")
	isl = await _wait_scene("MapIsland")
	await _visit("carte rouverte", false)
	report["duree_s"] = (Time.get_ticks_msec() - t0) / 1000
	var bad_n := 0
	for c in report["controles"]:
		if not c["ok"]:
			bad_n += 1
	report["echecs"] = bad_n
	var f := FileAccess.open(OUT + "/lot8_maison_rapport.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("== %d contrôle(s), %d échec(s) en %d s ==" % [report["controles"].size(), bad_n, report["duree_s"]])
	get_tree().quit()
