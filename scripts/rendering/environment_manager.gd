@tool
class_name EnvironmentManager
extends Node3D
## Point d'entrée UNIQUE de l'ambiance d'une scène : éclairage (LightingRig), ciel, brume, nuages doux,
## îles lointaines, plafonds d'exposition. Tout est piloté par config/environment.json (+ lighting.json).
##
## Causes traitées (et non symptômes) :
##   - surexposition des cristaux, du socle de l'Ancre et des matières claires : l'émission des matériaux est
##     MULTIPLIÉE par un facteur d'ambiance (faible le jour, fort la nuit), le point blanc du tonemapper est
##     relevé et le halo (glow) ne s'allume qu'au-dessus d'un seuil HDR ;
##   - nuages en blocs : nappes douces (CloudLayer) en 3D + ciel à nuages continus ;
##   - profondeur : brume atmosphérique, îles lointaines estompées par la distance ;
##   - transitions : fondu continu entre préréglages, et cycle jour → coucher → nuit paramétrable.
## Utilisation : ajouter un EnvironmentManager, appeler `setup(graine)` (îles lointaines) puis
## `apply_key("village_day")`, `transition_to("village_night", 3.0)` ou `set_time_of_day(0.8)`.

signal ambiance_changed(key: String)

const CONFIG_PATH := "res://config/environment.json"

@export var start_preset := "village_day"
@export var far_islands_enabled := true

var cfg := {}
var rig: LightingRig
var clouds: CloudLayer
var far: FarIslands
var current_key := ""
var time_of_day := 0.4
var cycle_speed := 0.0            # fraction de journée par seconde (0 = figé)
var _blend_from := {}
var _blend_to := {}
var _tween: Tween
var _presets_by_key := {}

func _ready() -> void:
	cfg = load_config()
	rig = get_node_or_null("LightingRig") as LightingRig
	if rig == null:
		rig = LightingRig.new()
		rig.name = "LightingRig"
		rig.start_preset = start_preset
		rig.shadow_distance = 150.0
		add_child(rig)
	clouds = CloudLayer.new()
	clouds.name = "Clouds"
	add_child(clouds)
	far = FarIslands.new()
	far.name = "FarIslands"
	add_child(far)
	if rig.presets.is_empty():
		rig.presets = LightingRig.load_presets()
	for p in rig.presets:
		_presets_by_key[p["key"]] = p
	for k in cfg.get("derived_presets", {}):
		var d: Dictionary = cfg["derived_presets"][k]
		var base: Dictionary = (_presets_by_key[d["from"]] as Dictionary).duplicate()
		for kk in d["set"]:
			base[kk] = d["set"][kk]
		base["key"] = k
		base["name"] = "Aube" if k == "village_dawn" else k
		_presets_by_key[k] = base
	if far_islands_enabled:
		far.build(1, cfg.get("far_islands", {}))
	apply_key(start_preset)

static func load_config() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

## Graine du monde : disposition des îles lointaines.
func setup(world_seed: int) -> void:
	if far != null and far_islands_enabled:
		far.build(world_seed, cfg.get("far_islands", {}))
		_apply_look(_blend_to if not _blend_to.is_empty() else _preset(current_key))

func _preset(key: String) -> Dictionary:
	return _presets_by_key.get(key, rig.presets[0] if not rig.presets.is_empty() else {})

# ------------------------------------------------------------------ ambiances

