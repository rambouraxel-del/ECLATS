@tool
class_name BuildingView
extends RefCounted
## BuildingModel → nœuds Godot : un MeshInstance3D pour la structure, un par tronçon de toiture, un par
## détail (aucun nœud par voxel) ; niveaux de détail pour la structure ; lumières regroupées dans le
## groupe « asset_lamps » (réglées par l'ambiance). Les maillages sont construits à la demande.

const C := VoxelGrid.STRUCTURE_SIZE

## Tableaux de sommets (pur, sans nœud : peut tourner dans un thread).
static func make_arrays(model: BuildingModel) -> Dictionary:
	var out := {"structure": [], "lod1": [], "lod2": [], "details": []}
	out["structure"] = VoxelMesher.build_arrays(model.volume, C, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	var s1 := model.volume.downsample(2, 0.3)
	out["lod1"] = VoxelMesher.build_arrays(s1, C * 2.0, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	var s2 := model.volume.downsample(4, 0.35)
	out["lod2"] = VoxelMesher.build_arrays(s2, C * 4.0, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	var det := []
	for d in model.details:
		det.append(VoxelMesher.build_arrays(d["volume"], float(d["grid"]), Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL))
	out["details"] = det
	return out

static func _mat_for(name: String) -> Material:
	match name:
		"crystal": return VoxelMaterials.crystal_material()
		"cloth": return VoxelMaterials.cloth_material()
	return VoxelMaterials.props_material()

## Construit le nœud (appelé sur le thread principal). lod_ranges : distances de bascule (m).
static func create_node(model: BuildingModel, arrays: Dictionary, lod_ranges := [26.0, 70.0]) -> Node3D:
	var root := Node3D.new()
	root.name = "Building_%s" % model.plan.type
	var s := _mesh_instance("Structure", arrays["structure"], VoxelMaterials.props_material())
	if s != null:
		s.visibility_range_end = lod_ranges[0]
		root.add_child(s)
	var s1 := _mesh_instance("Structure_LOD1", arrays["lod1"], VoxelMaterials.props_material())
	if s1 != null:
		s1.visibility_range_begin = lod_ranges[0]
		s1.visibility_range_end = lod_ranges[1]
		s1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(s1)
	var s2 := _mesh_instance("Structure_LOD2", arrays["lod2"], VoxelMaterials.props_material())
	if s2 != null:
		s2.visibility_range_begin = lod_ranges[1]
		s2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(s2)
	for r in model.roofs:
		var mi := _mesh_instance(r["name"], r["arrays"], VoxelMaterials.props_material())
		if mi != null:
			mi.position = r["offset"]
			root.add_child(mi)
	for i in model.details.size():
		var d: Dictionary = model.details[i]
		var mi := _mesh_instance(d["name"], arrays["details"][i], _mat_for(d["material"]))
		if mi != null:
			mi.position = d["offset"]
			mi.visibility_range_end = lod_ranges[0] * 0.8
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	for l in model.lights:
		var light := OmniLight3D.new()
		light.position = l["pos"]
		light.light_color = l["color"]
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 24.0
		light.distance_fade_length = 10.0
		light.add_to_group("asset_lamps")
		light.set_meta("interior", l["interior"])
		root.add_child(light)
	return root

static func _mesh_instance(name: String, arrays: Array, material: Material) -> MeshInstance3D:
	var mesh := VoxelMesher.arrays_to_mesh(arrays, VoxelMesher.Style.DETAIL)
	if mesh == null:
		return null
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	return mi
