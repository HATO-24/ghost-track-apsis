extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# JC-A01（#58）R1–R6 返修版：指挥权限与分方情报隔离
#
# 职责：
#   * 冻结「请求 context(actor/controller/fleet/domain) → shooter」授权链，
#     在**消耗资源/排弹/成功事件之前**给出明确拒绝原因；
#   * 真实逐舰运行态由调用方（GameSession）按**实际运行态**注入，配置 bool 不得自证；
#   * 每个 intel owner 独立的观测入口与读取 facade；共享必须经授权与**实际到达**；
#   * 隐藏真值（未观测）不得进入任何 owner 视图；
#   * owner 航迹、授权 context、审计纳入存档/恢复；旧档只迁入本舰域。
#
# 不做：完整 AI、逐舰战斗账本、真实协同协议。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.authority_intel.v1"
const VERSION := 1

const LEGACY_CONTEXT := "own_ship"
const TIME_TOL := 1.0e-6

# 拒绝原因（冻结，供探针与审计使用）
const R_UNKNOWN_SHOOTER := "unknown_shooter"
const R_NOT_AUTHORIZED := "shooter_not_authorized"
const R_ALLY_DIRECT := "direct_command_not_permitted"
const R_RUNTIME_UNAVAILABLE := "shooter_runtime_unavailable"
const R_LEGACY_ANCHOR_UNKNOWN := "legacy_anchor_unknown"
const R_DOMAIN_UNKNOWN := "domain_unknown"
const R_ACTOR_NOT_AUTHORIZED := "actor_not_authorized"
const R_CONTROLLER_MISMATCH := "controller_mismatch"
const R_FLEET_MISMATCH := "fleet_mismatch"
const R_CONTEXT_DOMAIN_MISMATCH := "context_domain_mismatch"
const R_OBSERVER_UNKNOWN := "unknown_observer"
const R_SHARE_NOT_AUTHORIZED := "share_not_authorized"
const R_RECEIVER_MISMATCH := "receiver_mismatch"
const R_TIME_INVALID := "invalid_observation_time"
const R_NOT_ARRIVED := "observation_not_arrived"

var ready := false
var errors: Array[String] = []

# domain_id -> {controller_id, intel_owner_id, kind, faction, authorized_actors, fleet_id}
var domains: Dictionary = {}
# entity_instance_id -> {domain_id, fleet_id}
var instances: Dictionary = {}
# intel_owner_id -> {track_id -> track dict}（各 owner 独立，不共享）
var intel: Dictionary = {}
# owner_id 观测流（含 observed_t/received_t/来源与路径）
var observations: Dictionary = {}
# 幂等键：owner|delivery_id|observation_id -> true
var seen_deliveries: Dictionary = {}
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
	seen_deliveries = {}
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
				"fleet_id": String(d.get("fleet_id", "")),
				"authorized_actors": (d.get("authorized_actors", []) as Array).duplicate(),
			}
	else:
		domains["player"] = {"controller_id": "player_ctrl",
			"intel_owner_id": "player_intel", "kind": "player",
			"faction": "", "fleet_id": "own_fleet",
			"authorized_actors": ["player_ctrl"]}
		domains["ally"] = {"controller_id": "ally_ai",
			"intel_owner_id": "ally_intel", "kind": "ai_ally",
			"faction": "", "fleet_id": "ally_fleet",
			"authorized_actors": ["ally_ai"]}
		domains["opfor"] = {"controller_id": "opfor_ai",
			"intel_owner_id": "opfor_intel", "kind": "ai_hostile",
			"faction": "", "fleet_id": "enemy_fleet",
			"authorized_actors": ["opfor_ai"]}
	for did2 in domains.keys():
		var owner := String((domains[did2] as Dictionary).get("intel_owner_id", ""))
		intel[owner] = {}
		observations[owner] = []
	own_owner = String((domains.get("player", {}) as Dictionary).get("intel_owner_id", ""))
	# 实例归属：本舰 + 可选 fleet_instances（fleet_id 参与授权）
	if own_entity != "":
		instances[own_entity] = {"domain_id": "player",
			"fleet_id": String((domains["player"] as Dictionary).get("fleet_id", ""))}
	for raw2 in (cfg.get("fleet_instances", []) as Array):
		if not (raw2 is Dictionary):
			continue
		var inst: Dictionary = raw2
		var eid := String(inst.get("entity_instance_id", ""))
		if eid == "":
			continue
		var dom := String(inst.get("domain_id", "player"))
		var fleet := String(inst.get("fleet_id",
			String((domains.get(dom, {}) as Dictionary).get("fleet_id", ""))))
		instances[eid] = {"domain_id": dom, "fleet_id": fleet}
	ready = errors.is_empty() and domains.size() > 0
	return ready


