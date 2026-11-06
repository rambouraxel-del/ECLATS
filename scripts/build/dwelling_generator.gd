class_name DwellingGenerator
extends RefCounted
## HABITATIONS GÉNÉRÉES (Lot 9) : trois variantes réellement distinctes, produites avec la même grammaire de construction que le joueur
## (ConstructionOps), donc modifiables dans l'atelier et enregistrables comme n'importe quelle maison.
##   cabane       une pièce, 3 à 5 m de large, murs bas, une fenêtre, toit à deux pans
##   deux_pieces  rectangle de 5 à 8 m cloisonné en DEUX pièces reliées par une porte intérieure, 3 à 4 fenêtres
##   en_L         deux ailes à angle droit : corps principal bas + aile haute de 3,0 m, DEUX toits à faîtages croisés (≥ 5,8 × 7,8 m)
## À graine, emprise et réglages identiques, la même maison (même signature). `auto` choisit la variante d'après la graine
## parmi celles qui tiennent dans l'emprise. Le modèle est normalisé : la porte regarde le sud (+z), le placement le tourne.

const C := preload("res://scripts/build/construction.gd")
const VARIANTS := ["cabane", "deux_pieces", "en_L"]
const NAMES := {"cabane": "Cabane", "deux_pieces": "Maison à deux pièces", "en_L": "Maison en L"}
## Plus petit rectangle de murs (u de 0,5 m) de chaque variante.
const MIN_WALLS := {"cabane": Vector2i(6, 6), "deux_pieces": Vector2i(10, 8), "en_L": Vector2i(10, 14)}
const OVERHANG_TOTAL := 0.8        # 2 × (débord de toit 0,30 m + demi-épaisseur de mur 0,10 m)

static func min_fit(variant: String) -> Vector2:
	var m: Vector2i = MIN_WALLS[variant]
	return Vector2(float(m.x) * C.U + OVERHANG_TOTAL, float(m.y) * C.U + OVERHANG_TOTAL)

static func variant_name(v: String) -> String:
	return String(NAMES.get(v, v))

## Variantes qui tiennent dans l'emprise.
static func fitting(fit: Vector2) -> Array[String]:
	var out: Array[String] = []
	for v in VARIANTS:
		var m := min_fit(v)
		if fit.x >= m.x - 0.001 and fit.y >= m.y - 0.001:
			out.append(v)
	return out

static func _avail_u(fit: Vector2) -> Vector2i:
	return Vector2i(int(floor((fit.x - OVERHANG_TOTAL) / C.U + 0.001)), int(floor((fit.y - OVERHANG_TOTAL) / C.U + 0.001)))

static func _rng(seed: int, variant: String, fit: Vector2, opts: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, variant, roundi(fit.x * 10.0), roundi(fit.y * 10.0)])
	return r

static func _pick(r: RandomNumberGenerator, a: Array):
	return a[r.randi() % a.size()]

