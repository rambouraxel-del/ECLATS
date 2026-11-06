class_name LabSelection
extends Node3D
## Trois sélections du laboratoire, avec aperçu visible dans le monde :
##   POINT      point visé au réticule (anneau + piquet)                    → arbre, rocher
##   RECTANGLE  deux coins (clics), dimensions affichées en mètres           → maison
##   PINCEAU    zone peinte (clic maintenu), rayon réglable                  → aplanir
## Les clics n'agissent que souris capturée (le clic qui recapture la souris ne sélectionne pas).

enum Tool { POINT, RECT, BRUSH }
signal selection_changed

const V := VoxelGrid.VOXEL_SIZE
const SNAP := 0.1

var tool := Tool.POINT
var camera: Camera3D
var lab: LabWorld
var aim := Vector3.INF
var point := Vector2.INF
var rect_a := Vector2.INF
var rect_b := Vector2.INF
var rect_state := 0                        # 0 aucun · 1 premier coin posé · 2 rectangle défini
var lock_size := false                     # impose l'emprise de 3,50 × 3,50 m
var lock_dims := Vector2(3.5, 3.5)
var brush_cells := {}                      # index de colonne → true
var brush_radius := 1.2
var brush_stroke: Array = []               # centres des coups de pinceau (m), pour la recette
var enabled := true

var _mat: StandardMaterial3D
var _point_mi: MeshInstance3D
var _rect_mi: MeshInstance3D
var _brush_mi: MeshInstance3D
var _hover_mi: MeshInstance3D
var _label: Label3D
var _was_captured := false
var _lmb_down := false
var _last_paint := Vector2.INF
var _flat_colors := {}                     # index → Color (aperçu d'aplanissement)

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.render_priority = 2
	for n in ["_point_mi", "_rect_mi", "_brush_mi", "_hover_mi"]:
		var mi := MeshInstance3D.new()
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		set(n, mi)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 56
	_label.pixel_size = 0.0035
	_label.outline_size = 14
	_label.modulate = Color(1, 1, 1)
	_label.outline_modulate = Color(0.05, 0.1, 0.15, 0.95)
	_label.visible = false
	_label.render_priority = 5
	add_child(_label)

func set_tool(t: int) -> void:
	tool = t as Tool
	selection_changed.emit()

func tool_name() -> String:
	return ["Point", "Rectangle", "Pinceau"][tool]

func snap(p: Vector2) -> Vector2:
	return Vector2(roundf(p.x / SNAP), roundf(p.y / SNAP)) * SNAP

# ------------------------------------------------------------------ état de la sélection

func has_point() -> bool:
	return point.x < 1.0e8

func has_rect() -> bool:
	return rect_state == 2

func rect_m() -> Rect2:
	var lo := Vector2(minf(rect_a.x, rect_b.x), minf(rect_a.y, rect_b.y))
	var hi := Vector2(maxf(rect_a.x, rect_b.x), maxf(rect_a.y, rect_b.y))
	return Rect2(lo, hi - lo)

func aim_xz() -> Vector2:
	return Vector2(aim.x, aim.z) if aim.x < 1.0e8 else Vector2.INF

func point_or_aim() -> Vector2:
	return point if has_point() else snap(aim_xz())

func set_point(p: Vector2) -> void:
	point = snap(p)
	_draw_point()
	selection_changed.emit()

func set_rect(a: Vector2, b: Vector2) -> void:
	rect_a = snap(a)
	rect_b = snap(b)
	rect_state = 2
	_draw_rect()
	selection_changed.emit()

## Rectangle de dimensions données, centré sur un point (commande /rect).
func set_rect_centered(center: Vector2, dims: Vector2) -> void:
	var lo := snap(center - dims * 0.5)        # coin ramené à 10 cm, dimensions exactes (3,50 reste 3,50)
	set_rect(lo, lo + dims)

func clear_rect() -> void:
	rect_state = 0
	rect_a = Vector2.INF
	rect_b = Vector2.INF
	_rect_mi.mesh = null
	_label.visible = false
	selection_changed.emit()

