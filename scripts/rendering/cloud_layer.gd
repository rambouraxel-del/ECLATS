@tool
class_name CloudLayer
extends Node3D
## Nappes de nuages DOUCES (plans texturés par shader, non voxel) qui suivent la caméra : une mer de nuages
## sous l'île (parallaxe quand on bouge), des nuages moyens à l'horizon et un voile haut. Les couleurs
## suivent l'ambiance (EnvironmentManager).

const SHADER := preload("res://materials/soft_clouds.gdshader")

## Couches : hauteur, couverture, échelle du bruit, opacité, distance d'effacement.
const LAYERS := [
	{"name": "sea", "y": -34.0, "cover": 0.62, "scale": 0.011, "opacity": 0.95, "far": 700.0, "near": 12.0, "stretch": Vector2(1.0, 1.0), "soft": 0.3},
	{"name": "sea_low", "y": -52.0, "cover": 0.7, "scale": 0.007, "opacity": 0.85, "far": 900.0, "near": 12.0, "stretch": Vector2(1.0, 1.0), "soft": 0.35},
	{"name": "mid", "y": 66.0, "cover": 0.5, "scale": 0.009, "opacity": 0.55, "far": 600.0, "near": 25.0, "stretch": Vector2(1.0, 0.8), "soft": 0.3},
	{"name": "high", "y": 150.0, "cover": 0.45, "scale": 0.004, "opacity": 0.4, "far": 1100.0, "near": 60.0, "stretch": Vector2(0.5, 1.6), "soft": 0.32},
]

var materials: Array[ShaderMaterial] = []
var follow: Node3D

func _ready() -> void:
	for c in get_children():
		c.queue_free()
	materials.clear()
	var i := 0
	for L in LAYERS:
		var mi := MeshInstance3D.new()
		mi.name = L["name"]
		var pm := PlaneMesh.new()
		pm.size = Vector2(2600, 2600)
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4000.0
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.render_priority = i - 8
		m.set_shader_parameter("cover", L["cover"])
		m.set_shader_parameter("scale", L["scale"])
		m.set_shader_parameter("opacity", L["opacity"])
		m.set_shader_parameter("fade_far", L["far"])
		m.set_shader_parameter("fade_near", L["near"])
		m.set_shader_parameter("stretch", L["stretch"])
		m.set_shader_parameter("softness", L["soft"])
		m.set_shader_parameter("seed", float(i) * 3.7)
		pm.material = m
		mi.position.y = L["y"]
		add_child(mi)
		materials.append(m)
		i += 1

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	# les plans suivent la caméra en x/z (le bruit est en coordonnées monde : pas de glissement apparent)
	global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)

## Couleurs de lumière et d'ombre des nuages, direction du soleil, couverture globale (0-1).
func set_look(light: Color, shade: Color, sun_dir: Vector3, cover_scale := 1.0, opacity_scale := 1.0) -> void:
	for i in materials.size():
		var m := materials[i]
		m.set_shader_parameter("light_color", light)
		m.set_shader_parameter("shade_color", shade)
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("cover", clampf(float(LAYERS[i]["cover"]) * cover_scale, 0.0, 1.0))
		m.set_shader_parameter("opacity", float(LAYERS[i]["opacity"]) * opacity_scale)
