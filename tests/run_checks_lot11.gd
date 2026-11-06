extends SceneTree
## Contrôles du Lot 11 (fiabilité des cartes, des constructions et de la progression) — sans rendu :
##   godot --headless -s tests/run_checks_lot11.gd
const DIR := "user://lot11_tests/"
var ok := 0
var ko := 0

func check(cond: bool, label: String) -> void:
	if cond:
		ok += 1
		print("  OK    ", label)
	else:
		ko += 1
		print("  ÉCHEC ", label)

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func _initialize() -> void:
	print("== Lot 11 : fiabilité ==")
	_clean()
	_safe_file()
	_layers()
	_sculpt_limit()
	_import_validation()
	_session()
	_houses()
	_game_save()
	_clean()
	print("== %d réussite(s), %d échec(s) ==" % [ok, ko])
	quit(1 if ko > 0 else 0)

# ------------------------------------------------------------------ écriture sûre
func _safe_file() -> void:
	print("-- écriture sûre --")
	var f := DIR + "a.json"
	var r1 := SafeFile.write_text(f, "{\"v\":1}")
	check(r1["ok"] and FileAccess.get_file_as_string(f) == "{\"v\":1}" and not FileAccess.file_exists(f + ".tmp"), "écriture : fichier final écrit, aucun .tmp laissé")
	var r2 := SafeFile.write_text(f, "{\"v\":2}")
	check(r2["ok"] and FileAccess.get_file_as_string(f + ".bak") == "{\"v\":1}", "seconde écriture : l'ancienne version est gardée en .bak")
	for mode in ["open", "write", "verify", "replace"]:
		SafeFile.fail_at = mode
		var r := SafeFile.write_text(f, "{\"v\":3}")
		SafeFile.fail_at = ""
		check(not r["ok"] and FileAccess.get_file_as_string(f) == "{\"v\":2}" and not FileAccess.file_exists(f + ".tmp"), "panne « %s » : erreur lisible (%s), fichier final intact, pas de .tmp" % [mode, String(r["error"]).left(40)])
	check(FileAccess.get_file_as_string(f + ".bak") == "{\"v\":1}", "après les pannes, la dernière sauvegarde exploitable (.bak) est intacte")
	var bad := SafeFile.write_text(DIR + "b.json", "pas du json", func(t: String) -> String: return "" if JSON.parse_string(t) != null else "JSON invalide")
	check(not bad["ok"] and not FileAccess.file_exists(DIR + "b.json"), "contenu invalide refusé par la vérification : aucun fichier créé")
	var fa := FileAccess.open(f, FileAccess.WRITE)
	fa.store_string("{abîmé")
	fa.close()
	var rj := SafeFile.read_json(f)
	check(rj["ok"] and rj["from_backup"] and rj["data"]["v"] == 1, "fichier principal abîmé : la dernière version exploitable est relue")

