@tool
class_name AssetKit
extends VoxelModelBuilder
## Boîte à outils de modélisation des assets détaillés (microvoxels de 2 cm).
## Rassemble les éléments récurrents des planches de référence (docs/references) :
## pierre claire ébréchée, planches de bois à rainures, capuchons et équerres en cuivre,
## rivets, bannières bleues à losange et franges, lanternes, lierre, fleurs, cristaux.
## Toutes les coordonnées sont en cellules de 2 cm, bornes incluses.

var rng := RandomNumberGenerator.new()

const STONE_TONES := ["stone_light", "stone_carved", "stone_light"]
const WOOD_TONES := ["wood_planks", "wood_honey", "wood_planks", "wood_dark"]

func _init(size: Vector3i, seed := 1) -> void:
	super(size)
	rng.seed = seed

## Convertit des centimètres en cellules de 2 cm.
static func cm(v: float) -> int:
	return roundi(v / 2.0)

func is_empty(x: int, y: int, z: int) -> bool:
	return volume.is_inside(x, y, z) and volume.get_voxel(x, y, z) == 0

func set_if_empty(x: int, y: int, z: int, key: String) -> void:
	if is_empty(x, y, z):
		set_cell(x, y, z, key)

## Retourne le volume d'avant en arrière (z → taille - 1 - z).
func mirror_z() -> void:
	var src := volume.data.duplicate()
	var sz := volume.size.z
	for y in volume.size.y:
		for z in sz:
			for x in volume.size.x:
				volume.data[volume.index_of(x, y, z)] = src[volume.index_of(x, y, sz - 1 - z)]

# ---------------------------------------------------------------- Formes de révolution

## Cylindre vertical (plein, ou creux si `inner` > 0), centre (cx, cz) en cellules, de y0 à y1.
func cyl_y(cx: float, cz: float, y0: int, y1: int, r: float, key: String, inner := 0.0) -> void:
	var id := mat(key)
	var ri := ceili(r) + 1
	for z in range(floori(cz) - ri, floori(cz) + ri + 1):
		for x in range(floori(cx) - ri, floori(cx) + ri + 1):
			var d := Vector2(x + 0.5 - cx, z + 0.5 - cz).length()
			if d <= r and d >= inner:
				for y in range(y0, y1 + 1):
					volume.set_voxel(x, y, z, id)

## Anneau de maçonnerie rond : assises de `bh` cellules, blocs de `bw` cellules de long,
## joints en pierre ombrée, tons de pierre claire variés par bloc.
func stone_ring(cx: float, cz: float, y0: int, y1: int, r_out: float, r_in: float, bw := 12, bh := 8) -> void:
	var ri := ceili(r_out) + 1
	var joint := mat("stone_shade")
	for z in range(floori(cz) - ri, floori(cz) + ri + 1):
		for x in range(floori(cx) - ri, floori(cx) + ri + 1):
			var dv := Vector2(x + 0.5 - cx, z + 0.5 - cz)
			var d := dv.length()
			if d > r_out or d < r_in:
				continue
			var ang := atan2(dv.y, dv.x) + PI
			for y in range(y0, y1 + 1):
				var row := (y - y0) / bh
				var arc := ang * r_out
				var seg := int((arc + (row % 2) * bw * 0.5) / bw)
				var in_row := (y - y0) % bh
				var in_seg := fmod(arc + (row % 2) * bw * 0.5, float(bw))
				var key_id := joint
				if in_row != 0 and in_seg > 1.0:
					key_id = mat(STONE_TONES[int(VoxelGrid.hash01(seg, row, 3, 17) * 3.0) % 3])
				volume.set_voxel(x, y, z, key_id)

## Tonneau : douelles bombées, cerclage (cuivre), fonds en retrait. Axe vertical.
func barrel(cx: float, cz: float, y0: int, height: int, r_mid: float, r_end: float, key := "wood_planks", hoop := "copper") -> void:
	for yy in height:
		var t := float(yy) / maxf(height - 1, 1)
		var r := lerpf(r_end, r_mid, sin(t * PI))
		var ri := ceili(r) + 1
		var is_hoop := yy < 2 or yy >= height - 2 or absi(yy - height / 3) < 1 or absi(yy - 2 * height / 3) < 1
		for z in range(floori(cz) - ri, floori(cz) + ri + 1):
			for x in range(floori(cx) - ri, floori(cx) + ri + 1):
				var d := Vector2(x + 0.5 - cx, z + 0.5 - cz)
				if d.length() <= r:
					var stave := int((atan2(d.y, d.x) + PI) / TAU * 14.0)
					var kk := hoop if (is_hoop and d.length() > r - 1.6) else (key if stave % 2 == 0 else "wood_honey")
					volume.set_voxel(x, y0 + yy, z, mat(kk))
	# Fond (couvercle) : planches rayonnantes plus sombres.
	var top := y0 + height - 1
	cyl_y(cx, cz, top, top, r_end - 1.2, "wood_dark")

