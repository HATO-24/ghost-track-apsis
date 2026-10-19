extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# V2-CORE-3 systems probe（教学门控 / 损管 / 回放 / 执行窗口 / 声望 / 站体储罐）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v16" --script res://tests/systems_probe.gd
#
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const SCENARIO := "res://content/scenario_l1_v2.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("V2-CORE-3 SYSTEMS PROBE · 教学/损管/回放/执行窗口/声望/站体")
	print("════════════════════════════════════════════════════════════")
	_test_station_tank()
	_test_tutorial()
	_test_damage()
	_test_exec_window()
	_test_reputation()
	_test_replay()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V2-CORE-3 SYSTEMS PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("SYSTEMS PROBE FAILED")
		quit(1)
	else:
		print("SYSTEMS PROBE OK")
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

func _non_empty(s: String, label: String) -> void:
	_ok(s != "", label, "" if s == "" else "len=%d" % s.length())

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _new_session() -> Dictionary:
	var s := V2Scenario.load_file(SCENARIO)
	var w := V2World.new()
	var ok := w.load_scenario(s)
	var m := V2Mission.from_scenario(s)
	w.attach_mission(m)
	return {"world": w, "mission": m, "scenario": s, "ok": ok}

func _to_command(w: V2World) -> void:
	w.prelude_skip()
	w.advance(0.01)
	w.advance(0.01)

func _satisfy_tutorial(w: V2World) -> void:
	for aid in ["crossfix", "radar_illum", "model_ident", "iff_query"]:
		if w.tutorial_ready():
			return
		w.perform_action(aid, "2001")

func _to_decision(w: V2World) -> void:
	_to_command(w)
	_satisfy_tutorial(w)
	if not bool(w.flow.get("decision_open", false)):
		w.open_decision()
	w.advance(0.01)

# ═══════════════════════════════════════════════════════════════════
# 1. Chronos 站体 / 储罐数据（content 数据驱动；固定无推进）
# ═══════════════════════════════════════════════════════════════════

func _test_station_tank() -> void:
	_section_begin("1 站体/储罐数据")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var s: V2Scenario = sess["scenario"]
	_eq(s.entities.size(), 9, "实体 9（7 舰 + 站体 + 储罐）")
	_eq(s.initial_tracks.size(), 10, "初始航迹 10")
	var station := s.find_entity("chronos_station")
	var tank := s.find_entity("tank_farm")
	_ok(station != null, "chronos_station 实体存在")
	_ok(tank != null, "tank_farm 实体存在")
	if station != null:
		_eq(station.kind, "station", "站体 kind=station")
		_eq(station.side, "neutral", "站体 side=neutral")
		_eq(station.is_fixed(), true, "站体固定（无推进）")
		_eq(String(station.meta.get("icon", "")), "station", "站体 meta.icon")
		_ok(float(station.meta.get("size_km", 0.0)) > 0.0, "站体 meta.size_km",
			str(station.meta.get("size_km")))
		var v: Array = (station.orbit.get("v", []) as Array)
		_eq(v.size(), 3, "站体有轨道分量")
		if v.size() == 3:
			_eq(absf(float(v[0])) + absf(float(v[1])) + absf(float(v[2])), 0.0, "站体速度 0（不伪造推进）")
	if tank != null:
		_eq(tank.kind, "tank", "储罐 kind=tank")
		_eq(tank.is_fixed(), true, "储罐固定（无推进）")
		_eq(int(tank.meta.get("tanks", 0)), 3, "储罐组数量来自数据")
	# world 接触行
	var row_station := w.vm_contact("0100")
	var row_tank := w.vm_contact("0101")
	_eq(String(row_station.get("kind", "")), "station", "接触行 0100 kind=station")
	_eq(String(row_station.get("icon", "")), "station", "接触行 0100 icon")
	_eq(bool(row_station.get("fixed", false)), true, "接触行 0100 fixed")
	_eq(String(row_station.get("orbit_source", "")), "fixed", "接触行 0100 orbit_source=fixed")
	_eq(String(row_tank.get("kind", "")), "tank", "接触行 0101 kind=tank")
	_eq(String(row_tank.get("icon", "")), "tank", "接触行 0101 icon")
	_eq(w.vm_contacts().size(), 10, "vm_contacts 10")
	_eq(w.entities.size(), 9, "world entities 9")
	_data_line("facilities", "chronos_station(kind=station) tank_farm(kind=tank) fixed=true v=0")

# ═══════════════════════════════════════════════════════════════════
# 2. 教学门控（DECISION 前至少 2 项关键识别；不自动完成）
# ═══════════════════════════════════════════════════════════════════

