@tool
class_name TerrainGenerator
extends RefCounted
## Génération HIÉRARCHIQUE du relief naturel d'une île (aucun bruit « voxel par voxel ») :
##   1. Silhouette générale        (harmoniques polaires + distance au vide)
##   2. Grandes zones de relief    (dôme central, collines, plateaux répartis par disque de Poisson)
##   3. Espaces habitables         (plateaux plats, détectés et mesurés ; le village les réutilise)
##   4. Transitions et pentes      (limiteur de pente, paliers à hauteur constante)
##   5. Détails naturels           (matières selon pente / humidité, sous-face en cônes structurés)
##   6. Nettoyage et validation    (cellules isolées, pics, creux, composante connexe unique)
## Tout est déterministe : (profil, graine) → TerrainField identique sur toutes les machines.
## Les aménagements (village, chemins) sont appliqués ENSUITE par SettlementGenerator.

const V := VoxelGrid.VOXEL_SIZE

var profile: IslandProfile
var seed := 0
var field: TerrainField
var _rng: RandomNumberGenerator
var _heights := PackedFloat32Array()   # relief continu (m), avant quantification
var _flat := PackedFloat32Array()      # masque de plateau (0-1)
var report := {}                        # statistiques de génération

func generate(p_profile: IslandProfile, p_seed: int) -> TerrainField:
	profile = p_profile
	seed = p_seed
	_rng = WorldRng.stream(seed, "terrain")
	field = TerrainField.new()
	field.seed = seed
	field.profile_key = profile.key
	var r := WorldRng.range_f(_rng, profile.g("radius_m", [20.0, 22.0]))
	field.radius_m = r
	field.init_size(int(ceil(2.0 * 1.3 * r / V / 2.0)) * 2 + 8)
	_silhouette(r)
	_edge_distance()
	_macro_relief(r)
	_slope_limit()
	_quantize()
	_cleanup()
	_find_plateaus()
	_materials()
	_underside(r)
	_finish_core()
	return field

# ------------------------------------------------------------------ 1. silhouette

func _silhouette(r: float) -> void:
	var n := field.n
	var harm: Array = profile.g("silhouette.harmonics", [[2, 0.1], [3, 0.06]])
	var rough := float(profile.g("silhouette.roughness", 0.02))
	var phases := []
	var signs := []
	for h in harm:
		phases.append(_rng.randf() * TAU)
		signs.append(1.0 if _rng.randf() < 0.5 else -1.0)
	var rim_noise := WorldRng.noise(seed, "rim", 0.9)
	var mask := PackedByteArray()
	mask.resize(n * n)
	for cz in n:
		for cx in n:
			var p := field.center_m(cx, cz)
			var ang := atan2(p.y, p.x)
			var rad := 1.0
			for i in harm.size():
				rad += float(harm[i][1]) * signs[i] * cos(float(harm[i][0]) * ang + phases[i])
			rad += rim_noise.get_noise_2d(cos(ang) * 2.0, sin(ang) * 2.0) * rough * 4.0
			rad = maxf(rad, 0.62)
			mask[cx + cz * n] = 1 if p.length() < r * rad else 0
	# Lissage : retire les excroissances de 1 cellule, comble les trous isolés (2 passes).
	for pass_i in 2:
		var next := mask.duplicate()
		for cz in range(1, n - 1):
			for cx in range(1, n - 1):
				var c := 0
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					c += mask[(cx + o.x) + (cz + o.y) * n]
				var i := cx + cz * n
				if mask[i] == 1 and c <= 1:
					next[i] = 0
				elif mask[i] == 0 and c >= 3:
					next[i] = 1
		mask = next
	# Une seule composante connexe : la plus grande.
	var comp := _largest_component(mask)
	for i in n * n:
		field.top[i] = 0 if comp[i] == 1 else TerrainField.NO_GROUND
	_heights.resize(n * n)
	_flat.resize(n * n)
	_flat.fill(0.0)

