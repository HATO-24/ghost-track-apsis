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
		_near(float(solv.get("quality", -1.0)), 0.7, CONF_TOL,
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
	for i4 in range(4):
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
	for i5b in range(4):
		sc.tick(TICK_DT)
	var mq5: Dictionary = sc.owner_measurement_quality("player_intel", "raider_2")
	_near(float(mq5.get("measurement_quality", -1.0)), 0.7, CONF_TOL,
		"当前测量质量 = 0.7（受干扰后）")
	_ok(float(mq5.get("aggregate_quality", -1.0)) > 0.7,
		"历史聚合质量保留较高值（与当前测量分开）",
		"agg=" + str(mq5.get("aggregate_quality", null)))
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
	var path := "user://jc_a03_ew_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(se.save_state())
	f.close()
	var sf = _new()
	var lr: Dictionary = sf.load_state(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(bool(lr.get("ok", false)), "真实文件恢复成功", str(lr.get("errors", [])))
	_ok((sf.ew_delivery_queue() as Array).size() > 0, "在途观测队列随档恢复")
	var vis_ok := true
	for i8 in range(10):
		se.tick(TICK_DT)
		sf.tick(TICK_DT)
		var ids_e: Array = _visibility_ids(se.ew_visible_tracks("player_intel"))
		var ids_f: Array = _visibility_ids(sf.ew_visible_tracks("player_intel"))
		ids_e.sort()
		ids_f.sort()
		if JSON.stringify(ids_e) != JSON.stringify(ids_f):
			vis_ok = false
		var qe: float = float(se.owner_measurement_quality("player_intel",
			"raider_2").get("measurement_quality", -1.0))
		var qf: float = float(sf.owner_measurement_quality("player_intel",
			"raider_2").get("measurement_quality", -2.0))
		if absf(qe - qf) > CONF_TOL:
			vis_ok = false
	_ok(vis_ok, "恢复后 10 tick 可见集合/质量与连续运行逐 tick 一致")
	_eq((se.ew_delivery_queue() as Array).size(),
		(sf.ew_delivery_queue() as Array).size(), "恢复后队列长度一致")
	var de: Array = se.ew_delivered_observations()
	var df: Array = sf.ew_delivered_observations()
	_eq(de.size(), df.size(), "恢复后投递数量一致")
	if de.size() == df.size() and df.size() > 0:
		_eq(String((de[de.size() - 1] as Dictionary).get("observation_id", "")),
			String((df[df.size() - 1] as Dictionary).get("observation_id", "")),
			"恢复后末尾观测 ID 一致")

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
