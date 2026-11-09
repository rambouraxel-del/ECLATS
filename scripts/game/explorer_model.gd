class_name ExplorerModel
extends Node3D
## Explorateur (personnage jouable) — version 2, d'après la planche de référence : formes cubiques adoucies,
## proportions compactes (tête ≈ ⅓ de la hauteur), visage expressif, lunettes d'aviateur en laiton, écharpe-cape
## bleu lavande à croix sable, tunique crème, gilet et ceinture de cuir, pantalon kaki, bottes brunes.
##
## Modèle voxel de 1,72 m en cellules de 4 cm (le jeu l'affiche à l'échelle de `PlayerConfig`, 1,50 m).
## Articulé : 17 pivots (hanches, torse, tête, bras + avant-bras, cuisses + tibias + pieds, cape en 2 pans,
## tabard, bourse) ; chaque pièce est un maillage voxel rigide posé sur son pivot (pas de peau à calculer :
## l'export glTF de la galerie reprend la même hiérarchie et les mêmes animations).
## Animations (`Animation` réelles dans un `AnimationPlayer`) : idle, walk, run, jump (saut / chute).
## Repère : pieds en y = 0, regard vers -z ; +x = côté droit du personnage.

const G := 0.04
const HIPS_Y := 14.0 * G                 # hauteur des hanches : 0,56 m
const CLIPS := {                         # nom → [libellé, durée (s) de la boucle]
	"idle": ["Attente", 3.2],
	"walk": ["Marche", 0.9],
	"run": ["Course", 0.56],
	"jump": ["Saut / chute", 1.0],
}
const ARM_REST := 0.15                   # bras légèrement écartés (pose en A de la planche)
const KEYS := 16                         # images clés par boucle

var anim: AnimationPlayer
var parts := {}                          # nom → pivot (Node3D)
var _clip := ""
var _fall_t := 0.0

func _ready() -> void:
	if parts.is_empty():
		_build()

## Construction hors arbre de scène (export de la galerie) : maillages, pivots et animations.
func build_now() -> void:
	if parts.is_empty():
		_build()

# ---------------------------------------------------------------- fabrication des pièces

## Arrondit les arêtes : retire les cellules d'angle (exposées sur les trois axes et adossées à au moins
## trois voisines) → cubes « adoucis » sans changer la grille.
func _soften(b: VoxelModelBuilder) -> void:
	var v := b.volume
	var sz := v.size
	var kill: Array[Vector3i] = []
	for y in sz.y:
		for z in sz.z:
			for x in sz.x:
				if v.get_voxel(x, y, z) == 0:
					continue
				var ex := v.get_voxel(x - 1, y, z) == 0 or v.get_voxel(x + 1, y, z) == 0
				var ey := v.get_voxel(x, y - 1, z) == 0 or v.get_voxel(x, y + 1, z) == 0
				var ez := v.get_voxel(x, y, z - 1) == 0 or v.get_voxel(x, y, z + 1) == 0
				if not (ex and ey and ez):
					continue
				var n := 0
				for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					if v.get_voxel(x + d.x, y + d.y, z + d.z) != 0:
						n += 1
				if n >= 3:
					kill.append(Vector3i(x, y, z))
	for c in kill:
		v.set_voxel(c.x, c.y, c.z, 0)

## Pièce voxel. `fill(b)` dessine la masse, `soft` arrondit, `detail(b)` ajoute les détails fins après l'arrondi.
## `anchor` = position (cellules) du pivot dans la pièce ; `pivot` = point d'attache (m, repère du parent).
func _part(parent: Node3D, pname: String, size: Vector3i, anchor: Vector3, pivot: Vector3, fill: Callable, soft := true, detail := Callable()) -> Node3D:
	var b := VoxelModelBuilder.new(size)
	fill.call(b)
	if soft:
		_soften(b)
	if detail.is_valid():
		detail.call(b)
	var pv := Node3D.new()
	pv.name = pname
	pv.position = pivot
	parent.add_child(pv)
	var mesh := VoxelMesher.build(b.volume, G, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	if mesh != null:
		mesh.surface_set_material(0, VoxelMaterials.props_material())
		var mi := MeshInstance3D.new()
		mi.name = pname + "_mesh"
		mi.mesh = mesh
		mi.position = -anchor * G
		pv.add_child(mi)
	parts[pname] = pv
	return pv

func _build() -> void:
	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0, HIPS_Y, 0)
	add_child(hips)
	parts["Hips"] = hips
	_build_legs(hips)
	var torso := _build_torso(hips)
	_build_head(torso)
	_build_arms(torso)
	_build_cape(torso)
	_rest_pose()
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	anim.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	for c in CLIPS:
		lib.add_animation(c, _make_clip(c))
	anim.add_animation_library("", lib)

