extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3S 最小 probe：PreludeScenario（序章专用场景内容）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/prelude_scenario_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 world/UI。
# ═══════════════════════════════════════════════════════════════════

const PreludeScenario := preload("res://scripts/core/prelude_scenario.gd")
const GameSession := preload("res://scripts/core/game_session.gd")

const ENTITIES := ["apsis", "harmattan", "ferry", "watchtower", "deepwell",
	"ceres_2", "av_4412", "l1_station", "chronos"]
const EXTRA_PROFILES := ["ferry_prologue", "watchtower_prologue",
	"deepwell_prologue", "av_4412"]
const TRIGGERS := ["ceres_no_reply", "av4412_arrival", "chronos_unrest"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3S PROBE · PreludeScenario")
	print("════════════════════════════════════════════════════════════")
	_test_entities()
	_test_profiles_refs()
	_test_codes_triggers()
	_test_facility_boot()
	_test_invalid_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 PRELUDE SCENARIO PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 PRELUDE SCENARIO PROBE FAILED")
		quit(1)
	else:
		print("V17 PRELUDE SCENARIO PROBE OK")
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

func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _new_scenario() -> Object:
	var p = PreludeScenario.new()
	_ok(bool(p.ready), "PreludeScenario ready", str(p.errors))
	return p

func _base(p) -> Dictionary:
	return (p.to_dict() as Dictionary).duplicate(true)

func _bad(p) -> Dictionary:
	return _base(p)

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

# ═══════════════════════════════════════════════════════════════════
# 1. entities
# ═══════════════════════════════════════════════════════════════════

func _test_entities() -> void:
	_section_begin("1 entities")
	var p = _new_scenario()
	_eq((p.entity_ids() as Array).size(), 9, "9 entities")
	for eid in ENTITIES:
		_ok(str(eid) in p.entity_ids(), "含 entity " + str(eid))
		var e: Dictionary = p.entity(str(eid))
		_ok(not e.is_empty(), "entity 存在 " + str(eid))
		for k in ["id", "batch", "kind", "side", "identity", "transponder_profile"]:
			_ok(str(e.get(k, "")) != "", "%s.%s 非空" % [eid, k])
		_ok((e.get("pos_km", []) as Array).size() == 3, "%s pos 3" % eid)
		_ok((e.get("vel_kmps", []) as Array).size() == 3, "%s vel 3" % eid)
		for x in (e.get("pos_km", []) as Array):
			_ok(is_finite(float(x)), "%s pos finite" % eid)
		for v in (e.get("vel_kmps", []) as Array):
			_ok(is_finite(float(v)), "%s vel finite" % eid)
		_ok(e.get("light_capable") is bool, "%s light_capable bool" % eid)
		_ok(str(e.get("kind", "")) in ["ship", "station", "port", "fuel", "tank", "otc", "relay"],
			"%s kind" % eid)
	# 明确不得以 Harmattan 代替 Ceres-2
	var c2: Dictionary = p.entity("ceres_2")
	_eq(str(c2.get("batch", "")), "FRC-OW-CER2-0417-C", "Ceres-2 batch")
	_eq(str(c2.get("registration", "")), "FRC-OW-CER2-0417-C", "Ceres-2 registration")
	_eq(str(c2.get("transponder_code", "")), "0417", "Ceres-2 transponder 0417")
	_eq(str(c2.get("emergency_code", "")), "7600", "Ceres-2 emergency 7600")
	_eq((c2.get("light_codes", []) as Array), ["L3-0417", "L4-0417"], "Ceres-2 light codes")
	_ok(str(c2.get("id", "")) != "harmattan", "Ceres-2 不是 Harmattan")
	_eq(str(c2.get("kind", "")), "ship", "Ceres-2 ship")
	_eq(str(p.entity("av_4412").get("batch", "")), "UEG-AV-4412", "AV-4412 batch")
	_eq(str(p.entity("av_4412").get("side", "")), "ueg", "AV-4412 side ueg")
	_eq(str(p.entity("l1_station").get("facility_id", "")), "L1-05", "l1_station facility")
	_eq(str(p.entity("chronos").get("facility_id", "")), "L1-05", "chronos facility")
	# 唯一 id
	var ids: Dictionary = {}
	for eid2 in p.entity_ids():
		ids[str(eid2)] = true
	_eq(ids.size(), 9, "entity_ids 唯一")
	var sum: Dictionary = p.summary()
	_eq(int(sum.get("entities", 0)), 9, "summary entities 9")
	_eq(int(sum.get("facility_bound", 0)), 2, "summary facility_bound 2")
	_eq(bool((sum.get("writes", {}) as Dictionary).get("world", true)), false, "不写 world")
	_ok(bool(p.check_contracts().get("ok", false)), "contracts ok")
	# triggers_for_event
	_eq((p.triggers_for_event("no_reply") as Array).size(), 1, "triggers_for_event no_reply")
	_eq((p.triggers_for_event("nope") as Array).size(), 0, "triggers_for_event 未知空")
	_data_line("entities", "9 实体（含 ceres_2/av_4412/chronos） · batch/kind/side/identity/pos/vel/light_capable")

# ═══════════════════════════════════════════════════════════════════
# 2. transponder profiles / refs
# ═══════════════════════════════════════════════════════════════════

func _test_profiles_refs() -> void:
	_section_begin("2 profiles/refs")
	var p = _new_scenario()
	var sum: Dictionary = p.summary()
	_eq(int(sum.get("profiles", 0)), 4, "4 序章补充 profiles")
	_eq(int(sum.get("merged_profiles", 0)), 10, "合并 10 profiles")
	for pid in EXTRA_PROFILES:
		_ok(str(pid) in p.profile_ids(), "含补充 profile " + str(pid))
		var pr: Dictionary = p.profile(str(pid))
		_ok(not pr.is_empty(), "profile 存在 " + str(pid))
		_ok(str(pr.get("transponder_code", "")) != "", "profile code " + str(pid))
		_ok(str(pr.get("registration_code", "")) != "", "profile reg " + str(pid))
		_ok((pr.get("modes", []) as Array).size() > 0, "profile modes " + str(pid))
		_ok(str(pr.get("default_mode", "")) in (pr.get("modes", []) as Array),
			"profile default mode " + str(pid))
		_ok(str(pr.get("status", "")) in ["normal", "off", "faulty", "captured",
			"spoofed", "crypto_fail", "expired", "no_reply", "wrong_code"],
			"profile status " + str(pid))
	# 外部引用 profiles 也在 merged
	for pid2 in ["apsis", "harmattan", "l1_station", "chronos", "ceres_2_demo"]:
		_ok(str(pid2) in p.profile_ids(), "含外部 profile " + str(pid2))
	# Ceres-2 故障/无应答
	var c2p: Dictionary = p.profile("ceres_2_demo")
	_eq(str(c2p.get("status", "")), "faulty", "ceres profile faulty")
	_eq(str(c2p.get("transponder_code", "")), "0417", "ceres profile txp 0417")
	_eq(str(c2p.get("registration_code", "")), "FRC-OW-CER2-0417-C", "ceres profile reg")
	_eq(str(c2p.get("emergency_code", "")), "7600", "ceres profile emergency 7600")
	_eq((c2p.get("light_codes", []) as Array), ["L3-0417", "L4-0417"], "ceres profile light codes")
	_eq(str((c2p.get("trigger_map", {}) as Dictionary).get("no_reply", "")),
		"ceres_no_reply", "ceres no_reply trigger")
	# AV-4412 mode5/crypto/military
	var av: Dictionary = p.profile("av_4412")
	_ok((av.get("modes", []) as Array).has("mode_5"), "AV modes 含 mode_5")
	_eq(str(av.get("default_mode", "")), "mode_5", "AV default mode_5")
	_eq(bool(av.get("military", false)), true, "AV military")
	_ok(float((av.get("crypto", {}) as Dictionary).get("epoch", 0)) >= 1,
		"AV crypto epoch")
	_eq(bool((av.get("crypto", {}) as Dictionary).get("valid", false)), true,
		"AV crypto valid")
	# station beacon
	for pid3 in ["l1_station", "chronos"]:
		_ok((p.profile(pid3).get("modes", []) as Array).has("station_beacon"),
			pid3 + " station_beacon")
		_ok(bool((p.profile(pid3).get("broadcast", {}) as Dictionary).get("enabled", false)),
			pid3 + " broadcast enabled")
	# 实体 profile 引用有效
	for eid in ENTITIES:
		var pid4 := str(p.entity(eid).get("transponder_profile", ""))
		_ok(str(pid4) in p.profile_ids(), "entity %s profile 有效" % eid)
	# refs 内容
	var refs: Dictionary = p.summary().get("refs", {})
	for k in ["facilities_content", "transponders_content", "light_codes_content"]:
		_ok(str(refs.get(k, "")) != "", "refs " + k)
		_ok(FileAccess.file_exists(str(refs.get(k, ""))), "refs 文件存在 " + k)
	_ok(FileAccess.file_exists("res://framework/content/scenario_prologue.json"),
		"场景内容文件存在")
	# 缺失 refs 内容 → errors
	var bad := _bad(p)
	var bad_refs: Dictionary = (bad.get("refs", {}) as Dictionary).duplicate(true)
	bad_refs["transponders_content"] = "/no/such.json"
	bad["refs"] = bad_refs
	_ok(not bool(p.validate(bad).get("ok", true)), "缺 transponder 内容拒绝")
	_ok(not bool(p.load_data(bad)), "非法 refs load 失败")
	_eq((p.entity_ids() as Array).size(), 9, "失败后旧状态保留")
	_data_line("profiles", "4 补充+6 外部=10 · ceres faulty · AV mode5/crypto/military · station beacon")

# ═══════════════════════════════════════════════════════════════════
# 3. light codes / triggers
# ═══════════════════════════════════════════════════════════════════

func _test_codes_triggers() -> void:
	_section_begin("3 codes/triggers")
	var p = _new_scenario()
	# 灯语码：谷神-2 应急 + 通用询问/确认
	var codes: Array = p.light_code_ids()
	_ok(codes.size() >= 6, "码 >=6", str(codes.size()))
	var has_emergency := false
	var has_query := false
	for cid in codes:
		var c: Dictionary = p.light_code(str(cid))
		_ok(str(c.get("code", "")).length() == 4, "码四位 " + str(cid))
		_ok(str(c.get("mode", "")) in ["blink", "steady"], "码 mode " + str(cid))
		_ok(str(c.get("meaning", "")) != "", "码 meaning " + str(cid))
		if str(c.get("id", "")).contains("GUSHEN2"):
			has_emergency = true
		if str(c.get("id", "")).contains("QUERY"):
			has_query = true
	_ok(has_emergency, "含谷神-2 应急码")
	_ok(has_query, "含通用询问/确认")
	_ok("GUSHEN2_REQ" in codes, "GUSHEN2_REQ")
	_ok("GUSHEN2_MAYDAY" in codes, "GUSHEN2_MAYDAY")
	_ok("QUERY_STATUS" in codes, "QUERY_STATUS")
	_ok("QUERY_ACK" in codes, "QUERY_ACK")
	_ok("APPROACH_REQ" in codes, "含外部通用码 APPROACH_REQ")
	# 触发
	_eq((p.trigger_ids() as Array).size(), 3, "3 triggers")
	for tid in TRIGGERS:
		_ok(str(tid) in p.trigger_ids(), "含 trigger " + str(tid))
		var tr: Dictionary = p.trigger(str(tid))
		_ok(not tr.is_empty(), "trigger 存在 " + str(tid))
		_ok(str(tr.get("event", "")) != "", "trigger event " + str(tid))
		_ok(str(tr.get("target_id", "")) in ENTITIES, "trigger target 存在 " + str(tid))
		_ok(str(tr.get("story_flag", "")) != "", "trigger story_flag " + str(tid))
		if str(tr.get("light_code", "")) != "":
			_ok(str(tr.get("light_code", "")) in codes, "trigger light_code 存在 " + str(tid))
	_eq(str(p.trigger("ceres_no_reply").get("target_id", "")), "ceres_2",
		"ceres_no_reply target")
	_eq(str(p.trigger("ceres_no_reply").get("event", "")), "no_reply",
		"ceres_no_reply event")
	_eq(str(p.trigger("av4412_arrival").get("target_id", "")), "av_4412",
		"av4412_arrival target")
	_eq(str(p.trigger("av4412_arrival").get("event", "")), "entity_arrival",
		"av4412_arrival event")
	_eq(str(p.trigger("chronos_unrest").get("target_id", "")), "chronos",
		"chronos_unrest target")
	_eq(str(p.trigger("chronos_unrest").get("event", "")), "light_signal",
		"chronos_unrest event")
	_eq(str(p.trigger("chronos_unrest").get("light_code", "")), "GUSHEN2_MAYDAY",
		"chronos_unrest light_code")
	# 重复触发 id / 缺失 light_code / 缺失 target
	var bad_tid := _bad(p)
	((bad_tid.get("triggers", []) as Array)[1] as Dictionary)["trigger_id"] = "ceres_no_reply"
	_ok(not bool(p.validate(bad_tid).get("ok", true)), "重复 trigger_id 拒绝")
	var bad_light := _bad(p)
	((bad_light.get("triggers", []) as Array)[0] as Dictionary)["light_code"] = "NOPE_CODE"
	_ok(not bool(p.validate(bad_light).get("ok", true)), "trigger light_code 缺失拒绝")
	var bad_target := _bad(p)
	((bad_target.get("triggers", []) as Array)[0] as Dictionary)["target_id"] = "nope"
	_ok(not bool(p.validate(bad_target).get("ok", true)), "trigger target 缺失拒绝")
	var bad_flag := _bad(p)
	((bad_flag.get("triggers", []) as Array)[0] as Dictionary)["story_flag"] = ""
	_ok(not bool(p.validate(bad_flag).get("ok", true)), "trigger story_flag 缺失拒绝")
	# 灯语码非法
	var bad_code := _bad(p)
	((bad_code.get("light_codes", {}) as Dictionary)["codes"] as Array)[0]["code"] = "12"
	_ok(not bool(p.validate(bad_code).get("ok", true)), "非四位灯语码拒绝")
	var bad_dup_code := _bad(p)
	((bad_dup_code.get("light_codes", {}) as Dictionary)["codes"] as Array)[1]["id"] = \
		str(((bad_dup_code.get("light_codes", {}) as Dictionary)["codes"] as Array)[0]["id"])
	_ok(not bool(p.validate(bad_dup_code).get("ok", true)), "重复灯语码 id 拒绝")
	_data_line("codes/triggers", "13 合并码 · 谷神-2/通用询问确认 · 3 triggers（ceres/av4412/chronos）")

# ═══════════════════════════════════════════════════════════════════
# 4. facility / boot config / GameSession
# ═══════════════════════════════════════════════════════════════════

func _test_facility_boot() -> void:
	_section_begin("4 facility/boot")
	var p = _new_scenario()
	var fac: Dictionary = p.facility_for_entity("chronos")
	_ok(not fac.is_empty(), "chronos facility")
	_eq(str(fac.get("facility_id", "")), "L1-05", "facility L1-05")
	_eq(str(fac.get("name", "")), "Chronos", "facility name Chronos")
	_eq(str(p.facility_for_entity("l1_station").get("facility_id", "")), "L1-05",
		"l1_station facility L1-05")
	_ok(p.facility_for_entity("apsis").is_empty(), "apsis 无 facility")
	# boot config 结构
	var cfg: Dictionary = p.boot_config()
	_ok(not cfg.is_empty(), "boot config 非空")
	_ok(cfg.get("entities") is Array, "boot entities")
	_eq((cfg.get("entities", []) as Array).size(), 9, "boot 9 entities")
	_ok(cfg.get("facility_registry") is Dictionary, "boot facility_registry")
	_ok(cfg.get("transponder_service") is Dictionary, "boot transponder_service")
	_ok((cfg.get("transponder_service", {}) as Dictionary).get("content") is Dictionary,
		"boot transponder content")
	var tprof: Array = ((cfg.get("transponder_service", {}) as Dictionary).get(
		"content", {}) as Dictionary).get("profiles", []) as Array
	_eq(tprof.size(), 10, "boot 10 profiles")
	_ok(cfg.get("signal_service") is Dictionary, "boot signal_service")
	var stargets: Array = (cfg.get("signal_service", {}) as Dictionary).get("targets", [])
	_eq(stargets.size(), 9, "boot 9 signal targets")
	_ok((cfg.get("signal_service", {}) as Dictionary).get("codes_content") is Dictionary,
		"boot signal codes")
	var prelude: Dictionary = cfg.get("prelude", {})
	_eq((prelude.get("trigger_ids", []) as Array).size(), 3, "boot prelude trigger ids")
	_eq((prelude.get("light_code_ids", []) as Array).size() >= 6, true,
		"boot prelude code ids")
	# GameSession 可用 boot config 启动
	var gs = GameSession.new(cfg)
	_ok(bool(gs.ready), "GameSession boot ready", str(gs.errors))
	_eq((gs.world.entities_sorted() as Array).size(), 9, "GS world 9 entities")
	for eid in ENTITIES:
		_ok(gs.world.has_entity(str(eid)), "GS 实体 " + str(eid))
	_ok(gs.transponder_service != null, "GS transponder")
	_eq((gs.transponder_service.profile_ids() as Array).size(), 10, "GS 10 profiles")
	_ok(gs.signal_service != null, "GS signal")
	_eq((gs.signal_target_ids() as Array).size(), 9, "GS 9 signal targets")
	_eq(bool(gs.check_contracts().get("ok", false)), true, "GS contracts ok")
	# Ceres-2 故障 / AV-4412 mode5 在 boot 内容中真实存在
	var c2: Dictionary = gs.transponder_service.profile("ceres_2_demo")
	_eq(str(c2.get("entity_id", "")), "ceres_2", "GS ceres profile entity")
	_eq(str(c2.get("status", "")), "faulty", "GS ceres faulty")
	_ok((gs.transponder_service.profile("av_4412").get("modes", []) as Array).has("mode_5"),
		"GS AV mode5")
	# facility 注册表
	_eq(str(gs.facility_lookup("L1-05").get("facility", {}).get("name", "")), "Chronos",
		"GS facility L1-05")
	# boot 确定性
	var cfg2: Dictionary = p.boot_config()
	_ok(_norm(cfg) == _norm(cfg2), "boot config 确定")
	_data_line("facility/boot", "L1-05 绑定 · boot 9 entities/10 profiles/9 targets · GameSession 可启动")

# ═══════════════════════════════════════════════════════════════════
# 5. 非法内容 / JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_invalid_json() -> void:
	_section_begin("5 非法/JSON")
	var p = _new_scenario()
	var before := _norm(p.to_dict())
	var ids_before: Array = p.entity_ids()
	# 非法内容矩阵
	var bads: Array = []
	var b1 := _bad(p); b1["schema"] = "bad"; bads.append(b1)
	var b2 := _bad(p); b2["version"] = "9.9.9"; bads.append(b2)
	var b3 := _bad(p); b3["entities"] = []; bads.append(b3)
	var b4 := _bad(p); ((b4["entities"] as Array)[1] as Dictionary)["id"] = "apsis"; bads.append(b4)
	var b5 := _bad(p); ((b5["entities"] as Array)[0] as Dictionary)["kind"] = "bogus"; bads.append(b5)
	var b6 := _bad(p); ((b6["entities"] as Array)[0] as Dictionary)["side"] = "bogus"; bads.append(b6)
	var b7 := _bad(p); ((b7["entities"] as Array)[0] as Dictionary)["identity"] = "bogus"; bads.append(b7)
	var b8 := _bad(p); ((b8["entities"] as Array)[0] as Dictionary)["pos_km"] = [0.0, 0.0]; bads.append(b8)
	var b9 := _bad(p); ((b9["entities"] as Array)[0] as Dictionary)["pos_km"] = [NAN, 0.0, 0.0]; bads.append(b9)
	var b10 := _bad(p); ((b10["entities"] as Array)[0] as Dictionary)["light_capable"] = "yes"; bads.append(b10)
	var b11 := _bad(p); ((b11["entities"] as Array)[0] as Dictionary)["transponder_profile"] = "nope"; bads.append(b11)
	var b12 := _bad(p); ((b12["entities"] as Array)[7] as Dictionary)["facility_id"] = "NOPE"; bads.append(b12)
	var b13 := _bad(p); ((b13["transponder_profiles"] as Array)[0] as Dictionary)["profile_id"] = "av_4412"; bads.append(b13)
	var b14 := _bad(p); ((b14["transponder_profiles"] as Array)[0] as Dictionary)["modes"] = ["bogus"]; bads.append(b14)
	var b15 := _bad(p); ((b15["transponder_profiles"] as Array)[0] as Dictionary)["status"] = "bogus"; bads.append(b15)
	var b16 := _bad(p); (b16["refs"] as Dictionary)["facilities_content"] = "/no/such.json"; bads.append(b16)
	var b17 := _bad(p); (b17["refs"] as Dictionary)["light_codes_content"] = "/no/such.json"; bads.append(b17)
	var b18 := _bad(p); ((b18["transponder_profiles"] as Array)[0] as Dictionary)["entity_id"] = ""; bads.append(b18)
	for i in range(bads.size()):
		var brok: bool = p.load_data(bads[i])
		_ok(not brok, "非法内容拒绝 #" + str(i))
	_eq(_norm(p.to_dict()), before, "非法内容不改场景")
	_eq(p.entity_ids(), ids_before, "非法内容不改 entity_ids")
	_ok(bool(p.ready), "非法内容后仍 ready")
	# 非对象/空
	_ok(not bool(p.load_data("x")), "字符串内容拒绝")
	_ok(not bool(p.load_data([])), "数组内容拒绝")
	_ok(not bool(p.load_data({})), "空对象拒绝")
	# JSON
	var j: String = str(p.to_json())
	_ok(JSON.parse_string(j) is Dictionary, "to_json 可解析")
	var d: Dictionary = p.to_dict()
	_eq(str(d.get("schema", "")), "v17.prelude_scenario.v1", "to_dict schema")
	_eq((d.get("entities", []) as Array).size(), 9, "to_dict entities 9")
	_ok(str(d.get("source", "")) != "", "to_dict source")
	# 往返
	var p2 = _new_scenario()
	_ok(bool(p2.load_data(d)), "load_data(to_dict) ok")
	_eq(_norm(p2.to_dict()), _norm(d), "to_dict 往返一致")
	_eq(p2.entity_ids(), p.entity_ids(), "往返 entity_ids")
	_ok(_norm(p2.boot_config()) == _norm(p.boot_config()), "往返 boot config 一致")
	# 确定性
	var a = _new_scenario()
	var b = _new_scenario()
	_eq(_norm(a.to_dict()), _norm(b.to_dict()), "两次加载一致")
	_eq(a.to_json(), b.to_json(), "to_json 一致")
	_ok(_norm(a.boot_config()) == _norm(b.boot_config()), "两次 boot config 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "contracts ok 2")
	_data_line("invalid/json", "18 类非法内容原子拒绝 · to_dict/to_json 往返 · 两次加载/boot 确定")