func apply_key(key: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	current_key = key
	var p := _preset(key)
	_blend_to = p
	_apply(p, key)
	ambiance_changed.emit(key)

## Fondu vers une ambiance en `seconds` secondes (interpolation de tous les paramètres).
func transition_to(key: String, seconds := 3.0) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_blend_from = _blend_to if not _blend_to.is_empty() else _preset(current_key)
	var target := _preset(key)
	current_key = key
	_tween = create_tween()
	_tween.tween_method(func(k: float) -> void:
		var mixed := LightingRig.blend(_blend_from, target, k)
		mixed["emission_scale"] = lerpf(_emission_for(_blend_from), _emission_for(target), k)
		_blend_to = mixed if k < 1.0 else target
		_apply_dict(mixed), 0.0, 1.0, seconds)
	_tween.finished.connect(func() -> void: ambiance_changed.emit(key))

## Heure du jour 0 → 1 (0 = nuit profonde, 0.17 = aube, 0.38-0.66 = plein jour, 0.82 = coucher, 1 = nuit).
func set_time_of_day(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	var keys: Array = cfg.get("time_keys", [])
	if keys.is_empty():
		return
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[keys.size() - 1]
	for i in range(keys.size() - 1):
		if time_of_day >= float(keys[i]["t"]) and time_of_day <= float(keys[i + 1]["t"]):
			a = keys[i]
			b = keys[i + 1]
			break
	var span := maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var k := (time_of_day - float(a["t"])) / span
	k = k * k * (3.0 - 2.0 * k)
	var pa := _preset(a["preset"])
	var pb := _preset(b["preset"])
	var mixed := LightingRig.blend(pa, pb, k)
	mixed["emission_scale"] = lerpf(_emission_for(pa), _emission_for(pb), k)
	_blend_to = mixed
	current_key = a["preset"] if k < 0.5 else b["preset"]
	_apply_dict(mixed)

func _emission_for(p: Dictionary) -> float:
	var table: Dictionary = cfg.get("emission_scale", {})
	return float(table.get(p.get("key", ""), table.get("default", 0.35)))

func _apply(p: Dictionary, key: String) -> void:
	var d := p.duplicate()
	d["emission_scale"] = _emission_for(p)
	_apply_dict(d)

func _apply_dict(p: Dictionary) -> void:
	rig.interior_min = float(cfg.get("interior_lamp_min", 0.0))
	var q := p.duplicate()
	var glow_cap := float(cfg.get("glow", {}).get("intensity_cap", 1.0))
	q["glow"] = minf(float(q.get("glow", 0.5)), glow_cap)
	rig.apply_preset_dict(q)
	_apply_caps(float(p.get("emission_scale", 0.35)))
	_apply_look(p)

## Plafonds d'exposition : émission des matériaux, point blanc, seuil du halo.
func _apply_caps(emission_scale: float) -> void:
	VoxelMaterials.set_global_param("emission_multiplier", emission_scale)
	var env := rig.world_env.environment
	var tm: Dictionary = cfg.get("tonemap", {})
	env.tonemap_white = float(tm.get("white", 4.0))
	var g: Dictionary = cfg.get("glow", {})
	env.glow_hdr_threshold = float(g.get("hdr_threshold", 1.0))
	env.glow_hdr_scale = float(g.get("hdr_scale", 1.0))
	env.glow_bloom = float(g.get("bloom", 0.02))
	var f: Dictionary = cfg.get("fog", {})
	env.fog_sky_affect = float(f.get("sky_affect", 0.3))
	env.fog_aerial_perspective = float(f.get("aerial_perspective", 0.4))
	env.fog_density = env.fog_density * float(f.get("density_scale", 1.0))

## Nuages et îles lointaines suivent la lumière et la brume de l'ambiance.
func _apply_look(p: Dictionary) -> void:
	if rig == null or rig.sun == null:
		return
	var sun_vec := rig.sun.global_transform.basis.z
	var cl := Color.html(p.get("cloud_light", "#ffffff"))
	var cs := Color.html(p.get("cloud_shadow", "#b4bfd2"))
	var key: String = p.get("key", current_key)
	var cc: Dictionary = cfg.get("clouds", {})
	var cover_scale := float((cc.get("cover_scale", {}) as Dictionary).get(key, 1.0))
	var opacity_scale := float((cc.get("opacity_scale", {}) as Dictionary).get(key, 1.0))
	if clouds != null:
		clouds.set_look(cl, cs, sun_vec, cover_scale, opacity_scale)
	if far != null:
		var fog_col := Color.html(p.get("fog_color", "#c4dbee"))
		var amb := Color.html(p.get("sky_horizon", "#b9d4ea")).lerp(Color.html(p.get("sky_top", "#5b8fd6")), 0.5) * clampf(float(p.get("ambient_energy", 0.6)) * 1.3, 0.2, 1.2)
		var sun_col := Color.html(p.get("sun_color", "#fff2dc")) * clampf(float(p.get("sun_energy", 1.0)), 0.2, 1.2)
		far.set_look(fog_col.lerp(Color.html(p.get("sky_horizon", "#b9d4ea")), 0.6), sun_vec, sun_col, amb, float(cfg.get("far_islands", {}).get("fog_end", 400.0)))

func _process(delta: float) -> void:
	if cycle_speed != 0.0:
		set_time_of_day(time_of_day + delta * cycle_speed)