func clear_point() -> void:
	point = Vector2.INF
	_point_mi.mesh = null
	selection_changed.emit()

func clear_brush() -> void:
	brush_cells.clear()
	brush_stroke.clear()
	_flat_colors.clear()
	_last_paint = Vector2.INF
	_brush_mi.mesh = null
	selection_changed.emit()

func clear_all() -> void:
	clear_point()
	clear_rect()
	clear_brush()

func info_text() -> String:
	match tool:
		Tool.POINT:
			return "Point : %.1f ; %.1f m" % [point.x, point.y] if has_point() else "Point : visez le sol et cliquez"
		Tool.RECT:
			if rect_state == 2:
				var r := rect_m()
				return "Rectangle %s × %s m" % [_fm(r.size.x), _fm(r.size.y)]
			return "Rectangle : cliquez le premier coin" if rect_state == 0 else "Rectangle : cliquez le second coin"
	return "Pinceau : %d colonnes (%.1f m²), rayon %.1f m" % [brush_cells.size(), float(brush_cells.size()) * V * V, brush_radius] if not brush_cells.is_empty() \
		else "Pinceau : maintenez le clic pour peindre (rayon %.1f m)" % brush_radius

static func _fm(v: float) -> String:
	return ("%.2f" % v).replace(".", ",")

# ------------------------------------------------------------------ pinceau

func paint_at(c: Vector2, radius := -1.0, erase := false) -> void:
	var r := radius if radius > 0.0 else brush_radius
	var f := lab.field
	var lo := f.col_of_m(c.x - r, c.y - r)
	var hi := f.col_of_m(c.x + r, c.y + r)
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if not f.has_ground(cx, cz):
				continue
			if f.center_m(cx, cz).distance_to(c) > r:
				continue
			var i := f.idx(cx, cz)
			if erase:
				brush_cells.erase(i)
			else:
				brush_cells[i] = true
	_flat_colors.clear()
	_draw_brush()
	selection_changed.emit()

## Trace complète (recette) : centres relatifs au premier coup, posés à partir de `origin`.
func paint_trace(origin: Vector2, rel: Array, radius: float) -> void:
	brush_radius = radius
	for q: Vector2 in rel:
		paint_at(origin + q, radius)
		brush_stroke.append(origin + q)

func stroke_relative() -> Array:
	var out: Array = []
	if brush_stroke.is_empty():
		return out
	var o: Vector2 = brush_stroke[0]
	var last := Vector2.INF
	for q: Vector2 in brush_stroke:
		if last.x > 1.0e8 or q.distance_to(last) >= 0.3:
			out.append(snap(q - o))
			last = q
	return out

## Couleurs d'aperçu de l'aplanissement : déblai (orangé), remblai (bleuté), niveau (vert).
func show_flatten(op: Dictionary) -> void:
	_flat_colors.clear()
	if op.has("target"):
		var target: int = op["target"]
		for i in brush_cells:
			var d := lab.field.top[int(i)] - target
			_flat_colors[i] = Color(1.0, 0.55, 0.15, 0.62) if d > 0 else (Color(0.25, 0.6, 1.0, 0.62) if d < 0 else Color(0.35, 0.95, 0.45, 0.55))
	_draw_brush(not bool(op.get("ok", false)))

func reset_flatten_colors() -> void:
	_flat_colors.clear()
	_draw_brush()

# ------------------------------------------------------------------ entrées

