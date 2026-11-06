extends Node
## Essai joué + captures du laboratoire (Lot 6), dans le VRAI jeu lancé au menu :
##   godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/lot6_captures_lab.gd
## menu → Outils développeur → salle grise → point, rectangle 3,50 × 3,50 m, maison (commande), confirmation, Ctrl+Z ;
## retour au menu → île vide → même recette sur la pente → pinceau (aplanir) → annulation.
## Les entrées (clics, touches T / Ctrl+Z / Entrée) sont de vrais événements d'entrée ; seul le déplacement du joueur est téléporté.
const OUT := "/tmp/claude-0/-home-user/a63a7b17-b085-5a47-af76-319612b62b36/scratchpad/l6"

var scene: DevLab
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

func _click(button: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(e)
	for i in 3:
		await get_tree().process_frame           # l'événement est traité au plus tard au bout de quelques images

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
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(label_start):
			(b as Button).pressed.emit()
			return
	_check(false, "bouton « %s » introuvable" % label_start)

func _aim_ground(x: float, z: float, yaw: float, pitch: float, from_dist := 6.0) -> void:
	# pose le joueur à `from_dist` de (x, z), regard sur ce point (le déplacement réel est éprouvé ailleurs)
	var px := x + sin(yaw) * from_dist
	var pz := z + cos(yaw) * from_dist
	scene.place_player(px, pz, yaw, pitch)

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(20)
	# ------------------------------------------------------------ salle grise
	await _open_from_menu("Laboratoire développeur — salle grise")
	await _wait_lab("room")
	_check(scene != null and App.capture_on_resume, "salle grise ouverte depuis « Outils développeur » (première personne)")
	var ctl := scene.ctl
	var sel := scene.sel
	var lab := scene.lab
	await _phys(30)
	await _shot("00_salle_depart")
	# point : vrai clic au réticule
	scene.place_player(0.0, 6.0, 0.0, -0.32)
	await _phys(20)
	await _frames(4)
	sel.set_tool(LabSelection.Tool.POINT)
	await _frames(3)
	_check(sel.aim.x < 1.0e8, "le réticule vise le sol (%.1f ; %.1f)" % [sel.aim.x, sel.aim.z])
	await _click(MOUSE_BUTTON_LEFT, true)
	await _click(MOUSE_BUTTON_LEFT, false)
	_check(sel.has_point(), "outil Point : un clic fixe le point (%.1f ; %.1f m)" % [sel.point.x, sel.point.y])
	var r1: Dictionary = ctl.request("arbre", {"espece": "oak", "seed": 7})
	_check(bool(r1["ok"]), "arbre : aperçu au point visé")
	await _frames(4)
	await _shot("04a_salle_point_arbre_apercu")
	var c1: Dictionary = await ctl.confirm()
	_check(bool(c1["ok"]) and lab.stack.size() == 1, "arbre : confirmé")
	await _key(KEY_Z, true)
	await _frames(40)
	_check(lab.stack.is_empty(), "Ctrl+Z (touche réelle) annule l'arbre")
	sel.clear_all()
	# rectangle : deux vrais clics, emprise imposée 3,50 × 3,50 m
	sel.set_tool(LabSelection.Tool.RECT)
	sel.lock_size = true
	scene.place_player(-0.6, 5.0, 0.0, -0.45)
	await _phys(20)
	await _frames(4)
	await _click(MOUSE_BUTTON_LEFT, true)
	await _click(MOUSE_BUTTON_LEFT, false)
	_check(sel.rect_state == 1, "outil Rectangle : premier coin posé")
	await _frames(3)
	await _click(MOUSE_BUTTON_LEFT, true)
	await _click(MOUSE_BUTTON_LEFT, false)
	_check(sel.has_rect() and is_equal_approx(sel.rect_m().size.x, 3.5) and is_equal_approx(sel.rect_m().size.y, 3.5), "rectangle 3,50 × 3,50 m défini par deux clics (%s)" % sel.info_text())
	# on recentre pour une belle vue : le rectangle est posé au centre de la salle
	sel.lock_size = false
	sel.set_rect_centered(Vector2(0.0, 0.0), Vector2(3.5, 3.5))
	scene.place_player(0.0, 6.2, 0.0, -0.42)
	await _phys(20)
	# commande réelle dans la barre T
	await _key(KEY_T)
	_check(scene.ui.bar_open and scene.ui.bar.visible, "T ouvre la barre de commandes")
	_check(not scene.explorer.control_enabled, "pendant la saisie, les touches ne déplacent plus le joueur")
	scene.ui.bar.text = "/generer maison --graine 42"
	scene.ui.bar.text_submitted.emit(scene.ui.bar.text)
	await _frames(25)
	_check(not ctl.pending.is_empty() and bool(ctl.pending.get("ok", false)), "/generer maison --graine 42 : aperçu prêt")
	await _frames(10)
	await _shot("04_salle_rectangle_apercu_maison")
	var recipe_text := ctl.recipe_text()
	await _key(KEY_ENTER)
	await _frames(60)
	_check(lab.stack.size() == 1, "Entrée : maison confirmée (%s)" % ctl.history.back().substr(0, 70))
	await _shot("04b_salle_maison_posee")
	var copied := ctl.copy_recipe()
	_check(copied == recipe_text and copied.begins_with("/generer maison --graine 42"), "Copier la recette : %s" % copied)
	report["recette_salle"] = copied
	var before_undo_zone := lab.field.zone.duplicate()
	await _key(KEY_Z, true)
	await _frames(60)
	_check(lab.stack.is_empty() and lab.occ.items.size() == 0, "Ctrl+Z : la maison disparaît entièrement")
	# refus : emprise trop petite, raison affichée, terrain intact
	var snap := lab.snapshot()
	sel.set_rect_centered(Vector2(4.0, -4.0), Vector2(2.0, 2.0))
	var bad: Dictionary = ctl.request("maison", {"seed": 42})
	_check(not bool(bad["ok"]) and lab.field.top == snap["top"] and lab.field.zone == snap["zone"], "emprise 2 × 2 m refusée sans toucher le terrain : %s" % String(bad["reason"]).substr(0, 60))
	await _frames(6)
	await _shot("04c_salle_refus")
	ctl.cancel_preview()
	# pause (Échap réel) puis retour au menu
	await _key(KEY_ESCAPE)
	await _frames(4)
	_check(App.paused_menu and get_tree().paused, "Échap : pause dans le laboratoire")
	(App.find_child("RetourMenu", true, false) as Button).pressed.emit()
	await _frames(30)
	_check(get_tree().current_scene.name == "MainMenu" and not is_instance_valid(scene), "retour au menu : laboratoire déchargé")
	# ------------------------------------------------------------ île vide
	await _open_from_menu("Laboratoire développeur — île vide")
	await _wait_lab("island")
	ctl = scene.ctl
	sel = scene.sel
	lab = scene.lab
	await _phys(30)
	await _shot("00_ile_depart")
	_check(lab.build_ms > 0, "île vide préparée en %d ms" % lab.build_ms)
	# même recette, rectangle posé sur la pente
	sel.set_tool(LabSelection.Tool.RECT)
	sel.set_rect_centered(Vector2(3.0, 0.0), Vector2(3.5, 3.5))
	scene.place_player(3.0, 8.0, 0.0, -0.18)
	await _phys(20)
	await _key(KEY_T)
	scene.ui.bar.text = copied
	scene.ui.bar.text_submitted.emit(copied)
	await _frames(30)
	var pend: Dictionary = ctl.pending
	_check(not pend.is_empty() and bool(pend.get("ok", false)), "recette rejouée sur la pente : aperçu prêt (%s)" % ctl.history.back().substr(0, 60))
	await _frames(10)
	await _shot("05a_ile_apercu_pente")
	var plan_island: BuildingPlan = pend["plan"]
	var cells_slope := int(pend.get("terrain_cells", 0))
	await _key(KEY_ENTER)
	await _frames(80)
	_check(lab.stack.size() == 1, "maison confirmée sur la pente (%d colonnes raccordées)" % cells_slope)
	report["raccord_pente_colonnes"] = cells_slope
	# profil bas, depuis le sud-ouest : la maison, son soubassement et le talus qui épouse la pente
	scene.place_player(-1.3, 6.4, -0.66, -0.12)
	await _phys(20)
	await _frames(8)
	await _shot("05_ile_maison_sur_la_pente")
	await _key(KEY_Z, true)
	await _frames(80)
	_check(lab.stack.is_empty(), "Ctrl+Z sur la pente : relief et raccord restaurés")
	# pinceau : peindre, aperçu, appliquer
	sel.clear_all()
	sel.set_tool(LabSelection.Tool.BRUSH)
	sel.brush_radius = 1.3
	scene.place_player(8.2, 4.9, 0.0, -0.5)
	await _phys(20)
	await _frames(4)
	# vrai clic maintenu : la caméra est déplacée en balayant la zone
	await _click(MOUSE_BUTTON_LEFT, true)
	for k in 16:
		scene.place_player(8.2 + 0.2 * float(k), 4.9, 0.0, -0.5)
		await _frames(2)
		await _phys(1)
	await _click(MOUSE_BUTTON_LEFT, false)
	_check(sel.brush_cells.size() > 80, "outil Pinceau : clic maintenu = %d colonnes peintes" % sel.brush_cells.size())
	var painted := sel.brush_cells.duplicate()
	var top_before := lab.field.top.duplicate()
	var rr: Dictionary = ctl.request("aplanir", {})
	_check(bool(rr["ok"]), "aplanir : aperçu (%s)" % LabWorld.describe(rr["op"]).substr(0, 80))
	scene.place_player(9.7, 5.7, 0.0, -0.42)
	await _phys(10)
	await _frames(10)
	await _shot("06_pinceau_zone_peinte")
	_check(lab.field.top == top_before, "l'aperçu du pinceau ne modifie pas le terrain")
	await _key(KEY_ENTER)
	await _frames(80)
	var outside := 0
	for i in lab.field.top.size():
		if lab.field.top[i] != top_before[i] and not painted.has(i):
			outside += 1
	_check(lab.stack.size() == 1 and outside == 0, "aplanissement appliqué, 0 colonne modifiée hors de la zone (%d)" % outside)
	scene.place_player(9.7, 5.7, 0.0, -0.42)
	await _phys(10)
	await _frames(10)
	await _shot("07_pinceau_resultat")
	await _key(KEY_Z, true)
	await _frames(80)
	_check(lab.field.top == top_before, "Ctrl+Z : le terrain est restauré à l'identique")
	# arbre et rocher sur l'île (point)
	var save_json := FileAccess.open(OUT + "/lot6_lab_rapport.json", FileAccess.WRITE)
	report["duree_s"] = (Time.get_ticks_msec() - t0) / 1000
	var bad_n := 0
	for c in report["controles"]:
		if not c["ok"]:
			bad_n += 1
	report["echecs"] = bad_n
	save_json.store_string(JSON.stringify(report, "\t"))
	save_json.close()
	print("== %d contrôle(s), %d échec(s) en %d s ==" % [report["controles"].size(), bad_n, report["duree_s"]])
	get_tree().quit()
