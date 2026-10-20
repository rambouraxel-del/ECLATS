@tool
class_name BuildingFurnisher
extends RefCounted
## Meuble les pièces d'un bâtiment selon leur FONCTION (living, chambre, atelier, boutique, réserve…).
## Les meubles sont des modèles en microvoxels de 2 cm posés sur une grille de 10 cm :
##   - jamais sur le foyer, l'escalier, devant une porte (zone de dégagement) ni dans une autre pièce ;
##   - le long des murs d'abord, puis au centre ;
##   - après chaque ajout, un parcours (BFS) vérifie qu'un personnage de 50 cm de large peut encore aller
##     de chaque porte à chaque autre porte de la pièce ; sinon le meuble est retiré (jamais silencieux :
##     le compte est conservé dans model.checks).
## Entrée : un BuildingModel déjà construit. Sortie : model.furniture, model.details, model.colliders.

const C := VoxelGrid.STRUCTURE_SIZE
const PIX := VoxelGrid.DETAIL_SIZE
const P := preload("res://scripts/world/building/building_plan.gd")
const CLEARANCE := 5          # largeur libre minimale d'un passage (cellules de 10 cm)

# Programme par fonction : [meuble, quantité min, max, mur?]
const PROGRAM := {
	"living": [["bench", 1, 1, true], ["chest", 1, 1, true], ["shelf", 1, 1, true], ["table", 1, 1, false], ["barrel", 0, 1, true]],
	"bedroom": [["bed", 1, 1, true], ["chest", 1, 1, true], ["shelf", 0, 1, true]],
	"chamber": [["bed", 1, 2, true], ["chest", 1, 1, true], ["shelf", 0, 1, true]],
	"hall": [["long_table", 1, 1, false], ["bench", 1, 2, true], ["chest", 0, 1, true], ["barrel", 0, 1, true]],
	"kitchen": [["counter", 1, 1, true], ["shelf", 1, 1, true], ["barrel", 1, 2, true], ["table", 0, 1, false]],
	"workroom": [["workbench", 1, 2, true], ["anvil", 0, 1, false], ["shelf", 1, 1, true], ["crate", 1, 2, true], ["barrel", 0, 1, true]],
	"store": [["crate", 2, 4, true], ["barrel", 1, 3, true], ["sacks", 1, 2, true], ["shelf", 0, 1, true]],
	"storage": [["crate", 3, 6, true], ["barrel", 2, 4, true], ["sacks", 2, 3, true], ["shelf", 1, 2, true], ["crate_stack", 1, 2, false]],
	"shop": [["counter", 1, 1, false], ["shelf", 1, 2, true], ["crate", 1, 2, true], ["barrel", 0, 1, true]],
}

# Empreinte (cellules de 10 cm) : x = largeur, z = profondeur, dans le repère canonique « dos au mur nord ».
const SIZES := {
	"bed": Vector2i(10, 20), "chest": Vector2i(7, 4), "shelf": Vector2i(12, 3), "bench": Vector2i(14, 4),
	"table": Vector2i(12, 8), "long_table": Vector2i(24, 8), "barrel": Vector2i(5, 5), "crate": Vector2i(5, 5),
	"counter": Vector2i(20, 6), "workbench": Vector2i(16, 7), "anvil": Vector2i(5, 5), "sacks": Vector2i(8, 6),
	"crate_stack": Vector2i(10, 6),
}
const HEIGHTS := {
	"bed": 5, "chest": 5, "shelf": 18, "bench": 4, "table": 8, "long_table": 8, "barrel": 7, "crate": 5,
	"counter": 9, "workbench": 9, "anvil": 6, "sacks": 6, "crate_stack": 10,
}

static func furnish(model: BuildingModel) -> void:
	var plan := model.plan
	var rng := WorldRng.stream(plan.seed, "furnish")
	model.furniture.clear()
	var removed := 0
	for info in model.rooms:
		var role: String = info["role"]
		if not PROGRAM.has(role):
			continue
		removed += _furnish_room(model, info, rng)
	model.checks["furniture_count"] = model.furniture.size()
	model.checks["furniture_removed_for_circulation"] = removed

