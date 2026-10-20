@tool
class_name VoxelVolume
extends RefCounted
## Grille 3D dense d'identifiants de matières (0 = air), 1 octet par cellule.
## API volontairement proche de VoxelBuffer (Voxel Tools) : get_voxel / set_voxel.

var size: Vector3i
var data: PackedByteArray
var _stride_z: int
var _stride_y: int

func _init(p_size: Vector3i = Vector3i.ONE) -> void:
	size = p_size
	_stride_z = size.x
	_stride_y = size.x * size.z
	data = PackedByteArray()
	data.resize(size.x * size.y * size.z)

func index_of(x: int, y: int, z: int) -> int:
	return x + z * _stride_z + y * _stride_y

func is_inside(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z

func get_voxel(x: int, y: int, z: int) -> int:
	if not is_inside(x, y, z):
		return 0
	return data[x + z * _stride_z + y * _stride_y]

func set_voxel(x: int, y: int, z: int, material_id: int) -> void:
	if is_inside(x, y, z):
		data[x + z * _stride_z + y * _stride_y] = material_id

## Remplit la boîte [from, to] (bornes incluses).
func fill_box(from: Vector3i, to: Vector3i, material_id: int) -> void:
	for y in range(maxi(from.y, 0), mini(to.y, size.y - 1) + 1):
		for z in range(maxi(from.z, 0), mini(to.z, size.z - 1) + 1):
			for x in range(maxi(from.x, 0), mini(to.x, size.x - 1) + 1):
				data[x + z * _stride_z + y * _stride_y] = material_id

func count_solid() -> int:
	return data.size() - data.count(0)

## Empreinte du contenu (sert à vérifier le déterminisme).
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(size))
	ctx.update(data)
	return ctx.finish().hex_encode()
