# Bilan du Lot 5 — Île d'ouverture jouable

Branche : `claude/lot5-ile-ouverture` (partie de `claude/lot4-generation-coherente`).
Accès : scène de démarrage, ou **F10** ; F9 reste l'île générée du Lot 4. Mode d'emploi : [ILE_OUVERTURE.md](ILE_OUVERTURE.md).

## Livré

- **Île fixe et éditable** (`config/islands/ile_ouverture.json`) : ≈ 41 500 m² de terre (île de test : ≈ 2 100 m²),
  relief dessiné par formes (grève, corniche, landes, col, cuvette du hameau, hauteurs, éperon, sommet), falaises
  de 3 à 16 m, 8 chemins taillés dans le relief, 6 bâtiments, 135 arbres, 36 rochers et ruines, 50 objets.
- **Plan dessiné avant construction** : [captures/lot5/00_plan.png](captures/lot5/00_plan.png) (outil :
  `tools/island_relief.gd` + `tools/plan_ile.py`).
- **Lot 4 réutilisé comme bibliothèque** : terrain, placement, plateformes et talus, chemins, maisons visitables,
  quai et navire, arbres, rochers, herbes, voxels (par tuiles de 32 m), assets cuits. Ajouts : relief dessiné,
  voxélisation par tuiles, sous-face grossière, collisions, cache de l'île construite.
- **Explorateur provisoire** à cape bleu ardoise (voxels de 4 cm, membres animés), ZQSD/WASD par touches
  physiques + flèches, course, saut, marches franchies automatiquement, caméra à la troisième personne qui évite les
  murs et se rapproche dans les maisons ; départ au quai et retour au quai après une chute.
- **Objectif et Ancre** : « ◆ Rejoindre le sanctuaire », invite « E · Activer l'Ancre » (lettre lue sur le clavier
  réel), pulsation cyan + anneau au sol + « Île découverte », objectif retiré, sauvegarde sous `ile-ouverture-01`.
- HUD validé conservé (en haut à gauche) ; ses lignes de commandes s'adaptent à la scène.

## Recette (partie jouée par un pilote automatique, mêmes collisions et vitesse que le joueur)

| Contrôle | Résultat |
|---|---|
| Trajet complet quai → cristal, hors visite | **246 s = 4,1 min** à 2,2 m/s, **0 blocage** (falaises 74 s, col 39 s, place 10 s, rue 12 s, lacets 52 s, pointe 4 s + retour, crête 42 s, montée 5 s) |
| Maison visitable | entrée, caméra rapprochée, rez-de-chaussée, escalier, **étage atteint (+2,61 m)**, ressortie : 15 s |
| Détour du verger | 30 s, rejoint le chemin principal |
| Ancre | invite « E · Activer l'Ancre » à portée, activation, bandeau « Île découverte », objectif vide, invite masquée |
| Sauvegarde | `ile-ouverture-01 : anchor_active = true` écrit ; **relance (nouveau processus)** : Ancre active, pas d'objectif ni d'invite |
| Chute | sortie de la corniche vers le vide → retour au quai en 6,2 s |
| Contrôles rapides | `tests/run_checks_lot5.gd` : 50 / 50 |

Corrigé pendant la recette : lacets trop serrés au départ (mur de soutènement), gradins de l'Ancre bloqués par la
collision d'origine de l'asset, marches d'escalier (rampe de collision dans l'escalier de la maison).

## Captures (positions enregistrées pendant la partie jouée)

- Plan de l'île (dessiné avant construction) : ![Plan de l'île (dessiné avant construction)](captures/lot5/00_plan.png)
- Départ au quai, objectif affiché : ![Départ au quai, objectif affiché](captures/lot5/01_quai_depart.jpg)
- Quai : appontement et navire amarré : ![Quai : appontement et navire amarré](captures/lot5/01b_quai_navire.jpg)
- Sentier des falaises (vide à gauche, tour de guet) : ![Sentier des falaises (vide à gauche, tour de guet)](captures/lot5/02_sentier_des_falaises.jpg)
- Col de la Pierre levée : ![Col de la Pierre levée](captures/lot5/03_col.jpg)
- Le hameau se découvre : ![Le hameau se découvre](captures/lot5/03b_decouverte_du_hameau.jpg)
- Maison visitable : ![Maison visitable](captures/lot5/04_maison_visitable.jpg)
- Entrée, caméra rapprochée : ![Entrée, caméra rapprochée](captures/lot5/05_interieur.jpg)
- Escalier vers l'étage : ![Escalier vers l'étage](captures/lot5/06_escalier_etage.jpg)
- Détour du verger : ![Détour du verger](captures/lot5/07_detour_du_verger.jpg)
- Pointe du Guet (point de vue) : ![Pointe du Guet (point de vue)](captures/lot5/08_pointe_du_guet.jpg)
- Chemin de crête et fûts : ![Chemin de crête et fûts](captures/lot5/09_chemin_de_crete.jpg)
- Montée régulière au sanctuaire : ![Montée régulière au sanctuaire](captures/lot5/10_montee_du_sanctuaire.jpg)
- « E · Activer l'Ancre » : ![« E · Activer l'Ancre »](captures/lot5/11_invite_ancre.jpg)
- Pulsation cyan, « Île découverte » : ![Pulsation cyan, « Île découverte »](captures/lot5/12_pulsation_ile_decouverte.jpg)
- Anneau au sol, objectif retiré : ![Anneau au sol, objectif retiré](captures/lot5/13_anneau_apres_activation.jpg)
- Après relance : Ancre active : ![Après relance : Ancre active](captures/lot5/14_apres_relance.jpg)
- Chute dans le vide : ![Chute dans le vide](captures/lot5/15_chute.jpg)
- Retour au quai : ![Retour au quai](captures/lot5/16_retour_au_quai.jpg)

## Mesures

- Première ouverture : construction ≈ 90 s sur 4 cœurs (relief 7 s, aménagements et objets 8 s, terrain et modèles
  en parallèle ≈ 75 s), écriture du cache 9 s (≈ 69 Mo dans `user://cache/`). Ouvertures suivantes : **≈ 3 s**.
- Terrain : ≈ 3,2 M sommets (faces enterrées non maillées) + sous-face grossière 0,6 M.

## Limites et points à vérifier sur un PC avec carte graphique

- Fluidité, ombres et distance d'affichage non mesurées sur GPU (rendu logiciel ici : 1 à 3 images/s).
- Les sols suivent une carte de hauteurs : sur les marches de 20 cm, les pieds peuvent flotter ou s'enfoncer de
  quelques centimètres.
- Quelques objets sont posés malgré un refus du placement universel (tour de guet en pente, bancs proches des
  lanternes, socle de l'Ancre sur sa plateforme, quelques rochers) ; 4 arbres non posés. Liste dans la console.
- L'explorateur est provisoire (pas de squelette ; animation par pivots). Pas de manette.
- La sauvegarde ne contient que l'état de l'Ancre ; « Ctrl + Suppr » l'efface pour rejouer.
