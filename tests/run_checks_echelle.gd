extends SceneTree
## Échelle et immersion : valeurs dérivées de config/player.json, capsule et caméra cohérentes, champ de vision (F),
## arbres et rochers de l'île d'ouverture agrandis de façon mesurée (aucun agrandissement global).
##   godot --headless -s tests/run_checks_echelle.gd
var ok := 0
var ko := 0

func check(cond: bool, label: String) -> void:
	if cond:
		ok += 1
		print("  OK    ", label)
	else:
		ko += 1
		print("  ÉCHEC ", label)

func _initialize() -> void:
	print("== Échelle et immersion ==")
	PlayerConfig.ensure()
	check(absf(PlayerConfig.height - 1.5) < 0.001, "hauteur du personnage : 1,50 m (config/player.json)")
	check(absf(PlayerConfig.eye() - 1.6 * 1.5 / 1.7) < 0.001 and PlayerConfig.eye() < PlayerConfig.height, "yeux à %.2f m, sous le haut de la capsule" % PlayerConfig.eye())
	check(absf(PlayerConfig.radius() - 0.28 * 1.5 / 1.7) < 0.001, "rayon de la capsule %.2f m (même proportion qu'avant)" % PlayerConfig.radius())
	var ex := Explorer.new()
	get_root().add_child(ex)
	await process_frame
	var cap := (ex.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	check(absf(cap.height - PlayerConfig.height) < 0.001 and absf(cap.radius - PlayerConfig.radius()) < 0.001, "capsule de collision : %.2f m × rayon %.2f m" % [cap.height, cap.radius])
	check(absf(ex.model.scale.y - PlayerConfig.k()) < 0.001, "le modèle suit l'échelle (×%.3f)" % ex.model.scale.y)
	check(Explorer.STEP_H >= 0.3 + 0.05, "les marches de 30 cm se montent (hauteur franchissable %.0f cm)" % (Explorer.STEP_H * 100.0))
	# porte : 80 cm de large minimum pour une capsule de 2 × rayon
	check(PlayerConfig.radius() * 2.0 < 0.6, "capsule plus étroite qu'un passage de 60 cm")
	# champ de vision
	var cam := ThirdPersonCamera.new()
	get_root().add_child(cam)
	await process_frame
	cam.first_person = true
	check(absf(cam.cam.fov - PlayerConfig.fov_fp) < 0.01, "caméra : champ de vision de départ %d°" % roundi(cam.cam.fov))
	var seen: Array = []
	PlayerConfig.fov_fp = 76.0
	for i in 3:
		seen.append(PlayerConfig.cycle_fov())
	check(seen == [84.0, 68.0, 76.0], "touche F : 76° → 84° → 68° → 76° (%s)" % str(seen))
	cam.first_person = true
	check(absf(cam.cam.fov - 76.0) < 0.01, "la caméra reprend le champ de vision choisi")
	cam.first_person = false
	check(absf(cam.cam.fov - 64.0) < 0.01, "3e personne : écart d'origine conservé (64° pour 76°)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerConfig.SETTINGS))
	# île d'ouverture : arbres et rochers
	var map := IslandMap.load_map()
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/islands/archive/ile_ouverture_lot11.json"))
	var scaled := 0
	var worst := 1.0
	for t in map["trees"]:
		var k := float(t.get("scale", 1.0))
		if k != 1.0:
			scaled += 1
		worst = maxf(worst, k)
	check(scaled > 0 and scaled < (map["trees"] as Array).size() / 2 and worst <= 1.25, "arbres : %d sur %d agrandis, au plus ×%.2f" % [scaled, (map["trees"] as Array).size(), worst])
	var rs := 0
	var rworst := 1.0
	for i in (map["rocks"] as Array).size():
		var k := float(map["rocks"][i].get("scale", 1.0)) / float(old["rocks"][i].get("scale", 1.0))
		if absf(k - 1.0) > 0.001:
			rs += 1
		rworst = maxf(rworst, k)
	check(rs > 0 and rs < (map["rocks"] as Array).size() / 2 and rworst <= 1.26, "rochers : %d sur %d agrandis, au plus ×%.2f" % [rs, (map["rocks"] as Array).size(), rworst])
	check(map["trees"].size() == old["trees"].size() and map["rocks"].size() == old["rocks"].size() and map["buildings"] == old["buildings"] and map["paths"] == old["paths"] and map["terrain"] == old["terrain"], "positions, bâtiments, chemins et relief inchangés")
	print("== %d réussite(s), %d échec(s) ==" % [ok, ko])
	quit(1 if ko > 0 else 0)
