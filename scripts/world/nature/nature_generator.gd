@tool
class_name NatureGenerator
extends RefCounted
## Végétation, rochers et plantes d'une île, posés par le placement universel :
##   - les couloirs de circulation (routes, cours, place) sont réservés d'abord ;
##   - les arbres forment des BOSQUETS (mêmes espèces selon l'humidité du sol) plus quelques isolés ;
##   - les rochers se répartissent entre quatre familles (blocs, affleurements au bord, formations, ruines) ;
##   - les plantes sont semées en AMAS selon le biome, jamais sur une zone bâtie, un chemin, une
##     emprise réservée ou la roche nue.
## Chaque refus est compté par raison (stats de placement) ; rien n'est posé « de force ».

const V := VoxelGrid.VOXEL_SIZE

var w: WorldData
var field: TerrainField
var occ: OccupancyMap
var placement: PlacementSystem
var rng: RandomNumberGenerator
var pal: VoxelPalette
var _mat_biome := {}       # id de matière → biome

static func generate(world: WorldData) -> void:
	var g := NatureGenerator.new()
	g.w = world
	g.field = world.field
	g.occ = world.occ
	g.placement = world.placement
	g.rng = WorldRng.stream(world.seed, "nature")
	g.pal = VoxelPalette.get_default()
	for k in ["grass_lush"]:
		g._mat_biome[g.pal.id(k)] = "lush"
	for k in ["grass_dry", "dirt_dry"]:
		g._mat_biome[g.pal.id(k)] = "dry"
	for k in ["rock_warm", "rock_grey", "stone", "stone_dark"]:
		g._mat_biome[g.pal.id(k)] = "rock"
	g._reserve_corridors()
	g._rocks()
	g._trees()
	g._plants()

# ------------------------------------------------------------------ couloirs réservés

## Les routes gardent un couloir libre de 40 cm de part et d'autre (rien de dur n'y est posé).
func _reserve_corridors() -> void:
	var n := field.n
	var owner := occ.new_owner()
	for idx in w.paths.road_cells:
		var cx: int = idx % n
		var cz: int = idx / n
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				var x := cx + dx
				var z := cz + dz
				if not field.has_ground(x, z):
					continue
				var i := x + z * n
				if occ.tag[i] == PlacementSpec.TAG_FREE and Vector2(dx, dz).length() <= 3.2:
					occ.tag[i] = PlacementSpec.TAG_ROAD
					occ.owner[i] = owner

func _biome_at(p: Vector2) -> String:
	var c := field.col_of_m(p.x, p.y)
	if not field.has_ground(c.x, c.y):
		return "normal"
	return _mat_biome.get(int(field.material[field.idx(c.x, c.y)]), "normal")

func _free_natural_point(min_edge: float, avoid: Array, min_gap: float) -> Vector2:
	for k in 80:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * field.radius_m * 0.95
		var c: Vector2 = field.landmarks.get("center", Vector2.ZERO)
		var p := c + Vector2(cos(a), sin(a)) * r
		var col := field.col_of_m(p.x, p.y)
		if not field.has_ground(col.x, col.y):
			continue
		var i := field.idx(col.x, col.y)
		if field.zone[i] != TerrainField.Zone.NATURAL or occ.tag[i] != PlacementSpec.TAG_FREE or field.edge_dist[i] < min_edge:
			continue
		var ok := true
		for q: Vector2 in avoid:
			if q.distance_to(p) < min_gap:
				ok = false
				break
		if ok:
			return p
	return Vector2(INF, INF)

# ------------------------------------------------------------------ arbres

func _tree_spec(pl: Dictionary) -> PlacementSpec:
	var s := PlacementSpec.new()
	s.id = "tree_%s_%d" % [pl["species"], pl["seed"] % 100000]
	s.kind = "tree"
	var r: float = pl["trunk_r"]
	s.size = Vector3(r * 2.2, float(pl["height"]), r * 2.2)
	s.hard = [AABB(Vector3(-r, 0.0, -r), Vector3(r * 2.0, minf(float(pl["height"]), 2.2), r * 2.0))]
	var cr: AABB = pl["crown"]
	if cr.size.x > 0.0:
		var ext := maxf(maxf(absf(cr.position.x), cr.end.x), maxf(absf(cr.position.z), cr.end.z))
		s.soft = [AABB(Vector3(-ext, cr.position.y, -ext), Vector3(ext * 2.0, cr.size.y, ext * 2.0))]
	s.support = "ground"
	s.support_fraction = 0.7
	s.gap_tolerance_m = 0.2
	s.embed_max_m = 0.4
	s.clearance_m = 0.45
	s.cliff_margin_m = 0.7
	s.soft_overlap_max = 0.5
	s.allowed_zones = PackedInt32Array([TerrainField.Zone.NATURAL])
	s.forbidden_materials = PackedStringArray(["rock_warm", "rock_grey", "cobble", "cobble_dark", "path_dirt", "stone"])
	s.snap_m = 0.2
	return s

