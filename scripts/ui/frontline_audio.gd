extends Node
signal sound_played(key: String)
signal custom_music_notice(text: String)
## Client-only presentation service. Created by main, compatible with PCK updates.
const CONFIG := "user://audio.cfg"
const SOUNDS := ["click","open","close","card","draw","deploy","move","attack","damage","death","counter","order","heal","turn","victory","defeat"]
const DEFAULTS := {"master":0.8,"music":0.32,"effects":0.7,"muted":false,"background_mute":true,"animations":true}
## Player-chosen local music. Files are only read from this computer; nothing is uploaded or sent to the opponent.
const CUSTOM_DEFAULTS := {"custom_music_dir":"","custom_music_scope":"both"}
const CUSTOM_SCOPES := ["both","menu","battle"]
const CUSTOM_EXTENSIONS := ["mp3","ogg","wav"]
const CUSTOM_SCAN_LIMIT := 500
var preferences: Dictionary = _all_defaults()
var enabled := DisplayServer.get_name() != "headless"
var config_path := CONFIG
var scene := ""
var field_music := ""
var music_revision := 0
var suspended := false
var music_players: Array[AudioStreamPlayer] = []
var voices: Array[AudioStreamPlayer] = []
var gains := [0.0,0.0]
var targets := [0.0,0.0]
var tracks: Dictionary = {}
var sounds: Dictionary = {}
var cooldowns: Dictionary = {}
var _voice := 0
var _music_slot := 0
var _save_due := -1.0
var custom_playlist: Array[String] = []
var custom_order: Array[String] = []
var custom_failed: Dictionary = {}
var custom_current := ""
var custom_active := false
var custom_notice := ""
var _custom_scanned := false
var _custom_scanned_dir := ""

static func _all_defaults() -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate()
	result.merge(CUSTOM_DEFAULTS)
	return result

static func service(context: Node) -> Node:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	return context.get_tree().get_first_node_in_group("frontline_audio")

static func cue(context: Node, key: String) -> void:
	var manager := service(context)
	if manager != null: manager.sound(key)

static func reveal(context: Node, control: Control) -> void:
	var manager := service(context)
	if manager != null: manager.fade_in(control)

func _ready() -> void:
	add_to_group("frontline_audio")
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_preferences()
	for key in SOUNDS: sounds[key] = load("res://assets/audio/"+key+".ogg")
	for key in ["menu","battle"]: tracks[key] = load("res://assets/audio/"+key+".ogg")
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.volume_db = -80
		add_child(player)
		music_players.append(player)
	for i in 10:
		var player := AudioStreamPlayer.new()
		add_child(player)
		voices.append(player)
	get_tree().node_added.connect(_node_added)
	for node in get_parent().find_children("*", "BaseButton", true, false): _wire_button(node)

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK: return
	for key in DEFAULTS:
		var value: Variant = config.get_value("audio",key,DEFAULTS[key])
		if DEFAULTS[key] is bool:
			if value is bool: preferences[key] = value
		elif (value is float or value is int) and is_finite(float(value)):
			preferences[key] = clampf(float(value),0,1)
	var folder: Variant = config.get_value("audio","custom_music_dir","")
	if folder is String: preferences.custom_music_dir = folder
	var scope: Variant = config.get_value("audio","custom_music_scope","both")
	if scope is String and scope in CUSTOM_SCOPES: preferences.custom_music_scope = scope

func set_preference(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key): return
	if DEFAULTS[key] is bool:
		if not value is bool: return
	elif not (value is float or value is int) or not is_finite(float(value)): return
	else: value = clampf(float(value),0,1)
	preferences[key] = value
	_save_due = 0.25
	_apply_volumes()

func custom_music_dir() -> String:
	return str(preferences.get("custom_music_dir",""))

func custom_music_scope() -> String:
	var scope := str(preferences.get("custom_music_scope","both"))
	return scope if scope in CUSTOM_SCOPES else "both"

