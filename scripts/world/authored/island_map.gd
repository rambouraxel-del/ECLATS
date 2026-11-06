@tool
class_name IslandMap
extends RefCounted
## Carte d'une île FIXE (Lot 5) : fichier JSON éditable (config/islands/*.json). Toutes les positions sont en
## mètres (x vers l'est, z vers le sud) ; les hauteurs des objets sont calculées sur le relief à la construction.
## La signature (hash du fichier + version du constructeur) sert de clé de cache : modifier la carte reconstruit l'île.

const DEFAULT_PATH := "res://config/islands/ile_ouverture.json"

static func load_map(path := DEFAULT_PATH) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Carte d'île invalide : %s" % path)
		return {}
	var map: Dictionary = parsed
	map["_path"] = path
	map["_hash"] = "%08x" % WorldRng.fnv(text)
	return map

static func v2(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))

static func pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out
