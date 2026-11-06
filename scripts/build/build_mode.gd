class_name BuildMode
extends Node
## MODE CONSTRUCTION EN PREMIÈRE PERSONNE (Lot 8) — dans le laboratoire (salle grise = atelier, île vide = pente).
##   B : entrer / sortir · 1-8 : outils (sol, fondations, mur, porte, fenêtre, pièce, toit, modifier)
##   clic gauche : coin / cible · clic droit : revenir en arrière · Entrée : confirmer · X : annuler l'aperçu · Ctrl+Z : défaire
##   PageUp / PageDown : niveau · H : hauteur du mur · G : hauteur de la pièce · O : côté de la porte · M : matière
##   modifier : clic = choisir un mur / sol / toit · J raccourcir · K prolonger · Y changer d'extrémité · Suppr retirer
## Chaque pose est PRÉPARÉE (ConstructionOps), montrée en aperçu aimanté (grille 0,50 m et bords des éléments posés) avec ses
## dimensions et son coût, puis CONFIRMÉE : le stock de démonstration n'est débité qu'à la confirmation.

signal message(text: String, level: String)
signal changed

const C := preload("res://scripts/build/construction.gd")
const DEMO_STOCK := 200
const DIR := "user://maisons/"
const SNAP_EDGE_M := 0.3
const REACH := 14.0
const TOOLS := [["sol", "Sol"], ["fondations", "Fondations"], ["mur", "Mur"], ["porte", "Porte"], ["fenetre", "Fenêtre"],
	["piece", "Pièce"], ["toit", "Toit"], ["modifier", "Modifier"]]
const SIDE_LABELS := ["Sud", "Est", "Nord", "Ouest"]

var lab: LabWorld
var camera: Camera3D
var player: Node3D
var lab_ui: LabUi
var sel: LabSelection
var active := false
var c: Construction = Construction.new()
var stock := DEMO_STOCK
var tool := "mur"
var level := 0
var wall_h := 2.5
var door_side := "S"
var wall_mat := "bois"
var floor_mat := "planches"
var roof_mat := "tuiles"
var has_corner := false
var corner := Vector2i.ZERO
var aim := Vector3.INF
var aim_override := Vector3.INF            # essais automatiques : remplace le point visé
var aim_u := Vector2i.ZERO
var aim_snap := ""
var pending: Dictionary = {}               # opération verrouillée, en attente de confirmation
var live: Dictionary = {}                  # opération montrée en direct (pas encore verrouillée)
var sel_id := -1
var edit_end := "B"
var undo_stack: Array[Dictionary] = []
var history: Array[String] = []
var node: Node3D
var spent_total := 0

var _ghost: Node3D
var _ghost_key := ""
var _marker: MeshInstance3D
var _label3d: Label3D
var _layer: CanvasLayer
var _panel: PanelContainer
var _hint: Label
var _toast: Label
var _toast_t := 0.0
var _stock_label: Label
var _level_label: Label
var _tool_btns := {}
var _h_opt: OptionButton
var _side_opt: OptionButton
var _wall_opt: OptionButton
var _floor_opt: OptionButton
var _roof_opt: OptionButton
var _lmb_ready := false
var _was_captured := false
var _refusal: Dictionary = {}
var _refusal_t := 0.0
var _file_dialog: Control
var _file_name: LineEdit
var _file_list: OptionButton
var _file_msg: Label
var _marker_mat: StandardMaterial3D

func setup(p_lab: LabWorld, p_cam: Camera3D, p_player: Node3D, p_ui: LabUi, p_sel: LabSelection) -> void:
	lab = p_lab
	camera = p_cam
	player = p_player
	lab_ui = p_ui
	sel = p_sel
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = Color(1, 1, 1, 0.9)
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.no_depth_test = true
	_marker_mat.render_priority = 4
	_marker = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.5, 0.1)
	_marker.mesh = bm
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	lab.add_child(_marker)
	_label3d = Label3D.new()
	_label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label3d.no_depth_test = true
	_label3d.font_size = 52
	_label3d.pixel_size = 0.004
	_label3d.outline_size = 14
	_label3d.outline_modulate = Color(0.05, 0.1, 0.15, 0.95)
	_label3d.render_priority = 6
	_label3d.visible = false
	lab.add_child(_label3d)
	_build_ui()
	_layer.visible = false
	set_process(false)
	set_process_unhandled_input(false)

# ------------------------------------------------------------------ activation

