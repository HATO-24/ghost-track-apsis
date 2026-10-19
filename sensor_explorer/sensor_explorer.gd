extends Node3D

## SENSOR EXPLORER · 雷达 / 光电 / IFF / ELINT 独立技术演示（SENSOR-EXPLORER-1）
##
## 数据与状态机全部来自 V2 传感器模型（sim/ 只读）：
##   * sim/sensor_types.gd  → 型号能力记录（YW-R9 / MS-OT2 / CH-IR2 / MK-12 / ELINT）
##   * sim/radar.gd         → 球形搜索 R_eff / RCS / 刷新 / 暴露（ELINT 截获/定位）
##   * sim/tws.gd           → TWS 六态通道（SEARCH→…→FIRE_CONTROL）、quality/age/失锁/重捕
##   * sim/optical.gd       → VIS/IR 凝视通道（光照/遮挡/凝视进度/锁定）
##   * scripts/sensor_model.gd（V2 规则层）→ IFF 询问、ELINT 截获、发射特征
##
## 视觉：V1 薄荷绿线框 / 1px 线 / 7–11pt 终端字体 / Palette；ImmediateMesh 线段，无贴图。
## 诚实标注（HUD 固定）：`V2 SIM MODEL — NOT YET AUTHORITATIVE IN V17`。
## 本演示是「传感器技术演示」：本舰固定在 L1 局部板坐标系原点，6 个目标按脚本轨迹运动；
## 雷达球是**真实球形**（不是扇形）；光学视锥来自 V2 optical 通道的方位/俯仰。
##
## 控制：
##   LMB 拖拽旋转 · RMB/MMB 拖拽平移 · 滚轮缩放
##   TAB 循环目标 · 1–6 选择目标 · 0/F 相机焦点：本舰/选中目标 · R 重置
##   SPACE 暂停/播放 · -/= 时间倍率 1×/10×/100×/1000×
##   M 雷达开/EMCON · V VIS 通道开关 · I IR 通道开关 · E ELINT 接收机开关
##   Q IFF 询问选中目标（2 s 冷却）
## 截图：
##   DSH_SX_SHOT=<png> · DSH_SX_VIEW=overview|tws|optical|elint
##   可选 DSH_SX_TIME=<s>、DSH_SX_SPEED=<1|10|100|1000>、DSH_SX_PAUSE=1
##   按视图自动预热到可观察状态（overview/tws=80 s，optical=120 s，elint=55 s），
##   1920×1080 第 36 帧保存退出。

const Types := preload("res://sim/sensor_types.gd")
const RadarModel := preload("res://sim/radar.gd")
const TwsModel := preload("res://sim/tws.gd")
const OpticalModel := preload("res://sim/optical.gd")
const SM := preload("res://scripts/sensor_model.gd")
const Pal := preload("res://scripts/pal.gd")
const UiFonts := preload("res://scripts/fonts.gd")

const KM_PER_UNIT := 1000.0
const SPEEDS := [1.0, 10.0, 100.0, 1000.0]
const FRAME_CAPTURE := 36
const SIM_CHUNK := 0.25
const OWN_ID := "SX-01"

const STATE_ORDER := ["SEARCH", "DETECT", "ACQUIRE", "TRACK", "STARE", "FIRE_CONTROL"]
const STATE_SHORT := {"SEARCH": "SRCH", "DETECT": "DET", "ACQUIRE": "ACQ",
	"TRACK": "TRK", "STARE": "STARE", "FIRE_CONTROL": "FC"}
const VIEW_WARM := {"overview": 80.0, "tws": 200.0, "optical": 120.0, "elint": 55.0}

var camera: Camera3D
var mesh_instance: MeshInstance3D
var hud: Control
var _line_material: StandardMaterial3D

# ── V2 模型（只读调用）──────────────────────────────────────────
var _radar_rec = null
var _vis_rec = null
var _ir_rec = null
var _iff_rec = null
var _elint_rec = null
var _tws = null
var _optical = null

# ── 仿真 / 场景状态 ─────────────────────────────────────────────
var _t := 0.0
var _speed_idx := 1
var _paused := false
var _radar_on := true
var _elint_on := true
var _vis_on := true
var _ir_on := true
var _target_defs: Array = []
var _targets: Array = []
var _selected_id := "T1"
var _camera_focus := "own"
var _last_iff := {}
var _iff_cooldown := 0.0
var _auto_iff_done: Array = []
var _last_elint_emit_t: Dictionary = {}
var _last_own_emit_t := -999.0
var _events: Array = []
var _exposure: Dictionary = {}
var _tws_out: Dictionary = {}
var _optical_out: Dictionary = {}
var _elint_signals: Array = []
var _sim_acc := 0.0

# ── 相机 ────────────────────────────────────────────────────────
var _cam_yaw := deg_to_rad(-35.0)
var _cam_pitch := deg_to_rad(30.0)
var _cam_dist := 85.0
var _cam_target := Vector3.ZERO
var _pan_offset := Vector3.ZERO
var _drag_left := false
var _drag_pan := false
var _drag_moved := 0.0

# ── 截图 ────────────────────────────────────────────────────────
var _shot_path := ""
var _shot_view := ""
var _frames := 0
var _vm: Dictionary = {}


