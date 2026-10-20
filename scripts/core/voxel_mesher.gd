@tool
class_name VoxelMesher
extends RefCounted
## Transforme une VoxelVolume en ArrayMesh.
## - Seules les faces en contact avec l'air sont générées (aucune face intérieure).
## - Occlusion ambiante par sommet (coins plus sombres) pour des reliefs lisibles.
## - Couleur légèrement variée par voxel, calculée à partir des coordonnées MONDE :
##   un bloc posé a donc exactement la même teinte que le terrain au même endroit.
## Canaux transmis au shader voxel.gdshader :
##   COLOR = couleur linéaire * AO, UV = (émission, rugosité), UV2 = position dans la face.

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
## world_cell_offset : position de la cellule (0,0,0) dans la grille monde (variation de teinte).
## color_seed  : graine de variation de teinte.
static func build(volume: VoxelVolume, voxel_size: float, region_min := Vector3i.ZERO,
		region_max := Vector3i(-1, -1, -1), solid_mask := PackedByteArray(),
		world_cell_offset := Vector3i.ZERO, color_seed := 0) -> ArrayMesh:
	return arrays_to_mesh(build_arrays(volume, voxel_size, region_min, region_max, solid_mask,
			world_cell_offset, color_seed))

## Crée l'ArrayMesh à partir des tableaux produits par build_arrays (null si vide).
static func arrays_to_mesh(arrays: Array) -> ArrayMesh:
	if arrays.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, VoxelMaterials.voxel_material())
	return mesh

## Calcule les tableaux de sommets. Fonction pure : peut tourner dans un thread.
static func build_arrays(volume: VoxelVolume, voxel_size: float, region_min := Vector3i.ZERO,
		region_max := Vector3i(-1, -1, -1), solid_mask := PackedByteArray(),
		world_cell_offset := Vector3i.ZERO, color_seed := 0) -> Array:
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
