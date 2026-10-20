extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3A：StoryState（剧情状态服务；新文件）
#
# - flags / evidence_ids / choices / trust(副官) / morality / reputation /
#   threat / chapter / phase；只读 VM/快照；
# - API：set_flag/clear_flag/has_flag、add_evidence/has_evidence、record_choice、
#   adjust_trust/morality/reputation/threat、set_chapter/phase、gate(conditions)、
#   snapshot/load(JSON)/save_state/reset；
# - DbC：取值范围、未知 flag 拒绝、证据唯一、trust/morality 边界、time/version 单调；
# - 分支 gate 数据化：AEUG / GHOST TRACK / 程序正义 / 错付 / 守口如瓶最小条件；
# - 不做 UI/剧情文案/物理；不接旧场景。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.story_state.v1"
const VERSION := "1.0.0"
const PHASES := ["prelude", "read", "command", "decision", "consequence", "report", "end"]
const ID_PATTERN := "^[a-z][a-z0-9_]*$"

const TRUST_MIN := 0.0
const TRUST_MAX := 100.0
const MORALITY_MIN := -100.0
const MORALITY_MAX := 100.0
const REPUTATION_MIN := 0.0
const REPUTATION_MAX := 100.0
const THREAT_MIN := 0.0
const THREAT_MAX := 5.0

## 分支 gate（数据化最小条件；不含文案）。条件键见 gate()。
const BRANCHES := {
	"aeug": {
		"name": "AEUG",
		"conditions": {"flags": ["aeug_contact"], "trust_min": 60.0},
	},
	"ghost_track": {
		"name": "GHOST TRACK",
		"conditions": {"flags": ["ghost_track_found"], "evidence": ["ev_ghost_track"]},
	},
	"procedural_justice": {
		"name": "程序正义",
		"conditions": {"flags": ["procedural_justice"], "reputation_min": 60.0},
	},
	"misplaced_trust": {
		"name": "错付",
		"conditions": {"flags": ["misplaced_trust"], "trust_min": 70.0},
	},
	"silence": {
		"name": "守口如瓶",
		"conditions": {"flags": ["silence_pact"], "threat_max": 3.0},
	},
}

const DEFAULTS := {
	"trust": 50.0,
	"morality": 0.0,
	"reputation": 50.0,
	"threat": 1.0,
	"chapter": "prelude",
	"phase": "prelude",
}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var flags: Dictionary = {}          # name -> scalar
var evidence_ids: Array = []        # 唯一字符串数组
var choices: Array = []             # [{choice_id,t_s,chapter,phase,meta}]
var trust := 50.0
var morality := 0.0
var reputation := 50.0
var threat := 1.0
var chapter := "prelude"
var phase := "prelude"
var t_s := 0.0
var revision := 1

var _initial: Dictionary = {}
var _choice_ids: Dictionary = {}

func _init(seed := {}) -> void:
	setup(seed)

# ── setup / 初始 ────────────────────────────────────────────────

## seed 可含：flags/evidence_ids/choices/trust/morality/reputation/threat/
## chapter/phase/t_s；不合法则 setup 失败（不静默）。
func setup(seed := {}) -> bool:
	var s: Dictionary = seed if seed is Dictionary else {}
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	flags = {}
	evidence_ids = []
	choices = []
	_choice_ids = {}
	t_s = float(s.get("t_s", 0.0))
	trust = float(s.get("trust", DEFAULTS["trust"]))
	morality = float(s.get("morality", DEFAULTS["morality"]))
	reputation = float(s.get("reputation", DEFAULTS["reputation"]))
	threat = float(s.get("threat", DEFAULTS["threat"]))
	chapter = String(s.get("chapter", DEFAULTS["chapter"]))
	phase = String(s.get("phase", DEFAULTS["phase"]))
	revision = 1
	# flags
	if s.get("flags") is Dictionary:
		for raw_k in (s.get("flags") as Dictionary).keys():
			var k := String(raw_k)
			var v = (s.get("flags") as Dictionary)[raw_k]
			if not _id_ok(k):
				errors.append("precondition: flag 名非法：" + k)
			elif not _scalar(v):
				errors.append("precondition: flag 值必须是标量：" + k)
			else:
				flags[k] = v
	elif s.has("flags"):
		errors.append("precondition: flags 必须是对象")
	# evidence
	if s.get("evidence_ids") is Array:
		for raw_e in (s.get("evidence_ids") as Array):
			var eid := String(raw_e)
			if not _id_ok(eid):
				errors.append("precondition: evidence id 非法：" + eid)
			elif evidence_ids.has(eid):
				errors.append("precondition: 证据重复：" + eid)
			else:
				evidence_ids.append(eid)
		evidence_ids.sort()
	elif s.has("evidence_ids"):
		errors.append("precondition: evidence_ids 必须是数组")
	# choices
	if s.get("choices") is Array:
		for raw_c in (s.get("choices") as Array):
			if not (raw_c is Dictionary):
				errors.append("precondition: choice 项必须是对象")
				continue
			var c: Dictionary = raw_c
			var cid := String(c.get("choice_id", ""))
			if cid == "" or _choice_ids.has(cid):
				errors.append("precondition: choice_id 非法/重复：" + cid)
				continue
			_choice_ids[cid] = true
			choices.append(_norm_choice(cid, c))
	# 数值/章节/相位
	_validate_stats("precondition", errors)
	if not (phase in PHASES):
		errors.append("precondition: phase 非法：" + phase)
	if chapter.strip_edges() == "":
		errors.append("precondition: chapter 不能为空")
	_initial = {
		"flags": flags.duplicate(true), "evidence_ids": evidence_ids.duplicate(),
		"choices": choices.duplicate(true), "trust": trust, "morality": morality,
		"reputation": reputation, "threat": threat, "chapter": chapter,
		"phase": phase, "t_s": t_s,
	}
	if not errors.is_empty():
		return false
	ready = true
	return true

