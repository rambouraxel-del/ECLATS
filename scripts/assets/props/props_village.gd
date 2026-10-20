@tool
extends RefCounted
## Mobilier de village (planches 2 et 3) : puits, bitte d'amarrage, balustrade, jardinière,
## kiosque, charrette, tonneaux, sanctuaire, caisses, clôture, potager. Microvoxels de 2 cm.
## build(args) : args["id"] choisit le modèle.

static func build(args: Dictionary) -> VoxelAsset:
	match String(args["id"]):
		"water_well": return _well()
		"mooring_post": return _mooring_post()
		"balustrade": return _balustrade()
		"large_planter": return _planter()
		"canopy_kiosk": return _kiosk()
		"utility_cart": return _cart()
		"barrel_set": return _barrels()
		"shrine_marker": return _shrine()
		"crate_stack": return _crates()
		"garden_fence": return _fence()
		"vegetable_bed": return _vegetable_bed()
	return null

static func _cyl_x(k: AssetKit, x0: int, x1: int, cy: float, cz: float, r: float, key: String) -> void:
	var id := k.mat(key)
	for z in range(floori(cz - r) - 1, ceili(cz + r) + 1):
		for y in range(floori(cy - r) - 1, ceili(cy + r) + 1):
			if Vector2(z + 0.5 - cz, y + 0.5 - cy).length() <= r:
				for x in range(x0, x1 + 1):
					k.volume.set_voxel(x, y, z, id)

# ------------------------------------------------------------------ puits
static func _well() -> VoxelAsset:
	var a := VoxelAsset.new("water_well", "Puits", Vector3i(7, 11, 7), "Puits de pierre à poulie, toit de planches et bannière.")
	var k := AssetKit.new(Vector3i(70, 110, 70), 701)
	k.stone_ring(35, 35, 0, 33, 33, 21, 13, 8)
	k.cyl_y(35, 35, 34, 37, 34.5, "stone_carved", 20.0)
	k.cyl_y(35, 35, 38, 38, 34.5, "stone_light", 20.0)
	k.cyl_y(35, 35, 28, 31, 21.0, "water")
	# Poteaux, traverse, tambour et corde.
	for x in [5, 59]:
		k.post(x, 31, 36, 98, 6, "wood_planks")
		k.copper_collar(x, 31, 36, 38, 6)
		k.copper_cap(x, 31, 99, 6, 3)
	k.box(8, 88, 32, 61, 93, 37, "wood_dark")
	_cyl_x(k, 12, 56, 78, 34.5, 5.5, "wood_planks")
	for x in range(14, 55, 4):
		_cyl_x(k, x, x + 1, 78, 34.5, 6.2, "rope")
	k.line(Vector3(34, 76, 34.5), Vector3(34, 54, 34.5), 1, "rope")
	k.cyl_y(34, 34.5, 44, 53, 5.5, "wood_planks", 3.8)
	k.cyl_y(34, 34.5, 44, 45, 5.5, "copper", 3.8)
	k.cyl_y(34, 34.5, 51, 52, 5.5, "copper", 3.8)
	k.cyl_y(34, 34.5, 44, 44, 4.0, "wood_dark")
	# Manivelle de cuivre.
	k.box(57, 76, 34, 67, 77, 36, "copper")
	k.box(66, 70, 34, 68, 78, 36, "wood_dark")
	# Toit à deux pans en planches, faîtage de cuivre, bannière.
	for j in 17:
		var y := 96 + j
		var z0 := 4 + j * 2
		var z1 := 66 - j * 2
		if z1 - z0 < 2:
			break
		k.planks(1, y, z0, 68, y + 1, z0 + 1, 0, 2, 4, ["wood_dark", "wood_planks", "wood_honey"], false)
		k.planks(1, y, z1 - 1, 68, y + 1, z1, 0, 2, 4, ["wood_dark", "wood_planks", "wood_honey"], false)
	k.banner(28, 100, 3, 14, 34, 2, 4)
	var glow := k.lantern(66, 62, 30, 5, 8)
	k.ivy(Vector3i(7, 64, 32), 26, Vector3i(0, 0, 1), 0.12)
	k.bush(Vector3(60, 38, 61), Vector3(7, 5, 6), "flower_white", 0.16)
	k.bush(Vector3(9, 38, 60), Vector3(6, 4, 5), "flower_yellow", 0.14)
	a.add_part("structure", k)
	a.add_light(glow, Color("ffb860"), 0.9, 4.0)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(69, 40, 69))
	a.lod_ranges = [12.0, 34.0, 0.0]
	return a

