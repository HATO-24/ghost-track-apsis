extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3P 最小 probe：TransponderService（应答机行为层）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/transponder_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 world/TrackTable/UI。
# ═══════════════════════════════════════════════════════════════════

const TransponderService := preload("res://scripts/core/transponder_service.gd")
const FacilityRegistry := preload("res://scripts/core/facility_registry.gd")

const CONTENT := "res://framework/content/transponders_prologue.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3P PROBE · TransponderService")
	print("════════════════════════════════════════════════════════════")
	_test_setup_content()
	_test_modes_status()
	_test_crypto()
	_test_conditions()
	_test_codes_broadcast()
	_test_management_save()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 TRANSPONDER PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 TRANSPONDER PROBE FAILED")
		quit(1)
	else:
		print("V17 TRANSPONDER PROBE OK")
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

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

func _new_facility() -> Object:
	var fr = FacilityRegistry.new()
	_ok(bool(fr.ready), "FacilityRegistry ready", str(fr.errors))
	return fr

func _new_service() -> Object:
	var fr = _new_facility()
	var ts = TransponderService.new({"facility_registry": fr})
	_ok(bool(ts.ready), "TransponderService ready", str(ts.errors))
	return ts

func _new_service_no_fac() -> Object:
	var ts = TransponderService.new({"facility_registry": null})
	_ok(bool(ts.ready), "TransponderService(no facility) ready", str(ts.errors))
	return ts

func _bad_content(ts) -> Dictionary:
	return (ts.content as Dictionary).duplicate(true)

func _quick_status(ts, profile_id: String, status: String) -> Dictionary:
	return ts.interrogate("test_source", profile_id, "", {"range_km": 0.0})

func _eq_str(d: Dictionary, key: String, expected: String, label: String) -> void:
	_eq(str(d.get(key, "")), expected, label)

# ═══════════════════════════════════════════════════════════════════
# 1. setup / content / binding
# ═══════════════════════════════════════════════════════════════════

