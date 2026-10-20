@tool
class_name BuildingBuilder
extends RefCounted
## Plan → BuildingModel. Les bâtiments sont VISITABLES PAR CONCEPTION : volumes pleins uniquement là où
## il y a de la matière (fondation, murs, planchers, marches) ; les pièces sont de l'air délimité par des
## murs percés d'ouvertures réelles (portes ≥ 1,00 / 0,90 m, hauteur ≥ 2,00 m), escalier de 20 × 30 cm
## avec 1,80 m de hauteur sous plafond, sol fini à 20 cm au-dessus du terrain (une marche).
## Rien dans ce fichier ne dépend d'une île, d'une seed ou de coordonnées particulières.

const C := VoxelGrid.STRUCTURE_SIZE
const P := preload("res://scripts/world/building/building_plan.gd")

var plan: BuildingPlan
var model: BuildingModel
var vol: VoxelVolume
var pal: VoxelPalette
var rng: RandomNumberGenerator
var _ridge_y := 0
var _roof_underside: Callable

static func build(p_plan: BuildingPlan) -> BuildingModel:
	var b := BuildingBuilder.new()
	return b._build(p_plan)

func _build(p_plan: BuildingPlan) -> BuildingModel:
	plan = p_plan
	pal = VoxelPalette.get_default()
	rng = WorldRng.stream(plan.seed, "build:" + plan.type)
	model = BuildingModel.new()
	model.plan = plan
	var rise := _plan_roof_height()
	var height := plan.total_height_cells() + rise + 14
	vol = VoxelVolume.new(Vector3i(plan.footprint.x, height, plan.footprint.y))
	model.volume = vol
	_foundation()
	_walls()
	_timber_frame()
	_floors()
	_partitions()
	_stairs()
	_hearth()
	_gables_and_roofs()
	_patches()
	_carve_openings()
	_openings_trim()
	_reclaimed()
	BuildingDetails.add_all(self)
	_colliders()
	_rooms_info()
	BuildingFurnisher.furnish(model)
	_checks()
	return model

# ------------------------------------------------------------------ outils

func mat(key: String) -> int:
	return pal.id(key)

func fill(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, key: String) -> void:
	vol.fill_box(Vector3i(mini(x0, x1), mini(y0, y1), mini(z0, z1)), Vector3i(maxi(x0, x1), maxi(y0, y1), maxi(z0, z1)), mat(key))

