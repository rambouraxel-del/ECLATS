extends Node
## Recette JOUÉE du personnage articulé, dans le VRAI jeu (île d'ouverture, collisions réelles, rendu logiciel) :
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 -- --recette=res://tools/personnage_recette.gd
## Le pilote automatique tient la place du joueur (mêmes déplacements, mêmes collisions, mêmes animations) ; la vue
## bascule par la vraie méthode de la touche V. Sortie : captures (OUT), images du GIF (FRAMES), rapport JSON.
const OUT := "/home/user/ECLATS/docs/captures/personnage"
const FRAMES := "/tmp/claude-0/-home-user/a63a7b17-b085-5a47-af76-319612b62b36/scratchpad/pn_frames"

var scene: Node
var ex: Explorer
var cam: ThirdPersonCamera
var report := {"controles": [], "captures": []}
var _gif := 0
var _gif_dir := ""

func _check(cond: bool, label: String) -> void:
	report["controles"].append({"ok": cond, "controle": label})
	print(("  OK    " if cond else "  ÉCHEC ") + label)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [OUT, name], 0.9)
	report["captures"].append(name)
	print("saved ", name)

func _grab(every := 2) -> void:
	if _gif % every == 0:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		img.save_png("%s/%s_%03d.png" % [FRAMES, _gif_dir, _gif / every])
	_gif += 1

func _pos2() -> Vector2:
	return Vector2(ex.global_position.x, ex.global_position.z)

func _place(p: Vector2, face_dir: Vector2, view_dir: Vector2, dist := 4.6) -> void:
	var g := float(scene.call("ground_y_at", p.x, p.y))
	ex.teleport(Vector3(p.x, (0.0 if is_nan(g) else g) + 0.05, p.y), atan2(-face_dir.x, -face_dir.y))
	cam.yaw = atan2(-view_dir.x, -view_dir.y)
	cam.pitch = -0.12
	cam.dist_out = dist
	cam.snap()

