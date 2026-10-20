# Direction artistique d'ÉCLATS

Document de référence pour **toutes** les créations graphiques du projet (assets, bâtiments,
décors, structures, terrain, éclairage), y compris celles générées par IA ou par script.
Les cinq planches de concept (`docs/references/`) sont les références permanentes :

| Planche | Contenu | Sert de référence pour |
|---|---|---|
| `planche_1_structures_anciennes.webp` | Piédestal d'ancre, marqueur de téléportation, amas de cristaux, coffre à reliques, colonnes en ruine, brasero rituel, piédestal sculpté, arche, console ancienne, pilier à bannière | Technologie ancienne, ruines, cristaux |
| `planche_2_village_exterieur.webp` | Puits, étal, bitte d'amarrage, garde-corps, jardinière, banc, kiosque à auvent, chariot, tonneaux, sanctuaire | Village, extérieur, commerce |
| `planche_3_eclairage_decor.webp` | Lampadaire, applique, suspension, porte-bannière, panneau, tableau d'affichage, paravent, fontaine, brasero | Éclairage et décor |
| `planche_4_artisanat_stockage.webp` | Établi, râtelier d'outils, caisse, tonneau, table à cartes, forge, lavabo, étagère, cabinet d'alchimie, coffre | Artisanat, rangement |
| `planche_5_mobilier.webp` | Chaise, tabouret, table, bureau, banc, coffre, armoire, étagère murale, lit, table d'appoint | Mobilier |

Ce sont des références de **style et de qualité**, pas des plans : on s'en inspire pour des
modèles originaux, avec la même identité.

## 1. L'identité en une phrase

*Voxel fantasy artisanal et chaleureux : de la pierre claire, du bois travaillé, du cuivre et
quelques éclats de cristal lumineux, patinés par la mousse et le lierre, sous une lumière dorée.*

## 2. Motifs signatures (à retrouver dans chaque création)

1. **Pieds de pierre claire** : tout ce qui est en bois repose sur un ou deux blocs de pierre
   ébréchés (poteaux, pieds de banc, coins de coffre).
2. **Ferrures de cuivre** : capuchons à gradins au sommet des poteaux, bagues, équerres en L
   aux angles, bandes rivetées. Le cuivre est le métal « de structure » ; le laiton et l'or
   servent aux détails nobles (serrures, balances, losanges) ; le fer noirci aux rivets, poignées
   et outils.
3. **Textile bleu à losange** : bannière, chemin de table, couverture. Fond bleu, liseré crème,
   losange crème à cœur sarcelle, franges crème en bas. Le losange est l'emblème d'ÉCLATS.
4. **Cristal bleu** : seul élément à émission forte, utilisé avec parcimonie (serrure, piédestal,
   présentoir). Les cristaux sont prismatiques, pointus, en grappes inclinées.
5. **Lumière chaude** : lanternes de cuivre à verre ambré, bougies. Contraste voulu avec le
   bleu froid des cristaux.
6. **Vie végétale** : lierre qui retombe des angles et des poutres, petites touffes de feuillage
   fleuries (fleurs blanches, parfois violettes), mousse sur la pierre (jamais sur le bois).
7. **Assemblages visibles** : tenons, chevilles, rainures entre planches, joints de maçonnerie
   en creux, rivets. Rien n'est un bloc plein sans détail.

## 3. Matières et palette

La palette unique est `config/palette.json` (terrain et objets partagent les mêmes matières).
Familles :

- **Pierre** : `stone_light` (claire, dominante), `stone_carved`, `stone_shade` (joints, ombres).
  Teinte par bloc entier, pas par voxel ; arêtes ébréchées ; mouchetis rare.
