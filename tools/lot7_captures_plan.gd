extends Node
## Captures de l'étape 1 (Lot 7), dans le VRAI jeu lancé au menu : « Générer une île » (graine, largeur, longueur) → aperçu du
## plan 2D → « Construire et explorer l'île » → première personne sur un chemin → vue aérienne 3D de la même île.
##   godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/lot7_captures_plan.gd [-- graine L H]
const OUT := "/tmp/l7"
var report := {"controles": []}

func _check(cond: bool, label: String) -> void:
	report["controles"].append({"ok": cond, "controle": label})
	var line := ("  OK    " if cond else "  ÉCHEC ") + label
	print(line)
	var f := FileAccess.open(OUT + "/plan_checks.txt", FileAccess.READ_WRITE if FileAccess.file_exists(OUT + "/plan_checks.txt") else FileAccess.WRITE)
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

func _spin(menu: Node, prop: String, v: float) -> void:
	(menu.get(prop) as SpinBox).value = v

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds: Array = []
	var w := 56.0
	var l := 48.0
	for a in args:
		if a.begins_with("--graines="):
			for s in a.substr(10).split(","):
				seeds.append(int(s))
		elif a.begins_with("--taille="):
			var p := a.substr(9).split("x")
			w = float(p[0])
			l = float(p[1])
	if seeds.is_empty():
		seeds = [42]
	await _frames(30)
	var menu := get_tree().current_scene
	menu.call("show_page", "generate")
	await _frames(30)
	for sd in seeds:
		_spin(menu, "_seed", sd)
		_spin(menu, "_width", w)
		_spin(menu, "_length", l)
		var prev := (menu.get("_pages") as Dictionary)["generate"].find_child("Premier", true, false) as Button
		prev.pressed.emit()
		await _frames(12)
		await _shot("g_plan_%d" % sd)
	var sd0: int = seeds[seeds.size() - 1]
	var plan_a: IslandPlan = menu.get("_plan")
	# même graine, mêmes dimensions : même plan ; autre graine : autre plan
	var again := PlanGenerator.generate(sd0, w, l)
	_check(again.to_json() == plan_a.to_json(), "même graine et mêmes dimensions : même plan")
	_check(PlanGenerator.generate(sd0 + 1, w, l).to_json() != plan_a.to_json(), "graine suivante : plan différent")
	var go := menu.find_child("Construire", true, false) as Button
	go.pressed.emit()
	var t := Time.get_ticks_msec()
	var isl: MapIsland = null
	while Time.get_ticks_msec() - t < 600000:
		var s := get_tree().current_scene
		if s != null and s.name == "MapIsland" and bool(s.get("ready_to_play")):
			isl = s as MapIsland
			break
		await get_tree().process_frame
		OS.delay_msec(5)
	_check(isl != null, "l'île s'ouvre en 3D depuis le plan (%d ms)" % (isl.load_ms if isl else -1))
	_check(isl.plan.to_json() == plan_a.to_json(), "l'île 3D est construite depuis le même plan que l'aperçu")
	_check(PlanTerrain.fingerprint(isl.build.field) == PlanTerrain.fingerprint(PlanTerrain.build(again).field), "terrain 3D = terrain de base du plan (empreinte identique)")
	_check(isl.camrig.first_person, "première personne par défaut")
	await _frames(6)
	await _shot("g_depart")
	var pa: Dictionary = isl.plan.paths[0]
	var a: Vector2 = pa["pts"][1]
	var b: Vector2 = pa["pts"][2]
	isl.place_player(a.x, a.y, atan2(-(b.x - a.x), -(b.y - a.y)), -0.06)
	await _frames(6)
	await _shot("g_chemin")
	isl.set_aerial(true)
	await _frames(8)
	await _shot("g_aerienne")
	var f := FileAccess.open(OUT + "/recette_plan.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	get_tree().quit()