func _process(_delta: float) -> void:
	if camera == null or lab == null:
		return
	_update_aim()
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if enabled and captured:
		match tool:
			Tool.POINT:
				if not has_point():
					_draw_point(true)
			Tool.RECT:
				if rect_state == 1:
					rect_b = _second_corner()
					_draw_rect(true)
			Tool.BRUSH:
				_draw_hover()
				if _lmb_down and _was_captured and aim.x < 1.0e8:
					var c := snap(aim_xz())
					if _last_paint.x > 1.0e8 or c.distance_to(_last_paint) >= minf(brush_radius * 0.4, 0.4):
						paint_at(c)
						brush_stroke.append(c)
						_last_paint = c
				else:
					_last_paint = Vector2.INF
	if tool != Tool.BRUSH:
		_hover_mi.mesh = null
	_was_captured = captured

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or camera == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_lmb_down = event.pressed and _was_captured          # état suivi ici : fiable quelle que soit la source de l'événement
	if event is InputEventMouseButton and event.pressed and _was_captured:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and aim.x < 1.0e8:
			match tool:
				Tool.POINT:
					set_point(aim_xz())
				Tool.RECT:
					if rect_state != 1:
						rect_a = snap(aim_xz())
						rect_b = rect_a
						rect_state = 1
						_rect_mi.mesh = null
						selection_changed.emit()
					else:
						rect_b = _second_corner()
						rect_state = 2
						_draw_rect()
						selection_changed.emit()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			match tool:
				Tool.POINT: clear_point()
				Tool.RECT: clear_rect()
				Tool.BRUSH:
					if aim.x < 1.0e8:
						paint_at(snap(aim_xz()), -1.0, true)
		elif tool == Tool.BRUSH and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_radius = minf(brush_radius + 0.2, 4.0)
			selection_changed.emit()
		elif tool == Tool.BRUSH and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_radius = maxf(brush_radius - 0.2, 0.4)
			selection_changed.emit()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: set_tool(Tool.POINT)
			KEY_2: set_tool(Tool.RECT)
			KEY_3: set_tool(Tool.BRUSH)
			KEY_R:
				lock_size = not lock_size
				selection_changed.emit()
			KEY_BRACKETLEFT:
				brush_radius = maxf(brush_radius - 0.2, 0.4)
				selection_changed.emit()
			KEY_BRACKETRIGHT:
				brush_radius = minf(brush_radius + 0.2, 4.0)
				selection_changed.emit()
			KEY_DELETE:
				clear_all()

func _second_corner() -> Vector2:
	var b := snap(aim_xz()) if aim.x < 1.0e8 else rect_b
	if lock_size:
		var sx := 1.0 if b.x >= rect_a.x else -1.0
		var sz := 1.0 if b.y >= rect_a.y else -1.0
		return rect_a + Vector2(sx * lock_dims.x, sz * lock_dims.y)
	return b

func _update_aim() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 40.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	aim = Vector3.INF if hit.is_empty() else (hit["position"] as Vector3)

# ------------------------------------------------------------------ dessin

func _gy(x: float, z: float) -> float:
	var g := lab.field.ground_at_m(x, z)
	return (0.0 if is_nan(g) else g) + 0.04

func _ribbon(st: Array, pts: Array, col: Color, w := 0.05) -> void:
	# ruban horizontal le long d'une polyligne posée sur le sol
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var d := (b - a)
		if d.length() < 0.001:
			continue
		var n := Vector2(-d.y, d.x).normalized() * w
		var q := [Vector3(a.x + n.x, _gy(a.x, a.y), a.y + n.y), Vector3(a.x - n.x, _gy(a.x, a.y), a.y - n.y),
			Vector3(b.x - n.x, _gy(b.x, b.y), b.y - n.y), Vector3(b.x + n.x, _gy(b.x, b.y), b.y + n.y)]
		st.append({"q": q, "c": col})

func _circle(c: Vector2, r: float, n := 40) -> Array:
	var pts: Array = []
	for k in n + 1:
		var a := TAU * float(k) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

