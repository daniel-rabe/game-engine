# Datenformat

Ein Spiel besteht nur aus JSON-Dateien. Die Engine liest sie beim Start aus `res://data/`.

| Datei | Inhalt |
| --- | --- |
| `data/game.json` | Titel, Startraum, Spielfigur, Figuren, Sammelobjekte, Intro, Stil der Grafiken |
| `data/items.json` | Gegenstände: `{"id": {...}}` |
| `data/dialogs.json` | Dialogbäume: `{"id": {"knoten": {...}}}` |
| `data/rooms/<raum>.json` | Ein Raum pro Datei, Reihenfolge in `game.json` → `rooms` |
| `tests/walkthrough.json` | Komplettlösung für die Durchspieltests |

## game.json

```json
{
  "title": "Sternenschrott",
  "start_room": "kabine",
  "start_entry": "start",
  "player": {"id": "ria", "placeholder": {"body": "#c0392b"}},
  "companion": {"id": "bolt", "if": "bolt_on"},
  "rooms": ["kabine", "schacht"],
  "characters": {"ria": {"name": "Ria", "color": "#ffd27f"}, "text": {"name": "", "color": "#ffffff"}},
  "medal_label": {"one": "Schraubenmedaille", "many": "Schraubenmedaillen"},
  "medals": {"wasserhahn": "Tropfenden Wasserhahn repariert"},
  "texts": {"look": "Nichts Besonderes."},
  "intro": [["title", "STERNENSCHROTT"]],
  "art": {"style": "pixel art, ...", "negative": "photo, ...", "actors": {"ria": {"size": [32, 48], "walk_frames": 6, "prompt": "..."}}}
}
```

- `player.id`: Sprecher-Id der Spielfigur. Sie spricht Standardantworten und die Sätze aus Dialogoptionen.
  `player.placeholder` ändert die Farben der Platzhalterfigur (`legs`, `shoes`, `body`, `shirt`, `skin`, `hair`, `accent`, `mouth`).
- `companion` (optional): Begleiter, der der Spielfigur folgt, solange die Bedingung `if` gilt.
  Platzhalterfarben unter `companion.placeholder` (`body`, `light`, `eye_bg`, `eye`).
- `characters`: alle Sprecher mit Anzeigename und Textfarbe. `text` ist der Erzähler.
- `medals` und `medal_label`: optionale Sammelobjekte (Medaillen, Anstecker …) mit Namen für Anzeige und Meldung.
- `texts`: ersetzt Standardsätze der Engine. Schlüssel: die Verben (`give`, `open`, `close`, `take`, `talk`,
  `use`, `push`, `pull`, `look`), `other`, `already_have`, `exit_blocked`, `saved`, `save_failed`, `loaded`, `load_failed`, `music_on`, `music_off`
  und die Texte des Spielmenüs (Esc): `menu_title`, `menu_resume`, `menu_save`, `menu_load`, `menu_quit`, `menu_back`,
  `menu_quit_confirm`, `menu_yes`, `menu_no`, `menu_overwrite`, `slot_empty`, `slot_quick`.
- `menu` (optional): Bild hinter dem Spielmenü, z. B. `{"panel": "res://art/ui/menu_panel.png", "panel_margin": 116}`.
  Das Bild wird auf die Menübreite verkleinert; der Rand (`panel_margin` Bildpunkte) bleibt, nur die Mitte streckt sich.
  `fonts.menu` ersetzt die Menüschrift.
- `music` (optional): Hintergrundmusik, z. B. `{"default": "titel", "acts": {"1": "schiff"}, "volume_db": -8,
  "fade": 2.5, "track_db": {"schiff": -1}, "dir": "res://music"}`. Jeder Raum spielt sein Feld `"music"`,
  sonst das Stück seines Akts (`acts`, Schlüssel ist das Raumfeld `act`), sonst `default`. Stücke sind
  `<dir>/<stück>.ogg` und laufen als Schleife; beim Raumwechsel blendet die Engine in `fade` Sekunden über,
  ein schon laufendes Stück spielt weiter. Fehlt die Datei, blendet die Musik aus. `track_db` gleicht
  einzelne Stücke an. Taste M schaltet stumm (Bus „Music“).
