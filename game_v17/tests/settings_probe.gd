extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段4E 最小 probe：SettingsService（用户设置/原子/损坏/迁移）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/settings_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接 UI/音频/本地化表。
# ═══════════════════════════════════════════════════════════════════

const SettingsService := preload("res://scripts/core/settings_service.gd")

const PROBE_PATH := "user://settings_probe.json"
const FIELDS := ["language", "master_volume", "music_volume", "sfx_volume",
	"subtitles", "text_speed", "default_time_scale", "display_mode", "ui_scale"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE4E PROBE · SettingsService")
	print("════════════════════════════════════════════════════════════")
	_cleanup()
	_test_defaults()
	_test_get_set()
	_test_from_dict()
	_test_save_load_atomic()
	_test_corruption_migration()
	_test_apply_reset()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 SETTINGS PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	_cleanup()
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 SETTINGS PROBE FAILED")
		quit(1)
	else:
		print("V17 SETTINGS PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if detail != "":
			line += "  (" + detail + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, detail])

func _eq(actual, expected, label: String, detail := "") -> void:
	var d := "actual=%s expected=%s" % [str(actual), str(expected)]
	if detail != "":
		d += " · " + detail
	_ok(actual == expected, label, d)

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _svc(path := PROBE_PATH) -> Object:
	var s = SettingsService.new({"path": path})
	_ok(bool(s.ready), "SettingsService ready", str(s.errors))
	return s

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _cleanup() -> void:
	for ext in ["", ".bak", ".tmp"]:
		var p := _abs(PROBE_PATH + ext)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _write(path: String, text: String) -> void:
	var abs := _abs(path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var f := FileAccess.open(abs, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

func _read(path: String) -> String:
	var abs := _abs(path)
	if not FileAccess.file_exists(abs):
		return ""
	return FileAccess.get_file_as_string(abs)

func _exists(path: String) -> bool:
	return FileAccess.file_exists(_abs(path))

# ═══════════════════════════════════════════════════════════════════
# 1. 默认值
# ═══════════════════════════════════════════════════════════════════

func _test_defaults() -> void:
	_section_begin("1 默认值")
	var s = _svc()
	_eq(str(s.last_load.get("status", "")), "defaults_missing", "缺文件 defaults")
	_eq(bool(s.last_load.get("ok", false)), true, "defaults ok")
	_eq(s.to_dict().size(), 9, "9 字段")
	for k in FIELDS:
		_ok(s.to_dict().has(str(k)), "字段 " + str(k))
	_eq(str(s.get("language")), "zh", "默认 language zh")
	_eq(float(s.get("master_volume")), 0.8, "默认 master .8")
	_eq(float(s.get("music_volume")), 0.7, "默认 music .7")
	_eq(float(s.get("sfx_volume")), 0.8, "默认 sfx .8")
	_eq(bool(s.get("subtitles")), true, "默认 subtitles true")
	_eq(float(s.get("text_speed")), 1.0, "默认 text_speed 1.0")
	_eq(int(s.get("default_time_scale")), 1, "默认 time_scale 1")
	_eq(str(s.get("display_mode")), "windowed", "默认 windowed")
	_eq(float(s.get("ui_scale")), 1.0, "默认 ui_scale 1.0")
	_ok(s.defaults() is Dictionary, "defaults 对象")
	_eq(s.defaults().size(), 9, "defaults 9")
	_ok(bool(s.check_contracts().get("ok", false)), "默认 contracts ok")
	_eq(bool((s.summary().get("writes", {}) as Dictionary).get("world", true)), false,
		"不写 world")
	_eq(bool((s.summary().get("writes", {}) as Dictionary).get("ui", true)), false,
		"不写 UI")
	_data_line("defaults", "9 字段默认 · zh/0.8/0.7/0.8/true/1.0/1/windowed/1.0 · 缺文件 defaults")

# ═══════════════════════════════════════════════════════════════════
# 2. get/set / 范围
# ═══════════════════════════════════════════════════════════════════

func _test_get_set() -> void:
	_section_begin("2 get/set/范围")
	var s = _svc()
	# Object.get 兼容
	_eq(str(s.get("language")), "zh", "Object.get language")
	# set_value 合法
	_eq(bool(s.set_value("language", "ja")), true, "set language ja")
	_eq(str(s.get_value("language")), "ja", "language ja")
	_eq(bool(s.set_value("master_volume", 0.0)), true, "volume 0")
	_eq(bool(s.set_value("music_volume", 1.0)), true, "music 1")
	_eq(bool(s.set_value("sfx_volume", 0.35)), true, "sfx 0.35")
	_eq(bool(s.set_value("subtitles", false)), true, "subtitles false")
	_eq(bool(s.set_value("text_speed", 0.5)), true, "text speed 0.5")
	_eq(bool(s.set_value("default_time_scale", 300)), true, "time scale 300")
	_eq(bool(s.set_value("display_mode", "fullscreen")), true, "display fullscreen")
	_eq(bool(s.set_value("ui_scale", 1.5)), true, "ui 1.5")
	_eq(s.to_dict().size(), 9, "set 后字段数")
	# Object.set 兼容（void；通过 get 校验）
	s.set("language", "en")
	_eq(str(s.get("language")), "en", "Object.set language")
	s.set("subtitles", true)
	_eq(bool(s.get("subtitles")), true, "Object.set subtitles")
	# 非法值/范围/未知键：不改状态
	var before := JSON.stringify(s.to_dict())
	var bads: Array = [
		["language", "fr"], ["language", ""], ["language", 3],
		["master_volume", -0.1], ["master_volume", 1.1], ["music_volume", "x"],
		["sfx_volume", NAN], ["subtitles", "on"], ["text_speed", 0.49],
		["text_speed", 2.01], ["default_time_scale", 5], ["default_time_scale", 60.5],
		["display_mode", "window"], ["display_mode", true], ["ui_scale", 0.79],
		["ui_scale", 1.51], ["unknown_key", 1]]
	for pair in bads:
		_eq(bool(s.set_value(str(pair[0]), pair[1])), false,
			"非法 set 拒绝 " + str(pair[0]) + "=" + str(pair[1]))
	_eq(JSON.stringify(s.to_dict()), before, "非法 set 不改状态")
	# 边界合法
	for pair2 in [["language", "zh"], ["master_volume", 0.0],
			["music_volume", 1.0], ["text_speed", 0.5], ["text_speed", 2.0],
			["default_time_scale", 1], ["default_time_scale", 10],
			["default_time_scale", 60], ["default_time_scale", 300],
			["display_mode", "borderless"], ["ui_scale", 0.8], ["ui_scale", 1.5]]:
		_eq(bool(s.set_value(str(pair2[0]), pair2[1])), true,
			"边界 set " + str(pair2[0]))
	# get unknown / fallback
	_eq(s.get_value("NOPE", "fb"), "fb", "get unknown fallback")
	_eq(s.get("NOPE"), null, "Object.get unknown null")
	_data_line("get/set", "9 字段 Object.get/set 兼容 · 边界 · 17 类非法原子拒绝 · 范围 0..1/.5..2/.8..1.5")

# ═══════════════════════════════════════════════════════════════════
# 3. from_dict / to_dict
# ═══════════════════════════════════════════════════════════════════

func _test_from_dict() -> void:
	_section_begin("3 from_dict/to_dict")
	var s = _svc()
	var full := {"language": "ja", "master_volume": 0.2, "music_volume": 0.3,
		"sfx_volume": 0.4, "subtitles": false, "text_speed": 1.5,
		"default_time_scale": 60, "display_mode": "borderless", "ui_scale": 1.2}
	_eq(bool(s.from_dict(full)), true, "from_dict full")
	_eq(s.to_dict(), full, "from_dict full 应用")
	# wrapper
	var wrap := {"schema": "v17.settings.v1", "version": "1.0.0",
		"settings": {"language": "en", "master_volume": 0.5}}
	_eq(bool(s.from_dict(wrap)), true, "from_dict wrapper")
	_eq(str(s.get("language")), "en", "wrapper language")
	_eq(float(s.get("master_volume")), 0.5, "wrapper master")
	_eq(float(s.get("ui_scale")), 1.2, "partial 保留其他")
	# 非法原子
	var before := JSON.stringify(s.to_dict())
	var bads: Array = [
		{"language": "fr"}, {"master_volume": 2.0}, {"subtitles": "x"},
		{"unknown_field": 1}, {"default_time_scale": 2}]
	for b in bads:
		_eq(bool(s.from_dict(b)), false, "非法 from_dict 拒绝：" + str(b))
	_eq(JSON.stringify(s.to_dict()), before, "非法 from_dict 不改状态")
	_ok(not bool(s.from_dict("x")), "非对象 from_dict 拒绝")
	# to_dict 副本
	var d: Dictionary = s.to_dict()
	d["language"] = "MUTATED"
	_eq(str(s.get("language")), "en", "to_dict 是副本")
	_eq(JSON.stringify(s.to_dict()), before, "to_dict 副本不改内部")
	# JSON
	_ok(JSON.parse_string(s.to_json()) is Dictionary, "to_json 可解析")
	_data_line("dict", "full/wrapper/partial · 5 类非法原子拒绝 · to_dict 副本/JSON")

# ═══════════════════════════════════════════════════════════════════
# 4. save/load/atomic/backup
# ═══════════════════════════════════════════════════════════════════

func _test_save_load_atomic() -> void:
	_section_begin("4 save/load/atomic")
	_cleanup()
	var s = _svc()
	s.from_dict({"language": "ja", "master_volume": 0.4,
		"music_volume": 0.5, "sfx_volume": 0.6, "subtitles": false,
		"text_speed": 1.25, "default_time_scale": 10,
		"display_mode": "borderless", "ui_scale": 1.1})
	var sv: Dictionary = s.save()
	_eq(bool(sv.get("ok", false)), true, "save ok")
	_eq(bool(sv.get("atomic", false)), true, "atomic write")
	_ok(_exists(PROBE_PATH), "主文件存在")
	_ok(not _exists(PROBE_PATH + ".tmp"), "无残留 .tmp")
	var raw := _read(PROBE_PATH)
	var file: Dictionary = JSON.parse_string(raw)
	_ok(file is Dictionary, "文件 JSON 可解析")
	_eq(str(file.get("schema", "")), "v17.settings.v1", "文件 schema")
	_eq(str(file.get("version", "")), "1.0.0", "文件 version")
	_eq((file.get("settings", {}) as Dictionary).size(), 9, "文件 9 字段")
	# 重新加载
	var s2 = _svc()
	_eq(str(s2.last_load.get("status", "")), "loaded", "load status")
	_eq(s2.to_dict(), s.to_dict(), "load 设置一致")
	eq_near(s2, "master_volume", 0.4)
	# 第二次 save → 备份
	s2.set_value("language", "en")
	var sv2: Dictionary = s2.save()
	_ok(str(sv2.get("backup", "")) != "", "第二次 save 有备份")
	_ok(_exists(PROBE_PATH + ".bak"), "备份文件存在")
	var bak: Dictionary = JSON.parse_string(_read(PROBE_PATH + ".bak"))
	_eq(str(((bak.get("settings", {}) as Dictionary).get("language", ""))), "ja",
		"备份保存旧值")
	# 再次 reload 新值
	var s3 = _svc()
	_eq(str(s3.get("language")), "en", "reload 新值")
	# 文件内容确定性
	var text1 := _read(PROBE_PATH)
	var s4 = _svc()
	s4.from_dict(s3.to_dict())
	s4.set_value("language", "en")
	s4.save()
	_eq(_read(PROBE_PATH), text1, "同设置 save 内容确定")
	# 不写 world/UI
	_eq(bool((s3.summary().get("writes", {}) as Dictionary).get("world", true)), false,
		"save 不写 world")
	# save/load 往返
	_eq(s4.to_dict(), s3.to_dict(), "save/load 往返")
	_data_line("save", "原子写/tmp 清理/文件 schema · 第二次 save 备份 · load 一致 · 内容确定")

func eq_near(s, key: String, expected: float) -> void:
	_ok(absf(float(s.get(key)) - expected) <= 1.0e-6, "near " + str(key),
		str(s.get(key)))

# ═══════════════════════════════════════════════════════════════════
# 5. 损坏恢复 / 迁移
# ═══════════════════════════════════════════════════════════════════

func _test_corruption_migration() -> void:
	_section_begin("5 损坏/迁移")
	# 损坏主文件 + 有效备份 → recovered_backup
	_cleanup()
	var s = _svc()
	s.from_dict({"language": "ja", "master_volume": 0.3})
	s.save()
	s.set_value("language", "en")
	s.save()  # .bak = ja
	_eq(str(s.last_load.get("status", "")), "saved", "第二次 saved")
	_write(PROBE_PATH, "{bad json")
	var s2 = _svc()
	_eq(str(s2.last_load.get("status", "")), "recovered_backup", "损坏→备份恢复")
	_eq(str(s2.get("language")), "ja", "备份值恢复")
	_eq(float(s2.get("master_volume")), 0.3, "备份 volume")
	_eq(bool(s2.ready), true, "备份恢复 ready")
	# 损坏且无备份 → defaults
	_cleanup()
	_write(PROBE_PATH, "{bad json")
	var s3 = _svc()
	_eq(str(s3.last_load.get("status", "")), "recovered_defaults", "损坏无备份→defaults")
	_eq(str(s3.get("language")), "zh", "defaults language")
	_eq(float(s3.get("ui_scale")), 1.0, "defaults ui")
	_eq(bool(s3.ready), true, "defaults recovery ready")
	# 空文件也当损坏
	_write(PROBE_PATH, "")
	var s3b = _svc()
	_eq(str(s3b.last_load.get("status", "")), "recovered_defaults", "空文件→defaults")
	# legacy flat（无 schema）→ migrated
	_cleanup()
	_write(PROBE_PATH, JSON.stringify({"language": "ja", "master_volume": 0.2,
		"subtitles": false}))
	var s4 = _svc()
	_eq(str(s4.last_load.get("status", "")), "migrated", "legacy migrated status")
	_eq(bool(s4.last_load.get("migrated", false)), true, "legacy migrated flag")
	_eq(str(s4.last_load.get("from_version", "")), "legacy", "legacy from")
	_eq(str(s4.get("language")), "ja", "legacy language")
	_eq(bool(s4.get("subtitles")), false, "legacy subtitles")
	_eq(float(s4.get("ui_scale")), 1.0, "legacy 补默认")
	# 0.9.0 wrapper → migrated
	_cleanup()
	_write(PROBE_PATH, JSON.stringify({"schema": "v17.settings.v1",
		"version": "0.9.0", "settings": {"language": "en", "ui_scale": 1.3}}))
	var s5 = _svc()
	_eq(str(s5.last_load.get("status", "")), "migrated", "0.9 migrated")
	_eq(str(s5.last_load.get("from_version", "")), "0.9.0", "0.9 from")
	_eq(str(s5.get("language")), "en", "0.9 language")
	_eq(float(s5.get("ui_scale")), 1.3, "0.9 ui")
	_eq(float(s5.get("master_volume")), 0.8, "0.9 补默认 master")
	# 未知版本 → defaults + warning
	_cleanup()
	_write(PROBE_PATH, JSON.stringify({"schema": "v17.settings.v1",
		"version": "9.9.9", "settings": {"language": "ja"}}))
	var s6 = _svc()
	_eq(str(s6.last_load.get("status", "")), "recovered_defaults", "未来版本→defaults")
	_eq(str(s6.get("language")), "zh", "未来版本 default language")
	_ok((s6.warnings as Array).size() >= 1, "未来版本 warning")
	# 非法字段值 → 回退默认 + warning
	_cleanup()
	_write(PROBE_PATH, JSON.stringify({"schema": "v17.settings.v1",
		"version": "1.0.0", "settings": {"language": "xx",
			"master_volume": 2.0, "ui_scale": 1.2}}))
	var s7 = _svc()
	_eq(str(s7.get("language")), "zh", "非法 language 回退默认")
	_eq(float(s7.get("master_volume")), 0.8, "非法 volume 回退默认")
	_eq(float(s7.get("ui_scale")), 1.2, "合法 ui 保留")
	_ok((s7.warnings as Array).size() >= 2, "非法字段 warning")
	# 非法内容 save 拒绝
	var s8 = _svc()
	s8.settings["language"] = "xx"
	var badsave: Dictionary = s8.save()
	_eq(bool(badsave.get("ok", true)), false, "非法 settings save 拒绝")
	_eq(str(badsave.get("reason", "")), "invalid_settings", "save reason")
	_data_line("corrupt/migrate", "损坏→bak→defaults · legacy/0.9 迁移 · 未来版本/非法字段回退 · save 拒绝")

# ═══════════════════════════════════════════════════════════════════
# 6. apply / reset / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_apply_reset() -> void:
	_section_begin("6 apply/reset")
	var s = _svc()
	s.from_dict({"language": "ja", "master_volume": 0.25, "music_volume": 0.5,
		"sfx_volume": 0.75, "subtitles": false, "text_speed": 1.5,
		"default_time_scale": 60, "display_mode": "fullscreen", "ui_scale": 1.25})
	var au: Dictionary = s.apply_audio()
	_eq(bool(au.get("ok", false)), true, "apply_audio ok")
	_eq(float(au.get("master_volume", 0.0)), 0.25, "audio master")
	_eq(float(au.get("music_volume", 0.0)), 0.5, "audio music")
	_eq(float(au.get("sfx_volume", 0.0)), 0.75, "audio sfx")
	_eq(bool(au.get("muted", true)), false, "audio not muted")
	_eq(bool(((au.get("backends", {}) as Dictionary).get("writes", {}) as Dictionary).get("audio_bus", true)), false,
		"audio 不写 bus")
	var di: Dictionary = s.apply_display()
	_eq(bool(di.get("ok", false)), true, "apply_display ok")
	_eq(str(di.get("display_mode", "")), "fullscreen", "display mode")
	_eq(float(di.get("ui_scale", 0.0)), 1.25, "display ui")
	_eq(str(di.get("language", "")), "ja", "display language")
	_eq(bool(di.get("subtitles", true)), false, "display subtitles")
	_eq(float(di.get("text_speed", 0.0)), 1.5, "display text_speed")
	_eq(int(di.get("default_time_scale", 0)), 60, "display time_scale")
	_eq(bool(((di.get("backends", {}) as Dictionary).get("writes", {}) as Dictionary).get("window", true)), false,
		"display 不写 window")
	# muted 边界
	s.set_value("master_volume", 0.0)
	_eq(bool(s.apply_audio().get("muted", false)), true, "master 0 muted")
	# reset
	s.set_value("language", "en")
	_eq(bool(s.reset()), true, "reset ok")
	_eq(s.to_dict(), s.defaults(), "reset 回默认")
	_eq(str(s.get("language")), "zh", "reset language")
	# 确定性 JSON / from_dict
	var a = _svc()
	var b = _svc()
	var cfg := {"language": "en", "master_volume": 0.4, "subtitles": false,
		"display_mode": "borderless", "ui_scale": 1.2}
	a.from_dict(cfg)
	b.from_dict(cfg)
	_eq(a.to_json(), b.to_json(), "同设置 JSON 一致")
	_eq(a.to_file_dict(), b.to_file_dict(), "同设置 file dict 一致")
	eq_near(a, "master_volume", 0.4)
	_ok(bool(a.check_contracts().get("ok", false)), "contracts ok")
	# 不写 world/UI 声明
	_eq(bool((a.summary().get("writes", {}) as Dictionary).get("world", true)), false,
		"summary 不写 world")
	_eq(bool((a.summary().get("writes", {}) as Dictionary).get("ui", true)), false,
		"summary 不写 UI")
	_data_line("apply/reset", "audio/display 接口值 · muted 边界 · reset 默认 · JSON 确定 · 不写 world/UI")
