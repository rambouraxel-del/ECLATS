@tool
class_name PlacementSpec
extends RefCounted
## Métadonnées de placement d'un élément du monde (arbre, rocher, bâtiment, objet, meuble…).
## Repère local : origine = centre de l'emprise, au niveau du sol (base) ; x vers l'est, z vers le sud.
## Le même système valide un arbre, une maison ou (plus tard) une pose du joueur.

# Raisons de rejet (clés du rapport de placement).
const R_OUT := "hors_ile"
const R_CLIFF := "trop_pres_du_bord"
const R_ZONE := "zone_interdite"
const R_MATERIAL := "matiere_interdite"
const R_RESERVED := "espace_reserve"
const R_SLOPE := "pente_excessive"
const R_SUPPORT := "support_insuffisant"
const R_CORE := "intersecte_le_coeur"
const R_COLLISION := "collision"
const R_SOFT := "volume_mou_dans_construction"
const R_ACCESS := "inaccessible"
const R_DEPTH := "surface_trop_mince"
const R_INTERIOR := "hors_de_la_piece"

# Étiquettes de réservation d'espace (OccupancyMap).
const TAG_FREE := 0
const TAG_PLAZA := 1
const TAG_ROAD := 2
const TAG_PLOT := 3
const TAG_ITEM := 4
const TAG_GARDEN := 5
const TAG_PORT := 6
const TAG_NAMES := ["libre", "place", "chemin", "parcelle", "objet", "jardin", "port"]

var id := ""
var kind := "prop"                      # tree | rock | building | prop | interior | structure | plant
var size := Vector3(1, 1, 1)            # emprise englobante (m) : x, hauteur, z
var hard: Array[AABB] = []              # volumes qui bloquent (repère local centre-bas)
var soft: Array[AABB] = []              # volumes qui peuvent se chevaucher (couronne, décor)
var support := "ground"                 # ground | none (pont, passerelle) | floor (intérieur)
var support_fraction := 0.85            # part de l'emprise qui doit toucher le sol
var gap_tolerance_m := 0.2              # vide maximal toléré sous l'objet
var embed_max_m := 0.0                  # enfoncement admis (racines, fondations), dans la surface seulement
var clearance_m := 0.0                  # distance minimale aux autres volumes durs (m)
var allowed_zones := PackedInt32Array() # TerrainField.Zone autorisées (vide = naturel + jardin)
var allowed_tags := PackedInt32Array()  # étiquettes d'espace autorisées (vide = libre)
var forbidden_materials := PackedStringArray()
var cliff_margin_m := 0.8
var needs_access := false
var access_radius_m := 1.6
var exceptions := PackedStringArray()   # overhang_void, climbing, on_road, in_building
var yaw_options := PackedInt32Array([0, 1, 2, 3])
var snap_m := 0.2                       # alignement sur la grille (0 = aucun)
var overhang_fraction := 0.0            # part de l'emprise autorisée au-dessus du vide (exception overhang_void)
var soft_overlap_max := 0.35            # recouvrement maximal entre deux volumes mous
var soft_blocks_kinds := PackedStringArray(["building", "structure"])  # volumes durs que la couronne ne doit pas pénétrer
var origin_offset := Vector3.ZERO       # décalage origine de l'asset → centre-bas (assets à origine en coin)
var meta := {}

func allows_exception(name: String) -> bool:
	return exceptions.has(name)

## Emprise (demi-dimensions en x, z) après rotation de yaw × 90°.
func half_extents(yaw: int) -> Vector2:
	return Vector2(size.z, size.x) * 0.5 if yaw % 2 == 1 else Vector2(size.x, size.z) * 0.5

static func rotate_box(b: AABB, yaw: int) -> AABB:
	var basis := Basis(Vector3.UP, yaw * PI * 0.5)
	var a := basis * b.position
	var c := basis * b.end
	var lo := Vector3(minf(a.x, c.x), minf(a.y, c.y), minf(a.z, c.z))
	var hi := Vector3(maxf(a.x, c.x), maxf(a.y, c.y), maxf(a.z, c.z))
	return AABB(lo, hi - lo)

# ------------------------------------------------------------------ constructeurs

## Depuis la fiche JSON d'un asset (origine en coin minimum de l'emprise).
static func from_asset_info(info: Dictionary, kind_name := "prop") -> PlacementSpec:
	var s := PlacementSpec.new()
	s.id = info["id"]
	s.kind = kind_name
	var sz := Vector3(info["size_m"][0], info["size_m"][1], info["size_m"][2])
	s.size = sz
	var center := Vector3(sz.x * 0.5, 0.0, sz.z * 0.5)
	s.origin_offset = center
	for c in info.get("colliders", []):
		var lo := Vector3(c["position"][0], c["position"][1], c["position"][2]) - center
		s.hard.append(AABB(lo, Vector3(c["size"][0], c["size"][1], c["size"][2])))
	if s.hard.is_empty():
		s.hard.append(AABB(Vector3(-sz.x * 0.5, 0, -sz.z * 0.5), sz))
	return s
