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
Un niveau = 3,0 m sol à sol. Un mur dont un sol est posé au-dessus monte jusqu'à ce sol. Un toit à deux pans se pose sur le dernier niveau, **ajusté au rectangle des murs** reliés (faîtage le long du grand côté). **Escalier** (Éditeur d'îles créatif) : outil 9, 12 marches de 25 cm (1 m × 4 m) du niveau courant au niveau supérieur ; le sol de l'étage est percé à l'emplacement de l'escalier et doit dépasser son sommet d'au moins 1 m (palier). Visuellement des marches pleines ; la collision est une rampe qui passe par le nez des marches (le joueur monte en douceur).

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

## Habitations générées (Lot 9)

Dans le laboratoire : **Habitation (3 variantes)** dans le panneau, ou `/generer habitation --variante auto|cabane|deux_pieces|en_L --graine N [--emprise 8x7] [--yaw 0-3] [--murs bois|pierre|enduit] [--toit tuiles|chaume|ardoise|bardeaux]` (barre T). L'emprise est le rectangle sélectionné ; la maison générée tient dedans.

| Variante | Agencement | Volume |
|---|---|---|
| **Cabane** | une pièce, porte au sud, une fenêtre | 3 à 5 m de large, murs de 2,0 ou 2,5 m, un toit |
| **Maison à deux pièces** | cloison avec porte intérieure, porte d'entrée dans la plus grande pièce, 3 fenêtres | 5 à 8 m, un toit |
| **Maison en L** | deux ailes reliées par une porte ; l'aile est plus profonde que large | corps bas (2,5 m) + aile haute (3,0 m), **deux toits aux faîtages croisés** |

- **Déterminisme** : à graine, emprise et réglages identiques, la même maison (même signature). `auto` choisit la variante d'après la graine parmi celles qui tiennent. Imposer une matière (`--murs`, `--toit`) ne change pas la forme.
- **Recette** affichée dans le panneau (« Recette : /generer habitation --variante en_L --graine 7 … », la variante retenue par `auto` y est écrite en clair) et **contraintes de pose** : emprise avec débord de toit, porte à orienter vers le chemin, dénivelé rattrapé (1,60 m), raccord ≤ 14 m et ≤ 30 %, jamais sur zone protégée.
- Dans le labo, la pose réutilise le **même raccord de terrain** que l'éditeur de cartes (`HousePad`) ; Ctrl+Z restaure tout. Refus expliqués : emprise trop petite (taille minimale donnée), hors de l'île, relief trop accidenté, emplacement occupé.

### Placement automatique sur un plan (éditeur de cartes, outil 9)
« **Placer automatiquement une habitation** » (variante, graine, emprise disponible) :
1. génère l'habitation ; 2. examine les emplacements des **parcelles** du plan (zones *plateau habitable* et *pelouse*, abords de 3 m compris) dans les quatre orientations, par un contrôle rapide (île, bord, occupation, masque, relief) ; 3. pour les 20 meilleurs candidats (porte proche d'un chemin, proche du centre de la parcelle), évalue l'implantation complète ; 4. retient celui dont **le raccord au chemin est le plus court et le plus doux** — l'orientation découle de l'accès — et le pose (une opération, Ctrl+Z).
**Aucune pose forcée** : sans parcelle compatible, la phrase donne le nombre d'emplacements examinés et les causes (zone protégée, relief, occupation, bord, chemin trop loin) ; sans plateau ni pelouse, ou sans chemin, le refus le dit.

### Composition « marché + végétation » (première démonstration)
Dans le laboratoire, avec le **pinceau** (zone peinte) : `/generer composition --etals 0-5 --vegetation 0-100 --graine N` ou « Marché + végétation » dans le panneau. Objets existants : étal de marchand, tas de caisses, tonneaux (assets cuits), arbres du générateur. Les étals forment une couronne ouverte vers le centre, caisses ou tonneaux près des étals, arbres sur le pourtour ; chaque objet passe par le système de placement (support, pente, collisions) et reste **sur la zone peinte**. **Ajustable** : nombre d'étals, densité de végétation, graine, puis nouvel aperçu sur la même zone. **Une seule opération** à confirmer, **une seule** à annuler (Ctrl+Z retire tout). Hors périmètre : boutique, mairie, économie, faune, remodelage de l'île d'ouverture (en attente des retours d'Axel sur les variantes d'habitation).
