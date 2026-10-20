extends SceneTree

## SENSOR EXPLORER · headless probe（SENSOR-EXPLORER-1）
##
## 直接验证 V2 传感器模型（不启动场景）：
##   * 型号记录（YW-R9 / MS-OT2 / CH-IR2 / MK-12 / ELINT）与球形搜索体；
##   * 球形 R_eff / RCS / 干扰 / 暴露（ELINT 截获距离、定位时间）；
##   * TWS 六态状态机（SEARCH→DETECT→ACQUIRE→TRACK→STARE→FIRE_CONTROL）、
##     失锁与重捕、6 通道、quality/age/更新率；
##   * 光学 VIS/IR 凝视（锁定 / 阴影丢失 / 独立状态）；
##   * IFF 询问（friend / faulty / no_reply / wrong_code / out_of_range）与「不明≠敌意」；
##   * ELINT 被动截获（只出信号不出接触、静默收不到、超出截获距离收不到）；
##   * 输出 JSON 可序列化 + 确定性（同输入两次运行一致）。
##
## 运行（工作区根目录）：
##   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
##       --path .\sensor_explorer --script res://tests/sensor_explorer_probe.gd
## 期望末行 SENSOR EXPLORER PROBE PASS，退出码 0；日志 tests/sensor_explorer_probe.log。

const Types := preload("res://sim/sensor_types.gd")
const RadarModel := preload("res://sim/radar.gd")
const TwsModel := preload("res://sim/tws.gd")
const OpticalModel := preload("res://sim/optical.gd")
const OpticalIR := preload("res://ui/sx_optical_ir.gd")
const InfoModel := preload("res://ui/sx_information_warfare.gd")
const SM := preload("res://scripts/sensor_model.gd")

var ok := true
var pass_count := 0
var fail_count := 0


func _initialize() -> void:
	print("==== SENSOR EXPLORER PROBE · GHOST TRACK / APSIS ====")
	print("[SRC] sim/{sensor_types,radar,tws,optical}.gd + scripts/sensor_model.gd")
	_run()
	print("")
	print("[SUMMARY] pass=%d fail=%d" % [pass_count, fail_count])
	if ok:
		print("SENSOR EXPLORER PROBE PASS")
	else:
		print("SENSOR EXPLORER PROBE FAIL")
	quit(0 if ok else 1)


func check(cond: bool, label: String, detail: String = "") -> bool:
	if cond:
		pass_count += 1
		print("[PASS] ", label, ("  " + detail) if detail != "" else "")
	else:
		ok = false
		fail_count += 1
		print("[FAIL] ", label, ("  " + detail) if detail != "" else "")
	return cond


func _json_ok(value: Variant) -> bool:
	var txt := JSON.stringify(value)
	return txt.length() > 2 and not txt.contains("<Object")


func tgt(id: String, range_km: float, bearing_deg: float, rcs: float = 10.0,
		illum: float = 1.0, transponder: String = "off", iff_code: String = "",
		emissions: Array = []) -> Dictionary:
	var b := deg_to_rad(bearing_deg)
	var pos := Vector3(sin(b) * range_km, cos(b) * range_km, 0.0)
	return {
		"id": id, "name": id, "pos_km": pos, "range_km": range_km, "bearing_deg": bearing_deg,
		"elevation_deg": 0.0, "rcs_m2": rcs, "temp_k": 300.0, "area_m2": 1000.0,
		"illum": illum, "transponder": transponder, "iff_code": iff_code,
		"faction": "unknown", "classification": {"ship_class": "DDG", "role": "", "faction": "unknown"},
		"emissions": emissions,
	}
func snap(t: float, targets: Array, jamming: float = 0.0) -> Dictionary:
	return {"t": t, "observer": {"id": "SX-01", "pos_km": Vector3.ZERO, "maneuver_g": 0.0},
		"targets": targets, "sun_illum": 1.0, "jamming": jamming, "los": true, "shadow": false}


