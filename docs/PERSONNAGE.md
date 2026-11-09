# Personnage 3D articulé — première version (branche `claude/personnage-3d-explorateur`)

Remplace l'explorateur provisoire du Lot 5 par un modèle voxel articulé, d'après la planche de référence (formes cubiques adoucies, proportions compactes, visage expressif, palette lavande / crème / cuir / kaki / laiton).

## Modèle (`scripts/game/explorer_model.gd`)
- **1,72 m en cellules de 4 cm**, affiché à l'échelle actuelle du jeu (`PlayerConfig`, 1,50 m) : capsule, yeux et caméras inchangés.
- **Proportions** : tête + cheveux + lunettes ≈ ⅓ de la hauteur, jambes courtes, bras en « A » légèrement écartés.
- **Cubes adoucis** : chaque pièce passe par `_soften()` qui retire les cellules d'angle (exposées sur 3 axes) → arêtes chanfreinées, même grille de 4 cm.
- **Détails** : cheveux bouclés irréguliers, lunettes d'aviateur en laiton relevées avec sangle et boucle, visage (sourcils, yeux, sourire, joues, barbe courte), écharpe-cape lavande avec croix sable sur la poitrine et dans le dos (pointe en V), tunique crème, gilet et ceinture de cuir à boucle, brandebourgs, tabard bleu à croix, bourse, brassards, bottes à rabat et sangle.
- **Couleurs** : 16 matières `perso_*` ajoutées **à la fin** de `config/palette.json` (identifiants existants inchangés).
- **Squelette** : 17 pivots (`Hips`, `Torso`, `Head`, `ArmL/R` + `ForearmL/R`, `ThighL/R` + `ShinL/R` + `FootL/R`, `CapeUp` + `CapeLow`, `Tabard`, `Pouch`). Chaque pièce est un maillage voxel rigide posé sur son pivot (pas de peau).
- **~2 650 triangles** (maillage glouton), un seul matériau partagé du jeu.

## Animations (vraies `Animation` dans un `AnimationPlayer`, boucles)
| Clip | Durée | Contenu |
|---|---|---|
| `idle` Attente | 3,2 s | respiration, léger déhanché, tête qui regarde à droite et à gauche, bras et cape qui bougent à peine |
| `walk` Marche | 0,9 s | balancier des jambes, genoux, bras opposés, torse qui tourne, rebond du bassin, cape et tabard qui suivent |
| `run` Course | 0,56 s | foulée ample, coudes pliés, torse penché, cape et tabard rejetés en arrière |
| `jump` Saut / chute | 1,0 s | jambes décalées, bras écartés, cape relevée |

16 images clés par boucle (interpolation linéaire). Dans le jeu, `animate(vitesse, au_sol, dt)` choisit le clip (arrêt < 0,12 · marche < 1,5 × vitesse de marche · course au-delà), fond 0,2 s entre clips et règle la vitesse de lecture sur la vitesse réelle (pas de patinage). Un décollage de moins de 0,08 s (marche d'escalier, pente) ne déclenche pas le saut.

## Intégration
`Explorer` crée toujours `ExplorerModel` et appelle `animate()` : collisions (capsule), marches, première personne (modèle masqué), bascule V, caméra à la 3e personne — aucun changement. Le modèle se construit seul dans `_ready()`.

## Galerie 3D
Nouvelle famille **Personnages** (`tools/galerie/galerie_export.gd`, `_family_character`) : le même arbre de pivots et l'`AnimationPlayer` sont exportés par `GLTFDocument` dans `personnage_explorateur.glb.gz` (≈ 40 Ko, 4 animations). La page (`galerie/app.js`) lit `animations` dans le catalogue et affiche un bouton par clip (+ « Repos »), via `THREE.AnimationMixer`. `tools/galerie.sh` regénère le tout.

## Captures et outils
- `tools/personnage_captures.gd` : planche face / profil / dos / trois-quarts, gros plan, poses des animations, images d'un cycle.
- `tools/personnage_recette.gd` : recette jouée dans le vrai jeu (voir `docs/BILAN_PERSONNAGE.md`).
- `tests/run_checks_personnage.gd` : contrôles automatiques.

## Limites
Voir `docs/BILAN_PERSONNAGE.md`.
