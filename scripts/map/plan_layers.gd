@tool
class_name PlanLayers
extends RefCounted
## Couches matricielles d'une carte (une valeur par colonne de 20 cm, alignées sur le TerrainField) :
##   delta : retouche de relief en cellules (entier 32 bits en mémoire, ±MAX_DELTA, 0 = aucune) ajoutée au relief issu du plan.
##           Fichier : 16 bits signés (« delta16 ») ; les cartes v1-v2 (octets, ±127 = 25,4 m) se relisent par migration.
##   mat   : matière du sol imposée par le pinceau (0 = celle du plan)
##   mask  : masque de protection (0 = libre, 1 = protégé)
## Stockées dans la carte exportée (compressées en base64). `fit` les recale si la grille change (contour agrandi).

## Limite des retouches de relief : ±2000 cellules (400 m). Au-delà, la pose est refusée (jamais écrêtée en silence).
const MAX_DELTA := 2000
const LEGACY_MAX := 127

var n := 0
var ox := 0        # cellule monde de la colonne 0 (même repère que TerrainField.origin)
var oz := 0
var delta := PackedInt32Array()
var mat := PackedByteArray()
var mask := PackedByteArray()

static func create(p_n: int, origin: Vector2i) -> PlanLayers:
	var l := PlanLayers.new()
	l.n = p_n
	l.ox = origin.x
	l.oz = origin.y
	l.delta.resize(p_n * p_n)
	l.mat.resize(p_n * p_n)
	l.mask.resize(p_n * p_n)
	return l

func copy() -> PlanLayers:
	var l := PlanLayers.new()
	l.n = n
	l.ox = ox
	l.oz = oz
	l.delta = delta.duplicate()
	l.mat = mat.duplicate()
	l.mask = mask.duplicate()
	return l

func get_delta(i: int) -> int:
	return delta[i]

## Écrit la retouche de la colonne i. Renvoie false (rien écrit) si |v| dépasse MAX_DELTA : l'appelant doit alors limiter la hauteur affichée.
func set_delta(i: int, v: int) -> bool:
	if absi(v) > MAX_DELTA:
		return false
	delta[i] = v
	return true

## Plus grande hauteur autorisée pour une colonne dont le relief de base est `base`.
static func limit_top(base: int, wanted: int) -> int:
	return base + clampi(wanted - base, -MAX_DELTA, MAX_DELTA)

func is_empty() -> bool:
	for i in n * n:
		if delta[i] != 0 or mat[i] != 0 or mask[i] != 0:
			return false
	return true

func count_mask() -> int:
	var c := 0
	for i in n * n:
		if mask[i] != 0:
			c += 1
	return c

func count_delta() -> int:
	var c := 0
	for i in n * n:
		if delta[i] != 0:
			c += 1
	return c

func count_mat() -> int:
	var c := 0
	for i in n * n:
		if mat[i] != 0:
			c += 1
	return c

## Recale sur une nouvelle grille (même repère monde) ; le contenu hors de la nouvelle grille est perdu.
func fit(new_n: int, new_origin: Vector2i) -> void:
	if new_n == n and new_origin.x == ox and new_origin.y == oz:
		return
	var nl := PlanLayers.create(new_n, new_origin)
	for cz in n:
		var z := cz + oz - new_origin.y
		if z < 0 or z >= new_n:
			continue
		for cx in n:
			var x := cx + ox - new_origin.x
			if x < 0 or x >= new_n:
				continue
			var i := cx + cz * n
			var j := x + z * new_n
			nl.delta[j] = delta[i]
			nl.mat[j] = mat[i]
			nl.mask[j] = mask[i]
	n = nl.n
	ox = nl.ox
	oz = nl.oz
	delta = nl.delta
	mat = nl.mat
	mask = nl.mask

