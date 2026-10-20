# Bilan — Lot 2 : refonte graphique voxel et premiers assets détaillés

## Livré

1. **Cinq modèles 3D** (`assets/props/*/*.tscn`) : établi d'artisan, coffre ancien, piédestal
   d'Ancre, étal de marchand, banc décoratif — voir `docs/ASSETS.md`.
2. **Système de détails à 2 cm** : `VoxelGrid.DETAIL_SIZE = 0.02`, `AssetKit`, `VoxelAsset`,
   bake vers scènes Godot ; les 10 objets du Lot 1 restent en 5 cm (`LEGACY_DETAIL_SIZE`).
3. **Terrain stylisé** : faces fusionnées (aucun contour entre voxels coplanaires), aucune
   variation par cellule, nuances par zones dans le shader, herbe continue, flancs d'herbe qui
   passent à la terre, strates de pierre. Dimensions de l'île, seed, cœur/surface, chunks :
   inchangés (empreinte de génération identique, testée).
4. **Laboratoire enrichi** : socles avec nom, dimensions et triangles ; diorama des assets sur
   terrain voxel ; comparaison terrain Lot 1 / Lot 2 ; vues 1 à 9 ; éclairage « Présentation ».
   Sur l'île, **V** bascule entre l'ancien et le nouveau rendu.
5. **Captures** : `docs/captures/lot2/`.
6. **Direction artistique** : `docs/DIRECTION_ARTISTIQUE.md` ; planches dans `docs/references/`.
7. Résultats ci-dessous.

## Mesures (Godot 4.3, Linux, sans GPU, 4 cœurs)

| Asset | Microvoxels pleins | Sommets | Triangles | Maillage (.res) | Génération + maillage |
|---|---|---|---|---|---|
| Établi d'artisan | 105 072 | 28 584 | 14 292 | 171 Ko | 0,76 s |
| Coffre ancien | 62 361 | 13 668 | 6 834 | 79 Ko | 0,34 s |
| Piédestal d'Ancre | 142 156 | 53 928 | 26 964 | 324 Ko | 0,94 s |
| Étal de marchand | 250 405 | 90 764 | 45 382 | 531 Ko | 2,1 s |
| Banc décoratif | 33 226 | 11 128 | 5 564 | 65 Ko | 0,35 s |
| **Total** | 593 220 | 198 072 | **99 036** | 1,2 Mo | |

- Terrain de l'île (30 m) : **135 728 triangles** contre 185 492 avec le rendu du Lot 1
  (−27 %), maillage ≈ 1,9 s contre 2,6 s.
- Mémoire : volumes sources des 5 assets = 3,0 Mo (non chargés au runtime) ; au runtime,
  seuls les maillages (≈ 2,4 Mo en vertex avant compression) sont en mémoire.
- Un `MeshInstance3D` par pièce (1 à 3 par asset), aucun nœud par voxel.

## Tests

`tools/check.sh` / `tools/check.ps1` : import headless sans erreur de script, puis
`tests/run_checks.gd` : **103 contrôles réussis, 0 échec** (44 du Lot 1 conservés, adaptés au
nouveau mailleur par un mode « rendu Lot 1 »). Nouveaux contrôles : résolution 2 cm,
fusion de faces (cube 8³ → 6 quads), même surface visible qu'avant fusion, pas de fusion entre
matières, absence de variation par cellule, île inchangée, et pour chaque asset : emprise,
déterminisme, géométrie contenue dans l'emprise, budget de triangles, **aucune face interne**
(faces = contacts plein/vide), collisions dans l'emprise, scène importée cohérente.

## Limites connues

- **Rendu non validé sur GPU ni Windows** : captures en rendu Compatibilité (OpenGL logiciel) —
  pas de SSAO, tonemapping différent. À valider sur Forward+.
- Les assets s'inspirent des planches sans les égaler : lierre et mousse plus clairsemés,
  ornements sculptés (runes, losanges de bois) simplifiés, pas de cannelures fines partout.
- Le bois est un peu plus chaud que sur les planches sous l'éclairage de présentation.
- Les lumières d'assets sont de simples `OmniLight3D` ; pas de halo volumétrique.
- Les cristaux sont émissifs (glow) mais pas translucides ; le tissu de l'étal ondule
  légèrement mais n'est pas simulé.
- Collisions : boîtes englobantes simplifiées, pas de collision fine par voxel.
- Le placement utilisateur (aperçu fantôme, rotation) n'est pas implémenté : seule l'interface
  `PlaceableAsset` est prête.
- Génération des assets synchrone dans le bake (jusqu'à ~2 s pour l'étal) ; non utilisée en jeu.
- Le diorama et la comparaison sont construits au lancement du laboratoire (~3 s).

## Pistes suivantes

1. Validation visuelle sous Windows et retouches (teinte du bois, densité de lierre).
2. Les autres objets des planches (puits, lampadaires, forge, mobilier…) avec le même kit.
3. Système de placement sur la grille de 20 cm (fantôme, rotation 90°, collision de l'emprise).
4. Cristaux translucides et halos ; vent sur lierre et tissus ; particules (flamme, poussière).
5. LOD des assets (grandes distances) et instanciation (MultiMesh) pour les répétitions.