## Roue de charrette dans le plan YZ (axe x) : jante, rayons, moyeu.
func wheel_x(x0: int, cy: float, cz: float, thick: int, r: float, key := "wood_dark", hub := "copper", spokes := 8) -> void:
	var ri := ceili(r) + 1
	for z in range(floori(cz) - ri, floori(cz) + ri + 1):
		for y in range(floori(cy) - ri, floori(cy) + ri + 1):
			var d := Vector2(z + 0.5 - cz, y + 0.5 - cy)
			var l := d.length()
			var on_rim := l <= r and l >= r - 3.0
			var on_hub := l <= 3.2
			var ang := fposmod(atan2(d.y, d.x), TAU / spokes)
			var on_spoke := l < r - 2.5 and (ang < 0.12 + 0.5 / maxf(l, 1.0) or ang > TAU / spokes - 0.12 - 0.5 / maxf(l, 1.0))
			if on_rim or on_hub or on_spoke:
				var kk := hub if (on_hub and l < 2.3) or (on_rim and l > r - 1.2) else key
				for x in range(x0, x0 + thick):
					volume.set_voxel(x, y, z, mat(kk))

## Roue de charrette dans le plan XY (axe z) : jante, rayons, moyeu.
func wheel_z(cx: float, cy: float, z0: int, thick: int, r: float, key := "wood_dark", hub := "copper", spokes := 8) -> void:
	var ri := ceili(r) + 1
	for y in range(floori(cy) - ri, floori(cy) + ri + 1):
		for x in range(floori(cx) - ri, floori(cx) + ri + 1):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy)
			var l := d.length()
			var on_rim := l <= r and l >= r - 3.0
			var on_hub := l <= 3.2
			var ang := fposmod(atan2(d.y, d.x), TAU / spokes)
			var w := 0.1 + 0.55 / maxf(l, 1.0)
			var on_spoke := l < r - 2.5 and (ang < w or ang > TAU / spokes - w)
			if on_rim or on_hub or on_spoke:
				var kk := hub if (on_hub and l < 2.3) or (on_rim and l > r - 1.2) else key
				for z in range(z0, z0 + thick):
					volume.set_voxel(x, y, z, mat(kk))

## Caisse en planches : cadre sombre aux angles, lattes, bande de cuivre optionnelle.
func crate(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, key := "wood_planks", band := "") -> void:
	planks(x0, y0, z0, x1, y1, z1, 0, 1, 4, [key, "wood_honey", key], true)
	for c in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
		box(c.x, y0, c.y, c.x, y1, c.y, "wood_dark")
	box(x0, y0, z0, x1, y0, z1, "wood_dark")
	box(x0, y1, z0, x1, y1, z1, "wood_dark")
	if band != "":
		var m := (x0 + x1) / 2
		box(m - 1, y0, z0 - 0, m, y1, z0, band)
		box(m - 1, y0, z1, m, y1, z1, band)

# ---------------------------------------------------------------- Pierre

## Bloc de pierre claire : teinte par bloc (pas par cellule), mouchetis discret,
## arêtes ébréchées. chip = nombre d'éclats retirés sur les arêtes.
func stone_block(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, chip := 4, tone := "") -> void:
	var key: String = tone if tone != "" else STONE_TONES[rng.randi() % STONE_TONES.size()]
	box(x0, y0, z0, x1, y1, z1, key)
	# Mouchetis de surface (pierre plus sombre ou plus claire), en petites taches.
	var spots := int((x1 - x0 + 1) * (z1 - z0 + 1) * 0.05) + 2
	for i in spots:
		var p := Vector3i(rng.randi_range(x0, x1), rng.randi_range(y0, y1), rng.randi_range(z0, z1))
		match rng.randi() % 3:
			0: p.y = y1
			1: p.x = x0 if rng.randf() < 0.5 else x1
			2: p.z = z0 if rng.randf() < 0.5 else z1
		set_cell(p.x, p.y, p.z, "stone_shade" if key != "stone_shade" else "stone_carved")
	# Éclats sur les arêtes supérieures et les coins.
	for i in chip:
		var cx := x0 if rng.randf() < 0.5 else x1
		var cz := z0 if rng.randf() < 0.5 else z1
		var cy := y1 if rng.randf() < 0.7 else y0
		var along := rng.randi() % 2
		var length := rng.randi_range(1, 3)
		for t in length:
			if along == 0:
				var x := clampi(cx + (t if cx == x0 else -t), x0, x1)
				set_cell(x, cy, cz, "")
			else:
				var z := clampi(cz + (t if cz == z0 else -t), z0, z1)
				set_cell(cx, cy, z, "")

