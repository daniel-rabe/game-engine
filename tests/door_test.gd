extends SceneTree
## Prüft die Schiebetüren (Hotspot-Feld "door") im Demospiel in der echten Oberfläche:
## verschlossene Tür bleibt zu, offene Tür geht in der Nähe auf und hinter der Figur wieder zu,
## der Ausgang wartet auf die offene Tür, beim Betreten und Laden steht die Tür richtig.
##
##   godot --headless --path . -s res://addons/game_engine/tests/door_test.gd

const SETTLE := 0.8  # länger als die Öffnungszeit der Demo-Türen

var game
var main
var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = root.get_node("Game")
	game.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(game.save_dir)
	game.fast = true
	main = load("res://addons/game_engine/main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	game.fast = false
	var rv = main.room_view
	var tuer: Dictionary = game.hotspot("tuer")
	var door_point: Vector2 = game.hotspot_walk_point(tuer)
	_expect(game.room_id == "werkstatt" and rv.is_door(tuer), "Werkstatt hat eine Schiebetür")
	_expect(rv.door_openness("tuer") == 0.0, "Tür ist am Anfang zu")

	# verschlossen (exit_if has:schluessel): bleibt zu, auch direkt davor
	game.player_pos = door_point
	await _wait(SETTLE)
	_expect(rv.door_openness("tuer") == 0.0, "verschlossene Tür bleibt zu")

	# aufgeschlossen: geht in der Nähe auf, weg davon wieder zu
	game.inventory.append("schluessel")
	await _wait(0.1)
	var halfway: float = rv.door_openness("tuer")
	_expect(halfway > 0.0 and halfway < 1.0, "Tür gleitet auf (%.2f nach 0,1 s)" % halfway)
	await _wait(SETTLE)
	_expect(rv.door_openness("tuer") == 1.0, "Tür ist offen, wenn die Figur davor steht")
	game.player_pos = Vector2(60, 120)
	await _wait(SETTLE)
	_expect(rv.door_openness("tuer") == 0.0, "Tür schließt, wenn die Figur weggeht")

	# durch die Tür gehen: die Figur läuft hin, die Tür geht auf, dann Raumwechsel
	game.player_pos = Vector2(200, 120)
	await game.do_sentence("walk", "tuer")
	_expect(game.room_id == "hof", "Ausgang durch die Schiebetür führt in den Hof")
	_expect(rv.door_openness("tuer") == 1.0, "Tür im Hof ist beim Hereinkommen offen")
	game.player_pos = Vector2(250, 120)
	await _wait(SETTLE)
	_expect(rv.door_openness("tuer") == 0.0, "und schließt sich hinter der Figur")

	# Laden: der Türzustand folgt aus der Position, Spielstände brauchen nichts Neues
	game.player_pos = game.hotspot_walk_point(game.hotspot("tuer"))
	_expect(game.save_game(1), "Spielstand vor der Tür gespeichert")
	game.player_pos = Vector2(250, 120)
	await _wait(SETTLE)
	_expect(game.load_game(1), "Spielstand geladen")
	_expect(rv.door_openness("tuer") == 1.0, "nach dem Laden vor der Tür ist sie offen")

	DirAccess.remove_absolute(game.save_path(1))
	print("Türtest: %s" % ("OK" if errors == 0 else "%d Fehler" % errors))
	quit(1 if errors else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FEHLER ") + what)
	if not ok:
		errors += 1
