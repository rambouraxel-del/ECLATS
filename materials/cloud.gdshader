shader_type spatial;
// Nuages voxel : trois tons plats selon l'orientation par rapport au soleil (pas de dégradé, pas de
// texture), couleurs pilotées par l'ambiance (LightingRig). Non éclairés : toujours lisibles.
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 light_color : source_color = vec3(1.0);
uniform vec3 shade_color : source_color = vec3(0.7, 0.76, 0.86);
uniform vec3 sun_dir = vec3(0.4, 0.7, 0.3);

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float l = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	float tone = floor(clamp(l, 0.0, 0.999) * 3.0) / 2.0;
	vec3 col = mix(shade_color, light_color, tone);
	col *= COLOR.rgb;
	col *= mix(1.0, COLOR.a, 0.6);
	ALBEDO = col;
}
