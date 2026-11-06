extends Node
## Comparatif de génération de terrain (A actuel · B FastNoiseLite · C Voxel Tools) — captures, vérifications, mesures.
##   CMP="caps A 21 56 48 dossier" xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -- --recette=res://tools/comparatif_terrain.gd
## (crochet de recette de l'App : le script tourne au-dessus du vrai jeu ; arguments dans la variable d'environnement CMP)
## MODE : caps (7 captures + 1 vue aérienne) · verif (reproductibilité, exploration, chemins, retouche enregistrée) · mesure
## La méthode C exige un moteur qui embarque Voxel Tools (voir docs/COMPARATIF_TERRAIN.md). Les cadrages ne dépendent QUE du plan :
## ils sont identiques pour les trois méthodes (même graine, mêmes dimensions → même plan, mêmes repères).
const DT := 1.0 / 60.0
const FOV_AERIAL := 46.0

var mode := ""
var method := "A"
var seed_v := 21
var width := 56.0
var length := 48.0
var out_dir := ""
var plan: IslandPlan
var scene: MapIsland
var report := {}

func _ready() -> void:
	var a := OS.get_environment("CMP").split(" ")
	mode = a[0]
	method = a[1]
	seed_v = int(a[2])
	width = float(a[3])
	length = float(a[4])
	out_dir = a[5]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	await get_tree().process_frame
	run()

func run() -> void:
	plan = PlanGenerator.generate(seed_v, width, length)
	match mode:
		"caps":
			await _caps()
		"verif":
			await _verif()
		"mesure":
			await _mesure()
	var f := FileAccess.open("%s/%s_%s_%d.json" % [out_dir, mode, method, seed_v], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	get_tree().quit()

# ------------------------------------------------------------------ plan commun : points de repère des cadrages

func _zone(id: String) -> Dictionary:
	return plan.zone_by_id(id)

## Point du relief « libre » : dans l'île, loin des chemins, des zones et du contour ; le plus proche du centre. Ne dépend que du plan.
func _relief_point() -> Vector2:
	var best := Vector2.ZERO
	var best_d := 1.0e9
	for gz in range(-30, 31):
		for gx in range(-30, 31):
			var q := Vector2(gx, gz) * 1.5
			if not IslandPlan.point_in_poly(q, plan.outline) or IslandPlan.dist_to_poly(q, plan.outline) < 7.0:
				continue
			var ok := true
			for z in plan.zones:
				if q.distance_to(z["c"]) < float(z["r"]) + 5.0:
					ok = false
			if not ok:
				continue
			var near := false
			for pa in plan.paths:
				var pts: Array = pa["pts"]
				for k in range(pts.size() - 1):
					var s := _seg(q, pts[k], pts[k + 1])
					if q.distance_to(s) < 6.0:
						near = true
			if near:
				continue
			var d := q.length()
			if d < best_d:
				best_d = d
				best = q
	return best

func _seg(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	return a + ab * clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)

func _path_point(pa: Dictionary, frac: float) -> Array:
	var pts: Array = pa["pts"]
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + (pts[k] as Vector2).distance_to(pts[k - 1]))
	var s := cum[-1] * frac
	var p := PlanTerrain.point_at(pts, cum, s)
	var p2 := PlanTerrain.point_at(pts, cum, minf(s + 1.5, cum[-1]))
	return [p, (p2 - p).normalized()]

