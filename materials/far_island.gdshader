shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Silhouette d'île lointaine : couleurs plates par sommet, éclairage simple (demi-Lambert), puis fondu vers
// la couleur de l'horizon avec la distance (perspective atmosphérique). Aucune texture.
uniform vec3 fog_color : source_color = vec3(0.77, 0.86, 0.93);
uniform vec3 sun_dir = vec3(0.4, 0.7, 0.3);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 ambient : source_color = vec3(0.5, 0.55, 0.65);
uniform float fog_start = 60.0;
uniform float fog_end = 380.0;
uniform float fog_max : hint_range(0.0, 1.0) = 0.85;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float l = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	vec3 col = COLOR.rgb * (ambient + sun_color * l * 0.75);
	float d = distance(wpos, CAMERA_POSITION_WORLD);
	float f = smoothstep(fog_start, fog_end, d) * fog_max;
	ALBEDO = mix(col, fog_color, f);
}
