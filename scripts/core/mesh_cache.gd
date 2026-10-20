@tool
class_name MeshCache
extends RefCounted
## Cache de tableaux de sommets par CONTENU (empreinte du volume + taille de cellule). Deux objets
## identiques (tonneaux, battants de porte, caisses…) ne sont maillés qu'une fois, même depuis des fils
## d'exécution différents (accès protégé par un verrou). Les tableaux sont en lecture seule après création.

static var _cache := {}
static var _mutex := Mutex.new()
static var hits := 0
static var misses := 0

static func arrays_for(vol: VoxelVolume, grid: float) -> Array:
	var key := vol.checksum() + "|" + str(grid)
	_mutex.lock()
	var found = _cache.get(key)
	if found != null:
		hits += 1
	_mutex.unlock()
	if found != null:
		return found
	var arr := VoxelMesher.build_arrays(vol, grid, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	_mutex.lock()
	_cache[key] = arr
	misses += 1
	_mutex.unlock()
	return arr

static func clear() -> void:
	_mutex.lock()
	_cache.clear()
	hits = 0
	misses = 0
	_mutex.unlock()
