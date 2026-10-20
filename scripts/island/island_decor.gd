@tool
class_name IslandDecor
extends Node3D
## Pose la végétation sur une VoxelIsland (arbres + plantes basses), de façon déterministe.
## Les plantes basses sont dessinées en MultiMesh (un seul appel de rendu par espèce).

@export var island_path: NodePath
@export var tree_count := 9
@export var plant_count := 700
## Distance minimale entre deux arbres (m).
@export var tree_spacing_m := 4.5

const PLANTS := ["tuft", "tuft", "tuft", "fern", "flower_yellow", "flower_violet"]

func _ready() -> void:
	var island := get_node_or_null(island_path) as VoxelIsland
	if island == null:
		return
	island.generated.connect(_on_generated.bind(island))
	if island.data != null:
		_on_generated(island.data, island)

func _on_generated(data: IslandData, island: VoxelIsland) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed * 977 + 13
	var pal := VoxelPalette.get_default()
	var grass_ids := [pal.id("grass"), pal.id("grass_lush"), pal.id("grass_dry")]
	var sx := data.size().x
	var sz := data.size().z
	# Colonnes candidates : herbe, terrain plat autour (3×3).
	var candidates: Array[Vector2i] = []
	for z in range(1, sz - 1):
		for x in range(1, sx - 1):
			if not grass_ids.has(data.top_material[x + z * sx]):
				continue
			var t := data.column_top(x, z)
			var flat := true
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if data.column_top(x + o.x, z + o.y) != t:
					flat = false
					break
			if flat:
				candidates.append(Vector2i(x, z))
	if candidates.is_empty():
		return
	_place_trees(data, island, rng, candidates)
	_place_plants(data, island, rng, candidates)

func _place_trees(data: IslandData, island: VoxelIsland, rng: RandomNumberGenerator, candidates: Array[Vector2i]) -> void:
	var placed: Array[Vector2i] = []
	var spacing := tree_spacing_m / VoxelGrid.VOXEL_SIZE
	var center := Vector2(data.size().x, data.size().z) * 0.5
	var attempts := 0
	while placed.size() < tree_count and attempts < 400:
		attempts += 1
		var c := candidates[rng.randi() % candidates.size()]
		# Pas trop près du bord (les couronnes débordent) ni des autres arbres.
		if Vector2(c).distance_to(center) > center.x * 0.62:
			continue
		var ok := true
		for p in placed:
			if Vector2(p).distance_to(Vector2(c)) < spacing:
				ok = false
				break
		if not ok:
			continue
		placed.append(c)
		var vol := VegetationLibrary.build_tree(data.seed * 131 + placed.size())
		var mi := MeshInstance3D.new()
		mi.name = "Tree_%d" % placed.size()
		mi.mesh = VoxelMesher.build(vol, VoxelGrid.VOXEL_SIZE)
		var half := vol.size.x / 2
		# Base du tronc sur la cellule (c.x, c.y), au ras du sol.
		# (enfoncée d'un voxel pour ancrer les racines).
		mi.position = to_local(island.column_surface_position(c.x, c.y)) \
				- Vector3(half, 1, half) * VoxelGrid.VOXEL_SIZE
		add_child(mi)

func _place_plants(data: IslandData, island: VoxelIsland, rng: RandomNumberGenerator, candidates: Array[Vector2i]) -> void:
	var transforms := {}
	for kind in PLANTS:
		transforms[kind] = []
	var used := {}
	for i in plant_count:
		var c := candidates[rng.randi() % candidates.size()]
		if used.has(c):
			continue
		used[c] = true
		var kind: String = PLANTS[rng.randi() % PLANTS.size()]
		var base := to_local(island.column_surface_position(c.x, c.y))
		var half := Vector3(0.1, 0, 0.1)
		var rot := Basis(Vector3.UP, (rng.randi() % 4) * PI * 0.5)
		transforms[kind].append(Transform3D(rot, base + half - rot * half))
	for kind in transforms:
		var list: Array = transforms[kind]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = VoxelMesher.build(VegetationLibrary.build_plant(kind), VoxelGrid.DETAIL_SIZE)
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Plants_%s" % kind
		mmi.multimesh = mm
		add_child(mmi)
