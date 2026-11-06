extends SceneTree
## Lot 11 — mesures de performance (mêmes conditions avant / après) :
##   godot --headless --fixed-fps 60 -s tools/lot11_mesures.gd -- rapport.json
## Pour chaque taille de plan : relief du plan, passage éditeur → 3D (relief + mise en place du terrain 3D), traits de
## pinceau (lissage, relief), annulation, retouche locale du terrain 3D (collisions + tuiles). Médiane de 3 répétitions.
## CPU uniquement (rendu « dummy » en headless) : pas de mesure GPU.

var report := {"machine": {}, "tailles": []}

func _t() -> int:
	return Time.get_ticks_usec()

func _med(a: Array) -> float:
	a.sort()
	return float(a[a.size() / 2])

func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://mesures.json"
	report["machine"] = {"os": OS.get_name(), "cpu": OS.get_processor_name(), "coeurs": OS.get_processor_count(),
		"rendu": RenderingServer.get_video_adapter_name() + " / " + str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "moteur": Engine.get_version_info()["string"]}
	for dims in [[56.0, 48.0], [120.0, 120.0]]:
		await _taille(dims[0], dims[1])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print(JSON.stringify(report, "\t"))
	quit()

func _taille(w: float, l: float) -> void:
	var r := {"plan_m": [w, l]}
	var plan := PlanGenerator.generate(7, w, l)
	var doc: MapDoc
	var ts: Array = []
	for k in 3:
		var t0 := _t()
		doc = MapDoc.from_plan(plan.copy())
		ts.append(_t() - t0)
	r["colonnes_par_cote"] = doc.field.n
	r["relief_du_plan_ms"] = _med(ts) / 1000.0
	# --- éditeur → 3D : ce que fait la scène 3D à l'ouverture (relief recalculé puis terrain 3D)
	var t_build: Array = []
	var t_setup: Array = []
	for k in 3:
		var t1 := _t()
		var b := PlanTerrain.build(doc.plan)
		PlanTerrain.apply_layers(b, doc.plan)
		t_build.append(_t() - t1)
		var lab := LabWorld.new()
		root.add_child(lab)
		await process_frame
		var t2 := _t()
		lab.setup_field(b.field, "plan", doc.plan.seed, doc.plan.start)
		t_setup.append(_t() - t2)
		if k == 2:
			r["_lab"] = lab
		else:
			root.remove_child(lab)
			lab.free()
	r["vue3d_relief_ms"] = _med(t_build) / 1000.0
	if doc.build.has_method("with_field"):
		var tre: Array = []
		for k in 3:
			var t1b := _t()
			var bb = doc.build.with_field(doc.field.duplicate_field())
			tre.append(_t() - t1b)
		r["vue3d_relief_reutilise_ms"] = _med(tre) / 1000.0
	r["vue3d_terrain_ms"] = _med(t_setup) / 1000.0
	# --- pinceaux sur le document
	var c := doc.field.center_m(doc.field.n / 2, doc.field.n / 2)
	for tool in ["adoucir", "monter"]:
		var tt: Array = []
		var td: Array = []
		var te: Array = []
		for k in 3:
			var t3 := _t()
			doc.stroke_begin("mesure", tool, c)
			var t4 := _t()
			for j in 30:
				doc.stroke_dab(tool, c + Vector2(float(j) * 0.3, 0.0), 2.5, 0.6)
			var t5 := _t()
			doc.stroke_end()
			var t6 := _t()
			tt.append(t4 - t3)
			td.append((t5 - t4) / 30)
			te.append(t6 - t5)
		r["%s_debut_ms" % tool] = _med(tt) / 1000.0
		r["%s_par_coup_ms" % tool] = _med(td) / 1000.0
		r["%s_fin_ms" % tool] = _med(te) / 1000.0
	var tu: Array = []
	for k in 3:
		var t7 := _t()
		doc.undo()
		tu.append(_t() - t7)
	r["annuler_ms"] = _med(tu) / 1000.0
	r["pile_annulation"] = doc.undo_stack.size()
	# --- retouche locale du terrain 3D
	var lab2: LabWorld = r["_lab"]
	r.erase("_lab")
	var tg: Array = []
	for k in 3:
		var t8 := _t()
		lab2.update_ground()
		tg.append(_t() - t8)
	r["collisions_update_ground_ms"] = _med(tg) / 1000.0
	var tg2: Array = []
	for k in 3:
		var t8b := _t()
		lab2.update_ground(Rect2i(lab2.field.n / 2 - 8, lab2.field.n / 2 - 8, 16, 16))
		tg2.append(_t() - t8b)
	r["collisions_update_ground_local_ms"] = _med(tg2) / 1000.0
	var tr: Array = []
	var mid := Vector2i(lab2.field.n / 2, lab2.field.n / 2)
	for k in 3:
		for dz in range(-6, 6):
			for dx in range(-6, 6):
				var i := (mid.x + dx) + (mid.y + dz) * lab2.field.n
				if lab2.field.top[i] != TerrainField.NO_GROUND:
					lab2.field.top[i] += 1
		var t9 := _t()
		await lab2.rebuild_rect(Rect2i(mid - Vector2i(6, 6), Vector2i(12, 12)))
		tr.append(_t() - t9)
	r["retouche_locale_3d_ms"] = _med(tr) / 1000.0
	# une tuile (80 colonnes) : voxelisation et maillage séparés (la reconstruction d'une retouche locale en refait 1 à 4)
	var tv: Array = []
	var tm: Array = []
	for k in 3:
		var job := {"rect": Rect2i(mid - Vector2i(40, 40), Vector2i(80, 80)), "out": []}
		lab2._bld._tile_job(job)
		tv.append(int(job["t_vox"]))
		tm.append(int(job["t_mesh"]))
		var hsh := 0
		for o in job["out"]:
			for a in o["arrays"]:
				hsh = hash([hsh, hash(a)])
		r["tuile_empreinte"] = hsh
	r["tuile_voxelisation_ms"] = _med(tv) / 1000.0
	r["tuile_maillage_ms"] = _med(tm) / 1000.0
	lab2.queue_free()
	report["tailles"].append(r)
