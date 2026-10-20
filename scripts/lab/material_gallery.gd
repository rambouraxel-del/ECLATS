@tool
extends Node3D
## Galerie de matériaux : panneaux à l'échelle réelle pour juger les textures de près.
## Rangées (du fond vers l'avant) : bois · pierre · métaux · tissus et cristaux · terrain · toits et enduits.
## Touches : 1-6 vue sur chaque rangée · T bascule les textures (avant / après) · L éclairage.

const V := VoxelGrid.DETAIL_SIZE
const LABEL_COLOR := Color(0.12, 0.12, 0.14)
const ROWS_Z := [-5.0, -2.4, 0.2, 2.8, 5.4, 8.0]
const ROW_NAMES := ["Bois", "Pierre", "Métaux", "Tissus et cristaux", "Terrain", "Enduit et toitures"]

var _tex_on := true

func _ready() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			child.queue_free()
	_floor()
	_row_wood()
	_row_stone()
	_row_metal()
	_row_fabric_crystal()
	_row_terrain()
	_row_roofs()
	if not Engine.is_editor_hint():
		App.set_scene_help("Galerie : 1-6 rangées · T textures on/off · L éclairage")
		_go_view(1)

func _add(node: Node3D, pos := Vector3.ZERO) -> Node3D:
	node.set_meta("generated", true)
	node.position = pos
	add_child(node)
	return node

