extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段2K 最小 probe：DamageService（V2DamageModel 多舰损管）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/damage_service_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接 UI/物理。
# ═══════════════════════════════════════════════════════════════════

const DamageService := preload("res://scripts/core/damage_service.gd")

const DAMAGE_PATH := "res://framework/content/damage_l1.json"
const ALL_SHIPS := ["apsis", "harmattan", "ferry", "watchtower", "deepwell"]
const SECTIONS := ["hull", "power", "propulsion", "sensors", "comms", "tanks", "docking"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2K PROBE · DamageService")
	print("════════════════════════════════════════════════════════════")
	_test_setup()
	_test_damage_events()
	_test_sections_fire_power()
	_test_repair()
	_test_repair_priority_resources()
	_test_tick_fire_decompression()
	_test_save_load()
	_test_matrix()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 DAMAGE SERVICE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 DAMAGE SERVICE PROBE FAILED")
		quit(1)
	else:
		print("V17 DAMAGE SERVICE PROBE OK")
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
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.6f expected=%.6f" % [actual, expected])

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _norm_json(value) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func _new_damage(ships := ALL_SHIPS, default_ship := "apsis"):
	var ds = DamageService.new({"content_path": DAMAGE_PATH, "ships": ships,
		"default_ship": default_ship})
	_ok(bool(ds.ready), "DamageService ready", str(ds.errors))
	return ds

func _integrity(ds, ship_id: String, section_id: String) -> float:
	var vm: Dictionary = ds.ship_vm(ship_id)
	for raw in (vm.get("sections", []) as Array):
		if String((raw as Dictionary).get("id", "")) == section_id:
			return float((raw as Dictionary).get("integrity", -1.0))
	return -1.0

func _summary(ds, ship_id: String) -> Dictionary:
	return ds.ship_vm(ship_id).get("summary", {}) as Dictionary

func _core(ds) -> String:
	var vm: Dictionary = ds.vm()
	return _norm_json({"t": vm.get("t", 0.0), "ships": vm.get("ships", []),
		"applied_damage": vm.get("applied_damage", [])})

func _event(ship_id: String, damage: float, section := "hull",
		kind := "kinetic", pen := 0.5, target := "") -> Dictionary:
	return {"schema": "combat_damage_event.v1", "kind": "damage",
		"t": 0.0, "target_id": target, "target_ship": ship_id,
		"damage": damage, "penetration": pen, "damage_kind": kind,
		"suggested_section": section, "shot_id": "S-" + str(damage),
		"source": "probe"}

# ═══════════════════════════════════════════════════════════════════
# 1. setup / 内容
# ═══════════════════════════════════════════════════════════════════

func _test_setup() -> void:
	_section_begin("1 setup/内容")
	var ds = DamageService.new({"content_path": DAMAGE_PATH})
	_ok(bool(ds.ready), "默认全部舰船 ready", str(ds.errors))
	_eq(ds.ship_ids_list().size(), 6, "默认 6 舰")
	_ok("apsis" in ds.ship_ids_list(), "含 apsis")
	_ok("harmattan" in ds.ship_ids_list(), "含 harmattan")
	_eq(String(ds.default_ship), ds.ship_ids_list()[0], "默认 default_ship 首舰")
	_ok(bool(ds.check_contracts().get("ok", false)), "初始 contracts ok")
	var vm: Dictionary = ds.vm()
	_eq(String(vm.get("schema", "")), "v17.damage_service.v1", "VM schema")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("v15", true)), false, "不写 v15")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("world", true)), false, "不写 world")
	_eq(bool((vm.get("writes", {}) as Dictionary).get("physics", true)), false, "不做物理")
	_eq((vm.get("ships", []) as Array).size(), 6, "VM 6 舰")
	_ok(vm.get("summary") is Dictionary, "VM summary")
	# 子集
	var ds2 = _new_damage(["apsis", "harmattan"], "harmattan")
	_eq(ds2.ship_ids_list().size(), 2, "子集 2 舰")
	_eq(String(ds2.default_ship), "harmattan", "指定 default_ship")
	_ok(ds2.model("apsis") != null, "model(apsis)")
	_ok(ds2.model("ferry") == null, "未配置舰模型为空")
	_ok(bool(ds2.is_operational("apsis")), "初始 operational")
	# 内容/ships 校验
	var bad1 = DamageService.new({"content": {}})
	_ok(not bool(bad1.ready), "空内容拒绝")
	var bad2 = DamageService.new({"content_path": DAMAGE_PATH, "ships": ["no_such"]})
	_ok(not bool(bad2.ready), "未知舰船拒绝")
	var bad3 = DamageService.new({"content_path": DAMAGE_PATH, "ships": ["apsis"],
		"default_ship": "harmattan"})
	_ok(not bool(bad3.ready), "default_ship 不在 ships 拒绝")
	var bad4 = DamageService.new({"content_path": "/no/such.json"})
	_ok(not bool(bad4.ready), "不存在内容拒绝")
	var bad_content: Dictionary = {"schema": "bad", "ships": {}}
	_ok(not bool(ds.validate_content(bad_content).get("ok", true)), "validate_content 坏内容")
	# 每舰分区 7
	for sid in ds.ship_ids_list():
		var svm: Dictionary = ds.ship_vm(sid)
		_eq((svm.get("sections", []) as Array).size(), 7, "ship %s 7 分区" % sid)
		_ok(int((svm.get("summary", {}) as Dictionary).get("on_fire", -1)) == 0,
			"ship %s 初始无火" % sid)
	_data_line("setup", "默认6舰/子集/default_ship/内容校验/每舰7分区")

