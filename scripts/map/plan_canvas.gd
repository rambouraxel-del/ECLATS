class_name PlanCanvas
extends Control
## Vue AÉRIENNE 2D d'un plan d'île (Lot 7) : relief ombré + matières du sol, contour, zones, chemins (avec points de
## passage et liaisons), repères, départ, masque de protection, légende. Orientée nord en haut (z vers le bas), comme la
## vue aérienne 3D du jeu. Sert à l'aperçu du menu, à l'éditeur et aux captures.

const V := VoxelGrid.VOXEL_SIZE
const SEA := Color(0.09, 0.15, 0.25)
const EDGE := Color(0.96, 0.95, 0.90)

var plan: IslandPlan
var field: TerrainField
var path_reports: Array = []
var view_center := Vector2.ZERO          # point du monde (m) au centre de la vue
var px_per_m := 10.0
var show_handles := false                # points du contour et des chemins (édition)
var show_legend := true
var show_grid := true
var show_labels := true
var show_title := true
var legend_scale := 1.0                  # 1 = légende complète ; 0,8 = compacte (éditeur)
var interactive := false                 # molette = zoom, glisser (milieu) = déplacer
var selected_path := ""
var selected_landmark := ""
var cursor_world := Vector2.INF          # aperçu de pinceau / de sélection (édition)
var cursor_radius := 0.0
var cursor_color := Color(1, 1, 1, 0.9)
var cursor_note := ""
var sel_rect := Rect2()                  # sélection rectangulaire (monde, m) ; size == 0 : aucune
var sel_cells: Array = []                # sélection au pinceau : Vector2 (centres, m) — dessinée en voile
var sel_color := Color(0.30, 0.85, 1.0, 0.35)
var draft_outline: Array = []            # contour en cours de tracé
var draft_path: Array = []               # chemin en cours de tracé
var hint := ""

var _img: Image
var _tex: ImageTexture
var _mask_img: Image
var _mask_tex: ImageTexture
var _mask_count := 0
var _pan_from := Vector2.ZERO
var _panning := false

signal view_changed
signal canvas_event(event: InputEvent)      # clics et mouvements non utilisés par le zoom / le déplacement (éditeur)

var _lo := 0
var _hi := 1

# ------------------------------------------------------------------ repère écran ↔ monde

func w2s(p: Vector2) -> Vector2:
	return (p - view_center) * px_per_m + size * 0.5

func s2w(p: Vector2) -> Vector2:
	return (p - size * 0.5) / px_per_m + view_center

func fit(margin_m := 4.0) -> void:
	if plan == null or plan.outline.size() < 3:
		view_center = Vector2.ZERO
		px_per_m = minf(size.x / (plan.width + 8.0), size.y / (plan.length + 8.0)) if plan != null else 10.0
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p: Vector2 in plan.outline:
		lo = lo.min(p)
		hi = hi.max(p)
	view_center = (lo + hi) * 0.5
	var span := hi - lo + Vector2(margin_m, margin_m) * 2.0
	var reserve := (282.0 * legend_scale) if show_legend else 0.0        # la légende occupe la gauche : l'île est centrée dans le reste
	px_per_m = minf((size.x - reserve) / span.x, size.y / span.y)
	view_center -= Vector2(reserve * 0.5 / px_per_m, 0.0)
	view_changed.emit()
	queue_redraw()

# ------------------------------------------------------------------ image du relief

static func make_image(f: TerrainField, plan: IslandPlan = null) -> Image:
	var n := f.n
	var pal := VoxelPalette.get_default()
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var lo := 1 << 30
	var hi := -(1 << 30)
	for t in f.top:
		if t != TerrainField.NO_GROUND:
			lo = mini(lo, t)
			hi = maxi(hi, t)
	for cz in n:
		for cx in n:
			_shade_px(img, f, pal, cx, cz, lo, hi)
	return img

