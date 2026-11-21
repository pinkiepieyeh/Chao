extends SceneTree
## Custom local music folder: scan, runtime loading, shuffle/advance, field priority and fallback.
const Audio=preload("res://scripts/ui/frontline_audio.gd")
const CONFIG:="user://audio-custom-music-test.cfg"
var failures:=0
var checks:=0
var notices:Array[String]=[]

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func _initialize()->void:call_deferred("run")

func write_wav(path:String,seconds:float,pitch:float)->void:
	var rate:=8000
	var data:=PackedByteArray();data.resize(int(rate*seconds)*2)
	for i in int(rate*seconds):data.encode_s16(i*2,int(sin(TAU*pitch*i/rate)*6000))
	var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=rate;wav.stereo=false;wav.data=data
	check(wav.save_to_wav(path)==OK,"Generated wav saved: "+path)

func write_bytes(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()

func remove_tree(path:String)->void:
	var dir:=DirAccess.open(path)
	if dir==null:return
	for sub in dir.get_directories():remove_tree(path.path_join(sub))
	for file in dir.get_files():DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

func active(manager:Node)->AudioStreamPlayer:return manager.music_players[manager._music_slot]

func run()->void:
	var base:=ProjectSettings.globalize_path("user://custom_music_test")
	remove_tree(base)
	var music:=base.path_join("music");var empty:=base.path_join("empty")
	DirAccess.make_dir_recursive_absolute(music.path_join("album/deeper"));DirAccess.make_dir_recursive_absolute(empty)
	write_wav(music.path_join("a.wav"),1.5,440)
	write_wav(music.path_join("album/b.WAV"),1.2,660)
	write_wav(music.path_join("album/deeper/too_deep.wav"),1.0,330)
	write_bytes(music.path_join("broken.mp3"),"not really an mp3 file at all".to_utf8_buffer())
	write_bytes(music.path_join("vip.ncm"),"CTENFDAM encrypted".to_utf8_buffer())
	write_bytes(music.path_join("notes.txt"),"hello".to_utf8_buffer())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))

	var scanned:=Audio.scan_custom_music(music)
	check(scanned.size()==3,"Scan finds 2 wav + 1 mp3, one level deep only: %s"%[scanned])
	check(not scanned.any(func(p):return p.ends_with("too_deep.wav") or p.ends_with(".ncm") or p.ends_with(".txt")),"Scan skips deep folders, .ncm and other files")
	check(Audio.load_custom_stream(music.path_join("broken.mp3"))==null,"Unreadable mp3 returns null instead of crashing")
	var loaded:=Audio.load_custom_stream(music.path_join("a.wav"))
	check(loaded is AudioStreamWAV and absf(loaded.get_length()-1.5)<.05,"Generated wav loads at runtime")
	check(Audio.scan_custom_music(base.path_join("missing")).is_empty(),"Missing folder scans empty")

	var parent:=Node.new();root.add_child(parent)
	var manager:=Audio.new();manager.config_path=CONFIG;parent.add_child(manager)
	manager.enabled=true
	manager.custom_music_notice.connect(func(text):notices.append(text))
	check(manager.custom_music_dir()=="" and not manager.custom_music_wanted("menu"),"Custom music is off by default")
	manager.set_scene("menu")
	check(active(manager).stream==manager.tracks.menu,"Built-in menu music without a folder")

	manager.set_custom_music_dir(music)
	check(manager.custom_playlist.size()==3,"Playlist loaded from folder")
	check(manager.custom_active and active(manager).stream is AudioStreamWAV,"Menu switches to custom track immediately")
	check(active(manager).playing,"Custom track plays")
	var saved:=ConfigFile.new();saved.load(CONFIG)
	check(saved.get_value("audio","custom_music_dir","")==music and saved.get_value("audio","custom_music_scope","")=="both","Folder and scope stored in audio config")
	check(saved.has_section_key("audio","music"),"Existing audio preferences still saved alongside")
	var reloaded:=Audio.new();reloaded.config_path=CONFIG;reloaded.load_preferences()
	check(reloaded.custom_music_dir()==music,"Folder reloads from config");reloaded.free()

	var seen:={}
	for i in 8:
		var stream:AudioStream=manager.next_custom_stream()
		check(stream is AudioStreamWAV,"Only readable tracks are returned")
		seen[manager.custom_current]=true
	check(seen.size()==2,"Shuffle covers both readable tracks")
	check(manager.custom_failed.has(music.path_join("broken.mp3")),"Unreadable file is remembered and skipped")
	check(manager.custom_music_status().contains("1 首无法读取"),"Status reports skipped file: "+manager.custom_music_status())

	var slot:int=manager._music_slot;var current:=manager.custom_current
	active(manager).stop();manager._process(.1)
	check(manager._music_slot!=slot and manager.custom_active,"Track end crossfades to next custom track")
	check(manager.custom_current!=current,"Next track differs from the one that ended")

	slot=manager._music_slot
	manager.set_scene("battle")
	check(manager._music_slot==slot and manager.custom_active,"Custom song continues from menu into battle")

	# Field-card music keeps priority over the custom list.
	manager.field_music="field-test";manager._crossfade(manager.tracks.battle)
	check(not manager.custom_active,"Field music marks the slot as non-custom")
	slot=manager._music_slot
	manager.set_custom_music_scope("battle")
	check(manager._music_slot==slot and active(manager).stream==manager.tracks.battle,"Changing scope keeps field music playing")
	active(manager).stop();manager._process(.1)
	check(manager._music_slot==slot and active(manager).stream==manager.tracks.battle,"Field music repeats instead of advancing the playlist")
	manager.field_music=""

	manager.set_custom_music_scope("menu")
	check(not manager.custom_active and active(manager).stream==manager.tracks.battle,"Menu-only scope uses built-in battle music")
	manager.set_custom_music_scope("battle")
	check(manager.custom_active,"Battle-only scope uses custom list in battle")
	manager.set_scene("menu")
	check(not manager.custom_active and active(manager).stream==manager.tracks.menu,"Battle-only scope leaves menu built-in")
	manager.set_custom_music_scope("both")
	check(manager.custom_active,"Both scope uses custom list in menu")

	notices.clear()
	manager.set_custom_music_dir(empty)
	check(manager.custom_playlist.is_empty(),"Empty folder gives empty playlist")
	check(not manager.custom_active and active(manager).stream==manager.tracks.menu,"Empty folder falls back to built-in music")
	check(notices.size()==1 and notices[0].contains("内置音乐"),"Fallback shows a notice: %s"%[notices])
	check(manager.custom_music_status().contains("没有可播放"),"Status explains empty folder")
	manager.set_scene("battle")
	check(active(manager).stream==manager.tracks.battle and notices.size()==1,"Fallback persists without repeating the notice")

	notices.clear()
	manager.set_custom_music_dir(base.path_join("missing"))
	check(active(manager).stream==manager.tracks.battle and notices.size()==1 and notices[0].contains("找不到"),"Missing folder falls back with a notice")

	manager.set_custom_music_dir(music)
	check(manager.custom_active,"Valid folder recovers after fallback")
	manager.set_custom_music_dir("")
	check(not manager.custom_active and active(manager).stream==manager.tracks.battle,"Clearing restores built-in music")

	manager.set_process(false)
	for player in manager.music_players+manager.voices:player.stop();player.stream=null
	await create_timer(.2).timeout
	manager._save_due=-1;parent.queue_free();await create_timer(.2).timeout
	remove_tree(base);DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	print("CUSTOM_MUSIC: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
