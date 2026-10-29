extends Node
## Spielzustand, Spieldaten und Skript-Interpreter (Autoload "Game").
##
## Räume, Gegenstände und Dialoge stehen als JSON in res://data. Die Spiellogik
## steckt komplett in diesen Daten; dieses Skript führt sie nur aus. Alles, was
## man sieht (Laufen, Sprechtexte, Auswahl), erledigt die View in main.gd.
## Ohne View (Tests) läuft die Logik genauso, nur ohne Darstellung.
##
## Alles Spielspezifische (Spielfigur, Begleiter, Sammelobjekte, Standardsätze)
## kommt aus data/game.json, siehe docs/format.md im Addon.

signal state_changed

## Platz 0 ist der Schnellspeicher (F5/F9), 1 bis SAVE_SLOTS - 1 wählt man im Menü.
const SAVE_SLOTS := 6
const ENGINE_DIR := "res://addons/game_engine"

const VERB_NAMES := {
	"give": "Gib",
	"open": "Öffne",
	"close": "Schließe",
	"take": "Nimm",
	"talk": "Rede mit",
	"use": "Benutze",
	"push": "Drücke",
	"pull": "Ziehe",
	"look": "Schau an",
	"walk": "Gehe zu",
}

## Verben mit zweitem Objekt und das Bindewort im Satz.
const TWO_OBJECT_VERBS := {"use": "mit", "give": "an"}

## Standardsätze; jedes Spiel kann sie in game.json unter "texts" ersetzen.
const DEFAULT_TEXTS := {
	"give": "Das will ich nicht hergeben.",
	"open": "Das lässt sich nicht öffnen.",
	"close": "Das lässt sich nicht schließen.",
	"take": "Das brauche ich nicht.",
	"talk": "Ich glaube nicht, dass das antwortet.",
	"use": "Das funktioniert so nicht.",
	"push": "Das bewegt sich nicht.",
	"pull": "Das bewegt sich nicht.",
	"look": "Nichts Besonderes.",
	"other": "Hm.",
	"already_have": "Das habe ich schon.",
	"exit_blocked": "Da komme ich nicht durch.",
	"saved": "Spielstand gespeichert.",
	"save_failed": "Speichern geht gerade nicht.",
	"loaded": "Spielstand geladen.",
	"load_failed": "Kein Spielstand vorhanden.",
	"music_on": "Musik an.",
	"music_off": "Musik aus.",
	"menu_title": "Pause",
	"menu_resume": "Weiterspielen",
	"menu_save": "Spielstand speichern",
	"menu_load": "Spielstand laden",
	"menu_quit": "Beenden",
	"menu_new": "Neues Spiel",
	"menu_continue": "Fortsetzen",
	"menu_back": "Zurück",
	"menu_quit_confirm": "Bist du sicher?",
	"menu_yes": "Ja",
	"menu_no": "Nein",
	"menu_overwrite": "Diesen Spielstand überschreiben?",
	"slot_empty": "– frei –",
	"slot_quick": "Schnellspeicher",
}

var meta: Dictionary = {}
var rooms: Dictionary = {}
var items: Dictionary = {}
var dialogs: Dictionary = {}
var characters: Dictionary = {}
## Sprecher-Id der Spielfigur (game.json "player.id").
var player_id: String = "player"
## Sprecher-Id des Begleiters oder "" (game.json "companion.id").
var companion_id: String = ""

var flags: Dictionary = {}
var inventory: Array = []
var medals: Array = []
var room_id: String = ""
var player_pos: Vector2 = Vector2.ZERO

## Die Darstellung (main.gd) oder null.
var view = null
## true, solange ein Skript läuft; die Oberfläche nimmt dann keine Befehle an.
var busy: bool = false
## Testmodus: keine Wartezeiten, Dialoge wählen automatisch.
var fast: bool = false
## Vorgegebene Dialogauswahl für Tests (Indizes der sichtbaren Optionen).
var scripted_choices: Array = []
## Ordner der Spielstände; Tests nehmen einen eigenen.
var save_dir: String = "user://"


func _ready() -> void:
	load_data()


