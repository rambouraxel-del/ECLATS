@tool
class_name VoxelAsset
extends RefCounted
## Description d'un asset, indépendante du moteur de scène : pièces en voxels, lumières,
## volumes de collision, emprise sur la grille et réglages de niveaux de détail.
## tools/bake_assets.gd la transforme en scène Godot (assets/props/<id>/<id>.tscn).

var id := ""
var display_name := ""
var description := ""
var category := "prop"
## Emprise en cellules de 20 cm (x, hauteur arrondie au-dessus, z). L'origine de l'asset
## est le coin minimum de l'emprise, posé au sol : il s'aligne sur la grille du terrain.
var footprint := Vector3i.ONE
## Taille d'une cellule des pièces par défaut : 2 cm (objets), 10 cm (bâtiments, arbres).
## Hauteur (m) du niveau du sol DANS le volume : l'asset se pose avec y = sol - ground_y
## (embarcadère dont les pilotis descendent sous le tablier, par exemple).
var ground_y := 0.0
var cell_m := VoxelGrid.DETAIL_SIZE
## Niveaux de détail : facteurs de sous-échantillonnage des LOD1 et LOD2 (0 = pas de LOD).
var lod_factors := [2, 5]
## Distances (m) : fin du LOD0, fin du LOD1, fin du LOD2 (0 = visible jusqu'au bout).
var lod_ranges := [14.0, 40.0, 0.0]
## Pièces : { name, volume, grid, offset (m), material ("props" | "cloth" | "crystal"),
##            animation ("" | "float" | "orbit" | "bob") }
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

## Instanciable en MultiMesh : ni lumière ni pièce animée.
func is_instanceable() -> bool:
	if not lights.is_empty():
		return false
	for part in parts:
		if part["animation"] != "":
			return false
	return true

## Ajoute une pièce. offset_cells = position du coin de la pièce en cellules de `grid`.
func add_part(part_name: String, kit: VoxelModelBuilder, offset_cells := Vector3i.ZERO,
		material := "props", animation := "", grid := -1.0) -> void:
	var g := cell_m if grid < 0.0 else grid
	parts.append({
		"name": part_name, "volume": kit.volume, "grid": g,
		"offset": Vector3(offset_cells) * g,
		"material": "props" if material == "stylized" else material, "animation": animation,
	})

## Lumière placée en cellules de `cell_m` (repère de l'asset).
func add_light(pos_cells: Vector3, color: Color, energy: float, light_range: float, shadow := false) -> void:
	lights.append({"position": pos_cells * cell_m, "color": color,
		"energy": energy, "range": light_range, "shadow": shadow})

## Boîte de collision en cellules de `cell_m` (bornes incluses).
func add_collider(a: Vector3i, b: Vector3i) -> void:
	var lo := Vector3(a) * cell_m
	colliders.append(AABB(lo, Vector3(b - a + Vector3i.ONE) * cell_m))
