extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段4E：SettingsService（用户设置；新文件）
#
# - 字段：language(zh/ja/en)、master/music/sfx volume 0..1、
#   subtitles on/off、text_speed 0.5..2.0、default_time_scale(1/10/60/300)、
#   display_mode(windowed/fullscreen/borderless)、ui_scale 0.8..1.5；
# - 持久化 `user://settings.json`：原子写（tmp→bak→rename）、损坏回退
#   （主文件损坏→.bak→defaults）、版本迁移；
# - API：setup/load/save/get/set/reset/apply_audio/apply_display/
#   to_dict/from_dict；非法值拒绝且不改状态；
# - 只做设置数据/接口，不接 UI/实际本地化表/音频/显示后端；不写 world/V15。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.settings.v1"
const VERSION := "1.0.0"
const DEFAULT_PATH := "user://settings.json"
const LEGACY_VERSIONS := ["0.9.0", "1.0.0"]
const TMP_SUFFIX := ".tmp"
const BAK_SUFFIX := ".bak"
const LANGUAGES := ["zh", "ja", "en"]
const DISPLAY_MODES := ["windowed", "fullscreen", "borderless"]
const TIME_SCALES := [1, 10, 60, 300]
const FIELDS := ["language", "master_volume", "music_volume", "sfx_volume",
	"subtitles", "text_speed", "default_time_scale", "display_mode", "ui_scale"]
const DEFAULTS := {
	"language": "zh",
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"subtitles": true,
	"text_speed": 1.0,
	"default_time_scale": 1,
	"display_mode": "windowed",
	"ui_scale": 1.0,
}
const RANGES := {
	"master_volume": [0.0, 1.0],
	"music_volume": [0.0, 1.0],
	"sfx_volume": [0.0, 1.0],
	"text_speed": [0.5, 2.0],
	"ui_scale": [0.8, 1.5],
}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []
var settings: Dictionary = {}
var path := DEFAULT_PATH
var global_path := ""
var last_load: Dictionary = {}
var version := VERSION

func _init(cfg := {}) -> void:
	setup(cfg)

# ── setup / load / save ────────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	settings = DEFAULTS.duplicate(true)
	last_load = {}
	version = VERSION
	var c: Dictionary = cfg if cfg is Dictionary else {}
	path = str(c.get("path", c.get("settings_path", DEFAULT_PATH)))
	if path.strip_edges() == "":
		errors.append("settings path 为空")
		return false
	global_path = _global(path)
	var r := load_settings()
	ready = bool(r.get("ok", false))
	return ready

func _global(p: String) -> String:
	if p.begins_with("user://") or p.begins_with("res://"):
		return ProjectSettings.globalize_path(p)
	return p

