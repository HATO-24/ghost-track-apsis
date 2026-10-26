extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# JC-B00：联合战役多舰队/指挥/情报契约（K0 / R6 返修版）
#
# 语义校验器（**不是**完整 JSON Schema 引擎）：只校验本契约声明的结构、引用完整性、
# 权限绑定、单位与安全范围；不持有运行态、不写任何服务状态（纯函数）。
#
# R6 返修要点：
#   * **冻结 actor→controller→shooter 授权**：actor 必须在该域授权名单内，controller
#     必须等于域直控，shooter 必须是该域已选实例；legacy 只能绑定真实本舰。
#   * **情报**：observer 必须是实例，owner 必须是某域的 intel_owner，共享必须有授权者，
#     `received_t - observed_t` 必须与 `delay_s` 一致（≤1e-6 s）。
#   * **选择→部署**：只有 selected=true 的实例可部署，且必须逐一对应。
#   * **幂等键**：request_id 不得重复；重复时必须载荷一致，否则冲突拒绝。
#   * **账本**：连续 kg 量（mass_kg/fuel_kg）与整数计数（ammo/cooldown）分开校验，
#     必要资源缺失、非有限、越安全范围均拒绝。
#   * **冻结 owner 融合方案**：`intel_partitioning` 必须显式指定；AI 只读视图只允许
#     授权情报，不允许裸取真值。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.jc.contracts.v1"
const VERSION := 1
const SAFE_INT_MAX := 9007199254740991.0
const SAFE_NUM_MAX := 1.0e15

const DEPLOYMENT_ORDER := ["DRAFT", "VALIDATED", "DEPLOYED"]
const DOMAIN_KINDS := ["player", "ai_ally", "ai_hostile"]
const PLAYER_KNOWN_STATES := ["unknown", "suspected", "confirmed", "disabled"]
const INTEL_PARTITION_MODES := ["per_owner_track_table", "explicit_partition"]
# R6：事件/通信生命周期冻结（顺序固定，状态机不得跳步）
const EVENT_LIFECYCLE := ["created", "observed", "shared", "received", "executed", "closed"]
# R7：命令请求/回执/执行记录的状态枚举（生命周期冻结）
const LIFECYCLE_STATES := ["pending", "accepted", "rejected", "executing",
	"completed", "failed", "lost"]
# R8/K0-2：受支持的 lifecycle 版本身份（未知版本明确拒绝）
const LIFECYCLE_VERSIONS := ["v17.cmd_lifecycle.v1"]
const LEGACY_UNKNOWN_BEHAVIOR := ["reject", "legacy_tag"]

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
	# 分方情报方案必须显式冻结
	var partition := String(doc.get("intel_partitioning", ""))
	if not (partition in INTEL_PARTITION_MODES):
		errs.append("intel_partitioning 必须是 %s 之一（收到 '%s'）" % [
			str(INTEL_PARTITION_MODES), partition])
	var dom_res: Dictionary = _validate_domains(doc.get("command_domains", []))
	errs.append_array(dom_res.get("errors", []))
	var dom_index: Dictionary = dom_res.get("index", {})
	errs.append_array(_validate_fleets(doc.get("fleets", []), dom_index))
	var inst_res: Dictionary = _validate_instances(doc.get("instances", []),
		doc.get("fleets", []), dom_index)
	errs.append_array(inst_res.get("errors", []))
	var idx: Dictionary = inst_res.get("index", {})
	errs.append_array(_validate_roster_refs(doc.get("fleets", []), idx))
	errs.append_array(_validate_deployments(doc.get("deployments", []), idx))
	errs.append_array(_validate_observations(doc.get("observation_shares", []),
		idx, dom_index))
	errs.append_array(_validate_commands(doc.get("commands", []), idx, dom_index))
	errs.append_array(_validate_objectives(doc.get("objectives", []), idx))
	errs.append_array(_validate_ledgers(doc.get("ledgers", []), idx))
	errs.append_array(_validate_ai_view(doc.get("ai_read_view", null), idx, dom_index))
	errs.append_array(_validate_lifecycle(doc.get("event_lifecycle", null)))
	errs.append_array(_validate_legacy_scope(doc.get("legacy_scope", null)))
	if (doc.get("fleets", []) as Array).size() == 0:
		warns.append("没有任何 fleet；空战役配置")
	return {"ok": errs.is_empty(), "errors": errs, "warnings": warns,
		"schema": SCHEMA, "version": VERSION}


