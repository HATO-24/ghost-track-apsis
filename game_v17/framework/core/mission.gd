class_name V2Mission
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2-1 任务阶段状态机（数据驱动）
#
#   阶段序列：PRELUDE → READ → COMMAND → DECISION → CONSEQUENCE? → REPORT → END
#   - phases 来自场景（scenario.phases）：id / kind / title / enter 条件 /
#     prompt_ref / options_ref / actions / optional；代码里不写死第一关结局。
#   - 进入条件由数据描述：always / min_t / max_t / flags_all|any|none /
#     evidence_min / track_level / order_state / all / any；未知条件键报错，
#     不静默放行。
#   - 提示/选项文本从场景 story 里按 ref 取（story.decision_prompt 等）；
#     取不到时返回空并由 errors 记录，不伪造文本。
#   - 可选阶段（CONSEQUENCE?）：条件不满足时 advance 自动跳过，非可选阶段
#     条件不满足则停留并给 reason。
# ═══════════════════════════════════════════════════════════════════

signal phase_changed(from_id: String, to_id: String)

const PHASE_KINDS := ["PRELUDE", "READ", "COMMAND", "DECISION", "CONSEQUENCE", "REPORT", "END"]
const ENTER_KEYS := ["always", "min_t", "max_t", "flags_all", "flags_any", "flags_none",
	"evidence_min", "track_level", "order_state", "all", "any"]

var phases: Array = []
var phase := ""
var kind := ""
var entered_t := 0.0
var flags: Dictionary = {}
var phase_flags: Dictionary = {}
var history: Array = []
var errors: Array[String] = []

var scenario: V2Scenario = null
var world: V2World = null

# ── 行动触发文本（阶段2 TEXT-ENGINE-1）────────────────────────────
# story.triggers 定义：玩家动作/选择/命令/裁决/环境 → 既有 story.events /
# story.radio_lines 条目（只引用索引，不复制、不发明文本）。
const STORY_TRIGGER_SCHEMA := "v2_story_trigger.v1"
const STORY_TRIGGER_ON := ["select", "action", "order", "prelude", "evidence",
	"decision", "report", "environment", "flag"]
var story_triggers: Array = []
var fired_triggers: Dictionary = {}
var trigger_log: Array = []
var trigger_seq := 0
var _story_events: Array = []
var _story_radio: Array = []

func _init() -> void:
	phases = default_phases()
	if phases.size() > 0:
		var d: Dictionary = phases[0]
		phase = String(d.get("id", ""))
		kind = String(d.get("kind", ""))
		phase_flags[phase] = true

## 无场景时的兜底阶段（只为 V2-0 骨架可跑，不含任何第一关文本/结局）。
static func default_phases() -> Array:
	return [
		{"id": "prelude", "kind": "PRELUDE", "title": "前置 / PRELUDE", "enter": {"always": true}, "actions": []},
		{"id": "read", "kind": "READ", "title": "读取 / READ", "enter": {"always": true}, "actions": []},
		{"id": "command", "kind": "COMMAND", "title": "处置 / COMMAND", "enter": {"always": true}, "actions": []},
		{"id": "decision", "kind": "DECISION", "title": "决策 / DECISION", "enter": {"always": true}, "actions": []},
		{"id": "consequence", "kind": "CONSEQUENCE", "title": "后果 / CONSEQUENCE", "enter": {"always": true}, "optional": true, "actions": []},
		{"id": "report", "kind": "REPORT", "title": "报告 / REPORT", "enter": {"always": true}, "actions": []},
		{"id": "end", "kind": "END", "title": "结束 / END", "enter": {"always": true}, "actions": []},
	]

static func from_scenario(s: V2Scenario) -> V2Mission:
	var m := V2Mission.new()
	if s == null:
		m.errors.append("from_scenario: scenario 为空，使用默认阶段")
		return m
	m.attach_scenario(s)
	var ph: Array = s.phases
	if ph.is_empty():
		m.errors.append("scenario 无 phases，使用默认阶段（不写死关卡内容）")
	else:
		m.phases = ph.duplicate(true)
		m._reset_to_start()
	return m

# —— 绑定 ——

func attach_scenario(s: V2Scenario) -> void:
	scenario = s
	if s != null:
		for e in s.errors:
			if not (e in errors):
				errors.append(e)
	_load_story_triggers()

func attach_world(w: V2World) -> void:
	world = w

func attach(w: V2World, s: V2Scenario) -> void:
	attach_world(w)
	attach_scenario(s)

# —— 行动触发文本（TEXT-ENGINE-1）──────────────────────────────

