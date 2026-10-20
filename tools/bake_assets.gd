extends SceneTree
## Génère les assets (voxels → maillages optimisés avec niveaux de détail → scènes Godot).
##   godot --headless -s tools/bake_assets.gd                 (tous les assets)
##   godot --headless -s tools/bake_assets.gd -- market_stall (un seul)
##   godot --headless -s tools/bake_assets.gd -- group:prop   (un groupe : lot2, prop, building, tree, vehicle)
## Produit pour chaque asset : assets/props/<id>/<id>.tscn, un .res par pièce et par niveau de
## détail, <id>.info.json (utilisé par PropScatter) et met à jour assets/props/assets_report.json.

const LOD_THRESHOLDS := {2: 0.25, 3: 0.2, 4: 0.18, 5: 0.16}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var ids: Array = []
	if args.is_empty():
		ids = Array(AssetLibrary.all_ids())
	for a in args:
		if a.begins_with("group:"):
			ids.append_array(Array(AssetLibrary.ids_in(a.substr(6))))
		else:
			ids.append(a)
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

static func _tri_count(arrays: Array) -> int:
	return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if not arrays.is_empty() else 0

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
	var ranges: Array = asset.lod_ranges
	var tri_lod := [0, 0, 0]
	var vert0 := 0
	var solid := 0
	var bytes := 0
	var parts_info := []
	var detail_style := VoxelMesher.Style.DETAIL
	for part in asset.parts:
		var vol: VoxelVolume = part["volume"]
		var grid: float = part["grid"]
		solid += vol.count_solid()
		var arrays0 := VoxelMesher.build_arrays(vol, grid, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, detail_style)
		if arrays0.is_empty():
			continue
		var node_pos: Vector3 = part["offset"]
		var top := 0.0
		if part["material"] == "cloth":
			# Le haut du tissu doit être en y = 0 (le shader fait balancer ce qui pend dessous).
			var pv: PackedVector3Array = arrays0[Mesh.ARRAY_VERTEX]
			top = -INF
			for v in pv:
				top = maxf(top, v.y)
			node_pos.y += top
		var animated: bool = part["animation"] != ""
		var lods := [arrays0]
		var lod_grids := [grid]
		if not animated and asset.lod_factors.size() > 0:
			for li in asset.lod_factors.size():
				var f: int = asset.lod_factors[li]
				if f <= 1:
					continue
				var small := vol.downsample(f, LOD_THRESHOLDS.get(f, 0.2))
				var arr := VoxelMesher.build_arrays(small, grid * f, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, detail_style)
				# Pas de gain réel : on garde le niveau précédent.
				if arr.is_empty() or _tri_count(arr) > _tri_count(lods[lods.size() - 1]) * 0.8:
					break
				lods.append(arr)
				lod_grids.append(grid * f)
		var part_name := String(part["name"])
		var mesh_paths := []
		var tris := []
		for li in lods.size():
			var arrays: Array = lods[li]
			if top != 0.0:
				var pv2: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in pv2.size():
					pv2[i].y -= top
				arrays[Mesh.ARRAY_VERTEX] = pv2
			var mesh := VoxelMesher.arrays_to_mesh(arrays, detail_style)
			match part["material"]:
				"cloth": mesh.surface_set_material(0, VoxelMaterials.cloth_material())
				"crystal": mesh.surface_set_material(0, VoxelMaterials.crystal_material())
			var suffix := "" if li == 0 else "_lod%d" % li
			var mesh_path := "%s/%s_%s%s.res" % [dir, id, part_name, suffix]
			ResourceSaver.save(mesh, mesh_path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH)
			bytes += FileAccess.get_file_as_bytes(mesh_path).size()
			mesh_paths.append(mesh_path)
			var t := _tri_count(arrays)
			tris.append(t)
			tri_lod[li] += t
			if li == 0:
				vert0 += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var mi := MeshInstance3D.new()
			mi.name = part_name.to_pascal_case() + ("" if li == 0 else "_LOD%d" % li)
			mi.mesh = load(mesh_path)
			mi.position = node_pos
			if animated:
				mi.set_script(load("res://scripts/assets/floating_part.gd"))
				mi.set("mode", part["animation"])
				mi.set("pivot", Vector3(vol.size) * grid * 0.5)
			elif lods.size() > 1:
				mi.visibility_range_begin = 0.0 if li == 0 else float(ranges[li - 1])
				mi.visibility_range_end = float(ranges[li]) if li < lods.size() - 1 else float(ranges[lods.size() - 1])
			if li > 0:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if li == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		parts_info.append({"name": part_name, "offset": [node_pos.x, node_pos.y, node_pos.z],
				"animation": part["animation"], "material": part["material"],
				"meshes": mesh_paths, "triangles": tris, "grid": grid})
	var lights_info := []
	for i in asset.lights.size():
		var l: Dictionary = asset.lights[i]
		var light := OmniLight3D.new()
		light.name = "Light%d" % (i + 1)
		light.position = l["position"]
		light.light_color = l["color"]
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.shadow_enabled = l["shadow"]
		light.distance_fade_enabled = true
		light.distance_fade_begin = 28.0
		light.distance_fade_shadow = 14.0
		light.distance_fade_length = 10.0
		light.add_to_group("asset_lamps")
		root.add_child(light)
		lights_info.append({"position": [l["position"].x, l["position"].y, l["position"].z],
				"color": l["color"].to_html(false), "energy": l["energy"], "range": l["range"], "shadow": l["shadow"]})
	var colliders_info := []
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
			colliders_info.append({"position": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z]})
	root.set("triangle_count", tri_lod[0])
	root.set("vertex_count", vert0)
	_set_owner(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, AssetLibrary.scene_path(id))
	root.free()
	var info := {
		"id": id, "name": asset.display_name, "group": asset.category,
		"footprint_cells": [asset.footprint.x, asset.footprint.y, asset.footprint.z],
		"size_m": [asset.size_m().x, asset.size_m().y, asset.size_m().z],
		"lod_ranges": ranges, "instanceable": asset.is_instanceable(), "ground_y": asset.ground_y,
		"vertices": vert0, "triangles": tri_lod[0], "triangles_lod": tri_lod,
		"solid_voxels": solid, "mesh_kb": bytes / 1024, "build_ms": t_build, "total_ms": Time.get_ticks_msec() - t0,
		"parts": parts_info, "lights": lights_info, "colliders": colliders_info,
	}
	var f := FileAccess.open(AssetLibrary.info_path(id), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t", false))
	f.close()
	print("%-20s LOD0 %6d tri · LOD1 %6d · LOD2 %6d · %8d voxels · %5d Ko · %d ms" % [id, tri_lod[0], tri_lod[1], tri_lod[2], solid, bytes / 1024, info["total_ms"]])
	var report := info.duplicate()
	report.erase("parts")
	report.erase("lights")
	report.erase("colliders")
	return report

static func _set_owner(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_set_owner(c, owner)
