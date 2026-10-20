@tool
class_name BuildingPlanner
extends RefCounted
## Produit le PLAN d'un bâtiment (pièces, cloisons, ouvertures, escalier, foyer, annexes, toiture)
## à partir d'un archétype et d'une graine. Déterministe. Ne connaît ni le terrain ni les voxels.
## Les règles de conception (portes, escaliers, fenêtres) sont ici, une seule fois, pour TOUS les bâtiments.

static func plan(type: String, seed: int) -> BuildingPlan:
	var arch := BuildingCatalog.get_archetype(type)
	var rng := WorldRng.stream(seed, "plan:" + type)
	var p := BuildingPlan.new()
	p.type = type
	p.seed = seed
	p.archetype = arch
	p.floors = rng.randi_range(int(arch["floors"][0]), int(arch["floors"][1]))
	p.W = _even(rng.randi_range(int(arch["w"][0]), int(arch["w"][1])))
	p.D = _even(rng.randi_range(int(arch["d"][0]), int(arch["d"][1])))
	_style(p, rng, arch)
	var has_annex := rng.randf() < float(arch["annex_chance"])
	var annex_side := 1 if rng.randf() < 0.5 else -1       # (tirage conservé : il fixe la suite du flux de la graine)
	# Le foyer est contre le pignon ouest ; l'annexe est du côté opposé (est) par défaut.
	annex_side = 1
	var annex_w := 0
	if has_annex:
		annex_w = _even(rng.randi_range(24, 32))
	p.mx = 2
	p.mz = 2
	_layout(p, rng, arch)
	if has_annex:
		_add_annex(p, rng, annex_w, annex_side)
	p.footprint = Vector2i(p.mx + p.W + (annex_w if has_annex else 0) + 2, p.mz + p.D + 6)
	_roof(p, rng)
	_windows(p, rng)
	_finish(p, rng)
	return p

static func _even(v: int) -> int:
	return v - (v % 2)

static func _pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi() % arr.size()]

static func _style(p: BuildingPlan, rng: RandomNumberGenerator, arch: Dictionary) -> void:
	var ws: String = _pick(rng, arch["wall_styles"])
	var def: Dictionary = BuildingCatalog.WALL_STYLES[ws]
	var low: String = _pick(rng, def["low"])
	var up: String = _pick(rng, def["up"])
	p.style = {
		"wall_style": ws, "wall_low": low, "wall_up": up, "timber": def["timber"],
		"frame": "wood_aged_dark", "trim": "wood_aged", "wear": 0.55 + rng.randf() * 0.4,
		"low_height": rng.randi_range(10, 14),
		"patch_up": _pick(rng, ["plaster_worn_ochre", "plaster_worn_grey", "plaster_worn_cream", "stone_rubble_warm"]),
		"reclaimed": rng.randf() < 0.6,
	}

# ------------------------------------------------------------------ agencement des pièces

static func _room(p: BuildingPlan, floor_idx: int, x0: int, z0: int, x1: int, z1: int, role: String, floor_mat := "floor_planks") -> BuildingPlan.Room:
	var r := BuildingPlan.Room.new()
	r.id = p.rooms.size()
	r.floor = floor_idx
	r.x0 = x0
	r.z0 = z0
	r.x1 = x1
	r.z1 = z1
	r.role = role
	r.floor_material = floor_mat
	p.rooms.append(r)
	return r

static func _wall(p: BuildingPlan, axis: int, pos: int, u0: int, u1: int, floor_idx: int, thickness: int, exterior: bool, material: String) -> BuildingPlan.Wall:
	var w := BuildingPlan.Wall.new()
	w.axis = axis
	w.p = pos
	w.u0 = u0
	w.u1 = u1
	w.floor = floor_idx
	w.thickness = thickness
	w.exterior = exterior
	w.material = material
	p.walls.append(w)
	return w

