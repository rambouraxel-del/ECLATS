@tool
class_name VoxelClouds
extends Node3D
## Nuages en voxels autour de l'île : cumulus à fond plat, formés de sphères fondues, maillés par
## le mailleur glouton (quelques centaines de triangles chacun) et peints par cloud.gdshader.
## Anneau proche sous l'île (points de vue sur les nuages), grands cumulus à l'horizon.
## Déterministe (graine) ; couleurs pilotées par LightingRig (groupe « lighting_rig »).

@export var seed := 11
@export var puff_count := 16
@export var ring_inner := 38.0
@export var ring_outer := 110.0
@export var min_y := -46.0
@export var max_y := -8.0
## Nuages lointains, plus hauts, à l'horizon.
@export var horizon_count := 8

var triangles := 0
var _material: ShaderMaterial

func _ready() -> void:
	for c in get_children():
		c.queue_free()
	_material = load("res://materials/cloud_material.tres").duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var total := puff_count + horizon_count
	for i in total:
		var far := i >= puff_count
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(ring_inner, ring_outer) if not far else rng.randf_range(170.0, 260.0)
		var cell := rng.randf_range(0.9, 1.5) if not far else rng.randf_range(3.0, 4.5)
		var size := Vector3i(rng.randi_range(18, 30), rng.randi_range(8, 12), rng.randi_range(14, 24))
		var mesh := _puff(rng, size, cell)
		if mesh == null:
			continue
		triangles += VoxelMesher.triangle_count(mesh)
		var mi := MeshInstance3D.new()
		mi.name = "Cloud%d" % i
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var y := rng.randf_range(min_y, max_y) if not far else rng.randf_range(-30.0, 18.0)
		mi.position = Vector3(cos(ang) * dist, y, sin(ang) * dist) - Vector3(size) * cell * 0.5 * Vector3(1, 0, 1)
		add_child(mi)
	var rig := get_tree().get_first_node_in_group("lighting_rig") as LightingRig if is_inside_tree() else null
	if rig:
		rig.cloud_materials.append(_material)
		rig.apply_preset(rig.current_index)

func _puff(rng: RandomNumberGenerator, size: Vector3i, cell: float) -> ArrayMesh:
	var vol := VoxelVolume.new(size)
	var pal := VoxelPalette.get_default()
	var white := pal.id("cloud_white")
	var dim := pal.id("cloud_dim")
	var balls: Array[Vector4] = []
	var n := rng.randi_range(6, 10)
	for i in n:
		var t := float(i) / n
		balls.append(Vector4(
			size.x * (0.2 + 0.6 * t + rng.randf_range(-0.06, 0.06)),
			size.y * rng.randf_range(0.22, 0.5),
			size.z * rng.randf_range(0.3, 0.7),
			rng.randf_range(0.18, 0.3) * minf(size.x, size.z * 1.3)))
	for y in size.y:
		for z in size.z:
			for x in size.x:
				var f := 0.0
				for b in balls:
					var d := Vector3(x + 0.5 - b.x, (y + 0.5 - b.y) * 1.5, z + 0.5 - b.z).length()
					f += pow(maxf(1.0 - d / b.w, 0.0), 1.6)
				if y < 1:
					f *= 0.55     # fond presque plat
				if f > 0.42:
					vol.set_voxel(x, y, z, dim if VoxelGrid.hash01(x, y, z, 3) < 0.25 else white)
	var arrays := VoxelMesher.build_arrays(vol, cell, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.STYLIZED)
	if arrays.is_empty():
		return null
	var mesh := VoxelMesher.arrays_to_mesh(arrays, VoxelMesher.Style.STYLIZED)
	mesh.surface_set_material(0, _material)
	return mesh
