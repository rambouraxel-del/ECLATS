class_name ThirdPersonCamera
extends Node3D
## Caméra à la troisième personne : orbite à la souris autour de l'explorateur, bras à ressort qui évite les murs,
## rapprochement automatique en intérieur. Clic : capturer la souris · Échap : la libérer · molette : distance.

var target: Node3D
var yaw := 0.0
var pitch := -0.32
var interior := false
var sensitivity := 0.0032
var dist_out := 4.6
var dist_in := 1.8
var arm: SpringArm3D
var cam: Camera3D
var _h := 1.55

func _ready() -> void:
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

func snap() -> void:
	if target:
		global_position = target.global_position + Vector3(0, _h, 0)
		rotation = Vector3(pitch, yaw, 0)
		arm.spring_length = dist_in if interior else dist_out

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * sensitivity
		pitch = clampf(pitch - mm.relative.y * sensitivity, -1.25, 0.55)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist_out = clampf(dist_out - 0.4, 2.2, 9.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist_out = clampf(dist_out + 0.4, 2.2, 9.0)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta: float) -> void:
	if target == null:
		return
	var h := 1.45 if interior else 1.55
	_h = lerpf(_h, h, clampf(delta * 4.0, 0.0, 1.0))
	var goal := target.global_position + Vector3(0, _h, 0)
	global_position = global_position.lerp(goal, clampf(1.0 - exp(-14.0 * delta), 0.0, 1.0))
	var want_pitch := pitch
	if interior:
		want_pitch = clampf(pitch, -0.7, 0.15)
	rotation = Vector3(want_pitch, yaw, 0)
	arm.spring_length = lerpf(arm.spring_length, dist_in if interior else dist_out, clampf(delta * 3.0, 0.0, 1.0))