func enter() -> void:
	if active:
		return
	active = true
	if sel != null:
		sel.enabled = false
		sel.visible = false
	lab_ui.suspended = true
	lab_ui.panel.visible = false
	lab_ui.msg.visible = false
	_layer.visible = true
	set_process(true)
	set_process_unhandled_input(true)
	_refresh_ui()
	_say("Mode construction · 1-8 outils · clic pour tracer · Entrée pour confirmer · B pour sortir", "info")

func leave() -> void:
	if not active:
		return
	active = false
	_cancel_all()
	if sel != null:
		sel.enabled = true
		sel.visible = true
	lab_ui.suspended = false
	lab_ui.panel.visible = true
	_layer.visible = false
	_clear_ghost()
	_marker.visible = false
	_label3d.visible = false
	set_process(false)
	set_process_unhandled_input(false)

func _say(text: String, level_name := "info") -> void:
	history.append("[%s] %s" % [level_name, text])
	message.emit(text, level_name)
	if _toast != null:
		_toast.text = text
		_toast.visible = true
		_toast_t = 0.0
		_toast.add_theme_color_override("font_color", {"info": Color(0.9, 0.95, 1.0), "ok": Color(0.55, 1.0, 0.65), "erreur": Color(1.0, 0.55, 0.5)}.get(level_name, Color.WHITE))

# ------------------------------------------------------------------ état

func set_tool(t: String) -> void:
	if tool == t:
		return
	_cancel_all()
	tool = t
	sel_id = -1
	_refresh_ui()

func set_level(lv: int) -> void:
	lv = clampi(lv, 0, C.MAX_LEVELS - 1)
	if lv > 0 and c.is_empty():
		_say("Posez d'abord un sol au rez-de-chaussée : un étage doit reposer sur un niveau.", "erreur")
		return
	if lv > c.level_count():
		_say("Construisez d'abord le niveau %d." % (level + 1), "erreur")
		return
	if lv == level:
		return
	_cancel_all()
	level = lv
	_apply_fade()
	_refresh_ui()

func _apply_fade() -> void:
	if node != null:
		ConstructionView.set_active_level(node, level if (c.level_count() > 1 or level > 0) else -1)

func _cancel_all() -> void:
	pending = {}
	live = {}
	has_corner = false
	_refusal = {}
	_clear_ghost()

func cancel_preview() -> void:
	if not pending.is_empty():
		pending = {}
		_say("Aperçu annulé : rien n'a été débité.")
	elif has_corner:
		has_corner = false
	elif sel_id >= 0:
		sel_id = -1
	_refusal = {}
	live = {}
	_clear_ghost()

## Essais : remet l'atelier à zéro sans toucher au monde.
func leave_state_reset_for_test() -> void:
	c = Construction.new()
	undo_stack.clear()
	pending = {}
	has_corner = false
	level = 0
	sel_id = -1
	_rebuild()

func _work() -> Construction:
	if not c.is_empty():
		return c
	var w := Construction.new()
	w.name = c.name
	var p := Vector2(corner) * C.U if has_corner else Vector2(aim.x, aim.z)
	var g := lab.ground_y(p.x, p.y)
	w.base_y = snappedf(0.0 if is_nan(g) else g, 0.2)
	return w

# ------------------------------------------------------------------ visée

func _ray() -> Dictionary:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	return {"o": from, "d": dir}

func _update_aim() -> void:
	if aim_override.x < 1.0e8:
		aim = aim_override
	else:
		var r := _ray()
		var from: Vector3 = r["o"]
		var dir: Vector3 = r["d"]
		aim = Vector3.INF
		if level > 0 and not c.is_empty():
			var y := c.level_y(level)
			if absf(dir.y) > 1.0e-4:
				var t := (y - from.y) / dir.y
				if t > 0.0 and t < REACH * 2.0:
					aim = from + dir * t
		else:
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH * 2.0, 1)
			var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				aim = hit["position"]
	aim_snap = ""
	if aim.x > 1.0e8:
		return
	var best := Vector2i(roundi(aim.x / C.U), roundi(aim.z / C.U))
	aim_snap = "grille"
	var d_best := SNAP_EDGE_M
	var here := Vector2(aim.x, aim.z)
	for p in _snap_points():
		var d := here.distance_to(Vector2(p) * C.U)
		if d < d_best:
			d_best = d
			best = p
			aim_snap = "bord"
	aim_u = best

## Coins et extrémités des éléments posés (toutes hauteurs) : points d'aimantation.
func _snap_points() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in c.elements:
		match String(e["t"]):
			"floor", "foundation", "roof":
				out.append(Vector2i(int(e["x0"]), int(e["z0"])))
				out.append(Vector2i(int(e["x1"]), int(e["z0"])))
				out.append(Vector2i(int(e["x0"]), int(e["z1"])))
				out.append(Vector2i(int(e["x1"]), int(e["z1"])))
			"wall":
				out.append(Vector2i(int(e["ax"]), int(e["az"])))
				out.append(Vector2i(int(e["bx"]), int(e["bz"])))
	return out

