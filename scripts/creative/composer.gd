class_name Composer
extends RefCounted
## GÉNÉRATION D'UNE COMPOSITION dans une zone (cercle) : « foret » (arbres de plusieurs essences, quelques rochers) ou « marche »
## (étals en couronne ouverts vers le centre, caisses et tonneaux, puits). Pure : calcule des objets, ne modifie rien (MapDoc.compose
## applique le résultat en une opération annulable).
## Refus par emplacement : hors de l'île ou trop près du bord, colonne protégée (masque), pente forte, chemin, maison, objet voisin (verrouillé ou non).
## Déterministe : mêmes graine, zone, réglages et état de la carte = mêmes objets.

const PRESETS := {"foret": "Forêt", "marche": "Marché"}
const TREES := ["tree_oak_1", "tree_oak_2", "tree_oak_3", "tree_birch_1", "tree_birch_2", "tree_pine_1", "tree_pine_2", "tree_parasol_1", "tree_parasol_2",
	"tree_weeping_1", "tree_fruit_1", "tree_fruit_2"]
const ROCKS := ["boulder_1", "boulder_2", "boulder_3", "boulder_4"]
const GEN_GROUPS := ["foret", "marche"]

## Pourquoi un emplacement est refusé ("" = libre). others : objets déjà là (dictionnaires) ; taken : objets ajoutés par cette génération.
static func spot_problem(doc: MapDoc, ref: String, pos: Vector2, scl: float, others: Array, taken: Array, slope_max := 0.6) -> String:
	var f := doc.field
	var c := f.col_of_m(pos.x, pos.y)
	if not f.has_ground(c.x, c.y):
		return "hors de l'île"
	if f.edge_dist[f.idx(c.x, c.y)] < 1.0:
		return "trop près du bord"
	if doc.plan.layers != null and doc.is_protected(f.idx(c.x, c.y)):
		return "zone protégée"
	var r := CreativeObjects.clear_radius(ref) * scl
	var lo := 1.0e9
	var hi := -1.0e9
	for q in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var g := f.ground_at_m(pos.x + q.x, pos.y + q.y)
		if is_nan(g):
			return "bord de l'île"
		lo = minf(lo, g)
		hi = maxf(hi, g)
	if hi - lo > slope_max:
		return "pente trop forte"
	var np := HousePad.nearest_path(doc.plan.paths, pos)
	if not np.is_empty():
		var pa := doc.plan.path_by_id(String(np["path_id"]))
		if float(np["d"]) < float(pa.get("width", 2.0)) * 0.5 + r + 0.3:
			return "sur un chemin"
	for h in doc.plan.houses:
		if (h["rect"] as Rect2).grow(r + 0.5).has_point(pos):
			return "dans une maison"
	for lst in [others, taken]:
		for o in lst:
			var d := pos.distance_to(o["pos"])
			if d < r + CreativeObjects.clear_radius(String(o["ref"])) * float(o.get("scale", 1.0)) + 0.15:
				return "objet voisin"
	return ""