static func _door(p: BuildingPlan, wall: String, axis: int, pos: int, u: int, w: int, h: int, floor_idx: int, thickness: int, sign: int, rooms: Vector2i, main := false, leaf := "single") -> BuildingPlan.Opening:
	var o := BuildingPlan.Opening.new()
	o.kind = "door"
	o.wall = wall
	o.axis = axis
	o.p = pos
	o.u = u
	o.w = w
	o.h = h
	o.sill = 0
	o.floor = floor_idx
	o.thickness = thickness
	o.sign = sign
	o.rooms = rooms
	o.main = main
	o.leaf = leaf
	p.openings.append(o)
	if main:
		p.main_door = p.openings.size() - 1
	return o

static func _layout(p: BuildingPlan, rng: RandomNumberGenerator, arch: Dictionary) -> void:
	var W := p.W
	var D := p.D
	var ix0 := p.mx + BuildingPlan.WALL
	var ix1 := p.mx + W - BuildingPlan.WALL - 1
	var iz0 := p.mz + BuildingPlan.WALL
	var iz1 := p.mz + D - BuildingPlan.WALL - 1
	var wall_mat: String = p.style["wall_low"]
	# Murs extérieurs (tous les niveaux).
	for f in p.floors:
		_wall(p, 2, p.mz + D - BuildingPlan.WALL, p.mx, p.mx + W - 1, f, 2, true, wall_mat)    # S (façade)
		_wall(p, 2, p.mz, p.mx, p.mx + W - 1, f, 2, true, wall_mat)                              # N
		_wall(p, 0, p.mx, p.mz, p.mz + D - 1, f, 2, true, wall_mat)                              # O
		_wall(p, 0, p.mx + W - BuildingPlan.WALL, p.mz, p.mz + D - 1, f, 2, true, wall_mat)     # E
	var main_w: int = arch["main_door_w"]
	match p.type:
		"house_small": _layout_house_small(p, rng, ix0, ix1, iz0, iz1, main_w)
		"house_large": _layout_house_large(p, rng, ix0, ix1, iz0, iz1, main_w)
		"workshop": _layout_workshop(p, rng, ix0, ix1, iz0, iz1, main_w)
		"warehouse": _layout_warehouse(p, rng, ix0, ix1, iz0, iz1, main_w)
		"shop": _layout_shop(p, rng, ix0, ix1, iz0, iz1, main_w)
		"community_hall": _layout_hall(p, rng, ix0, ix1, iz0, iz1, main_w)

## Porte d'entrée sur la façade S, dans [ua, ub] (cellule gauche de la porte).
static func _main_door(p: BuildingPlan, rng: RandomNumberGenerator, ua: int, ub: int, w: int, room_id: int, leaf := "single") -> void:
	var u := rng.randi_range(ua, maxi(ub, ua))
	u -= (u - p.mx) % 1
	var h := BuildingPlan.DOOR_MAIN_H if w <= 12 else 24
	_door(p, "S", 2, p.mz + p.D - BuildingPlan.WALL, u, w, h, 0, BuildingPlan.WALL, 1, Vector2i(-1, room_id), true, leaf if w <= 12 else "double")
	p.door_front = Vector2i(u + w / 2, p.mz + p.D + 6)

static func _partition_x(p: BuildingPlan, x: int, z0: int, z1: int, floor_idx: int, thick := BuildingPlan.PART) -> void:
	_wall(p, 0, x, z0, z1, floor_idx, thick, false, "wood_aged")

static func _partition_z(p: BuildingPlan, z: int, x0: int, x1: int, floor_idx: int, thick := BuildingPlan.PART) -> void:
	_wall(p, 2, z, x0, x1, floor_idx, thick, false, "wood_aged")

static func _int_door_x(p: BuildingPlan, x: int, u: int, floor_idx: int, a: int, b: int, thick := BuildingPlan.PART) -> void:
	# porte dans une cloison le long de z (x fixe)
	_door(p, "I", 0, x, u, BuildingPlan.DOOR_INT_W, BuildingPlan.DOOR_INT_H, floor_idx, thick, 1, Vector2i(a, b))

static func _int_door_z(p: BuildingPlan, z: int, u: int, floor_idx: int, a: int, b: int, thick := BuildingPlan.PART) -> void:
	_door(p, "I", 2, z, u, BuildingPlan.DOOR_INT_W, BuildingPlan.DOOR_INT_H, floor_idx, thick, 1, Vector2i(a, b))

