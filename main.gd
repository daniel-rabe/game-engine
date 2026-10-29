extends Node2D
## Darstellung und Bedienung im Stil von Monkey Island 2: Raum oben, darunter
## Satzzeile, neun Verben und Inventar. Baut alle Knoten im Code auf.
##
## Bedienung: Verb wählen, Objekt anklicken. Linksklick ohne Verb läuft,
## Rechtsklick nimmt das Standardverb des Objekts. F5 speichert, F9 lädt,
## Esc bricht einen halben Satz ab, sonst öffnet es das Spielmenü (menu.gd).
## Linksklick oder Punkt überspringt Text.

signal arrived
signal choice_made(index: int)

const ROOM_SCALE := 2.0
const UI_TOP := 288
const WALK_SPEED := 70.0
const VERB_GRID := [["give", "take", "use"], ["open", "look", "push"], ["close", "talk", "pull"]]
const INV_COLUMNS := 3
const INV_ROWS := 2
const VERB_COLOR := Color("#2f7a2f")
const VERB_ACTIVE := Color("#8cff8c")
const VERB_HINT := Color("#58c058")

var room_view = null  # room_view.gd
var music = null  # music.gd
var menu = null  # menu.gd
var sentence_label: Label
var speech_label: Label
var title_label: Label
var title_bg: ColorRect
var toast_label: Label
var medal_label: Label
var verb_panel: Control
var choice_box: VBoxContainer
var verb_buttons := {}
var inv_buttons: Array = []
var inv_up: Button
var inv_down: Button

var verb := "walk"
var obj1 := ""
var awaiting_second := false
var hover := ""
var inv_scroll := 0

var walk_target = null
var companion_pos := Vector2.ZERO
## Der Begleiter schwebt so hoch über dem Boden und so weit hinter der Spielfigur (Raumeinheiten, vorn im Raum).
const COMPANION_HOVER := 36.0
const COMPANION_BEHIND := 22.0
var _skip := false
var _inv_hover := ""
var _talking := ""
var _talk_text := ""
var _talk_mood := ""
var _talk_t := 0.0
var _talk_duration := 1.0
## Mundformen beim Sprechen, je Buchstabe; alles andere (Leerzeichen, Satzzeichen) schließt den Mund.
const MOUTHS := {"a": "open", "ä": "open", "o": "o", "u": "o", "ö": "o", "ü": "o", "e": "e", "i": "e", "y": "e",
	"m": "closed", "b": "closed", "p": "closed"}
const MOUTH_RATE := 11.0  # Wechsel pro Sekunde


func _ready() -> void:
	Game.view = self
	room_view = preload("res://addons/game_engine/room_view.gd").new()
	room_view.scale = Vector2(ROOM_SCALE, ROOM_SCALE)
	add_child(room_view)
	music = preload("res://addons/game_engine/music.gd").new()
	music.process_mode = Node.PROCESS_MODE_ALWAYS  # läuft im Menü weiter
	add_child(music)
	_build_ui()
	Game.state_changed.connect(_refresh_ui)
	_refresh_ui()
	Game.new_game()


# --- Aufbau der Oberfläche --------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.size = Vector2(640, 400)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var panel := ColorRect.new()
	panel.color = Color("#07070f")
	panel.position = Vector2(0, UI_TOP)
	panel.size = Vector2(640, 400 - UI_TOP)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	sentence_label = _make_label(root, Vector2(0, UI_TOP + 2), Vector2(640, 20), Color("#c8a0ff"), 15)
	sentence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	verb_panel = Control.new()
	verb_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	verb_panel.size = Vector2(640, 400)
	root.add_child(verb_panel)
	for row in VERB_GRID.size():
		for col in VERB_GRID[row].size():
			var v: String = VERB_GRID[row][col]
			var b := _make_button(verb_panel, Game.VERB_NAMES[v], Vector2(6 + col * 104, UI_TOP + 26 + row * 28), Vector2(100, 26))
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(_on_verb_pressed.bind(v))
			verb_buttons[v] = b

	for i in INV_COLUMNS * INV_ROWS:
		var pos := Vector2(332 + (i % INV_COLUMNS) * 94, UI_TOP + 26 + int(i / float(INV_COLUMNS)) * 42)
		var b := _make_button(verb_panel, "", pos, Vector2(90, 38))
		b.clip_text = true
		b.expand_icon = true
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", Color("#d8b070"))
		b.add_theme_color_override("font_hover_color", Color("#ffe0a0"))
		b.gui_input.connect(_on_inv_input.bind(i))
		b.mouse_entered.connect(_on_inv_hover.bind(i))
		b.mouse_exited.connect(_on_inv_hover.bind(-1))
		inv_buttons.append(b)
	inv_up = _make_button(verb_panel, "▲", Vector2(614, UI_TOP + 26), Vector2(22, 38))
	inv_down = _make_button(verb_panel, "▼", Vector2(614, UI_TOP + 68), Vector2(22, 38))
	inv_up.pressed.connect(_scroll_inventory.bind(-1))
	inv_down.pressed.connect(_scroll_inventory.bind(1))

	medal_label = _make_label(root, Vector2(332, UI_TOP + 2), Vector2(300, 20), Color("#a08a50"), 11)
	medal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	choice_box = VBoxContainer.new()
	choice_box.position = Vector2(8, UI_TOP + 4)
	choice_box.size = Vector2(624, 400 - UI_TOP - 8)
	choice_box.visible = false
	root.add_child(choice_box)

	speech_label = _make_label(root, Vector2.ZERO, Vector2(380, 140), Color.WHITE, 16)
	speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speech_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_label.add_theme_color_override("font_outline_color", Color.BLACK)
	speech_label.add_theme_constant_override("outline_size", 5)

	toast_label = _make_label(root, Vector2(0, 4), Vector2(640, 20), Color("#ffe080"), 13)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 4)

	title_bg = ColorRect.new()
	title_bg.color = Color.BLACK
	title_bg.size = Vector2(640, 400)
	title_bg.visible = false
	title_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_bg)
	title_label = _make_label(title_bg, Vector2(20, 0), Vector2(600, 400), Color("#ffd27f"), 26)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	menu = preload("res://addons/game_engine/menu.gd").new()
	menu.view = self
	root.add_child(menu)