func _test_tutorial() -> void:
	_section_begin("2 教学门控")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var m: V2Mission = sess["mission"]
	_to_command(w)
	var tut := w.vm_tutorial()
	_eq(bool(tut.get("enabled", false)), true, "教学门控启用（story.tutorial）")
	_eq(bool(tut.get("ready", true)), false, "初始未 ready")
	_eq((tut.get("required_actions", []) as Array).size(), 4, "required_actions 4（内容）")
	_eq(int((tut.get("progress", {}) as Dictionary).get("need", 0)), 2, "need=2（至少两项关键识别）")
	_eq(int((tut.get("progress", {}) as Dictionary).get("done", 0)), 0, "已完成 0")

	# 未完成时拒绝打开决策，且不自动识别
	var lv_before := int(w.track_for("2001").level)
	var gated := w.open_decision()
	_eq(bool(gated.get("ok", true)), false, "教学未完成时 open_decision 被拒绝")
	_ok(String(gated.get("reason", "")).contains("教学"), "拒绝原因写明教学门控", String(gated.get("reason", "")))
	_eq(int(w.track_for("2001").level), lv_before, "门控不会自动完成识别（等级不变）")
	_eq(bool(w.flow.get("decision_pending", false)), true, "决策挂起 pending")
	_eq(bool(m.has_flag("decision_open")), false, "mission flag decision_open 未置位")

	# 只完成 1 项：仍不 ready
	w.perform_action("crossfix", "2001")
	var tut1 := w.vm_tutorial()
	_eq(int((tut1.get("progress", {}) as Dictionary).get("done", 0)), 1, "完成 1 项识别")
	_eq(bool(tut1.get("ready", true)), false, "1 项不够（need=2）")
	_eq(bool(w.open_decision().get("ok", true)), false, "1 项时仍拒绝决策")

	# 完成第 2 项：ready + pending 自动打开决策
	w.perform_action("model_ident", "2001")
	var tut2 := w.vm_tutorial()
	_eq(int((tut2.get("progress", {}) as Dictionary).get("done", 0)), 2, "完成 2 项识别")
	_eq(bool(tut2.get("ready", false)), true, "tutorial_ready()=true")
	_eq(w.tutorial_ready(), true, "world.tutorial_ready()")
	_eq(bool(w.flow.get("decision_open", false)), true, "挂起的决策在识别完成后自动打开")
	_eq(bool(w.flow.get("decision_pending", false)), false, "pending 清除")
	_ok((tut2.get("missing", []) as Array).size() == 2, "missing 列出未完成项",
		"missing=%d" % (tut2.get("missing", []) as Array).size())
	# 完成清单含动作/时间（UI 可勾选）
	var completed: Array = tut2.get("completed", [])
	_ok(completed.size() == 2, "completed 行 2（含 label/at）", str(completed))
	w.advance(0.01)
	_eq(m.kind, "DECISION", "mission 进入 DECISION")
	_data_line("tutorial", "required=4 need=2 gate→pending→auto-open，不自动识别")

# ═══════════════════════════════════════════════════════════════════
# 3. 损管模型
# ═══════════════════════════════════════════════════════════════════

func _test_damage() -> void:
	_section_begin("3 损管模型")
	var sess := _new_session()
	var w: V2World = sess["world"]
	w.prelude_skip()
	var dmg := w.vm_damage()
	_eq(String(dmg.get("entity_id", "")), "harmattan", "损管归属本舰")
	var sections: Array = dmg.get("sections", [])
	_eq(sections.size(), 3, "本舰损管项 3（content damage.initial）")
	var ids: Array = []
	for raw in sections:
		ids.append(String((raw as Dictionary).get("id", "")))
	for need in ["sensor_cal", "ir_false_alarm", "thermal"]:
		_ok(need in ids, "损管项存在: " + need)
	var sm: Dictionary = dmg.get("summary", {})
	_eq(int(sm.get("total", 0)), 3, "summary total 3")
	_ok(int(sm.get("damaged", 0)) + int(sm.get("degraded", 0)) > 0, "存在受损项")
	_eq(bool(sm.get("needs_attention", false)), true, "needs_attention=true")
	# 开始维修 + 推进
	var rep := w.start_repair("sensor_cal")
	_eq(bool(rep.get("ok", false)), true, "开始维修 sensor_cal", String(rep.get("reason", "")))
	_eq(String(w._damage_item("sensor_cal").get("state", "")), "repairing", "状态 repairing")
	_eq(bool(w.start_repair("sensor_cal").get("ok", true)), false, "重复维修被拒绝")
	var done := w.advance_damage(120.0)
	_ok((done as Array).size() >= 1, "维修到点完成", "done=%d" % (done as Array).size())
	_eq(String(w._damage_item("sensor_cal").get("state", "")), "repaired", "sensor_cal repaired")
	_eq(w.vm_damage().get("queue", []).size(), 0, "维修队列清空")
	# 新损伤 + 自动 advance 推进
	w.apply_damage("thermal", 0.8, "热控回路过热")
	var thermal := w._damage_item("thermal")
	_eq(String(thermal.get("state", "")), "damaged", "apply_damage 加重 → damaged")
	_ok(float(thermal.get("severity", 0.0)) >= 0.8, "severity 更新", str(thermal.get("severity")))
	w.start_repair("thermal")
	var eta := float(w._damage_item("thermal").get("repair_eta_s", 0.0))
	if eta <= 0.0:
		eta = 180.0
	var out := w.advance(eta + 1.0)
	_ok((out.get("damage", []) as Array).size() >= 1, "world.advance 自动推进维修",
		"done=%d" % (out.get("damage", []) as Array).size())
	_eq(String(w._damage_item("thermal").get("state", "")), "repaired", "thermal repaired")
	# 其他舰无损管项不影响 vm_damage
	_eq(w.vm_damage().get("sections", []).size(), 3, "vm_damage 只含本舰损管项")
	_data_line("damage", "3 项（校准/红外虚警/热控）；repair 120s/180s；advance 自动完成")

