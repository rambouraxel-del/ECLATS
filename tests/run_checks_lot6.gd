extends SceneTree
## Contrôles ciblés du Lot 6 (sans rendu) : laboratoire développeur — terrain éditable, sélections, génération, annulation, recettes.
##   godot --headless -s tests/run_checks_lot6.gd
var ok := 0
var ko := 0

func check(cond: bool, label: String) -> void:
	if cond:
		ok += 1
		print("  OK    ", label)
	else:
		ko += 1
		print("  ÉCHEC ", label)

func _initialize() -> void:
	_run.call_deferred()

func _same(a: LabWorld, snap: Dictionary) -> bool:
	return a.field.top == snap["top"] and a.field.zone == snap["zone"] and a.field.material == snap["mat"] and a.occ.tag == snap["tag"] and a.occ.items.size() == int(snap["items"])

func _make(kind: String) -> LabWorld:
	var l := LabWorld.new()
	root.add_child(l)
	l.setup(kind)
	return l

func _run() -> void:
	print("== Lot 6 : laboratoire développeur ==")
	# --- commandes
	var p := LabCommands.parse("/generer maison --graine 42")
	check(p["ok"] and p["cmd"] == "generer" and p["gen"] == "maison" and int(p["opts"]["seed"]) == 42, "commande /generer maison --graine 42 analysée")
	p = LabCommands.parse("/générer Maison --graine 7 --emprise 3,5x3,5 --yaw 1 --toit ardoise --murs bois")
	check(p["ok"] and p["opts"]["emprise"] == Vector2(3.5, 3.5) and p["opts"]["toit"] == "slate" and p["opts"]["murs"] == "timber" and p["opts"]["yaw"] == 1, "accents, virgule décimale, options")
	check(not LabCommands.parse("/generer dragon")["ok"] and not LabCommands.parse("/zzz")["ok"] and not LabCommands.parse("/generer maison --graine abc")["ok"], "commandes invalides refusées avec une raison")
	var rs := LabCommands.recipe_string({"gen": "maison", "opts": {"seed": 42, "emprise": Vector2(3.5, 3.5), "yaw": 0}})
	check(rs == "/generer maison --graine 42 --emprise 3.5x3.5 --yaw 0", "recette maison : %s" % rs)
	var back := LabCommands.parse(rs)
	check(back["ok"] and back["opts"]["seed"] == 42 and back["opts"]["emprise"] == Vector2(3.5, 3.5), "recette relue par le même analyseur")
	# --- planificateur : paramètres, ancien comportement intact
	var a := BuildingPlanner.plan("house_large", 7)
	var b := BuildingPlanner.plan("house_large", 7, {})
	check(a.W == b.W and a.D == b.D and a.style["wall_low"] == b.style["wall_low"] and a.roof["kind"] == b.roof["kind"] and a.openings.size() == b.openings.size(), "sans options le plan est identique")
	var h1 := BuildingPlanner.plan("hut", 42, {"W": 30, "D": 26, "annex": false})
	var h2 := BuildingPlanner.plan("hut", 42, {"W": 30, "D": 26, "annex": false})
	check(h1.footprint == Vector2i(34, 34), "cabane 3,40 × 3,40 m dans l'emprise de 3,50 × 3,50 m : %s" % h1.footprint)
	check(h1.roof["kind"] == h2.roof["kind"] and h1.style["wall_style"] == h2.style["wall_style"] and h1.openings.size() == h2.openings.size(), "même graine, même variante")
	var h3 := BuildingPlanner.plan("hut", 43, {"W": 30, "D": 26, "annex": false})
	check(h3.roof["kind"] != h1.roof["kind"] or h3.style["wall_style"] != h1.style["wall_style"] or h3.openings.size() != h1.openings.size() or h3.style["wall_low"] != h1.style["wall_low"], "graine différente, variante différente")
	var h4 := BuildingPlanner.plan("hut", 42, {"W": 30, "D": 26, "annex": false, "roof": "slate", "wall": "timber"})
	check(h4.roof["kind"] == "slate" and h4.style["wall_style"] == "timber", "réglages toit et murs imposés")
	# --- salle grise : maison 3,50 × 3,50, annulation
	var room := _make("room")
	check(room.field.land_count() > 20000, "salle : sol plat de %.0f m²" % (float(room.field.land_count()) * 0.04))
	var snap0 := room.snapshot()
	var rect := Rect2(Vector2(-1.75, -1.75), Vector2(3.5, 3.5))
	var op: Dictionary = room.prepare_house(rect, {"seed": 42, "yaw": 0})
	check(op["ok"], "salle : emprise 3,50 × 3,50 m acceptée (%s)" % ", ".join(op["reasons"]))
	check(_same(room, snap0), "aperçu : le terrain n'a pas été modifié")
	var r: Dictionary = await room.apply(op)
	check(r["ok"], "salle : maison posée")
	check(room.stack.size() == 1 and room.occ.items.size() == 1, "une opération, un objet réservé")
	var sample := room.field.col_of_m(0.0, 0.0)
	check(room.field.zone_at(sample.x, sample.y) == TerrainField.Zone.PLOT, "sol de la cour raccordé à la maison")
	var ur: Dictionary = await room.undo()
	check(ur["ok"] and _same(room, snap0) and room.objects_root.get_child_count() == 0, "Ctrl+Z : terrain, réservations et objets restaurés")
	check(not room.field.top.is_empty(), "salle : terrain valide après annulation")
	# --- recette de la maison : mêmes caractéristiques sur l'île en pente
	var roomplan: BuildingPlan = op["plan"]
	var isl := _make("island")
	var isnap := isl.snapshot()
	var slope_rect := Rect2(Vector2(2.0, -1.75), Vector2(3.5, 3.5))
	var op2: Dictionary = isl.prepare_house(slope_rect, {"seed": 42, "yaw": 0})
	check(op2["ok"], "île : la même recette est acceptée sur la pente (%s)" % ", ".join(op2["reasons"]))
	var p1: BuildingPlan = op["plan"]
	var p2: BuildingPlan = op2["plan"]
	check(p1.type == p2.type and p1.footprint == p2.footprint and p1.roof["kind"] == p2.roof["kind"] and p1.style["wall_low"] == p2.style["wall_low"] and p1.openings.size() == p2.openings.size() and p1.rooms.size() == p2.rooms.size(),
		"île : même variante (cabane, toit %s, %d ouvertures)" % [p2.roof["kind"], p2.openings.size()])
	check(_same(isl, isnap), "île : l'aperçu n'a pas modifié le terrain")
	check(int(op2["terrain_cells"]) > int(op["terrain_cells"]), "raccord adapté au site : %d colonnes raccordées sur la pente, %d dans la salle" % [op2["terrain_cells"], op["terrain_cells"]])
	var r2: Dictionary = await isl.apply(op2)
	check(r2["ok"], "île : maison posée sur la pente")
	var changed_cols := int(op2["terrain_cells"])
	var ur2: Dictionary = await isl.undo()
	check(ur2["ok"] and _same(isl, isnap), "île : Ctrl+Z restaure le relief et le raccord au sol (%d colonnes)" % changed_cols)
	# --- refus : raison claire, terrain intact
	var steep := Rect2(Vector2(-20.0, -1.0), Vector2(3.5, 3.5))
	var bad: Dictionary = isl.prepare_house(Rect2(Vector2(26.0, 0.0), Vector2(3.5, 3.5)), {"seed": 1})
	check(not bad["ok"] and bad["reasons"].size() > 0, "bord de l'île : refus « %s »" % (bad["reasons"][0] if bad["reasons"].size() > 0 else "?"))
	var small: Dictionary = isl.prepare_house(Rect2(Vector2(0, 0), Vector2(2.0, 2.0)), {"seed": 1})
	check(not small["ok"] and String(small["reasons"][0]).contains("trop petite"), "emprise trop petite : %s" % small["reasons"][0])
	check(_same(isl, isnap), "refus : aucune modification du terrain")
	# --- point : arbre et rocher
	var t: Dictionary = isl.prepare_tree(Vector2(-12.0, 0.0), "oak", 7)
	check(t["ok"], "arbre au point visé (%s)" % ", ".join(t["reasons"]))
	var tr: Dictionary = await isl.apply(t)
	check(tr["ok"] and isl.objects_root.get_child_count() == 2, "arbre posé (visuel + collision)")
	var t2: Dictionary = isl.prepare_tree(Vector2(-12.0, 0.0), "oak", 8)
	check(not t2["ok"], "deuxième arbre au même point refusé : %s" % (t2["reasons"][0] if t2["reasons"].size() > 0 else "?"))
	var rk: Dictionary = isl.prepare_rock(Vector2(-14.0, 6.0), "boulder", 3, 1.0)
	check(rk["ok"], "rocher au point visé (%s)" % ", ".join(rk["reasons"]))
	await isl.apply(rk)
	await isl.undo()
	await isl.undo()
	check(_same(isl, isnap) and isl.objects_root.get_child_count() == 0, "arbre et rocher annulés dans l'ordre")
	# --- pinceau : aplanir, reste dans la zone, annulation
	var sel := LabSelection.new()
	root.add_child(sel)
	sel.lab = isl
	sel.paint_at(Vector2(4.0, 0.0), 1.2)
	var cells: Array = sel.brush_cells.keys()
	var fop: Dictionary = isl.prepare_flatten(cells, {})
	check(fop["ok"] and cells.size() > 40, "pinceau : %d colonnes peintes, aplanir à %.2f m (déblai max %.2f m, remblai max %.2f m)" % [cells.size(), fop["target_m"], fop["cut_max_m"], fop["fill_max_m"]])
	check(_same(isl, isnap), "aperçu du pinceau : terrain intact")
	var before_top := isl.field.top.duplicate()
	await isl.apply(fop)
	var outside := 0
	var inside_flat := true
	var inside_set := {}
	for c in cells:
		inside_set[int(c)] = true
	var tgt: int = fop["target"]
	for i in isl.field.top.size():
		if isl.field.top[i] != before_top[i] and not inside_set.has(i):
			outside += 1
		if inside_set.has(i) and isl.field.top[i] != tgt:
			inside_flat = false
	check(outside == 0, "aplanissement : aucune colonne modifiée hors de la zone peinte")
	check(inside_flat, "aplanissement : toute la zone est au niveau %.2f m" % fop["target_m"])
	await isl.undo()
	check(_same(isl, isnap), "aplanissement annulé : relief identique")
	var big := LabSelection.new()
	root.add_child(big)
	big.lab = isl
	big.paint_at(Vector2(10.0, 0.0), 4.0)
	var bop: Dictionary = isl.prepare_flatten(big.brush_cells.keys(), {"niveau": 4.0})
	check(not bop["ok"] and String(bop["reasons"][0]).contains("Dénivelé"), "zone trop inégale : refus expliqué (%s)" % String(bop["reasons"][0]).substr(0, 60))
	check(_same(isl, isnap), "refus du pinceau : terrain intact")
	print("== %d réussite(s), %d échec(s) ==" % [ok, ko])
	quit(1 if ko > 0 else 0)