## Mur / sol / toit visé (calcul analytique : une ouverture reste visible comme partie du mur). Niveau courant seulement.
func pick() -> Dictionary:
	var r := _ray()
	var o: Vector3 = r["o"]
	var d: Vector3 = r["d"]
	if aim_override.x < 1.0e8:
		d = (aim_override - o).normalized()
	var best := {}
	var bt := REACH * 2.0
	var y0 := c.level_y(level)
	for w in c.of_type("wall", level):
		var line := float(C.wall_line(w)) * C.U
		var sp := C.wall_span(w)
		var along_x := C.wall_axis(w) == 0
		var dn := d.z if along_x else d.x
		if absf(dn) < 1.0e-5:
			continue
		var t := (line - (o.z if along_x else o.x)) / dn
		if t <= 0.0 or t >= bt:
			continue
		var p := o + d * t
		var s := (p.x if along_x else p.z) / C.U
		if s < float(sp.x) - 0.2 or s > float(sp.y) + 0.2 or p.y < y0 - C.SLAB_T or p.y > y0 + c.wall_top(w) + 0.05:
			continue
		bt = t
		best = {"kind": "wall", "id": int(w["id"]), "s": s, "t": t, "point": p}
	for f in c.slabs(level):
		if absf(d.y) < 1.0e-5:
			continue
		var t2 := (y0 - o.y) / d.y
		if t2 <= 0.0 or t2 >= bt:
			continue
		var p2 := o + d * t2
		if p2.x >= float(f["x0"]) * C.U and p2.x <= float(f["x1"]) * C.U and p2.z >= float(f["z0"]) * C.U and p2.z <= float(f["z1"]) * C.U:
			bt = t2
			best = {"kind": String(f["t"]), "id": int(f["id"]), "t": t2, "point": p2}
	for rf in c.of_type("roof", level):
		var sh := c.roof_shape(rf)
		var pts := ConstructionView.roof_points(sh, y0 + float(sh["y"]))
		var bb := AABB(pts[0], Vector3.ZERO)
		for q in pts:
			bb = bb.expand(q)
		var hit = bb.intersects_ray(o, d)
		if hit != null:
			var t3 := o.distance_to(hit)
			if t3 < bt:
				bt = t3
				best = {"kind": "roof", "id": int(rf["id"]), "t": t3, "point": hit}
	return best

# ------------------------------------------------------------------ calcul de l'aperçu

func _compute_live() -> Dictionary:
	if aim.x > 1.0e8:
		return {}
	match tool:
		"sol", "fondations":
			if has_corner:
				var kind := "foundation" if tool == "fondations" else "floor"
				return ConstructionOps.add_slab(_work(), kind, 0 if kind == "foundation" else level, corner, aim_u, floor_mat if kind == "floor" else "")
		"mur":
			if has_corner:
				return ConstructionOps.add_wall(_work(), level, corner, aim_u, wall_h, wall_mat)
		"piece":
			if has_corner:
				return ConstructionOps.add_room(_work(), level, corner, aim_u, wall_h, door_side, wall_mat, floor_mat)
		"porte", "fenetre":
			var p := pick()
			if not p.is_empty() and String(p["kind"]) == "wall":
				return ConstructionOps.add_opening(c, int(p["id"]), "door" if tool == "porte" else "window", float(p["s"]))
		"toit":
			var p2 := pick()
			if not p2.is_empty() and String(p2["kind"]) == "wall":
				return ConstructionOps.add_roof(c, int(p2["id"]), roof_mat)
	return {}

## Un résultat « ok » mais hors budget devient un refus expliqué.
func _afford(op: Dictionary) -> Dictionary:
	if op.is_empty() or not bool(op["ok"]):
		return op
	if int(op["delta"]) > stock:
		var o2 := op.duplicate()
		o2["ok"] = false
		o2["reasons"] = ["Stock insuffisant : il manque %d unité%s (stock %d, coût %d)." % [int(op["delta"]) - stock, "s" if int(op["delta"]) - stock > 1 else "", stock, int(op["delta"])]]
		return o2
	return op

func _process(delta: float) -> void:
	if not active:
		return
	_toast_t += delta
	if _toast.visible and _toast_t > 6.0:
		_toast.visible = false
	if not _refusal.is_empty():
		_refusal_t += delta
		if _refusal_t > 5.0:
			_refusal = {}
	_was_captured = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or aim_override.x < 1.0e8
	_update_aim()
	var shown: Dictionary
	if not pending.is_empty():
		shown = pending
	else:
		live = _afford(_compute_live())
		shown = live if not live.is_empty() else _refusal
	_draw(shown)
	_update_hint(shown)

