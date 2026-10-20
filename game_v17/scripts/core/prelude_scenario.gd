extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3S：PreludeScenario（序章专用场景内容；新文件）
#
# - 内容：apsis/harmattan/ferry/watchtower/deepwell/ceres_2/av_4412/
#   l1_station/chronos；每实体 batch/kind/side/identity/pos/vel/
#   transponder_profile/light_capable/facility_id；
# - 应答机 profiles（序章补充 ferry/watchtower/deepwell/av_4412；共享
#   apsis/harmattan/l1_station/chronos/ceres_2_demo 来自 transponder 内容）；
# - 灯语码（谷神-2 应急/通用询问确认）；触发 ceres_no_reply/av4412_arrival/
#   chronos_unrest；facility 绑定 L1-05；
# - 与 Transponder/Signal/Facility 内容做引用校验；生成 GameSession boot config；
# - 只读场景内容：不写 world/UI/V15。
# ═══════════════════════════════════════════════════════════════════

const FacilityRegistryScript := preload("res://scripts/core/facility_registry.gd")
const TransponderServiceScript := preload("res://scripts/core/transponder_service.gd")

const SCHEMA := "v17.prelude_scenario.v1"
const VERSION := "1.0.0"
const DEFAULT_CONTENT := "res://framework/content/scenario_prologue.json"
const ENTITY_KINDS := ["ship", "station", "port", "fuel", "tank", "otc", "relay"]
const SIDES := ["friend", "neutral", "hostile", "unknown", "ueg", "ocu", "mixed"]
const IDENTITIES := ["unknown", "friend", "neutral", "suspect", "hostile", "station"]
const MODES := ["mode_a", "mode_c", "mode_s", "mode_5", "station_beacon", "adsb_like"]
const STATUSES := ["normal", "off", "faulty", "captured", "spoofed", "crypto_fail",
	"expired", "no_reply", "wrong_code"]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var refs: Dictionary = {}
var entities: Array = []
var scenario_profiles: Array = []
var triggers: Array = []
var light_codes: Dictionary = {}
var merged_profiles: Array = []
var merged_codes: Dictionary = {}
var facility_registry = null
var _entities_by_id: Dictionary = {}
var _triggers_by_id: Dictionary = {}
var _profiles_by_id: Dictionary = {}
var _codes_by_id: Dictionary = {}
var _external_profiles: Array = []

func _init(cfg := {}) -> void:
	setup(cfg)

func setup(cfg := {}) -> bool:
	var c: Dictionary = cfg if cfg is Dictionary else {}
	content_path = str(c.get("content_path", DEFAULT_CONTENT))
	content = {}
	if c.get("content") is Dictionary and not (c.get("content") as Dictionary).is_empty():
		content = (c.get("content") as Dictionary).duplicate(true)
	else:
		content = _read_json(content_path)
	if content.is_empty():
		errors.append("序章内容不可读：" + content_path)
		ready = false
		return false
	return load_data(content)

func load_content(path := DEFAULT_CONTENT) -> bool:
	var d: Dictionary = _read_json(path)
	if d.is_empty():
		errors.append("序章内容不可读/JSON 无效：" + path)
		ready = false
		return false
	content_path = path
	return load_data(d)

func load_data(value: Variant) -> bool:
	if not (value is Dictionary):
		errors.append("序章内容必须是对象")
		# 原子：已有有效场景时保留旧状态
		return false
	var v: Dictionary = validate(value)
	if not bool(v.get("ok", false)):
		errors.clear()
		for e in (v.get("errors", []) as Array):
			errors.append("prelude: " + str(e))
		# 原子：已有有效场景时失败保留旧内容/ready
		return false
	_apply(value as Dictionary)
	ready = true
	return true

# ── 校验 ───────────────────────────────────────────────────────

