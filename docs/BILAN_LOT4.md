# Bilan — Lot 4 : refonte structurelle de la génération et de la cohérence graphique

Principe : **corriger les causes, pas les symptômes**. Tout ce qui est décrit ici est une règle générale du code
(aucune retouche propre à une île) ; `docs/GENERATION_MONDE.md` décrit les règles en détail.

## 1. Audit : d'où venaient les défauts du Lot 3

| Symptôme observé | Cause d'architecture (Lot 3) | Remède du Lot 4 |
|---|---|---|
| Objets qui flottent, arbres plantés dans les murs, rochers sur les chemins | la colonie était un **plan à coordonnées fixes** (`VillageLayout`) ; la pose d'objets lisait le sol sans jamais le valider | **PlacementSystem** : chaque objet décrit ses besoins (`PlacementSpec`), toute pose est validée (11 contrôles), refus explicite sinon |
| Bâtiments qui « traversent » le terrain ou reposent dans le vide | bâtiments = assets cuits de taille fixe, posés sur un terrain sculpté pour eux à la main | **TerrainEditor** : plateforme + talus ou soutènement, calculés pour le site ; **BuildingPlanner/Builder** : fondation enterrée de 20 cm, sol fini à 20 cm au-dessus du terrain |
| Intérieurs impraticables (murs pleins, portes décoratives) | maisons = volumes extérieurs sculptés | bâtiments **visitables par conception** : plan (pièces, portes ≥ 1,00 × 2,10 m), escalier 20 × 30 cm, mobilier par fonction, validé voxel par voxel pour un personnage de 1,80 m |
| Style « maison de poupée », toits en escalier, façades propres | assets uniques, peu de variation, couleurs saturées | générateur d'architecture de **survivants** (moellons, enduits usés, colombages, toits rapiécés, appentis, réemplois), couleurs désaturées |
| Arbres flottants, branches coupées, racines sur la pente | arbres cuits à partir d'une forme fixe, posés à la hauteur du sol sous le tronc | **TreeGenerator** paramétrique : squelette connexe, socle jusqu'au sol le plus bas, racines qui plongent dans le relief réel, contrôle de connexité |
| Rochers « posés » comme des meubles | 4 modèles uniques | **RockGenerator** : 4 familles, strates, fissures, enfoncement, contrôle des pièces flottantes |
| Bateau décoratif (voiles qui se croisent, mâts traversant) | modèle unique sculpté à la main | **ShipGenerator** paramétrique + **PortBuilder** (ponton haubané) ; voiles séparées, vérifiées voxel par voxel |
| Cristaux, socle de l'Ancre et matières claires **blanchis** | émission des matériaux constante, halo (glow) sans seuil, point blanc du tonemapper bas | **EnvironmentManager** : émission pilotée par l'ambiance (0,2 de jour → 1,0 la nuit), seuil HDR du halo, point blanc relevé, plafonds dans `config/environment.json` |
| Nuages en blocs, ciel plat | ciel et nuages codés dans une seule scène | nappes de nuages **doux** 3D + ciel continu, brume atmosphérique, **îles lointaines**, fondu entre ambiances, cycle jour/nuit |
| Chaque correction à refaire pour chaque île | aucune validation | **WorldValidator** + `tools/world_report.gd` : 15 familles de contrôles sur l'état FINAL, multi-graines |

## 2. Ce qui a été livré

- **Architecture modulaire déterministe** (`scripts/world/…`) : profil JSON + graine → terrain → colonie → nature →
  voxélisation → modèles → validation ; un flux aléatoire par étiquette (ajouter un générateur ne décale pas les
  autres). Pipeline chronométré, modèles calculés en parallèle (recouvrement avec la voxélisation du terrain).
- **Terrain hiérarchique** avec 3 profils (`settled`, `verdant`, `rocky`) : silhouette → relief (dôme, collines,
  plateaux) → espaces habitables détectés → falaises → matières → sous-face ; cœur fixe défini à partir du relief
  naturel, jamais entamé (écriture refusée au niveau du champ de colonnes).
- **Placement universel** : spec (emprise, volumes durs/mous, support, enfoncement, marge de falaise, zones,
  matières, exceptions déclarées, accès), réservations d'espace, statistiques de refus par raison.
- **Colonie** : place, port, sanctuaire de l'Ancre, parcelles, routes (A\*, marches), bâtiments, potagers, décor ;
  site cherché par balayage régulier de la couronne voulue ; terrassement mesuré ; annulation propre si la route est
  impossible.
- **Bâtiments de survivants** : 6 archétypes, plan en cellules de 10 cm, volumes, détails en microvoxels de 2 cm,
  **mobilier** (lits, tables, bancs, étagères, établis, comptoirs, tonneaux, caisses, sacs…), **validateur voxel**.
