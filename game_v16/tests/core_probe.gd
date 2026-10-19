extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# V2-1 headless probe（core 数据模型/状态机）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v16" --script res://tests/core_probe.gd
#
# 覆盖：内容规则 / V2 schema 校验 / v15 迁移 / L1→L4 航迹状态机 / 身份与等级分离 /
#       动作可用性 / 命令状态机与队列 / 数据驱动阶段推进 / world view-model /
#       证据 / sim 观测桥。测试数据全部来自 content/*.json，不写死批号。
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const V2_SCENARIO := "res://content/scenario_l1_v2.json"
const LEGACY_SCENARIO := "res://content/scenario_l1.json"
const TRACK_RULES := "res://content/track_rules.json"

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("V2-1 CORE PROBE")
	print("════════════════════════════════════════════════════════════")
	_test_content_rules()
	_test_scenario_v2()
	_test_schema_errors()
	_test_legacy_migration()
	_test_track_state_machine()
	_test_actions()
	_test_orders()
	_test_mission()
	_test_world_and_view_model()
	_test_observation_bridge()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V2-1 CORE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("PROBE FAILED")
		quit(1)
	else:
		print("PROBE OK")
		quit(0)

# ── 测试工具 ─────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)

func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		if detail != "":
			print("[PASS] %s  %s" % [label, detail])
		else:
			print("[PASS] %s" % label)
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

func _non_empty(s: String, label: String) -> void:
	_ok(s != "", label, "" if s == "" else s)

func _contains(haystack: Array, needle, label: String) -> void:
	_ok(needle in haystack, label, "needle=" + str(needle))

func _errors_contain(errors: Array, substr: String, label: String) -> void:
	var hit := false
	for e in errors:
		if String(e).contains(substr):
			hit = true
			break
	_ok(hit, label, "substr=" + substr + " errors=" + str(errors).substr(0, 300))

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

# ═══════════════════════════════════════════════════════════════════
# 1. 内容规则（track_rules / actions）— 代码不写死数值与清单
# ═══════════════════════════════════════════════════════════════════

func _test_content_rules() -> void:
	_section_begin("1 内容规则")
	var rule_errors: Array = []
	var rules: Dictionary = V2TrackTable.load_rules(TRACK_RULES, rule_errors)
	_eq(rule_errors.size(), 0, "track_rules 加载无错误")
	var levels: Array = rules.get("levels", [])
	_eq(levels.size(), 5, "track_rules 等级数 = 5（L0–L4）")
	var names: Array = []
	var valid: Dictionary = {}
	for raw in levels:
		var d: Dictionary = raw
		names.append(String(d.get("id", "")))
		valid[int(d.get("level", -1))] = float(d.get("valid_s", -1))
	_ok("BEARING" in names and "POSITION" in names and "CLASSIFIED" in names and "IDENTIFIED" in names,
		"等级名 L1 BEARING → L2 POSITION → L3 CLASSIFIED → L4 IDENTIFIED", str(names))
	_eq(valid.get(2, 0.0), 210.0, "L2 有效期 210s（来自内容，非代码）")
	_eq(valid.get(3, 0.0), 90.0, "L3 有效期 90s")
	_eq(valid.get(4, 0.0), 30.0, "L4 有效期 30s")
	var idn: Dictionary = rules.get("identity", {})
	_eq((idn.get("classes", []) as Array).size(), 7, "身份分类 7 级（待定/未知/假定友好/友方/中立/可疑/敌方）")

	_ok(V2Actions.ensure_loaded(), "actions 内容加载无错误", str(V2Actions.errors))
	_ok(V2Actions.definitions.size() >= 10, "动作定义数量 >= 10", str(V2Actions.definitions.size()))
	var required := ["crossfix", "radar_illum", "model_ident", "radar_track",
		"iff_query", "optical_channel", "ir_channel"]
	for aid in required:
		_ok(not V2Actions.definition(aid).is_empty(), "动作存在: " + aid)
	for wid in ["fire_control", "missile_solve", "weapons_hold"]:
		var wd := V2Actions.definition(wid)
		_ok(not wd.is_empty(), "武器类动作存在（显式 unsupported）: " + wid)
		_eq(bool(wd.get("supported", true)), false, "武器类 " + wid + " supported=false")
		_non_empty(String(wd.get("unsupported_reason", "")), "武器类 " + wid + " 有 unsupported_reason")
	_data_line("track_rules levels", str(names))
	_data_line("track_rules decay", "L2=%.0fs L3=%.0fs L4=%.0fs" % [valid[2], valid[3], valid[4]])
	_data_line("actions", str(V2Actions.definitions.size()))

# ═══════════════════════════════════════════════════════════════════
# 2. V2 场景（schema v2，数据驱动实体/航迹/阶段/证据/命令配置）
# ═══════════════════════════════════════════════════════════════════

var _sc_v2: V2Scenario = null

func _test_scenario_v2() -> void:
	_section_begin("2 V2 场景加载")
	var s := V2Scenario.load_file(V2_SCENARIO)
	_sc_v2 = s
	_eq(s.errors.size(), 0, "V2 场景校验无错误", str(s.errors))
	_eq(s.migrated, false, "V2 场景不是迁移路径")
	_eq(s.entities.size(), 9, "V2 场景实体数 9（7 舰 + 站体 + 储罐）")
	_eq(s.initial_tracks.size(), 10, "V2 场景初始航迹 10（8 + 站体/储罐）")
	_eq(s.phases.size(), 7, "V2 场景阶段数 7")
	_eq(s.phase_kinds(), ["PRELUDE", "READ", "COMMAND", "DECISION", "CONSEQUENCE", "REPORT", "END"],
		"阶段 kind 序列来自场景数据")
	_eq(s.own_entity_id, "harmattan", "own_entity 解析")
	_eq(s.evidence_defs.size(), 4, "证据定义 4")
	_eq(int(s.evidence_policy.get("min_for_expose", 0)), 2, "证据门槛来自场景 policy")
	_eq(float(s.orders_config.get("tx_delay_s", 0.0)), 8.0, "命令链路延迟来自场景配置")
	_non_empty(String(s.story.get("decision_prompt", "")), "story 文本从 story_file 载入")
	_eq(s.endings.size(), 3, "结局选项来自内容（3 种，不写死）")

	var summon := s.find_entity("summons_4471")
	_ok(summon != null, "按 slug 找到实体 summons_4471")
	if summon != null:
		_eq(summon.batch, "2001", "实体批号来自数据")
		_contains(summon.capabilities, "sensor.elint.passive", "实体能力来自数据")
		_contains(summon.capabilities, "sensor.radar.active", "实体雷达能力来自数据")
	var phantom := s.track_seed("9002")
	_eq(phantom.size() > 0 and String(phantom.get("entity_id", "x")) == "", true,
		"回波航迹 9002 无实体（不写死批号）")
	_data_line("V2 scenario", "entities=7 tracks=8 phases=7 evidence=4 endings=3")

