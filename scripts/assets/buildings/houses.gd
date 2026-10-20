@tool
extends RefCounted
## Bâtiments du village : maison de colon, chaumière, atelier à foyer ouvert, entrepôt du port,
## tour de guet. Grille de 10 cm ; motifs de pierre, crépi, tuiles et bois dessinés par le shader
## en pixels de 2 cm. Façade principale vers +z. build(args) : args["id"].

const M := 5   # marge (débord de toit) en cellules

static func build(args: Dictionary) -> VoxelAsset:
	match String(args["id"]):
		"house_colonist": return _house_a()
		"house_cottage": return _house_b()
		"workshop": return _workshop()
		"warehouse": return _warehouse()
		"watch_tower": return _tower()
	return null

static func _new_asset(id: String, name: String, size: Vector3i, desc: String) -> VoxelAsset:
	var a := VoxelAsset.new(id, name, Vector3i(size.x / 2, (size.y + 1) / 2, size.z / 2), desc)
	a.cell_m = VoxelGrid.STRUCTURE_SIZE
	a.category = "building"
	a.lod_factors = [2, 4]
	a.lod_ranges = [28.0, 75.0, 0.0]
	return a

# ------------------------------------------------------------------ maison de colon
static func _house_a() -> VoxelAsset:
	var W := 70
	var D := 54
	var size := Vector3i(W + 2 * M, 104, D + 2 * M + 6)
	var a := _new_asset("house_colonist", "Maison de colon", size, "Grande maison à étage en encorbellement : colombage, toit de tuiles, cheminée, volets.")
	var k := BuildingKit.new(size, 801)
	var x0 := M
	var x1 := M + W - 1
	var z0 := M
	var z1 := M + D - 1
	k.box(x0 - 1, 0, z0 - 1, x1 + 1, 5, z1 + 1, "stone_ashlar_dark")
	k.box(x0, 6, z0, x1, 32, z1, "plaster_cream")
	k.quoins(x0, x1, z0, z1, 6, 32)
	k.box(x0 - 1, 33, z0 - 1, x1 + 1, 35, z1 + 4, "wood_dark")
	k.box(x0, 36, z0, x1, 62, z1 + 3, "plaster_ochre")
	k.half_timber(2, z1 + 3, 1, x0 + 1, x1 - 1, 36, 62, 14, 0.4)
	k.half_timber(2, z0, -1, x0 + 1, x1 - 1, 36, 62, 14, 0.3)
	k.half_timber(0, x0, -1, z0 + 1, z1 + 2, 36, 62, 15, 0.3)
	k.half_timber(0, x1, 1, z0 + 1, z1 + 2, 36, 62, 15, 0.3)
	k.corbels(x0, x1, z1 + 1, 33, 9)
	# Porte, fenêtres.
	k.door(2, z1, 1, x0 + 30, 10, 21)
	k.window(2, z1, 1, x0 + 8, 12, 8, 10, true, true, true)
	k.window(2, z1, 1, x0 + 52, 12, 8, 10, false, true, true)
	for ux in [6, 28, 54]:
		k.window(2, z1 + 3, 1, x0 + ux, 41, 8, 12, ux == 28, true, ux != 28)
	k.window(0, x0, -1, z0 + 14, 12, 8, 10, false, true)
	k.window(0, x1, 1, z0 + 14, 12, 8, 10, true, true)
	k.window(0, x0, -1, z0 + 30, 41, 8, 12, true, true)
	k.window(0, x1, 1, z0 + 30, 41, 8, 12, false, true)
	k.window(2, z0, -1, x0 + 14, 12, 8, 10, false, true)
	k.window(2, z0, -1, x0 + 46, 41, 8, 12, true, true)
	# Toit, cheminée, planches d'avant-toit.
	k.gable_roof(x0 - 5, x1 + 5, z0 - 5, z1 + 3 + 5, 63, "tiles_terracotta", "plaster_ochre", 2, 3, x0, x1)
	k.box(x0 - 5, 62, z0 - 5, x1 + 5, 62, z0 - 5, "wood_dark")
	k.box(x0 - 5, 62, z1 + 8, x1 + 5, 62, z1 + 8, "wood_dark")
	k.chimney(x1 - 14, z0 + 8, 62, 92, 6, 6)
	# Détails fins (2 cm) : bannière, lanternes, panneau.
	k.add_banner(Vector3((x0 + 21) * 0.1, 3.25, (z1 + 1.3) * 0.1))
	var g := k.add_lantern(Vector3((x0 + 44) * 0.1, 2.25, (z1 + 2.2) * 0.1))
	k.add_lantern(Vector3((x0 + 18) * 0.1, 2.25, (z1 + 2.2) * 0.1))
	k.flush_details(a)
	a.add_part("structure", k)
	a.add_light(g / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 1.1, 5.0)
	a.add_collider(Vector3i(x0 - 1, 0, z0 - 1), Vector3i(x1 + 1, 62, z1 + 4))
	return a

