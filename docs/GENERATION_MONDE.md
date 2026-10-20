# Génération du monde — règles et architecture (Lot 4)

Principe directeur : **on corrige les causes, pas les symptômes**. Chaque règle ci-dessous vit à UN seul endroit
du code et s'applique automatiquement à toute île, toute graine, tout profil. Si l'on génère 100 îles demain,
aucune retouche manuelle n'est nécessaire ; si l'une d'elles viole une règle, le validateur le dit.

## 1. Pipeline

```
profil (config/profiles/*.json) + graine
   │
   ├─ 1 TerrainGenerator ─► TerrainField   silhouette → relief → plateaux → falaises → matières → sous-face
   ├─ 2 SettlementGenerator                place · port · sanctuaire · parcelles · routes · bâtiments · potagers · décor
   ├─ 3 NatureGenerator                    couloirs réservés · rochers · bosquets d'arbres · plantes en amas
   ├─ 4 TerrainVoxelizer ─► IslandData     cœur fixe + surface modifiable (grille 20 cm)
   ├─ 5 modèles (en parallèle)             bâtiments, arbres, rochers, ponton, bateau → volumes + maillages à 3 niveaux de détail
   └─ 6 WorldValidator                     rapport : erreurs / avertissements / échecs de génération
                │
        WorldData (pur données)  ──►  WorldView (nœuds)  +  EnvironmentManager (ambiance)
```

`WorldBuilder.build(profil, graine)` orchestre et chronomètre chaque phase (`WorldData.timings`). Aucun nœud
n'est créé avant `WorldView` : la génération tourne dans un fil d'exécution (la scène `F9` reste vivante).

| Module | Fichiers | Rôle |
|---|---|---|
| Flux déterministes | `world_rng.gd` | une sous-graine par étiquette (`stream(graine, "colonie")`) : ajouter un générateur ne décale jamais les autres |
| Terrain | `terrain_field.gd`, `terrain_generator.gd`, `terrain_voxelizer.gd`, `island_profile.gd` | carte de colonnes de 20 cm, relief hiérarchique, cœur fixe |
| Placement | `placement_spec.gd`, `placement_system.gd`, `occupancy_map.gd`, `world_nav.gd` | règles universelles de pose + réservations + accessibilité |
| Aménagement | `terrain_editor.gd`, `path_network.gd` | plateformes, talus, soutènements, routes (A\*, marches) |
| Colonie | `settlement/settlement_generator.gd`, `settlement/port_builder.gd` | programme du profil → île habitée |
| Bâtiments | `building/*` | plan → volumes → détails → mobilier → validation |
| Nature | `nature/tree_generator.gd`, `rock_generator.gd`, `nature_generator.gd`, `voxel_shapes.gd` | arbres, rochers, plantes |
| Bateau | `ship/ship_generator.gd`, `ship_view.gd` | coque, mâts, voiles, haubans, amarrage |
| Validation | `validation/world_validator.gd` | contrôles automatiques sur l'état final |
| Ambiance | `rendering/environment_manager.gd`, `cloud_layer.gd`, `far_islands.gd`, `config/environment.json` | éclairage, exposition, brume, nuages, îles lointaines |

## 2. Règles d'échelle (rappel, inchangées)

