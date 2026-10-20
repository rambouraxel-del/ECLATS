extends SceneTree
## Aperçu d'une île générée :
##   godot --rendering-driver opengl3 -s tools/world_preview.gd -- <profil> <graine> <sortie.png> [preset] [px py pz tx ty tz]
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	var world := WorldBuilder.build(args[0], int(args[1]))
	print("génération : ", Time.get_ticks_msec() - t0, " ms ", world.timings)
	print("bâtiments ", world.buildings.size(), " échecs ", world.failures)
	print("rejets ", world.stats.get("site_reasons"))
	if not world.port.is_empty():
		print("port rim ", world.port["rim"], " axis ", world.port["axis"], " deck_top ", world.port["deck_top"], " side ", world.port["ship_side"])
	var rig := LightingRig.new()
	rig.start_preset = args[3] if args.size() > 3 else "village_day"
	root.add_child(rig)
	var scene := Node3D.new()
	root.add_child(scene)
	var refs := WorldView.create(world, scene)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.far = 2500.0
	root.add_child(cam)
	if args.size() >= 5 and args[4] == "port" and not world.port.is_empty():
		var rim: Vector2 = world.port["rim"]
		var axis: Vector2 = world.port["axis"]
		var perp: Vector2 = world.port["perp"]
		var side: float = world.port["ship_side"]
		var d := float(args[5]) if args.size() > 5 else 13.0
		var h := float(args[6]) if args.size() > 6 else 4.0
		var c2 := rim + axis * 5.0
		cam.global_position = Vector3(c2.x - perp.x * side * d, float(world.port["deck_top"]) + h, c2.y - perp.y * side * d)
		cam.look_at(Vector3(c2.x + perp.x * side * 1.5, float(world.port["deck_top"]) - 0.5, c2.y + perp.y * side * 1.5))
	elif args.size() >= 10:
		cam.global_position = Vector3(float(args[4]), float(args[5]), float(args[6]))
		cam.look_at(Vector3(float(args[7]), float(args[8]), float(args[9])))
	else:
		cam.global_position = Vector3(0, 38, 52)
		cam.look_at(Vector3(0, 2, 0))
	cam.current = true
	rig.refresh_lamps()
	for i in 24:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[2])
	quit()
