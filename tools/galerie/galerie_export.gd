extends SceneTree
## Export de la galerie 3D : détecte les modèles précuits et les générateurs enregistrés, exporte chaque
## modèle en glTF binaire (.glb) et écrit le catalogue (catalogue.json).
##   tools/galerie.sh                       (commande reproductible : import + export)
##   godot --headless -s tools/galerie/galerie_export.gd -- [--sortie=galerie] [--seulement=famille] [--max=N]
## Sortie : <sortie>/catalogue.json et <sortie>/modeles/*.glb (voir docs/GALERIE_3D.md).
## Familles : precuit · asset_arbre · asset_rocher · nature_arbre · nature_rocher · nature_ruine · batiment ·
##            habitation · bateau · lot1 · exemple · manuel

const CONFIG := "res://tools/galerie/config.json"
const MANUELS := "res://tools/galerie/manuels"
const MAISONS := "res://assets/maisons"

var _out := "res://galerie"
var _only := ""
var _max := 0
var _cfg: Dictionary = {}
var _entries: Array = []
var _skipped: Array = []
var _mats := {}
var _registered_scripts := {}      # chemin de script → nom de famille (pour la détection des non exportés)
var _t0 := 0

func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sortie="):
			_out = a.substr(9)
		elif a.begins_with("--seulement="):
			_only = a.substr(12)
		elif a.begins_with("--max="):
			_max = int(a.substr(6))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Configuration illisible : %s" % CONFIG)
		quit(1)
		return
	_cfg = parsed
	DirAccess.make_dir_recursive_absolute(_abs(_out + "/modeles"))
	VoxelMesher.palette_warmup()
	_run()
	_write_catalog()
	print("Galerie : %d modèles exportés, %d éléments non exportés, %.1f s" % [_entries.size(), _skipped.size(), float(Time.get_ticks_msec() - _t0) / 1000.0])
	quit(0)

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") else p

func _want(family: String) -> bool:
	return _only == "" or _only == family

# ------------------------------------------------------------------ familles

func _run() -> void:
	if _want("precuit"):
		_family_precooked()
	for gen in ["asset_arbre", "asset_rocher"]:
		if _want(gen):
			_family_asset_generated(gen)
	if _want("nature_arbre"):
		_family_nature_tree()
	if _want("nature_rocher") or _want("nature_ruine"):
		_family_nature_rock()
	if _want("batiment"):
		_family_building()
	if _want("habitation"):
		_family_dwelling()
	if _want("bateau"):
		_family_ship()
	if _want("lot1"):
		_family_lot1()
	if _want("exemple"):
		_family_examples()
	if _want("manuel"):
		_family_manual()
	if _want("personnage"):
		_family_character()
	if _only == "":
		_detect_unexported()

func _gen_cfg(key: String) -> Dictionary:
	var g: Dictionary = (_cfg.get("generateurs", {}) as Dictionary).get(key, {})
	return g

func _combos(axes: Dictionary, auto_values: Dictionary) -> Array:
	# produit cartésien des axes (« auto » → valeurs détectées dans le code)
	var out: Array = [{}]
	for k in axes:
		var vals: Array = auto_values.get(k, []) if typeof(axes[k]) == TYPE_STRING else axes[k]
		var nxt: Array = []
		for base in out:
			for v in vals:
				var d: Dictionary = base.duplicate()
				d[k] = v
				nxt.append(d)
		out = nxt
	return out

# --- précuits (assets/props/*/*.tscn) : ce que le jeu charge réellement
func _family_precooked() -> void:
	_registered_scripts["res://scripts/assets/asset_library.gd"] = "precuit"
	var ids := AssetLibrary.all_ids()
	var count := 0
	for id in ids:
		if _max > 0 and count >= _max:
			break
		count += 1
		var entry: Array = AssetLibrary._all()[id]
		_registered_scripts[String(entry[1])] = "precuit"
		var cat := _asset_category(id)
		var meshes: Array = []
		var source := "precuit"
		var scene_exists := ResourceLoader.exists(AssetLibrary.scene_path(id))
		var name_fr := id
		if scene_exists:
			var inst := AssetLibrary.instantiate(id)
			_harvest(inst, Transform3D.IDENTITY, meshes)
			var info := AssetLibrary.info(id)
			name_fr = String(info.get("name", id))
			inst.free()
		else:
			# enregistré mais pas encore « baké » : on le construit à la volée (il apparaît quand même)
			source = "genere"
			var a := AssetLibrary.build(id)
			name_fr = a.display_name
			meshes = _asset_meshes(a)
		var args: Dictionary = entry[2] if entry.size() > 2 else {}
		_add(id, name_fr, cat, "precuit" if scene_exists else "enregistre", "", {}, meshes, String(entry[1]), {"groupe": String(entry[0]), "params": args})