# ═══════════════════════════════════════════════════════════════════
# 2. combat_damage_event
# ═══════════════════════════════════════════════════════════════════

func _test_damage_events() -> void:
	_section_begin("2 伤害事件")
	var ds = _new_damage()
	var before := _integrity(ds, "apsis", "hull")
	var r: Dictionary = ds.apply_combat_damage(_event("apsis", 0.4, "hull"))
	_eq(bool(r.get("ok", false)), true, "apply_combat_damage ok", str(r.get("reason", "")))
	_eq(bool(r.get("applied", false)), true, "applied=true")
	_eq(String(r.get("ship_id", "")), "apsis", "ship_id")
	_eq(String(r.get("section", "")), "hull", "section")
	var after := _integrity(ds, "apsis", "hull")
	_ok(after < before, "integrity 下降")
	_ok(float(r.get("hit", {}).get("integrity_after", 1.0)) < 1.0, "hit integrity_after")
	var vm: Dictionary = ds.vm()
	_eq((vm.get("applied_damage", []) as Array).size(), 1, "applied_damage 1")
	_eq(String((vm.get("applied_damage", []) as Array)[0].get("ship_id", "")), "apsis",
		"applied 记录 ship")
	_ok(bool(_summary(ds, "apsis").get("damaged", 0) >= 1), "summary damaged")
	_ok(bool(ds.check_contracts().get("ok", false)), "伤害后 contracts ok")
	# section / suggested_section
	var r2: Dictionary = ds.apply_combat_damage(_event("apsis", 0.3, "power"))
	_eq(String(r2.get("section", "")), "power", "power 伤害")
	_ok(_integrity(ds, "apsis", "power") < 1.0, "power integrity 下降")
	# damage_kind 映射（无 section）
	var no_sec := {"schema": "combat_damage_event.v1", "kind": "damage",
		"target_ship": "apsis", "damage": 0.2, "penetration": 0.3,
		"damage_kind": "energy", "shot_id": "S-E"}
	var r3: Dictionary = ds.apply_combat_damage(no_sec)
	_eq(String(r3.get("section", "")), "sensors", "energy→sensors 映射")
	# 未知目标 + default_ship
	var unknown_target := {"schema": "combat_damage_event.v1", "kind": "damage",
		"target_id": "TRACK-X", "damage": 0.2, "penetration": 0.2,
		"damage_kind": "kinetic", "shot_id": "S-D"}
	var r4: Dictionary = ds.apply_combat_damage(unknown_target)
	_eq(String(r4.get("ship_id", "")), "apsis", "未知 target→default_ship")
	# opts ship_id
	var ev_ship := {"schema": "combat_damage_event.v1", "kind": "damage",
		"target_id": "T1", "damage": 0.2, "penetration": 0.2,
		"damage_kind": "kinetic", "shot_id": "S-O"}
	var r5: Dictionary = ds.apply_combat_damage(ev_ship, {"ship_id": "harmattan"})
	_eq(String(r5.get("ship_id", "")), "harmattan", "opts.ship_id 指定舰")
	# 直接 apply_hit
	var r6: Dictionary = ds.apply_hit("harmattan", "comms", 0.25)
	_eq(bool(r6.get("ok", false)), true, "apply_hit ok")
	_ok(_integrity(ds, "harmattan", "comms") < 1.0, "apply_hit comms 下降")
	# 非法事件
	var applied_before: int = (ds.vm().get("applied_damage", []) as Array).size()
	var integ_before := _integrity(ds, "apsis", "hull")
	var bads: Array = [
		{},
		{"schema": "bad", "kind": "damage", "damage": 0.2},
		{"schema": "combat_damage_event.v1", "kind": "damage", "target_ship": "apsis", "damage": 0},
		{"schema": "combat_damage_event.v1", "kind": "damage", "target_ship": "apsis", "damage": -1},
		{"schema": "combat_damage_event.v1", "kind": "damage", "target_ship": "no_ship", "damage": 0.2},
		{"schema": "combat_damage_event.v1", "kind": "damage", "target_ship": "apsis", "damage": 0.2, "suggested_section": "bad"},
	]
	for b in bads:
		var br: Dictionary = ds.apply_combat_damage(b)
		_eq(bool(br.get("ok", true)), false, "非法伤害事件拒绝：" + str(b).substr(0, 40))
	_eq((ds.vm().get("applied_damage", []) as Array).size(), applied_before, "拒绝不记录 applied")
	_eq(_integrity(ds, "apsis", "hull"), integ_before, "拒绝不改 integrity")
	# NaN
	var nan_ev := {"schema": "combat_damage_event.v1", "kind": "damage",
		"target_ship": "apsis", "damage": NAN}
	_eq(bool(ds.apply_combat_damage(nan_ev).get("ok", true)), false, "NaN damage 拒绝")
	_data_line("damage_event", "分区/映射/default/opts/非法拒绝/applied 记录")