# ------------------------------------------------------------------ pièce

static func _furnish_room(model: BuildingModel, info: Dictionary, rng: RandomNumberGenerator) -> int:
	var rect: Rect2 = info["rect"]
	var x0 := roundi(rect.position.x / C)
	var z0 := roundi(rect.position.y / C)
	var w := roundi(rect.size.x / C)
	var d := roundi(rect.size.y / C)
	var floor_idx: int = info["floor"]
	# grille d'occupation : 0 libre, 1 interdit (obstacle), 2 meuble
	var grid := PackedByteArray()
	grid.resize(w * d)
	for o in info["obstacles"]:
		_mark(grid, w, d, x0, z0, o as Rect2, 1)
	var door_cells: Array[Vector2i] = []
	for dc in model.door_clear:
		if dc["floor"] == floor_idx:
			_mark(grid, w, d, x0, z0, dc["rect"] as Rect2, 1)
	for o in model.plan.openings:
		if o.kind != "door" or o.floor != floor_idx:
			continue
		var bx := _door_inside_cell(model, o, x0, z0, w, d)
		if bx.x >= 0:
			door_cells.append(bx)
	var removed := 0
	var wanted: Array = []
	for entry in PROGRAM[info["role"]]:
		var n := rng.randi_range(int(entry[1]), int(entry[2]))
		for i in n:
			wanted.append({"kind": entry[0], "wall": entry[3]})
	# meubles de mur d'abord (les grands en premier), puis ceux du centre
	wanted.sort_custom(func(a, b):
		if a["wall"] != b["wall"]:
			return a["wall"]
		var sa: Vector2i = SIZES[a["kind"]]
		var sb: Vector2i = SIZES[b["kind"]]
		return sa.x * sa.y > sb.x * sb.y)
	for want in wanted:
		var kind: String = want["kind"]
		var cands := _candidates(kind, want["wall"], w, d)
		_shuffle(cands, rng)
		for cand in cands:
			var fp: Rect2i = cand["rect"]
			if not _fits(grid, w, d, fp):
				continue
			# on essaie : poser, vérifier la circulation, annuler sinon
			_fill(grid, w, d, fp, 2)
			if _circulation_ok(grid, w, d, door_cells, info):
				_commit(model, info, kind, cand, x0, z0, floor_idx, rng)
				break
			_fill(grid, w, d, fp, 0)
			removed += 1
	return removed

static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

static func _mark(grid: PackedByteArray, w: int, d: int, x0: int, z0: int, r: Rect2, v: int) -> void:
	var rx0 := floori(r.position.x / C + 0.001) - x0
	var rz0 := floori(r.position.y / C + 0.001) - z0
	var rx1 := ceili(r.end.x / C - 0.001) - x0
	var rz1 := ceili(r.end.y / C - 0.001) - z0
	for z in range(maxi(rz0, 0), mini(rz1, d)):
		for x in range(maxi(rx0, 0), mini(rx1, w)):
			grid[z * w + x] = v

static func _fill(grid: PackedByteArray, w: int, d: int, r: Rect2i, v: int) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			grid[z * w + x] = v

static func _fits(grid: PackedByteArray, w: int, d: int, r: Rect2i) -> bool:
	if r.position.x < 0 or r.position.y < 0 or r.end.x > w or r.end.y > d:
		return false
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if grid[z * w + x] != 0:
				return false
	return true

