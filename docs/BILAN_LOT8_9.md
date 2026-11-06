# Bilan des Lots 8 et 9 — construction joueur, atelier, habitations

Branche : `claude/lot8-9-construction-assemblage` (partie de `claude/lot7-carte-terrain-editeur`). Un commit par étape :
étape 1 `c5d8656` (construction joueur) · étape 2 `0fea2d7` (enregistrer / replacer une maison) · étape 3 (habitations générées, placement automatique, composition) : voir `git log` (derniers commits de la branche).
Mode d'emploi, coûts, formats : [CONSTRUCTION.md](CONSTRUCTION.md).

Légende : **joué** = vrais événements d'entrée (clics, touches, boutons) dans le jeu lancé au menu, rendu réel ; **automatisé** = contrôles sans rendu ; **capture** = constaté sur image.

## Étape 1 — Construire en première personne (laboratoire, touche B)
| Parcours | Type | Résultat |
|---|---|---|
| Sol 1,50 × 1,50 m : aperçu, X, confirmation, Ctrl+Z | joué + automatisé | aperçu « 3 unités » ; annulé = 0 débité ; confirmé = 197 ; Ctrl+Z = 200 |
| Mur 6 m × 2,5 m, porte, fenêtre | joué | 15 / 4 / 2 unités ; passage de porte vide et murs pleins vérifiés par requêtes de collision ; le joueur traverse la porte à pied |
| Modification refusée (mur raccourci sous la fenêtre / la porte) | joué | aperçu rouge expliqué, construction et stock intacts ; prolonger de 0,5 m = différence de 2 unités |
| Pièce rapide 6 × 4 m, côté de porte (O), toit ajusté, entrée à pied | joué | plancher + 4 murs, porte sud, toit 37 unités |
| Étage (PgUp), niveaux atténués | joué + capture | étage posé, autres niveaux translucides |
| Stock insuffisant | joué + automatisé | aperçu refusé, rien posé ni débité |
| Règles de coût, ouvertures, pièces, toits, étages, format | automatisé | `tests/run_checks_lot8.gd` |

## Étape 2 — Enregistrer et replacer une maison
| Parcours | Type | Résultat |
|---|---|---|
| Enregistrer dans l'atelier (`eclats-construction` v1) et rouvrir | joué + automatisé | fichier écrit, relu à l'identique ; fichier abîmé / carte / version future : erreur expliquée |
| Placer sur une parcelle en pente (éditeur, outil 9, R) | joué | aperçu vert avec raccord, plateforme plate, ~2 500 colonnes adaptées |
| Zone protégée | joué | refus expliqué, relief / maisons / historique inchangés |
| Ctrl+Z | joué | maison retirée, terrain identique colonne pour colonne |
| Export, nouvelle session, réouverture, île 3D | joué | maison et terrain identiques, 3 ouvertures conservées, porte et fenêtres vides, **marche du chemin jusque dans la maison** (avant et après réouverture) |
| Refus (hors île, aucun chemin à 14 m, protégé, raccord > 30 %) | automatisé | `tests/lot8_carte.gd` |

