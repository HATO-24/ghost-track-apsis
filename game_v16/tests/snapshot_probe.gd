extends SceneTree

## GHOST TRACK / APSIS · V2-SENSOR-2 headless probe（战术快照 / 可视化数据）
##
## 验证 sim/tactical_snapshot.gd：
##   1) 真实 V2 场景 → world（8 接触，含无实体 9002）；
##   2) build()：本舰/接触局部坐标、屏幕投影建议、L级/身份/威胁、雷达球 R_eff、
##      TWS 通道、光学/IR 通道、暴露状态、方位线/range_band、JSON 可序列化；
##   3) step()：推进 sim 模型、返回雷达/TWS 观测建议与通道事件，world 保持不变；
##   4) 失锁：目标消失 → TWS 降级 → 建议被过滤；world 不受影响；
##   5) 投影/相机建议的确定性；无 sim_state 的降级路径。
##
## 运行（工作区根目录）：
##   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
##       --path .\game_v16 --script res://tests/snapshot_probe.gd
## 期望末行 V2 SENSOR-2 SNAPSHOT PROBE PASS，退出码 0。
## 日志：game_v16/tests/snapshot_probe.log

const Types := preload("res://sim/sensor_types.gd")
const TacticalSnapshot := preload("res://sim/tactical_snapshot.gd")
const ScenarioScript := preload("res://core/scenario.gd")
const WorldScript := preload("res://core/world.gd")

const SCENARIO := "res://content/scenario_l1_v2.json"
const EXPECTED_IDS := ["1000", "1001", "1002", "1003", "1004", "2001", "9001", "9002"]

var ok := true
var pass_count := 0
var fail_count := 0


func _initialize() -> void:
	print("==== V2 SENSOR-2 SNAPSHOT PROBE · GHOST TRACK / APSIS ====")
	print("[SRC] sim/tactical_snapshot.gd × sim/{sensor_types,radar,tws,optical} × core/{scenario,world}")
	_run()
	print("")
	print("[SUMMARY] pass=%d fail=%d" % [pass_count, fail_count])
	if ok:
		print("V2 SENSOR-2 SNAPSHOT PROBE PASS")
	else:
		print("V2 SENSOR-2 SNAPSHOT PROBE FAIL")
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

func _find_contact(contacts: Array, track_id: String) -> Dictionary:
	for raw in contacts:
		if raw is Dictionary and String((raw as Dictionary).get("track_id", "")) == track_id:
			return raw
	return {}


func _dist2(a: Variant, b: Variant) -> float:
	var va := Types.to_vec3(a)
	var vb := Types.to_vec3(b)
	return va.distance_to(vb)


func _events_of(all_events: Array, kind: String) -> Array:
	var out: Array = []
	for raw in all_events:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			out.append(raw)
	return out


func _json_ok(value: Variant) -> bool:
	var txt := JSON.stringify(value)
	return txt.length() > 2 and not txt.contains("<Object")


func _script_ready(script: Variant) -> bool:
	return script is GDScript and (script as GDScript).can_instantiate()


