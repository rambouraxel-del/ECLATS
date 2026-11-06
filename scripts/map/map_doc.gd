class_name MapDoc
extends RefCounted
## Document de carte ÉDITABLE (Lot 7, étape 2) : le plan + son terrain, les pinceaux de relief et de matière, le masque de
## protection, la régénération du relief dans une sélection, l'annulation PAR OPÉRATION (un trait de pinceau, un déplacement de
## chemin, une régénération = une opération), l'export et l'ouverture de cartes.
## Aucun nœud : tout est testable sans rendu. L'éditeur (MapEditor) n'est qu'une interface sur ce document.
##
## Les retouches (relief, matières, masque) vivent dans plan.layers (couches de colonnes alignées sur le terrain) ; le terrain
## affiché = relief du plan + retouches. Le masque protège contre les pinceaux ET la régénération.

const V := VoxelGrid.VOXEL_SIZE
const FEATHER_M := 2.0              # raccord de la régénération autour de la sélection et du masque
const UNDO_MAX := 60

var plan: IslandPlan
var build: PlanTerrain.Build
var field: TerrainField
var path_reports: Array = []
var undo_stack: Array[Dictionary] = []
var message := ""
var rebuilds := 0
var _snap: Dictionary = {}
var _hf := PackedFloat32Array()      # hauteurs flottantes (cellules) pendant un trait de relief
var _target := 0.0
var _stroke_dirty := Rect2i()
var _stroke_has := false
var _regen_n := 0

static func from_plan(p: IslandPlan) -> MapDoc:
	var d := MapDoc.new()
	d.plan = p
	d.rebuild(true)
	return d

static func blank(p_name := "Nouvelle île") -> MapDoc:
	var d := MapDoc.new()
	d.plan = IslandPlan.blank(p_name)
	return d

func has_terrain() -> bool:
	return field != null

func layers() -> PlanLayers:
	return plan.layers

## Recalcule le relief de base si la structure du plan a changé, puis ré-applique les retouches.
func rebuild(force := false) -> void:
	if plan.outline.size() < 3:
		build = null
		field = null
		path_reports = []
		return
	if force or build == null or plan.signature() != build.plan_sig:
		build = PlanTerrain.build(plan)
		field = build.field
		rebuilds += 1
		if plan.layers == null:
			plan.layers = PlanLayers.create(field.n, field.origin)
		else:
			plan.layers.fit(field.n, field.origin)
	elif plan.layers == null:
		plan.layers = PlanLayers.create(field.n, field.origin)
	PlanTerrain.apply_layers(build, plan)
	path_reports = PlanTerrain.path_reports(plan, field)

# ------------------------------------------------------------------ opérations et annulation

func begin_op(label: String) -> void:
	_snap = {"label": label, "plan": plan.copy()}

## Termine l'opération : l'état d'avant est empilé (annulable). Renvoie "" ou une raison de refus (opération défaite).
func finish_op(do_rebuild := true) -> String:
	if _snap.is_empty():
		return ""
	if plan.outline.size() >= 3 and IslandPlan.poly_self_intersects(plan.outline):
		var snap := _snap
		_snap = {}
		plan = snap["plan"]
		rebuild(true)
		message = "Contour refusé : il se croise lui-même. L'opération est annulée."
		return message
	if do_rebuild:
		rebuild()
	undo_stack.append(_snap)
	if undo_stack.size() > UNDO_MAX:
		undo_stack.pop_front()
	message = String(_snap["label"])
	_snap = {}
	return ""

func cancel_op() -> void:
	if _snap.is_empty():
		return
	plan = _snap["plan"]
	_snap = {}
	rebuild(true)

func edit(label: String, fn: Callable) -> String:
	begin_op(label)
	fn.call()
	return finish_op()

func can_undo() -> bool:
	return not undo_stack.is_empty()

## Annule la dernière opération ENTIÈRE ; renvoie son libellé ("" si rien à annuler).
func undo() -> String:
	if undo_stack.is_empty():
		return ""
	var e: Dictionary = undo_stack.pop_back()
	var structure_changed := (e["plan"] as IslandPlan).signature() != plan.signature()
	plan = e["plan"]
	rebuild(structure_changed or build == null)
	message = "Annulé : %s" % e["label"]
	return String(e["label"])

# ------------------------------------------------------------------ édition structurelle (à appeler entre begin_op et finish_op)

