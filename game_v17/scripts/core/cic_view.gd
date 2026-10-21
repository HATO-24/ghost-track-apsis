extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段4I：CICView（CIC 可观测信息层；新文件）
#
# 输入（只读）：
#   - TrackTable VM（tracks/bearing/range/level/quality/age/identity/evidence）
#   - ownship / observer 状态（id/pos_km/heading）
#   - FacilityRegistry 已知设施（id/code/name/cluster/position）
#   - track metadata（entity/facility/known）
# 输出 CICView（truth=false，不含 truth）：
#   - ownship（已知）
#   - facilities（注册表已知）
#   - L1：只给 bearing ray/cone，**不给位置**
#   - L2：bearing/range → 局部估计位置 + uncertainty_km + age/quality
#   - L3/L4：保留估计/身份/威胁/证据
#   - 无 bearing/range/ownship 时不伪造位置
# - 不读 PhysicsWorld truth、不写 TrackTable/world/UI/V15。
# ═══════════════════════════════════════════════════════════════════

const SCHEMA := "v17.cic_view.v1"
const VERSION := "1.0.0"
const LEVEL_NAMES := {1: "L1_BEARING", 2: "L2_POSITION",
	3: "L3_CLASSIFIED", 4: "L4_IDENTIFIED"}
const LEVEL_LABELS := {1: "方位", 2: "定位", 3: "分类", 4: "识别"}

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var contract_errors: Array[String] = []

var vm: Dictionary = {}
var track_table = null
var ownship_in: Dictionary = {}
var facilities_in: Array = []
var metadata: Dictionary = {}
var config: Dictionary = {}
var _view: Dictionary = {}
var _built := false

func _init(cfg := {}) -> void:
	setup(cfg)

# ── setup ───────────────────────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors.clear()
	warnings.clear()
	contract_errors.clear()
	_built = false
	_view = {}
	config = cfg.duplicate(true) if cfg is Dictionary else {}
	if not (cfg is Dictionary):
		errors.append("config 必须是对象")
		return false
	var c: Dictionary = cfg
	# TrackTable / VM
	track_table = c.get("track_table", null)
	vm = {}
	if c.get("track_table_vm") is Dictionary:
		vm = (c.get("track_table_vm") as Dictionary).duplicate(true)
	elif track_table != null:
		if track_table.has_method("vm"):
			var v = track_table.vm()
			if v is Dictionary:
				vm = (v as Dictionary).duplicate(true)
		elif track_table is Dictionary:
			vm = (track_table as Dictionary).duplicate(true)
	if vm.is_empty():
		errors.append("缺少 TrackTable VM/track_table")
		return false
	if not (vm.get("tracks") is Array):
		errors.append("TrackTable VM 缺少 tracks 数组")
		return false
	# ownship / observer
	ownship_in = {}
	if c.get("ownship") is Dictionary:
		ownship_in = (c.get("ownship") as Dictionary).duplicate(true)
	elif c.get("observer") is Dictionary:
		ownship_in = (c.get("observer") as Dictionary).duplicate(true)
	var pos_res := _valid_pos(ownship_in.get("pos_km", ownship_in.get("position_km", null)))
	if not bool(pos_res.get("ok", false)):
		errors.append("ownship/observer pos_km 必须是有限三维")
		return false
	ownship_in["pos_km"] = pos_res.get("pos_km")
	if ownship_in.has("heading_deg") and (not (ownship_in["heading_deg"] is int or ownship_in["heading_deg"] is float)
			or not is_finite(float(ownship_in["heading_deg"]))):
		errors.append("ownship heading_deg 非法")
		return false
	# facilities：registry 或数组
	facilities_in = []
	var reg = c.get("facility_registry", null)
	if reg != null:
		var rf = reg.get("facilities") if reg != null else null
		if rf is Array:
			facilities_in = (rf as Array).duplicate(true)
		elif reg.has_method("to_dict"):
			var rd: Dictionary = reg.to_dict()
			if rd.get("facilities") is Array:
				facilities_in = (rd["facilities"] as Array).duplicate(true)
	elif c.get("facilities") is Array:
		facilities_in = (c.get("facilities") as Array).duplicate(true)
	# metadata
	metadata = {}
	var m = c.get("metadata", null)
	if m is Dictionary:
		if (m as Dictionary).get("tracks") is Dictionary:
			metadata = ((m as Dictionary)["tracks"] as Dictionary).duplicate(true)
		else:
			metadata = (m as Dictionary).duplicate(true)
	elif m is Array:
		for raw in (m as Array):
			if raw is Dictionary:
				var md: Dictionary = raw
				var mk := str(md.get("track_id", md.get("id", "")))
				if mk != "":
					metadata[mk] = md.duplicate(true)
	ready = errors.is_empty()
	return ready