# ═══════════════════════════════════════════════════════════════════
# 4. 执行窗口
# ═══════════════════════════════════════════════════════════════════

func _test_exec_window() -> void:
	_section_begin("4 执行窗口")
	var sess := _new_session()
	var w: V2World = sess["world"]
	_to_command(w)
	_eq(w.exec_window_s, 360.0, "exec_window_s 来自 content（360）")
	var left0 := w.exec_left()
	_ok(absf(left0 - 360.0) < 0.1, "初始 exec_left ≈360", "left=%.1f" % left0)
	w.advance(100.0)
	var left1 := w.exec_left()
	_ok(absf(left1 - (360.0 - w.t)) < 0.1, "exec_left 随时间减少", "t=%.1f left=%.1f" % [w.t, left1])
	var flow := w.vm_flow()
	_ok(flow.has("exec_window_s") and flow.has("exec_left") and flow.has("exec_pct"), "vm_flow 提供执行窗口")
	_eq(float(flow.get("exec_window_s", 0.0)), 360.0, "vm_flow.exec_window_s")
	_ok(float(flow.get("exec_pct", 0.0)) > 0.0, "vm_flow.exec_pct", str(flow.get("exec_pct")))
	# 决策后冻结剩余
	_satisfy_tutorial(w)
	if not bool(w.flow.get("decision_open", false)):
		w.open_decision()
	w.advance(0.01)
	var frozen_left := w.exec_left()
	w.choose_ending("HOLD")
	_eq(w.exec_left(), frozen_left, "决策后 exec_left 冻结")
	w.advance(30.0)
	_eq(w.exec_left(), frozen_left, "决策后继续 advance 不恢复倒计时")
	var end := w.end_summary()
	_ok(end.has("exec_window_s") and end.has("exec_left"), "end_summary 提供执行窗口")
	_data_line("exec", "window=360s；决策前倒计时、决策后冻结 left=%.1f" % frozen_left)

# ═══════════════════════════════════════════════════════════════════
# 5. 声望（结局差量来自 story；缺数据基线 + settled=false）
# ═══════════════════════════════════════════════════════════════════

