@tool
class_name PortBuilder
extends RefCounted
## Port d'une île flottante : choix du rivage, plateforme d'accostage, appontement HAUBANÉ.
##
## Un appontement ne peut pas reposer sur le vide : le tablier est une poutraison encastrée dans une
## semelle de maçonnerie posée sur la terre ferme (contrepoids), et soutenue par des haubans fixés au
## sommet de deux portiques dressés sur la plateforme. Tout est paramétré par la graine et le rivage,
## rien n'est codé pour une île précise.
##
## Repère local de l'appontement : origine = milieu du bord de l'île à la hauteur du dessus du tablier,
## +z = vers le large, x = largeur, y = vers le haut. Orienté dans le monde par un quart de tour.

const V := VoxelGrid.VOXEL_SIZE
const C := VoxelGrid.STRUCTURE_SIZE
const PIER_LEN := 8.0
const PIER_W := 2.4
const LAND_LEN := 1.0
const SHIP_SIDE_OFFSET := 4.0

static func dir_of_yaw(k: int) -> Vector2:
	match k % 4:
		0: return Vector2(0, 1)
		1: return Vector2(1, 0)
		2: return Vector2(0, -1)
	return Vector2(-1, 0)

static func yaw_of_dir(d: Vector2) -> int:
	for k in 4:
		if dir_of_yaw(k).distance_to(d) < 0.1:
			return k
	return 0

# ------------------------------------------------------------------ rivage

static func _ground_run(field: TerrainField, p: Vector2, dir: Vector2, max_len: float) -> float:
	# distance (m) jusqu'au dernier sol continu depuis p le long de dir (3 cellules vides = fin)
	var last := -1.0
	var gap := 0
	var t := 0.0
	while t < max_len:
		var q := p + dir * t
		var c := field.col_of_m(q.x, q.y)
		if field.has_ground(c.x, c.y):
			last = t
			gap = 0
		else:
			gap += 1
			if gap >= 3 and last >= 0.0:
				break
		t += V
	return last

static func _void_band(field: TerrainField, rim: Vector2, axis: Vector2, perp: Vector2, lat0: float, lat1: float, len_m: float) -> bool:
	var t := 0.5
	while t < len_m:
		var l := lat0
		while l <= lat1:
			var q := rim + axis * t + perp * l
			var c := field.col_of_m(q.x, q.y)
			if field.has_ground(c.x, c.y):
				return false
			l += V * 2.0
		t += V * 2.0
	return true

static func find_site(field: TerrainField, occ: OccupancyMap, plaza: Dictionary, rng: RandomNumberGenerator, profile: IslandProfile) -> Dictionary:
	var c: Vector2 = plaza["center"]
	var best := {}
	var best_score := 1.0e18
	var max_cut := 4
	for k in 36:
		var ang := float(k) * TAU / 36.0 + rng.randf() * 0.05
		var d := Vector2(cos(ang), sin(ang))
		var axis := Vector2(signf(d.x), 0.0) if absf(d.x) > absf(d.y) else Vector2(0.0, signf(d.y))
		var perp := Vector2(-axis.y, axis.x)
		var run := _ground_run(field, c, d, field.radius_m * 1.6)
		if run < float(plaza["radius"]) + 7.0:
			continue
		var p0 := c + d * (run * 0.8)
		var c0 := field.col_of_m(p0.x, p0.y)
		if not field.has_ground(c0.x, c0.y):
			continue
		var t_rim := _ground_run(field, p0, axis, 40.0)
		if t_rim < 3.0:
			continue
		var rim := p0 + axis * t_rim
		var pad_c := rim - axis * 2.6
		var half := Vector2(absf(axis.x) * 2.2 + absf(axis.y) * 2.5, absf(axis.y) * 2.2 + absf(axis.x) * 2.5)
		# plateforme : du recul de 4,8 m jusqu'au bord de l'île ; l'évaluation exclut la bande du rivage
		var lo := pad_c - half
		var hi := pad_c + half
		var rect := Rect2i(field.col_of_m(lo.x, lo.y), Vector2i(int(ceil((hi.x - lo.x) / V)), int(ceil((hi.y - lo.y) / V))))
		var eval_c := rim - axis * 3.6
		var eh := Vector2(absf(axis.x) * 1.2 + absf(axis.y) * 2.5, absf(axis.y) * 1.2 + absf(axis.x) * 2.5)
		var elo := eval_c - eh
		var ehi := eval_c + eh
		var erect := Rect2i(field.col_of_m(elo.x, elo.y), Vector2i(int(ceil((ehi.x - elo.x) / V)), int(ceil((ehi.y - elo.y) / V))))
		var ev := TerrainEditor.evaluate_pad(field, occ, erect, 2, max_cut, 6, 2)
		if not ev["ok"]:
			continue
		var side := 0.0
		if _void_band(field, rim, axis, perp, -PIER_W * 0.5 - 0.4, PIER_W * 0.5 + 0.4, PIER_LEN + 0.6):
			if _void_band(field, rim, axis, perp, PIER_W * 0.5 + 0.6, SHIP_SIDE_OFFSET + 3.4, PIER_LEN + 3.0):
				side = 1.0
			elif _void_band(field, rim, axis, perp, -SHIP_SIDE_OFFSET - 3.4, -PIER_W * 0.5 - 0.6, PIER_LEN + 3.0):
				side = -1.0
		if side == 0.0:
			continue
		var score: float = float(ev["cost"]) * 2.0 + absf(pad_c.distance_to(c) - (float(plaza["radius"]) + 12.0)) * 0.2 + rng.randf() * 0.4
		if score < best_score:
			best_score = score
			best = {"axis": axis, "perp": perp, "yaw": yaw_of_dir(axis), "rim": rim, "pad_center": pad_c, "pad_rect": rect, "eval_rect": erect,
				"target": ev["target"], "ship_side": side, "landing": pad_c, "length": PIER_LEN, "width": PIER_W}
	return best

