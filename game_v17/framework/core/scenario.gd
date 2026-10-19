class_name V2Scenario
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2-1 场景加载 / 校验 / 旧场景迁移
#
#   V2 schema（"schema": "scenario.v2"）：
#     id / title / epoch / datum / own_entity
#     entities[]  实体（id/kind/side/name/class/capabilities/orbit/…）
#     tracks[]    初始航迹种子（id/entity_id/level/identity/threat/age_s/…）
#     phases[]    数据驱动任务阶段（id/kind/enter/prompt_ref/options_ref/actions）
#     evidence    证据定义 + policy
#     orders      命令队列配置
#     story_file  文本数据文件（story.* ref 从这里取）
#   校验错误逐条写 errors（带路径），不做静默兜底。
#
#   旧场景（v15："schema": "scenario.v0"，含 ships/tracks/sensors/story/false_alarm）：
#     迁移为 entities + initial_tracks + phases + evidence；能力由传感器架推出；
#     story 内的 decision_t / evidence_tasks / endings / prelude 等映射为阶段与证据。
# ═══════════════════════════════════════════════════════════════════

const V2_SCHEMAS := ["scenario.v2", "v2"]
const LEGACY_SCHEMAS := ["scenario.v0", "scenario.v1", "v0", ""]
const PHASE_KINDS := ["PRELUDE", "READ", "COMMAND", "DECISION", "CONSEQUENCE", "REPORT", "END"]
const ENTER_KEYS := ["always", "min_t", "max_t", "flags_all", "flags_any", "flags_none",
	"evidence_min", "track_level", "order_state", "all", "any"]
const SIDES := ["friend", "hostile", "neutral", "unknown"]
const DEFAULT_EVIDENCE_POLICY := {"min_for_expose": 2}
const DEFAULT_ORDERS_CONFIG := {"tx_delay_s": 8.0, "exec_delay_s": 0.0}
const DEFAULT_EXEC_WINDOW := {"duration_s": 360.0}
const DEFAULT_DAMAGE := {"repair_rate_s": 120.0, "initial": []}

var raw: Dictionary = {}
var source_path := ""
var schema := ""
var source_schema := ""
var id := ""
var title := ""
var epoch := 0.0
var datum := "L1"

var own_entity_id := ""
var entities: Array[V2Entity] = []
var initial_tracks: Array = []
var phases: Array = []
var evidence_defs: Dictionary = {}
var evidence_policy: Dictionary = DEFAULT_EVIDENCE_POLICY.duplicate(true)
var orders_config: Dictionary = DEFAULT_ORDERS_CONFIG.duplicate(true)
var exec_window_config: Dictionary = DEFAULT_EXEC_WINDOW.duplicate(true)
var damage_config: Dictionary = DEFAULT_DAMAGE.duplicate(true)
var story: Dictionary = {}
var endings: Array = []
var timeline: Dictionary = {}
var orders_rules: Dictionary = {}

var warnings: Array[String] = []
var errors: Array[String] = []
var migrated := false

# ── 加载 ─────────────────────────────────────────────────────────

static func load_file(path: String) -> V2Scenario:
	var s := V2Scenario.new()
	s.source_path = path
	if not FileAccess.file_exists(path):
		s.errors.append("missing scenario: " + path)
		return s
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		s.errors.append("invalid json (不是对象): " + path)
		return s
	return V2Scenario.from_dict(parsed, path)

## 深拷贝（restart 用）：从原始数据重新走一遍校验/迁移，不复用旧实体/航迹对象。
func clone() -> V2Scenario:
	return V2Scenario.from_dict(raw.duplicate(true), source_path)

