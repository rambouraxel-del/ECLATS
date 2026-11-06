class_name LabController
extends Node
## Logique commune du panneau et de la barre de commandes : UNE sélection, UNE logique.
## request() prépare une génération sur la sélection courante et montre l'aperçu ; confirm() l'applique ; cancel_preview()
## l'abandonne ; undo() annule la dernière opération entière ; recipe() / copy_recipe() donnent la recette reproductible.

signal message(text: String, level: String)         # level : info | ok | erreur
signal state_changed

const RECIPE_FILE := "user://lab_recette.txt"

var lab: LabWorld
var sel: LabSelection
var player: Node3D
var pending := {}                  # opération préparée, en attente de confirmation
var last_recipe := {}              # recette de la dernière opération préparée ou appliquée
var ghost: Node3D
var history: Array[String] = []   # historique lisible (pour les essais)

func _say(text: String, level := "info") -> void:
	history.append("[%s] %s" % [level, text])
	message.emit(text, level)

# ------------------------------------------------------------------ commandes (barre T) — même logique que le panneau

func run_command(line: String) -> Dictionary:
	var p := LabCommands.parse(line)
	if not p["ok"]:
		_say(String(p["error"]), "erreur")
		return {"ok": false, "reason": p["error"]}
	var o: Dictionary = p["opts"]
	match String(p["cmd"]):
		"generer":
			return request(String(p["gen"]), o)
		"aplanir":
			return request("aplanir", o)
		"confirmer":
			return await confirm()
		"annuler":
			cancel_preview()
			return {"ok": true}
		"defaire":
			return await undo()
		"recette":
			var s := copy_recipe()
			return {"ok": s != "", "recipe": s}
		"rejouer":
			return await replay_saved_recipe()
		"rect":
			var a: Array = p["args"]
			if a.size() < 2:
				_say("Usage : /rect LARGEUR PROFONDEUR (mètres), par exemple /rect 3.5 3.5", "erreur")
				return {"ok": false}
			var c := sel.point_or_aim()
			if c.x > 1.0e8:
				_say("Visez le sol pour placer le rectangle.", "erreur")
				return {"ok": false}
			sel.set_tool(LabSelection.Tool.RECT)
			sel.set_rect_centered(c, Vector2(LabCommands._num(String(a[0])), LabCommands._num(String(a[1]))))
			_say("Rectangle %s." % sel.info_text().replace("Rectangle ", ""), "ok")
			return {"ok": true}
		"point":
			var a2: Array = p["args"]
			sel.set_tool(LabSelection.Tool.POINT)
			if a2.size() >= 2:
				sel.set_point(Vector2(LabCommands._num(String(a2[0])), LabCommands._num(String(a2[1]))))
			else:
				sel.set_point(sel.snap(sel.aim_xz()))
			_say(sel.info_text(), "ok")
			return {"ok": true}
		"pinceau":
			var a3: Array = p["args"]
			sel.set_tool(LabSelection.Tool.BRUSH)
			if a3.size() >= 1:
				sel.brush_radius = clampf(LabCommands._num(String(a3[0])), 0.4, 4.0)
			_say("Pinceau : rayon %.1f m." % sel.brush_radius, "ok")
			return {"ok": true}
		"effacer":
			cancel_preview()
			sel.clear_all()
			_say("Sélections effacées.")
			return {"ok": true}
		"aide":
			_say(LabCommands.HELP)
			return {"ok": true}
	return {"ok": false}

# ------------------------------------------------------------------ génération

