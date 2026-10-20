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
	b.speckle("leaves", "grass_lush", 0.12, seed + 1)
	if blossom:
		b.speckle("leaves", "blossom", 0.22, seed)
	return b.volume

## Plantes basses (0,05 m). Emprise d'une cellule de terrain (4 × 4 cellules de détail).
static func build_plant(kind: String) -> VoxelVolume:
	var b: VoxelModelBuilder
	match kind:
		"tuft":
			b = VoxelModelBuilder.new(Vector3i(4, 6, 4))
			b.box(0, 0, 1, 0, 2, 1, "grass_lush")
			b.box(1, 0, 3, 1, 4, 3, "grass")
			b.box(2, 0, 0, 2, 3, 0, "grass_lush")
			b.box(3, 0, 2, 3, 5, 2, "grass")
			b.box(1, 0, 1, 2, 1, 2, "grass_lush")
		"flower_yellow", "flower_violet":
			b = VoxelModelBuilder.new(Vector3i(4, 8, 4))
			b.box(1, 0, 1, 1, 5, 1, "grass_lush")
			b.box(2, 0, 2, 2, 1, 3, "grass")
			b.box(0, 2, 1, 0, 2, 1, "grass")
			b.box(0, 6, 0, 2, 6, 2, kind)
			b.box(1, 7, 1, 1, 7, 1, kind)
			b.set_cell(1, 6, 1, "flower_yellow" if kind == "flower_violet" else "dirt")
		"fern":
			b = VoxelModelBuilder.new(Vector3i(4, 5, 4))
			b.ellipsoid(Vector3(2, 1, 2), Vector3(2.2, 2.6, 2.2), "leaves")
			b.speckle("leaves", "grass_lush", 0.3, 3)
		_:
			b = VoxelModelBuilder.new(Vector3i(4, 4, 4))
	return b.volume
