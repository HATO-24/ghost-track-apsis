extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2E：SaveService（文件存档；新文件）
#
# - 基于 GameSession.save_state()/load_state()：把内存 JSON 字符串写文件；
# - 槽位 save/menu/quit/autosave；JSON + 版本 + 时间戳 + 章节/位置元数据；
# - 原子写入（tmp→rename）、旧档备份（.bak）、sha256 损坏检测、版本迁移骨架；
# - 三色圆点：save / save_and_menu / save_and_quit 只写文件并返回意图，不直接退出/切 UI；
# - 存档目录可配置（probe 用临时目录；不污染真实用户目录）；不做 UI/剧情/物理。
# ═══════════════════════════════════════════════════════════════════

const GameSessionScript := preload("res://scripts/core/game_session.gd")

const SCHEMA := "v17.save_file.v1"
const PAYLOAD_SCHEMA := "v17.session_payload.v1"
const CURRENT_VERSION := "1.0.0"
const DEFAULT_ROOT := "user://saves"
const VALID_SLOTS := ["save", "menu", "quit", "autosave"]
const BACKUP_SUFFIX := ".bak"
const TMP_SUFFIX := ".tmp"
const INTENTS := ["save", "save_and_menu", "save_and_quit"]
const INTENT_SLOTS := {"save": "save", "save_and_menu": "menu", "save_and_quit": "quit"}

var root_dir := DEFAULT_ROOT
var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var last_path := ""

func _init(dir := DEFAULT_ROOT) -> void:
	setup(dir)

func setup(dir := DEFAULT_ROOT) -> bool:
	errors.clear()
	warnings.clear()
	ready = false
	root_dir = String(dir).replace("\\\\", "/")
	if root_dir == "":
		errors.append("precondition: 存档目录不能为空")
		return false
	var g := _global(root_dir)
	var dir_abs := DirAccess.open(g)
	if dir_abs == null:
		DirAccess.make_dir_recursive_absolute(g)
		dir_abs = DirAccess.open(g)
	if dir_abs == null:
		errors.append("存档目录不可创建：" + root_dir)
		return false
	ready = true
	return true

# ── 路径 / 时间 / 校验 ─────────────────────────────────────────

func _global(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path

func slot_path(slot: String) -> String:
	return root_dir.path_join(slot + ".json")

func backup_path(slot: String) -> String:
	return slot_path(slot) + BACKUP_SUFFIX

func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))

func has_backup(slot: String) -> bool:
	return FileAccess.file_exists(backup_path(slot))

func _now_unix() -> float:
	return Time.get_unix_time_from_system()

func _now_iso() -> String:
	var dt := Time.get_datetime_string_from_system(false, true)
	return dt + "Z"

func _checksum(text: String) -> String:
	return text.sha256_text()

func _is_valid_slot(slot: String) -> bool:
	return slot in VALID_SLOTS

func _version_tuple(v: String) -> Array:
	var parts: Array = []
	for p in v.split("."):
		if not String(p).is_valid_int():
			return []
		parts.append(int(p))
	while parts.size() < 3:
		parts.append(0)
	return parts

func _version_gt(a: String, b: String) -> bool:
	var ta := _version_tuple(a)
	var tb := _version_tuple(b)
	if ta.is_empty() or tb.is_empty():
		return false
	for i in range(3):
		if int(ta[i]) > int(tb[i]):
			return true
		if int(ta[i]) < int(tb[i]):
			return false
	return false

# ── 文件编码 / 解码 ────────────────────────────────────────────

## 编码外层文件：payload 先 JSON 化，外层带 sha256（损坏检测）。
func encode_file(payload: Dictionary) -> String:
	var payload_text := JSON.stringify(payload)
	var outer := {
		"schema": SCHEMA,
		"checksum": _checksum(payload_text),
		"payload": payload_text,
	}
	return JSON.stringify(outer)

## 解码外层文件：校验 schema/checksum/JSON；返回 {ok,payload,errors}。
func decode_file(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"ok": false, "errors": ["空存档文件"], "payload": {}}
	var outer = JSON.parse_string(text)
	if not (outer is Dictionary):
		return {"ok": false, "errors": ["外层 JSON 无效"], "payload": {}}
	var o: Dictionary = outer
	if String(o.get("schema", "")) != SCHEMA:
		return {"ok": false, "errors": ["外层 schema 无效：" + String(o.get("schema", ""))], "payload": {}}
	var payload_text := String(o.get("payload", ""))
	if payload_text == "":
		return {"ok": false, "errors": ["缺 payload"], "payload": {}}
	var checksum := String(o.get("checksum", ""))
	if checksum == "" or _checksum(payload_text) != checksum:
		return {"ok": false, "errors": ["存档校验失败（损坏或篡改）"], "payload": {}}
	var payload = JSON.parse_string(payload_text)
	if not (payload is Dictionary):
		return {"ok": false, "errors": ["payload JSON 无效"], "payload": {}}
	return {"ok": true, "payload": payload, "errors": []}

