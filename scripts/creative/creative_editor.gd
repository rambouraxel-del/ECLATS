class_name CreativeEditor
extends Node3D
## ÉDITEUR D'ÎLES CRÉATIF : mode développeur intégré au jeu pour construire et modifier librement une île d'histoire.
## Même document que l'éditeur de carte 2D (MapDoc : plan, relief, matières, masque, maisons, objets, historique) et même île 3D
## (LabWorld) : tout ce qui est fait ici s'enregistre dans la carte (format eclats-carte v4) et se rouvre dans l'éditeur 2D.
##   Vues : aérienne (V), première personne en vol (V), jeu (P : l'île se parcourt avec collisions, P revient à l'éditeur).
##   Outils : 1 Sélection · 2 Poser (inventaire I) · 3 Relief · 4 Matière · 5 Carte · 6 Générer · 7 Atelier (construire en 1re personne).
## Voir docs/EDITEUR_CREATIF.md pour toutes les commandes.

const V := VoxelGrid.VOXEL_SIZE
const TOOLS := [["select", "Sélection"], ["place", "Poser"], ["terrain", "Relief"], ["material", "Matière"], ["map", "Carte"], ["generate", "Générer"]]
const SNAP_M := 0.5
const EYE := 1.6

signal changed                      # le document a changé (l'interface se rafraîchit)
signal toast(text: String, level: String)

var session: MapSession
var doc: MapDoc
var lab: LabWorld
var env: EnvironmentManager
var obj_root: Node3D
var obj_nodes := {}                 # id d'objet → nœud
var house_nodes := {}               # id de maison → nœud
var overlay: Node3D                 # pinceau, repères, chemins (outils)
var ui: CreativeUi
var ready_to_edit := false
var busy := false

var mode := "aerial"                # aerial | fp | play
var tool := "select"
var cam: Camera3D
var a_target := Vector3.ZERO
var a_dist := 70.0
var a_yaw := 0.0
var a_pitch := -1.0
var f_pos := Vector3.ZERO
var f_yaw := 0.0
var f_pitch := -0.1
var f_walk := false                 # vrai : suit le sol à hauteur des yeux ; faux : vol libre
var captured := false
var explorer: Explorer
var camrig: ThirdPersonCamera
var _before_play := "aerial"

# --- sélection et pose
var selected := ""                  # identifiant d'objet, ou "h:<id>" pour une maison
var inv_item: Dictionary = {}       # élément d'inventaire choisi (outil Poser)
var inv_yaw := 0.0
var inv_scale := 1.0
var grid_snap := true
var ghost: Node3D
var ghost_ok := true
var ghost_text := ""
var house_model: Construction = null
var house_yaw := 0
var house_link := true
var house_eval: Dictionary = {}
var _ghost_key := ""
var _grab := false
var _grab_from := Vector2.ZERO
var _grab_dup := false

# --- relief, matière, protection
var brush := {"mode": "monter", "radius": 2.5, "strength": 0.6, "material": 0}
var _stroke := false
var _stroke_tool := ""
var _last_dab := Vector2.INF
var _dirty := Rect2i()
var _dab_t := 0.0

# --- carte
var map_sub := "zone"               # zone | chemin | repere | protege | contour
var zone_kind := "bois"
var path_pts: Array[Vector2] = []   # chemin en cours de tracé
var path_edit := ""                 # chemin dont on déplace un point
var _drag_path := {"id": "", "k": -1}
var _zone_stroke := false
var _last_zone := Vector2.INF

# --- génération
var gen := {"preset": "foret", "radius": 6.0, "densite": 60, "etals": 4, "seed": 1}
var gen_last := {}                  # dernière génération {center, radius, preset}

# --- instantané du monde affiché (détection des changements de relief)
var _top_snap := PackedInt32Array()
var _mat_snap := PackedByteArray()
var _field_ref: TerrainField = null
var _syncing := false
var _resync := false
var _ring: MeshInstance3D
var _marks: MeshInstance3D
var _handles: Node3D
var _mask: MeshInstance3D
var mouse_override := Vector2.INF   # essais et captures : remplace la position de la souris
var aim_override := Vector3.INF     # idem : remplace le point visé au sol
var last_message := ""

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	GameInput.ensure()
	App.current_path = App.CREATIVE_SCENE
	App.set_tech_default(false)
	App.capture_on_resume = false
	App.set_scene_help("Éditeur d'îles créatif · V vue · P jouer · I inventaire · Ctrl+Z défaire · Ctrl+S enregistrer")
	env = get_node_or_null("Environment") as EnvironmentManager
	ui = CreativeUi.new()
	ui.name = "Ui"
	add_child(ui)
	ui.setup(self)
	ui.loading("Préparation de l'île…")
	await get_tree().process_frame
	await get_tree().process_frame
	await _open_from_launch()

## Document de départ : session en cours (retour de l'atelier, de la vue 3D), île vide, graine ou carte enregistrée.
func _open_from_launch() -> void:
	var l: Dictionary = App.launch
	if l.has("session") and l["session"] != null:
		session = l["session"] as MapSession
	else:
		var d: MapDoc
		var path := ""
		match String(l.get("mode", "vide")):
			"graine":
				d = MapDoc.from_plan(PlanGenerator.generate(int(l.get("seed", 7)), float(l.get("width", 56.0)), float(l.get("length", 48.0))))
			"ouvrir":
				d = MapDoc.new()
				var r := d.open_from(String(l["path"]))
				if not bool(r["ok"]):
					d = _empty_doc()
					toast.emit("Ouverture impossible : %s Une île vide est ouverte à la place." % String(r["error"]), "error")
				else:
					path = String(l["path"])
			_:
				d = _empty_doc()
		session = MapSession.begin(d, path)
		if String(l.get("mode", "vide")) == "graine":
			d.plan.name = "Île %d" % int(l.get("seed", 7))
	MapSession.current = session
	doc = session.doc
	await _make_world()
	_start_view()
	ui.loading("")
	ready_to_edit = true
	if not l.has("session") or l["session"] == null:
		toast.emit("Éditeur prêt. V : vue · I : inventaire · 1-6 : outils", "info")
	changed.emit()

## Île vide : un contour ovale irrégulier (≈ 40 × 32 m) et un plateau plat au centre : on peut poser et sculpter tout de suite.
static func _empty_doc() -> MapDoc:
	var p := IslandPlan.blank("Île vide", 1, 56.0, 48.0)
	var pts: Array = []
	for k in 20:
		var a := TAU * float(k) / 20.0
		var rr := 1.0 + 0.10 * sin(3.0 * a + 0.6) + 0.06 * sin(5.0 * a + 1.3)
		pts.append(Vector2(cos(a) * 20.0 * rr, sin(a) * 16.0 * rr))
	p.outline = pts
	p.start = Vector2(-6, 2)
	p.zones.append({"id": p.new_id("zone"), "kind": "plateau", "c": Vector2(0, 0), "r": 11.0, "h": 4.0})
	p.settings["relief"] = 0.6
	p.generated = false
	return MapDoc.from_plan(p)

# ------------------------------------------------------------------ monde 3D

