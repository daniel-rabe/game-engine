extends Control
## Spielmenü über dem laufenden Spiel (Esc): Weiterspielen, Spielstand
## speichern, Spielstand laden, Beenden. Hält das Spiel an, solange es offen ist.
##
## Seiten: Hauptliste, Speicherplätze (Speichern oder Laden) und eine
## Ja/Nein-Abfrage (Beenden, Überschreiben). Esc geht eine Seite zurück.
## Texte kommen aus Game.text("menu_…"), lassen sich also in game.json ersetzen.
## Hintergrund: game.json "menu": {"panel": Bild, "panel_margin": Rahmenbreite in Bildpunkten};
## das Bild wird auf die Menübreite verkleinert, nur die Mitte streckt sich (Neun-Felder-Raster).
## Ohne Bild ein schlichter dunkler Kasten.

signal closed

const GOLD := Color("#ffd27f")
const ENTRY := Color("#e8c890")
const ENTRY_HOVER := Color("#fff2c0")
const ENTRY_DISABLED := Color(0.6, 0.55, 0.45, 0.5)
const OUTLINE := Color("#1a0f08")
const PANEL_WIDTH := 340.0

var view = null  # main.gd, für Hinweise (_toast)
var _plate: NinePatchRect
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _page := ""


func _init() -> void:
	size = Vector2(640, 400)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.size = size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_panel = PanelContainer.new()
	var cfg: Dictionary = Game.meta.get("menu", {})
	var tex: Texture2D = load(cfg["panel"]) if ResourceLoader.exists(cfg.get("panel", "")) else null
	var margin := 14.0
	if tex:
		# in voller Auflösung gezeichnet und verkleinert, damit der gemalte Rahmen scharf bleibt
		var k := PANEL_WIDTH / tex.get_width()
		var m: int = cfg.get("panel_margin", 0)
		_plate = NinePatchRect.new()
		_plate.texture = tex
		_plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_plate.patch_margin_left = m
		_plate.patch_margin_right = m
		_plate.patch_margin_top = m
		_plate.patch_margin_bottom = m
		_plate.scale = Vector2(k, k)
		_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_plate)
		margin = m * k + 6
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(margin)
		_panel.add_theme_stylebox_override("panel", empty)
	else:
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color("#140d08", 0.92)
		frame.border_color = Color("#8a6a3a")
		frame.set_border_width_all(2)
		frame.set_corner_radius_all(6)
		frame.set_content_margin_all(margin)
		frame.shadow_color = Color(0, 0, 0, 0.5)
		frame.shadow_size = 8
		_panel.add_theme_stylebox_override("panel", frame)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(PANEL_WIDTH - 2 * margin, 0)
	style_title(_title, 28, menu_font())
	box.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	box.add_child(_list)


# --- Stil, auch für andere Menüs (Startbild) --------------------------------

## Serifenschrift für Titel und Menüs: game.json "fonts.title" (.ttf/.otf), sonst eine des Systems.
static func title_font() -> Font:
	var path: String = Game.meta.get("fonts", {}).get("title", "")
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "DejaVu Serif", "serif"])
	f.font_weight = 700
	return f


## Blockige Schrift fürs Spielmenü wie die Verben: game.json "fonts.menu", sonst die Oberflächenschrift, kräftiger.
static func menu_font() -> Font:
	var path: String = Game.meta.get("fonts", {}).get("menu", "")
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 0.6
	return f


## Goldene Überschrift mit dunkler Kontur und Schatten.
static func style_title(l: Label, font_size: int, font: Font = null) -> void:
	l.add_theme_font_override("font", font if font else title_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)


## Menüeintrag als schlichter Textknopf, hell beim Darüberfahren.
static func make_entry(text: String, font_size := 19, font: Font = null) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font if font else title_font())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", ENTRY)
	b.add_theme_color_override("font_hover_color", ENTRY_HOVER)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", ENTRY_DISABLED)
	b.add_theme_color_override("font_outline_color", OUTLINE)
	b.add_theme_constant_override("outline_size", 6)
	return b


