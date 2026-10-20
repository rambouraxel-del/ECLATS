shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// Nappe de nuages DOUCE (non voxel) : bruit fractal continu en coordonnées monde, bords fondus, lumière du
// soleil lue dans le gradient du bruit (face éclairée plus claire), disparition progressive près de la
// caméra et au loin. Aucune texture : tout est calculé ici.
uniform vec3 light_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade_color : source_color = vec3(0.72, 0.78, 0.88);
uniform vec3 sun_dir = vec3(0.4, 0.7, 0.3);
uniform float cover : hint_range(0.0, 1.0) = 0.5;
uniform float softness : hint_range(0.05, 0.6) = 0.28;
uniform float scale : hint_range(0.002, 0.2) = 0.02;
uniform vec2 stretch = vec2(1.0, 1.0);
uniform vec2 wind = vec2(0.6, 0.2);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float fade_near = 8.0;
uniform float fade_far = 520.0;
uniform float seed = 0.0;
uniform float brightness : hint_range(0.3, 1.0) = 0.74;

varying vec3 wpos;

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	return 0.5 * vn(p) + 0.27 * vn(p * 2.03 + 7.0) + 0.14 * vn(p * 4.1 + 3.0) + 0.09 * vn(p * 8.3 + 1.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz * stretch + wind * TIME * 0.4 + vec2(seed * 31.0, seed * 17.0)) * scale;
	float d = fbm(uv);
	float dens = smoothstep(1.0 - cover, 1.0 - cover + softness, d);
	// éclairage : le gradient du bruit vers le soleil éclaire les bords ; le cœur est plus sombre
	vec2 sun2 = normalize(sun_dir.xz + vec2(0.001));
	float d2 = fbm(uv + sun2 * 0.07);
	float lit = clamp(brightness + (d - d2) * 6.0, 0.0, 1.0);
	lit = mix(lit, 1.0, smoothstep(0.55, 1.0, d) * 0.15);
	vec3 col = mix(shade_color, light_color, lit);
	float dist = distance(wpos, CAMERA_POSITION_WORLD);
	float fade = smoothstep(fade_near, fade_near * 2.2, dist) * (1.0 - smoothstep(fade_far * 0.55, fade_far, dist));
	ALBEDO = col;
	ALPHA = dens * opacity * fade;
}
