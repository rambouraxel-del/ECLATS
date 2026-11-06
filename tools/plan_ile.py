#!/usr/bin/env python3
"""Plan annoté d'une île dessinée (Lot 5) : relief exporté par tools/island_relief.gd + tracés de la carte JSON.
  python3 tools/plan_ile.py config/islands/ile_ouverture.json relief.png plan.png
Le relief (PNG + JSON de métadonnées) vient de :
  godot --headless -s tools/island_relief.gd -- res://config/islands/ile_ouverture.json relief.png --complet
"""
import json, math, sys
from PIL import Image, ImageDraw, ImageFont

mp = json.load(open(sys.argv[1]))
relief = Image.open(sys.argv[2]).convert("RGB")
meta = json.load(open(sys.argv[2].replace(".png", ".json")))
out = sys.argv[3]
n = meta["n"]; ox, oz = meta["origin"]; cell = meta["cell_m"]
SCALE = 1600 / n
img = relief.resize((1600, 1600), Image.LANCZOS)
d = ImageDraw.Draw(img, "RGBA")
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
except Exception:
    font = small = ImageFont.load_default()

def px(p):
    return ((p[0] / cell - ox) * SCALE, (p[1] / cell - oz) * SCALE)

# chemins
for p in mp["paths"]:
    pts = [px(q) for q in p["pts"]]
    col = (190, 60, 40, 235) if p.get("kind") == "main" else (240, 200, 40, 235)
    d.line(pts, fill=col, width=7 if p.get("kind") == "main" else 5, joint="curve")
# bâtiments
for b in mp["buildings"]:
    x, y = px(b["pos"])
    r = 4.5 / cell * SCALE
    d.rectangle([x - r, y - r * 0.8, x + r, y + r * 0.8], fill=(120, 70, 50, 230) if not b.get("visitable") else (210, 120, 40, 255), outline=(30, 20, 10, 255), width=2)
# arbres, rochers, objets
for t in mp["trees"]:
    x, y = px(t["pos"])
    d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(30, 90, 35, 220))
for r in mp["rocks"]:
    x, y = px(r["pos"])
    s = 4 + 3 * r.get("scale", 1.0)
    col = (225, 225, 210, 240) if r["family"] == "ruin" else (110, 110, 115, 240)
    d.rectangle([x - s, y - s, x + s, y + s], fill=col, outline=(40, 40, 40, 255))
for p in mp["props"]:
    x, y = px(p["pos"])
    d.ellipse([x - 2.5, y - 2.5, x + 2.5, y + 2.5], fill=(250, 250, 250, 230))
# zones
for z in mp["zones"]:
    x, y = px(z["center"])
    text = z["name"]
    w = d.textlength(text, font=font)
    d.rectangle([x - w / 2 - 6, y - 40, x + w / 2 + 6, y - 12], fill=(255, 255, 255, 200))
    d.text((x - w / 2, y - 38), text, font=font, fill=(20, 20, 30, 255))
# quai (appontement), départ, ancre (dessinés par-dessus les noms)
pm = mp.get("pier")
if pm:
    lx, lz = pm["landing"]; ax, az = pm["axis"]
    a0 = px((lx + ax * 8, lz + az * 8)); a1 = px((lx + ax * 19, lz + az * 19))
    d.line([a0, a1], fill=(120, 80, 45, 255), width=12)
x, y = px(mp["spawn"]["pos"])
d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=(40, 140, 255, 255), outline=(255, 255, 255, 255), width=3)
x, y = px(mp["anchor"]["pos"])
d.ellipse([x - 12, y - 12, x + 12, y + 12], fill=(90, 230, 255, 255), outline=(255, 255, 255, 255), width=3)
# légende
lg = [((190, 60, 40), "itinéraire principal"), ((240, 200, 40), "détour"), ((210, 120, 40), "maison visitable"),
      ((120, 70, 50), "bâtiments"), ((30, 90, 35), "arbres"), ((110, 110, 115), "rochers"), ((225, 225, 210), "ruines"),
      ((40, 140, 255), "départ (quai)"), ((90, 230, 255), "Ancre")]
y0 = 1600 - 26 * len(lg) - 20
d.rectangle([14, y0 - 10, 260, 1590], fill=(255, 255, 255, 210))
for i, (c, t) in enumerate(lg):
    d.rectangle([24, y0 + i * 26, 44, y0 + i * 26 + 18], fill=c + (255,))
    d.text((52, y0 + i * 26), t, font=small, fill=(20, 20, 30, 255))
d.text((20, 16), "%s — plan (%.0f × %.0f m)" % (mp["name"], n * cell, n * cell), font=font, fill=(20, 20, 30, 255))
img.save(out)
print("écrit", out)
