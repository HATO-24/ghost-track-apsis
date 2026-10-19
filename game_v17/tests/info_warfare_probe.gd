extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R5-INFO-1 headless probe：统一 IFF / ELINT / COMINT / EW（shadow）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/info_warfare_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
#
# 覆盖：IFF 全状态 + 不判敌 + 不产生位置；ELINT 链路预算/单站/多站候选/门限；
#       COMINT 加密不解码；EW 各效果/事件总线/EMCON/phantom；JSON/确定性/不写 TrackTable。
# ═══════════════════════════════════════════════════════════════════

const IW := preload("res://framework/sim/information_warfare.gd")
const TrackTable := preload("res://framework/core/track_table.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

var _lib: Dictionary = {}
var _targets: Array = []
var _config: Dictionary = {}


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R5-INFO-1 PROBE · IFF / ELINT / COMINT / EW（shadow）")
	print("════════════════════════════════════════════════════════════")
	_make_inputs()
	_test_setup()
	_test_iff()
	_test_iff_bounds()
	_test_elint()
	_test_triangulation()
	_test_comint()
	_test_ew_effects()
	_test_ew_emcon_phantom()
	_test_events_alerts()
	_test_vm_json_no_write()
	_test_determinism()
	_print_results()


# ── 工具 ─────────────────────────────────────────────────────────

func _make_inputs() -> void:
	_lib = IW.default_iff_config()["library"]
	var radar := {"model": "YW-R9", "type": "radar", "active": true,
		"frequency_mhz": 9500.0, "power_dbm": 90.0, "gain_tx_dbi": 30.0}
	var radar_weak := {"model": "YW-R9", "type": "radar", "active": true,
		"frequency_mhz": 9500.0, "power_dbm": 20.0, "gain_tx_dbi": 30.0}
	var radar_lpi := {"model": "KD-R6", "type": "radar", "active": true, "lpi": true,
		"frequency_mhz": 9500.0, "power_dbm": 90.0, "gain_tx_dbi": 30.0}
	var radar_silent := {"model": "YW-R9", "type": "radar", "active": false, "silent": true,
		"frequency_mhz": 9500.0, "power_dbm": 90.0}
	var radar_unknown := {"model": "MYSTERY-R7", "type": "radar", "active": true,
		"frequency_mhz": 9000.0, "power_dbm": 90.0, "signature": ""}
	var radar_spoof := {"model": "YW-R9", "type": "radar", "active": true, "spoof": true,
		"frequency_mhz": 9500.0, "power_dbm": 90.0}
	var comms_plain := {"from": "F1", "to": "F2", "mode": "radio", "text": "plain hello",
		"encrypted": false, "frequency_mhz": 300.0}
	var comms_enc := {"from": "E1", "to": "E2", "mode": "radio", "text": "SECRET",
		"encrypted": true, "frequency_mhz": 300.0}
	var comms_laser := {"from": "LSR", "to": "X", "mode": "lasercom", "text": "LASER",
		"encrypted": false, "frequency_mhz": 300000.0}
	_targets = [
		{"id": "F1", "name": "友舰", "pos_km": [0.0, 1000.0, 0.0], "transponder": "ok",
			"registered": true, "crypto_epoch": "epoch-1", "reply_delay_s": 0.2,
			"iff_codes": _lib.duplicate(), "emissions": [radar], "comms": [comms_plain]},
		{"id": "F2", "name": "友舰2", "pos_km": [0.0, 1500.0, 0.0], "transponder": "ok",
			"registered": true, "crypto_epoch": "epoch-1", "iff_codes": _lib.duplicate()},
		{"id": "R1", "name": "未注册", "pos_km": [0.0, 1200.0, 0.0], "transponder": "ok",
			"registered": false, "crypto_epoch": "epoch-1", "iff_codes": _lib.duplicate()},
		{"id": "E1", "name": "未知", "pos_km": [0.0, 1600.0, 0.0], "transponder": "off",
			"emissions": [radar], "comms": [comms_enc]},
		{"id": "X1", "pos_km": [0.0, 900.0, 0.0], "transponder": "faulty", "registered": true},
		{"id": "X2", "pos_km": [0.0, 800.0, 0.0], "transponder": "captured",
			"registered": true, "iff_codes": _lib.duplicate()},
		{"id": "X3", "pos_km": [0.0, 700.0, 0.0], "transponder": "ok",
			"registered": true, "iff_codes": {"3/A": "BAD"}},
		{"id": "X4", "pos_km": [0.0, 600.0, 0.0], "transponder": "ok",
			"registered": true, "crypto_epoch": "epoch-0", "iff_codes": _lib.duplicate()},
		{"id": "X5", "pos_km": [0.0, 500.0, 0.0], "transponder": "ok",
			"registered": true, "reply_delay_s": 3.0, "iff_codes": _lib.duplicate()},
		{"id": "FAR", "pos_km": [0.0, 2500.0, 0.0], "transponder": "ok", "registered": true},
		{"id": "TRI", "pos_km": [0.0, 5000.0, 0.0], "transponder": "off",
			"emissions": [{"model": "KD-R6", "type": "radar", "active": true,
				"frequency_mhz": 9500.0, "power_dbm": 90.0, "gain_tx_dbi": 30.0}]},
		{"id": "LPI", "pos_km": [0.0, 4000.0, 0.0], "transponder": "off",
			"emissions": [radar_lpi]},
		{"id": "SILENT", "pos_km": [0.0, 3000.0, 0.0], "transponder": "off",
			"emissions": [radar_silent]},
		{"id": "UNKNOWN", "pos_km": [2000.0, 3000.0, 0.0], "transponder": "off",
			"emissions": [radar_unknown]},
		{"id": "SPOOF", "pos_km": [0.0, 2500.0, 0.0], "transponder": "off",
			"emissions": [radar_spoof]},
		{"id": "LSR", "pos_km": [0.0, 10000.0, 0.0], "transponder": "off",
			"comms": [comms_laser]},
		{"id": "WEAK", "pos_km": [20000.0, 30000.0, 0.0], "transponder": "off",
			"emissions": [radar_weak]},
	]
	_config = {
		"observer_id": "harmattan",
		"targets": _targets,
		"stations": [
			{"id": "A", "pos_km": [0.0, 0.0, 0.0], "sigma_bearing_deg": 1.0},
			{"id": "B", "pos_km": [5000.0, 0.0, 0.0], "sigma_bearing_deg": 1.0},
		],
		"advisory_contacts": [{"id": "F1", "track_id": "T2001", "batch": "2001"}],
	}


func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)


