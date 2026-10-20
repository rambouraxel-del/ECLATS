shader_type spatial;
// Shader voxel unique d'ÉCLATS (Lot 3) : terrain, objets et bâtiments.
//
// RÈGLE : aucune texture image, aucun détail plus fin que le pixel. Toute la surface est découpée
// en PIXELS DE 2 cm (grille alignée sur les voxels de 2, 10 et 20 cm) ; chaque pixel a UNE SEULE
// couleur plate, nuancée par rapport à ses voisins (bois veiné, pierre mouchetée, pavés...).
// Les motifs sont calculés par des fonctions de hachage entières, sans texture externe.
// À grande distance, les variations de pixel s'estompent vers la teinte moyenne (pas de scintillement).
//
// Données de sommet (VoxelMesher) :
//   COLOR = couleur linéaire + occlusion (a) · UV = (émission, rugosité)
//   UV2 = (style + usure·0.98, métal) · CUSTOM0 = (u, v, largeur, hauteur) du quad en m
//   CUSTOM1 = (épaisseur derrière la face, graine du quad, sens du grain)   [objets seulement]
// Styles (VoxelPalette.STYLES) : 0 défaut 1 herbe 2 terre 3 pierre taillée 4 bois 5 métal
//   6 cristal 7 tissu 8 feuillage 9 appareil de pierre 10 enduit 11 tuiles 12 pavés
//   13 roche 14 écorce 15 gravier 16 bardeaux 17 lampe 18 eau
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Active les données de quad (objets / bâtiments). Faux pour le terrain.
uniform bool use_quad_data = false;
// Force des nuances de pixels (0 = couleur unie du Lot 2, 1 = normal, 2 = marqué).
uniform float tex_strength : hint_range(0.0, 2.0) = 1.0;
// Nuances par grandes zones (terrain).
uniform float zone_strength : hint_range(0.0, 0.5) = 0.12;
// Herbe : plaques sèches, flancs qui passent à la terre.
uniform vec3 grass_dry_tint = vec3(1.25, 1.1, 0.62);
uniform float grass_side_cover : hint_range(0.0, 1.0) = 0.36;
// Couleur LINÉAIRE de la terre sur les flancs des voxels d'herbe.
uniform vec3 soil_color = vec3(0.235, 0.13, 0.072);
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float emission_multiplier : hint_range(0.0, 8.0) = 1.0;
// Intensité des verres de lanterne / fenêtres (jour faible, nuit forte).
uniform float lamp_emission : hint_range(0.0, 4.0) = 0.35;
uniform float crystal_pulse : hint_range(0.0, 1.0) = 0.0;
// Balancement des tissus (0 = immobile). Le haut du maillage (y = 0) est fixe.
uniform float sway_strength = 0.0;
uniform float sway_range = 1.0;

const float PIX = 0.02;

varying vec3 v_lpos;
varying vec3 v_lnrm;
varying vec2 v_quv;
varying flat vec2 v_qsize;
varying flat vec3 v_q2;

struct Ctx {
	vec2 pc;       // pixel (entier) dans le plan de la face
	vec2 gp;       // pixel aligné sur le grain : x le long des fibres, y en travers
	vec2 wp;       // pixel de mur : (horizontale, verticale)
	float layer;   // couche (profondeur de la face) : fait varier les motifs d'une face à l'autre
	float edge_px; // distance au bord du quad, en pixels (0 = pixel de bord)
	vec2 qpx;      // position dans le quad, en pixels
	vec2 qsz;      // taille du quad, en pixels
	float depth;
	float seed;
	float wear;
	float ao;
	float up;      // 1 dessus, 0 flanc, -1 dessous
	float grain;   // 0 le long de u, 1 le long de v, 2 bois de bout, 3 inconnu
	float amp;     // amplitude des nuances de pixel (estompée avec la distance)
	float ampz;    // amplitude des grandes zones
	float py;      // hauteur locale (m)
};

// ---------------------------------------------------------------- hachage entier

