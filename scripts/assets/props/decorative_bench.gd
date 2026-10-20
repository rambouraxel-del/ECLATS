@tool
extends RefCounted
## Asset 5 — Banc décoratif. 1,80 × 0,60 m, assise à 0,50 m, dossier à 0,96 m.
## Inspiré des planches 2 et 5 (Village bench, Bench) : pieds en pierre claire à deux
## assises, assise en planches à chant arrondi, traverses à tenons chevillés, équerres
## de cuivre, dossier à deux lisses et fronton, couverture bleue drapée, lierre et fleurs.

static func build() -> VoxelAsset:
	var asset := VoxelAsset.new("decorative_bench", "Banc décoratif", Vector3i(9, 5, 3),
			"Banc de bois sur pieds de pierre, ferrures de cuivre, couverture et lierre.")
	var k := AssetKit.new(Vector3i(90, 50, 30), 505)
	var seat_y := 25  # dessus de l'assise (0,52 m)

	# Pieds de pierre : large semelle puis bloc plus étroit (profil en gradin).
	for x0 in [4, 70]:
		k.stone_block(x0 - 2, 0, 0, x0 + 17, 6, 29, 6)
		k.stone_block(x0 + 1, 7, 3, x0 + 14, 18, 26, 5)
		k.box(x0 + 3, 9, 3, x0 + 12, 16, 3, "stone_shade")   # cartouche creusé
		k.box(x0 + 4, 10, 3, x0 + 11, 15, 3, "")
		k.box(x0 + 3, 9, 26, x0 + 12, 16, 26, "stone_shade")
		k.box(x0 + 4, 10, 26, x0 + 11, 15, 26, "")
		# Capuchons de cuivre aux angles du bloc.
		for c in [Vector2i(x0 + 1, 3), Vector2i(x0 + 11, 3), Vector2i(x0 + 1, 23), Vector2i(x0 + 11, 23)]:
			k.box(c.x, 16, c.y, c.x + 3, 19, c.y + 3, "copper")
			k.set_cell(c.x + 1, 18, c.y if c.y < 10 else c.y + 3, "iron_dark")
		# Traverse de bois qui traverse le pied : tenons apparents + chevilles.
		k.box(x0 + 3, 19, 0, x0 + 12, 20, 29, "wood_dark")
		for z in [0, 29]:
			k.set_cell(x0 + 5, 20, z, "wood_light")
			k.set_cell(x0 + 10, 20, z, "wood_light")

	# Assise : cinq lames, chant avant arrondi, lames de teintes variées.
	k.planks(0, 21, 2, 89, seat_y, 25, 0, 2, 5)
	k.box(0, seat_y, 2, 89, seat_y, 2, "")
	k.box(0, 21, 2, 89, 21, 2, "")
	# Équerres de cuivre entre assise et pieds.
	for x in [6, 19, 72, 85]:
		k.box(x, 21, 1, x + 1, seat_y, 1, "copper")
		k.set_cell(x, 23, 0, "iron_dark")

	# Dossier : montants, deux lisses, fronton sculpté.
	for x in [7, 80]:
		k.post(x, 24, seat_y + 1, 44, 5, "wood_dark")
		k.copper_cap(x, 24, 45, 5, 2)
	k.planks(7, 29, 25, 84, 34, 27, 0, 1, 6, ["wood_planks", "wood_honey"], false)
	k.planks(7, 36, 25, 84, 41, 27, 0, 1, 6, ["wood_honey", "wood_planks"], false)
	k.box(5, 42, 24, 86, 44, 28, "wood_dark")
	# Fronton : arc doux et losange de laiton au centre.
	for x in range(34, 57):
		var h := int(round(2.0 * sin(PI * (x - 34) / 22.0)))
		if h > 0:
			k.box(x, 45, 25, x, 44 + h, 27, "wood_dark")
	for dy in range(-3, 4):
		var w := 3 - absi(dy)
		k.box(45 - w, 46 + dy + 1, 28, 45 + w, 46 + dy + 1, 28, "brass")
	k.set_cell(45, 47, 29, "crystal_warm")

	# Couverture bleue : posée sur la lisse haute, retombe sur l'assise et pend devant.
	k.drape(12, 16, [Vector2i(45, 28), Vector2i(45, 23), Vector2i(26, 23), Vector2i(26, 1), Vector2i(12, 1)], 3)

	# Végétation : lierre sur le pied droit, touffe fleurie au pied gauche, mousse.
	k.ivy(Vector3i(88, 24, 20), 22, Vector3i(0, 0, -1), 0.1)
	k.ivy(Vector3i(86, 18, 28), 16, Vector3i(-1, 0, 0), 0.08)
	k.bush(Vector3(2.5, 5, 26), Vector3(3, 4, 3), "flower_white", 0.3)
	k.moss_top(0, 0, 22, 29, 0.4, 11)
	k.moss_top(66, 0, 89, 29, 0.4, 12)

	# Modélisé dossier vers +z : on retourne pour que l'avant de l'asset soit côté +z.
	k.mirror_z()
	asset.add_part("structure", k)
	asset.add_collider(Vector3i(0, 0, 0), Vector3i(89, seat_y, 29))
	asset.add_collider(Vector3i(5, seat_y, 0), Vector3i(86, 47, 5))
	return asset
