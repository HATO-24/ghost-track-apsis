extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# JC-B00：联合战役多舰队/指挥/情报契约（K0）
#
# 这是**语义校验器**，不是完整 JSON Schema 引擎：
#   * 只校验本契约声明的结构、引用完整性、权限语义、单位与序号范围；
#   * 不做通用 schema 推导、不支持 $ref/oneOf 等 JSON Schema 特性；
#   * 不持有运行态、不写任何服务状态（纯函数）。
#
# 权威划分（详见 docs/contracts/joint_campaign_r2.md）：
#   campaign/scenario → 内容配置；fleet/instance → 编制与部署服务；
#   kinematics → PhysicsWorld；静态舰级 → EntityCatalog/ShipCatalog；
#   observation → 各情报拥有者自己的 TrackTable；event id/seq → EventBus。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.jc.contracts.v1"
const VERSION := 1
const SAFE_INT_MAX := 9007199254740991.0

const DEPLOYMENT_ORDER := ["DRAFT", "VALIDATED", "DEPLOYED"]
const DOMAIN_KINDS := ["player", "ai_ally", "ai_hostile"]
const PLAYER_KNOWN_STATES := ["unknown", "suspected", "confirmed", "disabled"]

# 1 t = 1000 kg（旧舰队名册用 t，PhysicsWorld 用 kg；只允许转换一次）
const KG_PER_TONNE := 1000.0


static func validate(doc: Dictionary) -> Dictionary:
	var errs: Array = []
	var warns: Array = []
	if String(doc.get("schema", "")) != SCHEMA:
		errs.append("schema 必须是 " + SCHEMA)
	var ver = doc.get("version", null)
	if not _is_int(ver) or int(ver) != VERSION:
		errs.append("version 必须是精确整数 %d（收到 %s）" % [VERSION, str(ver)])
	if String(doc.get("campaign_id", "")).strip_edges() == "":
		errs.append("campaign_id 不能为空")
	errs.append_array(_validate_domains(doc.get("command_domains", [])))
	errs.append_array(_validate_fleets(doc.get("fleets", []), doc.get("command_domains", [])))
	var inst_res: Dictionary = _validate_instances(doc.get("instances", []),
		doc.get("fleets", []), doc.get("command_domains", []))
	errs.append_array(inst_res.get("errors", []))
	var idx: Dictionary = inst_res.get("index", {})
	errs.append_array(_validate_deployments(doc.get("deployments", []), idx))
	errs.append_array(_validate_observations(doc.get("observation_shares", []), idx))
	errs.append_array(_validate_commands(doc.get("commands", []), idx,
		doc.get("command_domains", [])))
	errs.append_array(_validate_objectives(doc.get("objectives", []), idx))
	errs.append_array(_validate_ledgers(doc.get("ledgers", []), idx))
	if (doc.get("fleets", []) as Array).size() == 0:
		warns.append("没有任何 fleet；空战役配置")
	return {"ok": errs.is_empty(), "errors": errs, "warnings": warns,
		"schema": SCHEMA, "version": VERSION}


# ── 指挥域 ───────────────────────────────────────────────────────
static func _validate_domains(raw) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["command_domains 必须是数组"]
	if (raw as Array).size() < 3:
		errs.append("至少需要 3 个指挥域（player/ai_ally/ai_hostile）")
	var seen_id: Dictionary = {}
	var seen_ctrl: Dictionary = {}
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("command_domains 项必须是对象")
			continue
		var d: Dictionary = r
		var did := String(d.get("domain_id", ""))
		if did == "":
			errs.append("command_domains.domain_id 不能为空")
			continue
		if seen_id.has(did):
			errs.append("重复 domain_id: " + did)
		seen_id[did] = true
		var kind := String(d.get("kind", ""))
		if not (kind in DOMAIN_KINDS):
			errs.append("domain %s 的 kind 非法: %s" % [did, kind])
		# 阵营（faction）、直控（controller）、情报拥有者必须分开建模
		var ctrl := String(d.get("controller_id", ""))
		if ctrl == "":
			errs.append("domain %s 缺少 controller_id（直控授权必须显式）" % did)
		elif seen_ctrl.has(ctrl):
			errs.append("controller_id 重复（不同域不得共用直控）: " + ctrl)
		seen_ctrl[ctrl] = true
		if String(d.get("intel_owner_id", "")) == "":
			errs.append("domain %s 缺少 intel_owner_id（情报拥有者必须显式）" % did)
		var fac := String(d.get("faction", ""))
		if fac == "":
			errs.append("domain %s 缺少 faction（阵营不等于直控）" % did)
		var roe = d.get("roe", null)
		if not (roe is String) or String(roe) == "":
			errs.append("domain %s 缺少显式 roe 授权" % did)
	return errs


