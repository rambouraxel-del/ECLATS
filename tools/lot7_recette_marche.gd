extends SceneTree
## Recette JOUÉE du Lot 7 (parcours 2) : un pilote automatique marche, en première personne et avec les vraies collisions,
## les liaisons du plan : arrivée → plateau → zone boisée → point haut, en suivant les chemins tracés. Mesure le temps,
## les blocages, les chutes, les repères atteints et le confort de la caméra (écart vertical par image).
##   godot --headless --fixed-fps 60 -s tools/lot7_recette_marche.gd -- rapport.json [graine] [largeur] [longueur]
const DT := 1.0 / 60.0
var scene: Node
var ex: Explorer
var cam: ThirdPersonCamera
var plan: IslandPlan
var report := {"etapes": [], "defauts": []}
var _cam_y := NAN
var _dy := 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://recette_marche.json"
	var sd := int(args[1]) if args.size() > 1 else 3
	var w := float(args[2]) if args.size() > 2 else 56.0
	var l := float(args[3]) if args.size() > 3 else 48.0
	plan = PlanGenerator.generate(sd, w, l)
	root.get_node("App").set("launch", {"plan": plan, "trees": true})
	scene = (load("res://scenes/map/map_island.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var t_wait := Time.get_ticks_msec()
	while not bool(scene.get("ready_to_play")) and Time.get_ticks_msec() - t_wait < 600000:
		await process_frame
		OS.delay_msec(5)
	ex = scene.get("explorer")
	cam = scene.get("camrig")
	report["plan"] = {"graine": sd, "largeur": w, "longueur": l}
	report["chargement_ms"] = scene.get("load_ms")
	report["arbres"] = scene.get("trees_planted")
	report["premiere_personne"] = cam.first_person
	var start := Vector2(ex.global_position.x, ex.global_position.z)
	report["depart_m"] = [snappedf(start.x, 0.01), snappedf(start.y, 0.01)]
	report["depart_sur_le_plan"] = start.distance_to(plan.start) < 0.6
	for p in plan.paths:
		var t0 := Time.get_ticks_msec()
		var total := 0.0
		var pts: Array = p["pts"]
		var ok := true
		for k in range(1, pts.size()):
			var t := await _walk_to(pts[k], 0.8, String(p["id"]))
			if t < 0.0:
				ok = false
				break
			total += t
		var z: Dictionary = plan.zone_by_id(p["to"])
		var arrived := Vector2(ex.global_position.x, ex.global_position.z).distance_to(z["c"]) < 1.6
		report["etapes"].append({"chemin": p["id"], "vers": p["to"], "duree_s": snappedf(total, 0.1), "arrive_dans_la_zone": arrived, "altitude_m": snappedf(ex.global_position.y, 0.01),
			"longueur_m": snappedf(IslandPlan.path_length(pts), 0.1)})
		if not ok or not arrived:
			report["defauts"].append({"type": "etape_non_terminee", "chemin": p["id"]})
	report["reperes_atteints"] = scene.get("reached")
	report["chutes"] = scene.get("falls")
	report["saut_camera_max_cm"] = snappedf(_dy * 100.0, 0.1)
	report["defauts_n"] = report["defauts"].size()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print(JSON.stringify(report, "\t"))
	quit()

func _pos2() -> Vector2:
	return Vector2(ex.global_position.x, ex.global_position.z)

func _sample() -> void:
	var y := cam.cam.global_position.y
	if not is_nan(_cam_y):
		_dy = maxf(_dy, absf(y - _cam_y))
	_cam_y = y

func _walk_to(target: Vector2, tol: float, label: String) -> float:
	ex.auto_active = true
	var t := 0.0
	var check_t := 0.0
	var check_pos := _pos2()
	var stuck := 0.0
	var falls0: int = scene.get("falls")
	while _pos2().distance_to(target) > tol:
		var d := target - _pos2()
		ex.auto_dir = d.normalized()
		await physics_frame
		t += DT
		check_t += DT
		_sample()
		if int(scene.get("falls")) != falls0:
			report["defauts"].append({"type": "chute", "etape": label})
			ex.auto_dir = Vector2.ZERO
			return -1.0
		if check_t >= 1.0:
			if check_pos.distance_to(target) - _pos2().distance_to(target) < 0.35:
				stuck += check_t
				ex.auto_jump = true
			else:
				stuck = 0.0
			check_t = 0.0
			check_pos = _pos2()
		if stuck > 5.0 or t > 120.0:
			report["defauts"].append({"type": "blocage", "etape": label, "pos": [ex.global_position.x, ex.global_position.y, ex.global_position.z]})
			ex.auto_dir = Vector2.ZERO
			return -1.0
	ex.auto_dir = Vector2.ZERO
	return t
