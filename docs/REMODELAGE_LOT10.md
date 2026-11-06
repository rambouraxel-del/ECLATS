# Lot 10 — Remodelage de l'île d'ouverture à hauteur de joueur

La carte du Lot 5 est **retouchée à la main**, par données (aucun hasard caché) :

```
python3 tools/lot10_remodelage.py            # étapes 1 et 2
python3 tools/lot10_remodelage.py --etape 1  # quai et hameau seulement
```

- Entrée : `config/islands/archive/ile_ouverture_lot5.json` (carte du Lot 5, conservée telle quelle).
- Sortie : `config/islands/ile_ouverture.json` (la carte jouée ; l'ancien cache est invalidé et l'île reconstruite).
- Chaque position est écrite dans le script ; les aides `along(chemin, distance, décalage)` ne servent qu'à la
  calculer (décalage > 0 = à droite du sens de marche). Les graines des objets ajoutés sont numérotées dans l'ordre
  d'écriture (arbres 30001…, rochers 31001…) : même script = même île.
- Un seul changement de code : `spawn.pier_m` (départ SUR le ponton, voir ci-dessous).

Repère : mètres, x vers l'est, z vers le sud.

## Étape 1 — du quai au hameau

| Lieu | Choix |
|---|---|
| Départ | sur le tablier, à 7 m du bord de l'île (`spawn.pier_m`), cap plein nord : le navire est à droite ; le ponton, la grève et la chaussée balisée devant |
| Pied du ponton | dallage `quai_dallage` (pavés) de la plateforme au sentier ; lampes de part et d'autre, bitte d'amarrage |
| Aire de déchargement | caisses et tonneaux groupés côté navire (est) |
| Sortie | panneau d'avis, porte-bannière et panneau directionnel à la fourche ; lampes jusqu'au pied des lacets ; chaussée dallée du ponton au pied des lacets |
| Pied de falaise | deux blocs et des pins au nord de la grève (transition grève / falaise) |
| Montée jusqu'au col | le sentier part franchement au nord-ouest ; bosquets de pins et de bouleaux du côté de la falaise, blocs au bord du vide, alternance serré / ouvert ; menhir de l'arrivée |
| Révélation du hameau | une **butte** (`butte_de_revelation`, +4 m) barre la vallée : depuis le col le hameau est caché ; au sommet, point `(-60 ; -25,5)`, il apparaît d'un coup à ~55 m, la fontaine dans l'axe (vérifié sur le relief par `tests/run_checks_lot10.gd`) |
| Hameau | la descente se termine par une avenue **rectiligne visant la fontaine** (lampes en alignement, deux porte-bannières à l'entrée de la place) ; marché en rue côté sud de la rue du hameau (étals, caisses, tonneaux) ; lampes de l'allée de la maison visitable ; deux fruitiers marquent le départ du détour du verger |

Bâtiments : les maisons texturées existantes sont conservées (aucune habitation de l'atelier n'a été posée : le
hameau reste cohérent de matériaux). La maison visitable garde son escalier : l'étage est accessible (recette).

## Étape 2 — de la crête au sanctuaire

| Lieu | Choix |
|---|---|
| Pointe du Guet | belvédère : panneau « retour » à la fourche, deux lampes sur les 10 m d'approche, arche qui encadre le vide, banc face au vide, porte-bannière ; blocs en parapet côté vide |
| Chemin de crête | alternance **resserré / ouvert** : (s = 15 m) deux blocs à 2,8 m de l'axe et pins derrière ; (s = 31 m) belvédère ouvert avec banc ; (s = 62 m, tronçon droit) porte de deux colonnes en ruine et pins serrés ; (s = 74 m) lampes à l'approche de la montée |
| Montée du sanctuaire | braseros au pied des gradins (en plus des bornes), colonnes de ruine qui bordent les gradins, **arche d'entrée en haut des gradins, dans l'axe du cristal** (visible depuis le pied de la montée), mur écroulé derrière le brasero nord ; l'axe gradins → cristal reste libre |
| Raccords de terrain | l'épaule qui raccorde chaque tracé au relief est réglable (`skirt`, en colonnes de 20 cm, 12 par défaut) : doublée sur la descente du col, la rue du hameau, le détour, les lacets, la crête et la pointe |

Les falaises, les dénivelés et le caractère voxel de l'île ne sont pas touchés : seuls des tracés, des objets et une butte (`butte_de_revelation`) ont été ajoutés.

## Défaut corrigé au passage

Plateforme de l'Ancre : à la **première** construction de l'île (cache absent, ou lancement sans interface), la plateforme gardait un bloc de collision de 90 cm
en plus de ses trois marches (la fonction qui retire les collisions propres aux objets cherchait « Props » sous « Props » et ne trouvait rien).
Le joueur butait alors à 3 m du cristal, au bord de la plateforme (blocage déjà présent à la fin du Lot 5, relevé par la recette). Corrigé dans
`AuthoredIslandView.create` : les trois marches de 30 cm se montent désormais, sondées par `tools/lot10_sonde_ancre.gd`.

## Contrôles

- `godot --headless -s tests/run_checks_lot10.gd` : carte du Lot 5 archivée, tracés continus, avenue alignée sur la fontaine, **hameau caché depuis le col et en vue
  depuis le point de révélation** (visée sur le relief), objets ajoutés sur l'île et hors des chemins et des allées de porte, axe du sanctuaire libre.
- `tools/opening_recette.gd` (partie jouée, inchangée sur le fond) : trajet complet, maison et étage, détour, Ancre, chute, relance.
- `tools/lot10_captures.gd` + `docs/captures/lot10/cadrages.json` : captures à cadrages fixes (avant / après).
