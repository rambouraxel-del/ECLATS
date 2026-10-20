shader_type spatial;
// Sol neutre du laboratoire : grille fine 0,20 m (voxel) et grille 1 m.
render_mode diffuse_burley;

uniform vec3 base_color : source_color = vec3(0.66, 0.66, 0.67);
uniform vec3 line_color : source_color = vec3(0.55, 0.55, 0.56);
uniform vec3 major_color : source_color = vec3(0.42, 0.42, 0.44);
uniform float voxel_size = 0.2;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float cell, float width) {
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) * cell;
	vec2 fw = fwidth(p);
	vec2 l = 1.0 - smoothstep(vec2(0.0), fw * 1.5 + width, g);
	return max(l.x, l.y);
}

void fragment() {
	// Plan du sol : XZ ; murs : utiliser la coordonnée dominante.
	vec3 n = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 p = n.y > 0.5 ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	float minor = grid(p, voxel_size, 0.004);
	float major = grid(p, 1.0, 0.012);
	vec3 col = mix(base_color, line_color, minor * 0.6);
	col = mix(col, major_color, major);
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
