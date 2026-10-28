class_name V2CommsService
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2B · 通信服务骨架（CommsService）
#
# 职责：
#   * 节点/链路（LD / LR / RDO / IR / VIS）建模：延迟、带宽、丢包、干扰、遮挡、
#     中继路由；发送/投递/失败；不实现物理/UI/ROE。
#   * 所有文本通过独立 TextLibrary 解析：text_key 选择模板 + from/to/mode 变量
#     替换；服务内不硬编码舰名/对白。
#   * 事件驱动：send/tick 产出 comms_event.v1；事件含动态文本。
#
# 边界：本服务只维护自己的时间/投递队列；不读 game_v17 HUD/state/bridge/world，
# 不写 V15；遮挡/干扰/距离由调用方以链路参数或 opts 提供（不在此做轨道物理）。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA_EVENT := "comms_event.v1"
const SCHEMA_VM := "comms_service.v1"
const SCHEMA_LINK := "comms_link.v1"
const MODES := ["LD", "LR", "RDO", "IR", "VIS"]
const MODE_DEFAULTS := {
	"LD": {"latency_s": 0.1, "range_km": 150000.0, "requires_los": true,
		"bandwidth_kbps": 1000.0},
	"LR": {"latency_s": 0.35, "range_km": 200000.0, "requires_los": true,
		"bandwidth_kbps": 500.0},
	"RDO": {"latency_s": 2.0, "range_km": 300000.0, "requires_los": false,
		"bandwidth_kbps": 64.0},
	"IR": {"latency_s": 0.2, "range_km": 12000.0, "requires_los": true,
		"bandwidth_kbps": 128.0},
	"VIS": {"latency_s": 0.05, "range_km": 2000.0, "requires_los": true,
		"bandwidth_kbps": 8.0},
}
const DEFAULT_JAM_THRESHOLD := 0.7
const MAX_EVENTS := 200
const MAX_PENDING := 200
const MAX_TEXT_ENTRIES := 256


# ── 独立文本库（内嵌接口；可被 order_service 复用）────────────────
class TextLibrary:
	extends RefCounted
	const SCHEMA := "comms_text_library.v1"
	var entries: Dictionary = {}      # text_key -> Array[entry]
	var errors: Array = []
	var warnings: Array = []
	var use_count: Dictionary = {}
	var last_use_t: Dictionary = {}

	func add_entry(entry: Dictionary) -> bool:
		var key := String(entry.get("text_key", entry.get("key", "")))
		if key == "":
			errors.append("text entry 缺 text_key")
			return false
		var template := String(entry.get("template", ""))
		var variants: Array = entry.get("variants", []) if entry.get("variants") is Array else []
		if template == "" and variants.is_empty():
			errors.append("text_key %s 缺 template/variants" % key)
			return false
		var e: Dictionary = entry.duplicate(true)
		e["text_key"] = key
		if not (entries.get(key) is Array):
			entries[key] = []
		if (entries[key] as Array).size() >= MAX_TEXT_ENTRIES:
			warnings.append("text_key %s 条目过多" % key)
			return false
		(entries[key] as Array).append(e)
		return true

	func add_entries(arr: Array) -> int:
		var n := 0
		for raw in arr:
			if raw is Dictionary and add_entry(raw as Dictionary):
				n += 1
		return n

	func has(key: String) -> bool:
		return (entries.get(key) is Array) and not (entries[key] as Array).is_empty()

	func keys() -> Array:
		var out: Array = entries.keys()
		out.sort()
		return out

	func _ctx_value(ctx: Dictionary, key: String) -> Variant:
		if ctx.has(key):
			return ctx[key]
		return null

	func _resolve_identity(ctx: Dictionary, side: String) -> String:
		var cands := [side, side + "_name", side + "_id", side + "_role"]
		for c in cands:
			var ck := String(c)
			if ctx.has(ck) and String(ctx.get(ck, "")) != "":
				return String(ctx.get(ck, ""))
		return ""

	func _match(entry: Dictionary, ctx: Dictionary) -> bool:
		var channel := String(entry.get("channel", ""))
		var ch := String(ctx.get("channel", ""))
		if channel != "" and channel != "*" and channel != "ALL" and ch != "" and channel != ch:
			return false
		var mode := String(entry.get("mode", ""))
		var cm := String(ctx.get("mode", ""))
		if mode != "" and mode != cm:
			return false
		for role_key in ["speaker_role", "listener_role"]:
			var rv := String(entry.get(role_key, ""))
			if rv != "":
				var ctx_role := String(ctx.get("from_role" if role_key == "speaker_role" else "to_role", ""))
				if ctx_role != rv:
					return false
		return true

	func _template_for(entry: Dictionary, ctx: Dictionary) -> String:
		if entry.get("template_by_role") is Dictionary:
			var tbr: Dictionary = entry.get("template_by_role")
			var fr := String(ctx.get("from_role", ""))
			if fr != "" and tbr.has(fr):
				return String(tbr[fr])
			var tr := String(ctx.get("to_role", ""))
			if tr != "" and tbr.has(tr):
				return String(tbr[tr])
		var variants: Array = entry.get("variants", []) if entry.get("variants") is Array else []
		if not variants.is_empty():
			var idx := 0
			if ctx.has("variant_index"):
				idx = int(ctx.get("variant_index", 0))
			else:
				idx = int(use_count.get(String(entry.get("text_key", "")), 0))
			idx = posmod(idx, variants.size())
			return String(variants[idx])
		return String(entry.get("template", ""))

	func render_template(template: String, vars: Dictionary) -> Dictionary:
		var re := RegEx.new()
		re.compile("\\{([a-zA-Z0-9_]+)\\}")
		var missing: Array = []
		var text := template
		var matches := re.search_all(template)
		for m in matches:
			var name := String(m.get_string(1))
			if not vars.has(name):
				missing.append(name)
				continue
			var val = vars[name]
			var s := ""
			if val is float:
				s = trim_num(float(val))
			else:
				s = str(val)
			text = text.replace("{" + name + "}", s)
		if not missing.is_empty():
			return {"ok": false, "reason": "missing_var:" + ",".join(missing),
				"missing": missing, "text": ""}
		return {"ok": true, "reason": "", "text": text, "missing": []}

	func trim_num(v: float) -> String:
		if absf(v - roundf(v)) < 1.0e-9:
			return str(int(roundf(v)))
		return "%.2f" % v

	## 选择模板并解析 from/to/mode；未知 key/缺变量均返回 ok=false（DbC，不静默）。
	func select(key: String, ctx := {}) -> Dictionary:
		if not has(key):
			return {"ok": false, "reason": "unknown_text_key", "text_key": key,
				"text": "", "from": "", "to": "", "mode": ""}
		var context: Dictionary = ctx if ctx is Dictionary else {}
		var list: Array = entries[key]
		var candidates: Array = []
		for raw in list:
			if raw is Dictionary and _match(raw as Dictionary, context):
				candidates.append(raw)
		if candidates.is_empty():
			candidates = list
		var best: Dictionary = candidates[0]
		for raw in candidates:
			var e: Dictionary = raw
			if int(e.get("priority", 0)) > int(best.get("priority", 0)):
				best = e
		var template := _template_for(best, context)
		var vars: Dictionary = context.duplicate(true)
		if not vars.has("from") or String(vars.get("from", "")) == "":
			vars["from"] = _resolve_identity(context, "from")
		if not vars.has("to") or String(vars.get("to", "")) == "":
			vars["to"] = _resolve_identity(context, "to")
		if not vars.has("mode"):
			vars["mode"] = String(context.get("mode", ""))
		var r: Dictionary = render_template(template, vars)
		use_count[key] = int(use_count.get(key, 0)) + 1
		if not bool(r.get("ok", false)):
			return {"ok": false, "reason": String(r.get("reason", "")), "text_key": key,
				"text": "", "from": String(vars.get("from", "")), "to": String(vars.get("to", "")),
				"mode": String(vars.get("mode", "")), "template": template}
		return {"ok": true, "reason": "", "schema": SCHEMA, "text_key": key,
			"text": String(r.get("text", "")), "template": template,
			"from": String(vars.get("from", "")), "to": String(vars.get("to", "")),
			"mode": String(vars.get("mode", "")),
			"from_role": String(context.get("from_role", "")),
			"to_role": String(context.get("to_role", ""))}

	func to_dict() -> Dictionary:
		return {"schema": SCHEMA, "keys": keys(), "entry_count": _count(),
			"errors": errors.duplicate(), "warnings": warnings.duplicate()}

	func _count() -> int:
		var n := 0
		for k in entries.keys():
			n += (entries[k] as Array).size()
		return n


