extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# R5-OPTICAL-IR-1 headless probe：完整光学 / IR 通道模型（单次）
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/optical_ir_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。
#
# 覆盖：相机参数/FOV/IFOV、FOV 内外、地球/月球遮挡、光照/反照/眩光、角尺寸/SNR、
#       凝视/曝光/锁定/分类、运动模糊/角速度/机动、VIS/IR 等级铁律、多目标/多通道、
#       JSON/确定性/只读。
# ═══════════════════════════════════════════════════════════════════

const O := preload("res://framework/sim/optical_ir_channel.gd")

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("R5-OPTICAL-IR-1 PROBE · 完整光学 / IR 通道模型（单次）")
	print("════════════════════════════════════════════════════════════")
	_test_setup()
	_test_fov()
	_test_occlusion()
	_test_illumination()
	_test_resolution_snr()
	_test_stare_lock()
	_test_motion()
	_test_ir()
	_test_multi_channel()
	_test_errors_json()
	_print_results()


# ── helpers ──────────────────────────────────────────────────────

func _section_begin(name: String) -> void:
	_section = name
	print("")
	print("── %s ──" % name)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		var line := "%s · %s" % [_section, label]
		if detail != "":
			line += "  (" + detail + ")"
		_failures.append(line)
		print("[FAIL] %s  %s" % [label, detail])


func _eq(actual, expected, label: String, detail := "") -> void:
	if actual == expected:
		_pass += 1
		print("[PASS] %s" % label)
		return
	_fail += 1
	var d := "actual=%s expected=%s%s" % [str(actual), str(expected),
		(" · " + detail) if detail != "" else ""]
	_failures.append("%s · %s (%s)" % [_section, label, d])
	print("[FAIL] %s  %s" % [label, d])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	var diff := absf(actual - expected)
	_ok(diff <= tol, label, "actual=%s expected=%s diff=%s tol=%s" % [
		str(actual), str(expected), str(diff), str(tol)])


func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)


func _json_ok(v: Variant) -> bool:
	var txt := JSON.stringify(v)
	if txt.length() <= 2:
		return false
	var back = JSON.parse_string(txt)
	return back is Dictionary or back is Array


func _observer(pos := [7000.0, 0.0, 0.0], vel := [0.0, 0.0, 0.0], opts := {}) -> Dictionary:
	var o := O.default_observer("harmattan")
	o["pos_km"] = pos
	o["vel_kmps"] = vel
	if opts.get("g", null) != null:
		o["maneuver_g"] = float(opts["g"])
	if opts.get("rate", null) != null:
		o["angular_rate_dps"] = opts["rate"]
	return o


func _target(tid: String, pos: Array, opts := {}) -> Dictionary:
	return O.make_target(tid, pos, opts)


func _snap(targets: Array, env := {}, obs_opts := {}) -> Dictionary:
	var o := _observer(obs_opts.get("pos", [7000.0, 0.0, 0.0]),
		obs_opts.get("vel", [0.0, 0.0, 0.0]), obs_opts)
	return O.make_snapshot(0.0, o, targets, env)


func _model(optical_over := {}, ir_over := {}) -> Object:
	var sensors := O.default_sensors()
	for k in (optical_over as Dictionary).keys():
		(sensors["optical"] as Dictionary)[String(k)] = (optical_over as Dictionary)[k]
	for k in (ir_over as Dictionary).keys():
		(sensors["ir"] as Dictionary)[String(k)] = (ir_over as Dictionary)[k]
	var m = O.new()
	m.setup({"sensors": sensors})
	return m


func _step_for(m, snap: Dictionary, duration: float, dt := 0.5) -> void:
	var n := int(ceil(duration / dt))
	for i in range(n):
		m.step(dt, snap)


func _new_baseline_targets() -> Array:
	return [
		_target("NEAR", [7000.0, 8000.0, 0.0], {"size_m": 50.0, "classification": {"ship_class": "DDG"}}),
		_target("MID", [7000.0, 15000.0, 0.0], {"size_m": 50.0, "classification": {"ship_class": "DDG"}}),
		_target("FAR", [7000.0, 30000.0, 0.0], {"size_m": 50.0}),
		_target("OFF", [15000.0, 0.0, 0.0], {"size_m": 50.0}),
		_target("BEHIND", [-7000.0, 0.0, 0.0], {"size_m": 50.0}),
		_target("HOT", [7000.0, 8000.0, 0.0], {"size_m": 50.0, "temp_k": 600.0}),
	]


# ═══════════════════════════════════════════════════════════════════
# 1. 相机参数 / FOV / IFOV
# ═══════════════════════════════════════════════════════════════════

