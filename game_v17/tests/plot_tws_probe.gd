extends SceneTree

## GHOST TRACK / APSIS · V17-SENSOR-1 headless probe
##
## 验证 game_v17/scripts/tws_bridge.gd（V15 state 只读 → V2 球形雷达 R_eff / TWS 通道）：
##   1) V2 framework/sim/{radar,tws,optical} 真实装载（R_eff、六态状态机、光学通道）；
##   2) 基于 V15 state.tracks 生成 TWS 六通道（DETECT→…→FIRE_CONTROL 全流程）；
##   3) 球形半径 = V2 R_eff（不是扇形）；暴露 = V2 exposure_state（ELINT 45,000 km / 20 s）；
##   4) EMCON / 关机 → 不输出球/通道（plot 不画）；光学通道可锁定；
##   5) 全程不修改 V15 state（clock / tracks / sensor_on / 观测字段不变）；
##   6) 输出 JSON 可序列化；`state.board_pos` 可为 plot 提供屏幕投影输入。
##
## 运行（工作区根目录）：
##   .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
##       --path .\game_v17 --script res://tests/plot_tws_probe.gd
## 期望末行 V17 SENSOR-1 TWS PROBE PASS，退出码 0。
## 日志：game_v17/tests/plot_tws_probe.log

const StateScript := preload("res://scripts/state.gd")
const BridgeScript := preload("res://scripts/tws_bridge.gd")
const RadarModel := preload("res://framework/sim/radar.gd")