# ── 舰队 ─────────────────────────────────────────────────────────
static func _validate_fleets(raw, domains_raw) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["fleets 必须是数组"]
	var dom_ids: Dictionary = {}
	for d in (domains_raw as Array):
		if d is Dictionary:
			dom_ids[String((d as Dictionary).get("domain_id", ""))] = true
	var seen: Dictionary = {}
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("fleets 项必须是对象")
			continue
		var f: Dictionary = r
		var fid := String(f.get("fleet_id", ""))
		if fid == "":
			errs.append("fleets.fleet_id 不能为空")
			continue
		if seen.has(fid):
			errs.append("重复 fleet_id: " + fid)
		seen[fid] = true
		var did := String(f.get("domain_id", ""))
		if not dom_ids.has(did):
			errs.append("fleet %s 引用未知 domain_id: %s" % [fid, did])
		var roster = f.get("roster", [])
		if not (roster is Array):
			errs.append("fleet %s 的 roster 必须是数组" % fid)
		elif (roster as Array).is_empty():
			errs.append("fleet %s 的 roster 不能为空" % fid)
	return errs


# ── 部署实例 ─────────────────────────────────────────────────────
static func _validate_instances(raw, fleets_raw, domains_raw) -> Dictionary:
	var errs: Array = []
	var index: Dictionary = {}
	if not (raw is Array):
		return {"errors": ["instances 必须是数组"], "index": index}
	var fleet_dom: Dictionary = {}
	for f in (fleets_raw as Array):
		if f is Dictionary:
			fleet_dom[String((f as Dictionary).get("fleet_id", ""))] = \
				String((f as Dictionary).get("domain_id", ""))
	var dom_ids: Dictionary = {}
	for d in (domains_raw as Array):
		if d is Dictionary:
			dom_ids[String((d as Dictionary).get("domain_id", ""))] = true
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("instances 项必须是对象")
			continue
		var it: Dictionary = r
		var eid := String(it.get("entity_instance_id", ""))
		if eid == "":
			errs.append("instances.entity_instance_id 不能为空")
			continue
		if index.has(eid):
			errs.append("重复 entity_instance_id: " + eid)
			continue
		var fid := String(it.get("fleet_id", ""))
		if not fleet_dom.has(fid):
			errs.append("instance %s 引用未知 fleet_id: %s" % [eid, fid])
		var dom := String(it.get("domain_id", ""))
		if not dom_ids.has(dom):
			errs.append("instance %s 引用未知 domain_id: %s" % [eid, dom])
		elif fleet_dom.has(fid) and String(fleet_dom[fid]) != dom:
			# 跨域指挥：实例所属域必须与舰队域一致
			errs.append("跨域指挥：instance %s 的域 %s 与 fleet %s 的域 %s 不一致" % [
				eid, dom, fid, String(fleet_dom[fid])])
		if String(it.get("ship_class_id", "")) == "":
			errs.append("instance %s 缺少 ship_class_id（静态舰级来自 catalog）" % eid)
		var cre = it.get("ship_class_config_revision", null)
		if not _is_int(cre) or int(cre) < 1:
			errs.append("instance %s 的 ship_class_config_revision 必须是正整数" % eid)
		var st := String(it.get("deployment_state", ""))
		if not (st in DEPLOYMENT_ORDER):
			errs.append("instance %s 的 deployment_state 非法: %s" % [eid, st])
		if bool(it.get("selected", false)) == false:
			pass  # 未选择舰不在部署清单由 deployments 段约束
		index[eid] = {"fleet_id": fid, "domain_id": dom,
			"deployment_state": st}
	return {"errors": errs, "index": index}


