extends SceneTree
## Diagnostic de marche (Lot 5) : godot --headless --fixed-fps 60 -s tools/opening_debug_walk.gd -- "x0,z0,x1,z1[,y_rayon];…"
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: Node = (load("res://scenes/game/opening_island.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var t_wait := Time.get_ticks_msec()
	while not bool(scene.get("ready_to_play")) and Time.get_ticks_msec() - t_wait < 600000:
		await process_frame
		OS.delay_msec(5)
	var ex: Explorer = scene.get("explorer")
	print("chargé, cache=", scene.get("from_cache"))
	for spec in args[0].split(";"):
		var v := spec.split(",")
		var a := Vector2(float(v[0]), float(v[1]))
		var b := Vector2(float(v[2]), float(v[3]))
		var y0: float = scene.call("ground_y_at", a.x, a.y, float(v[4]) if v.size() > 4 else 300.0)
		ex.teleport(Vector3(a.x, y0 + 0.05, a.y))
		for i in 10:
			await physics_frame
		ex.auto_active = true
		print("--- de ", a, " vers ", b, " (sol ", y0, ")")
		for i in 360:
			var p := ex.global_position
			var d := b - Vector2(p.x, p.z)
			if d.length() < 0.3:
				break
			ex.auto_dir = d.normalized()
			await physics_frame
			if i % 15 == 0:
				var hit := ""
				for k in ex.get_slide_collision_count():
					var c := ex.get_slide_collision(k)
					hit += " [%s n=%s]" % [(c.get_collider() as Node).name if c.get_collider() is Node else "?", c.get_normal().snapped(Vector3(0.01, 0.01, 0.01))]
				print("%.2f %.2f %.2f sol=%s marches=%d%s" % [p.x, p.y, p.z, ex.is_on_floor(), ex.stepped, hit])
		ex.auto_dir = Vector2.ZERO
	quit()
