@tool
class_name BuildingModel
extends RefCounted
## Bâtiment généré : volume de structure (10 cm), toitures (maillages extrudés), détails (2 cm),
## colliders simplifiés, lumières, et description de l'intérieur pour le mobilier et la validation.
## Repère local : coin minimum du volume = origine ; x est, z sud, y haut ; unité : mètre.

const C := VoxelGrid.STRUCTURE_SIZE

var plan: BuildingPlan
var volume: VoxelVolume                 # structure, cellules de 10 cm
var roofs: Array[Dictionary] = []       # {arrays, offset(Vector3 m), material}
var details: Array[Dictionary] = []     # {name, volume, grid, offset(Vector3 m), material}
var colliders: Array[AABB] = []         # volumes durs simplifiés (murs, planchers, marches, foyer)
var lights: Array[Dictionary] = []      # {pos(m), color, energy, range, interior}
var rooms: Array[Dictionary] = []       # {id, role, floor, rect (Rect2, m), floor_y (m), obstacles: [Rect2]}
var door_clear: Array[Dictionary] = []  # zones de dégagement devant les portes : {floor, rect (Rect2 m)}
var ground_y_cells := BuildingPlan.GY
var checks := {}                        # indicateurs de conception (portes, marches, hauteurs sous plafond)

func size_m() -> Vector3:
	return Vector3(volume.size) * C

func footprint_m() -> Vector2:
	return Vector2(plan.footprint) * C

## Centre-bas de l'emprise (repère local), pour PlacementSpec.
func center_bottom() -> Vector3:
	return Vector3(plan.footprint.x * C * 0.5, 0.0, plan.footprint.y * C * 0.5)

## Hauteur du sol fini d'un niveau (m, depuis le bas du volume).
func floor_y_m(f: int) -> float:
	return float(plan.floor_y(f)) * C

func door_front_m() -> Vector2:
	return Vector2(plan.door_front) * C