func _cadrages() -> Array:
	var pa_pl := _path_between("arrivee", "plateau")
	var pa_so := _path_between("bois", "sommet")
	var q := _relief_point()
	var c := Vector2.ZERO
	var H := maxf(plan.width, plan.length) * 1.05
	var out: Array = []
	out.append({"nom": "01_vue_aerienne_generale", "mode": "aerial", "pos": Vector3(c.x, 4.0 + H, c.y + H * 0.36), "look": Vector3(c.x, 4.0, c.y - 1.0), "fov": FOV_AERIAL})
	out.append({"nom": "02_cretes_et_vallees_aerien", "mode": "aerial", "pos": Vector3(q.x, 4.0 + 28.0, q.y + 17.0), "look": Vector3(q.x, 4.0, q.y), "fov": 50.0})
	var st := plan.start
	var a1 := _path_point(pa_pl, 0.0) if not pa_pl.is_empty() else [st, Vector2(0, -1)]
	out.append({"nom": "03_arrivee_premiere_personne", "mode": "fp", "pos": st, "dir": (a1[1] as Vector2), "pitch": -0.06})
	var a2 := _path_point(pa_pl, 0.45) if not pa_pl.is_empty() else [st, Vector2(0, -1)]
	out.append({"nom": "04_chemin_vers_le_plateau", "mode": "fp", "pos": a2[0], "dir": (a2[1] as Vector2), "pitch": -0.05})
	# pente / falaise : au bord du contour, du côté du sommet, à 3,5 m du vide, regard vers le large
	var so := _zone("sommet")
	var dir_s := ((so["c"] as Vector2) - c).normalized() if not so.is_empty() else Vector2(0, -1)
	var edge := c
	while IslandPlan.point_in_poly(edge + dir_s * 0.25, plan.outline):
		edge += dir_s * 0.25
	var p5 := edge - dir_s * 3.5
	out.append({"nom": "05_pente_ou_falaise", "mode": "fp", "pos": p5, "dir": dir_s, "pitch": -0.22})
	var dq := Vector2(0, -1)
	out.append({"nom": "06a_zone_avant_pinceau", "mode": "aerial", "pos": Vector3(q.x, 4.0 + 13.0, q.y + 15.0), "look": Vector3(q.x, 4.5, q.y), "fov": 55.0})
	out.append({"nom": "06b_zone_apres_pinceau", "mode": "aerial", "pos": Vector3(q.x, 4.0 + 13.0, q.y + 15.0), "look": Vector3(q.x, 4.5, q.y), "fov": 55.0})
	return out

func _path_between(a: String, b: String) -> Dictionary:
	for pa in plan.paths:
		var z0 := plan.zone_at((pa["pts"] as Array)[0])
		var z1 := plan.zone_at((pa["pts"] as Array)[-1])
		if not z0.is_empty() and not z1.is_empty() and z0["id"] == a and z1["id"] == b:
			return pa
	return {}

# ------------------------------------------------------------------ lancement de la scène

func _launch(extra := {}) -> void:
	plan.settings["method"] = method
	var l := {"plan": plan, "trees": false}
	l.merge(extra, true)
	var old := get_tree().current_scene
	_aerial_cam = null
	get_node("/root/App").call("open", "res://scenes/map/map_island.tscn", l)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900000:
		await get_tree().process_frame
		OS.delay_msec(5)
		var cs := get_tree().current_scene
		if cs != null and cs != old and cs.name == "MapIsland" and bool(cs.get("ready_to_play")):
			break
	scene = get_tree().current_scene as MapIsland
	for i in 20:
		await get_tree().process_frame

func _free_scene() -> void:
	var old := get_tree().current_scene
	get_node("/root/App").call("open", "res://scenes/menu/main_menu.tscn")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs != null and cs != old:
			break
	scene = null
	_aerial_cam = null
	for i in 5:
		await get_tree().process_frame

func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s_graine%d.png" % [out_dir, name, method, seed_v]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _fp(c: Dictionary) -> void:
	var ex := scene.explorer
	var p: Vector2 = c["pos"]
	var d: Vector2 = c["dir"]
	var yaw := atan2(-d.x, -d.y)
	var g := scene._ground_y(p.x, p.y)
	scene.set_aerial(false)
	ex.visible = true
	ex.teleport(Vector3(p.x, (0.0 if is_nan(g) else g) + 0.05, p.y), yaw)
	scene.camrig.yaw = yaw
	scene.camrig.pitch = float(c["pitch"])
	for i in 30:
		await get_tree().physics_frame
	scene.camrig.snap()

var _aerial_cam: Camera3D

