extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-A04 EW COMMS PROBE · #61
# EW 进入真实通信链路：三条真实发送入口（send_comms / issue_order /
# queue_intel_share）都按发送时刻冻结的 comms effect 采样，确定性 draw
# 决定 extra latency/failure；真实 DELIVERED/FAILED 驱动 session/order/
# intel 回调，pending 消失不能冒充 delivered；outcome/state 版本化恢复；
# 读档不重新抽样、真实文件继续 ≥10 tick 一致；旧 v1 迁移、未知版本拒绝。
# ═══════════════════════════════════════════════════════════════════

const GS := preload("res://scripts/core/game_session.gd")
const TICK_DT := 1.0
const WATCHDOG_S := 420.0
const TOL := 1.0e-9
const T_TOL := 1.0e-6

var _pass := 0
var _fail := 0
var _failures: Array = []
var _finished := false

func _initialize() -> void:
	print("[JC-A04] START")
	_run()
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("JC-A04 EW COMMS PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A04] FAILED: ", f)
		quit(1)
	else:
		print("[A04] ALL PASS")
		quit(0)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A04] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (detail: " + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A04] FAIL ", line)

func _eq(actual, expected, label: String, detail := "") -> void:
	_ok(actual == expected, label,
		("%s (actual=%s expected=%s)" % [detail, str(actual), str(expected)]).strip_edges())

func _near(actual: float, expected: float, tol: float, label: String, detail := "") -> void:
	_ok(absf(actual - expected) <= tol, label,
		"%s actual=%.12f expected=%.12f tol=%s" % [detail, actual, expected, str(tol)])

func _step(title: String) -> void:
	print("")
	print("[A04] STEP ", title)

func _info(text: String) -> void:
	print("[A04] INFO ", text)

# ── helpers ───────────────────────────────────────────────────────

	_step("S8 确定性失败/成功臂 + 真实文件恢复 ≥10tick + 下一消息 PRNG 一致")
	var fail_seed := _find_ew_seed(true)
	var ok_seed := _find_ew_seed(false)
	_ok(fail_seed >= 0, "找到确定性失败 seed", str(fail_seed))
	_ok(ok_seed >= 0, "找到确定性成功 seed", str(ok_seed))
	if fail_seed >= 0:
		_restore_arm(fail_seed, true)
	if ok_seed >= 0:
		_restore_arm(ok_seed, false)

	_step("S9 篡改与旧残留：篡改 EW 字段拒绝、legacy 残留不冒充 delivered、发送端 EW 生效")
	var t9 = _new()
	_apply_jam(t9, "ally_ship", 0.5)
	var s9: Dictionary = t9.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
	var text9: String = t9.save_state()
	var doc9: Dictionary = JSON.parse_string(text9)
	# 篡改 outcome.ew.draw（重放应按发送时冻结值检测 divergence）
	var tam: Dictionary = doc9.duplicate(true)
	for raw_op in (tam.get("log", []) as Array):
		if raw_op is Dictionary and String((raw_op as Dictionary).get("op", "")) == "send_comms":
			var oc = (raw_op as Dictionary).get("outcome", null)
			if oc is Dictionary and (oc as Dictionary).get("ew") is Dictionary:
				((oc as Dictionary).get("ew") as Dictionary)["draw"] = 0.77
	var t9b = _new()
	var lr9: Dictionary = t9b.load_state(JSON.stringify(tam))
	_ok(bool(lr9.get("ok", true)) == false, "篡改 outcome.ew.draw 被拒绝")
	_ok(JSON.stringify(lr9.get("errors", [])).contains("comms_replay_diverged"),
		"篡改 EW outcome 报 replay divergence", JSON.stringify(lr9.get("errors", [])))
	# 篡改在途 pending.ew.draw（冻结结果一致性）
	var tam2: Dictionary = doc9.duplicate(true)
	var pend9 = (tam2.get("comms", {}) as Dictionary).get("pending", []) \
		if tam2.get("comms") is Dictionary else []
	if pend9 is Array and (pend9 as Array).size() > 0:
		var p0: Dictionary = (pend9 as Array)[0]
		if p0.get("ew") is Dictionary:
			((p0 as Dictionary).get("ew") as Dictionary)["draw"] = 0.01
	var t9c = _new()
	var lr9c: Dictionary = t9c.load_state(JSON.stringify(tam2))
	_ok(bool(lr9c.get("ok", true)) == false, "篡改 pending.ew.draw 被拒绝")
	_ok(JSON.stringify(lr9c.get("errors", [])).contains("pending.ew"),
		"篡改在途 EW 字段原因明确", JSON.stringify(lr9c.get("errors", [])))
	# 旧残留 standalone：无真实结果时不得发布假 delivered
	var t9d = _new()
	t9d._standalone["C-LEGACY"] = {"from": "own_ship", "to": "ally_ship",
		"mode": "LD", "text_key": "COMMS_SENT", "sent_t": 0.0}
	var ev9: Array = _advance(t9d, 2.0)
	var types9: Array = []
	for raw_ev in _comms_events(ev9):
		types9.append(String((raw_ev as Dictionary).get("type", "")))
	_ok("comms.unknown_outcome" in types9, "旧残留显式 unknown_outcome", str(types9))
	_ok(not ("comms.delivered" in types9), "旧残留不冒充 delivered")
	# 发送端 EW 也生效（链路两端都采样）
	var t9e = _new()
	_apply_jam(t9e, "own_ship", 0.5)
	var se9: Dictionary = t9e.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	var ewe9: Dictionary = _ew_of(se9)
	_near(float(ewe9.get("jam_severity", -1.0)), 0.5, TOL, "发送端 EW 采样 jam=.5")
	_near(float(se9.get("latency_ew_add_s", -1.0)), 20.0, T_TOL, "发送端 EW 附加 20s")

