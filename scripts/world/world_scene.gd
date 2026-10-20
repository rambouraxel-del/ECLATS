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
	if not Engine.is_editor_hint():
		App.set_scene_help("Île générée · vues 1-9,0 · F5 jour · F6 coucher · F7 nuit · Y cycle · N/B île · G profil · R régénérer · V validation")
		_generate()

func _generate() -> void:
	if _building:
		return
	_building = true
	_label.text = "Génération de l'île « %s » (graine %d)…" % [profile, world_seed]
	var p := profile
	var s := world_seed
	_thread = Thread.new()
	_thread.start(func() -> void:
		_result = WorldBuilder.build(p, s)
		call_deferred("_on_built"))

func _on_built() -> void:
	_thread.wait_to_finish()
	world = _result
	_validation = WorldValidator.validate(world, {"buildings": false})
	if nodes != null:
		nodes.queue_free()
	nodes = Node3D.new()
	nodes.name = "Generated"
	add_child(nodes)
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
				var rp: Vector3 = world.rocks[0]["pos"]
				return [rp + Vector3(6, 2.4, 6.5), rp + Vector3(0, 1.3, 0)]
		9: return [Vector3(pc.x + 90, 40, pc.y + 150), Vector3(pc.x, 0, pc.y)]
		0: return [Vector3(pc.x - 40, 12, pc.y - 40), Vector3(pc.x, 2, pc.y)]
	return [Vector3(0, 30, 50), Vector3(0, 2, 0)]

func _go_view(n: int) -> void:
	var v := _view(n)
	if cam and not v.is_empty():
		cam.look_from(v[0], v[1])

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