- **Nature** : 7 espèces d'arbres, 4 familles de rochers, plantes en amas selon le biome.
- **Port** : ponton haubané (tablier, portiques, haubans de 2 cm, passerelle) et **bateau paramétrique** amarré.
- **Environnement centralisé** (`EnvironmentManager`, `config/environment.json`).
- **Validation automatique** (`WorldValidator`) et outils : `world_report.gd` (diagnostic JSON), `world_capture.gd`
  (captures multi-vues), `world_perf.gd` (mesures), `scene_check.gd` (chargement de la scène F9).
- **Scène F9** (`scenes/world/settled_island.tscn`) : génération dans un fil d'exécution, 10 vues, ambiances avec
  fondu, cycle jour/nuit, changement de graine / profil, rapport de validation (V).
- **Documentation** : `GENERATION_MONDE.md`, ce bilan, README, ARCHITECTURE, DIRECTION_ARTISTIQUE mis à jour.
- La colonie du Lot 3 (F4) est **conservée** telle quelle pour comparaison.

## 3. Mesures

Île habitée, graine 3 (8 bâtiments, 26 arbres, 16 rochers, 23 objets posés, 5 073 plantes), Godot 4.3, Linux, **4 cœurs,
rendu OpenGL logiciel (llvmpipe), aucune mesure GPU** (`tools/world_perf.gd`, JSON dans `docs/mesures_lot4.json`) :

