class_name DevLab
extends Node3D
## Laboratoire développeur (Lot 6) : salle grise sur sol plat OU île vide avec une pente accessible. Première personne,
## mêmes outils dans les deux environnements : sélections (point, rectangle, pinceau), panneau de génération, barre de
## commandes (T), aperçu / confirmation / annulation (Ctrl+Z), recette copiable.
##
## Aperçu des commandes : voir docs/LABORATOIRE.md.

@export_enum("room", "island") var kind := "room"

var lab: LabWorld
var explorer: Explorer
var camrig: ThirdPersonCamera
var sel: LabSelection
var ctl: LabController
var ui: LabUi
var builder: BuildMode
var env: EnvironmentManager
var ready_to_play := false
var falls := 0
var load_ms := 0
var _loading: Label
var _hud: CanvasLayer

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	GameInput.ensure()
	App.current_path = App.LAB_ROOM_SCENE if kind == "room" else App.LAB_ISLAND_SCENE
	App.set_tech_default(false)
	App.capture_on_resume = true
	App.set_scene_help("Laboratoire développeur (%s) · T commandes · Tab souris libre · Ctrl+Z défaire" % ("salle grise" if kind == "room" else "île vide"))
	env = get_node_or_null("Environment") as EnvironmentManager
	_hud = CanvasLayer.new()
	_hud.layer = 20
	add_child(_hud)
	_loading = Label.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_theme_font_size_override("font_size", 28)
	_loading.add_theme_color_override("font_color", Color(1, 1, 1))
	_loading.text = "Préparation du laboratoire (%s)…" % ("salle grise" if kind == "room" else "île vide")
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.name = "Fond"
	_hud.add_child(bg)
	_hud.add_child(_loading)
	await get_tree().process_frame
	await get_tree().process_frame
	_build()

func _build() -> void:
	var t0 := Time.get_ticks_msec()
	lab = LabWorld.new()
	lab.name = "Lab"
	add_child(lab)
	lab.setup(kind)
	if env != null:
		env.setup(7)
	if kind == "room":
		_room_shell()
	explorer = Explorer.new()
	explorer.name = "Explorer"
	add_child(explorer)
	explorer.kill_y = lab.spawn.y - 25.0
	explorer.fell.connect(_on_fell)
	var yaw := 0.0 if kind == "room" else -PI * 0.5
	explorer.teleport(lab.spawn, yaw)
	camrig = ThirdPersonCamera.new()
	camrig.name = "CameraRig"
	camrig.target = explorer
	add_child(camrig)
	camrig.yaw = yaw
	camrig.pitch = -0.12
	camrig.arm.add_excluded_object(explorer.get_rid())
	camrig.first_person = true
	camrig.snap()
	sel = LabSelection.new()
	sel.name = "Selection"
	add_child(sel)
	sel.lab = lab
	sel.camera = camrig.cam
	ctl = LabController.new()
	ctl.name = "Controller"
	add_child(ctl)
	ctl.lab = lab
	ctl.sel = sel
	ctl.player = explorer
	ui = LabUi.new()
	ui.name = "Ui"
	ui.env_label = ("Salle grise · sol plat 30 × 30 m" if kind == "room" else "Île vide · pente de 20 % (≈ 11°)")
	ui.player = explorer
	add_child(ui)
	ui.setup(ctl, sel)
	builder = BuildMode.new()
	builder.name = "Construction"
	add_child(builder)
	builder.setup(lab, camrig.cam, explorer, ui, sel)
	_hud.get_node("Fond").queue_free()
	_loading.queue_free()
	load_ms = Time.get_ticks_msec() - t0
	ready_to_play = true
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[laboratoire %s] prêt en %d ms" % [kind, load_ms])

func _process(_delta: float) -> void:
	if not ready_to_play:
		return
	explorer.cam_yaw = camrig.yaw

## B : entrer / sortir du mode construction (atelier).
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not ready_to_play or App.paused_menu or ui.bar_open:
		return
	if k.keycode == KEY_B and not k.ctrl_pressed:
		if builder.active:
			builder.leave()
		else:
			builder.enter()
		get_viewport().set_input_as_handled()

## Salle : 4 murs, plafond (ni ombre ni exposition au ciel : la lumière du jour reste celle du jeu), collisions des murs.
func _room_shell() -> void:
	var shell := Node3D.new()
	shell.name = "Salle"
	add_child(shell)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.59, 0.61)
	mat.roughness = 1.0
	var y0 := lab.ground_y(0.0, 0.0)
	var h := 6.0
	var half := 15.2
	var thick := 0.4
	var boxes := [
		[Vector3(0, y0 + h * 0.5, -half), Vector3(half * 2 + thick * 2, h, thick)],
		[Vector3(0, y0 + h * 0.5, half), Vector3(half * 2 + thick * 2, h, thick)],
		[Vector3(-half, y0 + h * 0.5, 0), Vector3(thick, h, half * 2)],
		[Vector3(half, y0 + h * 0.5, 0), Vector3(thick, h, half * 2)],
		[Vector3(0, y0 + h + thick * 0.5, 0), Vector3(half * 2 + thick * 2, thick, half * 2 + thick * 2)],
	]
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	shell.add_child(body)
	for b in boxes:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[1]
		mi.mesh = bm
		mi.material_override = mat
		mi.position = b[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b[1]
		cs.shape = sh
		cs.position = b[0]
		body.add_child(cs)

func _on_fell() -> void:
	falls += 1
	explorer.teleport(lab.spawn, camrig.yaw)
	camrig.snap()
	ctl.message.emit("Retour au point de départ", "info")

## Place le joueur au sol en (x, z) (essais et captures).
func place_player(x: float, z: float, yaw: float, pitch := 0.0) -> void:
	var g := lab.ground_y(x, z)
	explorer.teleport(Vector3(x, (0.0 if is_nan(g) else g) + 0.05, z), yaw)
	camrig.yaw = yaw
	camrig.pitch = pitch
	camrig.snap()