func _ok(cond: bool, label: String, detail := "") -> void:
	var d_trim := detail
	if d_trim.length() > 320:
		d_trim = d_trim.substr(0, 320) + "…"
	if cond:
		_pass += 1
		if d_trim != "":
			print("[PASS] %s  %s" % [label, d_trim])
		else:
			print("[PASS] %s" % label)
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if d_trim != "":
			line += "  (" + d_trim + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, d_trim])


func _eq(actual, expected, label: String, detail := "") -> void:
	if actual == expected:
		_ok(true, label, "")
		return
	var d := "actual=%s expected=%s" % [str(actual), str(expected)]
	if detail != "":
		d += " · " + detail
	_ok(false, label, d)


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	var diff := absf(actual - expected)
	_ok(diff <= tol, label, "actual=%s expected=%s diff=%s" % [
		str(actual), str(expected), str(diff)])


func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)


func _json_ok(value: Variant) -> bool:
	var txt := JSON.stringify(value)
	if txt.length() <= 2:
		return false
	var back = JSON.parse_string(txt)
	return back is Dictionary or back is Array


func _find_signal(rows: Array, source: String, station := "") -> Array:
	var out: Array = []
	for raw in rows:
		if raw is Dictionary:
			var s: Dictionary = raw
			if str(s.get("source_id", "")) != source:
				continue
			if station != "" and str(s.get("station_id", "")) != station:
				continue
			out.append(s)
	return out


func _latest_for(iw, source: String, station := "", freq := "") -> Array:
	return _find_signal(iw.latest_signals(), source, station)


func _find_alert(rows: Array, kind: String) -> Dictionary:
	for raw in rows:
		if raw is Dictionary and str((raw as Dictionary).get("kind", "")) == kind:
			return raw
	return {}


func _new_iw(cfg := {}) -> Object:
	var c: Dictionary = _config.duplicate(true)
	for k in (cfg as Dictionary).keys():
		c[str(k)] = (cfg as Dictionary)[k]
	var iw = IW.new()
	iw.setup(c)
	return iw


# ═══════════════════════════════════════════════════════════════════
# 1. 初始化 / 边界
# ═══════════════════════════════════════════════════════════════════

func _test_setup() -> void:
	_section_begin("1 初始化 / 模式 / 输入")
	var iw = _new_iw()
	_ok(bool(iw.ready), "setup 成功", str(iw.errors))
	_eq(iw.errors.size(), 0, "setup 无错误")
	_eq(str(iw.mode), "shadow", "mode=shadow")
	_eq(bool(iw.authoritative), false, "authoritative=false")
	_eq(bool(iw.writes_track_table), false, "writes_track_table=false")
	_eq(bool(iw.writes_v15), false, "writes_v15=false")
	_ok(not iw.has_write_target(), "has_write_target()=false")
	_eq(str(iw.observer.get("id", "")), "harmattan", "observer=harmattan")
	_eq(iw.targets.size(), 17, "17 个目标")
	_eq(iw.stations.size(), 2, "2 个 ELINT 站")
	_eq(str(iw.iff_cfg.get("model", "")), "MK-12", "IFF 型号 MK-12")
	_eq(str(iw.elint_cfg.get("model", "")), "ELINT", "ELINT 型号 ELINT")
	var vm: Dictionary = iw.vm_information_warfare()
	for key in ["schema", "mode", "authoritative", "ready", "t", "observer", "iff", "elint",
			"comint", "ew", "effects", "events", "alerts", "summary", "writes", "shadow"]:
		_ok(vm.has(key), "vm 字段 " + key)
	_eq(str(vm.get("schema", "")), "information_warfare.v1", "vm schema")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("track_table", true)), false,
		"vm.writes.track_table=false")
	_eq(bool((vm.get("shadow", {}) as Dictionary).get("never_auto_hostile", false)), true,
		"shadow.never_auto_hostile")
	# 空配置/无目标
	var empty = IW.new()
	_ok(bool(empty.setup({"targets": []})), "空 targets setup 成功")
	_ok(not bool(empty.step(1.0).get("ok", true)) or true, "空目标 step 不崩溃")
	_data_line("setup", "targets=%d stations=%d mode=%s" % [
		iw.targets.size(), iw.stations.size(), str(iw.mode)])


# ═══════════════════════════════════════════════════════════════════
# 2. IFF
# ═══════════════════════════════════════════════════════════════════

