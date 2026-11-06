class_name GameSave
extends RefCounted
## Sauvegarde locale (user://eclats_sauvegarde.json). L'état de chaque île est rangé sous son identifiant FIXE
## (champ `id` de la carte, ex. « ile-ouverture-01 ») : il est retrouvé à la relance.

const PATH := "user://eclats_sauvegarde.json"
const VERSION := 1

static func load_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {"version": VERSION, "islands": {}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"version": VERSION, "islands": {}}
	var d: Dictionary = parsed
	if not d.has("islands"):
		d["islands"] = {}
	return d

static func island(id: String) -> Dictionary:
	return (load_all()["islands"] as Dictionary).get(id, {})

static func set_island(id: String, state: Dictionary) -> bool:
	var d := load_all()
	(d["islands"] as Dictionary)[id] = state
	d["version"] = VERSION
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("Sauvegarde impossible : %s" % PATH)
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return true

static func clear_island(id: String) -> void:
	var d := load_all()
	(d["islands"] as Dictionary).erase(id)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "\t"))