uint pcg(uint v) {
	uint state = v * 747796405u + 2891336653u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

float rnd2(vec2 ip, float s) {
	ivec2 i = ivec2(floor(ip));
	uint h = pcg(uint(i.x) + pcg(uint(i.y) + pcg(uint(int(s * 64.0)))));
	return float(h >> 8u) / 16777216.0;
}

float rnd1(float i, float s) {
	return rnd2(vec2(i, 0.37), s);
}

float hash11(float x) {
	return rnd2(vec2(floor(x * 4096.0), 1.0), 3.0);
}

// Bruit de valeur sur réseau de L pixels, évalué au CENTRE du pixel (résultat plat par pixel).
float vnoise(vec2 pc, float L, float s) {
	vec2 q = (pc + 0.5) / L;
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	float a = rnd2(i, s);
	float b = rnd2(i + vec2(1.0, 0.0), s);
	float c = rnd2(i + vec2(0.0, 1.0), s);
	float d = rnd2(i + vec2(1.0, 1.0), s);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Worley au pixel : (distance au point le plus proche en px, F2 - F1 en px, identifiant de cellule).
vec3 worley(vec2 pc, float cell, float s) {
	vec2 p = (pc + 0.5) / cell;
	vec2 ci = floor(p);
	float f1 = 99.0;
	float f2 = 99.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cl = ci + vec2(float(i), float(j));
			vec2 o = vec2(rnd2(cl, s), rnd2(cl, s + 17.0));
			float d = length(cl + o - p) * cell;
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = rnd2(cl, s + 33.0);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f1, f2 - f1, id);
}

// Quantifie une valeur 0..1 en n+1 niveaux (nuances franches de pixel-art).
float ps(float v, float n) {
	return floor(clamp(v, 0.0, 1.0) * n + 0.5) / n;
}

// Plan de la face : même convention que VoxelMesher (axes u, v des quads).
vec2 plane_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x > 0.5) {
		return n.x > 0.0 ? p.yz : p.zy;
	}
	if (a.y > 0.5) {
		return n.y > 0.0 ? p.zx : p.xz;
	}
	return n.z > 0.0 ? p.xy : p.yx;
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float sl(Ctx c, float s) {
	return s + c.layer * 0.173;
}

// Mousse : plaques de pixels vert sombre, surtout sur le dessus et dans les creux.
vec3 moss_layer(Ctx c, vec3 col, float amount, float s) {
	float m1 = vnoise(c.pc, 18.0, sl(c, s));
	float m2 = vnoise(c.wp, 7.0, sl(c, s + 5.0));
	float where = c.up > 0.5 ? smoothstep(0.42, 0.62, m1) : smoothstep(0.62, 0.78, m2) * 0.6;
	where *= (1.25 - c.ao * 0.6);
	// Taches en petits amas de pixels (jamais de confettis isolés).
	float v = 0.6 * vnoise(c.pc, 4.0, sl(c, s + 11.0)) + 0.4 * rnd2(c.pc, sl(c, s + 9.0));
	float thr = clamp(where * amount, 0.0, 1.0) * 0.55;
	if (v < thr) {
		float k = v / max(thr, 0.001);
		return k < 0.35 ? vec3(0.07, 0.14, 0.035) : (k < 0.7 ? vec3(0.11, 0.21, 0.05) : vec3(0.17, 0.28, 0.08));
	}
	return col;
}

// ---------------------------------------------------------------- pierre

vec3 stone_surface(Ctx c, vec3 base, float rough_k, inout float rough) {
	float s = sl(c, c.seed * 13.0);
	float h = hash11(c.seed * 71.3 + 2.0);
	vec3 col = base * (0.94 + 0.12 * h);
	// Mouchetis : taches de 2 à 6 pixels, 5 niveaux de gris-beige.
	float m = ps(vnoise(c.pc, 5.0, s + 1.0) * 0.6 + rnd2(c.pc, s + 2.0) * 0.4, 4.0);
	col *= 1.0 + c.amp * (m - 0.5) * 0.3;
	// Pores : pixels isolés plus sombres, éclats clairs.
	float r = rnd2(c.pc, s + 3.0);
	col *= r > 0.965 ? 1.0 - 0.22 * c.amp : (r < 0.02 ? 1.0 + 0.16 * c.amp : 1.0);
	// Fissures : bords de cellules de Worley, rares, plus nombreuses avec l'âge.
	vec3 w = worley(c.pc, 15.0, s + 4.0);
	float mask = vnoise(c.pc, 30.0, s + 5.0);
	if (w.y < 0.75 && mask > 0.66 - c.wear * 0.2) {
		col *= 1.0 - 0.38 * c.amp;
	}
	// Coulures verticales sur les flancs.
	if (c.up < 0.5) {
		float st = rnd1(c.wp.x, s + 6.0);
		float len = 8.0 + floor(rnd1(c.wp.x, s + 7.0) * 30.0);
		if (st > 0.9 && mod(c.wp.y + rnd1(c.wp.x, s + 8.0) * 60.0, 90.0) < len) {
			col *= 1.0 - 0.14 * c.amp * (0.4 + c.wear);
		}
	}
	// Arêtes : pixel de bord légèrement plus clair (usure), poussière.
	if (c.edge_px < 0.5 && use_quad_data) {
		col *= 1.0 + 0.12 * c.amp * (0.4 + c.wear);
	}
	col = moss_layer(c, col, c.wear * 0.8 * c.amp, s + 20.0);
	rough = clamp(rough * rough_k, 0.6, 1.0);
	return col;
}