func _test_setup() -> void:
	_section_begin("1 相机参数 / FOV / IFOV / 模式")
	var m = O.new()
	_ok(m.errors.is_empty(), "默认 setup 无错误", str(m.errors))
	_eq(m.sensors.size(), 2, "VIS+IR 两个传感器")
	_ok(m.has_sensor("optical") and m.has_sensor("ir"), "VIS/IR 均可用")
	var vis: Dictionary = m.sensors_view()["optical"]
	var ir: Dictionary = m.sensors_view()["ir"]
	_eq(str(vis.get("model", "")), "MS-OT2", "VIS 型号 MS-OT2")
	_eq(str(ir.get("model", "")), "CH-IR2", "IR 型号 CH-IR2")
	_near(float(vis.get("aperture_m", 0.0)), 1.2, 1e-9, "VIS 口径 1.2 m")
	_near(float(vis.get("focal_m", 0.0)), 4.8, 1e-9, "VIS 焦距 4.8 m")
	_eq(int(vis.get("detector_px", 0)), 4096, "VIS 4096 px")
	_near(float(vis.get("pixel_pitch_um", 0.0)), 5.0, 1e-9, "VIS 像元 5 µm")
	_near(float(vis.get("fov_deg", 0.0)), 0.2444, 2e-4, "VIS FOV≈0.244°")
	_near(float(vis.get("ifov_urad", 0.0)), 1.0417, 1e-3, "VIS IFOV≈1.04 µrad")
	_near(float(vis.get("ifov_eff_urad", 0.0)), 1.0417, 1e-3, "VIS IFOV_eff=IFOV（非衍射限）")
	_ok(float(vis.get("diffraction_urad", 0.0)) < float(vis.get("ifov_urad", 0.0)),
		"VIS 衍射 < 探测器 IFOV")
	_near(float(ir.get("aperture_m", 0.0)), 0.35, 1e-9, "IR 口径 0.35 m")
	_near(float(ir.get("focal_m", 0.0)), 1.2, 1e-9, "IR 焦距 1.2 m")
	_near(float(ir.get("fov_deg", 0.0)), 0.7334, 2e-4, "IR FOV≈0.733°")
	_near(float(ir.get("ifov_urad", 0.0)), 12.5, 1e-6, "IR 探测器 IFOV=12.5 µrad")
	_ok(float(ir.get("ifov_eff_urad", 0.0)) >= float(ir.get("diffraction_urad", 0.0)) - 1e-9,
		"IR IFOV_eff 受衍射限")
	_eq(str(vis.get("band", "")), "0.4-0.7 um", "VIS 波段")
	_eq(str(ir.get("band", "")), "8-12 um", "IR 波段")
	_near(float(vis.get("refresh_s", 0.0)), 8.0, 1e-9, "VIS refresh 8 s")
	_near(float(ir.get("refresh_s", 0.0)), 1.0, 1e-9, "IR refresh 1 s")
	_near(float(vis.get("max_exposure_s", 0.0)), 1.0, 1e-9, "VIS 曝光 1 s")
	_near(float(ir.get("max_exposure_s", 0.0)), 0.25, 1e-9, "IR 曝光 0.25 s")
	# FOV 公式一致性
	var calc := rad_to_deg(2.0 * atan(4096.0 * 5.0e-6 / (2.0 * 4.8)))
	_near(float(vis.get("fov_deg", 0.0)), calc, 1e-9, "VIS FOV 与 detector/focal 一致")
	var calc_ir := rad_to_deg(2.0 * atan(1024.0 * 15.0e-6 / (2.0 * 1.2)))
	_near(float(ir.get("fov_deg", 0.0)), calc_ir, 1e-9, "IR FOV 与 detector/focal 一致")
	# 模式/只读
	_eq(str(m.vm_optical_ir().get("mode", "")), "shadow", "mode=shadow")
	_eq(bool(m.vm_optical_ir().get("authoritative", true)), false, "authoritative=false")
	_eq(bool((m.vm_optical_ir().get("writes", {}) as Dictionary).get("track_table", true)), false,
		"不写 TrackTable")
	_eq(bool((m.vm_optical_ir().get("writes", {}) as Dictionary).get("v15", true)), false,
		"不写 V15")
	# 缺传感器
	var only_optical = O.new()
	only_optical.setup({"sensors": {"optical": O.default_sensor("optical")}})
	_ok(only_optical.has_sensor("optical") and not only_optical.has_sensor("ir"), "可只配 VIS")
	var r_ir: Dictionary = only_optical.start_channel("ir", "T1")
	_eq(str(r_ir.get("reason", "")), "no_sensor", "缺 IR → no_sensor")
	_data_line("optics", "VIS fov=%.4f°/ifov=%.3fµrad · IR fov=%.4f°/ifov_eff=%.2fµrad" % [
		float(vis.get("fov_deg", 0.0)), float(vis.get("ifov_urad", 0.0)),
		float(ir.get("fov_deg", 0.0)), float(ir.get("ifov_eff_urad", 0.0))])