# ── 指挥域：阵营/直控/情报/ROE 四者分离 + actor 授权名单 ─────────
static func _validate_domains(raw) -> Dictionary:
	var errs: Array = []
	var index: Dictionary = {}
	if not (raw is Array):
		return {"errors": ["command_domains 必须是数组"], "index": index}
	if (raw as Array).size() < 3:
		errs.append("至少需要 3 个指挥域（player/ai_ally/ai_hostile）")
	var seen_id: Dictionary = {}
	var seen_ctrl: Dictionary = {}
	var seen_intel: Dictionary = {}
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
		var ctrl := String(d.get("controller_id", ""))
		if ctrl == "":
			errs.append("domain %s 缺少 controller_id（直控授权必须显式）" % did)
		elif seen_ctrl.has(ctrl):
			errs.append("controller_id 重复（不同域不得共用直控）: " + ctrl)
		seen_ctrl[ctrl] = true
		var owner := String(d.get("intel_owner_id", ""))
		if owner == "":
			errs.append("domain %s 缺少 intel_owner_id" % did)
		elif seen_intel.has(owner):
			errs.append("intel_owner_id 重复（情报拥有者必须唯一）: " + owner)
		seen_intel[owner] = true
		var fac := String(d.get("faction", ""))
		if fac == "":
			errs.append("domain %s 缺少 faction（阵营不等于直控）" % did)
		var roe = d.get("roe", null)
		if not (roe is String) or String(roe) == "":
			errs.append("domain %s 缺少显式 roe 授权" % did)
		# R6：actor 授权名单（冻结 actor→controller 关系）
		var actors = d.get("authorized_actors", [])
		if not (actors is Array) or (actors as Array).is_empty():
			errs.append("domain %s 缺少 authorized_actors（actor 授权必须显式）" % did)
			actors = []
		for a in (actors as Array):
			if String(a) == "":
				errs.append("domain %s 的 authorized_actors 含空项" % did)
		index[did] = {"controller_id": ctrl, "intel_owner_id": owner,
			"kind": kind, "faction": fac,
			"authorized_actors": (actors as Array).duplicate()}
	return {"errors": errs, "index": index}


# ── 舰队 ─────────────────────────────────────────────────────────
static func _validate_fleets(raw, dom_index: Dictionary) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["fleets 必须是数组"]
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
		if not dom_index.has(did):
			errs.append("fleet %s 引用未知 domain_id: %s" % [fid, did])
		var roster = f.get("roster", [])
		if not (roster is Array):
			errs.append("fleet %s 的 roster 必须是数组" % fid)
		elif (roster as Array).is_empty():
			errs.append("fleet %s 的 roster 不能为空" % fid)
	return errs


# ── 部署实例：选择标记、跨域、唯一 id ────────────────────────────
static func _validate_instances(raw, fleets_raw, dom_index: Dictionary) -> Dictionary:
	var errs: Array = []
	var index: Dictionary = {}
	if not (raw is Array):
		return {"errors": ["instances 必须是数组"], "index": index}
	var fleet_dom: Dictionary = {}
	for f in (fleets_raw as Array):
		if f is Dictionary:
			fleet_dom[String((f as Dictionary).get("fleet_id", ""))] = \
				String((f as Dictionary).get("domain_id", ""))
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
		var fleet_ok := fleet_dom.has(fid)
		if not fleet_ok:
			errs.append("instance %s 引用未知 fleet_id: %s" % [eid, fid])
		var dom := String(it.get("domain_id", ""))
		if not dom_index.has(dom):
			errs.append("instance %s 引用未知 domain_id: %s" % [eid, dom])
		elif fleet_ok and String(fleet_dom[fid]) != dom:
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
		if not (it.get("selected", null) is bool):
			errs.append("instance %s 缺少 selected(bool)：选择→部署映射必须显式" % eid)
		index[eid] = {"fleet_id": fid, "domain_id": dom, "deployment_state": st,
			"selected": bool(it.get("selected", false))}
	return {"errors": errs, "index": index}


