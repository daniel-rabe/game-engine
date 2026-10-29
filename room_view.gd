extends Node2D
## Zeichnet den aktuellen Raum in Raumkoordinaten (320 x 144) samt Figuren.
##
## Grafiken werden per Dateikonvention gesucht (siehe docs/assets.md). Fehlt eine
## Datei, zeichnet die View einen Platzhalter, sodass das Spiel ohne jede Grafik
## spielbar bleibt und ComfyUI-Ergebnisse einfach in art/ gelegt werden können.
##
## Hintergründe und Objektbilder dürfen größer sein als ihr Platz in Raumkoordinaten
## (z. B. 1280 x 576 für einen 4-fach gemalten Raum). Sie werden in ihr Rechteck
## gestreckt und auf einer eigenen Ebene mit linearer Filterung gezeichnet, damit
## gemalte Bilder nicht verpixeln. Bilder in Originalgröße bleiben pixelgenau.
## Für Figuren gilt dasselbe: Bilder höher als die Figurengröße aus game.json sind
## 4-fach gemalt und werden mit einem Viertel ihrer Größe auf dieser Ebene gezeichnet.

const ROOM_SIZE := Vector2(320, 144)
const HIRES_SCALE := 4.0  # gemalte Hintergründe, Objekte und Figuren sind 4-fach
const PLAYER_COLORS := {
	"legs": "#7a1c1c", "shoes": "#2a2a2a", "body": "#c0392b", "shirt": "#e8e0d0",
	"skin": "#e8c19a", "hair": "#5a2e14", "accent": "#5fb0c0", "mouth": "#5a1010",
}
const COMPANION_COLORS := {"body": "#9aa6b2", "light": "#ff5050", "eye_bg": "#0a1a2a", "eye": "#66ddff"}

var room: Dictionary = {}
var player_pos := Vector2.ZERO
var player_walking := false
var player_flip := false
var player_talking := false
## Mundform beim Sprechen ("" = spricht nicht) und Stimmung ("" = ruhig, sonst z. B. "happy"), aus main.gd
var player_mouth := ""
var player_mood := ""
var companion_mouth := ""
var companion_mood := ""
var companion_pos := Vector2.ZERO
var show_companion := false
var companion_flying := false
var companion_flip := false
var companion_floor_y := 0.0  # Boden unter dem Begleiter (für den Schatten)
var hover_id := ""

var _time := 0.0
var _action: Array = []  # Bilder einer laufenden Aktion (z. B. pickup_N.png)
var _action_t0 := 0.0
var _action_fps := 15.0
var _bg: Texture2D = null
var _textures := {}
var _hires: Node2D = null  # Ebene unter allem anderen für hochaufgelöste Bilder


func _ready() -> void:
	_hires = Node2D.new()
	_hires.show_behind_parent = true
	_hires.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_hires.draw.connect(_draw_hires)
	add_child(_hires)


func set_room(r: Dictionary) -> void:
	room = r
	_bg = texture("res://art/rooms/%s.png" % r.get("id", ""))
	queue_redraw()


## Lädt eine Textur einmal und merkt sich auch, wenn sie fehlt.
func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	_hires.queue_redraw()


## Größer als sein Platz in Raumkoordinaten, also auf der linear gefilterten Ebene.
func _is_hires(tex: Texture2D, size: Vector2) -> bool:
	return tex.get_width() > size.x or tex.get_height() > size.y