func _aerial(c: Dictionary) -> void:
	if _aerial_cam == null:
		_aerial_cam = Camera3D.new()
		_aerial_cam.near = 0.3
		_aerial_cam.far = 3000.0
		scene.add_child(_aerial_cam)
	_aerial_cam.fov = float(c["fov"])
	_aerial_cam.global_position = c["pos"]
	_aerial_cam.look_at(c["look"], Vector3.UP)
	_aerial_cam.current = true
	scene.explorer.visible = false
	_hud_visible(false)

func _hud_visible(v: bool) -> void:
	for n in scene.get_children():
		if n is CanvasLayer:
			(n as CanvasLayer).visible = v

# ------------------------------------------------------------------ captures

func _caps() -> void:
	await _launch()
	report["methode"] = method
	report["graine"] = seed_v
	report["relief_ms"] = scene.build.ms
	var cad := _cadrages()
	if seed_v != int(OS.get_environment("CMP_SEED1") if OS.get_environment("CMP_SEED1") != "" else "21"):
		# graine 2 : une seule vue aérienne générale
		await _aerial(cad[0])
		await _shot(cad[0]["nom"])
		return
	var q := _relief_point()
	for c in cad:
		var nm := String(c["nom"])
		if nm == "06b_zone_apres_pinceau":
			await _stroke(q)
		if String(c["mode"]) == "fp":
			if _aerial_cam != null:
				_hud_visible(true)
			await _fp(c)
			_hud_visible(false)
		else:
			await _aerial(c)
		await _shot(nm)
	report["trait_ms"] = _last_edit_ms

var _last_edit_ms := 0.0

## Trait de pinceau « monter » : 14 coups de rayon 2,5 m le long d'un segment de 7 m passant par q (axe est-ouest).
func _stroke(q: Vector2) -> void:
	var dabs: Array[Vector2] = []
	for k in 15:
		dabs.append(q + Vector2(-3.5 + float(k) * 0.5, 0.0))
	var t0 := Time.get_ticks_msec()
	if method == "C":
		var vw := scene.vw
		for d in dabs:
			var g := vw.ground_y(d.x, d.y)
			vw.sculpt_dab(Vector3(d.x, g - 1.25, d.y), 2.5, true)
		await _wait_voxel_idle()
	else:
		var doc := MapDoc.from_plan(IslandPlan.from_dict(plan.to_dict())["plan"] as IslandPlan)
		doc.stroke_begin("trait", "monter", q)
		var rect := Rect2i()
		for d in dabs:
			var r := doc.stroke_dab("monter", d, 2.5, 1.6)
			rect = r if rect.size == Vector2i.ZERO else rect.merge(r)
		doc.stroke_end()
		var f := scene.lab.field
		for i in f.top.size():
			if f.top[i] != doc.field.top[i]:
				f.top[i] = doc.field.top[i]
		await scene.lab.rebuild_rect(rect.grow(2))
	_last_edit_ms = Time.get_ticks_msec() - t0
	for i in 20:
		await get_tree().process_frame

func _wait_voxel_idle() -> void:
	var vw := scene.vw
	var bb := vw.bounds_voxels()
	var quiet := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
		if vw._idle():
			quiet += 1
		else:
			quiet = 0
		if quiet >= 8 and bool(vw.terrain.call("is_area_meshed", bb)):
			break

# ------------------------------------------------------------------ vérifications

func _check(cond: bool, label: String) -> void:
	if not report.has("controles"):
		report["controles"] = []
	report["controles"].append({"ok": cond, "controle": label})
	print(("  OK    " if cond else "  ÉCHEC ") + label)

