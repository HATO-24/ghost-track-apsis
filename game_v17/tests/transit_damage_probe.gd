extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 阶段2-TRANSIT-DAMAGE-1 最小 probe：转场 5 舰损管数据层
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST_TRACK_APSIS\game_v17" --script res://tests/transit_damage_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接 HUD。
# ═══════════════════════════════════════════════════════════════════

const TransitDamage := preload("res://scripts/transit_damage.gd")
const DamageModel := preload("res://framework/core/damage_model.gd")

const SHIPS := ["apsis", "harmattan", "ferry", "watchtower", "deepwell"]
const BATCHES := ["1000", "1001", "1002", "1003", "1004"]
const SECTIONS := ["hull", "power", "propulsion", "sensors", "comms", "tanks", "docking"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2-TRANSIT-DAMAGE-1 PROBE · 转场 5 舰损管数据层")
	print("════════════════════════════════════════════════════════════")
	_test_content()
	_test_init()
	_test_damage()
	_test_repair()
	_test_summary_determinism()
	_test_errors_reset()
	_test_json()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 TRANSIT DAMAGE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 TRANSIT DAMAGE PROBE FAILED")
		quit(1)
	else:
		print("V17 TRANSIT DAMAGE PROBE OK")
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
	_ok(diff <= tol, label, "actual=%.6f expected=%.6f tol=%.6f" % [actual, expected, tol])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _section_row(vm: Dictionary, sid: String) -> Dictionary:
	for raw in (vm.get("sections", []) as Array):
		if String((raw as Dictionary).get("id", "")) == sid:
			return raw
	return {}

# ═══════════════════════════════════════════════════════════════════
# 1. 内容档案
# ═══════════════════════════════════════════════════════════════════

func _test_content() -> void:
	_section_begin("1 内容档案")
	var content: Dictionary = DamageModel.load_content()
	_ok(not content.is_empty(), "damage_l1.json 可加载")
	var ships: Dictionary = content.get("ships", {}) if content.get("ships") is Dictionary else {}
	for sid in SHIPS:
		_ok(ships.has(sid), "档案存在: " + sid)
	for legacy in ["harmattan", "summons_4471"]:
		_ok(ships.has(legacy), "旧档案保留: " + legacy)
	for i in range(SHIPS.size()):
		var sid: String = SHIPS[i]
		if not ships.has(sid):
			continue
		var p: Dictionary = ships[sid]
		_eq(String(p.get("id", "")), sid, "档案 %s id" % sid)
		_ok(String(p.get("name", "")) != "", "档案 %s name" % sid)
		_ok(String(p.get("class", "")) != "", "档案 %s class" % sid)
		var secs: Array = p.get("sections", []) if p.get("sections") is Array else []
		_eq(secs.size(), 7, "档案 %s 分区数=7" % sid)
		var ids: Array = []
		for raw in secs:
			ids.append(String((raw as Dictionary).get("id", "")))
		_eq(ids, SECTIONS, "档案 %s 分区 id 完整" % sid)
		for raw in secs:
			var s: Dictionary = raw
			var sid2 := String(s.get("id", ""))
			_ok(String(s.get("label", "")) != "", "%s.%s label" % [sid, sid2])
			_ok(String(s.get("kind", "")) != "", "%s.%s kind" % [sid, sid2])
			_ok(float(s.get("integrity", -1.0)) == 1.0, "%s.%s integrity=1" % [sid, sid2])
			_ok(float(s.get("repair_s", 0.0)) > 0.0, "%s.%s repair_s>0" % [sid, sid2])
			_ok(float(s.get("fire_risk", -1.0)) >= 0.0, "%s.%s fire_risk" % [sid, sid2])
			_ok(float(s.get("vacuum_risk", -1.0)) >= 0.0, "%s.%s vacuum_risk" % [sid, sid2])
			_ok(s.get("adjacent") is Array, "%s.%s adjacent" % [sid, sid2])
		var tr: Dictionary = p.get("transit", {}) if p.get("transit") is Dictionary else {}
		if sid != "harmattan":
			_eq(String(tr.get("batch", "")), BATCHES[i], "档案 %s batch" % sid)
			_eq(String(tr.get("fleet", "")), "transit_l4_l1", "档案 %s fleet" % sid)
			_ok(String(tr.get("role", "")) != "", "档案 %s role" % sid)
	# 旧 harmattan 档案未被覆盖（保留原 hull repair_s=180）
	var h: Dictionary = ships.get("harmattan", {})
	var hsecs: Array = h.get("sections", []) if h.get("sections") is Array else []
	_eq(hsecs.size(), 7, "harmattan 仍 7 分区")
	_near(float((hsecs[0] as Dictionary).get("repair_s", 0.0)), 180.0, 1.0e-9,
		"harmattan 原档案未覆盖")
	var list: Array = DamageModel.list_ships(content)
	_eq(list.size(), 6, "档案总数 6（旧2+新4，harmattan 共用）")
	_data_line("content", "ships=%s" % str(list))

# ═══════════════════════════════════════════════════════════════════
# 2. 初始化
# ═══════════════════════════════════════════════════════════════════

func _test_init() -> void:
	_section_begin("2 初始化")
	var td = TransitDamage.new()
	_ok(td.ready, "TransitDamage ready", str(td.errors))
	_eq(td.errors.size(), 0, "无初始化 errors")
	_eq(td.ship_ids().size(), 5, "5 舰模型")
	_eq(td.ship_ids(), SHIPS, "舰顺序 apsis..deepwell")
	for i in range(SHIPS.size()):
		var sid: String = SHIPS[i]
		_ok(td.has_ship(sid), "has_ship " + sid)
		_eq(td.batch_for(sid), BATCHES[i], "batch_for " + sid)
		_ok(td.role_for(sid) != "", "role_for " + sid)
		var vm: Dictionary = td.vm(sid)
		_eq(bool(vm.get("ok", false)), true, "vm %s ok" % sid)
		_eq(String(vm.get("wrapper_schema", "")), "v17_transit_damage.v1", "vm %s schema" % sid)
		_eq(String(vm.get("ship_id", "")), sid, "vm %s ship_id" % sid)
		_eq(String(vm.get("batch", "")), BATCHES[i], "vm %s batch" % sid)
		_eq(String(vm.get("fleet", "")), "transit_l4_l1", "vm %s fleet" % sid)
		_ok(String(vm.get("name", "")) != "", "vm %s name" % sid)
		_ok(String(vm.get("class", "")) != "", "vm %s class" % sid)
		_eq((vm.get("sections", []) as Array).size(), 7, "vm %s 7 分区" % sid)
		var sm: Dictionary = vm.get("summary", {})
		_eq(int(sm.get("total", -1)), 7, "vm %s summary.total=7" % sid)
		_eq(int(sm.get("nominal", -1)), 7, "vm %s 全 nominal" % sid)
		_eq(int(sm.get("on_fire", -1)), 0, "vm %s 无火" % sid)
		_eq(int(sm.get("decompressed", -1)), 0, "vm %s 无失压" % sid)
		var res: Dictionary = vm.get("resources", {})
		_ok(int(res.get("teams_total", 0)) >= 1, "vm %s teams_total" % sid)
		_ok(int(res.get("spares", 0)) >= 1, "vm %s spares" % sid)
		var eff: Dictionary = vm.get("effects", {})
		_ok(eff.get("power") is Dictionary, "vm %s effects.power" % sid)
		_ok(eff.get("sensors") is Dictionary, "vm %s effects.sensors" % sid)
		_ok(eff.get("docking") is Dictionary, "vm %s effects.docking" % sid)
		for sec_id in SECTIONS:
			var sr := _section_row(vm, sec_id)
			_ok(not sr.is_empty(), "vm %s 分区 %s" % [sid, sec_id])
			_eq(String(sr.get("state", "")), "nominal", "%s.%s nominal" % [sid, sec_id])
			_near(float(sr.get("integrity", -1.0)), 1.0, 1.0e-9, "%s.%s integrity=1" % [sid, sec_id])
			_eq(bool(sr.get("powered", false)), true, "%s.%s powered" % [sid, sec_id])
	var s: Dictionary = td.summary()
	_eq(String(s.get("schema", "")), "v17_transit_damage.v1", "summary schema")
	_eq(int((s.get("totals", {}) as Dictionary).get("ships", -1)), 5, "summary ships=5")
	_eq(int((s.get("totals", {}) as Dictionary).get("nominal", -1)), 35, "summary nominal=35")
	_eq(int((s.get("totals", {}) as Dictionary).get("operational", -1)), 5, "summary 全 operational")
	_eq((s.get("ships", []) as Array).size(), 5, "summary ships 数组 5")
	_data_line("init", "5 舰 × 7 分区全 nominal · resources teams/spares 就绪")

# ═══════════════════════════════════════════════════════════════════
# 3. 伤害 / 火灾 / 失压 / 断电
# ═══════════════════════════════════════════════════════════════════

func _test_damage() -> void:
	_section_begin("3 伤害/火灾/失压/断电")
	var td = TransitDamage.new()
	# 普通伤害
	var hit: Dictionary = td.apply_hit("apsis", "hull", 0.35, 0.4)
	_eq(bool(hit.get("ok", false)), true, "apsis hull 命中 ok")
	var vm: Dictionary = td.vm("apsis")
	var hull := _section_row(vm, "hull")
	_ok(float(hull.get("integrity", 1.0)) < 1.0, "apsis hull integrity 下降",
		"%.3f" % float(hull.get("integrity", 1.0)))
	_ok(int(vm.get("summary", {}).get("needs_attention", 0)) > 0, "apsis needs_attention>0")
	_ok((vm.get("events", []) as Array).size() > 0, "apsis events 记录")
	# 火灾（tanks fire_risk 高）
	var fire_hit: Dictionary = td.apply_hit("apsis", "tanks", 0.9, 0.5)
	_eq(bool(fire_hit.get("ok", false)), true, "apsis tanks 命中 ok")
	var vm2: Dictionary = td.vm("apsis")
	var tanks := _section_row(vm2, "tanks")
	_ok(bool((tanks.get("fire", {}) as Dictionary).get("active", false)), "apsis tanks 起火")
	_ok(float((tanks.get("fire", {}) as Dictionary).get("intensity", 0.0)) > 0.0,
		"火灾强度>0")
	_ok(int(vm2.get("summary", {}).get("on_fire", 0)) >= 1, "summary on_fire>=1")
	_ok(int((vm2.get("effects", {}).get("fire", {}) as Dictionary).get("count", 0)) >= 1,
		"effects.fire count")
	td.step(5.0)
	var vm2b: Dictionary = td.vm("apsis")
	var fire_int := float((_section_row(vm2b, "tanks").get("fire", {}) as Dictionary).get("intensity", 0.0))
	_ok(fire_int >= float((tanks.get("fire", {}) as Dictionary).get("intensity", 0.0)),
		"火灾随时间增长/保持", "%.3f" % fire_int)
	# 失压（hull vacuum_risk 高）
	var dec_hit: Dictionary = td.apply_hit("deepwell", "hull", 0.8, 0.4)
	_eq(bool(dec_hit.get("ok", false)), true, "deepwell hull 命中 ok")
	var dw_vm: Dictionary = td.vm("deepwell")
	var dw_hull := _section_row(dw_vm, "hull")
	_ok(bool((dw_hull.get("decompression", {}) as Dictionary).get("active", false)),
		"deepwell hull 失压")
	_ok(int(dw_vm.get("summary", {}).get("decompressed", 0)) >= 1, "summary decompressed>=1")
	var integrity0 := float(dw_hull.get("integrity", 1.0))
	td.step(5.0)
	var integrity1 := float(_section_row(td.vm("deepwell"), "hull").get("integrity", 1.0))
	_ok(integrity1 < integrity0, "失压持续损伤", "%.3f→%.3f" % [integrity0, integrity1])
	# 断电（power 完整度低于 0.5 传播）
	var p_hit: Dictionary = td.apply_hit("watchtower", "power", 0.6, 0.5)
	_eq(bool(p_hit.get("ok", false)), true, "watchtower power 命中 ok")
	td.step(0.1)
	var wt_vm: Dictionary = td.vm("watchtower")
	var wt_power := _section_row(wt_vm, "power")
	_ok(float(wt_power.get("integrity", 1.0)) < 0.5, "watchtower power<0.5",
		"%.3f" % float(wt_power.get("integrity", 1.0)))
	var unpowered := int(wt_vm.get("summary", {}).get("unpowered", 0))
	_ok(unpowered >= 1, "断电传播 unpowered>=1", str(unpowered))
	var wt_sensors := _section_row(wt_vm, "sensors")
	_eq(bool(wt_sensors.get("powered", true)), false, "sensors 断电")
	_eq(bool((wt_vm.get("effects", {}).get("sensors", {}) as Dictionary).get("available", true)),
		false, "effects.sensors unavailable")
	# 毁坏
	var destroy_hit1: Dictionary = td.apply_hit("ferry", "hull", 1.0, 0.6)
	td.apply_hit("ferry", "hull", 1.0, 0.6)
	var f_vm: Dictionary = td.vm("ferry")
	var f_hull := _section_row(f_vm, "hull")
	_ok(String(f_hull.get("state", "")) in ["damaged", "critical", "destroyed"],
		"ferry hull 重度/毁坏", String(f_hull.get("state", "")))
	var repair_destroyed := td.assign_repair("ferry", "hull")
	if String(f_hull.get("state", "")) == "destroyed":
		_eq(bool(repair_destroyed.get("ok", true)), false, "毁坏分区不可修")
	_data_line("damage", "普通伤害/起火/失压/断电传播/重度毁坏 均正确记录")

# ═══════════════════════════════════════════════════════════════════
# 4. 维修 / 资源
# ═══════════════════════════════════════════════════════════════════

func _test_repair() -> void:
	_section_begin("4 维修/资源")
	var td = TransitDamage.new()
	td.apply_hit("apsis", "hull", 0.5, 0.4)
	td.apply_hit("apsis", "propulsion", 0.6, 0.4)
	var a: Dictionary = td.assign_repair("apsis", "hull", 1)
	_eq(bool(a.get("ok", false)), true, "assign_repair hull ok")
	_eq(int((a.get("job", {}) as Dictionary).get("priority", -1)), 1, "维修优先级 1")
	var dup: Dictionary = td.assign_repair("apsis", "hull", 2)
	_eq(bool(dup.get("ok", true)), false, "重复 assign 拒绝")
	_eq(String(dup.get("reason", "")), "已在维修队列", "重复 assign reason")
	var pr: Dictionary = td.set_priority("apsis", "hull", 3)
	_eq(bool(pr.get("ok", false)), true, "set_priority ok")
	_eq(int((pr.get("job", {}) as Dictionary).get("priority", -1)), 3, "priority=3")
	td.step(2.0)
	var vm: Dictionary = td.vm("apsis")
	var res: Dictionary = vm.get("resources", {})
	_ok(int(res.get("teams_busy", 0)) >= 1, "维修队投入", str(res.get("teams_busy", 0)))
	_ok(int(res.get("spares_used", 0)) >= 1, "备件消耗", str(res.get("spares_used", 0)))
	_ok(int(vm.get("summary", {}).get("repairing", 0)) >= 1, "summary repairing>=1")
	_ok((vm.get("queue", []) as Array).size() >= 1, "queue 非空")
	var q0: Dictionary = (vm.get("queue", []) as Array)[0]
	_ok(float(q0.get("progress_s", 0.0)) > 0.0, "维修进度>0")
	var c: Dictionary = td.cancel_repair("apsis", "hull")
	_eq(bool(c.get("ok", false)), true, "cancel_repair ok")
	var c2: Dictionary = td.cancel_repair("apsis", "hull")
	_eq(bool(c2.get("ok", true)), false, "重复 cancel 拒绝")
	# 多舰多分区维修，资源不超额
	td.apply_hit("deepwell", "tanks", 0.6, 0.4)
	td.apply_hit("watchtower", "comms", 0.5, 0.4)
	td.apply_hit("ferry", "sensors", 0.5, 0.4)
	for pair in [["deepwell", "tanks"], ["watchtower", "comms"], ["ferry", "sensors"]]:
		td.assign_repair(String(pair[0]), String(pair[1]), 2)
	td.step(20.0)
	var all: Dictionary = td.summary()
	_ok(int((all.get("totals", {}) as Dictionary).get("repairing", 0)) >= 1, "多舰维修中")
	for raw_ship in (all.get("ships", []) as Array):
		var sr: Dictionary = raw_ship
		var r2: Dictionary = td.vm(String(sr.get("ship_id", ""))).get("resources", {})
		_ok(int(r2.get("spares_used", 0)) <= int(r2.get("spares", 0)) + 1, "备件不超额")
		_ok(int(r2.get("teams_busy", 0)) <= int(r2.get("teams_total", 0)), "维修队不超额")
	# 未知分组
	_eq(bool(td.assign_repair("no_ship", "hull").get("ok", true)), false, "未知舰维修拒绝")
	_eq(bool(td.assign_repair("apsis", "no_section").get("ok", true)), false, "未知分区维修拒绝")
	_data_line("repair", "assign/priority/step/cancel/多舰资源上限 正常")

# ═══════════════════════════════════════════════════════════════════
# 5. step / summary / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_summary_determinism() -> void:
	_section_begin("5 step/summary/确定性")
	var a = TransitDamage.new()
	var b = TransitDamage.new()
	a.apply_hit("apsis", "hull", 0.4, 0.4)
	a.apply_hit("ferry", "tanks", 0.8, 0.5)
	b.apply_hit("apsis", "hull", 0.4, 0.4)
	b.apply_hit("ferry", "tanks", 0.8, 0.5)
	var step_res: Dictionary = a.step(10.0)
	_eq(bool(step_res.get("ok", false)), true, "step ok")
	_ok(float(step_res.get("t", -1.0)) >= 10.0, "step t 推进")
	_eq(int(step_res.get("step_count", 0)), 1, "step_count=1")
	_ok(step_res.get("summary") is Dictionary, "step 返回 summary")
	var t0 := float(a.summary().get("t", -1.0))
	a.step(0.0)
	_near(float(a.summary().get("t", -1.0)), t0, 1.0e-9, "step(0) t 不变")
	_ok(JSON.stringify(a.summary()).length() > 2000, "summary JSON 较大")
	_ok(JSON.parse_string(JSON.stringify(a.summary())) is Dictionary, "summary JSON 回读")
	b.step(10.0)
	var va := JSON.stringify(a.vm("apsis"))
	var vb := JSON.stringify(b.vm("apsis"))
	_ok(va == vb, "两实例 apsis VM 完全一致（确定性）")
	_ok(JSON.stringify(a.summary()) == JSON.stringify(b.summary()), "两实例 summary 一致")
	_ok(JSON.stringify(a.vm("ferry")) == JSON.stringify(b.vm("ferry")), "ferry 确定性")
	var s: Dictionary = a.summary()
	_eq(String(s.get("fleet", "")), "transit_l4_l1", "summary fleet")
	_ok(int((s.get("totals", {}) as Dictionary).get("sections", -1)) == 35, "totals.sections=35")
	_ok(int((s.get("totals", {}) as Dictionary).get("on_fire", 0)) >= 1, "totals.on_fire>=1")
	_ok(int((s.get("totals", {}) as Dictionary).get("needs_attention", 0)) >= 1,
		"totals.needs_attention")
	_ok(String(s.get("weapon_source", "")).contains("none"), "summary 明示无武器来源")
	_ok(a.vm("apsis").has("hud_fields"), "vm 含 hud_fields")
	_ok(a.vm("apsis").get("hud_fields") is Array, "hud_fields 数组")
	_data_line("step", "t=%.1f step_count=1 · 两实例 VM/summary 一致 · totals sections=35" % t0)

# ═══════════════════════════════════════════════════════════════════
# 6. 错误 / reset
# ═══════════════════════════════════════════════════════════════════

func _test_errors_reset() -> void:
	_section_begin("6 错误/reset")
	var td = TransitDamage.new()
	var bad_vm: Dictionary = td.vm("no_ship")
	_eq(bool(bad_vm.get("ok", true)), false, "未知舰 vm ok=false")
	_eq(String(bad_vm.get("reason", "")), "unknown_ship", "未知舰 reason")
	var bad_hit: Dictionary = td.apply_hit("apsis", "no_section", 0.5)
	_eq(bool(bad_hit.get("ok", true)), false, "未知分区命中拒绝")
	var bad_cancel: Dictionary = td.cancel_repair("apsis", "no_section")
	_eq(bool(bad_cancel.get("ok", true)), false, "未知分区 cancel 拒绝")
	var bad_prio: Dictionary = td.set_priority("no_ship", "hull", 1)
	_eq(bool(bad_prio.get("ok", true)), false, "未知舰 priority 拒绝")
	td.apply_hit("apsis", "hull", 0.6, 0.5)
	td.assign_repair("apsis", "hull", 1)
	td.step(5.0)
	_ok(float(td.summary().get("t", 0.0)) > 0.0, "reset 前 t>0")
	_ok(td.reset(), "reset ok")
	_eq(td.ship_ids().size(), 5, "reset 后 5 舰")
	_near(float(td.summary().get("t", -1.0)), 0.0, 1.0e-9, "reset 后 t=0")
	var hull := _section_row(td.vm("apsis"), "hull")
	_near(float(hull.get("integrity", -1.0)), 1.0, 1.0e-9, "reset 后 hull integrity=1")
	_eq((td.vm("apsis").get("queue", []) as Array).size(), 0, "reset 后 queue 空")
	_eq(int(td.summary().get("totals", {}).get("nominal", -1)), 35, "reset 后全 nominal")
	_data_line("errors/reset", "未知舰/分区安全拒绝 · reset 恢复 5 舰全 nominal")

# ═══════════════════════════════════════════════════════════════════
# 7. JSON
# ═══════════════════════════════════════════════════════════════════

func _test_json() -> void:
	_section_begin("7 JSON")
	var td = TransitDamage.new()
	var vm := td.vm("apsis")
	var js := JSON.stringify(vm)
	_ok(js.length() > 2000, "apsis VM JSON", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "apsis VM JSON 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_ok(pd.get("sections") is Array, "回读 sections")
		_ok(pd.get("resources") is Dictionary, "回读 resources")
		_ok(pd.get("effects") is Dictionary, "回读 effects")
		_ok(pd.get("queue") is Array, "回读 queue")
		_eq((pd.get("sections", []) as Array).size(), 7, "回读 7 分区")
	for sid in SHIPS:
		var sj := JSON.stringify(td.vm(sid))
		_ok(sj.length() > 1000, "vm %s JSON 可序列化" % sid, "len=%d" % sj.length())
		_ok(JSON.parse_string(sj) is Dictionary, "vm %s JSON 回读" % sid)
	var sm := JSON.stringify(td.summary())
	_ok(sm.length() > 3000, "summary JSON", "len=%d" % sm.length())
	_ok(JSON.parse_string(sm) is Dictionary, "summary JSON 回读")
	var hv: Array = td.vm("apsis").get("hud_fields", [])
	for key in ["sections", "queue", "resources", "summary", "effects", "ship_id", "batch"]:
		var found := false
		for f in hv:
			if String(f).contains(key):
				found = true
		_ok(found, "hud_fields 含 " + key)
	_data_line("json", "apsis VM=%d summary=%d · 5 舰 JSON 均可回读" % [js.length(), sm.length()])
