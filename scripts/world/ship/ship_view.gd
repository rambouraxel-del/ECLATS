@tool
class_name ShipView
extends RefCounted
## Bateau (ShipGenerator.build) → nœuds : coque/mâts/vergues (10 cm), voiles (tissu, 2 cm), haubans (2 cm),
## lumières. Chaque voile est un nœud séparé (jamais fusionnée avec une autre).

static func parts(ship: Dictionary) -> Array:
	var out: Array = []
	out.append({"name": "hull", "volume": ship["volume"], "origin": ship["origin"], "grid": ship["grid"], "material": "props"})
	var i := 0
	for s in ship["sails"]:
		out.append({"name": "sail%d" % i, "volume": s["volume"], "origin": s["origin"], "grid": s["grid"], "material": "cloth"})
		i += 1
	i = 0
	for r in ship["ropes"]:
		var k := ShipGenerator.rope_kit(r["a"], r["b"], r["sag"])
		out.append({"name": "rope%d" % i, "volume": k["volume"], "origin": k["origin"], "grid": k["grid"], "material": "props"})
		i += 1
	return out

static func create_node(ship: Dictionary) -> Node3D:
	# parties et maillages précalculés par WorldBuilder (fil d'exécution) ; sinon calculés ici
	var p: Array = ship["parts"] if ship.has("parts") else parts(ship)
	var arrays: Array = ship["arrays"] if ship.has("arrays") else VoxelObjectView.make_arrays(p)
	var node := VoxelObjectView.create_node("Ship", p, arrays, [45.0, 120.0], true)
	for l in ship["lights"]:
		var light := OmniLight3D.new()
		light.position = l["pos"]
		light.light_color = l["color"]
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.add_to_group("asset_lamps")
		light.set_meta("interior", l["interior"])
		node.add_child(light)
	return node
