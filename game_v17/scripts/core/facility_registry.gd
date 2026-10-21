extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3O/4B：FacilityRegistry（全设施注册表）
#
# - 基础内容：L1–L5 港群 20 站 + NESOSS-01..06 + LUNSYNC-01..03
#   （29 facility / 57 ports，保持原有查询/计数语义）；
# - 4B 扩展：facilities_system.json 顶层 `otc_satellites`（19 OTC）、
#   `fuel_facilities`（31 TNK + 31 FUL = 62）、`orbital_nodes`（LEO/FAR 节点）
#   合并进查询：facility()/by_code()/by_transponder_code()/ports/facility_card/
#   facility_for_entity/扩展计数；旧设施不重复 ID；
# - summary 区分 base/total/extension；`facilities_by_cluster` 保持旧 cluster
#   的基础语义（旧 probe/session 回归），扩展 cluster LEO/FAR 返回合并结果，
#   另有 all_facilities_by_cluster 查询全合并；
# - 只读注册表：不写 world/UI/物理；不改现有实体。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.facilities_system.v1"
const VERSION := "1.0.0"
const DEFAULT_PATH := "res://framework/content/facilities_system.json"
const CARD_SCHEMA := "facility_card.v1"
const REQUIRED_FACILITY := ["facility_id", "name", "name_en", "facility_code",
	"transponder_code", "transponder_type", "parent_cluster", "facility_class",
	"owner", "side", "services", "ports", "physical"]
const EXTENSION_KEYS := ["otc_satellites", "fuel_facilities"]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var data: Dictionary = {}
var source := ""
var title := ""
var generated_at := ""
var clusters: Array = []
var facilities: Array = []

var base_clusters: Array = []
var base_facilities: Array = []
var otc_satellites: Array = []
var fuel_facilities: Array = []
var orbital_nodes: Array = []
var extension_facilities: Array = []

var clusters_by_id: Dictionary = {}
var facilities_by_id: Dictionary = {}
var by_facility_code: Dictionary = {}
var by_transponder: Dictionary = {}
var by_parent: Dictionary = {}
var by_entity: Dictionary = {}
var ports_by_id: Dictionary = {}
var _transponder_types: Dictionary = {}
var _base_cluster_ids: Dictionary = {}
var _base_facility_ids: Dictionary = {}
var _base_by_parent: Dictionary = {}
var _base_ports: Dictionary = {}

func _init(cfg := {}) -> void:
	setup(cfg)

# ── load / validate ────────────────────────────────────────────

## cfg: {content: Dictionary} 或 {content_path: String}；成功 true。
func setup(cfg := {}) -> bool:
	var c: Dictionary = cfg if cfg is Dictionary else {}
	if c.get("content") is Dictionary:
		return load_data(c.get("content"))
	return load_content(str(c.get("content_path", DEFAULT_PATH)))

## 读取 JSON 文件；无文件/非法 JSON/校验失败 → ready=false 且不改旧状态。
func load_content(path := DEFAULT_PATH) -> bool:
	var p := str(path)
	var parsed = null
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		if f != null:
			parsed = JSON.parse_string(f.get_as_text())
			f.close()
	if not (parsed is Dictionary):
		errors.append("facilities 内容不可读/JSON 无效：" + p)
		ready = false
		return false
	return load_data(parsed)

## 校验并应用（先 validate；失败不部分写入）。
func load_data(value: Variant) -> bool:
	if not (value is Dictionary):
		errors.append("facilities 内容必须是对象")
		ready = false
		return false
	var v: Dictionary = validate(value)
	if not bool(v.get("ok", false)):
		errors.clear()
		for e in (v.get("errors", []) as Array):
			errors.append("facilities: " + str(e))
		# 原子：已有有效注册表时保持 ready/旧数据；首次加载失败才 ready=false
		return false
	_apply(value as Dictionary)
	ready = true
	return true

