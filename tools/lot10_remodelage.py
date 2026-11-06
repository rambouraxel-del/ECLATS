#!/usr/bin/env python3
"""Lot 10 — remodelage de l'île d'ouverture, À LA MAIN mais REPRODUCTIBLE.

Part de la carte du Lot 5 (config/islands/archive/ile_ouverture_lot5.json) et applique des retouches EXPLICITES
(relief, tracés, placements) : le résultat est config/islands/ile_ouverture.json.
    python3 tools/lot10_remodelage.py            # étapes 1 et 2
    python3 tools/lot10_remodelage.py --etape 1  # quai et hameau seulement
Aucun hasard caché : chaque position est écrite ici (les aides `along` ne servent qu'à les calculer).
Mètres ; x vers l'est, z vers le sud.
"""
import json, math, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "config/islands/archive/ile_ouverture_lot5.json")
DST = os.path.join(ROOT, "config/islands/ile_ouverture.json")


def along(pts, s, off=0.0):
    """Point situé à la distance s (m) du début de la polyligne, décalé de off (m, > 0 = à droite du sens de marche,
    avec x vers l'est et z vers le sud). Renvoie [x, z] arrondi au cm."""
    acc = 0.0
    for a, b in zip(pts, pts[1:]):
        l = math.dist(a, b)
        if acc + l >= s or b is pts[-1]:
            t = max(0.0, min(1.0, (s - acc) / l))
            x = a[0] + (b[0] - a[0]) * t
            z = a[1] + (b[1] - a[1]) * t
            dx, dz = (b[0] - a[0]) / l, (b[1] - a[1]) / l
            return [round(x - dz * off, 2), round(z + dx * off, 2)]
        acc += l
    return list(pts[-1])


def path_by_id(d, pid):
    return next(p for p in d["paths"] if p["id"] == pid)


def drop_props(d, pred):
    d["props"] = [p for p in d["props"] if not pred(p)]


def near(p, x, z, r):
    return math.dist(p["pos"], (x, z)) <= r


class Seeds:
    """Graines des objets ajoutés : numérotées à partir d'une base, dans l'ordre d'écriture (donc stables)."""
    def __init__(self, base):
        self.n = base

    def __call__(self):
        self.n += 1
        return self.n


