# Comparatif de génération du terrain — A · B · C

Branche `claude/comparatif-generation-terrain` (partie du dernier commit du Lot 11, `c6c5962`). Le choix du générateur reste à faire après examen des captures.

## Les trois méthodes (laboratoire développeur → « Comparatif de génération du terrain », ou « Générer une île »)

Graine, largeur, longueur et méthode se règlent dans la même page ; la méthode est mémorisée dans la carte (`settings.method`, carte v3, absente = A).

| | Principe |
|---|---|
| **A** | Générateur actuel du Lot 11 (`PlanTerrain`, méthode « A ») : relief de base résolu entre les zones et les chemins + bruit léger à 2 octaves. Inchangé. |
| **B** | Même plan, mêmes zones plates, mêmes chemins creusés ; le bruit de détail est remplacé par du **FastNoiseLite** enrichi : crêtes (fractal *ridged*), vallées incisées, corps fractal, déformation de domaine. Amplitude ≈ ×2,8. Dénivelé de l'île 5,2 → 8,2 m (graine 21). |
| **C** | **Voxel Tools réellement utilisé** : `VoxelTerrain` + `VoxelMesherBlocky` + `VoxelGeneratorScript` (génération par blocs de 16³ sur les fils de Voxel Tools) + `VoxelViewer` + collisions du module + `VoxelStreamSQLite` (retouches enregistrées). Le plan fournit un *squelette* (zones plates, chemins creusés, matières : `PlanTerrain` méthode « S ») ; le détail (crêtes, vallées, flancs) est généré dans le générateur avec `ZN_FastNoiseLite`, le bruit natif du module, pondéré à zéro sur les zones plates et près des chemins. Voxels de 20 cm (nœud mis à l'échelle 0,2). |

Pas une substitution : C n'utilise ni `TerrainField` ni `LabWorld` pour afficher ou collisionner le terrain (la scène lit seulement les repères du plan).

## Compatibilité et installation de Voxel Tools

- **Version retenue : Voxel Tools 1.3.0** (tag `v1.3.0`, « primarily developed with Godot 4.3 »). Les versions suivantes ciblent Godot 4.4 et plus ; l'édition **GDExtension** n'est annoncée que pour Godot ≥ 4.4.1, elle ne convient donc pas à Godot 4.3 du projet.
- **Mode retenu : module compilé dans le moteur** — Godot **4.3-stable** (commit `77dcf97d8`) + `modules/voxel` = v1.3.0. Les binaires de la page *Releases* n'étaient pas téléchargeables depuis cet environnement (accès réseau limité aux dépôts git) : le moteur est donc **compilé ici** (`tools/build_godot_voxel.sh`, 25 min sur 4 cœurs, éditeur linuxbsd, OpenGL 3, sans Vulkan).
- Le moteur obtenu est un Godot 4.3 ordinaire (`4.3.stable.custom_build`) : même GDScript, même rendu ; toutes les mesures et captures du comparatif (A, B et C) ont été faites **avec ce même binaire**.
- **Conflit de nom corrigé** : le projet avait une classe `VoxelMesher`, déjà définie par Voxel Tools. Elle est renommée `EclatsMesher` (27 fichiers, sans changement de comportement).
- Le projet reste exécutable avec le Godot 4.3 officiel : aucune classe `Voxel*` n'est nommée dans les scripts (tout passe par `ClassDB`, voir `scripts/voxel_proto/`) ; avec le moteur officiel, choisir C affiche « méthode C indisponible » au lieu d'une erreur.
- Pour distribuer un jeu avec C, il faudrait aussi compiler des **modèles d'export** avec le module (non fait ici).

## Comparaison : mêmes plans, mêmes lieux

Pour chaque graine, **le plan est strictement le même** pour A, B et C (contour, arrivée, plateau, bois, sommet, chemins, départ ; empreinte de structure identique). Les cadrages ne dépendent que du plan : mêmes positions, orientations, hauteur d'yeux, champ de vision, lumière et heure. Arbres désactivés pour les trois (C ne sait pas en poser). Rendu logiciel (llvmpipe).

Graine 21, 56 × 48 m ; deuxième graine : 7. Originaux : `docs/captures/comparatif-terrain/` ; planches : `docs/captures/comparatif-terrain/planches/`.

## Vérifications (graine 21, 56 × 48 m ; `tools/comparatif_terrain.gd`, mode `verif`)

| Vérification | A | B | C |
|---|---|---|---|
| Reproductibilité d'une graine | ✔ empreinte identique | ✔ | ✔ deux générations indépendantes : mêmes voxels |
| Chemins praticables (pente ≤ 30 %, marche < 40 cm) | ✔ 3/3 | ✔ 3/3 | ✔ 3/3 (lus dans les voxels, marche max 20 cm) |
| Exploration en première personne (autopilote, vraies collisions) | ✔ 3 chemins, 0 chute | ✔ | ✔ |
| Retouche enregistrée puis rouverte | ✔ carte v3, identique colonne par colonne | ✔ | ✔ base SQLite (49 Ko, 430 ms), nouveau `VoxelTerrain` : retouche retrouvée |

Tests automatiques (Godot officiel) : `tests/run_checks_comparatif.gd`, 30 contrôles (A/B reproductibles, B ≠ A, même grille, mêmes colonnes de chemin, centres des zones plates identiques, chemins et départ sûrs, B garde le contour, détail nul sur les chemins du squelette, méthode conservée dans la carte, méthode inconnue refusée) + suite complète.

## Mesures (Xeon 2,1 GHz, 4 cœurs, Godot 4.3 « custom_build », OpenGL 3 / llvmpipe — **aucun GPU**)

Plan de 56 × 48 m, médiane non calculée : valeurs d'un premier chargement (processus froid) puis, entre parenthèses, d'un second chargement dans le même processus. Il n'existe aucun cache disque pour ces terrains (celui de l'île d'ouverture est un autre système) : « cache » désigne ici le second chargement.

| 56 × 48 m | A | B | C |
|---|---|---|---|
| Relief (plan → hauteurs ; C : squelette) | 928 (817) ms | 911 (1002) ms | 961 (983) ms |
| Génération des voxels seule, 1 fil (C) | — | — | 908 (929) ms pour 1764 blocs |
| Construction du terrain (maillage ; C : génération + maillage + collisions sur 4 fils) | 1495 (1347) ms | 1771 (1708) ms | 1838 (1749) ms |
| Collisions (A/B : carte de hauteurs complète) | 14 ms | 12 ms | comprises ci-dessus |
| Retouche locale (trait de 15 coups → terrain et collisions à jour) | 661 (707) ms | 889 (998) ms | 1067 (1097) ms |
| Mémoire ajoutée | 32 Mo | 53 Mo | 119 Mo |
| Triangles du terrain | 84 828 | 176 824 | 416 372 |

| 120 × 120 m | A | B | C |
|---|---|---|---|
| Relief | 4554 ms | 4964 ms | 5038 ms |
| Génération seule 1 fil (C) | — | — | 5549 ms (8648 blocs) |
| Construction du terrain | 5324 ms | 6364 ms | 8988 ms |
| Collisions | 57 ms | 60 ms | comprises |
| Retouche locale | 571 ms | 748 ms | 2291–2775 ms |
| Mémoire ajoutée | 98 Mo | 183 Mo | 591 Mo |
| Triangles | 346 924 | 821 486 | 2 227 500 |

Lecture prudente :
- Le relief du plan (≈ 1 s / 4,5 s) domine pour les trois et est **identique** : c'est le squelette commun, pas la méthode.
- C construit plus lentement et pèse 3 à 6 fois plus de mémoire et de triangles : le mailleur blocky de Voxel Tools **ne fusionne pas** les faces (A et B les fusionnent). La mesure des triangles est celle des primitives du rendu (terrain visible moins terrain masqué, vue aérienne).
- La retouche locale de C comprend l'attente de la fin des tâches du module ; la durée dépend du rythme d'images (rendu logiciel, quelques images par seconde) : à 120 × 120 m elle est surtout un plafond.
- **Fluidité GPU non évaluée** : tout est du CPU et du rendu logiciel. Le coût de 2 M de triangles à l'écran sur carte graphique reste à vérifier, comme l'effet du LOD de Voxel Tools (non utilisé ici : `VoxelTerrain`, pas `VoxelLodTerrain`, qui exige un mailleur lisse).
- Mesures faites sur un seul processus par méthode et par taille, sans répétition (variabilité non chiffrée).

## Fonctionnalités manquantes et adaptations nécessaires pour C

Manque dans le prototype : arbres, rochers, maisons et constructions du joueur (tout repose sur `LabWorld` / `TerrainField`) ; placement et occupation (`OccupancyMap`, `PlacementSystem` lisent `TerrainField.top`) ; raccords de chemins, aplanissement de maisons (`HousePad`, `TerrainEditor`) ; éditeur de carte 2D (relief, masque, annulation Ctrl+Z : le pinceau C est un `do_sphere` direct, sans couches ni masque, et l'annulation de Voxel Tools n'est pas branchée) ; sous-face de l'île (croûte constante de 2 m, pas de cône rocheux) ; shader d'ÉCLATS à pixels de 2 cm (remplacé par un shader simple : couleur par voxel de 20 cm + liseré) ; fusion des faces (triangles ×5) ; île d'ouverture (cartes sculptées à la main, cache de maillage).
Adaptations : écrire un `VoxelGeneratorScript` (ou un graphe) pour chaque source de relief ; faire lire la hauteur du sol à tout le gameplay par `VoxelTool` au lieu de `TerrainField` ; compiler les modèles d'export avec le module ; remplacer le mailleur ou écrire un mailleur fusionnant pour retrouver le coût de A/B ; décider du format de sauvegarde (SQLite de Voxel Tools contre carte v3 par couches).

## Limites de la comparaison

- C et B partagent la même famille de bruit (crêtes, vallées, déformation) : la différence entre B et C est celle du **pipeline** (stockage, maillage, collisions), pas du relief.
- Les reliefs de B et C sont plus accidentés que A au point de ressembler à du bruit sur les flancs (voir planche 2) : l'amplitude n'a pas été réglée finement.
- Un seul plan de départ pour la reproductibilité et les chemins (graine 21) ; la graine 7 n'a que la vue aérienne.
- Aucune évaluation à la souris sur PC ni sous GPU (voir plus haut).

## Recommandation

Voir le message de livraison : elle s'appuie sur ces chiffres et sur les planches.

## Fichiers

`scripts/map/plan_terrain.gd` (méthodes B et S) · `scripts/voxel_proto/` (C) · `materials/voxel_blocky.gdshader` · `scripts/map/map_island.gd` (méthode) · `scripts/menu/main_menu.gd` (sélecteur) · `tools/comparatif_terrain.gd` (captures, vérifications, mesures) · `tools/comparatif_planches.py` · `tools/build_godot_voxel.sh` · `tests/run_checks_comparatif.gd` · données : `docs/captures/comparatif-terrain/*.json`.
