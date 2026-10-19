class_name V2Actions
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2-1 动作注册表：动作全部来自内容（content/actions.json），代码不写死清单。
#
#   可用性 available(actor, target, track) 由
#     capability（actor.capabilities） × 目标航迹等级（track.level / target.track_level）
#     × 距离（track.range_km） × 阶段/flag（ctx） 共同决定
#   返回动作数组，每项：
#     {id,label,label_en,available,reason,reason_code,requires_all,requires_any,
#      levels,supported,duration_s,effect,hint,...}
#   不可用时 reason 一定非空，UI 直接显示。
#
#   本框架不模拟武器：L4 武器类动作在内容里 supported=false，永远 available=false。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_PATH := "res://framework/content/actions.json"

static var definitions: Array = []
static var errors: Array[String] = []
static var loaded := false
static var source_path := ""

## 惰性加载默认内容；返回是否成功。
static func ensure_loaded(path: String = DEFAULT_PATH) -> bool:
	if loaded and source_path == path:
		return errors.is_empty()
	return load_file(path)

## 从内容文件加载动作定义。校验失败时保留旧定义并写 errors。
static func load_file(path: String) -> bool:
	source_path = path
	if not FileAccess.file_exists(path):
		errors = ["missing actions content: " + path]
		loaded = true
		return false
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		errors = ["invalid actions json: " + path]
		loaded = true
		return false
	return load_data(parsed, path)

## 从字典加载（测试/内嵌内容用）。
static func load_data(data: Dictionary, source: String = "<memory>") -> bool:
	var errs: Array[String] = []
	var schema := String(data.get("schema", ""))
	if not schema.begins_with("actions"):
		errs.append("actions schema 不匹配: " + schema + "（期望 actions.*）")
	var list: Array = data.get("actions", [])
	if list.is_empty():
		errs.append("actions 列表为空: " + source)
	var ids: Dictionary = {}
	var defs: Array = []
	for i in range(list.size()):
		var raw = list[i]
		if not (raw is Dictionary):
			errs.append("actions[%d]: 不是字典" % i)
			continue
		var d: Dictionary = (raw as Dictionary).duplicate(true)
		var aid := String(d.get("id", ""))
		if aid == "":
			errs.append("actions[%d].id: 不能为空" % i)
			continue
		if ids.has(aid):
			errs.append("actions[%d].id: 重复 %s" % [i, aid])
			continue
		ids[aid] = true
		if String(d.get("label", "")) == "":
			errs.append("actions[%d] (%s).label: 不能为空" % [i, aid])
		for k in ["requires_all", "requires_any", "levels", "phases", "requires_flags", "forbidden_flags"]:
			if d.has(k) and not (d.get(k) is Array):
				errs.append("actions[%d] (%s).%s: 必须是数组" % [i, aid, k])
		if not bool(d.get("supported", true)) and String(d.get("unsupported_reason", "")) == "":
			errs.append("actions[%d] (%s): supported=false 但缺少 unsupported_reason" % [i, aid])
		defs.append(d)
	if not errs.is_empty():
		errors = errs
		loaded = true
		return false
	definitions = defs
	errors = []
	loaded = true
	return true

static func reset() -> void:
	definitions = []
	errors = []
	loaded = false
	source_path = ""

static func definition(action_id: String) -> Dictionary:
	ensure_loaded()
	for raw in definitions:
		var d: Dictionary = raw
		if String(d.get("id", "")) == action_id:
			return d.duplicate(true)
	return {}

static func effect(action_id: String) -> Dictionary:
	var d := definition(action_id)
	return ((d.get("effect", {}) as Dictionary)).duplicate(true)

static func is_supported(action_id: String) -> bool:
	var d := definition(action_id)
	return not d.is_empty() and bool(d.get("supported", true))

## 核心 API：按 actor/target/track 评估每一个动作的可用性。
static func available(actor: V2Entity, target: V2Entity = null, track: V2Track = null,
		ctx: Dictionary = {}) -> Array:
	ensure_loaded()
	var out: Array = []
	for raw in definitions:
		var d: Dictionary = raw
		out.append(_evaluate(d, actor, target, track, ctx))
	return out

## 向后兼容别名（V2-0 UI 使用），track 可选。
static func actions_for(actor: V2Entity, target: V2Entity = null, track: V2Track = null,
		ctx: Dictionary = {}) -> Array:
	return available(actor, target, track, ctx)

