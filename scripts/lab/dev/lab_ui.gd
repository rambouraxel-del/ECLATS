class_name LabUi
extends CanvasLayer
## Interface du laboratoire : panneau de génération (à droite), barre de commandes (T), messages, réticule.
## Le panneau et la barre appellent LabController : même sélection, même logique.
## Raccourcis : 1 Point · 2 Rectangle · 3 Pinceau · R emprise 3,50 × 3,50 · [ ] rayon · G aperçu · Entrée confirmer · X annuler l'aperçu
##              Ctrl+Z annuler l'opération · C copier la recette · T commandes · Tab libérer la souris (cliquer le panneau) · Suppr effacer

var ctl: LabController
var sel: LabSelection
var panel: PanelContainer
var bar: LineEdit
var msg: Label
var info: Label
var recipe_label: Label
var bar_open := false
var player: Explorer
var env_label := ""
var suspended := false             # vrai pendant le mode construction : le panneau et les raccourcis du labo se taisent

var _tool_btns: Array[Button] = []
var _gen: OptionButton
var _seed: SpinBox
var _variant: OptionButton
var _roof: OptionButton
var _yaw: OptionButton
var _lock: CheckButton
var _variant_label: Label
var _roof_label: Label
var _yaw_label: Label
var _msg_t := 0.0
var _reticle: Control

const GENS := [["arbre", "Arbre"], ["rocher", "Rocher"], ["maison", "Maison"], ["aplanir", "Aplanir (zone peinte)"]]

func setup(c: LabController, s: LabSelection) -> void:
	ctl = c
	sel = s
	layer = 8
	_build()
	ctl.message.connect(_on_message)
	ctl.state_changed.connect(_refresh)
	sel.selection_changed.connect(_refresh)
	_refresh()

