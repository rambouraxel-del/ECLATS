@tool
class_name BuildingKit
extends AssetKit
## Outils de construction de bâtiments à la grille de 10 cm (5 pixels de texture de 2 cm par voxel).
## Les murs sont lisses : les joints de pierre, le crépi, les tuiles et le bois sont dessinés par
## les pixels du shader. Seuls les volumes (poutres, encadrements, volets, toits) sont en voxels.
## Les détails fins (bannières, lanternes, bacs à fleurs) sont des pièces séparées de 2 cm.
## Orientation : la façade principale regarde +z. Face = Vector2i-like (axe, signe) :
##   axe 0 = x, axe 2 = z ; signe +1 / -1 = côté sortant.

var details: Array = []   # [AssetKit (2 cm), position (m), nom]

func _init(size: Vector3i, seed := 1) -> void:
	super(size, seed)

## Cellule de mur : `p` = plan du mur (dernier voxel plein), `sign` = côté extérieur,
## `u` le long du mur, `v` la hauteur, `layer` = 0 (dans le mur), 1.. (en saillie).
func wc(axis: int, p: int, sign: int, u: int, v: int, layer := 0) -> Vector3i:
	if axis == 2:
		return Vector3i(u, v, p + sign * layer)
	return Vector3i(p + sign * layer, v, u)

func wset(axis: int, p: int, sign: int, u: int, v: int, layer: int, key: String) -> void:
	var c := wc(axis, p, sign, u, v, layer)
	volume.set_voxel(c.x, c.y, c.z, mat(key))

func wbox(axis: int, p: int, sign: int, u0: int, v0: int, u1: int, v1: int, layer: int, key: String, thick := 1) -> void:
	for l in range(layer, layer + thick):
		for v in range(v0, v1 + 1):
			for u in range(u0, u1 + 1):
				wset(axis, p, sign, u, v, l, key)

## Ouvre une fenêtre : cadre de bois en saillie, vitre (éventuellement éclairée), appui de pierre,
## volets de planches à charnières de cuivre, bac à fleurs (pièce de détail de 2 cm).
func window(axis: int, p: int, sign: int, u: int, v: int, w := 8, h := 10, lit := false, shutters := true, flowers := false) -> void:
	wbox(axis, p, sign, u, v, u + w - 1, v + h - 1, 0, "window_lit" if lit else "window_glass")
	# Cadre (en saillie d'une cellule) et croisillon.
	wbox(axis, p, sign, u - 1, v - 1, u + w, v - 1, 1, "wood_dark")
	wbox(axis, p, sign, u - 1, v + h, u + w, v + h, 1, "wood_dark")
	wbox(axis, p, sign, u - 1, v, u - 1, v + h - 1, 1, "wood_dark")
	wbox(axis, p, sign, u + w, v, u + w, v + h - 1, 1, "wood_dark")
	wbox(axis, p, sign, u + w / 2, v, u + w / 2, v + h - 1, 1, "wood_dark")
	wbox(axis, p, sign, u, v + h / 2, u + w - 1, v + h / 2, 1, "wood_dark")
	# Appui et linteau de pierre.
	wbox(axis, p, sign, u - 2, v - 2, u + w + 1, v - 2, 1, "stone_ashlar", 2)
	wbox(axis, p, sign, u - 2, v + h + 1, u + w + 1, v + h + 1, 1, "stone_ashlar", 1)
	if shutters:
		for side in [-1, 1]:
			var us := u - 5 if side < 0 else u + w + 2
			wbox(axis, p, sign, us, v - 1, us + 2, v + h, 1, "wood_planks")
			wbox(axis, p, sign, us, v + 1, us + 2, v + 1, 2, "wood_dark")
			wbox(axis, p, sign, us, v + h - 2, us + 2, v + h - 2, 2, "wood_dark")
			wbox(axis, p, sign, us + 1, v + h / 2 - 1, us + 1, v + h / 2 + 2, 2, "wood_honey")   # découpe en losange
			wset(axis, p, sign, us + (2 if side < 0 else 0), v + 1, 2, "copper")
	if flowers:
		var c := wc(axis, p, sign, u - 1, v - 6, 2)
		_flower_box(c, axis, w + 2)

func _flower_box(c: Vector3i, axis: int, length_cells: int) -> void:
	var d := AssetKit.new(Vector3i(length_cells * 5 + 4, 22, 14), c.x * 31 + c.z * 17 + 3)
	d.planks(0, 0, 0, length_cells * 5 + 3, 9, 8, 0, 2, 4, ["wood_planks", "wood_honey"], true)
	d.box(1, 9, 1, length_cells * 5 + 2, 9, 7, "potting_soil")
	d.bush(Vector3(length_cells * 2.5 + 2, 13, 4), Vector3(length_cells * 2.4, 6, 5), ["flower_white", "flower_pink", "flower_yellow"][(c.x + c.z) % 3], 0.2)
	d.ivy(Vector3i(3, 9, 7), 10, Vector3i(1, 0, 0), 0.1)
	var pos := Vector3(c) * VoxelGrid.STRUCTURE_SIZE
	if axis == 0:
		# Boîte tournée : longueur le long de z. On reconstruit simplement un volume transposé.
		var t := AssetKit.new(Vector3i(d.volume.size.z, d.volume.size.y, d.volume.size.x), 1)
		for y in d.volume.size.y:
			for z in d.volume.size.z:
				for x in d.volume.size.x:
					t.volume.data[t.volume.index_of(z, y, x)] = d.volume.get_voxel(x, y, z)
		d = t
	details.append([d, pos + Vector3(-0.02, 0.0, 0.0) if axis == 2 else pos, "flower_box"])

