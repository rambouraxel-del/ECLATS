@tool
extends RefCounted
## Éclairage et décor (planche 3) : lampadaire à éclat, porte-bannière, panneau directionnel,
## tableau d'affichage, fontaine à piédestal, brasero. Microvoxels de 2 cm.

static func build(args: Dictionary) -> VoxelAsset:
	match String(args["id"]):
		"crystal_lamp": return _lamp()
		"banner_stand": return _banner_stand()
		"signpost": return _signpost()
		"notice_board": return _notice_board()
		"pedestal_fountain": return _fountain()
		"brazier": return _brazier()
	return null

# ------------------------------------------------------------------ lampadaire
static func _lamp() -> VoxelAsset:
	var a := VoxelAsset.new("crystal_lamp", "Lampadaire à éclat", Vector3i(4, 14, 3), "Poteau de bois sur socle de pierre, bras de cuivre, lanterne et bannière.")
	var k := AssetKit.new(Vector3i(40, 138, 30), 721)
	k.stone_block(2, 0, 2, 27, 9, 24, 4)
	k.stone_block(6, 10, 6, 21, 13, 20, 3, "stone_carved")
	k.post(10, 8, 12, 122, 8, "wood_planks")
	k.copper_collar(10, 8, 12, 14, 8)
	k.copper_collar(10, 8, 70, 72, 8)
	k.copper_cap(10, 8, 123, 8, 3)
	# Bras de cuivre en équerre qui porte la lanterne.
	k.box(18, 104, 11, 35, 108, 14, "copper")
	k.box(20, 96, 11, 23, 104, 14, "copper")
	k.line(Vector3(19, 98, 12.5), Vector3(30, 108, 12.5), 2, "iron_dark")
	k.line(Vector3(31.5, 104, 12.5), Vector3(31.5, 98, 12.5), 1, "iron_dark")
	var glow := k.lantern(31, 80, 12, 8, 14)
	k.banner(10, 100, 17, 14, 36, 2, 4)
	k.bush(Vector3(8, 16, 19), Vector3(7, 6, 6), "flower_white", 0.22)
	k.ivy(Vector3i(12, 70, 20), 36, Vector3i(1, 0, 0), 0.1)
	a.add_part("structure", k)
	a.add_light(glow, Color("ffb860"), 1.6, 6.5)
	a.add_collider(Vector3i(2, 0, 2), Vector3i(27, 124, 24))
	a.lod_ranges = [12.0, 34.0, 0.0]
	return a

# ------------------------------------------------------------------ porte-bannière
static func _banner_stand() -> VoxelAsset:
	var a := VoxelAsset.new("banner_stand", "Porte-bannière", Vector3i(6, 12, 2), "Cadre de bois et de cuivre portant une grande bannière à losange.")
	var k := AssetKit.new(Vector3i(60, 120, 12), 722)
	k.stone_block(0, 0, 0, 12, 7, 11, 3)
	k.stone_block(47, 0, 0, 59, 7, 11, 3)
	k.box(8, 6, 1, 51, 9, 10, "wood_dark")
	for x in [6, 50]:
		k.post(x, 3, 8, 104, 4, "wood_planks")
		k.copper_collar(x, 3, 40, 42, 4)
	k.box(4, 104, 3, 55, 107, 6, "copper")
	k.copper_cap(24, 2, 108, 12, 3)
	for x in [2, 54]:
		k.box(x, 103, 3, x + 3, 108, 6, "copper")
	k.banner(12, 102, 4, 36, 80, 2, 6)
	k.ivy(Vector3i(8, 90, 5), 30, Vector3i(0, 0, 1), 0.06)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(59, 108, 11))
	a.lod_ranges = [12.0, 32.0, 0.0]
	return a