func _lbl(text: String, size := 15, color := MenuStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _build() -> void:
	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(func() -> void:
		_reticle.draw_circle(Vector2.ZERO, 3.6, Color(0, 0, 0, 0.5))
		_reticle.draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 1, 0.95)))
	add_child(_reticle)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.box(Color(0.08, 0.10, 0.14, 0.9), Color(0.30, 0.42, 0.55, 0.9), 10, 1))
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -318
	panel.offset_right = -10
	panel.offset_top = 10
	panel.offset_bottom = -10
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)
	v.add_child(_lbl("Laboratoire développeur", 19, MenuStyle.ACCENT))
	var env := _lbl(env_label, 13, MenuStyle.MUTED)
	env.name = "Env"
	v.add_child(env)
	v.add_child(_lbl("Sélection", 14, MenuStyle.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	for t in 3:
		var b := Button.new()
		b.text = ["1 Point", "2 Rectangle", "3 Pinceau"][t]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void: sel.set_tool(t))
		row.add_child(b)
		_tool_btns.append(b)
	info = _lbl("", 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	_lock = CheckButton.new()
	_lock.text = "Emprise 3,50 × 3,50 m (R)"
	_lock.focus_mode = Control.FOCUS_NONE
	_lock.add_theme_font_size_override("font_size", 13)
	_lock.toggled.connect(func(on: bool) -> void: sel.lock_size = on)
	v.add_child(_lock)
	v.add_child(HSeparator.new())
	v.add_child(_lbl("Génération", 14, MenuStyle.MUTED))
	_gen = OptionButton.new()
	for g in GENS:
		_gen.add_item(g[1])
	_gen.focus_mode = Control.FOCUS_NONE
	_gen.item_selected.connect(func(_i: int) -> void: _refresh())
	v.add_child(_gen)
	var g1 := GridContainer.new()
	g1.columns = 2
	v.add_child(g1)
	g1.add_child(_lbl("Graine", 14))
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 99999
	_seed.value = 42
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g1.add_child(_seed)
	_variant_label = _lbl("Espèce", 14)
	g1.add_child(_variant_label)
	_variant = OptionButton.new()
	_variant.focus_mode = Control.FOCUS_NONE
	_variant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g1.add_child(_variant)
	_roof_label = _lbl("Toit", 14)
	g1.add_child(_roof_label)
	_roof = OptionButton.new()
	_roof.focus_mode = Control.FOCUS_NONE
	_roof.add_item("(selon la graine)")
	for r in LabCommands.ROOF_NAMES.values():
		_roof.add_item(String(r))
	g1.add_child(_roof)
	_yaw_label = _lbl("Porte", 14)
	g1.add_child(_yaw_label)
	_yaw = OptionButton.new()
	_yaw.focus_mode = Control.FOCUS_NONE
	for y in ["vers le joueur", "sud (0)", "est (1)", "nord (2)", "ouest (3)"]:
		_yaw.add_item(y)
	g1.add_child(_yaw)
	var b1 := _btn("Aperçu (G)", _on_preview)
	b1.name = "BtnApercu"
	v.add_child(b1)
	var b2 := _btn("Confirmer (Entrée)", func() -> void: ctl.confirm())
	b2.name = "BtnConfirmer"
	v.add_child(b2)
	var b3 := _btn("Annuler l'aperçu (X)", func() -> void: ctl.cancel_preview())
	v.add_child(b3)
	var b4 := _btn("Défaire (Ctrl+Z)", func() -> void: ctl.undo())
	v.add_child(b4)
	v.add_child(HSeparator.new())
	var b5 := _btn("Copier la recette (C)", func() -> void: ctl.copy_recipe())
	b5.name = "BtnRecette"
	v.add_child(b5)
	var b6 := _btn("Rejouer la recette copiée", func() -> void: ctl.replay_saved_recipe())
	v.add_child(b6)
	recipe_label = _lbl("", 12, MenuStyle.MUTED)
	recipe_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(recipe_label)
	var hint := _lbl("T : commandes · Tab : souris libre\nÉchap : pause · F3 : infos", 12, MenuStyle.MUTED)
	v.add_child(hint)
	# message principal (bas de l'écran)
	msg = Label.new()
	msg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	msg.offset_left = 20
	msg.offset_right = -340
	msg.offset_top = -170
	msg.offset_bottom = -70
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 20)
	msg.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	msg.add_theme_constant_override("shadow_offset_x", 2)
	msg.add_theme_constant_override("shadow_offset_y", 2)
	msg.visible = false
	add_child(msg)
	# barre de commandes
	bar = LineEdit.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 20
	bar.offset_right = -340
	bar.offset_top = -62
	bar.offset_bottom = -20
	bar.placeholder_text = "/generer maison --graine 42   (Entrée : lancer · Échap : fermer)"
	bar.add_theme_font_size_override("font_size", 20)
	bar.add_theme_stylebox_override("normal", MenuStyle.box(Color(0.05, 0.07, 0.10, 0.94), MenuStyle.ACCENT, 8, 2))
	bar.add_theme_stylebox_override("focus", MenuStyle.box(Color(0.05, 0.07, 0.10, 0.94), MenuStyle.ACCENT, 8, 2))
	bar.visible = false
	bar.text_submitted.connect(_on_submit)
	bar.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
			close_bar()
			bar.accept_event())
	add_child(bar)

func _btn(text: String, fn: Callable) -> Button:
	var b := MenuStyle.button(text)
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	return b

func current_gen() -> String:
	return String(GENS[_gen.selected][0])

## Options de la génération courante, telles que la barre de commandes les aurait analysées.
func current_opts() -> Dictionary:
	var o := {"seed": int(_seed.value)}
	match current_gen():
		"arbre":
			o["espece"] = LabCommands.SPECIES[LabCommands.SPECIES_NAMES.values()[maxi(_variant.selected, 0)]]
		"rocher":
			o["famille"] = LabCommands.FAMILIES[LabCommands.FAMILY_NAMES.values()[maxi(_variant.selected, 0)]]
		"maison":
			if _variant.selected > 0:
				o["murs"] = LabCommands.WALLS[LabCommands.WALL_NAMES.values()[_variant.selected - 1]]
			if _roof.selected > 0:
				o["toit"] = LabCommands.ROOFS[LabCommands.ROOF_NAMES.values()[_roof.selected - 1]]
			if _yaw.selected > 0:
				o["yaw"] = _yaw.selected - 1
		"aplanir":
			pass
	return o

