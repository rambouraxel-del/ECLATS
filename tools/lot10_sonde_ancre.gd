extends SceneTree
## Sonde : approche du cristal de l'Ancre à pied (marches de la plateforme).
##   godot --headless --fixed-fps 60 -s tools/lot10_sonde_ancre.gd
func _initialize() -> void:
	var scene: Node = (load("res://scenes/game/opening_island.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	while not bool(scene.get("ready_to_play")):
		await process_frame
		OS.delay_msec(5)
	var ex: Explorer = scene.get("explorer")
	var a: Vector3 = scene.get("info")["anchor"]["pos"]
	print("[sonde] ancre ", a)
	for n in scene.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs.shape is BoxShape3D:
			var c := cs.global_position
			if Vector2(c.x, c.z).distance_to(Vector2(a.x, a.z)) < 5.0:
				var sz := (cs.shape as BoxShape3D).size
				print("[sonde] ", cs.get_path(), " parent ", cs.get_parent().get_class(), " ", cs.get_parent().name, " groupe ", cs.get_parent().get_parent().name if cs.get_parent().get_parent() else "", " boîte centre ", c, " taille ", sz, " x ", snappedf(c.x - sz.x * 0.5, 0.01), "→", snappedf(c.x + sz.x * 0.5, 0.01), " y ", snappedf(c.y - sz.y * 0.5, 0.01), "→", snappedf(c.y + sz.y * 0.5, 0.01))
	for p in [[24.0, -77.5], [24.0, -76.2], [24.0, -79.0]]:
		var g: float = scene.call("ground_y_at", p[0], p[1])
		ex.teleport(Vector3(p[0], g + 0.1, p[1]), PI * 0.5)
		for i in 20:
			await physics_frame
		ex.auto_active = true
		ex.auto_dir = Vector2(-1, 0)
		for t in 240:
			await physics_frame
			if t % 30 == 0:
				print("[sonde] départ ", p, " t=", t, " x=%.2f y=%.3f z=%.2f" % [ex.global_position.x, ex.global_position.y, ex.global_position.z], " sol ", snappedf(float(scene.call("ground_y_at", ex.global_position.x, ex.global_position.z)), 0.01), " marches ", ex.stepped)
		ex.auto_dir = Vector2.ZERO
	quit()
