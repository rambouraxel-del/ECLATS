# Optimisations (Lot 3)

| Technique | Où | Gain |
|---|---|---|
| **Maillage glouton** : faces coplanaires de même matière fusionnées | `VoxelMesher` | −27 % de triangles sur le terrain, plus sur les grandes surfaces |
| **LOD par sous-échantillonnage** des voxels (×2 puis ×4/×5) | `VoxelVolume.downsample`, `tools/bake_assets.gd` | LOD1 ≈ 25-30 % et LOD2 ≈ 5-8 % des triangles du LOD0 ; silhouettes fines (feuillage) conservées par un seuil de remplissage |
| **Plages de visibilité (HLOD)** : LOD0 jusqu'à 10-30 m, LOD1 jusqu'à 28-75 m, LOD2 au-delà ; ombres coupées sur LOD2 | `visibility_range_*` dans les scènes générées et dans `PropScatter` | les objets lointains coûtent ~5 % |
| **Instanciation (MultiMesh)** par cellule de 14 m et par niveau de détail | `PropScatter` | un appel de dessin pour toutes les instances d'un même modèle d'une cellule ; 1 389 instances dans 300 MultiMesh |
| **Un seul matériau par usage** (terrain, objets, tissus, cristaux, nuages) + aucune texture image | `VoxelMaterials` | 5 matériaux pour toute l'île ; aucune mémoire de texture |
| **Collisions simplifiées** en boîtes, regroupées en un `StaticBody3D` par cellule | `PropScatter`, fiches d'assets | 109 boîtes pour tout le village |
| **Lumières maîtrisées** : seuls les assets lumineux sont des scènes ; atténuation par distance (28 m, ombres 14 m) ; le jour les lampes sont éteintes (`visible = false`) | `LightingRig.refresh_lamps`, bake | pas de lumières inutiles hors de la zone de jeu |
| **Pièces animées séparées** (tissus, cristaux, flammes) | `VoxelAsset.add_part` | seules les pièces mobiles ont un script ; la structure reste statique et instanciable |
| **Végétation basse en MultiMesh à 2 niveaux** (2 cm jusqu'à 16 m, 4 cm jusqu'à 48 m, puis disparition) ; sans ombres | `colony_island.gd` | ≈ 310 k triangles au total, jamais tous à l'écran |
| **Nuages voxel** : 24 nuages, maillés glouton, sans ombres | `VoxelClouds` | quelques centaines de triangles par nuage |
| **Maillage parallèle** du terrain (WorkerThreadPool), chunks de 64 voxels pour la colonie | `VoxelIsland` | moins de nœuds, moins d'appels |
| **Maillages générés versionnés** (`.res` compressés) | `assets/props/` | le projet démarre sans régénérer ; seuls les pixels de texture sont calculés au rendu |

## Réglages utiles

- Distances de LOD par asset : `lod_ranges` dans le script de l'asset (m), puis `tools/bake_assets.gd`.
- Densité de plantes : dictionnaire `kinds` dans `colony_island.gd`.
- Taille de cellule d'instanciation : `PropScatter.cell_size`.
- Force des nuances de pixels : paramètre `tex_strength` (touche T dans la colonie et la galerie).