# ── 服务状态 ─────────────────────────────────────────────────────
var ready := false
var t := 0.0
var dt_last := 0.0
var step_count := 0
var errors: Array = []
var warnings: Array = []
var nodes: Dictionary = {}         # id -> node dict
var links: Array = []             # link dicts
var pending: Array = []           # 待投递
var events: Array = []            # 全量事件（JSON）
var _outbox: Array = []           # 自上次 tick/take_events 的新事件
var text_library = null
var config: Dictionary = {}
var _delivery_seq := 0
var _event_seq := 0
var _jam_threshold := DEFAULT_JAM_THRESHOLD
# JC-A04：发送时刻的 EW 链路 effect + 确定性抽样状态（随档保存）
var ew_service = null
var _ew_seed := 0
var _ew_seq := 0
var _ew_forced_draw := -1.0   # 测试注入：一次性覆盖下一条 draw；不进存档/公开玩家选项
var _sender_authorizer = null  # Session 注入：校验 sender 与 actor/controller/fleet/owner 上下文

var _event_out: Array = []        # 兼容别名


func _init(cfg := {}) -> void:
	setup(cfg)


func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	nodes = {}
	links = []
	pending = []
	events = []
	_outbox = []
	t = 0.0
	dt_last = 0.0
	step_count = 0
	_delivery_seq = 0
	_event_seq = 0
	_jam_threshold = DEFAULT_JAM_THRESHOLD
	config = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	_jam_threshold = float(config.get("jam_threshold", DEFAULT_JAM_THRESHOLD))
	if config.get("text_library") is Object and (config.get("text_library") as Object).has_method("select"):
		text_library = config.get("text_library")
	else:
		text_library = TextLibrary.new()
		_add_default_text_entries()
	if config.get("text_entries") is Array:
		text_library.add_entries(config.get("text_entries") as Array)
	for raw in (config.get("nodes", []) as Array):
		if raw is Dictionary:
			add_node(raw as Dictionary)
	for raw in (config.get("links", []) as Array):
		if raw is Dictionary:
			add_link(raw as Dictionary)
	ready = errors.is_empty()
	return ready


func _add_default_text_entries() -> void:
	# 通用模板，无具体舰名；from/to/mode 由上下文替换。
	text_library.add_entries([
		{"text_key": "COMMS_SENT",
			"template": "[{from} 至 {to}]-[{mode}]-[{content}]",
			"channel": "comms", "priority": 0},
		{"text_key": "COMMS_DELIVERED",
			"template": "[{from} 至 {to}]-[{mode}]-[送达] {content}",
			"channel": "comms", "priority": 0},
		{"text_key": "COMMS_FAILED",
			"template": "[{from} 至 {to}]-[{mode}]-[投递失败：{reason_text}]",
			"channel": "comms", "priority": 0},
		{"text_key": "COMMS_RELAYED",
			"template": "[{from} 至 {to}]-[{mode}]-[经中继 {relay_count} 跳] {content}",
			"channel": "comms", "priority": 1},
	])


