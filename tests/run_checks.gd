extends SceneTree
## Vérifications automatiques (sans affichage) :
##   godot --headless -s tests/run_checks.gd
## Code de sortie 0 = tout est bon, 1 = au moins un échec.

var _failures := 0
var _passes := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  OK    ", label)
	else:
		_failures += 1
		printerr("  ÉCHEC ", label)

func _initialize() -> void:
	print("== ÉCLATS : vérifications ==")
	_check_palette()
	_check_grid()
	_check_mesher()
	_check_island()
	_check_models()
	await _check_scenes()
	print("== %d réussite(s), %d échec(s) ==" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)

func _check_palette() -> void:
	print("Palette")
	var pal := VoxelPalette.get_default()
	check(pal.count() > 20, "palette chargée (%d matières)" % (pal.count() - 1))
	for key in ["stone", "dirt", "grass", "wood_planks", "crystal", "root"]:
		check(pal.id(key) > 0, "matière '%s' présente" % key)
	check(pal.emission[pal.id("crystal")] > 0.0, "l'éclat est émissif")

func _check_grid() -> void:
	print("Grille")
	check(is_equal_approx(VoxelGrid.VOXEL_SIZE, 0.2), "voxel principal = 0,20 m")
	check(is_equal_approx(VoxelGrid.DETAIL_SIZE, 0.05), "détail = 0,05 m")
	check(VoxelGrid.world_to_cell(Vector3(0.19, -0.01, 1.0)) == Vector3i(0, -1, 5), "monde → cellule")
	check(VoxelGrid.cell_to_world(Vector3i(5, -1, 2)).is_equal_approx(Vector3(1.0, -0.2, 0.4)), "cellule → monde")
	check(VoxelGrid.hash01(3, 4, 5, 9) == VoxelGrid.hash01(3, 4, 5, 9), "bruit de cellule déterministe")

func _faces(vol: VoxelVolume) -> int:
	var arrays := VoxelMesher.build_arrays(vol, 0.2)
	return 0 if arrays.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4

func _check_mesher() -> void:
	print("Maillage")
	var one := VoxelVolume.new(Vector3i(3, 3, 3))
	one.set_voxel(1, 1, 1, 1)
	check(_faces(one) == 6, "1 voxel → 6 faces")
	var two := VoxelVolume.new(Vector3i(3, 3, 3))
	two.set_voxel(0, 0, 0, 1)
	two.set_voxel(1, 0, 0, 1)
	check(_faces(two) == 10, "2 voxels accolés → 10 faces (face commune supprimée)")
	var cube := VoxelVolume.new(Vector3i(4, 4, 4))
	cube.fill_box(Vector3i.ZERO, Vector3i(3, 3, 3), 1)
	check(_faces(cube) == 6 * 16, "cube plein 4³ → seulement les 96 faces extérieures")
	var mask := PackedByteArray()
	mask.resize(one.data.size())
	mask.fill(1)
	check(_faces(one) == 6 and VoxelMesher.build_arrays(one, 0.2, Vector3i.ZERO, Vector3i(-1, -1, -1), mask).is_empty(),
		"masque d'occupation : faces cachées contre la couche voisine")