vec3 rock_surface(Ctx c, vec3 base, inout float rough) {
	float s = sl(c, 41.0);
	// Strates horizontales ondulées : bandes de 3 à 8 pixels, tons alternés.
	float warp = floor(vnoise(c.wp, 40.0, s) * 9.0);
	float band = floor((c.wp.y + warp) / 5.0);
	float bt = ps(rnd1(band, s + 1.0), 3.0);
	vec3 col = base * (0.88 + 0.2 * bt * c.amp + 0.1 * (1.0 - c.amp));
	// Grain minéral : tons voisins posterisés + éclats clairs (micas) et sombres.
	float g = ps(vnoise(c.pc, 3.0, s + 2.0) * 0.5 + rnd2(c.pc, s + 3.0) * 0.5, 3.0);
	col *= 1.0 + c.amp * (g - 0.5) * 0.26;
	float r = rnd2(c.pc, s + 4.0);
	col *= r > 0.975 ? 1.0 + 0.3 * c.amp : (r < 0.03 ? 1.0 - 0.28 * c.amp : 1.0);
	// Fissures profondes.
	vec3 w = worley(c.pc, 26.0, s + 5.0);
	if (w.y < 0.8 && vnoise(c.pc, 60.0, s + 6.0) > 0.5) {
		col *= 1.0 - 0.5 * c.amp;
	}
	// Érosion : bandes claires lessivées sur les flancs.
	if (c.up < 0.5 && rnd1(floor(c.wp.x / 3.0), s + 7.0) > 0.86) {
		col *= 1.0 + 0.14 * c.amp;
	}
	col = moss_layer(c, col, (0.15 + c.wear * 0.9) * c.amp, s + 30.0);
	rough = 0.95;
	return col;
}

vec3 ashlar_surface(Ctx c, vec3 base, inout float rough) {
	if (c.up > 0.5 || c.up < -0.5) {
		return stone_surface(c, base, 1.0, rough);
	}
	// Assises de 11 pixels (22 cm), blocs de 14 à 38 pixels, joint de 1 pixel.
	float row = floor(c.wp.y / 11.0);
	float ry = mod(c.wp.y, 11.0);
	float blen = 14.0 + floor(rnd1(row, 5.0) * 24.0);
	float off = floor(rnd1(row, 6.0) * 60.0);
	float cu = c.wp.x + off;
	float ci = floor(cu / blen);
	float cx = mod(cu, blen);
	float bid = rnd2(vec2(row, ci), 7.0);
	vec3 col = stone_surface(c, base * (0.86 + 0.28 * ps(bid, 4.0)), 1.0, rough);
	// Biseau : ligne claire en haut du bloc, ombre en bas, bord gauche éclairé.
	if (ry > 9.5 && cx > 1.0) {
		col *= 1.0 + 0.1 * c.amp;
	} else if (ry < 1.5 && ry > 0.5) {
		col *= 1.0 - 0.08 * c.amp;
	}
	// Joint (mortier) : 1 pixel sombre, un peu de mousse avec l'âge.
	if (ry < 0.5 || cx < 0.5) {
		vec3 mortar = base * vec3(0.55, 0.52, 0.47) * (0.9 + 0.2 * rnd2(c.pc, 8.0));
		return moss_layer(c, mortar, c.wear * 0.5 * c.amp, 9.0);
	}
	return col;
}

vec3 cobble_surface(Ctx c, vec3 base, inout float rough) {
	if (c.up < 0.5) {
		return stone_surface(c, base * 0.92, 1.0, rough);
	}
	// Pavés : cellules de ~9 pixels (18 cm), joints d'un pixel, un ton par pavé.
	vec3 w = worley(c.pc, 9.0, sl(c, 3.0));
	vec3 col = base * (0.72 + 0.56 * ps(w.z, 4.0));
	float r = rnd2(c.pc, sl(c, 4.0));
	col *= 1.0 + c.amp * ((r - 0.5) * 0.16 + (w.x < 2.6 ? 0.09 : -0.05));
	if (w.y < 0.5) {
		vec3 joint = vec3(0.09, 0.07, 0.05) * (0.8 + 0.5 * r);
		// Herbe qui perce dans les joints.
		if (c.wear > 0.3 && vnoise(c.pc, 14.0, 11.0) > 0.62 && r > 0.45) {
			joint = vec3(0.11, 0.2, 0.05) * (0.8 + r * 0.6);
		}
		return mix(base * 0.7, joint, clamp(c.amp, 0.0, 1.0));
	}
	col = moss_layer(c, col, c.wear * 0.35 * c.amp, 12.0);
	rough = 0.92;
	return col;
}

vec3 gravel_surface(Ctx c, vec3 base, inout float rough) {
	vec3 w = worley(c.pc, 3.2, sl(c, 5.0));
	float t = ps(w.z, 4.0);
	vec3 col = base * (0.72 + 0.5 * t);
	if (w.y < 0.4) {
		col *= 0.62;
	}
	col *= 1.0 + c.amp * (rnd2(c.pc, sl(c, 6.0)) - 0.5) * 0.14;
	rough = 0.97;
	return col;
}