## 从 scenario.story.triggers 读取触发器；事件/无线电文本只按索引引用。
func _load_story_triggers() -> void:
	story_triggers.clear()
	fired_triggers.clear()
	trigger_log.clear()
	trigger_seq = 0
	_story_events = []
	_story_radio = []
	if scenario == null:
		return
	var st: Dictionary = scenario.story
	_story_events = (st.get("events", []) as Array).duplicate(true)
	_story_radio = (st.get("radio_lines", []) as Array).duplicate(true)
	var raw: Variant = st.get("triggers", [])
	if not (raw is Array):
		errors.append("story.triggers: 必须是数组")
		return
	var seen: Dictionary = {}
	for i in range((raw as Array).size()):
		var item = (raw as Array)[i]
		if not (item is Dictionary):
			errors.append("story.triggers[%d]: 必须是对象" % i)
			continue
		var t: Dictionary = (item as Dictionary).duplicate(true)
		var tid := String(t.get("id", ""))
		if tid == "":
			errors.append("story.triggers[%d]: 缺少 id" % i)
			continue
		if seen.has(tid):
			errors.append("story.triggers: 重复 id " + tid)
			continue
		seen[tid] = true
		var on := String(t.get("on", ""))
		if not (on in STORY_TRIGGER_ON):
			errors.append("story.triggers[%s]: 未知 on=%s" % [tid, on])
			continue
		var channel := String(t.get("channel", "event"))
		if not (channel in ["event", "radio"]):
			errors.append("story.triggers[%s]: channel 必须 event|radio" % tid)
			continue
		var idx := int(t.get("event_index" if channel == "event" else "radio_index", -1))
		var entries: Array = _story_events if channel == "event" else _story_radio
		if idx < 0 or idx >= entries.size():
			errors.append("story.triggers[%s]: %s_index 越界 %d" % [tid, channel, idx])
			continue
		if on == "environment" and not (t.has("min_t") or t.has("at_t")):
			errors.append("story.triggers[%s]: environment 需要 min_t/at_t" % tid)
			continue
		story_triggers.append({
			"id": tid, "on": on, "action": String(t.get("action", "")),
			"target": String(t.get("target", "")),
			"targets": (t.get("targets", []) as Array).duplicate(),
			"state": String(t.get("state", "")),
			"channel": channel, "index": idx,
			"min_t": float(t.get("min_t", t.get("at_t", -1.0))),
			"once": bool(t.get("once", true)),
			"text_key": String(t.get("text_key", "")),
			"note": String(t.get("note", "")),
		})

## 玩家动作/选择/命令/裁决成功后调用；返回本次触发的文本条目（按触发器定义顺序）。
## 同一条触发器 once 默认只触发一次；动作失败由调用方不调用本函数保证。
func note_player_event(kind: String, action: String, target := "", extra: Dictionary = {}) -> Array:
	var fired: Array = []
	if not bool(extra.get("ok", true)):
		return fired
	var now := world.t if world != null else float(extra.get("now", 0.0))
	for raw in story_triggers:
		if not (raw is Dictionary):
			continue
		var t: Dictionary = raw
		if String(t.get("on", "")) != kind or kind == "environment":
			continue
		if String(t.get("action", "")) != "" and String(t.get("action", "")) != action:
			continue
		if String(t.get("target", "")) != "" and String(t.get("target", "")) != target:
			continue
		var targets: Array = t.get("targets", []) as Array
		if not targets.is_empty() and not (target in targets):
			continue
		if String(t.get("state", "")) != "" \
				and String(t.get("state", "")) != String(extra.get("state", "")):
			continue
		var min_t := float(t.get("min_t", -1.0))
		if min_t >= 0.0 and now + 1.0e-9 < min_t:
			continue
		if bool(t.get("once", true)) and fired_triggers.has(String(t.get("id", ""))):
			continue
		var item := _fire_trigger(t, kind, action, target, now)
		if not item.is_empty():
			fired.append(item)
	return fired

## 环境/倒计时触发器（只允许 story.triggers 中 on=="environment"；不占用玩家动作顺序）。
func tick_environment(now: float) -> Array:
	var fired: Array = []
	for raw in story_triggers:
		if not (raw is Dictionary):
			continue
		var t: Dictionary = raw
		if String(t.get("on", "")) != "environment":
			continue
		if bool(t.get("once", true)) and fired_triggers.has(String(t.get("id", ""))):
			continue
		var min_t := float(t.get("min_t", -1.0))
		if min_t < 0.0 or now + 1.0e-9 < min_t:
			continue
		var item := _fire_trigger(t, "environment", "", "", now)
		if not item.is_empty():
			fired.append(item)
	return fired

