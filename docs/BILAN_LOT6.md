# Bilan du Lot 6 — Menu principal, première personne, laboratoire développeur

Branche : `claude/lot6-menu-laboratoire` (partie de `claude/lot5-ile-ouverture`), **deux commits**, un par étape.
Accès : le projet démarre sur le **menu principal**. Détails : [LABORATOIRE.md](LABORATOIRE.md) · [ILE_OUVERTURE.md](ILE_OUVERTURE.md).

## Étape 1 — Menu principal et première personne

- **Menu** (provisoire, lisible) : *Jouer l'île d'ouverture* · *Générer une île* (type d'île et graine, générateur du Lot 4) · *Outils développeur* · *Quitter*.
  Seule la scène choisie est chargée (écran « Chargement… »). *Outils développeur* : laboratoire (salle grise, île vide), île générée (F9), colonie (F4), première île (F2), labo graphique (F1), galerie de matériaux (F8).
- **Pause** (Échap, dans toute scène sauf le menu) : *Reprendre* (la souris est rendue au joueur) / *Retour au menu principal* (la scène est fermée et **déchargée** ; un calcul d'île encore en cours est joint plus tard, sans bloquer).
- **Île d'ouverture en première personne** : caméra à 1,60 m, réticule discret, marche, saut, collisions, Ancre, sauvegarde et retour au quai conservés. **V** : retour à la troisième personne.
- **HUD** : objectif (« ◆ Rejoindre le sanctuaire ») et invite (« E · Activer l'Ancre ») dans le HUD de jeu ; informations techniques (FPS, position, aide) **à la demande avec F3**.
- **Correctif de confort trouvé pendant la recette** : sur la rampe d'escalier, l'explorateur était hissé à chaque image (la caméra montait par à-coups de **24,6 cm** par image). Corrigé (`Explorer._try_step` : une pente n'est plus prise pour une marche) et lissage des marches adouci : **5,6 cm/image** au maximum dans l'escalier, **2,8 cm** au passage de la porte.

## Étape 2 — Laboratoire développeur

Salle grise (sol plat) et île vide (pente de 20 %), mêmes outils en première personne :
**point** (arbre, rocher), **rectangle** à deux coins avec dimensions affichées (emprise de 3,50 × 3,50 m → cabane), **pinceau** (aplanir). Panneau de génération et barre de commandes (**T**) sur la même sélection et la même logique ;
aperçu → confirmation → **Ctrl+Z** (opération entière, raccord au sol compris) ; raisons de refus affichées sans toucher le terrain ; **Copier la recette** (générateur, graine, emprise, réglages) rejouable sur l'autre terrain.

## Recette

Légende : **joué** = pilote automatique avec les vraies collisions et la vraie vitesse du joueur, ou vrais événements d'entrée (clics, touches) injectés dans le jeu lancé au menu ; **automatisé** = contrôles sans rendu ; **capture** = constaté sur image seulement.

| Parcours | Type | Résultat |
|---|---|---|
| Démarrage au menu | joué (jeu lancé au menu, rendu réel) | le projet ouvre `MainMenu` |
| Menu → île d'ouverture → pause → *Retour au menu principal* | joué | pause active, reprise = souris recapturée, retour au menu, île déchargée |
| Île : trajet quai → cristal en première personne | joué (headless, 60 images/s fixes) | **4,2 min**, 0 blocage |
| Île : passage de la porte, escalier, étage | joué | entrée et sortie, étage atteint (+2,61 m) ; caméra : ≤ 2,8 cm/image à la porte, ≤ 5,6 cm/image dans l'escalier |
| Île : Ancre | joué | invite « E · Activer l'Ancre », activation, « Île découverte », objectif retiré, sauvegarde écrite |
| Île : chute / relance | joué | retour au quai en 6,4 s ; nouvelle instance : Ancre active, plus d'objectif ni d'invite |
| Île : détour | joué | rejoint le chemin principal |
| Labo : Point (vrai clic au réticule) → arbre → Ctrl+Z | joué (entrées réelles) | point fixé, aperçu, confirmation, annulation |
| Labo : Rectangle 3,50 × 3,50 m (deux vrais clics) | joué | dimensions exactes affichées |
| Labo : T → `/generer maison --graine 42` → Entrée → Ctrl+Z | joué (entrées réelles) | aperçu, maison posée, annulée entièrement (terrain, réservations, objets) |
| Labo : même recette sur la pente | joué | même variante (cabane, même toit, mêmes ouvertures) ; **1 336 colonnes** raccordées sur la pente contre 0 dans la salle ; Ctrl+Z restaure le relief |
| Labo : emprise 2 × 2 m | joué | refus « Emprise trop petite … », terrain intact |
| Labo : Pinceau (clic maintenu) → aplanir → Ctrl+Z | joué (entrées réelles) | 331 colonnes ; **0 colonne modifiée hors de la zone** ; terrain restauré à l'identique |
| Labo : pause Échap → retour au menu | joué | laboratoire déchargé |
| Tests rapides | automatisé | `run_checks` 180/180 · lot 4 121/121 · lot 5 50/50 · **lot 6 39/39** |

## Captures (rendu logiciel, 1280 × 720)

1. [Menu principal](captures/lot6/01_menu_principal.jpg)
2. [Première personne, escalier de la maison](captures/lot6/02_interieur_escalier_premiere_personne.jpg) (et [palier](captures/lot6/02b_palier_etage.jpg), [rez-de-chaussée](captures/lot6/02c_rez_de_chaussee.jpg))
3. [Menu de pause](captures/lot6/03_menu_pause.jpg)
4. [Salle grise : rectangle 3,50 × 3,50 m et aperçu de la maison](captures/lot6/04_salle_rectangle_apercu_maison.jpg) (et [arbre au point visé](captures/lot6/04a_salle_point_arbre_apercu.jpg), [refus](captures/lot6/04c_salle_refus.jpg))
5. [Maison sur l'île vide, contact avec la pente](captures/lot6/05_ile_maison_sur_la_pente.jpg)
6. [Pinceau : zone peinte avant application](captures/lot6/06_pinceau_zone_peinte.jpg)
7. [Résultat du pinceau, même cadrage](captures/lot6/07_pinceau_resultat.jpg)
8. [Invite d'activation de l'Ancre](captures/lot6/08_invite_ancre_premiere_personne.jpg)

Rapports bruts : `captures/lot6/*.json`.

## Limites constatées

- **Fluidité sur carte graphique non mesurée** : tout le rendu s'est fait en logiciel (1 à 3 images/s). Les essais « joués » tournent donc sans rendu (physique à 60 images/s fixes) ou avec téléportation du joueur pour les captures.
- Dans le laboratoire, la reconstruction des tuiles de terrain après une pose ou une annulation prend ≈ 1 s en rendu logiciel (le jeu reste réactif pendant l'attente).
- L'aperçu est un **voile vert** sur le modèle réel (les matériaux voxel ne gèrent pas la transparence d'instance).
- Le **confort dans l'escalier et aux portes est mesuré** (déplacement vertical de la caméra par image) mais pas ressenti à la main : à confirmer sur un vrai PC.
- La pente de 20 % du laboratoire se rend en marches de 20 cm (voxels) : visuellement « en terrasses », franchissable sans à-coup.
- Un cas d'usage par type de sélection, comme demandé ; pas d'inventaire de construction, de bibliothèque de bâtiments, d'export ni de remodelage de l'île d'ouverture (lots suivants).
- Pas de manette ; la barre de commandes est en français (accents facultatifs).
