extends Node
## Autoload « App » : navigation entre scènes (menu principal, jeu, outils), pause Échap, aide technique à la demande.
##   Échap : pause (Reprendre / Retour au menu principal) dans toute scène sauf le menu
##   F3 : informations techniques (FPS, position, aide)   F11 : plein écran   L : éclairage suivant
##   Raccourcis de développement (inchangés) : F1 labo graphique · F2 première île · F4 colonie · F8 matériaux ·
##   F9 île générée (Lot 4) · F10 île d'ouverture · F12 laboratoire développeur

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const OPENING_SCENE := "res://scenes/game/opening_island.tscn"
const GENERATED_SCENE := "res://scenes/world/settled_island.tscn"
const LAB_ROOM_SCENE := "res://scenes/lab/dev_lab_room.tscn"
const LAB_ISLAND_SCENE := "res://scenes/lab/dev_lab_island.tscn"
const MAP_ISLAND_SCENE := "res://scenes/map/map_island.tscn"      # île issue d'un plan (Lot 7)
const MAP_EDITOR_SCENE := "res://scenes/map/map_editor.tscn"      # éditeur de carte (Lot 7)
const CREATIVE_SCENE := "res://scenes/creative/creative_editor.tscn"  # éditeur d'îles créatif (3D)

const SCENES := {
	KEY_F1: "res://scenes/lab/graphics_lab.tscn",
	KEY_F2: "res://scenes/island/first_island.tscn",
	KEY_F4: "res://scenes/island/colony_island.tscn",
	KEY_F8: "res://scenes/lab/material_gallery.tscn",
	KEY_F9: GENERATED_SCENE,
	KEY_F10: OPENING_SCENE,
	KEY_F12: LAB_ROOM_SCENE,
}

signal scene_opened(path: String)

## Paramètres transmis à la scène qui s'ouvre (ex. profil et graine de l'île à générer).
var launch := {}
## La scène courante est une scène de jeu : la souris est (re)capturée à la reprise.
var capture_on_resume := false
var paused_menu := false
var current_path := ""

var _hud: Label
var _layer: CanvasLayer
var _extra_help := ""
var _controls_help := PackedStringArray()
var _tech_default := true
var _overlay: CanvasLayer
var _loading_label: Label
var _pause_layer: CanvasLayer
var _pause_panel: Control
var _orphans: Array[Thread] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# crochet de recette : godot … -- --recette=res://tools/xxx.gd lance un script (Node) au-dessus du vrai jeu
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--recette="):
			var sc := load(a.substr(10)) as Script
			if sc != null:
				var n := Node.new()
				n.set_script(sc)
				n.name = "Recette"
				n.process_mode = Node.PROCESS_MODE_ALWAYS
				add_child.call_deferred(n)
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
	_layer.visible = false         # le menu n'affiche rien de technique ; chaque scène choisit

# ------------------------------------------------------------------ navigation

## Ouvre une scène : état de chargement affiché, scène précédente fermée et déchargée.
func open(path: String, params := {}) -> void:
	# Lot 11 : une carte en cours d'édition n'est jamais perdue en silence (menu, autre scène…). L'éditeur et la vue 3D
	# de la même session passent librement de l'un à l'autre.
	if MapSession.current != null and path != MAP_EDITOR_SCENE and path != MAP_ISLAND_SCENE and path != CREATIVE_SCENE and not params.has("session"):
		if MapSession.current.is_dirty() and not bool(params.get("_quitter_ok", false)):
			var p2 := params.duplicate()
			p2["_quitter_ok"] = true
			MapSession.ask(self, func() -> void: open(path, p2))
			return
		MapSession.current = null
	launch = params
	_hide_pause()
	_extra_help = ""
	_controls_help = PackedStringArray()
	capture_on_resume = false
	current_path = path
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _layer:
		_layer.visible = false
	_show_loading("Chargement…")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	_hide_loading()
	if _layer and path != MENU_SCENE:
		_layer.visible = _tech_default
	scene_opened.emit(path)

func go_menu() -> void:
	open(MENU_SCENE)

## La scène courante fixe la visibilité par défaut des informations techniques (F3 les affiche à la demande).
func set_tech_default(visible_by_default: bool) -> void:
	_tech_default = visible_by_default
	if _layer:
		_layer.visible = visible_by_default

func _show_loading(text: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.layer = 30
		add_child(_overlay)
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.07, 0.10, 0.96)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(bg)
		_loading_label = Label.new()
		_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_loading_label.add_theme_font_size_override("font_size", 28)
		_loading_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		_overlay.add_child(_loading_label)
	_loading_label.text = text
	_overlay.visible = true