func air(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
	vol.fill_box(Vector3i(mini(x0, x1), mini(y0, y1), mini(z0, z1)), Vector3i(maxi(x0, x1), maxi(y0, y1), maxi(z0, z1)), 0)

func set_cell(x: int, y: int, z: int, key: String) -> void:
	vol.set_voxel(x, y, z, mat(key))

func wall_key(f: int, y_rel: int, x: int, z: int) -> String:
	var st: Dictionary = plan.style
	if f == 0 and y_rel < int(st["low_height"]):
		# variantes de moellons par plaques de 1,2 m : l'œil lit des reprises, pas un aplat
		var pick := VoxelGrid.hash01(x / 12, y_rel / 8, z / 12, plan.seed)
		return st["wall_low"] if pick < 0.7 else "stone_rubble_dark" if pick < 0.88 else "stone_rubble_warm"
	var up: String = st["wall_up"]
	if st["wall_style"] == "stone":
		var pick := VoxelGrid.hash01(x / 12, y_rel / 8, z / 12, plan.seed + 3)
		return up if pick < 0.7 else "stone_rubble_dark" if pick < 0.85 else "stone_rubble_warm"
	return up

# ------------------------------------------------------------------ toiture : hauteurs (pour murs et pignons)

func _plan_roof_height() -> int:
	return plan.roof_rise_cells()

## Hauteur (cellules, depuis le bas du volume) de la sous-face du toit principal au-dessus de la
## cellule (x, z). Valable sur l'emprise du bloc principal.
func roof_underside(x: int, z: int) -> float:
	var r: Dictionary = plan.roof
	var pitch: Array = r["pitch"]
	var eave := float(plan.floor_y(plan.floors - 1) + P.CLEAR)
	var half: float
	var d: float
	if r["axis"] == 0:
		half = float(plan.D) * 0.5
		d = absf(float(z) + 0.5 - (float(plan.mz) + half))
	else:
		half = float(plan.W) * 0.5
		d = absf(float(x) + 0.5 - (float(plan.mx) + half))
	return eave + (half - d) * float(pitch[0]) / float(pitch[1])

# ------------------------------------------------------------------ fondation, murs

func _blocks() -> Array[Rect2i]:
	var out: Array[Rect2i] = [Rect2i(plan.mx, plan.mz, plan.W, plan.D)]
	for a in plan.annexes:
		out.append(Rect2i(a.x0, a.z0, a.x1 - a.x0 + 1, a.z1 - a.z0 + 1))
	return out

func _foundation() -> void:
	for r in _blocks():
		fill(r.position.x, 0, r.position.y, r.end.x - 1, P.FY - 1, r.end.y - 1, "stone_rubble_dark")
		# plinthe visible (hors sol) en moellons plus clairs
		fill(r.position.x, P.GY, r.position.y, r.end.x - 1, P.FY - 1, r.end.y - 1, "stone_rubble")
	# Marche d'entrée principale (20 cm) devant la porte.
	if plan.main_door >= 0:
		var o: P.Opening = plan.openings[plan.main_door]
		fill(o.u - 2, P.GY, o.p + o.thickness, o.u + o.w + 1, P.FY - 1, o.p + o.thickness + 3, "stone_rubble_dark")

func _wall_height(f: int) -> int:
	return P.FLOOR_H if f < plan.floors - 1 else P.CLEAR

func _walls() -> void:
	for w in plan.walls:
		if not w.exterior:
			continue
		var y0 := plan.floor_y(w.floor)
		var h := _wall_height(w.floor)
		var is_annex := _is_annex_wall(w)
		for u in range(w.u0, w.u1 + 1):
			for t in w.thickness:
				var x := u if w.axis == 2 else w.p + t
				var z := w.p + t if w.axis == 2 else u
				if is_annex:
					var a: P.Annex = plan.annexes[0]
					var top_h := _annex_top(a, x) if w.axis == 2 else a.eave
					for y in range(y0, y0 + top_h):
						set_cell(x, y, z, a.wall_material if y - y0 > 8 or a.wall_material == "wood_aged" else "stone_rubble_dark")
				else:
					for y in range(y0, y0 + h):
						set_cell(x, y, z, wall_key(w.floor, y - y0, x, z))

func _is_annex_wall(w: P.Wall) -> bool:
	if not w.exterior:
		return false
	for a in plan.annexes:
		if w.axis == 2 and w.p >= a.z0 and w.p <= a.z1 and w.u0 >= a.x0 and w.u1 <= a.x1:
			return true
		if w.axis == 0 and w.p >= a.x1 - 1 and w.u0 >= a.z0 and w.u1 <= a.z1 and w.p != plan.mx and w.p != plan.mx + plan.W - 2:
			return true
	return false

## Hauteur des murs de l'appentis (cellules au-dessus du sol fini) à la colonne x : suit la pente du toit.
func _annex_top(a: P.Annex, x: int) -> int:
	var high := P.CLEAR
	var low: int = a.eave
	var t := float(x - a.x0) / float(maxi(a.x1 - a.x0, 1))
	return int(round(lerpf(float(high), float(low), t)))

# ------------------------------------------------------------------ ossature de bois (style « colombage »)

func _timber_frame() -> void:
	if not plan.style["timber"]:
		return
	var frame: String = plan.style["frame"]
	for w in plan.walls:
		if not w.exterior:
			continue
		var is_main := true
		for a in plan.annexes:
			if w.p >= a.x1 - 1 and w.axis == 0 or (w.axis == 2 and w.u0 >= a.x0):
				is_main = false
		if not is_main:
			continue
		var y0 := plan.floor_y(w.floor)
		var sill_y := y0 + (int(plan.style["low_height"]) if w.floor == 0 else 0)
		var top_y := y0 + _wall_height(w.floor) - 1
		var u := w.u0 + 2
		var posts: Array[int] = [w.u0, w.u1 - 1]
		while u < w.u1 - 10:
			posts.append(u)
			u += rng.randi_range(12, 22)
		posts.sort()
		for pu in posts:
			for t in w.thickness:
				for dy in range(sill_y, top_y):
					for du in 2:
						var uu: int = pu + du
						if uu > w.u1:
							continue
						var x := uu if w.axis == 2 else w.p + t
						var z := w.p + t if w.axis == 2 else uu
						if vol.get_voxel(x, dy, z) != 0:
							set_cell(x, dy, z, frame)
		# sablière basse et haute
		for uu in range(w.u0, w.u1 + 1):
			for t in w.thickness:
				for ry in [sill_y, top_y - 1, top_y]:
					var x := uu if w.axis == 2 else w.p + t
					var z := w.p + t if w.axis == 2 else uu
					if vol.get_voxel(x, ry, z) != 0:
						set_cell(x, ry, z, frame)
		# croix de Saint-André irrégulières : pas toutes les travées
		for i in range(posts.size() - 1):
			if rng.randf() < 0.4 and posts[i + 1] - posts[i] >= 12:
				var ua := posts[i] + 2
				var ub := posts[i + 1] - 1
				var flip := rng.randf() < 0.5
				var n := top_y - 1 - sill_y - 1
				for k in range(n):
					var uu := ua + int(round(float(k) * float(ub - ua) / float(n)))
					if flip:
						uu = ub - (uu - ua)
					for t in w.thickness:
						var x := uu if w.axis == 2 else w.p + t
						var z := w.p + t if w.axis == 2 else uu
						if vol.get_voxel(x, sill_y + 1 + k, z) != 0:
							set_cell(x, sill_y + 1 + k, z, frame)

# ------------------------------------------------------------------ planchers

func _floors() -> void:
	for r in plan.rooms:
		var fy := plan.floor_y(r.floor)
		fill(r.x0, fy - 1, r.z0, r.x1, fy - 1, r.z1, r.floor_material)
	# Planchers d'étage : lisses (poutres) + planches, couvrant tout l'intérieur du bloc principal.
	for f in range(1, plan.floors):
		var fy := plan.floor_y(f)
		var x0 := plan.mx + P.WALL
		var x1 := plan.mx + plan.W - P.WALL - 1
		var z0 := plan.mz + P.WALL
		var z1 := plan.mz + plan.D - P.WALL - 1
		fill(x0, fy - P.SLAB, z0, x1, fy - 2, z1, "wood_aged")
		for z in range(z0, z1 + 1, 6):
			fill(x0, fy - P.SLAB, z, x1, fy - P.SLAB, z, "wood_aged_dark")
		for r in plan.rooms:
			if r.floor == f:
				fill(r.x0, fy - 1, r.z0, r.x1, fy - 1, r.z1, r.floor_material)
		# les cloisons d'étage reposent sur le plancher : lignes de partition remplies après

func _partitions() -> void:
	for w in plan.walls:
		if w.exterior:
			continue
		var y0 := plan.floor_y(w.floor)
		var h := _wall_height(w.floor) if w.floor < plan.floors - 1 else P.CLEAR
		h = P.CLEAR
		for u in range(w.u0, w.u1 + 1):
			for t in w.thickness:
				var x := u if w.axis == 2 else w.p + t
				var z := w.p + t if w.axis == 2 else u
				for y in range(y0, y0 + h):
					var key: String = w.material
					if w.thickness >= 2:
						key = "plaster_worn_grey" if (y - y0) > 6 else "stone_rubble"
					set_cell(x, y, z, key)
	# Poteaux de cloison apparents (bois) tous les 20 cellules sur les cloisons minces.
	for w in plan.walls:
		if w.exterior or w.thickness >= 2:
			continue
		var y0 := plan.floor_y(w.floor)
		for u in range(w.u0, w.u1 + 1, 20):
			for y in range(y0, y0 + P.CLEAR):
				var x := u if w.axis == 2 else w.p
				var z := w.p if w.axis == 2 else u
				set_cell(x, y, z, "wood_aged_dark")

# ------------------------------------------------------------------ escalier

func stair_tread_z(k: int) -> Vector2i:
	# marche k (1..13) : z_lo..z_hi ; le pied de l'escalier est au sud
	var st: P.StairPlan = plan.stair
	var south := st.z0 + st.l - 1
	var z_hi := south - 3 * (k - 1)
	return Vector2i(z_hi - 2, z_hi)

func _stairs() -> void:
	if plan.stair == null:
		return
	var st: P.StairPlan = plan.stair
	var steps := P.FLOOR_H / P.STEP_RISE
	var fy1 := plan.floor_y(1)
	# Trémie : de la marche 1 à la marche 12 (la marche 13 est le palier, à hauteur du plancher d'étage).
	var south := st.z0 + st.l - 1
	air(st.x0, fy1 - P.SLAB, st.z0 + 3, st.x0 + st.w - 1, fy1 - 1, south)
	for k in range(1, steps + 1):
		var zz := stair_tread_z(k)
		var top := plan.floor_y(0) + P.STEP_RISE * k
		fill(st.x0, plan.floor_y(0), zz.x, st.x0 + st.w - 1, top - 1, zz.y, "wood_aged_dark")
		fill(st.x0, top - 1, zz.x, st.x0 + st.w - 1, top - 1, zz.y, "wood_pale_old" if k % 2 == 0 else "floor_planks")

# ------------------------------------------------------------------ foyer et cheminée

func hearth_block() -> Dictionary:
	if plan.hearth.is_empty():
		return {}
	var h: Dictionary = plan.hearth
	var hx: int = h["x"]
	var hz: int = h["z"]
	var hw: int = h["w"]
	var hd: int = h["d"]
	var rect: Rect2i
	match String(h["side"]):
		"W", "E":
			rect = Rect2i(hx, hz, hd, hw)
		_:
			rect = Rect2i(hx, hz, hw, hd)
	return {"rect": rect, "side": h["side"], "h": int(h["h"]), "room": h["room"]}

func _hearth() -> void:
	var hb := hearth_block()
	if hb.is_empty():
		return
	var r: Rect2i = hb["rect"]
	var fy := plan.floor_y(0)
	var hh: int = hb["h"]
	fill(r.position.x, fy, r.position.y, r.end.x - 1, fy + hh - 1, r.end.y - 1, "stone_rubble_dark")
	# Parement plus clair sur la façade du foyer.
	var side: String = hb["side"]
	var fbx0 := 0
	var fbx1 := 0
	var fbz0 := 0
	var fbz1 := 0
	match side:
		"W":
			fbx0 = r.position.x + 1
			fbx1 = r.end.x - 1
			fbz0 = r.position.y + 3
			fbz1 = r.end.y - 4
		"E":
			fbx0 = r.position.x
			fbx1 = r.end.x - 2
			fbz0 = r.position.y + 3
			fbz1 = r.end.y - 4
		_:
			fbx0 = r.position.x + 3
			fbx1 = r.end.x - 4
			fbz0 = r.position.y + 1
			fbz1 = r.end.y - 1
	# Boîte à feu : suie en fond, air devant ; linteau de bois au-dessus.
	fill(fbx0, fy, fbz0, fbx1, fy + 8, fbz1, "soot")
	var ax0 := fbx0 + (0 if side != "W" else 1)
	var ax1 := fbx1 - (0 if side != "E" else 1)
	var az0 := fbz0 + (0 if side != "N" else 1)
	var az1 := fbz1
	match side:
		"W":
			air(fbx0 + 2, fy, fbz0 + 1, fbx1, fy + 7, fbz1 - 1)
		"E":
			air(fbx0, fy, fbz0 + 1, fbx1 - 2, fy + 7, fbz1 - 1)
		_:
			air(fbx0 + 1, fy, fbz0 + 2, fbx1 - 1, fy + 7, fbz1)
	# Lintel et dalle de sol de foyer.
	match side:
		"W":
			fill(r.end.x - 1, fy + 9, fbz0 - 1, r.end.x - 1, fy + 9, fbz1 + 1, "wood_aged_dark")
		"E":
			fill(r.position.x, fy + 9, fbz0 - 1, r.position.x, fy + 9, fbz1 + 1, "wood_aged_dark")
		_:
			fill(fbx0 - 1, fy + 9, r.end.y - 1, fbx1 + 1, fy + 9, r.end.y - 1, "wood_aged_dark")
	# Cheminée : massif monté jusqu'au-dessus du faîtage.
	var ch: Dictionary = plan.chimney
	var top_y := int(ceil(_max_roof_y())) + 6
	fill(ch["x0"], fy + hh, ch["z0"], ch["x1"], top_y, ch["z1"], "stone_rubble")
	fill(ch["x0"] - 1, top_y - 1, ch["z0"] - 1, ch["x1"] + 1, top_y, ch["z1"] + 1, "stone_rubble_dark")
	fill(ch["x0"], top_y + 1, ch["z0"], ch["x1"], top_y + 1, ch["z1"], "stone_rubble_dark")
	# conduit : évidement de suie de la boîte à feu jusqu'en haut (le feu « tire »)
	fill(ch["x0"] + 2, top_y + 1, ch["z0"] + 2, ch["x1"] - 2, top_y + 1, ch["z1"] - 2, "soot")
	model.checks["chimney_top"] = top_y

func _max_roof_y() -> float:
	var r: Dictionary = plan.roof
	var pitch: Array = r["pitch"]
	var eave := float(plan.floor_y(plan.floors - 1) + P.CLEAR)
	var half := (float(plan.D) if r["axis"] == 0 else float(plan.W)) * 0.5
	return eave + half * float(pitch[0]) / float(pitch[1]) + float(r["thick"])

# ------------------------------------------------------------------ pignons et toitures

func _gables_and_roofs() -> void:
	var r: Dictionary = plan.roof
	var eave := plan.floor_y(plan.floors - 1) + P.CLEAR
	var up: String = plan.style["wall_up"]
	# Pignons : comblent le triangle entre le haut des murs et la sous-face du toit.
	if r["axis"] == 0:
		for wx in [plan.mx, plan.mx + plan.W - P.WALL]:
			for t in P.WALL:
				for z in range(plan.mz, plan.mz + plan.D):
					var top := int(ceil(roof_underside(wx, z)))
					for y in range(eave, top):
						set_cell(wx + t, y, z, wall_key(plan.floors - 1, y - eave + 10, wx, z))
	else:
		for wz in [plan.mz, plan.mz + plan.D - P.WALL]:
			for t in P.WALL:
				for x in range(plan.mx, plan.mx + plan.W):
					var top := int(ceil(roof_underside(x, wz)))
					for y in range(eave, top):
						set_cell(x, y, wz + t, wall_key(plan.floors - 1, y - eave + 10, x, wz))
	# Toit principal : trois tronçons le long du faîtage (celui du milieu en matériau de réparation).
	var ov: int = r["overhang"]
	var half: float = (float(plan.D) if r["axis"] == 0 else float(plan.W)) * 0.5
	var prof := RoofBuilder.gable_profile(half, ov, eave, r["pitch"], r["thick"])
	var length_cells := (plan.W if r["axis"] == 0 else plan.D) + 2 * 2
	var start_cells := (plan.mx if r["axis"] == 0 else plan.mz) - 2
	var segs: Array = [[0.0, 1.0, r["material"]]]
	if r["patch"]:
		var u0: float = r["patch_u"]
		var l: float = r["patch_len"]
		segs = [[0.0, u0, r["material"]], [u0, minf(u0 + l, 1.0), r["alt_material"]], [minf(u0 + l, 1.0), 1.0, r["material"]]]
	for s in segs:
		if s[1] - s[0] <= 0.001:
			continue
		var a0 := int(round(float(s[0]) * length_cells))
		var a1 := int(round(float(s[1]) * length_cells))
		if a1 <= a0:
			continue
		var ex := RoofBuilder.extrude(prof["bottom"], prof["top"], float(a1 - a0) * C, r["axis"], s[2])
		var along := (start_cells + a0) * C
		var across := (float(plan.mz) + half - half - float(ov)) * C if r["axis"] == 0 else (float(plan.mx) - float(ov)) * C
		var off: Vector3
		if r["axis"] == 0:
			off = Vector3(along, float(prof["origin_y"]) * C, (float(plan.mz) - float(ov)) * C)
		else:
			off = Vector3((float(plan.mx) - float(ov)) * C, float(prof["origin_y"]) * C, along)
		model.roofs.append({"arrays": ex["arrays"], "offset": off, "material": s[2], "name": "roof_main"})
	# Toit de l'appentis (un pan).
	for a in plan.annexes:
		var run := float(a.x1 - a.x0 + 1)
		var low_y: int = plan.floor_y(0) + a.eave
		var high_y: int = plan.floor_y(0) + P.CLEAR
		var sp := RoofBuilder.shed_profile(run, r["overhang"], low_y, high_y, int(r["thick"]))
		# Le profil part du bord bas (x grand) ; on l'extrude le long de z et on le retourne en x.
		var bottom: PackedInt32Array = sp["bottom"]
		var topv: PackedInt32Array = sp["top"]
		var n := bottom.size()
		var rb := PackedInt32Array()
		var rt := PackedInt32Array()
		rb.resize(n)
		rt.resize(n)
		for i in n:
			rb[i] = bottom[n - 1 - i]
			rt[i] = topv[n - 1 - i]
		var length_m := float(a.z1 - a.z0 + 1 + 2 * r["overhang"]) * C
		var ex := RoofBuilder.extrude(rb, rt, length_m, 2, r["alt_material"])
		var off := Vector3(float(a.x0) * C, float(sp["origin_y"]) * C, float(a.z0 - int(r["overhang"])) * C)
		model.roofs.append({"arrays": ex["arrays"], "offset": off, "material": r["alt_material"], "name": "roof_annex"})

# ------------------------------------------------------------------ reprises et réparations

func _patches() -> void:
	var count := rng.randi_range(2, 4)
	var patch_mat: String = plan.style["patch_up"]
	for i in count:
		var w: P.Wall = plan.walls[rng.randi() % plan.walls.size()]
		if not w.exterior:
			continue
		var y0 := plan.floor_y(w.floor)
		var pw := rng.randi_range(5, 12)
		var ph := rng.randi_range(4, 9)
		var u := rng.randi_range(w.u0 + 3, maxi(w.u1 - pw - 3, w.u0 + 4))
		var yy := y0 + rng.randi_range(6, maxi(P.CLEAR - ph - 2, 7))
		for du in pw:
			for dy in ph:
				for t in w.thickness:
					var x := u + du if w.axis == 2 else w.p + t
					var z := w.p + t if w.axis == 2 else u + du
					if vol.get_voxel(x, yy + dy, z) != 0:
						set_cell(x, yy + dy, z, patch_mat)

# ------------------------------------------------------------------ ouvertures

func opening_box(o: P.Opening) -> Dictionary:
	var y0 := plan.floor_y(o.floor) + o.sill
	if o.axis == 2:
		return {"x0": o.u, "x1": o.u + o.w - 1, "z0": o.p, "z1": o.p + o.thickness - 1, "y0": y0, "y1": y0 + o.h - 1}
	return {"x0": o.p, "x1": o.p + o.thickness - 1, "z0": o.u, "z1": o.u + o.w - 1, "y0": y0, "y1": y0 + o.h - 1}

func _carve_openings() -> void:
	for o in plan.openings:
		var b := opening_box(o)
		air(b["x0"], b["y0"], b["z0"], b["x1"], b["y1"], b["z1"])

func _openings_trim() -> void:
	var reclaimed: bool = plan.style["reclaimed"]
	for oi in plan.openings.size():
		var o: P.Opening = plan.openings[oi]
		var b := opening_box(o)
		var lintel := "wood_aged_dark"
		if o.main and reclaimed:
			lintel = "stone_carved"
		if o.kind == "door":
			if o.axis == 2:
				fill(b["x0"] - 1, b["y1"] + 1, b["z0"], b["x1"] + 1, b["y1"] + 1, b["z1"], lintel)
				fill(b["x0"] - 1, b["y0"], b["z0"], b["x0"] - 1, b["y1"], b["z1"], "wood_aged")
				fill(b["x1"] + 1, b["y0"], b["z0"], b["x1"] + 1, b["y1"], b["z1"], "wood_aged")
			else:
				fill(b["x0"], b["y1"] + 1, b["z0"] - 1, b["x1"], b["y1"] + 1, b["z1"] + 1, lintel)
				fill(b["x0"], b["y0"], b["z0"] - 1, b["x1"], b["y1"], b["z0"] - 1, "wood_aged")
				fill(b["x0"], b["y0"], b["z1"] + 1, b["x1"], b["y1"], b["z1"] + 1, "wood_aged")
			# seuil : une pierre à hauteur du sol fini
			if o.axis == 2:
				fill(b["x0"], b["y0"] - 1, b["z0"], b["x1"], b["y0"] - 1, b["z1"], "stone_rubble_dark")
			else:
				fill(b["x0"], b["y0"] - 1, b["z0"], b["x1"], b["y0"] - 1, b["z1"], "stone_rubble_dark")
		else:
			# fenêtre : linteau de bois, appui de pierre débordant vers l'extérieur
			if o.axis == 2:
				fill(b["x0"] - 1, b["y1"] + 1, b["z0"], b["x1"] + 1, b["y1"] + 1, b["z1"], "wood_aged_dark")
				fill(b["x0"] - 1, b["y0"] - 1, b["z0"], b["x1"] + 1, b["y0"] - 1, b["z1"], "stone_rubble_dark")
			else:
				fill(b["x0"], b["y1"] + 1, b["z0"] - 1, b["x1"], b["y1"] + 1, b["z1"] + 1, "wood_aged_dark")
				fill(b["x0"], b["y0"] - 1, b["z0"] - 1, b["x1"], b["y0"] - 1, b["z1"] + 1, "stone_rubble_dark")

## Éléments récupérés dans les ruines : tambour de colonne en marche, bloc sculpté encastré.
func _reclaimed() -> void:
	if not plan.style["reclaimed"] or plan.main_door < 0:
		return
	var o: P.Opening = plan.openings[plan.main_door]
	# Tambour de colonne couché devant la porte (pierre claire sculptée, cristal éteint en son centre).
	var ox := o.u + o.w + 4
	var oz := o.p + o.thickness
	fill(ox, P.GY, oz + 1, ox + 5, P.GY + 2, oz + 5, "stone_carved")
	set_cell(ox + 2, P.GY + 3, oz + 3, "stone_carved")
	# Bloc sculpté encastré dans le mur, à côté de la porte.
	var u := o.u - 8
	if u > plan.mx + 3:
		var y := plan.floor_y(0) + 10
		for du in 4:
			for dy in 4:
				for t in 2:
					set_cell(u + du, y + dy, o.p + t, "stone_carved")
		set_cell(u + 1, y + 1, o.p + o.thickness - 1, "crystal_deep")

# ------------------------------------------------------------------ colliders simplifiés

func _box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
	model.colliders.append(AABB(Vector3(x0, y0, z0) * C, Vector3(x1 - x0 + 1, y1 - y0 + 1, z1 - z0 + 1) * C))

func _colliders() -> void:
	# sols et fondations
	for r in _blocks():
		_box(r.position.x, 0, r.position.y, r.end.x - 1, P.FY - 1, r.end.y - 1)
	# planchers d'étage (sans la trémie)
	for f in range(1, plan.floors):
		var fy := plan.floor_y(f)
		var x0 := plan.mx + P.WALL
		var x1 := plan.mx + plan.W - P.WALL - 1
		var z0 := plan.mz + P.WALL
		var z1 := plan.mz + plan.D - P.WALL - 1
		if plan.stair == null:
			_box(x0, fy - P.SLAB, z0, x1, fy - 1, z1)
		else:
			var st: P.StairPlan = plan.stair
			var south := st.z0 + st.l - 1
			var hz0 := st.z0 + 3
			var hx0 := st.x0
			var hx1 := st.x0 + st.w - 1
			_box(x0, fy - P.SLAB, z0, x1, fy - 1, hz0 - 1)                 # nord de la trémie
			if hx0 > x0:
				_box(x0, fy - P.SLAB, hz0, hx0 - 1, fy - 1, z1)
			if hx1 < x1:
				_box(hx1 + 1, fy - P.SLAB, hz0, x1, fy - 1, z1)
	# murs, découpés autour des ouvertures
	for w in plan.walls:
		var y0 := plan.floor_y(w.floor)
		var h := _wall_height(w.floor) if w.exterior else P.CLEAR
		var ops: Array[P.Opening] = []
		for o in plan.openings:
			if o.floor == w.floor and o.axis == w.axis and o.p == w.p and o.u >= w.u0 and o.u + o.w - 1 <= w.u1:
				ops.append(o)
		ops.sort_custom(func(a, b): return a.u < b.u)
		var cur := w.u0
		for o in ops:
			if o.u > cur:
				_wall_box(w, cur, o.u - 1, y0, y0 + h - 1)
			# allège et linteau
			if o.sill > 0:
				_wall_box(w, o.u, o.u + o.w - 1, y0, y0 + o.sill - 1)
			if o.sill + o.h < h:
				_wall_box(w, o.u, o.u + o.w - 1, y0 + o.sill + o.h, y0 + h - 1)
			cur = o.u + o.w
		if cur <= w.u1:
			_wall_box(w, cur, w.u1, y0, y0 + h - 1)
	# marches
	if plan.stair != null:
		var st: P.StairPlan = plan.stair
		for k in range(1, P.FLOOR_H / P.STEP_RISE + 1):
			var zz := stair_tread_z(k)
			_box(st.x0, plan.floor_y(0), zz.x, st.x0 + st.w - 1, plan.floor_y(0) + P.STEP_RISE * k - 1, zz.y)
	# foyer et cheminée
	var hb := hearth_block()
	if not hb.is_empty():
		var r: Rect2i = hb["rect"]
		_box(r.position.x, plan.floor_y(0), r.position.y, r.end.x - 1, plan.floor_y(0) + int(hb["h"]) - 1, r.end.y - 1)

func _wall_box(w: P.Wall, u0: int, u1: int, y0: int, y1: int) -> void:
	if _is_annex_wall(w):
		# murs d'appentis : hauteur variable (suit la pente du toit) → tronçons de 6 cellules, hauteur du côté bas
		var a: P.Annex = plan.annexes[0]
		var u := u0
		while u <= u1:
			var ue := mini(u + 5, u1)
			var top_h: int = a.eave
			if w.axis == 2:
				top_h = mini(_annex_top(a, u), _annex_top(a, ue))
			var top := plan.floor_y(w.floor) + top_h - 1
			if top >= y0 and top_h > 0:
				var yy1 := mini(y1, top)
				if w.axis == 2:
					_box(u, y0, w.p, ue, yy1, w.p + w.thickness - 1)
				else:
					_box(w.p, y0, u, w.p + w.thickness - 1, yy1, ue)
			u = ue + 1
		return
	if w.axis == 2:
		_box(u0, y0, w.p, u1, y1, w.p + w.thickness - 1)
	else:
		_box(w.p, y0, u0, w.p + w.thickness - 1, y1, u1)

# ------------------------------------------------------------------ description de l'intérieur

func _rooms_info() -> void:
	var hb := hearth_block()
	for r in plan.rooms:
		var info := {
			"id": r.id, "role": r.role, "floor": r.floor, "annex": r.annex,
			"rect": Rect2(Vector2(r.x0, r.z0) * C, Vector2(r.x1 - r.x0 + 1, r.z1 - r.z0 + 1) * C),
			"floor_y": float(plan.floor_y(r.floor)) * C, "obstacles": [],
		}
		# obstacles : foyer (+ dégagement), escalier, cheminée traversante
		if not hb.is_empty() and hb["room"] == r.id and r.floor == 0:
			var hr: Rect2i = hb["rect"]
			var grown := Rect2(Vector2(hr.position) * C, Vector2(hr.size) * C).grow(0.0)
			var side: String = hb["side"]
			var clear := 0.9
			match side:
				"W": grown = Rect2(grown.position, Vector2(grown.size.x + clear, grown.size.y))
				"E": grown = Rect2(grown.position - Vector2(clear, 0), Vector2(grown.size.x + clear, grown.size.y))
				_: grown = Rect2(grown.position, Vector2(grown.size.x, grown.size.y + clear))
			info["obstacles"].append(grown)
		if plan.stair != null and (r.role == "stairs" or r.role == "landing"):
			var st: P.StairPlan = plan.stair
			if r.floor == 0 or r.role == "landing":
				info["obstacles"].append(Rect2(Vector2(st.x0, st.z0) * C, Vector2(st.w, st.l) * C))
		if not plan.chimney.is_empty() and r.floor > 0 and not hb.is_empty():
			var ch: Dictionary = plan.chimney
			info["obstacles"].append(Rect2(Vector2(ch["x0"], ch["z0"]) * C, Vector2(ch["x1"] - ch["x0"] + 1, ch["z1"] - ch["z0"] + 1) * C))
		model.rooms.append(info)
	# Dégagement devant chaque porte (battant ouvert) : carré de la largeur de porte, côté pièce.
	for o in plan.openings:
		if o.kind != "door":
			continue
		var b := opening_box(o)
		var rect: Rect2
		if o.axis == 2:
			rect = Rect2(Vector2(b["x0"], b["z0"] - o.w) * C, Vector2(o.w, o.w * 2 + o.thickness) * C)
		else:
			rect = Rect2(Vector2(b["x0"] - o.w, b["z0"]) * C, Vector2(o.w * 2 + o.thickness, o.w) * C)
		model.door_clear.append({"floor": o.floor, "rect": rect})

func _checks() -> void:
	var c := model.checks
	var min_door_w := 1000
	var min_door_h := 1000
	for o in plan.openings:
		if o.kind == "door":
			min_door_w = mini(min_door_w, o.w)
			min_door_h = mini(min_door_h, o.h)
	c["min_door_w_cells"] = min_door_w
	c["min_door_h_cells"] = min_door_h
	c["clear_height_cells"] = P.CLEAR
	c["step_rise_cells"] = P.STEP_RISE
	c["step_run_cells"] = P.STEP_RUN
	c["sill_cells"] = P.FY - P.GY