func _verif() -> void:
	report["methode"] = method
	report["graine"] = seed_v
	# 1. même plan pour les trois méthodes (structure sans le réglage de méthode)
	var d := plan.structure_dict()
	(d["settings"] as Dictionary).erase("method")
	report["plan_structure_hash"] = WorldRng.fnv(JSON.stringify(d, "", true))
	# 2. reproductibilité d'une graine
	if method == "C":
		pass
	else:
		var b1 := PlanTerrain.build(plan, {"method": method})
		var b2 := PlanTerrain.build(PlanGenerator.generate(seed_v, width, length), {"method": method})
		_check(PlanTerrain.fingerprint(b1.field) == PlanTerrain.fingerprint(b2.field), "reproductibilité : même graine, même terrain (empreinte %d)" % PlanTerrain.fingerprint(b1.field))
		var reps := PlanTerrain.path_reports(plan, b1.field)
		var ok_paths := 0
		for r in reps:
			if r["ok"]:
				ok_paths += 1
		report["chemins_terrain"] = reps.map(func(r: Dictionary) -> Dictionary: return {"id": r["id"], "longueur_m": snappedf(r["length_m"], 0.1), "pente_max": snappedf(r["max_grade"], 0.01), "ok": r["ok"]})
		_check(ok_paths == reps.size(), "chemins praticables sur le terrain (%d / %d : pente ≤ 30 %%, aucune marche ≥ 40 cm)" % [ok_paths, reps.size()])
		_check(bool(PlanTerrain.start_report(plan, b1.field)["ok"]), "départ sûr (sol plat, loin du bord)")
	await _launch()
	if method == "C":
		var h1 := scene.vw.surface_hash()
		var sig1 := scene.vw.column_signature(plan.start.x, plan.start.y)
		var cols := PackedInt32Array()
		var f := scene.vw.field
		report["c_chemins"] = _voxel_paths(scene.vw)
		var okp := 0
		for r in report["c_chemins"]:
			if r["ok"]:
				okp += 1
		_check(okp == (report["c_chemins"] as Array).size(), "chemins praticables sur les voxels (%d / %d)" % [okp, (report["c_chemins"] as Array).size()])
		var spawn_ok := not is_nan(scene.vw.ground_y(plan.start.x, plan.start.y))
		_check(spawn_ok, "départ sur du sol")
		await _free_scene()
		# deuxième génération indépendante (autre VoxelTerrain, même graine) : même surface, mêmes voxels
		await _launch()
		var h2 := scene.vw.surface_hash()
		var sig2 := scene.vw.column_signature(plan.start.x, plan.start.y)
		_check(h1 == h2 and sig1 == sig2, "reproductibilité : même graine, mêmes voxels (empreinte de surface %d, colonne de départ identique)" % h1)
	# 3. exploration en première personne, le long de chaque chemin
	await _explore()
	# 4. retouche enregistrée puis rouverte
	await _free_scene()
	await _retouche()

func _voxel_paths(vw: VoxelProtoIsland) -> Array:
	var out: Array = []
	for pa in plan.paths:
		var pts: Array = pa["pts"]
		var total := IslandPlan.path_length(pts)
		var s := 0.0
		var prev := NAN
		var worst_step := 0.0
		var max_grade := 0.0
		var samples: Array = []
		while s <= total:
			var cum := PackedFloat32Array([0.0])
			for k in range(1, pts.size()):
				cum.append(cum[k - 1] + (pts[k] as Vector2).distance_to(pts[k - 1]))
			var p := PlanTerrain.point_at(pts, cum, s)
			var y := vw.ground_y(p.x, p.y)
			if not is_nan(y):
				if not is_nan(prev):
					worst_step = maxf(worst_step, absf(y - prev))
				samples.append(y)
				prev = y
			s += 0.25
		for k in range(0, samples.size() - 8):
			max_grade = maxf(max_grade, absf(samples[k + 8] - samples[k]) / 2.0)
		out.append({"id": pa["id"], "longueur_m": snappedf(total, 0.1), "pente_max": snappedf(max_grade, 0.01), "marche_max_m": snappedf(worst_step, 0.01), "ok": worst_step < 0.39 and max_grade <= 0.30})
	return out

