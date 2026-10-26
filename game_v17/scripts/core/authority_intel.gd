extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# JC-A01（#58）：指挥权限与分方情报隔离
#
# 职责：
#   * 冻结「actor → controller → domain → shooter」授权链，并在**消耗资源/排弹/
#     成功事件之前**给出明确拒绝原因；
#   * 每个 intel owner 独立的观测入口与读取 facade（list/selected/plot/导出）；
#   * 隐藏真值（未观测）不得进入任何 owner 视图；
#   * owner 航迹与授权 context 纳入存档/恢复，旧档只迁入本舰域。
#
# 不做：完整 AI、逐舰战斗账本、真实协同协议。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.authority_intel.v1"
const VERSION := 1

const LEGACY_CONTEXT := "own_ship"

# 拒绝原因（冻结，供探针与审计使用）
const R_UNKNOWN_SHOOTER := "unknown_shooter"
const R_NOT_AUTHORIZED := "shooter_not_authorized"
const R_ALLY_DIRECT := "direct_command_not_permitted"
const R_RUNTIME_UNAVAILABLE := "shooter_runtime_unavailable"
const R_LEGACY_ANCHOR_UNKNOWN := "legacy_anchor_unknown"
const R_DOMAIN_UNKNOWN := "domain_unknown"

var ready := false
var errors: Array[String] = []

# domain_id -> {controller_id, intel_owner_id, kind, faction, authorized_actors}
var domains: Dictionary = {}
# entity_instance_id -> {domain_id, combat_runtime}
var instances: Dictionary = {}
# intel_owner_id -> {track_id -> track dict}（各 owner 独立，不共享）
var intel: Dictionary = {}
# owner_id 观测流（含 observed_t/received_t/来源与路径）
var observations: Dictionary = {}
# fire 审计（拒绝与成功都记录，不消耗资源）
var audit: Array = []
var own_entity := ""
var own_owner := ""


func setup(cfg: Dictionary) -> bool:
	ready = false
	errors = []
	domains = {}
	instances = {}
	intel = {}
	observations = {}
	audit = []
	own_entity = String(cfg.get("own_entity", ""))
	var raw_domains = cfg.get("command_domains", [])
	if raw_domains is Array and not (raw_domains as Array).is_empty():
		for raw in (raw_domains as Array):
			if not (raw is Dictionary):
				continue
			var d: Dictionary = raw
			var did := String(d.get("domain_id", ""))
			if did == "":
				errors.append("command_domains.domain_id 不能为空")
				continue
			domains[did] = {
				"controller_id": String(d.get("controller_id", "")),
				"intel_owner_id": String(d.get("intel_owner_id", "")),
				"kind": String(d.get("kind", "ai_ally")),
				"faction": String(d.get("faction", "")),
				"authorized_actors": (d.get("authorized_actors", []) as Array).duplicate(),
			}
	else:
		# 默认三域（旧 seed 兼容：本舰域 + 无观测的盟军/敌方域）
		domains["player"] = {"controller_id": "player_ctrl",
			"intel_owner_id": "player_intel", "kind": "player",
			"faction": "", "authorized_actors": ["player_ctrl"]}
		domains["ally"] = {"controller_id": "ally_ai",
			"intel_owner_id": "ally_intel", "kind": "ai_ally",
			"faction": "", "authorized_actors": ["ally_ai"]}
		domains["opfor"] = {"controller_id": "opfor_ai",
			"intel_owner_id": "opfor_intel", "kind": "ai_hostile",
			"faction": "", "authorized_actors": ["opfor_ai"]}
	for did2 in domains.keys():
		intel[String((domains[did2] as Dictionary).get("intel_owner_id", ""))] = {}
		observations[String((domains[did2] as Dictionary).get("intel_owner_id", ""))] = []
	own_owner = String((domains.get("player", {}) as Dictionary).get("intel_owner_id", ""))
	# 实例归属：本舰 + 可选 fleet_instances
	if own_entity != "":
		instances[own_entity] = {"domain_id": "player", "combat_runtime": true}
	for raw2 in (cfg.get("fleet_instances", []) as Array):
		if not (raw2 is Dictionary):
			continue
		var inst: Dictionary = raw2
		var eid := String(inst.get("entity_instance_id", ""))
		if eid == "":
			continue
		var dom := String(inst.get("domain_id", "player"))
		instances[eid] = {"domain_id": dom,
			"combat_runtime": eid == own_entity}
	for raw3 in (cfg.get("own_fleet", []) as Array):
		if not (raw3 is Dictionary):
			continue
		var of: Dictionary = raw3
		var oid := String(of.get("entity_instance_id", ""))
		if oid == "":
			continue
		if not instances.has(oid):
			instances[oid] = {"domain_id": "player", "combat_runtime": false}
		instances[oid]["combat_runtime"] = bool(of.get("combat_runtime", false)) \
			or oid == own_entity
	ready = errors.is_empty() and domains.size() > 0
	return ready


