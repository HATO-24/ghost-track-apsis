extends SceneTree

## GHOST TRACK / APSIS · V2-SENSOR-1 headless probe
##
## 验证：传感器能力记录 / 球形雷达（非扇形）/ 距离衰减 / 刷新率 / 暴露风险 /
##       TWS 六态状态机 / 多目标通道 / 失锁降级 / 光学+IR 凝视 / TWS-光学独立性。
##
## 运行（工作区根目录；路径带空格要引号）：
##   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
##       --path .\game_v16 --script res://tests/sensor_probe.gd
## 期望末行 V2 SENSOR PROBE PASS，退出码 0。
##
## 只依赖 game_v16/sim/*（RefCounted）与 game_v16/scripts/sensor_model.gd（规则库）；
## 不加载场景、不依赖 UI。

const Types := preload("res://sim/sensor_types.gd")
const RadarModel := preload("res://sim/radar.gd")
const TwsModel := preload("res://sim/tws.gd")
const OpticalModel := preload("res://sim/optical.gd")
const SM := preload("res://scripts/sensor_model.gd")

var ok := true
var pass_count := 0
var fail_count := 0


func _initialize() -> void:
	print("==== V2 SENSOR PROBE · GHOST TRACK / APSIS ====")
	print("[SRC] docs/34 §4 状态机 · docs/11 参数 · 05 §S-01…S-07 · game_v16/scripts/sensor_model.gd")
	_probe_types()
	_probe_geometry()
	_probe_radar()
	_probe_radar_refresh()
	_probe_tws_state_machine()
	_probe_tws_channels()
	_probe_tws_lost_lock()
	_probe_optical()
	_probe_optical_ir()
	_probe_independence()
	_probe_contract()
	print("")
	print("[SUMMARY] pass=%d fail=%d" % [pass_count, fail_count])
	if ok:
		print("V2 SENSOR PROBE PASS")
	else:
		print("V2 SENSOR PROBE FAIL")
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
# 快照构造工具
# ═══════════════════════════════════════════════════════════════════

func _target(tid: String, pos: Vector3, rcs: float = 1400.0,
		temp: float = 310.0, area: float = 1600.0) -> Dictionary:
	return {
		"id": tid,
		"pos_km": pos,
		"rcs_m2": rcs,
		"temp_k": temp,
		"area_m2": area,
		"classification": {"ship_class": "传唤级", "builder": "第33舰队改装", "faction": "UEG 第33舰队"},
	}


func _snapshot(t: float, targets: Array, extra: Dictionary = {}) -> Dictionary:
	var s: Dictionary = {
		"t": t,
		"observer": {"id": "harmattan", "pos_km": Vector3.ZERO, "maneuver_g": 0.0},
		"targets": targets,
		"sun_illum": 1.0,
		"jamming": 0.0,
	}
	for raw_key in extra.keys():
		var k := String(raw_key)
		s[k] = extra[k]
	return s


func _obs_by_id(obs_list: Array) -> Dictionary:
	var out: Dictionary = {}
	for raw in obs_list:
		if raw is Dictionary:
			var o: Dictionary = raw
			out[String(o.get("target_id", ""))] = o
	return out


func _find_channel(channels: Array, tid: String) -> Dictionary:
	for raw in channels:
		if raw is Dictionary:
			var c: Dictionary = raw
			if String(c.get("target_id", "")) == tid:
				return c
	return {}


func _state_sequence(ch: Dictionary) -> Array:
	var seq: Array = []
	for raw in (ch.get("history", []) as Array):
		if raw is Dictionary:
			seq.append(String((raw as Dictionary).get("to", "")))
	return seq


func _events_of(all_events: Array, kind: String) -> Array:
	var out: Array = []
	for raw in all_events:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			out.append(raw)
	return out


# ═══════════════════════════════════════════════════════════════════
# 1. 传感器能力枚举 / 记录
# ═══════════════════════════════════════════════════════════════════

