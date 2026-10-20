@tool
class_name VoxelMesher
extends RefCounted
## Transforme une VoxelVolume en ArrayMesh. Seules les faces en contact avec l'air sont
## générées (aucune face intérieure), avec occlusion ambiante par sommet.
##
## Deux styles de rendu :
## - STYLIZED (Lot 2, par défaut) : les faces coplanaires de même matière et même
##   occlusion sont FUSIONNÉES en grands rectangles (maillage glouton). Aucune variation
##   de couleur par cellule : les nuances viennent du shader voxel_stylized.gdshader,
##   calculées en continu dans l'espace monde (zones douces, transitions herbe/terre).
##   Canaux : COLOR.rgb = couleur linéaire, COLOR.a = occlusion, UV = (émission, rugosité),
##   UV2 = (style de la matière, aspect métal).
## - LEGACY (Lot 1) : une face par voxel, teinte variée cellule par cellule, liseré
##   des arêtes (voxel.gdshader). Conservé pour comparer l'ancien et le nouveau rendu.

## LEGACY   : Lot 1. STYLIZED : terrain (Lot 2). DETAIL : objets et bâtiments (Lot 3) =
## STYLIZED + données de quad (CUSTOM0/1) pour les motifs de matière (fibres du bois,
## joints, usure des arêtes, facettes des cristaux, plis des tissus).
##   CUSTOM0 = (u, v, largeur, hauteur) du quad en mètres (u, v = position dans le quad)
##   CUSTOM1 = (épaisseur de matière derrière la face en mètres, graine aléatoire du quad,
##              sens du grain : 0 le long de u, 1 le long de v, 2 bois de bout, 3 inconnu)
##   UV2.x   = style + usure * 0.98 (partie entière = style, partie fractionnaire = usure)
enum Style { LEGACY, STYLIZED, DETAIL }

# Faces : normale, axes u et v (u × v = normale), coin de base. Les tables sont
# recréées localement à chaque appel (les constantes partagées ne sont pas sûres entre threads).
static func _face_table() -> Array:
	return [
		[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0)],
		[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 0, 0)],
		[Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
		[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 0)],
		[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
		[Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 0)],
	]

## Paramètres d'un maillage.
## volume      : voxels à mailler.
## solid_mask  : masque d'occupation optionnel (même taille) qui cache aussi les faces
##               contre d'autres volumes (ex. cœur ↔ surface). Vide = le volume seul.
## region_min/max : sous-partie à mailler (bornes incluses) — sert au découpage en chunks.
## voxel_size  : taille d'un voxel en mètres (VoxelGrid.VOXEL_SIZE ou DETAIL_SIZE).
## world_cell_offset, color_seed : variation de teinte par cellule (style LEGACY seulement).
static func build(volume: VoxelVolume, voxel_size: float, region_min := Vector3i.ZERO,
		region_max := Vector3i(-1, -1, -1), solid_mask := PackedByteArray(),
		world_cell_offset := Vector3i.ZERO, color_seed := 0, style := Style.STYLIZED) -> ArrayMesh:
	return arrays_to_mesh(build_arrays(volume, voxel_size, region_min, region_max, solid_mask,
			world_cell_offset, color_seed, style), style)

## Crée l'ArrayMesh à partir des tableaux produits par build_arrays (null si vide).
static func arrays_to_mesh(arrays: Array, style := Style.STYLIZED) -> ArrayMesh:
	if arrays.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var flags := 0
	if arrays[Mesh.ARRAY_CUSTOM0] != null:
		flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		flags |= Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, VoxelMaterials.material_for(style))
	return mesh

## Calcule les tableaux de sommets. Fonction pure : peut tourner dans un thread.
static func build_arrays(volume: VoxelVolume, voxel_size: float, region_min := Vector3i.ZERO,
		region_max := Vector3i(-1, -1, -1), solid_mask := PackedByteArray(),
		world_cell_offset := Vector3i.ZERO, color_seed := 0, style := Style.STYLIZED) -> Array:
	if style == Style.LEGACY:
		return _build_arrays_legacy(volume, voxel_size, region_min, region_max, solid_mask,
				world_cell_offset, color_seed)
	return _build_arrays_greedy(volume, voxel_size, region_min, region_max, solid_mask, style == Style.DETAIL)

## Nombre de triangles d'un maillage (toutes surfaces).
static func triangle_count(mesh: Mesh) -> int:
	var n := 0
	if mesh == null:
		return 0
	for i in mesh.get_surface_count():
		n += mesh.surface_get_array_index_len(i) / 3
	return n