## Cellule intérieure située juste derrière une porte (côté pièce), en coordonnées locales à la pièce.
static func _door_inside_cell(model: BuildingModel, o: P.Opening, x0: int, z0: int, w: int, d: int) -> Vector2i:
	var mid := o.u + o.w / 2
	var gx := 0
	var gz := 0
	if o.axis == 2:
		gx = mid
		# la pièce est du côté opposé à `sign` pour un mur extérieur ; pour une cloison, on teste les deux côtés
		gz = o.p - 1
		if _inside(gx - x0, gz - z0, w, d):
			return Vector2i(gx - x0, gz - z0)
		gz = o.p + o.thickness
	else:
		gz = mid
		gx = o.p - 1
		if _inside(gx - x0, gz - z0, w, d):
			return Vector2i(gx - x0, gz - z0)
		gx = o.p + o.thickness
	if _inside(gx - x0, gz - z0, w, d):
		return Vector2i(gx - x0, gz - z0)
	return Vector2i(-1, -1)

static func _inside(x: int, z: int, w: int, d: int) -> bool:
	return x >= 0 and z >= 0 and x < w and z < d

## Positions candidates : contre un mur (dos au mur) ou dans la partie centrale.
static func _candidates(kind: String, wall: bool, w: int, d: int) -> Array:
	var out: Array = []
	var s: Vector2i = SIZES[kind]
	for rot in 4:                       # 0: dos au nord, 1: dos à l'est, 2: dos au sud, 3: dos à l'ouest
		var sz := s if rot % 2 == 0 else Vector2i(s.y, s.x)
		if wall:
			var xs: Array = []
			var zs: Array = []
			match rot:
				0: zs = [0]
				1: xs = [w - sz.x]
				2: zs = [d - sz.y]
				3: xs = [0]
			if rot % 2 == 0:
				for x in range(0, w - sz.x + 1, 2):
					out.append({"rect": Rect2i(x, zs[0], sz.x, sz.y), "rot": rot})
			else:
				for z in range(0, d - sz.y + 1, 2):
					out.append({"rect": Rect2i(xs[0], z, sz.x, sz.y), "rot": rot})
		else:
			if rot > 1:
				continue
			for z in range(CLEARANCE, d - sz.y - CLEARANCE + 1, 3):
				for x in range(CLEARANCE, w - sz.x - CLEARANCE + 1, 3):
					out.append({"rect": Rect2i(x, z, sz.x, sz.y), "rot": rot})
	return out

# ------------------------------------------------------------------ circulation

## Les cellules « praticables » sont celles dont le carré de CLEARANCE autour est libre (le meuble ne
## doit pas pincer un passage sous 50 cm). Toutes les portes de la pièce doivent rester reliées.
static func _circulation_ok(grid: PackedByteArray, w: int, d: int, doors: Array[Vector2i], info: Dictionary) -> bool:
	var half := CLEARANCE / 2
	# praticable = cellule libre OU zone de porte (marquée 1) dont ne dépend pas la largeur des meubles
	var walk := PackedByteArray()
	walk.resize(w * d)
	for z in d:
		for x in w:
			if grid[z * w + x] == 2:
				continue
			var ok := true
			for dz in range(-half, half + 1):
				for dx in range(-half, half + 1):
					var xx := x + dx
					var zz := z + dz
					if xx < 0 or zz < 0 or xx >= w or zz >= d:
						continue          # le mur ne pince pas (le mur est hors pièce)
					if grid[zz * w + xx] == 2:
						ok = false
						break
				if not ok:
					break
			walk[z * w + x] = 1 if ok else 0
	var start := -1
	for dd in doors:
		start = dd.y * w + dd.x
		break
	if start < 0:
		return true
	if walk[start] == 0:
		return false
	var seen := PackedByteArray()
	seen.resize(w * d)
	var q: Array[int] = [start]
	seen[start] = 1
	var qi := 0
	while qi < q.size():
		var c := q[qi]
		qi += 1
		var cx := c % w
		var cz := c / w
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + n.x
			var nz: int = cz + n.y
			if nx < 0 or nz < 0 or nx >= w or nz >= d:
				continue
			var ni := nz * w + nx
			if seen[ni] == 0 and walk[ni] == 1:
				seen[ni] = 1
				q.append(ni)
	for dd in doors:
		if seen[dd.y * w + dd.x] == 0:
			return false
	# la partie praticable doit rester d'un seul tenant (pas d'îlot de plancher isolé)
	for i in w * d:
		if walk[i] == 1 and seen[i] == 0:
			return false
	return true

