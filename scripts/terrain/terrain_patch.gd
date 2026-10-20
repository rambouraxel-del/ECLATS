@tool
class_name TerrainPatch
extends RefCounted
## Portion de terrain rectangulaire (herbe / terre / pierre, paliers), même logique de
## matières que l'île. Sert au laboratoire : diorama des assets et comparaison des rendus.
## Les zones `flat` (Rect2i en cellules) sont aplanies à la hauteur `flat_height`.

static func generate(size_x: int, size_z: int, seed: int, base_height := 4, relief := 4,
		flat: Array[Rect2i] = [], flat_height := 4) -> VoxelVolume:
	var pal := VoxelPalette.get_default()
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.06
	var nm := FastNoiseLite.new()
	nm.seed = seed + 1
	nm.frequency = 0.08
	var max_h := base_height + relief + 2
	var vol := VoxelVolume.new(Vector3i(size_x, max_h + 1, size_z))
	for z in size_z:
		for x in size_x:
			var h := base_height + relief * (n.get_noise_2d(x, z) * 0.5 + 0.5)
			h = IslandGenerator._terrace(h, 2.0)
			var top := clampi(roundi(h), 1, max_h)
			# Bords : léger affaissement pour une silhouette naturelle.
			var edge := mini(mini(x, size_x - 1 - x), mini(z, size_z - 1 - z))
			if edge < 2:
				top = maxi(1, top - (2 - edge))
			for r in flat:
				if r.has_point(Vector2i(x, z)):
					top = flat_height
			var m := nm.get_noise_2d(x, z)
			var top_key := "grass_lush" if m > 0.3 else ("grass_dry" if m < -0.35 else "grass")
			for y in top + 1:
				var d := top - y
				var key := top_key if d == 0 else ("dirt" if d <= 2 else "stone")
				vol.set_voxel(x, y, z, pal.id(key))
	return vol

## Hauteur (en cellules, première cellule vide) de la colonne (x, z).
static func surface_height(vol: VoxelVolume, x: int, z: int) -> int:
	for y in range(vol.size.y - 1, -1, -1):
		if vol.get_voxel(x, y, z) != 0:
			return y + 1
	return 0