func request(gen: String, o: Dictionary) -> Dictionary:
	cancel_preview(false)
	var recipe := {"gen": gen, "opts": {}}
	var op := {}
	match gen:
		"arbre":
			var p := sel.point_or_aim()
			if p.x > 1.0e8:
				return _refuse("Aucun point : visez le sol (outil Point, clic) ou utilisez /point x z.")
			var species := String(o.get("espece", "oak"))
			var seed := int(o.get("seed", 1))
			recipe["opts"] = {"espece": species, "seed": seed}
			op = lab.prepare_tree(p, species, seed)
		"rocher":
			var p2 := sel.point_or_aim()
			if p2.x > 1.0e8:
				return _refuse("Aucun point : visez le sol (outil Point, clic) ou utilisez /point x z.")
			var fam := String(o.get("famille", "boulder"))
			var seed2 := int(o.get("seed", 1))
			var k := float(o.get("echelle", 1.0))
			recipe["opts"] = {"famille": fam, "seed": seed2, "echelle": k}
			op = lab.prepare_rock(p2, fam, seed2, k)
		"maison":
			var r := Rect2()
			if o.has("emprise"):
				var dims: Vector2 = o["emprise"]
				var c := sel.rect_m().get_center() if sel.has_rect() else sel.point_or_aim()
				if c.x > 1.0e8:
					return _refuse("Aucune emprise : sélectionnez un rectangle ou visez le sol pour y poser l'emprise demandée.")
				r = Rect2(sel.snap(c - dims * 0.5), dims)
				if not sel.has_rect():
					sel.set_tool(LabSelection.Tool.RECT)
				sel.set_rect(r.position, r.position + dims)
			elif sel.has_rect():
				r = sel.rect_m()
			else:
				return _refuse("Aucun rectangle : choisissez l'outil Rectangle (2 clics), tapez /rect 3.5 3.5, ou ajoutez --emprise 3.5x3.5.")
			var yaw := int(o["yaw"]) if o.has("yaw") else _auto_yaw(r.get_center())
			var params := {"seed": int(o.get("seed", 1)), "yaw": yaw}
			for k2 in ["murs", "toit"]:
				if o.has(k2):
					params[k2] = o[k2]
			recipe["opts"] = params.duplicate()
			recipe["opts"]["emprise"] = r.size
			op = lab.prepare_house(r, params)
			op["summary"] = "Maison"
		"aplanir":
			if sel.brush_cells.is_empty() and o.has("trace"):
				var origin := sel.snap(sel.aim_xz()) if sel.aim.x < 1.0e8 else Vector2.ZERO
				if o.has("origin"):
					origin = o["origin"]
				sel.set_tool(LabSelection.Tool.BRUSH)
				sel.paint_trace(origin, o["trace"], float(o.get("rayon", sel.brush_radius)))
			if o.has("rayon"):
				sel.brush_radius = float(o["rayon"])
			if sel.brush_cells.is_empty():
				return _refuse("Aucune zone : peignez avec l'outil Pinceau (clic maintenu) ou donnez --trace.")
			var params2 := {}
			if o.has("niveau"):
				params2["niveau"] = o["niveau"]
			var ro := {"rayon": sel.brush_radius, "trace": sel.stroke_relative()}
			if o.has("niveau"):
				ro["niveau"] = o["niveau"]
			recipe["opts"] = ro
			op = lab.prepare_flatten(sel.brush_cells.keys(), params2)
			sel.show_flatten(op)
		_:
			return _refuse("Générateur inconnu : " + gen)
	op["recipe"] = recipe
	last_recipe = recipe
	if not bool(op.get("ok", false)):
		pending = {}
		_show_refusal(op)
		state_changed.emit()
		return {"ok": false, "reason": "; ".join(op.get("reasons", [])), "op": op}
	pending = op
	_make_ghost(op)
	var what := LabWorld.describe(op)
	if what == "":
		what = String(op.get("summary", gen))
	_say("Aperçu prêt · %s\nEntrée : confirmer · X : annuler l'aperçu" % what, "ok")
	state_changed.emit()
	return {"ok": true, "op": op}

func _auto_yaw(center: Vector2) -> int:
	# la porte (façade +z locale) regarde vers le joueur
	if player == null:
		return 0
	var d := Vector2(player.global_position.x, player.global_position.z) - center
	var best := 0
	var bd := -2.0
	for y in 4:
		var f := Vector2(sin(y * PI * 0.5), cos(y * PI * 0.5))
		var dot := f.dot(d.normalized()) if d.length() > 0.01 else 0.0
		if dot > bd:
			bd = dot
			best = y
	return best

func _refuse(text: String) -> Dictionary:
	_say(text, "erreur")
	return {"ok": false, "reason": text}

func _show_refusal(op: Dictionary) -> void:
	var rs: Array = op.get("reasons", [])
	_say("Impossible : %s\nRien n'est modifié." % " ".join(PackedStringArray(rs)), "erreur")
	if op.get("kind", "") == "flatten":
		sel.show_flatten(op)