static func _enc(a: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(a.compress(FileAccess.COMPRESSION_DEFLATE))

## Décodage tolérant : renvoie un tableau vide si le texte n'est pas du base64 / deflate valide ou n'a pas la taille attendue.
static func _dec(s: String, size: int) -> PackedByteArray:
	if s == "":
		return PackedByteArray()
	var raw := Marshalls.base64_to_raw(s)
	if raw.is_empty():
		return PackedByteArray()
	var out := raw.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	return out if out.size() == size else PackedByteArray()

func _delta16() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n * n * 2)
	for i in n * n:
		b.encode_s16(i * 2, delta[i])
	return b

func to_dict() -> Dictionary:
	if is_empty():
		return {}
	return {"n": n, "origin": [ox, oz], "delta16": _enc(_delta16()), "mat": _enc(mat), "mask": _enc(mask)}

## Relit un dictionnaire de couches. Renvoie {ok, layers} ou {ok: false, error} (phrase destinée à l'utilisateur).
## Migration : « delta » (octets, 128 = rien, cartes v1-v2) → entiers ; « delta16 » (v3) → entiers.
static func parse(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {"ok": false, "error": "les couches sont vides."}
	for k in ["n", "origin"]:
		if not d.has(k):
			return {"ok": false, "error": "le champ « %s » manque." % k}
	if (typeof(d["n"]) != TYPE_INT and typeof(d["n"]) != TYPE_FLOAT) or typeof(d["origin"]) != TYPE_ARRAY:
		return {"ok": false, "error": "taille ou origine mal formées."}
	var nn := int(d["n"])
	var o: Array = d["origin"]
	if nn <= 0 or nn > 4096 or float(d["n"]) != float(nn):
		return {"ok": false, "error": "taille de grille hors limites (%s ; 1 à 4096)." % str(d["n"])}
	if o.size() != 2 or (typeof(o[0]) != TYPE_INT and typeof(o[0]) != TYPE_FLOAT) or (typeof(o[1]) != TYPE_INT and typeof(o[1]) != TYPE_FLOAT) \
			or absf(float(o[0])) > 100000.0 or absf(float(o[1])) > 100000.0:
		return {"ok": false, "error": "origine de grille invalide."}
	var count := nn * nn
	var l := create(nn, Vector2i(int(o[0]), int(o[1])))
	if d.has("delta16"):
		var raw := _dec(String(d["delta16"]), count * 2)
		if raw.is_empty():
			return {"ok": false, "error": "les retouches de relief sont illisibles ou de mauvaise taille."}
		for i in count:
			var v := raw.decode_s16(i * 2)
			if absi(v) > MAX_DELTA:
				return {"ok": false, "error": "une retouche de relief (%d cellules = %.1f m) dépasse la limite de ±%d cellules (±%d m)." % [v, absf(float(v)) * 0.2, MAX_DELTA, MAX_DELTA / 5]}
			l.delta[i] = v
	elif d.has("delta"):
		var old := _dec(String(d["delta"]), count)
		if old.is_empty():
			return {"ok": false, "error": "les retouches de relief (ancien format) sont illisibles ou de mauvaise taille."}
		for i in count:
			l.delta[i] = int(old[i]) - 128
	else:
		return {"ok": false, "error": "les retouches de relief manquent."}
	var m := _dec(String(d.get("mat", "")), count)
	var k := _dec(String(d.get("mask", "")), count)
	if m.is_empty() or k.is_empty():
		return {"ok": false, "error": "les matières ou le masque de protection sont illisibles ou de mauvaise taille."}
	var pal_n := VoxelPalette.get_default().count()
	for i in count:
		if k[i] > 1:
			return {"ok": false, "error": "le masque de protection contient une valeur inconnue (%d)." % k[i]}
		if m[i] != 0 and m[i] >= pal_n:
			return {"ok": false, "error": "une matière du sol n'existe pas dans la palette (numéro %d)." % m[i]}
	l.mat = m
	l.mask = k
	return {"ok": true, "layers": l}

## Compatibilité : renvoie les couches ou null.
static func from_dict(d: Dictionary) -> PlanLayers:
	var r := parse(d)
	return r["layers"] if bool(r["ok"]) else null