func _ready() -> void:
	_build_material()
	camera = get_node_or_null("Camera") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera"
		add_child(camera)
	camera.fov = 56.0
	camera.near = 0.02
	camera.far = 20000.0
	camera.current = true
	mesh_instance = get_node_or_null("Mesh") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		add_child(mesh_instance)
	hud = get_node_or_null("HUDLayer/HUD") as Control
	_setup_models()
	_setup_targets()
	_shot_path = OS.get_environment("DSH_SX_SHOT")
	_shot_view = OS.get_environment("DSH_SX_VIEW")
	var ss := OS.get_environment("DSH_SX_SPEED")
	if ss != "":
		var sv := float(ss)
		for i in range(SPEEDS.size()):
			if absf(float(SPEEDS[i]) - sv) < 0.5:
				_speed_idx = i
	if OS.get_environment("DSH_SX_PAUSE") == "1":
		_paused = true
	_apply_view(_shot_view if _shot_view != "" else "overview")
	var tt := OS.get_environment("DSH_SX_TIME")
	var warm := 0.0
	if tt != "":
		warm = maxf(0.0, float(tt))
	elif _shot_path != "":
		warm = float(VIEW_WARM.get(_shot_view, 80.0))
	if warm > 0.0:
		_warm_to(warm)
		_paused = true
	_step_sim(0.0)
	_update_camera(1.0)
	_rebuild_mesh()
	_update_vm()
	if hud != null:
		hud.set_vm(_vm)
		hud.queue_redraw()
	if _shot_path != "":
		get_window().borderless = true
		get_window().size = Vector2i(1920, 1080)
		get_window().position = Vector2i(0, 0)
		print("[SX] SHOT mode view=%s t=%.1f path=%s" % [_shot_view, _t, _shot_path])
	else:
		print("[SX] boot t=%.1f radar=%s targets=%d tws_ch=%d" % [
			_t, str(_radar_on), _targets.size(), int(_tws_out.get("channel_count", 0))])


# ═══════════════════════════════════════════════════════════════════
# 1. V2 模型 / 目标场景
# ═══════════════════════════════════════════════════════════════════

func _setup_models() -> void:
	_radar_rec = Types.record("YW-R9")
	_vis_rec = Types.record("MS-OT2")
	_ir_rec = Types.record("CH-IR2")
	_iff_rec = Types.record("MK-12")
	_elint_rec = Types.record("ELINT")
	var cap := 6
	if _radar_rec != null:
		cap = maxi(1, int(_radar_rec.track_capacity))
	_tws = TwsModel.new(_radar_rec, {"id": "YW-R9", "max_channels": cap, "enabled": true})
	_optical = OpticalModel.new({})
	_optical.set_sensor("optical", _vis_rec)
	_optical.set_sensor("ir", _ir_rec)
	_optical.start("optical", "T1")
	_optical.start("ir", "T1")
	_optical.start("optical", "T3")
	_optical.start("ir", "T6")


func _setup_targets() -> void:
	# 脚本轨迹（技术演示；非 V17 关卡数据）：
	# T4 距离振荡 → 进出 R_eff 球，可观察 TWS 失锁/重捕；T3 在 t∈[90,200) 进入阴影 → VIS 丢失/IR 仍在。
	_target_defs = [
		{"id": "T1", "name": "远地点", "range": 12000.0, "bearing": 40.0, "range_rate": 0.02,
			"bearing_rate": 0.03, "rcs": 12.0, "emitter": false, "transponder": "ok",
			"iff_code": "CMP-119", "faction": "friend", "cls": "DDG", "temp_k": 300.0},
		{"id": "T2", "name": "渡口", "range": 1900.0, "bearing": 120.0, "range_rate": -0.01,
			"bearing_rate": -0.02, "rcs": 8.0, "emitter": true, "transponder": "off",
			"iff_code": "", "faction": "neutral", "cls": "FFG", "temp_k": 295.0},
		{"id": "T3", "name": "望楼", "range": 24000.0, "bearing": 205.0, "range_rate": 0.0,
			"bearing_rate": 0.015, "rcs": 6.0, "emitter": false, "transponder": "ok",
			"iff_code": "CMP-211", "faction": "friend", "cls": "CV", "temp_k": 300.0},
		{"id": "T4", "name": "深井", "range": 28500.0, "bearing": 300.0, "range_rate": 0.0,
			"bearing_rate": -0.01, "rcs": 6.0, "emitter": false, "transponder": "faulty",
			"iff_code": "CMP-034", "faction": "unknown", "cls": "DDG", "temp_k": 305.0},
		{"id": "T5", "name": "传令者", "range": 28000.0, "bearing": 75.0, "range_rate": 0.0,
			"bearing_rate": 0.0, "rcs": 10.0, "emitter": true, "transponder": "captured",
			"iff_code": "REB-7", "faction": "hostile", "cls": "C2", "temp_k": 310.0},
		{"id": "T6", "name": "谷神-2", "range": 1500.0, "bearing": 155.0, "range_rate": 0.015,
			"bearing_rate": 0.02, "rcs": 10.0, "emitter": false, "transponder": "ok",
			"iff_code": "CMP-207", "faction": "friend", "cls": "DDG", "temp_k": 300.0},
	]


func _jamming_at(t: float) -> float:
	return 0.7 if t >= 150.0 and t < 190.0 else 0.0


func _illum_at(def: Dictionary, t: float) -> float:
	if String(def.get("id", "")) == "T3" and t >= 90.0 and t < 200.0:
		return 0.02
	return 1.0


func _refresh_targets() -> void:
	_targets = []
	for raw in _target_defs:
		var d: Dictionary = raw
		var rng := float(d.get("range", 0.0)) + float(d.get("range_rate", 0.0)) * _t
		if String(d.get("id", "")) == "T4":
			rng += 3200.0 * sin(TAU * _t / 120.0)
		var brg := deg_to_rad(float(d.get("bearing", 0.0)) + float(d.get("bearing_rate", 0.0)) * _t)
		var pos := Vector3(sin(brg) * rng, cos(brg) * rng, 0.0)
		var range_km := pos.length()
		var bearing := fposmod(rad_to_deg(atan2(pos.x, pos.y)), 360.0)
		var emissions: Array = []
		if bool(d.get("emitter", false)):
			emissions.append({"model": "YW-R9", "type": "radar", "on": true, "range_km": 30000.0})
		_targets.append({
			"id": String(d.get("id", "")),
			"name": String(d.get("name", "")),
			"pos_km": pos,
			"range_km": range_km,
			"bearing_deg": bearing,
			"elevation_deg": 0.0,
			"rcs_m2": float(d.get("rcs", 10.0)),
			"temp_k": float(d.get("temp_k", 300.0)),
			"area_m2": 1000.0,
			"illum": _illum_at(d, _t),
			"transponder": String(d.get("transponder", "off")),
			"iff_code": String(d.get("iff_code", "")),
			"faction": String(d.get("faction", "unknown")),
			"classification": {"ship_class": String(d.get("cls", "")),
				"role": "", "faction": String(d.get("faction", "unknown"))},
			"emissions": emissions,
		})


