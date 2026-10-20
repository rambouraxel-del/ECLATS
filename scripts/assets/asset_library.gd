@tool
class_name AssetLibrary
extends RefCounted
## Registre des assets détaillés du Lot 2. Ordre = ordre de présentation.

const BUILDERS := {
	"artisan_workbench": "res://scripts/assets/props/artisan_workbench.gd",
	"ancient_chest": "res://scripts/assets/props/ancient_chest.gd",
	"anchor_pedestal": "res://scripts/assets/props/anchor_pedestal.gd",
	"market_stall": "res://scripts/assets/props/market_stall.gd",
	"decorative_bench": "res://scripts/assets/props/decorative_bench.gd",
}
const ASSET_DIR := "res://assets/props"

static func ids() -> PackedStringArray:
	return PackedStringArray(BUILDERS.keys())

## Construit la description procédurale (voxels) d'un asset.
static func build(id: String) -> VoxelAsset:
	var script: GDScript = load(BUILDERS[id])
	return script.call("build")

## Scène Godot générée par tools/bake_assets.gd.
static func scene_path(id: String) -> String:
	return "%s/%s/%s.tscn" % [ASSET_DIR, id, id]

static func instantiate(id: String) -> Node3D:
	var packed := load(scene_path(id)) as PackedScene
	return packed.instantiate() as Node3D if packed else null
