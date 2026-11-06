extends Node
## Essai JOUÉ + captures du LOT 11, dans le VRAI jeu lancé au menu (éditeur de carte) :
##   godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/lot11_recette.gd
## 1. éditeur : carte graine 21, retouche de relief (trait de pinceau), Ctrl+Z ; 2. « Vérifier en 3D » puis F6 : même document, même historique ;
## 3. dialogue de sortie (Annuler / échec d'enregistrement / Enregistrer) ; 4. maison posée, terrain modifié autour (zone), maison toujours raccordée,
##    modification qui la casserait refusée ; 5. 3D : du chemin jusque dans la maison.
const OUT := "/tmp/claude-0/-home-user/a63a7b17-b085-5a47-af76-319612b62b36/scratchpad/l11"
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

func _btn(root: Node, text_start: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(text_start):
			return b
	return null

func _dialog() -> Node:
	return App.find_child("DialogueSortie", true, false)

func _first_ok(doc: MapDoc, model: Construction) -> Dictionary:
	var z := doc.plan.zone_by_id("plateau")
	for r in [4.0, 7.0, 10.0, 13.0]:
		for yaw in 4:
			for k in 16:
				var p: Vector2 = (z["c"] as Vector2) + Vector2.from_angle(float(k) * TAU / 16.0) * r
				if doc.evaluate_house(model, p, yaw)["ok"]:
					return {"pos": p, "yaw": yaw}
	return {}

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(20)
	var menu := get_tree().current_scene
	menu.call("show_page", "dev")
	await _frames(3)
	_btn(menu, "Éditeur de carte").pressed.emit()
	ed = await _wait_scene("MapEditor") as MapEditor
	cv = ed.canvas
	await _frames(10)
	ed._g_seed.value = 21
	_btn(ed, "Générer").pressed.emit()
	await _frames(8)
	var doc := ed.doc
	var session := ed.session
	_check(not session.is_dirty(), "plan généré, rien de modifié : aucun dialogue à prévoir")
	# --- 1. retouche de relief (même chemin que la souris : _on_press / _on_motion / _on_release)
	await _key(KEY_5)
	ed.brush_radius = 4.5
	ed.brush_strength = 25.0
	var c := Vector2(doc.plan.zone_by_id("plateau")["c"]) + Vector2(6, 4)
	cv.view_center = c
	cv.px_per_m = 14.0
	cv.queue_redraw()
	await _frames(4)
	var base_h := doc.field.top_at(doc.col_of(c).x, doc.col_of(c).y)
	ed._on_press(c, false, Vector2.ZERO)
	for k in 12:
		ed._on_motion(c + Vector2(float(k) * 0.4, 0.0))
		await get_tree().process_frame
	ed._on_release(c + Vector2(5, 0))
	await _frames(6)
	var h1 := doc.field.top_at(doc.col_of(c).x, doc.col_of(c).y)
	_check(h1 > base_h and doc.undo_stack.size() == 1 and session.is_dirty(), "relief monté au pinceau (+%d cellules), une opération annulable, carte « modifiée »" % (h1 - base_h))
	ed._refresh(true)        # image complète (même échelle de teintes qu'après le retour de la 3D)
	await _frames(4)
	await _shot("01_editeur_avant_3d")
	var rebuilds := doc.rebuilds
	var shown := doc.field.top.duplicate()
	# --- 2. vue 3D puis retour
	ed._on_verify()
	isl = await _wait_scene("MapIsland")
	_check(isl != null and bool(isl.get("reused_field")), "vue 3D : le relief du document est réutilisé (pas recalculé)")
	await _frames(20)
	await _shot("02_vue_3d")
	await _key(KEY_F6)
	ed = await _wait_scene("MapEditor") as MapEditor
	await _frames(8)
	_check(ed.doc == doc and ed.doc.undo_stack.size() == 1 and ed.doc.rebuilds == rebuilds and ed.doc.field.top == shown, "retour de la 3D : même document, historique Ctrl+Z conservé, relief non recalculé, terrain identique")
	cv = ed.canvas
	cv.view_center = c
	cv.px_per_m = 14.0
	cv.queue_redraw()
	await _frames(4)
	await _shot("03_editeur_apres_3d")
	# --- annulation après le retour
	await _key(KEY_Z, true)
	await _frames(4)
	_check(ed.doc.field.top_at(ed.doc.col_of(c).x, ed.doc.col_of(c).y) == base_h and not ed.doc.can_undo(), "Ctrl+Z après le retour : le trait est annulé (terrain d'origine)")
	await _shot("04_annulation")
	# --- 3. dialogue de sortie
	ed.doc.stroke_begin("Monter", "monter", c)
	ed.doc.stroke_dab("monter", c, 3.0, 4.0)
	ed.doc.stroke_end()
	ed._refresh(true)
	_btn(ed, "Menu").pressed.emit()
	await _frames(8)
	var dlg := _dialog()
	_check(dlg != null and App.current_path == App.MAP_EDITOR_SCENE, "sortie demandée avec une carte modifiée : dialogue ouvert, on reste dans l'éditeur")
	await _shot("05_dialogue_sortie")
	_btn(dlg, "Annuler").pressed.emit()
	await _frames(6)
	_check(_dialog() == null and get_tree().current_scene.name == "MapEditor" and ed.doc.is_dirty(), "« Annuler » : l'éditeur est inchangé, la carte reste modifiée")
	_btn(ed, "Menu").pressed.emit()
	await _frames(8)
	dlg = _dialog()
	SafeFile.fail_at = "write"
	_btn(dlg, "Enregistrer").pressed.emit()
	await _frames(6)
	SafeFile.fail_at = ""
	var err := dlg.find_child("Erreur", true, false) as Label
	_check(err != null and "impossible" in err.text and get_tree().current_scene.name == "MapEditor" and ed.doc.is_dirty() and ed.doc.plan.layers.count_delta() > 0, "échec d'enregistrement : erreur expliquée, carte ouverte et modifiée intacte (« %s »)" % err.text.left(110))
	await _shot("06_echec_enregistrement")
	_btn(dlg, "Enregistrer").pressed.emit()
	var tm := Time.get_ticks_msec()
	while (get_tree().current_scene == null or get_tree().current_scene.name == "MapEditor") and Time.get_ticks_msec() - tm < 20000:
		await get_tree().process_frame
	var saved_path := session.path
	await _frames(10)
	_check(get_tree().current_scene != null and get_tree().current_scene.name != "MapEditor" and FileAccess.file_exists(saved_path), "« Enregistrer puis continuer » : carte enregistrée (%s) puis retour au menu" % saved_path.get_file())
	# --- 4. maison, terrain modifié autour, raccord conservé
	menu = get_tree().current_scene
	menu.call("show_page", "dev")
	await _frames(3)
	_btn(menu, "Éditeur de carte").pressed.emit()
	ed = await _wait_scene("MapEditor") as MapEditor
	await _frames(8)
	_btn(ed, "Ouvrir une carte").pressed.emit()
	await _frames(4)
	var lst := ed.find_child("Liste", true, false) as ItemList
	var model: Construction = Construction.load_file("res://assets/maisons/maison_exemple.eclats-maison.json")["construction"]
	ed._dialog.queue_free()
	ed._dialog = null
	ed.open_file(saved_path)
	await _frames(6)
	doc = ed.doc
	_check(doc.plan.layers.count_delta() > 0 and not ed.session.is_dirty(), "carte rouverte : retouches retrouvées, carte « propre »")
	var found := _first_ok(doc, model)
	var pr := doc.place_house(model, found["pos"], found["yaw"])
	_check(pr["ok"], "maison posée en pente : %s" % String(pr["text"]).left(110))
	ed._refresh(true)
	var h: Dictionary = doc.plan.houses[0]
	var far := (h["pos"] as Vector2) + Vector2(17, -14)
	if not IslandPlan.point_in_poly(far, doc.plan.outline):
		far = (h["pos"] as Vector2) + Vector2(-17, 14)
	var top_house: Array = []
	for i in h["terrain"]["cells"]:
		top_house.append(doc.field.top[i])
	var sig := doc.plan.signature()
	doc.begin_op("Zone ajoutée près de la maison")
	doc.add_zone_disc("bois", far, 3.5)
	var e1 := doc.finish_op()
	if e1 != "":
		print("   ", e1)
	var same := true
	for k in (h["terrain"]["cells"] as PackedInt32Array).size():
		if doc.field.top[h["terrain"]["cells"][k]] != top_house[k]:
			same = false
	_check(e1 == "" and doc.plan.signature() != sig and same, "zone ajoutée à côté : relief de base recalculé, plateforme de la maison inchangée")
	# chemin déplacé loin de la maison : refusé
	var lk: Dictionary = h["link"]
	var pid: String = HousePad.nearest_path(doc.plan.paths, lk["to"])["path_id"]
	doc.begin_op("Déplacer le chemin")
	var pa := doc.plan.path_by_id(pid)
	var mv: Array = []
	for q in pa["pts"]:
		mv.append((q as Vector2) + Vector2(11, 9))
	pa["pts"] = mv
	var e2 := doc.finish_op()
	_check(e2 != "" and doc.plan.houses.size() == 1, "chemin déplacé loin de la maison : refusé avec explication (« %s »)" % e2.left(120))
	ed._msg.text = e2
	ed._refresh(true)
	cv = ed.canvas
	cv.view_center = h["pos"]
	cv.px_per_m = 16.0
	cv.queue_redraw()
	await _frames(6)
	await _shot("07_maison_modification_refusee")
	# --- 5. enregistrer, rouvrir en 3D, du chemin jusque dans la maison
	var pf := MapEditor.DIR + "carte_lot11_maison.eclats-carte.json"
	_check(doc.export_to(pf)["ok"], "carte avec maison enregistrée")
	ed._on_verify()
	isl = await _wait_scene("MapIsland")
	_check(isl != null and (isl.get("house_nodes") as Array).size() == 1 and bool(isl.get("reused_field")), "3D : maison présente, relief réutilisé")
	var plan: IslandPlan = isl.get("plan")
	var hh: Dictionary = plan.houses[0]
	var ex: Explorer = isl.get("explorer")
	var np := HousePad.nearest_path(plan.paths, hh["door"])
	isl.call("place_player", (np["q"] as Vector2).x, (np["q"] as Vector2).y, 0.0, 0.0)
	await get_tree().physics_frame
	await _frames(6)
	var fp := HousePad.footprint(Construction.from_dict(hh["model"])["construction"])
	var dir := HousePad.rot_i((fp["entrance"] as Dictionary)["dir"], int(hh["yaw"]))
	var ok1 := await _walk(ex, hh["door"], 0.5)
	var inside := (hh["pos"] as Vector2) + Vector2(dir) * -1.0
	var ok2 := await _walk(ex, inside, 0.8)
	_check(ok1 and ok2 and (hh["rect"] as Rect2).has_point(Vector2(ex.global_position.x, ex.global_position.z)) and int(isl.get("falls")) == 0, "du chemin jusque dans la maison, par le raccord, après modification du terrain")
	var out_p := (hh["door"] as Vector2) + Vector2(dir) * 6.0
	ex.auto_active = false
	ex.teleport(Vector3(out_p.x, (isl.get("lab") as LabWorld).ground_y(out_p.x, out_p.y) + 0.1, out_p.y), 0.0)
	var d := (hh["pos"] as Vector2) - out_p
	isl.get("camrig").yaw = atan2(-d.x, -d.y)
	isl.get("camrig").pitch = -0.07
	isl.get("camrig").snap()
	await get_tree().physics_frame
	await _frames(10)
	await _shot("08_maison_raccordee_en_3d")
	report["duree_s"] = (Time.get_ticks_msec() - t0) / 1000
	var bad_n := 0
	for ck in report["controles"]:
		if not ck["ok"]:
			bad_n += 1
	report["echecs"] = bad_n
	var f := FileAccess.open(OUT + "/lot11_recette_rapport.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("== %d contrôle(s), %d échec(s) en %d s ==" % [report["controles"].size(), bad_n, report["duree_s"]])
	get_tree().quit()

func _walk(ex: Explorer, target: Vector2, tol: float) -> bool:
	ex.auto_active = true
	var t := 0.0
	var stuck := 0.0
	var check_t := 0.0
	var check_pos := Vector2(ex.global_position.x, ex.global_position.z)
	var falls0: int = isl.get("falls")
	while Vector2(ex.global_position.x, ex.global_position.z).distance_to(target) > tol:
		var p2 := Vector2(ex.global_position.x, ex.global_position.z)
		ex.auto_dir = (target - p2).normalized()
		await get_tree().physics_frame
		t += DT
		check_t += DT
		if int(isl.get("falls")) != falls0:
			ex.auto_dir = Vector2.ZERO
			return false
		if check_t >= 1.0:
			var p3 := Vector2(ex.global_position.x, ex.global_position.z)
			if check_pos.distance_to(target) - p3.distance_to(target) < 0.3:
				stuck += check_t
				ex.auto_jump = true
			else:
				stuck = 0.0
			check_t = 0.0
			check_pos = p3
		if stuck > 5.0 or t > 90.0:
			ex.auto_dir = Vector2.ZERO
			return false
	ex.auto_dir = Vector2.ZERO
	return true