## Étape 3 — Habitations générées, placement automatique, composition
| Parcours | Type | Résultat |
|---|---|---|
| Trois variantes distinctes (cabane 4 murs · deux pièces 5 murs + cloison · maison en L 7 murs, 2 toits croisés, 2 hauteurs) | automatisé + joué | `/generer habitation` : aperçu, Entrée, Ctrl+Z ×3 |
| Même graine / emprise / réglages = même maison ; recette rejouable | automatisé | signatures identiques, recette relue |
| Recette et contraintes affichées | joué + capture | panneau du laboratoire |
| Sur la pente du labo (même raccord que l'atelier) | joué | 2 000+ colonnes raccordées, Ctrl+Z restaure |
| Placement automatique sur plan (3 graines × 3 variantes) | automatisé + joué | orientation d'après l'accès ; refus expliqués (en L sur la graine 21 : aucune parcelle ; tout protégé ; plan sans parcelle) sans rien forcer |
| Habitation posée automatiquement, 3D, marche jusqu'à l'intérieur | joué | 0 chute |
| Composition marché + végétation sur zone peinte : aperçu, réglage, pose, Ctrl+Z | joué | une opération pose, une opération annule ; 18 contrôles joués du labo (`captures/lot9/lot9_labo_controles.txt`) |

Tests rapides : voir la section « Tests » ci-dessous.

## Captures (rendu logiciel 1280 × 720)
Lot 8 (`captures/lot8/`) : [sol, coût](captures/lot8/00_sol_apercu_cout.jpg) · [mur, dimensions et coût](captures/lot8/01_mur_apercu_dimensions_cout.jpg) · [porte et fenêtre découpées](captures/lot8/02_porte_et_fenetre_decoupes.jpg) · [modification refusée](captures/lot8/03_modification_refusee_ouverture.jpg) · [stock insuffisant](captures/lot8/03b_stock_insuffisant.jpg) · [pièce et toit](captures/lot8/04_piece_avec_toit.jpg) · [étage actif](captures/lot8/05_etage_actif_rdc_attenue.jpg) · [rez-de-chaussée actif](captures/lot8/06_rdc_actif_etage_attenue.jpg) · [enregistrer](captures/lot8/07_dialogue_enregistrer.jpg) · [aperçu d'implantation](captures/lot8/08_carte_apercu_implantation.jpg) · [refus zone protégée](captures/lot8/09_carte_refus_zone_protegee.jpg) · [maison posée](captures/lot8/10_carte_maison_posee_raccord.jpg) · [3D sur la pente](captures/lot8/11_maison_en_3d_sur_la_pente.jpg) · [intérieur](captures/lot8/12_interieur_maison_ouvertures.jpg) · [carte rouverte](captures/lot8/13_carte_rouverte_avec_maison.jpg).
Lot 9 (`captures/lot9/`) : [aperçu, recette, contraintes](captures/lot9/14_habitation_apercu_recette_contraintes.jpg) · [trois variantes](captures/lot9/15_trois_variantes_habitation.jpg) · [sur la pente](captures/lot9/16_habitation_sur_la_pente.jpg) · [composition aperçu](captures/lot9/17_composition_marche_vegetation_apercu.jpg) · [ajustée](captures/lot9/18_composition_ajustee.jpg) · [posée](captures/lot9/19_composition_posee.jpg) · [refus maison en L](captures/lot9/20_carte_refus_naturel_maison_en_L.jpg) · [placement automatique](captures/lot9/21_carte_placement_automatique.jpg) · [refus zone protégée](captures/lot9/22_carte_refus_zone_protegee.jpg) · [habitation en 3D](captures/lot9/23_habitation_en_3d.jpg).

## Limites constatées
- **Fluidité GPU non mesurée** (rendu logiciel, quelques images/s) ; confort de marche mesuré par pilote automatique, pas ressenti à la main.
- **Pas d'escalier** : l'étage se construit et se voit mais n'est pas accessible à pied. Pas de porte à l'étage.
- Murs en boîtes de couleur de la palette du jeu (pas de textures voxel) ; les murs sont alignés sur la grille de 0,50 m, sans diagonales ; toit à deux pans seulement.
- Fondations : profondeur fixe de 60 cm ; sur pente forte on s'appuie sur la plateforme terrassée (limite 1,60 m de dénivelé, 80 cm de déblai et de remblai).
- Une maison sans porte extérieure ne peut pas être placée sur une carte (accès impossible).
- Le raccord est une bande droite (≤ 14 m, ≤ 30 %) ; si le chemin est derrière la maison, il faut tourner la maison (le placement automatique le fait).
- Retirer une maison sur la carte ne rend pas le terrain aménagé (Ctrl+Z, lui, le rend).
- Parcelles = zones « plateau » et « pelouse » ; pas de notion de lotissement. L'évaluation d'un emplacement prend ~70 ms ; la recherche automatique 0,5 à 1 s.
- La composition marché + végétation est un premier exemple (étals, caisses, tonneaux, arbres) sur le pinceau du labo ; pas encore dans l'éditeur de carte.
- Hors périmètre, comme demandé : boutique, mairie (en attente des retours d'Axel sur les variantes d'habitation), économie complète, faune, remodelage de l'île d'ouverture.
