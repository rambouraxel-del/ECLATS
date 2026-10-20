@tool
class_name RockGenerator
extends RefCounted
## Rochers PARAMÉTRIQUES en quatre familles (cellules de 10 cm, strates de teintes plates) :
##   boulder   bloc isolé : volume bosselé, base aplatie, fissures partielles
##   outcrop   affleurement : empilement de strates en gradins, large et bas, partiellement enterré
##   formation colonnes de hauteurs et de largeurs variées, soudées par un massif ; veines de cristal possibles
##   ruin      vestiges minéraux : fût de colonne brisé, pan de mur d'appareil, linteau, dalles
## Toutes les formes sont ENFONCÉES dans le sol (`embed`) et reliées : aucune pièce ne flotte
## (composantes non ancrées supprimées). Plan puis rastérisation, comme TreeGenerator.

const C := 0.1

const TONES := {
	"warm": ["rock_warm", "rock_warm", "stone", "rock_grey"],
	"grey": ["rock_grey", "rock_grey", "stone", "stone_dark"],
	"dark": ["stone_dark", "rock_grey", "stone_shade", "stone_dark"],
}

static func families() -> PackedStringArray:
	return PackedStringArray(["boulder", "outcrop", "formation", "ruin"])

static func plan(family: String, seed: int) -> Dictionary:
	var rng := WorldRng.stream(seed, "rock:" + family)
	var tone: String = ["warm", "grey", "warm", "grey", "dark"][rng.randi() % 5]
	# identifiants de matières propres à ce rocher (copie locale : aucun conteneur partagé entre fils d'exécution)
	var pal := VoxelPalette.get_default()
	var tone_ids: Array[int] = []
	for k in (TONES[tone] as Array):
		tone_ids.append(pal.id(k))
	var p := {"family": family, "seed": seed, "tone": tone, "tone_ids": tone_ids, "embed": 0.3, "overhang_ok": false}
	match family:
		"boulder":
			var s := rng.randf_range(1.0, 2.6)
			p["radii"] = Vector3(s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.55, 0.9), s * rng.randf_range(0.8, 1.2))
			p["size"] = Vector3(p["radii"].x * 2.1, p["radii"].y * 1.7, p["radii"].z * 2.1)
			p["embed"] = p["radii"].y * 0.35
			p["fissures"] = rng.randi_range(0, 2)
		"outcrop":
			var w := rng.randf_range(2.4, 4.6)
			p["layers"] = rng.randi_range(3, 6)
			p["w"] = w
			p["d"] = w * rng.randf_range(0.55, 0.9)
			p["layer_h"] = rng.randf_range(0.28, 0.45)
			p["size"] = Vector3(w * 1.05, float(p["layers"]) * float(p["layer_h"]), float(p["d"]) * 1.05)
			p["embed"] = 0.35
			p["overhang_ok"] = true
		"formation":
			var k := rng.randi_range(3, 6)
			p["columns"] = k
			p["spread"] = rng.randf_range(1.0, 1.8)
			p["max_h"] = rng.randf_range(2.2, 4.2)
			p["size"] = Vector3(p["spread"] * 2.0 + 1.6, p["max_h"], p["spread"] * 2.0 + 1.6)
			p["embed"] = 0.4
			p["crystal"] = rng.randf() < 0.4
		"ruin":
			p["sub"] = ["column", "wall", "arch", "slab"][rng.randi() % 4]
			match p["sub"]:
				"column": p["size"] = Vector3(2.4, 2.6, 2.4)
				"wall": p["size"] = Vector3(rng.randf_range(2.4, 3.8), rng.randf_range(1.3, 2.3), 0.9)
				"arch": p["size"] = Vector3(3.0, 2.8, 0.9)
				"slab": p["size"] = Vector3(2.4, 0.9, 1.8)
			p["embed"] = 0.2
	return p

static func _mat_for_height(tone_ids: Array, y_m: float, seed: int, band_h: float, warp: float) -> int:
	var band := floori((y_m + warp) / band_h)
	var h := VoxelGrid.hash01(band, 3, 11, seed)
	return tone_ids[int(h * 100.0) % tone_ids.size()]