## Parcourt chaque chemin dans le sens du plan avec l'explorateur (collisions réelles, vitesse du joueur).
func _explore() -> void:
	var ex := scene.explorer
	scene.set_aerial(false)
	var res: Array = []
	for pa in plan.paths:
		var pts: Array = pa["pts"]
		var p0: Vector2 = pts[0]
		var g := scene._ground_y(p0.x, p0.y)
		ex.teleport(Vector3(p0.x, g + 0.1, p0.y), 0.0)
		for i in 20:
			await get_tree().physics_frame
		var falls0 := scene.falls
		var t_all := 0.0
		var ok := true
		for k in range(1, pts.size()):
			var r := await _walk(ex, pts[k], 0.8)
			t_all += float(r["t"])
			if not bool(r["ok"]):
				ok = false
				break
		var end := Vector2(ex.global_position.x, ex.global_position.z)
		res.append({"id": pa["id"], "atteint": ok and scene.falls == falls0, "temps_s": snappedf(t_all, 0.1), "chutes": scene.falls - falls0, "distance_fin_m": snappedf(end.distance_to(pts[-1]), 0.1)})
		_check(ok and scene.falls == falls0, "exploration en première personne : le chemin %s est parcouru de bout en bout (%.1f s, %d chute)" % [pa["id"], t_all, scene.falls - falls0])
	report["exploration"] = res
	ex.auto_active = false

func _walk(ex: Explorer, target: Vector2, tol: float) -> Dictionary:
	ex.auto_active = true
	var t := 0.0
	var stuck := 0.0
	var check_t := 0.0
	var check_pos := Vector2(ex.global_position.x, ex.global_position.z)
	var falls0 := scene.falls
	while Vector2(ex.global_position.x, ex.global_position.z).distance_to(target) > tol:
		var p2 := Vector2(ex.global_position.x, ex.global_position.z)
		ex.auto_dir = (target - p2).normalized()
		await get_tree().physics_frame
		t += DT
		check_t += DT
		if scene.falls != falls0:
			ex.auto_dir = Vector2.ZERO
			return {"ok": false, "t": t}
		if check_t >= 1.0:
			var p3 := Vector2(ex.global_position.x, ex.global_position.z)
			if check_pos.distance_to(target) - p3.distance_to(target) < 0.3:
				stuck += check_t
				ex.auto_jump = true
			else:
				stuck = 0.0
			check_t = 0.0
			check_pos = p3
		if stuck > 5.0 or t > 120.0:
			ex.auto_dir = Vector2.ZERO
			return {"ok": false, "t": t}
	ex.auto_dir = Vector2.ZERO
	return {"ok": true, "t": t}

## Retouche enregistrée puis rouverte.
##  A / B : trait « monter » sur un MapDoc, export du fichier de carte (v3), réouverture dans un autre MapDoc, terrain identique colonne pour colonne.
##  C     : mêmes coups avec VoxelTool, VoxelStreamSQLite (blocs modifiés), nouveau VoxelTerrain sur la même base : mêmes voxels.
func _retouche() -> void:
	var q := _relief_point()
	if method == "C":
		var db := "user://cmp_c_%d.sqlite" % seed_v
		DirAccess.remove_absolute(ProjectSettings.globalize_path(db))
		await _launch({"voxel_db": db})
		var vw := scene.vw
		var before := vw.column_signature(q.x, q.y)
		await _stroke(q)
		var after := vw.column_signature(q.x, q.y)
		_check(before != after, "retouche appliquée aux voxels (la colonne a changé)")
		var save_ms := await vw.save_edits()
		_check(save_ms >= 0, "retouche enregistrée dans la base Voxel Tools (%d ms)" % save_ms)
		var ground_after := vw.ground_y(q.x, q.y)
		await _free_scene()
		await _launch({"voxel_db": db})
		var again := scene.vw.column_signature(q.x, q.y)
		_check(again == after and again != before, "base rouverte dans un nouveau VoxelTerrain : retouche retrouvée (sol %.2f m)" % scene.vw.ground_y(q.x, q.y))
		report["retouche_c"] = {"avant_sol_m": snappedf(ground_after, 0.01), "enregistrement_ms": save_ms, "octets_base": FileAccess.get_file_as_bytes(db).size() if FileAccess.file_exists(db) else -1}
	else:
		var p2 := IslandPlan.from_dict(plan.to_dict())["plan"] as IslandPlan
		var doc := MapDoc.from_plan(p2)
		var top0 := doc.field.top.duplicate()
		doc.stroke_begin("trait", "monter", q)
		for k in 15:
			doc.stroke_dab("monter", q + Vector2(-3.5 + float(k) * 0.5, 0.0), 2.5, 1.6)
		doc.stroke_end()
		_check(doc.field.top != top0, "retouche appliquée (relief modifié)")
		var path := "user://cmp_%s_%d.eclats-carte.json" % [method, seed_v]
		var ex := doc.export_to(path)
		_check(bool(ex["ok"]), "retouche enregistrée dans la carte (v3)")
		var doc2 := MapDoc.new()
		var op := doc2.open_from(path)
		_check(bool(op["ok"]) and doc2.field.top == doc.field.top and doc2.field.material == doc.field.material, "carte rouverte : relief et matières identiques colonne pour colonne")
		_check(String(doc2.plan.settings.get("method", "A")) == method, "la méthode est conservée dans la carte (%s)" % method)