func validate(value: Variant) -> Dictionary:
	var errs: Array[String] = []
	if not (value is Dictionary):
		return {"ok": false, "errors": ["内容必须是对象"]}
	var d: Dictionary = value
	if str(d.get("schema", "")) != SCHEMA:
		errs.append("schema 必须为 " + SCHEMA)
	if str(d.get("version", "")) != VERSION:
		errs.append("version 必须为 " + VERSION)
	var refs_in: Dictionary = d.get("refs", {}) if d.get("refs") is Dictionary else {}
	if refs_in.is_empty():
		errs.append("refs 缺失")
	# 实体
	var ents = d.get("entities", null)
	if not (ents is Array) or (ents as Array).is_empty():
		errs.append("entities 必须为非空数组")
		return {"ok": false, "errors": errs}
	var ids: Dictionary = {}
	for raw in (ents as Array):
		if not (raw is Dictionary):
			errs.append("entity 非对象")
			continue
		var e: Dictionary = raw
		var id := str(e.get("id", ""))
		if id == "" or id.strip_edges() != id:
			errs.append("entity id 非法")
		elif ids.has(id):
			errs.append("entity id 重复：" + id)
		ids[id] = true
		var kind := str(e.get("kind", ""))
		if not (kind in ENTITY_KINDS):
			errs.append("entity %s kind 非法：%s" % [id, kind])
		for k in ["batch", "side", "identity", "transponder_profile"]:
			if str(e.get(k, "")) == "":
				errs.append("entity %s 缺少 %s" % [id, k])
		if not (str(e.get("side", "")) in SIDES):
			errs.append("entity %s side 非法" % id)
		if not (str(e.get("identity", "")) in IDENTITIES):
			errs.append("entity %s identity 非法" % id)
		for k2 in ["pos_km", "vel_kmps"]:
			var arr = e.get(k2, null)
			if not (arr is Array) or (arr as Array).size() != 3:
				errs.append("entity %s %s 必须为三维数组" % [id, k2])
			else:
				for x in (arr as Array):
					if not (x is int or x is float) or not is_finite(float(x)):
						errs.append("entity %s %s 非有限" % [id, k2])
		_ok_bool(errs, e, "light_capable", id)
	# refs 内容
	var fac_path := str(refs_in.get("facilities_content", ""))
	var facilities = null
	var fac_reg = null
	if fac_path == "":
		errs.append("refs.facilities_content 缺失")
	elif not FileAccess.file_exists(fac_path):
		errs.append("facility 内容不存在：" + fac_path)
	else:
		facilities = _read_json(fac_path)
		if not (facilities is Dictionary) or str((facilities as Dictionary).get("schema", "")) != \
				"v17.facilities_system.v1":
			errs.append("facility 内容 schema 非法")
		else:
			fac_reg = FacilityRegistryScript.new({"content": facilities})
			if not bool(fac_reg.ready):
				errs.append("facility 内容校验失败：" + str(fac_reg.errors))
	# transponder 外部内容
	var txp_path := str(refs_in.get("transponders_content", ""))
	var external: Dictionary = {}
	if txp_path == "":
		errs.append("refs.transponders_content 缺失")
	elif not FileAccess.file_exists(txp_path):
		errs.append("transponder 内容不存在：" + txp_path)
	else:
		external = _read_json(txp_path)
		if not (external is Dictionary) or str(external.get("schema", "")) != \
				"v17.transponders_prologue.v1":
			errs.append("transponder 内容 schema 非法")
	# 序章补充 profiles
	var extra = d.get("transponder_profiles", null)
	if not (extra is Array) or (extra as Array).is_empty():
		errs.append("transponder_profiles 必须为非空数组")
		extra = []
	var extra_ids: Dictionary = {}
	for raw_p in (extra as Array):
		if not (raw_p is Dictionary):
			errs.append("transponder profile 非对象")
			continue
		var p: Dictionary = raw_p
		var pid := str(p.get("profile_id", ""))
		if pid == "":
			errs.append("transponder profile_id 为空")
		elif extra_ids.has(pid):
			errs.append("transponder profile_id 重复：" + pid)
		extra_ids[pid] = true
		if not (str(p.get("entity_type", "")) in ENTITY_KINDS):
			errs.append("profile %s entity_type 非法" % pid)
		if str(p.get("entity_id", "")) == "" and str(p.get("facility_id", "")) == "":
			errs.append("profile %s 缺 entity_id/facility_id" % pid)
		for k3 in ["transponder_code", "registration_code"]:
			if str(p.get(k3, "")) == "":
				errs.append("profile %s 缺 %s" % [pid, k3])
		var modes = p.get("modes", null)
		if not (modes is Array) or (modes as Array).is_empty():
			errs.append("profile %s modes 为空" % pid)
		else:
			for mm in (modes as Array):
				if not (str(mm) in MODES):
					errs.append("profile %s mode 非法" % pid)
			if not (str(p.get("default_mode", "")) in (modes as Array)):
				errs.append("profile %s default_mode 非法" % pid)
		if not (str(p.get("status", "")) in STATUSES):
			errs.append("profile %s status 非法" % pid)
	# 合并外部 + 补充 profiles（用于引用与 boot）
	var merged: Array = []
	if external.get("profiles") is Array:
		for raw_x in (external.get("profiles") as Array):
			if raw_x is Dictionary:
				merged.append((raw_x as Dictionary).duplicate(true))
	for raw_e in (extra as Array):
		if raw_e is Dictionary:
			merged.append((raw_e as Dictionary).duplicate(true))
	var merged_ids: Dictionary = {}
	for raw_m in merged:
		if raw_m is Dictionary:
			var mid := str((raw_m as Dictionary).get("profile_id", ""))
			if mid != "":
				if merged_ids.has(mid):
					errs.append("合并后 profile_id 重复：" + str(mid))
				merged_ids[mid] = true
	# 实体 profile 引用
	for raw_e2 in (ents as Array):
		if raw_e2 is Dictionary:
			var e2: Dictionary = raw_e2
			var pid2 := str(e2.get("transponder_profile", ""))
			if pid2 != "" and not merged_ids.has(pid2):
				errs.append("entity %s transponder_profile 不存在：%s" % [str(e2.get("id", "")), pid2])
	# facility 绑定
	for raw_e3 in (ents as Array):
		if not (raw_e3 is Dictionary):
			continue
		var e3: Dictionary = raw_e3
		var fid := str(e3.get("facility_id", ""))
		if fid == "":
			continue
		if fac_reg == null or not bool(fac_reg.ready):
			errs.append("entity %s facility 绑定但 facility registry 不可用" % str(e3.get("id", "")))
		elif fac_reg.facility(fid).is_empty():
			errs.append("entity %s facility 不存在：%s" % [str(e3.get("id", "")), fid])
	# 灯语码（外部 + 场景）
	var lc = d.get("light_codes", null)
	if not (lc is Dictionary):
		errs.append("light_codes 必须是对象")
	else:
		var merged_codes_v: Dictionary = _merge_codes(refs_in, lc as Dictionary, errs)
		if not merged_codes_v.is_empty():
			# 校验每个 code 被场景引用（若触发引用）
			var code_ids: Dictionary = {}
			for c in (merged_codes_v.get("codes", []) as Array):
				if c is Dictionary:
					code_ids[str((c as Dictionary).get("id", ""))] = true
			var trs = d.get("triggers", [])
			if trs is Array:
				for tr in (trs as Array):
					if tr is Dictionary and str((tr as Dictionary).get("light_code", "")) != "":
						if not code_ids.has(str((tr as Dictionary).get("light_code", ""))):
							errs.append("trigger %s light_code 不存在：%s" % [
								str((tr as Dictionary).get("trigger_id", "")),
								str((tr as Dictionary).get("light_code", ""))])
	# 触发
	var trs2 = d.get("triggers", null)
	if not (trs2 is Array) or (trs2 as Array).is_empty():
		errs.append("triggers 必须为非空数组")
	else:
		var tids: Dictionary = {}
		for raw_t in (trs2 as Array):
			if not (raw_t is Dictionary):
				errs.append("trigger 非对象")
				continue
			var tr3: Dictionary = raw_t
			var tid3 := str(tr3.get("trigger_id", ""))
			if tid3 == "":
				errs.append("trigger_id 为空")
			elif tids.has(tid3):
				errs.append("trigger_id 重复：" + tid3)
			tids[tid3] = true
			if str(tr3.get("event", "")) == "":
				errs.append("trigger %s event 为空" % tid3)
			var target := str(tr3.get("target_id", ""))
			if target == "" or not ids.has(target):
				errs.append("trigger %s target 不存在：%s" % [tid3, target])
			if tr3.has("source_entity_id") and not ids.has(str(tr3.get("source_entity_id", ""))):
				errs.append("trigger %s source_entity 不存在" % tid3)
			if tr3.has("condition") and not (tr3.get("condition") is Dictionary):
				errs.append("trigger %s condition 必须是对象" % tid3)
			if str(tr3.get("story_flag", "")) == "":
				errs.append("trigger %s story_flag 为空" % tid3)
	# 合并 profiles 通过 TransponderService 校验（设施可用时）
	if merged_profiles_ok(merged, fac_reg, errs):
		pass
	# 场景 light codes 基本 schema
	if not (lc is Dictionary) or str((lc as Dictionary).get("schema", "")) != "light_codes.v1":
		errs.append("light_codes schema 必须为 light_codes.v1")
	return {"ok": errs.is_empty(), "errors": errs}

