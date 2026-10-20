@tool
extends RefCounted
## Arbres en voxels de 10 cm (pixels de 2 cm via le shader). Six espèces, plusieurs variantes
## chacune (graine) : chêne, parasol, pin, saule pleureur, bouleau, arbre fruitier.
## Le pied du tronc est au CENTRE de l'emprise. Niveaux de détail : 20 cm puis 40 cm.
## args = {species, seed, name}

const C := VoxelGrid.STRUCTURE_SIZE

static func build(args: Dictionary) -> VoxelAsset:
	var species: String = args["species"]
	var seed: int = args.get("seed", 1)
	var width := 100
	var height := 96
	var k := AssetKit.new(Vector3i(width, height, width), seed * 131 + 7)
	var c := width / 2
	match species:
		"oak": _oak(k, c, seed)
		"parasol": _parasol(k, c, seed)
		"pine": _pine(k, c, seed)
		"weeping": _weeping(k, c, seed)
		"birch": _birch(k, c, seed)
		"fruit": _fruit(k, c, seed)
	# Emprise réelle (en cellules de 20 cm), centrée sur le tronc.
	var bb := _bounds(k.volume)
	var half := maxi(maxi(c - bb.position.x, bb.end.x - c), maxi(c - bb.position.z, bb.end.z - c)) + 1
	var fp_xz := maxi(int(ceil(half * 2.0 * C / VoxelGrid.VOXEL_SIZE)), 1)
	var fp_y := maxi(int(ceil((bb.end.y + 1) * C / VoxelGrid.VOXEL_SIZE)), 1)
	# On recadre le volume pour que le tronc soit au centre de l'emprise.
	var cells_xz := fp_xz * 2
	var out := AssetKit.new(Vector3i(cells_xz, bb.end.y + 1, cells_xz), seed)
	var shift := Vector3i(cells_xz / 2 - c, 0, cells_xz / 2 - c)
	for y in bb.end.y + 1:
		for z in bb.position.z - 1 + 0:
			pass
	for y in mini(k.volume.size.y, out.volume.size.y):
		for z in k.volume.size.z:
			var oz := z + shift.z
			if oz < 0 or oz >= cells_xz:
				continue
			for x in k.volume.size.x:
				var m := k.volume.get_voxel(x, y, z)
				if m != 0:
					var ox := x + shift.x
					if ox >= 0 and ox < cells_xz:
						out.volume.data[out.volume.index_of(ox, y, oz)] = m
	var asset := VoxelAsset.new("", args.get("name", "Arbre"), Vector3i(fp_xz, fp_y, fp_xz))
	asset.cell_m = C
	asset.lod_factors = [2, 4]
	asset.lod_ranges = [20.0, 55.0, 0.0]
	asset.add_part("tree", out)
	var mid := cells_xz / 2
	asset.add_collider(Vector3i(mid - 2, 0, mid - 2), Vector3i(mid + 1, 24, mid + 1))
	return asset

static func _bounds(v: VoxelVolume) -> AABB:
	var lo := Vector3i(v.size)
	var hi := Vector3i(-1, -1, -1)
	for y in v.size.y:
		for z in v.size.z:
			for x in v.size.x:
				if v.get_voxel(x, y, z) != 0:
					lo = Vector3i(mini(lo.x, x), mini(lo.y, y), mini(lo.z, z))
					hi = Vector3i(maxi(hi.x, x), maxi(hi.y, y), maxi(hi.z, z))
	return AABB(Vector3(lo), Vector3(hi - lo))

# ------------------------------------------------------------------ éléments communs

