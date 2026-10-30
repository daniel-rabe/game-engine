extends Node
## Eigener Mauszeiger aus game.json "cursor", mit zweitem Bild, solange die Maus
## über einem Objekt (Hotspot im Raum oder Gegenstand im Inventar) steht:
## {"normal": "res://art/ui/cursor.png", "hover": "res://art/ui/cursor_hover.png",
##  "hotspot": [x, y], "size": 16}
## "hotspot" ist der Klickpunkt in Bildpunkten des Bildes, "size" die Höhe in
## Spielpixeln (640x400). Der Zeiger wächst mit dem Fenster (F11, Vollbild) und
## wird dafür neu gerechnet, weil das System ihn sonst in Bildschirmpixeln zeigt.
## Ohne Eintrag oder auf Touchgeräten bleibt der Systemzeiger.

const BASE := Vector2(640, 400)
const MAX_PIXELS := 256  # größer nimmt Godot keine Zeiger an

var view = null  # main.gd
var _cfg := {}
var _images := {}  # "normal"/"hover" -> Image in Originalgröße
var _hover := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # auch im Spielmenü
	_cfg = Game.meta.get("cursor", {})
	if _cfg.is_empty() or OS.has_feature("mobile"):
		set_process(false)
		return
	for key in ["normal", "hover"]:
		var path: String = _cfg.get(key, "")
		if path != "" and ResourceLoader.exists(path):
			_images[key] = (load(path) as Texture2D).get_image()
	if not _images.has("normal"):
		set_process(false)
		return
	get_tree().root.size_changed.connect(_apply)
	_apply()


func _process(_delta: float) -> void:
	var h := _wants_hover()
	if h != _hover:
		_hover = h
		_apply()


func _wants_hover() -> bool:
	if view == null or Game.busy or view.start_screen or view.menu.visible:
		return false
	return view.hover != ""


func _apply() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var stretch := minf(win.x / BASE.x, win.y / BASE.y)
	var key := "hover" if _hover and _images.has("hover") else "normal"
	var src: Image = _images[key]
	var px := clampi(roundi(float(_cfg.get("size", 16)) * stretch), 8, MAX_PIXELS)
	var f := float(px) / src.get_height()
	var img := src.duplicate() as Image
	img.resize(maxi(1, roundi(src.get_width() * f)), px, Image.INTERPOLATE_LANCZOS)
	var hs: Array = _cfg.get("hotspot", [0, 0])
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), Input.CURSOR_ARROW, Vector2(hs[0], hs[1]) * f)
