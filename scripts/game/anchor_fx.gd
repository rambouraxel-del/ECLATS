class_name AnchorFx
extends Node3D
## Effets de l'Ancre (Lot 5) : lueur du cristal, PULSATION cyan à l'activation (sphère qui s'étend et s'efface,
## éclat de lumière) et ANNEAU discret au sol qui s'ouvre puis reste visible faiblement tant que l'Ancre est active.

const CYAN := Color(0.42, 0.86, 1.0)

var active := false
var crystal_local := Vector3(0, 1.9, 0)
var ground_y_local := 0.95
var _light: OmniLight3D
var _pulse: MeshInstance3D
var _ring: MeshInstance3D
var _pulse_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _t := -1.0

func _ready() -> void:
	_light = OmniLight3D.new()
	_light.light_color = CYAN
	_light.light_energy = 0.6
	_light.omni_range = 6.0
	_light.position = crystal_local
	add_child(_light)
	_pulse_mat = StandardMaterial3D.new()
	_pulse_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pulse_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pulse_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pulse_mat.albedo_color = Color(CYAN, 0.0)
	_pulse_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	_pulse = MeshInstance3D.new()
	_pulse.mesh = sm
	_pulse.material_override = _pulse_mat
	_pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulse.position = crystal_local
	_pulse.visible = false
	add_child(_pulse)
	_ring_mat = _pulse_mat.duplicate()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.94
	tm.outer_radius = 1.0
	tm.rings = 64
	tm.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, ground_y_local + 0.03, 0)
	_ring.scale = Vector3(1.0, 0.05, 1.0)
	_ring.visible = false
	add_child(_ring)

## État sans animation (chargement d'une sauvegarde).
func set_active(on: bool) -> void:
	active = on
	_light.light_energy = 2.2 if on else 0.6
	_ring.visible = on
	_ring.scale = Vector3(3.2, 0.05, 3.2)
	_ring_mat.albedo_color = Color(CYAN, 0.28)

## Activation : pulsation cyan + anneau au sol.
func activate() -> void:
	active = true
	_t = 0.0
	_pulse.visible = true
	_ring.visible = true

func _process(delta: float) -> void:
	if _t < 0.0:
		if active:
			# respiration lente du cristal actif
			_light.light_energy = 2.2 + sin(Time.get_ticks_msec() * 0.002) * 0.35
		return
	_t += delta
	var k := clampf(_t / 1.6, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	_pulse.scale = Vector3.ONE * lerpf(0.3, 7.5, e)
	_pulse_mat.albedo_color = Color(CYAN, 0.55 * (1.0 - k))
	var rk := clampf(_t / 2.4, 0.0, 1.0)
	var rr := lerpf(0.6, 3.2, 1.0 - pow(1.0 - rk, 2.0))
	_ring.scale = Vector3(rr, 0.05, rr)
	_ring_mat.albedo_color = Color(CYAN, lerpf(0.85, 0.28, rk))
	_light.light_energy = lerpf(9.0, 2.2, e)
	_light.omni_range = lerpf(14.0, 6.0, e)
	if _t > 2.4:
		_t = -1.0
		_pulse.visible = false
