#!/usr/bin/env bash
# Prüft die Engine mit dem Demospiel aus demo/: Datenprüfung und Durchspieltest
# in echtem Godot. Aufruf: tests/run_demo.sh [godot-programm]
set -euo pipefail
GODOT="${1:-${GODOT:-godot}}"
ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -r "$ENGINE/demo/." "$WORK/"
rm -f "$WORK/.gdignore"
mkdir -p "$WORK/addons/game_engine"
tar -C "$ENGINE" --exclude=.git --exclude=demo -cf - . | tar -C "$WORK/addons/game_engine" -xf -
python3 "$ENGINE/tools/check_game.py" --root="$WORK"
"$GODOT" --headless --path "$WORK" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$WORK" -s res://addons/game_engine/tests/walkthrough.gd
