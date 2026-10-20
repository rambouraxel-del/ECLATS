@tool
class_name LightingRig
extends Node3D
## Soleil + ciel + environnement, pilotés par config/lighting.json.
## Partagé par toutes les scènes. Touche L (via App) : préréglage suivant.

signal preset_changed(preset_name: String)

const LIGHTING_PATH := "res://config/lighting.json"

@export var start_preset := "day":
	set(value):
		start_preset = value
		if is_inside_tree():
			apply_preset_key(value)
## Distance maximale des ombres du soleil (m).
@export var shadow_distance := 90.0

var presets: Array = []
var current_index := 0
var sun: DirectionalLight3D
var world_env: WorldEnvironment
## Intensité des lumières d'objets (0 le jour, plus la nuit).
var lamp_scale := 0.0
## Matériaux de nuages à teinter selon l'ambiance (renseignés par VoxelClouds).
var cloud_materials: Array[ShaderMaterial] = []
var sky_material: ShaderMaterial

func _ready() -> void:
	add_to_group("lighting_rig")
	_build_nodes()
	presets = load_presets()
	apply_preset_key(start_preset)

static func load_presets() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LIGHTING_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Éclairage invalide : %s" % LIGHTING_PATH)
		return []
	return parsed["presets"]

func _build_nodes() -> void:
	for child in get_children():
		child.queue_free()
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = shadow_distance
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 0.6
	add_child(sun)

	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://materials/sky_clouds.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssao_detail = 0.6
	env.glow_enabled = true
	env.glow_bloom = 0.05
	env.sdfgi_enabled = false
	env.fog_enabled = true
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.02
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

func preset_names() -> PackedStringArray:
	var out := PackedStringArray()
	for p in presets:
		out.append(p["name"])
	return out

func apply_preset_key(key: String) -> void:
	for i in presets.size():
		if presets[i]["key"] == key:
			apply_preset(i)
			return
	if not presets.is_empty():
		apply_preset(0)

func next_preset() -> void:
	if not presets.is_empty():
		apply_preset((current_index + 1) % presets.size())

func current_name() -> String:
	return presets[current_index]["name"] if not presets.is_empty() else "-"

func apply_preset(index: int) -> void:
	if sun == null or presets.is_empty():
		return
	current_index = index
	var p: Dictionary = presets[index]
	sun.light_color = Color.html(p["sun_color"])
	sun.light_energy = float(p["sun_energy"])
	sun.rotation_degrees = Vector3(-float(p["sun_angle"]), float(p["sun_heading"]), 0.0)
	sky_material.set_shader_parameter("sky_top", Color.html(p["sky_top"]))
	sky_material.set_shader_parameter("sky_horizon", Color.html(p["sky_horizon"]))
	sky_material.set_shader_parameter("ground_bottom", Color.html(p["ground_bottom"]))
	sky_material.set_shader_parameter("ground_horizon", Color.html(p["ground_horizon"]))
	var sun_vec := sun.global_transform.basis.z   # le soleil éclaire dans -z : il se trouve vers +z
	sky_material.set_shader_parameter("sun_dir", sun_vec)
	sky_material.set_shader_parameter("sun_color", Color.html(p["sun_color"]))
	var night := float(p.get("moon", 0.0))
	sky_material.set_shader_parameter("moon_dir", sun_vec)
	sky_material.set_shader_parameter("moon_amount", night)
	sky_material.set_shader_parameter("sun_glow", 0.0 if night > 0.5 else 0.8)
	sky_material.set_shader_parameter("sun_size", 0.001 if night > 0.5 else 0.028)
	sky_material.set_shader_parameter("star_amount", float(p.get("stars", 0.0)))
	sky_material.set_shader_parameter("cloud_light", Color.html(p.get("cloud_light", "#ffffff")))
	sky_material.set_shader_parameter("cloud_shadow", Color.html(p.get("cloud_shadow", "#b4bfd2")))
	sky_material.set_shader_parameter("cloud_cover", float(p.get("cloud_cover", 0.45)))
	lamp_scale = float(p.get("lamp_scale", 0.0))
	VoxelMaterials.set_global_param("lamp_emission", float(p.get("lamp_emission", 0.35)))
	for cm in cloud_materials:
		cm.set_shader_parameter("light_color", Color.html(p.get("cloud_light", "#ffffff")))
		cm.set_shader_parameter("shade_color", Color.html(p.get("cloud_shadow", "#b4bfd2")))
		cm.set_shader_parameter("sun_dir", sun_vec)
	var env := world_env.environment
	env.ambient_light_energy = float(p["ambient_energy"])
	env.tonemap_exposure = float(p["exposure"])
	env.fog_light_color = Color.html(p["fog_color"])
	env.fog_density = float(p["fog_density"])
	env.fog_enabled = env.fog_density > 0.0
	env.glow_intensity = float(p["glow"])
	refresh_lamps()
	preset_changed.emit(current_name())

## Ajuste l'intensité des lumières d'objets (groupe « asset_lamps ») selon l'ambiance.
func refresh_lamps() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("asset_lamps"):
		var l := node as Light3D
		if l == null:
			continue
		if not l.has_meta("base_energy"):
			l.set_meta("base_energy", l.light_energy)
		var base: float = l.get_meta("base_energy")
		l.light_energy = base * lamp_scale
		l.visible = lamp_scale > 0.02
