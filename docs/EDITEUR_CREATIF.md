# Éditeur d'îles créatif

Mode développeur intégré au jeu pour construire et modifier librement une île d'histoire (confort « créatif »). Il édite le **même document**
que l'éditeur de carte 2D (`MapDoc` : plan, relief, matières, masque de protection, maisons, historique) et l'affiche avec la **même île 3D**
(`LabWorld`) : une carte faite ici se rouvre dans l'éditeur 2D et dans le jeu, et réciproquement.

## Lancer (Mac, Windows, Linux)
1. Ouvrir le projet dans Godot 4.3 et lancer (F5), ou `godot --path .`.
2. Menu principal → **Outils développeur** → **Éditeur d'îles créatif (3D)**. Au premier lancement une **île vide** (ovale ≈ 40 × 32 m, plateau plat) s'ouvre.
3. Menu **Fichier** (en haut à gauche) : *Nouvelle île vide*, *Générer une île (graine)…*, *Ouvrir une carte…* (cartes de `user://cartes/`), *Enregistrer*, *Enregistrer sous…*, *Exporter une copie…*.
   Dossier des cartes : `~/Library/Application Support/Godot/app_userdata/ÉCLATS/cartes/` (Mac) · `%APPDATA%\Godot\app_userdata\ÉCLATS\cartes\` (Windows).

## Commandes
| Touche | Action |
|---|---|
| **V** | vue aérienne ↔ première personne (vol) |
| **P** | **mode jeu** : l'île se parcourt avec collisions (comme dans le jeu) ; P revient à l'éditeur |
| **1** Sélection · **2** Poser · **3** Relief · **4** Matière · **5** Carte · **6** Générer · **7** Atelier | outils |
| **I** | inventaire créatif (recherche, catégories, aperçu 3D tournant) |
| WASD / flèches · Q E · molette | aérien : déplacer, tourner, zoomer |
| WASD · Espace / C · Maj · Tab · F | première personne : avancer, monter / descendre, courir, libérer la souris, marche au sol ↔ vol |
| Clic · **G** · R / Maj+R · Ctrl+D · **L** · Suppr | sélectionner · déplacer · tourner par 15° · dupliquer · verrouiller · supprimer |
| **N** | aimantation à la grille de 0,5 m (poser / déplacer) |
| [ ] · − + | taille du pinceau · intensité (ou échelle de l'objet en pose) |
| **Ctrl+Z** / **Ctrl+Y** (Ctrl+Maj+Z) | annuler / rétablir **une opération entière** (un trait de pinceau, une pose, une génération…) |
| **Ctrl+S** · Ctrl+O | enregistrer · ouvrir |

Les confirmations sont réservées à ce qui peut faire perdre du travail (remplacer une carte modifiée non enregistrée) ; poser, déplacer, supprimer se défont avec Ctrl+Z.

## Outils
- **Sélection** : clic sur un objet ou une maison (cadre jaune ; rouge si verrouillé). Glisser l'objet ou G pour le déplacer, R pour le tourner, Ctrl+D pour le dupliquer, L pour le verrouiller, Suppr pour le retirer. Maison : *Reprendre* (la retire, terrain restauré, et la remet en main pour la replacer) ou *Supprimer*.
- **Poser** : choisir un élément dans l'inventaire (catégories : Arbres, Rochers, Ruines et vestiges, Mobilier, Marché et village, Maisons, Port et navires, **Mes maisons**). Aperçu translucide vert (rouge si impossible), posé sur le sol réel, aimanté (N). Un **modèle de maison** est évalué par le système de placement des maisons (plateforme, talus, raccord du seuil au chemin) : l'aperçu dit pourquoi une implantation est refusée ; **K** active / coupe le raccord au chemin, **R** tourne d'un quart de tour.
- **Relief** : monter, creuser, aplanir, adoucir ; taille et intensité réglables ; la zone d'effet est dessinée sur le sol. Les colonnes protégées ne bougent pas.
- **Matière** : 11 matières du sol (herbe, mousse, terre, sentier, gravier, pavés, roche…) ; clic droit = effacer la peinture.
- **Carte** : *Zones* (disques prairie, bois, plateau, crique, falaise…), *Chemins* (clics, Entrée pour finir ; points déplaçables à la souris, double-clic pour en ajouter, clic droit pour en retirer), *Repères* (point de vue ; point de départ), *Protéger* (colonnes **rouges** que ni les pinceaux ni les régénérations ne touchent), *Contour* (sommets déplaçables). Une zone, un chemin ou le contour redessinent le relief de base (≈ 1 s) ; les retouches sont conservées.
- **Générer** : **Forêt** (arbres de 12 variétés + rochers) ou **Marché** (étals en couronne ouverts vers le centre, caisses, tonneaux, puits, panneau) dans un cercle réglable ou *dans la zone peinte* sous le curseur. Graine +1 / **G** : nouvelle variante au même endroit. Les objets produits sont des objets ordinaires (déplaçables, supprimables un à un). À chaque génération : les objets **verrouillés (🔒)**, posés **à la main** ou situés en **zone protégée** sont conservés ; les autres objets générés de la zone sont remplacés. Emplacement refusé : hors île / bord, zone protégée, pente forte, chemin, maison, objet voisin.
- **Atelier (7)** : ouvre l'atelier de construction en première personne (salle grise, mode construction actif) avec la session de la carte ; **F6** revient à l'éditeur. Outils : sol, fondations, mur, porte, fenêtre, pièce, toit, **escalier (9)**, modifier ; B quitte / entre le mode construction ; l'**enregistrement** d'une maison (panneau du mode construction) la place dans `user://maisons/` → elle apparaît dans l'inventaire, catégorie *Mes maisons*.

## Données : carte `eclats-carte` v4
v4 ajoute `objets` : `{id, kind:"asset", ref (id d'asset), pos [x,z], yaw (degrés), scale, lift, locked, group ("manuel" | "foret" | "marche")}`. Les objets suivent le sol (la hauteur est recalculée si le relief change dessous). Les cartes v1 à v3 se rouvrent sans perte ; un fichier v4 invalide est refusé avec une phrase d'explication (type d'objet inconnu, échelle hors limites, identifiant en double…). Les objets ne font pas partie de la signature du plan : poser ou déplacer un objet ne recalcule pas le relief.

## Code
`scripts/creative/` : `creative_editor.gd` (scène, caméras, outils, entrées), `creative_ui.gd` (barre, options, inventaire, dialogues), `creative_objects.gd` (objets → nœuds, sélection par rayon), `asset_catalog.gd` (catalogue de l'inventaire, mêmes fiches que la galerie 3D), `composer.gd` (forêt, marché).
Réutilisés : `MapDoc` (opérations, annulation, **rétablissement ajouté**, régénération, maisons), `MapSession` (fichier et dialogue de sortie), `LabWorld` (terrain par tuiles), `HousePad`, `Explorer`, `BuildMode` (**outil escalier ajouté**), `ConstructionView`.
Tests : `tests/run_checks_creatif.gd` (51 contrôles). Recette jouée + captures : `tools/creatif_recette.gd`.

## Limites connues
Voir le bilan de livraison (liste à jour des manques et de la façon de les reproduire).