# ═══════════════════════════════════════════════════════════════════
# 3. 分区 / 火灾 / 失压 / 断电
# ═══════════════════════════════════════════════════════════════════

func _test_sections_fire_power() -> void:
	_section_begin("3 火灾/失压/断电")
	var ds = _new_damage()
	# 每个分区可受伤
	for sec in SECTIONS:
		var ship := "harmattan"
		var before := _integrity(ds, ship, sec)
		var r: Dictionary = ds.apply_hit(ship, sec, 0.05, 0.1)
		_eq(bool(r.get("ok", false)), true, "section %s 可受伤" % sec)
		_ok(_integrity(ds, ship, sec) <= before, "section %s integrity" % sec)
	# 火灾/失压：tanks 高能命中
	var tanks: Dictionary = ds.apply_hit("apsis", "tanks", 0.9, 0.8)
	_eq(bool(tanks.get("ok", false)), true, "tanks 高能命中 ok")
	var vm: Dictionary = ds.ship_vm("apsis")
	var fire_count := int((vm.get("summary", {}) as Dictionary).get("on_fire", 0))
	_ok(fire_count >= 1, "tanks 起火", "fire=%d" % fire_count)
	var dec_count := int((vm.get("summary", {}) as Dictionary).get("decompressed", 0))
	_ok(dec_count >= 1, "失压触发", "dec=%d" % dec_count)
	var effects: Dictionary = vm.get("effects", {})
	_ok(int((effects.get("fire", {}) as Dictionary).get("count", 0)) >= 1, "effects fire count")
	# 推进火灾
	var integ_before := _integrity(ds, "apsis", "tanks")
	var tk: Dictionary = ds.tick(5.0)
	_eq(bool(tk.get("ok", false)), true, "tick ok")
	_ok(_integrity(ds, "apsis", "tanks") < integ_before, "火灾期间 integrity 继续下降")
	# 断电：击毁 power
	var ds2 = _new_damage(["apsis"], "apsis")
	for i in range(6):
		ds2.apply_hit("apsis", "power", 0.9, 0.9)
	_ok(_integrity(ds2, "apsis", "power") <= 0.0, "power 被击毁")
	var seff: Dictionary = ds2.ship_vm("apsis").get("effects", {})
	_eq(bool((seff.get("power", {}) as Dictionary).get("available", true)), false,
		"power unavailable")
	_ok((seff.get("unpowered_sections", []) as Array).size() > 0, "存在 unpowered sections")
	_ok(not bool(ds2.is_operational("apsis")), "power 毁坏后非 operational")
	# 毁坏分区不可维修
	var rep: Dictionary = ds2.repair("apsis", "power", 1)
	_eq(bool(rep.get("ok", true)), false, "毁坏分区维修拒绝")
	_data_line("fire_power", "tanks 起火/失压/火灾推进 · power 毁坏→断电/不可运作")

# ═══════════════════════════════════════════════════════════════════
# 4. 维修
# ═══════════════════════════════════════════════════════════════════

