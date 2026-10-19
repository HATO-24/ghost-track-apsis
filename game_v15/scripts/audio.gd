class_name AudioDirector
extends Node
## P5b-AUDIO：程序化 BGM / SFX 播放器。
## 设计为 Autoload 单例（项目设置里添加 Autoload，名 Audio，路径 res://scripts/audio.gd）。
## 不依赖编辑器导入：WAV 由本脚本按 PCM 头直接读取，headless/Dummy 驱动下安全。
##
## 公共 API：
##   play_bgm(name)             name: "menu" | "game" | "menu_ambient" | "game_ambient"
##   stop_bgm()
##   sfx(name)                  UI/警报等短音效，名称缺失时静默
##   set_bgm_volume(db)         线性总线音量（dB），默认 -14 dB
##   set_sfx_volume(db)         默认 -6 dB
##   toggle_mute() -> bool
##   is_muted() -> bool
##   _self_test() -> Dictionary 测试/启动自检
##
## 环境变量：
##   DSH_MUTE=1                 强制静音（覆盖用户配置）
##   DSH_AUDIO_LOG=0            关闭启动打印
## 本地配置：user://audio.cfg（音量/静音；不存在时使用默认值）。

const BGM_NAMES := {
	"menu": "menu_ambient",
	"menu_ambient": "menu_ambient",
	"game": "game_ambient",
	"game_ambient": "game_ambient",
}

const SFX_NAMES := [
	"ui_hover", "ui_select", "ui_confirm", "ui_back", "ui_error",
	"ui_toggle_on", "ui_toggle_off", "ui_open", "ui_close", "ui_slider", "ui_tab",
	"sys_boot", "sys_sensor_on", "sys_sensor_off", "sys_radar_ping", "sys_elint",
	"sys_comms_rx", "sys_cmd_queued", "sys_cmd_tx", "sys_cmd_exec",
	"sys_evidence_start", "sys_evidence_done", "sys_evac_start", "sys_evac_done",
	"sys_clock_tick", "alarm", "alarm_decision", "alarm_lock", "alarm_fire", "alarm_damage",
	"fire", "hard_cut", "boot",
]

const SFX_POOL_SIZE := 16
const BGM_DIR := "res://audio/"
const DEFAULT_BGM_DB := -14.0
const DEFAULT_SFX_DB := -6.0
const MUTE_DB := -80.0

var bgm_db := DEFAULT_BGM_DB
var sfx_db := DEFAULT_SFX_DB
var muted := false
var current_bgm := ""
var headless := false

var _forced_mute := false
var _setup_done := false
var _bgm_streams: Dictionary = {}
var _sfx_streams: Dictionary = {}
var _missing: Array[String] = []
var _bgm_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_index := 0
var _bgm_bus := "BGM"
var _sfx_bus := "SFX"

static var instance: AudioDirector


func _ready() -> void:
	_setup()
	instance = self


func _setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	headless = DisplayServer.get_name() == "headless"
	_forced_mute = OS.get_environment("DSH_MUTE") == "1"
	_bgm_bus = _ensure_bus("BGM")
	_sfx_bus = _ensure_bus("SFX")
	_load_config()
	if _forced_mute:
		muted = true
	_apply_volume()
	_load_assets()
	_build_players()
	if OS.get_environment("DSH_AUDIO_LOG") != "0":
		print("AUDIO OK files=%d headless=%s muted=%s" % [_loaded_count(), str(headless), str(muted)])


func _ensure_bus(bus_name: String) -> String:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name), 0.0)
	return bus_name


func _load_assets() -> void:
	_bgm_streams.clear()
	_sfx_streams.clear()
	_missing.clear()
	for key in BGM_NAMES.keys():
		var fname: String = BGM_NAMES[key]
		if not _bgm_streams.has(fname):
			var st := _load_wav(fname, true)
			if st == null:
				_missing.append(fname)
			else:
				_bgm_streams[fname] = st
	for key in SFX_NAMES:
		var st2 := _load_wav(String(key), false)
		if st2 == null:
			_missing.append(String(key))
		else:
			_sfx_streams[String(key)] = st2


func _load_wav(name: String, loop: bool) -> AudioStreamWAV:
	var path := BGM_DIR + name + ".wav"
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44:
		return null
	var channels := 1
	var mix_rate := 44100
	var bits := 16
	var data_off := -1
	var data_len := 0
	var pos := 12
	while pos + 8 <= bytes.size():
		var cid := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var sz := int(bytes.decode_u32(pos + 4))
		if cid == "fmt " and pos + 8 + 16 <= bytes.size():
			channels = int(bytes.decode_u16(pos + 10))
			mix_rate = int(bytes.decode_u32(pos + 12))
			bits = int(bytes.decode_u16(pos + 22))
		elif cid == "data":
			data_off = pos + 8
			data_len = mini(sz, bytes.size() - data_off)
		pos += 8 + sz + (sz & 1)
	if data_off < 0 or data_len <= 0:
		return null
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = mix_rate
	st.stereo = channels == 2
	st.data = bytes.slice(data_off, data_off + data_len)
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = data_len / 2
	return st