func _build_legs(hips: Node3D) -> void:
	for side in [-1, 1]:
		var s := "L" if side < 0 else "R"
		# cuisse : pantalon kaki bouffant
		var f_thigh := func(b: VoxelModelBuilder) -> void:
			b.box(0, 0, 0, 5, 6, 5, "perso_pantalon")
		var thigh := _part(hips, "Thigh" + s, Vector3i(6, 7, 6), Vector3(3, 7, 3), Vector3(3.0 * side * G, 0, 0), f_thigh)
		# tibia : botte brune, rabat de cuir clair, sangle sable
		var f_shin := func(b: VoxelModelBuilder) -> void:
			b.box(0, 0, 0, 4, 4, 4, "perso_botte")
			b.box(0, 4, 0, 4, 4, 4, "perso_cuir_clair")
		var d_shin := func(b: VoxelModelBuilder) -> void:
			b.box(1, 1, 0, 3, 3, 0, "perso_beige")
			b.set_cell(2, 2, 0, "perso_laiton")
		var shin := _part(thigh, "Shin" + s, Vector3i(5, 5, 5), Vector3(2.5, 5, 2.5), Vector3(0, -7 * G, 0), f_shin, true, d_shin)
		# pied : semelle sombre, bout renforcé
		var f_foot := func(b: VoxelModelBuilder) -> void:
			b.box(0, 0, 0, 4, 1, 6, "perso_botte")
			b.box(0, 0, 0, 4, 0, 6, "wood_aged_dark")
		var d_foot := func(b: VoxelModelBuilder) -> void:
			b.box(1, 1, 0, 3, 1, 1, "perso_cuir_clair")
		_part(shin, "Foot" + s, Vector3i(5, 2, 7), Vector3(2.5, 2, 4), Vector3(0, -5 * G, 0), f_foot, true, d_foot)

func _build_torso(hips: Node3D) -> Node3D:
	var fill := func(b: VoxelModelBuilder) -> void:
		b.box(1, 0, 1, 10, 13, 6, "perso_tunique")
		b.box(0, 11, 0, 11, 14, 7, "perso_cape")                      # écharpe-cape autour du cou
		b.box(1, 1, 1, 10, 2, 6, "perso_cuir")                         # ceinture
		b.box(1, 3, 1, 2, 10, 1, "perso_cuir")                         # gilet (deux pans)
		b.box(9, 3, 1, 10, 10, 1, "perso_cuir")
	var detail := func(b: VoxelModelBuilder) -> void:
		b.box(5, 1, 0, 6, 2, 0, "perso_laiton")                               # boucle de ceinture
		for y in [5, 8]:                                               # brandebourgs du gilet
			b.set_cell(4, y, 0, "perso_cuir_clair")
			b.set_cell(7, y, 0, "perso_cuir_clair")
		b.box(0, 11, 0, 11, 11, 0, "perso_cape_ombre")                # ourlet de l'écharpe
		b.box(1, 8, 0, 4, 10, 0, "perso_cape")                         # drapé sur la poitrine + croix sable
		for c in [Vector2i(2, 9), Vector2i(2, 8), Vector2i(2, 10), Vector2i(1, 9), Vector2i(3, 9)]:
			b.set_cell(c.x, c.y, 0, "perso_beige")
		b.box(1, 7, 0, 4, 7, 0, "perso_beige")
	return _part(hips, "Torso", Vector3i(12, 15, 8), Vector3(6, 0, 4), Vector3.ZERO, fill, true, detail)