## load 与 GDScript 全局 load() 冲突，使用 load_settings()/reload() 别名。
func load_settings() -> Dictionary:
	errors.clear()
	warnings.clear()
	last_load = {}
	if global_path == "":
		global_path = _global(path)
	# 缺失 → defaults
	if not FileAccess.file_exists(global_path):
		settings = DEFAULTS.duplicate(true)
		last_load = {"ok": true, "status": "defaults_missing",
			"migrated": false, "from_version": "", "source": "defaults",
			"path": global_path}
		ready = true
		return last_load.duplicate(true)
	var raw := _read_text(global_path)
	if raw.get("ok", false):
		var parsed = _parse(raw.get("text", ""))
		if parsed is Dictionary:
			var mig := _migrate_dict(parsed)
			if bool(mig.get("ok", false)):
				var applied := _apply_loaded_settings(mig.get("settings", {}))
				if bool(applied.get("ok", false)):
					last_load = {"ok": true,
						"status": "migrated" if bool(mig.get("migrated", false)) else "loaded",
						"migrated": bool(mig.get("migrated", false)),
						"from_version": str(mig.get("from_version", "")),
						"source": "main", "path": global_path,
						"warnings": (applied.get("warnings", []) as Array).duplicate()}
					if not (applied.get("warnings", []) as Array).is_empty():
						warnings.append_array(applied.get("warnings", []))
					ready = true
					return last_load.duplicate(true)
			# 版本不支持/结构非法 → 尝试备份，再 defaults
			warnings.append("主文件结构/版本不可用：" + str(mig.get("reason", "")))
		else:
			warnings.append("主设置 JSON 损坏")
	else:
		warnings.append("主设置文件不可读")
	# 损坏/非法 → .bak 恢复
	var bak := global_path + BAK_SUFFIX
	if FileAccess.file_exists(bak):
		var braw := _read_text(bak)
		if bool(braw.get("ok", false)):
			var bparsed = _parse(braw.get("text", ""))
			if bparsed is Dictionary:
				var bmig := _migrate_dict(bparsed)
				if bool(bmig.get("ok", false)):
					var bapp := _apply_loaded_settings(bmig.get("settings", {}))
					if bool(bapp.get("ok", false)):
						last_load = {"ok": true, "status": "recovered_backup",
							"migrated": bool(bmig.get("migrated", false)),
							"from_version": str(bmig.get("from_version", "")),
							"source": "backup", "path": global_path,
							"warnings": (bapp.get("warnings", []) as Array).duplicate()}
						ready = true
						return last_load.duplicate(true)
	# 最终 defaults
	settings = DEFAULTS.duplicate(true)
	last_load = {"ok": true, "status": "recovered_defaults", "migrated": false,
		"from_version": "", "source": "defaults", "path": global_path,
		"warnings": warnings.duplicate()}
	ready = true
	return last_load.duplicate(true)

func save() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: SettingsService 未 ready")
	var v := validate_settings(settings)
	if not bool(v.get("ok", false)):
		return _fail("invalid_settings", "settings 非法：" + str(v.get("errors", [])))
	var text := JSON.stringify(_file_dict())
	var wr := _atomic_write(global_path, text)
	if not bool(wr.get("ok", false)):
		return _fail("write_failed", "设置写入失败：" + str(wr.get("reason", "")))
	last_load = {"ok": true, "status": "saved", "path": global_path,
		"atomic": true, "backup": str(wr.get("backup", "")),
		"schema": SCHEMA, "version": VERSION}
	return {"ok": true, "path": global_path, "atomic": true,
		"backup": str(wr.get("backup", "")), "bytes": text.length()}

func _file_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": version,
		"settings": settings.duplicate(true)}

func _read_text(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "open_failed"}
	var txt := f.get_as_text()
	f.close()
	return {"ok": true, "text": txt}

func _parse(text: String) -> Variant:
	if text.strip_edges() == "":
		return null
	return JSON.parse_string(text)

func _atomic_write(abs_path: String, text: String) -> Dictionary:
	var dir := abs_path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := abs_path + TMP_SUFFIX
	var bak := abs_path + BAK_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "reason": "tmp_open_failed"}
	f.store_string(text)
	f.flush()
	f.close()
	# 回读校验
	var rd := _read_text(tmp)
	if not bool(rd.get("ok", false)) or str(rd.get("text", "")) != text:
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		return {"ok": false, "reason": "tmp_verify_failed"}
	# 旧主文件 → 备份
	if FileAccess.file_exists(abs_path):
		var old := _read_text(abs_path)
		if bool(old.get("ok", false)):
			var bf := FileAccess.open(bak, FileAccess.WRITE)
			if bf != null:
				bf.store_string(str(old.get("text", "")))
				bf.flush()
				bf.close()
		DirAccess.remove_absolute(abs_path)
	var err := DirAccess.rename_absolute(tmp, abs_path)
	if err != OK:
		if FileAccess.file_exists(bak):
			var b2 := _read_text(bak)
			if bool(b2.get("ok", false)):
				var rf := FileAccess.open(abs_path, FileAccess.WRITE)
				if rf != null:
					rf.store_string(str(b2.get("text", "")))
					rf.close()
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		return {"ok": false, "reason": "rename_failed"}
	return {"ok": true, "backup": bak if FileAccess.file_exists(bak) else ""}

# ── migration / validation ────────────────────────────────────