func _test_setup_content() -> void:
	_section_begin("1 setup/内容/绑定")
	var ts = _new_service()
	_eq((ts.profile_ids() as Array).size(), 6, "6 profiles")
	for pid in ["apsis", "harmattan", "l1_station", "chronos", "greenwich", "ceres_2_demo"]:
		_ok(str(pid) in ts.profile_ids(), "含 profile " + str(pid))
		var p: Dictionary = ts.profile(str(pid))
		_ok(str(p.get("profile_id", "")) == pid, "profile id " + str(pid))
		_ok(str(p.get("name", "")) != "", "profile name " + str(pid))
		_ok(str(p.get("entity_type", "")) in ["ship", "station", "port", "fuel", "tank", "otc", "relay"],
			"entity_type " + str(pid))
		_ok((p.get("modes", []) as Array).size() > 0, "modes " + str(pid))
		_ok(str(p.get("default_mode", "")) in (p.get("modes", []) as Array),
			"default_mode " + str(pid))
		_ok(str(p.get("status", "")) in TransponderService.STATUSES, "status " + str(pid))
		_ok(str(p.get("transponder_code", "")) != "", "transponder_code " + str(pid))
		_ok(str(p.get("registration_code", "")) != "", "registration_code " + str(pid))
		_ok(p.get("crypto") is Dictionary, "crypto " + str(pid))
		_ok(p.get("broadcast") is Dictionary, "broadcast " + str(pid))
		_ok(p.get("trigger_map") is Dictionary, "trigger_map " + str(pid))
	var sum: Dictionary = ts.summary()
	_eq(int(sum.get("profiles", 0)), 6, "summary 6")
	_eq(int((sum.get("by_type", {}) as Dictionary).get("ship", 0)), 3, "3 ship")
	_eq(int((sum.get("by_type", {}) as Dictionary).get("station", 0)), 2, "2 station")
	_eq(int((sum.get("by_type", {}) as Dictionary).get("fuel", 0)), 1, "1 fuel")
	# 绑定：ship→entity，station→facility
	_eq(str(ts.profile("apsis").get("entity_id", "")), "apsis", "apsis 绑定 entity")
	_ok(str(ts.profile("apsis").get("facility_id", "")) == "", "ship 无 facility")
	_eq(str(ts.profile("l1_station").get("facility_id", "")), "L1-05", "l1_station 绑定 L1-05")
	_eq(str(ts.profile("l1_station").get("facility_code", "")), "FC-L1-05",
		"l1_station facility_code")
	_eq(str(ts.profile("greenwich").get("facility_id", "")), "L1-01", "greenwich 绑定 L1-01")
	_eq(str(ts.profile("chronos").get("entity_type", "")), "fuel", "chronos fuel")
	_eq(str(ts.profile("ceres_2_demo").get("status", "")), "faulty", "ceres demo faulty")
	# 内容校验
	var ts2 = _new_service_no_fac()
	_ok(bool(ts2.ready), "无 facility registry 也可加载")
	var bad_schema := _bad_content(ts2)
	bad_schema["schema"] = "bad"
	_ok(not bool(ts2.validate_content(bad_schema).get("ok", true)), "坏 schema 拒绝")
	var bad_ver := _bad_content(ts2)
	bad_ver["version"] = "9.9.9"
	_ok(not bool(ts2.validate_content(bad_ver).get("ok", true)), "坏 version 拒绝")
	var bad_dup := _bad_content(ts2)
	(bad_dup["profiles"] as Array)[1]["transponder_code"] = \
		(bad_dup["profiles"] as Array)[0]["transponder_code"]
	_ok(not bool(ts2.validate_content(bad_dup).get("ok", true)), "重复 transponder_code 拒绝")
	var bad_reg := _bad_content(ts2)
	(bad_reg["profiles"] as Array)[1]["registration_code"] = \
		(bad_reg["profiles"] as Array)[0]["registration_code"]
	_ok(not bool(ts2.validate_content(bad_reg).get("ok", true)), "重复 registration_code 拒绝")
	var bad_mode := _bad_content(ts2)
	(bad_mode["profiles"] as Array)[0]["modes"] = ["bogus"]
	_ok(not bool(ts2.validate_content(bad_mode).get("ok", true)), "非法 mode 拒绝")
	var bad_status := _bad_content(ts2)
	(bad_status["profiles"] as Array)[0]["status"] = "bogus"
	_ok(not bool(ts2.validate_content(bad_status).get("ok", true)), "非法 status 拒绝")
	var bad_ship := _bad_content(ts2)
	(bad_ship["profiles"] as Array)[0]["entity_id"] = ""
	_ok(not bool(ts2.validate_content(bad_ship).get("ok", true)), "ship 缺 entity_id 拒绝")
	var bad_fac := _bad_content(ts)
	var station_row: Dictionary = (bad_fac["profiles"] as Array)[2]
	station_row["facility_id"] = "NOPE"
	_ok(not bool(ts.validate_content(bad_fac).get("ok", true)), "station 未知 facility 拒绝")
	var bad_range := _bad_content(ts2)
	(bad_range["profiles"] as Array)[0]["range_km"] = -1
	_ok(not bool(ts2.validate_content(bad_range).get("ok", true)), "负 range 拒绝")
	# 不存在内容
	var bad = TransponderService.new({"content_path": "/no/such.json"})
	_ok(not bool(bad.ready), "不存在内容拒绝")
	# 契约/不写声明
	_ok(bool(ts.check_contracts().get("ok", false)), "contracts ok")
	var vm: Dictionary = ts.vm()
	_eq(bool((vm.get("writes", {}) as Dictionary).get("world", true)), false, "不写 world")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("track_table", true)), false,
		"不写 TrackTable")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("v15", true)), false, "不写 V15")
	_data_line("setup", "6 profiles（3 ship/2 station/1 fuel）· entity/facility 绑定 · 内容校验")

# ═══════════════════════════════════════════════════════════════════
# 2. modes / status / triggers
# ═══════════════════════════════════════════════════════════════════