# ── 名册引用：roster 成员必须是本舰队已登记实例 ──────────────────
static func _validate_roster_refs(fleets_raw, index: Dictionary) -> Array:
	var errs: Array = []
	for f in (fleets_raw as Array):
		if not (f is Dictionary):
			continue
		var fid := String((f as Dictionary).get("fleet_id", ""))
		for rr in ((f as Dictionary).get("roster", []) as Array):
			var rid := String((rr as Dictionary).get("entity_instance_id", ""))
			if not index.has(rid):
				errs.append("fleet %s 的 roster 引用未登记实例: %s" % [fid, rid])
			elif String((index[rid] as Dictionary).get("fleet_id", "")) != fid:
				errs.append("fleet %s 的 roster 成员 %s 不属于本舰队" % [fid, rid])
	return errs


# ── 部署清单：选择→部署逐一对应 + 幂等键冲突 ────────────────────
static func _validate_deployments(raw, index: Dictionary) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["deployments 必须是数组"]
	var by_request: Dictionary = {}
	var deployed_ids: Dictionary = {}
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("deployments 项必须是对象")
			continue
		var d: Dictionary = r
		var eid := String(d.get("entity_instance_id", ""))
		if not index.has(eid):
			errs.append("deployments 引用未登记实例: " + eid)
			continue
		if deployed_ids.has(eid):
			errs.append("deployments 重复部署同一实例: " + eid)
		deployed_ids[eid] = true
		var info: Dictionary = index[eid]
		if not bool(info.get("selected", false)):
			errs.append("未选择的实例 %s 不得进入部署清单" % eid)
		if String(info.get("deployment_state", "")) != "DEPLOYED":
			errs.append("实例 %s 尚未 DEPLOYED（当前 %s），不能出现在部署清单" % [
				eid, String(info.get("deployment_state", ""))])
		var from := String(d.get("from_state", ""))
		var to := String(d.get("to_state", ""))
		if not (from in DEPLOYMENT_ORDER) or not (to in DEPLOYMENT_ORDER):
			errs.append("deployments %s 的状态迁移非法: %s→%s" % [eid, from, to])
		else:
			var fi := DEPLOYMENT_ORDER.find(from)
			var ti := DEPLOYMENT_ORDER.find(to)
			if ti != fi + 1:
				errs.append("deployments %s 必须单步前进（%s→%s）" % [eid, from, to])
		# R7：部署记录时间必须有限非负；记录终点必须与实例当前状态一致
		#（历史迁移链应写进 history 字段，不能用 DRAFT→VALIDATED 记录解释 DEPLOYED 实例）。
		var dtv = d.get("t", null)
		if not _is_finite(dtv) or float(dtv) < 0.0:
			errs.append("deployments %s 的 t 必须是有限非负秒" % eid)
		if to != "" and to != String(info.get("deployment_state", "")):
			errs.append("deployments %s 记录到 %s，但实例当前状态是 %s（记录与状态不一致）" % [
				eid, to, String(info.get("deployment_state", ""))])
		# R6：幂等键必须存在且唯一；重复时载荷必须一致（冲突拒绝）
		var rid := String(d.get("request_id", ""))
		if rid == "":
			errs.append("deployments %s 缺少 request_id（重复请求须幂等）" % eid)
			continue
		var payload_sig := "%s|%s|%s" % [eid, from, to]
		if by_request.has(rid):
			if String(by_request[rid]) != payload_sig:
				errs.append("幂等键冲突：request_id %s 携带不同载荷（%s vs %s）" % [
					rid, String(by_request[rid]), payload_sig])
		else:
			by_request[rid] = payload_sig
	# 所有 selected 实例都必须出现在部署清单（选择→部署逐一对应）
	for eid2 in index.keys():
		if bool((index[eid2] as Dictionary).get("selected", false)) \
				and not deployed_ids.has(String(eid2)):
			errs.append("已选择实例 %s 未出现在部署清单" % String(eid2))
	return errs


