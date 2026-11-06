class_name MapEditor
extends Control
## ÉDITEUR DE CARTE (Lot 7, étape 2) — outil développeur. Vue AÉRIENNE 2D pour composer l'île (contour, zones, chemins,
## repères, pinceaux de relief et de matière, masque de protection, régénération) ; « Vérifier en 3D » ouvre la même carte
## en première personne pour contrôler les raccords (F6 y fait revenir). Toute la logique est dans MapDoc (testée sans rendu).
## Raccourcis : 1-8 outils · Ctrl+Z annuler · Entrée / clic droit : terminer un tracé · Échap : abandonner · Suppr : supprimer
## la sélection · molette : zoom · bouton du milieu : déplacer la vue.

const TOOLS := [["contour", "1  Contour"], ["zones", "2  Zones"], ["chemins", "3  Chemins"], ["reperes", "4  Repères"],
	["relief", "5  Relief"], ["matiere", "6  Matériau"], ["masque", "7  Masque"], ["regen", "8  Régénérer"], ["maisons", "9  Maisons"]]
const DIR := "user://cartes/"

var doc: MapDoc
var canvas: PlanCanvas
var tool := "contour"
var pal: VoxelPalette

# réglages d'outils
var kind := "plateau"
var brush_radius := 2.5
var brush_strength := 0.6
var relief_mode := "monter"
var mat_index := 0
var mat_erase := false
var mask_mode := "peindre"
var lm_kind := "vue"
var lm_label := "Point de vue"
var path_width := 2.2
var regen_variation := 0
var house_model: Construction = null            # maison choisie (modèle normalisé)
var house_source := ""
var house_yaw := 0
var house_eval: Dictionary = {}                # dernier aperçu d'implantation
var house_pos := Vector2.INF
var _house_info: Label
var _house_pick: OptionButton
var _house_files: Array[String] = []
var _eval_t := 0
var auto_variant := 0
var auto_seed := 1
var auto_fit := Vector2(8.0, 7.0)

# état de manipulation
var _dragging := false
var _drag_kind := ""              # sommet | point | repere | depart | zone | selection
var _drag_i := -1
var _drag_id := ""
var _stroke := false
var _last_dab := Vector2.INF
var _selected_path := ""
var _selected_lm := ""
var _sel_a := Vector2.INF
var _new_outline := false
var _lmb := false
var _busy := false

var _top: Control
var _tool_buttons := {}
var _opts: VBoxContainer
var _status: Label
var _msg: Label
var _dialog: Control
var _g_seed: SpinBox
var _g_w: SpinBox
var _g_l: SpinBox
var _undo_btn: Button
var _title: Label

func _ready() -> void:
	App.current_path = App.MAP_EDITOR_SCENE
	App.set_tech_default(false)
	App.capture_on_resume = false
	App.set_scene_help("Éditeur de carte · Ctrl+Z annuler · molette zoom · clic milieu déplacer")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	pal = VoxelPalette.get_default()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var launch: Dictionary = App.launch
	if launch.has("plan"):
		doc = MapDoc.from_plan(launch["plan"] as IslandPlan)
		if doc.plan.outline.size() < 3:
			doc = MapDoc.blank()
	else:
		doc = MapDoc.blank()
	_build_ui()
	select_tool("contour" if doc.plan.outline.size() < 3 else "zones")
	_refresh(true)
	canvas.fit.call_deferred()

# ------------------------------------------------------------------ interface

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = MenuStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# barre du haut
	var topp := PanelContainer.new()
	var tb := MenuStyle.box(Color(0.10, 0.13, 0.18), Color(0.25, 0.35, 0.48), 0, 1)
	tb.content_margin_left = 6
	tb.content_margin_right = 6
	tb.content_margin_top = 4
	tb.content_margin_bottom = 4
	topp.add_theme_stylebox_override("panel", tb)
	root.add_child(topp)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	topp.add_child(bar)
	bar.add_child(_btn("Menu", func() -> void: App.go_menu(), 64))
	bar.add_child(_vsep())
	bar.add_child(_btn("Canevas vide", _on_blank, 112))
	_g_seed = _spin(bar, "Graine", 0, 99999, 1, 3, 84)
	_g_w = _spin(bar, "L", 32, 120, 2, 56, 66)
	_g_l = _spin(bar, "H", 32, 120, 2, 48, 66)
	bar.add_child(_btn("Générer", _on_generate, 84))
	bar.add_child(_vsep())
	_undo_btn = _btn("Annuler (Ctrl+Z)", _on_undo, 136)
	bar.add_child(_undo_btn)
	bar.add_child(_btn("Exporter la carte", func() -> void: _open_dialog("export"), 144))
	bar.add_child(_btn("Ouvrir une carte", func() -> void: _open_dialog("open"), 140))
	bar.add_child(_btn("Vérifier en 3D", _on_verify, 124))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	# outils (gauche)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(142, 0)
	left.add_theme_stylebox_override("panel", MenuStyle.box(Color(0.09, 0.12, 0.16), Color(0.25, 0.35, 0.48), 0, 1))
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	var lt := Label.new()
	lt.text = "Outils"
	lt.add_theme_font_size_override("font_size", 17)
	lt.add_theme_color_override("font_color", MenuStyle.MUTED)
	lv.add_child(lt)
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 17)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(select_tool.bind(t[0]))
		_tool_buttons[t[0]] = b
		lv.add_child(b)
	# vue aérienne (centre)
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	holder.custom_minimum_size = Vector2(300, 300)
	body.add_child(holder)
	canvas = PlanCanvas.new()
	canvas.name = "Canevas"
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.interactive = true
	canvas.show_handles = true
	canvas.legend_scale = 0.82
	canvas.canvas_event.connect(_on_canvas_event)
	canvas.mouse_exited.connect(func() -> void:
		canvas.cursor_world = Vector2.INF
		canvas.queue_redraw())
	holder.add_child(canvas)
	# panneau d'options (droite)
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(318, 0)
	right.add_theme_stylebox_override("panel", MenuStyle.box(Color(0.09, 0.12, 0.16), Color(0.25, 0.35, 0.48), 0, 1))
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", MenuStyle.ACCENT)
	rv.add_child(_title)
	_opts = VBoxContainer.new()
	_opts.add_theme_constant_override("separation", 7)
	rv.add_child(_opts)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sp)
	_msg = Label.new()
	_msg.name = "Message"
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(290, 60)
	_msg.add_theme_font_size_override("font_size", 15)
	_msg.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	rv.add_child(_msg)
	_status = Label.new()
	_status.name = "Etat"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(290, 130)
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", MenuStyle.MUTED)
	rv.add_child(_status)

