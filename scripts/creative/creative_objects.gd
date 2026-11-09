class_name CreativeObjects
extends RefCounted
## Objets posés de l'Éditeur créatif : les données (plan.objects) deviennent des nœuds 3D (asset précuit, pivot au centre de l'emprise,
## posé sur le sol réel) ; sélection par rayon (boîte orientée). Aucune logique d'édition ici (voir MapDoc et CreativeEditor).

static func footprint(ref: String) -> Vector3:
	var info := AssetLibrary.info(ref)
	var sz: Array = info.get("size_m", [1.0, 1.0, 1.0])
	return Vector3(float(sz[0]), float(sz[1]), float(sz[2]))

static func ground_offset(ref: String) -> float:
	return float(AssetLibrary.info(ref).get("ground_y", 0.0))

## Rayon d'encombrement au sol (m), échelle comprise.
static func radius(o: Dictionary) -> float:
	var s := footprint(String(o["ref"]))
	return maxf(s.x, s.z) * 0.5 * float(o.get("scale", 1.0))

## Rayon libre au sol (m) : le tronc d'un arbre, pas sa couronne (les couronnes peuvent se toucher) ; le socle d'un rocher ; l'emprise des autres objets.
static func clear_radius(ref: String) -> float:
	var s := footprint(ref)
	var half := maxf(s.x, s.z) * 0.5
	if ref.begins_with("tree_"):
		return clampf(half * 0.32, 0.5, 1.2)
	if ref.begins_with("boulder_"):
		return half * 0.8
	return half

## Hauteur du sol sous l'objet : moyenne du centre et de quatre points de son emprise (un étal sur pente ne flotte ni ne s'enfonce trop).
static func ground_under(field: TerrainField, o: Dictionary) -> float:
	var p: Vector2 = o["pos"]
	var r := minf(radius(o) * 0.6, 3.0)
	var sum := 0.0
	var cnt := 0
	for q in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var g := field.ground_at_m(p.x + q.x, p.y + q.y)
		if not is_nan(g):
			sum += g
			cnt += 1
	if cnt == 0:
		return 0.0
	return sum / float(cnt)

static func transform_for(o: Dictionary, field: TerrainField) -> Transform3D:
	var p: Vector2 = o["pos"]
	var y := ground_under(field, o) + float(o.get("lift", 0.0)) - ground_offset(String(o["ref"])) * float(o.get("scale", 1.0))
	var b := Basis(Vector3.UP, deg_to_rad(float(o.get("yaw", 0.0)))) * Basis.from_scale(Vector3.ONE * float(o.get("scale", 1.0)))
	return Transform3D(b, Vector3(p.x, y, p.y))

## Nœud 3D de l'objet (racine = pivot au centre de l'emprise, au sol). `collide` : garde les collisions de l'asset (mode jeu).
static func make_node(o: Dictionary, field: TerrainField, collide := true) -> Node3D:
	var root := Node3D.new()
	root.name = "O_%s" % o["id"]
	root.set_meta("oid", String(o["id"]))
	var ref := String(o["ref"])
	var inst := AssetLibrary.instantiate(ref) if ResourceLoader.exists(AssetLibrary.scene_path(ref)) else null
	var fp := footprint(ref)
	if inst == null:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1, 1)
		mi.mesh = bm
		mi.position = Vector3(0, 0.5, 0)
		root.add_child(mi)
	else:
		inst.position = Vector3(-fp.x * 0.5, 0.0, -fp.z * 0.5)
		if not collide:
			AuthoredIslandView.strip_asset_collisions(inst)
		root.add_child(inst)
	if field != null:
		root.transform = transform_for(o, field)
	return root

## Boîte locale (repère du pivot) de l'objet, échelle non comprise.
static func local_box(ref: String) -> AABB:
	var fp := footprint(ref)
	var g := ground_offset(ref)
	return AABB(Vector3(-fp.x * 0.5, -g, -fp.z * 0.5), Vector3(fp.x, maxf(fp.y, 0.3), fp.z))

## Distance le long du rayon jusqu'à l'objet (boîte orientée) ; -1 si manqué.
static func ray_hit(o: Dictionary, field: TerrainField, origin: Vector3, dir: Vector3) -> float:
	var xf := transform_for(o, field)
	var inv := xf.affine_inverse()
	var lo := inv * origin
	var ld := (inv.basis * dir)
	var box := local_box(String(o["ref"]))
	var t0 := -1.0e9
	var t1 := 1.0e9
	for a in 3:
		var mn := box.position[a]
		var mx := box.end[a]
		if absf(ld[a]) < 1.0e-8:
			if lo[a] < mn or lo[a] > mx:
				return -1.0
		else:
			var ta := (mn - lo[a]) / ld[a]
			var tb := (mx - lo[a]) / ld[a]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
	if t1 < maxf(t0, 0.0):
		return -1.0
	return maxf(t0, 0.0) / maxf(dir.length(), 1.0e-6)
