@tool
class_name VoxelAsset
extends RefCounted
## Description d'un asset détaillé, indépendante du moteur de scène :
## pièces en microvoxels, lumières, volumes de collision et emprise sur la grille.
## tools/bake_assets.gd la transforme en scène Godot (assets/props/<id>/<id>.tscn).

var id := ""
var display_name := ""
var description := ""
## Emprise en cellules de 20 cm (x, hauteur arrondie au-dessus, z). L'origine de l'asset
## est le coin minimum de l'emprise, posé au sol : il s'aligne sur la grille du terrain.
var footprint := Vector3i.ONE
## Pièces : { name, volume, grid, offset (m), material ("stylized" | "cloth" | "crystal"),
##            animation ("" | "float" | "orbit") }
var parts: Array[Dictionary] = []
## Lumières : { position (m), color, energy, range, shadow }
var lights: Array[Dictionary] = []
## Collisions simplifiées (boîtes en mètres, repère de l'asset).
var colliders: Array[AABB] = []

func _init(p_id: String, p_name: String, p_footprint: Vector3i, p_description := "") -> void:
	id = p_id
	display_name = p_name
	footprint = p_footprint
	description = p_description

func size_m() -> Vector3:
	return Vector3(footprint) * VoxelGrid.VOXEL_SIZE

## Ajoute une pièce. offset_cells = position du coin de la pièce, en cellules de 2 cm.
func add_part(part_name: String, kit: VoxelModelBuilder, offset_cells := Vector3i.ZERO,
		material := "stylized", animation := "") -> void:
	parts.append({
		"name": part_name, "volume": kit.volume, "grid": VoxelGrid.DETAIL_SIZE,
		"offset": Vector3(offset_cells) * VoxelGrid.DETAIL_SIZE,
		"material": material, "animation": animation,
	})

## Lumière placée en cellules de 2 cm (repère de l'asset).
func add_light(pos_cells: Vector3, color: Color, energy: float, light_range: float, shadow := false) -> void:
	lights.append({"position": pos_cells * VoxelGrid.DETAIL_SIZE, "color": color,
		"energy": energy, "range": light_range, "shadow": shadow})

## Boîte de collision en cellules de 2 cm (bornes incluses).
func add_collider(a: Vector3i, b: Vector3i) -> void:
	var lo := Vector3(a) * VoxelGrid.DETAIL_SIZE
	colliders.append(AABB(lo, Vector3(b - a + Vector3i.ONE) * VoxelGrid.DETAIL_SIZE))