func load_data() -> void:
	meta = _load_json("res://data/game.json")
	items = _load_json("res://data/items.json")
	dialogs = _load_json("res://data/dialogs.json")
	characters = meta.get("characters", {})
	player_id = meta.get("player", {}).get("id", "player")
	companion_id = meta.get("companion", {}).get("id", "")
	rooms.clear()
	for id in meta.get("rooms", []):
		var r := _load_json("res://data/rooms/%s.json" % id)
		if not r.is_empty():
			rooms[id] = r


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Datei fehlt: %s" % path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Kann %s nicht lesen" % path)
		return {}
	return data


# --- Spielstart, Speichern, Laden -------------------------------------------

func new_game() -> void:
	flags.clear()
	inventory.clear()
	medals.clear()
	busy = true
	await change_room(meta["start_room"], meta.get("start_entry", ""))
	await run(meta.get("intro", []))
	busy = false
	state_changed.emit()


func save_path(slot: int) -> String:
	return save_dir.path_join("spielstand.json" if slot == 0 else "spielstand_%d.json" % slot)


func save_game(slot := 0) -> bool:
	if busy or room_id == "":
		return false
	var data := {
		"room": room_id,
		"pos": [player_pos.x, player_pos.y],
		"flags": flags,
		"inventory": inventory,
		"medals": medals,
		"time": int(Time.get_unix_time_from_system()),
	}
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	return true


## Kurzinfo zu einem Speicherplatz für Menüs: {} wenn leer, sonst
## {"room", "room_name", "time" (Unix-Sekunden, 0 bei alten Ständen), "medals"}.
func save_info(slot: int) -> Dictionary:
	var data = _read_save(slot)
	if data == null:
		return {}
	var id: String = data["room"]
	return {
		"room": id,
		"room_name": rooms[id].get("name", id),
		"time": int(data.get("time", 0)),
		"medals": data.get("medals", []).size(),
	}


## Gibt es einen Spielstand auf diesem Platz (-1: auf irgendeinem)?
func has_save(slot := -1) -> bool:
	return latest_slot() >= 0 if slot < 0 else _read_save(slot) != null


## Der zuletzt gespeicherte Platz oder -1, etwa für „Fortsetzen“.
func latest_slot() -> int:
	var best := -1
	var best_time := -1
	for slot in SAVE_SLOTS:
		var info := save_info(slot)
		if not info.is_empty() and info["time"] > best_time:
			best = slot
			best_time = info["time"]
	return best


func load_game(slot := 0) -> bool:
	if busy:
		return false
	var data = _read_save(slot)
	if data == null:
		return false
	flags = data["flags"]
	inventory = data["inventory"]
	medals = data["medals"]
	room_id = data["room"]
	player_pos = Vector2(data["pos"][0], data["pos"][1])
	if view:
		view.room_entered()
	state_changed.emit()
	return true