## Volume + décalage (m) du coin minimum, repère centré sur le pied (y = 0 : surface du sol).
static func rasterize(pl: Dictionary, ground: Dictionary) -> Dictionary:
	var pal := VoxelPalette.get_default()
	var seed: int = pl["seed"]
	var size: Vector3 = pl["size"]
	var embed: float = pl["embed"]
	var margin := 0.4
	var lo := Vector3(-size.x * 0.5 - margin, -embed - 0.6, -size.z * 0.5 - margin)
	lo = (lo / C).floor() * C
	var hi := Vector3(size.x * 0.5 + margin, size.y + 0.4, size.z * 0.5 + margin)
	var vsize := Vector3i(ceili((hi.x - lo.x) / C), ceili((hi.y - lo.y) / C), ceili((hi.z - lo.z) / C))
	var vol := VoxelVolume.new(vsize)
	var rng := WorldRng.stream(seed, "rock_raster")
	var tone_ids: Array = pl["tone_ids"]
	var moss := pal.id("moss")
	var warp := rng.randf() * 5.0
	var band_h := rng.randf_range(0.28, 0.5)
	var nz := FastNoiseLite.new()
	nz.seed = seed
	nz.frequency = 0.9
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	match pl["family"]:
		"boulder": _boulder(vol, lo, pl, pal, nz, tone_ids, band_h, warp)
		"outcrop": _outcrop(vol, lo, pl, pal, nz, tone_ids, rng)
		"formation": _formation(vol, lo, pl, pal, nz, tone_ids, band_h, warp, rng)
		"ruin": _ruin(vol, lo, pl, pal, rng)
	# socle sous le rocher jusqu'au point le plus bas du sol (rien ne flotte sur une pente)
	if not ground.is_empty():
		_plug(vol, lo, pl, ground, pal, tone_ids, seed)
	# mousse sur les faces supérieures exposées (déterministe)
	for z in vol.size.z:
		for x in vol.size.x:
			for y in range(vol.size.y - 1, -1, -1):
				if vol.get_voxel(x, y, z) != 0:
					if y + 1 >= vol.size.y or vol.get_voxel(x, y + 1, z) == 0:
						var yy := lo.y + float(y) * C
						if yy > -0.05 and VoxelGrid.hash01(x, z, 17, seed) < 0.42 and nz.get_noise_3d(float(x) * 2.0, 0.0, float(z) * 2.0) > -0.2:
							vol.set_voxel(x, y, z, moss)
					break
	var removed := VoxelShapes.keep_anchored(vol, int((0.05 - lo.y) / C))
	var b := VoxelShapes.bounds(vol)
	return {"volume": vol, "origin": lo, "plan": pl, "stats": {"cells": vol.count_solid(), "floating_removed": removed, "bounds": b}}

static func _plug(vol: VoxelVolume, lo: Vector3, pl: Dictionary, ground: Dictionary, pal: VoxelPalette, tone_ids: Array, seed: int) -> void:
	# pour chaque colonne occupée au pied, combler jusqu'à 60 cm sous le sol local
	var step := 0.2
	var half: float = ground["half"]
	for z in vol.size.z:
		for x in vol.size.x:
			var wx := lo.x + (float(x) + 0.5) * C
			var wz := lo.z + (float(z) + 0.5) * C
			# cellule la plus basse occupée dans la colonne
			var low_y := -1
			for y in vol.size.y:
				if vol.get_voxel(x, y, z) != 0:
					low_y = y
					break
			if low_y < 0:
				continue
			var gy := TreeGenerator.ground_at(ground, wx, wz) if absf(wx) <= half and absf(wz) <= half else 0.0
			var target := int(floor((gy - 0.3 - lo.y) / C))
			var m := _mat_for_height(tone_ids, lo.y + float(low_y) * C, seed, 0.4, 0.0)
			for y in range(maxi(target, 0), low_y):
				if vol.get_voxel(x, y, z) == 0:
					vol.set_voxel(x, y, z, m)