# ── 迁移骨架 ───────────────────────────────────────────────────

## 当前版本；旧版本迁移骨架（0.9 → 1.0 示例），未来版本拒绝。
func migrate_payload(payload: Dictionary) -> Dictionary:
	var version := String(payload.get("version", ""))
	if version == "":
		version = "0.9.0"
	if version == CURRENT_VERSION:
		return {"ok": true, "payload": payload.duplicate(true), "migrated": false, "from": version}
	if _version_gt(version, CURRENT_VERSION):
		return {"ok": false, "reason": "unsupported_future_version",
			"errors": ["存档版本 %s 高于当前 %s" % [version, CURRENT_VERSION]],
			"payload": payload.duplicate(true)}
	if version == "0.9.0":
		var p: Dictionary = payload.duplicate(true)
		if not p.has("session_save"):
			if p.get("session_state") is String:
				p["session_save"] = String(p.get("session_state"))
			else:
				return {"ok": false, "reason": "migration_failed",
					"errors": ["0.9 迁移缺 session_state/session_save"], "payload": p}
		p.erase("session_state")
		p["version"] = CURRENT_VERSION
		p["game_version"] = String(p.get("game_version", "v17"))
		if not p.has("meta") or not (p.get("meta") is Dictionary):
			p["meta"] = {}
		(p["meta"] as Dictionary)["migrated_from"] = version
		p["migrated_at"] = _now_iso()
		return {"ok": true, "payload": p, "migrated": true, "from": version}
	return {"ok": false, "reason": "unsupported_old_version",
		"errors": ["无迁移路径的旧版本：%s" % version], "payload": payload.duplicate(true)}

# ── 原子写入 / 备份 ────────────────────────────────────────────

func atomic_write_text(path: String, text: String) -> Dictionary:
	var g := _global(path)
	var tmp := g + TMP_SUFFIX
	var bak := g + BACKUP_SUFFIX
	# 1) 备份旧文件（若存在）
	if FileAccess.file_exists(g):
		var old := FileAccess.get_file_as_string(g)
		if old != "":
			var bf := FileAccess.open(bak, FileAccess.WRITE)
			if bf != null:
				bf.store_string(old)
				bf.close()
			else:
				warnings.append("备份写入失败：" + bak)
	# 2) 写临时文件并回读校验
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "reason": "tmp_open_failed", "errors": ["无法写临时文件：" + tmp]}
	f.store_string(text)
	f.close()
	var check := FileAccess.get_file_as_string(tmp)
	if check != text:
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		return {"ok": false, "reason": "tmp_verify_failed", "errors": ["临时文件回读不一致"]}
	# 3) 原子 rename
	if FileAccess.file_exists(g):
		var rm := DirAccess.remove_absolute(g)
		if rm != OK:
			DirAccess.remove_absolute(tmp)
			return {"ok": false, "reason": "remove_old_failed", "errors": ["无法移除旧存档"]}
	var err := DirAccess.rename_absolute(tmp, g)
	if err != OK:
		return {"ok": false, "reason": "rename_failed", "errors": ["rename 失败：%d" % err]}
	last_path = path
	return {"ok": true, "path": path, "global_path": g, "backup": bak,
		"bytes": text.length(), "checksum": _checksum(text)}

# ── 保存 ──────────────────────────────────────────────────────