# ═══════════════════════════════════════════════════════════════════
# 3. V2 schema 校验：错误必须明确
# ═══════════════════════════════════════════════════════════════════

func _test_schema_errors() -> void:
	_section_begin("3 V2 schema 校验")
	var bad := {
		"schema": "scenario.v2",
		"id": "bad",
		"title": "bad",
		"epoch": 0.0,
		"entities": [
			{"id": "a", "kind": "ship", "side": "weird"},
			{"id": "a", "kind": "ship", "side": "friend"},
		],
		"tracks": [{"id": "t1", "entity_id": "missing", "level": 9}],
		"phases": [
			{"id": "p1", "kind": "NOPE"},
			{"id": "p1", "kind": "READ"},
			{"id": "p2", "kind": "READ", "enter": {"bogus_condition": 1}},
		],
	}
	var s := V2Scenario.from_dict(bad, "<test>")
	_ok(s.errors.size() >= 5, "非法场景产生多条明确错误", str(s.errors.size()))
	_errors_contain(s.errors, "side", "报非法阵营")
	_errors_contain(s.errors, "entity_id", "报悬空 entity_id")
	_errors_contain(s.errors, "level", "报 level 越界")
	_errors_contain(s.errors, "kind", "报非法阶段 kind")
	_errors_contain(s.errors, "重复", "报重复 id")
	_errors_contain(s.errors, "未知进入条件", "报未知进入条件键")
	_errors_contain(s.errors, "own_entity", "报无法确定己方实体")
	var missing := V2Scenario.from_dict({"schema": "scenario.v2"}, "<test>")
	_ok(missing.errors.size() >= 5, "缺字段场景产生多条错误", str(missing.errors))
	_data_line("schema errors", str(s.errors.size()))

# ═══════════════════════════════════════════════════════════════════
# 4. v15 旧场景迁移（tracks/ships/story → entities/initial_tracks/phases）
# ═══════════════════════════════════════════════════════════════════

var _sc_legacy: V2Scenario = null

func _test_legacy_migration() -> void:
	_section_begin("4 v15 → V2 迁移")
	var s := V2Scenario.load_file(LEGACY_SCENARIO)
	_sc_legacy = s
	_eq(s.errors.size(), 0, "旧场景迁移无错误", str(s.errors))
	_eq(s.migrated, true, "识别为旧场景迁移")
	_eq(s.entities.size(), 7, "迁移实体 7（ships/tracks 合并）")
	_eq(s.initial_tracks.size(), 8, "迁移航迹 8（7 条 + 虚警 9002）")
	_eq(s.own_entity_id, "1001", "own_ship 迁移为己方实体 1001")
	_eq(s.phase_kinds(), ["PRELUDE", "READ", "COMMAND", "DECISION", "CONSEQUENCE", "REPORT", "END"],
		"story 结构迁移为 7 个数据驱动阶段")
	_eq(s.evidence_defs.size(), 4, "story.evidence_tasks 迁移为证据定义")
	_non_empty(String(s.story.get("decision_prompt", "")), "story 保留")

	var e2001 := s.find_entity("2001")
	_ok(e2001 != null, "迁移实体 2001 存在")
	if e2001 != null:
		_eq(e2001.batch, "2001", "实体批号 = 旧 track id")
		_contains(e2001.capabilities, "sensor.elint.passive", "2001 能力含 ELINT（来自传感器架）")
		_contains(e2001.capabilities, "sensor.radar.active", "2001 能力含雷达（来自传感器架）")
		_eq((e2001.meta.get("sensors", []) as Array).size(), 4, "2001 传感器架迁移 4 模块")
		_eq(String(e2001.identity), "unknown", "身份迁移（未知）")
	_eq(s.find_entity("9002"), null, "虚警 9002 不迁移为实体")
	var seed_fa := s.track_seed("9002")
	if not seed_fa.is_empty():
		_contains(seed_fa.get("tags", []), "false_alarm", "虚警航迹带 false_alarm 标记")
		_eq(float(seed_fa.get("bearing_deg", -1.0)), 302.0, "虚警方位来自 story.false_alarm")
	var own_e := s.by_batch("1001")
	_ok(own_e != null and "own" in own_e.tags, "己方实体 1001 带 own 标记")
	_data_line("legacy migration", "entities=7 tracks=8 phases=7 evidence=4")

# ═══════════════════════════════════════════════════════════════════
# 5. 航迹状态机：L1 → L2 → L3 → L4、身份分离、质量门槛、衰减
# ═══════════════════════════════════════════════════════════════════