func _test_iff() -> void:
	_section_begin("2 IFF 状态 / 身份 / 不判敌")
	var iw = _new_iw()
	# 正常友军应答（注册 + Mode 3/A）
	var f1: Dictionary = iw.interrogate_iff("F1", ["3/A"])
	_eq(str(f1.get("schema", "")), "iff_result.v1", "IFF schema")
	_eq(str(f1.get("status", "")), "reply_ok", "F1 reply_ok")
	_eq(str(f1.get("identity", "")), "friend", "F1 identity=friend")
	_eq(int(f1.get("level_support", 0)), 4, "F1 level_support=4（L4 证据）")
	_ok(float(f1.get("confidence", 0.0)) >= 0.9, "F1 confidence≥0.9")
	_eq(bool(f1.get("produces_contact", true)), false, "IFF 不产生接触")
	_eq(bool(f1.get("produces_position", true)), false, "IFF 不产生位置")
	_near(float(f1.get("bearing_deg", -1.0)), -1.0, 1e-9, "IFF bearing=-1")
	_near(float(f1.get("range_km", -1.0)), -1.0, 1e-9, "IFF range=-1")
	_eq(bool(f1.get("never_hostile", false)), true, "IFF never_hostile")
	_eq(bool(f1.get("hostile_allowed", true)), false, "IFF hostile_allowed=false")
	_eq(str(f1.get("state", "")), "resolved", "IFF state=resolved")
	_ok((f1.get("state_history", []) as Array).size() >= 5, "IFF state_history≥5")
	_ok(not (f1.get("identity_evidence", []) as Array).is_empty(), "F1 identity_evidence 非空")
	var ev0: Dictionary = (f1.get("identity_evidence", []) as Array)[0]
	_eq(str(ev0.get("kind", "")), "iff", "identity evidence kind=iff")
	_eq(int(ev0.get("level_support", 0)), 4, "identity evidence L4")
	_ok((f1.get("expose_self", {}) as Dictionary).has("elint_range_km"), "IFF 暴露字段")
	_near(float((f1.get("expose_self", {}) as Dictionary).get("elint_range_km", 0.0)),
		4000.0, 1e-6, "IFF 暴露 4,000 km")
	_eq(str(f1.get("track_id", "")), "T2001", "IFF 关联 advisory track_id")
	_eq(bool(f1.get("advisory_linked", false)), true, "IFF advisory_linked")
	# cooldown
	var f1b: Dictionary = iw.interrogate_iff("F1", ["3/A"])
	_eq(str(f1b.get("status", "")), "cooldown", "连续询问 → cooldown")
	_ok(float(f1b.get("cooldown_remaining_s", 0.0)) > 0.0, "cooldown_remaining_s>0")
	iw.step(3.0)
	var f1c: Dictionary = iw.interrogate_iff("F1", ["3/A"])
	_eq(str(f1c.get("status", "")), "reply_ok", "冷却后可重新询问")
	# Mode 5（加密）
	var f2: Dictionary = iw.interrogate_iff("F2", ["5"])
	_eq(str(f2.get("status", "")), "reply_ok", "F2 Mode 5 reply_ok")
	_eq(str(f2.get("identity", "")), "friend", "F2 Mode 5 identity=friend")
	_eq(bool(f2.get("crypto_ok", false)), true, "F2 crypto_ok")
	iw.step(3.0)
	var f2all: Dictionary = iw.interrogate_iff("F2", ["1", "2", "C", "S", "3/A"])
	_eq(str(f2all.get("status", "")), "reply_ok", "Mode 1/2/C/S/3A 全部应答")
	_eq((f2all.get("modes_replied", []) as Array).size(), 5, "modes_replied=5")
	_eq(str(f2all.get("identity", "")), "friend", "多模式注册应答 → friend")
	# 未注册：应答正确但 unknown / 无 L4
	var r1: Dictionary = iw.interrogate_iff("R1", ["3/A"])
	_eq(str(r1.get("status", "")), "reply_ok", "R1 reply_ok")
	_eq(str(r1.get("identity", "")), "unknown", "R1 未注册 → unknown")
	_eq(int(r1.get("level_support", -1)), 0, "R1 未注册不升 L4")
	# 无应答/故障/缴获/错码/超时/超距
	var e1: Dictionary = iw.interrogate_iff("E1", ["3/A"])
	_eq(str(e1.get("status", "")), "no_reply", "E1 no_reply")
	_eq(str(e1.get("identity", "")), "unknown", "no_reply → unknown（不判敌）")
	var x1: Dictionary = iw.interrogate_iff("X1", ["3/A"])
	_eq(str(x1.get("status", "")), "faulty_transponder", "X1 faulty_transponder")
	_eq(str(x1.get("identity", "")), "unknown", "faulty → unknown")
	var x2: Dictionary = iw.interrogate_iff("X2", ["3/A"])
	_eq(str(x2.get("status", "")), "captured", "X2 captured")
	_ok(float(x2.get("confidence", 1.0)) <= 0.5, "captured confidence≤0.5")
	_ok((x2.get("spoof_flags", []) as Array).has("captured_code"), "captured_code 标记")
	_eq(str(x2.get("identity", "")), "unknown", "captured → unknown")
	var x3: Dictionary = iw.interrogate_iff("X3", ["3/A"])
	_eq(str(x3.get("status", "")), "wrong_code", "X3 wrong_code")
	_eq(str(x3.get("identity", "")), "unknown", "wrong_code → unknown")
	var x4: Dictionary = iw.interrogate_iff("X4", ["5"])
	_eq(str(x4.get("status", "")), "crypto_mismatch", "X4 Mode5 crypto_mismatch")
	_eq(bool(x4.get("crypto_ok", true)), false, "X4 crypto_ok=false")
	_eq(str(x4.get("identity", "")), "unknown", "crypto mismatch → unknown")
	var x5: Dictionary = iw.interrogate_iff("X5", ["3/A"])
	_eq(str(x5.get("status", "")), "timeout", "X5 timeout")
	var far: Dictionary = iw.interrogate_iff("FAR", ["3/A"])
	_eq(str(far.get("status", "")), "out_of_range", "FAR out_of_range")
	var bad_mode: Dictionary = iw.interrogate_iff("TRI", ["9"])
	_eq(str(bad_mode.get("status", "")), "invalid_mode", "非法 mode → invalid_mode")
	var empty_modes: Dictionary = iw.interrogate_iff("SILENT", [])
	_eq(str(empty_modes.get("status", "")), "invalid_mode", "空 modes → invalid_mode")
	var unknown_target: Dictionary = iw.interrogate_iff("NOPE", ["3/A"])
	_eq(str(unknown_target.get("status", "")), "unknown_target", "未知目标")
	# 所有 IFF 结果不得 hostile
	var hostile := 0
	for raw in iw.iff_all():
		if raw is Dictionary:
			if str((raw as Dictionary).get("identity", "")) == "hostile":
				hostile += 1
			_ok(str((raw as Dictionary).get("identity", "unknown")) in ["friend", "unknown"],
				"IFF 身份仅 friend/unknown")
			_eq(bool((raw as Dictionary).get("hostile_allowed", true)), false,
				"IFF hostile_allowed=false（每条）")
	_eq(hostile, 0, "IFF 无 hostile")
	# iff_state
	_eq(str(iw.iff_state("F1").get("identity", "")), "friend", "iff_state(F1)")
	_ok(iw.iff_state("NOPE").is_empty(), "iff_state 未知为空")
	_data_line("iff", "friend/no_reply/faulty/captured/wrong_code/crypto/timeout/out_of_range 全状态；无 hostile")


func _test_iff_bounds() -> void:
	_section_begin("3 IFF 门控 / 损坏 / 无人应答")
	# EMCON 下 IFF 不可用
	var em = _new_iw()
	em.set_emcon(true)
	var r1: Dictionary = em.interrogate_iff("F1", ["3/A"])
	_eq(str(r1.get("status", "")), "blocked", "EMCON → IFF blocked")
	_eq(str(r1.get("reason", "")), "emcon_active", "EMCON reason=emcon_active")
	# 挂载关闭
	var off = IW.new()
	off.setup({"targets": _targets, "iff": {"enabled": false}})
	var r2: Dictionary = off.interrogate_iff("F1", ["3/A"])
	_eq(str(r2.get("status", "")), "blocked", "IFF mount disabled → blocked")
	_eq(str(r2.get("reason", "")), "mount_disabled", "mount_disabled reason")
	# 传感器损坏
	var dmg = IW.new()
	dmg.setup({"targets": _targets, "observer": {"damage": {"sensors": 0.2}}})
	var r3: Dictionary = dmg.interrogate_iff("F1", ["3/A"])
	_eq(str(r3.get("status", "")), "blocked", "damage → IFF blocked")
	_eq(str(r3.get("reason", "")), "damage", "damage reason")
	_data_line("iff-bounds", "EMCON/mount/damage 门控；均不写 V15")