# ------------------------------------------------------------------ couches
func _layers() -> void:
	print("-- couches de relief (16 bits, migration) --")
	var L := PlanLayers.create(16, Vector2i(-8, -8))
	check(L.set_delta(5, 900) and L.get_delta(5) == 900 and L.set_delta(6, -1500), "retouches de ±900 et -1500 cellules (au-delà de 25,4 m) acceptées")
	check(not L.set_delta(7, 2001) and L.get_delta(7) == 0, "2001 cellules : refus explicite, rien d'écrit")
	L.mask[3] = 1
	L.mat[4] = 2
	var d := L.to_dict()
	var back := PlanLayers.parse(d)
	check(back["ok"] and (back["layers"] as PlanLayers).delta == L.delta and (back["layers"] as PlanLayers).mask == L.mask and (back["layers"] as PlanLayers).mat == L.mat, "aller-retour exact (retouches, matières, masque)")
	# ancien format : octets, 128 = rien
	var old := PackedByteArray()
	old.resize(256)
	old.fill(128)
	old[10] = 128 + 100
	old[11] = 128 - 127
	var zeros := PackedByteArray()
	zeros.resize(256)
	var dold := {"n": 16, "origin": [-8, -8], "delta": PlanLayers._enc(old), "mat": PlanLayers._enc(zeros), "mask": PlanLayers._enc(zeros)}
	var mig := PlanLayers.parse(dold)
	check(mig["ok"] and (mig["layers"] as PlanLayers).get_delta(10) == 100 and (mig["layers"] as PlanLayers).get_delta(11) == -127 and (mig["layers"] as PlanLayers).get_delta(0) == 0, "ancien format (octets) migré : +100, -127 et « aucune retouche » retrouvés")
	var raw := PackedByteArray()
	raw.resize(512)
	raw.encode_s16(0, 2001)
	var dbad := d.duplicate()
	dbad["delta16"] = PlanLayers._enc(raw)
	var rb := PlanLayers.parse(dbad)
	check(not rb["ok"] and "limite" in String(rb["error"]), "valeur hors limites dans un fichier : refus (« %s »)" % String(rb.get("error", "")).left(60))
	for case in [["delta16", "!!pas du base64!!"], ["mat", ""], ["mask", Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))]]:
		var dd := d.duplicate()
		dd[case[0]] = case[1]
		check(not PlanLayers.parse(dd)["ok"], "couche « %s » illisible : refus" % case[0])
	var dm := d.duplicate()
	var mk := PackedByteArray()
	mk.resize(256)
	mk[0] = 7
	dm["mask"] = PlanLayers._enc(mk)
	check(not PlanLayers.parse(dm)["ok"], "masque contenant 7 : refus")
	var dn := d.duplicate()
	dn["n"] = 99999
	check(not PlanLayers.parse(dn)["ok"], "taille de grille 99999 : refus")

# ------------------------------------------------------------------ sculpter au-delà de 25,4 m
func _sculpt_limit() -> void:
	print("-- sculpter au-delà de 25,4 m --")
	var doc := MapDoc.from_plan(PlanGenerator.generate(21, 56, 48))
	var c := doc.field.center_m(doc.field.n / 2, doc.field.n / 2)
	var base := doc.field.top_at(doc.field.n / 2, doc.field.n / 2)
	doc.stroke_begin("Monter", "monter", c)
	for k in 5:
		doc.stroke_dab("monter", c, 2.5, 60.0)       # 60 cellules par passage
	doc.stroke_end()
	var ci := doc.col_of(c)
	var up := doc.field.top_at(ci.x, ci.y) - base
	check(up > 127, "le relief affiché dépasse 127 cellules (%d cellules = %.1f m)" % [up, up * 0.2])
	var shown := doc.field.top.duplicate()
	var mat := doc.field.material.duplicate()
	var path := DIR + "haut.eclats-carte.json"
	check(doc.export_to(path)["ok"], "carte enregistrée")
	var doc2 := MapDoc.new()
	var op := doc2.open_from(path)
	check(op["ok"] and doc2.field.top == shown and doc2.field.material == mat, "rouverte : le terrain est IDENTIQUE à celui affiché (toutes colonnes)")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(path))["version"]) == IslandPlan.VERSION, "version de carte écrite : v%d" % IslandPlan.VERSION)
	# limite : jamais écrêté en silence
	var doc3 := MapDoc.from_plan(PlanGenerator.generate(21, 56, 48))
	doc3.stroke_begin("Monter", "monter", c)
	for k in 12:
		doc3.stroke_dab("monter", c, 2.5, 400.0)
	doc3.stroke_end()
	var cj := doc3.col_of(c)
	check(doc3.limit_hit and doc3.plan.layers.get_delta(cj.x + cj.y * doc3.field.n) == PlanLayers.MAX_DELTA, "au-delà de la limite (±%d cellules) : hauteur limitée ET signalée (limit_hit)" % PlanLayers.MAX_DELTA)
	var shown3 := doc3.field.top.duplicate()
	var p3 := DIR + "limite.eclats-carte.json"
	doc3.export_to(p3)
	var doc4 := MapDoc.new()
	doc4.open_from(p3)
	check(doc4.field.top == shown3, "même à la limite, le terrain rouvert est identique au terrain affiché")
	# ancienne carte (v2, octets)
	var plan := PlanGenerator.generate(5, 56, 48)
	var dd := MapDoc.from_plan(plan)
	dd.stroke_begin("Monter", "monter", c)
	dd.stroke_dab("monter", c, 2.5, 20.0)
	dd.stroke_end()
	var dict := dd.plan.to_dict()
	var L := dd.plan.layers
	var ob := PackedByteArray()
	ob.resize(L.n * L.n)
	for i in L.n * L.n:
		ob[i] = L.delta[i] + 128
	(dict["layers"] as Dictionary).erase("delta16")
	dict["layers"]["delta"] = PlanLayers._enc(ob)
	dict["version"] = 2
	var r2 := IslandPlan.from_dict(dict)
	check(r2["ok"] and (r2["plan"] as IslandPlan).layers.delta == L.delta, "une carte v2 (retouches sur un octet) se relit : mêmes retouches")
	var doc5 := MapDoc.from_plan(r2["plan"])
	check(doc5.field.top == dd.field.top, "carte v2 : terrain identique à celui d'origine")

