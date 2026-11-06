extends Node3D
## Lot 5 — Île d'ouverture : île FIXE construite depuis config/islands/ile_ouverture.json (Lot 4 = bibliothèque),
## explorateur jouable à la troisième personne, objectif « Rejoindre le sanctuaire », activation de l'Ancre
## (pulsation cyan, anneau au sol, « Île découverte »), état sauvegardé sous l'identifiant fixe de l'île.
##
## Première ouverture : l'île est construite (≈ 1 à 2 min selon la machine) puis mise en CACHE dans
## user://cache/ (clé = carte + palette + version du constructeur) ; les ouvertures suivantes la rechargent en
## quelques secondes. Modifier la carte JSON invalide le cache automatiquement.
##
## Touches : ZQSD/WASD (selon le clavier) ou flèches · souris : caméra (clic pour capturer, Échap pour libérer)
##           Maj courir · Espace sauter · E activer · F5/F6/F7 ambiance · Ctrl+Suppr : oublier la sauvegarde de l'île

const MAP_PATH := "res://config/islands/ile_ouverture.json"
const CACHE_DIR := "user://cache"

var map: Dictionary
var world: WorldData            # null quand l'île vient du cache
var info := {}                  # données de jeu : départ, Ancre, intérieurs, seuil de chute, graine
var env: EnvironmentManager
var explorer: Explorer
var camrig: ThirdPersonCamera
var anchor_fx: AnchorFx
var nodes: Node3D
var island_id := ""
var anchor_active := false
var ready_to_play := false
var interiors: Array = []
var spawn_pos := Vector3.ZERO
var spawn_yaw := 0.0
var load_ms := 0
var from_cache := false
var falls := 0
var use_cache := true

var _thread: Thread
var _result: WorldData
var _t0 := 0
var _cache_path := ""
var _loading_cache := false
var _hud_layer: CanvasLayer
var _objective: Label
var _prompt: Label
var _banner: Label
var _loading: Label
var _banner_t := -1.0
var _toast: Label
var _toast_t := -1.0
var _in_range := false

func _ready() -> void:
	GameInput.ensure()
	env = $Environment
	_make_hud()
	map = IslandMap.load_map(MAP_PATH)
	island_id = String(map.get("id", "ile"))
	if Engine.is_editor_hint():
		return
	App.set_scene_help("Île d'ouverture · F5 jour · F6 coucher · F7 nuit · Ctrl+Suppr oublier la sauvegarde de l'île")
	App.set_controls_help(PackedStringArray([
		"%s bouger (ou flèches) · souris caméra · Maj courir · Espace sauter · %s activer" % [GameInput.move_keys_label(), GameInput.key_label("interact")],
		"Clic : capturer la souris · Échap : la libérer · molette : distance de la caméra",
	]))
	if OS.get_cmdline_user_args().has("--sans-cache"):
		use_cache = false
	_t0 = Time.get_ticks_msec()
	var sig := AuthoredIslandBuilder.signature(map)
	_cache_path = "%s/%s.scn" % [CACHE_DIR, sig]
	_loading.visible = true
	if use_cache and FileAccess.file_exists(_cache_path) and FileAccess.file_exists(_cache_path.replace(".scn", ".json")):
		_loading.text = "Chargement de l'île d'ouverture…"
		from_cache = true
		_loading_cache = true
		ResourceLoader.load_threaded_request(_cache_path, "PackedScene", true)
		return
	_start_build()

func _start_build() -> void:
	_loading.text = "Construction de l'île d'ouverture (première ouverture : une à deux minutes)…"
	_loading.visible = true
	var m := map
	_thread = Thread.new()
	_thread.start(func() -> void:
		_result = AuthoredIslandBuilder.build(m)
		call_deferred("_on_built"))

func _on_built() -> void:
	_thread.wait_to_finish()
	world = _result
	nodes = Node3D.new()
	nodes.name = "Generated"
	add_child(nodes)
	AuthoredIslandView.create(world, nodes)
	info = _info_from_world(world)
	print("[île d'ouverture] construite en %d ms · %s · %d événements" % [Time.get_ticks_msec() - _t0, world.timings, world.events.size()])
	for e in world.events:
		print("  · ", e)
	_start_game()
	if use_cache and DisplayServer.get_name() != "headless":
		_save_cache()

func _on_cache_loaded() -> void:
	var packed := ResourceLoader.load_threaded_get(_cache_path) as PackedScene
	if packed == null:
		push_warning("Cache illisible, reconstruction : %s" % _cache_path)
		from_cache = false
		DirAccess.remove_absolute(_cache_path)
		_start_build()
		return
	nodes = packed.instantiate() as Node3D
	add_child(nodes)
	AuthoredIslandView.strip_asset_collisions(nodes)
	# les groupes ne sont pas conservés dans le cache : les lampes rejoignent le groupe réglé par l'ambiance
	for l in nodes.find_children("*", "Light3D", true, false):
		if l.has_meta("interior"):
			l.add_to_group("asset_lamps")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_cache_path.replace(".scn", ".json")))
	info = _decode_info(parsed if typeof(parsed) == TYPE_DICTIONARY else {})
	print("[île d'ouverture] rechargée du cache en %d ms" % (Time.get_ticks_msec() - _t0))
	_start_game()

