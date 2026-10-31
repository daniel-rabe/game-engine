extends Node
## Hintergrundmusik: ein Stück pro Raum, Überblenden beim Raumwechsel.
##
## Welches Stück läuft, steht in den Daten: Raumfeld "music", sonst
## game.json "music.acts" nach dem Feld "act" des Raums, sonst "music.default".
## Die Dateien liegen als <dir>/<stück>.ogg (Standard res://music/) und laufen
## als Schleife. Fehlt eine Datei, blendet die Musik aus. Läuft das gewünschte
## Stück schon, spielt es einfach weiter. Taste M schaltet die Musik stumm.

const BUS := "Music"
const SILENT_DB := -60.0

var track := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _streams := {}
var _tween: Tween


func _ready() -> void:
	Game.audio_bus(BUS)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)


func _settings() -> Dictionary:
	return Game.meta.get("music", {})


## Das Stück, das im Raum r laufen soll, oder "".
func track_for(r: Dictionary) -> String:
	if r.has("music"):
		return r["music"]
	var cfg := _settings()
	return cfg.get("acts", {}).get(str(int(r.get("act", 0))), cfg.get("default", ""))


func room_entered(r: Dictionary) -> void:
	play(track_for(r))


func toggle_mute() -> bool:
	var i := Game.audio_bus(BUS)
	AudioServer.set_bus_mute(i, not AudioServer.is_bus_mute(i))
	return not AudioServer.is_bus_mute(i)


## Blendet vom laufenden Stück zu `name` über ("" = Stille).
func play(name: String) -> void:
	if name == track:
		return
	track = name
	var cfg := _settings()
	var fade: float = cfg.get("fade", 2.5)
	var old := _players[_active]
	var stream := _stream(name)
	if _tween:
		_tween.kill()
	var tw := create_tween().set_parallel()
	_tween = tw
	if stream:
		_active = 1 - _active
		var new := _players[_active]
		new.stop()
		new.stream = stream
		new.volume_db = SILENT_DB
		new.play()
		var target: float = cfg.get("volume_db", -8.0) + cfg.get("track_db", {}).get(name, 0.0)
		tw.tween_property(new, "volume_db", target, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if old.playing:
		tw.tween_property(old, "volume_db", SILENT_DB, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(old.stop)


func _stream(name: String) -> AudioStream:
	if name == "":
		return null
	if not _streams.has(name):
		var path := "%s/%s.ogg" % [str(_settings().get("dir", "res://music")).trim_suffix("/"), name]
		var s: AudioStreamOggVorbis = load(path) if ResourceLoader.exists(path) else null
		if s:
			s.loop = true
		_streams[name] = s
	return _streams[name]
