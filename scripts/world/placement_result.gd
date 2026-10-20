@tool
class_name PlacementResult
extends RefCounted
## Résultat d'une tentative de placement : valide, ou liste explicite des raisons du refus.
## Un résultat invalide n'est JAMAIS posé : l'appelant le corrige (nouvelle position), le régénère
## ou le rejette ; le système tient le compte des refus par raison pour le rapport de diagnostic.

var ok := false
var reasons := PackedStringArray()
var spec: PlacementSpec
var pos := Vector3.ZERO          # centre de l'emprise, au niveau de la base
var yaw := 0                     # quarts de tour
var rect := Rect2i()             # colonnes couvertes
var base_top := 0                # cellule du dessus du sol sous la base
var range_cells := 0             # écart de hauteur du sol sous l'emprise
var embed_cells := 0             # enfoncement dans la surface
var support := 0.0               # part de l'emprise qui touche le sol
var item_index := -1             # index dans OccupancyMap.items une fois posé
var access_cell := Vector2i(-1, -1)

func fail(reason: String) -> PlacementResult:
	ok = false
	if not reasons.has(reason):
		reasons.append(reason)
	return self

func basis() -> Basis:
	return Basis(Vector3.UP, yaw * PI * 0.5)

## Transform de l'asset (origine en coin d'emprise) correspondant à ce placement.
func asset_transform() -> Transform3D:
	return Transform3D(basis(), pos) * Transform3D(Basis.IDENTITY, -spec.origin_offset)

## Transform pour un nœud dont l'origine est le centre-bas de l'emprise.
func center_transform() -> Transform3D:
	return Transform3D(basis(), pos)

func describe() -> String:
	return "%s @ (%.1f, %.1f) yaw %d : %s" % [spec.id if spec else "?", pos.x, pos.z, yaw, "OK" if ok else ",".join(reasons)]
