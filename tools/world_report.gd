extends SceneTree
## Rapport de diagnostic de génération : construit une île par graine, la valide (WorldValidator) et affiche
## un résumé lisible ; écrit aussi un JSON complet.
##   godot --headless -s tools/world_report.gd -- <profil> <graine,graine,...> [sortie.json] [--rapide] [--determinisme]
##   --rapide : saute la validation voxel de l'intérieur des bâtiments ; --determinisme : reconstruit la 1re graine et compare.
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage : -s tools/world_report.gd -- <profil> <graines> [sortie.json] [--rapide] [--determinisme]")
		quit(2)
		return
	var profile := args[0]
	var seeds: Array[int] = []
	for s in args[1].split(","):
		seeds.append(int(s))
	var out_path := ""
	for a in args.slice(2):
		if not a.begins_with("--"):
			out_path = a
	var fast := args.has("--rapide")
	var determinism := args.has("--determinisme")
	var report := {"profile": profile, "islands": []}
	var total_errors := 0
	print("== Rapport de génération : profil « %s », %d graine(s) ==" % [profile, seeds.size()])
	for seed in seeds:
		var t0 := Time.get_ticks_msec()
		var w := WorldBuilder.build(profile, seed)
		var t1 := Time.get_ticks_msec()
		var r := WorldValidator.validate(w, {"buildings": not fast})
		var t2 := Time.get_ticks_msec()
		var tris := 0
		var entry := {
			"seed": seed, "timings_ms": w.timings, "generation_ms": t1 - t0, "validation_ms": t2 - t1,
			"buildings": w.buildings.size(), "trees": w.trees.size(), "rocks": w.rocks.size(), "props": w.props.size(),
			"plants": int(w.stats.get("plants", 0)), "port": not w.port.is_empty(), "plaza_m": snappedf(float(w.settlement.plaza.get("radius", 0.0)), 0.1),
			"placement": w.placement.stats, "site_reasons": w.stats.get("site_reasons"), "failures": w.failures,
			"summary": r["summary"], "checks": r["checks"], "issues": r["issues"], "signature": WorldValidator.signature(w),
		}
		print("-- graine %d : %d bâtiments · %d arbres · %d rochers · %d objets · %d plantes · port %s · génération %d ms · validation %d ms" % [
			seed, entry["buildings"], entry["trees"], entry["rocks"], entry["props"], entry["plants"], "oui" if entry["port"] else "non", t1 - t0, t2 - t1])
		print("   erreurs %d · avertissements %d · échecs de génération %d" % [r["summary"]["errors"], r["summary"]["warnings"], w.failures.size()])
		for i in r["issues"]:
			print("   [%s] %s : %s" % [i["severity"], i["check"], i["message"]])
		for f in w.failures:
			print("   (génération) %s : %s" % [f["what"], f["reason"]])
		total_errors += int(r["summary"]["errors"])
		report["islands"].append(entry)
		if determinism and seed == seeds[0]:
			var w2 := WorldBuilder.build(profile, seed)
			var same: bool = WorldValidator.signature(w2) == entry["signature"]
			entry["deterministic"] = same
			print("   déterminisme (reconstruction) : %s" % ("OK" if same else "DIFFÉRENT"))
			if not same:
				total_errors += 1
	report["total_errors"] = total_errors
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "\t"))
	print("== Total : %d erreur(s) ==" % total_errors)
	quit(1 if total_errors > 0 else 0)