func _build_snapshot() -> Dictionary:
	_refresh_targets()
	return {
		"t": _t,
		"observer": {"id": OWN_ID, "pos_km": Vector3.ZERO, "maneuver_g": 0.0},
		"targets": _targets.duplicate(true),
		"sun_illum": 1.0,
		"jamming": _jamming_at(_t),
		"los": true,
		"shadow": false,
	}


func _sensor_dict(rec) -> Dictionary:
	if rec == null:
		return {}
	return rec.as_v15_sensor()


# ═══════════════════════════════════════════════════════════════════
# 2. 仿真推进（真实 step；事件/暴露/IFF/ELINT 时间线）
# ═══════════════════════════════════════════════════════════════════

func _warm_to(target_t: float) -> void:
	var guard := 0
	while _t < target_t - 1.0e-6 and guard < 8000:
		guard += 1
		_step_sim(minf(SIM_CHUNK, target_t - _t))


func _step_sim(dt: float) -> void:
	if dt > 0.0:
		_t += dt
	_refresh_targets()
	var snap := _build_snapshot()
	_iff_cooldown = maxf(0.0, _iff_cooldown - dt)
	if _tws != null:
		_tws.set_enabled(_radar_on)
		var tws_out: Dictionary = _tws.step(dt, snap)
		_tws_out = tws_out
		_ingest_tws_events(tws_out.get("events", []))
		var radar_info: Dictionary = tws_out.get("radar", {}) if tws_out.get("radar") is Dictionary else {}
		_exposure = RadarModel.exposure_state(_radar_rec,
			float(radar_info.get("seconds_on", 0.0)), {"on": _radar_on})
		if _elint_on:
			_own_elint_exposure()
	if _optical != null:
		var opt_out: Dictionary = _optical.step(dt, snap)
		_optical_out = opt_out
		_ingest_optical_events(opt_out.get("events", []))
	if _elint_on:
		_elint_sweep(dt)
	_scripted_iff()
	_update_signals()


func _ingest_tws_events(events: Array) -> void:
	for raw in events:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var kind := String(ev.get("kind", ""))
		var tid := String(ev.get("target_id", ""))
		var tname := _target_name(tid)
		match kind:
			"state_change":
				_push_event("tws", "TWS %s %s: %s → %s" % [tid, tname,
					_state_short(String(ev.get("from", ""))), _state_short(String(ev.get("to", "")))])
			"target_detected":
				_push_event("tws", "雷达发现 %s %s · R %.0f km" % [tid, tname,
					float(ev.get("range_km", 0.0))])
			"target_dropped":
				_push_event("tws_lost", "TWS %s %s 释放通道（%s）" % [tid, tname,
					String(ev.get("reason", ""))])
			"lock_lost":
				_push_event("tws_lost", "TWS %s %s 失锁（质量 %.0f%%）" % [tid, tname,
					float(ev.get("quality", 0.0)) * 100.0])
			"fire_control_ready":
				_push_event("tws_fc", "火控解算就绪 %s %s · q%.0f%%" % [tid, tname,
					float(ev.get("quality", 0.0)) * 100.0])
			"fire_control_lost":
				_push_event("tws_lost", "火控解算丢失 %s %s" % [tid, tname])
			"channel_full":
				_push_event("tws", "TWS 通道已满：%s 未分配" % tid)


func _ingest_optical_events(events: Array) -> void:
	for raw in events:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var kind := String(ev.get("kind", ""))
		var ch := String(ev.get("channel", ""))
		var tid := String(ev.get("target_id", ""))
		var message := String(ev.get("message", ""))
		var label := "VIS" if ch == "optical" else "IR"
		if kind.find("lost") >= 0:
			_push_event("optical_lost", "%s %s %s 丢失（%s）" % [label, tid,
				_target_name(tid), message])
		elif message != "":
			_push_event("optical", "%s %s %s · %s" % [label, tid, _target_name(tid), message])


func _own_elint_exposure() -> void:
	if not _radar_on or _radar_rec == null or not bool(_exposure.get("exposed", false)):
		return
	if _t - _last_own_emit_t < 12.0:
		return
	_push_event("elint", "本舰 YW-R9 发射 → 对方 ELINT 可截获 ≤ %.0f km · %.0f s 后定位" % [
		float(_exposure.get("elint_intercept_range_km", 0.0)),
		float(_exposure.get("fix_after_s", 0.0))])
	_last_own_emit_t = _t


func _elint_sweep(dt: float) -> void:
	if _elint_rec == null:
		return
	if fmod(_t, 2.0) > dt + 1.0e-6:
		return
	var elint_sensor := _sensor_dict(_elint_rec)
	for raw in _targets:
		var tr: Dictionary = raw
		var tid := String(tr.get("id", ""))
		if (tr.get("emissions", []) as Array).is_empty():
			continue
		if not bool(tr.get("emitter_on", true)):
			continue
		var det: Dictionary = SM.detect_elint(elint_sensor, tr, {"los": true})
		if not bool(det.get("detected", false)):
			continue
		var last := float(_last_elint_emit_t.get(tid, -999.0))
		if _t - last + 1.0e-9 < 10.0:
			continue
		_last_elint_emit_t[tid] = _t
		var sig: Dictionary = det.get("signal", {})
		_push_event("elint", "ELINT 截获 %s %s · %s · 方位 %.0f°（仅信号/无接触）" % [
			tid, _target_name(tid), String(sig.get("signature", "?")),
			float(det.get("bearing_deg", 0.0))])


func _scripted_iff() -> void:
	var schedule := [[8.0, "T6"], [20.0, "T2"], [34.0, "T5"], [46.0, "T6"]]
	for raw in schedule:
		var it: Array = raw
		var at := float(it[0])
		var tid := String(it[1])
		var key := "%s@%.0f" % [tid, at]
		if _t >= at and not _auto_iff_done.has(key):
			_auto_iff_done.append(key)
			_iff_query(tid)


