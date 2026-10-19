class_name V2NavigationModel
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2 导航 / 交通管制 / 机动规划模型（R4-NAV-CORE-1）
#
# **规划模型，不接物理**：路线边的 Δv/时间/暴露/风险是内容文件中的抽象转移成本，
# 不冒充真实轨道积分；R6 接入真实物理后 schema 不变，只替换数据来源。
#
# 能力：
#   1. 地月交通节点（Earth Port / GEO / L1–L5 / 月球港 / 月球低轨）：
#      id/name/kind/position_source（可绑定 cislunar model 的 id）/abstract_pos_km/authority。
#   2. 路线图：边有 transfer_type / dv_ms / duration_s / exposure / risk /
#      traffic_required；`plan_routes(from,to,constraints)` 返回快速/经济/隐蔽 3 类候选，
#      带 Δv/时间/暴露/风险/约束违背/可行标记 —— 只规划，不执行。
#   3. 交通管制：`request_clearance(route, window, priority)` → granted/deny/hold/expire；
#      有排队（按优先级 + 先到先得）、拒绝原因、时间窗、许可有效期；不自动执行。
#   4. 机动状态机：PRE_ORDER→AUTHORIZED→QUEUED→EXECUTING→DONE/ABORTED；
#      `plan_maneuver(kind,target)` 支持 hold/approach/retreat/evade/point/burn；
#      执行按抽象 Δv/时间消耗；可中断；**不修改轨道物理/世界状态**。
#   5. 只读 `vm_navigation()`：routes/selected/clearance/queue/planned_maneuvers/budget/limits/events。
#
# 单位：Δv m/s；时间 s；距离 km；exposure/risk 0..1。全部 JSON 可序列化。
# 内容：framework/content/navigation_l1.json（成本/节点/规则，不在代码写死）。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_CONTENT_PATH := "res://framework/content/navigation_l1.json"
const SCHEMA := "navigation.v1"
const MAX_EVENTS := 200
const VM_EVENT_LIMIT := 72
const DEFAULT_PROFILES := ["fast", "economy", "covert"]
const DEFAULT_STATE_ORDER := ["PRE_ORDER", "AUTHORIZED", "QUEUED", "EXECUTING", "DONE", "ABORTED"]
const MANEUVER_KINDS := ["hold", "approach", "retreat", "evade", "point", "burn"]
const DEFAULT_PRIORITY_RANGE := [1, 5]

# ── 内容 / 图 ────────────────────────────────────────────────────
var content: Dictionary = {}
var nodes: Dictionary = {}               # id -> node dict（含 abstract_pos_km:Vector3）
var edges: Array = []                    # 规范化边 dict（含 _rev 双向展开）
var adjacency: Dictionary = {}           # node id -> [{to, edge, reversed}]
var edges_by_id: Dictionary = {}
var route_cfg: Dictionary = {}
var traffic_cfg: Dictionary = {}
var maneuvers_cfg: Dictionary = {}
var budget_cfg: Dictionary = {}

# ── 状态 ─────────────────────────────────────────────────────────
var t := 0.0
var ready := false
var errors: Array[String] = []
var events: Array = []

var last_routes: Array = []              # 最近一次 plan_routes 的候选
var selected_route: Dictionary = {}
var requests: Array = []                 # 所有交通许可请求（含历史）
var queue: Array = []                    # 待处理/保持的请求 id（已排序）
var planned_maneuvers: Array = []        # 所有机动计划（含历史）
var dv_used_ms := 0.0                    # 已消耗 Δv
var dv_committed_ms := 0.0               # 已授权/排队但未执行完的 Δv（预留）
var position_provider: Callable = Callable()

var _route_seq := 0
var _req_seq := 0
var _mnv_seq := 0

# ═══════════════════════════════════════════════════════════════════
# 0. 内容装载 / 校验
# ═══════════════════════════════════════════════════════════════════

## 读取 JSON 内容（res:// 与项目相对路径兼容，风格同 damage_model）。
static func load_content(path := DEFAULT_CONTENT_PATH) -> Dictionary:
	var candidates: Array = [path]
	var base := ProjectSettings.globalize_path("res://")
	candidates.append(base.path_join("../framework/content/navigation_l1.json").simplify_path())
	for raw_path in candidates:
		var p := String(raw_path)
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			return parsed
	return {}


