extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-A00 R6 返修探针：G1 完整动态指向 + G2 组合原子导入与严格校验
#
# G1 反例：只保存角度时，恢复后 `desired_target_id` 为空 → `_update_pointing`
#          直接 continue → 停止跟踪 → 移动目标提前失锁（审查方 123 tick 反例）。
# G2 反例：authority 先改 optical 再校验 TWS/元数据 → 失败仍半写；
#          radar/TWS version 未校验、scan_index 溢出、负时长、畸形通道、
#          缺 radar 子段、光学角度越界 均被接受。
#
# Output: `JC-A00 R6 SENSOR STATE PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const GS := preload("res://scripts/core/game_session.gd")

const TICK_DT := 1.0
const TRACK_TICKS := 240
const FOLLOW_TICKS := 130

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-A00 R6 SENSOR STATE PROBE · G1 动态指向 + G2 原子导入")
	print("══════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(300.0).timeout
	if _finished:
		return
	print("[R6] FAIL watchdog timeout")
	_fail += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("JC-A00 R6 SENSOR STATE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[R6] FAILED: ", f)
		print("JC-A00 R6 SENSOR STATE PROBE FAILED")
	else:
		print("JC-A00 R6 SENSOR STATE PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[R6] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[R6] FAIL ", line)


func _eq(actual, expected, label: String, detail := "") -> void:
	_ok(actual == expected, label,
		("actual=%s expected=%s" % [str(actual), str(expected)])
		+ (("  " + detail) if detail != "" else ""))


func _step(t: String) -> void:
	print("")
	print("[R6] STEP ", t)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("G1 完整动态指向：移动目标恢复后继续跟踪")
	# 目标 1000 km、切向 0.003°/s → 横向速度 = 1000*0.003*PI/180 ≈ 0.05236 km/s
	var omega_dps := 0.003
	var range_km := 1000.0
	var vtrans := range_km * omega_dps * PI / 180.0
	var s = GS.new(_seed(range_km, vtrans))
	_ok(bool(s.ready), "G1 session ready", str(s.errors))
	if not bool(s.ready):
		_finish()
		return
	var st: Dictionary = s.sensor_service.start_channel("optical", "harmattan")
	for i in range(TRACK_TICKS):
		s.tick(TICK_DT)
	var pre := _chan(s, "optical")
	var pre_az := float(pre.get("boresight_deg", 0.0))
	# 本 fixture 几何未进入 locked，但**指向跟踪**仍进行；G1 缺陷模式是
	# 「恢复后 desired_target_id 为空 → 停止跟踪 → 角度冻结」，故以持续指向为判据。
	_ok(pre_az != 0.0, "G1 original 已在持续指向（非初始 0°）", "az=%.6f" % pre_az)
	# 恢复前记录指向模式/目标（新状态字段）
	var pre_sensors: Dictionary = s.sensor_service._authority._optical_ir.sensors
	var pre_mode := String((pre_sensors.get("optical", {}) as Dictionary)
		.get("pointing_mode", ""))
	var pre_tid := String((pre_sensors.get("optical", {}) as Dictionary)
		.get("desired_target_id", ""))
	_eq(pre_mode, "track", "G1 original pointing_mode 是 track")
	_eq(pre_tid, "harmattan", "G1 original desired_target_id 已记录")
	var text: String = s.save_state()
	var r = GS.new()
	var lr: Dictionary = r.load_state(text)
	_ok(bool(lr.get("ok", false)), "G1 restore ok", str(lr.get("errors", [])))
	if not bool(lr.get("ok", false)):
		_finish()
		return
	var rs: Dictionary = r.sensor_service._authority._optical_ir.sensors
	_eq(String((rs.get("optical", {}) as Dictionary).get("pointing_mode", "")), "track",
		"G1 恢复后 pointing_mode 仍是 track")
	_eq(String((rs.get("optical", {}) as Dictionary).get("desired_target_id", "")),
		"harmattan", "G1 恢复后 desired_target_id 仍是 harmattan")
	# 继续跟踪：两侧状态必须一致（关键：修复前恢复侧会因 target 为空停止跟踪）
	var first_diff := -1
	for i in range(FOLLOW_TICKS):
		s.tick(TICK_DT)
		r.tick(TICK_DT)
		var a := _chan(s, "optical")
		var b := _chan(r, "optical")
		if String(a.get("status", "")) != String(b.get("status", "")) \
				or absf(float(a.get("boresight_deg", 0.0))
					- float(b.get("boresight_deg", 0.0))) > 1.0e-6:
			if first_diff < 0:
				first_diff = i + 1
	print("[R6] INFO G1 first divergence at tick ", first_diff)
	_eq(first_diff, -1, "G1 恢复后 %d tick 持续跟踪无分歧（审查方 123 tick 反例）"
		% FOLLOW_TICKS)
	var fin_a := _chan(s, "optical")
	var fin_b := _chan(r, "optical")
	_eq(String(fin_b.get("status", "")), String(fin_a.get("status", "")),
		"G1 最终通道状态一致", "orig=%s rest=%s" % [String(fin_a.get("status", "")),
			String(fin_b.get("status", ""))])
	_ok(absf(float(fin_b.get("boresight_deg", 0.0))
		- float(fin_a.get("boresight_deg", 0.0))) <= 1.0e-6,
		"G1 最终指向角一致",
		"orig=%.9f rest=%.9f" % [float(fin_a.get("boresight_deg", 0.0)),
			float(fin_b.get("boresight_deg", 0.0))])

	_step("G2 原子性：坏子状态不得半写（optical / TWS / authority 元数据）")
	for case_name in _atom_cases():
		var label := String(case_name)
		var ctx = GS.new(_seed(range_km, vtrans))
		ctx.sensor_service.start_channel("optical", "harmattan")
		for i in range(3):
			ctx.tick(TICK_DT)
		var good: Dictionary = ctx.sensor_service.export_state()
		var bad: Dictionary = JSON.parse_string(JSON.stringify(good))
		_mutate_atom(String(case_name), bad)
		var auth = ctx.sensor_service._authority
		var before := {
			"auth_t": float(auth.t), "auth_step": int(auth.step_count),
			"opt_t": float(auth._optical_ir.t),
			"tws_t": float(auth._tws.now_t),
			"radar_t": float(auth._tws.radar.elapsed_s),
		}
		var res: Dictionary = ctx.sensor_service.import_state(bad)
		_ok(bool(res.get("ok", true)) == false, "G2 拒绝: " + label,
			str(res.get("reason", "")))
		var after := {
			"auth_t": float(auth.t), "auth_step": int(auth.step_count),
			"opt_t": float(auth._optical_ir.t),
			"tws_t": float(auth._tws.now_t),
			"radar_t": float(auth._tws.radar.elapsed_s),
		}
		_ok(JSON.stringify(before) == JSON.stringify(after),
			"G2 拒绝后全部时钟不变: " + label,
			"before=%s after=%s" % [JSON.stringify(before), JSON.stringify(after)])

	_step("G2 严格校验矩阵（版本/溢出/负值/畸形通道/缺子段/角度越界）")
	var base_ctx = GS.new(_seed(range_km, vtrans))
	base_ctx.sensor_service.start_channel("optical", "harmattan")
	for i in range(3):
		base_ctx.tick(TICK_DT)
	var good_state: Dictionary = base_ctx.sensor_service.export_state()
	_ok(bool(base_ctx.sensor_service.import_state(
		JSON.parse_string(JSON.stringify(good_state))).get("ok", false)),
		"G2 合法状态往返通过")
	for spec_name in _strict_cases():
		var label2 := String(spec_name)
		var bad2: Dictionary = JSON.parse_string(JSON.stringify(good_state))
		_mutate_strict(String(spec_name), bad2)
		var probe = GS.new(_seed(range_km, vtrans))
		probe.sensor_service.start_channel("optical", "harmattan")
		for i in range(3):
			probe.tick(TICK_DT)
		var r2: Dictionary = probe.sensor_service.import_state(bad2)
		_ok(bool(r2.get("ok", true)) == false, "G2 STRICT 拒绝: " + label2,
			str(r2.get("errors", []).slice(0, 2)))
	# 额外直接验证 radar/tws 子状态版本与安全范围
	var auth2 = base_ctx.sensor_service._authority
	var be: Dictionary = auth2.export_backend_state()
	var twsv: Dictionary = auth2._tws.validate_state(be.get("tws", {}))
	_ok(bool(twsv.get("ok", false)), "G2 tws 自身导出态通过 validate_state",
		str(twsv.get("errors", [])))
	var bad_be: Dictionary = JSON.parse_string(JSON.stringify(be))
	(bad_be.get("tws", {}) as Dictionary)["version"] = 999
	_ok(bool(auth2._tws.validate_state(bad_be.get("tws", {})).get("ok", true)) == false,
		"G2 tws version=999 被 validate_state 拒绝")
	var bad_be2: Dictionary = JSON.parse_string(JSON.stringify(be))
	((bad_be2.get("tws", {}) as Dictionary).get("radar", {}) as Dictionary)["scan_index"] = 1.0e100
	_ok(bool(auth2._tws.validate_state(bad_be2.get("tws", {})).get("ok", true)) == false,
		"G2 radar scan_index=1e100 被拒绝（安全整数范围）")

	_step("G2/R7 STARE 通道：字段齐全但缺 FSM 必需字段必须拒绝")
	for stare_name in _stare_cases():
		var lbl := String(stare_name)
		var bad3: Dictionary = JSON.parse_string(JSON.stringify(good_state))
		_make_stare_case(String(stare_name), bad3)
		var pr = GS.new(_seed(range_km, vtrans))
		pr.sensor_service.start_channel("optical", "harmattan")
		for i in range(3):
			pr.tick(TICK_DT)
		var r3: Dictionary = pr.sensor_service.import_state(bad3)
		_ok(bool(r3.get("ok", true)) == false, "G2/R7 拒绝: " + lbl,
			str(r3.get("errors", []).slice(0, 2)))

	_step("C 旧档迁移：v1 合法旧数据做可重建迁移并如实标 partial，不冒充完整恢复")
	# 模拟 C55 旧档：backend 无 tws / authority_* / mount_pointing
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(good_state))
	var lb: Dictionary = legacy.get("backend", {}) as Dictionary
	lb.erase("tws")
	lb.erase("authority_t")
	lb.erase("authority_step_count")
	lb.erase("authority_dt_last")
	lb.erase("mount_pointing")
	legacy["backend"] = lb
	var leg_sess = GS.new(_seed(range_km, vtrans))
	leg_sess.sensor_service.start_channel("optical", "harmattan")
	for i in range(3):
		leg_sess.tick(TICK_DT)
	var legr: Dictionary = leg_sess.sensor_service.import_state(legacy)
	_ok(bool(legr.get("ok", false)), "C 旧 v1 档可迁移导入（不误判为损坏）",
		str(legr.get("reason", "")))
	_eq(String(legr.get("restore_mode", "")), "partial",
		"C 旧档明确标记 partial restore")
	var prs: Array = legr.get("partial_reasons", [])
	_ok(prs.size() > 0, "C 旧档列出部分恢复原因", str(prs))
	_ok(String(JSON.stringify(prs)).find("tws_runtime_reset_unrecoverable") >= 0,
		"C 明确标注 TWS 运行态不可重建", str(prs.slice(0, 3)))
	_ok(String(JSON.stringify(prs)).find("pointing_target_not_persisted") >= 0,
		"C 明确标注旧档指向目标未持久化", str(prs.slice(0, 3)))
	# 对照：新格式缺 tws 仍必须拒绝（损坏而非旧档）
	var broken_new: Dictionary = JSON.parse_string(JSON.stringify(good_state))
	((broken_new.get("backend", {}) as Dictionary))["authority_t"] = 5.0
	((broken_new.get("backend", {}) as Dictionary)).erase("tws")
	var brk_sess = GS.new(_seed(range_km, vtrans))
	brk_sess.sensor_service.start_channel("optical", "harmattan")
	for i in range(3):
		brk_sess.tick(TICK_DT)
	var brkr: Dictionary = brk_sess.sensor_service.import_state(broken_new)
	_ok(bool(brkr.get("ok", true)) == false,
		"C 新格式缺 TWS 仍拒绝（与旧档区分）", str(brkr.get("errors", []).slice(0, 2)))

	_step("C2 公共 load 透传：GameSession.load_state 必须报告 partial 模式与原因")
	var gs_sess = GS.new(_seed(range_km, vtrans))
	gs_sess.sensor_service.start_channel("optical", "harmattan")
	for i in range(3):
		gs_sess.tick(TICK_DT)
	var gs_text: String = gs_sess.save_state()
	var gs_doc: Dictionary = JSON.parse_string(gs_text)
	var gs_backend: Dictionary = (gs_doc.get("sensor_service", {}) as Dictionary) \
		.get("backend", {}) as Dictionary
	gs_backend.erase("tws")
	gs_backend.erase("authority_t")
	gs_backend.erase("authority_step_count")
	gs_backend.erase("authority_dt_last")
	gs_backend.erase("mount_pointing")
	(gs_doc.get("sensor_service", {}) as Dictionary)["backend"] = gs_backend
	var gs_r = GS.new()
	var gs_lr: Dictionary = gs_r.load_state(JSON.stringify(gs_doc))
	_ok(bool(gs_lr.get("ok", false)), "C2 旧档经公共 load 成功",
		str(gs_lr.get("errors", [])))
	_eq(String(gs_lr.get("sensor_restore_mode", "")), "partial",
		"C2 公共 load 结果透传 restore_mode=partial")
	var gsrp: Dictionary = gs_r.sensor_restore_report()
	_eq(bool(gsrp.get("is_partial", false)), true,
		"C2 恢复报告标记 is_partial")
	_ok((gsrp.get("partial_reasons", []) as Array).size() > 0,
		"C2 恢复报告携带 partial_reasons",
		str((gsrp.get("partial_reasons", []) as Array).slice(0, 3)))
	# 对照：完整档必须是 full
	var full_sess = GS.new(_seed(range_km, vtrans))
	full_sess.sensor_service.start_channel("optical", "harmattan")
	for i in range(3):
		full_sess.tick(TICK_DT)
	var full_text: String = full_sess.save_state()
	var full_r = GS.new()
	var full_lr: Dictionary = full_r.load_state(full_text)
	_eq(String(full_lr.get("sensor_restore_mode", "")), "full",
		"C2 完整档经公共 load 报告 full")

	_step("总结")
	print("[R6] INFO G1 指向/模式持久化 + G2 两阶段原子导入与严格校验已覆盖")
	_finish()