static func _shade_px(img: Image, f: TerrainField, pal: VoxelPalette, cx: int, cz: int, lo: int, hi: int) -> void:
	var n := f.n
	var i := cx + cz * n
	var t := f.top[i]
	if t == TerrainField.NO_GROUND:
		img.set_pixel(cx, cz, Color(0, 0, 0, 0))
		return
	var c := pal.colors_linear[f.material[i]].linear_to_srgb()
	var tw := f.top_at(cx - 1, cz)
	var te := f.top_at(cx + 1, cz)
	var tn := f.top_at(cx, cz - 1)
	var ts := f.top_at(cx, cz + 1)
	if tw == TerrainField.NO_GROUND: tw = t
	if te == TerrainField.NO_GROUND: te = t
	if tn == TerrainField.NO_GROUND: tn = t
	if ts == TerrainField.NO_GROUND: ts = t
	var shade := clampf(1.0 + 0.16 * float((te - tw) + (ts - tn)), 0.62, 1.30)
	var alt := float(t - lo) / float(maxi(hi - lo, 1))
	# teinte d'altitude : bleuté en bas, doré en haut (lecture du relief) + ombrage + courbes de niveau
	var tint := Color(0.16, 0.42, 0.82).lerp(Color(1.0, 0.86, 0.45), alt)
	var col := Color(c.r * shade, c.g * shade, c.b * shade, 1.0).lerp(tint, 0.30)
	# courbes de niveau tous les mètres
	var k := floori(float(t + 1) * V)
	if floori(float(tw + 1) * V) != k or floori(float(tn + 1) * V) != k:
		col = col.darkened(0.34)
	img.set_pixel(cx, cz, col)

func set_field(f: TerrainField) -> void:
	field = f
	if f == null:
		_img = null
		_tex = null
		return
	_lo = 1 << 30
	_hi = -(1 << 30)
	for t in f.top:
		if t != TerrainField.NO_GROUND:
			_lo = mini(_lo, t)
			_hi = maxi(_hi, t)
	_img = make_image(f, plan)
	_tex = ImageTexture.create_from_image(_img)
	queue_redraw()

## Met à jour un rectangle de colonnes (après un coup de pinceau).
func refresh_rect(r: Rect2i) -> void:
	if field == null or _img == null:
		return
	var g := r.grow(1).intersection(Rect2i(0, 0, field.n, field.n))
	var pal := VoxelPalette.get_default()
	for cz in range(g.position.y, g.end.y):
		for cx in range(g.position.x, g.end.x):
			var t := field.top[cx + cz * field.n]
			if t != TerrainField.NO_GROUND:
				_lo = mini(_lo, t)
				_hi = maxi(_hi, t)
	for cz in range(g.position.y, g.end.y):
		for cx in range(g.position.x, g.end.x):
			_shade_px(_img, field, pal, cx, cz, _lo, _hi)
	_tex.update(_img)
	queue_redraw()

## Mise à jour partielle du masque (pendant un trait) : seules les colonnes du rectangle sont relues.
func refresh_mask_rect(layers: PlanLayers, r: Rect2i) -> void:
	if _mask_img == null:
		refresh_mask(layers)
		return
	var g := r.grow(1).intersection(Rect2i(0, 0, field.n, field.n))
	for cz in range(g.position.y, g.end.y):
		for cx in range(g.position.x, g.end.x):
			if layers.mask[cx + cz * field.n] != 0:
				var stripe := ((cx + cz) / 3) % 2 == 0
				_mask_img.set_pixel(cx, cz, Color(1.0, 0.18, 0.28, 0.62) if stripe else Color(1.0, 0.55, 0.60, 0.50))
			else:
				_mask_img.set_pixel(cx, cz, Color(0, 0, 0, 0))
	_mask_tex.update(_mask_img)
	_mask_count = maxi(_mask_count, 1)
	queue_redraw()

func refresh_mask(layers: PlanLayers) -> void:
	_mask_count = 0
	if layers == null or field == null:
		_mask_img = null
		_mask_tex = null
		queue_redraw()
		return
	var n := field.n
	_mask_img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for cz in n:
		for cx in n:
			if layers.mask[cx + cz * n] != 0:
				_mask_count += 1
				var stripe := ((cx + cz) / 3) % 2 == 0
				_mask_img.set_pixel(cx, cz, Color(1.0, 0.18, 0.28, 0.62) if stripe else Color(1.0, 0.55, 0.60, 0.50))
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	queue_redraw()