## 内容自检；返回错误列表（空 = 通过）。probe 用篡改副本验证。
static func validate_content(data: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if data.is_empty():
		errs.append("content empty")
		return errs
	if String(data.get("schema", "")) != SCHEMA:
		errs.append("schema != %s" % SCHEMA)
	if String(data.get("id", "")) == "":
		errs.append("id empty")
	var raw_nodes = data.get("nodes", null)
	if not (raw_nodes is Dictionary) or (raw_nodes as Dictionary).is_empty():
		errs.append("nodes empty")
		return errs
	var node_map: Dictionary = raw_nodes
	for raw_key in node_map.keys():
		var nid := String(raw_key)
		var nd = node_map[raw_key]
		if not (nd is Dictionary):
			errs.append("node %s not object" % nid)
			continue
		var node: Dictionary = nd
		if String(node.get("name", "")) == "":
			errs.append("node %s name empty" % nid)
		if String(node.get("kind", "")) == "":
			errs.append("node %s kind empty" % nid)
		if String(node.get("position_source", "")) == "":
			errs.append("node %s position_source empty" % nid)
		var pos = node.get("abstract_pos_km", null)
		if not (pos is Array) or (pos as Array).size() != 3:
			errs.append("node %s abstract_pos_km != [x,y,z]" % nid)
	var raw_edges = data.get("edges", null)
	if not (raw_edges is Array) or (raw_edges as Array).is_empty():
		errs.append("edges empty")
	else:
		var seen: Dictionary = {}
		for raw_e in (raw_edges as Array):
			if not (raw_e is Dictionary):
				errs.append("edge not object")
				continue
			var ed: Dictionary = raw_e
			var eid := String(ed.get("id", ""))
			if eid == "":
				errs.append("edge id empty")
			elif seen.has(eid):
				errs.append("edge id duplicated: %s" % eid)
			seen[eid] = true
			var f_id := String(ed.get("from", ""))
			var to_id := String(ed.get("to", ""))
			if not node_map.has(f_id):
				errs.append("edge %s from unknown node %s" % [eid, f_id])
			if not node_map.has(to_id):
				errs.append("edge %s to unknown node %s" % [eid, to_id])
			if String(ed.get("transfer_type", "")) == "":
				errs.append("edge %s transfer_type empty" % eid)
			if float(ed.get("dv_ms", -1.0)) < 0.0:
				errs.append("edge %s dv_ms < 0" % eid)
			if float(ed.get("duration_s", 0.0)) <= 0.0:
				errs.append("edge %s duration_s <= 0" % eid)
			var expo := float(ed.get("exposure", -1.0))
			if expo < 0.0 or expo > 1.0:
				errs.append("edge %s exposure out of 0..1" % eid)
			var risk := float(ed.get("risk", -1.0))
			if risk < 0.0 or risk > 1.0:
				errs.append("edge %s risk out of 0..1" % eid)
			if not (ed.get("traffic_required", null) is bool):
				errs.append("edge %s traffic_required not bool" % eid)
	var rl = data.get("route_limits", null)
	if not (rl is Dictionary):
		errs.append("route_limits missing")
	else:
		var profiles: Array = (rl as Dictionary).get("profiles", [])
		for p in DEFAULT_PROFILES:
			if not profiles.has(p):
				errs.append("route_limits missing profile %s" % p)
		var weights: Dictionary = (rl as Dictionary).get("profile_weights", {})
		for p2 in DEFAULT_PROFILES:
			if not weights.has(p2):
				errs.append("route_limits missing weights %s" % p2)
	var tr = data.get("traffic", null)
	if not (tr is Dictionary):
		errs.append("traffic missing")
	else:
		var trd: Dictionary = tr
		if int(trd.get("max_queue", 0)) < 1:
			errs.append("traffic max_queue < 1")
		var pr: Array = trd.get("priority_range", [])
		if pr.size() != 2 or int(pr[0]) > int(pr[1]):
			errs.append("traffic priority_range invalid")
		if float(trd.get("hold_exposure_threshold", 2.0)) < 0.0 \
				or float(trd.get("hold_exposure_threshold", 2.0)) > 1.0:
			errs.append("traffic hold_exposure_threshold out of 0..1")
	var mcfg = data.get("maneuvers", null)
	if not (mcfg is Dictionary):
		errs.append("maneuvers missing")
	else:
		var md: Dictionary = mcfg
		var kinds: Dictionary = md.get("kinds", {}) if md.get("kinds") is Dictionary else {}
		for kind in MANEUVER_KINDS:
			if not kinds.has(kind):
				errs.append("maneuvers missing kind %s" % kind)
		var order: Array = md.get("state_order", [])
		for st in ["PRE_ORDER", "AUTHORIZED", "QUEUED", "EXECUTING", "DONE", "ABORTED"]:
			if not order.has(st):
				errs.append("maneuvers state_order missing %s" % st)
		if not (md.get("terminal_states", null) is Array):
			errs.append("maneuvers terminal_states invalid")
	var bcfg = data.get("budget", null)
	if not (bcfg is Dictionary):
		errs.append("budget missing")
	else:
		var bd: Dictionary = bcfg
		if float(bd.get("dv_total_ms", 0.0)) <= 0.0:
			errs.append("budget dv_total_ms <= 0")
		if float(bd.get("dv_reserve_ms", 0.0)) < 0.0 \
				or float(bd.get("dv_reserve_ms", 0.0)) >= float(bd.get("dv_total_ms", 0.0)):
			errs.append("budget dv_reserve_ms invalid")
	return errs


static func node_ids(from_content: Dictionary) -> Array:
	var out: Array = []
	var nd = from_content.get("nodes", {})
	if nd is Dictionary:
		for k in (nd as Dictionary).keys():
			out.append(String(k))
	out.sort()
	return out


static func list_nodes(from_content: Dictionary) -> Array:
	var out: Array = []
	var nd = from_content.get("nodes", {})
	if nd is Dictionary:
		for k in (nd as Dictionary).keys():
			var node: Dictionary = (nd as Dictionary)[k] if (nd as Dictionary)[k] is Dictionary else {}
			out.append({"id": String(k), "name": String(node.get("name", k)),
				"kind": String(node.get("kind", "")),
				"position_source": String(node.get("position_source", ""))})
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


# ═══════════════════════════════════════════════════════════════════
# 1. 初始化
# ═══════════════════════════════════════════════════════════════════

## content_override 为空时从 navigation_l1.json 装载。
func setup(content_override := {}) -> bool:
	ready = false
	errors.clear()
	content = content_override.duplicate(true) if content_override is Dictionary \
		and not (content_override as Dictionary).is_empty() else load_content()
	if content.is_empty():
		errors.append("navigation content 未就绪：%s" % DEFAULT_CONTENT_PATH)
		return false
	errors = validate_content(content)
	if not errors.is_empty():
		return false
	_build_graph()
	budget_cfg = _content_dict("budget")
	traffic_cfg = _content_dict("traffic")
	maneuvers_cfg = _content_dict("maneuvers")
	route_cfg = _content_dict("route_limits")
	t = 0.0
	events.clear()
	last_routes.clear()
	selected_route.clear()
	requests.clear()
	queue.clear()
	planned_maneuvers.clear()
	dv_used_ms = 0.0
	dv_committed_ms = 0.0
	_route_seq = 0
	_req_seq = 0
	_mnv_seq = 0
	ready = true
	_event("navigation_ready", String(content.get("id", "")),
		"导航模型就绪：%d 节点 / %d 边" % [nodes.size(), edges.size()])
	return true


func reset() -> void:
	if content.is_empty():
		return
	setup(content.duplicate(true))


func _build_graph() -> void:
	nodes.clear()
	edges.clear()
	edges_by_id.clear()
	adjacency.clear()
	var raw_nodes: Dictionary = content.get("nodes", {}) if content.get("nodes") is Dictionary else {}
	for raw_key in raw_nodes.keys():
		var nid := String(raw_key)
		var nd: Dictionary = raw_nodes[raw_key]
		var pos_arr: Array = nd.get("abstract_pos_km", [0.0, 0.0, 0.0])
		nodes[nid] = {
			"id": nid,
			"name": String(nd.get("name", nid)),
			"kind": String(nd.get("kind", "")),
			"position_source": String(nd.get("position_source", "")),
			"abstract_pos_km": Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])),
			"authority": String(nd.get("authority", "")),
			"traffic_class": String(nd.get("traffic_class", "")),
			"capacity": int(nd.get("capacity", 1)),
			"notes": String(nd.get("notes", "")),
		}
		adjacency[nid] = []
	var raw_edges: Array = content.get("edges", []) if content.get("edges") is Array else []
	for raw_e in raw_edges:
		var ed: Dictionary = raw_e
		var edge: Dictionary = {
			"id": String(ed.get("id", "")),
			"from": String(ed.get("from", "")),
			"to": String(ed.get("to", "")),
			"bidirectional": bool(ed.get("bidirectional", false)),
			"transfer_type": String(ed.get("transfer_type", "")),
			"dv_ms": float(ed.get("dv_ms", 0.0)),
			"duration_s": float(ed.get("duration_s", 0.0)),
			"exposure": clampf(float(ed.get("exposure", 0.0)), 0.0, 1.0),
			"risk": clampf(float(ed.get("risk", 0.0)), 0.0, 1.0),
			"traffic_required": bool(ed.get("traffic_required", false)),
			"corridor": String(ed.get("corridor", "")),
			"notes": String(ed.get("notes", "")),
		}
		edges.append(edge)
		edges_by_id[String(edge.get("id", ""))] = edge
		(adjacency[String(edge.get("from", ""))] as Array).append({
			"to": String(edge.get("to", "")), "edge": edge, "reversed": false})
		if bool(edge.get("bidirectional", false)):
			(adjacency[String(edge.get("to", ""))] as Array).append({
				"to": String(edge.get("from", "")), "edge": edge, "reversed": true})


func _content_dict(key: String) -> Dictionary:
	var v = content.get(key, {})
	return v if v is Dictionary else {}


func _maneuver_kinds() -> Dictionary:
	var kinds = maneuvers_cfg.get("kinds", {})
	return kinds if kinds is Dictionary else {}


func _profiles() -> Array:
	var ps: Array = route_cfg.get("profiles", DEFAULT_PROFILES)
	return ps if not ps.is_empty() else DEFAULT_PROFILES


func _state_order() -> Array:
	var so: Array = maneuvers_cfg.get("state_order", DEFAULT_STATE_ORDER)
	return so if not so.is_empty() else DEFAULT_STATE_ORDER


func _terminal_states() -> Array:
	var ts: Array = maneuvers_cfg.get("terminal_states", ["DONE", "ABORTED"])
	return ts


