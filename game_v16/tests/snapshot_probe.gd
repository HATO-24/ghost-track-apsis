extends SceneTree

## GHOST TRACK / APSIS · V2-SENSOR-3 headless probe（真实轨道预测 / 站体快照）
##
## 验证 sim/tactical_snapshot.gd：
##   1) 真实 V2 场景 → world（9 实体 / 10 接触：7 舰 + chronos_station + tank_farm + 无实体 9002）；
##   2) build()：接触局部坐标/屏幕建议/L级/身份/威胁；雷达球 R_eff；TWS 通道；光学/IR；暴露；
##   3) 位置/预测来自 Orbit.local_propagate_rk4（非 r+v·t 线性），预测点列 30/60/120 s，
##      真实轨道 vs 线性外推误差可测；taylor/rk4 两种传播器；time_s 覆盖；
##   4) 固定设施：station/tank 的 kind/icon/size_km/marker、fixed 不推进（static_fixed）、
##      prediction 点列退化但存在；无实体 9002 方位线不伪造位置/预测；
##   5) step()：推进 sim 模型、返回观测建议，world 不变；失锁降级；JSON 可序列化。
##
## 运行（工作区根目录）：
##   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
##       --path .\game_v16 --script res://tests/snapshot_probe.gd
## 期望末行 V2 SENSOR-3 SNAPSHOT PROBE PASS，退出码 0。
## 日志：game_v16/tests/snapshot_probe.log

const Types := preload("res://sim/sensor_types.gd")
const TacticalSnapshot := preload("res://sim/tactical_snapshot.gd")
const Orbit := preload("res://scripts/orbit_model.gd")
const ScenarioScript := preload("res://core/scenario.gd")
const WorldScript := preload("res://core/world.gd")

const SCENARIO := "res://content/scenario_l1_v2.json"
const BASE_IDS := ["1000", "1001", "1002", "1003", "1004", "2001", "9001", "9002"]
const FACILITY_IDS := ["0100", "0101"]

var ok := true
var pass_count := 0
var fail_count := 0


func _initialize() -> void:
	print("==== V2 SENSOR-3 SNAPSHOT PROBE · GHOST TRACK / APSIS ====")
	print("[SRC] sim/tactical_snapshot.gd × scripts/orbit_model.gd(local_propagate/RK4) × core/{scenario,world}")
	_run()
	print("")
	print("[SUMMARY] pass=%d fail=%d" % [pass_count, fail_count])
	if ok:
		print("V2 SENSOR-3 SNAPSHOT PROBE PASS")
	else:
		print("V2 SENSOR-3 SNAPSHOT PROBE FAIL")
	quit(0 if ok else 1)


func check(cond: bool, label: String, detail: String = "") -> bool:
	if cond:
		pass_count += 1
		print("[PASS] ", label, ("  " + detail) if detail != "" else "")
	else:
		ok = false
		fail_count += 1
		print("[FAIL] ", label, ("  " + detail) if detail != "" else "")
	return cond


# ═══════════════════════════════════════════════════════════════════
# 工具
# ═══════════════════════════════════════════════════════════════════

func _script_ready(script: Variant) -> bool:
	return script is GDScript and (script as GDScript).can_instantiate()


func _find_contact(contacts: Array, track_id: String) -> Dictionary:
	for raw in contacts:
		if raw is Dictionary and String((raw as Dictionary).get("track_id", "")) == track_id:
			return raw
	return {}


func _dist2(a: Variant, b: Variant) -> float:
	return Types.to_vec3(a).distance_to(Types.to_vec3(b))


func _events_of(all_events: Array, kind: String) -> Array:
	var out: Array = []
	for raw in all_events:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			out.append(raw)
	return out


func _json_ok(value: Variant) -> bool:
	var txt := JSON.stringify(value)
	return txt.length() > 2 and not txt.contains("<Object")


func _pred_point(pred: Dictionary, dt_s: float) -> Dictionary:
	for raw in (pred.get("points", []) as Array):
		if raw is Dictionary and absf(float((raw as Dictionary).get("dt_s", -1.0)) - dt_s) < 1.0e-6:
			return raw
	return {}


func _entity_orbit(entity) -> Dictionary:
	if entity == null:
		return {}
	return entity.orbit.duplicate(true)