# ── 授权：fire 入口 ─────────────────────────────────────────────

## 返回 {ok, reason, shooter_id, domain_id, controller_id, legacy_context, own_entity_instance_id}
## 该函数**不**消耗资源；调用方必须在弹道/弹药之前使用它。
func authorize_fire(opts: Dictionary) -> Dictionary:
	var o: Dictionary = opts if opts is Dictionary else {}
	var explicit := String(o.get("shooter_id", ""))
	if explicit == "":
		# 旧调用：只映射本舰（可信锚点来自场景配置，不由命令自证）
		if own_entity == "":
			# 无本舰锚点的会话（如纯服务测试）：授权门**不抢先拒绝**，
			# 交回既有 combat/ballistics 检查，保持旧语义不变；审计记录 deferred。
			return {"ok": true, "reason": "legacy_no_anchor_deferred",
				"shooter_id": "", "deferred": true,
				"detail": "场景未配置 own_entity：授权门放行由既有服务检查"}
		if not instances.has(own_entity):
			return {"ok": false, "reason": R_LEGACY_ANCHOR_UNKNOWN,
				"detail": "本舰未登记为实例: " + own_entity}
		return {"ok": true, "reason": "ok", "shooter_id": own_entity,
			"domain_id": "player", "controller_id": _controller_of("player"),
			"legacy_context": LEGACY_CONTEXT,
			"own_entity_instance_id": own_entity}
	if not instances.has(explicit):
		return {"ok": false, "reason": R_UNKNOWN_SHOOTER,
			"detail": "shooter 不是已登记实例: " + explicit}
	var info: Dictionary = instances[explicit]
	var dom := String(info.get("domain_id", ""))
	if not domains.has(dom):
		return {"ok": false, "reason": R_DOMAIN_UNKNOWN,
			"detail": "shooter 所属域未知: " + dom}
	var kind := String((domains[dom] as Dictionary).get("kind", ""))
	if kind == "ai_hostile":
		return {"ok": false, "reason": R_NOT_AUTHORIZED,
			"detail": "敌方实例不能接受本方命令: " + explicit}
	if kind == "ai_ally":
		return {"ok": false, "reason": R_ALLY_DIRECT,
			"detail": "盟军不能接受直接命令（应走协同请求协议）: " + explicit}
	# 本方其他舰：若尚无独立战斗运行态 → 明确不可用，绝不借旗舰
	if not bool(info.get("combat_runtime", false)):
		return {"ok": false, "reason": R_RUNTIME_UNAVAILABLE,
			"detail": "该本方舰尚无独立战斗运行态: " + explicit}
	return {"ok": true, "reason": "ok", "shooter_id": explicit,
		"domain_id": dom, "controller_id": _controller_of(dom),
		"legacy_context": ""}


func _controller_of(dom: String) -> String:
	return String((domains.get(dom, {}) as Dictionary).get("controller_id", ""))


## 审计：拒绝与成功都记录（含资源前后由调用方补充）
func record_audit(entry: Dictionary) -> void:
	var e: Dictionary = entry.duplicate(true)
	e["t"] = float(e.get("t", 0.0))
	e["schema"] = SCHEMA
	audit.append(e)
	while audit.size() > 200:
		audit.pop_front()


func fire_audit() -> Array:
	return audit.duplicate(true)


# ── 情报：owner 隔离入口 ────────────────────────────────────────

func owner_of_entity(entity_id: String) -> String:
	var info: Dictionary = instances.get(entity_id, {}) if instances.get(entity_id) is Dictionary else {}
	var dom := String(info.get("domain_id", "player"))
	return String((domains.get(dom, {}) as Dictionary).get("intel_owner_id", own_owner))


func has_owner(owner_id: String) -> bool:
	return intel.has(owner_id)


## 接收观测：只有接收 owner 自己的视图可见；其他 owner 不可见。
## row: {observation_id, observer_id, target_id, sensor, observed_t, received_t,
##       delay_s, source, path, quality, range_km, bearing_deg}
func receive_observation(owner_id: String, row: Dictionary) -> Dictionary:
	if not intel.has(owner_id):
		return {"ok": false, "reason": "unknown_intel_owner", "owner_id": owner_id}
	var r: Dictionary = row.duplicate(true)
	r["intel_owner_id"] = owner_id
	(observations[owner_id] as Array).append(r)
	var tid := String(r.get("target_id", ""))
	if tid != "":
		var cur: Dictionary = (intel[owner_id] as Dictionary).get(tid, {})
		var trk: Dictionary = cur if cur is Dictionary else {}
		trk["id"] = tid
		trk["intel_owner_id"] = owner_id
		trk["last_observed_t"] = float(r.get("observed_t", 0.0))
		trk["last_received_t"] = float(r.get("received_t", 0.0))
		trk["source"] = String(r.get("source", ""))
		trk["quality"] = float(r.get("quality", 0.0))
		# 几何以 observed_t 的观测为准；不得用当前真值替换
		if r.get("pos_km") is Array and (r.get("pos_km") as Array).size() >= 3:
			trk["pos_km"] = (r.get("pos_km") as Array).duplicate()
		if r.get("range_km") != null:
			trk["range_km"] = float(r.get("range_km"))
		if r.get("bearing_deg") != null:
			trk["bearing_deg"] = float(r.get("bearing_deg"))
		(intel[owner_id] as Dictionary)[tid] = trk
	return {"ok": true, "owner_id": owner_id, "track_id": tid}


