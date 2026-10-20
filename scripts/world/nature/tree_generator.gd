@tool
class_name TreeGenerator
extends RefCounted
## Arbres PARAMÉTRIQUES : un squelette (tronc, branches, racines) puis un feuillage en amas.
##   - le bois est en cellules de 10 cm (tronc effilé, branches continues, racines qui épousent la pente) ;
##   - le feuillage est en cellules de 20 cm (amas ellipsoïdaux bosselés ou rideaux), centrés sur l'extrémité
##     d'une branche : jamais de feuille sans branche ;
##   - le pied est ENRACINÉ : socle sous le tronc jusqu'au point le plus bas du sol, empattement et racines
##     de surface qui plongent dans le terrain réel (grille de hauteurs fournie par le placement).
## Deux étapes pour s'intégrer au placement universel :
##   plan(espèce, graine)           → squelette + emprise (sert à écrire le PlacementSpec)
##   rasterize(plan, sol)           → volumes voxel, une fois la position validée
## Aucune dépendance à une île : la graine et le sol local suffisent.

const C := 0.1
const F := 0.2

const SPECIES := {
	"oak": {"h": [2.6, 3.4], "r0": [0.40, 0.48], "r1": 0.24, "lean": 0.06, "wobble": 0.10, "bark": "bark",
		"limbs": {"t": [0.55, 0.92], "count": [4, 6], "pitch": [42, 68], "len": [1.7, 2.7], "r": 0.5, "droop": 0.25, "children": {"p": 0.6, "pitch": [28, 50], "len": 0.55}},
		"blob": {"r": [1.1, 1.55], "flat": 0.82, "lift": 0.35, "top": [2.0, 2.4]},
		"leaf": ["leaves", "leaves", "leaf_light", "leaf_dark"]},
	"parasol": {"h": [4.2, 5.6], "r0": [0.26, 0.32], "r1": 0.15, "lean": 0.16, "wobble": 0.22, "bark": "bark",
		"limbs": {"t": [0.78, 0.98], "count": [3, 5], "pitch": [66, 82], "len": [1.8, 2.7], "r": 0.5, "droop": -0.15, "children": {"p": 0.25, "pitch": [20, 40], "len": 0.45}},
		"blob": {"r": [1.5, 2.0], "flat": 0.36, "lift": 0.1, "top": [1.6, 2.0]},
		"leaf": ["leaf_light", "leaves", "leaf_light", "leaf_olive"]},
	"pine": {"h": [5.6, 7.6], "r0": [0.26, 0.34], "r1": 0.06, "lean": 0.03, "wobble": 0.05, "bark": "bark_dark",
		"tiers": {"from": 0.22, "step": 1.05, "r0": 1.75, "r1": 0.3, "h": 0.62},
		"leaf": ["pine", "pine", "leaf_dark", "pine"]},
	"weeping": {"h": [2.6, 3.4], "r0": [0.32, 0.4], "r1": 0.18, "lean": 0.08, "wobble": 0.12, "bark": "bark",
		"limbs": {"t": [0.7, 0.96], "count": [4, 6], "pitch": [38, 62], "len": [1.6, 2.3], "r": 0.5, "droop": 0.9, "children": {"p": 0.0, "pitch": [20, 30], "len": 0.4}},
		"blob": {"r": [0.9, 1.2], "flat": 0.7, "lift": 0.0, "top": [1.3, 1.6]},
		"strands": {"len": [1.1, 2.1], "density": 0.55},
		"leaf": ["leaf_olive", "leaf_light", "leaf_olive", "leaves"]},
	"birch": {"h": [3.8, 5.0], "r0": [0.17, 0.22], "r1": 0.08, "lean": 0.11, "wobble": 0.15, "bark": "bark_birch", "marks": true,
		"limbs": {"t": [0.5, 0.95], "count": [5, 7], "pitch": [28, 48], "len": [1.0, 1.6], "r": 0.45, "droop": 0.0, "children": {"p": 0.3, "pitch": [20, 35], "len": 0.5}},
		"blob": {"r": [0.75, 1.0], "flat": 0.95, "lift": 0.2, "top": [1.1, 1.4]},
		"leaf": ["leaf_light", "leaves", "leaf_light", "leaf_light"]},
	"fruit": {"h": [1.8, 2.4], "r0": [0.26, 0.32], "r1": 0.16, "lean": 0.05, "wobble": 0.1, "bark": "bark", "fruits": true,
		"limbs": {"t": [0.6, 0.95], "count": [4, 5], "pitch": [38, 58], "len": [1.1, 1.6], "r": 0.5, "droop": 0.15, "children": {"p": 0.3, "pitch": [25, 40], "len": 0.5}},
		"blob": {"r": [1.0, 1.3], "flat": 0.88, "lift": 0.25, "top": [1.5, 1.9]},
		"leaf": ["leaves", "leaf_light", "leaves", "leaf_dark"]},
	"dead": {"h": [3.0, 4.2], "r0": [0.26, 0.34], "r1": 0.1, "lean": 0.12, "wobble": 0.22, "bark": "bark_dark",
		"limbs": {"t": [0.35, 0.95], "count": [5, 7], "pitch": [35, 75], "len": [1.0, 2.0], "r": 0.4, "droop": 0.3, "children": {"p": 0.7, "pitch": [30, 60], "len": 0.55}},
		"leaf": []},
}

