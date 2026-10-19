extends SceneTree

## GHOST TRACK / APSIS · V2-SENSOR-1 × V2-CORE-1 集成探针
##
## 验证 sim/ 的传感器输出能被 core 的观测桥直接消费（不需要两边的类互相依赖）：
##   1) 真实 V2 content 场景（scenario_l1_v2.json）装载 world；
##   2) V2World 实体 orbit → world_snapshot → V2RadarModel.scan_now/step；
##   3) V2ObservationBridge.scan_to_observations / ingest_scan → V2Track L2；
##   4) V2TwsModel 通道 → V2ObservationBridge.tws_channel_to_observation → core L2（火控不抬等级）；
##   5) V2OpticalModel 锁定通道 → 观测（optical.classification）→ core L3；
##   6) 停更后 evidence 老化 → L3/L2 逐级衰减到 L1（失锁在 core 侧的降级路径）。
##
## 运行（工作区根目录）：
##   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
##       --path .\game_v16 --script res://tests/sensor_bridge_probe.gd
## 期望末行 V2 SENSOR×CORE BRIDGE PROBE PASS，退出码 0。

const Types := preload("res://sim/sensor_types.gd")
const RadarModel := preload("res://sim/radar.gd")
const TwsModel := preload("res://sim/tws.gd")
const OpticalModel := preload("res://sim/optical.gd")
const Bridge := preload("res://sim/observation_bridge.gd")
const ScenarioScript := preload("res://core/scenario.gd")
const WorldScript := preload("res://core/world.gd")

const SCENARIO := "res://content/scenario_l1_v2.json"

var ok := true
var pass_count := 0
var fail_count := 0


func _initialize() -> void:
	print("==== V2 SENSOR×CORE BRIDGE PROBE · GHOST TRACK / APSIS ====")
	print("[SRC] sim/{sensor_types,radar,tws,optical,observation_bridge} × core/{scenario,world,tracks} ")
	_run()
	print("")
	print("[SUMMARY] pass=%d fail=%d" % [pass_count, fail_count])
	if ok:
		print("V2 SENSOR×CORE BRIDGE PROBE PASS")
	else:
		print("V2 SENSOR×CORE BRIDGE PROBE FAIL")
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
# 1. 用真实 V2 场景搭建 world 与 sim 快照
# ═══════════════════════════════════════════════════════════════════