func set_outline(pts: Array) -> void:
	plan.outline = pts.duplicate()
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p: Vector2 in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	plan.width = snappedf(hi.x - lo.x, 0.1)
	plan.length = snappedf(hi.y - lo.y, 0.1)
	if not IslandPlan.point_in_poly(plan.start, plan.outline):
		plan.start = _centroid(pts)

static func _centroid(pts: Array) -> Vector2:
	var c := Vector2.ZERO
	for p: Vector2 in pts:
		c += p
	return c / maxf(float(pts.size()), 1.0)

func move_outline_point(i: int, p: Vector2) -> void:
	plan.outline[i] = _r2(p)
	_resize_from_outline()

func insert_outline_point(i: int, p: Vector2) -> void:
	plan.outline.insert(i + 1, _r2(p))

func remove_outline_point(i: int) -> bool:
	if plan.outline.size() <= 3:
		return false
	plan.outline.remove_at(i)
	_resize_from_outline()
	return true

func _resize_from_outline() -> void:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p: Vector2 in plan.outline:
		lo = lo.min(p)
		hi = hi.max(p)
	plan.width = snappedf(hi.x - lo.x, 0.1)
	plan.length = snappedf(hi.y - lo.y, 0.1)

static func _r2(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, 0.01), snappedf(p.y, 0.01))

## Pose un disque de zone. Une zone plate prend la hauteur du sol sous son centre (aucune falaise), les autres n'imposent pas de hauteur.
func add_zone_disc(kind: String, c: Vector2, r: float, h := -1.0) -> void:
	var kd: Dictionary = IslandPlan.KINDS[kind]
	if h < 0.0:
		h = 0.0
		if bool(kd["flat"]) and field != null:
			var g := field.ground_at_m(c.x, c.y)
			if not is_nan(g):
				h = snappedf(g, 0.1)
	# un disque de même type presque confondu avec le précédent n'est pas ajouté (traits de pinceau)
	for i in range(plan.zones.size() - 1, maxi(plan.zones.size() - 4, -1), -1):
		var z: Dictionary = plan.zones[i]
		if z["kind"] == kind and (z["c"] as Vector2).distance_to(c) < r * 0.35 and absf(float(z["r"]) - r) < 0.2:
			return
	plan.zones.append({"id": plan.new_id(kind), "kind": kind, "c": _r2(c), "r": snappedf(r, 0.1), "h": h})

func delete_zone_at(p: Vector2) -> void:
	for i in range(plan.zones.size() - 1, -1, -1):
		if p.distance_to(plan.zones[i]["c"]) <= float(plan.zones[i]["r"]):
			plan.zones.remove_at(i)
			return

func add_path(pts: Array, width := 2.2) -> String:
	var id := plan.new_id("chemin")
	var a: Dictionary = plan.zone_at(pts[0])
	var b: Dictionary = plan.zone_at(pts[-1])
	var rp: Array = []
	for p: Vector2 in pts:
		rp.append(_r2(p))
	plan.paths.append({"id": id, "width": width, "pts": rp, "from": String(a.get("id", "")), "to": String(b.get("id", ""))})
	return id

func _relink(pa: Dictionary) -> void:
	var pts: Array = pa["pts"]
	pa["from"] = String(plan.zone_at(pts[0]).get("id", ""))
	pa["to"] = String(plan.zone_at(pts[-1]).get("id", ""))

func move_path_point(id: String, k: int, p: Vector2) -> void:
	var pa := plan.path_by_id(id)
	(pa["pts"] as Array)[k] = _r2(p)
	_relink(pa)

func insert_path_point(id: String, k: int, p: Vector2) -> void:
	var pa := plan.path_by_id(id)
	(pa["pts"] as Array).insert(k + 1, _r2(p))

func remove_path_point(id: String, k: int) -> bool:
	var pa := plan.path_by_id(id)
	var pts: Array = pa["pts"]
	if pts.size() <= 2:
		return false
	pts.remove_at(k)
	_relink(pa)
	return true

func set_path_width(id: String, w: float) -> void:
	plan.path_by_id(id)["width"] = snappedf(clampf(w, 1.0, 6.0), 0.1)

func delete_path(id: String) -> void:
	for i in plan.paths.size():
		if plan.paths[i]["id"] == id:
			plan.paths.remove_at(i)
			return

