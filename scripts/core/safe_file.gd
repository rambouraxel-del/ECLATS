class_name SafeFile
extends RefCounted
## ÉCRITURE SÛRE d'un fichier texte (cartes, constructions, progression) :
##   1. écriture dans « fichier.tmp » ; 2. relecture et vérification (contenu identique, et `verify` si fourni) ;
##   3. l'ancienne version devient « fichier.bak » ; 4. le .tmp prend la place du fichier final.
## En cas d'échec à n'importe quelle étape, le fichier final et la dernière version exploitable (.bak) restent intacts
## et une erreur lisible est renvoyée. `fail_at` (tests) simule une panne : "" | "open" | "write" | "verify" | "replace".

static var fail_at := ""

static func backup_path(path: String) -> String:
	return path + ".bak"

static func _err(msg: String, path: String) -> Dictionary:
	return {"ok": false, "error": "%s (%s). Le fichier précédent est conservé." % [msg, path.get_file()], "path": path}

## verify : Callable(text) -> String ("" si le contenu est exploitable, sinon la raison).
static func write_text(path: String, text: String, verify := Callable()) -> Dictionary:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tmp"
	if fail_at == "open":
		return _err("Impossible de créer le fichier temporaire (accès refusé)", path)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _err("Impossible d'écrire (erreur %d)" % FileAccess.get_open_error(), path)
	f.store_string(text)
	var werr := f.get_error()
	f.close()
	if fail_at == "write" or werr != OK:
		DirAccess.remove_absolute(tmp)
		return _err("Écriture interrompue (disque plein ou accès refusé)", path)
	var back := FileAccess.get_file_as_string(tmp)
	var why := "contenu écrit différent du contenu prévu" if (fail_at == "verify" or back != text) else ""
	if why == "" and verify.is_valid():
		why = String(verify.call(back))
	if why != "":
		DirAccess.remove_absolute(tmp)
		return _err("Vérification après écriture échouée : %s" % why, path)
	var had := FileAccess.file_exists(path)
	var old := path + ".old"
	if had:
		DirAccess.remove_absolute(old)
		if DirAccess.rename_absolute(path, old) != OK:
			DirAccess.remove_absolute(tmp)
			return _err("Impossible de mettre à l'abri la version précédente", path)
	if fail_at == "replace" or DirAccess.rename_absolute(tmp, path) != OK:
		if had:
			DirAccess.rename_absolute(old, path)       # on remet la version précédente ; l'ancienne sauvegarde (.bak) n'a pas bougé
		DirAccess.remove_absolute(tmp)
		return _err("Impossible de remplacer le fichier", path)
	if had:
		DirAccess.remove_absolute(backup_path(path))
		DirAccess.rename_absolute(old, backup_path(path))
	return {"ok": true, "path": path}

## Lit un fichier ; si le fichier final est absent ou illisible (JSON) et qu'une sauvegarde .bak existe, la renvoie avec `from_backup`.
static func read_json(path: String) -> Dictionary:
	for k in 2:
		var p := path if k == 0 else backup_path(path)
		if not FileAccess.file_exists(p):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(parsed) == TYPE_DICTIONARY:
			return {"ok": true, "data": parsed, "from_backup": k == 1}
	return {"ok": false}