# ------------------------------------------------------------------ panneau directionnel
static func _signpost() -> VoxelAsset:
	var a := VoxelAsset.new("signpost", "Panneau directionnel", Vector3i(4, 12, 4), "Poteau à deux flèches de bois gravées, lanterne et pierres de calage.")
	var k := AssetKit.new(Vector3i(40, 120, 40), 723)
	for p in [Vector2i(2, 4), Vector2i(26, 2), Vector2i(8, 26), Vector2i(24, 24)]:
		k.stone_block(p.x, 0, p.y, p.x + 12, 8, p.y + 11, 4)
	k.post(14, 14, 6, 110, 10, "wood_dark")
	k.copper_cap(14, 14, 111, 10, 3)
	k.copper_collar(14, 14, 20, 22, 10)
	# Deux flèches en sens opposés, rainures et losange/maison gravés.
	for arrow in [[88, -1], [66, 1]]:
		var y: int = arrow[0]
		var dir: int = arrow[1]
		var x0 := 20 if dir > 0 else -2
		k.box(x0 + 2, y, 15, x0 + 32, y + 13, 22, "wood_honey")
		for i in 7:
			var tip := (x0 + 33 + i) if dir > 0 else (x0 + 1 - i)
			k.box(tip, y + i, 16, tip, y + 13 - i, 21, "wood_honey")
		k.box(x0 + 2, y, 15, x0 + 32, y, 22, "wood_dark")
		k.box(x0 + 2, y + 13, 15, x0 + 32, y + 13, 22, "wood_dark")
		for dy in range(-3, 4):
			var w := 3 - absi(dy)
			k.box(x0 + 16 - w, y + 6 + dy, 14, x0 + 16 + w, y + 6 + dy, 14, "stone_light")
		k.rivets(Vector3i(x0 + 4, y + 6, 23), Vector3i(x0 + 4, y + 6, 23), 1)
	var glow := k.lantern(29, 62, 18, 6, 9)
	k.line(Vector3(29.5, 82, 18.5), Vector3(29.5, 96, 18.5), 1, "iron_dark")
	k.line(Vector3(24, 96, 18.5), Vector3(29.5, 96, 18.5), 1, "iron_dark")
	k.bush(Vector3(8, 12, 30), Vector3(8, 6, 6), "flower_white", 0.22)
	k.ivy(Vector3i(15, 60, 14), 40, Vector3i(0, 0, 1), 0.08)
	a.add_part("structure", k)
	a.add_light(glow, Color("ffb860"), 0.9, 4.0)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(39, 112, 39))
	a.lod_ranges = [12.0, 34.0, 0.0]
	return a

# ------------------------------------------------------------------ tableau d'affichage
static func _notice_board() -> VoxelAsset:
	var a := VoxelAsset.new("notice_board", "Tableau d'affichage", Vector3i(8, 10, 2), "Panneau de bois couvert d'annonces, chaperon de toile bleue et lanterne.")
	var k := AssetKit.new(Vector3i(80, 100, 14), 724)
	for x in [3, 66]:
		k.stone_block(x - 3, 0, 0, x + 13, 7, 13, 4)
		k.post(x, 2, 8, 84, 10, "wood_planks")
		k.copper_cap(x, 2, 85, 10, 3)
	k.planks(10, 28, 4, 69, 78, 7, 0, 1, 5, ["wood_planks", "wood_honey", "wood_planks"], false)
	k.box(10, 76, 3, 69, 80, 8, "wood_dark")
	k.box(10, 28, 3, 69, 31, 8, "wood_dark")
	# Annonces : feuilles de papier clouées, de tailles variées.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 9:
		var x := 14 + (i % 3) * 18 + rng.randi_range(0, 3)
		var y := 36 + (i / 3) * 14 + rng.randi_range(0, 2)
		var w := rng.randi_range(9, 14)
		var h := rng.randi_range(9, 12)
		k.box(x, y, 3, x + w, y + h, 3, "paper")
		for l in 3:
			k.box(x + 2, y + 2 + l * 3, 2, x + w - 2, y + 2 + l * 3, 2, "wood_dark")
		k.set_cell(x + w / 2, y + h, 2, "iron_dark")
	k.banner(10, 85, 2, 60, 12, 2, 4)
	var glow := k.lantern(5, 50, 4, 6, 9)
	k.ivy(Vector3i(66, 84, 4), 40, Vector3i(0, 0, 1), 0.08)
	a.add_part("structure", k)
	a.add_light(glow, Color("ffb860"), 0.8, 3.5)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(79, 88, 13))
	a.lod_ranges = [12.0, 32.0, 0.0]
	return a