func merged_profiles_ok(merged: Array, fac_reg, errs: Array[String]) -> bool:
	if merged.is_empty():
		errs.append("合并 profile 为空")
		return false
	var content := {"schema": "v17.transponders_prologue.v1", "version": "1.0.0",
		"profiles": merged}
	var cfg := {"content": content}
	if fac_reg != null and bool(fac_reg.ready):
		cfg["facility_registry"] = fac_reg
	var ts = TransponderServiceScript.new(cfg)
	if not bool(ts.ready):
		for e in (ts.errors as Array):
			errs.append("transponder 内容校验失败：" + str(e))
		return false
	return true

func _ok_bool(errs: Array[String], e: Dictionary, key: String, id: String) -> void:
	if not (e.get(key) is bool):
		errs.append("entity %s %s 必须是 bool" % [id, key])

func _merge_codes(refs_in: Dictionary, local: Dictionary, errs: Array[String]) -> Dictionary:
	var codes: Array = []
	var ext_path := str(refs_in.get("light_codes_content", ""))
	if ext_path != "":
		if not FileAccess.file_exists(ext_path):
			errs.append("light codes 内容不存在：" + ext_path)
		else:
			var ext = _read_json(ext_path)
			if ext is Dictionary and (ext.get("codes") is Array):
				for c in (ext.get("codes") as Array):
					codes.append((c as Dictionary).duplicate(true) if c is Dictionary else c)
	if local.get("codes") is Array:
		for c2 in (local.get("codes") as Array):
			codes.append((c2 as Dictionary).duplicate(true) if c2 is Dictionary else c2)
	var ids: Dictionary = {}
	for c3 in codes:
		if not (c3 is Dictionary):
			errs.append("light code 非对象")
			continue
		var cid := str((c3 as Dictionary).get("id", ""))
		if cid == "":
			errs.append("light code id 为空")
		elif ids.has(cid):
			errs.append("light code id 重复：" + cid)
		ids[cid] = true
		if String((c3 as Dictionary).get("code", "")).length() != 4:
			errs.append("light code %s 必须四位" % cid)
		if not (str((c3 as Dictionary).get("mode", "")) in ["blink", "steady"]):
			errs.append("light code %s mode 非法" % cid)
		if str((c3 as Dictionary).get("meaning", "")) == "":
			errs.append("light code %s meaning 为空" % cid)
	var defaults: Dictionary = (local.get("defaults", {}) as Dictionary).duplicate(true) \
		if local.get("defaults") is Dictionary else {}
	return {"schema": "light_codes.v1", "title": str(local.get("title", "prologue")),
		"defaults": defaults, "codes": codes}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

