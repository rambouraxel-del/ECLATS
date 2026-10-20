@tool
extends RefCounted
## Technologie et ruines des Ancres (planche 1) : plateforme de téléportation, amas de cristaux,
## colonne brisée, arche en ruine.

static func build(args: Dictionary) -> VoxelAsset:
	match String(args["id"]):
		"teleport_anchor": return _teleporter()
		"crystal_cluster": return _cluster()
		"ruin_column": return _column()
		"ruin_arch": return _arch()
	return null

# ------------------------------------------------------------------ plateforme de téléportation
## Disque de pierre claire à gradins, quatre piliers à lanterne d'éclat, glyphe hexagonal incrusté
## (pièce en microvoxels de 2 cm). Le piédestal d'Ancre se pose au centre.
static func _teleporter() -> VoxelAsset:
	var a := VoxelAsset.new("teleport_anchor", "Plateforme d'Ancre", Vector3i(26, 6, 26), "Disque de pierre à glyphes lumineux et quatre piliers à éclat : point de téléportation.")
	a.cell_m = 0.1
	a.lod_factors = [2, 4]
	var k := AssetKit.new(Vector3i(52, 14, 52), 741)
	var c := 26.0
	# Gradins concentriques, secteurs de pierre alternés.
	var rings := [[25.5, 0, 2, "stone_carved"], [23.0, 3, 3, "stone_light"], [20.0, 4, 4, "stone_carved"]]
	for rg in rings:
		for y in range(rg[1], rg[1] + 2):
			for z in 52:
				for x in 52:
					var d := Vector2(x + 0.5 - c, z + 0.5 - c).length()
					if d <= rg[0]:
						var ang := atan2(z + 0.5 - c, x + 0.5 - c) + PI
						var sector := int(ang / TAU * 24.0)
						var key := "stone_light" if sector % 2 == 0 else "stone_carved"
						if int(d * 3.0) % 7 == 0 and y == rg[1]:
							key = "stone_shade"
						k.volume.set_voxel(x, y, z, k.mat(key))
	k.cyl_y(c, c, 5, 6, 17.0, "stone_light")
	k.cyl_y(c, c, 7, 7, 17.0, "stone_carved", 14.0)
	k.cyl_y(c, c, 7, 7, 14.0, "stone_shade", 13.0)
	# Quatre piliers à lanterne d'éclat.
	var lights: Array[Vector3] = []
	for i in 4:
		var ang := PI / 4.0 + i * PI / 2.0
		var px := int(c + cos(ang) * 21.0) - 2
		var pz := int(c + sin(ang) * 21.0) - 2
		k.stone_block(px - 1, 8, pz - 1, px + 4, 10, pz + 4, 1, "stone_carved")
		k.stone_block(px, 11, pz, px + 3, 24, pz + 3, 1, "stone_light")
		k.box(px + 1, 15, pz - 1, px + 2, 21, pz - 1, "crystal_blue")
		k.box(px + 1, 15, pz + 4, px + 2, 21, pz + 4, "crystal_blue")
		k.box(px - 1, 15, pz + 1, px - 1, 21, pz + 2, "crystal_blue")
		k.box(px + 4, 15, pz + 1, px + 4, 21, pz + 2, "crystal_blue")
		for yy in [14, 22]:
			k.box(px - 1, yy, pz - 1, px + 4, yy + 1, pz + 4, "copper")
		k.box(px, 25, pz, px + 3, 26, pz + 3, "stone_carved")
		k.box(px + 1, 27, pz + 1, px + 2, 28, pz + 2, "copper")
		lights.append(Vector3(px + 2, 18, pz + 2))
	k.moss_top(0, 0, 51, 51, 0.1, 13)
	for i in 6:
		var ang := k.rng.randf() * TAU
		k.bush(Vector3(c + cos(ang) * 24.0, 5, c + sin(ang) * 24.0), Vector3(4, 3, 4), "flower_white", 0.3)
	a.add_part("structure", k)
	# Glyphe : disque de pierre sombre + hexagone et étoile lumineux, pixels de 2 cm.
	var g := AssetKit.new(Vector3i(170, 3, 170), 742)
	var gc := 85.0
	g.cyl_y(gc, gc, 0, 0, 84.0, "stone_shade")
	g.cyl_y(gc, gc, 0, 0, 80.0, "stone_carved")
	for z in 170:
		for x in 170:
			var p := Vector2(x + 0.5 - gc, z + 0.5 - gc)
			var l := p.length()
			if l > 80.0:
				continue
			var ang := fposmod(atan2(p.y, p.x), TAU / 6.0) - TAU / 12.0
			var hex := l * cos(ang)
			var on := false
			on = on or (absf(hex - 66.0) < 1.7)                         # hexagone extérieur
			on = on or (absf(hex - 40.0) < 1.4)                         # hexagone intérieur
			on = on or (l < 9.0 and l > 6.0)                            # anneau central
			var a2 := fposmod(atan2(p.y, p.x), TAU / 6.0)
			on = on or (l > 9.0 and l < 66.0 and (a2 < 0.025 + 0.4 / l or a2 > TAU / 6.0 - 0.025 - 0.4 / l))  # rayons
			if on:
				g.volume.set_voxel(x, 1, z, g.mat("crystal_blue"))
			elif l > 76.0 and l < 79.0 and int(l * 5.0 + atan2(p.y, p.x) * 20.0) % 3 == 0:
				g.volume.set_voxel(x, 1, z, g.mat("copper"))
	# Pose : le glyphe repose sur le disque central (y = 8 cellules de 10 cm).
	a.add_part("glyph", g, Vector3i(int((26.0 * 0.1 - 85.0 * 0.02) / 0.02), 40, int((26.0 * 0.1 - 85.0 * 0.02) / 0.02)), "crystal", "", 0.02)
	a.add_light(Vector3(26, 20, 26), Color("6cc8ff"), 1.4, 7.0)
	for l in lights:
		a.add_light(l, Color("7fd2ff"), 0.5, 3.5)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(51, 8, 51))
	a.lod_ranges = [16.0, 44.0, 0.0]
	return a