# ═══════════════════════════════════════════════════════════════════
# 2. FOV / 视轴 / 万向架
# ═══════════════════════════════════════════════════════════════════

func _test_fov() -> void:
	_section_begin("2 FOV 内 / 外 / 视轴 / 万向架")
	var m = _model()
	var snap := _snap([
		_target("ON", [7000.0, 8000.0, 0.0], {"size_m": 50.0}),
		_target("OFF", [15000.0, 0.0, 0.0], {"size_m": 50.0}),
	])
	var r0: Dictionary = m.start_channel("optical", "ON")
	_ok(bool(r0.get("ok", false)), "VIS 通道建立")
	var ch0: Dictionary = m.channel("optical", "ON")
	_near(float(ch0.get("fov_deg", 0.0)), 0.2444, 2e-4, "channel fov_deg 输出")
	m.step(1.0, snap)
	var on: Dictionary = m.channel("optical", "ON")
	_eq(str(on.get("status", "")), "staring", "视轴内 → staring")
	_ok(bool(on.get("visible", false)), "视轴内 visible")
	_near(float(on.get("off_axis_deg", -1.0)), 0.0, 1e-6, "ON off_axis=0")
	# 固定视轴 0°，目标 90° → fov_miss
	var m2 = _model()
	m2.set_boresight("optical", 0.0)
	m2.start_channel("optical", "OFF", {"boresight_deg": 0.0})
	m2.step(1.0, snap)
	var off: Dictionary = m2.channel("optical", "OFF")
	_eq(str(off.get("reason", "")), "fov_miss", "视轴外 → fov_miss")
	_eq(str(off.get("status", "")), "lost", "视轴外 status=lost")
	_ok(not bool(off.get("visible", true)), "视轴外 not visible")
	_ok(float(off.get("off_axis_deg", 0.0)) > float(off.get("fov_deg", 0.0)) * 0.5,
		"off_axis > FOV/2")
	# 手动转视轴到 90° → 可见
	var rb: Dictionary = m2.set_boresight("optical", 90.0)
	_ok(bool(rb.get("ok", false)), "手动 set_boresight")
	m2.step(1.0, snap)
	var off2: Dictionary = m2.channel("optical", "OFF")
	_ok(str(off2.get("reason", "")) != "fov_miss", "转视轴后不再 fov_miss")
	_ok(bool(off2.get("visible", false)), "转视轴后 visible")
	_data_line("fov", "fov=%.4f° half=%.4f°；off_axis 90° → fov_miss；set_boresight 后可见" % [
		float(on.get("fov_deg", 0.0)), float(on.get("fov_deg", 0.0)) * 0.5])


# ═══════════════════════════════════════════════════════════════════
# 3. 遮挡（地球/月球/环境 LOS）
# ═══════════════════════════════════════════════════════════════════

func _test_occlusion() -> void:
	_section_begin("3 地球/月球遮挡 / LOS")
	var m = _model()
	var behind := _snap([_target("BEHIND", [-7000.0, 0.0, 0.0], {"size_m": 50.0})])
	m.set_boresight("optical", -90.0)
	m.start_channel("optical", "BEHIND")
	m.step(1.0, behind)
	var ch: Dictionary = m.channel("optical", "BEHIND")
	_eq(str(ch.get("reason", "")), "occluded", "目标在地球背面 → occluded")
	_eq(str(ch.get("status", "")), "lost", "occluded status=lost")
	_ok(not bool(ch.get("visible", true)), "occluded not visible")
	# 环境 LOS=false
	var m2 = _model()
	var snap_los := _snap([_target("V", [7000.0, 8000.0, 0.0], {"size_m": 50.0})], {"los": false})
	m2.start_channel("optical", "V")
	m2.step(1.0, snap_los)
	_eq(str(m2.channel("optical", "V").get("reason", "")), "occluded", "snapshot los=false → occluded")
	# 月球遮挡：月球放在观测-目标连线上
	var m3 = _model()
	var snap_moon := _snap([_target("V", [7000.0, 8000.0, 0.0], {"size_m": 50.0})],
		{"moon": {"pos_km": [7000.0, 4000.0, 0.0], "radius_km": 1737.4}})
	m3.start_channel("optical", "V")
	m3.step(1.0, snap_moon)
	_eq(str(m3.channel("optical", "V").get("reason", "")), "occluded", "月球挡线 → occluded")
	# 月球不在线段上 → 不遮挡
	var m4 = _model()
	var snap_moon2 := _snap([_target("V", [7000.0, 8000.0, 0.0], {"size_m": 50.0})],
		{"moon": {"pos_km": [9000.0, 4000.0, 0.0], "radius_km": 1737.4}})
	m4.start_channel("optical", "V")
	m4.step(1.0, snap_moon2)
	_ok(str(m4.channel("optical", "V").get("reason", "")) != "occluded", "月球离线 → 不遮挡")
	_data_line("occlusion", "地球背面/环境 LOS/月球挡线 → occluded；月球离线不挡")


