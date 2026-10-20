extends MeshInstance3D
## Animation douce d'une pièce : flottement + rotation (« float »), rotation inverse (« orbit »),
## ou simple houle (« bob » : montée/descente et léger roulis, pour un bateau amarré).

@export_enum("float", "orbit", "bob") var mode := "float"
@export var bob_height := 0.05
@export var spin_speed := 0.35
## Centre de rotation dans le repère du maillage (m).
@export var pivot := Vector3.ZERO

var _base := Vector3.ZERO
var _t := 0.0

func _ready() -> void:
	_base = position
	_t = 0.0 if mode == "bob" else fposmod(_base.x * 3.1 + _base.z * 1.7, TAU)

func _process(delta: float) -> void:
	_t += delta
	if mode == "bob":
		# Houle : simple montée/descente, identique pour toutes les pièces du bateau (corps rigide).
		position = _base + Vector3(0, sin(_t * 1.1) * bob_height, 0)
		return
	var rot := Basis(Vector3.UP, _t * spin_speed * (1.0 if mode == "float" else -0.6))
	var bob := Vector3(0, sin(_t * 1.3) * bob_height, 0) if mode == "float" else Vector3.ZERO
	transform = Transform3D(rot, _base + pivot - rot * pivot + bob)
