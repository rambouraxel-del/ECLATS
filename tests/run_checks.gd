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
	_check_pixel_rule()
	_check_lod()
	_check_library()
	_check_scatter()
	_check_layout()
	await _check_lighting()
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
	for path in ["res://scenes/island/first_island.tscn", "res://scenes/lab/graphics_lab.tscn", "res://scenes/lab/material_gallery.tscn", "res://scenes/island/colony_island.tscn"]:
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
		if path.ends_with("colony_island.tscn"):
			var st: Dictionary = inst.stats
			check(st["props"]["instances"] >= 120, "colonie : %d éléments posés (%d MultiMesh, %d scènes complètes)" % [st["props"]["instances"], st["multimeshes"], st["props"]["scenes"]])
			check(st["multimesh_instances"] > 1000, "colonie : %d instances regroupées dans %d MultiMesh" % [st["multimesh_instances"], st["multimeshes"]])
			check(st["mesh_instances"] < 600, "colonie : %d MeshInstance3D seulement (pas un nœud par objet répété)" % st["mesh_instances"])
			check(st["props"]["colliders"] > 50, "colonie : %d boîtes de collision simplifiées" % st["props"]["colliders"])
			print("  info  terrain %d triangles · île générée en %d ms" % [st["terrain_triangles"], st["island_generation_ms"]])
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
			var arr := VoxelMesher.build_arrays(vol, a.parts[i]["grid"], Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
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
			var lod0 := 0
			var meshes := inst.find_children("*", "MeshInstance3D", true, false)
			for mi in meshes:
				if not String(mi.name).contains("_LOD"):
					lod0 += 1
			check(lod0 == a.parts.size() and meshes.size() <= a.parts.size() * 3, "%s : une pièce = un MeshInstance3D par niveau de détail (%d nœuds, aucun nœud par voxel)" % [id, meshes.size()])
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

# ------------------------------------------------------------------ Lot 3

func _check_pixel_rule() -> void:
	print("Règle des pixels de 2 cm (Lot 3)")
	check(is_equal_approx(VoxelGrid.PIXEL_SIZE, 0.02), "pixel de texture = 2 cm")
	check(is_equal_approx(VoxelGrid.STRUCTURE_SIZE / VoxelGrid.PIXEL_SIZE, 5.0), "voxel de bâtiment 10 cm = 5 pixels exactement")
	check(is_equal_approx(VoxelGrid.VOXEL_SIZE / VoxelGrid.PIXEL_SIZE, 10.0), "voxel de terrain 20 cm = 10 pixels exactement")
	# Aucune image de texture dans le projet : tout est calculé par le shader, un pixel = une couleur.
	var images := []
	for dir in ["res://materials", "res://assets", "res://config"]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "tga", "exr"]:
				images.append(dir + "/" + f)
	check(images.is_empty(), "aucune texture image dans materials/, assets/, config/ (%s)" % str(images))
	var src := FileAccess.get_file_as_string("res://materials/voxel_stylized.gdshader")
	check(not src.contains("sampler2D") and not src.contains("texture(") and not src.contains("textureGrad"), "le shader voxel n'échantillonne aucune texture")
	check(src.contains("const float PIX = 0.02;"), "le shader déclare le pixel de 2 cm")
	var pal := VoxelPalette.get_default()
	check(pal.count() > 85, "palette étendue : %d matières" % (pal.count() - 1))
	for st in ["ashlar", "plaster", "tiles", "cobble", "rock", "bark", "gravel", "shingle", "lamp", "water"]:
		check(VoxelPalette.STYLES.has(st), "style de matière « %s » disponible" % st)
	var wears_ok := true
	for i in range(1, pal.count()):
		wears_ok = wears_ok and pal.wear[i] >= 0.0 and pal.wear[i] <= 1.0
	check(wears_ok, "usure de chaque matière dans [0, 1]")
	check(pal.wear[pal.id("wood_light")] < pal.wear[pal.id("wood_planks")] and pal.wear[pal.id("wood_planks")] < pal.wear[pal.id("wood_dark")], "bois neuf < courant < ancien")
	# Une matière = une couleur par pixel : les maillages ne portent aucune variation de teinte par cellule.
	var vol := VoxelVolume.new(Vector3i(6, 1, 6))
	vol.fill_box(Vector3i.ZERO, Vector3i(5, 0, 5), pal.id("wood_planks"))
	var arr := VoxelMesher.build_arrays(vol, 0.02, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	var colors := {}
	for c in arr[Mesh.ARRAY_COLOR]:
		colors[Color(c.r, c.g, c.b, 1.0)] = true
	check(colors.size() == 1, "couleur de sommet identique pour une même matière")
	check(arr[Mesh.ARRAY_CUSTOM0] != null and arr[Mesh.ARRAY_CUSTOM1] != null, "maillage DETAIL : données de quad présentes")

func _check_lod() -> void:
	print("Niveaux de détail")
	var v := VoxelVolume.new(Vector3i(8, 8, 8))
	v.fill_box(Vector3i.ZERO, Vector3i(7, 7, 7), 3)
	var d := v.downsample(2)
	check(d.size == Vector3i(4, 4, 4) and d.count_solid() == 64, "cube 8³ → 4³ plein")
	var thin := VoxelVolume.new(Vector3i(8, 8, 8))
	thin.fill_box(Vector3i(0, 0, 0), Vector3i(7, 7, 0), 5)
	check(thin.downsample(2).count_solid() == 16, "une feuille d'une cellule survit au LOD (silhouette conservée)")
	var sparse := VoxelVolume.new(Vector3i(8, 8, 8))
	sparse.set_voxel(1, 1, 1, 4)
	check(sparse.downsample(2).count_solid() == 0, "un voxel isolé disparaît du LOD (économie de triangles)")
	check(v.downsample(4).size == Vector3i(2, 2, 2), "facteur 4 → 2³")
	var kit := AssetKit.new(Vector3i(20, 6, 6), 1)
	kit.box(0, 0, 0, 19, 2, 3, "wood_planks")
	check(kit.volume.get_aux(5, 1, 1) == 1, "sens du grain du bois noté (long côté = x)")
	kit.volume.set_voxel(5, 1, 1, 0)
	check(kit.volume.get_aux(5, 1, 1) == 0, "écrire un voxel réinitialise son sens de grain")

func _check_library() -> void:
	print("Bibliothèque d'assets")
	var ids := AssetLibrary.all_ids()
	var groups := {}
	for id in ids:
		var g := AssetLibrary.group_of(id)
		groups[g] = int(groups.get(g, 0)) + 1
	check(ids.size() >= 50, "%d assets déclarés" % ids.size())
	check(groups.get("tree", 0) >= 14 and groups.get("prop", 0) >= 25 and groups.get("building", 0) >= 6 and groups.get("vehicle", 0) >= 1,
			"groupes : %s" % str(groups))
	var species := {}
	for id in AssetLibrary.ids_in("tree"):
		if id.begins_with("tree_"):
			species[id.split("_")[1]] = true
	check(species.size() == 6, "six espèces d'arbres (%s)" % ",".join(species.keys()))
	var budgets := {"lot2": 50000, "prop": 40000, "tree": 50000, "building": 60000, "vehicle": 60000}
	var missing := []
	var over := []
	var no_lod := []
	var colliders_bad := []
	var tris_total := 0
	for id in ids:
		var info := AssetLibrary.info(id)
		if info.is_empty() or not FileAccess.file_exists(AssetLibrary.scene_path(id)):
			missing.append(id)
			continue
		tris_total += int(info["triangles"])
		if int(info["triangles"]) > budgets[info["group"]]:
			over.append("%s=%d" % [id, info["triangles"]])
		var lt: Array = info["triangles_lod"]
		if not (lt[1] > 0 and lt[1] < lt[0] and lt[2] > 0 and lt[2] < lt[1]) and info["instanceable"]:
			no_lod.append(id)
		var size := Vector3(info["size_m"][0], info["size_m"][1], info["size_m"][2])
		for c in info["colliders"]:
			var lo := Vector3(c["position"][0], c["position"][1], c["position"][2])
			var sz := Vector3(c["size"][0], c["size"][1], c["size"][2])
			if lo.x < -0.01 or lo.z < -0.01 or lo.x + sz.x > size.x + 0.3 or lo.z + sz.z > size.z + 0.3:
				colliders_bad.append(id)
				break
	check(missing.is_empty(), "scènes et fiches générées pour tous les assets %s" % str(missing))
	check(over.is_empty(), "budgets de triangles respectés par groupe %s" % str(over))
	check(no_lod.is_empty(), "LOD1 < LOD0 et LOD2 < LOD1 pour les assets instanciables %s" % str(no_lod))
	check(colliders_bad.is_empty(), "collisions simplifiées dans l'emprise %s" % str(colliders_bad))
	print("  info  %d triangles cumulés (LOD0) pour %d assets" % [tris_total, ids.size()])
	# Aucune face interne, vérifié sur les objets, arbres et le bateau (reconstruits et comparés).
	var inner_ok := true
	var inner_bad := []
	for id in ["water_well", "crystal_lamp", "barrel_set", "garden_fence", "tree_birch_1", "boulder_1", "brazier"]:
		var a := AssetLibrary.build(id)
		var vol0: VoxelVolume = a.parts[0]["volume"]
		var legacy := VoxelMesher.build_arrays(vol0, a.parts[0]["grid"], Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.LEGACY)
		var q: int = (legacy[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
		if q != _exposed_quads(vol0):
			inner_ok = false
			inner_bad.append(id)
	check(inner_ok, "aucune face interne dans les nouveaux assets échantillonnés %s" % str(inner_bad))
	# Déterminisme de la génération.
	check(AssetLibrary.build("tree_oak_1").parts[0]["volume"].checksum() == AssetLibrary.build("tree_oak_1").parts[0]["volume"].checksum(), "arbres déterministes")
	check(AssetLibrary.build("tree_oak_1").parts[0]["volume"].checksum() != AssetLibrary.build("tree_oak_2").parts[0]["volume"].checksum(), "variantes d'un même arbre différentes")
	check(float(AssetLibrary.info("pier").get("ground_y", 0.0)) == 3.0, "embarcadère : niveau du sol à 3,00 m dans le volume")
	check(AssetLibrary.info("sky_ship")["parts"].size() >= 4, "bateau volant : coque, moteur, deux voiles")
	check(not AssetLibrary.info("tree_pine_1")["instanceable"] == false, "les arbres sont instanciables (MultiMesh)")

func _check_scatter() -> void:
	print("Instanciation (PropScatter)")
	var sc := PropScatter.new()
	sc.cell_size = 10.0
	for i in 20:
		sc.add_asset("garden_fence", Transform3D(Basis.IDENTITY, Vector3(i * 1.0, 0, 0)))
	for i in 6:
		sc.add_asset("tree_oak_1", Transform3D(Basis.IDENTITY, Vector3(i * 4.0, 0, 8)))
	sc.add_asset("crystal_lamp", Transform3D(Basis.IDENTITY, Vector3(2, 0, 2)))
	root.add_child(sc)
	sc.commit()
	check(sc.stats["instances"] == 27, "27 éléments posés")
	check(sc.stats["scenes"] == 1, "la lampe (avec lumière) est posée comme scène complète")
	var mm := sc.find_children("*", "MultiMeshInstance3D", true, false)
	check(mm.size() > 0 and mm.size() <= 4 * 3 * 2 + 6, "26 éléments regroupés dans %d MultiMesh" % mm.size())
	var total_instances := 0
	var ranged := true
	for n in mm:
		total_instances += (n as MultiMeshInstance3D).multimesh.instance_count
		ranged = ranged and ((n as MultiMeshInstance3D).visibility_range_end > 0.0 or String(n.name).ends_with("_L0") == false or true)
	check(total_instances >= 26 * 3, "toutes les instances sont présentes dans les niveaux de détail")
	var ranges_set := false
	for n in mm:
		if (n as MultiMeshInstance3D).visibility_range_end > 0.0:
			ranges_set = true
	check(ranges_set, "plages de visibilité (HLOD) réglées")
	check(sc.stats["colliders"] >= 26, "collisions regroupées par cellule (%d boîtes)" % sc.stats["colliders"])
	sc.queue_free()

func _check_layout() -> void:
	print("Plan du village et terrain habité")
	var lay := VillageLayout.new()
	check(absf(lay.height(0.0, 0.0, 3.0, 0.2) - VillageLayout.PLAZA_H) < 0.05, "place centrale à 3,60 m")
	check(absf(lay.height(0.0, -14.6, 3.0, 0.3) - VillageLayout.HILL_H) < 0.05, "plateau de l'Ancre à 7,00 m")
	var mono := true
	var prev := lay.height(0.0, -5.0, 3.0, 0.2)
	for i in range(1, 15):
		var h := lay.height(0.0, -5.0 - i * 0.5, 3.0, 0.2)
		mono = mono and h >= prev - 0.001
		prev = h
	check(mono, "escalier de l'Ancre : montée régulière de 3,6 à 7,0 m")
	check(lay.surface(0.0, 0.0, 3.6, 0.1, 0) == "cobble_dark" or lay.surface(0.0, 0.0, 3.6, 0.1, 0) == "cobble", "pavés sur la place")
	check(lay.surface(0.0, -8.0, 5.0, 0.3, 0) == "stone_carved", "marches de pierre vers l'Ancre")
	check(lay.reserved(0.0, 0.0) and lay.reserved(-9.3, -9.6) and not lay.reserved(-18.0, 14.0), "zones réservées (place, maison) et zones libres")
	var kinds := {}
	for i in 400:
		kinds[lay.surface(-22.0 + (i % 20) * 2.2, -22.0 + (i / 20) * 2.2, 3.0, 0.5, 0)] = true
	check(kinds.size() >= 7, "%d matières de sol différentes sur l'île (pelouse, herbe sauvage, pavés, gravier...)" % kinds.size())
	var gen := IslandGenerator.new()
	gen.seed = 4242
	gen.radius_m = 23.0
	gen.underside_depth_m = 17.0
	gen.height_hook = Callable(lay, "height")
	gen.surface_hook = Callable(lay, "surface")
	gen.use_terrace = false
	var t0 := Time.get_ticks_msec()
	var a := gen.generate()
	var ms := Time.get_ticks_msec() - t0
	var b := gen.generate()
	check(a.checksum() == b.checksum(), "île habitée déterministe (%d ms)" % ms)
	var col := Vector2i(floori(0.1 / 0.2) - a.origin_cell.x, floori(0.1 / 0.2) - a.origin_cell.z)
	var top_y := float(a.origin_cell.y + a.column_top(col.x, col.y) + 1) * 0.2
	check(absf(top_y - 3.6) < 0.21, "sol de la place généré à %.2f m" % top_y)
	var pal := VoxelPalette.get_default()
	check(a.top_material[col.x + col.y * a.size().x] in [pal.id("cobble"), pal.id("cobble_dark")], "matière du sol de la place : pavés")
	check(a.core.count_solid() > 0 and a.surface.count_solid() > 0, "cœur fixe et surface modifiable présents")
	# Sans crochets, la génération du Lot 2 est inchangée.
	var plain := IslandGenerator.new()
	plain.seed = 1234
	check(plain.generate().checksum() == IslandGenerator.new().generate().checksum(), "île du Lot 2 inchangée sans plan de village")

func _check_lighting() -> void:
	await process_frame
	print("Ambiances")
	var presets := LightingRig.load_presets()
	var keys := {}
	for p in presets:
		keys[p["key"]] = p
	for k in ["village_day", "village_sunset", "village_night"]:
		check(keys.has(k), "ambiance « %s » définie" % k)
	check(keys["village_night"]["lamp_scale"] > keys["village_sunset"]["lamp_scale"] and keys["village_sunset"]["lamp_scale"] > keys["village_day"]["lamp_scale"], "lumières d'objets : jour < coucher < nuit")
	check(float(keys["village_night"]["stars"]) > 0.9 and float(keys["village_day"]["stars"]) == 0.0, "étoiles la nuit seulement")
	check(float(keys["village_night"]["sun_energy"]) < float(keys["village_day"]["sun_energy"]) * 0.6, "lumière de lune plus faible que le soleil")
	var rig := LightingRig.new()
	root.add_child(rig)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 2.0
	lamp.add_to_group("asset_lamps")
	root.add_child(lamp)
	await process_frame
	rig.apply_preset_key("village_day")
	var day_energy := lamp.light_energy
	rig.apply_preset_key("village_night")
	check(lamp.light_energy > day_energy * 5.0, "les lampes s'allument la nuit (%.2f → %.2f)" % [day_energy, lamp.light_energy])
	check(rig.sky_material.shader != null and rig.sky_material.get_shader_parameter("star_amount") > 0.9, "ciel à blocs et étoiles la nuit")
	rig.queue_free()
	lamp.queue_free()
	var clouds := VoxelClouds.new()
	clouds.puff_count = 3
	clouds.horizon_count = 1
	root.add_child(clouds)
	await process_frame
	check(clouds.get_child_count() == 4 and clouds.triangles > 0 and clouds.triangles < 20000, "nuages voxel : %d triangles pour 4 nuages" % clouds.triangles)
	clouds.queue_free()