# ── 部署清单与生命周期 ───────────────────────────────────────────
static func _validate_deployments(raw, index: Dictionary) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["deployments 必须是数组"]
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("deployments 项必须是对象")
			continue
		var d: Dictionary = r
		var eid := String(d.get("entity_instance_id", ""))
		if not index.has(eid):
			errs.append("deployments 引用未部署实例: " + eid)
			continue
		# 只有 DEPLOYED 的实例可进部署清单
		var st := String((index[eid] as Dictionary).get("deployment_state", ""))
		if st != "DEPLOYED":
			errs.append("实例 %s 尚未 DEPLOYED（当前 %s），不能出现在部署清单" % [
				eid, st])
		var from := String(d.get("from_state", ""))
		var to := String(d.get("to_state", ""))
		if not (from in DEPLOYMENT_ORDER) or not (to in DEPLOYMENT_ORDER):
			errs.append("deployments %s 的状态迁移非法: %s→%s" % [eid, from, to])
			continue
		var fi := DEPLOYMENT_ORDER.find(from)
		var ti := DEPLOYMENT_ORDER.find(to)
		if ti != fi + 1:
			errs.append("deployments %s 必须单步前进（%s→%s）" % [eid, from, to])
		if bool(d.get("idempotent_replay", false)) == false \
				and String(d.get("request_id", "")) == "":
			errs.append("deployments %s 缺少 request_id（重复请求须幂等）" % eid)
	return errs


# ── 观测共享（分方情报 + 延迟）──────────────────────────────────
static func _validate_observations(raw, index: Dictionary) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["observation_shares 必须是数组"]
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("observation_shares 项必须是对象")
			continue
		var o: Dictionary = r
		var target := String(o.get("target_entity_instance_id", ""))
		if target != "" and not index.has(target):
			errs.append("观测引用未知 target_entity_instance_id: " + target)
		if String(o.get("source", "")) == "":
			errs.append("观测缺少 source（证据来源）")
		if String(o.get("observer_id", "")) == "":
			errs.append("观测缺少 observer_id")
		if String(o.get("intel_owner_id", "")) == "":
			errs.append("观测缺少 intel_owner_id（必须归某个情报拥有者）")
		for tf in ["observed_t", "received_t"]:
			var v = o.get(tf, null)
			if not (v is int or v is float) or not is_finite(float(v)) \
					or float(v) < 0.0:
				errs.append("观测 %s 必须是有限非负秒" % tf)
		if _num(o.get("observed_t")) > _num(o.get("received_t")) + 1.0e-9:
			errs.append("时序错误：observed_t(%s) 晚于 received_t(%s)" % [
				str(o.get("observed_t")), str(o.get("received_t"))])
		var delay = o.get("delay_s", 0.0)
		if not (delay is int or delay is float) or not is_finite(float(delay)) \
				or float(delay) < 0.0:
			errs.append("观测 delay_s 必须是非负有限秒")
		if String(o.get("path", "")) == "":
			errs.append("观测缺少 path（共享路径必须显式）")
	return errs


# ── 命令（actor/controller/fleet/shooter 与显式 shooter 校验）────
static func _validate_commands(raw, index: Dictionary, domains_raw) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["commands 必须是数组"]
	var ctrl_of: Dictionary = {}
	for d in (domains_raw as Array):
		if d is Dictionary:
			ctrl_of[String((d as Dictionary).get("domain_id", ""))] = \
				String((d as Dictionary).get("controller_id", ""))
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("commands 项必须是对象")
			continue
		var c: Dictionary = r
		var actor := String(c.get("actor_id", ""))
		if actor == "":
			errs.append("命令缺少 actor_id")
		var dom := String(c.get("domain_id", ""))
		if not ctrl_of.has(dom):
			errs.append("命令引用未知 domain_id: " + dom)
		var controller := String(c.get("controller_id", ""))
		if controller == "":
			errs.append("命令缺少 controller_id（不能以阵营代替直控）")
		elif ctrl_of.has(dom) and controller != String(ctrl_of[dom]):
			errs.append("命令 %s 的 controller_id 与域 %s 的直控不一致（跨域指挥）" % [
				String(c.get("command_id", "")), dom])
		var sid := String(c.get("shooter_id", ""))
		if sid == "":
			errs.append("命令 %s 缺少显式 shooter_id（禁止退回旗舰）" % String(c.get("command_id", "")))
		elif not index.has(sid):
			errs.append("命令 %s 的 shooter_id 不是有效实例: %s" % [
				String(c.get("command_id", "")), sid])
		elif ctrl_of.has(dom):
			var sdom := String((index[sid] as Dictionary).get("domain_id", ""))
			if sdom != dom:
				errs.append("命令 %s 的 shooter %s 属于域 %s，不在指挥域 %s 内" % [
					String(c.get("command_id", "")), sid, sdom, dom])
		if String(c.get("legacy_context", "")) != "" \
				and String(c.get("legacy_context", "")) != "own_ship":
			errs.append("旧调用只能映射 own_ship，不能扩成所有友舰")
	return errs


