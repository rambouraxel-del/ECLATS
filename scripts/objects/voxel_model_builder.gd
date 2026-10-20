@tool
class_name VoxelModelBuilder
extends RefCounted
## Petit outil de modélisation voxel par code (boîtes, lignes, ellipsoïdes).
## Les coordonnées sont en cellules de la grille du modèle (0,05 m pour les détails).

var volume: VoxelVolume
var palette: VoxelPalette

func _init(size: Vector3i) -> void:
	volume = VoxelVolume.new(size)
	palette = VoxelPalette.get_default()

func mat(key: String) -> int:
	return palette.id(key) if key != "" else 0

func set_cell(x: int, y: int, z: int, key: String) -> void:
	volume.set_voxel(x, y, z, mat(key))

## Boîte pleine, bornes incluses. key = "" pour creuser.
func box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, key: String) -> void:
	volume.fill_box(Vector3i(mini(x0, x1), mini(y0, y1), mini(z0, z1)),
			Vector3i(maxi(x0, x1), maxi(y0, y1), maxi(z0, z1)), mat(key))

## Segment épais entre deux points (centres de cellules).
func line(a: Vector3, b: Vector3, thickness: int, key: String) -> void:
	var id := mat(key)
	var steps := int(ceil(a.distance_to(b) * 2.0)) + 1
	var lo := -(thickness - 1) / 2
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		for dx in range(lo, lo + thickness):
			for dy in range(lo, lo + thickness):
				for dz in range(lo, lo + thickness):
					volume.set_voxel(c.x + dx, c.y + dy, c.z + dz, id)

## Ellipsoïde plein. only_empty = true : ne remplit que les cellules vides.
func ellipsoid(center: Vector3, radii: Vector3, key: String, only_empty := false) -> void:
	var id := mat(key)
	for y in range(floori(center.y - radii.y), ceili(center.y + radii.y) + 1):
		for z in range(floori(center.z - radii.z), ceili(center.z + radii.z) + 1):
			for x in range(floori(center.x - radii.x), ceili(center.x + radii.x) + 1):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - center) / radii
				if d.length_squared() <= 1.0:
					if only_empty and volume.get_voxel(x, y, z) != 0:
						continue
					volume.set_voxel(x, y, z, id)

## Remplace une matière par une autre selon une probabilité déterministe.
func speckle(from_key: String, to_key: String, rate: float, seed: int) -> void:
	var a := mat(from_key)
	var b := mat(to_key)
	for y in volume.size.y:
		for z in volume.size.z:
			for x in volume.size.x:
				if volume.get_voxel(x, y, z) == a and VoxelGrid.hash01(x, y, z, seed) < rate:
					volume.set_voxel(x, y, z, b)