func _asset_category(id: String) -> String:
	var entry: Array = AssetLibrary._all()[id]
	var script := String(entry[1])
	if id in ["artisan_workbench"]:
		return "Artisanat"
	if id in ["ancient_chest", "anchor_pedestal"]:
		return "Vestiges et cristaux"
	if id in ["market_stall"]:
		return "Village"
	if id in ["decorative_bench"]:
		return "Décor"
	if id in ["pier", "sky_ship"]:
		return "Port et navires"
	if script.ends_with("trees.gd"):
		return "Arbres"
	if script.ends_with("rocks.gd"):
		return "Rochers et ruines"
	if script.ends_with("houses.gd"):
		return "Bâtiments"
	if script.ends_with("props_village.gd"):
		return "Village"
	if script.ends_with("props_decor.gd"):
		return "Décor"
	if script.ends_with("props_craft.gd"):
		return "Artisanat"
	if script.ends_with("props_ancient.gd"):
		return "Vestiges et cristaux"
	return "Divers"

# --- variantes des générateurs de la bibliothèque (arbres, rochers) : mêmes scripts que le registre
func _family_asset_generated(gen: String) -> void:
	var g := _gen_cfg(gen)
	if g.is_empty() or not bool(g.get("actif", true)):
		return
	var suffix := "trees.gd" if gen == "asset_arbre" else "rocks.gd"
	var template := {}
	var script := ""
	for id in AssetLibrary.all_ids():
		var e: Array = AssetLibrary._all()[id]
		if String(e[1]).ends_with(suffix):
			script = String(e[1])
			template = (e[2] as Dictionary).duplicate()
			break
	if script == "":
		_skipped.append({"nom": g.get("nom", gen), "type": "générateur", "raison": "Aucune entrée du registre n'utilise %s." % suffix, "comment": "Enregistrer une entrée dans scripts/assets/asset_registry_lot3.gd."})
		return
	_registered_scripts[script] = gen
	var species := PackedStringArray(["oak", "parasol", "pine", "weeping", "birch", "fruit"])
	var combos := _combos(g.get("axes", {}), {"species": Array(species)})
	var count := 0
	for combo in combos:
		for seed in g.get("graines", [1]):
			if _max > 0 and count >= _max:
				return
			count += 1
			var args := template.duplicate()
			args.merge(combo, true)
			args["seed"] = int(seed)
			var label := ""
			if gen == "asset_arbre":
				label = "%s — graine %d" % [_species_fr(String(args["species"])), seed]
				args["name"] = label
			else:
				label = "Rocher %s %d — graine %d" % ["chaud" if args.get("warm", true) else "gris", int(args.get("size", 18)), seed]
			var asset: VoxelAsset = (load(script) as GDScript).call("build", args)
			var id := "%s_%s" % [gen, _slug(combo, int(seed))]
			_add(id, label, String(g.get("categorie", "Divers")), "genere", gen, _with_seed(combo, int(seed)), _asset_meshes(asset), script, {})

func _species_fr(s: String) -> String:
	return {"oak": "Chêne", "parasol": "Arbre parasol", "pine": "Pin", "weeping": "Saule pleureur", "birch": "Bouleau", "fruit": "Arbre fruitier", "dead": "Arbre mort"}.get(s, s.capitalize())

func _slug(combo: Dictionary, seed: int) -> String:
	var parts: PackedStringArray = []
	for k in combo:
		parts.append(str(combo[k]).replace(" ", "").to_lower())
	parts.append("g%d" % seed)
	return "_".join(parts)

func _with_seed(combo: Dictionary, seed: int) -> Dictionary:
	var d := combo.duplicate()
	d["graine"] = seed
	return d