# ── 观测共享：实例/owner/授权者/延迟一致性 ──────────────────────
static func _validate_observations(raw, index: Dictionary, dom_index: Dictionary) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["observation_shares 必须是数组"]
	var intel_owners: Dictionary = {}
	for did in dom_index.keys():
		intel_owners[String((dom_index[did] as Dictionary).get("intel_owner_id", ""))] = true
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
		var observer := String(o.get("observer_id", ""))
		var observer_owner := ""
		if observer == "":
			errs.append("观测缺少 observer_id")
		elif not index.has(observer):
			errs.append("观测 observer 不是已登记实例: " + observer)
		else:
			# R7：**原始 owner 固定**——观测最初归 observer 所属域的情报拥有者。
			var obs_dom := String((index[observer] as Dictionary).get("domain_id", ""))
			observer_owner = String((dom_index.get(obs_dom, {}) as Dictionary)
				.get("intel_owner_id", ""))
		var owner := String(o.get("intel_owner_id", ""))
		if owner == "":
			errs.append("观测缺少 intel_owner_id（必须归某个情报拥有者）")
		elif not intel_owners.has(owner):
			errs.append("观测 intel_owner_id 不是任何域的 intel_owner: " + owner)
		# R7：共享授权者必须是**原始 owner**（observer 所属域），不能自授权敌方观测。
		var authz := String(o.get("share_authorized_by", ""))
		if authz == "":
			errs.append("观测缺少 share_authorized_by（共享授权必须显式）")
		elif not intel_owners.has(authz):
			errs.append("观测 share_authorized_by 不是任何域的 intel_owner: " + authz)
		elif observer_owner != "" and authz != observer_owner:
			errs.append("观测共享授权者不是原始 owner：observer_owner=%s authorized_by=%s" % [
				observer_owner, authz])
		# R8/K0-3：接收方**必须显式**声明（不再默认成 intel_owner 静默放行）。
		var raw_receiver = o.get("received_by_intel_owner_id", null)
		if raw_receiver == null:
			errs.append("观测缺少 received_by_intel_owner_id（接收 owner 必须显式）")
		else:
			var receiver := String(raw_receiver)
			if not intel_owners.has(receiver):
				errs.append("观测 received_by_intel_owner_id 不是任何域的 intel_owner: "
					+ receiver)
			elif receiver != owner:
				errs.append("观测接收 owner 与 intel_owner_id 不一致：%s vs %s" % [
					receiver, owner])
		# 他人观测只能经原始 owner 授权；自我授权敌观测已由上面的 owner 校验拒绝。
		for tf in ["observed_t", "received_t"]:
			var v = o.get(tf, null)
			if not _is_finite(v) or float(v) < 0.0:
				errs.append("观测 %s 必须是有限非负秒" % tf)
		if _num(o.get("observed_t")) > _num(o.get("received_t")) + 1.0e-9:
			errs.append("时序错误：observed_t(%s) 晚于 received_t(%s)" % [
				str(o.get("observed_t")), str(o.get("received_t"))])
		var delay = o.get("delay_s", null)
		if not _is_finite(delay) or float(delay) < 0.0:
			errs.append("观测 delay_s 必须是非负有限秒")
		else:
			# R6：delay 必须与 (received - observed) 一致（≤1e-6 s）
			var delta := _num(o.get("received_t")) - _num(o.get("observed_t"))
			if absf(delta - float(delay)) > 1.0e-6:
				errs.append("观测延迟不一致：received-observed=%.9f 但 delay_s=%.9f" % [
					delta, float(delay)])
		if String(o.get("path", "")) == "":
			errs.append("观测缺少 path（共享路径必须显式）")
	return errs


