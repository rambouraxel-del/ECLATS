@tool
class_name WorldValidator
extends RefCounted
## Validation AUTOMATIQUE d'une île générée, valable pour n'importe quelle graine ou profil.
## Chaque contrôle recalcule son diagnostic à partir de l'état FINAL (terrain après terrassements et routes,
## volumes réels des bâtiments, arbres, rochers, port, bateau) : si une étape tardive casse une étape précoce,
## le défaut apparaît ici.
##
## Contrôles :
##   terrain      · cœur fixe respecté · cellules de terrain isolées
##   objets       · intersections de volumes durs · objets flottants (support RECALCULÉ) · bâtiments traversés par le terrain
##   bâtiments    · fondations portées · intérieur visitable (BuildingValidator : portes, escaliers, 1,80 m, meubles)
##   arbres       · bois d'un seul tenant, pied enraciné, feuillage rattaché à une branche
##   rochers      · enfoncés dans le sol, d'un seul tenant
##   circulation  · routes continues (marche ≤ 20 cm) · entrées, sanctuaire et port reliés à la place
##   port         · appontement ancré, sans traverser le terrain ; bateau (voiles, mâts) sans croisement ; bateau hors ponton
##   déterminisme · signature de l'île (voir signature())
## Résultat : {issues: [{check, severity, message}], checks: {nom: {checked, failed}}, summary: {errors, warnings}}

const V := VoxelGrid.VOXEL_SIZE

var w: WorldData
var issues: Array[Dictionary] = []
var checks := {}

static func validate(world: WorldData, opts := {}) -> Dictionary:
	var v := WorldValidator.new()
	v.w = world
	v._terrain()
	v._items()
	v._buildings(bool(opts.get("buildings", true)))
	v._trees()
	v._rocks()
	v._circulation()
	v._port()
	var errors := 0
	var warnings := 0
	for i in v.issues:
		if i["severity"] == "error":
			errors += 1
		else:
			warnings += 1
	return {"issues": v.issues, "checks": v.checks, "summary": {"errors": errors, "warnings": warnings}}

func _count(check: String, n := 1) -> void:
	if not checks.has(check):
		checks[check] = {"checked": 0, "failed": 0}
	checks[check]["checked"] += n

func _fail(check: String, severity: String, msg: String) -> void:
	_count(check, 0)
	checks[check]["failed"] += 1
	issues.append({"check": check, "severity": severity, "message": msg})

# ------------------------------------------------------------------ terrain

func _terrain() -> void:
	var f := w.field
	var n := f.n
	_count("terrain.coeur", f.land_count())
	var bad := 0
	for i in n * n:
		if f.top[i] == TerrainField.NO_GROUND:
			continue
		if f.top[i] < f.core_top[i] + TerrainField.MIN_SURFACE:
			bad += 1
	if bad > 0:
		_fail("terrain.coeur", "error", "%d colonnes sous la surface modifiable minimale (le cœur fixe a été entamé)" % bad)
	# composantes de colonnes (4 voisins)
	_count("terrain.cellules_isolees")
	var seen := PackedByteArray()
	seen.resize(n * n)
	var comps: Array[int] = []
	for s in n * n:
		if f.top[s] == TerrainField.NO_GROUND or seen[s] == 1:
			continue
		var stack: Array[int] = [s]
		seen[s] = 1
		var size := 0
		while not stack.is_empty():
			var i: int = stack.pop_back()
			size += 1
			var cx := i % n
			var cz := i / n
			for o in WorldNav.NEIGH:
				var x: int = cx + o.x
				var z: int = cz + o.y
				if x < 0 or z < 0 or x >= n or z >= n:
					continue
				var j := x + z * n
				if f.top[j] != TerrainField.NO_GROUND and seen[j] == 0:
					seen[j] = 1
					stack.append(j)
		comps.append(size)
	comps.sort()
	if comps.size() > 1:
		var small := 0
		for k in comps.size() - 1:
			small += comps[k]
		_fail("terrain.cellules_isolees", "error" if small < 400 else "warning", "%d morceau(x) de terrain détaché(s) (%d colonnes) en plus de l'île principale" % [comps.size() - 1, small])

# ------------------------------------------------------------------ objets (volumes durs)

