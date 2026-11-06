extends SceneTree
## Contrôles ciblés du Lot 9 (sans rendu) : habitations générées (3 variantes, déterminisme, recette), pose dans le laboratoire,
## placement automatique sur un plan, composition marché + végétation. godot --headless -s tests/run_checks_lot9.gd
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

func _run() -> void:
	print("== Lot 9 : habitations générées, placement automatique, composition ==")
	_generator_checks()
	await load("res://tests/lot9_lab.gd").run(self)
	await load("res://tests/lot9_plan.gd").run(self)
	print("\n%d contrôles réussis, %d échecs" % [ok, ko])
	quit(1 if ko > 0 else 0)

func _features(m: Construction) -> Dictionary:
	var ridge := {}
	for r in m.of_type("roof"):
		ridge[int(m.roof_shape(r)["ridge_axis"])] = true
	var heights := {}
	for w in m.of_type("wall"):
		heights[float(w["h"])] = true
	return {"walls": m.of_type("wall").size(), "roofs": m.of_type("roof").size(), "ridges": ridge.size(), "heights": heights.size(), "floors": m.of_type("floor").size(),
		"bbox": m.bbox_m().size, "openings": m.count_openings()}

func _generator_checks() -> void:
	var fit := Vector2(9.0, 8.5)
	var sigs := {}
	var feats := {}
	for v in DwellingGenerator.VARIANTS:
		var r := DwellingGenerator.generate(v, 11, fit)
		check(r["ok"], "variante « %s » générée (%s)" % [v, String(r["text"]).left(70)])
		sigs[v] = (r["model"] as Construction).signature()
		feats[v] = _features(r["model"])
	check(sigs["cabane"] != sigs["deux_pieces"] and sigs["deux_pieces"] != sigs["en_L"] and sigs["cabane"] != sigs["en_L"], "trois modèles différents")
	var f1: Dictionary = feats["cabane"]
	var f2: Dictionary = feats["deux_pieces"]
	var f3: Dictionary = feats["en_L"]
	check(f1["walls"] == 4 and f2["walls"] == 5 and f3["walls"] == 7, "agencement distinct : 4 murs (1 pièce) · 5 murs (2 pièces cloisonnées) · 7 murs (2 ailes) — %d / %d / %d" % [f1["walls"], f2["walls"], f3["walls"]])
	check(f1["roofs"] == 1 and f2["roofs"] == 1 and f3["roofs"] == 2 and f3["ridges"] == 2 and f3["heights"] == 2, "volume distinct : la maison en L a deux toits aux faîtages croisés et deux hauteurs de murs")
	check(f2["floors"] == 1 and f3["floors"] == 2, "volumes au sol distincts (plancher unique vs deux ailes)")
	check((f1["bbox"] as Vector2).x * (f1["bbox"] as Vector2).y < (f2["bbox"] as Vector2).x * (f2["bbox"] as Vector2).y and (f2["bbox"] as Vector2).x * (f2["bbox"] as Vector2).y < (f3["bbox"] as Vector2).x * (f3["bbox"] as Vector2).y, "emprises croissantes : cabane < deux pièces < maison en L")
	# déterminisme
	for v in DwellingGenerator.VARIANTS:
		var a := DwellingGenerator.generate(v, 42, fit)
		var b := DwellingGenerator.generate(v, 42, fit)
		check((a["model"] as Construction).signature() == (b["model"] as Construction).signature() and a["recipe"] == b["recipe"], "« %s » : même graine, même emprise, mêmes réglages = même maison" % v)
		var c := DwellingGenerator.generate(v, 43, fit)
		check((c["model"] as Construction).signature() != (a["model"] as Construction).signature(), "« %s » : une autre graine change la maison" % v)
	var au1 := DwellingGenerator.generate("auto", 5, fit)
	var au2 := DwellingGenerator.generate("auto", 5, fit)
	check(au1["variant"] == au2["variant"] and (au1["model"] as Construction).signature() == (au2["model"] as Construction).signature(), "variante « auto » : même graine = même variante (%s)" % au1["variant"])
	var seen := {}
	for sd in 40:
		seen[DwellingGenerator.generate("auto", sd, fit)["variant"]] = true
	check(seen.size() == 3, "« auto » couvre les trois variantes selon la graine")
	# recette reproductible
	var rr := DwellingGenerator.generate("auto", 9, fit)
	var text := LabCommands.recipe_string(rr["recipe"])
	var parsed := LabCommands.parse(text)
	check(parsed["ok"] and parsed["gen"] == "habitation", "la recette « %s » se relit" % text)
	var po: Dictionary = parsed["opts"]
	var again := DwellingGenerator.generate(String(po["variante"]), int(po["seed"]), po["emprise"], {"murs": po["murs"], "toit": po["toit"]})
	check((again["model"] as Construction).signature() == (rr["model"] as Construction).signature(), "rejouer la recette redonne exactement la même habitation")
	# contraintes et refus
	check("Contraintes de pose" in DwellingGenerator.constraints_text(rr) and "30 %" in DwellingGenerator.constraints_text(rr), "contraintes utiles à la pose affichées : %s" % DwellingGenerator.constraints_text(rr).left(90))
	var tiny := DwellingGenerator.generate("auto", 1, Vector2(3.0, 3.0))
	check(not tiny["ok"] and "Emprise trop petite" in String(tiny["reasons"][0]), "emprise trop petite : refus expliqué")
	var small_l := DwellingGenerator.generate("en_L", 1, Vector2(5.0, 5.0))
	check(not small_l["ok"] and "en_L" not in String(small_l["reasons"][0]) and "Maison en L" in String(small_l["reasons"][0]), "maison en L dans 5 × 5 m : refus avec la taille minimale")
	# chaque variante a une porte d'entrée extérieure et des ouvertures valides
	var entr := true
	for v in DwellingGenerator.VARIANTS:
		var m: Construction = DwellingGenerator.generate(v, 3, fit)["model"]
		entr = entr and not m.entrance().is_empty() and Construction.from_dict(m.to_dict())["ok"]
	check(entr, "chaque variante a une porte d'entrée sur l'extérieur et se relit comme fichier de maison")