func _build_head(torso: Node3D) -> void:
	var fill := func(b: VoxelModelBuilder) -> void:
		b.box(1, 0, 1, 10, 9, 10, "perso_peau")                        # crâne et visage
		b.box(0, 3, 4, 0, 5, 6, "perso_peau_ombre")                    # oreilles
		b.box(11, 3, 4, 11, 5, 6, "perso_peau_ombre")
		b.box(1, 6, 1, 10, 11, 10, "perso_cheveux")                    # boucles : calotte
		b.box(1, 3, 6, 10, 11, 10, "perso_cheveux")                    # nuque
		b.box(0, 6, 3, 0, 10, 9, "perso_cheveux")
		b.box(11, 6, 3, 11, 10, 9, "perso_cheveux")
		b.box(1, 0, 1, 3, 1, 3, "perso_barbe")                         # barbe courte
		b.box(8, 0, 1, 10, 1, 3, "perso_barbe")
		b.box(1, 2, 1, 1, 4, 3, "perso_barbe")
		b.box(10, 2, 1, 10, 4, 3, "perso_barbe")
		for z in range(1, 11):                                         # volume irrégulier des boucles
			for x in range(0, 12):
				var h := VoxelGrid.hash01(x, 7, z, 31)
				var top := 11 + (1 if h > 0.45 else 0) + (1 if h > 0.85 else 0)
				if z <= 2 and h < 0.4:
					top -= 1
				if (x == 0 or x == 11 or z == 1 or z == 10) and h < 0.35:
					continue
				for y in range(11, top + 1):
					b.set_cell(x, y, z, "perso_cheveux")
		b.speckle("perso_cheveux", "perso_cheveux_clair", 0.22, 5)
	var detail := func(b: VoxelModelBuilder) -> void:
		for x in range(1, 11):                                         # frange (alternance peau / mèches)
			b.set_cell(x, 9, 1, "perso_cheveux")
			if x in [1, 2, 5, 9, 10]:
				b.set_cell(x, 8, 1, "perso_cheveux")
		b.set_cell(2, 8, 1, "perso_cheveux_clair")
		b.set_cell(7, 8, 1, "perso_cheveux_clair")
		for x in [2, 3, 4, 7, 8, 9]:                                   # sourcils
			b.set_cell(x, 7, 1, "perso_cheveux")
		for x in [3, 8]:                                               # yeux
			b.set_cell(x, 4, 1, "perso_oeil")
			b.set_cell(x, 5, 1, "perso_oeil")
		for x in [5, 6]:                                               # sourire
			b.set_cell(x, 2, 1, "perso_oeil")
		b.set_cell(4, 3, 1, "perso_oeil")
		b.set_cell(7, 3, 1, "perso_oeil")
		b.set_cell(2, 3, 1, "perso_peau_ombre")                        # joues
		b.set_cell(9, 3, 1, "perso_peau_ombre")
		for gx in [1, 6]:                                              # lunettes d'aviateur relevées sur le front
			b.box(gx, 10, 0, gx + 4, 13, 1, "perso_laiton")
			b.box(gx + 1, 11, 0, gx + 3, 12, 1, "perso_verre")
		b.box(0, 10, 2, 11, 11, 2, "perso_cuir")                       # sangle de cuir et boucle
		b.box(0, 10, 2, 0, 11, 9, "perso_cuir")
		b.box(11, 10, 2, 11, 11, 9, "perso_cuir")
		b.box(0, 10, 10, 11, 11, 10, "perso_cuir")
		b.box(0, 10, 5, 0, 11, 6, "perso_laiton")
	_part(torso, "Head", Vector3i(12, 15, 11), Vector3(6, 0, 6), Vector3(0, 14 * G, 0), fill, true, detail)

func _build_arms(torso: Node3D) -> void:
	for side in [-1, 1]:
		var s := "L" if side < 0 else "R"
		var f_arm := func(b: VoxelModelBuilder) -> void:                # manche crème, revers sable
			b.box(1, 0, 1, 4, 5, 4, "perso_tunique")
			b.box(0, 0, 0, 5, 2, 5, "perso_beige")
		var arm := _part(torso, "Arm" + s, Vector3i(6, 6, 6), Vector3(3, 6, 3), Vector3(7.0 * side * G, 13 * G, 0), f_arm)
		var f_fore := func(b: VoxelModelBuilder) -> void:               # brassard de cuir, main nue
			b.box(1, 4, 1, 4, 7, 4, "perso_cuir")
			b.box(1, 0, 1, 4, 3, 4, "perso_peau")
		var d_fore := func(b: VoxelModelBuilder) -> void:
			b.box(1, 7, 1, 4, 7, 4, "perso_cuir_clair")
			b.box(1, 5, 0, 4, 5, 0, "perso_cuir_clair")
		_part(arm, "Forearm" + s, Vector3i(6, 8, 6), Vector3(3, 8, 3), Vector3(0, -6 * G, 0), f_fore, true, d_fore)