## Résultat : {ok, reasons[], model, variant, requested, recipe, constraints{}, text}. opts : murs (bois|pierre|enduit), toit (tuiles|chaume|ardoise|bardeaux).
static func generate(variant: String, seed: int, fit: Vector2, opts := {}) -> Dictionary:
	var res := {"ok": false, "reasons": [], "variant": "", "requested": variant}
	var fits := fitting(fit)
	if fits.is_empty():
		var m := min_fit("cabane")
		res["reasons"] = ["Emprise trop petite : %s × %s m. La plus petite habitation (la cabane) demande au moins %s × %s m, débord de toit compris." % [C.fm(fit.x), C.fm(fit.y), C.fm(m.x), C.fm(m.y)]]
		return res
	var v := variant
	if v == "auto" or v == "":
		var ra := RandomNumberGenerator.new()
		ra.seed = hash([seed, roundi(fit.x * 10.0), roundi(fit.y * 10.0)])
		v = fits[ra.randi() % fits.size()]
	if not VARIANTS.has(v):
		res["reasons"] = ["Variante inconnue : %s (cabane, deux_pieces, en_L ou auto)." % v]
		return res
	if not fits.has(v):
		var m2 := min_fit(v)
		res["reasons"] = ["Emprise trop petite pour « %s » : %s × %s m ; il en faut au moins %s × %s m (débord de toit compris)." % [variant_name(v), C.fm(fit.x), C.fm(fit.y), C.fm(m2.x), C.fm(m2.y)]]
		return res
	var r := _rng(seed, v, fit, opts)
	# les tirages de matières sont toujours consommés : imposer une matière ne change ni la forme ni le reste de la maison
	var wall_mat: String = _pick(r, C.WALL_MATS)
	var roof_mat: String = _pick(r, C.ROOF_MATS)
	wall_mat = String(opts.get("murs", wall_mat))
	roof_mat = String(opts.get("toit", roof_mat))
	if not C.WALL_MATS.has(wall_mat):
		res["reasons"] = ["Matière de mur inconnue : %s." % wall_mat]
		return res
	if not C.ROOF_MATS.has(roof_mat):
		res["reasons"] = ["Matière de toit inconnue : %s." % roof_mat]
		return res
	var av := _avail_u(fit)
	var c: Construction
	match v:
		"cabane": c = _cabane(r, av, wall_mat, roof_mat)
		"deux_pieces": c = _deux_pieces(r, av, wall_mat, roof_mat)
		"en_L": c = _en_l(r, av, wall_mat, roof_mat)
	if c == null:
		res["reasons"] = ["La génération de « %s » a échoué pour cette emprise." % variant_name(v)]
		return res
	c.name = "%s (graine %d)" % [variant_name(v), seed]
	var n := c.normalized()
	n.name = c.name
	res["ok"] = true
	res["model"] = n
	res["variant"] = v
	res["recipe"] = {"gen": "habitation", "opts": {"variante": v, "seed": seed, "emprise": fit, "murs": wall_mat, "toit": roof_mat}}
	res["constraints"] = constraints_for(n)
	res["text"] = describe(res)
	return res

static func constraints_for(model: Construction) -> Dictionary:
	var fp := HousePad.footprint(model)
	var s: Vector2 = fp["size"]
	return {"emprise_m": s, "hauteur_m": model.height_m(), "porte": not (fp["entrance"] as Dictionary).is_empty(),
		"denivele_max_m": float(HousePad.CUT + HousePad.FILL) * VoxelGrid.VOXEL_SIZE, "raccord_max_m": HousePad.LINK_MAX_M, "pente_max": HousePad.LINK_GRADE}

static func describe(res: Dictionary) -> String:
	var m: Construction = res["model"]
	var cs: Dictionary = res["constraints"]
	var s: Vector2 = cs["emprise_m"]
	var o: Dictionary = (res["recipe"] as Dictionary)["opts"]
	return "%s · graine %d · emprise bâtie %s × %s m · hauteur %s m · %d mur(s), %d ouverture(s), %d toit(s) · murs %s, toit %s · coût de construction %d" % [
		variant_name(res["variant"]), int(o["seed"]), C.fm(s.x), C.fm(s.y), C.fm(float(cs["hauteur_m"])), m.of_type("wall").size(), m.count_openings(),
		m.of_type("roof").size(), o["murs"], o["toit"], m.total_cost()]

static func constraints_text(res: Dictionary) -> String:
	var cs: Dictionary = res["constraints"]
	var s: Vector2 = cs["emprise_m"]
	return "Contraintes de pose : emprise %s × %s m (débord de toit compris), porte au rez-de-chaussée à orienter vers le chemin, plateforme plate (dénivelé rattrapé jusqu'à %s m), raccord au chemin ≤ %s m et ≤ %d %%, jamais sur une zone protégée." % [
		C.fm(s.x), C.fm(s.y), C.fm(float(cs["denivele_max_m"]), 2), C.fm(float(cs["raccord_max_m"]), 0), roundi(float(cs["pente_max"]) * 100.0)]

