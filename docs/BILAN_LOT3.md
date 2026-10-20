# Bilan — Lot 3 : première île habitée, textures et enrichissement graphique

## Ce qui a été livré

1. **Île habitée** (`scenes/island/colony_island.tscn`, touche F4, scène de démarrage) : île flottante de
   ~46 m, place centrale à fontaine, marché (étal, kiosque, établi, charrette), maisons, atelier à forge,
   entrepôt, tour de guet, potager clos, belvédère sur les nuages, port avec embarcadère et **bateau
   volant**, colline de l'**Ancre** (plateforme de téléportation + piédestal d'Ancre, escalier monumental,
   arche et colonnes en ruine, amas de cristaux, sanctuaire). Chemins, escaliers, paliers.
2. **Textures** : nouveau shader sans aucune image (voir ci-dessous), 90 matières, usure par matière.
3. **Arbres et végétation** : 6 espèces (chêne, parasol, pin, saule pleureur, bouleau, fruitier), 14 variantes,
   rochers, 6 espèces de plantes basses, trois herbes (tondue, sauvage, piétinée), trois terres.
4. **Les 5 assets du Lot 2** : repris avec le nouveau shader (bois veinés, pierre mouchetée, cuivre oxydé,
   toile à trame, cristaux à facettes), avec niveaux de détail.
5. **Bibliothèque** : 55 assets au total — 25 objets nouveaux, 5 bâtiments, embarcadère, bateau volant,
   14 arbres, 4 rochers (liste dans `docs/ASSETS.md`).
6. **Ambiances** : plein jour (F5), coucher de soleil (F6), nuit (F7) ; ciel à blocs, nuages voxel, étoiles, lune ;
   les lanternes et fenêtres s'allument progressivement.
7. **Optimisations** : voir `docs/OPTIMISATION.md`.
8. **Galerie de matériaux** (`scenes/lab/material_gallery.tscn`, F8) et laboratoire conservé.
9. **Tests** : 180 contrôles automatiques (103 du Lot 2 conservés).

## La règle des pixels de 2 cm

Après un premier essai trop « photographique », la règle a été fixée avec vous : **aucune texture image,
une seule couleur plate par pixel de 2 cm, nuancée par rapport à ses voisins**. Le shader découpe chaque
face en pixels de 2 cm (5 par voxel de bâtiment, 10 par voxel de terrain, 1 par microvoxel d'objet) et
calcule la couleur de chaque pixel par hachage entier. Le projet ne contient plus aucune image de texture
(un test le vérifie).

## Mesures (Godot 4.3, Linux, rendu logiciel — NON représentatives d'un GPU)

| Mesure | Valeur |
|---|---|
| Colonie : éléments posés | 137 (104 en MultiMesh, 33 en scène complète pour lumière/animation) |
| Colonie : MultiMesh / instances regroupées | 300 / 1 389 (hors herbes) |
| Colonie : nœuds MeshInstance3D | 287 pour toute l'île |
| Colonie : triangles terrain | 286 700 |
| Colonie : triangles props (vue d'ensemble, LOD mélangés) | ≈ 1,16 M en LOD0 + 0,19 M LOD1 + 0,04 M LOD2 (avant culling) |
| Colonie : appels de dessin / primitives (vue d'ensemble, rendu logiciel) | ≈ 1 340 / ≈ 1,6 M |
| Colonie : boîtes de collision | 109 |
| Génération de l'île (4 cœurs, sans GPU) | ≈ 8 s (terrain 46 m de large + maillage) |
| Bibliothèque : 55 assets, triangles cumulés LOD0 | 971 000 |
| Poids des maillages générés | ≈ 26 Mo (compressés, dont arbres et bâtiments) |

Exemples (LOD0 → LOD1 → LOD2) : maison de colon 37 204 → 7 580 → 1 516 ; piédestal d'Ancre 26 978 → 6 980 → 1 150 ;
chêne 38 718 → 6 350 → 1 556 ; bateau volant 26 434 → 8 260 → 1 546.

## Ce qui est testé automatiquement

Imports Godot 4.3 sans erreur ; 180 contrôles (`tools/check.sh`) : règle des pixels (aucune image, shader sans
texture, 2 cm / 10 cm / 20 cm), LOD (échantillonnage, silhouettes fines conservées), 55 assets (scène, fiche, budgets,
LOD décroissants, collisions dans l'emprise, absence de faces internes sur un échantillon, déterminisme),
instanciation (regroupement, plages de visibilité, collisions), plan de village (hauteurs, matières, zones réservées,
génération déterministe, île du Lot 2 inchangée), ambiances (lanternes, étoiles, nuages), chargement de 4 scènes
en headless.

## Ce qui doit être validé sur GPU Windows

- **Performances réelles** : fluidité (FPS), temps de chargement, mémoire GPU. Les mesures ci-dessus viennent d'un
  rendu logiciel sans GPU : seuls les comptes de triangles, d'objets et d'appels de dessin sont utiles.
- Rendu **Forward+** (SSAO, ombres 4 cascades, tonemapping) : les captures utilisent le mode « Compatibilité »
  (OpenGL logiciel), sans SSAO et avec un contraste un peu différent.
- Lisibilité des motifs de pixels à la résolution de votre écran (4K, 1440p) et sans scintillement en mouvement.
- Visibilité des lumières nocturnes et force du bloom.
- Réglage des distances de LOD (`lod_ranges`) selon vos préférences.

## Limites connues

- La génération de l'île prend ≈ 8 s sans GPU (synchrone) ; pas de chargement progressif.
- Le bateau « flotte » avec une simple houle (hauteur) ; pas de physique, pas d'hélices animées.
- L'eau de la fontaine est un plan de pixels animé, pas un fluide.
- Les collisions sont des boîtes simplifiées ; pas de collisions fines (escaliers à marcher) ni de navmesh.
- Les ombres des nuages et la brume volumétrique ne sont pas implémentées ; la brume est celle du moteur.
- Pas d'occlusion culling dédié (le moteur gère le frustum et les plages de visibilité).
- Le belvédère et certains arbres du bord masquent parfois les vues prédéfinies 9 et 0 selon la graine ; utiliser la
  caméra libre.

## Prochaines étapes proposées

1. Valider sur Windows ; ajuster les distances de LOD et le nombre de lumières à ombres.
2. Génération en arrière-plan avec apparition progressive des chunks.
3. Hauteur de personnage : navmesh, collisions d'escaliers, ombres de nuages.
4. Variantes d'architecture (greniers, serres, ateliers spécialisés), intérieurs.
5. Système de placement sur la grille de 20 cm avec les assets de la bibliothèque.
