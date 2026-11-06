extends SceneTree
## Écrit la maison d'exemple dans assets/maisons/ : godot --headless -s tools/lot8_maison_exemple.gd
func _initialize() -> void:
	var c := ConstructionOps.demo_house()
	var r := Construction.save_file(c, "res://assets/maisons/maison_exemple.eclats-maison.json")
	print(r, " ", c.summary())
	quit()