# ── build ───────────────────────────────────────────────────────

func build() -> Dictionary:
	if not ready:
		return _fail("not_ready", "precondition: CICView 未 ready")
	var t_vm := float(vm.get("t", 0.0))
	var own_pos: Array = (ownship_in.get("pos_km", []) as Array).duplicate()
	var own_id := str(ownship_in.get("id", ownship_in.get("ship_id", "ownship")))
	var own := {"id": own_id, "known": true, "pos_km": own_pos.duplicate(),
		"heading_deg": float(ownship_in.get("heading_deg", 0.0)),
		"truth": false}
	var facilities: Array = []
	for raw in facilities_in:
		if not (raw is Dictionary):
			continue
		var f: Dictionary = raw
		var fid := str(f.get("facility_id", ""))
		var fcode := str(f.get("facility_code", ""))
		if fid == "" and fcode == "":
			continue
		var fpos = f.get("pos_km", null)
		if fpos == null:
			var ph = f.get("physical", null)
			if ph is Dictionary and (ph as Dictionary).get("orbit") is Dictionary:
				fpos = ((ph as Dictionary)["orbit"] as Dictionary).get("position_km", null)
		var pr := _valid_pos(fpos)
		var row := {"facility_id": fid, "facility_code": fcode,
			"name": str(f.get("name", f.get("name_en", ""))),
			"cluster_id": str(f.get("parent_cluster", "")),
			"known": true, "truth": false}
		if bool(pr.get("ok", false)):
			row["pos_km"] = pr.get("pos_km")
		else:
			row["pos_km"] = null
		facilities.append(row)
	facilities.sort_custom(func(a, b): return str(a.get("facility_id", "")) < str(b.get("facility_id", "")))
	var tracks: Array = []
	for raw_t in (vm.get("tracks", []) as Array):
		if not (raw_t is Dictionary):
			continue
		var tr: Dictionary = raw_t
		var tid := str(tr.get("id", tr.get("track_id", "")))
		if tid == "":
			continue
		var level := int(tr.get("level", 1))
		if not (level in [1, 2, 3, 4]):
			level = 1
		var md: Dictionary = (metadata.get(tid, {}) as Dictionary)
		if md.is_empty():
			# metadata 也允许按 entity_id/batch 索引
			for mk in metadata.keys():
				var cand: Dictionary = metadata[mk] as Dictionary
				if str(cand.get("entity_id", "")) == str(tr.get("entity_id", "")) \
						and str(tr.get("entity_id", "")) != "":
					md = cand
					break
		var known := bool(tr.get("known", false)) or bool(md.get("known", false))
		var entity_id := str(md.get("entity_id", tr.get("entity_id", "")))
		var facility_id := str(md.get("facility_id", tr.get("facility_id", "")))
		var quality := clampf(float(tr.get("quality", 0.0)), 0.0, 1.0)
		var last_t := float(tr.get("last_update", tr.get("last_t", 0.0)))
		var age := float(tr.get("age", tr.get("age_s", t_vm - last_t)))
		if not is_finite(age) or age < 0.0:
			age = 0.0
		var stale := bool(tr.get("stale", false)) or age >= float(config.get("stale_after_s", 30.0))
		var sources: Array = (tr.get("sources", []) as Array).duplicate() \
			if tr.get("sources") is Array else []
		var bearing = tr.get("bearing_deg", null)
		var range = tr.get("range_km", null)
		var has_bearing := (bearing is int or bearing is float) and is_finite(float(bearing)) \
			and float(bearing) >= 0.0
		var has_range := (range is int or range is float) and is_finite(float(range)) \
			and float(range) > 0.0
		var row := {"id": tid, "batch": str(tr.get("batch", "")),
			"entity_id": entity_id, "facility_id": facility_id, "known": known,
			"level": level, "level_name": str(LEVEL_NAMES.get(level, "L%d" % level)),
			"level_label": str(LEVEL_LABELS.get(level, "")),
			"identity": str(tr.get("identity", "unknown")),
			"threat": str(tr.get("threat", "unknown")),
			"quality": quality, "confidence": quality,
			"age_s": age, "stale": stale,
			"sources": sources, "truth": false}
		if has_bearing:
			row["bearing_deg"] = _norm_deg(float(bearing))
		else:
			row["bearing_deg"] = null
		# L1 只给方位线/锥，不暴露距离/位置；L2+ 才保留 range
		if level >= 2 and has_range:
			row["range_km"] = float(range)
		else:
			row["range_km"] = null
		# L1：只给 bearing ray/cone，不给位置
		if has_bearing:
			var cone := _cone_for(level, quality, age)
			row["bearing_ray"] = {"origin_km": own_pos.duplicate(),
				"bearing_deg": _norm_deg(float(bearing)),
				"cone_deg": cone, "range_km": null,
				"truth": false}
			row["uncertainty_deg"] = cone
		else:
			row["bearing_ray"] = null
			row["reason"] = "missing_bearing"
		# L2+：局部估计位置（无 range/ownship 不伪造）
		if level >= 2:
			if has_bearing and has_range:
				var est := _estimate_pos(own_pos, float(bearing), float(range),
					tr.get("elevation_deg", 0.0))
				row["estimate_km"] = est
				row["position_km"] = est.duplicate()
				row["uncertainty_km"] = _uncertainty(level, float(range), quality, age)
				row["position_source"] = "ownship+bearing+range"
				row["position_truth"] = false
			else:
				row["estimate_km"] = null
				row["position_km"] = null
				row["uncertainty_km"] = null
				row["reason"] = "missing_bearing" if not has_bearing else "missing_range"
		# L3/L4：身份/威胁/证据（本身来自 TrackTable，不是 truth）
		if level >= 3:
			row["identity"] = str(tr.get("identity", "unknown"))
			row["threat"] = str(tr.get("threat", "unknown"))
			row["evidence"] = (tr.get("evidence", []) as Array).duplicate() \
				if tr.get("evidence") is Array else []
		tracks.append(row)
	tracks.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	var summary := {"tracks": tracks.size(), "levels": {"1": 0, "2": 0, "3": 0, "4": 0},
		"known": 0, "stale": 0, "with_position": 0, "bearing_only": 0,
		"missing_geometry": 0, "facilities": facilities.size(),
		"ownship_known": true, "truth": false}
	for raw2 in tracks:
		var row2: Dictionary = raw2
		var lv := int(row2.get("level", 1))
		summary["levels"][str(lv)] = int(summary["levels"].get(str(lv), 0)) + 1
		if bool(row2.get("known", false)):
			summary["known"] = int(summary["known"]) + 1
		if bool(row2.get("stale", false)):
			summary["stale"] = int(summary["stale"]) + 1
		if row2.get("estimate_km", null) != null:
			summary["with_position"] = int(summary["with_position"]) + 1
		elif lv == 1:
			summary["bearing_only"] = int(summary["bearing_only"]) + 1
		else:
			summary["missing_geometry"] = int(summary["missing_geometry"]) + 1
	_view = {"schema": SCHEMA, "version": VERSION, "ready": true,
		"t": t_vm, "truth": false,
		"writes": {"track_table": false, "world": false, "ui": false,
			"physics": false, "v15": false},
		"ownship": own, "facilities": facilities, "tracks": tracks,
		"summary": summary, "metadata_known": metadata.size()}
	_built = true
	return _view.duplicate(true)

