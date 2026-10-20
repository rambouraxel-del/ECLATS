shader_type spatial;
// Shader voxel du Lot 2, partagé par le terrain ET les objets (cohérence des matières).
// Données fournies par VoxelMesher (style STYLIZED) :
//   COLOR.rgb = couleur linéaire de la matière, COLOR.a = occlusion ambiante du sommet,
//   UV = (émission, rugosité), UV2 = (style, métal).
// Styles (VoxelPalette.STYLES) : 0 défaut, 1 herbe, 2 terre, 3 pierre, 4 bois, 5 métal,
//   6 cristal, 7 tissu, 8 feuillage.
// Les nuances sont calculées en continu dans l'espace monde : pas de damier par cellule.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- Nuances par zones (quelques mètres) ---
uniform float zone_scale = 0.22;
uniform float zone_strength : hint_range(0.0, 0.5) = 0.13;
// --- Grain fin, très discret ---
uniform float grain_scale = 18.0;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.035;
// --- Herbe ---
// Facteur multiplicatif (linéaire) appliqué aux plaques d'herbe sèche.
uniform vec3 grass_dry_tint = vec3(1.25, 1.12, 0.62);
uniform float grass_dry_amount : hint_range(0.0, 1.0) = 0.35;
// Couleur LINÉAIRE de la terre sur les flancs des voxels d'herbe (= matière « dirt »).
uniform vec3 soil_color = vec3(0.235, 0.13, 0.072);
// Part du haut des flancs d'un voxel d'herbe qui reste verte (transition herbe/terre).
uniform float grass_side_cover : hint_range(0.0, 1.0) = 0.36;
uniform float terrain_voxel = 0.2;
// --- Occlusion ---
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
// --- Émission ---
uniform float emission_multiplier : hint_range(0.0, 8.0) = 1.0;
uniform float crystal_pulse : hint_range(0.0, 1.0) = 0.0;
// --- Balancement des tissus (0 = immobile). Le haut du maillage (y = 0) est fixe. ---
uniform float sway_strength = 0.0;
uniform float sway_range = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.07 + 5.3) + 0.15 * vnoise(p * 4.13 + 1.7);
}

void vertex() {
	if (sway_strength > 0.0) {
		float w = clamp(-VERTEX.y / sway_range, 0.0, 1.0);
		float t = TIME;
		VERTEX.x += sin(t * 1.1 + VERTEX.z * 1.9) * sway_strength * w;
		VERTEX.z += sin(t * 1.5 + VERTEX.x * 1.3) * sway_strength * 0.5 * w;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int style = int(UV2.x + 0.5);
	vec3 col = COLOR.rgb;
	float zone = fbm(wpos * zone_scale);
	float grain = vnoise(wpos * grain_scale) - 0.5;
	float grain_k = grain_strength;
	float emission_k = UV.x;
	col *= 1.0 + (zone - 0.5) * 2.0 * zone_strength;

	if (style == 1) {
		// Herbe : plaques plus sèches par zones, flancs qui passent à la terre.
		float dry = smoothstep(0.52, 0.78, fbm(wpos * zone_scale * 0.7 + vec3(3.1, 0.0, 7.7)));
		col = mix(col, col * grass_dry_tint, dry * grass_dry_amount);
		grain_k *= 0.7;
		if (abs(wnrm.y) < 0.5) {
			float h = fract(wpos.y / terrain_voxel + 0.001);
			float jag = vnoise(vec3(wpos.x * 31.0, wpos.y * 4.0, wpos.z * 31.0));
			float edge = 1.0 - grass_side_cover + (jag - 0.5) * 0.3;
			float g = smoothstep(edge - 0.03, edge + 0.03, h);
			vec3 soil = soil_color * (1.0 + (zone - 0.5) * 0.2);
			col = mix(soil, col * 0.92, g);
		}
	} else if (style == 2) {
		float layers = vnoise(vec3(wpos.x * 2.0, wpos.y * 11.0, wpos.z * 2.0));
		col *= 0.9 + layers * 0.18;
		grain_k *= 1.5;
	} else if (style == 3) {
		// Pierre : strates horizontales douces + mouchetis.
		float strata = vnoise(vec3(wpos.x * 1.3, wpos.y * 7.0, wpos.z * 1.3));
		col *= 0.94 + strata * 0.12;
		grain_k *= 1.6;
	} else if (style == 4) {
		// Bois : fibres fines étirées.
		float fib = vnoise(vec3(wpos.x * 4.0, wpos.y * 45.0, wpos.z * 45.0));
		col *= 0.95 + fib * 0.08;
	} else if (style == 6) {
		// Cristal : cœur lumineux renforcé sur les bords (Fresnel) + pulsation optionnelle.
		float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
		emission_k *= 0.75 + 0.6 * fres + crystal_pulse * 0.35 * sin(TIME * 2.2 + wpos.y * 3.0);
		grain_k = 0.0;
	} else if (style == 7) {
		// Tissu : trame très fine.
		float weave = sin(wpos.x * 260.0) * sin(wpos.z * 260.0 + wpos.y * 260.0);
		col *= 0.97 + weave * 0.03;
	} else if (style == 8) {
		float tint = fbm(wpos * 1.7 + 11.0);
		col *= 0.88 + tint * 0.24;
	}
	col *= 1.0 + grain * 2.0 * grain_k;
	float ao = mix(1.0, COLOR.a, ao_strength);
	ALBEDO = col * ao;
	ROUGHNESS = UV.y;
	METALLIC = UV2.y;
	SPECULAR = 0.4;
	EMISSION = COLOR.rgb * emission_k * emission_multiplier;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
}