static func _layout_house_small(p: BuildingPlan, rng: RandomNumberGenerator, ix0: int, ix1: int, iz0: int, iz1: int, main_w: int) -> void:
	var wi := ix1 - ix0 + 1
	var s := ix0 + int(round(wi * rng.randf_range(0.58, 0.66)))
	var living := _room(p, 0, ix0, iz0, s - 1, iz1, "living", "floor_planks" if rng.randf() < 0.6 else "floor_earth")
	var bed := _room(p, 0, s + 1, iz0, ix1, iz1, "bedroom", "floor_planks")
	_partition_x(p, s, iz0, iz1, 0)
	_int_door_x(p, s, iz1 - BuildingPlan.DOOR_INT_W - rng.randi_range(2, 10), 0, living.id, bed.id)
	_main_door(p, rng, ix0 + 18, s - main_w - 3, main_w, living.id)
	p.hearth = {"room": living.id, "side": "W", "x": ix0, "z": (iz0 + iz1) / 2 - 7, "w": 14, "d": 7, "h": 17}
	p.furniture = [{"role": "living", "room": living.id}, {"role": "bedroom", "room": bed.id}]

static func _layout_house_large(p: BuildingPlan, rng: RandomNumberGenerator, ix0: int, ix1: int, iz0: int, iz1: int, main_w: int) -> void:
	var wi := ix1 - ix0 + 1
	var a := ix0 + int(round(wi * rng.randf_range(0.36, 0.42)))         # cloison ouest de la cage d'escalier
	var b := a + 11                                                       # cloison est (cage : 10 cellules libres)
	var hall := _room(p, 0, ix0, iz0, a - 1, iz1, "hall", "floor_planks")
	var bay0 := _room(p, 0, a + 1, iz0, b - 1, iz1, "stairs", "floor_planks")
	var kitchen := _room(p, 0, b + 1, iz0, ix1, iz1, "kitchen", "floor_flag")
	_partition_x(p, a, iz0, iz1, 0, 2)
	_partition_x(p, b, iz0, iz1, 0, 1)
	# Escalier droit, monte vers le nord (z décroissant) ; le pied est au sud de la cage.
	var st := BuildingPlan.StairPlan.new()
	st.w = 10
	st.l = BuildingPlan.STEP_RUN * (BuildingPlan.FLOOR_H / BuildingPlan.STEP_RISE)   # 39
	st.dir = -1
	st.x0 = a + 1
	st.z0 = iz1 - st.l + 1 - 2                    # marche 1 au sud, laisse 2 cellules de palier au pied
	st.from_floor = 0
	if st.z0 < iz0 + 6:
		st.z0 = iz0 + 6
	p.stair = st
	var door_z := iz1 - BuildingPlan.DOOR_INT_W - 1
	_int_door_x(p, a, door_z, 0, hall.id, bay0.id, 2)
	_int_door_x(p, b, door_z, 0, bay0.id, kitchen.id, 1)
	_main_door(p, rng, ix0 + 6, a - main_w - 4, main_w, hall.id)
	# Étage : deux chambres et le palier de la cage.
	var ch1 := _room(p, 1, ix0, iz0, a - 1, iz1, "chamber", "floor_planks")
	var bay1 := _room(p, 1, a + 1, iz0, b - 1, iz1, "landing", "floor_planks")
	var ch2 := _room(p, 1, b + 1, iz0, ix1, iz1, "chamber", "floor_planks")
	_partition_x(p, a, iz0, iz1, 1, 2)
	_partition_x(p, b, iz0, iz1, 1, 1)
	var door_up := iz0 + 2
	_int_door_x(p, a, door_up, 1, ch1.id, bay1.id, 2)
	_int_door_x(p, b, door_up, 1, bay1.id, ch2.id, 1)
	p.hearth = {"room": hall.id, "side": "W", "x": ix0, "z": (iz0 + iz1) / 2 - 7, "w": 14, "d": 7, "h": 17}
	p.furniture = [{"role": "hall", "room": hall.id}, {"role": "kitchen", "room": kitchen.id}, {"role": "chamber", "room": ch1.id}, {"role": "chamber", "room": ch2.id}]

