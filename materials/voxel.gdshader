shader_type spatial;
// Shader commun à TOUS les voxels (terrain, blocs, meubles).
// Données fournies par VoxelMesher :
//   COLOR.rgb = couleur linéaire (AO incluse), UV.x = émission, UV.y = rugosité,
//   UV2 = position dans la face du voxel (0..1) pour le liseré des arêtes.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Assombrissement des arêtes de chaque voxel (lisibilité du relief).
uniform float edge_strength : hint_range(0.0, 1.0) = 0.16;
// Largeur du liseré, en fraction de face.
uniform float edge_width : hint_range(0.01, 0.5) = 0.09;
// Léger éclaircissement du sommet des faces (effet « biseau »).
uniform float bevel_light : hint_range(0.0, 0.5) = 0.06;
uniform float emission_multiplier : hint_range(0.0, 8.0) = 1.0;

void fragment() {
	vec2 f = UV2;
	vec2 d = min(f, vec2(1.0) - f);
	float e = min(d.x, d.y);
	// Le liseré s'efface quand le voxel devient trop petit à l'écran (évite le moiré).
	vec2 fw = fwidth(f);
	float px = max(fw.x, fw.y);
	float fade = 1.0 - smoothstep(0.06, 0.22, px);
	float edge = (1.0 - smoothstep(0.0, edge_width, e)) * fade;
	float bevel = smoothstep(edge_width, edge_width * 2.0, e) * (1.0 - smoothstep(0.3, 0.5, e)) * fade;
	vec3 col = COLOR.rgb * (1.0 - edge * edge_strength) * (1.0 + bevel * bevel_light);
	ALBEDO = col;
	ROUGHNESS = UV.y;
	SPECULAR = 0.35;
	EMISSION = COLOR.rgb * UV.x * emission_multiplier;
}
