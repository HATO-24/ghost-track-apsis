extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3Y 最小 probe：IncidentRecordService（未来事故记录生成器）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/incident_record_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不写 UI/world。
# ═══════════════════════════════════════════════════════════════════

const IncidentRecordService := preload("res://scripts/core/incident_record_service.gd")
const FacilityRegistry := preload("res://scripts/core/facility_registry.gd")

const TYPES := ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9"]
const REQUIRED_ACCIDENT := ["incident_id", "t_s", "t_iso", "facility_id",
	"facility_code", "cluster_id", "type", "type_key", "severity", "impact",
	"disposition", "record_integrity", "operator", "summary"]
const STANDARD_CHANNELS := ["pressure_kpa", "temperature_c", "power_kw", "flow_tph"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE3Y PROBE · IncidentRecordService")
	print("════════════════════════════════════════════════════════════")
	_test_setup_content()
	_test_schedule_determinism()
	_test_records_structure()
	_test_queries_format()
	_test_save_reset_invalid()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 INCIDENT RECORD PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 INCIDENT RECORD PROBE FAILED")
		quit(1)
	else:
		print("V17 INCIDENT RECORD PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if detail != "":
			line += "  (" + detail + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, detail])

func _eq(actual, expected, label: String, detail := "") -> void:
	var d := "actual=%s expected=%s" % [str(actual), str(expected)]
	if detail != "":
		d += " · " + detail
	_ok(actual == expected, label, d)

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _svc(cfg := {}) -> Object:
	var s = IncidentRecordService.new(cfg)
	_ok(bool(s.ready), "IncidentRecordService ready", str(s.errors))
	return s

func _norm(v) -> String:
	var txt := JSON.stringify(v)
	if txt.strip_edges() == "":
		return ""
	return JSON.stringify(JSON.parse_string(txt))

func _config(extra := {}) -> Dictionary:
	var c := {"seed": 2193, "horizon_days": 365}
	for k in extra.keys():
		c[k] = extra[k]
	return c

func _facility_codes(gen) -> Array:
	var out: Array = []
	for raw in gen.incidents():
		var code := str((raw as Dictionary).get("facility_code", ""))
		if not (code in out):
			out.append(code)
	return out

# ═══════════════════════════════════════════════════════════════════
# 1. setup / content / NESOSS 排除
# ═══════════════════════════════════════════════════════════════════

