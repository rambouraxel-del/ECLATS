@tool
class_name PlanTerrain
extends RefCounted
## Du PLAN au TERRAIN (Lot 7). Le plan est la seule source :
##   1. le contour donne les colonnes de sol (AuthoredTerrain) ;
##   2. les zones imposent des hauteurs (disques) ; le relief entre elles est la solution lissée (équation de Laplace) des
##      hauteurs imposées par les zones ET par les chemins ; un bruit à basse fréquence, d'amplitude propre à chaque type de
##      zone, donne du caractère (nul sur les zones plates) ;
##   3. les zones plates (arrivée, plateau, crique) sont aplanies exactement ;
##   4. chaque chemin est CREUSÉ : profil de hauteur sans rupture (palier dans les zones qu'il relie, pente régulière entre),
##      largeur du plan, épaulements adoucis ; matière « sentier » ;
##   5. matières : celle de la zone, roche sur les pentes fortes, taches d'herbe ailleurs ;
##   6. les couches de retouches (relief, matières) s'ajoutent par-dessus (apply_layers).
## Même plan + mêmes réglages = même terrain (tests : empreinte des hauteurs).

const V := VoxelGrid.VOXEL_SIZE
const S := 1.5                     # pas de la grille de résolution du relief (m)
const SHOULDER := 1.6              # largeur des épaulements d'un chemin (m)
const GRADE_WALK := 0.30           # au-delà, un tronçon de chemin est signalé « pente forte »

class Build extends RefCounted:
	var field: TerrainField
	var base_top := PackedInt32Array()      # relief issu du plan seul
	var base_mat := PackedByteArray()
	var path_cols := PackedByteArray()      # 1 = colonne de chemin
	var path_h: Dictionary = {}             # id de chemin → hauteurs aux sommets (m)
	var ms := 0
	var plan_sig := 0