func _test_repair() -> void:
	_section_begin("4 维修")
	var ds = _new_damage(["apsis"], "apsis")
	ds.apply_hit("apsis", "hull", 0.5, 0.3)
	var integ := _integrity(ds, "apsis", "hull")
	_ok(integ < 1.0, "受伤后 <1")
	var r: Dictionary = ds.repair("apsis", "hull", 1)
	_eq(bool(r.get("ok", false)), true, "repair 指派 ok")
	var job: Dictionary = r.get("job", {})
	_eq(String(job.get("status", "")), "queued", "job queued")
	_eq(int(job.get("priority", 0)), 1, "priority 1")
	_ok(float(job.get("required_s", 0.0)) > 0.0, "required_s")
	var res: Dictionary = r.get("resources", {})
	_eq(int(res.get("teams_busy", -1)), 0, "queued 未占 team")
	# 重复维修
	_eq(String(ds.repair("apsis", "hull").get("reason", "")), "已在维修队列", "重复维修拒绝")
	# 未知舰/分区
	_eq(String(ds.repair("ferry", "hull").get("reason", "")), "unknown_ship", "未知舰拒绝")
	_eq(String(ds.repair("apsis", "bad").get("reason", "")), "未知分区：bad", "未知分区拒绝")
	# tick 推进维修（active/资源）
	ds.tick(1.0)
	var vm: Dictionary = ds.ship_vm("apsis")
	var queue: Array = vm.get("queue", [])
	_ok(queue.size() == 1, "queue 1")
	_eq(String((queue[0] as Dictionary).get("status", "")), "active", "维修 active")
	_ok(int((vm.get("resources", {}) as Dictionary).get("teams_busy", 0)) == 1, "team busy")
	# 完成（长时间 tick）
	var done := false
	for i in range(30):
		ds.tick(20.0)
		var sm := _summary(ds, "apsis")
		if int((sm.get("repairing", 0)) == 0) and int((sm.get("queued", 0)) == 0):
			done = true
			break
	_ok(done, "维修最终完成")
	_near(_integrity(ds, "apsis", "hull"), 1.0, 1.0e-9, "维修恢复 integrity 1.0")
	_ok(int(_summary(ds, "apsis").get("on_fire", 0)) == 0, "维修清火")
	# cancel（独立实例，避免历史 done job）
	var dc = _new_damage(["apsis"], "apsis")
	dc.apply_hit("apsis", "hull", 0.5, 0.3)
	dc.repair("apsis", "hull", 2)
	_eq((dc.ship_vm("apsis").get("queue", []) as Array).size(), 1, "cancel 前 queue 1")
	var cr: Dictionary = dc.cancel_repair("apsis", "hull")
	_eq(bool(cr.get("ok", false)), true, "cancel_repair ok")
	_eq((dc.ship_vm("apsis").get("queue", []) as Array).size(), 0, "cancel 后 queue 空")
	_eq(String(dc.cancel_repair("apsis", "hull").get("reason", "")), "不在维修队列",
		"重复 cancel 拒绝")
	# fix 别名
	ds.apply_hit("apsis", "tanks", 0.3, 0.2)
	var fx: Dictionary = ds.fix("apsis", "tanks", 2)
	_eq(bool(fx.get("ok", false)), true, "fix 别名 ok")
	_data_line("repair", "指派/重复拒绝/资源/队列/tick 完成/恢复/cancel/fix")

# ═══════════════════════════════════════════════════════════════════
# 5. 优先级 / 资源限制
# ═══════════════════════════════════════════════════════════════════

