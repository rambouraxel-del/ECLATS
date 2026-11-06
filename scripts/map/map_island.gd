class_name MapIsland
extends Node3D
## Île 3D construite à partir d'un PLAN (Lot 7) : terrain, matières et chemins viennent du plan ; première personne
## (point de départ sûr), repères à rejoindre, vue aérienne (F5) orientée comme le plan 2D (nord en haut).
## Lancement : App.open(App.MAP_ISLAND_SCENE, {"plan": IslandPlan}) — ou {"seed", "width", "length"} pour générer le plan.
## Si la scène vient de l'éditeur ({"from_editor": true}), F6 y retourne.

var plan: IslandPlan
var build: PlanTerrain.Build
var lab: LabWorld
var explorer: Explorer
var camrig: ThirdPersonCamera
var aerial_cam: Camera3D
var env: EnvironmentManager
var ready_to_play := false
var aerial := false
var load_ms := 0
var falls := 0
var trees_planted := 0
var house_nodes: Array[Node3D] = []
var reached: Array[String] = []
var target_index := 0
var _hud: CanvasLayer
var _loading: Label
var _title: Label
var _goal: Label
var _hint: Label
var _toast: Label
var _toast_t := 0.0
var _reticle: Control
var _aerial_h := 0.0
var _plant_trees := true
var session: MapSession = null        # session d'édition d'où l'on vient (retour par F6 sans rien perdre)
var reused_field := false              # vrai : le relief de l'éditeur est réutilisé (pas recalculé)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	GameInput.ensure()
	App.current_path = App.MAP_ISLAND_SCENE
	App.set_tech_default(false)
	App.capture_on_resume = true
	App.set_scene_help("Île issue d'un plan · F5 vue aérienne · V changer de vue")
	env = get_node_or_null("Environment") as EnvironmentManager
	var launch: Dictionary = App.launch
	if launch.has("session"):
		session = launch["session"] as MapSession
		MapSession.current = session
	if launch.has("plan"):
		plan = launch["plan"] as IslandPlan
	elif launch.has("seed"):
		plan = PlanGenerator.generate(int(launch["seed"]), float(launch.get("width", 56.0)), float(launch.get("length", 48.0)))
	else:
		plan = PlanGenerator.generate(7, 56.0, 48.0)
	_plant_trees = bool(launch.get("trees", true))
	_hud = CanvasLayer.new()
	_hud.layer = 20
	add_child(_hud)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.name = "Fond"
	_hud.add_child(bg)
	_loading = Label.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_theme_font_size_override("font_size", 28)
	_loading.add_theme_color_override("font_color", Color(1, 1, 1))
	_loading.text = "Construction de l'île depuis le plan…\n%s" % plan.name
	_hud.add_child(_loading)
	await get_tree().process_frame
	await get_tree().process_frame
	await _build()

## Relief de la scène. Venant de l'éditeur, le relief déjà calculé du document est réutilisé (copie indépendante) si le plan n'a pas
## changé depuis ; sinon il est calculé dans un fil de calcul, l'écran de chargement restant animé.
func _make_terrain() -> void:
	var doc: MapDoc = session.doc if session != null else null
	if doc != null and doc.build != null and doc.field != null and doc.plan == plan and doc.build.plan_sig == plan.signature():
		build = doc.build.with_field(doc.field.duplicate_field())
		reused_field = true
		return
	var task := WorkerThreadPool.add_task(func() -> void:
		var b := PlanTerrain.build(plan)
		PlanTerrain.apply_layers(b, plan)
		_built = b, false, "Relief du plan")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	build = _built

var _built: PlanTerrain.Build = null

func _build() -> void:
	var t0 := Time.get_ticks_msec()
	await _make_terrain()
	lab = LabWorld.new()
	lab.name = "Lab"
	add_child(lab)
	lab.setup_field(build.field, "plan", plan.seed, plan.start)
	_spawn_houses()
	if env != null:
		env.setup(plan.seed)
	explorer = Explorer.new()
	explorer.name = "Explorer"
	add_child(explorer)
	explorer.kill_y = _lowest() - 25.0
	explorer.fell.connect(_on_fell)
	var yaw := _start_yaw()
	explorer.teleport(lab.spawn, yaw)
	camrig = ThirdPersonCamera.new()
	camrig.name = "CameraRig"
	camrig.target = explorer
	add_child(camrig)
	camrig.yaw = yaw
	camrig.pitch = -0.08
	camrig.arm.add_excluded_object(explorer.get_rid())
	camrig.first_person = true
	camrig.snap()
	_make_aerial()
	_make_hud()
	_hud.get_node("Fond").queue_free()
	_loading.queue_free()
	if _plant_trees:
		await _plant()
	_next_target()
	load_ms = Time.get_ticks_msec() - t0
	ready_to_play = true
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[île du plan] prête en %d ms (terrain %d ms, %d arbres)" % [load_ms, build.ms, trees_planted])