# ── 目标（权威裁决 vs 玩家获知状态分开）────────────────────────
static func _validate_objectives(raw, index: Dictionary) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["objectives 必须是数组"]
	var seen: Dictionary = {}
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("objectives 项必须是对象")
			continue
		var o: Dictionary = r
		var oid := String(o.get("objective_id", ""))
		if oid == "":
			errs.append("objectives.objective_id 不能为空")
			continue
		if seen.has(oid):
			errs.append("重复 objective_id: " + oid)
		seen[oid] = true
		var target := String(o.get("target_entity_instance_id", ""))
		if target != "" and not index.has(target):
			errs.append("objective %s 引用未知 target: %s" % [oid, target])
		var ts = o.get("threshold", null)
		if not _is_int(ts) or int(ts) < 0:
			errs.append("objective %s 的 threshold 必须是非负整数" % oid)
		# 权威裁决状态与玩家获知状态必须是两个字段
		if not o.has("authority_state"):
			errs.append("objective %s 缺少 authority_state（权威裁决状态）" % oid)
		var pks := String(o.get("player_known_state", ""))
		if not (pks in PLAYER_KNOWN_STATES):
			errs.append("objective %s 的 player_known_state 非法: %s" % [oid, pks])
		if o.has("story_independent") and bool(o.get("story_independent", false)) == false:
			errs.append("objective %s 必须 story_independent=true（story=false 仍裁决）" % oid)
	return errs


# ── 单舰账本（资源引用不得跨舰、单位明确）───────────────────────
static func _validate_ledgers(raw, index: Dictionary) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["ledgers 必须是数组"]
	var seen: Dictionary = {}
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("ledgers 项必须是对象")
			continue
		var l: Dictionary = r
		var eid := String(l.get("entity_instance_id", ""))
		if not index.has(eid):
			errs.append("ledger 引用未知实体实例: " + eid)
			continue
		if seen.has(eid):
			errs.append("重复 ledger（每舰唯一账本）: " + eid)
		seen[eid] = true
		var units: Dictionary = l.get("units", {}) if l.get("units") is Dictionary else {}
		if String(units.get("mass", "")) != "kg":
			errs.append("ledger %s 的质量单位必须是 kg（t→kg 只换算一次）" % eid)
		if String(units.get("fuel", "")) != "kg":
			errs.append("ledger %s 的燃料单位必须是 kg" % eid)
		if String(units.get("delta_v", "")) != "km/s":
			errs.append("ledger %s 的 Δv 单位必须是 km/s" % eid)
		for nf in ["ammo", "fuel_kg", "cooldown_s_count"]:
			var v = l.get(nf, null)
			if v == null:
				continue
			if not _is_int(v) or int(v) < 0:
				errs.append("ledger %s 的 %s 必须是非负整数" % [eid, nf])
		# 资源引用别舰：任何 *_of / owner 指向必须在同一实例
		var ref = l.get("resource_owner_instance_id", null)
		if ref != null and String(ref) != eid:
			errs.append("资源引用别舰：ledger %s 声明 owner=%s" % [eid, String(ref)])
		if float(l.get("mass_kg", 0.0)) < 0.0:
			errs.append("ledger %s 的 mass_kg 不能为负" % eid)
	return errs


# ── 单位换算辅助（契约固定：t→kg 只做一次）──────────────────────
static func tons_to_kg(tons: float) -> float:
	return tons * KG_PER_TONNE


# ── 可逆序列化（JSON 往返后语义不变）──────────────────────────
static func roundtrip(doc: Dictionary) -> Dictionary:
	var text := JSON.stringify(doc)
	var back = JSON.parse_string(text)
	if not (back is Dictionary):
		return {"ok": false, "errors": ["JSON 往返失败"]}
	var r: Dictionary = validate(back)
	return {"ok": bool(r.get("ok", false)), "errors": r.get("errors", []),
		"text": text, "doc": back}


static func _is_int(v) -> bool:
	if v is int:
		return true
	if not (v is float):
		return false
	if not is_finite(float(v)):
		return false
	if absf(float(v) - roundf(float(v))) > 0.0:
		return false
	return absf(float(v)) <= SAFE_INT_MAX


static func _num(v) -> float:
	if v is int or v is float:
		return float(v)
	return 0.0