func _migrate_dict(d: Dictionary) -> Dictionary:
	var raw: Dictionary = {}
	var from_version := ""
	var migrated := false
	if d.has("schema"):
		if str(d.get("schema", "")) != SCHEMA:
			return {"ok": false, "reason": "invalid_schema",
				"schema": str(d.get("schema", ""))}
		from_version = str(d.get("version", ""))
		if from_version != "" and not (from_version in LEGACY_VERSIONS) \
				and from_version != VERSION:
			return {"ok": false, "reason": "unsupported_version",
				"version": from_version}
		raw = d.get("settings", {}) as Dictionary if d.get("settings") is Dictionary else {}
		migrated = from_version != VERSION or not (d.get("settings") is Dictionary)
	else:
		# legacy flat 设置（无 schema）→ v1
		raw = d.duplicate(true)
		from_version = "legacy"
		migrated = true
	# 未知字段忽略；缺省补默认
	var out := DEFAULTS.duplicate(true)
	for k in FIELDS:
		if raw.has(k):
			out[k] = raw[k]
	return {"ok": true, "settings": out, "migrated": migrated,
		"from_version": from_version, "version": VERSION}

func _apply_loaded_settings(raw: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	var warns: Array = []
	for k in FIELDS:
		if raw.has(k):
			var vr := _validate_value(str(k), raw[k])
			if bool(vr.get("ok", false)):
				out[str(k)] = _normalize_value(str(k), raw[k])
			else:
				warns.append("%s 非法，回退默认" % str(k))
	settings = out
	return {"ok": true, "settings": settings.duplicate(true), "warnings": warns}

func validate_settings(value: Dictionary) -> Dictionary:
	var errs: Array[String] = []
	for k in value.keys():
		if not (str(k) in FIELDS):
			errs.append("未知字段：" + str(k))
			continue
		var vr := _validate_value(str(k), value[k])
		if not bool(vr.get("ok", false)):
			errs.append(str(vr.get("reason", "")))
	for k2 in FIELDS:
		if not value.has(k2):
			errs.append("缺少字段：" + str(k2))
	return {"ok": errs.is_empty(), "errors": errs}

func _validate_value(key: String, value: Variant) -> Dictionary:
	if not (key in FIELDS):
		return {"ok": false, "reason": "未知字段：" + key}
	match key:
		"language":
			if not (value is String) or not (str(value) in LANGUAGES):
				return {"ok": false, "reason": "language 必须为 zh/ja/en"}
		"display_mode":
			if not (value is String) or not (str(value) in DISPLAY_MODES):
				return {"ok": false, "reason": "display_mode 非法"}
		"subtitles":
			if not (value is bool):
				return {"ok": false, "reason": "subtitles 必须为 bool"}
		"default_time_scale":
			if not (value is int or value is float):
				return {"ok": false, "reason": "default_time_scale 必须为数值"}
			if not (int(value) in TIME_SCALES) or float(value) != float(int(value)):
				return {"ok": false, "reason": "default_time_scale 必须为 1/10/60/300"}
		_:
			if not (value is int or value is float):
				return {"ok": false, "reason": str(key) + " 必须为数值"}
			if not is_finite(float(value)):
				return {"ok": false, "reason": str(key) + " 必须有限"}
			var rg = RANGES.get(key, null)
			if rg is Array:
				if float(value) < float(rg[0]) or float(value) > float(rg[1]):
					return {"ok": false, "reason": "%s 必须在 %.2f..%.2f" % [
						str(key), float(rg[0]), float(rg[1])]}
	return {"ok": true, "reason": ""}

func _normalize_value(key: String, value: Variant) -> Variant:
	if key == "default_time_scale":
		return int(value)
	if key in ["master_volume", "music_volume", "sfx_volume", "text_speed", "ui_scale"]:
		return float(value)
	return value

# ── get/set/reset/from_dict ───────────────────────────────────

## Object.get(key) 兼容（单参数）；默认值用 get_value。
func _get(property: StringName) -> Variant:
	var k := str(property)
	return settings[k] if settings.has(k) else null

## Object.set(key, value) 兼容；非法值拒绝且不改状态（引擎调用返回 false）。
func _set(property: StringName, value: Variant) -> bool:
	var k := str(property)
	if not (k in FIELDS):
		return false
	var vr := _validate_value(k, value)
	if not bool(vr.get("ok", false)):
		return false
	settings[k] = _normalize_value(k, value)
	return true

func get_value(key: String, fallback: Variant = null) -> Variant:
	if settings.has(key):
		return settings[key]
	return fallback

func set_value(key: String, value: Variant) -> bool:
	var vr := _validate_value(str(key), value)
	if not bool(vr.get("ok", false)):
		errors.append(str(vr.get("reason", "invalid_value")))
		return false
	settings[str(key)] = _normalize_value(str(key), value)
	return true

# 兼容命名（GDScript native get/set 签名不可覆盖）
func get_setting(key: String, fallback: Variant = null) -> Variant:
	return get_value(key, fallback)

func set_setting(key: String, value: Variant) -> bool:
	return set_value(key, value)

func reload() -> Dictionary:
	return load_settings()

func reset() -> bool:
	settings = DEFAULTS.duplicate(true)
	errors.clear()
	warnings.clear()
	return true

func from_dict(value: Variant) -> bool:
	if not (value is Dictionary):
		errors.append("from_dict 必须是对象")
		return false
	var d: Dictionary = value
	var raw: Dictionary = {}
	if d.get("settings") is Dictionary:
		raw = (d.get("settings") as Dictionary).duplicate(true)
	else:
		raw = d.duplicate(true)
	var out := settings.duplicate(true)
	for k in raw.keys():
		if not (str(k) in FIELDS):
			errors.append("未知字段：" + str(k))
			return false
		var vr := _validate_value(str(k), raw[k])
		if not bool(vr.get("ok", false)):
			errors.append(str(vr.get("reason", "invalid_value")))
			return false
		out[str(k)] = _normalize_value(str(k), raw[k])
	settings = out
	return true

# ── apply interfaces（不实际改音频/显示后端）────────────────────

func apply_audio() -> Dictionary:
	return {"ok": true, "master_volume": float(settings.get("master_volume", 0.8)),
		"music_volume": float(settings.get("music_volume", 0.7)),
		"sfx_volume": float(settings.get("sfx_volume", 0.8)),
		"muted": float(settings.get("master_volume", 0.8)) <= 0.0,
		"backends": {"audio": "interface_only", "writes": {"audio_bus": false}}}

func apply_display() -> Dictionary:
	return {"ok": true, "display_mode": str(settings.get("display_mode", "windowed")),
		"ui_scale": float(settings.get("ui_scale", 1.0)),
		"language": str(settings.get("language", "zh")),
		"subtitles": bool(settings.get("subtitles", true)),
		"text_speed": float(settings.get("text_speed", 1.0)),
		"default_time_scale": int(settings.get("default_time_scale", 1)),
		"backends": {"display": "interface_only", "ui": "interface_only",
			"writes": {"window": false, "ui": false}},
		"note": "不接实际窗口/本地化表；由 UI/本地化系统消费"}

# ── 只读 / to_dict / from_dict JSON ──────────────────────────

func to_dict() -> Dictionary:
	return settings.duplicate(true)

func to_file_dict() -> Dictionary:
	return _file_dict()

func to_json() -> String:
	return JSON.stringify(to_dict())

func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)

func summary() -> Dictionary:
	return {"schema": SCHEMA, "version": version, "ready": ready,
		"path": global_path, "last_status": str(last_load.get("status", "")),
		"migrated": bool(last_load.get("migrated", false)),
		"settings": settings.duplicate(true),
		"writes": {"world": false, "ui": false, "v15": false}}

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("service 未 ready")
	var vr := validate_settings(settings)
	if not bool(vr.get("ok", false)):
		v.append_array(vr.get("errors", []))
	if str(settings.get("language", "")) not in LANGUAGES:
		v.append("language 非法")
	if str(settings.get("display_mode", "")) not in DISPLAY_MODES:
		v.append("display_mode 非法")
	if not (int(settings.get("default_time_scale", 0)) in TIME_SCALES):
		v.append("default_time_scale 非法")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func last_error() -> String:
	return errors[errors.size() - 1] if not errors.is_empty() else ""

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
