class_name ConstructionOps
extends RefCounted
## Opérations de construction (Lot 8) : chacune PRÉPARE un résultat sans toucher la construction courante.
##   { ok, reasons[], cand (copie modifiée), delta (unités à payer ; négatif = remboursées), ghost[] (éléments à montrer),
##     text (dimensions + coût), bad (éléments en cause), kind }
## Appliquer = remplacer la construction par `cand` et débiter `delta` (BuildMode). Un résultat refusé (ok = false) laisse tout intact.

const C := preload("res://scripts/build/construction.gd")

static func _fail(kind: String, reasons: Array, ghost: Array = [], text := "") -> Dictionary:
	return {"ok": false, "kind": kind, "reasons": reasons, "cand": null, "delta": 0, "ghost": ghost, "text": text}

static func _ok(kind: String, cand: Construction, delta: int, ghost: Array, text: String) -> Dictionary:
	return {"ok": true, "kind": kind, "reasons": [], "cand": cand, "delta": delta, "ghost": ghost, "text": text}

static func _rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(lo, hi - lo)

static func _slab_rect(f: Dictionary) -> Rect2i:
	return Rect2i(int(f["x0"]), int(f["z0"]), int(f["x1"]) - int(f["x0"]), int(f["z1"]) - int(f["z0"]))

static func _inter_area(a: Rect2i, b: Rect2i) -> int:
	var i := a.intersection(b)
	return maxi(i.size.x, 0) * maxi(i.size.y, 0)

static func cost_text(delta: int) -> String:
	if delta > 0:
		return "coût %d unité%s" % [delta, "s" if delta > 1 else ""]
	if delta < 0:
		return "remboursement %d unité%s" % [-delta, "s" if -delta > 1 else ""]
	return "gratuit"

static func _dims(w_u: int, d_u: int) -> String:
	return "%s × %s m" % [C.fm(float(w_u) * C.U, 2), C.fm(float(d_u) * C.U, 2)]

static func mat_ok(m: String, use: String) -> bool:
	return C.MATS.has(m) and String(C.MATS[m]["use"]) == use

# ------------------------------------------------------------------ sols et fondations

## kind : "floor" | "foundation". a, b : coins opposés (u).
static func add_slab(c: Construction, kind: String, lv: int, a: Vector2i, b: Vector2i, mat := "") -> Dictionary:
	var r := _rect(a, b)
	var label := "Fondations" if kind == "foundation" else "Sol"
	if mat == "":
		mat = "socle" if kind == "foundation" else "planches"
	var el := {"id": 0, "t": kind, "lv": lv, "x0": r.position.x, "z0": r.position.y, "x1": r.end.x, "z1": r.end.y, "mat": mat}
	if r.size.x <= 0 or r.size.y <= 0:
		return _fail(kind, ["Deux coins distincts sont nécessaires : un sol a une surface."], [])
	var text := "%s %s" % [label, _dims(r.size.x, r.size.y)]
	var reasons: Array = []
	if lv < 0 or lv >= C.MAX_LEVELS:
		reasons.append("Niveau hors limites (0 à %d)." % (C.MAX_LEVELS - 1))
	if kind == "foundation" and lv > 0:
		reasons.append("Les fondations se posent au rez-de-chaussée.")
	if r.size.x > C.MAX_SPAN or r.size.y > C.MAX_SPAN:
		reasons.append("Trop grand : %s m au maximum de chaque côté." % C.fm(float(C.MAX_SPAN) * C.U, 0))
	for f in c.slabs(lv):
		if _inter_area(r, _slab_rect(f)) > 0:
			reasons.append("Ce sol chevauche un sol déjà posé à ce niveau.")
			break
	if lv > 0 and reasons.is_empty():
		var under := 0
		for f in c.slabs(lv - 1):
			under += _inter_area(r, _slab_rect(f))
		if under * 2 < r.size.x * r.size.y:
			reasons.append("Un étage doit reposer sur le niveau inférieur : moins de la moitié de ce sol est au-dessus d'un sol existant.")
	var cost := C.slab_cost(el)
	if not reasons.is_empty():
		return _fail(kind, reasons, [el], "%s · %s" % [text, cost_text(cost)])
	var cand := c.copy()
	el["id"] = cand.new_id()
	cand.elements.append(el)
	return _ok(kind, cand, cost, [el], "%s · %s" % [text, cost_text(cost)])

# ------------------------------------------------------------------ murs