# ═══════════════════════════════════════════════════════════════════
# 4. 光照 / 地球反照 / 眩光
# ═══════════════════════════════════════════════════════════════════

func _test_illumination() -> void:
	_section_begin("4 光照 / 阴影 / 地球反照 / 太阳眩光")
	var m = _model()
	var targets := [_target("V", [7000.0, 8000.0, 0.0], {"size_m": 50.0})]
	m.start_channel("optical", "V")
	var shadow := _snap(targets, {"shadow": true, "sun_illum": 0.0})
	m.step(1.0, shadow)
	var ch: Dictionary = m.channel("optical", "V")
	_eq(str(ch.get("reason", "")), "too_dark", "阴影/太阳 0 → too_dark")
	_ok(float(ch.get("illum", 1.0)) < 0.1, "shadow illum<0.1")
	# 太阳 illum=1 → 可见
	var m2 = _model()
	m2.start_channel("optical", "V")
	var sun := _snap(targets, {"sun_illum": 1.0, "shadow": false})
	m2.step(1.0, sun)
	_ok(str(m2.channel("optical", "V").get("reason", "")) != "too_dark", "太阳 1 → 不 too_dark")
	_near(float(m2.channel("optical", "V").get("illum", 0.0)), 1.015, 1e-6, "illum≈1+albedo 弱补光")
	# 太阳直射视轴 → dazzled
	var m3 = _model()
	m3.start_channel("optical", "V")
	var glare := _snap(targets, {"sun_dir": [0.0, 1.0, 0.0]})
	m3.step(1.0, glare)
	_eq(str(m3.channel("optical", "V").get("reason", "")), "dazzled", "太阳在视轴 → dazzled")
	# 太阳 90° → 不 dazzled
	var m4 = _model()
	m4.start_channel("optical", "V")
	var side := _snap(targets, {"sun_dir": [1.0, 0.0, 0.0]})
	m4.step(1.0, side)
	_ok(str(m4.channel("optical", "V").get("reason", "")) != "dazzled", "太阳离轴 → 不 dazzled")
	_data_line("illum", "shadow→too_dark；illum=%s；sun_avoid_deg=5 → dazzled" %
		str(m2.channel("optical", "V").get("illum", 0.0)))


# ═══════════════════════════════════════════════════════════════════
# 5. 角尺寸 / SNR / 曝光 / 分类像素
# ═══════════════════════════════════════════════════════════════════