func set_custom_music_dir(path: String) -> void:
	preferences.custom_music_dir = path.strip_edges()
	_custom_scanned = false
	custom_notice = ""
	save_preferences()
	_refresh_scene_music()

func set_custom_music_scope(scope: String) -> void:
	if not scope in CUSTOM_SCOPES or scope == custom_music_scope(): return
	preferences.custom_music_scope = scope
	save_preferences()
	_refresh_scene_music()

## Lists up to CUSTOM_SCAN_LIMIT playable files in the folder and its direct subfolders (one level, no deeper).
static func scan_custom_music(folder: String) -> Array[String]:
	var found: Array[String] = []
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): return found
	var level: Array[String] = [folder]
	for depth in 2:
		var next_level: Array[String] = []
		for path in level:
			var dir := DirAccess.open(path)
			if dir == null: continue
			var files := Array(dir.get_files())
			files.sort()
			for file in files:
				if found.size() >= CUSTOM_SCAN_LIMIT: return found
				if str(file).get_extension().to_lower() in CUSTOM_EXTENSIONS: found.append(path.path_join(file))
			if depth == 0:
				var folders := Array(dir.get_directories())
				folders.sort()
				for sub in folders: next_level.append(path.path_join(sub))
		level = next_level
	return found

## Loads one local file at runtime. Returns null for unreadable, encrypted (.ncm renamed) or tiny files.
static func load_custom_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path): return null
	var stream: AudioStream = null
	match path.get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			var wav := AudioStreamWAV.load_from_file(path)
			if wav != null: wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
			stream = wav
	if stream == null or not stream.get_length() > 0.5: return null
	if "loop" in stream: stream.set("loop",false)
	return stream

func custom_music_wanted(target: String = scene) -> bool:
	if custom_music_dir().is_empty() or not target in ["menu","battle"]: return false
	return custom_music_scope() == "both" or custom_music_scope() == target

func rescan_custom_music() -> int:
	_custom_scanned = true
	_custom_scanned_dir = custom_music_dir()
	custom_playlist = scan_custom_music(_custom_scanned_dir)
	custom_order.clear()
	custom_failed.clear()
	return custom_playlist.size()

func _ensure_custom_scanned() -> void:
	if not _custom_scanned or _custom_scanned_dir != custom_music_dir(): rescan_custom_music()

func custom_music_status() -> String:
	if custom_music_dir().is_empty(): return "未设置，使用内置音乐。"
	if not DirAccess.dir_exists_absolute(custom_music_dir()): return "找不到这个文件夹，使用内置音乐。"
	_ensure_custom_scanned()
	if custom_playlist.size() <= custom_failed.size(): return "文件夹里没有可播放的 mp3 / ogg / wav，使用内置音乐。"
	var skipped := "（%d 首无法读取，已跳过）" % custom_failed.size() if custom_failed.size() > 0 else ""
	var capped := "（最多读取 %d 首）" % CUSTOM_SCAN_LIMIT if custom_playlist.size() >= CUSTOM_SCAN_LIMIT else ""
	return "已找到 %d 首%s%s，随机播放。" % [custom_playlist.size(),skipped,capped]

## Picks and loads the next shuffled track; unreadable files are skipped and remembered.
func next_custom_stream() -> AudioStream:
	_ensure_custom_scanned()
	for attempt in custom_playlist.size()+1:
		if custom_order.is_empty():
			for path in custom_playlist:
				if not custom_failed.has(path): custom_order.append(path)
			if custom_order.is_empty(): return null
			custom_order.shuffle()
			# Avoid repeating the song that just ended when a new round starts.
			if custom_order.size() > 1 and custom_order.back() == custom_current:
				custom_order.push_front(custom_order.pop_back())
		var path: String = custom_order.pop_back()
		var stream := load_custom_stream(path)
		if stream != null:
			custom_current = path
			return stream
		custom_failed[path] = true
		push_warning("Custom music skipped (unreadable): "+path)
	return null

func _custom_fallback(reason: String) -> void:
	var text := reason+"，已改用内置音乐。"
	if text == custom_notice: return
	custom_notice = text
	custom_music_notice.emit(text)