# ── 命令：actor→controller→shooter 授权绑定 ────────────────────
static func _validate_commands(raw, index: Dictionary, dom_index: Dictionary) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["commands 必须是数组"]
	var seen_cmd: Dictionary = {}
	for r in (raw as Array):
		if not (r is Dictionary):
			errs.append("commands 项必须是对象")
			continue
		var c: Dictionary = r
		var cid := String(c.get("command_id", ""))
		if cid == "":
			# R7：命令标识必须显式；缺 ID 无法幂等/追溯，直接拒绝。
			errs.append("命令缺少 command_id（标识与幂等必须显式）")
		else:
			if seen_cmd.has(cid):
				errs.append("重复 command_id: " + cid)
			seen_cmd[cid] = true
		# R7：命令需要事件 ID/seq 与请求/回执/执行记录的版本与关联。
		var ev_id := String(c.get("event_id", ""))
		if ev_id == "":
			errs.append("命令 %s 缺少 event_id（事件标识必须显式）" % cid)
		var seqv = c.get("seq", null)
		# R8/K0-1：seq 是冻结契约的一部分，**必需**（不接受"合法省略"两套口径）。
		if seqv == null:
			errs.append("命令 %s 缺少 seq（事件序号必须显式）" % cid)
		elif not _is_int(seqv) or float(seqv) < 0.0:
			errs.append("命令 %s 的 seq 必须是非负整数" % cid)
		var lc: Dictionary = c.get("lifecycle", {}) if c.get("lifecycle") is Dictionary else {}
		if lc.is_empty():
			errs.append("命令 %s 缺少 lifecycle（请求/回执/执行记录必须冻结）" % cid)
		else:
			# R8/K0-2：lifecycle 版本必须属于受支持集合，未知版本明确拒绝。
			var lv := String(lc.get("lifecycle_version", ""))
			if lv == "":
				errs.append("命令 %s 的 lifecycle 缺少版本" % cid)
			elif not (lv in LIFECYCLE_VERSIONS):
				errs.append("命令 %s 的 lifecycle 版本不受支持: %s（支持 %s）" % [
					cid, lv, str(LIFECYCLE_VERSIONS)])
			for stage in ["request", "receipt", "execution"]:
				var row = lc.get(stage, null)
				if not (row is Dictionary):
					errs.append("命令 %s 的 lifecycle 缺少 %s 记录" % [cid, stage])
					continue
				var rt = (row as Dictionary).get("t", null)
				if not _is_finite(rt) or float(rt) < 0.0:
					errs.append("命令 %s 的 lifecycle.%s.t 必须有限非负" % [cid, stage])
				var stt := String((row as Dictionary).get("state", ""))
				if not (stt in LIFECYCLE_STATES):
					errs.append("命令 %s 的 lifecycle.%s.state 非法: %s" % [
						cid, stage, stt])
			# 关联：回执/执行必须引用同一 request_id
			var req_rid := String((lc.get("request", {}) as Dictionary).get("request_id", ""))
			if req_rid == "":
				errs.append("命令 %s 的 lifecycle.request 缺少 request_id" % cid)
			for st2 in ["receipt", "execution"]:
				if lc.get(st2) is Dictionary:
					var r2 := String((lc.get(st2) as Dictionary).get("request_id", ""))
					if r2 != req_rid:
						errs.append("命令 %s 的 lifecycle.%s 未关联同一 request_id" % [
							cid, st2])
		var dom := String(c.get("domain_id", ""))
		if not dom_index.has(dom):
			errs.append("命令引用未知 domain_id: " + dom)
			continue
		var dom_row: Dictionary = dom_index[dom]
		var actors: Array = dom_row.get("authorized_actors", [])
		var actor := String(c.get("actor_id", ""))
		if actor == "":
			errs.append("命令 %s 缺少 actor_id" % cid)
		elif not (actor in actors):
			errs.append("命令 %s 的 actor %s 不在域 %s 授权名单内（冻结 actor→controller）" % [
				cid, actor, dom])
		var controller := String(c.get("controller_id", ""))
		if controller == "":
			errs.append("命令 %s 缺少 controller_id（不能以阵营代替直控）" % cid)
		elif controller != String(dom_row.get("controller_id", "")):
			errs.append("命令 %s 的 controller_id 与域 %s 的直控不一致（跨域指挥）" % [
				cid, dom])
		var sid := String(c.get("shooter_id", ""))
		if sid == "":
			errs.append("命令 %s 缺少显式 shooter_id（禁止退回旗舰）" % cid)
		elif not index.has(sid):
			errs.append("命令 %s 的 shooter_id 不是有效实例: %s" % [cid, sid])
		else:
			var sinfo: Dictionary = index[sid]
			var sdom := String(sinfo.get("domain_id", ""))
			if sdom != dom:
				errs.append("命令 %s 的 shooter %s 属于域 %s，不在指挥域 %s 内" % [
					cid, sid, sdom, dom])
			# R7：shooter 必须是**实际参战/可受令**的实例，不只是已登记。
			if bool(sinfo.get("selected", false)) != true:
				errs.append("命令 %s 的 shooter %s 未被选中，不能受令" % [cid, sid])
			if String(sinfo.get("deployment_state", "")) != "DEPLOYED":
				errs.append("命令 %s 的 shooter %s 未部署（当前 %s），不能受令" % [
					cid, sid, String(sinfo.get("deployment_state", ""))])
		# legacy 只能绑定真实本舰：必须给出 own_entity_instance_id 且 shooter==own
		var legacy := String(c.get("legacy_context", ""))
		if legacy != "":
			if legacy != "own_ship":
				errs.append("旧调用只能映射 own_ship，不能扩成所有友舰")
			var own := String(c.get("own_entity_instance_id", ""))
			if own == "":
				errs.append("命令 %s 声明 legacy_context 但缺少 own_entity_instance_id" % cid)
			elif sid != own:
				errs.append("命令 %s 的 legacy 调用 shooter=%s 不等于本舰 %s" % [
					cid, sid, own])
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
		if not o.has("authority_state"):
			errs.append("objective %s 缺少 authority_state（权威裁决状态）" % oid)
		var pks := String(o.get("player_known_state", ""))
		if not (pks in PLAYER_KNOWN_STATES):
			errs.append("objective %s 的 player_known_state 非法: %s" % [oid, pks])
		if o.has("story_independent") and bool(o.get("story_independent", false)) == false:
			errs.append("objective %s 必须 story_independent=true（story=false 仍裁决）" % oid)
	return errs


