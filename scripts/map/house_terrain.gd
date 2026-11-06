class_name HouseTerrain
extends RefCounted
## TERRAIN D'UNE MAISON POSÉE (Lot 11) : les colonnes de relief et de matière que la pose a modifiées (plateforme, cour, raccord),
## avec les retouches d'AVANT et celles écrites PAR la pose. Sert à
##   • garder la maison cohérente quand le relief de base est recalculé (déplacement d'un chemin, d'une zone…) :
##     la hauteur ABSOLUE des colonnes est conservée, les retouches sont recalculées par rapport au nouveau relief ;
##   • restaurer le terrain à la suppression de la maison sans effacer les retouches faites depuis (colonne par colonne).
## Représentation : Dictionary {cells, before_d, placed_d, before_m, placed_m} (tableaux alignés ; cells = indices de colonnes de la grille
## du plan, ox/oz/n = repère de cette grille au moment de l'écriture, pour pouvoir convertir si la grille change).

const MAX_CELLS := 400000

static func make(layers: PlanLayers, before_d: PackedInt32Array, before_m: PackedByteArray, cells: Array) -> Dictionary:
	var c := PackedInt32Array()
	var bd := PackedInt32Array()
	var pd := PackedInt32Array()
	var bm := PackedByteArray()
	var pm := PackedByteArray()
	for i in cells:
		c.append(i)
		bd.append(before_d[i])
		pd.append(layers.delta[i])
		bm.append(before_m[i])
		pm.append(layers.mat[i])
	return {"cells": c, "before_d": bd, "placed_d": pd, "before_m": bm, "placed_m": pm, "n": layers.n, "ox": layers.ox, "oz": layers.oz}

static func _enc32(a: PackedInt32Array) -> String:
	return PlanLayers._enc(a.to_byte_array())

static func to_dict(t: Dictionary) -> Dictionary:
	return {"n": t["n"], "origin": [t["ox"], t["oz"]], "count": (t["cells"] as PackedInt32Array).size(),
		"cells": _enc32(t["cells"]), "before_d": _enc32(t["before_d"]), "placed_d": _enc32(t["placed_d"]),
		"before_m": PlanLayers._enc(t["before_m"]), "placed_m": PlanLayers._enc(t["placed_m"])}

static func parse(d) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return {"ok": false, "error": "contenu mal formé."}
	for k in ["n", "origin", "count", "cells", "before_d", "placed_d", "before_m", "placed_m"]:
		if not d.has(k):
			return {"ok": false, "error": "le champ « %s » manque." % k}
	if not IslandPlan._in(d["count"], 0.0, float(MAX_CELLS)) or not IslandPlan._in(d["n"], 1.0, 4096.0) or typeof(d["origin"]) != TYPE_ARRAY or (d["origin"] as Array).size() != 2:
		return {"ok": false, "error": "taille ou origine hors limites."}
	var cnt := int(d["count"])
	var n := int(d["n"])
	var out := {"n": n, "ox": int(d["origin"][0]), "oz": int(d["origin"][1])}
	for k in ["cells", "before_d", "placed_d"]:
		var raw := PlanLayers._dec(String(d[k]), cnt * 4)
		if raw.is_empty() and cnt > 0:
			return {"ok": false, "error": "« %s » est illisible ou de mauvaise taille." % k}
		out[k] = raw.to_int32_array()
	for k in ["before_m", "placed_m"]:
		var raw2 := PlanLayers._dec(String(d[k]), cnt)
		if raw2.is_empty() and cnt > 0:
			return {"ok": false, "error": "« %s » est illisible ou de mauvaise taille." % k}
		out[k] = raw2
	for i in cnt:
		var ci: int = out["cells"][i]
		if ci < 0 or ci >= n * n:
			return {"ok": false, "error": "une colonne est hors de la grille."}
		if absi(int(out["before_d"][i])) > PlanLayers.MAX_DELTA or absi(int(out["placed_d"][i])) > PlanLayers.MAX_DELTA:
			return {"ok": false, "error": "une retouche dépasse la limite de relief."}
	return {"ok": true, "terrain": out}