## Maçonnerie : blocs de pierre décalés à joints creux (1 cellule) sur les faces extérieures.
func masonry(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, bw: int, bh: int, chip := 2) -> void:
	box(x0, y0, z0, x1, y1, z1, "stone_shade")
	var row := 0
	var y := y0
	while y <= y1:
		var yt := mini(y + bh - 1, y1)
		var off := (row % 2) * (bw / 2)
		var x := x0 - off
		while x <= x1:
			var xs := maxi(x, x0)
			var xe := mini(x + bw - 2, x1)
			var z := z0 - ((row + 1) % 2) * (bw / 2)
			while z <= z1:
				var zs := maxi(z, z0)
				var ze := mini(z + bw - 2, z1)
				if xe >= xs and ze >= zs:
					stone_block(xs, y, zs, xe, yt - (1 if yt < y1 else 0), ze, chip)
				z += bw
			x += bw
		y += bh
		row += 1
	# Joints en creux : on retire la couche extérieure des cellules de joint.
	var joint := mat("stone_shade")
	for yy in range(y0, y1 + 1):
		for zz in range(z0, z1 + 1):
			for xx in range(x0, x1 + 1):
				var outer := xx == x0 or xx == x1 or zz == z0 or zz == z1
				if outer and volume.get_voxel(xx, yy, zz) == joint:
					set_cell(xx, yy, zz, "")

# ---------------------------------------------------------------- Bois

## Planches : la boîte est découpée en lames parallèles à l'axe `run` (0 = x, 2 = z),
## de largeur `pw` le long de l'axe `across`. Rainure de 1 cellule entre deux lames
## sur la face visible (axe `face` : 1 = dessus/dessous). Teintes variées par lame.
func planks(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, run: int, across: int, pw: int,
		tones: Array = WOOD_TONES, groove := true) -> void:
	var lo := Vector3i(x0, y0, z0)
	var hi := Vector3i(x1, y1, z1)
	var face := 3 - run - across
	var start := lo[across]
	var idx := 0
	while start <= hi[across]:
		var end := mini(start + pw - 1, hi[across])
		var key: String = tones[(idx + rng.randi() % 2) % tones.size()]
		var a := lo
		var b := hi
		a[across] = start
		b[across] = end
		box(a.x, a.y, a.z, b.x, b.y, b.z, key)
		# Joints d'about (lames de longueurs différentes).
		var l := hi[run] - lo[run] + 1
		if l > 40 and rng.randf() < 0.6:
			var cut := lo[run] + rng.randi_range(l / 4, 3 * l / 4)
			var c0 := a
			var c1 := b
			c0[run] = cut
			c1[run] = cut
			c0[face] = hi[face]
			c1[face] = hi[face]
			box(c0.x, c0.y, c0.z, c1.x, c1.y, c1.z, "")
		if groove and end < hi[across]:
			for side in [lo[face], hi[face]]:
				var g0 := lo
				var g1 := hi
				g0[across] = end
				g1[across] = end
				g0[face] = side
				g1[face] = side
				box(g0.x, g0.y, g0.z, g1.x, g1.y, g1.z, "")
		start = end + 1
		idx += 1

## Poteau carré à arêtes chanfreinées.
func post(x0: int, z0: int, y0: int, y1: int, w: int, key := "wood_planks") -> void:
	box(x0, y0, z0, x0 + w - 1, y1, z0 + w - 1, key)
	for c in [Vector2i(x0, z0), Vector2i(x0 + w - 1, z0), Vector2i(x0, z0 + w - 1), Vector2i(x0 + w - 1, z0 + w - 1)]:
		box(c.x, y0, c.y, c.x, y1, c.y, "")