# --- arbres du monde (TreeGenerator)
func _family_nature_tree() -> void:
	var g := _gen_cfg("nature_arbre")
	if g.is_empty() or not bool(g.get("actif", true)):
		return
	_registered_scripts["res://scripts/world/nature/tree_generator.gd"] = "nature_arbre"
	_registered_scripts["res://scripts/world/nature/voxel_object_view.gd"] = "nature_arbre"
	var count := 0
	for combo in _combos(g.get("axes", {}), {"espece": Array(TreeGenerator.SPECIES.keys())}):
		for seed in g.get("graines", [1]):
			if _max > 0 and count >= _max:
				return
			count += 1
			var sp := String(combo["espece"])
			var m := TreeGenerator.rasterize(TreeGenerator.plan(sp, int(seed)), {})
			var parts: Array = [{"name": "bois", "volume": m["wood"], "origin": m["wood_origin"], "grid": TreeGenerator.C, "material": "props"}]
			if m["foliage"] != null:
				parts.append({"name": "feuillage", "volume": m["foliage"], "origin": m["foliage_origin"], "grid": TreeGenerator.F, "material": "props"})
			if m.get("fruits") != null:
				parts.append({"name": "fruits", "volume": m["fruits"], "origin": m["foliage_origin"], "grid": TreeGenerator.C, "material": "props"})
			_add("nature_arbre_%s_g%d" % [sp, seed], "%s du monde — graine %d" % [_species_fr(sp), seed], String(g.get("categorie", "Arbres")), "genere", "nature_arbre",
					_with_seed(combo, int(seed)), _parts_meshes(parts), "res://scripts/world/nature/tree_generator.gd", {})

# --- rochers et vestiges du monde (RockGenerator)
func _family_nature_rock() -> void:
	_registered_scripts["res://scripts/world/nature/rock_generator.gd"] = "nature_rocher"
	var g := _gen_cfg("nature_rocher")
	var count := 0
	if not g.is_empty() and bool(g.get("actif", true)) and _want("nature_rocher"):
		var fams := Array(RockGenerator.families())
		fams.erase("ruin")
		for combo in _combos(g.get("axes", {}), {"famille": fams}):
			if String(combo["famille"]) == "ruin":
				continue
			for seed in g.get("graines", [1]):
				if _max > 0 and count >= _max:
					return
				count += 1
				var fam := String(combo["famille"])
				var m := RockGenerator.rasterize(RockGenerator.plan(fam, int(seed)), {})
				var parts: Array = [{"name": "roche", "volume": m["volume"], "origin": m["origin"], "grid": RockGenerator.C, "material": "props"}]
				_add("nature_rocher_%s_g%d" % [fam, seed], "%s du monde — graine %d" % [{"boulder": "Bloc", "outcrop": "Affleurement", "formation": "Formation"}.get(fam, fam), seed],
						String(g.get("categorie", "Rochers et ruines")), "genere", "nature_rocher", _with_seed(combo, int(seed)), _parts_meshes(parts), "res://scripts/world/nature/rock_generator.gd", {})
	var r := _gen_cfg("nature_ruine")
	if not r.is_empty() and bool(r.get("actif", true)) and _want("nature_ruine"):
		for combo in _combos(r.get("axes", {}), {}):
			for seed in r.get("graines", [1]):
				var sub := String(combo["sous_type"])
				var m2 := RockGenerator.rasterize(RockGenerator.plan("ruin", int(seed), sub), {})
				var parts2: Array = [{"name": "vestige", "volume": m2["volume"], "origin": m2["origin"], "grid": RockGenerator.C, "material": "props"}]
				_add("nature_ruine_%s_g%d" % [sub, seed], "Vestige (%s) — graine %d" % [{"column": "colonne", "arch": "arche", "wall": "mur", "slab": "dalle"}.get(sub, sub), seed],
						String(r.get("categorie", "Rochers et ruines")), "genere", "nature_ruine", _with_seed(combo, int(seed)), _parts_meshes(parts2), "res://scripts/world/nature/rock_generator.gd", {})

