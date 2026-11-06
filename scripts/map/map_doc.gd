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
var _hf_ready := PackedByteArray()   # 1 = colonne déjà initialisée dans _hf (initialisation paresseuse)
var _target := 0.0
var _stroke_dirty := Rect2i()
var _stroke_has := false
var _regen_n := 0
var serial := 0                      # compteur d'opérations validées (sert à savoir si le document a changé depuis l'enregistrement)
var saved_serial := 0
var limit_hit := false               # une retouche a atteint la limite de relief (±PlanLayers.MAX_DELTA) pendant le trait en cours
var last_conflict := ""              # dernière opération refusée parce qu'elle casserait une maison (explication)

static func from_plan(p: IslandPlan) -> MapDoc:
	var d := MapDoc.new()
	d.plan = p
	d.rebuild(true)
	return d

static func blank(p_name := "Nouvelle île") -> MapDoc:
	var d := MapDoc.new()
	d.plan = IslandPlan.blank(p_name)
	return d

## Modifications non enregistrées ? (une carte générée et intacte, ou tout juste enregistrée / ouverte, n'est pas modifiée)
func is_dirty() -> bool:
	return serial != saved_serial

func mark_saved() -> void:
	saved_serial = serial

func has_terrain() -> bool:
	return field != null

func layers() -> PlanLayers:
	return plan.layers

## Recalcule le relief de base si la structure du plan a changé, puis ré-applique les retouches.
## keep_houses : changement DEMANDÉ par l'utilisateur (déplacer un chemin, une zone…) → les colonnes de terrain des maisons gardent
## leur hauteur absolue (voir HouseTerrain) ; faux pour l'annulation et l'ouverture, où les couches sont déjà cohérentes avec leur base.
func rebuild(force := false, keep_houses := false) -> void:
	if plan.outline.size() < 3:
		build = null
		field = null
		path_reports = []
		return
	if force or build == null or plan.signature() != build.plan_sig:
		var old_build := build
		build = PlanTerrain.build(plan)
		field = build.field
		rebuilds += 1
		if plan.layers == null:
			plan.layers = PlanLayers.create(field.n, field.origin)
		else:
			var old_n := plan.layers.n
			var old_o := Vector2i(plan.layers.ox, plan.layers.oz)
			plan.layers.fit(field.n, field.origin)
			if keep_houses and old_build != null and not plan.houses.is_empty():
				_carry_houses(old_build, old_n, old_o)
	elif plan.layers == null:
		plan.layers = PlanLayers.create(field.n, field.origin)
	PlanTerrain.apply_layers(build, plan)
	path_reports = PlanTerrain.path_reports(plan, field)