## Résultat : {ok, objects (à ajouter), remove (ids à retirer), counts, reasons}.
static func plan_composition(doc: MapDoc, preset: String, center: Vector2, radius: float, seed: int, params := {}) -> Dictionary:
	var res := {"ok": false, "objects": [], "remove": [], "counts": {}, "reasons": [], "kept_locked": 0, "kept_protected": 0}
	if doc.field == null:
		res["reasons"] = ["Aucune île : créez ou ouvrez une carte."]
		return res
	if not PRESETS.has(preset):
		res["reasons"] = ["Composition inconnue : %s." % preset]
		return res
	if radius < 2.0:
		res["reasons"] = ["Zone trop petite : au moins 2 m de rayon."]
		return res
	var f := doc.field
	# 1) objets d'une génération précédente dans la zone : retirés, sauf verrouillés ou en zone protégée
	var keep: Array = []
	for o in doc.plan.objects:
		var inside: bool = (o["pos"] as Vector2).distance_to(center) <= radius
		var generated: bool = GEN_GROUPS.has(String(o.get("group", "manuel")))
		if inside and generated:
			var c := f.col_of_m((o["pos"] as Vector2).x, (o["pos"] as Vector2).y)
			if bool(o.get("locked", false)):
				res["kept_locked"] += 1
				keep.append(o)
			elif doc.plan.layers != null and f.in_bounds(c.x, c.y) and doc.is_protected(f.idx(c.x, c.y)):
				res["kept_protected"] += 1
				keep.append(o)
			else:
				(res["remove"] as Array).append(String(o["id"]))
		else:
			keep.append(o)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, preset, roundi(center.x * 10.0), roundi(center.y * 10.0), roundi(radius * 10.0)])
	var taken: Array = []
	var counts := {}
	var fails := {}
	var add := func(ref: String, pos: Vector2, yaw: float, scl: float, role: String) -> bool:
		var why := spot_problem(doc, ref, pos, scl, keep, taken, 0.4 if preset == "marche" else 0.6)
		if why != "":
			fails[why] = int(fails.get(why, 0)) + 1
			return false
		var o := MapDoc.make_object(ref, pos, yaw, scl, preset)
		o["id"] = "tmp_%d" % taken.size()
		taken.append(o)
		counts[role] = int(counts.get(role, 0)) + 1
		return true
	if preset == "foret":
		var density := clampf(float(params.get("densite", 50)), 5.0, 100.0) / 100.0
		var target := clampi(roundi(PI * radius * radius * density * 0.13), 1, 120)
		var tries := target * 14
		var placed := 0
		while placed < target and tries > 0:
			tries -= 1
			var ang := rng.randf() * TAU
			var rr := radius * sqrt(rng.randf())
			var p := center + Vector2(cos(ang), sin(ang)) * rr
			var is_rock := rng.randf() < 0.07
			var ref: String = ROCKS[rng.randi() % ROCKS.size()] if is_rock else TREES[rng.randi() % TREES.size()]
			var scl := rng.randf_range(0.85, 1.2) if not is_rock else rng.randf_range(0.8, 1.3)
			if add.call(ref, p, rng.randf() * 360.0, scl, "rocher" if is_rock else "arbre"):
				placed += 1
	else:
		var n_stall := clampi(int(params.get("etals", 4)), 1, 8)
		var ring := minf(radius * 0.62, 5.0)
		var a0 := rng.randf() * TAU
		if radius >= 4.0:
			add.call("water_well", center, 0.0, 1.0, "puits")
		var stalls: Array = []
		for k in n_stall:
			for attempt in 12:
				var ang2 := a0 + float(k) * TAU / float(n_stall) + (rng.randf() - 0.5) * 0.4
				var p2 := center + Vector2(cos(ang2), sin(ang2)) * (ring + 0.3 * float(attempt % 3))
				var to_c := center - p2
				var yaw := rad_to_deg(atan2(to_c.x, to_c.y))
				if add.call("market_stall", p2, yaw, 1.0, "étal"):
					stalls.append(p2)
					break
		for sp: Vector2 in stalls:
			for attempt in 8:
				var ang3 := rng.randf() * TAU
				var p3 := sp + Vector2(cos(ang3), sin(ang3)) * (2.0 + 0.25 * float(attempt))
				var rf := "crate_stack" if rng.randf() < 0.5 else "barrel_set"
				if add.call(rf, p3, rng.randf() * 360.0, 1.0, "caisses" if rf == "crate_stack" else "tonneaux"):
					break
		if radius >= 5.0:
			for attempt in 10:
				var ang4 := a0 + PI / float(maxi(n_stall, 1)) + rng.randf() * 0.3
				if add.call("notice_board", center + Vector2(cos(ang4), sin(ang4)) * (radius * 0.85), rad_to_deg(ang4) + 90.0, 1.0, "panneau"):
					break
	res["objects"] = taken
	res["counts"] = counts
	res["fails"] = fails
	if taken.is_empty():
		var why := "aucun emplacement libre"
		if not fails.is_empty():
			var best := ""
			var bn := 0
			for k in fails:
				if int(fails[k]) > bn:
					bn = int(fails[k])
					best = String(k)
			why = "emplacements refusés surtout : %s" % best
		res["reasons"] = ["Rien n'a pu être posé dans cette zone (%s). Agrandissez la zone, choisissez un sol plus plat ou hors zone protégée." % why]
		return res
	res["ok"] = true
	return res

static func summary(preset: String, counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in counts:
		parts.append("%d %s" % [int(counts[k]), k])
	return "%s : %s" % [PRESETS.get(preset, preset), ", ".join(parts)]
