@tool
extends RefCounted
## Port : embarcadère de bois sur pilotis et bateau volant (coque, mâts, voiles de toile à losange,
## moteur à éclat). Grille de 10 cm pour les grandes formes, 2 cm pour voiles et ornements.

static func build(args: Dictionary) -> VoxelAsset:
	match String(args["id"]):
		"pier": return _pier()
		"sky_ship": return _ship()
	return null

# ------------------------------------------------------------------ embarcadère (3 × 10 m)
static func _pier() -> VoxelAsset:
	var a := VoxelAsset.new("pier", "Embarcadère", Vector3i(15, 20, 50), "Tablier de planches sur pilotis contreventés, garde-corps de cordes et bittes.")
	a.cell_m = VoxelGrid.STRUCTURE_SIZE
	a.category = "building"
	a.ground_y = 3.0
	a.lod_factors = [2, 4]
	a.lod_ranges = [30.0, 80.0, 0.0]
	var k := BuildingKit.new(Vector3i(30, 40, 100), 811)
	# Longerons, tablier (planches en travers), rives.
	for x in [3, 24]:
		k.box(x, 24, 0, x + 2, 27, 99, "wood_dark")
	k.planks(0, 28, 0, 29, 29, 99, 0, 2, 3, ["wood_planks", "wood_honey", "wood_planks", "wood_dark"], false)
	k.box(0, 28, 0, 1, 30, 99, "wood_dark")
	k.box(28, 28, 0, 29, 30, 99, "wood_dark")
	# Pilotis tous les 2,5 m, contreventement en croix, bagues de cuivre.
	for z in range(4, 100, 25):
		for x in [2, 25]:
			k.box(x, 0, z, x + 2, 27, z + 2, "wood_planks")
			k.box(x - 1, 22, z - 1, x + 3, 23, z + 3, "copper")
			k.box(x - 1, 28, z - 1, x + 3, 31, z + 3, "wood_dark")
		k.line(Vector3(3, 4, z + 1), Vector3(26, 22, z + 1), 1, "wood_dark")
		k.line(Vector3(26, 4, z + 1), Vector3(3, 22, z + 1), 1, "wood_dark")
	# Garde-corps : poteaux, lisse de bois, corde.
	for z in range(4, 100, 12):
		for x in [1, 27]:
			k.box(x, 30, z, x + 1, 39, z + 1, "wood_planks")
	for x in [1, 27]:
		k.box(x, 37, 2, x + 1, 38, 98, "wood_planks")
		k.box(x, 33, 2, x + 1, 33, 98, "rope")
	k.moss_top(0, 0, 29, 40, 0.0, 1)
	var g1 := k.add_lantern(Vector3(0.45, 4.35, 2.5))
	var g2 := k.add_lantern(Vector3(2.55, 4.35, 9.5))
	k.flush_details(a)
	a.add_part("structure", k)
	a.add_light(g1 / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 0.9, 5.0)
	a.add_light(g2 / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 0.9, 5.0)
	a.add_collider(Vector3i(0, 24, 0), Vector3i(29, 30, 99))
	return a