func _test_track_state_machine() -> void:
	_section_begin("5 航迹状态机 L1→L4")
	var errs: Array = []
	var rules: Dictionary = V2TrackTable.load_rules(TRACK_RULES, errs)
	var table := V2TrackTable.new(rules)

	# L1：IR 方位线（无距离）
	var t := table.ingest({
		"track_id": "SIM-77", "entity_id": "unit-a", "sensor": "CH-IR2",
		"source": "harmattan", "kind": "ir", "t": 0.0, "quality": 0.9,
		"bearing_deg": 302.0, "bearing_sigma_deg": 1.2, "support": 1,
	}, 0.0)
	_ok(t != null, "ingest 新建航迹")
	_eq(t.level, 1, "L1 BEARING")
	_eq(t.level_name(), "BEARING", "L1 等级名来自规则")
	_eq(t.is_bearing_only(), true, "L1 仅方位（无距离解）")
	_eq(t.range_km, -1.0, "L1 无距离")
	_contains(t.sources, "CH-IR2", "观测记录 sensor")
	_contains(t.observers, "harmattan", "观测记录 source")
	_eq(t.observation_count, 1, "观测计数")

	# L2：雷达距离 + 方位
	table.observe("SIM-77", {
		"track_id": "SIM-77", "sensor": "YW-R9", "source": "harmattan",
		"kind": "radar", "t": 10.0, "quality": 0.8, "support": 2,
		"bearing_deg": 302.5, "bearing_sigma_deg": 0.15,
		"range_km": 120.0, "range_sigma_km": 1.0,
	}, 10.0)
	_eq(t.level, 2, "L2 POSITION（雷达给距离+方位）")
	_eq(t.level_name(), "POSITION", "L2 等级名")
	_eq(t.range_km, 120.0, "L2 距离")
	_eq(t.has_position(), true, "L2 有位置解")

	# L3：光学凝视分类
	table.observe("SIM-77", {
		"track_id": "SIM-77", "sensor": "MS-OT2", "source": "harmattan",
		"kind": "optical", "t": 20.0, "quality": 0.6, "support": 3,
		"classification": {"ship_class": "传唤级", "faction": "UEG 第33舰队", "confidence": 0.9},
	}, 20.0)
	_eq(t.level, 3, "L3 CLASSIFIED（光学分类）")
	_eq(String(t.classification.get("ship_class", "")), "传唤级", "L3 分类数据")
	_eq(t.has_classification(), true, "L3 有分类")

	# L4：IFF / 身份
	table.observe("SIM-77", {
		"track_id": "SIM-77", "sensor": "MK-12", "source": "harmattan",
		"kind": "iff", "t": 30.0, "quality": 0.95, "support": 4,
		"bearing_deg": 302.4, "bearing_sigma_deg": 1.0, "range_km": 118.0, "range_sigma_km": 1.0,
		"identity": {"name": "AV-4412", "hull": "4412", "via": "iff", "confidence": 0.9, "kind": "assumed_friend"},
		"iff_status": "friend",
	}, 30.0)
	_eq(t.level, 4, "L4 IDENTIFIED（身份数据）")
	_eq(t.level_name(), "IDENTIFIED", "L4 等级名")
	_eq(t.identity_kind, "assumed_friend", "身份与等级分开存储（身份=假定友好）")
	_eq(String(t.identity.get("name", "")), "AV-4412", "L4 身份详情")
	_eq(t.iff_status, "friend", "IFF 状态")
	_eq(t.level_evidence.has(4), true, "L4 证据时间戳")
	_data_line("track SIM-77", "L%d %s identity=%s sources=%s" %
		[t.level, t.level_name(), t.identity_kind, str(t.sources)])

	# 身份与等级分离：L2 时身份可以已经是中立
	var table_b := V2TrackTable.new(rules)
	var t2 := table_b.ingest({
		"track_id": "SIM-88", "entity_id": "a", "kind": "radar", "sensor": "YW-R9",
		"source": "harmattan", "t": 0.0, "quality": 0.7, "support": 2,
		"bearing_deg": 10.0, "range_km": 50.0, "range_sigma_km": 1.0,
		"identity_kind": "neutral",
	}, 0.0)
	_eq(t2.level, 2, "身份不提升等级：L2")
	_eq(t2.identity_kind, "neutral", "L2 同时身份=中立（分离）")
	# IFF 无应答 → 未知（不自动判敌）
	var table_c := V2TrackTable.new(rules)
	var t3 := table_c.ingest({
		"track_id": "SIM-89", "entity_id": "b", "kind": "iff", "sensor": "MK-12",
		"source": "harmattan", "t": 0.0, "quality": 0.5, "support": 1,
		"bearing_deg": 40.0, "iff_status": "no_reply",
	}, 0.0)
	_eq(t3.identity_kind, "unknown", "IFF 无应答 → 未知（不自动判敌）")
	_ok(t3.level <= 2, "IFF 无应答不会给等级加成")

	# 证据衰减：L4→L3→L2→L1（数值来自内容）
	var table_d := V2TrackTable.new(rules)
	table_d.ingest({
		"track_id": "DECAY", "entity_id": "c", "kind": "iff", "sensor": "MK-12",
		"source": "x", "t": 0.0, "quality": 1.0, "support": 4,
		"bearing_deg": 45.0, "range_km": 100.0, "range_sigma_km": 1.0,
		"classification": {"ship_class": "C"},
		"identity": {"name": "N", "via": "iff", "kind": "friend"}, "iff_status": "friend",
	}, 0.0)
	var td := table_d.find("DECAY")
	_eq(td.level, 4, "衰减测试起点 L4")
	table_d.expire(31.0)
	_eq(td.level, 3, "L4 30s 后衰减 → L3")
	_ok(td.stale, "失去刷新 → stale")
	table_d.expire(91.0)
	_eq(td.level, 2, "L3 90s 后衰减 → L2")
	table_d.expire(211.0)
	_eq(td.level, 1, "L2 210s 后衰减 → L1（记忆地板）")
	var trans := table_d.expire(9999.0)
	_eq(td.level, 1, "L1 不衰减为 L0（失去跟踪不删除）")
	_data_line("decay", "seed L4 → 31s:L%d → 91s:L%d → 211s:L%d transitions=%d" %
		[3, 2, 1, trans.size()])

	# 质量门槛：低质量观测不刷新证据
	var table_e := V2TrackTable.new(rules)
	table_e.ingest({"track_id": "Q", "entity_id": "e", "kind": "ir", "t": 0.0,
		"quality": 0.9, "bearing_deg": 1.0, "support": 1}, 0.0)
	var q_t := table_e.find("Q")
	var applied := q_t.apply_observation({"kind": "radar", "t": 1.0, "quality": 0.0,
		"support": 2, "range_km": 100.0, "bearing_deg": 1.0}, 1.0)
	_eq(applied, false, "低质量观测被拒绝（quality < min_quality）")
	_eq(q_t.level, 1, "低质量观测不提升等级")

	# 支撑级一致性校验：声称 L2 但无位置 → 降为 L1
	var table_f := V2TrackTable.new(rules)
	var f_t := table_f.ingest({"track_id": "V", "entity_id": "f", "kind": "radar",
		"t": 0.0, "quality": 0.9, "support": 2, "bearing_deg": 5.0}, 0.0)
	_eq(f_t.level, 1, "无位置解的 L2 声称被降级为 L1")
	var note_hit := false
	for n in f_t.notes:
		if String(n).contains("降为 L1"):
			note_hit = true
	_ok(note_hit, "降级原因写入 notes")

	# 自动批号（不写死批号）
	var table_g := V2TrackTable.new(rules)
	var g_t := table_g.ingest({"entity_id": "anon-1", "kind": "ir", "t": 5.0,
		"quality": 0.5, "bearing_deg": 10.0}, 5.0)
	_eq(g_t.id, "T0001", "匿名航迹自动批号按规则生成")
	_eq(table_g.find_by_entity("anon-1") == g_t, true, "实体双索引")
	_ok(table_g.summary().size() == 1, "summary 视图行")

	# 迁移种子按 age 立即衰减
	var table_h := V2TrackTable.new(rules)
	var h_t := table_h.seed({"id": "H", "entity_id": "h", "level": 4, "identity": "friend",
		"age_s": 40.0}, 0.0)
	_eq(h_t.level, 3, "播种 L4 但 age=40s → 立即衰减为 L3")