# ---------------------------------------------------------------- Métal

## Capuchon de cuivre au sommet d'un poteau (cx, cz = coin du poteau, w = largeur).
func copper_cap(x0: int, z0: int, y: int, w: int, h := 4) -> void:
	box(x0 - 1, y, z0 - 1, x0 + w, y + h - 1, z0 + w, "copper")
	box(x0, y + h, z0, x0 + w - 1, y + h, z0 + w - 1, "copper")
	var m := w / 2
	box(x0 + m - 1, y + h + 1, z0 + m - 1, x0 + m, y + h + 2, z0 + m, "copper")
	# Rivet sombre au centre de chaque face.
	set_cell(x0 - 1, y + h / 2, z0 + m, "iron_dark")
	set_cell(x0 + w, y + h / 2, z0 + m, "iron_dark")
	set_cell(x0 + m, y + h / 2, z0 - 1, "iron_dark")
	set_cell(x0 + m, y + h / 2, z0 + w, "iron_dark")

## Bague de cuivre autour d'un poteau, de y0 à y1.
func copper_collar(x0: int, z0: int, y0: int, y1: int, w: int, key := "copper") -> void:
	box(x0 - 1, y0, z0 - 1, x0 + w, y1, z0 + w, key)
	box(x0, y0, z0, x0 + w - 1, y1, z0 + w - 1, key)

## Plaque d'angle en L, peinte sur les deux faces qui se rejoignent à l'arête verticale
## (x, z) d'une boîte ; (dx, dz) pointe vers l'intérieur de la boîte. Rivets en relief.
func corner_plate(x: int, z: int, dx: int, dz: int, y0: int, y1: int, length: int, key := "copper") -> void:
	for t in length:
		for y in range(y0, y1 + 1):
			if volume.get_voxel(x + dx * t, y, z) != 0:
				set_cell(x + dx * t, y, z, key)
			if volume.get_voxel(x, y, z + dz * t) != 0:
				set_cell(x, y, z + dz * t, key)
	var ym := (y0 + y1) / 2
	set_if_empty(x + dx * (length - 2), ym, z - dz, "iron_dark")
	set_if_empty(x - dx, ym, z + dz * (length - 2), "iron_dark")

## Rivets (1 cellule) le long d'un segment, tous les `step`.
func rivets(a: Vector3i, b: Vector3i, step: int, key := "iron_dark") -> void:
	var d := b - a
	var n := maxi(absi(d.x), maxi(absi(d.y), absi(d.z)))
	var i := 0
	while i <= n:
		var t := float(i) / maxf(n, 1)
		var p := Vector3(a).lerp(Vector3(b), t).round()
		set_cell(int(p.x), int(p.y), int(p.z), key)
		i += step

## Ajoute un anneau de 1 cellule autour des voxels pleins de la tranche y0..y1 (bague, bandeau).
func band_ring(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, key: String) -> void:
	var id := mat(key)
	for y in range(y0, y1 + 1):
		var add: Array[Vector2i] = []
		for z in range(z0 - 1, z1 + 2):
			for x in range(x0 - 1, x1 + 2):
				if volume.get_voxel(x, y, z) != 0:
					continue
				if volume.get_voxel(x + 1, y, z) != 0 or volume.get_voxel(x - 1, y, z) != 0 \
						or volume.get_voxel(x, y, z + 1) != 0 or volume.get_voxel(x, y, z - 1) != 0:
					add.append(Vector2i(x, z))
		for c in add:
			volume.set_voxel(c.x, y, c.y, id)

## Coupe les angles verticaux d'une zone (plan octogonal) : retire les cellules à moins
## de `cut` (distance |dx| + |dz|) de chaque coin.
func cut_corners(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, cut: int) -> void:
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var dx := mini(x - x0, x1 - x)
				var dz := mini(z - z0, z1 - z)
				if dx + dz < cut:
					volume.set_voxel(x, y, z, 0)

## Dessine un motif en caractères ('#' = matière, autre = rien) dans le plan XY à z,
## coin haut-gauche en (x0, y_top).
func glyph(rows: Array, x0: int, y_top: int, z: int, key: String) -> void:
	for v in rows.size():
		var row: String = rows[v]
		for u in row.length():
			if row[u] == "#":
				set_cell(x0 + u, y_top - v, z, key)

# ---------------------------------------------------------------- Textile

