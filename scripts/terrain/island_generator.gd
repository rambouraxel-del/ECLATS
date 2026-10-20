@tool
class_name IslandGenerator
extends RefCounted
## Génère une île flottante voxel de façon déterministe à partir d'une graine (seed).
## Même seed + mêmes réglages = exactement les mêmes voxels sur toutes les machines.
## Préparé pour devenir plus tard un VoxelGeneratorScript (Voxel Tools) : la logique
## « colonne par colonne » ne dépend d'aucun nœud de scène.

## Profondeur (en voxels) de la couche superficielle modifiable. 6 × 0,20 m = 1,20 m.
const SURFACE_DEPTH := 6

var seed := 1234
var radius_m := 15.0          # ≈ 30 m de diamètre
var base_height_m := 1.6      # hauteur moyenne du plateau
var hill_height_m := 3.2      # amplitude des collines
var terrace_step_m := 0.6     # hauteur des paliers (relief constructible)
var underside_depth_m := 14.0 # profondeur de la sous-face au centre
var crystal_rate := 0.01      # proportion d'éclats sur la sous-face
var root_rate := 0.006        # densité des racines pendantes sous l'île

## Longueur maximale des racines pendantes (voxels).
const ROOT_MAX := 14

const V := VoxelGrid.VOXEL_SIZE