func _build_cape(torso: Node3D) -> void:
	# cape : deux pans (haut + bas) pour onduler, liseré sable et croix dans le dos
	var f_up := func(b: VoxelModelBuilder) -> void:
		b.box(0, 0, 0, 14, 6, 1, "perso_cape")
	var up := _part(torso, "CapeUp", Vector3i(15, 7, 2), Vector3(7.5, 7, 0), Vector3(0, 13 * G, 4 * G), f_up, false)
	var f_low := func(b: VoxelModelBuilder) -> void:
		b.box(0, 0, 0, 14, 6, 1, "perso_cape")
	var d_low := func(b: VoxelModelBuilder) -> void:
		for x in range(0, 15):                                         # pointe en V + liseré sable
			var d := absi(x - 7)
			var row := 0 if d < 5 else (1 if d == 5 else 2)
			for y in range(0, row):
				b.set_cell(x, y, 0, "")
				b.set_cell(x, y, 1, "")
			b.set_cell(x, row, 1, "perso_beige")
			b.set_cell(x, row, 0, "perso_cape_ombre")
		for c in [Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 2), Vector2i(6, 3), Vector2i(8, 3)]:
			b.set_cell(c.x, c.y, 1, "perso_beige")
	_part(up, "CapeLow", Vector3i(15, 7, 2), Vector3(7.5, 7, 0), Vector3(0, -7 * G, 0), f_low, false, d_low)
	# tabard : bannière bleue à croix sablée sur la hanche droite
	var f_tab := func(b: VoxelModelBuilder) -> void:
		b.box(0, 0, 0, 4, 7, 0, "perso_cape")
	var d_tab := func(b: VoxelModelBuilder) -> void:
		b.box(0, 0, 0, 0, 7, 0, "perso_beige")
		b.box(4, 0, 0, 4, 7, 0, "perso_beige")
		b.box(0, 0, 0, 4, 0, 0, "perso_beige")
		for c in [Vector2i(2, 4), Vector2i(2, 3), Vector2i(2, 5), Vector2i(1, 4), Vector2i(3, 4)]:
			b.set_cell(c.x, c.y, 0, "perso_beige")
	_part(torso, "Tabard", Vector3i(5, 8, 1), Vector3(2.5, 8, 0.5), Vector3(3.5 * G, 1.5 * G, -3.5 * G), f_tab, false, d_tab)
	# bourse de cuir à la hanche gauche
	var f_pouch := func(b: VoxelModelBuilder) -> void:
		b.box(0, 0, 0, 2, 3, 3, "perso_cuir_clair")
	var d_pouch := func(b: VoxelModelBuilder) -> void:
		b.box(0, 3, 0, 2, 3, 3, "perso_cuir")
		b.set_cell(1, 2, 0, "perso_laiton")
	_part(torso, "Pouch", Vector3i(3, 4, 4), Vector3(1.5, 4, 2), Vector3(-6.5 * G, 1.0 * G, 0), f_pouch, true, d_pouch)

# ---------------------------------------------------------------- poses et animations

func _rest_pose() -> void:
	for n in parts:
		(parts[n] as Node3D).rotation = Vector3.ZERO
	(parts["ArmL"] as Node3D).rotation = Vector3(0, 0, -ARM_REST)
	(parts["ArmR"] as Node3D).rotation = Vector3(0, 0, ARM_REST)

