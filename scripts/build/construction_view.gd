class_name ConstructionView
extends RefCounted
## Construction → nœuds Godot (Lot 8) : un maillage par (niveau, matière), des collisions réelles (une boîte par morceau de mur : les
## portes et fenêtres sont de vraies découpes), un toit à deux pans. Les niveaux autres que le niveau actif sont atténués.
## Matières : palette du jeu (mêmes couleurs que le monde).

const C := preload("res://scripts/build/construction.gd")
const FADE_ALPHA := 0.22

static var _mats: Dictionary = {}

static func color_of(mat: String) -> Color:
	var key := String(C.MATS[mat]["key"]) if C.MATS.has(mat) else "stone_rubble"
	var pal := VoxelPalette.get_default()
	return pal.colors_linear[pal.id(key)].linear_to_srgb()

# ------------------------------------------------------------------ géométrie

static func _tri(st: Dictionary, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	# Godot : face avant = sens horaire ; (b-a)×(c-a) doit donc s'opposer à la normale
	var cr := (b - a).cross(c - a)
	if cr.dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var v: PackedVector3Array = st["v"]
	var nn: PackedVector3Array = st["n"]
	v.append(a)
	v.append(b)
	v.append(c)
	nn.append(n)
	nn.append(n)
	nn.append(n)
	st["v"] = v
	st["n"] = nn

static func _quad(st: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)

static func _box(st: Dictionary, bx: AABB) -> void:
	var p := bx.position
	var q := bx.end
	_quad(st, Vector3(p.x, p.y, p.z), Vector3(q.x, p.y, p.z), Vector3(q.x, q.y, p.z), Vector3(p.x, q.y, p.z), Vector3(0, 0, -1))
	_quad(st, Vector3(p.x, p.y, q.z), Vector3(q.x, p.y, q.z), Vector3(q.x, q.y, q.z), Vector3(p.x, q.y, q.z), Vector3(0, 0, 1))
	_quad(st, Vector3(p.x, p.y, p.z), Vector3(p.x, p.y, q.z), Vector3(p.x, q.y, q.z), Vector3(p.x, q.y, p.z), Vector3(-1, 0, 0))
	_quad(st, Vector3(q.x, p.y, p.z), Vector3(q.x, p.y, q.z), Vector3(q.x, q.y, q.z), Vector3(q.x, q.y, p.z), Vector3(1, 0, 0))
	_quad(st, Vector3(p.x, q.y, p.z), Vector3(q.x, q.y, p.z), Vector3(q.x, q.y, q.z), Vector3(p.x, q.y, q.z), Vector3(0, 1, 0))
	_quad(st, Vector3(p.x, p.y, p.z), Vector3(q.x, p.y, p.z), Vector3(q.x, p.y, q.z), Vector3(p.x, p.y, q.z), Vector3(0, -1, 0))

static func _pt(shape: Dictionary, s: float, y: float, along: float) -> Vector3:
	return Vector3(along, y, s) if int(shape["ridge_axis"]) == 0 else Vector3(s, y, along)

## Pentagone convexe (portée, hauteur) extrudé le long du faîtage. y absolu.
static func roof_points(shape: Dictionary, y_abs: float) -> Array[Vector3]:
	var ra := int(shape["ridge_axis"])
	var s0 := float(shape["z0"]) if ra == 0 else float(shape["x0"])
	var s1 := float(shape["z1"]) if ra == 0 else float(shape["x1"])
	var a0 := float(shape["x0"]) if ra == 0 else float(shape["z0"])
	var a1 := float(shape["x1"]) if ra == 0 else float(shape["z1"])
	var sm := (s0 + s1) * 0.5
	var prof := [Vector2(s0, y_abs), Vector2(s1, y_abs), Vector2(s1, y_abs + C.ROOF_T), Vector2(sm, y_abs + C.ROOF_T + float(shape["rise"])), Vector2(s0, y_abs + C.ROOF_T)]
	var pts: Array[Vector3] = []
	for al in [a0, a1]:
		for p: Vector2 in prof:
			pts.append(_pt(shape, p.x, p.y, al))
	return pts

static func _roof(st: Dictionary, shape: Dictionary, y_abs: float) -> void:
	var ra := int(shape["ridge_axis"])
	var s0 := float(shape["z0"]) if ra == 0 else float(shape["x0"])
	var s1 := float(shape["z1"]) if ra == 0 else float(shape["x1"])
	var a0 := float(shape["x0"]) if ra == 0 else float(shape["z0"])
	var a1 := float(shape["x1"]) if ra == 0 else float(shape["z1"])
	var sm := (s0 + s1) * 0.5
	var prof := [Vector2(s0, y_abs), Vector2(s1, y_abs), Vector2(s1, y_abs + C.ROOF_T), Vector2(sm, y_abs + C.ROOF_T + float(shape["rise"])), Vector2(s0, y_abs + C.ROOF_T)]
	var cen := Vector3.ZERO
	for p: Vector2 in prof:
		cen += _pt(shape, p.x, p.y, (a0 + a1) * 0.5)
	cen /= float(prof.size())
	for i in prof.size():
		var p: Vector2 = prof[i]
		var q: Vector2 = prof[(i + 1) % prof.size()]
		var m := (_pt(shape, p.x, p.y, a0) + _pt(shape, q.x, q.y, a0)) * 0.5
		var e1 := _pt(shape, q.x, q.y, a0) - _pt(shape, p.x, p.y, a0)
		var e2 := Vector3(1, 0, 0) if ra == 0 else Vector3(0, 0, 1)
		var n := e1.cross(e2).normalized()
		if n.dot(m - cen) < 0.0:
			n = -n
		_quad(st, _pt(shape, p.x, p.y, a0), _pt(shape, q.x, q.y, a0), _pt(shape, q.x, q.y, a1), _pt(shape, p.x, p.y, a1), n)
	var endn := Vector3(-1, 0, 0) if ra == 0 else Vector3(0, 0, -1)
	for k in [0, 1]:
		var al := a0 if k == 0 else a1
		var nn := endn if k == 0 else -endn
		for i in range(1, prof.size() - 1):
			_tri(st, _pt(shape, (prof[0] as Vector2).x, (prof[0] as Vector2).y, al), _pt(shape, (prof[i] as Vector2).x, (prof[i] as Vector2).y, al), _pt(shape, (prof[i + 1] as Vector2).x, (prof[i + 1] as Vector2).y, al), nn)

static func _new_st() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array()}