func _atom_cases() -> Array:
	return ["坏 optical channels（缺 status）", "坏 TWS channels（缺 last_update_t）",
		"坏 authority_t（Inf）", "缺 TWS 子状态"]


func _mutate_atom(case_name: String, bad: Dictionary) -> void:
	var backend: Dictionary = bad.get("backend", {}) as Dictionary
	match case_name:
		"坏 optical channels（缺 status）":
			var ch: Array = backend.get("channels", []) as Array
			if ch.size() > 0:
				(ch[0] as Dictionary).erase("status")
		"坏 TWS channels（缺 last_update_t）":
			var tws: Dictionary = backend.get("tws", {}) as Dictionary
			var chans: Dictionary = tws.get("channels", {}) as Dictionary
			for k in chans.keys():
				(chans[k] as Dictionary).erase("last_update_t")
				break
		"坏 authority_t（Inf）":
			backend["authority_t"] = INF
		"缺 TWS 子状态":
			backend.erase("tws")


func _stare_cases() -> Array:
	return ["STARE 缺 stare_s/stare_required_s", "通道缺 scan_index/last_miss_t",
		"quality 非数字", "history 显式 null", "stare_s 显式 null",
		"state_since_t 显式 null"]


func _make_stare_case(case_name: String, bad: Dictionary) -> void:
	var backend: Dictionary = bad.get("backend", {}) as Dictionary
	var tws: Dictionary = backend.get("tws", {}) as Dictionary
	match case_name:
		"STARE 缺 stare_s/stare_required_s":
			tws["channels"] = {"broken": {"target_id": "broken",
				"state": "STARE", "quality": 1.0, "last_update_t": 0.0}}
			backend["tws"] = tws
		"通道缺 scan_index/last_miss_t":
			var chans: Dictionary = tws.get("channels", {}) as Dictionary
			chans["x"] = {"target_id": "x", "state": "TRACK",
				"state_since_t": 0.0, "slot": 0, "quality": 0.5, "age_s": 0.0,
				"pd": 0.5, "hits": 1, "consecutive_hits": 1, "misses": 0,
				"update_count": 1, "update_rate_hz": 1.0, "last_update_t": 1.0,
				"range_km": 10.0, "bearing_deg": 0.0, "elevation_deg": 0.0,
				"range_sigma_km": 0.1, "bearing_sigma_deg": 0.1,
				"stable_track": true, "in_sphere": true,
				"effective_radius_km": 1.0, "stare_s": 0.0,
				"stare_required_s": 8.0, "stare_progress": 0.0,
				"fire_control": {}, "lost_lock_count": 0, "exposure": {},
				"history": []}
			tws["channels"] = chans
			backend["tws"] = tws
		"quality 非数字":
			var chans3: Dictionary = tws.get("channels", {}) as Dictionary
			for k in chans3.keys():
				(chans3[k] as Dictionary)["quality"] = "high"
				break
			tws["channels"] = chans3
			backend["tws"] = tws
		"history 显式 null":
			var chans4: Dictionary = tws.get("channels", {}) as Dictionary
			for k4 in chans4.keys():
				(chans4[k4] as Dictionary)["history"] = null
				break
			tws["channels"] = chans4
			backend["tws"] = tws
		"stare_s 显式 null":
			var chans5: Dictionary = tws.get("channels", {}) as Dictionary
			for k5 in chans5.keys():
				(chans5[k5] as Dictionary)["stare_s"] = null
				break
			tws["channels"] = chans5
			backend["tws"] = tws
		"state_since_t 显式 null":
			var chans6: Dictionary = tws.get("channels", {}) as Dictionary
			for k6 in chans6.keys():
				(chans6[k6] as Dictionary)["state_since_t"] = null
				break
			tws["channels"] = chans6
			backend["tws"] = tws


