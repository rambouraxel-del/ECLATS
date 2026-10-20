@tool
class_name OccupancyMap
extends RefCounted
## Registre des espaces occupés et RÉSERVÉS d'une île (colonnes de 20 cm + volumes 3D).
## Les générateurs réservent d'abord (place, parcelles, chemins), puis placent : deux générateurs ne
## peuvent jamais s'attribuer le même espace. Index spatial : cellules de 4 m.

const V := VoxelGrid.VOXEL_SIZE
const HASH := 4.0

var field: TerrainField
var tag := PackedByteArray()       # étiquette de réservation par colonne (PlacementSpec.TAG_*)
var owner := PackedInt32Array()    # propriétaire de la réservation (0 = personne)
var items: Array = []              # {id, kind, owner, pos, yaw, hard:[AABB], soft:[AABB], rect, clearance, spec}
var _hash := {}
var _next_owner := 1

func _init(p_field: TerrainField) -> void:
	field = p_field
	tag.resize(field.n * field.n)
	owner.resize(field.n * field.n)

func new_owner() -> int:
	_next_owner += 1
	return _next_owner

func tag_at(cx: int, cz: int) -> int:
	return tag[cx + cz * field.n] if field.in_bounds(cx, cz) else PlacementSpec.TAG_FREE

func owner_at(cx: int, cz: int) -> int:
	return owner[cx + cz * field.n] if field.in_bounds(cx, cz) else 0

## Réserve un rectangle de colonnes. overwrite = false : ne touche pas aux cellules déjà réservées.
func reserve(rect: Rect2i, p_tag: int, p_owner: int, overwrite := true) -> int:
	var count := 0
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if not field.has_ground(cx, cz):
				continue
			var i := cx + cz * field.n
			if tag[i] != PlacementSpec.TAG_FREE and not overwrite:
				continue
			tag[i] = p_tag
			owner[i] = p_owner
			count += 1
	return count

func reserve_disc(center_m: Vector2, radius_m: float, p_tag: int, p_owner: int, overwrite := true) -> void:
	var c := field.col_of_m(center_m.x, center_m.y)
	var r := int(ceil(radius_m / V)) + 1
	for cz in range(c.y - r, c.y + r + 1):
		for cx in range(c.x - r, c.x + r + 1):
			if not field.has_ground(cx, cz):
				continue
			if field.center_m(cx, cz).distance_to(center_m) > radius_m:
				continue
			var i := cx + cz * field.n
			if tag[i] != PlacementSpec.TAG_FREE and not overwrite:
				continue
			tag[i] = p_tag
			owner[i] = p_owner

func release_owner(p_owner: int) -> void:
	for i in tag.size():
		if owner[i] == p_owner:
			tag[i] = PlacementSpec.TAG_FREE
			owner[i] = 0

func rect_free(rect: Rect2i, allowed_tags: PackedInt32Array, p_owner := 0) -> bool:
	for cz in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if not field.has_ground(cx, cz):
				continue
			var i := cx + cz * field.n
			if tag[i] == PlacementSpec.TAG_FREE:
				continue
			if p_owner != 0 and owner[i] == p_owner:
				continue
			if not allowed_tags.has(tag[i]):
				return false
	return true

# ------------------------------------------------------------------ objets placés

func add_item(item: Dictionary) -> int:
	items.append(item)
	var k := items.size() - 1
	for b: AABB in item["hard"] + item["soft"]:
		for key in _keys(b):
			if not _hash.has(key):
				_hash[key] = []
			if not _hash[key].has(k):
				_hash[key].append(k)
	return k

func _keys(b: AABB) -> Array:
	var out := []
	for gz in range(floori(b.position.z / HASH), floori(b.end.z / HASH) + 1):
		for gx in range(floori(b.position.x / HASH), floori(b.end.x / HASH) + 1):
			out.append(Vector2i(gx, gz))
	return out

## Indices des objets dont un volume peut rencontrer la boîte (zone élargie d'une marge).
func candidates(b: AABB, margin := 0.0) -> Array:
	var seen := {}
	var out := []
	for key in _keys(b.grow(margin)):
		for k in _hash.get(key, []):
			if not seen.has(k):
				seen[k] = true
				out.append(k)
	return out

func count_kind(kind: String) -> int:
	var n := 0
	for it in items:
		if it["kind"] == kind:
			n += 1
	return n