- `voice` (optional): Sprachausgabe für `say`, z. B. `{"speakers": ["text"], "dir": "res://voice",
  "volume_db": 0, "duck_db": -8, "duck_fade": 0.4}`. Für jede Zeile eines Sprechers aus `speakers` spielt
  die Engine `<dir>/<sprecher>/<schlüssel>.ogg` (Schlüssel: die ersten 12 Zeichen des MD5 des Texts), lässt
  den Text so lange stehen, wie die Aufnahme dauert, und senkt die Musik um `duck_db`. Überspringen stoppt
  den Ton. Fehlt die Datei (etwa nach einer Textänderung), bleibt die Zeile stumm (Bus „Voice“).
- `intro`: Befehle beim Spielstart.
- `title_screen` (optional): Startbild mit Menü (Neues Spiel, Fortsetzen, Beenden) vor dem Intro:
  `{"image": "res://art/screens/titel.png", "music": "titel", "subtitle": "…", "text_pos": "top", "menu_pos": [220, 290]}`.
  Das Bild füllt den ganzen Bildschirm (640×400, gern doppelt so groß gemalt), `title` steht als echte Schrift darüber.
  Nach „Neues Spiel“ bleibt der Bildschirm schwarz bis zur ersten Tafel, zum ersten Satz oder Gang.
- `art`: Stil, Negativ-Prompt und Figuren für `tools/asset_manifest.py`. Je Figur außerdem `walk_fps`
  (Laufbilder pro Sekunde, Standard 8) und `idle_fps` (für `idle_0.png` …, Standard 8). Sind die Bilder
  höher als `size`, gelten sie als 4-fach gemalt und werden geviertelt und geglättet gezeichnet.
  `actions` beschreibt Aktionsbilder: `{"pickup": {"fps": 15, "grab": 7}}`. `pickup` spielt die Engine
  automatisch bei „Nimm“, wenn das Verb einen Gegenstand gibt; das Skript läuft ab Bild `grab` weiter.
  Sprechbilder: `talk_<mund>_N.png` mit den Mundformen `small`, `open`, `o`, `e` (geschlossen = `idle_N.png`),
  N wie bei den Ruhebildern. Für eine Stimmung `<stimmung>_<mund>_N.png`, z. B. `happy_closed_N.png`,
  `happy_open_N.png`. Die Engine wechselt die Mundform nach den Buchstaben des Satzes; fehlende Formen
  werden durch ähnliche ersetzt. Eine Dialogoption kann ihre Stimmung mit `"mood"` angeben.

## Räume

```json
{
  "id": "kabine",
  "name": "Kabine",
  "act": 1,
  "art_prompt": "cramped cabin of a rusty freighter",
  "bg": {"wall": "#2a3040", "floor": "#1a1e28", "floor_y": 100, "stars": false},
  "walk": [20, 104, 300, 138],
  "entries": {"start": [60, 120], "schacht": [280, 120]},
  "decor": [{"rect": [10, 10, 40, 20], "color": "#444444"}],
  "on_enter": [],
  "hotspots": []
}
```

Ein Raum ist 320 × 144 Pixel groß (auch mit 4-fach gemaltem Hintergrund, der wird nur größer gezeichnet). `walk` ist das Rechteck, in dem die Figur laufen darf
(x1, y1, x2, y2), `entries` sind benannte Startpunkte. Optional `"depth": {"y": [104, 138], "scale": [0.8, 1.05]}`:
die Spielfigur ist an y = 104 (hinten) 0,8-mal und an y = 138 (vorn) 1,05-mal so groß, dazwischen linear;
ihre Laufgeschwindigkeit skaliert mit, damit die Schritte zur Größe passen. `bg` und `decor` gelten nur für den
Platzhalter. `on_enter` läuft bei jedem Betreten.

Optional `"frame": [0, 40, 320, 64]`: nur dieser Ausschnitt des Raums ist zu sehen, der Rest bleibt schwarz
(z. B. ein enger Schacht). Der Hintergrund füllt dann nur den Ausschnitt (4-fach: 1280 × 256), Erzähltext und
Sätze von Figuren ohne Platz im Raum stehen im Schwarz darüber. Optional `"pose": "crawl"`: die Spielfigur nimmt
in diesem Raum statt `walk_N`/`idle_N` die Bilder `crawl_N.png` (Fortbewegung) und `crawl_idle_N.png` (sonst
`crawl_0.png`) im Stand, Bildraten unter `art.actors.<id>.poses.crawl` (`fps`, `idle_fps`, Standard 8).

### Hotspots

