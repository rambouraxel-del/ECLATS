# Bilan — Lot 11 : fiabilité de l'éditeur, des sauvegardes et des performances

Branche `claude/lot11-fiabilite-optimisation` (partie de `0d57f01`). Détail, choix de conception et mesures : [FIABILITE_LOT11.md](FIABILITE_LOT11.md).

## Commits
| Commit | Contenu |
|---|---|
| `dc57058` | **Fiabilité** : relief 16 bits, écritures sûres, validation, session éditeur ↔ 3D, dialogue de sortie, maisons cohérentes |
| `12f1104` | **Optimisations** mesurées : début de trait, Ctrl+Z, collisions locales |
| dernier commit de la branche | finitions (l'éditeur retrouve son outil et ses réglages au retour de la 3D, nom de maison dans les messages), documentation, captures, recette |

## Corrections (constats tous confirmés dans le code)
1. **Relief > 25,4 m** : les retouches tiennent maintenant sur 16 bits (±2000 cellules). Le terrain rouvert est identique colonne pour colonne au terrain affiché ; les cartes v1 et v2 se relisent ; une valeur hors limites est refusée (fichier) ou limitée **et signalée** (pinceau).
2. **Session éditeur ↔ 3D** : même document, même historique Ctrl+Z, relief non recalculé.
3. **Dialogue de sortie** (quitter, ouvrir, générer, retour au menu depuis l'éditeur **ou** la 3D) : Enregistrer puis continuer / Continuer sans enregistrer / Annuler. Un échec d'enregistrement laisse la carte ouverte et modifiée, avec l'erreur.
4. **Écritures sûres** (cartes, constructions, progression) : fichier temporaire relu et validé, ancienne version gardée (`.bak`, relue si le fichier principal est abîmé). L'Ancre n'annonce « enregistrée » que si l'écriture a réussi (sinon avertissement et nouvelle tentative).
5. **Validation des imports** renforcée (version, types, bornes, doublons, couches, masque, matières, constructions) : refus expliqué, document courant intact.
6. **Maisons** : la plateforme garde sa hauteur absolue quand le relief de base est recalculé ; une modification qui casserait le raccord (chemin déplacé trop loin, maison hors de l'île, falaise au bord) est **refusée et expliquée** ; supprimer une maison **restaure** le terrain sans effacer les retouches faites depuis (Maj + clic droit : garder le terrain) ; Ctrl+Z remet tout.

## Mesures (CPU, rendu logiciel / headless, 4 cœurs Xeon 2,1 GHz — pas de GPU)
Plan 56 × 48 m / 120 × 120 m : relief recalculé à l'ouverture de la 3D **805 / 4 221 ms → ≈ 0** ; début de trait **9–44 → 0,2–0,4 ms** ; Ctrl+Z d'un trait **23 / 113 → 3 / 2,5 ms** ; collisions du sol après retouche locale **11 / 51 → 0,5 / 1,4 ms**.
**Sans gain, non modifié** : masques du mailleur (maillage identique, aucun gain mesuré), maillage d'une tuile (≈ 140 ms), lissage par coup (≈ 4,5 ms), île d'ouverture (100 s / 4,6 s depuis le cache, inchangés).

## Tests
| Type | Résultat |
|---|---|
| **Automatisés** (`godot --headless`) | Lots 1 à 10 inchangés : 180, 121, 50, 39, 68, 104, 64, 30 — **Lot 11 : 88**, tous à 0 échec |
| **Joués** (vrai jeu lancé au menu, entrées et boutons réels, rendu logiciel) | éditeur : 16 contrôles, 0 échec (pinceau, 3D, retour, Ctrl+Z, dialogue, échec d'enregistrement, maison, refus, marche jusque dans la maison) ; **île d'ouverture** (pilote automatique, collisions réelles) : trajet complet sans blocage (≈ 4,3 min), maison et étage, détour, Ancre (invite, activation), relance (Ancre active), chute → retour au quai |
| **Visuels** | 8 captures ci-dessous (rendu logiciel : lisibilité des interfaces, pas d'impression de fluidité) |

Les parcours demandés : (1) sculpter > 25,4 m, sauvegarder, rouvrir, retrouver le terrain + ancienne carte v2 → tests automatisés ; (2) modifier / 3D / retour / annuler + trois choix du dialogue + échec d'enregistrement → joué + automatisé ; (3) maison en pente, chemin ou zone modifié, sauvegarde et réouverture, fondations, seuil, trajet → joué + automatisé ; (4) JSON valide mal formé, version inconnue, écriture impossible → automatisé ; (5) île d'ouverture jusqu'à l'Ancre et relance → joué.

## Captures (`docs/captures/lot11/`)
1. [Éditeur avant le passage en 3D](https://github.com/rambouraxel-del/ECLATS/blob/claude/lot11-fiabilite-optimisation/docs/captures/lot11/01_editeur_avant_passage_3d.jpg) · 2. [La même carte en 3D](https://github.com/rambouraxel-del/ECLATS/blob/claude/lot11-fiabilite-optimisation/docs/captures/lot11/02_vue_3d_meme_carte.jpg) · 3. [Éditeur après le retour](https://github.com/rambouraxel-del/ECLATS/blob/claude/lot11-fiabilite-optimisation/docs/captures/lot11/03_editeur_apres_retour_3d.jpg) (même terrain, même historique)
4. [Annulation (Ctrl+Z) après le retour](https://github.com/rambouraxel-del/ECLATS/blob/claude/lot11-fiabilite-optimisation/docs/captures/lot11/04_annulation_ctrl_z.jpg)
5. [Dialogue de sortie](https://github.com/rambouraxel-del/ECLATS/blob/claude/lot11-fiabilite-optimisation/docs/captures/lot11/05_dialogue_de_sortie.jpg) · 6. [Échec d'enregistrement : carte intacte, erreur lisible](https://github.com/rambouraxel-del/ECLATS/blob/claude/lot11-fiabilite-optimisation/docs/captures/lot11/06_echec_d_enregistrement.jpg)
7. [Maison posée, chemin déplacé trop loin : modification refusée et expliquée](https://github.com/rambouraxel-del/ECLATS/blob/claude/lot11-fiabilite-optimisation/docs/captures/lot11/07_maison_modification_refusee.jpg) · 8. [Maison raccordée en 3D après modification du terrain](https://github.com/rambouraxel-del/ECLATS/blob/claude/lot11-fiabilite-optimisation/docs/captures/lot11/08_maison_raccordee_en_3d.jpg)

## Points restant ouverts
- Un recalcul structurel dans l'éditeur (4 s sur 120 × 120 m) reste dans le fil principal : il faudrait rendre `MapDoc.rebuild` asynchrone.
- La retouche locale du terrain 3D reste ≈ 200 ms par tuile (voxelisation + maillage) : à reprendre avec un maillage incrémental, en vérifiant les raccords entre secteurs.
- Fluidité réelle et sensation sur PC non évaluées (aucun GPU) ; l'interface du dialogue est jugée sur capture seulement.
- Maisons posées avant le Lot 11 : leur terrain d'origine n'est pas connu (suppression = terrain aménagé conservé, dit à l'utilisateur) ; seuil de conflit (8 cellules, 0,6 m d'écart de raccord) à valider à l'usage.
- Les cartes enregistrées en v3 ne s'ouvrent pas dans un jeu antérieur au Lot 11 (message de version).
