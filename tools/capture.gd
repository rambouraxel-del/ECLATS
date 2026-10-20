extends SceneTree
## Capture d'écran d'une scène (outil de vérification visuelle).
## Usage : godot --rendering-driver opengl3 -s tools/capture.gd -- <scène.tscn> <sortie.png> [px py pz tx ty tz] [preset]
##         ... -- <scène.tscn> <sortie.png> view <n> [preset]    (vue prédéfinie du laboratoire)
##         ... -- <scène.tscn> <sortie.png> legacy <px py pz tx ty tz> [preset]  (île, rendu Lot 1)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[1]
	var scene: PackedScene = load(args[0])
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var cam := root.get_viewport().get_camera_3d()
	if args.size() >= 3 and args[2] == "legacy":
		for n in inst.get_children():
			if n is VoxelIsland:
				n.render_style = VoxelMesher.Style.LEGACY
		args.remove_at(2)
	if args.size() >= 4 and args[2] == "view":
		cam.set_process(false)
		inst.call("_go_to_view", int(args[3]))
		if args.size() >= 5:
			inst.get_node("LightingRig").apply_preset_key(args[4])
		args = PackedStringArray()
	if cam and args.size() >= 8:
		cam.set_process(false)
		cam.global_position = Vector3(float(args[2]), float(args[3]), float(args[4]))
		cam.look_at(Vector3(float(args[5]), float(args[6]), float(args[7])))
	if args.size() >= 9:
		var rig := inst.get_node_or_null("LightingRig")
		if rig:
			rig.apply_preset_key(args[8])
	for i in 30:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit()
