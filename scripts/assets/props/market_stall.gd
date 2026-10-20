@tool
extends RefCounted
## Asset 4 — Étal de marchand. 2,40 × 1,60 m, hauteur 2,60 m.
## Inspiré de la planche 2 (Market stall, Canopy kiosk) : poteaux de bois sur blocs de
## pierre, capuchons de cuivre, comptoir sur soubassement de pierre, étagères garnies,
## auvent rayé crème et bleu à franges (pièce de tissu animée), bannières, enseigne
## suspendue, lanterne, paniers de fruits, balance, lierre.

static func build() -> VoxelAsset:
	var asset := VoxelAsset.new("market_stall", "Étal de marchand", Vector3i(12, 13, 8),
			"Kiosque de bois et de pierre : comptoir, étagères, marchandises, auvent de toile.")
	var k := AssetKit.new(Vector3i(120, 118, 80), 404)

	# Poteaux sur blocs de pierre, bagues et capuchons de cuivre.
	var posts := [Vector2i(4, 4), Vector2i(106, 4), Vector2i(4, 64), Vector2i(106, 64)]
	for p in posts:
		k.stone_block(p.x - 2, 0, p.y - 2, p.x + 11, 9, p.y + 11, 5)
		k.post(p.x, p.y, 10, 108, 10, "wood_planks")
		k.copper_collar(p.x, p.y, 10, 12, 10)
		k.copper_collar(p.x, p.y, 96, 98, 10)
		k.copper_cap(p.x, p.y, 109, 10, 3)
	# Poutres hautes et jambes de force.
	k.box(4, 100, 66, 115, 107, 71, "wood_dark")
	k.box(4, 100, 6, 115, 107, 11, "wood_dark")
	k.box(6, 100, 14, 11, 107, 63, "wood_dark")
	k.box(108, 100, 14, 113, 107, 63, "wood_dark")
	for side in [[14.0, 26.0], [105.0, 93.0]]:
		k.line(Vector3(side[0], 86, 68.5), Vector3(side[1], 99, 68.5), 3, "wood_planks")
	k.rivets(Vector3i(10, 103, 72), Vector3i(110, 103, 72), 10, "copper")

	# Comptoir : soubassement de pierre, caisson en planches, plateau qui déborde.
	k.masonry(14, 0, 48, 105, 7, 73, 14, 8, 2)
	k.planks(15, 8, 49, 104, 44, 72, 0, 1, 6)
	k.box(15, 8, 72, 18, 44, 72, "wood_dark")
	k.box(101, 8, 72, 104, 44, 72, "wood_dark")
	k.planks(12, 45, 46, 107, 48, 77, 0, 2, 8)
	k.box(12, 45, 77, 107, 46, 77, "wood_dark")
	for c in [Vector2i(12, 77), Vector2i(107, 77)]:
		k.corner_plate(c.x, c.y, 1 if c.x < 50 else -1, -1, 45, 48, 6)
	# Bannière accrochée à l'avant du comptoir + étoffe crème.
	k.banner(51, 47, 78, 18, 38, 2, 4)
	k.banner(24, 47, 78, 12, 26, 2, 3, "fabric_cream")

	# Marchandises sur le comptoir.
	var y := 49
	_basket(k, 22, y, 54, 18, 14)
	_fruit_pile(k, 22, y + 5, 54, 18, 14, "apple")
	_basket(k, 45, y, 56, 14, 12)
	_fruit_pile(k, 45, y + 5, 56, 14, 12, "leaf_light")
	# Balance de laiton.
	k.box(70, y, 60, 75, y + 1, 65, "brass")
	k.box(72, y + 2, 62, 73, y + 14, 63, "brass")
	k.box(64, y + 15, 62, 81, y + 15, 63, "brass")
	for px in [65, 80]:
		k.line(Vector3(px, y + 14, 62.5), Vector3(px, y + 7, 62.5), 1, "iron_dark")
		k.ellipsoid(Vector3(px + 0.5, y + 6.5, 63), Vector3(3.5, 0.7, 3.5), "brass")
	k.ellipsoid(Vector3(80.5, y + 8, 63), Vector3(1.6, 1.4, 1.6), "crystal_blue")
	# Pièces d'or et registre.
	for i in 3:
		k.box(86 + i * 3, y, 66, 87 + i * 3, y + 1 + i, 67, "gold")
	k.box(90, y, 54, 101, y + 2, 62, "paper")
	k.box(90, y + 3, 54, 101, y + 3, 62, "fabric_wine")
	k.box(90, y, 54, 90, y + 3, 62, "fabric_wine")
	# Pot à épices.
	k.box(15, y, 58, 20, y + 6, 63, "terracotta")
	k.box(16, y + 7, 59, 19, y + 7, 62, "wood_light")

	# Fond : panneau, trois étagères garnies.
	k.planks(14, 10, 6, 105, 98, 7, 1, 0, 8, ["wood_planks", "wood_honey", "wood_dark"])
	for sy in [36, 60, 84]:
		k.planks(14, sy, 8, 105, sy + 2, 24, 0, 2, 6, ["wood_honey", "wood_planks"])
		for x in [16, 58, 102]:
			k.line(Vector3(x, sy - 1, 8.5), Vector3(x, sy - 6, 8.5), 1, "copper")
			k.line(Vector3(x, sy - 1, 8.5), Vector3(x, sy - 1, 13.5), 1, "copper")
	# Étagère 1 : pots de terre cuite (avec plantes) et fioles.
	for i in 3:
		var cx := 22 + i * 13
		_cylinder_y(k, cx, 39, 16, 4.2, 8, "terracotta")
		if i != 1:
			k.bush(Vector3(cx + 0.5, 51, 16.5), Vector3(4.5, 4, 4.5), "flower_white", 0.1)
		else:
			k.box(cx - 3, 47, 13, cx + 3, 48, 19, "potting_soil")
	for i in 6:
		var x := 66 + i * 6
		var key: String = ["glass_green", "potion_violet", "crystal_deep"][i % 3]
		k.box(x, 39, 14, x + 3, 45, 17, key)
		k.box(x + 1, 46, 15, x + 2, 47, 16, "wood_light")
	# Étagère 2 : rouleaux de tissu et pains.
	var fabrics := ["fabric_blue", "fabric_cream", "fabric_wine", "fabric_teal"]
	for i in 4:
		_cylinder_x(k, 18 + i * 12, 29 + i * 12, 67, 15, 3.6, fabrics[i])
	for i in 3:
		k.ellipsoid(Vector3(72 + i * 10, 65, 16), Vector3(4.2, 2.6, 3.2), "bread")
	# Étagère 3 : présentoir d'éclats, coffrets.
	k.stone_block(24, 87, 11, 37, 90, 21, 2, "stone_light")
	k.crystal(Vector3(28, 91, 15), 9.0, 1.8, Vector2(-0.12, 0.0), "crystal_blue")
	k.crystal(Vector3(32, 91, 17), 12.0, 2.2, Vector2(0.05, -0.05), "crystal_blue")
	k.crystal(Vector3(35, 91, 14), 7.0, 1.5, Vector2(0.15, 0.05), "crystal_deep")
	for i in 3:
		var x := 52 + i * 15
		k.planks(x, 87, 11, x + 10, 93, 21, 0, 1, 3, ["wood_dark", "wood_red"], false)
		k.box(x + 4, 91, 22, x + 6, 92, 22, "copper")
	# Sous l'étagère : sacs de grain liés de corde, caisse.
	for i in 3:
		var cx := 24 + i * 14
		k.ellipsoid(Vector3(cx, 7 + 7, 18), Vector3(6, 7.5, 6), "fabric_cream")
		k.box(cx - 2, 21, 17, cx + 2, 22, 19, "rope")
	k.planks(70, 10, 10, 95, 26, 28, 0, 1, 5, ["wood_planks", "wood_honey"])
	k.corner_plate(70, 28, 1, -1, 10, 26, 5)
	k.corner_plate(95, 28, -1, -1, 10, 26, 5)

	# Enseigne suspendue (avant gauche) et lanterne (avant droite).
	for x in [21, 37]:
		k.line(Vector3(x, 99, 70.5), Vector3(x, 91, 70.5), 1, "iron_dark")
	k.planks(17, 76, 70, 41, 90, 71, 0, 1, 5, ["wood_honey", "wood_planks"], false)
	k.box(17, 76, 72, 41, 76, 72, "copper")
	k.box(17, 90, 72, 41, 90, 72, "copper")
	for dy in range(-5, 6):
		var w := 5 - absi(dy)
		k.box(29 - w, 83 + dy, 72, 29 + w, 83 + dy, 72, "brass")
	k.box(28, 82, 73, 30, 84, 73, "crystal_blue")
	k.line(Vector3(98, 99, 68.5), Vector3(98, 92, 68.5), 1, "iron_dark")
	var glow := k.lantern(98, 76, 68, 6, 9)

	# Lierre sur le poteau avant gauche et la poutre, jardinière sur le côté droit.
	k.ivy(Vector3i(3, 107, 70), 70, Vector3i(0, 0, 1), 0.07)
	k.ivy(Vector3i(14, 99, 73), 24, Vector3i(1, 0, 0), 0.05)
	k.ivy(Vector3i(116, 106, 63), 40, Vector3i(0, 0, -1), 0.06)
	k.planks(107, 0, 30, 118, 12, 52, 2, 1, 4, ["wood_dark", "wood_planks"])
	k.box(108, 12, 31, 117, 12, 51, "potting_soil")
	k.bush(Vector3(112.5, 17, 41), Vector3(5, 5, 10), "flower_violet", 0.12)
	asset.add_part("structure", k)

	# Auvent en toile (pièce séparée, matériau de tissu qui ondule doucement).
	var c := AssetKit.new(Vector3i(120, 54, 80), 405)
	for z in 80:
		for x in 120:
			var yc := lerpf(50.0, 40.0, z / 79.0) - 3.0 * sin(PI * x / 119.0) * (0.4 + 0.6 * z / 79.0)
			var band := (x / 15) % 2
			var key := "fabric_cream" if band == 0 else "fabric_blue"
			if x % 15 == 0 or z >= 74:
				key = "fabric_cream" if band == 1 else "fabric_teal"
			var yi := roundi(yc)
			c.set_cell(x, yi, z, key)
			c.set_cell(x, yi - 1, z, key)
			if z == 79:
				# Lambrequin festonné à franges.
				var drop := 7 if (x % 12) < 6 else 5
				for d in drop:
					var fk := key if d < drop - 2 else ("fabric_cream" if x % 2 == 0 else "")
					if fk != "":
						c.set_cell(x, yi - 2 - d, z, fk)
	c.banner(2, 40, 79, 14, 34, 2, 4)
	c.banner(104, 40, 79, 14, 34, 2, 4)
	asset.add_part("canopy", c, Vector3i(0, 66, 0), "cloth")

	asset.add_light(glow, Color("ffb860"), 1.3, 5.0, true)
	asset.add_collider(Vector3i(12, 0, 46), Vector3i(107, 48, 77))
	asset.add_collider(Vector3i(14, 0, 4), Vector3i(105, 98, 24))
	for p in posts:
		asset.add_collider(Vector3i(p.x - 2, 0, p.y - 2), Vector3i(p.x + 11, 108, p.y + 11))
	return asset