func _iff_query(tid: String) -> void:
	if _iff_rec == null:
		return
	var tr := _target_by_id(tid)
	if tr.is_empty():
		return
	var res: Dictionary = SM.interrogate_iff(_sensor_dict(_iff_rec), tr, {"los": true})
	var status := String(res.get("iff_status", "no_reply"))
	_last_iff = {"target_id": tid, "status": status, "t": _t, "notes": res.get("notes", [])}
	var text := "IFF 询问 %s %s → %s" % [tid, _target_name(tid), status]
	if not bool(res.get("detected", false)):
		text = "IFF 询问 %s 失败：%s" % [tid, String(res.get("reason", "out_of_range"))]
	_push_event("iff", text)
	_iff_cooldown = 2.0


func _update_signals() -> void:
	_elint_signals = []
	if not _elint_on or _elint_rec == null:
		return
	for raw in _targets:
		var tr: Dictionary = raw
		if (tr.get("emissions", []) as Array).is_empty():
			continue
		var det: Dictionary = SM.detect_elint(_sensor_dict(_elint_rec), tr, {"los": true})
		if bool(det.get("detected", false)):
			var sig: Dictionary = det.get("signal", {})
			_elint_signals.append({
				"target_id": String(tr.get("id", "")),
				"signature": String(sig.get("signature", "")),
				"bearing_deg": float(tr.get("bearing_deg", 0.0)),
				"quality": float(det.get("quality", 0.0)),
			})


# ═══════════════════════════════════════════════════════════════════
# 3. 事件 / 查询工具
# ═══════════════════════════════════════════════════════════════════

func _push_event(kind: String, text: String) -> void:
	_events.append({"t": _t, "kind": kind, "text": text})
	while _events.size() > 80:
		_events.pop_front()


func _target_by_id(tid: String) -> Dictionary:
	for raw in _targets:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == tid:
			return raw
	return {}


func _target_name(tid: String) -> String:
	var tr := _target_by_id(tid)
	return String(tr.get("name", tid))


func _state_short(st: String) -> String:
	return String(STATE_SHORT.get(st, st))


func _channel_of(tid: String) -> Dictionary:
	if _tws == null:
		return {}
	var ch: Dictionary = _tws.channel(tid)
	return ch


func _optical_channel(kind: String, tid: String) -> Dictionary:
	if _optical == null:
		return {}
	var ch: Dictionary = _optical.channel(kind, tid)
	return ch


# ═══════════════════════════════════════════════════════════════════
# 4. 相机 / 视图
# ═══════════════════════════════════════════════════════════════════

func _apply_view(mode: String) -> void:
	match mode:
		"tws":
			_selected_id = "T4"
			_set_camera(95.0, -35.0, 34.0, "own")
		"optical":
			_selected_id = "T1"
			_set_camera(22.0, -20.0, 22.0, "selected")
		"elint":
			_selected_id = "T5"
			_set_camera(90.0, -40.0, 28.0, "own")
		_:
			_selected_id = "T1"
			_set_camera(85.0, -35.0, 30.0, "own")


func _set_camera(dist: float, yaw_deg: float, pitch_deg: float, focus: String) -> void:
	_cam_dist = dist
	_cam_yaw = deg_to_rad(yaw_deg)
	_cam_pitch = deg_to_rad(pitch_deg)
	_camera_focus = focus
	_pan_offset = Vector3.ZERO
	_cam_target = _camera_target_pos()


func _camera_target_pos() -> Vector3:
	if _camera_focus == "selected":
		var tr := _target_by_id(_selected_id)
		if not tr.is_empty():
			return _w(tr.get("pos_km", Vector3.ZERO))
	return Vector3.ZERO


func _update_camera(delta: float) -> void:
	var want := _camera_target_pos() + _pan_offset
	var k := clampf(delta * 7.0, 0.0, 1.0)
	if _cam_target.length() < 1.0e-6:
		_cam_target = want
	else:
		_cam_target = _cam_target.lerp(want, k)
	var cp := cos(_cam_pitch)
	var sp := sin(_cam_pitch)
	var dir := Vector3(cp * sin(_cam_yaw), sp, cp * cos(_cam_yaw))
	camera.position = _cam_target + dir * _cam_dist
	camera.look_at(_cam_target, Vector3.UP)


# ═══════════════════════════════════════════════════════════════════
# 5. 3D 线框绘制（ImmediateMesh 线段；无贴图）
# ═══════════════════════════════════════════════════════════════════

func _build_material() -> void:
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## 板坐标 km（x=东、y=北、z=天顶）→ 场景单位（X=东、Y=天顶、Z=北；1 unit=1000 km）
func _w(km: Vector3) -> Vector3:
	return Vector3(km.x, km.z, km.y) / KM_PER_UNIT


func _wdir(km_dir: Vector3) -> Vector3:
	return Vector3(km_dir.x, km_dir.z, km_dir.y).normalized()


func _bearing_dir(bearing_deg: float, elev_deg: float) -> Vector3:
	var b := deg_to_rad(bearing_deg)
	var e := deg_to_rad(elev_deg)
	var km_dir := Vector3(sin(b) * cos(e), cos(b) * cos(e), sin(e))
	return _wdir(km_dir)


