extends SceneTree
## Planche-contact d'assets sur une rangée :
##   godot --rendering-driver opengl3 -s tools/sheet.gd -- sortie.png [preset] id1 id2 ...
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var rig := LightingRig.new()
	rig.start_preset = args[1]
	root.add_child(rig)
	var x := 0.0
	var tallest := 0.0
	var depth := 0.0
	for i in range(2, args.size()):
		var inst := AssetLibrary.instantiate(args[i])
		if inst == null:
			continue
		var size := (inst as PlaceableAsset).footprint_size_m()
		inst.position = Vector3(x, 0, 0)
		root.add_child(inst)
		x += size.x + 0.7
		tallest = maxf(tallest, size.y)
		depth = maxf(depth, size.z)
	var total := x
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 40)
	pm.material = load("res://materials/lab_floor_material.tres")
	floor_mi.mesh = pm
	floor_mi.position = Vector3(total * 0.5, -0.01, 0)
	root.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	var center := Vector3(total * 0.5, tallest * 0.38, depth * 0.4)
	cam.global_position = center + Vector3(total * 0.12, tallest * 0.55 + 0.4, maxf(total * 0.95, 5.0))
	cam.look_at(center)
	cam.current = true
	for i in 25:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[0])
	quit()
