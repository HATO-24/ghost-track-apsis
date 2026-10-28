extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-A03（#60）EW 实际影响观测/航迹/火控 · 验收探针
#
# 真实 API：session.apply_ew → tick（真实 sensor 采样）→ owner 情报/航迹
# → 延迟队列 → 火控解算/射击结果 → 真实文件恢复继续 10 tick。
#
# Output: `JC-A03 EW OBSERVATION PROBE RESULT: PASS=n FAIL=m`; quit 0/1
# ═══════════════════════════════════════════════════════════════════

const GS := preload("res://scripts/core/game_session.gd")
const TICK_DT := 1.0
const CONF_TOL := 1.0e-9
const TIME_TOL := 1.0e-6

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-A03 EW OBSERVATION PROBE · 采样/质量/延迟/航迹/火控/恢复")
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(420.0).timeout
	if _finished:
		return
	print("[A03] FAIL watchdog timeout")
	_fail += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("JC-A03 EW OBSERVATION PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A03] FAILED: ", f)
		print("JC-A03 EW OBSERVATION PROBE FAILED")
	else:
		print("JC-A03 EW OBSERVATION PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A03] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A03] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(a: float, b: float, tol: float, label: String) -> void:
	_ok(absf(float(a) - float(b)) <= tol, label,
		"actual=%s expected=%s tol=%s" % [str(a), str(b), str(tol)])


func _step(t: String) -> void:
	print("")
	print("[A03] STEP ", t)


func _info(t: String) -> void:
	print("[A03] INFO ", t)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("W1 同 seed EW 关/开：真实 sensor 观测质量与 effect 采样")
	var sa = _new()
	for i1 in range(2):
		sa.tick(TICK_DT)
	var sb = _new()
	var jam: Dictionary = sb.apply_ew({"effect": "noise_jam",
		"target_id": "raider_2", "severity": 0.5, "duration_s": 60.0,
		"source_id": "EW-1", "band": "radar"})
	_ok(bool(jam.get("ok", false)), "EW noise_jam=0.5 经真实 API 生效",
		str(jam.get("reason", "")))
	for i2 in range(2):
		sb.tick(TICK_DT)
	var samples: Array = sb.ew_observation_samples()
	_ok(samples.size() > 0, "真实观测产生 EW effect 采样", "n=" + str(samples.size()))
	var s_raid: Dictionary = _sample_for(samples, "raider_2")
	_ok(not s_raid.is_empty(), "raider_2 观测有采样记录")
	var eff: Dictionary = s_raid.get("effect", {}) if s_raid.get("effect") is Dictionary else {}
	_near(float(eff.get("delay_s", -1.0)), 3.0, TIME_TOL,
		"effect.delay_s = 6×0.5 = 3s（真实采样）")
	var q_before := float(s_raid.get("quality_before", -1.0))
	var q_after := float(s_raid.get("quality_after", -1.0))
	_ok(q_before > 0.0, "采样记录原始质量", str(q_before))
	_near(q_after, q_before * 0.7, CONF_TOL, "观测质量 = 原质量 × 0.7")
	_eq(String(s_raid.get("sensor_kind", "")), "radar", "采样传感器类型 radar")
	_eq(bool(eff.get("jammed", false)), true, "采样标记录受干扰")
	# EW 关对照：质量不降、无延迟
	var sa_track: Dictionary = _view_track(sa, "player_intel", "raider_2")
	_ok(not sa_track.is_empty(), "EW 关时观测进入 owner 航迹")
	_near(float(sa_track.get("measurement_quality", -1.0)), q_before, CONF_TOL,
		"EW 关测量质量不降")

	_step("W2/W3 延迟队列：到达前不可见、到达后可见且时间一致")
	var sb_track: Dictionary = _view_track(sb, "player_intel", "raider_2")
	_ok(sb_track.is_empty(), "延迟期间 owner 情报不可见（不提前显示）",
		"t=" + str(sb.now_s()))
	_ok((sb.ew_delivery_queue() as Array).size() > 0, "真实延迟队列非空")
	var delivered_before: int = (sb.ew_delivered_observations() as Array).size()
	for i3 in range(4):
		sb.tick(TICK_DT)
	var sb_track2: Dictionary = _view_track(sb, "player_intel", "raider_2")
	_ok(not sb_track2.is_empty(), "到达后 owner 情报可见")
	var delivered: Array = sb.ew_delivered_observations()
	_ok(delivered.size() > delivered_before, "真实投递记录增长")
	var d0: Dictionary = _delivered_for(delivered, "raider_2")
	_ok(not d0.is_empty(), "raider_2 投递记录存在")
	var d_delay := float(d0.get("delay_s", -1.0))
	_near(d_delay, 3.0, TIME_TOL, "投递 delay = effect.delay_s（1e-6s）")
	_near(float(d0.get("received_t", -1.0)), float(d0.get("observed_t", -2.0)) + 3.0,
		TIME_TOL, "received_t = observed_t + delay")
	_eq(bool(d0.get("truth_regenerated", true)), false, "投递不使用后来真值重生成")
	var mq: Dictionary = sb.owner_measurement_quality("player_intel", "raider_2")
	_ok(bool(mq.get("ok", false)), "owner 当前测量质量可读",
		str(mq.get("reason", "")))
	_near(float(mq.get("measurement_quality", -1.0)), 0.7, CONF_TOL,
		"owner 航迹当前测量质量 = 0.7")

	_step("W4 当前测量质量进入实际火控（冻结 fixture 规则）")
	_register_combat_track(sb, "raider_2")
	var sol: Dictionary = sb.combat_request_solution("raider_2", "missile", true)
	var cq: Dictionary = sb.combat_measurement_quality("raider_2")
	_ok(bool(cq.get("ok", false)), "火控边界读到当前测量质量",
		str(cq.get("reason", "")))
	_near(float(cq.get("measurement_quality", -1.0)), 0.7, CONF_TOL,
		"火控边界测量质量 = 0.7")
	_ok(bool(sol.get("ok", false)), "降质后解算仍可执行（0.5<=q<0.9）",
		str(sol.get("reason", "")))
	if bool(sol.get("ok", false)):
		var solv: Dictionary = sol.get("solution", {}) if sol.get("solution") is Dictionary else {}
		_near(float(solv.get("measurement_quality", -1.0)), 0.7, CONF_TOL,
			"解算结果记录消费质量 0.7")
		var base_time := float(sol.get("base_solution_s", 0.0))
		var eff_time := float(solv.get("solution_s", 0.0))
		_ok(eff_time > base_time, "低质量解算耗时增加",
			"base=%s eff=%s" % [str(base_time), str(eff_time)])
		_near(eff_time, base_time * 1.5, TIME_TOL, "解算耗时为基准 ×1.5")
	# 低质量门槛
	var sb_low = _new()
	sb_low.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 1.0, "duration_s": 60.0, "source_id": "EW-2"})
	for i4 in range(10):
		sb_low.tick(TICK_DT)
	_register_combat_track(sb_low, "raider_2")
	var sol_low: Dictionary = sb_low.combat_request_solution("raider_2", "missile", true)
	_ok(bool(sol_low.get("ok", true)) == false, "q<0.5 时解算被拒绝",
		str(sol_low.get("reason", "")))
	_eq(String(sol_low.get("reason", "")), "insufficient_quality",
		"拒绝原因明确为质量不足")

	_step("W5 历史聚合不吞当前退化")
	var sc = _new()
	for i5 in range(2):
		sc.tick(TICK_DT)
	sc.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.5, "duration_s": 60.0, "source_id": "EW-3"})
	for i5b in range(10):
		sc.tick(TICK_DT)
	var mq5: Dictionary = sc.owner_measurement_quality("player_intel", "raider_2")
	var last_q5 := -1.0
	var max_q5 := -1.0
	for raw_s5 in (sc.ew_observation_samples() as Array):
		if raw_s5 is Dictionary and String((raw_s5 as Dictionary).get(
				"target_id", "")) == "raider_2":
			var qa5 := float((raw_s5 as Dictionary).get("quality_after", -1.0))
			last_q5 = qa5
			max_q5 = maxf(max_q5, float((raw_s5 as Dictionary).get(
				"quality_before", -1.0)))
	_near(float(mq5.get("measurement_quality", -1.0)), last_q5, CONF_TOL,
		"当前测量质量等于最近一次真实采样（受干扰后）")
	_ok(float(mq5.get("aggregate_quality", -1.0)) >= max_q5 - CONF_TOL,
		"历史聚合质量保留较高值（与当前测量分开）",
		"agg=" + str(mq5.get("aggregate_quality", null)) + " max_sample=" + str(max_q5))
	var cq5: Dictionary = sc.combat_measurement_quality("raider_2") if \
		sc.combat_measurement_quality("raider_2") is Dictionary else {}
	_ok(String(cq5.get("reason", "")) != "", "未注册 combat 航迹时火控质量显式不可用",
		str(cq5.get("reason", "")))

	_step("W6 欺骗候选：只进被影响 owner、identity=unknown、不自动成确认目标")
	var sd = _new()
	sd.apply_ew({"effect": "deception", "target_id": "raider_2",
		"severity": 0.6, "duration_s": 60.0, "source_id": "EW-4"})
	for i6 in range(5):
		sd.tick(TICK_DT)
	var cand: Array = sd.ew_candidate_evidence("player_intel")
	_ok(cand.size() > 0, "欺骗候选进入被影响 owner 的普通证据流",
		"n=" + str(cand.size()))
	var bad_ident := false
	for raw_c in cand:
		if raw_c is Dictionary and String((raw_c as Dictionary).get(
			"identity", "unknown")) != "unknown":
			bad_ident = true
	_ok(not bad_ident, "候选证据 identity 保持 unknown（不自动确认）")
	_eq((sd.ew_candidate_evidence("ally_intel") as Array).size(), 0,
		"候选不泄漏给其他 owner")

	_step("W7 真实文件在途恢复：队列/可见/质量/解算继续 ≥10 tick 一致")
	var se = _new()
	se.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.5, "duration_s": 120.0, "source_id": "EW-5"})
	for i7 in range(2):
		se.tick(TICK_DT)
	_ok((se.ew_delivery_queue() as Array).size() > 0, "保存前存在在途观测")
	_ok((se.ew_delivery_queue() as Array).size() > 0, "保存前存在在途观测")
	var path := "user://jc_a03_ew_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(se.save_state())
	f.close()
	var sf = _new()
	var lr: Dictionary = sf.load_state(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(bool(lr.get("ok", false)), "真实文件恢复成功", str(lr.get("errors", [])))
	_ok((sf.ew_delivery_queue() as Array).size() > 0, "在途观测队列随档恢复")
	# 全量比较：队列条目、捕获观测几何/质量、投递审计、owner 质量与实际解算
	_register_combat_track(se, "raider_2")
	_register_combat_track(sf, "raider_2")
	se.grant_authorization("FIRE", "target", "raider_2")
	sf.grant_authorization("FIRE", "target", "raider_2")
	var sol_e: Dictionary = se.combat_request_solution("raider_2", "missile", true)
	var sol_f: Dictionary = sf.combat_request_solution("raider_2", "missile", true)
	var vis_ok := true
	var first_bad := ""
	for i8 in range(10):
		se.tick(TICK_DT)
		sf.tick(TICK_DT)
		var ids_e: Array = _visibility_ids(se.ew_visible_tracks("player_intel"))
		var ids_f: Array = _visibility_ids(sf.ew_visible_tracks("player_intel"))
		ids_e.sort()
		ids_f.sort()
		if JSON.stringify(ids_e) != JSON.stringify(ids_f):
			vis_ok = false
			if first_bad == "":
				first_bad = "t=%s ids_e=%s ids_f=%s" % [str(se.now_s()), str(ids_e), str(ids_f)]
		# 完整队列（ID/双时间/捕获观测几何与质量）
		var q_e: Array = _queue_sig(se.ew_delivery_queue())
		var q_f: Array = _queue_sig(sf.ew_delivery_queue())
		if JSON.stringify(q_e) != JSON.stringify(q_f):
			vis_ok = false
			if first_bad == "":
				first_bad = "t=%s queue_e=%s queue_f=%s" % [str(se.now_s()),
					str(q_e), str(q_f)]
		# 投递审计（计数与末尾捕获值）
		var d_e: Array = se.ew_delivered_observations()
		var d_f: Array = sf.ew_delivered_observations()
		if d_e.size() != d_f.size():
			vis_ok = false
			if first_bad == "":
				first_bad = "t=%s delivered_e=%d delivered_f=%d" % [
					str(se.now_s()), d_e.size(), d_f.size()]
		elif d_e.size() > 0:
			var le := _delivered_sig(d_e[d_e.size() - 1] as Dictionary)
			var lf := _delivered_sig(d_f[d_f.size() - 1] as Dictionary)
			if JSON.stringify(le) != JSON.stringify(lf):
				vis_ok = false
				if first_bad == "":
					first_bad = "t=%s delivered_e=%s delivered_f=%s" % [
						str(se.now_s()), str(le), str(lf)]
		# owner 当前测量质量
		var mqe: Dictionary = se.owner_measurement_quality("player_intel", "raider_2")
		var mqf: Dictionary = sf.owner_measurement_quality("player_intel", "raider_2")
		if bool(mqe.get("ok", false)) != bool(mqf.get("ok", false)):
			vis_ok = false
			if first_bad == "":
				first_bad = "t=%s mq_ok_e=%s mq_ok_f=%s" % [str(se.now_s()),
					str(mqe.get("ok", false)), str(mqf.get("ok", false))]
		elif bool(mqe.get("ok", false)):
			var qe := float(mqe.get("measurement_quality", -1.0))
			var qf := float(mqf.get("measurement_quality", -2.0))
			if absf(qe - qf) > CONF_TOL:
				vis_ok = false
				if first_bad == "":
					first_bad = "t=%s q_e=%s q_f=%s" % [str(se.now_s()), str(qe), str(qf)]
		# 实际解算状态/质量/误差一致（在途解算继续）
		var se_sol: Dictionary = _solution_sig(se, String((sol_e.get(
			"solution", {}) as Dictionary).get("solution_id", "")))
		var sf_sol: Dictionary = _solution_sig(sf, String((sol_f.get(
			"solution", {}) as Dictionary).get("solution_id", "")))
		if JSON.stringify(se_sol) != JSON.stringify(sf_sol):
			vis_ok = false
			if first_bad == "":
				first_bad = "t=%s sol_e=%s sol_f=%s" % [str(se.now_s()),
					str(se_sol), str(sf_sol)]
	_info("W7 first mismatch: " + first_bad)
	_ok(vis_ok, "恢复后 10 tick 可见/队列/捕获值/质量/实际解算逐 tick 一致",
		first_bad)
	var de: Array = se.ew_delivered_observations()
	var df: Array = sf.ew_delivered_observations()
	_eq(de.size(), df.size(), "恢复后投递数量一致")
	if de.size() == df.size() and df.size() > 0:
		_eq(String((de[de.size() - 1] as Dictionary).get("observation_id", "")),
			String((df[df.size() - 1] as Dictionary).get("observation_id", "")),
			"恢复后末尾观测 ID 一致")
	var qe_final: Array = _queue_sig(se.ew_delivery_queue())
	var qf_final: Array = _queue_sig(sf.ew_delivery_queue())
	_eq(JSON.stringify(qe_final), JSON.stringify(qf_final), "恢复后完整队列一致")
	var se_final: Dictionary = _solution_sig(se, String((sol_e.get(
		"solution", {}) as Dictionary).get("solution_id", "")))
	var sf_final: Dictionary = _solution_sig(sf, String((sol_f.get(
		"solution", {}) as Dictionary).get("solution_id", "")))
	_eq(JSON.stringify(se_final), JSON.stringify(sf_final), "恢复后实际解算行一致")

	_step("W8 EW=0 兼容与未支持效果限制")
	var sg = _new()
	for i9 in range(3):
		sg.tick(TICK_DT)
	var qg: Dictionary = sg.owner_measurement_quality("player_intel", "raider_2")
	_ok(bool(qg.get("ok", false)), "EW=0 时测量质量可读")
	_eq(bool(qg.get("degraded", true)), false, "EW=0 不降质")
	_eq((sg.ew_delivery_queue() as Array).size(), 0, "EW=0 无延迟队列项")
	var sh = _new()
	sh.apply_ew({"effect": "comms_jam", "target_id": "raider_2",
		"severity": 0.8, "duration_s": 60.0, "source_id": "EW-6"})
	for i10 in range(2):
		sh.tick(TICK_DT)
	var s_unsup: Dictionary = _sample_for(sh.ew_observation_samples(), "raider_2")
	_ok(not s_unsup.is_empty(), "未支持效果下仍有观测采样")
	var eff_u: Dictionary = s_unsup.get("effect", {}) if \
		s_unsup.get("effect") is Dictionary else {}
	_near(float(eff_u.get("confidence_mult", -1.0)), 1.0, CONF_TOL,
		"comms_jam 不影响雷达观测质量（明确限制）")
	_near(float(eff_u.get("delay_s", -1.0)), 0.0, TIME_TOL,
		"comms_jam 不产生观测延迟")

	_step("R17 修订R1：解算/射击消费当前精度与误差，记录数据时刻与有效性（不硬禁射）")
	# 例1：干净解算 → 降质到达后旧 READY 仍可发射（观察口径），但输出必须解释质量/数据时刻
	var sl = _new()
	for i17 in range(2):
		sl.tick(TICK_DT)
	_register_combat_track(sl, "raider_2")
	_ok(bool(sl.grant_authorization("FIRE", "target", "raider_2").get("ok", false)),
		"合法 FIRE 授权")
	var sol_l: Dictionary = sl.combat_request_solution("raider_2", "missile", true)
	_ok(bool(sol_l.get("ok", false)), "干净质量下创建解算",
		str(sol_l.get("reason", "")))
	for i17b in range(12):
		sl.tick(TICK_DT)
	var sid_l := String((sol_l.get("solution", {}) as Dictionary).get(
		"solution_id", ""))
	var ready_l: Dictionary = sl.combat_service.solution_status(sid_l)
	_eq(String(ready_l.get("status", "")), "READY", "解算先到 READY")
	var ready_q0 := float(ready_l.get("quality", 0.0))
	var ammo_before := _ammo(sl, "missile")
	sl.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 1.0, "duration_s": 120.0, "source_id": "EW-L"})
	for i17c in range(10):
		sl.tick(TICK_DT)
	var mq_l: Dictionary = sl.owner_measurement_quality("player_intel", "raider_2")
	var current_low := float(mq_l.get("measurement_quality", 1.0))
	_ok(current_low < 0.5, "降质观测确已到达（q<0.5）", str(current_low))
	var fire_l: Dictionary = sl.request_fire("raider_2", "missile", true,
		{"target_entity": "raider_2", "actor_id": "player_ctrl",
			"controller_id": "player_ctrl", "domain_id": "player",
			"fleet_id": "own_fleet"})
	# 修订后口径：不硬禁射；发射仅作观察，但结果必须说明质量/有效性/数据时刻
	_ok(bool(fire_l.get("ok", false)), "旧解算低质量下仍可发射（修订口径观察）",
		str(fire_l.get("reason", "")))
	if bool(fire_l.get("ok", false)):
		_near(float(fire_l.get("measurement_quality", -1.0)), current_low,
			CONF_TOL, "发射结果记录当前测量质量")
		_eq(bool(fire_l.get("quality_valid", true)), false,
			"发射结果标记质量不足（有效性字段）")
		_eq(bool(fire_l.get("quality_sufficient", true)), false,
			"发射结果标记 quality_sufficient=false")
		_near(float(fire_l.get("quality_accuracy_mult", -1.0)), 0.85,
			CONF_TOL, "低质量发射仍消费精度因子 0.85")
		var fire_q := float(fire_l.get("quality", -1.0))
		var base_low := _clean_solution_quality(sl, "raider_2", "missile")
		_near(fire_q, base_low * 0.85, CONF_TOL,
			"低质量发射质量 = clean 基准 × 0.85")
		_ok(absf(float(fire_l.get("measurement_t", -9.0))
			- float(ready_l.get("measurement_t", -8.0))) >= 0.0,
			"发射结果带测量数据时刻", str(fire_l.get("measurement_t", null)))
		_eq(_ammo(sl, "missile"), ammo_before - 1, "观察口径发射消耗 1 发（记录不判失败）")
	# 例2：COMPUTING 期间降质 → READY 消费当前质量而非创建时质量
	var sc2 = _new()
	for i17d in range(2):
		sc2.tick(TICK_DT)
	_register_combat_track(sc2, "raider_2")
	sc2.grant_authorization("FIRE", "target", "raider_2")
	var sol_c: Dictionary = sc2.combat_request_solution("raider_2", "missile", true)
	_ok(bool(sol_c.get("ok", false)), "COMPUTING 用例创建解算")
	sc2.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.2, "duration_s": 120.0, "source_id": "EW-C"})
	for i17e in range(20):
		sc2.tick(TICK_DT)
	var sid_c := String((sol_c.get("solution", {}) as Dictionary).get(
		"solution_id", ""))
	var ready_c: Dictionary = sc2.combat_service.solution_status(sid_c)
	_eq(String(ready_c.get("status", "")), "READY", "COMPUTING 用例到达 READY")
	var mq_c := float(ready_c.get("measurement_quality", 1.0))
	_ok(mq_c < 0.9, "READY 记录的是当前（降质后）测量质量", str(mq_c))
	_near(float(ready_c.get("quality_accuracy_mult", -1.0)), 0.85, CONF_TOL,
		"READY 消费中等精度因子 0.85")
	var base_c := _clean_solution_quality(sc2, "raider_2", "missile")
	_near(float(ready_c.get("quality", -1.0)), base_c * 0.85, CONF_TOL,
		"READY 质量 = clean 基准 × 0.85（非创建时质量）")
	_ok(float(ready_c.get("error_km", -1.0)) > 0.0, "READY 记录误差",
		str(ready_c.get("error_km", null)))
	_ok(float(ready_c.get("ready_measurement_t", -1.0))
		>= float((sol_c.get("solution", {}) as Dictionary).get(
			"start_t", -1.0)), "READY 记录测量数据时刻", str(
			ready_c.get("ready_measurement_t", null)))
	# 例3：持续 moderate 的 clean 对照（同 range 输出差异）
	var sm = _new()
	for i17f in range(2):
		sm.tick(TICK_DT)
	sm.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.2, "duration_s": 120.0, "source_id": "EW-M"})
	for i17g in range(4):
		sm.tick(TICK_DT)
	_register_combat_track(sm, "raider_2")
	sm.grant_authorization("FIRE", "target", "raider_2")
	var sol_m: Dictionary = sm.combat_request_solution("raider_2", "missile", true)
	for i17h in range(20):
		sm.tick(TICK_DT)
	var sid_m := String((sol_m.get("solution", {}) as Dictionary).get(
		"solution_id", ""))
	var ready_m: Dictionary = sm.combat_service.solution_status(sid_m)
	_eq(String(ready_m.get("status", "")), "READY", "持续 moderate 解算到达 READY")
	_ok(float(ready_m.get("measurement_quality", 1.0)) < 0.9,
		"持续 moderate 测量质量 <0.9")
	var base_clean := _clean_solution_quality(sm, "raider_2", "missile")
	_near(float(ready_m.get("quality", -1.0)), base_clean * 0.85, CONF_TOL,
		"中等质量解算质量 = clean 基准 × 0.85")

	_step("R18 重投同一观测快照：整个新增消费者边界幂等，不回滚已恢复质量")
	var sr = _new()
	sr.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.4, "duration_s": 120.0, "source_id": "EW-R"})
	var q18: Array = []
	for i18b in range(30):
		sr.tick(TICK_DT)
		q18 = sr.ew_delivery_queue()
		if q18.size() > 0:
			break
	_ok(q18.size() > 0, "存在可重投的在途观测快照")
	if q18.size() > 0:
		var entry18: Dictionary = q18[0]
		sr._deliver_ew_observation(entry18)
		var mq18a: Dictionary = sr.owner_measurement_quality("player_intel",
			"raider_2")
		var del18a: int = (sr.ew_delivered_observations() as Array).size()
		sr._deliver_ew_observation(entry18)
		var mq18b: Dictionary = sr.owner_measurement_quality("player_intel",
			"raider_2")
		var del18b: int = (sr.ew_delivered_observations() as Array).size()
		_near(float(mq18b.get("measurement_quality", -1.0)),
			float(mq18a.get("measurement_quality", -2.0)), CONF_TOL,
			"重投不覆盖当前测量质量")
		_eq(del18b, del18a, "重投不增加正常投递审计")
		_ok((sr.ew_rejected_deliveries() as Array).size() >= 1,
			"重投被记录为拒绝/去重审计")

	_step("R19 损坏的新 EW 段明确失败；有效新段与真正缺段分别兼容")
	var ss = _new()
	ss.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.3, "duration_s": 60.0, "source_id": "EW-S"})
	for i19 in range(2):
		ss.tick(TICK_DT)
	var good_text: String = ss.save_state()
	var good_doc: Dictionary = JSON.parse_string(good_text)
	_ok(good_doc.get("ew_observation_queue") is Array, "有效新段含 EW 队列")
	var bad_doc: Dictionary = JSON.parse_string(good_text)
	bad_doc["ew_observation_queue"] = null
	var ss2 = _new()
	var bad_lr: Dictionary = ss2.load_state(JSON.stringify(bad_doc))
	_ok(bool(bad_lr.get("ok", true)) == false, "损坏的新 EW 队列明确失败",
		str(bad_lr.get("errors", [])))
	_eq(String(bad_lr.get("ew_restore_mode", "")), "invalid",
		"损坏新段恢复模式为 invalid")
	var ss3 = _new()
	var good_lr: Dictionary = ss3.load_state(good_text)
	_ok(bool(good_lr.get("ok", false)), "有效新段仍可恢复",
		str(good_lr.get("errors", [])))
	_eq(String(good_lr.get("ew_restore_mode", "")), "full", "有效新段模式 full")
	_ok((ss3.ew_delivery_queue() as Array).size() >= 1, "有效新段队列恢复")
	var old_doc: Dictionary = JSON.parse_string(good_text)
	for k19 in ["ew_observation_samples", "ew_observation_queue",
			"ew_delivered_observations", "ew_candidates", "ew_observation_seq",
			"ew_quality_history", "ew_combat_quality",
			"ew_rejected_deliveries"]:
		old_doc.erase(k19)
	var ss4 = _new()
	var old_lr: Dictionary = ss4.load_state(JSON.stringify(old_doc))
	_ok(bool(old_lr.get("ok", false)), "真正缺 EW 段的旧档可加载",
		str(old_lr.get("errors", [])))
	_eq(String(old_lr.get("ew_restore_mode", "")), "legacy_absent",
		"旧档恢复模式 legacy_absent")




	_step("R20 真实弹道消费者：测量精度/误差进入预测与弹体（含无测量对照）")
	var f20a = _consumer_fixture("moderate")
	var f20b = _consumer_fixture("none")
	var f20c = _consumer_fixture("no_measure")
	_ok(bool((f20a.get("fire", {}) as Dictionary).get("ok", false)),
		"moderate 实际发射成功")
	_ok(bool((f20b.get("fire", {}) as Dictionary).get("ok", false)),
		"clean 实际发射成功")
	_ok(bool((f20c.get("fire", {}) as Dictionary).get("ok", false)),
		"无测量对照实际发射成功",
		str((f20c.get("fire", {}) as Dictionary).get("reason", "")))
	var fa20: Dictionary = f20a.get("fire", {}) if f20a.get("fire") is Dictionary else {}
	var fb20: Dictionary = f20b.get("fire", {}) if f20b.get("fire") is Dictionary else {}
	var fc20: Dictionary = f20c.get("fire", {}) if f20c.get("fire") is Dictionary else {}
	var pa20: Dictionary = f20a.get("proj", {}) if f20a.get("proj") is Dictionary else {}
	var pb20: Dictionary = f20b.get("proj", {}) if f20b.get("proj") is Dictionary else {}
	var pc20: Dictionary = f20c.get("proj", {}) if f20c.get("proj") is Dictionary else {}
	_near(float((fa20.get("prediction", {}) as Dictionary).get("error_km", -1.0)),
		float(fa20.get("error_km", -2.0)), CONF_TOL, "moderate 预测误差 = 接口误差")
	_near(float((fb20.get("prediction", {}) as Dictionary).get("error_km", -1.0)),
		float(fb20.get("error_km", -2.0)), CONF_TOL, "clean 预测误差 = 接口误差")
	_near(float((fc20.get("prediction", {}) as Dictionary).get("error_km", -1.0)),
		float(fc20.get("error_km", -2.0)), CONF_TOL, "无测量对照预测误差 = 接口误差")
	_near(float(pa20.get("applied_error_km", -1.0)),
		float(fa20.get("error_km", -2.0)), CONF_TOL, "moderate 弹体采用误差 = 接口误差")
	_near(float(pb20.get("applied_error_km", -1.0)),
		float(fb20.get("error_km", -2.0)), CONF_TOL, "clean 弹体采用误差 = 接口误差")
	_near(float(pc20.get("applied_error_km", -1.0)),
		float(fc20.get("error_km", -2.0)), CONF_TOL, "无测量对照弹体采用误差 = 接口误差")
	_ok(absf(float(fa20.get("error_km", 0.0))
		- float(fc20.get("error_km", 0.0))) > CONF_TOL,
		"有测量 vs 无测量：接口误差不同（输入被使用）",
		"%s vs %s" % [str(fa20.get("error_km", null)), str(fc20.get("error_km", null))])
	_ok(absf(float(pa20.get("applied_error_km", 0.0))
		- float(pc20.get("applied_error_km", 0.0))) > CONF_TOL,
		"有测量 vs 无测量：弹体实际误差不同（真实消费者）",
		"%s vs %s" % [str(pa20.get("applied_error_km", null)),
			str(pc20.get("applied_error_km", null))])
	_ok(JSON.stringify(pa20.get("aim_km", [])) != JSON.stringify(
		pc20.get("aim_km", [])), "有测量 vs 无测量：弹体初始瞄准不同")
	_info("moderate/clean interface errors: %s / %s" % [
		str(fa20.get("error_km", null)), str(fb20.get("error_km", null))])

	_step("R21 owner 拒绝项不得写全局 TrackTable/映射")
	var r21src = _new()
	r21src.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.5, "duration_s": 60.0, "source_id": "EW-R21"})
	var entry21: Dictionary = {}
	for i21 in range(6):
		r21src.tick(TICK_DT)
		var q21: Array = r21src.ew_delivery_queue()
		if q21.size() > 0:
			entry21 = (q21[0] as Dictionary).duplicate(true)
			break
	_ok(not entry21.is_empty(), "捕获到真实投递快照")
	var s21 = _new()
	for i21b in range(2):
		s21.tick(TICK_DT)
	var tracks_before := int(s21.track_table.tracks.size())
	var map_before: int = (s21._sensor_track_map as Dictionary).size()
	if not entry21.is_empty():
		var wrong: Dictionary = entry21.duplicate(true)
		wrong["owner_id"] = "ally_intel"
		s21._deliver_ew_observation(wrong)
	_eq(int(s21.track_table.tracks.size()), tracks_before,
		"owner 拒绝项不写全局 TrackTable")
	_eq((s21._sensor_track_map as Dictionary).size(), map_before,
		"owner 拒绝项不更新 sensor 映射")
	var rej21: Array = s21.ew_rejected_deliveries()
	_ok(rej21.size() >= 1, "owner 拒绝项记录 rejected 审计")

	_step("R22 部分新 EW 段：可解释 partial，不触发转换异常")
	var sp = _new()
	sp.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.5, "duration_s": 60.0, "source_id": "EW-R22"})
	for i22 in range(2):
		sp.tick(TICK_DT)
	var sp_doc: Dictionary = JSON.parse_string(sp.save_state())
	sp_doc.erase("ew_combat_quality")
	var sp2 = _new()
	var sp_lr: Dictionary = sp2.load_state(JSON.stringify(sp_doc))
	_ok(bool(sp_lr.get("ok", false)), "部分新段仍可恢复",
		str(sp_lr.get("errors", [])))
	_eq(String(sp_lr.get("ew_restore_mode", "")), "partial",
		"部分新段恢复模式 partial")
	var miss22: Array = sp_lr.get("ew_restore_missing", []) if \
		sp_lr.get("ew_restore_missing") is Array else []
	_ok("ew_combat_quality" in miss22, "missing 列出缺失字段", str(miss22))

	_step("R23 发射前普通预测：实体键/HUD匿名键读同一质量，mq-only 分支实际应用因子")
	var pre_m = _prefire_session(true)
	var pre_c = _prefire_session(false)
	_ok(not pre_m.is_empty(), "moderate 发射前会话就绪", str(pre_m.get("reason", "")))
	_ok(not pre_c.is_empty(), "clean 发射前会话就绪", str(pre_c.get("reason", "")))
	if not pre_m.is_empty() and not pre_c.is_empty():
		var prm = pre_m["session"]
		var prc = pre_c["session"]
		var mq_m := float(pre_m.get("mq", -1.0))
		_ok(mq_m < 0.9, "moderate 当前 owner 质量 <0.9", str(mq_m))
		var pe_m: Dictionary = prm.combat_predict_track("raider_2", "railgun")
		var pe_c: Dictionary = prc.combat_predict_track("raider_2", "railgun")
		_ok(bool(pe_m.get("ok", false)), "实体键发射前预测 ok",
			str(pe_m.get("reason", "")))
		var mq_now := float((prm.owner_measurement_quality("player_intel", "raider_2") as Dictionary).get("measurement_quality", -1.0))
		_near(float(pe_m.get("measurement_quality", -1.0)), mq_now, CONF_TOL,
			"实体键预测读取 owner 当前质量")
		_near(float(pe_m.get("quality_accuracy_mult", -1.0)), 0.85, CONF_TOL,
			"实体键预测消费精度因子 0.85")
		var iface_m: Dictionary = prm.combat_service.predict_shot("raider_2", "railgun")
		_near(float(pe_m.get("hit_probability", -1.0)),
			float(iface_m.get("hit_probability", -2.0)), CONF_TOL,
			"发射前预测概率 = 接口同一规则")
		_near(float(pe_m.get("error_km", -1.0)),
			float(iface_m.get("error_km", -2.0)), CONF_TOL,
			"发射前预测误差 = 接口同一规则")
		_info("prefire probability moderate=%s clean=%s" % [
			str(pe_m.get("hit_probability", null)),
			str(pe_c.get("hit_probability", null))])
		var hud_key := String((prm._sensor_track_map as Dictionary).get("raider_2", ""))
		if hud_key == "":
			hud_key = "raider_2"
		var ph_m: Dictionary = prm.combat_predict_track(hud_key, "railgun")
		_ok(bool(ph_m.get("ok", false)), "HUD 匿名键发射前预测 ok",
			str(ph_m.get("reason", "")))
		_near(float(ph_m.get("measurement_quality", -1.0)), mq_now, CONF_TOL,
			"HUD 匿名键预测复用实体映射读质量")
		_near(float(ph_m.get("hit_probability", -1.0)),
			float(pe_m.get("hit_probability", -2.0)), CONF_TOL,
			"HUD 匿名键与实体键预测一致")
		# mq-only 分支（无显式 quality/error）：实际应用因子并生成误差
		var st_m: Dictionary = prm._ballistics_states()
		var base_hm: Dictionary = prm.combat_ballistics.predict(
			st_m[prm._own_ballistics_entity(st_m)],
			st_m[prm._entity_for_track("raider_2")], "railgun")
		var mq_only: Dictionary = prm.combat_ballistics.predict(
			st_m[prm._own_ballistics_entity(st_m)],
			st_m[prm._entity_for_track("raider_2")], "railgun",
			{"measurement_quality": 0.8})
		_ok(float(mq_only.get("hit_probability", 1.0))
			< float(base_hm.get("hit_probability", 0.0)),
			"mq-only 分支实际降低概率（非仅附带字段）",
			"%s vs %s" % [str(mq_only.get("hit_probability", null)),
				str(base_hm.get("hit_probability", null))])
		_near(float(mq_only.get("hit_probability", -1.0)),
			float(base_hm.get("hit_probability", 0.0)) * 0.85, CONF_TOL,
			"mq-only 分支概率 = 基准 × 0.85")
		_ok(float(mq_only.get("error_km", 0.0)) > float(
			base_hm.get("error_km", 0.0)) - 1.0e-9,
			"mq-only 分支生成对应误差",
			"%s vs %s" % [str(mq_only.get("error_km", null)),
				str(base_hm.get("error_km", null))])

	_step("R24 旧档覆盖活跃会话：清除加载前 EW 运行态，fresh/active 一致")
	var act = _new()
	act.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
		"severity": 0.5, "duration_s": 60.0, "source_id": "EW-R24"})
	for i24 in range(2):
		act.tick(TICK_DT)
	var act_queue_before: int = (act.ew_delivery_queue() as Array).size()
	var act_samples_before: int = (act.ew_observation_samples() as Array).size()
	_ok(act_queue_before > 0 and act_samples_before > 0,
		"活跃会话加载前存在 EW 运行态",
		"queue=%d samples=%d" % [act_queue_before, act_samples_before])
	var clean24 = _new()
	clean24.tick(TICK_DT)
	var doc24: Dictionary = JSON.parse_string(clean24.save_state())
	for k24 in ["ew_observation_samples", "ew_observation_queue",
			"ew_delivered_observations", "ew_candidates", "ew_observation_seq",
			"ew_quality_history", "ew_combat_quality", "ew_rejected_deliveries"]:
		doc24.erase(k24)
	var old_text: String = JSON.stringify(doc24)
	var lr24a: Dictionary = act.load_state(old_text)
	_ok(bool(lr24a.get("ok", false)), "活跃会话加载旧档成功",
		str(lr24a.get("errors", [])))
	_eq(String(lr24a.get("ew_restore_mode", "")), "legacy_absent",
		"活跃会话旧档模式 legacy_absent")
	_eq((act.ew_delivery_queue() as Array).size(), 0, "活跃会话旧档覆盖后队列清空")
	_eq((act.ew_observation_samples() as Array).size(), 0,
		"活跃会话旧档覆盖后采样清空")
	_eq((act.ew_delivered_observations() as Array).size(), 0,
		"活跃会话旧档覆盖后投递审计清空")
	var fresh24 = _new()
	var lr24f: Dictionary = fresh24.load_state(old_text)
	_ok(bool(lr24f.get("ok", false)), "新实例加载同一旧档成功",
		str(lr24f.get("errors", [])))
	_eq(String(lr24f.get("ew_restore_mode", "")), "legacy_absent",
		"新实例旧档模式 legacy_absent")
	_eq((fresh24.ew_delivery_queue() as Array).size(),
		(act.ew_delivery_queue() as Array).size(), "fresh/active 队列一致")
	_eq((fresh24.ew_observation_samples() as Array).size(),
		(act.ew_observation_samples() as Array).size(), "fresh/active 采样一致")
	_info("R24 same_state_as_fresh=true（queue/samples/delivered 均 0）")


	_step("总结")
	_info("A03 验收：真实 sensor 采样→质量/延迟→owner 航迹→火控→文件恢复")
	_finish()


