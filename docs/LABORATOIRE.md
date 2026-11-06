# Laboratoire développeur (Lot 6)

Deux environnements, **mêmes outils**, en première personne :

- **Salle grise** : sol plat de 30 × 30 m, murs et plafond gris.
- **Île vide** : une petite île (≈ 54 × 50 m), versant plat à l'ouest, **pente de 20 % (≈ 11°)** accessible à pied, replat à l'est.

Accès : menu principal → **Outils développeur** → *Laboratoire développeur — salle grise* ou *— île vide* (la salle s'ouvre aussi avec **F12**).
Échap : pause (Reprendre / Retour au menu principal).

## Les trois sélections (aperçu visible dans le monde)

| Outil | Touche | Geste | Aperçu | Usage |
|---|---|---|---|---|
| **Point** | 1 | viser le sol, clic | anneau + piquet cyan | arbre, rocher |
| **Rectangle** | 2 | clic sur un coin, clic sur le coin opposé (**R** : emprise imposée 3,50 × 3,50 m) | contour jaune posé sur le relief, **dimensions affichées** (« 3,50 × 3,50 m ») | maison |
| **Pinceau** | 3 | clic maintenu pour peindre, clic droit efface, molette ou **[** **]** = rayon | zone verte ; après « Aperçu » : déblai (orange), remblai (bleu), niveau (vert) | aplanir le terrain |

Suppr efface les sélections. **Tab** libère la souris pour cliquer le panneau (clic dans la vue : la souris est reprise).

## Génération : panneau et barre de commandes (T)

Le panneau (à droite) et la barre (touche **T**, ou **/**) font **la même chose** : même sélection, même logique (`LabController`).

```
/generer maison --graine 42
/generer maison --graine 42 --emprise 3.5x3.5 --yaw 0 --murs pierre --toit ardoise
/generer arbre  --espece chene --graine 7
/generer rocher --famille bloc --graine 3 --echelle 1.2
/aplanir [--niveau 7.0] [--rayon 1.3] [--trace x,z;x,z…]
/rect 3.5 3.5     /point x z     /pinceau 1.5     /effacer
/confirmer   /annuler (l'aperçu)   /defaire (Ctrl+Z)   /recette   /rejouer   /aide
```

Maison : le rectangle donne l'emprise (porte au sud = côté +z ; `--yaw` tourne par quarts de tour ; par défaut la porte regarde le joueur).
Une emprise de 3,50 × 3,50 m reçoit une **cabane** d'une pièce (bloc de 3,0 × 2,6 m, cour devant la porte). Au-delà d'environ 5 m de large, c'est une maison simple de deux pièces.

## Aperçu, confirmation, annulation

1. **Aperçu** (bouton, **G**, ou la commande) : le modèle apparaît sous un voile vert, avec la plateforme prévue ; le message résume l'opération. Le terrain n'est **pas** modifié.
2. **Confirmer** (**Entrée**) applique ; **X** (ou « Annuler l'aperçu ») abandonne.
3. **Ctrl+Z** annule l'opération **entière** : objet, collisions, réservations, relief **et raccord au sol** (talus et cour de la maison).
4. Si l'emprise ou la pente est incompatible, la **raison** s'affiche en rouge et rien n'est modifié : emprise trop petite, trop près du bord, espace occupé, dénivelé trop fort (au plus 1,20 m sous l'emprise, 60 cm de déblai / 1 m de remblai pour le pinceau), etc.

## Copier la recette

**Copier la recette** (bouton ou **C**) place dans le presse-papiers (et dans `user://lab_recette.txt`) la commande qui reproduit l'opération :

```
/generer maison --graine 42 --emprise 3.5x3.5 --yaw 0
```

Elle contient le générateur, la graine, l'emprise, l'orientation et les réglages. **Rejouer la recette copiée** (ou la coller dans la barre T) sur l'autre environnement
donne **la même variante** (même plan, toit, murs, ouvertures) ; le **raccord au sol est calculé pour le site** : 0 colonne retouchée dans la salle plate,
plus d'un millier sur la pente (talus 1:3, cour ramenée au niveau fini).

## Réutilisation du Lot 4 / 5

`TerrainField` et `TerrainEditor` (plateforme + talus), `PlacementSystem`, `BuildingPlanner`/`BuildingBuilder` (nouvelle archétype `hut`, options `W`, `D`, `roof`, `wall`),
`TreeGenerator`, `RockGenerator`, `AuthoredTerrain` / `AuthoredIslandBuilder` (voxels par tuiles) et `AuthoredIslandView` (collisions).
Code : `scripts/lab/dev/` (`lab_world.gd` terrain et opérations, `lab_selection.gd`, `lab_controller.gd`, `lab_commands.gd`, `lab_ui.gd`, `dev_lab.gd`).

## Limites connues

- Un cas d'usage par type de sélection ; pas d'inventaire de construction, pas de bibliothèque complète de bâtiments, pas d'export (lots suivants).
- La reconstruction des tuiles de terrain après une pose prend ≈ 1 s en rendu logiciel (sans rendu bloquant, mais perceptible).
- Les « fantômes » sont un voile vert sur le vrai modèle (les matériaux voxel ne gèrent pas la transparence).