## 全量校验；返回 {ok,errors}，不修改当前状态。
func validate(value: Variant) -> Dictionary:
	var errs: Array[String] = []
	if not (value is Dictionary):
		return {"ok": false, "errors": ["内容必须是对象"]}
	var d: Dictionary = value
	if str(d.get("schema", "")) != SCHEMA:
		errs.append("schema 必须为 " + SCHEMA)
	if str(d.get("version", "")) != VERSION:
		errs.append("version 必须为 " + VERSION)
	var clusters_in = d.get("clusters", null)
	var facilities_in = d.get("facilities", null)
	if not (clusters_in is Array) or (clusters_in as Array).is_empty():
		errs.append("clusters 必须为非空数组")
		return {"ok": false, "errors": errs}
	if not (facilities_in is Array) or (facilities_in as Array).is_empty():
		errs.append("facilities 必须为非空数组")
		return {"ok": false, "errors": errs}
	var cluster_ids: Dictionary = {}
	for raw_c in (clusters_in as Array):
		if not (raw_c is Dictionary):
			errs.append("cluster 必须是对象")
			continue
		var c: Dictionary = raw_c
		var cid := str(c.get("cluster_id", ""))
		if cid == "" or cid.strip_edges() != cid:
			errs.append("cluster_id 非法")
		if cluster_ids.has(cid):
			errs.append("cluster_id 重复：" + cid)
		cluster_ids[cid] = true
		for k in ["name", "name_en"]:
			if str(c.get(k, "")) == "":
				errs.append("cluster %s 缺少 %s" % [cid, k])
	# 4B 轨道节点：LEO/FAR 等 cluster 元数据，合并进 cluster_ids
	var nodes = d.get("orbital_nodes", null)
	if nodes != null and not (nodes is Array):
		errs.append("orbital_nodes 必须是数组")
	elif nodes is Array:
		for raw_n in (nodes as Array):
			if not (raw_n is Dictionary):
				errs.append("orbital_node 必须是对象")
				continue
			var n: Dictionary = raw_n
			var nid := str(n.get("cluster_id", ""))
			if nid == "" or nid.strip_edges() != nid:
				errs.append("orbital_node cluster_id 非法")
			elif cluster_ids.has(nid):
				errs.append("orbital_node cluster_id 重复：" + nid)
			cluster_ids[nid] = true
			for k2 in ["name", "name_en"]:
				if str(n.get(k2, "")) == "":
					errs.append("orbital_node %s 缺少 %s" % [nid, k2])
	var fids: Dictionary = {}
	var codes: Dictionary = {}
	var txps: Dictionary = {}
	var ports: Dictionary = {}
	# 基础 29 设施
	for raw_f in (facilities_in as Array):
		_validate_facility(raw_f, "base", cluster_ids, fids, codes, txps, ports, errs)
	# 4B 扩展设施：OTC 19 + TNK/FUL 62
	for ext_key in EXTENSION_KEYS:
		var ext = d.get(ext_key, null)
		if ext == null:
			continue
		if not (ext is Array):
			errs.append("%s 必须是数组" % str(ext_key))
			continue
		for raw_e in (ext as Array):
			_validate_facility(raw_e, str(ext_key), cluster_ids, fids, codes,
				txps, ports, errs)
	return {"ok": errs.is_empty(), "errors": errs}