func _test_modes_status() -> void:
	_section_begin("2 modes/status")
	var ts = _new_service()
	# apsis 支持 4 模式
	for mode in ["mode_a", "mode_c", "mode_s", "mode_5"]:
		var r: Dictionary = ts.interrogate("l1_station", "apsis", mode)
		_eq(bool(r.get("ok", false)), true, "apsis mode ok " + mode)
		_eq(str((r.get("reply", {}) as Dictionary).get("mode", "")), mode,
			"reply mode " + mode)
		_ok((r.get("evidence", []) as Array).size() == 1, "reply evidence " + mode)
	# harmattan mode_5 challenge/reply
	var r5: Dictionary = ts.interrogate("apsis", "harmattan", "mode_5",
		{"challenge": "CH-TEST"})
	_eq(bool(r5.get("ok", false)), true, "harmattan mode5 ok")
	var rep5: Dictionary = r5.get("reply", {})
	_eq(str(rep5.get("challenge", "")), "CH-TEST", "mode5 challenge")
	_ok(str(rep5.get("challenge_response", "")) != "", "mode5 challenge_response")
	_ok(str(rep5.get("crypto", {}).get("key_id", "")) != "", "mode5 crypto key")
	# 普通模式不需要 challenge：不提供 challenge 也 ok
	var rn: Dictionary = ts.interrogate("apsis", "harmattan", "mode_s")
	_eq(bool(rn.get("ok", false)), true, "普通模式不需要 challenge")
	_eq(str((rn.get("reply", {}) as Dictionary).get("challenge", "")), "",
		"普通模式 challenge 空")
	# 不支持模式
	var ru: Dictionary = ts.interrogate("apsis", "harmattan", "mode_a")
	_eq(bool(ru.get("ok", true)), false, "不支持模式 no reply")
	_eq(str(ru.get("reason", "")), "mode_unsupported", "mode_unsupported")
	_ok(ru.get("reply") is Dictionary, "no reply 仍有 reply 对象")
	# 不同状态
	var statuses: Array = ["off", "no_reply", "faulty", "expired", "wrong_code", "crypto_fail"]
	for st in statuses:
		_eq(bool(ts.set_status("apsis", str(st)).get("ok", false)), true,
			"set_status " + str(st))
		var r2: Dictionary = ts.interrogate("l1_station", "apsis", "mode_s")
		_eq(bool(r2.get("ok", true)), false, "status 不回复 " + str(st))
		_eq(str(r2.get("reason", "")), str(st), "status reason " + str(st))
	# captured → spoofed reply
	ts.set_status("l1_station", "captured")
	var rc: Dictionary = ts.interrogate("apsis", "l1_station", "station_beacon")
	_eq(bool(rc.get("ok", false)), true, "captured 返回 spoofed reply")
	var repc: Dictionary = rc.get("reply", {})
	_eq(bool(repc.get("spoofed", false)), true, "captured spoofed=true")
	_eq(str(repc.get("identity", "")), "unknown", "captured identity unknown")
	_eq(str((rc.get("trigger", {}) as Dictionary).get("trigger_id", "")),
		"station_spoof", "captured trigger station_spoof")
	# spoofed
	ts.set_status("l1_station", "spoofed")
	var rs: Dictionary = ts.interrogate("apsis", "l1_station", "station_beacon")
	_eq(bool((rs.get("reply", {}) as Dictionary).get("spoofed", false)), true,
		"spoofed reply")
	# normal 恢复
	ts.set_status("l1_station", "normal")
	_eq(bool(ts.interrogate("apsis", "l1_station", "station_beacon").get("ok", false)),
		true, "normal 恢复")
	# ceres demo faulty → ceres_no_reply
	var rf: Dictionary = ts.interrogate("apsis", "ceres_2_demo", "mode_s")
	_eq(str((rf.get("trigger", {}) as Dictionary).get("trigger_id", "")),
		"ceres_no_reply", "ceres_no_reply trigger")
	_ok("ceres_no_reply" in ts.trigger_ids(), "trigger_ids 含 ceres_no_reply")
	# 非法状态拒绝且不改
	var before := str(ts.profile("apsis").get("status", ""))
	_eq(bool(ts.set_status("apsis", "bogus").get("ok", true)), false, "非法状态拒绝")
	_eq(str(ts.profile("apsis").get("status", "")), before, "非法状态不改")
	_eq(bool(ts.set_status("no_such", "normal").get("ok", true)), false,
		"未知 profile 状态拒绝")
	# 事件
	_ok(ts.events.size() > 0, "产生事件")
	var ev: Dictionary = (ts.events[ts.events.size() - 1] as Dictionary)
	_eq(str(ev.get("schema", "")), "transponder_event.v1", "事件 schema")
	_ok(ev.has("kind") and ev.has("payload"), "事件 kind/payload")
	_data_line("modes", "mode_a/c/s/5 · 6 状态 no_reply · captured/spoofed · challenge/reply · triggers")