func _run() -> void:
	# ── 1. 型号记录 / 球形搜索体 ──────────────────────────────────
	print("")
	print("── 1. V2 型号记录 / 球形搜索 ──")
	var radar_rec = Types.record("YW-R9")
	var vis_rec = Types.record("MS-OT2")
	var ir_rec = Types.record("CH-IR2")
	var iff_rec = Types.record("MK-12")
	var elint_rec = Types.record("ELINT")
	check(radar_rec != null and String(radar_rec.kind) == "search_radar", "YW-R9 = 球形搜索雷达",
		String(radar_rec.kind))
	check(bool(radar_rec.spherical) and String(radar_rec.scan_volume) == "sphere",
		"YW-R9 scan_volume=sphere（不是扇形）")
	check(absf(float(radar_rec.range_km) - 30000.0) < 1.0e-6
		and absf(float(radar_rec.track_range_km()) - 15000.0) < 1.0e-6,
		"YW-R9 探测 30,000 km / 稳定跟踪 15,000 km")
	check(absf(float(radar_rec.refresh_s) - 6.0) < 1.0e-6
		and int(radar_rec.track_capacity) == 6, "YW-R9 6 s 刷新 / TWS 6 通道")
	check(String(vis_rec.v15_type) == "optical" and absf(float(vis_rec.range_km) - 15000.0) < 1.0,
		"MS-OT2 光学凝视 15,000 km")
	check(String(ir_rec.v15_type) == "ir" and absf(float(ir_rec.range_km) - 60000.0) < 1.0,
		"CH-IR2 红外 60,000 km")
	check(String(iff_rec.v15_type) == "iff" and absf(float(iff_rec.range_km) - 2000.0) < 1.0,
		"MK-12 IFF 2,000 km")
	check(String(elint_rec.v15_type) == "elint" and absf(float(elint_rec.range_km) - 60000.0) < 1.0,
		"ELINT 接收 60,000 km")
	check(absf(RadarModel.effective_radius_km(radar_rec, 10.0, 0.0) - 30000.0) < 1.0e-6,
		"R_eff @RCS 10 m² = 30,000 km")
	var r_eff_40 := RadarModel.effective_radius_km(radar_rec, 40.0, 0.0)
	check(absf(r_eff_40 - 30000.0 * pow(4.0, 0.25)) < 1.0e-3,
		"R_eff ∝ RCS^0.25（40 m² → %.0f km）" % r_eff_40)
	var r_eff_jam := RadarModel.effective_radius_km(radar_rec, 10.0, 0.5)
	check(absf(r_eff_jam - 30000.0 * 0.72) < 1.0e-3,
		"干扰 0.5 → R_eff ×0.72（%.0f km）" % r_eff_jam)
	var sph := RadarModel.sphere_for(radar_rec, Vector3.ZERO, 10.0, 0.0)
	check(String(sph.get("shape", "")) == "sphere" and bool(sph.get("no_sector", false))
		and absf(float(sph.get("effective_radius_km", 0.0)) - 30000.0) < 1.0e-6,
		"sphere_for：shape=sphere / no_sector / R_eff=30,000 km")
	check(absf(float(sph.get("track_radius_km", 0.0)) - 15000.0) < 1.0e-6
		and absf(float(sph.get("refresh_s", 0.0)) - 6.0) < 1.0e-6,
		"sphere_for：track=15,000 km / refresh=6 s / capacity=6")

	# ── 2. 暴露 / ELINT 截获 ─────────────────────────────────────
	print("")
	print("── 2. 暴露 / ELINT 截获（开机即暴露）──")
	var exp0 := RadarModel.exposure_state(radar_rec, 0.0, {"on": true})
	var exp10 := RadarModel.exposure_state(radar_rec, 10.0, {"on": true})
	var exp30 := RadarModel.exposure_state(radar_rec, 30.0, {"on": true})
	check(bool(exp0.get("exposed", false)) and absf(float(exp0.get("elint_intercept_range_km", 0.0)) - 45000.0) < 1.0,
		"开机即暴露：ELINT 截获 45,000 km")
	check(absf(float(exp10.get("fix_progress", 0.0)) - 0.5) < 1.0e-6
		and absf(float(exp10.get("bearing_sigma_deg", 0.0)) - 0.6) < 1.0e-6,
		"10 s 定位进度 50% / 测向 σ 0.6°")
	check(bool(exp30.get("fixed", false)) and absf(float(exp30.get("bearing_sigma_deg", 0.0)) - 0.2) < 1.0e-6,
		"30 s 完成定位 / σ 0.2°")
	var exp_off := RadarModel.exposure_state(radar_rec, 30.0, {"on": false})
	check(not bool(exp_off.get("exposed", true)), "EMCON 关闭 → 无暴露")
	var emitter: Dictionary = SM.emission_for(radar_rec.as_v15_sensor())
	check(absf(float(emitter.get("elint_range_km", 0.0)) - 45000.0) < 1.0,
		"emission_for：YW-R9 ELINT 截获 45,000 km")
	var ic_near: Dictionary = SM.elint_intercept(emitter, 10000.0, 5.0, {})
	var ic_far: Dictionary = SM.elint_intercept(emitter, 50000.0, 5.0, {})
	check(bool(ic_near.get("detected", false)) and not bool(ic_far.get("detected", false)),
		"对方 ELINT：10,000 km 截获 / 50,000 km 收不到")
	check(bool(ic_near.get("model_recorded", "") != ""), "截获后记录发射型号", String(ic_near.get("model_recorded", "")))

	# ── 3. TWS 六态状态机 ───────────────────────────────────────
	print("")
	print("── 3. TWS 六态状态机 / 6 通道 ──")
	var tws = TwsModel.new(radar_rec, {"id": "YW-R9", "max_channels": 6, "enabled": true})
	var targets: Array = []
	for i in range(6):
		targets.append(tgt("T%d" % (i + 1), 9000.0 + 2000.0 * float(i), 40.0 + 55.0 * float(i)))
	var t := 0.0
	var final_out: Dictionary = {}
	for k in range(6):
		final_out = tws.step(6.0, snap(t, targets))
		t += 6.0
	check(int(final_out.get("channel_count", 0)) == 6, "6 个 TWS 通道",
		"n=%d" % int(final_out.get("channel_count", 0)))
	var by: Dictionary = final_out.get("by_state", {})
	var sum_states := 0
	for key in by.keys():
		sum_states += int(by[key])
	check(sum_states == 6, "六态计数合计 = 6", str(by))
	var ch_t1: Dictionary = tws.channel("T1")
	var hist: Array = ch_t1.get("history", [])
	var tos: Array = []
	for raw in hist:
		if raw is Dictionary:
			tos.append(String((raw as Dictionary).get("to", "")))
	var sequence_ok := true
	for wanted in ["DETECT", "ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]:
		if not tos.has(wanted):
			sequence_ok = false
	check(sequence_ok, "单通道状态序列覆盖 DETECT→ACQUIRE→TRACK→STARE→FIRE_CONTROL", str(tos))
	check(String(ch_t1.get("state", "")) == "FIRE_CONTROL"
		and float(ch_t1.get("quality", 0.0)) >= 0.85,
		"T1 到达 FIRE_CONTROL / quality ≥0.85", "q=%.2f" % float(ch_t1.get("quality", 0.0)))
	check(absf(float(ch_t1.get("update_rate_hz", 0.0)) - 1.0 / 6.0) < 0.05,
		"更新率 ≈1/6 Hz", "%.3f" % float(ch_t1.get("update_rate_hz", 0.0)))
	check(_json_ok(final_out) and _json_ok(tws.to_dict()), "TWS 输出 JSON 可序列化")

	# ── 4. 失锁 / 重捕 ─────────────────────────────────────────
	print("")
	print("── 4. 失锁 / 重捕（目标移出球体再返回）──")
	var lost_seen := false
	var dropped_or_lost := false
	for k in range(4):
		var far: Array = []
		for i in range(6):
			var rr := 40000.0 if i == 0 else 9000.0 + 2000.0 * float(i)
			far.append(tgt("T%d" % (i + 1), rr, 40.0 + 55.0 * float(i)))
		var out_far: Dictionary = tws.step(6.0, snap(t, far))
		t += 6.0
		for raw in (out_far.get("events", []) as Array):
			if raw is Dictionary:
				var kk := String((raw as Dictionary).get("kind", ""))
				if kk == "lock_lost":
					lost_seen = true
					dropped_or_lost = true
				if kk == "target_dropped":
					dropped_or_lost = true
	check(lost_seen or dropped_or_lost, "失锁事件可观察（lock_lost / target_dropped）")
	var ch_after_far: Dictionary = tws.channel("T1")
	check(ch_after_far.is_empty() or String(ch_after_far.get("state", "")) != "FIRE_CONTROL",
		"失锁后通道不再为 FIRE_CONTROL", String(ch_after_far.get("state", "dropped")))
	var back: Array = []
	for i in range(6):
		back.append(tgt("T%d" % (i + 1), 9000.0 + 2000.0 * float(i), 40.0 + 55.0 * float(i)))
	var reacquired := false
	for k in range(5):
		var out_back: Dictionary = tws.step(6.0, snap(t, back))
		t += 6.0
		var ch_re: Dictionary = tws.channel("T1")
		if not ch_re.is_empty() and int(ch_re.get("lost_lock_count", 0)) >= 1:
			reacquired = true
			break
	check(reacquired, "目标返回后重新捕获（lost_lock_count ≥1）")

	# ── 5. 光学 VIS / IR ────────────────────────────────────────
	print("")
	print("── 5. 光学 VIS / IR（凝视/锁定/阴影）──")
	var opt = OpticalModel.new({})
	opt.set_sensor("optical", vis_rec)
	opt.set_sensor("ir", ir_rec)
	var opt_targets: Array = [tgt("T1", 10000.0, 40.0), tgt("T3", 24000.0, 205.0, 6.0)]
	var st_vis: Dictionary = opt.start("optical", "T1")
	var st_ir: Dictionary = opt.start("ir", "T1")
	check(bool(st_vis.get("ok", false)) and bool(st_ir.get("ok", false)),
		"VIS/IR 通道建立", String(st_vis.get("reason", "")))
	var vis_locked := false
	var ir_locked := false
	var ot := 0.0
	for k in range(100):
		var oo: Dictionary = opt.step(1.0, snap(ot, opt_targets))
		ot += 1.0
		var cv: Dictionary = opt.channel("optical", "T1")
		var ci: Dictionary = opt.channel("ir", "T1")
		if String(cv.get("status", "")) == "locked":
			vis_locked = true
		if String(ci.get("status", "")) == "locked":
			ir_locked = true
	check(vis_locked, "VIS 凝视锁定（约 62.5 s @10,000 km）")
	check(ir_locked, "IR 快速锁定（4 s，独立于 VIS）")
	var cv_final: Dictionary = opt.channel("optical", "T1")
	check(float(cv_final.get("progress", 0.0)) >= 1.0
		and int(cv_final.get("level_support", 0)) == 3,
		"VIS 锁定 → 进度 100% / 支撑 L3")
	# 阴影：T3 illum=0.02 → VIS 丢失；IR 仍可工作
	var opt2 = OpticalModel.new({})
	opt2.set_sensor("optical", vis_rec)
	opt2.set_sensor("ir", ir_rec)
	opt2.start("optical", "T3")
	opt2.start("ir", "T3")
	var shadow_targets := [tgt("T3", 24000.0, 205.0, 6.0, 0.02)]
	for k in range(12):
		opt2.step(1.0, snap(float(k), shadow_targets))
	var cv2: Dictionary = opt2.channel("optical", "T3")
	var ci2: Dictionary = opt2.channel("ir", "T3")
	check(String(cv2.get("status", "")) == "lost" and String(cv2.get("reason", "")) == "shadow",
		"VIS 阴影 → lost / reason=shadow", String(cv2.get("reason", "")))
	check(String(ci2.get("status", "")) in ["locked", "staring", "acquiring"],
		"IR 不受可见光阴影影响", String(ci2.get("status", "")))
	check(_json_ok(opt.to_dict()) and _json_ok(opt2.to_dict()), "光学输出 JSON 可序列化")

	# ── 6. IFF ─────────────────────────────────────────────────
	print("")
	print("── 6. IFF 询问 / 应答 / 无应答 ──")
	var iff_sensor: Dictionary = iff_rec.as_v15_sensor()
	var friend: Dictionary = tgt("F1", 1500.0, 30.0, 10.0, 1.0, "ok", "CMP-119")
	var faulty: Dictionary = tgt("F2", 1500.0, 60.0, 10.0, 1.0, "faulty", "OCU-207")
	var no_reply: Dictionary = tgt("F3", 1500.0, 90.0, 10.0, 1.0, "off", "")
	var wrong: Dictionary = tgt("F4", 1500.0, 120.0, 10.0, 1.0, "ok", "REB-7")
	var far_iff: Dictionary = tgt("F5", 5000.0, 150.0, 10.0, 1.0, "ok", "CMP-119")
	var r_friend: Dictionary = SM.interrogate_iff(iff_sensor, friend, {"los": true})
	var r_faulty: Dictionary = SM.interrogate_iff(iff_sensor, faulty, {"los": true})
	var r_none: Dictionary = SM.interrogate_iff(iff_sensor, no_reply, {"los": true})
	var r_wrong: Dictionary = SM.interrogate_iff(iff_sensor, wrong, {"los": true})
	var r_far: Dictionary = SM.interrogate_iff(iff_sensor, far_iff, {"los": true})
	check(String(r_friend.get("iff_status", "")) == "friend"
		and int(r_friend.get("level_support", 0)) >= 3,
		"IFF 友方应答 → friend / 身份支撑")
	check(String(r_faulty.get("iff_status", "")) == "faulty_transponder",
		"应答机故障 → faulty_transponder")
	check(String(r_none.get("iff_status", "")) == "no_reply", "关闭应答机 → no_reply")
	check(String(r_wrong.get("iff_status", "")) == "wrong_code", "错误码 → wrong_code")
	check(not bool(r_far.get("detected", true)) and String(r_far.get("reason", "")).begins_with("out_of_range"),
		"超出 2,000 km → IFF 不成立", String(r_far.get("reason", "")))
	check(bool(r_none.get("warning", "").contains("不明 ≠ 敌意")), "IFF 警示：不明 ≠ 敌意")
	check(_json_ok(r_friend) and _json_ok(r_none), "IFF 结果 JSON 可序列化")

	# ── 7. ELINT 被动截获 ──────────────────────────────────────
	print("")
	print("── 7. ELINT 被动截获（只出信号不出接触）──")
	var elint_sensor: Dictionary = elint_rec.as_v15_sensor()
	var emitting: Dictionary = tgt("E1", 30000.0, 75.0, 10.0, 1.0, "off", "",
		[{"model": "YW-R9", "type": "radar", "on": true, "range_km": 30000.0}])
	var silent: Dictionary = tgt("E2", 30000.0, 120.0, 10.0, 1.0, "off", "", [])
	var too_far: Dictionary = tgt("E3", 52000.0, 150.0, 10.0, 1.0, "off", "",
		[{"model": "LR-4", "type": "optical", "subtype": "lidar", "on": true, "range_km": 4000.0}])
	var e_hit: Dictionary = SM.detect_elint(elint_sensor, emitting, {"los": true})
	var e_silent: Dictionary = SM.detect_elint(elint_sensor, silent, {"los": true})
	var e_far: Dictionary = SM.detect_elint(elint_sensor, too_far, {"los": true})
	check(bool(e_hit.get("detected", false)) and not bool(e_hit.get("produces_contact", true)),
		"ELINT 截获发射源 · produces_contact=false")
	var sig: Dictionary = e_hit.get("signal", {})
	check(String(sig.get("signature", "")) == "YW-R9" and bool(sig.get("bearing_only", false)),
		"信号特征码 YW-R9 / 仅方位")
	check(not bool(e_silent.get("detected", true))
		and String(e_silent.get("reason", "")).begins_with("no_emission"),
		"对方静默 → 收不到", String(e_silent.get("reason", "")))
	check(not bool(e_far.get("detected", true)),
		"超出 ELINT 截获距离 → 收不到", String(e_far.get("reason", "")))
	check(_json_ok(e_hit), "ELINT 结果 JSON 可序列化")

	# ── 8. 快照 / 确定性 ───────────────────────────────────────
	print("")
	print("── 8. 快照 JSON / 确定性 ──")
	var snap0 := snap(0.0, [tgt("T1", 10000.0, 40.0)])
	check(_json_ok(snap0), "world snapshot JSON 可序列化")
	var tws_a = TwsModel.new(radar_rec, {"max_channels": 6})
	var tws_b = TwsModel.new(radar_rec, {"max_channels": 6})
	for k in range(3):
		var ss: Array = [tgt("T1", 10000.0, 40.0), tgt("T2", 12000.0, 90.0)]
		tws_a.step(6.0, snap(float(k * 6), ss))
		tws_b.step(6.0, snap(float(k * 6), ss))
	check(JSON.stringify(tws_a.to_dict()) == JSON.stringify(tws_b.to_dict()),
		"确定性：同输入两次 TWS 运行结果一致")

	# ── 9. 完整光学/IR（vendored V2OpticalIRChannel）─────────────
	print("")
	print("── 9. 完整光学/IR（optical_ir）──")
	var om = OpticalIR.new()
	check((om.errors as Array).is_empty(), "optical_ir setup 无错误", str(om.errors))
	var osensor: Dictionary = om.sensors_view()["optical"]
	var isensor: Dictionary = om.sensors_view()["ir"]
	check(absf(float(osensor.get("fov_deg", 0.0)) - 0.2444) < 2.0e-4, "VIS FOV≈0.2444°")
	check(absf(float(osensor.get("ifov_urad", 0.0)) - 1.0417) < 1.0e-3, "VIS IFOV≈1.04 µrad")
	check(absf(float(isensor.get("fov_deg", 0.0)) - 0.7334) < 2.0e-4, "IR FOV≈0.7334°")
	var o_obs := {"id": "SX-01", "pos_km": [7000.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]}
	var o_t1 := OpticalIR.make_target("T1", [7000.0, 8000.0, 0.0],
		{"size_m": 50.0, "classification": {"ship_class": "DDG"}})
	var o_snap := OpticalIR.make_snapshot(0.0, o_obs, [o_t1], {})
	om.start_channel("optical", "T1")
	om.start_channel("ir", "T1")
	for i in range(100):
		om.step(0.5, o_snap)
	var ov: Dictionary = om.channel("optical", "T1")
	var oi: Dictionary = om.channel("ir", "T1")
	check(String(ov.get("status", "")) == "locked", "optical_ir VIS 锁定", String(ov.get("status", "")))
	check(int(ov.get("level_support", 0)) == 3, "optical_ir VIS → L3/classification")
	check(not (ov.get("classification", {}) as Dictionary).is_empty(), "optical_ir VIS classification")
	check(String(oi.get("status", "")) == "locked" and int(oi.get("level_support", 0)) == 1,
		"optical_ir IR 锁定 → L1")
	check(float(ov.get("fov_deg", 0.0)) > 0.0 and float(ov.get("snr_db", 0.0)) > 0.0,
		"optical_ir FOV/SNR 字段")
	check(String(ov.get("reason", "")) != "occluded", "optical_ir 无遮挡")
	# FOV 外
	var o_off := OpticalIR.make_target("OFF", [15000.0, 0.0, 0.0], {"size_m": 50.0})
	var om2 = OpticalIR.new()
	om2.start_channel("optical", "OFF", {"boresight_deg": 0.0, "boresight_el_deg": 0.0})
	om2.step(0.5, OpticalIR.make_snapshot(0.0, o_obs, [o_off], {}))
	check(String(om2.channel("optical", "OFF").get("reason", "")) == "fov_miss",
		"optical_ir 视轴外 → fov_miss")
	# 地球遮挡
	var o_behind := OpticalIR.make_target("BEHIND", [-7000.0, 0.0, 0.0], {"size_m": 50.0})
	var om3 = OpticalIR.new()
	om3.start_channel("optical", "BEHIND", {"boresight_deg": -90.0})
	om3.step(1.0, OpticalIR.make_snapshot(0.0, o_obs, [o_behind], {}))
	check(String(om3.channel("optical", "BEHIND").get("reason", "")) == "occluded",
		"optical_ir 地球遮挡 → occluded")
	# 角速度模糊
	var o_blur := OpticalIR.make_target("BLUR", [7000.0, 8000.0, 0.0], {"size_m": 50.0,
		"vel_kmps": [10.0, 0.0, 0.0]})
	var om4 = OpticalIR.new()
	om4.start_channel("optical", "BLUR")
	om4.step(0.5, OpticalIR.make_snapshot(0.0, o_obs, [o_blur], {}))
	check(String(om4.channel("optical", "BLUR").get("reason", "")) == "blurred",
		"optical_ir 角速度 → blurred")
	check(_json_ok(om.vm_optical_ir()), "optical_ir VM JSON 可序列化")
	check(bool((om.vm_optical_ir().get("writes", {}) as Dictionary).get("track_table", true)) == false,
		"optical_ir 不写 TrackTable")

	# ── 10. 信息作战（vendored V2InformationWarfare）────────────
	print("")
	print("── 10. IFF / ELINT / COMINT / EW（information_warfare）──")
	var info = InfoModel.new()
	var i_cfg: Dictionary = {
		"observer": {"id": "SX-01", "pos_km": [0.0, 0.0, 0.0]},
		"targets": [
			{"id": "F1", "pos_km": [0.0, 1500.0, 0.0], "transponder": "ok",
				"registered": true, "crypto_epoch": "epoch-1",
				"iff_codes": {"3/A": "CMP-119"}},
			{"id": "F2", "pos_km": [0.0, 1000.0, 0.0], "transponder": "off"},
			{"id": "E1", "pos_km": [0.0, 30000.0, 0.0], "transponder": "off",
				"emissions": [{"model": "YW-R9", "type": "radar", "active": true,
					"power_dbm": 90.0, "frequency_mhz": 9500.0}],
				"comms": [{"from": "E1", "to": "F1", "mode": "radio",
					"text": "SECRET", "encrypted": true, "frequency_mhz": 300.0}]},
		],
	}
	info.setup(i_cfg)
	var ir_friend: Dictionary = info.interrogate_iff("F1", ["3/A"],
		{"expected_codes": {"3/A": "CMP-119"}})
	check(String(ir_friend.get("status", "")) == "reply_ok"
		and String(ir_friend.get("identity", "")) == "friend", "IFF 友方应答 → friend")
	check(bool(ir_friend.get("produces_contact", true)) == false, "IFF 不产生接触/位置")
	var ir_none: Dictionary = info.interrogate_iff("F2", ["3/A"])
	check(String(ir_none.get("status", "")) == "no_reply"
		and String(ir_none.get("identity", "")) == "unknown", "IFF 无应答 → unknown（不判敌）")
	check(bool(ir_none.get("never_hostile", false)) and not bool(ir_none.get("hostile_allowed", true)),
		"IFF never_hostile / hostile_allowed=false")
	var sigs: Array = info.signals
	var detected_sig := false
	for raw_s in sigs:
		if raw_s is Dictionary and String((raw_s as Dictionary).get("source_id", "")) == "E1":
			detected_sig = bool((raw_s as Dictionary).get("detected", false))
			check(bool((raw_s as Dictionary).get("produces_contact", true)) == false,
				"ELINT 单站 produces_contact=false")
			check(int((raw_s as Dictionary).get("level_support", 0)) <= 3,
				"ELINT fingerprint ≤ L3")
	check(detected_sig, "ELINT 截获 E1 信号")
	var comint_ok := false
	for raw_c in info.comint_events:
		if raw_c is Dictionary:
			if bool((raw_c as Dictionary).get("encrypted", false)):
				comint_ok = String(((raw_c as Dictionary).get("comms_content", {}) as Dictionary).get("text", "x")) == ""
	check(comint_ok, "COMINT 加密只给元数据、不解码")
	info.inject_noise_jamming("E1", "SX-01", 0.7, 60.0)
	var je: Dictionary = info.radar_effect(30000.0, 0.2)
	check(absf(float(je.get("jam_factor", 0.0)) - 0.608) < 1e-6, "EW noise jam factor=0.608")
	info.inject_deception("E1", "SX-01", 0.7, 30.0, 2)
	check(info.phantom_candidates.size() == 2, "EW phantom=2（不产生真实接触）")
	var i_vm: Dictionary = info.vm_information_warfare()
	check(_json_ok(i_vm), "information_warfare VM JSON 可序列化")
	check(int((i_vm.get("summary", {}) as Dictionary).get("iff_identity_hostile", -1)) == 0,
		"information_warfare hostile=0")
	check(bool((i_vm.get("writes", {}) as Dictionary).get("track_table", true)) == false,
		"information_warfare 不写 TrackTable")