# ── 授权：fire 入口 ─────────────────────────────────────────────

## 授权检查。**不**消耗资源；调用方必须在弹道/弹药之前使用。
## opts 可含：shooter_id / actor_id / controller_id / domain_id / fleet_id / target_id
## runtime_ids：**由调用方按真实运行态注入**的可发射实例集合（配置 bool 不得自证）
func authorize_fire(opts: Dictionary, runtime_ids := []) -> Dictionary:
	var o: Dictionary = opts if opts is Dictionary else {}
	var explicit := String(o.get("shooter_id", ""))
	# 请求 context：任一字段出现即视为「显式 context」，必须完整合法
	var ctx_actor := String(o.get("actor_id", ""))
	var ctx_ctrl := String(o.get("controller_id", ""))
	var ctx_dom := String(o.get("domain_id", ""))
	var ctx_fleet := String(o.get("fleet_id", ""))
	var has_ctx := ctx_actor != "" or ctx_ctrl != "" or ctx_dom != "" or ctx_fleet != ""
	var resolved := ""
	var legacy := ""
	if explicit == "":
		if own_entity == "":
			# 无本舰锚点的纯服务会话：不抢先拒绝，交回既有检查（旧语义不变）
			return {"ok": true, "reason": "legacy_no_anchor_deferred",
				"shooter_id": "", "deferred": true,
				"detail": "场景未配置 own_entity：授权门放行由既有服务检查"}
		if has_ctx:
			# 显式非法 context 不得被抹成 legacy：先按 context 校验
			var bad: Dictionary = _validate_context(ctx_actor, ctx_ctrl, ctx_dom, ctx_fleet)
			if not bool(bad.get("ok", false)):
				return bad
		if not instances.has(own_entity):
			return {"ok": false, "reason": R_LEGACY_ANCHOR_UNKNOWN,
				"detail": "本舰未登记为实例: " + own_entity}
		resolved = own_entity
		legacy = LEGACY_CONTEXT
	else:
		resolved = explicit
	if not instances.has(resolved):
		return {"ok": false, "reason": R_UNKNOWN_SHOOTER,
			"detail": "shooter 不是已登记实例: " + resolved}
	var info: Dictionary = instances[resolved]
	var dom := String(info.get("domain_id", ""))
	if not domains.has(dom):
		return {"ok": false, "reason": R_DOMAIN_UNKNOWN,
			"detail": "shooter 所属域未知: " + dom}
	var dom_row: Dictionary = domains[dom]
	# 显式 context（含给定 shooter 时也校验其一致性）
	if has_ctx:
		var chk: Dictionary = _validate_context(ctx_actor, ctx_ctrl, ctx_dom, ctx_fleet,
			dom, String(info.get("fleet_id", "")))
		if not bool(chk.get("ok", false)):
			return chk
	# 域种类限制
	var kind := String(dom_row.get("kind", ""))
	if kind == "ai_hostile":
		return {"ok": false, "reason": R_NOT_AUTHORIZED,
			"detail": "敌方实例不能接受本方命令: " + resolved}
	if kind == "ai_ally":
		return {"ok": false, "reason": R_ALLY_DIRECT,
			"detail": "盟军不能接受直接命令（应走协同请求协议）: " + resolved}
	# R1b：真实逐舰运行态由调用方注入，配置 bool 不得自证
	var has_runtime := false
	for rid in (runtime_ids as Array):
		if String(rid) == resolved:
			has_runtime = true
			break
	if not has_runtime:
		return {"ok": false, "reason": R_RUNTIME_UNAVAILABLE,
			"detail": "该本方舰无真实战斗运行态: " + resolved}
	return {"ok": true, "reason": "ok", "shooter_id": resolved,
		"domain_id": dom, "fleet_id": String(info.get("fleet_id", "")),
		"controller_id": String(dom_row.get("controller_id", "")),
		"actor_id": String(ctx_actor) if ctx_actor != "" \
			else String(dom_row.get("authorized_actors", [""])[0]),
		"legacy_context": legacy,
		"context_source": "explicit" if has_ctx else "shooter_only"}