func _test_setup_content() -> void:
	_section_begin("1 setup/content")
	var s = _svc(_config())
	_eq(str(s.templates.get("schema", "")), "v17.incident_templates.v1", "templates schema")
	_eq((s.templates.get("types", []) as Array).size(), 9, "9 类事故模板")
	for code in TYPES:
		_ok(str(code) in (s._type_map.keys()), "模板含 " + str(code))
		var t: Dictionary = s._type_map[str(code)]
		_ok(str(t.get("name", "")) != "", "模板名称 " + str(code))
		_ok((t.get("severity", []) as Array).size() == 2, "severity 区间 " + str(code))
		_ok((t.get("anomalies", []) as Array).size() >= 1, "anomalies " + str(code))
		_ok((t.get("telemetry_channels", []) as Array).size() >= 1,
			"telemetry channels " + str(code))
	_ok(s.templates.get("facility_class_weights") is Dictionary, "设施类别权重")
	_ok(s.templates.get("anomaly_patterns") is Dictionary, "异常模式")
	_ok(s.templates.get("record_schema") is Dictionary, "record_schema")
	_ok(s.templates.get("schedule") is Dictionary, "schedule")
	# 设施与 NESOSS 排除
	_ok(s.facilities.size() >= 20, "可用设施 >=20", str(s.facilities.size()))
	_eq(s.facilities.size(), 23, "排除 NESOSS 后 23 设施")
	_eq(s.excluded.size(), 6, "NESOSS 排除 6")
	for raw in s.excluded:
		_eq(str((raw as Dictionary).get("reason", "")), "NESOSS excluded", "排除原因")
	for raw2 in s.facilities:
		var f: Dictionary = raw2
		_ok(not str(f.get("facility_code", "")).contains("NESOSS"), "无 NESOSS 设施")
		_ok(str(f.get("parent_cluster", "")) != "NESOSS", "无 NESOSS cluster")
		_ok(str(f.get("facility_id", "")) != "", "设施 id")
		_ok(str(f.get("facility_code", "")) != "", "设施 code")
	_eq(int(Time.get_unix_time_from_datetime_string("2193-11-07T00:00:00")),
		s.start_unix, "开场日期 unix")
	_eq(s.start_date, "2193-11-07", "开场日期")
	# pressure map
	var pm: Dictionary = s.pressure_map()
	_eq(pm.size(), s.facilities.size(), "pressure map 数量")
	for k in pm.keys():
		_ok(float(pm[k]) >= 0.0 and float(pm[k]) <= 1.0, "pressure 0..1 " + str(k))
	# FacilityRegistry 输入
	var reg = FacilityRegistry.new()
	_ok(bool(reg.ready), "FacilityRegistry ready")
	var via_reg = _svc(_config({"facility_registry": reg}))
	_eq(via_reg.facilities.size(), s.facilities.size(), "registry 输入同设施数")
	_ok(via_reg.ready, "registry 输入 ready")
	# 失败 setup
	var bad1 = IncidentRecordService.new({"horizon_days": -1.0})
	_ok(not bool(bad1.ready), "负 horizon 拒绝")
	var bad2 = IncidentRecordService.new({"pressure": 2.0})
	_ok(not bool(bad2.ready), "非法 pressure 拒绝")
	var bad3 = IncidentRecordService.new({"templates_path": "/no/such.json"})
	_ok(not bool(bad3.ready), "不存在模板拒绝")
	var bad4 = IncidentRecordService.new({"facilities": []})
	_ok(not bool(bad4.ready), "空设施拒绝")
	_data_line("setup", "9 类模板 · 23 可用设施/6 NESOSS 排除 · pressure 0..1 · Registry 输入")

