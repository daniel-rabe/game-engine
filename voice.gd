extends Node
## Sprachausgabe: gesprochene Fassung einer Textzeile, solange sie auf dem Schirm steht.
##
## game.json "voice": {"speakers": ["text"], "dir" (Standard res://voice), "volume_db",
## "duck_db" (so viel leiser wird die Musik, Standard -8), "duck_fade"}.
## Die Aufnahme einer Zeile liegt als <dir>/<sprecher>/<schlüssel>.ogg; der Schlüssel sind
## die ersten 12 Zeichen des MD5 des Spieltexts. Ändert sich der Text, fehlt die Aufnahme und
## die Zeile bleibt stumm. Läuft im Bus "Voice"; die Musik (Bus "Music") wird dabei leiser.

const BUS := "Voice"
const MUSIC_BUS := "Music"

var _player: AudioStreamPlayer
var _tween: Tween
var _music_db := 0.0
var _ducked := false


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	add_child(_player)
	var m := AudioServer.get_bus_index(MUSIC_BUS)
	if m >= 0:
		_music_db = AudioServer.get_bus_volume_db(m)


func _settings() -> Dictionary:
	return Game.meta.get("voice", {})


static func key(text: String) -> String:
	return text.md5_text().substr(0, 12)


## Spielt die Aufnahme der Zeile und gibt ihre Länge in Sekunden zurück (0: keine Aufnahme).
func play(who: String, text: String) -> float:
	stop()
	var cfg := _settings()
	if not who in cfg.get("speakers", []):
		return 0.0
	var path := "%s/%s/%s.ogg" % [str(cfg.get("dir", "res://voice")).trim_suffix("/"), who, key(text)]
	if not ResourceLoader.exists(path):
		return 0.0
	var s: AudioStream = load(path)
	_player.stream = s
	_player.volume_db = cfg.get("volume_db", 0.0)
	_player.play()
	_duck(true)
	return s.get_length()


## Bricht die Aufnahme ab; die Musik wird kurz danach wieder lauter (zwischen zwei Zeilen nicht).
func stop() -> void:
	_player.stop()
	if _ducked:
		_duck(false)


func _duck(on: bool) -> void:
	var m := AudioServer.get_bus_index(MUSIC_BUS)
	if m < 0:
		return
	var cfg := _settings()
	var target: float = _music_db + (cfg.get("duck_db", -8.0) if on else 0.0)
	_ducked = on
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if not on:
		_tween.tween_interval(0.3)
	_tween.tween_method(func(v: float): AudioServer.set_bus_volume_db(m, v),
			AudioServer.get_bus_volume_db(m), target, cfg.get("duck_fade", 0.4))