## Maillage glouton (style STYLIZED).
static func _build_arrays_greedy(volume: VoxelVolume, voxel_size: float, rmin: Vector3i,
		rmax: Vector3i, solid_mask: PackedByteArray, extra := false) -> Array:
	var palette := VoxelPalette.get_default()
	if rmax.x < 0:
		rmax = volume.size - Vector3i.ONE
	var sx := volume.size.x
	var sy := volume.size.y
	var sz := volume.size.z
	var stride_z := sx
	var stride_y := sx * sz
	var data := volume.data
	var aux := volume.aux if extra else PackedByteArray()
	var solid := data if solid_mask.is_empty() else solid_mask
	var rs := rmax - rmin + Vector3i.ONE
	# Index local dans la région : lx + lz * rs.x + ly * rs.x * rs.z (pas par axe x, y, z).
	var lstride := PackedInt32Array([1, rs.x * rs.z, rs.x])
	var cells := rs.x * rs.y * rs.z
	var maxdim := maxi(rs.x, maxi(rs.y, rs.z))
	var masks := PackedInt32Array()
	masks.resize(cells * 6)
	masks.fill(0)
	# Rectangle englobant des faces de chaque tranche : [a_min, a_max, b_min, b_max].
	var bounds := PackedInt32Array()
	bounds.resize(6 * maxdim * 4)
	for i in 6 * maxdim:
		bounds[i * 4] = 1 << 30
		bounds[i * 4 + 1] = -1
		bounds[i * 4 + 2] = 1 << 30
		bounds[i * 4 + 3] = -1
	var face_n: Array[Vector3i] = []
	var face_u: Array[Vector3i] = []
	var face_v: Array[Vector3i] = []
	var face_b: Array[Vector3i] = []
	var ax_n := PackedInt32Array()
	var ax_u := PackedInt32Array()
	var ax_v := PackedInt32Array()
	for f in _face_table():
		face_n.append(f[0])
		face_u.append(f[1])
		face_v.append(f[2])
		face_b.append(f[3])
		ax_n.append(_axis_of(f[0]))
		ax_u.append(_axis_of(f[1]))
		ax_v.append(_axis_of(f[2]))
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]

	# Passe 1 : faces visibles → clé (matière + occlusion des 4 coins) dans le masque de la tranche.
	for y in range(rmin.y, rmax.y + 1):
		for z in range(rmin.z, rmax.z + 1):
			var row := z * stride_z + y * stride_y
			for x in range(rmin.x, rmax.x + 1):
				var mat := data[row + x]
				if mat == 0:
					continue
				var lc := Vector3i(x - rmin.x, y - rmin.y, z - rmin.z)
				var li := lc.x + lc.z * rs.x + lc.y * rs.x * rs.z
				for fi in 6:
					var n := face_n[fi]
					var nx := x + n.x
					var ny := y + n.y
					var nz := z + n.z
					if nx >= 0 and ny >= 0 and nz >= 0 and nx < sx and ny < sy and nz < sz:
						if solid[nx + nz * stride_z + ny * stride_y] != 0:
							continue
					var u := face_u[fi]
					var v := face_v[fi]
					var key := mat
					for k in 4:
						var c := corners[k]
						var su := c.x * 2 - 1
						var sv := c.y * 2 - 1
						var s1 := _is_solid(solid, nx + u.x * su, ny + u.y * su, nz + u.z * su, sx, sy, sz)
						var s2 := _is_solid(solid, nx + v.x * sv, ny + v.y * sv, nz + v.z * sv, sx, sy, sz)
						var s3 := _is_solid(solid, nx + u.x * su + v.x * sv, ny + u.y * su + v.y * sv, nz + u.z * su + v.z * sv, sx, sy, sz)
						var level := 0 if (s1 and s2) else 3 - int(s1) - int(s2) - int(s3)
						key |= level << (8 + k * 2)
					if not aux.is_empty():
						key |= aux[row + x] << 16
					masks[fi * cells + li] = key
					var bi := (fi * maxdim + lc[ax_n[fi]]) * 4
					var a := lc[ax_u[fi]]
					var b := lc[ax_v[fi]]
					if a < bounds[bi]: bounds[bi] = a
					if a > bounds[bi + 1]: bounds[bi + 1] = a
					if b < bounds[bi + 2]: bounds[bi + 2] = b
					if b > bounds[bi + 3]: bounds[bi + 3] = b

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var ao_curve := PackedFloat32Array([0.56, 0.72, 0.87, 1.0])  # luminosité selon l'occlusion

	# Passe 2 : fusion gloutonne des faces identiques, tranche par tranche.
	for fi in 6:
		var na := ax_n[fi]
		var su_ := lstride[ax_u[fi]]
		var sv_ := lstride[ax_v[fi]]
		var sn := lstride[na]
		var off := fi * cells
		var uf := Vector3(face_u[fi])
		var vf := Vector3(face_v[fi])
		var nf := Vector3(face_n[fi])
		for s in rs[na]:
			var bi := (fi * maxdim + s) * 4
			var amax := bounds[bi + 1]
			if amax < 0:
				continue
			var amin := bounds[bi]
			var bmin := bounds[bi + 2]
			var bmax := bounds[bi + 3]
			for b in range(bmin, bmax + 1):
				var rowi := off + s * sn + b * sv_
				var a := amin
				while a <= amax:
					var li := rowi + a * su_
					var key := masks[li]
					if key == 0:
						a += 1
						continue
					var w := 1
					while a + w <= amax and masks[li + w * su_] == key:
						w += 1
					var h := 1
					var grow := true
					while grow and b + h <= bmax:
						var li2 := li + h * sv_
						for t in w:
							if masks[li2 + t * su_] != key:
								grow = false
								break
						if grow:
							h += 1
					for hh in h:
						for t in w:
							masks[li + hh * sv_ + t * su_] = 0
					# Émission du rectangle fusionné.
					var lc := Vector3i.ZERO
					lc[na] = s
					lc[ax_u[fi]] = a
					lc[ax_v[fi]] = b
					var origin := Vector3(rmin + lc + face_b[fi])
					var mat := key & 0xFF
					var base: Color = palette.colors_linear[mat]
					var uv := Vector2(palette.emission[mat], palette.roughness[mat])
					var uv2 := Vector2(float(palette.styles[mat]) + palette.wear[mat] * 0.98, palette.metallic[mat])
					var depth_m := 0.0
					var seed_q := 0.0
					var grain_code := 3.0
					if extra:
						var cell := rmin + lc
						var back := -face_n[fi]
						var dm := 1
						var cp := cell + back
						while dm < 48 and cp.x >= 0 and cp.y >= 0 and cp.z >= 0 and cp.x < sx and cp.y < sy and cp.z < sz \
								and data[cp.x + cp.z * stride_z + cp.y * stride_y] == mat:
							dm += 1
							cp += back
						depth_m = dm * voxel_size
						seed_q = VoxelGrid.hash01(cell.x, cell.y, cell.z, fi * 17 + 3)
						var ga := (key >> 16) & 7
						if ga > 0:
							grain_code = 2.0 if ga - 1 == ax_n[fi] else (0.0 if ga - 1 == ax_u[fi] else 1.0)
					var start := verts.size()
					var lv := PackedInt32Array([0, 0, 0, 0])
					for k in 4:
						var c := corners[k]
						var level := (key >> (8 + k * 2)) & 3
						lv[k] = level
						verts.append((origin + uf * (c.x * w) + vf * (c.y * h)) * voxel_size)
						normals.append(nf)
						colors.append(Color(base.r, base.g, base.b, ao_curve[level]))
						uvs.append(uv)
						uv2s.append(uv2)
						if extra:
							custom0.append_array(PackedFloat32Array([c.x * w * voxel_size, c.y * h * voxel_size, w * voxel_size, h * voxel_size]))
							custom1.append_array(PackedFloat32Array([depth_m, seed_q, grain_code]))
					if lv[0] + lv[2] >= lv[1] + lv[3]:
						indices.append_array([start, start + 2, start + 1, start, start + 3, start + 2])
					else:
						indices.append_array([start, start + 3, start + 1, start + 1, start + 3, start + 2])
					a += w

	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	if extra:
		arrays[Mesh.ARRAY_CUSTOM0] = custom0
		arrays[Mesh.ARRAY_CUSTOM1] = custom1
	return arrays

