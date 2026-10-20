extends Node
## Autoload « App » : raccourcis globaux et petit panneau d'aide.
##   F1 : laboratoire graphique   F2 : première île   L : éclairage suivant
##   F3 : afficher / masquer l'aide   F11 : plein écran

const SCENES := {
	KEY_F1: "res://scenes/lab/graphics_lab.tscn",
	KEY_F2: "res://scenes/island/first_island.tscn",
}

var _hud: Label
var _layer: CanvasLayer
var _extra_help := ""

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)
	_hud = Label.new()
	_hud.position = Vector2(14, 10)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	_layer.add_child(_hud)

## Lignes d'aide propres à la scène courante.
func set_scene_help(text: String) -> void:
	_extra_help = text

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if SCENES.has(key.keycode):
		_extra_help = ""
		get_tree().change_scene_to_file(SCENES[key.keycode])
	elif key.keycode == KEY_L:
		var rig := get_tree().get_first_node_in_group("lighting_rig") as LightingRig
		if rig:
			rig.next_preset()
	elif key.keycode == KEY_F3 and _layer:
		_layer.visible = not _layer.visible
	elif key.keycode == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(_delta: float) -> void:
	if _hud == null or not _layer.visible:
		return
	var cam := get_viewport().get_camera_3d()
	var rig := get_tree().get_first_node_in_group("lighting_rig") as LightingRig
	var lines := PackedStringArray()
	lines.append("ÉCLATS — prototype graphique   %d FPS" % Engine.get_frames_per_second())
	if cam:
		var p := cam.global_position
		var c := VoxelGrid.world_to_cell(p)
		lines.append("Position %.1f, %.1f, %.1f m   cellule %d, %d, %d" % [p.x, p.y, p.z, c.x, c.y, c.z])
		if cam is FreeCamera:
			var fc := cam as FreeCamera
			lines.append("Caméra : %s   vitesse %.1f m/s" % ["orbite" if fc.mode == FreeCamera.Mode.ORBIT else "vol libre", fc.move_speed])
	if rig:
		lines.append("Éclairage : %s" % rig.current_name())
	lines.append("")
	lines.append("ZQSD/WASD bouger · souris regarder · Espace/Ctrl monter/descendre · Shift accélérer")
	lines.append("Molette vitesse/zoom · Tab vol/orbite · Échap libérer la souris (clic pour reprendre)")
	lines.append("F1 laboratoire · F2 île · L éclairage · F3 masquer l'aide · F11 plein écran")
	if _extra_help != "":
		lines.append(_extra_help)
	_hud.text = "\n".join(lines)
