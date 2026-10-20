@tool
class_name VoxelGrid
extends RefCounted
## Système de coordonnées commun à tout le projet.
## 1 unité Godot = 1 mètre. Le terrain et les blocs posés partagent la grille
## principale (VOXEL_SIZE) ; les objets fins utilisent la grille de détail.

const VOXEL_SIZE := 0.2
## Microvoxels des objets détaillés (Lot 2) : 2 cm, soit 10 par voxel de terrain.
const DETAIL_SIZE := 0.02
const DETAILS_PER_VOXEL := 10  # VOXEL_SIZE / DETAIL_SIZE
## Ancienne grille de détail du Lot 1 (5 cm), conservée pour les objets de référence du Lot 1.
const LEGACY_DETAIL_SIZE := 0.05

## Cellule de la grille principale qui contient le point `p` (en mètres).
static func world_to_cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / VOXEL_SIZE), floori(p.y / VOXEL_SIZE), floori(p.z / VOXEL_SIZE))

## Coin minimum (en mètres) d'une cellule.
static func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c) * VOXEL_SIZE

## Centre (en mètres) d'une cellule.
static func cell_center(c: Vector3i) -> Vector3:
	return (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * VOXEL_SIZE

## Aligne un point sur la grille principale (coin de cellule le plus proche).
static func snap(p: Vector3) -> Vector3:
	return (p / VOXEL_SIZE).round() * VOXEL_SIZE

## Bruit déterministe [0, 1] pour une cellule entière (variation de teinte, décor).
static func hash01(x: int, y: int, z: int, seed: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 2654435761)
	h &= 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	h = ((h ^ (h >> 12)) * 0x297A2D39) & 0xFFFFFFFF
	h ^= h >> 15
	return float(h & 0xFFFFFF) / float(0xFFFFFF)