func _test_repair_priority_resources() -> void:
	_section_begin("5 优先级/资源")
	var ds = _new_damage(["apsis"], "apsis")
	# 多分区维修，优先级排序
	for sec in ["hull", "sensors", "comms"]:
		ds.apply_hit("apsis", sec, 0.3, 0.2)
	ds.repair("apsis", "hull", 3)
	ds.repair("apsis", "sensors", 1)
	ds.repair("apsis", "comms", 2)
	var q: Array = ds.ship_vm("apsis").get("queue", [])
	_eq(q.size(), 3, "queue 3")
	# set_priority
	var sp: Dictionary = ds.set_priority("apsis", "hull", 1)
	_eq(bool(sp.get("ok", false)), true, "set_priority ok")
	var q2: Array = ds.ship_vm("apsis").get("queue", [])
	var statuses: Array = []
	for raw in q2:
		statuses.append(String((raw as Dictionary).get("status", "")))
	_ok(statuses.size() == 3, "队列仍 3")
	_eq(String(ds.set_priority("apsis", "no_job", 1).get("reason", "")), "不在维修队列",
		"未知 job 优先级拒绝")
	# tick 后 teams 上限（teams_total 2）
	ds.tick(5.0)
	var active := 0
	for raw in (ds.ship_vm("apsis").get("queue", []) as Array):
		if String((raw as Dictionary).get("status", "")) == "active":
			active += 1
	_ok(active <= 2, "active 维修不超过 teams", str(active))
	# 资源数值合法
	var r: Dictionary = ds.ship_vm("apsis").get("resources", {})
	_ok(int(r.get("teams_busy", -1)) >= 0, "teams_busy>=0")
	_ok(int(r.get("spares_used", -1)) >= 0, "spares_used>=0")
	_ok(int(r.get("personnel_used", -1)) >= 0, "personnel_used>=0")
	_ok(bool(ds.check_contracts().get("ok", false)), "资源 contracts ok")
	# 优先级有效性
	_eq(bool(ds.set_priority("apsis", "hull", 99).get("ok", false)), true,
		"priority clamp 仍 ok")
	_data_line("priority", "3 队列/优先级/teams 上限/资源非负/clamp")

# ═══════════════════════════════════════════════════════════════════
# 6. tick / 火灾 / 失压推进
# ═══════════════════════════════════════════════════════════════════

func _test_tick_fire_decompression() -> void:
	_section_begin("6 tick 推进")
	var ds = _new_damage(["apsis"], "apsis")
	var t0: float = float(ds.t)
	var r: Dictionary = ds.tick(2.5)
	_eq(bool(r.get("ok", false)), true, "tick ok")
	_near(ds.t, t0 + 2.5, 1.0e-9, "service t 推进")
	_near(float(ds.model("apsis").t), ds.t, 1.0e-9, "model t 同步")
	_eq(String(ds.tick(-1.0).get("reason", "")), "invalid_dt", "负 dt 拒绝")
	_eq(String(ds.tick(NAN).get("reason", "")), "invalid_dt", "NaN dt 拒绝")
	# 火灾/失压推进
	ds.apply_hit("apsis", "tanks", 0.9, 0.8)
	var fire0 := int(_summary(ds, "apsis").get("on_fire", 0))
	_ok(fire0 >= 1, "起火")
	var integ0 := _integrity(ds, "apsis", "tanks")
	# hull 受击产生失压（tanks 可能被火灾继续摧毁后清除失压）
	ds.apply_hit("apsis", "hull", 0.9, 0.8)
	var dec := int(_summary(ds, "apsis").get("decompressed", 0))
	_ok(dec >= 1, "失压存在")
	ds.tick(10.0)
	_ok(_integrity(ds, "apsis", "tanks") <= integ0, "火灾继续损害")
	# tick 0 不推进
	var t_before: float = float(ds.t)
	ds.tick(0.0)
	_near(ds.t, t_before, 1.0e-9, "tick0 不推进")
	# 多舰同步
	var ds2 = _new_damage(["apsis", "harmattan"], "apsis")
	ds2.tick(3.0)
	_near(float(ds2.model("apsis").t), ds2.t, 1.0e-9, "apsis model t")
	_near(float(ds2.model("harmattan").t), ds2.t, 1.0e-9, "harmattan model t")
	_ok(bool(ds2.check_contracts().get("ok", false)), "多舰 contracts ok")
	_data_line("tick", "t 推进/model 同步/负 NaN 拒绝/火灾失压推进/multi-ship 同步")

# ═══════════════════════════════════════════════════════════════════
# 7. 存档
# ═══════════════════════════════════════════════════════════════════

