extends SceneTree
## Recette JOUÉE de l'île d'ouverture (Lot 5) : un pilote automatique tient le rôle du joueur (mêmes déplacements,
## mêmes collisions, vitesse de marche réelle) et enchaîne :
##   1. le trajet complet quai → sanctuaire (chronométré, hors visite), par l'itinéraire principal ;
##   2. la visite de la maison (entrée, rez-de-chaussée, escalier, étage) ;
##   3. le détour du verger (jusqu'au chemin principal) ;
##   4. l'activation de l'Ancre (invite « E · Activer l'Ancre », pulsation, « Île découverte », sauvegarde) ;
##   5. une chute dans le vide (retour au quai).
## Avec --relance : vérifie seulement, dans un NOUVEAU processus, que l'état sauvegardé est retrouvé.
##   godot --headless --fixed-fps 60 -s tools/opening_recette.gd -- rapport.json [--relance]
## Le rapport (JSON) liste mesures, défauts, et les positions des captures (tools/opening_shot.gd).

const DT := 1.0 / 60.0

var scene: Node
var ex: Explorer
var report := {"etapes": [], "defauts": [], "captures": []}
var map: Dictionary
var S := 1.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://recette_ile.json"
	var relance := args.has("--relance")
	map = IslandMap.load_map()
	if not relance:
		GameSave.clear_island(String(map["id"]))
	scene = (load("res://scenes/game/opening_island.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var waited := 0
	var t_wait := Time.get_ticks_msec()
	while not bool(scene.get("ready_to_play")) and Time.get_ticks_msec() - t_wait < 900000:
		await process_frame
		OS.delay_msec(5)
		waited += 1
	ex = scene.get("explorer")
	print("[recette] prête après %d images ; explorateur : %s" % [waited, ex])
	report["chargement_ms"] = scene.get("load_ms")
	report["depuis_cache"] = scene.get("from_cache")
	if relance:
		await _check_relaunch()
	else:
		await _play()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print(JSON.stringify(report, "\t"))
	quit()

# ------------------------------------------------------------------ outils

func _path_pts(id: String) -> Array:
	for p in map["paths"]:
		if p["id"] == id:
			var out: Array = []
			for q in p["pts"]:
				out.append(Vector2(float(q[0]), float(q[1])))
			return out
	return []

func _pos2() -> Vector2:
	return Vector2(ex.global_position.x, ex.global_position.z)

func _ground(p: Vector2) -> float:
	return float(scene.call("ground_y_at", p.x, p.y))

func _teleport(p: Vector2, yaw := 0.0, from_y := 300.0) -> void:
	var g := float(scene.call("ground_y_at", p.x, p.y, from_y))
	ex.teleport(Vector3(p.x, (0.0 if is_nan(g) else g) + 0.1, p.y), yaw)

func _capture(name: String, yaw_toward: Vector2 = Vector2.INF, pitch := -0.22) -> void:
	var p := ex.global_position
	var yaw := (ex.model.rotation.y) if yaw_toward == Vector2.INF else atan2(-(yaw_toward.x - p.x), -(yaw_toward.y - p.z))
	report["captures"].append({"nom": name, "pos": [p.x, p.y, p.z], "yaw": yaw, "pitch": pitch})

## Marche vers un point (x, z) : renvoie le temps mis (s) ; signale les blocages (et les franchit pour continuer).
func _walk_to(target: Vector2, tol := 0.8, label := "") -> float:
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
		if int(scene.get("falls")) != falls0:
			report["defauts"].append({"type": "chute", "etape": label, "vers": [target.x, target.y]})
			ex.auto_dir = Vector2.ZERO
			return -1.0
		if check_t >= 1.0:
			# progrès vers la cible (et non simple mouvement) : un piétinement compte comme un blocage
			if check_pos.distance_to(target) - _pos2().distance_to(target) < 0.35:
				stuck += check_t
				ex.auto_jump = true
				# contournement : petit pas de côté
				var side := Vector2(-d.y, d.x).normalized() * (1.0 if int(stuck) % 2 == 0 else -1.0)
				for i in 30:
					ex.auto_dir = side
					await physics_frame
					t += DT
			else:
				stuck = 0.0
			check_t = 0.0
			check_pos = _pos2()
		if stuck > 6.0 or t > 180.0:
			report["defauts"].append({"type": "blocage", "etape": label, "pos": [ex.global_position.x, ex.global_position.y, ex.global_position.z], "vers": [target.x, target.y]})
			_teleport(target, ex.model.rotation.y, ex.global_position.y + 2.5)
			break
	ex.auto_dir = Vector2.ZERO
	return t

## caps : index de point → nom de capture (prise en arrivant au point, vers le point suivant)
func _walk_path(pts: Array, label: String, caps := {}) -> float:
	var total := 0.0
	for i in pts.size():
		var q: Vector2 = pts[i]
		var t := await _walk_to(q, 0.9, label)
		if t < 0.0:
			return -1.0
		total += t
		if caps.has(i):
			_capture(caps[i], pts[mini(i + 1, pts.size() - 1)] if i + 1 < pts.size() else q + (q - pts[i - 1]), -0.18)
	return total

# ------------------------------------------------------------------ partie jouée

func _play() -> void:
	var t_route := 0.0
	var dist := 0.0
	var plaza: Dictionary = map["plaza"]
	var pc := Vector2(float(plaza["center"][0]), float(plaza["center"][1]))
	var pr := float(plaza["radius"])
	# --- 1. quai → col → hameau
	_capture("01_quai_depart", _path_pts("sentier_des_falaises")[2])
	var legs := [["sentier_des_falaises", "Sentier des falaises"], ["descente_du_col", "Descente du col"]]
	var caps := {"sentier_des_falaises": {7: "02_sentier_des_falaises", 17: "03_col_pierre_levee"}, "descente_du_col": {3: "03b_vue_sur_le_hameau"}}
	for lg in legs:
		var pts := _path_pts(lg[0])
		var t := await _walk_path(pts, lg[1], caps.get(lg[0], {}))
		report["etapes"].append({"etape": lg[1], "temps_s": snappedf(t, 0.1)})
		t_route += maxf(t, 0.0)
		if lg[0] == "sentier_des_falaises":
			pass
	# traversée de la place en contournant la fontaine
	var p3 := _path_pts("rue_du_hameau")
	var t_pl := await _walk_path([pc + Vector2(-pr * 0.6, pr * 0.55), pc + Vector2(pr * 0.6, pr * 0.55), p3[0]], "Place")
	t_route += maxf(t_pl, 0.0)
	report["etapes"].append({"etape": "Place du hameau", "temps_s": snappedf(t_pl, 0.1)})
	var resume_pos := _pos2()
	# --- 2. visite de la maison (hors chronomètre)
	await _visit_house(pc, pr)
	_teleport(resume_pos)
	# --- 3. hauteurs, Pointe du Guet, crête, sanctuaire
	for lg in [["rue_du_hameau", "Rue du hameau"], ["lacets_des_hauteurs", "Lacets des hauteurs"], ["pointe_du_guet", "Pointe du Guet"]]:
		var t := await _walk_path(_path_pts(lg[0]), lg[1])
		report["etapes"].append({"etape": lg[1], "temps_s": snappedf(t, 0.1)})
		t_route += maxf(t, 0.0)
	var guet := _path_pts("pointe_du_guet")
	_capture("08_pointe_du_guet", guet[1] + (guet[1] - guet[0]) * 3.0, -0.12)
	var crete := _path_pts("chemin_de_crete")
	var t_back := await _walk_to(crete[0], 0.9, "Retour de la pointe")
	t_route += maxf(t_back, 0.0)
	var t_cr := await _walk_path(crete, "Chemin de crête", {6: "09_chemin_de_crete"})
	t_route += maxf(t_cr, 0.0)
	report["etapes"].append({"etape": "Chemin de crête", "temps_s": snappedf(t_cr, 0.1)})
	_capture("10_pied_de_la_montee", _path_pts("montee_du_sanctuaire")[1], -0.1)
	var t_m := await _walk_path(_path_pts("montee_du_sanctuaire"), "Montée du sanctuaire")
	t_route += maxf(t_m, 0.0)
	report["etapes"].append({"etape": "Montée du sanctuaire", "temps_s": snappedf(t_m, 0.1)})
	# jusqu'au cristal
	var a: Dictionary = scene.get("info")["anchor"]
	var ap: Vector3 = a["pos"]
	var arrive := Vector2(ap.x, ap.z) + (_pos2() - Vector2(ap.x, ap.z)).normalized() * 2.0
	var t_a := await _walk_to(arrive, 0.5, "Vers l'Ancre")
	t_route += maxf(t_a, 0.0)
	report["trajet_principal_s"] = snappedf(t_route, 0.1)
	report["trajet_principal_min"] = snappedf(t_route / 60.0, 0.01)
	report["vitesse_marche_mps"] = ex.walk_speed
	# --- 4. Ancre
	await _anchor_test()
	# --- 5. détour du verger (essai séparé)
	var d1 := _path_pts("detour_du_verger")
	_teleport(d1[0])
	var t_d := await _walk_path(d1, "Détour du verger")
	var main4 := _path_pts("lacets_des_hauteurs")
	var joined := _pos2().distance_to(d1.back()) < 1.5
	report["detour"] = {"temps_s": snappedf(t_d, 0.1), "rejoint_le_chemin_principal": joined}
	_teleport(d1[2])
	_capture("07_detour_du_verger", d1[3], -0.15)
	# --- 6. chute dans le vide : du sentier des falaises vers l'ouest
	var p1 := _path_pts("sentier_des_falaises")
	var edge_start: Vector2 = p1[11]
	_teleport(edge_start)
	var falls0: int = scene.get("falls")
	ex.auto_active = true
	ex.auto_dir = Vector2(-1, 0)
	var t_f := 0.0
	while int(scene.get("falls")) == falls0 and t_f < 30.0:
		await physics_frame
		t_f += DT
	ex.auto_dir = Vector2.ZERO
	await physics_frame
	var sp: Vector3 = scene.get("spawn_pos")
	report["chute"] = {"retour_au_quai": int(scene.get("falls")) > falls0 and ex.global_position.distance_to(sp) < 2.0, "temps_s": snappedf(t_f, 0.1)}

func _anchor_test() -> void:
	var res := {}
	await physics_frame
	res["a_portee"] = bool(scene.call("anchor_in_range"))
	res["objectif_avant"] = String(scene.call("objective_text"))
	for i in 3:
		await process_frame
	var prompt: Label = scene.get("_prompt")
	res["invite_visible"] = prompt.visible
	res["invite"] = prompt.text
	res["touche_attendue"] = GameInput.key_label("interact")
	var a: Dictionary = scene.get("info")["anchor"]
	_capture("11_invite_ancre", Vector2((a["pos"] as Vector3).x, (a["pos"] as Vector3).z), -0.15)
	Input.action_press("interact")
	await process_frame
	await process_frame
	Input.action_release("interact")
	await process_frame
	res["active"] = bool(scene.get("anchor_active"))
	res["objectif_apres"] = String(scene.call("objective_text"))
	var banner: Label = scene.get("_banner")
	res["banniere"] = banner.text
	res["invite_apres"] = (scene.get("_prompt") as Label).visible
	var saved := GameSave.island(String(map["id"]))
	res["sauvegarde"] = saved
	res["fichier"] = ProjectSettings.globalize_path(GameSave.PATH)
	report["ancre"] = res

## Visite : allée de la porte, rez-de-chaussée (chemin calculé sur les collisions), escalier, étage, retour.
func _visit_house(pc: Vector2, pr: float) -> void:
	var house := {}
	for it in scene.get("interiors"):
		if bool(it.get("visitable", false)):
			house = it
	if house.is_empty():
		report["defauts"].append({"type": "maison", "detail": "aucune maison visitable"})
		return
	var res := {"id": house["id"]}
	var door := Vector2(float(house["door"][0]), float(house["door"][1]))
	var front := Vector2(float(house["front"][0]), float(house["front"][1]))
	var t := 0.0
	t += await _walk_to(pc + (door - pc).normalized() * (pr - 0.6), 0.9, "Vers la maison")
	t += await _walk_to(door + front * 2.0, 0.6, "Allée de la maison")
	_capture("04_maison_visitable", door - front * 2.0, -0.12)
	t += await _walk_to(door + front * 0.3, 0.4, "Seuil")
	var inside := door - front * 1.2
	t += await _walk_to(inside, 0.4, "Entrée")
	var floor0 := float(house["floor0_y"])
	res["entre"] = absf(ex.global_position.y - floor0) < 0.25 and bool(scene.call("_is_interior", ex.global_position))
	res["camera_interieur"] = bool((scene.get("camrig") as ThirdPersonCamera).interior)
	_capture("05_interieur_rdc", inside - front * 3.0, -0.2)
	if house.has("stair_foot"):
		var foot := Vector2(float(house["stair_foot"][0]), float(house["stair_foot"][2]))
		var top := Vector2(float(house["stair_top"][0]), float(house["stair_top"][2]))
		var route := _bfs_inside(house, inside, foot)
		res["chemin_rdc_points"] = route.size()
		for q: Vector2 in route:
			t += await _walk_to(q, 0.35, "Rez-de-chaussée")
		t += await _walk_to(foot, 0.35, "Pied de l'escalier")
		t += await _walk_to(top, 0.4, "Escalier")
		var f1 := float(house["floor1_y"])
		res["etage_atteint"] = ex.global_position.y > f1 - 0.15
		res["hauteur_etage"] = snappedf(ex.global_position.y - floor0, 0.01)
		res["marches_franchies"] = ex.stepped
		_capture("06_etage", top + (top - foot).normalized() * 2.0, -0.25)
		# redescente et sortie
		t += await _walk_to(foot, 0.4, "Descente")
		route.reverse()
		for q: Vector2 in route:
			t += await _walk_to(q, 0.35, "Rez-de-chaussée (retour)")
		t += await _walk_to(inside, 0.4, "Vers la porte")
		t += await _walk_to(door + front * 2.0, 0.6, "Sortie")
		res["ressorti"] = not bool(scene.call("_is_interior", ex.global_position))
	res["temps_visite_s"] = snappedf(t, 0.1)
	report["maison"] = res

## Chemin intérieur (grille de 20 cm, cases libres d'après les collisions réelles) de a vers b.
func _bfs_inside(house: Dictionary, a: Vector2, b: Vector2) -> Array:
	var box: AABB = house["aabb"]
	var floor0 := float(house["floor0_y"])
	var cell := 0.2
	var nx := int(box.size.x / cell) + 1
	var nz := int(box.size.z / cell) + 1
	var space := (scene as Node3D).get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.5
	q.shape = cap
	q.collision_mask = 1
	var free := PackedByteArray()
	free.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var x := box.position.x + (float(ix) + 0.5) * cell
			var z := box.position.z + (float(iz) + 0.5) * cell
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, floor0 + 0.12 + 0.75 + 0.02, z))
			free[ix + iz * nx] = 1 if space.intersect_shape(q, 1).is_empty() else 0
	var to_cell := func(p: Vector2) -> Vector2i:
		return Vector2i(clampi(int((p.x - box.position.x) / cell), 0, nx - 1), clampi(int((p.y - box.position.z) / cell), 0, nz - 1))
	var s: Vector2i = to_cell.call(a)
	var g: Vector2i = to_cell.call(b)
	free[s.x + s.y * nx] = 1
	free[g.x + g.y * nx] = 1
	var prev := {}
	var queue := [s]
	prev[s] = s
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c == g:
			break
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + o
			if nc.x < 0 or nc.y < 0 or nc.x >= nx or nc.y >= nz or prev.has(nc) or free[nc.x + nc.y * nx] == 0:
				continue
			prev[nc] = c
			queue.append(nc)
	if not prev.has(g):
		report["defauts"].append({"type": "maison", "detail": "pas de chemin libre de l'entrée à l'escalier"})
		return []
	var cells: Array = []
	var c := g
	while c != s:
		cells.append(c)
		c = prev[c]
	cells.reverse()
	var out: Array = []
	for i in range(0, cells.size(), 3):
		var cc: Vector2i = cells[i]
		out.append(Vector2(box.position.x + (float(cc.x) + 0.5) * cell, box.position.z + (float(cc.y) + 0.5) * cell))
	return out

# ------------------------------------------------------------------ relance

func _check_relaunch() -> void:
	await physics_frame
	var res := {}
	res["ancre_active_au_chargement"] = bool(scene.get("anchor_active"))
	res["objectif"] = String(scene.call("objective_text"))
	res["sauvegarde"] = GameSave.island(String(map["id"]))
	var a: Dictionary = scene.get("info")["anchor"]
	var ap: Vector3 = a["pos"]
	_teleport(Vector2(ap.x + 2.0, ap.z))
	for i in 10:
		await physics_frame
	await process_frame
	res["invite_visible_pres_de_l_ancre"] = (scene.get("_prompt") as Label).visible
	report["relance"] = res
