@tool
class_name IslandPlan
extends RefCounted
## PLAN d'une île (Lot 7) : la source unique du terrain 3D. Contour, zones (disques ordonnés, le dernier posé l'emporte),
## chemins (polylignes avec largeur et liaisons), repères, point de départ, réglages — plus les couches de retouches
## (relief, matières, masque de protection) quand la carte a été éditée.
## Mètres partout : x vers l'est, z vers le sud (le nord est en haut du plan 2D).
## Format de fichier : JSON versionné « eclats-carte » (voir to_json / from_json).

const FORMAT := "eclats-carte"
const VERSION := 3                     # v2 : maisons posées ; v3 (Lot 11) : retouches de relief sur 16 bits (±400 m), maisons avec leur terrain. Les cartes v1 et v2 se relisent par migration.
const COORD_LIMIT := 5000.0            # |x|, |z| maximaux acceptés à l'import (m)
const MAX_ITEMS := 5000                # zones, chemins, repères, maisons, points : garde-fou à l'import
const MIN_SIZE := 32.0
const MAX_SIZE := 120.0

## Types de zones : libellé, couleur de légende, matière du sol, plat (habitable) ou non, amplitude du relief naturel (m),
## hauteur par défaut (m, 0 = pas de contrainte) et part du rayon qui impose la hauteur.
const KINDS := {
	"arrivee": {"label": "Arrivée (en contrebas)", "color": Color("e3b24f"), "mat": "gravel", "flat": true, "amp": 0.05, "h": 2.4, "cr": 1.0},
	"plateau": {"label": "Plateau habitable", "color": Color("94c96b"), "mat": "grass_trim", "flat": true, "amp": 0.10, "h": 6.0, "cr": 1.0},
	"bois": {"label": "Zone boisée", "color": Color("3f7d4a"), "mat": "grass_lush", "flat": false, "amp": 1.0, "h": 8.0, "cr": 0.5},
	"sommet": {"label": "Point haut", "color": Color("b3aeb0"), "mat": "rock_grey", "flat": false, "amp": 0.6, "h": 11.0, "cr": 0.45},
	"crique": {"label": "Crique", "color": Color("efe0a6"), "mat": "gravel", "flat": true, "amp": 0.05, "h": 1.6, "cr": 1.0},
	"falaise": {"label": "Falaise / roche", "color": Color("b48c6c"), "mat": "rock_warm", "flat": false, "amp": 1.5, "h": 0.0, "cr": 0.0},
	"pelouse": {"label": "Prairie", "color": Color("bddc92"), "mat": "grass", "flat": false, "amp": 0.7, "h": 0.0, "cr": 0.0},
}
const KIND_ORDER := ["arrivee", "plateau", "bois", "sommet", "crique", "falaise", "pelouse"]
const LANDMARK_KINDS := {
	"vue": {"label": "Point de vue", "color": Color("ffd84a")},
	"lieu": {"label": "Lieu à dévoiler", "color": Color("ff8fb0")},
}
## Matières peignables au pinceau : [clé de palette, libellé].
const MATERIALS := [["grass", "Herbe"], ["grass_lush", "Herbe dense"], ["grass_dry", "Herbe dorée"], ["moss", "Mousse"],
	["dirt", "Terre"], ["dirt_dry", "Terre sèche"], ["path_dirt", "Sentier"], ["gravel", "Gravier"], ["cobble", "Pavés"],
	["rock_grey", "Roche grise"], ["rock_warm", "Roche chaude"]]

var name := "Île sans nom"
var seed := 1
var width := 56.0
var length := 48.0
var settings := {"relief": 1.0}
var outline: Array = []                  # Array[Vector2]
var zones: Array[Dictionary] = []        # {id, kind, c: Vector2, r, h}
var paths: Array[Dictionary] = []        # {id, width, pts: Array[Vector2], from, to}
var landmarks: Array[Dictionary] = []    # {id, kind, pos: Vector2, label}
var start := Vector2.ZERO
var layers: PlanLayers = null            # retouches (null = aucune)
var houses: Array[Dictionary] = []      # maisons posées : {id, name, model (dict eclats-construction), pos: Vector2, yaw, ground_m, rect: [x0,z0,x1,z1] (m), door: Vector2}
var generated := true                    # vrai tant que la carte vient du générateur sans canevas vide
var _uid := 0