// ---------------------------------------------------------------- terre, herbe

vec3 soil_surface(Ctx c, vec3 base, inout float rough) {
	float s = sl(c, 51.0);
	float p = ps(vnoise(c.pc, 6.0, s) * 0.55 + rnd2(c.pc, s + 1.0) * 0.45, 4.0);
	vec3 col = base * (0.84 + 0.3 * mix(0.5, p, c.amp));
	// Humidité : plaques plus sombres.
	float wet = vnoise(c.pc, 26.0, s + 2.0);
	if (wet > 0.62 - c.wear * 0.15) {
		col *= 1.0 - 0.3 * c.amp;
	}
	// Cailloux : disques de 2 à 4 pixels gris.
	vec3 cell = worley(c.pc, 15.0, s + 3.0);
	if (cell.z > 0.6 && cell.x < 1.0 + cell.z * 1.8) {
		col = mix(col, vec3(0.2, 0.19, 0.17) * (0.7 + 0.8 * cell.z), clamp(c.amp, 0.0, 1.0));
	}
	// Racines et sillons sur les flancs.
	if (c.up < 0.5) {
		float rc = rnd1(c.wp.x, s + 4.0);
		float seg = mod(c.wp.y + rnd1(c.wp.x, s + 5.0) * 40.0, 40.0);
		if (rc > 0.93 && seg < 9.0) {
			col = vec3(0.1, 0.065, 0.04) * (0.8 + 0.4 * rnd2(c.pc, s + 6.0));
		}
	}
	rough = 1.0;
	return col;
}

vec3 grass_top(Ctx c, vec3 base, inout float rough) {
	float s = sl(c, 61.0);
	float patch = vnoise(c.pc, 40.0, s);
	float zone = vnoise(c.pc, 160.0, s + 1.0);
	vec3 col = base * (0.9 + 0.2 * patch);
	float dry = smoothstep(0.55, 0.8, zone) * (0.25 + c.wear * 0.75);
	if (rnd2(c.pc, s + 2.0) < dry * 0.9) {
		col *= mix(vec3(1.0), grass_dry_tint, 0.75 * c.amp);
	}
	// Brins : quatre verts qui alternent par pixel, touffes sombres au cœur, pointes claires.
	float t = ps(vnoise(c.pc, 3.0, s + 3.0) * 0.5 + rnd2(c.pc, s + 4.0) * 0.5, 3.0);
	col *= 1.0 + c.amp * (t - 0.5) * 0.36;
	vec3 tf = worley(c.pc, 7.0, s + 5.0);
	if (tf.x < 1.0) {
		col *= 1.0 - 0.18 * c.amp;
	} else if (tf.x < 2.1 && tf.z > 0.5) {
		col *= 1.0 + 0.1 * c.amp;
	}
	// Trèfles : petits groupes plus clairs.
	if (vnoise(c.pc, 12.0, s + 6.0) > 0.8 && rnd2(c.pc, s + 7.0) > 0.5) {
		col *= vec3(1.14, 1.2, 0.9);
	}
	// Herbe piétinée : le sol apparaît par taches de pixels.
	float tr = smoothstep(0.75, 1.0, c.wear);
	if (vnoise(c.pc, 12.0, s + 8.0) < tr * 0.7 && rnd2(c.pc, s + 9.0) < 0.85) {
		col = vec3(0.3, 0.2, 0.115) * (0.8 + 0.4 * rnd2(c.pc, s + 10.0));
	}
	rough = 0.95;
	return col;
}

// ---------------------------------------------------------------- bois, écorce

