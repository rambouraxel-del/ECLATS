shader_type sky;
// Ciel d'ÉCLATS : dégradé chaud, soleil/lune, étoiles, mer de nuages sous l'horizon et nuages
// d'altitude. Les nuages sont des BLOCS DE PIXELS plats (grille angulaire grossière), dans l'esprit
// voxel du jeu : aucune texture, une seule couleur par bloc, trois niveaux de lumière.
uniform vec3 sky_top : source_color = vec3(0.36, 0.56, 0.84);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.87, 0.94);
uniform vec3 ground_horizon : source_color = vec3(0.86, 0.89, 0.93);
uniform vec3 ground_bottom : source_color = vec3(0.62, 0.70, 0.82);
uniform vec3 sun_dir = vec3(0.4, 0.7, 0.3);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size : hint_range(0.005, 0.1) = 0.028;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.7;
uniform vec3 moon_dir = vec3(-0.4, 0.6, -0.5);
uniform float moon_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.72, 0.78, 0.88);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_block : hint_range(10.0, 80.0) = 34.0;
uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
uniform float sea_cover : hint_range(0.0, 1.0) = 0.5;

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

float fbm2(vec2 p) {
	return 0.55 * vn(p) + 0.3 * vn(p * 2.1 + 7.0) + 0.15 * vn(p * 4.3 + 3.0);
}

// Nuages en blocs : valeur plate par cellule, trois tons selon la lumière du soleil.
vec4 cloud_layer(vec2 uv, vec2 sun2, float cover, float block) {
	vec2 cell = floor(uv * block);
	vec2 c = (cell + 0.5) / block;
	float d = fbm2(c * 1.6 + vec2(3.0, 9.0));
	float dens = smoothstep(1.0 - cover, 1.0 - cover + 0.16, d);
	float d2 = fbm2((c + sun2 * (1.2 / block)) * 1.6 + vec2(3.0, 9.0));
	float lit = clamp(0.5 + (d - d2) * 9.0, 0.0, 1.0);
	float tone = floor(lit * 2.99) / 2.0;
	vec3 col = mix(cloud_shadow, cloud_light, tone);
	return vec4(col, dens);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(sky_horizon, sky_top, pow(clamp(up, 0.0, 1.0), 0.5));
		// Halo du soleil.
		float sd = dot(dir, normalize(sun_dir));
		col += sun_color * sun_glow * pow(max(sd, 0.0), 14.0) * 0.55;
		col += sun_color * sun_glow * pow(max(sd, 0.0), 220.0) * 0.8;
		float disc = step(cos(sun_size), sd);
		col = mix(col, sun_color * 3.0, disc);
		// Lune.
		float md = dot(dir, normalize(moon_dir));
		col = mix(col, vec3(0.9, 0.93, 1.0) * 1.4, step(cos(0.032), md) * moon_amount);
		col += vec3(0.5, 0.6, 0.9) * pow(max(md, 0.0), 40.0) * 0.25 * moon_amount;
		// Étoiles : petits blocs de pixels.
		vec2 sp = floor(dir.xz / (abs(up) + 0.35) * 70.0);
		float s = h2(sp);
		float star = step(0.985, s) * smoothstep(0.02, 0.3, up) * star_amount;
		col += vec3(0.9, 0.92, 1.0) * star * (0.6 + 0.8 * h2(sp + 5.0));
		// Nuages d'altitude.
		vec2 uv = dir.xz / (up + 0.18);
		vec2 sun2 = normalize(sun_dir.xz + vec2(0.001));
		vec4 cl = cloud_layer(uv * 0.6, sun2, cloud_cover, cloud_block);
		float fade = smoothstep(0.0, 0.22, up);
		col = mix(col, cl.rgb, cl.a * fade * 0.95);
	} else {
		float t = clamp(-up, 0.0, 1.0);
		col = mix(ground_horizon, ground_bottom, pow(t, 0.45));
		// Mer de nuages : plaque de blocs à l'infini, plus claire au loin.
		vec2 uv = dir.xz / (-up + 0.05);
		vec2 sun2 = normalize(sun_dir.xz + vec2(0.001));
		vec4 cl = cloud_layer(uv * 0.2, sun2, sea_cover, cloud_block * 1.25);
		col = mix(col, cl.rgb, cl.a * smoothstep(0.0, 0.14, t) * 0.9);
	}
	COLOR = col;
}