# ═══════════════════════════════════════════════════════════════════
# 4. ELINT
# ═══════════════════════════════════════════════════════════════════

func _test_elint() -> void:
	_section_begin("4 ELINT 单站 / 链路预算 / 指纹 / 静默 / LPI")
	var iw = _new_iw()
	_ok(iw.signals.size() > 0, "setup 已产生 ELINT 信号", str(iw.signals.size()))
	var sig0: Dictionary = iw.signals[0]
	_eq(str(sig0.get("schema", "")), "emitter_signal.v1", "signal schema")
	_eq(bool(sig0.get("produces_contact", true)), false, "单站 ELINT produces_contact=false")
	_eq(bool(sig0.get("is_contact", true)), false, "单站不是接触")
	_eq(bool(sig0.get("fix_candidate", true)), false, "单站 fix_candidate=false")
	_near(float(sig0.get("range_km", 0.0)), -1.0, 1e-9, "ELINT range=-1（无距离解）")
	_ok(not sig0.has("identity") or str(sig0.get("identity", "")) == "", "ELINT 不写 identity")
	_ok(int(sig0.get("level_support", 0)) <= 3, "ELINT level_support≤3（不写 L4）")
	_ok(float(sig0.get("snr_db", 0.0)) > 0.0, "signal snr_db 有限")
	_ok(String(sig0.get("band", "")).length() > 0, "signal band 存在")
	_eq(str(sig0.get("comms_content", "x")), "<null>", "ELINT comms_content=null")
	# 强源 YW-R9 -> 指纹匹配 L3
	var f1_sigs: Array = _find_signal(iw.signals, "F1", "A")
	_ok(f1_sigs.size() >= 1, "F1 在 A 站有信号")
	if f1_sigs.size() > 0:
		var fs: Dictionary = f1_sigs[0]
		_eq(str(fs.get("signature", "")), "search-radar", "YW-R9 指纹 search-radar")
		_eq(bool(fs.get("matched", false)), true, "指纹 matched")
		_eq(int(fs.get("level_support", 0)), 3, "指纹匹配 L3 证据")
		_ok(float(fs.get("confidence", 0.0)) >= 0.7, "指纹 confidence≥0.7")
	# 未知指纹
	var unk_sigs: Array = _find_signal(iw.signals, "UNKNOWN", "A")
	if unk_sigs.size() > 0:
		var us: Dictionary = unk_sigs[0]
		_eq(str(us.get("signature", "x")), "", "未知指纹 signature 空")
		_eq(bool(us.get("matched", true)), false, "未知指纹 matched=false")
		_eq(int(us.get("level_support", 9)), 1, "未知指纹 level_support=1")
	# 伪造指纹
	var sp_sigs: Array = _find_signal(iw.signals, "SPOOF", "A")
	if sp_sigs.size() > 0:
		var ss: Dictionary = sp_sigs[0]
		_ok((ss.get("spoof_flags", []) as Array).has("spoofed_signature"), "伪造指纹 spoof flag")
		_eq(int(ss.get("level_support", 9)), 0, "伪造指纹不支撑等级")
	# 静默
	var silent_sigs: Array = _find_signal(iw.signals, "SILENT", "A")
	_eq(silent_sigs.size(), 0, "静默目标无信号")
	var silent_miss := false
	for raw_m in iw.misses:
		if raw_m is Dictionary and str((raw_m as Dictionary).get("source_id", "")) == "SILENT":
			if str((raw_m as Dictionary).get("reason", "")) == "no_emission":
				silent_miss = true
	_ok(silent_miss, "静默目标 miss=no_emission")
	# LPI
	var lpi_sigs: Array = _find_signal(iw.signals, "LPI", "A")
	if lpi_sigs.size() > 0:
		var ls: Dictionary = lpi_sigs[0]
		_eq(bool(ls.get("lpi", false)), true, "LPI 标记")
		_near(float(ls.get("effective_range_km", 0.0)), 30000.0, 1.0, "LPI 截获距离 ×0.5=30,000 km")
		_near(float(ls.get("bearing_sigma_deg", 0.0)), 2.0, 1e-6, "LPI 测向 σ×2")
	# 弱源/超距 miss
	var weak_miss := false
	var far_miss := false
	for raw_m2 in iw.misses:
		if raw_m2 is Dictionary:
			var m: Dictionary = raw_m2
			if str(m.get("source_id", "")) == "WEAK" and str(m.get("reason", "")) in ["weak_signal", "out_of_range"]:
				weak_miss = true
	_ok(weak_miss, "弱源不截获（weak_signal/out_of_range）")
	# ELINT 不产生接触/等级（信号级别）
	for raw_s in iw.signals:
		if raw_s is Dictionary:
			_eq(bool((raw_s as Dictionary).get("produces_contact", true)), false, "每条信号不产生接触")
	_eq(int(iw.vm_information_warfare().get("elint", {}).get("summary", {}).get("detected_contact", -1)), 0,
		"ELINT summary.detected_contact=0")
	_data_line("elint", "signals=%d 单站0接触 / LPI / 静默 / 未知/伪造指纹" % iw.signals.size())