func mask_count() -> int:
	return _mask_count

# ------------------------------------------------------------------ dessin

func _font() -> Font:
	return ThemeDB.fallback_font

func _text(p: Vector2, s: String, size := 16, col := Color(1, 1, 1), align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	var f := _font()
	draw_string_outline(f, p, s, align, w, size, 5, Color(0.04, 0.06, 0.10, 0.95))
	draw_string(f, p, s, align, w, size, col)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	if plan == null:
		return
	if show_grid:
		_draw_grid()
	if _tex != null and field != null:
		var o := w2s(Vector2(float(field.origin.x) * V, float(field.origin.y) * V))
		draw_texture_rect(_tex, Rect2(o, Vector2(field.n, field.n) * V * px_per_m), false)
		if _mask_tex != null:
			draw_texture_rect(_mask_tex, Rect2(o, Vector2(field.n, field.n) * V * px_per_m), false)
	elif plan.outline.size() >= 3:
		var poly := PackedVector2Array()
		for p: Vector2 in plan.outline:
			poly.append(w2s(p))
		draw_colored_polygon(poly, Color(0.30, 0.42, 0.30, 0.9))
	# zones
	var labelled := {}
	var label_jobs: Array = []
	for z in plan.zones:
		var kd: Dictionary = IslandPlan.KINDS[z["kind"]]
		var c := w2s(z["c"])
		var r := float(z["r"]) * px_per_m
		var col: Color = kd["color"]
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.22))
		draw_arc(c, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.95), 2.5, true)
		if show_labels and not labelled.has(z["kind"]):
			labelled[z["kind"]] = true
			label_jobs.append([c + Vector2(-100.0, -r - 7.0), String(kd["label"]).get_slice(" (", 0), col.lightened(0.4)])
	# contour
	if plan.outline.size() >= 3:
		var line := PackedVector2Array()
		for p: Vector2 in plan.outline:
			line.append(w2s(p))
		line.append(line[0])
		draw_polyline(line, Color(0.03, 0.05, 0.08, 0.9), 6.0, true)
		draw_polyline(line, EDGE, 2.5, true)
		if show_handles:
			for q in line.size() - 1:
				draw_circle(line[q], 6.0, Color(0.03, 0.05, 0.08))
				draw_circle(line[q], 4.0, EDGE)
	if draft_outline.size() > 0:
		var dl := PackedVector2Array()
		for p: Vector2 in draft_outline:
			dl.append(w2s(p))
		if dl.size() >= 2:
			draw_polyline(dl, Color(1, 0.9, 0.3), 3.0, true)
		for q in dl:
			draw_circle(q, 5.0, Color(1, 0.9, 0.3))
		if cursor_world != Vector2.INF and dl.size() >= 1:
			draw_line(dl[dl.size() - 1], w2s(cursor_world), Color(1, 0.9, 0.3, 0.6), 2.0)
			if dl.size() >= 3:
				draw_line(w2s(cursor_world), dl[0], Color(1, 0.9, 0.3, 0.25), 2.0)
	# chemins
	for pa in plan.paths:
		_draw_path(pa)
	if draft_path.size() > 0:
		var pl := PackedVector2Array()
		for p: Vector2 in draft_path:
			pl.append(w2s(p))
		if pl.size() >= 2:
			draw_polyline(pl, Color(1, 0.9, 0.3), maxf(plan.paths[0]["width"] if not plan.paths.is_empty() else 2.0, 1.0) * px_per_m * 0.6, true)
		for q in pl:
			draw_circle(q, 5.0, Color(1, 0.9, 0.3))
		if cursor_world != Vector2.INF:
			draw_line(pl[pl.size() - 1], w2s(cursor_world), Color(1, 0.9, 0.3, 0.6), 2.0)
	# anomalies de pente
	for rep in path_reports:
		for q: Vector2 in rep["breaks"]:
			_marker_bad(w2s(q))
		for q: Vector2 in rep["steep"]:
			draw_circle(w2s(q), 4.0, Color(1.0, 0.35, 0.25, 0.9))
	for j in label_jobs:
		_text(j[0], j[1], 15, j[2], HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	# repères et départ
	for l in plan.landmarks:
		_draw_landmark(l)
	_draw_start()
	# sélection
	if sel_rect.size.x > 0.0 and sel_rect.size.y > 0.0:
		var rr := Rect2(w2s(sel_rect.position), sel_rect.size * px_per_m)
		draw_rect(rr, Color(sel_color.r, sel_color.g, sel_color.b, 0.06), true)
		draw_rect(rr, Color(sel_color.r, sel_color.g, sel_color.b, 1.0), false, 2.5)
		_text(rr.position + Vector2(4, -6), "%.1f × %.1f m" % [sel_rect.size.x, sel_rect.size.y], 15, Color(0.7, 0.95, 1.0))
	for q: Vector2 in sel_cells:
		draw_rect(Rect2(w2s(q) - Vector2(1, 1) * V * px_per_m * 0.5, Vector2(1, 1) * V * px_per_m), sel_color, true)
	# curseur (pinceau)
	if cursor_world != Vector2.INF and cursor_radius > 0.0:
		var cc := w2s(cursor_world)
		var rad := cursor_radius * px_per_m
		draw_circle(cc, rad, Color(cursor_color.r, cursor_color.g, cursor_color.b, 0.16))
		draw_arc(cc, rad, 0.0, TAU, 48, cursor_color, 2.5, true)
		draw_arc(cc, rad * 0.5, 0.0, TAU, 32, Color(cursor_color.r, cursor_color.g, cursor_color.b, 0.55), 1.5, true)
		if cursor_note != "":
			_text(cc + Vector2(rad + 8.0, 5.0), cursor_note, 15, Color(1, 1, 1))
	_draw_north_scale()
	if show_title:
		_text(Vector2(14, 26), plan.name, 20, Color(1, 1, 1))
		_text(Vector2(14, 48), "Graine %d · %.0f × %.0f m · plan vue du ciel (nord en haut)" % [plan.seed, plan.width, plan.length], 14, Color(0.78, 0.86, 0.95))
	if show_legend:
		_draw_legend()
	if hint != "":
		_text(Vector2(size.x * 0.5, size.y - 16.0), hint, 15, Color(1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x - 40.0)

func _draw_grid() -> void:
	var step := 10.0
	var tl := s2w(Vector2.ZERO)
	var br := s2w(size)
	var gx := floorf(tl.x / step) * step
	while gx <= br.x:
		var sx := w2s(Vector2(gx, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color(1, 1, 1, 0.06), 1.0)
		gx += step
	var gz := floorf(tl.y / step) * step
	while gz <= br.y:
		var sy := w2s(Vector2(0, gz)).y
		draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(1, 1, 1, 0.06), 1.0)
		gz += step

func _draw_path(pa: Dictionary) -> void:
	var pts: Array = pa["pts"]
	var pl := PackedVector2Array()
	for p: Vector2 in pts:
		pl.append(w2s(p))
	if pl.size() < 2:
		return
	var w := maxf(float(pa["width"]) * px_per_m, 3.0)
	var sel := String(pa["id"]) == selected_path
	draw_polyline(pl, Color(0.10, 0.07, 0.04, 0.95), w + 5.0, true)
	draw_polyline(pl, Color(1.0, 0.85, 0.3) if sel else Color(0.93, 0.82, 0.60), w, true)
	for q in pl.size():
		if q > 0 and q < pl.size() - 1:
			draw_circle(pl[q], w * 0.5, Color(0.93, 0.82, 0.60) if not sel else Color(1.0, 0.85, 0.3))
	if show_handles or sel:
		for q in pl.size():
			draw_circle(pl[q], 7.0, Color(0.05, 0.05, 0.08))
			draw_circle(pl[q], 5.0, Color(1, 1, 1) if q % (pl.size() - 1) != 0 else Color(1.0, 0.55, 0.15))
	# liaisons : extrémités reliées à une zone
	for end in [0, pl.size() - 1]:
		var zid := String(pa.get("from", "")) if end == 0 else String(pa.get("to", ""))
		if zid != "":
			draw_arc(pl[end], 10.0, 0.0, TAU, 20, Color(1, 1, 1), 2.5, true)
			draw_circle(pl[end], 4.0, Color(0.10, 0.07, 0.04))

func _marker_bad(p: Vector2) -> void:
	draw_circle(p, 9.0, Color(1, 0.15, 0.15, 0.9))
	draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), Color(1, 1, 1), 2.5)
	draw_line(p + Vector2(-5, 5), p + Vector2(5, -5), Color(1, 1, 1), 2.5)