## 校验显式 context；给定 shooter 域/舰队时要求一致。
func _validate_context(actor: String, ctrl: String, dom: String, fleet: String,
		shooter_dom := "", shooter_fleet := "") -> Dictionary:
	if dom != "":
		if not domains.has(dom):
			return {"ok": false, "reason": R_DOMAIN_UNKNOWN,
				"detail": "context domain 未知: " + dom}
		if shooter_dom != "" and dom != shooter_dom:
			return {"ok": false, "reason": R_CONTEXT_DOMAIN_MISMATCH,
				"detail": "context domain=%s 与 shooter 域=%s 不一致" % [dom, shooter_dom]}
	var check_dom := dom if dom != "" else shooter_dom
	if check_dom == "":
		return {"ok": false, "reason": R_CONTEXT_DOMAIN_MISMATCH,
			"detail": "缺少可判定的域"}
	var row: Dictionary = domains[check_dom]
	if actor != "":
		var actors: Array = row.get("authorized_actors", [])
		if not (actor in actors):
			return {"ok": false, "reason": R_ACTOR_NOT_AUTHORIZED,
				"detail": "actor %s 不在域 %s 授权名单" % [actor, check_dom]}
	if ctrl != "":
		if ctrl != String(row.get("controller_id", "")):
			return {"ok": false, "reason": R_CONTROLLER_MISMATCH,
				"detail": "controller %s 与域 %s 直控 %s 不一致" % [
					ctrl, check_dom, String(row.get("controller_id", ""))]}
	if fleet != "":
		var want := String(row.get("fleet_id", ""))
		if want != "" and fleet != want:
			return {"ok": false, "reason": R_FLEET_MISMATCH,
				"detail": "fleet %s 与域 %s 舰队 %s 不一致" % [fleet, check_dom, want]}
		if shooter_fleet != "" and fleet != shooter_fleet:
			return {"ok": false, "reason": R_FLEET_MISMATCH,
				"detail": "fleet %s 与 shooter 舰队 %s 不一致" % [fleet, shooter_fleet]}
	return {"ok": true}


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
	if info.is_empty():
		return ""
	var dom := String(info.get("domain_id", ""))
	return String((domains.get(dom, {}) as Dictionary).get("intel_owner_id", ""))


func has_owner(owner_id: String) -> bool:
	return intel.has(owner_id)