func _on_preview() -> void:
	ctl.request(current_gen(), current_opts())

func _on_submit(text: String) -> void:
	bar.text = ""
	close_bar()
	ctl.run_command(text)

func open_bar(prefill := "") -> void:
	bar_open = true
	bar.visible = true
	bar.text = prefill
	if player:
		player.control_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	bar.grab_focus()
	bar.caret_column = bar.text.length()

func close_bar() -> void:
	bar_open = false
	bar.visible = false
	bar.release_focus()
	if player:
		player.control_enabled = true
	if App.capture_on_resume and DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _refresh() -> void:
	if sel == null:
		return
	for i in _tool_btns.size():
		_tool_btns[i].set_pressed_no_signal(i == sel.tool)
	# la sélection courante oriente la génération proposée
	var want := {LabSelection.Tool.POINT: [0, 1], LabSelection.Tool.RECT: [2], LabSelection.Tool.BRUSH: [3]}
	if not (want[sel.tool] as Array).has(_gen.selected):
		_gen.select(want[sel.tool][0])
	_variant.clear()
	match current_gen():
		"arbre":
			_variant_label.text = "Espèce"
			for n in LabCommands.SPECIES_NAMES.values():
				_variant.add_item(String(n))
		"rocher":
			_variant_label.text = "Famille"
			for n in LabCommands.FAMILY_NAMES.values():
				_variant.add_item(String(n))
		"maison":
			_variant_label.text = "Murs"
			_variant.add_item("(selon la graine)")
			for n in LabCommands.WALL_NAMES.values():
				_variant.add_item(String(n))
		"aplanir":
			_variant_label.text = "Niveau"
			_variant.add_item("médian de la zone")
	var house := current_gen() == "maison"
	_roof_label.visible = house
	_roof.visible = house
	_yaw_label.visible = house
	_yaw.visible = house
	_lock.visible = sel.tool == LabSelection.Tool.RECT
	_lock.set_pressed_no_signal(sel.lock_size)
	_seed.editable = current_gen() != "aplanir"
	info.text = sel.info_text()
	var rt := ctl.recipe_text()
	recipe_label.text = ("Recette : " + rt) if rt != "" else ""

func _on_message(text: String, level: String) -> void:
	msg.text = text
	msg.visible = true
	var col := {"info": Color(0.9, 0.95, 1.0), "ok": Color(0.55, 1.0, 0.65), "erreur": Color(1.0, 0.55, 0.5)}
	msg.add_theme_color_override("font_color", col.get(level, Color.WHITE))
	_msg_t = 0.0 if level == "ok" and not text.begins_with("Aperçu") else 9999.0
	if level != "ok" or not text.begins_with("Aperçu"):
		_msg_t = 0.0

func _process(delta: float) -> void:
	if msg.visible and not ctl.pending.is_empty():
		return                           # l'aperçu en attente garde son message affiché
	if msg.visible:
		_msg_t += delta
		if _msg_t > 8.0:
			msg.visible = false

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or bar_open or App.paused_menu:
		return
	if suspended and k.keycode != KEY_TAB:
		return
	match k.keycode:
		KEY_T:
			open_bar()
			get_viewport().set_input_as_handled()
		KEY_SLASH:
			open_bar("/")
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			ctl.confirm()
		KEY_X, KEY_BACKSPACE:
			ctl.cancel_preview()
		KEY_G:
			_on_preview()
		KEY_C:
			if not k.ctrl_pressed:
				ctl.copy_recipe()
		KEY_Z:
			if k.ctrl_pressed:
				ctl.undo()
		KEY_TAB:
			var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)
