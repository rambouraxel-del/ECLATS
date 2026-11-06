@tool
class_name PlanLayers
extends RefCounted
## Couches matricielles d'une carte (une valeur par colonne de 20 cm, alignées sur le TerrainField) :
##   delta : retouche de relief en cellules (octet, 128 = aucune retouche) ajoutée au relief issu du plan
##   mat   : matière du sol imposée par le pinceau (0 = celle du plan)
##   mask  : masque de protection (0 = libre, 1 = protégé)
## Stockées dans la carte exportée (compressées en base64). `fit` les recale si la grille change (contour agrandi).

var n := 0
var ox := 0        # cellule monde de la colonne 0 (même repère que TerrainField.origin)
var oz := 0
var delta := PackedByteArray()
var mat := PackedByteArray()
var mask := PackedByteArray()

static func create(p_n: int, origin: Vector2i) -> PlanLayers:
	var l := PlanLayers.new()
	l.n = p_n
	l.ox = origin.x
	l.oz = origin.y
	l.delta.resize(p_n * p_n)
	l.delta.fill(128)
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
	return int(delta[i]) - 128

func set_delta(i: int, v: int) -> void:
	delta[i] = clampi(v, -127, 127) + 128

func is_empty() -> bool:
	for i in n * n:
		if delta[i] != 128 or mat[i] != 0 or mask[i] != 0:
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
		if delta[i] != 128:
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

static func _dec(s: String, size: int) -> PackedByteArray:
	var raw := Marshalls.base64_to_raw(s)
	return raw.decompress(size, FileAccess.COMPRESSION_DEFLATE)

func to_dict() -> Dictionary:
	if is_empty():
		return {}
	return {"n": n, "origin": [ox, oz], "delta": _enc(delta), "mat": _enc(mat), "mask": _enc(mask)}

## Relit un dictionnaire de couches. Renvoie null si le contenu est incohérent.
static func from_dict(d: Dictionary) -> PlanLayers:
	if d.is_empty():
		return null
	var nn := int(d.get("n", 0))
	var o: Array = d.get("origin", [0, 0])
	if nn <= 0 or nn > 4096 or o.size() != 2:
		return null
	var l := create(nn, Vector2i(int(o[0]), int(o[1])))
	var d1 := _dec(String(d.get("delta", "")), nn * nn)
	var d2 := _dec(String(d.get("mat", "")), nn * nn)
	var d3 := _dec(String(d.get("mask", "")), nn * nn)
	if d1.size() != nn * nn or d2.size() != nn * nn or d3.size() != nn * nn:
		return null
	l.delta = d1
	l.mat = d2
	l.mask = d3
	return l
