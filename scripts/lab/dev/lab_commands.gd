class_name LabCommands
extends RefCounted
## Langage de commandes du laboratoire (barre ouverte avec T) ET format des recettes copiées : une seule grammaire.
##   /generer arbre   [--espece chene|parasol|pin|saule|bouleau|fruitier|mort] [--graine N]
##   /generer rocher  [--famille bloc|affleurement|formation|ruine] [--graine N] [--echelle 1.0]
##   /generer maison  [--graine N] [--emprise 3.5x3.5] [--yaw 0-3] [--murs pierre|enduit|bois] [--toit chaume|bardeaux|tuiles|ardoise]
##   /generer habitation [--variante auto|cabane|deux_pieces|en_L] [--graine N] [--emprise 8x6] [--yaw 0-3] [--murs …] [--toit …]
##   /generer composition [--etals 0-5] [--vegetation 0-100] [--graine N] [--rayon R] [--trace x,z;x,z…]   (marché + végétation sur la zone peinte)
##   /aplanir         [--niveau M] [--rayon R] [--trace x,z;x,z…]
##   /confirmer · /annuler (aperçu) · /defaire (Ctrl+Z) · /recette (copier) · /rect LxP · /point x z · /pinceau R · /effacer · /aide
## Les nombres acceptent la virgule (3,5) ; les accents sont facultatifs.

const SPECIES := {"chene": "oak", "oak": "oak", "parasol": "parasol", "pin": "pine", "pine": "pine", "saule": "weeping", "weeping": "weeping",
	"bouleau": "birch", "birch": "birch", "fruitier": "fruit", "fruit": "fruit", "mort": "dead", "dead": "dead"}
const SPECIES_NAMES := {"oak": "chene", "parasol": "parasol", "pine": "pin", "weeping": "saule", "birch": "bouleau", "fruit": "fruitier", "dead": "mort"}
const FAMILIES := {"bloc": "boulder", "boulder": "boulder", "affleurement": "outcrop", "outcrop": "outcrop", "formation": "formation", "ruine": "ruin", "ruin": "ruin"}
const FAMILY_NAMES := {"boulder": "bloc", "outcrop": "affleurement", "formation": "formation", "ruin": "ruine"}
const WALLS := {"pierre": "stone", "stone": "stone", "enduit": "plaster", "plaster": "plaster", "bois": "timber", "timber": "timber"}
const WALL_NAMES := {"stone": "pierre", "plaster": "enduit", "timber": "bois"}
const ROOFS := {"chaume": "thatch", "thatch": "thatch", "bardeaux": "shingle", "shingle": "shingle", "tuiles": "tiles", "tiles": "tiles", "ardoise": "slate", "slate": "slate"}
const VARIANTS := {"auto": "auto", "cabane": "cabane", "deux_pieces": "deux_pieces", "deux-pieces": "deux_pieces", "deuxpieces": "deux_pieces", "deux": "deux_pieces",
	"en_l": "en_L", "en-l": "en_L", "enl": "en_L", "l": "en_L"}
const ROOF_NAMES := {"thatch": "chaume", "shingle": "bardeaux", "tiles": "tuiles", "slate": "ardoise"}

static func _fold(s: String) -> String:
	var t := s.to_lower()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ô", "o"], ["û", "u"], ["ç", "c"]]:
		t = t.replace(pair[0], pair[1])
	return t

static func _num(s: String) -> float:
	return s.replace(",", ".").to_float()

