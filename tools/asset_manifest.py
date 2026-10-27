#!/usr/bin/env python3
"""Erzeugt art/manifest.json und Layout-Vorlagen für die Grafikerstellung mit ComfyUI.

Das Manifest listet jede Grafik, die das Spiel nutzen kann: Pfad, Größe in Pixeln,
Prompt und ob die Datei schon existiert. Die Layout-Vorlagen (art/layout/<raum>.png)
zeigen die Platzhalter-Anordnung eines Raums und dienen als Eingabe für
img2img/ControlNet, damit Türen und Objekte dort landen, wo die Hotspots sind.

Aufruf (im Spielordner): python3 addons/game_engine/tools/asset_manifest.py              (Manifest + Layouts)
                         python3 addons/game_engine/tools/asset_manifest.py --no-layout
"""
import json
import sys
from pathlib import Path

# Spielordner: --root=<pfad>, sonst das aktuelle Verzeichnis.
ROOT = Path(next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--root=")), ".")).resolve()
ART = ROOT / "art"

ROOM_SIZE = [320, 144]
ICON_SIZE = [44, 18]
DEFAULT_STYLE = ("pixel art, LucasArts adventure game style like Monkey Island 2 (1991), "
                 "hand-painted VGA graphics, 256 colors, soft dithering")
DEFAULT_NEGATIVE = "photo, 3d render, blurry, text, watermark, logo, signature, modern UI, frame, border"


def load(rel):
    with open(ROOT / rel, encoding="utf-8") as f:
        return json.load(f)


def art_settings(meta):
    """Stil, Negativ-Prompt und Figuren stehen in game.json unter "art"."""
    art = meta.get("art", {})
    style = art.get("style", DEFAULT_STYLE).rstrip(", ") + ", "
    return style, art.get("negative", DEFAULT_NEGATIVE), art.get("actors", {})


def entry(path, kind, size, prompt, negative, **extra):
    e = {"path": path, "kind": kind, "size": size, "prompt": prompt, "negative": negative,
         "exists": (ROOT / path).exists()}
    e.update(extra)
    return e


def build():
    meta = load("data/game.json")
    items = load("data/items.json")
    STYLE, NEGATIVE, ACTORS = art_settings(meta)
    assets = []
    rooms = {}
    for rid in meta["rooms"]:
        room = load(f"data/rooms/{rid}.json")
        rooms[rid] = room
        assets.append(entry(f"art/rooms/{rid}.png", "room", ROOM_SIZE,
                            STYLE + room.get("art_prompt", room["name"]) + ", empty room, no people",
                            NEGATIVE, room=rid, layout=f"art/layout/{rid}.png", act=room.get("act")))
        for h in room["hotspots"]:
            if not h.get("sprite"):
                continue
            size = h["rect"][2:]
            prompt = STYLE + h.get("art_prompt", h["name"]) + ", single object, isolated, transparent background"
            assets.append(entry(f"art/objects/{rid}/{h['id']}.png", "object", size, prompt, NEGATIVE,
                                room=rid, position=h["rect"][:2]))
            for cond, suffix in h.get("art_variants", {}).items():
                assets.append(entry(f"art/objects/{rid}/{h['id']}_{suffix}.png", "object_state", size,
                                    prompt + f", state: {suffix}", NEGATIVE, room=rid, position=h["rect"][:2],
                                    condition=cond))
    for iid, item in items.items():
        assets.append(entry(f"art/items/{iid}.png", "item_icon", ICON_SIZE,
                            STYLE + "inventory icon, " + item.get("art_prompt", item["name"])
                            + ", single object, isolated, transparent background", NEGATIVE))
    for aid, actor in ACTORS.items():
        prompt = STYLE + "character sprite, " + actor["prompt"] + ", transparent background"
        assets.append(entry(f"art/actors/{aid}/stand.png", "actor", actor["size"], prompt + ", standing", NEGATIVE))
        for i in range(actor["walk_frames"]):
            assets.append(entry(f"art/actors/{aid}/walk_{i}.png", "actor", actor["size"],
                                prompt + f", walk cycle frame {i + 1} of {actor['walk_frames']}", NEGATIVE))
    return rooms, assets, STYLE, NEGATIVE


def draw_layouts(rooms):
    from PIL import Image, ImageDraw
    out = ART / "layout"
    out.mkdir(parents=True, exist_ok=True)
    for rid, room in rooms.items():
        bg = room.get("bg", {})
        floor_y = bg.get("floor_y", 100)
        img = Image.new("RGB", tuple(ROOM_SIZE), bg.get("wall", "#2a3040"))
        d = ImageDraw.Draw(img)
        d.rectangle([0, floor_y, ROOM_SIZE[0], ROOM_SIZE[1]], fill=bg.get("floor", "#1a1e28"))
        for deco in room.get("decor", []):
            x, y, w, h = deco["rect"]
            d.rectangle([x, y, x + w - 1, y + h - 1], fill=deco.get("color", "#444444"))
        for h in room["hotspots"]:
            if h.get("placeholder") is False:
                continue
            x, y, w, hh = h["rect"]
            d.rectangle([x, y, x + w - 1, y + hh - 1], fill=h.get("color", "#6a7a8a"))
        img.save(out / f"{rid}.png")


def main():
    rooms, assets, style, negative = build()
    manifest = {
        "style": style.strip(", "),
        "negative": negative,
        "note": "Generiert von addons/game_engine/tools/asset_manifest.py. Nicht von Hand bearbeiten; Prompts stehen in data/.",
        "assets": assets,
    }
    ART.mkdir(exist_ok=True)
    with open(ART / "manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    if "--no-layout" not in sys.argv:
        draw_layouts(rooms)
    done = sum(a["exists"] for a in assets)
    print(f"art/manifest.json: {len(assets)} Grafiken, davon {done} vorhanden")


if __name__ == "__main__":
    main()