# ═══════════════════════════════════════════════════════════════════
# 3. 加密
# ═══════════════════════════════════════════════════════════════════

func _test_crypto() -> void:
	_section_begin("3 加密")
	var ts = _new_service()
	var cs: Dictionary = ts.crypto_state("greenwich")
	_ok(not cs.is_empty(), "crypto_state greenwich")
	_eq(bool(cs.get("challenge_required", false)), true, "greenwich 需要 crypto")
	_ok(int((cs.get("crypto", {}) as Dictionary).get("epoch", 0)) > 0, "epoch")
	# 普通 ship 模式不需要 challenge；mode5 需要
	var r1: Dictionary = ts.interrogate("apsis", "greenwich", "station_beacon")
	_eq(bool(r1.get("ok", false)), true, "station_beacon 不需要 challenge")
	var r2: Dictionary = ts.interrogate("apsis", "greenwich", "mode_5")
	_eq(bool(r2.get("ok", false)), true, "greenwich mode5 ok")
	_ok(str((r2.get("reply", {}) as Dictionary).get("challenge_response", "")) != "",
		"mode5 reply 有 response")
	# crypto 无效 → mode5 crypto_fail
	_eq(bool(ts.set_crypto("greenwich", {"valid": false}).get("ok", false)), true,
		"set crypto invalid ok")
	var r3: Dictionary = ts.interrogate("apsis", "greenwich", "mode_5")
	_eq(str(r3.get("reason", "")), "crypto_fail", "crypto fail mode5")
	_eq(str(ts.profile("greenwich").get("status", "")), "normal", "crypto fail 不改 status")
	# 普通模式不受 crypto invalid 阻断（仍 non-crypto）
	var r4: Dictionary = ts.interrogate("apsis", "greenwich", "station_beacon")
	_eq(bool(r4.get("ok", false)), true, "普通模式 crypto invalid 仍回复")
	# captured crypto → mode5 captured_crypto
	ts.set_crypto("greenwich", {"valid": true, "captured": true})
	var r5: Dictionary = ts.interrogate("apsis", "greenwich", "mode_5")
	_eq(str(r5.get("reason", "")), "captured_crypto", "captured crypto mode5")
	# 恢复
	ts.set_crypto("greenwich", {"valid": true, "captured": false, "epoch": 9})
	_eq(int((ts.crypto_state("greenwich").get("crypto", {}) as Dictionary).get("epoch", 0)),
		9, "crypto epoch 更新")
	var r6: Dictionary = ts.interrogate("apsis", "greenwich", "mode_5")
	_eq(bool(r6.get("ok", false)), true, "crypto 恢复后 mode5 ok")
	# 非法 crypto patch
	_eq(bool(ts.set_crypto("greenwich", {"epoch": NAN}).get("ok", true)), false,
		"NaN epoch 拒绝")
	_eq(bool(ts.set_crypto("no_such", {"valid": true}).get("ok", true)), false,
		"未知 profile crypto 拒绝")
	_ok(ts.crypto_state("no_such").is_empty(), "未知 crypto_state 空")
	_data_line("crypto", "epoch/valid/captured · mode5 challenge/reply · crypto_fail · 普通模式不受阻")

# ═══════════════════════════════════════════════════════════════════
# 4. 距离/遮挡/干扰/延迟
# ═══════════════════════════════════════════════════════════════════

