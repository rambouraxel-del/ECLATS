class_name HousePad
extends RefCounted
## IMPLANTATION D'UNE MAISON SUR UN TERRAIN (Lots 8-9) : plateforme sous l'emprise + cour (réutilise TerrainEditor, comme le
## laboratoire) et RACCORD du seuil au chemin le plus proche. Fonctionne sur un TerrainField ; l'éditeur de carte en déduit les
## retouches de relief (couches du plan) et le laboratoire s'en sert pour ses habitations.
##
## evaluate(field, model, pos, yaw, ctx, commit) → {ok, reasons[], rect, rect_m, ground_m, cut, fill, changed[], link{}, door, dir, text}
## Le terrain n'est modifié que si ok ET commit ; sinon il est restauré à l'identique (relief, matières, zones).
## ctx : mask (PackedByteArray des colonnes protégées, optionnel) · paths (chemins du plan) · avoid (Array[Rect2], emprises déjà prises)
##       path_cols (colonnes de chemin, optionnel) · keep_clear (Array[Vector2], points à dégager) · need_link (bool)

const V := VoxelGrid.VOXEL_SIZE
const YARD := 3
const CUT := 4
const FILL := 4
const EDGE_MIN_M := 1.2
const LINK_MAX_M := 14.0
const LINK_WIDTH_M := 1.4
const LINK_GRADE := 0.30
const OVERHANG := 0.3

static func rot(v: Vector2, yaw: int) -> Vector2:
	match posmod(yaw, 4):
		1: return Vector2(v.y, -v.x)
		2: return Vector2(-v.x, -v.y)
		3: return Vector2(-v.y, v.x)
	return v

static func rot_i(v: Vector2i, yaw: int) -> Vector2i:
	var r := rot(Vector2(v), yaw)
	return Vector2i(roundi(r.x), roundi(r.y))

## Emprise locale (m) avec débord de toit, centre, entrée.
static func footprint(model: Construction) -> Dictionary:
	var bb := model.bbox_m()
	var r := bb.grow(OVERHANG)
	return {"rect": r, "center": r.get_center(), "size": r.size, "entrance": model.entrance()}

## Transformation 3D du nœud de la construction (modèle normalisé, base_y = 0) posée en `pos` (centre de l'emprise) à la hauteur `ground_m`.
static func node_transform(model: Construction, pos: Vector2, yaw: int, ground_m: float) -> Transform3D:
	var fp := footprint(model)
	var b := Basis(Vector3.UP, float(posmod(yaw, 4)) * PI * 0.5)
	var c: Vector2 = fp["center"]
	return Transform3D(b, Vector3(pos.x, ground_m, pos.y) + b * Vector3(-c.x, 0.0, -c.y))

static func size_for(model: Construction, yaw: int) -> Vector2:
	var s: Vector2 = footprint(model)["size"]
	return Vector2(s.y, s.x) if posmod(yaw, 2) == 1 else s

static func _cols(field: TerrainField, r: Rect2) -> Rect2i:
	var c0 := field.col_of_m(r.position.x, r.position.y)
	var c1 := field.col_of_m(r.end.x - 0.001, r.end.y - 0.001)
	return Rect2i(c0, c1 - c0 + Vector2i.ONE)

static func _seg_closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
	return a + ab * t

## Chemin le plus proche d'un point : {q, d, path_id} ou {}.
static func nearest_path(paths: Array, p: Vector2) -> Dictionary:
	var best := {}
	var bd := 1.0e9
	for pa in paths:
		var pts: Array = pa["pts"]
		for k in range(pts.size() - 1):
			var q := _seg_closest(p, pts[k], pts[k + 1])
			var d := p.distance_to(q)
			if d < bd:
				bd = d
				best = {"q": q, "d": d, "path_id": String(pa.get("id", ""))}
	return best

static func _reason(key: String, ctx := {}) -> String:
	match key:
		"hors_ile": return "L'emprise de la maison sort de l'île."
		"trop_pres_du_bord": return "Trop près du bord de l'île (marge de sécurité de %s m non respectée)." % Construction.fm(EDGE_MIN_M)
		"reserve": return "L'emprise touche un espace déjà occupé : une autre maison, un chemin ou le point de départ."
		"relief_trop_accidente": return "Relief trop accidenté pour cette emprise : %s m de dénivelé, la plateforme n'en rattrape que %s m." % [Construction.fm(float(ctx.get("range_m", 0.0)), 2), Construction.fm(float(CUT + FILL) * V, 2)]
	return key

static func _snapshot(f: TerrainField) -> Dictionary:
	return {"top": f.top.duplicate(), "zone": f.zone.duplicate(), "mat": f.material.duplicate()}

static func _restore(f: TerrainField, s: Dictionary) -> void:
	f.top = s["top"]
	f.zone = s["zone"]
	f.material = s["mat"]

