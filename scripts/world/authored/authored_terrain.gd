@tool
class_name AuthoredTerrain
extends RefCounted
## Relief DESSINÉ d'une île fixe (Lot 5) : la carte JSON décrit le contour et une suite de formes (plateaux,
## lignes de crête ou de corniche, disques, buttes) appliquées dans l'ordre. Résultat : un TerrainField du Lot 4
## (mêmes conventions : colonnes de 20 cm, cœur fixe, zones), utilisable par tous les outils du Lot 4.
##
## Formes (mètres) :
##   poly  {pts, h, blend, rough, op, mat?}   polygone de hauteur h, fondu sur `blend` m autour (0 = falaise nette)
##   disc  {c, r, h, blend, rough, op}
##   line  {pts:[[x, z, h]…], hw, blend, rough, op}   bande de demi-largeur hw dont la hauteur suit la polyligne
##   bump  {c, r, h}                                    butte gaussienne ajoutée
## op : set (remplace avec fondu), max, min. `rough` (m) déforme les bords (bruit) pour des contours naturels.
## Le calcul se fait sur une grille de 40 cm (interpolée aux colonnes) : rapide, même pour une grande île.

const V := VoxelGrid.VOXEL_SIZE
const G := 2                     # colonnes par échantillon de la grille grossière (0,40 m)

