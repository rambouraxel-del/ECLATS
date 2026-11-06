extends SceneTree
## Contrôles du Lot 10 (remodelage de l'île d'ouverture) — sans rendu :
##   godot --headless -s tests/run_checks_lot10.gd
## La partie jouée (trajet, maison et étage, détour, Ancre, chute, relance) : tools/opening_recette.gd.

const ARCHIVE := "res://config/islands/archive/ile_ouverture_lot5.json"
var ok := 0
var ko := 0

func check(cond: bool, label: String) -> void:
	if cond:
		ok += 1
		print("  OK    ", label)
	else:
		ko += 1
		print("  ÉCHEC ", label)

func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _dist_path(p: Vector2, pts: PackedVector2Array) -> float:
	var d := 1.0e9
	for i in pts.size() - 1:
		d = minf(d, _dist_seg(p, pts[i], pts[i + 1]))
	return d

func _initialize() -> void:
	print("== Lot 10 : remodelage de l'île d'ouverture ==")
	var map := IslandMap.load_map()
	var old := IslandMap.load_map(ARCHIVE)
	check(not old.is_empty() and old["id"] == map["id"], "carte du Lot 5 conservée (archive) ; même identifiant d'île (sauvegardes compatibles)")
	check(int(map["version"]) == int(old["version"]), "version de la carte inchangée (%d)" % int(map["version"]))
	var ids := {}
	for p in map["paths"]:
		ids[p["id"]] = p
	for id in ["sentier_des_falaises", "descente_du_col", "rue_du_hameau", "lacets_des_hauteurs", "chemin_de_crete", "montee_du_sanctuaire", "detour_du_verger"]:
		check(ids.has(id), "chemin %s toujours présent" % id)
	# --- quai : départ sur le ponton, chaussée dallée jusqu'aux lacets
	check(map["spawn"].has("pier_m") and float(map["spawn"]["pier_m"]) > 1.0, "départ sur le ponton (pier_m = %s)" % map["spawn"].get("pier_m"))
	check(ids.has("quai_dallage") and String(ids["quai_dallage"]["material"]) == "cobble", "chaussée dallée du quai")
	var q := IslandMap.pts(ids["quai_dallage"]["pts"])
	var s := IslandMap.pts(ids["sentier_des_falaises"]["pts"])
	var d := IslandMap.pts(ids["descente_du_col"]["pts"])
	check(q[q.size() - 1].distance_to(s[0]) < 0.6, "chaussée du quai → sentier : raccord continu")
	check(s[s.size() - 1].distance_to(d[0]) < 0.6, "sentier → descente du col : raccord continu")
	var plaza: Dictionary = map["plaza"]
	var pc := IslandMap.v2(plaza["center"])
	var pr := float(plaza["radius"])
	check(absf(d[d.size() - 1].distance_to(pc) - pr) < 1.5, "l'avenue arrive au bord de la place (%.1f m du centre pour un rayon de %.1f m)" % [d[d.size() - 1].distance_to(pc), pr])
	# avenue rectiligne visant la fontaine : les 4 derniers segments sont alignés (≤ 5°) sur la direction de la fontaine
	var worst := 0.0
	for i in range(d.size() - 4, d.size() - 1):
		var dir := (d[i + 1] - d[i]).normalized()
		var to_f := (pc - d[i]).normalized()
		worst = maxf(worst, rad_to_deg(dir.angle_to(to_f)))
	check(worst <= 5.0, "avenue alignée sur la fontaine (écart max %.1f°)" % worst)
	# --- révélation du hameau par le relief : caché depuis le col, dégagé depuis le point de révélation
	var field := AuthoredTerrain.build_field(map)
	var R := Vector2(-60.0, -25.5)
	var col := d[0]
	var fh := field.ground_at_m(pc.x, pc.y) + 2.0                  # sommet de la fontaine
	check(_blocked(field, col, pc, fh), "depuis le col, la fontaine est cachée par le relief")
	check(not _blocked(field, R, pc, fh), "depuis le point de révélation (-60 ; -25,5), la fontaine est en vue (%.0f m)" % R.distance_to(pc))
	# --- objets ajoutés : sur l'île, dégagement des chemins et des allées de porte
	var mains: Array = []
	for p in map["paths"]:
		mains.append({"id": p["id"], "pts": IslandMap.pts(p["pts"]), "hw": float(p.get("width", 1.8)) * 0.5})
	var added := 0
	var off_island := 0
	var blocking: Array[String] = []
	var seeds := {}
	var dup := 0
	var sets := {"props": 0.7, "rocks": 1.4, "trees": 1.1}
	for key in sets:
		var known := {}
		for it in old[key]:
			known[JSON.stringify(it)] = true
		for it in map[key]:
			if known.has(JSON.stringify(it)):
				continue
			added += 1
			var pos := IslandMap.v2(it["pos"])
			var c := field.col_of_m(pos.x, pos.y)
			if not field.has_ground(c.x, c.y):
				off_island += 1
			if it.has("seed"):
				if seeds.has(int(it["seed"])):
					dup += 1
				seeds[int(it["seed"])] = true
			for pp in mains:
				var dd := _dist_path(pos, pp["pts"])
				# les lampes et porte-bannières bordent volontairement un chemin (à plus de la demi-largeur + 0,5 m)
				if dd < float(pp["hw"]) + float(sets[key]) - (0.3 if key == "props" else 0.0):
					blocking.append("%s %s en (%.1f ; %.1f) à %.1f m de %s" % [key, it.get("id", it.get("species", it.get("family", "?"))), pos.x, pos.y, dd, pp["id"]])
	check(added >= 40, "%d objets ajoutés au Lot 10" % added)
	check(off_island == 0, "tous les objets ajoutés sont sur l'île (%d hors de l'île)" % off_island)
	check(dup == 0, "graines des objets ajoutés distinctes")
	for b in blocking:
		print("    · gêne : ", b)
	check(blocking.is_empty(), "aucun objet ajouté ne gêne un chemin (%d)" % blocking.size())
	for b in map["buildings"]:
		for dp in b.get("door_path", []):
			var dpv := IslandMap.v2(dp)
			var near_door := 0
			for key in ["props", "rocks", "trees"]:
				var known2 := {}
				for it in old[key]:
					known2[JSON.stringify(it)] = true
				for it in map[key]:
					if not known2.has(JSON.stringify(it)) and IslandMap.v2(it["pos"]).distance_to(dpv) < 1.8:
						near_door += 1
			check(near_door == 0, "allée de « %s » dégagée" % b["id"])
	# --- sanctuaire et crête (étape 2 : marquée par l'épaule de raccord du chemin de crête)
	if not ids["chemin_de_crete"].has("skirt"):
		print("  (étape 2 non appliquée : contrôles de la crête et du sanctuaire ignorés)")
		print("== %d réussite(s), %d échec(s) ==" % [ok, ko])
		quit(1 if ko > 0 else 0)
		return
	var m := IslandMap.pts(ids["montee_du_sanctuaire"]["pts"])
	var anchor := IslandMap.v2(map["anchor"]["pos"])
	var free_axis := true
	for key in ["props", "rocks"]:
		for it in map[key]:
			var pos2 := IslandMap.v2(it["pos"])
			var id := String(it.get("id", it.get("family", "")))
			if id == "ruin_arch" or id == "teleport_anchor" or id == "anchor_pedestal":
				continue
			if _dist_seg(pos2, m[m.size() - 1], anchor) < 1.2:
				free_axis = false
				print("    · sur l'axe de montée : ", id, pos2)
	check(free_axis, "axe gradins → cristal dégagé (hors arche d'entrée)")
	check(_has_prop(map, "ruin_arch", Vector2(26.0, -76.6)), "arche d'entrée en haut des gradins")
	check(_count_prop(map, "brazier") >= 4, "braseros au pied et en haut de la montée (%d)" % _count_prop(map, "brazier"))
	print("== %d réussite(s), %d échec(s) ==" % [ok, ko])
	quit(1 if ko > 0 else 0)

func _has_prop(map: Dictionary, id: String, pos: Vector2) -> bool:
	for p in map["props"]:
		if p["id"] == id and IslandMap.v2(p["pos"]).distance_to(pos) < 0.5:
			return true
	return false

func _count_prop(map: Dictionary, id: String) -> int:
	var n := 0
	for p in map["props"]:
		if p["id"] == id:
			n += 1
	return n

## Vrai si le relief coupe la ligne de visée œil (1,7 m au-dessus du sol en a) → sommet visé (hauteur h en b).
func _blocked(field: TerrainField, a: Vector2, b: Vector2, h_target: float) -> bool:
	var ya := field.ground_at_m(a.x, a.y) + 1.7
	var n := int(a.distance_to(b))
	for i in range(1, n):
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		var g := field.ground_at_m(p.x, p.y)
		var los := lerpf(ya, h_target, t)
		if not is_nan(g) and g > los:
			return true
	return false