func _test_reputation() -> void:
	_section_begin("5 声望")
	var keys := ["ocu", "meridian", "ueg_doves", "outer", "reclaimers"]
	var sess := _new_session()
	var w: V2World = sess["world"]
	_to_decision(w)
	var hold := w.choose_ending("HOLD")
	_eq(bool(hold.get("ok", false)), true, "HOLD 决策")
	var rep: Dictionary = hold.get("reputation", {})
	_eq(int(rep.get("ocu", 0)), 8, "HOLD → ocu +8（story.endings 数据）")
	_eq(int(rep.get("meridian", 0)), 15, "HOLD → meridian +15")
	_eq(int(rep.get("reclaimers", 0)), -12, "HOLD → reclaimers -12")
	_eq(bool(hold.get("reputation_settled", false)), true, "HOLD reputation_settled=true")
	var end := w.end_summary()
	_eq(bool(end.get("reputation_settled", false)), true, "end_summary reputation_settled")
	for k in keys:
		_ok((end.get("reputation", {}) as Dictionary).has(k), "五方声望含 " + k)
	# FIRE 灾难分支：负向差量来自 story.fire_option
	var sess2 := _new_session()
	var w2: V2World = sess2["world"]
	_to_decision(w2)
	var fire := w2.choose_ending("FIRE")
	_eq(bool(fire.get("ok", false)), true, "FIRE 决策")
	var fire_rep: Dictionary = fire.get("reputation", {})
	_ok(int(fire_rep.get("ueg_doves", 0)) < 0, "FIRE → ueg_doves 负向",
		str(fire_rep.get("ueg_doves")))
	_eq(bool(fire.get("reputation_settled", false)), true, "FIRE reputation_settled")
	# 缺数据：基线 + settled=false
	var mini := V2Scenario.from_dict({
		"schema": "scenario.v2", "id": "mini-rep", "title": "mini", "epoch": 0.0,
		"own_entity": "a",
		"entities": [{"id": "a", "kind": "ship", "side": "friend", "capabilities": []}],
		"tracks": [],
		"phases": [{"id": "p1", "kind": "PRELUDE", "enter": {"always": true}}],
		"story": {
			"reputation": {"ocu": 0, "meridian": 0, "ueg_doves": 0, "outer": 0, "reclaimers": 0},
			"endings": [{"kind": "HOLD", "code": "A", "label": "HOLD"}],
			"decision_replies": {"HOLD": {"from": "a", "to": "b", "mode": "LD", "text": "ok"}},
		},
	}, "<probe>")
	_eq(mini.errors.size(), 0, "mini 声望场景校验", str(mini.errors))
	var w3 := V2World.new()
	w3.load_scenario(mini)
	w3.open_decision()
	var mini_hold := w3.choose_ending("HOLD")
	_eq(bool(mini_hold.get("ok", false)), true, "缺 reputation 数据的结局仍可选")
	_eq(bool(mini_hold.get("reputation_settled", true)), false, "缺数据 → settled=false")
	_eq(int((mini_hold.get("reputation", {}) as Dictionary).get("ocu", -1)), 0, "缺数据 → 返回基线")
	_data_line("reputation", "HOLD +8/+15/+4/+6/-12；FIRE 负向；缺数据 settled=false")

# ═══════════════════════════════════════════════════════════════════
# 6. 回放
# ═══════════════════════════════════════════════════════════════════

func _test_replay() -> void:
	_section_begin("6 回放")
	var sess := _new_session()
	var w: V2World = sess["world"]
	var vm0 := w.vm_replay()
	_eq(bool(vm0.get("recording", false)), true, "默认录制")
	_eq(int(vm0.get("total", 0)), 1, "装载时先写 1 帧（t=0）")
	_eq(int(vm0.get("index", -1)), 0, "index=0")
	_to_command(w)
	for i in range(4):
		w.advance(1.2)
	var vm1 := w.vm_replay()
	_ok(int(vm1.get("total", 0)) >= 4, "每 1s/事件写帧", "frames=%d" % vm1.get("total", 0))
	var frame := w.replay_frame()
	for key in ["t", "own", "contacts", "events_count", "orders", "evidence", "flow", "damage", "exec_left"]:
		_ok(frame.has(key), "帧字段: " + key)
	_ok(not frame.has("weapons") and not frame.has("fire_control"), "回放不含武器数据（不伪造）")
	_ok((frame.get("contacts", []) as Array).size() >= 10, "帧含接触摘要",
		str((frame.get("contacts", []) as Array).size()))
	# 播放/暂停/定位/停止
	var st := w.replay_start()
	_eq(bool(st.get("playing", false)), true, "replay_start playing")
	_eq(int(st.get("index", -1)), 0, "replay_start 从 0 开始")
	var seek := w.replay_seek(2.0)
	var cur: Dictionary = seek.get("current", {})
	_ok(float(cur.get("t", -1.0)) <= 2.0 + 1.0e-6 and float(cur.get("t", -1.0)) >= 0.0,
		"replay_seek(2.0) 定位到 ≤2s 帧", "t=%.2f" % float(cur.get("t", -1.0)))
	_eq(bool(w.replay_pause().get("paused", false)), true, "replay_pause")
	var stop := w.replay_stop()
	_eq(bool(stop.get("playing", true)), false, "replay_stop")
	var last_idx := int(stop.get("index", -1))
	_ok(last_idx == int(stop.get("total", 0)) - 1, "replay_stop 定位最后一帧")
	_eq(int(w.replay_seek_index(0).get("index", -1)), 0, "replay_seek_index(0)")
	# 回放只读：定位不影响世界时间/航迹
	var t_before := w.t
	w.replay_seek(0.0)
	_eq(w.t, t_before, "回放定位不推进世界时间")
	# 清空后继续录制
	w.replay_clear()
	_eq(int(w.vm_replay().get("total", -1)), 0, "replay_clear 清空")
	w.advance(1.2)
	_ok(int(w.vm_replay().get("total", 0)) >= 1, "清空后继续录制")
	_data_line("replay", "1s/事件帧；start/seek/pause/stop/seek_index/frame；只读不推进")

func _dummy() -> void:
	pass