## Maisons posées dans l'éditeur : modèle intégré à la carte → construction visitable (collisions réelles, ouvertures découpées).
func _spawn_houses() -> void:
	for h in plan.houses:
		var r := Construction.from_dict(h["model"])
		if not bool(r["ok"]):
			push_warning("Maison illisible : %s" % String(r["error"]))
			continue
		var model: Construction = r["construction"]
		var node := ConstructionView.create(model, {"collide": true})
		node.name = "Maison_%s" % String(h["id"])
		node.transform = HousePad.node_transform(model, h["pos"], int(h["yaw"]), float(h["ground_m"]))
		lab.add_child(node)
		house_nodes.append(node)
		# réserve l'emprise : les arbres du décor ne poussent pas dans la maison
		var rm: Rect2 = h["rect"]
		var c0 := lab.field.col_of_m(rm.position.x - 0.6, rm.position.y - 0.6)
		var c1 := lab.field.col_of_m(rm.end.x + 0.6, rm.end.y + 0.6)
		lab.occ.reserve(Rect2i(c0, c1 - c0 + Vector2i.ONE), PlacementSpec.TAG_PLOT, lab.occ.new_owner())

func _lowest() -> float:
	var lo := 1.0e9
	for t in build.field.top:
		if t != TerrainField.NO_GROUND:
			lo = minf(lo, float(t + 1) * 0.2)
	return lo

## Regarde vers le prochain repère (ou vers le centre de l'île).
func _start_yaw() -> float:
	var to := Vector2.ZERO
	var best := 1.0e9
	for l in plan.landmarks:
		var d: float = (l["pos"] as Vector2).distance_to(plan.start)
		if d > 3.0 and d < best:
			best = d
			to = l["pos"]
	var dir := to - plan.start
	if dir.length() < 0.1:
		return 0.0
	# yaw 0 = vers -z ; rotation positive = vers la gauche (-x)
	return atan2(-dir.x, -dir.y)

func _make_aerial() -> void:
	aerial_cam = Camera3D.new()
	aerial_cam.name = "VueAerienne"
	aerial_cam.fov = 46.0
	aerial_cam.near = 0.5
	aerial_cam.far = 3000.0
	add_child(aerial_cam)
	_aerial_h = maxf(plan.width, plan.length) * 1.05
	_place_aerial()

## Même orientation que le plan 2D : le nord (−z) est en haut de l'image. Inclinaison forte (≈ 70°).
func _place_aerial() -> void:
	var c := Vector2.ZERO
	if plan.outline.size() >= 3:
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p: Vector2 in plan.outline:
			lo = lo.min(p)
			hi = hi.max(p)
		c = (lo + hi) * 0.5
	var gy := 4.0
	var g := build.field.ground_at_m(c.x, c.y)
	if not is_nan(g):
		gy = g
	var pos := Vector3(c.x, gy + _aerial_h, c.y + _aerial_h * 0.36)
	aerial_cam.look_at_from_position(pos, Vector3(c.x, gy, c.y - 1.0), Vector3.UP)

func _label(size: int, col := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(l)
	return l

func _make_hud() -> void:
	_title = _label(17, Color(0.85, 0.93, 1.0))
	_title.position = Vector2(18, 12)
	_title.text = "%s · graine %d" % [plan.name, plan.seed]
	_goal = _label(24)
	_goal.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_goal.position = Vector2(0, 52)
	_goal.size = Vector2(1280, 36)
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.anchor_left = 0.0
	_goal.anchor_right = 1.0
	_goal.offset_left = 0
	_goal.offset_right = 0
	_hint = _label(16, Color(0.80, 0.88, 0.96))
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -40
	_hint.offset_bottom = -12
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = _label(26, Color(1, 0.92, 0.55))
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.offset_top = 150
	_toast.offset_bottom = 190
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(func() -> void:
		_reticle.draw_circle(Vector2.ZERO, 3.6, Color(0, 0, 0, 0.45))
		_reticle.draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 1, 0.9)))
	_hud.add_child(_reticle)
	_refresh_hint()

func _refresh_hint() -> void:
	var back := "  ·  F6 éditeur" if bool(App.launch.get("from_editor", false)) else ""
	if aerial:
		_hint.text = "Vue aérienne (nord en haut)  ·  molette : hauteur  ·  F5 : revenir au sol%s  ·  Échap : pause" % back
	else:
		_hint.text = "ZQSD / WASD marcher · Maj courir · Espace sauter · souris : regarder · F5 : vue aérienne · V : 3e personne%s · Échap : pause" % back