# ------------------------------------------------------------------ bitte d'amarrage
static func _mooring_post() -> VoxelAsset:
	var a := VoxelAsset.new("mooring_post", "Bitte d'amarrage", Vector3i(5, 6, 4), "Gros poteau cerclé de cuivre sur socle de pierre, cordage enroulé.")
	var k := AssetKit.new(Vector3i(50, 62, 40), 702)
	k.stone_block(6, 0, 4, 43, 7, 35, 5)
	k.cyl_y(25, 20, 8, 44, 12.5, "wood_planks")
	k.cyl_y(25, 20, 8, 44, 12.5, "wood_dark", 11.0)
	k.cyl_y(25, 20, 45, 50, 11.0, "wood_honey")
	k.cyl_y(25, 20, 51, 52, 8.0, "wood_dark")
	k.cyl_y(25, 20, 8, 11, 13.5, "copper", 11.0)
	k.cyl_y(25, 20, 42, 46, 13.5, "copper", 11.0)
	for i in 8:
		var a2 := TAU * i / 8.0
		k.box(int(25 + cos(a2) * 13.5), 44, int(20 + sin(a2) * 13.5), int(25 + cos(a2) * 13.5), 44, int(20 + sin(a2) * 13.5), "iron_dark")
	# Cordage : spires de corde sur le fût, deux brins qui partent.
	for y in range(14, 40, 3):
		k.cyl_y(25, 20, y, y + 1, 13.2, "rope", 11.0)
	for t in 60:
		var p := Vector3(25 + 13 + t * 0.35, 14 + sin(t * 0.18) * 2, 20 + sin(t * 0.12) * 3 + t * 0.15)
		k.set_if_empty(int(p.x), int(p.y), int(p.z), "rope")
		k.set_if_empty(int(p.x), int(p.y) + 1, int(p.z), "rope")
	k.moss_top(6, 4, 43, 35, 0.25, 3)
	a.add_part("structure", k)
	a.add_collider(Vector3i(6, 0, 4), Vector3i(43, 52, 35))
	a.lod_ranges = [10.0, 28.0, 0.0]
	return a

# ------------------------------------------------------------------ balustrade (module de 1 m)
static func _balustrade() -> VoxelAsset:
	var a := VoxelAsset.new("balustrade", "Balustrade", Vector3i(5, 5, 2), "Module de garde-corps : piliers de pierre à lanterne, lisse de bois ajourée.")
	var k := AssetKit.new(Vector3i(50, 50, 10), 703)
	for x in [0, 38]:
		k.stone_block(x, 0, 0, x + 11, 22, 9, 4)
		k.stone_block(x - 1, 23, -0 + 0, x + 12, 26, 9, 3, "stone_carved")
		k.copper_cap(x + 2, 2, 27, 8, 2)
	k.box(12, 14, 3, 37, 18, 6, "wood_planks")
	k.box(12, 4, 3, 37, 6, 6, "wood_dark")
	# Remplissage ajouré : losanges.
	for i in 5:
		var cx := 17 + i * 5
		k.box(cx, 7, 4, cx + 1, 13, 5, "wood_honey")
	k.box(12, 14, 3, 37, 14, 6, "wood_dark")
	k.box(12, 18, 3, 37, 18, 6, "wood_dark")
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(49, 28, 9))
	a.lod_ranges = [10.0, 26.0, 0.0]
	return a

