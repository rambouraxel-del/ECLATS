extends Node
## Recette + captures de l'ÉDITEUR D'ÎLES CRÉATIF, dans le VRAI jeu lancé au menu (rendu logiciel, Xvfb) :
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/creatif_recette.gd
## Parcours : île vide → colline → zone boisée + forêt → arbre déplacé et supprimé → chemin → objets de l'inventaire → marché →
## construction (atelier) → maison enregistrée → deux maisons dont une sur pente → carte enregistrée, rouverte, parcourue → annulation →
## zone protégée et objet verrouillé face à une régénération.
## Entrées : touches et clics SOURIS réels (Input.parse_input_event) pour les gestes courants ; le reste appelle directement les mêmes
## méthodes que l'interface (boutons) — chaque étape dit lequel des deux. Rien n'est écrit en dehors de user:// et de OUT.
const OUT := "/tmp/claude-0/-home-user/a63a7b17-b085-5a47-af76-319612b62b36/scratchpad/ei"
const SAVE := "user://cartes/ile_creative_demo.eclats-carte.json"

var ed: CreativeEditor
var report := {"controles": [], "captures": []}
var ids := {}

func _check(cond: bool, label: String) -> void:
	report["controles"].append({"ok": cond, "controle": label})
	print(("  OK    " if cond else "  ÉCHEC ") + label)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [OUT, name], 0.9)
	report["captures"].append(name)
	print("saved ", name)

func _key(code: int, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame

func _wait_editor() -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 600000:
		var s := get_tree().current_scene
		if s is CreativeEditor and (s as CreativeEditor).ready_to_edit:
			ed = s
			await _frames(8)
			return
		await get_tree().process_frame

func _settle() -> void:
	# attend la fin des mises à jour de l'île (tuiles reconstruites)
	var t := Time.get_ticks_msec()
	while (ed._syncing or ed._live_busy) and Time.get_ticks_msec() - t < 120000:
		await get_tree().process_frame
	await _frames(6)

func _sp(p: Vector3) -> Vector2:
	return ed.cam.unproject_position(p)

func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, ed.doc.field.ground_at_m(p.x, p.y), p.y)

func _mouse(sp: Vector2, button := 0, pressed := false) -> void:
	ed.mouse_override = sp
	if button == 0:
		var m := InputEventMouseMotion.new()
		m.position = sp
		m.global_position = sp
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
		Input.parse_input_event(m)
	else:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = sp
		e.global_position = sp
		e.button_mask = (1 << (button - 1)) if pressed else 0
		Input.parse_input_event(e)
	await get_tree().process_frame

## Clic souris réel sur un point du monde (le rayon de la caméra le retrouve au sol).
func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var sp := _sp(_ground(p))
	await _mouse(sp)
	await _mouse(sp, button, true)
	await _mouse(sp, button, false)
	await get_tree().process_frame

