@tool
class_name WorldData
extends RefCounted
## Résultat complet de la génération d'une île : terrain, réservations, bâtiments, objets, végétation,
## rochers, port, bateau, rapport. Pur données : aucun nœud. Le même WorldData peut être rendu (WorldView),
## validé (WorldValidator) ou sérialisé en rapport.

var seed := 0
var profile: IslandProfile
var field: TerrainField
var island: IslandData
var occ: OccupancyMap
var placement: PlacementSystem
var paths: PathNetwork
var settlement: SettlementGenerator
var buildings: Array[Dictionary] = []   # {type, plan, model, arrays, res, xform, door, door_col, owner}
var props: Array[Dictionary] = []       # assets cuits : {id, xform, kind}
var trees: Array[Dictionary] = []       # {species, pos(Vector3), yaw, res, volume, ...}
var rocks: Array[Dictionary] = []
var plants: Array[Dictionary] = []      # {kind, transforms…} par amas
var port: Dictionary = {}               # {pier: {...}, xform, ship: {...}}
var ship: Dictionary = {}
var timings := {}                       # ms par phase
var stats := {}
var failures: Array[Dictionary] = []
var events: Array[String] = []          # journal : corrections et rejets (jamais silencieux)

func log_event(msg: String) -> void:
	events.append(msg)