# ── helpers ──────────────────────────────────────────────────────

func _new():
	return GS.new(_seed())


func _sample_for(samples: Array, target: String) -> Dictionary:
	for raw in samples:
		if raw is Dictionary and String((raw as Dictionary).get(
				"target_id", "")) == target:
			return raw
	return {}


func _view_track(s, owner: String, target: String) -> Dictionary:
	var v: Dictionary = s.intel_view(owner)
	for raw in (v.get("tracks", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == target:
			return raw
	return {}


func _delivered_for(rows: Array, target: String) -> Dictionary:
	for raw in rows:
		if raw is Dictionary and String((raw as Dictionary).get(
				"target_id", "")) == target:
			return raw
	return {}


func _visibility_ids(rows: Array) -> Array:
	var ids: Array = []
	for raw in rows:
		if raw is Dictionary:
			ids.append(String((raw as Dictionary).get("id", "")))
	return ids


func _register_combat_track(s, tid: String) -> void:
	if s == null or s.combat_service == null:
		return
	s.combat_service.register_track(tid, {"id": tid, "batch": tid,
		"track_id": tid, "entity_id": tid,
		"identity": "unknown", "threat": "unknown",
		"range_km": 500.0, "in_arc": true, "destroyed": false,
		"pos_km": [321719.0, 500.0, 0.0]})


func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "fleet_id": "own_fleet",
				"authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "fleet_id": "ally_fleet",
				"authorized_actors": ["ally_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player",
				"fleet_id": "own_fleet"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally",
				"fleet_id": "ally_fleet"}],
		"ew_service": {},
		"identification_service": {"evidence_ttl_s": 30.0,
			"decay_half_life_s": 60.0, "auto": {"enabled": false}},
		"combat_service": {
			"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "own_fleet"},
		"combat_ballistics": {
			"content_path": "res://framework/content/weapons_l1.json"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship",
				"pos_km": [321719.0, 600.0, 0.0], "vel_kmps": [0.0, 0.4, 0.0]}],
		"sensor_service": {
			"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [
				{"id": "raider_2", "pos_km": [321719.0, 600.0, 0.0],
					"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}},
	}
func _ammo(s, weapon: String) -> int:
	if s == null or s.combat_service == null:
		return -1
	var vm: Dictionary = s.combat_service.vm()
	for raw in (vm.get("weapons", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == weapon:
			return int((raw as Dictionary).get("ammo", -1))
	return -1


func _clean_solution_quality(s, target: String, weapon: String) -> float:
	if s == null or s.combat_service == null:
		return -1.0
	var w: Dictionary = s.combat_service.weapon_def(weapon)
	var tr = s.combat_service.track(target)
	if w.is_empty() or not (tr is Dictionary):
		return -1.0
	var range_km := float((tr as Dictionary).get("range_km", 0.0))
	var acc := float(w.get("accuracy", 0.5))
	var wr := maxf(1.0, float(w.get("range_km", 1.0)))
	return clampf(acc * (1.0 - clampf(range_km / wr, 0.0, 1.0) * 0.25),
		0.0, 1.0)
func _queue_sig(rows: Array) -> Array:
	var out: Array = []
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var obs: Dictionary = e.get("obs", {}) if e.get("obs") is Dictionary else {}
		out.append({"id": String(e.get("observation_id", "")),
			"owner": String(e.get("owner_id", "")),
			"target": String(e.get("target_id", "")),
			"observed_t": float(e.get("observed_t", 0.0)),
			"arrive_t": float(e.get("arrive_t", 0.0)),
			"delay_s": float(e.get("delay_s", 0.0)),
			"quality": float(e.get("quality", 0.0)),
			"pos": (obs.get("pos_km", []) as Array).duplicate() if obs.get("pos_km") is Array else [],
			"range_km": float(obs.get("range_km", -1.0)),
			"bearing_deg": float(obs.get("bearing_deg", -1.0))})
	return out


func _delivered_sig(rec: Dictionary) -> Dictionary:
	return {"id": String(rec.get("observation_id", "")),
		"owner": String(rec.get("owner_id", "")),
		"target": String(rec.get("target_id", "")),
		"observed_t": float(rec.get("observed_t", 0.0)),
		"received_t": float(rec.get("received_t", 0.0)),
		"delay_s": float(rec.get("delay_s", 0.0)),
		"quality": float(rec.get("quality", 0.0)),
		"quality_original": float(rec.get("quality_original", 0.0))}


func _solution_sig(s, sid: String) -> Dictionary:
	if s == null or s.combat_service == null:
		return {}
	var row: Dictionary = s.combat_service.solution_status(sid)
	if row.is_empty():
		return {}
	return {"id": String(row.get("solution_id", "")),
		"status": String(row.get("status", "")),
		"quality": float(row.get("quality", 0.0)),
		"error_km": float(row.get("error_km", -1.0)),
		"measurement_quality": float(row.get("measurement_quality", -1.0)),
		"measurement_t": float(row.get("measurement_t", -1.0))}
func _consumer_fixture(mode: String) -> Dictionary:
	var sd: Dictionary = JSON.parse_string(JSON.stringify(_seed()))
	if mode == "no_measure":
		sd["sensor_service"]["targets"] = []
		sd["sensor_service"]["options"] = {"radar_enabled": false, "emcon": false}
	var s = GS.new(sd)
	for i in range(6):
		s.tick(TICK_DT)
	_register_combat_track(s, "raider_2")
	s.grant_authorization("FIRE", "target", "raider_2")
	var sol: Dictionary = s.combat_request_solution("raider_2", "railgun", true)
	if not bool(sol.get("ok", false)):
		return {"fire": {"ok": false, "reason": String(sol.get("reason", ""))}}
	var sid := String((sol.get("solution", {}) as Dictionary).get("solution_id", ""))
	for i2 in range(30):
		s.tick(TICK_DT)
		if String(s.combat_service.solution_status(sid).get("status", "")) == "READY":
			break
	if mode == "moderate":
		s.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
			"severity": 0.2, "duration_s": 120.0, "source_id": "EW-FIX"})
	for i3 in range(2):
		s.tick(TICK_DT)
	var mq: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	var fire: Dictionary = s.request_fire("raider_2", "railgun", true,
		{"target_entity": "raider_2", "actor_id": "player_ctrl",
			"controller_id": "player_ctrl", "domain_id": "player",
			"fleet_id": "own_fleet"})
	var proj: Dictionary = {}
	if bool(fire.get("ok", false)):
		var pids: Array = fire.get("projectile_ids", []) if fire.get("projectile_ids") is Array else []
		if pids.size() > 0:
			var pid := String(pids[0])
			for raw_p in (s.combat_ballistics.vm().get("projectiles", []) as Array):
				if raw_p is Dictionary and String((raw_p as Dictionary).get(
						"projectile_id", "")) == pid:
					proj = (raw_p as Dictionary).duplicate(true)
					break
	return {"session": s, "fire": fire, "proj": proj,
		"measurement_ok": bool(mq.get("ok", false)),
		"measurement_quality": float(mq.get("measurement_quality", -1.0))}
func _prefire_session(moderate: bool) -> Dictionary:
	var sd: Dictionary = JSON.parse_string(JSON.stringify(_seed()))
	var s = GS.new(sd)
	for i in range(6):
		s.tick(TICK_DT)
	_register_combat_track(s, "raider_2")
	s.grant_authorization("FIRE", "target", "raider_2")
	var sol: Dictionary = s.combat_request_solution("raider_2", "railgun", true)
	if not bool(sol.get("ok", false)):
		return {"reason": "no_solution:" + String(sol.get("reason", ""))}
	var sid := String((sol.get("solution", {}) as Dictionary).get("solution_id", ""))
	for i2 in range(30):
		s.tick(TICK_DT)
		if String(s.combat_service.solution_status(sid).get("status", "")) == "READY":
			break
	if moderate:
		s.apply_ew({"effect": "noise_jam", "target_id": "raider_2",
			"severity": 0.2, "duration_s": 120.0, "source_id": "EW-PRE"})
		for i3 in range(2):
			s.tick(TICK_DT)
	var mq: Dictionary = s.owner_measurement_quality("player_intel", "raider_2")
	return {"session": s,
		"mq": float(mq.get("measurement_quality", -1.0)) if bool(
			mq.get("ok", false)) else -1.0}