# ------------------------------------------------------------------ amas de cristaux
static func _cluster() -> VoxelAsset:
	var a := VoxelAsset.new("crystal_cluster", "Amas de cristaux", Vector3i(7, 9, 7), "Éboulis de pierre claire et mousse portant un amas de cristaux bleus.")
	var k := AssetKit.new(Vector3i(70, 90, 70), 743)
	var blocks := [[4, 0, 6, 30, 16, 36], [26, 0, 30, 50, 12, 58], [34, 0, 4, 62, 20, 30], [8, 0, 38, 28, 10, 62], [44, 0, 38, 66, 15, 64]]
	for b in blocks:
		k.stone_block(b[0], b[1], b[2], b[3], b[4], b[5], 6)
	k.stone_block(16, 17, 12, 34, 26, 30, 4)
	k.stone_block(36, 21, 8, 56, 30, 24, 4)
	# Croûte de cuivre natif orangé entre les cristaux.
	k.stone_block(24, 14, 22, 44, 24, 42, 3, "stone_shade")
	for i in 14:
		k.line(Vector3(28 + k.rng.randf() * 16, 20, 26 + k.rng.randf() * 14), Vector3(28 + k.rng.randf() * 16, 24 + k.rng.randf() * 8, 26 + k.rng.randf() * 14), 2, "copper")
	k.crystal(Vector3(34, 22, 32), 62.0, 8.5, Vector2(0.05, -0.04), "crystal_blue", 0.34)
	k.crystal(Vector3(24, 18, 40), 36.0, 5.5, Vector2(-0.25, 0.12), "crystal_cyan", 0.4)
	k.crystal(Vector3(46, 18, 24), 44.0, 6.0, Vector2(0.2, -0.1), "crystal_deep", 0.4)
	k.crystal(Vector3(16, 12, 20), 24.0, 4.0, Vector2(-0.3, -0.2), "crystal_blue", 0.4)
	k.crystal(Vector3(54, 16, 46), 28.0, 4.5, Vector2(0.25, 0.2), "crystal_ice", 0.4)
	k.crystal(Vector3(40, 12, 52), 18.0, 3.4, Vector2(0.1, 0.3), "crystal_cyan", 0.45)
	k.moss_top(0, 0, 69, 69, 0.5, 23)
	k.bush(Vector3(10, 14, 52), Vector3(8, 5, 7), "flower_white", 0.2)
	k.bush(Vector3(60, 16, 8), Vector3(7, 4, 6), "", 0.0)
	k.ivy(Vector3i(24, 26, 14), 18, Vector3i(1, 0, 0), 0.08)
	a.add_part("structure", k)
	a.add_light(Vector3(34, 40, 34), Color("7fd2ff"), 0.9, 4.0)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(69, 30, 69))
	a.lod_ranges = [14.0, 40.0, 0.0]
	return a