func _recomputed_support(item: Dictionary) -> Dictionary:
	var f := w.field
	var rect: Rect2i = item["rect"]
	var spec: PlacementSpec = item["spec"]
	var base_y: float = (item["pos"] as Vector3).y
	var cols := 0
	var supported := 0
	var above := 0
	var gap := spec.gap_tolerance_m + 0.2     # + fondation enterrée des bâtiments (20 cm)
	var embed := spec.embed_max_m + 0.001
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if not f.has_ground(cx, cz):
				continue
			cols += 1
			var gy := f.ground_y_m(cx, cz)
			if gy >= base_y - gap - 0.001:
				supported += 1
			if gy > base_y + embed + 0.001 and spec.kind != "plant":
				above += 1
	return {"cols": cols, "supported": supported, "above": above}

func _items() -> void:
	var items := w.occ.items
	_count("objets.intersections", items.size())
	_count("objets.flottants", items.size())
	var overlaps := 0
	var reported := 0
	for a in items.size():
		var ia: Dictionary = items[a]
		var ua: AABB = PlacementSystem._union(ia["hard"]) if not (ia["hard"] as Array).is_empty() else AABB()
		if (ia["hard"] as Array).is_empty():
			continue
		for b in w.occ.candidates(ua, 0.0):
			if b <= a:
				continue
			var ib: Dictionary = items[b]
			var exempt: PackedStringArray = (ib["exceptions"] as PackedStringArray) if ib.has("exceptions") else PackedStringArray()
			var exempt_a: PackedStringArray = ia["exceptions"] if ia.has("exceptions") else PackedStringArray()
			var hit := false
			for ha: AABB in ia["hard"]:
				for hb: AABB in ib["hard"]:
					if ha.intersects(hb):
						if (exempt.has("in_building") and ia["kind"] == "building") or (exempt_a.has("in_building") and ib["kind"] == "building"):
							continue
						hit = true
			if hit:
				overlaps += 1
				if reported < 6:
					reported += 1
					_fail("objets.intersections", "error", "%s et %s se chevauchent" % [ia["id"], ib["id"]])
	# objets flottants : support recalculé sur le terrain final
	var floating := 0
	for it in items:
		var spec: PlacementSpec = it["spec"]
		if spec.support == "none":
			continue
		var s := _recomputed_support(it)
		if s["cols"] == 0:
			continue
		var frac := float(s["supported"]) / float(s["cols"])
		var need := spec.support_fraction - 0.05
		if spec.allows_exception("overhang_void"):
			need = 0.4
		if frac < need:
			floating += 1
			if floating <= 6:
				_fail("objets.flottants", "error", "%s flotte (support %.0f %% < %.0f %%)" % [it["id"], frac * 100.0, spec.support_fraction * 100.0])
		if it["kind"] == "building" and s["above"] > 0:
			_fail("objets.batiment_traverse", "error", "%s : le terrain traverse le bâtiment (%d colonnes plus hautes que le sol fini)" % [it["id"], s["above"]])
	_count("objets.batiment_traverse", w.buildings.size())

# ------------------------------------------------------------------ bâtiments

func _buildings(deep: bool) -> void:
	_count("batiments.fondations", w.buildings.size())
	_count("batiments.interieur", w.buildings.size() if deep else 0)
	for b in w.buildings:
		var res: PlacementResult = b["res"]
		if res.support < 0.97:
			_fail("batiments.fondations", "error", "%s : fondation portée à %.0f %% seulement" % [b["type"], res.support * 100.0])
		if deep and b.has("model"):
			var r := BuildingValidator.validate(b["model"])
			for e in r["errors"]:
				_fail("batiments.interieur", "error", "%s (graine %d) : %s" % [b["type"], b["plan"].seed, e])

# ------------------------------------------------------------------ arbres, rochers

func _trees() -> void:
	_count("arbres.ancrage", w.trees.size())
	for t in w.trees:
		if not t.has("model"):
			continue
		var iss := TreeGenerator.check(t["model"], t["ground"])
		for s in iss:
			_fail("arbres.ancrage", "error", "arbre %s (%d) : %s" % [t["species"], t["seed"] % 10000, s])

func _rocks() -> void:
	_count("rochers.enfonces", w.rocks.size())
	for r in w.rocks:
		if not r.has("model"):
			continue
		var m: Dictionary = r["model"]
		var vol: VoxelVolume = m["volume"]
		var lo: Vector3 = m["origin"]
		var contact := false
		# chaque morceau doit toucher le sol (niveau 0) : un morceau plus haut flotterait
		var sx := vol.size.x
		var sz := vol.size.z
		for comp in VoxelShapes.components(vol):
			var low := 1 << 20
			for i in comp:
				low = mini(low, i / (sx * sz))
			if lo.y + float(low) * 0.1 > 0.15:
				_fail("rochers.enfonces", "error", "rocher %s : un morceau de %d cellules flotte" % [r["family"], comp.size()])
		# du matériau doit exister sous le niveau du sol local (enfoncement)
		var below := int((0.0 - lo.y) / 0.1) - 1
		for z in vol.size.z:
			for x in vol.size.x:
				if below >= 0 and vol.get_voxel(x, below, z) != 0:
					contact = true
					break
			if contact:
				break
		if not contact:
			_fail("rochers.enfonces", "error", "rocher %s (%d) non enfoncé dans le sol" % [r["family"], r["seed"] % 10000])