func add_landmark(kind: String, pos: Vector2, label: String) -> String:
	var id := plan.new_id("repere")
	plan.landmarks.append({"id": id, "kind": kind, "pos": _r2(pos), "label": label})
	return id

func move_landmark(id: String, p: Vector2) -> void:
	for l in plan.landmarks:
		if l["id"] == id:
			l["pos"] = _r2(p)

func delete_landmark(id: String) -> void:
	for i in plan.landmarks.size():
		if plan.landmarks[i]["id"] == id:
			plan.landmarks.remove_at(i)
			return

func set_start(p: Vector2) -> void:
	plan.start = _r2(p)

# ------------------------------------------------------------------ pinceaux (relief, matière, masque)

func col_of(p: Vector2) -> Vector2i:
	return field.col_of_m(p.x, p.y)

func is_protected(i: int) -> bool:
	return plan.layers.mask[i] != 0

## Début d'un trait : l'état d'avant est conservé pour l'annulation ; les hauteurs sont suivies en flottant (plusieurs
## passages cumulent, la quantification à 20 cm n'est faite qu'à l'écriture).
func stroke_begin(label: String, tool: String, at: Vector2) -> void:
	begin_op(label)
	_stroke_has = false
	_stroke_dirty = Rect2i()
	if tool in ["monter", "creuser", "aplanir", "adoucir"]:
		var n := field.n
		_hf.resize(n * n)
		for i in n * n:
			_hf[i] = float(field.top[i])
		var c := col_of(at)
		_target = float(field.top_at(c.x, c.y)) if field.has_ground(c.x, c.y) else 0.0

## Un coup de pinceau. tool : monter, creuser, aplanir, adoucir, matiere, masque, gomme_masque, gomme_matiere.
## strength : cellules (20 cm) par passage pour monter/creuser ; part de rapprochement (0-1) pour aplanir/adoucir.
## Renvoie le rectangle de colonnes touché.
func stroke_dab(tool: String, center: Vector2, radius: float, strength := 0.5, material_id := 0) -> Rect2i:
	var n := field.n
	var cc := col_of(center)
	var rc := int(ceil(radius / V)) + 1
	var lo := Vector2i(maxi(cc.x - rc, 0), maxi(cc.y - rc, 0))
	var hi := Vector2i(mini(cc.x + rc, n - 1), mini(cc.y + rc, n - 1))
	var L := plan.layers
	var tlo := Vector2i(1 << 30, 1 << 30)
	var thi := Vector2i(-1, -1)
	var win := PackedFloat32Array()
	if tool == "adoucir":
		win = _hf.duplicate()
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var i := cx + cz * n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			var d := field.center_m(cx, cz).distance_to(center)
			if d > radius:
				continue
			var w := pow(1.0 - (d / radius) * (d / radius), 2.0) if radius > 0.0 else 1.0
			var changed := false
			match tool:
				"masque":
					if L.mask[i] == 0:
						L.mask[i] = 1
						changed = true
				"gomme_masque":
					if L.mask[i] != 0:
						L.mask[i] = 0
						changed = true
				"matiere":
					if L.mask[i] == 0 and L.mat[i] != material_id:
						L.mat[i] = material_id
						field.material[i] = material_id
						changed = true
				"gomme_matiere":
					if L.mask[i] == 0 and L.mat[i] != 0:
						L.mat[i] = 0
						field.material[i] = build.base_mat[i]
						changed = true
				_:
					if L.mask[i] != 0:
						continue
					match tool:
						"monter":
							_hf[i] += strength * w
						"creuser":
							_hf[i] -= strength * w
						"aplanir":
							_hf[i] = lerpf(_hf[i], _target, clampf(strength * w * 1.4, 0.0, 1.0))
						"adoucir":
							var s := 0.0
							var c := 0
							for dz in range(-2, 3):
								for dx in range(-2, 3):
									var x := cx + dx
									var z := cz + dz
									if x < 0 or z < 0 or x >= n or z >= n:
										continue
									var j := x + z * n
									if field.top[j] == TerrainField.NO_GROUND:
										continue
									s += win[j]
									c += 1
							if c > 0:
								_hf[i] = lerpf(_hf[i], s / float(c), clampf(strength * w * 1.2, 0.0, 1.0))
					var nt := maxi(roundi(_hf[i]), field.core_top[i] + TerrainField.MIN_SURFACE)
					if nt != field.top[i]:
						field.top[i] = nt
						L.set_delta(i, nt - build.base_top[i])
						changed = true
			if changed:
				tlo = Vector2i(mini(tlo.x, cx), mini(tlo.y, cz))
				thi = Vector2i(maxi(thi.x, cx), maxi(thi.y, cz))
	if thi.x < 0:
		return Rect2i()
	var touched := Rect2i(tlo, thi - tlo + Vector2i.ONE)
	_stroke_has = true
	_stroke_dirty = touched if _stroke_dirty.size == Vector2i.ZERO else _stroke_dirty.merge(touched)
	return touched