def etape1(d):
    tree_seed = Seeds(30000)
    rock_seed = Seeds(31000)

    def tree(sp, pos):
        d["trees"].append({"species": sp, "pos": pos, "seed": tree_seed()})

    def rock(fam, pos, scale=1.0, variant=None):
        r = {"family": fam, "pos": pos, "seed": rock_seed(), "scale": scale}
        if variant:
            r["variant"] = variant
        d["rocks"].append(r)

    def prop(i, pos, yaw=0):
        d["props"].append({"id": i, "pos": pos, "yaw": yaw})

    # Épaules de raccord plus larges (2 x l'ordinaire) sur les tracés retouchés : moins de cassures de relief
    for pid, sk in (("descente_du_col", 24), ("rue_du_hameau", 20), ("detour_du_verger", 20)):
        path_by_id(d, pid)["skirt"] = sk

    # ---------------------------------------------------------------- QUAI
    # Départ SUR le ponton (au pied de la passerelle du navire) : navire à droite, grève et sentier devant.
    d["spawn"] = {"pos": [-67.5, 112.5], "pier_m": 7.0, "yaw_deg": 0.0}
    # Mobilier d'origine du quai : dispersé -> regroupé par usage (déchargement, balisage, sortie).
    drop_props(d, lambda p: (p["id"] in ("mooring_post", "crate_stack", "barrel_set", "crystal_lamp", "banner_stand")
                             and p["pos"][1] > 90.0) or (p["id"] == "signpost" and near(p, -80.0, 92.5, 1.0)))
    # 1. pied du ponton : lampes de part et d'autre, bitte d'amarrage
    prop("crystal_lamp", [-71.2, 112.2], 0)
    prop("crystal_lamp", [-63.8, 112.2], 0)
    prop("mooring_post", [-64.0, 109.6], 1)
    # 2. aire de déchargement, côté navire (est) : caisses et tonneaux groupés contre le bord
    prop("crate_stack", [-61.6, 110.4], 1)
    prop("barrel_set", [-60.2, 108.8], 0)
    prop("crate_stack", [-61.9, 107.9], 2)
    # 3. balisage de la sortie : panneau d'avis + porte-bannière à la fourche, lampes jusqu'au pied des lacets
    prop("notice_board", [-71.6, 106.4], 3)
    prop("banner_stand", [-65.2, 103.0], 0)
    prop("signpost", [-72.0, 100.4], 1)
    prop("crystal_lamp", [-70.0, 104.6], 0)
    prop("crystal_lamp", [-74.0, 93.6], 0)
    prop("crystal_lamp", [-83.8, 91.8], 0)
    prop("signpost", [-84.2, 92.8], 1)
    # Tracé : chaussée dallée du ponton jusqu'au pied des lacets (contraste net avec la grève), puis sentier de terre
    d["paths"].insert(0, {"id": "quai_dallage", "name": "Dallage du quai", "kind": "main", "width": 2.4,
                          "material": "cobble",
                          "pts": [[-67.5, 112.0], [-67.5, 103.5], [-70.5, 99.0], [-75.0, 95.0], [-82.5, 90.0]]})
    sent = path_by_id(d, "sentier_des_falaises")
    sent["pts"] = [[-82.5, 90.0]] + sent["pts"][3:]
    # Pied de falaise : chaos d'éboulis au nord de la grève, deux pins et deux blocs en « porte » devant les lacets
    # (positions testées : la pose automatique en refusait d'autres — pente, espace réservé, hors île)
    for pos, sc in (([-60.5, 91.0], 1.0), ([-54.0, 93.0], 1.2)):
        rock("boulder", pos, sc)
    tree("pine", [-58.0, 94.5])
    tree("pine", [-51.0, 97.5])

    # ---------------------------------------------------------------- MONTÉE (corniche) jusqu'au col
    cor = sent["pts"][-8:]           # derniers points du sentier : de (-122.5, 5) au col
    # Alternance serré / ouvert : bosquets du côté de la falaise, blocs au bord du vide, puis vue qui se dégage
    for s, off, sp in ((6, 5.5, "pine"), (9, 7.0, "pine"), (14, 6.0, "birch")):
        tree(sp, along(cor, s, off))
    rock("boulder", along(cor, 18, 4.5), 1.3, "mass")
    rock("boulder", along(cor, 20, -5.2), 1.0)
    for s, off, sp in ((26, 6.5, "pine"), (29, 5.0, "pine"), (33, 7.5, "birch"), (36, -6.0, "birch")):
        tree(sp, along(cor, s, off))
    rock("boulder", along(cor, 40, 4.8), 1.5, "slab")
    for s, off, sp in ((44, 6.0, "pine"), (47, -6.5, "pine"), (50, 5.5, "pine")):
        tree(sp, along(cor, s, off))
    # Le menhir et son bloc d'accompagnement encadrent l'arrivée au col
    rock("boulder", [-97.5, -30.0], 1.0, "spike")

    # ---------------------------------------------------------------- HAMEAU : approche, révélation, place
    # Une butte barre la vallée : depuis le col le hameau est caché ; en haut de la butte, le point de
    # révélation R = (-60, -25,5), il apparaît d'un coup, à ~50 m, avec la fontaine dans l'axe d'une avenue rectiligne.
    R = [-60.0, -25.5]
    F = [-10.0, 0.0]
    d["terrain"]["shapes"].append({"id": "butte_de_revelation", "type": "bump", "c": R, "r": 11.0, "h": 4.0})
    desc = path_by_id(d, "descente_du_col")
    desc["pts"] = [[-92.5, -37.5], [-84.0, -34.5], [-76.0, -31.5], [-68.0, -28.5], R, [-48.0, -19.4], [-37.0, -13.8],
                   [-26.0, -8.2], [-17.2, -3.7]]
    # Avant la butte : bosquets et blocs qui cadrent la montée, côté sud puis côté nord (aucun obstacle sur l'axe de l'avenue)
    tree("pine", [-72.0, -24.0])
    tree("pine", [-67.5, -21.0])
    tree("birch", [-70.5, -37.0])
    rock("boulder", [-75.5, -26.0], 1.2, "mass")
    rock("boulder", [-73.5, -37.5], 1.0)
    # Entrée de la place, dans l'axe : deux porte-bannières encadrent l'avenue (repérables de loin), lampes en alignement
    prop("banner_stand", [-16.5, -6.0], 3)
    prop("banner_stand", [-18.7, -1.8], 3)
    prop("crystal_lamp", [-21.6, -8.1], 0)
    prop("crystal_lamp", [-23.4, -4.7], 0)
    prop("crystal_lamp", [-32.3, -13.5], 0)
    prop("crystal_lamp", [-34.1, -10.1], 0)
    # Place : le marché s'organise en rue (étals sur le côté sud de la rue du hameau), accès à la maison libre
    prop("market_stall", [9.5, 5.4], 2)
    prop("market_stall", [14.2, 5.6], 2)
    prop("crate_stack", [11.9, 7.6], 0)
    prop("barrel_set", [16.4, 7.3], 0)
    # Dégager l'axe de révélation : le parasol et le fruitier qui masquaient la fontaine sont décalés
    d["trees"] = [t for t in d["trees"] if not (t["species"] == "parasol" and near(t, -21.25, -11.25, 0.5))
                  and not (t["species"] == "fruit" and near(t, -23.96, 2.13, 0.5))]
    tree("parasol", [-26.5, 4.5])
    tree("parasol", [3.2, 6.8])          # grand parasol derrière la fontaine, vu depuis le point de révélation
    # Maison visitable : lampes de part et d'autre de l'allée de porte
    prop("crystal_lamp", [-9.7, -9.5], 0)
    prop("crystal_lamp", [-5.3, -9.5], 0)
    # Détour du verger : deux arbres fruitiers marquent le départ à côté du panneau
    tree("fruit", [29.4, 6.8])
    tree("fruit", [36.4, 8.4])


