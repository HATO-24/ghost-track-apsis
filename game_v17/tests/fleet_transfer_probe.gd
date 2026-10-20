extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# 阶段2-FLEET-ORBIT-1 最小 probe：5 舰独立 CR3BP 传播
#
# 运行：
#   tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless \
#     --path "D:\GHOST TRACK_APSIS\game_v17" --script res://tests/fleet_transfer_probe.gd
# 退出码：0 = 全过；1 = 有 FAIL。只跑一次；不接 UI。
# ═══════════════════════════════════════════════════════════════════

const FleetTransfer := preload("res://framework/sim/fleet_transfer.gd")
const TransferPlanner := preload("res://framework/sim/transfer_planner.gd")
const Physics := preload("res://framework/sim/cislunar_physics.gd")

const CACHE_PATH := "res://framework/content/transfer_l4_l1_fleet_cached.json"
const SHIPS := ["apsis", "harmattan", "ferry", "watchtower", "deepwell"]
const BATCHES := ["1000", "1001", "1002", "1003", "1004"]

var _pass := 0
var _fail := 0
var _section := ""
var _data: Array[String] = []
var _failures: Array[String] = []

func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("STAGE2-FLEET-ORBIT-1 PROBE · 5 舰独立 CR3BP 传播")
	print("════════════════════════════════════════════════════════════")
	_test_cache()
	_test_cache_plan()
	_test_fresh_plan()
	_test_independent_trajectories()
	_test_samples()
	_test_summary_json()
	_test_boundaries()
	print("────────────────────────────────────────────────────────────")
	for d in _data:
		print("[DATA] ", d)
	print("────────────────────────────────────────────────────────────")
	print("V17 FLEET TRANSFER PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("V17 FLEET TRANSFER PROBE FAILED")
		quit(1)
	else:
		print("V17 FLEET TRANSFER PROBE OK")
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

func _arr3_finite(a) -> bool:
	if not (a is Array) or (a as Array).size() < 3:
		return false
	var arr: Array = a
	for i in range(3):
		if not is_finite(float(arr[i])):
			return false
	return true

func _vec(a) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		var arr: Array = a
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO

func _state_finite(st: Dictionary) -> bool:
	return _arr3_finite(st.get("r", [])) and _arr3_finite(st.get("v", []))

func _data_line(label: String, value: String) -> void:
	_data.append(label + " = " + value)

func _row_map(rows: Array) -> Dictionary:
	var out := {}
	for raw in rows:
		out[String((raw as Dictionary).get("ship_id", ""))] = raw
	return out

# ═══════════════════════════════════════════════════════════════════
# 1. 缓存 JSON
# ═══════════════════════════════════════════════════════════════════

func _test_cache() -> void:
	_section_begin("1 缓存 JSON")
	_ok(FileAccess.file_exists(CACHE_PATH), "缓存文件存在")
	var text := FileAccess.get_file_as_string(CACHE_PATH)
	_ok(text.length() > 10000, "缓存文本较大", "len=%d" % text.length())
	var parsed = JSON.parse_string(text)
	_ok(parsed is Dictionary, "缓存 JSON 可解析")
	var c: Dictionary = parsed if parsed is Dictionary else {}
	_eq(String(c.get("schema", "")), "v17_fleet_transfer_cache.v1", "cache schema")
	_eq(String(c.get("fleet", "")), "transit_l4_l1", "cache fleet")
	_eq(String(c.get("source_port", "")), "L4-02 Hammer", "cache source_port")
	_eq(String(c.get("target_port", "")), "L1-Meridian-05", "cache target_port")
	_near(float(c.get("tof_s", 0.0)), 6.0 * 86400.0, 1.0e-6, "cache TOF=6 天")
	_ok(bool(c.get("deterministic", false)), "cache deterministic")
	var ships: Array = c.get("ships", []) if c.get("ships") is Array else []
	_eq(ships.size(), 5, "cache 5 舰")
	var samples: Array = c.get("samples", []) if c.get("samples") is Array else []
	_eq(samples.size(), 11, "cache 11 采样")
	var rows := _row_map(ships)
	for i in range(SHIPS.size()):
		var sid: String = SHIPS[i]
		_ok(rows.has(sid), "cache 舰: " + sid)
		if rows.has(sid):
			var r: Dictionary = rows[sid]
			_eq(String(r.get("batch", "")), BATCHES[i], "cache %s batch" % sid)
			_ok(_state_finite(r.get("initial_state_rot", {})), "cache %s initial 有限" % sid)
			_ok(_state_finite(r.get("departure_state_rot", {})), "cache %s departure 有限" % sid)
			_ok(_state_finite(r.get("arrival_state_rot", {})), "cache %s arrival 有限" % sid)
			_ok(bool(r.get("independent_propagation", false)), "cache %s independent" % sid)
			_ok(float(r.get("arrival_error_km", -1.0)) >= 0.0, "cache %s arrival_error" % sid)
			_ok(float(r.get("arrival_speed_kmps", -1.0)) >= 0.0, "cache %s arrival_speed" % sid)
			_ok(bool(r.get("within_gate", false)), "cache %s within_gate" % sid)
	for raw in samples:
		var sr: Dictionary = raw
		_ok(_arr3_finite(sr.get("t_s", [NAN])) or is_finite(float(sr.get("t_s", NAN))),
			"cache 采样 t 有限")
		var ss: Array = sr.get("ships", [])
		_eq(ss.size(), 5, "cache 采样 5 舰")
		for sw in ss:
			_ok(_arr3_finite((sw as Dictionary).get("pos_rot_km", [])), "cache 采样 pos 有限")
			_ok((sw as Dictionary).has("rel_to_flagship_km"), "cache 采样相对旗舰")
	_data_line("cache", "ships=5 samples=11 tof=6d bytes=%d" % text.length())

# ═══════════════════════════════════════════════════════════════════
# 2. 从缓存 plan
# ═══════════════════════════════════════════════════════════════════

func _test_cache_plan() -> void:
	_section_begin("2 缓存 plan")
	var ft = FleetTransfer.new()
	var res: Dictionary = ft.plan({"use_cache": true, "cache_path": CACHE_PATH})
	_ok(bool(res.get("ok", false)), "cache plan ok", str(ft.errors))
	_ok(ft.ready, "cache plan ready")
	_eq(ft.fleet_rows.size(), 5, "cache plan 5 舰")
	_eq(ft.samples.size(), 11, "cache plan 11 采样")
	_near(ft.tof_s, 6.0 * 86400.0, 1.0e-6, "cache plan TOF")
	_ok(ft.has_ship("apsis"), "cache plan has apsis")
	_ok(not ft.has_ship("no_ship"), "cache plan no unknown")
	_ok(ft.row_for("apsis").has("arrival_state_rot"), "row_for apsis")
	_eq(ft.row_for("no_ship").size(), 0, "row_for 未知空")
	var smp: Dictionary = ft.sample(ft.tof_s * 0.5)
	_ok(bool(smp.get("ok", false)), "cache sample ok")
	_eq(String(smp.get("phase", "")), "cruise", "cache sample phase")
	_data_line("cache_plan", "ready/cache rows=5 samples=11")

func _rows_close(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var ma := _row_map(a)
	var mb := _row_map(b)
	for sid in ma.keys():
		if not mb.has(sid):
			return false
		var ra: Dictionary = ma[sid]
		var rb: Dictionary = mb[sid]
		for k in ["arrival_error_km", "arrival_speed_kmps", "departure_dv_mps",
				"arrival_dv_mps", "total_dv_mps"]:
			if absf(float(ra.get(k, 0.0)) - float(rb.get(k, 0.0))) > 1.0e-4:
				return false
		if int(ra.get("propagated_steps", -1)) != int(rb.get("propagated_steps", -2)):
			return false
		for st_key in ["initial_state_rot", "departure_state_rot", "arrival_state_rot"]:
			var sa: Dictionary = ra.get(st_key, {})
			var sb: Dictionary = rb.get(st_key, {})
			for comp in ["r", "v"]:
				var aa: Array = sa.get(comp, [])
				var bb: Array = sb.get(comp, [])
				if aa.size() != bb.size():
					return false
				for i in range(aa.size()):
					if absf(float(aa[i]) - float(bb[i])) > 0.01:
						return false
	return true

func _samples_close(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i in range(a.size()):
		var sa: Dictionary = a[i]
		var sb: Dictionary = b[i]
		if absf(float(sa.get("t_s", 0.0)) - float(sb.get("t_s", -1.0))) > 1.0e-6:
			return false
		var ma := _row_map(sa.get("ships", []))
		var mb := _row_map(sb.get("ships", []))
		for sid in ma.keys():
			if not mb.has(sid):
				return false
			var ra: Dictionary = ma[sid]
			var rb: Dictionary = mb[sid]
			var pa := _vec(ra.get("pos_rot_km", []))
			var pb := _vec(rb.get("pos_rot_km", []))
			if (pa - pb).length() > 0.1:
				return false
			var va := _vec(ra.get("vel_rot_kmps", []))
			var vb := _vec(rb.get("vel_rot_kmps", []))
			if (va - vb).length() > 1.0e-5:
				return false
	return true

func _summary_close(a: Dictionary, b: Dictionary) -> bool:
	var aa: Dictionary = a.get("arrival", {})
	var ba: Dictionary = b.get("arrival", {})
	if absf(float(aa.get("max_error_km", 0.0)) - float(ba.get("max_error_km", 1.0))) > 1.0e-4:
		return false
	if absf(float(aa.get("max_speed_kmps", 0.0)) - float(ba.get("max_speed_kmps", 1.0))) > 1.0e-9:
		return false
	var ad: Dictionary = a.get("dv", {})
	var bd: Dictionary = b.get("dv", {})
	for k in ["sum_total_mps", "avg_total_mps"]:
		if absf(float(ad.get(k, 0.0)) - float(bd.get(k, 0.0))) > 1.0e-4:
			return false
	return true

# ═══════════════════════════════════════════════════════════════════
# 3. 现算 plan（独立传播）
# ═══════════════════════════════════════════════════════════════════

func _test_fresh_plan() -> void:
	_section_begin("3 现算 plan")
	var t0 := Time.get_ticks_msec()
	var ft = FleetTransfer.new()
	var res: Dictionary = ft.plan()
	_ok(bool(res.get("ok", false)), "fresh plan ok", str(ft.errors))
	_ok(ft.ready, "fresh ready")
	_eq(ft.errors.size(), 0, "fresh 无 errors")
	_eq(ft.fleet_rows.size(), 5, "fresh 5 舰行")
	_eq(ft.samples.size(), 11, "fresh 11 采样")
	_near(ft.tof_s, 6.0 * 86400.0, 1.0e-6, "fresh TOF=6d")
	var rows := _row_map(ft.fleet_rows)
	_ok(rows.size() == 5, "fresh 舰 id 唯一")
	for i in range(SHIPS.size()):
		var sid: String = SHIPS[i]
		_ok(rows.has(sid), "fresh 舰 " + sid)
		if not rows.has(sid):
			continue
		var r: Dictionary = rows[sid]
		_eq(String(r.get("batch", "")), BATCHES[i], "fresh %s batch" % sid)
		_ok(String(r.get("role", "")) != "", "fresh %s role" % sid)
		_ok(_arr3_finite(r.get("offset_km", [])), "fresh %s offset" % sid)
		_ok(_arr3_finite(r.get("offset_kmps", [])), "fresh %s offset_v" % sid)
		_ok(_state_finite(r.get("initial_state_rot", {})), "fresh %s initial" % sid)
		_ok(_state_finite(r.get("departure_state_rot", {})), "fresh %s departure" % sid)
		_ok(_state_finite(r.get("arrival_state_rot", {})), "fresh %s arrival" % sid)
		_ok(bool(r.get("independent_propagation", false)), "fresh %s independent" % sid)
		_ok(int(r.get("propagated_steps", 0)) > 0, "fresh %s propagated_steps>0" % sid)
		_ok(float(r.get("departure_dv_mps", 0.0)) > 0.0, "fresh %s departure_dv>0" % sid)
		_ok(float(r.get("arrival_dv_mps", 0.0)) > 0.0, "fresh %s arrival_dv>0" % sid)
		_ok(float(r.get("total_dv_mps", 0.0)) > 0.0, "fresh %s total_dv>0" % sid)
		var err := float(r.get("arrival_error_km", 99999.0))
		var spd := float(r.get("arrival_speed_kmps", 999.0))
		_ok(err <= float(r.get("gate_radius_km", 0.0)), "fresh %s 到达误差<=3000" % sid,
			"%.1f km" % err)
		_ok(spd <= float(r.get("gate_speed_kmps", 0.0)), "fresh %s 到达速度<=3" % sid,
			"%.3f km/s" % spd)
		_ok(bool(r.get("within_gate", false)), "fresh %s within_gate" % sid)
	# 与缓存一致（确定性）
	var cache_ft = FleetTransfer.new()
	cache_ft.plan({"use_cache": true, "cache_path": CACHE_PATH})
	_ok(_rows_close(ft.fleet_rows, cache_ft.fleet_rows),
		"现算 rows 与缓存一致（容差/确定性）")
	_ok(_samples_close(ft.samples, cache_ft.samples),
		"现算 samples 与缓存一致（容差）")
	_ok(_summary_close(ft.summary(), cache_ft.summary()),
		"现算 summary 与缓存一致（容差）")
	var sm: Dictionary = ft.summary()
	_eq(String(sm.get("schema", "")), "v17_fleet_transfer.v1", "summary schema")
	_eq(String(sm.get("fleet", "")), "transit_l4_l1", "summary fleet")
	_eq(int(sm.get("ship_count", -1)), 5, "summary ship_count=5")
	_eq(int(sm.get("sample_count", -1)), 11, "summary sample_count=11")
	_ok(bool((sm.get("arrival", {}) as Dictionary).get("all_within_gate", false)),
		"summary all_within_gate")
	_ok(float((sm.get("arrival", {}) as Dictionary).get("max_error_km", 99999.0)) < 3000.0,
		"summary max_error<3000")
	_eq((sm.get("ships", []) as Array).size(), 5, "summary ships 5")
	_data_line("fresh", "ms=%d arrival_errs=%s total_dv=%s" % [
		Time.get_ticks_msec() - t0,
		str(rows.keys().map(func(k): return "%.0f" % float(rows[k].get("arrival_error_km", 0.0)))),
		str(sm.get("dv", {}).get("rows", []).map(func(x): return "%.0f" % float(x.get("total_dv_mps", 0.0))))])

# ═══════════════════════════════════════════════════════════════════
# 4. 独立轨迹（不是 timeline+常量偏移）
# ═══════════════════════════════════════════════════════════════════

func _test_independent_trajectories() -> void:
	_section_begin("4 独立轨迹")
	var ft = FleetTransfer.new()
	ft.plan()
	var baseline: Dictionary = TransferPlanner.plan({"tof_days": [6.0]})
	_ok(bool(baseline.get("ok", false)), "baseline planner ok")
	var timeline: Array = baseline.get("timeline", [])
	_eq(timeline.size(), 11, "baseline timeline 11")
	var rows := _row_map(ft.fleet_rows)
	var samples: Array = ft.samples
	# 旗舰应与 baseline timeline 一致（同初速 0 偏移）
	var flag_row: Dictionary = rows.get("apsis", {})
	var offset_map := {}
	for raw in ft.fleet_rows:
		offset_map[String((raw as Dictionary).get("ship_id", ""))] = _vec((raw as Dictionary).get("offset_km", []))
	var flag_max := 0.0
	var ship_dev_max := {}
	for i in range(samples.size()):
		var srow: Dictionary = samples[i]
		var t := float(srow.get("t_s", 0.0))
		var base_pos := _vec((timeline[mini(i, timeline.size() - 1)] as Dictionary).get("pos_rot_km", []))
		for raw in (srow.get("ships", []) as Array):
			var sr: Dictionary = raw
			var sid := String(sr.get("ship_id", ""))
			var actual := _vec(sr.get("pos_rot_km", []))
			var expected := base_pos + _vec(offset_map.get(sid, []))
			var dev := (actual - expected).length()
			if sid == "apsis":
				flag_max = maxf(flag_max, dev)
			else:
				ship_dev_max[sid] = maxf(float(ship_dev_max.get(sid, 0.0)), dev)
	_ok(flag_max < 2.0, "旗舰采样与 baseline timeline 一致", "max=%.3f km" % flag_max)
	for sid in ["harmattan", "ferry", "watchtower", "deepwell"]:
		_ok(float(ship_dev_max.get(sid, 0.0)) > 1.0,
			"%s 轨迹偏离 baseline+常量偏移 >1km" % sid,
			"max_dev=%.1f km" % float(ship_dev_max.get(sid, 0.0)))
		_ok(ship_dev_max.get(sid) != null, "%s 有独立传播差异" % sid)
	# 采样点相对旗舰偏移随时间变化（不是常量）
	var rel_mid := {}
	var smp0: Dictionary = ft.sample(0.0)
	var smpm: Dictionary = ft.sample(ft.tof_s * 0.5)
	var smpe: Dictionary = ft.sample(ft.tof_s)
	for phase_rows in [smp0.get("ships", []), smpm.get("ships", []), smpe.get("ships", [])]:
		for raw in phase_rows:
			var sr: Dictionary = raw
			var sid := String(sr.get("ship_id", ""))
			if sid == "apsis":
				continue
			var mag := float(sr.get("rel_to_flagship_mag_km", -1.0))
			_ok(mag >= 0.0, "%s rel_to_flagship 非负" % sid)
			if phase_rows == smpm.get("ships", []):
				rel_mid[sid] = mag
			# 采样点偏移非零（速度偏移导致）
			_ok(mag > 0.0, "%s 采样 relative 非零" % sid)
	for sid in ["harmattan", "ferry", "watchtower", "deepwell"]:
		var off_len := _vec(rows[sid].get("offset_km", [])).length()
		_datum(off_len, sid)
		_ok(rel_mid.has(sid), "mid rel " + sid)
		_ok(absf(float(rel_mid.get(sid, 0.0)) - off_len) > 0.01 or off_len == 0.0,
			"%s mid 偏移 != 初始常量" % sid)
	# 每舰 arrival 与末采样一致
	var last: Dictionary = samples[samples.size() - 1]
	var last_map := _row_map(last.get("ships", []))
	for sid in SHIPS:
		var arr := _vec(rows[sid].get("arrival_state_rot", {}).get("r", []))
		var lastp := _vec(last_map[sid].get("pos_rot_km", [])) if last_map.has(sid) else Vector3.ZERO
		_near((arr - lastp).length(), 0.0, 1.0, "末采样=arrival: " + sid)
	_data_line("independence", "旗舰=baseline；4 舰偏离 baseline+常量偏移（真实独立传播）")

func _datum(off_len: float, sid: String) -> void:
	_ok(off_len >= 0.0, "初始偏移 %s 有效" % sid)

# ═══════════════════════════════════════════════════════════════════
# 5. sample(t)
# ═══════════════════════════════════════════════════════════════════

func _test_samples() -> void:
	_section_begin("5 sample(t)")
	var ft = FleetTransfer.new()
	ft.plan()
	var s0: Dictionary = ft.sample(0.0)
	_eq(String(s0.get("phase", "")), "departure", "sample(0) departure")
	_near(float(s0.get("progress", -1.0)), 0.0, 1.0e-9, "sample(0) progress=0")
	_eq((s0.get("ships", []) as Array).size(), 5, "sample(0) 5 舰")
	var sm: Dictionary = ft.sample(ft.tof_s * 0.5)
	_eq(String(sm.get("phase", "")), "cruise", "sample(mid) cruise")
	_near(float(sm.get("progress", -1.0)), 0.5, 1.0e-9, "sample(mid) progress")
	var se: Dictionary = ft.sample(ft.tof_s)
	_eq(String(se.get("phase", "")), "arrival", "sample(tof) arrival")
	_near(float(se.get("progress", -1.0)), 1.0, 1.0e-9, "sample(tof) progress")
	var over: Dictionary = ft.sample(ft.tof_s + 1000.0)
	_eq(bool(over.get("clamped", false)), true, "sample 超时 clamp")
	_eq(String(over.get("phase", "")), "arrival", "clamp phase=arrival")
	var neg: Dictionary = ft.sample(-100.0)
	_eq(bool(neg.get("clamped", false)), true, "sample 负时间 clamp")
	_eq(String(neg.get("phase", "")), "departure", "clamp phase=departure")
	# 采样点精确性 + 每舰有限
	for raw in ft.samples:
		var srow: Dictionary = raw
		var t := float(srow.get("t_s", 0.0))
		var smp: Dictionary = ft.sample(t)
		_ok(bool(smp.get("ok", false)), "sample t=%d ok" % int(t))
		for sw in (smp.get("ships", []) as Array):
			var sr: Dictionary = sw
			_ok(_arr3_finite(sr.get("pos_rot_km", [])), "sample pos 有限 " + String(sr.get("ship_id", "")))
			_ok(_arr3_finite(sr.get("vel_rot_kmps", [])), "sample vel 有限")
			_ok(float(sr.get("rel_to_flagship_mag_km", -1.0)) >= 0.0,
				"sample rel>=0 " + String(sr.get("ship_id", "")))
	# sample 在采样点与缓存 samples 一致（pos 误差<1km；vel<0.01）
	var mid_idx := 5
	var stored: Dictionary = ft.samples[mid_idx]
	var smp2: Dictionary = ft.sample(float(stored.get("t_s", 0.0)))
	var stored_map := _row_map(stored.get("ships", []))
	var smp_map := _row_map(smp2.get("ships", []))
	for sid in SHIPS:
		_ok(stored_map.has(sid) and smp_map.has(sid), "sample 采样点含 " + sid)
		if stored_map.has(sid) and smp_map.has(sid):
			var pd := (_vec(stored_map[sid].get("pos_rot_km", [])) \
				- _vec(smp_map[sid].get("pos_rot_km", []))).length()
			_near(pd, 0.0, 1.0, "sample 采样点 pos 一致: " + sid)
	# 轨迹差异（各舰 pos 不同）
	var mid_ships: Array = sm.get("ships", [])
	var pos_set := {}
	for raw in mid_ships:
		var sr: Dictionary = raw
		pos_set[str(sr.get("pos_rot_km", []))] = true
	_eq(pos_set.size(), 5, "5 舰 mid 位置各不相同")
	_data_line("samples", "phases departure/cruise/arrival clamp · 5 舰位置可区分")

# ═══════════════════════════════════════════════════════════════════
# 6. summary / fleet / JSON / Δv
# ═══════════════════════════════════════════════════════════════════

func _test_summary_json() -> void:
	_section_begin("6 summary/JSON/Δv")
	var ft = FleetTransfer.new()
	ft.plan({"use_cache": true, "cache_path": CACHE_PATH})
	var sm: Dictionary = ft.summary()
	_ok(bool(sm.get("ok", false)), "summary ok")
	var arr: Dictionary = sm.get("arrival", {})
	_ok(arr.get("rows") is Array, "arrival.rows 数组")
	_eq((arr.get("rows", []) as Array).size(), 5, "arrival rows 5")
	_ok(bool(arr.get("all_within_gate", false)), "arrival all_within_gate")
	_ok(float(arr.get("max_error_km", 99999.0)) < 3000.0, "arrival max_error<3000")
	_ok(float(arr.get("max_speed_kmps", 999.0)) < 3.0, "arrival max_speed<3")
	var dv: Dictionary = sm.get("dv", {})
	_eq((dv.get("rows", []) as Array).size(), 5, "dv rows 5")
	var sum_dep := float(dv.get("sum_departure_mps", -1.0))
	var sum_arr := float(dv.get("sum_arrival_mps", -1.0))
	var sum_tot := float(dv.get("sum_total_mps", -1.0))
	_near(sum_tot, sum_dep + sum_arr, 1.0e-6, "dv sum total=dep+arr")
	var avg := float(dv.get("avg_total_mps", -1.0))
	_near(avg, sum_tot / 5.0, 1.0e-6, "dv avg=sum/5")
	_ok(float(dv.get("max_departure_mps", 0.0)) > 0.0, "dv max departure")
	_ok(float(dv.get("max_arrival_mps", 0.0)) > 0.0, "dv max arrival")
	for raw in (dv.get("rows", []) as Array):
		var r: Dictionary = raw
		_ok(float(r.get("total_dv_mps", 0.0)) > 0.0, "dv %s total>0" % String(r.get("ship_id", "")))
	var fleet_rows: Array = ft.fleet()
	_eq(fleet_rows.size(), 5, "fleet() 5")
	_ok(ft.samples_data().size() == 11, "samples_data 11")
	var js := ft.to_json()
	_ok(js.length() > 3000, "to_json 长度", "len=%d" % js.length())
	var parsed = JSON.parse_string(js)
	_ok(parsed is Dictionary, "to_json 回读")
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		_eq(String(pd.get("schema", "")), "v17_fleet_transfer.v1", "回读 schema")
		_eq((pd.get("ships", []) as Array).size(), 5, "回读 ships 5")
		_ok(pd.get("arrival") is Dictionary, "回读 arrival")
		_ok(pd.get("dv") is Dictionary, "回读 dv")
	var cache_json := JSON.stringify(ft.cache())
	_ok(cache_json.length() > 5000, "cache() JSON", "len=%d" % cache_json.length())
	# fleet 行与 sample 舰一致
	for sid in SHIPS:
		_ok(ft.row_for(sid).get("arrival_state_rot") is Dictionary, "row_for %s arrival" % sid)
	_data_line("summary", "max_error=%.1fkm max_speed=%.3fkm/s avg_dv=%.1fm/s" % [
		float(arr.get("max_error_km", 0.0)), float(arr.get("max_speed_kmps", 0.0)),
		float(dv.get("avg_total_mps", 0.0))])

# ═══════════════════════════════════════════════════════════════════
# 7. 边界
# ═══════════════════════════════════════════════════════════════════

func _test_boundaries() -> void:
	_section_begin("7 边界")
	var ft = FleetTransfer.new()
	var pre: Dictionary = ft.sample(0.0)
	_eq(bool(pre.get("ok", true)), false, "未 plan sample ok=false")
	_eq(ft.fleet().size(), 0, "未 plan fleet 空")
	_ok(not ft.load_cache("res://framework/content/no_such_cache.json"), "缓存不存在 load 失败")
	_eq(ft.errors.size(), 1, "load 失败记录 error")
	_ok(not ft.load_cache("res://framework/content/damage_l1.json"), "错误 schema load 失败")
	var bad = FleetTransfer.new()
	var bad_res: Dictionary = bad.plan({"tof_days": []})
	_eq(bool(bad_res.get("ok", true)), false, "无效 TOF plan 失败")
	_ok(not bad.ready, "失败 plan 不 ready")
	_eq(bad.fleet_rows.size(), 0, "失败不伪造舰行")
	_eq(bad.samples.size(), 0, "失败不伪造采样")
	ft.reset()
	_ok(not ft.ready, "reset 后未 ready")
	_eq(ft.summary().get("ok", true), false, "reset summary ok=false")
	_data_line("boundaries", "未 plan/缓存缺失/错误 schema/无效 TOF 均安全失败不伪造")
