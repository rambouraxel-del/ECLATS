extends Node3D
## Première île habitée d'ÉCLATS : petite colonie sur une île flottante de ~46 m.
## Terrain voxel (20 cm, pixels de texture de 2 cm), village (place, marché, maisons, atelier,
## entrepôt, tour, potager), colline de l'Ancre de téléportation, port avec bateau volant, nuages.
## Les assets sont posés par PropScatter (MultiMesh par cellules, niveaux de détail, collisions).
## Touches : 1-9, 0 vues · F5 jour · F6 coucher de soleil · F7 nuit · L ambiance suivante · T textures on/off
## (la pose est déterministe : même graine = même village).

const AMBIANCES := ["village_day", "village_sunset", "village_night"]
const SEED := 4242

var layout := VillageLayout.new()
var island: VoxelIsland
var scatter: PropScatter
var rig: LightingRig
var stats := {}
var _tex_on := true
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	rig = $LightingRig
	scatter = PropScatter.new()
	scatter.name = "Props"
	scatter.cell_size = 14.0
	scatter.max_distance = 220.0
	add_child(scatter)
	island = VoxelIsland.new()
	island.name = "Island"
	island.seed = SEED
	island.radius_m = 23.0
	island.underside_depth_m = 17.0
	island.hill_height_m = 3.2
	island.chunk_size = 64
	island.layout = layout
	island.generated.connect(_on_island_generated)
	add_child(island)
	if not Engine.is_editor_hint():
		App.set_scene_help("Colonie · vues 1-9,0 · F5 jour · F6 coucher · F7 nuit · T textures · L ambiance")
		_go_view(1)

func _on_island_generated(_d: IslandData) -> void:
	scatter.clear_all()
	_rng.seed = SEED
	_place_village()
	_place_nature()
	scatter.commit()
	rig.refresh_lamps()
	_collect_stats()

# ------------------------------------------------------------------ pose

## Transform d'un asset dont l'emprise est centrée en `center` (x, z), tourné de yaw × 90°.
func xform_for(id: String, center: Vector2, yaw: int, y_override := NAN, y_extra := 0.0) -> Transform3D:
	var info := AssetLibrary.info(id)
	var size := Vector3(info["size_m"][0], info["size_m"][1], info["size_m"][2])
	var basis := Basis(Vector3.UP, yaw * PI * 0.5)
	var o := Vector3(center.x, 0.0, center.y) - basis * Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	o.x = snappedf(o.x, VoxelGrid.VOXEL_SIZE)
	o.z = snappedf(o.z, VoxelGrid.VOXEL_SIZE)
	var ground := island.surface_y_at(center.x, center.y) if is_nan(y_override) else y_override
	o.y = ground - float(info.get("ground_y", 0.0)) + y_extra
	return Transform3D(basis, o)

func place(id: String, center: Vector2, yaw := 0, y_override := NAN, y_extra := 0.0) -> Transform3D:
	var xf := xform_for(id, center, yaw, y_override, y_extra)
	scatter.add_asset(id, xf)
	return xf

## Pose un asset dans le repère d'un bâtiment (origine locale en mètres).
func place_in(parent: Transform3D, id: String, local_origin: Vector3, yaw := 0) -> void:
	var xf := parent * Transform3D(Basis(Vector3.UP, yaw * PI * 0.5), local_origin)
	scatter.add_asset(id, xf)