static func pts2(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out

static func build_field(map: Dictionary) -> TerrainField:
	var t: Dictionary = map["terrain"]
	var seed: int = int(map.get("seed", 1))
	var outline := pts2(t["outline"])
	var ext := 0.0
	for p in outline:
		ext = maxf(ext, maxf(absf(p.x), absf(p.y)))
	var n := int(ceil((ext * 2.0 + 4.0) / V))
	n += (G * 4) - n % (G * 4)
	var field := TerrainField.new()
	field.init_size(n)
	field.seed = seed
	field.profile_key = String(map.get("id", "authored"))
	field.radius_m = ext
	field.landmarks = {"center": Vector2.ZERO}
	# 1) emprise : balayage par lignes (colonne au sol si son centre est dans le contour)
	var ground := PackedByteArray()
	ground.resize(n * n)
	var m := outline.size()
	for cz in n:
		var zc := (float(field.origin.y + cz) + 0.5) * V
		var xs: Array[float] = []
		for k in m:
			var a := outline[k]
			var b := outline[(k + 1) % m]
			if (a.y > zc) != (b.y > zc):
				xs.append(a.x + (zc - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		for s in range(0, xs.size() - 1, 2):
			var c0 := maxi(ceili(xs[s] / V - 0.5) - field.origin.x, 0)
			var c1 := mini(floori(xs[s + 1] / V - 0.5) - field.origin.x, n - 1)
			for cx in range(c0, c1 + 1):
				ground[cx + cz * n] = 1
	# 2) hauteurs sur la grille grossière
	var cn := n / G
	var hm := PackedFloat32Array()
	hm.resize(cn * cn)
	hm.fill(float(t.get("base_m", 8.0)))
	var mat_of := PackedInt32Array()       # matière imposée par une forme (index + 1 dans mat_keys), 0 = aucune
	mat_of.resize(cn * cn)
	var mat_keys: Array[String] = []
	var rough_n := WorldRng.noise(seed, "authored_rough", 0.09, 2)
	var rough_v := PackedFloat32Array()
	rough_v.resize(cn * cn)
	var glob := WorldRng.noise(seed, "authored_relief", float(t.get("noise_freq", 0.06)), 3)
	var gamp := float(t.get("noise_m", 0.3))
	var x0 := float(field.origin.x) * V
	var z0 := float(field.origin.y) * V
	var step := V * G
	for j in cn:
		for i in cn:
			var px := x0 + (float(i) + 0.5) * step
			var pz := z0 + (float(j) + 0.5) * step
			rough_v[i + j * cn] = rough_n.get_noise_2d(px, pz)
	for sh: Dictionary in t.get("shapes", []):
		_apply_shape(sh, hm, mat_of, mat_keys, rough_v, cn, x0, z0, step)
	for j in cn:
		for i in cn:
			var px := x0 + (float(i) + 0.5) * step
			var pz := z0 + (float(j) + 0.5) * step
			hm[i + j * cn] += glob.get_noise_2d(px, pz) * gamp
	# 3) colonnes : interpolation bilinéaire puis quantification à 20 cm
	var core_depth := int(t.get("core_depth_cells", 20))
	for cz in n:
		var v := (float(cz) - 0.5) / float(G)
		var j0 := clampi(floori(v), 0, cn - 2)
		var fv := clampf(v - float(j0), 0.0, 1.0)
		for cx in n:
			var ci := cx + cz * n
			if ground[ci] == 0:
				continue
			var u := (float(cx) - 0.5) / float(G)
			var i0 := clampi(floori(u), 0, cn - 2)
			var fu := clampf(u - float(i0), 0.0, 1.0)
			var a := i0 + j0 * cn
			var h := lerpf(lerpf(hm[a], hm[a + 1], fu), lerpf(hm[a + cn], hm[a + cn + 1], fu), fv)
			var top := roundi(h / V) - 1
			field.top[ci] = top
			field.natural_top[ci] = top
			field.core_top[ci] = top - core_depth
			field.bottom[ci] = top - 8
			field.zone[ci] = TerrainField.Zone.NATURAL
	_edge_distance(field)
	_materials(field, seed, mat_of, mat_keys, cn)
	return field

## Applique une forme sur la grille grossière (boîte englobante seulement).
static func _apply_shape(sh: Dictionary, hm: PackedFloat32Array, mat_of: PackedInt32Array, mat_keys: Array[String],
		rough_v: PackedFloat32Array, cn: int, x0: float, z0: float, step: float) -> void:
	var type: String = sh.get("type", "poly")
	var blend := float(sh.get("blend", 0.0))
	var rough := float(sh.get("rough", 0.0))
	var op: String = sh.get("op", "set")
	var mat_index := 0
	if sh.has("mat"):
		var key: String = sh["mat"]
		if not mat_keys.has(key):
			mat_keys.append(key)
		mat_index = mat_keys.find(key) + 1
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var poly := PackedVector2Array()
	var line_pts := PackedVector2Array()
	var line_h := PackedFloat32Array()
	var c := Vector2.ZERO
	var r := 0.0
	var hw := 0.0
	match type:
		"poly":
			poly = pts2(sh["pts"])
			for p in poly:
				lo = lo.min(p)
				hi = hi.max(p)
		"disc", "bump":
			c = Vector2(float(sh["c"][0]), float(sh["c"][1]))
			r = float(sh["r"])
			var e := r * (2.5 if type == "bump" else 1.0)
			lo = c - Vector2(e, e)
			hi = c + Vector2(e, e)
		"line":
			hw = float(sh["hw"])
			for p in sh["pts"]:
				var q := Vector2(float(p[0]), float(p[1]))
				line_pts.append(q)
				line_h.append(float(p[2]))
				lo = lo.min(q - Vector2(hw, hw))
				hi = hi.max(q + Vector2(hw, hw))
	var pad := blend + absf(rough) + 0.5
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)
	var i_lo := clampi(floori((lo.x - x0) / step), 0, cn - 1)
	var i_hi := clampi(ceili((hi.x - x0) / step), 0, cn - 1)
	var j_lo := clampi(floori((lo.y - z0) / step), 0, cn - 1)
	var j_hi := clampi(ceili((hi.y - z0) / step), 0, cn - 1)
	var h_shape := float(sh.get("h", 0.0))
	var pc := poly.size()
	var lc := line_pts.size()
	for j in range(j_lo, j_hi + 1):
		var pz := z0 + (float(j) + 0.5) * step
		for i in range(i_lo, i_hi + 1):
			var px := x0 + (float(i) + 0.5) * step
			var idx := i + j * cn
			var p := Vector2(px, pz)
			var d := 0.0
			var target := h_shape
			match type:
				"poly":
					var inside := false
					var best := 1e9
					for k in pc:
						var a := poly[k]
						var b := poly[(k + 1) % pc]
						if (a.y > pz) != (b.y > pz) and px < (b.x - a.x) * (pz - a.y) / (b.y - a.y) + a.x:
							inside = not inside
						var ab := b - a
						var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
						best = minf(best, p.distance_squared_to(a + ab * tt))
					d = sqrt(best)
					if inside:
						d = -d
				"disc":
					d = p.distance_to(c) - r
				"bump":
					hm[idx] += h_shape * exp(-p.distance_squared_to(c) / (r * r))
					continue
				"line":
					var best := 1e9
					var bh := 0.0
					for k in lc - 1:
						var a := line_pts[k]
						var b := line_pts[k + 1]
						var ab := b - a
						var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
						var dd := p.distance_squared_to(a + ab * tt)
						if dd < best:
							best = dd
							bh = lerpf(line_h[k], line_h[k + 1], tt)
					d = sqrt(best) - hw
					target = bh
			d += rough_v[idx] * rough
			var w := 0.0
			if d <= 0.0:
				w = 1.0
			elif blend > 0.0 and d < blend:
				var s := d / blend
				w = 1.0 - s * s * (3.0 - 2.0 * s)
			if w <= 0.0:
				continue
			var cur := hm[idx]
			var nv := cur + (target - cur) * w
			match op:
				"max": nv = maxf(cur, nv)
				"min": nv = minf(cur, nv)
			hm[idx] = nv
			if mat_index > 0 and w > 0.5:
				mat_of[idx] = mat_index
			elif w > 0.5:
				mat_of[idx] = 0

## Distance au vide (m), par parcours en largeur limité à 12 m (au-delà : 30 m).
static func _edge_distance(field: TerrainField) -> void:
	var n := field.n
	var dist := PackedInt32Array()
	dist.resize(n * n)
	dist.fill(1 << 20)
	var queue := PackedInt32Array()
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			for o in WorldNav.NEIGH:
				var x: int = cx + o.x
				var z: int = cz + o.y
				if x < 0 or z < 0 or x >= n or z >= n or field.top[x + z * n] == TerrainField.NO_GROUND:
					dist[i] = 0
					queue.append(i)
					break
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var d := dist[i]
		if d >= 60:
			continue
		var cx := i % n
		var cz := i / n
		for o in WorldNav.NEIGH:
			var x: int = cx + o.x
			var z: int = cz + o.y
			if x < 0 or z < 0 or x >= n or z >= n:
				continue
			var j := x + z * n
			if field.top[j] == TerrainField.NO_GROUND or dist[j] <= d + 1:
				continue
			dist[j] = d + 1
			queue.append(j)
	for i in n * n:
		if field.top[i] == TerrainField.NO_GROUND:
			field.edge_dist[i] = 0.0
		else:
			field.edge_dist[i] = 30.0 if dist[i] > 60 else (float(dist[i]) + 0.5) * V

## Matières du dessus : celles imposées par une forme, roche sur les pentes fortes, herbes en taches ailleurs.
static func _materials(field: TerrainField, seed: int, mat_of: PackedInt32Array, mat_keys: Array[String], cn: int) -> void:
	var n := field.n
	var pal := VoxelPalette.get_default()
	var moist := WorldRng.noise(seed, "moisture", 0.03, 2)
	var rocky := WorldRng.noise(seed, "rockiness", 0.06, 2)
	var patch := WorldRng.noise(seed, "grass_patch", 0.16, 2)
	var forced: Array[int] = [0]
	for k in mat_keys:
		forced.append(pal.id(k))
	var ids := {"lush": pal.id("grass_lush"), "dry": pal.id("grass_dry"), "wild": pal.id("grass_wild"), "grass": pal.id("grass"),
		"warm": pal.id("rock_warm"), "grey": pal.id("rock_grey")}
	# bruits évalués sur la grille grossière (40 cm) : quatre fois moins d'appels
	var mo := PackedFloat32Array()
	mo.resize(cn * cn)
	var ro := PackedFloat32Array()
	ro.resize(cn * cn)
	var ro2 := PackedFloat32Array()
	ro2.resize(cn * cn)
	for j in cn:
		for i in cn:
			var p := field.center_m(i * G, j * G)
			mo[i + j * cn] = moist.get_noise_2d(p.x, p.y) * 0.5 + 0.5 + patch.get_noise_2d(p.x, p.y) * 0.16
			ro[i + j * cn] = rocky.get_noise_2d(p.x, p.y)
			ro2[i + j * cn] = rocky.get_noise_2d(p.y, p.x)
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			var gi := mini(cx / G, cn - 1) + mini(cz / G, cn - 1) * cn
			var slope := field.step_at(cx, cz)
			var id: int = ids["grass"]
			var fm := mat_of[gi]
			if slope >= 3 or (ro[gi] > 0.62 and slope >= 1):
				id = ids["warm"] if ro2[gi] > 0.0 else ids["grey"]
			elif fm > 0:
				id = forced[fm]
			elif field.edge_dist[i] < 0.5:
				id = ids["wild"]
			else:
				# taches d'herbe lissées (pas de tirage par colonne : les grandes faces restent fusionnables)
				var mm := mo[gi]
				if mm > 0.62:
					id = ids["lush"]
				elif mm < 0.24:
					id = ids["dry"]
				else:
					id = ids["wild"] if mm < 0.5 else ids["grass"]
			field.material[i] = id

## Fond de la croûte fine (20 cm) : chaque colonne descend sous le plus bas de ses voisines (flancs des marches et
## falaises fermés) d'une épaisseur `crust` ; près du bord (< 3 m du vide) la croûte fine est épaisse (`rim_crust`) pour
## que les falaises extérieures restent fines. Sous la croûte, la sous-face grossière (1 m) commence sous le plus bas
## fond de chaque bloc de 1 m : jamais de recouvrement, et les éventuels jours restent invisibles (sous la surface).
## Renvoie, par bloc de 1 m, le haut de la sous-face grossière (en mètres entiers) ou NO_GROUND.
static func finalize_bottoms(field: TerrainField, crust := 4, rim_crust := 36) -> Dictionary:
	var n := field.n
	var B := 5
	var bn := n / B
	var bbot := PackedInt32Array()
	bbot.resize(bn * bn)
	bbot.fill(1 << 20)
	var bfull := PackedByteArray()
	bfull.resize(bn * bn)
	bfull.fill(1)
	var bany := PackedByteArray()
	bany.resize(bn * bn)
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			var t := field.top[i]
			var b := mini(cx / B, bn - 1) + mini(cz / B, bn - 1) * bn
			if t == TerrainField.NO_GROUND:
				bfull[b] = 0
				continue
			bany[b] = 1
			var lowest := t
			for o in WorldNav.NEIGH:
				var u := field.top_at(cx + o.x, cz + o.y)
				if u != TerrainField.NO_GROUND:
					lowest = mini(lowest, u)
			var c := rim_crust if field.edge_dist[i] < 3.0 else crust
			var bot := lowest - c
			field.bottom[i] = bot
			bbot[b] = mini(bbot[b], bot)
	var top_k := PackedInt32Array()
	top_k.resize(bn * bn)
	top_k.fill(TerrainField.NO_GROUND)
	var brim := PackedByteArray()
	brim.resize(bn * bn)
	for bz in bn:
		for bx in bn:
			var b := bx + bz * bn
			if bany[b] == 0:
				continue
			var rim := bfull[b] == 0
			for o in WorldNav.NEIGH:
				var x: int = bx + o.x
				var z: int = bz + o.y
				if x < 0 or z < 0 or x >= bn or z >= bn or bfull[x + z * bn] == 0:
					rim = true
			brim[b] = 1 if rim else 0
			top_k[b] = floori(float(bbot[b]) / float(B))
	return {"bn": bn, "top_k": top_k, "rim": brim, "full": bfull}

## Sous-face grossière (voxels de 1 m) sous la croûte fine : cône irrégulier, plus profond vers l'intérieur,
## quelques pointes. Renvoie {volume, origin (m)}.
static func build_underside(field: TerrainField, blocks: Dictionary, seed: int) -> Dictionary:
	var bn: int = blocks["bn"]
	var bbot: PackedInt32Array = blocks["top_k"]
	var brim: PackedByteArray = blocks["rim"]
	var B := 5
	# distance au bord, en blocs (parcours en largeur sur les blocs pleins)
	var dist := PackedInt32Array()
	dist.resize(bn * bn)
	dist.fill(-1)
	var queue := PackedInt32Array()
	for b in bn * bn:
		if bbot[b] != TerrainField.NO_GROUND and brim[b] == 1:
			dist[b] = 0
			queue.append(b)
	var head := 0
	while head < queue.size():
		var b := queue[head]
		head += 1
		var bx := b % bn
		var bz := b / bn
		for o in WorldNav.NEIGH:
			var x: int = bx + o.x
			var z: int = bz + o.y
			if x < 0 or z < 0 or x >= bn or z >= bn:
				continue
			var q := x + z * bn
			if bbot[q] == TerrainField.NO_GROUND or dist[q] >= 0:
				continue
			dist[q] = dist[b] + 1
			queue.append(q)
	var lump := WorldRng.noise(seed, "underside", 0.05, 2)
	var spike_n := WorldRng.noise(seed, "underside_spikes", 0.11, 1)
	var ymin := 1 << 20
	var ymax := -(1 << 20)
	var bottoms := PackedInt32Array()
	bottoms.resize(bn * bn)
	for b in bn * bn:
		if bbot[b] == TerrainField.NO_GROUND or brim[b] == 1:
			continue
		var top_k := bbot[b]                                 # premier mètre occupé par la croûte fine
		var p := field.center_m((b % bn) * B + 2, (b / bn) * B + 2)
		var e := clampf(float(dist[b]) / 45.0, 0.0, 1.0)
		var depth := 7.0 + 30.0 * sqrt(e) + lump.get_noise_2d(p.x, p.y) * 4.0
		var sp := spike_n.get_noise_2d(p.x, p.y)
		if sp > 0.45:
			depth += (sp - 0.45) * 40.0 * (0.4 + e)
		var bot_k := top_k - maxi(int(depth), 3)
		bottoms[b] = bot_k
		ymin = mini(ymin, bot_k)
		ymax = maxi(ymax, top_k)
	if ymin > ymax:
		return {}
	var sy := ymax - ymin + 1
	var vol := VoxelVolume.new(Vector3i(bn, sy, bn))
	var pal := VoxelPalette.get_default()
	var m := {"warm": pal.id("rock_warm"), "grey": pal.id("rock_grey"), "stone": pal.id("stone"), "stone_dark": pal.id("stone_dark")}
	var cache := {}
	var warp := WorldRng.noise(seed, "strata", 0.035, 2)
	for b in bn * bn:
		if bbot[b] == TerrainField.NO_GROUND or brim[b] == 1:
			continue
		var top_k := bbot[b]
		var bx := b % bn
		var bz := b / bn
		var wv := warp.get_noise_2d(float(bx * B), float(bz * B)) * 2.2
		for k in range(bottoms[b], top_k):
			var mat := TerrainVoxelizer._strata(seed, k * B, wv, (top_k - bottoms[b]) * B, m, cache, top_k * B)
			vol.set_voxel(bx, k - ymin, bz, mat)
	var origin := Vector3(float(field.origin.x) * V, float(ymin) * 1.0, float(field.origin.y) * V)
	return {"volume": vol, "origin": origin}