static func _layout_workshop(p: BuildingPlan, rng: RandomNumberGenerator, ix0: int, ix1: int, iz0: int, iz1: int, main_w: int) -> void:
	var di := iz1 - iz0 + 1
	var s := iz0 + int(round(di * rng.randf_range(0.34, 0.42)))      # cloison est-ouest : réserve au nord, atelier au sud
	var store := _room(p, 0, ix0, iz0, ix1, s - 1, "store", "floor_earth")
	var work := _room(p, 0, ix0, s + 1, ix1, iz1, "workroom", "floor_flag")
	_partition_z(p, s, ix0, ix1, 0, 2)
	_int_door_z(p, s, ix1 - 14 - rng.randi_range(0, 6), 0, store.id, work.id, 2)
	_main_door(p, rng, ix0 + 20, ix1 - main_w - 18, main_w, work.id)
	p.hearth = {"room": work.id, "side": "W", "x": ix0, "z": s + 6, "w": 16, "d": 7, "h": 17}
	p.furniture = [{"role": "workroom", "room": work.id}, {"role": "store", "room": store.id}]

static func _layout_warehouse(p: BuildingPlan, rng: RandomNumberGenerator, ix0: int, ix1: int, iz0: int, iz1: int, main_w: int) -> void:
	var hall := _room(p, 0, ix0, iz0, ix1, iz1, "storage", "floor_earth" if rng.randf() < 0.5 else "floor_planks")
	_main_door(p, rng, ix0 + 14, ix1 - main_w - 14, main_w, hall.id, "double")
	# Porte latérale (est), petite.
	_door(p, "E", 0, p.mx + p.W - BuildingPlan.WALL, iz1 - 22, 10, BuildingPlan.DOOR_MAIN_H, 0, BuildingPlan.WALL, 1, Vector2i(-1, hall.id), false, "single")
	p.furniture = [{"role": "storage", "room": hall.id}]

static func _layout_shop(p: BuildingPlan, rng: RandomNumberGenerator, ix0: int, ix1: int, iz0: int, iz1: int, main_w: int) -> void:
	var di := iz1 - iz0 + 1
	var s := iz0 + int(round(di * rng.randf_range(0.34, 0.4)))
	var store := _room(p, 0, ix0, iz0, ix1, s - 1, "store", "floor_earth")
	var shop := _room(p, 0, ix0, s + 1, ix1, iz1, "shop", "floor_planks")
	_partition_z(p, s, ix0, ix1, 0, 1)
	_int_door_z(p, s, ix0 + 8 + rng.randi_range(0, 8), 0, store.id, shop.id, 1)
	_main_door(p, rng, ix1 - main_w - 16, ix1 - main_w - 6, main_w, shop.id)
	p.hearth = {"room": store.id, "side": "W", "x": ix0, "z": iz0 + 4, "w": 14, "d": 7, "h": 17}
	p.furniture = [{"role": "shop", "room": shop.id}, {"role": "store", "room": store.id}]

static func _layout_hall(p: BuildingPlan, rng: RandomNumberGenerator, ix0: int, ix1: int, iz0: int, iz1: int, main_w: int) -> void:
	var wi := ix1 - ix0 + 1
	var s := ix1 - int(round(wi * rng.randf_range(0.22, 0.28)))
	var hall := _room(p, 0, ix0, iz0, s - 1, iz1, "hall", "floor_flag")
	var kitchen := _room(p, 0, s + 1, iz0, ix1, iz1, "kitchen", "floor_planks")
	_partition_x(p, s, iz0, iz1, 0, 2)
	_int_door_x(p, s, iz1 - 16 - rng.randi_range(0, 6), 0, hall.id, kitchen.id, 2)
	_main_door(p, rng, ix0 + 22, s - main_w - 22, main_w, hall.id, "double")
	p.hearth = {"room": hall.id, "side": "N", "x": (ix0 + s) / 2 - 8, "z": iz0, "w": 16, "d": 7, "h": 17}
	p.furniture = [{"role": "hall", "room": hall.id}, {"role": "kitchen", "room": kitchen.id}]

# ------------------------------------------------------------------ annexe (appentis)