# --- bâtiments (BuildingPlanner → BuildingBuilder → BuildingView)
func _family_building() -> void:
	var g := _gen_cfg("batiment")
	if g.is_empty() or not bool(g.get("actif", true)):
		return
	for s in ["building_planner", "building_builder", "building_view", "building_catalog", "building_details", "building_furnisher", "roof_builder", "building_model", "building_plan", "building_validator", "building_placement"]:
		_registered_scripts["res://scripts/world/building/%s.gd" % s] = "batiment"
	var types: Array = Array(BuildingCatalog.TYPES)
	types.append("hut")
	var count := 0
	for combo in _combos(g.get("axes", {}), {"type": types}):
		for seed in g.get("graines", [1]):
			if _max > 0 and count >= _max:
				return
			count += 1
			var t := String(combo["type"])
			var plan := BuildingPlanner.plan(t, int(seed))
			var model := BuildingBuilder.build(plan)
			var arrays := BuildingView.make_arrays(model)
			var node := BuildingView.create_node(model, arrays)
			var meshes: Array = []
			_harvest(node, Transform3D.IDENTITY, meshes)
			node.free()
			var nm: String = String(BuildingCatalog.ARCHETYPES[t]["name"])
			_add("batiment_%s_g%d" % [t, seed], "%s — graine %d" % [nm, seed], String(g.get("categorie", "Bâtiments")), "genere", "batiment",
					_with_seed(combo, int(seed)), meshes, "res://scripts/world/building/building_planner.gd", {})

# --- habitations du joueur (DwellingGenerator → ConstructionView)
func _family_dwelling() -> void:
	var g := _gen_cfg("habitation")
	if g.is_empty() or not bool(g.get("actif", true)):
		return
	for s in ["dwelling_generator", "construction_view", "construction", "construction_ops", "house_pad"]:
		_registered_scripts["res://scripts/build/%s.gd" % s] = "habitation"
	var fe: Array = g.get("emprise_m", [9.0, 8.0])
	var fit := Vector2(float(fe[0]), float(fe[1]))
	var count := 0
	for combo in _combos(g.get("axes", {}), {"variante": Array(DwellingGenerator.VARIANTS)}):
		for seed in g.get("graines", [1]):
			if _max > 0 and count >= _max:
				return
			count += 1
			var v := String(combo["variante"])
			var res := DwellingGenerator.generate(v, int(seed), fit)
			if not bool(res.get("ok", false)):
				_skipped.append({"nom": "Habitation %s graine %d" % [v, seed], "type": "variante", "raison": "; ".join(res.get("reasons", [])), "comment": "Agrandir « emprise_m » dans tools/galerie/config.json."})
				continue
			var node := ConstructionView.create(res["model"], {"collide": false})
			var meshes: Array = []
			_harvest(node, Transform3D.IDENTITY, meshes)
			node.free()
			_add("habitation_%s_g%d" % [v, seed], "%s — graine %d" % [DwellingGenerator.variant_name(v), seed], String(g.get("categorie", "Habitations")), "genere", "habitation",
					_with_seed(combo, int(seed)), meshes, "res://scripts/build/dwelling_generator.gd", {"emprise_m": [fit.x, fit.y]})

# --- bateaux (ShipGenerator → ShipView)
func _family_ship() -> void:
	var g := _gen_cfg("bateau")
	if g.is_empty() or not bool(g.get("actif", true)):
		return
	_registered_scripts["res://scripts/world/ship/ship_generator.gd"] = "bateau"
	_registered_scripts["res://scripts/world/ship/ship_view.gd"] = "bateau"
	var count := 0
	for seed in g.get("graines", [1]):
		if _max > 0 and count >= _max:
			return
		count += 1
		var ship := ShipGenerator.build(int(seed))
		var parts := ShipView.parts(ship)
		_add("bateau_g%d" % seed, "Bateau volant — graine %d" % seed, String(g.get("categorie", "Port et navires")), "genere", "bateau",
				{"graine": int(seed)}, _parts_meshes(parts), "res://scripts/world/ship/ship_generator.gd", {})

# --- modèles du Lot 1 (VoxelModelLibrary)
func _family_lot1() -> void:
	_registered_scripts["res://scripts/objects/voxel_model_library.gd"] = "lot1"
	_registered_scripts["res://scripts/objects/voxel_model_builder.gd"] = "lot1"
	for key in VoxelModelLibrary.KEYS:
		var model := VoxelModelLibrary.get_model(key)
		var mesh := VoxelMesher.build(model["volume"], model["grid"])
		var meshes: Array = []
		if mesh != null:
			meshes.append({"mesh": mesh, "xf": Transform3D.IDENTITY, "nom": key, "kind": "props"})
		_add("lot1_" + key, String(model["name"]), "Modèles du Lot 1", "precuit", "", {}, meshes, "res://scripts/objects/voxel_model_library.gd", {})

