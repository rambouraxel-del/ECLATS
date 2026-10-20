extends SceneTree
## Capture d'écran d'une scène (outil de vérification visuelle).
## Usage : godot --rendering-driver opengl3 -s tools/capture.gd -- <scène.tscn> <sortie.png> [px py pz tx ty tz] [preset]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: PackedScene = load(args[0])
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var cam := root.get_viewport().get_camera_3d()
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
	img.save_png(args[1])
	print("saved ", args[1])
	quit()