static func prepare_land(field: TerrainField, occ: OccupancyMap, placement: PlacementSystem, port: Dictionary) -> void:
	var pal := VoxelPalette.get_default()
	var rect: Rect2i = port["pad_rect"]
	var target: int = port["target"]
	TerrainEditor.stamp_pad(field, rect, target, TerrainField.Zone.PORT, pal.id("cobble_dark"), true)
	var owner := occ.new_owner()
	occ.reserve(rect, PlacementSpec.TAG_PORT, owner)
	placement.mark_access(rect)
	port["owner"] = owner
	port["level"] = target
	port["deck_top"] = float(target + 1) * V + 0.2

# ------------------------------------------------------------------ appontement

## Transformation (repère de l'appontement → monde).
static func frame_transform(port: Dictionary) -> Transform3D:
	var rim: Vector2 = port["rim"]
	return Transform3D(Basis(Vector3.UP, float(int(port["yaw"])) * PI * 0.5), Vector3(rim.x, float(port["deck_top"]), rim.y))

static func build_pier(port: Dictionary, seed: int) -> Dictionary:
	var pal := VoxelPalette.get_default()
	var rng := WorldRng.stream(seed, "pier")
	var X0 := 13                    # cellules : x de -13 à 12
	var Z0 := 12                    # z de -12 à ...
	var NZ := int((PIER_LEN + 1.4) / C) + 2
	var Y0 := 8                     # y de -8
	var NY := 8 + 34
	var vol := VoxelVolume.new(Vector3i(26, NY, NZ))
	var m := func(key: String) -> int: return pal.id(key)
	var put := func(x: int, y: int, z: int, key: String) -> void:
		var ix := x + X0
		var iy := y + Y0
		var iz := z + Z0
		if ix >= 0 and iy >= 0 and iz >= 0 and ix < 26 and iy < NY and iz < NZ:
			vol.set_voxel(ix, iy, iz, m.call(key))
	var box := func(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, key: String) -> void:
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					put.call(x, y, z, key)
	var deck_end := int(PIER_LEN / C)
	var land_cells := int(LAND_LEN / C)
	var side := int(port["ship_side"])
	var colliders: Array[AABB] = []
	var plank_keys := ["floor_planks", "wood_aged", "wood_pale_old", "wood_aged", "floor_planks"]
	# tablier : planches posées en travers (une cellule de large), teintes alternées
	for z in range(-land_cells, deck_end + 1):
		var key: String = plank_keys[(z * 7 + 3 * (z / 5) + 100) % plank_keys.size()]
		box.call(-12, -1, z, 11, -1, z, key)
	# semelle de maçonnerie sous la partie posée sur la terre
	box.call(-12, -2, -land_cells, 11, -2, 1, "stone_rubble_dark")
	# poutraison : 3 longerons + entretoises tous les 1,6 m, sous la partie en porte-à-faux
	for xs in [[-12, -11], [-1, 0], [10, 11]]:
		box.call(xs[0], -5, 0, xs[1], -2, deck_end, "wood_aged_dark")
	for z in range(2, deck_end + 1, 16):
		box.call(-12, -4, z, 11, -3, z + 1, "wood_aged")
	# garde-corps : poteaux tous les 1,6 m, lisse haute et lisse basse ; ouverture côté bateau
	var gap0 := 44
	var gap1 := 62
	for sx in [-1, 1]:
		var x := -12 if sx < 0 else 10
		var open_side: bool = (sx == side)
		for z in range(1, deck_end + 1, 16):
			box.call(x, 0, z, x + 1, 8, z + 1, "wood_aged_dark")
		var last_post := deck_end - 1
		box.call(x, 0, last_post, x + 1, 8, last_post + 1, "wood_aged_dark")
		for z in range(1, deck_end + 1):
			if open_side and z >= gap0 and z <= gap1:
				continue
			box.call(x, 7, z, x, 8, z, "wood_aged")
			if z % 2 == 0:
				box.call(x, 3, z, x, 3, z, "wood_aged_dark")
	# bout de l'appontement : traverse et bittes d'amarrage
	box.call(-12, 0, deck_end, 11, 2, deck_end, "wood_aged_dark")
	for bx in [-9, 8]:
		box.call(bx, 0, deck_end - 3, bx + 2, 4, deck_end - 1, "wood_aged_dark")
		box.call(bx, 5, deck_end - 3, bx + 2, 5, deck_end - 1, "iron_rust")
	# passerelle d'embarquement : planche de 1 m de large, dans l'ouverture du garde-corps, vers le bateau
	if side != 0:
		var gz := (gap0 + gap1) / 2
		var gx0 := 11 if side > 0 else -12
		for k in range(0, 9):
			var gxx := gx0 + k * side
			box.call(gxx, -1, gz - 4, gxx, -1, gz + 5, "floor_planks" if k % 2 == 0 else "wood_aged")
		for gzz in [gz - 4, gz + 5]:
			for k in range(0, 9):
				box.call(gx0 + k * side, -2, gzz, gx0 + k * side, -2, gzz, "wood_aged_dark")
	# portiques haubanés : deux poteaux sur la plateforme, traverse supérieure et jambes de force
	var tower_z := -9
	var tower_h := 32
	for tx in [-12, 10]:
		box.call(tx, -2, tower_z, tx + 2, tower_h, tower_z + 2, "wood_aged_dark")
		box.call(tx - 1 if tx < 0 else tx, -2, tower_z - 1, tx + 3, 0, tower_z + 3, "stone_rubble_dark")
	box.call(-12, tower_h - 3, tower_z, 12, tower_h - 1, tower_z + 2, "wood_aged")
	for tx in [-12, 10]:
		box.call(tx, tower_h + 1, tower_z, tx + 2, tower_h + 2, tower_z + 2, "iron_rust")
	# fanal au bout (lanterne en cellules de 10 cm : lampe, pas de verre)
	var lamp_z := deck_end - 1
	box.call(-1, 0, lamp_z, 0, 22, lamp_z + 1, "wood_aged_dark")
	box.call(-2, 23, lamp_z - 1, 1, 26, lamp_z + 2, "iron_rust")
	box.call(-1, 24, lamp_z, 0, 25, lamp_z + 1, "lantern_glow")
	box.call(-1, 27, lamp_z, 0, 27, lamp_z + 1, "iron_dark")
	# colliders (repère local, mètres)
	colliders.append(AABB(Vector3(-1.2, -0.5, 0.0), Vector3(2.4, 0.5, PIER_LEN)))
	colliders.append(AABB(Vector3(-1.2, -0.2, -LAND_LEN), Vector3(2.4, 0.2, LAND_LEN)))
	# haubans (cordages de 2 cm) : sommet des portiques → poteaux du garde-corps
	var ropes: Array[Dictionary] = []
	var top := Vector3(0.0, float(tower_h) * C + 0.2, float(tower_z + 1) * C)
	for sx in [-1, 1]:
		var tx := -1.15 if sx < 0 else 1.15
		var start := Vector3(tx, top.y, top.z)
		for k in 3:
			var zz := (1.6 + 1.6 * float(k)) * 1.0 + 0.1
			var zc: float = clampf(zz, 1.7, PIER_LEN - 1.0)
			var endp := Vector3(tx, 0.9, zc + 0.1)
			ropes.append({"a": start, "b": endp})
	var lights: Array[Dictionary] = []
	lights.append({"pos": Vector3(0.0, 2.55, float(lamp_z) * C + 0.1), "color": Color("ffb35c"), "energy": 1.1, "range": 7.0, "interior": false})
	var origin := Vector3(-float(X0) * C, -float(Y0) * C, -float(Z0) * C)
	return {"volume": vol, "origin": origin, "ropes": ropes, "colliders": colliders, "lights": lights,
		"hard": AABB(Vector3(-1.3, -0.5, -LAND_LEN), Vector3(2.6, 3.3, PIER_LEN + LAND_LEN)),
		"length": PIER_LEN, "width": PIER_W, "ship_side": side}