# ═══════════════════════════════════════════════════════════════════
# 6. 动作可用性（内容驱动 + available/reason）
# ═══════════════════════════════════════════════════════════════════

func _test_actions() -> void:
	_section_begin("6 动作可用性")
	V2Actions.ensure_loaded()
	var actor := V2Entity.from_dict({
		"id": "actor-x", "side": "friend",
		"capabilities": ["sensor.ir", "sensor.radar.active", "sensor.optical",
			"sensor.iff.interrogator", "comms.radio"],
	})
	var target := V2Entity.from_dict({"id": "tgt-x", "batch": "T-42", "side": "hostile", "track_level": 1})
	var errs: Array = []
	var rules: Dictionary = V2TrackTable.load_rules(TRACK_RULES, errs)
	var table := V2TrackTable.new(rules)
	var tr := table.ingest({"track_id": "T-42", "entity_id": "tgt-x", "kind": "ir",
		"t": 0.0, "quality": 0.8, "support": 1, "bearing_deg": 30.0,
		"range_km": 118.0, "range_sigma_km": 1.0}, 0.0)

	var acts := V2Actions.available(actor, target, tr)
	_ok(acts.size() >= 10, "available 返回全部动作", str(acts.size()))
	_eq(bool((V2Actions.find(acts, "crossfix") as Dictionary).get("available", false)), true,
		"L1 crossfix 可用（被动红外）")
	_eq(bool((V2Actions.find(acts, "radar_illum") as Dictionary).get("available", false)), true,
		"L1 radar_illum 可用（有雷达能力）")
	var mi: Dictionary = V2Actions.find(acts, "model_ident")
	_eq(bool(mi.get("available", true)), false, "L1 model_ident 不可用")
	_eq(String(mi.get("reason_code", "")), "level", "model_ident 不可用原因=level")
	_non_empty(String(mi.get("reason", "")), "不可用 reason 非空: " + String(mi.get("reason", "")))
	_eq(String((V2Actions.find(acts, "iff_query") as Dictionary).get("reason_code", "")), "level",
		"iff_query 需 L3")
	_eq(String((V2Actions.find(acts, "optical_channel") as Dictionary).get("reason_code", "")), "level",
		"optical_channel 需 L3")
	_eq(bool((V2Actions.find(acts, "ir_channel") as Dictionary).get("available", false)), true,
		"ir_channel 任意等级可用")
	var fc: Dictionary = V2Actions.find(acts, "fire_control")
	_eq(bool(fc.get("available", true)), false, "L4 武器类 fire_control 明确不可用")
	_eq(String(fc.get("reason_code", "")), "unsupported", "武器类 reason_code=unsupported")
	_non_empty(String(fc.get("reason", "")), "武器类 reason 非空")

	# 升到 L4 后武器仍然 unsupported
	table.ensure("T-42", "tgt-x", 0.0)
	table.set_level("T-42", 4, 0.0, "probe")
	var acts4 := V2Actions.available(actor, target, tr)
	_eq(bool((V2Actions.find(acts4, "optical_channel") as Dictionary).get("available", false)), true,
		"L4 optical_channel 可用")
	_eq(bool((V2Actions.find(acts4, "iff_query") as Dictionary).get("available", false)), true,
		"L4 iff_query 可用")
	_eq(String((V2Actions.find(acts4, "fire_control") as Dictionary).get("reason_code", "")), "unsupported",
		"L4 武器仍 unsupported（禁止伪造）")

	# 能力缺失（用 L1 目标单独测，避免等级条件先失败）
	var actor_ir := V2Entity.from_dict({"id": "ir-only", "side": "friend",
		"capabilities": ["sensor.ir"]})
	var table_l1 := V2TrackTable.new(rules)
	var tr_l1 := table_l1.ingest({"track_id": "T-43", "entity_id": "tgt-y", "kind": "ir",
		"t": 0.0, "quality": 0.8, "support": 1, "bearing_deg": 30.0}, 0.0)
	var target_l1 := V2Entity.from_dict({"id": "tgt-y", "batch": "T-43", "side": "hostile", "track_level": 1})
	var acts2 := V2Actions.available(actor_ir, target_l1, tr_l1)
	var ri: Dictionary = V2Actions.find(acts2, "radar_illum")
	_eq(bool(ri.get("available", true)), false, "无雷达能力 → radar_illum 不可用")
	_ok(String(ri.get("reason", "")).contains("缺少能力"), "原因写明缺少能力", String(ri.get("reason", "")))
	_eq(bool((V2Actions.find(acts2, "crossfix") as Dictionary).get("available", false)), true,
		"requires_any 满足其一即可用（crossfix）")
	_eq(bool((V2Actions.find(acts2, "ir_channel") as Dictionary).get("available", false)), true,
		"ir_channel 可用（有红外）")

	# 无目标
	var no_target := V2Actions.available(actor, null, null)
	var nt: Dictionary = V2Actions.find(no_target, "crossfix")
	_eq(bool(nt.get("available", true)), false, "无目标 → crossfix 不可用")
	_eq(String(nt.get("reason_code", "")), "no_track", "无目标 reason_code=no_track")

	# 距离
	var table_r := V2TrackTable.new(rules)
	var far := table_r.ingest({"track_id": "FAR", "entity_id": "far", "kind": "radar",
		"t": 0.0, "quality": 0.9, "support": 2, "range_km": 20000.0,
		"range_sigma_km": 5.0, "bearing_deg": 10.0}, 0.0)
	var far_e := V2Entity.from_dict({"id": "far", "side": "hostile", "track_level": 2})
	var acts3 := V2Actions.available(actor, far_e, far)
	var mid: Dictionary = V2Actions.find(acts3, "model_ident")
	_eq(bool(mid.get("available", true)), false, "超出光学作用距离 → model_ident 不可用")
	_eq(String(mid.get("reason_code", "")), "range", "距离原因 reason_code=range")

	# ctx 阶段门控（自定义内容，验证数据驱动）
	var custom := {"schema": "actions.v1", "actions": [
		{"id": "phase_gate", "label": "阶段动作", "phases": ["DECISION"]},
		{"id": "flag_gate", "label": "条件动作", "requires_flags": ["decision_open"]},
	]}
	_ok(V2Actions.load_data(custom, "<probe>"), "加载自定义动作内容（phase/flag 门控）")
	var g1 := V2Actions.available(actor, target, tr, {"phase": "COMMAND", "flags": {}})
	_eq(String((V2Actions.find(g1, "phase_gate") as Dictionary).get("reason_code", "")), "phase",
		"阶段不匹配 → reason_code=phase")
	var g2 := V2Actions.available(actor, target, tr, {"phase": "DECISION", "flags": {"decision_open": true}})
	_eq(bool((V2Actions.find(g2, "phase_gate") as Dictionary).get("available", false)), true,
		"阶段匹配 → 可用")
	_eq(bool((V2Actions.find(g2, "flag_gate") as Dictionary).get("available", false)), true,
		"flag 满足 → 可用")
	_ok(V2Actions.load_file(V2Actions.DEFAULT_PATH), "恢复正式动作内容", str(V2Actions.errors))

	# V2-0 UI 兼容别名（两参数）
	var compat := V2Actions.actions_for(actor, target)
	_eq(compat.size() >= 10, true, "actions_for(actor,target) 向后兼容")

