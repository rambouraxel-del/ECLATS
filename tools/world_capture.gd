extends SceneTree
## Captures de contrôle visuel d'une île générée (une génération, plusieurs vues) :
##   godot --rendering-driver opengl3 -s tools/world_capture.gd -- <profil> <graine> <dossier> [vues séparées par des virgules]
## Vues : aerial, settlement, street, relief, port, interior, grove, rocks, sunset, night, far
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out_dir := args[2]
	var views: PackedStringArray = args[3].split(",") if args.size() > 3 else PackedStringArray(["aerial", "settlement", "street", "relief", "port", "interior", "grove", "rocks", "night"])
	var world := WorldBuilder.build(args[0], int(args[1]))
	var env := EnvironmentManager.new()
	env.name = "Environment"
	root.add_child(env)
	var rig := env.rig
	var scene := Node3D.new()
	root.add_child(scene)
	WorldView.create(world, scene)
	var cam := Camera3D.new()
	cam.fov = 62
	cam.far = 2500.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true
	env.setup(world.seed)
	rig.refresh_lamps()
	var s := world.settlement
	var pc := Vector2.ZERO
	var pl_y := 3.0
	if not s.plaza.is_empty():
		pc = s.plaza["center"]
		pl_y = float(world.field.ground_y_m(s.plaza["col"].x, s.plaza["col"].y))
	else:
		var g := world.field.ground_at_m(0.0, 0.0)
		pl_y = 3.0 if is_nan(g) else g
	# point le plus haut de l'île (vue « relief »)
	var hi_i := 0
	for i in world.field.n * world.field.n:
		if world.field.top[i] > world.field.top[hi_i]:
			hi_i = i
	var hi_m := world.field.center_m(hi_i % world.field.n, hi_i / world.field.n)
	var hi_y := float(world.field.top[hi_i] + 1) * 0.2
	for v in views:
		var preset := "village_day"
		var from := Vector3.ZERO
		var to := Vector3.ZERO
		var fov := 62.0
		match v:
			"aerial":
				from = Vector3(pc.x + 8, 40, pc.y + 54); to = Vector3(pc.x, 2, pc.y)
			"far":
				from = Vector3(pc.x + 90, 40, pc.y + 150); to = Vector3(pc.x, 0, pc.y)
			"settlement":
				from = Vector3(pc.x - 13, pl_y + 9, pc.y + 17); to = Vector3(pc.x + 1, pl_y + 1.5, pc.y - 2)
			"street":
				if world.buildings.is_empty():
					continue
				var b: Dictionary = world.buildings[0]
				var d: Vector2 = b["door"]
				var dir := (pc - d).normalized()
				from = Vector3(d.x - dir.x * 1.0, world.field.ground_at_m(d.x, d.y) + 1.65, d.y - dir.y * 1.0); to = Vector3(pc.x, pl_y + 1.4, pc.y); fov = 70.0
			"shrine":
				if s.shrine.is_empty():
					continue
				var sc: Vector2 = s.shrine["center"]
				var dirv := (sc - pc).normalized()
				from = Vector3(sc.x - dirv.x * 11.0, pl_y + 2.5, sc.y - dirv.y * 11.0); to = Vector3(sc.x, float(world.field.ground_at_m(sc.x, sc.y)) + 1.8, sc.y)
			"relief":
				var dirh := (hi_m - Vector2.ZERO).normalized() if hi_m.length() > 1.0 else Vector2(0, 1)
				from = Vector3(hi_m.x - dirh.x * 4.0 + dirh.y * 9.0, hi_y + 3.5, hi_m.y - dirh.y * 4.0 - dirh.x * 9.0); to = Vector3(hi_m.x, hi_y - 0.5, hi_m.y); fov = 66.0
			"natural":
				from = Vector3(10, 34, 46); to = Vector3(0, 1, 0)
			"port":
				if world.port.is_empty():
					continue
				var rim: Vector2 = world.port["rim"]
				var axis: Vector2 = world.port["axis"]
				var perp: Vector2 = world.port["perp"]
				var side: float = world.port["ship_side"]
				var c2 := rim + axis * 6.0
				var dp: float = float(world.port["deck_top"])
				from = Vector3(c2.x + perp.x * side * 12.0 - axis.x * 5.0, dp + 4.2, c2.y + perp.y * side * 12.0 - axis.y * 5.0); to = Vector3(c2.x, dp + 0.5, c2.y); fov = 58.0
			"interior":
				if world.buildings.is_empty():
					continue
				var b: Dictionary = world.buildings[0]
				var plan: BuildingPlan = b["plan"]
				var xf: Transform3D = b["xform"]
				# caméra dans l'embrasure de la porte principale, regardant l'intérieur
				var o: BuildingPlan.Opening = plan.openings[plan.main_door]
				var local_from := Vector3((float(o.u) + float(o.w) * 0.5) * 0.1, float(plan.floor_y(0)) * 0.1 + 1.55, (float(o.p) + 3.0) * 0.1)
				var local_to := Vector3((float(o.u) + float(o.w) * 0.5) * 0.1 - 0.2, float(plan.floor_y(0)) * 0.1 + 1.0, (float(o.p) - 25.0) * 0.1)
				from = xf * local_from; to = xf * local_to; fov = 75.0
			"grove":
				if world.trees.is_empty():
					continue
				var t: Dictionary = world.trees[0]
				var tp: Vector3 = t["pos"]
				from = tp + Vector3(10.0, 5.5, 11.0); to = tp + Vector3(0, 1.8, 0)
			"rocks":
				if world.rocks.is_empty():
					continue
				var best: Dictionary = world.rocks[0]
				for r in world.rocks:
					if r["family"] == "formation":
						best = r
						break
				var rp: Vector3 = best["pos"]
				from = rp + Vector3(6.0, 2.4, 6.5); to = rp + Vector3(0, 1.3, 0)
			"sunset":
				preset = "village_sunset"; from = Vector3(pc.x + 8, 24, pc.y + 44); to = Vector3(pc.x, 3, pc.y)
			"night":
				preset = "village_night"; from = Vector3(pc.x - 7, pl_y + 15, pc.y + 21); to = Vector3(pc.x + 1, pl_y + 0.5, pc.y - 2)
		env.apply_key(preset)
		rig.refresh_lamps()
		cam.fov = fov
		cam.global_position = from
		cam.look_at(to)
		for i in int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 6:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, v])
		print("capture ", v)
	quit()
