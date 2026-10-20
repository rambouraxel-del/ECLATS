@tool
class_name PlaceableAsset
extends Node3D
## Racine d'un asset prêt à poser. Préparé pour le futur système de placement :
## l'origine est le coin minimum de l'emprise, au sol ; l'emprise est donnée en cellules
## de la grille de construction (20 cm). Rotation prévue par pas de 90° autour de Y.

@export var asset_id := ""
@export var display_name := ""
## Emprise en cellules de 20 cm (x, hauteur, z).
@export var footprint_cells := Vector3i.ONE
## Statistiques de génération (lecture seule, renseignées par tools/bake_assets.gd).
@export var triangle_count := 0
@export var vertex_count := 0

func footprint_size_m() -> Vector3:
	return Vector3(footprint_cells) * VoxelGrid.VOXEL_SIZE

## Cellules de la grille occupées si l'asset est posé avec son origine en `origin_cell`.
func occupied_cells(origin_cell: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for y in footprint_cells.y:
		for z in footprint_cells.z:
			for x in footprint_cells.x:
				out.append(origin_cell + Vector3i(x, y, z))
	return out