func _test_resolution_snr() -> void:
	_section_begin("5 角尺寸 / N_px / SNR / 曝光")
	var m = _model()
	var near := [_target("NEAR", [7000.0, 8000.0, 0.0], {"size_m": 50.0,
		"classification": {"ship_class": "DDG"}})]
	m.start_channel("optical", "NEAR")
	m.step(1.0, _snap(near))
	var ch: Dictionary = m.channel("optical", "NEAR")
	var exp_near := 50.0 / 8000000.0 / 1.0416666666666667e-6
	_near(float(ch.get("angular_size_rad", 0.0)), 50.0 / 8000000.0, 1e-15, "目标角尺寸 θ=size/R")
	_near(float(ch.get("n_px", 0.0)), exp_near, 1e-6, "N_px(50 m @ 8000 km)≈6")
	_ok(float(ch.get("snr_db", -99.0)) > float(ch.get("min_snr_db", 8.0)), "SNR 高于阈值")
	_ok(float(ch.get("exposure_s", 0.0)) <= 1.0 + 1e-9, "曝光 ≤ max_exposure")
	# 15,000 km：θ 更小，N_px≈3.2
	var m2 = _model()
	m2.start_channel("optical", "MID")
	m2.step(1.0, _snap([_target("MID", [7000.0, 15000.0, 0.0], {"size_m": 50.0})]))
	var mid: Dictionary = m2.channel("optical", "MID")
	_near(float(mid.get("n_px", 0.0)), 3.2, 1e-2, "N_px(50 m @ 15,000 km)≈3.2")
	# 30,000 km：需要把 range 扩到 40,000 才可见；N_px≈1.6 不分类
	var m3 = _model({"range_km": 40000.0})
	m3.start_channel("optical", "FAR")
	_step_for(m3, _snap([_target("FAR", [7000.0, 30000.0, 0.0], {"size_m": 50.0,
		"classification": {"ship_class": "DDG"}})]), 250.0)
	var far: Dictionary = m3.channel("optical", "FAR")
	_near(float(far.get("n_px", 0.0)), 1.6, 1e-2, "N_px(50 m @ 30,000 km)≈1.6")
	_eq(str(far.get("status", "")), "locked", "30k 仍可锁定（探测）")
	_ok(not bool(far.get("classify_ok", true)), "N_px<3 → 不可分类")
	_eq(int(far.get("level_support", -1)), 1, "不可分类时 VIS 仅 L1")
	# 口径/曝光影响 SNR
	var small = _model({"aperture_m": 0.6})
	small.start_channel("optical", "MID")
	small.step(1.0, _snap([_target("MID", [7000.0, 15000.0, 0.0], {"size_m": 50.0})]))
	var snr_small := float(small.channel("optical", "MID").get("snr_db", -99.0))
	var big = _model({"aperture_m": 2.4})
	big.start_channel("optical", "MID")
	big.step(1.0, _snap([_target("MID", [7000.0, 15000.0, 0.0], {"size_m": 50.0})]))
	var snr_big := float(big.channel("optical", "MID").get("snr_db", -99.0))
	_ok(snr_big > snr_small, "大口径 SNR 更高", "%.2f > %.2f" % [snr_big, snr_small])
	_near(snr_big - snr_small, 20.0 * O.log10(2.4 / 0.6), 1e-6, "SNR 口径 20log10 关系")
	# min_snr 强制 low_snr
	var m4 = _model({"min_snr_db": 100.0})
	m4.start_channel("optical", "MID")
	m4.step(1.0, _snap([_target("MID", [7000.0, 15000.0, 0.0], {"size_m": 50.0})]))
	_eq(str(m4.channel("optical", "MID").get("reason", "")), "low_snr", "min_snr 高 → low_snr")
	_data_line("resolution", "N_px 6@8k / 3.2@15k / 1.6@30k；SNR 口径关系验证")


# ═══════════════════════════════════════════════════════════════════
# 6. 凝视 / 锁定 / 分类 / 失锁保持
# ═══════════════════════════════════════════════════════════════════

func _test_stare_lock() -> void:
	_section_begin("6 凝视 / 锁定 / VIS 分类 L3 / 失锁")
	var m = _model()
	var target := _target("NEAR", [7000.0, 8000.0, 0.0], {"size_m": 50.0,
		"classification": {"ship_class": "DDG", "role": "escort"}})
	m.start_channel("optical", "NEAR")
	_step_for(m, _snap([target]), 20.0)
	var ch1: Dictionary = m.channel("optical", "NEAR")
	_eq(str(ch1.get("status", "")), "staring", "20 s：staring")
	_ok(float(ch1.get("progress", 0.0)) > 0.2 and float(ch1.get("progress", 0.0)) < 1.0,
		"进度在 0..1")
	_ok(float(ch1.get("required_s", 0.0)) >= 35.0 and float(ch1.get("required_s", 0.0)) <= 45.0,
		"8,000 km 所需凝视≈40 s", str(ch1.get("required_s", 0.0)))
	_step_for(m, _snap([target]), 30.0)
	var ch2: Dictionary = m.channel("optical", "NEAR")
	_eq(str(ch2.get("status", "")), "locked", "40+ s → locked")
	_ok(bool(ch2.get("locked", false)), "locked 标记")
	_ok(bool(ch2.get("classify_ok", false)), "lock 后像素/SNR 满足 → 分类")
	_eq(int(ch2.get("level_support", 0)), 3, "VIS 分类 → L3")
	_eq(str((ch2.get("classification", {}) as Dictionary).get("ship_class", "")), "DDG",
		"classification ship_class 来自目标")
	_eq(str(ch2.get("identity", "")), "unknown", "classification 不写 identity")
	_near(float(ch2.get("measured_range_km", 0.0)), -1.0, 1e-9, "不给测量距离")
	_ok(float(ch2.get("snr_db", 0.0)) >= float(ch2.get("min_snr_db", 8.0)), "锁定 SNR 达标")
	# 失锁保持：视轴转走 → lost，保留进度；恢复 → 继续
	var m2 = _model()
	m2.start_channel("optical", "NEAR")
	_step_for(m2, _snap([target]), 20.0)
	var before_prog := float(m2.channel("optical", "NEAR").get("progress", 0.0))
	m2.set_boresight("optical", 90.0)
	m2.step(1.0, _snap([target]))
	var lost: Dictionary = m2.channel("optical", "NEAR")
	_eq(str(lost.get("status", "")), "lost", "视轴失配 → lost")
	_ok(float(lost.get("progress", 1.0)) <= before_prog + 1e-9, "lost 后进度不增/保留")
	m2.set_boresight("optical", 0.0)
	m2.step(1.0, _snap([target]))
	_ok(str(m2.channel("optical", "NEAR").get("status", "")) in ["acquiring", "staring", "locked"],
		"恢复视轴 → 重新捕获")
	# 超过 lost_hold 后清零：把窗口调短
	var m3 = _model({"lost_hold_s": 0.5})
	m3.start_channel("optical", "NEAR")
	_step_for(m3, _snap([target]), 20.0)
	m3.set_boresight("optical", 90.0)
	m3.step(1.0, _snap([target]))
	m3.step(1.0, _snap([target]))
	_near(float(m3.channel("optical", "NEAR").get("stare_s", -1.0)), 0.0, 1e-9,
		"超出 lost_hold_s → 凝视清零")
	_data_line("stare", "required≈%.0f s；锁定→L3+classification；失锁保留/超时清零" %
		float(ch2.get("required_s", 0.0)))