func _fire_trigger(t: Dictionary, kind: String, action: String, target: String, now: float) -> Dictionary:
	var tid := String(t.get("id", ""))
	var channel := String(t.get("channel", "event"))
	var idx := int(t.get("index", -1))
	var entries: Array = _story_events if channel == "event" else _story_radio
	if idx < 0 or idx >= entries.size():
		errors.append("story.trigger %s: 文本索引失效" % tid)
		return {}
	var entry: Dictionary = (entries[idx] as Dictionary).duplicate(true)
	trigger_seq += 1
	var item := {
		"schema": STORY_TRIGGER_SCHEMA,
		"trigger_id": tid, "channel": channel, "index": idx,
		"text_key": String(t.get("text_key", "")),
		"source": kind, "action": action, "target": target,
		"seq": trigger_seq, "t": now,
	}
	if channel == "event":
		item["event"] = entry
	else:
		item["radio"] = entry
	fired_triggers[tid] = {"seq": trigger_seq, "t": now, "source": kind}
	trigger_log.append(item.duplicate(true))
	return item

func reset_story_triggers(reload := true) -> void:
	fired_triggers.clear()
	trigger_log.clear()
	trigger_seq = 0
	if reload:
		_load_story_triggers()

## 触发器状态快照（JSON-safe；供 probe/诊断，不接 UI）。
func trigger_snapshot() -> Dictionary:
	var rows: Array = []
	for raw in story_triggers:
		var t: Dictionary = raw
		rows.append({
			"id": String(t.get("id", "")), "on": String(t.get("on", "")),
			"action": String(t.get("action", "")), "target": String(t.get("target", "")),
			"state": String(t.get("state", "")), "channel": String(t.get("channel", "")),
			"index": int(t.get("index", -1)), "min_t": float(t.get("min_t", -1.0)),
			"text_key": String(t.get("text_key", "")),
			"fired": fired_triggers.has(String(t.get("id", ""))),
		})
	return {
		"schema": STORY_TRIGGER_SCHEMA,
		"trigger_count": story_triggers.size(),
		"fired_count": fired_triggers.size(),
		"log_count": trigger_log.size(),
		"next_seq": trigger_seq,
		"triggers": rows,
		"log": trigger_log.duplicate(true),
		"errors": errors.duplicate(),
	}

# —— 查询 ——

func current() -> Dictionary:
	var i := _index_of(phase)
	return phases[i] if i >= 0 else {}

func current_index() -> int:
	return _index_of(phase)

func total_phases() -> int:
	return phases.size()

func phase_kind() -> String:
	return kind

func title() -> String:
	var cur := current()
	if cur.has("title"):
		return String(cur.get("title", ""))
	var t := _resolve_ref(String(cur.get("title_ref", "")))
	return t

func is_phase(p: String) -> bool:
	return phase == p or kind == p

func elapsed(now: float) -> float:
	return maxf(0.0, now - entered_t)

func has_flag(name: String) -> bool:
	return bool(flags.get(name, false))

func set_flag(name: String, value := true) -> void:
	flags[name] = value

func clear_flag(name: String) -> void:
	flags.erase(name)

func available_action_ids() -> Array:
	var cur := current()
	return (cur.get("actions", []) as Array).duplicate()

func is_last() -> bool:
	return current_index() >= phases.size() - 1

# —— 提示/选项（从场景文本按 ref 取）——

## 返回 {title, text, hint, options, actions}；文本缺失时为空字符串。
func prompt() -> Dictionary:
	var cur := current()
	var out := {
		"title": title(),
		"text": "",
		"hint": "",
		"options": [],
		"actions": available_action_ids(),
		"phase": phase,
		"kind": kind,
	}
	if cur.has("prompt"):
		out["text"] = String(cur.get("prompt", ""))
	elif cur.has("prompt_ref"):
		out["text"] = _resolve_ref(String(cur.get("prompt_ref", "")))
	if cur.has("hint"):
		out["hint"] = String(cur.get("hint", ""))
	if cur.has("options"):
		out["options"] = (cur.get("options", []) as Array).duplicate(true)
	elif cur.has("options_ref"):
		var opts: Variant = _resolve_ref_any(String(cur.get("options_ref", "")))
		if opts is Array:
			out["options"] = (opts as Array).duplicate(true)
		elif opts is Dictionary:
			out["options"] = (opts as Dictionary).duplicate(true)
	return out

func _resolve_ref(path: String) -> String:
	var v: Variant = _resolve_ref_any(path)
	if v == null:
		errors.append("文本引用不存在: " + path)
		return ""
	return String(v) if not (v is Dictionary or v is Array) else ""