# ------------------------------------------------------------------ validation des imports
func _import_validation() -> void:
	print("-- validation des fichiers importés --")
	var good := PlanGenerator.generate(9, 56, 48)
	var doc := MapDoc.from_plan(good)
	var keep_plan := doc.plan
	var cases := {
		"version inconnue": func(d: Dictionary) -> void: d["version"] = 99,
		"version nulle": func(d: Dictionary) -> void: d["version"] = 0,
		"mauvais format": func(d: Dictionary) -> void: d["format"] = "autre",
		"coordonnée géante": func(d: Dictionary) -> void: d["outline"][0] = [1.0e9, 0.0],
		"point non numérique": func(d: Dictionary) -> void: d["outline"][1] = ["a", "b"],
		"zone de type inconnu": func(d: Dictionary) -> void: d["zones"][0]["kind"] = "volcan",
		"rayon de zone négatif": func(d: Dictionary) -> void: d["zones"][0]["r"] = -3.0,
		"chemin à un point": func(d: Dictionary) -> void: d["paths"][0]["pts"] = [[0, 0]],
		"largeur de chemin nulle": func(d: Dictionary) -> void: d["paths"][0]["width"] = 0.0,
		"repère de type inconnu": func(d: Dictionary) -> void: d["landmarks"].append({"id": "x", "kind": "inconnu", "pos": [0, 0], "label": ""}),
		"identifiant de zone en double": func(d: Dictionary) -> void: d["zones"].append(d["zones"][0].duplicate(true)),
		"dimensions nulles": func(d: Dictionary) -> void: d["width"] = 0.0,
		"graine texte": func(d: Dictionary) -> void: d["seed"] = "abc",
		"départ mal formé": func(d: Dictionary) -> void: d["start"] = [1],
		"contour texte": func(d: Dictionary) -> void: d["outline"] = "non",
		"réglages mal formés": func(d: Dictionary) -> void: d["settings"] = [1],
	}
	for name in cases:
		var d := good.to_dict()
		var mod: Callable = cases[name]
		mod.call(d)
		var f := DIR + "bad.json"
		var fa := FileAccess.open(f, FileAccess.WRITE)
		fa.store_string(JSON.stringify(d))
		fa.close()
		var r := doc.open_from(f)
		check(not r["ok"] and String(r["error"]) != "" and doc.plan == keep_plan, "%s : refusé (« %s »), carte courante intacte" % [name, String(r.get("error", "")).left(48)])
	for txt in ["", "pas du json", "[1,2]", "{\"format\":\"eclats-carte\"}", "{\"format\":\"eclats-carte\",\"version\":1,\"width\":1.0}"]:
		var fb := FileAccess.open(DIR + "bad2.json", FileAccess.WRITE)
		fb.store_string(txt)
		fb.close()
		var rb := doc.open_from(DIR + "bad2.json")
		check(not rb["ok"] and doc.plan == keep_plan, "contenu « %s » : refusé, carte courante intacte" % txt.left(24))
	# JSON valide mais mal formé : une maison sans emprise, un terrain de maison incohérent
	var dh := good.to_dict()
	dh["maisons"] = [{"id": "m", "name": "M", "model": {}, "pos": [0, 0], "rect": [0, 0, 1, 1]}]
	check(not IslandPlan.from_dict(dh)["ok"], "maison au modèle vide : refusée")
	# constructions
	var model: Construction = Construction.load_file("res://assets/maisons/maison_exemple.eclats-maison.json")["construction"]
	var cd := model.to_dict()
	cd["elements"][0]["id"] = cd["elements"][1]["id"]
	check(not Construction.from_dict(cd)["ok"], "construction : identifiant d'élément en double refusé")
	var cd2 := model.to_dict()
	for e in cd2["elements"]:
		if e["t"] == "wall":
			e["ax"] = 1.5
			break
	check(not Construction.from_dict(cd2)["ok"], "construction : coordonnée 1,5 (non entière) refusée")
	var cd3 := model.to_dict()
	for e in cd3["elements"]:
		if e["t"] == "wall":
			e["bx"] = 99999
			break
	check(not Construction.from_dict(cd3)["ok"], "construction : coordonnée hors limites refusée")
	# écriture de construction : panne = fichier précédent intact
	var cf := DIR + "maison.eclats-maison.json"
	check(Construction.save_file(model, cf)["ok"], "construction enregistrée")
	var before := FileAccess.get_file_as_string(cf)
	SafeFile.fail_at = "write"
	var cr := Construction.save_file(model, cf)
	SafeFile.fail_at = ""
	check(not cr["ok"] and FileAccess.get_file_as_string(cf) == before, "écriture de construction impossible : erreur lisible, fichier précédent intact")

