# Bilan — premier personnage 3D articulé

Branche **`claude/personnage-3d-explorateur`**, créée à partir de `claude/editeur-iles-creatif` (la plus récente : elle contient le Lot 11, l'échelle 1,50 m, la galerie 3D et l'éditeur créatif). Description du modèle : [PERSONNAGE.md](PERSONNAGE.md).

Liens des captures : `docs/captures/personnage/` (sur GitHub : `…/blob/claude/personnage-3d-explorateur/docs/captures/personnage/<fichier>`).

## Ce qui a été fait
- **Modèle** : explorateur voxel de 1,72 m (affiché 1,52 m, capsule 1,50 m inchangée), cubes adoucis, tête ≈ ⅓ de la hauteur, visage souriant, lunettes d'aviateur, écharpe-cape lavande à croix sable, tunique crème, gilet et ceinture de cuir, pantalon kaki, bottes, tabard et bourse. 17 pivots, ≈ 2 650 triangles, 16 matières `perso_*` ajoutées à la fin de la palette.
- **Animations** réelles (`AnimationPlayer`) : attente, marche, course, saut / chute ; fondu entre clips, vitesse de lecture calée sur la vitesse réelle.
- **Jeu** : intégré à `Explorer` sans changer collisions, première personne (modèle masqué), bascule V, caméra 3e personne.
- **Galerie 3D** : famille « Personnages », modèle exporté avec ses 4 animations (même exporteur glTF), boutons Attente / Marche / Course / Saut / Repos.

## Captures
| Sujet | Fichier |
|---|---|
| Face, profil, dos, trois-quarts | [planche_face_profil_dos.jpg](../docs/captures/personnage/planche_face_profil_dos.jpg) · [face](../docs/captures/personnage/modele_face.jpg) · [profil](../docs/captures/personnage/modele_profil.jpg) · [dos](../docs/captures/personnage/modele_dos.jpg) · [trois-quarts](../docs/captures/personnage/modele_trois_quarts.jpg) |
| Visage en gros plan | [visage_gros_plan.jpg](../docs/captures/personnage/visage_gros_plan.jpg) |
| Poses des animations (attente / marche / course / saut) | [poses_animations.jpg](../docs/captures/personnage/poses_animations.jpg) |
| **En jeu** près de la porte d'une maison (échelle) : face, côté, dos | [jeu_porte_de_face.jpg](../docs/captures/personnage/jeu_porte_de_face.jpg) · [jeu_porte_de_cote.jpg](../docs/captures/personnage/jeu_porte_de_cote.jpg) · [jeu_porte_de_dos.jpg](../docs/captures/personnage/jeu_porte_de_dos.jpg) |
| En jeu : marche, course, saut | [jeu_marche.jpg](../docs/captures/personnage/jeu_marche.jpg) · [jeu_course.jpg](../docs/captures/personnage/jeu_course.jpg) · [jeu_saut.jpg](../docs/captures/personnage/jeu_saut.jpg) |
| **GIF de la marche** (et course) en jeu | [jeu_marche.gif](../docs/captures/personnage/jeu_marche.gif) · [jeu_course.gif](../docs/captures/personnage/jeu_course.gif) · MP4 : [marche](../docs/captures/personnage/jeu_marche.mp4), [course](../docs/captures/personnage/jeu_course.mp4) |
| Première personne devant la porte | [jeu_premiere_personne_porte.jpg](../docs/captures/personnage/jeu_premiere_personne_porte.jpg) |
| Collision contre la façade | [jeu_collision_facade.jpg](../docs/captures/personnage/jeu_collision_facade.jpg) |
| Galerie 3D (navigateur) : bureau et mobile, attente / marche / course | [bureau](../docs/captures/personnage/galerie_bureau_walk.png) · [mobile](../docs/captures/personnage/galerie_mobile_run.png) (+ `_idle`, `_run`, `_walk`) |
| Journal de la recette | [journal_recette.txt](../docs/captures/personnage/journal_recette.txt) |

## Ce qui a été réellement joué, et ce qui ne l'a été qu'automatiquement
**Joué dans le vrai jeu** (île d'ouverture, collisions et animations réelles, pilote automatique à la place du clavier, rendu logiciel) : lancement, arrêt (attente), marche 5,7 m en 2,6 s, course 9,9 m en 2,2 s, retour à l'attente, saut, bascule 3e ↔ 1re personne (modèle masqué, yeux à 1,41 m, animation poursuivie), marche contre la façade (arrêt par le soubassement de pierre). 13 contrôles du journal ; un seuil de la collision était mal réglé dans mon script (le « point porte » est au milieu du mur) : étape rejouée seule avec le seuil corrigé, voir le journal.
**Contrôlé automatiquement** : `tests/run_checks_personnage.gd` (30 contrôles : pivots, hauteur, boucles d'animation, choix du clip, échelle, capsule, vue) ; galerie testée dans un vrai navigateur (Chromium, bureau + mobile, 0 erreur).
**Jamais fait** : essai au clavier et à la souris réels, sur Mac, avec carte graphique ; fluidité mesurée seulement en rendu logiciel.

## Tests
Tous les tests des lots précédents rejoués (voir la sortie de `tools/check.sh`) + 30 nouveaux. Le test d'échelle (14) est inchangé et passe.

## Limites
- **Modèle** : pièces rigides (pas de peau) : aux genoux, coudes et épaules les pièces se chevauchent ou laissent un petit jour en mouvement ample ; mains sans doigts ; visage fixe (pas de clignement ni d'expressions) ; bras légèrement écartés en pose en A, ils frôlent un chambranle étroit.
- **Fidélité** : on reconnaît la planche (palette, lunettes, écharpe, tabard, bourse) mais le grain de 4 cm simplifie : cheveux moins bouclés, croix et boucles de 1 cellule, cape plus rigide, jambes un peu courtes.
- **Animations** : 4 boucles seulement (pas de démarrage / arrêt, de virage, de saut en trois temps, d'interaction, ni de marche en pente ou d'escalier). Le saut est une pose tenue ; la cape et le tabard sont animés par clés, pas par une simulation du vent.
- **Galerie** : la page n'est visible que si les pages GitHub sont activées (réglage déjà signalé) ; le modèle est animé par nœuds (pas de squelette `Skin`).
- Les anciennes sauvegardes et cartes ne sont pas touchées (seul l'aspect change).