func _probe_types() -> void:
	print("")
	print("── 1. sensor_types：能力枚举 / 记录 ──")
	check(Types.KINDS.size() == 6, "六类传感器能力枚举（搜索雷达/TWS/光学/IR/IFF/ELINT）",
		str(Types.KINDS))

	var radar_rec = Types.record("YW-R9")
	check(radar_rec.kind == Types.KIND_SEARCH_RADAR, "YW-R9 → 搜索雷达",
		radar_rec.describe())
	check(radar_rec.spherical and radar_rec.scan_volume == Types.SPHERE,
		"YW-R9 探测体 = 球形（非扇形）", "scan_volume=%s" % radar_rec.scan_volume)
	check(radar_rec.track_capacity == 6, "YW-R9 TWS 通道 = 6",
		"track_capacity=%d" % radar_rec.track_capacity)
	check(radar_rec.has_capability("sensor.radar.active")
		and radar_rec.has_capability(Types.CAP_TWS),
		"YW-R9 能力字符串（docs/34 schema）", str(radar_rec.capabilities))
	check(Types.validate_record(radar_rec).is_empty(), "记录校验通过",
		str(Types.validate_record(radar_rec)))

	var tws_rec = Types.record("KD-R6", {"kind": Types.KIND_TWS_RADAR})
	check(tws_rec.kind == Types.KIND_TWS_RADAR and tws_rec.lpi,
		"KD-R6 可作 TWS 火控雷达 + LPI", tws_rec.describe())

	var opt_rec = Types.record("MS-OT2")
	check(opt_rec.kind == Types.KIND_OPTICAL and opt_rec.has_capability(Types.CAP_PASSIVE)
		and not opt_rec.exposed,
		"MS-OT2 → 光学凝视（被动、不暴露）", "stare=%.0f s @ %.0f km" % [
			opt_rec.stare_s, opt_rec.stare_ref_km])

	var ir_rec = Types.record("CH-IR2")
	check(ir_rec.kind == Types.KIND_IR and absf(ir_rec.range_km - 60000.0) < 1.0,
		"CH-IR2 → 红外阵列（60,000 km）", ir_rec.describe())

	var iff_rec = Types.record("MK-12")
	check(iff_rec.kind == Types.KIND_IFF and iff_rec.exposed,
		"MK-12 → IFF 询问机（询问即暴露）", "kind=%s exposure=%s" % [
			iff_rec.kind, iff_rec.exposure_kind])

	var elint_rec = Types.record("ELINT")
	check(elint_rec.kind == Types.KIND_ELINT and not elint_rec.exposed,
		"ELINT → 电子侦察（被动）", elint_rec.describe())

	var lidar_rec = Types.record("LR-4")
	check(lidar_rec.kind == Types.KIND_OPTICAL and lidar_rec.subtype == "lidar"
		and lidar_rec.has_capability(Types.CAP_LIDAR),
		"LR-4 → optical 子型 lidar（04 §12）", lidar_rec.describe())

	var roundtrip = Types.record_from_dict(radar_rec.to_dict())
	check(roundtrip.kind == radar_rec.kind
		and absf(roundtrip.range_km - radar_rec.range_km) < 1.0e-6
		and roundtrip.track_capacity == radar_rec.track_capacity
		and roundtrip.capabilities == radar_rec.capabilities,
		"SensorRecord to_dict/record_from_dict 往返")

	# v15 传感器架 → 能力记录（core 迁移路径）。
	var rack_radar = Types.record_from_rack_sensor(SM.rack_sensor("harmattan", "YW-R9"))
	check(rack_radar.kind == Types.KIND_SEARCH_RADAR
		and absf(rack_radar.range_km - 30000.0) < 1.0e-6,
		"v15 rack sensor → 能力记录（哈马丹 YW-R9）", rack_radar.describe())


# ═══════════════════════════════════════════════════════════════════
# 2. 几何 / 快照工具
# ═══════════════════════════════════════════════════════════════════

func _probe_geometry() -> void:
	print("")
	print("── 2. 几何工具（球坐标/方位/遮挡） ──")
	var g1: Dictionary = Types.geometry_km(Vector3.ZERO, Vector3(0, 8000, 0))
	check(absf(float(g1["range_km"]) - 8000.0) < 1.0e-6
		and absf(float(g1["bearing_deg"])) < 1.0e-6,
		"正北目标：方位 0°", "%.2f°/%.1f km" % [float(g1["bearing_deg"]), float(g1["range_km"])])
	var g2: Dictionary = Types.geometry_km(Vector3.ZERO, Vector3(8000, 0, 0))
	check(absf(float(g2["bearing_deg"]) - 90.0) < 1.0e-6, "正东目标：方位 90°",
		"%.2f°" % float(g2["bearing_deg"]))
	var g3: Dictionary = Types.geometry_km(Vector3.ZERO, Vector3(0, 8000, 8000))
	check(absf(float(g3["elevation_deg"]) - 45.0) < 1.0e-6, "天顶前方目标：俯仰 45°",
		"%.2f°" % float(g3["elevation_deg"]))
	var blocked: Dictionary = {
		"observer": {"pos_km": Vector3(7000, 0, 0)},
		"targets": [{"id": "x", "pos_km": Vector3(-7000, 0, 0)}],
		"occluders": [{"center_km": Vector3.ZERO, "radius_km": 6378.137}],
	}
	check(not Types.los_ok(blocked, Vector3(7000, 0, 0), Vector3(-7000, 0, 0)),
		"地球遮挡：穿透地心 → 不通视")
	var clear: Dictionary = blocked.duplicate(true)
	clear["observer"] = {"pos_km": Vector3(7000, 0, 0)}
	check(Types.los_ok(clear, Vector3(7000, 0, 0), Vector3(20000, 0, 0)),
		"同侧目标：通视")


# ═══════════════════════════════════════════════════════════════════
# 3. 球形雷达：范围 / 衰减 / 检测概率 / 暴露
# ═══════════════════════════════════════════════════════════════════