# ------------------------------------------------------------------ enregistrement

static func _commit(model: BuildingModel, info: Dictionary, kind: String, cand: Dictionary, x0: int, z0: int, floor_idx: int, rng: RandomNumberGenerator) -> void:
	var fp: Rect2i = cand["rect"]
	var rot: int = cand["rot"]
	var plan := model.plan
	var base := Vector3(float(x0 + fp.position.x) * C, float(info["floor_y"]), float(z0 + fp.position.y) * C)
	var s: Vector2i = SIZES[kind]
	var kit := build_kit(kind, s, plan.seed + model.furniture.size() * 31 + hash(kind) % 997, rng)
	var vol := kit.volume.rotated_y(rot)
	model.details.append({"name": "f_%s_%d" % [kind, model.furniture.size()], "volume": vol, "grid": PIX, "offset": base, "material": "props"})
	var h: int = HEIGHTS[kind]
	var abs_rect := Rect2(Vector2(x0 + fp.position.x, z0 + fp.position.y) * C, Vector2(fp.size) * C)
	model.furniture.append({"kind": kind, "floor": floor_idx, "room": info["id"], "rect": abs_rect, "height": float(h) * C, "rot": rot})
	model.colliders.append(AABB(Vector3(abs_rect.position.x, float(info["floor_y"]), abs_rect.position.y), Vector3(abs_rect.size.x, float(h) * C, abs_rect.size.y)))

# ------------------------------------------------------------------ modèles (2 cm)

