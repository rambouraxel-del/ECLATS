@tool
extends RefCounted
## Entrées du Lot 3 (nouveaux assets). [groupe, script, arguments]

const NATURE := "res://scripts/assets/nature/"

static func entries() -> Dictionary:
	var d := {}
	# --- Arbres : espèces × variantes ---
	for spec in [["oak", "Chêne", 3], ["parasol", "Arbre parasol", 2], ["pine", "Pin", 2],
			["weeping", "Saule pleureur", 2], ["birch", "Bouleau", 2], ["fruit", "Arbre fruitier", 2]]:
		for v in spec[2]:
			d["tree_%s_%d" % [spec[0], v + 1]] = ["tree", NATURE + "trees.gd", {"species": spec[0], "seed": v + 1, "name": "%s %d" % [spec[1], v + 1]}]
	# --- Objets de village et d'artisanat ---
	var props := "res://scripts/assets/props/"
	for id in ["water_well", "mooring_post", "balustrade", "large_planter", "canopy_kiosk", "utility_cart", "barrel_set", "shrine_marker", "crate_stack", "garden_fence", "vegetable_bed"]:
		d[id] = ["prop", props + "props_village.gd", {"id": id}]
	for id in ["crystal_lamp", "banner_stand", "signpost", "notice_board", "pedestal_fountain", "brazier"]:
		d[id] = ["prop", props + "props_decor.gd", {"id": id}]
	for id in ["forge", "tool_rack", "storage_rack", "supply_chest", "materials_crate"]:
		d[id] = ["prop", props + "props_craft.gd", {"id": id}]
	for id in ["teleport_anchor", "crystal_cluster", "ruin_column", "ruin_arch"]:
		d[id] = ["prop", props + "props_ancient.gd", {"id": id}]
	# --- Bâtiments ---
	for id in ["house_colonist", "house_cottage", "workshop", "warehouse", "watch_tower"]:
		d[id] = ["building", "res://scripts/assets/buildings/houses.gd", {"id": id}]
	for v in [[1, 14, true], [2, 20, false], [3, 10, true], [4, 26, true]]:
		d["boulder_%d" % v[0]] = ["tree", NATURE + "rocks.gd", {"seed": v[0], "size": v[1], "warm": v[2]}]
	for id in ["pier", "sky_ship"]:
		d[id] = ["building" if id == "pier" else "vehicle", "res://scripts/assets/buildings/port.gd", {"id": id}]
	return d
