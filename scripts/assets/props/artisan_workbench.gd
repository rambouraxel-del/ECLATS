@tool
extends RefCounted
## Asset 1 — Établi d'artisan. 2,00 × 1,00 m, plan de travail à 0,94 m, râtelier à 1,80 m.
## Inspiré de la planche 4 (Workbench, Tool rack) : pieds sur blocs de pierre claire,
## capuchons et équerres en cuivre, tiroirs, étagère basse garnie, panneau à outils,
## chemin de table bleu, plantes en pot, bougie.

static func build() -> VoxelAsset:
	var asset := VoxelAsset.new("artisan_workbench", "Établi d'artisan", Vector3i(10, 10, 5),
			"Grand établi en bois renforcé de cuivre, tiroirs, outils et rangements.")
	var k := AssetKit.new(Vector3i(100, 100, 50), 101)
	var top_y := 46  # dessus du plateau (0,94 m)

	# Pieds : blocs de pierre claire puis jambes de bois chanfreinées.
	var legs := [Vector2i(2, 2), Vector2i(88, 2), Vector2i(2, 37), Vector2i(88, 37)]
	for l in legs:
		k.stone_block(l.x - 2, 0, l.y - 2, l.x + 11, 7, l.y + 11, 5)
		k.post(l.x, l.y, 8, top_y - 6, 10, "wood_planks")
		k.copper_collar(l.x, l.y, 8, 9, 10)
		k.corner_plate(l.x if l.x < 50 else l.x + 9, l.y if l.y < 25 else l.y + 9,
				1 if l.x < 50 else -1, 1 if l.y < 25 else -1, top_y - 12, top_y - 6, 6)
	# Traverses basses avec tenons apparents et chevilles.
	for z in [5, 40]:
		k.box(0, 18, z, 99, 21, z + 3, "wood_dark")
		for x in [0, 99]:
			k.set_cell(x, 19, z + 1, "wood_light")
			k.set_cell(x, 20, z + 2, "wood_light")
	k.box(5, 18, 9, 7, 21, 39, "wood_dark")
	k.box(92, 18, 9, 94, 21, 39, "wood_dark")
	# Étagère basse en planches.
	k.planks(12, 22, 6, 87, 23, 43, 0, 2, 8)

	# Ceinture sous le plateau + trois tiroirs en façade.
	k.box(2, top_y - 11, 4, 97, top_y - 6, 45, "wood_dark")
	for i in 3:
		var x0 := 14 + i * 25
		var x1 := x0 + 21
		k.box(x0, top_y - 12, 46, x1, top_y - 5, 46, "wood_dark")         # cadre
		k.box(x0 + 1, top_y - 11, 47, x1 - 1, top_y - 6, 47, "wood_honey")  # façade
		var hx := (x0 + x1) / 2
		k.box(hx - 3, top_y - 9, 48, hx + 3, top_y - 8, 48, "copper")      # poignée
		k.set_cell(hx - 3, top_y - 9, 49, "copper")
		k.set_cell(hx + 3, top_y - 9, 49, "copper")
		k.set_cell(hx, top_y - 7, 48, "iron_dark")                         # entrée de serrure

	# Plateau épais en planches, chant avant sombre, équerres de cuivre aux coins.
	k.planks(0, top_y - 5, 0, 99, top_y, 48, 0, 2, 10)
	k.box(0, top_y - 5, 48, 99, top_y - 3, 48, "wood_dark")
	for c in [Vector2i(0, 0), Vector2i(99, 0), Vector2i(0, 48), Vector2i(99, 48)]:
		k.corner_plate(c.x, c.y, 1 if c.x == 0 else -1, 1 if c.y == 0 else -1, top_y - 5, top_y, 7)

	# Râtelier arrière : montants, traverse haute, panneau, étagère.
	for x in [2, 92]:
		k.post(x, 1, top_y + 1, 86, 6, "wood_planks")
		k.copper_cap(x, 1, 87, 6, 3)
	k.planks(2, 80, 1, 97, 86, 6, 0, 1, 4, ["wood_dark", "wood_planks"], false)
	k.planks(8, top_y + 1, 2, 91, 79, 3, 1, 0, 9, ["wood_planks", "wood_honey", "wood_dark"])
	k.box(8, 64, 4, 91, 65, 13, "wood_honey")      # étagère
	for x in [10, 89]:
		k.line(Vector3(x, 63, 4.5), Vector3(x, 56, 4.5), 1, "copper")  # consoles
		k.line(Vector3(x, 63, 4.5), Vector3(x, 63, 11.5), 1, "copper")

	# Outils accrochés au panneau (z = 4).
	# Marteau.
	k.box(14, 52, 4, 15, 63, 4, "wood_honey")
	k.box(11, 60, 4, 18, 62, 5, "iron")
	k.set_cell(14, 58, 5, "copper")
	# Scie : lame dentée + poignée.
	k.box(22, 50, 4, 33, 57, 4, "iron")
	for x in range(22, 34, 2):
		k.set_cell(x, 50, 4, "")
	k.box(33, 53, 4, 37, 58, 5, "wood_dark")
	k.set_cell(35, 55, 4, "")
	# Ciseaux à bois.
	for i in 3:
		var x := 42 + i * 4
		k.box(x, 55, 4, x + 1, 60, 5, "wood_red")
		k.box(x, 49, 4, x + 1, 54, 4, "iron")
		k.set_cell(x, 60, 6, "copper")
	k.box(41, 61, 5, 54, 61, 6, "copper")  # porte-outils
	# Clé et compas.
	k.box(59, 49, 4, 60, 61, 4, "iron")
	k.box(57, 59, 4, 62, 62, 4, "iron")
	k.set_cell(59, 61, 4, "")
	k.set_cell(60, 60, 4, "")
	k.line(Vector3(68, 62, 4.5), Vector3(65, 50, 4.5), 1, "brass")
	k.line(Vector3(68, 62, 4.5), Vector3(71, 50, 4.5), 1, "brass")
	k.box(67, 62, 4, 69, 63, 5, "copper")
	# Rouleau de corde accroché.
	for a in 12:
		var t := TAU * a / 12.0
		k.set_cell(int(80 + cos(t) * 4), int(56 + sin(t) * 4), 4, "rope")
		k.set_cell(int(80 + cos(t) * 3), int(56 + sin(t) * 3), 5, "rope")
	k.box(79, 60, 4, 81, 62, 6, "copper")

	# Étagère du râtelier : flacons, pot, éclat.
	for i in 4:
		var x := 14 + i * 6
		var key: String = ["glass_green", "potion_violet", "glass_green", "crystal_deep"][i]
		k.box(x, 66, 7, x + 3, 71, 10, key)
		k.box(x + 1, 72, 8, x + 2, 73, 9, "wood_light")  # bouchon
	k.box(44, 66, 6, 51, 72, 11, "terracotta")
	k.box(45, 73, 7, 50, 73, 10, "terracotta")
	k.bush(Vector3(48, 76, 9), Vector3(5, 4, 4), "flower_white", 0.15)
	k.crystal(Vector3(62, 66, 9), 9.0, 2.2, Vector2(0.15, 0.0), "crystal_blue")
	k.crystal(Vector3(65, 66, 8), 6.0, 1.6, Vector2(-0.1, 0.1), "crystal_blue")

	# Sur le plateau : plan, bougie, rabot, planche, pot de fleurs, boîte de clous.
	var y := top_y + 1
	k.box(30, y, 14, 55, y, 32, "paper")
	k.line(Vector3(33, y, 18), Vector3(47, y, 27), 1, "wood_dark")
	k.line(Vector3(36, y, 26), Vector3(50, y, 17), 1, "fabric_blue")
	k.box(40, y, 21, 43, y, 23, "wood_red")
	k.box(5, y, 8, 14, y + 1, 17, "copper")          # coupelle
	k.box(8, y + 2, 11, 11, y + 8, 14, "paper")       # bougie
	k.box(9, y + 9, 12, 10, y + 11, 13, "lantern_glow")
	k.box(62, y, 30, 75, y + 4, 35, "wood_honey")     # rabot
	k.box(66, y + 5, 31, 70, y + 7, 34, "wood_dark")
	k.box(63, y, 29, 74, y, 29, "iron")
	k.planks(20, y, 36, 58, y + 1, 41, 0, 2, 3, ["wood_light"], false)
	for i in 6:
		k.set_cell(60 + i * 2, y, 40 - i % 2, "wood_light")  # copeaux
	k.box(84, y, 6, 93, y + 7, 15, "terracotta")
	k.box(85, y + 8, 7, 92, y + 8, 14, "terracotta")
	k.bush(Vector3(88.5, y + 13, 10.5), Vector3(7, 6, 6), "flower_white", 0.12)
	k.box(80, y, 26, 87, y + 3, 32, "wood_dark")
	k.box(81, y + 3, 27, 86, y + 3, 31, "copper")

	# Chemin de table bleu drapé sur le plateau, qui tombe devant.
	k.drape(60, 16, [Vector2i(top_y + 1, 18), Vector2i(top_y + 1, 49), Vector2i(top_y - 22, 49)], 3)

	# Sous l'étagère basse : caisse cerclée de cuivre, blocs de pierre, seau.
	k.planks(18, 24, 14, 39, 37, 33, 0, 1, 5, ["wood_planks", "wood_honey"])
	for c in [Vector2i(18, 14), Vector2i(39, 14), Vector2i(18, 33), Vector2i(39, 33)]:
		k.box(c.x, 24, c.y, c.x, 37, c.y, "copper")
	k.stone_block(46, 24, 20, 57, 31, 33, 3)
	k.stone_block(48, 32, 22, 56, 37, 31, 3)
	for a in 16:
		var t := TAU * a / 16.0
		for yy in range(24, 34):
			k.set_cell(int(74 + cos(t) * 6), yy, int(26 + sin(t) * 6), "wood_planks" if yy != 30 else "copper")
	k.box(70, 24, 22, 78, 24, 30, "wood_dark")

	# Lierre qui s'échappe de la plante du râtelier.
	k.ivy(Vector3i(92, 75, 9), 22, Vector3i(1, 0, 0), 0.1)

	asset.add_part("structure", k)
	asset.add_light(Vector3(9.5, y + 11, 12.5), Color("ffc277"), 0.7, 3.0)
	asset.add_collider(Vector3i(0, 0, 0), Vector3i(99, top_y, 48))
	asset.add_collider(Vector3i(2, top_y + 1, 1), Vector3i(97, 86, 6))
	return asset