func _validate_facility(raw_f: Variant, group: String, cluster_ids: Dictionary,
		fids: Dictionary, codes: Dictionary, txps: Dictionary, ports: Dictionary,
		errs: Array[String]) -> void:
	if not (raw_f is Dictionary):
		errs.append("%s facility 必须是对象" % group)
		return
	var f: Dictionary = raw_f
	var fid := str(f.get("facility_id", ""))
	for req in REQUIRED_FACILITY:
		if not f.has(req):
			errs.append("facility %s 缺少 %s" % [fid, req])
	if fid == "" or fid.strip_edges() != fid:
		errs.append("facility_id 非法")
	if fids.has(fid):
		errs.append("facility_id 重复：" + fid)
	fids[fid] = true
	var code := str(f.get("facility_code", ""))
	var txp := str(f.get("transponder_code", ""))
	if code == "":
		errs.append("facility %s facility_code 为空" % fid)
	elif codes.has(code):
		errs.append("facility_code 重复：" + code)
	codes[code] = true
	if txp == "":
		errs.append("facility %s transponder_code 为空" % fid)
	elif txps.has(txp):
		errs.append("transponder_code 重复：" + txp)
	txps[txp] = true
	var parent := str(f.get("parent_cluster", ""))
	if not cluster_ids.has(parent):
		errs.append("facility %s parent_cluster 不存在：%s" % [fid, parent])
	for k2 in ["name", "name_en", "transponder_type", "facility_class",
			"owner", "side"]:
		if str(f.get(k2, "")) == "":
			errs.append("facility %s 缺少 %s" % [fid, k2])
	if not (f.get("services") is Array) or (f.get("services") as Array).is_empty():
		errs.append("facility %s services 必须为非空数组" % fid)
	else:
		for s in (f.get("services") as Array):
			if str(s) == "":
				errs.append("facility %s service 为空" % fid)
	if not (f.get("ports") is Array) or (f.get("ports") as Array).is_empty():
		errs.append("facility %s ports 必须为非空数组" % fid)
	else:
		for raw_p in (f.get("ports") as Array):
			if not (raw_p is Dictionary):
				errs.append("facility %s port 非对象" % fid)
				continue
			var p: Dictionary = raw_p
			var pid := str(p.get("port_id", ""))
			if pid == "":
				errs.append("facility %s port_id 为空" % fid)
			elif ports.has(pid):
				errs.append("port_id 重复：" + pid)
			ports[pid] = true
			if str(p.get("kind", "")) == "":
				errs.append("facility %s port %s kind 为空" % [fid, pid])
			if int(p.get("berths", 0)) <= 0:
				errs.append("facility %s port %s berths 必须 >0" % [fid, pid])
			if float(p.get("max_length_m", 0.0)) <= 0.0:
				errs.append("facility %s port %s max_length_m 必须 >0" % [fid, pid])
	var phys = f.get("physical", null)
	if not (phys is Dictionary):
		errs.append("facility %s physical 必须是对象" % fid)
	else:
		var ph: Dictionary = phys
		if not (ph.get("orbit") is Dictionary) or (ph.get("orbit") as Dictionary).is_empty():
			errs.append("facility %s physical.orbit 缺失" % fid)
		for k3 in ["mass_kg", "radius_km", "cross_section_m2", "period_s"]:
			if not (ph.get(k3) is int or ph.get(k3) is float) \
					or not is_finite(float(ph.get(k3, NAN))) or float(ph.get(k3, 0.0)) <= 0.0:
				errs.append("facility %s physical.%s 必须有限且 >0" % [fid, k3])
		if not (ph.get("station_keeping") is Dictionary) \
				or (ph.get("station_keeping") as Dictionary).is_empty():
			errs.append("facility %s physical.station_keeping 缺失" % fid)
		else:
			var sk: Dictionary = ph.get("station_keeping")
			if str(sk.get("mode", "")) == "":
				errs.append("facility %s station_keeping.mode 为空" % fid)
			if not (sk.get("dv_m_s_year") is int or sk.get("dv_m_s_year") is float) \
					or not is_finite(float(sk.get("dv_m_s_year", NAN))) \
					or float(sk.get("dv_m_s_year", -1.0)) < 0.0:
				errs.append("facility %s station_keeping.dv_m_s_year 非法" % fid)
	if f.has("entity_ids") and not (f.get("entity_ids") is Array):
		errs.append("facility %s entity_ids 必须是数组" % fid)

