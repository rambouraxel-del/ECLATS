@tool
class_name RoofBuilder
extends RefCounted
## Toitures à pente continue : le PROFIL est dessiné en microvoxels de 2 cm (marches de 2 cm, donc
## sans l'aspect « escalier de cubes » d'un toit à 10 cm), puis extrudé sur toute la longueur du faîtage
## par étirement d'un maillage d'une seule cellule. Coût : quelques centaines de triangles par pan.
## Les motifs de matière (tuiles, bardeaux, chaume) restent des pixels de 2 cm.

const PIX := VoxelGrid.DETAIL_SIZE

## Maillage d'une section de toit : `bottom`/`top` = hauteurs (microvoxels de 2 cm) par colonne de la
## portée. length_m : longueur le long du faîtage. ridge_axis : 0 = faîtage le long de x, 2 = le long de z.
## Renvoie {arrays, size_m (Vector3), } ; la portée est le long de l'autre axe horizontal.
static func extrude(bottom: PackedInt32Array, top: PackedInt32Array, length_m: float, ridge_axis: int, material_key: String) -> Dictionary:
	var span := top.size()
	var h := 0
	for i in span:
		h = maxi(h, top[i] + 1)
	var pal := VoxelPalette.get_default()
	var id := pal.id(material_key)
	var size := Vector3i(1, h, span) if ridge_axis == 0 else Vector3i(span, h, 1)
	var vol := VoxelVolume.new(size)
	for i in span:
		for y in range(maxi(bottom[i], 0), top[i] + 1):
			if ridge_axis == 0:
				vol.set_voxel(0, y, i, id)
			else:
				vol.set_voxel(i, y, 0, id)
	var arrays := VoxelMesher.build_arrays(vol, PIX, Vector3i.ZERO, Vector3i(-1, -1, -1), PackedByteArray(), Vector3i.ZERO, 0, VoxelMesher.Style.DETAIL)
	arrays = VoxelMesher.stretch_axis(arrays, ridge_axis, length_m / PIX, PIX)
	return {"arrays": arrays, "span": span, "height": h, "material": material_key}

## Profil à deux pans symétriques. Unités : cellules de 10 cm.
##   half_cells : demi-portée mesurée aux faces extérieures des murs (le faîtage est au centre)
##   overhang   : débord de chaque côté (cellules) ; eave_y : hauteur de la sous-face aux murs (cellules)
##   pitch      : [montée, course] ; thick : épaisseur verticale du toit (cellules)
## Renvoie {bottom, top (microvoxels de 2 cm, origine = eave_y - drop), origin_y_cells, fn(z_cells) → sous-face}.
static func gable_profile(half_cells: float, overhang: int, eave_y: int, pitch: Array, thick: int) -> Dictionary:
	var num := float(pitch[0])
	var den := float(pitch[1])
	var total_cells := 2.0 * (half_cells + overhang)
	var span := int(round(total_cells * 5.0))
	var drop := int(ceil(overhang * num / den)) + 1     # le bord bas descend sous les murs
	var bottom := PackedInt32Array()
	var top := PackedInt32Array()
	bottom.resize(span)
	top.resize(span)
	var y0 := float(eave_y - drop)
	for i in span:
		var z := (float(i) + 0.5) / 5.0 - (half_cells + overhang)       # cellules depuis le faîtage, de -(H+ov) à +(H+ov)
		var under := float(eave_y) + (half_cells - absf(z)) * num / den - y0
		bottom[i] = int(floor(under * 5.0))
		top[i] = int(floor((under + float(thick)) * 5.0))
	return {"bottom": bottom, "top": top, "origin_y": y0, "span_cells": total_cells, "start": -(half_cells + overhang)}

## Profil à un pan (appentis) : monte de `low_y` (bord bas) à `high_y` (contre le mur) sur `run_cells`.
static func shed_profile(run_cells: float, overhang: int, low_y: int, high_y: int, thick: int) -> Dictionary:
	var total := run_cells + overhang
	var span := int(round(total * 5.0))
	var y0 := float(low_y - 2)
	var bottom := PackedInt32Array()
	var top := PackedInt32Array()
	bottom.resize(span)
	top.resize(span)
	for i in span:
		# i = 0 côté bas (extérieur, débord compris), i = span-1 contre le mur principal
		var t := (float(i) + 0.5) / 5.0
		var u := clampf((t - overhang) / run_cells, 0.0, 1.2)
		var under := float(low_y) + (float(high_y) - float(low_y)) * (1.0 - (1.0 - u)) - y0
		under = float(low_y) + (float(high_y - low_y)) * u - y0
		bottom[i] = int(floor(under * 5.0))
		top[i] = int(floor((under + float(thick)) * 5.0))
	return {"bottom": bottom, "top": top, "origin_y": y0, "span_cells": total}