# ------------------------------------------------------------------ session et dialogue de sortie
func _session() -> void:
	print("-- session et protection des modifications --")
	var doc := MapDoc.from_plan(PlanGenerator.generate(21, 56, 48))
	var s := MapSession.begin(doc)
	s.dir = DIR
	check(not s.is_dirty(), "plan généré et intact : rien à protéger")
	var c := doc.field.center_m(doc.field.n / 2, doc.field.n / 2)
	doc.stroke_begin("Monter", "monter", c)
	doc.stroke_dab("monter", c, 2.5, 3.0)
	doc.stroke_end()
	check(s.is_dirty() and doc.undo_stack.size() == 1, "après une retouche : modifié, une opération annulable")
	# passage en 3D et retour : le même document (historique conservé) ; la scène 3D travaille sur une COPIE du relief
	var rebuilds := doc.rebuilds
	var f3 := doc.field.duplicate_field()
	var b3 := doc.build.with_field(f3)
	f3.top[0] = 12345
	f3.bottom[0] = 99
	check(doc.field.top[0] != 12345 and doc.field.bottom[0] != 99 and b3.base_top == doc.build.base_top, "vue 3D : copie indépendante du relief (le document de l'éditeur n'est pas touché)")
	check(MapSession.current == s and s.doc == doc and doc.undo_stack.size() == 1 and doc.rebuilds == rebuilds, "retour de la 3D : même document, historique intact, relief non recalculé")
	var shown := doc.field.top.duplicate()
	doc.undo()
	check(not doc.field.top == shown and not s.is_dirty() == false, "Ctrl+Z après le retour : l'opération est annulée")
	# les trois choix
	doc.stroke_begin("Monter", "monter", c)
	doc.stroke_dab("monter", c, 2.5, 3.0)
	doc.stroke_end()
	var flags := {"n": 0}
	var then := func() -> void: flags["n"] += 1
	var rc := s.choose("cancel", then)
	check(not rc["done"] and flags["n"] == 0 and s.is_dirty(), "choix « Annuler » : l'action n'a pas lieu, la carte reste modifiée")
	SafeFile.fail_at = "write"
	var rs := s.choose("save", then)
	SafeFile.fail_at = ""
	check(not rs["ok"] and flags["n"] == 0 and s.is_dirty() and doc.plan.layers.count_delta() > 0 and not FileAccess.file_exists(s.target_file()), "choix « Enregistrer » avec échec d'écriture : action non poursuivie, carte ouverte et modifiée intacte (« %s »)" % String(rs.get("error", "")).left(40))
	var ok_save := s.choose("save", then)
	check(ok_save["ok"] and flags["n"] == 1 and not s.is_dirty() and FileAccess.file_exists(s.path), "choix « Enregistrer » : enregistré puis action poursuivie, carte « propre »")
	doc.stroke_begin("Monter", "monter", c)
	doc.stroke_dab("monter", c, 2.5, 3.0)
	doc.stroke_end()
	var rd := s.choose("discard", then)
	check(rd["done"] and flags["n"] == 2, "choix « Quitter sans enregistrer » : l'action a lieu")
	check(MapSession.ask(null, func() -> void: flags["n"] += 1) == false, "dialogue demandé quand la carte est modifiée (sans rendu : l'action n'a pas lieu toute seule)")
	var s2 := MapSession.begin(MapDoc.from_plan(PlanGenerator.generate(4, 56, 48)))
	check(MapSession.ask(null, func() -> void: flags["n"] += 1) and flags["n"] == 3, "carte intacte : l'action est immédiate, aucun dialogue")
	# nom d'enregistrement : jamais l'écrasement d'une autre carte
	s2.dir = DIR
	var f1 := s2.target_file()
	var fa := FileAccess.open(f1, FileAccess.WRITE)
	fa.store_string("{}")
	fa.close()
	check(s2.target_file() != f1, "nom déjà pris : une autre carte n'est pas écrasée (%s)" % s2.target_file().get_file())
	# ouverture d'une autre carte : modifiée → protégée côté éditeur (même API)
	var other := MapDoc.new()
	check(other.open_from(DIR + "inexistant.json")["ok"] == false, "ouvrir un fichier absent : erreur lisible")