func _make_world() -> void:
	ready_to_edit = false
	for n in [lab, obj_root, overlay]:
		if n != null:
			n.queue_free()
	obj_nodes.clear()
	house_nodes.clear()
	if doc.field == null:
		doc.rebuild(true)
	lab = LabWorld.new()
	lab.name = "Lab"
	add_child(lab)
	lab.setup_field(doc.field, "plan", doc.plan.seed, doc.plan.start)
	if env != null:
		env.setup(doc.plan.seed)
	obj_root = Node3D.new()
	obj_root.name = "ObjetsCrees"
	add_child(obj_root)
	overlay = Node3D.new()
	overlay.name = "Outils"
	add_child(overlay)
	_make_overlay()
	_field_ref = doc.field
	_top_snap = doc.field.top.duplicate()
	_mat_snap = doc.field.material.duplicate()
	_sync_nodes()

func _make_overlay() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Pinceau"
	_ring.mesh = ImmediateMesh.new()
	_ring.material_override = _line_mat(Color(1, 0.9, 0.3))
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.add_child(_ring)
	_marks = MeshInstance3D.new()
	_marks.name = "Reperes"
	_marks.mesh = ImmediateMesh.new()
	_marks.material_override = _line_mat(Color(1, 1, 1))
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.add_child(_marks)
	_handles = Node3D.new()
	_handles.name = "Poignees"
	overlay.add_child(_handles)
	_mask = MeshInstance3D.new()
	_mask.name = "ZonesProtegees"
	_mask.mesh = ImmediateMesh.new()
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mask.material_override = mm
	_mask.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.add_child(_mask)

static func _line_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.no_depth_test = true
	m.render_priority = 10
	return m

## Aligne les nœuds d'objets et de maisons sur le document (ajouts, retraits, déplacements, relief changé dessous).
func _sync_nodes() -> void:
	var want := {}
	for o in doc.plan.objects:
		var id := String(o["id"])
		want[id] = true
		if not obj_nodes.has(id):
			var n := CreativeObjects.make_node(o, doc.field)
			obj_root.add_child(n)
			obj_nodes[id] = n
		else:
			(obj_nodes[id] as Node3D).transform = CreativeObjects.transform_for(o, doc.field)
	for id in obj_nodes.keys():
		if not want.has(id):
			(obj_nodes[id] as Node3D).queue_free()
			obj_nodes.erase(id)
	var wh := {}
	for h in doc.plan.houses:
		var hid := String(h["id"])
		wh[hid] = true
		if not house_nodes.has(hid):
			var r := Construction.from_dict(h["model"])
			if bool(r["ok"]):
				var model: Construction = r["construction"]
				var node := ConstructionView.create(model, {"collide": true})
				node.name = "Maison_%s" % hid
				node.transform = HousePad.node_transform(model, h["pos"], int(h["yaw"]), float(h["ground_m"]))
				lab.add_child(node)
				house_nodes[hid] = node
	for hid in house_nodes.keys():
		if not wh.has(hid):
			(house_nodes[hid] as Node3D).queue_free()
			house_nodes.erase(hid)
	if selected != "" and not _selection_exists():
		selected = ""

func _selection_exists() -> bool:
	if selected.begins_with("h:"):
		return house_nodes.has(selected.substr(2))
	return obj_nodes.has(selected)

## À appeler après TOUTE opération du document (pose, annulation, rétablissement, régénération…) : met l'île 3D à jour.
## Relief changé : seules les tuiles touchées sont reconstruites ; carte entièrement recalculée (contour, zones, chemins) : île reconstruite.
func sync() -> void:
	if _syncing:
		_resync = true
		return
	_syncing = true
	while true:
		_resync = false
		if doc.field != _field_ref:
			var keep := selected
			await _make_world()
			selected = keep
			_start_cameras_keep()
		else:
			var rect := _diff_rect()
			if rect.size != Vector2i.ZERO:
				await lab.rebuild_rect(rect)
				_top_snap = doc.field.top.duplicate()
				_mat_snap = doc.field.material.duplicate()
			_sync_nodes()
		if not _resync:
			break
	_syncing = false
	ready_to_edit = true
	_refresh_overlay()
	changed.emit()

func _diff_rect() -> Rect2i:
	var n := doc.field.n
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	var t := doc.field.top
	var m := doc.field.material
	if t.size() != _top_snap.size():
		return Rect2i(0, 0, n, n)
	for i in t.size():
		if t[i] != _top_snap[i] or m[i] != _mat_snap[i]:
			var x := i % n
			var z := i / n
			lo = Vector2i(mini(lo.x, x), mini(lo.y, z))
			hi = Vector2i(maxi(hi.x, x), maxi(hi.y, z))
	if hi.x < 0:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)

# ------------------------------------------------------------------ caméras

func _island_center() -> Vector2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p: Vector2 in doc.plan.outline:
		lo = lo.min(p)
		hi = hi.max(p)
	return (lo + hi) * 0.5 if hi.x > lo.x else Vector2.ZERO

func _start_view() -> void:
	cam = Camera3D.new()
	cam.name = "CameraEditeur"
	cam.fov = 60.0
	cam.near = 0.1
	cam.far = 3000.0
	add_child(cam)
	cam.current = true
	var c := _island_center()
	var g := doc.field.ground_at_m(c.x, c.y)
	a_target = Vector3(c.x, 0.0 if is_nan(g) else g, c.y)
	var ext := maxf(doc.plan.width, doc.plan.length)
	a_dist = clampf(ext * 1.0, 30.0, 160.0)
	a_yaw = 0.0
	a_pitch = -1.0
	var s := doc.plan.start
	var gs := doc.field.ground_at_m(s.x, s.y)
	f_pos = Vector3(s.x, (0.0 if is_nan(gs) else gs) + 3.0, s.y)
	f_yaw = 0.0
	f_pitch = -0.2
	set_mode("aerial")

func _start_cameras_keep() -> void:
	if cam == null or not is_instance_valid(cam):
		_start_view()

func set_mode(m: String) -> void:
	if m == "play" and doc.field == null:
		return
	if mode == "play" and m != "play":
		_leave_play()
	mode = m
	match m:
		"aerial":
			_set_capture(false)
			cam.current = true
		"fp":
			cam.current = true
			_set_capture(DisplayServer.get_name() != "headless" and not ui.panel_open())
		"play":
			_enter_play()
	_apply_cam()
	changed.emit()

func _set_capture(on: bool) -> void:
	captured = on
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)

func toggle_view() -> void:
	if mode == "play":
		return
	set_mode("fp" if mode == "aerial" else "aerial")

func _enter_play() -> void:
	_before_play = "aerial" if mode == "aerial" else "fp"
	var p := Vector3(f_pos.x, 0, f_pos.z)
	if mode_was_aerial():
		p = Vector3(a_target.x, 0, a_target.z)
	var g := doc.field.ground_at_m(p.x, p.z)
	if is_nan(g):
		p = Vector3(doc.plan.start.x, 0, doc.plan.start.y)
		g = doc.field.ground_at_m(p.x, p.z)
	explorer = Explorer.new()
	explorer.name = "Explorer"
	add_child(explorer)
	explorer.kill_y = -60.0
	explorer.fell.connect(func() -> void:
		explorer.teleport(Vector3(doc.plan.start.x, doc.field.ground_at_m(doc.plan.start.x, doc.plan.start.y) + 0.2, doc.plan.start.y), f_yaw)
		toast.emit("Retour au point de départ", "info"))
	explorer.teleport(Vector3(p.x, (0.0 if is_nan(g) else g) + 0.1, p.z), f_yaw)
	camrig = ThirdPersonCamera.new()
	camrig.name = "CameraJeu"
	camrig.target = explorer
	add_child(camrig)
	camrig.yaw = f_yaw
	camrig.pitch = -0.1
	camrig.arm.add_excluded_object(explorer.get_rid())
	camrig.first_person = true
	camrig.snap()
	cam.current = false
	camrig.cam.current = true
	App.capture_on_resume = true
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	captured = true

