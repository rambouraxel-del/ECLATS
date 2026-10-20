@tool
extends RefCounted
## Artisanat et rangement (planche 4) : forge, râtelier d'outils, étagère de stockage,
## coffre de ravitaillement, caisse à matériaux. Microvoxels de 2 cm.

static func build(args: Dictionary) -> VoxelAsset:
	match String(args["id"]):
		"forge": return _forge()
		"tool_rack": return _tool_rack()
		"storage_rack": return _storage_rack()
		"supply_chest": return _supply_chest()
		"materials_crate": return _materials_crate()
	return null

# ------------------------------------------------------------------ forge
static func _forge() -> VoxelAsset:
	var a := VoxelAsset.new("forge", "Forge", Vector3i(11, 10, 8), "Forge de pierre à cheminée, enclume, soufflet, baquet et outils.")
	var k := AssetKit.new(Vector3i(110, 100, 80), 731)
	# Socle et foyer.
	k.masonry(0, 0, 0, 62, 17, 49, 16, 8, 3)
	k.masonry(4, 18, 4, 58, 44, 45, 16, 8, 3)
	k.box(18, 18, 4, 44, 34, 6, "stone_dark")            # ouverture du foyer
	k.box(18, 18, 7, 44, 34, 40, "stone_dark")
	k.box(20, 18, 8, 42, 20, 38, "ember")
	for i in 26:
		k.set_if_empty(21 + k.rng.randi_range(0, 20), 21, 9 + k.rng.randi_range(0, 28), "ember")
	# Cheminée pyramidale, bandeau de cuivre, tuyau.
	for i in 12:
		k.masonry(10 + i * 2, 45 + i * 4, 10 + i, 52 - i * 2, 48 + i * 4, 40 - i, 12, 8, 2)
	k.box(24, 92, 18, 38, 98, 30, "stone_carved")
	k.copper_cap(24, 18, 99, 14, 4)
	k.box(4, 41, 3, 58, 44, 4, "copper")
	k.box(14, 35, 3, 48, 36, 4, "copper")
	# Enclume en fer.
	k.box(78, 16, 20, 100, 22, 36, "wood_dark")
	k.box(82, 23, 22, 96, 32, 34, "iron_dark")
	k.box(76, 33, 20, 102, 38, 36, "iron")
	k.box(100, 34, 24, 108, 37, 32, "iron")
	k.box(78, 38, 24, 98, 39, 32, "iron")
	# Soufflet de cuir et bois.
	k.box(66, 18, 4, 76, 40, 18, "wood_planks")
	for i in 6:
		k.box(66 - i, 22 + i * 3, 6, 76 + i, 24 + i * 3, 16, "leather")
	k.box(60, 24, 10, 66, 28, 12, "copper")
	# Baquet d'eau, outils appuyés, pince, marteau.
	k.barrel(88, 62, 0, 20, 9.0, 8.0, "wood_planks", "copper")
	k.cyl_y(88, 62, 19, 19, 7.0, "water")
	k.box(66, 18, 44, 69, 44, 47, "wood_honey")
	k.box(63, 40, 44, 72, 44, 47, "iron")
	k.line(Vector3(72, 18, 50), Vector3(76, 44, 50), 2, "wood_dark")
	k.stone_block(64, 0, 54, 80, 7, 74, 3)
	k.banner(24, 76, 51, 16, 30, 2, 4)
	k.moss_top(0, 0, 62, 49, 0.2, 5)
	k.ivy(Vector3i(2, 44, 6), 20, Vector3i(0, 0, 1), 0.05)
	a.add_part("structure", k)
	a.add_light(Vector3(31, 24, 30), Color("ff9a3c"), 1.5, 5.0)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(62, 99, 49))
	a.add_collider(Vector3i(76, 0, 18), Vector3i(108, 40, 38))
	a.lod_ranges = [14.0, 38.0, 0.0]
	return a