## Modèle canonique, dos au nord (z = 0 côté mur), taille s en cellules de 10 cm (= 5 pixels de 2 cm).
static func build_kit(kind: String, s: Vector2i, seed: int, rng: RandomNumberGenerator) -> AssetKit:
	var W := s.x * 5
	var D := s.y * 5
	var H := int(HEIGHTS[kind]) * 5 + 2
	var k := AssetKit.new(Vector3i(W, H, D), seed)
	match kind:
		"bed":
			k.box(0, 0, 0, 2, 7, 2, "wood_aged_dark")
			k.box(W - 3, 0, 0, W - 1, 7, 2, "wood_aged_dark")
			k.box(0, 0, D - 3, 2, 4, D - 1, "wood_aged_dark")
			k.box(W - 3, 0, D - 3, W - 1, 4, D - 1, "wood_aged_dark")
			k.box(0, 8, 0, W - 1, 11, 3, "wood_aged")          # tête de lit
			k.box(0, 3, 0, W - 1, 6, D - 1, "wood_aged_dark")   # cadre
			k.box(2, 7, 4, W - 3, 10, D - 3, "sack_cloth")      # paillasse
			var blanket: String = ["cloth_brown", "cloth_faded_blue", "cloth_ochre"][rng.randi() % 3]
			k.box(1, 10, int(D * 0.45), W - 2, 12, D - 2, blanket)
			k.box(3, 10, 6, W - 4, 13, 18, "paper")              # oreiller
		"chest":
			k.box(0, 0, 0, W - 1, 15, D - 1, "wood_aged")
			k.box(0, 0, 0, W - 1, 1, D - 1, "wood_aged_dark")
			k.box(0, 7, 0, W - 1, 8, D - 1, "iron_rust")
			k.box(0, 15, 1, W - 1, 17, D - 2, "wood_aged_dark")
			k.box(W / 2 - 1, 11, D - 1, W / 2 + 1, 13, D - 1, "iron_dark")
		"shelf":
			# montants + 4 étagères ; objets (pots, livres) sur les tablettes
			k.box(0, 0, 0, 1, H - 1, D - 1, "wood_aged_dark")
			k.box(W - 2, 0, 0, W - 1, H - 1, D - 1, "wood_aged_dark")
			k.box(0, 0, 0, W - 1, H - 1, 0, "wood_aged")
			for i in 4:
				var y := 6 + i * 20
				k.box(0, y, 0, W - 1, y + 1, D - 1, "wood_aged_dark")
				var x := 4
				while x < W - 8:
					var wi := 3 + rng.randi() % 5
					var hi := 4 + rng.randi() % 8
					var key: String = ["terracotta", "cloth_brown", "paper", "leather", "iron_rust", "sack_cloth"][rng.randi() % 6]
					if x + wi < W - 3:
						k.box(x, y + 2, 2, x + wi - 1, y + 1 + hi, mini(D - 2, 2 + wi), key)
					x += wi + 2 + rng.randi() % 4
		"bench":
			k.box(0, 8, 0, W - 1, 10, D - 1, "wood_aged")
			k.box(1, 0, 1, 3, 7, D - 2, "wood_aged_dark")
			k.box(W - 4, 0, 1, W - 2, 7, D - 2, "wood_aged_dark")
		"table", "long_table":
			k.box(0, H - 5, 0, W - 1, H - 3, D - 1, "wood_aged")
			k.box(0, H - 6, 0, W - 1, H - 6, D - 1, "wood_aged_dark")
			for lx in [1, W - 4]:
				k.box(lx, 0, 1, lx + 2, H - 6, 3, "wood_aged_dark")
				k.box(lx, 0, D - 4, lx + 2, H - 6, D - 2, "wood_aged_dark")
			# quelques objets : un bol, un pain
			k.box(W / 2 - 3, H - 2, D / 2 - 3, W / 2 + 2, H - 1, D / 2 + 2, "terracotta")
			if kind == "long_table":
				k.box(W / 4, H - 2, D / 2, W / 4 + 5, H, D / 2 + 5, "bread")
		"barrel":
			k.barrel(W / 2.0, D / 2.0, 0, H, float(W) * 0.5 - 0.5, float(W) * 0.5 - 2.0, "wood_aged", "iron_rust")
		"crate":
			k.crate(0, 0, 0, W - 1, H - 3, D - 1, "wood_aged", "")
		"crate_stack":
			k.crate(0, 0, 0, W / 2 - 1, 24, D - 1, "wood_aged", "")
			k.crate(W / 2, 0, 0, W - 1, 24, D - 1, "wood_aged", "")
			k.crate(W / 4, 25, 2, W / 4 + W / 2, H - 3, D - 3, "wood_aged_dark", "")
		"counter":
			k.box(0, 0, 0, W - 1, H - 6, D - 1, "wood_aged_dark")
			k.box(0, H - 5, 0, W - 1, H - 3, D - 1, "wood_aged")
			k.box(2, 2, 2, W - 3, H - 8, 4, "wood_aged")
		"workbench":
			k.box(0, H - 6, 0, W - 1, H - 4, D - 1, "wood_aged")
			for lx in [1, W - 5]:
				k.box(lx, 0, 1, lx + 3, H - 7, 4, "wood_aged_dark")
				k.box(lx, 0, D - 5, lx + 3, H - 7, D - 2, "wood_aged_dark")
			k.box(3, H - 3, 3, 12, H - 2, 9, "iron_rust")
			k.box(W - 14, H - 3, D - 12, W - 6, H - 3, D - 5, "leather")
		"anvil":
			k.box(3, 0, 3, W - 4, 8, D - 4, "wood_aged_dark")
			k.box(0, 9, 4, W - 1, 14, D - 5, "iron_dark")
		"sacks":
			for i in 3:
				var ox: int = (i * (W / 3)) % max(W - 14, 1)
				var oz := (i % 2) * 8
				k.ellipsoid(Vector3(ox + 8, 6, oz + 9), Vector3(7, 6, 7), "sack_cloth")
				k.box(ox + 7, 11, oz + 8, ox + 9, 12, oz + 10, "rope")
		_:
			k.box(0, 0, 0, W - 1, H - 3, D - 1, "wood_aged")
	return k