func _norm_choice(cid: String, c: Dictionary) -> Dictionary:
	return {
		"choice_id": cid,
		"t_s": float(c.get("t_s", t_s)),
		"chapter": String(c.get("chapter", chapter)),
		"phase": String(c.get("phase", phase)),
		"meta": (c.get("meta", {}) as Dictionary).duplicate(true) if c.get("meta") is Dictionary else {},
	}

# ── flags ───────────────────────────────────────────────────────

func set_flag(flag: String, value = true) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not _id_ok(flag):
		return _fail("invalid_flag", "precondition: flag 名非法：" + flag)
	if not _scalar(value):
		return _fail("invalid_value", "precondition: flag 值必须是标量")
	var existed := flags.has(flag)
	flags[flag] = value
	_touch()
	return {"ok": true, "flag": flag, "value": value, "changed": not existed or _changed,
		"revision": revision}

## 未知 flag 清除拒绝（不静默）。
func clear_flag(flag: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not flags.has(flag):
		return _fail("unknown_flag", "precondition: 未知 flag 不能清除：" + flag)
	flags.erase(flag)
	_touch()
	return {"ok": true, "flag": flag, "revision": revision}

func has_flag(flag: String) -> bool:
	return flags.has(flag)

func flag_value(flag: String, fallback = null) -> Variant:
	return flags.get(flag, fallback)

# ── evidence ────────────────────────────────────────────────────

## 证据唯一；重复/非法 id 拒绝。
func add_evidence(evidence_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not _id_ok(evidence_id):
		return _fail("invalid_evidence", "precondition: evidence id 非法：" + evidence_id)
	if evidence_ids.has(evidence_id):
		return _fail("duplicate_evidence", "precondition: 证据已存在：" + evidence_id)
	evidence_ids.append(evidence_id)
	evidence_ids.sort()
	_touch()
	return {"ok": true, "evidence_id": evidence_id, "count": evidence_ids.size(),
		"revision": revision}

func has_evidence(evidence_id: String) -> bool:
	return evidence_ids.has(evidence_id)

# ── choices ─────────────────────────────────────────────────────

## 记录选择（choice_id 唯一）；未知/重复/非法 id 拒绝。
func record_choice(choice_id: String, meta := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not _id_ok(choice_id):
		return _fail("invalid_choice", "precondition: choice_id 非法：" + choice_id)
	if _choice_ids.has(choice_id):
		return _fail("duplicate_choice", "precondition: choice 已记录：" + choice_id)
	var rec := {
		"choice_id": choice_id, "t_s": t_s, "chapter": chapter, "phase": phase,
		"meta": (meta as Dictionary).duplicate(true) if meta is Dictionary else {},
	}
	_choice_ids[choice_id] = true
	choices.append(rec)
	_touch()
	return {"ok": true, "choice": rec.duplicate(true), "count": choices.size(),
		"revision": revision}

func has_choice(choice_id: String) -> bool:
	return _choice_ids.has(choice_id)

# ── 数值（带边界）─────────────────────────────────────────────

func adjust_trust(delta: float) -> Dictionary:
	return _adjust("trust", delta, TRUST_MIN, TRUST_MAX)

func adjust_morality(delta: float) -> Dictionary:
	return _adjust("morality", delta, MORALITY_MIN, MORALITY_MAX)

func adjust_reputation(delta: float) -> Dictionary:
	return _adjust("reputation", delta, REPUTATION_MIN, REPUTATION_MAX)

func adjust_threat(delta: float) -> Dictionary:
	return _adjust("threat", delta, THREAT_MIN, THREAT_MAX)

func _adjust(stat: String, delta: float, lo: float, hi: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not is_finite(delta):
		return _fail("invalid_delta", "precondition: delta 必须是有限数")
	var before := float(get(stat))
	var after := clampf(before + delta, lo, hi)
	set(stat, after)
	_touch()
	return {"ok": true, "stat": stat, "before": before, "after": after,
		"delta": after - before, "clamped": absf(after - (before + delta)) > 1.0e-9,
		"revision": revision}

# ── chapter / phase / time ─────────────────────────────────────

func set_chapter(new_chapter: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if new_chapter.strip_edges() == "":
		return _fail("invalid_chapter", "precondition: chapter 不能为空")
	chapter = new_chapter
	_touch()
	return {"ok": true, "chapter": chapter, "revision": revision}

func set_phase(new_phase: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not (new_phase in PHASES):
		return _fail("invalid_phase", "precondition: phase 非法：" + new_phase)
	phase = new_phase
	_touch()
	return {"ok": true, "phase": phase, "revision": revision}

## 时间只允许向前（DbC：time/version 单调）。
func set_time(new_t_s: float) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not is_finite(new_t_s) or new_t_s < 0.0:
		return _fail("invalid_time", "precondition: t_s 必须有限且 >=0")
	if new_t_s + 1.0e-9 < t_s:
		return _fail("time_backwards", "precondition: 时间不允许回退")
	t_s = new_t_s
	_touch()
	return {"ok": true, "t_s": t_s, "revision": revision}

# ── 分支 gate ───────────────────────────────────────────────────

## 条件（AND，全部满足才 passed）：
## flags[]/flags_any[]/flags_not[]、evidence[]/evidence_any[]、choices[]、
## trust_min/max、morality_min/max、reputation_min/max、threat_min/max、
## chapter/chapter_in[]、phase/phase_in[]。
func gate(conditions = {}) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not (conditions is Dictionary):
		return _fail("invalid_conditions", "precondition: conditions 必须是对象")
	var c: Dictionary = conditions
	var failed: Array[String] = []
	var details := {}
	var unknown_keys: Array[String] = []
	var known := ["flags", "flags_any", "flags_not", "evidence", "evidence_any",
		"choices", "trust_min", "trust_max", "morality_min", "morality_max",
		"reputation_min", "reputation_max", "threat_min", "threat_max",
		"chapter", "chapter_in", "phase", "phase_in"]
	for raw_k in c.keys():
		if not (String(raw_k) in known):
			unknown_keys.append(String(raw_k))
	if not unknown_keys.is_empty():
		return _fail("unknown_condition", "precondition: 未知 gate 条件：" + str(unknown_keys))
	# flags
	for name in _str_list(c.get("flags", []), "flags", failed):
		if not flags.has(name):
			failed.append("flag_missing:" + name)
		else:
			details["flag:" + name] = flags[name]
	for name in _str_list(c.get("flags_any", []), "flags_any", failed):
		pass
	if c.has("flags_any"):
		var any_ok := false
		for name in _str_list(c.get("flags_any"), "flags_any", failed):
			if flags.has(name):
				any_ok = true
		if not any_ok:
			failed.append("flags_any_none")
	for name in _str_list(c.get("flags_not", []), "flags_not", failed):
		if flags.has(name):
			failed.append("flag_present:" + name)
	# evidence
	for eid in _str_list(c.get("evidence", []), "evidence", failed):
		if not evidence_ids.has(eid):
			failed.append("evidence_missing:" + eid)
	if c.has("evidence_any"):
		var ev_ok := false
		for eid in _str_list(c.get("evidence_any"), "evidence_any", failed):
			if evidence_ids.has(eid):
				ev_ok = true
		if not ev_ok:
			failed.append("evidence_any_none")
	# choices
	for cid in _str_list(c.get("choices", []), "choices", failed):
		if not _choice_ids.has(cid):
			failed.append("choice_missing:" + cid)
	# stats
	_gate_minmax(c, "trust", trust, failed, details)
	_gate_minmax(c, "morality", morality, failed, details)
	_gate_minmax(c, "reputation", reputation, failed, details)
	_gate_minmax(c, "threat", threat, failed, details)
	# chapter/phase
	if c.has("chapter") and chapter != String(c.get("chapter", "")):
		failed.append("chapter_mismatch")
	if c.has("chapter_in"):
		if not (chapter in _str_list(c.get("chapter_in"), "chapter_in", failed)):
			failed.append("chapter_not_in")
	if c.has("phase") and phase != String(c.get("phase", "")):
		failed.append("phase_mismatch")
	if c.has("phase_in"):
		if not (phase in _str_list(c.get("phase_in"), "phase_in", failed)):
			failed.append("phase_not_in")
	var passed := failed.is_empty()
	return {"ok": true, "passed": passed, "failed": failed, "details": details,
		"condition_count": c.size(), "errors": []}

func _gate_minmax(c: Dictionary, stat: String, value: float, failed: Array[String],
		details: Dictionary) -> void:
	var min_key := stat + "_min"
	var max_key := stat + "_max"
	if c.has(min_key):
		if float(c.get(min_key)) > value + 1.0e-9:
			failed.append(stat + "_below_min")
	details[stat] = value
	if c.has(max_key):
		if float(c.get(max_key)) < value - 1.0e-9:
			failed.append(stat + "_above_max")

func _str_list(raw, label: String, failed: Array[String]) -> Array:
	if not (raw is Array):
		failed.append(label + "_not_array")
		return []
	var out: Array = []
	for item in (raw as Array):
		if not (item is String):
			failed.append(label + "_not_string")
			continue
		out.append(String(item))
	return out

## 评估单个数据化分支（AEUG/GHOST TRACK/程序正义/错付/守口如瓶）。
func evaluate_branch(branch_id: String) -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: StoryState 未初始化")
	if not BRANCHES.has(branch_id):
		return _fail("unknown_branch", "precondition: 未知分支：" + branch_id)
	var b: Dictionary = BRANCHES[branch_id]
	var res := gate(b.get("conditions", {}))
	res["branch_id"] = branch_id
	res["branch_name"] = String(b.get("name", branch_id))
	res["passed"] = bool(res.get("passed", false))
	return res

## 全部分支（按 BRANCHES 声明顺序；只读结果）。
func evaluate_branches() -> Array:
	var out: Array = []
	for id in BRANCHES.keys():
		out.append(evaluate_branch(String(id)))
	return out

func branch_ids() -> Array:
	return BRANCHES.keys()

# ── DbC / 快照 ──────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not is_finite(trust) or trust < TRUST_MIN or trust > TRUST_MAX:
		v.append("trust 越界")
	if not is_finite(morality) or morality < MORALITY_MIN or morality > MORALITY_MAX:
		v.append("morality 越界")
	if not is_finite(reputation) or reputation < REPUTATION_MIN or reputation > REPUTATION_MAX:
		v.append("reputation 越界")
	if not is_finite(threat) or threat < THREAT_MIN or threat > THREAT_MAX:
		v.append("threat 越界")
	if not is_finite(t_s) or t_s < 0.0:
		v.append("t_s 非法")
	if revision < 1:
		v.append("revision <1")
	if not (phase in PHASES):
		v.append("phase 非法")
	if chapter.strip_edges() == "":
		v.append("chapter 为空")
	if evidence_ids.size() != _unique_count(evidence_ids):
		v.append("evidence 不唯一")
	if choices.size() != _choice_ids.size():
		v.append("choices 不与索引一致")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

## 只读 VM（深拷贝）。
func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"ready": ready,
		"revision": revision,
		"t_s": t_s,
		"chapter": chapter,
		"phase": phase,
		"flags": flags.duplicate(true),
		"evidence_ids": evidence_ids.duplicate(),
		"choices": choices.duplicate(true),
		"trust": trust,
		"morality": morality,
		"reputation": reputation,
		"threat": threat,
		"ranges": {
			"trust": [TRUST_MIN, TRUST_MAX],
			"morality": [MORALITY_MIN, MORALITY_MAX],
			"reputation": [REPUTATION_MIN, REPUTATION_MAX],
			"threat": [THREAT_MIN, THREAT_MAX],
		},
		"branches": evaluate_branches(),
		"contracts": check_contracts(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"contract_errors": contract_errors.duplicate(),
	}

func vm() -> Dictionary:
	return snapshot()

func to_json() -> String:
	return JSON.stringify(snapshot())

# ── save / load / reset ─────────────────────────────────────────

func save_state() -> String:
	return JSON.stringify({
		"schema": SCHEMA,
		"version": VERSION,
		"revision": revision,
		"t_s": t_s,
		"chapter": chapter,
		"phase": phase,
		"flags": flags.duplicate(true),
		"evidence_ids": evidence_ids.duplicate(),
		"choices": choices.duplicate(true),
		"trust": trust,
		"morality": morality,
		"reputation": reputation,
		"threat": threat,
	})

## 从 save_state JSON 或 Dictionary 恢复；失败不改变现有状态。
func load(data) -> Dictionary:
	var d: Dictionary = {}
	if data is String:
		var parsed = JSON.parse_string(data)
		if not (parsed is Dictionary):
			return _load_fail("invalid_json", "load: JSON 无效")
		d = parsed
	elif data is Dictionary:
		d = (data as Dictionary).duplicate(true)
	else:
		return _load_fail("invalid_data", "load: 需要 JSON 字符串或对象")
	if String(d.get("schema", "")) != SCHEMA:
		return _load_fail("invalid_schema", "load: schema 无效")
	var ver := String(d.get("version", ""))
	if ver != VERSION:
		if _version_gt(ver, VERSION):
			return _load_fail("unsupported_future_version", "load: 版本高于当前：" + ver)
		return _load_fail("unsupported_version", "load: 不支持的版本：" + ver)
	# 先按临时 seed 校验，再写入
	var seed := {
		"flags": d.get("flags", {}), "evidence_ids": d.get("evidence_ids", []),
		"choices": d.get("choices", []), "trust": d.get("trust", DEFAULTS["trust"]),
		"morality": d.get("morality", DEFAULTS["morality"]),
		"reputation": d.get("reputation", DEFAULTS["reputation"]),
		"threat": d.get("threat", DEFAULTS["threat"]),
		"chapter": d.get("chapter", DEFAULTS["chapter"]),
		"phase": d.get("phase", DEFAULTS["phase"]),
		"t_s": d.get("t_s", 0.0),
	}
	var probe_state = get_script().new(seed)
	if not probe_state.ready:
		var errs: Array = probe_state.errors.duplicate()
		errors.append_array(errs)
		return {"ok": false, "errors": errs, "reason": "invalid_state"}
	flags = probe_state.flags.duplicate(true)
	evidence_ids = probe_state.evidence_ids.duplicate()
	choices = probe_state.choices.duplicate(true)
	_choice_ids = probe_state._choice_ids.duplicate()
	trust = probe_state.trust
	morality = probe_state.morality
	reputation = probe_state.reputation
	threat = probe_state.threat
	chapter = probe_state.chapter
	phase = probe_state.phase
	t_s = probe_state.t_s
	revision = int(d.get("revision", 1))
	_initial = probe_state._initial.duplicate(true)
	ready = true
	return {"ok": true, "errors": [], "revision": revision}

func _load_fail(reason: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": reason, "errors": [msg]}

func reset() -> Dictionary:
	setup(_initial)
	return {"ok": ready, "revision": revision}

# ── 内部 ────────────────────────────────────────────────────────

var _changed := false

func _touch() -> void:
	revision += 1
	_changed = true

func _validate_stats(prefix: String, out: Array[String]) -> void:
	if not is_finite(trust) or trust < TRUST_MIN or trust > TRUST_MAX:
		out.append(prefix + ": trust 必须在 [0,100]")
	if not is_finite(morality) or morality < MORALITY_MIN or morality > MORALITY_MAX:
		out.append(prefix + ": morality 必须在 [-100,100]")
	if not is_finite(reputation) or reputation < REPUTATION_MIN or reputation > REPUTATION_MAX:
		out.append(prefix + ": reputation 必须在 [0,100]")
	if not is_finite(threat) or threat < THREAT_MIN or threat > THREAT_MAX:
		out.append(prefix + ": threat 必须在 [0,5]")
	if not is_finite(t_s) or t_s < 0.0:
		out.append(prefix + ": t_s 必须有限且 >=0")

func _fail(reason: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	push_error("StoryState: " + msg)
	return {"ok": false, "reason": reason, "errors": [msg],
		"contract_errors": contract_errors.duplicate()}

func _id_ok(id: String) -> bool:
	var re := RegEx.new()
	re.compile(ID_PATTERN)
	return re.search(id) != null

func _scalar(v) -> bool:
	return (v is String) or (v is bool) or (v is int) or (v is float)

func _unique_count(arr: Array) -> int:
	var seen := {}
	for raw in arr:
		seen[raw] = true
	return seen.size()

func _version_gt(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	if pa.size() != 3 or pb.size() != 3:
		return false
	for i in range(3):
		if not String(pa[i]).is_valid_int() or not String(pb[i]).is_valid_int():
			return false
		if int(pa[i]) > int(pb[i]):
			return true
		if int(pa[i]) < int(pb[i]):
			return false
	return false