## Données de jeu (sérialisables) tirées de l'île construite.
func _info_from_world(w: WorldData) -> Dictionary:
	var lowest := 1.0e9
	for i in w.field.n * w.field.n:
		if w.field.top[i] != TerrainField.NO_GROUND:
			lowest = minf(lowest, float(w.field.top[i] + 1) * 0.2)
	return {"seed": w.seed, "spawn": w.authored["spawn"], "anchor": w.authored["anchor"], "interiors": w.authored["interiors"],
		"kill_y": lowest - 20.0, "events": w.events, "timings": w.timings}

static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _encode_info(d: Dictionary) -> Dictionary:
	var sp: Dictionary = d["spawn"]
	var an: Dictionary = d["anchor"]
	var ints: Array = []
	for it in d["interiors"]:
		var b: AABB = it["aabb"]
		var e: Dictionary = it.duplicate()
		e["aabb"] = [b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z]
		ints.append(e)
	var p: Vector3 = sp["pos"]
	var ap: Vector3 = an["pos"]
	var cr: Vector3 = an["crystal"]
	return {"seed": d["seed"], "kill_y": d["kill_y"], "spawn": {"pos": [p.x, p.y, p.z], "yaw_deg": sp["yaw_deg"]},
		"anchor": {"pos": [ap.x, ap.y, ap.z], "crystal": [cr.x, cr.y, cr.z], "platform_y": an["platform_y"], "radius_m": an["radius_m"]},
		"interiors": ints, "events": d.get("events", [])}

func _decode_info(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out["spawn"] = {"pos": _v3(d["spawn"]["pos"]), "yaw_deg": float(d["spawn"]["yaw_deg"])}
	out["anchor"] = {"pos": _v3(d["anchor"]["pos"]), "crystal": _v3(d["anchor"]["crystal"]), "platform_y": float(d["anchor"]["platform_y"]),
		"radius_m": float(d["anchor"]["radius_m"])}
	var ints: Array = []
	for it in d["interiors"]:
		var a: Array = it["aabb"]
		var e: Dictionary = it.duplicate()
		e["aabb"] = AABB(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]))
		ints.append(e)
	out["interiors"] = ints
	return out