func _play_custom() -> bool:
	if not DirAccess.dir_exists_absolute(custom_music_dir()):
		_custom_fallback("找不到自定义音乐文件夹")
		return false
	var stream := next_custom_stream()
	if stream == null:
		_custom_fallback("自定义音乐文件夹里没有可播放的 mp3 / ogg / wav")
		return false
	custom_notice = ""
	_crossfade(stream,true)
	return true

## Plays what the current scene should hear: the custom list when chosen, else the built-in track.
func _play_scene_music() -> void:
	if custom_music_wanted() and _play_custom(): return
	if tracks.has(scene): _crossfade(tracks[scene])

func _refresh_scene_music() -> void:
	# Field-card music keeps priority during battles; it is replaced when the field ends.
	if scene.is_empty() or (scene == "battle" and not field_music.is_empty()): return
	_play_scene_music()

func save_preferences() -> void:
	var config := ConfigFile.new()
	for key in preferences: config.set_value("audio",key,preferences[key])
	config.save(config_path)
	_save_due = -1

func _exit_tree() -> void:
	if _save_due >= 0: save_preferences()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		suspended = true
		_apply_volumes()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]:
		suspended = false
		_apply_volumes()

func silent() -> bool:
	return not enabled or bool(preferences.muted) or float(preferences.master)<=0 or (suspended and bool(preferences.background_mute))

func set_scene(next: String) -> void:
	if next != "battle": field_music=""; music_revision+=1
	if next == scene or not tracks.has(next): return
	scene = next
	# Keep the current custom song going when both scenes use the custom list.
	if custom_active and custom_music_wanted(next): return
	_play_scene_music()

func _crossfade(stream: AudioStream, custom := false) -> void:
	custom_active = custom
	_music_slot = 1-_music_slot
	var player := music_players[_music_slot]
	player.stop()
	player.stream = stream
	player.volume_db = -80
	gains[_music_slot] = 0.0
	targets = [0.0,0.0]
	targets[_music_slot] = 1.0
	if enabled: player.play()
	_apply_volumes()

func sound(key: String) -> bool:
	if silent() or float(preferences.effects)<=0 or not sounds.has(key): return false
	var now := Time.get_ticks_msec()
	# Bound simultaneous area damage and double-click spam without dropping later actions.
	var gap := 65 if key in ["damage","death","draw","deploy"] else 45
	if now-int(cooldowns.get(key,-1000)) < gap: return false
	cooldowns[key] = now
	var player := voices[_voice]
	_voice = (_voice+1)%voices.size()
	player.stop()
	player.stream = sounds[key]
	player.volume_db = linear_to_db(maxf(0.0001,float(preferences.master)*float(preferences.effects)))
	player.play()
	sound_played.emit(key)
	return true

func _apply_volumes() -> void:
	var quiet := silent()
	for i in music_players.size():
		var player := music_players[i]
		player.stream_paused = quiet or float(preferences.music)<=0
		player.volume_db = linear_to_db(maxf(0.0001,float(gains[i])*float(preferences.master)*float(preferences.music)))
	for player in voices:
		if quiet or float(preferences.effects)<=0: player.stop()
		else: player.volume_db = linear_to_db(maxf(0.0001,float(preferences.master)*float(preferences.effects)))

func _process(delta: float) -> void:
	if _save_due >= 0:
		_save_due -= delta
		if _save_due < 0: save_preferences()
	if silent(): return
	for i in music_players.size():
		gains[i] = move_toward(float(gains[i]),float(targets[i]),delta/0.9)
		var player := music_players[i]
		if targets[i] == 0.0 and gains[i] == 0.0:
			player.stop()
		elif targets[i] > 0 and float(preferences.music)>0:
			# Non-looping recordings end naturally, then fade back in on the next pass.
			if not player.playing:
				if custom_active and i == _music_slot:
					# Custom playlists advance to the next song instead of repeating.
					if not _play_custom() and tracks.has(scene): _crossfade(tracks[scene])
					break
				gains[i] = 0.0
				player.play()
			elif player.get_playback_position() > player.stream.get_length()-1.4:
				gains[i] = minf(float(gains[i]),maxf(0.0,(player.stream.get_length()-player.get_playback_position())/1.4))
	_apply_volumes()