def etape2(d):
    tree_seed = Seeds(32000)
    rock_seed = Seeds(33000)

    def tree(sp, pos):
        d["trees"].append({"species": sp, "pos": pos, "seed": tree_seed()})

    def rock(fam, pos, scale=1.0, variant=None, sub=None):
        r = {"family": fam, "pos": pos, "seed": rock_seed(), "scale": scale}
        if variant:
            r["variant"] = variant
        if sub:
            r["sub"] = sub
        d["rocks"].append(r)

    def prop(i, pos, yaw=0):
        d["props"].append({"id": i, "pos": pos, "yaw": yaw})

    # Épaules de raccord plus larges (2 x l'ordinaire) sur les tracés retouchés : moins de cassures de relief
    for pid, sk in (("lacets_des_hauteurs", 20), ("chemin_de_crete", 24), ("pointe_du_guet", 20)):
        path_by_id(d, pid)["skirt"] = sk

    # ---------------------------------------------------------------- POINTE DU GUET
    # Belvédère : le chemin y mène, l'arche encadre le vide, le banc et le porte-bannière marquent le point de vue ;
    # au départ, panneau et lampe disent « retour : chemin principal ».
    g = path_by_id(d, "pointe_du_guet")["pts"]               # (110, -8.75) -> (118.75, -5)
    drop_props(d, lambda p: p["id"] == "decorative_bench" and near(p, 115.0, -1.25, 1.0))
    prop("signpost", [110.2, -13.4], 3)                       # fourche : retour vers le chemin principal
    prop("crystal_lamp", along(g, 2.5, -1.9), 0)
    prop("crystal_lamp", along(g, 7.0, 1.9), 0)
    prop("decorative_bench", [121.0, -1.6], 1)                # face au vide, à côté de l'arche
    prop("banner_stand", [121.4, -9.4], 0)
    rock("boulder", [127.0, 2.5], 1.1)                       # parapet de blocs côté vide

    # ---------------------------------------------------------------- CRÊTE : passages resserrés / ouverts
    cr = path_by_id(d, "chemin_de_crete")["pts"]
    # resserré 1 : deux blocs à 2,4 m de l'axe, pins derrière
    rock("boulder", along(cr, 15, 2.8), 1.3, "mass")
    rock("boulder", along(cr, 16, -2.8), 1.1, "spike")
    tree("pine", along(cr, 14, 8.0))
    tree("pine", along(cr, 18, -6.8))
    # ouvert : belvédère de crête, un banc côté vide et rien d'autre sur 14 m
    prop("decorative_bench", along(cr, 31, -3.4), 1)
    # resserré 2 (tronçon droit s = 57–69) : porte de ruines (deux colonnes) et pins serrés
    rock("ruin", along(cr, 62, 3.4), 1.0, None, "column")
    rock("ruin", along(cr, 62, -3.4), 1.0, None, "column")
    tree("pine", along(cr, 60, 5.8))
    tree("pine", along(cr, 65, -5.8))
    # ouvert : dernier belvédère avant la montée (vue sur le sanctuaire)
    prop("crystal_lamp", along(cr, 74, 2.0), 0)
    prop("crystal_lamp", along(cr, 74, -2.0), 0)

    # ---------------------------------------------------------------- SANCTUAIRE
    # Pied de la montée (45, -72.5) : braseros de part et d'autre des gradins, bornes déjà présentes à 3,7 m.
    prop("brazier", [41.6, -70.5], 0)
    prop("brazier", [41.6, -75.4], 0)
    # En haut des gradins : arche d'entrée alignée sur le cristal (axe de la montée), entre les deux braseros existants.
    prop("ruin_arch", [26.0, -76.6], 1)
    # Ruines intégrées à la composition : colonnes qui bordent les gradins, mur écroulé derrière le brasero nord
    prop("ruin_column", [33.0, -72.0], 0)
    prop("ruin_column", [33.0, -80.2], 0)
    rock("ruin", [22.0, -90.0], 1.0, None, "wall")


if __name__ == "__main__":
    only = None
    if "--etape" in sys.argv:
        only = int(sys.argv[sys.argv.index("--etape") + 1])
    data = json.load(open(SRC, encoding="utf-8"))
    data["_doc"] = data["_doc"] + " Lot 10 : retouchée à la main par tools/lot10_remodelage.py (voir docs/REMODELAGE_LOT10.md)."
    if only in (None, 1, 2):
        etape1(data)
    if only in (None, 2):
        etape2(data)
    with open(DST, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("écrit", DST)