func _make_label(parent: Node, pos: Vector2, size: Vector2, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _make_button(parent: Node, text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = pos
	b.size = size
	b.add_theme_color_override("font_color", VERB_COLOR)
	b.add_theme_color_override("font_hover_color", VERB_ACTIVE)
	parent.add_child(b)
	return b


func _refresh_ui() -> void:
	var max_scroll: int = max(0, ceili(Game.inventory.size() / float(INV_COLUMNS)) - INV_ROWS)
	inv_scroll = clampi(inv_scroll, 0, max_scroll)
	for i in inv_buttons.size():
		var idx: int = inv_scroll * INV_COLUMNS + i
		var b: Button = inv_buttons[i]
		if idx < Game.inventory.size():
			var id: String = Game.inventory[idx]
			var icon: Texture2D = room_view.texture("res://art/items/%s.png" % id)
			b.icon = icon
			var item: Dictionary = Game.items.get(id, {})
			b.text = "" if icon else item.get("short", item.get("name", id))
			b.tooltip_text = Game.items.get(id, {}).get("name", id)
		else:
			b.icon = null
			b.text = ""
			b.tooltip_text = ""
	inv_up.disabled = inv_scroll == 0
	inv_down.disabled = inv_scroll >= max_scroll
	var total: int = Game.meta.get("medals", {}).size()
	medal_label.text = "%s: %d/%d" % [Game.meta.get("medal_label", {}).get("many", "Medaillen"), Game.medals.size(), total]
	_refresh_verbs()


func _refresh_verbs() -> void:
	var def := Game.object_def(hover) if hover != "" else {}
	var hint: String = def.get("default", "walk" if def.has("exit") else "look") if not def.is_empty() else ""
	for v in verb_buttons:
		var color := VERB_COLOR
		if v == verb:
			color = VERB_ACTIVE
		elif v == hint and verb == "walk":
			color = VERB_HINT
		verb_buttons[v].add_theme_color_override("font_color", color)


# --- Eingabe ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	var key := event as InputEventKey
	if event is InputEventMouseMotion:
		_update_hover()
	elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if Game.busy:
			_skip = true
	elif key and key.pressed and not key.echo:
		match key.keycode:
			KEY_PERIOD:
				_skip = true
			KEY_ESCAPE:
				if awaiting_second or verb != "walk":
					_reset_sentence()
				else:
					open_menu()
			KEY_F5:
				_toast(Game.text("saved") if Game.save_game() else Game.text("save_failed"))
			KEY_F9:
				_toast(Game.text("loaded") if Game.load_game() else Game.text("load_failed"))
			KEY_M:
				_toast(Game.text("music_on") if music.toggle_mute() else Game.text("music_off"))


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or Game.busy:
		return
	var mouse := get_global_mouse_position()
	if mouse.y >= UI_TOP:
		return
	var p := mouse / ROOM_SCALE
	var h := Game.hotspot_at(p)
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if not h.is_empty():
			_reset_sentence()
			_execute(h.get("default", "walk" if h.has("exit") else "look"), h["id"], "")
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if h.is_empty():
			_reset_sentence()
			walk_target = _clamp_walk(p)
		else:
			_click_object(h["id"])


func _on_verb_pressed(v: String) -> void:
	if Game.busy:
		return
	_reset_sentence()
	verb = v
	_update_sentence()
	_refresh_verbs()


func _on_inv_input(event: InputEvent, slot: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or Game.busy:
		return
	var idx: int = inv_scroll * INV_COLUMNS + slot
	if idx >= Game.inventory.size():
		return
	var id: String = Game.inventory[idx]
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_click_object(id)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_reset_sentence()
		_execute(Game.items.get(id, {}).get("default", "look"), id, "")


func _on_inv_hover(slot: int) -> void:
	_inv_hover = ""
	if slot >= 0:
		var idx: int = inv_scroll * INV_COLUMNS + slot
		if idx < Game.inventory.size():
			_inv_hover = Game.inventory[idx]
	_update_hover()


func _scroll_inventory(direction: int) -> void:
	inv_scroll += direction
	_refresh_ui()


func _click_object(id: String) -> void:
	if Game.busy:
		return
	if awaiting_second:
		if id == obj1:
			return
		var v := verb
		var first := obj1
		_reset_sentence()
		_execute(v, first, id)
		return
	var v := verb
	var is_item := Game.inventory.has(id)
	if v == "walk" and is_item:
		v = "use"
	if Game.TWO_OBJECT_VERBS.has(v) and is_item and not Game.items.get(id, {}).get("verbs", {}).has(v):
		verb = v
		obj1 = id
		awaiting_second = true
		_update_sentence()
		return
	_reset_sentence()
	_execute(v, id, "")


func _execute(v: String, a: String, b: String) -> void:
	walk_target = null
	await Game.do_sentence(v, a, b)
	_update_hover()


func _reset_sentence() -> void:
	verb = "walk"
	obj1 = ""
	awaiting_second = false
	_update_sentence()
	_refresh_verbs()


func _update_hover() -> void:
	var mouse := get_global_mouse_position()
	var id := ""
	if mouse.y < UI_TOP:
		var h := Game.hotspot_at(mouse / ROOM_SCALE)
		if not h.is_empty():
			id = h["id"]
	else:
		id = _inv_hover
	if id != hover:
		hover = id
		room_view.hover_id = id
		_refresh_verbs()
	_update_sentence()


func _update_sentence() -> void:
	if sentence_label == null:
		return
	var t: String = Game.VERB_NAMES[verb]
	if awaiting_second:
		t += " " + Game.object_name(obj1) + " " + Game.TWO_OBJECT_VERBS[verb]
	if hover != "" and hover != obj1:
		t += " " + Game.object_name(hover)
	sentence_label.text = t


func open_menu() -> void:
	_reset_sentence()
	menu.open()


func _toast(text: String) -> void:
	toast_label.text = text
	await get_tree().create_timer(2.0).timeout
	if toast_label.text == text:
		toast_label.text = ""


# --- Bewegung ---------------------------------------------------------------

func _process(delta: float) -> void:
	if walk_target != null:
		# weiter hinten kleiner und langsamer, damit die Schritte zur Größe passen
		var stride: float = WALK_SPEED * delta * room_view.depth_scale(Game.player_pos.y)
		var d: Vector2 = walk_target - Game.player_pos
		if abs(d.x) > 0.5:
			room_view.player_flip = d.x < 0
		if d.length() <= stride:
			Game.player_pos = walk_target
			walk_target = null
			arrived.emit()
		else:
			Game.player_pos += d.normalized() * stride
	var companion_home := _companion_home()
	var before := companion_pos
	companion_pos = companion_pos.lerp(companion_home, clampf(delta * 2.5, 0.0, 1.0))
	# fliegt er, schaut er in Flugrichtung, sonst wie die Spielfigur
	var vx := (companion_pos.x - before.x) / maxf(delta, 0.001)
	room_view.companion_flying = absf(vx) > 6.0 or (companion_pos - companion_home).length() > 3.0
	room_view.companion_flip = vx < 0 if absf(vx) > 6.0 else room_view.player_flip
	room_view.companion_floor_y = companion_pos.y + COMPANION_HOVER * room_view.depth_scale(Game.player_pos.y)
	room_view.player_pos = Game.player_pos
	room_view.player_walking = walk_target != null
	room_view.player_talking = _talking == Game.player_id
	room_view.talking_id = _talking
	var mouth := _mouth()
	room_view.player_mouth = mouth if _talking == Game.player_id else ""
	room_view.player_mood = _talk_mood if _talking == Game.player_id else ""
	room_view.companion_mouth = mouth if _talking == Game.companion_id else ""
	room_view.companion_mood = _talk_mood if _talking == Game.companion_id else ""
	room_view.companion_pos = companion_pos
	room_view.show_companion = Game.companion_id != "" and Game.check(Game.meta["companion"].get("if"))


## Platz des Begleiters: hinter der Spielfigur in der Luft, mit der Raumtiefe kleiner.
func _companion_home() -> Vector2:
	var s: float = room_view.depth_scale(Game.player_pos.y)
	return Game.player_pos + Vector2(COMPANION_BEHIND if room_view.player_flip else -COMPANION_BEHIND, -COMPANION_HOVER) * s


func _clamp_walk(p: Vector2) -> Vector2:
	var w: Array = Game.room().get("walk", [0, 100, 320, 144])
	return Vector2(clampf(p.x, w[0], w[2]), clampf(p.y, w[1], w[3]))


# --- Schnittstelle für game.gd ----------------------------------------------

func room_entered() -> void:
	walk_target = null
	room_view.set_room(Game.room())
	music.room_entered(Game.room())
	companion_pos = _companion_home()
	_update_hover()


func walk_to(p: Vector2) -> void:
	p = _clamp_walk(p)
	if Game.fast:
		Game.player_pos = p
		return
	walk_target = p
	await arrived


func walk_to_hotspot(h: Dictionary) -> void:
	await walk_to(Game.hotspot_walk_point(h))
	# zum Objekt drehen
	var r: Array = h["rect"]
	var dx: float = r[0] + r[2] / 2.0 - Game.player_pos.x
	if absf(dx) > 2.0:
		room_view.player_flip = dx < 0


## Spielt eine Aktion der Spielfigur ab und kehrt im Moment des Zugreifens zurück;
## der Rest der Aktion läuft weiter, während das Skript fortfährt.
func play_action(action: String) -> void:
	var grab: float = room_view.start_action(action)
	if grab > 0.0:
		await get_tree().create_timer(grab).timeout


## Mundform zum Zeitpunkt im laufenden Satz: der Text wird über die Sprechdauer abgefahren, in festen
## Schritten, damit der Mund nicht flackert. Kein echtes Lip-Sync, nur der Takt des Satzes.
func _mouth() -> String:
	if _talking.is_empty() or _talk_text.is_empty():
		return ""
	var talked := _talk_duration * 0.85  # am Ende schließt sich der Mund, der Text steht noch kurz
	if _talk_t >= talked:
		return "closed"
	var step := floorf(_talk_t * MOUTH_RATE) / MOUTH_RATE
	var c := _talk_text[int(step / talked * _talk_text.length())].to_lower()
	if MOUTHS.has(c):
		return MOUTHS[c]
	return "small" if c.to_upper() != c else "closed"


func say(who: String, text: String, mood := "") -> void:
	if Game.fast:
		return
	var color := Color(Game.characters.get(who, {}).get("color", "#ffffff"))
	speech_label.add_theme_color_override("font_color", color)
	speech_label.text = text
	var anchor := Vector2(320, 110)
	if who == Game.player_id:
		anchor = (Game.player_pos - Vector2(0, room_view.player_height())) * ROOM_SCALE
	elif who == Game.companion_id and room_view.show_companion:
		anchor = (companion_pos - Vector2(0, room_view.companion_height() / 2)) * ROOM_SCALE
	else:
		# Figuren im Raum sind Hotspots mit "speaker"; der Text steht über ihnen.
		for h in Game.visible_hotspots():
			if h.get("speaker", "") == who:
				var r: Array = h["rect"]
				anchor = Vector2(r[0] + r[2] / 2.0, r[1] - 4) * ROOM_SCALE
				break
	speech_label.position = Vector2(
		clampf(anchor.x - speech_label.size.x / 2, 4, 636 - speech_label.size.x),
		max(anchor.y - speech_label.size.y, 0))
	_talking = who
	_talk_text = text
	_talk_mood = mood
	_skip = false
	_talk_duration = clampf(text.length() * 0.065, 1.5, 8.0)
	_talk_t = 0.0
	while _talk_t < _talk_duration and not _skip:
		await get_tree().process_frame
		if not get_tree().paused:  # Spielmenü offen
			_talk_t += get_process_delta_time()
	_skip = false
	_talking = ""
	speech_label.text = ""


func show_title(text: String) -> void:
	if Game.fast:
		return
	title_label.text = text
	title_bg.visible = true
	_skip = false
	var t := 0.0
	while t < 4.0 and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
	_skip = false
	title_bg.visible = false


func choose(texts: Array) -> int:
	verb_panel.visible = false
	sentence_label.visible = false
	choice_box.visible = true
	for i in texts.size():
		var b := Button.new()
		b.text = texts[i]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", Color("#8a6ac8"))
		b.add_theme_color_override("font_hover_color", Color("#e0c8ff"))
		b.pressed.connect(func() -> void: choice_made.emit(i))
		choice_box.add_child(b)
	var index: int = await choice_made
	for c in choice_box.get_children():
		c.queue_free()
	choice_box.visible = false
	verb_panel.visible = true
	sentence_label.visible = true
	return index
