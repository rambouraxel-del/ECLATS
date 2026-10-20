@tool
class_name VoxelMaterials
extends RefCounted
## Accès aux matériaux de rendu partagés (un seul matériau pour tous les voxels d'un style).

const VOXEL_MATERIAL_PATH := "res://materials/voxel_material.tres"           # Lot 1
const STYLIZED_MATERIAL_PATH := "res://materials/voxel_stylized_material.tres"  # Lot 2
const CLOTH_MATERIAL_PATH := "res://materials/voxel_cloth_material.tres"      # tissus animés

static var _cache := {}

static func _load_cached(path: String) -> Material:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

static func voxel_material() -> Material:
	return _load_cached(VOXEL_MATERIAL_PATH)

static func stylized_material() -> Material:
	return _load_cached(STYLIZED_MATERIAL_PATH)

static func cloth_material() -> Material:
	return _load_cached(CLOTH_MATERIAL_PATH)

static func material_for(style: int) -> Material:
	return voxel_material() if style == VoxelMesher.Style.LEGACY else stylized_material()
