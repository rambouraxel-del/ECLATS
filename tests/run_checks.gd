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
	_check_greedy()
	_check_assets()
	await _check_scenes()
	print("== %d réussite(s), %d échec(s) ==" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)

func _check_palette() -> void:
	print("Palette")
	var pal := VoxelPalette.get_default()
	check(pal.count() > 40, "palette chargée (%d matières)" % (pal.count() - 1))
	for key in ["stone", "dirt", "grass", "wood_planks", "crystal", "root"]:
		check(pal.id(key) > 0, "matière '%s' présente" % key)
	check(pal.emission[pal.id("crystal")] > 0.0, "l'éclat est émissif")

func _check_grid() -> void:
	print("Grille")
	check(is_equal_approx(VoxelGrid.VOXEL_SIZE, 0.2), "voxel principal = 0,20 m")
	check(is_equal_approx(VoxelGrid.DETAIL_SIZE, 0.02), "microvoxel = 2 cm")
	check(VoxelGrid.DETAILS_PER_VOXEL * VoxelGrid.DETAIL_SIZE == VoxelGrid.VOXEL_SIZE, "10 microvoxels = 1 voxel de terrain")
	check(VoxelGrid.world_to_cell(Vector3(0.19, -0.01, 1.0)) == Vector3i(0, -1, 5), "monde → cellule")
	check(VoxelGrid.cell_to_world(Vector3i(5, -1, 2)).is_equal_approx(Vector3(1.0, -0.2, 0.4)), "cellule → monde")
	check(VoxelGrid.hash01(3, 4, 5, 9) == VoxelGrid.hash01(3, 4, 5, 9), "bruit de cellule déterministe")