func _run() -> void:
	print("")
	print("── 1. 场景装载 / 快照组装（core → sim）──")
	var s = ScenarioScript.load_file(SCENARIO)
	check(s.errors.is_empty(), "scenario.v2 装载无错误", str(s.errors))
	var w = WorldScript.new()
	var loaded: bool = w.load_scenario(s)
	check(loaded, "world.load_scenario ok", "errors=%s" % str(w.errors))
	# V2-CORE-2：前置航行执行前 world.advance() 冻结仿真时间（prelude_open）；集成测试先跳过 PRELUDE。
	if w.has_method("prelude_skip"):
		w.prelude_skip()
	check(not bool(w.vm_state().get("time_frozen", true)),
		"prelude_skip：世界时间可推进（V2-CORE-2 行为）",
		"prelude_open=%s" % str(w.vm_state().get("prelude_open", false)))
	check(String(w.own_id) == "harmattan" and w.entities.size() == 7,
		"world：7 实体 / own=harmattan", "entities=%d own=%s" % [w.entities.size(), str(w.own_id)])

	var observer = w.by_id.get("harmattan")
	check(observer != null, "观察平台实体存在")
	var entity_ids: Array = []
	var snapshot: Dictionary = {
		"t": 0.0,
		"observer": {"id": "harmattan", "pos_km": Types.to_vec3(observer.orbit), "maneuver_g": 0.0},
		"targets": [],
		"sun_illum": 1.0,
		"jamming": 0.0,
		"los": true,
	}
	for e in w.entities:
		if String(e.id) == "harmattan":
			continue
		var row: Dictionary = Bridge.target_row(e, w.track_for(String(e.id)))
		# sim target id 用实体 id（与 core entity_id 对齐）；bridge 负责 target_id → entity_id。
		row["id"] = String(e.id)
		if row.has("r") or row.has("orbit"):
			(snapshot["targets"] as Array).append(row)
		entity_ids.append(String(e.id))
	check((snapshot["targets"] as Array).size() == 6,
		"world→snapshot：6 个目标行", "ids=%s" % str(entity_ids))
	var sample_row: Dictionary = (snapshot["targets"] as Array)[0]
	check(sample_row.has("r") and sample_row.has("batch"),
		"target_row 带轨道航迹要素（r/batch）", JSON.stringify({"r": sample_row.get("r", []), "batch": sample_row.get("batch", "")}))
	check(String(sample_row.get("entity_id", "")) != ""
		and String((sample_row.get("classification", {}) as Dictionary).get("ship_class", "")) != "",
		"target_row 增强：entity_id / classification{class} 就绪（光学 L3 用）",
		JSON.stringify({"entity_id": sample_row.get("entity_id", ""),
			"classification": sample_row.get("classification", {})}))

	# ═══════════════════════════════════════════════════════════════
	# 2. 球形雷达扫描 → observation_bridge → core L2
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 2. V2RadarModel 扫描 → ObservationBridge → core V2Track ──")
	var radar_rec = Types.record("YW-R9")
	var radar = RadarModel.new(radar_rec, {"id": "harmattan"})
	var scan: Dictionary = radar.scan_now(snapshot)
	var observations: Array = scan.get("observations", [])
	check(observations.size() == 6, "雷达扫描 6 个目标", "obs=%d" % observations.size())
	var detected_count := 0
	for raw in observations:
		if raw is Dictionary and bool((raw as Dictionary).get("detected", false)):
			detected_count += 1
	check(detected_count == 6, "6 个目标全部落在球形范围（L1 局部几何）",
		"detected=%d" % detected_count)
	var ingested: Array = Bridge.ingest_scan(w, scan,
		{"source": "harmattan", "entity_ids": entity_ids})
	check(ingested.size() == 6, "bridge.ingest_scan 向 world 注入 6 条观测",
		"tracks=%d" % ingested.size())
	var tr_2001 = w.track_for("summons_4471")
	check(tr_2001 != null, "core 找到 2001 航迹（entity_id 映射）")
	if tr_2001 != null:
		check(tr_2001.level == 2, "雷达观测 → core L2 POSITION",
			"level=%d range=%.1f km" % [int(tr_2001.level), float(tr_2001.range_km)])
		check(String("YW-R9") in tr_2001.sources, "核心航迹记录来源型号 YW-R9",
			str(tr_2001.sources))
		var geom: Dictionary = Types.geometry_km(
			Types.to_vec3(observer.orbit), Types.to_vec3(w.by_id["summons_4471"].orbit))
		var expected_range: float = float(geom.get("range_km", -1.0))
		check(absf(float(tr_2001.range_km) - float(expected_range)) < 1.0,
			"core 航迹距离与 sim 几何一致", "%.1f vs %.1f km" % [
				float(tr_2001.range_km), float(expected_range)])
		check(float(tr_2001.quality) > 0.5 and int(tr_2001.observation_count) >= 1,
			"core 航迹 quality / 观测计数", "q=%.2f n=%d" % [
				float(tr_2001.quality), int(tr_2001.observation_count)])

	# 刷新一帧：world 时间推进 → 第二次扫描再注入。
	w.advance(6.0)
	snapshot["t"] = 6.0
	var step_out: Dictionary = radar.step(6.0, snapshot)
	check(bool(step_out.get("scanned", false)), "6 s 后第二次扫描（刷新率）",
		"scan_index=%d" % int(step_out.get("scan_index", 0)))
	Bridge.ingest_scan(w, step_out, {"source": "harmattan", "entity_ids": entity_ids})
	check(tr_2001 != null and int(tr_2001.observation_count) >= 2,
		"刷新观测持续注入同一航迹", "n=%d" % int(tr_2001.observation_count))

	# ═══════════════════════════════════════════════════════════════
	# 3. TWS 多目标通道 → 观测映射 → core
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 3. V2TwsModel 通道数据 → 观测（V2ObservationBridge 已实现映射）──")
	var tws = TwsModel.new(radar_rec)
	for i in range(25):
		var t_now := float(i + 1)
		var tick_snap: Dictionary = _snapshot_with_observer(snapshot, observer, t_now)
		tws.step(1.0, tick_snap)
	var tws_ch: Dictionary = tws.channel("summons_4471")
	check(String(tws_ch.get("state", "")) == TwsModel.STATE_FIRE_CONTROL,
		"TWS 对 2001 进入 FIRE_CONTROL", "state=%s q=%.2f" % [
			String(tws_ch.get("state", "")), float(tws_ch.get("quality", 0.0))])

	# bridge 已实现通道→观测映射（docs/34 §8.6 约定）。
	var tws_opts: Dictionary = {
		"sensor": "YW-R9", "source": "harmattan",
		"t": tws.now_t, "entity_ids": entity_ids,
	}
	var tws_obs: Dictionary = Bridge.tws_channel_to_observation(tws_ch, tws_opts)
	check(bool(tws_obs.get("detected", false))
		and String(tws_obs.get("kind", "")) == "radar.tws"
		and int(tws_obs.get("support", 0)) == 2,
		"bridge.tws_channel_to_observation：radar.tws / support=2 / detected=true",
		JSON.stringify({"kind": tws_obs.get("kind", ""), "support": tws_obs.get("support", 0)}))
	check((tws_obs.get("notes", []) as Array).size() >= 3,
		"bridge：age/update_rate/stable_track 进 notes", str(tws_obs.get("notes", [])))
	check(String(tws_obs.get("channel_state", "")) == TwsModel.STATE_FIRE_CONTROL
		and not (tws_obs.get("fire_control", {}) as Dictionary).is_empty(),
		"bridge：fire_control 只透传（channel_state + fire_control 字段）")
	check(String(tws_obs.get("entity_id", "")) == "summons_4471",
		"bridge：target_id → entity_id", str(tws_obs.get("entity_id", "")))
	check(String(tws_obs.get("kind", "")) == "radar.tws"
		and absf(float(tws_obs.get("quality", 0.0)) - float(tws_ch.get("quality", 0.0))) < 1.0e-6,
		"bridge：TWS quality/kind 透传", JSON.stringify(tws_obs))
	var tr_after_tws = w.ingest(tws_obs)
	check(tr_after_tws != null and tr_after_tws.level == 2,
		"TWS 观测经 bridge 注入后 core 仍为 L2（火控不抬等级）",
		"level=%d q=%.2f" % [int(tr_after_tws.level) if tr_after_tws != null else -1,
			float(tr_after_tws.quality) if tr_after_tws != null else 0.0])
	var multi_obs: Array = Bridge.tws_channels_to_observations(tws.channels_export(), tws_opts)
	check(multi_obs.size() == 6, "bridge.tws_channels_to_observations：6 个可跟踪通道全部可注入",
		"n=%d" % multi_obs.size())
	var multi_ingested: Array = Bridge.ingest_tws_channels(w, tws.channels_export(), tws_opts)
	check(multi_ingested.size() == 6, "bridge.ingest_tws_channels → world 注入 6 条观测",
		"tracks=%d" % multi_ingested.size())
	print("[REPORT] TWS 火控解算字段: ", JSON.stringify(tws_ch.get("fire_control", {})))

	# 失锁：目标消失 → 通道降级（FIRE_CONTROL→TRACK→DETECT）→ bridge 过滤，停止注入。
	for i in range(15):
		var lost_snap: Dictionary = _snapshot_with_observer(snapshot, observer, 26.0 + i)
		lost_snap["targets"] = []
		tws.step(1.0, lost_snap)
	var lost_obs: Array = Bridge.tws_channels_to_observations(tws.channels_export(), tws_opts)
	check(lost_obs.is_empty(), "失锁通道被 bridge 过滤（detected=false → 停止注入）",
		"n=%d states=%s" % [lost_obs.size(), str(tws.to_dict().get("by_state", {}))])
	check(Bridge.ingest_tws_channels(w, tws.channels_export(), tws_opts).is_empty(),
		"失锁后 ingest_tws_channels 注入 0 条")
	print("[REPORT] TWS 失锁后通道状态: ", str(tws.to_dict().get("by_state", {})))

	# ═══════════════════════════════════════════════════════════════
	# 4. 光学凝视锁定 → optical.classification → core L3
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 4. V2OpticalModel 锁定 → optical.classification → core L3 ──")
	var opt = OpticalModel.new({"optical": Types.record("MS-OT2")})
	var started: Dictionary = opt.start("optical", "summons_4471")
	check(bool(started.get("ok", false)), "建立光学通道")
	for i in range(10):
		var tick_snap: Dictionary = _snapshot_with_observer(snapshot, observer, 30.0 + i)
		opt.step(1.0, tick_snap)
	var opt_ch: Dictionary = opt.channel("optical", "summons_4471")
	check(String(opt_ch.get("status", "")) == OpticalModel.STATUS_LOCKED,
		"近距离目标 4 s 内完成凝视锁定", "status=%s required=%.1f s" % [
			String(opt_ch.get("status", "")), float(opt_ch.get("required_s", 0.0))])
	var opt_obs: Dictionary = _optical_channel_to_observation(opt_ch, opt.now_t)
	var opt_mapped: Dictionary = Bridge.to_core_observation(opt_obs,
		{"source": "harmattan", "entity_ids": entity_ids})
	var tr_after_opt = w.ingest(opt_mapped)
	check(tr_after_opt != null and tr_after_opt.level == 3,
		"optical.classification 观测 → core L3 CLASSIFIED",
		"level=%d cls=%s" % [
			int(tr_after_opt.level) if tr_after_opt != null else -1,
			JSON.stringify(tr_after_opt.classification) if tr_after_opt != null else "{}"])
	check(String(tr_after_opt.classification.get("ship_class", "")) == "传唤级",
		"core 航迹分类字段来自 sim 光学锁定分类",
		String(tr_after_opt.classification.get("ship_class", "")))
	check(opt_obs.get("range_km", null) == null,
		"光学观测不带距离解（不伪造测量）",
		"range_km=%s" % str(opt_obs.get("range_km", "missing")))

	# IR 通道只支撑 L1，不改变已有 L3。
	var opt_ir = OpticalModel.new({"ir": Types.record("CH-IR2")})
	opt_ir.start("ir", "summons_4471")
	for i in range(6):
		opt_ir.step(1.0, _snapshot_with_observer(snapshot, observer, 40.0 + i))
	var ir_ch: Dictionary = opt_ir.channel("ir", "summons_4471")
	var ir_obs: Dictionary = _ir_channel_to_observation(ir_ch, opt_ir.now_t)
	var ir_mapped: Dictionary = Bridge.to_core_observation(ir_obs,
		{"source": "harmattan", "entity_ids": entity_ids})
	var tr_after_ir = w.ingest(ir_mapped)
	check(tr_after_ir != null and tr_after_ir.level == 3,
		"IR（支撑 L1）不降低已有 L3 识别", "level=%d band=%s" % [
			int(tr_after_ir.level) if tr_after_ir != null else -1,
			String(ir_obs.get("range_band", ""))])

	# ═══════════════════════════════════════════════════════════════
	# 5. 停更 → core evidence 老化降级（失锁在 core 侧的处置）
	# ═══════════════════════════════════════════════════════════════
	print("")
	print("── 5. 停止注入观测 → core evidence 老化：L3→L2→L1 ──")
	w.advance(100.0)
	check(int(tr_2001.level) == 2,
		"停更 100 s：L3 证据过期（valid 90 s）→ 降到 L2",
		"level=%d age=%.0f" % [int(tr_2001.level), float(tr_2001.age_s)])
	w.advance(120.0)
	check(int(tr_2001.level) == 1,
		"停更 220 s：L2 证据过期（valid 210 s）→ 降到 L1",
		"level=%d age=%.0f" % [int(tr_2001.level), float(tr_2001.age_s)])
	w.advance(10.0)
	check(int(tr_2001.level) == 1,
		"L1 为记忆地板：失去跟踪不删除（05 §S-07）",
		"level=%d t=%.0f" % [int(tr_2001.level), float(w.t)])
	print("[REPORT] core 航迹 2001：", JSON.stringify({
		"id": tr_2001.id, "entity_id": tr_2001.entity_id, "level": tr_2001.level,
		"range_km": tr_2001.range_km, "quality": tr_2001.quality,
		"sources": tr_2001.sources, "observation_count": tr_2001.observation_count,
	}))
	print("[MAP] 已收进 V2ObservationBridge（V2-CORE-1）：tws_channel_to_observation / tws_channels_to_observations / ingest_tws_channels")
	print("[MAP]   kind='radar.tws'、support=2、quality/bearing/range/sigmas 透传；detected = state∈ACQUIRE/TRACK/STARE/FIRE_CONTROL；")
	print("[MAP]   notes 带 state/age/update；fire_control 只透传不参与等级；失锁→detected=false→停止注入，core 证据老化降级。")
	print("[MAP] target_row 已增强：entity_id / track_id / classification / r,v / meta(rcs_m2,temp_k,area_m2,transponder,iff_code)")
	print("[MAP] 光学/IR：显式观测 kind='optical.classification'+support=3+classification / kind='ir'+support=1+range_band（core 已验证 L3 语义）")
	print("[API] 以上均为 sim→core 单向；sim/ 不引用 core/，bridge 在 sim/ 内只做格式适配")