vec3 wood_surface(Ctx c, vec3 base, inout float rough) {
	float s = c.seed * 29.0 + 3.0;
	float h1 = hash11(c.seed * 91.7 + 1.3);
	float h2 = hash11(c.seed * 53.1 + 7.7);
	vec3 col = base * (0.88 + 0.24 * h1);
	col *= vec3(1.0 + 0.06 * (h2 - 0.5), 1.0, 1.0 - 0.1 * (h2 - 0.5));
	float w = c.wear;
	bool endg = c.grain > 1.5 && c.grain < 2.5;
	if (endg) {
		// Bois de bout : cernes concentriques en pixels, quelques fentes.
		vec2 q = c.qpx - c.qsz * 0.5;
		float d = length(q + vec2(sin(q.y * 0.9) * 0.6, 0.0));
		float ring = mod(floor(d * 0.62 + h1 * 4.0), 3.0);
		col *= ring < 1.0 ? 1.0 - 0.24 * c.amp : (ring < 2.0 ? 1.0 : 1.0 + 0.08 * c.amp);
		if (rnd2(floor(q * 0.5), s) > 0.9 && abs(q.x) < abs(q.y) * 0.4 + 1.0) {
			col *= 1.0 - 0.3 * c.amp;
		}
		col *= 1.0 + c.amp * (rnd2(c.pc, s + 1.0) - 0.5) * 0.1;
		rough = 0.95;
		return col;
	}
	// Fibres : une ligne de pixels par rangée en travers ; chaque ligne alterne des tronçons
	// de 5 à 20 pixels de ton différent.
	float li = c.gp.y;
	float lt = rnd1(li, s);
	float seg_len = 5.0 + floor(rnd1(li, s + 1.0) * 16.0);
	float seg = floor((c.gp.x + floor(rnd1(li, s + 2.0) * seg_len)) / seg_len);
	float st = rnd2(vec2(li, seg), s + 3.0);
	float tone = ps(mix(lt, st, 0.65), 4.0);
	col *= 1.0 + c.amp * (tone - 0.5) * 0.36;
	// Veinures : bandes ondulées plus sombres d'un pixel.
	float wv = c.gp.y + floor(6.0 * vnoise(c.gp, 22.0, s + 5.0));
	if (mod(wv, 9.0) < 1.0) {
		col *= 1.0 - 0.14 * c.amp;
	}
	// Nœuds : anneaux de pixels autour d'un point (allongés dans le sens des fibres).
	vec3 kn = worley(vec2(c.gp.x * 0.62, c.gp.y), 34.0, s + 9.0);
	if (kn.z > 0.9) {
		float d = kn.x;
		if (d < 1.3) {
			col *= 1.0 - 0.5 * c.amp;
		} else if (d < 2.4) {
			col *= 1.0 - 0.22 * c.amp;
		} else if (d < 3.3) {
			col *= 1.0 - 0.34 * c.amp;
		}
	}
	// Âge : bois neuf chaud → ancien gris-brun → usé argenté, fendillé.
	vec3 grey = vec3(lum(col)) * vec3(1.06, 1.0, 0.9);
	col = mix(col, grey * 0.92, w * 0.55 * min(c.amp, 1.0));
	if (rnd2(vec2(li, floor(c.gp.x / 14.0)), s + 20.0) > 0.93 - w * 0.08) {
		col *= 1.0 - 0.34 * c.amp * (0.4 + w);
	}
	// Arête usée : pixel de bord plus clair.
	if (use_quad_data && c.edge_px < 0.5) {
		col *= 1.0 + (0.1 + 0.14 * w) * c.amp;
	}
	rough = 0.68 + 0.28 * w;
	return col;
}

vec3 bark_surface(Ctx c, vec3 base, inout float rough) {
	float s = sl(c, 71.0);
	// Sillons verticaux : colonnes de pixels de ton propre, tronçons de 8 à 30 pixels.
	float warp = floor(vnoise(vec2(0.0, c.wp.y), 24.0, s) * 5.0);
	float col_i = c.wp.x + warp;
	float ct = rnd1(col_i, s + 1.0);
	float seg_len = 8.0 + floor(rnd1(col_i, s + 2.0) * 22.0);
	float seg = floor((c.wp.y + floor(rnd1(col_i, s + 3.0) * seg_len)) / seg_len);
	float tone = ps(mix(ct, rnd2(vec2(col_i, seg), s + 4.0), 0.6), 3.0);
	vec3 col = base * (0.68 + 0.6 * mix(0.5, tone, c.amp));
	if (rnd1(col_i, s + 5.0) > 0.78) {
		col *= 1.0 - 0.32 * c.amp;        // sillon profond
	}
	if (lum(base) > 0.35) {
		// Bouleau : lenticelles sombres horizontales de 3 à 6 pixels.
		float row = floor(c.wp.y / 5.0);
		if (rnd2(vec2(floor(c.wp.x / 5.0), row), s + 6.0) > 0.8 && mod(c.wp.y, 5.0) < 1.0) {
			col = base * 0.3;
		}
	}
	// Lichens et mousse en plaques.
	if (vnoise(c.wp, 16.0, s + 7.0) > 0.8 - c.wear * 0.1 && rnd2(c.pc, s + 8.0) > 0.45) {
		col = vec3(0.17, 0.24, 0.1) * (0.8 + 0.5 * rnd2(c.pc, s + 9.0));
	}
	rough = 1.0;
	return col;
}

// ---------------------------------------------------------------- métal