# ═══════════════════════════════════════════════════════════════════
# 2. 排程 / 频率 / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_schedule_determinism() -> void:
	_section_begin("2 排程/频率")
	var s = _svc(_config())
	var g: Dictionary = s.generate()
	_eq(bool(g.get("ok", false)), true, "generate ok")
	_ok(int(g.get("generated", 0)) >= 10, "生成 >=10 事故", str(g.get("generated", 0)))
	_eq(int(g.get("excluded_nesoss", 0)), 6, "generate 排除 NESOSS")
	var incs: Array = s.incidents()
	_eq(incs.size(), int(g.get("generated", -1)), "incidents 数量")
	# 时间从开场后开始、落在 horizon 内
	var prev := 0.0
	var total_s := 365.0 * 86400.0
	var deltas: Array = []
	for raw in incs:
		var inc: Dictionary = raw
		var t := float(inc.get("t_s", 0.0))
		_ok(t > 0.0, "事故在开场后 " + str(inc.get("incident_id", "")))
		_ok(t <= total_s, "事故在 horizon 内")
		_ok(t > prev, "事故时间递增")
		if prev > 0.0:
			deltas.append(t - prev)
		prev = t
		_ok(str(inc.get("t_iso", "")) >= "2193-11-07", "日期不早于开场 " + str(inc.get("incident_id", "")))
		_ok(int(inc.get("day", 0)) >= 0, "day 非负")
	# 不规则：间隔不唯一
	var uniq: Dictionary = {}
	for d in deltas:
		uniq[str(snappedf(float(d), 1.0))] = true
	_ok(uniq.size() > 1, "间隔不规则", str(uniq.size()))
	# 同一站点可多次
	var counts: Dictionary = {}
	for inc2 in incs:
		var c := str((inc2 as Dictionary).get("facility_code", ""))
		counts[c] = int(counts.get(c, 0)) + 1
	var max_count := 0
	for k in counts.keys():
		max_count = maxi(max_count, int(counts[k]))
	_ok(max_count >= 2, "同一站点可多次事故", str(max_count))
	# 确定性：同 seed/配置一致
	var a = _svc(_config({"seed": 42}))
	var b = _svc(_config({"seed": 42}))
	var ga: Dictionary = a.generate()
	var gb: Dictionary = b.generate()
	_eq(ga.get("generated"), gb.get("generated"), "同 seed 生成数一致")
	_eq(_norm(a.incidents()), _norm(b.incidents()), "同 seed incidents 一致")
	_eq(_norm(a.clues()), _norm(b.clues()), "同 seed clues 一致")
	_eq(a.save_state(), b.save_state(), "同 seed save 一致")
	# 不同 seed 不同
	var c = _svc(_config({"seed": 43}))
	c.generate()
	_ok(_norm(a.incidents()) != _norm(c.incidents()), "不同 seed 不同")
	# pressure 频率：高 pressure 更多/更短间隔
	var lo = _svc(_config({"seed": 7, "horizon_days": 365, "pressure": 0.0}))
	var hi = _svc(_config({"seed": 7, "horizon_days": 365, "pressure": 1.0}))
	var glo: Dictionary = lo.generate()
	var ghi: Dictionary = hi.generate()
	_ok(int(ghi.get("generated", 0)) > int(glo.get("generated", 0)),
		"高 pressure 更高频率", "%d > %d" % [int(ghi.generated), int(glo.generated)])
	_ok(float(ghi.get("last_t_s", 0.0)) >= float(glo.get("last_t_s", 0.0)),
		"高 pressure 覆盖更晚")
	# 每设施 pressure 生效
	var pf = _svc(_config({"seed": 9, "horizon_days": 365,
		"pressure": {"FC-L1-05": 1.0, "default": 0.0}}))
	pf.generate()
	_eq(float(pf.pressure_map().get("FC-L1-05", 0.0)), 1.0, "单设施 pressure")
	_eq(float(pf.pressure_map().get("FC-L2-02", 1.0)), 0.0, "默认 pressure")
	# 更高 horizon 覆盖更久
	var long = _svc(_config({"seed": 2193, "horizon_days": 730}))
	long.generate()
	_ok(long.incidents().size() > s.incidents().size(), "更长 horizon 更多事故")
	_data_line("schedule", "开场后不规则排程 · 递增/不重复间隔 · 同站点多次 · 高 pressure 更高频 · 确定")

# ═══════════════════════════════════════════════════════════════════
# 3. 三类记录 / 线索结构
# ═══════════════════════════════════════════════════════════════════