## Analyse une ligne. Retour : {ok, cmd, gen, opts, error}. `cmd` : generer | aplanir | confirmer | annuler | defaire | recette | rect | point | pinceau | effacer | aide
static func parse(line: String) -> Dictionary:
	var out := {"ok": false, "cmd": "", "gen": "", "opts": {}, "args": [], "error": ""}
	var txt := _fold(line.strip_edges())
	if txt == "":
		out["error"] = "Commande vide. Exemple : /generer maison --graine 42"
		return out
	if not txt.begins_with("/"):
		txt = "/" + txt
	var toks := txt.substr(1).split(" ", false)
	var cmd := String(toks[0])
	var aliases := {"generer": "generer", "gen": "generer", "aplanir": "aplanir", "confirmer": "confirmer", "ok": "confirmer", "annuler": "annuler",
		"defaire": "defaire", "undo": "defaire", "recette": "recette", "rect": "rect", "rectangle": "rect", "point": "point", "pinceau": "pinceau",
		"effacer": "effacer", "aide": "aide", "help": "aide", "rejouer": "rejouer", "replay": "rejouer"}
	if not aliases.has(cmd):
		out["error"] = "Commande inconnue : /%s (essayez /aide)" % cmd
		return out
	out["cmd"] = aliases[cmd]
	var i := 1
	var opts := {}
	var args: Array = []
	while i < toks.size():
		var tk := String(toks[i])
		if tk.begins_with("--"):
			var key := tk.substr(2)
			var val := ""
			if i + 1 < toks.size() and not String(toks[i + 1]).begins_with("--"):
				val = String(toks[i + 1])
				i += 1
			opts[key] = val
		else:
			args.append(tk)
		i += 1
	out["args"] = args
	if out["cmd"] == "generer":
		if args.is_empty():
			out["error"] = "Précisez quoi générer : arbre, rocher, maison, habitation ou composition."
			return out
		var g := String(args[0])
		var gens := {"arbre": "arbre", "tree": "arbre", "rocher": "rocher", "rock": "rocher", "maison": "maison", "house": "maison", "cabane": "maison",
			"habitation": "habitation", "hab": "habitation", "dwelling": "habitation", "composition": "composition", "marche": "composition", "market": "composition"}
		if not gens.has(g):
			out["error"] = "Générateur inconnu : %s (arbre, rocher, maison, habitation, composition)" % g
			return out
		out["gen"] = gens[g]
	var parsed := {}
	for k in opts:
		var v := String(opts[k])
		match k:
			"graine", "seed":
				if not v.is_valid_int():
					out["error"] = "--graine attend un entier."
					return out
				parsed["seed"] = int(v)
			"espece":
				if not SPECIES.has(v):
					out["error"] = "Espèce inconnue : %s (%s)" % [v, ", ".join(SPECIES_NAMES.values())]
					return out
				parsed["espece"] = SPECIES[v]
			"famille":
				if not FAMILIES.has(v):
					out["error"] = "Famille inconnue : %s (%s)" % [v, ", ".join(FAMILY_NAMES.values())]
					return out
				parsed["famille"] = FAMILIES[v]
			"echelle":
				parsed["echelle"] = clampf(_num(v), 0.4, 2.0)
			"emprise":
				var d := v.replace("×", "x").split("x")
				if d.size() != 2 or _num(d[0]) <= 0.0 or _num(d[1]) <= 0.0:
					out["error"] = "--emprise attend LxP en mètres, par exemple 3.5x3.5."
					return out
				parsed["emprise"] = Vector2(_num(d[0]), _num(d[1]))
			"yaw":
				if not v.is_valid_int():
					out["error"] = "--yaw attend 0, 1, 2 ou 3 (quarts de tour)."
					return out
				parsed["yaw"] = posmod(int(v), 4)
			"murs":
				if out["gen"] == "habitation":
					if not Construction.WALL_MATS.has(v):
						out["error"] = "Murs inconnus : %s (pierre, enduit, bois)" % v
						return out
					parsed["murs"] = v
				else:
					if not WALLS.has(v):
						out["error"] = "Murs inconnus : %s (pierre, enduit, bois)" % v
						return out
					parsed["murs"] = WALLS[v]
			"toit":
				if out["gen"] == "habitation":
					if not Construction.ROOF_MATS.has(v):
						out["error"] = "Toit inconnu : %s (chaume, bardeaux, tuiles, ardoise)" % v
						return out
					parsed["toit"] = v
				else:
					if not ROOFS.has(v):
						out["error"] = "Toit inconnu : %s (chaume, bardeaux, tuiles, ardoise)" % v
						return out
					parsed["toit"] = ROOFS[v]
			"variante":
				if not VARIANTS.has(v):
					out["error"] = "Variante inconnue : %s (auto, cabane, deux_pieces, en_L)" % v
					return out
				parsed["variante"] = VARIANTS[v]
			"etals":
				if not v.is_valid_int():
					out["error"] = "--etals attend un entier de 0 à 5."
					return out
				parsed["etals"] = clampi(int(v), 0, 5)
			"vegetation":
				if not v.is_valid_int():
					out["error"] = "--vegetation attend un pourcentage de 0 à 100."
					return out
				parsed["vegetation"] = clampi(int(v), 0, 100)
			"niveau":
				if v != "auto" and v != "":
					parsed["niveau"] = _num(v)
			"rayon":
				parsed["rayon"] = clampf(_num(v), 0.4, 5.0)
			"trace":
				var pts: Array = []
				for q in v.split(";", false):
					var xy := q.split(",")
					if xy.size() == 2:
						pts.append(Vector2(_num(xy[0]), _num(xy[1])))
				parsed["trace"] = pts
			_:
				out["error"] = "Option inconnue : --%s" % k
				return out
	out["opts"] = parsed
	out["ok"] = true
	return out