# ------------------------------------------------------------------ copie, identifiants

func copy() -> IslandPlan:
	var p := IslandPlan.new()
	p.name = name
	p.seed = seed
	p.width = width
	p.length = length
	p.settings = settings.duplicate(true)
	p.outline = outline.duplicate()
	for z in zones:
		p.zones.append(z.duplicate(true))
	for pa in paths:
		var q := pa.duplicate(true)
		q["pts"] = (pa["pts"] as Array).duplicate()
		p.paths.append(q)
	for l in landmarks:
		p.landmarks.append(l.duplicate(true))
	for h in houses:
		p.houses.append(h.duplicate(true))
	p.start = start
	p.layers = layers.copy() if layers != null else null
	p.generated = generated
	p._uid = _uid
	return p

func new_id(prefix: String) -> String:
	_uid += 1
	return "%s_%d" % [prefix, _uid]

## Plan vide (canevas) : aucun contour, aucune zone.
static func blank(p_name := "Nouvelle île", p_seed := 1, w := 56.0, l := 48.0) -> IslandPlan:
	var p := IslandPlan.new()
	p.name = p_name
	p.seed = p_seed
	p.width = w
	p.length = l
	p.generated = false
	return p

func zone_by_id(id: String) -> Dictionary:
	for z in zones:
		if z["id"] == id:
			return z
	return {}

func path_by_id(id: String) -> Dictionary:
	for p in paths:
		if p["id"] == id:
			return p
	return {}

## Dernière zone (celle qui l'emporte) qui contient le point.
func zone_at(p: Vector2) -> Dictionary:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if p.distance_to(z["c"]) <= float(z["r"]):
			return z
	return {}

func zone_height(z: Dictionary) -> float:
	return float(z.get("h", KINDS[z["kind"]]["h"]))

func extent() -> float:
	var e := maxf(width, length) * 0.5
	for p: Vector2 in outline:
		e = maxf(e, maxf(absf(p.x), absf(p.y)))
	return e

# ------------------------------------------------------------------ géométrie du contour

static func poly_area(poly: Array) -> float:
	var a := 0.0
	var m := poly.size()
	for i in m:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % m]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

static func point_in_poly(pt: Vector2, poly: Array) -> bool:
	var inside := false
	var m := poly.size()
	for i in m:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % m]
		if (a.y > pt.y) != (b.y > pt.y) and pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
	return inside