# --- Öffnen und Schließen ---------------------------------------------------

func open() -> void:
	visible = true
	get_tree().paused = true
	_show_main()


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _page == "main":
			close()
		else:
			_show_main()


# --- Seiten -----------------------------------------------------------------

func _show_main() -> void:
	_page = "main"
	_begin(Game.text("menu_title"))
	_add(Game.text("menu_resume"), close)
	# mitten in einer Szene (Skript läuft) lässt sich nicht speichern oder laden
	_add(Game.text("menu_save"), _show_slots.bind(true), Game.busy or Game.room_id == "")
	_add(Game.text("menu_load"), _show_slots.bind(false), Game.busy or not Game.has_save())
	_add(Game.text("menu_quit"), _confirm.bind(Game.text("menu_quit_confirm"), get_tree().quit))
	_end()


func _show_slots(saving: bool) -> void:
	_page = "save" if saving else "load"
	_begin(Game.text("menu_save" if saving else "menu_load"))
	# Platz 0 ist der Schnellspeicher (F5): nur laden, nicht im Menü überschreiben
	for slot in range(1 if saving else 0, Game.SAVE_SLOTS):
		var info := Game.save_info(slot)
		if slot == 0 and info.is_empty():
			continue
		var b := _add(_slot_text(slot, info), _on_slot.bind(slot, saving, info.is_empty()), not saving and info.is_empty(), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_add(Game.text("menu_back"), _show_main, false, 17)
	_end()


func _slot_text(slot: int, info: Dictionary) -> String:
	var label := Game.text("slot_quick") if slot == 0 else str(slot)
	if info.is_empty():
		return "%s   %s" % [label, Game.text("slot_empty")]
	var t := ""
	if info["time"] > 0:
		var d := Time.get_datetime_dict_from_unix_time(info["time"] + _utc_offset())
		t = "  ·  %02d.%02d. %02d:%02d" % [d["day"], d["month"], d["hour"], d["minute"]]
	return "%s   %s%s" % [label, info["room_name"], t]


func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _on_slot(slot: int, saving: bool, empty: bool) -> void:
	if not saving:
		_finish(Game.load_game(slot), "loaded", "load_failed")
	elif empty:
		_finish(Game.save_game(slot), "saved", "save_failed")
	else:
		_confirm(Game.text("menu_overwrite"), func() -> void: _finish(Game.save_game(slot), "saved", "save_failed"),
			_show_slots.bind(true))


func _finish(ok: bool, ok_text: String, fail_text: String) -> void:
	close()
	if view:
		view._toast(Game.text(ok_text if ok else fail_text))


## Ja/Nein-Abfrage; Nein (oder Esc) führt zurück.
func _confirm(question: String, yes: Callable, no := Callable()) -> void:
	_page = "confirm"
	_begin(question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	_list.add_child(row)
	var y := make_entry(Game.text("menu_yes"), 20, menu_font())
	y.pressed.connect(yes)
	row.add_child(y)
	var n := make_entry(Game.text("menu_no"), 20, menu_font())
	n.pressed.connect(no if no.is_valid() else _show_main)
	row.add_child(n)
	_end()


func _begin(title: String) -> void:
	_title.text = title
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()


func _add(text: String, action: Callable, disabled := false, font_size := 19) -> Button:
	var b := make_entry(text, font_size, menu_font())
	b.disabled = disabled
	b.pressed.connect(action)
	_list.add_child(b)
	return b


## Rahmen an den Inhalt anpassen und mittig stellen.
func _end() -> void:
	_panel.size = Vector2(PANEL_WIDTH, 0)
	_panel.reset_size()
	_panel.size.x = PANEL_WIDTH
	_panel.position = ((size - _panel.get_combined_minimum_size()) / 2).floor()
	_panel.position.x = (size.x - PANEL_WIDTH) / 2
	if _plate:
		_plate.position = _panel.position
		_plate.size = _panel.size / _plate.scale