func _read_save(slot: int):
	var path := save_path(slot)
	if not FileAccess.file_exists(path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not rooms.has(data.get("room", "")):
		return null
	return data


# --- Bedingungen ------------------------------------------------------------

## Bedingung prüfen: null (immer wahr), "flag", "!flag", "has:item",
## "medal:id" oder ein Array von Bedingungen, die alle gelten müssen.
func check(cond) -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c in cond:
			if not check(c):
				return false
		return true
	var s: String = cond
	var negate := s.begins_with("!")
	if negate:
		s = s.substr(1)
	var result: bool
	if s.begins_with("has:"):
		result = inventory.has(s.substr(4))
	elif s.begins_with("medal:"):
		result = medals.has(s.substr(6))
	else:
		result = flags.get(s, false)
	return result != negate


# --- Räume und Objekte ------------------------------------------------------

func room() -> Dictionary:
	return rooms.get(room_id, {})


func visible_hotspots() -> Array:
	var out := []
	for h in room().get("hotspots", []):
		if check(h.get("if")):
			out.append(h)
	return out


func hotspot(id: String) -> Dictionary:
	for h in visible_hotspots():
		if h["id"] == id:
			return h
	return {}


## Oberster sichtbarer Hotspot an einem Punkt (Raumkoordinaten). Später
## eingetragene Hotspots liegen oben.
func hotspot_at(p: Vector2) -> Dictionary:
	var hs := visible_hotspots()
	for i in range(hs.size() - 1, -1, -1):
		var r: Array = hs[i]["rect"]
		if Rect2(r[0], r[1], r[2], r[3]).has_point(p):
			return hs[i]
	return {}


## Definition eines Objekts: Gegenstand im Inventar oder Hotspot im Raum.
func object_def(id: String) -> Dictionary:
	if inventory.has(id):
		return items.get(id, {})
	return hotspot(id)


func object_name(id: String) -> String:
	return object_def(id).get("name", id)


## Erstes passendes Farb-/Bildvarianten-Feld: {"bedingung": wert, ...}.
func pick_variant(variants: Dictionary, fallback):
	for cond in variants:
		if check(cond):
			return variants[cond]
	return fallback


# --- Sätze ------------------------------------------------------------------

## Führt einen Satz aus, wie ihn die Oberfläche baut: "Benutze Klebeband mit Leck"
## ist do_sentence("use", "klebeband", "leitung").
func do_sentence(verb: String, obj1: String, obj2: String = "") -> void:
	if busy:
		return
	busy = true
	await _do_sentence(verb, obj1, obj2)
	busy = false
	state_changed.emit()


func _do_sentence(verb: String, obj1: String, obj2: String) -> void:
	var d1 := object_def(obj1)
	var d2 := object_def(obj2) if obj2 != "" else {}
	if d1.is_empty() or (obj2 != "" and d2.is_empty()):
		push_warning("Unbekanntes Objekt in Satz: %s %s %s" % [verb, obj1, obj2])
		return

	# Zum Hotspot laufen; Gegenstände im Inventar brauchen keinen Weg.
	var walk_target := {}
	if obj2 != "" and not inventory.has(obj2):
		walk_target = d2
	elif not inventory.has(obj1):
		walk_target = d1
	if view and not walk_target.is_empty():
		await view.walk_to_hotspot(walk_target)
	elif not walk_target.is_empty():
		player_pos = hotspot_walk_point(walk_target)

	if verb == "walk":
		if d1.has("exit"):
			await _use_exit(d1)
		elif _verb_actions(d1, "walk") != null:
			await run(_verb_actions(d1, "walk"))
		return

	var actions = null
	if obj2 != "":
		actions = _verb_actions(d2, verb + ":" + obj1)
		if actions == null:
			actions = _verb_actions(d1, verb + ":" + obj2)
	else:
		actions = _verb_actions(d1, verb)
	if actions == null:
		await say(player_id, _default_answer(verb, obj1))
		return
	# Beim Nehmen, das einen Gegenstand gibt, greift die Figur zu (Aktion "pickup", falls es Bilder gibt).
	if verb == "take" and view and not fast and actions.any(func(a): return a[0] == "give"):
		await view.play_action("pickup")
	await run(actions)


## Aktionen eines Verbs; ein String statt einer Liste verweist auf ein anderes
## Verb desselben Objekts ("push": "use").
func _verb_actions(def: Dictionary, key: String):
	var verbs: Dictionary = def.get("verbs", {})
	var actions = verbs.get(key)
	if actions is String:
		actions = verbs.get(actions)
	return actions


func _default_answer(verb: String, obj: String) -> String:
	if verb == "take" and inventory.has(obj):
		return text("already_have")
	return text(verb if DEFAULT_TEXTS.has(verb) else "other")


## Standardsatz aus game.json "texts" oder DEFAULT_TEXTS.
func text(key: String) -> String:
	return meta.get("texts", {}).get(key, DEFAULT_TEXTS.get(key, key))


func hotspot_walk_point(h: Dictionary) -> Vector2:
	if h.has("walk_to"):
		return Vector2(h["walk_to"][0], h["walk_to"][1])
	var r: Array = h["rect"]
	if h.has("speaker"):
		# Neben einer Figur stehen bleiben, nicht in ihr.
		var left: float = r[0] - 12
		var x: float = left if left > 30 else r[0] + r[2] + 12
		return Vector2(x, r[1] + r[3] + 4)
	return Vector2(r[0] + r[2] / 2.0, r[1] + r[3] + 4)


func _use_exit(h: Dictionary) -> void:
	if not check(h.get("exit_if")):
		await run(h.get("exit_blocked", [["say", player_id, text("exit_blocked")]]))
		return
	await run(h.get("exit_do", []))
	await change_room(h["exit"], h.get("entry", ""))


func change_room(id: String, entry: String = "") -> void:
	if not rooms.has(id):
		push_error("Unbekannter Raum: %s" % id)
		return
	room_id = id
	var entries: Dictionary = room().get("entries", {})
	var p = entries.get(entry)
	if p == null:
		p = entries.values()[0] if not entries.is_empty() else [160, 120]
	player_pos = Vector2(p[0], p[1])
	if view:
		view.room_entered()
	state_changed.emit()
	await run(room().get("on_enter", []))


# --- Skript-Interpreter -----------------------------------------------------

func run(actions: Array) -> void:
	for a in actions:
		await _exec(a)


func _exec(a: Array) -> void:
	match a[0]:
		"say":
			await say(a[1], a[2], a[3] if a.size() > 3 else "")
		"set":
			flags[a[1]] = true
		"clear":
			flags.erase(a[1])
		"give":
			if not inventory.has(a[1]):
				inventory.append(a[1])
			state_changed.emit()
		"remove":
			inventory.erase(a[1])
			state_changed.emit()
		"confiscate":
			# Alles abnehmen außer den genannten Gegenständen.
			inventory = inventory.filter(func(i): return a[1].has(i))
			state_changed.emit()
		"if":
			if check(a[1]):
				await run(a[2])
			elif a.size() > 3:
				await run(a[3])
		"case":
			for branch in a[1]:
				if check(branch[0]):
					await run(branch[1])
					break
		"goto":
			await change_room(a[1], a[2] if a.size() > 2 else "")
		"walk":
			if view:
				await view.walk_to(Vector2(a[1], a[2]))
			else:
				player_pos = Vector2(a[1], a[2])
		"medal":
			await award_medal(a[1])
		"dialog":
			await run_dialog(a[1])
		"title":
			if view:
				await view.show_title(a[1], a[2] if a.size() > 2 else "", a[3] if a.size() > 3 else "")
		"anim":
			if view and not fast:
				await view.play_action(a[1])
		"music":
			if view:
				view.music.play(a[1] if a.size() > 1 else view.music.track_for(room()))
		"wait":
			if view and not fast:
				await get_tree().create_timer(a[1]).timeout
		_:
			push_error("Unbekannter Befehl: %s" % str(a))


## mood: Stimmung für die Sprechbilder ("" = ruhig, z. B. "happy"), siehe room_view._talk_frame
func say(who: String, text: String, mood := "") -> void:
	if view:
		await view.say(who, text, mood)
	elif not fast:
		print("%s: %s" % [characters.get(who, {}).get("name", who), text])


func award_medal(id: String) -> void:
	if medals.has(id):
		return
	medals.append(id)
	state_changed.emit()
	var names: Dictionary = meta.get("medals", {})
	var label: String = meta.get("medal_label", {}).get("one", "Medaille")
	await say("text", "%s: %s (%d/%d)" % [label, names.get(id, id), medals.size(), names.size()])


func run_dialog(id: String) -> void:
	var dlg: Dictionary = dialogs.get(id, {})
	var node_id := "start"
	while dlg.has(node_id):
		var node: Dictionary = dlg[node_id]
		await run(node.get("do", []))
		var all_options: Array = node.get("options", [])
		var shown := []
		for i in all_options.size():
			var o: Dictionary = all_options[i]
			var once_flag := "dlg:%s:%s:%d" % [id, node_id, i]
			if check(o.get("if")) and not (o.get("once", false) and flags.has(once_flag)):
				shown.append(i)
		if shown.is_empty():
			return
		var choice := shown.size() - 1
		if not scripted_choices.is_empty():
			choice = scripted_choices.pop_front()
		elif view and not fast:
			var texts := []
			for i in shown:
				texts.append(all_options[i]["text"])
			choice = await view.choose(texts)
		var index: int = shown[clampi(choice, 0, shown.size() - 1)]
		var option: Dictionary = all_options[index]
		if option.get("once", false):
			flags["dlg:%s:%s:%d" % [id, node_id, index]] = true
		await say(player_id, option["text"], option.get("mood", ""))
		await run(option.get("do", []))
		node_id = option.get("next", "end")
