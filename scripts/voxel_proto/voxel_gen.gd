extends VoxelGeneratorScript
## Prototype C — générateur de blocs pour Voxel Tools (module du moteur ; ce script ne se charge que dans un moteur qui l'embarque).
## Entrées : le SQUELETTE du plan (PlanTerrain.build méthode « S » : zones plates, chemins creusés, matières) ; le détail naturel
## (crêtes, vallées, flancs) est généré ICI par ZN_FastNoiseLite, le bruit natif de Voxel Tools, pondéré par `detail_w`
## (nul sur les zones plates et près des chemins) : les lieux et les chemins du plan restent donc identiques.
## Une colonne = un voxel de 20 cm ; unité de bloc = 1 voxel (le nœud VoxelTerrain est mis à l'échelle 0,2).

const V := 0.2
const NO := -1000000
const SOIL := 2            # épaisseur de terre sous la surface (voxels)
const CRUST := 10          # épaisseur de la croûte (voxels) sous la surface

var n := 0
var ox := 0                # origine du terrain (colonnes) : voxel x = ox + colonne
var oz := 0
var top := PackedInt32Array()
var mat := PackedInt32Array()
var dw := PackedFloat32Array()
var da := PackedFloat32Array()
var amp := 2.8
var ridge: Object
var body: Object
var valley: Object
var warp: Object
var fine: Object
var id_dirt := 3
var id_stone := 1
var id_warm := 0
var id_grey := 0
var calls := 0

func setup(field: TerrainField, b: PlanTerrain.Build, seed: int, pal: VoxelPalette) -> void:
	n = field.n
	ox = field.origin.x
	oz = field.origin.y
	top = field.top
	mat = PackedInt32Array()
	mat.resize(n * n)
	for i in n * n:
		mat[i] = field.material[i]
	dw = b.detail_w
	da = b.detail_a
	id_dirt = pal.id("dirt")
	id_stone = pal.id("stone")
	id_warm = pal.id("rock_warm")
	id_grey = pal.id("rock_grey")
	ridge = _noise(seed, 1, 0.055, 4, 3)
	body = _noise(seed, 2, 0.034, 4, 1)
	valley = _noise(seed, 3, 0.028, 2, 0)
	warp = _noise(seed, 4, 0.045, 2, 0)
	fine = _noise(seed, 5, 0.19, 2, 0)

## ZN_FastNoiseLite : bruit natif de Voxel Tools (fractal 0 aucun · 1 FBM · 3 ridged).
func _noise(seed: int, k: int, freq_m: float, octaves: int, fractal: int) -> Object:
	var z: Object = ClassDB.instantiate("ZN_FastNoiseLite")
	z.set("seed", seed * 31 + k * 7919)
	z.set("period", 1.0 / freq_m)
	z.set("noise_type", 1)          # simplex lissé
	z.set("fractal_type", fractal)
	z.set("fractal_octaves", octaves)
	if fractal == 3:
		z.set("fractal_gain", 0.55)
	return z

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE

## Hauteur (indice du voxel de surface) de la colonne de voxels (vx, vz), ou NO s'il n'y a pas de sol.
func height_at(vx: int, vz: int) -> int:
	var cx := vx - ox
	var cz := vz - oz
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return NO
	var i := cx + cz * n
	var t := top[i]
	if t == TerrainField.NO_GROUND:
		return NO
	var w := dw[i]
	if w <= 0.0:
		return t
	var x := (float(vx) + 0.5) * V
	var z := (float(vz) + 0.5) * V
	var wx: float = float(warp.call("get_noise_2d", x, z)) * 5.0
	var wz: float = float(warp.call("get_noise_2d", z + 37.0, x - 19.0)) * 5.0
	var px := x + wx
	var pz := z + wz
	var r: float = ridge.call("get_noise_2d", px, pz)
	var crest := maxf(r, -0.2) * 1.25
	var v: float = valley.call("get_noise_2d", px, pz)
	var incision := smoothstep(0.02, 0.45, -v) * 1.1
	var d: float = float(body.call("get_noise_2d", px, pz)) * 0.9 + crest * 0.8 - incision + float(fine.call("get_noise_2d", x, z)) * 0.25
	var hm := float(t + 1) * V + d * da[i] * w * amp
	return maxi(roundi(maxf(hm, 0.6) / V) - 1, t - 40)

func _generate_block(buf: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var sz := buf.get_size()
	var hs := PackedInt32Array()
	hs.resize((sz.x + 2) * (sz.z + 2))
	for z in sz.z + 2:
		for x in sz.x + 2:
			hs[x + z * (sz.x + 2)] = height_at(origin.x + x - 1, origin.z + z - 1)
	var oy := origin.y
	var y_hi := oy + sz.y - 1
	var ch := VoxelBuffer.CHANNEL_TYPE
	for z in sz.z:
		for x in sz.x:
			var k := (x + 1) + (z + 1) * (sz.x + 2)
			var h := hs[k]
			if h == NO:
				continue
			var y_lo := h - CRUST
			if y_hi < y_lo or oy > h:
				continue
			# matière de surface : roche sur les pentes fortes, sinon celle du squelette du plan
			var cx := origin.x + x - ox
			var cz := origin.z + z - oz
			var surf := id_stone
			if cx >= 0 and cz >= 0 and cx < n and cz < n:
				surf = mat[cx + cz * n]
			var step := maxi(maxi(absi(h - hs[k - 1]), absi(h - hs[k + 1])), maxi(absi(h - hs[k - (sz.x + 2)]), absi(h - hs[k + (sz.x + 2)])))
			if step >= 3:
				surf = id_warm if ((origin.x + x + origin.z + z) * 2654435761 >> 5) & 1 == 0 else id_grey
			var y0 := maxi(y_lo, oy)
			var y1 := mini(h, y_hi)
			# pierre sous la terre, terre, surface
			var s_top := h - 1 - SOIL
			if y0 <= s_top:
				buf.fill_area(id_stone, Vector3i(x, y0 - oy, z), Vector3i(x + 1, mini(s_top, y1) - oy + 1, z + 1), ch)
			var d0 := maxi(y0, h - SOIL)
			if d0 <= mini(h - 1, y1):
				buf.fill_area(id_dirt, Vector3i(x, d0 - oy, z), Vector3i(x + 1, mini(h - 1, y1) - oy + 1, z + 1), ch)
			if h >= oy and h <= y_hi:
				buf.set_voxel(surf, x, h - oy, z, ch)
