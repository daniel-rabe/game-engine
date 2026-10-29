extends SceneTree
## Spielfigur steht, läuft nach rechts und zurück; für Aufnahmen mit --write-movie.
##
##   godot --path . --write-movie user://walk/f.png --fixed-fps 30 -s res://addons/game_engine/tests/walk_movie.gd -- --from=60 --to=250

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var game = root.get_node("Game")
	game.fast = true  # Intro überspringen
	var main = load("res://addons/game_engine/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	game.fast = false
	var y := float(args.get("y", "124"))
	game.player_pos = Vector2(float(args.get("from", "60")), y)
	await create_timer(2.0).timeout
	await main.walk_to(Vector2(float(args.get("to", "250")), y))
	await create_timer(1.5).timeout
	await main.walk_to(Vector2(float(args.get("from", "60")), y))
	await create_timer(1.5).timeout
	quit(0)