static func from_dict(data: Dictionary, source := "<memory>") -> V2Scenario:
	var s := V2Scenario.new()
	s.source_path = source
	s.raw = data.duplicate(true)
	s.schema = String(data.get("schema", ""))
	s.source_schema = s.schema if s.schema != "" else "scenario.v0"
	s.id = String(data.get("id", ""))
	s.title = String(data.get("title", ""))
	s.epoch = float(data.get("epoch", 0.0))
	s.datum = String(data.get("datum", "L1"))
	s.timeline = (data.get("timeline", {}) as Dictionary).duplicate(true)
	if s.schema in V2_SCHEMAS or (s.schema == "" and data.has("entities")):
		if s.schema == "":
			s.warnings.append("场景缺少 schema 字段，按 scenario.v2 校验")
		s._build_v2()
	elif s.schema in LEGACY_SCHEMAS or data.has("tracks") or data.has("ships"):
		s.migrated = true
		s._migrate_v0()
	else:
		s.errors.append("无法识别的场景 schema: '%s'（支持 scenario.v2 / scenario.v0）" % s.schema)
	return s

# ── 查询 ─────────────────────────────────────────────────────────

func find_entity(eid: String) -> V2Entity:
	for e in entities:
		if e.id == eid:
			return e
	return null

func by_batch(batch: String) -> V2Entity:
	for e in entities:
		if e.id == batch or e.batch == batch:
			return e
	return null

func entity_for_track(track_id: String) -> V2Entity:
	for raw_t in initial_tracks:
		var t: Dictionary = raw_t
		if String(t.get("id", "")) == track_id:
			var eid := String(t.get("entity_id", ""))
			if eid != "":
				return find_entity(eid)
	return null

func track_seed(track_id: String) -> Dictionary:
	for raw_t in initial_tracks:
		var t: Dictionary = raw_t
		if String(t.get("id", "")) == track_id:
			return t
	return {}

func phase_ids() -> Array:
	var out: Array = []
	for raw_p in phases:
		out.append(String((raw_p as Dictionary).get("id", "")))
	return out

func phase_kinds() -> Array:
	var out: Array = []
	for raw_p in phases:
		out.append(String((raw_p as Dictionary).get("kind", "")))
	return out

func story_endings() -> Array:
	return endings

# ── 流程数据（V2-CORE-2 用；全部来自 story/场景，不写死关卡文本）─────

func prelude_data() -> Dictionary:
	return (story.get("prelude", {}) as Dictionary).duplicate(true)

func prelude_enabled() -> bool:
	return not prelude_data().is_empty() and ("PRELUDE" in phase_kinds())

func story_events() -> Array:
	return (story.get("events", []) as Array).duplicate(true)

func story_radio() -> Array:
	return (story.get("radio_lines", []) as Array).duplicate(true)

func decision_prompt() -> String:
	return String(story.get("decision_prompt", ""))

func decision_replies() -> Dictionary:
	return (story.get("decision_replies", {}) as Dictionary).duplicate(true)

func consequence_text() -> String:
	return String(story.get("consequence_fire", ""))

## 结局选项（kind/code/label/hint），来自 story.endings；FIRE 是独立灾难分支，不在列表内时由 UI 单独提供。
func ending_by_kind(kind: String) -> Dictionary:
	for raw in endings:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			return (raw as Dictionary).duplicate(true)
	return {}

func report_bodies() -> Dictionary:
	return (story.get("report_bodies", {}) as Dictionary).duplicate(true)

func report_fake() -> Dictionary:
	return (story.get("report_fake", {}) as Dictionary).duplicate(true)

func report_recommend() -> Dictionary:
	return (story.get("report_recommend", {}) as Dictionary).duplicate(true)

func reputation_base() -> Dictionary:
	return (story.get("reputation", {}) as Dictionary).duplicate(true)

# ── V2 校验 ─────────────────────────────────────────────────────