const REF_RCS_M2 := 10.0
const EXPECTED_STATES := ["DETECT", "ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]

var ok := true
var pass_count := 0
var fail_count := 0


func _initialize() -> void:
	print("==== V17 SENSOR-1 TWS PROBE · GHOST TRACK / APSIS ====")
	print("[SRC] scripts/{state,tws_bridge,plot}.gd × framework/sim/{radar,tws,optical}.gd")
	_run()
	print("")
	print("[SUMMARY] pass=%d fail=%d" % [pass_count, fail_count])
	if ok:
		print("V17 SENSOR-1 TWS PROBE PASS")
	else:
		print("V17 SENSOR-1 TWS PROBE FAIL")
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


func _events_of(all_events: Array, kind: String) -> Array:
	var out: Array = []
	for raw in all_events:
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			out.append(raw)
	return out


func _json_ok(value: Variant) -> bool:
	var txt := JSON.stringify(value)
	return txt.length() > 2 and not txt.contains("<Object")


func _track_signature(st) -> String:
	var parts: Array = []
	parts.append(str(st.clock))
	parts.append(str(st.tracks.size()))
	for raw in st.tracks:
		var tr: Dictionary = raw
		parts.append("%s|%s|%s|%d" % [
			String(tr.get("id", "")),
			str(tr.get("r", Vector3.ZERO)),
			str(tr.get("v", Vector3.ZERO)),
			int(tr.get("level", 0)),
		])
	parts.append(str(st.sensor_on))
	parts.append(str(st.own_events))
	return "|".join(PackedStringArray(parts))


func _run() -> void:
	# ── 1. V15 state（帧 = T0+30：脚本时序已开 YW-R9 雷达）───────────
	print("")
	print("── 1. V15 state 只读场景（T+46）──")
	var st = StateScript.new()
	var t0: float = float(StateScript.T0)
	check(st.tracks.size() == 8, "V15 tracks 8 条（7 舰 + 9002 虚警）",
		"n=%d" % st.tracks.size())
	st.capture = true
	st.clock = t0 + 46.0
	st.refresh(st.clock)
	check(absf(st.tau() - 46.0) < 1.0e-6, "tau=46 s（脚本时序 T+20 雷达已开机 26 s）",
		"tau=%.1f" % st.tau())
	var radar_on: bool = bool((st.sensor_on.get("harmattan", {}) as Dictionary).get("YW-R9", false))
	check(radar_on, "V15 sensor_on：哈马丹 YW-R9 开机")

	# ── 2. bridge 装载 V2 模型 ──────────────────────────────────────
	print("")
	print("── 2. V17TwsBridge：V2 模型装载（framework/sim）──")
	var b = BridgeScript.new(st, {"ship": "harmattan", "radar_model": "YW-R9"})
	check(b.radar_record != null, "V2SensorTypes 记录装载（radar_record）")
	check(b.tws != null and b.optical != null, "V2TwsModel / V2OpticalModel 实例就绪")
	check(String(b.radar_record.model) == "YW-R9", "雷达型号 YW-R9",
		String(b.radar_record.model))
	check(absf(float(b.radar_record.refresh_s) - 6.0) < 1.0e-6, "刷新率 = 6 s")
	check(int(b.radar_record.track_capacity) == 6, "TWS 通道容量 = 6")
	check(bool(b.radar_record.spherical) and String(b.radar_record.scan_volume) == "sphere",
		"V2 记录：球形搜索体（非扇形）")

	# ── 3. step：TWS 六通道状态机 ──────────────────────────────────
	print("")
	print("── 3. step()：TWS 六通道 / 状态迁移 / 质量 / 更新率 ──")
	var sig_before := _track_signature(st)
	var out: Dictionary = b.step(-1.0)
	check(bool(out.get("ok", false)), "bridge.step 成功", String(out.get("reason", "")))
	check(bool(out.get("active", false)), "雷达 active（plot 可画球）")
	check(int(out.get("channel_count", 0)) == 6, "TWS 六通道（非本舰 6 个目标）",
		"n=%d" % int(out.get("channel_count", 0)))
	check(int(out.get("active_channels", 0)) == 6, "6 通道 active",
		"n=%d" % int(out.get("active_channels", 0)))
	var by_state: Dictionary = out.get("by_state", {})
	check(int(by_state.get("FIRE_CONTROL", 0)) == 6,
		"雷达开机 26 s 后六通道全部 FIRE_CONTROL", str(by_state))
	var chans: Array = out.get("channels", [])
	var ch0: Dictionary = chans[0] if chans.size() > 0 else {}
	check(String(ch0.get("short", "")) == "FC" and bool(ch0.get("fire_control_ready", false)),
		"短标签 FC / fire_control_ready", str(ch0.get("short", "")))
	check(float(ch0.get("quality", 0.0)) >= 0.85, "quality ≥0.85",
		"q=%.2f" % float(ch0.get("quality", 0.0)))
	check(absf(float(ch0.get("update_rate_hz", 0.0)) - 1.0 / 6.0) < 0.03,
		"更新率 ≈1/6 Hz", "%.3f" % float(ch0.get("update_rate_hz", 0.0)))
	check(float(ch0.get("age_s", 99.0)) <= 6.0, "age ≤ 扫描周期",
		"age=%.1f" % float(ch0.get("age_s", 99.0)))
	check(float(ch0.get("range_km", -1.0)) > 0.0, "通道带距离（plot/TWS 环用）",
		"%.0f km" % float(ch0.get("range_km", -1.0)))
	check(String(ch0.get("name", "")) != "" and String(ch0.get("batch", "")) != "",
		"通道 join V15 航迹资料（batch/name）", "%s %s" % [
			String(ch0.get("batch", "")), String(ch0.get("name", ""))])

	# 状态历史：单通道完整序列（V2Tws 内部 history）
	var raw_ch: Dictionary = b.tws.channel(String(ch0.get("target_track_id", "")))
	var hist_to: Array = []
	for raw_h in (raw_ch.get("history", []) as Array):
		if raw_h is Dictionary:
			hist_to.append(String((raw_h as Dictionary).get("to", "")))
	var seq_ok := true
	for wanted in EXPECTED_STATES:
		if not hist_to.has(wanted):
			seq_ok = false
	check(seq_ok, "单通道状态序列覆盖 DETECT→ACQUIRE→TRACK→STARE→FIRE_CONTROL", str(hist_to))
	check(hist_to.has("FIRE_CONTROL"), "状态机到达 FIRE_CONTROL")

	# 增量 step：更新计数/质量继续增长
	var cnt_before := int(ch0.get("update_count", 0))
	var out2: Dictionary = b.step(6.0)
	var ch1 := {}
	for raw_c in (out2.get("channels", []) as Array):
		if raw_c is Dictionary and String((raw_c as Dictionary).get("target_track_id", "")) \
				== String(ch0.get("target_track_id", "")):
			ch1 = raw_c
	check(int(ch1.get("update_count", 0)) > cnt_before, "step(6 s) 继续刷新（update_count 增长）",
		"%d→%d" % [cnt_before, int(ch1.get("update_count", 0))])
	check(bool(out2.get("ok", false)) and not bool(out2.get("state_modified", true)),
		"step 声明 state_modified=false")

	# ── 4. 球形雷达范围 / 暴露（V2 R_eff）──────────────────────────
	print("")
	print("── 4. 球形雷达 R_eff / 暴露（非扇形）──")
	var sph: Dictionary = b.radar_sphere()
	check(bool(sph.get("available", false)) and bool(sph.get("active", false)),
		"球形雷达 available/active")
	check(String(sph.get("shape", "")) == "sphere" and bool(sph.get("no_sector", false)),
		"shape=sphere / no_sector", str(sph.get("sphere", {}).get("shape", "")))
	check(absf(float(sph.get("nominal_radius_km", 0.0)) - 30000.0) < 1.0e-6,
		"标称球半径 30,000 km（YW-R9）")
	var eff := float(sph.get("effective_radius_km", 0.0))
	var eff_direct: float = RadarModel.effective_radius_km(b.radar_record, REF_RCS_M2, 0.0)
	check(absf(eff - eff_direct) < 1.0e-6 and absf(eff - 30000.0) < 1.0,
		"R_eff 与 V2RadarModel 直接计算一致", "%.3f km" % eff)
	check(absf(float(sph.get("track_radius_km", 0.0)) - 15000.0) < 1.0e-6,
		"稳定跟踪半径 15,000 km")
	check(absf(float(sph.get("refresh_s", 0.0)) - 6.0) < 1.0e-6, "球刷新 6 s")
	check(int(sph.get("targets_total", 0)) == 6 and int(sph.get("targets_in_sphere", 0)) == 6,
		"6 目标全部在球内", "total=%d in=%d" % [
			int(sph.get("targets_total", 0)), int(sph.get("targets_in_sphere", 0))])
	var exp: Dictionary = sph.get("exposure", {})
	check(bool(exp.get("exposed", false))
		and absf(float(exp.get("emission_level", 0.0)) - 1.0) < 1.0e-6,
		"暴露 emission_level=1.0（开机即暴露）")
	check(absf(float(exp.get("elint_intercept_range_km", 0.0)) - 45000.0) < 1.0,
		"ELINT 截获 45,000 km（V2 暴露模型）")
	check(absf(float(exp.get("fix_after_s", 0.0)) - 20.0) < 1.0e-6,
		"20 s 可定位（fix_after_s）")
	check(bool(exp.get("fixed", false)), "T+30 已被定位（fixed=true）",
		"progress=%.2f" % float(exp.get("fix_progress", 0.0)))
	var line := b.exposure_line()
	check(line.contains("R_eff 30,000 km") and line.contains("45,000"),
		"exposure_line 含真实 R_eff/截获距离", line)
	check(b.summary().contains("TWS") and b.summary().contains("RADAR ON"),
		"summary 可读", b.summary())

	# ── 5. snapshot：给 V2 模型的 world_snapshot ──────────────────
	print("")
	print("── 5. snapshot()：V15 tracks → V2 world_snapshot ──")
	var snap: Dictionary = b.snapshot()
	var targets: Array = snap.get("targets", [])
	check(targets.size() == 6, "world_snapshot 目标 6（非本舰）", "n=%d" % targets.size())
	var obs: Dictionary = snap.get("observer", {})
	check(String(obs.get("id", "")) == "1001", "observer = 本舰 track 1001",
		String(obs.get("id", "")))
	check((obs.get("pos_km", null) is Array) and (obs.get("pos_km", []) as Array).size() == 3,
		"observer pos_km 为 3D 局部坐标")
	var tgt0: Dictionary = targets[0] if targets.size() > 0 else {}
	check((tgt0.get("pos_km", null) is Array) and tgt0.has("rcs_m2") and tgt0.has("classification"),
		"目标行含 pos_km/rcs_m2/classification")
	check(_json_ok(snap) and _json_ok(out), "step/snapshot 输出 JSON 可序列化")

	# plot 投影输入：每个通道目标都能由 state.board_pos 算屏幕点
	var proj_ok := true
	for raw_pc in chans:
		var pcid := String((raw_pc as Dictionary).get("target_track_id", ""))
		var trp: Dictionary = st.track_by_id(pcid)
		if trp.is_empty():
			proj_ok = false
			continue
		var pp = st.board_pos(trp, st.tau())
		if not (pp is Vector3) or (pp as Vector3).length() < 1.0:
			proj_ok = false
	check(proj_ok, "plot 可用 state.board_pos 投影全部通道目标")

	# ── 6. 关机 / EMCON：不输出球与通道 ─────────────────────────
	print("")
	print("── 6. 雷达关机 / EMCON ──")
	st.set_sensor("harmattan", 0, false)   # YW-R9 在第 1 格
	check(not bool(b.is_radar_on()), "关机后 is_radar_on=false")
	var off: Dictionary = b.step(1.0)
	check(bool(off.get("ok", false)) and not bool(off.get("active", true)),
		"关机后 step.active=false（plot 不画球）")
	var off_sph: Dictionary = off.get("sphere", {})
	check(not bool(off_sph.get("active", true))
		and not bool((off_sph.get("exposure", {}) as Dictionary).get("exposed", true)),
		"关机后球形 active=false / 无暴露")
	st.set_sensor("harmattan", 0, true)
	check(bool(b.is_radar_on()), "重新开机 is_radar_on=true")
	st.set_emcon("harmattan", true)
	check(not bool(b.is_radar_on()), "EMCON 时 is_radar_on=false")
	var emcon_out: Dictionary = b.step(0.5)
	check(not bool(emcon_out.get("active", true)), "EMCON 时 step.active=false")
	st.set_emcon("harmattan", false)
	check(bool(b.is_radar_on()), "解除 EMCON 恢复")

	# ── 7. 光学 / IR 通道（V2OpticalModel）──────────────────────
	print("")
	print("── 7. 光学/IR 通道（V2OpticalModel）──")
	check(b.optical_channels().is_empty(), "未建通道时光学通道 0")
	var st_opt: Dictionary = b.start_optical("2001")
	check(bool(st_opt.get("ok", false)), "建立 VIS 凝视通道（2001）",
		String(st_opt.get("reason", "")))
	b.step(5.0)
	var opt_ch: Array = b.optical_channels()
	check(opt_ch.size() == 1, "1 条 VIS 通道", "n=%d" % opt_ch.size())
	var vis: Dictionary = opt_ch[0] if opt_ch.size() > 0 else {}
	check(String(vis.get("status", "")) == "locked"
		and float(vis.get("progress", 0.0)) >= 1.0,
		"VIS 凝视 5 s 锁定（目标 ~319 km）", "status=%s" % String(vis.get("status", "")))
	check(int(vis.get("level_support", 0)) == 3, "VIS 锁定支撑 L3")
	b.stop_optical()
	check(b.optical_channels().is_empty(), "stop_optical 清空通道")

	# ── 8. 不修改 V15 state ─────────────────────────────────────
	print("")
	print("── 8. 只读契约：bridge 不修改 state ──")
	var sig_after := _track_signature(st)
	check(sig_before == sig_after, "state.clock/tracks/sensor_on/own_events 未被 bridge 修改")
	check(st.tracks.size() == 8, "tracks 数量不变")
	check(_json_ok(b.last_step()), "last_step JSON 可序列化")

	# ── 9. 报告 ─────────────────────────────────────────────────
	print("")
	print("[API] V17TwsBridge.new(state, {ship,radar_model}) / step(dt<0 自动追帧|dt>=0) / channels() / radar_sphere() / exposure_line() / optical_channels() / start_optical/start_ir/stop_optical / snapshot()")
	print("[API] plot：_draw_radar_sphere()（SPHERICAL SEARCH · R_eff ... km，1px 球壳线框）/ _draw_tws_channels()（六态环 + 短标签 SRCH/DET/ACQ/TRK/STARE/FC，蓝/琥珀）/ _v17_exposure_line()")
	print("[REPORT] bridge: ", b.summary())
	print("[REPORT] by_state: ", JSON.stringify(by_state))
	print("[REPORT] sphere: ", JSON.stringify({
		"shape": sph.get("shape", ""), "no_sector": sph.get("no_sector", false),
		"nominal_km": sph.get("nominal_radius_km", 0.0),
		"eff_km": sph.get("effective_radius_km", 0.0),
		"track_km": sph.get("track_radius_km", 0.0),
		"refresh_s": sph.get("refresh_s", 0.0),
		"in_sphere": sph.get("targets_in_sphere", 0),
	}))
	print("[REPORT] channel[0]: ", JSON.stringify(ch0))