func _place_village() -> void:
	# --- Place centrale ---
	place("pedestal_fountain", Vector2(0, 0))
	for p in [Vector2(3.4, 3.4), Vector2(-3.4, 3.4), Vector2(3.4, -3.3), Vector2(-3.4, -3.3)]:
		place("crystal_lamp", p, _rng.randi() % 4)
	place("decorative_bench", Vector2(3.9, 0.6), 3)
	place("decorative_bench", Vector2(-3.9, 0.2), 1)
	place("decorative_bench", Vector2(0.3, 3.9), 2)
	place("large_planter", Vector2(-4.4, -3.9))
	place("large_planter", Vector2(4.5, -3.7))
	place("barrel_set", Vector2(4.8, 3.2), 1)
	place("brazier", Vector2(-2.0, -5.3))
	place("brazier", Vector2(2.0, -5.3))
	place("notice_board", Vector2(-4.1, -5.6))
	place("signpost", Vector2(2.9, -6.0))
	# --- Marché ---
	place("market_stall", Vector2(9.2, -2.9))
	place("canopy_kiosk", Vector2(13.0, -2.7))
	place("artisan_workbench", Vector2(9.4, 3.1), 2)
	place("utility_cart", Vector2(13.2, 3.1), 2)
	place("barrel_set", Vector2(6.3, -2.9))
	place("crate_stack", Vector2(11.4, 4.3), 1)
	place("crystal_lamp", Vector2(7.4, 1.5), 1)
	place("crystal_lamp", Vector2(11.6, 1.5), 3)
	# --- Maisons ---
	place("house_colonist", Vector2(-9.3, -9.6))
	place("house_cottage", Vector2(8.8, -9.9))
	place("large_planter", Vector2(-13.0, -5.6))
	place("large_planter", Vector2(-5.4, -5.6))
	place("crate_stack", Vector2(5.2, -6.4))
	place("garden_fence", Vector2(12.6, -6.2))
	place("garden_fence", Vector2(13.6, -6.2))
	# --- Atelier (façade vers l'est, baie ouverte avec forge) ---
	var wxf := place("workshop", Vector2(-13.4, 2.4), 1)
	place_in(wxf, "forge", Vector3(2.7, 0.6, 4.3), 0)
	place("storage_rack", Vector2(-12.8, -3.2), 1)
	place("materials_crate", Vector2(-9.6, -0.9), 1)
	place("supply_chest", Vector2(-9.7, 6.0), 1)
	place("tool_rack", Vector2(-10.1, 7.2), 1)
	# --- Port ---
	var pier_xf := place("pier", Vector2(1.8, 22.0), 0, 2.4)
	place("warehouse", Vector2(7.0, 12.4))
	var ship_xf := place("sky_ship", Vector2(6.3, 22.6), 3, 2.4, -2.6)
	place("mooring_post", Vector2(3.0, 18.9), 0, 2.4)
	place("mooring_post", Vector2(3.0, 25.4), 0, 2.4)
	place("crate_stack", Vector2(1.2, 19.6), 0, 2.4)
	place("barrel_set", Vector2(1.9, 24.6), 0, 2.4)
	place("crate_stack", Vector2(3.8, 16.9))
	place("barrel_set", Vector2(11.3, 16.6))
	place("utility_cart", Vector2(-1.5, 15.2), 0)
	place("crystal_lamp", Vector2(-0.7, 14.6), 0)
	place("crystal_lamp", Vector2(11.7, 14.6), 0)
	place("watch_tower", Vector2(14.2, 6.8))
	# --- Potager ---
	for bed in VillageLayout.BEDS:
		place("vegetable_bed", bed[0], 0)
	place("large_planter", Vector2(-9.2, 5.5))
	for x in range(-14, -3):
		var fx := float(x) + 0.5
		if absf(fx + 9.2) < 1.2:
			continue
		place("garden_fence", Vector2(fx, 6.1))
		place("garden_fence", Vector2(fx, 14.5))
	for z in range(7, 14):
		var fz := float(z) + 0.5
		if absf(fz - 10.4) < 1.2:
			continue
		place("garden_fence", Vector2(-14.5, fz), 1)
		place("garden_fence", Vector2(-3.9, fz), 1)
	place("tree_fruit_1", Vector2(-13.2, 12.9))
	place("tree_fruit_2", Vector2(-5.2, 13.3))
	# --- Colline de l'Ancre ---
	var c := VillageLayout.HILL_C
	var hill_y := VillageLayout.HILL_H
	place("teleport_anchor", c, 0, hill_y)
	place("anchor_pedestal", c, 0, hill_y, 0.84)
	place("ruin_arch", Vector2(-4.8, -17.6))
	place("ruin_column", Vector2(4.7, -17.2))
	place("ruin_column", Vector2(-6.8, -13.0))
	place("ruin_column", Vector2(6.9, -12.6))
	place("crystal_cluster", Vector2(5.4, -15.4))
	place("shrine_marker", Vector2(-3.9, -9.0), 0)
	place("brazier", Vector2(-2.1, -12.4), 0, hill_y)
	place("brazier", Vector2(2.1, -12.4), 0, hill_y)
	place("banner_stand", Vector2(-3.3, -11.6), 0, hill_y)
	place("banner_stand", Vector2(3.3, -11.6), 0, hill_y)
	# --- Belvédère ouest : balustrade, bancs, lampes, vue sur les nuages ---
	for i in 7:
		place("balustrade", Vector2(-19.6, -6.0 + i * 1.0), 1)
	place("decorative_bench", Vector2(-17.8, -4.7), 3)
	place("decorative_bench", Vector2(-17.8, -1.3), 3)
	place("crystal_lamp", Vector2(-19.0, -6.7))
	place("crystal_lamp", Vector2(-19.0, 0.7))
	place("large_planter", Vector2(-15.8, -6.0), 1)

