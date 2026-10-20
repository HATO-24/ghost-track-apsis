extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 阶段2-FLEET-ORBIT-1：5 舰独立 CR3BP 传播（新文件；不接 UI/其他模块）
#
# - 基准：transfer_planner 的 L4-02 出发状态 + 6 天 TOF（单 TOF 规划，与默认结果一致）；
# - 5 舰各自有明确位置/速度小偏移（见 FLEET_OFFSETS），每舰从自己的 departure 状态
#   **独立**调用 cislunar_physics.propagate_state（CR3BP/RK4，步长≤60s）传播到同一 TOF；
#   不是“旗舰 timeline + 常量偏移”；
# - 输出：每舰 initial/departure/arrival 状态、到达误差/速度、gate、Δv 分配；
#   每舰独立 11 点轨迹采样（cache/sample(t)/fleet()/summary()/to_json()）；
# - 缓存 JSON：framework/content/transfer_l4_l1_fleet_cached.json（确定性）；
# - 失败不伪造；不写 world/V15；不接 HUD。
# ═══════════════════════════════════════════════════════════════════

const TransferPlanner := preload("res://framework/sim/transfer_planner.gd")
const Physics := preload("res://framework/sim/cislunar_physics.gd")

const SCHEMA := "v17_fleet_transfer.v1"
const CACHE_SCHEMA := "v17_fleet_transfer_cache.v1"
const CACHE_PATH := "res://framework/content/transfer_l4_l1_fleet_cached.json"
const FLEET := "transit_l4_l1"
const SOURCE_PORT := "L4-02 Hammer"
const TARGET_PORT := "L1-Meridian-05"
const TOF_DAYS := 6.0
const SAMPLE_COUNT := 11

# 每舰偏移（明确数值；km、km/s）。旗舰为基准（0）。
const FLEET_OFFSETS := [
	{"id": "apsis", "batch": "1000", "role": "flagship",
		"offset_km": [0.0, 0.0, 0.0], "offset_kmps": [0.0, 0.0, 0.0]},
	{"id": "harmattan", "batch": "1001", "role": "command",
		"offset_km": [12.0, -8.0, 2.0], "offset_kmps": [0.0004, -0.0003, 0.00005]},
	{"id": "ferry", "batch": "1002", "role": "escort",
		"offset_km": [-15.0, 10.0, -3.0], "offset_kmps": [-0.0005, 0.0004, 0.0]},
	{"id": "watchtower", "batch": "1003", "role": "relay",
		"offset_km": [8.0, 16.0, 4.0], "offset_kmps": [0.0003, 0.0006, -0.0001]},
	{"id": "deepwell", "batch": "1004", "role": "tanker",
		"offset_km": [-20.0, -12.0, -5.0], "offset_kmps": [-0.0007, -0.0005, 0.00015]},
]

var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var baseline_plan: Dictionary = {}
var tof_s := 0.0
var t_s := 0.0
var fleet_rows: Array = []
var samples: Array = []
var cache_data: Dictionary = {}
var cache_path_used := ""
var step_count := 0

# ── 工具 ─────────────────────────────────────────────────────────

