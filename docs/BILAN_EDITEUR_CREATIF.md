# Bilan — Éditeur d'îles créatif

Branche **`claude/editeur-iles-creatif`**, issue de `claude/galerie-modeles-3d` (la plus récente : elle contient le Lot 11, l'échelle du personnage 1,50 m et la galerie 3D).
Mode d'emploi, commandes et format : [`EDITEUR_CREATIF.md`](EDITEUR_CREATIF.md).

## Ce qui a été ajouté
- **Éditeur 3D intégré** (`scripts/creative/`) sur le même document que l'éditeur de carte 2D (`MapDoc`) et la même île 3D (`LabWorld`) : île vide, île générée d'une graine, ou carte enregistrée ; vue aérienne, première personne en vol, **mode jeu** (P) et retour à l'éditeur.
- **Inventaire créatif** (I) : recherche, 8 catégories, aperçu 3D tournant, pose avec aperçu aimanté ; sélection, déplacement (glisser ou G), rotation (R, par 15°), duplication (Ctrl+D), verrouillage (L), suppression (Suppr).
- **Relief** (monter, creuser, aplanir, adoucir), **matières** du sol, **carte** (zones, chemins à points déplaçables, repères, contour, **zones protégées** affichées en rouge).
- **Génération** forêt et marché dans un cercle ou dans une zone peinte ; objets individuellement modifiables ; **verrous**, objets posés à la main et zones protégées conservés à chaque génération.
- **Atelier** : construction en première personne ; **escalier ajouté au mode construction** (il n'existait pas : « pas d'escalier pour l'instant » dans la doc du Lot 8) avec étage percé et palier ; enregistrement dans l'inventaire (« Mes maisons »), pose avec aperçu, orientation, raccord au chemin et à la pente.
- **Historique** : Ctrl+Z **et rétablissement Ctrl+Y** (ajouté à `MapDoc`), sauvegarde, ouverture, export, dialogue « modifications non enregistrées ».
- **Format de carte v4** (`objets`) ; les cartes v1 à v3 se rouvrent sans perte ; la vue 3D classique et l'éditeur 2D conservent les objets.

## Correctifs découverts en chemin
- Un contour non arrondi au centimètre ne se relisait pas à l'identique (5 colonnes de bord changeaient après enregistrement) : les points de l'éditeur sont désormais arrondis comme le fichier de carte.
- La touche **L** (verrouiller) déclenchait aussi le changement d'éclairage de l'autoload : les touches de l'éditeur passent maintenant avant celles de l'application.
- Les maisons ne s'implantent plus sur un arbre, un étal ou un rocher posé (les objets sont des emprises à éviter pour `HousePad`).

## Captures (`docs/captures/editeur-creatif/`)
Menu et choix de la carte : [01 menu](captures/editeur-creatif/01_menu_principal.jpg) · [02 outils développeur](captures/editeur-creatif/02_menu_outils_developpeur.jpg) · [02b choix de la carte](captures/editeur-creatif/02b_menu_choix_de_la_carte.jpg) · [03 île vide](captures/editeur-creatif/03_ile_vide_vue_aerienne.jpg) · [04 graine](captures/editeur-creatif/04_choix_graine_generer.jpg) · [05 ouvrir](captures/editeur-creatif/05_choix_carte_ouvrir.jpg) · [05b cartes enregistrées](captures/editeur-creatif/05b_choix_carte_cartes_enregistrees.jpg)

Inventaire : [10 catégories](captures/editeur-creatif/10_inventaire_categories.jpg) · [11 arbres](captures/editeur-creatif/11_inventaire_categorie_arbres.jpg) · [12 recherche + aperçu](captures/editeur-creatif/12_inventaire_recherche_apercu_objet.jpg) · [13 ruines + aperçu](captures/editeur-creatif/13_inventaire_ruines_apercu.jpg)

Objets : [50 aperçu aimanté](captures/editeur-creatif/50_placement_apercu_aimant.jpg) · [51 aperçu tourné](captures/editeur-creatif/51_placement_apercu_tourne.jpg) · [52 objets posés](captures/editeur-creatif/52_objets_poses.jpg) · [53 rotation](captures/editeur-creatif/53_objet_tourne.jpg) · [54 déplacement](captures/editeur-creatif/54_objet_grab_deplacement.jpg) · [55 duplication](captures/editeur-creatif/55_objet_duplique.jpg)

Relief et matière : [20 avant](captures/editeur-creatif/20_relief_avant.jpg) · [21 colline](captures/editeur-creatif/21_relief_apres_colline.jpg) · [22 adouci (matière avant)](captures/editeur-creatif/22_relief_adouci.jpg) · [23 roche peinte (matière après)](captures/editeur-creatif/23_matiere_apres_roche.jpg)

Carte, forêt, marché : [30 avant](captures/editeur-creatif/30_carte_zone_avant.jpg) · [31 zone boisée](captures/editeur-creatif/31_zone_boisee_peinte.jpg) · [32 forêt générée](captures/editeur-creatif/32_foret_generee.jpg) · [33 arbre sélectionné](captures/editeur-creatif/33_arbre_selectionne.jpg) · [34 en déplacement](captures/editeur-creatif/34_arbre_en_deplacement.jpg) · [35 déplacé](captures/editeur-creatif/35_arbre_deplace.jpg) · [36 supprimé](captures/editeur-creatif/36_arbre_supprime.jpg) · [40 chemin en tracé](captures/editeur-creatif/40_chemin_en_trace.jpg) · [41 chemin + poignées](captures/editeur-creatif/41_chemin_termine_poignees.jpg) · [60 marché](captures/editeur-creatif/60_marche_genere.jpg) · [61 étal déplacé](captures/editeur-creatif/61_marche_objet_deplace.jpg)

Construction : [70 aperçu de l'escalier](captures/editeur-creatif/70_atelier_construction_ouverte.jpg) · [71 escalier vu du pied](captures/editeur-creatif/71_maison_escalier_vu_du_pied.jpg) · [72 étage atteint à pied](captures/editeur-creatif/72_etage_accessible_a_pied.jpg)

Maisons : [80 « Mes maisons »](captures/editeur-creatif/80_inventaire_mes_maisons_apercu.jpg) · [81 aperçu](captures/editeur-creatif/81_maison_apercu_implantation.jpg) · [82 posée](captures/editeur-creatif/82_maison_posee_plateau.jpg) · [82b versant sculpté](captures/editeur-creatif/82b_versant_sculpte_pour_la_maison.jpg) · [83 aperçu sur pente](captures/editeur-creatif/83_maison_pente_apercu.jpg) · [84 raccord coupé](captures/editeur-creatif/84_maison_pente_raccord_desactive.jpg) · [85 autre orientation](captures/editeur-creatif/85_maison_pente_orientation_changee.jpg) · [86 posée sur la pente](captures/editeur-creatif/86_maison_pente_posee.jpg) · [87 deux maisons](captures/editeur-creatif/87_deux_maisons_vue_aerienne.jpg)

Fichiers, historique, parcours : [90 enregistrer](captures/editeur-creatif/90_dialogue_enregistrer.jpg) · [91 non enregistré](captures/editeur-creatif/91_dialogue_modifications_non_enregistrees.jpg) · [92 rouverte, aérien](captures/editeur-creatif/92_carte_rouverte_vue_aerienne.jpg) · [93 rouverte, 1re personne](captures/editeur-creatif/93_carte_rouverte_premiere_personne_vol.jpg) · [93b poser en 1re personne](captures/editeur-creatif/93b_premiere_personne_poser_visee_centre.jpg) · [94 mode jeu](captures/editeur-creatif/94_mode_jeu_devant_la_maison.jpg) · [95 dans la maison](captures/editeur-creatif/95_mode_jeu_dans_la_maison.jpg) · [100 historique](captures/editeur-creatif/100_historique_avant_annulation.jpg) · [101 annulé / rétablir](captures/editeur-creatif/101_historique_apres_annulation_retablir.jpg)

Zone protégée : [110 avant](captures/editeur-creatif/110_zone_protegee_avant_regeneration.jpg) · [111 après régénération](captures/editeur-creatif/111_zone_protegee_apres_regeneration.jpg) · [112 vue rapprochée](captures/editeur-creatif/112_zone_protegee_apres_vue_rapprochee.jpg)

## Ce qui a été réellement joué, et ce qui ne l'a été qu'automatiquement
**Joué dans le vrai jeu** (`tools/creatif_recette.gd`, lancé au menu, rendu logiciel) avec de **vrais événements** clavier et souris : touches I, 1 à 7, R, G, L, Ctrl+D, Suppr, Entrée, Ctrl+Z, Ctrl+Y, Ctrl+S, P, F6 ; clics et glissés de souris sur l'île pour sculpter, peindre une zone et une protection, tracer un chemin, générer la forêt, sélectionner, déplacer un arbre, poser cinq objets de l'inventaire, poser les deux maisons.
**Appelé directement** (mêmes méthodes que les boutons, sans cliquer le bouton) : choix de la catégorie et de la recherche dans l'inventaire, boutons du panneau (matière, essence de zone, rayon, graine), marché (génération appelée sur `MapDoc`), ouverture du dialogue Fichier, le bouton « Île vide » du menu (signal du bouton), la caméra de chaque capture (placée par programme), la pose de l'objet en 1re personne (visée au centre, appel de `place_here`).
**Contrôlé automatiquement, jamais joué** : tests ciblés `tests/run_checks_creatif.gd` (51 contrôles : catalogue, objets, annulation / rétablissement, génération reproductible, verrou, zone protégée, v3 → v4, escalier avec montée à pied sous physique réelle).
**Jamais essayé** : le clavier réel en première personne (WASD, souris capturée, Tab), un vrai Mac, le rendu GPU.

## Tests et recette
- **Tests automatiques** (`tools/check.sh`, tous les lots) : 180, 121, 50, 39, 68, 104, 64, 30, 88, 14 contrôles des lots précédents, **tous en réussite** (aucune régression : la construction, les maisons, les cartes et le laboratoire sont intacts) ; nouveaux : **51 contrôles** de l'éditeur, 0 échec.
- **Recette jouée** (`tools/creatif_recette.gd`) : **54 contrôles, 0 échec** sur le parcours complet ; journal dans [`captures/editeur-creatif/journal_recette.txt`](captures/editeur-creatif/journal_recette.txt) et rapport JSON. Le parcours a demandé plusieurs passes : les défauts trouvés (sélection dans une forêt dense, dépôt après G, maison sur un objet, contour non arrondi, maison trop grande pour la pente, escalier non montable) sont corrigés.
- **Parcours demandé** : (1) petite île et colline +2,8 m ; (2) zone boisée, forêt de 11 arbres, un déplacé à la souris, un supprimé ; (3) chemin de 4 points et 5 objets de l'inventaire ; (4) maison à étage avec porte, fenêtres, escalier, montée à pied de +3,02 m ; (5) maison enregistrée, seconde posée sur un versant de 1,0 m sur 6 m avec plateforme et raccord au chemin ; (6) carte enregistrée (relief relu identique), rouverte, parcourue en vol puis en mode jeu avec entrée dans la maison ; (7) pose annulée (Ctrl+Z) et rétablie (Ctrl+Y), puis zone protégée (1 046 colonnes) inchangée et arbre verrouillé conservé après une régénération ciblée du relief et des objets (15 objets remplacés).
- Les captures ont été prises avant un correctif d'affichage : l'état de la carte (nom, ●, nombre d'objets) est maintenant sous la barre à droite ([05b](captures/editeur-creatif/05b_choix_carte_cartes_enregistrees.jpg) le montre) ; les autres captures gardent un petit résidu « ;) » en haut à droite.

## Limites restantes et comment les reproduire
1. **Contour** : on déplace, ajoute (double-clic) et retire des sommets, mais on ne dessine pas un contour neuf en 3D (l'île vide est un ovale fixe). Pour un tracé libre : Fichier → *Éditeur de carte 2D*.
2. **Atelier** : on construit dans la salle grise (le laboratoire), pas sur l'île ; la maison est ensuite enregistrée puis posée. Pas de construction directe sur la carte.
3. **Maison posée** : on ne la déplace pas en glissant ; sélectionner → *Reprendre* la retire (terrain restauré) et la remet en main. Rotation par quarts de tour.
4. **Génération** : forêt et marché seulement (arbres tirés parmi 12 variétés, étals, caisses, tonneaux, puits) ; pas de choix des essences ; les objets sont des assets précuits (pas les variantes par graine de la galerie).
5. **Sélection** : un seul objet à la fois ; pas de copier-coller de groupe.
6. **Maisons sur pente** : l'implantation reste soumise aux règles du Lot 8 (dénivelé limité, marge au bord, raccord au chemin à ≤ 14 m) : une grande maison peut ne trouver aucune parcelle sur une petite île (reproduire : poser « Maison à étage » sur l'île vide pleine d'objets).
7. **Fluidité** : mesurée sous rendu logiciel seulement ; le sculpt reconstruit les tuiles touchées à chaque trait (quelques dixièmes de seconde sous llvmpipe) ; à vérifier avec un GPU.
8. **Escalier** : droit, 1 m × 4 m, vers un seul niveau ; un étage doit déborder de 1 m au-dessus de l'arrivée.