func _rebuild_mesh() -> void:
	if mesh_instance == null:
		return
	var verts: Array = []
	var jamming := _jamming_at(_t)
	var eff_r := 0.0
	if _radar_rec != null:
		eff_r = RadarModel.effective_radius_km(_radar_rec, 10.0, jamming) / KM_PER_UNIT
	var track_r := 0.0
	if _radar_rec != null:
		track_r = RadarModel.effective_track_radius_km(_radar_rec, 10.0, jamming) / KM_PER_UNIT
	if _radar_on:
		_add_sphere(verts, eff_r, Pal.PH, 0.26)
		_add_circle_plane(verts, track_r, "horizontal", Pal.PH_DIM, 0.13)
	# 参考面：外环 + 方位辐条（L1 局部板参考面，非地球实体）
	_add_circle_plane(verts, maxf(eff_r * 1.15, 34.0), "horizontal", Pal.GRID, 0.35)
	for i in range(12):
		var ang := TAU * float(i) / 12.0
		var d := Vector3(sin(ang), 0.0, cos(ang))
		var r0 := maxf(eff_r * 1.15, 34.0)
		_add_line(verts, d * (r0 - 1.5), d * r0, Pal.GRID, 0.45)
	# 本舰
	_add_octahedron(verts, Vector3.ZERO, 0.65, Pal.PH, 0.9)
	_add_line(verts, Vector3.ZERO, Vector3(0.0, 0.0, 1.8), Pal.PH, 0.5)
	# 目标 + TWS 环/状态短线 + 视线/发射标记
	for raw in _targets:
		var tr: Dictionary = raw
		var p := _w(tr.get("pos_km", Vector3.ZERO))
		var ch := _channel_of(String(tr.get("id", "")))
		var st := String(ch.get("state", ""))
		var col: Color = _state_col(st)
		_add_line(verts, Vector3.ZERO, p, Pal.PH, 0.06)
		_add_octahedron(verts, p, 0.62, col, 0.9)
		if not ch.is_empty():
			_add_tws_ring(verts, p, st, float(ch.get("quality", 0.0)), col)
		if not (tr.get("emissions", []) as Array).is_empty():
			_add_emitter_marker(verts, p, Pal.AMBER)
	# 光学视锥（VIS/IR 独立读数；来自 V2 optical）
	_add_optical_cone(verts, "optical", Pal.PH)
	_add_optical_cone(verts, "ir", Pal.BLUE)
	# ELINT 被动截获方位线（仅方位，无距离/接触）
	for raw2 in _elint_signals:
		var sig: Dictionary = raw2
		var d := _bearing_dir(float(sig.get("bearing_deg", 0.0)), 0.0)
		_add_dashed(verts, d * 1.2, d * 46.0, Pal.AMBER, 0.16)
	# IFF 最近询问连线
	if not _last_iff.is_empty() and _t - float(_last_iff.get("t", -999.0)) < 6.0:
		var tgt := _target_by_id(String(_last_iff.get("target_id", "")))
		if not tgt.is_empty():
			var pc := Pal.PH if String(_last_iff.get("status", "")) == "friend" else Pal.AMBER
			_add_dashed(verts, Vector3.ZERO, _w(tgt.get("pos_km", Vector3.ZERO)), pc, 0.45)
	# 选中目标高亮
	var sel := _target_by_id(_selected_id)
	if not sel.is_empty():
		var sp := _w(sel.get("pos_km", Vector3.ZERO))
		_add_line(verts, sp + Vector3(0.9, 0, 0), sp + Vector3(1.5, 0.3, 0), Pal.AMBER, 0.9)
		_add_line(verts, sp - Vector3(0.9, 0, 0), sp - Vector3(1.5, 0.3, 0), Pal.AMBER, 0.9)
		_add_line(verts, sp + Vector3(0, 0.9, 0), sp + Vector3(0.3, 1.5, 0), Pal.AMBER, 0.9)
	var im := ImmediateMesh.new()
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
	for pair in verts:
		var vc: Array = pair
		im.surface_set_color(vc[1])
		im.surface_add_vertex(vc[0])
	im.surface_end()
	mesh_instance.mesh = im


func _add_line(arr: Array, a: Vector3, b: Vector3, col: Color, alpha: float) -> void:
	var c := col
	c.a = alpha
	arr.append([a, c])
	arr.append([b, c])


func _add_polyline(arr: Array, pts: Array, col: Color, alpha: float) -> void:
	for i in range(1, pts.size()):
		_add_line(arr, pts[i - 1], pts[i], col, alpha)


func _add_dashed(arr: Array, a: Vector3, b: Vector3, col: Color, alpha: float) -> void:
	var dist := a.distance_to(b)
	var n := maxi(1, int(dist / 1.5))
	for i in range(n):
		var t0 := float(i) / float(n)
		var t1 := t0 + 0.5 / float(n)
		_add_line(arr, a.lerp(b, clampf(t0, 0.0, 1.0)), a.lerp(b, clampf(t1, 0.0, 1.0)), col, alpha)


func _add_circle_plane(arr: Array, radius: float, plane: String, col: Color, alpha: float) -> void:
	if radius <= 0.0:
		return
	var prev := Vector3.ZERO
	for i in range(97):
		var ang := TAU * float(i) / 96.0
		var p := Vector3.ZERO
		match plane:
			"horizontal":
				p = Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
			"vertical_xy":
				p = Vector3(cos(ang) * radius, sin(ang) * radius, 0.0)
			_:
				p = Vector3(0.0, cos(ang) * radius, sin(ang) * radius)
		if i > 0:
			_add_line(arr, prev, p, col, alpha)
		prev = p


func _add_sphere(arr: Array, radius: float, col: Color, alpha: float) -> void:
	if radius <= 0.0:
		return
	_add_circle_plane(arr, radius, "horizontal", col, alpha)
	_add_circle_plane(arr, radius, "vertical_xy", col, alpha * 0.8)
	_add_circle_plane(arr, radius, "vertical_yz", col, alpha * 0.8)
	for i in range(1, 5):
		var z := -radius + 2.0 * radius * float(i) / 5.0
		var rr := sqrt(maxf(0.0, radius * radius - z * z))
		var prev := Vector3.ZERO
		for j in range(65):
			var ang := TAU * float(j) / 64.0
			var p := Vector3(cos(ang) * rr, z, sin(ang) * rr)
			if j > 0:
				_add_line(arr, prev, p, col, alpha * 0.55)
			prev = p


func _add_octahedron(arr: Array, center: Vector3, s: float, col: Color, alpha: float) -> void:
	var pts := [Vector3(s, 0, 0), Vector3(-s, 0, 0), Vector3(0, s, 0),
		Vector3(0, -s, 0), Vector3(0, 0, s), Vector3(0, 0, -s)]
	var edges := [[0, 2], [0, 3], [0, 4], [0, 5], [1, 2], [1, 3], [1, 4], [1, 5],
		[2, 4], [4, 3], [3, 5], [5, 2]]
	for e in edges:
		_add_line(arr, center + (pts[e[0]] as Vector3), center + (pts[e[1]] as Vector3), col, alpha)