# ------------------------------------------------------------------ circulation

func _circulation() -> void:
	var s := w.settlement
	var f := w.field
	if s == null or s.plaza.is_empty():
		return
	_count("circulation.routes", w.paths.routes.size())
	for r in w.paths.routes:
		var cells: Array = r["cells"]
		for k in range(1, cells.size()):
			var a: Vector2i = cells[k - 1]
			var b: Vector2i = cells[k]
			if absi(f.top_at(a.x, a.y) - f.top_at(b.x, b.y)) > 1:
				_fail("circulation.routes", "error", "route interrompue en (%d, %d) : marche de %d cellules" % [a.x, a.y, absi(f.top_at(a.x, a.y) - f.top_at(b.x, b.y))])
				break
	# réseau de circulation : place, routes, escaliers, parcelles, port
	var allowed := PackedByteArray()
	allowed.resize(f.n * f.n)
	for i in f.n * f.n:
		var z := f.zone[i]
		if f.top[i] != TerrainField.NO_GROUND and (z == TerrainField.Zone.PLAZA or z == TerrainField.Zone.ROAD or z == TerrainField.Zone.STAIR or z == TerrainField.Zone.PLOT or z == TerrainField.Zone.PORT or z == TerrainField.Zone.GARDEN):
			allowed[i] = 1
	var blocked := WorldNav.blocked_mask(f, w.occ)
	var pc: Vector2i = _free_start(s.plaza["col"], int(float(s.plaza["radius"]) / V), allowed, blocked)
	var reach := WorldNav.flood(f, pc, allowed, blocked)
	_count("circulation.entrees", w.buildings.size())
	for b in w.buildings:
		var dc: Vector2i = b["door_col"]
		if not reach.has(dc.x + dc.y * f.n):
			_fail("circulation.entrees", "error", "l'entrée de %s (%s) n'est pas reliée à la place" % [b["type"], str(b["door"])])
	_count("circulation.sanctuaire")
	if not s.shrine.is_empty():
		var rect: Rect2i = s.shrine["rect"]
		var ok := false
		for cz in range(rect.position.y - 1, rect.end.y + 1):
			for cx in range(rect.position.x - 1, rect.end.x + 1):
				if reach.has(cx + cz * f.n):
					ok = true
		if not ok:
			_fail("circulation.sanctuaire", "error", "le sanctuaire n'est pas relié à la place")
	_count("circulation.port")
	if not s.port.is_empty():
		var rect: Rect2i = s.port["pad_rect"]
		var ok := false
		for cz in range(rect.position.y - 1, rect.end.y + 1):
			for cx in range(rect.position.x - 1, rect.end.x + 1):
				if reach.has(cx + cz * f.n):
					ok = true
		if not ok:
			_fail("circulation.port", "error", "le port n'est pas relié à la place")