func mode_was_aerial() -> bool:
	return _before_play == "aerial"

func _leave_play() -> void:
	if explorer != null:
		f_pos = explorer.global_position + Vector3(0, 2.5, 0)
		f_yaw = camrig.yaw if camrig != null else f_yaw
	for n in [camrig, explorer]:
		if n != null:
			n.queue_free()
	camrig = null
	explorer = null
	cam.current = true
	App.capture_on_resume = false
	_set_capture(false)

func _apply_cam() -> void:
	if cam == null:
		return
	match mode:
		"aerial":
			var dir := Vector3(sin(a_yaw) * cos(a_pitch), -sin(a_pitch), cos(a_yaw) * cos(a_pitch))
			var off := Vector3(-sin(a_yaw) * cos(a_pitch), sin(-a_pitch), -cos(a_yaw) * cos(a_pitch))
			cam.position = a_target + Vector3(sin(a_yaw) * cos(a_pitch), -sin(a_pitch), cos(a_yaw) * cos(a_pitch)) * a_dist
			cam.look_at(a_target, Vector3.UP)
		"fp":
			cam.position = f_pos
			cam.rotation = Vector3(f_pitch, f_yaw, 0.0)

# ------------------------------------------------------------------ boucle

func _process(delta: float) -> void:
	if not ready_to_edit or cam == null:
		return
	match mode:
		"aerial": _move_aerial(delta)
		"fp": _move_fp(delta)
	if mode != "play":
		_apply_cam()
		_update_tool(delta)
	else:
		_refresh_overlay()

func _axes() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	return v

func _move_aerial(delta: float) -> void:
	if ui.typing():
		return
	var v := _axes()
	if v != Vector2.ZERO:
		var sp := a_dist * 0.9 * delta
		var fwd := Vector3(-sin(a_yaw), 0, -cos(a_yaw))
		var right := Vector3(cos(a_yaw), 0, -sin(a_yaw))
		a_target += (right * v.x + fwd * -v.y) * sp
		_clamp_target()
	if Input.is_physical_key_pressed(KEY_Q):
		a_yaw -= 1.2 * delta
	if Input.is_physical_key_pressed(KEY_E):
		a_yaw += 1.2 * delta

func _clamp_target() -> void:
	var c := _island_center()
	var lim := maxf(doc.plan.width, doc.plan.length) * 0.8
	a_target.x = clampf(a_target.x, c.x - lim, c.x + lim)
	a_target.z = clampf(a_target.z, c.y - lim, c.y + lim)
	var g := doc.field.ground_at_m(a_target.x, a_target.z)
	a_target.y = lerpf(a_target.y, 0.0 if is_nan(g) else g, 0.15)

func _move_fp(delta: float) -> void:
	if ui.typing():
		return
	var v := _axes()
	var sp := 7.0 * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var basis := Basis(Vector3.UP, f_yaw)
	f_pos += basis * Vector3(v.x, 0, v.y) * sp * delta
	if f_walk:
		var g := doc.field.ground_at_m(f_pos.x, f_pos.z)
		if not is_nan(g):
			f_pos.y = lerpf(f_pos.y, g + EYE, clampf(12.0 * delta, 0.0, 1.0))
	else:
		if Input.is_physical_key_pressed(KEY_SPACE):
			f_pos.y += sp * 0.8 * delta
		if Input.is_physical_key_pressed(KEY_C) or Input.is_key_pressed(KEY_CTRL):
			f_pos.y -= sp * 0.8 * delta
		var g2 := doc.field.ground_at_m(f_pos.x, f_pos.z)
		if not is_nan(g2):
			f_pos.y = maxf(f_pos.y, g2 + 0.6)

# ------------------------------------------------------------------ visée

## Rayon (origine, direction) vers le curseur (souris libre) ou le centre de l'écran (souris capturée).
func pick_ray() -> Dictionary:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var m := mouse_override if mouse_override != Vector2.INF else (size * 0.5 if captured else vp.get_mouse_position())
	return {"o": cam.project_ray_origin(m), "d": cam.project_ray_normal(m)}

## Point du relief visé (INF si le rayon ne touche pas l'île).
func ground_hit(o: Vector3, d: Vector3) -> Vector3:
	var f := doc.field
	var t := 0.0
	var step := 0.35
	var prev_t := 0.0
	var found := false
	while t < 600.0:
		var p := o + d * t
		var g := f.ground_at_m(p.x, p.z)
		if not is_nan(g) and p.y <= g:
			found = true
			break
		prev_t = t
		t += step * (1.0 + t * 0.01)
	if not found:
		return Vector3.INF
	var lo := prev_t
	var hi := t
	for i in 10:
		var mid := (lo + hi) * 0.5
		var pm := o + d * mid
		var gm := f.ground_at_m(pm.x, pm.z)
		if not is_nan(gm) and pm.y <= gm:
			hi = mid
		else:
			lo = mid
	var pf := o + d * hi
	var gf := f.ground_at_m(pf.x, pf.z)
	return Vector3(pf.x, 0.0 if is_nan(gf) else gf, pf.z)

func aim() -> Vector3:
	if aim_override != Vector3.INF:
		return aim_override
	if cam == null or doc.field == null:
		return Vector3.INF
	var r := pick_ray()
	return ground_hit(r["o"], r["d"])

func aim2() -> Vector2:
	var a := aim()
	return Vector2(a.x, a.z) if a != Vector3.INF else Vector2.INF

func snap_point(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, SNAP_M), snappedf(p.y, SNAP_M)) if grid_snap else p

## Objet ou maison sous le curseur : "id" d'objet, "h:id" de maison, "" sinon.
func pick_thing(o: Vector3, d: Vector3) -> String:
	var best := ""
	var bt := 1.0e9
	for ob in doc.plan.objects:
		var t := CreativeObjects.ray_hit(ob, doc.field, o, d)
		if t >= 0.0 and t < bt:
			bt = t
			best = String(ob["id"])
	var g := ground_hit(o, d)
	for h in doc.plan.houses:
		var rect: Rect2 = h["rect"]
		var hn: Node3D = house_nodes.get(String(h["id"]))
		if hn == null:
			continue
		# la maison est choisie si le rayon passe dans son emprise, entre le sol et son toit
		var ht := 4.5
		var tt := 0.0
		while tt < 120.0:
			var p := o + d * tt
			if rect.has_point(Vector2(p.x, p.z)) and p.y >= float(h["ground_m"]) - 0.2 and p.y <= float(h["ground_m"]) + ht:
				if tt < bt:
					bt = tt
					best = "h:" + String(h["id"])
				break
			if g != Vector3.INF and tt > o.distance_to(g) + 1.0:
				break
			tt += 0.25
	return best

# ------------------------------------------------------------------ outils

func set_tool(t: String) -> void:
	_cancel_pending()
	tool = t
	if t == "place" and inv_item.is_empty():
		ui.show_inventory(true)
	changed.emit()
	_refresh_overlay()

func _cancel_pending() -> void:
	if _grab:
		_grab = false
		_sync_nodes()
	if not path_pts.is_empty():
		path_pts.clear()
	_clear_ghost()

