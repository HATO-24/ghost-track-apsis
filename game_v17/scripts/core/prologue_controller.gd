extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3C：PrologueController（序章流程控制器；新文件）
#
# 状态机（手动，不自动）：
#   NAME_INPUT → BRIEFING → HANDOVER → NAVIGATION → DEPARTURE_REQUEST
#   → BURN_WINDOW → CRUISE → ARRIVAL → COMPLETE
#
# - 玩家名：submit_name（IME 提交；非空/长度/字符校验）；存档；
# - 读 scenario_transit_l4_l1.json + transfer_l4_l1_fleet_cached.json：
#   source/target/TOF/Δv/fleet/时间轴；
# - set_destination/request_departure/authorize_burn/ignite/arrive/complete；
# - 事件 prologue.* + 可选 StoryState flag/evidence/trust 效果；
# - 内存 save/load；不做 UI/物理、不写 world/V15。
# ═══════════════════════════════════════════════════════════════════

const SCENARIO_PATH := "res://framework/content/scenario_transit_l4_l1.json"
const FLEET_PATH := "res://framework/content/transfer_l4_l1_fleet_cached.json"
const SCHEMA := "v17.prologue.v1"
const SAVE_SCHEMA := "v17.prologue_save.v1"
const VERSION := "1.0.0"

const STATES := ["NAME_INPUT", "BRIEFING", "HANDOVER", "NAVIGATION",
	"DEPARTURE_REQUEST", "BURN_WINDOW", "CRUISE", "ARRIVAL", "COMPLETE"]
const STATE_INDEX := {
	"NAME_INPUT": 0, "BRIEFING": 1, "HANDOVER": 2, "NAVIGATION": 3,
	"DEPARTURE_REQUEST": 4, "BURN_WINDOW": 5, "CRUISE": 6,
	"ARRIVAL": 7, "COMPLETE": 8,
}
const WINDOW_OPEN_S := 18.0 * 3600.0
const WINDOW_CLOSE_S := 24.0 * 3600.0
const MAX_NAME_LEN := 24

const EFFECTS := {
	"name_submitted": {"flags": ["prologue_name_set"]},
	"briefing_confirmed": {"flags": ["briefing_confirmed"]},
	"handover_accepted": {"flags": ["handover_done"]},
	"destination_set": {"flags": ["destination_set"]},
	"departure_requested": {"flags": ["departure_requested"]},
	"burn_authorized": {"flags": ["burn_authorized"], "trust": 2.0},
	"burn_ignited": {"flags": ["burn_ignited"], "trust": 3.0},
	"arrived": {"flags": ["arrived_l1"], "evidence": ["ev_arrival_l1"],
		"trust": 5.0},
	"completed": {"flags": ["prologue_complete"]},
}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var scenario_path := SCENARIO_PATH
var fleet_path := FLEET_PATH
var scenario: Dictionary = {}
var fleet_cache: Dictionary = {}

var source_id := ""
var target_id := ""
var source_display := ""
var target_display := ""
var tof_s := 0.0
var tof_days := 0.0
var dv_data: Dictionary = {}
var fleet_rows: Array = []
var timeline_rows: Array = []
var allowed_destinations: Array = []
var source_port := {}
var target_port := {}

var state := "NAME_INPUT"
var player_name := ""
var destination := ""
var request_id := ""
var burn_authorized := false
var ignition_t := -1.0
var arrival_t := -1.0
var t_s := 0.0

var history: Array = []
var events: Array = []
var _event_seq := 0
var applied_flags: Dictionary = {}
var applied_evidence: Array = []
var trust := 50.0
var morality := 0.0
var reputation := 50.0
var threat := 1.0

var story_state = null
var event_bus = null

func _init(opts := {}) -> void:
	setup(opts)

