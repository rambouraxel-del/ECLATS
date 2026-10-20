@tool
class_name BuildingPlan
extends RefCounted
## Plan d'un bâtiment, indépendant du terrain et du moteur : tout est en CELLULES de 10 cm dans un
## repère canonique (x vers l'est, z vers le sud ; la façade d'entrée regarde +z ; y vers le haut).
## Le plan est la source unique de vérité : le constructeur de volumes, les colliders, le mobilier et
## le validateur lisent TOUS ce plan (aucun chiffre magique recopié ailleurs).
##
## Constantes de conception (personnage de 1,80 m) :
##   mur 20 cm · cloison 10 cm · hauteur libre 2,40 m · plancher d'étage 20 cm
##   porte d'entrée ≥ 1,00 × 2,10 m · porte intérieure ≥ 0,90 × 2,00 m
##   escalier : marche 20 cm × 30 cm, largeur ≥ 1,00 m, hauteur sous plafond ≥ 1,80 m

const WALL := 2             # épaisseur des murs porteurs (cellules)
const PART := 1             # épaisseur des cloisons
const FY := 4               # niveau du sol fini au-dessus du bas du volume (fondation 20 cm enterrée + 20 cm hors sol)
const GY := 2               # niveau du terrain fini dans le volume
const CLEAR := 24           # hauteur libre d'un niveau
const SLAB := 2             # épaisseur du plancher d'étage
const FLOOR_H := CLEAR + SLAB   # hauteur d'un niveau, sol à sol
const STEP_RISE := 2
const STEP_RUN := 3
const MIN_HEADROOM := 18    # 1,80 m
const DOOR_MAIN_W := 10
const DOOR_MAIN_H := 21
const DOOR_INT_W := 9
const DOOR_INT_H := 20

class Room extends RefCounted:
	var id := 0
	var floor := 0
	var x0 := 0      # intérieur, bornes incluses (cellules du repère du bâtiment)
	var z0 := 0
	var x1 := 0
	var z1 := 0
	var role := "living"
	var floor_material := "floor_planks"
	var annex := false
	func area_cells() -> int:
		return (x1 - x0 + 1) * (z1 - z0 + 1)
	func rect() -> Rect2i:
		return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)

class Opening extends RefCounted:
	var kind := "window"        # door | window | arch | hatch
	var wall := "S"             # S N E W (mur extérieur) ou "I" (cloison intérieure)
	var axis := 2               # axe perpendiculaire à la paroi : 2 = mur le long de x (normale z), 0 = mur le long de z
	var p := 0                  # position du plan de la paroi (z pour axis=2, x pour axis=0), cellule de la face extérieure
	var u := 0                  # premier indice le long de la paroi
	var w := 4
	var h := 5
	var sill := 0               # hauteur du bas de l'ouverture au-dessus du sol fini du niveau
	var floor := 0
	var thickness := 2
	var leaf := "none"          # none | single | double | shutters
	var main := false
	var rooms := Vector2i(-1, -1)   # pièces reliées (-1 = extérieur)
	var sign := 1               # côté extérieur (+1 / -1 sur l'axe de la normale)

class Wall extends RefCounted:
	var axis := 2               # 2 = le long de x à z fixe ; 0 = le long de z à x fixe
	var p := 0                  # coordonnée fixe de la première cellule
	var u0 := 0
	var u1 := 0                 # bornes incluses le long de la paroi
	var floor := 0
	var thickness := 2
	var exterior := true
	var material := "stone_rubble"

class Annex extends RefCounted:
	var x0 := 0
	var z0 := 0
	var x1 := 0                 # emprise extérieure incluse (cellules)
	var z1 := 0
	var kind := "lean_to"
	var eave := 20              # hauteur des murs côté bas (cellules au-dessus du sol fini)
	var slope_dir := Vector2i(1, 0)  # direction de descente du toit (x ou z)
	var wall_material := "plaster_worn_grey"
	var room_id := -1

class StairPlan extends RefCounted:
	var x0 := 0                 # emprise de l'escalier (cellules)
	var z0 := 0
	var w := 10
	var l := 39
	var dir := 1                # +1 : monte vers +z ; -1 : vers -z
	var from_floor := 0

var type := ""
var seed := 0
var floors := 1
var W := 60                     # bloc principal, hors tout (cellules)
var D := 48
var mx := 0                     # position du bloc principal dans l'emprise
var mz := 0
var footprint := Vector2i.ZERO  # emprise totale (bloc + annexes), cellules
var rooms: Array[Room] = []
var walls: Array[Wall] = []
var openings: Array[Opening] = []
var annexes: Array[Annex] = []
var stair: StairPlan
var hearth := {}                # {room, x, z, w, d, side}
var chimney := {}               # {x, z, w, d}
var roof := {}                  # {type, axis, pitch_num, pitch_den, overhang, material, patch}
var style := {}                 # matériaux : {wall_low, wall_up, trim, floor, wear, frame}
var furniture: Array = []       # [{role, room, count}]
var main_door := -1             # indice dans openings
var door_front := Vector2i.ZERO # cellule (x, z) juste devant la porte d'entrée, à l'extérieur
var archetype := {}

func size_m() -> Vector2:
	return Vector2(footprint) * VoxelGrid.STRUCTURE_SIZE

func room_at(floor_idx: int, x: int, z: int) -> Room:
	for r in rooms:
		if r.floor == floor_idx and x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1:
			return r
	return null

## Hauteur (cellules, depuis le bas du volume) du sol fini d'un niveau.
func floor_y(floor_idx: int) -> int:
	return FY + floor_idx * FLOOR_H

func total_height_cells() -> int:
	return floor_y(floors - 1) + CLEAR