# ------------------------------------------------------------------ bateau volant
static func _ship() -> VoxelAsset:
	var a := VoxelAsset.new("sky_ship", "Bateau volant", Vector3i(52, 60, 24), "Voilier des nuages : coque de bois et de cuivre, cabine arrière, deux mâts, voiles à losange, moteur à éclat.")
	a.cell_m = VoxelGrid.STRUCTURE_SIZE
	a.category = "vehicle"
	a.lod_factors = [2, 4]
	a.lod_ranges = [30.0, 80.0, 0.0]
	var L := 100                 # longueur en cellules de 10 cm
	var k := BuildingKit.new(Vector3i(104, 90, 48), 821)
	var zc := 24.0
	# Coque : sections transversales paramétrées (carène, pont relevé aux extrémités).
	for x in L:
		var t := float(x) / (L - 1)
		var beam := 12.0 * pow(sin(minf(t * 1.04, 1.0) * PI * 0.97 + 0.12), 0.7)
		if t > 0.8:
			beam *= 1.0 - (t - 0.8) * 2.2
		beam = maxf(beam, 1.5)
		var keel := 8.0 + 11.0 * pow(absf(t - 0.42) * 1.9, 2.2)
		var deck := 27.0 + 9.0 * pow(absf(t - 0.4) * 1.8, 2.0)
		for z in range(int(zc - beam), int(zc + beam) + 1):
			var zr := absf(z + 0.5 - zc) / beam
			var bot := keel + pow(zr, 2.2) * (deck - keel) * 0.85
			for y in range(int(bot), int(deck) + 1):
				var key := "wood_planks"
				if y < keel + 8:
					key = "wood_dark"
				elif y >= int(deck) - 1:
					key = "copper"
				elif int(y / 3) % 2 == 0:
					key = "wood_honey"
				var shell := zr > 0.88 or y < int(bot) + 2 or x < 2 or x > L - 3
				if shell or y >= int(deck) - 2:
					k.volume.set_voxel(x, y, z, k.mat(key))
				else:
					k.volume.set_voxel(x, y, z, k.mat("wood_dark"))
		# Pont : planches, légèrement en retrait du plat-bord.
		for z in range(int(zc - beam) + 2, int(zc + beam) - 1):
			k.volume.set_voxel(x, int(deck) - 1, z, k.mat("wood_planks" if (x / 3 + z / 4) % 2 == 0 else "wood_honey"))
	# Bande de cuivre sous le plat-bord et proue ferrée.
	k.box(L - 6, 22, 20, L - 1, 38, 27, "copper")
	k.box(L - 2, 30, 18, L + 3, 42, 29, "wood_dark")
	# Cabine arrière : murs de planches, fenêtres éclairées, toit de bardeaux.
	var cx0 := 4
	var cx1 := 26
	k.box(cx0, 27, 14, cx1, 40, 33, "wood_planks")
	k.half_timber(2, 33, 1, cx0 + 1, cx1 - 1, 28, 40, 7, 0.0)
	k.half_timber(2, 14, -1, cx0 + 1, cx1 - 1, 28, 40, 7, 0.0)
	k.window(2, 33, 1, cx0 + 4, 31, 4, 5, true, false)
	k.window(2, 33, 1, cx0 + 14, 31, 4, 5, true, false)
	k.window(0, cx0, -1, 20, 31, 4, 5, true, false)
	k.gable_roof(cx0 - 2, cx1 + 2, 12, 35, 41, "shingle_wood", "wood_planks", 1, 2, cx0, cx1)
	k.chimney(cx1 - 6, 18, 41, 50, 3, 3)
	# Gaillard avant (petit pont surélevé) et rambardes.
	k.box(66, 32, 17, 84, 34, 31, "wood_planks")
	for x in range(66, 85, 6):
		for z in [17, 30]:
			k.box(x, 29, z, x, 33, z, "wood_dark")
	for z in [17, 30]:
		k.box(66, 34, z, 84, 34, z, "copper")
	for x in range(30, 66, 5):
		for z in [12, 35]:
			var deck := int(27.0 + 9.0 * pow(absf(x / float(L - 1) - 0.4) * 1.8, 2.0))
			k.box(x, deck, z, x, deck + 4, z, "wood_planks")
			k.set_if_empty(x, deck + 5, z, "copper")
	# Mâts, vergues, bastingage.
	k.box(46, 27, 23, 48, 85, 25, "wood_planks")
	k.box(46, 86, 23, 48, 87, 25, "copper")
	k.box(24, 61, 23, 70, 62, 25, "wood_dark")           # grande vergue
	k.box(74, 27, 23, 75, 70, 24, "wood_planks")         # mât avant
	k.box(62, 55, 23, 87, 56, 24, "wood_dark")
	k.line(Vector3(104, 40, 24), Vector3(88, 34, 24), 1, "wood_planks")   # beaupré
	# Haubans de corde.
	for z in [14, 34]:
		k.line(Vector3(47, 80, 24), Vector3(52, 30, z), 1, "rope")
		k.line(Vector3(47, 80, 24), Vector3(40, 30, z), 1, "rope")
		k.line(Vector3(74.5, 66, 24), Vector3(76, 33, z), 1, "rope")
	k.line(Vector3(47, 86, 24), Vector3(100, 41, 24), 1, "rope")
	# Ailerons de stabilisation (cuivre et bois) de part et d'autre.
	for side in [-1, 1]:
		for i in 18:
			var zz: int = 24 + side * (12 + i)
			var yy: int = 33 - i / 3
			k.box(52 - i, yy, zz, 62 - i, yy, zz, "wood_honey" if i % 2 == 0 else "wood_planks")
			k.box(52 - i, yy, zz, 52 - i, yy, zz, "copper")
	# Gouvernail et moteur à éclat à l'arrière.
	k.box(0, 20, 22, 2, 38, 25, "wood_dark")
	k.add_banner(Vector3(0.5, 3.9, 2.0), 40, 90, 0, "fabric_blue")
	var g := k.add_lantern(Vector3(1.0, 4.2, 2.45))
	var g2 := k.add_lantern(Vector3(9.5, 3.9, 1.35))
	k.flush_details(a)
	a.add_part("hull", k)
	# Moteur : cage de cuivre et cristal bleu (matériau de cristal animé).
	var eng := AssetKit.new(Vector3i(40, 56, 40), 822)
	eng.cyl_y(20, 20, 0, 3, 14.0, "copper", 10.0)
	eng.cyl_y(20, 20, 40, 43, 14.0, "copper", 10.0)
	for i in 6:
		var ang := TAU * i / 6.0
		eng.line(Vector3(20 + cos(ang) * 12.5, 3, 20 + sin(ang) * 12.5), Vector3(20 + cos(ang) * 12.5, 40, 20 + sin(ang) * 12.5), 2, "copper")
	eng.crystal(Vector3(20, 6, 20), 34.0, 7.0, Vector2.ZERO, "crystal_blue", 0.36)
	a.add_part("engine", eng, Vector3i(int(4.8 / 0.02) - 20, 0, int(2.4 / 0.02) - 20), "crystal", "float", 0.02)
	# Voiles : toile crème à bandes et losange, pièces de tissu (balancement), pixels de 2 cm.
	var sail_w := 230
	var sail_h := 210
	var s1 := AssetKit.new(Vector3i(sail_w, sail_h, 4), 823)
	for y in sail_h:
		for x in sail_w:
			var bulge := int(round(2.0 * sin(PI * x / sail_w) * (0.4 + 0.6 * y / sail_h)))
			var key := "fabric_cream"
			if (y / 26) % 2 == 1:
				key = "fabric_blue" if y > sail_h * 0.52 else "fabric_cream"
			if y < 4 or x < 3 or x > sail_w - 4:
				key = "fabric_cream"
			if y >= sail_h - 5:
				key = "fabric_blue" if (x / 2) % 2 == 0 else "fabric_cream"
			s1.set_cell(x, sail_h - 1 - y, 1 + clampi(bulge, 0, 2), key)
	# Losange d'ÉCLATS au centre.
	var mx := sail_w / 2
	var my := sail_h / 2
	for dy in range(-44, 45):
		for dx in range(-44, 45):
			var d := absi(dx) + absi(dy)
			if d <= 44 and d >= 38:
				s1.set_cell(mx + dx, my + dy, 2, "fabric_cream")
			elif d <= 8:
				s1.set_cell(mx + dx, my + dy, 2, "fabric_teal")
			elif d >= 20 and d <= 22:
				s1.set_cell(mx + dx, my + dy, 2, "fabric_cream")
	a.add_part("main_sail", s1, Vector3i(int(2.4 / 0.02), int(6.1 / 0.02) - sail_h, int(2.36 / 0.02)), "cloth", "", 0.02)
	var s2 := AssetKit.new(Vector3i(130, 120, 4), 824)
	for y in 120:
		for x in 130:
			var key := "fabric_cream" if (y / 20) % 2 == 0 else "fabric_teal"
			if y < 3 or x < 3 or x > 126:
				key = "fabric_cream"
			s2.set_cell(x, 119 - y, 1 + int(round(1.5 * sin(PI * x / 130.0))), key)
	for dy in range(-22, 23):
		for dx in range(-22, 23):
			var d := absi(dx) + absi(dy)
			if d <= 22 and d >= 18:
				s2.set_cell(65 + dx, 60 + dy, 2, "fabric_blue")
	a.add_part("fore_sail", s2, Vector3i(int(6.3 / 0.02), int(5.5 / 0.02) - 120, int(2.35 / 0.02)), "cloth", "", 0.02)
	a.add_light(g / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 1.0, 5.0)
	a.add_light(g2 / VoxelGrid.STRUCTURE_SIZE, Color("ffb860"), 0.9, 4.0)
	a.add_light(Vector3(10, 28, 24), Color("6cc8ff"), 1.2, 6.0)
	a.add_collider(Vector3i(0, 8, 12), Vector3i(100, 40, 36))
	return a