## 接收观测（**必须**经真实投递到达）。
## row: observation_id/observer_id/target_id/sensor/source/observed_t/pos_km/quality...
## delivery: delivery_id / received_t / share_authorized_by / path / now_t
## 返回 {ok, reason?, duplicated?}
func receive_observation(owner_id: String, row: Dictionary,
		delivery := {}) -> Dictionary:
	if not intel.has(owner_id):
		return {"ok": false, "reason": "unknown_intel_owner", "owner_id": owner_id}
	var r: Dictionary = row.duplicate(true)
	var d: Dictionary = delivery if delivery is Dictionary else {}
	var observer := String(r.get("observer_id", ""))
	# 未知 observer 不得默认本方（旧实现默认 player）
	if observer == "":
		return {"ok": false, "reason": "missing_observer"}
	if not instances.has(observer):
		return {"ok": false, "reason": R_OBSERVER_UNKNOWN,
			"detail": "observer 不是已登记实例: " + observer}
	var observer_owner := owner_of_entity(observer)
	# 跨 owner 共享：必须有原始 owner 授权 + 真实投递
	var delivery_id := String(d.get("delivery_id", ""))
	if observer_owner != owner_id:
		var authz := String(d.get("share_authorized_by", ""))
		if authz == "":
			return {"ok": false, "reason": R_SHARE_NOT_AUTHORIZED,
				"detail": "跨 owner 共享缺少 share_authorized_by"}
		if authz != observer_owner:
			return {"ok": false, "reason": R_SHARE_NOT_AUTHORIZED,
				"detail": "共享授权者 %s 不是观察者原始 owner %s" % [
					authz, observer_owner]}
		if delivery_id == "":
			return {"ok": false, "reason": R_NOT_ARRIVED,
				"detail": "跨 owner 共享必须经真实投递（缺 delivery_id）"}
	# 时间契约：有限非负、received>=observed、delay 与差值一致、不得来自未来
	var observed_t := float(r.get("observed_t", -1.0))
	if not is_finite(observed_t) or observed_t < 0.0:
		return {"ok": false, "reason": R_TIME_INVALID, "detail": "observed_t 非法"}
	var received_raw = d.get("received_t", r.get("received_t", null))
	if received_raw == null or not is_finite(float(received_raw)) \
			or float(received_raw) < 0.0:
		return {"ok": false, "reason": R_TIME_INVALID, "detail": "received_t 非法"}
	var received_t := float(received_raw)
	if received_t + TIME_TOL < observed_t:
		return {"ok": false, "reason": R_TIME_INVALID,
			"detail": "received_t 早于 observed_t"}
	var now_raw = d.get("now_t", null)
	if now_raw != null:
		if not is_finite(float(now_raw)):
			return {"ok": false, "reason": R_TIME_INVALID, "detail": "now_t 非法"}
		if received_t > float(now_raw) + TIME_TOL:
			return {"ok": false, "reason": R_NOT_ARRIVED,
				"detail": "received_t 晚于当前时刻（尚未到达）"}
	var delay_raw = d.get("delay_s", r.get("delay_s", null))
	if delay_raw != null:
		var delay := float(delay_raw)
		if not is_finite(delay) or delay < 0.0:
			return {"ok": false, "reason": R_TIME_INVALID, "detail": "delay_s 非法"}
		if absf((received_t - observed_t) - delay) > TIME_TOL:
			return {"ok": false, "reason": R_TIME_INVALID,
				"detail": "delay_s 与 received-observed 不一致"}
	# 幂等：同一 owner + delivery/observation 只融合一次
	var obs_id := String(r.get("observation_id", ""))
	var idem_key := "%s|%s|%s" % [owner_id, delivery_id,
		obs_id if obs_id != "" else "%s@%.6f" % [String(r.get("target_id", "")), observed_t]]
	if seen_deliveries.has(idem_key):
		return {"ok": true, "duplicated": true, "owner_id": owner_id,
			"observation_id": obs_id}
	seen_deliveries[idem_key] = true
	r["intel_owner_id"] = owner_id
	r["delivery_id"] = delivery_id
	r["received_t"] = received_t
	r["observed_t"] = observed_t
	if d.get("path", null) != null:
		r["path"] = String(d.get("path", ""))
	if d.get("share_authorized_by", null) != null:
		r["share_authorized_by"] = String(d.get("share_authorized_by", ""))
	(observations[owner_id] as Array).append(r)
	var tid := String(r.get("target_id", ""))
	if tid != "":
		var cur: Dictionary = (intel[owner_id] as Dictionary).get(tid, {})
		var trk: Dictionary = cur if cur is Dictionary else {}
		trk["id"] = tid
		trk["intel_owner_id"] = owner_id
		trk["last_observed_t"] = observed_t
		trk["last_received_t"] = received_t
		trk["source"] = String(r.get("source", ""))
		trk["quality"] = float(r.get("quality", 0.0))
		if r.get("pos_km") is Array and (r.get("pos_km") as Array).size() >= 3:
			trk["pos_km"] = (r.get("pos_km") as Array).duplicate()
		if r.get("range_km") != null:
			trk["range_km"] = float(r.get("range_km"))
		if r.get("bearing_deg") != null:
			trk["bearing_deg"] = float(r.get("bearing_deg"))
		(intel[owner_id] as Dictionary)[tid] = trk
	return {"ok": true, "owner_id": owner_id, "track_id": tid,
		"observation_id": obs_id}


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


