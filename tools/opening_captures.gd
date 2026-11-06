extends SceneTree
## Captures du parcours de l'île d'ouverture (Lot 5), aux positions ENREGISTRÉES par la recette jouée
## (tools/opening_recette.gd), plus les états de l'Ancre et la chute :
##   godot --rendering-driver opengl3 --fixed-fps 60 -s tools/opening_captures.gd -- recette.json dossier [--relance]
## Sans --relance : la sauvegarde de l'île est d'abord oubliée (l'invite et l'activation sont visibles).
## Avec --relance : une seule capture près de l'Ancre, état rechargé depuis la sauvegarde.

var scene: Node
var ex: Explorer
var cam: ThirdPersonCamera
var out_dir := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var rec = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	out_dir = args[1]
	var relance := args.has("--relance")
	var map := IslandMap.load_map()
	if not relance:
		GameSave.clear_island(String(map["id"]))
	scene = (load("res://scenes/game/opening_island.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var t0 := Time.get_ticks_msec()
	while not bool(scene.get("ready_to_play")) and Time.get_ticks_msec() - t0 < 900000:
		await process_frame
		OS.delay_msec(5)
	ex = scene.get("explorer")
	cam = scene.get("camrig")
	var caps: Array = rec["captures"]
	var by_name := {}
	for c in caps:
		by_name[c["nom"]] = c
	if relance:
		var c: Dictionary = by_name.get("11_invite_ancre", caps.back())
		await _place(c)
		await _shot("14_apres_relance")
		quit()
		return
	for c in caps:
		if String(c["nom"]).begins_with("11_"):
			continue
		await _place(c)
		await _shot(String(c["nom"]))
	# invite, activation, après activation
	if by_name.has("11_invite_ancre"):
		await _place(by_name["11_invite_ancre"])
		await _shot("11_invite_ancre")
		scene.call("activate_anchor")
		for i in 34:
			await process_frame
		await _shot("12_activation_ancre")
		for i in 50:
			await process_frame
		scene.set("_banner_t", 3.6)
		for i in 40:
			await process_frame
		await _shot("13_ile_decouverte")
	# chute : en plein vol sous le bord des falaises, puis retour au quai
	var p1: Array = []
	for p in map["paths"]:
		if p["id"] == "sentier_des_falaises":
			p1 = p["pts"]
	var e := Vector2(float(p1[11][0]) - 9.0, float(p1[11][1]))
	ex.teleport(Vector3(e.x, float(scene.call("ground_y_at", e.x + 9.0, e.y)) + 1.0, e.y), PI * 0.5)
	cam.yaw = -PI * 0.5 + 0.6
	cam.pitch = -0.45
	cam.snap()
	for i in 24:
		await physics_frame
	await _shot("15_chute")
	var t := 0
	while int(scene.get("falls")) == 0 and t < 1200:
		await physics_frame
		t += 1
	for i in 10:
		await process_frame
	await _shot("16_retour_au_quai")
	quit()

func _place(c: Dictionary) -> void:
	var p := Vector3(float(c["pos"][0]), float(c["pos"][1]), float(c["pos"][2]))
	ex.teleport(p + Vector3(0, 0.05, 0), float(c["yaw"]))
	cam.yaw = float(c["yaw"])
	cam.pitch = float(c.get("pitch", -0.2))
	for i in 12:
		await physics_frame
	cam.interior = bool(scene.call("_is_interior", ex.global_position))
	cam.snap()
	for i in 6:
		await process_frame

func _shot(name: String) -> void:
	var path := "%s/%s.png" % [out_dir, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