# ------------------------------------------------------------------ chaumière
static func _house_b() -> VoxelAsset:
	var W := 52
	var D := 44
	var size := Vector3i(W + 2 * M, 84, D + 2 * M + 12)
	var a := _new_asset("house_cottage", "Chaumière", size, "Petite maison au toit de bardeaux, porche à poteaux, lucarne et cheminée de pierre.")
	var k := BuildingKit.new(size, 802)
	var x0 := M
	var x1 := M + W - 1
	var z0 := M
	var z1 := M + D - 1
	k.box(x0 - 1, 0, z0 - 1, x1 + 1, 5, z1 + 1, "stone_ashlar")
	k.box(x0, 6, z0, x1, 30, z1, "plaster_ochre")
	k.box(x0, 6, z0, x1, 17, z1, "plaster_ochre")
	k.quoins(x0, x1, z0, z1, 6, 30)
	k.half_timber(2, z1, 1, x0 + 1, x1 - 1, 6, 30, 13, 0.35)
	k.half_timber(2, z0, -1, x0 + 1, x1 - 1, 6, 30, 13, 0.3)
	k.half_timber(0, x0, -1, z0 + 1, z1 - 1, 6, 30, 14, 0.3)
	k.half_timber(0, x1, 1, z0 + 1, z1 - 1, 6, 30, 14, 0.3)
	k.door(2, z1, 1, x0 + 21, 10, 21)
	k.window(2, z1, 1, x0 + 5, 11, 8, 10, true, true, true)
	k.window(2, z1, 1, x0 + 39, 11, 8, 10, false, true, false)
	k.window(0, x0, -1, z0 + 17, 11, 8, 10, true, true)
	k.window(0, x1, 1, z0 + 17, 11, 8, 10, false, true)
	k.window(2, z0, -1, x0 + 21, 11, 8, 10, true, true)
	# Porche : deux poteaux, auvent à un pan.
	for px in [x0 + 17, x0 + 32]:
		k.box(px, 0, z1 + 9, px + 2, 27, z1 + 11, "wood_planks")
		k.box(px - 1, 27, z1 + 8, px + 3, 28, z1 + 12, "wood_dark")
	k.box(x0 + 14, 0, z1 + 4, x0 + 36, 0, z1 + 11, "stone_ashlar_dark")
	k.box(x0 + 14, 28, z1 + 2, x0 + 36, 29, z1 + 12, "wood_dark")
	for j in 8:
		k.box(x0 + 13, 29 + j, z1 + 2 + j, x0 + 37, 30 + j, z1 + 2 + j, "shingle_wood")
	k.box(x0 + 13, 29, z1 + 10, x0 + 37, 37, z1 + 12, "shingle_wood")
	# Toit de bardeaux plus pentu, lucarne.
	k.gable_roof(x0 - 5, x1 + 5, z0 - 5, z1 + 5, 31, "shingle_wood", "plaster_ochre", 1, 1, x0, x1)
	k.box(x0 + 18, 38, z1 - 1, x0 + 31, 48, z1 + 2, "plaster_ochre")
	k.window(2, z1 + 2, 1, x0 + 21, 40, 7, 7, true, false)
	k.chimney(x0 + 4, z0 + 6, 44, 62, 6, 6)
	k.add_banner(Vector3((x0 + 12) * 0.1, 2.9, (z1 + 1.3) * 0.1), 30, 64)
	var g := k.add_lantern(Vector3((x0 + 34) * 0.1, 2.3, (z1 + 2.2) * 0.1))
	k.flush_details(a)
	a.add_part("structure", k)
	a.add_light(g / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 1.0, 4.5)
	a.add_collider(Vector3i(x0 - 1, 0, z0 - 1), Vector3i(x1 + 1, 48, z1 + 12))
	return a