## Tronc : disques empilés, rayon décroissant, évasement du pied, ondulation et inclinaison.
## Renvoie les points du tronc (un tous les 3 cellules).
static func _trunk(k: AssetKit, cx: int, cz: int, h: int, r0: float, r1: float, lean: Vector2, wob: float,
		key: String, alt: String) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var ph := k.rng.randf() * TAU
	for y in h:
		var t := float(y) / h
		var r := lerpf(r0, r1, t)
		r += 3.2 * pow(maxf(1.0 - y / 9.0, 0.0), 2.0)           # pied évasé
		var off := lean * t * t + Vector2(sin(y * 0.19 + ph), cos(y * 0.23 + ph)) * wob
		var px := cx + off.x
		var pz := cz + off.y
		var ri := ceili(r) + 1
		for dz in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var d := Vector2(dx + 0.5, dz + 0.5).length()
				# Bord irrégulier : écorce en reliefs.
				var rr := r + (VoxelGrid.hash01(dx + y * 3, y, dz, 5) - 0.5) * 0.9
				if d <= rr:
					var kk := alt if VoxelGrid.hash01(int(px) + dx, y / 3, int(pz) + dz, 9) < 0.18 else key
					k.volume.set_voxel(int(px) + dx, y, int(pz) + dz, k.mat(kk))
		if y % 3 == 0:
			pts.append(Vector3(px, y, pz))
	return pts

static func _roots(k: AssetKit, cx: int, cz: int, n: int, length: float, key: String) -> void:
	for i in n:
		var a := TAU * i / n + k.rng.randf_range(-0.35, 0.35)
		var l := length * k.rng.randf_range(0.7, 1.15)
		k.line(Vector3(cx + 0.5, 5.0, cz + 0.5), Vector3(cx + 0.5 + cos(a) * l, 0.6, cz + 0.5 + sin(a) * l), 2, key)

## Masse de feuillage : ellipsoïde au bord déchiqueté, mélange de feuilles, bosses en surface.
static func _blob(k: AssetKit, center: Vector3, radii: Vector3, keys: Array, rough := 0.3, bumps := 6) -> void:
	for y in range(floori(center.y - radii.y), ceili(center.y + radii.y) + 1):
		for z in range(floori(center.z - radii.z), ceili(center.z + radii.z) + 1):
			for x in range(floori(center.x - radii.x), ceili(center.x + radii.x) + 1):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - center) / radii
				var l := d.length()
				if l > 1.0 or (l > 0.72 and VoxelGrid.hash01(x, y, z, 77) < rough * (l - 0.72) * 3.2):
					continue
				# Grappes de ton : une teinte par bloc de 3×3×3 pour des paquets de feuilles.
				var hk := VoxelGrid.hash01(x / 3, y / 3, z / 3, 21)
				var key: String = keys[int(hk * keys.size()) % keys.size()]
				if l > 0.8 and d.y > 0.2 and VoxelGrid.hash01(x, y, z, 31) < 0.22:
					key = keys[0]
				k.set_if_empty(x, y, z, key)
	for i in bumps:
		var dir := Vector3(k.rng.randf_range(-1, 1), k.rng.randf_range(-0.3, 1), k.rng.randf_range(-1, 1)).normalized()
		var p := center + dir * radii * 0.92
		var r := k.rng.randf_range(2.5, 5.0)
		k.ellipsoid(p, Vector3(r, r * 0.8, r), keys[k.rng.randi() % keys.size()], true)

static func _branch(k: AssetKit, a: Vector3, b: Vector3, th: int, key: String) -> void:
	k.line(a, b, th, key)

static func _palette(seed: int) -> Array:
	var sets := [
		["leaves", "leaf_dark", "leaves", "leaf_light"],
		["leaf_olive", "leaves", "leaf_light", "leaves"],
		["leaf_dark", "leaves", "leaf_dark", "leaf_olive"],
	]
	return sets[seed % sets.size()]

# ------------------------------------------------------------------ espèces

