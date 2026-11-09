class_name CreativeUi
extends CanvasLayer
## Interface de l'éditeur créatif : barre du haut (fichier, historique, outils, vues), panneau d'options de l'outil, inventaire
## (recherche, catégories, aperçu 3D), aide des commandes, messages, dialogues d'enregistrement et d'ouverture.
## Textes grands (lisibles sur une capture de téléphone).

const FS := 19
const TS := 17            # barre du haut
const PANEL_W := 330.0
const INV_W := 400.0

var ed: CreativeEditor
var _top: PanelContainer
var _left: PanelContainer
var _left_box: VBoxContainer
var _inv: PanelContainer
var _hint: Label
var _toast: Label
var _toast_t := 0.0
var _status: Label
var _loading: Label
var _hist: PanelContainer
var _hist_list: VBoxContainer
var _tool_btns := {}
var _mode_btns := {}
var _search: LineEdit
var _cat_box: HFlowContainer
var _items: ItemList
var _info: Label
var _preview: SubViewport
var _pv_node: Node3D
var _pv_cam: Camera3D
var _cat := ""
var _all: Array = []
var _shown: Array = []
var _sig := ""
var _dyn: Label
var _dialog: Control
var _undo_btn: Button
var _redo_btn: Button
var _file_menu: MenuButton

func setup(p_ed: CreativeEditor) -> void:
	ed = p_ed
	layer = 15
	_build()
	ed.toast.connect(say)
	ed.changed.connect(refresh)

