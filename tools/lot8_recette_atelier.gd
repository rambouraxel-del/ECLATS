extends Node
## Essai joué + captures de l'ATELIER DE CONSTRUCTION (Lot 8), dans le VRAI jeu lancé au menu :
##   godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/lot8_recette_atelier.gd
## menu → Outils développeur → salle grise → B → sol, mur, porte, fenêtre, modification refusée, pièce rapide, toit, étage, enregistrement.
## Clics, touches (B, 1-8, Entrée, X, Ctrl+Z, PgUp / PgDn, H, J, K, Y) : vrais événements d'entrée. Le joueur est placé (pas marché) pour viser.
const OUT := "/tmp/claude-0/-home-user/a63a7b17-b085-5a47-af76-319612b62b36/scratchpad/l8"

var scene: DevLab
var b: BuildMode
var report := {"controles": []}

func _check(cond: bool, label: String) -> void:
	report["controles"].append({"ok": cond, "controle": label})
	print(("  OK    " if cond else "  ÉCHEC ") + label)

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
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

func _click(button := MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = get_viewport().get_visible_rect().size * 0.5
		Input.parse_input_event(e)
		for i in 3:
			await get_tree().process_frame

func _look_at(p: Vector3) -> void:
	var cam := scene.camrig.cam
	var d := p - cam.global_position
	scene.camrig.yaw = atan2(-d.x, -d.z)
	scene.camrig.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	scene.camrig.snap()
	await _frames(3)

func _stand(x: float, z: float) -> void:
	scene.place_player(x, z, 0.0, 0.0)
	await _phys(8)
	await _frames(2)

## Se place à `dist` mètres de (x, z) côté `side` (+z par défaut), vise le point (x, y, z) et renvoie la case visée (u).
func _aim_xz(x: float, z: float, y_extra := 0.0, dist := 5.0, from := Vector2(0, 1)) -> Vector2i:
	await _stand(x + from.x * dist, z + from.y * dist)
	var gy := scene.lab.ground_y(x, z)
	await _look_at(Vector3(x, gy + y_extra, z))
	await _frames(2)
	return b.aim_u

func _click_u(ux: int, uz: int, y_extra := 0.0, from := Vector2(0, 1), dist := 5.0) -> void:
	var got := await _aim_xz(float(ux) * 0.5, float(uz) * 0.5, y_extra, dist, from)
	_check(got == Vector2i(ux, uz), "le réticule vise la case (%d ; %d) — lu : (%d ; %d), aimantation : %s" % [ux, uz, got.x, got.y, b.aim_snap])
	await _click()

func _wait_lab(kind: String) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 300000:
		var s := get_tree().current_scene
		if s is DevLab and (s as DevLab).kind == kind and (s as DevLab).ready_to_play:
			scene = s
			return
		await get_tree().process_frame
		OS.delay_msec(5)

func _open_from_menu(label_start: String) -> void:
	var menu := get_tree().current_scene
	menu.call("show_page", "dev")
	await _frames(3)
	for bt in menu.find_children("*", "Button", true, false):
		if (bt as Button).text.begins_with(label_start):
			(bt as Button).pressed.emit()
			return
	_check(false, "bouton « %s » introuvable" % label_start)

func _body_hits(x: float, y: float, z: float) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y, z))
	q.collision_mask = 1
	for h in scene.lab.get_world_3d().direct_space_state.intersect_shape(q, 8):
		if (h["collider"] as Node).name == "Collisions":
			return true
	return false

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(20)
	await _open_from_menu("Laboratoire développeur — salle grise")
	await _wait_lab("room")
	b = scene.builder
	await _phys(30)
	_check(b != null and not b.active, "atelier prêt, mode construction fermé au départ")
	await _key(KEY_B)
	_check(b.active and b._layer.visible and not scene.ui.panel.visible, "B : le mode construction s'ouvre (panneau du labo masqué)")
	_check(b.stock == 200, "stock de démonstration : 200 unités")
	# ------------------------------------------------------------ sol de 1,50 × 1,50 m : aperçu, annulation, confirmation, Ctrl+Z
	await _key(KEY_1)
	_check(b.tool == "sol", "touche 1 : outil Sol")
	await _click_u(0, 0)
	_check(b.has_corner, "premier coin posé")
	var gy := scene.lab.ground_y(0, 0)
	var aim2 := await _aim_xz(1.5, 1.5)
	_check(aim2 == Vector2i(3, 3) and b.live.get("ok", false) and int(b.live["delta"]) == 3, "second coin visé : l'aperçu annonce 3 unités (%s)" % String(b.live.get("text", "")))
	await _frames(4)
	await _shot("00_sol_apercu_cout")
	await _click()
	_check(not b.pending.is_empty() and b.stock == 200, "clic : aperçu verrouillé, stock toujours à 200")
	await _key(KEY_X)
	_check(b.pending.is_empty() and b.stock == 200 and b.c.is_empty(), "X : aperçu annulé avant confirmation, rien n'est débité")
	await _click_u(0, 0)
	await _click_u(3, 3)
	await _key(KEY_ENTER)
	_check(b.stock == 197 and b.c.elements.size() == 1, "Entrée : 3 unités débitées (stock %d)" % b.stock)
	await _key(KEY_Z, true)
	_check(b.stock == 200 and b.c.is_empty(), "Ctrl+Z : sol retiré, stock rendu (%d)" % b.stock)
	# ------------------------------------------------------------ mur de 6 m au nord, porte et fenêtre
	await _key(KEY_3)
	await _click_u(-6, -12)
	await _click_u(6, -12)
	_check(not b.pending.is_empty() and "Mur 6,00 m × 2,5 m" in String(b.pending["text"]), "mur : aperçu avec dimensions et coût (%s)" % String(b.pending.get("text", "")))
	await _frames(4)
	scene.place_player(0.0, 0.0, 0.0, -0.1)
	await _phys(6)
	await _look_at(Vector3(0, gy + 1.0, -6.0))
	await _frames(4)
	await _shot("01_mur_apercu_dimensions_cout")
	await _key(KEY_ENTER)
	_check(b.stock == 185 and b.c.of_type("wall").size() == 1, "mur posé (15 unités, stock %d)" % b.stock)
	await _phys(3)
	await _key(KEY_4)
	await _stand(0.0, 0.0)
	await _look_at(Vector3(0.0, b.c.level_y(0) + 1.0, -6.0))
	await _frames(4)
	_check(b.live.get("ok", false) and "Porte" in String(b.live.get("text", "")), "porte : aperçu de la découpe (%s)" % String(b.live.get("text", "")))
	await _click()
	await _key(KEY_ENTER)
	_check(b.c.count_openings() == 1 and b.stock == 181, "porte posée (4 unités, stock %d)" % b.stock)
	await _key(KEY_5)
	await _look_at(Vector3(-2.0, b.c.level_y(0) + 1.1, -6.0))
	await _frames(4)
	await _click()
	await _key(KEY_ENTER)
	_check(b.c.count_openings() == 2 and b.stock == 179, "fenêtre posée (2 unités, stock %d)" % b.stock)
	await _phys(5)
	var my := b.c.level_y(0) + 0.95
	_check(_body_hits(1.6, my, -6.0) and _body_hits(-0.9, my, -6.0) and not _body_hits(0.0, my, -6.0), "collisions : mur arrêtant le joueur, passage de la porte libre")
	await _key(KEY_8)
	await _stand(0.0, -2.0)
	await _look_at(Vector3(0.0, b.c.level_y(0) + 0.3, -3.0))
	await _frames(2)
	await _look_at(Vector3(0.0, b.c.level_y(0) + 1.2, -6.0))
	b.sel_id = -1
	await _frames(6)
	await _shot("02_porte_et_fenetre_decoupes")
	# marche réelle à travers la porte
	scene.place_player(0.0, -3.5, 0.0, 0.0)
	await _phys(10)
	Input.action_press("move_forward")
	await _phys(110)
	Input.action_release("move_forward")
	_check(scene.explorer.global_position.z < -6.6, "le joueur traverse réellement la porte (z = %.2f)" % scene.explorer.global_position.z)
	# ------------------------------------------------------------ modification refusée
	await _key(KEY_8)
	await _stand(2.0, -2.0)
	await _look_at(Vector3(2.0, b.c.level_y(0) + 1.0, -6.0))
	await _frames(3)
	await _click()
	_check(b.sel_id >= 0, "outil Modifier : mur choisi")
	var sig := b.c.signature()
	await _key(KEY_Y)
	for i in 1:
		await _key(KEY_J)
	_check(b.c.signature() == sig and not b._refusal.is_empty() and "ne tiendrait plus" in String(b._refusal["reasons"][0]), "J (raccourcir par le début) : refusé, construction intacte")
	await _frames(6)
	await _shot("03_modification_refusee_ouverture")
	await _key(KEY_Y)
	await _key(KEY_K)
	_check(not b.pending.is_empty() and int(b.pending["delta"]) == 2, "K (prolonger de 0,5 m) : aperçu, 2 unités de différence (15 → 17)")
	await _key(KEY_ENTER)
	_check(b.stock == 177, "différence payée seulement : stock %d" % b.stock)
	# ------------------------------------------------------------ pièce rapide, toit, étage
	await _key(KEY_6)
	await _key(KEY_O)
	_check(b.door_side == "E", "O : porte côté est")
	await _key(KEY_O)
	await _key(KEY_O)
	await _key(KEY_O)
	_check(b.door_side == "S", "O (4 fois) : retour au sud")
	await _click_u(-6, -2, 0.0, Vector2(0, 1), 7.0)
	await _click_u(6, 6, 0.0, Vector2(0, 1), 5.0)
	_check(not b.pending.is_empty() and "Pièce 6,00 × 4,00 m" in String(b.pending["text"]), "pièce 6 × 4 m : aperçu (%s)" % String(b.pending.get("text", "")))
	await _frames(4)
	await _key(KEY_ENTER)
	_check(b.c.of_type("floor").size() == 1 and b.c.of_type("wall").size() == 5, "pièce posée : plancher + 4 murs")
	var stock_room := b.stock
	await _key(KEY_7)
	await _stand(0.0, 9.0)
	await _look_at(Vector3(0.0, b.c.level_y(0) + 1.4, 3.0))
	await _frames(4)
	_check(b.live.get("ok", false), "toit : aperçu ajusté à l'emprise (%s)" % String(b.live.get("text", "")))
	await _click()
	await _key(KEY_ENTER)
	_check(b.c.of_type("roof").size() == 1 and b.stock < stock_room, "toit posé")
	await _key(KEY_8)
	await _stand(-4.0, 11.0)
	await _look_at(Vector3(0.0, b.c.level_y(0) + 1.5, 1.0))
	await _frames(6)
	await _shot("04_piece_avec_toit")
	# marche dans la pièce par la porte sud (x = 0, z = 3)
	scene.place_player(0.0, 6.0, 0.0, 0.0)
	await _phys(10)
	Input.action_press("move_forward")
	await _phys(110)
	Input.action_release("move_forward")
	_check(scene.explorer.global_position.z < 2.2 and scene.explorer.global_position.z > -1.6, "le joueur entre dans la pièce par la porte (z = %.2f)" % scene.explorer.global_position.z)
	# étage : on défait le toit, on monte d'un niveau, pièce à l'étage puis toit
	await _key(KEY_Z, true)
	_check(b.c.of_type("roof").is_empty(), "Ctrl+Z : toit retiré")
	await _key(KEY_PAGEUP)
	_check(b.level == 1, "PgUp : niveau 1")
	await _key(KEY_6)
	await _stand(0.0, 14.0)
	var y1 := b.c.level_y(1)
	await _look_at(Vector3(-3.0, y1, -1.0))
	_check(b.aim_u == Vector2i(-6, -2), "à l'étage, la visée suit le plan du niveau 1 (case %d ; %d)" % [b.aim_u.x, b.aim_u.y])
	await _click()
	await _look_at(Vector3(3.0, y1, 3.0))
	await _click()
	await _key(KEY_ENTER)
	_check(b.c.slabs(1).size() == 1 and b.c.of_type("wall", 1).size() == 4, "pièce d'étage posée (sans porte)")
	await _key(KEY_7)
	await _stand(0.0, 11.0)
	await _look_at(Vector3(0.0, y1 + 1.4, 3.0))
	await _frames(4)
	var live_roof := String(b.live.get("text", "")) + " " + str(b.live.get("reasons", []))
	_check(not b.live.get("ok", true) and "Stock insuffisant" in live_roof, "toit de l'étage : stock insuffisant, aperçu refusé et expliqué")
	await _click()
	_check(b.pending.is_empty() and b.stock == 25, "clic sur un aperçu refusé : rien n'est posé, rien n'est débité")
	await _shot("03b_stock_insuffisant")
	b._layer.find_child("BtnRecharger", true, false).pressed.emit()
	_check(b.stock == 200, "bouton « Recharger le stock de démo » : 200 unités")
	await _frames(3)
	await _click()
	await _key(KEY_ENTER)
	_check(b.c.of_type("roof").size() == 1 and int(b.c.of_type("roof")[0]["lv"]) == 1, "toit posé sur l'étage (%s ; tool=%s level=%d pending=%s)" % [live_roof, b.tool, b.level, str(b.pending.get("text", ""))])
	await _key(KEY_8)
	await _stand(-5.0, 12.0)
	await _look_at(Vector3(0.0, 3.0, 1.0))
	await _frames(8)
	await _shot("05_etage_actif_rdc_attenue")
	await _key(KEY_PAGEDOWN)
	_check(b.level == 0, "PgDn : retour au niveau 0")
	await _frames(8)
	await _shot("06_rdc_actif_etage_attenue")
	# ------------------------------------------------------------ enregistrement
	b.open_file_dialog()
	b._file_name.text = "Maison de l'atelier"
	await _frames(3)
	var save_btn := b._file_dialog.find_child("BtnEnregistrer", true, false) as Button
	save_btn.pressed.emit()
	await _frames(3)
	var path := b.file_path_for("Maison de l'atelier")
	_check(FileAccess.file_exists(path), "bouton Enregistrer : fichier écrit (%s)" % ProjectSettings.globalize_path(path))
	report["fichier"] = ProjectSettings.globalize_path(path)
	await _shot("07_dialogue_enregistrer")
	b._close_file_dialog()
	var n_el := b.c.elements.size()
	await _key(KEY_B)
	_check(not b.active and scene.ui.panel.visible, "B : sortie du mode construction, panneau du labo rétabli")
	report["duree_s"] = (Time.get_ticks_msec() - t0) / 1000
	var bad_n := 0
	for c in report["controles"]:
		if not c["ok"]:
			bad_n += 1
	report["echecs"] = bad_n
	report["elements"] = n_el
	var f := FileAccess.open(OUT + "/lot8_atelier_rapport.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("== %d contrôle(s), %d échec(s) en %d s ==" % [report["controles"].size(), bad_n, report["duree_s"]])
	get_tree().quit()