func _draw_landmark(l: Dictionary) -> void:
	var p := w2s(l["pos"])
	var kd: Dictionary = IslandPlan.LANDMARK_KINDS.get(l["kind"], IslandPlan.LANDMARK_KINDS["lieu"])
	var col: Color = kd["color"]
	var sel := String(l["id"]) == selected_landmark
	if l["kind"] == "vue":
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + float(k) * PI / 5.0
			var r := 12.0 if k % 2 == 0 else 5.2
			pts.append(p + Vector2.from_angle(a) * r)
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.1, 0.08, 0.02), 2.0, true)
	else:
		var pts := PackedVector2Array([p + Vector2(0, -12), p + Vector2(10, 0), p + Vector2(0, 12), p + Vector2(-10, 0)])
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.2, 0.05, 0.1), 2.0, true)
	if sel:
		draw_arc(p, 17.0, 0.0, TAU, 24, Color(1, 1, 1), 2.5, true)
	if show_labels and String(l.get("label", "")) != "":
		_text(p + Vector2(16, 5), String(l["label"]), 15, col.lightened(0.3))

func _draw_start() -> void:
	if plan.outline.size() < 3:
		return
	var p := w2s(plan.start)
	var tri := PackedVector2Array([p + Vector2(0, -11), p + Vector2(10, 8), p + Vector2(-10, 8)])
	draw_colored_polygon(tri, Color(0.35, 0.95, 0.45))
	tri.append(tri[0])
	draw_polyline(tri, Color(0.02, 0.15, 0.05), 2.0, true)
	if show_labels:
		_text(p + Vector2(14, 16), "Départ", 15, Color(0.6, 1.0, 0.65))