func generate() -> IslandData:
	var pal := VoxelPalette.get_default()
	var m := {
		"stone": pal.id("stone"), "stone_dark": pal.id("stone_dark"), "dirt": pal.id("dirt"),
		"grass": pal.id("grass"), "grass_lush": pal.id("grass_lush"), "grass_dry": pal.id("grass_dry"),
		"moss": pal.id("moss"), "crystal": pal.id("crystal"), "root": pal.id("root"),
	}
	var n_rim := _noise(0, 0.9)
	var n_height := _noise(1, 0.045)
	var n_hill := _noise(2, 0.02)
	var n_under := _noise(3, 0.08)
	var n_spike := _noise(4, 0.35)
	var n_mat := _noise(5, 0.07)
	var n_rock := _noise(6, 0.12)

	var r_vox := int(ceil(radius_m * 1.25 / V))
	var sxz := r_vox * 2 + 3
	var center := float(sxz) * 0.5
	var col_count := sxz * sxz
	var tops := PackedFloat32Array()
	var bottoms := PackedFloat32Array()
	tops.resize(col_count)
	bottoms.resize(col_count)
	var radial := PackedFloat32Array()
	radial.resize(col_count)

	# Passe 1 : forme de chaque colonne (haut et bas, en mètres).
	var min_y := 0
	var max_y := 0
	for z in sxz:
		for x in sxz:
			var i := x + z * sxz
			var dx := (x + 0.5 - center) * V
			var dz := (z + 0.5 - center) * V
			var dist := sqrt(dx * dx + dz * dz)
			var ang := atan2(dz, dx)
			var edge := radius_m * (1.0 + 0.16 * n_rim.get_noise_2d(cos(ang) * 2.0, sin(ang) * 2.0)
					+ 0.05 * n_rim.get_noise_2d(cos(ang) * 7.0 + 30.0, sin(ang) * 7.0))
			var r := dist / edge
			radial[i] = r
			if r >= 1.0:
				tops[i] = NAN
				continue
			var h := base_height_m + hill_height_m * (0.55 * (n_height.get_noise_2d(dx, dz) * 0.5 + 0.5)
					+ 0.75 * maxf(n_hill.get_noise_2d(dx, dz), 0.0))
			h -= smoothstep(0.78, 1.0, r) * 1.0
			h = _terrace(h, terrace_step_m)
			var depth := 1.4 + underside_depth_m * pow(1.0 - r, 1.25)
			depth += n_under.get_noise_2d(dx, dz) * 2.2 * (1.0 - r * 0.6)
			var spike := n_spike.get_noise_2d(dx, dz)
			if spike > 0.25:
				depth += (spike - 0.25) * 16.0 * (1.0 - r * 0.7)
			var top_v := roundi(h / V)
			var bottom_v := top_v - maxi(roundi(depth / V), 5)
			tops[i] = top_v
			bottoms[i] = bottom_v
			min_y = mini(min_y, bottom_v)
			max_y = maxi(max_y, top_v)

	var size := Vector3i(sxz, max_y - min_y + 3 + ROOT_MAX, sxz)
	var y_off := -min_y + 1 + ROOT_MAX
	var data := IslandData.new()
	data.seed = seed
	data.core = VoxelVolume.new(size)
	data.surface = VoxelVolume.new(size)
	data.solid = PackedByteArray()
	data.solid.resize(data.core.data.size())
	data.origin_cell = Vector3i(-sxz / 2, -y_off, -sxz / 2)
	data.top = PackedInt32Array()
	data.top.resize(col_count)
	data.top.fill(-1)
	data.top_material = PackedByteArray()
	data.top_material.resize(col_count)

	# Passe 2 : remplissage des matières, colonne par colonne.
	for z in sxz:
		for x in sxz:
			var i := x + z * sxz
			if is_nan(tops[i]):
				continue
			var top_v := int(tops[i])
			var bottom_v := int(bottoms[i])
			var dx := (x + 0.5 - center) * V
			var dz := (z + 0.5 - center) * V
			var r := radial[i]
			# Pente : différence de hauteur avec les voisins (sol rocheux si trop raide).
			var slope := 0
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var nz: int = z + o.y
				var nt := tops[nx + nz * sxz] if nx >= 0 and nz >= 0 and nx < sxz and nz < sxz else NAN
				slope = maxi(slope, top_v - int(nt) if not is_nan(nt) else 99)
			var mat_noise := n_mat.get_noise_2d(dx, dz)
			var rocky := n_rock.get_noise_2d(dx, dz) > 0.38 and r < 0.88
			var top_mat: int
			if rocky:
				top_mat = m["stone"]
			elif slope >= 2 and slope < 99:
				top_mat = m["dirt"]
			elif mat_noise > 0.28:
				top_mat = m["grass_lush"]
			elif mat_noise < -0.32:
				top_mat = m["grass_dry"]
			else:
				top_mat = m["grass"]
			var dirt_depth := 2 + int(VoxelGrid.hash01(x, 0, z, seed) * 3.0)
			for y in range(bottom_v, top_v + 1):
				var vy := y + y_off
				var d := top_v - y   # profondeur sous le sol, en voxels
				var mat: int
				if d == 0:
					mat = top_mat
				elif d <= dirt_depth and not rocky:
					mat = m["dirt"]
					# Mousse sur le haut des falaises extérieures.
					if r > 0.9 and d <= 2 and VoxelGrid.hash01(x, y, z, seed + 3) < 0.45:
						mat = m["moss"]
				else:
					# Roche en strates : bandes horizontales ondulées, plus sombres en profondeur.
					var depth_m := -float(y) * V
					var band := fposmod(depth_m / 1.6 + n_rock.get_noise_2d(dx * 3.0, dz * 3.0) * 0.6, 1.0)
					var dark := band > 0.62 or VoxelGrid.hash01(x, y, z, seed + 11) < clampf(depth_m / 14.0, 0.0, 0.5)
					mat = m["stone_dark"] if dark else m["stone"]
					if y - bottom_v <= 1 and VoxelGrid.hash01(x, y, z, seed + 17) < crystal_rate:
						mat = m["crystal"]
				data.solid[data.core.index_of(x, vy, z)] = 1
				if d < SURFACE_DEPTH:
					data.surface.set_voxel(x, vy, z, mat)
				else:
					data.core.set_voxel(x, vy, z, mat)
			data.top[i] = top_v + y_off
			data.top_material[i] = top_mat
			# Racines pendantes sous la bordure (cœur : non destructibles).
			if r > 0.45 and r < 0.97 and VoxelGrid.hash01(x, 1, z, seed + 23) < root_rate:
				var length := 3 + int(VoxelGrid.hash01(x, 2, z, seed + 29) * (ROOT_MAX - 3))
				var root_id: int = m["root"]
				var rx := x
				var rz := z
				for k in length:
					var vy := bottom_v + y_off - 1 - k
					if vy < 0:
						break
					# Les racines serpentent légèrement en descendant.
					if k > 1 and VoxelGrid.hash01(x, k, z, seed + 31) < 0.25:
						rx = clampi(rx + (1 if VoxelGrid.hash01(x, k, z, seed + 37) < 0.5 else -1), 0, sxz - 1)
					data.core.set_voxel(rx, vy, rz, root_id)
					data.solid[data.core.index_of(rx, vy, rz)] = 1
	return data

func _noise(offset: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed * 31 + offset
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = 3
	return n

## Paliers adoucis : zones plates constructibles reliées par de courtes pentes.
static func _terrace(h: float, step: float) -> float:
	var t := h / step
	var f := t - floorf(t)
	return (floorf(t) + smoothstep(0.3, 0.7, f)) * step
