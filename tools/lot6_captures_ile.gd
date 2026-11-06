extends Node
## Captures de l'étape 1 (Lot 6), prises dans le VRAI jeu lancé au menu (godot … -- --recette=res://tools/lot6_captures_ile.gd) :
## menu → « Jouer l'île d'ouverture » → première personne (maison, escalier, Ancre) → pause → retour au menu.
## Les positions sont posées par téléportation (le rendu logiciel est trop lent pour marcher) ; les déplacements
## réels sont éprouvés par tools/opening_recette.gd et tools/lot6_recette.gd (sans rendu, 60 images/s fixes).
const OUT := "/tmp/claude-0/-home-user/a63a7b17-b085-5a47-af76-319612b62b36/scratchpad/l6"

var scene: Node
var ex: Explorer
var cam: ThirdPersonCamera
var report := {}

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("saved ", name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(30)
	var menu := get_tree().current_scene
	report["demarre_au_menu"] = menu.name == "MainMenu" and App.current_path == App.MENU_SCENE
	await _shot("01_menu")
	GameSave.clear_island(String(IslandMap.load_map().get("id", "")))
	menu.call("play_opening")
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 1200000:
		var s := get_tree().current_scene
		if s != null and s.name == "OpeningIsland" and bool(s.get("ready_to_play")):
			break
		await get_tree().process_frame
		OS.delay_msec(5)
	scene = get_tree().current_scene
	GameSave.clear_island(String(IslandMap.load_map().get("id", "")))
	ex = scene.get("explorer")
	cam = scene.get("camrig")
	print("[captures] île prête après %d s (cache : %s)" % [(Time.get_ticks_msec() - t) / 1000, scene.get("from_cache")])
	report["premiere_personne"] = cam.first_person
	report["modele_masque"] = not ex.model.visible
	await _frames(5)
	await _shot("00_depart_quai")
	# --- maison : intérieur, escalier
	var house := {}
	for it in scene.get("interiors"):
		if bool(it.get("visitable", false)):
			house = it
	var door := Vector2(float(house["door"][0]), float(house["door"][1]))
	var front := Vector2(float(house["front"][0]), float(house["front"][1]))
	var foot := Vector2(float(house["stair_foot"][0]), float(house["stair_foot"][2]))
	var floor0 := float(house["floor0_y"])
	var yaw := atan2(front.x, front.y)             # regard vers l'intérieur (opposé à la façade)
	# seuil : la façade et la porte vues depuis la place (première personne)
	_place_y(door + front * 2.4, floor0 + 0.1, yaw, 0.02)
	await _settle()
	await _shot("02a_seuil")
	# entrée : on franchit la porte (téléportation au seuil intérieur ; le passage réel est éprouvé par la recette jouée)
	_place_y(door - front * 0.5, floor0 + 0.1, yaw, 0.0)
	await _settle()
	await _shot("02c_porte")
	# pied de l'escalier : regard vers le haut de la volée
	_place_y(foot + Vector2(0.0, 0.1), floor0 + 0.1, 0.0, 0.3)
	await _settle()
	print("[captures] floor0 ", floor0, " ex ", ex.global_position, " pied ", house["stair_foot"], " haut ", house["stair_top"])
	report["interieur_au_pied_de_l_escalier"] = bool(scene.call("_is_interior", ex.global_position))
	await _shot("02_interieur_escalier")
	var top := Vector2(float(house["stair_top"][0]), float(house["stair_top"][2]))
	_place_y(top + Vector2(0.0, 0.4), float(house["floor1_y"]) + 0.1, PI, -0.35)
	await _settle()
	report["palier_a_l_etage"] = ex.global_position.y > float(house["floor1_y"]) - 0.2
	await _shot("02b_palier")
	# --- Ancre
	var a: Dictionary = scene.get("info")["anchor"]
	var ap: Vector3 = a["pos"]
	var cr: Vector3 = a["crystal"]
	var dir := (Vector2(ap.x, ap.z) - Vector2(door.x, door.y)).normalized()
	var spot := Vector2(ap.x, ap.z) + Vector2(-dir.x, -dir.y) * 2.0
	var g := float(scene.call("ground_y_at", spot.x, spot.y, ap.y + 2.5))
	print("[captures] ancre ", ap, " cristal ", cr, " spot ", spot, " sol ", g)
	ex.teleport(Vector3(spot.x, g + 0.05, spot.y), 0.0)
	var look := Vector3(cr.x - spot.x, cr.y - (g + 1.6), cr.z - spot.y)
	cam.yaw = atan2(-look.x, -look.z)
	cam.pitch = atan2(look.y, Vector2(look.x, look.z).length()) * 0.8
	cam.snap()
	await _settle(40)
	print("[captures] explorateur ", ex.global_position)
	report["ancre_a_portee"] = scene.call("anchor_in_range")
	report["invite"] = (scene.get("_prompt") as Label).text if (scene.get("_prompt") as Label).visible else ""
	await _shot("08_invite_ancre")
	# --- pause
	App.toggle_pause()
	await _frames(6)
	report["pause_active"] = get_tree().paused and App.paused_menu
	await _shot("03_pause")
	App.toggle_pause()
	await _frames(4)
	report["reprise_ok"] = not get_tree().paused and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	App.toggle_pause()
	await _frames(4)
	var btn := App.find_child("RetourMenu", true, false) as Button
	btn.pressed.emit()
	await _frames(20)
	report["retour_menu"] = get_tree().current_scene != null and get_tree().current_scene.name == "MainMenu"
	report["ile_dechargee"] = not is_instance_valid(scene) or not scene.is_inside_tree()
	report["pause_fermee"] = not get_tree().paused
	print(JSON.stringify(report, "\t"))
	print("[captures] total ", (Time.get_ticks_msec() - t0) / 1000, " s")
	get_tree().quit()

func _free(space: PhysicsDirectSpaceState3D, c: Vector2, floor0: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.5
	q.shape = cap
	q.collision_mask = 1
	q.transform = Transform3D(Basis.IDENTITY, Vector3(c.x, floor0 + 0.12 + 0.75 + 0.02, c.y))
	return space.intersect_shape(q, 1).is_empty()

func _place(p: Vector2, yaw: float, pitch: float) -> void:
	var g := float(scene.call("ground_y_at", p.x, p.y, ex.global_position.y + 3.0))
	_place_y(p, (0.0 if is_nan(g) else g) + 0.05, yaw, pitch)

func _place_y(p: Vector2, y: float, yaw: float, pitch: float) -> void:
	ex.teleport(Vector3(p.x, y, p.y), yaw)
	cam.yaw = yaw
	cam.pitch = pitch
	cam.snap()

func _settle(n := 25) -> void:
	for i in n:
		await get_tree().physics_frame
	cam.snap()
	await _frames(6)
