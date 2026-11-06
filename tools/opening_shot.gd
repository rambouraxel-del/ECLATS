extends SceneTree
## Captures de l'île d'ouverture (Lot 5) depuis la caméra du joueur :
##   godot --rendering-driver opengl3 -s tools/opening_shot.gd -- dossier "x,z,yaw_deg[,pitch[,y_rayon]][;…]"
## Chaque point : l'explorateur est posé au sol en (x, z), tourné vers yaw, la caméra derrière lui.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var scene: Node = (load("res://scenes/game/opening_island.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var waited := 0
	while not bool(scene.get("ready_to_play")) and waited < 20000:
		await process_frame
		waited += 1
	var shots: PackedStringArray = args[1].split(";") if args.size() > 1 else PackedStringArray()
	var k := 0
	for s in shots:
		var v := s.split(",")
		var x := float(v[0])
		var z := float(v[1])
		var yaw := deg_to_rad(float(v[2]))
		for i in 2:
			await physics_frame
		var g: float = scene.call("ground_y_at", x, z, float(v[4]) if v.size() > 4 else 300.0)
		var ex: Explorer = scene.get("explorer")
		ex.teleport(Vector3(x, (0.0 if is_nan(g) else g) + 0.05, z), yaw + PI)
		var cr: ThirdPersonCamera = scene.get("camrig")
		cr.yaw = yaw + PI
		cr.pitch = float(v[3]) if v.size() > 3 else -0.25
		for i in 20:
			await physics_frame
		cr.interior = bool(scene.call("_is_interior", ex.global_position))
		cr.snap()
		for i in 8:
			await process_frame
		var path := "%s/shot_%02d.png" % [out_dir, k]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		k += 1
	quit()
