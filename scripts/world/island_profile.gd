@tool
class_name IslandProfile
extends RefCounted
## Profil de génération réutilisable (config/profiles/*.json) : décrit un TYPE d'île, jamais une île
## précise. Une île = un profil + une graine. Les valeurs sont des plages [min, max] tirées par le
## générateur avec ses flux déterministes ; aucune coordonnée n'est écrite dans un profil.
##   verdant : île verdoyante, douce, sans village.
##   rocky   : île rocheuse, reliefs marqués, falaises, peu de plateaux.
##   settled : île habitée (village, port, chemins, jardins).

const DIR := "res://config/profiles/"

var key := ""
var data := {}

static func load_profile(profile_key: String) -> IslandProfile:
	var p := IslandProfile.new()
	p.key = profile_key
	var path := DIR + profile_key + ".json"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Profil d'île invalide : %s" % path)
		return p
	p.data = parsed
	return p

static func keys() -> PackedStringArray:
	return PackedStringArray(["verdant", "rocky", "settled"])

## Valeur imbriquée : g("relief.base_m", 2.0).
func g(path: String, default: Variant = null) -> Variant:
	var cur: Variant = data
	for part in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not (cur as Dictionary).has(part):
			return default
		cur = cur[part]
	return cur

func has_settlement() -> bool:
	return bool(g("settlement.enabled", false))
