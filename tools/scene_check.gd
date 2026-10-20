extends SceneTree
## Charge la scène « île générée » (F9), attend la fin de la génération (fil d'exécution), vérifie qu'elle est
## complète et sauvegarde une capture :
##   godot --rendering-driver opengl3 -s tools/scene_check.gd -- res://scenes/world/settled_island.tscn sortie.png
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var inst: Node = (load(args[0]) as PackedScene).instantiate()
	root.add_child(inst)
	var waited := 0
	await process_frame
	while (inst.get("world") == null or inst.get("_building")) and waited < 6000:
		await process_frame
		waited += 1
	var w: WorldData = inst.get("world")
	if w == null:
		printerr("ÉCHEC : l'île n'a pas été générée")
		quit(1)
		return
	print("île générée : %d bâtiments, %d arbres, %d rochers ; nœuds MeshInstance3D : %d" % [w.buildings.size(), w.trees.size(), w.rocks.size(), inst.find_children("*", "MeshInstance3D", true, false).size()])
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[1])
	print("saved ", args[1])
	quit()
