@tool
class_name VillageLayout
extends RefCounted
## Plan de la première île habitée : relief, zones aplanies, escaliers, chemins, matières de sol,
## et liste des éléments à poser. Source unique de vérité : le terrain (hooks du générateur) et la
## scène de pose lisent ce même plan. Coordonnées en mètres dans le repère du nœud île
## (x vers l'est, z vers le sud, la façade des bâtiments regarde +z).

const V := VoxelGrid.VOXEL_SIZE
var base_height_m := 2.2

const PLAZA_H := 3.6
const PLAZA_R := 5.2
const HILL_C := Vector2(0.0, -14.6)
const HILL_H := 7.0

## Zones aplanies : [centre, demi-taille, hauteur du sol, largeur du raccord, nom]
const PADS := [
	[Vector2(-9.3, -9.6), Vector2(4.5, 4.0), 4.4, 2.2, "house_colonist"],
	[Vector2(8.8, -9.9), Vector2(3.7, 3.9), 4.4, 2.2, "house_cottage"],
	[Vector2(-13.4, 2.4), Vector2(3.8, 4.4), 3.6, 2.2, "workshop"],
	[Vector2(10.4, -0.4), Vector2(4.3, 4.5), 3.6, 2.0, "market"],
	[Vector2(7.0, 12.4), Vector2(4.8, 4.7), 2.4, 2.0, "warehouse"],
	[Vector2(2.0, 15.6), Vector2(8.4, 2.8), 2.4, 1.8, "port"],
	[Vector2(14.2, 6.8), Vector2(3.2, 3.2), 3.0, 2.0, "tower"],
	[Vector2(-9.2, 10.4), Vector2(5.2, 4.3), 3.2, 1.8, "garden"],
	[Vector2(-17.0, -3.0), Vector2(2.4, 3.2), 4.0, 1.8, "viewpoint"],
]

## Rampes (escaliers) : [départ, arrivée, demi-largeur, hauteur départ, hauteur arrivée, matière]
const RAMPS := [
	[Vector2(0.0, -5.0), Vector2(0.0, -12.0), 1.4, 3.6, 7.0, "stone_carved"],
	[Vector2(0.0, 5.0), Vector2(0.0, 13.0), 1.45, 3.6, 2.4, "cobble"],
	[Vector2(-4.5, 4.2), Vector2(-7.6, 7.6), 0.8, 3.6, 3.2, "gravel"],
	[Vector2(-5.2, -2.0), Vector2(-16.0, -3.0), 0.9, 3.6, 4.0, "gravel"],
]

## Chemins : [points, largeur, matière]
const PATHS := [
	[[Vector2(-9.3, -5.4), Vector2(-8.4, -4.2), Vector2(-5.6, -3.0), Vector2(-4.2, -2.6)], 1.9, "cobble"],
	[[Vector2(8.8, -5.9), Vector2(8.2, -4.4), Vector2(5.6, -3.0), Vector2(4.2, -2.4)], 1.9, "cobble"],
	[[Vector2(-9.9, 2.4), Vector2(-5.2, 1.4)], 3.2, "cobble"],
	[[Vector2(5.0, 0.0), Vector2(15.0, 0.0)], 3.6, "gravel"],
	[[Vector2(0.0, 13.0), Vector2(0.0, 15.6), Vector2(7.0, 15.6)], 3.0, "gravel"],
	[[Vector2(-4.5, 4.2), Vector2(-7.6, 7.6), Vector2(-9.2, 8.0)], 1.5, "path_dirt"],
	[[Vector2(-5.2, -2.0), Vector2(-10.0, -3.0), Vector2(-16.0, -3.0)], 1.7, "gravel"],
	[[Vector2(4.2, 4.0), Vector2(9.0, 7.6), Vector2(13.0, 6.6)], 1.6, "gravel"],
	[[Vector2(-9.2, 6.2), Vector2(-9.2, 14.0)], 1.0, "path_dirt"],
	[[Vector2(-13.0, 10.4), Vector2(-5.4, 10.4)], 1.0, "path_dirt"],
	[[Vector2(9.0, -5.9), Vector2(12.0, -4.6), Vector2(14.2, -1.0)], 1.5, "path_dirt"],
]

## Planches de potager : [centre, demi-taille]
const BEDS := [
	[Vector2(-11.4, 8.5), Vector2(1.0, 0.55)], [Vector2(-11.4, 9.9), Vector2(1.0, 0.55)],
	[Vector2(-7.0, 8.5), Vector2(1.0, 0.55)], [Vector2(-7.0, 9.9), Vector2(1.0, 0.55)],
	[Vector2(-11.4, 12.2), Vector2(1.0, 0.55)], [Vector2(-7.0, 12.2), Vector2(1.0, 0.55)],
]

# ------------------------------------------------------------------ outils géométriques

## Bruit de valeur lisse (0-1), traits d'environ 1 / scale mètres.
static func _vn(x: float, z: float, scale: float, salt := 0) -> float:
	var fx := x * scale
	var fz := z * scale
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var a := VoxelGrid.hash01(ix, salt, iz, 11)
	var b := VoxelGrid.hash01(ix + 1, salt, iz, 11)
	var c := VoxelGrid.hash01(ix, salt, iz + 1, 11)
	var d := VoxelGrid.hash01(ix + 1, salt, iz + 1, 11)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