## Espèces selon le biome (humidité du sol) ; la graine tranche.
static func species_for(biome: String, rng: RandomNumberGenerator) -> String:
	var table: Array
	match biome:
		"lush": table = ["oak", "birch", "weeping", "fruit", "oak", "birch"]
		"dry": table = ["parasol", "pine", "dead", "parasol", "pine"]
		"rock": table = ["pine", "dead", "pine", "parasol"]
		_: table = ["oak", "parasol", "birch", "pine", "fruit", "weeping"]
	return table[rng.randi() % table.size()]

# ------------------------------------------------------------------ squelette

static func plan(species: String, seed: int) -> Dictionary:
	var def: Dictionary = SPECIES[species]
	var rng := WorldRng.stream(seed, "tree:" + species)
	var segs: Array[Dictionary] = []
	var blobs: Array[Dictionary] = []
	var tips: Array[Vector3] = []
	var h: float = rng.randf_range(def["h"][0], def["h"][1])
	var r0: float = rng.randf_range(def["r0"][0], def["r0"][1])
	var r1: float = def["r1"]
	var lean_a := rng.randf() * TAU
	var lean := Vector2.from_angle(lean_a) * float(def["lean"]) * h
	var wob: float = def["wobble"]
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var n := maxi(int(h / 0.4), 4)
	var pts: Array[Vector3] = []
	for i in range(n + 1):
		var t := float(i) / float(n)
		var p := Vector3(lean.x * t * t + sin(t * 4.0 + ph1) * wob * t, h * t, lean.y * t * t + sin(t * 3.3 + ph2) * wob * t)
		pts.append(p)
		if i > 0:
			segs.append({"a": pts[i - 1], "b": p, "r0": lerpf(r0, r1, float(i - 1) / n), "r1": lerpf(r0, r1, t), "kind": "trunk"})
	var ctx := {"rng": rng, "segs": segs, "blobs": blobs, "tips": tips, "def": def}
	if def.has("limbs"):
		var L: Dictionary = def["limbs"]
		var count := rng.randi_range(int(L["count"][0]), int(L["count"][1]))
		var a0 := rng.randf() * TAU
		for k in count:
			var t := rng.randf_range(L["t"][0], L["t"][1])
			var idx := clampi(int(t * n), 1, n)
			var start := pts[idx]
			var az := a0 + TAU * float(k) / float(count) + rng.randf_range(-0.35, 0.35)
			var pitch := deg_to_rad(rng.randf_range(L["pitch"][0], L["pitch"][1]))
			var dir := Vector3(sin(pitch) * cos(az), cos(pitch), sin(pitch) * sin(az))
			var length: float = rng.randf_range(L["len"][0], L["len"][1])
			var rb: float = lerpf(r0, r1, t) * float(L["r"])
			_limb(ctx, start, dir, length, rb, rb * 0.45, float(L["droop"]), L["children"], 0)
	if def.has("tiers"):
		_tiers(ctx, pts, h, r0)
	# couronne sommitale pour les espèces à feuillage rond
	if def.has("blob") and def.has("limbs"):
		var B: Dictionary = def["blob"]
		var top := pts[n]
		var rad: float = rng.randf_range(B["top"][0], B["top"][1])
		blobs.append({"c": top + Vector3(0, rad * 0.35, 0), "radii": Vector3(rad, rad * float(B["flat"]) * 0.95, rad)})
		tips.append(top)
	# emprise (m, repère centré sur le pied) : bois + feuillage
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for s in segs:
		for p in [s["a"], s["b"]]:
			lo = lo.min(p - Vector3.ONE * float(s["r0"]))
			hi = hi.max(p + Vector3.ONE * float(s["r0"]))
	var crown_lo := Vector3(1e9, 1e9, 1e9)
	var crown_hi := Vector3(-1e9, -1e9, -1e9)
	for b in blobs:
		crown_lo = crown_lo.min(b["c"] - b["radii"])
		crown_hi = crown_hi.max(b["c"] + b["radii"])
	var strands_len := 0.0
	if def.has("strands"):
		strands_len = float(def["strands"]["len"][1])
		crown_lo.y -= strands_len
	var all_lo := lo.min(crown_lo) if not blobs.is_empty() else lo
	var all_hi := hi.max(crown_hi) if not blobs.is_empty() else hi
	return {"species": species, "seed": seed, "segs": segs, "blobs": blobs, "tips": tips, "height": all_hi.y, "trunk_r": r0, "trunk_top": pts[n],
		"aabb": AABB(all_lo, all_hi - all_lo), "crown": AABB(crown_lo, crown_hi - crown_lo) if not blobs.is_empty() else AABB(),
		"wood_aabb": AABB(lo, hi - lo), "def": def.duplicate(true), "base": pts[0]}