static func _f(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0") and s.contains("."):
		s = s.substr(0, s.length() - 1)
	return s.trim_suffix(".")

## Recette → commande (ex. « /generer maison --graine 42 --emprise 3.5x3.5 --yaw 0 »).
static func recipe_string(r: Dictionary) -> String:
	var gen := String(r.get("gen", ""))
	var o: Dictionary = r.get("opts", {})
	var parts := PackedStringArray()
	if gen == "aplanir":
		parts.append("/aplanir")
		if o.has("niveau"):
			parts.append("--niveau " + _f(float(o["niveau"])))
		parts.append("--rayon " + _f(float(o.get("rayon", 1.2))))
		if o.has("trace"):
			var pts := PackedStringArray()
			for q: Vector2 in o["trace"]:
				pts.append("%s,%s" % [_f(q.x), _f(q.y)])
			parts.append("--trace " + ";".join(pts))
		return " ".join(parts)
	if gen == "composition":
		parts.append("/generer composition")
		parts.append("--graine %d" % int(o.get("seed", 1)))
		parts.append("--etals %d" % int(o.get("etals", 3)))
		parts.append("--vegetation %d" % int(o.get("vegetation", 50)))
		parts.append("--rayon " + _f(float(o.get("rayon", 1.2))))
		if o.has("trace"):
			var pts2 := PackedStringArray()
			for q: Vector2 in o["trace"]:
				pts2.append("%s,%s" % [_f(q.x), _f(q.y)])
			parts.append("--trace " + ";".join(pts2))
		return " ".join(parts)
	parts.append("/generer " + gen)
	match gen:
		"habitation":
			parts.append("--variante " + String(o.get("variante", "auto")))
			parts.append("--graine %d" % int(o.get("seed", 1)))
			var e2: Vector2 = o.get("emprise", Vector2.ZERO)
			parts.append("--emprise %sx%s" % [_f(e2.x), _f(e2.y)])
			parts.append("--yaw %d" % int(o.get("yaw", 0)))
			if o.has("murs"):
				parts.append("--murs " + String(WALL_NAMES.get(o["murs"], o["murs"])))
			if o.has("toit"):
				parts.append("--toit " + String(ROOF_NAMES.get(o["toit"], o["toit"])))
		"arbre":
			parts.append("--espece " + String(SPECIES_NAMES.get(o.get("espece", "oak"), "chene")))
			parts.append("--graine %d" % int(o.get("seed", 1)))
		"rocher":
			parts.append("--famille " + String(FAMILY_NAMES.get(o.get("famille", "boulder"), "bloc")))
			parts.append("--graine %d" % int(o.get("seed", 1)))
			if absf(float(o.get("echelle", 1.0)) - 1.0) > 0.01:
				parts.append("--echelle " + _f(float(o["echelle"])))
		"maison":
			parts.append("--graine %d" % int(o.get("seed", 1)))
			var e: Vector2 = o.get("emprise", Vector2.ZERO)
			parts.append("--emprise %sx%s" % [_f(e.x), _f(e.y)])
			parts.append("--yaw %d" % int(o.get("yaw", 0)))
			if o.has("murs"):
				parts.append("--murs " + String(WALL_NAMES.get(o["murs"], o["murs"])))
			if o.has("toit"):
				parts.append("--toit " + String(ROOF_NAMES.get(o["toit"], o["toit"])))
	return " ".join(parts)

const HELP := "Commandes : /generer arbre|rocher|maison|habitation|composition [--graine N] … · /aplanir [--niveau M] · /confirmer · /annuler · /defaire · /recette · /rect 3.5 3.5 · /point x z · /pinceau R · /effacer"