## Fin du trait : empilé s'il a eu un effet, sinon abandonné (rien à annuler). Renvoie le rectangle de colonnes modifié.
func stroke_end() -> Rect2i:
	var r := _stroke_dirty
	if _stroke_has:
		finish_op(false)
		path_reports = PlanTerrain.path_reports(plan, field)
	else:
		_snap = {}
	_stroke_dirty = Rect2i()
	_stroke_has = false
	_hf = PackedFloat32Array()
	return r

# ------------------------------------------------------------------ régénération du relief dans une sélection

## Relance le relief (autre variante du bruit du plan) dans le rectangle `rect_m` (mètres). Respecte le masque : les colonnes
## protégées ne bougent pas ; un raccord de FEATHER_M adoucit la limite de la sélection et le contour du masque. Les retouches
## hors de la sélection sont conservées. Annulable en une fois. Renvoie {ok, changed, protected, rect, reason}.
func regenerate(rect_m: Rect2, variation := -1) -> Dictionary:
	if field == null:
		return {"ok": false, "reason": "Aucune île à régénérer : dessinez d'abord un contour."}
	if rect_m.size.x < 1.0 or rect_m.size.y < 1.0:
		return {"ok": false, "reason": "Sélection trop petite : tracez un rectangle (au moins 1 m)."}
	_regen_n += 1
	if variation < 0:
		variation = _regen_n
	var n := field.n
	var c0 := field.col_of_m(rect_m.position.x, rect_m.position.y)
	var c1 := field.col_of_m(rect_m.end.x, rect_m.end.y)
	var lo := Vector2i(maxi(c0.x, 0), maxi(c0.y, 0))
	var hi := Vector2i(mini(c1.x, n - 1), mini(c1.y, n - 1))
	var bare := plan.copy()
	bare.layers = null
	var vb := PlanTerrain.build(bare, {"variation": variation, "materials": false})
	if vb.field.n != n:
		return {"ok": false, "reason": "Grille incohérente."}
	var L := plan.layers
	# distance (en colonnes) au masque : deux passes de chanfrein sur la boîte de la sélection élargie
	var gl := Vector2i(maxi(lo.x - 20, 0), maxi(lo.y - 20, 0))
	var gh := Vector2i(mini(hi.x + 20, n - 1), mini(hi.y + 20, n - 1))
	var gw := gh.x - gl.x + 1
	var gh2 := gh.y - gl.y + 1
	var dm := PackedFloat32Array()
	dm.resize(gw * gh2)
	for z in gh2:
		for x in gw:
			dm[x + z * gw] = 0.0 if L.mask[(x + gl.x) + (z + gl.y) * n] != 0 else 1.0e4
	for z in gh2:
		for x in gw:
			var k := x + z * gw
			var v := dm[k]
			if x > 0: v = minf(v, dm[k - 1] + 1.0)
			if z > 0: v = minf(v, dm[k - gw] + 1.0)
			if x > 0 and z > 0: v = minf(v, dm[k - gw - 1] + 1.414)
			if x < gw - 1 and z > 0: v = minf(v, dm[k - gw + 1] + 1.414)
			dm[k] = v
	for z in range(gh2 - 1, -1, -1):
		for x in range(gw - 1, -1, -1):
			var k := x + z * gw
			var v := dm[k]
			if x < gw - 1: v = minf(v, dm[k + 1] + 1.0)
			if z < gh2 - 1: v = minf(v, dm[k + gw] + 1.0)
			if x < gw - 1 and z < gh2 - 1: v = minf(v, dm[k + gw + 1] + 1.414)
			if x > 0 and z < gh2 - 1: v = minf(v, dm[k + gw - 1] + 1.414)
			dm[k] = v
	var feather := FEATHER_M / V
	begin_op("Régénérer le relief (variante %d)" % variation)
	var changed := 0
	var kept := 0
	var dlo := Vector2i(1 << 30, 1 << 30)
	var dhi := Vector2i(-1, -1)
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var i := cx + cz * n
			if field.top[i] == TerrainField.NO_GROUND:
				continue
			if L.mask[i] != 0:
				kept += 1
				continue
			var d_edge := float(mini(mini(cx - lo.x, hi.x - cx), mini(cz - lo.y, hi.y - cz)))
			var d_mask := dm[(cx - gl.x) + (cz - gl.y) * gw]
			var w := smoothstep(0.0, feather, minf(d_edge, d_mask) - 0.5)
			if w <= 0.01:
				continue
			var nt := roundi(lerpf(float(field.top[i]), float(vb.base_top[i]), w))
			nt = maxi(nt, field.core_top[i] + TerrainField.MIN_SURFACE)
			if nt != field.top[i]:
				field.top[i] = nt
				L.set_delta(i, nt - build.base_top[i])
				changed += 1
				dlo = Vector2i(mini(dlo.x, cx), mini(dlo.y, cz))
				dhi = Vector2i(maxi(dhi.x, cx), maxi(dhi.y, cz))
	if changed == 0:
		cancel_op_keep()
		return {"ok": false, "changed": 0, "protected": kept, "reason": "Rien n'a changé : la sélection est entièrement protégée ou déjà identique à cette variante."}
	finish_op(false)
	path_reports = PlanTerrain.path_reports(plan, field)
	message = "Relief régénéré : %d colonnes modifiées, %d protégées par le masque" % [changed, kept]
	return {"ok": true, "changed": changed, "protected": kept, "rect": Rect2i(dlo, dhi - dlo + Vector2i.ONE), "variation": variation}

