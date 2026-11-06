class_name ExplorerModel
extends Node3D
## Explorateur PROVISOIRE (Lot 5) : silhouette voxel de 1,72 m en cellules de 4 cm, cape bleu ardoise.
## Membres sur pivots (hanches, épaules, cape) : marche, course et chute animées par code, sans squelette.
## Repère : pieds en y = 0, regard vers -z.

const G := 0.04

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _cape: Node3D
var _phase := 0.0
var _cape_angle := 0.12

func _ready() -> void:
	_build()

## Pièce voxel : `fill(b)` dessine dans un VoxelModelBuilder ; `pivot` = point d'attache (m, repère du parent) ;
## `anchor` = position (cellules) du pivot dans la pièce.
func _part(parent: Node3D, size: Vector3i, anchor: Vector3, pivot: Vector3, fill: Callable, pname: String) -> Node3D:
	var b := VoxelModelBuilder.new(size)
	fill.call(b)
	var pv := Node3D.new()
	pv.name = pname
	pv.position = pivot
	parent.add_child(pv)
	var mesh := VoxelMesher.build(b.volume, G, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	if mesh != null:
		mesh.surface_set_material(0, VoxelMaterials.props_material())
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = -anchor * G
		pv.add_child(mi)
	return pv

func _build() -> void:
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0, 0.88, 0)
	add_child(_hips)
	# jambes : pantalon brun, bottes de cuir (pivot à la hanche)
	for side in [-1, 1]:
		var leg := _part(_hips, Vector3i(4, 22, 4), Vector3(2, 22, 2), Vector3(0.09 * side, 0.0, 0.0), func(b: VoxelModelBuilder) -> void:
			b.box(0, 7, 0, 3, 21, 3, "cloth_brown")
			b.box(0, 0, 0, 3, 7, 3, "leather")
			b.box(0, 0, -1 + 1, 3, 1, 3, "wood_aged_dark")
			b.box(0, 0, 0, 3, 0, 0, "wood_aged_dark"), "Leg")
		if side < 0:
			_leg_l = leg
		else:
			_leg_r = leg
	# torse : tunique de lin, gilet de cuir, ceinture
	_torso = _part(_hips, Vector3i(10, 14, 6), Vector3(5, 0, 3), Vector3(0, 0.0, 0), func(b: VoxelModelBuilder) -> void:
		b.box(0, 0, 0, 9, 13, 5, "cloth_linen")
		b.box(0, 3, 0, 9, 12, 0, "leather")
		b.box(0, 3, 5, 9, 12, 5, "leather")
		b.box(0, 1, 0, 9, 2, 5, "wood_aged_dark")
		b.box(4, 1, 0, 5, 2, 0, "brass")
		b.box(3, 12, 0, 6, 13, 0, "cloth_slate_dark"), "Torso")
	# tête : visage, cheveux, capuche rabattue sur la nuque
	_head = _part(_torso, Vector3i(7, 8, 7), Vector3(3.5, 0, 3.5), Vector3(0, 14 * G, 0), func(b: VoxelModelBuilder) -> void:
		b.box(1, 0, 1, 5, 5, 5, "skin")
		b.box(1, 5, 1, 5, 6, 5, "wood_aged_dark")
		b.box(1, 3, 5, 5, 5, 5, "wood_aged_dark")
		b.set_cell(2, 3, 1, "iron_dark")
		b.set_cell(4, 3, 1, "iron_dark")
		# capuche rabattue : un col épais sur la nuque, les cheveux restent visibles
		b.box(0, 0, 4, 6, 2, 6, "cloth_slate")
		b.box(1, 3, 5, 5, 3, 6, "cloth_slate")
		b.box(0, 0, 3, 0, 1, 4, "cloth_slate")
		b.box(6, 0, 3, 6, 1, 4, "cloth_slate"), "Head")
	# bras : manches de lin, brassards de cuir, mains (pivot à l'épaule)
	for side in [-1, 1]:
		var arm := _part(_torso, Vector3i(3, 14, 3), Vector3(1.5, 14, 1.5), Vector3(0.25 * side, 13 * G, 0), func(b: VoxelModelBuilder) -> void:
			b.box(0, 5, 0, 2, 13, 2, "cloth_linen")
			b.box(0, 2, 0, 2, 5, 2, "leather")
			b.box(0, 0, 0, 2, 1, 2, "skin"), "Arm")
		if side < 0:
			_arm_l = arm
		else:
			_arm_r = arm
	# cape bleu ardoise : col sur les épaules, pan qui descend aux mollets (pivot en haut du dos)
	_cape = _part(_torso, Vector3i(14, 24, 3), Vector3(7, 24, 0), Vector3(0, 13.5 * G, 3 * G + 0.01), func(b: VoxelModelBuilder) -> void:
		for y in 24:
			var half := 5 + int(float(23 - y) / 23.0 * 0.0) + (1 if y < 18 else 0) + (1 if y < 8 else 0)
			var x0 := 7 - half
			var x1 := 6 + half
			b.box(x0, y, 1, x1, y, 1, "cloth_slate")
			b.box(x0 + 1, y, 0, x1 - 1, y, 0, "cloth_slate_dark")
		b.box(1, 21, 0, 12, 23, 2, "cloth_slate")
		b.box(5, 21, 2, 8, 22, 2, "brass"), "Cape")

## speed01 : 0 arrêt … 1 marche … 2 course ; grounded : au sol ; delta : pas de temps.
func animate(speed01: float, grounded: bool, delta: float) -> void:
	if _hips == null:
		return
	var s := clampf(speed01, 0.0, 2.2)
	_phase += delta * (4.2 + 2.6 * s) * (1.0 if s > 0.05 else 0.0)
	var amp := clampf(s, 0.0, 1.4) * 0.5
	var sw := sin(_phase)
	if not grounded:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -0.35, 0.15)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.25, 0.15)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.9, 0.12)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.9, 0.12)
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, sw * amp, 0.35)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -sw * amp, 0.35)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -sw * amp * 0.8, 0.35)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, sw * amp * 0.8, 0.35)
	_hips.position.y = 0.88 + (absf(cos(_phase)) * 0.035 * clampf(s, 0.0, 1.5) if grounded else 0.0)
	_torso.rotation.x = lerpf(_torso.rotation.x, -0.05 * clampf(s - 0.6, 0.0, 1.4), 0.1)
	# la cape s'écarte du dos avec la vitesse et ondule un peu
	var target := 0.08 + 0.22 * clampf(s, 0.0, 2.0) + sin(_phase * 0.5) * 0.04 * s + (0.5 if not grounded else 0.0)
	_cape_angle = lerpf(_cape_angle, target, 0.08)
	_cape.rotation.x = -_cape_angle
