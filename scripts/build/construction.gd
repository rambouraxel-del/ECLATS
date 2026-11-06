class_name Construction
extends RefCounted
## CONSTRUCTION JOUEUR (Lot 8) : sols, fondations, murs (avec portes et fenêtres), toits, sur 1 à 3 niveaux.
## Données pures (aucun nœud) : le même objet sert à l'atelier, au fichier « eclats-construction » et au placement sur une carte.
##
## Repère : x vers l'est, z vers le sud, y vers le haut. Grille de 0,50 m : toutes les positions sont des ENTIERS en
## « unités » (1 u = 0,5 m). Les hauteurs sont en mètres (2,0 / 2,5 / 3,0). Murs de 20 cm, centrés sur les lignes de la grille.
## `base_y` : hauteur du terrain sous le premier sol (mètres, repère du monde) ; 0 dans un fichier.
##
## Éléments (Dictionary, sérialisables tels quels) :
##   sol / fondations {id, t:"floor"|"foundation", lv, x0,z0,x1,z1, mat}
##   mur              {id, t:"wall", lv, ax,az,bx,bz, h, mat, grp, ops:[{id, k:"door"|"window", at, w}]}   (`at` : abscisse u le long du mur)
##   toit             {id, t:"roof", lv, x0,z0,x1,z1, mat}                    (rectangle des lignes de murs)
##
## COÛT (stock de démonstration, pas une économie) : 1 unité / m² (TARIFF), toujours arrondi à l'unité SUPÉRIEURE, par élément :
##   sol et fondations : surface · mur : longueur × hauteur (les ouvertures ne retirent rien) · toit : surface des deux pans
##   porte 4 · fenêtre 2 (forfaits).
## RÈGLE PROVISOIRE de redimensionnement : on paie la DIFFÉRENCE entre le nouveau coût et l'ancien (arrondis chacun à l'unité
## supérieure) ; si elle est négative, elle est remboursée ; retirer un élément rembourse son coût. Une pose refusée ou annulée
## avant confirmation ne débite rien.

const FORMAT := "eclats-construction"
const VERSION := 1
const U := 0.5
const WALL_T := 0.2
const SLAB_T := 0.2
const FOUND_DEPTH := 0.6
const LEVEL_H := 3.0
const MAX_LEVELS := 3
const TARIFF := 1
const DOOR_COST := 4
const WINDOW_COST := 2
const HEIGHTS := [2.0, 2.5, 3.0]
const DOOR_W := 2
const DOOR_H := 2.0
const WIN_W := 2
const WIN_SILL := 0.8
const WIN_H := 1.0
const OPEN_MARGIN := 1
const OPEN_GAP := 1
const MIN_WALL := 2
const MIN_ROOM := 4
const MAX_SPAN := 60
const ROOF_OVER := 0.3
const ROOF_PITCH := 0.5
const ROOF_T := 0.12

## Matières : étiquette, clé de la palette du jeu (mêmes couleurs que le monde), usage.
const MATS := {
	"bois": {"label": "Bois", "key": "wood_planks", "use": "wall"},
	"pierre": {"label": "Pierre", "key": "stone_rubble", "use": "wall"},
	"enduit": {"label": "Enduit", "key": "plaster_worn_cream", "use": "wall"},
	"planches": {"label": "Planches", "key": "floor_planks", "use": "floor"},
	"dalles": {"label": "Dalles", "key": "stone_light", "use": "floor"},
	"socle": {"label": "Pierre de socle", "key": "stone_rubble_dark", "use": "foundation"},
	"tuiles": {"label": "Tuiles", "key": "tiles_terracotta", "use": "roof"},
	"chaume": {"label": "Chaume", "key": "thatch", "use": "roof"},
	"ardoise": {"label": "Ardoise", "key": "slate_old", "use": "roof"},
	"bardeaux": {"label": "Bardeaux", "key": "shingle_aged", "use": "roof"},
}
const WALL_MATS := ["bois", "pierre", "enduit"]
const FLOOR_MATS := ["planches", "dalles"]
const ROOF_MATS := ["tuiles", "chaume", "ardoise", "bardeaux"]
const SIDES := ["S", "E", "N", "W"]
const SIDE_NAMES := {"S": "sud", "E": "est", "N": "nord", "W": "ouest"}