# ------------------------------------------------------------------ jardinière
static func _planter() -> VoxelAsset:
	var a := VoxelAsset.new("large_planter", "Grande jardinière", Vector3i(8, 5, 3), "Bac de pierre cerclé de bois et de cuivre, fleurs et lavande.")
	var k := AssetKit.new(Vector3i(80, 50, 30), 704)
	k.masonry(0, 0, 0, 79, 17, 29, 16, 9, 3)
	k.box(0, 18, 0, 79, 20, 29, "stone_carved")
	k.box(3, 19, 3, 76, 20, 26, "")
	k.box(3, 17, 3, 76, 19, 26, "potting_soil")
	k.planks(2, 6, 0, 77, 11, 0, 0, 1, 3, ["wood_planks", "wood_honey"], false)
	for x in [0, 77]:
		k.corner_plate(x, 0, 1 if x == 0 else -1, 1, 4, 17, 5)
		k.corner_plate(x + (2 if x == 77 else 0), 29, 1 if x == 0 else -1, -1, 4, 17, 5)
	# Motif de losange de cuivre sur la face avant.
	for dy in range(-4, 5):
		var w := 4 - absi(dy)
		k.box(40 - w, 10 + dy, 0, 40 + w, 10 + dy, 0, "copper")
	k.bush(Vector3(20, 22, 15), Vector3(16, 8, 11), "flower_white", 0.2)
	k.bush(Vector3(55, 22, 14), Vector3(15, 7, 10), "flower_pink", 0.18)
	# Lavande : tiges bleues.
	for i in 36:
		var x := 28 + i
		var z := 8 + (i * 7) % 14
		k.line(Vector3(x, 19, z), Vector3(x + 0.4, 29 + (i % 5), z), 1, "leaf_olive")
		k.box(x, 29 + (i % 5), z, x, 33 + (i % 5), z, "flower_blue")
	k.ivy(Vector3i(70, 22, 1), 12, Vector3i(1, 0, 0), 0.1)
	k.ivy(Vector3i(4, 22, 1), 13, Vector3i(1, 0, 0), 0.1)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(79, 22, 29))
	a.lod_ranges = [10.0, 28.0, 0.0]
	return a

# ------------------------------------------------------------------ kiosque à auvent
static func _kiosk() -> VoxelAsset:
	var a := VoxelAsset.new("canopy_kiosk", "Kiosque à auvent", Vector3i(11, 12, 7), "Petit kiosque de bois sur socle de pierre : comptoir, parchemins, flacons, auvent de toile.")
	var k := AssetKit.new(Vector3i(110, 114, 70), 705)
	var posts := [Vector2i(4, 4), Vector2i(96, 4), Vector2i(4, 54), Vector2i(96, 54)]
	for p in posts:
		k.stone_block(p.x - 2, 0, p.y - 2, p.x + 11, 7, p.y + 11, 4)
		k.post(p.x, p.y, 8, 96, 9, "wood_planks")
		k.copper_collar(p.x, p.y, 8, 10, 9)
		k.copper_cap(p.x, p.y, 97, 9, 3)
	k.box(4, 88, 4, 105, 95, 8, "wood_dark")
	k.box(4, 88, 54, 105, 95, 58, "wood_dark")
	# Comptoir.
	k.planks(14, 8, 40, 95, 38, 63, 0, 1, 6)
	k.box(12, 39, 38, 97, 42, 66, "wood_honey")
	k.box(12, 39, 66, 97, 40, 66, "wood_dark")
	k.banner(44, 38, 67, 18, 30, 2, 4)
	# Fond : panneau et étagère à flacons, parchemins accrochés.
	k.planks(12, 8, 6, 97, 90, 7, 1, 0, 9, ["wood_planks", "wood_honey", "wood_dark"])
	k.box(12, 52, 8, 97, 54, 20, "wood_honey")
	for i in 6:
		var x := 18 + i * 8
		k.box(x, 55, 11, x + 3, 61, 14, ["glass_green", "potion_violet", "crystal_deep"][i % 3])
		k.box(x + 1, 62, 12, x + 2, 63, 13, "wood_light")
	for i in 3:
		var x := 22 + i * 24
		k.box(x, 70, 8, x + 14, 84, 8, "paper")
		k.box(x + 2, 80, 9, x + 11, 80, 9, "wood_dark")
		k.box(x + 2, 76, 9, x + 9, 76, 9, "wood_dark")
		k.box(x + 2, 72, 9, x + 6, 72, 9, "wood_dark")
	# Sur le comptoir : rouleaux de parchemin, balance, coffret.
	for i in 3:
		k.cyl_y(22 + i * 6, 52, 43, 56, 2.2, "paper")
	k.box(60, 43, 46, 80, 50, 58, "wood_dark")
	k.box(61, 50, 47, 79, 51, 57, "wood_planks")
	k.box(63, 50, 50, 65, 52, 52, "copper")
	k.crystal(Vector3(88, 43, 50), 12.0, 2.4, Vector2(0.08, 0), "crystal_blue")
	# Enseigne et lanterne.
	k.planks(10, 70, 66, 34, 86, 67, 0, 1, 4, ["wood_honey", "wood_planks"], false)
	for dy in range(-4, 5):
		var w := 4 - absi(dy)
		k.box(22 - w, 78 + dy, 68, 22 + w, 78 + dy, 68, "brass")
	var glow := k.lantern(100, 78, 62, 6, 9)
	k.line(Vector3(100, 95, 62.5), Vector3(100, 88, 62.5), 1, "iron_dark")
	k.ivy(Vector3i(3, 95, 6), 60, Vector3i(0, 0, 1), 0.08)
	k.bush(Vector3(104, 12, 20), Vector3(5, 5, 8), "flower_white", 0.15)
	a.add_part("structure", k)
	# Auvent : toile rayée crème et bleu, lambrequin à franges.
	var c := AssetKit.new(Vector3i(110, 46, 70), 706)
	for z in 70:
		for x in 110:
			var yc := lerpf(42.0, 33.0, z / 69.0) - 2.5 * sin(PI * x / 109.0) * (0.4 + 0.6 * z / 69.0)
			var band := (x / 14) % 2
			var key := "fabric_cream" if band == 0 else "fabric_blue"
			if x % 14 == 0 or z >= 65:
				key = "fabric_cream" if band == 1 else "fabric_teal"
			var yi := roundi(yc)
			c.set_cell(x, yi, z, key)
			c.set_cell(x, yi - 1, z, key)
			if z == 69:
				var drop := 7 if (x % 10) < 5 else 5
				for d in drop:
					var fk := key if d < drop - 2 else ("fabric_cream" if x % 2 == 0 else "")
					if fk != "":
						c.set_cell(x, yi - 2 - d, z, fk)
	a.add_part("canopy", c, Vector3i(0, 70, 0), "cloth")
	a.add_light(glow, Color("ffb860"), 1.0, 4.5)
	a.add_collider(Vector3i(12, 0, 38), Vector3i(97, 42, 66))
	for p in posts:
		a.add_collider(Vector3i(p.x - 2, 0, p.y - 2), Vector3i(p.x + 11, 96, p.y + 11))
	a.lod_ranges = [14.0, 40.0, 0.0]
	return a

