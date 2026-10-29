extends SceneTree
## Spielfigur steht und läuft dann eine Punktfolge ab; für Aufnahmen mit --write-movie.
##
##   godot --path . --write-movie user://walk/f.png --fixed-fps 30 -s res://addons/game_engine/tests/walk_movie.gd -- --path=70:124,250:136,200:106 --do=take:werkzeugkasten

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
	var points := []
	for p: String in String(args.get("path", "60:124,250:124,60:124")).split(","):
		var xy: PackedStringArray = p.split(":")
		points.append(Vector2(float(xy[0]), float(xy[1])))
	game.player_pos = points[0]
	await create_timer(2.0).timeout
	for p in points.slice(1):
		await main.walk_to(p)
		await create_timer(0.6).timeout
	# optional ein Satz am Ende, z. B. --do=take:werkzeugkasten
	if args.has("do"):
		var vo: PackedStringArray = String(args["do"]).split(":")
		await game.do_sentence(vo[0], vo[1])
	await create_timer(1.0).timeout
	quit(0)
