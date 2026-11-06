extends SceneTree
## Contrôles rapides du Lot 5 (île d'ouverture) — sans rendu :
##   godot --headless -s tests/run_checks_lot5.gd
## La partie jouée complète (trajet, maison, détour, Ancre, chute, relance) : tools/opening_recette.gd.

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
	print("== Lot 5 : île d'ouverture ==")
	var map := IslandMap.load_map()
	check(not map.is_empty(), "carte chargée (%s)" % IslandMap.DEFAULT_PATH)
	check(String(map.get("id", "")) == "ile-ouverture-01", "identifiant fixe de l'île : %s" % map.get("id", "?"))
	for k in ["terrain", "paths", "buildings", "trees", "rocks", "props", "anchor", "spawn", "zones", "plaza", "pier"]:
		check(map.has(k), "section « %s » présente" % k)
	var ids := {}
	for p in map["paths"]:
		ids[p["id"]] = p
	for id in ["sentier_des_falaises", "descente_du_col", "rue_du_hameau", "lacets_des_hauteurs", "chemin_de_crete", "montee_du_sanctuaire", "detour_du_verger"]:
		check(ids.has(id), "chemin %s" % id)
	check(bool(ids.get("montee_du_sanctuaire", {}).get("regular", false)), "montée du sanctuaire à marches régulières")
	# longueur de l'itinéraire principal et temps de marche visé
	var length := 0.0
	for p in map["paths"]:
		if String(p.get("kind", "main")) != "main":
			continue
		var pts := IslandMap.pts(p["pts"])
		for i in pts.size() - 1:
			length += pts[i].distance_to(pts[i + 1])
	var spd := float(map.get("walk_speed_mps", 2.2))
	check(length / spd >= 240.0 and length / spd <= 360.0, "itinéraire principal %.0f m : %.1f min à %.1f m/s (visé 4 à 6 min)" % [length, length / spd / 60.0, spd])
	# détour : rejoint le chemin principal
	var d1 := IslandMap.pts(ids["detour_du_verger"]["pts"])
	var joins := 0
	for end in [d1[0], d1[d1.size() - 1]]:
		for p in map["paths"]:
			if String(p.get("kind", "main")) != "main":
				continue
			var pts := IslandMap.pts(p["pts"])
			for i in pts.size() - 1:
				if Geometry2D.get_closest_point_to_segment(end, pts[i], pts[i + 1]).distance_to(end) < 1.5:
					joins += 1
					break
	check(joins >= 2, "le détour part du chemin principal et le rejoint (%d raccords)" % joins)
	# zones : chacune a un repère
	check((map["zones"] as Array).size() >= 6, "%d zones nommées" % (map["zones"] as Array).size())
	for z in map["zones"]:
		check(String(z.get("landmark", "")) != "", "repère de « %s »" % z["name"])
	var vis := 0
	for b in map["buildings"]:
		if bool(b.get("visitable", false)):
			vis += 1
			check(String(b["type"]) == "house_large", "maison visitable à étage (house_large)")
	check(vis == 1, "une maison visitable")
	# relief : île bien plus grande que l'île de test, départ et Ancre sur le sol
	var t0 := Time.get_ticks_msec()
	var field := AuthoredTerrain.build_field(map)
	var area := float(field.land_count()) * 0.04
	check(area > 20000.0, "île de %.0f m² (île de test ≈ 2 100 m²) — relief en %d ms" % [area, Time.get_ticks_msec() - t0])
	var sp := IslandMap.v2(map["spawn"]["pos"])
	var an := IslandMap.v2(map["anchor"]["pos"])
	var cs := field.col_of_m(sp.x, sp.y)
	var ca := field.col_of_m(an.x, an.y)
	check(field.has_ground(cs.x, cs.y), "départ (quai) sur l'île")
	check(field.has_ground(ca.x, ca.y), "Ancre sur l'île")
	var hq := field.ground_at_m(sp.x, sp.y)
	var ha := field.ground_at_m(an.x, an.y)
	check(ha - hq > 15.0, "quai en contrebas, sanctuaire en hauteur (%.1f m → %.1f m)" % [hq, ha])
	var inside := 0
	for t in map["trees"]:
		var p := IslandMap.v2(t["pos"])
		var c := field.col_of_m(p.x, p.y)
		if field.has_ground(c.x, c.y):
			inside += 1
	check(inside >= (map["trees"] as Array).size() - 2, "arbres sur l'île (%d / %d)" % [inside, (map["trees"] as Array).size()])
	# commandes et sauvegarde
	GameInput.ensure()
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "interact"]:
		check(InputMap.has_action(a), "action %s" % a)
	var ev: InputEventKey = InputMap.action_get_events("move_forward")[0]
	check(ev.physical_keycode == KEY_W, "avancer = touche physique W (Z en AZERTY)")
	check(GameInput.key_label("interact") == "E", "libellé de la touche d'activation : %s" % GameInput.key_label("interact"))
	var test_id := "test-lot5-%d" % Time.get_ticks_msec()
	GameSave.set_island(test_id, {"anchor_active": true})
	check(bool(GameSave.island(test_id).get("anchor_active", false)), "sauvegarde relue sous l'identifiant de l'île")
	GameSave.clear_island(test_id)
	check(GameSave.island(test_id).is_empty(), "sauvegarde de test effacée")
	var sig := AuthoredIslandBuilder.signature(map)
	check(sig.begins_with("ile-ouverture-01_"), "clé de cache liée à la carte : %s" % sig)
	print("== %d réussite(s), %d échec(s) ==" % [ok, ko])
	quit(1 if ko > 0 else 0)
