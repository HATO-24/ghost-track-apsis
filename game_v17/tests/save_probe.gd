extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2E 最小 probe：SaveService 文件存档
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/save_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；使用 OS 临时目录，不污染用户目录。
# ═══════════════════════════════════════════════════════════════════

const SaveService := preload("res://scripts/core/save_service.gd")
const GameSession := preload("res://scripts/core/game_session.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []
var _root := ""
var _sv = null

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2E PROBE · SaveService 文件存档")
	print("════════════════════════════════════════════════════════════")
	_root = OS.get_temp_dir().path_join("v17_save_probe_%d" % Time.get_ticks_usec())
	_sv = SaveService.new(_root)
	_test_setup()
	_test_save_load()
	_test_overwrite_backup()
	_test_slots_intents()
	_test_atomic()
	_test_corruption()
	_test_migration()
	_test_errors_json()
	_test_cleanup()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 SAVE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 SAVE PROBE FAILED")
		quit(1)
	else:
		print("V17 SAVE PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		if detail != "":
			print("[PASS] %s  %s" % [label, detail])
		else:
			print("[PASS] %s" % label)
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

func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _make_session(orders := true):
	var s = GameSession.new()
	if orders:
		var iss: Dictionary = s.issue_order("hold", "apsis", ["harmattan"], {"k": 1}, {})
		var oid := String(iss.get("order_id", ""))
		s.tick(1.0)
		s.authorize_order(oid, "apsis")
		s.begin_execute_order(oid)
		s.complete_order(oid, {"done": true})
	return s

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

func _payload_of(text: String) -> Dictionary:
	var outer = JSON.parse_string(text)
	if not (outer is Dictionary):
		return {}
	return JSON.parse_string(String((outer as Dictionary).get("payload", ""))) if String((outer as Dictionary).get("payload", "")).length() > 0 else {}

# ═══════════════════════════════════════════════════════════════════
# 1. setup / 路径
# ═══════════════════════════════════════════════════════════════════

func _test_setup() -> void:
	_section_begin("1 setup/路径")
	_ok(bool(_sv.ready), "SaveService ready", str(_sv.errors))
	_ok(DirAccess.open(_sv._global(_root)) != null, "存档目录存在")
	_ok(_root.begins_with(OS.get_temp_dir()), "root 在 OS 临时目录", _root)
	_ok(not _root.begins_with("user://"), "root 非 user:// 真实目录")
	_eq(_sv.slot_path("save"), _root.path_join("save.json"), "slot_path save")
	_eq(_sv.backup_path("save"), _root.path_join("save.json.bak"), "backup_path save")
	_eq(SaveService.VALID_SLOTS, ["save", "menu", "quit", "autosave"], "合法槽位 4 个")
	_ok(not _sv.has_slot("save"), "初始无存档")
	_ok(not _sv.has_backup("save"), "初始无备份")
	_eq((_sv.list_slots() as Array).size(), 0, "初始 list_slots 空")
	# 非法目录 / 空目录
	var bad = SaveService.new("")
	_ok(not bool(bad.ready), "空目录 setup 失败")
	_data_line("setup", "root=OS temp · 槽位 save/menu/quit/autosave")

# ═══════════════════════════════════════════════════════════════════
# 2. 保存 / 读取 / 往返
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("2 保存/读取")
	var s = _make_session()
	var before := JSON.stringify(s.snapshot())
	var w: Dictionary = _sv.save_session(s, "save", {"chapter": "ch1", "location": "L1",
		"meta": {"difficulty": "normal"}})
	_eq(bool(w.get("ok", false)), true, "save_session ok", str(w.get("errors", [])))
	_eq(String(w.get("slot", "")), "save", "save slot")
	_ok(FileAccess.file_exists(_sv.slot_path("save")), "文件存在")
	_ok(int(w.get("bytes", 0)) > 500, "写入字节数", str(w.get("bytes", 0)))
	_ok(String(w.get("checksum", "")) != "", "返回 checksum")
	_ok(not bool(w.get("has_backup", true)), "首次保存无备份")
	var text := _read_text(_sv.slot_path("save"))
	_ok(text != "", "文件非空")
	_ok(not FileAccess.file_exists(_sv.slot_path("save") + ".tmp"), "无残留 .tmp")
	var parsed = JSON.parse_string(text)
	_ok(parsed is Dictionary, "外层 JSON 可解析")
	if parsed is Dictionary:
		_eq(String((parsed as Dictionary).get("schema", "")), "v17.save_file.v1", "外层 schema")
		_ok(String((parsed as Dictionary).get("checksum", "")) != "", "外层 checksum")
		_ok(String((parsed as Dictionary).get("payload", "")) != "", "外层 payload")
	var payload := _payload_of(text)
	_eq(String(payload.get("version", "")), "1.0.0", "payload version")
	_eq(String(payload.get("slot", "")), "save", "payload slot")
	_ok(float(payload.get("created_at", 0.0)) > 0.0, "created_at")
	_ok(float(payload.get("updated_at", 0.0)) > 0.0, "updated_at")
	_ok(String(payload.get("created_iso", "")) != "", "created_iso")
	_eq(String(payload.get("chapter", "")), "ch1", "chapter 元数据")
	_eq(String(payload.get("location", "")), "L1", "location 元数据")
	_eq(String((payload.get("meta", {}) as Dictionary).get("difficulty", "")), "normal", "meta 元数据")
	_ok(String(payload.get("session_save", "")) != "", "session_save 字符串")
	_ok(_sv.has_slot("save"), "has_slot")
	_ok(_sv.verify_slot("save").get("ok", false), "verify_slot ok")
	# 读取
	var lr: Dictionary = _sv.load_session("save")
	_eq(bool(lr.get("ok", false)), true, "load_session ok", str(lr.get("errors", [])))
	_ok(lr.get("session") != null, "load 返回 GameSession")
	var loaded = lr.get("session")
	_ok(JSON.stringify(loaded.snapshot()) == before, "往返 snapshot 一致")
	_ok(bool(loaded.ready), "loaded session ready")
	_eq(bool(lr.get("migrated", true)), false, "当前版本非迁移")
	var meta: Dictionary = lr.get("meta", {})
	_eq(String(meta.get("chapter", "")), "ch1", "读取 chapter")
	_eq(String(meta.get("location", "")), "L1", "读取 location")
	_eq(String(meta.get("version", "")), "1.0.0", "读取 version")
	_near(float(meta.get("created_at", 0.0)), float(w.get("created_at", -1.0)), 1.0e-6,
		"读取 created_at")
	_eq(int(meta.get("order_count", -1)), 1, "读取 order_count")
	var md = _sv.load_metadata("save")
	_ok(bool(md.get("ok", false)), "load_metadata ok")
	_eq(String((md.get("meta", {}) as Dictionary).get("chapter", "")), "ch1", "load_metadata chapter")
	var slots: Array = _sv.list_slots()
	_eq(slots.size(), 1, "list_slots 1")
	_eq(String((slots[0] as Dictionary).get("slot", "")), "save", "list slot=save")
	_ok(bool((slots[0] as Dictionary).get("ok", false)), "list slot ok")
	_data_line("save_load", "bytes=%d 往返 snapshot 一致 · 元数据 chapter/location/meta" % int(w.get("bytes", 0)))

# ═══════════════════════════════════════════════════════════════════
# 3. 覆盖 / 备份
# ═══════════════════════════════════════════════════════════════════

func _test_overwrite_backup() -> void:
	_section_begin("3 覆盖/备份")
	var s = _make_session()
	var old_text := _read_text(_sv.slot_path("save"))
	var old_payload := _payload_of(old_text)
	var w1: Dictionary = _sv.save_session(s, "save", {"chapter": "ch1"})
	_eq(bool(w1.get("ok", false)), true, "首次（覆盖）保存 ok")
	var created1 := float(w1.get("created_at", 0.0))
	_ok(_sv.has_backup("save"), "覆盖后备份存在")
	var bak_text := _read_text(_sv.backup_path("save"))
	_ok(bak_text != "", "备份非空")
	var bak_payload := _payload_of(bak_text)
	_near(float(bak_payload.get("created_at", 0.0)), float(old_payload.get("created_at", 0.0)),
		1.0e-6, "备份为旧内容")
	# 推进会话后再次保存
	s.tick(2.0)
	var w2: Dictionary = _sv.save_session(s, "save", {"chapter": "ch2"})
	_eq(bool(w2.get("ok", false)), true, "二次保存 ok")
	_near(float(w2.get("created_at", 0.0)), created1, 1.0e-6, "覆盖保留 created_at")
	_ok(float(w2.get("updated_at", 0.0)) >= created1, "updated_at 更新")
	_ok(not FileAccess.file_exists(_sv.slot_path("save") + ".tmp"), "无 .tmp")
	var new_payload := _payload_of(_read_text(_sv.slot_path("save")))
	_eq(String(new_payload.get("chapter", "")), "ch2", "主文件新 chapter")
	var bak_payload2 := _payload_of(_read_text(_sv.backup_path("save")))
	_eq(String(bak_payload2.get("chapter", "")), "ch1", "备份仍是上一次")
	# restore_backup 回到 ch1
	var rs: Dictionary = _sv.restore_backup("save")
	_eq(bool(rs.get("ok", false)), true, "restore_backup ok")
	var restored := _payload_of(_read_text(_sv.slot_path("save")))
	_eq(String(restored.get("chapter", "")), "ch1", "恢复后 chapter=ch1")
	var lr: Dictionary = _sv.load_session("save")
	_eq(bool(lr.get("ok", false)), true, "恢复后 load ok")
	_ok(bool(_sv.verify_slot("save").get("ok", false)), "恢复后 verify ok")
	_data_line("overwrite", "created 保留/updated 更新/备份旧档/恢复备份 ok")

# ═══════════════════════════════════════════════════════════════════
# 4. 槽位 / 三色圆点
# ═══════════════════════════════════════════════════════════════════

func _test_slots_intents() -> void:
	_section_begin("4 槽位/三色圆点")
	var s = _make_session()
	# 四个槽位
	for slot in ["save", "menu", "quit", "autosave"]:
		var r: Dictionary = _sv.save_session(s, slot, {"chapter": slot})
		_eq(bool(r.get("ok", false)), true, "槽位保存 " + slot, str(r.get("errors", [])))
		_ok(_sv.has_slot(slot), "槽位文件存在 " + slot)
		_eq(String(r.get("slot", "")), slot, "返回 slot " + slot)
	var slots: Array = _sv.list_slots()
	_eq(slots.size(), 4, "list_slots 4")
	for raw in slots:
		_ok(bool((raw as Dictionary).get("ok", false)),
			"list slot ok: " + String((raw as Dictionary).get("slot", "")))
	# 意图：save → save, save_and_menu → menu, save_and_quit → quit
	var i1: Dictionary = _sv.save_with_intent(s, "save", {})
	_eq(bool(i1.get("ok", false)), true, "intent save ok")
	_eq(String(i1.get("slot", "")), "save", "intent save slot")
	_eq(bool(i1.get("should_exit", true)), false, "save 不退出")
	_eq(bool(i1.get("should_show_menu", true)), false, "save 不切菜单")
	var i2: Dictionary = _sv.save_and_menu(s, {})
	_eq(bool(i2.get("ok", false)), true, "save_and_menu ok")
	_eq(String(i2.get("slot", "")), "menu", "save_and_menu → menu 槽")
	_eq(String(i2.get("intent", "")), "save_and_menu", "intent 记录")
	_eq(bool(i2.get("should_exit", true)), false, "save_and_menu 不退出")
	_eq(bool(i2.get("should_show_menu", false)), true, "save_and_menu 返回菜单意图")
	var i3: Dictionary = _sv.save_and_quit(s, {})
	_eq(bool(i3.get("ok", false)), true, "save_and_quit ok")
	_eq(String(i3.get("slot", "")), "quit", "save_and_quit → quit 槽")
	_eq(bool(i3.get("should_exit", true)), false, "save_and_quit 不直接退出")
	_ok(String(i3.get("note", "")).contains("不直接退出"), "note 说明不直接退出")
	var bad: Dictionary = _sv.save_with_intent(s, "no_such_intent", {})
	_eq(bool(bad.get("ok", true)), false, "未知 intent 拒绝")
	_eq(String(bad.get("reason", "")), "invalid_intent", "invalid_intent")
	# 各槽内容独立
	var m1 := _payload_of(_read_text(_sv.slot_path("save")))
	var m2 := _payload_of(_read_text(_sv.slot_path("menu")))
	_eq(String(m2.get("slot", "")), "menu", "menu 槽内容 slot=menu")
	_ok(String(m2.get("session_save", "")) != "", "menu 槽含 session_save")
	_eq(String(m1.get("chapter", "")), "", "intent save 覆盖后 chapter 空")
	_data_line("slots_intents", "4 槽 · save/menu/quit 意图只写文件不退出")

# ═══════════════════════════════════════════════════════════════════
# 5. 原子性
# ═══════════════════════════════════════════════════════════════════

func _test_atomic() -> void:
	_section_begin("5 原子性")
	var s = _make_session()
	# 手工残留 tmp，保存应清理
	var tmp: String = _sv.slot_path("autosave") + ".tmp"
	_write_text(tmp, "LEFTOVER")
	_ok(FileAccess.file_exists(tmp), "预置残留 tmp")
	var w: Dictionary = _sv.save_session(s, "autosave", {})
	_eq(bool(w.get("ok", false)), true, "残留 tmp 时保存 ok")
	_ok(not FileAccess.file_exists(tmp), "保存后 tmp 清理")
	# 再次覆盖：备份内容为旧、主内容为新
	var old_payload := _payload_of(_read_text(_sv.slot_path("autosave")))
	s.tick(3.0)
	var w2: Dictionary = _sv.save_session(s, "autosave", {"chapter": "new"})
	_eq(bool(w2.get("ok", false)), true, "覆盖保存 ok")
	var new_payload := _payload_of(_read_text(_sv.slot_path("autosave")))
	_ok(float(new_payload.get("t_s", -1.0)) > float(old_payload.get("t_s", -1.0)), "主文件已更新")
	var bak := _payload_of(_read_text(_sv.backup_path("autosave")))
	_near(float(bak.get("t_s", -1.0)), float(old_payload.get("t_s", -1.0)), 1.0e-6,
		"备份为旧状态")
	_ok(not FileAccess.file_exists(tmp), "覆盖后无 tmp")
	# 原子写文本 API 校验
	var aw: Dictionary = _sv.atomic_write_text(_sv.slot_path("autosave"), "abc")
	_eq(bool(aw.get("ok", false)), true, "atomic_write_text ok")
	_eq(_read_text(_sv.slot_path("autosave")), "abc", "atomic 写内容")
	_ok(_payload_of(_read_text(_sv.backup_path("autosave"))).size() > 0, "atomic 前备份旧内容")
	_data_line("atomic", "tmp 清理/回读校验/备份旧档/主文件新内容")

# ═══════════════════════════════════════════════════════════════════
# 6. 损坏检测
# ═══════════════════════════════════════════════════════════════════

func _test_corruption() -> void:
	_section_begin("6 损坏检测")
	# 6.1 篡改 payload（checksum 不匹配）
	var s = _make_session()
	_sv.save_session(s, "quit", {})
	var text := _read_text(_sv.slot_path("quit"))
	var tampered := text.replace("session_save", "session_savX")
	_ok(tampered != text, "构造篡改文本")
	_write_text(_sv.slot_path("quit"), tampered)
	var r1: Dictionary = _sv.load_session("quit")
	_eq(bool(r1.get("ok", true)), false, "篡改后 load 失败")
	_eq(String(r1.get("reason", "")), "corrupted", "篡改 reason corrupted")
	_ok((r1.get("errors", []) as Array).size() > 0, "篡改 errors 非空")
	_eq(r1.get("session"), null, "篡改不返回 session")
	_ok(not _sv.verify_slot("quit").get("ok", true), "篡改 verify false")
	var md: Dictionary = _sv.load_metadata("quit")
	_eq(bool(md.get("ok", true)), false, "篡改 metadata 失败")
	# list_slots 标记损坏
	var list: Array = _sv.list_slots()
	var quit_row := {}
	for raw in list:
		if String((raw as Dictionary).get("slot", "")) == "quit":
			quit_row = raw
	_ok(not quit_row.is_empty(), "list 含 quit")
	if not quit_row.is_empty():
		_ok(bool(quit_row.get("corrupted", false)), "list 标记 corrupted")
	# 6.2 截断 / 非法 JSON
	_sv.save_session(s, "autosave", {})
	_write_text(_sv.slot_path("autosave"), "{\"schema\":")
	var r2: Dictionary = _sv.load_session("autosave")
	_eq(bool(r2.get("ok", true)), false, "非法 JSON load 失败")
	# 6.3 空文件
	_sv.save_session(s, "menu", {})
	_write_text(_sv.slot_path("menu"), "")
	var r3: Dictionary = _sv.load_session("menu")
	_eq(bool(r3.get("ok", true)), false, "空文件 load 失败")
	_eq(String(r3.get("reason", "empty_file")), "empty_file", "空文件 reason")
	# 6.4 缺槽位
	var r4: Dictionary = _sv.load_session("save")
	# save 可能已被覆写；用删除后的槽位测试
	_sv.delete_slot("menu")
	var r5: Dictionary = _sv.load_session("menu")
	_eq(bool(r5.get("ok", true)), false, "缺槽位 load 失败")
	_eq(String(r5.get("reason", "")), "missing_slot", "缺槽位 reason")
	# 6.5 外层 schema 错误
	_sv.save_session(s, "menu", {})
	var outer_err := _read_text(_sv.slot_path("menu")).replace("v17.save_file.v1", "v17.bad.v1")
	_write_text(_sv.slot_path("menu"), outer_err)
	var r6: Dictionary = _sv.load_session("menu")
	_eq(bool(r6.get("ok", true)), false, "外层 schema 错 load 失败")
	# 6.6 损坏文件不能静默成空 session
	_ok(not bool(r1.get("ok", false)) and r1.get("session") == null, "损坏无静默 session")
	_data_line("corruption", "篡改/非法 JSON/空文件/缺槽位/外层 schema 均失败不静默")

# ═══════════════════════════════════════════════════════════════════
# 7. 版本迁移
# ═══════════════════════════════════════════════════════════════════

func _test_migration() -> void:
	_section_begin("7 版本迁移")
	var s = _make_session()
	var before := JSON.stringify(s.snapshot())
	# 7.1 0.9.0 旧格式：session_state
	var legacy := {
		"schema": "v17.session_payload.v1", "version": "0.9.0", "slot": "save",
		"created_at": 1.0, "updated_at": 1.0, "chapter": "old", "location": "legacy",
		"session_state": s.save_state(),
	}
	var text: String = _sv.encode_file(legacy)
	_write_text(_sv.slot_path("save"), text)
	var md: Dictionary = _sv.load_metadata("save")
	_eq(bool(md.get("ok", false)), true, "0.9 load_metadata ok", str(md.get("errors", [])))
	_eq(bool(md.get("migrated", false)), true, "0.9 标记 migrated")
	_eq(String((md.get("meta", {}) as Dictionary).get("version", "")), "1.0.0", "迁移后 version 1.0.0")
	var lr: Dictionary = _sv.load_session("save")
	_eq(bool(lr.get("ok", false)), true, "0.9 load_session ok", str(lr.get("errors", [])))
	_eq(bool(lr.get("migrated", false)), true, "load 标记 migrated")
	_ok(lr.get("session") != null, "0.9 返回 session")
	if lr.get("session") != null:
		_ok(JSON.stringify(lr.get("session").snapshot()) == before, "0.9 迁移后 snapshot 一致")
	_ok(bool(_sv.verify_slot("save").get("ok", false)), "迁移后可 verify")
	# 7.2 未来版本拒绝
	var future := {"schema": "v17.session_payload.v1", "version": "9.0.0", "slot": "save",
		"session_save": s.save_state()}
	_write_text(_sv.slot_path("save"), _sv.encode_file(future))
	var lr2: Dictionary = _sv.load_session("save")
	_eq(bool(lr2.get("ok", true)), false, "未来版本 load 拒绝")
	_eq(String(lr2.get("reason", "")), "unsupported_future_version", "future reason")
	_eq(lr2.get("session"), null, "未来版本不返回 session")
	# 7.3 未知旧版本拒绝
	var old := {"schema": "v17.session_payload.v1", "version": "0.5.0", "slot": "save",
		"session_save": s.save_state()}
	_write_text(_sv.slot_path("save"), _sv.encode_file(old))
	var lr3: Dictionary = _sv.load_session("save")
	_eq(bool(lr3.get("ok", true)), false, "未知旧版本 load 拒绝")
	_eq(String(lr3.get("reason", "")), "unsupported_old_version", "old reason")
	# 7.4 缺 version 按 0.9 迁移骨架
	var nover := {"schema": "v17.session_payload.v1", "slot": "save",
		"session_state": s.save_state()}
	_write_text(_sv.slot_path("save"), _sv.encode_file(nover))
	var lr4: Dictionary = _sv.load_session("save")
	_eq(bool(lr4.get("ok", false)), true, "缺 version 按 0.9 迁移 ok")
	if lr4.get("session") != null:
		_ok(JSON.stringify(lr4.get("session").snapshot()) == before, "缺 version 迁移一致")
	_data_line("migration", "0.9→1.0 迁移 · 未来版本/未知旧版本拒绝 · 缺 version 骨架")

# ═══════════════════════════════════════════════════════════════════
# 8. 错误 / JSON
# ═══════════════════════════════════════════════════════════════════

func _test_errors_json() -> void:
	_section_begin("8 错误/JSON")
	var s = _make_session()
	# 非法槽位
	var bad_slot: Dictionary = _sv.save_session(s, "bad_slot", {})
	_eq(bool(bad_slot.get("ok", true)), false, "非法槽位保存拒绝")
	_eq(String(bad_slot.get("reason", "")), "invalid_slot", "invalid_slot")
	var bad_load: Dictionary = _sv.load_session("bad_slot")
	_eq(bool(bad_load.get("ok", true)), false, "非法槽位读取拒绝")
	# 无 session / 无效 session
	var no_sess: Dictionary = _sv.save_session(null, "save", {})
	_eq(bool(no_sess.get("ok", true)), false, "null session 保存拒绝")
	var invalid_sess: Dictionary = _sv.save_session({"x": 1}, "save", {})
	_eq(bool(invalid_sess.get("ok", true)), false, "非 GameSession 保存拒绝")
	# 删除
	var w: Dictionary = _sv.save_session(s, "save", {})
	_eq(bool(w.get("ok", false)), true, "删除前保存 ok")
	var del: Dictionary = _sv.delete_slot("save")
	_eq(bool(del.get("ok", false)), true, "delete_slot ok")
	_ok(not _sv.has_slot("save"), "删除后无主文件")
	_ok(not _sv.has_backup("save"), "删除后无备份")
	_ok(not FileAccess.file_exists(_sv.slot_path("save")), "删除后文件不存在")
	# 恢复无备份（先删 quit 主文件与备份）
	_sv.delete_slot("quit")
	var rb: Dictionary = _sv.restore_backup("quit")
	_eq(bool(rb.get("ok", true)), false, "无备份 restore 拒绝")
	# encode/decode / checksum
	var payload := {"schema": "v17.session_payload.v1", "version": "1.0.0",
		"session_save": "x", "slot": "save"}
	var enc: String = _sv.encode_file(payload)
	var dec: Dictionary = _sv.decode_file(enc)
	_eq(bool(dec.get("ok", false)), true, "encode/decode ok")
	var dec_bad: Dictionary = _sv.decode_file(enc.replace("session_save", "session_savX"))
	_eq(bool(dec_bad.get("ok", true)), false, "篡改 decode 失败")
	# 文件 JSON 读取
	var slots: Array = _sv.list_slots()
	_ok(JSON.stringify(slots).length() > 2, "list_slots JSON")
	_data_line("errors_json", "非法槽位/无效 session/删除/无备份/encode-decode 校验")

# ═══════════════════════════════════════════════════════════════════
# 9. 清理
# ═══════════════════════════════════════════════════════════════════

func _test_cleanup() -> void:
	_section_begin("9 清理")
	var s = _make_session()
	_sv.save_session(s, "save", {})
	for slot in SaveService.VALID_SLOTS:
		_sv.delete_slot(slot)
	_eq((_sv.list_slots() as Array).size(), 0, "清理后无槽位")
	# 递归删除临时 root
	var g: String = _sv._global(_root)
	var files := DirAccess.get_files_at(g)
	for raw in files:
		DirAccess.remove_absolute(g + "/" + String(raw))
	var err := DirAccess.remove_absolute(g)
	_ok(err == OK, "删除临时目录", "err=%d" % err)
	_ok(DirAccess.open(g) == null, "临时目录已不存在")
	_data_line("cleanup", "槽位删除 · 临时目录删除（不污染用户目录）")
