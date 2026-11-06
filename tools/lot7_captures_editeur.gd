extends Node
## Essai JOUÉ + captures de l'éditeur de carte (Lot 7, étape 2), dans le VRAI jeu lancé au menu :
##   godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/lot7_captures_editeur.gd
## menu → Outils développeur → éditeur de carte → canevas vide → contour, zones, chemin (déplacé), repère, relief, masque sur la
## crique, régénération autour, Ctrl+Z → export → NOUVELLE scène (nouvelle session de l'éditeur) → ouverture → contrôles → 3D.
## Les entrées sont de vrais événements d'entrée (clics, glissés, touches) ; seule la 3D est observée en capture.
const OUT := "/tmp/l7"

var ed: MapEditor
var cv: PlanCanvas
var report := {"controles": []}
var _top_before_regen := PackedInt32Array()
var _json_exported := ""
var _hash_exported := 0

func _check(cond: bool, label: String) -> void:
	report["controles"].append({"ok": cond, "controle": label})
	var line := ("  OK    " if cond else "  ÉCHEC ") + label
	print(line)
	var f := FileAccess.open(OUT + "/ed_checks.txt", FileAccess.READ_WRITE if FileAccess.file_exists(OUT + "/ed_checks.txt") else FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
	f.close()

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

func _mouse(world: Vector2, button := 0, pressed := false, dbl := false) -> void:
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
		e.double_click = dbl
		e.position = _sp(world)
		e.global_position = e.position
		e.button_mask = (1 << (button - 1)) if pressed else 0
		Input.parse_input_event(e)
	await get_tree().process_frame

func _click(world: Vector2, button := MOUSE_BUTTON_LEFT, dbl := false) -> void:
	await _mouse(world)
	await _mouse(world, button, true, dbl)
	await _mouse(world, button, false)
	await get_tree().process_frame

func _drag(pts: Array, button := MOUSE_BUTTON_LEFT) -> void:
	await _mouse(pts[0])
	await _mouse(pts[0], button, true)
	for i in range(1, pts.size()):
		await _mouse(pts[i])
	await _mouse(pts[pts.size() - 1], button, false)
	await get_tree().process_frame

func _line(a: Vector2, b: Vector2, n: int) -> Array:
	var out: Array = []
	for i in n + 1:
		out.append(a.lerp(b, float(i) / float(n)))
	return out

func _wait_scene(cls: String) -> Node:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 600000:
		var s := get_tree().current_scene
		if s != null and s.get_class() != "" and s.name == cls and (cls != "MapIsland" or bool(s.get("ready_to_play"))):
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

func _pick(index: int) -> void:
	for o in ed._opts.find_children("*", "OptionButton", true, false):
		(o as OptionButton).select(index)
		(o as OptionButton).item_selected.emit(index)
	await _frames(2)

func _look(center: Vector2, ppm: float) -> void:
	cv.view_center = center
	cv.px_per_m = ppm
	cv.queue_redraw()

func _ready() -> void:
	await _frames(30)
	var menu := get_tree().current_scene
	menu.call("show_page", "dev")
	await _frames(5)
	_check(await _press_button(menu, "Éditeur de carte"), "menu → Outils développeur → Éditeur de carte")
	ed = await _wait_scene("MapEditor") as MapEditor
	cv = ed.canvas
	await _frames(10)
	_check(ed.doc.plan.outline.is_empty() and not ed.doc.has_terrain(), "l'éditeur s'ouvre sur un canevas vide")
	var P := MapDocTestIsland.points()
	# ---- contour : clics + Entrée
	_look(Vector2(0, -1), 15.0)
	for p: Vector2 in P:
		await _click(p)
	_check(cv.draft_outline.size() == P.size(), "contour : %d points posés (aperçu du tracé)" % cv.draft_outline.size())
	await _shot("e0_trace")
	await _key(KEY_ENTER)
	await _frames(4)
	_check(ed.doc.has_terrain() and ed.doc.plan.outline.size() == P.size(), "Entrée ferme le contour : l'île existe (%.0f m², %.0f × %.0f m)" % [float(ed.doc.field.land_count()) * 0.04, ed.doc.plan.width, ed.doc.plan.length])
	_check(ed.tool == "zones", "l'éditeur passe à l'outil Zones")
	_look(Vector2(0, -1), 15.0)
	# ---- zones : prairie, bois, crique
	await _pick(IslandPlan.KIND_ORDER.find("pelouse"))
	ed.brush_radius = 7.0
	await _drag(_line(Vector2(-8, -3), Vector2(8, 2), 6))
	await _pick(IslandPlan.KIND_ORDER.find("bois"))
	ed.brush_radius = 4.5
	await _drag(_line(Vector2(6, -9), Vector2(10, -4), 4))
	await _pick(IslandPlan.KIND_ORDER.find("crique"))
	ed.brush_radius = 3.4
	await _drag([Vector2(-12, 5), Vector2(-11, 5)])
	var kinds := {}
	for z in ed.doc.plan.zones:
		kinds[z["kind"]] = true
	_check(kinds.has("pelouse") and kinds.has("bois") and kinds.has("crique"), "zones peintes à la souris : %d disques (%s)" % [ed.doc.plan.zones.size(), ", ".join(kinds.keys())])
	var crique_y := ed.doc.field.ground_at_m(-11.0, 5.0)
	_check(absf(crique_y - ed.doc.field.ground_at_m(-12.0, 5.0)) < 0.25, "la crique peinte est plate (sol à %.1f m)" % crique_y)
	# relief naturel plus marqué (curseur du panneau « Zones »)
	var sliders := ed._opts.find_children("*", "HSlider", true, false)
	var rs := sliders[sliders.size() - 1] as HSlider
	rs.value = 1.8
	rs.drag_ended.emit(true)
	await _frames(4)
	_check(float(ed.doc.plan.settings["relief"]) == 1.8, "réglage du relief naturel (×1,8) appliqué depuis le panneau")
	# ---- chemin : tracé à la souris
	await _key(KEY_3)
	for p: Vector2 in [Vector2(-11, 5), Vector2(-4, 4), Vector2(2, 0), Vector2(8, -6)]:
		await _click(p)
	await _key(KEY_ENTER)
	await _frames(4)
	_check(ed.doc.plan.paths.size() == 1 and (ed.doc.plan.paths[0]["pts"] as Array).size() == 4, "chemin tracé à la souris (4 points), relié aux zones : %s → %s" % [ed.doc.plan.paths[0].get("from", ""), ed.doc.plan.paths[0].get("to", "")])
	# repère
	await _key(KEY_4)
	ed.lm_label = "Vue sur le bois"
	await _click(Vector2(8, -6))
	_check(ed.doc.plan.landmarks.size() == 1, "repère posé (point de vue)")
	await _frames(2)
	await _shot("e1_canevas_ile_manuelle")
	# ---- déplacer un point du chemin (glisser), le terrain suit
	await _key(KEY_3)
	var mid_before: Vector2 = ed.doc.plan.paths[0]["pts"][2]
	await _drag(_line(mid_before, Vector2(2, 8), 5))
	var mid_after: Vector2 = ed.doc.plan.paths[0]["pts"][2]
	_check(mid_after.distance_to(Vector2(2, 8)) < 0.8 and mid_before.distance_to(mid_after) > 5.0, "point du chemin déplacé à la souris : (%.1f ; %.1f) → (%.1f ; %.1f)" % [mid_before.x, mid_before.y, mid_after.x, mid_after.y])
	var rep_ok := true
	for r in ed.doc.path_reports:
		rep_ok = rep_ok and bool(r["ok"])
	_check(rep_ok, "le chemin déplacé reste praticable (pente max %d %%)" % roundi(float(ed.doc.path_reports[0]["max_grade"]) * 100.0))
	# ---- relief : monter une colline, creuser
	await _key(KEY_5)
	var cm := ed.doc.col_of(Vector2(-3, -9))
	var h0 := ed.doc.field.top_at(cm.x, cm.y)
	ed.brush_radius = 3.5
	ed.brush_strength = 0.9
	cv.cursor_world = Vector2(-3, -9)
	await _drag(_line(Vector2(-4, -9), Vector2(-1, -9), 6))
	_check(ed.doc.field.top_at(cm.x, cm.y) >= h0 + 2, "pinceau « monter » à la souris : +%d cellules" % (ed.doc.field.top_at(cm.x, cm.y) - h0))
	await _pick(1)
	ed.brush_radius = 2.0
	await _drag(_line(Vector2(6, 6), Vector2(8, 6), 4))
	_check(ed.doc.undo_stack.size() >= 8, "chaque trait est une opération annulable (%d opérations)" % ed.doc.undo_stack.size())
	# ---- masque de protection sur la crique
	await _key(KEY_7)
	ed.brush_radius = 4.6
	await _drag([Vector2(-12.5, 5), Vector2(-11.5, 5), Vector2(-10.5, 5)])
	var masked := ed.doc.plan.layers.count_mask()
	_check(masked > 500, "masque posé sur la crique : %d colonnes" % masked)
	# ---- avant la régénération (même cadrage que l'après)
	var sel := Rect2(Vector2(-18, -3), Vector2(15, 15))
	await _key(KEY_8)
	await _drag([sel.position, sel.end])
	_check(cv.sel_rect.size.x > 10.0, "sélection tracée à la souris : %.1f × %.1f m" % [cv.sel_rect.size.x, cv.sel_rect.size.y])
	var framing_c := Vector2(-9.5, 3.5)
	_look(framing_c, 21.0)
	cv.cursor_world = Vector2.INF
	await _frames(3)
	await _shot("e2_crique_avant")
	var top_pre := ed.doc.field.top.duplicate()
	var mask_pre := ed.doc.plan.layers.mask.duplicate()
	var sel_m: Rect2 = cv.sel_rect
	# ---- régénération par le bouton
	_check(await _press_button(ed, "Régénérer le relief dans la sélection"), "bouton « Régénérer le relief dans la sélection »")
	await _frames(4)
	var n := ed.doc.field.n
	var crique_ok := true
	var outside_ok := true
	var changed := 0
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			var p := ed.doc.field.center_m(cx, cz)
			if ed.doc.field.top[i] != top_pre[i]:
				changed += 1
				if mask_pre[i] != 0:
					crique_ok = false
				if not sel_m.has_point(p):
					outside_ok = false
	_check(changed > 300, "le relief change dans la zone sélectionnée (%d colonnes)" % changed)
	_check(crique_ok, "la crique protégée est restée intacte")
	_check(outside_ok, "les zones extérieures à la sélection n'ont pas bougé")
	_look(framing_c, 21.0)
	cv.cursor_world = Vector2.INF
	await _frames(3)
	await _shot("e3_crique_apres")
	var top_post := ed.doc.field.top.duplicate()
	# ---- Ctrl+Z : annule la régénération entière
	await _key(KEY_Z, true)
	await _frames(3)
	_check(ed.doc.field.top == top_pre, "Ctrl+Z restaure le relief d'avant la régénération (toutes les colonnes)")
	_check(await _press_button(ed, "Régénérer le relief dans la sélection"), "régénération relancée")
	await _frames(3)
	_check(ed.doc.field.top != top_post and ed.doc.field.top != top_pre, "relancer = variante suivante : un autre relief dans la même sélection")
	# ---- export par le dialogue
	_check(await _press_button(ed, "Exporter la carte"), "bouton « Exporter la carte »")
	await _frames(3)
	var le := ed._dialog.find_child("Nom", true, false) as LineEdit
	le.text = "essai_lot7"
	_check(await _press_button(ed._dialog, "Enregistrer"), "export : « Enregistrer »")
	var file := MapEditor.DIR + "essai_lot7.eclats-carte.json"
	_check(FileAccess.file_exists(file), "fichier écrit : %s (%d octets)" % [ProjectSettings.globalize_path(file), FileAccess.get_file_as_bytes(file).size()])
	_json_exported = ed.doc.plan.to_json()
	_hash_exported = hash(ed.doc.field.top)
	var layers_exported := ed.doc.plan.layers.copy()
	var path_pts: Array = ed.doc.plan.paths[0]["pts"].duplicate()
	# ---- NOUVELLE SESSION de l'éditeur : scène rechargée, canevas vide
	var menu_app := get_node("/root/App")
	menu_app.call("open", App.MAP_EDITOR_SCENE, {})
	await _frames(5)
	ed = await _wait_scene("MapEditor") as MapEditor
	cv = ed.canvas
	await _frames(10)
	_check(ed.doc.plan.outline.is_empty() and ed.doc.undo_stack.is_empty(), "nouvelle session : éditeur vide, historique vide")
	var bad := FileAccess.open(MapEditor.DIR + "cassee.json", FileAccess.WRITE)
	bad.store_string('{"format": "eclats-carte", "version": 1, "name": "x", "outline": [[0,0]')
	bad.close()
	await _key(KEY_Z, true)
	_check(await _press_button(ed, "Ouvrir une carte"), "bouton « Ouvrir une carte »")
	await _frames(3)
	var list := ed._dialog.find_child("Liste", true, false) as ItemList
	var names: Array = []
	for i in list.item_count:
		names.append(list.get_item_text(i))
	_check(names.has("essai_lot7.eclats-carte.json") and names.has("cassee.json"), "la liste propose les cartes du dossier : %s" % ", ".join(names))
	list.select(names.find("essai_lot7.eclats-carte.json"))
	_check(await _press_button(ed._dialog, "Ouvrir la carte choisie"), "ouverture de la carte exportée")
	await _frames(5)
	_check(ed.doc.plan.to_json() == _json_exported, "plan rouvert identique (zones, chemins, repères, réglages)")
	var l2 := ed.doc.plan.layers
	_check(l2 != null and l2.delta == layers_exported.delta and l2.mat == layers_exported.mat and l2.mask == layers_exported.mask, "retouches de relief, matières et masque conservés (%d / %d / %d colonnes)" % [l2.count_delta(), l2.count_mat(), l2.count_mask()])
	_check(hash(ed.doc.field.top) == _hash_exported, "terrain rouvert identique à celui exporté")
	var pts2: Array = ed.doc.plan.paths[0]["pts"]
	_check(pts2.size() == path_pts.size() and (pts2[2] as Vector2).distance_to(path_pts[2]) < 0.01, "chemin retouché retrouvé : point (%.1f ; %.1f)" % [(pts2[2] as Vector2).x, (pts2[2] as Vector2).y])
	# fichier corrompu ALORS QUE l'île est ouverte : erreur expliquée, île conservée
	_check(await _press_button(ed, "Ouvrir une carte"), "bouton « Ouvrir une carte » (île déjà ouverte)")
	await _frames(3)
	var list2 := ed._dialog.find_child("Liste", true, false) as ItemList
	var names2: Array = []
	for i in list2.item_count:
		names2.append(list2.get_item_text(i))
	list2.select(names2.find("cassee.json"))
	var top_keep := ed.doc.field.top.duplicate()
	_check(await _press_button(ed._dialog, "Ouvrir la carte choisie"), "ouverture du fichier corrompu demandée")
	var info := ed._dialog.find_child("Info", true, false) as Label
	_check(info.text.contains("impossible") and info.text.contains("illisible"), "erreur expliquée dans le dialogue : « %s »" % info.text)
	_check(ed.doc.plan.to_json() == _json_exported and ed.doc.field.top == top_keep, "l'île ouverte est conservée, intacte, après l'erreur")
	await _shot("e5_fichier_invalide")
	# la bonne carte, de nouveau, depuis le même dialogue
	list2.select(names2.find("essai_lot7.eclats-carte.json"))
	_check(await _press_button(ed._dialog, "Ouvrir la carte choisie"), "ouverture de la carte exportée (2e fois, après l'erreur)")
	await _frames(4)
	_check(ed._dialog == null and ed.doc.plan.to_json() == _json_exported and hash(ed.doc.field.top) == _hash_exported, "après l'erreur, la carte s'ouvre normalement")
	ed.select_tool("chemins")
	ed._selected_path = ed.doc.plan.paths[0]["id"]
	cv.selected_path = ed._selected_path
	_look(Vector2(-1, -1), 14.5)
	cv.cursor_world = Vector2.INF
	await _frames(3)
	await _shot("e4_carte_rouverte")
	# ---- contrôle en 3D (première personne / aérienne), puis retour
	_check(await _press_button(ed, "Vérifier en 3D"), "bouton « Vérifier en 3D »")
	var isl := await _wait_scene("MapIsland") as MapIsland
	_check(isl != null and isl.ready_to_play, "l'île éditée s'ouvre en 3D, première personne : %s" % (isl.plan.name if isl else "?"))
	var pa: Dictionary = isl.plan.paths[0]
	var a: Vector2 = pa["pts"][1]
	var b: Vector2 = pa["pts"][2]
	isl.place_player(a.x, a.y, atan2(-(b.x - a.x), -(b.y - a.y)), -0.1)
	await _frames(6)
	await _shot("e6_3d_chemin")
	isl.set_aerial(true)
	await _frames(6)
	await _shot("e7_3d_aerienne")
	await _key(KEY_F6)
	ed = await _wait_scene("MapEditor") as MapEditor
	_check(ed != null and ed.doc.plan.to_json() == _json_exported, "F6 : retour à l'éditeur avec la même carte")
	var f := FileAccess.open("/tmp/l7/recette_editeur.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	var bad_n := 0
	for c in report["controles"]:
		if not c["ok"]:
			bad_n += 1
	print("== %d contrôles, %d échec(s) ==" % [report["controles"].size(), bad_n])
	get_tree().quit()