func _check_island() -> void:
	print("Île")
	var gen := IslandGenerator.new()
	gen.seed = 1234
	var t0 := Time.get_ticks_msec()
	var a := gen.generate()
	var ms := Time.get_ticks_msec() - t0
	var b := gen.generate()
	gen.seed = 1235
	var c := gen.generate()
	check(a.checksum() == b.checksum(), "même seed → île identique (%d ms)" % ms)
	check(a.checksum() != c.checksum(), "seed différente → île différente")
	# Diamètre : colonnes non vides le long de l'axe X passant par le centre.
	var size := a.size()
	var min_x := size.x
	var max_x := -1
	for z in size.z:
		for x in size.x:
			if a.column_top(x, z) >= 0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var diameter := (max_x - min_x + 1) * VoxelGrid.VOXEL_SIZE
	check(diameter > 26.0 and diameter < 38.0, "diamètre ≈ 30 m (%.1f m)" % diameter)
	# Séparation cœur / surface.
	var overlap := 0
	for i in a.core.data.size():
		if a.core.data[i] != 0 and a.surface.data[i] != 0:
			overlap += 1
	check(overlap == 0, "aucune cellule à la fois dans le cœur et la surface")
	check(a.core.count_solid() > a.surface.count_solid(), "le cœur est plus massif que la couche modifiable")
	var cx := size.x / 2
	var cz := size.z / 2
	var top := a.column_top(cx, cz)
	var core_y := top - IslandGenerator.SURFACE_DEPTH
	check(a.is_core(cx, core_y, cz), "sous la couche superficielle : cœur")
	check(not a.set_surface_voxel(cx, core_y, cz, 0), "le cœur refuse d'être modifié")
	check(a.set_surface_voxel(cx, top, cz, 0), "la surface accepte d'être modifiée")
	var pal := VoxelPalette.get_default()
	var grass := 0
	for i in a.top_material.size():
		if a.top_material[i] in [pal.id("grass"), pal.id("grass_lush"), pal.id("grass_dry")]:
			grass += 1
	var land := a.top_material.size() - a.top_material.count(0)
	check(grass > land / 2, "surface majoritairement en herbe (%d / %d colonnes)" % [grass, land])
	# Nombre de faces = nombre exact de contacts plein / vide (aucune face intérieure).
	var small := IslandGenerator.new()
	small.radius_m = 3.0
	small.underside_depth_m = 3.0
	var s := small.generate()
	var expected := _exposed_faces(s)
	var got := 0
	for vol in [s.core, s.surface]:
		var arrays := VoxelMesher.build_arrays(vol, 0.2, Vector3i.ZERO, Vector3i(-1, -1, -1), s.solid)
		if not arrays.is_empty():
			got += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
	check(got == expected, "île : %d faces générées = %d faces exposées" % [got, expected])

func _exposed_faces(d: IslandData) -> int:
	var n := 0
	var sz := d.size()
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for y in sz.y:
		for z in sz.z:
			for x in sz.x:
				if d.get_voxel(x, y, z) == 0:
					continue
				for o in dirs:
					if d.get_voxel(x + o.x, y + o.y, z + o.z) == 0:
						n += 1
	return n

func _check_models() -> void:
	print("Objets")
	for key in VoxelModelLibrary.KEYS:
		var m := VoxelModelLibrary.get_model(key)
		var ok: bool = not m.is_empty() and (m["volume"] as VoxelVolume).count_solid() > 0
		var size: Vector3 = m["size_m"] if ok else Vector3.ZERO
		var aligned := is_zero_approx(fmod(size.x + 1e-4, 0.2) - 1e-4) and is_zero_approx(fmod(size.z + 1e-4, 0.2) - 1e-4)
		check(ok and aligned, "%s : %.2f × %.2f × %.2f m, emprise alignée sur 0,20 m" % [key, size.x, size.y, size.z])
	check(VoxelModelLibrary.get_model("shard_lamp").has("light"), "la lampe porte une lumière")

func _check_scenes() -> void:
	print("Scènes")
	for path in ["res://scenes/lab/graphics_lab.tscn", "res://scenes/island/first_island.tscn"]:
		var packed := load(path) as PackedScene
		check(packed != null, "chargement %s" % path)
		if packed == null:
			continue
		var inst := packed.instantiate()
		root.add_child(inst)
		for i in 3:
			await process_frame
		var meshes := inst.find_children("*", "MeshInstance3D", true, false).size()
		check(meshes > 5, "%s : %d maillages affichés" % [path.get_file(), meshes])
		check(root.get_viewport().get_camera_3d() != null, "%s : caméra active" % path.get_file())
		inst.queue_free()
		await process_frame
