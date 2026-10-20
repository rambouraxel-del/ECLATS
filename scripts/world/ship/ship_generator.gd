@tool
class_name ShipGenerator
extends RefCounted
## Bateau volant PARAMÉTRIQUE (graine → coque, château arrière, mâts, vergues, voiles, haubans) :
##   - coque : demi-largeur et fond calculés par section (étrave effilée relevée, tableau arrière plat,
##     livet qui remonte aux extrémités), bordés alternés ; pont en planches, bastingage, château arrière
##     accessible (échelle), gaillard avant, bout-dehors ; deux bras latéraux portent des cristaux de
##     sustentation sous la coque (c'est eux qui expliquent que le bateau vole) ;
##   - mâts : plantés dans la coque (une seule masse de bois connexe, vérifiée par composantes) ;
##   - voiles : panneaux SÉPARÉS de 2 cm, chacun sous sa vergue, bombés vers l'avant, à distance les uns
##     des autres ; aucune voile ne traverse un mât, un autre panneau ni un hauban (contrôlé voxel par voxel) ;
##   - haubans : cordages de 2 cm, d'un point d'attache à un autre, jamais à travers une voile.
## Repère local : origine au milieu du pont, y = niveau du pont, +z = étrave, x = travers.
## Paramétrique et réutilisable : `build(seed)` ne dépend d'aucune île ; l'amarrage est calculé à part.

const C := 0.1
const P := 0.02