static func build(plan: IslandPlan, opts := {}) -> Build:
	var t0 := Time.get_ticks_msec()
	var b := Build.new()
	b.plan_sig = plan.signature()
	var pal := VoxelPalette.get_default()
	var variation := int(opts.get("variation", 0))
	var outline: Array = []
	for p: Vector2 in plan.outline:
		outline.append([p.x, p.y])
	var f := AuthoredTerrain.build_field({"id": plan.name, "seed": plan.seed, "terrain": {"outline": outline, "base_m": 4.0,
		"noise_m": 0.0, "shapes": [], "core_depth_cells": 20}})
	b.field = f
	var n := f.n
	var gx0 := float(f.origin.x) * V
	var gz0 := float(f.origin.y) * V
	var gn := int(ceil(float(n) * V / S))
	# ---- grille grossière : sol, contraintes (zones), amplitude
	var land := PackedByteArray()
	land.resize(gn * gn)
	for j in gn:
		for i in gn:
			var x := gx0 + (float(i) + 0.5) * S
			var z := gz0 + (float(j) + 0.5) * S
			var hit := false
			for o in [Vector2(0, 0), Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]:
				var c := f.col_of_m(x + o.x * S, z + o.y * S)
				if f.has_ground(c.x, c.y):
					hit = true
					break
			land[i + j * gn] = 1 if hit else 0
	var fixed := PackedByteArray()
	fixed.resize(gn * gn)
	var hv := PackedFloat32Array()
	hv.resize(gn * gn)
	var amp := PackedFloat32Array()
	amp.resize(gn * gn)
	amp.fill(0.6)
	for z in plan.zones:
		var kd: Dictionary = IslandPlan.KINDS[z["kind"]]
		var zc: Vector2 = z["c"]
		var zr := float(z["r"])
		var zh := plan.zone_height(z)
		var core := zr * float(kd["cr"]) if (zh > 0.0 and float(kd["cr"]) > 0.0) else 0.0
		var i0 := clampi(floori((zc.x - zr - gx0) / S), 0, gn - 1)
		var i1 := clampi(ceili((zc.x + zr - gx0) / S), 0, gn - 1)
		var j0 := clampi(floori((zc.y - zr - gz0) / S), 0, gn - 1)
		var j1 := clampi(ceili((zc.y + zr - gz0) / S), 0, gn - 1)
		var nearest := -1
		var nd := 1.0e9
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var q := Vector2(gx0 + (float(i) + 0.5) * S, gz0 + (float(j) + 0.5) * S)
				var d := q.distance_to(zc)
				var idx := i + j * gn
				if d <= zr:
					fixed[idx] = 0
					amp[idx] = float(kd["amp"])
				if core > 0.0 and d <= core:
					fixed[idx] = 1
					hv[idx] = zh
				if d < nd:
					nd = d
					nearest = idx
		if core > 0.0 and nearest >= 0 and nd <= zr:
			fixed[nearest] = 1
			hv[nearest] = zh
	# ---- chemins : profils de hauteur, contraintes le long du tracé
	var zone_only := PackedFloat32Array()
	var need_free := false
	for pa in plan.paths:
		if _end_free(plan, pa["pts"][0]) or _end_free(plan, (pa["pts"] as Array)[-1]):
			need_free = true
	if need_free:
		zone_only = _solve(gn, land, fixed, hv)
	for pa in plan.paths:
		var prof := path_profile(plan, pa, func(q: Vector2) -> float: return _sample(zone_only, gn, gx0, gz0, q.x, q.y) if not zone_only.is_empty() else 4.0)
		b.path_h[pa["id"]] = prof
		var pts: Array = pa["pts"]
		var hw := float(pa["width"]) * 0.5 + S * 0.5
		var cum: PackedFloat32Array = prof["cum"]
		for k in range(pts.size() - 1):
			var a: Vector2 = pts[k]
			var c: Vector2 = pts[k + 1]
			var lo := a.min(c) - Vector2(hw, hw)
			var hi := a.max(c) + Vector2(hw, hw)
			for j in range(clampi(floori((lo.y - gz0) / S), 0, gn - 1), clampi(ceili((hi.y - gz0) / S), 0, gn - 1) + 1):
				for i in range(clampi(floori((lo.x - gx0) / S), 0, gn - 1), clampi(ceili((hi.x - gx0) / S), 0, gn - 1) + 1):
					var q := Vector2(gx0 + (float(i) + 0.5) * S, gz0 + (float(j) + 0.5) * S)
					var ab := c - a
					var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
					if q.distance_to(a + ab * t) <= hw:
						var idx := i + j * gn
						fixed[idx] = 1
						hv[idx] = profile_h(prof, lerpf(cum[k], cum[k + 1], t))
	var hs := _solve(gn, land, fixed, hv)
	# remplissage des cellules hors sol (les colonnes de bord les interpolent)
	_dilate(hs, land, gn)
	# amplitude lissée
	for pass_i in 2:
		var nx := amp.duplicate()
		for j in range(1, gn - 1):
			for i in range(1, gn - 1):
				var idx := i + j * gn
				nx[idx] = (amp[idx] * 4.0 + amp[idx - 1] + amp[idx + 1] + amp[idx - gn] + amp[idx + gn]) / 8.0
		amp = nx
	# ---- colonnes : relief + bruit + zones plates
	var nz1 := WorldRng.noise(plan.seed + variation * 7919, "plan_relief", 0.07, 2)
	var nz2 := WorldRng.noise(plan.seed + variation * 7919, "plan_relief_fine", 0.21, 1)
	var relief := float(plan.settings.get("relief", 1.0))
	var wflat := PackedFloat32Array()
	wflat.resize(n * n)
	var hflat := PackedFloat32Array()
	hflat.resize(n * n)
	for z in plan.zones:
		var kd: Dictionary = IslandPlan.KINDS[z["kind"]]
		var zc: Vector2 = z["c"]
		var zr := float(z["r"])
		var flat := bool(kd["flat"])
		var zh := plan.zone_height(z)
		var ext := zr + 1.4
		var cl := f.col_of_m(zc.x - ext, zc.y - ext)
		var ch := f.col_of_m(zc.x + ext, zc.y + ext)
		for cz in range(maxi(cl.y, 0), mini(ch.y, n - 1) + 1):
			for cx in range(maxi(cl.x, 0), mini(ch.x, n - 1) + 1):
				var d := f.center_m(cx, cz).distance_to(zc)
				var wd := 1.0 - smoothstep(zr * 0.8, zr + 1.2, d)
				if wd <= 0.0:
					continue
				var i := cx + cz * n
				if flat and zh > 0.0:
					if wd >= wflat[i]:
						hflat[i] = zh
						wflat[i] = wd
				else:
					wflat[i] *= (1.0 - wd)
	var Hc := PackedFloat32Array()
	Hc.resize(n * n)
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			if f.top[i] == TerrainField.NO_GROUND:
				continue
			var q := f.center_m(cx, cz)
			var h0 := _sample(hs, gn, gx0, gz0, q.x, q.y)
			var a := _sample(amp, gn, gx0, gz0, q.x, q.y) * relief
			var w := wflat[i]
			h0 += (nz1.get_noise_2d(q.x, q.y) * 0.7 + nz2.get_noise_2d(q.x, q.y) * 0.3) * a * (1.0 - w) * 1.6
			Hc[i] = lerpf(h0, hflat[i], w) if w > 0.0 else h0
	# ---- chemins creusés
	b.path_cols = _carve(plan, f, Hc, b.path_h)
	# ---- quantification
	for i in n * n:
		if f.top[i] == TerrainField.NO_GROUND:
			continue
		var top := roundi(maxf(Hc[i], 0.6) / V) - 1
		f.top[i] = top
		f.natural_top[i] = top
		f.core_top[i] = top - 20
		f.bottom[i] = top - 8
		f.zone[i] = TerrainField.Zone.ROAD if b.path_cols[i] == 1 else TerrainField.Zone.NATURAL
	# ---- matières
	if bool(opts.get("materials", true)):
		_materials(plan, f, b, pal)
	b.base_top = f.top.duplicate()
	b.base_mat = f.material.duplicate()
	b.ms = Time.get_ticks_msec() - t0
	return b