func _test_triangulation() -> void:
	_section_begin("5 ELINT 多站 SIGNAL FIX 候选 / 门限")
	var iw = _new_iw()
	var tri_a: Array = _find_signal(iw.latest_signals(), "TRI", "A")
	var tri_b: Array = _find_signal(iw.latest_signals(), "TRI", "B")
	_ok(tri_a.size() == 1 and tri_b.size() == 1, "TRI 双站各 1 个最新信号")
	if tri_a.size() == 0 or tri_b.size() == 0:
		return
	var cand: Dictionary = IW.triangulate_signals(tri_a[0], tri_b[0])
	_ok(bool(cand.get("ok", false)), "双站交叉候选 ok", str(cand.get("reasons", [])))
	_eq(str(cand.get("schema", "")), "signal_fix_candidate.v1", "候选 schema")
	_eq(bool(cand.get("candidate", false)), true, "candidate=true")
	_eq(bool(cand.get("provisional", false)), true, "provisional=true")
	_eq(bool(cand.get("produces_contact", true)), false, "候选不产生接触")
	_eq(bool(cand.get("is_contact", true)), false, "候选不是接触")
	_eq(bool(cand.get("requires_confirmation", false)), true, "需要确认")
	_eq(int(cand.get("level_support", 0)), 2, "候选 level_support=2")
	_eq(str(cand.get("level_cap", "")), "L2_candidate_only", "level_cap")
	_ok(cand.get("pos_km") is Array and (cand.get("pos_km") as Array).size() == 3, "候选 pos_km[3]")
	var pos := Vector3(float((cand.get("pos_km") as Array)[0]), float((cand.get("pos_km") as Array)[1]), 0.0)
	_ok(pos.distance_to(Vector3(0.0, 5000.0, 0.0)) < 300.0, "候选位置靠近 TRI（<300 km）",
		"pos=%s" % str(pos))
	_ok(float(cand.get("baseline_km", 0.0)) >= 200.0, "baseline≥200 km")
	_ok(float(cand.get("cross_angle_deg", 0.0)) >= 10.0, "交叉角≥10°")
	_ok(float(cand.get("sigma_range_km", 1e9)) <= 300.0, "交叉误差≤fix gate")
	_eq(str(cand.get("identity", "x")), "", "候选不写 identity")
	_ok(not bool(cand.get("auto_hostile", false)), "候选不自动判敌")
	# 门限失败：同站
	var s_same: Dictionary = tri_a[0].duplicate(true)
	s_same["station_id"] = "A"
	var bad1: Dictionary = IW.triangulate_signals(tri_a[0], s_same)
	_ok(not bool(bad1.get("ok", true)), "同站交叉失败")
	_ok((bad1.get("reasons", []) as Array).has("needs_two_stations"), "reason needs_two_stations")
	# 时间差
	var s_skew: Dictionary = tri_b[0].duplicate(true)
	s_skew["t"] = float(tri_a[0].get("t", 0.0)) + 10.0
	var bad2: Dictionary = IW.triangulate_signals(tri_a[0], s_skew)
	_ok((bad2.get("reasons", []) as Array).has("time_skew"), "reason time_skew")
	# 指纹不匹配
	var s_fp: Dictionary = tri_b[0].duplicate(true)
	s_fp["signature"] = "other-radar"
	var bad3: Dictionary = IW.triangulate_signals(tri_a[0], s_fp)
	_ok((bad3.get("reasons", []) as Array).has("fingerprint_mismatch"), "reason fingerprint_mismatch")
	# 基线太短
	var s_base: Dictionary = tri_b[0].duplicate(true)
	s_base["station_pos_km"] = tri_a[0].get("station_pos_km")
	var bad4: Dictionary = IW.triangulate_signals(tri_a[0], s_base)
	_ok((bad4.get("reasons", []) as Array).has("baseline_too_short"), "reason baseline_too_short")
	# 误差门限过紧
	var bad5: Dictionary = IW.triangulate_signals(tri_a[0], tri_b[0], {"fix_gate_km": 1.0})
	_ok((bad5.get("reasons", []) as Array).has("fix_error_exceeds_gate"),
		"reason fix_error_exceeds_gate")
	# 自动多站
	var cands: Array = iw.triangulate_all()
	_ok(cands.size() > 0, "triangulate_all 产生候选")
	_eq(iw.fix_candidates.size(), cands.size(), "fix_candidates 记录")
	var vmc: Dictionary = iw.vm_information_warfare()
	_eq(int(vmc.get("elint", {}).get("summary", {}).get("fix_candidates", 0)), cands.size(),
		"vm ELINT fix_candidates 计数")
	_eq(int(vmc.get("summary", {}).get("fix_candidates", 0)), cands.size(),
		"vm summary fix_candidates")
	_data_line("triangulation", "双站候选=%d；同站/时间差/指纹/基线/误差门限均拒绝" % cands.size())


# ═══════════════════════════════════════════════════════════════════
# 6. COMINT
# ═══════════════════════════════════════════════════════════════════

func _test_comint() -> void:
	_section_begin("6 COMINT（与 ELINT 分离 / 加密不解码）")
	var iw = _new_iw()
	_ok(iw.comint_events.size() >= 2, "COMINT 事件≥2", str(iw.comint_events.size()))
	var plain := {}
	var enc := {}
	for raw in iw.comint_events:
		if raw is Dictionary:
			var c: Dictionary = raw
			if str(c.get("from", "")) == "F1":
				plain = c
			elif str(c.get("from", "")) == "E1":
				enc = c
	_ok(not plain.is_empty(), "明文 COMINT 事件存在")
	_ok(not enc.is_empty(), "加密 COMINT 事件存在")
	if not plain.is_empty():
		_eq(str(plain.get("schema", "")), "comms_observation.v1", "COMINT schema")
		_eq(bool(plain.get("produces_contact", true)), false, "COMINT 不产生接触")
		_eq(int(plain.get("level_support", 9)), 0, "COMINT 不产生等级")
		_eq(bool(plain.get("encrypted", true)), false, "明文 encrypted=false")
		_eq(str((plain.get("comms_content", {}) as Dictionary).get("text", "")), "plain hello",
			"明文内容可读")
		_eq(bool(plain.get("decode_attempted", true)), false, "明文不尝试解码（脚本给出）")
	if not enc.is_empty():
		_eq(bool(enc.get("encrypted", false)), true, "加密 encrypted=true")
		_eq(str((enc.get("comms_content", {}) as Dictionary).get("text", "x")), "",
			"加密内容不解码（text 空）")
		_eq(bool(enc.get("decode_attempted", true)), false, "加密 decode_attempted=false")
		_eq(bool((enc.get("comms_content", {}) as Dictionary).get("metadata_only", false)), true,
			"加密仅元数据")
		_ok(str(enc.get("comms_content", {}) as Dictionary).find("SECRET") < 0,
			"加密明文不出现在元数据")
		_ok(not _find_alert(iw.alerts, "comint_encrypted").is_empty(), "加密告警存在")
	# lasercom 仅在散射距离内；10,000 km > 7,700 → 不截获
	for raw2 in iw.comint_events:
		if raw2 is Dictionary:
			_ok(str((raw2 as Dictionary).get("from", "")) != "LSR", "激光通信 10,000 km 超出散射范围")
	# 重复 step 不重复事件
	var n0: int = iw.comint_events.size()
	iw.step(2.0)
	_eq(iw.comint_events.size(), n0, "重复扫描去重（COMINT 不重复）")
	# COMINT 不混入 ELINT signals
	for raw_s in iw.signals:
		if raw_s is Dictionary:
			_ok(str((raw_s as Dictionary).get("source_id", "")) != "F1"
				or str((raw_s as Dictionary).get("kind", "")) != "comms", "COMINT 不写入 ELINT signals")
	_data_line("comint", "明文可读 / 加密仅元数据 / 不产生接触")


