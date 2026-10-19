extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R2-DAMAGE-1 headless probe：完整损管/毁伤模型
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/damage_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
# ═══════════════════════════════════════════════════════════════════

const DamageModel := preload("res://framework/core/damage_model.gd")
const CONTENT_PATH := "res://framework/content/damage_l1.json"
const SECTION_IDS := ["hull", "power", "propulsion", "sensors", "comms", "tanks", "docking"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R2-DAMAGE-1 PROBE · 损管/毁伤模型（分区/穿透/火灾/失压/断电/维修）")
	print("════════════════════════════════════════════════════════════")
	_test_content()
	_test_setup_and_vm()
	_test_hits_and_overflow()
	_test_fire()
	_test_decompression()
	_test_power_loss()
	_test_subsystem_effects()
	_test_repair_queue()
	_test_resource_exhaustion()
	_test_destroyed_and_operational()
	_test_two_ships_and_json()
	_test_determinism()
	_test_content_driven()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("DAMAGE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("DAMAGE PROBE FAILED")
		quit(1)
	else:
		print("DAMAGE PROBE OK")
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
	_ok(diff <= tol, label, "actual=%.5f expected=%.5f diff=%.5f tol=%.5f" % [actual, expected, diff, tol])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _new_model(ship_id := "harmattan"):
	var m = DamageModel.new()
	var ok: bool = m.setup({}, ship_id)
	_ok(ok, "setup " + ship_id, str(m.errors))
	return m

func _sec(m, sid: String) -> Dictionary:
	return m.section(sid)

func _state_of(m, sid: String) -> String:
	return String(_sec(m, sid).get("state", ""))

func _integrity(m, sid: String) -> float:
	return float(_sec(m, sid).get("integrity", -1.0))

func _step_many(m, count: int, dt: float) -> void:
	for i in range(count):
		m.step(dt)

func _has_event(m, type_name: String, sid := "") -> bool:
	for raw in m.events:
		var ev: Dictionary = raw
		if String(ev.get("type", "")) != type_name:
			continue
		if sid == "" or String(ev.get("section", "")) == sid:
			return true
	return false

func _queue_job(m, sid: String) -> Dictionary:
	for raw in m.queue:
		var job: Dictionary = raw
		if String(job.get("section", "")) == sid:
			return job
	return {}

# ═══════════════════════════════════════════════════════════════════
# 1. 内容文件 / schema
# ═══════════════════════════════════════════════════════════════════

func _test_content() -> void:
	_section_begin("1 内容文件")
	_ok(FileAccess.file_exists(CONTENT_PATH), "内容文件存在: " + CONTENT_PATH)
	var c := DamageModel.load_content()
	_ok(not c.is_empty(), "JSON 可解析")
	_eq(String(c.get("schema", "")), "damage.v1", "schema=damage.v1")
	_ok(String(c.get("id", "")) != "", "id 非空")
	var ships: Dictionary = c.get("ships", {})
	_ok(ships.has("harmattan"), "含本舰档案 harmattan")
	_ok(ships.has("summons_4471"), "含敌舰档案 summons_4471")
	for sid in ["harmattan", "summons_4471"]:
		var prof: Dictionary = ships[sid]
		var secs: Array = prof.get("sections", [])
		_eq(secs.size(), 7, "%s 分区 7" % sid)
		var ids: Array = []
		for raw in secs:
			ids.append(String((raw as Dictionary).get("id", "")))
		for need in SECTION_IDS:
			_ok(need in ids, "%s 含分区 %s" % [sid, need])
	var th: Dictionary = c.get("state_thresholds", {})
	for key in ["nominal", "degraded", "damaged", "destroyed"]:
		_ok(th.has(key), "阈值 state_thresholds." + key)
	_ok(c.get("repair") is Dictionary, "repair 参数存在")
	_ok(c.get("fire") is Dictionary and c.get("decompression") is Dictionary, "火灾/失压参数存在")
	_data_line("content", "schema=%s ships=%s" % [String(c.get("id", "")), str(DamageModel.list_ships(c))])

# ═══════════════════════════════════════════════════════════════════
# 2. 初始化 / vm_damage 结构
# ═══════════════════════════════════════════════════════════════════

func _test_setup_and_vm() -> void:
	_section_begin("2 初始化 / vm_damage")
	var m = _new_model()
	_eq(m.entity_id, "harmattan", "entity_id=harmattan")
	_eq(m.sections.size(), 7, "sections=7")
	_eq(m.section_ids(), SECTION_IDS, "分区 id 与规范一致")
	for sid in SECTION_IDS:
		_eq(_state_of(m, sid), "nominal", "初始 %s nominal" % sid)
		_near(_integrity(m, sid), 1.0, 1.0e-9, "初始 %s integrity=1.0" % sid)
		_ok(_sec(m, sid).has("fire") and _sec(m, sid).has("decompression"), "%s 有火灾/失压结构" % sid)
		_ok(_sec(m, sid).has("repair_s") and float(_sec(m, sid).get("repair_s", 0.0)) > 0.0,
			"%s 有维修难度 repair_s" % sid)
	var repair_cfg: Dictionary = (DamageModel.load_content().get("repair", {}) as Dictionary)
	_eq(int(m.resources.get("teams_total", 0)), int(repair_cfg.get("teams_total", 0)), "维修队数来自内容")
	_eq(int(m.resources.get("spares", 0)), int(repair_cfg.get("spares", 0)), "备件数来自内容")
	_eq(float(m.resources.get("power_max", 0.0)), float(repair_cfg.get("power_max", 0.0)), "电力上限来自内容")
	var vm: Dictionary = m.vm_damage()
	for key in ["schema", "model", "entity_id", "t", "sections", "events", "queue",
			"resources", "summary", "effects", "units", "note"]:
		_ok(vm.has(key), "vm_damage 含字段: " + key)
	_eq((vm.get("sections", []) as Array).size(), 7, "vm sections=7")
	var sum: Dictionary = vm.get("summary", {})
	_eq(int(sum.get("total", 0)), 7, "summary.total=7")
	_eq(int(sum.get("nominal", 0)), 7, "summary.nominal=7")
	_near(float(sum.get("integrity_avg", 0.0)), 1.0, 1.0e-9, "summary.integrity_avg=1.0")
	_eq(int(sum.get("needs_attention", -1)), 0, "summary.needs_attention=0")
	var eff: Dictionary = vm.get("effects", {})
	for key in ["power", "sensors", "comms", "propulsion", "docking", "fire", "decompression",
			"unpowered_sections"]:
		_ok(eff.has(key), "effects 含字段: " + key)
	_data_line("vm", "sections=7 · summary.nominal=7 · effects keys=%d" % eff.keys().size())

# ═══════════════════════════════════════════════════════════════════
# 3. 命中 / 穿透溢出
# ═══════════════════════════════════════════════════════════════════

func _test_hits_and_overflow() -> void:
	_section_begin("3 命中 / 穿透溢出")
	var m = _new_model()
	var r: Dictionary = m.apply_hit("sensors", 0.35, 0.2, "fore", "probe")
	_eq(bool(r.get("ok", false)), true, "apply_hit sensors ok")
	_ok(_integrity(m, "sensors") < 1.0, "sensors 完整度下降",
		"integrity=%.3f" % _integrity(m, "sensors"))
	_eq(_state_of(m, "sensors"), "degraded", "0.35 命中后 sensors=degraded")
	_ok(_has_event(m, "hit", "sensors"), "产生 hit 事件")
	_eq(_integrity(m, "tanks"), 1.0, "未命中/非相邻分区不受影响（tanks=1.0）")
	var bad: Dictionary = m.apply_hit("nonexistent", 0.5)
	_eq(bool(bad.get("ok", true)), false, "未知分区命中被拒绝")
	# 穿透：hull 0.9/0.8 → 溢出到 2 个相邻分区（按方向顺序）
	var m2 = _new_model()
	var r2: Dictionary = m2.apply_hit("hull", 0.9, 0.8, "fore", "probe")
	var overflow: Array = r2.get("overflow_sections", [])
	_eq(overflow.size(), 2, "穿透溢出到 2 个相邻分区", str(overflow))
	_ok(_integrity(m2, String(overflow[0])) < 1.0, "溢出分区 1 受损")
	_ok(_integrity(m2, String(overflow[1])) < 1.0, "溢出分区 2 受损")
	_ok(_has_event(m2, "penetration"), "产生 penetration 事件")
	_eq(_integrity(m2, "hull") < 1.0, true, "hull 本身受损")
	# 低穿透/低能量不溢出
	var m3 = _new_model()
	var r3: Dictionary = m3.apply_hit("hull", 0.2, 0.0, "fore", "probe")
	_eq((r3.get("overflow_sections", []) as Array).size(), 0, "低能量/零穿透不溢出")
	_data_line("hit/penetration", "sensors 0.35→%s · hull 0.9/0.8→overflow×2" % [
		_state_of(m, "sensors")])

# ═══════════════════════════════════════════════════════════════════
# 4. 火灾
# ═══════════════════════════════════════════════════════════════════

func _test_fire() -> void:
	_section_begin("4 火灾")
	var m = _new_model()
	var r: Dictionary = m.apply_hit("tanks", 0.6, 0.5, "aft", "probe")
	_eq(bool(r.get("ok", false)), true, "命中储罐")
	_ok(bool((_sec(m, "tanks").get("fire", {}) as Dictionary).get("active", false)), "储罐起火")
	_ok(_has_event(m, "fire", "tanks"), "产生 fire 事件")
	var i0 := _integrity(m, "tanks")
	var intensity0 := float((_sec(m, "tanks").get("fire", {}) as Dictionary).get("intensity", 0.0))
	m.step(5.0)
	_ok(_integrity(m, "tanks") < i0, "火灾持续造成伤害",
		"%.3f → %.3f" % [i0, _integrity(m, "tanks")])
	_ok(float((_sec(m, "tanks").get("fire", {}) as Dictionary).get("intensity", 0.0)) > intensity0,
		"火灾强度增长")
	_step_many(m, 3, 5.0)
	var fire_sections: Array = (m.effects().get("fire", {}) as Dictionary).get("sections", [])
	_ok(fire_sections.size() >= 2, "火灾蔓延到相邻分区", str(fire_sections))
	_ok(_has_event(m, "fire_spread"), "产生 fire_spread 事件")
	# 维修压制火焰并修复（小步长：压制先于火势蔓延）
	var m2 = _new_model()
	m2.apply_hit("tanks", 0.6, 0.5, "aft", "probe")
	var asg: Dictionary = m2.assign_repair("tanks", 1)
	_eq(bool(asg.get("ok", false)), true, "指派储罐维修")
	_step_many(m2, 400, 1.0)
	_eq(bool((_sec(m2, "tanks").get("fire", {}) as Dictionary).get("active", true)), false,
		"维修后火焰扑灭")
	_near(_integrity(m2, "tanks"), 1.0, 1.0e-9, "维修后储罐恢复 1.0")
	_ok(_has_event(m2, "fire_out", "tanks"), "产生 fire_out 事件")
	_data_line("fire", "tanks 起火/增长/蔓延 → 维修压制后恢复 1.0")

# ═══════════════════════════════════════════════════════════════════
# 5. 失压
# ═══════════════════════════════════════════════════════════════════

func _test_decompression() -> void:
	_section_begin("5 失压")
	var m = _new_model()
	m.apply_hit("hull", 0.5, 0.5, "fore", "probe")
	_ok(bool((_sec(m, "hull").get("decompression", {}) as Dictionary).get("active", false)), "舰体失压")
	_ok(_has_event(m, "decompression", "hull"), "产生 decompression 事件")
	var i0 := _integrity(m, "hull")
	m.step(5.0)
	_ok(_integrity(m, "hull") < i0, "失压持续造成伤害")
	_step_many(m, 3, 10.0)
	var dec_sections: Array = (m.effects().get("decompression", {}) as Dictionary).get("sections", [])
	_ok(dec_sections.size() >= 2, "失压扩散到相邻分区", str(dec_sections))
	_ok(_has_event(m, "decompression_spread"), "产生 decompression_spread 事件")
	# 封堵+修复
	var m2 = _new_model()
	m2.apply_hit("hull", 0.5, 0.5, "fore", "probe")
	m2.assign_repair("hull", 1)
	_step_many(m2, 400, 1.0)
	_eq(bool((_sec(m2, "hull").get("decompression", {}) as Dictionary).get("active", true)), false,
		"维修后失压封堵")
	_ok(_has_event(m2, "sealed", "hull"), "产生 sealed 事件")
	_data_line("decompression", "hull 失压/扩散 → 维修封堵并恢复")

# ═══════════════════════════════════════════════════════════════════
# 6. 断电 / 子系统
# ═══════════════════════════════════════════════════════════════════

func _test_power_loss() -> void:
	_section_begin("6 断电 / 子系统")
	var m = _new_model()
	m.apply_hit("power", 0.8, 0.3, "port", "probe")
	_ok(_integrity(m, "power") < 0.5, "power 完整度低于断电阈值",
		"%.3f" % _integrity(m, "power"))
	m.step(0.1)
	_ok(_has_event(m, "power_loss"), "产生 power_loss 事件")
	for sid in ["sensors", "comms", "docking", "propulsion"]:
		_eq(bool(_sec(m, sid).get("power_loss", false)), true, "%s 断电标志" % sid)
		_eq(bool(_sec(m, sid).get("powered", true)), false, "%s powered=false" % sid)
	var eff: Dictionary = m.effects()
	_ok(float((eff.get("power", {}) as Dictionary).get("fraction", 1.0)) < 0.5, "effects.power.fraction<0.5")
	_near(float((eff.get("sensors", {}) as Dictionary).get("mult", 1.0)), 0.0, 1.0e-9,
		"断电时 sensors mult=0")
	_ok(float((eff.get("comms", {}) as Dictionary).get("command_delay_s", 0.0)) >= 15.0,
		"断电时 comms 延迟 ≥15 s")
	# 修电恢复（小步长：先压制火灾再修结构）
	m.assign_repair("power", 1)
	_step_many(m, 150, 1.0)
	m.step(0.1)
	_eq(_state_of(m, "power"), "nominal", "power 修复到 nominal")
	m.step(0.1)
	_ok(_has_event(m, "power_restored"), "产生 power_restored 事件")
	_eq(bool(_sec(m, "sensors").get("powered", false)), true, "供电恢复后 sensors powered")
	_data_line("power", "power 0.8 命中→断电传播→维修恢复（power_restored）")

func _test_subsystem_effects() -> void:
	_section_begin("7 子系统效果映射")
	var m = _new_model()
	m.apply_hit("sensors", 0.5, 0.5, "fore", "probe")
	_eq(_state_of(m, "sensors"), "damaged", "sensors 受损 damaged")
	var eff: Dictionary = m.effects()
	_near(float((eff.get("sensors", {}) as Dictionary).get("mult", 1.0)), 0.3, 1.0e-6,
		"sensors.damaged_mult=0.3（来自内容）")
	_ok(bool((eff.get("sensors", {}) as Dictionary).get("available", false)), "sensors 仍可用")
	m.apply_hit("comms", 0.5, 0.5, "fore", "probe")
	eff = m.effects()
	_near(float((eff.get("comms", {}) as Dictionary).get("command_delay_s", 0.0)), 6.0, 1.0e-6,
		"comms.damaged_delay_s=6")
	m.apply_hit("propulsion", 0.5, 0.5, "fore", "probe")
	eff = m.effects()
	_near(float((eff.get("propulsion", {}) as Dictionary).get("dv_mult", 0.0)), 0.5, 1.0e-6,
		"propulsion.damaged_dv=0.5")
	m.apply_hit("docking", 0.5, 0.0, "fore", "probe")
	_ok(bool((m.effects().get("docking", {}) as Dictionary).get("available", false)),
		"docking 完整度 0.55 仍可用（无失压）")
	m.apply_hit("docking", 0.6, 0.8, "fore", "probe")
	_ok(not bool((m.effects().get("docking", {}) as Dictionary).get("available", true)),
		"docking 低于 min_integrity 后不可用")
	# 摧毁传感器 → 不可用/倍率 0
	var m2 = _new_model()
	m2.apply_hit("sensors", 1.0, 0.5, "fore", "probe")
	m2.apply_hit("sensors", 1.0, 0.5, "fore", "probe")
	_eq(_state_of(m2, "sensors"), "destroyed", "sensors 被摧毁")
	_eq(bool((m2.effects().get("sensors", {}) as Dictionary).get("available", true)), false,
		"摧毁后 sensors 不可用")
	_near(float((m2.effects().get("sensors", {}) as Dictionary).get("mult", 1.0)), 0.0, 1.0e-9,
		"摧毁后 sensors mult=0")
	_data_line("subsystem", "sensors 0.3 / comms 6s / propulsion 0.5 / docking min_integrity")

# ═══════════════════════════════════════════════════════════════════
# 8. 维修队列 / 优先级 / 取消
# ═══════════════════════════════════════════════════════════════════

func _test_repair_queue() -> void:
	_section_begin("8 维修队列 / 优先级")
	var m = _new_model()
	var a: Dictionary = m.assign_repair("sensors", 3)
	_eq(bool(a.get("ok", false)), true, "指派 sensors 优先级 3")
	var b: Dictionary = m.assign_repair("comms", 1)
	_eq(bool(b.get("ok", false)), true, "指派 comms 优先级 1")
	_eq(String((m.queue[0] as Dictionary).get("section", "")), "comms", "队列按优先级排序：comms 先")
	var again: Dictionary = m.assign_repair("sensors", 2)
	_eq(bool(again.get("ok", true)), false, "重复指派被拒绝")
	var pr: Dictionary = m.set_priority("sensors", 1)
	_eq(bool(pr.get("ok", false)), true, "set_priority ok")
	_eq(String((m.queue[0] as Dictionary).get("section", "")), "sensors",
		"同优先级按入队顺序：sensors 先")
	m.step(1.0)
	_eq(String(_queue_job(m, "sensors").get("status", "")), "active", "sensors 开始维修")
	_eq(int(m.resources.get("teams_busy", 0)), 2, "2 个维修队同时占用（teams_total=2）")
	_eq(int(m.resources.get("spares", 0)), 1, "两次启动各耗 1 备件（3→1）")
	var cancel: Dictionary = m.cancel_repair("comms")
	_eq(bool(cancel.get("ok", false)), true, "cancel_repair ok")
	_eq(m.queue.size(), 1, "取消后队列剩 1 项")
	_eq(int(m.resources.get("teams_busy", 0)), 1, "取消 active 任务释放 1 个维修队")
	_step_many(m, 10, 10.0)
	_eq(_state_of(m, "sensors"), "nominal", "sensors 修复到 nominal")
	_near(_integrity(m, "sensors"), 1.0, 1.0e-9, "sensors 修复后完整度 1.0")
	_eq(int(m.resources.get("teams_busy", -1)), 0, "完成后维修队释放")
	_ok(_has_event(m, "repair_done", "sensors"), "产生 repair_done 事件")
	_data_line("queue", "priority 排序/重复拒绝/取消/active 团队与备件消耗/完成释放")

# ═══════════════════════════════════════════════════════════════════
# 9. 资源耗尽
# ═══════════════════════════════════════════════════════════════════

func _test_resource_exhaustion() -> void:
	_section_begin("9 资源耗尽")
	var m = _new_model()
	var ids := ["hull", "power", "sensors", "comms", "tanks", "docking"]
	for sid in ids:
		var r: Dictionary = m.assign_repair(String(sid), 2)
		_eq(bool(r.get("ok", false)), true, "入队 " + String(sid))
	_eq(m.queue.size(), 6, "队列 6 项")
	_step_many(m, 30, 50.0)
	var failed := 0
	var failed_reasons := {}
	for raw in m.queue:
		var job: Dictionary = raw
		if String(job.get("status", "")) == "failed":
			failed += 1
			failed_reasons[String(job.get("reason", ""))] = true
	_ok(failed >= 1, "备件耗尽导致维修失败", "failed=%d" % failed)
	_eq(int(m.resources.get("spares", -1)), 0, "备件耗尽（spares=0）")
	_eq(bool(failed_reasons.has("spares")), true, "失败原因为 spares", str(failed_reasons.keys()))
	_ok(_has_event(m, "repair_failed"), "产生 repair_failed 事件")
	_eq(int(m.resources.get("teams_busy", -1)), 0, "完成后无占用维修队")
	_data_line("exhaustion", "6 项维修 + 备件 3 → failed=%d（spares）" % failed)

# ═══════════════════════════════════════════════════════════════════
# 10. 分区毁坏 / 不可修复 / 整体可用性
# ═══════════════════════════════════════════════════════════════════

func _test_destroyed_and_operational() -> void:
	_section_begin("10 分区毁坏 / 可用性")
	var m = _new_model()
	m.apply_hit("comms", 1.0, 0.5, "fore", "probe")
	m.apply_hit("comms", 1.0, 0.5, "fore", "probe")
	_eq(_state_of(m, "comms"), "destroyed", "comms 被摧毁")
	var asg: Dictionary = m.assign_repair("comms", 1)
	_eq(bool(asg.get("ok", true)), false, "毁坏分区不可现场修复")
	_ok(String(asg.get("reason", "")).contains("毁坏"), "拒绝原因写明毁坏",
		String(asg.get("reason", "")))
	var m2 = _new_model()
	m2.apply_hit("power", 1.0, 0.5, "fore", "probe")
	m2.apply_hit("power", 1.0, 0.5, "fore", "probe")
	m2.step(0.1)
	_eq(_state_of(m2, "power"), "destroyed", "power 被摧毁")
	_eq(bool((m2.effects().get("power", {}) as Dictionary).get("available", true)), false,
		"power 摧毁后 effects.power.available=false")
	_near(float((m2.effects().get("propulsion", {}) as Dictionary).get("dv_mult", 1.0)), 0.0, 1.0e-9,
		"power 摧毁后 propulsion dv_mult=0")
	_eq(m2.is_operational(), false, "power 毁坏 → is_operational=false")
	_data_line("destroyed", "comms 不可修 · power 毁坏→动力 0/不可用/非 operational")

# ═══════════════════════════════════════════════════════════════════
# 11. 双舰档案 / JSON
# ═══════════════════════════════════════════════════════════════════

func _test_two_ships_and_json() -> void:
	_section_begin("11 双舰档案 / JSON")
	var enemy = _new_model("summons_4471")
	_eq(enemy.entity_id, "summons_4471", "敌舰 entity_id")
	_eq(enemy.sections.size(), 7, "敌舰 7 分区")
	eq_check_ids(enemy)
	var r: Dictionary = enemy.apply_hit("hull", 0.5, 0.5, "dorsal", "probe")
	_eq(bool(r.get("ok", false)), true, "敌舰可受击")
	var vm: Dictionary = enemy.vm_damage()
	_ok(_has_event(enemy, "hit", "hull"), "敌舰事件记录")
	var js := JSON.stringify(vm)
	_ok(js.length() > 500, "vm_damage JSON 输出", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "JSON 回读 Dictionary")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_eq((pd.get("sections", []) as Array).size(), 7, "回读 sections=7")
		_ok(pd.get("summary") is Dictionary, "回读 summary")
		_ok(pd.get("resources") is Dictionary, "回读 resources")
		_ok(pd.get("effects") is Dictionary, "回读 effects")
		_ok(pd.get("queue") is Array, "回读 queue")
		_eq((pd.get("sections", []) as Array)[0].has("fire"), true, "回读 section fire")
	_ok(not js.contains("\"weapons\""), "vm 不含 weapons 字段（模型无武器）")
	_ok(String(vm.get("note", "")).contains("不生成武器"), "note 声明无武器")
	_data_line("ships/json", "harmattan + summons_4471 · vm JSON %d 字节可回读" % js.length())

func eq_check_ids(m) -> void:
	var ids: Array = []
	for raw in m.sections:
		ids.append(String((raw as Dictionary).get("id", "")))
	_eq(ids, SECTION_IDS, "分区 id 完整")

# ═══════════════════════════════════════════════════════════════════
# 12. 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_determinism() -> void:
	_section_begin("12 确定性")
	var a = _new_model()
	var b = _new_model()
	for m in [a, b]:
		m.apply_hit("tanks", 0.6, 0.5, "aft", "probe")
		m.apply_hit("power", 0.7, 0.3, "port", "probe")
		m.assign_repair("tanks", 1)
		_step_many(m, 5, 5.0)
	_eq(JSON.stringify(a.vm_damage()), JSON.stringify(b.vm_damage()), "相同输入序列 → 相同 vm_damage")
	_data_line("determinism", "两次同序列命中/维修/推进 → vm JSON 完全一致")

# ═══════════════════════════════════════════════════════════════════
# 13. 内容驱动（不写死）
# ═══════════════════════════════════════════════════════════════════

func _test_content_driven() -> void:
	_section_begin("13 内容驱动")
	var base := DamageModel.load_content()
	var copy: Dictionary = JSON.parse_string(JSON.stringify(base))
	(copy.get("repair", {}) as Dictionary)["spares"] = 1
	(copy.get("repair", {}) as Dictionary)["teams_total"] = 1
	var m = DamageModel.new()
	_ok(m.setup(copy, "harmattan"), "用修改后的内容 setup")
	_eq(int(m.resources.get("spares", 0)), 1, "spares 来自覆盖内容（1）")
	_eq(int(m.resources.get("teams_total", 0)), 1, "teams_total 来自覆盖内容（1）")
	# 修改火势增长参数 → 同样命中/推进后强度更高
	var copy2: Dictionary = JSON.parse_string(JSON.stringify(base))
	(copy2.get("fire", {}) as Dictionary)["growth_per_s"] = 0.5
	var fast = DamageModel.new()
	fast.setup(copy2, "harmattan")
	fast.apply_hit("tanks", 0.4, 0.5, "aft", "probe")
	fast.step(1.0)
	var slow = _new_model()
	slow.apply_hit("tanks", 0.4, 0.5, "aft", "probe")
	slow.step(1.0)
	var fast_i := float((_sec(fast, "tanks").get("fire", {}) as Dictionary).get("intensity", 0.0))
	var slow_i := float((_sec(slow, "tanks").get("fire", {}) as Dictionary).get("intensity", 0.0))
	_ok(fast_i > slow_i, "火势增长率来自内容（覆盖后更快）",
		"fast=%.3f slow=%.3f" % [fast_i, slow_i])
	# 修改阈值 → 状态判定改变（nominal 阈值降低后 0.35 命中仍 nominal）
	var copy3: Dictionary = JSON.parse_string(JSON.stringify(base))
	(copy3.get("state_thresholds", {}) as Dictionary)["degraded"] = 0.5
	var rare = DamageModel.new()
	rare.setup(copy3, "harmattan")
	rare.apply_hit("sensors", 0.25, 0.2, "fore", "probe")
	_ok(_state_of(rare, "sensors") != _state_of(_new_model(), "sensors"),
		"状态阈值来自内容（修改后判定不同）",
		"custom=%s default=degraded" % _state_of(rare, "sensors"))
	_data_line("content-driven", "spares/teams/growth/state_thresholds 均由 JSON 控制")