vec3 metal_surface(Ctx c, vec3 base, inout float rough, inout float metal_k) {
	float s = c.seed * 17.0 + 5.0;
	float z = ps(vnoise(c.pc, 7.0, s) * 0.6 + rnd2(c.pc, s + 1.0) * 0.4, 3.0);
	vec3 col = base * (0.88 + 0.24 * mix(0.5, z, c.amp));
	bool warm = base.r - base.b > 0.06;
	float w = c.wear;
	// Rayures : traits d'un pixel de 3 à 9 pixels dans le sens du grain, plus clairs.
	float li = c.gp.y;
	float start = floor(rnd1(li, s + 2.0) * 40.0);
	if (rnd1(li, s + 3.0) > 0.88 && mod(c.gp.x + start, 40.0) < 3.0 + floor(rnd1(li, s + 4.0) * 7.0)) {
		col *= 1.0 + 0.38 * c.amp;
	}
	// Oxydation : patine verte (cuivre, laiton) ou rouille (fer), pixels dans les creux.
	float pat = clamp((1.0 - c.ao) * 2.2 + (vnoise(c.pc, 9.0, s + 5.0) - 0.5) * 0.9, 0.0, 1.0) * w;
	float pr = 0.6 * vnoise(c.pc, 4.0, s + 8.0) + 0.4 * rnd2(c.pc, s + 6.0);
	if (pr < pat * 0.5 * c.amp) {
		col = warm ? vec3(0.11, 0.36, 0.28) * (0.75 + 0.5 * pr) : vec3(0.32, 0.14, 0.06) * (0.7 + pr);
		metal_k *= 0.5;
	}
	// Arête : pixel de métal nu brillant, pixel intérieur plus sombre (sépare métal et bois).
	if (use_quad_data) {
		if (c.edge_px < 0.5) {
			col = col * 1.5 + vec3(0.04);
		} else if (c.edge_px < 1.5) {
			col *= 1.0 - 0.28 * c.amp;
		}
	}
	rough = clamp(0.36 + 0.14 * z + 0.2 * w + (pat > 0.1 ? 0.2 : 0.0), 0.25, 0.95);
	return col;
}

// ---------------------------------------------------------------- tissu

vec3 fabric_surface(Ctx c, vec3 base, inout float rough) {
	float s = sl(c, 81.0);
	vec3 col = base;
	// Trame : damier d'un pixel (fils croisés), chaque fil un peu différent.
	float wv = mod(c.pc.x + c.pc.y, 2.0);
	col *= 1.0 + c.amp * (wv < 0.5 ? 0.035 : -0.035);
	col *= 1.0 + c.amp * (rnd2(c.pc, s) - 0.5) * 0.1;
	// Plis : bandes verticales de 5 à 8 pixels, trois tons.
	float fo = floor(c.gp.y + 3.0 * vnoise(c.gp, 28.0, s + 1.0));
	float fold = mod(fo, 7.0);
	col *= 1.0 + c.amp * (fold < 1.5 ? -0.07 : (fold < 3.0 ? 0.0 : (fold < 5.0 ? 0.04 : 0.0)));
	// Salissures et usure : quelques pixels plus sombres, plus nombreux en bas.
	if (rnd2(c.pc, s + 2.0) < c.wear * 0.07) {
		col *= 1.0 - 0.18 * c.amp;
	}
	if (use_quad_data && c.edge_px < 0.5) {
		col *= 1.0 + 0.07 * c.amp;
	}
	rough = 1.0;
	return col;
}

// ---------------------------------------------------------------- divers

vec3 plaster_surface(Ctx c, vec3 base, inout float rough) {
	float s = sl(c, 91.0);
	// Plaques de crépi de 4 à 10 pixels, trois tons, pixels isolés.
	float p = ps(vnoise(c.pc, 6.0, s) * 0.7 + rnd2(c.pc, s + 1.0) * 0.3, 3.0);
	vec3 col = base * (0.92 + 0.1 * mix(0.5, p, c.amp));
	if (rnd2(c.pc, s + 2.0) > 0.97) {
		col *= 1.0 - 0.1 * c.amp;
	}
	// Humidité en pied de mur : taches de pixels plus sombres, de moins en moins hautes.
	float damp = 1.0 - smoothstep(0.0, 0.9, c.py);
	if (rnd2(c.pc, s + 3.0) < damp * 0.5 * (0.4 + c.wear)) {
		col *= 1.0 - 0.18 * c.amp;
	}
	// Taches, fissures fines.
	if (vnoise(c.pc, 40.0, s + 4.0) > 0.78 && rnd2(c.pc, s + 5.0) > 0.5 && c.wear > 0.2) {
		col *= 0.88;
	}
	vec3 w = worley(c.pc, 34.0, s + 6.0);
	if (w.y < 0.6 && vnoise(c.pc, 70.0, s + 7.0) > 0.62) {
		col *= 1.0 - 0.22 * c.amp;
	}
	col = moss_layer(c, col, c.wear * 0.25 * c.amp * (1.0 - smoothstep(0.0, 0.5, c.py)), 8.0);
	rough = 0.97;
	return col;
}