func _apply(d: Dictionary) -> void:
	data = d.duplicate(true)
	source = str(d.get("source", ""))
	title = str(d.get("title", ""))
	generated_at = str(d.get("generated_at", ""))
	base_clusters = (d.get("clusters", []) as Array).duplicate(true)
	base_facilities = (d.get("facilities", []) as Array).duplicate(true)
	otc_satellites = (d.get("otc_satellites", []) as Array).duplicate(true) \
		if d.get("otc_satellites") is Array else []
	fuel_facilities = (d.get("fuel_facilities", []) as Array).duplicate(true) \
		if d.get("fuel_facilities") is Array else []
	orbital_nodes = (d.get("orbital_nodes", []) as Array).duplicate(true) \
		if d.get("orbital_nodes") is Array else []
	# 合并 orbital node → cluster（LEO/FAR）
	clusters = []
	for raw_c in base_clusters:
		if raw_c is Dictionary:
			var bc: Dictionary = (raw_c as Dictionary).duplicate(true)
			bc["registry_group"] = "base"
			clusters.append(bc)
	for raw_n in orbital_nodes:
		if not (raw_n is Dictionary):
			continue
		var n: Dictionary = (raw_n as Dictionary).duplicate(true)
		var nid := str(n.get("cluster_id", ""))
		var dup := false
		for raw_c2 in clusters:
			if str((raw_c2 as Dictionary).get("cluster_id", "")) == nid:
				dup = true
				break
		if dup:
			continue
		n["registry_group"] = "orbital_node"
		clusters.append(n)
	# 合并 facilities（base + OTC + fuel）
	facilities = []
	for raw_f in base_facilities:
		if raw_f is Dictionary:
			var bf: Dictionary = (raw_f as Dictionary).duplicate(true)
			bf["registry_group"] = "base"
			facilities.append(bf)
	extension_facilities = []
	for raw_o in otc_satellites:
		if raw_o is Dictionary:
			var of: Dictionary = (raw_o as Dictionary).duplicate(true)
			of["registry_group"] = "otc_satellite"
			facilities.append(of)
			extension_facilities.append(of.duplicate(true))
	for raw_u in fuel_facilities:
		if raw_u is Dictionary:
			var uf: Dictionary = (raw_u as Dictionary).duplicate(true)
			uf["registry_group"] = "fuel_facility"
			facilities.append(uf)
			extension_facilities.append(uf.duplicate(true))
	# 重建索引
	clusters_by_id = {}
	facilities_by_id = {}
	by_facility_code = {}
	by_transponder = {}
	by_parent = {}
	by_entity = {}
	ports_by_id = {}
	_transponder_types = {}
	_base_cluster_ids = {}
	_base_facility_ids = {}
	_base_by_parent = {}
	_base_ports = {}
	for raw_c3 in clusters:
		if raw_c3 is Dictionary:
			var c3: Dictionary = raw_c3
			clusters_by_id[str(c3.get("cluster_id", ""))] = c3
			if str(c3.get("registry_group", "")) == "base":
				_base_cluster_ids[str(c3.get("cluster_id", ""))] = true
	for raw_f2 in facilities:
		if not (raw_f2 is Dictionary):
			continue
		var f2: Dictionary = raw_f2
		var fid := str(f2.get("facility_id", ""))
		facilities_by_id[fid] = f2
		by_facility_code[str(f2.get("facility_code", ""))] = f2
		by_transponder[str(f2.get("transponder_code", "")).to_upper()] = f2
		_transponder_types[str(f2.get("transponder_code", "")).to_upper()] = \
			str(f2.get("transponder_type", ""))
		var parent := str(f2.get("parent_cluster", ""))
		if not by_parent.has(parent):
			by_parent[parent] = []
		(by_parent[parent] as Array).append(f2)
		if str(f2.get("registry_group", "")) == "base":
			_base_facility_ids[fid] = true
			if not _base_by_parent.has(parent):
				_base_by_parent[parent] = []
			(_base_by_parent[parent] as Array).append(f2)
		for eid in (f2.get("entity_ids", []) as Array):
			by_entity[str(eid)] = f2
		for raw_p2 in (f2.get("ports", []) as Array):
			if raw_p2 is Dictionary:
				var p2: Dictionary = raw_p2
				ports_by_id[str(p2.get("port_id", ""))] = p2
				if str(f2.get("registry_group", "")) == "base":
					_base_ports[str(p2.get("port_id", ""))] = p2

# ── 查询 ────────────────────────────────────────────────────────

func facility_ids() -> Array:
	var out: Array = facilities_by_id.keys()
	out.sort()
	return out

func base_facility_ids() -> Array:
	var out: Array = _base_facility_ids.keys()
	out.sort()
	return out

func extension_facility_ids() -> Array:
	var out: Array = []
	for raw in extension_facilities:
		out.append(str((raw as Dictionary).get("facility_id", "")))
	out.sort()
	return out

func otc_satellite_ids() -> Array:
	var out: Array = []
	for raw in otc_satellites:
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("facility_id", "")))
	out.sort()
	return out

func fuel_facility_ids() -> Array:
	var out: Array = []
	for raw in fuel_facilities:
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("facility_id", "")))
	out.sort()
	return out

func orbital_node_ids() -> Array:
	var out: Array = []
	for raw in orbital_nodes:
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("cluster_id", "")))
	out.sort()
	return out

func cluster_ids() -> Array:
	var out: Array = clusters_by_id.keys()
	out.sort()
	return out

func cluster(cluster_id: String) -> Dictionary:
	return (clusters_by_id.get(cluster_id, {}) as Dictionary).duplicate(true)

func facility(facility_id: String) -> Dictionary:
	return (facilities_by_id.get(facility_id, {}) as Dictionary).duplicate(true)

func by_code(facility_code: String) -> Dictionary:
	return (by_facility_code.get(facility_code, {}) as Dictionary).duplicate(true)