# ------------------------------------------------------------------ fontaine
static func _fountain() -> VoxelAsset:
	var a := VoxelAsset.new("pedestal_fountain", "Fontaine à piédestal", Vector3i(10, 9, 10), "Vasque octogonale de pierre, piédestal central, éclat bleu et filets d'eau.")
	var k := AssetKit.new(Vector3i(100, 92, 100), 725)
	# Vasque : anneau de maçonnerie, margelle, eau.
	k.stone_ring(50, 50, 0, 25, 49, 40, 14, 8)
	k.cyl_y(50, 50, 0, 20, 40.5, "stone_shade")
	k.cyl_y(50, 50, 26, 29, 49.5, "stone_carved", 38.0)
	k.cyl_y(50, 50, 30, 30, 49.5, "stone_light", 38.0)
	k.cyl_y(50, 50, 21, 24, 39.5, "water")
	# Piédestal central : fût octogonal, coupe supérieure, éclat flottant.
	k.stone_ring(50, 50, 21, 44, 10.5, 0.0, 10, 8)
	k.cyl_y(50, 50, 45, 48, 13.0, "stone_carved")
	k.cyl_y(50, 50, 49, 49, 14.0, "copper", 8.0)
	k.cyl_y(50, 50, 50, 52, 12.5, "stone_light", 9.0)
	k.cyl_y(50, 50, 50, 50, 8.5, "water")
	k.cyl_y(50, 50, 44, 44, 11.5, "copper", 9.5)
	k.crystal(Vector3(50, 53, 50), 26.0, 5.0, Vector2.ZERO, "crystal_ice", 0.35)
	# Filets d'eau : colonnes de pixels d'eau qui retombent dans la vasque.
	for i in 6:
		var ang := TAU * i / 6.0
		for y in range(24, 50):
			var rr := 12.5 + (49 - y) * 0.12
			k.set_if_empty(int(50 + cos(ang) * rr), y, int(50 + sin(ang) * rr), "water")
	# Plantes dans les angles, mousse sur la margelle.
	k.bush(Vector3(90, 32, 22), Vector3(7, 5, 7), "flower_white", 0.2)
	k.bush(Vector3(10, 32, 78), Vector3(7, 5, 7), "flower_pink", 0.2)
	k.moss_top(0, 0, 99, 99, 0.3, 17)
	k.ivy(Vector3i(70, 31, 85), 14, Vector3i(1, 0, 0), 0.1)
	a.add_part("structure", k)
	a.add_light(Vector3(50, 60, 50), Color("8fe0ff"), 0.9, 4.0)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(99, 31, 99))
	a.add_collider(Vector3i(36, 31, 36), Vector3i(63, 80, 63))
	a.lod_ranges = [14.0, 40.0, 0.0]
	return a

# ------------------------------------------------------------------ brasero
static func _brazier() -> VoxelAsset:
	var a := VoxelAsset.new("brazier", "Brasero rituel", Vector3i(4, 8, 4), "Piédestal de bois cerclé de cuivre portant une coupe de braises et de flammes.")
	var k := AssetKit.new(Vector3i(40, 84, 40), 726)
	k.stone_block(0, 0, 0, 39, 5, 39, 4)
	k.stone_block(4, 6, 4, 35, 9, 35, 3, "stone_carved")
	for c in [Vector2i(8, 8), Vector2i(26, 8), Vector2i(8, 26), Vector2i(26, 26)]:
		k.post(c.x, c.y, 10, 44, 6, "wood_dark")
		k.copper_collar(c.x, c.y, 24, 26, 6)
	k.box(8, 44, 8, 31, 46, 31, "wood_planks")
	k.banner(12, 40, 6, 16, 30, 2, 3)
	# Coupe de cuivre évasée, braises et flammes.
	for y in 12:
		var r := 8.0 + y * 0.95
		k.cyl_y(20, 20, 47 + y, 47 + y, r, "copper", r - 2.0)
	k.cyl_y(20, 20, 47, 47, 8.0, "copper")
	k.cyl_y(20, 20, 56, 56, 17.0, "ember")
	for i in 40:
		var ang := k.rng.randf() * TAU
		var rr := k.rng.randf() * 11.0
		k.set_if_empty(int(20 + cos(ang) * rr), 57, int(20 + sin(ang) * rr), "ember")
	var flame := AssetKit.new(Vector3i(40, 30, 40), 727)
	for i in 5:
		var ang := TAU * i / 5.0
		var base := Vector3(20 + cos(ang) * 6.0, 0, 20 + sin(ang) * 6.0)
		flame.line(base, Vector3(20 + cos(ang) * 2.0, 18 + (i % 3) * 3, 20 + sin(ang) * 2.0), 3, "fire")
	flame.line(Vector3(20, 0, 20), Vector3(20.5, 26, 20), 4, "fire")
	flame.line(Vector3(20, 4, 20), Vector3(20.5, 14, 20), 2, "crystal_warm")
	a.add_part("structure", k)
	a.add_part("flame", flame, Vector3i(0, 57, 0), "crystal")
	a.add_light(Vector3(20, 72, 20), Color("ffa24a"), 2.2, 7.0)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(39, 56, 39))
	a.lod_ranges = [12.0, 34.0, 0.0]
	return a