func _vec3(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	return Physics.to_vec3(value, fallback)

func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _state_arrays(r: Vector3, v: Vector3) -> Dictionary:
	return {"r": _arr(r), "v": _arr(v)}

func _propagate(r: Vector3, v: Vector3, dt: float) -> Dictionary:
	var res: Dictionary = Physics.propagate_state(Physics.make_state(r, v), dt,
		{"step_s": 60.0})
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": String(res.get("reason", "propagate_failed"))}
	var s: Dictionary = Physics.as_state(res["state"])
	return {"ok": true, "r": s["r"], "v": s["v"], "res": res}

static func _finite_arr(a) -> bool:
	if not (a is Array) or (a as Array).size() < 3:
		return false
	var arr: Array = a
	for i in range(3):
		if not is_finite(float(arr[i])):
			return false
	return true

# ── 规划（基准 + 5 舰独立传播）──────────────────────────────────

## 生成 5 舰独立传播方案（默认使用 6 天单 TOF 的 transfer_planner 基准）。
func plan(opts := {}) -> Dictionary:
	errors.clear()
	warnings.clear()
	ready = false
	baseline_plan = {}
	fleet_rows = []
	samples = []
	cache_data = {}
	step_count = 0
	t_s = 0.0
	var o: Dictionary = opts if opts is Dictionary else {}
	var use_cache := bool(o.get("use_cache", false))
	var cache_path := String(o.get("cache_path", CACHE_PATH))
	if use_cache:
		if load_cache(cache_path):
			return _make_result(true)
		warnings.append("cache 加载失败，改为现算")
	var planner_opts: Dictionary = {}
	if o.has("tof_days"):
		planner_opts["tof_days"] = o.get("tof_days")
	else:
		planner_opts["tof_days"] = [TOF_DAYS]
	baseline_plan = TransferPlanner.plan(planner_opts)
	if not bool(baseline_plan.get("ok", false)):
		errors.append("transfer_planner 失败：" + String(baseline_plan.get("reason", "")))
		return _make_result(false)
	var transfer: Dictionary = baseline_plan.get("transfer", {})
	tof_s = float(transfer.get("tof_s", 0.0))
	if tof_s <= 0.0:
		errors.append("TOF 无效")
		return _make_result(false)
	var source_pos := _vec3((baseline_plan.get("source", {}) as Dictionary).get("pos_rot_km", []))
	var target_pos := _vec3((baseline_plan.get("target", {}) as Dictionary).get("pos_rot_km", []))
	var depart_arrays: Dictionary = transfer.get("depart_state_rot", {})
	var base_dep_r := _vec3(depart_arrays.get("r", []))
	var base_dep_v := _vec3(depart_arrays.get("v", []))
	var gate_radius := float((baseline_plan.get("arrival", {}) as Dictionary)
		.get("gate_radius_km", 3000.0))
	var gate_speed := float((baseline_plan.get("arrival", {}) as Dictionary)
		.get("gate_speed_kmps", 3.0))
	# 每舰独立传播
	for raw in FLEET_OFFSETS:
		var ship: Dictionary = raw
		var sid := String(ship.get("id", ""))
		var off := Vec3Helper.from_arr(ship.get("offset_km", []))
		var off_v := Vec3Helper.from_arr(ship.get("offset_kmps", []))
		var init_r := source_pos + off
		var dep_r := base_dep_r + off
		var dep_v := base_dep_v + off_v
		var prop := _propagate(dep_r, dep_v, tof_s)
		if not bool(prop.get("ok", false)):
			errors.append("舰 %s 传播失败：%s" % [sid, String(prop.get("reason", ""))])
			continue
		var arr_r: Vector3 = prop["r"]
		var arr_v: Vector3 = prop["v"]
		var err_km := (arr_r - target_pos).length()
		var rel_speed := arr_v.length()   # 目标港 v_rot=0
		var dep_dv := (dep_v - Vec3Helper.from_arr([])).length()
		var arr_dv := arr_v.length()
		var dep_mps := dep_dv * 1000.0
		var arr_mps := arr_dv * 1000.0
		var within := err_km <= gate_radius and rel_speed <= gate_speed
		fleet_rows.append({
			"ship_id": sid,
			"batch": String(ship.get("batch", "")),
			"role": String(ship.get("role", "")),
			"offset_km": ship.get("offset_km", []),
			"offset_kmps": ship.get("offset_kmps", []),
			"initial_state_rot": _state_arrays(init_r, Vec3Helper.from_arr([])),
			"departure_state_rot": _state_arrays(dep_r, dep_v),
			"departure_dv_rot": _arr(dep_v),
			"departure_dv_mps": dep_mps,
			"arrival_state_rot": _state_arrays(arr_r, arr_v),
			"arrival_dv_rot": _arr(arr_v * -1.0),
			"arrival_dv_mps": arr_mps,
			"total_dv_mps": dep_mps + arr_mps,
			"arrival_error_km": err_km,
			"arrival_speed_kmps": rel_speed,
			"gate_radius_km": gate_radius,
			"gate_speed_kmps": gate_speed,
			"within_gate": within,
			"independent_propagation": true,
			"propagated_steps": int((prop.get("res", {}) as Dictionary).get("steps", 0)),
		})
	if fleet_rows.size() != FLEET_OFFSETS.size():
		errors.append("舰队传播未全部完成：%d/%d" % [fleet_rows.size(), FLEET_OFFSETS.size()])
		return _make_result(false)
	# 每舰独立 11 点采样（分段 CR3BP 传播，不是基准 timeline+偏移）
	var flagships := _fleet_map()
	for i in range(SAMPLE_COUNT):
		var frac := float(i) / float(SAMPLE_COUNT - 1)
		var row_t := tof_s * frac
		var ship_samples: Array = []
		for f in fleet_rows:
			var fr: Dictionary = f
			var sid := String(fr.get("ship_id", ""))
			var dep_state: Dictionary = fr.get("departure_state_rot", {})
			var prop_seg := _propagate(_vec3(dep_state.get("r", [])),
				_vec3(dep_state.get("v", [])), row_t)
			if not bool(prop_seg.get("ok", false)):
				errors.append("舰 %s 采样失败：%s" % [sid, String(prop_seg.get("reason", ""))])
				return _make_result(false)
			var p: Vector3 = prop_seg["r"]
			var vv: Vector3 = prop_seg["v"]
			var flag_row: Dictionary = flagships.get("apsis", {})
			var flag_pos := _vec3((flag_row.get("arrival_state_rot", {}) as Dictionary)
				.get("r", [])) if frac >= 1.0 else _vec3([])
			ship_samples.append({
				"ship_id": sid,
				"batch": String(fr.get("batch", "")),
				"role": String(fr.get("role", "")),
				"pos_rot_km": _arr(p),
				"vel_rot_kmps": _arr(vv),
				"distance_to_target_km": (p - target_pos).length(),
				"earth_distance_km": (p - Physics.earth_position_rot()).length(),
				"finite": bool(prop_seg.get("res", {}).get("finite", true)),
			})
		samples.append({"t_s": row_t, "t_days": row_t / 86400.0,
			"progress": frac, "ships": ship_samples})
	# 相对旗舰偏移（按采样点）
	for i in range(samples.size()):
		var srow: Dictionary = samples[i]
		var srows: Array = srow.get("ships", [])
		var flagp := Vector3.ZERO
		for raw2 in srows:
			if String((raw2 as Dictionary).get("ship_id", "")) == "apsis":
				flagp = _vec3((raw2 as Dictionary).get("pos_rot_km", []))
		for raw3 in srows:
			var sr: Dictionary = raw3
			var p3 := _vec3(sr.get("pos_rot_km", []))
			sr["rel_to_flagship_km"] = _arr(p3 - flagp)
			sr["rel_to_flagship_mag_km"] = (p3 - flagp).length()
	cache_data = _build_cache()
	ready = true
	return _make_result(true)

func _fleet_map() -> Dictionary:
	var out := {}
	for raw in fleet_rows:
		out[String((raw as Dictionary).get("ship_id", ""))] = raw
	return out

func _make_result(ok: bool) -> Dictionary:
	return {
		"ok": ok,
		"schema": SCHEMA,
		"ready": ready,
		"fleet": FLEET,
		"source_port": SOURCE_PORT,
		"target_port": TARGET_PORT,
		"tof_s": tof_s,
		"tof_days": tof_s / 86400.0,
		"t_s": t_s,
		"fleet_rows": fleet_rows.duplicate(true),
		"arrival": _arrival_summary(),
		"dv": _dv_summary(),
		"cache": {
			"schema": CACHE_SCHEMA,
			"path": cache_path_used,
			"has_cache": not cache_data.is_empty(),
			"deterministic": true,
		},
		"sample_count": samples.size(),
		"samples": samples.duplicate(true),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"note": "5 舰各自独立 CR3BP/RK4 传播（非 timeline+偏移）；模型值，不写 world/V15。",
	}

func _arrival_summary() -> Dictionary:
	var rows: Array = []
	var all_within := true
	var max_err := 0.0
	var max_speed := 0.0
	for raw in fleet_rows:
		var fr: Dictionary = raw
		var err := float(fr.get("arrival_error_km", 0.0))
		var spd := float(fr.get("arrival_speed_kmps", 0.0))
		max_err = maxf(max_err, err)
		max_speed = maxf(max_speed, spd)
		if not bool(fr.get("within_gate", false)):
			all_within = false
		rows.append({
			"ship_id": String(fr.get("ship_id", "")),
			"batch": String(fr.get("batch", "")),
			"arrival_error_km": err,
			"arrival_speed_kmps": spd,
			"within_gate": bool(fr.get("within_gate", false)),
		})
	return {
		"rows": rows,
		"max_error_km": max_err,
		"max_speed_kmps": max_speed,
		"all_within_gate": all_within,
		"gate_radius_km": float((fleet_rows[0] as Dictionary).get("gate_radius_km", 3000.0)) if not fleet_rows.is_empty() else 3000.0,
		"gate_speed_kmps": float((fleet_rows[0] as Dictionary).get("gate_speed_kmps", 3.0)) if not fleet_rows.is_empty() else 3.0,
	}

func _dv_summary() -> Dictionary:
	var rows: Array = []
	var sum_dep := 0.0
	var sum_arr := 0.0
	var max_dep := 0.0
	var max_arr := 0.0
	for raw in fleet_rows:
		var fr: Dictionary = raw
		var dep := float(fr.get("departure_dv_mps", 0.0))
		var arr := float(fr.get("arrival_dv_mps", 0.0))
		sum_dep += dep
		sum_arr += arr
		max_dep = maxf(max_dep, dep)
		max_arr = maxf(max_arr, arr)
		rows.append({
			"ship_id": String(fr.get("ship_id", "")),
			"batch": String(fr.get("batch", "")),
			"departure_dv_mps": dep,
			"arrival_dv_mps": arr,
			"total_dv_mps": float(fr.get("total_dv_mps", 0.0)),
		})
	var n := maxi(1, fleet_rows.size())
	return {
		"rows": rows,
		"sum_departure_mps": sum_dep,
		"sum_arrival_mps": sum_arr,
		"sum_total_mps": sum_dep + sum_arr,
		"avg_total_mps": (sum_dep + sum_arr) / float(n),
		"max_departure_mps": max_dep,
		"max_arrival_mps": max_arr,
	}

# ── sample / fleet / summary ────────────────────────────────────

## 按时间 t（秒，clamp 到 [0,tof]）返回每舰插值状态与相对旗舰偏移；
## 插值源为各舰独立传播的 11 点采样，不是基准 timeline+常量偏移。
func sample(t: float) -> Dictionary:
	if not ready or samples.is_empty():
		return {"ok": false, "reason": "not_ready", "t_s": 0.0, "ships": []}
	var requested := float(t)
	var clamped_t := clampf(requested, 0.0, tof_s)
	var clamped := absf(clamped_t - requested) > 1.0e-9
	var phase := "departure"
	if clamped_t >= tof_s - 1.0e-9:
		phase = "arrival"
	elif clamped_t > 1.0e-9:
		phase = "cruise"
	var idx := 0
	for i in range(samples.size()):
		if float((samples[i] as Dictionary).get("t_s", 0.0)) <= clamped_t + 1.0e-9:
			idx = i
	var a: Dictionary = samples[idx]
	var b: Dictionary = samples[mini(idx + 1, samples.size() - 1)]
	var ta := float(a.get("t_s", 0.0))
	var tb := float(b.get("t_s", ta))
	var frac := 0.0
	if tb > ta + 1.0e-9:
		frac = clampf((clamped_t - ta) / (tb - ta), 0.0, 1.0)
	var out_ships: Array = []
	var a_ships: Array = a.get("ships", [])
	var b_ships: Array = b.get("ships", [])
	for i in range(a_ships.size()):
		var sa: Dictionary = a_ships[i]
		var sb: Dictionary = b_ships[mini(i, b_ships.size() - 1)]
		var p := _lerp3(sa.get("pos_rot_km", []), sb.get("pos_rot_km", []), frac)
		var v := _lerp3(sa.get("vel_rot_kmps", []), sb.get("vel_rot_kmps", []), frac)
		var row := {
			"ship_id": String(sa.get("ship_id", "")),
			"batch": String(sa.get("batch", "")),
			"role": String(sa.get("role", "")),
			"pos_rot_km": p,
			"vel_rot_kmps": v,
			"earth_distance_km": (Physics.to_vec3(p, Vector3.ZERO)
				- Physics.earth_position_rot()).length(),
			"distance_to_target_km": (Physics.to_vec3(p, Vector3.ZERO)
				- _target_pos()).length(),
		}
		out_ships.append(row)
	var flagp := Vector3.ZERO
	for raw2 in out_ships:
		if String((raw2 as Dictionary).get("ship_id", "")) == "apsis":
			flagp = Physics.to_vec3((raw2 as Dictionary).get("pos_rot_km", []))
	for raw3 in out_ships:
		var r3: Dictionary = raw3
		var p3 := Physics.to_vec3(r3.get("pos_rot_km", []))
		r3["rel_to_flagship_km"] = _arr(p3 - flagp)
		r3["rel_to_flagship_mag_km"] = (p3 - flagp).length()
	t_s = clamped_t
	return {
		"ok": true,
		"schema": SCHEMA,
		"fleet": FLEET,
		"requested_t_s": requested,
		"t_s": clamped_t,
		"t_days": clamped_t / 86400.0,
		"clamped": clamped,
		"phase": phase,
		"progress": clamped_t / tof_s if tof_s > 0.0 else 0.0,
		"ships": out_ships,
		"sample_index": idx,
		"note": "每舰独立传播采样插值；不是旗舰 timeline+常量偏移。",
	}

func _target_pos() -> Vector3:
	return _vec3((baseline_plan.get("target", {}) as Dictionary).get("pos_rot_km", []))

func _lerp3(a: Variant, b: Variant, f: float) -> Array:
	var out := [0.0, 0.0, 0.0]
	if not (a is Array) or not (b is Array):
		return out
	var aa: Array = a
	var bb: Array = b
	for i in range(3):
		out[i] = lerpf(float(aa[i]), float(bb[i]), f)
	return out

func fleet() -> Array:
	return fleet_rows.duplicate(true)

func samples_data() -> Array:
	return samples.duplicate(true)

func summary() -> Dictionary:
	if not ready:
		return {"ok": false, "schema": SCHEMA, "reason": "not_ready",
			"errors": errors.duplicate()}
	return {
		"ok": true,
		"schema": SCHEMA,
		"fleet": FLEET,
		"source_port": SOURCE_PORT,
		"target_port": TARGET_PORT,
		"tof_s": tof_s,
		"tof_days": tof_s / 86400.0,
		"t_s": t_s,
		"ship_count": fleet_rows.size(),
		"sample_count": samples.size(),
		"arrival": _arrival_summary(),
		"dv": _dv_summary(),
		"ships": fleet_rows.duplicate(true),
		"deterministic": true,
		"cache": cache_data.duplicate(true),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"note": "5 舰独立 CR3BP/RK4 传播；仅模型数据；不接 UI。",
	}

func to_json() -> String:
	return JSON.stringify(summary())

# ── 缓存 ────────────────────────────────────────────────────────

func _build_cache() -> Dictionary:
	return {
		"schema": CACHE_SCHEMA,
		"generated_by": "fleet_transfer.gd",
		"fleet": FLEET,
		"source_port": SOURCE_PORT,
		"target_port": TARGET_PORT,
		"tof_s": tof_s,
		"tof_days": tof_s / 86400.0,
		"baseline": {
			"planner": "transfer_planner.gd",
			"method": String((baseline_plan.get("transfer", {}) as Dictionary).get("method", "")),
			"total_dv_mps": float((baseline_plan.get("transfer", {}) as Dictionary).get("total_dv_mps", 0.0)),
			"arrival_error_km": float((baseline_plan.get("arrival", {}) as Dictionary).get("radius_km", 0.0)),
		},
		"ships": fleet_rows.duplicate(true),
		"samples": samples.duplicate(true),
		"arrival": _arrival_summary(),
		"dv": _dv_summary(),
		"deterministic": true,
	}

func cache() -> Dictionary:
	return cache_data.duplicate(true)

func save_cache(path := CACHE_PATH) -> bool:
	if cache_data.is_empty():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		warnings.append("无法写缓存：" + path)
		return false
	f.store_string(JSON.stringify(cache_data, "  "))
	f.close()
	cache_path_used = path
	return true

## 从缓存恢复（校验 schema/5 舰/采样）；失败不伪造，返回 false。
func load_cache(path := CACHE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		errors.append("缓存不存在：" + path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		errors.append("缓存 JSON 无效：" + path)
		return false
	var data: Dictionary = parsed
	if String(data.get("schema", "")) != CACHE_SCHEMA:
		errors.append("缓存 schema 无效")
		return false
	if (data.get("ships", []) as Array).size() != FLEET_OFFSETS.size():
		errors.append("缓存舰数不是 5")
		return false
	tof_s = float(data.get("tof_s", 0.0))
	if tof_s <= 0.0:
		errors.append("缓存 TOF 无效")
		return false
	fleet_rows = (data.get("ships", []) as Array).duplicate(true)
	samples = (data.get("samples", []) as Array).duplicate(true)
	cache_data = data.duplicate(true)
	cache_path_used = path
	# 最小校验：每舰含 arrival/departure/error
	for raw in fleet_rows:
		var fr: Dictionary = raw
		if not fr.has("arrival_error_km") or not fr.has("departure_state_rot"):
			errors.append("缓存舰记录不完整")
			return false
	for raw_s in samples:
		var sr: Dictionary = raw_s
		if not (sr.get("ships", []) is Array) or (sr.get("ships", []) as Array).size() != 5:
			errors.append("缓存采样不完整")
			return false
	ready = true
	return true

func has_ship(ship_id: String) -> bool:
	for raw in fleet_rows:
		if String((raw as Dictionary).get("ship_id", "")) == ship_id:
			return true
	return false

func row_for(ship_id: String) -> Dictionary:
	for raw in fleet_rows:
		var fr: Dictionary = raw
		if String(fr.get("ship_id", "")) == ship_id:
			return fr.duplicate(true)
	return {}

func reset() -> void:
	ready = false
	baseline_plan = {}
	fleet_rows = []
	samples = []
	cache_data = {}
	tof_s = 0.0
	t_s = 0.0
	step_count = 0
	errors.clear()
	warnings.clear()
	cache_path_used = ""


# ── 小工具（避免 GDScript 内联 Vector3 数组转换歧义）────────────
class Vec3Helper:
	static func from_arr(a: Variant, fallback := Vector3.ZERO) -> Vector3:
		if a is Array and (a as Array).size() >= 3:
			var arr: Array = a
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		return fallback