func setup(opts := {}) -> bool:
	var o: Dictionary = opts if opts is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	state = "NAME_INPUT"
	player_name = ""
	destination = ""
	request_id = ""
	burn_authorized = false
	ignition_t = -1.0
	arrival_t = -1.0
	t_s = 0.0
	history = []
	events = []
	_event_seq = 0
	applied_flags = {}
	applied_evidence = []
	trust = 50.0
	morality = 0.0
	reputation = 50.0
	threat = 1.0
	story_state = null
	event_bus = null
	var lr: Dictionary = load_content(String(o.get("scenario_path", SCENARIO_PATH)),
		String(o.get("fleet_path", FLEET_PATH)))
	if not bool(lr.get("ok", false)):
		return false
	if o.get("story_state", null) != null:
		bind_story_state(o.get("story_state"))
	if o.get("event_bus", null) != null:
		bind_event_bus(o.get("event_bus"))
	ready = true
	return true

# ── 内容 ────────────────────────────────────────────────────────

func load_content(s_path := SCENARIO_PATH, f_path := FLEET_PATH) -> Dictionary:
	var sc = _read_json(s_path)
	var fl = _read_json(f_path)
	if not (sc is Dictionary):
		errors.append("scenario JSON 无效：" + s_path)
		return {"ok": false, "errors": errors.duplicate()}
	if not (fl is Dictionary):
		errors.append("fleet cache JSON 无效：" + f_path)
		return {"ok": false, "errors": errors.duplicate()}
	var v: Dictionary = validate_content(sc, fl)
	if not bool(v.get("ok", false)):
		errors.append_array(v.get("errors", []))
		warnings.append_array(v.get("warnings", []))
		return {"ok": false, "errors": errors.duplicate()}
	scenario_path = s_path
	fleet_path = f_path
	scenario = (sc as Dictionary).duplicate(true)
	fleet_cache = (fl as Dictionary).duplicate(true)
	var tr: Dictionary = scenario.get("transfer", {}) if scenario.get("transfer") is Dictionary else {}
	source_id = String(tr.get("source_port", ""))
	target_id = String(tr.get("target_port", ""))
	tof_s = float(fleet_cache.get("tof_s", 0.0))
	tof_days = float(fleet_cache.get("tof_days", tof_s / 86400.0))
	source_display = String(fleet_cache.get("source_port", source_id))
	target_display = String(fleet_cache.get("target_port", target_id))
	dv_data = (fleet_cache.get("dv", {}) as Dictionary).duplicate(true)
	fleet_rows = (fleet_cache.get("ships", []) as Array).duplicate(true)
	allowed_destinations = [target_id]
	for raw_d in (tr.get("target_cluster", []) as Array):
		var d := String(raw_d)
		if d != "" and not (d in allowed_destinations):
			allowed_destinations.append(d)
	source_port = _port_row(source_id)
	target_port = _port_row(target_id)
	_build_timeline()
	ready = true
	return {"ok": true, "errors": [], "warnings": warnings.duplicate()}