func _place_nature() -> void:
	var d := island.data
	var pal := VoxelPalette.get_default()
	var grass := {}
	for k in ["grass", "grass_lush", "grass_dry", "grass_trim", "grass_wild", "grass_trampled"]:
		grass[pal.id(k)] = true
	var sxz := d.size().x
	var half := Vector2(sxz, sxz) * 0.5 * VoxelGrid.VOXEL_SIZE
	var trees: Array[Vector2] = []
	var species := {
		"hill": ["tree_oak_1", "tree_oak_2", "tree_parasol_1", "tree_oak_3"],
		"ne": ["tree_pine_1", "tree_pine_2", "tree_pine_1"],
		"west": ["tree_birch_1", "tree_birch_2", "tree_weeping_1", "tree_weeping_2"],
		"south": ["tree_parasol_2", "tree_oak_2", "tree_birch_1", "tree_fruit_1"],
		"village": ["tree_oak_3", "tree_birch_2", "tree_weeping_1"],
	}
	var attempts := 0
	while trees.size() < 34 and attempts < 2500:
		attempts += 1
		var p := Vector2(_rng.randf_range(-22.0, 22.0), _rng.randf_range(-22.0, 22.0))
		if p.length() > 19.5:
			continue
		var y := island.surface_y_at(p.x, p.y)
		if is_nan(y) or layout.reserved(p.x, p.y, 1.9):
			continue
		var col := Vector2i(floori(p.x / VoxelGrid.VOXEL_SIZE) - d.origin_cell.x, floori(p.y / VoxelGrid.VOXEL_SIZE) - d.origin_cell.z)
		if not grass.has(int(d.top_material[col.x + col.y * sxz])):
			continue
		var too_close := false
		for q in trees:
			if q.distance_to(p) < 3.6:
				too_close = true
				break
		if too_close:
			continue
		var zone := "village"
		if p.distance_to(VillageLayout.HILL_C) < 11.0:
			zone = "hill"
		elif p.x > 4.0 and p.y < -11.0:
			zone = "ne"
		elif p.x < -13.0:
			zone = "west"
		elif p.y > 11.0:
			zone = "south"
		elif p.length() < 14.0 and _rng.randf() < 0.65:
			continue      # le centre du village reste dégagé
		var list: Array = species[zone]
		trees.append(p)
		place(list[_rng.randi() % list.size()], p, _rng.randi() % 4, NAN, -0.2)
	# Rochers : sur les bords et les pentes.
	var rocks := 0
	attempts = 0
	while rocks < 16 and attempts < 1500:
		attempts += 1
		var ang := _rng.randf() * TAU
		var rr := _rng.randf_range(11.0, 20.5)
		var p := Vector2(cos(ang), sin(ang)) * rr
		var y := island.surface_y_at(p.x, p.y)
		if is_nan(y) or layout.reserved(p.x, p.y, 1.6):
			continue
		rocks += 1
		place("boulder_%d" % (1 + _rng.randi() % 4), p, _rng.randi() % 4, NAN, -0.1)
	_scatter_plants(grass)