# ------------------------------------------------------------------ colonne brisée
static func _column() -> VoxelAsset:
	var a := VoxelAsset.new("ruin_column", "Colonne en ruine", Vector3i(5, 14, 5), "Colonne cannelée cassée sur un socle, tambour tombé, lierre.")
	var k := AssetKit.new(Vector3i(50, 140, 50), 744)
	k.stone_block(2, 0, 2, 47, 9, 47, 6)
	k.stone_block(6, 10, 6, 43, 16, 43, 5, "stone_carved")
	# Fût : tambours octogonaux cannelés, cassé en pointe.
	var top := 92 + k.rng.randi_range(0, 12)
	for y in range(17, top):
		var r := 15.5 - float(y - 17) * 0.012
		for z in range(25 - 17, 25 + 18):
			for x in range(25 - 17, 25 + 18):
				var d := Vector2(x + 0.5 - 25.0, z + 0.5 - 25.0)
				var ang := atan2(d.y, d.x)
				var flute := 0.9 * absf(sin(ang * 8.0))
				if d.length() <= r - flute:
					# Cassure irrégulière à mi-hauteur côté est.
					var broken := y > top - 22 and d.x > 3.0 and y > top - 22 + int((d.y + 20.0) * 0.45)
					if not broken:
						var seg := (y - 17) / 11
						var key := "stone_light" if (seg % 2 == 0) else "stone_carved"
						if (y - 17) % 11 == 0:
							key = "stone_shade"
						k.volume.set_voxel(x, y, z, k.mat(key))
	# Tambour tombé au pied et gravats.
	for y in 11:
		k.cyl_y(38, 43, y + 1, y + 1, 10.5 - absf(y - 5) * 0.2, "stone_light" if y % 3 else "stone_carved")
	k.stone_block(0, 0, 38, 14, 5, 48, 3)
	k.stone_block(40, 0, 0, 49, 4, 9, 3)
	k.moss_top(0, 0, 49, 49, 0.35, 29)
	k.ivy(Vector3i(20, top - 3, 20), top - 14, Vector3i(1, 0, 1), 0.07)
	k.ivy(Vector3i(30, top - 10, 30), top - 24, Vector3i(-1, 0, 0), 0.05)
	k.bush(Vector3(8, 12, 12), Vector3(7, 6, 6), "flower_white", 0.22)
	a.add_part("structure", k)
	a.add_collider(Vector3i(2, 0, 2), Vector3i(47, top, 47))
	a.lod_ranges = [12.0, 34.0, 0.0]
	return a

# ------------------------------------------------------------------ arche en ruine
static func _arch() -> VoxelAsset:
	var a := VoxelAsset.new("ruin_arch", "Arche en ruine", Vector3i(16, 15, 4), "Fragment d'arche de pierre claire, clé de voûte de cuivre, bannière et lanterne.")
	var k := AssetKit.new(Vector3i(160, 150, 40), 745)
	# Piliers.
	k.masonry(0, 0, 4, 29, 82, 35, 16, 9, 4)
	k.masonry(130, 0, 4, 159, 58, 35, 16, 9, 4)       # pilier droit cassé plus bas
	k.stone_block(0, 0, 0, 33, 7, 39, 4, "stone_carved")
	k.stone_block(126, 0, 0, 159, 7, 39, 4, "stone_carved")
	# Voûte : voussoirs sur un demi-cercle (plan XY), épaisseur en z.
	var cx := 79.5
	var cy := 82.0
	var r_in := 50.0
	var r_out := 63.0
	for y in range(80, 150):
		for x in range(0, 160):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy)
			var l := d.length()
			if l < r_in or l > r_out or d.y < -2.0:
				continue
			var ang := atan2(d.y, d.x)                     # 0 = droite, PI/2 = haut
			var sector := int(ang / PI * 11.0)
			# Partie droite écroulée au-delà d'un certain angle.
			if ang < 0.62:
				continue
			var key := "stone_light" if sector % 2 == 0 else "stone_carved"
			var joint := fposmod(ang / PI * 11.0, 1.0) < 0.05
			for z in range(5, 35):
				k.volume.set_voxel(x, y, z, k.mat("stone_shade" if joint else key))
	# Clé de voûte de cuivre, bannière, lanterne.
	k.box(76, 140, 3, 83, 152 - 4, 36, "copper")
	k.banner(56, 134, 2, 20, 56, 2, 5)
	var glow := k.lantern(112, 56, 20, 7, 11)
	k.line(Vector3(112.5, 82, 20.5), Vector3(112.5, 128, 20.5), 1, "iron_dark")
	# Décombres, lierre, mousse.
	k.stone_block(108, 0, 10, 126, 8, 30, 4)
	k.stone_block(96, 0, 22, 108, 5, 34, 3)
	k.moss_top(0, 0, 159, 39, 0.4, 31)
	k.ivy(Vector3i(10, 82, 4), 60, Vector3i(1, 0, 0), 0.08)
	k.ivy(Vector3i(140, 58, 5), 46, Vector3i(-1, 0, 0), 0.06)
	k.ivy(Vector3i(40, 126, 5), 30, Vector3i(1, 0, 0), 0.06)
	k.bush(Vector3(12, 6, 36), Vector3(9, 6, 5), "flower_white", 0.2)
	a.add_part("structure", k)
	a.add_light(glow, Color("ffb860"), 0.9, 4.0)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(33, 85, 39))
	a.add_collider(Vector3i(126, 0, 0), Vector3i(159, 60, 39))
	a.lod_ranges = [14.0, 40.0, 0.0]
	return a