| Mesure | Valeur |
|---|---|
| Génération complète (profil + graine → `WorldData`) | **22,8 s** |
| … terrain hiérarchique | 3,8 s |
| … colonie (place, port, sanctuaire, 8 bâtiments terrassés, routes, potagers, décor) | 3,9 s |
| … nature (placement : arbres, rochers, plantes) | 0,8 s |
| … voxélisation du terrain (en parallèle des modèles) | 3,8 s |
| … modèles (8 bâtiments, 26 arbres, 16 rochers, ponton, bateau : voxels + maillages à 3 LOD, fils d'exécution) | 14,4 s de temps réel, dont 10,6 s après la voxélisation |
| Mise en scène (création des nœuds, maillage du terrain par chunks) | 4,1 s |
| Mémoire statique après génération / pic | 347 Mo / 404 Mo |
| Cache de maillages (objets identiques) | 110 réutilisations / 100 maillages calculés |
| Nœuds | 584 `MeshInstance3D`, 220 `MultiMeshInstance3D`, 52 lumières, 32 collisions de scène (404 boîtes de collision de bâtiments) |

Triangles par catégorie et niveau de détail (LOD0 / LOD1 / LOD2, avant culling) :

| Catégorie | LOD0 | LOD1 | LOD2 |
|---|---|---|---|
| Terrain (20 cm) | 267 434 | – | – |
| Bâtiments (8) | 282 080 | 16 372 | 9 702 |
| Arbres et rochers (42) | 301 242 | 53 382 | 9 590 |
| Plantes (MultiMesh, 5 073 instances) | 1 205 338 | 432 038 | – |
| Objets cuits (Lot 3) | 268 950 | 80 898 | 9 226 |
| Ponton / amarres | 16 346 / 2 092 | – | – |
| Bateau | 59 884 | 15 058 | 2 142 |

Une vue réelle (ce qui est effectivement dessiné, après distances de visibilité et culling) :

| Vue | Appels de dessin | Objets | Primitives |
|---|---|---|---|
| Ensemble (40 m de haut) | 1 215 | 1 541 | 1,43 M |
| Place (au sol) | 1 333 | 1 634 | 3,40 M |
| Île vue de loin (150 m) | 971 | 1 300 | 0,72 M |

Gains mesurés pendant le Lot 4 : détails de bâtiments (battants, volets, meubles) ramenés à 3 variantes + cache par
contenu : modèle + maillages d'un bâtiment 3,9 s → 2,6 s en moyenne (mesure séquentielle) ; rastérisation d'une formation
rocheuse 757 ms → ≈ 420 ms (moyenne de 6 graines) ; la voxélisation du terrain (3,8 s) est recouverte par le calcul
des modèles en fils d'exécution.
Le poste dominant restant est le maillage glouton écrit en GDScript (≈ 1 µs par cellule) ; voir « Compromis »
et la validation GPU. Les 3,4 M de primitives de la vue « place » viennent surtout des 5 000 plantes en 2 cm
(LOD0 < 16 m) : à valider sur GPU, réglable (`plant_density`, distances).

## 4. Contrôles AUTOMATIQUES (exécutés ici, sans GPU)

| Suite | Contenu | Résultat |
|---|---|---|
| `tests/run_checks.gd` (Lots 1 à 3) | 180 contrôles conservés (palette, grille, maillage, assets, pixels 2 cm, LOD, instanciation, plan de village, ambiances, scènes) | **180 / 180** |
| `tests/run_checks_lot4.gd` (rapide) | graines, terrain (3 profils, déterminisme, cœur), placement (refus, exceptions, accès), terrassement, 12 bâtiments × 2 graines (visitabilité, style), 7 espèces d'arbres, pente, 12 rochers, 4 bateaux, ponton, environnement | **120 / 120** |
| `… -- --monde` | 4 îles complètes (2 habitées, 1 verdoyante, 1 rocheuse) : 0 erreur de validation, présence de la colonie / du port / du bateau, déterminisme (signature identique) | **+15, 135 / 135** |
| `tools/world_report.gd` | diagnostic multi-graines (JSON) | 0 erreur sur les graines 1 à 4 (habitée) |

Le validateur contrôle : cœur fixe respecté, cellules de terrain isolées, intersections de volumes durs, objets
flottants (support recalculé sur le terrain final), bâtiments traversés par le terrain, fondations portées, intérieur
visitable (portes, escaliers, tête à 1,80 m, meubles hors des zones de porte, colliders cohérents), arbres (bois d'un
seul tenant, pied enraciné, feuillage rattaché), rochers (aucune pièce flottante), routes continues, entrées /
sanctuaire / port reliés à la place, ponton et bateau (voiles, mâts, terrain, ponton), déterminisme.

Ce que le validateur a réellement trouvé pendant le développement (preuve qu'il fonctionne) : un collider de mur
d'annexe hors du mur (porte de l'annexe comptée dans le mur principal), des entrées bloquées par la « cour »
incluse dans le volume dur, des barreaux de garde-corps du ponton flottants, des éclats de bois d'arbre isolés, des
rochers dont une pièce flottait.

## 5. Validations VISUELLES / GPU encore nécessaires (sous Windows)

Les captures ci-dessous viennent d'un rendu OpenGL **logiciel** (mode Compatibilité, sans SSAO, 1–2 images/s).
À valider sur votre machine :

1. **Fluidité réelle** (FPS) et temps de chargement : les durées de génération mesurées ici (4 cœurs, sans GPU) sont
   une borne haute ; la mémoire GPU et les appels de dessin doivent être relevés avec un vrai GPU.
2. **Rendu Forward+** : SSAO, ombres 4 cascades, tonemapping Filmic — le contraste diffère du mode Compatibilité.
3. **Surexposition** : confirmer que cristaux, socle de l'Ancre et matériaux clairs ne blanchissent plus de jour, et
   que les lanternes / le feu restent lisibles la nuit (réglages : `emission_scale`, `glow` dans `config/environment.json`).
4. **Nuages doux** : coût de remplissage des 4 nappes (shader à 4 octaves) sur GPU intégré ; réglable
   (`CloudLayer.LAYERS`).
5. **Lisibilité** des feuillages à 20 cm et des toits à la résolution de votre écran ; goûts sur les couleurs
   (désaturées par rapport au Lot 3).
6. **Intérieurs** : éclairage de jour (`interior_lamp_min`), échelle ressentie à 1,80 m.

## 6. Compromis techniques assumés

- **Temps de génération** (~20 s sur 4 cœurs sans GPU) : maillage glouton en GDScript, principal poste. Les
  modèles sont calculés en parallèle et en recouvrement avec la voxélisation ; un cache de maillages par contenu
  évite de remailler les objets identiques ; pistes : maillage en C++ / GDExtension, génération progressive.
- **Programme de colonie partiel sur petites îles** : si l'île ne peut pas accueillir tous les bâtiments, les
  derniers sont refusés explicitement (rapport) plutôt que posés de force. Une île de 24 m de rayon en reçoit 5 à 8.
- **Feuillage à 20 cm** (arbres) et **bois à 10 cm** : la règle « terrain 20 cm / détails ≥ 2 cm » est respectée ;
  les feuilles ne sont pas modélisées au pixel (coût en triangles). Le shader apporte la variation de pixels de 2 cm.
- **Voiles en tissu de 2 cm** avec léger bombement : plus de 100 000 cellules par voile, maillées une fois.
- **Collisions** : boîtes simplifiées (murs, planchers, marches, foyer, meubles) ; pas de collisions d'arbres ni de
  navmesh ; le validateur de marche utilise les voxels, pas le moteur physique.
- **Mobilier** : 3 variantes par type (limite le temps de maillage) ; rotation par quarts de tour.
- **Îles lointaines** : silhouettes sans collision, à faces plates, sans détail (volontairement).
- Les nuages du **ciel** restent un shader de ciel ; les nappes 3D donnent la parallaxe.

## 7. Limites connues et pistes

- Le port exige un rivage à plateforme possible et ≥ 8 m de vide ; sinon il est refusé (rapport).
- Les routes ne contournent pas les bosquets déjà posés (les couloirs sont réservés avant les arbres).
- L'escalier des grandes maisons occupe une travée entière ; pas encore d'escaliers droits avec palier.
- Aucun habitant, aucune physique du bateau, pas d'ouverture des portes côté jeu (les battants sont fixes, ouverts).
- Pistes : toitures à pans multiples, étages sur les annexes, enseignes par métier, jardins clos, génération
  progressive par chunks, maillage GDExtension, validation intégrée à l'éditeur.