## Abandonne l'opération en cours SANS reconstruire (aucun changement n'a été écrit).
func cancel_op_keep() -> void:
	_snap = {}

# ------------------------------------------------------------------ maisons (Lot 8)

func house_ctx(need_link := true) -> Dictionary:
	var avoid: Array = []
	for h in plan.houses:
		avoid.append(h["rect"])
	return {"mask": plan.layers.mask if plan.layers != null else PackedByteArray(), "paths": plan.paths, "avoid": avoid,
		"path_cols": build.path_cols if build != null else PackedByteArray(), "keep_clear": [plan.start], "need_link": need_link and not plan.paths.is_empty()}

## Aperçu : implantation d'une maison (modèle normalisé) centrée en `pos`, tournée de `yaw` quarts de tour. Ne modifie rien.
func evaluate_house(model: Construction, pos: Vector2, yaw: int, need_link := true) -> Dictionary:
	if field == null:
		return {"ok": false, "reasons": ["Aucune île : dessinez d'abord un contour."], "changed": []}
	return HousePad.evaluate(field, model, pos, yaw, house_ctx(need_link), false)

## Pose la maison : plateforme, cour et raccord du seuil au chemin sont écrits dans les couches de relief ; une opération, annulable.
## Refus : rien ne change (ni relief, ni liste de maisons, ni pile d'annulation).
func place_house(model: Construction, pos: Vector2, yaw: int, hname := "", need_link := true) -> Dictionary:
	if field == null:
		return {"ok": false, "reasons": ["Aucune île : dessinez d'abord un contour."], "changed": []}
	var before_top := field.top.duplicate()
	var before_mat := field.material.duplicate()
	var res := HousePad.evaluate(field, model, pos, yaw, house_ctx(need_link), true)
	if not bool(res["ok"]):
		return res
	var label := hname if hname != "" else model.name
	begin_op("Poser la maison « %s »" % label)
	var L := plan.layers
	for i in res["changed"]:
		if field.top[i] != before_top[i]:
			L.set_delta(i, field.top[i] - build.base_top[i])
		if field.material[i] != before_mat[i]:
			L.mat[i] = field.material[i]
	var r: Rect2 = res["rect_m"]
	var h := {"id": plan.new_id("maison"), "name": label, "model": model.to_dict(), "pos": res["pos"], "yaw": posmod(yaw, 4), "ground_m": float(res["ground_m"]),
		"rect": r, "door": res.get("door", Vector2.ZERO)}
	plan.houses.append(h)
	finish_op(false)
	path_reports = PlanTerrain.path_reports(plan, field)
	message = "Maison posée : %s" % label
	res["id"] = h["id"]
	return res