- Terrain : grille **20 cm**. Bâtiments, arbres, rochers, ponton : **10 cm** (feuillage d'arbre : 20 cm).
- Détails (battants, volets, meubles, cordages, plantes, voiles) : **microvoxels de 2 cm**.
- Le shader dessine **une seule couleur plate par pixel de 2 cm** (aucune image de texture, aucun détail < 2 cm).
- Jamais un nœud par voxel : un maillage par bâtiment / arbre / rocher / voile, `MultiMesh` pour les plantes.
- Personnage de référence : **1,80 m** (porte d'entrée ≥ 1,00 × 2,10 m, intérieure ≥ 0,90 × 2,00 m,
  hauteur libre 2,40 m, marche 20 × 30 cm, tête libre 1,80 m).

## 3. Terrain hiérarchique

1. **Silhouette** : rayon + harmoniques du profil (`silhouette.harmonics`) → contour irrégulier mais lisse.
2. **Relief** : dôme + collines + **plateaux** posés par disque de Poisson (`relief.plateaus`), pente maximale
   entre colonnes voisines (`max_natural_step`), quantification en paliers (`level_step_m`).
3. **Espaces habitables** : les plateaux sont *détectés et mesurés* après coup (surface, rayon inscrit, distance
   au bord) ; la colonie s'y installe, elle ne les suppose pas.
4. **Falaises, matières** : roche en haut de pente, herbe selon l'humidité (`climate`), strates.
5. **Sous-face** : cônes, racines, éclats de cristal à la pointe des cônes.
6. **Cœur fixe** défini à partir du relief NATUREL : `core_top = relief_naturel − 6 cellules`. La couche
   modifiable fait donc au plus 6 cellules (1,20 m). `TerrainField.set_top` **refuse** toute écriture sous
   `core_top + 2` : un terrassement ne peut pas entamer le cœur (vérifié par test et par le validateur).

Option de profil `relief.terrace_strength` (0 → pentes continues, 1 → paliers pleins, défaut 1) : adoucit les marches des pentes
naturelles ; les plateaux planifiés, déjà à un multiple du pas, ne bougent pas.

Profils fournis : `settled` (île habitée), `verdant` (verdoyante, forêt dense), `rocky` (rocheuse, relief accentué).
Ajouter un profil = déposer un JSON dans `config/profiles/` (aucun code).

## 4. Placement universel

Tout (arbre, rocher, bâtiment, objet, meuble, infrastructure) décrit ses besoins dans un `PlacementSpec`
(emprise, volumes durs et mous, support, enfoncement admis, marge de falaise, zones et matières autorisées,
exceptions déclarées, accès requis). `PlacementSystem.evaluate` contrôle, dans cet ordre :

| Contrôle | Raison de refus |
|---|---|
| emprise sur l'île | `hors_ile` |
| distance au vide | `trop_pres_du_bord` |
| zone du terrain (naturel, place, parcelle, route…) | `zone_interdite` |
| matière du sol | `matiere_interdite` |
| espace réservé (route, cour, place, port, potager) | `espace_reserve` |
| pente / enfoncement | `pente_excessive` |
| support réel sous l'objet | `support_insuffisant` |
| intersection du cœur fixe | `intersecte_le_coeur`, `surface_trop_mince` |
| collisions (volumes durs + marge) | `collision` |
| couronnes contre constructions | `volume_mou_dans_construction` |
| accessibilité à pied | `inaccessible` |

Un placement invalide n'est **jamais posé** : l'appelant choisit un autre site, régénère ou rejette. Chaque refus
est compté par raison (`placement.stats`) ; les échecs de génération sont listés dans le rapport. Les
**exceptions** sont explicites dans le spec (`overhang_void` : affleurement qui déborde du bord ;
`in_building` : objet à l'intérieur d'un bâtiment) — sans déclaration, la règle s'applique.

**Réservations** (`OccupancyMap`) : place, routes, cours, parcelles, potagers, port sont réservés AVANT les
objets de décor ; deux générateurs ne peuvent donc pas se disputer un espace. Les routes gardent un couloir libre
de 40 cm de chaque côté (réservé avant arbres et rochers).

## 5. Colonie

1. **Place** : meilleur espace plat (coût de terrassement minimal, proche du centre), disque pavé à médaillon.
2. **Port** : rivage choisi par balayage (plateforme évaluée, vide suffisant pour le ponton et le bateau).
3. **Sanctuaire de l'Ancre** : le plateau le plus élevé hors de la place, plateforme de 8 m, reliée à la place.
4. **Bâtiments** (programme du profil : `settlement.buildings`) : pour chacun, balayage **régulier** (pas de 1 m)
   de la couronne voulue autour de la place (entrepôt : près du port) ; par site, `evaluate_pad` mesure le
   coût de terrassement ; façade tournée vers la place ; plateforme + talus 1:2 ou **soutènement** (maçonnerie
   sur les flancs exposés) ; parcelle et cour réservées ; placement validé ; **route possible** vérifiée avant
   d'aménager, annulation propre sinon (`_snapshot/_restore`). Repli : couronne élargie à toute l'île.
5. **Routes** (`PathNetwork`) : A\* (réutilise les routes existantes), hauteurs lissées, marche ≤ 20 cm entre
   cellules voisines (`STAIR` quand le niveau change), jamais dans le cœur fixe.
6. **Potagers, décor de place, marché, objets du port** : posés par le placement universel, dans leurs zones.

Si l'île est trop petite pour tout le programme, les bâtiments en trop sont **refusés explicitement**
(rapport : « aucun site valide »), jamais posés de force.

## 6. Bâtiments (style « survivants »)

Archétypes (`BuildingCatalog`) : maison, grande maison (2 niveaux, escalier), atelier, entrepôt, échoppe,
maison commune. Un archétype décrit un **programme** (pièces, fonctions), jamais une coordonnée.
`BuildingPlanner` → `BuildingPlan` (cellules de 10 cm, source unique de vérité) → `BuildingBuilder` (volumes)
→ `BuildingDetails` (battants, volets, claustras, lanternes, feu) → `BuildingFurnisher` (mobilier par fonction).

- Matières : moellons irréguliers, enduits usés qui laissent voir la pierre, bois vieilli, colombages,
  toitures de chaume / bardeaux / tuiles et lauzes rapiécées (profils extrudés de 2 cm), cheminées, appentis
  d'extension, éléments de réemploi. **Interdits** : grandes baies vitrées, façades symétriques « propres »,
  toits en escalier (testé : aucune vitre, fenêtres ≤ 0,6 × 0,8 m).
- **Visitables par conception** : murs percés d'ouvertures réelles, sol à 20 cm du terrain (une marche),
  escalier 20 × 30 cm avec 1,80 m de tête, meubles hors des zones de porte et sans bloquer le passage
  (parcours de 50 cm vérifié à chaque ajout ; sinon le meuble est retiré).
- `BuildingValidator` contrôle sur les **voxels** : un personnage de 1,80 m peut marcher de l'extérieur jusqu'au
  centre de chaque pièce (étages compris) ; portes aux bonnes dimensions ; colliders cohérents avec le volume.

## 7. Nature

- **Arbres** (`TreeGenerator`) : squelette paramétrique (tronc effilé, branches continues, sous-branches),
  racines de surface qui plongent dans le sol RÉEL, socle sous le tronc jusqu'au point le plus bas, feuillage en
  amas centrés sur des extrémités de branches. 7 espèces ; espèce selon l'humidité du sol et bosquet.
- **Rochers** (`RockGenerator`) : 4 familles (bloc isolé, affleurement en strates, formation de colonnes,
  vestiges minéraux), toujours enfoncés, aucune pièce flottante.
- **Plantes** : amas par biome, jamais sur zone bâtie, route, emprise réservée ni roche nue.
- **Port** : ponton haubané (tablier sur semelle de maçonnerie, portiques, haubans de 2 cm), bateau paramétrique
  amarré le long du ponton (passerelle, amarres).

## 8. Validation automatique (`WorldValidator`)

Calculée sur l'**état final** : si un terrassement tardif casse un placement précoce, l'erreur apparaît.

`terrain.coeur` · `terrain.cellules_isolees` · `objets.intersections` · `objets.flottants` (support recalculé) ·
`objets.batiment_traverse` · `batiments.fondations` · `batiments.interieur` · `arbres.ancrage` · `rochers.enfonces` ·
`circulation.routes` · `circulation.entrees` · `circulation.sanctuaire` · `circulation.port` · `port.ponton` ·
`port.bateau` (voiles, mâts, ponton, terrain) · déterminisme (`WorldValidator.signature`).

Outil de diagnostic :

```
godot --headless -s tools/world_report.gd -- settled 1,2,3 rapport.json [--rapide] [--determinisme]
```

## 9. Étendre

- **Nouvelle île** : un JSON dans `config/profiles/`.
- **Nouveau bâtiment** : une entrée dans `BuildingCatalog.ARCHETYPES` + un `_layout_*` dans `BuildingPlanner`.
- **Nouvelle espèce d'arbre / famille de rocher** : une entrée dans `TreeGenerator.SPECIES` / `RockGenerator`.
- **Nouveau contrôle** : une méthode dans `WorldValidator` (elle s'applique ensuite à toutes les îles).