func _apply(d: Dictionary) -> void:
	content = d.duplicate(true)
	refs = (d.get("refs", {}) as Dictionary).duplicate(true)
	entities = (d.get("entities", []) as Array).duplicate(true)
	scenario_profiles = (d.get("transponder_profiles", []) as Array).duplicate(true)
	triggers = (d.get("triggers", []) as Array).duplicate(true)
	light_codes = (d.get("light_codes", {}) as Dictionary).duplicate(true)
	_entities_by_id = {}
	for raw in entities:
		if raw is Dictionary:
			_entities_by_id[str((raw as Dictionary).get("id", ""))] = raw
	_triggers_by_id = {}
	for raw_t in triggers:
		if raw_t is Dictionary:
			_triggers_by_id[str((raw_t as Dictionary).get("trigger_id", ""))] = raw_t
	# 外部 transponder profiles
	_external_profiles = []
	var txp_path := str(refs.get("transponders_content", ""))
	if txp_path != "":
		var ext: Dictionary = _read_json(txp_path)
		if ext.get("profiles") is Array:
			_external_profiles = (ext.get("profiles") as Array).duplicate(true)
	merged_profiles = []
	_profiles_by_id = {}
	for raw_p in _external_profiles + scenario_profiles:
		if raw_p is Dictionary:
			var p2: Dictionary = (raw_p as Dictionary).duplicate(true)
			merged_profiles.append(p2)
			_profiles_by_id[str(p2.get("profile_id", ""))] = p2
	# codes
	var dummy: Array[String] = []
	merged_codes = _merge_codes(refs, light_codes, dummy)
	_codes_by_id = {}
	for c in (merged_codes.get("codes", []) as Array):
		if c is Dictionary:
			_codes_by_id[str((c as Dictionary).get("id", ""))] = c
	var fac_path := str(refs.get("facilities_content", ""))
	facility_registry = null
	if fac_path != "":
		facility_registry = FacilityRegistryScript.new({"content_path": fac_path})

