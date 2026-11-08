class_name PlayerConfig
extends RefCounted
## Échelle du personnage (essai « échelle et immersion ») : TOUT dérive de `hauteur_m` (config/player.json).
## Ancienne échelle : hauteur 1,70 m, yeux à 1,60 m, rayon 0,28 m. Nouvelle valeur d'essai : 1,50 m.
## Champ de vision : réglage rapide par la touche F (68° → 76° → 84°), mémorisé dans user://reglages.cfg.
const PATH := "res://config/player.json"
const SETTINGS := "user://reglages.cfg"
const REF_HEIGHT := 1.70
const REF_EYE := 1.60
const REF_RADIUS := 0.28
const THIRD_FOV_OFFSET := 12.0        # la 3e personne garde l'écart d'origine (76° → 64°)

static var _loaded := false
static var height := 1.50
static var presets: Array = [68.0, 76.0, 84.0]
static var fov_fp := 76.0

static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(d) == TYPE_DICTIONARY:
		height = clampf(float(d.get("hauteur_m", height)), 1.0, 2.2)
		fov_fp = clampf(float(d.get("fov_depart", fov_fp)), 50.0, 110.0)
		if typeof(d.get("fov_presets")) == TYPE_ARRAY and not (d["fov_presets"] as Array).is_empty():
			presets = d["fov_presets"]
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		fov_fp = clampf(float(cf.get_value("camera", "fov", fov_fp)), 50.0, 110.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fov="):
			fov_fp = clampf(float(a.substr(6)), 50.0, 110.0)
		elif a.begins_with("--hauteur="):
			height = clampf(float(a.substr(10)), 1.0, 2.2)

static func k() -> float:
	ensure()
	return height / REF_HEIGHT

static func eye() -> float:
	return REF_EYE * k()

static func radius() -> float:
	return REF_RADIUS * k()

## Épaule (3e personne) : 1,55 m en extérieur, 1,45 m à l'intérieur pour 1,70 m.
static func shoulder(interior: bool) -> float:
	return (1.45 if interior else 1.55) * k()

## Passe au champ de vision suivant (68 → 76 → 84 → 68), le mémorise et le renvoie.
static func cycle_fov() -> float:
	ensure()
	var idx := -1
	for i in presets.size():
		if absf(float(presets[i]) - fov_fp) < 0.5:
			idx = i
	fov_fp = float(presets[(idx + 1) % presets.size()])
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("camera", "fov", fov_fp)
	cf.save(SETTINGS)
	return fov_fp
