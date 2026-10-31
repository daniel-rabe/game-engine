#!/usr/bin/env python3
"""Baut die Bilder einer Schiebetür (<hotspot>_door_0.png … _door_N.png) aus zwei Gemälden:
dem Raumhintergrund mit geschlossener Tür und demselben Raum mit offener Tür (z. B. ein FLUX-Edit,
nur im Türbereich zurückgeklebt). Es wird nichts gemalt: Die Öffnung ist die Fläche, in der sich die
beiden Bilder unterscheiden, und das gemalte Türblatt aus dem geschlossenen Bild gleitet darin zur Seite,
bis dahinter das offene Bild frei ist.

Aufruf (im Spielordner):
  python3 addons/game_engine/tools/door_frames.py <raum> <hotspot> <offen.png> [--dir=left|right]
      [--slope=0.0] [--frames=8] [--threshold=40] [--fill=1] [--preview=vorschau.gif]

--dir: Richtung, in die das Türblatt gleitet (Standard left). --slope: senkrechte Verschiebung je
waagerechtem Pixel, für Türen an einer schrägen Seitenwand (Kante oben folgt der Perspektive).
--fill=0: Lücken in der Öffnung nicht zeilenweise füllen, z. B. wenn Schläuche oder Rohre vor dem
Türblatt hängen und stehen bleiben sollen; das Türblatt gleitet dann hinter ihnen.
Die Bilder haben die Größe des Hotspot-Rechtecks im Maßstab des Hintergrunds (bei 1280 × 576 also 4-fach).
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
if len(args) != 3:
    sys.exit(__doc__)
room_id, hid, open_path = args
root = Path(opts.get("root", ".")).resolve()
direction = opts.get("dir", "left")
slope = float(opts.get("slope", 0.0))
count = int(opts.get("frames", 8))
threshold = float(opts.get("threshold", 40))

room = json.loads((root / f"data/rooms/{room_id}.json").read_text(encoding="utf-8"))
h = next(x for x in room["hotspots"] if x["id"] == hid)
closed_img = Image.open(root / f"art/rooms/{room_id}.png").convert("RGB")
open_img = Image.open(open_path).convert("RGB")
assert closed_img.size == open_img.size, "beide Bilder müssen gleich groß sein"
scale = closed_img.width / 320
x, y, w, hh = [round(v * scale) for v in h["rect"]]
box = (x, y, x + w, y + hh)
closed = np.asarray(closed_img.crop(box)).astype(np.float32)
opened = np.asarray(open_img.crop(box)).astype(np.float32)

# Öffnung: wo sich die Bilder deutlich unterscheiden; Löcher schließen, Krümel entfernen
diff = np.abs(closed - opened).sum(axis=2)
mask = Image.fromarray(((diff > threshold) * 255).astype(np.uint8))
mask = mask.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))  # schließen
mask = mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))  # öffnen
m = np.asarray(mask) > 127
# je Zeile von der ersten bis zur letzten Öffnungsspalte füllen (die Öffnung ist zusammenhängend)
for r in range(m.shape[0]) if opts.get("fill", "1") != "0" else []:
    cols = np.flatnonzero(m[r])
    if cols.size:
        m[r, cols[0]:cols[-1] + 1] = True
if not m.any():
    sys.exit("Keine Öffnung gefunden: Bilder gleich? --threshold kleiner wählen.")
ys, xs = np.nonzero(m)
width = xs.max() - xs.min() + 1
sign = -1 if direction == "left" else 1
alpha = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)))

out_dir = root / f"art/objects/{room_id}"
out_dir.mkdir(parents=True, exist_ok=True)
gif = []
H, W = m.shape
yy, xx = np.mgrid[0:H, 0:W]
for k in range(count):
    t = k / (count - 1)
    t = t * t * (3 - 2 * t)  # sanft anfahren und abbremsen
    dx = sign * t * width
    dy = slope * dx
    # Ziel p zeigt das Türblatt von p - (dx, dy), solange beides in der Öffnung liegt
    sx = np.rint(xx - dx).astype(int)
    sy = np.rint(yy - dy).astype(int)
    inside = (sx >= 0) & (sx < W) & (sy >= 0) & (sy < H)
    src_in = np.zeros_like(m)
    src_in[inside] = m[sy[inside], sx[inside]]
    panel = m & src_in
    frame = opened.copy()
    frame[panel] = closed[sy[panel], sx[panel]]
    rgba = np.dstack([np.clip(frame, 0, 255), alpha]).astype(np.uint8)
    Image.fromarray(rgba).save(out_dir / f"{hid}_door_{k}.png")
    full = closed_img.copy()
    full.paste(Image.fromarray(rgba), box[:2], Image.fromarray(rgba))
    gif.append(full.crop((max(0, x - 80), max(0, y - 40), min(closed_img.width, x + w + 80),
                          min(closed_img.height, y + hh + 40))))
print(f"{count} Bilder in {out_dir} ({hid}_door_0..{count - 1}.png), Öffnung {width} px breit")
if "preview" in opts:
    seq = gif + gif[-1:] * 6 + gif[::-1] + gif[:1] * 6
    seq[0].save(opts["preview"], save_all=True, append_images=seq[1:], duration=60, loop=0)
