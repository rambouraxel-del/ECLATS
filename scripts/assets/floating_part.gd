extends MeshInstance3D
## Animation douce d'une pièce : flottement (« float ») ou rotation lente (« orbit »).

@export_enum("float", "orbit") var mode := "float"
@export var bob_height := 0.05
@export var spin_speed := 0.35
## Centre de rotation dans le repère du maillage (m).
@export var pivot := Vector3.ZERO

var _base := Vector3.ZERO
var _t := 0.0

func _ready() -> void:
	_base = position

func _process(delta: float) -> void:
	_t += delta
	var rot := Basis(Vector3.UP, _t * spin_speed * (1.0 if mode == "float" else -0.6))
	var bob := Vector3(0, sin(_t * 1.3) * bob_height, 0) if mode == "float" else Vector3.ZERO
	# Rotation autour du pivot : position = base + pivot - rot * pivot.
	transform = Transform3D(rot, _base + pivot - rot * pivot + bob)
