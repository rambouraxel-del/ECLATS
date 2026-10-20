@tool
class_name VoxelMaterials
extends RefCounted
## Accès aux matériaux de rendu partagés. Un matériau par usage, jamais un par objet :
##   terrain (style STYLIZED) · props (style DETAIL : objets, bâtiments) · tissus animés ·
##   cristaux animés · Lot 1 (LEGACY) · nuages.

const VOXEL_MATERIAL_PATH := "res://materials/voxel_material.tres"           # Lot 1
const TERRAIN_MATERIAL_PATH := "res://materials/voxel_stylized_material.tres"  # terrain
const PROPS_MATERIAL_PATH := "res://materials/voxel_props_material.tres"      # objets, bâtiments
const CLOTH_MATERIAL_PATH := "res://materials/voxel_cloth_material.tres"      # tissus animés
const CRYSTAL_MATERIAL_PATH := "res://materials/voxel_crystal_material.tres"  # cristaux animés

static var _cache := {}

static func _load_cached(path: String) -> Material:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

static func voxel_material() -> Material:
	return _load_cached(VOXEL_MATERIAL_PATH)

static func stylized_material() -> Material:
	return _load_cached(TERRAIN_MATERIAL_PATH)

static func props_material() -> Material:
	return _load_cached(PROPS_MATERIAL_PATH)

static func cloth_material() -> Material:
	return _load_cached(CLOTH_MATERIAL_PATH)

static func crystal_material() -> Material:
	return _load_cached(CRYSTAL_MATERIAL_PATH)

static func material_for(style: int) -> Material:
	match style:
		VoxelMesher.Style.LEGACY: return voxel_material()
		VoxelMesher.Style.DETAIL: return props_material()
	return stylized_material()

## Matériaux qui partagent le shader stylisé (pour piloter les paramètres globaux :
## intensité des lampes, activation des textures, etc.).
static func shared_materials() -> Array[Material]:
	return [stylized_material(), props_material(), cloth_material(), crystal_material()]

## Règle un paramètre de shader sur tous les matériaux voxel.
static func set_global_param(param: String, value: Variant) -> void:
	for m in shared_materials():
		(m as ShaderMaterial).set_shader_parameter(param, value)