## Première colonne de circulation libre (ni obstacle ni vide) en spirale autour du centre de la place.
func _free_start(c: Vector2i, radius: int, allowed: PackedByteArray, blocked: PackedByteArray) -> Vector2i:
	for r in range(0, radius + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var x := c.x + dx
				var z := c.y + dz
				if w.field.has_ground(x, z) and allowed[x + z * w.field.n] == 1 and blocked[x + z * w.field.n] == 0:
					return Vector2i(x, z)
	return c

# ------------------------------------------------------------------ port, ponton, bateau

func _port() -> void:
	if w.port.is_empty():
		return
	var f := w.field
	var port := w.port
	var pier: Dictionary = port["pier"]
	var frame := PortBuilder.frame_transform(port)
	_count("port.ponton")
	# 1) le ponton ne traverse pas le terrain (hors partie posée) et sa racine repose sur la plateforme
	var hard: AABB = pier["hard"]
	var vol: VoxelVolume = pier["volume"]
	var o: Vector3 = pier["origin"]
	var inside := 0
	var root_ground := 0
	var root_total := 0
	for iz in vol.size.z:
		for ix in vol.size.x:
			for iy in vol.size.y:
				if vol.get_voxel(ix, iy, iz) == 0:
					continue
				var p := frame * (o + (Vector3(ix, iy, iz) + Vector3(0.5, 0.5, 0.5)) * 0.1)
				var gy := f.ground_at_m(p.x, p.z)
				if not is_nan(gy) and p.y < gy - 0.02 and (o.z + float(iz) * 0.1) > 0.35:
					inside += 1
				break
	if inside > 0:
		_fail("port.ponton", "error", "le ponton pénètre le terrain (%d colonnes)" % inside)
	# racine : le dessus du tablier est à 20 cm au-dessus du sol de la plateforme
	for k in range(1, 8):
		var q := frame * Vector3(0.0, 0.0, -float(k) * 0.1)
		var gy := f.ground_at_m(q.x, q.z)
		if is_nan(gy):
			continue
		root_total += 1
		if absf((float(port["deck_top"]) - 0.2) - gy) < 0.15:
			root_ground += 1
	if root_total > 0 and root_ground < root_total / 2:
		_fail("port.ponton", "error", "la racine du ponton ne repose pas sur la plateforme")
	# 2) bateau : conception (voiles, mâts) et position
	if not w.ship.is_empty():
		_count("port.bateau")
		for iss in ShipGenerator.check(w.ship):
			_fail("port.bateau", "error", "bateau : %s" % iss)
		var xf: Transform3D = port["mooring"]["xform"]
		var sv: VoxelVolume = w.ship["volume"]
		var so: Vector3 = w.ship["origin"]
		var inv := xf.affine_inverse()
		var clashes := 0
		for iz in vol.size.z:
			for ix in vol.size.x:
				for iy in vol.size.y:
					if vol.get_voxel(ix, iy, iz) == 0:
						continue
					var p := frame * (o + (Vector3(ix, iy, iz) + Vector3(0.5, 0.5, 0.5)) * 0.1)
					var l := inv * p
					var c := Vector3i(floori((l.x - so.x) / 0.1), floori((l.y - so.y) / 0.1), floori((l.z - so.z) / 0.1))
					if sv.get_voxel(c.x, c.y, c.z) != 0:
						clashes += 1
		if clashes > 0:
			_fail("port.bateau", "error", "le bateau touche le ponton (%d cellules)" % clashes)
		# hors terrain : aucune colonne de sol dans l'emprise de la coque, au-dessus du fond
		var hull := AABB(Vector3(-float(w.ship["B"]) * 0.5, -float(w.ship["D"]), -float(w.ship["L"]) * 0.5), Vector3(float(w.ship["B"]), float(w.ship["D"]) + 1.2, float(w.ship["L"])))
		var hits := 0
		for ix in range(0, int(hull.size.x / 0.2) + 1):
			for iz in range(0, int(hull.size.z / 0.2) + 1):
				var p := xf * (hull.position + Vector3(float(ix) * 0.2, 0.0, float(iz) * 0.2))
				var gy := f.ground_at_m(p.x, p.z)
				if not is_nan(gy) and gy > xf.origin.y - float(w.ship["D"]) + 0.05:
					hits += 1
		if hits > 0:
			_fail("port.bateau", "error", "le bateau touche le terrain (%d colonnes)" % hits)

# ------------------------------------------------------------------ déterminisme

## Empreinte de l'île : terrain, bâtiments, objets, arbres, rochers, plantes, port, bateau.
static func signature(world: WorldData) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(world.field.top.to_byte_array())
	ctx.update(world.field.material)
	ctx.update(world.field.zone)
	for b in world.buildings:
		ctx.update(var_to_bytes([b["type"], (b["res"] as PlacementResult).pos, (b["res"] as PlacementResult).yaw]))
		if b.has("model"):
			ctx.update(b["model"].volume.data)
	for p in world.props:
		ctx.update(var_to_bytes([p["id"], p["xform"]]))
	for t in world.trees:
		ctx.update(var_to_bytes([t["species"], t["seed"], t["pos"]]))
		if t.has("model"):
			ctx.update(t["model"]["wood"].data)
	for r in world.rocks:
		ctx.update(var_to_bytes([r["family"], r["seed"], r["pos"]]))
		if r.has("model"):
			ctx.update(r["model"]["volume"].data)
	ctx.update(var_to_bytes([world.plants.size(), world.stats.get("plants", 0)]))
	if not world.ship.is_empty():
		ctx.update(world.ship["volume"].data)
	if not world.port.is_empty() and world.port.has("pier"):
		ctx.update(world.port["pier"]["volume"].data)
	return ctx.finish().hex_encode()