func _hide_loading() -> void:
	if _overlay:
		_overlay.visible = false

## Un fil de calcul encore en cours quand la scène est quittée : joint plus tard, sans bloquer le retour au menu.
func adopt_thread(t: Thread) -> void:
	if t != null and t.is_started():
		_orphans.append(t)

# ------------------------------------------------------------------ pause

func can_pause() -> bool:
	return current_path != MENU_SCENE and current_path != ""

func toggle_pause() -> void:
	if paused_menu:
		resume()
	elif can_pause():
		pause()

func pause() -> void:
	if paused_menu or not can_pause():
		return
	paused_menu = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if DisplayServer.get_name() == "headless":
		return
	_build_pause()
	_pause_layer.visible = true
	(_pause_panel.find_child("Reprendre", true, false) as Control).grab_focus()

func resume() -> void:
	if not paused_menu:
		return
	paused_menu = false
	_hide_pause()
	get_tree().paused = false
	if capture_on_resume and DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func back_to_menu() -> void:
	paused_menu = false
	_hide_pause()
	get_tree().paused = false
	go_menu()

func _hide_pause() -> void:
	paused_menu = false
	if _pause_layer:
		_pause_layer.visible = false

func _build_pause() -> void:
	if _pause_layer != null:
		return
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 25
	add_child(_pause_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(shade)
	_pause_panel = MenuStyle.panel(Vector2(440, 330))
	_pause_layer.add_child(_pause_panel)
	var box := _pause_panel.get_child(0) as VBoxContainer
	box.add_child(MenuStyle.title("Pause", 40))
	box.add_child(MenuStyle.spacer(10))
	var b1 := MenuStyle.button("Reprendre")
	b1.name = "Reprendre"
	b1.pressed.connect(resume)
	box.add_child(b1)
	var b2 := MenuStyle.button("Retour au menu principal")
	b2.name = "RetourMenu"
	b2.pressed.connect(back_to_menu)
	box.add_child(b2)
	box.add_child(MenuStyle.spacer(6))
	box.add_child(MenuStyle.note("Échap : reprendre · F3 : informations techniques"))

## Aide propre à la scène courante.
func set_scene_help(text: String) -> void:
	_extra_help = text

## Lignes de commandes propres à la scène (remplacent celles de la caméra libre).
func set_controls_help(lines: PackedStringArray) -> void:
	_controls_help = lines

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if paused_menu:
		return
	if SCENES.has(key.keycode):
		open(SCENES[key.keycode])
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
	for i in range(_orphans.size() - 1, -1, -1):
		if not _orphans[i].is_alive():
			_orphans[i].wait_to_finish()
			_orphans.remove_at(i)
	if _hud == null or not _layer.visible:
		return
	var cam := get_viewport().get_camera_3d()
	var rig := get_tree().get_first_node_in_group("lighting_rig") as LightingRig
	var lines := PackedStringArray()
	lines.append("ÉCLATS — informations techniques   %d FPS" % Engine.get_frames_per_second())
	if cam:
		var p := cam.global_position
		var c := VoxelGrid.world_to_cell(p)
		lines.append("Position %.1f, %.1f, %.1f m   cellule %d, %d, %d" % [p.x, p.y, p.z, c.x, c.y, c.z])
		if cam is FreeCamera:
			var fc := cam as FreeCamera
			lines.append("Caméra : %s   vitesse %.1f m/s" % ["orbite" if fc.mode == FreeCamera.Mode.ORBIT else "vol libre", fc.move_speed])
	var envm := get_tree().get_first_node_in_group("environment_manager") as EnvironmentManager
	if envm != null:
		lines.append("Éclairage : %s" % envm.hud_label())         # ambiance et heure réellement appliquées (fondus, cycle)
	elif rig:
		lines.append("Éclairage : %s" % rig.current_name())
	lines.append("")
	if _controls_help.is_empty():
		lines.append("ZQSD/WASD bouger · souris regarder · Espace/Ctrl monter/descendre · Shift accélérer")
		lines.append("Molette vitesse/zoom · Tab vol/orbite · clic pour reprendre la souris · Échap pause")
	else:
		lines.append_array(_controls_help)
	lines.append("F1 labo graphique · F2 île · F4 colonie · F9 île générée · F10 île d'ouverture · F12 laboratoire développeur · F8 matériaux · L éclairage · F3 infos · F11 plein écran")
	if _extra_help != "":
		lines.append(_extra_help)
	_hud.text = "\n".join(lines)