## Pose à la phase `ph` (0..1) du clip : nom de pivot → Vector3 (rotation, rad) ; "Hips" → position aussi.
func _pose(clip: String, ph: float) -> Dictionary:
	var w := TAU * ph
	var p := {}
	var hips_y := HIPS_Y
	var hips_x := 0.0
	match clip:
		"idle":
			var br := sin(w)
			hips_y += 0.006 * br
			hips_x = 0.006 * sin(w)
			p["Hips"] = Vector3(0, 0, 0.012 * sin(w))
			p["Torso"] = Vector3(0.012 * br, 0.03 * sin(w), -0.012 * sin(w))
			p["Head"] = Vector3(-0.015 * br + 0.02, 0.2 * sin(w), 0.035 * sin(2.0 * w + 0.6))
			p["ArmL"] = Vector3(0.03 * sin(w + 0.4), 0, -ARM_REST - 0.015 * br)
			p["ArmR"] = Vector3(-0.03 * sin(w + 0.4), 0, ARM_REST + 0.015 * br)
			p["ForearmL"] = Vector3(-0.12 - 0.02 * br, 0, 0)
			p["ForearmR"] = Vector3(-0.12 - 0.02 * br, 0, 0)
			p["ThighL"] = Vector3(0.0, 0, 0.0)
			p["ThighR"] = Vector3(0.0, 0, 0.0)
			p["CapeUp"] = Vector3(0.04 + 0.025 * sin(w + 0.8), 0, 0.01 * sin(w))
			p["CapeLow"] = Vector3(0.03 + 0.04 * sin(w + 1.7), 0, 0)
			p["Tabard"] = Vector3(0.02 * sin(w + 1.0), 0, 0)
			p["Pouch"] = Vector3(0.02 * sin(w + 2.0), 0, 0.02 * sin(w))
		"walk", "run":
			var run := clip == "run"
			var A := 0.95 if run else 0.55            # amplitude de cuisse
			var swing := sin(w)
			var tl := A * swing
			var tr := -A * swing
			var fl := _knee(w, run)
			var fr := _knee(w + PI, run)
			hips_y += (0.05 if run else 0.022) * cos(2.0 * w) - (0.02 if run else 0.0)
			p["Hips"] = Vector3(0.0, 0.0, (0.03 if run else 0.04) * swing)
			p["ThighL"] = Vector3(tl, 0, 0)
			p["ThighR"] = Vector3(tr, 0, 0)
			p["ShinL"] = Vector3(-fl, 0, 0)
			p["ShinR"] = Vector3(-fr, 0, 0)
			p["FootL"] = Vector3(0.45 * (tl - fl) * 0.0 - tl * 0.5 + fl * 0.35 - 0.05, 0, 0)
			p["FootR"] = Vector3(0.45 * (tr - fr) * 0.0 - tr * 0.5 + fr * 0.35 - 0.05, 0, 0)
			var lean := 0.24 if run else 0.05
			p["Torso"] = Vector3(lean, (0.2 if run else 0.12) * swing, -0.03 * swing)
			p["Head"] = Vector3(-lean * 0.8, -(0.2 if run else 0.1) * swing, 0.02 * swing)
			var sa := 0.9 if run else 0.5
			p["ArmL"] = Vector3(-sa * swing, 0, -ARM_REST - (0.05 if run else 0.0))
			p["ArmR"] = Vector3(sa * swing, 0, ARM_REST + (0.05 if run else 0.0))
			var eb := 1.25 if run else 0.25
			p["ForearmL"] = Vector3(-(eb + 0.25 * maxf(0.0, -swing) * (1.0 if run else 0.8)), 0, 0)
			p["ForearmR"] = Vector3(-(eb + 0.25 * maxf(0.0, swing) * (1.0 if run else 0.8)), 0, 0)
			var cs := 0.62 if run else 0.16
			p["CapeUp"] = Vector3(cs + (0.09 if run else 0.05) * sin(2.0 * w + 0.6), 0, 0.05 * sin(w))
			p["CapeLow"] = Vector3((0.28 if run else 0.1) + (0.22 if run else 0.1) * sin(2.0 * w + 1.5), 0, 0.06 * sin(w + 1.0))
			p["Tabard"] = Vector3((0.45 if run else 0.12) + 0.15 * sin(2.0 * w + 1.0), 0, 0.04 * swing)
			p["Pouch"] = Vector3(0.1 * sin(2.0 * w + 0.5), 0, 0.12 * swing)
		"jump":
			var fl2 := sin(w)
			hips_y += 0.0
			p["Hips"] = Vector3(0, 0, 0)
			p["ThighL"] = Vector3(-0.5 + 0.06 * fl2, 0, 0)
			p["ThighR"] = Vector3(0.75 + 0.06 * fl2, 0, 0)
			p["ShinL"] = Vector3(0.45, 0, 0)
			p["ShinR"] = Vector3(-0.85, 0, 0)
			p["FootL"] = Vector3(0.3, 0, 0)
			p["FootR"] = Vector3(0.25, 0, 0)
			p["Torso"] = Vector3(0.04, 0, 0)
			p["Head"] = Vector3(-0.12, 0, 0)
			p["ArmL"] = Vector3(-0.35 + 0.1 * fl2, 0, -0.95)
			p["ArmR"] = Vector3(-0.35 - 0.1 * fl2, 0, 0.95)
			p["ForearmL"] = Vector3(-0.5, 0, 0)
			p["ForearmR"] = Vector3(-0.5, 0, 0)
			p["CapeUp"] = Vector3(0.75 + 0.06 * sin(w + 1.0), 0, 0)
			p["CapeLow"] = Vector3(0.45 + 0.15 * sin(w + 2.0), 0, 0)
			p["Tabard"] = Vector3(0.6 + 0.1 * sin(w), 0, 0)
			p["Pouch"] = Vector3(0.3, 0, 0)
	p["_hips_pos"] = Vector3(hips_x, hips_y, 0)
	return p

