extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-A01（#58）R1–R6 返修验收探针
#
#   红→绿：显式非法 context（actor/controller/fleet）拒绝且零副作用；
#           配置 bool 不得代替真实逐舰运行态；日志/审计/重放携带同一 context；
#           玩家 HUD contacts/plot 只走 owner 情报 facade（无真值补齐）；
#           共享必须经真实 Comms 投递到达（发出→不可见→到达仅接收方→重投幂等）；
#           真正旧档迁移只进本舰 owner；坏新段明确失败；恢复模式公开可读；
#           隐藏真值钩子必须**实际改变**被测真值，同时玩家视图不变。
#
# Output: `JC-A01 AUTHORITY INTEL PROBE RESULT: PASS=n FAIL=m`; quit 0/1
# ═══════════════════════════════════════════════════════════════════

const GS := preload("res://scripts/core/game_session.gd")
const Binder := preload("res://scripts/ui/shell_binder.gd")
const TICK_DT := 1.0

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-A01 R6 PROBE · 真实授权/消费链/共享到达/恢复")
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(300.0).timeout
	if _finished:
		return
	print("[A01] FAIL watchdog timeout")
	_fail += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("JC-A01 AUTHORITY INTEL PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A01] FAILED: ", f)
		print("JC-A01 AUTHORITY INTEL PROBE FAILED")
	else:
		print("JC-A01 AUTHORITY INTEL PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A01] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A01] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _step(t: String) -> void:
	print("")
	print("[A01] STEP ", t)


func _info(t: String) -> void:
	print("[A01] INFO ", t)


func _is_authority_reason(reason: String) -> bool:
	return reason in ["unknown_shooter", "shooter_not_authorized",
		"direct_command_not_permitted", "shooter_runtime_unavailable",
		"legacy_anchor_unknown", "domain_unknown", "authority_unavailable",
		"actor_not_authorized", "controller_mismatch", "fleet_mismatch",
		"context_domain_mismatch"]


# ── 资源快照（真实库存/弹体/成功事件）──────────────────────────

func _res(s) -> Dictionary:
	var out := {"ammo": -1, "projectiles": -1, "launch_events": -1,
		"tracks_touched": -1}
	if s == null:
		return out
	if s.combat_service != null:
		var vm: Dictionary = s.combat_service.vm()
		var weapons: Array = vm.get("weapons", []) if vm.get("weapons") is Array else []
		for raw in weapons:
			if raw is Dictionary and String((raw as Dictionary).get("id", "")) == "missile":
				out["ammo"] = int((raw as Dictionary).get("ammo", -1))
				break
		if int(out["ammo"]) < 0 and weapons.size() > 0:
			out["ammo"] = int((weapons[0] as Dictionary).get("ammo", -1))
	if s.combat_ballistics != null:
		var vmB: Dictionary = s.combat_ballistics.vm() \
			if s.combat_ballistics.has_method("vm") else {}
		var cnt: Dictionary = vmB.get("counts", {}) \
			if vmB.get("counts") is Dictionary else {}
		out["projectiles"] = int(cnt.get("projectiles", -1))
	# 成功事件：优先统计弹道组件的 launch 事件（bus 可见历史有上限，不能只靠它）
	if s.combat_ballistics != null and s.combat_ballistics.has_method("vm"):
		var n2 := 0
		var vmB2: Dictionary = s.combat_ballistics.vm()
		for raw2 in (vmB2.get("events", []) as Array):
			if raw2 is Dictionary \
					and String((raw2 as Dictionary).get("kind", "")).find("launch") >= 0:
				n2 += 1
		out["launch_events"] = n2
	return out


func _diff_res(before: Dictionary, after: Dictionary) -> Dictionary:
	return {"ammo": int(after.get("ammo", -1)) - int(before.get("ammo", -1)),
		"projectiles": int(after.get("projectiles", -1)) - int(before.get("projectiles", -1)),
		"launch_events": int(after.get("launch_events", -1)) - int(before.get("launch_events", -1))}


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("R1a/R1b 真实发射授权：context 与运行态")
	var s = GS.new(_seed())
	_ok(bool(s.ready), "session ready", str(s.errors))
	if not bool(s.ready):
		_finish()
		return
	_register_target(s, "target_a")
	for i in range(2):
		s.tick(TICK_DT)
	# 正常 TIGHT + 显式 FIRE 授权（审查方的真实正对照口径）
	var gr: Dictionary = s.grant_authorization("FIRE", "target", "target_a")
	_ok(bool(gr.get("ok", false)), "显式 FIRE 授权", str(gr.get("reason", "")))
	# 真实解算：request_solution 后推进若干 tick 至 READY
	var sol: Dictionary = s.combat_service.request_solution("target_a", "missile", true)
	_ok(bool(sol.get("ok", false)), "请求射击解算", str(sol.get("reason", "")))
	for iSol in range(12):
		s.tick(TICK_DT)
	# 正例：合法本舰（无 context）真实发射应成功并耗一弹
	var b0 := _res(s)
	var ok_fire: Dictionary = s.request_fire("target_a", "missile", true,
		{"target_entity": "raider_2"})
	var a0 := _res(s)
	_ok(bool(ok_fire.get("ok", false)), "合法本舰真实发射成功",
		String(ok_fire.get("reason", "")))
	var d0 := _diff_res(b0, a0)
	_eq(int(d0.get("ammo", 0)), -1, "真实发射消耗 1 发弹药")
	_ok(int(d0.get("projectiles", 0)) >= 1, "真实发射产生弹体",
		str(d0.get("projectiles", 0)))
	_ok(int(d0.get("launch_events", 0)) >= 1, "真实发射产生 combat.weapon_launch 事件",
		str(d0.get("launch_events", 0)))
	var ctx0: Dictionary = ok_fire.get("authority_context", {}) if ok_fire.get("authority_context") is Dictionary else {}
	_eq(String(ctx0.get("legacy_context", "")), "own_ship", "结果透出 legacy context")
	_eq(String(ctx0.get("shooter_id", "")), "own_ship", "结果透出 shooter")

	# 负例：显式非法 context（四例）→ 拒绝且零副作用
	var bad_cases: Array = [
		{"label": "actor=opfor_ai", "opts": {"shooter_id": "own_ship",
			"actor_id": "opfor_ai", "target_entity": "raider_2"}},
		{"label": "controller=opfor_ai", "opts": {"shooter_id": "own_ship",
			"controller_id": "opfor_ai", "target_entity": "raider_2"}},
		{"label": "fleet=enemy_fleet", "opts": {"shooter_id": "own_ship",
			"fleet_id": "enemy_fleet", "target_entity": "raider_2"}},
		{"label": "无 shooter 但敌人 actor", "opts": {"actor_id": "opfor_ai",
			"target_entity": "target_a"}},
	]
	for raw in bad_cases:
		var bc: Dictionary = raw
		var bb := _res(s)
		var rf: Dictionary = s.request_fire("target_a", "missile", false,
			(bc.get("opts") as Dictionary).duplicate(true))
		var aa := _res(s)
		var dd := _diff_res(bb, aa)
		_ok(bool(rf.get("ok", true)) == false,
			"非法 context 拒绝: " + String(bc.get("label", "")),
			String(rf.get("reason", "")))
		_ok(_is_authority_reason(String(rf.get("reason", ""))),
			"拒绝原因属授权类: " + String(bc.get("label", "")),
			String(rf.get("reason", "")))
		_ok(int(dd.get("ammo", 0)) == 0 and int(dd.get("projectiles", 0)) == 0 \
			and int(dd.get("launch_events", 0)) == 0,
			"拒绝零副作用: " + String(bc.get("label", "")), str(dd))

	# R1b：第二本方舰即使配置 runtime=true 也不得借旗舰账本
	var s2 = GS.new(_seed())
	_register_target(s2, "target_a")
	for i2 in range(2):
		s2.tick(TICK_DT)
	var b2 := _res(s2)
	var rf2: Dictionary = s2.request_fire("target_a", "missile", false,
		{"shooter_id": "second_own", "target_entity": "raider_2"})
	var a2 := _res(s2)
	_eq(String(rf2.get("reason", "")), "shooter_runtime_unavailable",
		"第二本方舰无真实运行态 → unavailable")
	var d2 := _diff_res(b2, a2)
	_ok(int(d2.get("ammo", 0)) == 0 and int(d2.get("projectiles", 0)) == 0,
		"unavailable 零副作用", str(d2))

	_step("R2 授权 context 进入日志/审计/重放")
	var audit: Array = s.fire_audit()
	_ok(audit.size() >= 5, "审计记录成功与拒绝", str(audit.size()))
	var has_ctx := false
	for raw3 in audit:
		var e: Dictionary = raw3
		if bool(e.get("ok", false)) \
				and String(e.get("actor_id", "")) != "" \
				and String(e.get("controller_id", "")) != "" \
				and String(e.get("fleet_id", "")) != "" \
				and String(e.get("resolved_shooter", "")) == "own_ship":
			has_ctx = true
			break
	_ok(has_ctx, "审计含 actor/controller/fleet/shooter 规范化 context")
	var log_rows: Array = s._log
	var log_ok := false
	for raw4 in log_rows:
		if not (raw4 is Dictionary):
			continue
		var lo: Dictionary = raw4
		if String(lo.get("op", "")) == "request_fire" \
				and String(lo.get("shooter_id", "")) == "own_ship" \
				and lo.has("controller_id") and lo.has("fleet_id") \
				and lo.has("actor_id"):
			log_ok = true
			break
	_ok(log_ok, "操作日志保存同一份 context（重放可用）")

	_step("R3a/R3b 玩家读路径：HUD contacts 与 plot 只走 owner facade")
	var s3 = GS.new(_seed())
	_register_target(s3, "target_a")
	for i3 in range(2):
		s3.tick(TICK_DT)
	# 本舰一条真实观测（facade 直投，本域 owner）
	s3.receive_intel_observation("player_intel", {
		"observation_id": "OBS-1", "observer_id": "own_ship",
		"target_id": "target_a", "sensor": "radar", "source": "radar",
		"observed_t": 2.0, "quality": 0.7, "range_km": 500.0,
		"bearing_deg": 90.0, "pos_km": [321719.0, 500.0, 0.0]})
	var binder = Binder.new()
	binder.session = s3
	binder.refresh()
	var contact_ids: Array = []
	for raw5 in (binder.contacts as Array):
		contact_ids.append(String((raw5 as Dictionary).get("id", "")))
	_ok(contact_ids.size() >= 1, "HUD contacts 来自 owner 情报", str(contact_ids))
	_ok(not ("raider_2" in contact_ids), "隐藏实体不出现在 HUD contacts",
		str(contact_ids))
	# T1：显式合法目标必须有真实 contact 行（不能只断言"非空"就跳过）
	var rows_by_tid: Dictionary = {}
	for raw5b in (binder.contacts as Array):
		if raw5b is Dictionary:
			rows_by_tid[String((raw5b as Dictionary).get("track_id", ""))] = raw5b
	var c_a: Dictionary = rows_by_tid.get("target_a", {}) \
		if rows_by_tid.get("target_a") is Dictionary else {}
	_ok(not c_a.is_empty(), "已观测合法目标 target_a 有 contact 行",
		str(rows_by_tid.keys()))
	if not c_a.is_empty():
		var disp_a := String(c_a.get("display_id", ""))
		_ok(disp_a != "" and disp_a != "target_a",
			"contact 显示 ID 匿名（不回读内部目标名）", disp_a)
		_eq(String(c_a.get("intel_owner_id", "")), "player_intel",
			"contact 归属可信本舰 owner")
		_eq(String(c_a.get("side_source", "")), "intel_view",
			"contact side 来源为 owner 情报")
	var plot: Dictionary = binder.plot_positions()
	var p_ids: Array = []
	for raw6 in (plot.get("positions", []) as Array):
		p_ids.append(String((raw6 as Dictionary).get("id", "")))
	_ok(String(plot.get("source", "")) == "intel",
		"plot 数据源为 intel（不直出物理真值）", String(plot.get("source", "")))
	_ok(not ("raider_2" in p_ids), "隐藏实体不出现在 plot", str(p_ids))
	# 空情报 → 空（不回退真值）
	var s3b = GS.new(_seed())
	binder.session = s3b
	binder.refresh()
	var plot_empty: Dictionary = binder.plot_positions()
	_eq(String(plot_empty.get("source", "")), "intel",
		"空情报 plot 仍为 intel 源（不回退 physics）")
	_eq((plot_empty.get("positions", []) as Array).size(), 0,
		"空情报 plot 为空（不补物理真值）")

	_step("T2 同一已观测目标的隐藏真值变更：真值确实改变、玩家视图暂不跟随、新观测后更新")
	var s4 = GS.new(_seed())
	for i4 in range(2):
		s4.tick(TICK_DT)
	var p0: Array = [321719.0, 600.0, 0.0]
	var p1: Array = [999.0, 1234.0, 77.0]
	# 只观测真实存在的世界/物理实体 raider_2（与被变更目标同一）
	s4.receive_intel_observation("player_intel", {
		"observation_id": "OBS-2", "observer_id": "own_ship",
		"target_id": "raider_2", "sensor": "radar", "source": "radar",
		"observed_t": float(s4.now_s()), "quality": 0.7, "range_km": 600.0,
		"bearing_deg": 90.0, "pos_km": p0})
	var b4 = Binder.new()
	b4.session = s4
	b4.refresh()
	var row4: Dictionary = _contact_by_track(b4.contacts, "raider_2")
	_ok(not row4.is_empty(), "T2: 已观测目标 raider_2 有 contact")
	var plot4a: Dictionary = _plot_by_id(b4.plot_positions(), "raider_2")
	var pos4a: Array = plot4a.get("pos_km", []) if plot4a.get("pos_km") is Array else []
	_ok(_vec_near(pos4a, p0, 1.0e-6), "T2: plot 为已获观测位置", str(pos4a))
	var t4a := float(plot4a.get("observed_t", -1.0))
	# 实际改变**同一目标**的隐藏真值（WorldState + PhysicsWorld 两个面）
	var mut: Dictionary = s4._apply_hidden_truth_mutation("raider_2",
		"hidden_renamed", p1)
	_ok(bool(mut.get("ok", false)), "T2: 隐藏真值变更执行成功")
	_ok(bool(mut.get("truth_changed", false)),
		"T2: 真值变更前后确实改变", JSON.stringify(mut.get("before", {})).substr(0, 120))
	_ok(bool(mut.get("world_changed", false)), "T2: WorldState 面确实改变")
	_ok(bool(mut.get("physics_changed", false)), "T2: PhysicsWorld 面确实改变")
	var ph4: Dictionary = s4.physics_state("raider_2")
	var ph4r: Array = ph4.get("r", []) if ph4.get("r") is Array else []
	_ok(_vec_near(ph4r, p1, 1.0e-6), "T2: physics 就是被变更后的坐标", str(ph4r))
	# 未投递新观测：真实 HUD/plot 仍读旧获准数据
	b4.refresh()
	var row4b: Dictionary = _contact_by_track(b4.contacts, "raider_2")
	var plot4b: Dictionary = _plot_by_id(b4.plot_positions(), "raider_2")
	var pos4b: Array = plot4b.get("pos_km", []) if plot4b.get("pos_km") is Array else []
	_ok(not row4b.is_empty(), "T2: 未获新观测前 contact 仍在")
	_ok(_vec_near(pos4b, p0, 1.0e-6),
		"T2: 隐藏 physics 移动后 plot 不跟随（仍为旧获准数据）", str(pos4b))
	_eq(float(plot4b.get("observed_t", -2.0)), t4a,
		"T2: 未获新观测前采样时间不变")
	# 合法新观测到达 → 同一目标位置/时间更新（防止永远冻结）
	s4.tick(TICK_DT)
	s4.receive_intel_observation("player_intel", {
		"observation_id": "OBS-2B", "observer_id": "own_ship",
		"target_id": "raider_2", "sensor": "radar", "source": "radar",
		"observed_t": float(s4.now_s()), "quality": 0.7,
		"range_km": 3.0, "bearing_deg": 0.0, "pos_km": p1})
	b4.refresh()
	var plot4c: Dictionary = _plot_by_id(b4.plot_positions(), "raider_2")
	var pos4c: Array = plot4c.get("pos_km", []) if plot4c.get("pos_km") is Array else []
	_ok(_vec_near(pos4c, p1, 1.0e-6),
		"T2: 合法新观测后同一目标 plot 确实更新", str(pos4c))
	_ok(float(plot4c.get("observed_t", -1.0)) > t4a,
		"T2: 合法新观测后采样时间已更新", str(plot4c.get("observed_t", null)))

	_step("R4 共享必须经真实 Comms 投递到达、仅接收方融合、重投幂等")
	var s5 = GS.new(_seed())
	for i5 in range(2):
		s5.tick(TICK_DT)
	# 盟军观测（先进入 ally 自己的 owner）
	s5.receive_intel_observation("ally_intel", {
		"observation_id": "OBS-A", "observer_id": "ally_ship",
		"target_id": "target_b", "sensor": "optical", "source": "optical",
		"observed_t": 2.0, "quality": 0.6, "range_km": 800.0,
		"bearing_deg": 45.0})
	_ok((s5.intel_view("ally_intel").get("tracks", []) as Array).size() == 1,
		"ally 自己可见其观测")
	_ok((s5.intel_view("player_intel").get("tracks", []) as Array).size() == 0,
		"共享发出前 player 不可见")
	var share_row := {"observation_id": "OBS-A2", "observer_id": "ally_ship",
		"target_id": "target_b", "sensor": "optical", "source": "optical",
		"observed_t": 2.0, "quality": 0.6, "range_km": 800.0,
		"bearing_deg": 45.0, "share_authorized_by": "ally_intel"}
	var qs: Dictionary = s5.queue_intel_share("ally_ship", "own_ship",
		"player_intel", share_row)
	_ok(bool(qs.get("ok", false)), "共享经 Comms 发出", str(qs.get("reason", "")))
	_ok((s5.intel_view("player_intel").get("tracks", []) as Array).size() == 0,
		"发出后但未到达 → player 仍不可见")
	# 推进到消息到达（延迟 > 0）
	for i6 in range(8):
		s5.tick(TICK_DT)
	var pv5: Dictionary = s5.intel_view("player_intel")
	_ok(("target_b" in _ids(pv5)), "到达后仅接收方融合 target_b",
		str(_ids(pv5)) + " share_result=" + JSON.stringify(
			s5.last_intel_share_result()).substr(0, 220))
	_ok((s5.intel_view("opfor_intel").get("tracks", []) as Array).size() == 0,
		"共享不泄漏给第三方 owner")
	# 重投幂等：同一 delivery 再投一次不重复增长
	var before_obs: int = (s5.intel_view("player_intel").get("observations", []) as Array).size()
	var dup: Dictionary = s5.receive_intel_observation("player_intel", share_row,
		{"delivery_id": String(qs.get("delivery_id", "")),
			"received_t": float(s5.now_s()), "share_authorized_by": "ally_intel",
			"now_t": float(s5.now_s())})
	var after_obs: int = (s5.intel_view("player_intel").get("observations", []) as Array).size()
	_eq(after_obs, before_obs, "重复投递不增长观测流（幂等）")
	_ok(bool(dup.get("duplicated", false)) or bool(dup.get("ok", false)),
		"重复投递返回幂等结果", JSON.stringify(dup).substr(0, 120))
	# 负例：未授权共享（enemy observer 自报 player）、未来时间、时间不一致
	var s6 = GS.new(_seed())
	for i7 in range(2):
		s6.tick(TICK_DT)
	var neg_cases: Array = [
		{"label": "未授权跨 owner 共享", "owner": "player_intel",
			"row": {"observation_id": "X1", "observer_id": "enemy_ship",
				"target_id": "raider_2", "observed_t": 2.0, "quality": 0.5},
			"delivery": {"delivery_id": "D1", "received_t": 2.0,
				"now_t": 2.0, "share_authorized_by": ""}},
		{"label": "未来到达时刻", "owner": "player_intel",
			"row": {"observation_id": "X2", "observer_id": "own_ship",
				"target_id": "target_a", "observed_t": 2.0, "quality": 0.5},
			"delivery": {"delivery_id": "D2", "received_t": 99.0, "now_t": 2.0}},
		{"label": "received<observed", "owner": "player_intel",
			"row": {"observation_id": "X3", "observer_id": "own_ship",
				"target_id": "target_a", "observed_t": 9.0, "quality": 0.5},
			"delivery": {"delivery_id": "D3", "received_t": 1.0, "now_t": 9.0}},
		{"label": "未知 owner", "owner": "ghost_intel",
			"row": {"observation_id": "X4", "observer_id": "own_ship",
				"target_id": "target_a", "observed_t": 2.0},
			"delivery": {"delivery_id": "D4", "received_t": 2.0, "now_t": 2.0}},
	]
	for raw7 in neg_cases:
		var nc: Dictionary = raw7
		var rr: Dictionary = s6.receive_intel_observation(
			String(nc.get("owner", "")), (nc.get("row") as Dictionary),
			(nc.get("delivery") as Dictionary))
		_ok(bool(rr.get("ok", true)) == false,
			"共享负例拒绝: " + String(nc.get("label", "")),
			String(rr.get("reason", "")))

	_step("R5 旧档迁移 / 坏新段 / 公开恢复模式")
	# (a) 坏新段必须明确失败
	var bad_text: String = s3.save_state()
	var bad_doc: Dictionary = JSON.parse_string(bad_text)
	bad_doc["authority_intel"] = "broken"
	var s7 = GS.new(_seed())
	var bad_lr: Dictionary = s7.load_state(JSON.stringify(bad_doc))
	_ok(bool(bad_lr.get("ok", true)) == false, "坏 authority_intel 新段明确失败",
		str(bad_lr.get("errors", [])))
	_eq(String(bad_lr.get("authority_restore_mode", "")), "failed",
		"坏新段恢复模式标记 failed")
	# (b) 真正旧档：先推进到 t>=1 再写观测，逐 tick 断言 ok、并证明源自读成功
	var sL = GS.new(_seed())
	var src_ok := true
	for iL0 in range(2):
		var trL: Dictionary = sL.tick(TICK_DT)
		if not bool(trL.get("ok", false)):
			src_ok = false
	_ok(src_ok, "旧来源会话 tick 均 ok")
	sL.handle_observation({"schema": "sensor_observation.v1",
		"kind": "observation", "event_id": "OBS-L1", "t": float(sL.now_s()),
		"sensor": "radar", "entity_id": "raider_2", "batch": "OCU-07",
		"support": 1, "quality": 0.8, "range_km": 600.0,
		"bearing_deg": 90.0})
	var src_ok2 := true
	for iL in range(2):
		var trL2: Dictionary = sL.tick(TICK_DT)
		if not bool(trL2.get("ok", false)):
			src_ok2 = false
	_ok(src_ok2, "旧来源会话写观测后仍 tick ok")
	var legacy_text: String = sL.save_state()
	var src_self = GS.new(_seed())
	var src_lr: Dictionary = src_self.load_state(legacy_text)
	_ok(bool(src_lr.get("ok", false)), "旧来源存档可被同代码自读",
		str(src_lr.get("errors", [])))
	var legacy_doc: Dictionary = JSON.parse_string(legacy_text)
	legacy_doc.erase("authority_intel")
	(legacy_doc as Dictionary).erase("pending_intel_shares")
	var s8 = GS.new(_seed())
	var leg_lr: Dictionary = s8.load_state(JSON.stringify(legacy_doc))
	_ok(bool(leg_lr.get("ok", false)), "真正旧档可加载",
		str(leg_lr.get("errors", [])))
	_eq(String(leg_lr.get("authority_restore_mode", "")), "legacy_own_ship_only",
		"旧档恢复模式公开为 legacy_own_ship_only")
	var leg_rep: Dictionary = s8.authority_restore_report()
	_eq(String(leg_rep.get("restore_mode", "")), "legacy_own_ship_only",
		"恢复报告可读 restore_mode")
	var leg_player: Array = s8.intel_view("player_intel").get("tracks", []) as Array
	var leg_ally: Array = s8.intel_view("ally_intel").get("tracks", []) as Array
	_ok(leg_player.size() >= 1, "旧航迹迁移到本舰 owner", str(leg_player.size()))
	_ok(leg_ally.size() == 0, "旧航迹不复制给盟军", str(leg_ally.size()))

	_step("R6 真实文件恢复 + 在途共享 + 继续 10 tick")
	var s9 = GS.new(_seed())
	_register_target(s9, "target_a")
	for i8 in range(2):
		s9.tick(TICK_DT)
	s9.receive_intel_observation("player_intel", {
		"observation_id": "OBS-9", "observer_id": "own_ship",
		"target_id": "target_a", "sensor": "radar", "source": "radar",
		"observed_t": 2.0, "quality": 0.7, "range_km": 500.0,
		"bearing_deg": 90.0, "pos_km": [321719.0, 500.0, 0.0]})
	# 在途共享（尚未到达）
	var qs9: Dictionary = s9.queue_intel_share("ally_ship", "own_ship",
		"player_intel", {"observation_id": "OBS-9S", "observer_id": "ally_ship",
			"target_id": "target_b", "sensor": "optical", "source": "optical",
			"observed_t": 2.0, "quality": 0.6, "range_km": 800.0,
			"bearing_deg": 45.0, "share_authorized_by": "ally_intel"})
	_ok(bool(qs9.get("ok", false)), "在途共享已发出", str(qs9.get("reason", "")))
	var path := "user://jc_a01_probe_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s9.save_state())
	f.close()
	var s10 = GS.new(_seed())
	var text10 := FileAccess.get_file_as_string(path)
	var lr10: Dictionary = s10.load_state(text10)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(bool(lr10.get("ok", false)), "真实文件恢复成功", str(lr10.get("errors", [])))
	_eq(JSON.stringify(_sorted_sig(s10.intel_view("player_intel"))),
		JSON.stringify(_sorted_sig(s9.intel_view("player_intel"))),
		"恢复后 player 视图与存档时一致")
	_ok(int(lr10.get("pending_intel_shares", 0)) >= 1,
		"在途共享随档恢复", str(lr10.get("pending_intel_shares", 0)))
	for i9 in range(10):
		s9.tick(TICK_DT)
		s10.tick(TICK_DT)
	var ids10: Array = _ids(s10.intel_view("player_intel"))
	var ids9: Array = _ids(s9.intel_view("player_intel"))
	ids10.sort()
	ids9.sort()
	_eq(JSON.stringify(ids10), JSON.stringify(ids9),
		"继续 10 tick 后 player 航迹集合一致（含在途共享到达）")
	_eq((s10.intel_view("player_intel").get("observations", []) as Array).size(),
		(s9.intel_view("player_intel").get("observations", []) as Array).size(),
		"继续 10 tick 后观测条数一致（在途共享各到达一次）")
	_ok(("target_b" in ids10), "恢复后在途共享确实到达接收方", str(ids10))

	_step("R3 剩余：owner 航迹老化（>30s 标旧，>300s 忘却；新观测刷新）")
	var sA = GS.new(_seed())
	var trA0: Dictionary = sA.tick(TICK_DT)
	_ok(bool(trA0.get("ok", false)), "aging fixture tick ok")
	sA.receive_intel_observation("player_intel", {
		"observation_id": "OBS-AGE", "observer_id": "own_ship",
		"target_id": "target_age", "sensor": "radar", "source": "radar",
		"observed_t": float(sA.now_s()), "quality": 0.8,
		"range_km": 500.0, "bearing_deg": 90.0})
	var vA0: Dictionary = sA.intel_view("player_intel")
	var tA0: Dictionary = _track(vA0, "target_age")
	_ok(not tA0.is_empty(), "aging: fresh track present")
	_eq(bool(tA0.get("stale", false)), false, "aging: fresh track not stale")
	# 推进到 >30s
	var guard := 0
	while float(sA.now_s()) < 32.0 and guard < 64:
		sA.tick(TICK_DT)
		guard += 1
	var tA1: Dictionary = _track(sA.intel_view("player_intel"), "target_age")
	_ok(not tA1.is_empty(), "aging: track retained before forget threshold")
	_ok(bool(tA1.get("stale", false)) == true,
		"aging: track marked stale after stale_after_s", str(tA1.get("age_s", null)))
	# 合法新观测刷新 → 不再 stale
	sA.receive_intel_observation("player_intel", {
		"observation_id": "OBS-AGE-2", "observer_id": "own_ship",
		"target_id": "target_age", "sensor": "radar", "source": "radar",
		"observed_t": float(sA.now_s()), "quality": 0.8,
		"range_km": 500.0, "bearing_deg": 90.0})
	var tA2: Dictionary = _track(sA.intel_view("player_intel"), "target_age")
	_ok(bool(tA2.get("stale", false)) == false,
		"aging: legitimate new observation refreshes the track")
	# 推进到 >300s → 忘却
	var guard2 := 0
	while float(sA.now_s()) < 340.0 and guard2 < 360:
		sA.tick(TICK_DT)
		guard2 += 1
	var tA3: Dictionary = _track(sA.intel_view("player_intel"), "target_age")
	_ok(tA3.is_empty(), "aging: track forgotten after forget_after_s",
		"present=" + str(not tA3.is_empty()))

	_step("R4 剩余：到达前 save/load 的在途共享不得提前可见（逐 tick 对照）")
	var sB = GS.new(_seed())
	for iB in range(2):
		sB.tick(TICK_DT)
	sB.receive_intel_observation("ally_intel", {
		"observation_id": "OBS-B1", "observer_id": "ally_ship",
		"target_id": "target_b", "sensor": "optical", "source": "optical",
		"observed_t": float(sB.now_s()), "quality": 0.6,
		"range_km": 800.0, "bearing_deg": 45.0})
	var qB: Dictionary = sB.queue_intel_share("ally_ship", "own_ship",
		"player_intel", {"observation_id": "OBS-B2", "observer_id": "ally_ship",
			"target_id": "target_b", "sensor": "optical", "source": "optical",
			"observed_t": float(sB.now_s()), "quality": 0.6,
			"range_km": 800.0, "bearing_deg": 45.0,
			"share_authorized_by": "ally_intel"})
	_ok(bool(qB.get("ok", false)), "in-flight share queued before save")
	var pathB := "user://jc_a01_inflight.json"
	var fB := FileAccess.open(pathB, FileAccess.WRITE)
	fB.store_string(sB.save_state())
	fB.close()
	var sB2 = GS.new(_seed())
	var lrB: Dictionary = sB2.load_state(FileAccess.get_file_as_string(pathB))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pathB))
	_ok(bool(lrB.get("ok", false)), "in-flight restore load ok",
		str(lrB.get("errors", [])))
	_ok((sB2.comms_pending() as Array).size() >= 1,
		"Comms in-flight queue restored (not lost->delivered)",
		str((sB2.comms_pending() as Array).size()))
	var vis_ok := true
	var first_visible := -1
	for iC in range(10):
		sB.tick(TICK_DT)
		sB2.tick(TICK_DT)
		var idsB: Array = _ids(sB.intel_view("player_intel"))
		var idsB2: Array = _ids(sB2.intel_view("player_intel"))
		idsB.sort()
		idsB2.sort()
		if JSON.stringify(idsB) != JSON.stringify(idsB2):
			vis_ok = false
		if first_visible < 0 and ("target_b" in idsB2):
			first_visible = iC + 1
	_ok(vis_ok, "in-flight: per-tick visible set equal between continuous and restored")
	_eq(first_visible, 3,
		"in-flight: restored session first sees share at the real ETA tick")
	var obsB: Array = sB.intel_view("player_intel").get("observations", []) as Array
	var obsB2: Array = sB2.intel_view("player_intel").get("observations", []) as Array
	var rtB := -1.0
	var rtB2 := -2.0
	for rawB in obsB:
		if String((rawB as Dictionary).get("observation_id", "")) == "OBS-B2":
			rtB = float((rawB as Dictionary).get("received_t", -1.0))
	for rawB2 in obsB2:
		if String((rawB2 as Dictionary).get("observation_id", "")) == "OBS-B2":
			rtB2 = float((rawB2 as Dictionary).get("received_t", -1.0))
	_ok(absf(rtB - rtB2) <= 1.0e-6,
		"in-flight: received_t identical after restore", "cont=%s rest=%s" % [str(rtB), str(rtB2)])

	_step("总结")
	_info("本探针验证授权/消费链/共享到达/真实文件恢复；不含 AI/逐舰战斗账本")
	_finish()