# --- constructions d'exemple (assets/maisons/*.eclats-maison.json)
func _family_examples() -> void:
	for f in DirAccess.get_files_at(MAISONS):
		if not f.ends_with(".eclats-maison.json"):
			continue
		var r := Construction.load_file(MAISONS + "/" + f)
		if not bool(r.get("ok", false)):
			_skipped.append({"nom": f, "type": "construction", "raison": String(r.get("error", "illisible")), "comment": "Rouvrir le fichier dans l'atelier de construction et l'enregistrer de nouveau."})
			continue
		var node := ConstructionView.create(r["construction"], {"collide": false})
		var meshes: Array = []
		_harvest(node, Transform3D.IDENTITY, meshes)
		node.free()
		var base := f.replace(".eclats-maison.json", "")
		_add("exemple_" + base, "Construction d'exemple — " + String(r["construction"].name), "Constructions d'exemple", "exemple", "", {}, meshes, MAISONS + "/" + f, {})

# --- modèles ajoutés à la main : tools/galerie/manuels/<nom>.json + .glb à côté
func _family_manual() -> void:
	for f in DirAccess.get_files_at(MANUELS):
		if not f.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(MANUELS + "/" + f))
		if typeof(d) != TYPE_DICTIONARY or not d.has("glb"):
			_skipped.append({"nom": f, "type": "manuel", "raison": "Descripteur invalide (clé « glb » manquante).", "comment": "Voir docs/GALERIE_3D.md, section « Ajouter un modèle »."})
			continue
		var src := MANUELS + "/" + String(d["glb"])
		if not FileAccess.file_exists(src):
			_skipped.append({"nom": f, "type": "manuel", "raison": "Fichier glb introuvable : %s" % d["glb"], "comment": "Placer le .glb à côté du descripteur."})
			continue
		var id := "manuel_" + f.get_basename()
		var dest := _out + "/modeles/" + id + ".glb"
		var bytes := FileAccess.get_file_as_bytes(src)
		var fa := FileAccess.open(_abs(dest), FileAccess.WRITE)
		fa.store_buffer(bytes)
		fa.close()
		var e := {"id": id, "nom": String(d.get("nom", id)), "categorie": String(d.get("categorie", "Divers")), "famille": "manuel", "generateur": "", "params": {}, "graine": null,
				"dimensions_m": d.get("dimensions_m", null), "triangles": d.get("triangles", null), "fichier": "modeles/%s.glb" % id, "taille_ko": int(bytes.size() / 1024), "taille_brute_ko": int(bytes.size() / 1024), "source": "tools/galerie/manuels/" + f, "details": {}}
		_entries.append(e)

# --- personnage animé : hiérarchie de pivots + AnimationPlayer exportés tels quels (clips idle / walk / run / jump)
func _family_character() -> void:
	_registered_scripts["res://scripts/game/explorer_model.gd"] = "personnage"
	var model := ExplorerModel.new()
	model.build_now()
	var tris := 0
	var box := AABB()
	var first := true
	var stack: Array = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.mesh = _clean_mesh(mi.mesh, "props")
			tris += _tri_count(mi.mesh)
	# dimensions au repos
	for n in model.parts:
		var pv: Node3D = model.parts[n]
		for c in pv.get_children():
			if c is MeshInstance3D:
				var xf := Transform3D.IDENTITY
				var node: Node3D = c
				while node != model:
					xf = node.transform * xf
					node = node.get_parent()
				var bb: AABB = xf * (c as MeshInstance3D).mesh.get_aabb()
				box = bb if first else box.merge(bb)
				first = false
	var id := "personnage_explorateur"
	var path := _abs(_out + "/modeles/" + id + ".glb")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var ok := doc.append_from_scene(model, state) == OK and doc.write_to_filesystem(state, path) == OK
	var clips: Array = []
	for c in ExplorerModel.CLIPS:
		clips.append({"id": c, "nom": ExplorerModel.CLIPS[c][0], "duree_s": ExplorerModel.CLIPS[c][1]})
	model.free()
	if not ok:
		_skipped.append({"nom": "Explorateur", "type": "personnage", "raison": "Échec de l'export glTF.", "comment": "Voir le journal de l'exporteur."})
		return
	var raw := FileAccess.get_file_as_bytes(path)
	var gz := raw.compress(FileAccess.COMPRESSION_GZIP)
	var fz := FileAccess.open(path + ".gz", FileAccess.WRITE)
	fz.store_buffer(gz)
	fz.close()
	DirAccess.remove_absolute(path)
	_entries.append({"id": id, "nom": "Explorateur (personnage jouable)", "categorie": "Personnages", "famille": "personnage", "generateur": "", "params": {}, "graine": null,
			"dimensions_m": [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)], "triangles": tris, "fichier": "modeles/%s.glb.gz" % id,
			"taille_ko": gz.size() / 1024, "taille_brute_ko": raw.size() / 1024, "source": "scripts/game/explorer_model.gd",
			"details": {"hauteur_jeu_m": snappedf(PlayerConfig.height, 0.01), "pivots": 17}, "animations": clips})
	print("  %-44s %7d tri  %5d Ko  (%d animations)" % [id, tris, gz.size() / 1024, clips.size()])