# ── 节点/链路管理 ────────────────────────────────────────────────

func add_node(raw: Dictionary) -> bool:
	var id := String(raw.get("id", ""))
	if id == "":
		errors.append("node 缺 id")
		return false
	if nodes.has(id):
		errors.append("node 重复 id: " + id)
		return false
	nodes[id] = {
		"id": id, "name": String(raw.get("name", id)), "role": String(raw.get("role", "")),
		"type": String(raw.get("type", "ship")), "antenna": String(raw.get("antenna", "")),
		"power": float(raw.get("power", 1.0)), "encryption": String(raw.get("encryption", "none")),
		"status": String(raw.get("status", "ok")), "enabled": bool(raw.get("enabled", true)),
		"damage": float(raw.get("damage", 0.0)),
	}
	return true


func add_link(raw: Dictionary) -> bool:
	var a := String(raw.get("a", raw.get("from", "")))
	var b := String(raw.get("b", raw.get("to", "")))
	var mode := String(raw.get("mode", "LD")).to_upper()
	if a == "" or b == "" or a == b:
		errors.append("link 端点非法")
		return false
	if not nodes.has(a) or not nodes.has(b):
		errors.append("link 引用未知节点: %s-%s" % [a, b])
		return false
	if not (mode in MODES):
		errors.append("link 未知 mode: " + mode)
		return false
	var d: Dictionary = MODE_DEFAULTS.get(mode, {})
	links.append({
		"schema": SCHEMA_LINK, "id": String(raw.get("id", "L%d" % links.size())),
		"a": a, "b": b, "mode": mode,
		"latency_s": float(raw.get("latency_s", d.get("latency_s", 1.0))),
		"range_km": float(raw.get("range_km", d.get("range_km", 0.0))),
		"bandwidth_kbps": float(raw.get("bandwidth_kbps", d.get("bandwidth_kbps", 64.0))),
		"packet_loss": clampf(float(raw.get("packet_loss", 0.0)), 0.0, 1.0),
		"jam": clampf(float(raw.get("jam", 0.0)), 0.0, 1.0),
		"occluded": bool(raw.get("occluded", false)),
		"requires_los": bool(raw.get("requires_los", d.get("requires_los", true))),
		"enabled": bool(raw.get("enabled", true)),
		"relay_penalty_s": float(raw.get("relay_penalty_s", 0.2)),
	})
	return true


func _link_index(a: String, b: String, mode := "") -> int:
	for i in range(links.size()):
		var l: Dictionary = links[i]
		if String(l.get("mode", "")) != mode and mode != "":
			continue
		var la := String(l.get("a", ""))
		var lb := String(l.get("b", ""))
		if (la == a and lb == b) or (la == b and lb == a):
			return i
	return -1


func set_link_enabled(a: String, b: String, en: bool, mode := "") -> bool:
	var idx := _link_index(a, b, mode)
	if idx < 0:
		return false
	(links[idx] as Dictionary)["enabled"] = bool(en)
	return true


func set_link_occluded(a: String, b: String, occ: bool, mode := "") -> bool:
	var idx := _link_index(a, b, mode)
	if idx < 0:
		return false
	(links[idx] as Dictionary)["occluded"] = bool(occ)
	return true


func set_link_jam(a: String, b: String, jam: float, mode := "") -> bool:
	var idx := _link_index(a, b, mode)
	if idx < 0:
		return false
	(links[idx] as Dictionary)["jam"] = clampf(jam, 0.0, 1.0)
	return true


func set_node_status(id: String, status: String, damage := -1.0) -> bool:
	if not nodes.has(id):
		return false
	(nodes[id] as Dictionary)["status"] = status
	if damage >= 0.0:
		(nodes[id] as Dictionary)["damage"] = clampf(damage, 0.0, 1.0)
	return true


func node(id: String) -> Dictionary:
	var n = nodes.get(id, null)
	return (n as Dictionary).duplicate(true) if n is Dictionary else {}


func _node_ok(id: String) -> bool:
	var n = nodes.get(id, null)
	if not (n is Dictionary):
		return false
	var d: Dictionary = n
	if not bool(d.get("enabled", true)):
		return false
	if String(d.get("status", "ok")) in ["offline", "destroyed", "failed"]:
		return false
	if float(d.get("damage", 0.0)) >= 1.0:
		return false
	return true


func _check_link(link: Dictionary, distance_km := -1.0) -> Dictionary:
	if not bool(link.get("enabled", true)):
		return {"ok": false, "reason": "link_disabled"}
	if not _node_ok(String(link.get("a", ""))) or not _node_ok(String(link.get("b", ""))):
		return {"ok": false, "reason": "node_unavailable"}
	if bool(link.get("occluded", false)) and bool(link.get("requires_los", true)):
		return {"ok": false, "reason": "occluded"}
	if float(link.get("jam", 0.0)) >= _jam_threshold:
		return {"ok": false, "reason": "jammed"}
	var range_km := float(link.get("range_km", 0.0))
	if distance_km >= 0.0 and range_km > 0.0 and distance_km > range_km + 1.0e-9:
		return {"ok": false, "reason": "out_of_range"}
	return {"ok": true, "reason": ""}


