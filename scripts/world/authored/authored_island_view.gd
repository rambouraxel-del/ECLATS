@tool
class_name AuthoredIslandView
extends RefCounted
## Île dessinée (Lot 5) → nœuds Godot. Réutilise la mise en scène du Lot 4 (bâtiments, arbres, rochers, plantes,
## objets cuits, quai et navire) et ajoute : terrain par tuiles, sous-face grossière, COLLISIONS (sol en carte de
## hauteurs, boîtes des bâtiments, meubles, troncs, rochers, objets, quai).
##
## Couches physiques : 1 = décor (sol, bâtiments, objets), 2 = joueur.

const C := VoxelGrid.STRUCTURE_SIZE
const V := VoxelGrid.VOXEL_SIZE
const LAYER_WORLD := 1

static func create(world: WorldData, parent: Node3D) -> Dictionary:
	var refs := {}
	var root := Node3D.new()
	root.name = "World"
	parent.add_child(root)
	refs["root"] = root
	# terrain fin (tuiles) et sous-face
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	for t in world.authored.get("terrain_meshes", []):
		var mesh := VoxelMesher.arrays_to_mesh(t["arrays"], VoxelMesher.Style.STYLIZED)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = t.get("name", "T")
		mi.mesh = mesh
		mi.position = t["origin"]
		terrain.add_child(mi)
	var under := Node3D.new()
	under.name = "Underside"
	root.add_child(under)
	for t in world.authored.get("underside_meshes", []):
		var mesh := VoxelMesher.arrays_to_mesh(t["arrays"], VoxelMesher.Style.STYLIZED)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = t["origin"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		under.add_child(mi)
	# bâtiments
	var bnode := Node3D.new()
	bnode.name = "Buildings"
	root.add_child(bnode)
	for b in world.buildings:
		var n := BuildingView.create_node(b["model"], b["arrays"], [30.0, 80.0])
		n.transform = b["xform"]
		n.name = String(b.get("id", b["type"]))
		bnode.add_child(n)
	# quai et navire
	if not world.port.is_empty():
		root.add_child(WorldView._pier_node(world))
		if not world.ship.is_empty():
			var sn := ShipView.create_node(world.ship)
			sn.transform = world.port["mooring"]["xform"]
			root.add_child(sn)
			var ropes := Node3D.new()
			ropes.name = "Mooring"
			root.add_child(ropes)
			for r in world.port["mooring"]["ropes"]:
				var k := ShipGenerator.rope_kit(r["a"], r["b"], r["sag"])
				var a2 := VoxelMesher.build_arrays(k["volume"], float(k["grid"]), Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
				var rm := WorldView._mesh(a2)
				if rm != null:
					rm.position = k["origin"]
					rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					ropes.add_child(rm)
	# arbres, rochers, plantes
	var nat := Node3D.new()
	nat.name = "Nature"
	root.add_child(nat)
	for t in world.trees:
		var n := VoxelObjectView.create_node("%s_%d" % [t["species"], t["seed"] % 10000], t["parts"], t["arrays"], [40.0, 110.0])
		n.transform = Transform3D(Basis(Vector3.UP, t["rot"]).scaled(Vector3.ONE * float(t.get("scale", 1.0))), (t["pos"] as Vector3) + WorldView.DEZFIGHT)
		nat.add_child(n)
	for r in world.rocks:
		var n := VoxelObjectView.create_node("%s_%d" % [r["family"], r["seed"] % 10000], r["parts"], r["arrays"], [45.0, 130.0], true)
		n.transform = (r["xform"] as Transform3D).translated(WorldView.DEZFIGHT)
		nat.add_child(n)
	WorldView._plants_nodes(world, nat)
	# objets cuits
	var scatter := PropScatter.new()
	scatter.name = "Props"
	scatter.cell_size = 16.0
	scatter.max_distance = 260.0
	scatter.build_collisions = false          # collisions des objets : create_collisions (gradins de l'Ancre)
	root.add_child(scatter)
	for p in world.props:
		scatter.add_asset(p["id"], p["xform"])
	scatter.commit()
	strip_asset_collisions(root)      # Lot 10 : la racine contient « Props » (sur scatter, la recherche ne trouvait rien : la plateforme de l'Ancre gardait un bloc de 90 cm à la première construction)
	refs["scatter"] = scatter
	refs["physics"] = create_collisions(world, root)
	return refs

# ------------------------------------------------------------------ collisions

## Les assets instanciés (non regroupables) apportent leurs propres collisions : on les retire, create_collisions
## pose celles de tous les objets (avec les gradins de l'Ancre). À rappeler après un rechargement du cache : les
## sous-scènes instanciées y retrouvent leurs nœuds d'origine.
static func strip_asset_collisions(root: Node) -> void:
	var scatter := root.find_child("Props", true, false)
	if scatter == null:
		return
	for body in scatter.find_children("*", "StaticBody3D", true, false):
		body.get_parent().remove_child(body)
		body.free()

static func _box(body: StaticBody3D, box: AABB, xf := Transform3D.IDENTITY) -> void:
	if box.size.x <= 0.001 or box.size.y <= 0.001 or box.size.z <= 0.001:
		return
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = box.size
	cs.shape = sh
	cs.transform = xf * Transform3D(Basis.IDENTITY, box.get_center())
	body.add_child(cs)

## Collisions d'un bâtiment : murs, planchers, marches (colliders du modèle, rampe dans l'escalier) et meubles.
static func add_building(builds: StaticBody3D, b: Dictionary) -> void:
	var model: BuildingModel = b["model"]
	var xf: Transform3D = b["xform"]
	var plan: BuildingPlan = b["plan"]
	var st: BuildingPlan.StairPlan = plan.stair
	var f0 := float(plan.floor_y(0)) * C
	var f1 := float(plan.floor_y(1)) * C if plan.floors > 1 else 0.0
	for a: AABB in model.colliders:
		# marches de l'escalier (sauf le palier) remplacées par une rampe : montée fluide, mêmes hauteurs
		if st != null and absf(a.position.x - float(st.x0) * C) < 0.01 and absf(a.size.x - float(st.w) * C) < 0.01 \
				and absf(a.position.y - f0) < 0.01 and a.end.y < f1 - 0.05:
			continue
		_box(builds, a, xf)
	if st != null and plan.floors > 1:
		var cx := (float(st.x0) + float(st.w) * 0.5) * C
		var foot := Vector3(cx, f0, float(st.z0 + st.l) * C)
		var top := Vector3(cx, f1, float(st.z0 + 3) * C)
		var u := (top - foot).normalized()
		var nrm := Vector3(1, 0, 0).cross(u)
		if nrm.y < 0.0:
			nrm = -nrm
		var thick := 0.12
		var cs_r := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(st.w) * C, thick, foot.distance_to(top))
		cs_r.shape = bs
		cs_r.transform = xf * Transform3D(Basis(Vector3(1, 0, 0), nrm, u), (foot + top) * 0.5 - nrm * thick * 0.5)
		builds.add_child(cs_r)
	for f in model.furniture:
		var r: Rect2 = f["rect"]
		var h: float = float(f.get("height", 0.8))
		if h < 0.25:
			continue            # tapis, petits objets : on marche dessus
		var fy := model.floor_y_m(int(f.get("floor", 0)))
		_box(builds, AABB(Vector3(r.position.x, fy, r.position.y), Vector3(r.size.x, minf(h, 2.0), r.size.y)), xf)

static func add_tree(deco: StaticBody3D, t: Dictionary) -> void:
	var pl: Dictionary = t["plan"]
	var k := float(t.get("scale", 1.0))
	var r: float = float(pl.get("trunk_r", 0.3)) * k
	var cs2 := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(r * 0.9, 0.15)
	cyl.height = 2.6
	cs2.shape = cyl
	cs2.position = (t["pos"] as Vector3) + Vector3(0, 1.0, 0)
	deco.add_child(cs2)

static func add_rock(deco: StaticBody3D, r: Dictionary, occ: OccupancyMap) -> void:
	var item: Dictionary = occ.items[int(r["item"])] if int(r.get("item", -1)) >= 0 else {}
	for a: AABB in item.get("hard", []):
		# boîte un peu rentrée : les rochers sont arrondis
		var g := a.grow(-0.12)
		g.position.y = a.position.y - 0.5
		g.size.y = a.size.y + 0.5
		_box(deco, g)

static func create_collisions(world: WorldData, parent: Node3D) -> Node3D:
	var phys := Node3D.new()
	phys.name = "Physics"
	parent.add_child(phys)
	# sol : carte de hauteurs aux centres des colonnes (les marches de 20 cm deviennent des rampes franchissables,
	# les falaises des murs) ; le vide plonge très bas (on tombe).
	var field := world.field
	var n := field.n
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = LAYER_WORLD
	ground.collision_mask = 0
	phys.add_child(ground)
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	for i in n * n:
		var t := field.top[i]
		data[i] = (-400.0 if t == TerrainField.NO_GROUND else float(t + 1) * V) / V
	hm.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(V, V, V)
	cs.position = Vector3((float(field.origin.x) + 0.5 + float(n - 1) * 0.5) * V, 0.0, (float(field.origin.y) + 0.5 + float(n - 1) * 0.5) * V)
	ground.add_child(cs)
	# bâtiments : murs, planchers, marches (colliders du modèle) + meubles
	var builds := StaticBody3D.new()
	builds.name = "Buildings"
	builds.collision_layer = LAYER_WORLD
	builds.collision_mask = 0
	phys.add_child(builds)
	for b in world.buildings:
		add_building(builds, b)
	# troncs, rochers, objets
	var deco := StaticBody3D.new()
	deco.name = "Decor"
	deco.collision_layer = LAYER_WORLD
	deco.collision_mask = 0
	phys.add_child(deco)
	for t in world.trees:
		add_tree(deco, t)
	for r in world.rocks:
		add_rock(deco, r, world.occ)
	for p in world.props:
		var info := AssetLibrary.info(String(p["id"]))
		var xf: Transform3D = p["xform"]
		var cols: Array = info.get("colliders", [])
		if String(p["id"]) == "teleport_anchor":
			# plateforme de l'Ancre : trois gradins (marches de 30 cm) au lieu d'un bloc de 90 cm
			var sz: Array = info.get("size_m", [5.2, 1.2, 5.2])
			for k in 3:
				var inset := 0.45 * float(k)
				_box(deco, AABB(Vector3(inset, 0.0, inset), Vector3(float(sz[0]) - inset * 2.0, 0.3 * float(k + 1), float(sz[2]) - inset * 2.0)), xf)
			continue
		for c in cols:
			var pos: Array = c["position"]
			var size: Array = c["size"]
			_box(deco, AABB(Vector3(float(pos[0]), float(pos[1]), float(pos[2])), Vector3(float(size[0]), float(size[1]), float(size[2]))), xf)
	# quai (tablier)
	if not world.port.is_empty() and world.port.has("pier"):
		var frame := PortBuilder.frame_transform(world.port)
		for a: AABB in world.port["pier"]["colliders"]:
			_box(deco, a, frame)
	return phys