func by_transponder_code(transponder_code: String) -> Dictionary:
	return (by_transponder.get(transponder_code.to_upper(), {}) as Dictionary).duplicate(true)

## 应答机识别：返回 {ok,matched,transponder_code,transponder_type,facility_id,facility}。
func classify_transponder(transponder_code: String) -> Dictionary:
	var code := transponder_code.to_upper()
	if code == "":
		return {"ok": false, "matched": false, "reason": "empty_transponder"}
	var f = by_transponder.get(code, null)
	if f == null:
		return {"ok": false, "matched": false, "reason": "unknown_transponder",
			"transponder_code": code}
	return {"ok": true, "matched": true, "transponder_code": code,
		"transponder_type": str((f as Dictionary).get("transponder_type", "")),
		"facility_id": str((f as Dictionary).get("facility_id", "")),
		"facility": (f as Dictionary).duplicate(true)}

## 保持旧语义：基础 cluster 返回 29 设施中的对应列表；扩展节点（LEO/FAR）
## 返回合并结果。全合并查询用 all_facilities_by_cluster。
func facilities_by_cluster(cluster_id: String) -> Array:
	if _base_cluster_ids.has(cluster_id):
		return _sorted_facilities(_base_by_parent.get(cluster_id, []) as Array)
	return _sorted_facilities(by_parent.get(cluster_id, []) as Array)

func all_facilities_by_cluster(cluster_id: String) -> Array:
	return _sorted_facilities(by_parent.get(cluster_id, []) as Array)

func base_facilities_by_cluster(cluster_id: String) -> Array:
	return _sorted_facilities(_base_by_parent.get(cluster_id, []) as Array)

func _sorted_facilities(rows: Array) -> Array:
	var out: Array = []
	for raw in rows:
		out.append((raw as Dictionary).duplicate(true))
	out.sort_custom(func(a, b): return str(a.get("facility_id", "")) < str(b.get("facility_id", "")))
	return out

func facilities_by_parent(cluster_id: String) -> Array:
	return facilities_by_cluster(cluster_id)

## 设施卡片：facility + cluster + ports + codes + physical（只读）。
func facility_card(facility_id: String) -> Dictionary:
	var f := facility(facility_id)
	if f.is_empty():
		return {}
	var cid := str(f.get("parent_cluster", ""))
	return {"schema": CARD_SCHEMA, "ok": true, "facility": f,
		"cluster": cluster(cid), "ports": (f.get("ports", []) as Array).duplicate(true),
		"physical": (f.get("physical", {}) as Dictionary).duplicate(true),
		"codes": {"facility_code": str(f.get("facility_code", "")),
			"transponder_code": str(f.get("transponder_code", "")),
			"transponder_type": str(f.get("transponder_type", ""))},
		"registry_group": str(f.get("registry_group", "")),
		"writes": {"world": false, "v15": false, "ui": false}}

## world entity → facility（通过 facility.entity_ids 绑定；未知返回空）。
func facility_for_entity(entity_id: String) -> Dictionary:
	return (by_entity.get(entity_id, {}) as Dictionary).duplicate(true)

func ports_for(facility_id: String) -> Array:
	var f := facility(facility_id)
	return (f.get("ports", []) as Array).duplicate(true)

func port_ids_for(facility_id: String) -> Array:
	var out: Array = []
	for raw in ports_for(facility_id):
		if raw is Dictionary:
			out.append(str((raw as Dictionary).get("port_id", "")))
	return out

func extension_facilities_for_cluster(cluster_id: String) -> Array:
	var out: Array = []
	for raw in extension_facilities:
		if str((raw as Dictionary).get("parent_cluster", "")) == cluster_id:
			out.append((raw as Dictionary).duplicate(true))
	out.sort_custom(func(a, b): return str(a.get("facility_id", "")) < str(b.get("facility_id", "")))
	return out

func orbital_node(cluster_id: String) -> Dictionary:
	for raw in orbital_nodes:
		if raw is Dictionary and str((raw as Dictionary).get("cluster_id", "")) == cluster_id:
			return (raw as Dictionary).duplicate(true)
	return {}

# ── 计数 / summary ─────────────────────────────────────────────

func count() -> int:
	return facilities_by_id.size()

func total_count() -> int:
	return facilities_by_id.size()

func base_count() -> int:
	return _base_facility_ids.size()

func extension_count() -> int:
	return extension_facilities.size()