# ── 单舰账本：连续 kg 与整数计数分开、必要资源、安全范围 ────────
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
		for pair in [["mass", "kg"], ["fuel", "kg"], ["delta_v", "km/s"]]:
			if String(units.get(pair[0], "")) != String(pair[1]):
				errs.append("ledger %s 的 %s 单位必须是 %s" % [eid, pair[0], pair[1]])
		# 连续物理量：必须存在、有限、非负、安全范围
		for cf in ["mass_kg", "fuel_kg"]:
			var cv = l.get(cf, null)
			if cv == null:
				errs.append("ledger %s 缺少必要连续资源 %s" % [eid, cf])
			elif not _is_finite(cv) or float(cv) < 0.0 or float(cv) > SAFE_NUM_MAX:
				errs.append("ledger %s 的 %s 必须是安全范围内的有限非负数" % [eid, cf])
		var dv = l.get("delta_v_kmps", null)
		if dv != null and (not _is_finite(dv) or float(dv) < 0.0 or float(dv) > SAFE_NUM_MAX):
			errs.append("ledger %s 的 delta_v_kmps 必须是安全范围内的有限非负数" % eid)
		# 整数计数：必须存在、真整数、非负、安全范围
		for inf2 in ["ammo", "cooldown_s_count"]:
			var iv = l.get(inf2, null)
			if iv == null:
				errs.append("ledger %s 缺少必要整数计数 %s" % [eid, inf2])
			elif not _is_int(iv) or float(iv) < 0.0 or float(iv) > SAFE_INT_MAX:
				errs.append("ledger %s 的 %s 必须是非负安全整数（不接受浮点计数）" % [
					eid, inf2])
		var ref = l.get("resource_owner_instance_id", null)
		if ref != null and String(ref) != eid:
			errs.append("资源引用别舰：ledger %s 声明 owner=%s" % [eid, String(ref)])
	return errs