var name := "Sans titre"
var base_y := 0.0
var elements: Array[Dictionary] = []
var next_id := 1

# ------------------------------------------------------------------ outils de texte et de mesure

static func fm(v: float, dec := 1) -> String:
	return (("%." + str(dec) + "f") % v).replace(".", ",")

static func ceil_cost(x: float) -> int:
	return int(ceil(x - 1.0e-6))

func copy() -> Construction:
	var c := Construction.new()
	c.name = name
	c.base_y = base_y
	c.next_id = next_id
	for e in elements:
		c.elements.append(e.duplicate(true))
	return c

func is_empty() -> bool:
	return elements.is_empty()

func new_id() -> int:
	var i := next_id
	next_id += 1
	return i

func get_el(id: int) -> Dictionary:
	for e in elements:
		if int(e["id"]) == id:
			return e
	return {}

func index_of(id: int) -> int:
	for i in elements.size():
		if int(elements[i]["id"]) == id:
			return i
	return -1

func of_type(t: String, lv := -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in elements:
		if String(e["t"]) == t and (lv < 0 or int(e["lv"]) == lv):
			out.append(e)
	return out

func slabs(lv: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in elements:
		var t := String(e["t"])
		if (t == "floor" or t == "foundation") and int(e["lv"]) == lv:
			out.append(e)
	return out

func level_count() -> int:
	var m := -1
	for e in elements:
		m = maxi(m, int(e["lv"]))
	return m + 1

## Hauteur (m, repère du monde) de la surface finie d'un niveau.
func level_y(lv: int) -> float:
	return base_y + SLAB_T + float(lv) * LEVEL_H

# ------------------------------------------------------------------ géométrie des murs

static func wall_axis(w: Dictionary) -> int:
	return 0 if int(w["az"]) == int(w["bz"]) else 2

## Bornes [p0, p1] (u) le long du mur ; `line` : coordonnée fixe (u).
static func wall_span(w: Dictionary) -> Vector2i:
	return Vector2i(int(w["ax"]), int(w["bx"])) if wall_axis(w) == 0 else Vector2i(int(w["az"]), int(w["bz"]))

static func wall_line(w: Dictionary) -> int:
	return int(w["az"]) if wall_axis(w) == 0 else int(w["ax"])

static func wall_len_u(w: Dictionary) -> int:
	var s := wall_span(w)
	return s.y - s.x

static func wall_h_nominal(w: Dictionary) -> float:
	return float(w["h"])

## Hauteur visible du mur : s'il porte un sol à l'étage au-dessus, il monte jusqu'à lui.
func wall_top(w: Dictionary) -> float:
	var lv := int(w["lv"])
	var s := wall_span(w)
	var mid := float(s.x + s.y) * 0.5
	var line := float(wall_line(w))
	var px := mid if wall_axis(w) == 0 else line
	var pz := line if wall_axis(w) == 0 else mid
	for f in slabs(lv + 1):
		if px >= float(f["x0"]) - 0.01 and px <= float(f["x1"]) + 0.01 and pz >= float(f["z0"]) - 0.01 and pz <= float(f["z1"]) + 0.01:
			return LEVEL_H
	return float(w["h"])

## Boîtes pleines d'un mur, en mètres, repère de la construction ; y RELATIF à la surface du niveau. Les ouvertures sont de vraies coupes.
func wall_boxes(w: Dictionary) -> Array[AABB]:
	var out: Array[AABB] = []
	var ax := wall_axis(w)
	var line := float(wall_line(w)) * U
	var sp := wall_span(w)
	var s0 := float(sp.x) * U - WALL_T * 0.5
	var s1 := float(sp.y) * U + WALL_T * 0.5
	var top := wall_top(w)
	var y0 := -SLAB_T
	var ops: Array = (w.get("ops", []) as Array).duplicate()
	ops.sort_custom(func(a, b) -> bool: return int(a["at"]) < int(b["at"]))
	var cur := s0
	var add := func(a: float, b: float, ya: float, yb: float) -> void:
		if b - a < 1.0e-4 or yb - ya < 1.0e-4:
			return
		if ax == 0:
			out.append(AABB(Vector3(a, ya, line - WALL_T * 0.5), Vector3(b - a, yb - ya, WALL_T)))
		else:
			out.append(AABB(Vector3(line - WALL_T * 0.5, ya, a), Vector3(WALL_T, yb - ya, b - a)))
	for o in ops:
		var o0 := float(o["at"]) * U
		var o1 := float(int(o["at"]) + int(o["w"])) * U
		add.call(cur, o0, y0, top)
		if String(o["k"]) == "door":
			add.call(o0, o1, DOOR_H, top)
		else:
			add.call(o0, o1, y0, WIN_SILL)
			add.call(o0, o1, WIN_SILL + WIN_H, top)
		cur = o1
	add.call(cur, s1, y0, top)
	return out

func slab_box(f: Dictionary) -> AABB:
	var depth := FOUND_DEPTH if String(f["t"]) == "foundation" else SLAB_T
	return AABB(Vector3(float(f["x0"]) * U, -depth, float(f["z0"]) * U), Vector3(float(int(f["x1"]) - int(f["x0"])) * U, depth, float(int(f["z1"]) - int(f["z0"])) * U))

## Hauteur de la base d'un toit : sommet des murs du niveau qui touchent son rectangle.
func roof_base(r: Dictionary) -> float:
	var top := 0.0
	var lv := int(r["lv"])
	var found := false
	for w in of_type("wall", lv):
		var s := wall_span(w)
		var line := wall_line(w)
		var inside: bool
		if wall_axis(w) == 0:
			inside = line >= int(r["z0"]) and line <= int(r["z1"]) and s.y > int(r["x0"]) and s.x < int(r["x1"])
		else:
			inside = line >= int(r["x0"]) and line <= int(r["x1"]) and s.y > int(r["z0"]) and s.x < int(r["z1"])
		if inside:
			top = maxf(top, wall_top(w))
			found = true
	return top if found else float(HEIGHTS[1])

## Profil du toit : {x0,x1,z0,z1 (m), ridge_axis (0 = faîtage le long de x), hs (demi-portée), rise, length, y (base, relatif au niveau)}.
func roof_shape(r: Dictionary) -> Dictionary:
	var x0 := float(r["x0"]) * U - WALL_T * 0.5 - ROOF_OVER
	var x1 := float(r["x1"]) * U + WALL_T * 0.5 + ROOF_OVER
	var z0 := float(r["z0"]) * U - WALL_T * 0.5 - ROOF_OVER
	var z1 := float(r["z1"]) * U + WALL_T * 0.5 + ROOF_OVER
	var wx := x1 - x0
	var wz := z1 - z0
	var ridge_axis := 0 if wx >= wz else 2
	var span := wz if ridge_axis == 0 else wx
	var hs := span * 0.5
	return {"x0": x0, "x1": x1, "z0": z0, "z1": z1, "ridge_axis": ridge_axis, "hs": hs, "rise": hs * ROOF_PITCH,
		"length": wx if ridge_axis == 0 else wz, "y": float(r.get("y_override", roof_base(r)))}

# ------------------------------------------------------------------ coût

static func slab_cost(f: Dictionary) -> int:
	var a := (int(f["x1"]) - int(f["x0"])) * (int(f["z1"]) - int(f["z0"]))        # u² (1 u² = 0,25 m²)
	return ceil_cost(float(a) * 0.25 * float(TARIFF))

static func wall_cost_base(w: Dictionary) -> int:
	return ceil_cost(float(wall_len_u(w)) * U * float(w["h"]) * float(TARIFF))

static func op_cost(o: Dictionary) -> int:
	return DOOR_COST if String(o["k"]) == "door" else WINDOW_COST

static func wall_cost(w: Dictionary) -> int:
	var c := wall_cost_base(w)
	for o in w.get("ops", []):
		c += op_cost(o)
	return c

func roof_cost(r: Dictionary) -> int:
	var s := roof_shape(r)
	var slope := sqrt(float(s["hs"]) * float(s["hs"]) + float(s["rise"]) * float(s["rise"]))
	return ceil_cost(2.0 * float(s["length"]) * slope * float(TARIFF))

func el_cost(e: Dictionary) -> int:
	match String(e["t"]):
		"floor", "foundation": return slab_cost(e)
		"wall": return wall_cost(e)
		"roof": return roof_cost(e)
	return 0

func total_cost() -> int:
	var c := 0
	for e in elements:
		c += el_cost(e)
	return c

## Règle provisoire de redimensionnement : différence des coûts arrondis (positive = à payer, négative = remboursée).
static func resize_delta(old_cost: int, new_cost: int) -> int:
	return new_cost - old_cost

# ------------------------------------------------------------------ ouvertures

static func open_size(kind: String) -> int:
	return DOOR_W if kind == "door" else WIN_W

## "" si l'ouverture (k, at, w) est compatible avec le mur, sinon la phrase qui explique pourquoi. `skip_id` : ouverture ignorée (déplacement).
static func opening_problem(w: Dictionary, k: String, at: int, ow: int, skip_id := -1) -> String:
	var sp := wall_span(w)
	if at < sp.x + OPEN_MARGIN or at + ow > sp.y - OPEN_MARGIN:
		return "%s hors du mur : laissez au moins %s m de plein mur à chaque extrémité." % [("La porte" if k == "door" else "La fenêtre"), fm(float(OPEN_MARGIN) * U)]
	var h := float(w["h"])
	if k == "door" and h < DOOR_H - 0.001:
		return "Mur trop bas pour une porte : %s m au lieu de %s m minimum." % [fm(h), fm(DOOR_H)]
	if k == "window" and WIN_SILL + WIN_H > h - 0.29:
		return "Mur trop bas pour une fenêtre : %s m au lieu de %s m minimum." % [fm(h), fm(WIN_SILL + WIN_H + 0.3)]
	if k == "door" and int(w["lv"]) > 0:
		return "Pas de porte à l'étage : aucune sortie n'existe encore à ce niveau."
	for o in w.get("ops", []):
		if int(o["id"]) == skip_id:
			continue
		if at < int(o["at"]) + int(o["w"]) + OPEN_GAP and int(o["at"]) < at + ow + OPEN_GAP:
			return "Trop près d'une autre ouverture : gardez au moins %s m de mur entre deux." % fm(float(OPEN_GAP) * U)
	return ""

## Premier problème trouvé parmi les ouvertures d'un mur ("" si tout est compatible).
static func wall_problem(w: Dictionary) -> String:
	var ops: Array = w.get("ops", [])
	for o in ops:
		var m := opening_problem(w, String(o["k"]), int(o["at"]), int(o["w"]), int(o["id"]))
		if m != "":
			return "%s (%s à %s m du début du mur)" % [m, "porte" if String(o["k"]) == "door" else "fenêtre", fm(float(int(o["at"]) - wall_span(w).x) * U)]
	return ""

# ------------------------------------------------------------------ dimensions, entrée

## Rectangle englobant (m) des sols, fondations et murs du rez-de-chaussée et des étages, murs épais compris. Rect2() si vide.
func bbox_m() -> Rect2:
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	var any := false
	for e in elements:
		var t := String(e["t"])
		if t == "wall":
			var h := WALL_T * 0.5
			var s := wall_span(e)
			var line := float(wall_line(e)) * U
			if wall_axis(e) == 0:
				lo = lo.min(Vector2(float(s.x) * U - h, line - h))
				hi = hi.max(Vector2(float(s.y) * U + h, line + h))
			else:
				lo = lo.min(Vector2(line - h, float(s.x) * U - h))
				hi = hi.max(Vector2(line + h, float(s.y) * U + h))
			any = true
		elif t == "floor" or t == "foundation":
			lo = lo.min(Vector2(float(e["x0"]), float(e["z0"])) * U)
			hi = hi.max(Vector2(float(e["x1"]), float(e["z1"])) * U)
			any = true
	if not any:
		return Rect2()
	return Rect2(lo, hi - lo)

## Emprise au sol pour un placement : rectangle englobant (m) avec le débord des toits.
func footprint_m() -> Rect2:
	var r := bbox_m()
	if r.size == Vector2.ZERO:
		return r
	for e in elements:
		if String(e["t"]) == "roof":
			var s := roof_shape(e)
			r = r.merge(Rect2(Vector2(s["x0"], s["z0"]), Vector2(float(s["x1"]) - float(s["x0"]), float(s["z1"]) - float(s["z0"]))))
	return r

func height_m() -> float:
	var top := 0.0
	for e in elements:
		var lv := float(int(e["lv"])) * LEVEL_H
		match String(e["t"]):
			"wall": top = maxf(top, lv + wall_top(e))
			"floor": top = maxf(top, lv)
			"roof":
				var s := roof_shape(e)
				top = maxf(top, lv + float(s["y"]) + ROOF_T + float(s["rise"]))
	return top

## Porte d'entrée : la première porte du rez-de-chaussée. {pos (m, au seuil, à l'extérieur), dir (Vector2i, vers l'extérieur), wall_id, door (centre m)} ou {}.
func entrance() -> Dictionary:
	var bb := bbox_m()
	if bb.size == Vector2.ZERO:
		return {}
	var c := bb.get_center()
	for w in of_type("wall", 0):
		for o in w.get("ops", []):
			if String(o["k"]) != "door":
				continue
			var mid := (float(o["at"]) + float(o["w"]) * 0.5) * U
			var line := float(wall_line(w)) * U
			var p := Vector2(mid, line) if wall_axis(w) == 0 else Vector2(line, mid)
			var d := p - c
			var dir := Vector2i.ZERO
			if wall_axis(w) == 0:
				dir = Vector2i(0, 1) if d.y >= 0.0 else Vector2i(0, -1)
			else:
				dir = Vector2i(1, 0) if d.x >= 0.0 else Vector2i(-1, 0)
			return {"door": p, "dir": dir, "pos": p + Vector2(dir) * (WALL_T * 0.5 + 0.5), "wall_id": int(w["id"])}
	return {}

# ------------------------------------------------------------------ déplacement, normalisation

func translate_u(dx: int, dz: int) -> void:
	for e in elements:
		match String(e["t"]):
			"floor", "foundation", "roof":
				e["x0"] = int(e["x0"]) + dx
				e["x1"] = int(e["x1"]) + dx
				e["z0"] = int(e["z0"]) + dz
				e["z1"] = int(e["z1"]) + dz
			"wall":
				var ax := wall_axis(e)
				e["ax"] = int(e["ax"]) + dx
				e["bx"] = int(e["bx"]) + dx
				e["az"] = int(e["az"]) + dz
				e["bz"] = int(e["bz"]) + dz
				for o in e.get("ops", []):
					o["at"] = int(o["at"]) + (dx if ax == 0 else dz)

## Copie normalisée pour l'export : coin minimum à (0, 0) u, terrain à 0.
func normalized() -> Construction:
	var c := copy()
	var lo_x := 1 << 30
	var lo_z := 1 << 30
	for e in c.elements:
		match String(e["t"]):
			"floor", "foundation", "roof":
				lo_x = mini(lo_x, int(e["x0"]))
				lo_z = mini(lo_z, int(e["z0"]))
			"wall":
				lo_x = mini(lo_x, int(e["ax"]))
				lo_z = mini(lo_z, int(e["az"]))
	if lo_x < (1 << 30):
		c.translate_u(-lo_x, -lo_z)
	c.base_y = 0.0
	return c

# ------------------------------------------------------------------ (dé)sérialisation

func to_dict() -> Dictionary:
	var bb := bbox_m()
	var mats := {}
	for e in elements:
		mats[String(e["mat"])] = true
	var els: Array = []
	for e in elements:
		els.append(e.duplicate(true))
	return {"format": FORMAT, "version": VERSION, "name": name,
		"dims": {"largeur_m": snappedf(bb.size.x, 0.01), "profondeur_m": snappedf(bb.size.y, 0.01), "hauteur_m": snappedf(height_m(), 0.01), "niveaux": level_count()},
		"materiaux": mats.keys(), "tarif": TARIFF, "next_id": next_id, "elements": els}

func to_json() -> String:
	return JSON.stringify(to_dict(), "\t", true)

static func from_json(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"ok": false, "error": "Le fichier est vide."}
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"ok": false, "error": "Fichier illisible : le contenu est abîmé ou incomplet (JSON invalide à la ligne %d : %s)." % [j.get_error_line(), j.get_error_message()]}
	if typeof(j.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Ce fichier n'est pas une construction ÉCLATS (contenu inattendu)."}
	return from_dict(j.data)

static func _int_keys(e: Dictionary, keys: Array) -> bool:
	for k in keys:
		if not e.has(k) or (typeof(e[k]) != TYPE_INT and typeof(e[k]) != TYPE_FLOAT):
			return false
	return true

static func from_dict(d: Dictionary) -> Dictionary:
	if String(d.get("format", "")) != FORMAT:
		return {"ok": false, "error": "Ce fichier n'est pas une construction ÉCLATS (format « %s » au lieu de « %s »). Une carte d'île ne se rouvre pas ici." % [str(d.get("format", "absent")), FORMAT]}
	var ver := int(d.get("version", 0))
	if ver < 1:
		return {"ok": false, "error": "Version de construction invalide (%s)." % str(d.get("version", "absente"))}
	if ver > VERSION:
		return {"ok": false, "error": "Construction enregistrée avec une version plus récente (v%d) que celle de ce jeu (v%d) : mettez le jeu à jour." % [ver, VERSION]}
	if typeof(d.get("elements", null)) != TYPE_ARRAY:
		return {"ok": false, "error": "Construction incomplète : la liste des éléments manque."}
	var c := Construction.new()
	c.name = String(d.get("name", "Sans titre"))
	var maxid := 0
	for raw in d["elements"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return {"ok": false, "error": "Construction invalide : un élément est mal formé."}
		var e: Dictionary = raw
		var t := String(e.get("t", ""))
		if not ["floor", "foundation", "wall", "roof"].has(t):
			return {"ok": false, "error": "Construction invalide : type d'élément inconnu (« %s »)." % t}
		if not _int_keys(e, ["id", "lv"]) or int(e["lv"]) < 0 or int(e["lv"]) >= MAX_LEVELS:
			return {"ok": false, "error": "Construction invalide : un élément a un niveau hors limites (0 à %d)." % (MAX_LEVELS - 1)}
		if not MATS.has(String(e.get("mat", ""))):
			return {"ok": false, "error": "Construction invalide : matière inconnue (« %s »)." % str(e.get("mat", "absente"))}
		var n: Dictionary = {"id": int(e["id"]), "t": t, "lv": int(e["lv"]), "mat": String(e["mat"])}
		if t == "wall":
			if not _int_keys(e, ["ax", "az", "bx", "bz"]) or not e.has("h"):
				return {"ok": false, "error": "Construction invalide : un mur n'a pas toutes ses coordonnées."}
			for k in ["ax", "az", "bx", "bz"]:
				n[k] = int(e[k])
			if (int(n["ax"]) != int(n["bx"]) and int(n["az"]) != int(n["bz"])) or (int(n["ax"]) == int(n["bx"]) and int(n["az"]) == int(n["bz"])):
				return {"ok": false, "error": "Construction invalide : un mur n'est pas aligné sur la grille (ni nul)."}
			if int(n["ax"]) > int(n["bx"]) or int(n["az"]) > int(n["bz"]):
				return {"ok": false, "error": "Construction invalide : les extrémités d'un mur sont inversées."}
			n["h"] = float(e["h"])
			if not HEIGHTS.has(n["h"]):
				return {"ok": false, "error": "Construction invalide : hauteur de mur non prévue (%s m)." % str(e["h"])}
			n["grp"] = int(e.get("grp", 0))
			n["ops"] = []
			var ops_raw = e.get("ops", [])
			if typeof(ops_raw) != TYPE_ARRAY:
				return {"ok": false, "error": "Construction invalide : les ouvertures d'un mur sont mal formées."}
			for o in ops_raw:
				if typeof(o) != TYPE_DICTIONARY or not _int_keys(o, ["id", "at", "w"]) or not ["door", "window"].has(String(o.get("k", ""))):
					return {"ok": false, "error": "Construction invalide : une ouverture est mal formée."}
				(n["ops"] as Array).append({"id": int(o["id"]), "k": String(o["k"]), "at": int(o["at"]), "w": int(o["w"])})
				maxid = maxi(maxid, int(o["id"]))
			var pm := wall_problem(n)
			if pm != "":
				return {"ok": false, "error": "Construction invalide : ouverture incompatible avec son mur — %s" % pm}
		else:
			if not _int_keys(e, ["x0", "z0", "x1", "z1"]):
				return {"ok": false, "error": "Construction invalide : un sol ou un toit n'a pas toutes ses coordonnées."}
			for k in ["x0", "z0", "x1", "z1"]:
				n[k] = int(e[k])
			if int(n["x1"]) <= int(n["x0"]) or int(n["z1"]) <= int(n["z0"]):
				return {"ok": false, "error": "Construction invalide : un sol ou un toit a une surface nulle."}
		maxid = maxi(maxid, int(n["id"]))
		c.elements.append(n)
	c.next_id = maxi(int(d.get("next_id", 1)), maxid + 1)
	return {"ok": true, "construction": c}

static func save_file(c: Construction, path: String) -> Dictionary:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Impossible d'écrire « %s » (erreur %d)." % [path, FileAccess.get_open_error()]}
	f.store_string(c.normalized().to_json())
	f.close()
	return {"ok": true, "path": path}

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Fichier introuvable : %s" % path}
	var r := from_json(FileAccess.get_file_as_string(path))
	if not bool(r["ok"]):
		r["error"] = "%s (%s)" % [r["error"], path.get_file()]
	return r

## Résumé lisible.
func summary() -> String:
	var bb := bbox_m()
	return "%s · %s × %s m · %d niveau(x) · %d mur(s), %d ouverture(s) · coût total %d" % [name, fm(bb.size.x), fm(bb.size.y), level_count(),
		of_type("wall").size(), count_openings(), total_cost()]

func count_openings() -> int:
	var n := 0
	for w in of_type("wall"):
		n += (w.get("ops", []) as Array).size()
	return n

## Signature stable du contenu (comparaison avant / après export).
func signature() -> int:
	return hash(JSON.stringify(to_dict(), "", true))