# ------------------------------------------------------------------ maisons et terrain
func _first_ok(doc: MapDoc, model: Construction) -> Dictionary:
	var z := doc.plan.zone_by_id("plateau")
	for r in [4.0, 7.0, 10.0, 13.0]:
		for yaw in 4:
			for k in 16:
				var p: Vector2 = (z["c"] as Vector2) + Vector2.from_angle(float(k) * TAU / 16.0) * r
				var res := doc.evaluate_house(model, p, yaw)
				if res["ok"]:
					return {"pos": p, "yaw": yaw, "res": res}
	return {}

func _house_doc() -> Array:
	var model: Construction = Construction.load_file("res://assets/maisons/maison_exemple.eclats-maison.json")["construction"]
	var doc := MapDoc.from_plan(PlanGenerator.generate(21, 56, 48))
	var found := _first_ok(doc, model)
	return [doc, model, found]

func _houses() -> void:
	print("-- maisons : terrain recalculé, suppression --")
	var hd := _house_doc()
	var doc: MapDoc = hd[0]
	var model: Construction = hd[1]
	var found: Dictionary = hd[2]
	var top0 := doc.field.top.duplicate()
	var mat0 := doc.field.material.duplicate()
	var placed := doc.place_house(model, found["pos"], found["yaw"])
	check(placed["ok"] and doc.plan.houses[0].has("terrain") and doc.plan.houses[0].has("link"), "maison posée avec son terrain et son raccord mémorisés")
	var cells: PackedInt32Array = doc.plan.houses[0]["terrain"]["cells"]
	var tops_house := PackedInt32Array()
	for i in cells:
		tops_house.append(doc.field.top[i])
	# 1) retouche de structure SANS rapport avec la maison : zone ajoutée loin d'elle
	var far := Vector2(-20, -18)
	var hc: Vector2 = doc.plan.houses[0]["pos"]
	if hc.distance_to(far) < 14.0:
		far = Vector2(20, 18)
	var sig0 := doc.plan.signature()
	doc.begin_op("Zone loin de la maison")
	doc.add_zone_disc("bois", far, 3.0)
	var err := doc.finish_op()
	var same := true
	for k in cells.size():
		if doc.field.top[cells[k]] != tops_house[k]:
			same = false
	check(doc.plan.signature() != sig0 and err == "" and same, "zone ajoutée ailleurs : le relief de base est recalculé, la plateforme de la maison garde exactement sa hauteur (%s)" % err.left(60))
	# 2) retouche qui casserait le raccord : le chemin le plus proche part loin de la porte
	var lk: Dictionary = doc.plan.houses[0]["link"]
	var np := HousePad.nearest_path(doc.plan.paths, lk["to"])
	var pid: String = np["path_id"]
	var pa := doc.plan.path_by_id(pid)
	var before_plan := doc.plan
	var pts_before: Array = (pa["pts"] as Array).duplicate()
	var top_before := doc.field.top.duplicate()
	doc.begin_op("Déplacer le chemin loin de la maison")
	var pa2 := doc.plan.path_by_id(pid)
	var moved: Array = []
	for q in pa2["pts"]:
		moved.append((q as Vector2) + Vector2(11.0, 9.0))
	pa2["pts"] = moved
	var err2 := doc.finish_op()
	check(err2 != "" and "maison" in err2 and ("raccord" in err2 or "chemin" in err2), "chemin déplacé loin du raccord : opération refusée AVEC explication (« %s »)" % err2.left(90))
	var pa3 := doc.plan.path_by_id(pid)
	check(pa3["pts"] == pts_before and doc.field.top == top_before and doc.plan.houses.size() == 1, "refus : chemin, relief et maison inchangés")
	# 3) chemin légèrement déplacé : accepté, le raccord et l'entrée restent reliés
	doc.begin_op("Déplacer légèrement le chemin")
	var pa4 := doc.plan.path_by_id(pid)
	var moved2: Array = []
	for q in pa4["pts"]:
		moved2.append((q as Vector2) + Vector2(0.15, 0.1))
	pa4["pts"] = moved2
	var err3 := doc.finish_op()
	check(err3 == "", "chemin déplacé de 18 cm : accepté (%s)" % err3.left(60))
	# 4) sauvegarde / réouverture : fondations, seuil et trajet depuis le chemin
	var path := DIR + "maison.eclats-carte.json"
	check(doc.export_to(path)["ok"], "carte avec maison enregistrée")
	var shown := doc.field.top.duplicate()
	var doc2 := MapDoc.new()
	check(doc2.open_from(path)["ok"] and doc2.field.top == shown, "réouverte : terrain identique colonne pour colonne")
	var h2: Dictionary = doc2.plan.houses[0]
	var yard_ok := true
	var rr: Rect2 = h2["rect"]
	var c0 := doc2.field.col_of_m(rr.position.x + 0.05, rr.position.y + 0.05)
	var c1 := doc2.field.col_of_m(rr.end.x - 0.05, rr.end.y - 0.05)
	var hr := doc2.field.height_range(Rect2i(c0, c1 - c0 + Vector2i.ONE))
	yard_ok = hr.x == hr.y
	check(yard_ok, "fondations : plateforme toujours plate sous l'emprise après réouverture")
	var door: Vector2 = h2["door"]
	var q: Vector2 = h2["link"]["to"]
	var worst := 0.0
	var prev := doc2.field.ground_at_m(door.x, door.y)
	for k in range(1, 41):
		var pp := door.lerp(q, float(k) / 40.0)
		var g := doc2.field.ground_at_m(pp.x, pp.y)
		worst = maxf(worst, absf(g - prev))
		prev = g
	check(not is_nan(prev) and worst <= 0.41, "trajet du seuil au chemin après réouverture : aucune marche de plus de 40 cm (%.2f m)" % worst)
	var np2 := HousePad.nearest_path(doc2.plan.paths, q)
	check(float(np2["d"]) <= 1.6, "le raccord touche toujours le chemin (écart %.2f m)" % float(np2["d"]))
	check(doc2.house_conflicts().is_empty(), "aucun conflit de maison après réouverture")
	# 5) suppression : restaure le terrain (sans effacer une retouche indépendante), ou le garde
	var hd2 := _house_doc()
	var d3: MapDoc = hd2[0]
	var f3: Dictionary = hd2[2]
	var t0 := d3.field.top.duplicate()
	var m0 := d3.field.material.duplicate()
	d3.place_house(hd2[1], f3["pos"], f3["yaw"])
	var after_place := d3.field.top.duplicate()
	d3.remove_house(d3.plan.houses[0]["id"])
	check(d3.plan.houses.is_empty() and d3.field.top == t0 and d3.field.material == m0, "suppression : terrain restauré à l'identique (comme l'annulation de la pose) — %s" % d3.message.left(70))
	d3.undo()
	check(d3.plan.houses.size() == 1 and d3.field.top == after_place, "Ctrl+Z après la suppression : maison ET terrain reviennent")
	# retouche indépendante sur la cour, puis suppression : cette retouche est conservée
	var hc3: Vector2 = d3.plan.houses[0]["pos"]
	var rect3: Rect2 = d3.plan.houses[0]["rect"]
	var edge := Vector2(rect3.end.x + 0.5, hc3.y)
	d3.stroke_begin("Monter", "monter", edge)
	d3.stroke_dab("monter", edge, 0.6, 2.0)
	d3.stroke_end()
	var ec := d3.col_of(edge)
	var raised := d3.field.top[d3.field.idx(ec.x, ec.y)]
	d3.remove_house(d3.plan.houses[0]["id"])
	var st: Dictionary = d3.remove_stats
	check(int(st["kept"]) > 0 and int(st["restored"]) > 0 and d3.field.top[d3.field.idx(ec.x, ec.y)] == raised, "retouche faite depuis la pose : conservée (%d colonnes), le reste restauré (%d)" % [int(st["kept"]), int(st["restored"])])
	var d4 := _house_doc()[0] as MapDoc
	var f4: Dictionary = _house_doc()[2]
	d4.place_house(_house_doc()[1], f4["pos"], f4["yaw"])
	var placed_top := d4.field.top.duplicate()
	d4.remove_house(d4.plan.houses[0]["id"], false)
	check(d4.field.top == placed_top and d4.plan.houses.is_empty(), "retrait « garder le terrain » : le terrain aménagé reste, comme demandé")
	# masque et anciennes cartes
	var mdoc := _house_doc()[0] as MapDoc
	mdoc.begin_op("masque")
	var cm := mdoc.field.n / 2
	for dz in 4:
		for dx in 4:
			mdoc.plan.layers.mask[mdoc.field.idx(cm + dx, cm + dz)] = 1
	mdoc.finish_op(false)
	var mask_before := mdoc.plan.layers.mask.duplicate()
	var pm := DIR + "masque.json"
	mdoc.export_to(pm)
	var mdoc2 := MapDoc.new()
	mdoc2.open_from(pm)
	check(mdoc2.plan.layers.mask == mask_before, "masque de protection conservé à l'enregistrement")
	var legacy := _house_doc()
	var ld: MapDoc = legacy[0]
	ld.place_house(legacy[1], legacy[2]["pos"], legacy[2]["yaw"])
	var dict := ld.plan.to_dict()
	(dict["maisons"][0] as Dictionary).erase("terrain")
	(dict["maisons"][0] as Dictionary).erase("link")
	dict["version"] = 2
	var lr := IslandPlan.from_dict(dict)
	check(lr["ok"], "carte du Lot 8-10 (maison sans terrain mémorisé) : relue")
	var ld2 := MapDoc.from_plan(lr["plan"])
	ld2.remove_house(ld2.plan.houses[0]["id"])
	check(bool(ld2.remove_stats["legacy"]) and "avant le Lot 11" in ld2.message, "maison ancienne : suppression explicite (le terrain aménagé reste, c'est dit)")

# ------------------------------------------------------------------ progression
func _game_save() -> void:
	print("-- progression --")
	GameSave.PATH = DIR + "sauvegarde.json"
	check(GameSave.set_island("t", {"anchor_active": true}) and GameSave.island("t").get("anchor_active", false) == true, "progression écrite et relue")
	GameSave.set_island("t", {"anchor_active": true})      # deuxième écriture : la première devient la sauvegarde de secours
	SafeFile.fail_at = "write"
	var r := GameSave.set_island("t", {"anchor_active": false})
	SafeFile.fail_at = ""
	check(not r and GameSave.last_error != "" and GameSave.island("t").get("anchor_active", false) == true, "écriture impossible : renvoie faux avec une erreur lisible, la sauvegarde existante est intacte")
	var fa := FileAccess.open(GameSave.PATH, FileAccess.WRITE)
	fa.store_string("{abîmé")
	fa.close()
	check(GameSave.island("t").get("anchor_active", false) == true and GameSave.recovered_from_backup, "fichier abîmé : dernière version exploitable relue")
	GameSave.PATH = "user://eclats_sauvegarde.json"