# ------------------------------------------------------------------ variantes

static func _add(c: Construction, r: Dictionary) -> Construction:
	return r["cand"] if bool(r["ok"]) else c

static func _wall_by(c: Construction, lv: int, axis: int, line: int, a0 := -1, a1 := -1) -> Dictionary:
	for w in c.of_type("wall", lv):
		if C.wall_axis(w) == axis and C.wall_line(w) == line:
			var sp := C.wall_span(w)
			if a0 < 0 or (sp.x <= a0 and sp.y >= a1):
				return w
	return {}

## Une pièce : porte au sud, une fenêtre, un toit.
static func _cabane(r: RandomNumberGenerator, av: Vector2i, wall_mat: String, roof_mat: String) -> Construction:
	var w := clampi(r.randi_range(7, 10), 6, av.x)
	var d := clampi(r.randi_range(6, 8), 6, av.y)
	var h: float = _pick(r, [2.0, 2.5])
	var c := Construction.new()
	c = _add(c, ConstructionOps.add_room(c, 0, Vector2i(0, 0), Vector2i(w, d), h, "S", wall_mat, "planches"))
	var side: String = _pick(r, ["N", "E", "W"])
	var wall: Dictionary
	match side:
		"N": wall = _wall_by(c, 0, 0, 0)
		"E": wall = _wall_by(c, 0, 2, w)
		_: wall = _wall_by(c, 0, 2, 0)
	if h >= 2.5 and not wall.is_empty():
		var sp := C.wall_span(wall)
		c = _add(c, ConstructionOps.add_opening(c, int(wall["id"]), "window", float(sp.x + sp.y) * 0.5))
	return _roof(c, roof_mat)

## Deux pièces : cloison avec porte intérieure, porte d'entrée dans l'une, fenêtres sur le nord et l'est.
static func _deux_pieces(r: RandomNumberGenerator, av: Vector2i, wall_mat: String, roof_mat: String) -> Construction:
	var w := clampi(r.randi_range(12, 16), 10, av.x)
	var d := clampi(r.randi_range(9, 11), 8, av.y)
	var h: float = 2.5
	var c := Construction.new()
	c = _add(c, ConstructionOps.add_room(c, 0, Vector2i(0, 0), Vector2i(w, d), h, "S", wall_mat, "planches"))
	var split := clampi(int(round(float(w) * r.randf_range(0.38, 0.62))), 4, w - 4)
	var rp := ConstructionOps.add_wall(c, 0, Vector2i(split, 0), Vector2i(split, d), h, wall_mat, 0)
	c = _add(c, rp)
	var part := _wall_by(c, 0, 2, split)
	if not part.is_empty():
		var sp := C.wall_span(part)
		c = _add(c, ConstructionOps.add_opening(c, int(part["id"]), "door", float(sp.x + sp.y) * 0.5))
	# la porte d'entrée de add_room est au milieu du mur sud : on la déplace dans la plus grande pièce
	var south := _wall_by(c, 0, 0, d)
	var big_left := split >= w - split
	if not south.is_empty() and (south["ops"] as Array).size() > 0:
		var oid := int(south["ops"][0]["id"])
		var rr := ConstructionOps.remove_opening(c, int(south["id"]), oid)
		if bool(rr["ok"]):
			var tgt := float(split) * 0.5 if big_left else float(split + w) * 0.5
			var ad := ConstructionOps.add_opening(rr["cand"], int(south["id"]), "door", tgt)
			if bool(ad["ok"]):
				c = ad["cand"]
			else:
				c = c
	var north := _wall_by(c, 0, 0, 0)
	if not north.is_empty():
		for s in [float(split) * 0.5, float(split + w) * 0.5]:
			var rw := ConstructionOps.add_opening(c, int(north["id"]), "window", s)
			if bool(rw["ok"]):
				c = rw["cand"]
	var east := _wall_by(c, 0, 2, w)
	if not east.is_empty():
		c = _add(c, ConstructionOps.add_opening(c, int(east["id"]), "window", float(d) * 0.5))
	return _roof(c, roof_mat)