func _update_tool(delta: float) -> void:
	var a := aim()
	var p2 := Vector2(a.x, a.z) if a != Vector3.INF else Vector2.INF
	match tool:
		"place":
			_update_ghost(p2)
		"select":
			if _grab and p2 != Vector2.INF:
				var np := snap_point(p2)
				var o := doc.object_by_id(selected)
				if not o.is_empty() and obj_nodes.has(selected):
					var tmp: Dictionary = o.duplicate()
					tmp["pos"] = np
					(obj_nodes[selected] as Node3D).transform = CreativeObjects.transform_for(tmp, doc.field)
		"terrain", "material":
			_dab_t -= delta
			if _stroke and p2 != Vector2.INF and _dab_t <= 0.0:
				_dab(p2)
				_dab_t = 0.05
		"map":
			if _zone_stroke and p2 != Vector2.INF:
				_zone_dab(p2)
			elif _stroke and p2 != Vector2.INF and map_sub == "protege" and _dab_t <= 0.0:
				_dab(p2)
				_dab_t = 0.05
			if _drag_path["id"] != "" and p2 != Vector2.INF:
				_drag_point(p2)
		"generate":
			pass
	_refresh_overlay(p2)

# --- Poser

func choose_item(item: Dictionary) -> void:
	inv_item = item
	inv_yaw = 0.0
	inv_scale = 1.0
	_clear_ghost()
	house_model = null
	if String(item.get("kind", "asset")) == "modele":
		var r := Construction.load_file(String(item["path"]))
		if bool(r["ok"]):
			house_model = r["construction"]
		else:
			toast.emit("Modèle illisible : %s" % String(r["error"]), "error")
			inv_item = {}
			return
	set_tool("place")
	tool = "place"
	changed.emit()

func _clear_ghost() -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null
	_ghost_key = ""

func _update_ghost(p2: Vector2) -> void:
	if inv_item.is_empty() or p2 == Vector2.INF:
		if ghost != null:
			ghost.visible = false
		return
	if house_model != null:
		_update_house_ghost(p2)
		return
	var key := "a:%s" % inv_item["id"]
	if ghost == null or _ghost_key != key:
		_clear_ghost()
		var tmp := MapDoc.make_object(String(inv_item["id"]), p2, inv_yaw, inv_scale)
		tmp["id"] = "ghost"
		ghost = CreativeObjects.make_node(tmp, doc.field, false)
		add_child(ghost)
		_tint(ghost, Color(0.5, 1.0, 0.6, 0.55))
		_ghost_key = key
	ghost.visible = true
	var pp := snap_point(p2)
	var o := MapDoc.make_object(String(inv_item["id"]), pp, inv_yaw, inv_scale)
	ghost.transform = CreativeObjects.transform_for(o, doc.field)
	var c := doc.col_of(pp)
	ghost_ok = doc.field.has_ground(c.x, c.y)
	ghost_text = "%s · cap %d° · échelle %.2f" % [inv_item["name"], roundi(fposmod(inv_yaw, 360.0)), inv_scale] if ghost_ok else "Hors de l'île : visez le sol."
	_tint(ghost, Color(0.5, 1.0, 0.6, 0.55) if ghost_ok else Color(1.0, 0.45, 0.4, 0.55))

func _update_house_ghost(p2: Vector2) -> void:
	var pos := Vector2(snappedf(p2.x, 0.1), snappedf(p2.y, 0.1))
	var key := "h:%s:%d" % [inv_item["id"], house_yaw]
	house_eval = doc.evaluate_house(house_model, pos, house_yaw, house_link)
	var ok := bool(house_eval.get("ok", false))
	if ghost == null or _ghost_key != key or ghost_ok != ok:
		_clear_ghost()
		var col := Color(0.4, 1.0, 0.55, 0.45) if ok else Color(1.0, 0.4, 0.35, 0.45)
		ghost = ConstructionView.create(house_model, {"ghost": col, "collide": false})
		add_child(ghost)
		_ghost_key = key
	ghost_ok = ok
	ghost.visible = true
	var gm := float(house_eval.get("ground_m", doc.field.ground_at_m(pos.x, pos.y)))
	ghost.transform = HousePad.node_transform(house_model, pos, house_yaw, 0.0 if is_nan(gm) else gm)
	var dir: Vector2i = house_eval.get("dir", Vector2i.ZERO)
	if ok:
		ghost_text = "✔ %s" % String(house_eval.get("text", "Implantation possible."))
	else:
		ghost_text = "✖ %s" % " ".join(PackedStringArray(house_eval.get("reasons", ["Implantation impossible."])))
	if dir != Vector2i.ZERO:
		ghost_text = "Porte côté %s · %s" % [HousePad.side_name(dir), ghost_text]

func _tint(n: Node, c: Color) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			(ch as MeshInstance3D).material_override = m
		_tint(ch, c)

func place_here() -> String:
	var a2 := aim2()
	if a2 == Vector2.INF or inv_item.is_empty():
		return ""
	if house_model != null:
		var pos := Vector2(snappedf(a2.x, 0.1), snappedf(a2.y, 0.1))
		var r := doc.place_house(house_model, pos, house_yaw, "", house_link)
		if bool(r["ok"]):
			toast.emit("Maison posée : %s" % house_model.name, "ok")
			sync()
			return "h:" + String(r["id"])
		toast.emit("✖ %s Rien n'a été modifié." % " ".join(PackedStringArray(r.get("reasons", ["Impossible."]))), "error")
		return ""
	var id := doc.add_object(String(inv_item["id"]), snap_point(a2), inv_yaw, inv_scale)
	if id == "":
		toast.emit("Hors de l'île : visez le sol.", "error")
		return ""
	sync()
	return id

func rotate_pending(dir: int) -> void:
	if tool == "place":
		if house_model != null:
			house_yaw = posmod(house_yaw + dir, 4)
		else:
			inv_yaw = fposmod(inv_yaw + 15.0 * dir, 360.0)
	elif selected != "" and not selected.begins_with("h:"):
		var o := doc.object_by_id(selected)
		if not o.is_empty() and doc.update_object(selected, {"yaw": fposmod(float(o["yaw"]) + 15.0 * dir, 360.0)}, "Tourner l'objet"):
			sync()
		elif not o.is_empty():
			toast.emit(doc.message, "error")
	changed.emit()

func scale_pending(f: float) -> void:
	if tool == "place" and house_model == null:
		inv_scale = clampf(inv_scale * f, 0.5, 2.5)
	elif selected != "" and not selected.begins_with("h:"):
		var o := doc.object_by_id(selected)
		if not o.is_empty() and doc.update_object(selected, {"scale": clampf(float(o["scale"]) * f, 0.5, 2.5)}, "Changer l'échelle"):
			sync()
	changed.emit()

# --- Sélection

func select_at_cursor() -> void:
	var r := pick_ray()
	var s := pick_thing(r["o"], r["d"])
	selected = s
	changed.emit()
	_refresh_overlay()

func delete_selected() -> void:
	if selected == "":
		return
	if selected.begins_with("h:"):
		if doc.remove_house(selected.substr(2)):
			toast.emit(doc.message, "ok")
			selected = ""
			sync()
		return
	if doc.delete_object(selected):
		selected = ""
		toast.emit("Objet supprimé (Ctrl+Z pour annuler)", "ok")
		sync()
	else:
		toast.emit(doc.message, "error")

func duplicate_selected() -> void:
	if selected == "" or selected.begins_with("h:"):
		return
	var id := doc.duplicate_object(selected, Vector2(1.2, 1.2))
	if id != "":
		selected = id
		toast.emit("Objet dupliqué : déplacez-le (G) ou laissez-le", "ok")
		sync()
	else:
		toast.emit("Duplication impossible ici.", "error")

