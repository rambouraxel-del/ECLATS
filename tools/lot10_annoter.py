#!/usr/bin/env python3
"""Lot 10 — étiquette la vue aérienne (capture 7) : projette les repères du monde dans l'image avec la caméra du cadrage.
    python3 tools/lot10_annoter.py aerienne.png sortie.jpg   (cadrage « aerienne » de docs/captures/lot10/cadrages.json)"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cad = next(c for c in json.load(open(os.path.join(ROOT, "docs/captures/lot10/cadrages.json"))) if c["nom"] == "aerienne")
# (étiquette, repère monde, côté de l'étiquette)
REPERES = [("1  Quai", (-67.5, 3.5, 112.0), 1), ("2  Hameau", (-10.0, 10.0, 0.0), 1),
           ("3  Guet et crête", (112.0, 25.0, -12.0), 1), ("4  Sanctuaire", (17.5, 32.0, -77.5), -1)]


def norm(v):
    l = math.sqrt(sum(a * a for a in v))
    return [a / l for a in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def project(p, size):
    pos = [cad["pos"][0], cad["h"], cad["pos"][1]]
    f = norm([cad["look"][0] - pos[0], cad.get("ly", 10.0) - pos[1], cad["look"][1] - pos[2]])
    r = norm(cross(f, [0, 1, 0]))
    u = cross(r, f)
    v = [p[i] - pos[i] for i in range(3)]
    z = dot(v, f)
    t = math.tan(math.radians(cad["fov"]) / 2)
    nx = dot(v, r) / (z * t * size[0] / size[1])
    ny = dot(v, u) / (z * t)
    return (nx + 1) / 2 * size[0], (1 - ny) / 2 * size[1]


def main(src, dst):
    im = Image.open(src).convert("RGB")
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30)
    except OSError:
        font = ImageFont.load_default()
    for nom, p, side in REPERES:
        x, y = project(p, im.size)
        d.ellipse((x - 9, y - 9, x + 9, y + 9), outline=(255, 255, 255), width=4)
        d.ellipse((x - 9, y - 9, x + 9, y + 9), outline=(20, 20, 20), width=1)
        tw = d.textlength(nom, font=font)
        tx = x + 16 if side > 0 else x - 16 - tw
        tx = min(max(tx, 14), im.size[0] - tw - 14)
        ty = min(max(y - 40, 8), im.size[1] - 48)
        d.rectangle((tx - 8, ty - 4, tx + tw + 8, ty + 40), fill=(20, 24, 32))
        d.text((tx, ty), nom, fill=(255, 255, 255), font=font)
    im.save(dst, quality=88)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