func _build_v2() -> void:
	_require_key("id", "V2 场景缺少 id")
	_require_key("title", "V2 场景缺少 title")
	_require_key("epoch", "V2 场景缺少 epoch")
	_require_key("entities", "V2 场景缺少 entities")
	_require_key("tracks", "V2 场景缺少 tracks")
	_require_key("phases", "V2 场景缺少 phases")
	if not (raw.get("entities", []) is Array):
		errors.append("entities: 必须是数组")
		return
	if not (raw.get("tracks", []) is Array):
		errors.append("tracks: 必须是数组")
		return
	if not (raw.get("phases", []) is Array):
		errors.append("phases: 必须是数组")
		return

	# —— 实体 ——
	var ids: Dictionary = {}
	for i in range((raw.get("entities", []) as Array).size()):
		var raw_e = (raw.get("entities", []) as Array)[i]
		var path := "entities[%d]" % i
		if not (raw_e is Dictionary):
			errors.append(path + ": 必须是对象")
			continue
		var e := V2Entity.from_dict(raw_e)
		if e.id == "":
			errors.append(path + ".id: 不能为空")
			continue
		path = "entities[%d] (%s)" % [i, e.id]
		if ids.has(e.id):
			errors.append(path + ".id: 重复 " + e.id)
			continue
		ids[e.id] = true
		if e.kind == "":
			errors.append(path + ".kind: 不能为空")
		if not (e.side in SIDES):
			errors.append(path + ".side: 非法阵营 '%s'（允许 %s）" % [e.side, ", ".join(SIDES)])
		if not (raw_e.get("capabilities", []) is Array):
			errors.append(path + ".capabilities: 必须是数组")
		if not (raw_e.get("orbit", {}) is Dictionary):
			errors.append(path + ".orbit: 必须是对象")
		if not (raw_e.get("meta", {}) is Dictionary):
			errors.append(path + ".meta: 必须是对象")
		entities.append(e)

	# —— 初始航迹 ——
	var track_ids: Dictionary = {}
	for i in range((raw.get("tracks", []) as Array).size()):
		var raw_t = (raw.get("tracks", []) as Array)[i]
		var path := "tracks[%d]" % i
		if not (raw_t is Dictionary):
			errors.append(path + ": 必须是对象")
			continue
		var t: Dictionary = (raw_t as Dictionary).duplicate(true)
		var tid := String(t.get("id", ""))
		if tid == "":
			errors.append(path + ".id: 不能为空")
			continue
		path = "tracks[%d] (%s)" % [i, tid]
		if track_ids.has(tid):
			errors.append(path + ".id: 重复 " + tid)
			continue
		track_ids[tid] = true
		var eid := String(t.get("entity_id", ""))
		if eid != "" and not ids.has(eid):
			errors.append(path + ".entity_id: 引用了不存在的实体 '" + eid + "'")
		var lv := int(t.get("level", 1))
		if lv < 0 or lv > 4:
			errors.append(path + ".level: 必须在 0–4（当前 %d）" % lv)
		var identity := String(t.get("identity", "pending"))
		if identity == "":
			errors.append(path + ".identity: 不能为空")
		# 把实体轨道状态带进航迹种子，便于从 r/v 派生方位/距离（只做几何）。
		var ent := find_entity(eid)
		if ent != null and not t.has("orbit"):
			t["orbit"] = ent.orbit.duplicate(true)
			if not t.has("bearing_deg") and not t.has("range_km"):
				t["bearing_only"] = bool(t.get("bearing_only", true))
		initial_tracks.append(t)

	# —— 阶段 ——
	var phase_ids: Dictionary = {}
	for i in range((raw.get("phases", []) as Array).size()):
		var raw_p = (raw.get("phases", []) as Array)[i]
		var path := "phases[%d]" % i
		if not (raw_p is Dictionary):
			errors.append(path + ": 必须是对象")
			continue
		var ph: Dictionary = (raw_p as Dictionary).duplicate(true)
		var pid := String(ph.get("id", ""))
		if pid == "":
			errors.append(path + ".id: 不能为空")
			continue
		path = "phases[%d] (%s)" % [i, pid]
		if phase_ids.has(pid):
			errors.append(path + ".id: 重复 " + pid)
			continue
		phase_ids[pid] = true
		var pk := String(ph.get("kind", ""))
		if not (pk in PHASE_KINDS):
			errors.append(path + ".kind: 非法阶段类型 '%s'（允许 %s）" % [pk, ", ".join(PHASE_KINDS)])
		var enter: Dictionary = (ph.get("enter", {}) as Dictionary)
		if not (ph.get("enter", {}) is Dictionary):
			errors.append(path + ".enter: 必须是对象")
		else:
			_validate_enter(enter, path + ".enter")
		if ph.has("actions") and not (ph.get("actions") is Array):
			errors.append(path + ".actions: 必须是数组")
		phases.append(ph)

	# —— 证据 ——
	_build_evidence_from_v2(raw.get("evidence", {}))

	# —— 命令配置 ——
	if raw.has("orders"):
		if not (raw.get("orders") is Dictionary):
			errors.append("orders: 必须是对象")
		else:
			for k in (raw.get("orders") as Dictionary).keys():
				orders_config[k] = (raw.get("orders") as Dictionary)[k]

	# —— 执行窗口 / 损管配置（V2-CORE-3）——
	_build_exec_window(raw.get("exec_window", {}))
	_build_damage(raw.get("damage", {}))

	# —— 文本 ——
	if raw.has("story") and not (raw.get("story") is Dictionary):
		errors.append("story: 必须是对象")
	if raw.has("story"):
		story = (raw.get("story", {}) as Dictionary).duplicate(true)
	if raw.has("story_file"):
		_load_story_file(String(raw.get("story_file", "")))
	if raw.has("endings"):
		if not (raw.get("endings") is Array):
			errors.append("endings: 必须是数组")
		else:
			endings = (raw.get("endings") as Array).duplicate(true)
	if endings.is_empty() and story.has("endings"):
		endings = (story.get("endings", []) as Array).duplicate(true)

	# —— 基准实体 ——
	own_entity_id = _resolve_own_entity(String(raw.get("own_entity", "")))
	if own_entity_id == "":
		errors.append("own_entity: 无法确定己方实体（own_entity 未给且无 own/own_fleet tag）")

	_validate_action_refs()

