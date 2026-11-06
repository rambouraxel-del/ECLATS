class_name VoxelProtoIsland
extends Node3D
## Prototype C — l'île du plan en blocs de 20 cm avec VOXEL TOOLS (VoxelTerrain + VoxelMesherBlocky + VoxelGeneratorScript).
## Fonctionne UNIQUEMENT dans un moteur Godot qui embarque le module Voxel Tools (voir docs/COMPARATIF_TERRAIN.md) ; dans le moteur
## standard, `available()` est faux et rien n'est instancié (aucune classe Voxel n'est nommée dans ce fichier : tout passe par ClassDB).
## Services identiques à LabWorld pour la scène de l'île : `spawn`, `ground_y()`, `field` (squelette du plan, pour les requêtes de plan).

const V := 0.2
const GEN_SCRIPT := "res://scripts/voxel_proto/voxel_gen.gd"
const MATERIAL_SHADER := "res://materials/voxel_blocky.gdshader"

var plan: IslandPlan
var build: PlanTerrain.Build            # squelette (méthode S)
var field: TerrainField
var terrain: Node3D                     # VoxelTerrain
var gen: Object                         # VoxelGeneratorScript
var viewer: Node3D                      # VoxelViewer
var spawn := Vector3.ZERO
var stream: Object = null               # VoxelStreamSQLite (sauvegarde des retouches)
var db_path := ""
var mesh_material: ShaderMaterial
var setup_ms := 0
var ready_ms := 0                       # du lancement du chargement à « tout maillé »
var edits: Array = []                   # journal des coups de pinceau (pour comparer / rejouer)

static func available() -> bool:
	return ClassDB.class_exists("VoxelTerrain") and ClassDB.class_exists("VoxelGeneratorScript") and ClassDB.class_exists("ZN_FastNoiseLite")

static func version_text() -> String:
	if not available():
		return "Voxel Tools absent de ce moteur"
	if Engine.has_singleton("VoxelEngine"):
		var e := Engine.get_singleton("VoxelEngine")
		if e.has_method("get_version_string"):
			return String(e.call("get_version_string"))
	return "Voxel Tools"

## Bloc de lecture : bornes du terrain en voxels (x, y, z).
func bounds_voxels() -> AABB:
	var lo := 1000000
	var hi := -1000000
	for t in field.top:
		if t != TerrainField.NO_GROUND:
			lo = mini(lo, t)
			hi = maxi(hi, t)
	var y0 := lo - 16
	var y1 := hi + 60
	return AABB(Vector3(field.origin.x, y0, field.origin.y), Vector3(field.n, y1 - y0, field.n))

func setup(p_plan: IslandPlan, p_build: PlanTerrain.Build, p_db := "") -> void:
	var t0 := Time.get_ticks_msec()
	plan = p_plan
	build = p_build
	field = p_build.field
	var pal := VoxelPalette.get_default()
	gen = (load(GEN_SCRIPT) as GDScript).new()
	gen.call("setup", field, build, plan.seed, pal)
	var lib: Object = ClassDB.instantiate("VoxelBlockyLibrary")
	var models: Array = []
	var empty: Object = ClassDB.instantiate("VoxelBlockyModelEmpty")
	models.append(empty)
	for id in range(1, pal.count()):
		var m: Object = ClassDB.instantiate("VoxelBlockyModelCube")
		m.set("atlas_size_in_tiles", Vector2i(1, 1))
		m.set("color", pal.colors_linear[id])
		for side in 6:
			m.call("set_tile", side, Vector2i(0, 0))
		models.append(m)
	lib.set("models", models)
	var mesher: Object = ClassDB.instantiate("VoxelMesherBlocky")
	mesher.set("library", lib)
	mesher.set("occlusion_enabled", true)
	mesher.set("occlusion_darkness", 0.45)
	mesh_material = ShaderMaterial.new()
	mesh_material.shader = load(MATERIAL_SHADER) as Shader
	terrain = ClassDB.instantiate("VoxelTerrain") as Node3D
	terrain.name = "VoxelTerrain"
	terrain.set("mesher", mesher)
	terrain.set("generator", gen)
	terrain.set("material_override", mesh_material)
	terrain.set("generate_collisions", true)
	terrain.set("collision_layer", 1)
	terrain.set("collision_mask", 0)
	var bb := bounds_voxels()
	terrain.set("bounds", bb)
	terrain.set("max_view_distance", int(maxf(bb.size.x, bb.size.z)) + 64)
	if p_db != "":
		db_path = p_db
		stream = ClassDB.instantiate("VoxelStreamSQLite")
		stream.set("database_path", ProjectSettings.globalize_path(p_db))
		terrain.set("stream", stream)
	terrain.scale = Vector3.ONE * V
	add_child(terrain)
	viewer = ClassDB.instantiate("VoxelViewer") as Node3D
	viewer.name = "VoxelViewer"
	viewer.set("view_distance", int(maxf(bb.size.x, bb.size.z)) + 32)
	viewer.set("requires_collisions", true)
	viewer.set("requires_visuals", true)
	add_child(viewer)
	_place_viewer()
	setup_ms = Time.get_ticks_msec() - t0