# ── 查询 ────────────────────────────────────────────────────────

func entity_ids() -> Array:
	var out: Array = _entities_by_id.keys()
	out.sort()
	return out

func entity(id: String) -> Dictionary:
	return (_entities_by_id.get(id, {}) as Dictionary).duplicate(true)

func profile_ids() -> Array:
	var out: Array = _profiles_by_id.keys()
	out.sort()
	return out

func profile(id: String) -> Dictionary:
	return (_profiles_by_id.get(id, {}) as Dictionary).duplicate(true)

func trigger_ids() -> Array:
	var out: Array = _triggers_by_id.keys()
	out.sort()
	return out

func trigger(id: String) -> Dictionary:
	return (_triggers_by_id.get(id, {}) as Dictionary).duplicate(true)

func triggers_for_event(event: String) -> Array:
	var out: Array = []
	for raw in triggers:
		if raw is Dictionary and str((raw as Dictionary).get("event", "")) == event:
			out.append((raw as Dictionary).duplicate(true))
	return out

func light_code_ids() -> Array:
	var out: Array = _codes_by_id.keys()
	out.sort()
	return out

func light_code(id: String) -> Dictionary:
	return (_codes_by_id.get(id, {}) as Dictionary).duplicate(true)

func facility_for_entity(entity_id: String) -> Dictionary:
	if facility_registry == null:
		return {}
	var e: Dictionary = _entities_by_id.get(entity_id, {}) as Dictionary
	var fid := str(e.get("facility_id", ""))
	if fid == "":
		return {}
	return facility_registry.facility(fid)