func _resolve_ref_any(path: String) -> Variant:
	if path == "":
		return null
	var parts := path.split(".")
	var node: Variant = null
	if parts.size() > 0 and String(parts[0]) == "story":
		if scenario == null:
			return null
		node = scenario.story
		parts = parts.slice(1)
	else:
		return null
	for raw in parts:
		var key := String(raw)
		if node is Dictionary:
			if not (node as Dictionary).has(key):
				return null
			node = (node as Dictionary)[key]
		elif node is Array:
			var idx := int(key)
			if idx < 0 or idx >= (node as Array).size():
				return null
			node = (node as Array)[idx]
		else:
			return null
	return node

# —— 阶段推进 ——

func _reset_to_start() -> void:
	phase = ""
	kind = ""
	entered_t = 0.0
	history.clear()
	if phases.is_empty():
		return
	_enter_index(0, 0.0)

func _index_of(phase_id: String) -> int:
	for i in range(phases.size()):
		if String((phases[i] as Dictionary).get("id", "")) == phase_id:
			return i
	return -1

## 显式进入指定阶段（尊重进入条件，除非 force=true）。
func try_enter(phase_id: String, now: float, force := false) -> Dictionary:
	var i := _index_of(phase_id)
	if i < 0:
		return {"ok": false, "reason": "未知阶段: " + phase_id}
	if not force:
		var r := can_enter_phase(i, now)
		if not bool(r.get("ok", false)):
			return r
	return _enter_index(i, now)

## 评估某阶段的进入条件；返回 {ok, reason}。
func can_enter_phase(index: int, now: float) -> Dictionary:
	if index < 0 or index >= phases.size():
		return {"ok": false, "reason": "阶段下标越界: %d" % index}
	var ph: Dictionary = phases[index]
	var cond: Dictionary = (ph.get("enter", {}) as Dictionary)
	if cond.is_empty():
		return {"ok": true, "reason": ""}
	return evaluate_condition(cond, now)

func evaluate_condition(cond: Dictionary, now: float) -> Dictionary:
	for raw_key in cond.keys():
		var key := String(raw_key)
		var val = cond[raw_key]
		if not (key in ENTER_KEYS):
			return {"ok": false, "reason": "未知进入条件: " + key}
		match key:
			"always":
				if not bool(val):
					return {"ok": false, "reason": "条件 always=false"}
			"min_t":
				var t := _now(now)
				if t < float(val):
					return {"ok": false, "reason": "需到 T+%.1fs（当前 %.1fs）" % [float(val), t]}
			"max_t":
				var t2 := _now(now)
				if t2 > float(val):
					return {"ok": false, "reason": "已过 T+%.1fs（当前 %.1fs）" % [float(val), t2]}
			"flags_all":
				for raw_f in (val as Array):
					if not has_flag(String(raw_f)):
						return {"ok": false, "reason": "缺少 flag: " + String(raw_f)}
			"flags_any":
				var any_ok := false
				for raw_f in (val as Array):
					if has_flag(String(raw_f)):
						any_ok = true
						break
				if not any_ok:
					return {"ok": false, "reason": "需要 flag 之一: " + ", ".join(val)}
			"flags_none":
				for raw_f in (val as Array):
					if has_flag(String(raw_f)):
						return {"ok": false, "reason": "禁止 flag: " + String(raw_f)}
			"evidence_min":
				if world == null:
					return {"ok": false, "reason": "world 未绑定，无法判断证据"}
				if world.evidence_count() < int(val):
					return {"ok": false, "reason": "证据不足（%d/%d）" % [world.evidence_count(), int(val)]}
			"track_level":
				var r := _eval_track_level(val)
				if not bool(r.get("ok", false)):
					return r
			"order_state":
				var r2 := _eval_order_state(val)
				if not bool(r2.get("ok", false)):
					return r2
			"all":
				for raw_c in (val as Array):
					if raw_c is Dictionary:
						var rc := evaluate_condition(raw_c, now)
						if not bool(rc.get("ok", false)):
							return rc
			"any":
				var any_cond := false
				var last_reason := ""
				for raw_c in (val as Array):
					if raw_c is Dictionary:
						var rc2 := evaluate_condition(raw_c, now)
						if bool(rc2.get("ok", false)):
							any_cond = true
							break
						last_reason = String(rc2.get("reason", ""))
				if not any_cond:
					return {"ok": false, "reason": "任一条件都不满足（%s）" % last_reason}
	return {"ok": true, "reason": ""}

func _now(now: float) -> float:
	if world != null:
		return world.t
	return now