# ------------------------------------------------------------------ dessin

func _clear_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.get_parent().remove_child(_ghost)
		_ghost.queue_free()
	_ghost = null
	_ghost_key = ""
	if _label3d != null:
		_label3d.visible = false

func _draw(shown: Dictionary) -> void:
	# marqueur d'aimantation
	if aim.x < 1.0e8:
		var y := c.level_y(level) if (level > 0 and not c.is_empty()) else aim.y
		_marker.position = Vector3(float(aim_u.x) * C.U, y + 0.25, float(aim_u.y) * C.U)
		_marker_mat.albedo_color = Color(0.4, 0.95, 1.0, 0.95) if aim_snap == "bord" else Color(1, 1, 1, 0.85)
		_marker.visible = tool != "modifier" and tool != "porte" and tool != "fenetre" and tool != "toit"
	else:
		_marker.visible = false
	var els: Array = []
	var good := true
	if not shown.is_empty():
		els = shown["ghost"]
		good = bool(shown["ok"])
	var sel_els: Array = []
	if sel_id >= 0 and shown.is_empty():
		var se := c.get_el(sel_id)
		if not se.is_empty():
			sel_els = [se]
	var key := ""
	if not els.is_empty():
		key = "%s|%s|%d" % [JSON.stringify(els), good, c.level_count()]
	elif not sel_els.is_empty():
		key = "sel|%d|%s" % [sel_id, JSON.stringify(sel_els[0])]
	if key == _ghost_key:
		return
	_clear_ghost()
	_ghost_key = key
	if key == "":
		return
	var tmp := Construction.new()
	tmp.base_y = _work().base_y
	var use: Array = els if not els.is_empty() else sel_els
	var col := Color(0.3, 0.95, 0.45, 0.42) if good else Color(1.0, 0.3, 0.25, 0.45)
	if els.is_empty():
		col = Color(1.0, 0.85, 0.25, 0.5)
	for e in use:
		tmp.elements.append((e as Dictionary).duplicate(true))
	if tmp.elements.size() > 0 and tmp.elements[0]["t"] == "roof" and not tmp.elements[0].has("y_override"):
		tmp.elements[0]["y_override"] = c.roof_base(tmp.elements[0])
	# les murs d'un étage fantôme dépendent du plancher du dessus : le ghost est dessiné à plat
	_ghost = ConstructionView.create(tmp, {"ghost": col})
	lab.add_child(_ghost)
	if not els.is_empty():
		var bb := tmp.bbox_m()
		if bb.size != Vector2.ZERO:
			var hmax := tmp.height_m()
			_label3d.position = Vector3(bb.get_center().x, tmp.level_y(level) + minf(hmax, 3.2) + 0.5, bb.get_center().y)
			_label3d.text = String(shown["text"]).get_slice(" · ", 0)
			_label3d.modulate = Color(1, 1, 1) if good else Color(1.0, 0.7, 0.65)
			_label3d.visible = true

func _update_hint(shown: Dictionary) -> void:
	var lines: Array[String] = []
	if not shown.is_empty():
		lines.append(String(shown["text"]))
		if not bool(shown["ok"]):
			lines.append("✖ " + " ".join(PackedStringArray(shown["reasons"])))
			lines.append("Rien n'est posé, rien n'est débité.")
			_hint.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
		elif not pending.is_empty():
			lines.append("Entrée : confirmer · X ou clic droit : annuler (rien n'est débité tant que ce n'est pas confirmé)")
			_hint.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
		else:
			lines.append("Clic : verrouiller l'aperçu")
			_hint.add_theme_color_override("font_color", Color(0.85, 1.0, 0.9))
	else:
		_hint.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		lines.append(_tool_hint())
	_hint.text = "\n".join(PackedStringArray(lines))
	_stock_label.text = "Stock : %d unités" % stock
	_level_label.text = "Niveau %d%s" % [level, " (rez-de-chaussée)" if level == 0 else ""]