# ------------------------------------------------------------------ charrette
static func _cart() -> VoxelAsset:
	var a := VoxelAsset.new("utility_cart", "Charrette", Vector3i(11, 8, 5), "Charrette à bras : caisses, foin et rouleau de toile.")
	var k := AssetKit.new(Vector3i(110, 78, 50), 707)
	# Plateau et ridelles.
	k.planks(10, 20, 8, 80, 23, 41, 0, 2, 5)
	k.planks(10, 24, 8, 80, 36, 9, 0, 1, 4, ["wood_planks", "wood_honey"], true)
	k.planks(10, 24, 40, 80, 36, 41, 0, 1, 4, ["wood_planks", "wood_honey"], true)
	k.planks(10, 24, 8, 11, 36, 41, 2, 1, 4, ["wood_planks", "wood_honey"], true)
	k.planks(79, 24, 8, 80, 36, 41, 2, 1, 4, ["wood_planks", "wood_honey"], true)
	for p in [Vector2i(10, 8), Vector2i(79, 8), Vector2i(10, 40), Vector2i(79, 40)]:
		k.box(p.x - 1, 20, p.y - 1, p.x + 2, 40, p.y + 2, "wood_dark")
		k.copper_cap(p.x - 1, p.y - 1, 41, 4, 2)
	# Essieu et roues (grandes roues à rayons).
	k.box(44, 15, 4, 49, 19, 45, "wood_dark")
	k.wheel_z(46, 17, 1, 3, 16.0)
	k.wheel_z(46, 17, 46, 3, 16.0)
	# Brancards et poignée.
	k.box(80, 24, 14, 108, 26, 16, "wood_planks")
	k.box(80, 24, 34, 108, 26, 36, "wood_planks")
	k.box(104, 24, 14, 108, 26, 36, "wood_dark")
	k.copper_cap(104, 13, 27, 4, 2)
	# Chargement : caisses, rouleau de toile bleue, foin, tonnelet.
	k.crate(14, 24, 12, 33, 40, 31, "wood_planks", "copper")
	k.crate(36, 24, 12, 52, 34, 28, "wood_honey", "iron")
	_cyl_x(k, 14, 46, 32, 36, 6.0, "fabric_blue")
	_cyl_x(k, 14, 15, 32, 36, 6.0, "fabric_cream")
	_cyl_x(k, 45, 46, 32, 36, 6.0, "fabric_cream")
	for i in 90:
		var p := Vector3(k.rng.randf_range(52, 78), 24 + k.rng.randf_range(0, 9), k.rng.randf_range(11, 38))
		k.set_if_empty(int(p.x), int(p.y), int(p.z), "hay")
	k.barrel(62, 22, 24, 14, 6.5, 5.5)
	k.ivy(Vector3i(14, 40, 10), 10, Vector3i(1, 0, 0), 0.08)
	a.add_part("structure", k)
	a.add_collider(Vector3i(8, 0, 2), Vector3i(82, 40, 47))
	a.lod_ranges = [10.0, 28.0, 0.0]
	return a

