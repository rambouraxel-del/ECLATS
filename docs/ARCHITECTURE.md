# Architecture — Lot 1

## Conventions

- **1 unité Godot = 1 mètre.**
- **Grille principale : 0,20 m** (`VoxelGrid.VOXEL_SIZE`) — terrain et blocs posés.
- **Grille de détail : 0,02 m** (`VoxelGrid.DETAIL_SIZE`, Lot 2) — meubles, assets, plantes.
  Les 10 objets du Lot 1 restent en 0,05 m (`LEGACY_DETAIL_SIZE`).
- Toute emprise d'objet est un multiple de 0,20 m ; l'origine d'un objet est le coin
  minimum de son emprise, posé au sol. Un objet placé sur la grille s'aligne donc
  exactement sur le terrain.
- Aucun cube n'est un nœud : les voxels sont stockés dans des tableaux d'octets puis
  convertis en maillages groupés.

## Arborescence

```
config/        palette.json (matières), lighting.json (éclairages)
materials/     voxel.gdshader + voxel_material.tres (matériau unique des voxels), sol du labo
scripts/core/      VoxelGrid (coordonnées), VoxelVolume (stockage), VoxelPalette, VoxelMesher
scripts/terrain/   IslandGenerator (seed → données), IslandData (cœur + surface), VoxelIsland (nœud)
scripts/objects/   VoxelModelBuilder (outil de modélisation), VoxelModelLibrary (10 objets),
                   VoxelModelInstance (nœud qui affiche un objet)
scripts/island/    VegetationLibrary (arbres, plantes), IslandDecor (placement), first_island.gd
scripts/lab/       graphics_lab.gd (construction du laboratoire)
scripts/camera/    FreeCamera (vol + orbite), CameraInput (touches)
scripts/rendering/ LightingRig (soleil, ciel, environnement depuis lighting.json)
scripts/app/       App (autoload : changement de scène, éclairage, aide à l'écran)
scenes/            lab/graphics_lab.tscn, island/first_island.tscn
tests/             run_checks.gd (vérifications headless)
tools/             check.sh, check.ps1, capture.gd (captures d'écran)
```

## Chaîne de rendu voxel

1. **Données** : `VoxelVolume` = grille dense, 1 octet par cellule (0 = air, sinon
   identifiant de matière dans la palette). API calquée sur `VoxelBuffer` de Voxel Tools.
2. **Maillage** : `VoxelMesher.build_arrays` ne génère que les faces en contact avec
   l'air (vérifié par test : nombre de faces = nombre exact de contacts plein/vide).
   Il ajoute une occlusion ambiante par sommet et une légère variation de teinte par voxel.
   C'est une fonction pure : l'île est maillée en parallèle (WorkerThreadPool).
3. **Matériau unique** : `voxel.gdshader` lit la couleur dans les sommets, la rugosité et
   l'émission dans UV, et dessine un fin liseré sur les arêtes (qui s'efface au loin).
   Un seul matériau = peu d'appels de rendu, et un rendu identique partout.

## Pas de raccord terrain / blocs

Terrain et blocs posés partagent : la même grille (0,20 m), la même palette, le même
shader, et une variation de teinte calculée à partir des **coordonnées monde** de la
cellule. Un bloc d'herbe posé à côté du sol est donc indiscernable du terrain (démontré
dans le laboratoire, zone « Raccord terrain / blocs posés »).

## Île : cœur fixe et couche modifiable

`IslandGenerator` travaille colonne par colonne (forme du bord, hauteur avec paliers
constructibles, sous-face en stalactites, strates rocheuses, éclats, racines pendantes),
à partir de bruits `FastNoiseLite` dont la seed est dérivée de la seed de l'île :
**même seed = même île**, sur toutes les machines.

Le résultat (`IslandData`) contient deux volumes de même taille :

- `surface` : les 6 premiers voxels (1,20 m) sous le sol — **modifiable**
  (`set_surface_voxel`), prévu pour creuser / construire plus tard ;
- `core` : tout le reste (roche, sous-face, racines) — **non destructible**
  (`set_surface_voxel` refuse ces cellules).

Chaque couche est maillée séparément par chunks de 32³ voxels (6,4 m), en cachant ses
faces contre l'autre couche grâce à un masque d'occupation commun. Modifier la surface
ne demandera de reconstruire que les chunks concernés de la surface.

## Compatibilité future avec Voxel Tools

Voxel Tools n'est **pas** une dépendance. Le code est organisé pour migrer facilement :

| ÉCLATS (Lot 1) | Équivalent Voxel Tools |
|---|---|
| `VoxelVolume.get_voxel / set_voxel` | `VoxelBuffer.get_voxel / set_voxel` (canal TYPE) |
| Identifiants de `palette.json` | Modèles d'un `VoxelBlockyLibrary` (même ordre) |
| `IslandGenerator` (pur, colonne par colonne) | `VoxelGeneratorScript._generate_block` |
| `VoxelIsland` (chunks 32³) | `VoxelTerrain` + `VoxelMesherBlocky` |

## Éclairage

`LightingRig` crée soleil (ombres en 4 cascades), ciel procédural et environnement
(tonemap Filmic, SSAO, lueur, brouillard) et applique un préréglage de `lighting.json`.
Le même nœud sert dans les deux scènes.

## Ajouts du Lot 2

- `VoxelMesher.Style.STYLIZED` (défaut) : maillage glouton + shader `voxel_stylized.gdshader` ;
  `Style.LEGACY` : rendu du Lot 1, conservé pour comparaison (touche V sur l'île).
- Palette étendue (50 matières) : `style` (traitement shader) et `metallic` par matière.
- `scripts/assets/` : `AssetKit` (outils de modélisation 2 cm), `VoxelAsset`, `AssetLibrary`,
  `PlaceableAsset`, assets dans `props/`. `tools/bake_assets.gd` produit `assets/props/`.
- `TerrainPatch` : portion de terrain pour les dioramas du laboratoire.
- Détails : `docs/ASSETS.md`, `docs/DIRECTION_ARTISTIQUE.md`.

## Ajouts du Lot 3

- **Shader unique** `materials/voxel_stylized.gdshader` : pixels de 2 cm, une couleur par pixel, aucun fichier image.
  Données par quad (`CUSTOM0/1` : position et taille du quad, épaisseur de matière, graine, sens du grain) produites par
  `VoxelMesher.Style.DETAIL`. Usure par matière (`wear`).
- **Grille de bâtiments de 10 cm** (`VoxelGrid.STRUCTURE_SIZE`), `BuildingKit` (fenêtres, portes, colombage, toits, cheminées).
- **LOD** : `VoxelVolume.downsample`, `tools/bake_assets.gd` (maillages par niveau + fiche JSON).
- **Instanciation** : `PropScatter` (MultiMesh par cellule et par LOD, collisions regroupées).
- **Île habitée** : `VillageLayout` (plan), hooks `height_hook` / `surface_hook` du générateur, `colony_island.gd`.
- **Ciel et nuages** : `sky_clouds.gdshader`, `VoxelClouds`, ambiances dans `config/lighting.json`.
- Détails : `docs/OPTIMISATION.md`, `docs/BILAN_LOT3.md`, `docs/ASSETS.md`.