## Flexion du genou au cours du cycle : le tibia se replie pendant le balancier de la jambe.
func _knee(w: float, run: bool) -> float:
	var c := cos(w - 0.35)
	var k := maxf(0.0, c)
	return (0.12 + (1.45 if run else 0.62) * k * k) if k > 0.0 else (0.12 if not run else 0.2)

func _make_clip(clip: String) -> Animation:
	var a := Animation.new()
	var len: float = CLIPS[clip][1]
	a.length = len
	a.loop_mode = Animation.LOOP_LINEAR
	var names: Array = []
	for n in _pose(clip, 0.0):
		if n != "_hips_pos":
			names.append(n)
	var rot_tracks := {}
	for n in names:
		var ti := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(ti, NodePath(_node_path(n)))
		a.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
		rot_tracks[n] = ti
	var pos_t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pos_t, NodePath("Hips"))
	for k in range(KEYS + 1):
		var ph := float(k % KEYS) / float(KEYS)
		var t := len * float(k) / float(KEYS)
		var pose := _pose(clip, ph)
		for n in names:
			var r: Vector3 = pose[n]
			a.rotation_track_insert_key(rot_tracks[n], t, Quaternion.from_euler(r))
		a.position_track_insert_key(pos_t, t, pose["_hips_pos"])
	return a

## Chemin d'un pivot depuis la racine du modèle.
func _node_path(n: String) -> String:
	var parts_path: Array[String] = []
	var node: Node = parts[n]
	while node != self and node != null:
		parts_path.push_front(String(node.name))
		node = node.get_parent()
	return "/".join(parts_path)

# ---------------------------------------------------------------- pilotage

## Joue un clip (fondu enchaîné) ; `speed` = vitesse de lecture.
func play_clip(clip: String, speed := 1.0, blend := 0.18) -> void:
	if anim == null:
		return
	if clip != _clip:
		anim.play(clip, blend)
		_clip = clip
	anim.speed_scale = speed

func current_clip() -> String:
	return _clip

## Fige le modèle à l'instant `t` d'un clip (captures, tests).
func pose_at(clip: String, t: float) -> void:
	if anim == null:
		return
	anim.play(clip)
	anim.seek(t, true)
	anim.pause()
	_clip = clip

## speed01 : 0 arrêt … 1 marche … 2 course ; grounded : au sol ; delta : pas de temps.
func animate(speed01: float, grounded: bool, _delta: float) -> void:
	if anim == null:
		return
	var s := clampf(speed01, 0.0, 2.4)
	if anim.is_playing() == false and _clip != "":
		anim.play(_clip)
	if not grounded:
		_fall_t += _delta
		if _fall_t > 0.08:                 # ignore les décollements d'une image (marches, pentes)
			play_clip("jump", 1.0, 0.12)
		return
	_fall_t = 0.0
	if s < 0.12:
		play_clip("idle", 1.0, 0.25)
	elif s < 1.5:
		play_clip("walk", clampf(s, 0.45, 1.5), 0.2)
	else:
		play_clip("run", clampf(s / 2.0, 0.8, 1.25), 0.2)