func _build_evidence_from_v2(raw_ev) -> void:
	evidence_defs.clear()
	evidence_policy = DEFAULT_EVIDENCE_POLICY.duplicate(true)
	if not (raw_ev is Dictionary):
		if raw_ev != null and not (raw_ev is Dictionary):
			errors.append("evidence: 必须是对象")
		return
	var ev: Dictionary = raw_ev
	if ev.has("policy"):
		if not (ev.get("policy") is Dictionary):
			errors.append("evidence.policy: 必须是对象")
		else:
			for k in (ev.get("policy") as Dictionary).keys():
				evidence_policy[k] = (ev.get("policy") as Dictionary)[k]
	var items = ev.get("items", {})
	if items is Array:
		for i in range((items as Array).size()):
			var it = (items as Array)[i]
			if not (it is Dictionary):
				errors.append("evidence.items[%d]: 必须是对象" % i)
				continue
			var eid := String((it as Dictionary).get("id", ""))
			if eid == "":
				errors.append("evidence.items[%d].id: 不能为空" % i)
				continue
			var d: Dictionary = (it as Dictionary).duplicate(true)
			d["id"] = eid
			evidence_defs[eid] = d
	elif items is Dictionary:
		for k in (items as Dictionary).keys():
			var d2 = (items as Dictionary)[k]
			if not (d2 is Dictionary):
				errors.append("evidence.items.%s: 必须是对象" % String(k))
				continue
			var dd: Dictionary = (d2 as Dictionary).duplicate(true)
			if String(dd.get("id", "")) == "":
				dd["id"] = String(k)
			evidence_defs[String(dd["id"])] = dd

