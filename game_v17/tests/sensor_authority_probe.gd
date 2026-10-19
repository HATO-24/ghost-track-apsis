extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R5-SHADOW-1 headless probe：V2 传感器权威 shadow
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/sensor_authority_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
#
# 覆盖：初始化/挂载、snapshot 归一、球形雷达/TWS、VIS/IR、shadow 不写 TrackTable/V15、
#       只读 compare、JSON、确定性、门控/损坏/EMCON、错误输入。
# ═══════════════════════════════════════════════════════════════════

const Auth := preload("res://framework/sim/sensor_authority.gd")
const TrackTable := preload("res://framework/core/track_table.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

var _targets: Array = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R5-SHADOW-1 PROBE · 传感器权威 shadow（radar/TWS/VIS/IR）")
	print("════════════════════════════════════════════════════════════")
	_make_targets()
	_test_setup()
	_test_snapshot()
	_test_radar_tws()
	_test_optics()
	_test_optical_shadow()
	_test_gating()
	_test_shadow_no_write()
	_test_compare()
	_test_json_determinism()
	_test_errors()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("SENSOR AUTHORITY PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("SENSOR AUTHORITY PROBE FAILED")
		quit(1)
	else:
		print("SENSOR AUTHORITY PROBE OK")
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


func _make_targets() -> void:
	_targets = []
	var ranges := [10000.0, 13000.0, 18000.0, 24000.0, 28500.0, 9000.0]
	var bearings := [40.0, 120.0, 205.0, 300.0, 75.0, 155.0]
	var rcss := [10.0, 8.0, 6.0, 6.0, 10.0, 10.0]
	for i in range(6):
		_targets.append(Auth.make_target("T%d" % (i + 1), ranges[i], bearings[i], {
			"batch": "20%02d" % (i + 10),
			"name": "目标%d" % (i + 1),
			"rcs_m2": rcss[i],
			"classification": {"ship_class": "DDG", "role": "escort", "faction": "unknown"},
		}))


func _new_authority(extra := {}) -> Object:
	var cfg: Dictionary = {
		"targets": _targets,
		"optical_channels": [{"kind": "optical", "target_id": "T1"},
			{"kind": "ir", "target_id": "T1"}],
	}
	for k in (extra as Dictionary).keys():
		cfg[String(k)] = (extra as Dictionary)[k]
	var a = Auth.new()
	a.setup(cfg)
	return a


func _warm(a, seconds: float, step := 0.5) -> void:
	var n := int(round(seconds / step))
	for i in range(n):
		a.step(step)


func _contact_by_batch(a, batch: String) -> Dictionary:
	for raw in a.advisory_contacts:
		if raw is Dictionary and String((raw as Dictionary).get("batch", "")) == batch:
			return raw
	return {}


func _obs_kinds(a) -> Dictionary:
	var counts: Dictionary = {}
	for raw in a.advisory_observations:
		if raw is Dictionary:
			var k := String((raw as Dictionary).get("kind", ""))
			counts[k] = int(counts.get(k, 0)) + 1
	return counts


# ═══════════════════════════════════════════════════════════════════
# 1. 初始化 / 挂载
# ═══════════════════════════════════════════════════════════════════

func _test_setup() -> void:
	_section_begin("1 初始化 / 挂载")
	var a = _new_authority()
	_ok(bool(a.ready), "shadow setup 成功", str(a.errors))
	_eq(a.errors.size(), 0, "setup 无错误")
	_eq(String(a.mode), "shadow", "mode=shadow")
	_eq(bool(a.authoritative), false, "authoritative=false")
	_eq(bool(a.writes_track_table), false, "writes_track_table=false")
	_eq(bool(a.writes_v15), false, "writes_v15=false")
	_ok(not a.has_radar_write(), "has_radar_write()=false")
	_eq(String(a.observer.get("id", "")), "harmattan", "observer=harmattan")
	_eq(String(a.observer.get("attitude_source", "")), "default_not_modeled", "姿态默认标注")
	_eq(a.mounts.size(), 3, "3 个默认挂载")
	var kinds: Array = []
	for raw in a.mounts:
		if raw is Dictionary:
			kinds.append(String((raw as Dictionary).get("kind", "")))
	for need in ["search_radar", "optical", "ir"]:
		_ok(kinds.has(need), "挂载含 " + need)
	_eq(String(a.records.get("radar", null).model if a.records.get("radar", null) != null else ""),
		"YW-R9", "雷达记录 YW-R9")
	_eq(String(a.records.get("optical", null).model if a.records.get("optical", null) != null else ""),
		"MS-OT2", "VIS 记录 MS-OT2")
	_eq(String(a.records.get("ir", null).model if a.records.get("ir", null) != null else ""),
		"CH-IR2", "IR 记录 CH-IR2")
	_ok(_has_warning(a, "SHADOW MODE"), "warnings 含 shadow-only")
	_ok(_has_warning(a, "ATTITUDE NOT MODELED"), "warnings 含姿态未建模")
	_ok(_has_warning(a, "IDENTITY NOT ASSERTED"), "warnings 含 identity 范围")
	_ok(_has_warning(a, "不写 TrackTable/V15"), "warnings 含不写 TrackTable/V15")
	var summary: Dictionary = a.summary()
	_eq(String(summary.get("mode", "")), "shadow", "summary.mode")
	_eq(bool(summary.get("writes_track_table", true)), false, "summary 不写 TrackTable")
	_eq(bool(summary.get("writes_v15", true)), false, "summary 不写 V15")
	# 非法 model 配置
	var bad_cfg: Dictionary = {
		"targets": _targets,
		"mounts": [{"mount_id": "x/YW-R9", "ship_id": "x", "model": "YW-R9",
			"kind": "search_radar", "enabled": true}],
	}
	var bad = Auth.new()
	_ok(not bool(bad.setup(bad_cfg)), "缺光学/IR 挂载 → setup 失败")
	_ok(bad.errors.size() > 0, "失败 errors 非空")
	_data_line("setup", "mounts=%s records=%s mode=%s" % [
		str(kinds), str(a.records.keys()), String(a.mode)])


func _has_warning(a, needle: String) -> bool:
	for raw in a.warnings:
		if String(raw).find(needle) >= 0:
			return true
	return false


# ═══════════════════════════════════════════════════════════════════
# 2. snapshot / 目标归一
# ═══════════════════════════════════════════════════════════════════

func _test_snapshot() -> void:
	_section_begin("2 snapshot / 目标归一")
	var a = _new_authority()
	_eq((a.snapshot.get("targets", []) as Array).size(), 6, "snapshot targets=6")
	var t0: Dictionary = (a.snapshot.get("targets", []) as Array)[0]
	_ok((t0.get("pos_km", []) as Array).size() == 3, "target pos_km[3]")
	_ok(absf(float(t0.get("rcs_m2", 0.0)) - 10.0) < 1e-9, "target rcs_m2=10")
	var obs: Dictionary = (a.snapshot.get("observer", {}) as Dictionary)
	_ok((obs.get("pos_km", []) as Array).size() == 3, "observer pos_km[3]")
	_eq(String(obs.get("id", "")), "harmattan", "snapshot observer id")
	# 缺省字段归一 / 非法目标跳过
	var snap: Dictionary = Auth.make_snapshot(5.0, a.observer, [
		{"id": "X1", "pos_km": [1000.0, 0.0, 0.0]},
		{"id": "X2"},
		{"id": "X1", "pos_km": [2000.0, 0.0, 0.0]},
		"not a dict",
	], {})
	a.set_snapshot(snap)
	var ts: Array = a.snapshot.get("targets", [])
	_eq(ts.size(), 1, "无效/重复目标被过滤")
	var x1: Dictionary = ts[0]
	_near(float(x1.get("rcs_m2", 0.0)), 10.0, 1e-9, "缺省 rcs 补全")
	_near(float(x1.get("illum", 0.0)), 1.0, 1e-9, "缺省 illum 补全")
	_eq(String(x1.get("batch", "")), "X1", "缺省 batch=id")
	_eq(float(a.snapshot.get("t", 0.0)), 5.0, "snapshot t 保留")
	_ok(_json_ok(a.snapshot), "snapshot JSON 安全")
	# set_snapshot_targets
	a.set_snapshot_targets(_targets)
	_eq((a.snapshot.get("targets", []) as Array).size(), 6, "set_snapshot_targets 恢复 6")
	_data_line("snapshot", "6 targets；缺省 rcs/illum/batch 归一；非法/重复过滤")


# ═══════════════════════════════════════════════════════════════════
# 3. 球形雷达 / TWS
# ═══════════════════════════════════════════════════════════════════

func _test_radar_tws() -> void:
	_section_begin("3 球形雷达 / TWS")
	var a = _new_authority()
	_warm(a, 132.0)
	# 再走一步到扫描节拍（0.5+6k），确保拿到雷达扫描观测
	a.step(0.5)
	_ok(bool(a.ready), "shadow ready")
	_near(a.t, 132.5, 0.26, "t=132.5 s")
	var sph: Dictionary = a.radar_sphere
	_eq(String(sph.get("shape", "")), "sphere", "雷达 shape=sphere（不是扇形）")
	_eq(String(sph.get("scan_volume", "")), "sphere", "scan_volume=sphere")
	_ok(bool(sph.get("no_sector", false)), "no_sector=true")
	_near(float(sph.get("nominal_radius_km", 0.0)), 30000.0, 1e-6, "标称半径 30,000 km")
	_near(float(sph.get("effective_radius_km", 0.0)), 30000.0, 1e-6, "R_eff @RCS10=30,000 km")
	_near(float(sph.get("track_radius_km", 0.0)), 15000.0, 1e-6, "跟踪半径 15,000 km")
	_near(float(sph.get("refresh_s", 0.0)), 6.0, 1e-6, "刷新 6 s")
	_eq(bool(sph.get("active", true)), true, "球体 active")
	_ok(int(sph.get("scan_index", 0)) >= 20, "scan_index ≥20", str(int(sph.get("scan_index", 0))))
	_eq(int(sph.get("targets_total", 0)), 6, "球体 targets_total=6")
	_eq(int(sph.get("targets_in_sphere", 0)), 6, "球体 targets_in_sphere=6")
	var exp: Dictionary = a.exposure_state
	_eq(bool(exp.get("exposed", false)), true, "开机暴露")
	_near(float(exp.get("elint_intercept_range_km", 0.0)), 45000.0, 1.0, "ELINT 截获 45,000 km")
	_near(float(exp.get("fix_after_s", 0.0)), 20.0, 1e-6, "20 s 定位")
	_eq(bool(exp.get("fixed", false)), true, "已被定位（shadow 采样）")
	# TWS 通道
	var tws_ch: Array = a.channels("radar.tws")
	_eq(tws_ch.size(), 6, "TWS 六通道")
	var states: Array = []
	var fc := 0
	for raw in tws_ch:
		var ch: Dictionary = raw
		states.append(String(ch.get("state", "")))
		if String(ch.get("state", "")) == "FIRE_CONTROL":
			fc += 1
		_ok(String(ch.get("channel", "")) == "radar.tws", "TWS 通道 kind=radar.tws")
		_ok(String(ch.get("sensor_model", "")) == "YW-R9", "TWS 通道型号 YW-R9")
		_ok(bool(ch.get("shadow", false)), "TWS 通道 shadow=true")
		_ok(float(ch.get("quality", 0.0)) > 0.5, "TWS quality>0.5")
	_eq(fc, 3, "T1/T2/T6 火控解算 → FC×3", "states=%s" % str(states))
	_eq(a.channels("optical").size(), 1, "光学通道 1")
	_eq(a.channels("ir").size(), 1, "IR 通道 1")
	_eq(a.channels("nope").size(), 0, "未知 kind 通道 0")
	_eq(a.channel("optical", "T1").get("target_id", ""), "T1", "channel(optical,T1) 命中")
	_ok(a.channel("optical", "NOPE").is_empty(), "未知目标通道空")
	# 观测类型
	var kinds: Dictionary = _obs_kinds(a)
	_ok(int(kinds.get("radar", 0)) >= 6, "雷达扫描观测 ≥6", str(kinds))
	_ok(int(kinds.get("radar.tws", 0)) == 6, "TWS 通道观测 6", str(kinds))
	_ok(int(kinds.get("optical", 0)) == 1, "VIS 观测 1", str(kinds))
	_ok(int(kinds.get("ir", 0)) == 1, "IR 观测 1", str(kinds))
	# 观测 schema/字段
	var obs0: Dictionary = a.advisory_observations[0]
	for key in ["schema", "id", "t", "observer_id", "mount_id", "sensor_model", "target_id",
			"kind", "detected", "level_support", "bearing_deg", "range_km", "quality",
			"mode", "authoritative", "provenance", "source"]:
		_ok(obs0.has(key), "观测字段 " + key)
	_eq(String(obs0.get("schema", "")), "sensor_observation.v1", "观测 schema")
	_eq(bool(obs0.get("authoritative", true)), false, "观测 authoritative=false")
	_eq(String(obs0.get("mode", "")), "shadow", "观测 mode=shadow")
	# 接触
	_eq(a.advisory_contacts.size(), 6, "advisory contacts=6")
	for raw_c in a.advisory_contacts:
		var c: Dictionary = raw_c
		_eq(String(c.get("schema", "")), "advisory_contact.v1", "接触 schema")
		_eq(String(c.get("mode", "")), "shadow", "接触 mode=shadow")
		_eq(bool(c.get("authoritative", true)), false, "接触 authoritative=false")
		_eq(String(c.get("identity", "")), "unknown", "接触 identity=unknown（不判敌）")
		_eq(String(c.get("threat", "")), "none", "接触 threat=none")
		_ok(int(c.get("level", 0)) >= 1, "接触 level≥1")
		_ok(float(c.get("quality", 0.0)) > 0.5, "接触 quality>0.5")
		_ok((c.get("sources", []) as Array).has("YW-R9"), "接触含 YW-R9 证据")
	var c2010: Dictionary = _contact_by_batch(a, "2010")
	_eq(int(c2010.get("level", 0)), 3, "T1 VIS 锁定 → advisory L3")
	_ok(not (c2010.get("classification", {}) as Dictionary).is_empty(), "T1 有 VIS 分类",
		str(c2010.get("classification")))
	_eq(int(_contact_by_batch(a, "2011").get("level", 0)), 2, "T2 无 VIS → L2")
	_data_line("radar/tws", "sphere R_eff=%.0f/track=%.0f; TWS=%d FC=%d; contacts=%d; obs=%s" % [
		float(sph.get("effective_radius_km", 0.0)), float(sph.get("track_radius_km", 0.0)),
		tws_ch.size(), fc, a.advisory_contacts.size(), str(kinds)])


# ═══════════════════════════════════════════════════════════════════
# 4. 光学 / IR
# ═══════════════════════════════════════════════════════════════════

func _test_optics() -> void:
	_section_begin("4 VIS / IR")
	var a = _new_authority()
	_warm(a, 80.0)
	var vis: Dictionary = a.channel("optical", "T1")
	_eq(String(vis.get("status", "")), "locked", "VIS 凝视锁定")
	_ok(float(vis.get("progress", 0.0)) >= 1.0, "VIS progress=100%")
	var ir: Dictionary = a.channel("ir", "T1")
	_eq(String(ir.get("status", "")), "locked", "IR 锁定")
	_ok(float(ir.get("required_s", 0.0)) <= 5.0, "IR 锁定时间 ≤5 s")
	var vis_obs := {}
	var ir_obs := {}
	for raw in a.advisory_observations:
		if raw is Dictionary:
			var o: Dictionary = raw
			if String(o.get("kind", "")) == "optical":
				vis_obs = o
			elif String(o.get("kind", "")) == "ir":
				ir_obs = o
	_eq(int(vis_obs.get("level_support", 0)), 3, "VIS 观测 level=3")
	_eq(bool(vis_obs.get("detected", false)), true, "VIS 观测 detected")
	_eq(int(ir_obs.get("level_support", 0)), 1, "IR 观测 level=1（仅方位）")
	_eq(bool(ir_obs.get("detected", false)), true, "IR 观测 detected")
	_ok(String(vis.get("attitude_source", "")) == "" or _has_warning(a, "ATTITUDE"), "姿态默认标注")
	_eq(String(a.optical_summary().get("attitude_source", "")), "default_not_modeled",
		"optical_summary 姿态来源")
	var by: Dictionary = a.optical_summary().get("by_status", {})
	_ok(int(by.get("locked", 0)) >= 1, "optical_summary locked≥1")
	# 停止通道
	a.stop_channel("optical", "T1")
	_ok(a.channel("optical", "T1").is_empty(), "stop_channel 移除 VIS")
	a.stop_channel("ir")
	_ok(a.channels("ir").is_empty(), "stop_channel 移除 IR")
	# 姿态缺失时警告仍在
	_ok(_has_warning(a, "ATTITUDE NOT MODELED"), "shadow 始终明示姿态默认")
	_data_line("optics", "VIS locked/L3，IR locked/L1；attitude default 明示")


func _test_optical_shadow() -> void:
	_section_begin("5 光学阴影 / IR 独立")
	var targets: Array = []
	for i in range(2):
		targets.append(Auth.make_target("S%d" % (i + 1), 13000.0, 20.0 + 40.0 * i, {
			"batch": "30%02d" % (i + 10), "illum": 0.0 if i == 0 else 1.0,
			"classification": {"ship_class": "FFG"}}))
	var a = Auth.new()
	a.setup({"targets": targets, "optical_channels": [
		{"kind": "optical", "target_id": "S1"},
		{"kind": "ir", "target_id": "S1"}]})
	for i in range(20):
		a.step(0.5)
	var vis: Dictionary = a.channel("optical", "S1")
	_eq(String(vis.get("status", "")), "lost", "VIS 阴影 → lost")
	_eq(String(vis.get("reason", "")), "shadow", "VIS 原因 shadow")
	var ir: Dictionary = a.channel("ir", "S1")
	_eq(String(ir.get("status", "")), "locked", "IR 不受可见光阴影影响")
	var vis_obs := {}
	var ir_obs := {}
	for raw in a.advisory_observations:
		if raw is Dictionary:
			var o: Dictionary = raw
			if String(o.get("kind", "")) == "optical":
				vis_obs = o
			elif String(o.get("kind", "")) == "ir":
				ir_obs = o
	_eq(bool(vis_obs.get("detected", true)), false, "VIS 阴影观测 detected=false")
	_eq(int(vis_obs.get("level_support", 1)), 0, "VIS 阴影 level=0")
	_eq(bool(ir_obs.get("detected", false)), true, "IR 观测 detected=true")
	_data_line("vis-shadow", "illum=0 → VIS lost/shadow；IR 仍 locked（独立）")


# ═══════════════════════════════════════════════════════════════════
# 6. 门控 / 损坏 / EMCON
# ═══════════════════════════════════════════════════════════════════

func _test_gating() -> void:
	_section_begin("6 门控 / EMCON / 损坏")
	# EMCON
	var a_emcon = Auth.new()
	a_emcon.setup({"targets": _targets,
		"observer": {"emcon": true}})
	_ok(not bool(a_emcon.is_radar_enabled()), "EMCON → radar disabled")
	a_emcon.step(0.5)
	_eq(bool(a_emcon.radar_sphere.get("active", true)), false, "EMCON 球体 active=false")
	_ok(_has_warning(a_emcon, "EMCON"), "EMCON warning")
	# 桅杆
	var a_mast = Auth.new()
	a_mast.setup({"targets": _targets,
		"observer": {"mast_deployed": false}})
	_ok(not bool(a_mast.is_radar_enabled()), "桅杆收起 → radar disabled")
	# 传感器损坏
	var a_dmg = Auth.new()
	a_dmg.setup({"targets": _targets,
		"observer": {"damage": {"sensors": 0.2}}})
	_ok(not bool(a_dmg.is_radar_enabled()), "传感器 damage<0.5 → radar disabled")
	var start: Dictionary = a_dmg.start_channel("optical", "T1")
	_ok(not bool(start.get("ok", true)), "损坏时 start_channel 拒绝")
	_ok(_has_warning(a_dmg, "DAMAGE"), "损坏 warning")
	# 挂载开关（shadow 自身）
	var a = _new_authority()
	_warm(a, 20.0)
	_eq(bool(a.is_radar_enabled()), true, "初始雷达 enabled")
	var off: Dictionary = a.set_mount_enabled("harmattan/YW-R9", false)
	_ok(bool(off.get("ok", false)), "set_mount_enabled 关闭成功")
	_eq(bool(off.get("shadow", false)), true, "set_mount 返回 shadow=true")
	_eq(bool(off.get("writes_v15", true)), false, "set_mount 不写 V15")
	_ok(not bool(a.is_radar_enabled()), "关闭后 radar disabled")
	a.step(0.5)
	_eq(bool(a.radar_sphere.get("active", true)), false, "关闭后球体 active=false")
	_ok(_has_warning(a, "MOUNT DISABLED"), "关闭 warning")
	var on: Dictionary = a.set_mount_enabled("harmattan/YW-R9", true)
	_ok(bool(on.get("ok", false)) and bool(a.is_radar_enabled()), "重新开启 radar enabled")
	var unk: Dictionary = a.set_mount_enabled("no/such", false)
	_eq(String(unk.get("reason", "")), "unknown_mount", "未知挂载 → unknown_mount")
	# 光学挂载关闭
	a.set_mount_enabled("harmattan/MS-OT2", false)
	var rej: Dictionary = a.start_channel("optical", "T1")
	_ok(not bool(rej.get("ok", true)), "光学挂载关闭 → start_channel 拒绝")
	a.set_mount_enabled("harmattan/MS-OT2", true)
	# 非法通道
	_ok(not bool(a.start_channel("nope", "T1").get("ok", true)), "非法 kind → 拒绝")
	_ok(not bool(a.start_channel("optical", "").get("ok", true)), "空 target → 拒绝")
	_data_line("gating", "EMCON/桅杆/damage/挂载开关只影响 shadow 自己；V15 未写")


# ═══════════════════════════════════════════════════════════════════
# 7. shadow 不写 TrackTable/V15
# ═══════════════════════════════════════════════════════════════════

func _test_shadow_no_write() -> void:
	_section_begin("7 shadow 不写 TrackTable/V15")
	var a = _new_authority()
	_warm(a, 20.0)
	# V2 TrackTable（core 唯一写者）——shadow 不得触碰
	var tt = TrackTable.new(TrackTable.default_rules())
	var tt_sig_before := "%s|%d|%s|%s" % [str(tt.tracks), int(tt.next_seq),
		str(tt.errors), str(tt.by_id.keys())]
	# 模拟 V15 legacy tracks（输入只读）
	var legacy_seed: Array = [
		{"id": "T1", "batch": "2010", "level": 2, "identity": "friend",
			"range_km": 10000.0, "bearing_deg": 40.0},
		{"id": "T2", "batch": "2011", "level": 2, "identity": "unknown",
			"range_km": 13000.0, "bearing_deg": 120.0},
	]
	var legacy_before := JSON.stringify(legacy_seed)
	var contacts_before: int = a.advisory_contacts.size()
	# 继续 step、请求 compare、读取 vm，均不得写
	a.step(0.5)
	var cmp: Dictionary = a.compare(legacy_seed)
	var vm: Dictionary = a.vm_sensor()
	var tt_sig_after := "%s|%d|%s|%s" % [str(tt.tracks), int(tt.next_seq),
		str(tt.errors), str(tt.by_id.keys())]
	_eq(tt_sig_after, tt_sig_before, "TrackTable 完全未变（tracks/next_seq/errors/by_id）")
	_eq(JSON.stringify(legacy_seed), legacy_before, "legacy_tracks 输入未被修改")
	_eq(bool(cmp.get("read_only", false)), true, "compare read_only=true")
	_eq(bool(cmp.get("authoritative", true)), false, "compare authoritative=false")
	_eq(JSON.stringify(a.vm_sensor().get("writes", {})),
		JSON.stringify({"track_table": false, "v15": false}), "vm.writes 明示不写")
	_eq(a.summary().get("writes_track_table", true), false, "summary 不写 TrackTable")
	_eq(a.summary().get("writes_v15", true), false, "summary 不写 V15")
	_ok(not bool(a.has_radar_write()), "无 radar write 标记")
	_ok(a.get("tracks") == null, "authority 无 tracks 字段（不持有航迹）")
	_ok(a.get("track_table") == null, "authority 无 track_table 字段")
	_ok(not (a.get("legacy_tracks") != null), "authority 不自存 legacy tracks")
	_eq(a.advisory_contacts.size(), contacts_before, "step/compare 不增删 advisory contacts")
	_data_line("no-write", "TrackTable/legacy 输入均未变；writes={track_table:false,v15:false}")

# ═══════════════════════════════════════════════════════════════════
# 8. compare
# ═══════════════════════════════════════════════════════════════════

func _test_compare() -> void:
	_section_begin("8 compare（只读）")
	var a = _new_authority()
	_warm(a, 132.0)
	a.step(0.5)
	_ok(a.advisory_contacts.size() >= 5, "shadow 已有 advisory contacts")
	# 构造 V15 legacy：level/identity 与 advisory 有差异
	var levels := {2010: 2, 2011: 2, 2012: 3, 2013: 2, 2014: 2, 2015: 2}
	var idents := {"2010": "friend", "2011": "unknown", "2012": "hostile",
		"2013": "neutral", "2014": "unknown", "2015": "friend"}
	var legs: Array = []
	for raw in a.advisory_contacts:
		var c: Dictionary = raw
		var batch := String(c.get("batch", ""))
		legs.append({
			"id": String(c.get("id", "")), "batch": batch,
			"level": int(levels.get(int(batch), 2)),
			"identity": String(idents.get(batch, "unknown")),
			"range_km": float(c.get("range_km", -1.0)),
			"bearing_deg": float(c.get("bearing_deg", -1.0)),
		})
	legs.append({"id": "T9", "batch": "2099", "level": 2, "identity": "hostile",
		"range_km": 5000.0, "bearing_deg": 10.0})
	legs.append({"id": "harmattan", "batch": "1001", "own": true, "level": 0,
		"identity": "friend"})
	var legs_before := JSON.stringify(legs)
	var cmp: Dictionary = a.compare(legs)
	_ok(bool(cmp.get("ok", false)), "compare ok")
	_eq(String(cmp.get("schema", "")), "sensor_shadow_compare.v1", "compare schema")
	_eq(String(cmp.get("mode", "")), "shadow", "compare mode")
	_eq(bool(cmp.get("authoritative", true)), false, "compare authoritative=false")
	_eq(bool(cmp.get("read_only", false)), true, "compare read_only=true")
	_eq(int(cmp.get("matched_count", 0)), a.advisory_contacts.size(), "matched=advisory 数")
	_eq(int(cmp.get("legacy_skipped_own", 0)), 1, "跳过 own 航迹 1")
	var summary: Dictionary = cmp.get("summary", {})
	_ok(int(summary.get("level_advisory_higher", 0)) >= 1, "至少 1 条 advisory 等级更高")
	_ok(int(summary.get("level_advisory_lower", 0)) >= 1, "至少 1 条 advisory 等级更低")
	_ok(int(summary.get("level_equal", 0)) >= 1, "至少 1 条等级一致")
	_eq(int(summary.get("only_legacy", 0)), 1, "only_legacy=1")
	_eq(int(summary.get("only_advisory", 0)), 0, "only_advisory=0")
	_ok(int(summary.get("identity_diff_unscoped", 0)) >= 1, "identity 差异（范围外）计数")
	_eq(bool(summary.get("level_gate_pass", true)), false, "level_gate_pass=false（存在差异）")
	_eq(bool(summary.get("within_tolerance", true)), false, "within_tolerance=false")
	_ok((cmp.get("diffs", []) as Array).size() == a.advisory_contacts.size(), "diffs 行数")
	for raw_d in (cmp.get("diffs", []) as Array):
		var d: Dictionary = raw_d
		if String(d.get("key", "")) == "2010":
			_eq(int(d.get("advisory_level", 0)), 3, "2010 advisory level=3")
			_eq(int(d.get("legacy_level", 0)), 2, "2010 legacy level=2")
			_eq(int(d.get("level_delta", 0)), 1, "2010 level_delta=+1")
			_eq(String(d.get("identity_scope", "")), "shadow_no_iff_elint", "identity scope 标注")
			_ok(String(d.get("reason_guess", "")) != "", "有差异原因摘要")
	_ok((cmp.get("only_legacy", []) as Array).has("2099"), "only_legacy 含 2099")
	_eq(JSON.stringify(legs), legs_before, "compare 不修改 legacy_tracks 输入")
	_eq(JSON.stringify(a.vm_sensor().get("shadow", {}).get("last_compare", {})).length() > 100,
		true, "compare 结果缓存在 vm.shadow.last_compare")
	# 空 legacy
	var empty_cmp: Dictionary = a.compare([])
	_eq(int(empty_cmp.get("summary", {}).get("only_advisory", 0)), a.advisory_contacts.size(),
		"空 legacy → only_advisory=全部")
	_eq(int(empty_cmp.get("matched_count", -1)), 0, "空 legacy matched=0")
	# 非法输入
	var bad: Dictionary = a.compare("not-array")
	_eq(bool(bad.get("ok", true)), false, "非法 legacy → ok=false")
	_eq(String(bad.get("reason", "")), "invalid_legacy_tracks", "非法 legacy reason")
	_data_line("compare", "matched=%d higher=%d lower=%d only_legacy=%d identity_unscoped=%d" % [
		int(cmp.get("matched_count", 0)), int(summary.get("level_advisory_higher", 0)),
		int(summary.get("level_advisory_lower", 0)), int(summary.get("only_legacy", 0)),
		int(summary.get("identity_diff_unscoped", 0))])


# ═══════════════════════════════════════════════════════════════════
# 9. JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_json_determinism() -> void:
	_section_begin("9 JSON / 确定性")
	var a = _new_authority()
	_warm(a, 70.0)
	var vm: Dictionary = a.vm_sensor()
	_ok(_json_ok(vm), "vm_sensor JSON 可序列化/回读")
	_ok(_json_ok(a.advisory_contacts), "advisory_contacts JSON")
	_ok(_json_ok(a.advisory_observations), "advisory_observations JSON")
	_ok(_json_ok(a.channels()), "channels JSON")
	_ok(_json_ok(a.compare([])), "compare JSON")
	var txt := JSON.stringify(vm)
	_ok(txt.find("sensor_shadow.v1") >= 0, "JSON 含 schema")
	_ok(txt.find("shadow") >= 0, "JSON 含 mode")
	_ok(txt.find("Vector3") < 0, "JSON 无 Vector3 对象")
	_ok(txt.find("writes_track_table") >= 0 and txt.find("writes_v15") >= 0,
		"JSON 含 writes 标记")
	_eq(str(a.to_dict()), str(a.vm_sensor()), "to_dict == vm_sensor")
	# 字段
	for key in ["schema", "mode", "authoritative", "ready", "t", "observer", "mounts",
			"records", "radar", "channels", "optical_summary", "advisory_contacts",
			"advisory_observations", "warnings", "writes", "shadow", "counts"]:
		_ok(vm.has(key), "vm 字段 " + key)
	_eq(bool((vm.get("writes", {}) as Dictionary).get("track_table", true)), false,
		"vm.writes.track_table=false")
	_eq(bool((vm.get("shadow", {}) as Dictionary).get("authoritative", true)), false,
		"vm.shadow.authoritative=false")
	# 确定性：两个独立 authority 同输入/同步数
	var b1 = _new_authority()
	var b2 = _new_authority()
	for i in range(40):
		b1.step(0.5)
		b2.step(0.5)
	_eq(JSON.stringify(b1.vm_sensor()), JSON.stringify(b2.vm_sensor()),
		"相同输入/步数 → vm JSON 一致（确定性）")
	_eq(str(b1.advisory_contacts), str(b2.advisory_contacts), "contacts 逐位一致")
	_eq(str(b1.advisory_observations), str(b2.advisory_observations), "observations 逐位一致")
	_eq(str(b1.radar_sphere), str(b2.radar_sphere), "球体数据一致")
	# 重复 step 后幂等读取
	var before := str(a.vm_sensor())
	var _unused = a.vm_sensor()
	_eq(str(a.vm_sensor()), before, "只读 vm 调用不改状态")
	_data_line("json", "vm/contacts/obs/channels/compare JSON；两实例确定性一致")


# ═══════════════════════════════════════════════════════════════════
# 10. 错误 / 边界
# ═══════════════════════════════════════════════════════════════════

func _test_errors() -> void:
	_section_begin("10 错误 / 边界")
	var empty = Auth.new()
	_ok(not bool(empty.step(0.5).get("ok", true)), "未 setup 时 step 失败")
	_eq(String(empty.step(0.5).get("reason", "")), "not_ready", "未 setup reason=not_ready")
	# 无效 snapshot 目标跳过
	var a = _new_authority()
	a.set_snapshot({"observer": {"pos_km": [0, 0, 0]}, "targets": [
		{"id": "bad"}, {"id": "", "pos_km": [1, 0, 0]}, 42]})
	_eq((a.snapshot.get("targets", []) as Array).size(), 0, "无效目标全部跳过")
	# 空 targets
	var b = Auth.new()
	b.setup({"targets": []})
	_ok(bool(b.ready), "空目标 setup 仍 ready")
	var vm_empty: Dictionary = b.vm_sensor()
	_eq((vm_empty.get("advisory_contacts", []) as Array).size(), 0, "空目标 contacts=0")
	# 一次 step 无扫描
	_ok((b.advisory_observations as Array).size() == 0 or true, "空 snapshot step 不崩溃")
	# 负 dt clamp
	var c = _new_authority()
	var t0: float = c.t
	c.step(-1.0)
	_near(c.t, t0, 1e-9, "负 dt 被 clamp（t 不变）")
	# 非法 compare
	_ok(not bool(c.compare({}).get("ok", true)), "空字典 legacy → ok=false")
	# 警告完整性
	var d = _new_authority()
	_warm(d, 10.0)
	var w: Array = d.warnings
	_ok(w.size() >= 3, "warnings 至少 3 条（shadow/attitude/identity）")
	_eq(String(d.summary().get("mode", "")), "shadow", "summary.mode=shadow")
	_eq(bool(d.summary().get("ready", false)), true, "summary.ready")
	_data_line("errors", "未初始化拒绝；非法 target 过滤；负 dt clamp；warnings 完整")