## Couleur d'une cellule de bannière (u en largeur, v depuis le haut). "" = vide.
func banner_key(u: int, v: int, w: int, h: int, fringe := 4, base := "fabric_blue") -> String:
	var body_h := h - fringe
	if v >= body_h:
		return "fabric_cream" if u % 2 == 0 else ""
	if u == 1 or u == w - 2 or v == 2 or v == body_h - 2:
		return "fabric_cream"
	var cx := (w - 1) / 2.0
	var cy := (body_h - 1) / 2.0
	var r := minf(w * 0.32, body_h * 0.32)
	var d := absf(u - cx) + absf(v - cy) * 0.85
	if d >= r - 1.0 and d <= r:
		return "fabric_cream"
	if d <= 1.2:
		return "fabric_cream"
	if absf(d - r * 0.5) < 0.5:
		return "fabric_teal" if base == "fabric_blue" else "fabric_cream"
	return base

## Bannière verticale plane, épaisseur 1. plane = 2 : dans le plan XY (face vers z) ;
## plane = 0 : dans le plan ZY (face vers x). (x0, z0) = coin, y_top = haut.
func banner(x0: int, y_top: int, z0: int, w: int, h: int, plane := 2, fringe := 4, base := "fabric_blue") -> void:
	for v in h:
		for u in w:
			var key := banner_key(u, v, w, h, fringe, base)
			if key == "":
				continue
			if plane == 2:
				set_cell(x0 + u, y_top - v, z0, key)
			else:
				set_cell(x0, y_top - v, z0 + u, key)

## Chemin de table drapé : posé sur le dessus (y = top_y + 1) de z_back à z_front,
## puis tombant devant (z = z_front + 1) sur `hang` cellules. Largeur w le long de x.
func runner(x0: int, w: int, z_back: int, z_front: int, top_y: int, hang: int, fringe := 3) -> void:
	var flat := z_front - z_back + 1
	var total := flat + hang
	for u in w:
		for t in total:
			var key := banner_key(u, t, w, total, fringe)
			if key == "":
				continue
			if t < flat:
				set_cell(x0 + u, top_y + 1, z_back + t, key)
			else:
				set_cell(x0 + u, top_y + 1 - (t - flat) - 1, z_front + 1, key)

## Tissu drapé le long d'un chemin dans le plan (y, z) : `points` = suite de Vector2i(y, z)
## reliés par des segments horizontaux ou verticaux. Largeur w le long de x, motif de bannière
## déroulé le long du chemin (le losange et les franges suivent le tissu).
func drape(x0: int, w: int, points: Array, fringe := 3) -> void:
	var cells: Array[Vector2i] = []
	for i in points.size() - 1:
		var a: Vector2i = points[i]
		var b: Vector2i = points[i + 1]
		var d := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var p := a
		while p != b:
			cells.append(p)
			p += d
	cells.append(points[points.size() - 1])
	for u in w:
		for t in cells.size():
			var key := banner_key(u, t, w, cells.size(), fringe)
			if key != "":
				set_cell(x0 + u, cells[t].x, cells[t].y, key)

# ---------------------------------------------------------------- Lumière

## Lanterne de cuivre (planches 2 et 3). (cx, cz) = centre, y0 = bas, s = largeur du verre.
## Renvoie le centre lumineux (en cellules).
func lantern(cx: int, y0: int, cz: int, s := 6, glass_h := 8) -> Vector3:
	var h := s / 2
	var x0 := cx - h
	var z0 := cz - h
	var x1 := x0 + s - 1
	var z1 := z0 + s - 1
	box(x0 - 1, y0, z0 - 1, x1 + 1, y0 + 1, z1 + 1, "copper")            # socle
	box(x0, y0 + 2, z0, x1, y0 + 1 + glass_h, z1, "lantern_glow")        # verre
	for c in [Vector2i(x0 - 1, z0 - 1), Vector2i(x1 + 1, z0 - 1), Vector2i(x0 - 1, z1 + 1), Vector2i(x1 + 1, z1 + 1)]:
		box(c.x, y0 + 2, c.y, c.x, y0 + 1 + glass_h, c.y, "copper")       # montants
	var yt := y0 + 2 + glass_h
	box(x0 - 1, yt, z0 - 1, x1 + 1, yt + 1, z1 + 1, "copper")            # toit en gradins
	box(x0, yt + 2, z0, x1, yt + 2, z1, "copper")
	box(x0 + 1, yt + 3, z0 + 1, x1 - 1, yt + 3, z1 - 1, "wood_red")
	box(cx - 1, yt + 4, cz - 1, cx, yt + 5, cz, "copper")                # anneau
	return Vector3(cx, y0 + 2 + glass_h / 2.0, cz)