func toggle_lock() -> void:
	if selected == "" or selected.begins_with("h:"):
		return
	var o := doc.object_by_id(selected)
	if o.is_empty():
		return
	var v := not bool(o["locked"])
	doc.update_object(selected, {"locked": v}, "Verrouiller l'objet" if v else "Déverrouiller l'objet")
	toast.emit("Objet verrouillé : il survivra aux régénérations." if v else "Objet déverrouillé.", "ok")
	changed.emit()
	_refresh_overlay()

func begin_grab() -> void:
	if selected == "" or selected.begins_with("h:"):
		return
	var o := doc.object_by_id(selected)
	if o.is_empty():
		return
	if bool(o["locked"]):
		toast.emit("Objet verrouillé : déverrouillez-le (L) avant de le déplacer.", "error")
		return
	_grab = true
	_grab_from = o["pos"]
	changed.emit()

func end_grab(commit: bool) -> void:
	if not _grab:
		return
	_grab = false
	if commit:
		var a2 := aim2()
		if a2 != Vector2.INF:
			var np := snap_point(a2)
			if np.distance_to(_grab_from) > 0.04:
				var c := doc.col_of(np)
				if doc.field.has_ground(c.x, c.y) and doc.update_object(selected, {"pos": np}, "Déplacer l'objet"):
					sync()
					changed.emit()
					return
	_sync_nodes()
	changed.emit()

## Remplace la maison choisie : elle est retirée (terrain restauré) et reprise en main pour la reposer ailleurs ou autrement.
func pick_up_house() -> void:
	if not selected.begins_with("h:"):
		return
	var hid := selected.substr(2)
	for h in doc.plan.houses:
		if String(h["id"]) == hid:
			var r := Construction.from_dict(h["model"])
			if not bool(r["ok"]):
				return
			var model: Construction = r["construction"]
			var yaw := int(h["yaw"])
			if doc.remove_house(hid):
				selected = ""
				house_model = model
				house_yaw = yaw
				inv_item = {"id": "reprise:" + hid, "name": String(h["name"]), "cat": "Mes maisons", "kind": "modele"}
				tool = "place"
				_clear_ghost()
				toast.emit("Maison reprise : visez le nouvel emplacement (R tourner, K raccord au chemin). Ctrl+Z pour tout annuler.", "info")
				sync()
			return

# --- Relief, matière, protection

func _brush_tool() -> String:
	if tool == "material":
		return "matiere"
	if tool == "map" and map_sub == "protege":
		return "masque"
	return String(brush["mode"])

func begin_stroke(erase := false) -> void:
	var p := aim2()
	if p == Vector2.INF or _stroke:
		return
	var t := _brush_tool()
	if erase:
		if t == "matiere":
			t = "gomme_matiere"
		elif t == "masque":
			t = "gomme_masque"
		else:
			return
	var label: String = {"monter": "Monter le relief", "creuser": "Creuser le relief", "aplanir": "Aplanir le relief", "adoucir": "Adoucir le relief",
		"matiere": "Peindre la matière", "gomme_matiere": "Effacer la matière", "masque": "Protéger la zone", "gomme_masque": "Retirer la protection"}.get(t, "Pinceau")
	doc.stroke_begin(label, t, p)
	_stroke = true
	_stroke_tool = t
	_last_dab = Vector2.INF
	_dirty = Rect2i()
	_dab(p)

func _dab(p: Vector2) -> void:
	if not _stroke:
		return
	if _last_dab != Vector2.INF and _last_dab.distance_to(p) < maxf(float(brush["radius"]) * 0.25, 0.15):
		return
	_last_dab = p
	var mid := VoxelPalette.get_default().id(IslandPlan.MATERIALS[int(brush["material"])][0])
	var r := doc.stroke_dab(_stroke_tool, p, float(brush["radius"]), float(brush["strength"]), mid)
	if r.size != Vector2i.ZERO:
		_dirty = r if _dirty.size == Vector2i.ZERO else _dirty.merge(r)
		if _stroke_tool not in ["masque", "gomme_masque"]:
			_live_rebuild()

var _live_busy := false

func _live_rebuild() -> void:
	if _live_busy or _dirty.size == Vector2i.ZERO:
		return
	_live_busy = true
	var rect := _dirty
	await lab.rebuild_rect(rect)
	_top_snap = doc.field.top.duplicate()
	_mat_snap = doc.field.material.duplicate()
	_live_busy = false

func end_stroke() -> void:
	if not _stroke:
		return
	_stroke = false
	var r := doc.stroke_end()
	if limit_hit():
		toast.emit("Limite de relief atteinte (±400 m).", "info")
	_dirty = Rect2i()
	_last_dab = Vector2.INF
	if r.size != Vector2i.ZERO:
		sync()

func limit_hit() -> bool:
	return doc.limit_hit

# --- Carte : zones, chemins, repères

func _zone_dab(p: Vector2) -> void:
	if _last_zone != Vector2.INF and _last_zone.distance_to(p) < maxf(float(brush["radius"]) * 0.5, 0.3):
		return
	_last_zone = p
	doc.add_zone_disc(zone_kind, p, float(brush["radius"]))

func begin_zone(erase := false) -> void:
	var p := aim2()
	if p == Vector2.INF:
		return
	doc.begin_op("Effacer une zone" if erase else "Peindre une zone « %s »" % IslandPlan.KINDS[zone_kind]["label"])
	if erase:
		doc.delete_zone_at(p)
		_finish_structural()
		return
	_zone_stroke = true
	_last_zone = Vector2.INF
	_zone_dab(p)

func end_zone() -> void:
	if not _zone_stroke:
		return
	_zone_stroke = false
	_finish_structural()

func _finish_structural() -> void:
	var why := doc.finish_op()
	if why != "":
		toast.emit(why, "error")
	else:
		toast.emit("Relief recalculé depuis le plan.", "info")
	sync()

func path_click(p: Vector2) -> void:
	# clic sur un point existant : on le saisit pour le déplacer ; sinon on ajoute un point au tracé
	var hit := _handle_at(p)
	if hit["id"] != "" and path_pts.is_empty():
		_drag_path = hit
		doc.begin_op("Déplacer un point de chemin" if hit["id"] != "contour" else "Déplacer un point du contour")
		return
	path_pts.append(snap_point(p))
	changed.emit()

func finish_path() -> void:
	if path_pts.size() >= 2:
		doc.begin_op("Tracer un chemin")
		doc.add_path(path_pts.duplicate())
		path_pts.clear()
		_finish_structural()
	else:
		path_pts.clear()
		changed.emit()

func _handle_at(p: Vector2) -> Dictionary:
	var best := {"id": "", "k": -1}
	var bd := 1.2
	for pa in doc.plan.paths:
		var pts: Array = pa["pts"]
		for k in pts.size():
			var d := p.distance_to(pts[k])
			if d < bd:
				bd = d
				best = {"id": String(pa["id"]), "k": k}
	if map_sub == "contour":
		best = {"id": "", "k": -1}
		bd = 1.4
		for k in doc.plan.outline.size():
			var d2 := p.distance_to(doc.plan.outline[k])
			if d2 < bd:
				bd = d2
				best = {"id": "contour", "k": k}
	return best

func _drag_point(p: Vector2) -> void:
	var q := snap_point(p)
	if _drag_path["id"] == "contour":
		doc.plan.outline[int(_drag_path["k"])] = q
	else:
		var pa := doc.plan.path_by_id(String(_drag_path["id"]))
		if not pa.is_empty():
			(pa["pts"] as Array)[int(_drag_path["k"])] = q

