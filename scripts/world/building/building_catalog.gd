@tool
class_name BuildingCatalog
extends RefCounted
## Bibliothèque d'archétypes architecturaux d'ÉCLATS : colonies de SURVIVANTS, des siècles après la
## chute des grandes civilisations. Pauvres en technologie, bâties avec ce qu'on trouve :
##   pierre ancienne irrégulière (moellons), bois vieilli, poutres et charpentes apparentes, enduits
##   usés qui laissent voir la maçonnerie, toitures rustiques (chaume, bardeaux, tuiles et lauzes
##   rapiécées), ouvertures étroites, volets, claustras et toiles, réparations et extensions successives,
##   éléments récupérés dans les ruines (linteaux sculptés, tambours de colonne, cristaux éteints).
## À ÉVITER : grandes baies vitrées, carrelage, façades symétriques et « propres », toits en escalier.
## Chaque archétype décrit un PROGRAMME (pièces, fonctions), jamais une coordonnée.

const TYPES := ["house_small", "house_large", "workshop", "warehouse", "shop", "community_hall"]

const ARCHETYPES := {
	"house_small": {
		"name": "Maison", "floors": [1, 1], "w": [60, 72], "d": [46, 56],
		"wall_styles": ["stone", "plaster", "timber"], "roofs": ["thatch", "shingle", "tiles", "slate"],
		"annex_chance": 0.45, "main_door_w": 10,
		"rooms": ["living", "bedroom"], "hearth": "living",
	},
	"house_large": {
		"name": "Grande maison", "floors": [2, 2], "w": [74, 90], "d": [60, 70],
		"wall_styles": ["plaster", "timber", "stone"], "roofs": ["shingle", "tiles", "slate"],
		"annex_chance": 0.6, "main_door_w": 10,
		"rooms": ["hall", "stairs", "kitchen", "chamber", "chamber"], "hearth": "hall",
	},
	"workshop": {
		"name": "Atelier", "floors": [1, 1], "w": [72, 90], "d": [58, 68],
		"wall_styles": ["stone", "timber"], "roofs": ["shingle", "slate", "tiles"],
		"annex_chance": 0.5, "main_door_w": 14,
		"rooms": ["workroom", "store"], "hearth": "workroom",
	},
	"warehouse": {
		"name": "Entrepôt", "floors": [1, 1], "w": [96, 120], "d": [62, 76],
		"wall_styles": ["timber", "stone"], "roofs": ["shingle", "slate", "thatch"],
		"annex_chance": 0.35, "main_door_w": 20,
		"rooms": ["storage"], "hearth": "",
	},
	"shop": {
		"name": "Échoppe", "floors": [1, 1], "w": [66, 84], "d": [52, 64],
		"wall_styles": ["plaster", "timber"], "roofs": ["shingle", "tiles", "thatch"],
		"annex_chance": 0.4, "main_door_w": 10,
		"rooms": ["shop", "store"], "hearth": "store",
	},
	"community_hall": {
		"name": "Maison commune", "floors": [1, 1], "w": [104, 130], "d": [66, 80],
		"wall_styles": ["stone", "timber"], "roofs": ["slate", "shingle", "tiles"],
		"annex_chance": 0.5, "main_door_w": 14,
		"rooms": ["hall", "kitchen"], "hearth": "hall",
	},
}

## Matières de chaque style de mur : [bas (moellons), haut].
const WALL_STYLES := {
	"stone": {"low": ["stone_rubble", "stone_rubble_warm", "stone_rubble_dark"], "up": ["stone_rubble", "stone_rubble_warm", "stone_rubble"], "timber": false},
	"plaster": {"low": ["stone_rubble", "stone_rubble_dark"], "up": ["plaster_worn_cream", "plaster_worn_ochre", "plaster_worn_grey"], "timber": false},
	"timber": {"low": ["stone_rubble", "stone_rubble_warm"], "up": ["plaster_worn_cream", "plaster_worn_grey", "plaster_worn_ochre"], "timber": true},
}

const ROOF_STYLES := {
	"thatch": {"materials": ["thatch", "thatch_old"], "pitch": [1, 1], "thick": 7, "overhang": 4},
	"shingle": {"materials": ["shingle_aged", "wood_pale_old"], "pitch": [4, 5], "thick": 3, "overhang": 3},
	"tiles": {"materials": ["tiles_patched", "tiles_terracotta"], "pitch": [3, 5], "thick": 3, "overhang": 3},
	"slate": {"materials": ["slate_old", "tiles_slate"], "pitch": [3, 5], "thick": 3, "overhang": 3},
}

static func get_archetype(type: String) -> Dictionary:
	return ARCHETYPES[type]