static func _align(a: Vector2i, b: Vector2i) -> Vector2i:
	var d := b - a
	return Vector2i(b.x, a.y) if absi(d.x) >= absi(d.y) else Vector2i(a.x, b.y)

static func _wall_dict(lv: int, a: Vector2i, b: Vector2i, h: float, mat: String, grp := 0) -> Dictionary:
	return {"id": 0, "t": "wall", "lv": lv, "ax": mini(a.x, b.x), "az": mini(a.y, b.y), "bx": maxi(a.x, b.x), "bz": maxi(a.y, b.y), "h": h, "mat": mat, "grp": grp, "ops": []}

static func _walls_collide(a: Dictionary, b: Dictionary) -> bool:
	if C.wall_axis(a) != C.wall_axis(b) or C.wall_line(a) != C.wall_line(b) or int(a["lv"]) != int(b["lv"]):
		return false
	var sa := C.wall_span(a)
	var sb := C.wall_span(b)
	return mini(sa.y, sb.y) - maxi(sa.x, sb.x) > 0

static func _floor_under(c: Construction, lv: int, w: Dictionary) -> bool:
	var sp := C.wall_span(w)
	var line := C.wall_line(w)
	var mid := float(sp.x + sp.y) * 0.5
	var px := mid if C.wall_axis(w) == 0 else float(line)
	var pz := float(line) if C.wall_axis(w) == 0 else mid
	for f in c.slabs(lv):
		if px >= float(f["x0"]) and px <= float(f["x1"]) and pz >= float(f["z0"]) and pz <= float(f["z1"]):
			return true
	return false

## Un mur aligné sur la grille : si les deux points ne le sont pas, l'axe dominant est retenu.
static func add_wall(c: Construction, lv: int, a: Vector2i, b: Vector2i, h := 2.5, mat := "bois", grp := 0, skip_same := false) -> Dictionary:
	var bb := _align(a, b)
	var w := _wall_dict(lv, a, bb, h, mat, grp)
	if a == bb:
		return _fail("wall", ["Deux points distincts sont nécessaires pour un mur."], [])
	var len_u := C.wall_len_u(w)
	var text := "Mur %s m × %s m" % [C.fm(float(len_u) * C.U, 2), C.fm(h)]
	var cost := C.wall_cost(w)
	var reasons: Array = []
	if lv < 0 or lv >= C.MAX_LEVELS:
		reasons.append("Niveau hors limites (0 à %d)." % (C.MAX_LEVELS - 1))
	if len_u < C.MIN_WALL:
		reasons.append("Mur trop court : %s m au minimum." % C.fm(float(C.MIN_WALL) * C.U))
	if len_u > C.MAX_SPAN:
		reasons.append("Mur trop long : %s m au maximum." % C.fm(float(C.MAX_SPAN) * C.U, 0))
	if not C.HEIGHTS.has(h):
		reasons.append("Hauteur non prévue (2,0 · 2,5 · 3,0 m).")
	for o in c.of_type("wall", lv):
		if _walls_collide(w, o):
			if skip_same and C.wall_span(o) == C.wall_span(w):
				return {"ok": true, "kind": "wall", "reasons": [], "cand": c, "delta": 0, "ghost": [], "text": text + " (déjà posé)", "exists": true, "wall_id": int(o["id"])}
			reasons.append("Un mur existe déjà à cet endroit (ils se chevaucheraient).")
			break
	if lv > 0 and reasons.is_empty() and not _floor_under(c, lv, w):
		reasons.append("À l'étage, posez d'abord un sol : ce mur n'a rien dessous.")
	if not reasons.is_empty():
		return _fail("wall", reasons, [w], "%s · %s" % [text, cost_text(cost)])
	var cand := c.copy()
	w["id"] = cand.new_id()
	cand.elements.append(w)
	var res := _ok("wall", cand, cost, [w], "%s · %s" % [text, cost_text(cost)])
	res["wall_id"] = int(w["id"])
	return res

# ------------------------------------------------------------------ ouvertures

