@tool
extends Node3D
## Laboratoire graphique : salle neutre pour comparer tailles, matières et objets.
## Tout le contenu est généré au chargement (visible aussi dans l'éditeur).
## Disposition (du fond vers l'entrée, caméra au sud) :
##   Zone Lot 1 (z < 6)   : échantillons des matières, 10 objets de référence,
##                          raccord terrain / blocs posés, repères d'échelle.
##   Zone Lot 2 (z > 8)   : les 5 assets détaillés sur socles neutres (nom, dimensions,
##                          triangles), diorama des assets posés sur un terrain voxel,
##                          comparaison du terrain « Lot 1 / Lot 2 » (mêmes voxels).
## Touches 1 à 9 : vues prédéfinies (voir VIEWS).

const V := VoxelGrid.VOXEL_SIZE
const ROOM_MIN := Vector3(-20.0, 0.0, -10.0)
const ROOM_MAX := Vector3(20.0, 7.0, 42.0)
## Socles de présentation : centre (x, z) en mètres.
const SHOWCASE_Z := 11.6
const SHOWCASE_GAP := 1.4
const DIORAMA_ORIGIN := Vector3(-9.0, 0.0, 17.6)
const COMPARE_Z := 30.0
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
	_build_asset_showcase()
	_build_diorama()
	_build_terrain_comparison()
	if not Engine.is_editor_hint():
		App.set_scene_help("Laboratoire · vues : 1 Lot 1 · 2 assets · 3-7 gros plans · 8 diorama · 9 terrain Lot 1 / Lot 2")
		_go_to_view(2)

func _add(node: Node3D, pos := Vector3.ZERO) -> Node3D:
	node.set_meta("generated", true)
	node.position = pos
	add_child(node)
	return node

func _label(text: String, pos: Vector3, size := 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.003
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
	var size := ROOM_MAX - ROOM_MIN
	var c := (ROOM_MAX + ROOM_MIN) * 0.5
	_box(Vector3(size.x, 0.2, size.z), Vector3(c.x, -0.1, c.z), grid_mat)
	_box(Vector3(size.x, size.y, 0.4), Vector3(c.x, size.y * 0.5, ROOM_MIN.z - 0.2), grid_mat)
	_box(Vector3(0.4, size.y, size.z), Vector3(ROOM_MIN.x - 0.2, size.y * 0.5, c.z), grid_mat)
	_box(Vector3(0.4, size.y, size.z), Vector3(ROOM_MAX.x + 0.2, size.y * 0.5, c.z), grid_mat)

## Une rangée de cubes de 3×3×3 voxels (0,60 m), un par matière de la palette.
func _build_material_samples() -> void:
	var pal := VoxelPalette.get_default()
	var per_row := 25
	for id in range(1, pal.count()):
		var i := id - 1
		var pos := Vector3(snappedf((i % per_row - per_row / 2) * 1.2, V), 0.0, -8.8 + (i / per_row) * 2.0)
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
	# Silhouette de 1,80 m en voxels de 5 cm.
	var b := VoxelModelBuilder.new(Vector3i(10, 36, 6))
	b.box(1, 0, 1, 3, 15, 4, "iron")          # jambes
	b.box(6, 0, 1, 8, 15, 4, "iron")
	b.box(1, 16, 0, 8, 28, 5, "iron")         # torse
	b.box(0, 17, 1, 0, 27, 4, "iron")         # bras
	b.box(9, 17, 1, 9, 27, 4, "iron")
	b.box(3, 29, 1, 6, 35, 4, "stone")        # tête
	var sil := MeshInstance3D.new()
	sil.mesh = VoxelMesher.build(b.volume, VoxelGrid.LEGACY_DETAIL_SIZE)
	_add(sil, origin + Vector3(1.0, 0, 0))
	_label("Repère 1,80 m", origin + Vector3(1.25, 2.3, 0.15), 36)

# ------------------------------------------------------------------ Lot 2 : assets

var _showcase := []  # [id, centre (Vector3), taille (Vector3)]

## Les 5 assets détaillés sur des socles neutres, avec nom, dimensions et triangles.
func _build_asset_showcase() -> void:
	var plinth_mat := StandardMaterial3D.new()
	plinth_mat.albedo_color = Color(0.78, 0.77, 0.75)
	plinth_mat.roughness = 0.9
	var widths := []
	var total := 0.0
	for id in AssetLibrary.ids():
		var inst := AssetLibrary.instantiate(id)
		if inst == null:
			push_warning("Asset non généré : %s (lancer tools/bake_assets.gd)" % id)
			continue
		var size: Vector3 = (inst as PlaceableAsset).footprint_size_m()
		widths.append([id, inst, size])
		total += size.x + 0.8
	total += SHOWCASE_GAP * (widths.size() - 1)
	var x := -total * 0.5
	for entry in widths:
		var inst: Node3D = entry[1]
		var size: Vector3 = entry[2]
		var pw := size.x + 0.8
		var pd := size.z + 0.8
		var center := Vector3(snappedf(x + pw * 0.5, V), 0, SHOWCASE_Z)
		_box(Vector3(pw, 0.2, pd), center + Vector3(0, 0.1, 0), plinth_mat)
		var origin := Vector3(snappedf(center.x - size.x * 0.5, V), 0.2, snappedf(center.z - size.z * 0.5, V))
		_add(inst, origin)
		var asset := inst as PlaceableAsset
		var label := "%s\n%s × %s m · hauteur %s m\n%d triangles" % [asset.display_name, _m(size.x), _m(size.z), _m(size.y), asset.triangle_count]
		_label(label, center + Vector3(0, size.y + 0.75, pd * 0.5 - 0.2), 34)
		# Lumière d'appoint douce, de face, pour la présentation.
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.93, 0.84)
		fill.light_energy = 0.45
		fill.omni_range = 5.0
		_add(fill, center + Vector3(0.6, 2.4, 2.2))
		_showcase.append([entry[0], origin + size * Vector3(0.5, 0.45, 0.5), size])
		x += pw + SHOWCASE_GAP