## 路由：直连优先；否则单中继；返回 {ok,path,links,latency_s,relay_count,reason}。
func find_route(from_id: String, to_id: String, mode: String, opts := {}) -> Dictionary:
	if not nodes.has(from_id) or not nodes.has(to_id):
		return {"ok": false, "reason": "unknown_node", "path": [], "links": []}
	if from_id == to_id:
		return {"ok": false, "reason": "same_node", "path": [], "links": []}
	var o: Dictionary = opts if opts is Dictionary else {}
	var dist := float(o.get("distance_km", -1.0))
	var reasons: Array = []
	var candidates: Array = []
	# 直连
	for i in range(links.size()):
		var l: Dictionary = links[i]
		if String(l.get("mode", "")) != mode:
			continue
		var la := String(l.get("a", ""))
		var lb := String(l.get("b", ""))
		if not ((la == from_id and lb == to_id) or (la == to_id and lb == from_id)):
			continue
		var chk := _check_link(l, dist)
		if bool(chk.get("ok", false)):
			candidates.append({"path": [from_id, to_id], "links": [i],
				"latency_s": float(l.get("latency_s", 0.0)), "relay_count": 0})
		else:
			reasons.append(String(chk.get("reason", "blocked")))
	# 单中继
	for rid in nodes.keys():
		var r := String(rid)
		if r == from_id or r == to_id:
			continue
		if not _node_ok(r):
			continue
		var i1 := _find_link_dir(from_id, r, mode)
		var i2 := _find_link_dir(r, to_id, mode)
		if i1 < 0 or i2 < 0:
			continue
		var l1: Dictionary = links[i1]
		var l2: Dictionary = links[i2]
		var c1 := _check_link(l1, dist)
		var c2 := _check_link(l2, dist)
		if not bool(c1.get("ok", false)):
			reasons.append(String(c1.get("reason", "blocked")))
			continue
		if not bool(c2.get("ok", false)):
			reasons.append(String(c2.get("reason", "blocked")))
			continue
		var lat := float(l1.get("latency_s", 0.0)) + float(l2.get("latency_s", 0.0)) + 0.2
		candidates.append({"path": [from_id, r, to_id], "links": [i1, i2],
			"latency_s": lat, "relay_count": 1})
	if candidates.is_empty():
		var reason := "no_route"
		if not reasons.is_empty():
			reason = String(reasons[0])
		return {"ok": false, "reason": reason, "path": [], "links": []}
	var best: Dictionary = candidates[0]
	for raw in candidates:
		var c: Dictionary = raw
		if float(c.get("latency_s", 0.0)) < float(best.get("latency_s", 0.0)):
			best = c
	return {"ok": true, "reason": "", "mode": mode,
		"path": (best.get("path", []) as Array).duplicate(),
		"links": (best.get("links", []) as Array).duplicate(),
		"latency_s": float(best.get("latency_s", 0.0)),
		"relay_count": int(best.get("relay_count", 0))}


func _find_link_dir(a: String, b: String, mode: String) -> int:
	for i in range(links.size()):
		var l: Dictionary = links[i]
		if String(l.get("mode", "")) != mode:
			continue
		var la := String(l.get("a", ""))
		var lb := String(l.get("b", ""))
		if (la == a and lb == b) or (la == b and lb == a):
			return i
	return -1


# ── EW 链路采样（JC-A04）─────────────────────────────────────────

# 接线：EW 服务提供发送时刻链路 effect（纯读，不写 world/TrackTable）。
func set_ew_service(obj) -> void:
	ew_service = obj


# R1：Session 注入的 sender↔actor/controller/fleet/owner 校验器。
func set_sender_authorizer(fn) -> void:
	_sender_authorizer = fn


# 确定性抽样：同 seed + 发送顺序 → 同 draw；真实文件恢复保留 seed/seq。
func set_ew_rng(seed_value: int) -> void:
	_ew_seed = int(seed_value)


func reset_ew_rng(seed_value := 0) -> void:
	_ew_seed = int(seed_value)
	_ew_seq = 0


func ew_rng_state() -> Dictionary:
	return {"seed": _ew_seed, "seq": _ew_seq}


# 测试注入：仅影响下一条 draw；不保存、不公开为玩家选项。
func debug_force_draw(x: float) -> void:
	_ew_forced_draw = clampf(float(x), 0.0, 1.0)


func _ew_draw_next(delivery_id: String, from_id: String) -> float:
	_ew_seq += 1
	if _ew_forced_draw >= 0.0:
		var forced := _ew_forced_draw
		_ew_forced_draw = -1.0
		return forced
	var hs := "%d|%d|%s|%s" % [_ew_seed, _ew_seq, delivery_id, from_id]
	return float(hash(hs) & 0x7fffffff) / 2147483647.0


# 发送时刻冻结：返回本次实际使用的 EW 采样（含确定性 draw/will_fail）。
func _sample_ew_for_send(to_id: String, delivery_id: String, from_id: String,
		ignore_ew := false) -> Dictionary:
	var snap := {"jam_severity": 0.0, "latency_add_s": 0.0,
		"failure_chance": 0.0, "draw": -1.0, "will_fail": false,
		"sampled_t": t, "target_id": to_id, "ignored": ignore_ew}
	if ignore_ew:
		return snap
	if ew_service != null and ew_service.has_method("comms_effect"):
		# 链路两端都可能是 EW 作用对象：取两端商业 effect 的最大 severity 组合，
		# 一次发送只抽一次 draw（发送时刻冻结）。
		var eff_to: Dictionary = ew_service.comms_effect(to_id)
		var eff_from: Dictionary = ew_service.comms_effect(from_id)
		var jam := maxf(clampf(float(eff_to.get("jam_severity", 0.0)), 0.0, 1.0),
			clampf(float(eff_from.get("jam_severity", 0.0)), 0.0, 1.0))
		var add := maxf(maxf(0.0, float(eff_to.get("latency_add_s", 0.0))),
			maxf(0.0, float(eff_from.get("latency_add_s", 0.0))))
		var fc := maxf(clampf(float(eff_to.get("failure_chance", 0.0)), 0.0, 1.0),
			clampf(float(eff_from.get("failure_chance", 0.0)), 0.0, 1.0))
		var draw := _ew_draw_next(delivery_id, from_id)
		snap = {"jam_severity": jam, "latency_add_s": add,
			"failure_chance": fc, "draw": draw, "will_fail": draw < fc,
			"sampled_t": t, "target_id": to_id,
			"from_id": from_id, "ignored": false}
	return snap


