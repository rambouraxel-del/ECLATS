shader_type spatial;
// Prototype C (Voxel Tools) : matériau SIMPLIFIÉ pour les blocs du VoxelMesherBlocky.
// Données de sommet fournies par le mailleur : COLOR = couleur du modèle × occlusion, UV = 0..1 sur chaque face de voxel.
// Pas de motifs à 2 cm comme le shader d'ÉCLATS : une couleur plate par voxel de 20 cm, une nuance par voxel (hachage de la
// position monde) et le même liseré d'arête que l'ancien shader des voxels.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float edge_strength : hint_range(0.0, 1.0) = 0.16;
uniform float edge_width : hint_range(0.01, 0.5) = 0.09;
uniform float nuance : hint_range(0.0, 0.3) = 0.07;

varying vec3 v_wpos;
varying vec3 v_wnrm;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 f = UV;
	float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float edge = 1.0 - smoothstep(0.0, edge_width, e);
	vec3 cell = floor((v_wpos - v_wnrm * 0.05) / 0.2);
	float n = (h31(cell) - 0.5) * 2.0 * nuance;
	vec3 col = COLOR.rgb * (1.0 + n) * (1.0 - edge * edge_strength);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
