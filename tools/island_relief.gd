extends SceneTree
## Relief d'une île dessinée (Lot 5) → images PNG (ombrage + zones), pour le plan :
##   godot --headless -s tools/island_relief.gd -- res://config/islands/ile_ouverture.json sortie.png [--complet]
## --complet : construit toute l'île (chemins, bâtiments, objets) avant l'export, sinon le relief seul.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var map := IslandMap.load_map(args[0])
	var t0 := Time.get_ticks_msec()
	var field: TerrainField
	if args.has("--complet"):
		var w := AuthoredIslandBuilder.build(map, {"no_models": true, "no_voxels": true})
		field = w.field
	else:
		field = AuthoredTerrain.build_field(map)
	print("relief : %d ms, %d colonnes de côté, %d colonnes de sol" % [Time.get_ticks_msec() - t0, field.n, field.land_count()])
	var n := field.n
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var lo := 1 << 20
	var hi := -(1 << 20)
	for i in n * n:
		if field.top[i] != TerrainField.NO_GROUND:
			lo = mini(lo, field.top[i])
			hi = maxi(hi, field.top[i])
	var pal := VoxelPalette.get_default()
	for cz in n:
		for cx in n:
			var i := cx + cz * n
			var tp := field.top[i]
			if tp == TerrainField.NO_GROUND:
				img.set_pixel(cx, cz, Color(0.62, 0.74, 0.86))
				continue
			var tw := field.top_at(cx - 1, cz - 1)
			var shade := 1.0
			if tw != TerrainField.NO_GROUND:
				shade = clampf(1.0 + float(tw - tp) * 0.10, 0.55, 1.35)
			var base := pal.colors_linear[int(field.material[i])].linear_to_srgb()
			var hcol := Color(0.2, 0.2, 0.2).lerp(Color(1, 1, 1), float(tp - lo) / maxf(float(hi - lo), 1.0))
			var c := base.lerp(hcol, 0.35) * shade
			img.set_pixel(cx, cz, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1)))
	img.save_png(args[1])
	var meta := {"n": n, "origin": [field.origin.x, field.origin.y], "cell_m": 0.2, "lo_m": float(lo + 1) * 0.2, "hi_m": float(hi + 1) * 0.2}
	var f := FileAccess.open(args[1].replace(".png", ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	print("écrit ", args[1])
	quit()