func _valid_pos(v: Variant) -> Dictionary:
	if not (v is Array) or (v as Array).size() != 3:
		return {"ok": false}
	for x in (v as Array):
		if not (x is int or x is float) or not is_finite(float(x)):
			return {"ok": false}
	return {"ok": true, "pos_km": [float((v as Array)[0]), float((v as Array)[1]),
		float((v as Array)[2])]}

func _norm_deg(d: float) -> float:
	var x := fmod(d, 360.0)
	if x < 0.0:
		x += 360.0
	if x >= 360.0:
		x = 0.0
	return snappedf(x, 0.001)

## 北=+Y、顺时针为正：x=px+r*sin(bearing), y=py+r*cos(bearing), z=pz。
func _estimate_pos(own: Array, bearing_deg: float, range_km: float,
		elevation_deg: Variant) -> Array:
	var b := deg_to_rad(_norm_deg(bearing_deg))
	var el := deg_to_rad(float(elevation_deg)) if (elevation_deg is int or elevation_deg is float) else 0.0
	var horizontal := range_km * cos(el)
	return [float(own[0]) + horizontal * sin(b),
		float(own[1]) + horizontal * cos(b),
		float(own[2]) + range_km * sin(el)]

func _cone_for(level: int, quality: float, age: float) -> float:
	var base := float(config.get("base_cone_deg", 3.0))
	var qpen := (1.0 - quality) * float(config.get("quality_cone_deg", 4.0))
	var apen := minf(float(config.get("max_age_cone_deg", 6.0)),
		age * float(config.get("age_cone_deg_per_s", 0.05)))
	var cone := base + qpen + apen
	if level >= 2:
		cone = maxf(0.5, cone * 0.5)
	return snappedf(clampf(cone, 0.1, 25.0), 0.001)