## 保存会话到槽位（session 必须有 save_state()/snapshot()）。
func save_session(session, slot := "save", meta := {}) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	if not _is_valid_slot(slot):
		return {"ok": false, "reason": "invalid_slot",
			"errors": ["非法槽位：%s（允许 %s）" % [slot, str(VALID_SLOTS)]]}
	if session == null or not (session is Object) or not (session as Object).has_method("save_state"):
		return {"ok": false, "reason": "invalid_session", "errors": ["session 不可保存"]}
	var session_save := String(session.save_state())
	if session_save == "":
		return {"ok": false, "reason": "empty_session_save", "errors": ["session.save_state() 为空"]}
	var snap: Dictionary = {}
	if session.has_method("snapshot"):
		snap = session.snapshot()
	var m: Dictionary = meta if meta is Dictionary else {}
	var now := _now_unix()
	var payload := {
		"schema": PAYLOAD_SCHEMA,
		"version": CURRENT_VERSION,
		"game_version": "v17",
		"slot": slot,
		"created_at": now,
		"updated_at": now,
		"created_iso": _now_iso(),
		"chapter": String(m.get("chapter", "")),
		"location": String(m.get("location", "")),
		"t_s": float(snap.get("t_s", 0.0)),
		"writer": String(snap.get("writer", "")),
		"order_count": int((snap.get("orders_summary", {}) as Dictionary).get("orders", 0)),
		"comms_events": int((snap.get("comms_summary", {}) as Dictionary).get("events", 0)),
		"meta": (m.get("meta", {}) as Dictionary).duplicate(true) if m.get("meta") is Dictionary else {},
		"session_save": session_save,
	}
	# 保留已有 created_at（覆盖保存时）
	if has_slot(slot):
		var old_meta := load_metadata(slot)
		if bool(old_meta.get("ok", false)):
			payload["created_at"] = float((old_meta.get("payload", {}) as Dictionary).get("created_at", now))
			payload["created_iso"] = String((old_meta.get("payload", {}) as Dictionary).get("created_iso", payload["created_iso"]))
	var text := encode_file(payload)
	var wr := atomic_write_text(slot_path(slot), text)
	if not bool(wr.get("ok", false)):
		return {"ok": false, "reason": String(wr.get("reason", "")),
			"errors": wr.get("errors", []), "slot": slot}
	return {"ok": true, "slot": slot, "path": slot_path(slot), "bytes": int(wr.get("bytes", 0)),
		"created_at": float(payload["created_at"]), "updated_at": now,
		"version": CURRENT_VERSION, "checksum": String(wr.get("checksum", "")),
		"backup_path": backup_path(slot), "has_backup": has_backup(slot)}

## 三色圆点：save / save_and_menu / save_and_quit。只写文件并返回意图，不直接退出/切 UI。
func save_with_intent(session, intent := "save", meta := {}) -> Dictionary:
	if not (intent in INTENTS):
		return {"ok": false, "reason": "invalid_intent", "errors": ["未知意图：" + intent]}
	var slot := String(INTENT_SLOTS.get(intent, "save"))
	var res: Dictionary = save_session(session, slot, meta)
	res["intent"] = intent
	res["should_exit"] = false
	res["should_show_menu"] = intent == "save_and_menu"
	res["note"] = "只写文件/返回意图；不直接退出或切换 UI"
	return res

func save_and_menu(session, meta := {}) -> Dictionary:
	return save_with_intent(session, "save_and_menu", meta)

func save_and_quit(session, meta := {}) -> Dictionary:
	return save_with_intent(session, "save_and_quit", meta)

# ── 读取 ──────────────────────────────────────────────────────

func _read_slot_raw(slot: String) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing_slot", "errors": ["无存档槽位：" + slot]}
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {"ok": false, "reason": "empty_file", "errors": ["存档为空：" + slot]}
	var dec := decode_file(text)
	if not bool(dec.get("ok", false)):
		return {"ok": false, "reason": "corrupted", "errors": dec.get("errors", []), "text": text}
	var mig := migrate_payload(dec.get("payload", {}))
	if not bool(mig.get("ok", false)):
		return {"ok": false, "reason": String(mig.get("reason", "migration_failed")),
			"errors": mig.get("errors", [])}
	return {"ok": true, "payload": mig.get("payload", {}), "migrated": bool(mig.get("migrated", false)),
		"from_version": String(mig.get("from", "")), "text": text}

## 读档：返回新 GameSession 或错误（不静默）。
func load_session(slot := "save") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "not_ready", "errors": errors.duplicate()}
	if not _is_valid_slot(slot):
		return {"ok": false, "reason": "invalid_slot", "errors": ["非法槽位：" + slot]}
	var raw := _read_slot_raw(slot)
	if not bool(raw.get("ok", false)):
		return {"ok": false, "reason": String(raw.get("reason", "load_failed")),
			"errors": raw.get("errors", []), "slot": slot}
	var payload: Dictionary = raw.get("payload", {})
	var save_text := String(payload.get("session_save", ""))
	if save_text == "":
		return {"ok": false, "reason": "missing_session_save", "errors": ["存档缺 session_save"]}
	var session = GameSessionScript.new()
	var lr: Dictionary = session.load_state(save_text)
	if not bool(lr.get("ok", false)):
		return {"ok": false, "reason": "session_load_failed",
			"errors": lr.get("errors", []), "slot": slot}
	var meta := {
		"slot": slot, "version": String(payload.get("version", "")),
		"game_version": String(payload.get("game_version", "")),
		"created_at": float(payload.get("created_at", 0.0)),
		"updated_at": float(payload.get("updated_at", 0.0)),
		"chapter": String(payload.get("chapter", "")),
		"location": String(payload.get("location", "")),
		"t_s": float(payload.get("t_s", 0.0)),
		"writer": String(payload.get("writer", "")),
		"order_count": int(payload.get("order_count", 0)),
		"migrated": bool(raw.get("migrated", false)),
		"migrated_from": String(raw.get("from_version", "")),
	}
	return {"ok": true, "slot": slot, "session": session, "meta": meta,
		"payload": payload.duplicate(true), "migrated": bool(raw.get("migrated", false)),
		"errors": []}