## Maisons : conserve la hauteur absolue des colonnes aménagées quand le relief de base change (appelée APRÈS le recalage des couches).
## Pour chaque colonne de chaque maison : nouvelle retouche = retouche actuelle + (ancien relief de base − nouveau relief de base), ce qui
## garde absolu = base + retouche, y compris les retouches indépendantes faites depuis la pose. Les valeurs « avant pose » et « posées »
## de la maison sont décalées de la même façon (restauration cohérente) et ses indices convertis dans la nouvelle grille.
## Retouche hors limites (±MAX_DELTA) ou colonne sortie de la grille : `carry_problems` le dit (conflit signalé par finish_op).
func _carry_houses(old_build: PlanTerrain.Build, old_n: int, old_o: Vector2i) -> void:
	var L := plan.layers
	var nf := build.field
	var nn := nf.n
	carry_problems.clear()
	var shifted := {}
	for h in plan.houses:
		if not h.has("terrain"):
			continue
		var t: Dictionary = h["terrain"]
		var cells: PackedInt32Array = t["cells"]
		var tbd: PackedInt32Array = t["before_d"]
		var tpd: PackedInt32Array = t["placed_d"]
		var tbm: PackedByteArray = t["before_m"]
		var tpm: PackedByteArray = t["placed_m"]
		var keep := PackedInt32Array()
		var kbd := PackedInt32Array()
		var kpd := PackedInt32Array()
		var kbm := PackedByteArray()
		var kpm := PackedByteArray()
		var lost := 0
		for k in cells.size():
			var oi := cells[k]
			var tn := int(t["n"])
			var nx := (oi % tn) + int(t["ox"]) - nf.origin.x       # la maison suit la grille des couches (t["n"], t["ox"], t["oz"])
			var nz := (oi / tn) + int(t["oz"]) - nf.origin.y
			if nx < 0 or nz < 0 or nx >= nn or nz >= nn or oi >= old_build.base_top.size():
				lost += 1
				continue
			var ni := nx + nz * nn
			var ob: int = old_build.base_top[oi]
			var nb: int = build.base_top[ni]
			if ob == TerrainField.NO_GROUND or nb == TerrainField.NO_GROUND:
				lost += 1
				continue
			var shift := ob - nb
			if not shifted.has(ni):
				shifted[ni] = true
				if absi(L.delta[ni] + shift) > PlanLayers.MAX_DELTA:
					carry_problems.append("%s : le relief de base change de %.1f m sous la maison, au-delà de la limite de retouche." % [h["name"], absf(float(shift)) * 0.2])
				else:
					L.delta[ni] += shift
			keep.append(ni)
			kbd.append(tbd[k] + shift)
			kpd.append(tpd[k] + shift)
			kbm.append(tbm[k])
			kpm.append(tpm[k])
		if lost > 0:
			carry_problems.append("%s : %d colonnes d'aménagement sortiraient de l'île." % [h["name"], lost])
		t["cells"] = keep
		t["before_d"] = kbd
		t["placed_d"] = kpd
		t["before_m"] = kbm
		t["placed_m"] = kpm
		t["n"] = nn
		t["ox"] = nf.origin.x
		t["oz"] = nf.origin.y

var carry_problems: Array[String] = []

# ------------------------------------------------------------------ opérations et annulation

func begin_op(label: String) -> void:
	_snap = {"label": label, "plan": plan.copy()}

## Termine l'opération : l'état d'avant est empilé (annulable). Renvoie "" ou une raison de refus (opération défaite).
## Refus (rien ne change) : contour qui se croise ; ou modification du plan qui casserait l'implantation d'une maison posée
## (fondations, seuil, raccord au chemin) — la raison est expliquée en détail.
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
		var structural := build == null or plan.signature() != build.plan_sig
		rebuild(false, true)
		if structural and not plan.houses.is_empty():
			var cf := house_conflicts()
			if not cf.is_empty():
				var snap2 := _snap
				_snap = {}
				plan = snap2["plan"]
				rebuild(true)
				last_conflict = "Modification refusée (« %s ») : elle casserait une maison posée. %s L'opération est annulée, rien n'a changé." % [snap2["label"], " ".join(PackedStringArray(cf))]
				message = last_conflict
				return message
	undo_stack.append(_snap)
	if undo_stack.size() > UNDO_MAX:
		undo_stack.pop_front()
	message = String(_snap["label"])
	_snap = {}
	serial += 1
	return ""