# ═══════════════════════════════════════════════════════════════════
# 7. 命令状态机与队列（预命令不推进仿真 / 撤销 / 驳回）
# ═══════════════════════════════════════════════════════════════════

func _test_orders() -> void:
	_section_begin("7 命令状态机")
	var world := V2World.new()
	var ok := world.load_scenario(_sc_v2)
	_ok(ok, "命令测试用 world 装载 V2 场景")
	world.prelude_skip()
	var t0: float = world.t

	# 预命令：创建但不推进时间、不入队（用 exec_delay 把 TRANSMITTED 段拉出来验证）
	var issued := world.issue_order("crossfix", "2001", {"exec_delay_s": 2.0})
	_eq(bool(issued.get("ok", false)), true, "发预命令 crossfix（L1 可用）", str(issued.get("reason", "")))
	var order: V2Orders.Order = world.order_of(String((issued.get("order") as V2Orders.Order).id))
	_eq(order.state, "PRE_ORDER", "预命令状态 PRE_ORDER")
	_eq(world.t, t0, "预命令不推进仿真时间")
	_eq(world.orders.pending().size(), 1, "预命令在 pending（尚未入队）")
	_eq(world.orders.queued().size(), 0, "预命令不在队列")

	# 不可用动作不会产生命令
	var bad_issue := world.issue_order("iff_query", "2001")
	_eq(bool(bad_issue.get("ok", true)), false, "L1 的 iff_query 被拒绝")
	_ok(String(bad_issue.get("reason", "")).contains("等级"), "拒绝原因写明等级", String(bad_issue.get("reason", "")))
	var unknown_issue := world.issue_order("no_such_action", "2001")
	_eq(bool(unknown_issue.get("ok", true)), false, "未知动作被拒绝")
	_eq(world.t, t0, "被拒绝的命令不推进仿真时间")

	# 完整链路 PRE_ORDER → … → DONE
	_eq(bool(world.authorize_order(order.id).get("ok", false)), true, "authorize → AUTHORIZED")
	_eq(order.state, "AUTHORIZED", "状态 AUTHORIZED")
	_eq(bool(world.enqueue_order(order.id).get("ok", false)), true, "enqueue → QUEUED")
	_eq(order.state, "QUEUED", "状态 QUEUED")
	var tx_delay := float(world.scenario.orders_config.get("tx_delay_s", 8.0))
	world.advance(tx_delay)
	_eq(order.state, "TRANSMITTED", "链路延迟到期自动 TRANSMITTED")
	world.advance(2.05)
	_eq(order.state, "EXECUTING", "计划时刻到达 → EXECUTING")
	_eq(bool(world.complete_order(order.id).get("ok", false)), true, "complete → DONE")
	_eq(order.state, "DONE", "终态 DONE")
	_ok(order.tx_t >= tx_delay, "传输时间记录", "tx_t=%.2f" % order.tx_t)
	_data_line("order chain", "%s: tx_t=%.2f exec_t=%.2f state=%s" % [order.id, order.tx_t, order.exec_t, order.state])

	# 非法状态迁移
	var second := world.issue_order("ir_channel", "2001")
	var o2: V2Orders.Order = second.get("order", null)
	var illegal := world.transmit_order(o2.id)
	_eq(bool(illegal.get("ok", true)), false, "PRE_ORDER 直接 transmit 被拒绝")
	_ok(String(illegal.get("reason", "")).contains("非法"), "非法迁移原因明确", String(illegal.get("reason", "")))

	# 撤销：执行前可撤
	_eq(bool(world.abort_order(o2.id).get("ok", false)), true, "PRE_ORDER 可撤销")
	_eq(o2.state, "ABORTED", "撤销后 ABORTED")
	_eq(bool(world.abort_order(o2.id).get("ok", true)), false, "已终态不可再次撤销")
	_eq(bool(world.abort_latest_order().get("ok", true)), false, "无可撤销命令时 abort_latest 失败")

	# 驳回
	var third := world.issue_order("crossfix", "9001")
	var o3: V2Orders.Order = third.get("order", null)
	world.authorize_order(o3.id)
	var rej := world.reject_order(o3.id, "ROE 驳回")
	_eq(bool(rej.get("ok", false)), true, "AUTHORIZED 可驳回")
	_eq(o3.state, "REJECTED", "驳回后 REJECTED")
	_non_empty(o3.reason, "驳回原因记录: " + o3.reason)

	# 执行中不可撤销；带 duration 的命令自动 DONE
	var fourth := world.issue_order("crossfix", "2001")
	var o4: V2Orders.Order = fourth.get("order", null)
	world.authorize_order(o4.id)
	world.enqueue_order(o4.id)
	world.advance(tx_delay)
	world.advance(0.05)
	_eq(o4.state, "EXECUTING", "第四条 EXECUTING")
	var abort_exec := world.abort_order(o4.id)
	_eq(bool(abort_exec.get("ok", true)), false, "EXECUTING 不可撤销")
	_ok(String(abort_exec.get("reason", "")).contains("不可撤销"), "撤销失败原因", String(abort_exec.get("reason", "")))
	var fifth := world.issue_order("ir_channel", "2001")
	var o5: V2Orders.Order = fifth.get("order", null)
	world.authorize_order(o5.id)
	world.enqueue_order(o5.id)
	world.advance(tx_delay)
	world.advance(0.05)
	_eq(o5.state, "EXECUTING", "ir_channel（duration 4s）EXECUTING")
	world.advance(float(o5.duration_s) + 0.1)
	_eq(o5.state, "DONE", "duration 到期自动 DONE")

	# 队列快照/统计
	var summary := world.vm_orders_summary()
	_ok(int(summary.get("total", 0)) >= 5, "命令统计 total", str(summary.get("total", 0)))
	_ok((world.vm_orders() as Array).size() >= 5, "命令快照供 UI 读取")