## Cordage entre deux points (repère de l'appontement) : volume de 2 cm + décalage.
static func rope_kit(a: Vector3, b: Vector3) -> Dictionary:
	var p := 0.02
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3(p, p, p)
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3(p, p, p)
	var size := Vector3i(int(ceil((hi.x - lo.x) / p)) + 1, int(ceil((hi.y - lo.y) / p)) + 1, int(ceil((hi.z - lo.z) / p)) + 1)
	var kit := AssetKit.new(size, 5)
	var steps := int(maxf(maxf(absf(b.x - a.x), absf(b.y - a.y)), absf(b.z - a.z)) / p) * 2
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var q := (a.lerp(b, t) - lo) / p
		# légère flèche (corde non tendue) : la corde s'affaisse de quelques cellules au milieu
		var sag := sin(t * PI) * 2.0
		kit.set_cell(int(q.x), int(maxf(q.y - sag, 0.0)), int(q.z), "rope")
	return {"volume": kit.volume, "offset": lo, "grid": p}

## Amarrage du bateau le long du ponton : transformation (monde), points d'amarre et cordages.
## Le bateau est parallèle au ponton, proue vers le large ; son ouverture de bastingage fait face à la passerelle.
static func moor(port: Dictionary, ship: Dictionary) -> Dictionary:
	var axis: Vector2 = port["axis"]
	var perp: Vector2 = port["perp"]
	var side: float = port["ship_side"]
	var rim: Vector2 = port["rim"]
	var gap_cells := (44 + 62) / 2
	var gz := float(gap_cells) * C                       # position de la passerelle le long du ponton (m)
	var B: float = ship["B"]
	var ship_open_z := -0.15                             # ouverture du bastingage dans le repère du bateau
	var lateral := side * (PIER_W * 0.5 + B * 0.5 + 0.62)
	var pos2 := rim + axis * (gz - ship_open_z) + perp * lateral
	var deck_y: float = float(port["deck_top"]) - 0.28
	var xf := Transform3D(Basis(Vector3.UP, float(int(port["yaw"])) * PI * 0.5), Vector3(pos2.x, deck_y, pos2.y))
	# amarres : bittes du ponton → taquets du bateau (de chaque côté du bateau, avant et arrière)
	var frame := frame_transform(port)
	var ropes: Array[Dictionary] = []
	for k in 2:
		var zp := PIER_LEN - 0.5 if k == 0 else 0.9
		var xp := side * (PIER_W * 0.5 - 0.15)
		var a := frame * Vector3(xp, 0.35, zp)
		var zl := (2.6 if k == 0 else -2.4) * (float(ship["L"]) / 10.0)
		var local_cleat := Vector3(-side * (B * 0.5 - 0.15) * 1.0, 0.45, zl)
		# le repère local du bateau est tourné : x local → le long de perp (signe selon le quart de tour)
		var world_off := xf.basis * Vector3(1, 0, 0)
		var toward := Vector2(world_off.x, world_off.z)
		var sgn := 1.0 if toward.dot(perp) * side > 0.0 else -1.0
		local_cleat.x = -sgn * (B * 0.5 - 0.12)
		var b := xf * local_cleat
		ropes.append({"a": a, "b": b, "sag": 3.0})
	return {"xform": xf, "ropes": ropes}