# ═══════════════════════════════════════════════════════════════════
# 7. 运动模糊 / 相对角速度 / 平台机动
# ═══════════════════════════════════════════════════════════════════

func _test_motion() -> void:
	_section_begin("7 运动模糊 / 相对角速度 / 自舰机动")
	# 目标横向 10 km/s：角速度小但 smear>1 → blurred
	var m = _model()
	var fast := _target("FAST", [7000.0, 8000.0, 0.0], {"size_m": 50.0,
		"vel_kmps": [10.0, 0.0, 0.0]})
	m.start_channel("optical", "FAST")
	m.step(0.5, _snap([fast]))
	var ch: Dictionary = m.channel("optical", "FAST")
	_eq(str(ch.get("reason", "")), "blurred", "smear>1 → blurred")
	_ok(float(ch.get("smear_px", 0.0)) > 1.0, "smear_px >1")
	_ok(float(ch.get("omega_dps", 0.0)) < float(ch.get("track_rate_dps", 1.0)),
		"角速度低于跟瞄上限")
	# 目标 500 km/s：角速度快于 track_rate → too_fast
	var m2 = _model()
	var too_fast := _target("TOOFAST", [7000.0, 8000.0, 0.0], {"size_m": 50.0,
		"vel_kmps": [500.0, 0.0, 0.0]})
	m2.start_channel("optical", "TOOFAST")
	m2.step(0.5, _snap([too_fast]))
	_eq(str(m2.channel("optical", "TOOFAST").get("reason", "")), "too_fast",
		"角速度>track_rate → too_fast")
	# 低速目标：smear 小，可继续凝视
	var m3 = _model()
	var slow := _target("SLOW", [7000.0, 8000.0, 0.0], {"size_m": 50.0,
		"vel_kmps": [0.001, 0.0, 0.0]})
	m3.start_channel("optical", "SLOW")
	m3.step(0.5, _snap([slow]))
	_ok(str(m3.channel("optical", "SLOW").get("reason", "")) != "blurred", "低速目标不 blurred")
	# 自舰机动 > reset_maneuver_g → maneuver 重置
	var m4 = _model()
	m4.start_channel("optical", "SLOW")
	_step_for(m4, _snap([slow]), 10.0)
	_ok(float(m4.channel("optical", "SLOW").get("progress", 0.0)) > 0.0, "机动前有进度")
	m4.step(0.5, _snap([slow], {}, {"g": 0.03}))
	var man: Dictionary = m4.channel("optical", "SLOW")
	_eq(str(man.get("reason", "")), "maneuver", "自舰 0.03 g → maneuver")
	_near(float(man.get("stare_s", -1.0)), 0.0, 1e-9, "机动后凝视清零")
	# 自舰角速度 > reset_angular_rate_dps → 也计入 omega/track 超限
	var m5 = _model()
	m5.start_channel("optical", "SLOW")
	m5.step(0.5, _snap([slow], {}, {"rate": [0.0, 0.0, 2.0]}))
	var r5: Dictionary = m5.channel("optical", "SLOW")
	_ok(str(r5.get("reason", "")) in ["too_fast", "blurred"], "自舰 2°/s → too_fast/blurred")
	_data_line("motion", "smear=ω·t/IFOV；10 km/s→blurred，500 km/s→too_fast，0.03g→maneuver")