# ------------------------------------------------------------------ tonneaux
static func _barrels() -> VoxelAsset:
	var a := VoxelAsset.new("barrel_set", "Tonneaux et caisse", Vector3i(7, 5, 5), "Deux tonneaux cerclés de cuivre, une caisse, une jarre et un cordage.")
	var k := AssetKit.new(Vector3i(70, 54, 50), 708)
	k.barrel(20, 22, 0, 50, 15.0, 11.5)
	k.barrel(49, 15, 0, 38, 12.0, 9.5, "wood_honey", "iron")
	k.crate(54, 0, 28, 68, 14, 42, "wood_planks", "copper")
	# Jarre en terre cuite.
	for y in 22:
		var r := 7.0 * sin(PI * (y + 3) / 28.0) + 1.5
		k.cyl_y(44, 38, y, y, r, "terracotta")
	k.cyl_y(44, 38, 22, 24, 4.2, "terracotta", 2.8)
	# Cordage au sol.
	for t in 80:
		var ang := t * 0.3
		k.set_if_empty(int(8 + cos(ang) * (4 + t * 0.06)), 0, int(40 + sin(ang) * (4 + t * 0.06)), "rope")
	k.banner(7, 49, 5, 14, 20, 2, 3)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(69, 50, 49))
	a.lod_ranges = [10.0, 28.0, 0.0]
	return a

# ------------------------------------------------------------------ sanctuaire
static func _shrine() -> VoxelAsset:
	var a := VoxelAsset.new("shrine_marker", "Sanctuaire", Vector3i(6, 12, 6), "Borne de pierre à niche ogivale, éclat bleu, bougies et bannière.")
	var k := AssetKit.new(Vector3i(60, 116, 60), 709)
	k.masonry(0, 0, 0, 59, 11, 59, 14, 8, 3)
	k.masonry(8, 12, 8, 51, 21, 51, 12, 8, 3)
	# Stèle : fût et niche ogivale creusée.
	k.stone_block(18, 22, 18, 41, 82, 41, 3, "stone_light")
	k.box(16, 22, 16, 43, 25, 43, "stone_carved")
	for y in range(26, 58):
		var half := 6 if y < 46 else maxi(6 - (y - 46) / 2, 0)
		if half > 0:
			k.box(30 - half, y, 41, 29 + half, y, 41, "")
	k.box(26, 26, 38, 33, 44, 40, "stone_shade")
	# Éclat dans la niche, cadre de cuivre.
	k.crystal(Vector3(30, 28, 39), 17.0, 3.0, Vector2.ZERO, "crystal_blue", 0.35)
	for y in range(26, 58):
		var half := 6 if y < 46 else maxi(6 - (y - 46) / 2, 0)
		if half > 0:
			k.set_cell(30 - half - 1, y, 41, "copper")
			k.set_cell(29 + half + 1, y, 41, "copper")
	# Chapiteau pyramidal et capuchon.
	for i in 8:
		k.stone_block(17 + i, 83 + i * 2, 17 + i, 42 - i, 84 + i * 2, 42 - i, 0, "stone_carved")
	k.copper_cap(26, 26, 100, 8, 4)
	k.banner(21, 80, 42, 18, 40, 2, 4)
	# Bougies sur le socle.
	for p in [Vector2i(6, 2), Vector2i(12, 4), Vector2i(48, 3)]:
		k.box(p.x, 12, p.y + 6, p.x + 2, 17, p.y + 8, "paper")
		k.box(p.x + 1, 18, p.y + 7, p.x + 1, 20, p.y + 7, "fire")
	k.moss_top(0, 0, 59, 59, 0.35, 9)
	k.bush(Vector3(6, 14, 50), Vector3(7, 5, 7), "flower_white", 0.22)
	k.bush(Vector3(54, 14, 8), Vector3(6, 4, 6), "flower_white", 0.2)
	k.ivy(Vector3i(40, 80, 18), 50, Vector3i(1, 0, 0), 0.1)
	a.add_part("structure", k)
	a.add_light(Vector3(30, 38, 46), Color("7fd2ff"), 0.8, 3.0)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(59, 100, 59))
	a.lod_ranges = [14.0, 40.0, 0.0]
	return a