func end_drag() -> void:
	if _drag_path["id"] == "":
		return
	_drag_path = {"id": "", "k": -1}
	_finish_structural()

func remove_handle_at(p: Vector2) -> void:
	var hit := _handle_at(p)
	if hit["id"] == "":
		return
	doc.begin_op("Retirer un point")
	var ok := false
	if hit["id"] == "contour":
		ok = doc.remove_outline_point(int(hit["k"]))
	else:
		ok = doc.remove_path_point(String(hit["id"]), int(hit["k"]))
	if ok:
		_finish_structural()
	else:
		doc.cancel_op()
		toast.emit("Impossible de retirer ce point (il en faut au moins 3 au contour, 2 au chemin).", "error")

func insert_point_at(p: Vector2) -> void:
	# double-clic : ajoute un point au chemin le plus proche (sur le segment) ou au contour
	if map_sub == "contour":
		var best := -1
		var bd := 1.0e9
		var o := doc.plan.outline
		for k in o.size():
			var q := HousePad._seg_closest(p, o[k], o[(k + 1) % o.size()])
			if p.distance_to(q) < bd:
				bd = p.distance_to(q)
				best = k
		if best >= 0 and bd < 2.5:
			doc.begin_op("Ajouter un point au contour")
			doc.insert_outline_point(best + 1, snap_point(p))
			_finish_structural()
		return
	var np := HousePad.nearest_path(doc.plan.paths, p)
	if np.is_empty() or float(np["d"]) > 2.0:
		return
	var pa := doc.plan.path_by_id(String(np["path_id"]))
	var pts: Array = pa["pts"]
	var kk := 0
	var bd2 := 1.0e9
	for k in range(pts.size() - 1):
		var q2 := HousePad._seg_closest(p, pts[k], pts[k + 1])
		if p.distance_to(q2) < bd2:
			bd2 = p.distance_to(q2)
			kk = k
	doc.begin_op("Ajouter un point de chemin")
	doc.insert_path_point(String(pa["id"]), kk + 1, snap_point(p))
	_finish_structural()

func place_landmark(p: Vector2, kind: String) -> void:
	doc.begin_op("Poser un repère")
	doc.add_landmark(kind, p, "Repère")
	var why := doc.finish_op(false)
	if why != "":
		toast.emit(why, "error")
	changed.emit()

func set_start_here(p: Vector2) -> void:
	doc.begin_op("Déplacer le point de départ")
	doc.set_start(p)
	doc.finish_op(false)
	toast.emit("Point de départ déplacé.", "ok")
	changed.emit()

# --- Générer

func generate_here() -> void:
	var p := aim2()
	if p == Vector2.INF:
		toast.emit("Visez le sol de l'île.", "error")
		return
	_generate_at(p, float(gen["radius"]))

func generate_in_zone() -> void:
	var p := aim2()
	if p == Vector2.INF:
		return
	var z := doc.plan.zone_at(p)
	if z.is_empty():
		toast.emit("Aucune zone peinte sous le curseur : peignez-en une (outil Carte) ou utilisez le cercle.", "error")
		return
	_generate_at(z["c"], float(z["r"]))

func regenerate_last() -> void:
	if gen_last.is_empty():
		toast.emit("Rien à régénérer : générez d'abord une composition.", "info")
		return
	gen["seed"] = int(gen["seed"]) + 1
	_generate_at(gen_last["center"], float(gen_last["radius"]), String(gen_last["preset"]))

func _generate_at(center: Vector2, radius: float, preset := "") -> void:
	if preset == "":
		preset = String(gen["preset"])
	var r := doc.compose(preset, center, radius, int(gen["seed"]), {"densite": gen["densite"], "etals": gen["etals"]})
	if bool(r["ok"]):
		gen_last = {"center": center, "radius": radius, "preset": preset}
		var extra := ""
		if int(r["kept_locked"]) > 0:
			extra += " · %d verrouillé(s) conservé(s)" % int(r["kept_locked"])
		if int(r["kept_protected"]) > 0:
			extra += " · %d en zone protégée conservé(s)" % int(r["kept_protected"])
		toast.emit("%s%s" % [doc.message, extra], "ok")
		sync()
	else:
		toast.emit(doc.message, "error")

# ------------------------------------------------------------------ historique, fichiers

func undo() -> void:
	var l := doc.undo()
	toast.emit("Annulé : %s" % l if l != "" else "Rien à annuler.", "info")
	if l != "":
		sync()

func redo() -> void:
	var l := doc.redo()
	toast.emit("Rétabli : %s" % l if l != "" else "Rien à rétablir.", "info")
	if l != "":
		sync()

func save() -> Dictionary:
	var r := session.save()
	if bool(r["ok"]):
		toast.emit("Carte enregistrée : %s" % session.path.get_file(), "ok")
	else:
		toast.emit("Enregistrement impossible : %s La carte reste ouverte." % String(r["error"]), "error")
	changed.emit()
	return r

func save_as(nm: String) -> Dictionary:
	doc.plan.name = nm.strip_edges() if nm.strip_edges() != "" else doc.plan.name
	session.path = ""
	return save()

func export_copy(nm: String) -> Dictionary:
	var f := "user://cartes/export_%s.eclats-carte.json" % MapSession.clean_name(nm if nm != "" else doc.plan.name)
	var was := doc.saved_serial
	var r := IslandPlan.save_file(doc.plan, f)
	doc.saved_serial = was      # une copie exportée n'est pas l'enregistrement de la carte
	toast.emit("Exportée : %s" % ProjectSettings.globalize_path(f) if bool(r["ok"]) else "Export impossible : %s" % String(r["error"]), "ok" if bool(r["ok"]) else "error")
	return r

## Ouvre une autre carte (le dialogue « modifications non enregistrées » est posé par l'appelant via MapSession.ask).
func open_map(path: String) -> void:
	var d := MapDoc.new()
	var r := d.open_from(path)
	if not bool(r["ok"]):
		toast.emit("Ouverture impossible : %s La carte actuelle est conservée." % String(r["error"]), "error")
		return
	session = MapSession.begin(d, path)
	doc = d
	selected = ""
	await _make_world()
	_start_view()
	ready_to_edit = true
	toast.emit("Carte ouverte : %s" % d.plan.name, "ok")
	changed.emit()

func new_map(mode_name: String, params := {}) -> void:
	var d: MapDoc
	if mode_name == "graine":
		d = MapDoc.from_plan(PlanGenerator.generate(int(params.get("seed", 7)), float(params.get("width", 56.0)), float(params.get("length", 48.0))))
		d.plan.name = "Île %d" % int(params.get("seed", 7))
	else:
		d = _empty_doc()
	session = MapSession.begin(d, "")
	doc = d
	selected = ""
	await _make_world()
	_start_view()
	ready_to_edit = true
	toast.emit("Nouvelle carte : %s" % d.plan.name, "ok")
	changed.emit()

## Atelier : construction en première personne (laboratoire, île à pente). La session suit : au retour, la carte est telle qu'on l'a laissée.
func open_workshop() -> void:
	App.open(App.LAB_ROOM_SCENE, {"atelier": true, "session": session})

func open_map_2d() -> void:
	App.open(App.MAP_EDITOR_SCENE, {"session": session})

func play_map_3d() -> void:
	App.open(App.MAP_ISLAND_SCENE, {"session": session, "plan": doc.plan})

