extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# JC-A01（#58）：指挥权限与分方情报隔离
#
# 红例（实现前应失败，作为证据保留）：
#   R1 显式无效 shooter 回退本舰/旗舰发起
#   R2 玩家可见的 plot 直接取物理真值（隐藏敌方真值变化泄漏）
#   R3 无 owner 隔离的情报读入口（三 owner 观测串域）
#
# 正例：自有舰授权、合法本舰旧调用、三 owner 独立观测、共享经链路到达后仅接收方可见
# 负例：未知/敌方/友军 shooter 无资源变化；未实现的本方其他舰返回 unavailable；
#       隐藏目标改名/改坐标但合法观测不变时玩家视图不变；无观测 owner 仍未知
#
# Output: `JC-A01 AUTHORITY INTEL PROBE RESULT: PASS=n FAIL=m`; quit 0/1
# ═══════════════════════════════════════════════════════════════════

const GS := preload("res://scripts/core/game_session.gd")
const TICK_DT := 1.0

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("JC-A01 AUTHORITY/INTEL PROBE · 指挥权限 + 分方情报隔离")
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


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("R1 显式无效 shooter 不得回退本舰")
	var s = GS.new(_seed())
	_ok(bool(s.ready), "session ready", str(s.errors))
	if not bool(s.ready):
		_finish()
		return
	_register_target(s, "target_a")
	var before := _res(s)
	var r1: Dictionary = s.request_fire("target_a", "gun", false,
		{"shooter_id": "ghost_ship", "target_entity": "target_a"})
	_ok(bool(r1.get("ok", true)) == false,
		"R1 未知 shooter 必须拒绝（当前会回退本舰发起）", str(r1.get("reason", "")))
	var after := _res(s)
	_ok(JSON.stringify(before) == JSON.stringify(after),
		"R1 拒绝时资源/弹体不得变化",
		"before=%s after=%s" % [JSON.stringify(before), JSON.stringify(after)])

	_step("R1b 敌方/友军 shooter 直接命令必须拒绝")
	var r1b: Dictionary = s.request_fire("target_a", "gun", false,
		{"shooter_id": "enemy_ship", "target_entity": "target_a"})
	_ok(bool(r1b.get("ok", true)) == false, "敌方 shooter 拒绝",
		str(r1b.get("reason", "")))
	var r1c: Dictionary = s.request_fire("target_a", "gun", false,
		{"shooter_id": "ally_ship", "target_entity": "target_a"})
	_ok(bool(r1c.get("ok", true)) == false, "友军直接命令拒绝",
		str(r1c.get("reason", "")))

	_step("R1d 合法自有舰授权仍可发起（正例）")
	var d1: Dictionary = s.authorize_fire({"shooter_id": "own_ship"})
	_ok(bool(d1.get("ok", false)), "自有舰通过授权门", str(d1.get("reason", "")))
	var r1d: Dictionary = s.request_fire("target_a", "gun", false,
		{"shooter_id": "own_ship", "target_entity": "target_a"})
	_ok(not _is_authority_reason(String(r1d.get("reason", ""))),
		"自有舰发射路径未被授权拒绝", str(r1d.get("reason", "")))

	_step("R1e 合法旧调用（无 shooter）只映射本舰")
	var s2 = GS.new(_seed())
	_register_target(s2, "target_a")
	var lr2: Dictionary = s2.authorize_fire({})
	_ok(bool(lr2.get("ok", false)), "旧调用通过授权门", str(lr2.get("reason", "")))
	_eq(String(lr2.get("shooter_id", "")), "own_ship",
		"旧调用 shooter 固定为本舰（不借其他舰）")
	_eq(String(lr2.get("legacy_context", "")), "own_ship",
		"旧调用记录 legacy context")
	var r1e: Dictionary = s2.request_fire("target_a", "gun", false,
		{"target_entity": "target_a"})
	_ok(not _is_authority_reason(String(r1e.get("reason", ""))),
		"旧调用发射路径未被授权拒绝", str(r1e.get("reason", "")))

	_step("R3 分方情报：三 owner 观测必须隔离")
	var s3 = GS.new(_seed())
	for i in range(6):
		s3.tick(TICK_DT)
	# 链路投递：本舰域观测（direct）
	s3.receive_intel_observation("player_intel", {
		"observation_id": "OBS-1", "observer_id": "own_ship",
		"target_id": "target_a", "sensor": "radar", "source": "radar",
		"observed_t": 6.0, "received_t": 6.0, "delay_s": 0.0,
		"path": "direct", "quality": 0.7, "range_km": 500.0,
		"bearing_deg": 90.0})
	# 盟军自己的观测（只对 ally_intel 可见）
	s3.receive_intel_observation("ally_intel", {
		"observation_id": "OBS-A", "observer_id": "ally_ship",
		"target_id": "target_b", "sensor": "optical", "source": "optical",
		"observed_t": 6.0, "received_t": 36.0, "delay_s": 30.0,
		"path": "direct", "quality": 0.6, "range_km": 800.0,
		"bearing_deg": 45.0})
	_ok(s3.has_method("intel_view"), "存在 owner 隔离读入口 intel_view(owner_id)")
	if s3.has_method("intel_view"):
		var pv: Dictionary = s3.intel_view("player_intel")
		var av: Dictionary = s3.intel_view("ally_intel")
		var ov: Dictionary = s3.intel_view("opfor_intel")
		_ok((pv.get("tracks", []) as Array).size() >= 1, "player owner 有本舰观测航迹",
			str((pv.get("tracks", []) as Array).size()))
		var p_ids: Array = _ids(pv)
		_ok(not ("enemy_ship" in p_ids), "player 视图不因真值含敌方而自动出现",
			str(p_ids))
		_ok(not ("target_b" in p_ids), "player 不因 ally 观测而自动获得 target_b",
			str(p_ids))
		_ok((av.get("tracks", []) as Array).size() == 1,
			"ally 只看到自己的 1 条航迹", str(_ids(av)))
		_ok((ov.get("tracks", []) as Array).size() == 0,
			"opfor 未观测时视图为空", str(_ids(ov)))
		# 共享：ally 观测经授权链路到达 player 后才对 player 可见
		s3.receive_intel_observation("player_intel", {
			"observation_id": "OBS-A2", "observer_id": "ally_ship",
			"target_id": "target_b", "sensor": "optical", "source": "optical",
			"observed_t": 6.0, "received_t": 36.0, "delay_s": 30.0,
			"path": "relay:ally->player", "quality": 0.6,
			"range_km": 800.0, "bearing_deg": 45.0})
		var pv2: Dictionary = s3.intel_view("player_intel")
		_ok(("target_b" in _ids(pv2)),
			"共享观测到达后接收方可见 target_b", str(_ids(pv2)))
		_ok((s3.intel_view("opfor_intel").get("tracks", []) as Array).size() == 0,
			"共享不会泄漏给第三方 owner")

	_step("R2 玩家 plot 不得直出物理真值")
	_ok(s3.has_method("plot_positions"), "存在 owner 限定的 plot_positions(owner_id)")
	if s3.has_method("plot_positions"):
		var plot: Dictionary = s3.plot_positions("player_intel")
		var ids: Array = []
		for raw in (plot.get("positions", []) as Array):
			ids.append(String((raw as Dictionary).get("id", "")))
		_ok(not ("enemy_ship" in ids),
			"隐藏敌方不因物理真值出现在玩家 plot（当前 shell_binder 直取真值）",
			str(ids))
		_ok(String(plot.get("source", "")) != "physics",
			"plot 数据源不得标记为 physics 真值", String(plot.get("source", "")))

	_step("R2b 隐藏目标改名/改坐标但合法观测不变 → 玩家视图不变")
	var s4 = GS.new(_seed())
	for i in range(6):
		s4.tick(TICK_DT)
	_ok(s4.has_method("intel_view"), "intel_view 可用于视图不变性对照")
	if s4.has_method("intel_view"):
		var v_before: Dictionary = s4.intel_view("player_intel")
		_ok(s4.has_method("_apply_hidden_truth_mutation"),
			"存在隐藏真值变更测试钩子（仅测试用）")
		if s4.has_method("_apply_hidden_truth_mutation"):
			s4._apply_hidden_truth_mutation("enemy_ship", "renamed-hidden", [999.0, 0.0, 0.0])
			var v_after: Dictionary = s4.intel_view("player_intel")
			_eq(JSON.stringify(_view_sig(v_after)), JSON.stringify(_view_sig(v_before)),
				"真值变更不影响未观测的玩家视图")

	_step("R4 存档/恢复：owner 航迹与授权 context 一致")
	if s3.has_method("intel_view"):
		var text: String = s3.save_state()
		var s5 = GS.new(_seed())
		var lr: Dictionary = s5.load_state(text)
		_ok(bool(lr.get("ok", false)), "存档恢复成功", str(lr.get("errors", [])))
		if bool(lr.get("ok", false)):
			var v_rec: Dictionary = s5.intel_view("player_intel")
			_eq(JSON.stringify(_view_sig(v_rec)), JSON.stringify(_view_sig(
				s3.intel_view("player_intel"))), "恢复后 player 视图一致")
			for i in range(10):
				s3.tick(TICK_DT)
				s5.tick(TICK_DT)
			_eq(JSON.stringify(_view_sig(s5.intel_view("player_intel"))),
				JSON.stringify(_view_sig(s3.intel_view("player_intel"))),
				"继续 10 tick 后 player 视图一致")

	_step("R5 拒绝审计可记录且不消耗资源")
	_ok(s.has_method("fire_audit"), "存在 fire_audit() 审计入口")
	if s.has_method("fire_audit"):
		var aud: Array = s.fire_audit()
		_ok(aud.size() >= 3, "拒绝/成功均记入审计", str(aud.size()))
		var rejected: Array = []
		for raw in aud:
			if not bool((raw as Dictionary).get("ok", true)):
				rejected.append(raw)
		_ok(rejected.size() >= 3, "拒绝条目带原因",
			str(rejected.size()))

	_step("总结")
	_info("本探针只验证指挥授权与分方情报边界；不实现 AI/逐舰战斗账本")
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