static func evaluate(field: TerrainField, model: Construction, pos: Vector2, yaw: int, ctx := {}, commit := false) -> Dictionary:
	pos = Vector2(snappedf(pos.x, 0.1), snappedf(pos.y, 0.1))       # positions à 10 cm : le fichier de carte les garde à l'identique
	var fp := footprint(model)
	var size := size_for(model, yaw)
	var rect_m := Rect2(pos - size * 0.5, size)
	var res := {"ok": false, "reasons": [], "rect_m": rect_m, "pos": pos, "yaw": posmod(yaw, 4), "changed": [], "link": {}, "text": "", "size": size}
	if model.is_empty() or size == Vector2.ZERO:
		res["reasons"] = ["Cette maison est vide."]
		return res
	var ent: Dictionary = fp["entrance"]
	var center: Vector2 = fp["center"]
	var door := Vector2.ZERO
	var dir := Vector2i.ZERO
	if not ent.is_empty():
		door = pos + rot((ent["pos"] as Vector2) - center, yaw)
		dir = rot_i(ent["dir"], yaw)
		res["door"] = door
		res["dir"] = dir
		res["door_wall"] = pos + rot((ent["door"] as Vector2) - center, yaw)
	elif bool(ctx.get("need_link", false)):
		res["reasons"] = ["Cette maison n'a pas de porte d'entrée au rez-de-chaussée : aucun accès n'est possible. Ajoutez une porte dans l'atelier."]
		return res
	var rect := _cols(field, rect_m)
	res["rect"] = rect
	var mask: PackedByteArray = ctx.get("mask", PackedByteArray())
	var occ := OccupancyMap.new(field)
	var paths: Array = ctx.get("paths", [])
	for pa in paths:
		var pts: Array = pa["pts"]
		var hw := float(pa["width"]) * 0.5 + 0.4
		for k in range(pts.size() - 1):
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var lo := field.col_of_m(minf(a.x, b.x) - hw, minf(a.y, b.y) - hw)
			var hi := field.col_of_m(maxf(a.x, b.x) + hw, maxf(a.y, b.y) + hw)
			# le raccord doit pouvoir arriver au chemin : on ne réserve que sa bande, pas ses abords proches de la porte
			for cz in range(lo.y, hi.y + 1):
				for cx in range(lo.x, hi.x + 1):
					if field.has_ground(cx, cz) and field.center_m(cx, cz).distance_to(_seg_closest(field.center_m(cx, cz), a, b)) <= hw:
						occ.tag[field.idx(cx, cz)] = PlacementSpec.TAG_ROAD
	for r2: Rect2 in ctx.get("avoid", []):
		occ.reserve(_cols(field, r2.grow(0.8)), PlacementSpec.TAG_PLOT, occ.new_owner())
	for kp: Vector2 in ctx.get("keep_clear", []):
		occ.reserve_disc(kp, 1.6, PlacementSpec.TAG_ITEM, occ.new_owner())
	var snap := _snapshot(field)
	var ev := TerrainEditor.evaluate_pad(field, occ, rect, YARD, CUT, FILL, 2, PackedInt32Array(), EDGE_MIN_M)
	if not bool(ev["ok"]):
		var hr := field.height_range(rect)
		res["reasons"] = [_reason(String(ev["reason"]), {"range_m": float(hr.y - hr.x) * V if hr.x != TerrainField.NO_GROUND else 0.0})]
		return res
	var target: int = ev["target"]
	var yard := Rect2i(rect.position - Vector2i(YARD, YARD), rect.size + Vector2i(YARD, YARD) * 2)
	var dirt := VoxelPalette.get_default().id("path_dirt")
	TerrainEditor.stamp_pad(field, yard, target, TerrainField.Zone.PLOT, dirt, true)
	res["target"] = target
	res["ground_m"] = float(target + 1) * V
	res["cut"] = int(ev["cut"])
	res["fill"] = int(ev["fill"])
	res["yard"] = yard
	# ---- raccord du seuil au chemin
	var link := {}
	if not ent.is_empty() and not paths.is_empty():
		var np := nearest_path(paths, door)
		if np.is_empty() or float(np["d"]) > LINK_MAX_M:
			if bool(ctx.get("need_link", true)):
				_restore(field, snap)
				res["reasons"] = ["Aucun chemin à moins de %s m de la porte (le plus proche : %s m). Rapprochez la maison d'un chemin ou changez son orientation." % [Construction.fm(LINK_MAX_M, 0), Construction.fm(float(np.get("d", 0.0)), 1) if not np.is_empty() else "aucun"]]
				return res
		else:
			link = _carve_link(field, res, door, np, ctx)
			if not bool(link["ok"]):
				_restore(field, snap)
				res["reasons"] = [String(link["reason"])]
				res["link"] = link
				return res
	res["link"] = link
	# ---- colonnes modifiées, respect du masque
	var changed: Array[int] = []
	var protected := 0
	for i in field.n * field.n:
		if field.top[i] != snap["top"][i] or field.material[i] != snap["mat"][i]:
			changed.append(i)
			if mask.size() == field.n * field.n and mask[i] != 0:
				protected += 1
	if protected > 0:
		_restore(field, snap)
		res["reasons"] = ["Zone protégée : la plateforme de la maison et son raccord de terrain toucheraient %d colonnes protégées par le masque. Déplacez la maison ou retirez la protection." % protected]
		res["protected"] = protected
		return res
	res["changed"] = changed
	res["ok"] = true
	var parts: Array[String] = ["Implantation possible · niveau du sol %s m · déblai %d / remblai %d cellules · %d colonnes de terrain raccordées" % [
		Construction.fm(float(res["ground_m"]), 2), int(res["cut"]), int(res["fill"]), changed.size()]]
	if not link.is_empty():
		parts.append("raccord au chemin %s m, pente %d %%" % [Construction.fm(float(link["length"]), 1), roundi(float(link["grade"]) * 100.0)])
	res["text"] = " · ".join(PackedStringArray(parts))
	if commit:
		field.zone = snap["zone"]       # les zones ne sont que transitoires
	else:
		_restore(field, snap)
	return res

