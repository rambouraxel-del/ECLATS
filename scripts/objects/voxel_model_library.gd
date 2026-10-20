@tool
class_name VoxelModelLibrary
extends RefCounted
## Bibliothèque des objets de référence.
## Chaque modèle est décrit par un dictionnaire :
##   key, name, grid (taille de cellule en m), volume (VoxelVolume),
##   world_tint (true = teinte calculée en coordonnées monde, comme le terrain),
##   light (optionnel) : { position, color, energy, range }.
## Origine d'un modèle = coin minimum de son emprise, posé au sol (y = 0).
## Toutes les emprises sont des multiples de 0,20 m : elles s'alignent sur la grille du terrain.

const D := 4  # cellules de 5 cm par voxel de terrain (modèles du Lot 1, grille 0,05 m)

const KEYS := [
	"block_stone", "block_dirt", "block_grass", "block_wood",
	"wall", "slab", "stairs", "table", "workbench", "shard_lamp",
]

static var _cache := {}

static func names() -> Dictionary:
	return {
		"block_stone": "Bloc de pierre", "block_dirt": "Bloc de terre", "block_grass": "Bloc d'herbe",
		"block_wood": "Bloc de bois", "wall": "Mur", "slab": "Dalle", "stairs": "Escalier",
		"table": "Table", "workbench": "Établi", "shard_lamp": "Lampe à éclat",
	}

static func get_model(key: String) -> Dictionary:
	if not _cache.has(key):
		_cache[key] = _build(key)
	return _cache[key]

static func _build(key: String) -> Dictionary:
	match key:
		"block_stone": return _block(key, "stone")
		"block_dirt": return _block(key, "dirt")
		"block_grass": return _block(key, "grass")
		"block_wood": return _block(key, "wood_planks")
		"wall": return _wall()
		"slab": return _slab()
		"stairs": return _stairs()
		"table": return _table()
		"workbench": return _workbench()
		"shard_lamp": return _shard_lamp()
	push_error("Modèle inconnu : %s" % key)
	return {}

static func _model(key: String, grid: float, b: VoxelModelBuilder, world_tint := false) -> Dictionary:
	return {
		"key": key, "name": names().get(key, key), "grid": grid, "volume": b.volume,
		"world_tint": world_tint, "size_m": Vector3(b.volume.size) * grid,
	}

## Bloc constructible : exactement 1 voxel de terrain (0,20 m), même matière que le sol.
static func _block(key: String, material_key: String) -> Dictionary:
	var b := VoxelModelBuilder.new(Vector3i.ONE)
	b.set_cell(0, 0, 0, material_key)
	return _model(key, VoxelGrid.VOXEL_SIZE, b, true)

## Mur en pierre appareillée : 1,00 × 2,40 × 0,20 m. Joints en creux, pierres de tailles
## variées, lisse de bois sombre en couronnement.
static func _wall() -> Dictionary:
	var w := 5 * D
	var h := 12 * D
	var t := 1 * D
	var b := VoxelModelBuilder.new(Vector3i(w, h, t))
	# Âme de mortier en retrait (les joints apparaissent en creux).
	b.box(0, 0, 1, w - 1, h - 3, t - 2, "mortar")
	var course_h := 4
	var lengths := [7, 5, 9, 6, 8, 5, 7]
	for c in (h - 2) / course_h:
		var y0 := c * course_h
		var x := -((c * 3) % 6)
		var k := c
		while x < w:
			var length: int = lengths[k % lengths.size()]
			var x0 := maxi(x, 0)
			var x1 := mini(x + length - 2, w - 1)  # 1 cellule de joint entre deux pierres
			var key := "stone_brick" if VoxelGrid.hash01(k, c, 0, 41) > 0.3 else "stone"
			if c == 0:
				key = "stone_dark"
			if x1 >= x0:
				b.box(x0, y0, 0, x1, y0 + course_h - 2, t - 1, key)
			x += length
			k += 1
	# Couronnement en bois sombre, légèrement plus large que le joint.
	b.box(0, h - 2, 0, w - 1, h - 1, t - 1, "wood_dark")
	b.speckle("stone_brick", "moss", 0.02, 7)
	return _model("wall", VoxelGrid.LEGACY_DETAIL_SIZE, b)