static func _boulder(vol: VoxelVolume, lo: Vector3, pl: Dictionary, pal: VoxelPalette, nz: FastNoiseLite, tone_ids: Array, band_h: float, warp: float) -> void:
	var radii: Vector3 = pl["radii"]
	var seed: int = pl["seed"]
	var c := Vector3(0, radii.y * 0.45, 0)
	var pick := func(x: int, y: int, z: int, d: float) -> int:
		var yy: float = lo.y + float(y) * C
		var wob := nz.get_noise_3d(float(x) * 0.7, float(y) * 0.7, float(z) * 0.7) * 0.28
		if d + wob > 1.0:
			return 0
		return _mat_for_height(tone_ids, yy, seed, band_h, warp)
	VoxelShapes.ellipsoid_pick(vol, lo, C, c, radii, pick)
	# fissures : plans minces qui entaillent le volume sur une partie de sa profondeur
	var rng := WorldRng.stream(seed, "fissure")
	for f in int(pl["fissures"]):
		var ang := rng.randf() * PI
		var n2 := Vector2(cos(ang), sin(ang))
		var off := rng.randf_range(-radii.x * 0.4, radii.x * 0.4)
		var depth_y := rng.randf_range(0.3, 0.7) * radii.y * 2.0
		for z in vol.size.z:
			for x in vol.size.x:
				var px := lo.x + (float(x) + 0.5) * C
				var pz := lo.z + (float(z) + 0.5) * C
				if absf(px * n2.x + pz * n2.y - off) < 0.06 and Vector2(px, pz).length() < radii.x * 0.95:
					for y in vol.size.y:
						var yy := lo.y + float(y) * C
						if yy > depth_y * 0.25 and yy < depth_y:
							vol.set_voxel(x, y, z, 0)

static func _outcrop(vol: VoxelVolume, lo: Vector3, pl: Dictionary, pal: VoxelPalette, nz: FastNoiseLite, tone_ids: Array, rng: RandomNumberGenerator) -> void:
	var layers: int = pl["layers"]
	var lh: float = pl["layer_h"]
	var w: float = pl["w"]
	var d: float = pl["d"]
	var ox := 0.0
	var oz := 0.0
	for j in layers:
		var t := float(j) / float(maxi(layers - 1, 1))
		var shrink := lerpf(1.0, 0.35, pow(t, 0.8)) * rng.randf_range(0.9, 1.05)
		ox += rng.randf_range(-0.25, 0.25)
		oz += rng.randf_range(-0.18, 0.18)
		var c := Vector3(ox, float(j) * lh + lh * 0.45 - 0.2, oz)
		var radii := Vector3(w * 0.5 * shrink, lh * 0.62, d * 0.5 * shrink)
		var mat: int = tone_ids[(j * 5 + 3 * int(pl["seed"]) % 7) % tone_ids.size()]
		var seed: int = pl["seed"]
		var pick := func(x: int, y: int, z: int, dd: float) -> int:
			var wob := nz.get_noise_3d(float(x) * 0.5, float(y) * 0.5, float(z) * 0.5) * 0.22
			return mat if dd + wob <= 1.0 else 0
		VoxelShapes.ellipsoid_pick(vol, lo, C, c, Vector3(radii.x, radii.y * 1.5, radii.z), pick)