## 按动作 id 取单个评估结果；动作不存在时返回空字典。
static func available_one(action_id: String, actor: V2Entity, target: V2Entity = null,
		track: V2Track = null, ctx: Dictionary = {}) -> Dictionary:
	var d := definition(action_id)
	if d.is_empty():
		return {}
	return _evaluate(d, actor, target, track, ctx)

static func find(actions: Array, action_id: String) -> Dictionary:
	for raw in actions:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == action_id:
			return raw
	return {}

static func level_name(level: int) -> String:
	return ["L0", "L1", "L2", "L3", "L4"][clampi(level, 0, 4)]

static func _evaluate(def: Dictionary, actor: V2Entity, target: V2Entity,
		track: V2Track, ctx: Dictionary) -> Dictionary:
	var a: Dictionary = def.duplicate(true)
	var ok := true
	var reason := ""
	var code := ""
	var aid := String(a.get("id", ""))

	# 1) 框架明确不支持（武器类）——显式、不隐藏、不伪造。
	if not bool(a.get("supported", true)):
		ok = false
		code = "unsupported"
		reason = String(a.get("unsupported_reason", "未实现"))

	# 2) 执行单元
	if ok and actor == null:
		ok = false
		code = "no_actor"
		reason = "无执行单元"

	# 3) 目标/航迹
	var level := -1
	var track_id := ""
	if track != null:
		level = int(track.level)
		track_id = String(track.id)
	elif target != null:
		level = int(target.track_level)
		track_id = String(target.batch if target.batch != "" else target.id)
	if ok and bool(a.get("track_required", false)) and track == null and target == null:
		ok = false
		code = "no_track"
		reason = "无航迹/目标（先建立接触）"
	if ok and track == null and target == null and not a.get("levels", []).is_empty():
		ok = false
		code = "no_track"
		reason = "无航迹等级数据"

	# 4) 等级（levels 为允许集合；空数组 = 任意等级）
	var levels: Array = a.get("levels", [])
	if ok and not levels.is_empty():
		var ok_level := false
		for raw_lv in levels:
			if int(raw_lv) == level:
				ok_level = true
				break
		if not ok_level:
			ok = false
			code = "level"
			reason = "目标等级不适用（当前 L%d，需要 %s）" % [maxi(level, 0), _levels_text(levels)]

	# 5) 能力
	if ok:
		var req_all: Array = a.get("requires_all", [])
		for raw_cap in req_all:
			if not actor.has(String(raw_cap)):
				ok = false
				code = "capability"
				reason = "缺少能力：" + String(raw_cap)
				break
	if ok:
		var req_any: Array = a.get("requires_any", [])
		if not req_any.is_empty() and not actor.has_any_of(req_any):
			ok = false
			code = "capability"
			reason = "缺少能力（需要其一）：" + ", ".join(req_any)

	# 6) 距离
	if ok and float(a.get("max_range_km", 0.0)) > 0.0:
		var max_km := float(a.get("max_range_km", 0.0))
		var rng_km := -1.0
		if track != null:
			rng_km = float(track.range_km)
		if rng_km < 0.0:
			ok = false
			code = "no_range"
			reason = "无距离数据（需先定位到 L2）"
		elif rng_km > max_km:
			ok = false
			code = "range"
			reason = "超出作用距离（%.0f km > %.0f km）" % [rng_km, max_km]

	# 7) 阶段 / flag（由 mission/world 通过 ctx 传入）
	if ok:
		var phases: Array = a.get("phases", [])
		if not phases.is_empty() and ctx.has("phase") and not (String(ctx.get("phase", "")) in phases):
			ok = false
			code = "phase"
			reason = "当前阶段不可用（%s）" % String(ctx.get("phase", ""))
		var flags: Dictionary = (ctx.get("flags", {}) as Dictionary)
		for raw_f in (a.get("requires_flags", []) as Array):
			if not bool(flags.get(String(raw_f), false)):
				ok = false
				code = "flag"
				reason = "需要前置条件：" + String(raw_f)
				break
		if ok:
			for raw_f in (a.get("forbidden_flags", []) as Array):
				if bool(flags.get(String(raw_f), false)):
					ok = false
					code = "flag"
					reason = "条件已失效：" + String(raw_f)
					break

	if ok:
		reason = ""
		code = ""
	a["available"] = ok
	a["reason"] = reason
	a["reason_code"] = code
	a["target_track_id"] = track_id
	a["target_level"] = level
	return a

static func _levels_text(levels: Array) -> String:
	var parts: Array = []
	for raw in levels:
		parts.append("L%d" % int(raw))
	return "/".join(parts)