| Feld | Bedeutung |
| --- | --- |
| `id`, `name` | Kennung und Anzeigename |
| `rect` | x, y, Breite, Höhe in Raumkoordinaten |
| `baseline` | Fußlinie (y) für die Verdeckung bei gemalten Objektbildern, sonst die Unterkante von `rect`: steht die Figur dahinter (kleineres y), wird das Objekt über ihr gezeichnet |
| `if` | Nur sichtbar, solange die Bedingung gilt |
| `verbs` | `{"look": [...], "use:klebeband": [...], "push": "use"}`: Befehle je Verb, ein String verweist auf ein anderes Verb |
| `default` | Verb für Rechtsklick (sonst `walk` bei Ausgängen, `look` bei allem anderen) |
| `exit`, `entry` | Ausgang in einen Raum und dessen Eingang |
| `exit_if`, `exit_blocked`, `exit_do` | Bedingung für den Ausgang, Befehle wenn gesperrt, Befehle vor dem Raumwechsel |
| `speaker` | Hotspot ist eine Figur; ihr Text erscheint über ihr |
| `walk_to` | Punkt, zu dem die Figur läuft (sonst unter dem Rechteck) |
| `color`, `color_variants` | Platzhalterfarbe, je nach Bedingung |
| `placeholder` | `false`: nichts zeichnen (nur klickbare Fläche) |
| `sprite`, `art_variants`, `art_prompt` | Eigene Grafik und Zustände, siehe `docs/assets.md` des Spiels |

## Gegenstände

```json
{"klebeband": {"name": "Klebeband", "short": "Klebe-band", "default": "look", "art_prompt": "roll of duct tape",
               "verbs": {"look": [["say", "ria", "Hält alles zusammen."]]}}}
```

`short` ist der Text im Inventar, solange es kein Symbol gibt. „Benutze A mit B“ sucht erst
`use:A` bei B, dann `use:B` bei A. Dasselbe gilt für „Gib … an“.

## Dialoge

```json
{"otti": {
  "start": {"do": [["say", "otti", "Na?"]],
            "options": [{"text": "Wie geht's?", "if": "!gefragt", "once": true, "do": [["set", "gefragt"]], "next": "start"},
                        {"text": "Tschüss."}]}
}}
```

Ein Dialog beginnt beim Knoten `start`. Die Spielfigur spricht den Text der gewählten Option,
dann laufen deren Befehle und es geht bei `next` weiter (ohne `next`: Ende). `once` zeigt eine
Option nur einmal. Im Test wird ohne Vorgabe die letzte sichtbare Option gewählt.

## Befehle

| Befehl | Wirkung |
| --- | --- |
| `["say", sprecher, text]` | Sprechtext; optional mit Stimmung: `["say", "ria", "Juhu!", "happy"]` |
| `["set", flag]`, `["clear", flag]` | Flag setzen oder löschen |
| `["give", item]`, `["remove", item]` | Gegenstand ins Inventar oder heraus |
| `["confiscate", [items]]` | Alles abnehmen außer den genannten Gegenständen |
| `["if", bedingung, [dann], [sonst]]` | Verzweigung, `sonst` optional |
| `["case", [[bedingung, [befehle]], ...]]` | Erster passender Zweig |
| `["goto", raum, eingang]` | Raumwechsel |
| `["walk", x, y]` | Figur läuft zu einem Punkt |
| `["music", stück]`, `["music"]` | Anderes Musikstück bis zum nächsten Raumwechsel; ohne Stück zurück zur Raummusik |
| `["anim", "name"]` | Spielfigur spielt die Aktion `art/actors/<figur>/<name>_N.png` (weiter beim Bild `grab`) |
| `["medal", id]` | Sammelobjekt vergeben (einmalig) |
| `["dialog", id]` | Dialog starten |
| `["title", text, bild, ort]` | Texttafel; mit `bild` gemalte Tafel, die aus Schwarz einblendet, Text an `ort` (`left`, `right`, `top`, sonst mittig) |
| `["wait", sekunden]` | Warten |

## Bedingungen

`"flag"`, `"!flag"`, `"has:item"`, `"medal:id"` oder eine Liste von Bedingungen, die alle gelten müssen.

## Komplettlösung

```json
{"steps": [["take", "werkzeugkasten"], ["use", "schraubenschluessel", "gitter"], ["choose", 0, 2], ["talk", "otti"]],
 "expect_flags": ["ende"], "expect_medals": ["wasserhahn"]}
```

Jeder Schritt ist ein Satz wie aus der Oberfläche. `["choose", i, j, ...]` legt die Auswahl im
nächsten Dialog fest (Indizes der jeweils sichtbaren Optionen).
