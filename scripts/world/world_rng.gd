@tool
class_name WorldRng
extends RefCounted
## Flux aléatoires déterministes et INDÉPENDANTS par générateur.
## Chaque générateur reçoit son propre flux dérivé de (graine du monde, étiquette) : ajouter ou
## retirer un objet dans un générateur ne décale jamais les résultats d'un autre. Aucune dépendance
## à String.hash() (FNV-1a maison : identique sur toutes les plateformes et versions du moteur).

static func fnv(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h

## Graine dérivée d'un couple (graine, étiquette), positive, sur 31 bits.
static func sub_seed(seed: int, label: String) -> int:
	var h := (fnv(label) ^ (seed * 2654435761)) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	h = ((h ^ (h >> 12)) * 0x297A2D39) & 0xFFFFFFFF
	h ^= h >> 15
	return int(h & 0x7FFFFFFF)

static func stream(seed: int, label: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = sub_seed(seed, label)
	return r

## Bruit FastNoiseLite déterministe dérivé de (graine, étiquette).
static func noise(seed: int, label: String, frequency: float, octaves := 3) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = sub_seed(seed, label)
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n

## Réel dans [a, b] pour un entier de hachage (sans état).
static func range_f(rng: RandomNumberGenerator, v: Array) -> float:
	return rng.randf_range(float(v[0]), float(v[1]))

static func range_i(rng: RandomNumberGenerator, v: Array) -> int:
	return rng.randi_range(int(v[0]), int(v[1]))