func _add_emitter_marker(arr: Array, center: Vector3, col: Color) -> void:
	var s := 0.35
	for i in range(4):
		var a0 := TAU * float(i) / 4.0
		var a1 := a0 + TAU / 4.0
		var p0 := center + Vector3(cos(a0), 0.5, sin(a0)) * s
		var p1 := center + Vector3(cos(a1), 0.5, sin(a1)) * s
		_add_line(arr, p0, p1, col, 0.8)


func _add_tws_ring(arr: Array, center: Vector3, state: String, quality: float, col: Color) -> void:
	var r := 2.0
	var prev := Vector3.ZERO
	for i in range(41):
		var ang := TAU * float(i) / 40.0
		var p := center + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if i > 0:
			_add_line(arr, prev, p, col, 0.22)
		prev = p
	var idx := STATE_ORDER.find(state)
	for i in range(6):
		var ang := -PI * 0.5 + TAU * float(i) / 6.0
		var d := Vector3(cos(ang), 0.0, sin(ang))
		if i == idx:
			_add_line(arr, center + d * r, center + d * (r + 1.0), col, 0.95)
		else:
			_add_line(arr, center + d * r, center + d * (r + 0.5), col, 0.32)
	if quality > 0.01:
		var q0 := -PI * 0.5
		var q1 := q0 + TAU * clampf(quality, 0.0, 1.0)
		prev = Vector3.ZERO
		var steps := maxi(2, int(20.0 * quality))
		for j in range(steps + 1):
			var a: float = lerp(q0, q1, float(j) / float(steps))
			var p := center + Vector3(cos(a), 0.0, sin(a)) * (r + 0.35)
			if j > 0:
				_add_line(arr, prev, p, col, 0.5)
			prev = p


func _add_optical_cone(arr: Array, kind: String, col: Color) -> void:
	var tid := "T1" if kind == "optical" else "T6"
	var ch: Dictionary = _optical_channel(kind, tid)
	if ch.is_empty():
		return
	var st := String(ch.get("status", "idle"))
	if st == "idle":
		return
	var brg := float(ch.get("bearing_deg", -999.0))
	if brg < -900.0:
		return
	var dir := _bearing_dir(brg, float(ch.get("elevation_deg", 0.0)))
	var range_km := float(ch.get("slant_range_km", 0.0))
	var cone_len := clampf(range_km / KM_PER_UNIT * 1.15, 3.0, 38.0)
	var half := deg_to_rad(2.0) if kind == "optical" else deg_to_rad(3.2)
	var alpha := 0.34 if st == "locked" else 0.18
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var side := dir.cross(up).normalized()
	var up2 := side.cross(dir).normalized()
	var ring_pts: Array = []
	for i in range(25):
		var a := TAU * float(i) / 24.0
		ring_pts.append(dir * cone_len + (side * cos(a) + up2 * sin(a)) * (cone_len * tan(half)))
	_add_polyline(arr, ring_pts, col, alpha * 0.9)
	for i in range(8):
		var a2 := TAU * float(i) / 8.0
		var p := dir * cone_len + (side * cos(a2) + up2 * sin(a2)) * (cone_len * tan(half))
		_add_line(arr, Vector3.ZERO, p, col, alpha * 0.5)
	_add_line(arr, Vector3.ZERO, dir * cone_len, col, minf(1.0, alpha * 1.4))


# ═══════════════════════════════════════════════════════════════════
# 6. 每帧 / HUD view-model
# ═══════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_frames += 1
	if not _paused:
		_sim_acc += delta * float(SPEEDS[_speed_idx])
		var guard := 0
		while _sim_acc >= SIM_CHUNK and guard < 240:
			guard += 1
			_sim_acc -= SIM_CHUNK
			_step_sim(SIM_CHUNK)
	_update_camera(delta)
	_rebuild_mesh()
	_update_vm()
	if hud != null:
		hud.set_vm(_vm)
		hud.queue_redraw()
	if _shot_path != "" and _frames >= FRAME_CAPTURE:
		_capture_and_quit()