# ------------------------------------------------------------------ atelier à foyer ouvert
static func _workshop() -> VoxelAsset:
	var W := 66
	var D := 54
	var size := Vector3i(W + 2 * M, 92, D + 2 * M)
	var a := _new_asset("workshop", "Atelier", size, "Atelier de pierre à baie ouverte (forge et établi), colombage à l'étage, grande cheminée.")
	var k := BuildingKit.new(size, 803)
	var x0 := M
	var x1 := M + W - 1
	var z0 := M
	var z1 := M + D - 1
	k.box(x0 - 1, 0, z0 - 1, x1 + 1, 5, z1 + 1, "stone_ashlar_dark")
	k.box(x0, 6, z0, x1, 30, z1, "stone_ashlar")
	k.quoins(x0, x1, z0, z1, 6, 30, "stone_light")
	k.box(x0 - 1, 31, z0 - 1, x1 + 1, 33, z1 + 1, "wood_dark")
	k.box(x0, 34, z0, x1, 56, z1, "plaster_sage")
	k.half_timber(2, z1, 1, x0 + 1, x1 - 1, 34, 56, 13, 0.4)
	k.half_timber(2, z0, -1, x0 + 1, x1 - 1, 34, 56, 13, 0.3)
	k.half_timber(0, x0, -1, z0 + 1, z1 - 1, 34, 56, 14, 0.3)
	k.half_timber(0, x1, 1, z0 + 1, z1 - 1, 34, 56, 14, 0.3)
	# Baie ouverte au rez-de-chaussée : creusée, fond et sol de pierre, cadre de bois.
	var bx0 := x0 + 17
	var bx1 := x0 + 48
	k.box(bx0, 6, z1 - 15, bx1, 26, z1, "")
	k.box(bx0, 5, z1 - 15, bx1, 5, z1 + 5, "stone_ashlar_dark")
	k.box(bx0, 6, z1 - 16, bx1, 26, z1 - 16, "stone_dark")
	k.box(bx0, 27, z1 - 15, bx1, 29, z1, "wood_dark")
	for x in [bx0 - 3, bx1 + 1]:
		k.box(x, 6, z1 - 1, x + 2, 29, z1 + 2, "wood_planks")
		k.box(x - 1, 27, z1 - 2, x + 3, 29, z1 + 3, "copper")
	k.box(bx0 - 3, 29, z1 - 2, bx1 + 3, 30, z1 + 3, "wood_dark")
	# Fenêtres, étage.
	k.window(2, z1, 1, x0 + 4, 12, 7, 9, true, true)
	k.window(2, z1, 1, x0 + 54, 12, 7, 9, false, true)
	for ux in [8, 30, 52]:
		k.window(2, z1, 1, x0 + ux, 39, 8, 11, ux == 30, true, ux == 8)
	k.window(0, x0, -1, z0 + 20, 12, 7, 9, true, true)
	k.window(0, x0, -1, z0 + 20, 39, 8, 11, false, true)
	k.window(0, x1, 1, z0 + 20, 39, 8, 11, true, true)
	# Toit de bardeaux et grande cheminée de pierre sur le côté.
	k.gable_roof(x0 - 5, x1 + 5, z0 - 5, z1 + 5, 57, "shingle_wood", "plaster_sage", 2, 3, x0, x1)
	k.box(x0 - 5, 56, z0 - 5, x1 + 5, 56, z0 - 5, "wood_dark")
	k.box(x0 - 5, 56, z1 + 5, x1 + 5, 56, z1 + 5, "wood_dark")
	k.chimney(x1 - 10, z0 + 14, 40, 86, 9, 9)
	k.add_banner(Vector3((x0 + 8) * 0.1, 3.05, (z1 + 1.3) * 0.1), 30, 64, 2, "fabric_blue")
	var g := k.add_lantern(Vector3((bx0 - 4) * 0.1, 2.2, (z1 + 3.0) * 0.1))
	k.add_lantern(Vector3((bx1 + 5) * 0.1, 2.2, (z1 + 3.0) * 0.1))
	k.flush_details(a)
	a.add_part("structure", k)
	a.add_light(g / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 1.0, 5.0)
	a.add_collider(Vector3i(x0 - 1, 0, z0 - 1), Vector3i(x1 + 1, 56, z1 - 16))
	a.add_collider(Vector3i(x0 - 1, 0, z1 - 15), Vector3i(bx0 - 2, 56, z1 + 1))
	a.add_collider(Vector3i(bx1 + 2, 0, z1 - 15), Vector3i(x1 + 1, 56, z1 + 1))
	return a