func _largest_component(mask: PackedByteArray) -> PackedByteArray:
	var n := field.n
	var label := PackedInt32Array()
	label.resize(n * n)
	var best := -1
	var best_size := 0
	var next_label := 1
	for start in n * n:
		if mask[start] == 0 or label[start] != 0:
			continue
		var stack := [start]
		label[start] = next_label
		var size := 0
		while not stack.is_empty():
			var i: int = stack.pop_back()
			size += 1
			var cx := i % n
			var cz := i / n
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x: int = cx + o.x
				var z: int = cz + o.y
				if x < 0 or z < 0 or x >= n or z >= n:
					continue
				var j := x + z * n
				if mask[j] == 1 and label[j] == 0:
					label[j] = next_label
					stack.append(j)
		if size > best_size:
			best_size = size
			best = next_label
		next_label += 1
	var out := PackedByteArray()
	out.resize(n * n)
	for i in n * n:
		out[i] = 1 if label[i] == best else 0
	return out

## Distance (m) de chaque colonne de terre au vide le plus proche (chanfrein 3-4, deux passes).
func _edge_distance() -> void:
	var n := field.n
	var big := 1.0e6
	var d := PackedFloat32Array()
	d.resize(n * n)
	for i in n * n:
		d[i] = big if field.top[i] != TerrainField.NO_GROUND else 0.0
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			if d[i] == 0.0:
				continue
			var v := d[i]
			if cx > 0: v = minf(v, d[i - 1] + 1.0)
			if cz > 0: v = minf(v, d[i - n] + 1.0)
			if cx > 0 and cz > 0: v = minf(v, d[i - n - 1] + 1.4142)
			if cx < n - 1 and cz > 0: v = minf(v, d[i - n + 1] + 1.4142)
			d[i] = v
	for cz in range(n - 1, -1, -1):
		for cx in range(n - 1, -1, -1):
			var i := cx + cz * n
			if d[i] == 0.0:
				continue
			var v := d[i]
			if cx < n - 1: v = minf(v, d[i + 1] + 1.0)
			if cz < n - 1: v = minf(v, d[i + n] + 1.0)
			if cx < n - 1 and cz < n - 1: v = minf(v, d[i + n + 1] + 1.4142)
			if cx > 0 and cz < n - 1: v = minf(v, d[i + n - 1] + 1.4142)
			d[i] = v
	for i in n * n:
		field.edge_dist[i] = maxf(d[i] - 0.5, 0.0) * V if d[i] > 0.0 else 0.0

# ------------------------------------------------------------------ 2. grandes zones de relief