func _probe_radar() -> void:
	print("")
	print("── 3. radar.gd：球形搜索 + 距离衰减 + 检测概率 ──")
	var rec = Types.record("YW-R9")
	var radar = RadarModel.new(rec, {"id": "YW-R9"})
	var targets: Array = [
		_target("near", Vector3(0, 8000, 0), 10.0),
		_target("far", Vector3(0, 20000, 0), 10.0),
		_target("outside", Vector3(0, 45000, 0), 10.0),
		_target("behind", Vector3(4000, 0, -4000), 10.0),
	]
	var snap := _snapshot(1.0, targets)
	var scan: Dictionary = radar.scan_now(snap)
	var obs: Dictionary = _obs_by_id(scan.get("observations", []))

	check(absf(RadarModel.nominal_radius_km(rec) - 30000.0) < 1.0e-6,
		"YW-R9 标称球半径 30,000 km（05 §S-02）")
	var near: Dictionary = obs.get("near", {})
	var far: Dictionary = obs.get("far", {})
	var outside: Dictionary = obs.get("outside", {})
	var behind: Dictionary = obs.get("behind", {})
	check(bool(near.get("detected", false)) and bool(near.get("in_sphere", false)),
		"8,000 km 球内探测", "Pd=%.3f stable=%s" % [
			float(near.get("pd", 0.0)), str(near.get("stable_track", false))])
	check(bool(near.get("stable_track", false)), "8,000 km < 15,000 km → 稳定跟踪")
	check(bool(far.get("detected", false)) and bool(far.get("in_sphere", false))
		and not bool(far.get("stable_track", true)),
		"20,000 km 探测到但无稳定跟踪（05 §S-02 15,000 km 档）",
		"Pd=%.3f" % float(far.get("pd", 0.0)))
	check(not bool(outside.get("detected", true))
		and not bool(outside.get("in_sphere", true)),
		"45,000 km 在球外：不探测", String(outside.get("reason", "")))
	check(bool(behind.get("detected", false)) and bool(behind.get("in_sphere", false)),
		"球体全向：背后/下方目标同样进入检测（不是扇形）",
		"bearing=%.1f° elevation=%.1f°" % [
			float(behind.get("bearing_deg", -1.0)), float(behind.get("elevation_deg", 0.0))])
	check(float(near.get("pd", 0.0)) > float(far.get("pd", 0.0)),
		"距离衰减：近目标 Pd 高", "%.4f > %.4f" % [
			float(near.get("pd", 0.0)), float(far.get("pd", 0.0))])
	check(float(far.get("range_sigma_km", 0.0)) > float(near.get("range_sigma_km", 0.0)),
		"距离衰减：远目标测距 σ 大（且稳定跟踪外 ×3）", "%.1f km > %.1f km" % [
			float(far.get("range_sigma_km", 0.0)), float(near.get("range_sigma_km", 0.0))])

	# RCS 对球半径的影响（05 §S-02：(σ/10)^0.25）。
	var r10 := RadarModel.effective_radius_km(rec, 10.0, 0.0)
	var r100 := RadarModel.effective_radius_km(rec, 100.0, 0.0)
	check(absf(r10 - 30000.0) < 1.0e-6 and r100 > r10,
		"RCS 放大球半径：10 → 100 m²", "%.0f → %.0f km" % [r10, r100])
	var rjam := RadarModel.effective_radius_km(rec, 10.0, 0.5)
	check(rjam < r10, "噪声干扰压缩球半径（05 §E-01）", "%.0f → %.0f km" % [r10, rjam])
	var sph: Dictionary = RadarModel.sphere_for(rec, Vector3.ZERO, 10.0, 0.0)
	check(String(sph.get("shape", "")) == "sphere" and bool(sph.get("no_sector", false)),
		"sphere_for() 输出球形搜索体（shape=sphere）", str(sph))

	# 暴露风险：开机即暴露（05 §S-02）。
	var exp_radar: Dictionary = RadarModel.exposure_state(rec, 25.0)
	check(bool(exp_radar.get("exposed", false)) and float(exp_radar.get("emission_level", 0.0)) >= 0.99,
		"雷达开机暴露 emission_level=1.0", "ELINT %.0f km / %.0f s" % [
			float(exp_radar.get("elint_intercept_range_km", 0.0)),
			float(exp_radar.get("fix_after_s", 0.0))])
	check(absf(float(exp_radar.get("elint_intercept_range_km", 0.0)) - 45000.0) < 1.0,
		"ELINT 截获距离 = 30,000 × 1.5 = 45,000 km")
	check(bool(exp_radar.get("fixed", false))
		and absf(float(exp_radar.get("bearing_sigma_deg", 1.0)) - 0.2) < 0.01,
		"开机 25 s > 20 s：已被定位（σ→0.2°）",
		"fix_progress=%.2f" % float(exp_radar.get("fix_progress", 0.0)))
	var exp_lpi: Dictionary = RadarModel.exposure_state(Types.record("KD-R6"), 25.0)
	check(float(exp_lpi.get("elint_intercept_range_km", 0.0))
		< float(exp_radar.get("elint_intercept_range_km", 0.0))
		and float(exp_lpi.get("fix_after_s", 0.0)) > float(exp_radar.get("fix_after_s", 0.0)),
		"LPI 雷达更难被截获/定位（06 KD-R6）", "%.0f km / %.0f s" % [
			float(exp_lpi.get("elint_intercept_range_km", 0.0)),
			float(exp_lpi.get("fix_after_s", 0.0))])
	var exp_passive: Dictionary = RadarModel.exposure_state(Types.record("MS-OT2"), 25.0)
	check(not bool(exp_passive.get("exposed", true)), "被动光学：不暴露")


# ═══════════════════════════════════════════════════════════════════
# 4. 刷新率 / 扫描节奏
# ═══════════════════════════════════════════════════════════════════