const PARCEL_KINDS := ["plateau", "pelouse"]
const PARCEL_REACH_M := 3.0
const AUTO_FULL_EVALS := 20

## Cherche une parcelle compatible du plan (zones « plateau » et « pelouse », abords compris) pour une habitation générée et la pose
## (une opération annulable). L'orientation retenue est celle dont la porte se raccorde le mieux au chemin (raccord court et doux).
## Refus : aucune pose forcée, les raisons sont comptées par catégorie. commit = false : cherche seulement.
func auto_place_dwelling(variant: String, seed: int, fit: Vector2, opts := {}, commit := true) -> Dictionary:
	var out := {"ok": false, "reasons": [], "examined": 0}
	if field == null:
		out["reasons"] = ["Aucune île : dessinez d'abord un contour."]
		return out
	var gen := DwellingGenerator.generate(variant, seed, fit, opts)
	out["gen"] = gen
	if not bool(gen["ok"]):
		out["reasons"] = gen["reasons"]
		return out
	var model: Construction = gen["model"]
	var zones: Array[Dictionary] = []
	for z in plan.zones:
		if PARCEL_KINDS.has(String(z["kind"])):
			zones.append(z)
	if zones.is_empty():
		out["reasons"] = ["Le plan ne contient aucune parcelle (zone « plateau habitable » ou « pelouse ») : l'habitation n'a nulle part où se poser."]
		return out
	if plan.paths.is_empty():
		out["reasons"] = ["Le plan n'a aucun chemin : l'orientation de la porte ne peut pas être choisie ni raccordée."]
		return out
	var ctx := house_ctx(true)
	var occ := HousePad.build_occ(field, ctx)
	ctx["occ"] = occ
	var fp := HousePad.footprint(model)
	var ent: Dictionary = fp["entrance"]
	var counts := {"bord": 0, "occupe": 0, "protege": 0, "relief": 0, "chemin": 0}
	var cands: Array[Dictionary] = []
	var examined := 0
	for z in zones:
		var zc: Vector2 = z["c"]
		var reach := float(z["r"]) + PARCEL_REACH_M
		var steps := int(ceil(reach))
		for dz in range(-steps, steps + 1):
			for dx in range(-steps, steps + 1):
				var p := Vector2(snappedf(zc.x + float(dx), 0.1), snappedf(zc.y + float(dz), 0.1))
				if p.distance_to(zc) > reach or not IslandPlan.point_in_poly(p, plan.outline):
					continue
				for yaw in 4:
					examined += 1
					var key := HousePad.quick_check(field, model, p, yaw, ctx, occ)
					if key != "":
						counts[key] += 1
						continue
					var door := p + HousePad.rot((ent["pos"] as Vector2) - (fp["center"] as Vector2), yaw)
					var np := HousePad.nearest_path(plan.paths, door)
					if np.is_empty() or float(np["d"]) > HousePad.LINK_MAX_M:
						counts["chemin"] += 1
						continue
					cands.append({"pos": p, "yaw": yaw, "zone": String(z["id"]), "dd": float(np["d"]), "dc": p.distance_to(zc)})
	out["examined"] = examined
	out["counts"] = counts
	if cands.is_empty():
		out["reasons"] = [_auto_refusal(model, examined, counts)]
		return out
	cands.sort_custom(func(a, b) -> bool:
		var sa := float(a["dd"]) + 0.4 * float(a["dc"])
		var sb := float(b["dd"]) + 0.4 * float(b["dc"])
		if absf(sa - sb) > 1.0e-6:
			return sa < sb
		var pa: Vector2 = a["pos"]
		var pb: Vector2 = b["pos"]
		if pa.x != pb.x:
			return pa.x < pb.x
		if pa.y != pb.y:
			return pa.y < pb.y
		return int(a["yaw"]) < int(b["yaw"]))
	var best := {}
	var best_score := 1.0e9
	var refused: Array[String] = []
	var tried := 0
	for cd in cands:
		if tried >= AUTO_FULL_EVALS:
			break
		tried += 1
		var ev := HousePad.evaluate(field, model, cd["pos"], int(cd["yaw"]), ctx, false)
		if not bool(ev["ok"]):
			refused.append(String(ev["reasons"][0]))
			continue
		var lk: Dictionary = ev["link"]
		var score := float(lk.get("length", 0.0)) + 8.0 * float(lk.get("grade", 0.0)) + 0.4 * float(cd["dc"]) + 0.01 * float(int(ev["cut"]) + int(ev["fill"]))
		if score < best_score - 1.0e-9:
			best_score = score
			best = cd.duplicate()
			best["eval"] = ev
	if best.is_empty():
		var why := refused[0] if not refused.is_empty() else "aucune implantation complète n'a pu être calculée"
		out["reasons"] = ["Aucune parcelle ne convient pour %s : %d emplacements examinés, %d pré-sélectionnés, mais tous refusés à l'évaluation du terrain (par exemple : %s)" % [model.name, examined, cands.size(), why]]
		return out
	out["pos"] = best["pos"]
	out["yaw"] = best["yaw"]
	out["parcel"] = best["zone"]
	out["eval"] = best["eval"]
	out["door_side"] = HousePad.side_name(HousePad.rot_i(ent["dir"], int(best["yaw"])))
	out["ok"] = true
	if commit:
		var pr := place_house(model, best["pos"], int(best["yaw"]), model.name)
		if not bool(pr["ok"]):
			out["ok"] = false
			out["reasons"] = pr["reasons"]
			return out
		out["placed"] = pr
		var lk2: Dictionary = pr["link"]
		message = "Habitation posée : %s, parcelle « %s », porte côté %s, raccord au chemin %s m (%d %%) — %d emplacements examinés." % [
			model.name, out["parcel"], out["door_side"], Construction.fm(float(lk2.get("length", 0.0)), 1), roundi(float(lk2.get("grade", 0.0)) * 100.0), examined]
	return out

