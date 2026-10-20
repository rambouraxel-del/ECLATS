@tool
extends RefCounted
## Rochers et éboulis en voxels de 10 cm : blocs de roche chaude ou grise, mousse sur le dessus,
## quelques cailloux. args = {seed, size, warm}

const C := VoxelGrid.STRUCTURE_SIZE

static func build(args: Dictionary) -> VoxelAsset:
	var seed: int = args.get("seed", 1)
	var n: int = args.get("size", 18)
	var warm: bool = args.get("warm", true)
	var k := AssetKit.new(Vector3i(n * 2 + 4, n + 6, n * 2 + 4), seed * 17 + 3)
	var key := "rock_warm" if warm else "rock_grey"
	var alt := "rock_grey" if warm else "rock_warm"
	var cx := n + 2.0
	# Bloc principal et deux voisins, bords irréguliers.
	for i in 3:
		var r := n * (0.62 if i == 0 else 0.4) * k.rng.randf_range(0.85, 1.15)
		var p := Vector3(cx + (0 if i == 0 else k.rng.randf_range(-0.8, 0.8) * n * 0.8), r * 0.55, cx + (0 if i == 0 else k.rng.randf_range(-0.8, 0.8) * n * 0.8))
		for y in range(0, int(r * 1.3) + 2):
			for z in range(int(p.z - r) - 1, int(p.z + r) + 2):
				for x in range(int(p.x - r) - 1, int(p.x + r) + 2):
					var d := Vector3((x + 0.5 - p.x) / r, (y + 0.5 - p.y) / (r * 0.7), (z + 0.5 - p.z) / r)
					var l := d.length() + (VoxelGrid.hash01(x, y, z, seed) - 0.5) * 0.35
					if l <= 1.0:
						var kk := alt if VoxelGrid.hash01(x / 2, y / 2, z / 2, 5) < 0.18 else key
						k.set_if_empty(x, y, z, kk)
	k.moss_top(0, 0, n * 2 + 3, n * 2 + 3, 0.5, seed)
	var a := VoxelAsset.new("", "Rocher", Vector3i((n * 2 + 4) / 2, (n + 6) / 2 + 1, (n * 2 + 4) / 2))
	a.cell_m = C
	a.lod_factors = [2, 4]
	a.lod_ranges = [16.0, 45.0, 0.0]
	a.add_part("rock", k)
	a.add_collider(Vector3i(int(cx - n * 0.5), 0, int(cx - n * 0.5)), Vector3i(int(cx + n * 0.5), int(n * 0.6), int(cx + n * 0.5)))
	return a