func _probe_radar_refresh() -> void:
	print("")
	print("── 4. radar.gd：刷新率 / 暴露累计 / EMCON ──")
	var rec = Types.record("YW-R9")
	var radar = RadarModel.new(rec)
	var snap := _snapshot(0.0, [_target("2001", Vector3(0, 9000, 0))])
	var scan_steps: Array = []
	var scan_count := 0
	for i in range(12):
		var out: Dictionary = radar.step(1.0, snap)
		if bool(out.get("scanned", false)):
			scan_count += 1
			scan_steps.append(i + 1)
	check(scan_count == 2, "12 s 内扫描 2 次（6 s 刷新率）",
		"scanned_at=%s scan_index=%d" % [str(scan_steps), int(radar.scan_index)])
	check(int(radar.scan_index) == 2, "scan_index 递增", "scan_index=%d" % int(radar.scan_index))
	check(absf(float(radar.seconds_on) - 12.0) < 1.0e-6, "开机时长累计 12 s",
		"seconds_on=%.1f" % float(radar.seconds_on))
	var exposure: Dictionary = radar.step(1.0, snap).get("exposure", {})
	check(absf(float(exposure.get("fix_progress", 0.0)) - 13.0 / 20.0) < 1.0e-6,
		"暴露定位进度随开机时长推进", "progress=%.2f" % float(exposure.get("fix_progress", 0.0)))

	radar.set_enabled(false)
	var off_out: Dictionary = radar.step(5.0, snap)
	check(not bool(off_out.get("scanned", true))
		and absf(float(radar.seconds_on) - 13.0) < 1.0e-6,
		"EMCON 关机：不扫描、不再累计暴露",
		"seconds_on=%.1f" % float(radar.seconds_on))
	check(not bool((off_out.get("exposure", {}) as Dictionary).get("exposed", true)),
		"关机后暴露态归零")


# ═══════════════════════════════════════════════════════════════════
# 5. TWS 状态机：SEARCH→DETECT→ACQUIRE→TRACK→STARE→FIRE_CONTROL
# ═══════════════════════════════════════════════════════════════════

func _probe_tws_state_machine() -> void:
	print("")
	print("── 5. tws.gd：六态状态机 / 多目标 / quality / 更新率 ──")
	var rec = Types.record("YW-R9")
	var tws = TwsModel.new(rec)
	var targets: Array = [
		_target("2001", Vector3(0, 6000, 0), 1400.0),
		_target("9001", Vector3(4000, -4000, 0), 800.0),
		_target("1002", Vector3(-3000, 5000, 0), 1200.0),
	]
	var snap := _snapshot(0.0, targets)
	var all_events: Array = []
	var observed_states: Array = []
	var first_state := ""
	var threat_keys: Array = []
	for i in range(40):
		var out: Dictionary = tws.step(1.0, snap)
		all_events.append_array(out.get("events", []))
		var ch: Dictionary = tws.channel("2001")
		if not ch.is_empty():
			var st := String(ch.get("state", ""))
			if first_state == "":
				first_state = st
			if observed_states.is_empty() or String(observed_states[observed_states.size() - 1]) != st:
				observed_states.append(st)
		# 快照只读：模型不得往目标字典里写字段。
		if i == 0:
			for raw_key in (targets[0] as Dictionary).keys():
				threat_keys.append(String(raw_key))
			threat_keys.sort()
	check(first_state == TwsModel.STATE_DETECT,
		"首帧捕获目标 → DETECT", "state=%s" % first_state)
	check(int(tws.channel("2001").get("history", []).size()) >= 5,
		"2001 通道产生 5 次以上状态迁移",
		str(_state_sequence(tws.channel("2001"))))
	var seq := _state_sequence(tws.channel("2001"))
	check(seq == [TwsModel.STATE_DETECT, TwsModel.STATE_ACQUIRE,
		TwsModel.STATE_TRACK, TwsModel.STATE_STARE, TwsModel.STATE_FIRE_CONTROL],
		"迁移序列 = SEARCH→DETECT→ACQUIRE→TRACK→STARE→FIRE_CONTROL",
		str(seq))
	var ch: Dictionary = tws.channel("2001")
	check(String(ch.get("state", "")) == TwsModel.STATE_FIRE_CONTROL,
		"40 s 内 2001 进入 FIRE_CONTROL", "quality=%.3f" % float(ch.get("quality", 0.0)))
	check(float(ch.get("quality", 0.0)) >= TwsModel.Q_FIRE,
		"FIRE_CONTROL quality ≥ %.2f" % TwsModel.Q_FIRE,
		"q=%.3f" % float(ch.get("quality", 0.0)))
	check(int(ch.get("update_count", 0)) >= 5, "逐次刷新计数", "updates=%d" % int(ch.get("update_count", 0)))
	var rate := float(ch.get("update_rate_hz", 0.0))
	check(rate > 0.12 and rate < 0.22, "更新率 ≈ 1/6 Hz（6 s 扫描）", "%.3f Hz" % rate)
	check(float(ch.get("age_s", 99.0)) <= 6.0, "age ≤ 扫描周期", "age=%.1f s" % float(ch.get("age_s", 99.0)))
	var fc: Dictionary = ch.get("fire_control", {})
	check(not fc.is_empty() and fc.has("range_km")
		and float(fc.get("range_sigma_km", -1.0)) > 0.0,
		"火控解算含距离/σ/quality", JSON.stringify(fc))
	check(tws.channels_export().size() == 3, "多目标 TWS：3 个目标 3 个通道",
		"channels=%d max=%d" % [tws.channels_export().size(), int(tws.max_channels)])
	var all_fire := true
	for raw in tws.channels_export():
		if String((raw as Dictionary).get("state", "")) != TwsModel.STATE_FIRE_CONTROL:
			all_fire = false
	check(all_fire, "多目标全部进入 FIRE_CONTROL",
		str(tws.to_dict().get("by_state", {})))
	check(_events_of(all_events, "fire_control_ready").size() == 3,
		"3 次 fire_control_ready 事件")
	check(_events_of(all_events, "state_change").size() >= 15,
		"状态迁移事件完整", "events=%d" % _events_of(all_events, "state_change").size())
	var out_last: Dictionary = tws.step(1.0, snap)
	var exposure: Dictionary = out_last.get("exposure", {})
	check(bool(exposure.get("exposed", false)), "TWS 输出携带雷达暴露风险",
		"ELINT %.0f km" % float(exposure.get("elint_intercept_range_km", 0.0)))
	var sphere: Dictionary = out_last.get("sphere", {})
	check(String(sphere.get("shape", "")) == "sphere", "TWS 搜索体 = 球（不是扇形）",
		"nominal=%.0f km" % float(sphere.get("nominal_radius_km", 0.0)))
	# 只读契约：目标字典字段未被模型写入。
	var after_keys: Array = []
	for raw_key in (targets[0] as Dictionary).keys():
		after_keys.append(String(raw_key))
	after_keys.sort()
	check(after_keys == threat_keys, "模型只读快照：目标字典字段未被改写",
		"%s vs %s" % [str(threat_keys), str(after_keys)])
	print("[API] tws.step -> {t, scanned, scan_index, sphere, exposure, channels, by_state, events, radar}")
	print("[REPORT] TWS 2001: ", JSON.stringify(tws.channel("2001")))