## 旧档迁移：把旧 TrackTable 航迹迁入**可信本舰 owner**（不复制给盟军/敌方）
func migrate_legacy_tracks(own_owner_id: String, tracks: Array) -> Dictionary:
	if not intel.has(own_owner_id):
		return {"ok": false, "reason": "unknown_intel_owner"}
	var migrated := 0
	for raw in tracks:
		if not (raw is Dictionary):
			continue
		var t: Dictionary = raw
		var tid := String(t.get("id", t.get("track_id", "")))
		if tid == "":
			continue
		var trk: Dictionary = t.duplicate(true)
		trk["id"] = tid
		trk["intel_owner_id"] = own_owner_id
		trk["source"] = "legacy_migration"
		(intel[own_owner_id] as Dictionary)[tid] = trk
		migrated += 1
	return {"ok": true, "migrated": migrated, "owner": own_owner_id}


# ── 存档/恢复 ───────────────────────────────────────────────────

func export_state() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION,
		"own_entity": own_entity, "own_owner": own_owner,
		"domains": JSON.parse_string(JSON.stringify(domains)),
		"instances": JSON.parse_string(JSON.stringify(instances)),
		"intel": JSON.parse_string(JSON.stringify(intel)),
		"observations": JSON.parse_string(JSON.stringify(observations)),
		"seen_deliveries": JSON.parse_string(JSON.stringify(seen_deliveries)),
		"audit": JSON.parse_string(JSON.stringify(audit))}


## 恢复：owner 航迹与 context 一致；真正旧档只迁入本舰域，不复制到盟军。
func import_state(st) -> Dictionary:
	if st == null:
		return {"ok": true, "restore_mode": "legacy_own_ship_only",
			"note": "无 authority/intel 段：旧档迁移路径"}
	if not (st is Dictionary):
		# R5：**已存在但畸形**的新段必须明确失败，不得静默降级为旧档
		return {"ok": false, "reason": "invalid_state_type",
			"detail": "authority_intel 段必须是对象（收到 %s）" % type_string(typeof(st))}
	var s: Dictionary = st
	if s.is_empty():
		return {"ok": true, "restore_mode": "legacy_own_ship_only",
			"note": "空段：按旧档迁移"}
	if String(s.get("schema", "")) != SCHEMA:
		return {"ok": false, "reason": "invalid_schema",
			"detail": "schema=%s" % String(s.get("schema", ""))}
	if int(s.get("version", 0)) != VERSION:
		return {"ok": false, "reason": "invalid_version",
			"detail": "version=%s" % str(s.get("version", 0))}
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
	var raw_seen = s.get("seen_deliveries", {})
	seen_deliveries = (raw_seen as Dictionary).duplicate(true) \
		if raw_seen is Dictionary else {}
	var raw_audit = s.get("audit", [])
	audit = (raw_audit as Array).duplicate(true) if raw_audit is Array else []
	return {"ok": true, "restore_mode": "full",
		"owners": intel.keys(), "audit": audit.size()}