func _strict_cases() -> Array:
	return ["sensor version=1.5", "optical version=999", "optical az=1000 越界",
		"optical pointing_mode 非法", "tws negative now_t", "radar scan_index 分数"]


func _mutate_strict(case_name: String, bad: Dictionary) -> void:
	var backend2: Dictionary = bad.get("backend", {}) as Dictionary
	match case_name:
		"sensor version=1.5":
			bad["version"] = 1.5
		"optical version=999":
			backend2["version"] = 999
		"optical az=1000 越界":
			var mp: Dictionary = backend2.get("mount_pointing", {}) as Dictionary
			var row: Dictionary = mp.get("optical", {}) as Dictionary
			row["boresight_deg"] = 1000.0
			mp["optical"] = row
			backend2["mount_pointing"] = mp
		"optical pointing_mode 非法":
			var mp2: Dictionary = backend2.get("mount_pointing", {}) as Dictionary
			var row2: Dictionary = mp2.get("optical", {}) as Dictionary
			row2["pointing_mode"] = "slewing"
			mp2["optical"] = row2
			backend2["mount_pointing"] = mp2
		"tws negative now_t":
			((backend2.get("tws", {}) as Dictionary))["now_t"] = -5.0
		"radar scan_index 分数":
			var tws2: Dictionary = backend2.get("tws", {}) as Dictionary
			var rd: Dictionary = tws2.get("radar", {}) as Dictionary
			rd["scan_index"] = 1.5
			tws2["radar"] = rd
			backend2["tws"] = tws2


func _chan(s, kind: String) -> Dictionary:
	var auth = s.sensor_service._authority
	if auth == null or auth._optical_ir == null:
		return {}
	return auth._optical_ir.channel(kind, "harmattan")


func _seed(sep_km: float, vtrans: float) -> Dictionary:
	return {
		"own_entity": "apsis", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"sensor_service": {
			"observer": {"id": "apsis", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [
				{"id": "harmattan", "pos_km": [321719.0, sep_km, 0.0],
					"rcs_m2": 1100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}},
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [321719.0, sep_km, 0.0],
				"vel_kmps": [vtrans, 0.0, 0.0]}],
	}