## Maisons dont l'implantation ne tient plus sur le terrain actuel : liste de phrases (vide = tout est cohérent).
func house_conflicts() -> Array[String]:
	var out: Array[String] = []
	for s in carry_problems:
		out.append(s)
	carry_problems.clear()
	if field == null:
		return out
	for h in plan.houses:
		var nm := String(h["name"]) if String(h["name"]) != "" else "la maison"
		var rect_m: Rect2 = h["rect"]
		var c0 := field.col_of_m(rect_m.position.x, rect_m.position.y)
		var c1 := field.col_of_m(rect_m.end.x - 0.001, rect_m.end.y - 0.001)
		var off := false
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				if not field.has_ground(cx, cz) or field.edge_dist[field.idx(cx, cz)] < HousePad.EDGE_MIN_M * 0.5:
					off = true
		if off:
			out.append("« %s » ne serait plus entièrement sur l'île (ou trop près du bord)." % nm)
			continue
		if h.has("link"):
			var lk: Dictionary = h["link"]
			var q: Vector2 = lk["to"]
			var np := HousePad.nearest_path(plan.paths, q)
			var hw := 0.7
			if not np.is_empty():
				var pa := plan.path_by_id(String(np["path_id"]))
				hw = float(pa.get("width", 2.0)) * 0.5
			if np.is_empty() or float(np["d"]) > hw + 0.6:
				out.append("Le chemin s'éloignerait du raccord de « %s » : le seuil ne serait plus relié au chemin (écart %s m)." % [nm, Construction.fm(float(np["d"]) if not np.is_empty() else 99.0, 1)])
		if h.has("terrain"):
			var t: Dictionary = h["terrain"]
			var inside := {}
			for i in t["cells"]:
				inside[i] = true
			var worst := 0
			for i in t["cells"]:
				if field.top[i] == TerrainField.NO_GROUND:
					continue
				var cx2: int = i % field.n
				var cz2: int = i / field.n
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = cx2 + o.x
					var nz: int = cz2 + o.y
					if field.has_ground(nx, nz) and not inside.has(field.idx(nx, nz)):
						worst = maxi(worst, absi(field.top[i] - field.top[field.idx(nx, nz)]))
			if worst > HousePad.CUT + HousePad.FILL:
				out.append("Le terrain autour de « %s » changerait de %s m : sa plateforme se raccorderait par une falaise." % [nm, Construction.fm(float(worst) * V, 1)])
	return out

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
	var r_undo: Rect2i = e.get("rect", Rect2i())
	if not structure_changed and build != null and field != null and r_undo.size != Vector2i.ZERO:
		PlanTerrain.apply_layers_rect(build, plan, r_undo.grow(1))
		path_reports = PlanTerrain.path_reports(plan, field)
	else:
		rebuild(structure_changed or build == null)
	serial += 1
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
	limit_hit = false
	_stroke_dirty = Rect2i()
	if tool in ["monter", "creuser", "aplanir", "adoucir"]:
		# Lot 11 : hauteurs flottantes initialisées PAR COLONNE au premier passage du pinceau (plus de boucle sur toute la carte)
		var n := field.n
		_hf.resize(n * n)
		_hf_ready.resize(n * n)
		_hf_ready.fill(0)
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
	var relief_tool := tool in ["monter", "creuser", "aplanir", "adoucir"]
	var margin := 2 if tool == "adoucir" else 0
	var wlo := Vector2i(maxi(lo.x - margin, 0), maxi(lo.y - margin, 0))
	var whi := Vector2i(mini(hi.x + margin, n - 1), mini(hi.y + margin, n - 1))
	if relief_tool:
		for wz in range(wlo.y, whi.y + 1):
			for wx in range(wlo.x, whi.x + 1):
				var wi := wx + wz * n
				if _hf_ready[wi] == 0:
					_hf_ready[wi] = 1
					_hf[wi] = float(field.top[wi])
	# fenêtre de lissage : copie des seules hauteurs voisines (valeurs d'AVANT ce coup), au lieu de toute la carte
	var win := PackedFloat32Array()
	var ww := whi.x - wlo.x + 1
	if tool == "adoucir":
		win.resize(ww * (whi.y - wlo.y + 1))
		for wz in range(wlo.y, whi.y + 1):
			for wx in range(wlo.x, whi.x + 1):
				win[(wx - wlo.x) + (wz - wlo.y) * ww] = _hf[wx + wz * n]
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
									s += win[(x - wlo.x) + (z - wlo.y) * ww]
									c += 1
							if c > 0:
								_hf[i] = lerpf(_hf[i], s / float(c), clampf(strength * w * 1.2, 0.0, 1.0))
					var nt := maxi(roundi(_hf[i]), field.core_top[i] + TerrainField.MIN_SURFACE)
					var lim := PlanLayers.limit_top(build.base_top[i], nt)
					if lim != nt:
						limit_hit = true        # jamais écrêté en silence : l'éditeur le dit
						nt = lim
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
		_snap["rect"] = r            # l'annulation de ce trait ne recalcule que ce rectangle
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
			nt = PlanLayers.limit_top(build.base_top[i], nt)
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
	var before_d := L.delta.duplicate()
	var before_m := L.mat.duplicate()
	for i in res["changed"]:
		if field.top[i] != before_top[i]:
			var lim := PlanLayers.limit_top(build.base_top[i], field.top[i])
			field.top[i] = lim
			L.set_delta(i, lim - build.base_top[i])
		if field.material[i] != before_mat[i]:
			L.mat[i] = field.material[i]
	var r: Rect2 = res["rect_m"]
	var h := {"id": plan.new_id("maison"), "name": label, "model": model.to_dict(), "pos": res["pos"], "yaw": posmod(yaw, 4), "ground_m": float(res["ground_m"]),
		"rect": r, "door": res.get("door", Vector2.ZERO), "terrain": HouseTerrain.make(L, before_d, before_m, res["changed"])}
	var lk: Dictionary = res.get("link", {})
	if not lk.is_empty() and bool(lk.get("ok", false)):
		h["link"] = {"to": lk["to"], "path_id": String(lk["path_id"])}
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