func _mesh_from(quads: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for e in quads:
		var base := verts.size()
		for v in e["q"]:
			verts.append(v)
			cols.append(e["c"])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _draw_point(hover := false) -> void:
	var p := aim_xz() if hover else point
	if p.x > 1.0e8:
		_point_mi.mesh = null
		return
	var col := Color(0.45, 0.9, 1.0, 0.55 if hover else 0.95)
	var quads: Array = []
	_ribbon(quads, _circle(p, 0.38), col, 0.035)
	_ribbon(quads, _circle(p, 0.12), col, 0.03)
	var y0 := _gy(p.x, p.y)
	for a in [0.0, PI * 0.5]:
		var d := Vector2(cos(a), sin(a)) * 0.025
		quads.append({"q": [Vector3(p.x - d.x, y0, p.y - d.y), Vector3(p.x + d.x, y0, p.y + d.y), Vector3(p.x + d.x, y0 + 1.4, p.y + d.y), Vector3(p.x - d.x, y0 + 1.4, p.y - d.y)], "c": col})
	_point_mi.mesh = _mesh_from(quads)

func _draw_rect(live := false) -> void:
	if rect_a.x > 1.0e8:
		return
	var lo := Vector2(minf(rect_a.x, rect_b.x), minf(rect_a.y, rect_b.y))
	var hi := Vector2(maxf(rect_a.x, rect_b.x), maxf(rect_a.y, rect_b.y))
	var col := Color(1.0, 0.85, 0.25, 0.95) if not live else Color(1.0, 0.85, 0.25, 0.7)
	var fill := Color(1.0, 0.85, 0.25, 0.16)
	var quads: Array = []
	# remplissage colonne par colonne (suit le relief)
	var f := lab.field
	var c0 := f.col_of_m(lo.x, lo.y)
	var c1 := f.col_of_m(hi.x - 0.001, hi.y - 0.001)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			if not f.has_ground(cx, cz):
				continue
			var pc := f.center_m(cx, cz)
			var x0 := maxf(pc.x - V * 0.5, lo.x)
			var x1 := minf(pc.x + V * 0.5, hi.x)
			var z0 := maxf(pc.y - V * 0.5, lo.y)
			var z1 := minf(pc.y + V * 0.5, hi.y)
			var y := (float(f.top_at(cx, cz) + 1)) * V + 0.03
			quads.append({"q": [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)], "c": fill})
	var pts := []
	var step := 0.2
	var edge := func(a: Vector2, b: Vector2) -> void:
		var n := maxi(int(a.distance_to(b) / step), 1)
		for k in n + 1:
			pts.append(a.lerp(b, float(k) / float(n)))
		_ribbon(quads, pts, col, 0.04)
		pts.clear()
	edge.call(Vector2(lo.x, lo.y), Vector2(hi.x, lo.y))
	edge.call(Vector2(hi.x, lo.y), Vector2(hi.x, hi.y))
	edge.call(Vector2(hi.x, hi.y), Vector2(lo.x, hi.y))
	edge.call(Vector2(lo.x, hi.y), Vector2(lo.x, lo.y))
	_rect_mi.mesh = _mesh_from(quads)
	var c := (lo + hi) * 0.5
	_label.text = "%s × %s m" % [_fm(hi.x - lo.x), _fm(hi.y - lo.y)]
	_label.position = Vector3(c.x, _gy(c.x, hi.y) + 0.32, hi.y + 0.55)
	_label.visible = true

func _draw_brush(refused := false) -> void:
	var quads: Array = []
	var f := lab.field
	var base_col := Color(0.55, 1.0, 0.4, 0.5)
	if refused:
		base_col = Color(1.0, 0.3, 0.25, 0.55)
	for i in brush_cells:
		var cx: int = int(i) % f.n
		var cz: int = int(i) / f.n
		var pc := f.center_m(cx, cz)
		var y := (float(f.top_at(cx, cz) + 1)) * V + 0.03
		var col: Color = _flat_colors.get(i, base_col) if not refused else base_col
		quads.append({"q": [Vector3(pc.x - V * 0.5, y, pc.y - V * 0.5), Vector3(pc.x + V * 0.5, y, pc.y - V * 0.5), Vector3(pc.x + V * 0.5, y, pc.y + V * 0.5), Vector3(pc.x - V * 0.5, y, pc.y + V * 0.5)], "c": col})
	_brush_mi.mesh = _mesh_from(quads)

func _draw_hover() -> void:
	if aim.x > 1.0e8:
		_hover_mi.mesh = null
		return
	var quads: Array = []
	_ribbon(quads, _circle(snap(aim_xz()), brush_radius), Color(1, 1, 1, 0.9), 0.025)
	_hover_mi.mesh = _mesh_from(quads)

func refresh_visuals() -> void:
	if has_point():
		_draw_point()
	if rect_state == 2:
		_draw_rect()
	_draw_brush()
