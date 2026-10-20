extends SceneTree
## godot --rendering-driver opengl3 -s tools/preview_ship.gd -- <graine> <sortie.png> [azimut élévation distance]
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	VoxelMesher.palette_warmup()
	var t0 := Time.get_ticks_msec()
	var ship := ShipGenerator.build(int(args[0]))
	print("ship ms ", Time.get_ticks_msec() - t0, " L ", ship["L"], " sails ", ship["sails"].size(), " wood comps ", ship["wood_components"], " removed ", ship["removed_floating"])
	print("issues ", ShipGenerator.check(ship))
	var node := ShipView.create_node(ship)
	var rig := LightingRig.new()
	rig.start_preset = "village_day"
	root.add_child(rig)
	root.add_child(node)
	var az := deg_to_rad(float(args[2]) if args.size() > 2 else 40.0)
	var el := deg_to_rad(float(args[3]) if args.size() > 3 else 14.0)
	var dist := float(args[4]) if args.size() > 4 else 17.0
	var cam := Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	var center := Vector3(0, 2.0, 0)
	cam.global_position = center + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * dist
	cam.look_at(center)
	cam.current = true
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[1])
	quit()
