@tool
class_name BuildingDetails
extends RefCounted
## Détails fins (microvoxels de 2 cm) des bâtiments : battants de portes (ouverts, jamais en travers
## du passage), volets, claustras, lanternes, feu de foyer, lumières intérieures.
## Chaque pièce est construite dans une orientation canonique puis tournée par quarts de tour.

const C := VoxelGrid.STRUCTURE_SIZE
const PIX := VoxelGrid.DETAIL_SIZE
const P := preload("res://scripts/world/building/building_plan.gd")

static func add_all(b: BuildingBuilder) -> void:
	var plan := b.plan
	for oi in plan.openings.size():
		var o: P.Opening = plan.openings[oi]
		var rng := WorldRng.stream(plan.seed, "detail:%d" % oi)
		if o.kind == "door":
			_door_leaf(b, o, rng)
		else:
			_window_dress(b, o, rng)
	_main_lantern(b)
	_hearth_fire(b)
	_interior_lights(b)
	_signs(b)

static func _part(b: BuildingBuilder, name: String, kit: AssetKit, pos_m: Vector3, material := "props") -> void:
	b.model.details.append({"name": name, "volume": kit.volume, "grid": PIX, "offset": pos_m, "material": material})

# ------------------------------------------------------------------ portes

static func _leaf_kit(w_cells: int, h_cells: int, seed: int, key: String) -> AssetKit:
	var L := w_cells * 5
	var H := h_cells * 5
	var k := AssetKit.new(Vector3i(L, H, 4), seed)
	# Planches verticales, deux traverses de fer rouillé en saillie, poignée.
	k.planks(0, 0, 0, L - 1, H - 1, 2, 1, 0, 6, [key, "wood_aged", key, "wood_aged_dark"], true)
	k.box(0, int(H * 0.2), 3, L - 1, int(H * 0.2) + 2, 3, "iron_rust")
	k.box(0, int(H * 0.78), 3, L - 1, int(H * 0.78) + 2, 3, "iron_rust")
	k.box(L - 5, int(H * 0.48), 3, L - 3, int(H * 0.48) + 3, 3, "iron_dark")
	return k

static func _door_leaf(b: BuildingBuilder, o: P.Opening, rng: RandomNumberGenerator) -> void:
	var plan := b.plan
	var key := "wood_aged" if rng.randf() < 0.7 else "wood_pale_old"
	var leaves := 2 if (o.leaf == "double") else 1
	var lw := o.w / leaves
	var y_m := float(plan.floor_y(o.floor) + o.sill) * C
	for li in leaves:
		var kit := _leaf_kit(lw, o.h, plan.seed + o.u + li, key)
		var vol := kit.volume
		var left := (li == 0)
		if leaves == 1:
			left = rng.randf() < 0.5
		var len_m := float(lw) * C
		if o.axis == 2:
			# battant perpendiculaire au mur (plan z-y), ouvert vers l'intérieur
			kit.volume = vol.rotated_y(1)
			var x0 := float(o.u) * C if left else float(o.u + o.w) * C - 0.08
			if leaves == 2:
				x0 = float(o.u) * C if li == 0 else float(o.u + o.w) * C - 0.08
			var z0 := float(o.p) * C - len_m if o.sign > 0 else float(o.p + o.thickness) * C
			_part(b, "door_leaf_%d_%d" % [o.u, li], kit, Vector3(x0, y_m, z0))
		else:
			var z0 := float(o.u) * C if left else float(o.u + o.w) * C - 0.08
			if leaves == 2:
				z0 = float(o.u) * C if li == 0 else float(o.u + o.w) * C - 0.08
			var x0 := float(o.p) * C - len_m if o.sign > 0 else float(o.p + o.thickness) * C
			_part(b, "door_leaf_%d_%d" % [o.u, li], kit, Vector3(x0, y_m, z0))

# ------------------------------------------------------------------ fenêtres : volets et claustras

static func _window_dress(b: BuildingBuilder, o: P.Opening, rng: RandomNumberGenerator) -> void:
	var plan := b.plan
	var y_m := float(plan.floor_y(o.floor) + o.sill) * C
	var roll := rng.randf()
	var half_w := o.w / 2
	if roll < 0.25:
		# volets fermés : un battant plein devant l'ouverture, légèrement en saillie
		var kit := _shutter_kit(o.w, o.h, plan.seed + o.u, rng, true)
		_place_on_wall(b, o, kit, float(o.u) * C, y_m, true)
		return
	if roll < 0.7:
		# volets ouverts, plaqués contre le mur de chaque côté
		for side in [-1, 1]:
			var kit := _shutter_kit(maxi(half_w, 2), o.h, plan.seed + o.u + side, rng, false)
			var u0 := float(o.u - maxi(half_w, 2)) * C - 0.02 if side < 0 else float(o.u + o.w) * C + 0.02
			_place_on_wall(b, o, kit, u0, y_m, true)
	else:
		# claustra : lattis de bois dans l'ouverture (barres de 2 cm tous les 6 cm)
		var kit := _claustra_kit(o.w, o.h, plan.seed + o.u)
		_place_on_wall(b, o, kit, float(o.u) * C, y_m, false)
	# Rideau de toile derrière le volet ouvert ou le claustra : petit pli de tissu
	if o.floor >= 0 and rng.randf() < 0.5:
		var k2 := AssetKit.new(Vector3i(o.w * 5, o.h * 5, 2), plan.seed + o.u + 9)
		var cloth: String = ["cloth_brown", "cloth_ochre", "cloth_faded_blue"][rng.randi() % 3]
		var wcells := o.w * 5
		for x in wcells:
			var hang := int(round(float(o.h * 5) * (0.55 + 0.25 * sin(float(x) * 0.9))))
			k2.box(x, o.h * 5 - hang, 0, x, o.h * 5 - 1, 1, cloth)
		_place_on_wall(b, o, k2, float(o.u) * C, y_m, false, true)