# ------------------------------------------------------------------ entrepôt du port
static func _warehouse() -> VoxelAsset:
	var W := 72
	var D := 56
	var size := Vector3i(W + 2 * M, 90, D + 2 * M + 14)
	var a := _new_asset("warehouse", "Entrepôt du port", size, "Grand hangar de pierre et de planches, double porte cerclée de fer, palan sur potence, toit d'ardoise.")
	var k := BuildingKit.new(size, 804)
	var x0 := M
	var x1 := M + W - 1
	var z0 := M
	var z1 := M + D - 1
	k.box(x0 - 1, 0, z0 - 1, x1 + 1, 5, z1 + 1, "stone_ashlar_dark")
	k.box(x0, 6, z0, x1, 24, z1, "stone_ashlar")
	k.quoins(x0, x1, z0, z1, 6, 24, "stone_light")
	# Haut de mur en planches verticales (teintes alternées).
	k.planks(x0, 25, z0, x1, 50, z1, 1, 0, 4, ["wood_planks", "wood_honey", "wood_planks", "wood_dark"], false)
	k.box(x0 - 1, 25, z0 - 1, x1 + 1, 26, z1 + 1, "wood_dark")
	k.box(x0 - 1, 49, z0 - 1, x1 + 1, 50, z1 + 1, "wood_dark")
	k.half_timber(2, z1, 1, x0 + 1, x1 - 1, 27, 48, 18, 0.0)
	k.half_timber(0, x0, -1, z0 + 1, z1 - 1, 27, 48, 18, 0.0)
	k.half_timber(0, x1, 1, z0 + 1, z1 - 1, 27, 48, 18, 0.0)
	# Grande porte : double battant, cerclage de fer, arc de pierre.
	var dx := x0 + 24
	k.door(2, z1, 1, dx, 24, 30)
	for x in range(dx, dx + 24, 6):
		k.wbox(2, z1, 1, x, 3, x, 28, 2, "iron_dark")
	k.wbox(2, z1, 1, dx, 8, dx + 23, 9, 2, "iron_dark")
	k.wbox(2, z1, 1, dx, 22, dx + 23, 23, 2, "iron_dark")
	k.wbox(2, z1, 1, dx - 3, 31, dx + 26, 32, 1, "stone_light", 3)
	# Petites fenêtres hautes.
	for ux in [8, 20, 44, 56]:
		k.window(2, z1, 1, x0 + ux, 34, 6, 8, ux in [8, 56], false)
	for uz in [14, 34]:
		k.window(0, x0, -1, z0 + uz, 34, 6, 8, false, false)
		k.window(0, x1, 1, z0 + uz, 34, 6, 8, uz == 14, false)
	# Quai de chargement en bois devant la porte, escalier.
	k.planks(dx - 12, 0, z1 + 2, dx + 35, 3, z1 + 13, 0, 2, 4, ["wood_planks", "wood_honey", "wood_planks"], true)
	for px in [dx - 12, dx + 34]:
		for pz in [z1 + 2, z1 + 12]:
			k.box(px, 0, pz, px + 1, 4, pz + 1, "wood_dark")
	k.box(dx - 12, 3, z1 + 2, dx + 35, 4, z1 + 2, "wood_dark")
	# Toit d'ardoise, potence de palan au pignon.
	k.gable_roof(x0 - 5, x1 + 5, z0 - 5, z1 + 5, 51, "tiles_slate", "wood_planks", 2, 3, x0, x1)
	k.box(x0 - 5, 50, z0 - 5, x1 + 5, 50, z0 - 5, "wood_dark")
	k.box(x0 - 5, 50, z1 + 5, x1 + 5, 50, z1 + 5, "wood_dark")
	var bx := x0 + 36
	k.box(bx, 44, z1 + 3, bx + 3, 47, z1 + 23, "wood_dark")
	k.line(Vector3(bx + 1.5, 34, z1 + 2.5), Vector3(bx + 1.5, 45, z1 + 14), 3, "wood_planks")
	k.copper_cap(bx - 1, z1 + 21, 47, 5, 2)
	# Détail de 2 cm : poulie, corde et caisse suspendue.
	var hk := AssetKit.new(Vector3i(40, 150, 40), 805)
	hk.wheel_z(20, 140, 17, 6, 8.0, "wood_dark", "copper", 6)
	hk.line(Vector3(20, 132, 20), Vector3(20, 56, 20), 1, "rope")
	hk.crate(8, 6, 8, 32, 40, 32, "wood_planks", "copper")
	hk.line(Vector3(10, 46, 10), Vector3(20, 56, 20), 1, "rope")
	hk.line(Vector3(30, 46, 30), Vector3(20, 56, 20), 1, "rope")
	k.details.append([hk, Vector3((bx + 1.5) * 0.1 - 0.4, 4.45 - 2.8, (z1 + 22.0) * 0.1 - 0.4), "hoist"])
	k.add_banner(Vector3((dx - 5) * 0.1, 3.0, (z1 + 1.3) * 0.1), 30, 70, 2, "fabric_teal")
	var g := k.add_lantern(Vector3((dx - 3) * 0.1, 2.9, (z1 + 2.3) * 0.1))
	k.add_lantern(Vector3((dx + 27) * 0.1, 2.9, (z1 + 2.3) * 0.1))
	k.flush_details(a)
	a.add_part("structure", k)
	a.add_light(g / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 1.1, 5.5)
	a.add_collider(Vector3i(x0 - 1, 0, z0 - 1), Vector3i(x1 + 1, 50, z1 + 1))
	a.add_collider(Vector3i(dx - 12, 0, z1 + 2), Vector3i(dx + 35, 4, z1 + 13))
	return a