static func _end_free(plan: IslandPlan, p: Vector2) -> bool:
	var z := plan.zone_at(p)
	if z.is_empty():
		return true
	var kd: Dictionary = IslandPlan.KINDS[z["kind"]]
	return plan.zone_height(z) <= 0.0 or float(kd["cr"]) <= 0.0

## Profil de hauteur d'un chemin aux sommets du tracé : palier à la hauteur de la zone (dans son noyau) aux deux extrémités,
## pente régulière entre les deux. Une extrémité hors zone prend la hauteur `free_h(point)`.
static func path_profile(plan: IslandPlan, pa: Dictionary, free_h: Callable) -> Dictionary:
	var pts: Array = pa["pts"]
	var m := pts.size()
	var cum := PackedFloat32Array()
	cum.resize(m)
	for k in range(1, m):
		cum[k] = cum[k - 1] + (pts[k] as Vector2).distance_to(pts[k - 1])
	var total := cum[m - 1]
	var ha: float = free_h.call(pts[0])
	var hb: float = free_h.call(pts[m - 1])
	var sa := 0.0
	var sb := total
	var za := plan.zone_at(pts[0])
	if not za.is_empty() and not _end_free(plan, pts[0]):
		ha = plan.zone_height(za)
		var core_a := float(za["r"]) * float(IslandPlan.KINDS[za["kind"]]["cr"])
		sa = _leave_core(pts, cum, za["c"], core_a, false)
	var zb := plan.zone_at(pts[m - 1])
	if not zb.is_empty() and not _end_free(plan, pts[m - 1]):
		hb = plan.zone_height(zb)
		var core_b := float(zb["r"]) * float(IslandPlan.KINDS[zb["kind"]]["cr"])
		sb = _leave_core(pts, cum, zb["c"], core_b, true)
	return {"cum": cum, "total": total, "ha": ha, "hb": hb, "sa": sa, "sb": sb}

## Abscisse curviligne où le tracé quitte (depuis le début) ou rejoint (par la fin) le noyau d'une zone ; affinée au centimètre.
static func _leave_core(pts: Array, cum: PackedFloat32Array, c: Vector2, core: float, from_end: bool) -> float:
	var total := cum[cum.size() - 1]
	var step := 0.05
	var s := total if from_end else 0.0
	var last_in := s
	while s >= 0.0 and s <= total:
		var q := point_at(pts, cum, s)
		if q.distance_to(c) <= core:
			last_in = s
		else:
			break
		s += -step if from_end else step
	return last_in

