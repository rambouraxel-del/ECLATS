@tool
class_name VoxelPalette
extends RefCounted
## Palette de matières partagée (config/palette.json).
## Le terrain ET les objets lisent la même palette : mêmes couleurs, même rugosité,
## donc aucun raccord visible entre sol et blocs posés.

const PALETTE_PATH := "res://config/palette.json"

## Traitements du shader voxel_stylized.gdshader (l'ordre = le code transmis au shader).
const STYLES := ["default", "grass", "soil", "stone", "wood", "metal", "crystal", "fabric", "foliage"]

static var _instance: VoxelPalette

var keys: PackedStringArray = ["air"]
var names: PackedStringArray = ["Air"]
var colors_linear: PackedColorArray = [Color(0, 0, 0, 0)]
var variations: PackedFloat32Array = [0.0]
var roughness: PackedFloat32Array = [1.0]
var emission: PackedFloat32Array = [0.0]
var metallic: PackedFloat32Array = [0.0]
## Code de traitement du shader stylisé (voir STYLES).
var styles: PackedInt32Array = [0]
var _ids := {}

static func get_default() -> VoxelPalette:
	if _instance == null:
		_instance = VoxelPalette.new()
		_instance.load_json(PALETTE_PATH)
	return _instance

func load_json(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("materials"):
		push_error("Palette invalide : %s" % path)
		return
	for entry in parsed["materials"]:
		var key := String(entry["key"])
		_ids[key] = keys.size()
		keys.append(key)
		names.append(String(entry.get("name", key)))
		colors_linear.append(Color.html(entry["color"]).srgb_to_linear())
		variations.append(float(entry.get("variation", 0.05)))
		roughness.append(float(entry.get("roughness", 0.9)))
		emission.append(float(entry.get("emission", 0.0)))
		metallic.append(float(entry.get("metallic", 0.0)))
		styles.append(maxi(STYLES.find(String(entry.get("style", "default"))), 0))
	if keys.size() > 256:
		push_error("Palette : 255 matières maximum (stockage sur 1 octet).")

## Identifiant numérique d'une matière à partir de sa clé ("stone", "grass"...).
func id(key: String) -> int:
	if not _ids.has(key):
		push_error("Matière inconnue : %s" % key)
		return 0
	return _ids[key]

func count() -> int:
	return keys.size()
