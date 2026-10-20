@tool
extends Node3D
## Laboratoire graphique : salle neutre pour comparer tailles, matières et objets.
## Tout le contenu est généré au chargement (visible aussi dans l'éditeur).
## Disposition (vue depuis l'entrée, caméra au sud) :
##   fond      : échantillons de toutes les matières de la palette (cubes de 0,60 m)
##   centre    : les 10 objets de référence, avec nom et dimensions
##   gauche    : test de raccord terrain / blocs posés
##   droite    : repères d'échelle (mire 2 m, silhouette 1,80 m)

const V := VoxelGrid.VOXEL_SIZE
const ROOM_SIZE := Vector3(30.0, 6.0, 20.0)
const LABEL_COLOR := Color(0.12, 0.12, 0.14)

func _ready() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			child.queue_free()
	_build_room()
	_build_material_samples()
	_build_object_row()
	_build_seam_test()
	_build_scale_refs()
	if not Engine.is_editor_hint():
		App.set_scene_help("Laboratoire : comparer tailles, matières et objets.")

func _add(node: Node3D, pos := Vector3.ZERO) -> Node3D:
	node.set_meta("generated", true)
	node.position = pos
	add_child(node)
	return node

func _label(text: String, pos: Vector3, size := 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = LABEL_COLOR
	l.outline_size = 10
	l.outline_modulate = Color(1, 1, 1, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = true
	_add(l, pos)

func _box(size: Vector3, pos: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mi.mesh = mesh
	_add(mi, pos)

func _build_room() -> void:
	var grid_mat: Material = load("res://materials/lab_floor_material.tres")
	var hx := ROOM_SIZE.x * 0.5
	var hz := ROOM_SIZE.z * 0.5
	_box(Vector3(ROOM_SIZE.x, 0.2, ROOM_SIZE.z), Vector3(0, -0.1, 0), grid_mat)
	_box(Vector3(ROOM_SIZE.x, ROOM_SIZE.y, 0.4), Vector3(0, ROOM_SIZE.y * 0.5, -hz - 0.2), grid_mat)
	_box(Vector3(0.4, ROOM_SIZE.y, ROOM_SIZE.z), Vector3(-hx - 0.2, ROOM_SIZE.y * 0.5, 0), grid_mat)
	_box(Vector3(0.4, ROOM_SIZE.y, ROOM_SIZE.z), Vector3(hx + 0.2, ROOM_SIZE.y * 0.5, 0), grid_mat)

## Une rangée de cubes de 3×3×3 voxels (0,60 m), un par matière de la palette.
func _build_material_samples() -> void:
	var pal := VoxelPalette.get_default()
	var n := pal.count() - 1
	for id in range(1, pal.count()):
		var i := id - 1
		var pos := Vector3(snappedf((i - n * 0.5) * 1.2, V), 0.0, -8.4)
		var vol := VoxelVolume.new(Vector3i(3, 3, 3))
		vol.fill_box(Vector3i.ZERO, Vector3i(2, 2, 2), id)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMesher.build(vol, V, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), VoxelGrid.world_to_cell(pos))
		_add(mi, pos)
		_label(pal.names[id], pos + Vector3(0.3, 0.85 + (i % 2) * 0.35, 0.3), 44)

## Les 10 objets de référence alignés sur la grille.
func _build_object_row() -> void:
	var layout := [
		["block_stone", Vector3(-8.0, 0, 0.0)],
		["block_dirt", Vector3(-7.0, 0, 0.0)],
		["block_grass", Vector3(-6.0, 0, 0.0)],
		["block_wood", Vector3(-5.0, 0, 0.0)],
		["wall", Vector3(-3.4, 0, -0.2)],
		["slab", Vector3(-1.6, 0, -0.6)],
		["stairs", Vector3(0.4, 0, -1.2)],
		["table", Vector3(2.4, 0, -0.6)],
		["workbench", Vector3(4.8, 0, -0.6)],
		["shard_lamp", Vector3(7.4, 0, -0.4)],
	]
	for entry in layout:
		var inst := VoxelModelInstance.new()
		inst.model_key = entry[0]
		_add(inst, entry[1])
		var model := VoxelModelLibrary.get_model(entry[0])
		var size: Vector3 = model["size_m"]
		if String(entry[0]).begins_with("block_"):
			_label(model["name"], entry[1] + Vector3(0.1, 0.4, 0.1), 30)
			continue
		var top := size.y + 0.35
		var text := "%s\n%s × %s × %s m" % [model["name"], _m(size.x), _m(size.y), _m(size.z)]
		_label(text, entry[1] + Vector3(size.x * 0.5, top, size.z * 0.5), 36)
	_label("Blocs constructibles : 1 voxel = 0,20 m", Vector3(-6.4, 0.75, 0.1), 36)

func _m(v: float) -> String:
	return ("%.2f" % v).replace(".", ",")

## Bande de terrain voxel (même code que l'île) avec blocs posés dessus et à côté :
## aucune différence de teinte, de taille ou d'alignement ne doit être visible.
func _build_seam_test() -> void:
	var origin := Vector3(-13.0, 0.0, 1.0)
	var size := Vector3i(15, 4, 15)
	var vol := VoxelVolume.new(size)
	var pal := VoxelPalette.get_default()
	vol.fill_box(Vector3i(0, 0, 0), Vector3i(14, 1, 14), pal.id("stone"))
	vol.fill_box(Vector3i(0, 2, 0), Vector3i(14, 2, 14), pal.id("dirt"))
	vol.fill_box(Vector3i(0, 3, 0), Vector3i(14, 3, 14), pal.id("grass"))
	vol.fill_box(Vector3i(8, 3, 0), Vector3i(14, 3, 6), 0)    # un creux pour poser des blocs
	vol.fill_box(Vector3i(8, 3, 0), Vector3i(14, 3, 6), 0)
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMesher.build(vol, V, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), VoxelGrid.world_to_cell(origin))
	_add(mi, origin)
	# Blocs posés : comblent une partie du creux et s'empilent sur l'herbe.
	var placed := [
		["block_grass", Vector3i(8, 3, 0)], ["block_grass", Vector3i(9, 3, 0)], ["block_grass", Vector3i(8, 3, 1)],
		["block_dirt", Vector3i(10, 3, 0)], ["block_stone", Vector3i(11, 3, 0)], ["block_wood", Vector3i(12, 3, 0)],
		["block_stone", Vector3i(3, 4, 3)], ["block_stone", Vector3i(4, 4, 3)], ["block_wood", Vector3i(3, 5, 3)],
		["block_grass", Vector3i(5, 4, 9)],
	]
	for p in placed:
		var inst := VoxelModelInstance.new()
		inst.model_key = p[0]
		_add(inst, origin + Vector3(p[1]) * V)
	var wall := VoxelModelInstance.new()
	wall.model_key = "wall"
	_add(wall, origin + Vector3(0.2, 0.8, 2.6))
	var slab := VoxelModelInstance.new()
	slab.model_key = "slab"
	_add(slab, origin + Vector3(1.6, 0.8, 1.4))
	_label("Raccord terrain / blocs posés\n(même grille, même palette)", origin + Vector3(1.5, 3.4, 1.5), 28)

func _build_scale_refs() -> void:
	# Mire de 2 m : alternance tous les 0,20 m, repères à 1 m et 2 m.
	var origin := Vector3(10.6, 0.0, 2.0)
	var pal := VoxelPalette.get_default()
	var vol := VoxelVolume.new(Vector3i(1, 10, 1))
	for y in 10:
		vol.set_voxel(0, y, 0, pal.id("wood_dark") if y % 2 == 0 else pal.id("mortar"))
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMesher.build(vol, V)
	_add(mi, origin)
	_label("1 m", origin + Vector3(-0.35, 1.0, 0.1), 32)
	_label("2 m", origin + Vector3(-0.35, 2.0, 0.1), 32)
	# Silhouette de 1,80 m en voxels de détail (0,05 m).
	var b := VoxelModelBuilder.new(Vector3i(10, 36, 6))
	b.box(1, 0, 1, 3, 15, 4, "iron")          # jambes
	b.box(6, 0, 1, 8, 15, 4, "iron")
	b.box(1, 16, 0, 8, 28, 5, "iron")         # torse
	b.box(0, 17, 1, 0, 27, 4, "iron")         # bras
	b.box(9, 17, 1, 9, 27, 4, "iron")
	b.box(3, 29, 1, 6, 35, 4, "stone")        # tête
	var sil := MeshInstance3D.new()
	sil.mesh = VoxelMesher.build(b.volume, VoxelGrid.DETAIL_SIZE)
	_add(sil, origin + Vector3(1.0, 0, 0))
	_label("Repère 1,80 m", origin + Vector3(1.25, 2.3, 0.15), 36)