func _test_records_structure() -> void:
	_section_begin("3 记录结构")
	var s = _svc(_config())
	s.generate()
	var type_meta: Dictionary = s._type_map
	for raw in s.incidents():
		var inc: Dictionary = raw
		var iid := str(inc.get("incident_id", ""))
		var fac := str(inc.get("facility_code", ""))
		var typ := str(inc.get("type", ""))
		_ok(iid.begins_with("INC-"), "incident id 前缀")
		_ok(typ in TYPES, "type A1-A9 " + iid)
		_ok(int(inc.get("severity", 0)) >= 1 and int(inc.get("severity", 0)) <= 5,
			"severity 1..5 " + iid)
		_ok(inc.get("impact") is Dictionary, "impact " + iid)
		_ok(inc.get("disposition") is Dictionary, "disposition " + iid)
		_ok(inc.get("record_integrity") is Dictionary, "integrity " + iid)
		_ok(inc.get("operator") is Dictionary, "operator " + iid)
		_eq(bool((inc.get("operator", {}) as Dictionary).get("generic", false)), true,
			"operator 泛化 " + iid)
		var rec: Dictionary = s.records(iid)
		_eq(rec.keys().size() >= 5, true, "records 键 " + iid)
		_ok(rec.get("accident_log") is Dictionary, "accident_log " + iid)
		_ok(rec.get("telemetry") is Dictionary, "telemetry " + iid)
		_ok(rec.get("otc") is Dictionary, "otc " + iid)
		_ok(rec.get("clues") is Array, "records clues " + iid)
		# accident_log
		var al: Dictionary = rec.get("accident_log")
		for f in REQUIRED_ACCIDENT:
			_ok(al.has(f), "accident_log 字段 %s/%s" % [iid, f])
		_eq(str(al.get("incident_id", "")), iid, "accident id " + iid)
		_eq(str(al.get("facility_code", "")), fac, "accident facility " + iid)
		_eq(str(al.get("type", "")), typ, "accident type " + iid)
		_eq(bool(al.get("writes_v15", true)), false, "accident 不写 v15")
		# telemetry 前后采样/通道/缺口/异常/编辑/hash
		var tm: Dictionary = rec.get("telemetry")
		_ok((tm.get("samples", []) as Array).size() >= 2, "telemetry samples " + iid)
		var has_before := false
		var has_after := false
		for sm in (tm.get("samples", []) as Array):
			if sm is Dictionary:
				var off := float((sm as Dictionary).get("offset_s", 0.0))
				if off < 0.0:
					has_before = true
				if off > 0.0:
					has_after = true
		_ok(has_before and has_after, "telemetry 前后采样 " + iid)
		for ch in STANDARD_CHANNELS:
			_ok(str(ch) in (tm.get("channels", []) as Array), "telemetry 通道 " + str(ch) + " " + iid)
		_ok(tm.get("gaps") is Array, "telemetry gaps " + iid)
		_ok(tm.get("anomalies") is Array, "telemetry anomalies " + iid)
		_ok(tm.get("edit_marks") is Array, "telemetry edit_marks " + iid)
		_ok(str(tm.get("hash", "")).begins_with("sha256:"), "telemetry hash " + iid)
		_ok(tm.get("record_integrity") is Dictionary, "telemetry integrity " + iid)
		# OTC
		var otc: Dictionary = rec.get("otc")
		_ok((otc.get("tracks", []) as Array).size() >= 1, "otc tracks " + iid)
		for tk in (otc.get("tracks", []) as Array):
			if tk is Dictionary:
				_ok(str((tk as Dictionary).get("track_id", "")) != "", "track id " + iid)
				_ok(str((tk as Dictionary).get("transponder", "")) != "", "transponder " + iid)
				_ok(str((tk as Dictionary).get("clearance", "")) != "", "clearance " + iid)
				_ok((tk as Dictionary).get("handoff") is Dictionary, "handoff " + iid)
		_ok(otc.get("deleted_records") is Array, "otc deleted " + iid)
		_ok(otc.get("rewritten_records") is Array, "otc rewritten " + iid)
		_ok(otc.get("duplicate_codes") is Array, "otc duplicate " + iid)
		_ok(str(otc.get("hash", "")).begins_with("sha256:"), "otc hash " + iid)
		# clues
		var cl: Array = rec.get("clues", []) as Array
		_ok(cl.size() >= 1, "每事故至少 1 线索 " + iid)
		for cr in cl:
			var c: Dictionary = cr
			_eq(str(c.get("schema", "")), "incident_ghost_track_clue.v1", "clue schema " + iid)
			_eq(str(c.get("incident_id", "")), iid, "clue 关联 " + iid)
			_ok(str(c.get("clue_id", "")).begins_with("GTC-"), "clue id " + iid)
			_ok(str(c.get("kind", "")) != "", "clue kind " + iid)
			_ok(str(c.get("description", "")) != "", "clue description " + iid)
			_ok(float(c.get("confidence", -1.0)) >= 0.0 and float(c.get("confidence", 2.0)) <= 1.0,
				"clue confidence " + iid)
			_ok(c.get("evidence_ref") is Dictionary, "clue evidence_ref " + iid)
		# 类型 severity 区间
		var meta: Dictionary = type_meta[typ]
		var sr: Array = meta.get("severity", [1, 5]) as Array
		_ok(int(inc.get("severity", 0)) >= int(sr[0]) and int(inc.get("severity", 0)) <= int(sr[1]),
			"severity 符合模板 " + iid)
	_data_line("records", "事故日志字段 · 遥测前后采样/4 通道/缺口/异常/编辑/hash · OTC track/transponder/clearance/handoff · 线索")