func _new(seed_override := {}) -> Variant:
	var sd: Dictionary = _seed()
	for k in seed_override.keys():
		sd[k] = seed_override[k]
	return GS.new(sd)

func _seed(with_ew := true) -> Dictionary:
	var sd := {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "fleet_id": "own_fleet",
				"authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "fleet_id": "ally_fleet",
				"authorized_actors": ["ally_ai"]},
			{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai",
				"intel_owner_id": "opfor_intel", "fleet_id": "enemy_fleet",
				"authorized_actors": ["opfor_ai"]}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player",
				"fleet_id": "own_fleet"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally",
				"fleet_id": "ally_fleet"},
			{"entity_instance_id": "enemy_ship", "domain_id": "opfor",
				"fleet_id": "enemy_fleet"}],
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [0.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship", "pos_km": [100.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "enemy_ship", "kind": "ship", "pos_km": [400.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]}],
		"nodes": [{"id": "own_ship", "name": "OWN"},
			{"id": "ally_ship", "name": "ALLY"},
			{"id": "enemy_ship", "name": "OPFOR"}],
		"links": [
			{"a": "own_ship", "b": "ally_ship", "mode": "LD", "latency_s": 2.0},
			{"a": "own_ship", "b": "enemy_ship", "mode": "LD", "latency_s": 2.0}],
		"identification_service": {"auto": {"enabled": false}},
	}
	if with_ew:
		sd["ew_service"] = {}
	return sd

func _events(s, dt := TICK_DT) -> Array:
	var r: Dictionary = s.tick(dt)
	var out: Array = []
	for raw in (r.get("events", []) as Array):
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out

func _comms_events(events: Array) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and String((raw as Dictionary).get("type", "")).begins_with("comms."):
			out.append(raw)
	return out

func _delivered_ids(events: Array) -> Array:
	var out: Array = []
	for raw in _comms_events(events):
		if String((raw as Dictionary).get("type", "")) == "comms.delivered":
			var pl: Dictionary = (raw as Dictionary).get("payload", {}) \
				if (raw as Dictionary).get("payload") is Dictionary else {}
			out.append(String(pl.get("delivery_id", "")))
	return out

func _failed_events(events: Array) -> Array:
	var out: Array = []
	for raw in _comms_events(events):
		if String((raw as Dictionary).get("type", "")) == "comms.failed":
			out.append(raw)
	return out

func _advance(s, seconds: float) -> Array:
	var evs: Array = []
	var n := int(round(seconds / TICK_DT))
	for i in range(n):
		evs.append_array(_events(s))
	return evs

func _ew_of(res: Dictionary) -> Dictionary:
	return (res.get("ew", {}) as Dictionary) if res.get("ew") is Dictionary else {}

func _force_draw(s, x: float) -> void:
	if s != null and s.has_method("comms_debug_force_draw"):
		s.comms_debug_force_draw(x)