func _ids(view: Dictionary) -> Array:
	var out: Array = []
	for raw in (view.get("tracks", []) as Array):
		out.append(String((raw as Dictionary).get("id", "")))
	return out


func _view_sig(view: Dictionary) -> Dictionary:
	var out: Dictionary = {"owner": String(view.get("owner_id", "")),
		"tracks": [], "observations": []}
	for raw in (view.get("tracks", []) as Array):
		out["tracks"].append((raw as Dictionary).duplicate(true))
	for raw2 in (view.get("observations", []) as Array):
		out["observations"].append((raw2 as Dictionary).duplicate(true))
	return out


func _register_target(s, tid: String) -> void:
	if s == null or s.combat_service == null:
		return
	s.combat_service.register_track(tid, {
		"id": tid, "position": [321719.0, 500.0, 0.0],
		"pos_km": [321719.0, 500.0, 0.0],
		"velocity": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0],
		"rcs_m2": 100.0, "side": "hostile", "threat": "high",
		"identity": "unknown", "range_km": 500.0, "destroyed": false,
	})


func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "faction": "ueg", "roe": "TIGHT",
				"fleet_id": "own_fleet", "authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "faction": "ueg", "roe": "DEFENSIVE",
				"fleet_id": "ally_fleet", "authorized_actors": ["ally_ai"]},
			{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai",
				"intel_owner_id": "opfor_intel", "faction": "ocu", "roe": "AGGRESSIVE",
				"fleet_id": "enemy_fleet", "authorized_actors": ["opfor_ai"]},
		],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player",
				"fleet_id": "own_fleet", "role": "flag"},
			{"entity_instance_id": "second_own", "domain_id": "player",
				"fleet_id": "own_fleet", "role": "escort"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally",
				"fleet_id": "ally_fleet", "role": "picket"},
			{"entity_instance_id": "enemy_ship", "domain_id": "opfor",
				"fleet_id": "enemy_fleet", "role": "raider"},
		],
		"own_fleet": [
			{"entity_instance_id": "own_ship"},
			{"entity_instance_id": "second_own", "combat_runtime": true},
		],
		"nodes": [{"id": "own_ship"}, {"id": "ally_ship"}, {"id": "enemy_ship"}],
		"links": [
			{"a": "ally_ship", "b": "own_ship", "mode": "LD",
				"latency_s": 3.0, "packet_loss": 0.0},
			{"a": "own_ship", "b": "enemy_ship", "mode": "LD",
				"latency_s": 3.0, "packet_loss": 0.0}],
		"combat_ballistics": {
			"content_path": "res://framework/content/weapons_l1.json"},
		"combat_service": {
			"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "own_fleet"},
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "second_own", "kind": "ship",
				"pos_km": [321719.0, 120.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship",
				"pos_km": [321719.0, 300.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "raider_2", "kind": "ship",
				"pos_km": [321719.0, 600.0, 0.0], "vel_kmps": [0.0, 0.4, 0.0]},
			{"id": "enemy_ship", "kind": "ship",
				"pos_km": [321719.0, 800.0, 0.0], "vel_kmps": [0.0, 0.5, 0.0]}],
		"sensor_service": {
			"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [
				{"id": "target_a", "pos_km": [321719.0, 500.0, 0.0],
					"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"},
				{"id": "target_b", "pos_km": [321719.0, 800.0, 0.0],
					"rcs_m2": 90.0, "side": "hostile", "batch": "OCU-08"}],
			"options": {"radar_enabled": true, "emcon": false}},
	}

func _sorted_sig(view: Dictionary) -> Dictionary:
	var tr: Array = []
	for raw in (view.get("tracks", []) as Array):
		tr.append(JSON.stringify(raw))
	tr.sort()
	var ob: Array = []
	for raw2 in (view.get("observations", []) as Array):
		ob.append(JSON.stringify(raw2))
	ob.sort()
	return {"owner": String(view.get("owner_id", "")), "tracks": tr, "observations": ob}

func _track(view: Dictionary, tid: String) -> Dictionary:
	for raw in (view.get("tracks", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == tid:
			return raw
	return {}

func _contact_by_track(rows: Array, tid: String) -> Dictionary:
	for raw in rows:
		if raw is Dictionary \
				and String((raw as Dictionary).get("track_id", "")) == tid:
			return raw
	return {}


func _plot_by_id(plot: Dictionary, tid: String) -> Dictionary:
	for raw in (plot.get("positions", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == tid:
			return raw
	return {}


func _vec_near(a: Array, b: Array, tol: float) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	return absf(float(a[0]) - float(b[0])) <= tol \
		and absf(float(a[1]) - float(b[1])) <= tol \
		and absf(float(a[2]) - float(b[2])) <= tol