static func _add_annex(p: BuildingPlan, rng: RandomNumberGenerator, w: int, side: int) -> void:
	var a := BuildingPlan.Annex.new()
	a.kind = "lean_to"
	a.eave = 20
	a.slope_dir = Vector2i(1, 0)
	a.x0 = p.mx + p.W
	a.x1 = a.x0 + w - 1
	var depth := p.D - 14 - 2 * rng.randi_range(0, 4)
	depth -= depth % 2
	a.z1 = p.mz + p.D - 1 - rng.randi_range(0, 3) * 2
	a.z0 = a.z1 - depth + 1
	a.wall_material = ["plaster_worn_grey", "wood_aged", "stone_rubble_dark"][rng.randi() % 3]
	# L'annexe n'a ni étage ni cloison. Murs : N, E, S ; le côté ouest est le mur du bloc principal.
	var i0 := a.x0
	var i1 := a.x1 - BuildingPlan.WALL
	_wall(p, 2, a.z1 - 1, a.x0, a.x1, 0, 2, true, a.wall_material)       # S de l'annexe
	_wall(p, 2, a.z0, a.x0, a.x1, 0, 2, true, a.wall_material)           # N
	_wall(p, 0, a.x1 - 1, a.z0, a.z1, 0, 2, true, a.wall_material)       # E
	var r := _room(p, 0, a.x0, a.z0 + 2, a.x1 - 2, a.z1 - 2, "store", "floor_earth")
	r.annex = true
	a.room_id = r.id
	p.annexes.append(a)
	# Porte extérieure sur la façade sud de l'annexe, et passage vers le bloc principal (si une pièce
	# principale touche le pignon est).
	var du := rng.randi_range(a.x0 + 2, a.x1 - BuildingPlan.DOOR_MAIN_W - 4)
	_door(p, "S", 2, a.z1 - 1, du, 10, BuildingPlan.DOOR_MAIN_H, 0, 2, 1, Vector2i(-1, r.id))
	# Liaison : porte percée dans le pignon est du bloc principal, vers la pièce qui le longe.
	var east_room: BuildingPlan.Room = null
	for rr in p.rooms:
		if not rr.annex and rr.floor == 0 and rr.x1 == p.mx + p.W - BuildingPlan.WALL - 1:
			if east_room == null or rr.area_cells() > east_room.area_cells():
				east_room = rr
	if east_room != null:
		var zc := (maxi(a.z0 + 2, east_room.z0) + mini(a.z1 - 2, east_room.z1)) / 2
		_door(p, "I", 0, p.mx + p.W - BuildingPlan.WALL, zc - 5, BuildingPlan.DOOR_INT_W, BuildingPlan.DOOR_INT_H, 0, 2, 1, Vector2i(east_room.id, r.id))

# ------------------------------------------------------------------ toiture, fenêtres, finitions

static func _roof(p: BuildingPlan, rng: RandomNumberGenerator) -> void:
	var kind: String = _pick(rng, p.archetype["roofs"])
	var def: Dictionary = BuildingCatalog.ROOF_STYLES[kind]
	var mats: Array = def["materials"]
	var main_mat: String = mats[0]
	p.roof = {
		"kind": kind, "axis": 0 if p.W >= p.D else 2,
		"pitch": def["pitch"], "thick": def["thick"], "overhang": def["overhang"],
		"material": main_mat, "alt_material": mats[1],
		"patch": rng.randf() < 0.55,
		"patch_u": rng.randf_range(0.2, 0.7), "patch_len": rng.randf_range(0.12, 0.25),
	}

static func _windows(p: BuildingPlan, rng: RandomNumberGenerator) -> void:
	# Chaque pièce a au moins une ouverture sur l'extérieur ; les fenêtres sont petites et irrégulières.
	for r in p.rooms:
		var has_ext := false
		for o in p.openings:
			if o.floor == r.floor and o.rooms.y == r.id and o.rooms.x == -1:
				has_ext = true
			if o.floor == r.floor and o.rooms.x == r.id and o.rooms.y == -1:
				has_ext = true
		var tries := 0
		var count := 1 if (has_ext or r.role in ["stairs", "landing"]) else 1
		if r.role in ["hall", "living", "workroom", "shop", "chamber", "storage"] and r.area_cells() > 700:
			count += 1
		if r.role == "storage":
			count = 3
		if r.role == "stairs":
			count = 0
		while count > 0 and tries < 24:
			tries += 1
			if _try_window(p, rng, r):
				count -= 1