func _eval_track_level(spec: Variant) -> Dictionary:
	if not (spec is Dictionary):
		return {"ok": false, "reason": "track_level 条件格式错误"}
	if world == null:
		return {"ok": false, "reason": "world 未绑定，无法判断航迹等级"}
	var d: Dictionary = spec
	var tr: V2Track = null
	if d.has("track_id"):
		tr = world.tracks.find(String(d.get("track_id", "")))
	elif d.has("entity_id"):
		tr = world.tracks.find_by_entity(String(d.get("entity_id", "")))
	else:
		return {"ok": false, "reason": "track_level 需要 track_id 或 entity_id"}
	if tr == null:
		return {"ok": false, "reason": "航迹不存在"}
	if d.has("min") and tr.level < int(d.get("min", 0)):
		return {"ok": false, "reason": "航迹等级不足（L%d < L%d）" % [tr.level, int(d.get("min", 0))]}
	if d.has("max") and tr.level > int(d.get("max", 4)):
		return {"ok": false, "reason": "航迹等级过高（L%d > L%d）" % [tr.level, int(d.get("max", 4))]}
	return {"ok": true, "reason": ""}

func _eval_order_state(spec: Variant) -> Dictionary:
	if not (spec is Dictionary):
		return {"ok": false, "reason": "order_state 条件格式错误"}
	if world == null:
		return {"ok": false, "reason": "world 未绑定，无法判断命令状态"}
	var d: Dictionary = spec
	var want: Array = []
	if d.has("state"):
		want.append(String(d.get("state", "")))
	for raw in (d.get("states", []) as Array):
		want.append(String(raw))
	if want.is_empty():
		return {"ok": false, "reason": "order_state 需要 state/states"}
	var matched: Array = []
	for raw in world.orders.all():
		var o: V2Orders.Order = raw
		if d.has("order_id") and o.id != String(d.get("order_id", "")):
			continue
		if d.has("action") and o.action != String(d.get("action", "")):
			continue
		if d.has("target") and o.target != String(d.get("target", "")):
			continue
		matched.append(o)
	if matched.is_empty():
		return {"ok": false, "reason": "没有匹配的命令"}
	for raw in matched:
		var o: V2Orders.Order = raw
		if o.state in want:
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "命令状态不符（当前 %s）" % (matched[0] as V2Orders.Order).state}

## 推进到下一阶段。可选阶段条件不满足时自动跳过。
func advance(now: float) -> Dictionary:
	var i := current_index()
	if i < 0:
		return {"ok": false, "phase": phase, "reason": "当前阶段未知"}
	var skipped: Array = []
	var j := i + 1
	while j < phases.size():
		var ph: Dictionary = phases[j]
		var r := can_enter_phase(j, now)
		if bool(r.get("ok", false)):
			var from := phase
			_enter_index(j, now)
			return {"ok": true, "phase": phase, "kind": kind, "from": from,
				"skipped": skipped, "reason": ""}
		if bool(ph.get("optional", false)):
			skipped.append(String(ph.get("id", "")))
			j += 1
			continue
		return {"ok": false, "phase": phase, "reason": String(r.get("reason", "")), "skipped": skipped}
	return {"ok": false, "phase": phase, "reason": "已是最后阶段", "skipped": skipped}

func _enter_index(index: int, now: float) -> Dictionary:
	var from := phase
	var ph: Dictionary = phases[index]
	phase = String(ph.get("id", ""))
	kind = String(ph.get("kind", ""))
	entered_t = now
	phase_flags[phase] = true
	history.append({"from": from, "to": phase, "kind": kind, "t": now})
	phase_changed.emit(from, phase)
	return {"ok": true, "phase": phase, "kind": kind, "from": from, "reason": ""}

## UI 用的完整阶段视图。
func snapshot(now: float) -> Dictionary:
	var cur := current()
	return {
		"phase": phase, "kind": kind, "index": current_index(), "total": phases.size(),
		"title": title(), "elapsed_s": elapsed(_now(now)), "is_last": is_last(),
		"prompt": prompt(), "flags": flags.duplicate(true),
		"phase_flags": phase_flags.duplicate(), "history": history.duplicate(true),
		"errors": errors.duplicate(),
		"phases": phases.duplicate(true),
	}

## 重开：清空流程 flags/历史，回到第一个阶段（scenario 由 world.restart 重新装载）。
func reset() -> void:
	flags.clear()
	phase_flags.clear()
	history.clear()
	entered_t = 0.0
	phase = ""
	kind = ""
	if phases.is_empty() and scenario != null:
		phases = scenario.phases.duplicate(true)
	if not phases.is_empty():
		_enter_index(0, 0.0)