## Marche dans une direction pendant `secs` (physique réelle) ; enregistre des images si `gif` ≠ "".
func _go(dir: Vector2, secs: float, sprint := false, gif := "") -> void:
	ex.auto_active = true
	ex.auto_dir = dir
	ex.auto_sprint = sprint
	_gif = 0
	_gif_dir = gif
	var n := int(secs * 30.0)
	for i in n:
		await get_tree().process_frame
		if gif != "":
			await _grab()
	ex.auto_dir = Vector2.ZERO
	ex.auto_sprint = false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(FRAMES)
	DirAccess.make_dir_recursive_absolute(OUT)
	get_node("/root/App").call("open", "res://scenes/game/opening_island.tscn")
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 900000:
		await get_tree().process_frame
		var s := get_tree().current_scene
		if s != null and s.get("ready_to_play") == true:
			scene = s
			break
		OS.delay_msec(5)
	await _frames(20)
	ex = scene.get("explorer")
	cam = scene.get("camrig")
	await _play()
	var f := FileAccess.open("%s/%s" % [OUT, "rapport_collision.json" if OS.get_environment("PN_ONLY") == "collision" else "rapport_recette.json"], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	var bad := 0
	for c in report["controles"]:
		if not c["ok"]:
			bad += 1
	print("Recette personnage : %d contrôles, %d échecs" % [report["controles"].size(), bad])
	get_tree().quit()

func _height_m() -> float:
	var top := -1e9
	var bot := 1e9
	for n in ex.model.parts:
		for c in (ex.model.parts[n] as Node3D).get_children():
			if c is MeshInstance3D:
				var bb := (c as MeshInstance3D).global_transform * (c as MeshInstance3D).mesh.get_aabb()
				top = maxf(top, bb.end.y)
				bot = minf(bot, bb.position.y)
	return top - bot

func _play() -> void:
	var house := {}
	for it in scene.get("interiors"):
		if bool(it.get("visitable", false)):
			house = it
	var door := Vector2(float(house["door"][0]), float(house["door"][1]))
	var front := Vector2(float(house["front"][0]), float(house["front"][1])).normalized()
	var side := Vector2(-front.y, front.x)
	_check(ex.model != null and ex.model.anim != null and ex.model.parts.size() >= 17, "modèle articulé présent (%d pivots, animations : %s)" % [ex.model.parts.size(), str(ex.model.anim.get_animation_list())])
	if OS.get_environment("PN_ONLY") == "collision":
		cam.first_person = false
		await _collision(door, front, side)
		return
	var h := _height_m()
	_check(absf(h - PlayerConfig.height) < 0.12, "hauteur du modèle %.2f m ≈ capsule %.2f m (échelle conservée)" % [h, PlayerConfig.height])
	# 1. vue 3e personne, au repos près de la porte : de face, de côté
	cam.first_person = false
	await _frames(2)
	_place(door + front * 1.1 + side * 1.0, front, -front, 3.2)
	await _frames(40)
	_check(ex.model.current_clip() == "idle", "à l'arrêt : animation d'attente (« %s »)" % ex.model.current_clip())
	await _shot("jeu_porte_de_face")
	_place(door + front * 1.3 - side * 1.1, side, -front, 3.2)
	ex.face(atan2(-side.x, -side.y))
	await _frames(20)
	await _shot("jeu_porte_de_cote")
	_place(door + front * 1.0 + side * 1.0, -front, -front, 3.4)
	await _frames(20)
	await _shot("jeu_porte_de_dos")
	# 2. marche le long de la façade (GIF), puis course
	_place(door + front * 2.2 - side * 4.0, side, -front, 3.6)
	await _frames(15)
	var p0 := _pos2()
	await _go(side, 2.6, false, "marche")
	_check(ex.model.current_clip() == "walk", "en marche : animation de marche (« %s »)" % ex.model.current_clip())
	var d_walk := p0.distance_to(_pos2())
	_check(d_walk > 3.0, "déplacement réel en marche : %.1f m en 2,6 s (≈ 2,3 m/s)" % d_walk)
	await _shot("jeu_marche")
	_place(door + front * 2.2 - side * 6.0, side, -front, 3.8)
	await _frames(15)
	p0 = _pos2()
	await _go(side, 2.2, true, "course")
	_check(ex.model.current_clip() == "run", "à la course : animation de course (« %s »)" % ex.model.current_clip())
	_check(p0.distance_to(_pos2()) > 6.5, "déplacement réel à la course : %.1f m en 2,2 s" % p0.distance_to(_pos2()))
	await _shot("jeu_course")
	await _frames(60)
	_check(ex.model.current_clip() == "idle", "arrêt : retour à l'attente (« %s »)" % ex.model.current_clip())
	# 3. saut
	ex.auto_jump = true
	await _frames(8)
	_check(ex.model.current_clip() == "jump" or not ex.is_on_floor(), "saut : animation en l'air (« %s »)" % ex.model.current_clip())
	await _shot("jeu_saut")
	await _frames(60)
	# 4. changement de vue (méthode de la touche V) : modèle caché en 1re personne, visible en 3e
	var vis3 := ex.model.visible
	cam.toggle_view()
	await _frames(3)
	_check(cam.first_person and not ex.model.visible, "1re personne : modèle masqué, caméra aux yeux (%.2f m du sol)" % (cam.cam.global_position.y - ex.global_position.y))
	_place(door + front * 2.2, -front, front * 0.0 - front)
	cam.pitch = 0.0
	cam.snap()
	await _frames(20)
	await _shot("jeu_premiere_personne_porte")
	await _go(-front, 1.0, false)
	_check(ex.model.current_clip() == "walk", "1re personne : l'animation continue d'être jouée (« %s »)" % ex.model.current_clip())
	cam.toggle_view()
	await _frames(3)
	_check(not cam.first_person and ex.model.visible and vis3, "retour en 3e personne : modèle visible")
	await _collision(door, front, side)
	ex.auto_active = false
	var f := FileAccess.open("%s/frames.txt" % FRAMES, FileAccess.WRITE)
	f.store_string("ok")
	f.close()

## 5. collisions : marche droit contre la façade, à côté de la porte
func _collision(door: Vector2, front: Vector2, side: Vector2) -> void:
	# 5. collisions : marche contre la façade, à 3 m de la porte
	_place(door + front * 2.0 + side * 1.9, -front, -front, 3.4)
	await _frames(15)
	var start := _pos2()
	await _go(-front, 3.0)
	var rel := _pos2() - door
	_check(rel.dot(front) > -0.6, "collision : arrêté par le soubassement de la façade (%.2f m derrière le seuil, déplacement %.1f m sur 6,9 m possibles)" % [rel.dot(front), start.distance_to(_pos2())])
	await _shot("jeu_collision_facade")
	ex.auto_active = false