## `s` : abscisse visée le long du mur (u, flottante) ; l'ouverture est centrée dessus.
static func add_opening(c: Construction, wall_id: int, kind: String, s: float) -> Dictionary:
	var w := c.get_el(wall_id)
	if w.is_empty() or String(w["t"]) != "wall":
		return _fail(kind, ["Visez un mur pour y poser une %s." % ("porte" if kind == "door" else "fenêtre")], [])
	var ow := C.open_size(kind)
	var at := roundi(s - float(ow) * 0.5)
	var sp := C.wall_span(w)
	at = clampi(at, sp.x, sp.y - ow)
	var label := "Porte" if kind == "door" else "Fenêtre"
	var cost := C.DOOR_COST if kind == "door" else C.WINDOW_COST
	var ghost_w := w.duplicate(true)
	ghost_w["ops"] = [{"id": 0, "k": kind, "at": at, "w": ow}]
	var text := "%s %s × %s m · %s" % [label, C.fm(float(ow) * C.U), C.fm(C.DOOR_H if kind == "door" else C.WIN_H), cost_text(cost)]
	var msg := C.opening_problem(w, kind, at, ow)
	if msg != "":
		return _fail(kind, [msg], [ghost_w], text)
	var cand := c.copy()
	var cw := cand.get_el(wall_id)
	var oid := cand.new_id()
	(cw["ops"] as Array).append({"id": oid, "k": kind, "at": at, "w": ow})
	var res := _ok(kind, cand, cost, [ghost_w], text)
	res["opening_id"] = oid
	return res

static func remove_opening(c: Construction, wall_id: int, op_id: int) -> Dictionary:
	var cand := c.copy()
	var w := cand.get_el(wall_id)
	if w.is_empty():
		return _fail("remove", ["Mur introuvable."], [])
	var ops: Array = w["ops"]
	for i in ops.size():
		if int(ops[i]["id"]) == op_id:
			var refund := C.op_cost(ops[i])
			var k := String(ops[i]["k"])
			ops.remove_at(i)
			return _ok("remove", cand, -refund, [], "%s retirée · %s" % ["Porte" if k == "door" else "Fenêtre", cost_text(-refund)])
	return _fail("remove", ["Ouverture introuvable."], [])

## Ouverture visée (indice dans ops) à l'abscisse s (u), ou null.
static func opening_at(w: Dictionary, s: float) -> Dictionary:
	for o in w.get("ops", []):
		if s >= float(o["at"]) and s <= float(int(o["at"]) + int(o["w"])):
			return o
	return {}

# ------------------------------------------------------------------ modification d'un mur

## Nouvelles extrémités (u) et/ou hauteur. Les ouvertures gardent leur position ; si l'une devient incompatible, la modification est refusée.
static func modify_wall(c: Construction, wall_id: int, new_a: Vector2i, new_b: Vector2i, new_h: float) -> Dictionary:
	var w := c.get_el(wall_id)
	if w.is_empty() or String(w["t"]) != "wall":
		return _fail("modify", ["Aucun mur sélectionné."], [])
	var nw := w.duplicate(true)
	var bb := new_b if (new_a.y == new_b.y or new_a.x == new_b.x) else _align(new_a, new_b)
	nw["ax"] = mini(new_a.x, bb.x)
	nw["bx"] = maxi(new_a.x, bb.x)
	nw["az"] = mini(new_a.y, bb.y)
	nw["bz"] = maxi(new_a.y, bb.y)
	nw["h"] = new_h
	var old_len := C.wall_len_u(w)
	var new_len := C.wall_len_u(nw)
	var delta := C.resize_delta(C.wall_cost_base(w), C.wall_cost_base(nw))
	var text := "Mur %s m → %s m, hauteur %s m → %s m · %s" % [C.fm(float(old_len) * C.U, 2), C.fm(float(new_len) * C.U, 2), C.fm(float(w["h"])), C.fm(new_h), cost_text(delta)]
	var reasons: Array = []
	if new_len < C.MIN_WALL:
		reasons.append("Mur trop court : %s m au minimum." % C.fm(float(C.MIN_WALL) * C.U))
	if new_len > C.MAX_SPAN:
		reasons.append("Mur trop long : %s m au maximum." % C.fm(float(C.MAX_SPAN) * C.U, 0))
	if not C.HEIGHTS.has(new_h):
		reasons.append("Hauteur non prévue (2,0 · 2,5 · 3,0 m).")
	if reasons.is_empty():
		var pm := C.wall_problem(nw)
		if pm != "":
			reasons.append("Modification impossible, l'ouverture ne tiendrait plus : %s La construction reste intacte." % pm)
	if reasons.is_empty():
		for o in c.of_type("wall", int(w["lv"])):
			if int(o["id"]) != wall_id and _walls_collide(nw, o):
				reasons.append("Le mur prolongé rejoindrait un autre mur déjà posé.")
				break
	if not reasons.is_empty():
		return _fail("modify", reasons, [nw], text)
	var cand := c.copy()
	var idx := cand.index_of(wall_id)
	cand.elements[idx] = nw
	return _ok("modify", cand, delta, [nw], text)

