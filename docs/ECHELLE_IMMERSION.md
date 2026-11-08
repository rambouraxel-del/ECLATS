# Échelle et immersion — essai (branche `claude/echelle-immersion`)

Partie de `claude/lot11-fiabilite-optimisation`. Modification simple, réglable, sans agrandissement global du monde.

## Valeurs choisies (`config/player.json`, relancer après modification)
| | Avant | Maintenant |
|---|---|---|
| Hauteur du personnage / capsule de collision | 1,70 m | **1,50 m** (`hauteur_m`) |
| Yeux (1re personne) | 1,60 m | **1,41 m** (proportionnel) |
| Rayon de la capsule | 0,28 m | **0,25 m** |
| Épaule de la caméra 3e personne | 1,55 / 1,45 m (intérieur) | 1,37 / 1,28 m |
| Modèle du personnage | ×1 | ×0,88 |
| Marche franchissable | 36 cm | 36 cm (inchangée) |
| Vitesse de marche | 2,3 m/s | 2,3 m/s (inchangée) |
| Champ de vision 1re personne | 76° | 76° par défaut (réglable) |

Tout dérive de `hauteur_m` (`scripts/game/player_config.gd`) : essayer 1,40 ou 1,60 revient à changer ce seul nombre.

## Champ de vision
- **Touche F** (en jeu, île d'ouverture, île du plan, laboratoire) : 76° → 84° → 68° → 76°… ; un message le confirme ; le choix est mémorisé (`user://reglages.cfg`).
- Au lancement : `-- --fov=68` (ou 76, 84) ; `fov_depart` dans `config/player.json`. Le réglage actuel (76°) reste le point de départ. La 3e personne garde son écart de 12° (64° pour 76°).
- Aussi : `-- --hauteur=1.6` pour essayer une autre échelle sans modifier le fichier.

## Île d'ouverture : arbres et rochers (carte rejouée depuis l'archive du Lot 11)
`python3 tools/echelle_ile.py hauteurs.json` (relit `config/islands/archive/ile_ouverture_lot11.json`) :
- **48 arbres sur 161** (chênes bas, fruitiers, pleureurs, arbres morts de moins de 5,6 m) agrandis de ×1,12 à ×1,25 ; la collision du tronc suit ;
- **13 blocs et affleurements sur 53** d'échelle ≤ 1,0 agrandis de ×1,25 ; ruines et formations inchangées ;
- positions, bâtiments, chemins et relief identiques. L'île est reconstruite au premier lancement (le cache est invalidé).

## Vérifications
- Automatiques : tests précédents inchangés (180, 121, 50, 39, 68, 104, 64, 30, 88) + `tests/run_checks_echelle.gd` (14 : valeurs dérivées, capsule, modèle, touche F, arbres et rochers mesurés, île inchangée par ailleurs).
- Jouée (pilote automatique, vraies collisions, `tools/opening_recette.gd`) : aucun défaut ; trajet quai → sanctuaire 4,4 min (4,3 avant) ; porte et seuil : saut de caméra max 2,8 cm par image ; escalier : 5,1 cm (5,5 avant), étage atteint (+2,62 m), 79 marches de terrain franchies ; détour du verger rejoint le chemin ; Ancre : invite « E · Activer l'Ancre », activation, bandeau, sauvegarde ; relance : Ancre toujours active ; chute dans le vide : retour au quai.
- Captures comparables (mêmes positions, orientation, FOV 76°) : `docs/captures/echelle/comparaison_quai.jpg`, `comparaison_maison_exterieur.jpg`.

## Limites
- Rendu logiciel et pilote automatique : le **ressenti** (échelle, fluidité, souris) est à juger sur Mac.
- Les intérieurs n'ont pas de capture : le cadrage automatique se pose sur le toit ; la traversée de la porte et l'escalier sont vérifiés par la recette jouée, pas visuellement.
- Les objets (portes, mobilier, maisons) n'ont pas été modifiés : avec un personnage plus petit, ils paraissent un peu plus grands, ce qui est l'effet recherché.
- Les cartes générées (éditeur, laboratoire) gardent leurs arbres ; seule l'île d'ouverture est retouchée.