## Corps principal bas au sud + aile haute (3,0 m) au nord, à gauche ou à droite selon la graine ; deux toits aux faîtages croisés.
static func _en_l(r: RandomNumberGenerator, av: Vector2i, wall_mat: String, roof_mat: String) -> Construction:
	var wm := clampi(r.randi_range(12, 16), 10, av.x)
	var wn := clampi(r.randi_range(5, 7), 5, mini(wm - 4, av.y - 9))
	var dm := clampi(r.randi_range(7, 9), 7, av.y - (wn + 2))
	var dn := clampi(r.randi_range(wn + 2, wn + 4), wn + 2, av.y - dm)          # l'aile est plus profonde que large : son faîtage croise celui du corps principal
	var dt := dn + dm
	var mirror := r.randi() % 2 == 1
	var hm := 2.5
	var hn := 3.0
	var c := Construction.new()
	# corps principal (porte sud), z de dn à dt
	c = _add(c, ConstructionOps.add_room(c, 0, Vector2i(0, dn), Vector2i(wm, dt), hm, "S", wall_mat, "planches"))
	var gm := _group_of(c)
	# aile haute, au nord : plancher + trois murs (le quatrième côté est le mur nord du corps principal)
	var x0 := 0 if not mirror else wm - wn
	var x1 := x0 + wn
	c = _add(c, ConstructionOps.add_slab(c, "floor", 0, Vector2i(x0, 0), Vector2i(x1, dn), "planches"))
	var gn := c.next_id + 100
	c = _add(c, ConstructionOps.add_wall(c, 0, Vector2i(x0, 0), Vector2i(x1, 0), hn, wall_mat, gn))
	c = _add(c, ConstructionOps.add_wall(c, 0, Vector2i(x0, 0), Vector2i(x0, dn), hn, wall_mat, gn))
	c = _add(c, ConstructionOps.add_wall(c, 0, Vector2i(x1, 0), Vector2i(x1, dn), hn, wall_mat, gn))
	# le mur nord du corps principal appartient aussi à l'aile : porte intérieure entre les deux volumes
	var join := _wall_by(c, 0, 0, dn)
	if not join.is_empty():
		c = _add(c, ConstructionOps.add_opening(c, int(join["id"]), "door", float(x0 + x1) * 0.5))
	# fenêtres : aile (nord et côté libre), corps principal (est ou ouest)
	var wn_wall := _wall_by(c, 0, 0, 0)
	if not wn_wall.is_empty():
		c = _add(c, ConstructionOps.add_opening(c, int(wn_wall["id"]), "window", float(x0 + x1) * 0.5))
	var free_x := x0 if not mirror else x1
	var side := _wall_by(c, 0, 2, free_x, 0, dn)
	if not side.is_empty():
		c = _add(c, ConstructionOps.add_opening(c, int(side["id"]), "window", float(dn) * 0.5))
	var far_x := wm if not mirror else 0
	var far := _wall_by(c, 0, 2, far_x, dn, dt)
	if not far.is_empty():
		c = _add(c, ConstructionOps.add_opening(c, int(far["id"]), "window", float(dn + dt) * 0.5))
	# deux toits : un par volume
	for wall_id in [_wall_by(c, 0, 0, 0), _wall_by(c, 0, 0, dt)]:
		if not wall_id.is_empty():
			c = _add(c, ConstructionOps.add_roof(c, int(wall_id["id"]), roof_mat))
	return c

static func _group_of(c: Construction) -> int:
	var ws := c.of_type("wall")
	return int(ws[0]["grp"]) if not ws.is_empty() else 0

static func _roof(c: Construction, roof_mat: String) -> Construction:
	var ws := c.of_type("wall", 0)
	if ws.is_empty():
		return c
	return _add(c, ConstructionOps.add_roof(c, int(ws[0]["id"]), roof_mat))