## Dalle de sol : 1,00 × 1,00 × 0,20 m, quatre carreaux à coins chanfreinés.
static func _slab() -> Dictionary:
	var s := 5 * D
	var b := VoxelModelBuilder.new(Vector3i(s, D, s))
	b.box(0, 0, 0, s - 1, D - 2, s - 1, "stone")
	var tile := s / 2
	for tz in 2:
		for tx in 2:
			var key := "stone_brick" if (tx + tz) % 2 == 0 else "stone"
			var x0 := tx * tile
			var z0 := tz * tile
			b.box(x0, D - 1, z0, x0 + tile - 2, D - 1, z0 + tile - 2, key)
			# Chanfrein : on retire les coins du carreau.
			for corner in [Vector2i(x0, z0), Vector2i(x0 + tile - 2, z0), Vector2i(x0, z0 + tile - 2), Vector2i(x0 + tile - 2, z0 + tile - 2)]:
				b.set_cell(corner.x, D - 1, corner.y, "")
	return _model("slab", VoxelGrid.LEGACY_DETAIL_SIZE, b)

## Escalier à limons de bois : 1,00 m de large, monte de 1,00 m sur 2,00 m.
## Marches ouvertes en planches, limons qui suivent la pente, embouts en laiton.
static func _stairs() -> Dictionary:
	var w := 5 * D
	var rise := 5 * D
	var run := 10 * D
	var steps := 5
	var b := VoxelModelBuilder.new(Vector3i(w, rise + 2, run))
	var step_run := run / steps
	var step_rise := rise / steps
	for side in [0, w - 2]:
		# Limon : bande épaisse qui suit la pente.
		for z in run:
			var top := int(float(z + 1) / step_run * step_rise) + 1
			b.box(side, maxi(top - 5, 0), z, side + 1, mini(top, rise + 1), z, "wood_dark")
		b.box(side, rise, run - 2, side + 1, rise + 1, run - 1, "brass")
		b.box(side, 0, 0, side + 1, 1, 1, "brass")
	for i in steps:
		var y_top := (i + 1) * step_rise - 1
		var z0 := i * step_run
		b.box(2, y_top - 1, z0, w - 3, y_top, z0 + step_run - 1, "wood_planks")
		# Nez de marche plus sombre.
		b.box(2, y_top, z0, w - 3, y_top, z0, "wood_dark")
	return _model("stairs", VoxelGrid.LEGACY_DETAIL_SIZE, b)

## Table à tréteaux croisés : 1,40 × 0,80 × 0,80 m.
static func _table() -> Dictionary:
	var sx := 7 * D
	var sz := 4 * D
	var sy := 4 * D
	var b := VoxelModelBuilder.new(Vector3i(sx, sy, sz))
	# Plateau en planches (rainures sur le dessus), embouts sombres.
	b.box(0, sy - 2, 0, sx - 1, sy - 1, sz - 1, "wood_planks")
	for z in range(3, sz - 1, 4):
		b.box(2, sy - 1, z, sx - 3, sy - 1, z, "")
	b.box(0, sy - 2, 0, 1, sy - 1, sz - 1, "wood_dark")
	b.box(sx - 2, sy - 2, 0, sx - 1, sy - 1, sz - 1, "wood_dark")
	# Pieds en X à chaque extrémité.
	for x in [3, sx - 5]:
		b.line(Vector3(x + 0.5, 0.5, 1.5), Vector3(x + 0.5, sy - 2.5, sz - 2.5), 2, "wood_dark")
		b.line(Vector3(x + 0.5, 0.5, sz - 2.5), Vector3(x + 0.5, sy - 2.5, 1.5), 2, "wood_dark")
	# Traverse et chevilles en laiton.
	b.box(3, 6, sz / 2 - 1, sx - 4, 7, sz / 2, "wood_dark")
	b.box(3, 6, sz / 2 - 1, 4, 7, sz / 2, "brass")
	b.box(sx - 5, 6, sz / 2 - 1, sx - 4, 7, sz / 2, "brass")
	return _model("table", VoxelGrid.LEGACY_DETAIL_SIZE, b)

