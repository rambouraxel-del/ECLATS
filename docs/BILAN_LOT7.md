# Bilan du Lot 7 — Du plan 2D à l'île 3D, puis édition du terrain

Branche : `claude/lot7-carte-terrain-editeur` (partie de `claude/lot6-menu-laboratoire`). Un commit par étape :
**étape 1** `e32b958` (plan → terrain → île 3D), **étape 2** `0e98620` (éditeur de carte, masque, régénération, export / ouverture).
Mode d'emploi, format de fichier et limites : [CARTE_PLAN.md](CARTE_PLAN.md).

## Ce qui est livré

**Étape 1 — Générer le plan, puis construire l'île.** *Générer une île* : graine, largeur, longueur → **aperçu du plan 2D** (contour, zones,
chemins et liaisons, repères, départ, légende, relief ombré avec courbes de niveau) → **Construire et explorer l'île**. Le plan est la source du terrain :
hauteurs des zones, matières, chemins creusés selon le tracé. Profil « île d'arrivée » : crique avec arrivée en contrebas, plateau habitable plat,
zone boisée, point haut ; chemins en chaîne dont la pente est choisie praticable. Départ sûr en première personne, repères à rejoindre, vue aérienne (F5) orientée comme le plan.

**Étape 2 — Éditer, protéger, exporter, rouvrir.** *Outils développeur → Éditeur de carte* : canevas vide ou plan généré ; vue aérienne 2D avec contour (points déplaçables),
zones peintes, chemins (points déplaçables, largeur réglable), repères (points de vue, lieux à dévoiler), pinceaux monter / creuser / aplanir / adoucir (zone d'effet affichée avant d'appliquer),
pinceau de matière, **masque de protection** visible (rayures rouges), **régénération** du relief dans une sélection (le masque et l'extérieur restent intacts),
**Ctrl+Z** par opération (trait de pinceau, déplacement de chemin, régénération), **Exporter la carte / Ouvrir une carte** (JSON versionné `eclats-carte`), **Vérifier en 3D** (première personne, F6 pour revenir).

## Les quatre parcours

Légende : **joué** = vrais événements d'entrée (clics, glissés, touches) dans le jeu lancé au menu, ou pilote automatique avec les vraies collisions ; **automatisé** = contrôles sans rendu ; **capture** = constaté sur image seulement.

| # | Parcours | Type | Résultat |
|---|---|---|---|
| 1 | Même graine, mêmes dimensions → même plan ; autre graine → autre plan | joué (menu) + automatisé | JSON de plan identique ; terrain identique (empreinte des hauteurs et matières) ; graine suivante : contour et zones différents ; dimensions différentes : autre plan. 200 plans (40 graines × 5 formats de 32 × 32 à 120 × 120 m) cohérents, sans chevauchement de zones |
| 2 | Parcourir en première personne les liaisons arrivée → plateau → bois → sommet | joué (pilote, 60 images/s fixes, collisions réelles) | 3 liaisons parcourues sur 3 îles (56 × 48, 60 × 50, 90 × 70 m), **0 blocage, 0 chute**, repères atteints (clairière, point de vue), saut de caméra ≤ 5,1 cm/image. Sur 8 îles de formats variés : aucune rupture de pente, départ sûr |
| 3 | Petite île depuis un canevas vide ; déplacer un chemin, retoucher le relief, protéger une crique, régénérer autour ; Ctrl+Z | joué (entrées réelles) | contour de 10 points, zones peintes, chemin tracé puis **point déplacé à la souris** (le terrain suit, chemin toujours praticable), relief monté, crique protégée (2 076 colonnes) ; régénération : **1 531 colonnes changées** dans la sélection, **0 colonne de la crique**, **0 colonne hors sélection** ; Ctrl+Z restaure toutes les colonnes ; une nouvelle régénération = variante suivante |
| 4 | Exporter, rouvrir dans une nouvelle session, comparer | joué + automatisé | scène rechargée (éditeur vide, historique vide) puis *Ouvrir une carte* : plan identique, retouches de relief / matières / masque identiques, **terrain identique colonne pour colonne**, point de chemin déplacé retrouvé. Fichier corrompu : erreur expliquée dans le dialogue **et île ouverte conservée, intacte** ; la bonne carte s'ouvre ensuite |

Contrôles automatisés (sans rendu, `tests/run_checks_lot7.gd`) : **68** (plan, terrain, chemins, départ, format, éditeur). Lots précédents inchangés : **180 + 121 + 50 + 39** réussis.
Recette jouée de l'éditeur : **43 contrôles** (`docs/captures/lot7/recette_editeur.json`) ; marche : `recette_marche_graine*.json`.

## Captures (`docs/captures/lot7/`)

| Fichier | Contenu |
|---|---|
| `01_plan_2d_graine21.jpg` | plan 2D de l'île graine 21 (menu *Générer une île*), légende |
| `02_vue_aerienne_3d_graine21.jpg` | la **même île** en vue aérienne 3D, nord en haut comme le plan |
| `03_canevas_ile_manuelle.jpg` | canevas après tracé d'une petite île à la souris (contour, prairie, bois, crique, chemin, repère) |
| `04_crique_avant_regeneration.jpg` | crique protégée (masque rayé rouge) et sélection, avant |
| `05_crique_apres_regeneration.jpg` | même cadrage, après : relief changé autour, crique identique |
| `06_carte_exportee_puis_rouverte.jpg` | carte exportée puis rouverte dans une nouvelle session ; chemin retouché (jaune), masque, retouches |
| `07_premiere_personne_sur_la_liaison.jpg` | bonus : première personne sur le chemin arrivée → plateau |
| `08_fichier_invalide_erreur_expliquee.jpg` | bonus : fichier corrompu, erreur expliquée, île conservée |
| `09_ile_editee_vue_3d.jpg` | bonus : l'île dessinée à la main, construite en 3D (crique de gravier, chemin déplacé, arbres) |

## Limites observées

- **Fluidité GPU non mesurée** : le rendu s'est fait en logiciel (quelques images par seconde) ; les parcours se jouent sans rendu, ou avec le joueur téléporté pour les captures de la 3D.
- Le **confort de marche** (pentes, seuils) est mesuré, pas ressenti à la main : à confirmer sur un vrai PC.
- Le relief en colonnes de 20 cm se lit en **terrasses** ; la différence avant / après d'une régénération est nette sur les courbes de niveau, plus discrète sur l'ombrage seul.
- Changement de **structure** (contour, zone, chemin) : recalcul du relief de base ≈ 1 s (≈ 0,7 s en 56 × 48 m) ; les pinceaux sont immédiats.
- Les retouches sont des **écarts** par rapport au relief du plan : déplacer un chemin après avoir sculpté garde les écarts.
- Le **masque protège** aussi des pinceaux (choix de conception) ; pour retoucher une zone protégée, retirer d'abord la protection.
- Plan seulement : pas de bâtiments, pas de placement automatique, île d'ouverture inchangée (lots suivants). Arbres de décor limités à la zone boisée de l'île 3D.
- Une seule variante de profil de génération (« île d'arrivée ») ; pas de manette dans l'éditeur ; dialogues d'export / d'ouverture limités au dossier `user://cartes/`.
