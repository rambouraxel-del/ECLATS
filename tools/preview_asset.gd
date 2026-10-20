extends SceneTree
## Aperçu d'un asset (capture d'écran), sans passer par une scène :
##   godot --rendering-driver opengl3 -s tools/preview_asset.gd -- <id> <sortie.png> [azimut°] [élévation°] [distance]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	await process_frame
	var inst := AssetLibrary.instantiate(args[0])
	var rig := LightingRig.new()
	rig.start_preset = "presentation"
	root.add_child(rig)
	root.add_child(inst)
	var size := (inst as PlaceableAsset).footprint_size_m()
	var center := Vector3(size.x * 0.5, size.y * 0.42, size.z * 0.5)
	var az := deg_to_rad(float(args[2]) if args.size() > 2 else 35.0)
	var el := deg_to_rad(float(args[3]) if args.size() > 3 else 28.0)
	var dist := float(args[4]) if args.size() > 4 else size.length() * 1.25
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.global_position = center + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * dist
	cam.look_at(center)
	cam.current = true
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	pm.material = load("res://materials/lab_floor_material.tres")
	floor_mi.mesh = pm
	root.add_child(floor_mi)
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[1])
	quit()