static func _try_window(p: BuildingPlan, rng: RandomNumberGenerator, r: BuildingPlan.Room) -> bool:
	# Choisit un mur extérieur adjacent à la pièce.
	var cands := []
	var wi := p.mx + p.W
	if not r.annex:
		if r.z0 == p.mz + BuildingPlan.WALL:
			cands.append("N")
		if r.z1 == p.mz + p.D - BuildingPlan.WALL - 1:
			cands.append("S")
		if r.x0 == p.mx + BuildingPlan.WALL:
			cands.append("W")
		if r.x1 == wi - BuildingPlan.WALL - 1 and p.annexes.is_empty():
			cands.append("E")
	else:
		cands = ["N", "E"]
	if cands.is_empty():
		return false
	var side: String = _pick(rng, cands)
	var small := r.role in ["store", "storage", "kitchen"]
	var w := 4 if not small else 3
	var h := 5 if not small else 4
	var sill := 9 if not small else 14
	if r.role == "shop" and side == "S":
		return false
	var o := BuildingPlan.Opening.new()
	o.kind = "window"
	o.w = w
	o.h = h
	o.sill = sill
	o.floor = r.floor
	o.thickness = 2
	o.rooms = Vector2i(r.id, -1)
	o.leaf = "shutters"
	match side:
		"N":
			o.wall = "N"
			o.axis = 2
			o.p = (p.annexes[0].z0 if r.annex else p.mz)
			o.sign = -1
			o.u = rng.randi_range(r.x0 + 3, r.x1 - w - 3)
		"S":
			o.wall = "S"
			o.axis = 2
			o.p = p.mz + p.D - BuildingPlan.WALL
			o.sign = 1
			o.u = rng.randi_range(r.x0 + 3, r.x1 - w - 3)
		"W":
			o.wall = "W"
			o.axis = 0
			o.p = p.mx
			o.sign = -1
			o.u = rng.randi_range(r.z0 + 3, r.z1 - w - 3)
		"E":
			o.wall = "E"
			o.axis = 0
			o.p = (p.annexes[0].x1 - 1 if r.annex else p.mx + p.W - BuildingPlan.WALL)
			o.sign = 1
			o.u = rng.randi_range(r.z0 + 3, r.z1 - w - 3)
	if r.x1 - r.x0 < w + 6 and o.axis == 2:
		return false
	if r.z1 - r.z0 < w + 6 and o.axis == 0:
		return false
	# Pas de chevauchement avec une autre ouverture, ni avec le foyer, ni avec la cheminée.
	var span := Vector2i(o.u - 3, o.u + w + 3)
	for q in p.openings:
		if q.floor == o.floor and q.axis == o.axis and q.p == o.p:
			if span.x < q.u + q.w and span.y > q.u:
				return false
	if not p.hearth.is_empty() and p.hearth["room"] == r.id:
		var hs: String = p.hearth["side"]
		if side == hs:
			return false
	p.openings.append(o)
	return true

static func _finish(p: BuildingPlan, rng: RandomNumberGenerator) -> void:
	# Cheminée : massif de 8 × 8 cellules posé sur le foyer, monte au-dessus du faîtage.
	if not p.hearth.is_empty():
		var h: Dictionary = p.hearth
		var hx: int = h["x"]
		var hz: int = h["z"]
		var hw: int = h["w"]
		var hd: int = h["d"]
		var side: String = h["side"]
		if side == "W" or side == "E":
			p.chimney = {"x0": hx, "x1": hx + hd - 1, "z0": hz + (hw - 8) / 2, "z1": hz + (hw - 8) / 2 + 7}
		else:
			p.chimney = {"x0": hx + (hw - 8) / 2, "x1": hx + (hw - 8) / 2 + 7, "z0": hz, "z1": hz + hd - 1}
