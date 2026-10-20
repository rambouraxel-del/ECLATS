@tool
class_name VoxelMaterials
extends RefCounted
## Accès aux matériaux de rendu partagés (un seul matériau pour tous les voxels).

const VOXEL_MATERIAL_PATH := "res://materials/voxel_material.tres"

static var _voxel: Material

static func voxel_material() -> Material:
	if _voxel == null:
		_voxel = load(VOXEL_MATERIAL_PATH)
	return _voxel
