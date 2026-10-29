#!/usr/bin/env python3
"""Prüft die Spieldaten ohne Godot.

1. Alle JSON-Dateien lesbar, alle Verweise gültig (Räume, Eingänge, Gegenstände,
   Dialoge, Medaillen, Befehle, Hotspots im Bild).
2. Spielt tests/walkthrough.json mit derselben Logik wie game.gd durch.

Aufruf (im Spielordner): python3 addons/game_engine/tools/check_game.py [--root=<spielordner>]
"""
import json
import sys
from pathlib import Path

# Spielordner: --root=<pfad>, sonst das aktuelle Verzeichnis.
ROOT = Path(next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--root=")), ".")).resolve()
COMMANDS = {"say", "set", "clear", "give", "remove", "confiscate", "if", "case", "goto", "walk",
            "medal", "dialog", "title", "wait"}
VERBS = {"give", "open", "close", "take", "talk", "use", "push", "pull", "look", "walk"}

def load(rel):
    with open(ROOT / rel, encoding="utf-8") as f:
        return json.load(f)


errors = []
meta = load("data/game.json")
items = load("data/items.json")
dialogs = load("data/dialogs.json")
rooms = {rid: load(f"data/rooms/{rid}.json") for rid in meta["rooms"]}
speakers = set(meta["characters"])
if meta.get("player", {}).get("id") not in speakers:
    errors.append("game.json: player.id fehlt oder ist kein Eintrag in characters")
if meta.get("companion") and meta["companion"].get("id") not in speakers:
    errors.append("game.json: companion.id ist kein Eintrag in characters")


# --- Statische Prüfung ------------------------------------------------------

def check_cond(cond, where):
    if cond is None:
        return
    if isinstance(cond, list):
        for c in cond:
            check_cond(c, where)
        return
    s = cond.lstrip("!")
    if s.startswith("has:") and s[4:] not in items:
        errors.append(f"{where}: unbekannter Gegenstand in Bedingung {cond}")
    if s.startswith("medal:") and s[6:] not in meta["medals"]:
        errors.append(f"{where}: unbekannte Medaille in Bedingung {cond}")


def check_actions(actions, where):
    if not isinstance(actions, list):
        errors.append(f"{where}: Aktionen müssen eine Liste sein")
        return
    for a in actions:
        cmd = a[0]
        if cmd not in COMMANDS:
            errors.append(f"{where}: unbekannter Befehl {cmd}")
        elif cmd == "say" and a[1] not in speakers:
            errors.append(f"{where}: unbekannter Sprecher {a[1]}")
        elif cmd == "confiscate" and any(i not in items for i in a[1]):
            errors.append(f"{where}: unbekannter Gegenstand in confiscate {a[1]}")
        elif cmd in ("give", "remove") and a[1] not in items:
            errors.append(f"{where}: unbekannter Gegenstand {a[1]}")
        elif cmd == "medal" and a[1] not in meta["medals"]:
            errors.append(f"{where}: unbekannte Medaille {a[1]}")
        elif cmd == "dialog" and a[1] not in dialogs:
            errors.append(f"{where}: unbekannter Dialog {a[1]}")
        elif cmd == "goto" and (a[1] not in rooms or (len(a) > 2 and a[2] not in rooms[a[1]]["entries"])):
            errors.append(f"{where}: ungültiges Ziel {a[1:]}")
        elif cmd == "if":
            check_cond(a[1], where)
            check_actions(a[2], where)
            if len(a) > 3:
                check_actions(a[3], where)
        elif cmd == "case":
            for cond, branch in a[1]:
                check_cond(cond, where)
                check_actions(branch, where)


def check_verbs(verbs, where):
    for key, actions in verbs.items():
        verb, _, other = key.partition(":")
        if verb not in VERBS:
            errors.append(f"{where}: unbekanntes Verb {key}")
        if other and other not in items:
            errors.append(f"{where}: {key} verweist auf unbekannten Gegenstand")
        if isinstance(actions, str):
            if actions not in verbs:
                errors.append(f"{where}: Verweis {key} -> {actions} ins Leere")
        else:
            check_actions(actions, f"{where}.{key}")


check_actions(meta.get("intro", []), "intro")
if meta["start_room"] not in rooms:
    errors.append("Startraum fehlt")
for iid, item in items.items():
    check_verbs(item.get("verbs", {}), f"item {iid}")
for did, dlg in dialogs.items():
    for nid, node in dlg.items():
        check_actions(node.get("do", []), f"dialog {did}.{nid}")
        for o in node.get("options", []):
            check_cond(o.get("if"), f"dialog {did}")
            check_actions(o.get("do", []), f"dialog {did}.{nid}")
            if o.get("next", "end") != "end" and o["next"] not in dlg:
                errors.append(f"dialog {did}: Knoten {o['next']} fehlt")
for rid, room in rooms.items():
    if room["id"] != rid:
        errors.append(f"Raum {rid}: id passt nicht zum Dateinamen")
    x1, y1, x2, y2 = room["walk"]
    for e, (x, y) in room["entries"].items():
        if not (x1 <= x <= x2 and y1 <= y <= y2):
            errors.append(f"Raum {rid}: Eingang {e} liegt außerhalb der Lauffläche")
    check_actions(room.get("on_enter", []), f"{rid}.on_enter")
    for h in room["hotspots"]:
        where = f"{rid}.{h['id']}"
        x, y, w, hh = h["rect"]
        if x < 0 or y < 0 or x + w > 320 or y + hh > 144:
            errors.append(f"{where}: Rechteck ragt aus dem Raum (320x144)")
        check_cond(h.get("if"), where)
        check_cond(h.get("exit_if"), where)
        if h.get("speaker") and h["speaker"] not in speakers:
            errors.append(f"{where}: unbekannter Sprecher {h['speaker']}")
        check_verbs(h.get("verbs", {}), where)
        check_actions(h.get("exit_blocked", []), where)
        check_actions(h.get("exit_do", []), where)
        if "exit" in h:
            target = rooms.get(h["exit"])
            if target is None:
                errors.append(f"{where}: Ausgang in unbekannten Raum {h['exit']}")
            elif h.get("entry") and h["entry"] not in target["entries"]:
                errors.append(f"{where}: Eingang {h['entry']} fehlt in {h['exit']}")


# --- Simulation (gleiche Regeln wie game.gd) -------------------------

class Sim:
    def __init__(self):
        self.flags, self.inventory, self.medals = {}, [], []
        self.room = meta["start_room"]
        self.choices = []

    def check(self, cond):
        if cond is None:
            return True
        if isinstance(cond, list):
            return all(self.check(c) for c in cond)
        neg = cond.startswith("!")
        s = cond[1:] if neg else cond
        if s.startswith("has:"):
            r = s[4:] in self.inventory
        elif s.startswith("medal:"):
            r = s[6:] in self.medals
        else:
            r = bool(self.flags.get(s, False))
        return r != neg

    def enter(self, rid):
        self.room = rid
        self.run(rooms[rid].get("on_enter", []))

    def hotspot(self, hid):
        for h in rooms[self.room]["hotspots"]:
            if h["id"] == hid and self.check(h.get("if")):
                return h
        return None

    def obj(self, oid):
        if oid in self.inventory:
            return items[oid]
        return self.hotspot(oid)

    def verb_actions(self, d, key):
        verbs = d.get("verbs", {})
        a = verbs.get(key)
        if isinstance(a, str):
            a = verbs.get(a)
        return a

    def run(self, actions):
        for a in actions:
            cmd = a[0]
            if cmd == "set":
                self.flags[a[1]] = True
            elif cmd == "clear":
                self.flags.pop(a[1], None)
            elif cmd == "give" and a[1] not in self.inventory:
                self.inventory.append(a[1])
            elif cmd == "remove" and a[1] in self.inventory:
                self.inventory.remove(a[1])
            elif cmd == "confiscate":
                self.inventory = [i for i in self.inventory if i in a[1]]
            elif cmd == "if":
                if self.check(a[1]):
                    self.run(a[2])
                elif len(a) > 3:
                    self.run(a[3])
            elif cmd == "case":
                for cond, branch in a[1]:
                    if self.check(cond):
                        self.run(branch)
                        break
            elif cmd == "goto":
                self.enter(a[1])
            elif cmd == "medal" and a[1] not in self.medals:
                self.medals.append(a[1])
            elif cmd == "dialog":
                self.dialog(a[1])

    def dialog(self, did):
        dlg, nid = dialogs[did], "start"
        while nid in dlg:
            node = dlg[nid]
            self.run(node.get("do", []))
            shown = [o for i, o in enumerate(node.get("options", []))
                     if self.check(o.get("if")) and not (o.get("once") and self.flags.get(f"dlg:{did}:{nid}:{i}"))]
            if not shown:
                return
            # Wie im Testmodus der Engine: vorgegebene Wahl, sonst die letzte Option (Abschied).
            pick = self.choices.pop(0) if self.choices else len(shown) - 1
            o = shown[min(max(pick, 0), len(shown) - 1)]
            if o.get("once"):
                self.flags[f"dlg:{did}:{nid}:{node['options'].index(o)}"] = True
            self.run(o.get("do", []))
            nid = o.get("next", "end")

    def sentence(self, verb, o1, o2=""):
        d1 = self.obj(o1)
        d2 = self.obj(o2) if o2 else {}
        if d1 is None or d2 is None:
            return f"'{o2 if d1 else o1}' ist in Raum {self.room} nicht da"
        if verb == "walk":
            if "exit" not in d1:
                a = self.verb_actions(d1, "walk")
                if a is None:
                    return f"{o1} ist kein Ausgang"
                self.run(a)
                return None
            if not self.check(d1.get("exit_if")):
                return f"Ausgang {o1} ist noch versperrt"
            self.run(d1.get("exit_do", []))
            self.enter(d1["exit"])
            return None
        a = None
        if o2:
            a = self.verb_actions(d2, f"{verb}:{o1}") or self.verb_actions(d1, f"{verb}:{o2}")
        else:
            a = self.verb_actions(d1, verb)
        if a is None:
            return "keine Reaktion (Standardantwort)"
        self.run(a)
        return None


wt = load("tests/walkthrough.json")
sim = Sim()
sim.enter(meta["start_room"])
for n, step in enumerate(wt["steps"], 1):
    if step[0] == "choose":
        sim.choices = list(step[1:])
        continue
    problem = sim.sentence(*step)
    if problem:
        errors.append(f"Komplettlösung Schritt {n} {step}: {problem}")
        break
else:
    for f in wt.get("expect_flags", []):
        if not sim.flags.get(f):
            errors.append(f"Komplettlösung: Flag {f} fehlt am Ende")
    for m in wt.get("expect_medals", []):
        if m not in sim.medals:
            errors.append(f"Komplettlösung: Medaille {m} fehlt am Ende")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"OK: {len(rooms)} Räume, {len(items)} Gegenstände, Komplettlösung mit {len(wt['steps'])} Schritten, "
      f"Medaillen {len(sim.medals)}/{len(meta['medals'])}")