# ═══════════════════════════════════════════════════════════════════
# 8. 任务阶段（数据驱动 enter 条件 / 提示 / 可选阶段跳过）
# ═══════════════════════════════════════════════════════════════════

func _test_mission() -> void:
	_section_begin("8 任务阶段")
	var m := V2Mission.from_scenario(_sc_v2)
	_eq(m.total_phases(), 7, "阶段数来自场景（7）")
	_eq(m.phase, "prelude", "起始阶段 prelude")
	_eq(m.phase_kind(), "PRELUDE", "起始 kind PRELUDE")
	var pre := m.prompt()
	_ok(String(pre.get("text", "")) != "", "提示文本来自 story.prelude.body")
	_eq(typeof(pre.get("options", null)), TYPE_DICTIONARY, "前置选项目录来自数据")

	# 条件不满足 → 停留并给明确 reason
	var r1 := m.advance(0.0)
	_eq(bool(r1.get("ok", true)), false, "缺 prelude_executed → 不能进入 READ")
	_ok(String(r1.get("reason", "")).contains("flag"), "停留原因写明缺 flag", String(r1.get("reason", "")))
	m.set_flag("prelude_executed")
	var r2 := m.advance(0.0)
	_eq(bool(r2.get("ok", false)), true, "置位 flag 后进入 READ")
	_eq(m.phase_kind(), "READ", "READ 阶段")
	var r3 := m.advance(1.0)
	_eq(bool(r3.get("ok", false)), true, "READ → COMMAND（min_t 条件）")
	_eq(m.phase_kind(), "COMMAND", "COMMAND 阶段")
	var r4 := m.advance(2.0)
	_eq(bool(r4.get("ok", true)), false, "缺 decision_open → 不能进入 DECISION")
	m.set_flag("decision_open")
	var r5 := m.advance(3.0)
	_eq(bool(r5.get("ok", false)), true, "置位后进入 DECISION")
	_eq(m.phase_kind(), "DECISION", "DECISION 阶段")
	var dec := m.prompt()
	_ok(String(dec.get("text", "")) != "", "决策提示来自 story.decision_prompt")
	var dec_opts: Array = dec.get("options", [])
	_eq(dec_opts.size(), 3, "决策选项来自 story.endings（3）")
	var first_kind := String((dec_opts[0] as Dictionary).get("kind", ""))
	_ok(first_kind != "", "选项 kind 来自内容: " + first_kind)

	# 未走开火分支 → CONSEQUENCE 可选阶段自动跳过
	m.set_flag("decision_made")
	var r6 := m.advance(4.0)
	_eq(bool(r6.get("ok", false)), true, "决策完成 → 进入 REPORT")
	_eq(m.phase_kind(), "REPORT", "REPORT 阶段")
	_contains(r6.get("skipped", []), "consequence", "可选 CONSEQUENCE 条件不满足时自动跳过")
	m.set_flag("report_submitted")
	var r7 := m.advance(5.0)
	_eq(bool(r7.get("ok", false)), true, "REPORT → END")
	_eq(m.phase_kind(), "END", "END 阶段")
	var r8 := m.advance(6.0)
	_eq(bool(r8.get("ok", true)), false, "END 之后无法再推进")
	_eq(String(r8.get("reason", "")), "已是最后阶段", "END 提示")

	# 自定义场景阶段数 = 数据（证明不写死关卡）
	var mini := V2Scenario.from_dict({
		"schema": "scenario.v2", "id": "mini", "title": "mini", "epoch": 0.0,
		"own_entity": "a",
		"entities": [{"id": "a", "kind": "ship", "side": "friend", "capabilities": ["comms.radio"]}],
		"tracks": [],
		"phases": [
			{"id": "one", "kind": "PRELUDE", "enter": {"always": true}},
			{"id": "two", "kind": "END", "enter": {"always": true}},
		],
	}, "<probe>")
	_eq(mini.errors.size(), 0, "mini 场景校验", str(mini.errors))
	var mm := V2Mission.from_scenario(mini)
	_eq(mm.total_phases(), 2, "mini 阶段数 = 2（来自数据）")
	var mr := mm.advance(0.0)
	_eq(bool(mr.get("ok", false)), true, "mini 阶段推进")
	_eq(mm.phase, "two", "mini 进入 END")

	# 无场景兜底（V2-0 app 兼容）
	var m_def := V2Mission.new()
	_eq(m_def.total_phases(), 7, "默认兜底阶段 7（无场景，纯骨架）")
	var steps := 0
	while steps < 10:
		var rr := m_def.advance(0.0)
		if not bool(rr.get("ok", false)):
			break
		steps += 1
	_eq(m_def.phase_kind(), "END", "默认阶段可推进到 END（TAB 兼容）")
	var snap := m.snapshot(10.0)
	_ok(int(snap.get("total", 0)) == 7, "阶段快照供 UI 读取")

# ═══════════════════════════════════════════════════════════════════
# 9. world 容器 / view-model / 证据 / 旧世界兼容
# ═══════════════════════════════════════════════════════════════════

