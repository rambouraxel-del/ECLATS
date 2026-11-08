#!/usr/bin/env python3
"""Échelle de l'île d'ouverture (essai « échelle et immersion ») : agrandit un peu les arbres et rochers qui paraissent petits
face à un personnage de 1,50 m. Part de l'île du Lot 11 (archive) et réécrit la carte jouée ; idempotent.
   python3 tools/echelle_ile.py [hauteurs.json]    (hauteurs.json = [[indice, espèce, hauteur_m, rayon_tronc], …], voir la doc)
Règles (aucun agrandissement global) :
  arbres de moins de 5,6 m (chênes bas, fruitiers, pleureurs, arbres morts) : ×min(1,25 ; 6,2 / hauteur) ;
  blocs (« boulder ») d'échelle ≤ 1,0 et affleurements d'échelle ≤ 1,0 : ×1,25 ; ruines et formations inchangées."""
import json, os, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
src = os.path.join(root, "config/islands/archive/ile_ouverture_lot11.json")
dst = os.path.join(root, "config/islands/ile_ouverture.json")
d = json.load(open(src))
heights = {}
if len(sys.argv) > 1:
    for i, sp, h, r in json.load(open(sys.argv[1])):
        heights[i] = h
nt = nr = 0
for i, t in enumerate(d["trees"]):
    h = heights.get(i)
    if h is not None and h < 5.6:
        t["scale"] = round(min(1.25, 6.2 / h), 2)
        nt += 1
for r in d["rocks"]:
    if r["family"] in ("boulder", "outcrop") and float(r.get("scale", 1.0)) <= 1.0:
        r["scale"] = round(float(r.get("scale", 1.0)) * 1.25, 2)
        nr += 1
json.dump(d, open(dst, "w"), ensure_ascii=False, indent=1)
print("arbres agrandis :", nt, "· rochers agrandis :", nr)