func _draw_hires() -> void:
	if _bg and _is_hires(_bg, ROOM_SIZE):
		_hires.draw_texture_rect(_bg, Rect2(Vector2.ZERO, ROOM_SIZE), false)
	# Objekte, deren Fußlinie (Unterkante oder "baseline") vor der Figur liegt, verdecken sie
	var front := []
	for h in Game.visible_hotspots():
		var tex := _object_texture(h)
		var rect := _rect(h)
		if tex and _is_hires(tex, rect.size):
			if h.get("baseline", rect.end.y) > player_pos.y:
				front.append([tex, rect])
			else:
				_hires.draw_texture_rect(tex, rect, false)
	# der Begleiter schwebt hinter der Spielfigur, also vor ihr gezeichnet
	var cf := _companion_frame() if show_companion else null
	if cf and _actor_is_hires(Game.companion_id, cf):
		_draw_companion_hires(cf)
	var pf := _player_frame()
	if pf and _actor_is_hires(Game.player_id, pf):
		# weicher Schatten unter den Füßen, damit die gemalte Figur auf dem Boden steht
		_hires.draw_set_transform(player_pos, 0.0, Vector2(1.0, 0.22) * depth_scale(player_pos.y))
		for i in 4:
			_hires.draw_circle(Vector2.ZERO, 15.0 - i * 3.0, Color(0, 0, 0, 0.12))
		_hires.draw_set_transform(Vector2.ZERO)
		_draw_actor_frame(_hires, pf, pf.get_size() / HIRES_SCALE)
	for f in front:
		_hires.draw_texture_rect(f[0], f[1], false)


func _draw() -> void:
	if _bg:
		if not _is_hires(_bg, ROOM_SIZE):
			draw_texture(_bg, Vector2.ZERO)
	else:
		_draw_placeholder_room()
	for h in Game.visible_hotspots():
		_draw_hotspot(h)
	_draw_player()
	if show_companion:
		_draw_companion()


func _draw_placeholder_room() -> void:
	var bg: Dictionary = room.get("bg", {})
	var floor_y: float = bg.get("floor_y", 100)
	draw_rect(Rect2(0, 0, ROOM_SIZE.x, floor_y), Color(bg.get("wall", "#2a3040")))
	draw_rect(Rect2(0, floor_y, ROOM_SIZE.x, ROOM_SIZE.y - floor_y), Color(bg.get("floor", "#1a1e28")))
	if bg.get("stars", false):
		_draw_stars(Rect2(0, 0, ROOM_SIZE.x, floor_y))
	for d in room.get("decor", []):
		var r: Array = d["rect"]
		var rect := Rect2(r[0], r[1], r[2], r[3])
		draw_rect(rect, Color(d.get("color", "#444444")))
		if d.get("stars", false):
			_draw_stars(rect)


