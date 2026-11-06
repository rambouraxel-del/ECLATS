#!/usr/bin/env python3
"""Planches A / B / C du comparatif de terrain (lisibles sur téléphone) à partir des originaux.
   python3 tools/comparatif_planches.py DOSSIER_PNG [GRAINE1 GRAINE2]
   Sortie : docs/captures/comparatif-terrain/*.jpg (originaux) et planches/*.jpg (une planche par point de vue)."""
import sys, os, glob
from PIL import Image, ImageDraw, ImageFont

SRC = sys.argv[1]
S1 = int(sys.argv[2]) if len(sys.argv) > 2 else 21
S2 = int(sys.argv[3]) if len(sys.argv) > 3 else 7
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "captures", "comparatif-terrain")
os.makedirs(os.path.join(OUT, "planches"), exist_ok=True)
LABEL = {"A": "A · générateur actuel (Lot 11)", "B": "B · relief enrichi FastNoiseLite", "C": "C · prototype Voxel Tools"}
COL = {"A": (46, 102, 160), "B": (176, 110, 28), "C": (46, 128, 78)}
FONT = None
for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
    if os.path.exists(f):
        FONT = f
def font(sz):
    return ImageFont.truetype(FONT, sz) if FONT else ImageFont.load_default()

def orig(nom, m, s):
    p = os.path.join(SRC, "%s_%s_graine%d.png" % (nom, m, s))
    return Image.open(p).convert("RGB") if os.path.exists(p) else None

def save_original(nom, m, s):
    im = orig(nom, m, s)
    if im is not None:
        im.save(os.path.join(OUT, "%s_%s_graine%d.jpg" % (nom, m, s)), quality=90)

def band(w, text, m, h=64, sub=""):
    b = Image.new("RGB", (w, h), COL[m])
    d = ImageDraw.Draw(b)
    d.text((18, 8), text, font=font(30), fill=(255, 255, 255))
    if sub:
        d.text((18, 40), sub, font=font(18), fill=(235, 240, 245))
    return b

def planche(title, nom_list, s, fname, subtitle):
    """nom_list : 1 nom (planche simple) ou 2 noms (avant / après côte à côte)."""
    W = 1080 if len(nom_list) == 1 else 1240
    cw = W if len(nom_list) == 1 else W // 2 - 4
    ch = int(cw * 9 / 16)
    blocks = []
    for m in "ABC":
        strip = Image.new("RGB", (W, ch), (20, 20, 20))
        for i, nom in enumerate(nom_list):
            im = orig(nom, m, s)
            if im is None:
                im = Image.new("RGB", (1280, 720), (60, 60, 60))
                ImageDraw.Draw(im).text((40, 330), "%s : non disponible" % LABEL[m], font=font(48), fill=(255, 255, 255))
            strip.paste(im.resize((cw, ch), Image.LANCZOS), (i * (cw + 8), 0))
        sub = "graine %d · %s" % (s, subtitle)
        if len(nom_list) == 2:
            sub += "  ·  gauche : avant le trait  ·  droite : après"
        blk = Image.new("RGB", (W, 64 + ch + 6), (20, 20, 20))
        blk.paste(band(W, LABEL[m], m, sub=sub), (0, 0))
        blk.paste(strip, (0, 64))
        blocks.append(blk)
    head = Image.new("RGB", (W, 70), (24, 30, 40))
    ImageDraw.Draw(head).text((18, 16), title, font=font(28 if len(title) > 50 else 32), fill=(255, 255, 255))
    total = Image.new("RGB", (W, 70 + sum(b.height for b in blocks)), (20, 20, 20))
    total.paste(head, (0, 0))
    y = 70
    for b in blocks:
        total.paste(b, (0, y))
        y += b.height
    total.save(os.path.join(OUT, "planches", fname), quality=90)
    print("planche", fname, total.size)

POINTS = [
    ("01_vue_aerienne_generale", "1 · Vue aérienne générale"),
    ("02_cretes_et_vallees_aerien", "2 · Crêtes et vallées (aérien rapproché)"),
    ("03_arrivee_premiere_personne", "3 · Arrivée (première personne)"),
    ("04_chemin_vers_le_plateau", "4 · Chemin vers le plateau (première personne)"),
    ("05_pente_ou_falaise", "5 · Pente / falaise (première personne)"),
]
size = os.environ.get("CMP_TAILLE", "56 × 48 m")
for nom, titre in POINTS:
    for m in "ABC":
        save_original(nom, m, S1)
    planche(titre, [nom], S1, "planche_%s.jpg" % nom, size)
for m in "ABC":
    save_original("06a_zone_avant_pinceau", m, S1)
    save_original("06b_zone_apres_pinceau", m, S1)
    save_original("01_vue_aerienne_generale", m, S2)
planche("6 · Même zone avant / après un trait de pinceau",
        ["06a_zone_avant_pinceau", "06b_zone_apres_pinceau"], S1, "planche_06_avant_apres_pinceau.jpg", size)
planche("7 · Deuxième graine, vue aérienne générale", ["01_vue_aerienne_generale"], S2,
        "planche_07_graine%d_vue_aerienne.jpg" % S2, size)