# ------------------------------------------------------------------ superpositions (pinceau, repères)

func _draw_ring(im: ImmediateMesh, c: Vector3, r: float, col: Color, n := 48) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		var x := c.x + cos(a) * r
		var z := c.z + sin(a) * r
		var g := doc.field.ground_at_m(x, z)
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(x, (c.y if is_nan(g) else g) + 0.12, z))
	im.surface_end()

func _refresh_overlay(p2 := Vector2.INF) -> void:
	if _ring == null or not is_instance_valid(_ring) or doc.field == null:
		return
	var im := _ring.mesh as ImmediateMesh
	im.clear_surfaces()
	var mm := _marks.mesh as ImmediateMesh
	mm.clear_surfaces()
	for h in _handles.get_children():
		h.queue_free()
	if mode == "play":
		return
	if p2 == Vector2.INF:
		var a := aim()
		p2 = Vector2(a.x, a.z) if a != Vector3.INF else Vector2.INF
	var show_ring := tool in ["terrain", "material"] or (tool == "map" and map_sub in ["zone", "protege"]) or tool == "generate"
	if show_ring and p2 != Vector2.INF:
		var g := doc.field.ground_at_m(p2.x, p2.y)
		var c := Vector3(p2.x, 0.0 if is_nan(g) else g, p2.y)
		var rad := float(brush["radius"])
		var col := Color(1, 0.9, 0.3)
		if tool == "generate":
			rad = float(gen["radius"])
			col = Color(0.5, 1.0, 0.6)
		elif tool == "map" and map_sub == "protege":
			col = Color(1.0, 0.3, 0.3)
		_draw_ring(im, c, rad, col)
		_draw_ring(im, c, rad * 0.5, Color(col.r, col.g, col.b, 0.5), 32)
	# sélection : cadre autour de l'objet ou de la maison
	if selected != "":
		_draw_selection(mm)
	if tool == "map":
		_draw_map_marks(mm)
	if tool in ["generate", "select"]:
		_draw_locks(mm)
	_draw_mask()

## Colonnes protégées (masque) : carrés rouges translucides sur le sol, visibles avec les outils qui en tiennent compte.
func _draw_mask() -> void:
	var im := _mask.mesh as ImmediateMesh
	im.clear_surfaces()
	if doc.plan.layers == null or not (tool in ["generate", "terrain", "material", "map", "select"]):
		return
	var L := doc.plan.layers
	var f := doc.field
	var n := f.n
	var any := false
	var count := 0
	for i in n * n:
		if L.mask[i] != 0 and f.top[i] != TerrainField.NO_GROUND:
			if not any:
				im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				any = true
			var cx := i % n
			var cz := i / n
			var x0 := float(cx + f.origin.x) * V
			var z0 := float(cz + f.origin.y) * V
			var y := float(f.top[i] + 1) * V + 0.06
			var col := Color(1.0, 0.18, 0.18, 0.42)
			for q in [Vector3(x0, y, z0), Vector3(x0 + V, y, z0), Vector3(x0 + V, y, z0 + V), Vector3(x0, y, z0), Vector3(x0 + V, y, z0 + V), Vector3(x0, y, z0 + V)]:
				im.surface_set_color(col)
				im.surface_add_vertex(q)
			count += 1
			if count > 9000:
				break
	if any:
		im.surface_end()