## Herbes hautes, trèfles, fougères et fleurs (2 cm) : un MultiMesh par espèce et par cellule de 10 m.
func _scatter_plants(grass: Dictionary) -> void:
	var d := island.data
	var sxz := d.size().x
	var kinds := {"tuft": 2200, "clover": 800, "fern": 240, "flower_yellow": 240, "flower_violet": 180, "flower_white": 380}
	var lists := {}
	var used := {}
	for kind in kinds:
		lists[kind] = {}
		for i in kinds[kind]:
			var p := Vector2(_rng.randf_range(-22.0, 22.0), _rng.randf_range(-22.0, 22.0))
			if p.length() > 21.0:
				continue
			var cell := Vector2i(floori(p.x / 0.2), floori(p.y / 0.2))
			if used.has(cell) or layout.reserved(p.x, p.y, 0.25):
				continue
			var col := cell - Vector2i(d.origin_cell.x, d.origin_cell.z)
			if col.x < 0 or col.y < 0 or col.x >= sxz or col.y >= sxz or d.top[col.x + col.y * sxz] < 0:
				continue
			if not grass.has(int(d.top_material[col.x + col.y * sxz])):
				continue
			# Fleurs et fougères plus denses hors du centre ; pelouse entretenue plus rase.
			if kind != "tuft" and kind != "clover" and p.length() < 7.0:
				continue
			used[cell] = true
			var y := island.surface_y_at(p.x, p.y)
			var rot := Basis(Vector3.UP, (_rng.randi() % 4) * PI * 0.5)
			var half := Vector3(0.1, 0, 0.1)
			var base := Vector3(cell.x * 0.2, y, cell.y * 0.2)
			var key := Vector2i(floori(p.x / 10.0), floori(p.y / 10.0))
			if not lists[kind].has(key):
				lists[kind][key] = []
			lists[kind][key].append(Transform3D(rot, base + half - rot * half))
	var plants := Node3D.new()
	plants.name = "Plants"
	add_child(plants)
	for kind in lists:
		var vol := VegetationLibrary.build_plant(kind)
		# Deux niveaux : 2 cm de près (< 16 m), 4 cm plus loin (jusqu'à 48 m).
		var meshes := [
			VoxelMesher.build(vol, VoxelGrid.DETAIL_SIZE, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL),
			VoxelMesher.build(vol.downsample(2, 0.25), VoxelGrid.DETAIL_SIZE * 2.0, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL),
		]
		for key in lists[kind]:
			var xs: Array = lists[kind][key]
			for li in 2:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = meshes[li]
				mm.instance_count = xs.size()
				for i in xs.size():
					mm.set_instance_transform(i, xs[i])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "%s_%d_%d_P%d" % [kind, key.x, key.y, li]
				mmi.multimesh = mm
				mmi.visibility_range_begin = 0.0 if li == 0 else 16.0
				mmi.visibility_range_end = 16.0 if li == 0 else 48.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				plants.add_child(mmi)

func _collect_stats() -> void:
	var tris := 0
	var multimeshes := 0
	var instances := 0
	var mesh_instances := 0
	for n in find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		multimeshes += 1
		instances += mmi.multimesh.instance_count
	for n in find_children("*", "MeshInstance3D", true, false):
		mesh_instances += 1
	stats = {"props": scatter.stats, "multimeshes": multimeshes, "multimesh_instances": instances,
		"mesh_instances": mesh_instances, "island_generation_ms": island.last_generation_ms,
		"terrain_triangles": island.count_triangles()}

# ------------------------------------------------------------------ vues et ambiances

func _view(n: int) -> Array:
	match n:
		1: return [Vector3(2.0, 15.0, 50.0), Vector3(0.0, 3.0, -1.0)]       # le village
		2: return [Vector3(-3.0, 8.5, 6.0), Vector3(-9.3, 5.0, -9.0)]       # les bâtiments
		3: return [Vector3(2.4, 5.6, 7.0), Vector3(10.5, 4.6, -0.8)]        # le marché
		4: return [Vector3(6.5, 10.5, -4.5), Vector3(0.0, 8.0, -14.6)]      # l'Ancre
		5: return [Vector3(-8.0, 6.0, 31.0), Vector3(4.5, 3.4, 21.0)]       # le port
		6: return [Vector3(-3.4, 4.35, 5.4), Vector3(-4.6, 3.55, 1.4)]      # textures du terrain
		7: return [Vector3(-7.6, 4.9, 4.9), Vector3(-12.2, 4.4, 2.4)]       # détails des objets (forge)
		8: return [Vector3(-9.3, 4.5, -3.2), Vector3(-9.3, 5.2, -6.3)]      # matériaux : façade
		9: return [Vector3(-14.5, 6.0, -0.8), Vector3(-24.0, 2.0, -5.0)]    # belvédère et nuages
		0: return [Vector3(4.0, 5.2, 18.0), Vector3(7.5, 3.4, 22.6)]        # bateau volant
	return []

func _go_view(n: int) -> void:
	var v := _view(n)
	var cam := get_viewport().get_camera_3d() as FreeCamera
	if cam and not v.is_empty():
		cam.look_from(v[0], v[1])

func set_ambiance(i: int) -> void:
	rig.apply_preset_key(AMBIANCES[clampi(i, 0, AMBIANCES.size() - 1)])
	rig.refresh_lamps()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if Engine.is_editor_hint() or key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_0 and key.keycode <= KEY_9:
		_go_view(key.keycode - KEY_0)
	elif key.keycode == KEY_F5:
		set_ambiance(0)
	elif key.keycode == KEY_F6:
		set_ambiance(1)
	elif key.keycode == KEY_F7:
		set_ambiance(2)
	elif key.keycode == KEY_T:
		_tex_on = not _tex_on
		VoxelMaterials.set_global_param("tex_strength", 1.0 if _tex_on else 0.0)