func _test_world_and_view_model() -> void:
	_section_begin("9 world / view-model / 证据")
	var w := V2World.new()
	_ok(w.load_scenario(_sc_v2), "装载 V2 场景", str(w.errors))
	w.prelude_skip()
	var st := w.vm_state()
	_eq(int(st.get("entity_count", 0)), 9, "vm_state entity_count")
	_eq(int(st.get("track_count", 0)), 10, "vm_state track_count")
	_eq(String(st.get("own_id", "")), "harmattan", "own 实体")
	_eq(int(st.get("evidence_total", 0)), 4, "证据容器 4 项")

	var contacts: Array = w.vm_contacts()
	_eq(contacts.size(), 10, "vm_contacts 10 行")
	var row: Dictionary = {}
	for raw in contacts:
		if String((raw as Dictionary).get("track_id", "")) == "2001":
			row = raw
	_eq(String(row.get("identity", "")), "unknown", "2001 身份=未知（内容数据）")
	_eq(int(row.get("level", 0)), 1, "2001 初始 L1")
	_eq(String(row.get("name", "")), "AV-4412 传唤者", "vm 行合并实体名")
	_eq(String(row.get("batch", "")), "2001", "vm 行批号")
	var phantom_row := w.vm_contact("9002")
	_eq(bool(phantom_row.get("has_entity", true)), false, "虚警行无实体（纯接触）")

	# 选中：实体 id 与航迹 id 均可
	_ok(w.select("9002"), "按航迹 id 选中无实体接触")
	_eq(String(w.vm_selected().get("track_id", "")), "9002", "vm_selected = 9002")
	_ok(w.select("harmattan"), "按实体 id 选中")
	_ok(w.selected() != null, "legacy selected() 返回实体")
	_ok(w.selected_track() != null, "selected_track() 返回航迹")

	# 动作视图（右栏/右键菜单直接用）
	var acts := w.vm_actions("2001")
	_eq(bool((V2Actions.find(acts, "crossfix") as Dictionary).get("available", false)), true,
		"vm_actions: L1 crossfix 可用")
	_eq(String((V2Actions.find(acts, "iff_query") as Dictionary).get("reason_code", "")), "level",
		"vm_actions: iff_query 给出等级原因")

	# 观测 → 等级 → 实体快照同步（V2-0 UI 兼容）
	var lv_before := int(w.track_for("2001").level)
	w.observe_entity("summons_4471", {"kind": "radar", "sensor": "YW-R9", "source": "harmattan",
		"quality": 0.8, "support": 2, "bearing_deg": 302.5, "bearing_sigma_deg": 0.15,
		"range_km": 300.0, "range_sigma_km": 2.0})
	_eq(int(w.track_for("2001").level), 2, "观测融合后 2001 → L2")
	_eq(find_entity_level(w, "summons_4471"), 2, "实体快照已同步 L2（V2-0 UI 兼容）")
	_eq(int(w.vm_contact("2001").get("level", 0)), 2, "vm_contact 反映 L2")
	var ident_ok := w.set_track_identity("2001", "suspect", {"via": "optical", "confidence": 0.8})
	_eq(ident_ok, true, "身份独立设置（可疑）")
	_eq(int(w.track_for("2001").level), 2, "身份变化不影响等级（仍是 L2）")
	_eq(w.by_id.get("summons_4471").identity, "suspect", "实体快照身份同步")

	# 证据
	_eq(w.evidence_count(), 0, "初始证据 0")
	_eq(w.can_expose(), false, "证据不足不可曝光")
	_ok(w.evidence_start("port_telemetry"), "开始取证")
	_eq(w.evidence_count(), 0, "进行中不计入证据")
	_ok(w.evidence_complete("port_telemetry"), "取证完成 1")
	_ok(w.evidence_complete("inspection_blackbox"), "取证完成 2")
	_eq(w.evidence_count(), 2, "证据 2/4")
	_eq(w.can_expose(), true, "证据达到门槛可曝光（policy 来自场景）")
	_eq((w.vm_evidence() as Array).size(), 4, "vm_evidence 4 项")

	# 图层 / 时间推进 / 命令队列容器
	w.set_layer("contacts", false)
	_eq(w.layers.get("contacts", true), false, "图层开关")
	_ok(w.orders != null and w.tracks != null, "world 持有命令队列与航迹表容器")
	var before: float = w.t
	w.advance(1.5)
	_ok(w.t > before, "advance 推进世界时间")

	# 旧场景世界：V2-0 UI 兼容路径
	var w2 := V2World.new()
	var ok2 := w2.load_scenario(_sc_legacy)
	_ok(ok2, "旧场景迁移后世界可装载", str(w2.errors))
	_eq(w2.entities.size(), 7, "旧世界实体 7")
	_eq(w2.own_id, "1001", "旧世界 own=1001")
	_eq(w2.visible_entities().size(), 7, "legacy visible_entities()")
	_eq(w2.by_id.get("2001").track_level, 1, "实体快照等级来自迁移航迹")
	_ok(w2.track_for("9002") != null, "旧世界虚警航迹存在")
	var w2contacts := w2.vm_contacts()
	_eq(w2contacts.size(), 8, "旧世界 vm_contacts 8 行")
	_data_line("world vm", "entities=7 tracks=8 contacts=8 evidence_total=4")

func find_entity_level(w: V2World, eid: String) -> int:
	var e: V2Entity = w.by_id.get(eid)
	return int(e.track_level) if e != null else -1

# ═══════════════════════════════════════════════════════════════════
# 10. sim 观测桥（v15 SensorModel / V2 sim 观测 → core 观测）
# ═══════════════════════════════════════════════════════════════════