## 分方读取视图：只返回该 owner 自己的航迹与观测（不含任何其他 owner 数据）
func intel_view(owner_id: String) -> Dictionary:
	var tracks: Array = []
	var obs: Array = []
	if intel.has(owner_id):
		var m: Dictionary = intel[owner_id]
		var ids: Array = m.keys()
		ids.sort()
		for tid in ids:
			tracks.append((m[tid] as Dictionary).duplicate(true))
	if observations.has(owner_id):
		obs = (observations[owner_id] as Array).duplicate(true)
	return {"schema": SCHEMA, "owner_id": owner_id, "tracks": tracks,
		"observations": obs}


## 玩家/AI 可读的绘图位置：只来自该 owner 的航迹（绝不读物理真值）
func plot_positions(owner_id: String) -> Dictionary:
	var view: Dictionary = intel_view(owner_id)
	var positions: Array = []
	for raw in (view.get("tracks", []) as Array):
		var trk: Dictionary = raw
		if trk.get("pos_km") is Array and (trk.get("pos_km") as Array).size() >= 3:
			positions.append({"id": String(trk.get("id", "")),
				"pos_km": (trk.get("pos_km") as Array).duplicate(),
				"source": String(trk.get("source", "")),
				"observed_t": float(trk.get("last_observed_t", 0.0))})
	return {"schema": SCHEMA, "owner_id": owner_id, "source": "intel",
		"positions": positions}


func selected(owner_id: String) -> Array:
	var out: Array = []
	for raw in (intel_view(owner_id).get("tracks", []) as Array):
		if bool((raw as Dictionary).get("selected", false)):
			out.append((raw as Dictionary).duplicate(true))
	return out


# ── 存档/恢复 ───────────────────────────────────────────────────

func export_state() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION,
		"own_entity": own_entity, "own_owner": own_owner,
		"domains": JSON.parse_string(JSON.stringify(domains)),
		"instances": JSON.parse_string(JSON.stringify(instances)),
		"intel": JSON.parse_string(JSON.stringify(intel)),
		"observations": JSON.parse_string(JSON.stringify(observations)),
		"audit": JSON.parse_string(JSON.stringify(audit))}


## 恢复：owner 航迹与 context 一致；旧档（无本段）只迁入本舰域，不复制到盟军。
func import_state(st: Dictionary) -> Dictionary:
	if st == null or not (st is Dictionary) or (st as Dictionary).is_empty():
		return {"ok": true, "restore_mode": "legacy_own_ship_only",
			"note": "旧档无 authority/intel 段：仅本舰域，不复制到盟军"}
	var s: Dictionary = st
	if String(s.get("schema", "")) != SCHEMA:
		return {"ok": false, "reason": "invalid_schema"}
	if int(s.get("version", 0)) != VERSION:
		return {"ok": false, "reason": "invalid_version"}
	var new_intel: Dictionary = {}
	var new_obs: Dictionary = {}
	for did in domains.keys():
		var owner := String((domains[did] as Dictionary).get("intel_owner_id", ""))
		new_intel[owner] = {}
		new_obs[owner] = []
	var raw_intel = s.get("intel", {})
	if raw_intel is Dictionary:
		for owner2 in (raw_intel as Dictionary).keys():
			if not new_intel.has(String(owner2)):
				continue  # 不属于当前域的 owner 一律丢弃（不串域）
			var m2 = (raw_intel as Dictionary)[owner2]
			if m2 is Dictionary:
				new_intel[String(owner2)] = (m2 as Dictionary).duplicate(true)
	var raw_obs = s.get("observations", {})
	if raw_obs is Dictionary:
		for owner3 in (raw_obs as Dictionary).keys():
			if not new_obs.has(String(owner3)):
				continue
			var a3 = (raw_obs as Dictionary)[owner3]
			if a3 is Array:
				new_obs[String(owner3)] = (a3 as Array).duplicate(true)
	intel = new_intel
	observations = new_obs
	var raw_audit = s.get("audit", [])
	audit = (raw_audit as Array).duplicate(true) if raw_audit is Array else []
	return {"ok": true, "restore_mode": "full",
		"owners": intel.keys(), "audit": audit.size()}