static func _limb(ctx: Dictionary, start: Vector3, dir: Vector3, length: float, r_a: float, r_b: float, droop: float, children: Dictionary, depth: int) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var steps := maxi(int(length / 0.35), 2)
	var pos := start
	var d := dir.normalized()
	for i in steps:
		var t := float(i + 1) / float(steps)
		d = (d + Vector3(rng.randf_range(-0.12, 0.12), -droop / float(steps) * 1.6, rng.randf_range(-0.12, 0.12))).normalized()
		var nxt := pos + d * (length / float(steps))
		(ctx["segs"] as Array).append({"a": pos, "b": nxt, "r0": lerpf(r_a, r_b, float(i) / steps), "r1": lerpf(r_a, r_b, t), "kind": "limb"})
		if depth == 0 and i >= 1 and i < steps - 1 and rng.randf() < float(children["p"]):
			var axis := d.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1.0), rng.randf_range(-1, 1))).normalized()
			if axis.length() > 0.1:
				var ang := deg_to_rad(rng.randf_range(children["pitch"][0], children["pitch"][1]))
				var cd := d.rotated(axis, ang)
				var cl := length * float(children["len"]) * (1.0 - t * 0.4)
				_limb(ctx, nxt, cd, cl, lerpf(r_a, r_b, t) * 0.6, r_b * 0.5, droop * 0.5, children, depth + 1)
		pos = nxt
	(ctx["tips"] as Array).append(pos)
	var def: Dictionary = ctx["def"]
	if def.has("blob"):
		var B: Dictionary = def["blob"]
		var rad: float = rng.randf_range(B["r"][0], B["r"][1]) * (0.7 if depth > 0 else 1.0)
		(ctx["blobs"] as Array).append({"c": pos + Vector3(0, rad * float(B["lift"]), 0), "radii": Vector3(rad, rad * float(B["flat"]), rad)})