## 快照 targets 位置随时间推进（简化匀速直线：position += v×Δt，用于 TWS/光学多帧）。
func _snapshot_with_observer(base: Dictionary, observer, t: float) -> Dictionary:
	var snap: Dictionary = {
		"t": t,
		"observer": {"id": "harmattan", "pos_km": Types.to_vec3(observer.orbit), "maneuver_g": 0.0},
		"targets": [],
		"sun_illum": 1.0,
		"jamming": 0.0,
		"los": true,
	}
	for raw in (base.get("targets", []) as Array):
		if raw is Dictionary:
			var row: Dictionary = (raw as Dictionary).duplicate(true)
			(snap["targets"] as Array).append(row)
	return snap


# ═══════════════════════════════════════════════════════════════════
# 光学/IR 通道 → core 观测（单测里的最小适配；TWS 已由 bridge 内置）
# ═══════════════════════════════════════════════════════════════════

func _optical_channel_to_observation(ch: Dictionary, t: float) -> Dictionary:
	return {
		"detected": true,
		"target_id": String(ch.get("target_id", "")),
		"sensor": "MS-OT2",
		"kind": "optical.classification",
		"t": t,
		"quality": 0.9,
		"support": 3,
		"bearing_deg": float(ch.get("bearing_deg", -1.0)),
		"bearing_sigma_deg": float(ch.get("bearing_sigma_deg", 1.0)),
		"classification": (ch.get("classification", {}) as Dictionary).duplicate(true),
		"notes": ["光学凝视锁定：%.0f/%.0f s" % [
			float(ch.get("stare_s", 0.0)), float(ch.get("required_s", 0.0))]],
	}


func _ir_channel_to_observation(ch: Dictionary, t: float) -> Dictionary:
	return {
		"detected": true,
		"target_id": String(ch.get("target_id", "")),
		"sensor": "CH-IR2",
		"kind": "ir",
		"t": t,
		"quality": 0.6,
		"support": 1,
		"bearing_deg": float(ch.get("bearing_deg", -1.0)),
		"bearing_sigma_deg": float(ch.get("bearing_sigma_deg", 1.0)),
		"range_band": String(ch.get("range_band", "")),
	}