func _drag(pts: Array) -> void:
	await _mouse(_sp(_ground(pts[0])))
	await _mouse(_sp(_ground(pts[0])), MOUSE_BUTTON_LEFT, true)
	for i in range(1, pts.size()):
		await _mouse(_sp(_ground(pts[i])))
		await _frames(2)
	await _mouse(_sp(_ground(pts[pts.size() - 1])), MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame

func _cam_aerial(target: Vector2, dist: float, yaw := 0.0, pitch := -0.95) -> void:
	ed.set_mode("aerial")
	var g := ed.doc.field.ground_at_m(target.x, target.y)
	ed.a_target = Vector3(target.x, 0.0 if is_nan(g) else g, target.y)
	ed.a_dist = dist
	ed.a_yaw = yaw
	ed.a_pitch = pitch
	ed._apply_cam()
	await _frames(3)

func _cam_fp(pos: Vector3, look: Vector3) -> void:
	ed.set_mode("fp")
	ed.f_pos = pos
	var d := look - pos
	ed.f_yaw = atan2(-d.x, -d.z)
	ed.f_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	ed._apply_cam()
	await _frames(3)

func _spot(near: Vector2, edge := 4.0) -> Vector2:
	for r in range(0, 24):
		for a in 24:
			var p := near + Vector2.from_angle(float(a) * TAU / 24.0) * float(r)
			var c := ed.doc.col_of(p)
			if ed.doc.field.has_ground(c.x, c.y) and ed.doc.field.edge_dist[ed.doc.field.idx(c.x, c.y)] > edge:
				return p
	return near

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	await _run()
	DirAccess.make_dir_recursive_absolute(OUT)
	var f := FileAccess.open(OUT + "/rapport.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	var ko := 0
	for c in report["controles"]:
		if not bool(c["ok"]):
			ko += 1
	print("RECETTE : %d contrôles, %d échec(s)" % [(report["controles"] as Array).size(), ko])
	get_tree().quit(1 if ko > 0 else 0)

const ETAT := "user://cartes/export_etat.eclats-carte.json"

func _phase(name: String) -> bool:
	var ph := OS.get_environment("CREATIF_PHASES")
	return ph == "" or ph.split(",").has(name)

func _run() -> void:
	if not _phase("menu"):
		# reprise : on ouvre une île générée (graine 5) et on enchaîne directement sur les phases demandées
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cartes/"))
		var mode := {"mode": "ouvrir", "path": ETAT} if FileAccess.file_exists(ETAT) else {"mode": "graine", "seed": 5}
		App.open(App.CREATIVE_SCENE, mode)
		await _wait_editor()
		await _settle()
		ed.session.path = ""             # comme une carte jamais enregistrée (Ctrl+S ouvre le dialogue)
		await _key(KEY_1)
		await _run_late()
		return
	# ---------------------------------------------------------------- 1. menu et choix de la carte
	await _frames(20)
	await _shot("01_menu_principal")
	var menu := get_tree().current_scene
	menu.call("show_page", "dev")
	await _frames(6)
	await _shot("02_menu_outils_developpeur")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cartes/"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	menu.call("show_page", "creatif")
	await _frames(6)
	await _shot("02b_menu_choix_de_la_carte")
	(menu.find_child("Vide", true, false) as Button).pressed.emit()        # bouton « Île vide » de la page de choix
	await _wait_editor()
	_check(ed.doc.field != null and ed.doc.plan.outline.size() >= 3, "île vide ouverte depuis le menu développeur : contour + plateau, prête à sculpter")
	await _cam_aerial(ed._island_center(), 62.0)
	await _shot("03_ile_vide_vue_aerienne")
	ed.ui.show_file_dialog("seed")
	await _frames(4)
	await _shot("04_choix_graine_generer")
	ed.ui.close_dialog()
	ed.ui.show_file_dialog("open")
	await _frames(4)
	await _shot("05_choix_carte_ouvrir")
	ed.ui.close_dialog()
	await _frames(3)
	# ---------------------------------------------------------------- 2. inventaire
	await _key(KEY_I)
	_check(ed.ui.panel_open(), "touche I : l'inventaire s'ouvre")
	await _frames(6)
	await _shot("10_inventaire_categories")
	ed.ui._cat = "Arbres"
	ed.ui._fill_cats()
	ed.ui._fill_items()
	await _frames(4)
	await _shot("11_inventaire_categorie_arbres")
	ed.ui._cat = ""
	ed.ui._search.text = "chêne"
	ed.ui._fill_items()
	await _frames(2)
	_check(ed.ui._shown.size() >= 3, "recherche « chêne » : %d résultats" % ed.ui._shown.size())
	ed.ui._on_item(0)
	await _frames(30)
	await _shot("12_inventaire_recherche_apercu_objet")
	for cat in ["Marché et village", "Ruines et vestiges", "Mobilier", "Maisons", "Port et navires", "Rochers"]:
		ed.ui._search.text = ""
		ed.ui._cat = cat
		ed.ui._fill_items()
		_check(ed.ui._shown.size() > 0, "catégorie « %s » : %d éléments" % [cat, ed.ui._shown.size()])
	ed.ui._cat = "Ruines et vestiges"
	ed.ui._fill_cats()
	ed.ui._fill_items()
	ed.ui._on_item(0)
	await _frames(30)
	await _shot("13_inventaire_ruines_apercu")
	ed.ui._cat = ""
	ed.ui._search.text = ""
	ed.ui._fill_cats()
	ed.ui._fill_items()
	await _key(KEY_I)
	# ---------------------------------------------------------------- 3. colline (relief) puis matière
	var hill := _spot(ed.doc.plan.start + Vector2(8, -4), 5.0)
	await _cam_aerial(hill + Vector2(0, 6), 26.0, 0.0, -0.62)
	await _shot("20_relief_avant")
	await _key(KEY_3)
	_check(ed.tool == "terrain", "touche 3 : outil Relief")
	ed.brush["mode"] = "monter"
	ed.brush["radius"] = 4.0
	ed.brush["strength"] = 0.8
	var h0 := ed.doc.field.ground_at_m(hill.x, hill.y)
	var ops0 := ed.doc.undo_stack.size()
	await _drag([hill + Vector2(-2, 0), hill + Vector2(-1, 0), hill, hill + Vector2(1, 0.5), hill + Vector2(2, 0), hill + Vector2(0, 1), hill])
	for k in 5:
		await _drag([hill + Vector2(-1.5, 0.5), hill, hill + Vector2(1.5, -0.5)])
	await _settle()
	var h1 := ed.doc.field.ground_at_m(hill.x, hill.y)
	_check(h1 > h0 + 0.7, "clic maintenu et glisser : la colline monte de %.1f m" % (h1 - h0))
	_check(ed.doc.undo_stack.size() > ops0, "chaque trait de pinceau est une opération annulable")
	await _shot("21_relief_apres_colline")
	ed.brush["mode"] = "adoucir"
	ed.brush["radius"] = 4.5
	await _drag([hill + Vector2(-3, 1), hill, hill + Vector2(3, -1)])
	await _settle()
	await _shot("22_relief_adouci")
	await _key(KEY_4)
	ed.brush["material"] = 9         # roche grise
	ed.brush["radius"] = 2.6
	await _drag([hill + Vector2(-1.5, 0), hill, hill + Vector2(1.5, 0.3)])
	await _settle()
	var mid := ed.doc.field.material[ed.doc.field.idx(ed.doc.col_of(hill).x, ed.doc.col_of(hill).y)]
	_check(mid == VoxelPalette.get_default().id("rock_grey"), "matière peinte : roche grise au sommet")
	await _shot("23_matiere_apres_roche")
	# ---------------------------------------------------------------- 4. zone boisée et forêt
	var wood := _spot(ed.doc.plan.start + Vector2(-9, -6), 5.0)
	await _cam_aerial(wood, 30.0, 0.0, -0.8)
	await _key(KEY_5)
	ed.map_sub = "zone"
	ed.zone_kind = "bois"
	ed.brush["radius"] = 4.0
	ed.ui._sig = ""
	ed.ui.refresh()
	await _shot("30_carte_zone_avant")
	var zones0 := ed.doc.plan.zones.size()
	await _drag([wood + Vector2(-2, 0), wood, wood + Vector2(2, 1)])
	await _settle()
	_check(ed.doc.plan.zones.size() > zones0, "zone boisée peinte (%d zones)" % ed.doc.plan.zones.size())
	await _cam_aerial(wood, 30.0, 0.0, -0.8)
	await _shot("31_zone_boisee_peinte")
	await _key(KEY_6)
	ed.gen["preset"] = "foret"
	ed.gen["radius"] = 6.5
	ed.gen["densite"] = 65
	ed.gen["seed"] = 4
	ed.mouse_override = _sp(_ground(wood))
	var n_before := ed.doc.plan.objects.size()
	await _click(wood)
	await _settle()
	var n_forest := ed.doc.plan.objects.size() - n_before
	_check(n_forest >= 6, "clic : forêt générée (%d objets : %s)" % [n_forest, ed.doc.message])
	await _shot("32_foret_generee")
	var trees: Array = []
	for o in ed.doc.plan.objects:
		if String(o["group"]) == "foret" and String(o["ref"]).begins_with("tree_"):
			trees.append(o)
	# les arbres les plus proches de la caméra (z le plus grand : elle regarde vers le nord) : rien ne les masque
	trees.sort_custom(func(a, b) -> bool: return (a["pos"] as Vector2).y > (b["pos"] as Vector2).y)
	var t1: Dictionary = trees[0]
	var t2: Dictionary = trees[1]
	await _key(KEY_1)
	await _click(t1["pos"])
	_check(ed.selected == String(t1["id"]), "outil Sélection : clic sur un arbre généré → sélectionné")
	await _shot("33_arbre_selectionne")
	var from_pos: Vector2 = t1["pos"]
	var to_pos := from_pos + Vector2(2.5, 1.5)
	ed.mouse_override = _sp(_ground(from_pos))
	await _mouse(_sp(_ground(from_pos)), MOUSE_BUTTON_LEFT, true)
	await _mouse(_sp(_ground(to_pos)))
	await _frames(3)
	await _shot("34_arbre_en_deplacement")
	await _mouse(_sp(_ground(to_pos)), MOUSE_BUTTON_LEFT, false)
	await _settle()
	var moved: Dictionary = ed.doc.object_by_id(String(t1["id"]))
	_check((moved["pos"] as Vector2).distance_to(to_pos) < 0.8 and (moved["pos"] as Vector2).distance_to(from_pos) > 1.5, "arbre déplacé à la souris (%.1f m)" % (moved["pos"] as Vector2).distance_to(from_pos))
	await _shot("35_arbre_deplace")
	ed.selected = String(t2["id"])
	var count_before := ed.doc.plan.objects.size()
	await _key(KEY_DELETE)
	await _settle()
	_check(ed.doc.plan.objects.size() == count_before - 1 and ed.doc.object_by_id(String(t2["id"])).is_empty(), "touche Suppr : un autre arbre est supprimé")
	await _shot("36_arbre_supprime")
	# ---------------------------------------------------------------- 5. chemin et objets de l'inventaire
	var pa := _spot(ed.doc.plan.start + Vector2(2, 2), 3.0)
	await _cam_aerial(pa + Vector2(4, 0), 34.0, 0.0, -0.9)
	await _key(KEY_5)
	ed.map_sub = "chemin"
	ed.ui._sig = ""
	ed.ui.refresh()
	var paths0 := ed.doc.plan.paths.size()
	var pts := [pa + Vector2(-3, 3), pa + Vector2(1, 1), pa + Vector2(5, 2), pa + Vector2(9, -1)]
	for p in pts:
		await _click(_spot(p, 2.0))
	await _shot("40_chemin_en_trace")
	await _key(KEY_ENTER)
	await _settle()
	_check(ed.doc.plan.paths.size() == paths0 + 1, "chemin tracé par clics, Entrée pour finir (%d points)" % ((ed.doc.plan.paths.back()["pts"] as Array).size()))
	await _cam_aerial(pa + Vector2(4, 0), 34.0, 0.0, -0.9)
	await _shot("41_chemin_termine_poignees")
	# objets de l'inventaire
	await _key(KEY_I)
	var items := AssetCatalog.items()
	var place_items := ["water_well", "ruin_column", "decorative_bench", "boulder_2", "signpost"]
	var spots := [pa + Vector2(2, 5), pa + Vector2(6, 5), pa + Vector2(-2, 6), pa + Vector2(10, 4), pa + Vector2(4, -3)]
	var obj_count := ed.doc.plan.objects.size()
	for k in place_items.size():
		var it := {}
		for q in items:
			if String(q["id"]) == place_items[k]:
				it = q
		ed.choose_item(it)
		await _frames(3)
		var sp := _spot(spots[k], 3.0)
		ed.mouse_override = _sp(_ground(sp))
		await _frames(4)
		if k == 0:
			ed.ui._show_preview(it)
			await _frames(25)
			await _shot("50_placement_apercu_aimant")
		if k == 2:
			await _key(KEY_R)
			await _key(KEY_R)
			await _shot("51_placement_apercu_tourne")
		await _click(sp)
		await _settle()
	_check(ed.doc.plan.objects.size() == obj_count + place_items.size(), "5 objets posés depuis l'inventaire (clic réel) : puits, colonne, banc, rocher, panneau")
	await _key(KEY_I)
	await _key(KEY_1)
	await _cam_aerial(pa + Vector2(4, 3), 22.0, 0.3, -0.62)
	await _shot("52_objets_poses")
	# tourner et déplacer un objet posé
	var bench: Dictionary = {}
	for o in ed.doc.plan.objects:
		if String(o["ref"]) == "decorative_bench":
			bench = o
	var bench_pos0: Vector2 = bench["pos"]
	await _click(bench_pos0)
	var yaw0 := float(ed.doc.object_by_id(String(bench["id"]))["yaw"])
	await _key(KEY_R)
	await _key(KEY_R)
	await _key(KEY_R)
	await _settle()
	var yaw1 := float(ed.doc.object_by_id(String(bench["id"]))["yaw"])
	_check(absf(fposmod(yaw1 - yaw0, 360.0) - 45.0) < 0.1, "R : l'objet sélectionné tourne par pas de 15° (+%.0f°)" % fposmod(yaw1 - yaw0, 360.0))
	await _shot("53_objet_tourne")
	await _key(KEY_G)
	ed.mouse_override = _sp(_ground(bench_pos0 + Vector2(3, -1)))
	await _frames(4)
	await _shot("54_objet_grab_deplacement")
	await _click(bench_pos0 + Vector2(3, -1))
	await _settle()
	_check((ed.doc.object_by_id(String(bench["id"]))["pos"] as Vector2).distance_to(bench_pos0) > 2.0, "G puis clic : objet déplacé")
	await _key(KEY_D, true)
	await _settle()
	_check(ed.doc.plan.objects.size() == obj_count + place_items.size() + 1, "Ctrl+D : objet dupliqué")
	await _shot("55_objet_duplique")
	# ---------------------------------------------------------------- 6. marché
	var mk := _spot(ed.doc.plan.start + Vector2(10, 10), 5.0)
	await _cam_aerial(mk, 26.0, 0.0, -0.8)
	await _key(KEY_6)
	ed.gen["preset"] = "marche"
	ed.gen["radius"] = 7.0
	ed.gen["etals"] = 4
	ed.gen["seed"] = 2
	var m0 := ed.doc.plan.objects.size()
	var mr := {}
	for rad in [7.0, 8.0, 9.0]:
		ed.gen["radius"] = rad
		mr = ed.doc.compose("marche", mk, rad, 2, {"etals": 4})
		if bool(mr["ok"]):
			break
	await ed.sync()
	await _settle()
	_check(bool(mr["ok"]), "marché généré : %s" % ed.doc.message)
	await _shot("60_marche_genere")
	var stall := {}
	for o in ed.doc.plan.objects:
		if String(o["group"]) == "marche" and String(o["ref"]) == "market_stall":
			stall = o
	if not stall.is_empty():
		ed.doc.update_object(String(stall["id"]), {"pos": (stall["pos"] as Vector2) + Vector2(1.5, 1.0), "yaw": float(stall["yaw"]) + 30.0}, "Déplacer l'étal")
		ed.selected = String(stall["id"])
		await ed.sync()
		await _settle()
		_check(true, "un étal généré est déplacé et tourné individuellement")
		await _shot("61_marche_objet_deplace")
	ed.export_copy("etat")                  # état de reprise des phases suivantes (copie exportée : ne marque pas la carte enregistrée)
	await _run_late()

func _run_late() -> void:
	# ---------------------------------------------------------------- 7. atelier : construire la maison (escalier, étage)
	if not _phase("atelier"):
		await _after_house()
		return
	await _key(KEY_7, false)
	await _wait_lab()
	await _build_house()
	# ---------------------------------------------------------------- 8. retour à l'éditeur : maison enregistrée, deux poses
	await _key(KEY_F6)
	await _wait_editor()
	await _frames(10)
	await _after_house()

func _after_house() -> void:
	if OS.get_environment("CREATIF_PHASES") != "" and _phase("liste"):
		# choix de la carte à rouvrir : la liste des cartes enregistrées
		ed.ui.show_file_dialog("open")
		await _frames(6)
		await _shot("05b_choix_carte_cartes_enregistrees")
		ed.ui.close_dialog()
	if _phase("maisons"):
		await _place_houses()
	# ---------------------------------------------------------------- 9. sauvegarde, réouverture, parcours
	if _phase("save"):
		await _save_reopen_play()
	# ---------------------------------------------------------------- 10. annulation, protection, verrou
	if _phase("undo"):
		await _undo_protect()

func _wait_lab() -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 300000:
		var s := get_tree().current_scene
		if s is DevLab and (s as DevLab).ready_to_play:
			await _frames(10)
			return
		await get_tree().process_frame

func _build_house() -> void:
	var lab := get_tree().current_scene as DevLab
	var b := lab.builder
	_check(b.active and lab.session != null, "7 → l'atelier s'ouvre avec la session de la carte, mode construction actif")
	var c := Construction.new()
	c.name = "Maison à étage"
	var steps := []
	var r1 := {"ok": true}
	var r2 := ConstructionOps.add_room(c, 0, Vector2i(0, 0), Vector2i(14, 10), 3.0, "S", "enduit", "planches")
	c = r2["cand"]
	var wins := 0
	for w in c.of_type("wall", 0):
		if int(w["az"]) == 0 and Construction.wall_axis(w) == 0:
			var wo := ConstructionOps.add_opening(c, int(w["id"]), "window", float(Construction.wall_span(w).x + 8))
			if bool(wo["ok"]):
				c = wo["cand"]
				wins += 1
	var up := ConstructionOps.add_slab(c, "floor", 1, Vector2i(0, 0), Vector2i(14, 10), "planches")
	c = up["cand"]
	var up_walls := 0
	for seg in [[Vector2i(0, 0), Vector2i(14, 0)], [Vector2i(14, 0), Vector2i(14, 10)], [Vector2i(0, 10), Vector2i(14, 10)], [Vector2i(0, 0), Vector2i(0, 10)]]:
		var rw := ConstructionOps.add_wall(c, 1, seg[0], seg[1], 2.5, "enduit", 1)
		if bool(rw["ok"]):
			c = rw["cand"]
			up_walls += 1
	_check(up_walls == 4, "quatre murs d'étage posés")
	var c_no_stairs := c.copy()
	var st := ConstructionOps.add_stairs(c, 0, Vector2i(2, 2), "E", "planches")
	_check(bool(r1["ok"]) and bool(r2["ok"]) and bool(up["ok"]) and bool(st["ok"]), "fondations, pièce, porte, étage et escalier acceptés par les mêmes règles que le mode construction (escalier : %s)" % String(st["text"]))
	c = st["cand"]
	# toit sur le dernier niveau
	var roof_wall := -1
	for w in c.of_type("wall", 1):
		roof_wall = int(w["id"])
		break
	if roof_wall >= 0:
		var rr := ConstructionOps.add_roof(c, roof_wall, "tuiles")
		if bool(rr["ok"]):
			c = rr["cand"]
	var wo2 := 0
	for w in c.of_type("wall", 1):
		if Construction.wall_axis(w) == 0 and int(w["az"]) == 0:
			var o2 := ConstructionOps.add_opening(c, int(w["id"]), "window", float(Construction.wall_span(w).x + 8))
			if bool(o2["ok"]):
				c = o2["cand"]
				wo2 += 1
	var gy := lab.lab.ground_y(3.5, 2.5)
	c.base_y = gy
	b.c = c
	b.level = 0
	b._rebuild()
	_check(c.of_type("stairs").size() == 1 and c.level_count() == 2 and c.count_openings() >= 2, "maison : %s" % c.summary())
	var cr := lab.camrig
	var look := func(p: Vector3) -> void:
		var d: Vector3 = p - cr.cam.global_position
		cr.yaw = atan2(-d.x, -d.z)
		cr.pitch = atan2(d.y, Vector2(d.x, d.z).length())
		cr.snap()
	# aperçu de l'outil Escalier (touche 9) : l'étage est posé, l'escalier pas encore ; on vise le pied, aperçu VERT
	b.c = c_no_stairs
	b.c.base_y = gy
	b._rebuild()
	b.set_tool("escalier")
	b.door_side = "E"
	b.aim_override = Vector3(1.0, gy, 1.0)
	lab.explorer.teleport(Vector3(1.0, gy + 0.5, 3.9), 0.0)       # dans la pièce, devant l'emplacement de l'escalier
	await _frames(40)
	look.call(Vector3(3.0, gy + 0.9, 1.5))
	await _frames(8)
	await _shot("70_atelier_construction_ouverte")
	b.set_tool("modifier")
	b.aim_override = Vector3.INF
	b.c = c
	b._rebuild()
	# vue de l'escalier, de l'intérieur de la pièce, au pied
	lab.explorer.teleport(Vector3(0.6, gy + 0.5, 1.5), -PI * 0.5)
	await _frames(40)
	cr.yaw = -PI * 0.5
	cr.pitch = 0.25
	cr.snap()
	await _frames(8)
	await _shot("71_maison_escalier_vu_du_pied")
	# on monte réellement (physique du vrai jeu)
	lab.explorer.auto_active = true
	lab.explorer.auto_dir = Vector2(1, 0)
	var y0 := lab.explorer.global_position.y
	var top := y0
	for i in 420:
		await get_tree().physics_frame
		top = maxf(top, lab.explorer.global_position.y)
		if lab.explorer.global_position.y - y0 > 2.9 and lab.explorer.global_position.x > 5.3:
			break          # arrivé sur le palier de l'étage : on s'arrête là
	lab.explorer.auto_active = false
	_check(top - y0 > 2.6 and lab.explorer.global_position.x > 4.0, "on monte l'escalier à pied dans le vrai jeu : +%.2f m jusqu'à l'étage (x = %.1f m)" % [top - y0, lab.explorer.global_position.x])
	await _frames(30)
	cr.yaw = PI * 0.5          # on se retourne : l'escalier qu'on vient de monter, vu depuis l'étage
	cr.pitch = -0.4
	cr.snap()
	await _frames(8)
	await _shot("72_etage_accessible_a_pied")
	# enregistrement de la maison
	var sv := b.save_as("Ma maison à étage")
	_check(bool(sv.get("ok", false)), "la maison est enregistrée dans l'atelier (user://maisons/)")

func _place_houses() -> void:
	await _key(KEY_I)
	var items := AssetCatalog.houses()
	var mine := {}
	for h in items:
		if String(h["name"]).to_lower().contains("maison"):
			mine = h
	_check(not mine.is_empty() and (mine["cat"] == "Mes maisons"), "la maison enregistrée apparaît dans l'inventaire, catégorie « Mes maisons »")
	ed.ui._cat = "Mes maisons"
	ed.ui._fill_cats()
	ed.ui._fill_items()
	var idx := 0
	for i in ed.ui._shown.size():
		if String(ed.ui._shown[i]["id"]) == String(mine["id"]):
			idx = i
	ed.ui._on_item(idx)
	await _frames(40)
	await _shot("80_inventaire_mes_maisons_apercu")
	await _key(KEY_I)
	# première pose : la parcelle acceptée la plus plate
	var best := Vector2.INF
	var best_flat := 1.0e9
	for link in [true, false]:
		for dx in range(-22, 23, 2):
			for dz in range(-22, 23, 2):
				var q := Vector2(dx, dz)
				var cq := ed.doc.col_of(q)
				if not ed.doc.field.has_ground(cq.x, cq.y):
					continue
				var ev := ed.doc.evaluate_house(ed.house_model, Vector2(snappedf(q.x, 0.1), snappedf(q.y, 0.1)), 0, link)
				if bool(ev.get("ok", false)):
					var sl0 := absf(ed.doc.field.ground_at_m(q.x + 3, q.y) - ed.doc.field.ground_at_m(q.x - 3, q.y)) + absf(ed.doc.field.ground_at_m(q.x, q.y + 3) - ed.doc.field.ground_at_m(q.x, q.y - 3))
					if sl0 < best_flat:
						best_flat = sl0
						best = q
		if best != Vector2.INF:
			ed.house_link = link
			break
	_check(best != Vector2.INF, "une parcelle plate acceptée existe (dénivelé %.1f m sur 6 m)" % best_flat)
	if best == Vector2.INF:
		best = _spot(Vector2(-2, -4), 6.0)
	await _cam_aerial(best, 24.0, 0.0, -0.7)
	ed.mouse_override = _sp(_ground(best))
	await _frames(8)
	await _cam_aerial(best, 22.0, 0.0, -0.7)
	ed.mouse_override = _sp(_ground(best))
	await _frames(8)
	await _shot("81_maison_apercu_implantation")
	print("aperçu : ", ed.ghost_text)
	var h0 := ed.doc.plan.houses.size()
	await _click(best)
	await _settle()
	_check(ed.doc.plan.houses.size() == h0 + 1, "clic : première maison posée (%s)" % ed.doc.message)
	await _key(KEY_1)
	await _shot("82_maison_posee_plateau")
	# deuxième maison sur une pente : on sculpte d'abord un versant (vrais traits de pinceau), puis on cherche la parcelle acceptée la plus inclinée
	ed.choose_item(mine)
	var base_pt := _spot(Vector2(12, 6), 5.0)
	for cand in [Vector2(10, -12), Vector2(12, 6), Vector2(-14, 8), Vector2(-12, -10), Vector2(14, 14)]:
		var qq := _spot(cand, 6.0)
		if qq.distance_to(best) > 14.0:
			base_pt = qq
			break
	await _cam_aerial(base_pt, 26.0, 0.0, -0.62)
	await _key(KEY_3)
	ed.brush["mode"] = "monter"
	ed.brush["radius"] = 6.5
	ed.brush["strength"] = 0.45
	for k in 3:
		await _drag([base_pt + Vector2(-8, 0), base_pt + Vector2(-5, 0.5), base_pt + Vector2(-2, 0), base_pt + Vector2(1, -0.5), base_pt + Vector2(4, 0)])
	await _settle()
	await _shot("82b_versant_sculpte_pour_la_maison")
	await _key(KEY_2)
	ed.choose_item(mine)
	var slope_pt := Vector2.INF
	var best_s := -1.0
	for dx in range(-22, 23, 2):
		for dz in range(-22, 23, 2):
			var q2 := Vector2(dx, dz)
			var c2 := ed.doc.col_of(q2)
			if not ed.doc.field.has_ground(c2.x, c2.y):
				continue
			for yaw in 4:
				var ev2 := ed.doc.evaluate_house(ed.house_model, Vector2(snappedf(q2.x, 0.1), snappedf(q2.y, 0.1)), yaw, ed.house_link)
				if bool(ev2.get("ok", false)):
					var sl := absf(ed.doc.field.ground_at_m(q2.x + 3, q2.y) - ed.doc.field.ground_at_m(q2.x - 3, q2.y)) + absf(ed.doc.field.ground_at_m(q2.x, q2.y + 3) - ed.doc.field.ground_at_m(q2.x, q2.y - 3))
					if sl > best_s:
						best_s = sl
						slope_pt = q2
						ed.house_yaw = yaw
	_check(slope_pt != Vector2.INF, "une parcelle en pente acceptée existe (dénivelé %.1f m sur 6 m)" % best_s)
	if slope_pt == Vector2.INF:
		slope_pt = _spot(Vector2(10, 8), 5.0)
	await _cam_aerial(slope_pt, 22.0, 0.0, -0.62)
	ed.mouse_override = _sp(_ground(slope_pt))
	await _frames(8)
	await _shot("83_maison_pente_apercu")
	var info_a := ed.ghost_text
	# ajustement du raccord : sans raccord au chemin, puis avec
	ed.house_link = false
	await _frames(8)
	var info_b := ed.ghost_text
	await _shot("84_maison_pente_raccord_desactive")
	ed.house_link = true
	await _key(KEY_R)
	await _frames(8)
	await _shot("85_maison_pente_orientation_changee")
	await _key(KEY_R, false, false)
	await _key(KEY_R)
	await _key(KEY_R)
	await _frames(4)
	_check(info_a != "" and info_b != "", "l'aperçu explique l'implantation et le raccord (K : raccord au chemin, R : orientation)")
	var h1 := ed.doc.plan.houses.size()
	var top0 := ed.doc.field.top.duplicate()
	await _click(slope_pt)
	await _settle()
	var placed := ed.doc.plan.houses.size() == h1 + 1
	if not placed:
		# repli : l'orientation a pu changer l'acceptation ; on pose avec la dernière orientation valable
		for yaw in 4:
			var ev3 := ed.doc.evaluate_house(ed.house_model, Vector2(snappedf(slope_pt.x, 0.1), snappedf(slope_pt.y, 0.1)), yaw, true)
			if bool(ev3.get("ok", false)):
				ed.house_yaw = yaw
				await _click(slope_pt)
				await _settle()
				break
	_check(ed.doc.plan.houses.size() == h1 + 1, "deuxième maison posée sur la pente : plateforme et raccord au chemin créés (%s)" % ed.doc.message)
	var changed := DictChanged.count(top0, ed.doc.field.top)
	_check(changed > 20, "le terrain s'adapte sous la maison (%d colonnes ajustées)" % changed)
	await _key(KEY_1)
	await _shot("86_maison_pente_posee")
	await _cam_aerial(Vector2(0, 0), 42.0, 0.0, -0.8)
	await _shot("87_deux_maisons_vue_aerienne")

class DictChanged:
	static func count(a: PackedInt32Array, b: PackedInt32Array) -> int:
		var n := 0
		for i in mini(a.size(), b.size()):
			if a[i] != b[i]:
				n += 1
		return n

func _save_reopen_play() -> void:
	# dialogue de sauvegarde (vrai dialogue de l'éditeur), puis enregistrement
	await _key(KEY_S, true)
	await _frames(6)
	await _shot("90_dialogue_enregistrer")
	var d = ed.ui._dialog
	_check(d != null, "Ctrl+S sur une carte jamais enregistrée : dialogue « Enregistrer la carte »")
	ed.ui.close_dialog()
	var r := ed.save_as("ile_creative_demo")
	_check(bool(r["ok"]) and not ed.doc.is_dirty(), "carte enregistrée : %s" % ed.session.path.get_file())
	var objs := ed.doc.plan.objects.size()
	var houses := ed.doc.plan.houses.size()
	var tops := ed.doc.field.top.duplicate()
	# l'enregistrement relu à part doit redonner exactement le relief affiché
	var d2 := MapDoc.new()
	d2.open_from(ed.session.path)
	var ndiff := 0
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for i in tops.size():
		if i < d2.field.top.size() and tops[i] != d2.field.top[i]:
			ndiff += 1
			lo = Vector2i(mini(lo.x, i % ed.doc.field.n), mini(lo.y, i / ed.doc.field.n))
			hi = Vector2i(maxi(hi.x, i % ed.doc.field.n), maxi(hi.y, i / ed.doc.field.n))
	_check(ndiff == 0 and d2.field.top.size() == tops.size(), "enregistrement relu à part : relief identique (%d colonnes différentes %s–%s, tailles %d / %d)" % [ndiff, lo, hi, tops.size(), d2.field.top.size()])
	# modification non enregistrée → avertissement à la sortie
	ed.doc.add_object("barrel_set", _spot(Vector2(3, 3), 4.0), 0.0, 1.0)
	await ed.sync()
	var asked := MapSession.ask(ed.ui, func() -> void: pass)
	await _frames(6)
	_check(not asked, "carte modifiée : une action qui la remplacerait ouvre « Modifications non enregistrées »")
	await _shot("91_dialogue_modifications_non_enregistrees")
	var dl := ed.ui.get_node_or_null("../DialogueSortie")
	for n in ed.ui.get_children():
		if n.name == "DialogueSortie":
			n.queue_free()
	for n in ed.get_children():
		if n.name == "DialogueSortie":
			n.queue_free()
	ed.doc.undo()
	await ed.sync()
	# réouverture dans une nouvelle session
	ed.session.save()
	App.open(App.CREATIVE_SCENE, {"mode": "ouvrir", "path": ed.session.path})
	await _frames(10)
	await _wait_editor()
	await _settle()
	_check(ed.doc.plan.objects.size() == objs + 0 or ed.doc.plan.objects.size() == objs, "carte rouverte : %d objets, %d maison(s)" % [ed.doc.plan.objects.size(), ed.doc.plan.houses.size()])
	_check(ed.doc.plan.houses.size() == houses and ed.doc.field.top == tops, "carte rouverte : relief et maisons identiques à l'enregistrement")
	await _cam_aerial(Vector2(0, 0), 52.0, 0.0, -0.72)
	await _shot("92_carte_rouverte_vue_aerienne")
	var h: Dictionary = ed.doc.plan.houses[0]
	var hp: Vector2 = h["pos"]
	var hg := float(h["ground_m"])
	await _cam_fp(Vector3(hp.x - 6.0, hg + 3.5, hp.y + 9.0), Vector3(hp.x, hg + 1.5, hp.y))
	await _shot("93_carte_rouverte_premiere_personne_vol")
	# première personne : on pose un objet en visant le sol au centre de l'écran (souris capturée → réticule)
	var bench_item := {}
	for q in AssetCatalog.items():
		if String(q["id"]) == "decorative_bench":
			bench_item = q
	ed.mouse_override = Vector2.INF
	ed.aim_override = Vector3.INF
	ed.choose_item(bench_item)
	ed.f_pitch = -0.45
	ed._apply_cam()
	await _frames(12)
	await _shot("93b_premiere_personne_poser_visee_centre")
	var ob0 := ed.doc.plan.objects.size()
	ed.place_here()
	await _settle()
	_check(ed.doc.plan.objects.size() == ob0 + 1 or ed.aim() == Vector3.INF, "première personne : objet posé en visant le sol (réticule au centre)")
	ed.set_tool("select")
	ed.undo()
	await _settle()
	# mode jeu : marche réelle, collisions
	ed.set_mode("play")
	await _frames(30)
	ed.explorer.teleport(Vector3(hp.x, hg + 0.3, hp.y + 8.0), 0.0)
	ed.camrig.yaw = 0.0
	ed.camrig.pitch = -0.05
	ed.camrig.snap()
	for i in 40:
		await get_tree().physics_frame
	await _frames(6)
	await _shot("94_mode_jeu_devant_la_maison")
	# marche jusqu'à la porte et à l'intérieur (la porte est au sud, vers +z)
	ed.explorer.auto_active = true
	ed.explorer.auto_dir = Vector2(0, -1)
	var z0 := ed.explorer.global_position.z
	for i in 260:
		await get_tree().physics_frame
	ed.explorer.auto_active = false
	_check(absf(ed.explorer.global_position.z - hp.y) < 5.0, "mode jeu : le personnage marche jusqu'à la maison et y entre (z = %.1f, maison en %.1f)" % [ed.explorer.global_position.z, hp.y])
	ed.camrig.yaw = PI          # à l'intérieur, on se retourne vers la porte
	ed.camrig.pitch = -0.05
	ed.camrig.snap()
	await _frames(6)
	await _shot("95_mode_jeu_dans_la_maison")
	await _key(KEY_P)
	_check(ed.mode != "play", "touche P : retour à l'éditeur depuis le mode jeu")
	await _frames(10)

func _undo_protect() -> void:
	# --- historique et annulation
	await _cam_aerial(ed._island_center(), 46.0, 0.0, -0.75)
	var c0 := ed.doc.plan.objects.size()
	var spt := _spot(Vector2(6, -2), 4.0)
	ed.choose_item({"id": "market_stall", "name": "Étal de marchand", "cat": "Marché et village", "kind": "asset", "size": Vector3(2, 2, 1)})
	await _click(spt)
	await _settle()
	var placed := ed.doc.plan.objects.size() == c0 + 1
	ed.ui._toggle_history()
	await _frames(4)
	await _shot("100_historique_avant_annulation")
	await _key(KEY_Z, true)
	await _settle()
	_check(placed and ed.doc.plan.objects.size() == c0, "Ctrl+Z : la pose de l'étal est annulée")
	ed.ui.refresh()
	await _frames(4)
	await _shot("101_historique_apres_annulation_retablir")
	await _key(KEY_Y, true)
	await _settle()
	_check(ed.doc.plan.objects.size() == c0 + 1, "Ctrl+Y : rétablie")
	await _key(KEY_Z, true)
	await _settle()
	ed.ui._toggle_history()
	# --- zone protégée + objet verrouillé face à une régénération ciblée
	var pz := _spot(Vector2(-12, 8), 4.0)
	await _cam_aerial(pz, 22.0, 0.0, -0.75)
	await _key(KEY_5)
	ed.map_sub = "protege"
	ed.brush["radius"] = 3.2
	ed.ui._sig = ""
	await _drag([pz + Vector2(-1.5, 0), pz, pz + Vector2(1.5, 0.5)])
	await _settle()
	# arbres générés tout autour, un verrouillé
	await _key(KEY_6)
	ed.gen["preset"] = "foret"
	ed.gen["radius"] = 8.0
	ed.gen["densite"] = 80
	ed.gen["seed"] = 9
	await _click(pz)
	await _settle()
	var gen_ids := []
	for o in ed.doc.plan.objects:
		if String(o["group"]) == "foret" and (o["pos"] as Vector2).distance_to(pz) < 8.0:
			gen_ids.append(String(o["id"]))
	_check(gen_ids.size() >= 5, "forêt autour de la zone protégée : %d objets" % gen_ids.size())
	# on verrouille le premier arbre hors zone protégée
	var lock_id := ""
	for id in gen_ids:
		var o := ed.doc.object_by_id(id)
		var cc := ed.doc.col_of(o["pos"])
		if not ed.doc.is_protected(ed.doc.field.idx(cc.x, cc.y)):
			lock_id = id
			break
	ed.selected = lock_id
	ed.set_tool("select")
	await _key(KEY_L)
	_check(bool(ed.doc.object_by_id(lock_id)["locked"]), "L : un arbre est verrouillé")
	var lock_pos: Vector2 = ed.doc.object_by_id(lock_id)["pos"]
	var prot_cols := 0
	var top_prot := {}
	for i in ed.doc.field.n * ed.doc.field.n:
		if ed.doc.plan.layers.mask[i] != 0:
			prot_cols += 1
			top_prot[i] = ed.doc.field.top[i]
	await _cam_aerial(pz, 20.0, 0.0, -0.75)
	await _shot("110_zone_protegee_avant_regeneration")
	var before_ids := {}
	for o in ed.doc.plan.objects:
		before_ids[String(o["id"])] = (o["pos"] as Vector2)
	# régénération ciblée : relief (rectangle) puis composition (nouvelle graine)
	var rg := ed.doc.regenerate(Rect2(pz - Vector2(8, 8), Vector2(16, 16)))
	ed.gen["seed"] = 10
	ed.set_tool("generate")
	await _click(pz)
	await _settle()
	await _cam_aerial(pz, 20.0, 0.0, -0.75)
	await _shot("111_zone_protegee_apres_regeneration")
	var same_prot := true
	for i in top_prot:
		if ed.doc.field.top[i] != top_prot[i]:
			same_prot = false
	_check(prot_cols > 0 and same_prot, "zone protégée (%d colonnes) : relief inchangé après régénération (relief : %s)" % [prot_cols, String(rg.get("reason", "%d colonnes modifiées ailleurs" % int(rg.get("changed", 0))))])
	var lock_after := ed.doc.object_by_id(lock_id)
	_check(not lock_after.is_empty() and (lock_after["pos"] as Vector2).is_equal_approx(lock_pos), "objet verrouillé : toujours là, même position")
	var changed_objs := 0
	for id in gen_ids:
		if ed.doc.object_by_id(id).is_empty():
			changed_objs += 1
	_check(changed_objs >= 1, "la régénération a bien remplacé les autres objets générés (%d retirés)" % changed_objs)
	var in_prot := 0
	for id in gen_ids:
		var o2 := ed.doc.object_by_id(id)
		if not o2.is_empty():
			var c3 := ed.doc.col_of(o2["pos"])
			if ed.doc.is_protected(ed.doc.field.idx(c3.x, c3.y)):
				in_prot += 1
	await _cam_aerial(pz + Vector2(0, 4), 14.0, 0.5, -0.5)
	await _shot("112_zone_protegee_apres_vue_rapprochee")
	print("objets en zone protégée conservés : %d" % in_prot)