func cancel_preview(announce := true) -> void:
	var had := not pending.is_empty()
	pending = {}
	if is_instance_valid(ghost):
		ghost.get_parent().remove_child(ghost)
		ghost.queue_free()
	ghost = null
	sel.reset_flatten_colors()
	if had and announce:
		_say("Aperçu annulé.")
	state_changed.emit()

func confirm() -> Dictionary:
	if pending.is_empty():
		return _refuse("Rien à confirmer : lancez d'abord un aperçu (/generer … ou bouton Aperçu).")
	var op := pending
	var r: Dictionary = await lab.apply(op)
	if not bool(r.get("ok", false)):
		_say("Refusé : %s" % r.get("reason", "?"), "erreur")
		return r
	cancel_preview(false)
	if String(op["kind"]) == "flatten":
		sel.clear_brush()
	sel.refresh_visuals()
	last_recipe = op["recipe"]
	_say("Appliqué · %s · Ctrl+Z pour annuler" % _summary(op), "ok")
	state_changed.emit()
	return r

func _summary(op: Dictionary) -> String:
	var d := LabWorld.describe(op)
	return d if d != "" else String(op.get("summary", op["kind"]))

func undo() -> Dictionary:
	if not pending.is_empty():
		cancel_preview()
		return {"ok": true, "reason": "aperçu annulé"}
	var r: Dictionary = await lab.undo()
	if not bool(r.get("ok", false)):
		_say(String(r.get("reason", "Rien à annuler.")), "erreur")
		return r
	sel.refresh_visuals()
	_say("Annulé : %s (terrain, raccord au sol et collisions restaurés)" % String(r["entry"].get("summary", "opération")), "ok")
	state_changed.emit()
	return r

# ------------------------------------------------------------------ recettes

func recipe_text() -> String:
	return LabCommands.recipe_string(last_recipe) if not last_recipe.is_empty() else ""

func copy_recipe() -> String:
	var s := recipe_text()
	if s == "":
		_say("Aucune recette : générez d'abord quelque chose.", "erreur")
		return ""
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(s)
	var f := FileAccess.open(RECIPE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(s)
		f.close()
	_say("Recette copiée : %s" % s, "ok")
	return s

func saved_recipe() -> String:
	if FileAccess.file_exists(RECIPE_FILE):
		return FileAccess.get_file_as_string(RECIPE_FILE).strip_edges()
	return ""

## Rejoue la dernière recette copiée (fichier) sur la sélection courante de CE terrain.
func replay_saved_recipe() -> Dictionary:
	var s := saved_recipe()
	if s == "":
		return _refuse("Aucune recette copiée pour l'instant.")
	_say("Recette rejouée : %s" % s)
	return await run_command(s)

# ------------------------------------------------------------------ aperçu 3D

func _make_ghost(op: Dictionary) -> void:
	var g := Node3D.new()
	g.name = "Apercu"
	match String(op["kind"]):
		"tree", "rock":
			g.add_child((op["node_fn"] as Callable).call())
		"house":
			var n := BuildingView.create_node(op["model"], op["arrays"], [30.0, 80.0])
			n.transform = op["xform"]
			g.add_child(n)
			# plateforme prévue : cour ramenée au niveau fini
			var yard: Rect2i = op["yard"]
			var f := lab.field
			var c0 := f.center_m(yard.position.x, yard.position.y)
			var c1 := f.center_m(yard.end.x - 1, yard.end.y - 1)
			var size := Vector3(c1.x - c0.x + LabWorld.V, 0.03, c1.y - c0.y + LabWorld.V)
			var pad := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			pad.mesh = bm
			pad.position = Vector3((c0.x + c1.x) * 0.5, float(op["target_m"]) + 0.02, (c0.y + c1.y) * 0.5)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.3, 0.95, 0.45, 0.28)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pad.material_override = m
			pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.add_child(pad)
	_ghostify(g)
	lab.add_child(g)
	ghost = g

var _ghost_mat: StandardMaterial3D

## Aperçu : voile vert translucide par-dessus le modèle (les matériaux voxel ne gèrent pas la transparence d'instance).
func _ghostify(n: Node) -> void:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.albedo_color = Color(0.25, 0.95, 0.5, 0.30)
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.render_priority = 3
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == null:
			(c as GeometryInstance3D).material_overlay = _ghost_mat
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghostify(c)