func _update_vm() -> void:
	var by_state: Dictionary = _tws_out.get("by_state", {}) if _tws_out.get("by_state") is Dictionary else {}
	var chans: Array = _tws_out.get("channels", []) if _tws_out.get("channels") is Array else []
	var vis_ch := _optical_channel("optical", _selected_id)
	var ir_ch := _optical_channel("ir", _selected_id)
	var vis_summary := "—"
	var ir_summary := "—"
	if not vis_ch.is_empty():
		vis_summary = "%s %d%%" % [String(vis_ch.get("status", "idle")),
			int(float(vis_ch.get("progress", 0.0)) * 100.0)]
	if not ir_ch.is_empty():
		ir_summary = "%s %d%%" % [String(ir_ch.get("status", "idle")),
			int(float(ir_ch.get("progress", 0.0)) * 100.0)]
	var vstatus: Dictionary = _optical_out.get("by_status", {}) if _optical_out.get("by_status") is Dictionary else {}
	var vis_total := 0
	var vis_locked := 0
	var ir_total := 0
	var ir_locked := 0
	for raw_oc in (_optical_out.get("channels", []) as Array):
		if not (raw_oc is Dictionary):
			continue
		var oc: Dictionary = raw_oc
		var is_vis := String(oc.get("channel", "")) == "optical"
		if is_vis:
			vis_total += 1
			if String(oc.get("status", "")) == "locked":
				vis_locked += 1
		else:
			ir_total += 1
			if String(oc.get("status", "")) == "locked":
				ir_locked += 1
	var target_rows: Array = []
	for raw in _targets:
		var tr: Dictionary = raw
		var tid := String(tr.get("id", ""))
		var ch := _channel_of(tid)
		var pos_scene := _w(tr.get("pos_km", Vector3.ZERO))
		var screen := Vector2(-9999, -9999)
		var on_screen := false
		if camera != null and not camera.is_position_behind(pos_scene):
			screen = camera.unproject_position(pos_scene)
			on_screen = screen.x > 0.0 and screen.y > 0.0 and screen.x < 1920.0 and screen.y < 1080.0
		var vis := _optical_channel("optical", tid)
		var ir := _optical_channel("ir", tid)
		target_rows.append({
			"id": tid,
			"name": String(tr.get("name", "")),
			"range_km": float(tr.get("range_km", 0.0)),
			"bearing_deg": float(tr.get("bearing_deg", 0.0)),
			"rcs_m2": float(tr.get("rcs_m2", 10.0)),
			"illum": float(tr.get("illum", 1.0)),
			"state": String(ch.get("state", "")),
			"quality": float(ch.get("quality", 0.0)),
			"age_s": float(ch.get("age_s", 0.0)),
			"lost_lock_count": int(ch.get("lost_lock_count", 0)),
			"vis_status": String(vis.get("status", "")),
			"ir_status": String(ir.get("status", "")),
			"selected": tid == _selected_id,
			"on_screen": on_screen,
			"screen": screen,
			"color": _state_col(String(ch.get("state", ""))),
		})
	var sel := _target_by_id(_selected_id)
	var sel_ch := _channel_of(_selected_id)
	var sel_vis := _optical_channel("optical", _selected_id)
	var sel_ir := _optical_channel("ir", _selected_id)
	var selected: Dictionary = {}
	if not sel.is_empty():
		var iff_text := "no query"
		if String(_last_iff.get("target_id", "")) == _selected_id:
			iff_text = String(_last_iff.get("status", "no_reply"))
		var emitter_text := "passive"
		var emissions: Array = sel.get("emissions", [])
		if not emissions.is_empty():
			var em: Dictionary = emissions[0]
			emitter_text = "EMITTING · %s" % String(em.get("model", "radar"))
		selected = {
			"id": _selected_id,
			"name": String(sel.get("name", "")),
			"color": _state_col(String(sel_ch.get("state", ""))),
			"range_text": "%.0f km · bearing %.0f° · elev %.1f°" % [
				float(sel.get("range_km", 0.0)), float(sel.get("bearing_deg", 0.0)),
				float(sel.get("elevation_deg", 0.0))],
			"bearing_text": "RCS %.1f m² · pos %s" % [
				float(sel.get("rcs_m2", 10.0)), str(sel.get("pos_km", Vector3.ZERO))],
			"rcs_text": "R_eff(本目标) %.0f km" % _target_eff_radius(sel),
			"illum_text": "%.2f（光照）" % float(sel.get("illum", 1.0)),
			"tws_text": "%s · q%.0f%% · age %.0f s · lost %d" % [
				_state_short(String(sel_ch.get("state", ""))),
				float(sel_ch.get("quality", 0.0)) * 100.0,
				float(sel_ch.get("age_s", 0.0)), int(sel_ch.get("lost_lock_count", 0))],
			"quality_text": "%.3f Hz · scan %d" % [float(sel_ch.get("update_rate_hz", 0.0)),
				int(_tws_out.get("scan_index", 0))],
			"optical_text": "VIS %s · IR %s" % [_optical_brief(sel_vis), _optical_brief(sel_ir)],
			"iff_text": iff_text,
			"emitter_text": emitter_text,
			"note": "transponder=%s · iff_code=%s · faction=%s" % [
				String(sel.get("transponder", "")), String(sel.get("iff_code", "")),
				String(sel.get("faction", ""))],
		}
	_vm = {
		"t": _t,
		"speed": SPEEDS[_speed_idx],
		"paused": _paused,
		"radar_on": _radar_on,
		"elint_on": _elint_on,
		"source": "v2_sim",
		"model_note": "sim/{sensor_types,radar,tws,optical}.gd + scripts/sensor_model.gd（只读调用）",
		"targets": target_rows,
		"by_state": by_state,
		"channels": chans,
		"tws": {"scan_index": int(_tws_out.get("scan_index", 0)),
			"scan_period_s": float(_tws_out.get("scan_period_s", 6.0))},
		"selected": selected,
		"events": _events,
		"exposure": _exposure.duplicate(true),
		"optical": {"vis_summary": vis_summary, "ir_summary": ir_summary,
			"vis_total": vis_total, "vis_locked": vis_locked,
			"ir_total": ir_total, "ir_locked": ir_locked,
			"vis_locked_all": int(vstatus.get("locked", 0)), "by_status": vstatus},
		"elint": {"signals": _elint_signals},
		"iff": _last_iff,
		"labels_3d": _label_notes(),
	}


func _target_eff_radius(tr: Dictionary) -> float:
	if _radar_rec == null:
		return 0.0
	return RadarModel.effective_radius_km(_radar_rec, float(tr.get("rcs_m2", 10.0)),
		_jamming_at(_t))


func _optical_brief(ch: Dictionary) -> String:
	if ch.is_empty():
		return "off"
	return "%s %d%%" % [String(ch.get("status", "idle")),
		int(float(ch.get("progress", 0.0)) * 100.0)]


func _label_notes() -> Array:
	var out: Array = []
	if camera == null:
		return out
	if _radar_rec != null and _radar_on:
		var eff := RadarModel.effective_radius_km(_radar_rec, 10.0, _jamming_at(_t)) / KM_PER_UNIT
		out.append({"screen": camera.unproject_position(Vector3(eff * 0.72, eff * 0.72, 0.0)),
			"text": "SPHERICAL SEARCH · R_eff %.0f km（V2 球体）" % (eff * KM_PER_UNIT),
			"color": Pal.PH})
		var track := RadarModel.effective_track_radius_km(_radar_rec, 10.0, _jamming_at(_t)) / KM_PER_UNIT
		out.append({"screen": camera.unproject_position(Vector3(track, 0.0, 0.0)),
			"text": "TRACK RING %.0f km（稳定跟踪）" % (track * KM_PER_UNIT), "color": Pal.PH_DIM})
	var vis := _optical_channel("optical", "T1")
	if not vis.is_empty() and String(vis.get("status", "idle")) != "idle":
		var brg := float(vis.get("bearing_deg", 0.0))
		out.append({"screen": camera.unproject_position(_bearing_dir(brg, 0.0) * 30.0),
			"text": "VIS BORESIGHT · %s" % String(vis.get("status", "")), "color": Pal.PH})
	var ir := _optical_channel("ir", "T6")
	if not ir.is_empty() and String(ir.get("status", "idle")) != "idle":
		var brg2 := float(ir.get("bearing_deg", 0.0))
		out.append({"screen": camera.unproject_position(_bearing_dir(brg2, 0.0) * 26.0),
			"text": "IR BORESIGHT · %s" % String(ir.get("status", "")), "color": Pal.BLUE})
	return out


