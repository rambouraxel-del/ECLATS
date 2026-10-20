extends Node3D
## Scène « Première île » : île principale + îlots lointains.
##   N / B : graine suivante / précédente (régénère l'île principale)
##   K : afficher / masquer la couche superficielle (révèle le cœur fixe)

@onready var island: VoxelIsland = $Island

func _ready() -> void:
	island.generated.connect(func(_d: IslandData) -> void: _update_help())
	_update_help()

func _update_help() -> void:
	App.set_scene_help("Île : seed %d (N/B pour changer) · K couche modifiable %s · généré en %d ms" % [
		island.seed, "visible" if island.surface_visible else "masquée (cœur seul)", island.last_generation_ms])

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_N:
			island.seed += 1
		KEY_B:
			island.seed -= 1
		KEY_K:
			island.surface_visible = not island.surface_visible
			_update_help()