# ═══════════════════════════════════════════════════════════════════
# 6. TWS 多通道容量 / 淘汰
# ═══════════════════════════════════════════════════════════════════

func _probe_tws_channels() -> void:
	print("")
	print("── 6. tws.gd：TWS 通道容量 / 淘汰 / 重新分配 ──")
	var rec = Types.record("YW-R9")
	var tws = TwsModel.new(rec, {"max_channels": 3})
	var targets: Array = [
		_target("t1", Vector3(0, 1000, 0), 10.0),
		_target("t2", Vector3(0, 3000, 0), 10.0),
		_target("t3", Vector3(0, 5000, 0), 10.0),
		_target("t4", Vector3(0, 7000, 0), 10.0),
		_target("t5", Vector3(0, 9000, 0), 10.0),
	]
	var out: Dictionary = tws.step(1.0, _snapshot(1.0, targets))
	var events: Array = out.get("events", [])
	check(tws.channels_export().size() == 3, "通道上限 3：只保留 3 个目标",
		"channels=%d" % tws.channels_export().size())
	check(not tws.channel("t1").is_empty() and not tws.channel("t2").is_empty()
		and not tws.channel("t3").is_empty(),
		"按得分保留最近 3 个目标", str(tws.to_dict().get("by_state", {})))
	check(tws.channel("t4").is_empty() and tws.channel("t5").is_empty(),
		"超容量目标被拒绝（channel_full）")
	check(_events_of(events, "channel_full").size() == 2,
		"2 次 channel_full 事件", "kinds=%s" % _event_kind_list(events))

	# 重新分配：初始 3 个远目标占满通道，随后近目标抢走最弱通道。
	var tws2 = TwsModel.new(rec, {"max_channels": 3})
	var far_targets: Array = [
		_target("f1", Vector3(0, 25000, 0), 10.0),
		_target("f2", Vector3(0, 26000, 0), 10.0),
		_target("f3", Vector3(0, 27000, 0), 10.0),
	]
	tws2.step(1.0, _snapshot(1.0, far_targets))
	var before := tws2.channels_export().size()
	var close_target: Array = [
		_target("f1", Vector3(0, 25000, 0), 10.0),
		_target("f2", Vector3(0, 26000, 0), 10.0),
		_target("f3", Vector3(0, 27000, 0), 10.0),
		_target("close", Vector3(0, 1000, 0), 10.0),
	]
	var out2: Dictionary = tws2.step(6.0, _snapshot(7.0, close_target))
	var ev2: Array = out2.get("events", [])
	check(not tws2.channel("close").is_empty(), "近距离新目标抢占通道",
		"channels=%d" % tws2.channels_export().size())
	check(_events_of(ev2, "target_dropped").size() >= 1,
		"被淘汰目标产生 target_dropped", "kinds=%s" % _event_kind_list(ev2))
	check(tws2.channels_export().size() == before,
		"通道数保持上限（%d）" % before)


func _event_kind_list(events: Array) -> String:
	var kinds: Array = []
	for raw in events:
		if raw is Dictionary:
			kinds.append(String((raw as Dictionary).get("kind", "")))
	return str(kinds)


# ═══════════════════════════════════════════════════════════════════
# 7. TWS 失锁 / 降级 / 移除 / 重新捕获
# ═══════════════════════════════════════════════════════════════════