static func build(seed: int, scale_len := 1.0) -> Dictionary:
	var pal := VoxelPalette.get_default()
	var rng := WorldRng.stream(seed, "ship")
	var L_m := rng.randf_range(9.0, 11.5) * scale_len        # longueur de coque
	var B_m := rng.randf_range(2.9, 3.5)                    # largeur maître-bau
	var D_m := rng.randf_range(1.5, 1.9)                    # creux de la coque
	var castle_m := rng.randf_range(0.95, 1.2)              # hauteur du château arrière
	var castle_len := rng.randf_range(0.26, 0.32)           # fraction de la longueur
	var mast_h := [rng.randf_range(6.2, 7.2), rng.randf_range(4.8, 5.6)]
	var mast_t := [rng.randf_range(0.36, 0.41), rng.randf_range(0.64, 0.69)]     # position le long de la coque (0 arrière → 1 étrave)
	var NL := int(L_m / C)
	var NB := int(B_m / C) + 6
	var top_y := int((maxf(mast_h[0], mast_h[1]) + 0.9) / C)
	var NY := int(D_m / C) + top_y + 12                    # sous le pont + mâts
	var Y0 := int(D_m / C) + 8                              # cellule du niveau du pont
	var Z0 := NL / 2 + 4
	var X0 := NB / 2 + 12
	# volume bois : coque + château + mâts + vergues + bout-dehors, une seule masse connexe
	var vol := VoxelVolume.new(Vector3i(NB + 40, NY, NL + 40))
	var origin := Vector3(-float(X0) * C, -float(Y0) * C, -float(Z0) * C)
	var ids := {
		"a": pal.id("wood_aged"), "b": pal.id("wood_aged_dark"), "c": pal.id("wood_pale_old"), "deck": pal.id("floor_planks"),
		"iron": pal.id("iron_rust"), "dark": pal.id("iron_dark"), "cry": pal.id("crystal_cyan"), "cry2": pal.id("crystal_ice"), "lamp": pal.id("lantern_glow"),
		"rope": pal.id("rope"), "brass": pal.id("brass"),
	}
	var put := func(x: int, y: int, z: int, m: int) -> void:
		vol.set_voxel(x + X0, y + Y0, z + Z0, m)
	var Lc := NL
	var half_len := float(Lc) * 0.5
	# --- coque, section par section (z de -half_len à +half_len, +z = étrave) ---
	var hb_of := func(t: float) -> float:
		# demi-largeur normalisée (0 → 1) selon la position t (0 arrière, 1 étrave)
		if t < 0.34:
			return lerpf(0.80, 1.0, smoothstep(0.0, 1.0, t / 0.34))
		var u := (t - 0.34) / 0.66
		return pow(maxf(1.0 - pow(u, 1.7), 0.0), 0.65)
	var sheer := func(t: float) -> float:
		# hauteur du livet (m, au-dessus du pont de milieu) : remonte à l'étrave et un peu à l'arrière
		return 0.55 * pow(t, 3.0) + 0.16 * pow(1.0 - t, 2.0)
	var rise := func(t: float) -> float:
		# remontée du fond (m) aux extrémités
		return 0.9 * smoothstep(0.55, 1.0, t) + 0.3 * (1.0 - smoothstep(0.0, 0.25, t))
	var strake_keys: Array[int] = [ids["a"], ids["b"], ids["a"], ids["c"], ids["a"], ids["b"]]
	for iz in range(-int(half_len), int(half_len)):
		var t := (float(iz) + half_len) / float(Lc)
		var hb: float = float(hb_of.call(t)) * B_m * 0.5
		if hb < 0.05:
			continue
		var top_m: float = float(sheer.call(t))
		var bot_rise: float = float(rise.call(t))
		var hcells := int(ceil(hb / C))
		for ix in range(-hcells - 1, hcells + 2):
			var ax := absf((float(ix) + 0.5) * C)
			if ax > hb:
				continue
			var frac := ax / maxf(hb, 0.05)
			# fond : profondeur D au centre, remonte vers les bords ; relevé vers les extrémités
			var y0 := -D_m * (1.0 - pow(frac, 2.3)) + bot_rise * (1.0 - pow(frac, 2.0) * 0.5)
			var y1 := top_m
			for iy in range(int(floor(y0 / C)), int(ceil(y1 / C))):
				var ym := (float(iy) + 0.5) * C
				if ym < y0 - 0.001 or ym > y1:
					continue
				var strake := int(floor((ym + D_m) / (C * 2.0)))
				var m: int = strake_keys[posmod(strake, strake_keys.size())]
				if ym > y1 - 0.12:
					m = ids["b"]                 # liston / plat-bord plus sombre
				put.call(ix, iy, iz, m)
			# pont (planches posées en travers)
			var iy_deck := int(floor(top_m / C)) - 1
			put.call(ix, iy_deck, iz, ids["deck"] if (iz + 1000) % 3 != 0 else ids["a"])
	# --- bastingage (bordage) : parois basses sur les bords, ouverture au milieu côté ponton (les deux côtés) ---
	var gap0 := int(Lc * 0.40) - int(half_len)
	var gap1 := gap0 + int(1.5 / C)
	for iz in range(-int(half_len), int(half_len)):
		var t := (float(iz) + half_len) / float(Lc)
		var hb: float = float(hb_of.call(t)) * B_m * 0.5
		if hb < 0.3:
			continue
		var top_m: float = float(sheer.call(t))
		var hc := int(round(hb / C)) - 1
		var base := int(floor(top_m / C))
		for side in [-1, 1]:
			var x: int = hc * side
			var opening: bool = iz >= gap0 and iz <= gap1
			# poteaux tous les 1,2 m, lisse haute, lisse basse ajourée
			if (iz % 12) == 0:
				for iy in range(base, base + 9):
					put.call(x, iy, iz, ids["b"])
			if not opening:
				put.call(x, base + 8, iz, ids["a"])
				put.call(x, base + 4, iz, ids["a"])
				if iz % 3 != 0:
					put.call(x, base + 5, iz, ids["a"])
	# --- château arrière : pont surélevé, murs, porte, fanal ---
	var cz0 := -int(half_len)
	var cz1 := cz0 + int(castle_len * float(Lc))
	var ch := int(castle_m / C)
	for iz in range(cz0, cz1):
		var t := (float(iz) + half_len) / float(Lc)
		var hb: float = float(hb_of.call(t)) * B_m * 0.5
		var hc := int(round(hb / C)) - 1
		var base := int(floor(float(sheer.call(t)) / C))
		for ix in range(-hc, hc + 1):
			# plancher du château (2 cellules) + murs latéraux pleins
			put.call(ix, base + ch - 1, iz, ids["deck"])
			put.call(ix, base + ch - 2, iz, ids["a"])
		for iy in range(base, base + ch):
			put.call(-hc, iy, iz, ids["b"] if iy % 3 else ids["a"])
			put.call(hc, iy, iz, ids["b"] if iy % 3 else ids["a"])
	# mur avant du château avec porte et échelle
	for ix in range(-int(B_m * 0.5 / C) + 3, int(B_m * 0.5 / C) - 2):
		for iy in range(int(float(sheer.call(0.3)) / C), int(float(sheer.call(0.3)) / C) + ch):
			var door: bool = absi(ix) <= 4 and iy < int(float(sheer.call(0.3)) / C) + 20
			if not door:
				put.call(ix, iy, cz1, ids["b"] if iy % 2 else ids["a"])
	# échelle : deux montants et barreaux contre le mur avant du château (côté bâbord)
	var lx := int(B_m * 0.5 / C) - 6
	for iy in range(int(float(sheer.call(0.3)) / C), int(float(sheer.call(0.3)) / C) + ch):
		put.call(lx, iy, cz1 + 1, ids["b"])
		put.call(lx + 5, iy, cz1 + 1, ids["b"])
		if iy % 3 == 0:
			for k in range(1, 5):
				put.call(lx + k, iy, cz1 + 1, ids["a"])
	# garde-corps du château (poupe et côtés)
	var cbase := int(floor(float(sheer.call(0.1)) / C)) + ch
	for iz in range(cz0, cz1):
		var t := (float(iz) + half_len) / float(Lc)
		var hc := int(round(float(hb_of.call(t)) * B_m * 0.5 / C)) - 1
		for side in [-1, 1]:
			put.call(hc * side, cbase + 5, iz, ids["a"])
			if iz % 12 == 0:
				for iy in range(cbase, cbase + 6):
					put.call(hc * side, iy, iz, ids["b"])
	var hc_stern := int(round(float(hb_of.call(0.02)) * B_m * 0.5 / C)) - 1
	for ix in range(-hc_stern, hc_stern + 1):
		put.call(ix, cbase + 5, cz0, ids["a"])
		if ix % 6 == 0:
			for iy in range(cbase, cbase + 6):
				put.call(ix, iy, cz0, ids["b"])
	# gaillard avant
	var fz0 := int(half_len) - int(Lc * 0.16)
	var fz1 := int(half_len) - int(Lc * 0.05)
	for iz in range(fz0, fz1):
		var t := (float(iz) + half_len) / float(Lc)
		var hc := int(round(float(hb_of.call(t)) * B_m * 0.5 / C)) - 1
		var base := int(floor(float(sheer.call(t)) / C))
		for ix in range(-hc, hc + 1):
			put.call(ix, base + 6, iz, ids["deck"])
			put.call(ix, base + 5, iz, ids["a"])
		for iy in range(base, base + 5):
			put.call(-hc, iy, iz, ids["b"])
			put.call(hc, iy, iz, ids["b"])
	# --- mâts, vergues ---
	var masts: Array[Dictionary] = []
	for k in 2:
		var mz := int((mast_t[k] - 0.5) * float(Lc))
		var t := float(mast_t[k])
		var deck_m: float = float(sheer.call(t))
		var base_c := Vector3(0.0, deck_m - 0.7, float(mz) * C)
		var top_c := Vector3(0.0, deck_m + mast_h[k], float(mz) * C)
		VoxelShapes.capsule(vol, origin, C, base_c, top_c, 0.17, 0.09, ids["a"])
		# jonc de pied de mât
		VoxelShapes.capsule(vol, origin, C, Vector3(0, deck_m, float(mz) * C), Vector3(0, deck_m + 0.45, float(mz) * C), 0.27, 0.2, ids["b"])
		masts.append({"base": base_c, "top": top_c, "z": float(mz) * C, "deck": deck_m, "h": mast_h[k]})
	# vergues : 2 par mât (haute et basse), perpendiculaires à l'axe du bateau
	var yards: Array[Dictionary] = []
	for k in 2:
		var m: Dictionary = masts[k]
		var specs: Array = [[0.46, 0.64], [0.78, 0.46]] if k == 0 else [[0.46, 0.55], [0.76, 0.38]]   # [hauteur relative, demi-longueur relative]
		for sp in specs:
			var yy: float = float(m["deck"]) + float(m["h"]) * float(sp[0]) + 0.5
			var hl: float = B_m * float(sp[1]) * 1.05
			var a := Vector3(-hl, yy, float(m["z"]))
			var b := Vector3(hl, yy, float(m["z"]))
			VoxelShapes.capsule(vol, origin, C, a, b, 0.07, 0.07, ids["b"])
			VoxelShapes.capsule(vol, origin, C, Vector3(0, yy, float(m["z"]) - 0.0), Vector3(0, yy, float(m["z"]) + 0.0), 0.12, 0.12, ids["iron"])
			yards.append({"mast": k, "y": yy, "half": hl, "z": float(m["z"])})
	# bout-dehors (bowsprit) : poutre effilée qui part du gaillard vers l'avant et monte
	var bow_z := half_len * C
	var bs_a := Vector3(0.0, float(sheer.call(0.95)) + 0.55, bow_z - 1.6)
	var bs_b := Vector3(0.0, float(sheer.call(1.0)) + 1.5, bow_z + 1.7)
	VoxelShapes.capsule(vol, origin, C, bs_a, bs_b, 0.13, 0.06, ids["a"])
	# bras de sustentation (outriggers) : arche de chaque côté qui porte un cristal sous la coque
	var lev: Array[Dictionary] = []
	for side in [-1.0, 1.0]:
		var hb_mid := B_m * 0.5
		var arm_a := Vector3(side * hb_mid * 0.78, -0.35, -0.5)
		var arm_b := Vector3(side * (hb_mid + 0.95), -1.0, -0.5)
		VoxelShapes.capsule(vol, origin, C, arm_a, arm_b, 0.1, 0.07, ids["dark"])
		var arm2_a := Vector3(side * hb_mid * 0.78, -0.35, 1.1)
		var arm2_b := Vector3(side * (hb_mid + 0.95), -1.0, 1.1)
		VoxelShapes.capsule(vol, origin, C, arm2_a, arm2_b, 0.1, 0.07, ids["dark"])
		VoxelShapes.capsule(vol, origin, C, arm_b, arm2_b, 0.08, 0.08, ids["dark"])
		var cc := (arm_b + arm2_b) * 0.5 + Vector3(0, -0.12, 0)
		VoxelShapes.capsule(vol, origin, C, cc + Vector3(0, 0.1, -0.35), cc + Vector3(0, -0.95, 0.0), 0.2, 0.05, ids["cry"])
		VoxelShapes.capsule(vol, origin, C, cc + Vector3(0, 0.1, 0.35), cc + Vector3(0, -0.8, 0.1), 0.17, 0.05, ids["cry2"])
		lev.append({"pos": cc + Vector3(0, -0.4, 0)})
	# cristal de quille et fanal arrière
	VoxelShapes.capsule(vol, origin, C, Vector3(0, -D_m + 0.15, 0.0), Vector3(0, -D_m - 0.7, 0.0), 0.2, 0.05, ids["cry"])
	VoxelShapes.capsule(vol, origin, C, Vector3(0, float(cbase) * C, float(cz0 + 3) * C), Vector3(0, float(cbase + 16) * C, float(cz0 + 3) * C), 0.05, 0.05, ids["dark"])
	VoxelShapes.sphere(vol, origin, C, Vector3(0, float(cbase + 17) * C, float(cz0 + 3) * C), 0.2, ids["lamp"])
	# nettoyage : tout ce qui n'est pas relié à la coque est retiré (rien ne flotte)
	var removed := VoxelShapes.keep_anchored(vol, Y0 - int(D_m / C) + 2)
	var comps := VoxelShapes.components(vol).size()
	# --- voiles : panneaux de 2 cm, un par vergue, bombés vers l'avant ---
	var sails: Array[Dictionary] = []
	var cloth_keys: Array[int] = [pal.id("cloth_ochre"), pal.id("cloth_faded_blue"), pal.id("cloth_brown")]
	var base_key: int = cloth_keys[rng.randi() % cloth_keys.size()]
	var patch_key: int = cloth_keys[(rng.randi() % (cloth_keys.size() - 1) + 1 + cloth_keys.find(base_key)) % cloth_keys.size()]
	var by_mast := {0: [], 1: []}
	for yd in yards:
		by_mast[yd["mast"]].append(yd)
	for k in 2:
		var list: Array = by_mast[k]
		list.sort_custom(func(a, b): return a["y"] < b["y"])
		for j in list.size():
			var yd: Dictionary = list[j]
			var y_top: float = float(yd["y"]) - 0.11
			var y_bot: float = float(masts[k]["deck"]) + 1.3 if j == 0 else float(list[0]["y"]) + 0.28
			if j == 1:
				y_bot = float(list[0]["y"]) + 0.3
			var width := float(yd["half"]) * 2.0 * 0.92
			var height := y_top - y_bot
			if height < 0.8:
				continue
			sails.append(_sail(yd, width, height, y_top, k, seed + 31 * j + 7 * k, base_key, patch_key))
	# --- haubans : de la tête du grand mât au petit mât, du petit mât au bout-dehors, galhaubans ---
	var ropes: Array[Dictionary] = []
	var m0: Dictionary = masts[0]
	var m1: Dictionary = masts[1]
	var top0: Vector3 = (m0["top"] as Vector3)
	var top1: Vector3 = (m1["top"] as Vector3)
	ropes.append({"a": top0 + Vector3(0, -0.1, 0.1), "b": top1 + Vector3(0, -0.45, -0.1), "sag": 2.0})     # étai
	ropes.append({"a": top1 + Vector3(0, -0.1, 0.1), "b": bs_b + Vector3(0, 0.0, 0.0), "sag": 2.0})
	ropes.append({"a": top0 + Vector3(0, -0.15, -0.1), "b": Vector3(0, float(cbase + 5) * C, float(cz0) * C + 0.1), "sag": 3.0})   # galhauban arrière
	for k in 2:
		var m: Dictionary = masts[k]
		var h_att := float(m["deck"]) + float(m["h"]) * 0.62
		for side in [-1.0, 1.0]:
			for j in 3:
				# les haubans restent en arrière du plan des voiles (qui sont devant le mât) : ils penchent vers la poupe
				var dz := -0.25 - 0.4 * float(j)
				var hb_here := B_m * 0.5 * float(hb_of.call(mast_t[k]))
				ropes.append({"a": Vector3(side * 0.12, h_att - 0.2 * float(j), float(m["z"]) - 0.15), "b": Vector3(side * (hb_here - 0.12), float(sheer.call(mast_t[k])) + 0.75, float(m["z"]) + dz), "sag": 1.5})
	var lights: Array[Dictionary] = []
	lights.append({"pos": Vector3(0, float(cbase + 17) * C + 0.1, float(cz0 + 3) * C + 0.25), "color": Color("ffb35c"), "energy": 1.0, "range": 7.0, "interior": false})
	for lv in lev:
		lights.append({"pos": lv["pos"], "color": Color("69e3ff"), "energy": 0.8, "range": 5.0, "interior": false})
	var hull_aabb := AABB(Vector3(-B_m * 0.5 - 1.2, -D_m - 0.9, -L_m * 0.5 - 0.3), Vector3(B_m + 2.4, D_m + 0.9 + castle_m + 1.0 + mast_h[0], L_m + 3.0))
	var res := {"seed": seed, "L": L_m, "B": B_m, "D": D_m, "volume": vol, "origin": origin, "grid": C, "sails": sails, "ropes": ropes, "masts": masts, "yards": yards,
		"lights": lights, "aabb": hull_aabb, "deck_y": 0.0, "bow_z": bow_z, "bowsprit": [bs_a, bs_b], "removed_floating": removed, "wood_components": comps,
		"cleat_x": B_m * 0.5, "ids": ids}
	return res