func _priority_range() -> Array:
	var pr: Array = traffic_cfg.get("priority_range", DEFAULT_PRIORITY_RANGE)
	if pr.size() != 2:
		return DEFAULT_PRIORITY_RANGE
	return pr


func _reason_text(key: String) -> String:
	var reasons: Dictionary = traffic_cfg.get("deny_reasons", {}) if traffic_cfg.get("deny_reasons") is Dictionary else {}
	return String(reasons.get(key, key))


# ═══════════════════════════════════════════════════════════════════
# 2. 节点 / 位置来源（不加载 cislunar；由调用方绑定 provider）
# ═══════════════════════════════════════════════════════════════════

## 绑定位置提供者：func(position_source:String, node_id:String) -> Vector3|Array|Dictionary。
## R6/集成层用它把 cislunar model 的真实站体位置接进来；本模型不硬依赖。
func bind_position_provider(provider: Callable) -> void:
	position_provider = provider


func clear_position_provider() -> void:
	position_provider = Callable()


## 节点位置（优先 provider，失败回退抽象坐标）；返回 [x,y,z] km。
func node_position_km(node_id: String) -> Array:
	if not nodes.has(node_id):
		return []
	var node: Dictionary = nodes[node_id]
	if position_provider.is_valid():
		var got = position_provider.call(String(node.get("position_source", "")), node_id)
		var arr := _pos_array(got)
		if not arr.is_empty():
			return arr
	var pos: Vector3 = node.get("abstract_pos_km", Vector3.ZERO)
	return [pos.x, pos.y, pos.z]


func _pos_array(value: Variant) -> Array:
	if value is Vector3:
		var v: Vector3 = value
		return [v.x, v.y, v.z]
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return [float(a[0]), float(a[1]), float(a[2])]
	if value is Dictionary:
		var d: Dictionary = value
		for k in ["pos_km", "position", "pos", "r", "position_km"]:
			if d.has(k):
				return _pos_array(d.get(k))
	return []


## 所有节点的位置快照（给后续导航页/路线图用）。
func resolve_positions() -> Dictionary:
	var out: Dictionary = {}
	for nid in nodes.keys():
		out[String(nid)] = node_position_km(String(nid))
	return out


# ═══════════════════════════════════════════════════════════════════
# 3. 路线规划（只规划，不执行）
# ═══════════════════════════════════════════════════════════════════

