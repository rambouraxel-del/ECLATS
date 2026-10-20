@tool
class_name VegetationLibrary
extends RefCounted
## Végétation procédurale (déterministe) : arbres sur la grille du terrain (0,20 m),
## plantes basses en voxels de détail (0,05 m).

## Arbre « parasol » : tronc incliné, racines apparentes, couronnes de feuillage aplaties.
## Renvoie un VoxelVolume en voxels de 0,20 m ; la base du tronc est en (c, 0, c).
static func build_tree(seed: int) -> VoxelVolume:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var size := 26
	var b := VoxelModelBuilder.new(Vector3i(size, 32, size))
	var c := size / 2
	var height := rng.randi_range(10, 15)
	var lean := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(1.0, 3.0)
	var blossom := rng.randf() < 0.35
	# Racines qui s'étalent au pied.
	for i in 5:
		var a := TAU * i / 5.0 + rng.randf_range(-0.3, 0.3)
		var l := rng.randf_range(2.0, 3.5)
		b.line(Vector3(c + 0.5, 1.0, c + 0.5), Vector3(c + 0.5 + cos(a) * l, 0.2, c + 0.5 + sin(a) * l), 1, "root")
	# Tronc 2×2 qui s'incline progressivement.
	var top := Vector3.ZERO
	for y in height:
		var t := float(y) / height
		var off := lean * t * t
		var p := Vector3(c + off.x, y, c + off.y)
		b.box(int(p.x), y, int(p.z), int(p.x) + 1, y, int(p.z) + 1, "bark")
		top = p
	# Branches et couronnes.
	var crowns := rng.randi_range(3, 4)
	for i in crowns:
		var a := TAU * i / crowns + rng.randf_range(-0.5, 0.5)
		var reach := rng.randf_range(2.5, 4.0)
		var start := Vector3(top.x + 1.0, top.y - rng.randf_range(1.0, 4.0), top.z + 1.0)
		var end := start + Vector3(cos(a) * reach, rng.randf_range(2.0, 3.5), sin(a) * reach)
		b.line(start, end, 1, "bark")
		b.ellipsoid(end + Vector3(0, 1.0, 0), Vector3(rng.randf_range(3.8, 5.0), rng.randf_range(2.4, 3.2), rng.randf_range(3.8, 5.0)), "leaves", true)
	b.ellipsoid(top + Vector3(1.0, 2.5, 1.0), Vector3(5.0, 3.4, 5.0), "leaves", true)
	# Touffes plus claires sur le dessus de la couronne.
	b.speckle("leaves", "leaf_light", 0.12, seed + 1)
	if blossom:
		b.speckle("leaves", "blossom", 0.22, seed)
	return b.volume

## Plantes basses en microvoxels de 2 cm. Emprise d'une cellule de terrain
## (10 × 10 microvoxels = 20 × 20 cm), base au sol en y = 0.
static func build_plant(kind: String) -> VoxelVolume:
	var b: VoxelModelBuilder
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"tuft":
			# Touffe d'herbe : brins fins de hauteurs variées qui s'écartent du centre.
			b = VoxelModelBuilder.new(Vector3i(10, 16, 10))
			for i in 6:
				var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
				var h := rng.randf_range(6.0, 14.5)
				var lean := rng.randf_range(1.0, 3.5)
				var key := "leaf_light" if i % 3 == 0 else ("ivy" if i % 3 == 1 else "leaves")
				b.line(Vector3(5 + cos(a), 0.5, 5 + sin(a)), Vector3(5 + cos(a) * lean, h, 5 + sin(a) * lean), 1, key)
		"flower_yellow", "flower_violet", "flower_white":
			b = VoxelModelBuilder.new(Vector3i(10, 18, 10))
			b.line(Vector3(5, 0.5, 5), Vector3(5.5, 13, 4.5), 1, "ivy")
			b.line(Vector3(5, 3, 5), Vector3(2, 6, 6), 1, "leaf_light")
			b.line(Vector3(5, 5, 5), Vector3(8, 8, 3), 1, "leaf_light")
			# Corolle en croix de 5 pétales autour d'un cœur.
			var cy := 14
			for o in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
				b.set_cell(5 + o.x * 1, cy + o.y, 4 + o.z * 1, kind)
				b.set_cell(5 + o.x * 2, cy, 4 + o.z * 2, kind)
			b.set_cell(5, cy, 4, "flower_yellow" if kind != "flower_yellow" else "wood_honey")
		"fern":
			# Fougère : frondes arquées.
			b = VoxelModelBuilder.new(Vector3i(10, 10, 10))
			for i in 6:
				var a := TAU * i / 6.0 + 0.3
				var p0 := Vector3(5, 0.5, 5)
				var p1 := Vector3(5 + cos(a) * 2.5, 7, 5 + sin(a) * 2.5)
				var p2 := Vector3(5 + cos(a) * 4.6, 3, 5 + sin(a) * 4.6)
				b.line(p0, p1, 1, "leaves")
				b.line(p1, p2, 1, "leaf_light" if i % 2 == 0 else "leaves")
		"clover":
			b = VoxelModelBuilder.new(Vector3i(10, 4, 10))
			for c in [Vector2i(2, 3), Vector2i(6, 2), Vector2i(4, 6), Vector2i(7, 7)]:
				b.box(c.x, 1, c.y, c.x + 1, 1, c.y + 1, "ivy")
				b.set_cell(c.x, 0, c.y, "leaves")
			b.set_cell(4, 2, 6, "flower_white")
		_:
			b = VoxelModelBuilder.new(Vector3i(10, 4, 10))
	return b.volume
