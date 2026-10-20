@tool
class_name VoxelVolume
extends RefCounted
## Grille 3D dense d'identifiants de matières (0 = air), 1 octet par cellule.
## API volontairement proche de VoxelBuffer (Voxel Tools) : get_voxel / set_voxel.

var size: Vector3i
var data: PackedByteArray
## Donnée auxiliaire optionnelle (même taille) : axe du grain de chaque cellule
## (0 inconnu, 1 = x, 2 = y, 3 = z). Allouée à la première écriture. Sert au rendu du bois.
var aux: PackedByteArray
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
		var i := x + z * _stride_z + y * _stride_y
		data[i] = material_id
		if not aux.is_empty():
			aux[i] = 0

func get_aux(x: int, y: int, z: int) -> int:
	if aux.is_empty() or not is_inside(x, y, z):
		return 0
	return aux[x + z * _stride_z + y * _stride_y]

## Remplit l'axe du grain sur la boîte [from, to] (bornes incluses).
func fill_aux_box(from: Vector3i, to: Vector3i, value: int) -> void:
	if aux.is_empty():
		aux.resize(data.size())
	for y in range(maxi(from.y, 0), mini(to.y, size.y - 1) + 1):
		for z in range(maxi(from.z, 0), mini(to.z, size.z - 1) + 1):
			for x in range(maxi(from.x, 0), mini(to.x, size.x - 1) + 1):
				aux[x + z * _stride_z + y * _stride_y] = value

## Remplit la boîte [from, to] (bornes incluses).
func fill_box(from: Vector3i, to: Vector3i, material_id: int) -> void:
	for y in range(maxi(from.y, 0), mini(to.y, size.y - 1) + 1):
		for z in range(maxi(from.z, 0), mini(to.z, size.z - 1) + 1):
			for x in range(maxi(from.x, 0), mini(to.x, size.x - 1) + 1):
				var i := x + z * _stride_z + y * _stride_y
				data[i] = material_id
				if not aux.is_empty():
					aux[i] = 0

func count_solid() -> int:
	return data.size() - data.count(0)

## Empreinte du contenu (sert à vérifier le déterminisme).
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(size))
	ctx.update(data)
	return ctx.finish().hex_encode()

## Version simplifiée pour les niveaux de détail : chaque bloc factor³ devient un voxel de la
## matière majoritaire si au moins `threshold` du bloc est plein (les feuilles minces survivent).
## Renvoie un volume de taille ceil(size / factor). La grille du maillage doit être multipliée
## par `factor`.
func downsample(factor: int, threshold := 0.25) -> VoxelVolume:
	var ns := Vector3i((size.x + factor - 1) / factor, (size.y + factor - 1) / factor, (size.z + factor - 1) / factor)
	var out := VoxelVolume.new(ns)
	var need := maxi(int(ceil(factor * factor * factor * threshold)), 1)
	var counts := PackedInt32Array()
	counts.resize(256)
	for oy in ns.y:
		for oz in ns.z:
			for ox in ns.x:
				counts.fill(0)
				var solid := 0
				for dy in factor:
					var y := oy * factor + dy
					if y >= size.y:
						break
					for dz in factor:
						var z := oz * factor + dz
						if z >= size.z:
							break
						var row := ox * factor + z * _stride_z + y * _stride_y
						for dx in factor:
							if ox * factor + dx >= size.x:
								break
							var m := data[row + dx]
							if m != 0:
								counts[m] += 1
								solid += 1
				if solid >= need:
					var best := 0
					var best_n := 0
					for m in 256:
						if counts[m] > best_n:
							best_n = counts[m]
							best = m
					out.data[ox + oz * out._stride_z + oy * out._stride_y] = best
	return out