# ── 发送 / 投递 ──────────────────────────────────────────────────

func send(from_id: String, to_id: String, mode: String, text_key: String,
		payload := {}, opts := {}) -> Dictionary:
	# R2：普通发送不得请求 EW 旁路；只有 v1 迁移路径可走 send_legacy_v1。
	if opts is Dictionary and (opts as Dictionary).has("ignore_ew"):
		return _fail_send(from_id, to_id, String(mode).to_upper(), text_key,
			"ew_bypass_forbidden")
	return _send_core(from_id, to_id, mode, text_key, payload, opts, false)


## 仅供 v1 outcome 内部迁移/重放：保持 EW 接线前的语义，不接受普通 opts 旁路。
func send_legacy_v1(from_id: String, to_id: String, mode: String,
		text_key: String, payload := {}, opts := {}) -> Dictionary:
	return _send_core(from_id, to_id, mode, text_key, payload, opts, true)


func _send_core(from_id: String, to_id: String, mode: String, text_key: String,
		payload := {}, opts := {}, legacy_ignore_ew := false) -> Dictionary:
	var m := String(mode).to_upper()
	if not (m in MODES):
		return _fail_send(from_id, to_id, m, text_key, "invalid_mode")
	if not nodes.has(from_id):
		return _fail_send(from_id, to_id, m, text_key, "unknown_from")
	if not nodes.has(to_id):
		return _fail_send(from_id, to_id, m, text_key, "unknown_to")
	var p: Dictionary = payload if payload is Dictionary else {}
	var o: Dictionary = opts if opts is Dictionary else {}
	# R1：真实 sender 与调用方 actor/controller/fleet/owner 上下文必须一致；
	# v1 内部迁移重放不重新鉴权。
	if not legacy_ignore_ew and _sender_authorizer != null \
			and _sender_authorizer is Callable \
			and (_sender_authorizer as Callable).is_valid():
		var auth: Dictionary = (_sender_authorizer as Callable).call(from_id, o)
		if not bool(auth.get("ok", false)):
			return _fail_send(from_id, to_id, m, text_key,
				String(auth.get("reason", "sender_context_mismatch")))
	var from_node: Dictionary = nodes[from_id]
	var to_node: Dictionary = nodes[to_id]
	var content := String(p.get("content", p.get("text", o.get("content", ""))))
	var ctx: Dictionary = {
		"channel": "comms", "from": String(from_node.get("name", from_id)),
		"from_name": String(from_node.get("name", from_id)), "from_id": from_id,
		"from_role": String(from_node.get("role", "")),
		"to": String(to_node.get("name", to_id)), "to_name": String(to_node.get("name", to_id)),
		"to_id": to_id, "to_role": String(to_node.get("role", "")),
		"mode": m, "content": content,
	}
	for k in p.keys():
		ctx[String(k)] = p[k]
	for k in o.keys():
		if not ctx.has(String(k)):
			ctx[String(k)] = o[k]
	var selected: Dictionary = text_library.select(text_key, ctx)
	if not bool(selected.get("ok", false)):
		return _fail_send(from_id, to_id, m, text_key, String(selected.get("reason", "text_error")))
	var route: Dictionary = find_route(from_id, to_id, m, o)
	if not bool(route.get("ok", false)):
		return _fail_send(from_id, to_id, m, text_key, String(route.get("reason", "no_route")))
	var base_latency := maxf(0.0, float(route.get("latency_s", 0.0)))
	var delivery_id := "C-%06d" % (_delivery_seq + 1)
	_delivery_seq += 1
	# JC-A04：在**发送时刻**冻结 EW 采样与确定性 draw；到达时只按记录结果执行，
	# 读档/重放不得重新抽样改变结果。
	var ew_snap: Dictionary = _sample_ew_for_send(to_id, delivery_id, from_id,
		legacy_ignore_ew)
	var ew_add := float(ew_snap.get("latency_add_s", 0.0))
	var latency := base_latency + ew_add
	var arrive_t := t + latency
	var link_idxs: Array = (route.get("links", []) as Array).duplicate()
	var loss := 0.0
	for idx in link_idxs:
		if idx >= 0 and idx < links.size():
			loss = maxf(loss, float((links[idx] as Dictionary).get("packet_loss", 0.0)))
	var rec := {
		"delivery_id": delivery_id, "from": from_id, "to": to_id, "mode": m,
		"text_key": text_key, "text": String(selected.get("text", "")),
		"content": content, "path": (route.get("path", []) as Array).duplicate(),
		"latency_s": latency, "latency_base_s": base_latency,
		"latency_ew_add_s": ew_add, "ew": ew_snap.duplicate(true),
		"relay_count": int(route.get("relay_count", 0)),
		"packet_loss": loss, "arrive_t": arrive_t, "sent_t": t,
		"links": link_idxs,
	}
	pending.append(rec)
	while pending.size() > MAX_PENDING:
		pending.pop_front()
	_emit("SENT", rec, {"reason": "", "text": String(selected.get("text", "")),
		"path": (route.get("path", []) as Array).duplicate()})
	return {"ok": true, "reason": "", "delivery_id": delivery_id,
		"from": from_id, "to": to_id, "mode": m, "text_key": text_key,
		"text": String(selected.get("text", "")), "path": (route.get("path", []) as Array).duplicate(),
		"latency_s": latency, "latency_base_s": base_latency,
		"latency_ew_add_s": ew_add, "ew": ew_snap.duplicate(true),
		"relay_count": int(route.get("relay_count", 0)),
		"arrive_t": arrive_t, "sent_t": t, "packet_loss": loss,
		"from_name": String(from_node.get("name", from_id)),
		"to_name": String(to_node.get("name", to_id)),
		"writes_v15": false}


