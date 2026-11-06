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
| Départ | sur le tablier, à 7 m du bord de l'île (`spawn.pier_m`), cap plein nord : le navire est à droite, le ponton, la grève et le sentier balisé devant |
| Pied du ponton | dallage `quai_dallage` (pavés) de la plateforme au sentier ; lampes de part et d'autre, bitte d'amarrage |
| Aire de déchargement | caisses et tonneaux groupés côté navire (est) |
| Sortie | panneau d'avis, porte-bannière et panneau directionnel à la fourche ; lampes jusqu'au pied des lacets ; deux blocs en « porte » devant les lacets |
| Pied de falaise | chaos de blocs et deux pins au nord de la grève (transition grève / falaise) |
| Montée jusqu'au col | le sentier part franchement au nord-ouest ; bosquets de pins et de bouleaux du côté de la falaise, blocs au bord du vide, alternance serré / ouvert ; menhir de l'arrivée |
| Révélation du hameau | point `(-84, -33,5)`, juste après le col : les arbres restent derrière, seuls des blocs bas bordent la descente ; la fontaine est dans l'axe |
| Hameau | la descente se termine par une avenue **rectiligne visant la fontaine** (lampes en alignement, « porte » de deux bouleaux) ; marché en rue côté sud de la rue du hameau (étals, caisses, tonneaux) ; lampes de l'allée de la maison visitable ; deux fruitiers marquent le départ du détour du verger |

Bâtiments : les maisons texturées existantes sont conservées (aucune habitation de l'atelier n'a été posée : le
hameau reste cohérent de matériaux). La maison visitable garde son escalier : l'étage est accessible (recette).