## Panneau de voile : tissu de 2 cm (une cellule d'épaisseur + bombement), couleurs par pièces cousues,
## ourlets, ralingues et petites déchirures. Repère de l'objet : origine au milieu de la tête, y vers le bas.
static func _sail(yd: Dictionary, width: float, height: float, y_top: float, mast_idx: int, seed: int, key_a: int, key_b: int) -> Dictionary:
	var pal := VoxelPalette.get_default()
	var nx := int(width / P)
	var ny := int(height / P)
	var belly := 0.16 * minf(height / 2.2, 1.0)
	var nz := int(belly / P) + 6
	var vol := VoxelVolume.new(Vector3i(nx, ny, nz))
	var seam_id := pal.id("cloth_brown")
	var panel_w := int(0.55 / P)
	var rngs := WorldRng.stream(seed, "sail")
	var panel_tint: Array[int] = []
	for i in (nx / panel_w + 2):
		panel_tint.append(key_a if rngs.randf() > 0.2 else key_b)
	for iy in ny:
		var v := float(ny - 1 - iy) / float(ny - 1)          # 0 = tête (sous la vergue), 1 = point d'écoute
		for ix in nx:
			var u := float(ix) / float(nx - 1)
			# bombement vers l'avant (+z) : maximal au milieu, nul sur la vergue
			var zb := belly * sin(PI * u) * sin(PI * 0.5 * (1.0 - v) + 0.25) * 0.85 * (1.0 - v * 0.15)
			var iz := int(zb / P)
			# les angles du bas sont échancrés (voile classique en trapèze)
			var inset := int(0.12 * v * float(nx) * 0.5)
			if ix < inset or ix >= nx - inset:
				continue
			var m: int = panel_tint[ix / panel_w]
			if ix % panel_w == 0 or iy % int(0.9 / P) == 0:
				m = seam_id                                      # coutures
			if iy < 3 or iy >= ny - 3 or ix < inset + 2 or ix >= nx - inset - 2:
				m = seam_id                                        # ralingue
			if VoxelGrid.hash01(ix / 3, iy / 3, 1, seed) < 0.015 and v > 0.2 and iy > 8:
				continue                                           # déchirure
			vol.set_voxel(ix, iy, mini(iz, nz - 1), m)
			vol.set_voxel(ix, iy, mini(iz + 1, nz - 1), m)
	# repère : x centré, y vers le bas depuis y_top, z à 0.35 m devant le mât
	var ox: float = -width * 0.5
	var oy: float = y_top - height
	var oz: float = float(yd["z"]) + 0.34
	return {"volume": vol, "origin": Vector3(ox, oy, oz), "grid": P, "mast": mast_idx, "yard_y": yd["y"], "width": width, "height": height, "belly": belly}

