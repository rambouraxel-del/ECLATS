@tool
class_name VoxelObjectView
extends RefCounted
## Objets voxel à plusieurs volumes (arbres : bois + feuillage ; rochers ; bateau) → nœuds avec niveaux de
## détail. Chaque volume devient 3 maillages (pleine finesse, 2× plus grossier, 4× plus grossier) affichés
## selon la distance ; jamais de nœud par voxel.

static func _arrays(vol: VoxelVolume, grid: float) -> Array:
	return VoxelMesher.build_arrays(vol, grid, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)

## parts : [{volume, origin(Vector3 m), grid(float), material("props"|"cloth"|"crystal")}]
## Renvoie une liste (une entrée par partie) de 3 tableaux de sommets. Sans nœud : peut tourner dans un thread.
static func make_arrays(parts: Array) -> Array:
	var out: Array = []
	for p in parts:
		var vol: VoxelVolume = p["volume"]
		var g: float = p["grid"]
		var lods: Array = [_arrays(vol, g)]
		if vol.size.x * vol.size.y * vol.size.z > 4096:
			lods.append(_arrays(vol.downsample(2, 0.3), g * 2.0))
			lods.append(_arrays(vol.downsample(4, 0.35), g * 4.0))
		else:
			lods.append(lods[0])
			lods.append(lods[0])
		out.append(lods)
	return out

static func _material(name: String) -> Material:
	match name:
		"crystal": return VoxelMaterials.crystal_material()
		"cloth": return VoxelMaterials.cloth_material()
	return VoxelMaterials.props_material()

static func create_node(node_name: String, parts: Array, arrays: Array, ranges := [32.0, 90.0], shadows_far := false) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	for i in parts.size():
		var p: Dictionary = parts[i]
		var lods: Array = arrays[i]
		for li in 3:
			if li > 0 and lods[li] == lods[0]:
				continue
			var mesh := VoxelMesher.arrays_to_mesh(lods[li], VoxelMesher.Style.DETAIL)
			if mesh == null:
				continue
			mesh.surface_set_material(0, _material(p.get("material", "props")))
			var mi := MeshInstance3D.new()
			mi.name = "%s_L%d" % [p.get("name", "part"), li]
			mi.mesh = mesh
			mi.position = p["origin"]
			if li == 0:
				mi.visibility_range_end = ranges[0]
			elif li == 1:
				mi.visibility_range_begin = ranges[0]
				mi.visibility_range_end = ranges[1]
			else:
				mi.visibility_range_begin = ranges[1]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows_far else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	return root
