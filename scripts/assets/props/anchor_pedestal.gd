@tool
extends RefCounted
## Asset 3 — Piédestal d'Ancre. 1,60 × 1,60 m, cristal flottant à environ 1,75 m.
## Technologie ancienne d'ÉCLATS : socle octogonal à gradins en pierre claire, sillons de
## runes lumineuses, fût cannelé cerclé de cuivre, bannière à l'ancre, chapiteau à dalle
## runique, griffes de cuivre qui retiennent un éclat bleu en lévitation, éclats en orbite,
## petites lanternes de pierre aux angles. Inspiré de la planche 1 (Anchor pedestal,
## Teleport marker, Carved pedestal, Crystal cluster).

const ANCHOR := [
	"....###....",
	"...#...#...",
	"....###....",
	".#########.",
	".....#.....",
	".....#.....",
	".....#.....",
	".....#.....",
	".....#.....",
	"#....#....#",
	"##...#...##",
	".##..#..##.",
	"..#######..",
	"....###....",
]

static func build() -> VoxelAsset:
	var asset := VoxelAsset.new("anchor_pedestal", "Piédestal d'Ancre", Vector3i(8, 12, 8),
			"Socle ancien de pierre claire et de cuivre maintenant un éclat d'Ancre en lévitation.")
	var k := AssetKit.new(Vector3i(80, 92, 80), 303)

	# Gradins octogonaux en maçonnerie.
	k.masonry(0, 0, 0, 79, 9, 79, 16, 10, 3)
	k.cut_corners(0, 0, 0, 79, 9, 79, 14)
	k.masonry(8, 10, 8, 71, 17, 71, 14, 8, 3)
	k.cut_corners(8, 10, 8, 71, 17, 71, 12)
	# Sillon runique lumineux incrusté dans le second gradin.
	for z in range(8, 72):
		for x in range(8, 72):
			var dx := mini(x - 8, 71 - x)
			var dz := mini(z - 8, 71 - z)
			var d := mini(mini(dx, dz), dx + dz - 12)
			if d == 4 and k.volume.get_voxel(x, 17, z) != 0:
				k.set_cell(x, 17, z, "crystal_blue")
	for c in [Vector2i(40, 12), Vector2i(40, 67), Vector2i(12, 40), Vector2i(67, 40)]:
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if absi(dx) + absi(dz) == 2:
					k.set_cell(c.x + dx, 17, c.y + dz, "crystal_blue")
	# Plaques de cuivre rivetées sur le premier gradin.
	for c in [Vector2i(38, 79), Vector2i(38, 0)]:
		k.box(c.x - 3, 3, c.y, c.x + 6, 7, c.y, "copper")
		k.set_cell(c.x - 2, 5, c.y, "iron_dark")
		k.set_cell(c.x + 5, 5, c.y, "iron_dark")
	for c in [Vector2i(0, 38), Vector2i(79, 38)]:
		k.box(c.x, 3, c.y - 3, c.x, 7, c.y + 6, "copper")

	# Fût octogonal cannelé.
	k.box(26, 18, 26, 53, 62, 53, "stone_light")
	k.cut_corners(26, 18, 26, 53, 62, 53, 7)
	for i in 4:
		var p := 31 + i * 6
		k.box(p, 25, 26, p, 53, 26, "")
		k.box(p, 25, 53, p, 53, 53, "")
		k.box(26, 25, p, 26, 53, p, "")
		k.box(53, 25, p, 53, 53, p, "")
	for y in range(18, 63, 9):
		k.box(26, y, 26, 53, y, 53, "stone_carved")
		k.cut_corners(26, y, 26, 53, y, 53, 7)
	k.band_ring(26, 18, 26, 53, 21, 53, "copper")
	k.band_ring(26, 57, 26, 53, 60, 53, "copper")
	k.rivets(Vector3i(30, 19, 54), Vector3i(50, 19, 54), 5)
	k.rivets(Vector3i(30, 58, 54), Vector3i(50, 58, 54), 5)

	# Bannière à l'ancre sur la face avant.
	k.banner(31, 56, 54, 18, 34, 2, 4)
	k.box(34, 51, 54, 45, 30, 54, "fabric_blue")
	k.glyph(ANCHOR, 34, 49, 54, "fabric_cream")
	k.box(30, 56, 54, 49, 57, 55, "copper")  # tringle

	# Chapiteau à deux gradins + dalle runique.
	k.box(20, 63, 20, 59, 66, 59, "stone_carved")
	k.cut_corners(20, 63, 20, 59, 66, 59, 9)
	k.box(23, 67, 23, 56, 70, 56, "stone_light")
	k.cut_corners(23, 67, 23, 56, 70, 56, 8)
	k.band_ring(20, 66, 20, 59, 66, 59, "copper")
	k.box(33, 70, 33, 46, 70, 46, "copper")
	for z in range(34, 46):
		for x in range(34, 46):
			var d := absi(x * 2 - 79) + absi(z * 2 - 79)
			if d <= 22 and (d >= 16 or d <= 4):
				k.set_cell(x, 70, z, "crystal_blue")

	# Griffes de cuivre qui enserrent l'éclat.
	for c: Vector2 in [Vector2(27, 27), Vector2(52, 27), Vector2(27, 52), Vector2(52, 52)]:
		var out := (c - Vector2(39.5, 39.5)).normalized()
		var p0 := Vector3(c.x, 71, c.y)
		var p1 := Vector3(c.x + out.x * 4, 79, c.y + out.y * 4)
		var p2 := Vector3(c.x + out.x * 2, 86, c.y + out.y * 2)
		var p3 := Vector3(c.x - out.x * 3, 90, c.y - out.y * 3)
		k.line(p0, p1, 2, "copper")
		k.line(p1, p2, 2, "copper")
		k.line(p2, p3, 1, "brass")
		k.set_cell(int(p3.x), int(p3.y), int(p3.z), "crystal_deep")

	# Petites lanternes de pierre aux angles du premier gradin.
	for c in [Vector2i(9, 9), Vector2i(64, 9), Vector2i(9, 64), Vector2i(64, 64)]:
		k.stone_block(c.x, 10, c.y, c.x + 6, 30, c.y + 6, 3, "stone_light")
		k.box(c.x + 2, 22, c.y - 1, c.x + 4, 27, c.y + 7, "crystal_blue")
		k.box(c.x - 1, 22, c.y + 2, c.x + 7, 27, c.y + 4, "crystal_blue")
		k.copper_cap(c.x, c.y, 31, 7, 2)

	# Gravats, mousse, buissons et lierre.
	k.stone_block(1, 0, 1, 5, 3, 5, 2)
	k.stone_block(74, 0, 2, 78, 2, 6, 2)
	k.stone_block(2, 0, 73, 7, 4, 77, 2)
	k.moss_top(0, 0, 79, 79, 0.16, 21)
	k.bush(Vector3(16, 21, 70), Vector3(6, 4, 4), "flower_white", 0.12)
	k.bush(Vector3(70, 21, 24), Vector3(4, 4, 6), "flower_white", 0.12)
	k.bush(Vector3(6, 12, 40), Vector3(4, 3, 7), "", 0.0)
	k.ivy(Vector3i(56, 62, 50), 30, Vector3i(1, 0, 0), 0.08)
	k.ivy(Vector3i(23, 66, 30), 26, Vector3i(-1, 0, 0), 0.05)
	asset.add_part("structure", k)

	# Éclat d'Ancre flottant (pièce animée), deux tons de facettes.
	var cr := AssetKit.new(Vector3i(24, 48, 24), 304)
	cr.crystal(Vector3(12, 2, 12), 43.0, 7.5, Vector2.ZERO, "crystal_blue", 0.35)
	for y in cr.volume.size.y:
		for z in cr.volume.size.z:
			for x in cr.volume.size.x:
				if cr.volume.get_voxel(x, y, z) != 0 and (x - 12) + (z - 12) > 3:
					cr.set_cell(x, y, z, "crystal_deep")
	asset.add_part("anchor_crystal", cr, Vector3i(28, 72, 28), "crystal", "float")

	# Éclats en orbite.
	var orb := AssetKit.new(Vector3i(80, 24, 80), 305)
	for i in 5:
		var a := TAU * i / 5.0
		var r := 25.0 + (i % 2) * 6.0
		orb.crystal(Vector3(40 + cos(a) * r, 2 + (i * 7) % 12, 40 + sin(a) * r), 8.0 + (i % 3) * 2.0, 1.6,
				Vector2(cos(a) * 0.1, sin(a) * 0.1), "crystal_blue" if i % 2 == 0 else "crystal_deep", 0.45)
	asset.add_part("orbiting_shards", orb, Vector3i(0, 74, 0), "crystal", "orbit")

	asset.add_light(Vector3(40, 96, 40), Color("6cc8ff"), 2.4, 7.0)
	asset.add_light(Vector3(40, 22, 40), Color("6cc8ff"), 0.6, 2.5)
	asset.add_collider(Vector3i(0, 0, 0), Vector3i(79, 17, 79))
	asset.add_collider(Vector3i(20, 18, 20), Vector3i(59, 70, 59))
	return asset