# ═══════════════════════════════════════════════════════════════════
# 4. 查询 / 文本
# ═══════════════════════════════════════════════════════════════════

func _test_queries_format() -> void:
	_section_begin("4 查询/文本")
	var s = _svc(_config())
	s.generate()
	var incs: Array = s.incidents()
	_eq(s.incident_ids().size(), incs.size(), "incident_ids 数量")
	var ids: Dictionary = {}
	for iid in s.incident_ids():
		_ok(not ids.has(str(iid)), "incident id 唯一 " + str(iid))
		ids[str(iid)] = true
	# in_between 秒
	var first_t := float((incs[0] as Dictionary).get("t_s", 0.0))
	var last_t := float((incs[-1] as Dictionary).get("t_s", 0.0))
	var all_range: Array = s.in_between(0.0, 365.0 * 86400.0)
	_eq(all_range.size(), incs.size(), "in_between 全范围")
	var near: Array = s.in_between(first_t - 1.0, first_t + 1.0)
	_ok(near.size() >= 1, "in_between 定位事故")
	_eq(s.in_between(last_t + 10.0, last_t + 100.0).size(), 0, "in_between 空范围")
	# ISO 日期输入
	var iso_range: Array = s.in_between("2193-11-07", "2194-11-07")
	_eq(iso_range.size(), incs.size(), "in_between ISO")
	# 记录/线索查询
	var iid0 := str((incs[0] as Dictionary).get("incident_id", ""))
	_ok(not s.records(iid0).is_empty(), "records 查询")
	_eq(s.records({"incident_id": iid0}).get("incident_id", ""), iid0, "records 接受 dict")
	_eq(s.records("NOPE").size(), 0, "未知 records 空")
	var cl: Array = s.clues(iid0)
	_ok(cl.size() >= 1, "clues 按事故过滤")
	_eq((s.records(iid0).get("clues", []) as Array).size(), cl.size(), "records clues 数量")
	_eq(s.clues("NOPE").size(), 0, "未知 clues 空")
	# 文本格式
	var atxt := str(s.format_accident_text(iid0))
	_ok(atxt.contains("[事故记录]"), "事故文本 header")
	_ok(atxt.contains(iid0), "事故文本 id")
	_ok(atxt.contains(str((incs[0] as Dictionary).get("facility_code", ""))), "事故文本 facility")
	_ok(atxt.contains(str((incs[0] as Dictionary).get("type", ""))), "事故文本 type")
	_ok(atxt.contains("严重度"), "事故文本 severity")
	_ok(not atxt.contains("台词"), "事故文本无台词")
	var ttxt := str(s.format_telemetry_text(iid0))
	_ok(ttxt.contains("[遥测记录]"), "遥测文本 header")
	_ok(ttxt.contains("sha256:"), "遥测文本 hash")
	_ok(ttxt.contains("缺口"), "遥测文本 gaps")
	var otxt := str(s.format_otc_text(iid0))
	_ok(otxt.contains("[OTC/交通记录]"), "OTC 文本 header")
	_ok(otxt.contains("track="), "OTC 文本 track")
	_ok(otxt.contains("transponder="), "OTC 文本 transponder")
	_eq(str(s.format_accident_text("NOPE")), "", "未知事故文本空")
	_eq(str(s.format_telemetry_text(iid0)).length() > 0, true, "遥测文本非空")
	# 文本确定性
	_eq(str(s.format_accident_text(iid0)), str(s.format_accident_text(iid0)),
		"事故文本确定")
	_data_line("queries/format", "in_between 秒/ISO · records/clues 查询 · 三文本含 id/facility/type/hash · 无台词")

# ═══════════════════════════════════════════════════════════════════
# 5. save/load/reset/非法
# ═══════════════════════════════════════════════════════════════════