## Établi : 1,60 × 0,80 m, plan de travail à 0,90 m, râtelier à outils et étau.
static func _workbench() -> Dictionary:
	var sx := 8 * D
	var sz := 4 * D
	var top_y := 18  # 0,90 m
	var b := VoxelModelBuilder.new(Vector3i(sx, 7 * D, sz))
	# Pieds massifs + entretoises.
	for p in [Vector2i(1, 1), Vector2i(sx - 4, 1), Vector2i(1, sz - 4), Vector2i(sx - 4, sz - 4)]:
		b.box(p.x, 0, p.y, p.x + 2, top_y - 4, p.y + 2, "wood_dark")
	b.box(1, 3, 2, sx - 2, 4, sz - 3, "wood_planks")      # étagère basse
	b.box(1, top_y - 5, 1, sx - 2, top_y - 4, 2, "wood_dark")  # ceinture avant
	# Plateau épais (3 cellules) avec chants sombres.
	b.box(0, top_y - 3, 0, sx - 1, top_y - 1, sz - 1, "wood_planks")
	b.box(0, top_y - 3, 0, sx - 1, top_y - 3, sz - 1, "wood_dark")
	# Étau en fer sur l'avant gauche, poignée laiton.
	b.box(2, top_y - 6, 0, 6, top_y, 1, "iron")
	b.box(3, top_y - 5, 0, 5, top_y - 5, 0, "brass")
	# Râtelier arrière : deux montants, une barre, outils suspendus.
	b.box(1, top_y, sz - 2, 2, 6 * D + 2, sz - 1, "wood_dark")
	b.box(sx - 3, top_y, sz - 2, sx - 2, 6 * D + 2, sz - 1, "wood_dark")
	b.box(1, 6 * D, sz - 2, sx - 2, 6 * D + 1, sz - 1, "wood_dark")
	# Marteau.
	b.box(6, top_y + 4, sz - 2, 6, 6 * D - 1, sz - 2, "wood_planks")
	b.box(4, top_y + 4, sz - 2, 8, top_y + 5, sz - 2, "iron")
	# Scie (lame + poignée).
	b.box(12, top_y + 2, sz - 2, 15, 6 * D - 1, sz - 2, "iron")
	b.box(12, 6 * D - 3, sz - 2, 15, 6 * D - 1, sz - 2, "wood_dark")
	# Pinces / compas en laiton.
	b.line(Vector3(20.5, 6 * D - 0.5, sz - 1.5), Vector3(19.5, top_y + 6.5, sz - 1.5), 1, "brass")
	b.line(Vector3(20.5, 6 * D - 0.5, sz - 1.5), Vector3(22.5, top_y + 6.5, sz - 1.5), 1, "brass")
	# Sur le plan : un éclat brut et une planchette.
	b.box(22, top_y, 4, 24, top_y + 1, 6, "stone_dark")
	b.box(23, top_y + 2, 5, 23, top_y + 4, 5, "crystal")
	b.box(10, top_y, 3, 17, top_y, 7, "wood_planks")
	# Caisse sur l'étagère basse.
	b.box(sx - 12, 5, 4, sx - 6, 9, 10, "wood_dark")
	b.box(sx - 11, 9, 5, sx - 7, 9, 9, "wood_planks")
	return _model("workbench", VoxelGrid.LEGACY_DETAIL_SIZE, b)

## Lampe à éclat : un cristal flotte dans une coupe de laiton au sommet d'une tige
## de bois cintrée. Emprise 0,40 × 0,40 m, hauteur 1,80 m.
static func _shard_lamp() -> Dictionary:
	var s := 2 * D
	var h := 9 * D
	var b := VoxelModelBuilder.new(Vector3i(s, h, s))
	var c := s / 2.0
	# Socle en pierre arrondi, anneau de laiton.
	b.ellipsoid(Vector3(c, 0.0, c), Vector3(4.0, 3.0, 4.0), "stone_brick")
	b.box(1, 1, 1, s - 2, 1, s - 2, "brass")
	b.ellipsoid(Vector3(c, 0.0, c), Vector3(3.2, 2.9, 3.2), "stone_brick")
	# Tige cintrée (léger S).
	var prev := Vector3(c - 0.5, 2.5, c - 0.5)
	for i in range(1, 9):
		var y := 2.5 + i * 2.6
		var p := Vector3(c - 0.5 + sin(i * 0.7) * 1.6, y, c - 0.5 + cos(i * 0.5) * 0.8 - 0.8)
		b.line(prev, p, 2, "wood_dark")
		prev = p
	var cup_y := int(prev.y) + 1
	# Coupe ouverte : quatre griffes de laiton qui remontent.
	b.box(1, cup_y, 1, s - 2, cup_y, s - 2, "brass")
	b.box(3, cup_y, 3, 4, cup_y, 4, "")
	for corner in [Vector2i(0, 0), Vector2i(s - 1, 0), Vector2i(0, s - 1), Vector2i(s - 1, s - 1)]:
		b.box(corner.x, cup_y + 1, corner.y, corner.x, cup_y + 4, corner.y, "brass")
	# Éclat suspendu (sans contact) : losange vertical.
	var shard_base := cup_y + 3
	b.box(3, shard_base, 3, 4, shard_base + 5, 4, "crystal_warm")
	b.box(3, shard_base + 6, 3, 3, shard_base + 7, 3, "crystal_warm")
	b.box(4, shard_base + 1, 4, 4, shard_base + 1, 5, "crystal_warm")
	b.box(2, shard_base + 3, 3, 2, shard_base + 3, 3, "crystal_warm")
	var model := _model("shard_lamp", VoxelGrid.LEGACY_DETAIL_SIZE, b)
	model["light"] = {
		"position": Vector3(4.0, shard_base + 3.5, 4.0) * VoxelGrid.LEGACY_DETAIL_SIZE,
		"color": Color("ffc97a"), "energy": 1.6, "range": 7.0,
	}
	return model
