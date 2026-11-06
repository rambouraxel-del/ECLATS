extends SceneTree
## Lot 10 — captures à cadrages FIXES (avant / après). Mêmes points, même lumière, même hauteur d'yeux.
##   godot --rendering-driver opengl3 --resolution 1280x720 -s tools/lot10_captures.gd -- cadrages.json dossier [préfixe] [nom1,nom2]
## Chaque cadrage : {nom, mode:"fp"|"aerial", pos:[x,z], look:[x,z], pitch, (aerial: h, fov)}.
## fp = première personne au sol (le joueur est posé en pos, regard vers look).
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var cad: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var out_dir: String = args[1]
	var prefix := String(args[2]) if args.size() > 2 else ""
	var only: PackedStringArray = String(args[3]).split(",") if args.size() > 3 else PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameSave.clear_island("ile-ouverture-01")
	var scene: Node = (load("res://scenes/game/opening_island.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var t0 := Time.get_ticks_msec()
	while not bool(scene.get("ready_to_play")) and Time.get_ticks_msec() - t0 < 900000:
		await process_frame
		OS.delay_msec(5)
	_sonde(scene)
	var ex: Explorer = scene.get("explorer")
	var cr: ThirdPersonCamera = scene.get("camrig")
	for c in cad:
		var nm := String(c["nom"])
		if only.size() > 0 and not only.has(nm):
			continue
		var p: Array = c["pos"]
		var l: Array = c["look"]
		var yaw := atan2(-(float(l[0]) - float(p[0])), -(float(l[1]) - float(p[1])))
		var g: float = scene.call("ground_y_at", float(p[0]), float(p[1]), 300.0)
		if String(c.get("mode", "fp")) == "fp":
			ex.teleport(Vector3(float(p[0]), g + 0.05, float(p[1])), yaw)
			cr.yaw = yaw
			cr.pitch = float(c.get("pitch", -0.05))
			for i in 25:
				await physics_frame
			cr.interior = bool(scene.call("_is_interior", ex.global_position))
			cr.snap()
			for i in 10:
				await process_frame
		else:
			var cam := Camera3D.new()
			cam.fov = float(c.get("fov", 60))
			cam.far = 1200.0
			root.add_child(cam)
			var h := float(c.get("h", 150))
			cam.global_position = Vector3(float(p[0]), h, float(p[1]))
			cam.look_at(Vector3(float(l[0]), float(c.get("ly", 10.0)), float(l[1])), Vector3.UP)
			cam.current = true
			for i in 20:
				await process_frame
			ex.visible = false
		var path := "%s/%s%s.png" % [out_dir, prefix, nm]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		if String(c.get("mode", "fp")) != "fp":
			ex.visible = true
			for n in root.get_children():
				if n is Camera3D:
					n.queue_free()
			cr.cam.current = true
	quit()

## Sonde : position du navire et du ponton (pour choisir les cadrages).
func _sonde(n: Node, depth := 0) -> void:
	if depth > 6:
		return
	for c in n.get_children():
		var nm := String(c.name).to_lower()
		if c is Node3D and (nm.contains("ship") or nm.contains("pier") or nm.contains("quai")):
			var bb := AABB()
			for m in c.find_children("*", "MeshInstance3D", true, false):
				bb = bb.merge((m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()) if bb.size != Vector3.ZERO else (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			print("[sonde] ", c.name, " origine ", (c as Node3D).global_position, " boîte ", bb)
		_sonde(c, depth + 1)
