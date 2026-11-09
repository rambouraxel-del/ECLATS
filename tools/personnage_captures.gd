extends SceneTree
## Captures de l'explorateur sur fond neutre : planche face / côté dos / trois-quarts, gros plan du visage,
## poses des animations et images d'un cycle de marche (pour le GIF).
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1000x1000 -s tools/personnage_captures.gd -- [sortie] [mode]
## mode : planche (défaut) · anim · cycle · visage

var _out := "res://docs/captures/personnage"
var _model: ExplorerModel
var _cam: Camera3D

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "planche"
	for a in args:
		if a.begins_with("--sortie="):
			_out = a.substr(9)
		else:
			mode = a
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	VoxelMesher.palette_warmup()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#e6e1e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c9c3d0")
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_energy = 0.35
	root.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#ddd6dc")
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	_model = ExplorerModel.new()
	root.add_child(_model)
	_cam = Camera3D.new()
	_cam.fov = 30
	root.add_child(_cam)
	_cam.current = true
	await _frames(6)
	match mode:
		"planche":
			await _planche()
		"anim":
			await _anim_poses()
		"cycle":
			await _cycle()
		"visage":
			await _visage()
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String, yaw_deg: float, dist := 3.5, h := 0.82, w := 1000, ht := 1000) -> void:
	_model.rotation_degrees.y = yaw_deg
	_cam.position = Vector3(0, h, dist)
	_cam.look_at(Vector3(0, h, 0))
	await _frames(4)
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(_out + "/" + name + ".png"))
	print("saved ", name)

func _planche() -> void:
	_model.pose_at("idle", 0.0)
	for v in [["face", 180.0], ["profil", 90.0], ["dos", 0.0], ["trois_quarts", 145.0]]:
		await _shot(v[0], v[1])

func _visage() -> void:
	_model.pose_at("idle", 0.0)
	await _shot("visage_face", 180.0, 1.5, 1.5)
	await _shot("visage_trois_quarts", 150.0, 1.5, 1.5)

func _anim_poses() -> void:
	for c in ["idle", "walk", "run", "jump"]:
		var d: float = ExplorerModel.CLIPS[c][1]
		for k in 4:
			_model.pose_at(c, d * float(k) / 4.0)
			await _shot("anim_%s_%d" % [c, k], 90.0, 4.2, 0.85)

func _cycle() -> void:
	var clip := "walk"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
	var n := 24
	var d: float = ExplorerModel.CLIPS[clip][1]
	for k in n:
		_model.pose_at(clip, d * float(k) / float(n))
		await _shot("cycle_%s_%02d" % [clip, k], 115.0, 4.4, 0.82)