func _faces(vol: VoxelVolume) -> int:
	var arrays := VoxelMesher.build_arrays(vol, 0.2, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.LEGACY)
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
	check(_faces(one) == 6 and VoxelMesher.build_arrays(one, 0.2, Vector3i.ZERO, Vector3i(-1, -1, -1), mask, Vector3i.ZERO, 0, VoxelMesher.Style.LEGACY).is_empty(),
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
		var arrays := VoxelMesher.build_arrays(vol, 0.2, Vector3i.ZERO, Vector3i(-1, -1, -1), s.solid, Vector3i.ZERO, 0, VoxelMesher.Style.LEGACY)
		if not arrays.is_empty():
			got += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
	check(got == expected, "île (rendu Lot 1) : %d faces générées = %d faces exposées" % [got, expected])

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
	for path in ["res://scenes/island/first_island.tscn", "res://scenes/lab/graphics_lab.tscn"]:
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

## Aire totale (en voxels²) des quads d'un maillage, et nombre de quads.
func _area_and_quads(arrays: Array, voxel_size: float) -> Vector2:
	var v := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var area := 0.0
	var quads := v.size() / 4
	for q in quads:
		var a := v[q * 4]
		area += ((v[q * 4 + 1] - a).cross(v[q * 4 + 2] - a).length() + (v[q * 4 + 2] - a).cross(v[q * 4 + 3] - a).length()) * 0.5
	return Vector2(area / (voxel_size * voxel_size), quads)

func _check_greedy() -> void:
	print("Maillage fusionné (Lot 2)")
	var cube := VoxelVolume.new(Vector3i(8, 8, 8))
	cube.fill_box(Vector3i.ZERO, Vector3i(7, 7, 7), 1)
	var g := VoxelMesher.build_arrays(cube, 0.02)
	check((g[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4 == 6, "cube plein 8³ : 6 quads fusionnés (au lieu de 384)")
	# Même surface visible qu'avec une face par voxel.
	var gen := IslandGenerator.new()
	gen.radius_m = 3.0
	gen.underside_depth_m = 3.0
	var d := gen.generate()
	var tot_g := Vector2.ZERO
	var tot_l := Vector2.ZERO
	for vol in [d.core, d.surface]:
		var a := VoxelMesher.build_arrays(vol, 0.2, Vector3i.ZERO, Vector3i(-1, -1, -1), d.solid, Vector3i.ZERO, 0, VoxelMesher.Style.STYLIZED)
		var b := VoxelMesher.build_arrays(vol, 0.2, Vector3i.ZERO, Vector3i(-1, -1, -1), d.solid, Vector3i.ZERO, 0, VoxelMesher.Style.LEGACY)
		if not a.is_empty():
			tot_g += _area_and_quads(a, 0.2)
		if not b.is_empty():
			tot_l += _area_and_quads(b, 0.2)
	check(absf(tot_g.x - tot_l.x) < 0.5, "surface visible identique (%.0f voxels² fusionnés / %.0f)" % [tot_g.x, tot_l.x])
	check(tot_g.y < tot_l.y * 0.8, "fusion : %d quads au lieu de %d" % [tot_g.y, tot_l.y])
	# Une seule couleur par quad : deux matières voisines ne fusionnent pas.
	var two := VoxelVolume.new(Vector3i(4, 1, 1))
	two.set_voxel(0, 0, 0, 1)
	two.set_voxel(1, 0, 0, 1)
	two.set_voxel(2, 0, 0, 2)
	two.set_voxel(3, 0, 0, 2)
	var t := VoxelMesher.build_arrays(two, 0.02)
	check((t[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4 == 10, "matières différentes : pas de fusion (10 quads)")
	# Pas de variation par cellule : mêmes couleurs de sommet pour deux voxels identiques.
	var cols := t[Mesh.ARRAY_COLOR] as PackedColorArray
	var distinct := {}
	for c in cols:
		distinct[Color(c.r, c.g, c.b, 1.0)] = true
	check(distinct.size() == 2, "aucune variation de teinte par cellule (2 couleurs pour 2 matières)")
	# Le terrain est identique au Lot 1 (mêmes voxels).
	check(IslandGenerator.new().generate().checksum() == IslandGenerator.new().generate().checksum(), "génération de l'île inchangée et déterministe")

const ASSET_BUDGET_TRIANGLES := {
	"artisan_workbench": 25000, "ancient_chest": 15000, "anchor_pedestal": 45000,
	"market_stall": 70000, "decorative_bench": 15000,
}
const ASSET_SIZES_CELLS := {
	"artisan_workbench": Vector3i(10, 10, 5), "ancient_chest": Vector3i(6, 4, 4),
	"anchor_pedestal": Vector3i(8, 12, 8), "market_stall": Vector3i(12, 13, 8), "decorative_bench": Vector3i(9, 5, 3),
}

func _check_assets() -> void:
	print("Assets détaillés (2 cm)")
	var total_tris := 0
	for id in AssetLibrary.ids():
		var t0 := Time.get_ticks_msec()
		var a := AssetLibrary.build(id)
		var a2 := AssetLibrary.build(id)
		var ms := Time.get_ticks_msec() - t0
		check(a != null and a.parts.size() > 0, "%s : construit (%d pièce(s))" % [id, a.parts.size()])
		check(a.footprint == ASSET_SIZES_CELLS[id], "%s : emprise %s cellules de 20 cm" % [id, a.footprint])
		var same := true
		var tris := 0
		var verts := 0
		var inside := true
		var bounds := a.size_m() + Vector3.ONE * 0.001
		for i in a.parts.size():
			var vol: VoxelVolume = a.parts[i]["volume"]
			same = same and vol.checksum() == (a2.parts[i]["volume"] as VoxelVolume).checksum()
			var arr := VoxelMesher.build_arrays(vol, a.parts[i]["grid"])
			var pv := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			verts += pv.size()
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			# Les sommets restent dans l'emprise déclarée (hors pièces animées).
			if a.parts[i]["animation"] == "" and a.parts[i]["material"] != "cloth":
				var off: Vector3 = a.parts[i]["offset"]
				for v in pv:
					var w := v + off
					if w.x < -0.001 or w.y < -0.001 or w.z < -0.001 or w.x > bounds.x or w.y > bounds.y + 0.4 or w.z > bounds.z:
						inside = false
						break
		total_tris += tris
		check(same, "%s : génération déterministe" % id)
		check(inside, "%s : géométrie contenue dans l'emprise (%s m)" % [id, a.size_m()])
		check(tris <= ASSET_BUDGET_TRIANGLES[id], "%s : %d sommets, %d triangles (budget %d), %d ms" % [id, verts, tris, ASSET_BUDGET_TRIANGLES[id], ms / 2])
		# Collisions dans l'emprise.
		var cok := true
		for box in a.colliders:
			cok = cok and box.position.x >= -0.001 and box.position.z >= -0.001 and box.end.x <= bounds.x and box.end.z <= bounds.z
		check(cok and a.colliders.size() > 0, "%s : boîtes de collision dans l'emprise" % id)
		# Aucune face intérieure : chaque quad est un vrai contact plein/vide (pièce principale).
		var vol0: VoxelVolume = a.parts[0]["volume"]
		var legacy := VoxelMesher.build_arrays(vol0, 0.02, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.LEGACY)
		var exposed := _exposed_quads(vol0)
		check((legacy[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4 == exposed, "%s : aucune face interne (%d faces exposées)" % [id, exposed])
		# Scène générée (bake).
		var packed := load(AssetLibrary.scene_path(id)) as PackedScene
		check(packed != null, "%s : scène %s importée" % [id, AssetLibrary.scene_path(id).get_file()])
		if packed:
			var inst := packed.instantiate()
			var pa := inst as PlaceableAsset
			check(pa.footprint_cells == a.footprint and pa.triangle_count == tris, "%s : scène cohérente avec le générateur (%d triangles)" % [id, pa.triangle_count])
			check(inst.find_children("*", "MeshInstance3D", true, false).size() == a.parts.size(), "%s : un MeshInstance3D par pièce (aucun nœud par voxel)" % id)
			inst.free()
	check(total_tris < 200000, "total des 5 assets : %d triangles" % total_tris)
	# Mémoire : volumes en octets.
	var mem := 0
	for id in AssetLibrary.ids():
		for part in AssetLibrary.build(id).parts:
			mem += (part["volume"] as VoxelVolume).data.size()
	check(mem < 8 * 1024 * 1024, "mémoire des volumes sources : %.1f Mo (non chargés au runtime)" % (mem / 1048576.0))

func _exposed_quads(vol: VoxelVolume) -> int:
	var n := 0
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for y in vol.size.y:
		for z in vol.size.z:
			for x in vol.size.x:
				if vol.get_voxel(x, y, z) == 0:
					continue
				for o in dirs:
					if vol.get_voxel(x + o.x, y + o.y, z + o.z) == 0:
						n += 1
	return n
