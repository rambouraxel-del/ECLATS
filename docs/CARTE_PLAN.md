# Plan d'île, terrain et éditeur de carte (Lot 7)

Le **plan** (contour, zones, chemins, repères) est la **seule source** du terrain 3D : les hauteurs, les matières du sol et les
chemins de l'île construite correspondent aux tracés de l'aperçu 2D. Même graine + mêmes dimensions + mêmes réglages = même plan
et même terrain de base (tests : empreinte des hauteurs).

## Générer une île, voir le plan, la construire

Menu principal → **Générer une île** : graine, largeur et longueur (32 à 120 m) → **Aperçu du plan** (vue du ciel, nord en haut,
légende, ombrage du relief, courbes de niveau tous les mètres, teinte d'altitude bleue → dorée) → **Construire et explorer l'île**
(3D, première personne) ou **Modifier dans l'éditeur de carte**.

Profil « île d'arrivée » : une crique (entaille du contour) avec le **point d'arrivée en contrebas** (gravier), un **plateau habitable**
plat, une **zone boisée** (arbres de décor, déterministes), un **point haut**. Trois chemins en chaîne : arrivée → plateau → bois → sommet,
sinueux, **reliés à leurs zones** (liaisons) ; les hauteurs des zones sont choisies d'après la longueur réelle des chemins pour que
la pente reste praticable (≈ 15 %). Repères : point de vue au sommet, vue sur la crique, clairière du plateau.

Dans l'île 3D : première personne (V : 3e personne), **repère à rejoindre** affiché en haut, **F5 : vue aérienne** orientée comme le plan
(nord en haut), Échap : pause, F6 : retour à l'éditeur (si l'île vient de l'éditeur).

### Du plan au terrain (`PlanTerrain`)
1. le contour donne les colonnes de sol (colonnes de 20 cm, comme le Lot 5) ;
2. chaque zone impose une hauteur (zones plates : arrivée, plateau, crique ; noyau seulement pour bois et sommet) ; le relief entre les
   zones est la **solution lissée** des hauteurs imposées par les zones et par les chemins ; un bruit basse fréquence, d'amplitude propre
   à chaque type de zone (nul sur les zones plates), donne du caractère ;
3. les zones plates sont aplanies exactement ;
4. chaque chemin est **creusé** : palier à la hauteur de la zone, montée régulière entre les zones, largeur du plan, épaulements adoucis,
   matière « sentier » ;
5. matières : celle de la zone, roche sur les pentes fortes, taches d'herbe ailleurs ;
6. les retouches de l'éditeur s'ajoutent par-dessus.

**Ruptures de pente** : `PlanTerrain.path_reports` échantillonne chaque chemin tous les 25 cm (marche ≥ 40 cm, pente > 30 % sur 2 m,
tracé hors du sol). Les chemins du générateur sont **traités** (aucune rupture : testé sur 8 formats d'île) ; un chemin tracé à la main trop raide est
**signalé** : points rouges sur le plan, mention dans le panneau de l'éditeur. Une falaise ou une crique peut garder des pentes abruptes.
**Point de départ sûr** : sol plat (± 20 cm) sur 1,5 m, à 3 m au moins du bord (`start_report`).

## Éditeur de carte (Outils développeur → Éditeur de carte)

Vue **aérienne 2D** pour composer, **Vérifier en 3D** pour contrôler les raccords en première personne (F6 revient).
Départ : **canevas vide**, **Générer** (graine, L, H) ou **Ouvrir une carte**.

| Outil (touche) | Geste |
|---|---|
| 1 Contour | clics = points, Entrée / clic sur le 1er point = fermer ; ensuite glisser un sommet, double-clic sur un bord = ajouter un sommet, clic droit sur un sommet = le retirer. Un contour qui se croise est refusé (l'opération est défaite). |
| 2 Zones | peindre des disques de zone (prairie, bois, crique, falaise, plateau…), clic droit = effacer ; curseur du relief naturel (×) |
| 3 Chemins | clics = points, Entrée / clic droit = terminer ; glisser un point, double-clic = ajouter un point, clic droit = retirer, Suppr = supprimer ; curseur de largeur |
| 4 Repères | point de vue / lieu à dévoiler (avec libellé) ; « Placer le point de départ » |
| 5 Relief | Monter, Creuser, Aplanir, Adoucir ; rayon et force ; **la zone d'effet est affichée avant d'appliquer** (cercle, nom, sol sous le curseur) |
| 6 Matériau | peindre une matière du sol, clic droit = revenir à la matière du plan |
| 7 Masque | peindre / retirer la **protection** (rayures rouges) : pinceaux et régénération n'y touchent pas |
| 8 Régénérer | rectangle à deux coins + « Régénérer le relief dans la sélection » (variante suivante à chaque clic) |

**Ctrl+Z** annule une opération entière : un trait de pinceau, un déplacement de point, une régénération. Molette : zoom ; bouton du milieu : déplacer la vue.

**Régénération** : une autre variante du bruit du plan, appliquée dans le rectangle. Le masque est respecté (colonnes protégées inchangées),
un raccord de 2 m adoucit la limite de la sélection et le contour du masque ; les retouches hors de la sélection sont conservées ; les chemins
restent praticables (ils sont creusés dans les deux variantes).

## Format de carte (`eclats-carte`, version 1)

Fichier JSON : `format`, `version`, `name`, `seed`, `width`, `length`, `settings` (`relief`), `outline` (points), `zones` (`id`, `kind`, `c`, `r`, `h`),
`paths` (`id`, `width`, `pts`, `from`, `to`), `landmarks`, `start`, et, si la carte a été retouchée, `layers` : grille de colonnes (`n`, `origin`) avec
`delta` (relief, en cellules de 20 cm), `mat` (matière peinte) et `mask` (protection), compressées (deflate) puis en base64.
Dossier : `user://cartes/` (Windows : `%APPDATA%\Godot\app_userdata\ÉCLATS\cartes\`). Une carte plus récente que le jeu, un JSON illisible, un
champ manquant ou un type de zone inconnu sont refusés avec une phrase d'explication ; **l'île ouverte est conservée**.

## Code
`scripts/map/` : `island_plan.gd` (plan, format), `plan_layers.gd` (retouches), `plan_generator.gd`, `plan_terrain.gd`, `plan_canvas.gd` (vue 2D),
`map_doc.gd` (document éditable : pinceaux, masque, régénération, annulation, export — sans nœud, testé sans rendu), `map_editor.gd` (interface),
`map_island.gd` (île 3D). Réutilisés : `AuthoredTerrain`, `LabWorld.setup_field` (tuiles, collisions), `Explorer`, `ThirdPersonCamera`, menu et pause du Lot 6.

## Limites connues
- Le relief est en colonnes de 20 cm : une pente de 15 % se lit en terrasses de 20 cm (comme sur l'île d'ouverture).
- Chaque changement de structure (contour, zone, chemin) recalcule le relief de base (≈ 1 s) ; les pinceaux sont immédiats.
- Les retouches sont des écarts par rapport au relief du plan : déplacer un chemin après avoir sculpté garde les écarts (ils s'ajoutent au nouveau relief).
- Pas de bâtiments ni de placement automatique (lots suivants) ; arbres de décor seulement dans les zones boisées de l'île 3D.


## Format v2 (Lot 8) : maisons

`eclats-carte` passe en **version 2** : champ optionnel `maisons` = liste de `{id, name, model (eclats-construction), pos, yaw, ground_m, rect, door}`. Les retouches de terrain de la pose (plateforme, talus, raccord) sont dans `layers` comme celles d'un pinceau. Une carte v1 se rouvre ; une carte d'une version supérieure à 2 est refusée avec explication. Voir `CONSTRUCTION.md`.