# ------------------------------------------------------------------ pile de caisses
static func _crates() -> VoxelAsset:
	var a := VoxelAsset.new("crate_stack", "Caisses empilées", Vector3i(5, 5, 5), "Caisses de bois cerclées de cuivre et sac de grain.")
	var k := AssetKit.new(Vector3i(50, 54, 50), 710)
	k.crate(0, 0, 0, 27, 21, 27, "wood_planks", "copper")
	k.crate(30, 0, 4, 47, 15, 22, "wood_honey", "iron")
	k.crate(3, 22, 3, 21, 37, 21, "wood_planks", "copper")
	k.ellipsoid(Vector3(38, 8, 38), Vector3(9, 8, 9), "fabric_cream")
	k.box(35, 15, 35, 41, 17, 41, "rope")
	k.line(Vector3(0, 22, 0), Vector3(27, 22, 27), 1, "iron_dark")
	k.ivy(Vector3i(24, 36, 8), 14, Vector3i(0, 0, 1), 0.0)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(49, 37, 49))
	a.lod_ranges = [10.0, 26.0, 0.0]
	return a

# ------------------------------------------------------------------ clôture (module de 1 m)
static func _fence() -> VoxelAsset:
	var a := VoxelAsset.new("garden_fence", "Clôture de jardin", Vector3i(5, 4, 1), "Module de clôture en lattes avec poteaux à chapeau de cuivre.")
	var k := AssetKit.new(Vector3i(50, 42, 6), 711)
	for x in [0, 45]:
		k.post(x, 0, 0, 36, 5, "wood_dark")
		k.copper_cap(x, 0, 37, 5, 2)
	k.box(5, 26, 1, 44, 29, 3, "wood_planks")
	k.box(5, 10, 1, 44, 13, 3, "wood_planks")
	for x in range(7, 44, 6):
		k.box(x, 4, 2, x + 3, 30, 3, "wood_honey")
		k.box(x, 31, 2, x + 3, 32, 3, "wood_honey")
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(49, 36, 5))
	a.lod_ranges = [8.0, 22.0, 0.0]
	return a

# ------------------------------------------------------------------ potager
static func _vegetable_bed() -> VoxelAsset:
	var a := VoxelAsset.new("vegetable_bed", "Carré de potager", Vector3i(10, 3, 5), "Carré surélevé de terre fertile : rangs de choux, poireaux et fleurs.")
	var k := AssetKit.new(Vector3i(100, 30, 50), 712)
	k.planks(0, 0, 0, 99, 9, 49, 0, 1, 5, ["wood_planks", "wood_dark", "wood_honey"], true)
	k.box(3, 4, 3, 96, 9, 46, "potting_soil")
	k.box(2, 9, 2, 97, 9, 47, "dirt_fertile")
	for row in 4:
		var z := 8 + row * 11
		for i in 12:
			var x := 8 + i * 8
			match row:
				0:
					k.ellipsoid(Vector3(x, 14, z), Vector3(4.2, 3.6, 4.2), "leaf_light")
					k.ellipsoid(Vector3(x, 13, z), Vector3(3.0, 2.6, 3.0), "leaves", true)
				1:
					k.line(Vector3(x, 10, z), Vector3(x, 22, z), 2, "leaf_olive")
					k.box(x - 1, 10, z - 1, x, 12, z, "snow_white")
				2:
					k.ellipsoid(Vector3(x, 14, z), Vector3(3.5, 4.5, 3.5), "leaf_dark")
					if i % 3 == 0:
						k.set_cell(x, 18, z, "flower_yellow")
				3:
					k.line(Vector3(x, 10, z), Vector3(x + 0.5, 16, z), 1, "ivy")
					k.box(x - 1, 16, z - 1, x + 1, 18, z + 1, "flower_pink" if i % 2 == 0 else "flower_white")
	k.copper_cap(0, 0, 10, 4, 2)
	a.add_part("structure", k)
	a.add_collider(Vector3i(0, 0, 0), Vector3i(99, 24, 49))
	a.lod_ranges = [10.0, 26.0, 0.0]
	return a