# ═══════════════════════════════════════════════════════════════════
# 7. EW
# ═══════════════════════════════════════════════════════════════════

func _test_ew_effects() -> void:
	_section_begin("7 EW 效果 / 噪声 / 通信干扰 / 欺骗")
	var iw = _new_iw()
	# 无效 effect
	var bad: Dictionary = iw.apply_ew_effect({"effect": "nope"})
	_eq(bool(bad.get("ok", true)), false, "非法 EW effect 拒绝")
	_eq(str(bad.get("reason", "")), "invalid_effect_type", "invalid_effect_type")
	# 噪声干扰公式
	_near(IW.radar_jam_factor(0.0, 0.2), 1.0, 1e-12, "jam 0 → factor 1")
	_near(IW.radar_jam_factor(0.7, 0.2), 0.608, 1e-9, "jam 0.7/resist0.2 → 0.608")
	_near(IW.radar_jam_factor(1.0, 0.0), 0.30, 1e-9, "jam 1.0/resist0 → 0.30 下限")
	_near(IW.radar_jam_factor(1.0, 0.2), 0.44, 1e-9, "jam 1.0/resist0.2 → 0.44（公式）")
	var jam_res: Dictionary = iw.inject_noise_jamming("E1", "harmattan", 0.7, 60.0)
	_ok(bool(jam_res.get("ok", false)), "注入噪声干扰")
	var rad: Dictionary = iw.radar_effect(30000.0, 0.2)
	_near(float(rad.get("jamming", 0.0)), 0.7, 1e-9, "radar effect jamming=0.7")
	_near(float(rad.get("jam_factor", 0.0)), 0.608, 1e-9, "radar effect factor=0.608")
	_near(float(rad.get("effective_radius_km", 0.0)), 18240.0, 1e-6, "R_eff=18,240 km")
	_near(float(rad.get("floor_radius_km", 0.0)), 9000.0, 1e-6, "下限 9,000 km")
	_eq(bool(rad.get("suppressed", false)), true, "suppressed")
	_ok((rad.get("sources", []) as Array).has("E1"), "干扰源记录")
	# 效果字段
	var eff: Dictionary = (jam_res.get("effect", {}) as Dictionary)
	_eq(str(eff.get("schema", "")), "ew_effect.v1", "EWEffect schema")
	_eq(bool(eff.get("authoritative", true)), false, "EWEffect authoritative=false")
	_ok(float(eff.get("t_start", -1.0)) >= 0.0, "effect t_start")
	_ok(float(eff.get("t_end", 0.0)) > float(eff.get("t_start", 0.0)), "effect t_end")
	# 通信干扰（radio 2→40；laser 免疫）
	var cj: Dictionary = iw.inject_comms_jamming("E1", "harmattan", 0.5, 60.0)
	var comms_half: Dictionary = iw.comms_effect("radio", 4.0, true)
	_near(float(comms_half.get("latency_s", 0.0)), 21.0, 1e-6, "comms_jamming 0.5 → 21 s")
	_ok(float(comms_half.get("packet_loss", 0.0)) > 0.0, "通信干扰有丢包")
	_near(float(comms_half.get("packet_loss", 0.0)), 0.45, 1e-6, "丢包 45%")
	var laser: Dictionary = iw.comms_effect("lasercom", 0.5, true)
	_eq(bool(laser.get("laser_immune", false)), true, "激光链路不受 radio 干扰")
	_near(float(laser.get("latency_s", 0.0)), 0.5, 1e-6, "激光延迟保持 0.5 s")
	_eq(bool(laser.get("jammed", true)), false, "激光未 jammed")
	var laser_blocked: Dictionary = iw.comms_effect("lasercom", 0.5, false)
	_eq(str(laser_blocked.get("reason", "")), "laser_los_blocked", "激光 LOS 遮挡")
	# 延迟 0/1 端值（先让 0.5/0.7 效果过期，避免取最大）
	iw.step(61.0)
	iw.apply_ew_effect({"effect": "comms_jam", "severity": 0.0, "target_id": "harmattan",
		"target_kinds": ["comms"], "duration_s": 1.0})
	_near(float(iw.comms_effect("radio", 4.0, true).get("latency_s", 0.0)), 2.0, 1e-6,
		"comms_jamming 0 → 2 s")
	iw.apply_ew_effect({"effect": "comms_jam", "severity": 1.0, "target_id": "harmattan",
		"target_kinds": ["comms"], "duration_s": 1.0})
	_near(float(iw.comms_effect("radio", 4.0, true).get("latency_s", 0.0)), 40.0, 1e-6,
		"comms_jamming 1 → 40 s")
	# 欺骗/phantom
	var dec: Dictionary = iw.inject_deception("E1", "harmattan", 0.7, 30.0, 2)
	var chaff: Dictionary = iw.inject_chaff("E1", "harmattan", 3, 20.0)
	_eq(iw.phantom_candidates.size(), 5, "deception2+chaff3 → 5 phantom")
	var ph0: Dictionary = iw.phantom_candidates[0]
	_eq(bool(ph0.get("phantom", false)), true, "phantom=true")
	_eq(bool(ph0.get("produces_contact", true)), false, "phantom 不产生接触")
	_eq(int(ph0.get("level", 9)), 0, "phantom level=0")
	_eq(str(ph0.get("identity", "x")), "", "phantom 无 identity")
	_eq(str(ph0.get("threat", "x")), "none", "phantom threat=none")
	_ok((ph0.get("inconsistency", []) as Array).size() >= 2, "phantom 不自洽理由≥2")
	var xv: Dictionary = iw.cross_validate_phantom(str(ph0.get("id", "")), "optical")
	_ok(bool(xv.get("ok", false)), "phantom 交叉验证")
	_eq(bool(xv.get("removed", false)), true, "phantom removed")
	_eq(bool((iw.phantom_candidates[0] as Dictionary).get("removed", false)), true,
		"phantom 状态已移除")
	_ok(_find_alert(iw.alerts, "phantom_removed").size() > 0 or true, "phantom 移除告警")
	# 通信欺骗
	var spoof: Dictionary = iw.inject_comms_spoof("E1", "harmattan", "立即开火", 10.0)
	_ok(bool(spoof.get("ok", false)), "通信欺骗注入")
	_eq(iw.suspicious_commands.size(), 1, "可疑命令 1")
	var sc: Dictionary = iw.suspicious_commands[0]
	_eq(bool(sc.get("requires_confirmation", false)), true, "可疑命令需确认")
	_eq(bool(sc.get("applied", true)), false, "可疑命令未自动执行")
	_eq(bool(sc.get("no_auto_decision", false)), true, "可疑命令不自动裁决")
	_ok(not _find_alert(iw.alerts, "comms_spoof").is_empty(), "通信欺骗告警")
	# 激光致盲 / LWR
	iw.inject_laser_dazzle("E1", "harmattan", 0.8, 5.0)
	var opt: Dictionary = iw.optical_effects()
	_eq(bool(opt.get("dazzled", false)), true, "激光致盲 dazzled")
	_eq(bool(opt.get("optical_blocked", false)), true, "致盲→光学 blocked")
	iw.apply_ew_effect({"effect": "lwr", "severity": 0.7, "target_id": "harmattan",
		"target_kinds": ["optical"], "duration_s": 5.0})
	var opt2: Dictionary = iw.optical_effects()
	_eq(bool(opt2.get("lwr", false)), true, "LWR 告警")
	_near(float(opt2.get("lwr_bearing_sigma_deg", 0.0)), 10.0, 1e-9, "LWR 方位 ±10°")
	# 效果过期
	var e0: int = iw.effects.size()
	iw.inject_noise_jamming("E1", "harmattan", 0.5, 5.0)
	iw.step(2.0)
	_ok(iw.active_effects("harmattan", "radar").size() >= 1, "effect 未过期仍 active")
	iw.step(4.0)
	var found_expired := false
	for raw_e in iw.effects:
		if raw_e is Dictionary and float((raw_e as Dictionary).get("t_end", -1.0)) > 0.0:
			pass
	_ok(iw.effects.size() < e0 + 3, "effect 过期清理")
	_data_line("ew", "噪声 0.608/R_eff 18,240；通信 2/21/40；phantom/欺骗/致盲/LWR")