## Bande de 1,4 m de large du seuil au chemin ; hauteur interpolée ; refus si la pente dépasse 30 % ou si elle traverse la maison.
static func _carve_link(field: TerrainField, res: Dictionary, door: Vector2, np: Dictionary, ctx: Dictionary) -> Dictionary:
	var q: Vector2 = np["q"]
	var len := door.distance_to(q)
	var out := {"ok": true, "from": door, "to": q, "length": len, "path_id": np["path_id"], "grade": 0.0, "reason": ""}
	var yard: Rect2i = res["yard"]
	var rect_m: Rect2 = res["rect_m"]
	var h0: float = res["ground_m"]
	var g := field.ground_at_m(q.x, q.y)
	if is_nan(g):
		out["ok"] = false
		out["reason"] = "Le chemin le plus proche est hors de l'île à cet endroit."
		return out
	var dh := g - h0
	out["dh"] = dh
	out["grade"] = absf(dh) / maxf(len, 0.5)
	if len > 1.0:
		# la droite ne doit pas retraverser la maison
		for k in range(1, 20):
			var p := door.lerp(q, float(k) / 20.0)
			if rect_m.grow(-0.05).has_point(p) and p.distance_to(door) > 0.5:
				out["ok"] = false
				out["reason"] = "Le chemin le plus proche est derrière la maison : la porte ne peut pas s'y raccorder. Tournez la maison pour que la porte regarde vers le chemin."
				return out
	if float(out["grade"]) > LINK_GRADE + 1.0e-4:
		out["ok"] = false
		out["reason"] = "Raccord seuil–chemin trop raide : %d %% sur %s m (maximum %d %%) ; le chemin est %s m %s que le seuil. Choisissez un emplacement moins en pente ou plus près du chemin." % [
			roundi(float(out["grade"]) * 100.0), Construction.fm(len, 1), roundi(LINK_GRADE * 100.0), Construction.fm(absf(dh), 1), "plus haut" if dh > 0.0 else "plus bas"]
		return out
	var path_cols: PackedByteArray = ctx.get("path_cols", PackedByteArray())
	var band := {}
	var hw := LINK_WIDTH_M * 0.5
	var lo := field.col_of_m(minf(door.x, q.x) - hw - 0.2, minf(door.y, q.y) - hw - 0.2)
	var hi := field.col_of_m(maxf(door.x, q.x) + hw + 0.2, maxf(door.y, q.y) + hw + 0.2)
	var dirt := VoxelPalette.get_default().id("path_dirt")
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if not field.has_ground(cx, cz) or yard.has_point(Vector2i(cx, cz)):
				continue
			var i := field.idx(cx, cz)
			if path_cols.size() == field.n * field.n and path_cols[i] == 1:
				continue
			var c := field.center_m(cx, cz)
			var cl := _seg_closest(c, door, q)
			if c.distance_to(cl) > hw:
				continue
			var t := clampf(door.distance_to(cl) / maxf(len, 0.01), 0.0, 1.0)
			var h := lerpf(h0, g, t)
			var top := roundi(h / V) - 1
			if field.set_top(cx, cz, top, TerrainField.Zone.ROAD, dirt) or true:
				band[i] = top
	if not band.is_empty():
		TerrainEditor.apply_skirt(field, band, 6)
	out["columns"] = band.size()
	return out