static func _axis_of(v: Vector3i) -> int:
	return 0 if v.x != 0 else (1 if v.y != 0 else 2)

## Style LEGACY (Lot 1) : une face par voxel, teinte variée par cellule.
static func _build_arrays_legacy(volume: VoxelVolume, voxel_size: float, region_min: Vector3i,
		region_max: Vector3i, solid_mask: PackedByteArray,
		world_cell_offset: Vector3i, color_seed: int) -> Array:
	var palette := VoxelPalette.get_default()
	if region_max.x < 0:
		region_max = volume.size - Vector3i.ONE
	var sx := volume.size.x
	var sy := volume.size.y
	var sz := volume.size.z
	var stride_z := sx
	var stride_y := sx * sz
	var data := volume.data
	var solid := data if solid_mask.is_empty() else solid_mask
	# Copies locales des tables : chaque thread travaille sur ses propres données.
	var face_n: Array[Vector3i] = []
	var face_u: Array[Vector3i] = []
	var face_v: Array[Vector3i] = []
	var face_b: Array[Vector3i] = []
	for f in _face_table():
		face_n.append(f[0])
		face_u.append(f[1])
		face_v.append(f[2])
		face_b.append(f[3])
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	var ao_curve := PackedFloat32Array([0.48, 0.66, 0.84, 1.0])  # luminosité selon l'occlusion

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	for y in range(region_min.y, region_max.y + 1):
		for z in range(region_min.z, region_max.z + 1):
			var row := z * stride_z + y * stride_y
			for x in range(region_min.x, region_max.x + 1):
				var mat := data[row + x]
				if mat == 0:
					continue
				var base_color: Color = palette.colors_linear[mat]
				var wx := x + world_cell_offset.x
				var wy := y + world_cell_offset.y
				var wz := z + world_cell_offset.z
				var jitter := (VoxelGrid.hash01(wx, wy, wz, color_seed) - 0.5) * 2.0 * palette.variations[mat]
				var tint := VoxelGrid.hash01(wx, wy, wz, color_seed + 7) - 0.5
				var col := Color(
					base_color.r * (1.0 + jitter + tint * palette.variations[mat] * 0.6),
					base_color.g * (1.0 + jitter),
					base_color.b * (1.0 + jitter - tint * palette.variations[mat] * 0.6))
				var uv := Vector2(palette.emission[mat], palette.roughness[mat])
				for fi in 6:
					var n := face_n[fi]
					var nx := x + n.x
					var ny := y + n.y
					var nz := z + n.z
					if nx >= 0 and ny >= 0 and nz >= 0 and nx < sx and ny < sy and nz < sz:
						if solid[nx + nz * stride_z + ny * stride_y] != 0:
							continue
					var u := face_u[fi]
					var v := face_v[fi]
					var b := face_b[fi]
					var start := verts.size()
					var ao := PackedInt32Array([0, 0, 0, 0])
					for k in 4:
						var c := corners[k]
						var su := c.x * 2 - 1
						var sv := c.y * 2 - 1
						var s1 := _is_solid(solid, nx + u.x * su, ny + u.y * su, nz + u.z * su, sx, sy, sz)
						var s2 := _is_solid(solid, nx + v.x * sv, ny + v.y * sv, nz + v.z * sv, sx, sy, sz)
						var s3 := _is_solid(solid, nx + u.x * su + v.x * sv, ny + u.y * su + v.y * sv, nz + u.z * su + v.z * sv, sx, sy, sz)
						var level := 0 if (s1 and s2) else 3 - int(s1) - int(s2) - int(s3)
						ao[k] = level
						var p := Vector3(x + b.x + u.x * c.x + v.x * c.y,
								y + b.y + u.y * c.x + v.y * c.y,
								z + b.z + u.z * c.x + v.z * c.y) * voxel_size
						verts.append(p)
						normals.append(Vector3(n))
						var a := ao_curve[level]
						colors.append(Color(col.r * a, col.g * a, col.b * a, 1.0))
						uvs.append(uv)
						uv2s.append(Vector2(c))
					# Godot : faces avant dans le sens horaire. On retourne la diagonale
					# quand l'AO l'exige pour éviter les dégradés en « X ».
					if ao[0] + ao[2] >= ao[1] + ao[3]:
						indices.append_array([start, start + 2, start + 1, start, start + 3, start + 2])
					else:
						indices.append_array([start, start + 3, start + 1, start + 1, start + 3, start + 2])

	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

## À appeler sur le thread principal avant un maillage parallèle (charge la palette).
static func palette_warmup() -> void:
	VoxelPalette.get_default()

static func _is_solid(solid: PackedByteArray, x: int, y: int, z: int, sx: int, sy: int, sz: int) -> bool:
	if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
		return false
	return solid[x + z * sx + y * sx * sz] != 0