static func _smooth(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

func _macro_relief(r: float) -> void:
	var n := field.n
	var step := float(profile.g("relief.level_step_m", 0.6))
	var base := WorldRng.range_f(_rng, profile.g("relief.base_m", [2.0, 2.6]))
	var dome := WorldRng.range_f(_rng, profile.g("relief.dome_m", [1.0, 1.8]))
	base = roundf(base / step) * step
	# Dôme central : l'île monte doucement depuis son bord.
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			var e := clampf(field.edge_dist[i] / (0.6 * r), 0.0, 1.0)
			var h := base + dome * _smooth(e)
			h -= 0.45 * (1.0 - _smooth(field.edge_dist[i] / 1.6))     # lèvre du bord
			_heights[i] = h
	var placed: Array = []    # [{c: Vector2, r: float}] pour la séparation
	# Plateaux : disques de Poisson, hauteurs sur l'échelle de paliers, jupe douce.
	var pcount := WorldRng.range_i(_rng, profile.g("relief.plateaus.count", [4, 6]))
	var pr: Array = profile.g("relief.plateaus.radius_m", [3.2, 6.4])
	var lr: Array = profile.g("relief.plateaus.level_range", [-1, 3])
	var margin := float(profile.g("relief.plateaus.edge_margin_m", 3.0))
	var skirt_per := float(profile.g("relief.plateaus.skirt_per_level_m", 1.5))
	var plateau_specs := []
	var tries := 0
	while plateau_specs.size() < pcount and tries < 400:
		tries += 1
		var rad := WorldRng.range_f(_rng, pr)
		# Le premier plateau (le plus grand) est proche du centre : c'est le futur cœur habitable.
		if plateau_specs.is_empty():
			rad = pr[1]
		var c := Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r))
		if plateau_specs.is_empty():
			c = Vector2(_rng.randf_range(-0.18, 0.18) * r, _rng.randf_range(-0.18, 0.18) * r)
		var col := field.col_of_m(c.x, c.y)
		if not field.has_ground(col.x, col.y) or field.edge_dist[field.idx(col.x, col.y)] < margin + rad:
			continue
		var ok := true
		for q in placed:
			if q.c.distance_to(c) < q.r + rad + 1.2:
				ok = false
				break
		if not ok:
			continue
		placed.append({"c": c, "r": rad})
		var level := 1 if plateau_specs.is_empty() else clampi(1 + _rng.randi_range(int(lr[0]), int(lr[1])), -1, 6)
		plateau_specs.append({"c": c, "r": rad, "level": level})
	var hills := []
	var hcount := WorldRng.range_i(_rng, profile.g("relief.hills.count", [1, 2]))
	tries = 0
	while hills.size() < hcount and tries < 400:
		tries += 1
		var rad := WorldRng.range_f(_rng, profile.g("relief.hills.radius_m", [5.0, 8.0]))
		var c := Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r))
		var col := field.col_of_m(c.x, c.y)
		if not field.has_ground(col.x, col.y) or field.edge_dist[field.idx(col.x, col.y)] < rad * 0.7:
			continue
		var ok := true
		for q in placed:
			if q.c.distance_to(c) < q.r + rad * 0.9:
				ok = false
				break
		if not ok:
			continue
		placed.append({"c": c, "r": rad})
		hills.append({"c": c, "r": rad, "h": WorldRng.range_f(_rng, profile.g("relief.hills.height_m", [2.4, 3.6]))})
	# Collines d'abord (formes larges), puis plateaux par-dessus (ils restent plats).
	for hl in hills:
		_stamp_hill(hl.c, hl.r, hl.h)
	var anchor := 0.0
	for pl in plateau_specs:
		var level_h: float = (roundf((base + dome * 0.55) / step) + pl.level) * step
		_stamp_plateau(pl.c, pl.r, level_h, skirt_per, step)
		if anchor == 0.0:
			anchor = level_h
	# Bruit basse fréquence atténué sur les plateaux.
	var amp := float(profile.g("relief.noise_amp_m", 0.5))
	var nz := WorldRng.noise(seed, "relief", 0.045, 2)
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			var p := field.center_m(cx, cz)
			_heights[i] += nz.get_noise_2d(p.x, p.y) * amp * (1.0 - _flat[i]) * _smooth(field.edge_dist[i] / 2.0)
	report["plateaus_planned"] = plateau_specs.size()
	report["hills"] = hills.size()
	field.landmarks["plateau_specs"] = plateau_specs

