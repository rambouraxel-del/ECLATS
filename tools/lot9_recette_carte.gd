extends Node
## Essai JOUÉ + captures du LOT 9, dans le VRAI jeu lancé au menu :
##   godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/lot9_recette.gd
## (partie B seule) A. laboratoire (île vide, pente) : trois habitations (/generer habitation …, barre T, Entrée, Ctrl+Z), recette et contraintes affichées,
##    composition marché + végétation sur une zone peinte (aperçu, réglages, application, annulation en une opération).
## B. éditeur de carte : placement automatique d'une habitation (orientation d'après le chemin), refus expliqué, 3D visitable.
const OUT := "/tmp/claude-0/-home-user/a63a7b17-b085-5a47-af76-319612b62b36/scratchpad/l8"
const DT := 1.0 / 60.0

var scene: DevLab
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

func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _key(code: int, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		Input.parse_input_event(e)
		await get_tree().process_frame

func _command(text: String) -> void:
	await _key(KEY_T)
	scene.ui.bar.text = text
	scene.ui.bar.text_submitted.emit(text)
	await _frames(25)

func _wait_scene(cls: String) -> Node:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 600000:
		var s := get_tree().current_scene
		if s != null and s.name == cls and (cls != "MapIsland" or bool(s.get("ready_to_play"))) and (cls != "DevLabIsland" or (s as DevLab).ready_to_play):
			await _frames(6)
			return s
		await get_tree().process_frame
		OS.delay_msec(5)
	return null

func _open_from_menu(label_start: String) -> void:
	var menu := get_tree().current_scene
	menu.call("show_page", "dev")
	await _frames(3)
	for bt in menu.find_children("*", "Button", true, false):
		if (bt as Button).text.begins_with(label_start):
			(bt as Button).pressed.emit()
			return
	_check(false, "bouton « %s » introuvable" % label_start)

func _wait_lab(kind: String) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 300000:
		var s := get_tree().current_scene
		if s is DevLab and (s as DevLab).kind == kind and (s as DevLab).ready_to_play:
			scene = s
			return
		await get_tree().process_frame
		OS.delay_msec(5)

func _look_at(p: Vector3) -> void:
	var cam := scene.camrig.cam
	var d := p - cam.global_position
	scene.camrig.yaw = atan2(-d.x, -d.z)
	scene.camrig.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	scene.camrig.snap()
	await _frames(3)

func _view(player: Vector2, target: Vector3) -> void:
	scene.place_player(player.x, player.y, 0.0, 0.0)
	await _phys(8)
	await _look_at(target)

func _same(a: LabWorld, snap: Dictionary) -> bool:
	return a.field.top == snap["top"] and a.field.zone == snap["zone"] and a.field.material == snap["mat"] and a.occ.tag == snap["tag"] and a.occ.owner == snap["own"] and a.occ.items.size() == int(snap["items"])

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(20)
	# ------------------------------------------------------------ B. éditeur : placement automatique
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
	ed._g_seed.value = 21
	var gb := ed.find_children("*", "Button", true, false).filter(func(b) -> bool: return (b as Button).text.begins_with("Générer"))
	(gb[0] as Button).pressed.emit()
	await _frames(6)
	await _key(KEY_9)
	var doc := ed.doc
	var ab := ed.find_child("BtnAuto", true, false) as Button
	# refus naturel : la maison en L (8,8 × 8,3 m) ne tient sur aucune parcelle de la graine 21
	ed.auto_variant = 3
	ed.auto_seed = 3
	ed.auto_fit = Vector2(9.0, 8.5)
	var top0 := doc.field.top.duplicate()
	ab.pressed.emit()
	await _frames(6)
	_check(doc.plan.houses.is_empty() and "Aucune parcelle compatible" in ed._msg.text and doc.field.top == top0, "maison en L sur la graine 21 : aucune parcelle, refus expliqué (« %s »)" % ed._msg.text.left(150))
	cv.fit()
	await _frames(4)
	await _shot("20_carte_refus_naturel_maison_en_L")
	# la cabane, elle, tient : placement automatique
	ed.auto_variant = 1
	ed.auto_fit = Vector2(5.0, 4.5)
	ab.pressed.emit()
	await _frames(6)
	_check(doc.plan.houses.size() == 1 and doc.undo_stack.size() == 1, "placement automatique : habitation posée (%s)" % doc.message.left(120))
	var h: Dictionary = doc.plan.houses[0]
	cv.view_center = h["pos"]
	cv.px_per_m = 15.0
	cv.queue_redraw()
	await _frames(4)
	await _shot("21_carte_placement_automatique")
	var nm := String(h["name"])
	await _key(KEY_Z, true)
	_check(doc.plan.houses.is_empty() and doc.field.top == top0, "Ctrl+Z : habitation retirée, terrain restauré")
	# refus : tout est protégé
	doc.begin_op("masque")
	for i in doc.plan.layers.mask.size():
		doc.plan.layers.mask[i] = 1
	doc.finish_op(false)
	ed._refresh(true)
	var depth := doc.undo_stack.size()
	ab.pressed.emit()
	await _frames(6)
	_check(doc.plan.houses.is_empty() and doc.undo_stack.size() == depth, "tout est protégé : aucune pose forcée")
	_check("zone protégée" in ed._msg.text, "refus expliqué : %s" % ed._msg.text.left(120))
	cv.fit()
	await _frames(4)
	await _shot("22_carte_refus_zone_protegee")
	await _key(KEY_Z, true)
	_check(doc.plan.layers.count_mask() == 0, "masque retiré (Ctrl+Z)")
	ed.auto_variant = 2
	ed.auto_fit = Vector2(8.0, 6.5)
	ab.pressed.emit()
	await _frames(6)
	_check(doc.plan.houses.size() == 1, "« maison à deux pièces » posée automatiquement : %s" % doc.message.left(100))
	# 3D : visite
	var pf := MapEditor.DIR + "carte_habitation_lot9.eclats-carte.json"
	doc.export_to(pf)
	ed._on_verify()
	isl = await _wait_scene("MapIsland")
	_check(isl != null and (isl.get("house_nodes") as Array).size() == 1, "île 3D : l'habitation est là")
	var plan: IslandPlan = isl.get("plan")
	var hh: Dictionary = plan.houses[0]
	var model: Construction = Construction.from_dict(hh["model"])["construction"]
	var ex: Explorer = isl.get("explorer")
	var np := HousePad.nearest_path(plan.paths, hh["door"])
	isl.call("place_player", (np["q"] as Vector2).x, (np["q"] as Vector2).y, 0.0, 0.0)
	await get_tree().physics_frame
	await _frames(6)
	var fp := HousePad.footprint(model)
	var dir := HousePad.rot_i((fp["entrance"] as Dictionary)["dir"], int(hh["yaw"]))
	var okw := await _walk(ex, hh["door"], 0.5)
	var inside := (hh["pos"] as Vector2) + Vector2(dir) * -1.0
	var okw2 := await _walk(ex, inside, 0.8)
	_check(okw and okw2 and (hh["rect"] as Rect2).has_point(Vector2(ex.global_position.x, ex.global_position.z)) and int(isl.get("falls")) == 0, "du chemin jusque dans l'habitation par le raccord (x %.1f, z %.1f)" % [ex.global_position.x, ex.global_position.z])
	var out_p := (hh["door"] as Vector2) + Vector2(dir) * 7.0
	ex.auto_active = false
	ex.teleport(Vector3(out_p.x, (isl.get("lab") as LabWorld).ground_y(out_p.x, out_p.y) + 0.1, out_p.y), 0.0)
	var d := (hh["pos"] as Vector2) - out_p
	isl.get("camrig").yaw = atan2(-d.x, -d.y)
	isl.get("camrig").pitch = -0.06
	isl.get("camrig").snap()
	await get_tree().physics_frame
	await _frames(10)
	await _shot("23_habitation_en_3d")
	report["duree_s"] = (Time.get_ticks_msec() - t0) / 1000
	var bad_n := 0
	for c in report["controles"]:
		if not c["ok"]:
			bad_n += 1
	report["echecs"] = bad_n
	var f := FileAccess.open(OUT + "/lot9_carte_rapport.json", FileAccess.WRITE)
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