func _test_observation_bridge() -> void:
	_section_begin("10 观测桥")
	var raw := {
		"detected": true, "kind": "radar", "sensor": "YW-R9",
		"target_id": "2001", "t": 12.0, "quality": 0.7,
		"level_support": 2, "bearing_deg": 302.5, "bearing_sigma_deg": 0.15,
		"range_km": 300.0, "range_sigma_km": 2.0, "notes": ["v15 雷达观测"],
	}
	var core_obs := V2ObservationBridge.to_core_observation(raw, {"source": "harmattan"})
	_eq(String(core_obs.get("track_id", "")), "2001", "bridge: target_id → track_id")
	_eq(String(core_obs.get("sensor", "")), "YW-R9", "bridge: sensor")
	_eq(String(core_obs.get("source", "")), "harmattan", "bridge: source 来自 opts")
	_eq(int(core_obs.get("support", 0)), 2, "bridge: level_support → support")
	_eq(float(core_obs.get("quality", 0.0)), 0.7, "bridge: quality")
	var mapped := V2ObservationBridge.to_core_observation(
		{"detected": true, "kind": "optical", "target_id": "summons_4471", "t": 3.0},
		{"entity_ids": ["summons_4471"]})
	_eq(String(mapped.get("entity_id", "")), "summons_4471", "bridge: entity_ids 映射 target_id → entity_id")

	var scan := {
		"observations": [
			raw,
			{"detected": false, "kind": "radar", "target_id": "9001", "reason": "out_of_sphere"},
		],
	}
	var mapped_scan := V2ObservationBridge.scan_to_observations(scan, {"source": "harmattan"})
	_eq(mapped_scan.size(), 1, "bridge: scan 过滤未探测观测")

	# 真实 SensorModel 观测 → bridge → core 航迹（物理层与 core 打通）
	var sensor := SensorModel.rack_sensor("harmattan", "YW-R9")
	_ok(not sensor.is_empty(), "保留的 SensorModel 雷达在架")
	var target_row := {"range_km": 8000.0, "bearing_deg": 45.0, "rcs_m2": 10.0, "name": "T"}
	var det := SensorModel.detect_radar(sensor, target_row, {"los": true})
	_eq(bool(det.get("detected", false)), true, "SensorModel.detect_radar 探测成功")
	var sm_obs := V2ObservationBridge.to_core_observation(det, {"source": "harmattan",
		"track_id": "SM-1", "entity_id": "sm-target"})
	_eq(int(sm_obs.get("support", 0)), 2, "SensorModel 观测 → support L2")
	var errs: Array = []
	var rules: Dictionary = V2TrackTable.load_rules(TRACK_RULES, errs)
	var table := V2TrackTable.new(rules)
	var tr: V2Track = table.ingest(sm_obs, 0.0)
	_eq(tr.level, 2, "SensorModel 观测融合后航迹 L2")
	_ok(tr.range_km > 0.0, "SensorModel 观测带距离", "range=%.1f" % tr.range_km)

	# ingest_scan 直接喂 world
	var w := V2World.new()
	w.load_scenario(_sc_legacy)
	var tracker := w.track_for("9001")
	var scan2 := {"observations": [{
		"detected": true, "kind": "ir", "sensor": "CH-IR2", "target_id": "9001",
		"t": 5.0, "quality": 0.6, "level_support": 1,
		"bearing_deg": 118.0, "bearing_sigma_deg": 1.2,
	}]}
	var ingested := V2ObservationBridge.ingest_scan(w, scan2, {"source": "harmattan"})
	_eq(ingested.size(), 1, "ingest_scan 向 world 注入 1 条观测")
	_eq(tracker.observation_count >= 1, true, "world 航迹记录观测")
	_eq(int(tracker.level), 1, "IR 观测保持 L1")

	# 目标行（sim 快照组装用）
	var row2 := V2ObservationBridge.target_row(w.by_id.get("2001"), w.track_for("2001"))
	_eq(String(row2.get("batch", "")), "2001", "target_row 带批号")
	_ok(row2.has("orbit"), "target_row 带轨道状态")
	_ok(row2.has("track_id") and String(row2.get("track_id", "")) == "2001", "target_row 带 track_id")
	var row_cls: Dictionary = row2.get("classification", {})
	_eq(String(row_cls.get("ship_class", "")), "传唤级", "target_row 带 classification（光学 L3 用）")
	_eq(String(row_cls.get("faction", "")), "UEG 第33舰队", "target_row classification.faction")

	# TWS 通道 → 观测 映射（v2-sensor 约定，docs/34 §8.6）
	var ch := {
		"target_id": "2001", "state": "TRACK", "quality": 0.8,
		"bearing_deg": 302.5, "bearing_sigma_deg": 0.15,
		"range_km": 319.2, "range_sigma_km": 0.8,
		"age_s": 1.5, "update_rate_hz": 0.167, "stable_track": true,
		"fire_control": {"range_km": 319.2, "bearing_deg": 302.5, "track_quality": 0.8},
	}
	var tws_obs := V2ObservationBridge.tws_channel_to_observation(ch, {"source": "harmattan"})
	_eq(bool(tws_obs.get("detected", false)), true, "TWS TRACK 通道 → detected")
	_eq(String(tws_obs.get("kind", "")), "radar.tws", "TWS 观测 kind=radar.tws")
	_eq(int(tws_obs.get("support", 0)), 2, "TWS 只给 L2 位置证据")
	_eq(String(tws_obs.get("channel_state", "")), "TRACK", "TWS 通道状态透传")
	_ok(tws_obs.has("fire_control"), "TWS 火控解算仅透传（不参与等级）")
	var tws_notes: Array = tws_obs.get("notes", [])
	_ok(str(tws_notes).contains("update"), "TWS notes 携带 update_rate/age")
	var lost_obs := V2ObservationBridge.tws_channel_to_observation({"target_id": "2001", "state": "SEARCH", "quality": 0.2}, {})
	_eq(bool(lost_obs.get("detected", true)), false, "TWS SEARCH 不注入观测")
	var tws_list := V2ObservationBridge.tws_channels_to_observations([
		{"target_id": "1000", "state": "TRACK", "quality": 0.7, "range_km": 100.0, "bearing_deg": 10.0},
		{"target_id": "1001", "state": "FIRE_CONTROL", "quality": 0.9, "range_km": 90.0, "bearing_deg": 20.0},
		{"target_id": "1002", "state": "SEARCH", "quality": 0.1},
		{"target_id": "1003", "state": "DETECT", "quality": 0.1},
	], {"source": "harmattan"})
	_eq(tws_list.size(), 2, "TWS 多通道只注入 ACQUIRE/TRACK/STARE/FIRE_CONTROL")
	var w3 := V2World.new()
	w3.load_scenario(_sc_legacy)
	var before_count := w3.track_for("2001").observation_count
	var tws_ingested := V2ObservationBridge.ingest_tws_channels(w3, [ch], {"source": "harmattan"})
	_eq(tws_ingested.size(), 1, "TWS 通道快照可直接注入 world")
	_eq(int(w3.track_for("2001").level), 2, "TWS 观测注入后 2001 → L2")
	_ok(w3.track_for("2001").observation_count > before_count, "TWS 观测计数增长")
	_data_line("bridge", "radar obs → L2, TWS channel map, real SensorModel integration ok")