## Hauteur d'une pièce entière (tous les murs du groupe) ; tout ou rien.
static func set_group_height(c: Construction, wall_id: int, new_h: float) -> Dictionary:
	var w := c.get_el(wall_id)
	if w.is_empty():
		return _fail("height", ["Aucun mur sélectionné."], [])
	var grp := int(w["grp"])
	var ids: Array[int] = [wall_id]
	if grp > 0:
		ids = []
		for o in c.of_type("wall", int(w["lv"])):
			if int(o["grp"]) == grp:
				ids.append(int(o["id"]))
	var cur := c
	var delta := 0
	var ghost: Array = []
	for i in ids:
		var e := cur.get_el(i)
		var r := modify_wall(cur, i, Vector2i(int(e["ax"]), int(e["az"])), Vector2i(int(e["bx"]), int(e["bz"])), new_h)
		if not bool(r["ok"]):
			var rs: Array = r["reasons"]
			return _fail("height", rs, r["ghost"], "Hauteur %s m pour la pièce" % C.fm(new_h))
		cur = r["cand"]
		delta += int(r["delta"])
		ghost.append_array(r["ghost"])
	return _ok("height", cur, delta, ghost, "Pièce à %s m de hauteur · %s" % [C.fm(new_h), cost_text(delta)])

# ------------------------------------------------------------------ suppression

static func remove_element(c: Construction, id: int) -> Dictionary:
	var e := c.get_el(id)
	if e.is_empty():
		return _fail("remove", ["Rien à retirer."], [])
	var t := String(e["t"])
	if t == "floor" or t == "foundation":
		if not c.slabs(int(e["lv"]) + 1).is_empty():
			return _fail("remove", ["Retirez d'abord l'étage au-dessus : il repose sur ce sol."], [e])
	var refund := c.el_cost(e)
	var cand := c.copy()
	cand.elements.remove_at(cand.index_of(id))
	var nm: String = {"floor": "Sol", "foundation": "Fondations", "wall": "Mur", "roof": "Toit"}[t]
	return _ok("remove", cand, -refund, [], "%s retiré · %s" % [nm, cost_text(-refund)])

# ------------------------------------------------------------------ pièce rectangulaire

## Plancher + quatre murs (groupés, modifiables) + porte au milieu du côté choisi (S, E, N, W). Tout ou rien.
static func add_room(c: Construction, lv: int, a: Vector2i, b: Vector2i, h := 2.5, door_side := "S", wall_mat := "bois", floor_mat := "planches") -> Dictionary:
	var r := _rect(a, b)
	var text := "Pièce %s, murs de %s m" % [_dims(r.size.x, r.size.y), C.fm(h)]
	if r.size.x < C.MIN_ROOM or r.size.y < C.MIN_ROOM:
		return _fail("room", ["Pièce trop petite : %s m × %s m au minimum." % [C.fm(float(C.MIN_ROOM) * C.U), C.fm(float(C.MIN_ROOM) * C.U)]], [], text)
	if r.size.x > 40 or r.size.y > 40:
		return _fail("room", ["Pièce trop grande : 20 m de côté au maximum."], [], text)
	var cur := c
	var delta := 0
	var ghost: Array = []
	var grp := c.next_id
	var r1 := add_slab(cur, "floor", lv, r.position, r.end, floor_mat)
	if not bool(r1["ok"]):
		return _fail("room", r1["reasons"], r1["ghost"], text)
	cur = r1["cand"]
	delta += int(r1["delta"])
	ghost.append_array(r1["ghost"])
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	var sides := {"N": [Vector2i(x0, z0), Vector2i(x1, z0)], "S": [Vector2i(x0, z1), Vector2i(x1, z1)],
		"W": [Vector2i(x0, z0), Vector2i(x0, z1)], "E": [Vector2i(x1, z0), Vector2i(x1, z1)]}
	var door_wall := -1
	for s in ["N", "S", "W", "E"]:
		var rw := add_wall(cur, lv, sides[s][0], sides[s][1], h, wall_mat, grp, true)
		if not bool(rw["ok"]):
			return _fail("room", rw["reasons"], ghost + rw["ghost"], text)
		cur = rw["cand"]
		delta += int(rw["delta"])
		ghost.append_array(rw["ghost"])
		if s == door_side:
			door_wall = int(rw["wall_id"])
	if lv == 0 and door_wall >= 0:
		var dw := cur.get_el(door_wall)
		var sp := C.wall_span(dw)
		var mid := float(sp.x + sp.y) * 0.5
		var rd := add_opening(cur, door_wall, "door", mid)
		if not bool(rd["ok"]):
			return _fail("room", rd["reasons"], ghost, text)
		cur = rd["cand"]
		delta += int(rd["delta"])
		ghost.append_array(rd["ghost"])
	var full := "%s · porte côté %s · %s" % [text, C.SIDE_NAMES.get(door_side, door_side), cost_text(delta)]
	var res := _ok("room", cur, delta, ghost, full)
	res["group"] = grp
	return res