# ------------------------------------------------------------------ détection des non exportés

func _detect_unexported() -> void:
	# 1) éléments déclarés non exportables dans la configuration
	var declared: Dictionary = _cfg.get("non_exportes", {})
	for path in declared:
		_skipped.append({"nom": String(path).get_file(), "type": "générateur", "raison": String(declared[path]), "comment": "Pas de vue d'objet possible ; à ajouter seulement en écrivant un adaptateur dans tools/galerie/galerie_export.gd (voir docs/GALERIE_3D.md)."})
	# 2) cartes d'îles (config/islands/*.json) : cartes complètes, pas des objets
	for f in DirAccess.get_files_at("res://config/islands"):
		if f.ends_with(".json"):
			var sz := FileAccess.get_file_as_bytes("res://config/islands/" + f).size() / 1024
			_skipped.append({"nom": "Île « %s » (config/islands/%s)" % [f.get_basename(), f], "type": "carte",
					"raison": "Carte complète (%d Ko de plan : relief, chemins, bâtiments, végétation), pas un objet. Ses éléments sont exportés un à un." % sz,
					"comment": "Visible dans le jeu (nouvelle partie) ; chaque bâtiment, arbre et objet qu'elle utilise figure dans la galerie."})
	# 3) scripts « générateur / constructeur / planificateur » non reconnus : signalés automatiquement
	var all := _scan_scripts("res://scripts")
	var known := _registered_scripts.duplicate()
	for p in declared:
		known[p] = "declare"
	for p in all:
		if known.has(p):
			continue
		var base := String(p).get_file()
		if base.find("generator") >= 0 or base.find("planner") >= 0 or base.find("builder") >= 0:
			if _is_within_registered_dir(p):
				continue
			_skipped.append({"nom": base, "type": "détecté", "raison": "Générateur détecté, sans adaptateur d'export.", "comment": "Ajouter une famille dans tools/galerie/galerie_export.gd et une entrée dans tools/galerie/config.json."})

func _is_within_registered_dir(p: String) -> bool:
	# les scripts de pièces d'un bâtiment enregistré (ex. roof_builder) ne sont pas des générateurs à part
	return String(p).begins_with("res://scripts/assets/") or String(p).begins_with("res://scripts/world/building/") \
			or String(p).begins_with("res://scripts/build/") or String(p).begins_with("res://scripts/camera/") or String(p).begins_with("res://scripts/rendering/")

func _scan_scripts(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scan_scripts(dir + "/" + d))
	return out

# ------------------------------------------------------------------ conversion et écriture

func _asset_meshes(a: VoxelAsset) -> Array:
	var parts: Array = []
	for p in a.parts:
		parts.append({"name": p["name"], "volume": p["volume"], "origin": p["offset"], "grid": p["grid"], "material": p["material"]})
	return _parts_meshes(parts)

## parts : {name, volume, origin, grid, material} → meshes [{mesh, xf, nom, kind}]
func _parts_meshes(parts: Array) -> Array:
	var out: Array = []
	for p in parts:
		var arrays := VoxelMesher.build_arrays(p["volume"], p["grid"], Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
		var mesh := VoxelMesher.arrays_to_mesh(arrays, VoxelMesher.Style.DETAIL)
		if mesh == null:
			continue
		out.append({"mesh": mesh, "xf": Transform3D(Basis.IDENTITY, p["origin"]), "nom": String(p["name"]), "kind": String(p.get("material", "props"))})
	return out

## Récupère les maillages de plus haut niveau de détail (visibility_range_begin = 0) d'une scène.
func _harvest(node: Node, xf: Transform3D, out: Array) -> void:
	for c in node.get_children():
		if c is Node3D:
			var t: Transform3D = xf * (c as Node3D).transform
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				if mi.mesh != null and mi.visibility_range_begin <= 0.001 and not mi.name.to_lower().contains("_lod"):
					var kind := "props"
					var m := mi.mesh.surface_get_material(0) if mi.mesh.get_surface_count() > 0 else null
					if m != null and m.resource_path.find("cloth") >= 0:
						kind = "cloth"
					elif m != null and m.resource_path.find("crystal") >= 0:
						kind = "crystal"
					out.append({"mesh": mi.mesh, "xf": t, "nom": String(mi.name), "kind": kind})
			_harvest(c, t, out)

func _material_for(kind: String, original: Material) -> Material:
	if original is StandardMaterial3D:
		return original
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		m.resource_name = kind
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_BACK
		_mats[kind] = m
	return _mats[kind]

func _clean_mesh(mesh: Mesh, kind: String) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		for i in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arr[i] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, _material_for(kind, mesh.surface_get_material(s)))
	return out