func _build_players() -> void:
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "BGMPlayer"
		_bgm_player.bus = _bgm_bus
		add_child(_bgm_player)
	if _sfx_pool.is_empty():
		for i in SFX_POOL_SIZE:
			var p := AudioStreamPlayer.new()
			p.name = "SFXPlayer%02d" % i
			p.bus = _sfx_bus
			add_child(p)
			_sfx_pool.append(p)


func _loaded_count() -> int:
	return _bgm_streams.size() + _sfx_streams.size()


func _expected_count() -> int:
	var seen := {}
	for k in BGM_NAMES.keys():
		seen[BGM_NAMES[k]] = true
	return seen.size() + SFX_NAMES.size()


# ── BGM ────────────────────────────────────────────────

func play_bgm(name: String) -> bool:
	_setup()
	var key := name.to_lower()
	if not BGM_NAMES.has(key):
		return false
	var fname: String = BGM_NAMES[key]
	if not _bgm_streams.has(fname):
		return false
	if current_bgm == fname and _bgm_player != null and _bgm_player.playing:
		return true
	current_bgm = fname
	if headless or _bgm_player == null:
		return true
	_bgm_player.stream = _bgm_streams[fname]
	_bgm_player.play()
	return true


func stop_bgm() -> void:
	_setup()
	current_bgm = ""
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()


# ── SFX ────────────────────────────────────────────────

func sfx(name: String) -> bool:
	_setup()
	var key := name.to_lower()
	if not _sfx_streams.has(key):
		return false
	if headless or muted or _sfx_pool.is_empty():
		return true
	var p: AudioStreamPlayer = _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_pool.size()
	p.stream = _sfx_streams[key]
	p.play()
	return true


# ── 音量 / 静音 ────────────────────────────────────────

func set_bgm_volume(db: float) -> void:
	_setup()
	bgm_db = clampf(db, -80.0, 6.0)
	_apply_volume()
	_save_config()


func set_sfx_volume(db: float) -> void:
	_setup()
	sfx_db = clampf(db, -80.0, 6.0)
	_apply_volume()
	_save_config()


func toggle_mute() -> bool:
	_setup()
	if _forced_mute:
		muted = true
		_apply_volume()
		return muted
	muted = not muted
	_apply_volume()
	_save_config()
	return muted


func is_muted() -> bool:
	return muted


func _apply_volume() -> void:
	var bgm_idx := AudioServer.get_bus_index(_bgm_bus)
	var sfx_idx := AudioServer.get_bus_index(_sfx_bus)
	if bgm_idx != -1:
		AudioServer.set_bus_volume_db(bgm_idx, MUTE_DB if muted else bgm_db)
		AudioServer.set_bus_mute(bgm_idx, muted)
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, MUTE_DB if muted else sfx_db)
		AudioServer.set_bus_mute(sfx_idx, muted)


# ── 配置/自检 ──────────────────────────────────────────

func _load_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://audio.cfg")
	if err != OK:
		return
	bgm_db = clampf(float(cfg.get_value("audio", "bgm_db", DEFAULT_BGM_DB)), -80.0, 6.0)
	sfx_db = clampf(float(cfg.get_value("audio", "sfx_db", DEFAULT_SFX_DB)), -80.0, 6.0)
	muted = bool(cfg.get_value("audio", "muted", false))


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm_db", bgm_db)
	cfg.set_value("audio", "sfx_db", sfx_db)
	cfg.set_value("audio", "muted", muted)
	cfg.save("user://audio.cfg")


func _self_test() -> Dictionary:
	_setup()
	return {
		"ok": _missing.is_empty(),
		"files": _loaded_count(),
		"expected": _expected_count(),
		"missing": _missing.duplicate(),
		"headless": headless,
		"muted": muted,
		"forced_mute": _forced_mute,
		"bgm_db": bgm_db,
		"sfx_db": sfx_db,
		"bgm_keys": _bgm_streams.keys(),
		"sfx_keys": _sfx_streams.keys(),
		"pool": _sfx_pool.size(),
		"loop_end": _bgm_streams.get("game_ambient", null).loop_end if _bgm_streams.has("game_ambient") else 0,
	}


func debug_info() -> Dictionary:
	return _self_test()