static func point_at(pts: Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var m := pts.size()
	if s <= 0.0:
		return pts[0]
	for k in range(1, m):
		if s <= cum[k]:
			var seg := maxf(cum[k] - cum[k - 1], 1.0e-6)
			return (pts[k - 1] as Vector2).lerp(pts[k], (s - cum[k - 1]) / seg)
	return pts[m - 1]

## Hauteur (m) du profil à l'abscisse s : palier au début et à la fin, montée régulière entre les deux.
static func profile_h(prof: Dictionary, s: float) -> float:
	var sa: float = prof["sa"]
	var sb: float = prof["sb"]
	var ha: float = prof["ha"]
	var hb: float = prof["hb"]
	if sb <= sa:
		return lerpf(ha, hb, s / maxf(float(prof["total"]), 0.01))
	if s <= sa:
		return ha
	if s >= sb:
		return hb
	return lerpf(ha, hb, (s - sa) / (sb - sa))

## Résolution de Laplace par sur-relaxation, départ = valeur imposée la plus proche.
static func _solve(gn: int, land: PackedByteArray, fixed: PackedByteArray, hv: PackedFloat32Array) -> PackedFloat32Array:
	var h := hv.duplicate()
	var queue := PackedInt32Array()
	var seen := PackedByteArray()
	seen.resize(gn * gn)
	for i in gn * gn:
		if fixed[i] == 1 and land[i] == 1:
			seen[i] = 1
			queue.append(i)
	if queue.is_empty():
		for i in gn * gn:
			h[i] = 4.0
		return h
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % gn
		var z := i / gn
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = x + o.x
			var zz: int = z + o.y
			if xx < 0 or zz < 0 or xx >= gn or zz >= gn:
				continue
			var j := xx + zz * gn
			if seen[j] == 1 or land[j] == 0:
				continue
			seen[j] = 1
			h[j] = h[i]
			queue.append(j)
	for it in 90:
		var maxd := 0.0
		for j in range(gn):
			for i in range(gn):
				var idx := i + j * gn
				if land[idx] == 0 or fixed[idx] == 1:
					continue
				var s := 0.0
				var c := 0
				if i > 0 and land[idx - 1] == 1:
					s += h[idx - 1]
					c += 1
				if i < gn - 1 and land[idx + 1] == 1:
					s += h[idx + 1]
					c += 1
				if j > 0 and land[idx - gn] == 1:
					s += h[idx - gn]
					c += 1
				if j < gn - 1 and land[idx + gn] == 1:
					s += h[idx + gn]
					c += 1
				if c == 0:
					continue
				var d := s / float(c) - h[idx]
				h[idx] += 1.8 * d
				maxd = maxf(maxd, absf(d))
		if maxd < 0.004:
			break
	return h

static func _dilate(h: PackedFloat32Array, land: PackedByteArray, gn: int) -> void:
	var known := land.duplicate()
	for pass_i in 4:
		var nk := known.duplicate()
		for j in gn:
			for i in gn:
				var idx := i + j * gn
				if known[idx] == 1:
					continue
				var s := 0.0
				var c := 0
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var x: int = i + o.x
					var z: int = j + o.y
					if x >= 0 and z >= 0 and x < gn and z < gn and known[x + z * gn] == 1:
						s += h[x + z * gn]
						c += 1
				if c > 0:
					h[idx] = s / float(c)
					nk[idx] = 1
		known = nk

static func _sample(g: PackedFloat32Array, gn: int, gx0: float, gz0: float, x: float, z: float) -> float:
	var u := (x - gx0) / S - 0.5
	var v := (z - gz0) / S - 0.5
	var i0 := clampi(floori(u), 0, gn - 2)
	var j0 := clampi(floori(v), 0, gn - 2)
	var fu := clampf(u - float(i0), 0.0, 1.0)
	var fv := clampf(v - float(j0), 0.0, 1.0)
	var a := i0 + j0 * gn
	return lerpf(lerpf(g[a], g[a + 1], fu), lerpf(g[a + gn], g[a + gn + 1], fu), fv)

## Creuse les chemins dans Hc (mètres). Renvoie le masque des colonnes de chemin (largeur du plan).
static func _carve(plan: IslandPlan, f: TerrainField, Hc: PackedFloat32Array, path_h: Dictionary) -> PackedByteArray:
	var n := f.n
	var best_d := PackedFloat32Array()
	best_d.resize(n * n)
	best_d.fill(1.0e9)
	var best_h := PackedFloat32Array()
	best_h.resize(n * n)
	var best_w := PackedFloat32Array()
	best_w.resize(n * n)
	var touched: Array[int] = []
	for pa in plan.paths:
		var pts: Array = pa["pts"]
		var prof: Dictionary = path_h[pa["id"]]
		var cum: PackedFloat32Array = prof["cum"]
		var hw := float(pa["width"]) * 0.5
		var reach := hw + SHOULDER
		for k in range(pts.size() - 1):
			var a: Vector2 = pts[k]
			var c: Vector2 = pts[k + 1]
			var ab := c - a
			var inv := 1.0 / maxf(ab.length_squared(), 1.0e-6)
			var lo := f.col_of_m(minf(a.x, c.x) - reach, minf(a.y, c.y) - reach)
			var hi := f.col_of_m(maxf(a.x, c.x) + reach, maxf(a.y, c.y) + reach)
			for cz in range(maxi(lo.y, 0), mini(hi.y, n - 1) + 1):
				for cx in range(maxi(lo.x, 0), mini(hi.x, n - 1) + 1):
					var i := cx + cz * n
					if f.top[i] == TerrainField.NO_GROUND:
						continue
					var q := f.center_m(cx, cz)
					var t := clampf((q - a).dot(ab) * inv, 0.0, 1.0)
					var d := q.distance_to(a + ab * t) - hw
					if d >= reach - hw:
						continue
					if d < best_d[i]:
						if best_d[i] > 1.0e8:
							touched.append(i)
						best_d[i] = d
						best_h[i] = profile_h(prof, lerpf(cum[k], cum[k + 1], t))
						best_w[i] = hw
	var mask := PackedByteArray()
	mask.resize(n * n)
	for i in touched:
		var d := best_d[i]
		var w := 1.0 if d <= 0.0 else 1.0 - smoothstep(0.0, SHOULDER, d)
		Hc[i] = lerpf(Hc[i], best_h[i], w)
		if d <= 0.0:
			mask[i] = 1
	return mask

static func _materials(plan: IslandPlan, f: TerrainField, b: Build, pal: VoxelPalette) -> void:
	var n := f.n
	var G := AuthoredTerrain.G
	var cn := n / G
	var mat_of := PackedInt32Array()
	mat_of.resize(cn * cn)
	var keys: Array[String] = []
	var gx0 := float(f.origin.x) * V
	var gz0 := float(f.origin.y) * V
	var step := V * G
	for z in plan.zones:
		var key: String = IslandPlan.KINDS[z["kind"]]["mat"]
		if key == "grass":          # l'herbe ordinaire garde ses variations naturelles
			key = ""
		var mi := 0
		if key != "":
			if not keys.has(key):
				keys.append(key)
			mi = keys.find(key) + 1
		var zc: Vector2 = z["c"]
		var zr := float(z["r"])
		var i0 := clampi(floori((zc.x - zr - gx0) / step), 0, cn - 1)
		var i1 := clampi(ceili((zc.x + zr - gx0) / step), 0, cn - 1)
		var j0 := clampi(floori((zc.y - zr - gz0) / step), 0, cn - 1)
		var j1 := clampi(ceili((zc.y + zr - gz0) / step), 0, cn - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var q := Vector2(gx0 + (float(i) + 0.5) * step, gz0 + (float(j) + 0.5) * step)
				if q.distance_to(zc) <= zr:
					mat_of[i + j * cn] = mi
	AuthoredTerrain._materials(f, plan.seed, mat_of, keys, cn)
	var dirt := pal.id("path_dirt")
	for i in n * n:
		if b.path_cols[i] == 1:
			f.material[i] = dirt

## Applique les couches de retouches sur le relief du plan : top = base + delta (jamais sous le cœur), matières imposées.
static func apply_layers(b: Build, plan: IslandPlan) -> void:
	var f := b.field
	f.top = b.base_top.duplicate()
	f.material = b.base_mat.duplicate()
	var L := plan.layers
	if L == null:
		return
	L.fit(f.n, f.origin)
	for i in f.n * f.n:
		if f.top[i] == TerrainField.NO_GROUND:
			continue
		var d := L.get_delta(i)
		if d != 0:
			f.top[i] = maxi(f.top[i] + d, f.core_top[i] + TerrainField.MIN_SURFACE)
		if L.mat[i] != 0:
			f.material[i] = L.mat[i]

## Empreinte du relief (comparaison de deux générations).
static func fingerprint(f: TerrainField) -> int:
	return hash(f.top) ^ (hash(f.material) << 1)

# ------------------------------------------------------------------ vérification des chemins sur le terrain réel

## Pour chaque chemin : longueur, dénivelé, pente maximale (fenêtre de 2 m), ruptures (marche ≥ 40 cm entre deux points
## à 25 cm, ou tracé hors du sol). `ok` = aucune rupture ni pente forte.
static func path_reports(plan: IslandPlan, f: TerrainField) -> Array:
	var out: Array = []
	for pa in plan.paths:
		var pts: Array = pa["pts"]
		var samples: Array[Vector3] = []
		var breaks: Array[Vector2] = []
		var steep: Array[Vector2] = []
		var total := IslandPlan.path_length(pts)
		var s := 0.0
		var seg := 0
		var seg_start := 0.0
		var prev_y := NAN
		var step := 0.25
		while s <= total + 0.001:
			while seg < pts.size() - 2 and s > seg_start + (pts[seg + 1] as Vector2).distance_to(pts[seg]):
				seg_start += (pts[seg + 1] as Vector2).distance_to(pts[seg])
				seg += 1
			var a: Vector2 = pts[seg]
			var c: Vector2 = pts[seg + 1]
			var t := clampf((s - seg_start) / maxf(a.distance_to(c), 0.001), 0.0, 1.0)
			var q := a.lerp(c, t)
			var y := f.ground_at_m(q.x, q.y)
			if is_nan(y):
				breaks.append(q)
			else:
				if not is_nan(prev_y) and absf(y - prev_y) >= 0.39:
					breaks.append(q)
				samples.append(Vector3(q.x, y, q.y))
				prev_y = y
			s += step
		var max_grade := 0.0
		var w := 8                                  # 8 × 25 cm = 2 m
		for k in range(0, samples.size() - w):
			var g := absf(samples[k + w].y - samples[k].y) / 2.0
			if g > max_grade:
				max_grade = g
			if g > GRADE_WALK:
				steep.append(Vector2(samples[k].x, samples[k].z))
		var climb := 0.0
		if samples.size() >= 2:
			climb = samples[-1].y - samples[0].y
		out.append({"id": pa["id"], "length_m": total, "climb_m": climb, "max_grade": max_grade, "breaks": breaks, "steep": steep,
			"ok": breaks.is_empty() and steep.is_empty()})
	return out

## Le point de départ est-il sûr ? Sol plat (± 1 cellule) sur 1,5 m autour, à 3 m au moins du bord, hors chemin raide.
static func start_report(plan: IslandPlan, f: TerrainField) -> Dictionary:
	var c := f.col_of_m(plan.start.x, plan.start.y)
	if not f.has_ground(c.x, c.y):
		return {"ok": false, "reason": "Le départ est hors du sol."}
	var t0 := f.top_at(c.x, c.y)
	var worst := 0
	var rc := int(ceil(1.5 / V))
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			if Vector2(dx, dz).length() * V > 1.5:
				continue
			var t := f.top_at(c.x + dx, c.y + dz)
			if t == TerrainField.NO_GROUND:
				return {"ok": false, "reason": "Du vide à moins de 1,5 m du départ."}
			worst = maxi(worst, absi(t - t0))
	var edge := f.edge_at_m(plan.start.x, plan.start.y)
	var ok := worst <= 1 and edge >= 3.0
	return {"ok": ok, "flat_cells": worst, "edge_m": edge, "reason": "" if ok else ("Départ trop près du bord (%.1f m)." % edge if edge < 3.0 else "Départ sur un sol irrégulier (%d cellules).") % worst}