static func _to_mesh(st: Dictionary) -> ArrayMesh:
	var v: PackedVector3Array = st["v"]
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = st["n"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

# ------------------------------------------------------------------ construction du nœud

static func _material(mat: String, ghost: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ghost.a > 0.0:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = ghost
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 3
		return m
	m.albedo_color = color_of(mat)
	m.roughness = 0.95
	m.metallic = 0.0
	return m

## opts : ghost (Color, alpha > 0 = aperçu translucide), collide (bool, défaut vrai hors aperçu), level (niveau actif, -1 = tous pleins).
static func create(c: Construction, opts := {}) -> Node3D:
	var ghost: Color = opts.get("ghost", Color(0, 0, 0, 0))
	var collide: bool = bool(opts.get("collide", ghost.a <= 0.0))
	var root := Node3D.new()
	root.name = "Construction"
	var groups := {}        # "lv|mat" → st
	var body: StaticBody3D = null
	if collide:
		body = StaticBody3D.new()
		body.name = "Collisions"
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
	var add_shape := func(bx: AABB) -> void:
		if body == null:
			return
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = bx.size
		cs.shape = sh
		cs.position = bx.get_center()
		body.add_child(cs)
	for e in c.elements:
		var lv := int(e["lv"])
		var key := "%d|%s" % [lv, String(e["mat"])]
		if not groups.has(key):
			groups[key] = _new_st()
		var st: Dictionary = groups[key]
		var y0 := c.level_y(lv)
		match String(e["t"]):
			"floor", "foundation":
				var bx := c.slab_box(e)
				bx.position.y += y0
				_box(st, bx)
				add_shape.call(bx)
			"wall":
				for bx in c.wall_boxes(e):
					var b2 := bx
					b2.position.y += y0
					_box(st, b2)
					add_shape.call(b2)
			"roof":
				var shape := c.roof_shape(e)
				var yb := y0 + float(shape["y"])
				_roof(st, shape, yb)
				if body != null:
					var cs := CollisionShape3D.new()
					var sh := ConvexPolygonShape3D.new()
					sh.points = PackedVector3Array(roof_points(shape, yb))
					cs.shape = sh
					body.add_child(cs)
	var level_nodes := {}
	for key in groups:
		var parts := String(key).split("|")
		var lv := int(parts[0])
		var mesh := _to_mesh(groups[key])
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "N%d_%s" % [lv, parts[1]]
		mi.mesh = mesh
		var mat := _material(parts[1], ghost)
		mi.material_override = mat
		mi.set_meta("level", lv)
		if ghost.a > 0.0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		if not level_nodes.has(lv):
			level_nodes[lv] = []
		(level_nodes[lv] as Array).append(mat)
	root.set_meta("level_mats", level_nodes)
	root.set_meta("base_colors", {})
	set_active_level(root, int(opts.get("level", -1)))
	return root

## Niveau actif plein ; les autres atténués (translucides). -1 : tout plein.
static func set_active_level(root: Node3D, lv: int) -> void:
	var lm: Dictionary = root.get_meta("level_mats", {})
	for k in lm:
		for m: StandardMaterial3D in lm[k]:
			if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			var faded: bool = lv >= 0 and int(k) != lv
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
			var col := m.albedo_color
			col.a = FADE_ALPHA if faded else 1.0
			m.albedo_color = col
	root.set_meta("active_level", lv)
