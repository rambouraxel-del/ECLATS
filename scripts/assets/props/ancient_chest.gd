@tool
extends RefCounted
## Asset 2 — Coffre ancien. 1,20 × 0,80 m, hauteur 0,80 m.
## Inspiré des planches 1, 4 et 5 (Relic chest, Supply chest, Storage chest) : caisse en
## planches, piliers d'angle en pierre claire, couvercle bombé à gradins, bandes de cuivre
## rivetées, serrure ouvragée sertie d'un éclat, poignées de fer, étoffe bleue drapée,
## lierre et mousse.

static func build() -> VoxelAsset:
	var asset := VoxelAsset.new("ancient_chest", "Coffre ancien", Vector3i(6, 4, 4),
			"Coffre de bois travaillé, ferrures de cuivre, serrure à éclat et piliers de pierre.")
	var k := AssetKit.new(Vector3i(60, 40, 40), 202)

	# Socle : traverse de bois sombre posée sur quatre pieds de pierre.
	for c in [Vector2i(1, 1), Vector2i(49, 1), Vector2i(1, 29), Vector2i(49, 29)]:
		k.stone_block(c.x, 0, c.y, c.x + 9, 4, c.y + 9, 4)
	k.box(3, 4, 3, 56, 6, 36, "wood_dark")

	# Caisse : planches horizontales sur les quatre faces.
	k.planks(3, 7, 3, 56, 26, 36, 0, 1, 5, ["wood_planks", "wood_honey", "wood_planks", "wood_dark"])
	k.planks(3, 7, 3, 3, 26, 36, 2, 1, 5, ["wood_planks", "wood_honey"])
	k.planks(56, 7, 3, 56, 26, 36, 2, 1, 5, ["wood_planks", "wood_honey"])
	# Cadre sombre en bas et en haut de la caisse.
	k.box(3, 7, 3, 56, 8, 36, "wood_dark")
	k.box(3, 25, 3, 56, 26, 36, "wood_dark")

	# Piliers d'angle en pierre claire ébréchée, coiffés de cuivre.
	for c in [Vector2i(0, 0), Vector2i(51, 0), Vector2i(0, 31), Vector2i(51, 31)]:
		k.stone_block(c.x, 5, c.y, c.x + 8, 15, c.y + 8, 3)
		k.stone_block(c.x, 16, c.y, c.x + 8, 27, c.y + 8, 3)
		k.box(c.x + 1, 28, c.y + 1, c.x + 7, 29, c.y + 7, "copper")
		k.box(c.x + 3, 30, c.y + 3, c.x + 5, 30, c.y + 5, "copper")

	# Couvercle bombé à gradins (silhouette arrondie, lames le long de x).
	k.box(2, 27, 2, 57, 28, 37, "wood_dark")
	k.planks(3, 29, 3, 56, 31, 36, 0, 2, 6)
	k.planks(4, 32, 6, 55, 33, 33, 0, 2, 6)
	k.planks(5, 34, 10, 54, 35, 29, 0, 2, 6)
	k.planks(6, 36, 14, 53, 36, 25, 0, 2, 6, ["wood_honey", "wood_planks"])

	# Bandes de cuivre rivetées qui ceinturent caisse et couvercle.
	for bx in [14, 42]:
		for x in range(bx, bx + 4):
			for y in range(7, 37):
				for z in range(2, 38):
					if k.volume.get_voxel(x, y, z) == 0:
						continue
					var outer := z == 0 or k.volume.get_voxel(x, y, z + 1) == 0 or k.volume.get_voxel(x, y, z - 1) == 0 \
							or k.volume.get_voxel(x, y + 1, z) == 0
					if outer:
						k.set_cell(x, y, z, "copper")
		k.rivets(Vector3i(bx + 1, 10, 37), Vector3i(bx + 1, 24, 37), 5)
		k.rivets(Vector3i(bx + 2, 10, 37), Vector3i(bx + 2, 24, 37), 5)

	# Serrure : plaque en écusson, entrée sombre, moraillon et éclat serti.
	k.box(26, 13, 37, 33, 24, 37, "copper")
	k.box(27, 11, 37, 32, 12, 37, "copper")
	k.box(28, 10, 37, 31, 10, 37, "copper")
	k.box(29, 15, 38, 30, 18, 38, "iron_dark")
	k.box(27, 20, 38, 32, 30, 38, "brass")           # moraillon qui descend du couvercle
	k.box(28, 21, 38, 31, 23, 38, "iron_dark")
	k.box(28, 26, 39, 31, 28, 39, "crystal_blue")    # éclat serti
	k.set_cell(29, 29, 39, "crystal_blue")
	k.set_cell(30, 25, 39, "crystal_blue")

	# Poignées de fer sur les flancs.
	for x in [1, 58]:
		k.box(x, 22, 15, x, 22, 24, "iron_dark")
		k.box(x, 17, 15, x, 21, 15, "iron_dark")
		k.box(x, 17, 24, x, 21, 24, "iron_dark")
		k.box(x, 16, 16, x, 16, 23, "iron_dark")

	# Étoffe bleue drapée sur le couvercle, retombant devant (à droite de la serrure).
	k.drape(36, 14, [Vector2i(37, 13), Vector2i(37, 26), Vector2i(36, 26), Vector2i(36, 30), Vector2i(34, 30),
			Vector2i(34, 34), Vector2i(32, 34), Vector2i(32, 37), Vector2i(12, 37)], 3)

	# Lierre et mousse sur l'angle arrière gauche.
	k.ivy(Vector3i(2, 31, 2), 24, Vector3i(0, 0, 1), 0.12)
	k.ivy(Vector3i(8, 37, 12), 10, Vector3i(-1, 0, 0), 0.0)
	k.moss_top(0, 0, 20, 14, 0.5, 7)

	asset.add_part("structure", k)
	asset.add_light(Vector3(29.5, 27, 42), Color("7fd2ff"), 0.35, 1.2)
	asset.add_collider(Vector3i(0, 0, 0), Vector3i(59, 36, 39))
	return asset
