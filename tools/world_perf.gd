extends SceneTree
## Mesures de performance d'une île générée (à lancer avec un rendu, p. ex. xvfb-run en OpenGL logiciel) :
##   godot --rendering-driver opengl3 -s tools/world_perf.gd -- <profil> <graine> [sortie.json]
## Temps de génération par phase, triangles par catégorie et niveau de détail, nombre de nœuds, mémoire,
## puis appels de dessin / primitives / objets pour quelques vues. NB : sans GPU les durées de rendu ne sont pas
## représentatives ; les comptes (triangles, nœuds, appels de dessin) le sont.
func _tri(mi: MeshInstance3D) -> int:
	if mi.mesh == null:
		return 0
	return VoxelMesher.triangle_count(mi.mesh)

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var mem0 := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_msec()
	var world := WorldBuilder.build(args[0], int(args[1]))
	var gen_ms := Time.get_ticks_msec() - t0
	var env := EnvironmentManager.new()
	root.add_child(env)
	var scene := Node3D.new()
	root.add_child(scene)
	var t1 := Time.get_ticks_msec()
	var refs := WorldView.create(world, scene)
	var view_ms := Time.get_ticks_msec() - t1
	env.setup(world.seed)
	# triangles par catégorie et par niveau de détail
	var cats := {}
	var nodes := {"MeshInstance3D": 0, "MultiMeshInstance3D": 0, "OmniLight3D": 0, "CollisionShape3D": 0}
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		for k in nodes:
			if n.is_class(k):
				nodes[k] += 1
		var cat := ""
		var p := n
		while p != null and p != scene:
			if p.name in ["Island", "Buildings", "Nature", "Plants", "Props", "Pier", "Ship", "Mooring"]:
				cat = String(p.name)
				break
			p = p.get_parent()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var lod := 0 if mi.visibility_range_begin <= 0.0 else (1 if mi.visibility_range_end > 0.0 and mi.visibility_range_begin < 60.0 else 2)
			if not cats.has(cat):
				cats[cat] = [0, 0, 0]
			cats[cat][lod] += _tri(mi)
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			var tri := VoxelMesher.triangle_count(mm.mesh) * mm.instance_count
			if not cats.has("Plants"):
				cats["Plants"] = [0, 0, 0]
			cats["Plants" if cat == "Plants" else cat][0 if (n as MultiMeshInstance3D).visibility_range_begin <= 0.0 else 1] += tri
	var colliders := 0
	for b in world.buildings:
		colliders += b["model"].colliders.size()
	var cam := Camera3D.new()
	cam.far = 2500.0
	cam.fov = 62
	root.add_child(cam)
	cam.current = true
	var s := world.settlement
	var pc: Vector2 = s.plaza["center"]
	var pl_y := float(world.field.ground_y_m(s.plaza["col"].x, s.plaza["col"].y))
	var views := {
		"aerial": [Vector3(pc.x + 8, 40, pc.y + 54), Vector3(pc.x, 2, pc.y)],
		"plaza": [Vector3(pc.x - 6, pl_y + 3.0, pc.y + 9), Vector3(pc.x + 1, pl_y + 1.5, pc.y - 2)],
		"far": [Vector3(pc.x + 90, 40, pc.y + 150), Vector3(pc.x, 0, pc.y)],
	}
	var frames := {}
	for k in views:
		cam.global_position = views[k][0]
		cam.look_at(views[k][1])
		for i in 4:
			await process_frame
		frames[k] = {
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		}
	var report := {
		"profile": args[0], "seed": int(args[1]), "generation_ms": gen_ms, "timings_ms": world.timings, "scene_build_ms": view_ms,
		"triangles_by_category_lod": cats, "nodes": nodes, "collider_boxes_buildings": colliders,
		"counts": {"buildings": world.buildings.size(), "trees": world.trees.size(), "rocks": world.rocks.size(), "props": world.props.size(), "plant_instances": int(world.stats.get("plants", 0))},
		"memory_mb": {"static_before": snappedf(mem0 / 1048576.0, 0.1), "static_after": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1), "peak": snappedf(OS.get_static_memory_peak_usage() / 1048576.0, 0.1)},
		"frames": frames, "mesh_cache": {"hits": MeshCache.hits, "misses": MeshCache.misses},
	}
	print(JSON.stringify(report, "\t"))
	if args.size() > 2:
		var f := FileAccess.open(args[2], FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "\t"))
	quit()
