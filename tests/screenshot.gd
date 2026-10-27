extends SceneTree
## Macht ein Bildschirmfoto des Spiels nach einer Anzahl Schritte der Komplettlösung.
## Braucht eine echte Grafikausgabe (nicht --headless), z. B. unter xvfb-run.
##
##   godot --path . -s tests/screenshot.gd -- --steps=10 --out=user://shot.png

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var game = root.get_node("Game")
	game.fast = true
	var main = load("res://addons/game_engine/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var wt = JSON.parse_string(FileAccess.get_file_as_string("res://tests/walkthrough.json"))
	var steps: int = int(args.get("steps", "0"))
	for i in min(steps, wt["steps"].size()):
		var s: Array = wt["steps"][i]
		if s[0] == "choose":
			game.scripted_choices = s.slice(1).map(func(c): return c if c is String else int(c))
			continue
		await game.do_sentence(s[0], s[1], s[2] if s.size() > 2 else "")
	game.fast = false
	if args.has("say"):
		game.say(args.get("who", game.player_id), args["say"])
	for i in 30:
		await process_frame
	var out: String = args.get("out", "user://screenshot.png")
	root.get_viewport().get_texture().get_image().save_png(out)
	print("Bild gespeichert: ", ProjectSettings.globalize_path(out))
	quit(0)