## Retire une maison. restore_terrain (défaut) : le terrain est RESTAURÉ colonne par colonne là où il n'a pas été retouché depuis la pose
## (une colonne dont la retouche ou la matière a changé depuis — sculptée, repeinte — est CONSERVÉE telle quelle) ; sinon (ou pour une maison
## posée avant le Lot 11, qui n'a pas gardé son terrain d'origine) le terrain aménagé reste. `remove_stats` dit ce qui s'est passé.
## Une seule opération annulable (Ctrl+Z remet la maison ET son terrain).
func remove_house(id: String, restore_terrain := true) -> bool:
	for i in plan.houses.size():
		if String(plan.houses[i]["id"]) != id:
			continue
		var h: Dictionary = plan.houses[i]
		begin_op("Retirer la maison")
		var restored := 0
		var kept := 0
		var legacy := not h.has("terrain")
		if restore_terrain and not legacy:
			var L := plan.layers
			var t: Dictionary = h["terrain"]
			for k in (t["cells"] as PackedInt32Array).size():
				var ci: int = t["cells"][k]
				var touched := false
				if L.delta[ci] == int(t["placed_d"][k]):
					L.delta[ci] = int(t["before_d"][k])
				else:
					touched = true
				if L.mat[ci] == int(t["placed_m"][k]):
					L.mat[ci] = int(t["before_m"][k])
				else:
					touched = true
				if touched:
					kept += 1
				else:
					restored += 1
		plan.houses.remove_at(i)
		finish_op(false)
		rebuild(false)
		path_reports = PlanTerrain.path_reports(plan, field)
		remove_stats = {"restored": restored, "kept": kept, "legacy": legacy, "restore": restore_terrain}
		if not restore_terrain:
			message = "Maison retirée (terrain aménagé conservé comme demandé)."
		elif legacy:
			message = "Maison retirée. Elle avait été posée avant le Lot 11 : son terrain d'origine n'est pas connu, le terrain aménagé reste (Ctrl+Z pour tout annuler)."
		else:
			message = "Maison retirée : terrain restauré sur %d colonnes%s." % [restored, ", %d colonnes retouchées depuis la pose ont été conservées" % kept if kept > 0 else ""]
		return true
	return false

var remove_stats := {}

func house_at(p: Vector2) -> String:
	for h in plan.houses:
		if (h["rect"] as Rect2).has_point(p):
			return String(h["id"])
	return ""

# ------------------------------------------------------------------ export / ouverture

## Enregistre la carte (écriture sûre). Le document n'est marqué « enregistré » que si l'écriture a réussi : sinon il reste ouvert et modifié.
func export_to(path: String) -> Dictionary:
	var r := IslandPlan.save_file(plan, path)
	if bool(r["ok"]):
		mark_saved()
	else:
		message = String(r["error"])
	return r

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
	serial = 0
	saved_serial = 0
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
