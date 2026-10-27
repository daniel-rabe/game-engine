extends SceneTree
## Spielt die Komplettlösung aus tests/walkthrough.json in der echten Engine durch.
## Die Sätze sind dieselben, die die Oberfläche beim Klicken erzeugt.
##
## Aufruf (im Projektordner):
##   godot --headless --path . -s tests/walkthrough.gd
## Exit-Code 0 = bestanden, 1 = Fehler.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = root.get_node_or_null("Game")
	if game == null:
		game = load("res://addons/game_engine/game.gd").new()
		game.name = "Game"
		root.add_child(game)
	game.fast = true
	var wt = JSON.parse_string(FileAccess.get_file_as_string("res://tests/walkthrough.json"))
	await game.change_room(game.meta["start_room"], game.meta.get("start_entry", ""))
	var n := 0
	for step in wt["steps"]:
		n += 1
		if step[0] == "choose":
			game.scripted_choices = step.slice(1).map(func(c): return int(c))
			continue
		var verb: String = step[0]
		var a: String = step[1]
		var b: String = step[2] if step.size() > 2 else ""
		for id in [a, b]:
			if id != "" and game.object_def(id).is_empty():
				_fail("Schritt %d %s: '%s' ist in Raum %s nicht da" % [n, str(step), id, game.room_id])
				return
		var room_before: String = game.room_id
		var is_exit: bool = game.object_def(a).has("exit")
		await game.do_sentence(verb, a, b)
		if verb == "walk" and is_exit and game.room_id == room_before:
			_fail("Schritt %d %s: Ausgang hat nicht funktioniert" % [n, str(step)])
			return
	for f in wt.get("expect_flags", []):
		if not game.flags.get(f, false):
			_fail("Flag %s fehlt am Ende" % f)
			return
	for m in wt.get("expect_medals", []):
		if not game.medals.has(m):
			_fail("Medaille %s fehlt am Ende" % m)
			return
	print("Durchspieltest bestanden: %d Schritte, %d Medaillen" % [n, game.medals.size()])
	quit(0)


func _fail(message: String) -> void:
	printerr("Durchspieltest fehlgeschlagen: " + message)
	quit(1)
