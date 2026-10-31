extends SceneTree
## Prüft das Spielmenü (Esc) in der echten Oberfläche: Esc bricht erst einen
## halben Satz ab, dann öffnet es das Menü; Speichern auf Platz 1, Laden,
## Lautstärkeregler, Beenden-Abfrage. Spielstände landen in user://test_saves, nicht bei den echten.
## Braucht eine Grafikausgabe; mit --shots=<ordner> entstehen Bildschirmfotos.
##
##   godot --path . -s res://addons/game_engine/tests/menu_test.gd -- --steps=4 --shots=user://menu

var game
var main
var shots := ""
var errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	shots = args.get("shots", "")
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	game = root.get_node("Game")
	game.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(game.save_dir)
	var real_volume: Dictionary = game.volume.duplicate()
	game.settings_path = "user://test_saves/einstellungen.cfg"
	DirAccess.remove_absolute(game.settings_path)
	for slot in game.SAVE_SLOTS:
		DirAccess.remove_absolute(game.save_path(slot))
	game.fast = true
	main = load("res://addons/game_engine/main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	var wt = JSON.parse_string(FileAccess.get_file_as_string("res://tests/walkthrough.json"))
	for i in min(int(args.get("steps", "4")), wt["steps"].size()):
		var s: Array = wt["steps"][i]
		if s[0] == "choose":
			game.scripted_choices = s.slice(1).map(func(c): return int(c))
			continue
		await game.do_sentence(s[0], s[1], s[2] if s.size() > 2 else "")
	game.fast = false
	var menu = main.menu

	# Esc mit halbem Satz bricht nur den Satz ab
	main._on_verb_pressed("use")
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(main.verb == "walk" and not menu.visible, "Esc bricht halben Satz ab")
	_key(KEY_ESCAPE)
	await _frames(5)
	_expect(menu.visible and paused, "Esc öffnet Menü und hält an")
	_expect(_entry("menu_load").disabled, "Laden aus, solange nichts gespeichert ist")
	await _shot("1_menu")

	# Speichern auf Platz 1
	_entry("menu_save").pressed.emit()
	await _frames(5)
	await _shot("2_speichern")
	var room: String = game.room_id
	var inv: Array = game.inventory.duplicate()
	_slot_button(1).pressed.emit()
	await _frames(2)
	_expect(not menu.visible and not paused, "Menü nach dem Speichern zu")
	_expect(game.save_info(1).get("room") == room, "Platz 1 gespeichert")
	_expect(game.latest_slot() == 1, "neuester Platz ist 1")

	# Überschreiben fragt nach, Nein führt zurück
	main.open_menu()
	_entry("menu_save").pressed.emit()
	_slot_button(1).pressed.emit()
	await _frames(5)
	_expect(menu._page == "confirm", "Überschreiben fragt nach")
	_entry("menu_no").pressed.emit()
	_expect(menu._page == "save", "Nein führt zu den Plätzen zurück")
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(not menu.visible, "Esc schließt Seite für Seite")

	# Zustand ändern, dann laden
	game.inventory.clear()
	game.flags["menu_test"] = true
	main.open_menu()
	_entry("menu_load").pressed.emit()
	await _frames(5)
	await _shot("3_laden")
	_slot_button(1).pressed.emit()
	await _frames(5)
	_expect(game.inventory == inv and not game.flags.has("menu_test") and game.room_id == room, "Laden stellt Zustand her")

	# Optionen: Regler stellt den Bus sofort, Zurück speichert
	main.open_menu()
	_entry("menu_options").pressed.emit()
	await _frames(5)
	_expect(menu._page == "options", "Optionen öffnen")
	var sliders: Array = menu.find_children("*", "HSlider", true, false)
	_expect(sliders.size() == game.VOLUME_BUSES.size(), "ein Regler je Bus")
	sliders[0].value = 0.5
	var music_bus := AudioServer.get_bus_index("Music")
	_expect(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.5)), "Musikregler stellt den Bus")
	sliders[1].value = 0.0
	_expect(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice")) <= -79.0, "Sprache auf 0 ist stumm")
	await _shot("5_optionen")
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(menu._page == "main", "Esc führt von den Optionen zurück")
	var cfg := ConfigFile.new()
	_expect(cfg.load(game.settings_path) == OK and is_equal_approx(cfg.get_value("volume", "Music", 1.0), 0.5), "Lautstärke gespeichert")
	game.volume.clear()
	game.load_settings()
	_expect(is_equal_approx(game.volume["Music"], 0.5) and game.volume["Voice"] == 0.0, "Lautstärke wieder geladen")
	menu.close()

	# Beenden fragt nach
	main.open_menu()
	_entry("menu_quit").pressed.emit()
	await _frames(5)
	_expect(menu._page == "confirm" and menu._title.text == game.text("menu_quit_confirm"), "Beenden fragt „Bist du sicher?“")
	await _shot("4_beenden")
	_entry("menu_no").pressed.emit()
	_expect(menu._page == "main", "Nein führt zum Menü zurück")
	menu.close()

	for slot in game.SAVE_SLOTS:
		DirAccess.remove_absolute(game.save_path(slot))
	DirAccess.remove_absolute(game.settings_path)
	for bus in real_volume:
		game.set_volume(bus, real_volume[bus], false)
	print("Menütest: %s" % ("OK" if errors == 0 else "%d Fehler" % errors))
	quit(1 if errors else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	root.push_input(e)


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FEHLER ") + what)
	if not ok:
		errors += 1


## Knopf im Menü nach Text-Schlüssel.
func _entry(key: String) -> Button:
	return _find(main.menu, func(b: Button) -> bool: return b.text == game.text(key))


func _slot_button(slot: int) -> Button:
	return _find(main.menu, func(b: Button) -> bool: return b.text.begins_with("%d " % slot))


func _find(node: Node, test: Callable) -> Button:
	for c in node.get_children():
		if c is Button and test.call(c):
			return c
		var b := _find(c, test)
		if b:
			return b
	return null


func _shot(name: String) -> void:
	if shots == "":
		return
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))