func _probe_tws_lost_lock() -> void:
	print("")
	print("── 7. tws.gd：失锁 / 降级 / 移除 / 重新捕获 ──")
	var rec = Types.record("YW-R9")
	var tws = TwsModel.new(rec)
	var hold: Array = [_target("2001", Vector3(0, 5000, 0), 1400.0)]
	var all_events: Array = []
	for i in range(40):
		var out: Dictionary = tws.step(1.0, _snapshot(i + 1, hold))
		all_events.append_array(out.get("events", []))
	var locked_state := String(tws.channel("2001").get("state", ""))
	check(locked_state == TwsModel.STATE_FIRE_CONTROL,
		"失锁前已进入 FIRE_CONTROL", "state=%s" % locked_state)
	var quality_before := float(tws.channel("2001").get("quality", 0.0))

	# 目标消失 40 s：火控解算丢失 → 失锁降级 → 质量衰减 → 移除。
	for i in range(40):
		var out: Dictionary = tws.step(1.0, _snapshot(41 + i, []))
		all_events.append_array(out.get("events", []))
	var fc_lost := _events_of(all_events, "fire_control_lost")
	var lost := _events_of(all_events, "lock_lost")
	var dropped := _events_of(all_events, "target_dropped")
	check(fc_lost.size() >= 1, "漏刷新 → fire_control_lost（FIRE_CONTROL→TRACK）",
		"n=%d" % fc_lost.size())
	var lost_prev := ""
	if lost.size() > 0:
		lost_prev = String((lost[0] as Dictionary).get("previous", ""))
	check(lost.size() >= 1 and lost_prev == TwsModel.STATE_TRACK,
		"失锁事件：TRACK → DETECT 降级",
		"n=%d previous=%s age=%.0f s" % [lost.size(), lost_prev,
			float((lost[0] as Dictionary).get("age_s", -1.0)) if lost.size() > 0 else -1.0])
	var drop_quality := 1.0
	if dropped.size() > 0:
		drop_quality = float((dropped[0] as Dictionary).get("quality", 1.0))
	check(dropped.size() >= 1 and drop_quality < TwsModel.LOCK_DROP_QUALITY,
		"长时间无更新 → quality 见底 → target_dropped",
		"n=%d q=%.2f" % [dropped.size(), drop_quality])
	check(tws.channels_export().is_empty(),
		"目标通道已释放（channels=0）", "channels=%d" % tws.channels_export().size())

	# 重新捕获：目标回到球内，通道重建，25 s 内回到 TRACK 以上。
	var final_state := ""
	for i in range(25):
		var out: Dictionary = tws.step(1.0, _snapshot(121 + i, hold))
		all_events.append_array(out.get("events", []))
		final_state = String(tws.channel("2001").get("state", ""))
	var reacquired := TwsModel.STATES.has(final_state) and final_state != TwsModel.STATE_SEARCH \
		and final_state != TwsModel.STATE_DETECT
	check(reacquired, "重新捕获：目标恢复后重建通道并升回 TRACK 以上",
		"state=%s q=%.2f" % [final_state, float(tws.channel("2001").get("quality", 0.0))])
	check(_events_of(all_events, "target_detected").size() >= 2,
		"重新检测事件 target_detected",
		"n=%d" % _events_of(all_events, "target_detected").size())
	check(quality_before >= TwsModel.Q_FIRE
		and float(tws.channel("2001").get("quality", 0.0)) > TwsModel.Q_TRACK,
		"失锁清空后重新建立 track quality",
		"q_before=%.2f q_after=%.2f" % [quality_before, float(tws.channel("2001").get("quality", 0.0))])




# ═══════════════════════════════════════════════════════════════════
# 8. 光学凝视
# ═══════════════════════════════════════════════════════════════════