## Cristal prismatique à section octogonale, pointes aux deux extrémités, incliné.
func crystal(base: Vector3, height: float, radius: float, tilt := Vector2.ZERO, key := "crystal_blue", tip := 0.3) -> void:
	var id := mat(key)
	for yi in int(ceil(height)) + 1:
		var t := yi / height
		var r := radius
		if t < tip * 0.5:
			r = radius * (t / (tip * 0.5))
		elif t > 1.0 - tip:
			r = radius * (1.0 - t) / tip
		if r <= 0.0:
			r = 0.35
		var c := base + Vector3(tilt.x * yi, yi, tilt.y * yi)
		var ri := int(ceil(r)) + 1
		for dz in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var fx := absf(dx + 0.5 - fmod(c.x, 1.0))
				var fz := absf(dz + 0.5 - fmod(c.z, 1.0))
				if maxf(fx, fz) * 0.75 + (fx + fz) * 0.32 <= r:
					volume.set_voxel(int(c.x) + dx, int(c.y), int(c.z) + dz, id)

# ---------------------------------------------------------------- Végétation

## Lierre qui retombe depuis `start` sur `length` cellules (marche aléatoire vers le bas),
## avec grappes de feuilles et quelques fleurs. Ne remplace jamais une cellule pleine.
func ivy(start: Vector3i, length: int, drift := Vector3i(1, 0, 0), flowers := 0.06) -> void:
	var p := start
	for i in length:
		set_if_empty(p.x, p.y, p.z, "ivy")
		if i % 2 == 0:
			_leaf_cluster(p + Vector3i(rng.randi_range(-1, 1), 0, rng.randi_range(-1, 1)))
		if rng.randf() < flowers:
			set_if_empty(p.x + drift.x * 2, p.y, p.z + drift.z * 2, "flower_white")
		p.y -= 1
		if rng.randf() < 0.35:
			p.x += drift.x * (1 if rng.randf() < 0.7 else -1)
			p.z += drift.z * (1 if rng.randf() < 0.7 else -1)
		if p.y < 0:
			break

func _leaf_cluster(c: Vector3i) -> void:
	var keys := ["ivy", "leaves", "leaf_light", "ivy"]
	var key: String = keys[rng.randi() % keys.size()]
	for o in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
		if rng.randf() < 0.75:
			set_if_empty(c.x + o.x, c.y + o.y, c.z + o.z, key)

## Touffe de feuillage arrondie (buisson, plante en pot) avec fleurs optionnelles.
func bush(center: Vector3, radii: Vector3, flower_key := "", flower_rate := 0.08) -> void:
	for y in range(floori(center.y - radii.y), ceili(center.y + radii.y) + 1):
		for z in range(floori(center.z - radii.z), ceili(center.z + radii.z) + 1):
			for x in range(floori(center.x - radii.x), ceili(center.x + radii.x) + 1):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - center) / radii
				var l := d.length()
				if l > 1.0 or (l > 0.75 and rng.randf() < 0.45):
					continue
				var key: String = ["leaves", "ivy", "leaf_light", "leaves"][rng.randi() % 4]
				if flower_key != "" and l > 0.6 and d.y > -0.2 and rng.randf() < flower_rate:
					key = flower_key
				set_if_empty(x, y, z, key)

## Mousse : sur les colonnes de la zone, pose une cellule de mousse au-dessus du plus haut
## voxel plein s'il est en PIERRE, par plaques (bruit grossier). density = part de plaques.
func moss_top(x0: int, z0: int, x1: int, z1: int, density := 0.35, seed := 0) -> void:
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			if VoxelGrid.hash01(x / 3, 0, z / 3, seed) > density:
				continue
			if VoxelGrid.hash01(x, 1, z, seed) < 0.25:
				continue
			for y in range(volume.size.y - 2, -1, -1):
				var v := volume.get_voxel(x, y, z)
				if v != 0:
					if palette.styles[v] != VoxelPalette.STYLES.find("stone"):
						break
					set_if_empty(x, y + 1, z, "moss" if VoxelGrid.hash01(x, 2, z, seed) < 0.7 else "ivy")
					break