static func _oak(k: AssetKit, c: int, seed: int) -> void:
	var h := k.rng.randi_range(26, 34)
	var lean := Vector2(k.rng.randf_range(-3, 3), k.rng.randf_range(-3, 3))
	var pts := _trunk(k, c, c, h, k.rng.randf_range(3.3, 4.0), 2.5, lean, 0.8, "bark", "bark_dark")
	_roots(k, c, c, 7, 11.0, "bark")
	var keys := _palette(seed)
	var top: Vector3 = pts[pts.size() - 1]
	var n := k.rng.randi_range(4, 6)
	for i in n:
		var a := TAU * i / n + k.rng.randf_range(-0.5, 0.5)
		var start: Vector3 = pts[clampi(int(pts.size() * k.rng.randf_range(0.5, 0.8)), 0, pts.size() - 1)]
		var reach := k.rng.randf_range(15.0, 26.0)
		var end := start + Vector3(cos(a) * reach, k.rng.randf_range(2.0, 7.0), sin(a) * reach)
		var mid := start.lerp(end, 0.5) + Vector3(0, k.rng.randf_range(1, 3), 0)
		_branch(k, start, mid, 3, "bark")
		_branch(k, mid, end, 2, "bark_dark")
		var rx := k.rng.randf_range(11.0, 15.0)
		_blob(k, end + Vector3(0, 3, 0), Vector3(rx, rx * 0.66, rx), keys)
		if k.rng.randf() < 0.6:
			var a2 := a + k.rng.randf_range(-0.9, 0.9)
			_blob(k, end + Vector3(cos(a2) * 8, 1, sin(a2) * 8), Vector3(7, 5, 7), keys)
	_blob(k, top + Vector3(0, 5, 0), Vector3(13, 9, 13), keys)

static func _parasol(k: AssetKit, c: int, seed: int) -> void:
	var h := k.rng.randi_range(34, 44)
	var lean := Vector2(k.rng.randf_range(-8, 8), k.rng.randf_range(-8, 8))
	var pts := _trunk(k, c, c, h, 2.4, 1.6, lean, 1.0, "bark", "bark_dark")
	_roots(k, c, c, 5, 8.0, "bark")
	var keys := _palette(seed + 1)
	var top: Vector3 = pts[pts.size() - 1]
	var n := k.rng.randi_range(3, 4)
	for i in n:
		var a := TAU * i / n + k.rng.randf_range(-0.5, 0.5)
		var start: Vector3 = pts[clampi(pts.size() - 1 - k.rng.randi_range(0, 4), 0, pts.size() - 1)]
		var end := start + Vector3(cos(a) * 15.0, k.rng.randf_range(4, 8), sin(a) * 15.0)
		_branch(k, start, end, 2, "bark")
		_blob(k, end + Vector3(0, 3, 0), Vector3(19, 6, 19), keys, 0.35, 8)
	_blob(k, top + Vector3(0, 5, 0), Vector3(22, 7, 22), keys, 0.35, 8)

static func _pine(k: AssetKit, c: int, seed: int) -> void:
	var h := k.rng.randi_range(48, 60)
	var pts := _trunk(k, c, c, h, 2.0, 0.8, Vector2(k.rng.randf_range(-2, 2), k.rng.randf_range(-2, 2)), 0.5, "bark_dark", "bark")
	_roots(k, c, c, 5, 7.0, "bark_dark")
	var keys := ["pine", "leaf_dark", "pine", "pine"] if seed % 2 == 0 else ["leaf_dark", "pine", "leaf_dark", "leaf_olive"]
	var y := 14
	var tier := 0
	while y < h - 2:
		var t := float(y - 14) / float(h - 16)
		var r := lerpf(22.0, 4.0, pow(t, 0.85))
		k.ellipsoid(Vector3(c + 0.5, y + 1.0, c + 0.5), Vector3(r, 3.2, r), keys[tier % keys.size()], true)
		# Pointes pendantes sur le bord de l'étage.
		for i in 14:
			var a := TAU * i / 14.0 + tier
			var px := c + 0.5 + cos(a) * r * 0.9
			var pz := c + 0.5 + sin(a) * r * 0.9
			k.line(Vector3(px, y + 1.0, pz), Vector3(px * 0.97 + c * 0.03, y - 3.5, pz * 0.97 + c * 0.03), 1, keys[(tier + i) % keys.size()])
		y += 7 + int(t * 1.5)
		tier += 1
	k.ellipsoid(Vector3(c + 0.5, h + 1.0, c + 0.5), Vector3(2.2, 5.0, 2.2), "pine", true)

