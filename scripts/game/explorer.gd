class_name Explorer
extends CharacterBody3D
## Explorateur jouable (Lot 5) : déplacement relatif à la caméra (ZQSD/WASD selon le clavier, flèches),
## course (Maj), saut (Espace), franchissement automatique des marches (≤ 36 cm), collisions avec le décor.
## Tombe-t-il dans le vide ? Le signal `fell` est émis (la scène le ramène au quai).

signal fell

@export var walk_speed := 2.3          # m/s : marche d'exploration
@export var run_speed := 4.6
@export var accel := 14.0
@export var gravity := 18.0
@export var jump_speed := 5.2
const STEP_H := 0.36
## Échelle : voir PlayerConfig (config/player.json). Capsule = hauteur du personnage, rayon proportionnel.
var radius := PlayerConfig.radius()
var height := PlayerConfig.height

var cam_yaw := 0.0
var control_enabled := true
var kill_y := -30.0
var model: ExplorerModel
## Pilotage automatique (recette) : direction monde (x, z), course, saut.
var auto_active := false
var auto_dir := Vector2.ZERO
var auto_sprint := false
var auto_jump := false
var stepped := 0                        # marches franchies (statistique)

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	floor_constant_speed = true
	safe_margin = 0.02
	PlayerConfig.ensure()
	radius = PlayerConfig.radius()
	height = PlayerConfig.height
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	cs.shape = cap
	cs.position = Vector3(0, height * 0.5, 0)
	add_child(cs)
	model = ExplorerModel.new()
	model.name = "Model"
	model.scale = Vector3.ONE * PlayerConfig.k()
	add_child(model)

func face(yaw_rad: float) -> void:
	if model:
		model.rotation.y = yaw_rad

func _physics_process(delta: float) -> void:
	var inp := Vector2.ZERO
	var sprint := false
	var jump := false
	if auto_active:
		var d := auto_dir
		var wish := Vector3(d.x, 0.0, d.y)
		inp = Vector2.ZERO
		_move(delta, wish.limit_length(1.0), auto_sprint, auto_jump)
		auto_jump = false
		return
	if control_enabled:
		inp = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		sprint = Input.is_action_pressed("sprint")
		jump = Input.is_action_just_pressed("jump")
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(inp.x, 0.0, inp.y)
	_move(delta, dir.limit_length(1.0), sprint, jump)

func _move(delta: float, dir: Vector3, sprint: bool, jump: bool) -> void:
	var spd := run_speed if sprint else walk_speed
	var target := dir * spd
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var a := accel if is_on_floor() else accel * 0.35
	hv = hv.move_toward(target, a * spd * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if jump:
			velocity.y = jump_speed
	else:
		velocity.y -= gravity * delta
	if dir.length() > 0.05 and model:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), clampf(12.0 * delta, 0.0, 1.0))
	if is_on_floor() and hv.length() > 0.05:
		_try_step(hv * delta)
	move_and_slide()
	if model:
		model.position = model.position.lerp(Vector3.ZERO, clampf(9.0 * delta, 0.0, 1.0))      # lissage des marches (vue 1re personne : pas d'à-coup)
	if global_position.y < kill_y:
		fell.emit()
	if model:
		model.animate(Vector2(velocity.x, velocity.z).length() / walk_speed, is_on_floor(), delta)

## Marche : bloqué droit devant mais libre STEP_H plus haut → on hisse le corps sur la marche (le déplacement
## horizontal continue normalement) ; le modèle est lissé pour ne pas « sauter ».
func _try_step(motion: Vector3) -> bool:
	var dir := motion.normalized()
	var xf := global_transform
	var hit0 := KinematicCollision3D.new()
	if not test_move(xf, dir * maxf(motion.length(), 0.05), hit0):
		return false
	var slope_contact := hit0.get_normal().angle_to(Vector3.UP) <= floor_max_angle    # on touche une surface praticable
	var up := Vector3(0, STEP_H, 0)
	if test_move(xf, up):
		return false
	var raised := xf.translated(up)
	var probe := dir * (radius + 0.06)        # le centre doit passer au-dessus du nez de marche
	if test_move(raised, probe):
		return false
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), -up * 1.05, col):
		return false
	var dy := raised.origin.y + col.get_travel().y - xf.origin.y
	# Rampe d'escalier ou versant : le contact est praticable ET la surface d'arrivée est inclinée → c'est une pente, que
	# move_and_slide monte normalement. Sans ce test, l'explorateur était hissé à chaque image sur une rampe (en première
	# personne la vue montait par à-coups de 25 cm). Une vraie marche a un contact presque vertical ou un dessus plat.
	if slope_contact and col.get_normal().angle_to(Vector3.UP) > 0.35:
		return false
	if dy < 0.03 or col.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false
	var landing := raised.origin + probe + col.get_travel() + Vector3(0, 0.005, 0)
	var moved := landing - xf.origin
	global_position = landing
	if model:
		model.position -= moved          # le corps a « sauté » la marche ; le modèle rattrape en douceur
	stepped += 1
	return true

func teleport(pos: Vector3, yaw_rad := NAN) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	if not is_nan(yaw_rad):
		face(yaw_rad)