func otc_count() -> int:
	return otc_satellites.size()

func fuel_count() -> int:
	return fuel_facilities.size()

func orbital_node_count() -> int:
	return orbital_nodes.size()

func cluster_count() -> int:
	return clusters_by_id.size()

func base_cluster_count() -> int:
	return _base_cluster_ids.size()

func summary() -> Dictionary:
	var per_cluster: Dictionary = {}
	for cid in cluster_ids():
		# 基础 cluster 保持旧计数；扩展节点用合并计数
		if _base_cluster_ids.has(str(cid)):
			per_cluster[str(cid)] = (_base_by_parent.get(str(cid), []) as Array).size()
		else:
			per_cluster[str(cid)] = (by_parent.get(str(cid), []) as Array).size()
	var per_cluster_total: Dictionary = {}
	for cid2 in cluster_ids():
		per_cluster_total[str(cid2)] = (by_parent.get(str(cid2), []) as Array).size()
	return {"schema": SCHEMA, "ready": ready, "title": title,
		"source": source,
		# 旧字段保持 base 语义（兼容既有调用方）
		"clusters": _base_cluster_ids.size(),
		"facilities": _base_facility_ids.size(),
		"facility_codes": _base_facility_ids.size(),
		"transponders": _base_facility_ids.size(),
		"ports": _base_ports.size(),
		"per_cluster": per_cluster,
		# 4B 扩展/总计
		"base_clusters": _base_cluster_ids.size(),
		"base_facilities": _base_facility_ids.size(),
		"base_ports": _base_ports.size(),
		"extension_facilities": extension_facilities.size(),
		"otc_satellites": otc_satellites.size(),
		"fuel_facilities": fuel_facilities.size(),
		"orbital_nodes": orbital_nodes.size(),
		"total_clusters": clusters_by_id.size(),
		"total_facilities": facilities_by_id.size(),
		"total_facility_codes": by_facility_code.size(),
		"total_transponders": by_transponder.size(),
		"total_ports": ports_by_id.size(),
		"per_cluster_total": per_cluster_total,
		"writes": {"world": false, "v15": false, "ui": false}}

## 完整 JSON：保留基础 schema + 扩展顶层；load 后查询等价。
func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION, "title": title,
		"source": source, "generated_at": generated_at,
		"clusters": base_clusters.duplicate(true),
		"facilities": base_facilities.duplicate(true),
		"orbital_nodes": orbital_nodes.duplicate(true),
		"otc_satellites": otc_satellites.duplicate(true),
		"fuel_facilities": fuel_facilities.duplicate(true)}

## 合并视图（base + 扩展 + orbital node 合成 cluster），供调试/UI 使用。
func to_merged_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION, "title": title,
		"source": source, "generated_at": generated_at,
		"clusters": clusters.duplicate(true),
		"facilities": facilities.duplicate(true),
		"summary": summary()}

func to_json() -> String:
	return JSON.stringify(to_dict())

# ── DbC ────────────────────────────────────────────────────────

func check_contracts() -> Dictionary:
	var v: Array[String] = []
	if not ready:
		v.append("registry 未 ready")
	if facilities_by_id.size() != facilities.size():
		v.append("facility 索引数量不一致")
	if clusters_by_id.size() != clusters.size():
		v.append("cluster 索引数量不一致")
	if by_facility_code.size() != facilities.size():
		v.append("facility_code 索引数量不一致")
	if by_transponder.size() != facilities.size():
		v.append("transponder 索引数量不一致")
	if extension_facilities.size() != otc_satellites.size() + fuel_facilities.size():
		v.append("扩展设施计数不一致")
	if _base_facility_ids.size() > facilities_by_id.size():
		v.append("base facility 数超过 total")
	if ports_by_id.size() == 0:
		v.append("无 port 绑定")
	for fid in facility_ids():
		var f: Dictionary = facilities_by_id[fid]
		var ph: Dictionary = f.get("physical", {}) as Dictionary
		for k in ["mass_kg", "radius_km", "cross_section_m2", "period_s"]:
			if not is_finite(float(ph.get(k, NAN))) or float(ph.get(k, 0.0)) <= 0.0:
				v.append("facility %s physical.%s 非法" % [str(fid), str(k)])
		if not (f.get("ports") is Array) or (f.get("ports") as Array).is_empty():
			v.append("facility %s 无 ports" % str(fid))
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