# ------------------------------------------------------------------ mesures

func _med(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _mb() -> float:
	return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0

func _prims() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))

func _mesure() -> void:
	report["methode"] = method
	report["graine"] = seed_v
	report["carte_m"] = [width, length]
	report["godot"] = Engine.get_version_info()["string"]
	report["voxel_tools"] = VoxelProtoIsland.available()
	report["rendu"] = "%s / %s" % [RenderingServer.get_video_adapter_name(), ProjectSettings.get_setting("rendering/renderer/rendering_method")]
	report["processeur"] = OS.get_processor_name()
	report["coeurs"] = OS.get_processor_count()
	var m0 := _mb()
	plan.settings["method"] = method
	var runs: Array = []
	for rep in 2:            # 0 : premier chargement (processus froid) · 1 : deuxième chargement (même processus, caches chauds)
		var r := {}
		var t0 := Time.get_ticks_msec()
		var holder := Node3D.new()
		get_tree().root.add_child(holder)
		var mem_before := _mb()
		if method == "C":
			var b := PlanTerrain.build(plan, {"method": "S"})
			r["squelette_ms"] = Time.get_ticks_msec() - t0
			var vw := VoxelProtoIsland.new()
			holder.add_child(vw)
			var t1 := Time.get_ticks_msec()
			vw.setup(plan, b)
			r["installation_ms"] = Time.get_ticks_msec() - t1
			var ms := await vw.wait_loaded()
			r["generation_maillage_collisions_ms"] = ms
			# génération seule, un fil : tous les blocs de 16³ du volume
			var bb := vw.bounds_voxels()
			var t2 := Time.get_ticks_usec()
			var buf: Object = ClassDB.instantiate("VoxelBuffer")
			buf.call("create", 16, 16, 16)
			var blocks := 0
			for bz in range(int(bb.position.z), int(bb.end.z), 16):
				for bx in range(int(bb.position.x), int(bb.end.x), 16):
					if int(vw.gen.call("height_at", bx + 8, bz + 8)) <= -1000000 and bx % 64 != 0:
						continue
					for by in range(int(bb.position.y), int(bb.end.y), 16):
						buf.call("clear")
						vw.gen.call("_generate_block", buf, Vector3i(bx, by, bz), 0)
						blocks += 1
			r["generation_seule_1_fil_ms"] = float(Time.get_ticks_usec() - t2) / 1000.0
			r["blocs_generes_seuls"] = blocks
			r["relief_ms"] = r["squelette_ms"]
			r["terrain_ms"] = ms
			r["collisions_ms"] = "compris dans le maillage (tâches Voxel Tools)"
			await _free_voxel_view(vw)
			# visibilité : triangles
			for i in 10:
				await get_tree().process_frame
			var cam := Camera3D.new()
			holder.add_child(cam)
			var c := Vector2.ZERO
			var H := maxf(plan.width, plan.length) * 1.05
			cam.global_position = Vector3(c.x, 4.0 + H, c.y + H * 0.36)
			cam.look_at(Vector3(c.x, 4.0, c.y - 1.0), Vector3.UP)
			cam.current = true
			for i in 6:
				await get_tree().process_frame
			var with_t := _prims()
			vw.terrain.visible = false
			for i in 6:
				await get_tree().process_frame
			var without := _prims()
			vw.terrain.visible = true
			r["triangles_visibles_aerien"] = with_t - without
			# retouche locale : 15 coups
			var q := _relief_point()
			var t3 := Time.get_ticks_msec()
			for k in 15:
				var d := q + Vector2(-3.5 + float(k) * 0.5, 0.0)
				vw.sculpt_dab(Vector3(d.x, vw.ground_y(d.x, d.y) - 1.25, d.y), 2.5, true)
			var t_dabs := Time.get_ticks_msec() - t3
			var quiet := 0
			var bb2 := vw.bounds_voxels()
			while quiet < 4:
				await get_tree().process_frame
				quiet = quiet + 1 if (vw._idle() and bool(vw.terrain.call("is_area_meshed", bb2))) else 0
			r["retouche_locale_ms"] = Time.get_ticks_msec() - t3
			r["retouche_locale_dont_appels_ms"] = t_dabs
		else:
			var b := PlanTerrain.build(plan, {"method": method})
			PlanTerrain.apply_layers(b, plan)
			r["relief_ms"] = Time.get_ticks_msec() - t0
			var lab := LabWorld.new()
			holder.add_child(lab)
			var t1 := Time.get_ticks_msec()
			lab.setup_field(b.field, "plan", plan.seed, plan.start)
			r["terrain_ms"] = Time.get_ticks_msec() - t1
			var t2 := Time.get_ticks_usec()
			lab.update_ground()
			r["collisions_ms"] = float(Time.get_ticks_usec() - t2) / 1000.0
			# triangles (maillage des tuiles)
			var tris := 0
			for mi in lab.terrain_root.get_children():
				var mesh := (mi as MeshInstance3D).mesh
				if mesh == null:
					continue
				for s in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					tris += (idx.size() / 3) if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			r["triangles_maillage"] = tris
			var cam := Camera3D.new()
			holder.add_child(cam)
			var H := maxf(plan.width, plan.length) * 1.05
			cam.global_position = Vector3(0, 4.0 + H, H * 0.36)
			cam.look_at(Vector3(0, 4.0, -1.0), Vector3.UP)
			cam.current = true
			for i in 6:
				await get_tree().process_frame
			var with_t := _prims()
			lab.terrain_root.visible = false
			for i in 6:
				await get_tree().process_frame
			r["triangles_visibles_aerien"] = with_t - _prims()
			lab.terrain_root.visible = true
			# retouche locale : trait de 15 coups sur un MapDoc, puis mise à jour locale du terrain 3D (tuiles + collisions)
			var doc := MapDoc.from_plan(IslandPlan.from_dict(plan.to_dict())["plan"] as IslandPlan)
			var q := _relief_point()
			var t3 := Time.get_ticks_usec()
			doc.stroke_begin("trait", "monter", q)
			var rect := Rect2i()
			for k in 15:
				var rr := doc.stroke_dab("monter", q + Vector2(-3.5 + float(k) * 0.5, 0.0), 2.5, 1.6)
				rect = rr if rect.size == Vector2i.ZERO else rect.merge(rr)
			doc.stroke_end()
			var t4 := Time.get_ticks_usec()
			for i in lab.field.top.size():
				lab.field.top[i] = doc.field.top[i]
			await lab.rebuild_rect(rect.grow(2))
			r["retouche_pinceau_ms"] = float(t4 - t3) / 1000.0
			r["retouche_maj_terrain_3d_ms"] = float(Time.get_ticks_usec() - t4) / 1000.0
			r["retouche_locale_ms"] = float(Time.get_ticks_usec() - t3) / 1000.0
		r["memoire_mo"] = snappedf(_mb() - mem_before, 0.1)
		r["total_ms"] = Time.get_ticks_msec() - t0
		runs.append(r)
		get_tree().root.remove_child(holder)
		holder.free()
		for i in 5:
			await get_tree().process_frame
	report["premier_chargement"] = runs[0]
	report["deuxieme_chargement"] = runs[1]

func _free_voxel_view(_vw: Node) -> void:
	pass