func _lbl(t: String, size := FS, col := MenuStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _btn(t: String, cb: Callable, toggle := false, w := 0.0, fs := FS) -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(w, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", MenuStyle.TEXT)
	b.add_theme_stylebox_override("normal", MenuStyle.box(Color(0.17, 0.22, 0.30), Color(0.28, 0.38, 0.50), 6, 1))
	b.add_theme_stylebox_override("hover", MenuStyle.box(Color(0.22, 0.34, 0.46), MenuStyle.ACCENT, 6, 2))
	b.add_theme_stylebox_override("pressed", MenuStyle.box(Color(0.14, 0.45, 0.58), MenuStyle.ACCENT, 6, 2))
	b.add_theme_stylebox_override("hover_pressed", MenuStyle.box(Color(0.14, 0.45, 0.58), MenuStyle.ACCENT, 6, 2))
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := b.get_theme_stylebox(st) as StyleBoxFlat
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
	b.pressed.connect(cb)
	return b

func _panel(color := MenuStyle.PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := MenuStyle.box(color, Color(0.30, 0.42, 0.55, 0.9), 8, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	return p

func _build() -> void:
	# --- barre du haut
	_top = _panel()
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.offset_bottom = 54
	add_child(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_top.add_child(row)
	_file_menu = MenuButton.new()
	_file_menu.text = "Fichier"
	_file_menu.flat = false
	_file_menu.focus_mode = Control.FOCUS_NONE
	_file_menu.custom_minimum_size = Vector2(96, 40)
	_file_menu.add_theme_font_size_override("font_size", TS)
	_file_menu.add_theme_stylebox_override("normal", MenuStyle.box(Color(0.17, 0.22, 0.30), Color(0.28, 0.38, 0.50), 6, 1))
	var pm := _file_menu.get_popup()
	pm.add_theme_font_size_override("font_size", FS)
	for it in [["Nouvelle île vide", 0], ["Générer une île (graine)…", 1], ["Ouvrir une carte…  Ctrl+O", 2], ["Enregistrer  Ctrl+S", 3], ["Enregistrer sous…", 4],
			["Exporter une copie…", 5], ["", -1], ["Éditeur de carte 2D", 6], ["Parcourir en jeu (vue classique)", 7], ["Menu principal", 8]]:
		if it[1] < 0:
			pm.add_separator()
		else:
			pm.add_item(it[0], it[1])
	pm.id_pressed.connect(_file_action)
	row.add_child(_file_menu)
	_undo_btn = _btn("↶", func() -> void: ed.undo(), false, 46)
	_undo_btn.tooltip_text = "Annuler (Ctrl+Z)"
	_redo_btn = _btn("↷", func() -> void: ed.redo(), false, 46)
	_redo_btn.tooltip_text = "Rétablir (Ctrl+Y)"
	row.add_child(_undo_btn)
	row.add_child(_redo_btn)
	row.add_child(_btn("Historique", func() -> void: _toggle_history(), false, 0.0, TS))
	row.add_child(VSeparator.new())
	for t in CreativeEditor.TOOLS:
		var tt: String = t[0]
		var key := str(CreativeEditor.TOOLS.find(t) + 1)
		var b := _btn("%s %s" % [key, t[1]], func() -> void: ed.set_tool(tt), true, 0.0, TS)
		_tool_btns[tt] = b
		row.add_child(b)
	row.add_child(_btn("7 Atelier", func() -> void: ed.open_workshop(), false, 0.0, TS))
	row.add_child(VSeparator.new())
	for m in [["aerial", "Aérien"], ["fp", "1re pers."], ["play", "Jeu"]]:
		var mm: String = m[0]
		var b2 := _btn(m[1], func() -> void: ed.set_mode(mm), true, 0.0, TS)
		_mode_btns[mm] = b2
		row.add_child(b2)
	_status = _lbl("", 17, MenuStyle.MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.clip_text = true
	row.add_child(_status)
	# --- panneau d'options (gauche)
	_left = _panel()
	_left.position = Vector2(8, 62)
	_left.custom_minimum_size = Vector2(PANEL_W, 0)
	add_child(_left)
	_left_box = VBoxContainer.new()
	_left_box.add_theme_constant_override("separation", 6)
	_left.add_child(_left_box)
	# --- inventaire (droite)
	_build_inventory()
	# --- historique
	_hist = _panel()
	_hist.position = Vector2(8, 400)
	_hist.custom_minimum_size = Vector2(PANEL_W, 0)
	_hist.visible = false
	add_child(_hist)
	_hist_list = VBoxContainer.new()
	_hist.add_child(_hist_list)
	# --- aide et messages
	_hint = _lbl("", 18, Color(1, 1, 1))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -64
	_hint.offset_left = 12
	_hint.offset_right = -12
	_hint.offset_bottom = -6
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_toast = _lbl("", 22, Color(1, 1, 1))
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_top = -126
	_toast.offset_bottom = -76
	_toast.offset_left = -420
	_toast.offset_right = 420
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_toast.add_theme_constant_override("shadow_offset_x", 2)
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	# réticule (première personne, souris capturée)
	var ret := Label.new()
	ret.name = "Reticule"
	ret.text = "+"
	ret.add_theme_font_size_override("font_size", 30)
	ret.set_anchors_preset(Control.PRESET_CENTER)
	ret.offset_left = -10
	ret.offset_top = -20
	ret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ret)
	_loading = _lbl("", 30)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_loading)

func _build_inventory() -> void:
	_all = AssetCatalog.items()
	_inv = _panel()
	_inv.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_inv.offset_left = -INV_W - 8
	_inv.offset_right = -8
	_inv.offset_top = 62
	_inv.offset_bottom = 600
	_inv.visible = false
	add_child(_inv)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_inv.add_child(v)
	v.add_child(_lbl("Inventaire créatif", 22, MenuStyle.ACCENT))
	_search = LineEdit.new()
	_search.placeholder_text = "Rechercher (chêne, étal, maison…)"
	_search.add_theme_font_size_override("font_size", FS)
	_search.custom_minimum_size = Vector2(0, 38)
	_search.text_changed.connect(func(_t: String) -> void: _fill_items())
	v.add_child(_search)
	_cat_box = HFlowContainer.new()
	_cat_box.add_theme_constant_override("h_separation", 4)
	_cat_box.add_theme_constant_override("v_separation", 4)
	v.add_child(_cat_box)
	_items = ItemList.new()
	_items.custom_minimum_size = Vector2(0, 150)
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items.add_theme_font_size_override("font_size", FS)
	_items.item_selected.connect(_on_item)
	_items.item_activated.connect(_on_item)
	v.add_child(_items)
	var pv := SubViewportContainer.new()
	pv.stretch = true
	pv.custom_minimum_size = Vector2(0, 170)
	v.add_child(pv)
	_preview = SubViewport.new()
	_preview.size = Vector2i(380, 170)
	_preview.own_world_3d = true
	_preview.transparent_bg = false
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pv.add_child(_preview)
	var w := World3D.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.20, 0.26, 0.34)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.9)
	e.ambient_light_energy = 0.9
	w.environment = e
	_preview.world_3d = w
	_pv_cam = Camera3D.new()
	_pv_cam.fov = 38
	_preview.add_child(_pv_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	_preview.add_child(sun)
	_info = _lbl("Choisissez un objet : l'aperçu tourne ici, un clic sur l'île le pose.", 17, MenuStyle.MUTED)
	v.add_child(_info)
	_fill_cats()
	_fill_items()

func _fill_cats() -> void:
	for c in _cat_box.get_children():
		c.queue_free()
	var cats := [""]
	cats.append_array(AssetCatalog.CATS)
	for c in cats:
		var cc: String = c
		var b := _btn("Tout" if c == "" else c, func() -> void:
			_cat = cc
			_fill_cats()
			_fill_items(), true)
		b.button_pressed = (c == _cat)
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", 16)
		_cat_box.add_child(b)

func _fill_items() -> void:
	_all = AssetCatalog.items()
	_shown = AssetCatalog.search(_all, _cat, _search.text)
	_items.clear()
	for it in _shown:
		var sz: Vector3 = it["size"]
		var txt := String(it["name"])
		if sz != Vector3.ZERO:
			txt += "  (%.1f × %.1f × %.1f m)" % [sz.x, sz.y, sz.z]
		_items.add_item(txt)
	if _shown.is_empty():
		_items.add_item("Aucun résultat")
		_items.set_item_disabled(0, true)

func _on_item(i: int) -> void:
	if i < 0 or i >= _shown.size():
		return
	var it: Dictionary = _shown[i]
	_show_preview(it)
	ed.choose_item(it)

func _show_preview(it: Dictionary) -> void:
	if _pv_node != null:
		_pv_node.queue_free()
		_pv_node = null
	var node: Node3D = null
	var size := Vector3.ONE
	if String(it["kind"]) == "modele":
		var r := Construction.load_file(String(it["path"]))
		if bool(r["ok"]):
			var m: Construction = r["construction"]
			node = ConstructionView.create(m, {"collide": false})
			var bb := m.bbox_m()
			size = Vector3(bb.size.x, 4.0, bb.size.y)
			node.position = Vector3(-bb.get_center().x, 0, -bb.get_center().y)
			var holder := Node3D.new()
			holder.add_child(node)
			node = holder
	else:
		var fp := CreativeObjects.footprint(String(it["id"]))
		var inst := AssetLibrary.instantiate(String(it["id"]))
		if inst != null:
			AuthoredIslandView.strip_asset_collisions(inst)
			inst.position = Vector3(-fp.x * 0.5, 0, -fp.z * 0.5)
			var holder2 := Node3D.new()
			holder2.add_child(inst)
			node = holder2
			size = fp
	if node == null:
		return
	_pv_node = node
	_preview.add_child(node)
	var d := maxf(size.length(), 1.0)
	_pv_cam.position = Vector3(d * 0.6, size.y * 0.5 + d * 0.25, d * 0.78)
	_pv_cam.look_at(Vector3(0, size.y * 0.42, 0))
	_info.text = "%s · %s%s" % [it["name"], it["cat"], (" · %.1f × %.1f × %.1f m" % [size.x, size.y, size.z]) if String(it["kind"]) == "asset" else ""]

func _process(delta: float) -> void:
	if _pv_node != null:
		_pv_node.rotation.y += delta * 0.6
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_refresh_dynamic()

# ------------------------------------------------------------------ état

func loading(t: String) -> void:
	_loading.text = t
	_loading.visible = t != ""

func say(text: String, level := "info") -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", {"ok": Color(0.65, 1.0, 0.7), "error": Color(1.0, 0.65, 0.6)}.get(level, Color(1, 1, 1)))
	_toast_t = 5.0
	_toast.modulate.a = 1.0

func panel_open() -> bool:
	return _inv != null and _inv.visible

func typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is SpinBox

func mouse_over_ui() -> bool:
	var m := get_viewport().get_mouse_position()
	for c in [_top, _left, _inv, _hist, _dialog]:
		if c != null and c.visible and (c as Control).get_global_rect().has_point(m):
			return true
	return false

func show_inventory(on: bool) -> void:
	_inv.visible = on
	if on:
		ed._set_capture(false)
	elif ed.mode == "fp":
		ed._set_capture(true)

func toggle_inventory() -> void:
	show_inventory(not _inv.visible)

func _toggle_history() -> void:
	_hist.visible = not _hist.visible
	refresh()

func _panel_sig() -> String:
	return "%s|%s|%s|%s|%s|%s" % [ed.tool, ed.map_sub, ed.selected, ed.inv_item.get("id", ""), ed.mode, str(ed.doc.plan.objects.size() if ed.doc != null else 0)]

## Reconstruit le panneau d'options seulement quand son contenu change (les curseurs ne sont pas recréés pendant qu'on les tire).
func refresh() -> void:
	if ed == null or ed.doc == null:
		return
	for k in _tool_btns:
		(_tool_btns[k] as Button).button_pressed = (k == ed.tool)
	for k in _mode_btns:
		(_mode_btns[k] as Button).button_pressed = (k == ed.mode)
	var s := _panel_sig()
	if s != _sig:
		_sig = s
		_build_options()
	_undo_btn.disabled = not ed.doc.can_undo()
	_redo_btn.disabled = not ed.doc.can_redo()
	get_node("Reticule").visible = ed.captured and ed.mode != "play"
	_left.visible = ed.mode != "play"
	_top.visible = ed.mode != "play"
	_status.text = "%s%s · %d objets · %d maison(s)" % [ed.doc.plan.name, " ●" if ed.doc.is_dirty() else "", ed.doc.plan.objects.size(), ed.doc.plan.houses.size()]
	if _hist.visible:
		_fill_history()
	_hint.text = _hint_text()

func _fill_history() -> void:
	for c in _hist_list.get_children():
		_hist_list.remove_child(c)
		c.queue_free()
	_hist_list.add_child(_lbl("Historique (Ctrl+Z annule, Ctrl+Y rétablit)", 17, MenuStyle.ACCENT))
	var st := ed.doc.undo_stack
	var from := maxi(st.size() - 9, 0)
	if st.is_empty() and ed.doc.redo_stack.is_empty():
		_hist_list.add_child(_lbl("(aucune opération)", 17, MenuStyle.MUTED))
	for i in range(from, st.size()):
		_hist_list.add_child(_lbl("%d. %s" % [i + 1, st[i]["label"]], 17))
	for j in range(ed.doc.redo_stack.size() - 1, maxi(ed.doc.redo_stack.size() - 4, -1), -1):
		_hist_list.add_child(_lbl("↷ %s (annulée)" % ed.doc.redo_stack[j]["label"], 17, MenuStyle.MUTED))
	_hist.set_deferred("size", Vector2.ZERO)

func _hint_text() -> String:
	var common := "V vue · P jouer · I inventaire · N aimantation · Ctrl+Z annuler · Ctrl+Y rétablir · Ctrl+S enregistrer"
	var t := ""
	match ed.tool:
		"select": t = "Clic : choisir · G ou glisser : déplacer · R : tourner · Ctrl+D : dupliquer · L : verrouiller · Suppr : supprimer"
		"place": t = "Clic : poser · R : tourner · +/- : échelle · clic droit : retour · I : inventaire"
		"terrain": t = "Maintenir le clic : sculpter · [ ] taille · - + intensité"
		"material": t = "Maintenir le clic : peindre · clic droit : effacer · [ ] taille"
		"map":
			t = {"zone": "Clic : peindre une zone · clic droit : effacer", "chemin": "Clics : points · Entrée / clic droit : finir · glisser un point · double-clic : ajouter",
				"repere": "Clic : poser un repère", "protege": "Maintenir le clic : protéger (rouge) · clic droit : retirer", "contour": "Glisser un sommet · double-clic : ajouter · clic droit : retirer"}.get(ed.map_sub, "")
		"generate": t = "Clic : générer au curseur · G : nouvelle variante au même endroit · [ ] rayon"
	if ed.mode == "fp":
		common = "WASD déplacer · Espace/C monter/descendre · F marche/vol · Tab souris · " + common
	elif ed.mode == "aerial":
		common = "WASD déplacer · Q/E tourner · molette zoom · " + common
	return "%s\n%s" % [t, common]

func _refresh_dynamic() -> void:
	if _dyn == null or not is_instance_valid(_dyn):
		return
	match ed.tool:
		"select":
			_dyn.text = _selection_text()
		"place":
			_dyn.text = ed.ghost_text if ed.ghost != null else "Visez le sol de l'île."
			_dyn.add_theme_color_override("font_color", Color(0.65, 1.0, 0.7) if ed.ghost_ok else Color(1.0, 0.65, 0.6))
		"generate":
			_dyn.text = "Zone : %.1f m de rayon · graine %d" % [float(ed.gen["radius"]), int(ed.gen["seed"])]

func _selection_text() -> String:
	if ed.selected == "":
		return "Rien de sélectionné. Cliquez sur un objet ou une maison."
	if ed.selected.begins_with("h:"):
		for h in ed.doc.plan.houses:
			if String(h["id"]) == ed.selected.substr(2):
				var r := Construction.from_dict(h["model"])
				return "Maison « %s »\n%s\nOrientation %d × 90°" % [h["name"], (r["construction"] as Construction).summary() if bool(r["ok"]) else "", int(h["yaw"])]
		return ""
	var o := ed.doc.object_by_id(ed.selected)
	if o.is_empty():
		return ""
	var nm: String = AssetLibrary.info(String(o["ref"])).get("name", String(o["ref"]))
	return "%s\nPosition %.1f ; %.1f · cap %d° · échelle %.2f\n%s · %s" % [nm, (o["pos"] as Vector2).x, (o["pos"] as Vector2).y, roundi(float(o["yaw"])), float(o["scale"]),
		"🔒 verrouillé" if bool(o["locked"]) else "libre", "généré (%s)" % o["group"] if String(o["group"]) != "manuel" else "posé à la main"]

# ------------------------------------------------------------------ panneau d'options

func _clear_left() -> void:
	for c in _left_box.get_children():
		_left_box.remove_child(c)
		c.queue_free()
	_dyn = null

func _slider(title: String, lo: float, hi: float, step: float, val: float, cb: Callable, fmt := "%.1f") -> void:
	var l := _lbl("%s : %s" % [title, fmt % val], 17, MenuStyle.MUTED)
	_left_box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(0, 26)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void:
		cb.call(v)
		l.text = "%s : %s" % [title, fmt % v])
	_left_box.add_child(s)

func _chips(items: Array, current: String, cb: Callable, per_row := 2) -> void:
	var g := GridContainer.new()
	g.columns = per_row
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	_left_box.add_child(g)
	for it in items:
		var key: String = it[0]
		var b := _btn(it[1], func() -> void:
			cb.call(key)
			_sig = ""
			refresh(), true)
		b.button_pressed = (key == current)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)

func _build_options() -> void:
	_clear_left()
	var title: String = {"select": "Sélection", "place": "Poser", "terrain": "Relief", "material": "Matière du sol", "map": "Carte", "generate": "Générer"}.get(ed.tool, "")
	_left_box.add_child(_lbl(title, 23, MenuStyle.ACCENT))
	match ed.tool:
		"select":
			_dyn = _lbl("", 17)
			_left_box.add_child(_dyn)
			var hb := HFlowContainer.new()
			_left_box.add_child(hb)
			if ed.selected.begins_with("h:"):
				hb.add_child(_btn("Reprendre (replacer)", func() -> void: ed.pick_up_house()))
				hb.add_child(_btn("Supprimer", func() -> void: ed.delete_selected()))
			elif ed.selected != "":
				hb.add_child(_btn("Déplacer G", func() -> void: ed.begin_grab()))
				hb.add_child(_btn("Tourner R", func() -> void: ed.rotate_pending(1)))
				hb.add_child(_btn("Dupliquer", func() -> void: ed.duplicate_selected()))
				hb.add_child(_btn("Verrouiller L", func() -> void: ed.toggle_lock()))
				hb.add_child(_btn("Supprimer", func() -> void: ed.delete_selected()))
		"place":
			_dyn = _lbl("", 17)
			_left_box.add_child(_dyn)
			if ed.inv_item.is_empty():
				_left_box.add_child(_lbl("Ouvrez l'inventaire (I) et choisissez un objet, un arbre, une maison…", 17, MenuStyle.MUTED))
				_left_box.add_child(_btn("Ouvrir l'inventaire", func() -> void: show_inventory(true)))
			else:
				var hb2 := HFlowContainer.new()
				_left_box.add_child(hb2)
				hb2.add_child(_btn("Tourner R", func() -> void: ed.rotate_pending(1)))
				if ed.house_model != null:
					hb2.add_child(_btn("Raccord au chemin K", func() -> void: ed.house_link = not ed.house_link))
				else:
					hb2.add_child(_btn("Plus grand +", func() -> void: ed.scale_pending(1.1)))
					hb2.add_child(_btn("Plus petit -", func() -> void: ed.scale_pending(0.9)))
				hb2.add_child(_btn("Inventaire I", func() -> void: toggle_inventory()))
		"terrain":
			_chips([["monter", "Monter"], ["creuser", "Creuser"], ["aplanir", "Aplanir"], ["adoucir", "Adoucir"]], String(ed.brush["mode"]), func(k: String) -> void: ed.brush["mode"] = k)
			_slider("Taille", 0.5, 9.0, 0.5, float(ed.brush["radius"]), func(v: float) -> void: ed.brush["radius"] = v)
			_slider("Intensité", 0.1, 1.0, 0.1, float(ed.brush["strength"]), func(v: float) -> void: ed.brush["strength"] = v, "%.1f")
			_left_box.add_child(_lbl("Le relief se règle par pas de 20 cm. Les zones protégées (Carte → Protéger) ne bougent pas.", 16, MenuStyle.MUTED))
		"material":
			var mats: Array = []
			for i in IslandPlan.MATERIALS.size():
				mats.append([str(i), IslandPlan.MATERIALS[i][1]])
			_chips(mats, str(int(ed.brush["material"])), func(k: String) -> void: ed.brush["material"] = int(k), 2)
			_slider("Taille", 0.5, 9.0, 0.5, float(ed.brush["radius"]), func(v: float) -> void: ed.brush["radius"] = v)
		"map":
			_chips([["zone", "Zones"], ["chemin", "Chemins"], ["repere", "Repères"], ["protege", "Protéger"], ["contour", "Contour"]], ed.map_sub, func(k: String) -> void:
				ed.map_sub = k
				ed.path_pts.clear(), 2)
			match ed.map_sub:
				"zone":
					var kinds: Array = []
					for k in IslandPlan.KIND_ORDER:
						kinds.append([k, String(IslandPlan.KINDS[k]["label"]).split(" ")[0]])
					_chips(kinds, ed.zone_kind, func(k: String) -> void: ed.zone_kind = k, 2)
					_slider("Taille", 1.0, 9.0, 0.5, float(ed.brush["radius"]), func(v: float) -> void: ed.brush["radius"] = v)
					_left_box.add_child(_lbl("Une zone redessine le relief de base (≈ 1 s).", 16, MenuStyle.MUTED))
				"chemin":
					_left_box.add_child(_lbl("Clics pour tracer, Entrée pour finir. Les points se déplacent en glissant.", 16, MenuStyle.MUTED))
					_left_box.add_child(_btn("Terminer le chemin (Entrée)", func() -> void: ed.finish_path()))
				"protege":
					_slider("Taille", 0.5, 9.0, 0.5, float(ed.brush["radius"]), func(v: float) -> void: ed.brush["radius"] = v)
					_left_box.add_child(_lbl("Les colonnes rouges ne sont modifiées ni par les pinceaux ni par la régénération.", 16, MenuStyle.MUTED))
				"repere":
					_left_box.add_child(_btn("Point de départ ici", func() -> void:
						var p := ed.aim2()
						if p != Vector2.INF:
							ed.set_start_here(p)))
				"contour":
					_left_box.add_child(_lbl("Glissez un sommet pour remodeler l'île.", 16, MenuStyle.MUTED))
		"generate":
			_chips([["foret", "Forêt"], ["marche", "Marché"]], String(ed.gen["preset"]), func(k: String) -> void: ed.gen["preset"] = k, 2)
			_slider("Rayon", 2.0, 20.0, 0.5, float(ed.gen["radius"]), func(v: float) -> void: ed.gen["radius"] = v)
			if String(ed.gen["preset"]) == "foret":
				_slider("Densité", 5.0, 100.0, 5.0, float(ed.gen["densite"]), func(v: float) -> void: ed.gen["densite"] = v, "%.0f %%")
			else:
				_slider("Étals", 1.0, 8.0, 1.0, float(ed.gen["etals"]), func(v: float) -> void: ed.gen["etals"] = int(v), "%.0f")
			var hb3 := HFlowContainer.new()
			_left_box.add_child(hb3)
			hb3.add_child(_btn("Graine +1", func() -> void: ed.gen["seed"] = int(ed.gen["seed"]) + 1))
			hb3.add_child(_btn("Dans la zone peinte", func() -> void: ed.generate_in_zone()))
			hb3.add_child(_btn("Nouvelle variante G", func() -> void: ed.regenerate_last()))
			_dyn = _lbl("", 17)
			_left_box.add_child(_dyn)
			_left_box.add_child(_lbl("Les objets verrouillés (🔒), posés à la main ou en zone protégée sont conservés à chaque génération.", 16, MenuStyle.MUTED))
	_left.set_deferred("size", Vector2.ZERO)

# ------------------------------------------------------------------ fichiers

func _file_action(id: int) -> void:
	match id:
		0: _confirm_then(func() -> void: ed.new_map("vide"))
		1: show_file_dialog("seed")
		2: show_file_dialog("open")
		3:
			if ed.session.path == "":
				show_file_dialog("save")
			else:
				ed.save()
		4: show_file_dialog("save")
		5: show_file_dialog("export")
		6: _confirm_then(func() -> void: ed.open_map_2d(), false)
		7: ed.play_map_3d()
		8: App.go_menu()

## Action qui remplace la carte : le dialogue « modifications non enregistrées » est posé d'abord.
func _confirm_then(fn: Callable, ask := true) -> void:
	if ask:
		MapSession.ask(self, fn)
	else:
		fn.call()

func _maps() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at("user://cartes/"):
		if f.ends_with(".eclats-carte.json"):
			out.append("user://cartes/" + f)
	out.sort()
	return out

func close_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null

func show_file_dialog(kind: String) -> void:
	close_dialog()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_dialog = shade
	var p := MenuStyle.panel(Vector2(680, 480))
	shade.add_child(p)
	var box := p.get_child(0) as VBoxContainer
	var ttl: String = {"save": "Enregistrer la carte", "open": "Ouvrir une carte", "export": "Exporter une copie", "seed": "Générer une île"}.get(kind, "")
	box.add_child(MenuStyle.title(ttl, 28))
	var msg := _lbl("", 18, MenuStyle.MUTED)
	match kind:
		"save", "export":
			var le := LineEdit.new()
			le.text = ed.doc.plan.name
			le.add_theme_font_size_override("font_size", 22)
			le.custom_minimum_size = Vector2(0, 46)
			box.add_child(le)
			box.add_child(_lbl("Dossier : %s" % ProjectSettings.globalize_path("user://cartes/"), 15, MenuStyle.MUTED))
			var b := MenuStyle.button("Enregistrer" if kind == "save" else "Exporter")
			b.pressed.connect(func() -> void:
				var r: Dictionary = ed.save_as(le.text) if kind == "save" else ed.export_copy(le.text)
				if bool(r["ok"]):
					close_dialog()
				else:
					msg.text = "Impossible : %s" % String(r["error"]))
			box.add_child(b)
			le.call_deferred("grab_focus")
		"open":
			var il := ItemList.new()
			il.custom_minimum_size = Vector2(0, 240)
			il.add_theme_font_size_override("font_size", 20)
			var maps := _maps()
			for m in maps:
				il.add_item(m.get_file().replace(".eclats-carte.json", ""))
			if maps.is_empty():
				il.add_item("(aucune carte enregistrée)")
				il.set_item_disabled(0, true)
			box.add_child(il)
			var b2 := MenuStyle.button("Ouvrir")
			b2.pressed.connect(func() -> void:
				var sel := il.get_selected_items()
				if sel.is_empty():
					msg.text = "Choisissez une carte."
					return
				var path: String = maps[sel[0]]
				close_dialog()
				MapSession.ask(self, func() -> void: ed.open_map(path)))
			box.add_child(b2)
		"seed":
			var sp := SpinBox.new()
			sp.min_value = 1
			sp.max_value = 999999
			sp.value = 7
			sp.prefix = "Graine "
			sp.get_line_edit().add_theme_font_size_override("font_size", 22)
			sp.custom_minimum_size = Vector2(0, 46)
			box.add_child(sp)
			var b3 := MenuStyle.button("Générer et ouvrir")
			b3.pressed.connect(func() -> void:
				var sd := int(sp.value)
				close_dialog()
				MapSession.ask(self, func() -> void: ed.new_map("graine", {"seed": sd})))
			box.add_child(b3)
	box.add_child(msg)
	var bc := MenuStyle.button("Fermer")
	bc.pressed.connect(close_dialog)
	box.add_child(bc)