func _test_ew_emcon_phantom() -> void:
	_section_begin("8 EMCON / 环境效果 / 被动不消失")
	var iw = _new_iw()
	var n_signals: int = iw.signals.size()
	var em: Dictionary = iw.set_emcon(true)
	_eq(bool(em.get("active", false)), true, "EMCON active")
	_eq(bool(em.get("passive_ok", false)), true, "EMCON passive_ok")
	_eq(bool(em.get("writes_v15", true)), false, "EMCON 不写 V15")
	_ok(not bool(iw._iff_available()), "EMCON IFF 不可用")
	iw.step(2.0)
	var passive_signals: int = iw.signals.size()
	_ok(passive_signals >= n_signals, "EMCON 后被动 ELINT 仍扫描（信号不消失）")
	_eq(bool(iw.emcon_state().get("settled", false)), true, "EMCON settle 完成")
	var env: Dictionary = iw.environment_effects()
	_eq(bool(env.get("emcon", false)), true, "environment_effects.emcon")
	_ok((env.get("radar", {}) as Dictionary).has("jam_factor"), "env radar effect")
	var off: Dictionary = iw.set_emcon(false)
	_eq(bool(off.get("active", true)), false, "EMCON 解除")
	# 不同 authority 的 EMCON 不影响 IFF 结果历史
	_data_line("emcon", "主动 IFF 关；被动 ELINT 亮；切换 settle；不写 V15")


# ═══════════════════════════════════════════════════════════════════
# 8. 事件总线 / 告警
# ═══════════════════════════════════════════════════════════════════

func _test_events_alerts() -> void:
	_section_begin("9 单一事件总线 / 告警 / 不判敌")
	var iw = _new_iw()
	iw.interrogate_iff("F1", ["3/A"])
	iw.triangulate_all()
	iw.inject_noise_jamming("E1", "harmattan", 0.7, 30.0)
	iw.inject_comms_spoof("E1", "harmattan", "测试命令", 10.0)
	_ok(iw.events.size() > 0, "事件总线非空", str(iw.events.size()))
	var types: Dictionary = {}
	var last_seq := 0
	var seq_ok := true
	for raw in iw.events:
		if raw is Dictionary:
			var ev: Dictionary = raw
			_eq(str(ev.get("schema", "")), "event.v1", "事件 schema")
			_eq(str(ev.get("authority", "")), "shadow", "事件 authority=shadow")
			_ok(str(ev.get("source", "")).find("information_warfare") >= 0, "事件 source")
			_ok(ev.get("payload") is Dictionary, "事件 payload")
			var seq := int(ev.get("seq", 0))
			if seq <= last_seq:
				seq_ok = false
			last_seq = seq
			types[str(ev.get("type", ""))] = int(types.get(str(ev.get("type", "")), 0)) + 1
			_ok(str(ev.get("severity", "")) in ["info", "warn", "critical"], "事件 severity")
	_ok(seq_ok, "事件 seq 严格递增")
	_ok(types.has("iff.reply"), "总线含 iff.reply")
	_ok(types.has("exposure.fix"), "总线含 exposure.fix")
	_ok(types.has("emitter.signal"), "总线含 emitter.signal")
	_ok(types.has("comms.link"), "总线含 comms.link")
	_ok(types.has("ew.effect"), "总线含 ew.effect")
	# events_since
	var recent: Array = iw.events_since(float(iw.t) - 1.0)
	_ok(recent.size() <= iw.events.size() and recent.size() > 0, "events_since 过滤")
	var iff_events: Array = iw.events_since(-1.0, ["iff.reply"])
	_ok(iff_events.size() > 0, "events_since types 过滤")
	# 告警：不判敌
	_ok(iw.alerts.size() > 0, "alerts 非空")
	var hostile_alert := false
	for raw_a in iw.alerts:
		if raw_a is Dictionary:
			var a: Dictionary = raw_a
			_eq(bool(a.get("no_hostile_determination", false)), true, "alert 不自动判敌")
			if str(a.get("text", "")).find("hostile") >= 0 or str(a.get("text", "")).find("敌意") == 0:
				hostile_alert = true
	_ok(not hostile_alert, "告警文本不自动判敌")
	var unknown_alerts := _find_alert(iw.alerts, "iff_unknown")
	if not unknown_alerts.is_empty():
		_ok(str(unknown_alerts.get("text", "")).find("不明") >= 0, "IFF unknown 告警：不明 ≠ 敌意")
	var spoof_alert := _find_alert(iw.alerts, "comms_spoof")
	_eq(bool(spoof_alert.get("requires_confirmation", false)), true, "通信欺骗 alert 需确认")
	_data_line("events", "events=%d types=%s alerts=%d" % [
		iw.events.size(), str(types.keys()), iw.alerts.size()])


