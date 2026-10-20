@tool
class_name AssetLibrary
extends RefCounted
## Registre des assets (objets, bâtiments, arbres, véhicule). Chaque entrée pointe vers un
## script de construction `build()` qui renvoie un VoxelAsset ; tools/bake_assets.gd génère
## ensuite scènes, maillages (avec niveaux de détail) et fiche JSON.
## Groupes : "lot2" (les 5 assets du Lot 2, retravaillés), "prop", "building", "tree", "vehicle".

const PROPS_DIR := "res://scripts/assets/props/"
const BUILDINGS_DIR := "res://scripts/assets/buildings/"
const ASSET_DIR := "res://assets/props"

# id → [groupe, script] ou [groupe, script, arguments passés à build(args)]
const REGISTRY := {
	# --- Lot 2, retravaillés ---
	"artisan_workbench": ["lot2", PROPS_DIR + "artisan_workbench.gd"],
	"ancient_chest": ["lot2", PROPS_DIR + "ancient_chest.gd"],
	"anchor_pedestal": ["lot2", PROPS_DIR + "anchor_pedestal.gd"],
	"market_stall": ["lot2", PROPS_DIR + "market_stall.gd"],
	"decorative_bench": ["lot2", PROPS_DIR + "decorative_bench.gd"],
}

static var _extra := {}
static var _info_cache := {}

## Les cinq assets du Lot 2 (compatibilité avec les tests existants).
static func ids() -> PackedStringArray:
	return ids_in("lot2")

static func all_ids() -> PackedStringArray:
	return PackedStringArray(_all().keys())

static func ids_in(group: String) -> PackedStringArray:
	var out := PackedStringArray()
	var all := _all()
	for k in all:
		if all[k][0] == group:
			out.append(k)
	return out

static func _all() -> Dictionary:
	if _extra.is_empty():
		_extra = REGISTRY.duplicate()
		var reg: GDScript = load("res://scripts/assets/asset_registry_lot3.gd")
		if reg:
			_extra.merge(reg.call("entries"))
	return _extra

static func group_of(id: String) -> String:
	return _all()[id][0]

## Construit la description procédurale (voxels) d'un asset.
static func build(id: String) -> VoxelAsset:
	var entry: Array = _all()[id]
	var script: GDScript = load(entry[1])
	var asset: VoxelAsset = script.call("build", entry[2]) if entry.size() > 2 else script.call("build")
	if asset.id == "":
		asset.id = id
	asset.category = _all()[id][0]
	return asset

## Scène Godot générée par tools/bake_assets.gd.
static func scene_path(id: String) -> String:
	return "%s/%s/%s.tscn" % [ASSET_DIR, id, id]

static func info_path(id: String) -> String:
	return "%s/%s/%s.info.json" % [ASSET_DIR, id, id]

static func instantiate(id: String) -> Node3D:
	var packed := load(scene_path(id)) as PackedScene
	return packed.instantiate() as Node3D if packed else null

## Fiche générée (pièces, maillages par niveau de détail, lumières, collisions, statistiques).
static func info(id: String) -> Dictionary:
	if not _info_cache.has(id):
		var text := FileAccess.get_file_as_string(info_path(id))
		var parsed = JSON.parse_string(text)
		_info_cache[id] = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _info_cache[id]