func _draw_box(mm: ImmediateMesh, xf: Transform3D, box: AABB, col: Color) -> void:
	var c: Array[Vector3] = []
	for i in 8:
		c.append(xf * (box.position + Vector3(box.size.x * float(i & 1), box.size.y * float((i >> 1) & 1), box.size.z * float((i >> 2) & 1))))
	var edges := [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	mm.surface_begin(Mesh.PRIMITIVE_LINES)
	for e in edges:
		mm.surface_set_color(col)
		mm.surface_add_vertex(c[e[0]])
		mm.surface_set_color(col)
		mm.surface_add_vertex(c[e[1]])
	mm.surface_end()

func _draw_selection(mm: ImmediateMesh) -> void:
	if selected.begins_with("h:"):
		for h in doc.plan.houses:
			if String(h["id"]) == selected.substr(2):
				var r: Rect2 = h["rect"]
				var g := float(h["ground_m"])
				_draw_box(mm, Transform3D.IDENTITY, AABB(Vector3(r.position.x, g, r.position.y), Vector3(r.size.x, 4.0, r.size.y)), Color(0.4, 0.9, 1.0))
		return
	var o := doc.object_by_id(selected)
	if o.is_empty():
		return
	var xf := CreativeObjects.transform_for(o, doc.field)
	if _grab:
		var tmp: Dictionary = o.duplicate()
		var a2 := aim2()
		if a2 != Vector2.INF:
			tmp["pos"] = snap_point(a2)
			xf = CreativeObjects.transform_for(tmp, doc.field)
	_draw_box(mm, xf, CreativeObjects.local_box(String(o["ref"])), Color(1.0, 0.8, 0.2) if not bool(o["locked"]) else Color(1.0, 0.35, 0.35))

func _draw_locks(mm: ImmediateMesh) -> void:
	for o in doc.plan.objects:
		if bool(o["locked"]):
			var p: Vector2 = o["pos"]
			var g := doc.field.ground_at_m(p.x, p.y)
			if is_nan(g):
				continue
			var h := CreativeObjects.footprint(String(o["ref"])).y * float(o.get("scale", 1.0)) + 0.4
			mm.surface_begin(Mesh.PRIMITIVE_LINES)
			mm.surface_set_color(Color(1, 0.3, 0.3))
			mm.surface_add_vertex(Vector3(p.x, g + h, p.y))
			mm.surface_set_color(Color(1, 0.3, 0.3))
			mm.surface_add_vertex(Vector3(p.x, g + h + 0.7, p.y))
			mm.surface_end()

func _draw_map_marks(mm: ImmediateMesh) -> void:
	# zones : cercles colorés ; chemins : tracé + poignées ; repères ; contour
	for z in doc.plan.zones:
		var col: Color = IslandPlan.KINDS[String(z["kind"])]["color"]
		var c := Vector3((z["c"] as Vector2).x, 0.0, (z["c"] as Vector2).y)
		var g := doc.field.ground_at_m(c.x, c.z)
		c.y = 0.0 if is_nan(g) else g
		_draw_ring(mm, c, float(z["r"]), Color(col.r, col.g, col.b, 0.85), 40)
	if doc.plan.outline.size() >= 3:
		var o := doc.plan.outline
		mm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for k in o.size() + 1:
			var q: Vector2 = o[k % o.size()]
			var g2 := doc.field.ground_at_m(q.x, q.y)
			mm.surface_set_color(Color(1, 1, 1))
			mm.surface_add_vertex(Vector3(q.x, (2.0 if is_nan(g2) else g2) + 0.3, q.y))
		mm.surface_end()
		if map_sub == "contour":
			for q: Vector2 in o:
				_handle(q, Color(1, 1, 1), 0.35)
	for pa in doc.plan.paths:
		var pts: Array = pa["pts"]
		mm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for q: Vector2 in pts:
			var g3 := doc.field.ground_at_m(q.x, q.y)
			mm.surface_set_color(Color(1.0, 0.85, 0.3))
			mm.surface_add_vertex(Vector3(q.x, (2.0 if is_nan(g3) else g3) + 0.35, q.y))
		mm.surface_end()
		if map_sub == "chemin":
			for q: Vector2 in pts:
				_handle(q, Color(1.0, 0.85, 0.3), 0.3)
	if not path_pts.is_empty():
		mm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for q: Vector2 in path_pts:
			var g4 := doc.field.ground_at_m(q.x, q.y)
			mm.surface_set_color(Color(0.5, 1, 0.6))
			mm.surface_add_vertex(Vector3(q.x, (2.0 if is_nan(g4) else g4) + 0.4, q.y))
		var a2 := aim2()
		if a2 != Vector2.INF:
			var g5 := doc.field.ground_at_m(a2.x, a2.y)
			mm.surface_set_color(Color(0.5, 1, 0.6, 0.5))
			mm.surface_add_vertex(Vector3(a2.x, (2.0 if is_nan(g5) else g5) + 0.4, a2.y))
		mm.surface_end()
		for q: Vector2 in path_pts:
			_handle(q, Color(0.5, 1, 0.6), 0.3)
	for l in doc.plan.landmarks:
		var lp: Vector2 = l["pos"]
		_handle(lp, IslandPlan.LANDMARK_KINDS[String(l["kind"])]["color"], 0.45)
	_handle(doc.plan.start, Color(0.3, 1.0, 0.4), 0.5)

func _handle(p: Vector2, col: Color, r: float) -> void:
	var g := doc.field.ground_at_m(p.x, p.y)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	mi.material_override = m
	mi.position = Vector3(p.x, (2.0 if is_nan(g) else g) + 0.45, p.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_handles.add_child(mi)

# ------------------------------------------------------------------ entrées

func _unhandled_input(event: InputEvent) -> void:
	if not ready_to_edit or App.paused_menu:
		return
	if event is InputEventMouseMotion and captured and mode == "fp":
		var mm := event as InputEventMouseMotion
		f_yaw -= mm.relative.x * 0.0028
		f_pitch = clampf(f_pitch - mm.relative.y * 0.0028, -1.5, 1.5)
		return
	if mode == "play":
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_P and not (event as InputEventKey).echo:
			set_mode(_before_play)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if _key(event as InputEventKey):
			get_viewport().set_input_as_handled()

func _mouse_button(e: InputEventMouseButton) -> void:
	if mode == "aerial":
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			a_dist = clampf(a_dist * 0.9, 6.0, 300.0)
			return
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			a_dist = clampf(a_dist * 1.1, 6.0, 300.0)
			return
	if e.button_index == MOUSE_BUTTON_MIDDLE and mode == "aerial":
		return
	if e.button_index == MOUSE_BUTTON_LEFT:
		if mode == "fp" and not captured and not ui.mouse_over_ui():
			_set_capture(true)
			return
		if e.pressed:
			_left_down(e.double_click)
		else:
			_left_up()
	elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		_right_down()

func _left_down(dbl := false) -> void:
	match tool:
		"select":
			if selected != "" and not selected.begins_with("h:"):
				var r := pick_ray()
				if pick_thing(r["o"], r["d"]) == selected:
					begin_grab()
					return
			select_at_cursor()
		"place":
			place_here()
		"terrain", "material":
			begin_stroke(false)
		"map":
			var p := aim2()
			if p == Vector2.INF:
				return
			match map_sub:
				"zone": begin_zone(false)
				"protege": begin_stroke(false)
				"chemin":
					if dbl:
						insert_point_at(p)
					else:
						path_click(p)
				"contour":
					if dbl:
						insert_point_at(p)
					else:
						path_click(p)
				"repere": place_landmark(p, "vue")
		"generate":
			generate_here()

func _left_up() -> void:
	match tool:
		"select":
			if _grab:
				end_grab(true)
		"terrain", "material":
			end_stroke()
		"map":
			end_zone()
			end_stroke()
			end_drag()

func _right_down() -> void:
	match tool:
		"select":
			if _grab:
				end_grab(false)
			else:
				selected = ""
				changed.emit()
		"place":
			_clear_ghost()
			inv_item = {}
			house_model = null
			set_tool("select")
		"material":
			begin_stroke(true)
		"map":
			var p := aim2()
			match map_sub:
				"zone":
					begin_zone(true)
				"protege":
					begin_stroke(true)
				"chemin", "contour":
					if not path_pts.is_empty():
						finish_path()
					elif p != Vector2.INF:
						remove_handle_at(p)
		_:
			pass

func _key(k: InputEventKey) -> bool:
	if ui.typing():
		return false
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if ctrl:
		match k.keycode:
			KEY_Z:
				if k.shift_pressed:
					redo()
				else:
					undo()
				return true
			KEY_Y:
				redo()
				return true
			KEY_S:
				if session.path == "":
					ui.show_file_dialog("save")
				else:
					save()
				return true
			KEY_O:
				ui.show_file_dialog("open")
				return true
			KEY_D:
				duplicate_selected()
				return true
		return false
	match k.keycode:
		KEY_V:
			toggle_view()
		KEY_P:
			set_mode("play")
		KEY_I:
			ui.toggle_inventory()
		KEY_TAB:
			if mode == "fp":
				_set_capture(not captured)
		KEY_F:
			if mode == "fp":
				f_walk = not f_walk
				toast.emit("Marche au sol" if f_walk else "Vol libre (Espace monter, C descendre)", "info")
				changed.emit()
		KEY_1: set_tool("select")
		KEY_2: set_tool("place")
		KEY_3: set_tool("terrain")
		KEY_4: set_tool("material")
		KEY_5: set_tool("map")
		KEY_6: set_tool("generate")
		KEY_7: open_workshop()
		KEY_R:
			rotate_pending(-1 if k.shift_pressed else 1)
		KEY_L:
			toggle_lock()
		KEY_G:
			if tool == "select":
				begin_grab()
			elif tool == "generate":
				regenerate_last()
		KEY_N:
			grid_snap = not grid_snap
			toast.emit("Aimantation à la grille 0,5 m : %s" % ("activée" if grid_snap else "désactivée"), "info")
			changed.emit()
		KEY_K:
			house_link = not house_link
			toast.emit("Raccord au chemin : %s" % ("oui" if house_link else "non"), "info")
		KEY_DELETE, KEY_BACKSPACE, KEY_X:
			delete_selected()
		KEY_ENTER, KEY_KP_ENTER:
			if tool == "map":
				finish_path()
		KEY_ESCAPE:
			if not path_pts.is_empty():
				path_pts.clear()
				changed.emit()
				return true
			if _grab:
				end_grab(false)
				return true
			if tool == "place" and not inv_item.is_empty():
				_clear_ghost()
				inv_item = {}
				house_model = null
				set_tool("select")
				return true
			return false
		KEY_BRACKETLEFT:
			brush["radius"] = clampf(float(brush["radius"]) - 0.5, 0.5, 9.0)
			gen["radius"] = clampf(float(gen["radius"]) - 0.5, 2.0, 20.0)
			changed.emit()
		KEY_BRACKETRIGHT:
			brush["radius"] = clampf(float(brush["radius"]) + 0.5, 0.5, 9.0)
			gen["radius"] = clampf(float(gen["radius"]) + 0.5, 2.0, 20.0)
			changed.emit()
		KEY_MINUS, KEY_KP_SUBTRACT:
			brush["strength"] = clampf(float(brush["strength"]) - 0.1, 0.1, 1.0)
			scale_pending(0.9)
		KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
			brush["strength"] = clampf(float(brush["strength"]) + 0.1, 0.1, 1.0)
			scale_pending(1.1)
		_:
			return false
	return true

func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
