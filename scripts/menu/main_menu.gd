extends Control
## Menu principal provisoire (Lot 6) : Jouer l'île d'ouverture · Générer une île · Outils développeur · Quitter.
## Seule la scène choisie est chargée (App.open) ; le menu lui-même ne contient aucun monde 3D.

const PROFILES := [["settled", "Colonie (habitée)"], ["verdant", "Verdoyante"], ["rocky", "Rocheuse"]]

## Scènes de prototype accessibles depuis « Outils développeur » : [libellé, scène, raccourci, note].
var DEV_SCENES := [
	["Île générée (Lot 4)", App.GENERATED_SCENE, "F9", "génération structurelle, caméra libre"],
	["Colonie (Lot 3)", "res://scenes/island/colony_island.tscn", "F4", "village du Lot 3"],
	["Première île (Lot 2)", "res://scenes/island/first_island.tscn", "F2", "terrain voxel simple"],
	["Laboratoire graphique (Lot 1)", "res://scenes/lab/graphics_lab.tscn", "F1", "matériaux, assets, dioramas"],
	["Galerie de matériaux", "res://scenes/lab/material_gallery.tscn", "F8", "rangées de matériaux"],
]

var _pages := {}
var _page := ""
var _profile: OptionButton
var _seed: SpinBox

func _ready() -> void:
	App.current_path = App.MENU_SCENE
	App.capture_on_resume = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = MenuStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# bandeau en dégradé (ciel → nuit) et silhouette d'îles flottantes
	var sky := TextureRect.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.20, 0.34, 0.50), Color(0.10, 0.15, 0.24), Color(0.06, 0.08, 0.12)])
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	sky.texture = gt
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sky)
	add_child(_islands())
	var head := VBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 46
	head.add_theme_constant_override("separation", 2)
	add_child(head)
	head.add_child(MenuStyle.title("ÉCLATS", 78))
	head.add_child(MenuStyle.note("Un RPG d'exploration et de construction sur des îles flottantes", 20))
	_pages["main"] = _page_main()
	_pages["generate"] = _page_generate()
	_pages["dev"] = _page_dev()
	for k in _pages:
		add_child(_pages[k])
	var foot := MenuStyle.note("Menu provisoire · Lot 6", 14)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -34
	foot.offset_bottom = -10
	add_child(foot)
	show_page("main")

func _islands() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var s := c.size
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for k in 9:
			var cx := rng.randf_range(0.05, 0.95) * s.x
			var cy := rng.randf_range(0.55, 0.92) * s.y
			var w := rng.randf_range(0.08, 0.20) * s.x
			var h := w * rng.randf_range(0.25, 0.4)
			var top := PackedVector2Array([Vector2(cx - w, cy), Vector2(cx - w * 0.6, cy - h * 0.35), Vector2(cx, cy - h * 0.45), Vector2(cx + w * 0.7, cy - h * 0.3), Vector2(cx + w, cy)])
			var under := PackedVector2Array([Vector2(cx - w, cy), Vector2(cx + w, cy), Vector2(cx + w * 0.4, cy + h * 1.1), Vector2(cx, cy + h * 1.6), Vector2(cx - w * 0.45, cy + h * 0.9)])
			var a := rng.randf_range(0.30, 0.55)
			c.draw_colored_polygon(under, Color(0.10, 0.13, 0.18, a))
			c.draw_colored_polygon(top, Color(0.18, 0.28, 0.24, a)))
	return c

func show_page(name: String) -> void:
	_page = name
	for k in _pages:
		(_pages[k] as Control).visible = (k == name)
	var first := (_pages[name] as Control).find_child("Premier", true, false) as Control
	if first and DisplayServer.get_name() != "headless":
		first.grab_focus()

func _page_main() -> Control:
	var p := MenuStyle.panel(Vector2(460, 340))
	p.position.y += 70
	var box := p.get_child(0) as VBoxContainer
	var b1 := MenuStyle.button("Jouer l'île d'ouverture")
	b1.name = "Premier"
	b1.pressed.connect(play_opening)
	box.add_child(b1)
	var b2 := MenuStyle.button("Générer une île")
	b2.pressed.connect(show_page.bind("generate"))
	box.add_child(b2)
	var b3 := MenuStyle.button("Outils développeur")
	b3.pressed.connect(show_page.bind("dev"))
	box.add_child(b3)
	var b4 := MenuStyle.button("Quitter")
	b4.pressed.connect(get_tree().quit)
	box.add_child(b4)
	box.add_child(MenuStyle.note("Première personne · ZQSD/WASD, souris, Espace, Maj · Échap : pause"))
	p.name = "PageMain"
	return p

func _page_generate() -> Control:
	var p := MenuStyle.panel(Vector2(520, 420))
	p.position.y += 70
	var box := p.get_child(0) as VBoxContainer
	box.add_child(MenuStyle.title("Générer une île", 32))
	box.add_child(MenuStyle.note("Générateur du Lot 4 · l'île est calculée à l'ouverture (quelques secondes)."))
	var row := HBoxContainer.new()
	box.add_child(row)
	var l1 := Label.new()
	l1.text = "Type d'île"
	l1.custom_minimum_size = Vector2(150, 0)
	row.add_child(l1)
	_profile = OptionButton.new()
	for pr in PROFILES:
		_profile.add_item(pr[1])
	_profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_profile)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	var l2 := Label.new()
	l2.text = "Graine"
	l2.custom_minimum_size = Vector2(150, 0)
	row2.add_child(l2)
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 99999
	_seed.value = 3
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_seed)
	var go := MenuStyle.button("Générer")
	go.name = "Premier"
	go.pressed.connect(func() -> void: generate(PROFILES[_profile.selected][0], int(_seed.value)))
	box.add_child(go)
	var back := MenuStyle.button("Retour")
	back.pressed.connect(show_page.bind("main"))
	box.add_child(back)
	p.name = "PageGenerate"
	return p

func _page_dev() -> Control:
	var p := MenuStyle.panel(Vector2(700, 600))
	p.position.y += 60
	var box := p.get_child(0) as VBoxContainer
	box.add_theme_constant_override("separation", 8)
	box.add_child(MenuStyle.title("Outils développeur", 32))
	var first := true
	for e in DEV_SCENES:
		var b := MenuStyle.button(String(e[0]) + ("   [%s]" % e[2] if String(e[2]) != "" else ""))
		b.tooltip_text = String(e[3])
		if first:
			b.name = "Premier"
			first = false
		b.pressed.connect(App.open.bind(String(e[1])))
		box.add_child(b)
	var back := MenuStyle.button("Retour")
	back.pressed.connect(show_page.bind("main"))
	box.add_child(back)
	p.name = "PageDev"
	return p

func play_opening() -> void:
	App.open(App.OPENING_SCENE)

func generate(profile: String, seed: int) -> void:
	App.open(App.GENERATED_SCENE, {"profile": profile, "seed": seed})