func _tool_hint() -> String:
	match tool:
		"sol": return "Sol : visez un coin et cliquez, puis le coin opposé. Aimanté à la grille de 0,50 m et aux bords posés."
		"fondations": return "Fondations (rez-de-chaussée) : deux coins, comme un sol mais enterrées de 60 cm."
		"mur": return "Mur : cliquez le début puis la fin (horizontal). Hauteur %s m (H pour changer)." % C.fm(wall_h)
		"porte": return "Porte : visez un mur ; l'aperçu montre la découpe. Clic pour la verrouiller."
		"fenetre": return "Fenêtre : visez un mur ; l'aperçu montre la découpe."
		"piece": return "Pièce : deux coins opposés → plancher + 4 murs. Porte côté %s (O), hauteur %s m (H)." % [C.SIDE_NAMES[door_side], C.fm(wall_h)]
		"toit": return "Toit : visez un mur de la pièce à couvrir ; le toit s'ajuste à l'emprise des murs."
		"modifier": return "Modifier : cliquez un mur (H hauteur · G pièce · J/K longueur · Y extrémité · Suppr retirer)." if sel_id < 0 else "Sélection : %s" % _sel_text()
	return ""

func _sel_text() -> String:
	var e := c.get_el(sel_id)
	if e.is_empty():
		return ""
	if String(e["t"]) == "wall":
		return "mur %s m × %s m, extrémité %s · H hauteur · G pièce · J raccourcir · K prolonger · Y extrémité · Suppr retirer" % [C.fm(float(C.wall_len_u(e)) * C.U, 2), C.fm(float(e["h"])), edit_end]
	return "%s · Suppr pour retirer" % String(e["t"])

# ------------------------------------------------------------------ entrées

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed and _was_captured:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			click()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel_preview()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if _paused() or lab_ui.bar_open:
			return
		var handled := true
		match k.keycode:
			KEY_1: set_tool("sol")
			KEY_2: set_tool("fondations")
			KEY_3: set_tool("mur")
			KEY_4: set_tool("porte")
			KEY_5: set_tool("fenetre")
			KEY_6: set_tool("piece")
			KEY_7: set_tool("toit")
			KEY_8: set_tool("modifier")
			KEY_ENTER, KEY_KP_ENTER: confirm()
			KEY_X, KEY_BACKSPACE: cancel_preview()
			KEY_Z:
				if k.ctrl_pressed:
					undo()
				else:
					handled = false
			KEY_PAGEUP: set_level(level + 1)
			KEY_PAGEDOWN: set_level(level - 1)
			KEY_H: cycle_height(false)
			KEY_G: cycle_height(true)
			KEY_O: cycle_side()
			KEY_M: cycle_material()
			KEY_J: nudge_end(-1)
			KEY_K: nudge_end(1)
			KEY_Y: toggle_end()
			KEY_DELETE: remove_selected()
			_: handled = false
		if handled:
			get_viewport().set_input_as_handled()

## Stock de démonstration : remis à 200 unités (hors économie du jeu).
func refill_stock() -> void:
	stock = DEMO_STOCK
	_say("Stock de démonstration rechargé : %d unités." % stock, "ok")

func _paused() -> bool:
	var app := get_tree().root.get_node_or_null("App")
	return app != null and bool(app.get("paused_menu"))

func click() -> void:
	if aim.x > 1.0e8:
		return
	match tool:
		"sol", "fondations", "mur", "piece":
			if not has_corner:
				has_corner = true
				corner = aim_u
				_refusal = {}
			else:
				var op := _afford(_compute_live())
				if op.is_empty():
					return
				if bool(op["ok"]):
					pending = op
				else:
					_refuse(op)
		"porte", "fenetre", "toit":
			var op2 := _afford(_compute_live())
			if op2.is_empty():
				_say("Visez un mur de ce niveau.", "erreur")
			elif bool(op2["ok"]):
				pending = op2
			else:
				_refuse(op2)
		"modifier":
			var p := pick()
			if p.is_empty():
				sel_id = -1
			else:
				sel_id = int(p["id"])
				sel_s = float(p.get("s", -1.0))
	_ghost_key = "!"

var sel_s := -1.0

func _refuse(op: Dictionary) -> void:
	_refusal = op
	_refusal_t = 0.0
	_ghost_key = "!"
	_say("Impossible : %s Rien n'est modifié." % " ".join(PackedStringArray(op["reasons"])), "erreur")

## Confirme l'opération verrouillée : le stock est débité (ou remboursé) à cet instant seulement.
func confirm() -> Dictionary:
	if pending.is_empty():
		_say("Rien à confirmer : tracez d'abord une pose (clic) pour en voir l'aperçu.", "erreur")
		return {"ok": false}
	var op := _afford(pending)
	if not bool(op["ok"]):
		_refuse(op)
		pending = {}
		return {"ok": false, "reasons": op["reasons"]}
	undo_stack.append({"c": c, "stock": stock, "label": String(op["text"]).get_slice(" · ", 0)})
	c = op["cand"]
	stock -= int(op["delta"])
	spent_total += int(op["delta"])
	var txt := String(op["text"])
	pending = {}
	has_corner = false
	_refusal = {}
	_rebuild()
	_say("Posé · %s · stock %d · Ctrl+Z pour défaire" % [txt, stock], "ok")
	changed.emit()
	return {"ok": true, "op": op}