func _fail_send(from_id: String, to_id: String, mode: String, text_key: String,
		reason: String) -> Dictionary:
	var from_name := from_id
	var to_name := to_id
	if nodes.has(from_id):
		from_name = String((nodes[from_id] as Dictionary).get("name", from_id))
	if nodes.has(to_id):
		to_name = String((nodes[to_id] as Dictionary).get("name", to_id))
	var fctx := {"from": from_name, "to": to_name, "mode": mode, "reason_text": reason,
		"channel": "comms", "content": ""}
	var txt := ""
	if text_library.has("COMMS_FAILED"):
		var r: Dictionary = text_library.select("COMMS_FAILED", fctx)
		if bool(r.get("ok", false)):
			txt = String(r.get("text", ""))
	var ev := {"delivery_id": "", "from": from_id, "to": to_id, "mode": mode,
		"text_key": text_key, "text": txt, "reason": reason, "path": []}
	_emit("FAILED", ev, {"reason": reason, "text": txt, "path": []})
	return {"ok": false, "reason": reason, "from": from_id, "to": to_id, "mode": mode,
		"text_key": text_key, "text": txt, "delivery_id": "",
		"latency_s": 0.0, "latency_base_s": 0.0, "latency_ew_add_s": 0.0,
		"arrive_t": -1.0, "sent_t": t, "ew": {"jam_severity": 0.0,
			"latency_add_s": 0.0, "failure_chance": 0.0, "draw": -1.0,
			"will_fail": false, "sampled_t": t, "target_id": to_id,
			"ignored": false}, "writes_v15": false}


func tick(dt: float) -> Array:
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	var out_start := _outbox.size()
	var delivered: Array = []
	var kept: Array = []
	for raw in pending:
		if not (raw is Dictionary):
			continue
		var rec: Dictionary = raw
		if t + 1.0e-9 < float(rec.get("arrive_t", 0.0)):
			kept.append(rec)
			continue
		# 到达时重新校验目标/链路状态（遮挡/干扰可在途中改变）
		var reason := ""
		if not _node_ok(String(rec.get("to", ""))) or not _node_ok(String(rec.get("from", ""))):
			reason = "node_unavailable"
		else:
			for idx in (rec.get("links", []) as Array):
				if int(idx) >= 0 and int(idx) < links.size():
					var l: Dictionary = links[idx]
					if not bool(l.get("enabled", true)):
						reason = "link_disabled"
					elif bool(l.get("occluded", false)) and bool(l.get("requires_los", true)):
						reason = "occluded"
					elif float(l.get("jam", 0.0)) >= _jam_threshold:
						reason = "jammed"
		if reason == "":
			# JC-A04：发送时刻已冻结的 EW 失败结果，到达时执行（不重新抽样）
			var ew_rec: Dictionary = rec.get("ew", {}) if rec.get("ew") is Dictionary else {}
			if bool(ew_rec.get("will_fail", false)):
				reason = "comms_jam"
		if reason == "":
			var loss := float(rec.get("packet_loss", 0.0))
			if loss > 0.0:
				var hs := "%s|%s|%s|%s" % [String(rec.get("from", "")),
					String(rec.get("to", "")), String(rec.get("mode", "")),
					String(rec.get("delivery_id", ""))]
				var roll := float(hash(hs) & 0x7fffffff) / 2147483647.0
				if roll < loss:
					reason = "packet_lost"
		if reason == "":
			_emit("DELIVERED", rec, {"reason": "", "text": String(rec.get("text", "")),
				"path": (rec.get("path", []) as Array).duplicate()})
			delivered.append(rec.duplicate(true))
		else:
			_emit("FAILED", rec, {"reason": reason, "text": String(rec.get("text", "")),
				"path": (rec.get("path", []) as Array).duplicate()})
	pending = kept
	if _outbox.size() <= out_start:
		return []
	return _outbox.slice(out_start, _outbox.size())


func _emit(kind: String, rec: Dictionary, extra: Dictionary) -> void:
	_event_seq += 1
	var txt := String(extra.get("text", rec.get("text", "")))
	var ev := {
		"schema": SCHEMA_EVENT, "seq": _event_seq, "t": t, "kind": kind,
		"delivery_id": String(rec.get("delivery_id", "")),
		"from": String(rec.get("from", "")), "to": String(rec.get("to", "")),
		"from_name": String((nodes.get(rec.get("from", ""), {}) as Dictionary).get("name", rec.get("from", ""))),
		"to_name": String((nodes.get(rec.get("to", ""), {}) as Dictionary).get("name", rec.get("to", ""))),
		"mode": String(rec.get("mode", "")), "text_key": String(rec.get("text_key", "")),
		"text": txt, "reason": String(extra.get("reason", "")),
		"path": (extra.get("path", rec.get("path", [])) as Array).duplicate(),
		"relay_count": int(rec.get("relay_count", 0)),
		"latency_s": float(rec.get("latency_s", 0.0)),
		"shadow": true, "writes_v15": false, "writes_track_table": false,
	}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))


func take_events() -> Array:
	var out := _outbox.duplicate(true)
	_outbox = []
	return out


func pending_count() -> int:
	return pending.size()


func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out


# ── VM / JSON ───────────────────────────────────────────────────