func _auto_refusal(model: Construction, examined: int, counts: Dictionary) -> String:
	var parts: Array[String] = []
	var labels := {"bord": "hors de l'île ou trop près du bord", "occupe": "emplacement occupé (chemin, autre maison, départ)", "protege": "zone protégée par le masque",
		"relief": "relief trop accidenté", "chemin": "porte à plus de %d m d'un chemin" % int(HousePad.LINK_MAX_M)}
	for k in ["protege", "relief", "occupe", "bord", "chemin"]:
		if int(counts[k]) > 0:
			parts.append("%d × %s" % [int(counts[k]), labels[k]])
	var fp := HousePad.footprint(model)
	var sz: Vector2 = fp["size"]
	return "Aucune parcelle compatible pour %s (emprise %s × %s m) : %d positions et orientations examinées sur le plateau et la pelouse, toutes refusées — %s. Rien n'est posé." % [
		model.name, Construction.fm(sz.x), Construction.fm(sz.y), examined, ", ".join(PackedStringArray(parts))]

func remove_house(id: String) -> bool:
	for i in plan.houses.size():
		if String(plan.houses[i]["id"]) == id:
			begin_op("Retirer la maison")
			plan.houses.remove_at(i)
			finish_op(false)
			message = "Maison retirée (le terrain aménagé reste)."
			return true
	return false

func house_at(p: Vector2) -> String:
	for h in plan.houses:
		if (h["rect"] as Rect2).has_point(p):
			return String(h["id"])
	return ""

# ------------------------------------------------------------------ export / ouverture

func export_to(path: String) -> Dictionary:
	return IslandPlan.save_file(plan, path)

## Remplace le document par la carte du fichier. En cas d'erreur, le document courant est conservé ET l'erreur est expliquée.
func open_from(path: String) -> Dictionary:
	var r := IslandPlan.load_file(path)
	if not bool(r["ok"]):
		message = String(r["error"])
		return r
	plan = r["plan"]
	undo_stack.clear()
	_snap = {}
	build = null
	field = null
	rebuild(true)
	message = "Carte ouverte : %s" % plan.name
	return {"ok": true, "plan": plan}

## Compte les colonnes dont la hauteur a changé entre deux relevés (tests).
static func changed_columns(a: PackedInt32Array, b: PackedInt32Array, rect: Rect2i, n: int) -> int:
	var c := 0
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if a[cx + cz * n] != b[cx + cz * n]:
				c += 1
	return c