## 规划候选路线。constraints 支持：
##   max_dv_ms / max_duration_s / max_exposure / avoid_traffic /
##   exclude_transfer_types:[...] / max_hops:int
## 返回 {ok, from, to, constraints, candidates:[3 类], profiles, errors:[]}；
## 只写 last_routes（规划缓存），不改预算/许可/机动/时间/物理。
func plan_routes(from_id: String, to_id: String, constraints := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready")
	if not nodes.has(from_id):
		return _fail("unknown_node", {"node": from_id})
	if not nodes.has(to_id):
		return _fail("unknown_node", {"node": to_id})
	if from_id == to_id:
		return _fail("same_node", {"node": from_id})
	var cons := _merge_constraints(constraints)
	var max_hops := int(cons.get("max_hops", 0))
	if max_hops <= 0:
		max_hops = int(route_cfg.get("max_hops", 3))
	var max_paths := maxi(1, int(route_cfg.get("max_paths", 32)))
	var paths := _enumerate_paths(from_id, to_id, max_hops, max_paths)
	if paths.is_empty():
		last_routes = []
		return _fail("no_route", {"from": from_id, "to": to_id})
	# 统一路径指标（用于归一化打分）
	var enriched: Array = []
	var max_dv := 1.0
	var max_dur := 1.0
	for raw_path in paths:
		var path_dict: Dictionary = raw_path
		var met := _path_metrics(path_dict, cons)
		enriched.append({"path": path_dict, "metrics": met})
		max_dv = maxf(max_dv, float(met.get("dv_ms", 0.0)))
		max_dur = maxf(max_dur, float(met.get("duration_s", 0.0)))
	var weights_map: Dictionary = route_cfg.get("profile_weights", {}) if route_cfg.get("profile_weights") is Dictionary else {}
	var labels: Dictionary = route_cfg.get("profile_labels", {}) if route_cfg.get("profile_labels") is Dictionary else {}
	var profiles := _profiles()
	var used: Dictionary = {}
	var candidates: Array = []
	var rank := 0
	for raw_profile in profiles:
		var profile := String(raw_profile)
		var w: Dictionary = weights_map.get(profile, {}) if weights_map.get(profile) is Dictionary else {}
		var best_idx := -1
		var best_score := INF
		var best_feasible := false
		# 优先选可行且未使用；若都不可行则选未使用的最佳
		for pass_feasible in [true, false]:
			for i in range(enriched.size()):
				if used.has(i):
					continue
				var en: Dictionary = enriched[i]
				var met2: Dictionary = en.get("metrics", {})
				if pass_feasible and not bool(met2.get("feasible", false)):
					continue
				var sc := _score_metrics(met2, w, max_dv, max_dur)
				if sc < best_score:
					best_score = sc
					best_idx = i
					best_feasible = bool(met2.get("feasible", false))
			if best_idx >= 0:
				break
		if best_idx < 0:
			continue
		used[best_idx] = true
		rank += 1
		var chosen: Dictionary = enriched[best_idx]
		var candidate := _candidate_from_metrics(chosen.get("path", {}), chosen.get("metrics", {}),
			profile, String(labels.get(profile, profile)), rank, best_score)
		candidate["unique"] = true
		_route_seq += 1
		candidate["candidate_id"] = "RTE-%04d" % _route_seq
		candidates.append(candidate)
	# 推荐：可行候选中 score 最低者
	var recommended := ""
	var best_rec := INF
	for c in candidates:
		var cd: Dictionary = c
		if not bool(cd.get("feasible", false)):
			continue
		var sc2 := float(cd.get("score", INF))
		if sc2 < best_rec:
			best_rec = sc2
			recommended = String(cd.get("candidate_id", ""))
	last_routes = candidates.duplicate(true)
	_event("routes_planned", "%s->%s" % [from_id, to_id],
		"规划路线 %s → %s：%d 类候选（%s）" % [from_id, to_id, candidates.size(), recommended])
	return {
		"ok": true,
		"from": from_id,
		"to": to_id,
		"constraints": cons,
		"profiles": profiles.duplicate(),
		"candidates": candidates,
		"recommended": recommended,
		"errors": [],
	}


func _merge_constraints(raw: Variant) -> Dictionary:
	var defaults: Dictionary = route_cfg.get("constraints_default", {}) if route_cfg.get("constraints_default") is Dictionary else {}
	var out: Dictionary = defaults.duplicate(true)
	if raw is Dictionary:
		for k in (raw as Dictionary).keys():
			out[String(k)] = (raw as Dictionary)[k]
	return out


## 枚举简单路径（最多 max_hops 条边），返回 [{nodes:[...], edge_steps:[{edge,reversed}]}].
func _enumerate_paths(from_id: String, to_id: String, max_hops: int, max_paths: int) -> Array:
	var out: Array = []
	var stack: Array = [{"node": from_id, "nodes": [from_id], "edge_steps": []}]
	while not stack.is_empty() and out.size() < max_paths:
		var item: Dictionary = stack.pop_back()
		var cur := String(item.get("node", ""))
		var nodes_path: Array = item.get("nodes", [])
		var edge_steps: Array = item.get("edge_steps", [])
		if cur == to_id:
			out.append({"nodes": nodes_path, "edge_steps": edge_steps})
			continue
		if edge_steps.size() >= max_hops:
			continue
		var neigh: Array = adjacency.get(cur, [])
		for raw_n in neigh:
			var nn: Dictionary = raw_n
			var nxt := String(nn.get("to", ""))
			if nodes_path.has(nxt):
				continue
			var new_nodes: Array = nodes_path.duplicate()
			new_nodes.append(nxt)
			var new_steps: Array = edge_steps.duplicate()
			new_steps.append({"edge": nn.get("edge", {}), "reversed": bool(nn.get("reversed", false))})
			stack.append({"node": nxt, "nodes": new_nodes, "edge_steps": new_steps})
	return out


func _path_metrics(path_dict: Dictionary, cons: Dictionary) -> Dictionary:
	var nodes_path: Array = path_dict.get("nodes", [])
	var steps: Array = path_dict.get("edge_steps", [])
	var dv := 0.0
	var dur := 0.0
	var expo_sum := 0.0
	var risk_sum := 0.0
	var traffic := false
	var types: Array = []
	var edge_ids: Array = []
	var authorities: Array = []
	var corridors: Array = []
	for raw_step in steps:
		var step: Dictionary = raw_step
		var ed: Dictionary = step.get("edge", {})
		var eid := String(ed.get("id", ""))
		var travel_from := String(ed.get("from", ""))
		var reversed := bool(step.get("reversed", false))
		var actual_from := String(ed.get("to", "")) if reversed else travel_from
		var actual_to := String(ed.get("to", "")) if not reversed else String(ed.get("from", ""))
		dv += float(ed.get("dv_ms", 0.0))
		dur += float(ed.get("duration_s", 0.0))
		expo_sum += clampf(float(ed.get("exposure", 0.0)), 0.0, 1.0)
		risk_sum += clampf(float(ed.get("risk", 0.0)), 0.0, 1.0)
		if bool(ed.get("traffic_required", false)):
			traffic = true
			var auth := String(((nodes.get(actual_to, {}) as Dictionary).get("authority", "")))
			if auth != "" and not authorities.has(auth):
				authorities.append(auth)
			var auth_from := String(((nodes.get(actual_from, {}) as Dictionary).get("authority", "")))
			if auth_from != "" and not authorities.has(auth_from):
				authorities.append(auth_from)
		var tt := String(ed.get("transfer_type", ""))
		if tt != "" and not types.has(tt):
			types.append(tt)
		if eid != "" and not edge_ids.has(eid):
			edge_ids.append(eid)
		var corr := String(ed.get("corridor", ""))
		if corr != "" and not corridors.has(corr):
			corridors.append(corr)
	var hops := steps.size()
	var expo_avg := expo_sum / float(maxi(1, hops))
	var risk_avg := risk_sum / float(maxi(1, hops))
	var violations: Array = []
	var max_dv := float(cons.get("max_dv_ms", 0.0))
	if max_dv > 0.0 and dv > max_dv + 1.0e-6:
		violations.append("max_dv_ms")
	var max_dur := float(cons.get("max_duration_s", 0.0))
	if max_dur > 0.0 and dur > max_dur + 1.0e-6:
		violations.append("max_duration_s")
	var max_expo := float(cons.get("max_exposure", 1.0))
	if expo_avg > max_expo + 1.0e-6:
		violations.append("max_exposure")
	if bool(cons.get("avoid_traffic", false)) and traffic:
		violations.append("avoid_traffic")
	var exclude: Array = cons.get("exclude_transfer_types", []) if cons.get("exclude_transfer_types") is Array else []
	for et in exclude:
		if types.has(String(et)):
			violations.append("exclude_transfer_types:%s" % String(et))
			break
	var cons_hops := int(cons.get("max_hops", 0))
	if cons_hops > 0 and hops > cons_hops:
		violations.append("max_hops")
	return {
		"dv_ms": dv,
		"duration_s": dur,
		"hops": hops,
		"exposure_avg": expo_avg,
		"exposure_sum": expo_sum,
		"risk_avg": risk_avg,
		"risk_sum": risk_sum,
		"traffic_required": traffic,
		"transfer_types": types,
		"edge_ids": edge_ids,
		"clearance_authorities": authorities,
		"corridors": corridors,
		"feasible": violations.is_empty(),
		"violations": violations,
		"nodes_path": nodes_path.duplicate(),
	}


func _score_metrics(metrics: Dictionary, weights: Dictionary, max_dv: float, max_dur: float) -> float:
	var dv_n := float(metrics.get("dv_ms", 0.0)) / maxf(1.0e-6, max_dv)
	var dur_n := float(metrics.get("duration_s", 0.0)) / maxf(1.0e-6, max_dur)
	return float(weights.get("dv", 0.0)) * dv_n \
		+ float(weights.get("time", 0.0)) * dur_n \
		+ float(weights.get("exposure", 0.0)) * float(metrics.get("exposure_avg", 0.0)) \
		+ float(weights.get("risk", 0.0)) * float(metrics.get("risk_avg", 0.0))


func _candidate_from_metrics(path_dict: Dictionary, metrics: Dictionary, profile: String,
		profile_label: String, rank: int, score: float) -> Dictionary:
	var hops := int(metrics.get("hops", 0))
	return {
		"candidate_id": "",
		"profile": profile,
		"profile_label": profile_label,
		"from": String((path_dict.get("nodes", []) as Array)[0]) if hops > 0 else "",
		"to": String((path_dict.get("nodes", []) as Array)[-1]) if hops > 0 else "",
		"path": metrics.get("nodes_path", []),
		"edges": metrics.get("edge_ids", []),
		"transfer_types": metrics.get("transfer_types", []),
		"corridors": metrics.get("corridors", []),
		"hops": hops,
		"dv_ms": float(metrics.get("dv_ms", 0.0)),
		"duration_s": float(metrics.get("duration_s", 0.0)),
		"exposure": float(metrics.get("exposure_avg", 0.0)),
		"exposure_sum": float(metrics.get("exposure_sum", 0.0)),
		"risk": float(metrics.get("risk_avg", 0.0)),
		"risk_max_sum": float(metrics.get("risk_sum", 0.0)),
		"traffic_required": bool(metrics.get("traffic_required", false)),
		"clearance_authorities": metrics.get("clearance_authorities", []),
		"feasible": bool(metrics.get("feasible", false)),
		"violations": metrics.get("violations", []),
		"score": score,
		"rank": rank,
	}


## 选择候选路线（只写 selected_route，不执行、不消耗预算）。
func select_route(route_arg = null) -> Dictionary:
	if not ready:
		return _fail("not_ready")
	var route := _resolve_route(route_arg)
	if route.is_empty():
		return _fail("unknown_route")
	selected_route = route.duplicate(true)
	_event("route_selected", String(route.get("candidate_id", "")),
		"选中路线：%s（%s）" % [String(route.get("candidate_id", "")), String(route.get("profile", ""))])
	return {"ok": true, "selected": selected_route.duplicate(true)}


func _resolve_route(route_arg: Variant) -> Dictionary:
	if route_arg is Dictionary and not (route_arg as Dictionary).is_empty():
		var d: Dictionary = (route_arg as Dictionary).duplicate(true)
		if d.has("path") and d.has("dv_ms"):
			return d
	if route_arg is String and String(route_arg) != "":
		var cid := String(route_arg)
		for raw in last_routes:
			if raw is Dictionary and String((raw as Dictionary).get("candidate_id", "")) == cid:
				return (raw as Dictionary).duplicate(true)
		if not selected_route.is_empty() \
				and String(selected_route.get("candidate_id", "")) == cid:
			return selected_route.duplicate(true)
	if (route_arg is Dictionary and (route_arg as Dictionary).is_empty()) or route_arg == null:
		if not selected_route.is_empty():
			return selected_route.duplicate(true)
	return {}


# ═══════════════════════════════════════════════════════════════════
# 4. 交通管制（批准/拒绝/保持/过期；不自动执行）
# ═══════════════════════════════════════════════════════════════════

## 申请交通许可。route 可传候选 dict / candidate_id / 空（用 selected_route）。
## window: {open_t, close_t}；空 = t+min_lead 到 t+min_lead+slot。
## priority: 1（最高）..5（最低）。
## 返回 {ok, request_id, status, reason, reason_text, position, authority, ...}；
## granted/hold/denied 均写 requests；pending/hold 进 queue；不执行机动。
func request_clearance(route = null, window = null, priority := 3) -> Dictionary:
	if not ready:
		return _fail("not_ready")
	var route_dict := _resolve_route(route)
	var pmin := int(_priority_range()[0])
	var pmax := int(_priority_range()[1])
	var prio := int(priority)
	_req_seq += 1
	var req_id := "CLR-%04d" % _req_seq
	var rec: Dictionary = {
		"id": req_id,
		"route_id": String(route_dict.get("candidate_id", "")),
		"route_profile": String(route_dict.get("profile", "")),
		"from": String(route_dict.get("from", "")),
		"to": String(route_dict.get("to", "")),
		"dv_ms": float(route_dict.get("dv_ms", 0.0)),
		"duration_s": float(route_dict.get("duration_s", 0.0)),
		"exposure": float(route_dict.get("exposure", 0.0)),
		"traffic_required": bool(route_dict.get("traffic_required", false)),
		"priority": prio,
		"priority_label": String((traffic_cfg.get("priority_labels", {}) as Dictionary).get(str(prio), str(prio)))
			if traffic_cfg.get("priority_labels") is Dictionary else str(prio),
		"request_t": t,
		"status": "pending",
		"reason": "",
		"reason_text": "",
		"authority": String((traffic_cfg.get("authority_default", ""))),
		"window": {},
		"hold_until_t": -1.0,
		"granted_t": -1.0,
		"expires_t": -1.0,
		"queue_position": 0,
	}
	# 路由不存在
	if route_dict.is_empty():
		return _deny_request(rec, "unknown_route")
	# 约束不可行
	if not bool(route_dict.get("feasible", true)):
		return _deny_request(rec, "route_infeasible")
	# 优先级范围
	if prio < pmin or prio > pmax:
		return _deny_request(rec, "priority_range")
	# 时间窗
	var win := _normalize_window(window)
	rec["window"] = win
	if float(win.get("open_t", 0.0)) < t:
		return _deny_request(rec, "window_in_past")
	var min_lead := float(traffic_cfg.get("min_lead_s", 30.0))
	if float(win.get("close_t", 0.0)) <= t + min_lead:
		return _deny_request(rec, "window_closed")
	# 预算信息（交通许可不因 Δv 预算不足拒绝：许可是交通权，不是燃料/执行资格；
	# 预算由 plan/authorize/execute 的机动状态机检查）
	rec["budget_available_ms"] = available_dv_ms()
	rec["budget_ok"] = float(route_dict.get("dv_ms", 0.0)) <= available_dv_ms() + 1.0e-6
	# 权威/暴露：高暴露路线先 hold 等管制复核（只有会进入等待队列的请求才检查队列容量）
	var hold_threshold := float(traffic_cfg.get("hold_exposure_threshold", 0.35))
	var need_hold := float(route_dict.get("exposure", 0.0)) >= hold_threshold - 1.0e-9
	if need_hold:
		var max_q := maxi(1, int(traffic_cfg.get("max_queue", 6)))
		if queue.size() >= max_q:
			return _deny_request(rec, "queue_full")
	if need_hold:
		rec["status"] = "hold"
		rec["reason"] = "exposure_review"
		rec["reason_text"] = "高暴露路线：交通管制保持复核"
		rec["hold_until_t"] = t + float(traffic_cfg.get("hold_s", 600.0))
		requests.append(rec)
		queue.append(req_id)
		_resort_queue()
		rec["queue_position"] = queue.find(req_id) + 1
		_event("clearance_hold", req_id, "许可保持：%s（高暴露 %.2f）" % [req_id, float(rec["exposure"])])
		return _request_result(rec, "hold")
	# 批准
	rec["status"] = "granted"
	rec["reason"] = "granted" if bool(rec.get("traffic_required", false)) else "traffic_not_required"
	rec["reason_text"] = "许可批准" if bool(rec.get("traffic_required", false)) else "该航段无需交通许可（自动记录）"
	rec["granted_t"] = t
	rec["expires_t"] = t + float(traffic_cfg.get("validity_s", 1800.0))
	requests.append(rec)
	_event("clearance_granted", req_id, "许可批准：%s（%s，优先 %d）" % [
		req_id, String(rec.get("route_profile", "")), prio])
	return _request_result(rec, "granted")


func _deny_request(rec: Dictionary, reason_key: String) -> Dictionary:
	rec["status"] = "denied"
	rec["reason"] = reason_key
	rec["reason_text"] = _reason_text(reason_key)
	requests.append(rec)
	_event("clearance_denied", String(rec.get("id", "")),
		"许可拒绝：%s（%s）" % [String(rec.get("id", "")), rec["reason_text"]])
	var out := _request_result(rec, "denied")
	out["ok"] = false
	return out


func _request_result(rec: Dictionary, status: String) -> Dictionary:
	return {
		"ok": status == "granted" or status == "hold",
		"request_id": String(rec.get("id", "")),
		"status": status,
		"reason": String(rec.get("reason", "")),
		"reason_text": String(rec.get("reason_text", "")),
		"position": int(rec.get("queue_position", 0)),
		"authority": String(rec.get("authority", "")),
		"window": (rec.get("window", {}) as Dictionary).duplicate(true),
		"expires_t": float(rec.get("expires_t", -1.0)),
	}


func _normalize_window(window: Variant) -> Dictionary:
	var min_lead := float(traffic_cfg.get("min_lead_s", 30.0))
	var slot := float(traffic_cfg.get("window_slot_s", 3600.0))
	var out: Dictionary = {"open_t": t + min_lead, "close_t": t + min_lead + slot}
	if window is Dictionary:
		var w: Dictionary = window
		if w.has("open_t"):
			out["open_t"] = float(w.get("open_t", out["open_t"]))
		if w.has("close_t"):
			out["close_t"] = float(w.get("close_t", out["close_t"]))
	return out


## 管制员批准（pending/hold → granted）；不自动执行机动。
func grant_clearance(request_id: String) -> Dictionary:
	var req := _request_by_id(request_id)
	if req.is_empty():
		return _fail("unknown_request", {"request_id": request_id})
	if String(req.get("status", "")) != "pending" and String(req.get("status", "")) != "hold":
		return _fail("wrong_state", {"status": String(req.get("status", ""))})
	req["status"] = "granted"
	req["reason"] = "authority_granted"
	req["reason_text"] = "管制员批准"
	req["granted_t"] = t
	req["expires_t"] = t + float(traffic_cfg.get("validity_s", 1800.0))
	queue.erase(request_id)
	_resort_queue()
	_event("clearance_granted", request_id, "管制员批准许可：%s" % request_id)
	return {"ok": true, "request_id": request_id, "status": "granted",
		"expires_t": float(req["expires_t"])}


## 管制员拒绝（pending/hold → denied）。
func deny_clearance(request_id: String, reason := "authority_denied") -> Dictionary:
	var req := _request_by_id(request_id)
	if req.is_empty():
		return _fail("unknown_request", {"request_id": request_id})
	var st := String(req.get("status", ""))
	if st != "pending" and st != "hold":
		return _fail("wrong_state", {"status": st})
	req["status"] = "denied"
	req["reason"] = reason
	req["reason_text"] = _reason_text(reason)
	queue.erase(request_id)
	_resort_queue()
	_event("clearance_denied", request_id, "管制员拒绝许可：%s（%s）" % [request_id, reason])
	return {"ok": true, "request_id": request_id, "status": "denied", "reason": reason}


## 保持（pending → hold，可指定直到时间）。
func hold_clearance(request_id: String, until_t := -1.0) -> Dictionary:
	var req := _request_by_id(request_id)
	if req.is_empty():
		return _fail("unknown_request", {"request_id": request_id})
	var st0 := String(req.get("status", ""))
	if st0 != "pending" and st0 != "hold":
		return _fail("wrong_state", {"status": st0})
	req["status"] = "hold"
	req["reason"] = "authority_hold"
	req["reason_text"] = "管制员要求保持"
	req["hold_until_t"] = until_t if until_t >= 0.0 else t + float(traffic_cfg.get("hold_s", 600.0))
	if not queue.has(request_id):
		queue.append(request_id)
	_resort_queue()
	_event("clearance_hold", request_id, "管制员保持许可：%s" % request_id)
	return {"ok": true, "request_id": request_id, "status": "hold",
		"hold_until_t": float(req["hold_until_t"])}


func _request_by_id(request_id: String) -> Dictionary:
	for raw in requests:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == request_id:
			return raw
	return {}


func _resort_queue() -> void:
	queue = _sorted_queue_ids(queue)


func _sorted_queue_ids(ids: Array) -> Array:
	var out: Array = ids.duplicate()
	out.sort_custom(func(a, b):
		var ra := _request_by_id(String(a))
		var rb := _request_by_id(String(b))
		var pa := int(ra.get("priority", 99))
		var pb := int(rb.get("priority", 99))
		if pa != pb:
			return pa < pb
		var ta := float(ra.get("request_t", 0.0))
		var tb := float(rb.get("request_t", 0.0))
		if not is_equal_approx(ta, tb):
			return ta < tb
		return String(a) < String(b))
	return out


## 活动许可（已批准且未过期，按最近批准优先）。
func active_clearances() -> Array:
	var out: Array = []
	for raw in requests:
		if not (raw is Dictionary):
			continue
		var req: Dictionary = raw
		if String(req.get("status", "")) != "granted":
			continue
		if float(req.get("expires_t", -1.0)) > t:
			out.append(req)
	out.sort_custom(func(a, b): return float(a.get("granted_t", 0.0)) > float(b.get("granted_t", 0.0)))
	return out


func active_clearance() -> Dictionary:
	var list := active_clearances()
	return list[0].duplicate(true) if not list.is_empty() else {}


func clearance_status(request_id: String) -> Dictionary:
	var req := _request_by_id(request_id)
	return req.duplicate(true) if not req.is_empty() else {}


## 过期处理（step 内调用；也暴露给 probe/集成层）。
func expire_clearances(now := -1.0) -> Array:
	var at := t if now < 0.0 else float(now)
	var expired: Array = []
	for raw in requests:
		if not (raw is Dictionary):
			continue
		var req: Dictionary = raw
		var st := String(req.get("status", ""))
		if st != "granted" and st != "hold":
			continue
		var should_expire := false
		if st == "granted" and float(req.get("expires_t", -1.0)) >= 0.0 \
				and at >= float(req.get("expires_t", 0.0)):
			should_expire = true
		if st == "hold" and float(req.get("hold_until_t", -1.0)) >= 0.0 \
				and at >= float(req.get("hold_until_t", 0.0)):
			should_expire = true
		if not should_expire:
			continue
		req["status"] = "expired"
		req["reason"] = "expired"
		req["reason_text"] = "许可过期"
		queue.erase(String(req.get("id", "")))
		expired.append(String(req.get("id", "")))
		_event("clearance_expired", String(req.get("id", "")),
			"许可过期：%s" % String(req.get("id", "")))
	_resort_queue()
	return expired


# ═══════════════════════════════════════════════════════════════════
# 5. 机动状态机（PRE_ORDER→AUTHORIZED→QUEUED→EXECUTING→DONE/ABORTED）
# ═══════════════════════════════════════════════════════════════════

func plan_maneuver(kind: String, target := "", opts := {}) -> Dictionary:
	if not ready:
		return _fail("not_ready")
	var kinds := _maneuver_kinds()
	if not kinds.has(kind):
		return _fail("unknown_kind", {"kind": kind})
	var cfg: Dictionary = kinds[kind] if kinds[kind] is Dictionary else {}
	var req_target := bool(cfg.get("requires_target", false))
	if req_target and String(target) == "":
		return _fail("target_required", {"kind": kind})
	var dv := float(cfg.get("dv_ms", 0.0))
	if kind == "burn" and opts is Dictionary and (opts as Dictionary).has("dv_ms"):
		var total := float(budget_cfg.get("dv_total_ms", 1600.0))
		dv = clampf(float((opts as Dictionary).get("dv_ms", dv)), 1.0, total)
	_mnv_seq += 1
	var plan_id := "MNV-%04d" % _mnv_seq
	var plan: Dictionary = {
		"id": plan_id,
		"kind": kind,
		"label": String(cfg.get("label", kind)),
		"target": String(target),
		"state": "PRE_ORDER",
		"dv_ms": dv,
		"duration_s": maxf(0.001, float(cfg.get("duration_s", 60.0))),
		"exposure": clampf(float(cfg.get("exposure", 0.0)), 0.0, 1.0),
		"risk": clampf(float(cfg.get("risk", 0.0)), 0.0, 1.0),
		"requires_target": req_target,
		"requires_clearance": bool(cfg.get("requires_clearance", false)),
		"clearance_id": "",
		"created_t": t,
		"authorized_t": -1.0,
		"queued_t": -1.0,
		"exec_t": -1.0,
		"done_t": -1.0,
		"exec_elapsed_s": 0.0,
		"progress": 0.0,
		"reserved_ms": 0.0,
		"consumed_ms": 0.0,
		"abort_reason": "",
		"history": [],
	}
	planned_maneuvers.append(plan)
	_event("maneuver_planned", plan_id,
		"机动计划：%s %s（Δv %.0f m/s，预计 %.0f s）" % [plan_id, String(plan["label"]), dv, float(plan["duration_s"])])
	return {"ok": true, "plan_id": plan_id, "plan": _export_maneuver(plan)}


func authorize_maneuver(plan_id: String) -> Dictionary:
	var plan := _plan_by_id(plan_id)
	if plan.is_empty():
		return _fail("unknown_plan", {"plan_id": plan_id})
	if String(plan.get("state", "")) != "PRE_ORDER":
		return _fail("wrong_state", {"state": String(plan.get("state", ""))})
	var dv := float(plan.get("dv_ms", 0.0))
	if available_dv_ms() + 1.0e-9 < dv:
		return _fail("dv_budget", {"available_ms": available_dv_ms(), "required_ms": dv})
	plan["state"] = "AUTHORIZED"
	plan["authorized_t"] = t
	plan["reserved_ms"] = dv
	dv_committed_ms += dv
	_append_plan_history(plan, "PRE_ORDER", "AUTHORIZED", "commander_authorized")
	_event("maneuver_authorized", plan_id,
		"机动授权：%s（预留 Δv %.0f m/s）" % [plan_id, dv])
	return {"ok": true, "plan_id": plan_id, "state": "AUTHORIZED",
		"reserved_ms": dv, "available_ms": available_dv_ms()}


func queue_maneuver(plan_id: String, clearance_id := "") -> Dictionary:
	var plan := _plan_by_id(plan_id)
	if plan.is_empty():
		return _fail("unknown_plan", {"plan_id": plan_id})
	if String(plan.get("state", "")) != "AUTHORIZED":
		return _fail("wrong_state", {"state": String(plan.get("state", ""))})
	if bool(plan.get("requires_clearance", false)):
		var clr := _find_valid_clearance(clearance_id)
		if clr.is_empty():
			return _fail("clearance_required", {"plan_id": plan_id})
		plan["clearance_id"] = String(clr.get("id", ""))
	plan["state"] = "QUEUED"
	plan["queued_t"] = t
	_append_plan_history(plan, "AUTHORIZED", "QUEUED", "queued")
	_event("maneuver_queued", plan_id, "机动排队：%s" % plan_id)
	return {"ok": true, "plan_id": plan_id, "state": "QUEUED"}


func execute_maneuver(plan_id: String) -> Dictionary:
	var plan := _plan_by_id(plan_id)
	if plan.is_empty():
		return _fail("unknown_plan", {"plan_id": plan_id})
	if String(plan.get("state", "")) != "QUEUED":
		return _fail("wrong_state", {"state": String(plan.get("state", ""))})
	if bool(plan.get("requires_clearance", false)):
		var clr2 := _find_valid_clearance(String(plan.get("clearance_id", "")))
		if clr2.is_empty():
			return _fail("stale_clearance", {"plan_id": plan_id})
	plan["state"] = "EXECUTING"
	plan["exec_t"] = t
	plan["exec_elapsed_s"] = 0.0
	plan["progress"] = 0.0
	_append_plan_history(plan, "QUEUED", "EXECUTING", "execution_started")
	_event("maneuver_executing", plan_id, "机动执行：%s（%s）" % [plan_id, String(plan.get("label", ""))])
	return {"ok": true, "plan_id": plan_id, "state": "EXECUTING"}


## 中断（PRE_ORDER/AUTHORIZED/QUEUED 无消耗；EXECUTING 按进度消耗部分 Δv）。
func abort_maneuver(plan_id: String, reason := "commander_abort") -> Dictionary:
	var plan := _plan_by_id(plan_id)
	if plan.is_empty():
		return _fail("unknown_plan", {"plan_id": plan_id})
	var st := String(plan.get("state", ""))
	if _terminal_states().has(st):
		return _fail("wrong_state", {"state": st})
	var consumed := 0.0
	if st == "EXECUTING":
		var prog := clampf(float(plan.get("progress", 0.0)), 0.0, 1.0)
		consumed = float(plan.get("dv_ms", 0.0)) * prog
		dv_used_ms += consumed
		plan["consumed_ms"] = consumed
	dv_committed_ms = maxf(0.0, dv_committed_ms - float(plan.get("reserved_ms", 0.0)))
	plan["reserved_ms"] = 0.0
	plan["state"] = "ABORTED"
	plan["abort_reason"] = String(reason)
	_append_plan_history(plan, st, "ABORTED", String(reason))
	_event("maneuver_aborted", plan_id,
		"机动中断：%s（%s，Δv 消耗 %.0f m/s）" % [plan_id, String(reason), consumed])
	return {"ok": true, "plan_id": plan_id, "state": "ABORTED", "consumed_ms": consumed}


func _find_valid_clearance(clearance_id: String) -> Dictionary:
	if clearance_id != "":
		var req := _request_by_id(clearance_id)
		if not req.is_empty() and String(req.get("status", "")) == "granted" \
				and float(req.get("expires_t", -1.0)) > t:
			return req
		return {}
	return active_clearance()


func _plan_by_id(plan_id: String) -> Dictionary:
	for raw in planned_maneuvers:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == plan_id:
			return raw
	return {}


func _append_plan_history(plan: Dictionary, from_state: String, to_state: String, reason: String) -> void:
	var hist: Array = plan.get("history", [])
	hist.append({"t": t, "from": from_state, "to": to_state, "reason": reason})
	while hist.size() > 32:
		hist.pop_front()
	plan["history"] = hist


## 机动状态机推进（执行进度 / 完成 / 过期许可）。不改轨道物理。
func step(dt: float) -> Dictionary:
	if not ready:
		return _fail("not_ready")
	var d := maxf(0.0, float(dt))
	if d <= 0.0:
		return {"ok": true, "t": t, "events": [], "done": [], "budget": budget_vm()}
	t += d
	expire_clearances()
	var done: Array = []
	for raw in planned_maneuvers:
		var plan: Dictionary = raw
		if String(plan.get("state", "")) != "EXECUTING":
			continue
		var dur := maxf(0.001, float(plan.get("duration_s", 1.0)))
		plan["exec_elapsed_s"] = float(plan.get("exec_elapsed_s", 0.0)) + d
		plan["progress"] = clampf(float(plan["exec_elapsed_s"]) / dur, 0.0, 1.0)
		if float(plan["exec_elapsed_s"]) + 1.0e-9 >= dur:
			var dv := float(plan.get("dv_ms", 0.0))
			plan["state"] = "DONE"
			plan["done_t"] = t
			plan["progress"] = 1.0
			plan["consumed_ms"] = dv
			plan["reserved_ms"] = 0.0
			dv_used_ms += dv
			dv_committed_ms = maxf(0.0, dv_committed_ms - dv)
			_append_plan_history(plan, "EXECUTING", "DONE", "completed")
			done.append(String(plan.get("id", "")))
			_event("maneuver_done", String(plan.get("id", "")),
				"机动完成：%s（消耗 Δv %.0f m/s）" % [String(plan.get("id", "")), dv])
	return {"ok": true, "t": t, "done": done, "budget": budget_vm()}


# ═══════════════════════════════════════════════════════════════════
# 6. 预算（只读；规划不消耗，执行才消耗）
# ═══════════════════════════════════════════════════════════════════

func budget_total_ms() -> float:
	return float(budget_cfg.get("dv_total_ms", 0.0))


func budget_reserve_ms() -> float:
	return float(budget_cfg.get("dv_reserve_ms", 0.0))


func available_dv_ms() -> float:
	return maxf(0.0, budget_total_ms() - budget_reserve_ms() - dv_used_ms - dv_committed_ms)


func budget_vm() -> Dictionary:
	var total := budget_total_ms()
	var reserve := budget_reserve_ms()
	var spendable := maxf(1.0e-6, total - reserve)
	var avail := available_dv_ms()
	var used_ratio := dv_used_ms / spendable
	var warn_ratio := float(budget_cfg.get("warn_ratio", 0.75))
	return {
		"dv_total_ms": total,
		"dv_reserve_ms": reserve,
		"dv_used_ms": dv_used_ms,
		"dv_committed_ms": dv_committed_ms,
		"dv_available_ms": avail,
		"used_ratio": clampf(used_ratio, 0.0, 2.0),
		"warn_ratio": warn_ratio,
		"warning": used_ratio >= warn_ratio,
		"exhausted": avail <= 1.0e-9,
	}


# ═══════════════════════════════════════════════════════════════════
# 7. 只读 view-model / 摘要
# ═══════════════════════════════════════════════════════════════════

func vm_navigation() -> Dictionary:
	if not ready:
		return {"schema": SCHEMA, "ready": false, "t": t, "errors": errors.duplicate()}
	var node_rows: Array = []
	for nid in nodes.keys():
		var node: Dictionary = nodes[nid]
		var pos := node_position_km(String(nid))
		node_rows.append({
			"id": String(nid),
			"name": String(node.get("name", "")),
			"kind": String(node.get("kind", "")),
			"position_source": String(node.get("position_source", "")),
			"pos_km": pos,
			"authority": String(node.get("authority", "")),
			"traffic_class": String(node.get("traffic_class", "")),
			"capacity": int(node.get("capacity", 1)),
		})
	node_rows.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	var man_rows: Array = []
	for raw in planned_maneuvers:
		man_rows.append(_export_maneuver(raw))
	var clearance_rows: Array = []
	var queue_rows: Array = []
	for raw_req in requests:
		if not (raw_req is Dictionary):
			continue
		var req: Dictionary = raw_req
		var st := String(req.get("status", ""))
		if st == "granted" or st == "hold" or st == "pending":
			clearance_rows.append(_export_request(req, false))
		if st == "pending" or st == "hold":
			queue_rows.append(_export_request(req, true))
	queue_rows.sort_custom(func(a, b):
		var pa := int(a.get("priority", 99))
		var pb := int(b.get("priority", 99))
		if pa != pb:
			return pa < pb
		return String(a.get("id", "")) < String(b.get("id", "")))
	return {
		"schema": SCHEMA,
		"id": String(content.get("id", "")),
		"title": String(content.get("title", "")),
		"ready": true,
		"model_kind": "planning_abstract",
		"authoritative": false,
		"t": t,
		"nodes": node_rows,
		"routes": last_routes.duplicate(true),
		"selected": selected_route.duplicate(true),
		"clearance": active_clearance(),
		"clearances": clearance_rows,
		"queue": queue_rows,
		"planned_maneuvers": man_rows,
		"budget": budget_vm(),
		"limits": {
			"max_hops": int(route_cfg.get("max_hops", 3)),
			"max_queue": int(traffic_cfg.get("max_queue", 6)),
			"priority_range": _priority_range().duplicate(),
			"profiles": _profiles().duplicate(),
			"maneuver_states": _state_order().duplicate(),
			"terminal_states": _terminal_states().duplicate(),
			"hold_exposure_threshold": float(traffic_cfg.get("hold_exposure_threshold", 0.35)),
			"min_lead_s": float(traffic_cfg.get("min_lead_s", 30.0)),
			"validity_s": float(traffic_cfg.get("validity_s", 1800.0)),
		},
		"events": _events_vm(),
		"summary": summary(),
	}


func summary() -> Dictionary:
	var by_state: Dictionary = {}
	for raw in planned_maneuvers:
		var st := String((raw as Dictionary).get("state", ""))
		by_state[st] = int(by_state.get(st, 0)) + 1
	var queue_pending := 0
	var granted := 0
	var holds := 0
	var denied := 0
	for raw_req in requests:
		match String((raw_req as Dictionary).get("status", "")):
			"pending":
				queue_pending += 1
			"granted":
				granted += 1
			"hold":
				holds += 1
			"denied":
				denied += 1
	return {
		"nodes": nodes.size(),
		"edges": edges.size(),
		"routes": last_routes.size(),
		"selected": String(selected_route.get("candidate_id", "")),
		"requests": requests.size(),
		"queue": queue.size(),
		"pending": queue_pending,
		"hold": holds,
		"granted": granted,
		"denied": denied,
		"maneuvers": planned_maneuvers.size(),
		"maneuver_states": by_state,
		"budget": budget_vm(),
	}


## 状态签名（probe 验证「规划不执行/不改物理」用）。
func state_signature() -> String:
	var parts: Array = [str(t), "%.3f" % dv_used_ms, "%.3f" % dv_committed_ms,
		str(requests.size()), str(queue.size()), str(planned_maneuvers.size()),
		String(selected_route.get("candidate_id", ""))]
	for raw in planned_maneuvers:
		parts.append("%s:%s" % [String((raw as Dictionary).get("id", "")),
			String((raw as Dictionary).get("state", ""))])
	return "|".join(parts)


func _export_maneuver(plan: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"id": String(plan.get("id", "")),
		"kind": String(plan.get("kind", "")),
		"label": String(plan.get("label", "")),
		"target": String(plan.get("target", "")),
		"state": String(plan.get("state", "")),
		"dv_ms": float(plan.get("dv_ms", 0.0)),
		"duration_s": float(plan.get("duration_s", 0.0)),
		"exposure": float(plan.get("exposure", 0.0)),
		"risk": float(plan.get("risk", 0.0)),
		"requires_target": bool(plan.get("requires_target", false)),
		"requires_clearance": bool(plan.get("requires_clearance", false)),
		"clearance_id": String(plan.get("clearance_id", "")),
		"created_t": float(plan.get("created_t", 0.0)),
		"authorized_t": float(plan.get("authorized_t", -1.0)),
		"queued_t": float(plan.get("queued_t", -1.0)),
		"exec_t": float(plan.get("exec_t", -1.0)),
		"done_t": float(plan.get("done_t", -1.0)),
		"exec_elapsed_s": float(plan.get("exec_elapsed_s", 0.0)),
		"progress": float(plan.get("progress", 0.0)),
		"reserved_ms": float(plan.get("reserved_ms", 0.0)),
		"consumed_ms": float(plan.get("consumed_ms", 0.0)),
		"abort_reason": String(plan.get("abort_reason", "")),
		"history": (plan.get("history", []) as Array).duplicate(true),
	}
	return out


func _export_request(req: Dictionary, with_position: bool) -> Dictionary:
	var out: Dictionary = {
		"id": String(req.get("id", "")),
		"route_id": String(req.get("route_id", "")),
		"route_profile": String(req.get("route_profile", "")),
		"from": String(req.get("from", "")),
		"to": String(req.get("to", "")),
		"dv_ms": float(req.get("dv_ms", 0.0)),
		"exposure": float(req.get("exposure", 0.0)),
		"traffic_required": bool(req.get("traffic_required", false)),
		"priority": int(req.get("priority", 99)),
		"priority_label": String(req.get("priority_label", "")),
		"request_t": float(req.get("request_t", 0.0)),
		"status": String(req.get("status", "")),
		"reason": String(req.get("reason", "")),
		"reason_text": String(req.get("reason_text", "")),
		"authority": String(req.get("authority", "")),
		"window": (req.get("window", {}) as Dictionary).duplicate(true),
		"hold_until_t": float(req.get("hold_until_t", -1.0)),
		"granted_t": float(req.get("granted_t", -1.0)),
		"expires_t": float(req.get("expires_t", -1.0)),
	}
	if with_position:
		out["position"] = queue.find(String(req.get("id", ""))) + 1
	return out


func _events_vm() -> Array:
	var out: Array = []
	var start := maxi(0, events.size() - VM_EVENT_LIMIT)
	for i in range(start, events.size()):
		out.append((events[i] as Dictionary).duplicate(true))
	return out


func to_dict() -> Dictionary:
	return vm_navigation()


# ═══════════════════════════════════════════════════════════════════
# 8. 事件 / 工具
# ═══════════════════════════════════════════════════════════════════

func _event(kind: String, ref_id: String, text: String, extra := {}) -> void:
	var ev: Dictionary = {
		"t": t,
		"kind": kind,
		"ref": ref_id,
		"text": text,
	}
	if extra is Dictionary:
		ev.merge(extra, true)
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)


func _fail(reason: String, extra := {}) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": reason, "reason_text": _reason_text(reason)}
	if extra is Dictionary:
		out.merge(extra, true)
	out["errors"] = [reason]
	return out