# ── AI 只读视图：只能持有授权情报，不允许真值直读 ───────────────
static func _validate_ai_view(raw, index: Dictionary, dom_index: Dictionary) -> Array:
	var errs: Array = []
	if raw == null:
		errs.append("缺少 ai_read_view（AI 只读视图必须显式冻结）")
		return errs
	if not (raw is Dictionary):
		return ["ai_read_view 必须是对象"]
	var view: Dictionary = raw
	var reads_truth = view.get("reads_ground_truth", null)
	if reads_truth == null or bool(reads_truth) != false:
		errs.append("ai_read_view.reads_ground_truth 必须为 false（AI 不得直读真值）")
	var per_domain = view.get("by_domain", null)
	if not (per_domain is Dictionary):
		errs.append("ai_read_view.by_domain 必须是对象")
		return errs
	for did in (per_domain as Dictionary).keys():
		if not dom_index.has(String(did)):
			errs.append("ai_read_view 引用未知 domain_id: " + String(did))
			continue
		var row = (per_domain as Dictionary)[did]
		if not (row is Dictionary):
			errs.append("ai_read_view.%s 必须是对象" % String(did))
			continue
		var owners = (row as Dictionary).get("intel_owners", [])
		if not (owners is Array) or (owners as Array).is_empty():
			errs.append("ai_read_view.%s 缺少 intel_owners（只读授权必须显式）" % String(did))
			continue
		var expect_owner := String((dom_index[String(did)] as Dictionary)
			.get("intel_owner_id", ""))
		for ow in (owners as Array):
			if String(ow) != expect_owner:
				errs.append("ai_read_view.%s 只能读本域情报（%s），却声明 %s" % [
					String(did), expect_owner, String(ow)])
	return errs


# ── 事件/通信生命周期：顺序冻结，不得缺步或乱序 ──────────────────
static func _validate_lifecycle(raw) -> Array:
	var errs: Array = []
	if not (raw is Array):
		return ["event_lifecycle 必须是数组（事件/通信生命周期必须冻结）"]
	var arr: Array = raw
	if arr.size() != EVENT_LIFECYCLE.size():
		errs.append("event_lifecycle 必须恰好包含 %d 个阶段（收到 %d）" % [
			EVENT_LIFECYCLE.size(), arr.size()])
	for i in range(mini(arr.size(), EVENT_LIFECYCLE.size())):
		if String(arr[i]) != String(EVENT_LIFECYCLE[i]):
			errs.append("event_lifecycle 第 %d 阶段必须是 %s（收到 %s）" % [
				i, String(EVENT_LIFECYCLE[i]), String(arr[i])])
	return errs


# ── legacy scope：旧档/旧调用的恢复口径必须冻结 ──────────────────
static func _validate_legacy_scope(raw) -> Array:
	var errs: Array = []
	if not (raw is Dictionary):
		return ["legacy_scope 必须是对象（旧档/旧调用恢复口径必须冻结）"]
	var sc: Dictionary = raw
	if sc.get("own_ship_only", null) != true:
		errs.append("legacy_scope.own_ship_only 必须为 true（旧调用只映射本舰）")
	var ub := String(sc.get("unknown_campaign_behavior", ""))
	if not (ub in LEGACY_UNKNOWN_BEHAVIOR):
		errs.append("legacy_scope.unknown_campaign_behavior 必须是 %s 之一" % str(
			LEGACY_UNKNOWN_BEHAVIOR))
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


static func _is_finite(v) -> bool:
	if not (v is int or v is float):
		return false
	return is_finite(float(v))


static func _is_int(v) -> bool:
	if not _is_finite(v):
		return false
	if absf(float(v) - roundf(float(v))) > 0.0:
		return false
	return absf(float(v)) <= SAFE_INT_MAX


static func _num(v) -> float:
	if v is int or v is float:
		return float(v)
	return 0.0