func _set_owner_rec(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_set_owner_rec(c, owner_node)

func _save_cache() -> void:
	var t := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	# anciens caches de cette île (autre version de la carte) : supprimés
	var dir := DirAccess.open(CACHE_DIR)
	if dir:
		for f in dir.get_files():
			if f.begins_with(island_id + "_"):
				dir.remove(f)
	_set_owner_rec(nodes, nodes)
	var packed := PackedScene.new()
	if packed.pack(nodes) != OK:
		push_warning("Cache : mise en paquet impossible")
		return
	if ResourceSaver.save(packed, _cache_path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_warning("Cache : écriture impossible (%s)" % _cache_path)
		return
	var f := FileAccess.open(_cache_path.replace(".scn", ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_encode_info(info)))
	f.close()
	print("[île d'ouverture] cache écrit en %d ms : %s" % [Time.get_ticks_msec() - t, ProjectSettings.globalize_path(_cache_path)])

func _start_game() -> void:
	env.setup(int(info["seed"]))
	interiors = info["interiors"]
	var sp: Dictionary = info["spawn"]
	spawn_pos = sp["pos"]
	spawn_yaw = deg_to_rad(float(sp.get("yaw_deg", 0.0)))
	explorer = Explorer.new()
	explorer.name = "Explorer"
	explorer.walk_speed = float(map.get("walk_speed_mps", 2.3))
	explorer.run_speed = explorer.walk_speed * 2.0
	add_child(explorer)
	explorer.kill_y = float(info["kill_y"])
	explorer.fell.connect(_on_fell)
	explorer.teleport(spawn_pos, spawn_yaw)
	camrig = ThirdPersonCamera.new()
	camrig.name = "CameraRig"
	camrig.target = explorer
	add_child(camrig)
	camrig.yaw = spawn_yaw
	camrig.arm.add_excluded_object(explorer.get_rid())
	camrig.snap()
	var a: Dictionary = info["anchor"]
	anchor_fx = AnchorFx.new()
	anchor_fx.name = "AnchorFx"
	var apos: Vector3 = a["pos"]
	anchor_fx.crystal_local = (a["crystal"] as Vector3) - apos
	anchor_fx.ground_y_local = float(a["platform_y"]) - apos.y + 0.92
	add_child(anchor_fx)
	anchor_fx.global_position = apos
	var saved := GameSave.island(island_id)
	anchor_active = bool(saved.get("anchor_active", false))
	anchor_fx.set_active(anchor_active)
	_loading.visible = false
	load_ms = Time.get_ticks_msec() - _t0
	ready_to_play = true
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ------------------------------------------------------------------ HUD

func _label(size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = align
	return l

func _make_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 6
	add_child(_hud_layer)
	_objective = _label(20, HORIZONTAL_ALIGNMENT_RIGHT)
	_objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_objective.offset_left = -520
	_objective.offset_right = -24
	_objective.offset_top = 18
	_hud_layer.add_child(_objective)
	_prompt = _label(24, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -150
	_prompt.offset_bottom = -110
	_prompt.visible = false
	_hud_layer.add_child(_prompt)
	_banner = _label(48, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -500
	_banner.offset_right = 500
	_banner.offset_top = -170
	_banner.offset_bottom = -100
	_banner.add_theme_color_override("font_color", Color(0.78, 0.95, 1.0))
	_banner.visible = false
	_hud_layer.add_child(_banner)
	_toast = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 90
	_toast.visible = false
	_hud_layer.add_child(_toast)
	_loading = _label(26, HORIZONTAL_ALIGNMENT_CENTER)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.offset_left = -500
	_loading.offset_right = 500
	_hud_layer.add_child(_loading)

func show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_t = 0.0

func show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner_t = 0.0

func objective_text() -> String:
	return "" if anchor_active else "◆ Rejoindre le sanctuaire"

func prompt_text() -> String:
	return "%s · Activer l'Ancre" % GameInput.key_label("interact")

# ------------------------------------------------------------------ jeu

func anchor_in_range() -> bool:
	if explorer == null or anchor_active or info.is_empty():
		return false
	var a: Dictionary = info["anchor"]
	var c: Vector3 = a["crystal"]
	var p := explorer.global_position
	return Vector2(p.x - c.x, p.z - c.z).length() <= float(a.get("radius_m", 3.0)) and absf(p.y - (c.y - 1.5)) < 2.5

func activate_anchor() -> bool:
	if not anchor_in_range():
		return false
	anchor_active = true
	anchor_fx.activate()
	show_banner("Île découverte")
	GameSave.set_island(island_id, {"anchor_active": true, "discovered_at": Time.get_datetime_string_from_system(), "map": String(map.get("_hash", ""))})
	return true

func _on_fell() -> void:
	falls += 1
	show_toast("Retour au quai")
	explorer.teleport(spawn_pos, spawn_yaw)
	camrig.yaw = spawn_yaw
	camrig.snap()

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F5: env.transition_to("village_day", 2.5)
		KEY_F6: env.transition_to("village_sunset", 2.5)
		KEY_F7: env.transition_to("village_night", 2.5)
		KEY_DELETE:
			if k.ctrl_pressed:
				GameSave.clear_island(island_id)
				anchor_active = false
				if anchor_fx:
					anchor_fx.set_active(false)
				show_banner("Sauvegarde de l'île oubliée")

func _process(delta: float) -> void:
	if _loading_cache:
		var st := ResourceLoader.load_threaded_get_status(_cache_path)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading_cache = false
			_on_cache_loaded()
		return
	if not ready_to_play:
		return
	camrig.interior = _is_interior(explorer.global_position)
	explorer.cam_yaw = camrig.yaw
	_objective.text = objective_text()
	_in_range = anchor_in_range()
	_prompt.visible = _in_range
	if _in_range:
		_prompt.text = prompt_text()
		if Input.is_action_just_pressed("interact"):
			activate_anchor()
	if _toast_t >= 0.0:
		_toast_t += delta
		_toast.modulate.a = clampf((2.5 - _toast_t) / 0.6, 0.0, 1.0)
		if _toast_t > 2.5:
			_toast_t = -1.0
			_toast.visible = false
	if _banner_t >= 0.0:
		_banner_t += delta
		_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0) * clampf((4.0 - _banner_t) / 0.8, 0.0, 1.0)
		if _banner_t > 4.0:
			_banner_t = -1.0
			_banner.visible = false

## Hauteur du sol (ou d'un objet) sous (x, z), par lancer de rayon sur le décor ; NAN si vide.
func ground_y_at(x: float, z: float, from_y := 300.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -100.0, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y

func _is_interior(p: Vector3) -> bool:
	for it in interiors:
		var box: AABB = it["aabb"]
		var b := box.grow(-0.15)
		if p.x > b.position.x and p.x < b.end.x and p.z > b.position.z and p.z < b.end.z and p.y > float(it["floor0_y"]) - 0.6 and p.y < b.end.y - 1.0:
			return true
	return false
