extends SceneTree
## Génère les assets détaillés (voxels → maillages optimisés → scènes Godot).
##   godot --headless -s tools/bake_assets.gd            (tous les assets)
##   godot --headless -s tools/bake_assets.gd -- market_stall
## Produit pour chaque asset : assets/props/<id>/<id>.tscn + un maillage .res par pièce,
## et le rapport assets/props/assets_report.json (sommets, triangles, temps, poids).

func _initialize() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = AssetLibrary.ids()
	VoxelMesher.palette_warmup()
	var report := {}
	var report_path := AssetLibrary.ASSET_DIR + "/assets_report.json"
	if FileAccess.file_exists(report_path):
		var old = JSON.parse_string(FileAccess.get_file_as_string(report_path))
		if typeof(old) == TYPE_DICTIONARY:
			report = old
	for id in ids:
		report[id] = bake(id)
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t", false))
	f.close()
	quit()

static func bake(id: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var asset := AssetLibrary.build(id)
	var t_build := Time.get_ticks_msec() - t0
	var dir := "%s/%s" % [AssetLibrary.ASSET_DIR, id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	root.set_script(load("res://scripts/assets/placeable_asset.gd"))
	root.set("asset_id", id)
	root.set("display_name", asset.display_name)
	root.set("footprint_cells", asset.footprint)
	var verts := 0
	var tris := 0
	var solid := 0
	var bytes := 0
	var parts_info := []
	for part in asset.parts:
		var vol: VoxelVolume = part["volume"]
		solid += vol.count_solid()
		var arrays := VoxelMesher.build_arrays(vol, part["grid"])
		if arrays.is_empty():
			continue
		var node_pos: Vector3 = part["offset"]
		if part["material"] == "cloth":
			# Le haut du tissu doit être en y = 0 (le shader fait balancer ce qui pend dessous).
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var top := -INF
			for v in pv:
				top = maxf(top, v.y)
			for i in pv.size():
				pv[i].y -= top
			arrays[Mesh.ARRAY_VERTEX] = pv
			node_pos.y += top
		var mesh := VoxelMesher.arrays_to_mesh(arrays)
		match part["material"]:
			"cloth": mesh.surface_set_material(0, VoxelMaterials.cloth_material())
			"crystal": mesh.surface_set_material(0, load("res://materials/voxel_crystal_material.tres"))
		var mesh_path := "%s/%s_%s.res" % [dir, id, part["name"]]
		ResourceSaver.save(mesh, mesh_path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH)
		var mi := MeshInstance3D.new()
		mi.name = String(part["name"]).to_pascal_case()
		mi.mesh = load(mesh_path)  # référence externe (le .tscn reste léger)
		mi.position = node_pos
		if part["animation"] != "":
			mi.set_script(load("res://scripts/assets/floating_part.gd"))
			mi.set("mode", part["animation"])
			mi.set("pivot", Vector3(vol.size) * float(part["grid"]) * 0.5)
		root.add_child(mi)
		var v := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var t := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		verts += v
		tris += t
		var size := FileAccess.get_file_as_bytes(mesh_path).size()
		bytes += size
		parts_info.append({"name": part["name"], "vertices": v, "triangles": t, "file_kb": size / 1024})
	for i in asset.lights.size():
		var l: Dictionary = asset.lights[i]
		var light := OmniLight3D.new()
		light.name = "Light%d" % (i + 1)
		light.position = l["position"]
		light.light_color = l["color"]
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.shadow_enabled = l["shadow"]
		root.add_child(light)
	if not asset.colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "Collision"
		root.add_child(body)
		for i in asset.colliders.size():
			var box: AABB = asset.colliders[i]
			var shape := CollisionShape3D.new()
			shape.name = "Box%d" % (i + 1)
			var bs := BoxShape3D.new()
			bs.size = box.size
			shape.shape = bs
			shape.position = box.get_center()
			body.add_child(shape)
	root.set("triangle_count", tris)
	root.set("vertex_count", verts)
	_set_owner(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, AssetLibrary.scene_path(id))
	root.free()
	var info := {
		"name": asset.display_name, "size_m": [asset.size_m().x, asset.size_m().y, asset.size_m().z],
		"vertices": verts, "triangles": tris, "solid_microvoxels": solid,
		"mesh_kb": bytes / 1024, "build_ms": t_build, "total_ms": Time.get_ticks_msec() - t0,
		"parts": parts_info,
	}
	print("%-18s %6d sommets %6d triangles %8d microvoxels %5d Ko  %d ms" % [id, verts, tris, solid, bytes / 1024, info["total_ms"]])
	return info

static func _set_owner(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_set_owner(c, owner)
