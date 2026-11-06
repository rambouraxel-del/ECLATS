extends Node3D
## Île générée du Lot 4 : le monde est produit par WorldBuilder (terrain hiérarchique, colonie, nature,
## port, bateau), validé par WorldValidator puis mis en scène par WorldView ; l'ambiance est pilotée par
## EnvironmentManager. La génération tourne dans un fil d'exécution : la scène reste vivante pendant le calcul.
##
## Touches : 1-9, 0 vues · F5 jour · F6 coucher · F7 nuit · Y cycle jour/nuit · N / B île suivante / précédente
##           G profil suivant · R régénérer · V rapport de validation · T textures on/off

const PROFILES := ["settled", "verdant", "rocky"]

@export var profile := "settled"
@export var world_seed := 3

var world: WorldData
var env: EnvironmentManager
var cam: FreeCamera
var nodes: Node3D
var _label: Label
var _loading: Label
var _thread: Thread
var _building := false
var _tex_on := true
var _result: WorldData
var _validation := {}

func _ready() -> void:
	env = $Environment
	cam = $FreeCamera
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(14, 840)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_label)
	_loading = Label.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_theme_font_size_override("font_size", 28)
	_loading.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_loading.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_loading.add_theme_constant_override("shadow_offset_x", 2)
	_loading.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_loading)
	if not Engine.is_editor_hint():
		if App.launch.has("profile"):
			profile = String(App.launch["profile"])
			world_seed = int(App.launch.get("seed", world_seed))
		App.set_tech_default(true)
		App.set_scene_help("Île générée · vues 1-9,0 · F5 jour · F6 coucher · F7 nuit · Y cycle · N/B île · G profil · R régénérer · V validation")
		_generate()

func _exit_tree() -> void:
	# retour au menu pendant la génération : le fil est joint plus tard, sans bloquer
	if _thread != null and _thread.is_started():
		App.adopt_thread(_thread)

func _generate() -> void:
	if _building:
		return
	_building = true
	_label.text = "Génération de l'île « %s » (graine %d)…" % [profile, world_seed]
	_loading.text = "Génération de l'île « %s » (graine %d)…" % [profile, world_seed]
	_loading.visible = true
	var p := profile
	var s := world_seed
	_thread = Thread.new()
	_thread.start(func() -> void:
		_result = WorldBuilder.build(p, s)
		call_deferred("_on_built"))

func _on_built() -> void:
	if not is_inside_tree():
		return
	_thread.wait_to_finish()
	world = _result
	_validation = WorldValidator.validate(world, {"buildings": false})
	if nodes != null:
		nodes.queue_free()
	nodes = Node3D.new()
	nodes.name = "Generated"
	add_child(nodes)
	_loading.visible = false
	var t0 := Time.get_ticks_msec()
	WorldView.create(world, nodes)
	env.setup(world.seed)
	_building = false
	var errs: int = _validation["summary"]["errors"]
	_label.text = "Île « %s » #%d · %d bâtiments · %d arbres · %d rochers · génération %.1f s · validation %s" % [
		world.profile.key, world.seed, world.buildings.size(), world.trees.size(), world.rocks.size(),
		float(_sum_timings()) / 1000.0, "OK" if errs == 0 else "%d erreur(s) (V)" % errs]
	print("[monde] mise en scène %d ms · %s" % [Time.get_ticks_msec() - t0, world.timings])
	_go_view(1)

func _sum_timings() -> int:
	var t := 0
	for k in ["terrain", "colonie", "nature", "voxelisation", "modeles"]:
		t += int(world.timings.get(k, 0))
	return t

# ------------------------------------------------------------------ vues

