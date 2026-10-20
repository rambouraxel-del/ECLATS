@tool
class_name VoxelModelInstance
extends Node3D
## Affiche un modèle de la bibliothèque (VoxelModelLibrary).
## L'origine du nœud = coin minimum de l'emprise, au sol. Placer le nœud sur la grille
## de 0,20 m pour qu'il s'aligne exactement sur le terrain.

@export_enum("block_stone", "block_dirt", "block_grass", "block_wood", "wall", "slab",
		"stairs", "table", "workbench", "shard_lamp") var model_key := "block_stone":
	set(v):
		model_key = v
		if is_inside_tree():
			rebuild()

static var _mesh_cache := {}

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.queue_free()
	var model := VoxelModelLibrary.get_model(model_key)
	if model.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.set_meta("generated", true)
	mi.mesh = _mesh_for(model)
	add_child(mi)
	if model.has("light"):
		var l: Dictionary = model["light"]
		var light := OmniLight3D.new()
		light.set_meta("generated", true)
		light.position = l["position"]
		light.light_color = l["color"]
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.shadow_enabled = true
		add_child(light)

func _mesh_for(model: Dictionary) -> ArrayMesh:
	var grid: float = model["grid"]
	if model["world_tint"]:
		# Bloc posé : teinte calculée à sa position dans la grille monde (comme le terrain).
		var cell := VoxelGrid.world_to_cell(global_position + Vector3.ONE * grid * 0.5)
		return VoxelMesher.build(model["volume"], grid, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), cell)
	if not _mesh_cache.has(model["key"]):
		_mesh_cache[model["key"]] = VoxelMesher.build(model["volume"], grid)
	return _mesh_cache[model["key"]]
