@tool
class_name BuildingPlacement
extends RefCounted
## Pont entre un BuildingPlan et le système de placement : spec (emprise, volumes durs, règles de sol),
## position de la porte dans le monde, transformation du nœud. Aucune dépendance à une île précise.

const C := VoxelGrid.STRUCTURE_SIZE
const P := preload("res://scripts/world/building/building_plan.gd")

static func spec_for(plan: BuildingPlan) -> PlacementSpec:
	var s := PlacementSpec.new()
	s.id = "bld_%s_%d" % [plan.type, plan.seed]
	s.kind = "building"
	var fp := Vector2(plan.footprint) * C
	var h := float(plan.max_height_cells()) * C
	s.size = Vector3(fp.x, h, fp.y)
	s.origin_offset = Vector3(fp.x * 0.5, 0.0, fp.y * 0.5)
	# volume dur = emprise bâtie : la cour devant la façade et la frange latérale restent praticables
	var body := plan.body_rect()
	s.hard = [AABB(Vector3(float(body.position.x) * C - fp.x * 0.5, 0.0, float(body.position.y) * C - fp.y * 0.5), Vector3(body.size.x, 0.0, body.size.y) * C + Vector3(0.0, h, 0.0))]
	s.support = "ground"
	s.support_fraction = 0.97
	s.gap_tolerance_m = 0.0
	s.embed_max_m = 0.0
	s.clearance_m = 0.5
	s.cliff_margin_m = 0.8
	s.allowed_zones = PackedInt32Array([TerrainField.Zone.PLOT])
	s.allowed_tags = PackedInt32Array([PlacementSpec.TAG_PLOT])
	s.snap_m = 0.2
	s.meta = {"type": plan.type}
	return s

## Transformation du nœud du bâtiment (origine locale = coin minimum du volume, 20 cm sous le terrain fini).
static func node_transform(res: PlacementResult) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, -float(P.GY) * C, 0.0)) * res.asset_transform()

## Cellule du monde (mètres, x/z) située juste devant la porte d'entrée.
static func door_world(plan: BuildingPlan, res: PlacementResult) -> Vector2:
	var local := Vector3((float(plan.door_front.x) + 0.5) * C, 0.0, (float(plan.door_front.y) + 0.5) * C)
	var w := res.asset_transform() * local
	return Vector2(w.x, w.z)

## Normale de la façade d'entrée dans le monde (x, z).
static func front_dir(res: PlacementResult) -> Vector2:
	var d := res.basis() * Vector3(0, 0, 1)
	return Vector2(d.x, d.z)