func _toast_msg(t: String) -> void:
	_toast.text = t
	_toast_t = 3.0

# ------------------------------------------------------------------ repères à rejoindre

func _next_target() -> void:
	while target_index < plan.landmarks.size():
		var l: Dictionary = plan.landmarks[target_index]
		if (l["pos"] as Vector2).distance_to(Vector2(explorer.global_position.x, explorer.global_position.z)) < 3.6:
			reached.append(String(l["id"]))
			target_index += 1
		else:
			break
	_update_goal()

func _update_goal() -> void:
	if target_index >= plan.landmarks.size():
		_goal.text = "Tous les repères ont été rejoints"
		return
	var l: Dictionary = plan.landmarks[target_index]
	var d := (l["pos"] as Vector2).distance_to(Vector2(explorer.global_position.x, explorer.global_position.z))
	_goal.text = "Repère : %s · %d m" % [l.get("label", l["id"]), roundi(d)]

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	explorer.cam_yaw = camrig.yaw
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.text = ""
	if target_index < plan.landmarks.size():
		var l: Dictionary = plan.landmarks[target_index]
		var d := (l["pos"] as Vector2).distance_to(Vector2(explorer.global_position.x, explorer.global_position.z))
		if d < 3.6:
			reached.append(String(l["id"]))
			_toast_msg("Repère atteint : %s" % l.get("label", l["id"]))
			target_index += 1
		_update_goal()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not ready_to_play:
		return
	if key.keycode == KEY_F5:
		set_aerial(not aerial)
	elif key.keycode == KEY_F6 and bool(App.launch.get("from_editor", false)):
		App.open(App.MAP_EDITOR_SCENE, {"plan": plan, "session": session, "from_island": true})

func _unhandled_input(event: InputEvent) -> void:
	if aerial and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_aerial_h = maxf(_aerial_h * 0.9, 12.0)
			_place_aerial()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_aerial_h = minf(_aerial_h * 1.1, 400.0)
			_place_aerial()

func set_aerial(on: bool) -> void:
	aerial = on
	explorer.control_enabled = not on
	if on:
		aerial_cam.current = true
		_reticle.visible = false
		if DisplayServer.get_name() != "headless":
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		explorer.model.visible = true
	else:
		camrig.cam.current = true
		_reticle.visible = camrig.first_person
		explorer.model.visible = not camrig.first_person
		if DisplayServer.get_name() != "headless":
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_refresh_hint()

func _on_fell() -> void:
	falls += 1
	explorer.teleport(lab.spawn, camrig.yaw)
	camrig.snap()
	_toast_msg("Retour au point de départ")

# ------------------------------------------------------------------ arbres de la zone boisée (décor déterministe)

func _plant() -> void:
	var rng := WorldRng.stream(plan.seed, "plan_trees")
	var species := ["oak", "pine", "birch", "parasol", "oak", "pine"]
	var placed: Array[Vector2] = []
	var budget := 18
	for z in plan.zones:
		if z["kind"] != "bois":
			continue
		var zr := float(z["r"])
		var want := clampi(roundi(PI * zr * zr / 22.0), 2, 9)
		var tries := want * 6
		var got := 0
		while tries > 0 and got < want and budget > 0:
			tries -= 1
			var q: Vector2 = (z["c"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * zr * 0.92
			if not IslandPlan.point_in_poly(q, plan.outline) or IslandPlan.dist_to_poly(q, plan.outline) < 3.0:
				continue
			if _near_path(q, 2.4):
				continue
			var spaced := true
			for o in placed:
				if o.distance_to(q) < 3.2:
					spaced = false
			if not spaced:
				continue
			var sp: String = species[rng.randi() % species.size()]
			var sd := int(rng.randi() % 100000)
			var op := lab.prepare_tree(q, sp, sd)
			if not bool(op["ok"]):
				continue
			var r: Dictionary = await lab.apply(op)
			if bool(r["ok"]):
				placed.append(q)
				got += 1
				budget -= 1
				trees_planted += 1
	lab.stack.clear()

func _near_path(q: Vector2, margin: float) -> bool:
	for pa in plan.paths:
		var pts: Array = pa["pts"]
		for k in range(pts.size() - 1):
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var ab := b - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
			if q.distance_to(a + ab * t) < float(pa["width"]) * 0.5 + margin:
				return true
	return false

## Place le joueur au sol en (x, z) (essais et captures).
func place_player(x: float, z: float, yaw: float, pitch := 0.0) -> void:
	var g := lab.ground_y(x, z)
	explorer.teleport(Vector3(x, (0.0 if is_nan(g) else g) + 0.05, z), yaw)
	camrig.yaw = yaw
	camrig.pitch = pitch
	camrig.snap()

func _exit_tree() -> void:
	pass