func vm() -> Dictionary:
	var node_rows: Array = []
	for k in nodes.keys():
		node_rows.append((nodes[k] as Dictionary).duplicate(true))
	node_rows.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	var link_rows: Array = []
	for raw in links:
		if raw is Dictionary:
			link_rows.append((raw as Dictionary).duplicate(true))
	var pending_rows: Array = []
	for raw in pending:
		if raw is Dictionary:
			pending_rows.append((raw as Dictionary).duplicate(true))
	var ev_rows: Array = []
	for raw in events:
		if raw is Dictionary:
			ev_rows.append((raw as Dictionary).duplicate(true))
	return {
		"schema": SCHEMA_VM, "mode": "shadow", "authoritative": false,
		"ready": ready, "t": t, "dt": dt_last, "step_count": step_count,
		"nodes": node_rows, "links": link_rows,
		"pending": pending_rows, "events": ev_rows,
		"counts": {"nodes": node_rows.size(), "links": link_rows.size(),
			"pending": pending_rows.size(), "events": ev_rows.size()},
		"text_library": text_library.to_dict() if text_library != null else {},
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"track_table": false, "v15": false},
	}


func summary() -> Dictionary:
	return {
		"schema": SCHEMA_VM, "ready": ready, "t": t,
		"nodes": nodes.size(), "links": links.size(), "pending": pending.size(),
		"events": events.size(), "writes_v15": false,
	}


func to_dict() -> Dictionary:
	return vm()


func to_json() -> String:
	return JSON.stringify(vm())

# ── JC-A01/R4：在途投递与链路状态的存档/恢复 ─────────────────────
# 旧实现只保存会话其他组件，Comms.pending 丢失会被误判为「已送达」。
const STATE_SCHEMA := "v17.comms.state.v1"
# JC-A04 v2：新增发送时刻 EW 采样与确定性 RNG 状态；v1 作为合法旧档迁移。
const STATE_VERSION := 2
const STATE_VERSION_LEGACY := 1


func export_state() -> Dictionary:
	var pend: Array = []
	for raw in pending:
		if raw is Dictionary:
			pend.append((raw as Dictionary).duplicate(true))
	# 链路运行态（enabled/jam/occluded）按 a/b/mode 稳定键保存
	var link_rows: Array = []
	for raw2 in links:
		if not (raw2 is Dictionary):
			continue
		var l: Dictionary = raw2
		link_rows.append({"a": String(l.get("a", "")), "b": String(l.get("b", "")),
			"mode": String(l.get("mode", "")),
			"enabled": bool(l.get("enabled", true)),
			"jam": float(l.get("jam", 0.0)),
			"occluded": bool(l.get("occluded", false))})
	var node_rows: Dictionary = {}
	for nid in nodes.keys():
		var n: Dictionary = nodes[nid]
		node_rows[String(nid)] = {"status": String(n.get("status", "ok")),
			"enabled": bool(n.get("enabled", true)),
			"damage": float(n.get("damage", 0.0))}
	return {"schema": STATE_SCHEMA, "version": STATE_VERSION,
		"t": t, "dt_last": dt_last, "step_count": step_count,
		"delivery_seq": _delivery_seq, "event_seq": _event_seq,
		"ew_rng": ew_rng_state(),
		"pending": JSON.parse_string(JSON.stringify(pend)),
		"links": link_rows, "nodes": node_rows}