func summary() -> Dictionary:
	return {"schema": SCHEMA, "title": str(content.get("title", "")),
		"source": str(content.get("source", "")),
		"entities": entities.size(), "profiles": scenario_profiles.size(),
		"merged_profiles": merged_profiles.size(), "light_codes": _codes_by_id.size(),
		"triggers": triggers.size(), "facility_bound": _facility_bound_entities(),
		"refs": refs.duplicate(true), "writes_v15": false,
		"writes": {"world": false, "ui": false, "v15": false}}

func _facility_bound_entities() -> int:
	var n := 0
	for raw in entities:
		if raw is Dictionary and str((raw as Dictionary).get("facility_id", "")) != "":
			n += 1
	return n

func to_dict() -> Dictionary:
	return content.duplicate(true)

func to_json() -> String:
	return JSON.stringify(to_dict())

## GameSession boot config：entities/facility/transponder/signal；不写 world。
func boot_config() -> Dictionary:
	if not ready:
		return {}
	var seed_entities: Array = []
	for raw in entities:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		seed_entities.append({"id": str(e.get("id", "")),
			"batch": str(e.get("batch", "")), "kind": str(e.get("kind", "")),
			"side": str(e.get("side", "")), "identity": str(e.get("identity", "")),
			"pos_km": (e.get("pos_km", []) as Array).duplicate(),
			"vel_kmps": (e.get("vel_kmps", []) as Array).duplicate(),
			"transponder_profile": str(e.get("transponder_profile", "")),
			"light_capable": bool(e.get("light_capable", true)),
			"facility_id": str(e.get("facility_id", ""))})
	var observer := entity("apsis")
	if observer.is_empty() and entities.size() > 0:
		observer = entity(str((entities[0] as Dictionary).get("id", "")))
	var targets: Array = []
	for raw2 in entities:
		if not (raw2 is Dictionary):
			continue
		var e2: Dictionary = raw2
		targets.append({"id": str(e2.get("id", "")),
			"entity_id": str(e2.get("id", "")),
			"batch": str(e2.get("batch", "")),
			"side": _signal_side(str(e2.get("side", ""))),
			"identity": str(e2.get("identity", "unknown")),
			"pos_km": (e2.get("pos_km", []) as Array).duplicate(),
			"occluded": false, "light_capable": bool(e2.get("light_capable", true)),
			"receiver_facing": true})
	var profiles_content := {"schema": "v17.transponders_prologue.v1",
		"version": "1.0.0", "profiles": merged_profiles.duplicate(true)}
	return {"entities": seed_entities,
		"facility_registry": {"content_path": str(refs.get("facilities_content", ""))},
		"transponder_service": {"content": profiles_content, "jam": 0.0,
			"max_range_km": 20000.0},
		"signal_service": {"observer": {"id": str(observer.get("id", "apsis")),
				"pos_km": (observer.get("pos_km", [0.0, 0.0, 0.0]) as Array).duplicate()},
			"targets": targets, "codes_content": merged_codes.duplicate(true)},
		"prelude": {"scenario": SCHEMA, "title": str(content.get("title", "")),
			"trigger_ids": trigger_ids(), "light_code_ids": light_code_ids()}}

func _signal_side(side: String) -> String:
	var s := side.to_lower()
	if s in ["friend", "ocu", "ueg", "mixed"]:
		return "friend" if s == "friend" else "neutral"
	if s == "neutral":
		return "neutral"
	if s == "hostile":
		return "hostile"
	return "unknown"

# ── DbC ────────────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("scenario 未 ready")
	if entities.is_empty():
		v.append("entities 为空")
	if triggers.is_empty():
		v.append("triggers 为空")
	for tid in trigger_ids():
		var tr: Dictionary = _triggers_by_id[tid]
		if not _entities_by_id.has(str(tr.get("target_id", ""))):
			v.append("trigger %s target 不存在" % str(tid))
		if str(tr.get("light_code", "")) != "" and not _codes_by_id.has(str(tr.get("light_code", ""))):
			v.append("trigger %s light_code 不存在" % str(tid))
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