func _probe_optical() -> void:
	print("")
	print("── 8. optical.gd：可见光凝视 / 进度 / 锁定 / 失锁 ──")
	var opt_rec = Types.record("MS-OT2")
	var opt = OpticalModel.new({"optical": opt_rec})
	var tgt: Array = [_target("9001", Vector3(0, 8000, 0), 800.0, 300.0, 1000.0)]
	(tgt[0] as Dictionary)["classification"] = {"ship_class": "谷神改", "builder": "远环合作社", "role": "民用工作船"}
	var st := opt.start("optical", "9001")
	check(bool(st.get("ok", false)), "建立光学凝视通道", String(st.get("reason", "")))
	var snap := _snapshot(0.0, tgt)
	var all_events: Array = []
	var mid_progress := -1.0
	for i in range(45):
		var out: Dictionary = opt.step(1.0, snap)
		all_events.append_array(out.get("events", []))
		if i == 19:
			mid_progress = float((opt.channel("optical", "9001")).get("progress", 0.0))
	var ch: Dictionary = opt.channel("optical", "9001")
	check(mid_progress > 0.45 and mid_progress < 0.55,
		"8,000 km 凝视 20 s ≈ 50%（05 §2.1：40 s 识别）", "progress=%.2f" % mid_progress)
	check(absf(float(ch.get("required_s", 0.0)) - 40.0) < 0.5,
		"凝视所需时间 = 40 s @ 8,000 km", "required=%.1f s" % float(ch.get("required_s", 0.0)))
	check(String(ch.get("status", "")) == OpticalModel.STATUS_LOCKED,
		"凝视完成 → 锁定", "status=%s" % String(ch.get("status", "")))
	check(int(ch.get("level_support", 0)) == 3, "光学锁定 → L3 分类支撑（05 §S-03）",
		"level_support=%d" % int(ch.get("level_support", 0)))
	check(String((ch.get("classification", {}) as Dictionary).get("ship_class", "")) == "谷神改",
		"锁定输出分类（舰级），不含身份", JSON.stringify(ch.get("classification", {})))
	check(absf(float(ch.get("slant_range_km", 0.0)) - 8000.0) < 1.0
		and float(ch.get("measured_range_km", 0.0)) < 0.0,
		"光学不给距离解：measured=-1，仅几何距离", "slant=%.0f measured=%.1f" % [
			float(ch.get("slant_range_km", 0.0)), float(ch.get("measured_range_km", -1.0))])
	check(float(ch.get("refresh_s", 0.0)) > 0.0 and int(ch.get("samples", 0)) >= 5,
		"刷新采样计数", "refresh=%.1f s samples=%d" % [
			float(ch.get("refresh_s", 0.0)), int(ch.get("samples", 0))])
	check(_events_of(all_events, "channel_status").size() >= 3,
		"通道状态事件（acquiring/staring/locked）",
		"n=%d" % _events_of(all_events, "channel_status").size())
	print("[API] optical.channel_status(9001) = ", JSON.stringify(opt.channel_status("9001")))

	# 阴影区：不可见，进度不涨。
	var opt_shadow = OpticalModel.new({"optical": opt_rec})
	opt_shadow.start("optical", "9001")
	var shadow_snap := _snapshot(0.0, tgt, {"sun_illum": 0.0})
	opt_shadow.step(5.0, shadow_snap)
	opt_shadow.step(1.0, shadow_snap)
	var sh: Dictionary = opt_shadow.channel("optical", "9001")
	check(String(sh.get("status", "")) == OpticalModel.STATUS_LOST
		and String(sh.get("reason", "")) == "shadow",
		"阴影区光学不可见（05 §S-03）", "status=%s reason=%s" % [
			String(sh.get("status", "")), String(sh.get("reason", ""))])
	check(float(sh.get("progress", 1.0)) < 0.01, "阴影区凝视进度不增长")

	# 超出光学有效距离。
	var opt_far = OpticalModel.new({"optical": opt_rec})
	opt_far.start("optical", "9001")
	var far_snap := _snapshot(0.0, [_target("9001", Vector3(0, 20000, 0))])
	opt_far.step(2.0, far_snap)
	var fch: Dictionary = opt_far.channel("optical", "9001")
	check(String(fch.get("status", "")) == OpticalModel.STATUS_LOST
		and String(fch.get("reason", "")) == "out_of_range",
		"20,000 km > 15,000 km 光学有效距离", "reason=%s" % String(fch.get("reason", "")))

	# 自舰大幅机动 → 凝视重来（05 §S-03 缺陷）。
	var opt_mv = OpticalModel.new({"optical": opt_rec})
	opt_mv.start("optical", "9001")
	for i in range(20):
		opt_mv.step(1.0, _snapshot(i + 1, tgt))
	var before_reset := float(opt_mv.channel("optical", "9001").get("progress", 0.0))
	var move_snap := _snapshot(21.0, tgt)
	(move_snap["observer"] as Dictionary)["maneuver_g"] = 0.5
	var mv_out: Dictionary = opt_mv.step(1.0, move_snap)
	var mv_events: Array = mv_out.get("events", [])
	check(before_reset > 0.4 and float(opt_mv.channel("optical", "9001").get("progress", 1.0)) < 0.01,
		"自舰机动 > 0.02 g → 凝视清零重来", "before=%.2f after=%.2f" % [
			before_reset, float(opt_mv.channel("optical", "9001").get("progress", 1.0))])
	check(_events_of(mv_events, "stare_reset").size() >= 1, "stare_reset 事件")
	for i in range(10):
		opt_mv.step(1.0, _snapshot(22 + i, tgt))
	var mid_after := float(opt_mv.channel("optical", "9001").get("progress", 0.0))
	check(mid_after > 0.2 and mid_after < 0.35, "重来后 10 s 进度 ≈ 25%",
		"progress=%.2f" % mid_after)
	for i in range(35):
		opt_mv.step(1.0, _snapshot(32 + i, tgt))
	check(String(opt_mv.channel("optical", "9001").get("status", "")) == OpticalModel.STATUS_LOCKED,
		"重新凝视 40 s 后可再次锁定",
		"status=%s" % String(opt_mv.channel("optical", "9001").get("status", "")))


# ═══════════════════════════════════════════════════════════════════
# 9. IR 凝视通道
# ═══════════════════════════════════════════════════════════════════

func _probe_optical_ir() -> void:
	print("")
	print("── 9. optical.gd：IR 凝视通道（只给方位/距离档，不升 L3） ──")
	var ir_rec = Types.record("CH-IR2")
	var opt = OpticalModel.new({"ir": ir_rec})
	opt.start("ir", "9001")
	var tgt: Array = [_target("9001", Vector3(0, 20000, 0), 800.0, 310.0, 1600.0)]
	var statuses: Array = []
	for i in range(8):
		var out: Dictionary = opt.step(1.0, _snapshot(i + 1, tgt))
		var ch: Dictionary = opt.channel("ir", "9001")
		var st := String(ch.get("status", ""))
		if statuses.is_empty() or String(statuses[statuses.size() - 1]) != st:
			statuses.append(st)
	var ch: Dictionary = opt.channel("ir", "9001")
	check(String(ch.get("status", "")) == OpticalModel.STATUS_LOCKED,
		"IR 通道锁定", "status=%s" % String(ch.get("status", "")))
	check(int(ch.get("level_support", 9)) == 1,
		"IR 锁定只支撑 L1（05 §S-01：无距离、不分类）",
		"level_support=%d" % int(ch.get("level_support", 9)))
	check(int(ch.get("level_support", 9)) != 3 and (ch.get("classification", {}) as Dictionary).is_empty(),
		"IR 锁定不产生 L3 分类", "classification=%s" % JSON.stringify(ch.get("classification", {})))
	check(String(ch.get("range_band", "")) != "", "IR 输出远/中/近距离档",
		"range_band=%s" % String(ch.get("range_band", "")))
	check(float(ch.get("measured_range_km", 0.0)) < 0.0,
		"IR 不给距离解（05 §S-01）", "measured=%.1f" % float(ch.get("measured_range_km", 0.0)))
	check(String((opt.to_dict().get("sensors", {}) as Dictionary).get("ir", "")) == "CH-IR2",
		"IR 通道绑定 CH-IR2")


