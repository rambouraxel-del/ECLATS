# Construction joueur et maisons (Lots 8 et 9)

Accès : **Menu → Outils développeur → Laboratoire — salle grise** (ou île vide), puis **B**.
La salle grise sert d'**atelier** : sol plat, on y construit, enregistre et rouvre des maisons.

## Mode construction (B)

| Touche | Action |
|---|---|
| **1 – 8** | Sol · Fondations · Mur · Porte · Fenêtre · Pièce · Toit · Modifier |
| clic gauche | premier coin / second coin (aperçu verrouillé), ou cible directe pour porte, fenêtre, toit |
| clic droit · **X** | annuler l'aperçu (rien n'est débité) |
| **Entrée** | confirmer (c'est là que le stock est débité) |
| **Ctrl+Z** | défaire la dernière pose (stock rendu) |
| **PgUp / PgDn** | niveau actif (0 à 2) ; les autres niveaux sont atténués |
| **H** · **G** | hauteur du mur (2,0 / 2,5 / 3,0 m) · hauteur de toute la pièce |
| **O** · **M** | côté de la porte d'une pièce · matière des murs |
| Modifier : **J / K / Y** · **Suppr** | raccourcir / prolonger / changer d'extrémité · retirer le mur, le sol, le toit ou l'ouverture visée |
| **Tab** | libérer la souris pour cliquer le panneau |

Grille de **0,50 m**. Le réticule est aimanté à la grille et aux bords des éléments déjà posés (repère blanc = grille, bleu = bord).
Murs de 20 cm, fenêtre 1,0 × 1,0 m (allège 0,8 m), porte 1,0 × 2,0 m. Les ouvertures sont de **vraies découpes** : le mur est reconstruit en morceaux (pans, linteau, allège) et chaque morceau a sa collision ; le passage d'une porte est libre.

### Ce qui est refusé (et expliqué dans l'aperçu, construction intacte)
- mur ou sol qui en chevauche un autre ; sol d'étage posé sur moins de la moitié d'un sol inférieur ; mur d'étage sans sol dessous
- ouverture à moins de 0,5 m d'une extrémité ou d'une autre ouverture ; porte à l'étage ; fenêtre sur un mur trop bas
- **modification qui rend une ouverture incompatible** (mur raccourci sous une porte, mur abaissé…) : l'aperçu est rouge, la phrase dit laquelle, rien ne change
- toit sur un niveau qui porte un étage ; second toit sur la même emprise
- pose plus chère que le stock

## Coûts (stock de démonstration — ce n'est pas l'économie du jeu)

Tarif **1 unité / m²**, toujours **arrondi à l'unité supérieure**, uniquement des entiers affichés.

| Élément | Coût |
|---|---|
| Sol, fondations | surface (1 m² → 1 ; 1,50 × 1,50 m = 2,25 m² → **3**) |
| Mur | longueur × hauteur (les ouvertures n'en retirent pas) |
| Toit | surface des deux pans (pente 1/2, débord 30 cm) |
| Porte / fenêtre | forfait 4 / 2 |
| Pièce | plancher + 4 murs + porte, chacun arrondi |

**Règle provisoire de redimensionnement** : on paie la **différence** entre le nouveau coût et l'ancien (chacun arrondi à l'unité supérieure) ; une différence négative est **remboursée** ; retirer un élément rembourse son coût. Exemple : un mur de 6 m × 2,5 m (15) prolongé de 0,5 m (17) coûte 2.
Une pose refusée, ou annulée avant confirmation, **ne débite rien**. Le stock de départ est de 200 unités (bouton « Recharger » pour les essais). Hors périmètre : prix des matériaux, récolte, progression.

## Étages et toits
Un niveau = 3,0 m sol à sol. Un mur dont un sol est posé au-dessus monte jusqu'à ce sol. Un toit à deux pans se pose sur le dernier niveau, **ajusté au rectangle des murs** reliés (faîtage le long du grand côté). Pas d'escalier pour l'instant : l'étage se voit et se construit, il n'est pas encore accessible à pied.

## Vérifié
Voir `BILAN_LOT8_9.md`. Tests : `tests/run_checks_lot8.gd` (headless) ; essai joué : `tools/lot8_recette_atelier.gd`.

## Enregistrer et rouvrir une maison (atelier)

Dans le mode construction : **Enregistrer / ouvrir une maison…** → nom → *Enregistrer* (fichier `maisons/<nom>.eclats-maison.json` dans les données du jeu ; le chemin complet est affiché). *Ouvrir* rend la maison modifiable, devant le joueur (annulable, gratuit : l'atelier n'est pas une économie).

Format **`eclats-construction` v1** (distinct de `eclats-carte`) : `{format, version, name, dims, materiaux, tarif, elements[]}`. Les coordonnées sont des entiers en demi-mètres, normalisées (coin minimum à 0). Il conserve **dimensions, niveaux, matériaux, ouvertures et toit**. Un fichier abîmé, d'une version plus récente, ou qui est en fait une carte est refusé avec une phrase d'explication et la construction en cours est gardée.

## Placer une maison sur une carte (éditeur d'îles, outil 9 « Maisons »)

1. Choisir un modèle (exemple fourni ou maison de l'atelier). **R** : tourner d'un quart de tour.
2. Viser la parcelle : l'**aperçu** montre l'emprise (verte = possible, rouge = refusée), la porte, le **raccord prévu jusqu'au chemin**, et dit pourquoi en cas de refus.
3. **Clic** : pose. **Ctrl+Z** : retire la maison **et** restaure le terrain (une opération). Clic droit sur une maison : la retirer (le terrain aménagé reste).

Ce que fait la pose (`HousePad`, mêmes règles que l'atelier du Lot 6) :
- **plateforme plate** sous l'emprise (+ 60 cm de cour) au niveau médian de la parcelle, talus 1:2 ou soutènement autour ; déblai et remblai limités à 4 cellules (80 cm) chacun, soit 1,60 m de dénivelé rattrapé. Les fondations de la maison (60 cm) reposent sur cette plateforme ;
- **raccord seuil → chemin** : bande de 1,40 m de la porte au point le plus proche d'un chemin, hauteur interpolée, matière « chemin de terre ». Au plus **14 m** et **30 %** de pente ;
- **refus expliqués, rien ne change** : hors de l'île · trop près du bord · emprise occupée (autre maison, chemin, point de départ) · relief trop accidenté · **zone protégée** (le masque est respecté : si la plateforme ou le raccord toucheraient une colonne protégée, la pose est refusée) · aucun chemin à moins de 14 m · chemin derrière la maison (tourner la maison) · raccord trop raide · maison sans porte.

Les retouches sont écrites dans les couches de relief de la carte (comme un pinceau), la maison est **embarquée dans le fichier de carte** (`eclats-carte` **v2**, champ `maisons` ; les cartes v1 se rouvrent sans changement). Dans l'île 3D (« Vérifier en 3D »), la maison est visitable : portes et fenêtres sont de vraies découpes, les arbres du décor ne poussent pas dedans.
