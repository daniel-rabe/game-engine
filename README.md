# game-engine

Gemeinsame Adventure-Engine im Stil von Monkey Island 2 als Godot-4-Addon.
Sie läuft unter `addons/game_engine/` in
[Weltraumschrott](https://github.com/daniel-rabe/Weltraumschrott) und
[Gegenwind](https://github.com/daniel-rabe/gegenwind).

Die Engine führt nur aus, was in den JSON-Daten des Spiels steht: Räume,
Gegenstände, Dialoge und die Skripte an Hotspots. Es gibt keinen Bytecode und
keinen spielspezifischen Code im Addon. Fehlende Grafiken zeichnet sie als
Platzhalter, sodass jedes Spiel ohne eine einzige PNG-Datei durchspielbar ist.

## Inhalt

| Datei | Aufgabe |
| --- | --- |
| `game.gd` | Autoload `Game`: Spielzustand, Daten laden, Skript-Interpreter, Speichern/Laden |
| `main.gd`, `main.tscn` | MI2-Oberfläche: neun Verben, Satzzeile, Inventar, Sprechtexte, Dialogauswahl |
| `room_view.gd` | Raumdarstellung mit Grafiken nach Dateikonvention oder Platzhaltern |
| `tests/walkthrough.gd` | Spielt `res://tests/walkthrough.json` des Spiels in der echten Engine durch |
| `tests/screenshot.gd` | Bildschirmfoto nach n Schritten der Komplettlösung |
| `tools/check_game.py` | Prüft die Daten und simuliert die Komplettlösung ohne Godot |
| `tools/asset_manifest.py` | Erzeugt `art/manifest.json` und Layoutvorlagen für ComfyUI |
| `demo/` | Kleines Testspiel für die Engine selbst |
| `docs/format.md` | Das Datenformat |

## In ein Spiel einbinden

```
git submodule add https://github.com/daniel-rabe/game-engine addons/game_engine
```

In `project.godot`:

```
[application]
run/main_scene="res://addons/game_engine/main.tscn"

[autoload]
Game="*res://addons/game_engine/game.gd"
```

Die Spieldaten liegen im Spiel unter `data/`, Grafiken unter `art/`, die
Komplettlösung unter `tests/walkthrough.json`. Eine neue Engine-Version holt man mit
`git -C addons/game_engine pull origin main` (oder einen Tag auschecken) und
committet den neuen Stand des Submoduls.

## Tests

Im Spielordner:

```
python3 addons/game_engine/tools/check_game.py                       # Daten + Simulation
godot --headless --path . -s res://addons/game_engine/tests/walkthrough.gd   # echte Engine
```

Für die Engine selbst: `tests/run_demo.sh [godot-programm]`. GitHub Actions führt
das bei jedem Pull Request aus.