func _draw_stars(area: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in 90:
		var p := Vector2(rng.randf_range(0, ROOM_SIZE.x), rng.randf_range(0, ROOM_SIZE.y))
		if area.has_point(p):
			var c := Color(1, 1, 1, rng.randf_range(0.3, 1.0))
			draw_rect(Rect2(p.floor(), Vector2.ONE), c)


func _rect(h: Dictionary) -> Rect2:
	var r: Array = h["rect"]
	return Rect2(r[0], r[1], r[2], r[3])


## Eigene Objektgrafik (art/objects/<raum>/<hotspot>[_<variante>].png) oder null.
func _object_texture(h: Dictionary) -> Texture2D:
	var suffix: String = Game.pick_variant(h.get("art_variants", {}), "")
	var file_name: String = h["id"] + ("_" + suffix if suffix != "" else "")
	return texture("res://art/objects/%s/%s.png" % [room.get("id", ""), file_name])


func _draw_hotspot(h: Dictionary) -> void:
	var rect := _rect(h)
	var tex := _object_texture(h)
	if tex:
		if not _is_hires(tex, rect.size):
			draw_texture(tex, rect.position)
		return
	# Mit gemaltem Hintergrund sind feste Objekte schon im Bild.
	if (_bg and not h.get("sprite", false)) or not h.get("placeholder", true):
		return
	var c := Color(Game.pick_variant(h.get("color_variants", {}), h.get("color", "#6a7a8a")))
	if h.has("speaker"):
		_draw_placeholder_person(rect, c, h["id"] == hover_id)
		return
	draw_rect(rect, c)
	var edge := c.lightened(0.5) if h["id"] == hover_id else c.darkened(0.45)
	draw_rect(rect, edge, false, 1.0)


## Platzhalter für Figuren im Raum: Kopf, Körper und Beine im Hotspot-Rechteck.
func _draw_placeholder_person(rect: Rect2, c: Color, hovered: bool) -> void:
	var head := minf(rect.size.x * 0.6, rect.size.y * 0.28)
	var cx := rect.position.x + rect.size.x / 2
	var top := rect.position.y
	var body_h := (rect.size.y - head) * 0.6
	draw_rect(Rect2(cx - head / 2, top, head, head), Color("#d8b090"))
	draw_rect(Rect2(cx - head / 2, top, head, 2), c.darkened(0.5))
	draw_rect(Rect2(rect.position.x + 1, top + head, rect.size.x - 2, body_h), c)
	var legs_y := top + head + body_h
	var leg_w := maxf((rect.size.x - 6) / 2, 2)
	draw_rect(Rect2(cx - leg_w - 1, legs_y, leg_w, rect.end.y - legs_y), c.darkened(0.4))
	draw_rect(Rect2(cx + 1, legs_y, leg_w, rect.end.y - legs_y), c.darkened(0.4))
	if hovered:
		draw_rect(rect, c.lightened(0.5), false, 1.0)


func _draw_player() -> void:
	var tex := _player_frame()
	if tex:
		if not _actor_is_hires(Game.player_id, tex):
			_draw_actor_frame(self, tex, tex.get_size())
		return
	# Platzhalterfigur; Farben aus game.json "player.placeholder".
	var pc := _placeholder_colors("player", PLAYER_COLORS)
	var x := player_pos.x
	var y := player_pos.y
	var step := sin(_time * 14.0) * 2.0 if player_walking else 0.0
	draw_rect(Rect2(x - 5, y - 14 + max(step, 0), 4, 14 - max(step, 0)), pc["legs"])
	draw_rect(Rect2(x + 1, y - 14 + max(-step, 0), 4, 14 - max(-step, 0)), pc["legs"])
	draw_rect(Rect2(x - 6, y - 2, 5, 2), pc["shoes"])
	draw_rect(Rect2(x + 1, y - 2, 5, 2), pc["shoes"])
	draw_rect(Rect2(x - 6, y - 32, 12, 19), pc["body"])
	draw_rect(Rect2(x - 4, y - 31, 8, 4), pc["shirt"])
	draw_rect(Rect2(x - 8, y - 31, 2, 12), pc["skin"])
	draw_rect(Rect2(x + 6, y - 31, 2, 12), pc["skin"])
	draw_rect(Rect2(x - 4, y - 41, 8, 9), pc["skin"])
	draw_rect(Rect2(x - 5, y - 43, 10, 3), pc["hair"])
	draw_rect(Rect2(x - 5, y - 41, 2, 8), pc["hair"])
	draw_rect(Rect2(x - 4, y - 45, 8, 2), pc["accent"])
	if player_talking and int(_time * 8) % 2 == 0:
		draw_rect(Rect2(x - 1, y - 34, 2, 1), pc["mouth"])


func _draw_companion() -> void:
	var p := companion_pos + Vector2(0, sin(_time * 3.0) * 2.0)
	var tex := _companion_frame()
	if tex:
		if not _actor_is_hires(Game.companion_id, tex):
			draw_texture(tex, p - tex.get_size() / 2)
		return
	var cc := _placeholder_colors("companion", COMPANION_COLORS)
	draw_line(p + Vector2(0, -5), p + Vector2(0, -9), cc["body"])
	draw_circle(p + Vector2(0, -9), 1.0, cc["light"])
	draw_circle(p, 5.0, cc["body"])
	draw_circle(p + Vector2(1, -1), 2.0, cc["eye_bg"])
	draw_circle(p + Vector2(1, -1), 1.2, cc["eye"])


## Aktuelles Bild des Begleiters: walk_N im Flug, sonst idle_N (oder stand.png); null ohne Bilder.
func _companion_frame() -> Texture2D:
	var frames := _actor_frames(Game.companion_id)
	if frames.is_empty():
		return null
	var cfg := _actor_cfg(Game.companion_id)
	var walk: Array = frames.slice(1)
	if companion_flying and not walk.is_empty():
		return walk[int(_time * cfg.get("walk_fps", 8)) % walk.size()]
	var idle := _actor_idle(Game.companion_id)
	if not idle.is_empty():
		var i := int(_time * cfg.get("idle_fps", 8))
		return _talk_frame(Game.companion_id, companion_mood, companion_mouth, i, idle[i % idle.size()])
	return frames[0]


## 4-fach gemalter Begleiter: Bildmitte auf companion_pos, mit der Tiefe skaliert, Schwebebewegung im Bild
## selbst; ein blasser Schatten auf dem Boden darunter.
func _draw_companion_hires(tex: Texture2D) -> void:
	var s := depth_scale(player_pos.y)
	_hires.draw_set_transform(Vector2(companion_pos.x, companion_floor_y), 0.0, Vector2(1.0, 0.25) * s)
	for i in 3:
		_hires.draw_circle(Vector2.ZERO, 10.0 - i * 2.5, Color(0, 0, 0, 0.1))
	_hires.draw_set_transform(Vector2.ZERO)
	var size := tex.get_size() / HIRES_SCALE * s
	_draw_mirrored(_hires, tex, Rect2(companion_pos - size / 2, size), companion_flip)


## Höhe des Begleiters in Raumkoordinaten (für Sprechtexte).
func companion_height() -> float:
	var tex := _companion_frame()
	if tex == null:
		return 20.0
	var hires := _actor_is_hires(Game.companion_id, tex)
	return tex.get_height() / (HIRES_SCALE if hires else 1.0) * (depth_scale(player_pos.y) if hires else 1.0)


## Aktuelles Bild der Spielfigur: Laufbilder beim Gehen, sonst idle_N (oder stand.png).
func _player_frame() -> Texture2D:
	var frames := _actor_frames(Game.player_id)
	if frames.is_empty():
		return null
	var cfg := _actor_cfg(Game.player_id)
	if not _action.is_empty():
		var a := int((_time - _action_t0) * _action_fps)
		if a < _action.size():
			return _action[a]
		_action = []
	var walk: Array = frames.slice(1)
	if player_walking and not walk.is_empty():
		return walk[int(_time * cfg.get("walk_fps", 8)) % walk.size()]
	var idle := _actor_idle(Game.player_id)
	if not idle.is_empty():
		var i := int(_time * cfg.get("idle_fps", 8))
		return _talk_frame(Game.player_id, player_mood, player_mouth, i, idle[i % idle.size()])
	return frames[0]


## Ersatz, wenn eine Figur eine Mundform nicht hat (zuletzt die geschlossene, also das Ruhebild).
const MOUTH_FALLBACK := {"o": ["small", "open"], "e": ["small", "open"], "small": ["open"], "open": ["small"]}


## Sprechbild zum Ruhebild Nummer i: <stimmung>_<mund>_<i>.png mit der Stimmung "talk" (ruhig) oder z. B.
## "happy"; der Körper bewegt sich also weiter wie im Ruhebild. Ruhig und geschlossen ist das Ruhebild selbst.
func _talk_frame(actor: String, mood: String, mouth: String, i: int, idle: Texture2D) -> Texture2D:
	if mouth.is_empty():
		if mood.is_empty():
			return idle
		mouth = "closed"
	var prefix := "talk" if mood.is_empty() else mood
	for m in [mouth] + MOUTH_FALLBACK.get(mouth, []) + ["closed"]:
		var frames := _actor_numbered(actor, "%s_%s" % [prefix, m])
		if not frames.is_empty():
			return frames[i % frames.size()]
	return idle


## Größenfaktor der Figur an Höhe y: Raumfeld "depth" {"y": [hinten, vorn], "scale": [hinten, vorn]},
## dazwischen linear, außerhalb festgehalten. Ohne "depth" immer 1.
func depth_scale(y: float) -> float:
	var d: Dictionary = room.get("depth", {})
	if d.is_empty():
		return 1.0
	var ys: Array = d["y"]
	var sc: Array = d["scale"]
	var t := clampf(inverse_lerp(ys[0], ys[1], y), 0.0, 1.0)
	return lerpf(sc[0], sc[1], t)


## Fußpunkt unten mittig; nach links gespiegelt; mit der Tiefe skaliert.
func _draw_actor_frame(canvas: CanvasItem, tex: Texture2D, size: Vector2) -> void:
	size *= depth_scale(player_pos.y)
	_draw_mirrored(canvas, tex, Rect2(player_pos - Vector2(size.x / 2, size.y), size), player_flip)


## Zeichnet tex in rect, mit flip an der senkrechten Mittellinie von rect gespiegelt (für den Weg nach links).
## Eine negative Rechteckbreite spiegelt in Godot zwar das Bild, verschiebt es aber um eine Breite.
func _draw_mirrored(canvas: CanvasItem, tex: Texture2D, rect: Rect2, flip: bool) -> void:
	if flip:
		canvas.draw_set_transform(Vector2(rect.get_center().x * 2, 0), 0.0, Vector2(-1, 1))
	canvas.draw_texture_rect(tex, rect, false)
	if flip:
		canvas.draw_set_transform(Vector2.ZERO)


func _actor_cfg(actor: String) -> Dictionary:
	return Game.meta.get("art", {}).get("actors", {}).get(actor, {})


## Höher als die Figurengröße aus game.json: 4-fach gemalt.
func _actor_is_hires(actor: String, tex: Texture2D) -> bool:
	var size: Array = _actor_cfg(actor).get("size", [32, 48])
	return tex.get_height() > size[1]


## Höhe der Spielfigur in Raumkoordinaten (für Sprechtexte).
func player_height() -> float:
	var tex := _player_frame()
	if tex == null:
		return 48.0
	var h := tex.get_height() / (HIRES_SCALE if _actor_is_hires(Game.player_id, tex) else 1.0)
	return h * depth_scale(player_pos.y)


## Platzhalterfarben einer Figur: Vorgaben, überschrieben aus game.json.
func _placeholder_colors(who: String, defaults: Dictionary) -> Dictionary:
	var key := "colors:" + who
	if not _textures.has(key):
		var custom: Dictionary = Game.meta.get(who, {}).get("placeholder", {})
		var out := {}
		for k in defaults:
			out[k] = Color(custom.get(k, defaults[k]))
		_textures[key] = out
	return _textures[key]


## Spielt die Aktion <name>_0.png, <name>_1.png, ... der Spielfigur einmal ab. Gibt die Sekunden
## bis zum Bild "grab" aus game.json zurück (art.actors.<id>.actions.<name>), oder -1 ohne Bilder.
func start_action(action: String) -> float:
	var frames := _actor_numbered(Game.player_id, action)
	if frames.is_empty():
		return -1.0
	var cfg: Dictionary = _actor_cfg(Game.player_id).get("actions", {}).get(action, {})
	_action = frames
	_action_t0 = _time
	_action_fps = cfg.get("fps", 15)
	return cfg.get("grab", frames.size()) / _action_fps


func _actor_numbered(actor: String, prefix: String) -> Array:
	var key := prefix + ":" + actor
	if not _textures.has(key):
		var frames := []
		while true:
			var t := texture("res://art/actors/%s/%s_%d.png" % [actor, prefix, frames.size()])
			if t == null:
				break
			frames.append(t)
		_textures[key] = frames
	return _textures[key]


## Ruhebilder einer Figur: idle_0.png, idle_1.png, ... (leer, wenn es keine gibt).
func _actor_idle(actor: String) -> Array:
	return _actor_numbered(actor, "idle")


## Bilder einer Figur: stand.png, dann walk_0.png, walk_1.png, ...
func _actor_frames(actor: String) -> Array:
	var key := "frames:" + actor
	if not _textures.has(key):
		var frames := []
		var stand := texture("res://art/actors/%s/stand.png" % actor)
		if stand:
			frames.append(stand)
			var i := 0
			while true:
				var t := texture("res://art/actors/%s/walk_%d.png" % [actor, i])
				if t == null:
					break
				frames.append(t)
				i += 1
		_textures[key] = frames
	return _textures[key]