func _draw_north_scale() -> void:
	var c := Vector2(size.x - 38.0, 44.0)
	draw_circle(c, 22.0, Color(0.05, 0.08, 0.12, 0.8))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -16), c + Vector2(7, 8), c + Vector2(0, 3), c + Vector2(-7, 8)]), Color(1, 1, 1))
	_text(c + Vector2(-5, 20), "N", 14, Color(1, 1, 1))
	var len_m := 10.0
	var a := Vector2(size.x - 40.0 - len_m * px_per_m, size.y - 36.0)
	var b := a + Vector2(len_m * px_per_m, 0)
	draw_line(a, b, Color(0.04, 0.06, 0.1), 7.0)
	draw_line(a, b, Color(1, 1, 1), 3.0)
	draw_line(a + Vector2(0, -6), a + Vector2(0, 6), Color(1, 1, 1), 3.0)
	draw_line(b + Vector2(0, -6), b + Vector2(0, 6), Color(1, 1, 1), 3.0)
	_text(a + Vector2(0, -12), "10 m", 15, Color(1, 1, 1))

func _draw_legend() -> void:
	var rows: Array = []
	var seen := {}
	for z in plan.zones:
		if not seen.has(z["kind"]):
			seen[z["kind"]] = true
			rows.append(["zone", IslandPlan.KINDS[z["kind"]]["color"], String(IslandPlan.KINDS[z["kind"]]["label"])])
	if not plan.paths.is_empty():
		rows.append(["path", Color(0.93, 0.82, 0.60), "Chemin (largeur du plan)"])
		rows.append(["link", Color(1, 1, 1), "Liaison chemin ↔ zone"])
	if plan.outline.size() >= 3:
		rows.append(["start", Color(0.35, 0.95, 0.45), "Point de départ"])
	if rows.is_empty():
		return
	var has := {}
	for l in plan.landmarks:
		has[l["kind"]] = true
	if has.has("vue"):
		rows.append(["vue", IslandPlan.LANDMARK_KINDS["vue"]["color"], "Point de vue"])
	if has.has("lieu"):
		rows.append(["lieu", IslandPlan.LANDMARK_KINDS["lieu"]["color"], "Lieu à dévoiler"])
	if _mask_count > 0:
		rows.append(["mask", Color(1.0, 0.18, 0.28), "Zone protégée (masque)"])
	var bad := false
	for rep in path_reports:
		if not bool(rep["ok"]):
			bad = true
	if bad:
		rows.append(["bad", Color(1, 0.15, 0.15), "Rupture de pente sur un chemin"])
	var ls := legend_scale
	var rh := 24.0 * ls
	var w := 262.0 * ls
	var h := rows.size() * rh + 36.0 * ls
	var o := Vector2(12.0, size.y - h - 12.0)
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.05, 0.08, 0.12, 0.90), true)
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.35, 0.50, 0.65, 0.8), false, 1.5)
	_text(o + Vector2(10, 21 * ls), "Légende", int(16 * ls), Color(0.75, 0.9, 1.0))
	var y := o.y + 36.0 * ls
	for r in rows:
		var sw := Vector2(o.x + 22.0 * ls, y + rh * 0.5 - 2.0)
		match r[0]:
			"zone":
				draw_circle(sw, 8.0, Color(r[1].r, r[1].g, r[1].b, 0.35))
				draw_arc(sw, 8.0, 0.0, TAU, 20, r[1], 2.5, true)
			"path":
				draw_line(sw + Vector2(-11, 0), sw + Vector2(11, 0), Color(0.1, 0.07, 0.04), 9.0)
				draw_line(sw + Vector2(-11, 0), sw + Vector2(11, 0), r[1], 5.0)
			"link":
				draw_arc(sw, 8.0, 0.0, TAU, 20, Color(1, 1, 1), 2.5, true)
				draw_circle(sw, 3.0, Color(0.5, 0.4, 0.3))
			"start":
				draw_colored_polygon(PackedVector2Array([sw + Vector2(0, -8), sw + Vector2(8, 6), sw + Vector2(-8, 6)]), r[1])
			"vue":
				draw_colored_polygon(PackedVector2Array([sw + Vector2(0, -9), sw + Vector2(3, -3), sw + Vector2(9, -3), sw + Vector2(4, 2), sw + Vector2(6, 9), sw + Vector2(0, 5), sw + Vector2(-6, 9), sw + Vector2(-4, 2), sw + Vector2(-9, -3), sw + Vector2(-3, -3)]), r[1])
			"lieu":
				draw_colored_polygon(PackedVector2Array([sw + Vector2(0, -9), sw + Vector2(8, 0), sw + Vector2(0, 9), sw + Vector2(-8, 0)]), r[1])
			"mask":
				draw_rect(Rect2(sw - Vector2(8, 7), Vector2(16, 14)), Color(r[1].r, r[1].g, r[1].b, 0.7), true)
			"bad":
				draw_circle(sw, 7.0, r[1])
		_text(Vector2(o.x + 40.0 * ls, y + rh * 0.5 + 3.0), String(r[2]), int(15 * ls), Color(0.95, 0.97, 1.0))
		y += rh

# ------------------------------------------------------------------ navigation (zoom, déplacement)

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var handled := false
		if event is InputEventMouseButton:
			var b := (event as InputEventMouseButton).button_index
			handled = b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN or b == MOUSE_BUTTON_MIDDLE
		elif _panning:
			handled = true
		if not handled:
			canvas_event.emit(event)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_pan_from = mb.position
			accept_event()
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		view_center -= (mm.position - _pan_from) / px_per_m
		_pan_from = mm.position
		view_changed.emit()
		queue_redraw()
		accept_event()

func _zoom_at(screen_p: Vector2, k: float) -> void:
	var before := s2w(screen_p)
	px_per_m = clampf(px_per_m * k, 3.0, 60.0)
	var after := s2w(screen_p)
	view_center += before - after
	view_changed.emit()
	queue_redraw()