func _run() -> void:
	# 并发编辑保护：core 脚本若正在被其它任务改写，明确判 FAIL 而不是静默中断。
	var scenario_script_check: Variant = load("res://core/scenario.gd")
	var world_script_check: Variant = load("res://core/world.gd")
	var core_ready := _script_ready(scenario_script_check) and _script_ready(world_script_check)
	if not core_ready:
		check(false, "core/{scenario,world}.gd 未通过编译（可能正被并发编辑，稍后重跑）",
			"scenario_ok=%s world_ok=%s" % [
				str(_script_ready(scenario_script_check)), str(_script_ready(world_script_check))])
		return
	# ═══════════════════════════════════════════════════════════════
	# 1. 真实场景装载
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 1. 真实场景 → world（8 接触）──")
	var scenario = ScenarioScript.load_file(SCENARIO)
	check(scenario.errors.is_empty(), "scenario.v2 装载无错误", str(scenario.errors))
	var world = WorldScript.new()
	var loaded: bool = world.load_scenario(scenario)
	check(loaded and world.errors.is_empty(), "world 装载 ok",
		"errors=%s" % str(world.errors))
	var contacts_before: Array = world.vm_contacts()
	check(contacts_before.size() == 8, "world 8 条接触（7 实体 + 无实体 9002）",
		"n=%d" % contacts_before.size())
	var ids: Array = []
	for raw in contacts_before:
		ids.append(String((raw as Dictionary).get("track_id", "")))
	ids.sort()
	var expected: Array = EXPECTED_IDS.duplicate()
	expected.sort()
	check(ids == expected, "接触 id 集合", str(ids).replace("\n", ""))
	var world_t0 := float(world.t)
	var state0: Dictionary = world.vm_state()

	# ═══════════════════════════════════════════════════════════════
	# 2. make_sim_state（从本舰能力/传感器架装配）
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 2. make_sim_state：雷达/TWS/光学模型装配 ──")
	var sim: Dictionary = TacticalSnapshot.make_sim_state(world, {})
	check(String(sim.get("schema", "")) == "tactical_sim_state.v1", "sim_state schema")
	check(String(sim.get("observer_id", "")) == "harmattan", "observer = 哈马丹",
		String(sim.get("observer_id", "")))
	var sim_radar = sim.get("radar", null)
	var sim_tws = sim.get("tws", null)
	var sim_opt = sim.get("optical", null)
	check(sim_radar != null and sim_tws != null and sim_opt != null,
		"radar/tws/optical 模型实例就绪")
	check(sim_radar == sim_tws.radar, "TWS 与雷达共享同一实例（扫描节奏一致）")
	check(String(sim_radar.record.model) == "YW-R9", "雷达型号 YW-R9",
		String(sim_radar.record.model))
	check(int(sim_tws.max_channels) == 6, "TWS 通道 6", "max=%d" % int(sim_tws.max_channels))
	check(bool(sim_radar.enabled), "雷达默认开机（EMCON 由上层控制）")
	check(sim_opt.has_sensor("optical") and sim_opt.has_sensor("ir"),
		"光学 MS-OT2 + 红外 CH-IR2 已挂")

	# ═══════════════════════════════════════════════════════════════
	# 3. build()：纯数据战术快照
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 3. build()：接触 / 雷达球 / TWS / 光学 / 暴露 ──")
	var snap: Dictionary = TacticalSnapshot.build(world, sim, {})
	check(String(snap.get("schema", "")) == "tactical_snapshot.v1", "快照 schema",
		String(snap.get("schema", "")))
	check(not bool(snap.get("drawable", true)), "纯数据：drawable=false（不做渲染）")
	check(absf(float(snap.get("t", -1.0)) - world_t0) < 1.0e-6, "快照 t = world.t")
	check(String(snap.get("datum", "")) == "L1", "基准 L1", String(snap.get("datum", "")))

	var own: Dictionary = snap.get("own", {})
	check(String(own.get("id", "")) == "harmattan" and bool(own.get("available", false)),
		"own：哈马丹", String(own.get("id", "")))
	var own_r: Array = own.get("local_r_km", [])
	check(own_r is Array and own_r.size() == 3, "own 局部坐标 r（km）", str(own_r))
	check(own_r.size() == 3 and absf(float(own_r[0]) - 2.0) < 1.0e-6
		and absf(float(own_r[1]) + 3.0) < 1.0e-6 and absf(float(own_r[2])) < 1.0e-6,
		"own 局部坐标 = 哈马丹轨道 [2,-3,0]", str(own_r))
	var own_screen: Dictionary = own.get("screen", {})
	check(bool(own_screen.get("inside", false))
		and absf(float(own_screen.get("x", -1.0)) - 980.0) < 1.0e-6
		and absf(float(own_screen.get("y", -1.0)) - 500.0) < 1.0e-6,
		"屏幕投影建议：本舰位于地图像素中心（980,500）", str(own_screen))

	var contacts: Array = snap.get("contacts", [])
	check(contacts.size() == 8, "快照 8 接触", "n=%d" % contacts.size())
	var counts: Dictionary = snap.get("counts", {})
	check(int(counts.get("entities", 0)) == 7, "7 个有实体接触")
	check(int(counts.get("no_entity", 0)) == 1, "1 个无实体接触（9002）")
	check(int(counts.get("bearing_only", 0)) == 3, "3 条纯方位接触（2001/9001/9002）",
		"n=%d" % int(counts.get("bearing_only", 0)))

	var own_c := _find_contact(contacts, "1001")
	check(not own_c.is_empty() and bool(own_c.get("is_own", false)), "1001 标记为本舰")
	check(String((own_c.get("marker", {}) as Dictionary).get("shape", "")) == "own",
		"本舰 marker=own")

	var phantom := _find_contact(contacts, "9002")
	check(not phantom.is_empty() and not bool(phantom.get("has_entity", true)),
		"9002 无实体航迹", String(phantom.get("name", "")))
	check(String((phantom.get("marker", {}) as Dictionary).get("shape", "")) == "phantom",
		"9002 marker=phantom")
	var phantom_line: Dictionary = phantom.get("bearing_line", {})
	check(absf(float(phantom_line.get("bearing_deg", -1.0)) - 302.0) < 1.0e-6,
		"9002 方位线 302°（种子数据）", "%.1f°" % float(phantom_line.get("bearing_deg", -1.0)))
	check(phantom_line.has("endpoint_local_km") and phantom_line.has("endpoint_screen"),
		"9002 方位线端点局部坐标 + 投影建议")
	check(String(phantom.get("range_band", "x")) == "",
		"9002 range_band 字段存在（无距离档）", "band='%s'" % String(phantom.get("range_band", "")))

	# L1 接触不泄露实体真位置：2001 只给方位线（显示长度 450 km ≠ 实体 319 km）。
	var c2001 := _find_contact(contacts, "2001")
	check(String(c2001.get("position_source", "")) == "bearing_line",
		"2001（L1）position_source=bearing_line", String(c2001.get("position_source", "")))
	var rendered_range := _dist2(c2001.get("local_r_km", []), own.get("local_r_km", []))
	check(absf(rendered_range - 450.0) < 1.5,
		"2001 显示端点=方位线长度 450 km（不是实体真位置）",
		"rendered=%.1f km" % rendered_range)
	var truth_geom: Dictionary = Types.geometry_km(
		Types.to_vec3(own.get("local_r_km", [])),
		Types.to_vec3(world.entity("summons_4471").orbit))
	var truth_range: float = float(truth_geom.get("range_km", -1.0))
	check(absf(rendered_range - float(truth_range)) > 10.0,
		"2001 显示坐标未泄露实体轨道真值", "truth=%.1f km" % float(truth_range))

	# L4 友军：实体位置可显示（协同/融合位置），且在雷达球内。
	var apsis := _find_contact(contacts, "1000")
	check(String(apsis.get("position_source", "")) == "entity_orbit",
		"1000（L4 友军）position_source=entity_orbit")
	check((apsis.get("local_r_km", null) is Array)
		and bool((apsis.get("screen", {}) as Dictionary).get("inside", false)),
		"1000 有局部坐标 + 屏幕在 MAP 区内")
	check(bool(apsis.get("in_radar_sphere", false)), "1000 在雷达球内")

	var radar: Dictionary = snap.get("radar", {})
	check(bool(radar.get("available", false)), "radar 段可用")
	check(String(radar.get("model", "")) == "YW-R9", "radar 型号 YW-R9")
	check(bool(radar.get("enabled", false)), "radar enabled")
	var sphere: Dictionary = radar.get("sphere", {})
	check(String(sphere.get("shape", "")) == "sphere" and bool(sphere.get("no_sector", false)),
		"雷达球：shape=sphere / no_sector（不是扇形）", str(sphere.get("shape", "")))
	check(absf(float(sphere.get("nominal_radius_km", 0.0)) - 30000.0) < 1.0e-6
		and absf(float(sphere.get("effective_radius_km", 0.0)) - 30000.0) < 1.0e-6,
		"球标称/有效半径 30,000 km（RCS=10 m²）", "eff=%.0f km" % float(sphere.get("effective_radius_km", 0.0)))
	check(int(sphere.get("contacts_in_sphere", 0)) == 5, "5 个有位置接触在球内（本舰 + 4 友军；L1 仅方位线不计）",
		"n=%d" % int(sphere.get("contacts_in_sphere", 0)))
	check(absf(float(radar.get("scan_period_s", 0.0)) - 6.0) < 1.0e-6, "扫描周期 6 s")
	var exposure: Dictionary = snap.get("exposure", {})
	check(bool(exposure.get("exposed", false))
		and absf(float(exposure.get("emission_level", 0.0)) - 1.0) < 1.0e-6,
		"暴露：雷达开机 emission_level=1.0")
	check(absf(float(exposure.get("elint_intercept_range_km", 0.0)) - 45000.0) < 1.0,
		"暴露：ELINT 截获 45,000 km")
	check(absf(float(exposure.get("fix_after_s", 0.0)) - 20.0) < 1.0e-6, "暴露：20 s 可定位")

	var tws_before: Dictionary = snap.get("tws", {})
	check(bool(tws_before.get("available", false)) and int(tws_before.get("channel_count", -1)) == 0,
		"TWS：可用、未捕获前 0 通道")
	var sm: Array = tws_before.get("state_machine", [])
	check(sm == ["SEARCH", "DETECT", "ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"],
		"TWS 六态枚举", str(sm))
	var opt_before: Dictionary = snap.get("optical", {})
	check(bool(opt_before.get("available", false))
		and int(opt_before.get("locked_count", -1)) == 0,
		"光学：可用、未建通道前 0 锁定")
	check((snap.get("layers", {}) as Dictionary).has("contacts"), "layers 图层状态可读")

	check(_json_ok(snap), "快照可 JSON 序列化（无 Object/Vector）")
	var snap2: Dictionary = TacticalSnapshot.build(world, sim, {})
	check(JSON.stringify(snap) == JSON.stringify(snap2), "build() 确定性（同输入同输出）")

	# 无 sim_state 的降级路径：接触仍可显示，传感器段标记不可用。
	var bare: Dictionary = TacticalSnapshot.build(world, {}, {})
	check((bare.get("contacts", []) as Array).size() == 8,
		"无 sim_state：接触仍输出 8 条")
	check(not bool((bare.get("radar", {}) as Dictionary).get("available", true))
		and not bool((bare.get("tws", {}) as Dictionary).get("available", true)),
		"无 sim_state：radar/tws 段 available=false（降级）")
	check(_json_ok(bare), "降级快照可 JSON 序列化")

	# ═══════════════════════════════════════════════════════════════
	# 4. 屏幕投影建议（可确定性验证）
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
		"东 100 km → (600,500) 中心 + x", "x=%.1f y=%.1f" % [
			float(east.get("x", 0.0)), float(east.get("y", 0.0))])
	var north: Dictionary = TacticalSnapshot.project_local([0.0, 100.0, 0.0], cam, [0.0, 0.0, 0.0])
	check(absf(float(north.get("x", 0.0)) - 500.0) < 1.0e-6
		and absf(float(north.get("y", 0.0)) - 400.0) < 1.0e-6,
		"北 100 km → 屏幕向上（y 减小）")
	var view_offset: Dictionary = TacticalSnapshot.project_local([0.0, 0.0, 0.0], cam, [50.0, 50.0, 0.0])
	check(absf(float(view_offset.get("x", 0.0)) - 450.0) < 1.0e-6
		and absf(float(view_offset.get("y", 0.0)) - 550.0) < 1.0e-6,
		"相机以本舰为中心：本舰局部坐标投影回中心")
	var yaw90: Dictionary = TacticalSnapshot.project_local([100.0, 0.0, 0.0],
		{"map_rect": [0.0, 0.0, 1000.0, 1000.0], "yaw_deg": 90.0, "pitch_deg": 0.0,
		"scale_px_per_km": 1.0, "center_mode": "own"}, [0.0, 0.0, 0.0])
	check(absf(float(yaw90.get("x", 0.0)) - 500.0) < 1.0e-6
		and absf(float(yaw90.get("y", 0.0)) - 600.0) < 1.0e-6,
		"yaw 90° 旋转确定性", "x=%.1f y=%.1f" % [
			float(yaw90.get("x", 0.0)), float(yaw90.get("y", 0.0))])
	var off: Dictionary = TacticalSnapshot.project_local([1000.0, 0.0, 0.0],
		{"map_rect": [0.0, 0.0, 100.0, 100.0], "yaw_deg": 0.0, "pitch_deg": 0.0,
		"scale_px_per_km": 1.0, "center_mode": "own"}, [0.0, 0.0, 0.0])
	check(not bool(off.get("inside", true)) and off.has("edge"),
		"越界接触给出边缘提示 edge")
	var edge: Dictionary = off.get("edge", {})
	check(absf(float(edge.get("x", -1.0)) - 86.0) < 1.0e-6,
		"边缘提示夹到 MAP 内（含 14px 边距）", str(edge))

	var camera: Dictionary = snap.get("camera", {})
	check(bool(camera.get("auto_scale", false))
		and float(camera.get("scale_px_per_km", 0.0)) > 0.0,
		"默认相机建议：自动缩放", "scale=%.3f px/km" % float(camera.get("scale_px_per_km", 0.0)))
	var explicit_cam: Dictionary = {"camera": {"scale_px_per_km": 0.5, "map_rect": [0.0, 0.0, 1920.0, 1080.0]}}
	var snap_cam: Dictionary = TacticalSnapshot.build(world, sim, explicit_cam)
	var cam_used: Dictionary = snap_cam.get("camera", {})
	check(absf(float(cam_used.get("scale_px_per_km", 0.0)) - 0.5) < 1.0e-6,
		"cfg.camera 覆盖缩放建议")

	# ═══════════════════════════════════════════════════════════════
	# 5. build_world_snapshot（给传感器模型的输入）
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 5. build_world_snapshot：world → 传感器输入快照 ──")
	var ws: Dictionary = TacticalSnapshot.build_world_snapshot(world, sim, {})
	check((ws.get("targets", []) as Array).size() == 6, "目标行 6（除本舰）")
	var ws_t0: Dictionary = (ws.get("targets", []) as Array)[0]
	check(ws_t0.has("id") and ws_t0.has("track_id") and ws_t0.has("entity_id")
		and ws_t0.has("r") and ws_t0.has("classification"),
		"目标行含 id/track_id/entity_id/r/classification",
		JSON.stringify({"id": ws_t0.get("id", ""), "entity_id": ws_t0.get("entity_id", "")}))
	check(absf(float(ws.get("sun_illum", 0.0)) - 1.0) < 1.0e-6
		and float(ws.get("jamming", -1.0)) == 0.0, "环境参数透传")
	var ws_override: Dictionary = TacticalSnapshot.build_world_snapshot(world, sim, {"sim_targets": []})
	check((ws_override.get("targets", []) as Array).is_empty(),
		"cfg.sim_targets 覆盖钩子（空目标 = 验证失锁）")

	# ═══════════════════════════════════════════════════════════════
	# 6. step()：推进 sim、给观测建议、world 保持不变
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 6. step()：观测建议 / 通道更新 / world 只读 ──")
	var start_opt: Dictionary = TacticalSnapshot.start_channel(sim, "optical", "2001")
	var start_ir: Dictionary = TacticalSnapshot.start_channel(sim, "ir", "9001")
	check(bool(start_opt.get("ok", false)) and bool(start_ir.get("ok", false)),
		"建立光学/IR 凝视通道", "%s / %s" % [str(start_opt.get("ok")), str(start_ir.get("ok"))])
	check(not bool(TacticalSnapshot.start_channel(sim, "laser", "2001").get("ok", true)),
		"非法通道类型被拒绝")
	var world_obs_2001_before := int(world.track_for("2001").observation_count)
	var level_2001_before := int(world.track_for("2001").level)
	var cfg: Dictionary = {"sim_state": sim, "camera": {"scale_px_per_km": 0.8}}
	var total_channel_updates: Array = []
	var steps_with_radar := 0
	var steps_with_tws := 0
	var step_out: Dictionary = {}
	for i in range(28):
		step_out = TacticalSnapshot.step(world, 1.0, cfg)
		if not bool(step_out.get("ok", false)):
			check(false, "step 第 %d 步失败" % (i + 1), String(step_out.get("reason", "")))
			break
		if bool(step_out.get("world_modified", true)):
			check(false, "step 不得修改 world")
			break
		if int(step_out.get("radar_observations", [] as Array).size()) > 0:
			steps_with_radar += 1
		if int(step_out.get("tws_observations", [] as Array).size()) > 0:
			steps_with_tws += 1
		total_channel_updates.append_array(step_out.get("channel_updates", []))
	check(String(step_out.get("schema", "")) == "tactical_step.v1", "step schema")
	check(step_out.get("world_modified", true) == false, "step 声明 world_modified=false")
	check(steps_with_radar >= 4, "雷达扫描帧 ≥4（6 s 刷新，28 s 内 5 次）",
		"frames=%d" % steps_with_radar)
	check(steps_with_tws >= 10, "TWS 活跃观测建议持续输出", "steps=%d" % steps_with_tws)
	check(absf(float(sim.get("time", 0.0)) - 28.0) < 1.0e-6, "sim_state 时钟推进 28 s",
		"sim_time=%.0f" % float(sim.get("time", 0.0)))
	check(_json_ok(step_out), "step 输出可 JSON 序列化")

	var step_counts: Dictionary = step_out.get("counts", {})
	check(int(step_counts.get("tws_channels", 0)) == 6, "28 s 后 TWS 6 通道",
		"n=%d" % int(step_counts.get("tws_channels", 0)))
	check(int(step_counts.get("tws_active", 0)) == 6, "6 通道全部 active",
		"n=%d" % int(step_counts.get("tws_active", 0)))
	check(int(step_counts.get("optical_locked", 0)) == 2, "光学+IR 均锁定",
		"n=%d" % int(step_counts.get("optical_locked", 0)))
	check(_events_of(total_channel_updates, "target_detected").size() >= 6,
		"通道事件：target_detected ≥6",
		"n=%d" % _events_of(total_channel_updates, "target_detected").size())
	check(_events_of(total_channel_updates, "state_change").size() >= 18,
		"通道事件：六态迁移 state_change",
		"n=%d" % _events_of(total_channel_updates, "state_change").size())
	check(_events_of(total_channel_updates, "fire_control_ready").size() >= 6,
		"通道事件：fire_control_ready ≥6",
		"n=%d" % _events_of(total_channel_updates, "fire_control_ready").size())
	check(_events_of(total_channel_updates, "channel_status").size() >= 4,
		"通道事件：光学 acquiring/staring/locked",
		"n=%d" % _events_of(total_channel_updates, "channel_status").size())

	var last_obs: Array = step_out.get("observations", [])
	check(last_obs.size() > 0, "最后一步有观测建议", "n=%d" % last_obs.size())
	var obs0: Dictionary = last_obs[0] if last_obs.size() > 0 else {}
	check(String(obs0.get("source", "")) == "harmattan", "观测建议 source=本舰")
	check(String(obs0.get("track_id", "")) != "" and bool(obs0.get("detected", false)),
		"观测建议带 track_id/detected", String(obs0.get("track_id", "")))
	var radio_obs: Array = step_out.get("radar_observations", [])
	if radio_obs.size() > 0:
		var ro: Dictionary = radio_obs[0]
		check(String(ro.get("kind", "")) == "radar" and int(ro.get("support", 0)) == 2,
			"雷达观测建议字段（radar / support=2）", JSON.stringify(ro))
	var tws_obs: Array = step_out.get("tws_observations", [])
	if tws_obs.size() > 0:
		var to: Dictionary = tws_obs[0]
		check(String(to.get("kind", "")) == "radar.tws" and int(to.get("support", 0)) == 2
			and String(to.get("track_id", "")) != "",
			"TWS 观测建议字段（radar.tws / support=2 / track_id）", JSON.stringify(to))
	var suggested: Array = step_out.get("suggested_calls", [])
	check(suggested.size() >= 1, "附带 suggested_calls（调用方如何应用）")

	# world 完全未被 step 修改
	check(absf(float(world.t) - world_t0) < 1.0e-9, "step 不改 world.t", "t=%.1f" % float(world.t))
	check(int(world.track_for("2001").observation_count) == world_obs_2001_before,
		"step 不改 core 观测计数",
		"n=%d" % int(world.track_for("2001").observation_count))
	check(int(world.track_for("2001").level) == level_2001_before,
		"step 不改 core 航迹等级", "L%d" % int(world.track_for("2001").level))
	check((world.vm_contacts() as Array).size() == 8, "step 不新增/删除航迹")
	var state_after: Dictionary = world.vm_state()
	check(int(state_after.get("track_count", state0.get("track_count", -1)))
		== int(state0.get("track_count", -2)), "world.vm_state track_count 不变")

	# 步进后的快照：TWS/光学/暴露
	var snap_after: Dictionary = step_out.get("snapshot", {})
	var tws_after: Dictionary = snap_after.get("tws", {})
	check(int(tws_after.get("channel_count", 0)) == 6, "快照 TWS 通道 6")
	var ch2001 := {}
	for raw in (tws_after.get("channels", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("target_track_id", "")) == "2001":
			ch2001 = raw
	check(not ch2001.is_empty(), "快照含 2001 的 TWS 通道")
	check(String(ch2001.get("state", "")) == "FIRE_CONTROL"
		and bool(ch2001.get("fire_control_ready", false)),
		"2001 通道 FIRE_CONTROL", String(ch2001.get("state", "")))
	check(float(ch2001.get("quality", 0.0)) >= 0.85, "2001 quality ≥0.85",
		"q=%.2f" % float(ch2001.get("quality", 0.0)))
	check(absf(float(ch2001.get("update_rate_hz", 0.0)) - 1.0 / 6.0) < 0.03,
		"2001 更新率 ≈1/6 Hz", "%.3f Hz" % float(ch2001.get("update_rate_hz", 0.0)))
	check(float(ch2001.get("age_s", 99.0)) <= 6.0, "2001 age ≤ 扫描周期",
		"age=%.1f s" % float(ch2001.get("age_s", 99.0)))

	var opt_after: Dictionary = snap_after.get("optical", {})
	check(int(opt_after.get("locked_count", 0)) == 2, "快照光学锁定 2（VIS+IR）")
	var vis_ch := {}
	for raw2 in (opt_after.get("optical", []) as Array):
		if raw2 is Dictionary and String((raw2 as Dictionary).get("target_track_id", "")) == "2001":
			vis_ch = raw2
	check(String(vis_ch.get("status", "")) == "locked" and float(vis_ch.get("progress", 0.0)) >= 1.0,
		"VIS 锁定 + 进度 100%", "status=%s" % String(vis_ch.get("status", "")))
	check(int(vis_ch.get("level_support", 0)) == 3, "VIS 锁定支撑 L3")
	var ir_locked := (opt_after.get("ir", []) as Array)
	var ir_ok := false
	if ir_locked.size() > 0 and ir_locked[0] is Dictionary:
		ir_ok = int((ir_locked[0] as Dictionary).get("level_support", 0)) == 1
	check(ir_locked.size() == 1 and ir_ok, "IR 锁定且只支撑 L1")
	var c2001_after := _find_contact(snap_after.get("contacts", []), "2001")
	check(not (c2001_after.get("optical_channels", {}) as Dictionary).is_empty(),
		"接触 2001 关联光学通道状态")
	var exp_after: Dictionary = snap_after.get("exposure", {})
	check(bool(exp_after.get("fixed", false)), "开机 28 s：暴露已被定位（fix）",
		"progress=%.2f" % float(exp_after.get("fix_progress", 0.0)))

	# ═══════════════════════════════════════════════════════════════
	# 7. 失锁：目标消失 → TWS 降级 → 建议被过滤（world 仍不变）
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
	var lost_snap: Dictionary = final_out.get("snapshot", {})
	var lost_tws: Dictionary = lost_snap.get("tws", {})
	check(_events_of(lost_events, "fire_control_lost").size() >= 1,
		"失锁事件 fire_control_lost",
		"n=%d" % _events_of(lost_events, "fire_control_lost").size())
	check(_events_of(lost_events, "lock_lost").size() >= 1,
		"失锁事件 lock_lost", "n=%d" % _events_of(lost_events, "lock_lost").size())
	check(int(lost_tws.get("active_count", -1)) == 0,
		"失锁后 active_count=0", "active=%d" % int(lost_tws.get("active_count", -1)))
	var lost_states: Dictionary = lost_tws.get("by_state", {})
	var inactive_n := int(lost_states.get("SEARCH", 0)) + int(lost_states.get("DETECT", 0))
	check(inactive_n == 6, "6 通道降级到 SEARCH/DETECT", str(lost_states))
	check((final_out.get("tws_observations", []) as Array).is_empty(),
		"失锁后 TWS 观测建议被过滤（0 条）")
	check((world.vm_contacts() as Array).size() == 8 and absf(float(world.t) - world_t0) < 1.0e-9,
		"失锁期间 world 仍未被修改")

	# ═══════════════════════════════════════════════════════════════
	# 8. 通道停止 / EMCON / 无 sim_state 的 step 降级
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 8. 通道停止 / EMCON / step 降级 ──")
	TacticalSnapshot.stop_channel(sim, "optical", "2001")
	var stop_opt: Dictionary = TacticalSnapshot.build(world, sim, {}).get("optical", {})
	var stop_vis: Array = stop_opt.get("optical", [])
	var stop_ir: Array = stop_opt.get("ir", [])
	check(stop_vis.is_empty() and stop_ir.size() == 1,
		"停止 VIS 通道后仅剩 IR 通道", "vis=%d ir=%d" % [stop_vis.size(), stop_ir.size()])
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
		"step 缺 sim_state：明确报错、world_modified=false", String(bad_step.get("reason", "")))

	# ═══════════════════════════════════════════════════════════════
	# 9. 输出报告
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("[API] build(world, sim_state, cfg) -> {schema, t, datum, own, contacts, radar, tws, optical, exposure, layers, camera, counts, notes}")
	print("[API] step(world, dt, {sim_state, camera, sim_targets, ...}) -> {ok, snapshot, observations, radar_observations, tws_observations, channel_updates, events, world_modified:false, suggested_calls, counts}")
	print("[API] make_sim_state(world, cfg) / start_channel(sim,kind,id) / stop_channel(sim,kind,id?) / set_radar_enabled(sim,on)")
	print("[API] project_local(local_km, camera, own_local_km) / camera_from(cfg) / build_world_snapshot(world, sim, cfg)")
	print("[REPORT] build counts: ", JSON.stringify(snap_after.get("counts", {})))
	print("[REPORT] radar sphere: ", JSON.stringify(sphere))
	print("[REPORT] tws by_state: ", JSON.stringify(tws_after.get("by_state", {})))
	print("[REPORT] optical by_status: ", JSON.stringify(opt_after.get("by_status", {})))
	print("[REPORT] exposure: ", JSON.stringify(exp_after))