static func _shutter_kit(w_cells: int, h_cells: int, seed: int, rng: RandomNumberGenerator, closed: bool) -> AssetKit:
	var L := w_cells * 5
	var H := h_cells * 5 + 4
	var k := AssetKit.new(Vector3i(L, H, 3), seed)
	k.planks(0, 0, 0, L - 1, H - 1, 1, 1, 0, 4, ["wood_aged", "wood_pale_old", "wood_aged_dark"], true)
	# traverses et contre-fiche
	k.box(0, 2, 2, L - 1, 3, 2, "wood_aged_dark")
	k.box(0, H - 4, 2, L - 1, H - 3, 2, "wood_aged_dark")
	k.line(Vector3(1, 3, 2.5), Vector3(L - 2, H - 4, 2.5), 1, "wood_aged_dark")
	if rng.randf() < 0.6:
		# jour en losange découpé (2 pixels) : motif de volet
		var cx := L / 2
		var cy := H / 2
		k.box(cx, cy - 1, 0, cx, cy + 2, 1, "")
	return k

static func _claustra_kit(w_cells: int, h_cells: int, seed: int) -> AssetKit:
	var L := w_cells * 5
	var H := h_cells * 5
	var k := AssetKit.new(Vector3i(L, H, 2), seed)
	k.box(0, 0, 0, L - 1, 1, 1, "wood_aged_dark")
	k.box(0, H - 2, 0, L - 1, H - 1, 1, "wood_aged_dark")
	k.box(0, 0, 0, 1, H - 1, 1, "wood_aged_dark")
	k.box(L - 2, 0, 0, L - 1, H - 1, 1, "wood_aged_dark")
	for x in range(5, L - 2, 5):
		k.box(x, 0, 0, x + 1, H - 1, 0, "wood_aged")
	for y in range(5, H - 2, 5):
		k.box(0, y, 1, L - 1, y + 1, 1, "wood_aged")
	return k

## Place une pièce parallèle au mur d'une ouverture : face extérieure (outside = true) ou dans l'épaisseur.
static func _place_on_wall(b: BuildingBuilder, o: P.Opening, kit: AssetKit, u_m: float, y_m: float, outside: bool, inside_face := false) -> void:
	var vol := kit.volume
	var thick_m := float(vol.size.z) * PIX
	if o.axis == 2:
		var z_m: float
		if outside:
			z_m = float(o.p + o.thickness) * C if o.sign > 0 else float(o.p) * C - thick_m
		elif inside_face:
			z_m = float(o.p) * C - thick_m if o.sign > 0 else float(o.p + o.thickness) * C
		else:
			z_m = float(o.p) * C + (float(o.thickness) * C - thick_m) * 0.5
		_part(b, "win_%d_%d" % [o.u, o.p], kit, Vector3(u_m, y_m, z_m))
	else:
		kit.volume = vol.rotated_y(1)
		var x_m: float
		if outside:
			x_m = float(o.p + o.thickness) * C if o.sign > 0 else float(o.p) * C - thick_m
		elif inside_face:
			x_m = float(o.p) * C - thick_m if o.sign > 0 else float(o.p + o.thickness) * C
		else:
			x_m = float(o.p) * C + (float(o.thickness) * C - thick_m) * 0.5
		_part(b, "win_%d_%d" % [o.u, o.p], kit, Vector3(x_m, y_m, u_m))

# ------------------------------------------------------------------ lanterne, feu, lumières, enseignes

static func _lantern_kit() -> AssetKit:
	var k := AssetKit.new(Vector3i(8, 18, 8), 77)
	k.box(2, 0, 2, 5, 1, 5, "iron_rust")
	k.box(2, 2, 2, 5, 9, 5, "lantern_glow")
	for c in [Vector2i(1, 1), Vector2i(6, 1), Vector2i(1, 6), Vector2i(6, 6)]:
		k.box(c.x, 2, c.y, c.x, 9, c.y, "iron_rust")
	k.box(1, 10, 1, 6, 10, 6, "iron_rust")
	k.box(2, 11, 2, 5, 12, 5, "iron_rust")
	k.box(3, 13, 3, 4, 15, 4, "iron_dark")
	return k