func _test_conditions() -> void:
	_section_begin("4 range/occlusion/jam/latency")
	var ts = _new_service()
	# range
	var rr: Dictionary = ts.interrogate("src", "apsis", "mode_s", {"range_km": 999999.0})
	_eq(str(rr.get("reason", "")), "out_of_range", "超距 no_reply")
	_eq(bool((rr.get("reply", {}) as Dictionary).get("ok", true)), false,
		"超距 reply ok=false")
	var r0: Dictionary = ts.interrogate("src", "apsis", "mode_s", {"range_km": 10.0})
	_eq(bool(r0.get("ok", false)), true, "范围内 ok")
	# occlusion opts
	var ro: Dictionary = ts.interrogate("src", "apsis", "mode_s", {"occluded": true})
	_eq(str(ro.get("reason", "")), "occluded", "遮挡 opts no_reply")
	# target occlusion
	ts.set_occlusion("apsis", true)
	_eq(str(ts.interrogate("src", "apsis").get("reason", "")), "occluded",
		"target 遮挡 no_reply")
	ts.set_occlusion("apsis", false)
	# global occlusion
	ts.set_occlusion("", true)
	_eq(str(ts.interrogate("src", "apsis").get("reason", "")), "occluded",
		"全局遮挡 no_reply")
	ts.set_occlusion("", false)
	# jam >0.5
	ts.set_jam("apsis", 0.9)
	_eq(str(ts.interrogate("src", "apsis").get("reason", "")), "jammed", "强干扰 no_reply")
	# jam 0.3 降级：ok、confidence<1、support=3
	ts.set_jam("apsis", 0.3)
	var rj: Dictionary = ts.interrogate("src", "apsis")
	_eq(bool(rj.get("ok", false)), true, "弱干扰仍回复")
	var rjr: Dictionary = rj.get("reply", {})
	_ok(float(rjr.get("confidence", 1.0)) < 1.0, "弱干扰 confidence 降级")
	var weak_support := int(((rj.get("evidence", []) as Array)[0] as Dictionary).get("support", 0))
	_ok(weak_support in [3, 4], "弱干扰 evidence support 3/4", str(weak_support))
	_eq(float(rjr.get("jam", 0.0)), 0.3, "reply jam")
	ts.set_jam("apsis", 0.0)
	# latency
	var rl: Dictionary = ts.interrogate("src", "apsis", "mode_s", {"latency_s": 2.0})
	_eq(bool(rl.get("ok", false)), true, "可接受延迟 ok")
	_near(float((rl.get("reply", {}) as Dictionary).get("latency_s", 0.0)), 2.0,
		1.0e-9, "reply latency")
	var rl2: Dictionary = ts.interrogate("src", "apsis", "mode_s", {"latency_s": 99.0})
	_eq(str(rl2.get("reason", "")), "latency_exceeded", "超延迟 no_reply")
	# 全局 jam
	ts.set_jam("", 0.8)
	_eq(str(ts.interrogate("src", "apsis").get("reason", "")), "jammed", "全局 jam")
	ts.set_jam("", 0.0)
	# 非法 set_jam
	_eq(bool(ts.set_jam("apsis", -0.1).get("ok", true)), false, "负 jam 拒绝")
	_eq(bool(ts.set_jam("apsis", 1.5).get("ok", true)), false, ">1 jam 拒绝")
	# 事件含 reason
	var last_ev: Dictionary = (ts.events[ts.events.size() - 1] as Dictionary)
	_eq(str(last_ev.get("schema", "")), "transponder_event.v1", "条件事件 schema")
	_data_line("conditions", "超距/opts·target·全局遮挡/强·弱·全局干扰/延迟超限 · 事件")

# ═══════════════════════════════════════════════════════════════════
# 5. 码注册表 / 广播
# ═══════════════════════════════════════════════════════════════════

