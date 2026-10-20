# Bilan — Lot 1 : fondations graphiques 3D

## Livré

1. **Scènes** : `scenes/lab/graphics_lab.tscn` (laboratoire) et
   `scenes/island/first_island.tscn` (île de ~31 m + 3 îlots lointains).
2. **Modèles et matériaux** : 10 objets (blocs pierre / terre / herbe / bois, mur, dalle,
   escalier, table, établi, lampe à éclat), palette de 22 matières, végétation procédurale
   (arbres « parasol », touffes, fougères, fleurs), un matériau voxel unique.
3. **Caméra** : vol libre + orbite (ZQSD/WASD, souris, Espace/Ctrl, Shift, Échap, Tab, molette).
4. **Instructions** : voir le README (ouverture sous Windows, commandes, vérification).

## Vérifications réalisées (Godot 4.3 stable, Linux)

- Import headless du projet : **aucune erreur ni avertissement de script**.
- `tests/run_checks.gd` : **44 / 44 contrôles réussis**, dont :
  - maillage sans faces intérieures (1 voxel = 6 faces, cube 4³ = 96 faces, île test :
    faces générées = faces exposées) ;
  - déterminisme (même seed → même empreinte SHA-256, seed différente → île différente) ;
  - diamètre de l'île : 31,2 m ;
  - séparation cœur / surface : aucune cellule partagée, le cœur refuse la modification ;
  - 10 objets construits, emprises alignées sur 0,20 m, lampe avec lumière ;
  - chargement et exécution des deux scènes (maillages présents, caméra active).
- Captures d'écran réelles (rendu logiciel, `tools/capture.gd`) : `docs/captures/`.
- Temps de génération de l'île principale : ≈ 1 s de données + ≈ 1,3 s de maillage
  (4 cœurs, machine sans GPU) — environ 90 000 faces.

## Limites connues

- **Pas testé sur une vraie carte graphique ni sous Windows** : l'environnement de
  développement n'a pas de GPU. Les captures utilisent le rendu « Compatibilité »
  (OpenGL logiciel) : sans SSAO et avec des couleurs un peu plus saturées que le rendu
  Forward+ réel. À valider visuellement sur votre PC.
- Les messages `ERROR: Parameter "m" is null` dans les tests headless viennent du
  serveur de rendu factice de Godot en mode sans écran ; ils n'apparaissent pas en jeu.
- La génération est synchrone : l'île apparaît après ~2-3 s (gel bref au lancement ou
  quand on change de seed). Elle est aussi régénérée dans l'éditeur à l'ouverture de la scène.
- Pas de collisions (inutile pour la caméra volante) ; pas de niveaux de détail (LOD).
- Les feuillages sont opaques (pas de transparence ni d'animation au vent).
- La couche modifiable a une API (`IslandData.set_surface_voxel`) mais aucun outil de
  modification ni reconstruction partielle des chunks n'est branché.

## Prochaines étapes proposées

1. Valider le rendu sous Windows (Forward+) et ajuster `palette.json` / `lighting.json`.
2. Génération en arrière-plan (thread) avec apparition progressive des chunks.
3. Reconstruction d'un seul chunk après modification + collisions par chunk.
4. Placement de blocs / objets sur la grille (prévisualisation fantôme, rotation par 90°).
5. Végétation enrichie : feuillage animé par shader, herbes hautes, lianes sur falaises.
6. LOD pour les îlots lointains, puis évaluation de Voxel Tools pour les grands mondes.