## Porte à double vantail de planches, encadrement de pierre, ferrures de cuivre, marche.
func door(axis: int, p: int, sign: int, u: int, w := 10, h := 20, arched := false) -> void:
	wbox(axis, p, sign, u, 0, u + w - 1, h - 1, 0, "wood_planks")
	# Encadrement de pierre en saillie, linteau, seuil.
	wbox(axis, p, sign, u - 2, 0, u - 1, h + 1, 1, "stone_ashlar", 1)
	wbox(axis, p, sign, u + w, 0, u + w + 1, h + 1, 1, "stone_ashlar", 1)
	wbox(axis, p, sign, u - 2, h, u + w + 1, h + 1, 1, "stone_ashlar", 2)
	wbox(axis, p, sign, u - 3, 0, u + w + 2, 1, 2, "stone_ashlar_dark", 2)
	# Lattes verticales, traverses de fer, poignée de cuivre.
	for x in range(u, u + w, 3):
		wbox(axis, p, sign, x, 1, x, h - 2, 1, "wood_dark")
	wbox(axis, p, sign, u, 4, u + w - 1, 5, 1, "iron_dark")
	wbox(axis, p, sign, u, h - 6, u + w - 1, h - 5, 1, "iron_dark")
	wbox(axis, p, sign, u + w / 2 - 1, 0, u + w / 2, h - 1, 1, "wood_dark")
	wbox(axis, p, sign, u + w / 2 - 3, 9, u + w / 2 - 3, 11, 2, "copper")
	wbox(axis, p, sign, u + w / 2 + 2, 9, u + w / 2 + 2, 11, 2, "copper")

## Colombage : poteaux, sablière et lisse en saillie d'une cellule, quelques croix de Saint-André.
func half_timber(axis: int, p: int, sign: int, u0: int, u1: int, v0: int, v1: int, spacing := 14, diagonals := 0.35, key := "wood_dark") -> void:
	wbox(axis, p, sign, u0, v0, u1, v0 + 1, 1, key)
	wbox(axis, p, sign, u0, v1 - 1, u1, v1, 1, key)
	var u := u0
	while u <= u1:
		wbox(axis, p, sign, u, v0, u + 1, v1, 1, key)
		if u + spacing <= u1 and rng.randf() < diagonals:
			var ua := Vector3(wc(axis, p, sign, u + 2, v0 + 2, 1))
			var ub := Vector3(wc(axis, p, sign, u + spacing - 1, v1 - 2, 1))
			if rng.randf() < 0.5:
				ua = Vector3(wc(axis, p, sign, u + spacing - 1, v0 + 2, 1))
				ub = Vector3(wc(axis, p, sign, u + 2, v1 - 2, 1))
			line(ua, ub, 2, key)
		u += spacing
	wbox(axis, p, sign, u1 - 1, v0, u1, v1, 1, key)

## Chaînage d'angle en pierre de taille : assises alternées, pierres en saillie d'une cellule.
## (x0, z0) et (x1, z1) = cellules d'angle du mur.
func quoins(x0: int, x1: int, z0: int, z1: int, y0: int, y1: int, key := "stone_ashlar") -> void:
	for y in range(y0, y1 + 1):
		var long_x := ((y - y0) / 3) % 2 == 0
		for c in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
			var sx := 1 if c.x == x0 else -1
			var sz := 1 if c.y == z0 else -1
			var nx := 5 if long_x else 3
			var nz := 3 if long_x else 5
			for i in nx:
				volume.set_voxel(c.x + sx * i, y, c.y - sz, mat(key))
			for i in nz:
				volume.set_voxel(c.x - sx, y, c.y + sz * i, mat(key))

func set_cell_key(x: int, y: int, z: int, key: String) -> void:
	volume.set_voxel(x, y, z, mat(key))