# ═══════════════════════════════════════════════════════════════════
# 7. 输入
# ═══════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist * 0.88, 2.0, 1200.0)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist * 1.12, 2.0, 1200.0)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag_left = mb.pressed
			if mb.pressed:
				_drag_moved = 0.0
			elif _drag_moved < 6.0:
				_click_select(mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_pan = mb.pressed
			if mb.pressed:
				_drag_moved = 0.0
			return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _drag_left:
			_drag_moved += mm.relative.length()
			_cam_yaw = fposmod(_cam_yaw - mm.relative.x * 0.005, TAU)
			_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.004,
				deg_to_rad(-80.0), deg_to_rad(80.0))
			return
		if _drag_pan:
			_drag_moved += mm.relative.length()
			if camera != null:
				var basis := camera.global_transform.basis
				_pan_offset -= basis.x * mm.relative.x * _cam_dist * 0.0016 \
					+ basis.y * mm.relative.y * _cam_dist * 0.0016
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var kk: InputEventKey = event
		match kk.keycode:
			KEY_TAB:
				_cycle_selection(1)
			KEY_0:
				_camera_focus = "own"
				_cam_target = Vector3.ZERO
			KEY_F:
				_camera_focus = "selected" if _camera_focus == "own" else "own"
				_cam_target = _camera_target_pos()
			KEY_R:
				_reset()
			KEY_SPACE:
				_paused = not _paused
			KEY_MINUS, KEY_KP_SUBTRACT:
				_speed_idx = maxi(0, _speed_idx - 1)
			KEY_EQUAL, KEY_KP_ADD:
				_speed_idx = mini(SPEEDS.size() - 1, _speed_idx + 1)
			KEY_M:
				_radar_on = not _radar_on
				_push_event("tws", "本舰雷达 %s" % ("开机（暴露）" if _radar_on else "EMCON 关机（不暴露）"))
			KEY_V:
				_vis_on = not _vis_on
				if _vis_on:
					_optical.start("optical", "T1")
					_optical.start("optical", "T3")
				else:
					_optical.stop("optical")
				_push_event("optical", "VIS 全部通道 %s" % ("开机" if _vis_on else "关机"))
			KEY_I:
				_ir_on = not _ir_on
				if _ir_on:
					_optical.start("ir", "T1")
					_optical.start("ir", "T6")
				else:
					_optical.stop("ir")
				_push_event("optical", "IR 全部通道 %s" % ("开机" if _ir_on else "关机"))
			KEY_E:
				_elint_on = not _elint_on
				_push_event("elint", "ELINT 接收机 %s" % ("开机" if _elint_on else "关机"))
			KEY_Q:
				if _iff_cooldown <= 0.0:
					_iff_query(_selected_id)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var idx := int(kk.keycode - KEY_1)
				if idx >= 0 and idx < _targets.size():
					_select(String((_targets[idx] as Dictionary).get("id", "")))


func _reset() -> void:
	_t = 0.0
	_sim_acc = 0.0
	_speed_idx = 1
	_paused = false
	_radar_on = true
	_elint_on = true
	_vis_on = true
	_ir_on = true
	_events.clear()
	_last_iff = {}
	_last_elint_emit_t.clear()
	_auto_iff_done.clear()
	_setup_models()
	_setup_targets()
	_apply_view("overview")


func _select(tid: String) -> void:
	if tid == "" or _target_by_id(tid).is_empty():
		return
	_selected_id = tid
	if _camera_focus == "selected":
		_cam_target = _camera_target_pos()


func _cycle_selection(dir: int) -> void:
	if _targets.is_empty():
		return
	var ids: Array = []
	for raw in _targets:
		ids.append(String((raw as Dictionary).get("id", "")))
	var i := ids.find(_selected_id)
	i = (i + dir + ids.size()) % ids.size()
	_select(String(ids[i]))


func _click_select(pos: Vector2) -> void:
	if hud != null and hud.has_method("row_at"):
		var rid := String(hud.call("row_at", pos))
		if rid != "":
			_select(rid)
			return
	var best := ""
	var best_d := 16.0
	for raw in _targets:
		var tr: Dictionary = raw
		var p := _project(_w(tr.get("pos_km", Vector3.ZERO)))
		if p.x < 0.0:
			continue
		var d := p.distance_to(pos)
		if d < best_d:
			best_d = d
			best = String(tr.get("id", ""))
	if best != "":
		_select(best)


func _project(world: Vector3) -> Vector2:
	if camera == null or camera.is_position_behind(world):
		return Vector2(-9999, -9999)
	return camera.unproject_position(world)


func _state_col(st: String) -> Color:
	match st:
		"SEARCH":
			return Pal.DIM
		"DETECT":
			return Pal.PH_DIM
		"ACQUIRE":
			return Pal.BLUE
		"TRACK", "STARE":
			return Pal.PH
		"FIRE_CONTROL":
			return Pal.AMBER
		_:
			return Pal.DIM


# ═══════════════════════════════════════════════════════════════════
# 8. 截图
# ═══════════════════════════════════════════════════════════════════

func _capture_and_quit() -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("[SX] SHOT %s err=%d view=%s t=%.1f tws=%d events=%d → %s" % [
		str(img.get_size()), err, _shot_view, _t, int(_tws_out.get("channel_count", 0)),
		_events.size(), _shot_path])
	get_tree().quit(0 if err == OK else 1)