static func _formation(vol: VoxelVolume, lo: Vector3, pl: Dictionary, pal: VoxelPalette, nz: FastNoiseLite, tone_ids: Array, band_h: float, warp: float, rng: RandomNumberGenerator) -> void:
	var k: int = pl["columns"]
	var spread: float = pl["spread"]
	var seed: int = pl["seed"]
	var cols: Array[Dictionary] = []
	for i in k:
		var a := TAU * float(i) / float(k) + rng.randf_range(-0.4, 0.4)
		var r := spread * (0.0 if i == 0 else rng.randf_range(0.55, 1.0))
		cols.append({"x": cos(a) * r, "z": sin(a) * r, "rad": rng.randf_range(0.32, 0.7) * (1.3 if i == 0 else 1.0),
			"h": rng.randf_range(0.45, 1.0) * float(pl["max_h"]) * (1.0 if i == 0 else 0.85), "lean": Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)), "sides": rng.randi_range(5, 7)})
	for col in cols:
		var cx: float = col["x"]
		var cz: float = col["z"]
		var rad: float = col["rad"]
		var h: float = col["h"]
		var sides: int = col["sides"]
		var lean: Vector2 = col["lean"]
		# boîte englobante de la colonne (inclinaison comprise) : on ne parcourt que les cellules utiles
		var reach := rad * 1.3 + absf(lean.x) * h + absf(lean.y) * h + 0.1
		var x0 := maxi(int(floor((cx - reach - lo.x) / C)), 0)
		var x1 := mini(int(ceil((cx + reach - lo.x) / C)), vol.size.x - 1)
		var z0 := maxi(int(floor((cz - reach - lo.z) / C)), 0)
		var z1 := mini(int(ceil((cz + reach - lo.z) / C)), vol.size.z - 1)
		var y0 := maxi(int(floor((-0.2 - lo.y) / C)), 0)
		var y1 := mini(int(ceil((h - lo.y) / C)), vol.size.y - 1)
		for y in range(y0, y1 + 1):
			var yy := lo.y + float(y) * C
			if yy < -0.2 or yy > h:
				continue
			var t := clampf(yy / h, 0.0, 1.0)
			var lx: float = cx + lean.x * yy
			var lz: float = cz + lean.y * yy
			var r_here := rad * lerpf(1.1, 0.8, t)
			var mat := _mat_for_height(tone_ids, yy, seed, band_h, warp)
			for z in range(z0, z1 + 1):
				var pz := lo.z + (float(z) + 0.5) * C
				var dz := pz - lz
				for x in range(x0, x1 + 1):
					var px := lo.x + (float(x) + 0.5) * C
					var dx := px - lx
					var rr0 := Vector2(dx, dz).length()
					if rr0 > rad * 1.3:
						continue
					var ang := atan2(dz, dx)
					var poly := cos(PI / float(sides)) / cos(fposmod(ang, TAU / float(sides)) - PI / float(sides))
					# sommet incliné : facettes
					var cap := h - 0.25 * (dx * 1.0 + 0.5 * dz) / maxf(rad, 0.1)
					if rr0 * poly <= r_here and yy <= cap:
						vol.set_voxel(x, y, z, mat)
	# massif de liaison à la base
	var base_pick := func(x: int, y: int, z: int, d: float) -> int:
		var yy: float = lo.y + float(y) * C
		var wob := nz.get_noise_3d(float(x), float(y), float(z)) * 0.2
		return _mat_for_height(tone_ids, yy, seed, band_h, warp) if d + wob <= 1.0 else 0
	VoxelShapes.ellipsoid_pick(vol, lo, C, Vector3(0, 0.15, 0), Vector3(spread + 0.7, 0.6, spread + 0.7), base_pick)
	if pl.get("crystal", false):
		var cry := pal.id("crystal_cyan")
		var cry2 := pal.id("crystal_ice")
		for i in rng.randi_range(2, 4):
			var a := rng.randf() * TAU
			var rr := rng.randf_range(0.2, spread * 0.8)
			var base := Vector3(cos(a) * rr, rng.randf_range(0.5, 1.0), sin(a) * rr)
			var tip := base + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.7, 1.3), rng.randf_range(-0.2, 0.2))
			VoxelShapes.capsule(vol, lo, C, base, tip, 0.16, 0.04, cry if i % 2 == 0 else cry2)