vec3 roof_surface(Ctx c, vec3 base, int style, inout float rough) {
	// Les marches du toit sont des quads longs dans le sens du faîtage (gp.x).
	float h = hash11(c.seed * 37.0 + 4.0);
	float cw = style == 16 ? 5.0 + floor(hash11(floor(c.seed * 8.0)) * 3.0) : 9.0;
	float x = c.gp.x + floor(h * cw);
	float ci = floor(x / cw);
	float cx = mod(x, cw);
	float id = rnd2(vec2(ci, floor(c.seed * 64.0)), 3.0);
	vec3 col = base * (0.84 + 0.3 * ps(id, 3.0));
	if (c.up < 0.5) {
		col *= 0.74;            // contremarche à l'ombre de la tuile du dessus
	}
	// Relief de tuile canal (terre cuite) : colonne centrale plus claire, bords plus sombres.
	if (style == 11 && base.r > base.b * 1.4) {
		col *= cx < 1.0 || cx > cw - 1.5 ? 0.82 : (cx > cw * 0.35 && cx < cw * 0.65 ? 1.08 : 1.0);
	}
	col *= 1.0 + c.amp * (rnd2(c.pc, 5.0) - 0.5) * 0.14;
	if (style == 16) {
		float fib = rnd2(vec2(floor(c.gp.x), ci), 6.0);
		col *= 1.0 + c.amp * (fib - 0.5) * 0.18;
	}
	// Joint entre tuiles et bord bas ombré.
	if (cx < 0.5 || (use_quad_data && c.up > 0.5 && c.qpx.y < 0.5 + 0.0)) {
		col *= 1.0 - 0.28 * c.amp;
	}
	col = moss_layer(c, col, c.wear * 0.6 * c.amp, 5.0 + id);
	rough = style == 11 ? 0.62 : 0.85;
	return col;
}

vec3 foliage_surface(Ctx c, vec3 base, inout float rough) {
	float s = sl(c, 101.0);
	float h1 = hash11(c.seed * 41.0 + 2.0);
	// Folioles : cellules de 4 à 5 pixels, quatre tons de vert, pixels clairs au sommet.
	vec3 w = worley(c.pc, 4.6, s);
	float t = ps(w.z * 0.7 + rnd2(c.pc, s + 1.0) * 0.3, 3.0);
	vec3 col = base * (0.74 + 0.5 * mix(0.5, t, c.amp));
	col *= 0.92 + 0.16 * h1;
	if (w.x < 0.9) {
		col *= 1.0 - 0.12 * c.amp;
	}
	// Lumière du ciel : dessus clair et chaud, dessous sombre et froid.
	col *= mix(vec3(0.78, 0.84, 0.92), vec3(1.1, 1.08, 0.96), c.up * 0.5 + 0.5);
	rough = 0.9;
	return col;
}

void vertex() {
	v_lpos = VERTEX;
	v_lnrm = NORMAL;
	if (use_quad_data) {
		v_quv = CUSTOM0.xy;
		v_qsize = CUSTOM0.zw;
		v_q2 = CUSTOM1.xyz;
	}
	if (sway_strength > 0.0) {
		float w = clamp(-VERTEX.y / sway_range, 0.0, 1.0);
		float t = TIME;
		VERTEX.x += sin(t * 1.1 + VERTEX.z * 1.9) * sway_strength * w;
		VERTEX.z += sin(t * 1.5 + VERTEX.x * 1.3) * sway_strength * 0.5 * w;
	}
}