func _uncertainty(level: int, range_km: float, quality: float, age: float) -> float:
	var base := float(config.get("base_uncertainty_km", 1.0))
	var rf := float(config.get("range_uncertainty_factor", 0.02))
	var qp := float(config.get("quality_penalty_km", 10.0))
	var ap := float(config.get("age_penalty_km_per_s", 0.1))
	var maxu := float(config.get("max_uncertainty_km", 500.0))
	var u := base + range_km * rf + (1.0 - quality) * qp + age * ap
	if level >= 3:
		u *= 0.9
	return snappedf(clampf(u, 0.0, maxu), 0.001)

# ── 查询 ────────────────────────────────────────────────────────

func _ensure_built() -> void:
	if not _built and ready:
		build()

func tracks() -> Array:
	_ensure_built()
	return (_view.get("tracks", []) as Array).duplicate(true)

func ownship() -> Dictionary:
	_ensure_built()
	return (_view.get("ownship", {}) as Dictionary).duplicate(true)

func facilities() -> Array:
	_ensure_built()
	return (_view.get("facilities", []) as Array).duplicate(true)

func summary() -> Dictionary:
	_ensure_built()
	return (_view.get("summary", {}) as Dictionary).duplicate(true)

func to_dict() -> Dictionary:
	_ensure_built()
	return _view.duplicate(true)

func to_json() -> String:
	return JSON.stringify(to_dict())

# ── 契约检查 ───────────────────────────────────────────────────

func check() -> Dictionary:
	_ensure_built()
	var v: Array[String] = []
	if not ready:
		v.append("CICView 未 ready")
	var view: Dictionary = _view
	if bool(view.get("truth", true)):
		v.append("CICView truth 必须 false")
	var w: Dictionary = view.get("writes", {}) if view.get("writes") is Dictionary else {}
	for k in ["track_table", "world", "ui", "physics", "v15"]:
		if bool(w.get(k, true)):
			v.append("CICView 不应写 " + str(k))
	for raw in (view.get("tracks", []) as Array):
		var tr: Dictionary = raw
		var lv := int(tr.get("level", 1))
		if lv == 1:
			if tr.has("estimate_km") or tr.has("position_km"):
				v.append("L1 不得含位置：" + str(tr.get("id", "")))
		if tr.has("estimate_km") and tr["estimate_km"] != null \
				and tr.get("position_km", null) == null:
			v.append("L2+ estimate 无 position：" + str(tr.get("id", "")))
		if bool(tr.get("truth", true)):
			v.append("track truth 必须 false：" + str(tr.get("id", "")))
	if not (_view.get("ownship") is Dictionary):
		v.append("ownship 必须是对象")
	return {"schema": SCHEMA, "ok": v.is_empty(), "violations": v}

func _fail(reason_text: String, msg: String) -> Dictionary:
	errors.append(msg)
	contract_errors.append(msg)
	return {"ok": false, "reason": str(reason_text), "errors": [msg]}