func undo() -> void:
	if not pending.is_empty() or has_corner:
		cancel_preview()
		return
	if undo_stack.is_empty():
		_say("Rien à défaire.", "erreur")
		return
	var e: Dictionary = undo_stack.pop_back()
	c = e["c"]
	stock = int(e["stock"])
	sel_id = -1 if c.get_el(sel_id).is_empty() else sel_id
	if level >= maxi(c.level_count(), 1) + 0 and level > 0 and c.level_count() <= level:
		level = maxi(c.level_count() - 1, 0)
	_rebuild()
	_say("Défait : %s · stock %d" % [e["label"], stock], "ok")
	changed.emit()

func _rebuild() -> void:
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.queue_free()
	node = null
	if not c.is_empty():
		node = ConstructionView.create(c, {"collide": true})
		node.name = "ConstructionJoueur"
		lab.add_child(node)
		_apply_fade()
	_ghost_key = "!"
	_refresh_ui()

# ------------------------------------------------------------------ réglages

func cycle_height(whole_room: bool) -> void:
	if tool == "modifier" and sel_id >= 0 and String(c.get_el(sel_id).get("t", "")) == "wall":
		var w := c.get_el(sel_id)
		var i := C.HEIGHTS.find(float(w["h"]))
		var nh: float = C.HEIGHTS[(i + 1) % C.HEIGHTS.size()]
		var op: Dictionary
		if whole_room:
			op = ConstructionOps.set_group_height(c, sel_id, nh)
		else:
			op = ConstructionOps.modify_wall(c, sel_id, Vector2i(int(w["ax"]), int(w["az"])), Vector2i(int(w["bx"]), int(w["bz"])), nh)
		_lock_or_refuse(op)
		return
	var j := C.HEIGHTS.find(wall_h)
	wall_h = C.HEIGHTS[(j + 1) % C.HEIGHTS.size()]
	_refresh_ui()

func cycle_side() -> void:
	door_side = C.SIDES[(C.SIDES.find(door_side) + 1) % 4]
	_refresh_ui()

func cycle_material() -> void:
	var list: Array = C.WALL_MATS
	wall_mat = list[(list.find(wall_mat) + 1) % list.size()]
	_refresh_ui()

func toggle_end() -> void:
	edit_end = "A" if edit_end == "B" else "B"

func nudge_end(dir: int) -> void:
	if sel_id < 0 or String(c.get_el(sel_id).get("t", "")) != "wall":
		_say("Choisissez d'abord un mur (outil Modifier, clic).", "erreur")
		return
	var w := c.get_el(sel_id)
	var a := Vector2i(int(w["ax"]), int(w["az"]))
	var b := Vector2i(int(w["bx"]), int(w["bz"]))
	var along := Vector2i(1, 0) if C.wall_axis(w) == 0 else Vector2i(0, 1)
	if edit_end == "B":
		b += along * dir
	else:
		a -= along * dir
	_lock_or_refuse(ConstructionOps.modify_wall(c, sel_id, a, b, float(w["h"])))

func remove_selected() -> void:
	if sel_id < 0:
		_say("Choisissez d'abord un élément à retirer (outil Modifier, clic).", "erreur")
		return
	var e := c.get_el(sel_id)
	if String(e.get("t", "")) == "wall" and sel_s >= 0.0:
		var o := ConstructionOps.opening_at(e, sel_s)
		if not o.is_empty():
			_lock_or_refuse(ConstructionOps.remove_opening(c, sel_id, int(o["id"])))
			return
	_lock_or_refuse(ConstructionOps.remove_element(c, sel_id))

func _lock_or_refuse(op: Dictionary) -> void:
	op = _afford(op)
	if bool(op["ok"]):
		pending = op
		_ghost_key = "!"
	else:
		_refuse(op)

# ------------------------------------------------------------------ fichiers

func slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower().strip_edges():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "-"
	return out if out != "" else "maison"

func file_path_for(nm: String) -> String:
	return DIR + slug(nm) + ".eclats-maison.json"

func save_as(nm: String) -> Dictionary:
	if c.is_empty():
		_say("Rien à enregistrer : la construction est vide.", "erreur")
		return {"ok": false, "error": "vide"}
	c.name = nm.strip_edges() if nm.strip_edges() != "" else "Maison"
	var r := Construction.save_file(c, file_path_for(c.name))
	if bool(r["ok"]):
		_say("Maison enregistrée : %s (%s)" % [c.name, ProjectSettings.globalize_path(String(r["path"]))], "ok")
	else:
		_say(String(r["error"]), "erreur")
	return r