- **Bois** : `wood_planks`, `wood_honey`, `wood_light`, `wood_dark`, `wood_red`. Marron chaud et
  désaturé (pas d'orange vif). Planches à lames de teintes variées, rainures nettes.
- **Métaux** : `copper` (#c27a48), `brass`, `gold`, `iron`, `iron_dark`, `copper_patina`.
- **Cristaux** : `crystal_blue`, `crystal_deep`, `crystal` ; chauds : `crystal_warm`,
  `lantern_glow`.
- **Textiles** : `fabric_blue`, `fabric_cream`, `fabric_teal`, `fabric_wine`, `rope`.
- **Végétal** : `ivy`, `leaves`, `leaf_light`, `moss`, `flower_white/yellow/violet`.

Règles : couleurs naturelles et légèrement désaturées ; jamais de vert ou de rouge « pur » ;
le bleu et l'orange sont les deux seules couleurs vives, et elles sont rares et ciblées.
Toute nouvelle matière s'ajoute **à la fin** de la palette (les identifiants ne bougent pas).

## 4. Échelles et résolutions

| Élément | Résolution | Remarque |
|---|---|---|
| Terrain, grille de construction | **20 cm** | inchangé, `VoxelGrid.VOXEL_SIZE` |
| Objets, meubles, décors | **2 cm** (microvoxel) | `VoxelGrid.DETAIL_SIZE`, 10 par voxel de terrain |
| Végétation basse | 2 cm | touffes, fleurs, fougères |

Une emprise d'objet est toujours un **multiple de 20 cm** (placement sur la grille) ; la hauteur
peut l'être aussi (arrondie vers le haut). Les détails minimaux sont de 1 microvoxel (2 cm) :
rivets, chevilles, franges. Un détail plus petit n'a pas d'intérêt. Un objet de 1 m de haut
mesure donc 50 microvoxels : on y met de la finition, pas du bruit.

Proportions de référence (en m) : établi 2,00 × 1,00 × 2,00 ; coffre 1,20 × 0,80 × 0,80 ;
banc 1,80 × 0,60 × 1,00 ; étal 2,40 × 1,60 × 2,60 ; piédestal 1,60 × 1,60 × 2,40.
Les personnages jouables feront environ 1,80 m.

## 5. Silhouettes et volumes

- Une silhouette lisible **à 10 m** : masse principale claire, 2-3 éléments secondaires
  (auvent, dossier, couvercle bombé), jamais un parallélépipède nu.
- Casser les rectangles : couvercles à gradins, chanfreins sur les poteaux, frontons, plans
  octogonaux, griffes, consoles.
- Éviter les clichés « Minecraft » : gros cubes isolés, escaliers de cubes, barrières, lanternes
  génériques, textures répétitives, HUD à cœurs.
- Les détails fins se concentrent aux **points de contact** (assemblages, serrures, poignées) ;
  les grandes faces restent calmes pour que l'œil respire.

## 5 bis. Règle des pixels de 2 cm (Lot 3, impérative)

Toutes les surfaces sont dessinées en **pixels de 2 cm, une seule couleur plate par pixel**.
Pas de texture image, pas de dégradé, pas de détail plus fin que le pixel. La richesse vient de la
**variation de nuance d'un pixel à l'autre** (bois veiné, pierre mouchetée, pavés, strates…), jamais
d'un aplat uni ni d'une image plaquée.

- Un voxel de terrain (20 cm) = 10 × 10 pixels ; un voxel de bâtiment (10 cm) = 5 × 5 ; un microvoxel d'objet (2 cm) = 1 pixel.
- Les motifs sont calculés par le shader avec des fonctions de hachage entières, au pixel près : mêmes
  résultats sur toutes les machines, aucune dépendance à des fichiers d'image.
- Les nuances sont quantifiées en 3 à 5 tons francs (esprit pixel-art) ; à grande distance elles
  s'estompent vers la teinte moyenne pour éviter le scintillement.
- Une matière est décrite par une couleur de base + un `style` + une `usure` (`config/palette.json`).
  Ne jamais créer de matière « unique » pour un objet : réutiliser et nuancer.

## 6. Rendu (shader `voxel_stylized.gdshader`)

- **Aucun contour entre faces coplanaires** : le maillage fusionne les faces identiques.
- **Aucune variation de couleur par cellule de voxel** : les nuances viennent du shader, par
  pixels de 2 cm (voir §5 bis) et par grandes zones de plusieurs mètres.
- Herbe : plaques plus sèches par zones ; les flancs des voxels d'herbe passent à la terre avec
  une lisière irrégulière (transition herbe/terre/roche douce).
- Pierre : strates ; bois : fibres ; tissu : trame fine ; cristal : cœur lumineux renforcé aux
  bords et pulsation lente ; tissus suspendus : léger balancement.
- Occlusion ambiante par sommet (coins plus sombres) + SSAO en Forward+.

## 7. Lumière et ambiance

- Soleil chaud (heure dorée par défaut sur l'île), ombres douces, ciel clair, brouillard léger.
- Ambiance contemplative : peu de contraste agressif, pas de noir pur.
- Les lumières d'objets sont **ponctuelles et faibles** (`OmniLight3D`, 0,4 à 2,5 d'énergie,
  portée 1 à 7 m) ; une seule lumière avec ombres par asset au maximum.
- Préréglage de présentation : `presentation` (config/lighting.json).

## 7 bis. Checklist avant d'accepter un nouvel asset

- [ ] Au moins 3 motifs signatures (§2) présents.
- [ ] Silhouette non rectangulaire, lisible de loin.
- [ ] Emprise multiple de 20 cm ; origine au coin minimum, au sol.
- [ ] Palette uniquement (§3) ; pas de nouvelle teinte vive.
- [ ] Aucune face interne ; budget triangulaire respecté (§8) ; un `MeshInstance3D` par pièce.
- [ ] Collisions simplifiées en boîtes, lumières peu nombreuses.
- [ ] Capture de comparaison face à la planche de référence.

## 8. Budgets techniques

| Catégorie | Triangles (indicatif) |
|---|---|
| Petit objet (coffre, banc) | ≤ 15 000 |
| Mobilier / établi | ≤ 25 000 |
| Structure complexe (piédestal) | ≤ 45 000 |
| Bâtiment / kiosque | ≤ 70 000 |

Un maillage glouton réduit nettement ces nombres sur les grandes surfaces ; si un asset dépasse
son budget, simplifier les détails cachés (derrière, dessous) avant de réduire les détails
visibles.

## 9. Workflow pour créer un asset

1. Choisir la planche de référence et noter 3 détails à reprendre.
2. Écrire `scripts/assets/props/<id>.gd` avec `AssetKit` (voir `docs/ASSETS.md`), l'enregistrer
   dans `AssetLibrary`.
3. `godot --headless -s tools/bake_assets.gd -- <id>` puis aperçu avec `tools/preview_asset.gd`.
4. Comparer à la planche, ajuster, ajouter le test dans `tests/run_checks.gd`.

## 10. Catalogue des matières de surface (Lot 3)

| Style | Rendu en pixels de 2 cm |
|---|---|
| bois (`wood_*`) | fibres = rangées de pixels, tronçons de ton différent, veinures ondulées, nœuds en anneaux, bois de bout à cernes, fentes ; **usure** : neuf chaud → ancien gris-brun → usé argenté |
| pierre taillée / appareil | mouchetis en taches de 2-6 pixels, pores, éclats clairs, fissures, joints d'un pixel (assises de 22 cm), biseaux, coulures, mousse |
| roche | strates ondulées, micas, fissures profondes, érosion, mousse |
| pavés | cellules de ~18 cm, un ton par pavé, joints sombres, herbe dans les joints |
| métal | rayures d'un pixel, patine verte (cuivre/laiton) ou rouille (fer) dans les creux, arête de métal nu brillante, pixel intérieur sombre qui sépare métal et bois |
| tissu | trame en damier d'un pixel, plis en bandes, salissures |
| cristal | un ton par facette, cœur lumineux en anneaux, bord sombre d'un pixel, étincelles, pulsation |
| herbe | quatre verts alternés, touffes, trèfles, plaques sèches, lisière irrégulière sur les flancs, version tondue / sauvage / piétinée |
| terre | granulaire, plaques humides, cailloux, racines ; sèche / humide / fertile |
| enduit, tuiles, bardeaux, écorce, feuillage | crépi à plaques, tuiles à joints et reliefs, fibres de bardeaux, sillons d'écorce, folioles |

## 11. Architecture des survivants et ambiance (Lot 4)

**Lore** : des siècles après la chute de grandes civilisations, des survivants peu technologiques bâtissent avec ce
qu'ils trouvent.

À faire : pierre ancienne irrégulière (moellons, parfois sombres ou chauds), bois vieilli, poutres et colombages
apparents, enduits usés qui laissent voir la maçonnerie, toitures rustiques (chaume, bardeaux, tuiles et lauzes
rapiécées, patchs de teintes voisines), ouvertures étroites et irrégulières, volets, claustras, toiles, extensions
et réparations successives (appentis), éléments de réemploi (linteaux sculptés, tambours de colonne, cristaux
éteints). Intérieurs : sol de terre, planches ou dalles ; foyer en maçonnerie, mobilier de bois brut (table, bancs,
coffres, étagères, tonneaux, caisses, établi, enclume selon la fonction).

À éviter : grandes baies vitrées, tuiles modernes, façades symétriques et « propres », toitures en escalier,
bâtiments qui ressemblent à des maisons de poupée (tout est dimensionné pour un personnage de 1,80 m).

**Couleurs** : toits désaturés (ardoise grise, tuile terre cuite éteinte, bardeau brun, chaume doré terni), enduits
crème / ocre / gris usés, sols de cour de terre claire ; le vert vif est réservé à l'herbe et aux feuillages, et reste
sous la saturation du ciel.

**Ambiance** : l'émission des matériaux (cristaux, lampes, verres) est multipliée par un facteur d'ambiance
(`config/environment.json`) — environ 0,2 en plein jour, 0,6 au coucher, 1,0 la nuit — pour qu'un cristal ou le socle
de l'Ancre ne blanchisse jamais en plein soleil ; le halo ne s'allume qu'au-dessus d'un seuil HDR. Les nuages sont
**doux** (nappes continues en 3D sous l'île et à l'horizon, ciel continu) et non plus en blocs ; des silhouettes
d'îles lointaines, estompées par la distance, donnent la profondeur du monde. Les lumières intérieures restent
lisibles de jour.