## Le visionneur au centre de l'île, à la hauteur de la surface (les blocs sont demandés autour de lui).
func _place_viewer() -> void:
	var c := Vector3((float(field.origin.x) + field.n * 0.5) * V, 4.0, (float(field.origin.y) + field.n * 0.5) * V)
	viewer.global_position = c

## Attend que tout le terrain soit généré, maillé et que les collisions existent. Renvoie la durée (ms).
func wait_loaded(timeout_ms := 600000) -> int:
	var t0 := Time.get_ticks_msec()
	var bb := bounds_voxels()
	var quiet := 0
	while Time.get_ticks_msec() - t0 < timeout_ms:
		await get_tree().process_frame
		if _idle():
			quiet += 1
		else:
			quiet = 0
		if quiet >= 6 and bool(terrain.call("is_area_meshed", bb)):
			break
	ready_ms = Time.get_ticks_msec() - t0
	_compute_spawn()
	return ready_ms

func _idle() -> bool:
	if not Engine.has_singleton("VoxelEngine"):
		return true
	var st: Dictionary = Engine.get_singleton("VoxelEngine").call("get_stats")
	var tasks: Dictionary = st.get("tasks", {})
	var total := 0
	for k in tasks:
		total += int(tasks[k])
	return total == 0

func _compute_spawn() -> void:
	var s := plan.start
	spawn = Vector3(s.x, ground_y(s.x, s.y) + 0.1, s.y)

## Hauteur du sol (m) lue dans les VOXELS (retouches comprises), ou NAN.
func ground_y(x: float, z: float) -> float:
	if terrain == null:
		return NAN
	var vt: Object = terrain.call("get_voxel_tool")
	var vx := floori(x / V)
	var vz := floori(z / V)
	var h: int = int(gen.call("height_at", vx, vz))
	if h <= -1000000:
		return NAN
	for y in range(h + 40, h - 12, -1):
		if int(vt.call("get_voxel", Vector3i(vx, y, vz))) != 0:
			return float(y + 1) * V
	return NAN

func has_ground_m(x: float, z: float) -> bool:
	return not is_nan(ground_y(x, z))

## Un coup de pinceau « relever » : boule de roche/herbe ajoutée (VoxelTool mode ADD), rayon en mètres, centre en mètres.
func sculpt_dab(center: Vector3, radius_m: float, raise := true) -> void:
	var vt: Object = terrain.call("get_voxel_tool")
	vt.set("channel", 0)            # CHANNEL_TYPE
	vt.set("mode", 1 if raise else 2)   # MODE_ADD / MODE_REMOVE
	vt.set("value", VoxelPalette.get_default().id("grass"))
	vt.call("do_sphere", center / V, radius_m / V)
	edits.append({"c": center, "r": radius_m, "raise": raise})

## Voxels de la colonne (x, z) : liste (type) du haut vers le bas sur `depth` voxels, pour comparer deux états.
func column_signature(x: float, z: float, depth := 24) -> PackedInt32Array:
	var vt: Object = terrain.call("get_voxel_tool")
	var vx := floori(x / V)
	var vz := floori(z / V)
	var h: int = int(gen.call("height_at", vx, vz)) + 30
	var out := PackedInt32Array()
	for y in range(h, h - depth - 30, -1):
		out.append(int(vt.call("get_voxel", Vector3i(vx, y, vz))))
	return out

## Empreinte de tout le terrain lu dans les voxels (hauteur de surface par colonne), pour la reproductibilité.
func surface_hash(step := 1) -> int:
	var vt: Object = terrain.call("get_voxel_tool")
	var acc := PackedInt32Array()
	var n := field.n
	for cz in range(0, n, step):
		for cx in range(0, n, step):
			var h: int = int(gen.call("height_at", field.origin.x + cx, field.origin.y + cz))
			acc.append(h)
	return hash(acc)

func save_edits() -> int:
	if terrain == null or stream == null:
		return -1
	var t0 := Time.get_ticks_msec()
	var tr: Object = terrain.call("save_modified_blocks")
	while tr != null and not bool(tr.call("is_complete")):
		await get_tree().process_frame
	return Time.get_ticks_msec() - t0