func _label(text: String, pos: Vector3, size := 34) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.003
	l.modulate = LABEL_COLOR
	l.outline_size = 10
	l.outline_modulate = Color(1, 1, 1, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.double_sided = true
	_add(l, pos)

func _floor() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(26, 0.2, 18)
	bm.material = load("res://materials/lab_floor_material.tres")
	mi.mesh = bm
	_add(mi, Vector3(0, -0.1, 1.5))

func _panel(kit: VoxelModelBuilder, pos: Vector3, label: String, style := VoxelMesher.Style.DETAIL, grid := V) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMesher.build(kit.volume, grid, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, style)
	_add(mi, pos)
	_label(label, pos + Vector3(kit.volume.size.x * grid * 0.5, kit.volume.size.y * grid + 0.18, 0.0))

func _x(i: int, n: int) -> float:
	return (i - (n - 1) * 0.5) * 1.55 - 0.5

func _row_wood() -> void:
	var z: float = ROWS_Z[0]
	var keys := ["wood_light", "wood_honey", "wood_planks", "wood_red", "wood_dark"]
	var names := ["Neuf", "Miel", "Courant", "Rougeâtre", "Ancien / usé"]
	for i in keys.size():
		var k := AssetKit.new(Vector3i(70, 60, 8), 11 + i)
		k.planks(0, 0, 0, 69, 59, 4, 1, 0, 9, [keys[i], keys[i], keys[i]], true)
		k.box(0, 0, 5, 69, 3, 7, keys[i])
		k.box(0, 56, 5, 69, 59, 7, keys[i])
		# Poteau : bois de bout visible en haut.
		_panel(k, Vector3(_x(i, 5), 0, z), names[i])
	# Sections de poutres (bois de bout) et planches de chant
	var k2 := AssetKit.new(Vector3i(36, 40, 12), 3)
	k2.box(0, 0, 0, 11, 39, 11, "wood_planks")
	k2.box(14, 0, 0, 25, 24, 11, "wood_honey")
	k2.box(28, 0, 0, 35, 14, 11, "wood_dark")
	_panel(k2, Vector3(_x(5, 5) - 0.2, 0, z), "Bois de bout")

func _row_stone() -> void:
	var z: float = ROWS_Z[1]
	var a := AssetKit.new(Vector3i(70, 60, 12), 21)
	a.masonry(0, 0, 0, 69, 59, 11, 18, 10, 3)
	_panel(a, Vector3(_x(0, 5), 0, z), "Pierre taillée (joints)")
	var b := AssetKit.new(Vector3i(70, 60, 12), 22)
	b.box(0, 0, 0, 69, 59, 11, "stone_ashlar")
	_panel(b, Vector3(_x(1, 5), 0, z), "Appareil de pierre")
	var c := AssetKit.new(Vector3i(70, 8, 70), 23)
	c.box(0, 0, 0, 69, 5, 69, "cobble")
	c.box(0, 6, 0, 33, 7, 69, "cobble_dark")
	_panel(c, Vector3(_x(2, 5), 0, z - 0.2), "Pavés (clair / sombre)")
	var d := AssetKit.new(Vector3i(70, 60, 30), 24)
	d.box(0, 0, 0, 69, 29, 29, "rock_warm")
	d.box(0, 30, 0, 69, 59, 29, "rock_grey")
	_panel(d, Vector3(_x(3, 5), 0, z), "Roche (chaude / grise)")
	var e := AssetKit.new(Vector3i(70, 60, 12), 25)
	e.box(0, 0, 0, 69, 59, 11, "stone_shade")
	e.box(0, 0, 0, 69, 14, 11, "stone_dark")
	_panel(e, Vector3(_x(4, 5), 0, z), "Pierre ombrée / sombre")

func _row_metal() -> void:
	var z: float = ROWS_Z[2]
	var keys := ["copper", "brass", "iron", "iron_dark", "copper_patina"]
	var names := ["Cuivre", "Laiton", "Fer", "Fer noirci", "Cuivre patiné"]
	for i in keys.size():
		var k := AssetKit.new(Vector3i(70, 60, 10), 31 + i)
		k.box(0, 0, 0, 69, 59, 5, "wood_planks")
		k.box(4, 4, 6, 65, 17, 8, keys[i])
		k.box(4, 22, 6, 17, 55, 8, keys[i])
		k.box(52, 22, 6, 65, 55, 8, keys[i])
		k.rivets(Vector3i(8, 10, 9), Vector3i(60, 10, 9), 6, "iron_dark")
		k.copper_cap(24, 22, 40, 10, 4) if i == 0 else k.box(24, 22, 6, 40, 40, 9, keys[i])
		_panel(k, Vector3(_x(i, 5), 0, z), names[i])

func _row_fabric_crystal() -> void:
	var z: float = ROWS_Z[3]
	var f := AssetKit.new(Vector3i(40, 70, 4), 41)
	f.banner(2, 68, 1, 36, 66, 2, 5)
	_panel(f, Vector3(_x(0, 5), 0, z), "Bannière bleue")
	var g := AssetKit.new(Vector3i(40, 70, 4), 42)
	g.banner(2, 68, 1, 36, 66, 2, 5, "fabric_cream")
	_panel(g, Vector3(_x(1, 5), 0, z), "Toile crème")
	var h := AssetKit.new(Vector3i(40, 20, 40), 43)
	for i in 6:
		h.box(2 + i * 6, 0, 2, 7 + i * 6, 4, 37, ["fabric_blue", "fabric_cream", "fabric_teal", "fabric_wine", "rope", "hay"][i])
	_panel(h, Vector3(_x(2, 5) - 0.2, 0, z), "Tissus, corde, foin")
	var cr := AssetKit.new(Vector3i(60, 64, 60), 44)
	cr.crystal(Vector3(30, 2, 30), 55.0, 9.0, Vector2.ZERO, "crystal_blue", 0.35)
	cr.crystal(Vector3(14, 2, 36), 28.0, 5.0, Vector2(-0.2, 0.1), "crystal_cyan", 0.4)
	cr.crystal(Vector3(46, 2, 22), 34.0, 6.0, Vector2(0.15, 0.0), "crystal_deep", 0.4)
	cr.crystal(Vector3(40, 2, 44), 18.0, 4.0, Vector2(0.1, -0.1), "crystal_ice", 0.45)
	_panel(cr, Vector3(_x(3, 5) + 0.15, 0, z), "Cristaux")
	var l := AssetKit.new(Vector3i(40, 30, 40), 45)
	l.lantern(20, 2, 20, 8, 14)
	_panel(l, Vector3(_x(4, 5), 0, z), "Lanterne")

func _row_terrain() -> void:
	var z: float = ROWS_Z[4]
	var specs := [["grass_trim", "dirt", "Pelouse"], ["grass_wild", "dirt_dry", "Herbe sauvage"], ["grass_trampled", "path_dirt", "Herbe piétinée"],
			["gravel", "dirt_wet", "Gravier / terre humide"], ["rock_warm", "dirt_fertile", "Roche / terre fertile"]]
	var pal := VoxelPalette.get_default()
	for i in specs.size():
		var vol := VoxelVolume.new(Vector3i(7, 5, 7))
		vol.fill_box(Vector3i(0, 0, 0), Vector3i(6, 1, 6), pal.id(specs[i][1]))
		vol.fill_box(Vector3i(0, 2, 0), Vector3i(6, 2, 6), pal.id(specs[i][1]))
		vol.fill_box(Vector3i(0, 3, 0), Vector3i(6, 3, 6), pal.id(specs[i][0]))
		vol.fill_box(Vector3i(0, 4, 0), Vector3i(2, 4, 2), pal.id(specs[i][0]))
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMesher.build(vol, VoxelGrid.VOXEL_SIZE)
		_add(mi, Vector3(_x(i, 5) - 0.1, 0, z))
		_label(specs[i][2], Vector3(_x(i, 5) + 0.6, 1.2, z + 0.7))

func _row_roofs() -> void:
	var z: float = ROWS_Z[5]
	var keys := ["plaster_cream", "plaster_ochre", "tiles_terracotta", "tiles_slate", "shingle_wood"]
	var names := ["Enduit crème", "Enduit ocre", "Tuiles terre cuite", "Ardoise", "Bardeaux"]
	for i in keys.size():
		var k := AssetKit.new(Vector3i(70, 60, 30), 61 + i)
		if i < 2:
			k.box(0, 0, 0, 69, 59, 9, keys[i])
			k.box(0, 0, 0, 69, 11, 10, "stone_ashlar_dark")
		else:
			# Pan de toit à 45° : marches de 5 cm dans le sens du faîtage (x).
			for s in 30:
				k.box(0, s * 2, s, 69, s * 2 + 3, s, keys[i])
				k.box(0, s * 2, s, 69, s * 2, s + 1, keys[i])
		_panel(k, Vector3(_x(i, 5), 0, z), names[i])

# ---- vues -----------------------------------------------------------------
func _view(n: int) -> Array:
	if n >= 1 and n <= 6:
		var z: float = ROWS_Z[n - 1]
		return [Vector3(-0.5, 1.15, z + 4.6), Vector3(-0.5, 0.5, z)]
	return []

func _go_view(n: int) -> void:
	var v := _view(n)
	var cam := get_viewport().get_camera_3d() as FreeCamera
	if cam and not v.is_empty():
		cam.look_from(v[0], v[1])

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if Engine.is_editor_hint() or key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_6:
		_go_view(key.keycode - KEY_0)
	elif key.keycode == KEY_T:
		_tex_on = not _tex_on
		VoxelMaterials.set_global_param("tex_strength", 1.0 if _tex_on else 0.0)
		App.set_scene_help("Galerie : textures %s · 1-6 rangées · L éclairage" % ("ACTIVÉES" if _tex_on else "DÉSACTIVÉES (couleurs unies)"))