func _ew_state(s) -> Dictionary:
	if s != null and s.has_method("comms_ew_state"):
		return s.comms_ew_state()
	return {}

func _comms_state(s) -> Dictionary:
	if s == null or s.comms == null:
		return {}
	return s.comms.export_state()

func _log_ops(s) -> Array:
	var text: String = s.save_state()
	var doc = JSON.parse_string(text)
	if not (doc is Dictionary):
		return []
	return (doc.get("log", []) as Array) if doc.get("log") is Array else []

func _send_ops(s) -> Array:
	var out: Array = []
	for raw in _log_ops(s):
		if raw is Dictionary and String((raw as Dictionary).get("op", "")) == "send_comms":
			out.append(raw)
	return out

func _apply_jam(s, target := "ally_ship", sev := 0.5) -> Dictionary:
	return s.apply_ew({"effect": "comms_jam", "target_id": target,
		"severity": sev, "duration_s": 120.0, "source_id": "EW-A04"})

# ── run ───────────────────────────────────────────────────────────

func _run() -> void:
	_step("S1 EW=0 保持旧路由：发送/到达/成功只一次")
	var s1 = _new()
	_ok(s1 != null and bool(s1.ready), "EW=0 session 就绪", str(s1.errors if s1 != null else []))
	if s1 == null:
		return
	var r1: Dictionary = s1.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
	_ok(bool(r1.get("ok", false)), "EW=0 LD 发送成功", str(r1.get("reason", "")))
	var ew1: Dictionary = _ew_of(r1)
	_near(float(ew1.get("jam_severity", 0.0)), 0.0, TOL, "EW=0 jam_severity=0")
	_near(float(ew1.get("latency_add_s", 0.0)), 0.0, TOL, "EW=0 latency_add_s=0")
	_near(float(ew1.get("failure_chance", 0.0)), 0.0, TOL, "EW=0 failure_chance=0")
	_ok(bool(ew1.get("will_fail", true)) == false, "EW=0 不因 EW 失败")
	_near(float(r1.get("latency_base_s", -1.0)), 2.0, T_TOL, "EW=0 基础时延=2s")
	_near(float(r1.get("latency_ew_add_s", -1.0)), 0.0, T_TOL, "EW=0 EW 附加=0")
	_near(float(r1.get("latency_s", -1.0)), 2.0, T_TOL, "EW=0 总时延=2s")
	_near(float(r1.get("arrive_t", -1.0)), 2.0, T_TOL, "EW=0 arrive_t=2")
	_eq((s1.comms.pending as Array).size(), 1, "EW=0 在途 1")
	var did1 := String(r1.get("delivery_id", ""))
	var ev1: Array = _advance(s1, 1.0)
	_eq(_delivered_ids(ev1).size(), 0, "到达前无 delivered")
	_eq((s1.comms.pending as Array).size(), 1, "到达前仍在途")
	ev1.append_array(_advance(s1, 1.0))
	var dels1: Array = _delivered_ids(ev1)
	_eq(dels1.size(), 1, "恰好到达 tick 投递一次")
	_eq(String(dels1[0]) if dels1.size() > 0 else "", did1, "delivered id 一致")
	_eq((s1.comms.pending as Array).size(), 0, "到达后清空")
	_advance(s1, 3.0)
	_eq((s1.comms.pending as Array).size(), 0, "后续 tick 不重复投递")
	_eq(_send_ops(s1).size(), 1, "EW=0 记录 1 次真实 send")

	_step("S2 固定 fixture：jam=.5 → extra=20s / failure=.4；draw 两边界")
	var s2 = _new()
	var ap: Dictionary = _apply_jam(s2, "ally_ship", 0.5)
	_ok(bool(ap.get("ok", false)), "应用 comms_jam=.5", str(ap.get("reason", "")))
	_force_draw(s2, 0.1)
	var fail_send: Dictionary = s2.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	var ewf: Dictionary = _ew_of(fail_send)
	_near(float(ewf.get("jam_severity", -1.0)), 0.5, TOL, "采样 jam_severity=.5")
	_near(float(ewf.get("latency_add_s", -1.0)), 20.0, T_TOL, "采样 extra_latency=20s")
	_near(float(ewf.get("failure_chance", -1.0)), 0.4, TOL, "采样 failure_chance=.4")
	_near(float(ewf.get("draw", -1.0)), 0.1, T_TOL, "冻结 draw=.1")
	_eq(bool(ewf.get("will_fail", false)), true, "draw<.4 → 预定失败")
	_near(float(fail_send.get("latency_s", -1.0)), 22.0, T_TOL, "总时延=2+20")
	_near(float(fail_send.get("latency_ew_add_s", -1.0)), 20.0, T_TOL, "EW 附加=20")
	_near(float(fail_send.get("arrive_t", -1.0)), 22.0, T_TOL, "arrive_t=22")
	var ev_fail: Array = _advance(s2, 21.0)
	_eq(_failed_events(ev_fail).size(), 0, "到达前无失败")
	_eq((s2.comms.pending as Array).size(), 1, "失败预定仍在途")
	ev_fail.append_array(_advance(s2, 1.0))
	var fails2: Array = _failed_events(ev_fail)
	_eq(fails2.size(), 1, "到达 tick 产生 FAILED 一次")
	var fpl: Dictionary = {}
	if fails2.size() > 0:
		fpl = (fails2[0] as Dictionary).get("payload", {}) \
			if (fails2[0] as Dictionary).get("payload") is Dictionary else {}
	_eq(String(fpl.get("reason", "")), "comms_jam", "FAILED 原因为 comms_jam")
	_eq(_delivered_ids(ev_fail).size(), 0, "EW 失败不产生假 delivered")
	_eq((s2.comms.pending as Array).size(), 0, "失败后清空在途")
	_force_draw(s2, 0.9)
	var ok_send: Dictionary = s2.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	var ewo: Dictionary = _ew_of(ok_send)
	_near(float(ewo.get("draw", -1.0)), 0.9, T_TOL, "冻结 draw=.9")
	_eq(bool(ewo.get("will_fail", true)), false, "draw>.4 → 预定成功")
	var ev_ok: Array = _advance(s2, 23.0)
	_eq(_failed_events(ev_ok).size(), 0, "成功臂无 FAILED")
	_eq(_delivered_ids(ev_ok).size(), 1, "成功臂 DELIVERED 一次")
	_near(float(ok_send.get("arrive_t", -1.0)) - float(ok_send.get("sent_t", 0.0)),
		22.0, T_TOL, "成功臂同样 +20s（相对 sent_t）")

	_step("S3 三条真实入口都消费 EW：send_comms / issue_order / queue_intel_share")
	var s3 = _new()
	_apply_jam(s3, "ally_ship", 0.5)
	_force_draw(s3, 0.1)
	var rc: Dictionary = s3.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	var c_ev: Array = _advance(s3, 25.0)
	_eq(_failed_events(c_ev).size(), 1, "send_comms 真实失败回调")
	_eq(_delivered_ids(c_ev).size(), 0, "send_comms 失败不冒充送达")
	# 订单入口（OrderService.issue → comms.send → 实际 FAILED 回调）
	_force_draw(s3, 0.1)
	var oi: Dictionary = s3.issue_order("hold", "own_ship", ["ally_ship"], {},
		{"mode": "LD"})
	var oi_ok := bool(oi.get("ok", false))
	var oid := ""
	if oi_ok:
		var oo: Dictionary = oi.get("order", {}) if oi.get("order") is Dictionary else {}
		oid = String(oo.get("order_id", oi.get("order_id", "")))
	var o_ev: Array = _advance(s3, 25.0)
	var order_state := ""
	if oid != "" and s3.orders != null:
		var od = s3.orders.orders.get(oid, null)
		if od is Dictionary:
			order_state = String((od as Dictionary).get("status", ""))
	_ok(oi_ok, "订单真实发送成功入链", str(oi.get("reason", "")))
	_eq(order_state, "REJECTED", "EW 失败订单 REJECTED 而非 DELIVERED")
	var o_reason := ""
	if oid != "" and s3.orders != null:
		var od2 = s3.orders.orders.get(oid, null)
		if od2 is Dictionary:
			o_reason = String((od2 as Dictionary).get("reason", ""))
	_ok(o_reason.begins_with("comms_"), "订单失败原因来自 comms", o_reason)
	# 情报共享入口：失败不融合
	_force_draw(s3, 0.1)
	var share_row := {"observer_id": "own_ship", "target_id": "enemy_ship",
		"sensor": "radar", "observed_t": 0.0, "received_t": 0.0,
		"quality": 1.0, "range_km": 400.0, "bearing_deg": 0.0,
		"share_authorized_by": "player_ctrl"}
	var before_obs: int = 0
	if s3.authority_intel != null:
		before_obs = (s3.authority_intel.intel_view("ally_intel").get(
			"observations", []) as Array).size()
	var sh_bad: Dictionary = s3.queue_intel_share("own_ship", "ally_ship",
		"ally_intel", share_row)
	var sh_ev: Array = _advance(s3, 25.0)
	var after_obs_bad: int = 0
	if s3.authority_intel != null:
		after_obs_bad = (s3.authority_intel.intel_view("ally_intel").get(
			"observations", []) as Array).size()
	_eq(after_obs_bad, before_obs, "共享失败不融合到接收 owner")
	_eq((s3._pending_intel_shares as Dictionary).size(), 0, "共享失败清除待融合")
	# 成功臂：成功共享到达后融合一次
	_force_draw(s3, 0.9)
	var sh_ok: Dictionary = s3.queue_intel_share("own_ship", "ally_ship",
		"ally_intel", share_row)
	var sh_ok_ev: Array = _advance(s3, 25.0)
	var after_obs_ok: int = 0
	if s3.authority_intel != null:
		after_obs_ok = (s3.authority_intel.intel_view("ally_intel").get(
			"observations", []) as Array).size()
	_ok(bool(sh_ok.get("ok", false)), "共享成功入链", str(sh_ok.get("reason", "")))
	_ok(_delivered_ids(sh_ok_ev).size() >= 1, "共享成功产生真实 delivered")
	_eq((s3._pending_intel_shares as Dictionary).size(), 0, "共享成功清除待融合")
	_info("share success obs before/after=%d/%d（A01 负责融合授权语义）" % [
		before_obs, after_obs_ok])

	_step("S4 同 seed 确定性与真实文件恢复：读档不重新抽样")
	var a4 = _new()
	var b4 = _new()
	_apply_jam(a4, "ally_ship", 0.5)
	_apply_jam(b4, "ally_ship", 0.5)
	var sa: Dictionary = a4.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	var sb: Dictionary = b4.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	_near(float(_ew_of(sa).get("draw", -1.0)), float(_ew_of(sb).get("draw", -2.0)),
		T_TOL, "同 seed 首条消息 draw 相同")
	_eq(bool(_ew_of(sa).get("will_fail", false)),
		bool(_ew_of(sb).get("will_fail", true)), "同 seed 失败判定相同")
	# 真实文件保存/恢复：待到达消息失败结果不因读档改变
	var a5 = _new()
	_apply_jam(a5, "ally_ship", 0.5)
	var pend: Dictionary = a5.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	var path := "user://jc_a04_ew_comms.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(a5.save_state())
	f.close()
	var b5 = _new()
	var lr5: Dictionary = b5.load_state(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(bool(lr5.get("ok", false)), "真实文件恢复成功", str(lr5.get("errors", [])))
	_eq((b5.comms.pending as Array).size(), 1, "恢复保留在途 1")
	var ev_cont: Array = _advance(a5, 24.0)
	var ev_rest: Array = _advance(b5, 24.0)
	_eq(_failed_events(ev_rest).size(), _failed_events(ev_cont).size(),
		"恢复后失败回调数量一致")
	_eq(_delivered_ids(ev_rest).size(), _delivered_ids(ev_cont).size(),
		"恢复后成功回调数量一致")
	var will_fail5 := bool(_ew_of(pend).get("will_fail", false))
	if will_fail5:
		_eq(_delivered_ids(ev_rest).size(), 0, "预定失败恢复后不产生 delivered")
	else:
		_eq(_delivered_ids(ev_rest).size(), 1, "预定成功恢复后只 delivered 一次")
	# 恢复后下一条新消息的 PRNG 与连续运行一致
	var next_a: Dictionary = a5.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	var next_b: Dictionary = b5.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	_near(float(_ew_of(next_a).get("draw", -1.0)), float(_ew_of(next_b).get("draw", -2.0)),
		T_TOL, "恢复后后续 PRNG draw 一致")
	_eq(int(_ew_state(a5).get("seq", -1)), int(_ew_state(b5).get("seq", -2)),
		"恢复后 EW 抽样序号一致")

	_step("S5 版本化：outcome v2 / v1 迁移 / 未知版本拒绝 / state v2 迁移")
	var s6 = _new()
	s6.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
	var ops6: Array = _send_ops(s6)
	_ok(ops6.size() > 0, "存在 send_comms 日志操作")
	var oc6: Dictionary = {}
	if ops6.size() > 0:
		oc6 = (ops6[0] as Dictionary).get("outcome", {}) \
			if (ops6[0] as Dictionary).get("outcome") is Dictionary else {}
	_eq(int(oc6.get("version", -1)), 2, "outcome 版本 v2")
	_ok(oc6.get("ew") is Dictionary, "outcome 带 EW 采样块")
	var st6: Dictionary = _comms_state(s6)
	_eq(int(st6.get("version", -1)), 2, "comms state 版本 v2")
	_ok(st6.get("ew_rng") is Dictionary, "state 带确定抽样状态")
	# v1 迁移：构造真实旧档（outcome v1 无 EW，state v1 无 EW）
	var text6: String = s6.save_state()
	var doc6: Dictionary = JSON.parse_string(text6)
	var mig: Dictionary = doc6.duplicate(true)
	for row in (mig.get("log", []) as Array):
		if row is Dictionary and String((row as Dictionary).get("op", "")) == "send_comms":
			var old_out: Dictionary = {"schema": "v17.comms_outcome.v1",
				"version": 1, "ok": true, "reason": "", "mode": "LD",
				"delivery_id": "C-000001", "path": ["own_ship", "ally_ship"],
				"latency_s": 2.0, "relay_count": 0, "arrive_t": 2.0,
				"sent_t": 0.0}
			(row as Dictionary)["outcome"] = old_out
	if mig.get("comms") is Dictionary:
		(mig.get("comms") as Dictionary)["version"] = 1
		(mig.get("comms") as Dictionary).erase("ew_rng")
	var s6b = _new()
	var lr6: Dictionary = s6b.load_state(JSON.stringify(mig))
	_ok(bool(lr6.get("ok", false)), "v1 outcome/state 旧档可恢复",
		str(lr6.get("errors", [])))
	var rep6: Dictionary = s6b.comms_restore_report() if s6b.has_method(
		"comms_restore_report") else {}
	_ok(int(rep6.get("legacy_outcome_v1", 0)) >= 1, "报告标记 legacy_outcome_v1",
		str(rep6.get("legacy_outcome_v1", null)))
	# 未知版本拒绝
	var bad6: Dictionary = doc6.duplicate(true)
	for row2 in (bad6.get("log", []) as Array):
		if row2 is Dictionary and String((row2 as Dictionary).get("op", "")) == "send_comms":
			var oo2: Dictionary = (row2 as Dictionary).get("outcome", {}) \
				if (row2 as Dictionary).get("outcome") is Dictionary else {}
			oo2["version"] = 99
			(row2 as Dictionary)["outcome"] = oo2
	var s6c = _new()
	var lr6c: Dictionary = s6c.load_state(JSON.stringify(bad6))
	_ok(bool(lr6c.get("ok", true)) == false, "未知 outcome version 拒绝")
	var err6c: String = JSON.stringify(lr6c.get("errors", []))
	_ok(err6c.contains("comms_outcome_invalid"), "未知版本原因 comms_outcome_invalid", err6c)
	var bad_state: Dictionary = doc6.duplicate(true)
	if bad_state.get("comms") is Dictionary:
		(bad_state.get("comms") as Dictionary)["version"] = 99
	var s6d = _new()
	var lr6d: Dictionary = s6d.load_state(JSON.stringify(bad_state))
	_ok(bool(lr6d.get("ok", true)) == false, "未知 comms state version 拒绝")

	_step("S6 原失败原因/鉴权边界不因 EW 接线被绕过")
	var s7 = _new()
	var nr: Dictionary = s7.send_comms("own_ship", "ally_ship", "LR", "COMMS_SENT", {}, {})
	_eq(String(nr.get("reason", "")), "no_route", "无 LR 链路保持 no_route")
	var im: Dictionary = s7.send_comms("own_ship", "ally_ship", "QQ", "COMMS_SENT", {}, {})
	_eq(String(im.get("reason", "")), "invalid_mode", "未知模式保持 invalid_mode")
	var ut: Dictionary = s7.send_comms("own_ship", "ghost", "LD", "COMMS_SENT", {}, {})
	_eq(String(ut.get("reason", "")), "unknown_to", "未知目标保持 unknown_to")
	s7.comms.set_link_enabled("own_ship", "ally_ship", false)
	var dis: Dictionary = s7.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
	_ok(bool(dis.get("ok", true)) == false, "禁用链路发送失败")
	_ok(String(dis.get("reason", "")) in ["no_route", "link_disabled"],
		"禁用链路原因明确", str(dis.get("reason", "")))
	s7.comms.set_link_enabled("own_ship", "ally_ship", true)
	var forge: Dictionary = s7.issue_order("hold", "ghost_issuer", ["ally_ship"], {},
		{"mode": "LD"})
	_ok(bool(forge.get("ok", true)) == false, "非法 sender 订单被拒", str(forge.get("reason", "")))
	_ok(String(forge.get("reason", "")).contains("unknown_from"),
		"非法 sender 有明确 comms 原因", str(forge.get("reason", "")))

	_step("S7 EW=0 旧 seed（无 ew_service）兼容")
	var s8 = _new({"ew_service": null})
	_ok(bool(s8.ready), "无 ew_service 旧 seed 可启动", str(s8.errors))
	var n8: Dictionary = s8.send_comms("own_ship", "ally_ship", "LD", "COMMS_SENT", {}, {})
	_ok(bool(n8.get("ok", false)), "旧 seed 正常发送", str(n8.get("reason", "")))
	var ew8: Dictionary = _ew_of(n8)
	_near(float(ew8.get("jam_severity", -1.0)), 0.0, TOL, "旧 seed jam=0")
	_near(float(n8.get("latency_s", -1.0)), 2.0, T_TOL, "旧 seed 总时延=基础 2s")
	var ev8: Array = _advance(s8, 3.0)
	_eq(_delivered_ids(ev8).size(), 1, "旧 seed 正常投递一次")
func _find_ew_seed(want_fail: bool) -> int:
	for k in range(0, 120):
		var s = _new({"comms_ew_seed": k})
		_apply_jam(s, "ally_ship", 0.5)
		var r: Dictionary = s.send_comms("own_ship", "ally_ship", "LD",
			"COMMS_SENT", {}, {})
		var wf := bool(_ew_of(r).get("will_fail", false))
		if wf == want_fail:
			return k
	return -1


func _restore_arm(seed_k: int, want_fail: bool) -> void:
	var a = _new({"comms_ew_seed": seed_k})
	_apply_jam(a, "ally_ship", 0.5)
	var sent: Dictionary = a.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	_eq(bool(_ew_of(sent).get("will_fail", not want_fail)), want_fail,
		"确定性臂 %s 发送时冻结 will_fail" % ("fail" if want_fail else "ok"))
	var save_text: String = a.save_state()
	var b = _new({"comms_ew_seed": seed_k})
	var lr: Dictionary = b.load_state(save_text)
	_ok(bool(lr.get("ok", false)), "确定性臂恢复成功",
		str(lr.get("errors", [])))
	var ev_a: Array = _advance(a, 24.0)
	var ev_b: Array = _advance(b, 24.0)
	if want_fail:
		_eq(_failed_events(ev_b).size(), 1, "恢复后失败恰好一次")
		_eq(_delivered_ids(ev_b).size(), 0, "失败臂恢复后无 delivered")
		var freason := ""
		for raw_f in _failed_events(ev_b):
			var plf: Dictionary = (raw_f as Dictionary).get("payload", {}) \
				if (raw_f as Dictionary).get("payload") is Dictionary else {}
			freason = String(plf.get("reason", ""))
		_eq(freason, "comms_jam", "恢复后失败原因保持 comms_jam")
	else:
		_eq(_delivered_ids(ev_b).size(), 1, "恢复后成功恰好一次")
		_eq(_failed_events(ev_b).size(), 0, "成功臂恢复后无 failed")
	_eq(_failed_events(ev_b).size(), _failed_events(ev_a).size(),
		"连续/恢复失败数一致")
	_eq(_delivered_ids(ev_b).size(), _delivered_ids(ev_a).size(),
		"连续/恢复送达数一致")
	# 下一消息 PRNG 与连续运行一致
	var na: Dictionary = a.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	var nb: Dictionary = b.send_comms("own_ship", "ally_ship", "LD",
		"COMMS_SENT", {}, {})
	_near(float(_ew_of(na).get("draw", -1.0)), float(_ew_of(nb).get("draw", -2.0)),
		T_TOL, "恢复后下一消息 draw 一致")
	_eq(int(_ew_state(a).get("seq", -1)), int(_ew_state(b).get("seq", -2)),
		"恢复后下一消息抽样序号一致")