## 全量校验后再提交；失败不改运行态。
func load_state(st) -> Dictionary:
	if st == null:
		return {"ok": true, "restore_mode": "absent", "pending": pending.size()}
	if not (st is Dictionary):
		return {"ok": false, "reason": "invalid_state_type"}
	var s: Dictionary = st
	if String(s.get("schema", "")) != STATE_SCHEMA:
		return {"ok": false, "reason": "invalid_schema"}
	# R4：先严格确认整数版本，再转换/提交；2.5 等非整数版本拒绝。
	var raw_ver = s.get("version", null)
	var ver_int := false
	var ver_num := -1.0
	if raw_ver is int or raw_ver is float:
		ver_num = float(raw_ver)
		ver_int = is_finite(ver_num) and absf(ver_num - roundf(ver_num)) <= 0.0
	if not ver_int:
		return {"ok": false, "reason": "invalid_version", "version": raw_ver}
	var st_ver := int(roundf(ver_num))
	if st_ver != STATE_VERSION and st_ver != STATE_VERSION_LEGACY:
		return {"ok": false, "reason": "invalid_version", "version": raw_ver}
	var legacy_v1 := st_ver == STATE_VERSION_LEGACY
	var new_ew_seed := _ew_seed
	var new_ew_seq := _ew_seq
	if not legacy_v1:
		var raw_rng = s.get("ew_rng", null)
		if not (raw_rng is Dictionary):
			return {"ok": false, "reason": "invalid_state", "errors": ["ew_rng"]}
		var rng: Dictionary = raw_rng
		for rk in ["seed", "seq"]:
			var rv = rng.get(rk, null)
			if not (rv is int or rv is float) or not is_finite(float(rv)) \
					or absf(float(rv) - roundf(float(rv))) > 0.0 \
					or float(rv) < 0.0:
				return {"ok": false, "reason": "invalid_state",
					"errors": ["ew_rng." + rk]}
		new_ew_seed = int(rng.get("seed", _ew_seed))
		new_ew_seq = maxi(_ew_seq, int(rng.get("seq", _ew_seq)))
	for fld in ["t", "dt_last"]:
		var v = s.get(fld, null)
		if not (v is int or v is float) or not is_finite(float(v)) or float(v) < 0.0:
			return {"ok": false, "reason": "invalid_state", "errors": [fld]}
	for fld2 in ["step_count", "delivery_seq", "event_seq"]:
		var v2 = s.get(fld2, null)
		if v2 != null and (not (v2 is int or v2 is float) or not is_finite(float(v2))
				or float(v2) < 0.0):
			return {"ok": false, "reason": "invalid_state", "errors": [fld2]}
	var raw_pending = s.get("pending", [])
	if not (raw_pending is Array):
		return {"ok": false, "reason": "invalid_state", "errors": ["pending"]}
	var new_pending: Array = []
	for raw3 in (raw_pending as Array):
		if not (raw3 is Dictionary):
			return {"ok": false, "reason": "invalid_state", "errors": ["pending item"]}
		var rec: Dictionary = (raw3 as Dictionary).duplicate(true)
		if String(rec.get("delivery_id", "")) == "":
			return {"ok": false, "reason": "invalid_state",
				"errors": ["pending.delivery_id"]}
		var at = rec.get("arrive_t", null)
		if not (at is int or at is float) or not is_finite(float(at)):
			return {"ok": false, "reason": "invalid_state",
				"errors": ["pending.arrive_t"]}
		# R4：v2 必须携带冻结 EW 块；真正 v1 才允许缺省（迁移语义）。
		if not legacy_v1:
			if not (rec.get("ew") is Dictionary):
				return {"ok": false, "reason": "invalid_state",
					"errors": ["pending.ew"]}
			var ewv: Dictionary = rec.get("ew")
			if not (ewv.get("will_fail", false) is bool):
				return {"ok": false, "reason": "invalid_state",
					"errors": ["pending.ew.will_fail"]}
			for ef in ["jam_severity", "latency_add_s", "failure_chance", "draw"]:
				var ed = ewv.get(ef, null)
				if not (ed is int or ed is float) or not is_finite(float(ed)):
					return {"ok": false, "reason": "invalid_state",
						"errors": ["pending.ew." + ef]}
			var draw_v := float(ewv.get("draw", -1.0))
			var fc_v := float(ewv.get("failure_chance", 0.0))
			if draw_v < -1.0 - 1.0e-9 or draw_v > 1.0 + 1.0e-9 \
					or fc_v < -1.0e-9 or fc_v > 1.0 + 1.0e-9:
				return {"ok": false, "reason": "invalid_state",
					"errors": ["pending.ew.range"]}
			# 冻结结果一致性：will_fail 必须等于发送时刻 draw<failure_chance，
			# 读档被篡改（改单字段）必须显式拒绝而不是改变结果。
			if draw_v >= 0.0:
				var expect_fail := draw_v < fc_v
				if bool(ewv.get("will_fail", false)) != expect_fail:
					return {"ok": false, "reason": "invalid_state",
						"errors": ["pending.ew.frozen_result"]}
			for lk in ["latency_base_s", "latency_ew_add_s", "latency_s"]:
				var lv = rec.get(lk, null)
				if not (lv is int or lv is float) or not is_finite(float(lv)) \
						or float(lv) < 0.0:
					return {"ok": false, "reason": "invalid_state",
						"errors": ["pending." + lk]}
			if absf(float(rec.get("latency_s", 0.0))
					- (float(rec.get("latency_base_s", 0.0))
						+ float(rec.get("latency_ew_add_s", 0.0)))) > 1.0e-6:
				return {"ok": false, "reason": "invalid_state",
					"errors": ["pending.latency_sum"]}
			var st_t = rec.get("sent_t", null)
			if not (st_t is int or st_t is float) or not is_finite(float(st_t)):
				return {"ok": false, "reason": "invalid_state",
					"errors": ["pending.sent_t"]}
			if absf(float(rec.get("arrive_t", 0.0))
					- (float(st_t) + float(rec.get("latency_s", 0.0)))) > 1.0e-6:
				return {"ok": false, "reason": "invalid_state",
					"errors": ["pending.arrive_t"]}
		new_pending.append(rec)
	# 提交
	t = float(s.get("t", 0.0))
	dt_last = float(s.get("dt_last", 0.0))
	step_count = maxi(step_count, int(s.get("step_count", step_count)))
	_delivery_seq = maxi(_delivery_seq, int(s.get("delivery_seq", _delivery_seq)))
	_event_seq = maxi(_event_seq, int(s.get("event_seq", _event_seq)))
	_ew_seed = new_ew_seed
	_ew_seq = new_ew_seq
	pending = new_pending
	var raw_links = s.get("links", [])
	if raw_links is Array:
		for raw4 in (raw_links as Array):
			if not (raw4 is Dictionary):
				continue
			var lr: Dictionary = raw4
			for idx in range(links.size()):
				var l2: Dictionary = links[idx]
				if String(l2.get("a", "")) == String(lr.get("a", "")) \
						and String(l2.get("b", "")) == String(lr.get("b", "")) \
						and String(l2.get("mode", "")) == String(lr.get("mode", "")):
					l2["enabled"] = bool(lr.get("enabled", true))
					l2["jam"] = clampf(float(lr.get("jam", 0.0)), 0.0, 1.0)
					l2["occluded"] = bool(lr.get("occluded", false))
					break
	var raw_nodes = s.get("nodes", {})
	if raw_nodes is Dictionary:
		for nid2 in (raw_nodes as Dictionary).keys():
			if nodes.has(String(nid2)) and (raw_nodes as Dictionary)[nid2] is Dictionary:
				var nr: Dictionary = (raw_nodes as Dictionary)[nid2]
				var n2: Dictionary = nodes[String(nid2)]
				n2["status"] = String(nr.get("status", n2.get("status", "ok")))
				n2["enabled"] = bool(nr.get("enabled", n2.get("enabled", true)))
				n2["damage"] = float(nr.get("damage", n2.get("damage", 0.0)))
	return {"ok": true,
		"restore_mode": "migrated_v1" if legacy_v1 else "full",
		"pending": pending.size(),
		"t": t}
