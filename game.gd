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

const SAVE_PATH := "user://spielstand.json"
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
}

var meta: Dictionary = {}
var rooms: Dictionary = {}
var items: Dictionary = {}
var dialogs: Dictionary = {}
var duels: Dictionary = {}
var characters: Dictionary = {}
## Sprecher-Id der Spielfigur (game.json "player.id").
var player_id: String = "player"
## Sprecher-Id des Begleiters oder "" (game.json "companion.id").
var companion_id: String = ""

var flags: Dictionary = {}
var inventory: Array = []
var medals: Array = []
## Zähler wie Unterschriften: {"name": zahl}, Definitionen in game.json "counters".
var counters: Dictionary = {}
var room_id: String = ""
var player_pos: Vector2 = Vector2.ZERO

## Die Darstellung (main.gd) oder null.
var view = null
## true, solange ein Skript läuft; die Oberfläche nimmt dann keine Befehle an.
var busy: bool = false
## Testmodus: keine Wartezeiten, Dialoge wählen automatisch.
var fast: bool = false
## Vorgegebene Auswahl für Tests: Indizes der sichtbaren Dialogoptionen oder
## Ids von Entgegnungen im Duell.
var scripted_choices: Array = []
## Fehler, die ein Test melden soll (z. B. vorgegebene Wahl nicht möglich).
var test_errors: Array = []


func _ready() -> void:
	load_data()


func load_data() -> void:
	meta = _load_json("res://data/game.json")
	items = _load_json("res://data/items.json")
	dialogs = _load_json("res://data/dialogs.json")
	duels = _load_json("res://data/duels.json") if FileAccess.file_exists("res://data/duels.json") else {}
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
	counters.clear()
	busy = true
	await change_room(meta["start_room"], meta.get("start_entry", ""))
	await run(meta.get("intro", []))
	busy = false
	state_changed.emit()


