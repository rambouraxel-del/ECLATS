class_name FreeCamera
extends Camera3D
## Caméra libre (vol) avec mode orbite optionnel.
## Les touches de déplacement sont des touches PHYSIQUES : la même position de touche
## fonctionne en AZERTY (Z Q S D) et en QWERTY (W A S D).
##   ZQSD/WASD : se déplacer      Souris : regarder        Espace / Ctrl : monter / descendre
##   Shift : accélérer            Molette : vitesse (vol) ou distance (orbite)
##   Tab : basculer vol / orbite  Échap : libérer la souris (clic pour la reprendre)

enum Mode { FLY, ORBIT }

@export var mode: Mode = Mode.FLY
@export var move_speed := 6.0
@export var fast_multiplier := 4.0
@export var mouse_sensitivity := 0.0025
## Point autour duquel tourne le mode orbite.
@export var orbit_target := Vector3.ZERO
@export var orbit_distance := 40.0
## Au démarrage, oriente la caméra vers orbit_target.
@export var look_at_target_on_start := false

var _yaw := 0.0
var _pitch := 0.0

func _ready() -> void:
	CameraInput.ensure_actions()
	if look_at_target_on_start:
		look_at(orbit_target)
	_sync_angles_from_transform()
	if mode == Mode.ORBIT:
		_enter_orbit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _sync_angles_from_transform() -> void:
	var fwd := -global_transform.basis.z
	_yaw = atan2(-fwd.x, -fwd.z)
	_pitch = asin(clampf(fwd.y, -1.0, 1.0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.15)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
	elif event.is_action_pressed("camera_release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("camera_toggle_mode"):
		if mode == Mode.FLY:
			_enter_orbit()
		else:
			mode = Mode.FLY

func _zoom(factor: float) -> void:
	if mode == Mode.ORBIT:
		orbit_distance = clampf(orbit_distance * factor, 2.0, 250.0)
	else:
		move_speed = clampf(move_speed / factor, 0.5, 60.0)

func _enter_orbit() -> void:
	mode = Mode.ORBIT
	var offset := global_position - orbit_target
	orbit_distance = maxf(offset.length(), 2.0)
	# On regarde vers la cible : yaw/pitch déduits de la direction caméra → cible.
	var dir := -offset.normalized()
	_yaw = atan2(-dir.x, -dir.z)
	_pitch = asin(clampf(dir.y, -1.0, 1.0))

func _process(delta: float) -> void:
	var basis_yaw := Basis(Vector3.UP, _yaw)
	var look := basis_yaw * Basis(Vector3.RIGHT, _pitch)
	var speed := move_speed * (fast_multiplier if Input.is_action_pressed("camera_fast") else 1.0)
	var input := Vector3(
		Input.get_axis("camera_left", "camera_right"),
		Input.get_axis("camera_down", "camera_up"),
		Input.get_axis("camera_forward", "camera_back"))
	if mode == Mode.FLY:
		var motion := look.x * input.x + look.z * input.z + Vector3.UP * input.y
		global_position += motion.limit_length(1.0) * speed * delta
		global_transform.basis = look
	else:
		# En orbite, ZQSD déplace la cible à plat, Espace/Ctrl la monte/descend.
		var motion := basis_yaw.x * input.x + basis_yaw.z * input.z + Vector3.UP * input.y
		orbit_target += motion.limit_length(1.0) * speed * delta
		global_transform.basis = look
		global_position = orbit_target + look.z * orbit_distance