# ------------------------------------------------------------------ toit

## Murs reliés à `wall_id` (même niveau, extrémités qui se touchent), ou murs du même groupe.
static func connected_walls(c: Construction, wall_id: int) -> Array[Dictionary]:
	var w := c.get_el(wall_id)
	var out: Array[Dictionary] = []
	if w.is_empty():
		return out
	var lv := int(w["lv"])
	var all := c.of_type("wall", lv)
	if int(w["grp"]) > 0:
		for o in all:
			if int(o["grp"]) == int(w["grp"]):
				out.append(o)
		return out
	var seen := {int(w["id"]): true}
	var queue: Array[Dictionary] = [w]
	out.append(w)
	while not queue.is_empty():
		var cur: Dictionary = queue.pop_front()
		for o in all:
			if seen.has(int(o["id"])):
				continue
			if _touch(cur, o):
				seen[int(o["id"])] = true
				queue.append(o)
				out.append(o)
	return out

static func _touch(a: Dictionary, b: Dictionary) -> bool:
	var pa := [Vector2i(int(a["ax"]), int(a["az"])), Vector2i(int(a["bx"]), int(a["bz"]))]
	var pb := [Vector2i(int(b["ax"]), int(b["az"])), Vector2i(int(b["bx"]), int(b["bz"]))]
	for p in pa:
		if _on_wall(b, p):
			return true
	for p in pb:
		if _on_wall(a, p):
			return true
	return false

static func _on_wall(w: Dictionary, p: Vector2i) -> bool:
	return p.x >= int(w["ax"]) and p.x <= int(w["bx"]) and p.y >= int(w["az"]) and p.y <= int(w["bz"])

static func add_roof(c: Construction, wall_id: int, mat := "tuiles") -> Dictionary:
	var w := c.get_el(wall_id)
	if w.is_empty() or String(w["t"]) != "wall":
		return _fail("roof", ["Visez un mur de la pièce à couvrir."], [])
	var lv := int(w["lv"])
	var ws := connected_walls(c, wall_id)
	var x0 := 1 << 30
	var z0 := 1 << 30
	var x1 := -(1 << 30)
	var z1 := -(1 << 30)
	for o in ws:
		x0 = mini(x0, int(o["ax"]))
		z0 = mini(z0, int(o["az"]))
		x1 = maxi(x1, int(o["bx"]))
		z1 = maxi(z1, int(o["bz"]))
	var roof := {"id": 0, "t": "roof", "lv": lv, "x0": x0, "z0": z0, "x1": x1, "z1": z1, "mat": mat}
	var reasons: Array = []
	if x1 - x0 < 2 or z1 - z0 < 2:
		reasons.append("Ces murs n'entourent pas de surface à couvrir.")
	if not c.slabs(lv + 1).is_empty():
		reasons.append("Un étage existe au-dessus : le toit se pose sur le dernier niveau.")
	for r in c.of_type("roof", lv):
		if _inter_area(Rect2i(x0, z0, x1 - x0, z1 - z0), Rect2i(int(r["x0"]), int(r["z0"]), int(r["x1"]) - int(r["x0"]), int(r["z1"]) - int(r["z0"]))) > 0:
			reasons.append("Un toit couvre déjà cette emprise.")
			break
	var cost := c.roof_cost(roof)
	var text := "Toit à deux pans sur %s · %s" % [_dims(x1 - x0, z1 - z0), cost_text(cost)]
	if not reasons.is_empty():
		var fr := roof.duplicate(true)
		fr["y_override"] = c.roof_base(roof)
		return _fail("roof", reasons, [fr], text)
	var cand := c.copy()
	roof["id"] = cand.new_id()
	cand.elements.append(roof)
	var gr := roof.duplicate(true)
	gr["id"] = cand.next_id
	gr["y_override"] = cand.roof_base(roof)
	return _ok("roof", cand, cost, [gr], text)
