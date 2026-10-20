extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3O：FacilityRegistry（全设施注册表；新文件）
#
# - 内容：L1–L5 港群 20 站 + NESOSS-01..06 + LUNSYNC-01..03（TBD 提案）；
#   层次 cluster→facility；每设施唯一 facility_code/transponder_code，
#   物理参数 physical{orbit,mass_kg,radius_km,cross_section_m2,station_keeping,period_s}，
#   港口绑定 ports[]，可绑定 world entity（entity_ids）。
# - 只读注册表：load/validate/查询/classify_transponder/facility_card；
#   不写 world/UI/物理；不改现有实体。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.facilities_system.v1"
const VERSION := "1.0.0"
const DEFAULT_PATH := "res://framework/content/facilities_system.json"
const CARD_SCHEMA := "facility_card.v1"
const REQUIRED_FACILITY := ["facility_id", "name", "name_en", "facility_code",
	"transponder_code", "transponder_type", "parent_cluster", "facility_class",
	"owner", "side", "services", "ports", "physical"]

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

var clusters_by_id: Dictionary = {}
var facilities_by_id: Dictionary = {}
var by_facility_code: Dictionary = {}
var by_transponder: Dictionary = {}
var by_parent: Dictionary = {}
var by_entity: Dictionary = {}
var ports_by_id: Dictionary = {}
var _transponder_types: Dictionary = {}

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
	var fids: Dictionary = {}
	var codes: Dictionary = {}
	var txps: Dictionary = {}
	var ports: Dictionary = {}
	for raw_f in (facilities_in as Array):
		if not (raw_f is Dictionary):
			errs.append("facility 必须是对象")
			continue
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
	return {"ok": errs.is_empty(), "errors": errs}

func _apply(d: Dictionary) -> void:
	data = d.duplicate(true)
	source = str(d.get("source", ""))
	title = str(d.get("title", ""))
	generated_at = str(d.get("generated_at", ""))
	clusters = (d.get("clusters", []) as Array).duplicate(true)
	facilities = (d.get("facilities", []) as Array).duplicate(true)
	clusters_by_id = {}
	facilities_by_id = {}
	by_facility_code = {}
	by_transponder = {}
	by_parent = {}
	by_entity = {}
	ports_by_id = {}
	_transponder_types = {}
	for raw_c in clusters:
		if raw_c is Dictionary:
			var c: Dictionary = raw_c
			clusters_by_id[str(c.get("cluster_id", ""))] = c
	for raw_f in facilities:
		if not (raw_f is Dictionary):
			continue
		var f: Dictionary = raw_f
		var fid := str(f.get("facility_id", ""))
		facilities_by_id[fid] = f
		by_facility_code[str(f.get("facility_code", ""))] = f
		by_transponder[str(f.get("transponder_code", "")).to_upper()] = f
		_transponder_types[str(f.get("transponder_code", "")).to_upper()] = \
			str(f.get("transponder_type", ""))
		var parent := str(f.get("parent_cluster", ""))
		if not by_parent.has(parent):
			by_parent[parent] = []
		(by_parent[parent] as Array).append(f)
		for eid in (f.get("entity_ids", []) as Array):
			by_entity[str(eid)] = f
		for raw_p in (f.get("ports", []) as Array):
			if raw_p is Dictionary:
				ports_by_id[str((raw_p as Dictionary).get("port_id", ""))] = raw_p

# ── 查询 ────────────────────────────────────────────────────────

func facility_ids() -> Array:
	var out: Array = facilities_by_id.keys()
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

func facilities_by_cluster(cluster_id: String) -> Array:
	var out: Array = []
	for raw in (by_parent.get(cluster_id, []) as Array):
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

func count() -> int:
	return facilities_by_id.size()

func cluster_count() -> int:
	return clusters_by_id.size()

func summary() -> Dictionary:
	var per_cluster: Dictionary = {}
	for cid in cluster_ids():
		per_cluster[str(cid)] = facilities_by_cluster(str(cid)).size()
	return {"schema": SCHEMA, "ready": ready, "title": title,
		"source": source, "clusters": clusters_by_id.size(),
		"facilities": facilities_by_id.size(),
		"per_cluster": per_cluster, "facility_codes": by_facility_code.size(),
		"transponders": by_transponder.size(), "ports": ports_by_id.size(),
		"writes": {"world": false, "v15": false, "ui": false}}

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "version": VERSION, "title": title,
		"source": source, "generated_at": generated_at,
		"clusters": clusters.duplicate(true),
		"facilities": facilities.duplicate(true)}

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