func _stamp_plateau(c: Vector2, rad: float, level_h: float, skirt_per: float, step: float) -> void:
	var col := field.col_of_m(c.x, c.y)
	var here := _heights[field.idx(col.x, col.y)]
	var delta := absf(level_h - here)
	var skirt := clampf(skirt_per * delta / step, 1.8, 6.5)
	var wob := WorldRng.noise(seed, "plateau_%d_%d" % [col.x, col.y], 0.5, 2)
	var reach := rad * 1.2 + skirt
	var cx0 := maxi(col.x - int(reach / V) - 1, 0)
	var cx1 := mini(col.x + int(reach / V) + 1, field.n - 1)
	var cz0 := maxi(col.y - int(reach / V) - 1, 0)
	var cz1 := mini(col.y + int(reach / V) + 1, field.n - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := cx + cz * field.n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			var p := field.center_m(cx, cz)
			var d := p.distance_to(c)
			var ang := atan2(p.y - c.y, p.x - c.x)
			var rr := rad * (1.0 + 0.1 * wob.get_noise_2d(cos(ang) * 3.0, sin(ang) * 3.0))
			var w := 1.0 if d <= rr else 1.0 - _smooth((d - rr) / skirt)
			if w <= 0.0:
				continue
			_heights[i] = lerpf(_heights[i], level_h, w)
			_flat[i] = maxf(_flat[i], w)

func _stamp_hill(c: Vector2, rad: float, peak: float) -> void:
	var col := field.col_of_m(c.x, c.y)
	var reach := rad
	var cx0 := maxi(col.x - int(reach / V) - 1, 0)
	var cx1 := mini(col.x + int(reach / V) + 1, field.n - 1)
	var cz0 := maxi(col.y - int(reach / V) - 1, 0)
	var cz1 := mini(col.y + int(reach / V) + 1, field.n - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := cx + cz * field.n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			var d := field.center_m(cx, cz).distance_to(c) / rad
			if d >= 1.0:
				continue
			_heights[i] += peak * pow(1.0 - d * d, 1.5)

# ------------------------------------------------------------------ 4. transitions : limiteur de pente

func _slope_limit() -> void:
	var n := field.n
	var dmax := float(profile.g("relief.max_natural_step", 2)) * V
	for iteration in 3:
		for cz in n:
			for cx in n:
				_limit(cx, cz, dmax)
		for cz in range(n - 1, -1, -1):
			for cx in range(n - 1, -1, -1):
				_limit(cx, cz, dmax)

func _limit(cx: int, cz: int, dmax: float) -> void:
	var i := cx + cz * field.n
	if field.top[i] == TerrainField.NO_GROUND:
		return
	var h := _heights[i]
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var x: int = cx + o.x
		var z: int = cz + o.y
		if not field.in_bounds(x, z):
			continue
		var j := x + z * field.n
		if field.top[j] == TerrainField.NO_GROUND or field.edge_dist[j] < 0.7:
			continue
		h = clampf(h, _heights[j] - dmax, _heights[j] + dmax)
	_heights[i] = h

## Paliers : zones plates à hauteur constante reliées par de courtes marches.
func _quantize() -> void:
	var n := field.n
	var step := float(profile.g("relief.level_step_m", 0.6))
	# force des paliers (0 = pente continue, 1 = marches pleines) : les plateaux planifiés sont déjà à un multiple
	# du pas et ne bougent pas ; les pentes naturelles gardent une partie de leur inclinaison (moins de « gâteaux de mariage »)
	var strength := clampf(float(profile.g("relief.terrace_strength", 1.0)), 0.0, 1.0)
	for i in n * n:
		if field.top[i] == TerrainField.NO_GROUND:
			continue
		var t := _heights[i] / step
		var f := t - floorf(t)
		var q := (floorf(t) + _smooth((f - 0.3) / 0.4)) * step
		q = lerpf(_heights[i], q, strength)
		field.top[i] = maxi(roundi(q / V) - 1, 2)

# ------------------------------------------------------------------ 6. nettoyage

## Supprime pics, creux et cellules isolées : une colonne dont la hauteur est partagée par aucune
## de ses 8 voisines prend la hauteur majoritaire de ses voisines.
func _cleanup() -> void:
	var n := field.n
	var changed_total := 0
	for pass_i in 3:
		var next := field.top.duplicate()
		var changed := 0
		for cz in range(1, n - 1):
			for cx in range(1, n - 1):
				var i := cx + cz * n
				var t := field.top[i]
				if t == TerrainField.NO_GROUND:
					continue
				var same := 0
				var counts := {}
				var land := 0
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dz == 0:
							continue
						var u := field.top[(cx + dx) + (cz + dz) * n]
						if u == TerrainField.NO_GROUND:
							continue
						land += 1
						if u == t:
							same += 1
						counts[u] = int(counts.get(u, 0)) + 1
				if land >= 5 and same <= 1:
					var best := t
					var best_n := 0
					for k in counts:
						if counts[k] > best_n or (counts[k] == best_n and absi(k - t) < absi(best - t)):
							best_n = counts[k]
							best = k
					if best != t and best_n >= 3:
						next[i] = best
						changed += 1
		field.top = next
		changed_total += changed
		if changed == 0:
			break
	report["cleaned_columns"] = changed_total

# ------------------------------------------------------------------ 3. espaces habitables

func _find_plateaus() -> void:
	var n := field.n
	var label := PackedInt32Array()
	label.resize(n * n)
	var plateaus: Array = []
	var next_label := 1
	for start in n * n:
		var t0 := field.top[start]
		if t0 == TerrainField.NO_GROUND or label[start] != 0:
			continue
		var stack := [start]
		label[start] = next_label
		var cells: Array[int] = []
		while not stack.is_empty():
			var i: int = stack.pop_back()
			cells.append(i)
			var cx := i % n
			var cz := i / n
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x: int = cx + o.x
				var z: int = cz + o.y
				if x < 0 or z < 0 or x >= n or z >= n:
					continue
				var j := x + z * n
				if label[j] == 0 and field.top[j] == t0:
					label[j] = next_label
					stack.append(j)
		next_label += 1
		if cells.size() < 90:
			continue
		# Rayon inscrit : distance (en colonnes) au bord de la composante, par chanfrein.
		var inset := _inscribed(cells, label, label[start])
		if inset.radius_m < 1.1:
			continue
		var sx := 0.0
		var sz := 0.0
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		var emin := 1.0e9
		for i in cells:
			sx += float(i % n)
			sz += float(i / n)
			lo = Vector2i(mini(lo.x, i % n), mini(lo.y, i / n))
			hi = Vector2i(maxi(hi.x, i % n), maxi(hi.y, i / n))
			emin = minf(emin, field.edge_dist[i])
		plateaus.append({
			"id": plateaus.size(), "level": t0, "cells": cells.size(),
			"area_m2": cells.size() * V * V,
			"centroid": field.center_m(int(sx / cells.size()), int(sz / cells.size())),
			"rect": Rect2i(lo, hi - lo + Vector2i.ONE), "edge_m": emin,
			"inscribed_m": inset.radius_m, "center": inset.center,
		})
	plateaus.sort_custom(func(a, b): return a.inscribed_m > b.inscribed_m)
	for k in plateaus.size():
		plateaus[k]["id"] = k
	field.plateaus = plateaus
	report["plateaus"] = plateaus.size()

func _inscribed(cells: Array[int], label: PackedInt32Array, lab: int) -> Dictionary:
	var n := field.n
	var d := {}
	for i in cells:
		d[i] = 1.0e6
	# Les cellules de bord (voisine hors composante) valent 1 ; propagation par balayage.
	var frontier: Array[int] = []
	for i in cells:
		var cx := i % n
		var cz := i / n
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x: int = cx + o.x
			var z: int = cz + o.y
			if x < 0 or z < 0 or x >= n or z >= n or label[x + z * n] != lab:
				d[i] = 1.0
				frontier.append(i)
				break
	var head := 0
	while head < frontier.size():
		var i: int = frontier[head]
		head += 1
		var cx := i % n
		var cz := i / n
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x: int = cx + o.x
			var z: int = cz + o.y
			if x < 0 or z < 0 or x >= n or z >= n:
				continue
			var j := x + z * n
			if d.has(j) and d[j] > d[i] + 1.0:
				d[j] = d[i] + 1.0
				frontier.append(j)
	var best := 0.0
	var best_i := cells[0]
	for i in cells:
		if d[i] > best:
			best = d[i]
			best_i = i
	return {"radius_m": (best - 0.5) * V, "center": field.center_m(best_i % n, best_i / n)}

# ------------------------------------------------------------------ 5. détails naturels

func _materials() -> void:
	var n := field.n
	var pal := VoxelPalette.get_default()
	var moist := WorldRng.noise(seed, "moisture", float(profile.g("climate.moisture_freq", 0.03)), 2)
	var rocky := WorldRng.noise(seed, "rockiness", 0.06, 2)
	var lush := float(profile.g("climate.lush_above", 0.62))
	var dry := float(profile.g("climate.dry_below", 0.3))
	var rock_step := int(profile.g("cliff.rock_step", 3))
	var ids := {
		"lush": pal.id("grass_lush"), "dry": pal.id("grass_dry"), "wild": pal.id("grass_wild"), "grass": pal.id("grass"),
		"warm": pal.id("rock_warm"), "grey": pal.id("rock_grey"),
	}
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			var p := field.center_m(cx, cz)
			var m := moist.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			var slope := field.step_at(cx, cz)
			var id: int = ids["grass"]
			if slope >= rock_step or (rocky.get_noise_2d(p.x, p.y) > 0.62 and slope >= 1):
				id = ids["warm"] if rocky.get_noise_2d(p.y, p.x) > 0.0 else ids["grey"]
			elif field.edge_dist[i] < 0.5:
				id = ids["dry"]
			elif m > lush:
				id = ids["lush"]
			elif m < dry:
				id = ids["dry"]
			else:
				id = ids["wild"] if m < 0.5 else ids["grass"]
			field.material[i] = id
			field.zone[i] = TerrainField.Zone.NATURAL

## Sous-face : épaisseur de base lissée + cônes (stalactites) placés par disque de Poisson.
func _underside(r: float) -> void:
	var n := field.n
	var depth := WorldRng.range_f(_rng, profile.g("underside.depth_m", [13.0, 17.0]))
	var t_min := float(TerrainField.SURFACE_DEPTH + 4) * V + 0.6
	var lump := WorldRng.noise(seed, "underside", 0.05, 2)
	var spikes := []
	var want := WorldRng.range_i(_rng, profile.g("underside.spikes", [6, 10]))
	var len_r: Array = profile.g("underside.spike_len_m", [3.0, 8.0])
	var rad_r: Array = profile.g("underside.spike_radius_m", [1.6, 3.2])
	var tries := 0
	while spikes.size() < want and tries < 600:
		tries += 1
		var c := Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r))
		var col := field.col_of_m(c.x, c.y)
		if not field.has_ground(col.x, col.y):
			continue
		var e := clampf(field.edge_dist[field.idx(col.x, col.y)] / (0.7 * r), 0.0, 1.0)
		if e < 0.12 or _rng.randf() > 0.35 + e:
			continue
		var rad := WorldRng.range_f(_rng, rad_r)
		var ok := true
		for s in spikes:
			if s.c.distance_to(c) < (s.r + rad) * 1.1:
				ok = false
				break
		if not ok:
			continue
		spikes.append({"c": c, "r": rad, "len": WorldRng.range_f(_rng, len_r) * (0.55 + 0.6 * e)})
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			var p := field.center_m(cx, cz)
			var e := clampf(field.edge_dist[i] / (0.85 * r), 0.0, 1.0)
			var thick := t_min + depth * pow(_smooth(e), 1.15) + lump.get_noise_2d(p.x, p.y) * 1.2 * e
			for s in spikes:
				var d: float = p.distance_to(s.c)
				if d < s.r:
					thick += s.len * pow(1.0 - d / s.r, 1.35)
			field.bottom[i] = field.top[i] - roundi(thick / V)
	field.landmarks["spikes"] = spikes
	# Racines pendantes sous le bord (positions structurées : espacées, pas de semis aléatoire).
	var roots := []
	var rcount := WorldRng.range_i(_rng, profile.g("underside.roots", [6, 12]))
	tries = 0
	while roots.size() < rcount and tries < 500:
		tries += 1
		var a := _rng.randf() * TAU
		var rr := r * _rng.randf_range(0.5, 0.82)
		var c := Vector2(cos(a), sin(a)) * rr
		var col := field.col_of_m(c.x, c.y)
		if not field.has_ground(col.x, col.y):
			continue
		var ok := true
		for q in roots:
			if q.c.distance_to(c) < 2.0:
				ok = false
				break
		if ok:
			roots.append({"c": c, "len": _rng.randi_range(4, 12)})
	field.landmarks["roots"] = roots
	report["spikes"] = spikes.size()

## Définit le cœur fixe à partir du relief NATUREL (avant tout aménagement).
func _finish_core() -> void:
	for i in field.n * field.n:
		if field.top[i] == TerrainField.NO_GROUND:
			continue
		field.natural_top[i] = field.top[i]
		field.core_top[i] = field.top[i] - TerrainField.SURFACE_DEPTH
