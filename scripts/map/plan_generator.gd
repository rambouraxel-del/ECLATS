@tool
class_name PlanGenerator
extends RefCounted
## Générateur de PLAN d'île (Lot 7) : (graine, largeur, longueur, réglages) → IslandPlan, entièrement déterministe.
## Profil « île d'arrivée » : une crique avec le point d'arrivée en contrebas, un plateau habitable, une zone boisée et un
## point haut. Les chemins relient ces lieux en chaîne (arrivée → plateau → bois → sommet) ; leur tracé est sinueux et les
## hauteurs des zones sont choisies pour que la pente reste praticable à pied (≤ GRADE_PLAN) : le relief suit les chemins.

const GRADE_PLAN := 0.17            # pente visée le long d'un chemin (15 % ≈ 8,5°)
const PATH_WIDTH := 2.2

static func generate(seed: int, width: float, length: float, opts := {}) -> IslandPlan:
	var W := clampf(width, IslandPlan.MIN_SIZE, IslandPlan.MAX_SIZE)
	var L := clampf(length, IslandPlan.MIN_SIZE, IslandPlan.MAX_SIZE)
	var rng := WorldRng.stream(seed, "plan")
	var p := IslandPlan.new()
	p.seed = seed
	p.width = snappedf(W, 0.1)
	p.length = snappedf(L, 0.1)
	p.settings = {"relief": float(opts.get("relief", 1.0))}
	p.name = "Île %d · %d × %d m" % [seed, int(W), int(L)]
	p.generated = true
	var th0 := rng.randf() * TAU
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	p.outline = _outline(seed, rng, W, L, th0, side)
	var sc := clampf(minf(W, L) / 52.0, 0.62, 1.8)
	# --- zones : angle relatif à la crique, distance relative au rayon du contour
	var r_arr := 4.4 * sc * rng.randf_range(0.95, 1.1)
	var r_pla := 6.4 * sc * rng.randf_range(0.9, 1.1)
	var r_boi := 5.6 * sc * rng.randf_range(0.9, 1.1)
	var r_som := 4.6 * sc * rng.randf_range(0.9, 1.1)
	var R0 := _ray(p.outline, th0)
	var c_arr := Vector2.from_angle(th0) * maxf(R0 - r_arr - 2.6, R0 * 0.35)
	var th_p := th0 + side * rng.randf_range(1.3, 1.5)
	var th_b := th0 + side * rng.randf_range(2.55, 2.75)
	var th_s := th0 + side * rng.randf_range(3.65, 3.95)
	var c_pla := Vector2.from_angle(th_p) * _ray(p.outline, th_p) * rng.randf_range(0.56, 0.62)
	var c_boi := Vector2.from_angle(th_b) * _ray(p.outline, th_b) * rng.randf_range(0.56, 0.62)
	var c_som := Vector2.from_angle(th_s) * _ray(p.outline, th_s) * rng.randf_range(0.46, 0.52)
	var specs := [
		{"id": "arrivee", "kind": "arrivee", "c": c_arr, "r": r_arr},
		{"id": "plateau", "kind": "plateau", "c": c_pla, "r": r_pla},
		{"id": "bois", "kind": "bois", "c": c_boi, "r": r_boi},
		{"id": "sommet", "kind": "sommet", "c": c_som, "r": r_som},
	]
	# ajuste chaque disque : dans le contour avec marge, sans chevauchement des précédents
	for k in specs.size():
		var s: Dictionary = specs[k]
		for attempt in 16:
			var in_out := IslandPlan.point_in_poly(s["c"], p.outline) and IslandPlan.dist_to_poly(s["c"], p.outline) >= float(s["r"]) + 1.6
			var overlap := false
			for j in k:
				var o: Dictionary = specs[j]
				if (s["c"] as Vector2).distance_to(o["c"]) < float(s["r"]) + float(o["r"]) + 2.0:
					overlap = true
			if in_out and not overlap:
				break
			if not in_out:
				s["c"] = (s["c"] as Vector2) * 0.95
			if overlap or attempt > 8:
				s["r"] = float(s["r"]) * 0.94
	for s in specs:
		var kd: Dictionary = IslandPlan.KINDS[s["kind"]]
		p.zones.append({"id": s["id"], "kind": s["kind"], "c": _round2(s["c"]), "r": snappedf(float(s["r"]), 0.1), "h": float(kd["h"])})
	# la zone boisée est un amas : disque principal + deux disques satellites
	var bz: Dictionary = p.zone_by_id("bois")
	for k in 2:
		var a := rng.randf() * TAU
		var rr := float(bz["r"]) * rng.randf_range(0.6, 0.8)
		var cc: Vector2 = bz["c"] + Vector2.from_angle(a) * float(bz["r"]) * 0.75
		if IslandPlan.dist_to_poly(cc, p.outline) >= rr + 1.2 and IslandPlan.point_in_poly(cc, p.outline):
			p.zones.append({"id": "bois_%d" % (k + 2), "kind": "bois", "c": _round2(cc), "r": snappedf(rr, 0.1), "h": float(bz["h"])})
	# --- chemins en chaîne, puis hauteurs des zones d'après la longueur réelle des tracés
	var chain := ["arrivee", "plateau", "bois", "sommet"]
	var want := {"plateau": 2.6, "bois": 2.0, "sommet": 3.4}
	var h := float(IslandPlan.KINDS["arrivee"]["h"]) + rng.randf_range(-0.4, 0.4)
	p.zone_by_id("arrivee")["h"] = snappedf(h, 0.1)
	for k in range(1, chain.size()):
		var za: Dictionary = p.zone_by_id(chain[k - 1])
		var zb: Dictionary = p.zone_by_id(chain[k])
		var pts := _route(rng, za["c"], zb["c"], p.outline)
		p.paths.append({"id": "chemin_%d" % k, "width": PATH_WIDTH, "pts": pts, "from": za["id"], "to": zb["id"]})
		var core_a := float(za["r"]) * float(IslandPlan.KINDS[za["kind"]]["cr"])
		var core_b := float(zb["r"]) * float(IslandPlan.KINDS[zb["kind"]]["cr"])
		var eff := maxf(IslandPlan.path_length(pts) - core_a - core_b, 3.0)
		h += minf(float(want[chain[k]]), GRADE_PLAN * eff)
		zb["h"] = snappedf(h, 0.1)
		if chain[k] == "bois":
			for z in p.zones:
				if z["kind"] == "bois":
					z["h"] = zb["h"]
	# --- repères et départ
	p.landmarks.append({"id": "lieu_plateau", "kind": "lieu", "pos": _round2((p.zone_by_id("plateau")["c"] as Vector2) + Vector2(1.5, 1.0)), "label": "Clairière du plateau"})
	p.landmarks.append({"id": "vue_sommet", "kind": "vue", "pos": _round2(p.zone_by_id("sommet")["c"]), "label": "Point de vue"})
	var cape := _cape(p, th0 + side * 0.95)
	if cape != Vector2.INF:
		p.landmarks.append({"id": "vue_cap", "kind": "vue", "pos": _round2(cape), "label": "Vue sur la crique"})
	p.start = _round2(c_arr_of(p))
	p._uid = 10
	return p