func saved_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".eclats-maison.json"):
			out.append(f)
	out.sort()
	return out

## Ouvre une maison enregistrée devant le joueur (l'ouverture est annulable et ne coûte rien : l'atelier n'est pas une économie).
func open_file(path: String) -> Dictionary:
	var r := Construction.load_file(path)
	if not bool(r["ok"]):
		_say("Ouverture impossible : %s Votre construction actuelle est conservée." % String(r["error"]), "erreur")
		return r
	var n: Construction = r["construction"]
	var at := Vector2(player.global_position.x, player.global_position.z) + Vector2(sin(0.0), -1.0) * 4.0
	var fwd := -camera.global_transform.basis.z
	at = Vector2(player.global_position.x + fwd.x * 4.0, player.global_position.z + fwd.z * 4.0)
	n.translate_u(roundi(at.x / C.U), roundi(at.y / C.U))
	var g := lab.ground_y(at.x, at.y)
	n.base_y = snappedf(0.0 if is_nan(g) else g, 0.2)
	undo_stack.append({"c": c, "stock": stock, "label": "Ouverture de « %s »" % n.name})
	c = n
	level = 0
	sel_id = -1
	_cancel_all()
	_rebuild()
	_say("Maison ouverte : %s · modifiable comme une construction neuve." % n.summary(), "ok")
	changed.emit()
	return {"ok": true, "construction": n}

# ------------------------------------------------------------------ interface

func _lbl(text: String, size := 14, col := MenuStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _small_btn(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(fn)
	return b

func _opt(items: Array, fn: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 13)
	for i in items:
		o.add_item(String(i))
	o.item_selected.connect(fn)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return o

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 9
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", MenuStyle.box(Color(0.08, 0.10, 0.14, 0.92), Color(0.30, 0.42, 0.55, 0.9), 10, 1))
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -318
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.offset_bottom = -10
	_layer.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	_panel.add_child(v)
	v.add_child(_lbl("Atelier · construction", 19, MenuStyle.ACCENT))
	_stock_label = _lbl("Stock : 200 unités", 20, Color(1.0, 0.92, 0.55))
	v.add_child(_stock_label)
	v.add_child(_lbl("Tarif : 1 unité / m², arrondi au-dessus (stock de démonstration)", 11, MenuStyle.MUTED))
	var br0 := _small_btn("Recharger le stock de démo (200)", refill_stock)
	br0.name = "BtnRecharger"
	v.add_child(br0)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	var i := 0
	for t in TOOLS:
		i += 1
		var b := Button.new()
		b.text = "%d %s" % [i, t[1]]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(set_tool.bind(t[0]))
		g.add_child(b)
		_tool_btns[t[0]] = b
	var lr := HBoxContainer.new()
	v.add_child(lr)
	lr.add_child(_small_btn("−", func() -> void: set_level(level - 1)))
	_level_label = _lbl("Niveau 0", 14)
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lr.add_child(_level_label)
	lr.add_child(_small_btn("+", func() -> void: set_level(level + 1)))
	var gr := GridContainer.new()
	gr.columns = 2
	v.add_child(gr)
	gr.add_child(_lbl("Hauteur (H)", 13))
	_h_opt = _opt(["2,0 m", "2,5 m", "3,0 m"], func(k: int) -> void: wall_h = C.HEIGHTS[k])
	gr.add_child(_h_opt)
	gr.add_child(_lbl("Porte (O)", 13))
	_side_opt = _opt(SIDE_LABELS, func(k: int) -> void: door_side = C.SIDES[k])
	gr.add_child(_side_opt)
	gr.add_child(_lbl("Murs (M)", 13))
	_wall_opt = _opt(["Bois", "Pierre", "Enduit"], func(k: int) -> void: wall_mat = C.WALL_MATS[k])
	gr.add_child(_wall_opt)
	gr.add_child(_lbl("Sol", 13))
	_floor_opt = _opt(["Planches", "Dalles"], func(k: int) -> void: floor_mat = C.FLOOR_MATS[k])
	gr.add_child(_floor_opt)
	gr.add_child(_lbl("Toit", 13))
	_roof_opt = _opt(["Tuiles", "Chaume", "Ardoise", "Bardeaux"], func(k: int) -> void: roof_mat = C.ROOF_MATS[k])
	gr.add_child(_roof_opt)
	v.add_child(HSeparator.new())
	var br := HBoxContainer.new()
	v.add_child(br)
	var bc := _small_btn("Confirmer (Entrée)", func() -> void: confirm())
	bc.name = "BtnConfirmer"
	bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(bc)
	var bx := _small_btn("Annuler (X)", func() -> void: cancel_preview())
	bx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(bx)
	v.add_child(_small_btn("Défaire (Ctrl+Z)", func() -> void: undo()))
	var mr := HBoxContainer.new()
	v.add_child(mr)
	for spec in [["− long. (J)", -1], ["+ long. (K)", 1]]:
		var mb := _small_btn(spec[0], nudge_end.bind(spec[1]))
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mr.add_child(mb)
	var mr2 := HBoxContainer.new()
	v.add_child(mr2)
	var by := _small_btn("Extrémité (Y)", toggle_end)
	by.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mr2.add_child(by)
	var bd := _small_btn("Retirer (Suppr)", remove_selected)
	bd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mr2.add_child(bd)
	v.add_child(HSeparator.new())
	var bf := _small_btn("Enregistrer / ouvrir une maison…", func() -> void: open_file_dialog())
	bf.name = "BtnFichiers"
	v.add_child(bf)
	v.add_child(_small_btn("Quitter la construction (B)", leave))
	var hlp := _lbl("PgUp / PgDn : niveau · Tab : souris libre\nClic droit : revenir en arrière", 11, MenuStyle.MUTED)
	v.add_child(hlp)
	# messages
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 20
	_hint.offset_right = -340
	_hint.offset_top = -150
	_hint.offset_bottom = -16
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 19)
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_layer.add_child(_hint)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_left = 20
	_toast.offset_right = -340
	_toast.offset_top = 14
	_toast.offset_bottom = 90
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 19)
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_toast.add_theme_constant_override("shadow_offset_x", 2)
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.visible = false
	_layer.add_child(_toast)
	_build_file_dialog()