# ------------------------------------------------------------------ tour de guet
static func _tower() -> VoxelAsset:
	var size := Vector3i(48, 120, 48)
	var a := _new_asset("watch_tower", "Tour de guet", size, "Tour ronde de pierre à galerie de bois, toit conique d'ardoise et balise d'éclat.")
	a.lod_ranges = [30.0, 80.0, 0.0]
	var k := BuildingKit.new(size, 806)
	var c := 24.0
	# Pied évasé, fût d'appareil de pierre, galerie, étage de crépi, toit conique.
	k.cyl_y(c, c, 0, 5, 20.5, "stone_ashlar_dark")
	k.cyl_y(c, c, 6, 54, 17.5, "stone_ashlar")
	for y in range(6, 55, 12):
		k.cyl_y(c, c, y, y, 18.4, "stone_ashlar", 16.0)
	k.cyl_y(c, c, 55, 58, 22.0, "wood_dark")
	k.cyl_y(c, c, 59, 59, 22.5, "copper", 19.0)
	k.cyl_y(c, c, 60, 76, 15.5, "plaster_cream")
	for i in 12:
		var ang := TAU * i / 12.0
		var px := int(c + cos(ang) * 20.5)
		var pz := int(c + sin(ang) * 20.5)
		k.box(px, 60, pz, px + 1, 68, pz + 1, "wood_planks")
	k.cyl_y(c, c, 69, 69, 21.5, "wood_dark", 20.0)
	k.cyl_y(c, c, 77, 78, 18.0, "wood_dark")
	for y in 36:
		var r := 19.0 - y * 0.5
		if r < 1.0:
			break
		k.cyl_y(c, c, 79 + y, 79 + y, r, "tiles_slate")
	k.cyl_y(c, c, 79, 80, 19.5, "tiles_slate", 17.0)
	k.box(23, 112, 23, 24, 117, 24, "copper")
	k.crystal(Vector3(23.5, 113, 23.5), 7.0, 1.6, Vector2.ZERO, "crystal_blue", 0.4)
	# Porte (face +z), fenêtres, meurtrières.
	var kx := int(c) - 5
	k.box(kx, 6, 40, kx + 9, 25, 41, "wood_planks")
	k.box(kx - 2, 6, 40, kx - 1, 27, 42, "stone_light")
	k.box(kx + 10, 6, 40, kx + 11, 27, 42, "stone_light")
	k.box(kx - 2, 26, 40, kx + 11, 28, 42, "stone_light")
	for x in range(kx, kx + 10, 3):
		k.box(x, 7, 42, x, 24, 42, "wood_dark")
	k.box(kx + 4, 12, 43, kx + 5, 15, 43, "copper")
	for ang in [0.0, 1.9, 3.9, 5.2]:
		var px := int(c + cos(ang) * 17.5)
		var pz := int(c + sin(ang) * 17.5)
		k.box(px, 30, pz, px + 1, 38, pz + 1, "window_lit" if ang > 3.0 else "window_glass")
	for ang in [0.6, 2.6, 4.6]:
		var px := int(c + cos(ang) * 15.5)
		var pz := int(c + sin(ang) * 15.5)
		k.box(px, 64, pz, px + 2, 72, pz + 1, "window_lit")
	k.add_banner(Vector3(c * 0.1 + 0.85, 5.2, 4.35), 36, 90, 2, "fabric_blue")
	var g := k.add_lantern(Vector3(c * 0.1 - 0.9, 2.3, 4.45))
	k.flush_details(a)
	a.add_part("structure", k)
	a.add_light(g / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 1.0, 4.5)
	a.add_light(Vector3(24, 117, 24), Color("7fd2ff"), 1.4, 9.0)
	a.add_collider(Vector3i(6, 0, 6), Vector3i(41, 80, 43))
	return a