static func c_arr_of(p: IslandPlan) -> Vector2:
	return p.zone_by_id("arrivee")["c"]

static func _round2(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, 0.01), snappedf(v.y, 0.01))

static func _angdiff(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI

## Silhouette : ellipse W × L déformée par trois harmoniques, un bruit de bord, une crique (entaille) et un cap (pointe).
static func _outline(seed: int, rng: RandomNumberGenerator, W: float, L: float, th0: float, side: float) -> Array:
	var n := 60
	var ph2 := rng.randf() * TAU
	var ph3 := rng.randf() * TAU
	var ph4 := rng.randf() * TAU
	var a2 := rng.randf_range(0.05, 0.11)
	var a3 := rng.randf_range(0.04, 0.08)
	var a4 := rng.randf_range(0.02, 0.05)
	var nz := WorldRng.noise(seed, "plan_rim", 0.9, 2)
	var out: Array = []
	for i in n:
		var th := float(i) * TAU / float(n)
		var r := 1.0 + a2 * cos(2.0 * th + ph2) + a3 * cos(3.0 * th + ph3) + a4 * cos(4.0 * th + ph4)
		r += nz.get_noise_2d(cos(th) * 1.6, sin(th) * 1.6) * 0.07
		var d := _angdiff(th, th0)
		r -= 0.36 * exp(-pow(d / 0.26, 2.0))
		var d2 := _angdiff(th, th0 + side * 0.95)
		r += 0.10 * exp(-pow(d2 / 0.22, 2.0))
		r = clampf(r, 0.55, 1.22)
		out.append(Vector2(snappedf(W * 0.5 * r * cos(th), 0.1), snappedf(L * 0.5 * r * sin(th), 0.1)))
	return out

## Distance de l'origine au contour dans la direction th.
static func _ray(poly: Array, th: float) -> float:
	var dir := Vector2.from_angle(th)
	var best := 0.0
	var m := poly.size()
	for i in m:
		var hit = Geometry2D.segment_intersects_segment(Vector2.ZERO, dir * 400.0, poly[i], poly[(i + 1) % m])
		if hit != null:
			var d: float = (hit as Vector2).length()
			if best == 0.0 or d < best:
				best = d
	return best

## Sommet du contour le plus proche de la direction th, ramené de 3 m vers l'intérieur.
static func _cape(p: IslandPlan, th: float) -> Vector2:
	var dir := Vector2.from_angle(th)
	var R := _ray(p.outline, th)
	if R <= 6.0:
		return Vector2.INF
	var q := dir * (R - 3.2)
	if IslandPlan.dist_to_poly(q, p.outline) < 2.0:
		return Vector2.INF
	return q

## Tracé sinueux de a vers b : points de passage tous les ~6 m, déportés latéralement (sinus) pour allonger le chemin.
static func _route(rng: RandomNumberGenerator, a: Vector2, b: Vector2, poly: Array) -> Array:
	var d := b - a
	var len := d.length()
	var segs := clampi(roundi(len / 6.0), 2, 8)
	var perp := Vector2(-d.y, d.x).normalized()
	var sgn := 1.0 if rng.randf() < 0.5 else -1.0
	var best: Array = []
	for attempt in 6:
		var amp := len * (0.20 - 0.03 * attempt) * sgn
		var pts: Array = [_round2(a)]
		for k in range(1, segs):
			var t := float(k) / float(segs)
			var q := a + d * t + perp * amp * sin(PI * t) + perp * rng.randf_range(-0.05, 0.05) * len
			pts.append(_round2(q))
		pts.append(_round2(b))
		best = pts
		var inside := true
		for q: Vector2 in pts:
			if not IslandPlan.point_in_poly(q, poly) or IslandPlan.dist_to_poly(q, poly) < 2.5:
				inside = false
		if inside:
			break
		sgn = -sgn if attempt == 2 else sgn
	return best