func load_metadata(slot := "save") -> Dictionary:
	if not _is_valid_slot(slot):
		return {"ok": false, "reason": "invalid_slot", "errors": ["非法槽位：" + slot]}
	var raw := _read_slot_raw(slot)
	if not bool(raw.get("ok", false)):
		return {"ok": false, "reason": String(raw.get("reason", "load_failed")),
			"errors": raw.get("errors", []), "slot": slot}
	var p: Dictionary = raw.get("payload", {})
	return {"ok": true, "slot": slot, "payload": p.duplicate(true),
		"meta": _meta_of(p), "migrated": bool(raw.get("migrated", false))}

func _meta_of(p: Dictionary) -> Dictionary:
	return {
		"slot": String(p.get("slot", "")), "version": String(p.get("version", "")),
		"game_version": String(p.get("game_version", "")),
		"created_at": float(p.get("created_at", 0.0)),
		"updated_at": float(p.get("updated_at", 0.0)),
		"chapter": String(p.get("chapter", "")),
		"location": String(p.get("location", "")),
		"t_s": float(p.get("t_s", 0.0)),
	}

func list_slots() -> Array:
	var out: Array = []
	var g := _global(root_dir)
	if DirAccess.open(g) == null:
		return out
	for raw_name in DirAccess.get_files_at(g):
		var name := String(raw_name)
		if not name.ends_with(".json"):
			continue
		var slot := name.trim_suffix(".json")
		if not _is_valid_slot(slot):
			continue
		var md := load_metadata(slot)
		var row := {"slot": slot, "path": slot_path(slot),
			"exists": FileAccess.file_exists(slot_path(slot)),
			"has_backup": has_backup(slot), "ok": bool(md.get("ok", false))}
		if bool(md.get("ok", false)):
			for k in (md.get("meta", {}) as Dictionary).keys():
				row[k] = (md.get("meta", {}) as Dictionary)[k]
		else:
			row["errors"] = md.get("errors", [])
			row["corrupted"] = true
		out.append(row)
	out.sort_custom(func(a, b): return String(a.get("slot", "")) < String(b.get("slot", "")))
	return out

func verify_slot(slot := "save") -> Dictionary:
	var raw := _read_slot_raw(slot)
	return {"ok": bool(raw.get("ok", false)), "slot": slot,
		"reason": String(raw.get("reason", "")), "errors": raw.get("errors", []),
		"migrated": bool(raw.get("migrated", false))}

# ── 删除 / 备份恢复 ────────────────────────────────────────────

func delete_slot(slot := "save", delete_backup := true) -> Dictionary:
	if not _is_valid_slot(slot):
		return {"ok": false, "reason": "invalid_slot"}
	var removed := false
	if FileAccess.file_exists(slot_path(slot)):
		removed = DirAccess.remove_absolute(_global(slot_path(slot))) == OK
	if delete_backup and FileAccess.file_exists(backup_path(slot)):
		DirAccess.remove_absolute(_global(backup_path(slot)))
	return {"ok": true, "slot": slot, "removed": removed}

func restore_backup(slot := "save") -> Dictionary:
	if not _is_valid_slot(slot):
		return {"ok": false, "reason": "invalid_slot"}
	if not FileAccess.file_exists(backup_path(slot)):
		return {"ok": false, "reason": "no_backup", "errors": ["无备份：" + slot]}
	var text := FileAccess.get_file_as_string(backup_path(slot))
	if text == "":
		return {"ok": false, "reason": "empty_backup"}
	var wr := atomic_write_text(slot_path(slot), text)
	return {"ok": bool(wr.get("ok", false)), "slot": slot, "reason": String(wr.get("reason", ""))}

func reset() -> void:
	ready = false
	errors.clear()
	warnings.clear()
	last_path = ""