## Diorama : les 5 assets posés sur un terrain voxel (rendu Lot 2) avec végétation.
func _build_diorama() -> void:
	# Zones aplanies (cellules de 20 cm) et position de chaque asset dans le diorama.
	var spots := {
		"market_stall": Vector2i(5, 27), "anchor_pedestal": Vector2i(23, 7),
		"artisan_workbench": Vector2i(39, 29), "ancient_chest": Vector2i(57, 11),
		"decorative_bench": Vector2i(71, 31),
	}
	var flats: Array[Rect2i] = []
	var placed := []
	for id in spots:
		var inst := AssetLibrary.instantiate(id)
		if inst == null:
			continue
		var fp := (inst as PlaceableAsset).footprint_cells
		var c: Vector2i = spots[id]
		flats.append(Rect2i(c.x - 1, c.y - 1, fp.x + 2, fp.z + 2))
		placed.append([inst, c])
	var flat_h := 4
	var vol := TerrainPatch.generate(90, 45, 77, 3, 4, flats, flat_h)
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMesher.build(vol, V)
	_add(mi, DIORAMA_ORIGIN)
	for p in placed:
		var c: Vector2i = p[1]
		_add(p[0], DIORAMA_ORIGIN + Vector3(c.x, flat_h, c.y) * V)
	# Végétation basse hors des zones aplanies.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var plants := ["tuft", "tuft", "clover", "fern", "flower_white", "flower_yellow", "flower_violet"]
	var lists := {}
	for i in 900:
		var x := rng.randi_range(1, 88)
		var z := rng.randi_range(1, 43)
		var inside := false
		for r in flats:
			if r.grow(1).has_point(Vector2i(x, z)):
				inside = true
		if inside:
			continue
		var kind: String = plants[rng.randi() % plants.size()]
		var h := TerrainPatch.surface_height(vol, x, z)
		var rot := Basis(Vector3.UP, (rng.randi() % 4) * PI * 0.5)
		var half := Vector3(0.1, 0, 0.1)
		var base := Vector3(x, h, z) * V
		if not lists.has(kind):
			lists[kind] = []
		lists[kind].append(Transform3D(rot, base + half - rot * half))
	for kind in lists:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = VoxelMesher.build(VegetationLibrary.build_plant(kind), VoxelGrid.DETAIL_SIZE)
		mm.instance_count = lists[kind].size()
		for j in lists[kind].size():
			mm.set_instance_transform(j, lists[kind][j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		_add(mmi, DIORAMA_ORIGIN)
	_label("Diorama : assets posés sur le terrain (grille 0,20 m)", DIORAMA_ORIGIN + Vector3(9.0, 3.2, 0.4), 40)

## Comparaison : mêmes voxels, rendu Lot 1 (gauche) et Lot 2 (droite).
func _build_terrain_comparison() -> void:
	var vol := TerrainPatch.generate(30, 30, 12, 2, 6)
	var styles := [[VoxelMesher.Style.LEGACY, "Lot 1 : ancien rendu", -7.0], [VoxelMesher.Style.STYLIZED, "Lot 2 : rendu stylisé", 1.0]]
	for st in styles:
		var origin := Vector3(st[2], 0, COMPARE_Z)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMesher.build(vol, V, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(),
				VoxelGrid.world_to_cell(origin), 0, st[0])
		_add(mi, origin)
		_label(st[1], origin + Vector3(3.0, 0.9, 6.5), 52)

# ------------------------------------------------------------------ Vues

## Vue n (1 à 9) : [position caméra, point visé].
func _view(n: int) -> Array:
	match n:
		1: return [Vector3(0, 4.0, 7.0), Vector3(0, 0.6, -4.0)]
		2: return [Vector3(0, 3.4, 16.2), Vector3(0, 0.8, SHOWCASE_Z)]
		8: return [Vector3(0, 8.0, 29.0), Vector3(0, 0.4, DIORAMA_ORIGIN.z + 3.0)]
		9: return [Vector3(0.0, 6.0, COMPARE_Z + 12.0), Vector3(0.0, 0.2, COMPARE_Z + 3.0)]
	var i := n - 3
	if i >= 0 and i < _showcase.size():
		var target: Vector3 = _showcase[i][1]
		var size: Vector3 = _showcase[i][2]
		var d := maxf(size.x, size.y) * 1.25 + 0.8
		return [target + Vector3(d * 0.45, d * 0.38, d * 0.85), target]
	return []

func _go_to_view(n: int) -> void:
	var v := _view(n)
	var cam := get_viewport().get_camera_3d() as FreeCamera
	if cam and not v.is_empty():
		cam.look_from(v[0], v[1])

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if Engine.is_editor_hint() or key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		_go_to_view(key.keycode - KEY_0)