## Distance du point au contour (m).
static func dist_to_poly(pt: Vector2, poly: Array) -> float:
	var best := 1.0e9
	var m := poly.size()
	for i in m:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % m]
		var ab := b - a
		var t := clampf((pt - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
		best = minf(best, pt.distance_to(a + ab * t))
	return best

## Les segments du contour se croisent-ils ? (polygone non simple)
static func poly_self_intersects(poly: Array) -> bool:
	var m := poly.size()
	for i in m:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % m]
		for j in range(i + 2, m):
			if i == 0 and j == m - 1:
				continue
			var c: Vector2 = poly[j]
			var d: Vector2 = poly[(j + 1) % m]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return true
	return false

static func path_length(pts: Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += (pts[i] as Vector2).distance_to(pts[i - 1])
	return l

# ------------------------------------------------------------------ vérifications du plan

## Liste lisible de problèmes (vide = plan cohérent). N'exige pas de relief : travaille sur la géométrie du plan.
func problems() -> Array[String]:
	var out: Array[String] = []
	if outline.size() < 3:
		out.append("Le contour a moins de 3 points.")
		return out
	if poly_self_intersects(outline):
		out.append("Le contour se croise lui-même.")
	if absf(poly_area(outline)) < 150.0:
		out.append("Le contour est trop petit (moins de 150 m²).")
	for z in zones:
		if not point_in_poly(z["c"], outline):
			out.append("La zone « %s » (%s) est hors du contour." % [KINDS[z["kind"]]["label"], z["id"]])
	for pa in paths:
		var pts: Array = pa["pts"]
		if pts.size() < 2:
			out.append("Le chemin %s a moins de 2 points." % pa["id"])
			continue
		for pt: Vector2 in pts:
			if not point_in_poly(pt, outline):
				out.append("Le chemin %s sort du contour." % pa["id"])
				break
	for l in landmarks:
		if not point_in_poly(l["pos"], outline):
			out.append("Le repère %s est hors du contour." % l["id"])
	if not outline.is_empty() and not point_in_poly(start, outline):
		out.append("Le point de départ est hors du contour.")
	return out

# ------------------------------------------------------------------ (dé)sérialisation

static func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]

static func _p(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

## Structure du plan (sans les couches) : sert aussi de signature pour savoir si le relief de base doit être recalculé.
func structure_dict() -> Dictionary:
	var o: Array = []
	for p: Vector2 in outline:
		o.append(_v(p))
	var zs: Array = []
	for z in zones:
		zs.append({"id": z["id"], "kind": z["kind"], "c": _v(z["c"]), "r": snappedf(float(z["r"]), 0.01), "h": snappedf(float(z.get("h", 0.0)), 0.01)})
	var ps: Array = []
	for pa in paths:
		var pts: Array = []
		for q: Vector2 in pa["pts"]:
			pts.append(_v(q))
		ps.append({"id": pa["id"], "width": snappedf(float(pa["width"]), 0.01), "pts": pts, "from": pa.get("from", ""), "to": pa.get("to", "")})
	var ls: Array = []
	for l in landmarks:
		ls.append({"id": l["id"], "kind": l["kind"], "pos": _v(l["pos"]), "label": l.get("label", "")})
	return {"seed": seed, "width": snappedf(width, 0.01), "length": snappedf(length, 0.01), "settings": settings, "outline": o,
		"zones": zs, "paths": ps, "landmarks": ls, "start": _v(start)}

func signature() -> int:
	var d := structure_dict()
	d.erase("landmarks")      # les repères n'influencent pas le relief
	d.erase("start")
	return WorldRng.fnv(JSON.stringify(d, "", true))

func to_dict() -> Dictionary:
	var d := structure_dict()
	d["format"] = FORMAT
	d["version"] = VERSION
	d["name"] = name
	d["generated"] = generated
	d["uid"] = _uid
	if layers != null:
		var ld := layers.to_dict()
		if not ld.is_empty():
			d["layers"] = ld
	if not houses.is_empty():
		var hs: Array = []
		for h in houses:
			var r: Rect2 = h["rect"]
			hs.append({"id": h["id"], "name": h.get("name", "Maison"), "model": h["model"], "pos": _v(h["pos"]), "yaw": int(h["yaw"]),
				"ground_m": snappedf(float(h["ground_m"]), 0.001), "rect": [snappedf(r.position.x, 0.001), snappedf(r.position.y, 0.001), snappedf(r.end.x, 0.001), snappedf(r.end.y, 0.001)],
				"door": _v(h.get("door", Vector2.ZERO))})
			if h.has("terrain"):
				hs[hs.size() - 1]["terrain"] = HouseTerrain.to_dict(h["terrain"])
			if h.has("link"):
				hs[hs.size() - 1]["link"] = {"to": _v(h["link"]["to"]), "path_id": String(h["link"]["path_id"])}
		d["maisons"] = hs
	return d

func to_json() -> String:
	return JSON.stringify(to_dict(), "\t", true)

## Relit un plan. Renvoie {ok, plan, error} ; l'erreur est une phrase destinée à l'utilisateur.
static func from_json(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"ok": false, "error": "Le fichier est vide."}
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		var where := " à la ligne %d" % json.get_error_line() if json.get_error_line() > 0 else ""
		return {"ok": false, "error": "Fichier illisible : le contenu est abîmé ou incomplet (JSON invalide%s : %s)." % [where, json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Ce fichier n'est pas une carte ÉCLATS (contenu inattendu)."}
	return from_dict(json.data)

static func _is_num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and not is_nan(float(v)) and not is_inf(float(v))

static func _is_pt(q) -> bool:
	return typeof(q) == TYPE_ARRAY and (q as Array).size() == 2 and _is_num(q[0]) and _is_num(q[1]) \
			and absf(float(q[0])) <= COORD_LIMIT and absf(float(q[1])) <= COORD_LIMIT

static func _in(v, lo: float, hi: float) -> bool:
	return _is_num(v) and float(v) >= lo and float(v) <= hi

static func from_dict(d: Dictionary) -> Dictionary:
	if String(d.get("format", "")) != FORMAT:
		return {"ok": false, "error": "Ce fichier n'est pas une carte ÉCLATS (format « %s » au lieu de « %s »)." % [str(d.get("format", "absent")), FORMAT]}
	var ver := int(d.get("version", 0))
	if ver < 1:
		return {"ok": false, "error": "Version de carte invalide (%s)." % str(d.get("version", "absente"))}
	if ver > VERSION:
		return {"ok": false, "error": "Carte enregistrée avec une version plus récente (v%d) que celle de ce jeu (v%d) : mettez le jeu à jour." % [ver, VERSION]}
	for key in ["outline", "zones", "paths", "landmarks", "start", "width", "length", "seed"]:
		if not d.has(key):
			return {"ok": false, "error": "Carte incomplète : le champ « %s » manque." % key}
	var p := IslandPlan.new()
	p.name = String(d.get("name", "Île"))
	if not _in(d["seed"], -2147483648.0, 2147483647.0):
		return {"ok": false, "error": "Carte invalide : la graine n'est pas un nombre."}
	if not _in(d["width"], 1.0, 1000.0) or not _in(d["length"], 1.0, 1000.0):
		return {"ok": false, "error": "Carte invalide : dimensions hors limites (largeur et longueur entre 1 et 1000 m)."}
	p.seed = int(d["seed"])
	p.width = float(d["width"])
	p.length = float(d["length"])
	if typeof(d.get("settings", {})) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Carte invalide : les réglages sont mal formés."}
	p.settings = (d.get("settings", {"relief": 1.0}) as Dictionary).duplicate(true)
	if p.settings.has("relief") and not _in(p.settings["relief"], 0.0, 10.0):
		return {"ok": false, "error": "Carte invalide : réglage de relief hors limites (0 à 10)."}
	p.generated = bool(d.get("generated", false))
	p._uid = int(d.get("uid", 0)) if _is_num(d.get("uid", 0)) else 0
	if typeof(d["outline"]) != TYPE_ARRAY or typeof(d["zones"]) != TYPE_ARRAY or typeof(d["paths"]) != TYPE_ARRAY or typeof(d["landmarks"]) != TYPE_ARRAY:
		return {"ok": false, "error": "Carte invalide : contour, zones, chemins ou repères mal formés."}
	if (d["outline"] as Array).size() > MAX_ITEMS or (d["zones"] as Array).size() > MAX_ITEMS or (d["paths"] as Array).size() > MAX_ITEMS or (d["landmarks"] as Array).size() > MAX_ITEMS:
		return {"ok": false, "error": "Carte invalide : trop d'éléments (au plus %d de chaque sorte)." % MAX_ITEMS}
	for q in d["outline"]:
		if not _is_pt(q):
			return {"ok": false, "error": "Carte invalide : un point du contour est mal formé ou hors limites (±%d m)." % int(COORD_LIMIT)}
		p.outline.append(_p(q))
	var ids := {}
	for z in d["zones"]:
		if typeof(z) != TYPE_DICTIONARY or not KINDS.has(String(z.get("kind", ""))) or not z.has("c") or not z.has("r"):
			return {"ok": false, "error": "Carte invalide : une zone est mal formée ou de type inconnu (%s)." % str((z as Dictionary).get("kind", "?") if typeof(z) == TYPE_DICTIONARY else z)}
		if not _is_pt(z["c"]) or not _in(z["r"], 0.1, 2000.0) or (z.has("h") and not _in(z["h"], -50.0, 500.0)):
			return {"ok": false, "error": "Carte invalide : le centre, le rayon ou la hauteur d'une zone est hors limites."}
		var zid := String(z.get("id", "zone"))
		if ids.has("z" + zid):
			return {"ok": false, "error": "Carte invalide : l'identifiant de zone « %s » apparaît deux fois." % zid}
		ids["z" + zid] = true
		p.zones.append({"id": zid, "kind": String(z["kind"]), "c": _p(z["c"]), "r": float(z["r"]), "h": float(z.get("h", KINDS[String(z["kind"])]["h"]))})
	for pa in d["paths"]:
		if typeof(pa) != TYPE_DICTIONARY or not pa.has("pts") or typeof(pa["pts"]) != TYPE_ARRAY or (pa["pts"] as Array).size() < 2:
			return {"ok": false, "error": "Carte invalide : un chemin est mal formé (au moins 2 points)."}
		if (pa["pts"] as Array).size() > MAX_ITEMS or not _in(pa.get("width", 2.0), 0.2, 50.0):
			return {"ok": false, "error": "Carte invalide : un chemin a trop de points ou une largeur hors limites (0,2 à 50 m)."}
		var pts: Array = []
		for q in pa["pts"]:
			if not _is_pt(q):
				return {"ok": false, "error": "Carte invalide : un point de chemin est mal formé ou hors limites."}
			pts.append(_p(q))
		var pid := String(pa.get("id", "chemin"))
		if ids.has("p" + pid):
			return {"ok": false, "error": "Carte invalide : l'identifiant de chemin « %s » apparaît deux fois." % pid}
		ids["p" + pid] = true
		p.paths.append({"id": pid, "width": float(pa.get("width", 2.0)), "pts": pts, "from": String(pa.get("from", "")), "to": String(pa.get("to", ""))})
	for l in d["landmarks"]:
		if typeof(l) != TYPE_DICTIONARY or not l.has("pos") or not _is_pt(l["pos"]):
			return {"ok": false, "error": "Carte invalide : un repère est mal formé ou hors limites."}
		if not LANDMARK_KINDS.has(String(l.get("kind", "lieu"))):
			return {"ok": false, "error": "Carte invalide : type de repère inconnu (« %s »)." % str(l.get("kind"))}
		p.landmarks.append({"id": String(l.get("id", "repere")), "kind": String(l.get("kind", "lieu")), "pos": _p(l["pos"]), "label": String(l.get("label", ""))})
	if not _is_pt(d["start"]):
		return {"ok": false, "error": "Carte invalide : le point de départ est mal formé ou hors limites."}
	p.start = _p(d["start"])
	if d.has("layers"):
		if typeof(d["layers"]) != TYPE_DICTIONARY:
			return {"ok": false, "error": "Carte invalide : les couches de retouches sont mal formées."}
		var lr := PlanLayers.parse(d["layers"])
		if not bool(lr["ok"]):
			return {"ok": false, "error": "Carte invalide : couches de retouches — %s" % String(lr["error"])}
		p.layers = lr["layers"]
	if d.has("maisons"):
		if typeof(d["maisons"]) != TYPE_ARRAY or (d["maisons"] as Array).size() > MAX_ITEMS:
			return {"ok": false, "error": "Carte invalide : la liste des maisons est mal formée."}
		for h in d["maisons"]:
			if typeof(h) != TYPE_DICTIONARY or not h.has("model") or not h.has("pos") or not h.has("rect") or typeof(h["model"]) != TYPE_DICTIONARY:
				return {"ok": false, "error": "Carte invalide : une maison est mal formée (modèle, position ou emprise manquants)."}
			var mr := Construction.from_dict(h["model"])
			if not bool(mr["ok"]):
				return {"ok": false, "error": "Carte invalide : le modèle d'une maison est illisible — %s" % String(mr["error"])}
			var rr = h["rect"]
			if typeof(rr) != TYPE_ARRAY or (rr as Array).size() != 4 or not (_is_num(rr[0]) and _is_num(rr[1]) and _is_num(rr[2]) and _is_num(rr[3])) \
					or float(rr[2]) <= float(rr[0]) or float(rr[3]) <= float(rr[1]):
				return {"ok": false, "error": "Carte invalide : l'emprise d'une maison est mal formée."}
			if not _is_pt(h["pos"]) or (h.has("door") and not _is_pt(h["door"])) or not _in(h.get("ground_m", 0.0), -500.0, 5000.0) or not _in(h.get("yaw", 0), -1000.0, 1000.0):
				return {"ok": false, "error": "Carte invalide : position, porte, hauteur ou orientation d'une maison hors limites."}
			var hid := String(h.get("id", "maison"))
			if ids.has("h" + hid):
				return {"ok": false, "error": "Carte invalide : l'identifiant de maison « %s » apparaît deux fois." % hid}
			ids["h" + hid] = true
			var hr := {"id": hid, "name": String(h.get("name", "Maison")), "model": h["model"], "pos": _p(h["pos"]),
				"yaw": posmod(int(h.get("yaw", 0)), 4), "ground_m": float(h.get("ground_m", 0.0)),
				"rect": Rect2(Vector2(float(rr[0]), float(rr[1])), Vector2(float(rr[2]) - float(rr[0]), float(rr[3]) - float(rr[1]))),
				"door": _p(h.get("door", [0, 0]))}
			if h.has("link"):
				if typeof(h["link"]) != TYPE_DICTIONARY or not _is_pt(h["link"].get("to", null)):
					return {"ok": false, "error": "Carte invalide : le raccord d'une maison est mal formé."}
				hr["link"] = {"to": _p(h["link"]["to"]), "path_id": String(h["link"].get("path_id", ""))}
			if h.has("terrain"):
				var tr := HouseTerrain.parse(h["terrain"])
				if not bool(tr["ok"]):
					return {"ok": false, "error": "Carte invalide : terrain d'une maison — %s" % String(tr["error"])}
				hr["terrain"] = tr["terrain"]
			p.houses.append(hr)
	for h in p.houses:
		if h.has("terrain"):
			var t: Dictionary = h["terrain"]
			if p.layers == null or int(t["n"]) != p.layers.n or int(t["ox"]) != p.layers.ox or int(t["oz"]) != p.layers.oz:
				return {"ok": false, "error": "Carte invalide : le terrain de la maison « %s » ne correspond pas aux couches de retouches de la carte." % h["name"]}
	if p.outline.size() >= 3 and p.width <= 0.0:
		return {"ok": false, "error": "Carte invalide : dimensions nulles."}
	return {"ok": true, "plan": p}

static func save_file(plan: IslandPlan, path: String) -> Dictionary:
	# écriture sûre (Lot 11) : le fichier temporaire est relu et revalidé avant de remplacer la version précédente
	var verify := func(text: String) -> String:
		var r := from_json(text)
		return "" if bool(r["ok"]) else String(r["error"])
	return SafeFile.write_text(path, plan.to_json(), verify)

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Fichier introuvable : %s" % path}
	var r := from_json(FileAccess.get_file_as_string(path))
	if not r["ok"]:
		r["error"] = "%s (%s)" % [r["error"], path.get_file()]
	return r
