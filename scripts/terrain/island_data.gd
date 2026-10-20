@tool
class_name IslandData
extends RefCounted
## Résultat de la génération d'une île.
## Deux couches logiques de même taille :
##   core    : cœur fixe, NON destructible (roche profonde, sous-face, falaises basses).
##   surface : couche superficielle MODIFIABLE (les SURFACE_DEPTH premiers voxels sous le sol).
## Une cellule appartient à une seule couche. Les deux sont maillées séparément, chacune
## cachant ses faces contre l'autre : modifier la surface ne touche jamais le cœur.

var seed := 0
var core: VoxelVolume
var surface: VoxelVolume
## Position monde (en cellules) de la cellule (0,0,0) des volumes.
var origin_cell := Vector3i.ZERO
## Occupation combinée cœur + surface (1 = plein), utilisée pour cacher les faces internes.
var solid: PackedByteArray
## Hauteur du sol (index y dans les volumes) par colonne, -1 si vide. Index = x + z * size.x
var top: PackedInt32Array
## Matière du sol par colonne (0 si vide).
var top_material: PackedByteArray

func size() -> Vector3i:
	return core.size

func get_voxel(x: int, y: int, z: int) -> int:
	var v := surface.get_voxel(x, y, z)
	return v if v != 0 else core.get_voxel(x, y, z)

func is_core(x: int, y: int, z: int) -> bool:
	return core.get_voxel(x, y, z) != 0

## Modification de la couche superficielle (préparation des futurs outils).
## Refuse toute modification d'une cellule du cœur. Renvoie true si la cellule a changé.
func set_surface_voxel(x: int, y: int, z: int, material_id: int) -> bool:
	if is_core(x, y, z) or not surface.is_inside(x, y, z):
		return false
	surface.set_voxel(x, y, z, material_id)
	solid[surface.index_of(x, y, z)] = 1 if material_id != 0 else 0
	return true

func column_top(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= core.size.x or z >= core.size.z:
		return -1
	return top[x + z * core.size.x]

func checksum() -> String:
	return core.checksum() + surface.checksum()