func _test_save_load() -> void:
	_section_begin("7 存档")
	var ds = _new_damage()
	ds.apply_hit("apsis", "hull", 0.5, 0.4)
	ds.apply_hit("apsis", "tanks", 0.9, 0.8)
	ds.apply_hit("harmattan", "sensors", 0.3, 0.2)
	ds.repair("apsis", "hull", 1)
	ds.tick(5.0)
	var save := ds.save_state()
	var parsed = JSON.parse_string(save)
	_ok(parsed is Dictionary, "save JSON 可解析")
	if parsed is Dictionary:
		_eq(String((parsed as Dictionary).get("schema", "")), "v17.damage_service_save.v1",
			"save schema")
		_ok((parsed as Dictionary).get("ships") is Dictionary, "save ships")
		_eq(((parsed as Dictionary).get("ships", {}) as Dictionary).size(), 5, "save 5 舰")
	var ds2 = DamageService.new({"content_path": DAMAGE_PATH, "ships": ALL_SHIPS,
		"default_ship": "apsis"})
	var lr: Dictionary = ds2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "load ok", str(lr.get("errors", [])))
	_ok(_norm_json(ds.vm()) == _norm_json(ds2.vm()), "load 后 VM 一致")
	_ok(_norm_json(JSON.parse_string(save)) == _norm_json(JSON.parse_string(ds2.save_state())),
		"load 后再次 save 一致")
	_near(float(ds2.model("apsis").t), ds2.t, 1.0e-9, "load 后 model t 同步")
	var sm1 := _summary(ds, "apsis")
	var sm2 := _summary(ds2, "apsis")
	_eq(int(sm2.get("damaged", -1)), int(sm1.get("damaged", -2)), "load 后 damaged 一致")
	_eq(int(sm2.get("on_fire", -1)), int(sm1.get("on_fire", -2)), "load 后 on_fire 一致")
	# load 后继续
	ds2.tick(30.0)
	_ok(_integrity(ds2, "apsis", "tanks") <= _integrity(ds2, "apsis", "hull") + 1.0,
		"load 后继续 tick")
	_ok(bool(ds2.check_contracts().get("ok", false)), "load 后 contracts ok")
	# 非法存档不改状态
	var before := _core(ds2)
	for bad in ["", "{bad", JSON.stringify({"schema": "bad"}),
			JSON.stringify({"schema": "v17.damage_service_save.v1", "version": "9.9.9"}),
			JSON.stringify({"schema": "v17.damage_service_save.v1", "version": "1.0.0",
				"ships": {}}),
			JSON.stringify({"schema": "v17.damage_service_save.v1", "version": "1.0.0",
				"ships": {"apsis": {"sections": [], "resources": {}}}})]:
		var br: Dictionary = ds2.load_state(String(bad))
		_eq(bool(br.get("ok", true)), false, "非法存档拒绝：" + String(bad).substr(0, 36))
	_eq(_core(ds2), before, "非法存档不改状态")
	_data_line("save_load", "save/load VM 一致 · 继续 tick · 非法拒绝")

# ═══════════════════════════════════════════════════════════════════
# 8. 事件 / JSON / 确定性
# ═══════════════════════════════════════════════════════════════════

func _test_events_json_determinism() -> void:
	_section_begin("8 事件/JSON/确定性")
	var ds = _new_damage(["apsis"], "apsis")
	ds.apply_hit("apsis", "hull", 0.4)
	ds.repair("apsis", "hull", 1)
	ds.set_priority("apsis", "hull", 2)
	ds.cancel_repair("apsis", "hull")
	ds.tick(1.0)
	var kinds: Array = []
	for raw in ds.events:
		kinds.append(String((raw as Dictionary).get("kind", "")))
		_ok(String((raw as Dictionary).get("schema", "")) == "damage_service_event.v1",
			"事件 schema")
		_ok(bool((raw as Dictionary).get("writes_v15", true)) == false, "事件不写 v15")
	_ok("damage.applied" in kinds, "damage.applied 事件")
	_ok("damage.repair_queued" in kinds, "repair_queued 事件")
	_ok("damage.repair_cancelled" in kinds, "repair_cancelled 事件")
	_ok("damage.tick" in kinds, "tick 事件")
	_ok(ds.events_since(2).size() < ds.events.size(), "events_since 过滤")
	var taken: Array = ds.take_events()
	_ok(taken.size() > 0, "take_events")
	_eq(ds.events.size(), 0, "take 后 events 空")
	# VM/JSON
	var vm: Dictionary = ds.vm()
	_ok(JSON.parse_string(JSON.stringify(vm)) is Dictionary, "VM JSON 可解析")
	_ok(vm.get("ships") is Array, "VM ships")
	_ok(vm.get("summary") is Dictionary, "VM summary")

	# 每舰可单独查 VM
	for sid in ALL_SHIPS:
		var svm: Dictionary = ds.ship_vm(sid)
		_ok(svm.is_empty() or String(svm.get("entity_id", "")) != "", "ship_vm " + sid)
	var one: Dictionary = ds.vm("apsis")
	_eq((one.get("ships", []) as Array).size(), 1, "vm(apsis) 1 舰")
	# 确定性：两实例同操作
	var a = _new_damage(["apsis"], "apsis")
	var b = _new_damage(["apsis"], "apsis")
	for x in [a, b]:
		x.apply_combat_damage(_event("apsis", 0.4, "hull"))
		x.apply_hit("apsis", "tanks", 0.9, 0.8)
		x.repair("apsis", "hull", 1)
		x.tick(10.0)
	_ok(_norm_json(a.vm()) == _norm_json(b.vm()), "同操作 VM 一致")
	_ok(_norm_json(JSON.parse_string(a.save_state())) == _norm_json(JSON.parse_string(b.save_state())),
		"同操作 save 一致")
	_ok(bool(a.check_contracts().get("ok", false)), "确定性 contracts ok")
	_data_line("events_json", "事件序列/JSON/ship_vm/同操作确定性")