func _test_codes_broadcast() -> void:
	_section_begin("5 codes/broadcast")
	var ts = _new_service()
	# lookup transponder / registration / facility code
	var l1: Dictionary = ts.lookup_code("TXP-APSIS-01")
	_eq(bool(l1.get("ok", false)), true, "lookup transponder ok")
	_eq(str(l1.get("profile_id", "")), "apsis", "lookup profile")
	_eq(bool(l1.get("duplicate", true)), false, "lookup 不重复")
	var l2: Dictionary = ts.lookup_code("REG-OCUVF-APSIS")
	_eq(bool(l2.get("ok", false)), true, "lookup registration ok")
	_eq(str(l2.get("profile_id", "")), "apsis", "registration profile")
	var l3: Dictionary = ts.lookup_code("FC-L1-05")
	_eq(bool(l3.get("ok", false)), true, "lookup facility_code ok")
	_ok((l3.get("matches", []) as Array).size() >= 2, "facility_code 多匹配")
	_eq(bool(l3.get("duplicate", false)), true, "facility_code duplicate 标记")
	var l4: Dictionary = ts.lookup_code("NOPE")
	_eq(bool(l4.get("ok", true)), false, "未知码拒绝")
	_eq(str(l4.get("reason", "")), "unknown_code", "unknown_code reason")
	var l5: Dictionary = ts.lookup_code("")
	_eq(str(l5.get("reason", "")), "empty_code", "空码 reason")
	# 广播：站 3、ship silent 不含
	var br: Dictionary = ts.broadcast()
	_eq(bool(br.get("ok", false)), true, "broadcast ok")
	var rows: Array = br.get("broadcasts", [])
	_ok(rows.size() >= 3, "广播站 >=3", str(rows.size()))
	var ids: Array = []
	for raw in rows:
		ids.append(str((raw as Dictionary).get("profile_id", "")))
	_ok("l1_station" in ids, "广播 l1_station")
	_ok("chronos" in ids, "广播 chronos")
	_ok("greenwich" in ids, "广播 greenwich")
	_ok(not ("apsis" in ids), "ship silent 不广播")
	_ok(not ("harmattan" in ids), "harmattan silent 不广播")
	_ok((br.get("evidence", []) as Array).size() == rows.size(), "广播 evidence 数")
	for raw2 in rows:
		var row: Dictionary = raw2
		_eq(str(row.get("schema", "")), "transponder_broadcast.v1", "broadcast schema")
		_ok(str(row.get("transponder_code", "")) != "", "broadcast code")
		_ok(row.get("binding") is Dictionary, "broadcast binding")
		_ok(str(row.get("mode", "")) in ["station_beacon", "adsb_like"], "broadcast mode")
	# profile 过滤
	var b1: Dictionary = ts.broadcast({"profile_id": "greenwich"})
	_eq((b1.get("broadcasts", []) as Array).size(), 1, "广播 profile 过滤")
	# passive_listen
	var pl: Dictionary = ts.passive_listen()
	_eq(bool(pl.get("passive", false)), true, "passive flag")
	_eq((pl.get("broadcasts", []) as Array).size(), rows.size(), "passive 与广播一致")
	# 状态非 normal 不广播
	ts.set_status("greenwich", "faulty")
	var br2: Dictionary = ts.broadcast()
	var ids2: Array = []
	for raw3 in (br2.get("broadcasts", []) as Array):
		ids2.append(str((raw3 as Dictionary).get("profile_id", "")))
	_ok(not ("greenwich" in ids2), "faulty 站不广播")
	ts.set_status("greenwich", "normal")
	# 事件
	_ok(ts.events.size() > 0, "broadcast 产生事件")
	_data_line("codes/broadcast", "transponder/registration/facility 查询 · unknown/empty · 站广播 3 · silent ship · passive")

