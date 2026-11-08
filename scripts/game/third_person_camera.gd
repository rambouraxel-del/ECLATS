class_name ThirdPersonCamera
extends Node3D
## Caméra de l'explorateur : PREMIÈRE PERSONNE par défaut (Lot 6, à hauteur des yeux, suit le lissage des marches) ou
## troisième personne (touche V) : orbite à la souris, bras à ressort qui évite les murs, rapprochement en intérieur.
## Le clic recapture la souris ; la pause (Échap) est gérée par App.


var target: Node3D
var yaw := 0.0
var pitch := -0.32
var interior := false
var sensitivity := 0.0032
var dist_out := 4.6
var dist_in := 1.8
var arm: SpringArm3D
var cam: Camera3D
var first_person := false : set = set_first_person
var _h := 1.55
var _toast: Label
var _toast_t := 0.0

func _ready() -> void:
	PlayerConfig.ensure()
	_h = PlayerConfig.shoulder(false)
	arm = SpringArm3D.new()
	arm.name = "Arm"
	arm.collision_mask = 1
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	arm.shape = sph
	arm.margin = 0.08
	arm.spring_length = dist_out
	add_child(arm)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 64.0
	cam.near = 0.05
	cam.far = 2500.0
	arm.add_child(cam)
	cam.current = true
	_apply_mode()

func set_first_person(v: bool) -> void:
	first_person = v
	if arm != null:
		_apply_mode()

func _apply_mode() -> void:
	cam.fov = PlayerConfig.fov_fp if first_person else PlayerConfig.fov_fp - PlayerConfig.THIRD_FOV_OFFSET
	arm.shape = null if first_person else _sphere()
	if first_person:
		arm.spring_length = 0.0
		pitch = clampf(pitch, -1.4, 1.4)
	else:
		pitch = clampf(pitch, -1.25, 0.55)
		arm.spring_length = dist_in if interior else dist_out
	var ex := target as Explorer
	if ex and ex.model:
		ex.model.visible = not first_person

func _sphere() -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = 0.2
	return s

func toggle_view() -> void:
	set_first_person(not first_person)
	snap()

func snap() -> void:
	if target:
		global_position = _goal()
		rotation = Vector3(pitch, yaw, 0)
		arm.spring_length = 0.0 if first_person else (dist_in if interior else dist_out)

## Point visé par la caméra : yeux (1re personne, avec le lissage des marches du modèle) ou épaule (3e personne).
func _goal() -> Vector3:
	var base := target.global_position
	if first_person:
		var ex := target as Explorer
		var off := Vector3.ZERO
		if ex and ex.model:
			off = Vector3(0.0, ex.model.position.y, 0.0)        # le corps a « sauté » une marche : l'œil rattrape en douceur
		return base + Vector3(0, PlayerConfig.eye(), 0) + off
	return base + Vector3(0, _h, 0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * sensitivity
		var lim := 1.45 if first_person else 1.25
		pitch = clampf(pitch - mm.relative.y * sensitivity, -lim, 1.45 if first_person else 0.55)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif not first_person and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist_out = clampf(dist_out - 0.4, 2.2, 9.0)
		elif not first_person and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist_out = clampf(dist_out + 0.4, 2.2, 9.0)
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_V:
		toggle_view()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F:
		var f := PlayerConfig.cycle_fov()
		_apply_mode()
		_say("Champ de vision : %d°" % roundi(f))

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast != null:
			_toast.text = ""
	if target == null:
		return
	if first_person:
		global_position = _goal()           # sans retard : la vue suit exactement le corps
		rotation = Vector3(pitch, yaw, 0)
		return
	var h := PlayerConfig.shoulder(interior)
	_h = lerpf(_h, h, clampf(delta * 4.0, 0.0, 1.0))
	var goal := _goal()
	global_position = global_position.lerp(goal, clampf(1.0 - exp(-14.0 * delta), 0.0, 1.0))
	var want_pitch := pitch
	if interior:
		want_pitch = clampf(pitch, -0.7, 0.15)
	rotation = Vector3(want_pitch, yaw, 0)
	arm.spring_length = lerpf(arm.spring_length, dist_in if interior else dist_out, clampf(delta * 3.0, 0.0, 1.0))

func _say(t: String) -> void:
	if _toast == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		add_child(layer)
		_toast = Label.new()
		_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_toast.anchor_left = 0.0
		_toast.anchor_right = 1.0
		_toast.offset_top = 96
		_toast.offset_bottom = 130
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.add_theme_font_size_override("font_size", 24)
		_toast.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
		_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_toast.add_theme_constant_override("outline_size", 6)
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_toast)
	_toast.text = t
	_toast_t = 1.8
