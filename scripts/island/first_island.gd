extends Node3D
## Scène « Première île » : île principale + îlots lointains.
##   N / B : graine suivante / précédente (régénère l'île principale)
##   K : afficher / masquer la couche superficielle (révèle le cœur fixe)
##   V : comparer le rendu du terrain Lot 1 / Lot 2

@onready var island: VoxelIsland = $Island

func _ready() -> void:
	island.generated.connect(func(_d: IslandData) -> void: _update_help())
	_update_help()

func _update_help() -> void:
	App.set_scene_help("Île : seed %d (N/B) · K couche modifiable %s · V rendu %s · généré en %d ms" % [
		island.seed, "visible" if island.surface_visible else "masquée (cœur seul)",
		"Lot 2 (stylisé)" if island.render_style == VoxelMesher.Style.STYLIZED else "Lot 1 (ancien)",
		island.last_generation_ms])

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_N:
			island.seed += 1
		KEY_B:
			island.seed -= 1
		KEY_V:
			var legacy := island.render_style == VoxelMesher.Style.STYLIZED
			var style := VoxelMesher.Style.LEGACY if legacy else VoxelMesher.Style.STYLIZED
			for node in get_children():
				if node is VoxelIsland:
					node.render_style = style
			_update_help()
		KEY_K:
			island.surface_visible = not island.surface_visible
			_update_help()