func _view(n: int) -> Array:
	if world == null:
		return []
	var s := world.settlement
	var f := world.field
	var pc: Vector2 = s.plaza["center"] if not s.plaza.is_empty() else Vector2.ZERO
	var pl_y := float(f.ground_y_m(s.plaza["col"].x, s.plaza["col"].y)) if not s.plaza.is_empty() else 3.0
	match n:
		1: return [Vector3(pc.x + 8, 38, pc.y + 54), Vector3(pc.x, 2, pc.y)]
		2: return [Vector3(pc.x - 13, pl_y + 9, pc.y + 17), Vector3(pc.x + 1, pl_y + 1.5, pc.y - 2)]
		3:
			if not world.buildings.is_empty():
				var b: Dictionary = world.buildings[0]
				var d: Vector2 = b["door"]
				var dir := (pc - d).normalized()
				return [Vector3(d.x - dir.x, f.ground_at_m(d.x, d.y) + 1.65, d.y - dir.y), Vector3(pc.x, pl_y + 1.4, pc.y)]
		4:
			if not s.shrine.is_empty():
				var sc: Vector2 = s.shrine["center"]
				var dv := (sc - pc).normalized()
				return [Vector3(sc.x - dv.x * 11, pl_y + 2.5, sc.y - dv.y * 11), Vector3(sc.x, f.ground_at_m(sc.x, sc.y) + 1.8, sc.y)]
		5:
			if not world.port.is_empty():
				var rim: Vector2 = world.port["rim"]
				var axis: Vector2 = world.port["axis"]
				var perp: Vector2 = world.port["perp"]
				var side: float = world.port["ship_side"]
				var c2 := rim + axis * 6.0
				var dp: float = float(world.port["deck_top"])
				return [Vector3(c2.x + perp.x * side * 12 - axis.x * 5, dp + 4.2, c2.y + perp.y * side * 12 - axis.y * 5), Vector3(c2.x, dp + 0.5, c2.y)]
		6:
			if not world.buildings.is_empty():
				var b: Dictionary = world.buildings[0]
				var plan: BuildingPlan = b["plan"]
				var xf: Transform3D = b["xform"]
				var o: BuildingPlan.Opening = plan.openings[plan.main_door]
				var cx := (float(o.u) + float(o.w) * 0.5) * 0.1
				var fy := float(plan.floor_y(0)) * 0.1
				return [xf * Vector3(cx, fy + 1.55, (float(o.p) + 3.0) * 0.1), xf * Vector3(cx - 0.2, fy + 1.0, (float(o.p) - 25.0) * 0.1)]
		7:
			if not world.trees.is_empty():
				var tp: Vector3 = world.trees[0]["pos"]
				return [tp + Vector3(7, 3, 7.5), tp + Vector3(0, 2.2, 0)]
		8:
			if not world.rocks.is_empty():
				var rp: Vector3 = _showcase_rock()
				return [rp + Vector3(6, 2.4, 6.5), rp + Vector3(0, 1.3, 0)]
		9: return [Vector3(pc.x + 90, 40, pc.y + 150), Vector3(pc.x, 0, pc.y)]
		0: return [Vector3(pc.x - 40, 12, pc.y - 40), Vector3(pc.x, 2, pc.y)]
	return [Vector3(0, 30, 50), Vector3(0, 2, 0)]

## Vue prédéfinie sans village : centre et point haut de l'île (les vues colonie / port / sanctuaire n'existent pas).
func _view_natural(n: int) -> Array:
	var f := world.field
	var hi := 0
	for i in f.n * f.n:
		if f.top[i] > f.top[hi]:
			hi = i
	var hm := f.center_m(hi % f.n, hi / f.n)
	var hy := float(f.top[hi] + 1) * VoxelGrid.VOXEL_SIZE
	match n:
		1: return [Vector3(10, 36, 48), Vector3(0, 1, 0)]
		2, 4: return [Vector3(hm.x - 8.0, hy + 5.0, hm.y + 9.0), Vector3(hm.x, hy, hm.y)]
		7:
			if not world.trees.is_empty():
				var tp: Vector3 = world.trees[0]["pos"]
				return [tp + Vector3(10, 5.5, 11), tp + Vector3(0, 1.8, 0)]
		8:
			if not world.rocks.is_empty():
				var rp: Vector3 = _showcase_rock()
				return [rp + Vector3(7, 4.0, 7.5), rp + Vector3(0, 1.0, 0)]
		9: return [Vector3(90, 40, 150), Vector3(0, 0, 0)]
		0: return [Vector3(-40, 12, -40), Vector3(0, 2, 0)]
	return [Vector3(0, 30, 50), Vector3(0, 2, 0)]

## Repousse une caméra qui démarre DANS un feuillage (couronne d'arbre) : elle recule vers l'extérieur et monte
## jusqu'à être dégagée (8 essais de 1,5 m).
func _clear_of_foliage(from: Vector3, to: Vector3) -> Vector3:
	var p := from
	var away := Vector3(from.x - to.x, 0.0, from.z - to.z).normalized()
	for k in 8:
		var inside := false
		for t in world.trees:
			var cr: AABB = t["plan"]["crown"]
			if cr.size.x <= 0.0:
				continue
			var tp: Vector3 = t["pos"]
			var box := AABB(tp + cr.position, cr.size).grow(0.5)
			if box.has_point(p):
				inside = true
				break
		if not inside:
			break
		p += away * 1.5 + Vector3(0, 1.0, 0)
	return p

## Rocher mis en avant par la vue 8 : le plus massif parmi ceux qu'aucune couronne d'arbre ne recouvre (à 2 m près).
func _showcase_rock() -> Vector3:
	var best := 0
	var best_score := -1.0e9
	for i in world.rocks.size():
		var r: Dictionary = world.rocks[i]
		var sz: Vector3 = r["plan"]["size"]
		var rp: Vector3 = r["pos"]
		var score := sz.x * sz.y * sz.z
		if _in_crown(rp + Vector3(0, sz.y * 0.5, 0), 2.0):
			score -= 1000.0
		if score > best_score:
			best_score = score
			best = i
	return world.rocks[best]["pos"]

func _in_crown(p: Vector3, margin: float) -> bool:
	for t in world.trees:
		var cr: AABB = t["plan"]["crown"]
		if cr.size.x <= 0.0:
			continue
		var tp: Vector3 = t["pos"]
		if AABB(tp + cr.position, cr.size).grow(margin).has_point(p):
			return true
	return false

