# Assets détaillés (Lot 2)

## Les cinq assets

| id | Nom | Emprise (m) | Hauteur | Triangles | Inspiration |
|---|---|---|---|---|---|
| `artisan_workbench` | Établi d'artisan | 2,00 × 1,00 | 2,00 | 14 292 | planche 4 (établi, râtelier) |
| `ancient_chest` | Coffre ancien | 1,20 × 0,80 | 0,80 | 6 834 | planches 1, 4, 5 (coffres) |
| `anchor_pedestal` | Piédestal d'Ancre | 1,60 × 1,60 | 2,40 | 26 964 | planche 1 (piédestal d'ancre, téléporteur) |
| `market_stall` | Étal de marchand | 2,40 × 1,60 | 2,60 | 45 382 | planche 2 (étal, kiosque) |
| `decorative_bench` | Banc décoratif | 1,80 × 0,60 | 1,00 | 5 564 | planches 2 et 5 (bancs) |

Chiffres exacts et poids des fichiers : `assets/props/assets_report.json` (régénéré à chaque bake).

## Utiliser un asset dans Godot

Les scènes sont dans `assets/props/<id>/<id>.tscn`. Glisser-déposer dans une scène, ou :

```gdscript
var node := AssetLibrary.instantiate("market_stall")   # Node3D (PlaceableAsset)
add_child(node)
node.position = Vector3(2.0, 0.0, 4.0)                 # multiple de 0,20 m = aligné sur la grille
```

Structure d'une scène : racine `PlaceableAsset` (script) → `MeshInstance3D` par pièce
(maillage `.res` externe) → `OmniLight3D` → `StaticBody3D` « Collision » (boîtes).
`PlaceableAsset` expose `footprint_cells` (emprise en cellules de 20 cm), `occupied_cells(origin)`
et les statistiques de maillage — c'est le point d'accroche du futur système de placement.
Rotation prévue par pas de 90° autour de Y (l'origine est le coin minimum de l'emprise).

Pièces animées : `anchor_crystal` (flottement + rotation lente), `orbiting_shards` (rotation
inverse), `canopy` de l'étal (tissu qui ondule via `voxel_cloth_material.tres`).

## Générer / régénérer

```
godot --headless -s tools/bake_assets.gd              # tous
godot --headless -s tools/bake_assets.gd -- ancient_chest
godot --rendering-driver opengl3 -s tools/preview_asset.gd -- market_stall capture.png 30 20
```

Les scènes et maillages générés sont **versionnés** (le projet s'ouvre sans rien générer).
Si la palette change, relancer le bake : les couleurs sont écrites dans les sommets.

## Écrire un nouvel asset

- `scripts/assets/asset_kit.gd` : outils de modélisation en microvoxels de 2 cm
  (`stone_block`, `masonry`, `planks`, `post`, `copper_cap`, `corner_plate`, `banner`, `drape`,
  `lantern`, `crystal`, `ivy`, `bush`, `moss_top`…), hérite de `VoxelModelBuilder`
  (`box`, `line`, `ellipsoid`, `speckle`).
- `scripts/assets/voxel_asset.gd` : conteneur (pièces, lumières, collisions, emprise).
- `scripts/assets/props/*.gd` : un fichier par asset avec une fonction statique `build()`.
- Chaque asset est **déterministe** (graine fixe dans le constructeur de `AssetKit`).

## Pipeline de maillage

`VoxelVolume` (octets) → `VoxelMesher` style STYLIZED : faces visibles seulement, fusion
gloutonne des faces coplanaires de même matière et même occlusion, un seul matériau partagé
(`voxel_stylized_material.tres`). Les volumes sources ne sont pas chargés au runtime : seuls
les maillages `.res` compressés le sont.

## Blender ?

Non utilisé : la génération par code donne des résultats identiques, reproductibles et testés
en headless, sans dépendance. Si un export glTF devient utile, les maillages peuvent être
sauvegardés par `GLTFDocument` depuis `tools/bake_assets.gd`.