func _test_save_reset_invalid() -> void:
	_section_begin("5 save/reset/非法")
	var s = _svc(_config())
	s.generate()
	var save := str(s.save_state())
	var d = JSON.parse_string(save)
	_ok(d is Dictionary and (d as Dictionary).get("schema", "") == "v17.incident_record_save.v1",
		"save schema")
	for k in ["incidents", "clues", "facilities", "pressure_cfg", "start_unix",
			"horizon_days", "seed", "rng_state"]:
		_ok((d as Dictionary).has(k), "save 字段 " + str(k))
	var s2 = _svc(_config())
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "load ok", str(lr.get("errors", [])))
	_eq(_norm(s.vm()), _norm(s2.vm()), "load VM 一致")
	_eq(_norm(s.incidents()), _norm(s2.incidents()), "load incidents 一致")
	_eq(_norm(s.clues()), _norm(s2.clues()), "load clues 一致")
	_errorless(s2)
	# reset 后同 seed 重新生成一致
	var a = _svc(_config({"seed": 77}))
	a.generate()
	var before_vm := _norm(a.vm())
	var before_inc := _norm(a.incidents())
	var rr: Dictionary = a.reset()
	_eq(bool(rr.get("ok", false)), true, "reset ok")
	_eq(a.incidents().size(), 0, "reset 后无事故")
	_eq(a.clues().size(), 0, "reset 后无线索")
	var ag: Dictionary = a.generate()
	_eq(bool(ag.get("ok", false)), true, "reset 后 generate ok")
	_eq(_norm(a.incidents()), before_inc, "reset 后同 seed 重生成一致")
	_eq(_norm(a.vm()), before_vm, "reset 后 VM 一致")
	# 非法 generate
	var bad = _svc(_config())
	_eq(str(bad.generate({"horizon_days": -5.0}).get("reason", "")), "invalid_horizon",
		"非法 horizon generate")
	# 非法存档
	var keep := _norm(s2.vm())
	var bads: Array = ["", "{bad", JSON.stringify({"schema": "bad"}),
		JSON.stringify({"schema": "v17.incident_record_save.v1", "version": "9.9.9"}),
		JSON.stringify({"schema": "v17.incident_record_save.v1", "version": "1.0.0",
			"incidents": [], "clues": [], "facilities": []}),
		JSON.stringify({"schema": "v17.incident_record_save.v1", "version": "1.0.0",
			"incidents": [], "clues": [], "facilities": [], "pressure_cfg": "bad"}),
		JSON.stringify({"schema": "v17.incident_record_save.v1", "version": "1.0.0",
			"incidents": "bad", "clues": [], "facilities": [], "pressure_cfg": {}})]
	for b in bads:
		_eq(bool(s2.load_state(str(b)).get("ok", true)), false,
			"非法存档拒绝：" + str(b).substr(0, 30))
	_eq(_norm(s2.vm()), keep, "非法存档不改状态")
	# 确定性 + contracts
	var x = _svc(_config({"seed": 101}))
	var y = _svc(_config({"seed": 101}))
	x.generate()
	y.generate()
	_eq(_norm(x.incidents()), _norm(y.incidents()), "同配置 incidents 一致")
	_eq(x.save_state(), y.save_state(), "同配置 save 一致")
	_ok(bool(s.check_contracts().get("ok", false)), "contracts ok")
	_eq(bool((s.vm().get("writes", {}) as Dictionary).get("world", true)), false,
		"不写 world")
	_eq(bool((s.vm().get("writes", {}) as Dictionary).get("ui", true)), false,
		"不写 UI")
	_data_line("save/reset", "save 字段/load VM 一致 · reset 重生成一致 · 非法 generate/存档原子拒绝 · 确定")

func _errorless(s) -> void:
	_ok(s.incidents().size() > 0, "load 后 incidents 可用")
	_ok(s.clues().size() > 0, "load 后 clues 可用")
	_ok(bool(s.check_contracts().get("ok", false)), "load 后 contracts ok")