# ═══════════════════════════════════════════════════════════════════
# 8. IR（L1 铁律 / 阴影 / 波段 / 热对比）
# ═══════════════════════════════════════════════════════════════════

func _test_ir() -> void:
	_section_begin("8 IR：锁定 4 s / 阴影可用 / L1 / 热对比")
	var target := _target("IR1", [7000.0, 8000.0, 0.0], {"size_m": 50.0,
		"temp_k": 300.0, "area_m2": 1000.0})
	var m = _model()
	m.start_channel("ir", "IR1")
	m.step(2.0, _snap([target]))
	var ch: Dictionary = m.channel("ir", "IR1")
	_ok(str(ch.get("status", "")) in ["staring", "acquiring"], "IR 2 s 尚未锁定")
	_step_for(m, _snap([target]), 4.0)
	var ir: Dictionary = m.channel("ir", "IR1")
	_eq(str(ir.get("status", "")), "locked", "IR 4+ s → locked")
	_eq(bool(ir.get("locked", false)), true, "IR locked 标记")
	_eq(int(ir.get("level_support", -1)), 1, "IR 锁定 → L1（不升 L3）")
	_ok((ir.get("classification", {}) as Dictionary).is_empty(), "IR 不分类")
	_eq(str(ir.get("range_band", "")), "near", "IR range_band=near")
	_near(float(ir.get("measured_range_km", 0.0)), -1.0, 1e-9, "IR 不给测量距离")
	_eq(str(ir.get("identity", "")), "unknown", "IR identity=unknown")
	# 阴影内 IR 仍锁定
	var m2 = _model()
	m2.start_channel("ir", "IR1")
	var shadow := _snap([target], {"shadow": true, "sun_illum": 0.0})
	_step_for(m2, shadow, 5.0)
	var ir2: Dictionary = m2.channel("ir", "IR1")
	_eq(str(ir2.get("status", "")), "locked", "阴影内 IR 仍 locked")
	_eq(int(ir2.get("level_support", 0)), 1, "阴影 IR L1")
	_ok(float(ir2.get("contrast", 0.0)) < 1.0, "阴影热对比降低")
	# 热对比：热目标 contrast 更高
	var m3 = _model()
	m3.start_channel("ir", "HOT")
	m3.step(1.0, _snap([_target("HOT", [7000.0, 8000.0, 0.0], {"size_m": 50.0,
		"temp_k": 600.0, "area_m2": 1000.0})]))
	var hot: Dictionary = m3.channel("ir", "HOT")
	_ok(float(hot.get("contrast", 0.0)) > 1.0, "600 K 热对比 >1")
	_ok(float(hot.get("snr_db", 0.0)) > float(ir.get("snr_db", 0.0)), "热目标 SNR 更高")
	# IR 距离/波段
	var m4 = _model()
	var far := _target("IRFAR", [7000.0, 50000.0, 0.0], {"size_m": 50.0})
	m4.start_channel("ir", "IRFAR")
	m4.step(1.0, _snap([far]))
	var irf: Dictionary = m4.channel("ir", "IRFAR")
	_ok(str(irf.get("range_band", "")) in ["mid", "far"], "远距 IR range_band mid/far")
	_data_line("ir", "CH-IR2 locked 4s / 阴影可锁 / L1 / range_band / contrast")


# ═══════════════════════════════════════════════════════════════════
# 9. 多目标 / 多通道 / 容量
# ═══════════════════════════════════════════════════════════════════

func _test_multi_channel() -> void:
	_section_begin("9 多目标 / VIS+IR 独立 / 容量")
	var m = _model()
	var targets := [
		_target("A", [7000.0, 8000.0, 0.0], {"size_m": 50.0}),
		_target("B", [7000.0, 9000.0, 0.0], {"size_m": 50.0}),
	]
	var ra: Dictionary = m.start_channel("optical", "A")
	var rb: Dictionary = m.start_channel("optical", "B")
	_ok(bool(ra.get("ok", false)) and bool(rb.get("ok", false)), "VIS 同时开 A/B 通道")
	var ri: Dictionary = m.start_channel("ir", "A")
	_ok(bool(ri.get("ok", false)), "同目标 IR 通道独立")
	_ok(m.active_targets("optical").size() == 2, "VIS 活动目标 2")
	m.step(1.0, _snap(targets))
	_ok(bool(m.channel("optical", "A").get("visible", false))
		and bool(m.channel("optical", "B").get("visible", false)), "A/B 均可见")
	_ok(bool(m.channel("ir", "A").get("visible", false)), "IR A 可见")
	# 停 VIS A 不影响 VIS B/IR A
	m.stop_channel("optical", "A")
	_ok(m.channel("optical", "A").is_empty(), "停 VIS A")
	_ok(not m.channel("optical", "B").is_empty(), "VIS B 保留")
	_ok(not m.channel("ir", "A").is_empty(), "IR A 保留")
	m.stop_channel("ir")
	_ok(m.channel("ir", "A").is_empty(), "停 IR 全部")
	_ok(not m.channel("optical", "B").is_empty(), "停 IR 不影响 VIS B")
	# 容量
	var cap = _model({"max_channels": 1})
	var c1: Dictionary = cap.start_channel("optical", "A")
	var c2: Dictionary = cap.start_channel("optical", "B")
	_ok(bool(c1.get("ok", false)), "容量内第 1 通道")
	_eq(str(c2.get("reason", "")), "capacity_full", "容量满 → capacity_full")
	# 视轴指向输出
	_ok(m.sensors_view()["optical"].has("boresight_deg"), "sensor 输出 boresight_deg")
	_ok(m.sensors_view()["ir"].has("active_channels"), "sensor 输出 active_channels")
	_data_line("multi", "VIS A/B + IR A 独立；停 VIS A 不影响 B/IR；容量/视轴输出")


