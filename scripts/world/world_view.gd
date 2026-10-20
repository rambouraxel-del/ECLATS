@tool
class_name WorldView
extends RefCounted
## WorldData → arbre de nœuds Godot. Aucune génération ici : uniquement de la mise en scène.
## Un MeshInstance3D par bâtiment / arbre / rocher (jamais par voxel), MultiMesh pour les plantes,
## PropScatter pour les assets cuits.

const C := VoxelGrid.STRUCTURE_SIZE

## Construit les nœuds sous `parent`. Renvoie les références utiles.
static func create(world: WorldData, parent: Node3D) -> Dictionary:
	var refs := {}
	var island := VoxelIsland.new()
	island.name = "Island"
	island.seed = world.seed
	island.chunk_size = 64
	island.external_data = true
	parent.add_child(island)
	island.adopt(world.island)
	refs["island"] = island
	var root := Node3D.new()
	root.name = "World"
	parent.add_child(root)
	refs["root"] = root
	# bâtiments
	var bnode := Node3D.new()
	bnode.name = "Buildings"
	root.add_child(bnode)
	for b in world.buildings:
		var n := BuildingView.create_node(b["model"], b["arrays"])
		n.transform = b["xform"]
		n.name = "%s_%d" % [b["type"], b["plan"].seed % 10000]
		bnode.add_child(n)
	# appontement
	if not world.port.is_empty():
		root.add_child(_pier_node(world))
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
				var rm := _mesh(a2)
				if rm != null:
					rm.position = k["origin"]
					rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					ropes.add_child(rm)
	# arbres, rochers, plantes
	var nat := Node3D.new()
	nat.name = "Nature"
	root.add_child(nat)
	for t in world.trees:
		var n := VoxelObjectView.create_node("%s_%d" % [t["species"], t["seed"] % 10000], t["parts"], t["arrays"], [34.0, 95.0])
		n.transform = Transform3D(Basis(Vector3.UP, t["rot"]), t["pos"])
		nat.add_child(n)
	for r in world.rocks:
		var n := VoxelObjectView.create_node("%s_%d" % [r["family"], r["seed"] % 10000], r["parts"], r["arrays"], [40.0, 110.0], true)
		n.transform = r["xform"]
		nat.add_child(n)
	_plants_nodes(world, nat)
	# assets cuits (décor)
	var scatter := PropScatter.new()
	scatter.name = "Props"
	scatter.cell_size = 14.0
	scatter.max_distance = 220.0
	root.add_child(scatter)
	for p in world.props:
		scatter.add_asset(p["id"], p["xform"])
	scatter.commit()
	refs["scatter"] = scatter
	return refs

static func _pier_node(world: WorldData) -> Node3D:
	var port: Dictionary = world.port
	var pier: Dictionary = port["pier"]
	var n := Node3D.new()
	n.name = "Pier"
	n.transform = PortBuilder.frame_transform(port)
	var arrays := VoxelMesher.build_arrays(pier["volume"], C, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	var mi := _mesh(arrays)
	if mi != null:
		mi.name = "Deck"
		mi.position = pier["origin"]
		n.add_child(mi)
	for r in pier["ropes"]:
		var kit := PortBuilder.rope_kit(r["a"], r["b"])
		var a2 := VoxelMesher.build_arrays(kit["volume"], float(kit["grid"]), Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
		var rm := _mesh(a2)
		if rm != null:
			rm.name = "Stay"
			rm.position = kit["offset"]
			rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(rm)
	for l in pier["lights"]:
		var light := OmniLight3D.new()
		light.position = l["pos"]
		light.light_color = l["color"]
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.add_to_group("asset_lamps")
		light.set_meta("interior", l["interior"])
		n.add_child(light)
	return n

static func _mesh(arrays: Array) -> MeshInstance3D:
	var mesh := VoxelMesher.arrays_to_mesh(arrays, VoxelMesher.Style.DETAIL)
	if mesh == null:
		return null
	mesh.surface_set_material(0, VoxelMaterials.props_material())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi

## Plantes : un MultiMesh par espèce, par cellule de 10 m et par niveau de détail (2 cm près, 4 cm loin).
static func _plants_nodes(world: WorldData, parent: Node3D) -> void:
	var plants := Node3D.new()
	plants.name = "Plants"
	parent.add_child(plants)
	var meshes := {}
	for entry in world.plants:
		var kind: String = entry["kind"]
		if not meshes.has(kind):
			var vol := VegetationLibrary.build_plant(kind)
			meshes[kind] = [
				VoxelMesher.build(vol, VoxelGrid.DETAIL_SIZE, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL),
				VoxelMesher.build(vol.downsample(2, 0.25), VoxelGrid.DETAIL_SIZE * 2.0, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL),
			]
		var xs: Array = entry["xforms"]
		for li in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[kind][li]
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d_P%d" % [kind, entry["cell"].x, entry["cell"].y, li]
			mmi.multimesh = mm
			mmi.visibility_range_begin = 0.0 if li == 0 else 16.0
			mmi.visibility_range_end = 16.0 if li == 0 else 48.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plants.add_child(mmi)