static func _cylinder_y(k: AssetKit, cx: int, y0: int, cz: int, r: float, h: int, key: String) -> void:
	for y in range(y0, y0 + h):
		var rr := r - (0.6 if y == y0 else 0.0)
		for z in range(cz - 5, cz + 6):
			for x in range(cx - 5, cx + 6):
				if Vector2(x - cx, z - cz).length() <= rr:
					k.set_cell(x, y, z, key)

static func _cylinder_x(k: AssetKit, x0: int, x1: int, cy: int, cz: int, r: float, key: String) -> void:
	for x in range(x0, x1 + 1):
		for y in range(cy - 4, cy + 5):
			for z in range(cz - 4, cz + 5):
				if Vector2(y - cy, z - cz).length() <= r:
					k.set_cell(x, y, z, key if (x != x0 and x != x1) else "fabric_cream")

static func _basket(k: AssetKit, x0: int, y0: int, z0: int, w: int, d: int) -> void:
	for y in range(y0, y0 + 5):
		var key := "wood_honey" if y % 2 == 0 else "wood_dark"
		k.box(x0, y, z0, x0 + w - 1, y, z0 + d - 1, key)
	k.box(x0 + 1, y0 + 1, z0 + 1, x0 + w - 2, y0 + 4, z0 + d - 2, "")
	k.box(x0 + 1, y0 + 1, z0 + 1, x0 + w - 2, y0 + 2, z0 + d - 2, "wood_dark")

static func _fruit_pile(k: AssetKit, x0: int, y0: int, z0: int, w: int, d: int, key: String) -> void:
	for layer in 2:
		var off := 2 + layer * 2
		var z := z0 + off
		while z < z0 + d - 2:
			var x := x0 + off
			while x < x0 + w - 2:
				k.ellipsoid(Vector3(x + 0.5, y0 - 1 + layer * 3, z + 0.5), Vector3(2.2, 2.0, 2.2), key, true)
				if key == "apple" and k.rng.randf() < 0.3:
					k.set_if_empty(x, y0 + 1 + layer * 3, z, "leaves")
				x += 4
			z += 4