static func _weeping(k: AssetKit, c: int, seed: int) -> void:
	var h := k.rng.randi_range(30, 38)
	var lean := Vector2(k.rng.randf_range(-3, 3), k.rng.randf_range(-3, 3))
	var pts := _trunk(k, c, c, h, 2.8, 2.0, lean, 0.7, "bark", "bark_dark")
	_roots(k, c, c, 6, 9.0, "bark")
	var keys := ["leaf_light", "leaves", "leaf_olive", "leaf_light"]
	var top: Vector3 = pts[pts.size() - 1]
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		_branch(k, top - Vector3(0, 4, 0), top + Vector3(cos(a) * 10.0, 5, sin(a) * 10.0), 2, "bark")
	var center := top + Vector3(0, 6, 0)
	_blob(k, center, Vector3(24, 11, 24), keys, 0.3, 6)
	# Lianes de feuillage qui retombent du bord du dôme.
	for i in 150:
		var a := k.rng.randf() * TAU
		var rr := k.rng.randf_range(0.55, 0.98)
		var px := center.x + cos(a) * 24.0 * rr
		var pz := center.z + sin(a) * 24.0 * rr
		var py := center.y - 3.0 - sqrt(maxf(1.0 - rr * rr, 0.0)) * 8.0 + 8.0
		var length := k.rng.randi_range(8, 28)
		for j in length:
			var kk: String = keys[(i + j / 5) % keys.size()]
			k.set_if_empty(int(px), int(py) - j, int(pz), kk)
			if j % 3 == 0:
				k.set_if_empty(int(px) + 1, int(py) - j, int(pz), kk)
			if int(py) - j <= 0:
				break

static func _birch(k: AssetKit, c: int, seed: int) -> void:
	var h := k.rng.randi_range(48, 62)
	var lean := Vector2(k.rng.randf_range(-5, 5), k.rng.randf_range(-5, 5))
	var pts := _trunk(k, c, c, h, 1.7, 0.9, lean, 1.0, "bark_birch", "bark_birch")
	_roots(k, c, c, 4, 6.0, "bark_birch")
	var keys := ["leaf_olive", "leaf_light", "leaves", "leaf_olive"]
	var n := 4
	for i in n:
		var a := TAU * i / n + k.rng.randf_range(-0.6, 0.6)
		var start: Vector3 = pts[clampi(int(pts.size() * (0.5 + 0.12 * i)), 0, pts.size() - 1)]
		var end := start + Vector3(cos(a) * k.rng.randf_range(7, 14), k.rng.randf_range(5, 11), sin(a) * k.rng.randf_range(7, 14))
		_branch(k, start, end, 1, "bark_birch")
		var r := k.rng.randf_range(7.0, 10.5)
		_blob(k, end + Vector3(0, 2, 0), Vector3(r, r * 0.8, r), keys, 0.4, 5)
	var top: Vector3 = pts[pts.size() - 1]
	_blob(k, top + Vector3(0, 3, 0), Vector3(9, 8, 9), keys, 0.4, 5)

static func _fruit(k: AssetKit, c: int, seed: int) -> void:
	var h := k.rng.randi_range(26, 34)
	var pts := _trunk(k, c, c, h, 2.3, 1.7, Vector2(k.rng.randf_range(-2, 2), k.rng.randf_range(-2, 2)), 0.6, "bark", "bark_dark")
	_roots(k, c, c, 5, 7.0, "bark")
	var keys := _palette(seed)
	var top: Vector3 = pts[pts.size() - 1]
	for i in 4:
		var a := TAU * i / 4.0 + k.rng.randf()
		var start: Vector3 = pts[pts.size() - 1 - k.rng.randi_range(0, 3)]
		_branch(k, start, start + Vector3(cos(a) * 8.0, 6, sin(a) * 8.0), 2, "bark")
	_blob(k, top + Vector3(0, 6, 0), Vector3(17, 12, 17), keys, 0.3, 8)
	var fruit_key := "blossom" if seed % 2 == 1 else "apple"
	# Fruits ou fleurs sur la surface du feuillage.
	for i in 40:
		var dir := Vector3(k.rng.randf_range(-1, 1), k.rng.randf_range(-0.6, 1), k.rng.randf_range(-1, 1)).normalized()
		var p := top + Vector3(0, 6, 0) + dir * Vector3(17, 12, 17) * 0.96
		k.set_cell(int(p.x), int(p.y), int(p.z), fruit_key)
		if fruit_key == "blossom":
			k.set_cell(int(p.x) + 1, int(p.y), int(p.z), fruit_key)
