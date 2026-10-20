extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# TRANSIT SENSOR PROBE · 阶段2-TRANSIT-SENSOR-1
#
# 验证：5 舰/4 港真实几何、球形雷达/TWS、VIS/IR（FOV/遮挡/光照/SNR/
# 凝视/锁定/失败 reason）、observer 切换、目标选择、JSON、不写、确定性。
# 只跑一次；不接 UI/HUD；不写 world/V15。
#
# 运行：
#   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
#       --path .\game_v17 --script res://tests/transit_sensors_probe.gd
# 期望末行 TRANSIT SENSOR PROBE OK，退出码 0。
# ═══════════════════════════════════════════════════════════════════

const TransitSensors := preload("res://scripts/transit_sensors.gd")
const Authority := preload("res://framework/sim/sensor_authority.gd")
const SHIP_IDS := ["apsis", "harmattan", "ferry", "watchtower", "deepwell"]
const PORT_IDS := ["l4_02_hammer", "l1_meridian_05", "l1_anchorage_02", "l1_drydock_01"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("TRANSIT SENSOR PROBE · 阶段2-TRANSIT-SENSOR-1")
	print("════════════════════════════════════════════════════════════════")
	_test_content()
	_test_default_step()
	_test_ship_observers()
	_test_targets_and_failures()
	_test_arrival_ports()
	_test_controls_iff()
	_test_json_determinism_writes()
	print("────────────────────────────────────────────────────────────────")
	print("TRANSIT SENSOR PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("TRANSIT SENSOR PROBE FAILED")
		quit(1)
	else:
		print("TRANSIT SENSOR PROBE OK")
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


func _new(observer := "harmattan", target := "apsis") -> Object:
	return TransitSensors.new({"observer_id": observer, "target_id": target})


func _channel(vm: Dictionary, kind: String, target: String) -> Dictionary:
	var opt: Dictionary = vm.get("optical", {}) if vm.get("optical") is Dictionary else {}
	for raw in (opt.get("channels", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("channel", "")) == kind \
				and String((raw as Dictionary).get("target_id", "")) == target:
			return raw
	return {}


func _status_of(vm: Dictionary, target: String) -> String:
	for raw in (vm.get("targets", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == target:
			return String((raw as Dictionary).get("reason", ""))
	return ""


# ── 1. 数据装载 / 5 舰 4 港 ─────────────────────────────────────

func _test_content() -> void:
	print("")
	print("── 1. 转场数据 / 5 舰 / 4 港 ──")
	var ts = _new()
	_ok(bool(ts.ready), "ready", str(ts.errors))
	_ok((ts.errors as Array).is_empty(), "setup 无错误", str(ts.errors))
	_ok(bool(ts.plan.get("ok", false)), "transfer_planner ok", String(ts.plan.get("reason", "")))
	_ok(float(ts.tof_s) > 0.0, "tof_s > 0", str(ts.tof_s))
	_ok(float(ts.tof_s) > 86400.0, "tof 为真实多日转移", "%.1f s" % float(ts.tof_s))
	_eq((ts.ships as Array).size(), 5, "5 舰")
	_eq((ts.ports as Array).size(), 4, "4 港")
	var sids: Array = []
	var batches: Array = []
	for raw in (ts.ships as Array):
		var sh: Dictionary = raw
		sids.append(String(sh.get("id", "")))
		batches.append(String(sh.get("batch", "")))
	for sid in SHIP_IDS:
		_ok(sids.has(sid), "舰 %s 存在" % sid)
	for b in ["1000", "1001", "1002", "1003", "1004"]:
		_ok(batches.has(b), "批号 %s 存在" % b)
	var pids: Array = []
	var plpoints: Array = []
	for raw in (ts.ports as Array):
		var pt: Dictionary = raw
		pids.append(String(pt.get("id", "")))
		plpoints.append(String(pt.get("lpoint", "")))
	for pid in PORT_IDS:
		_ok(pids.has(pid), "港 %s 存在" % pid)
	_ok(plpoints.has("L4") and plpoints.has("L1"), "L4/L1 港群都在")
	var vm: Dictionary = ts.vm()
	_ok(String(vm.get("schema", "")) == "transit_sensor_data.v1", "VM schema")
	_ok(String(vm.get("mode", "")) == "shadow", "mode=shadow")
	_ok(_json_ok(vm), "VM JSON")
	_eq((vm.get("targets", []) as Array).size(), 8, "默认 8 目标（4 舰 + 4 港）")
	_ok(String((vm.get("selected_target", ""))) == "apsis", "默认 target=apsis")
	_eq(String(vm.get("observer_ship", "")), "harmattan", "默认 observer=harmattan")
	_ok((vm.get("warnings", []) as Array).size() > 0, "warnings 非空")
	_ok(((vm.get("writes", {}) as Dictionary).get("track_table", true)) == false, "writes.track_table=false")
	_ok(((vm.get("writes", {}) as Dictionary).get("v15", true)) == false, "writes.v15=false")


# ── 2. 默认观测：雷达/光学 ───────────────────────────────────────

func _test_default_step() -> void:
	print("")
	print("── 2. 雷达 / TWS / VIS / IR（默认 harmattan→apsis）──")
	var ts = _new()
	var vm: Dictionary = ts.step(18.0)
	_ok(_json_ok(vm), "step VM JSON")
	_ok(String(vm.get("phase", "")) in ["departure", "cruise"], "phase 有效", String(vm.get("phase", "")))
	_ok(int((vm.get("step_count", 0))) == 1, "step_count=1")
	var contacts: Array = vm.get("contacts", []) if vm.get("contacts") is Array else []
	_ok(contacts.size() >= 5, "雷达产生 ≥5 contacts", str(contacts.size()))
	var chans: Array = vm.get("channels", []) if vm.get("channels") is Array else []
	_ok(chans.size() >= 6, "channels ≥6（TWS+VIS+IR）", str(chans.size()))
	var tws_n := 0
	for raw in chans:
		if raw is Dictionary and String((raw as Dictionary).get("channel", "")) == "radar.tws":
			tws_n += 1
	_ok(tws_n >= 5, "TWS 通道 ≥5", str(tws_n))
	var vis := _channel(vm, "optical", "apsis")
	var ir := _channel(vm, "ir", "apsis")
	_ok(not vis.is_empty(), "VIS 通道存在")
	_ok(not ir.is_empty(), "IR 通道存在")
	_ok(String(vis.get("status", "")) == "locked", "VIS locked", String(vis.get("status", "")))
	_ok(String(ir.get("status", "")) == "locked", "IR locked", String(ir.get("status", "")))
	_eq(int(vis.get("level_support", 0)), 3, "VIS L3")
	_eq(int(ir.get("level_support", 0)), 1, "IR L1")
	_ok(float(vis.get("fov_deg", 0.0)) > 0.0, "VIS FOV >0")
	_ok(float(vis.get("ifov_urad", 0.0)) > 0.0, "VIS IFOV >0")
	_ok(float(vis.get("snr_db", 0.0)) > 0.0, "VIS SNR >0")
	_ok(float(ir.get("fov_deg", 0.0)) > 0.0, "IR FOV >0")
	_ok(float(ir.get("snr_db", 0.0)) > 0.0, "IR SNR >0")
	_ok(not bool(vis.get("occluded", true)), "VIS 无遮挡")
	_ok(String(vis.get("backend", "")) == "optical_ir", "VIS backend=optical_ir")
	_ok(float(vis.get("off_axis_deg", -1.0)) >= 0.0, "VIS off-axis 字段")
	var target_rows: Array = vm.get("targets", []) as Array
	var apsis_row: Dictionary = {}
	var l4_row: Dictionary = {}
	for raw in target_rows:
		if raw is Dictionary:
			if String((raw as Dictionary).get("id", "")) == "apsis":
				apsis_row = raw
			elif String((raw as Dictionary).get("id", "")) == "l4_02_hammer":
				l4_row = raw
	_ok(not apsis_row.is_empty(), "target 行 apsis")
	_eq(int(apsis_row.get("level", 0)), 3, "apsis 聚合 L3")
	_ok(float(apsis_row.get("range_km", 0.0)) > 0.0 and float(apsis_row.get("range_km", 0.0)) < 200.0,
		"apsis 近距离", str(apsis_row.get("range_km", 0.0)))
	_ok(not l4_row.is_empty(), "L4 港 target 行")
	_ok(int(l4_row.get("level", 0)) >= 1, "L4 港雷达接触", str(l4_row.get("level", 0)))
	var levels: Dictionary = vm.get("levels", {}) as Dictionary
	_ok((levels.get("by_target", {}) as Dictionary).has("apsis"), "levels by_target apsis")
	_ok(int(levels.get("max_level", 0)) >= 3, "levels.max_level≥3", str(levels.get("max_level", 0)))
	_ok((levels.get("counts", {}) as Dictionary).has("3"), "levels counts 有 L3")
	var optical: Dictionary = vm.get("optical", {}) as Dictionary
	_ok(String(optical.get("backend", "")) == "optical_ir", "optical.backend=optical_ir")
	_ok((optical.get("channels", []) as Array).size() == 2, "optical.channels=2")
	var ev: Array = vm.get("events", []) if vm.get("events") is Array else []
	_ok(ev is Array, "events[]")
	_ok((vm.get("warnings", []) as Array).size() >= 4, "warnings 完整")
	# 无目标的失败原因：L1 港在起飞段超出 VIS 有效距离 → 明确 reason
	var l1_row: Dictionary = {}
	for raw in target_rows:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == "l1_meridian_05":
			l1_row = raw
	_ok(not l1_row.is_empty(), "L1 港 target 行")
	_ok(float(l1_row.get("range_km", 0.0)) > 100000.0, "起飞段 L1 港超远", str(l1_row.get("range_km", 0.0)))
	_ok(int(l1_row.get("level", 0)) == 0, "起飞段 L1 港无接触")
	var r: Dictionary = ts.start_optical("optical", "l1_meridian_05")
	_ok(bool(r.get("ok", false)), "超距目标可建通道（随后失败）")
	vm = ts.step(80.0)
	var far := _channel(vm, "optical", "l1_meridian_05")
	_ok(not far.is_empty(), "超距 channel 存在")
	_ok(String(far.get("status", "")) == "lost", "超距 VIS lost", String(far.get("status", "")))
	var far_reason := String(far.get("reason", ""))
	_ok(far_reason in ["out_of_range", "fov_miss", "low_snr", "too_dark"], "超距原因明确", far_reason)


# ── 3. 5 舰均可作为 observer ────────────────────────────────────

func _test_ship_observers() -> void:
	print("")
	print("── 3. 5 舰 observer / capability fallback ──")
	var expect_fallback := {
		"apsis": ["search_radar"],
		"harmattan": [],
		"ferry": ["search_radar", "ir"],
		"watchtower": ["search_radar", "optical", "ir"],
		"deepwell": ["search_radar", "optical", "ir"],
	}
	for sid in SHIP_IDS:
		var ts = _new()
		var r: Dictionary = ts.select_ship(sid)
		_ok(bool(r.get("ok", false)), "%s select_ship ok" % sid)
		_eq(String(r.get("observer", "")), sid, "%s observer 字段" % sid)
		var fb: Array = r.get("fallbacks", []) if r.get("fallbacks") is Array else []
		_eq(fb.size(), (expect_fallback.get(sid, []) as Array).size(), "%s fallback 数量" % sid)
		for m in (expect_fallback.get(sid, []) as Array):
			_ok(fb.has(m), "%s fallback %s" % [sid, String(m)])
		var other := "apsis" if sid != "apsis" else "harmattan"
		_ok(bool(ts.set_target(other).get("ok", false)), "%s set_target %s" % [sid, other])
		var vm: Dictionary = ts.step(18.0)
		_ok(bool(vm.get("ready", false)), "%s VM ready" % sid)
		_eq(String(vm.get("observer_ship", "")), sid, "%s VM observer" % sid)
		_eq((vm.get("ships", []) as Array).size(), 5, "%s 5 ships" % sid)
		_eq((vm.get("ports", []) as Array).size(), 4, "%s 4 ports" % sid)
		_eq((vm.get("targets", []) as Array).size(), 8, "%s 8 targets" % sid)
		_ok((vm.get("contacts", []) as Array).size() >= 4, "%s contacts" % sid)
		_ok((vm.get("channels", []) as Array).size() >= 4, "%s channels" % sid)
		_ok((vm.get("optical", {}) as Dictionary).get("channels", []) is Array, "%s optical channels" % sid)
		_ok(_json_ok(vm), "%s VM JSON" % sid)
		var any_vis := false
		for raw in ((vm.get("optical", {}) as Dictionary).get("channels", []) as Array):
			if raw is Dictionary and String((raw as Dictionary).get("channel", "")) == "optical":
				any_vis = true
		_ok(any_vis, "%s VIS 自动通道" % sid)


# ── 4. 目标选择 / 光学失败 / 遮挡 ───────────────────────────────

func _test_targets_and_failures() -> void:
	print("")
	print("── 4. set_target / 光学失败 / 遮挡 / stop ──")
	var ts = _new()
	ts.step(18.0)
	var bad: Dictionary = ts.set_target("does_not_exist")
	_ok(not bool(bad.get("ok", false)), "set_target 未知目标 false")
	var bad2: Dictionary = ts.set_target("ferry")
	_ok(bool(bad2.get("ok", false)), "set_target ferry true")
	var vm: Dictionary = ts.vm()
	_eq(String(vm.get("selected_target", "")), "ferry", "selected_target 更新")
	for pid in PORT_IDS:
		_ok(bool(ts.set_target(pid).get("ok", false)), "set_target 港 %s" % pid)
	# 光学 FOV 失败：先锁 apsis，再把另一通道指向 l4 港（不同方位）
	ts.set_target("apsis")
	ts.step(12.0)
	var r1: Dictionary = ts.start_optical("optical", "l4_02_hammer")
	_ok(bool(r1.get("ok", false)), "start optical l4 港")
	ts.step(60.0)
	vm = ts.vm()
	var apsis_vis := _channel(vm, "optical", "apsis")
	var l4_vis := _channel(vm, "optical", "l4_02_hammer")
	_ok(not apsis_vis.is_empty() and String(apsis_vis.get("status", "")) in ["lost", "locked"],
		"apsis VIS 状态可读", String(apsis_vis.get("status", "")))
	_ok(not l4_vis.is_empty(), "l4 VIS 存在")
	_ok(String(l4_vis.get("status", "")) != "idle", "l4 VIS 已推进", String(l4_vis.get("status", "")))
	var fov_or_reason := String(apsis_vis.get("reason", "")) in ["fov_miss", "blurred", "out_of_range", ""]
	_ok(fov_or_reason, "VIS 失败/成功 reason 合法", String(apsis_vis.get("reason", "")))
	# 无效 API
	_ok(not bool(ts.start_optical("optical", "nope").get("ok", false)), "start_optical 未知目标 false")
	_ok(not bool(ts.start_optical("lidar", "apsis").get("ok", false)), "start_optical 非法 kind false")
	_ok(not bool(ts.stop_optical("", "does_not_exist").get("ok", false)), "stop_optical 无匹配 false")
	var stop: Dictionary = ts.stop_optical()
	_ok(bool(stop.get("ok", false)), "stop_optical 全部成功")
	ts.step(6.0)
	vm = ts.vm()
	_ok(((vm.get("optical", {}) as Dictionary).get("channels", []) as Array).is_empty(),
		"stop 后 optical channels 空")

	# 地球遮挡：使用 authority + optical_ir 的真实几何（observer 7000km，target 地球背面）
	var auth = Authority.new()
	var obs := {"id": "X", "pos_km": [7000.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}
	var tgt := {"id": "T", "entity_id": "T", "pos_km": [-7000.0, 0.0, 0.0],
		"rcs_m2": 10.0, "temp_k": 300.0, "area_m2": 1000.0, "illum": 1.0,
		"classification": {"ship_class": "DDG"}}
	auth.setup({"observer": obs, "targets": [tgt]})
	auth.start_channel("optical", "T", {"boresight_deg": -90.0})
	auth.step(1.0)
	var oc := auth.channel("optical", "T")
	_ok(String(oc.get("reason", "")) == "occluded", "地球遮挡 reason=occluded")
	_ok(bool(oc.get("occluded", false)), "地球遮挡 occluded=true")


# ── 5. 抵达 L1 / 港群 ───────────────────────────────────────────

func _test_arrival_ports() -> void:
	print("")
	print("── 5. 抵达 L1 / 港群观测 ──")
	var ts = _new()
	ts.step(6.0)
	var vm: Dictionary = ts.seek(ts.tof_s)
	_ok(String(vm.get("phase", "")) == "arrival", "seek 到 arrival", String(vm.get("phase", "")))
	vm = ts.step(6.0)
	_ok(_json_ok(vm), "arrival VM JSON")
	var port_rows: Dictionary = {}
	for raw in (vm.get("ports", []) as Array):
		if raw is Dictionary:
			port_rows[String((raw as Dictionary).get("id", ""))] = raw
	_eq(port_rows.size(), 4, "arrival 4 港")
	for pid in PORT_IDS:
		_ok(port_rows.has(pid), "arrival 港行 %s" % pid)
	_ok(float((port_rows.get("l1_meridian_05", {}) as Dictionary).get("range_km", 999999.0)) < 1000.0,
		"L1 Meridian 近距离", str((port_rows.get("l1_meridian_05", {}) as Dictionary).get("range_km", 0.0)))
	_ok(float((port_rows.get("l4_02_hammer", {}) as Dictionary).get("range_km", 0.0)) > 100000.0,
		"L4 港远距", str((port_rows.get("l4_02_hammer", {}) as Dictionary).get("range_km", 0.0)))
	var l1_contacts := 0
	for raw in (vm.get("contacts", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("target_id", "")) in PORT_IDS \
				and String((raw as Dictionary).get("target_id", "")) != "l4_02_hammer":
			l1_contacts += 1
	_ok(l1_contacts >= 2, "抵达段 L1 港雷达接触 ≥2", str(l1_contacts))
	_ok(bool(ts.set_target("l1_meridian_05").get("ok", false)), "抵达 set_target L1 港")
	var r: Dictionary = ts.start_optical("optical", "l1_meridian_05")
	_ok(bool(r.get("ok", false)), "抵达 start optical L1 港")
	ts.step(12.0)
	var ch := _channel(ts.vm(), "optical", "l1_meridian_05")
	_ok(not ch.is_empty(), "抵达 L1 港 VIS channel")
	_ok(String(ch.get("status", "")) in ["locked", "staring", "lost", "acquiring"],
		"抵达 L1 港 VIS 状态", String(ch.get("status", "")))
	_ok(float(ch.get("fov_deg", 0.0)) > 0.0, "抵达 VIS FOV")
	_ok(float(ch.get("snr_db", 0.0)) > 0.0, "抵达 VIS SNR")


# ── 6. JSON / 确定性 / 不写 ────────────────────────────────────

func _test_controls_iff() -> void:
	print("")
	print("── 7. 雷达/EMCON 开关 + 真实 IFF ──")
	var ts = _new()
	var vm: Dictionary = ts.step(18.0)
	_ok(bool(vm.get("radar_enabled", false)), "初始 radar_enabled=true")
	_ok(not bool(vm.get("emcon", true)), "初始 EMCON=false")
	_ok((vm.get("contacts", []) as Array).size() >= 5, "初始雷达 contact ≥5")
	var exp: Dictionary = vm.get("exposure", {}) as Dictionary
	_ok(bool(exp.get("exposed", false)), "雷达开机 → exposed=true", str(exp.keys()))
	_ok(float(exp.get("elint_intercept_range_km", 0.0)) > 0.0, "暴露 distance 字段")
	var before_contacts := (vm.get("contacts", []) as Array).size()
	# 关雷达 → EMCON / 无主动接触
	var off: Dictionary = ts.set_radar_enabled(false)
	_ok(bool(off.get("ok", false)), "set_radar_enabled(false) ok")
	_ok(not bool(off.get("radar_enabled", true)), "返回 radar_enabled=false")
	_ok(bool(off.get("emcon", false)), "关雷达 → EMCON=true")
	_ok(String(off.get("reason", "")) == "radar_off_emcon", "关雷达 reason")
	_ok(not bool((off.get("exposure", {}) as Dictionary).get("exposed", true)), "off exposure=false")
	var voff: Dictionary = ts.step(6.0)
	_ok(not bool(voff.get("radar_enabled", true)), "off VM radar_enabled=false")
	_ok(bool(voff.get("emcon", false)), "off VM emcon=true")
	_eq((voff.get("contacts", []) as Array).size(), 0, "off VM 无主动 contacts")
	_ok(not bool((voff.get("exposure", {}) as Dictionary).get("exposed", true)), "off VM 无暴露")
	# EMCON 下 IFF 被真实阻断
	var blocked: Dictionary = ts.iff_query("apsis")
	_eq(String(blocked.get("status", "")), "blocked", "EMCON 下 IFF blocked")
	_ok(bool(blocked.get("never_hostile", false)), "blocked never_hostile")
	# 开雷达 → 接触/暴露恢复
	var on: Dictionary = ts.set_radar_enabled(true)
	_ok(bool(on.get("ok", false)), "set_radar_enabled(true) ok")
	_ok(bool(on.get("radar_enabled", false)), "返回 radar_enabled=true")
	_ok(not bool(on.get("emcon", true)), "开雷达 EMCON=false")
	vm = ts.step(18.0)
	_ok((vm.get("contacts", []) as Array).size() >= before_contacts, "开雷达后 contact 恢复")
	_ok(bool((vm.get("exposure", {}) as Dictionary).get("exposed", false)), "开雷达后 exposed=true")
	# IFF：4 舰 + 4 港（observer 之外）
	var iff_ids := ["apsis", "ferry", "watchtower", "deepwell",
		"l4_02_hammer", "l1_meridian_05", "l1_anchorage_02", "l1_drydock_01"]
	var statuses: Dictionary = {}
	var contacts_before_iff := (ts.vm().get("contacts", []) as Array).size()
	for tid in iff_ids:
		var r: Dictionary = ts.iff_query(tid)
		_ok(bool(r.get("ok", false)), "IFF %s 查询 ok" % tid, String(r.get("status", "")))
		statuses[tid] = String(r.get("status", ""))
		_ok(String(r.get("schema", "")) == "transit_iff.v1", "IFF %s schema" % tid)
		_ok(bool(r.get("never_hostile", false)), "IFF %s never_hostile" % tid)
		_ok(not bool(r.get("hostile", true)), "IFF %s 无 hostile" % tid)
		_ok(not bool(r.get("produces_contact", true)), "IFF %s 不产生 contact" % tid)
		_ok(int(r.get("level_support", 0)) == 0, "IFF %s 不产生位置等级" % tid)
		_ok(not bool(r.get("writes_v15", true)), "IFF %s 不写 V15" % tid)
	_ok(String(statuses.get("apsis", "")) == "friend", "apsis IFF friend")
	_ok(String(statuses.get("ferry", "")) == "friend", "ferry IFF friend")
	_ok(String(statuses.get("watchtower", "")) == "faulty", "watchtower IFF faulty")
	_ok(String(statuses.get("deepwell", "")) == "no_reply", "deepwell IFF no_reply")
	_ok(String(statuses.get("l4_02_hammer", "")) == "friend", "L4 港 IFF friend")
	_ok(String(statuses.get("l1_meridian_05", "")) == "out_of_range", "起飞段 L1 港 IFF out_of_range")
	_ok(String(statuses.get("l1_anchorage_02", "")) == "out_of_range", "起飞段 Anchorage IFF out_of_range")
	_ok(String(statuses.get("l1_drydock_01", "")) == "out_of_range", "起飞段 Drydock IFF out_of_range")
	var vmi: Dictionary = ts.vm()
	_eq((vmi.get("contacts", []) as Array).size(), contacts_before_iff, "IFF 不增删 contacts")
	_ok(not (vmi.get("iff", {}) as Dictionary).is_empty(), "VM iff 字段存在")
	var ivm: Dictionary = vmi.get("iff", {}) as Dictionary
	_ok(String(ivm.get("schema", "")) == "transit_iff.v1", "VM iff schema")
	_ok(int((ivm.get("summary", {}) as Dictionary).get("hostile", -1)) == 0, "VM iff hostile=0")
	_ok(bool(ivm.get("never_hostile", false)), "VM iff never_hostile")
	_ok(not bool(ivm.get("produces_contact", true)), "VM iff produces_contact=false")
	_ok(int((ivm.get("summary", {}) as Dictionary).get("friend", 0)) >= 2, "VM iff friend count")
	_ok(int((ivm.get("summary", {}) as Dictionary).get("total", 0)) >= 8, "VM iff total≥8")
	_ok((ivm.get("by_target", {}) as Dictionary).has("apsis"), "VM iff by_target apsis")
	_ok(_json_ok(ivm), "VM iff JSON")
	# 未知/自身目标失败
	_eq(String(ts.iff_query("does_not_exist").get("status", "")), "unknown_target", "IFF 未知目标")
	_eq(String(ts.iff_query(ts.selected_ship).get("status", "")), "unknown_target", "IFF 自身目标拒绝")
	# 二次查询：真实模型可给 cooldown，但必须 never_hostile
	var repeat: Dictionary = ts.iff_query("apsis")
	_ok(bool(repeat.get("never_hostile", false)), "重复 IFF never_hostile")
	_ok(String(repeat.get("status", "")) in ["friend", "cooldown", "blocked"], "重复 IFF status 合法",
		String(repeat.get("status", "")))
	_ok(_json_ok(vmi), "controls VM JSON")
	_ok(((vmi.get("writes", {}) as Dictionary).get("track_table", true)) == false, "controls 不写 TrackTable")
	_ok(((vmi.get("writes", {}) as Dictionary).get("v15", true)) == false, "controls 不写 V15")


func _test_json_determinism_writes() -> void:
	print("")
	print("── 6. JSON / 确定性 / 只读 ──")
	var a = _new()
	var b = _new()
	for i in range(2):
		a.step(6.0)
		b.step(6.0)
	a.set_target("harmattan")
	b.set_target("harmattan")
	a.start_optical("optical", "harmattan")
	b.start_optical("optical", "harmattan")
	for i in range(2):
		a.step(6.0)
		b.step(6.0)
	var va: Dictionary = a.vm()
	var vb: Dictionary = b.vm()
	_ok(_json_ok(va), "A VM JSON")
	_ok(_json_ok(vb), "B VM JSON")
	_ok(JSON.stringify(va) == JSON.stringify(vb), "确定性：同输入两实例 VM 逐字节一致")
	for key in ["contacts", "channels", "optical", "levels", "events", "warnings", "writes", "targets", "ships", "ports"]:
		_ok(va.has(key), "VM key " + key)
	_ok(((va.get("writes", {}) as Dictionary).get("track_table", true)) == false, "A 不写 TrackTable")
	_ok(((va.get("writes", {}) as Dictionary).get("v15", true)) == false, "A 不写 V15")
	_ok(String(va.get("schema", "")) == "transit_sensor_data.v1", "A schema")
	_ok((va.get("contacts", []) as Array) is Array, "A contacts[]")
	_ok((va.get("channels", []) as Array) is Array, "A channels[]")
	_ok((va.get("levels", {}) as Dictionary).has("by_target"), "A levels.by_target")
	_ok((va.get("events", []) as Array) is Array, "A events[]")
	_ok((va.get("warnings", []) as Array) is Array, "A warnings[]")
	var sum: Dictionary = a.summary()
	_ok(_json_ok(sum), "summary JSON")
	_ok(((sum.get("writes_track_table", true)) == false), "summary writes_track_table=false")
	_ok(((sum.get("writes_v15", true)) == false), "summary writes_v15=false")
	_ok(String(sum.get("observer_ship", "")) == "harmattan", "summary observer")
	_ok(bool(sum.get("ready", false)), "summary ready")
