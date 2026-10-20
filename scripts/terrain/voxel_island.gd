@tool
class_name VoxelIsland
extends Node3D
## Nœud d'une île voxel : génère les données (IslandGenerator) puis les maille par chunks.
## Chaque chunk = 1 MeshInstance3D pour le cœur + 1 pour la surface (aucun nœud par cube).

signal generated(data: IslandData)

## Taille d'un chunk en voxels (32 × 0,20 m = 6,4 m). Plus grand = moins d'appels de dessin.
const CHUNK := 32
@export var chunk_size := 32

@export var seed := 1234:
	set(v):
		seed = v
		_queue_regen()
@export var radius_m := 15.0:
	set(v):
		radius_m = v
		_queue_regen()
@export var underside_depth_m := 14.0:
	set(v):
		underside_depth_m = v
		_queue_regen()
@export var hill_height_m := 3.2:
	set(v):
		hill_height_m = v
		_queue_regen()
## Rendu du terrain : STYLIZED (Lot 2) ou LEGACY (Lot 1, pour comparaison).
@export var render_style: VoxelMesher.Style = VoxelMesher.Style.STYLIZED:
	set(v):
		render_style = v
		if is_inside_tree() and data != null:
			_rebuild_meshes()
## Profil de génération optionnel : objet avec height(x, z, h, r) et surface(x, z, h, r, slope)
## (voir VillageLayout). Doit être renseigné avant d'entrer dans l'arbre.
var layout: RefCounted
## Générer aussi dans l'éditeur (aperçu). Peut prendre quelques secondes.
@export var preview_in_editor := true

var data: IslandData
var last_generation_ms := 0
var surface_visible := true:
	set(v):
		surface_visible = v
		if _surface_root:
			_surface_root.visible = v

var _core_root: Node3D
var _surface_root: Node3D
var _regen_queued := false

func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	regenerate()

func _queue_regen() -> void:
	if not is_inside_tree() or _regen_queued:
		return
	_regen_queued = true
	regenerate.call_deferred()

func regenerate() -> void:
	_regen_queued = false
	var t0 := Time.get_ticks_msec()
	var gen := IslandGenerator.new()
	gen.seed = seed
	gen.radius_m = radius_m
	gen.underside_depth_m = underside_depth_m
	gen.hill_height_m = hill_height_m
	if layout != null:
		gen.height_hook = Callable(layout, "height")
		gen.surface_hook = Callable(layout, "surface")
		gen.use_terrace = false
		gen.base_height_m = layout.get("base_height_m") if layout.get("base_height_m") != null else gen.base_height_m
	data = gen.generate()
	_rebuild_meshes()
	last_generation_ms = Time.get_ticks_msec() - t0
	generated.emit(data)

func _rebuild_meshes() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.queue_free()
	_core_root = _make_root("Core")
	_surface_root = _make_root("Surface")
	_surface_root.visible = surface_visible
	var size := data.size()
	var origin := VoxelGrid.cell_to_world(data.origin_cell)
	# Liste des tâches : (couche, région). Les maillages sont calculés en parallèle.
	var jobs := []
	for cy in range(0, size.y, chunk_size):
		for cz in range(0, size.z, chunk_size):
			for cx in range(0, size.x, chunk_size):
				var rmin := Vector3i(cx, cy, cz)
				var rmax := Vector3i(mini(cx + chunk_size, size.x), mini(cy + chunk_size, size.y), mini(cz + chunk_size, size.z)) - Vector3i.ONE
				jobs.append([_core_root, data.core, rmin, rmax])
				jobs.append([_surface_root, data.surface, rmin, rmax])
	var style := render_style
	var results := []
	results.resize(jobs.size())
	VoxelMesher.palette_warmup()
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var j: Array = jobs[i]
		results[i] = VoxelMesher.build_arrays(j[1], VoxelGrid.VOXEL_SIZE, j[2], j[3], data.solid, data.origin_cell, 0, style),
		jobs.size(), -1, true, "VoxelIsland meshing")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i in jobs.size():
		var mesh := VoxelMesher.arrays_to_mesh(results[i], style)
		if mesh == null:
			continue
		var rmin: Vector3i = jobs[i][2]
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d_%d" % [rmin.x / chunk_size, rmin.y / chunk_size, rmin.z / chunk_size]
		mi.mesh = mesh
		mi.position = origin
		(jobs[i][0] as Node3D).add_child(mi)

func _make_root(root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	root.set_meta("generated", true)
	add_child(root)
	return root

## Position monde (m) du sol au-dessus de la colonne (x, z) des volumes.
func column_surface_position(x: int, z: int) -> Vector3:
	var t := data.column_top(x, z)
	return to_global(VoxelGrid.cell_to_world(data.origin_cell + Vector3i(x, t + 1, z)))

func count_faces() -> int:
	var total := 0
	for root in [_core_root, _surface_root]:
		if root == null:
			continue
		for mi in root.get_children():
			total += (mi as MeshInstance3D).mesh.surface_get_array_len(0) / 4
	return total

func count_triangles() -> int:
	var total := 0
	for root in [_core_root, _surface_root]:
		if root == null:
			continue
		for mi in root.get_children():
			total += VoxelMesher.triangle_count((mi as MeshInstance3D).mesh)
	return total

## Hauteur (m) du sol au point (x, z) du repère du nœud (valeur de la colonne de 20 cm).
func surface_y_at(x: float, z: float) -> float:
	var cell := VoxelGrid.world_to_cell(Vector3(x, 0, z))
	var col := cell - Vector3i(data.origin_cell.x, 0, data.origin_cell.z)
	var t := data.column_top(col.x, col.z)
	if t < 0:
		return NAN
	return float(data.origin_cell.y + t + 1) * VoxelGrid.VOXEL_SIZE
