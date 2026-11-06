# Lot 11 — Fiabilité de l'éditeur, des sauvegardes et performances

Branche `claude/lot11-fiabilite-optimisation` (partie de `claude/lot10-remodelage-ile-ouverture`, `0d57f01`). Constats vérifiés dans le code, corrigés, puis mesures.

## 1. Constats vérifiés et corrections

| Constat | Vérifié | Correction |
|---|---|---|
| Retouches de relief limitées à ±127 cellules (25,4 m) : `set_delta` écrêtait en silence, le terrain affiché (`field.top`) continuait de monter | oui (`plan_layers.gd`, `map_doc.gd`) | retouches sur **16 bits** (±2000 cellules = ±400 m) ; au-delà, la hauteur affichée est **limitée** et l'éditeur le dit ; un fichier hors limites est refusé |
| La vue 3D recalculait le relief (`PlanTerrain.build` + `apply_layers`) et l'éditeur repartait d'un document neuf au retour (historique perdu) | oui (`map_island.gd`, `map_editor.gd`) | **session** (`MapSession`) : même document, même Ctrl+Z ; la 3D réutilise une copie du relief |
| Quitter, ouvrir ou générer perdait les modifications sans prévenir | oui (`_on_blank`, `_on_generate`, `open_file`, bouton Menu) | dialogue **Enregistrer puis continuer / Continuer sans enregistrer / Annuler** ; `App.open` le déclenche pour toute sortie de l'éditeur ou de la 3D |
| Écritures directes (`FileAccess.WRITE`) : une panne laissait un fichier tronqué ; l'Ancre confirmait sans vérifier | oui (cartes, constructions, `GameSave`) | `SafeFile` : fichier temporaire, relecture + validation, ancienne version gardée en `.bak`, erreur lisible ; l'Ancre active la partie mais **n'affiche « enregistrée » que si c'est vrai** (sinon avertissement et nouvelle tentative) |
| Import peu contrôlé (coordonnées, types, doublons, couches) | oui (`from_dict`) | bornes, types, doublons, types de repère, couches (taille, base64, masque 0/1, matières existantes), constructions (entiers de grille, nombre d'éléments, doublons) |
| Maison posée puis relief de base recalculé (chemin, zone déplacés) : les retouches de la maison sont **relatives** à l'ancien relief → plateforme décalée | oui (`place_house` écrit `delta = top − base`) | chaque maison mémorise ses colonnes (`HouseTerrain`) ; au recalcul, la **hauteur absolue** est conservée ; si la modification casserait le raccord ou la plateforme, elle est **refusée et expliquée** |
| Suppression d'une maison ≠ annulation de sa pose (le terrain aménagé restait) | oui (`remove_house`) | suppression = **restauration** colonne par colonne ; une colonne retouchée depuis la pose est **conservée** ; Maj + clic droit : garder le terrain |

### Choix de conception (à valider)
- **Limite de relief ±2000 cellules (400 m)** : très au-delà des îles (120 m max) ; 16 bits laissent de la marge. Écrêtage explicite, jamais silencieux.
- **Format de carte v3** : `delta16` (entiers 16 bits compressés) ; les v1 et v2 (octets, 128 = rien) se relisent par migration exacte. Une carte v3 est refusée par un jeu plus ancien avec un message de version (c'était déjà le comportement prévu).
- **Maison + modification du plan** : on préserve la hauteur absolue des colonnes aménagées et on refuse (au lieu de « réparer » en silence) tout changement qui éloigne le chemin du raccord (écart > demi-largeur + 0,6 m), sort la maison de l'île ou crée une falaise de plus de 8 cellules (1,6 m) au bord de la plateforme. Le chemin peut bouger de quelques centimètres.
- **Suppression** : restauration par défaut (même résultat que Ctrl+Z de la pose, mais sans toucher aux retouches ultérieures) ; les maisons posées avant le Lot 11 n'ont pas gardé leur terrain d'origine → le terrain aménagé reste, et le message le dit.
- **Dialogue de sortie** : porté par `App`/`MapSession` (et non par l'éditeur) pour fonctionner aussi depuis la vue 3D.
- **Calculs longs** : la vue 3D calcule le relief dans un fil de calcul (écran de chargement animé) quand il n'est pas réutilisé ; dans l'éditeur, un recalcul structurel (4 s sur 120 × 120 m) reste dans le fil principal (message d'attente affiché avant). Non traité : il demanderait de rendre `MapDoc.rebuild` asynchrone.

## 2. Mesures (mêmes conditions avant / après)

Machine : Intel Xeon 2,1 GHz, 4 cœurs, Linux, Godot 4.3. **Rendu logiciel (xvfb) ou « dummy » en headless : aucun GPU.** Les temps sont des CPU ; la fluidité d'affichage n'est pas mesurée. Outil : `tools/lot11_mesures.gd` (médiane de 3). Données : `docs/mesures_lot11_avant.json`, `docs/mesures_lot11_apres.json`.

Plan 56 × 48 m (312 colonnes de côté) · plan 120 × 120 m (664 colonnes) :

| Mesure | Avant (56 / 120) | Après (56 / 120) |
|---|---|---|
| Relief du plan (génération du document) | 788 ms / 4 320 ms | inchangé (794 / 4 033) |
| Éditeur → 3D : relief recalculé | 805 ms / 4 221 ms | **≈ 0 ms** (relief du document réutilisé) |
| Éditeur → 3D : terrain 3D (tuiles, collisions) | 1 295 ms / 5 279 ms | inchangé (1 240 / 5 173) |
| Début d'un trait de pinceau | 9,4–13,7 ms / 44 ms | **0,2 ms / 0,4 ms** |
| Un coup de lissage | 4,8 ms / 4,1 ms | inchangé (4,7 / 4,3) |
| Ctrl+Z d'un trait | 23 ms / 113 ms | **3 ms / 2,5 ms** |
| Collisions du sol après retouche locale | 10,7 ms / 51 ms (carte entière) | **0,45 ms / 1,4 ms** (rectangle) |
| Retouche locale du terrain 3D (tuiles) | 484 ms / 266 ms | inchangé (431 / 219) |
| Une tuile : voxelisation / maillage | 59 / 141 ms ; 71 / 138 ms | inchangé |
| Île d'ouverture, premier chargement | 100,2 s (Lot 10) | 100,8 s (inchangé) |
| Île d'ouverture, depuis le cache | 4,3 s (Lot 10) | 4,6–5,0 s (inchangé) |

### Ce qui n'a pas été optimisé, et pourquoi
- **Masques du mailleur** (`masks.resize(cells*6)` + `fill(0)`) : essai sans le `fill` (maillage identique, empreinte vérifiée) — **aucun gain mesurable** (tuile 136 ms contre 141 ms, dans le bruit). Changement abandonné ; le coût est dans le parcours des faces, pas dans l'allocation.
- **Retouche locale du terrain 3D** : dominée par la voxelisation et le maillage de 1 à 4 tuiles de 16 m (≈ 200 ms par tuile). Une refonte en tuiles plus petites ou un maillage incrémental risquerait des trous aux limites des secteurs : non entrepris.
- **Lissage** : la copie complète de `_hf` par coup (n² flottants) est supprimée (fenêtre locale), mais le coût d'un coup est dû à la boucle de moyenne 5 × 5 : inchangé.
- **Relief du plan** et **chargement de l'île d'ouverture** : non touchés.