static func _ruin(vol: VoxelVolume, lo: Vector3, pl: Dictionary, pal: VoxelPalette, rng: RandomNumberGenerator) -> void:
	var ash := pal.id("stone_ashlar")
	var ash_d := pal.id("stone_ashlar_dark")
	var carved := pal.id("stone_carved")
	var brick := pal.id("stone_brick")
	var size: Vector3 = pl["size"]
	var seed: int = pl["seed"]
	match pl["sub"]:
		"column":
			# fût en tambours (0,5 m) ; sommet brisé ; un tambour tombé à côté
			var drums := rng.randi_range(2, 4)
			var r := 0.42
			for j in drums:
				var y0 := float(j) * 0.5
				var tilt := Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04))
				var key: int = [ash, ash_d, carved][j % 3]
				for z in vol.size.z:
					for x in vol.size.x:
						var px := lo.x + (float(x) + 0.5) * C - tilt.x * y0
						var pz := lo.z + (float(z) + 0.5) * C - tilt.y * y0
						if Vector2(px, pz).length() > r - 0.02 * (j % 2):
							continue
						for y in vol.size.y:
							var yy := lo.y + float(y) * C
							if yy >= y0 and yy < y0 + 0.5 - (0.04 if j == drums - 1 else 0.0):
								var broken := j == drums - 1 and yy > y0 + 0.2 and px + 0.3 * pz > 0.2
								if not broken:
									vol.set_voxel(x, y, z, key)
			VoxelShapes.capsule(vol, lo, C, Vector3(0.9, 0.38, -0.6), Vector3(1.1, 0.38, 0.3), 0.36, 0.36, ash)
			VoxelShapes.box_m(vol, lo, C, Vector3(-0.55, -0.1, -0.55), Vector3(0.55, 0.15, 0.55), ash_d)
		"wall":
			# appareil à assises de 20 cm, joints décalés, parties manquantes
			var courses := int(size.y / 0.2)
			for j in courses:
				var bw := 0.5 + 0.1 * float(j % 3)
				var x := -size.x * 0.5 + (0.0 if j % 2 == 0 else bw * 0.5)
				var top_limit := size.y * (0.55 + 0.45 * VoxelGrid.hash01(j, 4, 2, seed))
				while x < size.x * 0.5:
					var run := minf(bw, size.x * 0.5 - x)
					# profil ruiné : l'assise manque aux extrémités plus haut
					var edge_t := absf(x) / (size.x * 0.5)
					var present := float(j) * 0.2 < top_limit * (1.0 - edge_t * 0.55) and VoxelGrid.hash01(j, int(x * 10.0), 8, seed) > 0.08
					if present:
						var key: int = [ash, ash_d, brick, ash][int(VoxelGrid.hash01(j, int(x * 10.0), 5, seed) * 4.0) % 4]
						VoxelShapes.box_m(vol, lo, C, Vector3(x, float(j) * 0.2 - 0.1, -size.z * 0.5 + 0.2), Vector3(x + run - 0.02, float(j) * 0.2 + 0.2 - 0.1, size.z * 0.5 - 0.2), key)
					x += bw
		"arch":
			# deux jambages brisés et un claveau tombé au pied
			for sx in [-1.0, 1.0]:
				var hgt: float = size.y * (1.0 if sx < 0.0 else 0.62) * rng.randf_range(0.9, 1.0)
				VoxelShapes.box_m(vol, lo, C, Vector3(sx * 1.2 - 0.35, -0.1, -0.35), Vector3(sx * 1.2 + 0.35, hgt, 0.35), ash_d)
				for j in int(hgt / 0.2):
					if j % 2 == 0:
						VoxelShapes.box_m(vol, lo, C, Vector3(sx * 1.2 - 0.38, float(j) * 0.2, -0.38), Vector3(sx * 1.2 + 0.38, float(j) * 0.2 + 0.1, 0.38), ash)
			VoxelShapes.box_m(vol, lo, C, Vector3(-1.55, size.y - 0.35, -0.3), Vector3(-0.4, size.y, 0.3), carved)
			VoxelShapes.box_m(vol, lo, C, Vector3(0.3, -0.1, 0.5), Vector3(1.0, 0.4, 1.1), ash)
		"slab":
			# dalles et marches enfoncées
			for j in 3:
				VoxelShapes.box_m(vol, lo, C, Vector3(-size.x * 0.5 + 0.15 * j, -0.2 + float(j) * 0.3, -size.z * 0.5 + 0.4 * j), Vector3(size.x * 0.5 - 0.2 * j, float(j) * 0.3 + 0.2, size.z * 0.5), [ash, ash_d, carved][j])