func _port_row(port_id: String) -> Dictionary:
	for raw in (scenario.get("ports", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == port_id:
			return (raw as Dictionary).duplicate(true)
	return {}

func _build_timeline() -> void:
	timeline_rows = []
	var samples: Array = fleet_cache.get("samples", []) if fleet_cache.get("samples") is Array else []
	for raw in samples:
		if not (raw is Dictionary):
			continue
		var sm: Dictionary = raw
		var ships: Array = sm.get("ships", []) if sm.get("ships") is Array else []
		var flagship := {}
		for sw in ships:
			if sw is Dictionary and String((sw as Dictionary).get("ship_id", "")) == "apsis":
				flagship = sw
				break
		timeline_rows.append({
			"t_s": float(sm.get("t_s", 0.0)),
			"t_days": float(sm.get("t_days", 0.0)),
			"progress": float(sm.get("progress", 0.0)),
			"flagship_pos_km": (flagship.get("pos_rot_km", []) as Array).duplicate() if flagship.get("pos_rot_km") is Array else [],
			"distance_to_target_km": float(flagship.get("distance_to_target_km", -1.0)),
			"rel_to_flagship_mag_km": float(flagship.get("rel_to_flagship_mag_km", 0.0)),
		})
	# 里程碑
	var milestones: Array = [
		{"kind": "burn_window_open", "t_s": WINDOW_OPEN_S},
		{"kind": "burn_window_close", "t_s": WINDOW_CLOSE_S},
		{"kind": "ignition", "t_s": ignition_t},
		{"kind": "arrival", "t_s": arrival_t},
	]
	for raw in milestones:
		timeline_rows.append((raw as Dictionary).duplicate(true))

func validate_content(sc: Dictionary, fl: Dictionary) -> Dictionary:
	var errs: Array[String] = []
	var warns: Array[String] = []
	if String(sc.get("schema", "")) != "scenario.v2":
		errs.append("scenario schema 必须为 scenario.v2")
	if String(sc.get("id", "")) != "transit_l4_l1":
		errs.append("scenario id 必须为 transit_l4_l1")
	var tr = sc.get("transfer")
	if not (tr is Dictionary):
		errs.append("scenario.transfer 必须是对象")
	else:
		var t: Dictionary = tr
		if String(t.get("source_port", "")) == "":
			errs.append("transfer.source_port 缺失")
		if String(t.get("target_port", "")) == "":
			errs.append("transfer.target_port 缺失")
		if not (t.get("target_cluster") is Array) or (t.get("target_cluster") as Array).is_empty():
			errs.append("transfer.target_cluster 必须非空数组")
		if not (t.get("arrival_gate") is Dictionary):
			errs.append("transfer.arrival_gate 必须是对象")
	if not (sc.get("ports") is Array) or (sc.get("ports") as Array).is_empty():
		errs.append("scenario.ports 必须非空数组")
	if String(fl.get("schema", "")) != "v17_fleet_transfer_cache.v1":
		errs.append("fleet cache schema 必须为 v17_fleet_transfer_cache.v1")
	if String(fl.get("fleet", "")) != "transit_l4_l1":
		errs.append("fleet 必须为 transit_l4_l1")
	if float(fl.get("tof_s", 0.0)) <= 0.0:
		errs.append("fleet tof_s 必须 >0")
	if String(fl.get("source_port", "")) == "" or String(fl.get("target_port", "")) == "":
		errs.append("fleet source/target 缺失")
	var ships: Array = fl.get("ships", []) if fl.get("ships") is Array else []
	if ships.size() != 5:
		errs.append("fleet ships 必须为 5")
	var has_flag := false
	for raw in ships:
		if raw is Dictionary and String((raw as Dictionary).get("ship_id", "")) == "apsis":
			has_flag = true
	if not has_flag:
		errs.append("fleet 缺旗舰 apsis")
	if not (fl.get("samples") is Array) or (fl.get("samples") as Array).is_empty():
		errs.append("fleet samples 必须非空数组")
	if not (fl.get("dv") is Dictionary):
		errs.append("fleet dv 必须是对象")
	if not bool(fl.get("deterministic", false)):
		errs.append("fleet cache deterministic 必须为 true")
	return {"ok": errs.is_empty(), "errors": errs, "warnings": warns}

func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

# ── 只读内容摘要 ────────────────────────────────────────────────

func fleet() -> Array:
	return fleet_rows.duplicate(true)

func timeline() -> Array:
	return timeline_rows.duplicate(true)

func dv() -> Dictionary:
	return dv_data.duplicate(true)

func milestones() -> Dictionary:
	return {
		"source": source_id, "target": target_id,
		"source_display": source_display, "target_display": target_display,
		"tof_s": tof_s, "tof_days": tof_days,
		"burn_window_open_s": WINDOW_OPEN_S, "burn_window_close_s": WINDOW_CLOSE_S,
		"ignition_t": ignition_t, "arrival_t": arrival_t,
		"t_s": t_s,
	}

func state_index() -> int:
	return int(STATE_INDEX.get(state, -1))

func window() -> Dictionary:
	return {
		"open_t": WINDOW_OPEN_S, "close_t": WINDOW_CLOSE_S,
		"authorized": burn_authorized,
		"is_open": t_s >= WINDOW_OPEN_S and t_s <= WINDOW_CLOSE_S,
		"t_s": t_s,
	}

func time_to_window_s() -> float:
	return maxf(0.0, WINDOW_OPEN_S - t_s)

func time_to_arrival_s() -> float:
	if arrival_t < 0.0:
		return -1.0
	return maxf(0.0, arrival_t - t_s)

# ── 名称 ────────────────────────────────────────────────────────

## 接收 ImeInput 提交的玩家名：非空、长度 1..24、无控制字符；成功进入 BRIEFING。
func submit_name(name_text: String, opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "NAME_INPUT":
		return _fail("wrong_state", "precondition: 当前状态 " + state + " 不能输入名字")
	var raw := String(name_text)
	var n := raw.strip_edges()
	if n == "":
		return _fail("empty_name", "precondition: 名字不能为空")
	if raw != n:
		return _fail("invalid_chars", "precondition: 名字首尾不能有空白")
	if n.length() > MAX_NAME_LEN:
		return _fail("name_too_long", "precondition: 名字长度 >%d" % MAX_NAME_LEN)
	for i in range(n.length()):
		var code := n.unicode_at(i)
		if code < 32 or code == 127:
			return _fail("invalid_chars", "precondition: 名字含控制字符")
	player_name = n
	var o: Dictionary = opts if opts is Dictionary else {}
	state = "BRIEFING"
	history.append({"t": t_s, "state": state, "action": "submit_name",
		"ime": bool(o.get("ime", false)), "name": player_name})
	_emit("name_submitted", {"name": player_name, "ime": bool(o.get("ime", false))})
	_apply_effect("name_submitted")
	_check_contracts()
	return {"ok": true, "name": player_name, "state": state,
		"next": next_state()}

func next_state() -> String:
	var i := state_index()
	if i < 0 or i + 1 >= STATES.size():
		return ""
	return String(STATES[i + 1])

# ── 状态机（手动）─────────────────────────────────────────────

func confirm_briefing() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "BRIEFING":
		return _fail("wrong_state", "precondition: 当前状态 " + state)
	state = "HANDOVER"
	history.append({"t": t_s, "state": state, "action": "confirm_briefing"})
	_emit("briefing_confirmed", {})
	_apply_effect("briefing_confirmed")
	_check_contracts()
	return {"ok": true, "state": state, "next": next_state()}

func accept_handover() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "HANDOVER":
		return _fail("wrong_state", "precondition: 当前状态 " + state)
	state = "NAVIGATION"
	history.append({"t": t_s, "state": state, "action": "accept_handover"})
	_emit("handover_accepted", {})
	_apply_effect("handover_accepted")
	_check_contracts()
	return {"ok": true, "state": state, "next": next_state()}

func set_destination(dest_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "NAVIGATION":
		return _fail("wrong_state", "precondition: 当前状态 " + state + " 不能设目的地")
	if not (dest_id in allowed_destinations):
		return _fail("invalid_destination", "precondition: 非法目的地 " + dest_id)
	destination = String(dest_id)
	history.append({"t": t_s, "state": state, "action": "set_destination",
		"destination": destination})
	_emit("destination_set", {"destination": destination})
	_apply_effect("destination_set")
	_check_contracts()
	return {"ok": true, "destination": destination, "state": state,
		"allowed": allowed_destinations.duplicate()}

func request_departure() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "NAVIGATION":
		return _fail("wrong_state", "precondition: 当前状态 " + state)
	if destination == "":
		return _fail("no_destination", "precondition: 未设目的地")
	request_id = "REQ-%06d" % (history.size() + 1)
	state = "DEPARTURE_REQUEST"
	history.append({"t": t_s, "state": state, "action": "request_departure",
		"request_id": request_id, "destination": destination})
	_emit("departure_requested", {"request_id": request_id,
		"destination": destination})
	_apply_effect("departure_requested")
	_check_contracts()
	return {"ok": true, "state": state, "request_id": request_id,
		"next": next_state()}

func authorize_burn() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "DEPARTURE_REQUEST":
		return _fail("wrong_state", "precondition: 当前状态 " + state)
	burn_authorized = true
	state = "BURN_WINDOW"
	history.append({"t": t_s, "state": state, "action": "authorize_burn"})
	_emit("burn_authorized", {"window_open_s": WINDOW_OPEN_S,
		"window_close_s": WINDOW_CLOSE_S})
	_apply_effect("burn_authorized")
	_check_contracts()
	return {"ok": true, "state": state, "authorized": burn_authorized,
		"window": window(), "next": next_state()}

func ignite() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "BURN_WINDOW":
		return _fail("wrong_state", "precondition: 当前状态 " + state)
	if not burn_authorized:
		return _fail("not_authorized", "precondition: 未授权点火")
	if t_s < WINDOW_OPEN_S:
		return _fail("window_not_open", "precondition: 尚未进入点火窗口")
	if t_s > WINDOW_CLOSE_S:
		return _fail("window_closed", "precondition: 点火窗口已关闭")
	ignition_t = t_s
	arrival_t = ignition_t + tof_s
	state = "CRUISE"
	history.append({"t": t_s, "state": state, "action": "ignite",
		"ignition_t": ignition_t, "arrival_t": arrival_t})
	_emit("burn_ignited", {"ignition_t": ignition_t, "arrival_t": arrival_t,
		"tof_s": tof_s, "destination": destination})
	_apply_effect("burn_ignited")
	_build_timeline()
	_check_contracts()
	return {"ok": true, "state": state, "ignition_t": ignition_t,
		"arrival_t": arrival_t, "next": next_state()}

## 手动推进时间（不自动推进状态）。
func advance_time(dt: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if not is_finite(dt) or dt < 0.0:
		return _fail("invalid_dt", "precondition: dt 必须有限且 >=0")
	t_s += dt
	_build_timeline()
	_check_contracts()
	return {"ok": true, "t_s": t_s, "window": window(),
		"time_to_arrival_s": time_to_arrival_s(),
		"arrival_ready": arrival_t >= 0.0 and t_s >= arrival_t}

func arrive() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "CRUISE":
		return _fail("wrong_state", "precondition: 当前状态 " + state + " 不能抵达")
	if arrival_t < 0.0:
		return _fail("not_departed", "precondition: 尚未点火")
	if t_s < arrival_t:
		return _fail("too_early", "precondition: 未到抵达时间（还差 %.0f s）" % (arrival_t - t_s))
	state = "ARRIVAL"
	history.append({"t": t_s, "state": state, "action": "arrive",
		"arrival_t": arrival_t})
	_emit("arrived", {"arrival_t": arrival_t, "t_s": t_s,
		"destination": destination, "arrival_gate": _arrival_gate()})
	_apply_effect("arrived")
	_check_contracts()
	return {"ok": true, "state": state,
		"arrival_error_km": _fleet_max("arrival_error_km"),
		"arrival_gate": _arrival_gate(), "next": next_state()}

func complete() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: controller 未 ready")
	if state != "ARRIVAL":
		return _fail("wrong_state", "precondition: 当前状态 " + state + " 不能完成")
	state = "COMPLETE"
	history.append({"t": t_s, "state": state, "action": "complete"})
	_emit("completed", {"t_s": t_s, "name": player_name,
		"destination": destination})
	_apply_effect("completed")
	_check_contracts()
	return {"ok": true, "state": state, "complete": true}

func _arrival_gate() -> Dictionary:
	var tr: Dictionary = scenario.get("transfer", {}) if scenario.get("transfer") is Dictionary else {}
	return (tr.get("arrival_gate", {}) as Dictionary).duplicate(true) if tr.get("arrival_gate") is Dictionary else {}

func _fleet_max(key: String) -> float:
	var m := 0.0
	for raw in fleet_rows:
		if raw is Dictionary:
			m = maxf(m, float((raw as Dictionary).get(key, 0.0)))
	return m

# ── 事件 / 效果 ────────────────────────────────────────────────

func _emit(kind: String, detail: Dictionary) -> void:
	_event_seq += 1
	var ev := {
		"schema": "prologue_event.v1",
		"seq": _event_seq,
		"t": t_s,
		"kind": "prologue." + kind,
		"state": state,
		"detail": detail.duplicate(true),
		"writes_v15": false,
	}
	events.append(ev)
	if events.size() > 200:
		events.pop_front()
	if event_bus != null and event_bus.has_method("publish"):
		var pub: Dictionary = event_bus.publish({
			"type": "prologue." + kind, "t": t_s, "source": "prologue",
			"target": destination, "payload": detail.duplicate(true),
			"text_key": "",
		})
		if not bool(pub.get("ok", false)):
			warnings.append("prologue bus publish 失败：" + str(pub.get("errors", [])))

func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out

func take_events() -> Array:
	var out := events.duplicate(true)
	events = []
	return out

func bind_story_state(ss) -> Dictionary:
	if ss == null or not ss.has_method("has_flag"):
		return {"ok": false, "reason": "invalid_story_state"}
	story_state = ss
	applied_flags = (ss.flags as Dictionary).duplicate(true)
	applied_evidence = (ss.evidence_ids as Array).duplicate()
	trust = float(ss.trust)
	morality = float(ss.morality)
	reputation = float(ss.reputation)
	threat = float(ss.threat)
	return {"ok": true, "story_ready": bool(ss.ready)}

func bind_event_bus(bus) -> Dictionary:
	if bus == null or not bus.has_method("publish"):
		return {"ok": false, "reason": "invalid_event_bus"}
	event_bus = bus
	return {"ok": true}

## 应用效果（flags/evidence/trust/morality/reputation/threat）；同步 StoryState。
func apply_effects(effects := {}) -> Dictionary:
	if not (effects is Dictionary):
		return {"ok": false, "errors": ["effects 必须是对象"]}
	var e: Dictionary = effects
	var applied := {"flags": [], "evidence": [], "stats": {}}
	var errs: Array[String] = []
	if e.get("flags") is Array:
		for raw in (e.get("flags") as Array):
			var flag := String(raw)
			if flag == "":
				continue
			if story_state != null:
				var fr: Dictionary = story_state.set_flag(flag, true)
				if not bool(fr.get("ok", false)):
					errs.append("flag 失败：" + flag)
			applied_flags[flag] = true
			(applied["flags"] as Array).append(flag)
	if e.get("evidence") is Array:
		for raw_e in (e.get("evidence") as Array):
			var eid := String(raw_e)
			if eid == "":
				continue
			if story_state != null:
				var er: Dictionary = story_state.add_evidence(eid)
				if not bool(er.get("ok", false)) and String(er.get("reason", "")) != "duplicate_evidence":
					errs.append("evidence 失败：" + eid)
			if not (eid in applied_evidence):
				applied_evidence.append(eid)
			(applied["evidence"] as Array).append(eid)
	for pair in [["trust", trust], ["morality", morality],
			["reputation", reputation], ["threat", threat]]:
		var stat := String(pair[0])
		if not e.has(stat):
			continue
		var delta := float(e.get(stat))
		if story_state != null:
			var res: Dictionary = {}
			match stat:
				"trust": res = story_state.adjust_trust(delta)
				"morality": res = story_state.adjust_morality(delta)
				"reputation": res = story_state.adjust_reputation(delta)
				"threat": res = story_state.adjust_threat(delta)
			if res.has("after"):
				(applied["stats"] as Dictionary)[stat] = float(res.get("after"))
		else:
			(applied["stats"] as Dictionary)[stat] = _set_stat(stat, delta)
	if story_state != null:
		trust = float(story_state.trust)
		morality = float(story_state.morality)
		reputation = float(story_state.reputation)
		threat = float(story_state.threat)
	return {"ok": errs.is_empty(), "applied": applied, "errors": errs}

func _set_stat(stat: String, delta: float) -> float:
	var cur := 0.0
	var lo := 0.0
	var hi := 100.0
	match stat:
		"trust": cur = trust; lo = 0.0; hi = 100.0
		"morality": cur = morality; lo = -100.0; hi = 100.0
		"reputation": cur = reputation; lo = 0.0; hi = 100.0
		"threat": cur = threat; lo = 0.0; hi = 5.0
	var after := clampf(cur + delta, lo, hi)
	match stat:
		"trust": trust = after
		"morality": morality = after
		"reputation": reputation = after
		"threat": threat = after
	return after

func _apply_effect(kind: String) -> void:
	if not EFFECTS.has(kind):
		return
	var res: Dictionary = apply_effects(EFFECTS[kind])
	if not bool(res.get("ok", false)):
		warnings.append_array(res.get("errors", []))

# ── DbC / 快照 ──────────────────────────────────────────────────

func _check_contracts() -> void:
	var v: Array = _violations()
	contract_errors.append_array(v)
	if not v.is_empty():
		warnings.append("prologue 不变量失败：" + str(v))

func _violations() -> Array[String]:
	var v: Array[String] = []
	if not (state in STATES):
		v.append("state 非法：" + state)
	if state != "NAME_INPUT" and player_name == "":
		v.append("非 NAME_INPUT 状态缺 player_name")
	if destination != "" and not (destination in allowed_destinations):
		v.append("destination 非法：" + destination)
	if ignition_t >= 0.0 and arrival_t < ignition_t:
		v.append("arrival_t 早于 ignition_t")
	if t_s < 0.0:
		v.append("t_s 为负")
	if not is_finite(trust) or trust < 0.0 or trust > 100.0:
		v.append("trust 越界")
	return v

func check_contracts() -> Dictionary:
	return {"schema": SCHEMA, "ok": _violations().is_empty(), "violations": _violations()}

func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"ready": ready,
		"state": state,
		"state_index": state_index(),
		"next_state": next_state(),
		"player_name": player_name,
		"destination": destination,
		"request_id": request_id,
		"burn_authorized": burn_authorized,
		"t_s": t_s,
		"ignition_t": ignition_t,
		"arrival_t": arrival_t,
		"window": window(),
		"time_to_window_s": time_to_window_s(),
		"time_to_arrival_s": time_to_arrival_s(),
		"source": source_id, "target": target_id,
		"source_display": source_display, "target_display": target_display,
		"tof_s": tof_s, "tof_days": tof_days,
		"dv": dv_data.duplicate(true),
		"fleet": fleet_rows.duplicate(true),
		"timeline": timeline_rows.duplicate(true),
		"allowed_destinations": allowed_destinations.duplicate(),
		"history": history.duplicate(true),
		"events": events.duplicate(true),
		"applied": {
			"flags": applied_flags.duplicate(true),
			"evidence": applied_evidence.duplicate(),
			"trust": trust, "morality": morality,
			"reputation": reputation, "threat": threat,
		},
		"story": story_state.snapshot() if story_state != null else null,
		"contracts": check_contracts(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"contract_errors": contract_errors.duplicate(),
	}

func vm() -> Dictionary:
	return snapshot()

func to_dict() -> Dictionary:
	return snapshot()

func to_json() -> String:
	return JSON.stringify(snapshot())

# ── 内存 save/load ─────────────────────────────────────────────

func save_state() -> String:
	return JSON.stringify({
		"schema": SAVE_SCHEMA, "version": VERSION,
		"scenario_path": scenario_path, "fleet_path": fleet_path,
		"state": state, "player_name": player_name,
		"destination": destination, "request_id": request_id,
		"burn_authorized": burn_authorized,
		"t_s": t_s, "ignition_t": ignition_t, "arrival_t": arrival_t,
		"history": JSON.parse_string(JSON.stringify(history)),
		"events": JSON.parse_string(JSON.stringify(events)),
		"event_seq": _event_seq,
		"flags": JSON.parse_string(JSON.stringify(applied_flags)),
		"evidence": applied_evidence.duplicate(),
		"trust": trust, "morality": morality,
		"reputation": reputation, "threat": threat,
		"story_save": story_state.save_state() if story_state != null else "",
	})

func load_state(json_text: String) -> Dictionary:
	if json_text.strip_edges() == "":
		return _fail("empty_state", "load: 空 JSON")
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return _fail("invalid_json", "load: JSON 无效")
	var d: Dictionary = parsed
	if String(d.get("schema", "")) != SAVE_SCHEMA:
		return _fail("invalid_schema", "load: schema 无效")
	if String(d.get("version", "")) != VERSION:
		return _fail("unsupported_version", "load: version 不支持")
	if not ready:
		return _fail("not_ready", "load: controller 未 ready")
	var saved_state := String(d.get("state", ""))
	if not (saved_state in STATES):
		return _fail("invalid_state", "load: state 非法：" + saved_state)
	var saved_name := String(d.get("player_name", ""))
	if saved_state != "NAME_INPUT" and saved_name == "":
		return _fail("invalid_name", "load: 非 NAME_INPUT 状态缺名字")
	if saved_name.length() > MAX_NAME_LEN:
		return _fail("invalid_name", "load: 名字超长")
	var saved_dest := String(d.get("destination", ""))
	if saved_dest != "" and not (saved_dest in allowed_destinations):
		return _fail("invalid_destination", "load: destination 非法")
	var saved_story := String(d.get("story_save", ""))
	if saved_story != "" and story_state != null:
		var probe_story = load("res://scripts/core/story_state.gd").new()
		if not bool(probe_story.load(saved_story).get("ok", false)):
			return _fail("invalid_story_save", "load: StoryState 快照无效")
	# 应用
	state = saved_state
	player_name = saved_name
	destination = saved_dest
	request_id = String(d.get("request_id", ""))
	burn_authorized = bool(d.get("burn_authorized", false))
	t_s = float(d.get("t_s", 0.0))
	ignition_t = float(d.get("ignition_t", -1.0))
	arrival_t = float(d.get("arrival_t", -1.0))
	history = (d.get("history", []) as Array).duplicate(true) if d.get("history") is Array else []
	events = (d.get("events", []) as Array).duplicate(true) if d.get("events") is Array else []
	_event_seq = int(d.get("event_seq", events.size()))
	var f = d.get("flags", {})
	applied_flags = (f as Dictionary).duplicate(true) if f is Dictionary else {}
	applied_evidence = (d.get("evidence", []) as Array).duplicate() if d.get("evidence") is Array else []
	trust = float(d.get("trust", 50.0))
	morality = float(d.get("morality", 0.0))
	reputation = float(d.get("reputation", 50.0))
	threat = float(d.get("threat", 1.0))
	if saved_story != "" and story_state != null:
		var sr: Dictionary = story_state.load(saved_story)
		if not bool(sr.get("ok", false)):
			return _fail("story_restore_failed", "load: StoryState 恢复失败")
		applied_flags = (story_state.flags as Dictionary).duplicate(true)
		applied_evidence = (story_state.evidence_ids as Array).duplicate()
		trust = float(story_state.trust)
	_build_timeline()
	_check_contracts()
	return {"ok": true, "state": state, "player_name": player_name,
		"destination": destination, "t_s": t_s, "errors": []}

func reset() -> Dictionary:
	state = "NAME_INPUT"
	player_name = ""
	destination = ""
	request_id = ""
	burn_authorized = false
	ignition_t = -1.0
	arrival_t = -1.0
	t_s = 0.0
	history = []
	events = []
	_event_seq = 0
	_build_timeline()
	return {"ok": true, "state": state}

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": String(reason_text), "errors": [msg]}