func _trees() -> void:
	var total := WorldRng.range_i(rng, w.profile.g("vegetation.tree_count", [10, 16]))
	var groves := WorldRng.range_i(rng, w.profile.g("vegetation.grove_count", [2, 3]))
	var centers: Array[Vector2] = []
	var placed := 0
	var in_groves := int(float(total) * 0.72)
	for gi in groves:
		var c := _free_natural_point(3.0, centers, 9.0)
		if c.x == INF:
			continue
		centers.append(c)
		var biome := _biome_at(c)
		var main := TreeGenerator.species_for(biome, rng)
		var second := TreeGenerator.species_for(biome, rng)
		var want := in_groves / groves
		var radius := rng.randf_range(4.5, 6.5)
		for k in want:
			var sp := main if rng.randf() < 0.7 else second
			if _place_tree(sp, c, radius):
				placed += 1
	var guard := 0
	while placed < total and guard < total * 4:
		guard += 1
		var p := _free_natural_point(1.5, [], 0.0)
		if p.x == INF:
			break
		var sp := TreeGenerator.species_for(_biome_at(p), rng)
		if _place_tree(sp, p, 3.0):
			placed += 1

func _place_tree(species: String, center: Vector2, radius: float) -> bool:
	var seed := WorldRng.sub_seed(w.seed, "tree:%d" % (w.trees.size() + 1000 * rng.randi_range(0, 9)))
	var pl := TreeGenerator.plan(species, seed)
	var spec := _tree_spec(pl)
	var res := placement.find_and_place(spec, center, radius, rng, {"samples": 36, "skip_access": true})
	if not res.ok:
		return false
	var ground := TreeGenerator.ground_grid(field, res.pos, 2.0)
	w.trees.append({"kind": "tree", "species": species, "seed": seed, "plan": pl, "res": res, "ground": ground,
		"rot": rng.randf() * TAU, "pos": res.pos, "item": res.item_index})
	return true

# ------------------------------------------------------------------ rochers

func _rock_spec(pl: Dictionary) -> PlacementSpec:
	var s := PlacementSpec.new()
	var size: Vector3 = pl["size"]
	s.id = "rock_%s_%d" % [pl["family"], pl["seed"] % 100000]
	s.kind = "rock"
	s.size = Vector3(size.x, size.y, size.z)
	var shrink := Vector3(size.x * 0.86, size.y * 0.9, size.z * 0.86)
	s.hard = [AABB(Vector3(-shrink.x * 0.5, 0.0, -shrink.z * 0.5), shrink)]
	s.support = "ground"
	s.support_fraction = 0.6
	s.gap_tolerance_m = 0.3
	s.embed_max_m = float(pl["embed"]) + 0.2
	s.clearance_m = 0.3
	s.cliff_margin_m = 0.5
	s.allowed_zones = PackedInt32Array([TerrainField.Zone.NATURAL])
	s.snap_m = 0.2
	if pl["overhang_ok"]:
		s.exceptions = PackedStringArray(["overhang_void"])
		s.overhang_fraction = 0.3
		s.cliff_margin_m = 0.0
	if pl["family"] == "ruin":
		s.forbidden_materials = PackedStringArray(["cobble", "cobble_dark"])
	return s