# ------------------------------------------------------------------ râtelier d'outils
static func _tool_rack() -> VoxelAsset:
	var a := VoxelAsset.new("tool_rack", "Râtelier d'outils", Vector3i(5, 7, 2), "Panneau de bois portant marteaux, scie, tenailles et clés ; caisse d'outils au pied.")
	var k := AssetKit.new(Vector3i(50, 72, 14), 732)
	for x in [0, 44]:
		k.post(x, 0, 4, 66, 6, "wood_planks")
		k.copper_cap(x, 0, 67, 6, 2)
	k.planks(6, 14, 2, 43, 62, 4, 1, 0, 6, ["wood_planks", "wood_honey", "wood_dark"], true)
	k.box(0, 60, 0, 49, 63, 6, "wood_dark")
	k.box(0, 14, 0, 49, 17, 6, "wood_dark")
	# Marteau, scie, tenailles, clé, compas.
	k.box(10, 24, 5, 12, 52, 5, "wood_honey")
	k.box(6, 48, 5, 16, 53, 6, "iron")
	k.box(20, 30, 5, 33, 54, 5, "iron")
	for x in range(20, 34, 2):
		k.set_cell(x, 30, 5, "")
	k.box(33, 46, 5, 38, 56, 6, "wood_dark")
	k.line(Vector3(40, 56, 5.5), Vector3(37, 30, 5.5), 1, "iron_dark")
	k.line(Vector3(40, 56, 5.5), Vector3(43, 30, 5.5), 1, "iron_dark")
	k.box(24, 20, 5, 25, 28, 5, "copper")
	k.box(22, 26, 5, 28, 29, 5, "copper")
	k.crate(8, 0, 4, 40, 13, 13, "wood_dark", "copper")
	k.box(14, 14, 6, 34, 15, 9, "iron_dark")
	k.banner(38, 62, 7, 10, 22, 2, 3)
	k.ivy(Vector3i(46, 66, 5), 20, Vector3i(0, 0, 1), 0.06)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(49, 68, 13))
	a.lod_ranges = [10.0, 28.0, 0.0]
	return a

# ------------------------------------------------------------------ étagère de stockage
static func _storage_rack() -> VoxelAsset:
	var a := VoxelAsset.new("storage_rack", "Étagère de stockage", Vector3i(8, 9, 3), "Étagère à trois niveaux : caisses, jarres, sacs, pierres taillées, bannière.")
	var k := AssetKit.new(Vector3i(80, 92, 30), 733)
	for x in [0, 72]:
		for z in [0, 22]:
			k.post(x, z, 0, 84, 8, "wood_planks")
		k.copper_cap(x, 0, 85, 8, 2)
	for y in [2, 30, 58]:
		k.planks(0, y, 0, 79, y + 3, 29, 0, 2, 5, ["wood_honey", "wood_planks"], true)
	k.box(0, 84, 0, 79, 87, 29, "wood_dark")
	# Niveau bas : caisses.
	k.crate(10, 5, 4, 34, 28, 24, "wood_planks", "copper")
	k.crate(38, 5, 6, 60, 20, 22, "wood_honey", "iron")
	# Niveau moyen : jarres et sacs.
	for i in 3:
		for y in 16:
			var r := 4.8 * sin(PI * (y + 3) / 22.0) + 1.0
			k.cyl_y(14 + i * 12, 14, 33 + y, 33 + y, r, "terracotta")
		k.cyl_y(14 + i * 12, 14, 49, 50, 3.0, "wood_light")
	k.ellipsoid(Vector3(54, 40, 14), Vector3(8, 8, 8), "fabric_cream")
	k.ellipsoid(Vector3(68, 38, 12), Vector3(7, 6, 7), "hay")
	# Niveau haut : pierres taillées, rouleaux, flacons.
	k.stone_block(6, 61, 6, 24, 70, 22, 3)
	k.stone_block(10, 71, 8, 22, 78, 20, 3)
	for i in 4:
		k.box(32 + i * 6, 61, 8, 36 + i * 6, 70, 14, ["glass_green", "potion_violet", "crystal_deep", "glass_green"][i])
		k.box(33 + i * 6, 71, 9, 35 + i * 6, 72, 13, "wood_light")
	k.crystal(Vector3(64, 61, 16), 14.0, 2.8, Vector2(0.1, 0), "crystal_blue")
	k.banner(70, 84, 25, 10, 24, 2, 3)
	k.bush(Vector3(40, 90, 14), Vector3(12, 5, 8), "flower_white", 0.15)
	k.ivy(Vector3i(8, 86, 26), 30, Vector3i(1, 0, 0), 0.08)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(79, 88, 29))
	a.lod_ranges = [12.0, 32.0, 0.0]
	return a

