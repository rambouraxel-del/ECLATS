@tool
class_name PropScatter
extends Node3D
## Pose de nombreux assets de façon économique :
##  - les assets sans lumière ni animation sont regroupés par CELLULE d'espace (16 m) et par
##    niveau de détail dans des MultiMeshInstance3D : un seul appel de dessin pour toutes les
##    instances d'un même modèle dans une cellule ;
##  - chaque niveau de détail a sa plage de visibilité (HLOD) : au loin, des maillages
##    simplifiés ; hors de portée, rien n'est dessiné ;
##  - les assets avec lumière ou animation sont instanciés comme scènes complètes ;
##  - les collisions simplifiées (boîtes) sont regroupées dans un StaticBody3D par cellule.
## Usage : add_asset("well", transform) autant de fois que nécessaire, puis commit().

@export var cell_size := 16.0
@export var build_collisions := true
## Distance au-delà de laquelle les assets disparaissent (0 = jamais), appliquée aux assets
## qui ne définissent pas leur propre portée.
@export var max_distance := 0.0

var _pending: Array = []       # [id, Transform3D]
var stats := {"instances": 0, "multimeshes": 0, "scenes": 0, "colliders": 0, "triangles_lod0": 0}

func add_asset(id: String, xf: Transform3D) -> void:
	_pending.append([id, xf])

func clear_all() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_pending.clear()
	stats = {"instances": 0, "multimeshes": 0, "scenes": 0, "colliders": 0, "triangles_lod0": 0}

func commit() -> void:
	var groups := {}   # asset id → cellule → [Transform3D]
	for entry in _pending:
		var id: String = entry[0]
		var xf: Transform3D = entry[1]
		var info := AssetLibrary.info(id)
		if info.is_empty():
			push_warning("PropScatter : asset non généré (%s)" % id)
			continue
		stats["instances"] += 1
		stats["triangles_lod0"] += int(info.get("triangles", 0))
		if not info.get("instanceable", false):
			var inst := AssetLibrary.instantiate(id)
			inst.transform = xf
			add_child(inst)
			stats["scenes"] += 1
			continue
		var cell := Vector2i(floori(xf.origin.x / cell_size), floori(xf.origin.z / cell_size))
		if not groups.has(id):
			groups[id] = {}
		if not groups[id].has(cell):
			groups[id][cell] = []
		groups[id][cell].append(xf)
	var bodies := {}
	for id in groups:
		var info := AssetLibrary.info(id)
		var ranges: Array = info.get("lod_ranges", [14.0, 40.0, 0.0])
		for cell in groups[id]:
			var xforms: Array = groups[id][cell]
			for part in info["parts"]:
				var meshes: Array = part["meshes"]
				var off := Vector3(part["offset"][0], part["offset"][1], part["offset"][2])
				for li in meshes.size():
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = load(meshes[li])
					mm.instance_count = xforms.size()
					for i in xforms.size():
						mm.set_instance_transform(i, xforms[i] * Transform3D(Basis.IDENTITY, off))
					var mmi := MultiMeshInstance3D.new()
					mmi.name = "%s_%d_%d_L%d" % [id, cell.x, cell.y, li]
					mmi.multimesh = mm
					if meshes.size() > 1:
						mmi.visibility_range_begin = 0.0 if li == 0 else float(ranges[li - 1])
						var end_r := float(ranges[li]) if li < meshes.size() - 1 else float(ranges[meshes.size() - 1])
						if li == meshes.size() - 1 and end_r <= 0.0:
							end_r = max_distance
						mmi.visibility_range_end = end_r
					if li >= 2:
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mmi)
					stats["multimeshes"] += 1
			if build_collisions:
				_add_colliders(bodies, cell, info, xforms)
	if build_collisions:
		# Les assets en scène portent déjà leurs propres collisions.
		pass
	_pending.clear()

func _add_colliders(bodies: Dictionary, cell: Vector2i, info: Dictionary, xforms: Array) -> void:
	if info["colliders"].is_empty():
		return
	var body: StaticBody3D = bodies.get(cell)
	if body == null:
		body = StaticBody3D.new()
		body.name = "Collision_%d_%d" % [cell.x, cell.y]
		add_child(body)
		bodies[cell] = body
	for xf in xforms:
		for c in info["colliders"]:
			var size := Vector3(c["size"][0], c["size"][1], c["size"][2])
			var center := Vector3(c["position"][0], c["position"][1], c["position"][2]) + size * 0.5
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = size
			shape.shape = bs
			shape.transform = xf * Transform3D(Basis.IDENTITY, center)
			body.add_child(shape)
			stats["colliders"] += 1