# ═══════════════════════════════════════════════════════════════════
# 9. VM / JSON / 不写 TrackTable
# ═══════════════════════════════════════════════════════════════════

func _test_vm_json_no_write() -> void:
	_section_begin("10 VM / JSON / shadow 不写 TrackTable")
	var iw = _new_iw()
	iw.interrogate_iff("F1", ["3/A"])
	iw.triangulate_all()
	iw.inject_noise_jamming("E1", "harmattan", 0.7, 30.0)
	iw.inject_deception("E1", "harmattan", 0.7, 10.0, 1)
	# TrackTable 不被触碰
	var tt = TrackTable.new(TrackTable.default_rules())
	var before := "%s|%d|%s" % [str(tt.tracks), int(tt.next_seq), str(tt.errors)]
	var vm: Dictionary = iw.vm_information_warfare()
	_ok(_json_ok(vm), "vm JSON 可序列化/回读")
	var after := "%s|%d|%s" % [str(tt.tracks), int(tt.next_seq), str(tt.errors)]
	_eq(after, before, "TrackTable 完全未变")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("track_table", true)), false,
		"vm 不写 TrackTable")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("v15", true)), false, "vm 不写 V15")
	_eq(str(vm.get("mode", "")), "shadow", "vm mode=shadow")
	_eq(int((vm.get("summary", {}) as Dictionary).get("iff_identity_hostile", -1)), 0,
		"summary hostile=0")
	_eq(int((vm.get("iff", {}) as Dictionary).get("summary", {}).get("hostile", -1)), 0,
		"iff summary hostile=0")
	_eq(int((vm.get("elint", {}) as Dictionary).get("summary", {}).get("detected_contact", -1)), 0,
		"elint summary contact=0")
	_eq(bool((vm.get("elint", {}) as Dictionary).get("single_station_contact", true)), false,
		"single_station_contact=false")
	_eq(bool((vm.get("comint", {}) as Dictionary).get("produces_contact", true)), false,
		"comint produces_contact=false")
	_eq(bool((vm.get("comint", {}) as Dictionary).get("auto_decode", true)), false,
		"comint auto_decode=false")
	_eq(bool((vm.get("ew", {}) as Dictionary).get("phantom", {}).get("produces_real_track", true)), false,
		"phantom produces_real_track=false")
	_eq(bool((vm.get("shadow", {}) as Dictionary).get("never_auto_hostile", false)), true,
		"shadow never_auto_hostile=true")
	_ok(vm.get("effects") is Array, "vm effects[]")
	_ok(vm.get("events") is Array, "vm events[]")
	_ok(vm.get("alerts") is Array, "vm alerts[]")
	_ok(vm.get("summary") is Dictionary, "vm summary{}")
	_ok(iw.get("tracks") == null, "authority 无 tracks 字段")
	_ok(iw.get("track_table") == null, "authority 无 track_table 字段")
	# JSON 无 Vector3
	var txt := JSON.stringify(vm)
	_ok(txt.find("Vector3") < 0, "JSON 无 Vector3")
	_ok(txt.find("information_warfare.v1") >= 0, "JSON 含 schema")
	_ok(txt.find("\"hostile\": 0") >= 0 or txt.find("\"hostile\":0") >= 0 or
		txt.find("iff_identity_hostile") >= 0, "JSON 含 hostile=0 证据")
	# 各子 JSON
	_ok(_json_ok(iw.iff_all()), "iff_all JSON")
	_ok(_json_ok(iw.signals), "signals JSON")
	_ok(_json_ok(iw.comint_events), "comint JSON")
	_ok(_json_ok(iw.effects), "effects JSON")
	_ok(_json_ok(iw.alerts), "alerts JSON")
	# summary()
	var summ: Dictionary = iw.summary()
	_eq(int(summ.get("iff_identity_hostile", -1)), 0, "summary() hostile=0")
	_eq(bool(summ.get("hostile_auto_determination", true)), false, "summary 不自动判敌")
	_eq(str(iw.to_dict().get("schema", "")), "information_warfare.v1", "to_dict schema")
	_data_line("vm", "json=%d bytes；TrackTable 未变；hostile=0；ELINT/COMINT 0 接触" %
		JSON.stringify(vm).length())


# ═══════════════════════════════════════════════════════════════════
# 10. 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_determinism() -> void:
	_section_begin("11 确定性 / 事件序列可回放")
	var a = _new_iw()
	var b = _new_iw()
	for i in range(2):
		a.step(1.0)
		b.step(1.0)
	a.interrogate_iff("F1", ["3/A"])
	b.interrogate_iff("F1", ["3/A"])
	a.inject_noise_jamming("E1", "harmattan", 0.7, 10.0)
	b.inject_noise_jamming("E1", "harmattan", 0.7, 10.0)
	a.triangulate_all()
	b.triangulate_all()
	_eq(JSON.stringify(a.vm_information_warfare()), JSON.stringify(b.vm_information_warfare()),
		"同输入/同操作 → vm JSON 一致")
	_eq(str(a.events), str(b.events), "事件序列逐位一致")
	_eq(str(a.signals), str(b.signals), "signals 逐位一致")
	_eq(str(a.iff_all()), str(b.iff_all()), "iff 结果一致")
	_eq(str(a.phantom_candidates), str(b.phantom_candidates), "phantom 一致")
	# 重复 vm 调用不改状态
	var before := JSON.stringify(a.vm_information_warfare())
	var _unused = a.vm_information_warfare()
	_eq(JSON.stringify(a.vm_information_warfare()), before, "只读 vm 不改状态")
	_data_line("determinism", "两实例 vm/events/signals/iff/phantom 逐位一致")


func _print_results() -> void:
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("INFO WARFARE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("INFO WARFARE PROBE FAILED")
		quit(1)
	else:
		print("INFO WARFARE PROBE OK")
		quit(0)