void fragment() {
	float st = floor(UV2.x + 0.01);
	int style = int(st);
	vec3 base = COLOR.rgb;
	float rough = UV.y;
	float metal_k = UV2.y;
	float emis = UV.x;
	float spec = 0.4;

	Ctx c;
	vec3 n = normalize(v_lnrm);
	vec2 pl = plane_uv(v_lpos, n);
	// Empreinte d'un pixel d'écran en mètres : estompe les nuances trop fines.
	float fp = max(length(dFdx(pl)), length(dFdy(pl)));
	c.amp = tex_strength * (1.0 - smoothstep(0.012, 0.04, fp));
	c.ampz = tex_strength * (1.0 - smoothstep(0.06, 0.25, fp));
	c.pc = floor(pl / PIX);
	c.layer = floor(dot(abs(n), v_lpos) * 100.0 + 0.5);
	c.qpx = floor(v_quv / PIX);
	c.qsz = max(floor(v_qsize / PIX + 0.5), vec2(1.0));
	c.depth = v_q2.x;
	c.seed = v_q2.y;
	c.grain = v_q2.z;
	c.wear = clamp((UV2.x - st) / 0.98, 0.0, 1.0);
	c.ao = COLOR.a;
	c.up = n.y > 0.5 ? 1.0 : (n.y < -0.5 ? -1.0 : 0.0);
	c.py = v_lpos.y;
	bool along_u = c.grain < 0.5 || (c.grain > 2.5 && v_qsize.x >= v_qsize.y);
	c.gp = along_u ? c.pc : c.pc.yx;
	float horiz = abs(n.x) > 0.5 ? v_lpos.z : v_lpos.x;
	c.wp = floor(vec2(horiz, v_lpos.y) / PIX);
	float ed = use_quad_data ? min(min(v_quv.x, v_qsize.x - v_quv.x), min(v_quv.y, v_qsize.y - v_quv.y)) : 10.0;
	c.edge_px = floor(ed / PIX);

	vec3 col = base;
	bool terrain_like = style == 1 || style == 2 || style == 13 || style == 15 || style == 12;
	if (terrain_like) {
		// Grandes zones : teinte qui varie sur plusieurs mètres (par pixels de 2 cm).
		float zone = vnoise(c.pc, 220.0, 13.0);
		col *= 1.0 + (zone - 0.5) * 2.0 * zone_strength * c.ampz;
	}

	if (style == 1) {
		if (c.up > 0.5) {
			col = grass_top(c, col, rough);
		} else {
			// Flancs : lisière d'herbe irrégulière (en pixels) au-dessus de la terre.
			vec3 top = grass_top(c, col, rough);
			vec3 soil = soil_surface(c, soil_color * (0.85 + 0.3 * c.wear), rough);
			float vox = 10.0;                       // pixels par voxel de terrain
			float hpx = mod(c.wp.y, vox);           // 0 = bas du voxel, 9 = haut
			float cover = grass_side_cover * vox;
			float jag = floor(rnd1(c.wp.x, 14.0) * 3.0) - 1.0 + floor(vnoise(vec2(c.wp.x, 0.0), 6.0, 15.0) * 2.0);
			col = (c.up < -0.5 || hpx < vox - cover - jag) ? soil : top * 0.9;
		}
	} else if (style == 2) {
		col = soil_surface(c, col, rough);
	} else if (style == 3) {
		col = stone_surface(c, col, 1.0, rough);
	} else if (style == 4) {
		col = wood_surface(c, col, rough);
	} else if (style == 5) {
		col = metal_surface(c, col, rough, metal_k);
	} else if (style == 6) {
		// Cristal : une teinte par facette (quad), cœur lumineux en anneaux de pixels,
		// bord sombre d'un pixel, étincelles.
		float h = hash11(c.seed * 61.0 + 1.0);
		vec3 tint = mix(vec3(0.62, 0.82, 1.12), vec3(0.95, 1.18, 1.0), ps(h, 3.0));
		col = base * tint;
		float ring = min(c.edge_px, 4.0);
		float core = ring / 4.0;
		col *= 0.62 + 0.5 * mix(0.5, ps(core, 3.0), c.amp + (1.0 - c.amp) * 0.0);
		float sp = rnd2(c.pc, c.seed * 9.0 + 2.0);
		if (use_quad_data && c.edge_px < 0.5) {
			col = base * vec3(0.3, 0.55, 1.0);
		}
		float spark = sp > 0.985 ? 1.0 : 0.0;
		float pulse = 1.0 + crystal_pulse * 0.35 * sin(TIME * 2.2 + v_lpos.y * 3.0 + h * 6.28);
		float k = (0.45 + 1.2 * ps(core, 3.0) + spark * 1.2) * pulse;
		emis *= mix(1.0, k, clamp(tex_strength, 0.0, 1.0));
		col *= 1.0 + spark * 0.5;
		rough = clamp(rough + (h - 0.5) * 0.1, 0.05, 0.5);
		spec = 0.8;
	} else if (style == 7) {
		col = fabric_surface(c, col, rough);
	} else if (style == 8) {
		col = foliage_surface(c, col, rough);
	} else if (style == 9) {
		col = ashlar_surface(c, col, rough);
	} else if (style == 10) {
		col = plaster_surface(c, col, rough);
	} else if (style == 11 || style == 16) {
		col = roof_surface(c, col, style, rough);
	} else if (style == 12) {
		col = cobble_surface(c, col, rough);
	} else if (style == 13) {
		col = rock_surface(c, col, rough);
	} else if (style == 14) {
		col = bark_surface(c, col, rough);
	} else if (style == 15) {
		col = gravel_surface(c, col, rough);
	} else if (style == 17) {
		// Lampe : verre chaud dont l'éclat dépend de l'ambiance, pixels de tons voisins.
		float f = ps(rnd2(c.pc, 3.0), 2.0);
		col = base * (0.88 + 0.24 * f);
		emis *= lamp_emission * (0.88 + 0.24 * f);
		rough = 0.25;
	} else if (style == 18) {
		float wv = ps(vnoise(c.pc + vec2(floor(TIME * 1.5), 0.0), 8.0, 2.0), 3.0);
		col = base * (0.85 + 0.3 * wv);
		rough = 0.06;
		spec = 0.9;
	}

	float ao = mix(1.0, c.ao, ao_strength);
	ALBEDO = col * ao;
	ROUGHNESS = rough;
	METALLIC = metal_k;
	SPECULAR = spec;
	EMISSION = (style == 17 ? base : col) * emis * emission_multiplier;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
}