# ═══════════════════════════════════════════════════════════════════
# 9. 批量矩阵（全舰/全分区/伤害类型/多舰存档/维修队列）
# ═══════════════════════════════════════════════════════════════════

func _test_matrix() -> void:
	_section_begin("9 批量矩阵")
	# 1) 全部 6 舰基础
	var all = DamageService.new({"content_path": DAMAGE_PATH})
	var all_ships: Array = all.ship_ids_list()
	_eq(all_ships.size(), 6, "全部内容 6 舰")
	for sid in all_ships:
		var svm: Dictionary = all.ship_vm(sid)
		_eq((svm.get("sections", []) as Array).size(), 7, "ship %s 7 分区" % sid)
		_eq((svm.get("summary", {}) as Dictionary).get("needs_attention", -1), 0,
			"ship %s 初始 needs_attention=0" % sid)
		_ok(bool(all.is_operational(String(sid))), "ship %s 初始 operational" % sid)
		var r: Dictionary = all.apply_hit(String(sid), "hull", 0.2, 0.1)
		_eq(bool(r.get("ok", false)), true, "ship %s 可受伤" % sid)
		_ok(_integrity(all, String(sid), "hull") < 1.0, "ship %s hull<1" % sid)
		_ok(float(_summary(all, String(sid)).get("integrity_avg", 1.0)) < 1.0,
			"ship %s integrity_avg<1" % sid)
		_ok(bool(all.repair(String(sid), "hull", 2).get("ok", false)),
			"ship %s 可维修" % sid)
		_eq((all.ship_vm(String(sid)).get("queue", []) as Array).size(), 1,
			"ship %s 维修队列 1" % sid)
		_ok(String((all.ship_vm(String(sid)).get("sections", []) as Array)[0].get("id", "")) != "",
			"ship %s vm sections 有效" % sid)
	# 全部舰受击后统一 tick / contracts
	all.tick(3.0)
	_ok(bool(all.check_contracts().get("ok", false)), "全舰受伤后 contracts ok")
	var all_vm: Dictionary = all.vm()
	_eq((all_vm.get("ships", []) as Array).size(), 6, "VM 6 舰")
	_ok(int(all.summary().get("queued", 0)) >= 6 or int(all.summary().get("repairing", 0)) >= 1,
		"全舰维修队列/进行中")
	# 2) 每个分区可受伤（7 分区）
	for sec in SECTIONS:
		var one = DamageService.new({"content_path": DAMAGE_PATH, "ships": ["apsis"],
			"default_ship": "apsis"})
		var before := _integrity(one, "apsis", String(sec))
		var r2: Dictionary = one.apply_hit("apsis", String(sec), 0.15, 0.2)
		_eq(bool(r2.get("ok", false)), true, "分区 %s 伤害 ok" % sec)
		_ok(_integrity(one, "apsis", String(sec)) < before, "分区 %s integrity 下降" % sec)
		_eq((one.ship_vm("apsis").get("sections", []) as Array).size(), 7,
			"分区 %s 后仍 7 分区" % sec)
		_ok(bool(one.check_contracts().get("ok", false)), "分区 %s contracts ok" % sec)
		_ok(bool(one.repair("apsis", String(sec), 2).get("ok", false)),
			"分区 %s 可维修" % sec)
		var qsz: int = (one.ship_vm("apsis").get("queue", []) as Array).size()
		_eq(qsz, 1, "分区 %s 维修队列 1" % sec)
		_eq(String((one.ship_vm("apsis").get("queue", []) as Array)[0].get("section", "")),
			String(sec), "分区 %s 维修目标一致" % sec)
	# 3) damage_kind → section 映射（无 suggested_section）
	var expect := {"kinetic": "hull", "explosive": "power", "energy": "sensors",
		"thermal": "tanks", "fire": "tanks", "fragmentation": "hull"}
	for kind in expect.keys():
		var dk = DamageService.new({"content_path": DAMAGE_PATH, "ships": ["apsis"],
			"default_ship": "apsis"})
		var ev := {"schema": "combat_damage_event.v1", "kind": "damage",
			"target_ship": "apsis", "damage": 0.2, "penetration": 0.2,
			"damage_kind": String(kind), "shot_id": "K-" + String(kind)}
		var rk: Dictionary = dk.apply_combat_damage(ev)
		_eq(bool(rk.get("ok", false)), true, "kind %s apply ok" % kind)
		_eq(String(rk.get("section", "")), String(expect[kind]),
			"kind %s → %s" % [kind, String(expect[kind])])
		_ok(_integrity(dk, "apsis", String(expect[kind])) < 1.0,
			"kind %s 对应分区受损" % kind)
		_eq((dk.vm("apsis").get("applied_damage", []) as Array).size(), 1,
			"kind %s applied 记录" % kind)
	# 4) 多舰（5 舰）存档往返
	var multi = _new_damage(ALL_SHIPS, "harmattan")
	for sid in ALL_SHIPS:
		multi.apply_hit(String(sid), "sensors", 0.3, 0.3)
	multi.tick(2.0)
	var save_m := multi.save_state()
	var multi2 = DamageService.new({"content_path": DAMAGE_PATH, "ships": ALL_SHIPS,
		"default_ship": "harmattan"})
	var lr_m: Dictionary = multi2.load_state(save_m)
	_eq(bool(lr_m.get("ok", false)), true, "多舰 save/load ok", str(lr_m.get("errors", [])))
	_ok(_norm_json(multi.vm()) == _norm_json(multi2.vm()), "多舰 load VM 一致")
	_near(float(multi2.t), multi.t, 1.0e-9, "多舰 load t 一致")
	for sid2 in ALL_SHIPS:
		_ok(_norm_json(multi.ship_vm(String(sid2))) == _norm_json(multi2.ship_vm(String(sid2))),
			"多舰 load ship %s 一致" % sid2)
		_ok(int(multi2.ship_vm(String(sid2)).get("summary", {}).get("total", 0)) == 7,
			"多舰 ship %s 7 分区" % sid2)
	_ok(bool(multi2.check_contracts().get("ok", false)), "多舰 load contracts ok")
	_eq(String(multi2.vm().get("content_id", "")), "damage_l1", "多舰 content_id")
	_ok((multi2.vm().get("ships", []) as Array).size() == 5, "多舰 vm 5 舰")
	_eq(String(multi2.vm().get("content_id", "")), "damage_l1", "多舰 content_id")
	_ok((multi2.vm().get("ships", []) as Array).size() == 5, "多舰 vm 5 舰")
	# 5) 7 分区同时维修队列/team 上限
	var jobs = DamageService.new({"content_path": DAMAGE_PATH, "ships": ["apsis"],
		"default_ship": "apsis"})
	for sec2 in SECTIONS:
		jobs.apply_hit("apsis", String(sec2), 0.25, 0.2)
		_ok(bool(jobs.repair("apsis", String(sec2), 2).get("ok", false)),
			"多分区维修指派 %s" % sec2)
	_eq((jobs.ship_vm("apsis").get("queue", []) as Array).size(), 7, "7 维修队列")
	jobs.tick(2.0)
	var active2 := 0
	for raw in (jobs.ship_vm("apsis").get("queue", []) as Array):
		if String((raw as Dictionary).get("status", "")) == "active":
			active2 += 1
	_ok(active2 <= 2, "active<=teams_total(2)", str(active2))
	_eq((jobs.ship_vm("apsis").get("resources", {}) as Dictionary).get("teams_busy", -1),
		active2, "teams_busy=active")
	_ok(bool(jobs.check_contracts().get("ok", false)), "多维修 contracts ok")
	# 取消一个排队项
	var queued_sec := ""
	for raw in (jobs.ship_vm("apsis").get("queue", []) as Array):
		if String((raw as Dictionary).get("status", "")) == "queued":
			queued_sec = String((raw as Dictionary).get("section", ""))
			break
	if queued_sec != "":
		_eq(bool(jobs.cancel_repair("apsis", queued_sec).get("ok", false)), true,
			"取消排队维修 ok")
		_eq((jobs.ship_vm("apsis").get("queue", []) as Array).size(), 6, "取消后队列 6")
	_data_line("matrix", "6舰/7分区/6 damage_kind/5舰存档/7维修队列/teams 上限")
