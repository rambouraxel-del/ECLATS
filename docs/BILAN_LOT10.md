# Bilan — Lot 10 : remodelage de l'île d'ouverture à hauteur de joueur

Branche `claude/lot10-remodelage-ile-ouverture` (partie de `claude/lot8-9-construction-assemblage`). Détail des choix : `docs/REMODELAGE_LOT10.md`.

## Ce qui a changé

- **Quai** : le joueur part **sur le ponton**, navire à sa droite ; devant lui la grève, une **chaussée dallée** qui mène au pied des lacets, et un balisage
  (lampes, porte-bannières, panneaux, panneau d'avis). Le mobilier est regroupé par usage (pied du ponton, aire de déchargement, sortie).
- **Montée et col** : bosquets, blocs et menhir alternent serré / ouvert le long de la corniche.
- **Hameau** : une **butte** barre la vallée — depuis le col le hameau est caché, au sommet (point de révélation) il apparaît d'un coup, la place dans l'axe d'une **avenue
  rectiligne** bordée de lampes ; deux porte-bannières marquent l'entrée de la place ; marché en rue (étals), lampes de l'allée de la maison visitable, fruitiers au départ du détour du verger.
- **Pointe du Guet** : belvédère (arche, banc face au vide, porte-bannière, panneau de retour). **Crête** : deux passages resserrés (blocs, puis porte de colonnes en ruine) séparés par
  des tronçons ouverts. **Sanctuaire** : braseros au pied des gradins, **arche d'entrée alignée sur le cristal**, ruines intégrées, axe gradins → cristal libre.
- **Raccords de terrain** : l'épaule de chaque tracé est réglable (`skirt`) et a été doublée sur les portions retouchées.
- **Défaut corrigé** : la plateforme de l'Ancre gardait un bloc de collision de 90 cm à la première construction (le joueur butait à 3 m du cristal) ; les marches de 30 cm se montent maintenant.

La carte est retouchée par `tools/lot10_remodelage.py` à partir de la carte du Lot 5 (archivée) : chaque position est écrite, rien n'est aléatoire. Identifiant d'île, format de carte et sauvegarde sont inchangés (une partie sauvegardée au Lot 5 se recharge).

## Commits

| Commit | Contenu |
|---|---|
| `8c4a8a7` | Étape 1 : quai et hameau |
| `0aa1bc7` | Étape 2 : crête, Pointe du Guet, sanctuaire, correction de la plateforme de l'Ancre |
| dernier commit de la branche | Captures, recette rejouée sur la carte finale, bilan |

## Recette

Partie **jouée** par le pilote automatique (mêmes collisions et vitesse que le joueur, première personne, `tools/opening_recette.gd`) :

| Parcours | Résultat |
|---|---|
| Départ sur le ponton → chaussée → lacets → col → hameau → hauteurs → Guet → crête → sanctuaire → cristal | **aucun blocage** ; ≈ 4,3 min de marche (visé 4 à 6) |
| Maison visitable : entrée, rez-de-chaussée, escalier, **étage atteint** (+2,61 m), retour dehors | oui ; saut de caméra max 5,5 cm par image dans l'escalier |
| Détour du verger | rejoint le chemin principal (≈ 33 s) |
| Invite « E · Activer l'Ancre », activation, bandeau « Île découverte », objectif retiré | oui |
| Relance dans un nouveau processus | Ancre active, objectif absent, sauvegarde retrouvée |
| Chute dans le vide (corniche ouest) | retour au quai |

Contrôles automatisés : Lots 1 à 9 inchangés (180, 121, 50, 39, 68, 104, 64), **Lot 10 : 30** (carte archivée, tracés continus, avenue alignée sur la fontaine,
hameau caché depuis le col et en vue depuis le point de révélation, objets hors des chemins et des allées de porte, axe du sanctuaire libre) — tous à 0 échec.

## Captures (`docs/captures/lot10/`, mêmes cadrages avant / après : `cadrages.json`, même lumière, même hauteur d'yeux)

1. `01_quai_depart_avant.jpg` · 2. `02_quai_depart_apres.jpg` — départ sur le ponton, navire à droite, sortie au fond
3. `03_hameau_decouverte_avant.jpg` · 4. `04_hameau_decouverte_apres.jpg` — point de révélation du hameau (-60 ; -25,5), première personne
5. `05_pied_sanctuaire_avant.jpg` · 6. `06_pied_sanctuaire_apres.jpg` — pied de la montée du sanctuaire, première personne
7. `07_vue_aerienne_finale.jpg` — vue aérienne avec étiquettes (quai, hameau, guet et crête, sanctuaire ; `tools/lot10_annoter.py` ; brume atténuée pour la lisibilité)

## Ce que la recette permet de dire, et ce qui reste à apprécier sur PC

La recette tourne en **rendu logiciel** et avec un **pilote automatique** : elle prouve que les parcours sont **franchissables** (collisions réelles, marches, étage, Ancre, sauvegarde, chute),
que le hameau est **réellement caché puis visible** (visée sur le relief) et que rien de décoratif ne gêne un chemin. Elle ne dit rien de :

- la **fluidité** (images par seconde sur carte graphique) et le **confort de marche ressenti** à la souris et au clavier ;
- la **lisibilité à l'écran d'un PC** : à 55 m la place du hameau est reconnaissable (bannières, lampes, fontaine, parasol), mais la taille des repères, le contraste et le rythme du parcours se jugent à la main ;
- l'**ambiance** aux autres heures (F5/F6/F7) : les cadrages sont pris de jour.

## Limites

- Les maisons du hameau restent celles du Lot 5 (aucune habitation de l'atelier n'a été posée) ; la composition de marché du laboratoire n'a pas été portée dans l'éditeur de carte : les étals sont posés par les données de la carte.
- Le départ sur le ponton place le joueur à côté du navire : le point de vue « navire + sortie » est celui de la capture 2, la sortie est plus lisible grâce au balisage qu'au relief.
- Quelques objets du Lot 5 sont encore « posés malgré refus » par la carte (tour de guet, rochers de la corniche…) : non touchés ici.
- Pas de nouvelle bibliothèque d'objets : les repères sont faits des objets existants (lampes, porte-bannières, arches, braseros).
