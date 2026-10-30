extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R2-DAMAGE-2 headless probe：完整损管模型接入 V17 world
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/damage_integration_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const ScenarioScript := preload("res://framework/core/scenario.gd")
const WorldScript := preload("res://framework/core/world.gd")
const EntityScript := preload("res://framework/core/entity.gd")
const BridgeScript := preload("res://scripts/framework_bridge.gd")
const DAMAGE_CONTENT_PATH := "res://framework/content/damage_l1.json"
const UNREGISTERED_FIXTURE := "res://tests/fixtures/damage_profile/unregistered_entity.json"
const LEGACY_IDS := ["sensor_cal", "ir_false_alarm", "thermal"]
const SECTION_IDS := ["hull", "power", "propulsion", "sensors", "comms", "tanks", "docking"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R2-DAMAGE-2 PROBE · 完整损管模型接入 V17 world")
	print("════════════════════════════════════════════════════════════")
	_test_world_init()
	_test_legacy_compat()
	_test_full_vm()
	_test_hit_and_advance()
	_test_repair_api()
	_test_legacy_repair_still_works()
	_test_entities_and_lazy()
	_test_hud_reads_and_json()
	_test_bridge_compat()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("DAMAGE INTEGRATION PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("DAMAGE INTEGRATION PROBE FAILED")
		quit(1)
	else:
		print("DAMAGE INTEGRATION PROBE OK")
		quit(0)

# ── 工具 ─────────────────────────────────────────────────────────

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

func _near(actual: float, expected: float, tol: float, label: String) -> void:
	var diff := absf(actual - expected)
	_ok(diff <= tol, label, "actual=%.6f expected=%.6f diff=%.6f" % [actual, expected, diff])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _inject_unregistered(w) -> void:
	# H01：真实未注册 fixture；不在 ShipCatalog/damage_l1/damage_profiles 中。
	var f := FileAccess.open(UNREGISTERED_FIXTURE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var spec: Dictionary = (parsed as Dictionary).get("entity", {})
	if spec.is_empty():
		return
	var e = EntityScript.from_dict(spec)
	if e == null:
		return
	if not w.by_id.has(e.id):
		w.by_id[e.id] = e
		w.entities.append(e)

func _make_world():
	var sc = ScenarioScript.load_file("res://framework/content/scenario_l1_v2.json")
	_ok(sc.errors.is_empty(), "场景解析无错误", str(sc.errors))
	var w = WorldScript.new()
	var ok: bool = w.load_scenario(sc)
	_ok(ok, "world.load_scenario", str(w.errors))
	if bool(w.prelude.get("open", false)) and not bool(w.prelude.get("executed", false)):
		w.prelude_skip()
	_inject_unregistered(w)
	_ok(w.by_id.has("unregistered_hulk"), "未注册 fixture 已注入")
	return w

func _entity(w, eid: String):
	return w.by_id.get(eid)

func _full(w, eid := "harmattan") -> Dictionary:
	return w.vm_damage_full(eid)

func _full_section(w, sid: String, eid := "harmattan") -> Dictionary:
	var full: Dictionary = _full(w, eid)
	for raw in (full.get("sections", []) as Array):
		if String((raw as Dictionary).get("id", "")) == sid:
			return raw
	return {}

func _has_full_event(w, type_name: String, eid := "harmattan") -> bool:
	var full: Dictionary = _full(w, eid)
	for raw in (full.get("events", []) as Array):
		if String((raw as Dictionary).get("type", "")) == type_name:
			return true
	return false

# ═══════════════════════════════════════════════════════════════════
# 1. world 初始化：实体带完整损管模型
# ═══════════════════════════════════════════════════════════════════

func _test_world_init() -> void:
	_section_begin("1 world 初始化")
	_ok(FileAccess.file_exists(DAMAGE_CONTENT_PATH), "损管内容文件存在")
	var w = _make_world()
	_ok(not w.damage_content.is_empty(), "world 已装载 damage_l1.json",
		String(w.damage_content.get("id", "")))
	_eq(String(w.damage_content.get("schema", "")), "damage.v1", "内容 schema=damage.v1")
	_ok(w.entities.size() >= 9, "实体数 ≥9", str(w.entities.size()))
	# 本舰/敌舰有模型；其他舰无（可选/默认空）
	var own = _entity(w, "harmattan")
	var enemy = _entity(w, "summons_4471")
	_ok(own != null and own.damage != null, "harmattan.damage 已初始化")
	_ok(enemy != null and enemy.damage != null, "summons_4471.damage 已初始化")
	_ok(own.has_damage_model(), "entity.has_damage_model()")
	_ok(w.damage_model_for("harmattan") != null, "world.damage_model_for(harmattan)")
	_ok(w.damage_model_for("summons_4471") != null, "world.damage_model_for(summons_4471)")
	# FERRY=HEMATITE 已有档案（damage_l1+damage_profiles）；缺档案负例改用未注册 fixture。
	var ferry = _entity(w, "ferry")
	_ok(ferry.damage != null, "ferry.damage 已按 HEMATITE 档案初始化")
	_ok(w.damage_model_for("ferry") != null, "world.damage_model_for(ferry)")
	var hulk = _entity(w, "unregistered_hulk")
	_ok(hulk != null and hulk.damage == null, "未注册 fixture 默认 null（缺档案）")
	_ok(w.damage_model_for("unregistered_hulk") == null,
		"world.damage_model_for(unregistered_hulk)=null")
	var own_full: Dictionary = w.vm_damage_full("harmattan")
	_eq((own_full.get("sections", []) as Array).size(), 7, "本舰完整模型 7 分区")
	var ids: Array = []
	for raw in (own_full.get("sections", []) as Array):
		ids.append(String((raw as Dictionary).get("id", "")))
	_eq(ids, SECTION_IDS, "完整模型分区 id 与规范一致")
	_eq(int((own_full.get("summary", {}) as Dictionary).get("total", 0)), 7, "完整 summary.total=7")
	_ok((w.events as Array).size() > 0, "world 统一日志非空（装载记录）")
	_data_line("init", "entities=%d · damaged_models=harmattan+summons_4471 · full sections=7" % w.entities.size())

# ═══════════════════════════════════════════════════════════════════
# 2. 旧字段兼容（bridge probe / V17 HUD 现有契约）
# ═══════════════════════════════════════════════════════════════════

func _test_legacy_compat() -> void:
	_section_begin("2 旧字段兼容")
	var w = _make_world()
	var vm: Dictionary = w.vm_damage()
	# 旧字段全部保留
	for key in ["entity_id", "entity_name", "sections", "queue", "repair_rate_s", "summary"]:
		_ok(vm.has(key), "vm_damage 保留旧字段: " + key)
	_eq(String(vm.get("entity_id", "")), "harmattan", "entity_id=harmattan")
	var sections: Array = vm.get("sections", [])
	_eq(sections.size(), 3, "旧 sections 仍为 3 项（bridge probe 契约）")
	var ids: Array = []
	for raw in sections:
		ids.append(String((raw as Dictionary).get("id", "")))
	_eq(ids, LEGACY_IDS, "旧 sections id 顺序不变")
	_eq(int((vm.get("summary", {}) as Dictionary).get("total", 0)), 3, "旧 summary.total=3")
	_eq(int((vm.get("summary", {}) as Dictionary).get("damaged", 0)), 1, "旧 summary.damaged=1")
	_eq(int((vm.get("summary", {}) as Dictionary).get("degraded", 0)), 2, "旧 summary.degraded=2")
	_ok(vm.get("queue") is Array, "旧 queue 为 Array")
	_near(float(vm.get("repair_rate_s", 0.0)), 120.0, 1.0e-9, "旧 repair_rate_s=120")
	# 新增别名与完整模型字段
	_ok(vm.has("damage_sections"), "兼容别名 damage_sections")
	_ok(vm.has("damage_queue"), "兼容别名 damage_queue")
	_eq((vm.get("damage_sections", []) as Array).size(), 3, "damage_sections 3 项")
	_eq(bool(vm.get("has_full_model", false)), true, "has_full_model=true")
	var model: Dictionary = vm.get("model", {})
	_ok(not model.is_empty(), "model 非空（完整模型 vm）")
	_eq((model.get("sections", []) as Array).size(), 7, "model.sections=7")
	for key in ["events", "resources", "summary_full", "effects", "units"]:
		_ok(vm.has(key), "vm_damage 增完整字段: " + key)
	_data_line("legacy", "sections=3（sensor_cal/ir_false_alarm/thermal）· summary.total=3 · 兼容别名齐全")

# ═══════════════════════════════════════════════════════════════════
# 3. 完整模型 vm 字段
# ═══════════════════════════════════════════════════════════════════

func _test_full_vm() -> void:
	_section_begin("3 完整模型 vm")
	var w = _make_world()
	var full: Dictionary = w.vm_damage_full("harmattan")
	for key in ["schema", "model", "entity_id", "sections", "events", "queue", "resources",
			"summary", "effects", "units", "note"]:
		_ok(full.has(key), "full vm 含字段: " + key)
	_eq(String(full.get("schema", "")), "damage.v1", "full schema")
	_eq(String(full.get("model", "")), "V2DamageModel", "full model=V2DamageModel")
	_eq(String(full.get("entity_id", "")), "harmattan", "full entity_id")
	var eff: Dictionary = full.get("effects", {})
	for key in ["power", "sensors", "comms", "propulsion", "docking", "fire", "decompression",
			"unpowered_sections"]:
		_ok(eff.has(key), "full effects 含: " + key)
	var res: Dictionary = full.get("resources", {})
	for key in ["teams_total", "teams_busy", "spares", "power", "power_max", "personnel"]:
		_ok(res.has(key), "full resources 含: " + key)
	_ok((full.get("events", []) as Array).size() >= 0, "full events 为 Array")
	var enemy_full: Dictionary = w.vm_damage_full("summons_4471")
	_eq((enemy_full.get("sections", []) as Array).size(), 7, "敌舰完整模型 7 分区")
	_ok(not w.vm_damage_full("unregistered_hulk").size() > 0,
		"未注册 fixture vm_damage_full 为空")
	_data_line("full-vm", "schema/model/entity/sections=7/events/queue/resources/summary/effects/units/note")

# ═══════════════════════════════════════════════════════════════════
# 4. 伤害输入 + await advance + 统一事件日志
# ═══════════════════════════════════════════════════════════════════

func _test_hit_and_advance() -> void:
	_section_begin("4 伤害/advance/事件")
	var w = _make_world()
	var legacy_before: Dictionary = w.vm_damage()
	var r: Dictionary = w.damage_apply_hit("sensors", 0.5, 0.5, "fore", "probe")
	_eq(bool(r.get("ok", false)), true, "world.damage_apply_hit 成功")
	_ok(_has_full_event(w, "hit", "harmattan"), "完整模型记录 hit 事件")
	_ok(float(_full_section(w, "sensors").get("integrity", 1.0)) < 1.0,
		"完整模型 sensors 完整度下降")
	_eq(_full_section(w, "sensors").get("state", ""), "damaged", "完整模型 sensors=damaged")
	# 旧字段不受影响（独立投影）
	var legacy_after: Dictionary = w.vm_damage()
	_eq((legacy_after.get("sections", []) as Array).size(), 3, "旧 sections 仍 3 项")
	_eq(_legacy_id_list(legacy_after), _legacy_id_list(legacy_before), "旧字段内容不变")
	_ok(not w.damage_events_log.is_empty(), "统一损管事件日志非空")
	_ok(w.damage_events(8).size() > 0, "damage_events(limit) 可读")
	var first_event: Dictionary = w.damage_events(1)[0]
	_ok(first_event.has("entity_id"), "统一事件含 entity_id")
	_eq(String(first_event.get("entity_id", "")), "harmattan", "事件 entity_id=harmattan")
	# advance 推进完整模型 + out 返回 damage_events
	var out: Dictionary = w.advance(2.0)
	_ok(out.has("damage_events"), "advance 返回 damage_events")
	_ok(out.has("damage"), "advance 保留旧 damage 返回")
	_ok(float(_full(w).get("t", 0.0)) > 0.0, "advance 推进完整模型 t")
	# 火灾 + advance 蔓延/事件
	w.damage_apply_hit("tanks", 0.6, 0.5, "aft", "probe")
	var fire_hits := 0
	var advance_events := 0
	for i in range(20):
		var adv: Dictionary = w.advance(1.0)
		if adv.has("damage_events"):
			advance_events += (adv.get("damage_events", []) as Array).size()
	for raw in (w.vm_damage_full("harmattan").get("events", []) as Array):
		if String((raw as Dictionary).get("type", "")) in ["fire", "fire_spread"]:
			fire_hits += 1
	_ok(fire_hits > 0, "完整模型有火灾事件", str(fire_hits))
	_ok(advance_events > 0, "advance 期间产生完整模型事件", str(advance_events))
	var sum: Dictionary = w.vm_damage_full("harmattan").get("summary", {})
	_ok(int(sum.get("on_fire", 0)) >= 0, "summary.on_fire 可读")
	var damage_logs := 0
	for ev in w.events:
		if String((ev as Dictionary).get("kind", "")) == "damage":
			damage_logs += 1
	_ok(damage_logs > 0, "world 统一日志含 damage 事件", str(damage_logs))
	_data_line("hit/advance", "hit→full model damaged；advance 推进；统一事件日志 entity_id=harmattan")

func _legacy_id_list(vm: Dictionary) -> Array:
	var ids: Array = []
	for raw in (vm.get("sections", []) as Array):
		ids.append(String((raw as Dictionary).get("id", "")))
	return ids

# ═══════════════════════════════════════════════════════════════════
# 5. 损管 API 转发
# ═══════════════════════════════════════════════════════════════════

func _test_repair_api() -> void:
	_section_begin("5 损管 API 转发")
	var w = _make_world()
	w.damage_apply_hit("sensors", 0.5, 0.5, "fore", "probe")
	w.damage_apply_hit("comms", 0.15, 0.0, "fore", "probe")
	var a: Dictionary = w.damage_assign_repair("sensors", 3)
	_eq(bool(a.get("ok", false)), true, "damage_assign_repair(sensors,3)")
	var b: Dictionary = w.damage_assign_repair("comms", 1)
	_eq(bool(b.get("ok", false)), true, "damage_assign_repair(comms,1)")
	var queue: Array = w.vm_damage_full().get("queue", [])
	_eq(queue.size(), 2, "完整模型 queue=2")
	_eq(String((queue[0] as Dictionary).get("section", "")), "comms", "队列按优先级：comms 先")
	var pr: Dictionary = w.damage_set_priority("sensors", 1)
	_eq(bool(pr.get("ok", false)), true, "damage_set_priority(sensors,1)")
	_eq(String((w.vm_damage_full().get("queue", []) as Array)[0].get("section", "")), "sensors",
		"同优先级按入队顺序：sensors 先")
	var cancel: Dictionary = w.damage_cancel_repair("comms")
	_eq(bool(cancel.get("ok", false)), true, "damage_cancel_repair(comms)")
	_eq((w.vm_damage_full().get("queue", []) as Array).size(), 1, "取消后 queue=1")
	# 推进完成修复（传感器 70s；火灾/失压已由压制逻辑处理）
	for i in range(120):
		w.advance(1.0)
	var sec := _full_section(w, "sensors")
	_near(float(sec.get("integrity", 0.0)), 1.0, 1.0e-9, "修复后 sensors integrity=1.0")
	_eq(String(sec.get("state", "")), "nominal", "修复后 sensors=nominal")
	_data_line("repair-api", "assign/set_priority/cancel 转发完整模型；advance 后修复完成")

# ═══════════════════════════════════════════════════════════════════
# 6. 旧维修链路仍可用（bridge probe 契约）
# ═══════════════════════════════════════════════════════════════════

func _test_legacy_repair_still_works() -> void:
	_section_begin("6 旧维修链路")
	var w = _make_world()
	var full_before: Dictionary = w.vm_damage_full()
	var rep: Dictionary = w.start_repair("sensor_cal")
	_eq(bool(rep.get("ok", false)), true, "world.start_repair(sensor_cal) 仍可用",
		String(rep.get("reason", "")))
	_eq(w.advance_damage(130.0).size(), 1, "advance_damage 完成 1 项（legacy）")
	var repaired := false
	for raw in (w.vm_damage().get("sections", []) as Array):
		var d: Dictionary = raw
		if String(d.get("id", "")) == "sensor_cal":
			repaired = String(d.get("state", "")) == "repaired"
	_ok(repaired, "legacy sensor_cal=repaired")
	_eq((w.vm_damage().get("queue", []) as Array).size(), 0, "legacy queue 清空")
	# legacy 操作不应推进/污染完整模型
	_eq(float((w.vm_damage_full().get("t", -1.0))), float(full_before.get("t", -1.0)),
		"legacy 维修不推进完整模型 t")
	_eq((w.vm_damage_full().get("queue", []) as Array).size(), 0,
		"legacy 维修不进入完整模型 queue")
	_data_line("legacy-repair", "start_repair/advance_damage 保持原行为；完整模型独立")

# ═══════════════════════════════════════════════════════════════════
# 7. 实体/懒加载/敌舰
# ═══════════════════════════════════════════════════════════════════

func _test_entities_and_lazy() -> void:
	_section_begin("7 实体/懒加载/敌舰")
	var w = _make_world()
	var r: Dictionary = w.damage_apply_hit("hull", 0.5, 0.5, "dorsal", "probe", "summons_4471")
	_eq(bool(r.get("ok", false)), true, "敌舰 damage_apply_hit 成功")
	_ok(float(_full_section(w, "hull", "summons_4471").get("integrity", 1.0)) < 1.0,
		"敌舰 hull 受损")
	_eq((w.vm_damage_full("harmattan").get("sections", []) as Array)[0].get("integrity", 0.0), 1.0,
		"敌舰受击不影响本舰")
	var bad: Dictionary = w.damage_apply_hit("hull", 0.5, 0.5, "fore", "probe", "unregistered_hulk")
	_eq(bool(bad.get("ok", true)), false, "未注册 fixture 命中被拒绝")
	_ok(String(bad.get("reason", "")).contains("无完整损管模型"), "拒绝原因明确",
		String(bad.get("reason", "")))
	_eq(w.damage_model_for("unregistered_hulk"), null,
		"拒绝后未注册 fixture 仍无模型（不伪造/不部分伤害）")
	_ok(not w.vm_damage_full("unregistered_hulk").size() > 0,
		"拒绝后未注册 fixture vm 仍为空")
	_data_line("entities", "summons 可受击；未注册 fixture 缺档案拒绝且无部分状态；本舰不受敌舰影响")

# ═══════════════════════════════════════════════════════════════════
# 8. HUD 读取兼容 + JSON
# ═══════════════════════════════════════════════════════════════════

func _test_hud_reads_and_json() -> void:
	_section_begin("8 HUD 读取/JSON")
	var w = _make_world()
	w.damage_apply_hit("sensors", 0.4, 0.4, "fore", "probe")
	var vm: Dictionary = w.vm_damage()
	# 模拟 V17 HUD `_fw_dmg_*` 读取（旧字段）
	var bad_rows := 0
	for raw in (vm.get("sections", []) as Array):
		var d: Dictionary = raw
		for key in ["id", "label", "state", "severity_pct", "repair_remaining_s",
				"progress", "can_repair"]:
			if not d.has(key):
				bad_rows += 1
	_eq(bad_rows, 0, "HUD 旧 sections 行字段齐全（不崩）")
	var summary: Dictionary = vm.get("summary", {})
	for key in ["total", "damaged", "degraded", "repairing", "repaired", "needs_attention"]:
		_ok(summary.has(key), "HUD summary 含 " + key)
	_ok(vm.get("queue") is Array, "HUD queue 为 Array")
	# 完整模型 HUD 页面可读字段
	var full: Dictionary = vm.get("model", {})
	for raw in (full.get("sections", []) as Array):
		var sec: Dictionary = raw
		for key in ["id", "label", "state", "integrity", "fire", "decompression",
				"powered", "repair"]:
			_ok(sec.has(key), "完整 section 含 " + key)
	var js := JSON.stringify(vm)
	_ok(js.length() > 2000, "vm_damage JSON 输出", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "JSON 回读 Dictionary")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_eq((pd.get("sections", []) as Array).size(), 3, "回读 legacy sections=3")
		var pm: Dictionary = pd.get("model", {})
		_eq((pm.get("sections", []) as Array).size(), 7, "回读完整 model.sections=7")
		_ok(pm.get("effects") is Dictionary, "回读完整 effects")
		_ok(pd.get("resources") is Dictionary, "回读 resources")
	_ok(not js.contains("\"weapons\""), "vm 不含 weapons（模型无武器）")
	_data_line("hud/json", "legacy 行字段齐全；完整模型字段可读；JSON %d 字节可回读" % js.length())

# ═══════════════════════════════════════════════════════════════════
# 9. V17 bridge 兼容
# ═══════════════════════════════════════════════════════════════════

func _test_bridge_compat() -> void:
	_section_begin("9 V17 bridge 兼容")
	var br = BridgeScript.new()
	_ok(br.boot(), "bridge.boot", str(br.errors))
	var dmg: Dictionary = br.damage_view()
	_eq(String(dmg.get("entity_id", "")), "harmattan", "bridge.damage_view entity_id")
	_eq((dmg.get("sections", []) as Array).size(), 3, "bridge 旧 sections=3（v17 HUD 不崩）")
	_eq(bool(dmg.get("has_full_model", false)), true, "bridge 暴露 has_full_model")
	_ok(not (dmg.get("model", {}) as Dictionary).is_empty(), "bridge 暴露完整 model")
	br.sync(0.1)
	var dmg2: Dictionary = br.damage_view()
	_eq((dmg2.get("sections", []) as Array).size(), 3, "bridge.sync 后旧 sections 仍 3 项")
	_ok(br.ready, "bridge 仍 ready")
	_data_line("bridge", "damage_view 保留 legacy sections=3 + has_full_model/model")