static func _tiers(ctx: Dictionary, pts: Array[Vector3], h: float, r0: float) -> void:
	var T: Dictionary = (ctx["def"] as Dictionary)["tiers"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var y := float(T["from"]) * h
	var n := pts.size() - 1
	while y < h - 0.5:
		var t := y / h
		var idx := clampi(int(t * n), 0, n)
		var base := pts[idx]
		var rad := lerpf(float(T["r0"]), float(T["r1"]), t) * rng.randf_range(0.9, 1.1)
		var th := float(T["h"])
		(ctx["blobs"] as Array).append({"c": base + Vector3(0, th * 0.35, 0), "radii": Vector3(rad, th, rad)})
		# branche courte vers le bas de l'étage : l'étage est porté par le tronc
		(ctx["segs"] as Array).append({"a": base, "b": base + Vector3(rad * 0.45, th * 0.2, 0), "r0": 0.07, "r1": 0.05, "kind": "limb"})
		(ctx["tips"] as Array).append(base)
		y += float(T["step"]) * rng.randf_range(0.85, 1.15)
	# pointe
	var top := pts[n]
	(ctx["blobs"] as Array).append({"c": top + Vector3(0, 0.25, 0), "radii": Vector3(0.38, 0.75, 0.38)})

# ------------------------------------------------------------------ sol local

## Grille de hauteurs du sol autour du pied, relatives à `base_y` (m) : sert à enraciner l'arbre.
static func ground_grid(field: TerrainField, base: Vector3, half := 2.0) -> Dictionary:
	var step := 0.2
	var n := int(ceil(half * 2.0 / step)) + 1
	var h := PackedFloat32Array()
	h.resize(n * n)
	for iz in n:
		for ix in n:
			var x := base.x - half + float(ix) * step
			var z := base.z - half + float(iz) * step
			var g := field.ground_at_m(x, z)
			h[ix + iz * n] = (g - base.y) if not is_nan(g) else NAN
	return {"half": half, "step": step, "n": n, "h": h}

static func ground_at(g: Dictionary, x: float, z: float) -> float:
	if g.is_empty():
		return 0.0
	var step: float = g["step"]
	var half: float = g["half"]
	var n: int = g["n"]
	var ix := clampi(int(round((x + half) / step)), 0, n - 1)
	var iz := clampi(int(round((z + half) / step)), 0, n - 1)
	var v: float = (g["h"] as PackedFloat32Array)[ix + iz * n]
	return v if not is_nan(v) else -1.0

# ------------------------------------------------------------------ voxels

static func rasterize(pl: Dictionary, ground: Dictionary) -> Dictionary:
	var pal := VoxelPalette.get_default()
	var def: Dictionary = pl["def"]
	var segs: Array = pl["segs"]
	var blobs: Array = pl["blobs"]
	var seed: int = pl["seed"]
	var rng := WorldRng.stream(seed, "tree_raster")
	var bark_id := pal.id(def["bark"])
	var root_id := pal.id("root") if def["bark"] != "bark_birch" else pal.id("bark_dark")
	# --- bois ---
	var wood_aabb: AABB = pl["wood_aabb"]
	var r_base: float = pl["trunk_r"]
	var min_ground := 0.0
	if not ground.is_empty():
		var half: float = ground["half"]
		for gz in range(-4, 5):
			for gx in range(-4, 5):
				if Vector2(gx, gz).length() <= r_base / 0.2 + 1.5:
					min_ground = minf(min_ground, ground_at(ground, float(gx) * 0.2, float(gz) * 0.2))
	var reach := 1.5
	var lo := Vector3(minf(wood_aabb.position.x, -reach), minf(wood_aabb.position.y, min_ground - 0.6), minf(wood_aabb.position.z, -reach)) - Vector3(0.2, 0.0, 0.2)
	var hi := Vector3(maxf(wood_aabb.end.x, reach), wood_aabb.end.y, maxf(wood_aabb.end.z, reach)) + Vector3(0.2, 0.2, 0.2)
	lo = (lo / C).floor() * C
	var wsize := Vector3i(ceili((hi.x - lo.x) / C), ceili((hi.y - lo.y) / C), ceili((hi.z - lo.z) / C))
	var wood := VoxelVolume.new(wsize)
	for s in segs:
		VoxelShapes.capsule(wood, lo, C, s["a"], s["b"], s["r0"], s["r1"], bark_id)
	# empattement et socle : le tronc plonge sous le sol jusqu'à son point le plus bas
	var plug_bottom := min_ground - 0.5
	VoxelShapes.capsule(wood, lo, C, Vector3(0, plug_bottom, 0), Vector3(0, 0.15, 0), r_base * 1.05, r_base * 1.05, bark_id)
	VoxelShapes.capsule(wood, lo, C, Vector3(0, 0.55, 0), Vector3(0, -0.1, 0), r_base * 0.95, r_base * 1.4, bark_id)
	# racines de surface : de l'empattement vers le point du sol le plus proche, plongeantes
	var nroots := rng.randi_range(3, 5)
	var ra := rng.randf() * TAU
	for k in nroots:
		var ang := ra + TAU * float(k) / float(nroots) + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(0.75, 1.25) + r_base
		var dir := Vector2.from_angle(ang)
		var tip_xz := dir * dist
		var tip_y := ground_at(ground, tip_xz.x, tip_xz.y) - 0.08
		var mid_xz := dir * (dist * 0.5)
		var mid_y := maxf(ground_at(ground, mid_xz.x, mid_xz.y), 0.0) + 0.1
		var p0 := Vector3(dir.x * r_base * 0.7, 0.45, dir.y * r_base * 0.7)
		var p1 := Vector3(mid_xz.x, mid_y, mid_xz.y)
		var p2 := Vector3(tip_xz.x, tip_y, tip_xz.y)
		VoxelShapes.capsule(wood, lo, C, p0, p1, r_base * 0.45, r_base * 0.3, root_id)
		VoxelShapes.capsule(wood, lo, C, p1, p2, r_base * 0.3, 0.07, root_id)
	# marques d'écorce du bouleau
	if def.get("marks", false):
		var dark := pal.id("bark_dark")
		for z in wood.size.z:
			for y in wood.size.y:
				for x in wood.size.x:
					if wood.get_voxel(x, y, z) == bark_id and (y % 4 == 0 or y % 7 == 3) and VoxelGrid.hash01(x, y, z, seed) < 0.38:
						wood.set_voxel(x, y, z, dark)
	var removed_wood := VoxelShapes.keep_largest(wood)
	# --- feuillage (20 cm) ---
	var foliage: VoxelVolume = null
	var f_origin := Vector3.ZERO
	var leaf_ids: Array[int] = []
	for k in (def["leaf"] as Array):
		leaf_ids.append(pal.id(k))
	if not blobs.is_empty() and not leaf_ids.is_empty():
		var clo := Vector3(1e9, 1e9, 1e9)
		var chi := Vector3(-1e9, -1e9, -1e9)
		for b in blobs:
			clo = clo.min(b["c"] - b["radii"] * 1.3)
			chi = chi.max(b["c"] + b["radii"] * 1.3)
		var strands: Dictionary = def.get("strands", {})
		if not strands.is_empty():
			clo.y -= float(strands["len"][1]) + 0.3
		f_origin = (clo / F).floor() * F
		var fsize := Vector3i(ceili((chi.x - f_origin.x) / F), ceili((chi.y - f_origin.y) / F), ceili((chi.z - f_origin.z) / F)) + Vector3i(2, 2, 2)
		foliage = VoxelVolume.new(fsize)
		var fruit_ids: Array[int] = []
		if def.get("fruits", false):
			fruit_ids = [pal.id("apple"), pal.id("blossom")]
		for bi in blobs.size():
			var b: Dictionary = blobs[bi]
			var c: Vector3 = b["c"]
			var radii: Vector3 = b["radii"]
			var pick := func(x: int, y: int, z: int, d: float) -> int:
				var nz := VoxelGrid.hash01(x, y, z, seed)
				if d + (nz - 0.5) * 0.32 > 1.0:
					return 0
				var topness: float = float(y) * F + f_origin.y - c.y
				var v := VoxelGrid.hash01(x / 2, y / 2, z / 2, seed + 7)
				var idx := int(v * float(leaf_ids.size())) % leaf_ids.size()
				if topness > radii.y * 0.3 and v > 0.45:
					idx = 1 % leaf_ids.size()
				if not fruit_ids.is_empty() and d > 0.8 and nz < 0.1:
					return fruit_ids[int(nz * 100.0) % fruit_ids.size()]
				return leaf_ids[idx]
			VoxelShapes.ellipsoid_pick(foliage, f_origin, F, c, radii, pick)
		if not strands.is_empty():
			var dens: float = strands["density"]
			for b in blobs:
				var c: Vector3 = b["c"]
				var radii: Vector3 = b["radii"]
				var sl: float = rng.randf_range(strands["len"][0], strands["len"][1])
				for iz in range(-6, 7):
					for ix in range(-6, 7):
						var ox := float(ix) * F
						var oz := float(iz) * F
						var rr := Vector2(ox / radii.x, oz / radii.z).length()
						if rr > 1.0 or rr < 0.45:
							continue
						var cx := int(floor((c.x + ox - f_origin.x) / F))
						var cz := int(floor((c.z + oz - f_origin.z) / F))
						if VoxelGrid.hash01(cx, cz, 5, seed) > dens:
							continue
						var top_y := c.y - radii.y * sqrt(maxf(1.0 - rr * rr, 0.0)) * 0.6
						var len_c := int((sl * (0.55 + 0.45 * VoxelGrid.hash01(cx, cz, 9, seed))) / F)
						var cy0 := int(floor((top_y - f_origin.y) / F))
						for k in len_c:
							foliage.set_voxel(cx, cy0 - k, cz, leaf_ids[(cx + cz + k) % leaf_ids.size()])
	var stats := {"wood_cells": wood.count_solid(), "foliage_cells": foliage.count_solid() if foliage != null else 0, "floating_removed": removed_wood,
		"blobs": blobs.size()}
	return {"wood": wood, "wood_origin": lo, "foliage": foliage, "foliage_origin": f_origin, "stats": stats, "plan": pl}

## Contrôle de conception (utilisé par le validateur) : rien ne flotte, chaque amas touche du bois,
## le pied plonge dans le sol. Renvoie une liste de défauts.
static func check(model: Dictionary, ground: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var wood: VoxelVolume = model["wood"]
	var lo: Vector3 = model["wood_origin"]
	# 1) une seule composante de bois, et elle touche le bas du volume sous le sol
	var comps := VoxelShapes.components(wood)
	if comps.size() > 1:
		issues.append("bois en %d morceaux" % comps.size())
	if comps.is_empty():
		issues.append("arbre sans bois")
		return issues
	# 2) le pied est sous le niveau du sol en tout point de son empreinte (pas de jour sous le tronc)
	var pl: Dictionary = model["plan"]
	var r: float = pl["trunk_r"]
	var gaps := 0
	for gz in range(-3, 4):
		for gx in range(-3, 4):
			var off := Vector2(gx, gz) * 0.1
			if off.length() > r * 0.8:
				continue
			var gy := ground_at(ground, off.x, off.y)
			var cx := int(floor((off.x - lo.x) / C))
			var cz := int(floor((off.y - lo.z) / C))
			var cy := int(floor((gy - 0.05 - lo.y) / C))
			if wood.get_voxel(cx, cy, cz) == 0:
				gaps += 1
	if gaps > 0:
		issues.append("jour sous le tronc (%d colonnes)" % gaps)
	# 3) chaque amas de feuillage a du bois à moins de 30 cm de son centre
	var segs: Array = pl["segs"]
	for b in pl["blobs"]:
		var ok := false
		for s in segs:
			if (b["c"] as Vector3).distance_to(s["b"]) < maxf((b["radii"] as Vector3).y, 0.5) + 0.3:
				ok = true
				break
		if not ok:
			issues.append("amas de feuillage sans branche")
			break
	return issues
