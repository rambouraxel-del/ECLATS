@tool
class_name FarIslands
extends Node3D
## Silhouettes d'îles LOINTAINES autour de l'île jouable : petits maillages à faces plates (dessus vert,
## flancs et sous-face de roche en strates, quelques stalactites), générés par graine, estompés par la
## distance. Elles donnent l'échelle du monde et de la profondeur au ciel ; elles ne sont pas visitables
## (aucune collision) et ne coûtent que quelques centaines de triangles chacune.

const SHADER := preload("res://materials/far_island.gdshader")

var seed := 1
var count := 9
var dist_range := Vector2(120.0, 330.0)
var radius_range := Vector2(7.0, 19.0)
var height_range := Vector2(-30.0, 36.0)
var material: ShaderMaterial
var triangles := 0

func build(p_seed: int, cfg := {}) -> void:
	seed = p_seed
	for c in get_children():
		c.queue_free()
	count = int(cfg.get("count", count))
	dist_range = Vector2(cfg.get("distance", [dist_range.x, dist_range.y])[0], cfg.get("distance", [dist_range.x, dist_range.y])[1])
	radius_range = Vector2(cfg.get("radius", [radius_range.x, radius_range.y])[0], cfg.get("radius", [radius_range.x, radius_range.y])[1])
	height_range = Vector2(cfg.get("height", [height_range.x, height_range.y])[0], cfg.get("height", [height_range.x, height_range.y])[1])
	material = ShaderMaterial.new()
	material.shader = SHADER
	var rng := WorldRng.stream(seed, "far_islands")
	var angles: Array[float] = []
	var a0 := rng.randf() * TAU
	for i in count:
		# répartition en couronne avec un léger désordre : pas deux îles dans la même direction
		var a := a0 + TAU * float(i) / float(count) + rng.randf_range(-0.22, 0.22)
		angles.append(a)
		var d := rng.randf_range(dist_range.x, dist_range.y)
		var R := rng.randf_range(radius_range.x, radius_range.y) * (d / 200.0 + 0.5)
		var mi := MeshInstance3D.new()
		mi.name = "FarIsland%d" % i
		var mesh := _island_mesh(WorldRng.sub_seed(seed, "far%d" % i), R)
		mesh.surface_set_material(0, material)
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(a) * d, rng.randf_range(height_range.x, height_range.y), sin(a) * d)
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)

## Île polaire : N secteurs × M anneaux. Dessus bombé bruité, rebord, dessous en cône irrégulier.
func _island_mesh(sub_seed: int, R: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed
	var segs := 18
	var rings := 4
	var noise := FastNoiseLite.new()
	noise.seed = sub_seed
	noise.frequency = 0.9
	var h2 := rng.randf_range(0.08, 0.22)
	var h3 := rng.randf_range(0.04, 0.12)
	var p2 := rng.randf() * TAU
	var p3 := rng.randf() * TAU
	var top_h := R * rng.randf_range(0.14, 0.3)
	var depth := R * rng.randf_range(0.8, 1.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass_a := Color(0.36, 0.52, 0.30)
	var grass_b := Color(0.46, 0.60, 0.33)
	var rock_a := Color(0.45, 0.38, 0.33)
	var rock_b := Color(0.33, 0.29, 0.30)
	var top: Array = []     # [ring][seg] Vector3
	var bot: Array = []
	for r in range(rings + 1):
		var rho := float(r) / float(rings)
		var trow: Array[Vector3] = []
		var brow: Array[Vector3] = []
		for s in range(segs):
			var th := TAU * float(s) / float(segs)
			var rad := R * (1.0 + h2 * sin(2.0 * th + p2) + h3 * sin(3.0 * th + p3) + 0.05 * noise.get_noise_2d(th * 3.0, 4.0))
			var x := cos(th) * rad * rho
			var z := sin(th) * rad * rho
			var ty := top_h * (1.0 - pow(rho, 2.0)) + noise.get_noise_2d(x * 0.35, z * 0.35) * top_h * 0.3 * (1.0 - rho * 0.5)
			var by := -depth * (1.0 - pow(rho, 1.15)) * (1.0 + 0.3 * noise.get_noise_2d(x * 0.5 + 40.0, z * 0.5)) - R * 0.12 * float(rho >= 0.99)
			trow.append(Vector3(x, ty, z))
			brow.append(Vector3(x, by - (1.0 if r == rings else 0.0) * 0.0, z))
		top.append(trow)
		bot.append(brow)
	# dessus
	for r in range(rings):
		for s in range(segs):
			var s2 := (s + 1) % segs
			var a: Vector3 = top[r][s]
			var b: Vector3 = top[r][s2]
			var c: Vector3 = top[r + 1][s2]
			var d: Vector3 = top[r + 1][s]
			var col := grass_a.lerp(grass_b, 0.5 + 0.5 * noise.get_noise_2d(a.x * 0.4, a.z * 0.4))
			_tri(st, a, c, b, col)
			_tri(st, a, d, c, col)
	# flanc et dessous : du rebord (anneau extérieur du dessus) vers le fond (anneau 0 du dessous)
	for r in range(rings):
		for s in range(segs):
			var s2 := (s + 1) % segs
			var a: Vector3 = bot[r][s]
			var b: Vector3 = bot[r][s2]
			var c: Vector3 = bot[r + 1][s2]
			var d: Vector3 = bot[r + 1][s]
			var t := float(r) / float(rings)
			var col := rock_b.lerp(rock_a, t * 0.9 + 0.1 * noise.get_noise_2d(a.x * 0.3, a.y * 0.3))
			_tri(st, a, b, c, col)
			_tri(st, a, c, d, col)
	# bande de rebord entre le dessus et le dessous
	for s in range(segs):
		var s2 := (s + 1) % segs
		var a: Vector3 = top[rings][s]
		var b: Vector3 = top[rings][s2]
		var c: Vector3 = bot[rings][s2]
		var d: Vector3 = bot[rings][s]
		var col := rock_a.lerp(grass_a, 0.25)
		_tri(st, a, b, c, col)
		_tri(st, a, c, d, col)
	st.generate_normals()
	var mesh := st.commit()
	triangles += segs * rings * 4 + segs * 2
	return mesh

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)

func set_look(fog_color: Color, sun_dir: Vector3, sun_color: Color, ambient: Color, fog_end := 380.0) -> void:
	if material == null:
		return
	material.set_shader_parameter("fog_color", fog_color)
	material.set_shader_parameter("sun_dir", sun_dir)
	material.set_shader_parameter("sun_color", sun_color)
	material.set_shader_parameter("ambient", ambient)
	material.set_shader_parameter("fog_end", fog_end)