## Toit à deux pans (faîtage le long de x). La pente monte de `rise` cellules pour `run` cellules.
## Le toit couvre [x0, x1] × [z0, z1], épaisseur 2 ; le pignon est comblé de mur.
func gable_roof(x0: int, x1: int, z0: int, z1: int, y0: int, roof_key: String, gable_key: String, rise := 2, run := 3, wall_x0 := -1, wall_x1 := -1) -> int:
	var half := (z1 - z0) / 2
	var top_y := y0
	for zr in range(0, half + 1):
		var y := y0 + (zr * rise) / run
		top_y = maxi(top_y, y + 1)
		for zz in [z0 + zr, z1 - zr]:
			box(x0, y, zz, x1, y + 1, zz, roof_key)
			# Marche d'appui sous la tuile (empêche toute transparence).
			if y > y0:
				box(x0, y - 1, zz, x1, y - 1, zz, roof_key)
	# Pignon : triangle de mur sous la pente, entre les murs latéraux.
	if wall_x0 >= 0:
		for zr in range(0, half + 1):
			var y := y0 + (zr * rise) / run
			for zz in [z0 + zr, z1 - zr]:
				for x in [wall_x0, wall_x1]:
					box(x, y0 - 1, zz, x, y - 1, zz, gable_key)
	# Faîtage de cuivre.
	var ridge_y := y0 + (half * rise) / run
	box(x0, ridge_y + 2, z0 + half - 1, x1, ridge_y + 2, z0 + half + 1, "copper")
	# Planches de rive (bords de pignon) en bois sombre, tuiles de rive.
	for zr in range(0, half + 1):
		var y := y0 + (zr * rise) / run
		for zz in [z0 + zr, z1 - zr]:
			box(x0, y - 1, zz, x0, y, zz, "wood_dark")
			box(x1, y - 1, zz, x1, y, zz, "wood_dark")
	return top_y

## Cheminée de pierre taillée à chapeau de cuivre.
func chimney(x: int, z: int, y0: int, y1: int, w := 6, d := 6) -> void:
	box(x, y0, z, x + w - 1, y1, z + d - 1, "stone_ashlar")
	box(x - 1, y1 - 1, z - 1, x + w, y1, z + d, "stone_ashlar_dark")
	box(x, y1 + 1, z, x + w - 1, y1 + 1, z + d - 1, "stone_ashlar")
	box(x + 1, y1 + 1, z + 1, x + w - 2, y1 + 1, z + d - 2, "ember")
	box(x - 1, y1 + 2, z - 1, x + w, y1 + 2, z + d, "copper")
	box(x + 1, y1 + 3, z + 1, x + w - 2, y1 + 3, z + d - 2, "copper")

## Consoles de bois sous un encorbellement.
func corbels(x0: int, x1: int, z: int, y: int, spacing := 10) -> void:
	var x := x0 + 3
	while x < x1 - 2:
		box(x, y - 3, z - 3, x + 1, y - 1, z - 1, "wood_dark")
		box(x, y - 2, z - 2, x + 1, y - 2, z + 0, "wood_dark")
		box(x, y - 1, z - 3, x + 1, y - 1, z - 3, "copper")
		x += spacing

## Ajoute une pièce de détail de 2 cm à l'asset (position en mètres, repère de l'asset).
func flush_details(asset: VoxelAsset) -> void:
	var by_name := {}
	for d in details:
		var kit: AssetKit = d[0]
		var pos: Vector3 = d[1]
		var off := Vector3i(roundi(pos.x / VoxelGrid.DETAIL_SIZE), roundi(pos.y / VoxelGrid.DETAIL_SIZE), roundi(pos.z / VoxelGrid.DETAIL_SIZE))
		var idx: int = by_name.get(d[2], 0)
		by_name[d[2]] = idx + 1
		asset.add_part("%s_%d" % [d[2], idx], kit, off, "props", "", VoxelGrid.DETAIL_SIZE)

## Bannière de 2 cm (pièce de détail) suspendue en (x, y_top, z) mètres, plan z (face = +z) ou x.
func add_banner(pos_m: Vector3, w_cm := 36, h_cm := 76, plane := 2, base := "fabric_blue") -> void:
	var w := w_cm / 2
	var h := h_cm / 2
	var d := AssetKit.new(Vector3i(w + 2, h + 4, 4), int(pos_m.x * 100 + pos_m.z * 7))
	d.banner(1, h + 2, 1, w, h, 2, 5, base)
	d.box(0, h + 2, 0, w + 1, h + 3, 2, "copper")
	var q := Vector3(pos_m.x, pos_m.y - (h + 3) * VoxelGrid.DETAIL_SIZE, pos_m.z)
	if plane == 0:
		var t := AssetKit.new(Vector3i(4, h + 4, w + 2), 1)
		for y in d.volume.size.y:
			for z in d.volume.size.z:
				for x in d.volume.size.x:
					t.volume.data[t.volume.index_of(z, y, x)] = d.volume.get_voxel(x, y, z)
		d = t
	details.append([d, q, "banner"])

## Lanterne de cuivre de 2 cm (pièce de détail) ; renvoie le centre lumineux en mètres.
func add_lantern(pos_m: Vector3, bracket := true) -> Vector3:
	var d := AssetKit.new(Vector3i(16, 30, 16), 99)
	d.lantern(8, 4, 8, 6, 10)
	if bracket:
		d.box(7, 24, 7, 8, 28, 8, "iron_dark")
	details.append([d, pos_m - Vector3(8, 4, 8) * VoxelGrid.DETAIL_SIZE, "lantern"])
	return pos_m + Vector3(0, 0.1, 0)