static func _smooth(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

static func _dist_segment(p: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return {"d": p.distance_to(a + ab * t), "t": t}

static func _rect_dist(p: Vector2, c: Vector2, half: Vector2) -> float:
	var q := (p - c).abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)

static func _poly_dist(p: Vector2, pts: Array) -> float:
	var best := 1e9
	for i in pts.size() - 1:
		best = minf(best, _dist_segment(p, pts[i], pts[i + 1])["d"])
	return best

# ------------------------------------------------------------------ crochets du générateur

## Hauteur du sol en mètres (avant quantification à 0,20 m).
func height(x: float, z: float, h: float, _r: float) -> float:
	var p := Vector2(x, z)
	var out := 2.3 + (h - 3.0) * 0.3
	# Colline de l'Ancre : plateau de rayon 3,2 m, flancs en paliers.
	var dh := p.distance_to(HILL_C)
	out = lerpf(out, HILL_H, _smooth(1.0 - (dh - 3.2) / 7.0))
	# Place, terrasses, ports, jardins.
	out = lerpf(out, PLAZA_H, _smooth(1.0 - (p.length() - PLAZA_R) / 3.2))
	for pad in PADS:
		var d := _rect_dist(p, pad[0], pad[1])
		out = lerpf(out, float(pad[2]), _smooth(1.0 - d / float(pad[3])))
	# Escaliers : hauteur interpolée le long de la rampe, bord franc.
	for ramp in RAMPS:
		var seg := _dist_segment(p, ramp[0], ramp[1])
		if seg["d"] < ramp[2] + 0.5:
			var hh := lerpf(float(ramp[3]), float(ramp[4]), seg["t"])
			out = lerpf(out, hh, _smooth(1.0 - (seg["d"] - ramp[2]) / 0.5))
	return out

## Matière du dessus ("" = génération par défaut). x, z, h en mètres.
func surface(x: float, z: float, h: float, r: float, slope: int) -> String:
	var p := Vector2(x, z)
	var jit := (VoxelGrid.hash01(int(floor(x * 5.0)), 0, int(floor(z * 5.0)), 3) - 0.5) * 0.45
	# Escaliers.
	for ramp in RAMPS:
		if _dist_segment(p, ramp[0], ramp[1])["d"] < ramp[2] + jit * 0.2:
			return ramp[5]
	# Place centrale : pavés avec anneau sombre et rosace.
	var d := p.length()
	if d < PLAZA_R + jit * 0.3:
		if d > 4.35 and d < 4.75:
			return "cobble_dark"
		if d < 2.1:
			return "cobble_dark" if d > 1.75 else "cobble"
		return "cobble"
	if d < PLAZA_R + 0.5:
		return "stone_ashlar_dark"
	# Plateau de l'Ancre.
	if p.distance_to(HILL_C) < 3.35:
		return "cobble_dark" if p.distance_to(HILL_C) < 3.1 else "stone_carved"
	# Chemins.
	for path in PATHS:
		if _poly_dist(p, path[0]) < float(path[1]) * 0.5 + jit * 0.35:
			return path[2]
	# Potager.
	for bed in BEDS:
		var q: Vector2 = (p - bed[0]).abs()
		if q.x < bed[1].x + 0.1 and q.y < bed[1].y + 0.1:
			return "dirt_fertile"
	# Aires de travail : gravier autour des quais et du marché, parvis devant les bâtiments.
	for pad in PADS:
		var name: String = pad[4]
		var dd := _rect_dist(p, pad[0], pad[1])
		if name in ["market", "port"] and dd < -0.3:
			return "gravel"
		if name in ["house_colonist", "house_cottage", "workshop", "warehouse", "tower"] and dd < -0.9:
			return "gravel" if _vn(x, z, 0.8, 3) < 0.3 else "grass_trim"
	# Pente forte : roche, avec mousse.
	if slope >= 4 and r < 0.97:
		return "rock_warm" if VoxelGrid.hash01(int(floor(x)), 2, int(floor(z)), 9) < 0.6 else "rock_grey"
	# Herbe : pelouse près du village, sauvage plus loin, piétinée le long des chemins.
	var near := 99.0
	for path in PATHS:
		near = minf(near, _poly_dist(p, path[0]) - float(path[1]) * 0.5)
	var vd := p.distance_to(Vector2(0.0, 2.0))
	var n := _vn(x, z, 0.3, 1)
	if near < 1.0 and near > 0.0 and _vn(x, z, 1.1, 2) > 0.42:
		return "grass_trampled"
	if vd < 11.5 + jit * 2.0:
		return "grass_lush" if n > 0.72 else "grass_trim"
	if vd < 15.0:
		return "grass_lush" if n > 0.55 else "grass"
	if n < 0.28:
		return "grass_dry"
	return "grass_lush" if n > 0.74 else "grass_wild"

## Vrai si (x, z) est occupé par un bâtiment, un chemin, la place ou un aménagement.
func reserved(x: float, z: float, margin := 0.6) -> bool:
	var p := Vector2(x, z)
	if p.length() < PLAZA_R + margin:
		return true
	if p.distance_to(HILL_C) < 3.6 + margin:
		return true
	for pad in PADS:
		if _rect_dist(p, pad[0], pad[1]) < margin:
			return true
	for ramp in RAMPS:
		if _dist_segment(p, ramp[0], ramp[1])["d"] < ramp[2] + margin:
			return true
	for path in PATHS:
		if _poly_dist(p, path[0]) < float(path[1]) * 0.5 + margin:
			return true
	for bed in BEDS:
		var q: Vector2 = (p - bed[0]).abs()
		if q.x < bed[1].x + margin and q.y < bed[1].y + margin:
			return true
	return false