func save_game() -> bool:
	if busy or room_id == "":
		return false
	var data := {
		"room": room_id,
		"pos": [player_pos.x, player_pos.y],
		"flags": flags,
		"inventory": inventory,
		"medals": medals,
		"counters": counters,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	return true


func load_game() -> bool:
	if busy or not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY or not rooms.has(data.get("room", "")):
		return false
	flags = data["flags"]
	inventory = data["inventory"]
	medals = data["medals"]
	counters = data.get("counters", {})
	room_id = data["room"]
	player_pos = Vector2(data["pos"][0], data["pos"][1])
	if view:
		view.room_entered()
	state_changed.emit()
	return true


# --- Bedingungen ------------------------------------------------------------

## Bedingung prüfen: null (immer wahr), "flag", "!flag", "has:item",
## "medal:id", ein Zählervergleich wie "unterschriften>=400" oder ein Array
## von Bedingungen, die alle gelten müssen.
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
	elif _COMPARE.search(s):
		result = _compare(s)
	else:
		result = flags.get(s, false)
	return result != negate


const _OPS := ["==", "!=", ">=", "<=", ">", "<"]
static var _COMPARE := RegEx.create_from_string("^[A-Za-z0-9_]+(==|!=|>=|<=|>|<)-?[0-9]+$")


func _compare(s: String) -> bool:
	for op in _OPS:
		var i := s.find(op)
		if i > 0:
			var value := int(counters.get(s.substr(0, i), 0))
			var target := int(s.substr(i + op.length()))
			match op:
				"==": return value == target
				"!=": return value != target
				">=": return value >= target
				"<=": return value <= target
				">": return value > target
				"<": return value < target
	return false


func counter(name: String) -> int:
	return int(counters.get(name, 0))


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
			await say(a[1], a[2])
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
		"add":
			counters[a[1]] = counter(a[1]) + int(a[2])
			state_changed.emit()
		"count":
			counters[a[1]] = int(a[2])
			state_changed.emit()
		"duel":
			await run_duel(a[1])
		"dialog":
			await run_dialog(a[1])
		"title":
			if view:
				await view.show_title(a[1])
		"wait":
			if view and not fast:
				await get_tree().create_timer(a[1]).timeout
		_:
			push_error("Unbekannter Befehl: %s" % str(a))


## Sprechtext; "{zaehler}" im Text wird durch den Zählerstand ersetzt.
func say(who: String, line: String) -> void:
	if "{" in line:
		for c in counters:
			line = line.replace("{%s}" % c, str(counters[c]))
	if view:
		await view.say(who, line)
	elif not fast:
		print("%s: %s" % [characters.get(who, {}).get("name", who), line])


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
			choice = int(scripted_choices.pop_front())
		elif view and not fast:
			var texts := []
			for i in shown:
				texts.append(all_options[i]["text"])
			choice = await view.choose(texts)
		var index: int = shown[clampi(choice, 0, shown.size() - 1)]
		var option: Dictionary = all_options[index]
		if option.get("once", false):
			flags["dlg:%s:%s:%d" % [id, node_id, index]] = true
		await say(player_id, option["text"])
		await run(option.get("do", []))
		node_id = option.get("next", "end")


# --- Argumente-Duell --------------------------------------------------------

## Argumente-Duell nach Art des Beleidigungsfechtens (Daten in data/duels.json).
## Die Gegenseite bringt eine Behauptung, die Spielfigur wählt eine Entgegnung.
## Passt sie, steigt das Publikumsbarometer, sonst sinkt es. Bei "win" ist das
## Duell gewonnen, bei "lose" abgebrochen; man kann es jederzeit neu versuchen.
func run_duel(id: String) -> void:
	var d: Dictionary = duels.get(id, {})
	if d.is_empty():
		push_error("Unbekanntes Duell: %s" % id)
		return
	var opponent: String = d.get("opponent", "text")
	var meter: int = d.get("start", 50)
	var step: int = d.get("step", 10)
	var rounds: Array = d.get("rounds", [])
	var countered := {}
	if view:
		view.duel_meter(d.get("label", "Publikum"), meter)
	await run(d.get("intro", []))
	var r := 0
	while meter < d.get("win", 100) and meter > d.get("lose", 0) and not rounds.is_empty():
		if countered.size() >= rounds.size():
			countered.clear()
		while countered.has(r % rounds.size()):
			r += 1
		var index := r % rounds.size()
		var rd: Dictionary = rounds[index]
		r += 1
		await say(opponent, rd["claim"])
		var options := duel_options(d)
		var pick := options.size() - 1
		if not scripted_choices.is_empty():
			pick = _duel_pick(options, scripted_choices.pop_front())
		elif view and not fast:
			var texts := []
			for o in options:
				texts.append(o["text"])
			pick = await view.choose(texts)
		var answer: Dictionary = options[clampi(pick, 0, options.size() - 1)]
		await say(player_id, answer["text"])
		var correct = rd.get("answer", [])
		if correct is String:
			correct = [correct]
		if correct.has(answer["id"]):
			countered[index] = true
			meter = mini(meter + step, 100)
			if view:
				view.duel_meter(d.get("label", "Publikum"), meter)
			await run(rd.get("hit", d.get("hit", [])))
		else:
			meter = maxi(meter - step, 0)
			if view:
				view.duel_meter(d.get("label", "Publikum"), meter)
			await run(rd.get("miss", d.get("miss", [])))
	if view:
		view.duel_meter("", -1)
	if meter >= d.get("win", 100):
		flags["duel_won:" + id] = true
		await run(d.get("on_win", []))
	else:
		await run(d.get("on_lose", []))


## Entgegnungen, die gerade zur Wahl stehen: freigeschaltete zuerst, dann die
## immer verfügbaren schwachen Antworten ("fillers").
func duel_options(d: Dictionary) -> Array:
	var out := []
	var retorts: Dictionary = d.get("retorts", {})
	for rid in retorts:
		if check(retorts[rid].get("if")):
			out.append({"id": rid, "text": retorts[rid]["text"]})
	var fillers: Array = d.get("fillers", ["Äh ..."])
	for i in fillers.size():
		out.append({"id": "filler:%d" % i, "text": fillers[i]})
	return out


## Vorgegebene Wahl im Test: Index oder Id der Entgegnung.
func _duel_pick(options: Array, wanted) -> int:
	if wanted is String:
		for i in options.size():
			if options[i]["id"] == wanted:
				return i
		test_errors.append("Entgegnung %s steht im Duell nicht zur Wahl" % wanted)
		return options.size() - 1
	return int(wanted)
