extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# SENSOR SERVICE PROBE · 完整游戏-阶段2I
#
# 验证：Observation/Evidence 事件管道（雷达/TWS/VIS/IR/IFF）、开关/EMCON、
# 目标/光学通道、无目标/超距/遮挡 reason、不写 TrackTable/world/V15、JSON、
# 确定性。只跑一次；不接 UI/物理。
# ═══════════════════════════════════════════════════════════════════

const SensorService := preload("res://scripts/core/sensor_service.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("SENSOR SERVICE PROBE · 完整游戏-阶段2I")
	print("════════════════════════════════════════════════════════════════")
	_test_setup_and_observations()
	_test_optical_ir_and_evidence()
	_test_controls_emcon()
	_test_iff_evidence()
	_test_failures_and_json()
	print("────────────────────────────────────────────────────────────────")
	print("SENSOR SERVICE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("SENSOR SERVICE PROBE FAILED")
		quit(1)
	else:
		print("SENSOR SERVICE PROBE OK")
		quit(0)


# ── 工具 ─────────────────────────────────────────────────────────

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[PASS] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[FAIL] ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _json_ok(v: Variant) -> bool:
	var s := JSON.stringify(v)
	return s.length() > 2 and not s.contains("<Object") and not s.contains("<Ref") \
		and not s.contains("Vector3")


func _target(id: String, batch: String, pos: Array, transponder: String,
		code: String, side := "unknown") -> Dictionary:
	return {
		"id": id, "target_id": id, "entity_id": "E-" + batch, "batch": batch,
		"pos_km": pos, "vel_kmps": [0.0, 0.0, 0.0],
		"rcs_m2": 10.0, "temp_k": 300.0, "area_m2": 1000.0, "size_m": 50.0,
		"illum": 1.0, "transponder": transponder, "iff_code": code,
		"registered": side == "friend", "crypto_epoch": "epoch-1",
		"side": side, "faction": "test",
		"classification": {"ship_class": "DDG", "role": "test", "faction": side},
	}


func _targets() -> Array:
	return [
		_target("T1", "2001", [0.0, 500.0, 0.0], "ok", "CMP-2001", "friend"),
		_target("T2", "2002", [0.0, 40000.0, 0.0], "off", ""),
		_target("T3", "2003", [0.0, 1000.0, 0.0], "faulty", "OCU-2003"),
	]


func _service(observer_pos := [0.0, 0.0, 0.0], sun := [0.0, 0.0, 1.0]) -> Object:
	return SensorService.new({
		"observer": {"id": "harmattan", "pos_km": observer_pos,
			"vel_kmps": [0.0, 0.0, 0.0], "attitude_quat": [0.0, 0.0, 0.0, 1.0]},
		"targets": _targets(),
		"snapshot": {"sun_dir": sun, "sun_illum": 1.0, "jamming": 0.0,
			"shadow": false, "los": true},
		"options": {"radar_enabled": true, "emcon": false},
	})


func _ev_count(vm: Dictionary, kind: String) -> int:
	var n := 0
	for raw in (vm.get("events", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


func _obs_sensors(vm: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw in (vm.get("observations", []) as Array):
		if raw is Dictionary:
			var s := String((raw as Dictionary).get("sensor", ""))
			out[s] = int(out.get(s, 0)) + 1
	return out


func _channel(vm: Dictionary, kind: String, target := "") -> Dictionary:
	for raw in (vm.get("channels", []) as Array):
		if not (raw is Dictionary):
			continue
		var ch: Dictionary = raw
		if String(ch.get("channel", "")) != kind:
			continue
		if target != "" and String(ch.get("target_id", "")) != target:
			continue
		return ch
	return {}


# ── 1. setup / 雷达观测 ─────────────────────────────────────────

func _test_setup_and_observations() -> void:
	print("")
	print("── 1. setup / 雷达观测事件 ──")
	var s = _service()
	_ok(bool(s.ready), "service ready", str(s.errors))
	_ok((s.errors as Array).is_empty(), "setup 无错误")
	_eq(String((s.observer as Dictionary).get("id", "")), "harmattan", "observer id")
	_ok((s.mounts as Array).size() >= 3, "mounts 默认装配")
	var vm: Dictionary = s.step(6.0)
	_ok(String(vm.get("schema", "")) == "sensor_service.v1", "VM schema")
	_ok(String(vm.get("mode", "")) == "shadow", "mode shadow")
	_ok(bool(vm.get("ready", false)), "VM ready")
	var obs: Array = vm.get("observations", []) if vm.get("observations") is Array else []
	_ok(obs.size() > 0, "step 产生 observations", str(obs.size()))
	var sensors := _obs_sensors(vm)
	_ok(sensors.has("radar") or sensors.has("radar.tws"), "雷达观测存在", str(sensors))
	_ok(int(sensors.get("radar", 0)) + int(sensors.get("radar.tws", 0)) > 0, "radar 观测计数")
	var first: Dictionary = obs[0]
	_eq(String(first.get("schema", "")), "sensor_observation.v1", "observation schema")
	_ok(String(first.get("event_id", "")) != "", "observation event_id")
	_ok(float(first.get("t", -1.0)) >= 0.0, "observation t")
	_ok(not bool(first.get("level_decided", true)), "不判等级")
	_ok(not bool(first.get("produces_contact", true)), "observation 不产生 contact")
	_ok(not bool(first.get("writes_v15", true)), "observation 不写 V15")
	_ok(first.get("position_km") is Array, "position 字段（可为空）")
	_ok(float(first.get("quality", -1.0)) >= 0.0, "observation quality")
	_ok(float(first.get("range_km", -1.0)) >= 0.0, "observation range")
	_ok(float(first.get("bearing_deg", -999.0)) >= -360.0, "observation bearing")
	_ok(String(first.get("sensor_model", "")) != "", "observation sensor_model")
	_ok(String(first.get("provenance", "")) != "", "observation provenance")
	var tws_ch := _channel(vm, "radar.tws")
	_ok(not tws_ch.is_empty(), "TWS channel 存在")
	_ok(String(tws_ch.get("sensor_model", "")) != "", "TWS sensor_model")
	_ok(tws_ch.has("hits"), "TWS hits 字段")
	_ok(int((vm.get("counts", {}) as Dictionary).get("events", 0)) > 0, "counts.events")
	_ok(_ev_count(vm, "observation") > 0 or obs.size() > 0, "observation event 可检索")
	_ok((vm.get("channels", []) as Array).size() > 0, "TWS/传感器 channels")
	_ok((vm.get("counts", {}) as Dictionary).has("observations"), "counts observations")
	_ok(_json_ok(vm), "VM JSON")
	_ok(((vm.get("writes", {}) as Dictionary).get("track_table", true)) == false, "不写 TrackTable")
	_ok(((vm.get("writes", {}) as Dictionary).get("v15", true)) == false, "不写 V15")
	_ok(((vm.get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
	# 同输入确定性
	var s2 = _service()
	var vm2: Dictionary = s2.step(6.0)
	_ok(JSON.stringify(vm) == JSON.stringify(vm2), "setup/step 确定性")


# ── 2. VIS/IR 通道 + Evidence ───────────────────────────────────

func _test_optical_ir_and_evidence() -> void:
	print("")
	print("── 2. VIS/IR / 目标 / 光学 Evidence ──")
	var s = _service()
	var vm: Dictionary = s.step(6.0)
	var before_evidence := (vm.get("evidence", []) as Array).size()
	_ok(bool(s.set_target("T1").get("ok", false)), "set_target T1")
	var so: Dictionary = s.start_channel("optical", "T1")
	_ok(bool(so.get("ok", false)), "start optical T1")
	var si: Dictionary = s.start_channel("ir", "T1")
	_ok(bool(si.get("ok", false)), "start IR T1")
	vm = s.step(30.0)
	var vis := _channel(vm, "optical")
	var ir := _channel(vm, "ir")
	_ok(not vis.is_empty(), "optical channel 存在")
	_ok(not ir.is_empty(), "IR channel 存在")
	_ok(String(vis.get("status", "")) == "locked", "VIS locked", String(vis.get("status", "")))
	_ok(String(ir.get("status", "")) == "locked", "IR locked", String(ir.get("status", "")))
	_ok(float(vis.get("fov_deg", 0.0)) > 0.0, "VIS FOV")
	_ok(float(vis.get("ifov_urad", 0.0)) > 0.0, "VIS IFOV")
	_ok(float(vis.get("snr_db", 0.0)) > 0.0, "VIS SNR")
	_ok(not bool(vis.get("occluded", true)), "VIS 无遮挡")
	_ok(float(vis.get("off_axis_deg", -1.0)) >= 0.0, "VIS off_axis")
	_ok(bool(vis.get("detected", false)), "VIS detected")
	_ok(String(vis.get("backend", "")) == "optical_ir", "VIS backend")
	_ok(int(ir.get("level_support", 0)) == 1, "IR L1（不分类）")
	var ir_obs := _obs_sensors(vm)
	_ok(ir_obs.has("optical") or ir_obs.has("ir"), "光学/IR observation 类型", str(ir_obs))
	var ev: Array = vm.get("evidence", []) if vm.get("evidence") is Array else []
	_ok(ev.size() > before_evidence, "光学 Evidence 产生")
	var opt_ev: Dictionary = {}
	for raw in ev:
		if raw is Dictionary and String((raw as Dictionary).get("evidence_type", "")) == "optical":
			opt_ev = raw
	_ok(not opt_ev.is_empty(), "optical evidence 存在")
	_eq(int(opt_ev.get("support", 0)), 3, "optical evidence support=3")
	_ok(not bool(opt_ev.get("produces_contact", true)), "evidence 不产生 contact")
	_ok(not bool(opt_ev.get("produces_position", true)), "evidence 不产生位置")
	_ok(not bool(opt_ev.get("level_decided", true)), "evidence 不判等级")
	_ok(not (opt_ev.get("classification", {}) as Dictionary).is_empty(), "evidence classification")
	var sensors := _obs_sensors(vm)
	_ok(sensors.has("optical") or sensors.has("ir"), "VIS/IR 观测存在", str(sensors))
	_ok(int(vm.get("counts", {}).get("optical_evidence", 0)) >= 1, "counts optical_evidence")
	_ok(_json_ok(opt_ev), "evidence JSON")
	_ok(_json_ok(vm), "VIS/IR VM JSON")
	# 通道停止
	var st: Dictionary = s.stop_channel("optical", "T1")
	_ok(bool(st.get("ok", false)), "stop optical T1")
	_ok(String(_channel(s.vm(), "optical", "T1").get("status", "off")) in ["off", "idle"],
		"stop 后 optical 状态")


# ── 3. 开关 / EMCON ────────────────────────────────────────────

func _test_controls_emcon() -> void:
	print("")
	print("── 3. 雷达开关 / EMCON ──")
	var s = _service()
	s.step(6.0)
	_ok(bool(s.radar_enabled), "初始 radar=true")
	var radar_before: int = int((s.vm().get("counts", {}) as Dictionary).get("radar_obs", 0))
	var off: Dictionary = s.set_radar_enabled(false)
	_ok(bool(off.get("ok", false)), "set_radar_enabled(false)")
	_ok(not bool(s.radar_enabled), "radar=false")
	_ok(bool(s.emcon), "emcon=true")
	var vm: Dictionary = s.step(6.0)
	_ok(not bool(vm.get("radar_enabled", true)), "VM radar=false")
	_ok(bool(vm.get("emcon", false)), "VM emcon=true")
	_ok(_ev_count(vm, "radar") > 0, "radar off event")
	_ok(int((vm.get("counts", {}) as Dictionary).get("radar_obs", 0)) <= radar_before,
		"off 后不新增雷达观测")
	# EMCON 下 IFF blocked
	var blocked: Dictionary = s.query_iff("T1")
	_ok(bool(blocked.get("ok", true)), "EMCON 下 IFF 返回证据")
	_eq(String(blocked.get("status", "")), "blocked", "IFF blocked")
	var on: Dictionary = s.set_radar_enabled(true)
	_ok(bool(on.get("ok", false)), "set_radar_enabled(true)")
	_ok(bool(s.radar_enabled), "radar=true")
	_ok(not bool(s.emcon), "emcon=false")
	s.step(6.0)
	_ok(bool((s.vm().get("radar_enabled", false))), "VM radar 恢复")
	# explicit emcon
	_ok(bool(s.set_emcon(true).get("ok", false)), "set_emcon(true)")
	_ok(bool(s.emcon), "emcon explicit")
	_ok(bool(s.set_emcon(false).get("ok", false)), "set_emcon(false)")
	_ok(not bool(s.emcon), "emcon off")
	_ok(_json_ok(s.vm()), "controls VM JSON")


# ── 4. IFF 证据 ───────────────────────────────────────────────

func _test_iff_evidence() -> void:
	print("")
	print("── 4. IFF 身份证据 / 不产生位置接触 ──")
	var s = _service()
	s.step(6.0)
	var before := (s.vm().get("observations", []) as Array).size()
	var r1: Dictionary = s.query_iff("T1")
	_ok(bool(r1.get("ok", false)), "IFF T1 ok")
	_eq(String(r1.get("status", "")), "friend", "T1 friend")
	_eq(String(r1.get("identity", "")), "friend", "T1 identity friend")
	_ok(bool(r1.get("never_hostile", false)), "T1 never_hostile")
	var e1: Dictionary = r1.get("evidence", {}) as Dictionary
	_eq(String(e1.get("schema", "")), "track_evidence.v1", "IFF evidence schema")
	_eq(String(e1.get("evidence_type", "")), "iff", "IFF evidence type")
	_eq(int(e1.get("support", 0)), 4, "IFF support=4")
	_ok(not bool(e1.get("produces_contact", true)), "IFF 不产生 contact")
	_ok(not bool(e1.get("produces_position", true)), "IFF 不产生位置")
	_ok(not bool(e1.get("hostile", true)), "IFF 不 hostile")
	_ok(not (e1.get("pos_km") is Array) and not (e1.get("position_km") is Array),
		"IFF evidence 无位置")
	_ok(String(e1.get("event_id", "")) != "", "IFF evidence event_id")
	_ok(String(e1.get("status", "")) == "friend", "IFF evidence status")
	_ok(String(e1.get("raw_status", "")) == "reply_ok", "IFF raw status")
	_ok(not bool(e1.get("level_decided", true)), "IFF 不判等级")
	# no_reply/faulty/out_of_range
	_eq(String(s.query_iff("T3").get("status", "")), "faulty_transponder", "T3 faulty")
	_eq(String(s.query_iff("T2").get("status", "")), "out_of_range", "T2 out_of_range")
	_eq(String(s.query_iff("NOPE").get("reason", "")), "unknown_target", "IFF 未知目标")
	_eq(String(s.query_iff("").get("reason", "")), "no_target", "IFF 未选目标")
	_ok((s.vm().get("observations", []) as Array).size() == before, "IFF 不增 observation")
	_ok((s.vm().get("evidence", []) as Array).size() >= 3, "IFF evidence 累计")
	var vm: Dictionary = s.vm()
	var iff_n := 0
	for raw in (vm.get("evidence", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("evidence_type", "")) == "iff":
			iff_n += 1
	_ok(iff_n >= 3, "IFF evidence 计数")
	_ok(_json_ok(vm), "IFF VM JSON")
	_ok(((vm.get("writes", {}) as Dictionary).get("track_table", true)) == false, "IFF 不写 TrackTable")


# ── 5. 失败 reason / JSON / 确定性 ──────────────────────────────

func _test_failures_and_json() -> void:
	print("")
	print("── 5. 无目标/超距/遮挡 / JSON / 确定性 ──")
	var s = _service()
	_ok(not bool(s.set_target("NOPE").get("ok", true)), "set_target 未知 false")
	_ok(not bool(s.start_channel("optical", "NOPE").get("ok", true)), "start 未知目标 false")
	_ok(not bool(s.start_channel("lidar", "T1").get("ok", true)), "start 非法 kind false")
	_ok(not bool(s.stop_channel("optical", "NOPE").get("ok", true)), "stop 无匹配 false")
	s.step(6.0)
	# 超距/视轴外：远目标建光学通道，step 后 reason
	var rf: Dictionary = s.start_channel("optical", "T2", {"boresight_deg": 0.0})
	_ok(bool(rf.get("ok", false)), "远目标通道建立")
	var vm: Dictionary = s.step(60.0)
	var far := _channel(vm, "optical", "T2")
	_ok(not far.is_empty(), "远目标 channel 存在")
	_ok(String(far.get("status", "")) == "lost", "远目标 lost")
	_ok(String(far.get("reason", "")) in ["out_of_range", "fov_miss", "low_snr", "too_dark"],
		"远目标 reason", String(far.get("reason", "")))
	_ok(not bool(far.get("detected", true)), "远目标 detected=false")
	_ok(bool(far.has("snr_db")), "远目标 SNR 字段")
	_ok(int((vm.get("counts", {}) as Dictionary).get("observations", 0)) > 0, "失败步骤仍记录观测/事件")
	# 地球遮挡：observer 7000，target 地球背面，boresight -90
	var sc = SensorService.new({
		"observer": {"id": "harmattan", "pos_km": [7000.0, 0.0, 0.0]},
		"targets": [_target("O1", "9001", [-7000.0, 0.0, 0.0], "off", "")],
		"snapshot": {"sun_dir": [0.0, 0.0, 1.0]},
	})
	_ok(bool(sc.ready), "遮挡 service ready")
	_ok(bool(sc.start_channel("optical", "O1", {"boresight_deg": -90.0}).get("ok", false)),
		"遮挡通道建立")
	var vmc: Dictionary = sc.step(1.0)
	var oc := _channel(vmc, "optical", "O1")
	_ok(String(oc.get("reason", "")) == "occluded", "遮挡 reason=occluded")
	_ok(bool(oc.get("occluded", false)), "遮挡 occluded=true")
	# 事件 outbox / events
	var s2 = _service()
	s2.step(6.0)
	var outbox: Array = s2.take_events()
	_ok(outbox is Array and outbox.size() > 0, "take_events 非空")
	_ok(_json_ok(s2.vm()), "最终 VM JSON")
	_ok(_json_ok(s2.summary()), "summary JSON")
	_ok(_json_ok(s2.events), "events JSON")
	# 确定性（完整流程）
	var a = _service()
	var b = _service()
	for svc in [a, b]:
		svc.set_target("T1")
		svc.start_channel("optical", "T1")
		svc.step(6.0)
		svc.query_iff("T1")
	_ok(JSON.stringify(a.vm()) == JSON.stringify(b.vm()), "确定性 VM")
	_ok(JSON.stringify(a.take_events()) == JSON.stringify(b.take_events()), "确定性 events")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "最终不写 TrackTable")
