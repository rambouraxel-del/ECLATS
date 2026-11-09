# Galerie 3D (GitHub Pages)

Visualiseur web des modèles réels du projet : liste, recherche, filtres, vue 3D (rotation tactile ou souris, zoom, recentrage),
dimensions, variantes reproductibles (graine affichée), chargement d'un modèle seulement quand on l'ouvre.

- Dossier : `galerie/` (page `index.html`, `app.js`, `style.css`, three.js r160 embarqué dans `vendor/`, aucune dépendance externe au chargement).
- Générés (non versionnés, refaits par l'automatisation) : `galerie/catalogue.json` et `galerie/modeles/*.glb.gz`.
- Adresse publiée : `https://rambouraxel-del.github.io/ECLATS/` ; ouvrir directement un modèle : `…/ECLATS/#tree_oak_1`.

## Solution retenue
Export **glTF binaire** par un script Godot 4.3 headless (`tools/galerie/galerie_export.gd`, `GLTFDocument`), compressé en gzip
(154 modèles ≈ 26 Mo au lieu de ≈ 380 Mo), affiché par **three.js**. Godot est déjà installé dans la CI du projet ; pas d'autre outil à installer.

## Inventaire (156 modèles avec les deux modèles d'essai ; 154 en l'état)
| Famille | Source | Nombre |
|---|---|---|
| Précuits | `assets/props/*` (registre `AssetLibrary`) : arbres, rochers, bâtiments, objets de village, artisanat, décor, vestiges, embarcadère, bateau | 55 |
| Modèles du Lot 1 | `VoxelModelLibrary` (blocs, mur, escalier, table…) | 10 |
| Générés | arbres et rochers de la bibliothèque (graines 5, 6, 7, 11), arbres, rochers et vestiges du monde, bâtiments, habitations du joueur, bateaux | 88 |
| Exemples | `assets/maisons/maison_exemple.eclats-maison.json` | 1 |

« Prêt à l'emploi » = précuit (fichier du jeu tel quel). « Généré » = nécessite une graine et des paramètres ; ceux de l'échantillon
sont dans `tools/galerie/config.json`. Chaque fiche indique nom, catégorie, identifiant/générateur, graine, dimensions, triangles et source.

## Commande d'actualisation
```bash
GODOT=/chemin/vers/godot tools/galerie.sh          # Windows : tools\galerie.ps1
python3 -m http.server -d galerie 8000             # aperçu : http://localhost:8000/
```
Options : `--seulement=<famille>` (precuit, asset_arbre, asset_rocher, nature_arbre, nature_rocher, nature_ruine, batiment, habitation, bateau, lot1, exemple, manuel), `--max=N`, `--sortie=dossier`.
La commande détecte les entrées du registre (précuites ou non), exporte les générateurs avec l'échantillon de `config.json`, puis écrit le catalogue.
Le message moteur `Parameter "m" is null` pendant l'écriture glTF est un bruit du rendu factice, sans effet sur les fichiers.

## Ajouter un modèle
1. **Nouvel asset du registre** (`scripts/assets/asset_registry_lot3.gd`) : visible tout de suite (famille « précuit » s'il a été « baké » par `tools/bake_assets.gd`, sinon construit à la volée).
2. **Plus de variantes d'un générateur** : modifier `graines` et `axes` dans `tools/galerie/config.json` (`"auto"` = valeurs détectées).
3. **Fichier glTF existant** : `tools/galerie/manuels/` (voir `LISEZMOI.md`).
4. **Nouveau générateur** : ajouter une fonction `_family_…` dans `galerie_export.gd` (il suffit de produire des maillages) et une entrée dans `config.json`. Tant que ce n'est pas fait, le script le signale dans « Éléments non exportés ».

## Éléments détectés mais non exportés (10)
Générateurs de terrain, de hameau, de port, de placement, d'île complète et de plan (`terrain_generator`, `settlement_generator`, `port_builder`,
`nature_generator`, `world_builder`, `authored_island_builder`, `plan_terrain`, `plan_generator`, `island_generator`) et la carte `ile_ouverture` :
ce sont des cartes ou des assemblages liés à un terrain, pas des objets isolés. Leurs éléments (bâtiments, arbres, objets) figurent dans la galerie.
La raison et la marche à suivre sont aussi affichées en bas de la liste.

## Automatisation (`.github/workflows/galerie-pages.yml`)
À chaque push sur `main` ou `claude/galerie-modeles-3d` (ou lancement manuel) : télécharge Godot 4.3, lance `tools/galerie.sh`, assemble `galerie/` et déploie sur Pages
(`actions/deploy-pages`). Aucune autre publication Pages n'existait dans le dépôt (aucun workflow Pages, pas de branche `gh-pages`) : la galerie est donc
publiée à la racine du site. Si un site existait déjà, il faudrait le copier dans `_site/` avant le déploiement, car un déploiement Actions remplace tout le site.
Réglages à faire une fois (impossibles depuis le workflow) : Settings → Pages → Source : **GitHub Actions** ; puis Settings → Environments → `github-pages` →
Deployment branches : autoriser `claude/galerie-modeles-3d` (ou fusionner dans la branche publiée). Sans cela l'étape `deploy` est refusée alors que `build` réussit
(constaté au premier essai : export, vérification du catalogue et téléversement de l'artefact réussis, déploiement refusé avant démarrage).

## Limites
Couleurs, rugosité, métal et émission du jeu ; pas les micro-textures de pixels de 2 cm du shader. Ni lumières, ni animations (tissus, cristaux), ni collisions.
Niveau de détail le plus fin seulement. Test navigateur : `NODE_PATH=$(npm root -g) node tools/galerie/test/galerie_test.js http://localhost:8000/ captures/`.