# ------------------------------------------------------------------ cordages (2 cm)

static func rope_kit(a: Vector3, b: Vector3, sag_cells: float) -> Dictionary:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3(0.05, 0.1, 0.05)
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3(0.05, 0.05, 0.05)
	var size := Vector3i(int(ceil((hi.x - lo.x) / P)) + 1, int(ceil((hi.y - lo.y) / P)) + 1, int(ceil((hi.z - lo.z) / P)) + 1)
	var vol := VoxelVolume.new(size)
	var rope_id := VoxelPalette.get_default().id("rope")
	var steps := int(maxf(maxf(absf(b.x - a.x), absf(b.y - a.y)), absf(b.z - a.z)) / P) * 2 + 2
	var pts: Array[Vector3i] = []
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var q := (a.lerp(b, t) - lo) / P
		var sag := sin(t * PI) * sag_cells
		var cell := Vector3i(int(q.x), int(maxf(q.y - sag, 0.0)), int(q.z))
		vol.set_voxel(cell.x, cell.y, cell.z, rope_id)
		pts.append(cell)
	return {"volume": vol, "origin": lo, "grid": P, "a": a, "b": b}

# ------------------------------------------------------------------ contrôles de conception

## Défauts de conception d'un bateau (liste vide = valide) : coque connexe, voiles disjointes entre elles,
## sans contact avec les mâts, vergues ou haubans ; chaque voile est portée par une vergue.
static func check(ship: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if int(ship["wood_components"]) != 1:
		issues.append("bois en %d morceaux" % int(ship["wood_components"]))
	var wood: VoxelVolume = ship["volume"]
	var wo: Vector3 = ship["origin"]
	var sails: Array = ship["sails"]
	# voiles ↔ voiles
	for i in sails.size():
		for j in range(i + 1, sails.size()):
			if _sails_overlap(sails[i], sails[j]):
				issues.append("voiles %d et %d se croisent" % [i, j])
	# voiles ↔ bois (mâts, vergues, coque) : on teste chaque cellule de voile (1 sur 3) dans le volume de bois
	for i in sails.size():
		var s: Dictionary = sails[i]
		var sv: VoxelVolume = s["volume"]
		var so: Vector3 = s["origin"]
		var hits := 0
		var first_hit := Vector3.ZERO
		for iy in range(0, sv.size.y, 3):
			for ix in range(0, sv.size.x, 3):
				for iz in sv.size.z:
					if sv.get_voxel(ix, iy, iz) == 0:
						continue
					var p := so + (Vector3(ix, iy, iz) + Vector3(0.5, 0.5, 0.5)) * P
					var c := Vector3i(floori((p.x - wo.x) / C), floori((p.y - wo.y) / C), floori((p.z - wo.z) / C))
					if wood.get_voxel(c.x, c.y, c.z) != 0:
						hits += 1
						if hits == 1:
							first_hit = p
		if hits > 0:
			issues.append("voile %d traverse du bois (%d points, ex. en %s ; mât %d, vergue y=%.2f)" % [i, hits, first_hit, int(s["mast"]), float(s["yard_y"])])
	# haubans ↔ voiles
	for r in ship["ropes"]:
		var a: Vector3 = r["a"]
		var b: Vector3 = r["b"]
		for k in 80:
			var t := float(k) / 79.0
			var p := a.lerp(b, t) - Vector3(0, sin(t * PI) * float(r["sag"]) * P, 0)
			for s in sails:
				var sv: VoxelVolume = s["volume"]
				var so: Vector3 = s["origin"]
				var c := Vector3i(floori((p.x - so.x) / P), floori((p.y - so.y) / P), floori((p.z - so.z) / P))
				if sv.get_voxel(c.x, c.y, c.z) != 0:
					issues.append("hauban à travers une voile")
					break
	# voiles portées : au-dessus de la tête de voile (1 cm) il y a une vergue
	for s in sails:
		var so: Vector3 = s["origin"]
		var sv: VoxelVolume = s["volume"]
		var mid := so + Vector3(float(sv.size.x) * 0.5 * P, float(sv.size.y) * P + 0.16, 0.0)
		var ok := false
		for dz in range(-4, 5):
			var c := Vector3i(floori((mid.x - wo.x) / C), floori((mid.y - wo.y) / C), floori((mid.z + float(dz) * C - wo.z) / C))
			if wood.get_voxel(c.x, c.y, c.z) != 0:
				ok = true
				break
		if not ok:
			issues.append("voile sans vergue")
	return issues

static func _sails_overlap(a: Dictionary, b: Dictionary) -> bool:
	var av: VoxelVolume = a["volume"]
	var bv: VoxelVolume = b["volume"]
	var ao: Vector3 = a["origin"]
	var bo: Vector3 = b["origin"]
	var aa := AABB(ao, Vector3(av.size) * P)
	var bb := AABB(bo, Vector3(bv.size) * P)
	if not aa.intersects(bb):
		return false
	for iy in range(0, av.size.y, 2):
		for ix in range(0, av.size.x, 2):
			for iz in av.size.z:
				if av.get_voxel(ix, iy, iz) == 0:
					continue
				var p := ao + (Vector3(ix, iy, iz) + Vector3(0.5, 0.5, 0.5)) * P
				var c := Vector3i(floori((p.x - bo.x) / P), floori((p.y - bo.y) / P), floori((p.z - bo.z) / P))
				if bv.get_voxel(c.x, c.y, c.z) != 0:
					return true
	return false