func _load_story_file(path: String) -> void:
	if path == "":
		errors.append("story_file: 路径为空")
		return
	if not FileAccess.file_exists(path):
		errors.append("story_file: 文件不存在 " + path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		errors.append("story_file: JSON 无效 " + path)
		return
	var d: Dictionary = parsed
	if d.has("story") and d.get("story") is Dictionary:
		story = (d.get("story") as Dictionary).duplicate(true)
	else:
		story = d.duplicate(true)
	if endings.is_empty() and story.has("endings"):
		endings = (story.get("endings", []) as Array).duplicate(true)

## 执行窗口配置（V2-CORE-3）：{"duration_s": 360.0}。
func _build_exec_window(raw_ew) -> void:
	exec_window_config = DEFAULT_EXEC_WINDOW.duplicate(true)
	if raw_ew == null:
		return
	if not (raw_ew is Dictionary):
		errors.append("exec_window: 必须是对象")
		return
	var ew: Dictionary = raw_ew
	for k in ew.keys():
		exec_window_config[k] = ew[k]
	if float(exec_window_config.get("duration_s", 0.0)) <= 0.0:
		errors.append("exec_window.duration_s: 必须 > 0（当前 %s）" % str(exec_window_config.get("duration_s")))

## 损管配置（V2-CORE-3）：{"repair_rate_s":..., "initial":[{id,label,state,severity,repair_eta_s}]}。
func _build_damage(raw_dmg) -> void:
	damage_config = DEFAULT_DAMAGE.duplicate(true)
	if raw_dmg == null:
		return
	if not (raw_dmg is Dictionary):
		errors.append("damage: 必须是对象")
		return
	var dm: Dictionary = raw_dmg
	for k in dm.keys():
		if k == "initial":
			continue
		damage_config[k] = dm[k]
	var items: Array = []
	var raw_items = dm.get("initial", [])
	if not (raw_items is Array):
		errors.append("damage.initial: 必须是数组")
	else:
		for i in range((raw_items as Array).size()):
			var it = (raw_items as Array)[i]
			if not (it is Dictionary):
				errors.append("damage.initial[%d]: 必须是对象" % i)
				continue
			var d: Dictionary = (it as Dictionary).duplicate(true)
			if String(d.get("id", "")) == "":
				errors.append("damage.initial[%d].id: 不能为空" % i)
				continue
			if not d.has("label"):
				d["label"] = String(d.get("id", ""))
			var sev := float(d.get("severity", 0.0))
			if sev < 0.0 or sev > 1.0:
				errors.append("damage.initial[%d] (%s).severity: 必须在 0–1" % [i, String(d.get("id", ""))])
			items.append(d)
	damage_config["initial"] = items

func _validate_enter(cond: Dictionary, path: String) -> void:	for raw_key in cond.keys():
		var key := String(raw_key)
		if not (key in ENTER_KEYS):
			errors.append(path + "." + key + ": 未知进入条件（允许 %s）" % ", ".join(ENTER_KEYS))
			continue
		var val = cond[raw_key]
		match key:
			"min_t", "max_t":
				if not (val is float or val is int):
					errors.append(path + "." + key + ": 必须是数字")
			"flags_all", "flags_any", "flags_none":
				if not (val is Array):
					errors.append(path + "." + key + ": 必须是数组")
			"evidence_min":
				if not (val is float or val is int):
					errors.append(path + "." + key + ": 必须是数字")
			"track_level", "order_state":
				if not (val is Dictionary):
					errors.append(path + "." + key + ": 必须是对象")
			"all", "any":
				if not (val is Array):
					errors.append(path + "." + key + ": 必须是数组")
				else:
					for j in range((val as Array).size()):
						var sub: Variant = (val as Array)[j]
						if sub is Dictionary:
							var subd: Dictionary = sub
							_validate_enter(subd, path + "." + key + "[%d]" % j)
						else:
							errors.append(path + "." + key + "[%d]: 必须是对象" % j)
			_:
				pass

func _validate_action_refs() -> void:
	V2Actions.ensure_loaded()
	for raw in V2Actions.errors:
		if not (raw in errors):
			errors.append(String(raw))
	for raw_p in phases:
		var ph: Dictionary = raw_p
		for raw_a in (ph.get("actions", []) as Array):
			var aid := String(raw_a)
			if V2Actions.definition(aid).is_empty():
				warnings.append("phases.%s.actions: 动作未定义 '%s'" % [String(ph.get("id", "")), aid])

func _resolve_own_entity(explicit: String) -> String:
	if explicit != "":
		if find_entity(explicit) == null:
			errors.append("own_entity: 引用了不存在的实体 '" + explicit + "'")
			return ""
		return explicit
	for e in entities:
		if "own" in e.tags:
			return e.id
	for e in entities:
		if "command" in e.tags:
			return e.id
	for e in entities:
		if "own_fleet" in e.tags:
			return e.id
	for e in entities:
		if e.side == "friend":
			return e.id
	return ""

func _require_key(key: String, message: String) -> void:
	if not raw.has(key):
		errors.append(message)

# ── v15 → V2 迁移 ───────────────────────────────────────────────

func _migrate_v0() -> void:
	migrated = true
	if not (raw.get("tracks", []) is Array) or (raw.get("tracks", []) as Array).is_empty():
		errors.append("旧场景缺少 tracks 数组（无法迁移为实体/航迹）")
		return
	story = (raw.get("story", {}) as Dictionary).duplicate(true)
	endings = (story.get("endings", []) as Array).duplicate(true)

	# ships：batch/id → 静态资料
	var ships_by_batch: Dictionary = {}
	var ships_by_id: Dictionary = {}
	for raw_ship in (raw.get("ships", []) as Array):
		if raw_ship is Dictionary:
			var sh: Dictionary = raw_ship
			var sid := String(sh.get("id", ""))
			if sid != "":
				ships_by_id[sid] = sh
			var batch := String(sh.get("batch", sid))
			if batch != "":
				ships_by_batch[batch] = sh

	var sensor_racks: Dictionary = (raw.get("sensors", {}) as Dictionary)
	var entity_ids: Dictionary = {}
	var track_ids: Dictionary = {}
	for raw_track in (raw.get("tracks", []) as Array):
		if not (raw_track is Dictionary):
			continue
		var tr: Dictionary = raw_track
		var tid := String(tr.get("id", tr.get("batch", "")))
		if tid == "":
			errors.append("旧场景 track 缺少 id/batch: %s" % str(tr))
			continue
		if track_ids.has(tid):
			errors.append("旧场景 track id 重复: " + tid)
			continue
		track_ids[tid] = true
		var ship: Dictionary = ships_by_batch.get(tid, ships_by_id.get(tid, {}))
		var e: V2Entity = _migrate_entity(tid, tr, ship, sensor_racks)
		if e != null:
			if entity_ids.has(e.id):
				errors.append("迁移后实体 id 重复: " + e.id)
			else:
				entity_ids[e.id] = true
				entities.append(e)
		var seed := _migrate_track_seed(tid, tr, e)
		initial_tracks.append(seed)

	# 虚警/残骸：v15 里 9002 是 CH-IR2 的回波候选，没有真实实体 —— 迁移为无实体航迹。
	var fa: Dictionary = (raw.get("false_alarm", {}) as Dictionary)
	if not fa.is_empty():
		var fb := String(fa.get("batch", ""))
		if fb != "" and track_ids.has(fb):
			warnings.append("false_alarm.batch 与已有航迹重复，跳过虚警迁移: " + fb)
		else:
			var seed_fa := {
				"id": fb if fb != "" else "PHANTOM",
				"entity_id": "",
				"level": 1,
				"identity": "pending",
				"threat": "none",
				"bearing_only": true,
				"bearing_deg": float(fa.get("bearing_deg", -1.0)),
				"age_s": 0.0,
				"sources": [String(fa.get("sensor", ""))],
				"tags": ["phantom", "false_alarm"],
				"notes": [String(fa.get("note", fa.get("kind", "回波候选"))),
					"来源: %s / %s" % [String(fa.get("owner", "")), String(fa.get("kind", ""))]],
			}
			initial_tracks.append(seed_fa)

	# 证据任务
	evidence_defs.clear()
	var tasks: Dictionary = (story.get("evidence_tasks", {}) as Dictionary)
	for k in tasks.keys():
		var raw_task = tasks[k]
		if not (raw_task is Dictionary):
			continue
		var d: Dictionary = (raw_task as Dictionary).duplicate(true)
		d["id"] = String(k)
		d["label"] = String(d.get("label", k))
		d["duration_s"] = float(d.get("duration", 0.0))
		# 迁移约定：v15 的「撤出 Chronos 人员」完成即平民撤离（旧场景无 flags 字段）。
		if String(k) == "evacuation":
			d["flags_on_done"] = ["civilians_evacuated"]
		evidence_defs[String(k)] = d
	evidence_policy = DEFAULT_EVIDENCE_POLICY.duplicate(true)
	warnings.append("迁移：证据门槛取默认 min_for_expose=%d（旧场景无该字段，口径见 docs/07）"
		% int(evidence_policy.get("min_for_expose", 2)))
	orders_config = DEFAULT_ORDERS_CONFIG.duplicate(true)

	# 阶段：旧 story 结构 → 数据驱动阶段（条件用 flag 名，由任务逻辑置位）
	phases = _migrate_phases(story)

	var own_ship := String(raw.get("own_ship", ""))
	if own_ship != "":
		for e in entities:
			if String(e.meta.get("ship_key", "")) == own_ship:
				own_entity_id = e.id
				break
	if own_entity_id == "":
		own_entity_id = _resolve_own_entity("")
	if own_entity_id == "":
		errors.append("迁移：无法确定己方实体（ships.own / tracks.own 均缺失）")
	_validate_action_refs()

func _migrate_entity(tid: String, tr: Dictionary, ship: Dictionary, sensor_racks: Dictionary) -> V2Entity:
	var e := V2Entity.from_dict(tr)
	# 旧版 track.id 就是四位数批号；实体 id 沿用批号，保持 V1.5 UI/日志兼容。
	e.id = tid
	e.batch = tid
	e.kind = String(tr.get("kind", "ship"))
	if e.kind == "" or e.kind == "unknown":
		e.kind = "ship"
	e.side = String(tr.get("side", "unknown"))
	e.name = String(ship.get("name", tr.get("name", "")))
	e.name_en = String(ship.get("name_en", tr.get("en", "")))
	e.cls = String(ship.get("ship_class", tr.get("cls", "")))
	e.role = String(ship.get("role", tr.get("role", "")))
	e.faction = String(ship.get("faction", ""))
	var ship_key := String(ship.get("id", ""))
	var orbit: Dictionary = {"frame": datum}
	if tr.has("r"):
		orbit["r"] = (tr.get("r", []) as Array).duplicate()
	if tr.has("v"):
		orbit["v"] = (tr.get("v", []) as Array).duplicate()
	if not orbit.has("r"):
		warnings.append("迁移：航迹 %s 缺少 r/v（无轨道状态，只保留接触数据）" % tid)
	e.orbit = orbit
	e.tags.clear()
	e.tags.append("own_fleet")
	if bool(tr.get("own", false)):
		e.tags.append("own")
	e.meta["ship_key"] = ship_key
	e.meta["migrated_from"] = "tracks[]"
	e.meta["batch"] = tid
	var builder := String(ship.get("builder", ""))
	if builder != "":
		e.meta["builder"] = builder
	# 能力：从旧场景的按舰传感器架推（数据驱动），推不出才用最小默认值。
	var models: Array = []
	for raw_s in (sensor_racks.get(ship_key, []) as Array):
		if raw_s is Dictionary:
			models.append(String((raw_s as Dictionary).get("model", "")))
	var caps := _capabilities_from_sensor_models(ship_key, models)
	if caps.is_empty():
		warnings.append("迁移：%s 无传感器架数据，使用最小能力默认值" % tid)
		caps = _fallback_capabilities(e.side)
	else:
		e.meta["capability_source"] = "migrated_from_sensor_rack"
	e.capabilities = caps
	e.meta["sensors"] = models
	e.signatures = {}
	e.track_level = int(tr.get("level", 1))
	e.identity = String(tr.get("identity", "pending"))
	e.threat = String(tr.get("threat", "pending"))
	return e

func _capabilities_from_sensor_models(ship_key: String, models: Array) -> Array[String]:
	var caps: Array[String] = []
	for raw_model in models:
		var model := String(raw_model)
		if model == "":
			continue
		var sensor: Dictionary = SensorModel.rack_sensor(ship_key, model)
		if sensor.is_empty():
			warnings.append("迁移：传感器型号 %s 不在型号库（%s）" % [model, ship_key])
			continue
		var stype := String(sensor.get("type", ""))
		var cap := ""
		match stype:
			"ir":
				cap = "sensor.ir"
			"radar":
				cap = "sensor.radar.active"
			"optical":
				cap = "sensor.lidar" if String(sensor.get("subtype", "")) == "lidar" else "sensor.optical"
			"iff":
				cap = "sensor.iff.interrogator"
			"elint":
				cap = "sensor.elint.passive"
			"radio":
				cap = "comms.radio"
			"lasercom":
				cap = "comms.laser"
		if cap != "" and not (cap in caps):
			caps.append(cap)
	if ship_key != "" and not ("comms.radio" in caps):
		caps.append("comms.radio")
	return caps

func _fallback_capabilities(side: String) -> Array[String]:
	var caps: Array[String] = ["comms.radio"]
	match side:
		"friend":
			caps.append_array(["sensor.radar.active", "sensor.optical", "sensor.ir",
				"sensor.iff.interrogator", "datalink.ocuvf"])
		"hostile":
			caps.append_array(["sensor.elint.passive", "sensor.iff.interrogator", "datalink.ueg33"])
		_:
			caps.append("sensor.optical.passive")
	return caps

func _migrate_track_seed(tid: String, tr: Dictionary, e: V2Entity) -> Dictionary:
	var seed := {
		"id": tid,
		"entity_id": e.id if e != null else "",
		"level": int(tr.get("level", 1)),
		"identity": String(tr.get("identity", "pending")),
		"threat": String(tr.get("threat", "pending")),
		"age_s": float(tr.get("age", 0.0)),
		"bearing_only": bool(tr.get("bearing_only", false)),
		"tags": [],
		"notes": [],
	}
	var orbit: Dictionary = {}
	if tr.has("r"):
		orbit["r"] = (tr.get("r", []) as Array).duplicate()
		if tr.has("v"):
			orbit["v"] = (tr.get("v", []) as Array).duplicate()
		seed["orbit"] = orbit
	if tr.has("name") and e == null:
		seed["notes"].append("无实体接触: " + String(tr.get("name", "")))
	if bool(tr.get("own", false)):
		seed["tags"].append("own")
	return seed

func _migrate_phases(st: Dictionary) -> Array:
	var out: Array = []
	var prelude: Dictionary = (st.get("prelude", {}) as Dictionary)
	var title := String(prelude.get("title", "PRELUDE"))
	out.append({
		"id": "prelude", "kind": "PRELUDE", "title": title,
		"enter": {"always": true},
		"prompt_ref": "story.prelude.body",
		"options_ref": "story.prelude",
		"actions": [],
	})
	out.append({
		"id": "read", "kind": "READ", "title": "接管通知 / NOTICE",
		"enter": {"flags_any": ["prelude_executed"]},
		"prompt_ref": "story.notice.body",
		"options_ref": "story.notice",
		"actions": [],
	})
	out.append({
		"id": "command", "kind": "COMMAND", "title": "处置 / COMMAND",
		"enter": {"min_t": 0.0},
		"prompt_ref": "story.decision_prompt",
		"actions": ["crossfix", "radar_illum", "model_ident", "radar_track",
			"iff_query", "optical_channel", "ir_channel"],
	})
	out.append({
		"id": "decision", "kind": "DECISION", "title": "指挥官决策 / DETERMINATION",
		"enter": {"flags_any": ["decision_open"]},
		"prompt_ref": "story.decision_prompt",
		"options_ref": "story.endings",
		"actions": ["crossfix", "radar_illum", "model_ident", "radar_track",
			"iff_query", "optical_channel", "ir_channel",
			"fire_control", "missile_solve", "weapons_hold"],
	})
	out.append({
		"id": "consequence", "kind": "CONSEQUENCE", "title": "后果 / CONSEQUENCE",
		"enter": {"flags_any": ["fire_release"]},
		"prompt_ref": "story.consequence_fire",
		"optional": true,
		"actions": [],
	})
	out.append({
		"id": "report", "kind": "REPORT", "title": "内部事后报告 / AFTER-ACTION",
		"enter": {"flags_any": ["decision_made", "fire_release"]},
		"prompt_ref": "story.report_event",
		"actions": [],
	})
	out.append({
		"id": "end", "kind": "END", "title": "归档 / END",
		"enter": {"flags_any": ["report_submitted"]},
		"prompt_ref": "story.report_evidence",
		"actions": [],
	})
	return out