# ═══════════════════════════════════════════════════════════════════
# 6. 管理 / 存档 / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_management_save() -> void:
	_section_begin("6 management/save")
	var ts = _new_service()
	# upsert 新 ship
	var np: Dictionary = {"profile_id": "test_ship", "name": "Test Ship",
		"entity_type": "ship", "entity_id": "test_ship", "facility_id": "",
		"facility_code": "", "transponder_code": "TXP-TEST-01",
		"registration_code": "REG-TEST-01", "side": "neutral", "identity": "unknown",
		"modes": ["mode_s"], "default_mode": "mode_s", "status": "normal",
		"range_km": 1000.0, "silent": true,
		"broadcast": {"enabled": false, "interval_s": 30.0, "modes": []},
		"crypto": {"epoch": 1, "valid": true, "captured": false, "key_id": "T"},
		"trigger_map": {}}
	var up: Dictionary = ts.upsert_profile(np)
	_eq(bool(up.get("ok", false)), true, "upsert profile ok", str(up.get("errors", [])))
	_eq(bool(up.get("created", false)), true, "upsert created")
	_ok("test_ship" in ts.profile_ids(), "profile_ids 含 test_ship")
	_eq(str(ts.profile("test_ship").get("name", "")), "Test Ship", "upsert name")
	var up2: Dictionary = ts.upsert_profile({"profile_id": "test_ship", "name": "Test 2",
		"entity_type": "ship", "entity_id": "test_ship",
		"transponder_code": "TXP-TEST-01", "registration_code": "REG-TEST-01",
		"modes": ["mode_s"], "default_mode": "mode_s", "status": "normal",
		"range_km": 1000.0})
	_eq(bool(up2.get("created", true)), false, "upsert 更新 created=false")
	_eq(str(ts.profile("test_ship").get("name", "")), "Test 2", "upsert 更新")
	# 非法 upsert 不改
	var count_before: int = int(ts.profile_ids().size())
	_eq(bool(ts.upsert_profile({"profile_id": "bad", "entity_type": "ship",
		"transponder_code": "TXP-APSIS-01", "registration_code": "REG-X",
		"modes": ["mode_s"], "default_mode": "mode_s"}).get("ok", true)), false,
		"重复码 upsert 拒绝")
	_eq(ts.profile_ids().size(), count_before, "非法 upsert 不改数量")
	# remove
	_eq(bool(ts.remove_profile("test_ship").get("ok", false)), true, "remove profile ok")
	_ok(not ("test_ship" in ts.profile_ids()), "remove 后不在")
	_eq(bool(ts.remove_profile("test_ship").get("ok", true)), false, "remove 未知拒绝")
	# 状态/crypto/jam/occlusion 已在前面覆盖；这里检查 vm
	var vm: Dictionary = ts.vm()
	_eq(str(vm.get("schema", "")), "v17.transponder_service.v1", "vm schema")
	_ok(int(vm.get("profile_count", 0)) >= 6, "vm profile_count")
	_ok(vm.get("events") is Array, "vm events")
	_ok(vm.get("evidence") is Array, "vm evidence")
	_ok(vm.get("trigger_ids") is Array, "vm trigger_ids")
	_ok(JSON.parse_string(JSON.stringify(vm)) is Dictionary, "vm JSON")
	# save/load
	ts.set_status("l1_station", "captured")
	ts.set_jam("apsis", 0.4)
	var save := str(ts.save_state())
	var ts2 = _new_service()
	var lr: Dictionary = ts2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "save/load ok", str(lr.get("errors", [])))
	_ok(JSON.stringify(JSON.parse_string(JSON.stringify(ts.vm()))) ==
		JSON.stringify(JSON.parse_string(JSON.stringify(ts2.vm()))), "load VM 一致")
	_eq(str(ts2.profile("l1_station").get("status", "")), "captured", "load status")
	_near(float(ts2.jam.get("apsis", 0.0)), 0.4, 1.0e-9, "load jam")
	_eq(bool(ts2.interrogate("x", "l1_station", "station_beacon").get("ok", true)),
		true, "load 后 spoof reply ok")
	# 非法存档
	var before_core := JSON.stringify(JSON.parse_string(ts2.save_state()))
	for bad in ["", "{bad", JSON.stringify({"schema": "bad"}),
			JSON.stringify({"schema": "v17.transponder_service_save.v1", "version": "9.9.9"}),
			JSON.stringify({"schema": "v17.transponder_service_save.v1", "version": "1.0.0",
				"profiles": []})]:
		_eq(bool(ts2.load_state(str(bad)).get("ok", true)), false,
			"非法存档拒绝：" + str(bad).substr(0, 30))
	_eq(JSON.stringify(JSON.parse_string(ts2.save_state())), before_core,
		"非法存档不改状态")
	# 确定性
	var a = _new_service()
	var b = _new_service()
	for x in [a, b]:
		x.interrogate("src", "apsis", "mode_s")
		x.interrogate("src", "l1_station", "station_beacon")
		x.set_status("l1_station", "spoofed")
		x.interrogate("src", "l1_station", "station_beacon")
		x.set_jam("harmattan", 0.2)
		x.interrogate("src", "harmattan", "mode_5")
	_eq(JSON.stringify(JSON.parse_string(a.save_state())),
		JSON.stringify(JSON.parse_string(b.save_state())), "同操作 save 一致")
	_eq(_norm(a.vm()), _norm(b.vm()), "同操作 VM 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	_data_line("management", "upsert/remove · vm/save/load · 非法存档原子拒绝 · 同操作确定性")
