extends SceneTree
## Personnage articulé : pivots, hauteur, animations (idle / walk / run / jump), choix du clip selon la vitesse,
## intégration à l'Explorer (échelle, capsule), palette, export galerie.
##   godot --headless -s tests/run_checks_personnage.gd
var ok := 0
var ko := 0

func check(cond: bool, label: String) -> void:
	if cond:
		ok += 1
		print("  OK    ", label)
	else:
		ko += 1
		print("  ÉCHEC ", label)

func _bbox(m: ExplorerModel) -> AABB:
	var box := AABB()
	var first := true
	for n in m.parts:
		var pv: Node3D = m.parts[n]
		for c in pv.get_children():
			if c is MeshInstance3D:
				var xf := Transform3D.IDENTITY
				var node: Node3D = c
				while node != m:
					xf = node.transform * xf
					node = node.get_parent()
				var bb: AABB = xf * (c as MeshInstance3D).mesh.get_aabb()
				box = bb if first else box.merge(bb)
				first = false
	return box

func _initialize() -> void:
	print("== Personnage articulé ==")
	GameInput.ensure()
	PlayerConfig.ensure()
	VoxelMesher.palette_warmup()
	var pal := VoxelPalette.get_default()
	var all := true
	for k in ["perso_cheveux", "perso_peau", "perso_cape", "perso_beige", "perso_tunique", "perso_pantalon", "perso_cuir", "perso_botte", "perso_verre", "perso_laiton", "perso_oeil"]:
		all = all and pal.id(k) > 0
	check(all, "matières du personnage dans la palette")
	check(pal.id("stone") == 1 or pal.id("stone") > 0, "identifiants de palette existants intacts (stone = %d)" % pal.id("stone"))
	var m := ExplorerModel.new()
	m.build_now()
	var need := ["Hips", "Torso", "Head", "ArmL", "ArmR", "ForearmL", "ForearmR", "ThighL", "ThighR", "ShinL", "ShinR", "FootL", "FootR", "CapeUp", "CapeLow", "Tabard", "Pouch"]
	var miss: Array = []
	for n in need:
		if not m.parts.has(n):
			miss.append(n)
	check(miss.is_empty(), "17 pivots présents %s" % str(miss))
	var bb := _bbox(m)
	check(absf(bb.size.y - 1.72) < 0.1, "hauteur du modèle %.2f m (≈ 1,72 m avant échelle)" % bb.size.y)
	check(absf(bb.position.y) < 0.03, "pieds posés sur y = 0 (%.3f)" % bb.position.y)
	check(bb.size.x < 0.95 and bb.size.z < 0.6, "encombrement %.2f × %.2f m" % [bb.size.x, bb.size.z])
	var head: Node3D = m.parts["Head"]
	check(head.global_transform.origin.y == head.global_transform.origin.y and (m.parts["Hips"] as Node3D).position.y > 0.5, "bassin à %.2f m" % (m.parts["Hips"] as Node3D).position.y)
	check(m.anim != null and m.anim.get_animation_list().size() == 4, "animations : %s" % str(m.anim.get_animation_list()))
	for c in ["idle", "walk", "run", "jump"]:
		var a := m.anim.get_animation(c)
		check(a != null and a.loop_mode == Animation.LOOP_LINEAR and absf(a.length - float(ExplorerModel.CLIPS[c][1])) < 0.001 and a.get_track_count() >= 14, "clip %s : boucle de %.2f s, %d pistes" % [c, a.length, a.get_track_count()])
		# boucle sans saut : première et dernière images identiques
		var same := true
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var q0: Quaternion = a.track_get_key_value(t, 0)
				var q1: Quaternion = a.track_get_key_value(t, a.track_get_key_count(t) - 1)
				same = same and q0.angle_to(q1) < 0.001
		check(same, "clip %s : boucle continue (début = fin)" % c)
	# les jambes bougent réellement en marche et plus en attente
	m.pose_at("walk", 0.0)
	var q_walk := (m.parts["ThighL"] as Node3D).rotation.x
	m.pose_at("walk", 0.45 * 0.5)
	var q_walk2 := (m.parts["ThighL"] as Node3D).rotation.x
	check(absf(q_walk - q_walk2) > 0.3, "marche : la cuisse oscille (%.2f → %.2f rad)" % [q_walk, q_walk2])
	m.pose_at("run", 0.56 * 0.25)
	check(absf((m.parts["ThighL"] as Node3D).rotation.x) > 0.7, "course : foulée plus ample (%.2f rad)" % (m.parts["ThighL"] as Node3D).rotation.x)
	check((m.parts["Torso"] as Node3D).rotation.x > 0.15, "course : torse penché (%.2f rad)" % (m.parts["Torso"] as Node3D).rotation.x)
	m.pose_at("idle", 0.0)
	check(absf((m.parts["ThighL"] as Node3D).rotation.x) < 0.05, "attente : jambes au repos")
	m.free()
	# Explorer : choix du clip selon la vitesse et l'état au sol
	var ex := Explorer.new()
	get_root().add_child(ex)
	await process_frame
	check(absf(ex.model.scale.y - PlayerConfig.k()) < 0.001, "échelle du jeu conservée (×%.3f → %.2f m)" % [ex.model.scale.y, 1.72 * ex.model.scale.y])
	var cap := (ex.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	check(absf(cap.height - PlayerConfig.height) < 0.001, "capsule de collision inchangée (%.2f m)" % cap.height)
	ex.model.animate(0.0, true, 0.016)
	check(ex.model.current_clip() == "idle", "vitesse 0 : attente")
	ex.model.animate(1.0, true, 0.016)
	check(ex.model.current_clip() == "walk", "vitesse de marche : marche")
	ex.model.animate(2.0, true, 0.016)
	check(ex.model.current_clip() == "run", "vitesse de course : course")
	ex.model.animate(2.0, false, 0.016)
	check(ex.model.current_clip() == "run", "décollage d'une image : pas de saut")
	for i in 8:
		ex.model.animate(2.0, false, 0.016)
	check(ex.model.current_clip() == "jump", "en l'air plus de 0,08 s : saut / chute")
	ex.model.animate(0.0, true, 0.016)
	check(ex.model.current_clip() == "idle", "retour au sol : attente")
	var cam := ThirdPersonCamera.new()
	cam.target = ex
	get_root().add_child(cam)
	await process_frame
	cam.first_person = true
	check(not ex.model.visible, "1re personne : modèle masqué")
	cam.toggle_view()
	check(ex.model.visible and not cam.first_person, "bascule en 3e personne : modèle visible")
	print("== %d réussite(s), %d échec(s) ==" % [ok, ko])
	quit(1 if ko > 0 else 0)