func _res(s) -> Dictionary:
	var ammo := {}
	var cb = s.combat_ballistics
	if cb != null:
		ammo["projectiles"] = (cb.projectiles as Array).size() if cb.get("projectiles") != null else -1
	var ca = s.combat_service
	if ca != null:
		var st: Dictionary = ca.state() if ca.has_method("state") else {}
		ammo["salvo"] = int(st.get("salvo_count", -1))
	return ammo


func _seed() -> Dictionary:
	return {
		"own_entity": "own_ship",
		"physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"command_domains": [
			{"domain_id": "player", "kind": "player", "controller_id": "player_ctrl",
				"intel_owner_id": "player_intel", "faction": "ueg", "roe": "TIGHT",
				"authorized_actors": ["player_ctrl"]},
			{"domain_id": "ally", "kind": "ai_ally", "controller_id": "ally_ai",
				"intel_owner_id": "ally_intel", "faction": "ueg", "roe": "DEFENSIVE",
				"authorized_actors": ["ally_ai"]},
			{"domain_id": "opfor", "kind": "ai_hostile", "controller_id": "opfor_ai",
				"intel_owner_id": "opfor_intel", "faction": "ocu", "roe": "AGGRESSIVE",
				"authorized_actors": ["opfor_ai"]},
		],
		"own_fleet": [{"entity_instance_id": "own_ship", "ship_class_id": "APSIS",
			"combat_runtime": true}],
		"fleet_instances": [
			{"entity_instance_id": "own_ship", "domain_id": "player", "role": "flag"},
			{"entity_instance_id": "ally_ship", "domain_id": "ally", "role": "picket"},
			{"entity_instance_id": "enemy_ship", "domain_id": "opfor", "role": "raider"},
		],
		"entities": [
			{"id": "own_ship", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "ally_ship", "kind": "ship", "pos_km": [321719.0, 300.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "enemy_ship", "kind": "ship", "pos_km": [321719.0, 800.0, 0.0],
				"vel_kmps": [0.0, 0.5, 0.0]}],
		"sensor_service": {
			"observer": {"id": "own_ship", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": [
				{"id": "target_a", "pos_km": [321719.0, 500.0, 0.0],
					"rcs_m2": 100.0, "side": "hostile", "batch": "OCU-07"}],
			"options": {"radar_enabled": true, "emcon": false}},
		"combat_ballistics": {
			"content_path": "res://framework/content/weapons_l1.json"},
		"combat_service": {
			"content_path": "res://framework/content/weapons_l1.json",
			"roe": "TIGHT", "own_id": "own_ship", "fleet_id": "taskforce"},
	}

## 注入一条合法敌方航迹（供 request_fire 使用；不属于被测权限逻辑）。
func _register_target(s, tid: String) -> void:
	if s == null or s.combat_service == null:
		return
	s.combat_service.register_track(tid, {
		"id": tid, "position": [321719.0, 500.0, 0.0],
		"pos_km": [321719.0, 500.0, 0.0],
		"velocity": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0],
		"rcs_m2": 100.0, "side": "hostile", "threat": "high",
		"identity": "unknown",
	})

func _is_authority_reason(reason: String) -> bool:
	return reason in ["unknown_shooter", "shooter_not_authorized",
		"direct_command_not_permitted", "shooter_runtime_unavailable",
		"legacy_anchor_unknown", "domain_unknown", "authority_unavailable"]
