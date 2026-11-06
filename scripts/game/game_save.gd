class_name GameSave
extends RefCounted
## Sauvegarde locale (user://eclats_sauvegarde.json). L'état de chaque île est rangé sous son identifiant FIXE
## (champ `id` de la carte, ex. « ile-ouverture-01 ») : il est retrouvé à la relance.
## Lot 11 : écritures SÛRES (fichier temporaire vérifié, ancienne version gardée en .bak) ; si le fichier principal est illisible,
## la dernière version exploitable (.bak) est relue. `last_error` : dernière erreur d'écriture, lisible par l'utilisateur.

static var PATH := "user://eclats_sauvegarde.json"
const VERSION := 1
static var last_error := ""
static var recovered_from_backup := false

static func _empty() -> Dictionary:
	return {"version": VERSION, "islands": {}}

static func load_all() -> Dictionary:
	recovered_from_backup = false
	var r := SafeFile.read_json(PATH)
	if not bool(r["ok"]):
		return _empty()
	recovered_from_backup = bool(r["from_backup"])
	var d: Dictionary = r["data"]
	if typeof(d.get("islands", {})) != TYPE_DICTIONARY:
		d["islands"] = {}
	if not d.has("islands"):
		d["islands"] = {}
	return d

static func island(id: String) -> Dictionary:
	return (load_all()["islands"] as Dictionary).get(id, {})

static func _write(d: Dictionary) -> bool:
	var verify := func(text: String) -> String:
		var p = JSON.parse_string(text)
		return "" if typeof(p) == TYPE_DICTIONARY and p.has("islands") else "le contenu relu n'est pas une sauvegarde valide"
	var r := SafeFile.write_text(PATH, JSON.stringify(d, "\t"), verify)
	last_error = "" if bool(r["ok"]) else String(r["error"])
	if not bool(r["ok"]):
		push_error("Sauvegarde impossible : %s" % last_error)
	return bool(r["ok"])

## Renvoie true seulement si la progression est réellement écrite (et relue).
static func set_island(id: String, state: Dictionary) -> bool:
	var d := load_all()
	(d["islands"] as Dictionary)[id] = state
	d["version"] = VERSION
	return _write(d)

static func clear_island(id: String) -> bool:
	var d := load_all()
	(d["islands"] as Dictionary).erase(id)
	return _write(d)