func _tri_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n

func _add(id: String, nom: String, categorie: String, famille: String, generateur: String, params: Dictionary, meshes: Array, source: String, details: Dictionary) -> void:
	if meshes.is_empty():
		_skipped.append({"nom": nom, "type": "modèle", "raison": "Aucun maillage produit (volume vide).", "comment": "Vérifier le générateur avec ses paramètres."})
		return
	var root := Node3D.new()
	root.name = id
	var tris := 0
	var box := AABB()
	var first := true
	for e in meshes:
		var mesh := _clean_mesh(e["mesh"], String(e["kind"]))
		var mi := MeshInstance3D.new()
		mi.name = String(e["nom"])
		mi.mesh = mesh
		mi.transform = e["xf"]
		root.add_child(mi)
		tris += _tri_count(mesh)
		var bb: AABB = (e["xf"] as Transform3D) * mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var rel := "modeles/%s.glb" % id
	var path := _abs(_out + "/" + rel)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var ok := doc.append_from_scene(root, state) == OK and doc.write_to_filesystem(state, path) == OK
	root.free()
	if not ok:
		_skipped.append({"nom": nom, "type": "modèle", "raison": "Échec de l'export glTF.", "comment": "Voir le journal de l'exporteur."})
		return
	# compression gzip (le navigateur la décompresse) : ~15 fois plus léger à servir
	var raw := FileAccess.get_file_as_bytes(path)
	var gz := raw.compress(FileAccess.COMPRESSION_GZIP)
	var fz := FileAccess.open(path + ".gz", FileAccess.WRITE)
	fz.store_buffer(gz)
	fz.close()
	DirAccess.remove_absolute(path)
	rel += ".gz"
	var size_kb: int = gz.size() / 1024
	_entries.append({"id": id, "nom": nom, "categorie": categorie, "famille": famille, "generateur": generateur, "params": params,
			"graine": params.get("graine", null), "dimensions_m": [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)],
			"triangles": tris, "fichier": rel, "taille_ko": size_kb, "taille_brute_ko": raw.size() / 1024, "source": source.replace("res://", ""), "details": details})
	print("  %-44s %7d tri  %5d Ko" % [id, tris, size_kb])

func _write_catalog() -> void:
	_entries.sort_custom(func(a, b): return [a["categorie"], a["famille"], a["id"]] < [b["categorie"], b["famille"], b["id"]])
	var gens: Array = []
	for k in (_cfg.get("generateurs", {}) as Dictionary):
		var g: Dictionary = _cfg["generateurs"][k]
		gens.append({"id": k, "nom": g.get("nom", k), "categorie": g.get("categorie", ""), "graines": g.get("graines", []), "axes": g.get("axes", {}), "actif": g.get("actif", true)})
	var cats := {}
	for e in _entries:
		cats[e["categorie"]] = int(cats.get(e["categorie"], 0)) + 1
	var cat := {
		"version": 1,
		"commit": OS.get_environment("GITHUB_SHA").substr(0, 7),
		"moteur": Engine.get_version_info()["string"],
		"nombre": _entries.size(),
		"categories": cats,
		"generateurs": gens,
		"modeles": _entries,
		"non_exportes": _skipped,
		"limites": [
			"Couleurs, rugosité, métal et émission du jeu ; les micro-textures de pixels de 2 cm du shader ne sont pas reproduites.",
			"Lumières, animations (tissus, cristaux) et collisions ne sont pas exportées.",
			"Niveau de détail le plus fin uniquement."],
	}
	var f := FileAccess.open(_abs(_out + "/catalogue.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(cat, "\t", false))
	f.close()
