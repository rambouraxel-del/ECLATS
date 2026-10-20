@tool
class_name VoxelShapes
extends RefCounted
## Primitives de rastérisation en mètres (capsules effilées, ellipsoïdes, cylindres) sur un VoxelVolume.
## `origin` = position (m) de la cellule (0,0,0) dans le repère de l'objet ; `grid` = côté d'une cellule (m).
## Utilisé par les arbres, rochers et le bateau : aucune de ces formes ne dépend d'une île.

## Capsule effilée de a à b (rayons r0 → r1), matière `mat`.
static func capsule(vol: VoxelVolume, origin: Vector3, grid: float, a: Vector3, b: Vector3, r0: float, r1: float, mat: int, only_empty := false) -> void:
	# rayon minimal : une capsule plus fine qu'une demi-cellule perdrait des cellules et se couperait en morceaux
	r0 = maxf(r0, grid * 0.62)
	r1 = maxf(r1, grid * 0.62)
	var len := a.distance_to(b)
	var steps := maxi(int(ceil(len / (grid * 0.5))), 1)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		sphere(vol, origin, grid, p, lerpf(r0, r1, t), mat, only_empty)

static func sphere(vol: VoxelVolume, origin: Vector3, grid: float, c: Vector3, r: float, mat: int, only_empty := false) -> void:
	var lo := (c - Vector3(r, r, r) - origin) / grid
	var hi := (c + Vector3(r, r, r) - origin) / grid
	var r2 := r * r
	for z in range(maxi(floori(lo.z), 0), mini(ceili(hi.z), vol.size.z - 1) + 1):
		var dz := origin.z + (float(z) + 0.5) * grid - c.z
		for y in range(maxi(floori(lo.y), 0), mini(ceili(hi.y), vol.size.y - 1) + 1):
			var dy := origin.y + (float(y) + 0.5) * grid - c.y
			var rem := r2 - dz * dz - dy * dy
			if rem < 0.0:
				continue
			for x in range(maxi(floori(lo.x), 0), mini(ceili(hi.x), vol.size.x - 1) + 1):
				var dx := origin.x + (float(x) + 0.5) * grid - c.x
				if dx * dx <= rem:
					if only_empty and vol.get_voxel(x, y, z) != 0:
						continue
					vol.set_voxel(x, y, z, mat)

## Ellipsoïde de rayons `radii` (m), cellules choisies par `pick(x, y, z, d) -> int` (0 = pas de cellule),
## d = distance normalisée au centre (0 centre, 1 surface). Pas d'allocation de nœud.
static func ellipsoid_pick(vol: VoxelVolume, origin: Vector3, grid: float, c: Vector3, radii: Vector3, pick: Callable) -> void:
	var lo := (c - radii * 1.25 - origin) / grid
	var hi := (c + radii * 1.25 - origin) / grid
	for z in range(maxi(floori(lo.z), 0), mini(ceili(hi.z), vol.size.z - 1) + 1):
		var nz := (origin.z + (float(z) + 0.5) * grid - c.z) / radii.z
		for y in range(maxi(floori(lo.y), 0), mini(ceili(hi.y), vol.size.y - 1) + 1):
			var ny := (origin.y + (float(y) + 0.5) * grid - c.y) / radii.y
			for x in range(maxi(floori(lo.x), 0), mini(ceili(hi.x), vol.size.x - 1) + 1):
				var nx := (origin.x + (float(x) + 0.5) * grid - c.x) / radii.x
				var d := sqrt(nx * nx + ny * ny + nz * nz)
				var m: int = pick.call(x, y, z, d)
				if m > 0:
					vol.set_voxel(x, y, z, m)

## Boîte alignée (m), bornes incluses côté minimum, exclues côté maximum.
static func box_m(vol: VoxelVolume, origin: Vector3, grid: float, lo: Vector3, hi: Vector3, mat: int) -> void:
	var a := (lo - origin) / grid
	var b := (hi - origin) / grid
	for z in range(maxi(roundi(a.z), 0), mini(roundi(b.z), vol.size.z)):
		for y in range(maxi(roundi(a.y), 0), mini(roundi(b.y), vol.size.y)):
			for x in range(maxi(roundi(a.x), 0), mini(roundi(b.x), vol.size.x)):
				vol.set_voxel(x, y, z, mat)

## Volume englobant des cellules non vides (cellules entières), ou Rect3i vide.
static func bounds(vol: VoxelVolume) -> Dictionary:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := Vector3i(-(1 << 20), -(1 << 20), -(1 << 20))
	var found := false
	for z in vol.size.z:
		for y in vol.size.y:
			for x in vol.size.x:
				if vol.get_voxel(x, y, z) != 0:
					found = true
					lo = Vector3i(mini(lo.x, x), mini(lo.y, y), mini(lo.z, z))
					hi = Vector3i(maxi(hi.x, x), maxi(hi.y, y), maxi(hi.z, z))
	return {"found": found, "lo": lo, "hi": hi}

## Composantes connexes (26 voisins) : renvoie les indices de cellules de chaque composante.
static func components(vol: VoxelVolume) -> Array:
	var seen := PackedByteArray()
	seen.resize(vol.data.size())
	var comps: Array = []
	var sx := vol.size.x
	var sz := vol.size.z
	for start in vol.data.size():
		if vol.data[start] == 0 or seen[start] == 1:
			continue
		var comp: Array[int] = []
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			var x := i % sx
			var z := (i / sx) % sz
			var y := i / (sx * sz)
			for dz in range(-1, 2):
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0 and dz == 0:
							continue
						var nx := x + dx
						var ny := y + dy
						var nz := z + dz
						if nx < 0 or ny < 0 or nz < 0 or nx >= vol.size.x or ny >= vol.size.y or nz >= sz:
							continue
						var j := nx + nz * sx + ny * sx * sz
						if vol.data[j] != 0 and seen[j] == 0:
							seen[j] = 1
							stack.append(j)
		comps.append(comp)
	return comps

## Supprime toute composante qui ne touche pas `anchor_y_max` cellules du bas (rien ne flotte).
## Renvoie le nombre de cellules retirées.
static func keep_anchored(vol: VoxelVolume, anchor_y_max: int) -> int:
	var removed := 0
	var sx := vol.size.x
	var sz := vol.size.z
	for comp in components(vol):
		var anchored := false
		for i in comp:
			if i / (sx * sz) <= anchor_y_max:
				anchored = true
				break
		if not anchored:
			for i in comp:
				vol.data[i] = 0
			removed += comp.size()
	return removed

## Ne garde que la plus grande composante connexe (les éclats isolés sont retirés). Renvoie le nombre de cellules retirées.
static func keep_largest(vol: VoxelVolume) -> int:
	var comps := components(vol)
	if comps.size() <= 1:
		return 0
	var best := 0
	for k in comps.size():
		if comps[k].size() > comps[best].size():
			best = k
	var removed := 0
	for k in comps.size():
		if k == best:
			continue
		for i in comps[k]:
			vol.data[i] = 0
		removed += comps[k].size()
	return removed