func _refresh_ui() -> void:
	if _panel == null:
		return
	for k in _tool_btns:
		(_tool_btns[k] as Button).set_pressed_no_signal(k == tool)
	_h_opt.select(C.HEIGHTS.find(wall_h))
	_side_opt.select(C.SIDES.find(door_side))
	_wall_opt.select(C.WALL_MATS.find(wall_mat))
	_floor_opt.select(C.FLOOR_MATS.find(floor_mat))
	_roof_opt.select(C.ROOF_MATS.find(roof_mat))

func _build_file_dialog() -> void:
	_file_dialog = Control.new()
	_file_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_file_dialog.visible = false
	_layer.add_child(_file_dialog)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_file_dialog.add_child(shade)
	var p := MenuStyle.panel(Vector2(560, 330))
	_file_dialog.add_child(p)
	var v := p.get_child(0) as VBoxContainer
	v.add_theme_constant_override("separation", 8)
	v.add_child(_lbl("Enregistrer / ouvrir une maison", 22, MenuStyle.ACCENT))
	v.add_child(_lbl("Format « eclats-construction » (distinct d'une carte d'île). Dossier : maisons/ dans les données du jeu.", 12, MenuStyle.MUTED))
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	_file_name = LineEdit.new()
	_file_name.placeholder_text = "Nom de la maison"
	_file_name.custom_minimum_size = Vector2(300, 34)
	_file_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(_file_name)
	var bs := _small_btn("Enregistrer", func() -> void:
		var r := save_as(_file_name.text)
		_file_msg.text = ("Enregistré : %s" % ProjectSettings.globalize_path(String(r["path"]))) if bool(r["ok"]) else String(r.get("error", "")))
	bs.name = "BtnEnregistrer"
	r1.add_child(bs)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_file_list = OptionButton.new()
	_file_list.custom_minimum_size = Vector2(300, 34)
	_file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(_file_list)
	var bo := _small_btn("Ouvrir", func() -> void:
		if _file_list.item_count == 0:
			_file_msg.text = "Aucune maison enregistrée."
			return
		var r := open_file(DIR + _file_list.get_item_text(_file_list.selected))
		_file_msg.text = "Maison ouverte." if bool(r["ok"]) else String(r["error"]))
	bo.name = "BtnOuvrir"
	r2.add_child(bo)
	_file_msg = _lbl("", 13, Color(1.0, 0.93, 0.6))
	_file_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_file_msg.custom_minimum_size = Vector2(500, 60)
	v.add_child(_file_msg)
	v.add_child(_small_btn("Fermer", func() -> void: _close_file_dialog()))

func open_file_dialog() -> void:
	_file_name.text = c.name if c.name != "Sans titre" else ""
	_file_list.clear()
	for f in saved_files():
		_file_list.add_item(f)
	_file_msg.text = ""
	_file_dialog.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close_file_dialog() -> void:
	_file_dialog.visible = false
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