func _rocks() -> void:
	var total := WorldRng.range_i(rng, w.profile.g("rocks.count", [6, 10]))
	var fams: Array = w.profile.g("rocks.families", ["boulder", "outcrop"])
	var shrine: Dictionary = w.settlement.shrine if w.settlement != null else {}
	var placed := 0
	var guard := 0
	while placed < total and guard < total * 5:
		guard += 1
		var fam: String = fams[rng.randi() % fams.size()]
		var seed := WorldRng.sub_seed(w.seed, "rock:%d" % guard)
		var pl := RockGenerator.plan(fam, seed)
		var spec := _rock_spec(pl)
		var center := Vector2.ZERO
		var radius := 3.0
		if fam == "outcrop":
			center = _rim_point(2.0)
			if center.x == INF:
				continue
		elif fam == "ruin" and not shrine.is_empty() and rng.randf() < 0.6:
			center = (shrine["center"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 10.0)
		else:
			center = _free_natural_point(1.0, [], 0.0)
			if center.x == INF:
				continue
		var res := placement.find_and_place(spec, center, radius, rng, {"samples": 30, "skip_access": true})
		if not res.ok:
			continue
		var ground := TreeGenerator.ground_grid(field, res.pos, 3.4)
		w.rocks.append({"kind": "rock", "family": fam, "seed": seed, "plan": pl, "res": res, "ground": ground, "pos": res.pos,
			"xform": Transform3D(res.basis(), res.pos), "item": res.item_index})
		placed += 1

## Point du bord de l'île (légèrement en retrait) sur un rayon tiré au hasard.
func _rim_point(inset: float) -> Vector2:
	var c: Vector2 = field.landmarks.get("center", Vector2.ZERO)
	for k in 12:
		var a := rng.randf() * TAU
		var d := Vector2(cos(a), sin(a))
		var last := -1.0
		var t := 0.0
		while t < field.radius_m * 1.6:
			var q := c + d * t
			var col := field.col_of_m(q.x, q.y)
			if field.has_ground(col.x, col.y):
				last = t
			elif last >= 0.0 and t - last > 0.6:
				break
			t += 0.2
		if last < 6.0:
			continue
		var p := c + d * (last - inset)
		var col := field.col_of_m(p.x, p.y)
		if field.has_ground(col.x, col.y) and occ.tag_at(col.x, col.y) == PlacementSpec.TAG_FREE and field.zone[field.idx(col.x, col.y)] == TerrainField.Zone.NATURAL:
			return p
	return Vector2(INF, INF)

# ------------------------------------------------------------------ plantes

const PLANTS := {
	"tuft": {"lush": 1.0, "normal": 1.0, "dry": 0.8, "rock": 0.15},
	"clover": {"lush": 1.0, "normal": 0.6, "dry": 0.0, "rock": 0.0},
	"fern": {"lush": 1.0, "normal": 0.25, "dry": 0.0, "rock": 0.0},
	"flower_yellow": {"lush": 1.0, "normal": 0.6, "dry": 0.1, "rock": 0.0},
	"flower_violet": {"lush": 0.9, "normal": 0.5, "dry": 0.0, "rock": 0.0},
	"flower_white": {"lush": 1.0, "normal": 0.8, "dry": 0.1, "rock": 0.0},
}

func _plants() -> void:
	var density: float = float(w.profile.g("vegetation.plant_density", 1.0))
	var n := field.n
	var land := field.land_count()
	var used := {}
	var lists := {}
	for kind in PLANTS:
		lists[kind] = {}
	var grass_ids := {}
	for k in ["grass", "grass_lush", "grass_dry", "grass_trim", "grass_wild", "grass_trampled"]:
		grass_ids[pal.id(k)] = true
	# amas : un centre pour environ 140 colonnes de terre ; chaque amas a un type dominant
	var clusters := int(float(land) / 140.0 * density)
	var kinds := PLANTS.keys()
	for ci in clusters:
		var c := _free_natural_point(0.4, [], 0.0)
		if c.x == INF:
			continue
		var biome := _biome_at(c)
		var kind: String = kinds[rng.randi() % kinds.size()]
		if rng.randf() < 0.45:
			kind = "tuft"
		var weight: float = PLANTS[kind][biome]
		if rng.randf() > weight:
			continue
		var rho := rng.randf_range(0.7, 1.9) * (1.3 if kind == "tuft" else 1.0)
		var count := int(rng.randf_range(10.0, 34.0) * (rho / 1.2) * (1.5 if kind == "tuft" else 1.0))
		for k in count:
			var off := Vector2.from_angle(rng.randf() * TAU) * rho * sqrt(rng.randf()) * (0.4 + 0.6 * rng.randf())
			var p := c + off
			var col := field.col_of_m(p.x, p.y)
			if not field.has_ground(col.x, col.y):
				continue
			var i := field.idx(col.x, col.y)
			if field.zone[i] != TerrainField.Zone.NATURAL or occ.tag[i] != PlacementSpec.TAG_FREE or field.edge_dist[i] < 0.3:
				continue
			if not grass_ids.has(int(field.material[i])):
				continue
			var cell_key := Vector2i(col.x, col.y)
			if used.has(cell_key):
				continue
			used[cell_key] = true
			var y := float(field.top[i] + 1) * V
			var rot := Basis(Vector3.UP, float(rng.randi() % 4) * PI * 0.5)
			var half := Vector3(0.1, 0.0, 0.1)
			var cp := field.center_m(col.x, col.y)
			var base := Vector3(cp.x - 0.1, y, cp.y - 0.1)
			var key := Vector2i(floori(cp.x / 10.0), floori(cp.y / 10.0))
			if not lists[kind].has(key):
				lists[kind][key] = []
			lists[kind][key].append(Transform3D(rot, base + half - rot * half))
	for kind in lists:
		for key in lists[kind]:
			w.plants.append({"kind": kind, "cell": key, "xforms": lists[kind][key]})
	w.stats["plants"] = used.size()
