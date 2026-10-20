extends SceneTree
## Aperçu d'un bâtiment généré :
##   godot --rendering-driver opengl3 -s tools/preview_building.gd -- <type> <seed> <sortie.png> [azimut] [élévation] [distance] [preset] [cx cy cz tx ty tz]
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	VoxelMesher.palette_warmup()
	var plan := BuildingPlanner.plan(args[0], int(args[1]))
	var model := BuildingBuilder.build(plan)
	var arrays := BuildingView.make_arrays(model)
	var rig := LightingRig.new()
	rig.start_preset = args[6] if args.size() > 6 else "presentation"
	root.add_child(rig)
	var node := BuildingView.create_node(model, arrays)
	root.add_child(node)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	pm.material = load("res://materials/lab_floor_material.tres")
	fl.mesh = pm
	fl.position = Vector3(0, 0.2, 0)     # sol fini = GY * 10 cm
	root.add_child(fl)
	var size := model.size_m()
	var center := Vector3(size.x * 0.5, size.y * 0.35, size.z * 0.5)
	var az := deg_to_rad(float(args[3]) if args.size() > 3 else 30.0)
	var el := deg_to_rad(float(args[4]) if args.size() > 4 else 22.0)
	var dist := float(args[5]) if args.size() > 5 else size.length() * 1.15
	var cam := Camera3D.new()
	cam.fov = 45
	root.add_child(cam)
	cam.global_position = center + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * dist
	cam.look_at(center)
	if args.size() >= 13:
		cam.global_position = Vector3(float(args[7]), float(args[8]), float(args[9]))
		cam.look_at(Vector3(float(args[10]), float(args[11]), float(args[12])))
	cam.current = true
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[2])
	quit()