func _run() -> void:
	# 并发编辑保护：core 脚本若正在被其它任务改写，明确判 FAIL 而不是静默中断。
	var scenario_script_check: Variant = load("res://core/scenario.gd")
	var world_script_check: Variant = load("res://core/world.gd")
	if not _script_ready(scenario_script_check) or not _script_ready(world_script_check):
		check(false, "core/{scenario,world}.gd 未通过编译（可能正被并发编辑，稍后重跑）",
			"world_ok=%s" % str(_script_ready(world_script_check)))
		return

	# ═══════════════════════════════════════════════════════════════
	# 1. 真实场景装载（9 实体 / 10 接触）
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 1. 真实场景 → world（9 实体 / 10 接触）──")
	var scenario = ScenarioScript.load_file(SCENARIO)
	check(scenario.errors.is_empty(), "scenario.v2 装载无错误", str(scenario.errors))
	var world = WorldScript.new()
	var loaded: bool = world.load_scenario(scenario)
	check(loaded and world.errors.is_empty(), "world 装载 ok", "errors=%s" % str(world.errors))
	var contacts_before: Array = world.vm_contacts()
	var expected_contacts := int(world.vm_state().get("track_count", -1))
	var expected_entities: int = world.entities.size()
	check(contacts_before.size() == expected_contacts and expected_contacts == 10,
		"world 10 条接触（7 舰 + 站体 + 储罐 + 9002）",
		"n=%d track_count=%d" % [contacts_before.size(), expected_contacts])
	check(expected_entities == 9, "world 9 实体（含 fixed 设施）", "entities=%d" % expected_entities)
	var ids: Array = []
	for raw in contacts_before:
		ids.append(String((raw as Dictionary).get("track_id", "")))
	var missing: Array = []
	for wanted in BASE_IDS + FACILITY_IDS:
		if not ids.has(wanted):
			missing.append(wanted)
	check(missing.is_empty(), "接触含原有 8 条 + 固定设施 0100/0101", "missing=%s" % str(missing))
	check(String(world.own_id) == "harmattan", "own = 哈马丹")
	var world_t0 := float(world.t)
	var state0: Dictionary = world.vm_state()

	# ═══════════════════════════════════════════════════════════════
	# 2. make_sim_state
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 2. make_sim_state：雷达/TWS/光学模型装配 ──")
	var sim: Dictionary = TacticalSnapshot.make_sim_state(world, {})
	check(String(sim.get("schema", "")) == "tactical_sim_state.v1", "sim_state schema")
	check(String(sim.get("observer_id", "")) == "harmattan", "observer = 哈马丹")
	var sim_radar = sim.get("radar", null)
	var sim_tws = sim.get("tws", null)
	var sim_opt = sim.get("optical", null)
	check(sim_radar != null and sim_tws != null and sim_opt != null, "radar/tws/optical 实例就绪")
	check(sim_radar == sim_tws.radar, "TWS 与雷达共享同一实例（扫描节奏一致）")
	check(String(sim_radar.record.model) == "YW-R9", "雷达 YW-R9")
	check(int(sim_tws.max_channels) == 6, "TWS 通道 6")
	check(sim_opt.has_sensor("optical") and sim_opt.has_sensor("ir"), "光学 MS-OT2 + 红外 CH-IR2")

	# ═══════════════════════════════════════════════════════════════
	# 3. build()：轨道传播 / 预测 / 站体元数据 / 球 / 通道
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 3. build()：真实轨道传播 + 预测点列 + station/tank 元数据 ──")
	var snap: Dictionary = TacticalSnapshot.build(world, sim, {})
	check(String(snap.get("schema", "")) == "tactical_snapshot.v1", "快照 schema")
	check(not bool(snap.get("drawable", true)), "纯数据：drawable=false（不做渲染）")
	check(absf(float(snap.get("t", -1.0)) - world_t0) < 1.0e-6, "快照 t = world.t")
	check(String(snap.get("orbit_source", "")) == "local_propagate",
		"orbit_source = local_propagate（需求 §3）", String(snap.get("orbit_source", "")))
	check(String(snap.get("propagator", "")) == "rk4", "默认传播器 rk4")
	var horizons: Array = snap.get("prediction_horizons_s", [])
	check(horizons == [30.0, 60.0, 120.0], "预测点列 30/60/120 s", str(horizons))

	# 本舰：真实轨道传播 + 预测
	var own: Dictionary = snap.get("own", {})
	var own_r: Array = own.get("local_r_km", [])
	check(String(own.get("id", "")) == "harmattan", "own = 哈马丹")
	check(own_r.size() == 3 and absf(float(own_r[0]) - 2.0) < 1.0e-6
		and absf(float(own_r[1]) + 3.0) < 1.0e-6, "own 坐标（t=0 → epoch）", str(own_r))
	check(String(own.get("orbit_source", "")) == "local_propagate", "own orbit_source=local_propagate")
	check(String(own.get("propagator", "")) == "rk4", "own propagator=rk4")
	check((own.get("epoch_r_km", null) is Array) and (own.get("epoch_v_kmps", null) is Array),
		"own 带 epoch r/v")
	var own_screen: Dictionary = own.get("screen", {})
	check(bool(own_screen.get("inside", false))
		and absf(float(own_screen.get("x", -1.0)) - 980.0) < 1.0e-6
		and absf(float(own_screen.get("y", -1.0)) - 500.0) < 1.0e-6,
		"投影建议：本舰在地图像素中心（980,500）")
	var own_pred: Dictionary = own.get("prediction", {})
	check((own_pred.get("points", []) as Array).size() == 3,
		"own 预测点 3 个（30/60/120 s）")
	var own_p30 := _pred_point(own_pred, 30.0)
	var own_p60 := _pred_point(own_pred, 60.0)
	var own_p120 := _pred_point(own_pred, 120.0)
	check(not own_p30.is_empty() and not own_p60.is_empty() and not own_p120.is_empty(),
		"own 预测点 dt_s 覆盖 30/60/120")
	check((own_p120.get("screen", {}) as Dictionary).has("x")
		and (own_p120.get("view_r_km", []) as Array).size() == 3,
		"预测点带 view_r_km + screen 投影建议")
	check(float(own_p120.get("sigma_km", 0.0)) > 0.0, "预测点带 σ（Orbit.sigma_km）",
		"σ120=%.2f km" % float(own_p120.get("sigma_km", 0.0)))

	# 真实传播 vs 线性外推（r+v·t）误差：本舰 120 s（v≈0.22,-0.12,0.03 km/s）
	var own_epoch := _entity_orbit(world.entity("harmattan"))
	var epoch_r := Types.to_vec3(own_epoch.get("r", []))
	var epoch_v := Types.to_vec3(own_epoch.get("v", []))
	var pred_abs := Types.to_vec3(own_p120.get("local_r_km", []))
	var linear_abs := epoch_r + epoch_v * 120.0
	var real_rk4: Dictionary = Orbit.local_propagate_rk4(epoch_r, epoch_v, 120.0)
	var rk4_abs: Vector3 = real_rk4.get("r", epoch_r)
	var linear_err := pred_abs.distance_to(linear_abs)
	var direct_err := pred_abs.distance_to(rk4_abs)
	check(direct_err < 1.0e-6, "预测点与 Orbit.local_propagate_rk4 直接计算一致",
		"err=%s km" % str(direct_err))
	check(linear_err > 1.0e-4 and linear_err < 5.0,
		"真实轨道 vs 线性外推误差可测（L1 局部相对运动）",
		"|rk4 - (r+v·t)|=%.4f km" % linear_err)
	var taylor_120: Dictionary = Orbit.local_propagate(epoch_r, epoch_v, 120.0)
	var taylor_vs_rk4 := (taylor_120.get("r", epoch_r) as Vector3).distance_to(rk4_abs)
	check(taylor_vs_rk4 < 0.05, "taylor 与 rk4 在 120 s 内一致",
		"diff=%s km" % str(taylor_vs_rk4))

	# 接触行（10 条）
	var contacts: Array = snap.get("contacts", [])
	var counts: Dictionary = snap.get("counts", {})
	# 有位置显示的实体接触 = L2+ 实体接触（L1 的 2001/9001 仍只有方位线）。
	var expected_positioned := 0
	for raw_c in contacts:
		if raw_c is Dictionary and bool((raw_c as Dictionary).get("has_entity", false)) \
				and not bool((raw_c as Dictionary).get("bearing_only", false)):
			expected_positioned += 1
	check(contacts.size() == expected_contacts, "快照接触 = world 航迹数",
		"n=%d" % contacts.size())
	check(int(counts.get("entities", 0)) == expected_entities, "有实体接触 = 实体数",
		"n=%d" % int(counts.get("entities", 0)))
	check(int(counts.get("no_entity", 0)) == 1, "无实体接触仍只有 9002")
	check(int(counts.get("bearing_only", 0)) == 3, "3 条纯方位接触（2001/9001/9002）")
	check(int(counts.get("stations", 0)) == 1 and int(counts.get("tanks", 0)) == 1,
		"站体/储罐各 1 条（含在 contacts 中）",
		"stations=%d tanks=%d" % [int(counts.get("stations", 0)), int(counts.get("tanks", 0))])
	check(int(counts.get("predicted", 0)) == expected_positioned,
		"有位置的实体接触均带预测点列（%d 条）" % expected_positioned,
		"predicted=%d" % int(counts.get("predicted", 0)))
	check(int(counts.get("in_radar_sphere", 0)) == expected_positioned,
		"全部有位置接触在雷达球内（含站体/储罐）",
		"n=%d" % int(counts.get("in_radar_sphere", 0)))

	# 原有 8 条接触行为保持：1000 友军 / 2001 L1 方位线 / 9002 无实体
	var apsis := _find_contact(contacts, "1000")
	check(String(apsis.get("position_source", "")) == "propagated_orbit",
		"1000（L4）position_source=propagated_orbit", String(apsis.get("position_source", "")))
	check(String(apsis.get("orbit_source", "")) == "local_propagate"
		and String(apsis.get("propagator", "")) == "rk4",
		"1000 orbit_source/propagator 标注")
	check(String(apsis.get("kind", "")) == "ship" and String(apsis.get("icon", "")) == "chevron",
		"1000 kind=ship / icon=chevron")
	check(absf(float(apsis.get("size_km", 0.0)) - 0.6) < 1.0e-6, "1000 size_km=0.6（catalog）")
	check(bool((apsis.get("screen", {}) as Dictionary).get("inside", false)),
		"1000 屏幕在 MAP 区内")
	check(bool(apsis.get("in_radar_sphere", false)), "1000 在雷达球内")
	var ap_pred: Dictionary = apsis.get("prediction", {})
	check((ap_pred.get("points", []) as Array).size() == 3, "1000 预测点 3 个")
	var ap120 := _pred_point(ap_pred, 120.0)
	check(not ap120.is_empty() and (ap120.get("screen", {}) as Dictionary).has("x"),
		"1000 预测 120 s 点带屏幕建议")
	check(float(ap120.get("sigma_km", 0.0)) > float(_pred_point(ap_pred, 30.0).get("sigma_km", 0.0)),
		"预测 σ 随预测时长增长")

	var c2001 := _find_contact(contacts, "2001")
	check(String(c2001.get("position_source", "")) == "bearing_line"
		and String(c2001.get("orbit_source", "")) == "none",
		"2001（L1）只给方位线、orbit_source=none（不泄露真位置）")
	check((c2001.get("prediction", {}) as Dictionary).is_empty(),
		"2001 无位置 → 不伪造轨道预测")
	var rendered_range := _dist2(c2001.get("local_r_km", []), own_r)
	var truth_geom: Dictionary = Types.geometry_km(
		Types.to_vec3(own_r), Types.to_vec3(world.entity("summons_4471").orbit))
	var truth_range: float = float(truth_geom.get("range_km", -1.0))
	check(absf(rendered_range - 450.0) < 1.5 and absf(rendered_range - truth_range) > 10.0,
		"2001 显示端点=方位线 450 km（非实体真位置）", "rendered=%.1f truth=%.1f" %
		[rendered_range, truth_range])

	var phantom := _find_contact(contacts, "9002")
	check(not bool(phantom.get("has_entity", true))
		and String((phantom.get("marker", {}) as Dictionary).get("shape", "")) == "phantom",
		"9002 无实体 / marker=phantom")
	check(absf(float((phantom.get("bearing_line", {}) as Dictionary).get("bearing_deg", -1.0)) - 302.0) < 1.0e-6,
		"9002 方位线 302°（种子数据）")
	check((phantom.get("prediction", {}) as Dictionary).is_empty(),
		"9002 方位线不伪造位置/预测")

	# 固定设施：station / tank（V2-CORE-3 content）
	var station := _find_contact(contacts, "0100")
	var tank := _find_contact(contacts, "0101")
	check(String(station.get("kind", "")) == "station" and bool(station.get("is_station", false)),
		"0100 = station 站体", String(station.get("name", "")))
	check(String((station.get("marker", {}) as Dictionary).get("shape", "")) == "station",
		"0100 marker=station")
	check(absf(float(station.get("size_km", 0.0)) - 1.2) < 1.0e-6,
		"0100 size_km=1.2（meta 覆盖）", "size=%.1f" % float(station.get("size_km", 0.0)))
	check(bool(station.get("fixed", false)), "0100 fixed=true")
	check(String(station.get("orbit_source", "")) == "static_fixed"
		and String(station.get("propagator", "")) == "none",
		"0100 固定设施不推进（orbit_source=static_fixed）",
		String(station.get("orbit_source", "")))
	check(absf(_dist2(station.get("local_r_km", []), [180.0, 210.0, 8.0])) < 1.0e-6,
		"0100 位置 = L1 固定点 [180,210,8]")
	check(String(station.get("position_source", "")) == "fixed_orbit",
		"0100 position_source=fixed_orbit（固定设施位置）",
		String(station.get("position_source", "")))
	var station_pred: Dictionary = station.get("prediction", {})
	check((station_pred.get("points", []) as Array).size() == 3 and bool(station_pred.get("fixed", false)),
		"0100 预测点列存在且 fixed=true（退化点，不伪造推进）")
	var sp120 := _pred_point(station_pred, 120.0)
	check(not sp120.is_empty()
		and absf(_dist2(sp120.get("local_r_km", []), station.get("local_r_km", []))) < 1.0e-9,
		"0100 预测 120 s 点 = 当前位置（fixed 不推进）")
	check(String(tank.get("kind", "")) == "tank" and bool(tank.get("is_tank", false))
		and String((tank.get("marker", {}) as Dictionary).get("shape", "")) == "tank",
		"0101 = tank 储罐 / marker=tank")
	check(absf(float(tank.get("size_km", 0.0)) - 0.8) < 1.0e-6
		and String(tank.get("orbit_source", "")) == "static_fixed",
		"0101 size_km=0.8 / static_fixed")
	check(String(station.get("identity", "")) == "neutral"
		and String(station.get("threat", "")) == "none",
		"0100 身份 neutral / 威胁 none")

	# 图标目录 / 元数据 API（station/tank 存在性）
	var catalog: Dictionary = snap.get("icon_catalog", {})
	check(catalog.has("ship") and catalog.has("station") and catalog.has("tank")
		and catalog.has("wreck"),
		"icon_catalog 含 ship/station/tank/wreck", str(catalog.keys()))
	var station_visual: Dictionary = TacticalSnapshot.visual_metadata("station",
		{"icon": "station", "size_km": 1.2, "radius_km": 0.7}, ["station", "fixed"])
	check(String(station_visual.get("shape", "")) == "station"
		and bool(station_visual.get("is_station", false))
		and bool(station_visual.get("fixed", false))
		and absf(float(station_visual.get("size_km", 0.0)) - 1.2) < 1.0e-6,
		"visual_metadata(station)：shape/固定设施/size 覆盖")
	var tank_visual: Dictionary = TacticalSnapshot.visual_metadata("tank",
		{"icon": "tank", "radius_km": 0.4}, ["tank", "fixed"])
	check(String(tank_visual.get("shape", "")) == "tank" and bool(tank_visual.get("is_tank", false))
		and absf(float(tank_visual.get("size_km", 0.0)) - 0.8) < 1.0e-6,
		"visual_metadata(tank)：radius_km 换算 size=0.8")
	var entity_visual: Dictionary = TacticalSnapshot.entity_visual(
		{"kind": "station", "meta": {"icon": "station", "size_km": 1.2}, "tags": ["station", "fixed"]})
	check(String(entity_visual.get("kind", "")) == "station"
		and bool(entity_visual.get("fixed", false)),
		"entity_visual(dict 实体) → station/fixed")

	# 传播器切换 / 时间基准覆盖
	var snap_taylor: Dictionary = TacticalSnapshot.build(world, sim, {"propagator": "taylor"})
	check(String(snap_taylor.get("propagator", "")) == "taylor"
		and String(snap_taylor.get("orbit_source", "")) == "local_propagate",
		"cfg.propagator=taylor：仍标 orbit_source=local_propagate")
	var ty_own: Dictionary = snap_taylor.get("own", {})
	var ty120 := _pred_point(ty_own.get("prediction", {}), 120.0)
	check(not ty120.is_empty()
		and _dist2(ty120.get("local_r_km", []), own_p120.get("local_r_km", [])) < 0.05,
		"taylor 与 rk4 预测 120 s 结果一致（<0.05 km）")
	var snap_t120: Dictionary = TacticalSnapshot.build(world, sim, {"time_s": 120.0})
	var own_t120: Array = (snap_t120.get("own", {}) as Dictionary).get("local_r_km", [])
	var expected_t120: Dictionary = Orbit.local_propagate_rk4(epoch_r, epoch_v, 120.0)
	var expected_t120_r: Vector3 = expected_t120.get("r", epoch_r)
	check(_dist2(own_t120, expected_t120_r) < 1.0e-6,
		"cfg.time_s=120：位置传播到 120 s（直接对照 Orbit）",
		"%.2f km" % _dist2(own_t120, expected_t120_r))
	check(_dist2(own_t120, own_r) > 10.0,
		"cfg.time_s=120：位置已移动（非静态快照）", "%.1f km" % _dist2(own_t120, own_r))

	# 雷达球 / 暴露 / TWS / 光学（保持 V2-SENSOR-2 行为）
	var radar: Dictionary = snap.get("radar", {})
	var sphere: Dictionary = radar.get("sphere", {})
	check(bool(radar.get("available", false)) and String(radar.get("model", "")) == "YW-R9",
		"radar 段可用 / YW-R9")
	check(String(sphere.get("shape", "")) == "sphere" and bool(sphere.get("no_sector", false)),
		"雷达球 shape=sphere / no_sector")
	check(absf(float(sphere.get("nominal_radius_km", 0.0)) - 30000.0) < 1.0e-6
		and absf(float(sphere.get("effective_radius_km", 0.0)) - 30000.0) < 1.0e-6,
		"球 R_eff = 30,000 km（RCS=10 m²）")
	check(int(sphere.get("contacts_in_sphere", 0)) == expected_positioned,
		"球内接触数 = 有位置实体接触数（%d，含 fixed 设施）" % expected_positioned)
	var exposure: Dictionary = snap.get("exposure", {})
	check(bool(exposure.get("exposed", false))
		and absf(float(exposure.get("elint_intercept_range_km", 0.0)) - 45000.0) < 1.0,
		"暴露：ELINT 45,000 km")
	var tws_before: Dictionary = snap.get("tws", {})
	check(bool(tws_before.get("available", false)) and int(tws_before.get("channel_count", -1)) == 0,
		"TWS：未捕获前 0 通道")
	check((tws_before.get("state_machine", []) as Array)
		== ["SEARCH", "DETECT", "ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"],
		"TWS 六态枚举")
	var opt_before: Dictionary = snap.get("optical", {})
	check(bool(opt_before.get("available", false))
		and int(opt_before.get("locked_count", -1)) == 0, "光学：未建通道前 0 锁定")
	check((snap.get("layers", {}) as Dictionary).has("contacts"), "layers 图层状态可读")
	check(_json_ok(snap), "快照可 JSON 序列化（含预测点/图标元数据）")
	var snap2: Dictionary = TacticalSnapshot.build(world, sim, {})
	check(JSON.stringify(snap) == JSON.stringify(snap2), "build() 确定性（同输入同输出）")
	var bare: Dictionary = TacticalSnapshot.build(world, {}, {})
	check((bare.get("contacts", []) as Array).size() == expected_contacts,
		"无 sim_state：接触仍输出（9 实体 + 9002）")
	check(not bool((bare.get("radar", {}) as Dictionary).get("available", true)),
		"无 sim_state：radar 段 available=false")
	check(_json_ok(bare), "降级快照可 JSON 序列化")

	# ═══════════════════════════════════════════════════════════════
	# 4. 屏幕投影建议（确定性）
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 4. project_local：屏幕投影建议 / 越界边缘提示 ──")
	var cam: Dictionary = {
		"map_rect": [0.0, 0.0, 1000.0, 1000.0], "yaw_deg": 0.0, "pitch_deg": 0.0,
		"scale_px_per_km": 1.0, "center_mode": "own",
	}
	var east: Dictionary = TacticalSnapshot.project_local([100.0, 0.0, 0.0], cam, [0.0, 0.0, 0.0])
	check(absf(float(east.get("x", 0.0)) - 600.0) < 1.0e-6
		and absf(float(east.get("y", 0.0)) - 500.0) < 1.0e-6 and bool(east.get("inside", false)),
		"东 100 km → (600,500) 中心 + x")
	var north: Dictionary = TacticalSnapshot.project_local([0.0, 100.0, 0.0], cam, [0.0, 0.0, 0.0])
	check(absf(float(north.get("x", 0.0)) - 500.0) < 1.0e-6
		and absf(float(north.get("y", 0.0)) - 400.0) < 1.0e-6, "北 100 km → 屏幕向上")
	var off: Dictionary = TacticalSnapshot.project_local([1000.0, 0.0, 0.0],
		{"map_rect": [0.0, 0.0, 100.0, 100.0], "yaw_deg": 0.0, "pitch_deg": 0.0,
		"scale_px_per_km": 1.0, "center_mode": "own"}, [0.0, 0.0, 0.0])
	check(not bool(off.get("inside", true)) and off.has("edge"), "越界接触给边缘提示 edge")
	var camera: Dictionary = snap.get("camera", {})
	check(bool(camera.get("auto_scale", false)) and float(camera.get("scale_px_per_km", 0.0)) > 0.0,
		"默认相机建议：自动缩放")

	# ═══════════════════════════════════════════════════════════════
	# 5. build_world_snapshot：world → 传感器输入快照（传播后位置）
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 5. build_world_snapshot：传播后的传感器输入 ──")
	var ws: Dictionary = TacticalSnapshot.build_world_snapshot(world, sim, {})
	check((ws.get("targets", []) as Array).size() == expected_entities - 1,
		"目标行 = 实体数 - 本舰", "n=%d" % (ws.get("targets", []) as Array).size())
	check(String(ws.get("orbit_source", "")) == "local_propagate"
		and String(ws.get("propagator", "")) == "rk4",
		"world_snapshot orbit_source/propagator 标注")
	var observer: Dictionary = ws.get("observer", {})
	check(String(observer.get("orbit_source", "")) == "local_propagate",
		"observer 位置来源 local_propagate")
	var ws_station := {}
	var ws_apsis := {}
	for raw in (ws.get("targets", []) as Array):
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		if String(row.get("entity_id", "")) == "chronos_station":
			ws_station = row
		if String(row.get("entity_id", "")) == "apsis":
			ws_apsis = row
	check(not ws_station.is_empty()
		and String(ws_station.get("orbit_source", "")) == "static_fixed"
		and bool(ws_station.get("fixed", false)),
		"站体目标行 static_fixed（传感器用固定位置）")
	check(absf(_dist2(ws_station.get("r", []), [180.0, 210.0, 8.0])) < 1.0e-6,
		"站体目标行 r = 固定点")
	check(not ws_apsis.is_empty()
		and String(ws_apsis.get("orbit_source", "")) == "local_propagate"
		and (ws_apsis.get("epoch_r", null) is Array),
		"舰船目标行 local_propagate + epoch 原值")
	var ws_override: Dictionary = TacticalSnapshot.build_world_snapshot(world, sim, {"sim_targets": []})
	check((ws_override.get("targets", []) as Array).is_empty(),
		"cfg.sim_targets 覆盖钩子（空目标 = 验证失锁）")

	# ═══════════════════════════════════════════════════════════════
	# 6. step()：观测建议 / world 只读
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 6. step()：观测建议 / 通道更新 / world 只读 ──")
	var start_opt: Dictionary = TacticalSnapshot.start_channel(sim, "optical", "2001")
	var start_ir: Dictionary = TacticalSnapshot.start_channel(sim, "ir", "9001")
	check(bool(start_opt.get("ok", false)) and bool(start_ir.get("ok", false)),
		"建立光学/IR 凝视通道")
	var world_obs_2001_before := int(world.track_for("2001").observation_count)
	var level_2001_before := int(world.track_for("2001").level)
	var cfg: Dictionary = {"sim_state": sim, "camera": {"scale_px_per_km": 0.8}}
	var total_channel_updates: Array = []
	var steps_with_radar := 0
	var steps_with_tws := 0
	var max_radar_obs := 0
	var step_out: Dictionary = {}
	for i in range(28):
		step_out = TacticalSnapshot.step(world, 1.0, cfg)
		if not bool(step_out.get("ok", false)):
			check(false, "step 第 %d 步失败" % (i + 1), String(step_out.get("reason", "")))
			break
		if bool(step_out.get("world_modified", true)):
			check(false, "step 不得修改 world")
			break
		var radar_n := (step_out.get("radar_observations", []) as Array).size()
		if radar_n > 0:
			steps_with_radar += 1
			max_radar_obs = maxi(max_radar_obs, radar_n)
		if (step_out.get("tws_observations", []) as Array).size() > 0:
			steps_with_tws += 1
		total_channel_updates.append_array(step_out.get("channel_updates", []))
	check(String(step_out.get("schema", "")) == "tactical_step.v1", "step schema")
	check(step_out.get("world_modified", true) == false, "step 声明 world_modified=false")
	check(steps_with_radar >= 4, "雷达扫描帧 ≥4（6 s 刷新）", "frames=%d" % steps_with_radar)
	check(steps_with_tws >= 10, "TWS 活跃观测建议持续输出", "steps=%d" % steps_with_tws)
	check(absf(float(sim.get("time", 0.0)) - 28.0) < 1.0e-6, "sim_state 时钟推进 28 s")
	check(_json_ok(step_out), "step 输出可 JSON 序列化")
	var step_counts: Dictionary = step_out.get("counts", {})
	check(int(step_counts.get("tws_channels", 0)) == 6, "28 s 后 TWS 6 通道")
	check(int(step_counts.get("tws_active", 0)) == 6, "6 通道全部 active")
	check(int(step_counts.get("optical_locked", 0)) == 2, "光学+IR 均锁定")
	check(max_radar_obs == expected_entities - 1,
		"雷达扫描帧覆盖全部 %d 个实体目标（含 station/tank）" % (expected_entities - 1),
		"max_obs=%d" % max_radar_obs)
	var radio_obs: Array = step_out.get("radar_observations", [])
	var last_obs: Array = step_out.get("observations", [])
	var obs0: Dictionary = last_obs[0] if last_obs.size() > 0 else {}
	check(String(obs0.get("source", "")) == "harmattan"
		and String(obs0.get("track_id", "")) != "" and bool(obs0.get("detected", false)),
		"观测建议 source/track_id/detected")
	if radio_obs.size() > 0:
		var ro: Dictionary = radio_obs[0]
		check(String(ro.get("kind", "")) == "radar" and int(ro.get("support", 0)) == 2,
			"雷达观测建议字段（radar / support=2）")
	var tws_obs: Array = step_out.get("tws_observations", [])
	if tws_obs.size() > 0:
		var to: Dictionary = tws_obs[0]
		check(String(to.get("kind", "")) == "radar.tws" and int(to.get("support", 0)) == 2,
			"TWS 观测建议字段（radar.tws / support=2）")
	check(_events_of(total_channel_updates, "fire_control_ready").size() >= 6,
		"通道事件：fire_control_ready ≥6")
	check(_events_of(total_channel_updates, "channel_status").size() >= 4,
		"通道事件：光学 acquiring/staring/locked")

	# world 完全未被 step 修改
	check(absf(float(world.t) - world_t0) < 1.0e-9, "step 不改 world.t")
	check(int(world.track_for("2001").observation_count) == world_obs_2001_before,
		"step 不改 core 观测计数")
	check(int(world.track_for("2001").level) == level_2001_before, "step 不改 core 航迹等级")
	check((world.vm_contacts() as Array).size() == expected_contacts, "step 不新增/删除航迹")
	var state_after: Dictionary = world.vm_state()
	check(int(state_after.get("track_count", -1))
		== int(state0.get("track_count", -2)), "world.vm_state track_count 不变")

	var snap_after: Dictionary = step_out.get("snapshot", {})
	check((snap_after.get("contacts", []) as Array).size() == expected_contacts,
		"step 后快照接触数不变")
	var snap_after_counts: Dictionary = snap_after.get("counts", {})
	check(int(snap_after_counts.get("stations", 0)) == 1
		and int(snap_after_counts.get("tanks", 0)) == 1,
		"step 后站体/储罐仍在快照中")
	var tws_after: Dictionary = snap_after.get("tws", {})
	var ch2001 := {}
	for raw in (tws_after.get("channels", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("target_track_id", "")) == "2001":
			ch2001 = raw
	check(not ch2001.is_empty() and String(ch2001.get("state", "")) == "FIRE_CONTROL",
		"2001 TWS 通道 FIRE_CONTROL")
	check(float(ch2001.get("quality", 0.0)) >= 0.85
		and absf(float(ch2001.get("update_rate_hz", 0.0)) - 1.0 / 6.0) < 0.03,
		"2001 quality≥0.85 / 更新率≈1/6 Hz")
	var opt_after: Dictionary = snap_after.get("optical", {})
	check(int(opt_after.get("locked_count", 0)) == 2, "快照光学锁定 2（VIS+IR）")
	var exp_after: Dictionary = snap_after.get("exposure", {})
	check(bool(exp_after.get("fixed", false)), "开机 28 s：暴露已被定位（fix）")

	# ═══════════════════════════════════════════════════════════════
	# 7. 失锁：目标消失 → TWS 降级 → 建议过滤（world 仍不变）
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 7. 失锁：sim_targets=[] → 通道降级 / 建议过滤 ──")
	var sim2: Dictionary = TacticalSnapshot.make_sim_state(world, {})
	var cfg2: Dictionary = {"sim_state": sim2}
	for i in range(30):
		TacticalSnapshot.step(world, 1.0, cfg2)
	var locked_before: Dictionary = TacticalSnapshot.build(world, sim2, {}).get("tws", {})
	check(int(locked_before.get("active_count", 0)) == 6, "失锁前 6 通道 active")
	var lost_events: Array = []
	var final_out: Dictionary = {}
	for i in range(25):
		final_out = TacticalSnapshot.step(world, 1.0,
			{"sim_state": sim2, "sim_targets": []})
		lost_events.append_array(final_out.get("channel_updates", []))
	check(_events_of(lost_events, "fire_control_lost").size() >= 1, "失锁事件 fire_control_lost")
	check(_events_of(lost_events, "lock_lost").size() >= 1, "失锁事件 lock_lost")
	var lost_snap: Dictionary = final_out.get("snapshot", {})
	var lost_tws: Dictionary = lost_snap.get("tws", {})
	check(int(lost_tws.get("active_count", -1)) == 0, "失锁后 active_count=0")
	check((final_out.get("tws_observations", []) as Array).is_empty(),
		"失锁后 TWS 观测建议被过滤（0 条）")
	check((world.vm_contacts() as Array).size() == expected_contacts
		and absf(float(world.t) - world_t0) < 1.0e-9, "失锁期间 world 仍未被修改")

	# ═══════════════════════════════════════════════════════════════
	# 8. 通道停止 / EMCON / step 降级
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 8. 通道停止 / EMCON / step 降级 ──")
	TacticalSnapshot.stop_channel(sim, "optical", "2001")
	var stop_opt: Dictionary = TacticalSnapshot.build(world, sim, {}).get("optical", {})
	check((stop_opt.get("optical", []) as Array).is_empty()
		and (stop_opt.get("ir", []) as Array).size() == 1,
		"停止 VIS 通道后仅剩 IR 通道")
	TacticalSnapshot.stop_channel(sim, "ir")
	var stop_all: Dictionary = TacticalSnapshot.build(world, sim, {}).get("optical", {})
	check((stop_all.get("channels", []) as Array).is_empty(), "stop_channel 清空通道")
	var sim3: Dictionary = TacticalSnapshot.make_sim_state(world, {})
	TacticalSnapshot.set_radar_enabled(sim3, false)
	var snap_off: Dictionary = TacticalSnapshot.build(world, sim3, {})
	check(not bool((snap_off.get("radar", {}) as Dictionary).get("enabled", true))
		and not bool((snap_off.get("exposure", {}) as Dictionary).get("exposed", true)),
		"EMCON 关闭：radar.enabled=false / 无暴露")
	var off_step: Dictionary = TacticalSnapshot.step(world, 1.0, {"sim_state": sim3})
	check(bool(off_step.get("ok", false))
		and (off_step.get("radar_observations", []) as Array).is_empty(),
		"EMCON 关闭：step 无雷达观测建议")
	var bad_step: Dictionary = TacticalSnapshot.step(world, 1.0, {})
	check(not bool(bad_step.get("ok", true)) and String(bad_step.get("reason", "")) != ""
		and not bool(bad_step.get("world_modified", true)),
		"step 缺 sim_state：明确报错、world_modified=false")

	# ═══════════════════════════════════════════════════════════════
	# 9. 报告
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("[API] build(world, sim_state, cfg) -> {schema, version:3, t, time_s, orbit_source, propagator, prediction_horizons_s, icon_catalog, own, contacts, radar, tws, optical, exposure, layers, camera, counts, notes}")
	print("[API] step(world, dt, {sim_state, camera, propagator, time_s, sim_targets}) -> {ok, snapshot, observations, radar_observations, tws_observations, channel_updates, events, world_modified:false, suggested_calls, counts}")
	print("[API] make_sim_state / start_channel / stop_channel / set_radar_enabled")
	print("[API] propagate_local(r_km, v_kmps, dt, mode) / visual_metadata(kind, meta, tags) / entity_visual(entity) / icon_catalog() / project_local / build_world_snapshot")
	print("[REPORT] counts: ", JSON.stringify(snap_after_counts))
	print("[REPORT] own prediction 120s: ", JSON.stringify(own_p120))
	print("[REPORT] station: ", JSON.stringify({"kind": station.get("kind", ""), "icon": station.get("icon", ""),
		"size_km": station.get("size_km", 0.0), "orbit_source": station.get("orbit_source", ""),
		"position_source": station.get("position_source", "")}))
	print("[REPORT] tank: ", JSON.stringify({"kind": tank.get("kind", ""), "marker": tank.get("marker", {}),
		"size_km": tank.get("size_km", 0.0), "orbit_source": tank.get("orbit_source", "")}))
	print("[REPORT] linear_vs_rk4_120s_km: %.6f | direct_err: %s" % [linear_err, str(direct_err)])
