class_name AssetCatalog
extends RefCounted
## CATALOGUE DE L'INVENTAIRE CRÉATIF : les assets du jeu (registre AssetLibrary, mêmes fiches que la galerie 3D) rangés en catégories
## de création, plus les maisons enregistrées dans l'atelier (user://maisons/) et la maison d'exemple.
## Un élément : {id, name, cat, kind ("asset" | "modele"), size (Vector3 m), path (modèles)}.

const CATS := ["Arbres", "Rochers", "Ruines et vestiges", "Mobilier", "Marché et village", "Maisons", "Port et navires", "Mes maisons"]
const HOUSE_DIRS := ["res://assets/maisons/", "user://maisons/"]

const BY_ID := {
	"boulder_1": "Rochers", "boulder_2": "Rochers", "boulder_3": "Rochers", "boulder_4": "Rochers", "crystal_cluster": "Rochers",
	"ruin_arch": "Ruines et vestiges", "ruin_column": "Ruines et vestiges", "shrine_marker": "Ruines et vestiges", "ancient_chest": "Ruines et vestiges",
	"anchor_pedestal": "Ruines et vestiges", "teleport_anchor": "Ruines et vestiges",
	"house_colonist": "Maisons", "house_cottage": "Maisons", "workshop": "Maisons", "warehouse": "Maisons", "watch_tower": "Maisons",
	"pier": "Port et navires", "sky_ship": "Port et navires", "mooring_post": "Port et navires",
	"market_stall": "Marché et village", "canopy_kiosk": "Marché et village", "notice_board": "Marché et village", "signpost": "Marché et village",
	"banner_stand": "Marché et village", "water_well": "Marché et village", "pedestal_fountain": "Marché et village", "garden_fence": "Marché et village",
	"balustrade": "Marché et village", "vegetable_bed": "Marché et village", "large_planter": "Marché et village",
}

static func category_of(id: String) -> String:
	if BY_ID.has(id):
		return BY_ID[id]
	if id.begins_with("tree_"):
		return "Arbres"
	return "Mobilier"

## Tous les éléments, triés par catégorie puis par nom.
static func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in AssetLibrary.all_ids():
		var info := AssetLibrary.info(id)
		var sz: Array = info.get("size_m", [1, 1, 1])
		out.append({"id": id, "name": String(info.get("name", id)), "cat": category_of(id), "kind": "asset",
			"size": Vector3(float(sz[0]), float(sz[1]), float(sz[2]))})
	for m in houses():
		out.append(m)
	out.sort_custom(func(a, b) -> bool:
		var ca := CATS.find(a["cat"])
		var cb := CATS.find(b["cat"])
		return ca < cb if ca != cb else String(a["name"]) < String(b["name"]))
	return out

## Modèles de maisons enregistrés (atelier de construction) et maison d'exemple.
static func houses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in HOUSE_DIRS:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".eclats-maison.json"):
				out.append({"id": d + f, "name": f.replace(".eclats-maison.json", "").replace("_", " ").capitalize(), "cat": "Mes maisons", "kind": "modele",
					"size": Vector3.ZERO, "path": d + f})
	return out

## Filtre par catégorie ("" = toutes) et par texte (sans accents ni casse, tous les mots).
static func search(all: Array, cat: String, text: String) -> Array[Dictionary]:
	var words := _norm(text).split(" ", false)
	var out: Array[Dictionary] = []
	for it in all:
		if cat != "" and String(it["cat"]) != cat:
			continue
		var hay := _norm("%s %s %s" % [it["name"], it["id"], it["cat"]])
		var ok := true
		for w in words:
			if hay.find(w) < 0:
				ok = false
				break
		if ok:
			out.append(it)
	return out

static func _norm(s: String) -> String:
	return s.to_lower().replace("é", "e").replace("è", "e").replace("ê", "e").replace("à", "a").replace("â", "a").replace("ô", "o").replace("î", "i").replace("ç", "c").replace("ï", "i").replace("û", "u").replace("ù", "u")