# ------------------------------------------------------------------ coffre de ravitaillement
static func _supply_chest() -> VoxelAsset:
	var a := VoxelAsset.new("supply_chest", "Coffre de ravitaillement", Vector3i(6, 3, 3), "Long coffre de bois cerclé de cuivre à coins de pierre, bande de toile bleue.")
	var k := AssetKit.new(Vector3i(60, 32, 30), 734)
	k.planks(0, 0, 0, 59, 20, 29, 0, 1, 4, ["wood_planks", "wood_honey", "wood_planks"], true)
	k.box(0, 21, 0, 59, 23, 29, "wood_dark")
	for i in 5:
		k.planks(2 + i, 24 + i, 3 + i, 57 - i, 24 + i, 26 - i, 0, 2, 4, ["wood_honey", "wood_planks"], false)
	for x in [0, 52]:
		k.stone_block(x, 0, 0, x + 7, 22, 7, 3)
		k.stone_block(x, 0, 22, x + 7, 22, 29, 3)
	for x in [16, 38]:
		k.box(x, 0, 0, x + 3, 28, 0, "copper")
		k.box(x, 0, 29, x + 3, 28, 29, "copper")
		k.box(x, 24, 4, x + 3, 28, 25, "copper")
	k.box(28, 12, 29, 33, 22, 30, "copper")
	k.box(29, 14, 30, 32, 17, 31, "iron_dark")
	k.runner(22, 14, 6, 24, 25, 12, 3)
	k.ivy(Vector3i(2, 23, 2), 14, Vector3i(0, 0, 1), 0.08)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(59, 28, 29))
	a.lod_ranges = [10.0, 26.0, 0.0]
	return a

# ------------------------------------------------------------------ caisse à matériaux
static func _materials_crate() -> VoxelAsset:
	var a := VoxelAsset.new("materials_crate", "Caisse à matériaux", Vector3i(5, 3, 3), "Caisse ouverte pleine de briques, de pierres et de cristaux bruts.")
	var k := AssetKit.new(Vector3i(50, 38, 30), 735)
	k.planks(0, 0, 0, 49, 17, 29, 0, 1, 4, ["wood_planks", "wood_honey", "wood_planks"], true)
	k.box(3, 8, 3, 46, 17, 26, "")
	k.box(3, 4, 3, 46, 8, 26, "wood_dark")
	for x in [0, 43]:
		k.stone_block(x, 0, 0, x + 6, 20, 6, 3)
		k.stone_block(x, 0, 23, x + 6, 20, 29, 3)
	# Chargement : briques, pierres, cristaux.
	for i in 9:
		var x := 5 + (i % 3) * 9
		var z := 5 + (i / 3) * 7
		k.box(x, 9, z, x + 7, 13 + (i % 2) * 2, z + 5, "terracotta" if i % 2 == 0 else "stone_light")
	k.crystal(Vector3(38, 9, 10), 18.0, 3.4, Vector2(-0.1, 0.05), "crystal_blue")
	k.crystal(Vector3(32, 9, 18), 12.0, 2.6, Vector2(0.12, 0), "crystal_cyan")
	k.stone_block(38, 9, 18, 46, 15, 25, 2, "stone_carved")
	k.runner(10, 12, 3, 12, 17, 8, 2)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(49, 20, 29))
	a.lod_ranges = [10.0, 26.0, 0.0]
	return a