# ═══════════════════════════════════════════════════════════════════
# 10. 错误 / JSON / 确定性 / 只读
# ═══════════════════════════════════════════════════════════════════

func _test_errors_json() -> void:
	_section_begin("10 错误 / JSON / 确定性 / 只读")
	var m = O.new()
	var bad_kind: Dictionary = m.start_channel("nope", "T1")
	_eq(str(bad_kind.get("reason", "")), "unknown_kind", "未知 kind")
	var no_target: Dictionary = m.start_channel("optical", "")
	_eq(str(no_target.get("reason", "")), "target_required", "空 target")
	m.set_enabled(false)
	var disabled: Dictionary = m.start_channel("optical", "T1")
	_eq(str(disabled.get("reason", "")), "model_disabled", "禁用时 start 拒绝")
	m.set_enabled(true)
	# 目标缺失：通道可建，step 报 target_missing
	m.start_channel("optical", "GHOST")
	m.step(1.0, _snap([_target("REAL", [7000.0, 8000.0, 0.0])]))
	_eq(str(m.channel("optical", "GHOST").get("reason", "")), "target_missing", "step 目标缺失")
	# JSON
	var vm: Dictionary = m.vm_optical_ir()
	_ok(_json_ok(vm), "vm JSON 可序列化")
	_ok(_json_ok(m.export_channels()), "channels JSON")
	var txt := JSON.stringify(vm)
	_ok(txt.find("optical_ir.v1") >= 0, "JSON 含 schema")
	_ok(txt.find("Vector3") < 0, "JSON 无 Vector3")
	_ok(txt.find("writes_track_table") >= 0, "JSON 含只读标记")
	_ok(m.get("tracks") == null, "模型无 tracks 字段")
	_eq(str(m.to_dict().get("schema", "")), "optical_ir.v1", "to_dict schema")
	for key in ["schema", "mode", "authoritative", "enabled", "t", "sensors", "channels",
			"by_status", "events", "warnings", "writes", "summary"]:
		_ok(vm.has(key), "vm 字段 " + key)
	_eq(bool((vm.get("writes", {}) as Dictionary).get("track_table", true)), false,
		"vm.writes.track_table=false")
	# 确定性：两个独立模型同 steps
	var s := _snap([_target("A", [7000.0, 8000.0, 0.0], {"size_m": 50.0})])
	var a = _model()
	var b = _model()
	a.start_channel("optical", "A")
	b.start_channel("optical", "A")
	for i in range(20):
		a.step(0.5, s)
		b.step(0.5, s)
	_eq(JSON.stringify(a.vm_optical_ir()), JSON.stringify(b.vm_optical_ir()),
		"同输入 → vm 逐位一致")
	_eq(str(a.export_channels()), str(b.export_channels()), "channels 一致")
	# 重复只读调用不改状态
	var before := JSON.stringify(a.vm_optical_ir())
	var _unused = a.vm_optical_ir()
	_eq(JSON.stringify(a.vm_optical_ir()), before, "只读 vm 不改状态")
	# summary 计数
	var sum: Dictionary = a.summary()
	_eq(int(sum.get("channels", -1)), 1, "summary channels=1")
	_eq(bool(sum.get("writes_v15", true)), false, "summary 不写 V15")
	_data_line("json", "json=%d bytes；errors/边界；两实例确定性" % txt.length())


func _print_results() -> void:
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("OPTICAL IR PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("OPTICAL IR PROBE FAILED")
		quit(1)
	else:
		print("OPTICAL IR PROBE OK")
		quit(0)