func _segment_hits_crown(a: Vector3, b: Vector3) -> bool:
	for t in world.trees:
		var cr: AABB = t["plan"]["crown"]
		if cr.size.x <= 0.0:
			continue
		var tp: Vector3 = t["pos"]
		if AABB(tp + cr.position, cr.size).grow(-0.4).intersects_segment(a, b) != null:
			return true
		var tr: float = float(t["plan"].get("trunk_r", 0.3)) + 0.4          # le tronc masque aussi le sujet
		if AABB(tp + Vector3(-tr, 0.0, -tr), Vector3(tr * 2.0, cr.position.y + cr.size.y * 0.5, tr * 2.0)).intersects_segment(a, b) != null:
			return true
	return false

## Emprises (bâtiments, rochers) à ne pas traverser avec la caméra : boîtes alignées sur les axes.
func _solid_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for group in [world.buildings, world.rocks]:
		for b in group:
			var res: PlacementResult = b["res"]
			var h := res.spec.half_extents(res.yaw)
			boxes.append(AABB(res.pos - Vector3(h.x, 0.0, h.y), Vector3(h.x * 2.0, maxf(res.spec.size.y, 1.0), h.y * 2.0)))
	return boxes

## Caméra dégagée : ni dans une couronne, ni derrière une couronne, ni sous le sol. Si le point de départ est masqué,
## on tourne autour du sujet (pas de 30°, trois distances) et on garde le premier cadrage libre.
func _clear_view(from: Vector3, to: Vector3) -> Vector3:
	var off := from - to
	var solids := _solid_boxes()
	for ring: float in [1.0, 1.3, 0.8]:
		for k in 12:
			var ang: float = deg_to_rad(float((k + 1) / 2) * 30.0 * (1.0 if k % 2 == 1 else -1.0)) if k > 0 else 0.0
			var o: Vector3 = Vector3(off.x, 0.0, off.z).rotated(Vector3.UP, ang) * ring + Vector3(0, off.y, 0)
			var p: Vector3 = to + o
			var g := world.field.ground_at_m(p.x, p.z)
			if not is_nan(g):
				p.y = maxf(p.y, g + 1.6)
			if _in_crown(p, 0.4) or _segment_hits_crown(p, to):
				continue
			var blocked := false
			for pr in world.props:           # auvents, étals, mobilier : la caméra ne se pose pas dessus (hors voisinage du sujet)
				var po: Vector3 = (pr["xform"] as Transform3D).origin
				if Vector2(po.x - to.x, po.z - to.z).length() > 6.0 and Vector2(po.x - p.x, po.z - p.z).length() < 1.8 and p.y < po.y + 3.2:
					blocked = true
					break
			if blocked:
				continue
			for bx in solids:
				if bx.grow(0.5).has_point(to):
					continue            # le sujet lui-même
				if bx.grow(1.6).has_point(p) or bx.grow(-0.2).intersects_segment(p, to) != null:
					blocked = true
					break
			if blocked:
				continue
			return p
	return _clear_of_foliage(from, to)

func _go_view(n: int) -> void:
	var v := _view(n) if (world != null and not world.settlement.plaza.is_empty()) else (_view_natural(n) if world != null else [])
	if cam and not v.is_empty():
		cam.look_from((_clear_view(v[0], v[1]) if (n == 4 or n == 8) else _clear_of_foliage(v[0], v[1])) if world != null else v[0], v[1])

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if Engine.is_editor_hint() or key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_0 and key.keycode <= KEY_9:
		_go_view(key.keycode - KEY_0)
	elif key.keycode == KEY_F5:
		env.transition_to("village_day", 2.5)
	elif key.keycode == KEY_F6:
		env.transition_to("village_sunset", 2.5)
	elif key.keycode == KEY_F7:
		env.transition_to("village_night", 2.5)
	elif key.keycode == KEY_Y:
		env.cycle_speed = 0.0 if env.cycle_speed > 0.0 else 1.0 / 60.0
	elif key.keycode == KEY_N:
		world_seed += 1
		_generate()
	elif key.keycode == KEY_B:
		world_seed = maxi(world_seed - 1, 1)
		_generate()
	elif key.keycode == KEY_G:
		profile = PROFILES[(PROFILES.find(profile) + 1) % PROFILES.size()]
		_generate()
	elif key.keycode == KEY_R:
		_generate()
	elif key.keycode == KEY_V and world != null:
		var full := WorldValidator.validate(world)
		for i in full["issues"]:
			print("[validation] [%s] %s : %s" % [i["severity"], i["check"], i["message"]])
		print("[validation] %s" % full["summary"])
		_label.text = "Validation : %d erreur(s), %d avertissement(s) (détails dans la console)" % [full["summary"]["errors"], full["summary"]["warnings"]]
	elif key.keycode == KEY_T:
		_tex_on = not _tex_on
		VoxelMaterials.set_global_param("tex_strength", 1.0 if _tex_on else 0.0)