func _vsep() -> VSeparator:
	return VSeparator.new()

func _btn(text: String, fn: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(fn)
	return b

func _spin(parent: Control, label: String, lo: float, hi: float, step: float, val: float, w: float) -> SpinBox:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.value = val
	sp.custom_minimum_size = Vector2(w, 0)
	parent.add_child(sp)
	return sp

func _label(text: String, size := 15, col := Color(0.88, 0.93, 0.98)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(290, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _slider(label: String, lo: float, hi: float, step: float, val: float, fn: Callable, fmt := "%.1f", commit := Callable()) -> HSlider:
	var l := _label("%s : %s" % [label, fmt % val])
	_opts.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(290, 22)
	s.value_changed.connect(func(v: float) -> void:
		l.text = "%s : %s" % [label, fmt % v]
		fn.call(v))
	if commit.is_valid():
		s.drag_ended.connect(func(changed: bool) -> void:
			if changed:
				commit.call())
	_opts.add_child(s)
	return s

func _option(items: Array, selected: int, fn: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = selected
	o.custom_minimum_size = Vector2(290, 36)
	o.add_theme_font_size_override("font_size", 16)
	o.item_selected.connect(fn)
	_opts.add_child(o)
	return o

func _opt_btn(text: String, fn: Callable) -> Button:
	var b := _btn(text, fn)
	b.custom_minimum_size = Vector2(290, 38)
	_opts.add_child(b)
	return b

# ------------------------------------------------------------------ outils

func select_tool(t: String) -> void:
	_finish_drafts(false)
	tool = t
	for k in _tool_buttons:
		(_tool_buttons[k] as Button).button_pressed = (k == t)
	canvas.cursor_radius = 0.0
	canvas.sel_rect = Rect2()
	canvas.hint = ""
	canvas.house_ghost = {}
	_house_info = null
	_selected_path = ""
	_selected_lm = ""
	canvas.selected_path = ""
	canvas.selected_landmark = ""
	_build_options()
	canvas.queue_redraw()

func _build_options() -> void:
	for c in _opts.get_children():
		c.queue_free()
	var names := {}
	for t in TOOLS:
		names[t[0]] = String(t[1]).substr(3)
	_title.text = String(names[tool])
	match tool:
		"contour":
			_opts.add_child(_label("Clic : poser un point · clic sur le 1er point, Entrée ou clic droit : fermer. Contour existant : glisser un sommet, double-clic sur un bord = ajouter un sommet, clic droit sur un sommet = le retirer."))
			_opt_btn("Nouveau contour (tracer)", func() -> void:
				_new_outline = true
				canvas.draft_outline = []
				canvas.hint = "Tracé du contour : cliquez les points, Entrée pour fermer"
				canvas.queue_redraw())
		"zones":
			var keys: Array = []
			for k in IslandPlan.KIND_ORDER:
				keys.append(IslandPlan.KINDS[k]["label"])
			_opts.add_child(_label("Peindre : clic maintenu · clic droit : effacer le disque touché."))
			_option(keys, IslandPlan.KIND_ORDER.find(kind), func(i: int) -> void: kind = IslandPlan.KIND_ORDER[i])
			_slider("Rayon du pinceau", 1.0, 9.0, 0.5, brush_radius, func(v: float) -> void: brush_radius = v)
			_opts.add_child(_label("Zones plates (arrivée, plateau, crique) : aplanies au niveau où l'on commence à peindre."))
			var relief_v := float(doc.plan.settings.get("relief", 1.0))
			_slider("Relief naturel (×)", 0.0, 2.0, 0.1, relief_v, func(_v: float) -> void: pass, "%.1f", func() -> void:
				pass)
			var rs := _opts.get_child(_opts.get_child_count() - 1) as HSlider
			rs.drag_ended.connect(func(changed: bool) -> void:
				if changed:
					doc.begin_op("Régler le relief naturel")
					doc.plan.settings["relief"] = snappedf(rs.value, 0.1)
					_end_op(true))
		"chemins":
			_opts.add_child(_label("Clic : poser un point (Entrée ou clic droit : terminer). Glisser un point pour le déplacer · double-clic sur un chemin = ajouter un point · clic droit sur un point = le retirer · Suppr : supprimer le chemin."))
			_slider("Largeur du chemin", 1.0, 5.0, 0.1, path_width, func(v: float) -> void: path_width = v, "%.1f m", func() -> void:
				if _selected_path != "":
					doc.begin_op("Largeur du chemin")
					doc.set_path_width(_selected_path, path_width)
					_end_op(true))
			_opt_btn("Supprimer le chemin sélectionné", _delete_selected)
		"reperes":
			_opts.add_child(_label("Clic : poser un repère · glisser pour déplacer · clic droit : retirer. Le départ se place avec le bouton ci-dessous."))
			_option(["Point de vue", "Lieu à dévoiler"], 0 if lm_kind == "vue" else 1, func(i: int) -> void: lm_kind = "vue" if i == 0 else "lieu")
			var le := LineEdit.new()
			le.text = lm_label
			le.custom_minimum_size = Vector2(290, 34)
			le.text_changed.connect(func(t: String) -> void: lm_label = t)
			_opts.add_child(le)
			_opt_btn("Placer le point de départ", func() -> void:
				_drag_kind = "depart"
				canvas.hint = "Cliquez sur le sol où le joueur démarre"
				canvas.queue_redraw())
		"relief":
			_opts.add_child(_label("Glisser pour modifier le relief. La zone d'effet est affichée avant d'appliquer. Les colonnes du masque ne bougent pas."))
			_option(["Monter", "Creuser", "Aplanir", "Adoucir"], ["monter", "creuser", "aplanir", "adoucir"].find(relief_mode), func(i: int) -> void:
				relief_mode = ["monter", "creuser", "aplanir", "adoucir"][i])
			_slider("Rayon", 0.5, 8.0, 0.25, brush_radius, func(v: float) -> void: brush_radius = v)
			_slider("Force", 0.1, 1.0, 0.05, brush_strength, func(v: float) -> void: brush_strength = v, "%.2f")
		"matiere":
			var names2: Array = []
			for m in IslandPlan.MATERIALS:
				names2.append(m[1])
			_opts.add_child(_label("Peindre la matière du sol. Clic droit : revenir à la matière du plan."))
			_option(names2, mat_index, func(i: int) -> void: mat_index = i)
			_slider("Rayon", 0.5, 8.0, 0.25, brush_radius, func(v: float) -> void: brush_radius = v)
		"masque":
			_opts.add_child(_label("Le masque (rayures rouges) protège le relief et les matières : pinceaux et régénération n'y touchent pas."))
			_option(["Protéger (peindre)", "Retirer la protection"], 0 if mask_mode == "peindre" else 1, func(i: int) -> void: mask_mode = "peindre" if i == 0 else "gommer")
			_slider("Rayon", 0.5, 9.0, 0.25, brush_radius, func(v: float) -> void: brush_radius = v)
			_opt_btn("Retirer tout le masque", _clear_mask)
		"maisons":
			_build_house_options()
		"regen":
			_opts.add_child(_label("1. Tracez un rectangle (deux coins) : c'est la zone où le relief est relancé. 2. Cliquez « Régénérer ». Le masque est respecté ; les retouches hors du rectangle sont conservées."))
			var sp := SpinBox.new()
			sp.min_value = 0
			sp.max_value = 999
			sp.value = regen_variation
			sp.prefix = "Variante (0 = suivante) : "
			sp.custom_minimum_size = Vector2(290, 34)
			sp.value_changed.connect(func(v: float) -> void: regen_variation = int(v))
			_opts.add_child(sp)
			_opt_btn("Régénérer le relief dans la sélection", _do_regen)
			_opt_btn("Sélectionner toute l'île", func() -> void:
				if doc.field != null:
					var lo := Vector2(1e9, 1e9)
					var hi := Vector2(-1e9, -1e9)
					for p: Vector2 in doc.plan.outline:
						lo = lo.min(p)
						hi = hi.max(p)
					canvas.sel_rect = Rect2(lo, hi - lo)
					canvas.queue_redraw())

# ------------------------------------------------------------------ maisons (Lot 8)

const HOUSE_DIRS := ["res://assets/maisons/", "user://maisons/"]

func _scan_houses() -> void:
	_house_files.clear()
	for d in HOUSE_DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		var fl := da.get_files()
		fl.sort()
		for f in fl:
			if f.ends_with(".eclats-maison.json"):
				_house_files.append(d + f)

func _build_house_options() -> void:
	_scan_houses()
	_opts.add_child(_label("Choisissez un modèle (atelier ou exemple), orientez-le avec R, visez la parcelle : l'aperçu dit si l'implantation est possible. Clic : poser · Ctrl+Z : annuler · clic droit sur une maison : la retirer."))
	var names: Array = []
	for f in _house_files:
		var nm := String(f).get_file().replace(".eclats-maison.json", "")
		names.append(("Exemple · " if String(f).begins_with("res://") else "Atelier · ") + nm)
	if names.is_empty():
		names.append("(aucune maison enregistrée)")
	_house_pick = _option(names, maxi(_house_files.find(house_source), 0), func(i: int) -> void: _load_house(i))
	_opt_btn("Tourner la maison (R)", _rotate_house)
	_opt_btn("Actualiser la liste", func() -> void: _build_options())
	_opts.add_child(HSeparator.new())
	_opts.add_child(_label("Habitation générée : le jeu cherche une parcelle compatible (plateau, pelouse), choisit l'orientation d'après l'accès au chemin et pose.", 13))
	_option(["Variante : auto (selon la graine)", "Cabane", "Maison à deux pièces", "Maison en L"], auto_variant, func(i: int) -> void: auto_variant = i)
	var hb := HBoxContainer.new()
	_opts.add_child(hb)
	var sd := SpinBox.new()
	sd.min_value = 0
	sd.max_value = 99999
	sd.value = auto_seed
	sd.prefix = "Graine "
	sd.custom_minimum_size = Vector2(120, 32)
	sd.value_changed.connect(func(v: float) -> void: auto_seed = int(v))
	hb.add_child(sd)
	var fw := SpinBox.new()
	fw.min_value = 4
	fw.max_value = 14
	fw.step = 0.5
	fw.value = auto_fit.x
	fw.prefix = "L "
	fw.suffix = " m"
	fw.custom_minimum_size = Vector2(80, 32)
	fw.value_changed.connect(func(v: float) -> void: auto_fit.x = v)
	hb.add_child(fw)
	var fd := SpinBox.new()
	fd.min_value = 4
	fd.max_value = 14
	fd.step = 0.5
	fd.value = auto_fit.y
	fd.prefix = "P "
	fd.suffix = " m"
	fd.custom_minimum_size = Vector2(80, 32)
	fd.value_changed.connect(func(v: float) -> void: auto_fit.y = v)
	hb.add_child(fd)
	var ab := _opt_btn("Placer automatiquement une habitation", _auto_place)
	ab.name = "BtnAuto"
	_house_info = _label("", 13, Color(0.85, 0.95, 1.0))
	_house_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_house_info.custom_minimum_size = Vector2(290, 150)
	_opts.add_child(_house_info)
	if not _house_files.is_empty():
		_load_house(maxi(_house_files.find(house_source), 0))

func _load_house(i: int) -> void:
	if i < 0 or i >= _house_files.size():
		return
	var r := Construction.load_file(_house_files[i])
	if not bool(r["ok"]):
		say("Maison illisible : %s" % String(r["error"]))
		house_model = null
		return
	house_model = r["construction"]
	house_source = _house_files[i]
	house_eval = {}
	if _house_info != null:
		_house_info.text = "%s\n%s" % [house_model.summary(), "Visez la parcelle sur le plan."]
	_update_house_preview(house_pos if house_pos.x < 1.0e8 else Vector2.INF, true)

func _rotate_house() -> void:
	house_yaw = (house_yaw + 1) % 4
	_update_house_preview(house_pos, true)

static func door_side_name(dir: Vector2i) -> String:
	return HousePad.side_name(dir)

## Aperçu d'implantation (limité à ~10 par seconde : chaque évaluation relit le relief autour de la parcelle).
func _update_house_preview(p: Vector2, force := false) -> void:
	if house_model == null or doc.field == null or p.x > 1.0e8:
		canvas.house_ghost = {}
		canvas.queue_redraw()
		return
	var now := Time.get_ticks_msec()
	if not force and now - _eval_t < 100:
		return
	_eval_t = now
	house_pos = Vector2(snappedf(p.x, 0.1), snappedf(p.y, 0.1))
	house_eval = doc.evaluate_house(house_model, house_pos, house_yaw)
	var rm: Rect2 = house_eval["rect_m"]
	var ok := bool(house_eval["ok"])
	var dir: Vector2i = house_eval.get("dir", Vector2i.ZERO)
	canvas.house_ghost = {"rect": rm, "door": house_eval.get("door", Vector2.ZERO), "ok": ok, "link": house_eval.get("link", {}),
		"label": "%s · porte côté %s" % [house_model.name, door_side_name(dir)] if dir != Vector2i.ZERO else house_model.name}
	if _house_info != null:
		var t := "%s\nOrientation : porte côté %s (R pour tourner)\n" % [house_model.summary(), door_side_name(dir) if dir != Vector2i.ZERO else "—"]
		if ok:
			t += "✔ %s" % String(house_eval["text"])
		else:
			t += "✖ %s\nRien ne sera modifié." % " ".join(PackedStringArray(house_eval["reasons"]))
		_house_info.text = t
		_house_info.add_theme_color_override("font_color", Color(0.65, 1.0, 0.7) if ok else Color(1.0, 0.65, 0.6))
	canvas.queue_redraw()

## Habitation générée posée sur une parcelle compatible, orientation choisie d'après le chemin ; refus expliqué sans rien forcer.
func _auto_place() -> Dictionary:
	if doc.field == null:
		say("Tracez d'abord un contour : il n'y a pas encore d'île.")
		return {"ok": false}
	canvas.house_ghost = {}
	var r := doc.auto_place_dwelling(["auto", "cabane", "deux_pieces", "en_L"][auto_variant], auto_seed, auto_fit)
	if bool(r["ok"]):
		var gen: Dictionary = r["gen"]
		say("%s — Ctrl+Z pour annuler." % doc.message)
		_refresh(true)
		if _house_info != null:
			_house_info.text = "✔ %s\n%s\nRecette : %s" % [doc.message, String(gen["text"]), LabCommands.recipe_string(gen["recipe"])]
			_house_info.add_theme_color_override("font_color", Color(0.65, 1.0, 0.7))
	else:
		var why := " ".join(PackedStringArray(r["reasons"]))
		say("Impossible : %s" % why)
		if _house_info != null:
			_house_info.text = "✖ %s" % why
			_house_info.add_theme_color_override("font_color", Color(1.0, 0.65, 0.6))
	return r

func place_house_here() -> Dictionary:
	if house_model == null or house_pos.x > 1.0e8:
		say("Choisissez une maison et visez la parcelle.")
		return {"ok": false}
	var r := doc.place_house(house_model, house_pos, house_yaw)
	if bool(r["ok"]):
		say("%s — Ctrl+Z pour annuler." % doc.message)
		_refresh(true)
		canvas.house_ghost = {}
		house_eval = {}
		if _house_info != null:
			_house_info.text = "%s\n✔ Maison posée. Déplacez la souris pour en poser une autre, ou Ctrl+Z pour annuler." % house_model.summary()
			_house_info.add_theme_color_override("font_color", Color(0.65, 1.0, 0.7))
	else:
		say("Impossible : %s Rien n'est modifié." % " ".join(PackedStringArray(r["reasons"])))
		_update_house_preview(house_pos, true)
	return r

func _delete_selected() -> void:
	if tool == "chemins" and _selected_path != "":
		doc.begin_op("Supprimer le chemin")
		doc.delete_path(_selected_path)
		_selected_path = ""
		canvas.selected_path = ""
		_end_op(true)
	elif tool == "reperes" and _selected_lm != "":
		doc.begin_op("Supprimer le repère")
		doc.delete_landmark(_selected_lm)
		_selected_lm = ""
		canvas.selected_landmark = ""
		_end_op(true)

# ------------------------------------------------------------------ rafraîchissement

func say(t: String) -> void:
	_msg.text = t

## full : image du relief, masque, chemins recalculés. Sinon : rectangle de colonnes seulement.
func _refresh(full: bool, rect := Rect2i()) -> void:
	canvas.plan = doc.plan
	canvas.path_reports = doc.path_reports
	if full:
		canvas.set_field(doc.field)
		canvas.refresh_mask(doc.plan.layers if doc.field != null else null)
	elif rect.size != Vector2i.ZERO:
		canvas.refresh_rect(rect)
	_undo_btn.disabled = not doc.can_undo()
	_update_status()
	canvas.queue_redraw()

func _update_status() -> void:
	var lines: Array[String] = []
	var p := doc.plan
	if p.outline.size() < 3:
		lines.append("Canevas vide : tracez un contour (outil 1) pour créer une île.")
	else:
		lines.append("%s · %.0f × %.0f m" % [p.name, p.width, p.length])
		lines.append("%d zones · %d chemins · %d repères · %d maison(s)" % [p.zones.size(), p.paths.size(), p.landmarks.size(), p.houses.size()])
		if doc.plan.layers != null:
			lines.append("Retouches : %d colonnes de relief, %d de matière · masque : %d" % [p.layers.count_delta(), p.layers.count_mat(), p.layers.count_mask()])
		for r in doc.path_reports:
			var tag := "praticable" if bool(r["ok"]) else "RUPTURE DE PENTE (%d points)" % (r["breaks"].size() + r["steep"].size())
			lines.append("%s : %.0f m · pente max %d %% · %s" % [r["id"], r["length_m"], roundi(float(r["max_grade"]) * 100.0), tag])
		for pr in p.problems():
			lines.append("⚠ " + pr)
		var sr := PlanTerrain.start_report(p, doc.field) if doc.field != null else {"ok": true}
		if not bool(sr["ok"]):
			lines.append("⚠ Départ : " + String(sr["reason"]))
	_status.text = "\n".join(lines)

## Termine une opération structurelle (recalcule le relief du plan) et rafraîchit tout.
func _end_op(_structural: bool) -> void:
	_busy = true
	var err := doc.finish_op()
	_busy = false
	if err != "":
		say(err)
	else:
		say(doc.message)
	_refresh(true)

# ------------------------------------------------------------------ barre du haut

func _on_blank() -> void:
	doc = MapDoc.blank("Nouvelle île dessinée")
	_selected_path = ""
	canvas.draft_outline = []
	canvas.draft_path = []
	select_tool("contour")
	_refresh(true)
	canvas.view_center = Vector2.ZERO
	canvas.px_per_m = 12.0
	say("Canevas vide : tracez le contour de l'île (clics, Entrée pour fermer).")

func _on_generate() -> void:
	var p := PlanGenerator.generate(int(_g_seed.value), float(_g_w.value), float(_g_l.value))
	doc = MapDoc.from_plan(p)
	_refresh(true)
	canvas.fit()
	say("Plan généré : %s" % p.name)

func _on_undo() -> void:
	var what := doc.undo()
	if what == "":
		say("Rien à annuler.")
		return
	_selected_path = ""
	canvas.selected_path = ""
	say(doc.message)
	_refresh(true)

func _on_verify() -> void:
	if doc.field == null:
		say("Tracez d'abord un contour : il n'y a pas encore d'île à explorer.")
		return
	App.open(App.MAP_ISLAND_SCENE, {"plan": doc.plan, "from_editor": true})

# ------------------------------------------------------------------ dialogues (exporter / ouvrir)

func _open_dialog(which: String) -> void:
	_close_dialog()
	_dialog = Control.new()
	_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dialog)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog.add_child(shade)
	var panel := MenuStyle.panel(Vector2(640, 420))
	_dialog.add_child(panel)
	var box := panel.get_child(0) as VBoxContainer
	DirAccess.make_dir_recursive_absolute(DIR)
	if which == "export":
		box.add_child(MenuStyle.title("Exporter la carte", 28))
		box.add_child(_label("La carte (plan, chemins, retouches de relief et de matières, repères, masques) est enregistrée dans un fichier .json versionné.", 15))
		var le := LineEdit.new()
		le.name = "Nom"
		le.text = String(doc.plan.name).to_lower().replace(" ", "_").replace("·", "").replace("×", "x").replace("__", "_")
		le.add_theme_font_size_override("font_size", 18)
		box.add_child(le)
		var info := _label("Dossier : %s" % ProjectSettings.globalize_path(DIR), 13, MenuStyle.MUTED)
		info.name = "Info"
		box.add_child(info)
		var go := MenuStyle.button("Enregistrer")
		go.pressed.connect(func() -> void: export_as(le.text))
		box.add_child(go)
	else:
		box.add_child(MenuStyle.title("Ouvrir une carte", 28))
		var list := ItemList.new()
		list.name = "Liste"
		list.custom_minimum_size = Vector2(0, 190)
		list.add_theme_font_size_override("font_size", 17)
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".json"):
				list.add_item(f)
		box.add_child(list)
		var info2 := _label("Dossier : %s" % ProjectSettings.globalize_path(DIR), 13, MenuStyle.MUTED)
		info2.name = "Info"
		box.add_child(info2)
		var go2 := MenuStyle.button("Ouvrir la carte choisie")
		go2.pressed.connect(func() -> void:
			if list.get_selected_items().is_empty():
				info2.text = "Choisissez une carte dans la liste."
				return
			open_file(DIR + list.get_item_text(list.get_selected_items()[0])))
		box.add_child(go2)
		list.item_activated.connect(func(i: int) -> void: open_file(DIR + list.get_item_text(i)))
	var cancel := MenuStyle.button("Fermer")
	cancel.pressed.connect(_close_dialog)
	box.add_child(cancel)

func _close_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null

func export_as(name: String, show := true) -> Dictionary:
	var clean := name.strip_edges().replace("/", "_").replace("\\", "_")
	if clean == "":
		clean = "carte"
	if not clean.ends_with(".json"):
		clean += ".eclats-carte.json"
	var r := doc.export_to(DIR + clean)
	if bool(r["ok"]):
		say("Carte exportée : %s" % ProjectSettings.globalize_path(DIR + clean))
		if _dialog != null:
			var info := _dialog.find_child("Info", true, false) as Label
			if info:
				info.text = "Enregistré : %s" % ProjectSettings.globalize_path(DIR + clean)
	else:
		say(String(r["error"]))
	return r

## Ouvre un fichier ; en cas d'erreur l'île ouverte est gardée et l'erreur expliquée (dans le dialogue et le panneau).
func open_file(path: String) -> Dictionary:
	var keep := doc
	var d := MapDoc.new()
	d.plan = IslandPlan.blank("tmp")
	var r := d.open_from(path)
	if not bool(r["ok"]):
		doc = keep
		say("Ouverture impossible : %s L'île actuelle est conservée." % r["error"])
		if _dialog != null:
			var info := _dialog.find_child("Info", true, false) as Label
			if info:
				info.text = "Ouverture impossible : %s" % r["error"]
		return r
	doc = d
	_close_dialog()
	_selected_path = ""
	canvas.draft_outline = []
	canvas.draft_path = []
	_refresh(true)
	canvas.fit()
	say("Carte ouverte : %s (%d retouches de relief, masque %d)" % [doc.plan.name, doc.plan.layers.count_delta() if doc.plan.layers else 0, doc.plan.layers.count_mask() if doc.plan.layers else 0])
	return r

# ------------------------------------------------------------------ clavier

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _dialog != null:
		return
	if key.keycode == KEY_Z and key.ctrl_pressed:
		_on_undo()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_finish_drafts(true)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and (not canvas.draft_outline.is_empty() or not canvas.draft_path.is_empty() or _dragging):
		_finish_drafts(false)
		if _dragging:
			doc.cancel_op()
			_dragging = false
			_refresh(true)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_DELETE:
		_delete_selected()
	elif key.keycode == KEY_R and tool == "maisons":
		_rotate_house()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_9 and not key.ctrl_pressed and not (get_viewport().gui_get_focus_owner() is LineEdit):
		select_tool(TOOLS[key.keycode - KEY_1][0])

## Termine (accept) ou abandonne un tracé en cours (contour ou chemin).
func _finish_drafts(accept: bool) -> void:
	if not canvas.draft_outline.is_empty():
		var pts := canvas.draft_outline.duplicate()
		canvas.draft_outline = []
		_new_outline = false
		canvas.hint = ""
		if accept and pts.size() >= 3:
			doc.begin_op("Tracer le contour")
			doc.set_outline(pts)
			_end_op(true)
			if doc.field != null:
				canvas.fit()
				select_tool("zones")
		elif accept:
			say("Un contour demande au moins 3 points.")
	if not canvas.draft_path.is_empty():
		var pts2 := canvas.draft_path.duplicate()
		canvas.draft_path = []
		canvas.hint = ""
		if accept and pts2.size() >= 2:
			doc.begin_op("Tracer un chemin")
			_selected_path = doc.add_path(pts2, path_width)
			canvas.selected_path = _selected_path
			_end_op(true)
		elif accept:
			say("Un chemin demande au moins 2 points.")
	canvas.queue_redraw()

# ------------------------------------------------------------------ souris

func _on_canvas_event(event: InputEvent) -> void:
	if _dialog != null or _busy:
		return
	if event is InputEventMouseMotion:
		var pos := canvas.s2w((event as InputEventMouseMotion).position)
		canvas.cursor_world = pos
		_on_motion(pos)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var pos := canvas.s2w(mb.position)
		canvas.cursor_world = pos
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_lmb = mb.pressed
			if mb.pressed:
				_on_press(pos, mb.double_click, mb.position)
			else:
				_on_release(pos)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_on_right(pos, mb.position)

func _snap(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, 0.5), snappedf(p.y, 0.5))

func _hit_radius_m() -> float:
	return 11.0 / canvas.px_per_m

func _near_outline_vertex(p: Vector2) -> int:
	for i in doc.plan.outline.size():
		if p.distance_to(doc.plan.outline[i]) <= _hit_radius_m():
			return i
	return -1

func _near_path_point(p: Vector2) -> Array:
	for pa in doc.plan.paths:
		var pts: Array = pa["pts"]
		for k in pts.size():
			if p.distance_to(pts[k]) <= _hit_radius_m():
				return [String(pa["id"]), k]
	return []

func _near_path_segment(p: Vector2) -> Array:
	var best := []
	var bd := 1.0e9
	for pa in doc.plan.paths:
		var pts: Array = pa["pts"]
		for k in range(pts.size() - 1):
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < maxf(float(pa["width"]) * 0.5, _hit_radius_m()) and d < bd:
				bd = d
				best = [String(pa["id"]), k]
	return best

func _near_landmark(p: Vector2) -> String:
	for l in doc.plan.landmarks:
		if p.distance_to(l["pos"]) <= _hit_radius_m() * 1.3:
			return String(l["id"])
	return ""

func _on_press(p: Vector2, dbl: bool, _screen: Vector2) -> void:
	match tool:
		"maisons":
			_update_house_preview(p, true)
			place_house_here()
		"contour":
			if _new_outline or doc.plan.outline.size() < 3:
				if canvas.draft_outline.size() >= 3 and p.distance_to(canvas.draft_outline[0]) <= _hit_radius_m():
					_finish_drafts(true)
				else:
					canvas.draft_outline.append(_snap(p))
					canvas.hint = "Contour : %d points · Entrée ou clic sur le premier point pour fermer · Échap : abandonner" % canvas.draft_outline.size()
					canvas.queue_redraw()
				return
			var v := _near_outline_vertex(p)
			if v >= 0:
				doc.begin_op("Déplacer un point du contour")
				_dragging = true
				_drag_kind = "sommet"
				_drag_i = v
			elif dbl:
				var best := -1
				var bd := 1.0e9
				var o: Array = doc.plan.outline
				for i in o.size():
					var a: Vector2 = o[i]
					var b: Vector2 = o[(i + 1) % o.size()]
					var ab := b - a
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
					var d := p.distance_to(a + ab * t)
					if d < bd:
						bd = d
						best = i
				if bd <= _hit_radius_m() * 1.5:
					doc.begin_op("Ajouter un point au contour")
					doc.insert_outline_point(best, p)
					_end_op(true)
		"zones":
			if doc.field == null:
				say("Tracez d'abord le contour de l'île.")
				return
			doc.begin_op("Peindre une zone (%s)" % IslandPlan.KINDS[kind]["label"])
			_dragging = true
			_drag_kind = "zone"
			doc.add_zone_disc(kind, p, brush_radius)
			_last_dab = p
			canvas.queue_redraw()
		"chemins":
			var hit := _near_path_point(p)
			if canvas.draft_path.is_empty() and not hit.is_empty():
				_selected_path = hit[0]
				canvas.selected_path = _selected_path
				doc.begin_op("Déplacer un point de chemin")
				_dragging = true
				_drag_kind = "point"
				_drag_id = hit[0]
				_drag_i = hit[1]
				path_width = float(doc.plan.path_by_id(_selected_path)["width"])
				_build_options_keep()
			elif canvas.draft_path.is_empty() and dbl:
				var seg := _near_path_segment(p)
				if not seg.is_empty():
					doc.begin_op("Ajouter un point au chemin")
					doc.insert_path_point(seg[0], seg[1], p)
					_end_op(true)
			elif canvas.draft_path.is_empty() and not _near_path_segment(p).is_empty():
				_selected_path = _near_path_segment(p)[0]
				canvas.selected_path = _selected_path
				path_width = float(doc.plan.path_by_id(_selected_path)["width"])
				_build_options_keep()
				canvas.queue_redraw()
			else:
				if doc.field == null:
					say("Tracez d'abord le contour de l'île.")
					return
				canvas.draft_path.append(_snap(p))
				canvas.hint = "Chemin : %d points · Entrée ou clic droit pour terminer · Échap : abandonner" % canvas.draft_path.size()
				canvas.queue_redraw()
		"reperes":
			if _drag_kind == "depart":
				doc.begin_op("Placer le départ")
				doc.set_start(p)
				_drag_kind = ""
				canvas.hint = ""
				_end_op(false)
				return
			var id := _near_landmark(p)
			if id != "":
				_selected_lm = id
				canvas.selected_landmark = id
				doc.begin_op("Déplacer un repère")
				_dragging = true
				_drag_kind = "repere"
				_drag_id = id
			elif doc.field != null:
				doc.begin_op("Poser un repère")
				_selected_lm = doc.add_landmark(lm_kind, p, lm_label)
				canvas.selected_landmark = _selected_lm
				_end_op(false)
		"relief", "matiere", "masque":
			if doc.field == null:
				say("Tracez d'abord le contour de l'île.")
				return
			_begin_brush(p, false)
		"regen":
			_dragging = true
			_drag_kind = "selection"
			_sel_a = p
			canvas.sel_rect = Rect2(p, Vector2.ZERO)

func _build_options_keep() -> void:
	# met à jour le curseur de largeur sans perdre la sélection
	var keep := _selected_path
	_build_options()
	_selected_path = keep
	canvas.selected_path = keep

func _begin_brush(p: Vector2, erase: bool) -> void:
	var t := ""
	var label := ""
	match tool:
		"relief":
			t = relief_mode
			label = {"monter": "Monter le relief", "creuser": "Creuser le relief", "aplanir": "Aplanir le relief", "adoucir": "Adoucir le relief"}[relief_mode]
		"matiere":
			t = "gomme_matiere" if erase else "matiere"
			label = "Effacer la matière peinte" if erase else "Peindre la matière"
		"masque":
			t = "gomme_masque" if (erase or mask_mode == "gommer") else "masque"
			label = "Retirer la protection" if t == "gomme_masque" else "Protéger une zone (masque)"
	doc.stroke_begin(label, t, p)
	_stroke = true
	_drag_kind = t
	_last_dab = Vector2.INF
	_dab(p)

func _dab(p: Vector2) -> void:
	if not _stroke:
		return
	if _last_dab != Vector2.INF and _last_dab.distance_to(p) < maxf(brush_radius * 0.28, 0.15):
		return
	_last_dab = p
	var mat_id := pal.id(IslandPlan.MATERIALS[mat_index][0])
	var r := doc.stroke_dab(_drag_kind, p, brush_radius, brush_strength, mat_id)
	if r.size != Vector2i.ZERO:
		if _drag_kind in ["masque", "gomme_masque"]:
			canvas.refresh_mask_rect(doc.plan.layers, r)
		else:
			canvas.refresh_rect(r)

func _on_motion(p: Vector2) -> void:
	_update_cursor(p)
	if tool == "maisons":
		_update_house_preview(p)
	if _stroke and _lmb:
		_dab(p)
	elif _dragging:
		match _drag_kind:
			"sommet":
				doc.plan.outline[_drag_i] = _snap(p)
			"point":
				(doc.plan.path_by_id(_drag_id)["pts"] as Array)[_drag_i] = _snap(p)
			"repere":
				doc.move_landmark(_drag_id, p)
			"zone":
				if _last_dab.distance_to(p) >= brush_radius * 0.5:
					doc.add_zone_disc(kind, p, brush_radius)
					_last_dab = p
			"selection":
				canvas.sel_rect = Rect2(_sel_a, p - _sel_a).abs()
		canvas.queue_redraw()
	canvas.queue_redraw()

func _update_cursor(p: Vector2) -> void:
	canvas.cursor_radius = 0.0
	canvas.cursor_note = ""
	match tool:
		"zones":
			canvas.cursor_radius = brush_radius
			canvas.cursor_color = IslandPlan.KINDS[kind]["color"]
			canvas.cursor_note = String(IslandPlan.KINDS[kind]["label"]).get_slice(" (", 0)
		"relief":
			canvas.cursor_radius = brush_radius
			canvas.cursor_color = {"monter": Color(1.0, 0.62, 0.2), "creuser": Color(0.35, 0.7, 1.0), "aplanir": Color(0.5, 1.0, 0.5), "adoucir": Color(0.9, 0.8, 1.0)}[relief_mode]
			var nm: String = {"monter": "Monter", "creuser": "Creuser", "aplanir": "Aplanir", "adoucir": "Adoucir"}[relief_mode]
			canvas.cursor_note = "%s · rayon %.1f m · force %.0f %%" % [nm, brush_radius, brush_strength * 100.0]
			if doc.field != null:
				var g := doc.field.ground_at_m(p.x, p.y)
				if not is_nan(g):
					canvas.cursor_note += " · sol %.1f m" % g
		"matiere":
			canvas.cursor_radius = brush_radius
			canvas.cursor_color = Color(0.95, 0.85, 0.4)
			canvas.cursor_note = String(IslandPlan.MATERIALS[mat_index][1])
		"masque":
			canvas.cursor_radius = brush_radius
			canvas.cursor_color = Color(1.0, 0.25, 0.35) if mask_mode == "peindre" else Color(1, 1, 1)
			canvas.cursor_note = "Protéger" if mask_mode == "peindre" else "Retirer la protection"

func _on_release(p: Vector2) -> void:
	if _stroke:
		var r := doc.stroke_end()
		_stroke = false
		_drag_kind = ""
		if r.size != Vector2i.ZERO:
			canvas.refresh_mask(doc.plan.layers)
			say(doc.message)
		else:
			say("Aucun effet (zone protégée par le masque ou hors de l'île).")
		_refresh(false)
		return
	if not _dragging:
		return
	_dragging = false
	match _drag_kind:
		"sommet", "point", "repere", "zone":
			_end_op(true)
		"selection":
			canvas.sel_rect = Rect2(_sel_a, p - _sel_a).abs()
			if canvas.sel_rect.size.x < 0.5 or canvas.sel_rect.size.y < 0.5:
				canvas.sel_rect = Rect2()
			else:
				say("Sélection : %.1f × %.1f m. Cliquez « Régénérer le relief dans la sélection »." % [canvas.sel_rect.size.x, canvas.sel_rect.size.y])
	_drag_kind = ""
	canvas.queue_redraw()

func _on_right(p: Vector2, _screen: Vector2) -> void:
	match tool:
		"maisons":
			var hid := doc.house_at(p)
			if hid != "":
				doc.remove_house(hid)
				say(doc.message + " Ctrl+Z pour la remettre.")
				_refresh(true)
			else:
				say("Aucune maison à cet endroit.")
		"contour":
			if not canvas.draft_outline.is_empty():
				_finish_drafts(true)
			else:
				var v := _near_outline_vertex(p)
				if v >= 0:
					doc.begin_op("Retirer un point du contour")
					if doc.remove_outline_point(v):
						_end_op(true)
					else:
						doc.cancel_op()
						say("Un contour garde au moins 3 points.")
		"zones":
			doc.begin_op("Effacer une zone")
			doc.delete_zone_at(p)
			_end_op(true)
		"chemins":
			if not canvas.draft_path.is_empty():
				_finish_drafts(true)
			else:
				var hit := _near_path_point(p)
				if not hit.is_empty():
					doc.begin_op("Retirer un point de chemin")
					if doc.remove_path_point(hit[0], hit[1]):
						_end_op(true)
					else:
						doc.cancel_op()
						say("Un chemin garde au moins 2 points (Suppr pour le supprimer).")
		"reperes":
			var id := _near_landmark(p)
			if id != "":
				doc.begin_op("Retirer un repère")
				doc.delete_landmark(id)
				_end_op(false)
		"matiere":
			if doc.field != null:
				_begin_brush(p, true)
				_lmb = true
		"masque":
			if doc.field != null:
				_begin_brush(p, true)
				_lmb = true

func _clear_mask() -> void:
	if doc.field == null or doc.plan.layers.count_mask() == 0:
		return
	doc.begin_op("Retirer tout le masque")
	doc.plan.layers.mask.fill(0)
	_end_op(false)

func _do_regen() -> void:
	if canvas.sel_rect.size.x < 1.0:
		say("Tracez d'abord un rectangle de sélection (outil Régénérer, deux coins).")
		return
	_busy = true
	say("Régénération en cours…")
	var r := doc.regenerate(canvas.sel_rect, regen_variation if regen_variation > 0 else -1)
	_busy = false
	if bool(r["ok"]):
		say(doc.message)
	else:
		say(String(r["reason"]))
	_refresh(true)

## Retour du bouton droit relâché pour les gommes (le clic droit déclenche un trait ; il se termine au relâchement).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and not (event as InputEventMouseButton).pressed and _stroke:
		_lmb = false
		_on_release(canvas.cursor_world)