static func _main_lantern(b: BuildingBuilder) -> void:
	var plan := b.plan
	if plan.main_door < 0:
		return
	var o: P.Opening = plan.openings[plan.main_door]
	var kit := _lantern_kit()
	var side := 1 if (plan.seed % 2 == 0) else -1
	var ux := float(o.u + o.w + 2) * C if side > 0 else float(o.u - 3) * C
	var y := float(plan.floor_y(0) + 18) * C
	var z := float(o.p + o.thickness) * C + 0.02
	_part(b, "main_lantern", kit, Vector3(ux, y, z))
	b.model.lights.append({"pos": Vector3(ux + 0.08, y + 0.15, z + 0.2), "color": Color("ffb35c"), "energy": 0.9, "range": 5.0, "interior": false})

static func _hearth_fire(b: BuildingBuilder) -> void:
	var plan := b.plan
	var hb := b.hearth_block()
	if hb.is_empty():
		return
	var r: Rect2i = hb["rect"]
	var fy := plan.floor_y(0)
	var side: String = hb["side"]
	var kit := AssetKit.new(Vector3i(40, 28, 40), plan.seed + 5)
	# Bûches croisées, braises, flammes en pointes (pixels de 2 cm).
	kit.box(6, 0, 10, 33, 2, 13, "wood_aged_dark")
	kit.box(8, 0, 22, 31, 2, 25, "wood_aged_dark")
	kit.box(10, 3, 14, 29, 4, 21, "wood_aged_dark")
	for i in 14:
		kit.set_cell(8 + (i * 7) % 24, 1, 12 + (i * 5) % 12, "ember_glow")
	for i in 5:
		var fx := 12 + i * 4
		kit.box(fx, 5, 16 + (i % 2) * 3, fx + 2, 9 + (i * 3) % 7 + 4, 18 + (i % 2) * 3, "fire")
	var cx := 0.0
	var cz := 0.0
	match side:
		"W":
			cx = float(r.end.x - 4) * C
			cz = float(r.position.y + r.size.y / 2) * C - 0.4
		"E":
			cx = float(r.position.x + 1) * C
			cz = float(r.position.y + r.size.y / 2) * C - 0.4
		_:
			cx = float(r.position.x + r.size.x / 2) * C - 0.4
			cz = float(r.end.y - 4) * C
	var y := float(fy) * C
	_part(b, "hearth_fire", kit, Vector3(cx - 0.4 if side == "W" else cx, y, cz), "crystal")
	b.model.lights.append({"pos": Vector3(cx + 0.4, y + 0.5, cz + 0.4), "color": Color("ff8a3a"), "energy": 1.1, "range": 5.0, "interior": true})

static func _interior_lights(b: BuildingBuilder) -> void:
	var plan := b.plan
	var used := 0
	for r in plan.rooms:
		if r.floor != 0 or r.role in ["stairs"]:
			continue
		if used >= 3:
			break
		var cx := float(r.x0 + r.x1 + 1) * 0.5 * C
		var cz := float(r.z0 + r.z1 + 1) * 0.5 * C
		b.model.lights.append({"pos": Vector3(cx, float(plan.floor_y(0) + 17) * C, cz), "color": Color("ffc072"), "energy": 0.55, "range": 4.2, "interior": true})
		used += 1

static func _signs(b: BuildingBuilder) -> void:
	var plan := b.plan
	if plan.type != "shop" and plan.type != "workshop" and plan.type != "warehouse":
		return
	if plan.main_door < 0:
		return
	var o: P.Opening = plan.openings[plan.main_door]
	# Enseigne : planche suspendue à une potence de fer, motif simple (balance, marteau ou sac).
	var kit := AssetKit.new(Vector3i(24, 20, 4), plan.seed + 21)
	kit.box(0, 0, 0, 23, 15, 1, "wood_aged")
	kit.box(0, 0, 0, 23, 1, 2, "wood_aged_dark")
	kit.box(0, 14, 0, 23, 15, 2, "wood_aged_dark")
	var glyph := {"shop": ["..##..", ".####.", "######", ".####.", "..##.."], "workshop": ["##..##", "######", "..##..", "..##..", "..##.."], "warehouse": ["######", "#....#", "#.##.#", "#....#", "######"]}[plan.type] as Array
	var gx := 8
	var gy := 5
	for v in glyph.size():
		var row: String = glyph[v]
		for u in row.length():
			if row[u] == "#":
				kit.set_cell(gx + u, gy + v, 2, "cloth_faded_blue" if plan.type == "shop" else "iron_rust")
	kit.box(10, 16, 1, 13, 19, 1, "iron_dark")
	var x := float(o.u - 14) * C
	var y := float(plan.floor_y(0) + 23) * C
	var z := float(o.p + o.thickness) * C + 0.1
	if x < float(plan.mx + 4) * C:
		x = float(o.u + o.w + 4) * C
	_part(b, "shop_sign", kit, Vector3(x, y, z))
