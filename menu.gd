extends Control
## Spielmenü über dem laufenden Spiel (Esc): Weiterspielen, Spielstand
## speichern, Spielstand laden, Optionen, Beenden. Hält das Spiel an, solange es offen ist.
##
## Seiten: Hauptliste, Speicherplätze (Speichern oder Laden), Optionen (Lautstärke
## je Bus aus Game.VOLUME_BUSES) und eine Ja/Nein-Abfrage (Beenden, Überschreiben).
## Esc geht eine Seite zurück. Vom Startbild aus öffnet open("options") nur die Optionen.
## Texte kommen aus Game.text("menu_…"), lassen sich also in game.json ersetzen.
## Hintergrund: game.json "menu": {"panel": Bild, "panel_margin": Rahmenbreite in Bildpunkten};
## das Bild wird auf die Menübreite verkleinert, nur die Mitte streckt sich (Neun-Felder-Raster).
## Ohne Bild ein schlichter dunkler Kasten.
## Das Menü wächst mit dem Fenster nur bis "max_scale" (game.json "menu", Standard 2,
## also so groß wie bei einem 1280x800-Fenster); in größeren Fenstern bleibt es so groß.

signal closed

const GOLD := Color("#ffd27f")
const ENTRY := Color("#e8c890")
const ENTRY_HOVER := Color("#fff2c0")
const ENTRY_DISABLED := Color(0.6, 0.55, 0.45, 0.5)
const OUTLINE := Color("#1a0f08")
const PANEL_WIDTH := 340.0
const MAX_SCALE := 2.0

var view = null  # main.gd, für Hinweise (_toast)
var _frame: Control  # hält Bild und Kasten, wird in großen Fenstern verkleinert
var _plate: NinePatchRect
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _page := ""
var _only_options := false  # vom Startbild geöffnet: Zurück schließt das Menü


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

	_frame = Control.new()
	_frame.size = size
	_frame.pivot_offset = size / 2
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
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
		_frame.add_child(_plate)
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
	_frame.add_child(_panel)
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

func open(page := "main") -> void:
	_fit_window()
	get_parent().move_child(self, -1)  # auch über dem Startbild
	visible = true
	get_tree().paused = true
	_only_options = page == "options"
	if _only_options:
		_show_options()
	else:
		_show_main()


## Verkleinert das Menü, sobald das Fenster es über max_scale hinaus vergrößern würde.
func _fit_window() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var stretch := minf(win.x / size.x, win.y / size.y)
	var cap: float = Game.meta.get("menu", {}).get("max_scale", MAX_SCALE)
	var f := minf(1.0, cap / stretch) if stretch > 0 else 1.0
	_frame.scale = Vector2(f, f)


func _ready() -> void:
	get_tree().root.size_changed.connect(_fit_window)


func close() -> void:
	if _page == "options":
		Game.save_settings()
	visible = false
	get_tree().paused = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _page == "main" or (_only_options and _page == "options"):
			close()
		else:
			_back()


# --- Seiten -----------------------------------------------------------------

func _show_main() -> void:
	_page = "main"
	_begin(Game.text("menu_title"))
	_add(Game.text("menu_resume"), close)
	# mitten in einer Szene (Skript läuft) lässt sich nicht speichern oder laden
	_add(Game.text("menu_save"), _show_slots.bind(true), Game.busy or Game.room_id == "")
	_add(Game.text("menu_load"), _show_slots.bind(false), Game.busy or not Game.has_save())
	_add(Game.text("menu_options"), _show_options)
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


## Lautstärkeregler; die Busse hört man sofort, gespeichert wird beim Verlassen der Seite.
func _show_options() -> void:
	_page = "options"
	_begin(Game.text("menu_options"))
	var width := _title.custom_minimum_size.x
	for bus in Game.VOLUME_BUSES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var name := _small_label(Game.text("volume_" + bus), 17, ENTRY)
		name.custom_minimum_size.x = width * 0.36
		row.add_child(name)
		var pct := _small_label("", 15, ENTRY)
		pct.custom_minimum_size.x = 40
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var slider := make_slider()
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value = Game.volume.get(bus, 1.0)
		pct.text = "%d %%" % roundi(slider.value * 100)
		slider.value_changed.connect(func(v: float) -> void:
			Game.set_volume(bus, v, false)
			pct.text = "%d %%" % roundi(v * 100))
		row.add_child(slider)
		row.add_child(pct)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	_list.add_child(gap)
	_add(Game.text("menu_back"), _back, false, 17)
	_end()


## Zurück zur Hauptliste (vom Startbild aus: Menü schließen).
func _back() -> void:
	if _page == "options":
		Game.save_settings()
	if _only_options:
		close()
	else:
		_show_main()


func _small_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", menu_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", 5)
	return l


## Regler von 0 bis 1 im Menüstil: dunkle Rille, goldene Füllung, runder Knopf.
static func make_slider() -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size.y = 22
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color("#1a0f08", 0.9)
	groove.border_color = Color("#8a6a3a")
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(3)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#c89a4a")
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	var hot: StyleBoxFlat = fill.duplicate()
	hot.bg_color = GOLD
	s.add_theme_stylebox_override("grabber_area_highlight", hot)
	s.add_theme_icon_override("grabber", _knob(ENTRY))
	s.add_theme_icon_override("grabber_highlight", _knob(ENTRY_HOVER))
	return s


static func _knob(color: Color) -> ImageTexture:
	var n := 14
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c + 0.5 - d, 0.0, 1.0)
			var px := color if d < c - 1.5 else OUTLINE
			img.set_pixel(x, y, Color(px, a))
	return ImageTexture.create_from_image(img)


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