# ═══════════════════════════════════════════════════════════════════
# 10. TWS 与光学独立
# ═══════════════════════════════════════════════════════════════════

func _probe_independence() -> void:
	print("")
	print("── 10. TWS 与光学通道独立 ──")
	var tws = TwsModel.new(Types.record("YW-R9"))
	var opt = OpticalModel.new({"optical": Types.record("MS-OT2")})
	opt.start("optical", "2001")
	var tgt: Array = [_target("2001", Vector3(0, 5000, 0), 1400.0)]
	for i in range(45):
		var out: Dictionary = tws.step(1.0, _snapshot(i + 1, tgt))
		opt.step(1.0, _snapshot(i + 1, tgt))
	check(String(tws.channel("2001").get("state", "")) == TwsModel.STATE_FIRE_CONTROL,
		"独立测试起点：TWS 已火控")
	check(String(opt.channel("optical", "2001").get("status", "")) == OpticalModel.STATUS_LOCKED,
		"独立测试起点：光学已锁定")
	var tws_events: Array = []
	for i in range(20):
		var out: Dictionary = tws.step(1.0, _snapshot(46 + i, []))
		tws_events.append_array(out.get("events", []))
		opt.step(1.0, _snapshot(46 + i, tgt))
	check(_events_of(tws_events, "lock_lost").size() >= 1,
		"目标从 TWS 消失 → 失锁事件")
	check(String(opt.channel("optical", "2001").get("status", "")) == OpticalModel.STATUS_LOCKED,
		"同期光学仍保持锁定（通道独立）",
		"optical=%s tws=%s" % [
			String(opt.channel("optical", "2001").get("status", "")),
			String(tws.channel("2001").get("state", ""))])
	check(tws.channel("2001").get("state", "") != TwsModel.STATE_FIRE_CONTROL,
		"TWS 已降级，不影响光学通道")


# ═══════════════════════════════════════════════════════════════════
# 11. 纯净性 / 契约
# ═══════════════════════════════════════════════════════════════════

func _probe_contract() -> void:
	print("")
	print("── 11. RefCounted / 无 UI / JSON 契约 ──")
	var radar = RadarModel.new(Types.record("YW-R9"))
	var tws = TwsModel.new(Types.record("YW-R9"))
	var opt = OpticalModel.new({"optical": Types.record("MS-OT2")})
	check(radar is RefCounted and tws is RefCounted and opt is RefCounted,
		"三个模型都是 RefCounted（不是 Node）")
	check(not (radar is Node) and not (tws is Node) and not (opt is Node),
		"不依赖场景树 / Node")
	var ok_files: Array = []
	for path in ["res://sim/sensor_types.gd", "res://sim/radar.gd",
			"res://sim/tws.gd", "res://sim/optical.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var clean := not src.contains("extends Node") and not src.contains("res://ui/") \
			and not src.contains("extends Control") and not src.contains("_draw(")
		ok_files.append("%s=%s" % [path.get_file(), str(clean)])
		if not clean:
			check(false, "无 UI/Node 依赖：%s" % path)
	check(ok_files.size() == 4 and not str(ok_files).contains("false"),
		"四个 sim 文件均无 Node/UI 依赖", str(ok_files))
	var tws_json := JSON.stringify(tws.to_dict())
	var opt_json := JSON.stringify(opt.to_dict())
	var radar_json := JSON.stringify(radar.to_dict())
	check(tws_json.length() > 100 and not tws_json.contains("<Object"),
		"TWS 状态可 JSON 序列化（供 core/UI）", "%d chars" % tws_json.length())
	check(opt_json.length() > 50 and not opt_json.contains("<Object"),
		"光学通道状态可 JSON 序列化", "%d chars" % opt_json.length())
	check(radar_json.length() > 50 and not radar_json.contains("<Object"),
		"雷达状态可 JSON 序列化", "%d chars" % radar_json.length())
	print("[API] types:    V2SensorTypes.record(model) / record_from_dict / record_from_rack_sensor / validate_record")
	print("[API] radar:    V2RadarModel.new(rec).step(dt, snapshot) / scan_now / set_enabled / exposure_state / effective_radius_km")
	print("[API] tws:      V2TwsModel.new(rec,{max_channels}).step(dt, snapshot) / ingest / set_enabled / channel / to_dict")
	print("[API] optical:  V2OpticalModel.new({optical,ir}).start/stop/step(dt,snapshot)/channel_status/to_dict")
	print("[REPORT] radar exposure: ", JSON.stringify(RadarModel.exposure_state(Types.record("YW-R9"), 25.0)))
	print("[REPORT] state machine: ", str(TwsModel.STATES))