func fade_in(control: Control) -> void:
	if not bool(preferences.animations) or not is_instance_valid(control): return
	if control.has_meta("ui_fade"):
		var previous: Tween = control.get_meta("ui_fade")
		if previous.is_valid(): previous.kill()
	control.modulate.a = 0.0
	var tween := control.create_tween()
	control.set_meta("ui_fade",tween)
	tween.tween_property(control,"modulate:a",1.0,0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _node_added(node: Node) -> void:
	if node is BaseButton: _wire_button.call_deferred(node)

func _wire_button(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or not get_parent().is_ancestor_of(node) or node.has_meta("feedback_wired"): return
	var button := node as BaseButton
	button.set_meta("feedback_wired",true)
	button.button_down.connect(func():
		if not button.disabled: card_sound("select",button.spec.get("media",{}),"card") if button.has_method("effect_badges") else sound("click")
	)
	# Card motion is owned by battle_view. Only ordinary buttons get a tint tween.
	if button.has_method("effect_badges") or button.get_script() == preload("res://scripts/ui/battle_props.gd"): return
	button.mouse_entered.connect(func(): _tint(button,Color(1.10,1.08,1.04)))
	button.mouse_exited.connect(func(): _tint(button,Color.WHITE))
	button.button_down.connect(func(): _tint(button,Color(0.82,0.85,0.82)))
	button.button_up.connect(func(): _tint(button,Color.WHITE))
	if button is OptionButton: button.item_selected.connect(func(_index): sound("click"))

func _tint(button: BaseButton, color: Color) -> void:
	if not is_instance_valid(button) or button.disabled: return
	if button.has_meta("ui_tint"):
		var previous: Tween = button.get_meta("ui_tint")
		if previous.is_valid(): previous.kill()
	if not bool(preferences.animations): button.self_modulate = Color.WHITE; return
	var tween := button.create_tween()
	button.set_meta("ui_tint",tween)
	tween.tween_property(button,"self_modulate",color,0.12)

static func card_cue(context: Node, key: String, media: Dictionary, fallback: String) -> void:
	var manager:=service(context)
	if manager!=null: manager.card_sound(key,media,fallback)

func preload_media(media: Dictionary) -> void:
	for id in media.get("sounds",{}).values(): CardSoundCache.fetch(str(id),get_tree())

func card_sound(key: String, media: Dictionary, fallback: String) -> bool:
	var id:=str(media.get("sounds",{}).get(key,""))
	var stream:=CardSoundCache.cached(id)
	if stream==null:
		if not id.is_empty(): CardSoundCache.fetch(id,get_tree())
		return sound(fallback)
	if silent() or float(preferences.effects)<=0: return false
	var now:=Time.get_ticks_msec()
	if now-int(cooldowns.get(id,-1000))<65:return false
	cooldowns[id]=now
	var player:=voices[_voice]
	_voice=(_voice+1)%voices.size()
	player.stop()
	player.stream=stream
	player.volume_db=linear_to_db(maxf(0.0001,float(preferences.master)*float(preferences.effects)))
	player.play()
	sound_played.emit(key)
	return true

func set_field_music(id: String) -> void:
	if scene!="battle" or id==field_music:return
	field_music=id
	music_revision+=1
	var revision:=music_revision
	# Always discard the previous field immediately, even during a slow download.
	# A custom battle song that is already playing keeps going until the field track arrives.
	if not (custom_active and custom_music_wanted("battle")): _play_scene_music()
	if id.is_empty():return
	var stream:=await CardSoundCache.fetch(id,get_tree())
	if not is_inside_tree() or revision!=music_revision or scene!="battle" or stream==null:return
	_crossfade(stream)
