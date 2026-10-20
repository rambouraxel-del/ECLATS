@tool
class_name TerrainVoxelizer
extends RefCounted
## TerrainField → IslandData (cœur fixe + surface modifiable), à la grille de 20 cm.
## Règles de matières (aucun semis aléatoire par voxel) :
##   dessus      : matière de la colonne (herbe, roche, pavés, sentier…)
##   sous le dessus : terre sur 2-4 cellules (moins sur les pentes), puis roche en STRATES
##   flancs aménagés : maçonnerie de soutènement (les parties exposées d'une plateforme ou d'un
##                     chemin surélevé sont en pierre, jamais en terre nue)
##   sous-face   : strates ondulées, plus sombres en profondeur ; cristaux à la pointe des cônes
## Le cœur est strictement défini par field.core_top (relief naturel − SURFACE_DEPTH).

const V := VoxelGrid.VOXEL_SIZE

static func build(field: TerrainField) -> IslandData:
	var pal := VoxelPalette.get_default()
	var m := {
		"dirt": pal.id("dirt"), "dirt_dry": pal.id("dirt_dry"), "dirt_fertile": pal.id("dirt_fertile"),
		"stone": pal.id("stone"), "stone_dark": pal.id("stone_dark"),
		"warm": pal.id("rock_warm"), "grey": pal.id("rock_grey"), "masonry": pal.id("stone_ashlar_dark"),
		"steps": pal.id("stone_carved"), "crystal": pal.id("crystal_blue"), "crystal_b": pal.id("crystal"),
		"root": pal.id("root"), "moss": pal.id("moss"),
	}
	var n := field.n
	var min_y := 1 << 20
	var max_y := -(1 << 20)
	var roots: Array = field.landmarks.get("roots", [])
	for i in n * n:
		if field.top[i] == TerrainField.NO_GROUND:
			continue
		min_y = mini(min_y, field.bottom[i])
		max_y = maxi(max_y, field.top[i])
	var root_max := 14
	var y_off := -(min_y - 1 - root_max)
	var size := Vector3i(n, max_y - min_y + 3 + root_max, n)
	var data := IslandData.new()
	data.seed = field.seed
	data.core = VoxelVolume.new(size)
	data.surface = VoxelVolume.new(size)
	data.solid = PackedByteArray()
	data.solid.resize(data.core.data.size())
	data.origin_cell = Vector3i(field.origin.x, -y_off, field.origin.y)
	data.top = PackedInt32Array()
	data.top.resize(n * n)
	data.top.fill(-1)
	data.top_material = PackedByteArray()
	data.top_material.resize(n * n)
	var core_data := data.core.data
	var surf_data := data.surface.data
	var solid := data.solid
	var stride_z := n
	var stride_y := n * n
	var warp := WorldRng.noise(field.seed, "strata", 0.035, 2)
	var band_cache := {}
	for cz in n:
		for cx in n:
			var ci := cx + cz * n
			var top := field.top[ci]
			if top == TerrainField.NO_GROUND:
				continue
			var bot := field.bottom[ci]
			var core_top := field.core_top[ci]
			var zone := field.zone[ci]
			var built := zone == TerrainField.Zone.PLAZA or zone == TerrainField.Zone.PLOT or zone == TerrainField.Zone.RETAIN \
					or zone == TerrainField.Zone.PORT or zone == TerrainField.Zone.ROAD or zone == TerrainField.Zone.STAIR
			# Voisine la plus basse (la partie au-dessus est exposée sur un flanc).
			var nmin := top
			var void_side := false
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var u := field.top_at(cx + o.x, cz + o.y)
				if u == TerrainField.NO_GROUND:
					void_side = true
					nmin = bot
				else:
					nmin = mini(nmin, u)
			var slope := field.step_at(cx, cz)
			var dirt_depth := 3 if slope <= 1 else (2 if slope == 2 else 1)
			var soil: int = m["dirt"]
			if zone == TerrainField.Zone.GARDEN:
				soil = m["dirt_fertile"]
				dirt_depth = 4
			var top_mat := int(field.material[ci])
			var is_rock_top: bool = top_mat == m["warm"] or top_mat == m["grey"]
			if is_rock_top:
				dirt_depth = 0
			var wv := warp.get_noise_2d(float(cx), float(cz)) * 2.2
			for y in range(bot, top + 1):
				var d := top - y
				var mat: int
				if d == 0:
					mat = top_mat
				elif y > nmin and built:
					mat = m["steps"] if (zone == TerrainField.Zone.ROAD or zone == TerrainField.Zone.STAIR) else m["masonry"]
				elif d <= dirt_depth and not void_side:
					mat = soil
				elif d <= dirt_depth and y > nmin:
					mat = soil
				else:
					mat = _strata(field.seed, y, wv, top - bot, m, band_cache, top)
				var vy := y + y_off
				var idx := cx + cz * stride_z + vy * stride_y
				solid[idx] = 1
				if y <= core_top:
					core_data[idx] = mat
				else:
					surf_data[idx] = mat
			data.top[ci] = top + y_off
			data.top_material[ci] = top_mat
	# Cristaux à la pointe des cônes de la sous-face (position structurée, pas de semis).
	for s in field.landmarks.get("spikes", []):
		var col := field.col_of_m(s.c.x, s.c.y)
		var ci := col.x + col.y * n
		if not field.has_ground(col.x, col.y):
			continue
		var tip := field.bottom[ci]
		if int(s.len) >= 4.0 and WorldRng.sub_seed(field.seed, "crystal_%d_%d" % [col.x, col.y]) % 3 != 0:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if absi(dx) + absi(dz) > 1:
						continue
					for dy in range(-2, 1):
						var x := col.x + dx
						var z := col.y + dz
						var vy := tip + dy + y_off
						if x < 0 or z < 0 or x >= n or z >= n or vy < 0:
							continue
						var idx := x + z * stride_z + vy * stride_y
						if solid[idx] != 0 and dy >= -1:
							core_data[idx] = m["crystal"] if (dx + dz + dy) % 2 == 0 else m["crystal_b"]
	# Racines pendantes sous le bord (cœur : non destructibles).
	for rt in roots:
		var col := field.col_of_m(rt.c.x, rt.c.y)
		if not field.has_ground(col.x, col.y):
			continue
		var ci := col.x + col.y * n
		var x := col.x
		for k in int(rt.len):
			var y := field.bottom[ci] - 1 - k
			var vy := y + y_off
			if vy < 0:
				break
			if k > 1 and (k * 7 + col.x) % 5 == 0:
				x = clampi(x + (1 if (k + col.y) % 2 == 0 else -1), 0, n - 1)
			var idx := x + col.y * stride_z + vy * stride_y
			if solid[idx] == 0:
				core_data[idx] = m["root"]
				solid[idx] = 1
	return data

## Matière de strate à l'altitude y : bandes d'épaisseur variable (0,6-1,6 m), ondulées par une
## fonction lente, plus sombres avec la profondeur sous le dessus.
static func _strata(seed: int, y: int, warp_v: float, thickness: int, m: Dictionary, cache: Dictionary, top: int) -> int:
	var band := floori((float(y) * V + warp_v) / 1.1)
	var depth_m := float(top - y) * V
	var key := band * 8 + clampi(int(depth_m / 4.0), 0, 6)
	if cache.has(key):
		return cache[key]
	var h := VoxelGrid.hash01(band, 7, 3, seed)
	var mat: int
	var deep := clampf(depth_m / 14.0, 0.0, 1.0)
	if h < 0.42 - deep * 0.2:
		mat = m["warm"]
	elif h < 0.78 - deep * 0.2:
		mat = m["grey"]
	elif h < 0.9:
		mat = m["stone"]
	else:
		mat = m["stone_dark"]
	if deep > 0.7 and h < 0.7:
		mat = m["stone_dark"]
	cache[key] = mat
	return mat
