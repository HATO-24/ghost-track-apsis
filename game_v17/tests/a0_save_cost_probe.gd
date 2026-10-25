extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# DS-A-07 · 正式会话的长时存档成本标定（measurement only）
#
# 基线：I6（10a4865…）。本探针**只测量**：不引入 checkpoint、不做压缩、不跳过 tick
# 重放、不声称满足任何尚未制定的产品性能预算。
#
# 固定负载：
#   * seed 从**正式 HUD orbital_sim 入口**装配（main_menu → v1_hud → ShellBinder →
#     GameSession），记录 scenario 文件 hash + 完整 seed hash；
#   * dt=1.0 s、time scale=1、无暂停；每 50 tick 施加固定控制操作序列；
#   * 每个规模（50/200/800/1000）都从**全新同 seed 会话**独立开始；
#   * 每规模 1 次预热 + 3 次独立测量；计时用单调时钟 ms。
#
# 分项计时：save_state / 文件写入 / 文件读取 / load_state(replay) / tick 总耗时。
# 正确性（每规模，取中位样本恢复后）：frame/t、physics/world 数值、事件 seq/去重、
# 传感器运行态、以及与未中断会话再跑 10 tick 的一致性。
#
# 输出：`A0-A07 SAVE COST PROBE RESULT: PASS=n FAIL=m`（正确性为准；性能样本即使很快，
# 正确性失败也计 FAIL）+ `A0-A07 MEASUREMENTS JSON: {...}` 供归档。
# ═══════════════════════════════════════════════════════════════════

const TARGET_PROFILE := "orbital_sim"
const TARGET_SCENARIO := "res://framework/content/scenario_orbital_sim.json"
const MAIN_MENU := "res://main_menu.tscn"
const V1_HUD := "res://v1_hud.tscn"
const GameSessionScript := preload("res://scripts/core/game_session.gd")
const SaveServiceScript := preload("res://scripts/core/save_service.gd")

const MAX_BOOT_FRAMES := 600
const MAX_BOOT_MS := 60000
const MAX_BINDER_FRAMES := 120
const WATCHDOG_S := 1500.0
const SCALES := [50, 200, 800, 1000]
const MEASURED_RUNS := 3
const TICK_DT := 1.0
const OP_EVERY := 50
const CORRECTNESS_TICKS := 10
const NUM_TOL := 1.0e-9
const TIME_TOL := 1.0e-6
# 安全超时（只用于终止失控测试，**不是**产品性能预算）
const SAFE_TIMEOUT_S := 1800

const ENV_KEYS := ["DSH_BUILD", "DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE",
	"DSH_V1_TEST", "DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
	"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _env_backup: Dictionary = {}
var _finished := false
var _main_menu_instantiated := false
var _seed: Dictionary = {}
var _env: Dictionary = {}
var _results: Array = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-A07 SAVE COST PROBE · baseline I6 · MEASUREMENT ONLY")
	print("Godot ", Engine.get_version_info().get("string", "?"), " · profile=", TARGET_PROFILE)
	print("════════════════════════════════════════════════════════════════")
	_setup_env()
	node_added.connect(_on_node_added)
	_watchdog()
	_run()


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	var scr = node.get_script()
	if scr != null and String(scr.resource_path) == "res://scripts/ui/main_menu.gd":
		_main_menu_instantiated = true


func _watchdog() -> void:
	await create_timer(WATCHDOG_S).timeout
	if _finished:
		return
	print("[A0-A07] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
	_fail += 1
	_failures.append("watchdog timeout")
	_finish()


func _setup_env() -> void:
	for k in ENV_KEYS:
		_env_backup[k] = OS.get_environment(k)
	OS.set_environment("DSH_BUILD", TARGET_PROFILE)
	for k in ["DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE", "DSH_V1_TEST",
			"DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
			"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]:
		OS.set_environment(k, "")


func _restore_env() -> void:
	for k in ENV_KEYS:
		var v := String(_env_backup.get(k, ""))
		if v == "":
			OS.unset_environment(k)
		else:
			OS.set_environment(k, v)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if not _results.is_empty():
		print("A0-A07 MEASUREMENTS JSON: " + JSON.stringify({
			"schema": "v17.save_cost.v1", "version": 1,
			"environment": _env, "scales": _results,
			"safe_timeout_s": SAFE_TIMEOUT_S,
			"product_budget_claim": false,
		}))
	print("────────────────────────────────────────────────────────────────")
	print("A0-A07 SAVE COST PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-A07] FAILED: ", f)
		print("A0-A07 SAVE COST PROBE FAILED")
	else:
		print("A0-A07 SAVE COST PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-A07] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-A07] FAIL ", line)


func _step(title: String) -> void:
	print("")
	print("[A0-A07] STEP ", title)


func _info(text: String) -> void:
	print("[A0-A07] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. assemble the fixed workload from the real HUD orbital_sim entry")
	var err := change_scene_to_file(MAIN_MENU)
	_ok(err == OK, "change_scene_to_file(main_menu) == OK", "err=%d" % err)
	if err != OK:
		_finish()
		return
	var boot := await _await_v1_hud()
	if boot["hud"] == null:
		_finish()
		return
	var binder = boot["hud"].get("binder")
	var session = binder.get("session") if binder != null else null
	_ok(session != null, "GameSession available from the real entry")
	if session == null:
		_finish()
		return
	_seed = session._seed.duplicate(true) if session._seed is Dictionary else {}
	_ok(not _seed.is_empty(), "captured the normalized seed from the real HUD session",
		"keys=" + str(_seed.keys().size()))
	# 固定 scenario hash（内容级，不依赖工作区路径）
	var scenario_text := FileAccess.get_file_as_string(TARGET_SCENARIO)
	_env = {
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"processor": OS.get_processor_name(),
		"cpu_count": OS.get_processor_count(),
		"godot": Engine.get_version_info().get("string", ""),
		"headless": DisplayServer.get_name() == "headless",
		"renderer": "headless" if DisplayServer.get_name() == "headless" else "display",
		"static_memory_mb": OS.get_static_memory_usage() / 1048576.0,
		"profile": TARGET_PROFILE,
		"scenario_path": TARGET_SCENARIO,
		"scenario_sha256": scenario_text.sha256_text(),
		"seed_sha256": JSON.stringify(_seed).sha256_text(),
		"seed_keys": _seed.keys().size(),
		"dt_s": TICK_DT, "time_scale": 1.0, "paused": false,
		"op_every_ticks": OP_EVERY,
		"scales": SCALES, "warmup_runs": 1, "measured_runs": MEASURED_RUNS,
		"git_head": OS.get_environment("A07_HEAD"),
	}
	_info("ENV: " + JSON.stringify(_env))
	_ok(String(_env["scenario_sha256"]).length() == 64,
		"scenario content hash recorded (sha256)")
	_ok(String(_env["seed_sha256"]).length() == 64, "seed hash recorded (sha256)")
	_ok(bool(_env["headless"]), "running headless (stated explicitly in the report)")

	_step("2. per-scale measurement (fresh session each scale, 1 warmup + 3 measured)")
	for n in SCALES:
		_measure_scale(int(n))

	_step("3. cost table summary")
	_info("SCALE_TABLE: " + JSON.stringify(_scale_table()))
	_finish()


func _measure_scale(ticks: int) -> void:
	var sizes: Array = []
	var save_ms: Array = []
	var write_ms: Array = []
	var read_ms: Array = []
	var load_ms: Array = []
	var tick_ms: Array = []
	var bus_events: Array = []
	var seen_ids: Array = []
	var log_ops: Array = []
	var samples: Array = []
	for run_i in range(1 + MEASURED_RUNS):
		var warmup := run_i == 0
		var s = GameSessionScript.new(_seed)
		if not bool(s.ready):
			_ok(false, "scale %d: session ready" % ticks, str(s.errors))
			return
		# 固定负载：dt=1.0、scale=1、无暂停；每 OP_EVERY tick 一个固定控制操作
		s.time.scale = 1.0
		s.time.paused = false
		var t0 := Time.get_ticks_msec()
		var op_i := 0
		var tick_errors: Array = []
		for i in range(ticks):
			var tr: Dictionary = s.tick(TICK_DT)
			if not bool(tr.get("ok", false)):
				tick_errors.append(str(tr.get("reason", "")))
			if (i + 1) % OP_EVERY == 0:
				var op: Dictionary = _control_op(s, op_i)
				op_i += 1
				if not bool(op.get("ok", true)):
					tick_errors.append("op:" + str(op.get("reason", "")))
		var tick_total := Time.get_ticks_msec() - t0
		var t_save := Time.get_ticks_msec()
		var text: String = s.save_state()
		var save_elapsed := Time.get_ticks_msec() - t_save
		# 文件写入 / 读取（真实文件）
		var path := "user://a07_scale_%d_run_%d.json" % [ticks, run_i]
		var t_w := Time.get_ticks_msec()
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
		var write_elapsed := Time.get_ticks_msec() - t_w
		var t_r := Time.get_ticks_msec()
		var read_text := FileAccess.get_file_as_string(path)
		var read_elapsed := Time.get_ticks_msec() - t_r
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		# load_state（不含引擎启动；进程已在本探针内）
		var t_l := Time.get_ticks_msec()
		var loaded = GameSessionScript.new()
		var lr: Dictionary = loaded.load_state(read_text)
		var load_elapsed := Time.get_ticks_msec() - t_l
		var rec := {
			"ticks": ticks, "run": run_i, "warmup": warmup,
			"ok": bool(lr.get("ok", false)),
			"tick_total_ms": tick_total,
			"tick_errors": tick_errors.size(),
			"save_state_ms": save_elapsed,
			"file_write_ms": write_elapsed,
			"file_read_ms": read_elapsed,
			"load_state_ms": load_elapsed,
			"bytes": text.length(),
			"bytes_utf8": text.to_utf8_buffer().size(),
			"bus_visible_events": int(s.bus.events.size()),
			"bus_used_ids": int(s.bus._seen_ids.size()),
			"bus_seq": int(s.bus.current_seq()),
			"log_ops": int(s._log.size()),
			"entities": int(s.world.entities_sorted().size() if s.world != null else 0),
			"t_s": float(s.now_s()),
			"loaded_ok": bool(lr.get("ok", false)),
		}
		_info("SAMPLE ticks=%d run=%d warmup=%s ok=%s bytes=%d tick=%dms save=%dms "
			+ "write=%dms read=%dms load=%dms log_ops=%d bus_events=%d"
			% [ticks, run_i, str(warmup), str(rec["ok"]), int(rec["bytes"]),
				tick_total, save_elapsed, write_elapsed, read_elapsed, load_elapsed,
				int(rec["log_ops"]), int(rec["bus_visible_events"])])
		if not warmup:
			sizes.append(int(rec["bytes"]))
			save_ms.append(save_elapsed)
			write_ms.append(write_elapsed)
			read_ms.append(read_elapsed)
			load_ms.append(load_elapsed)
			tick_ms.append(tick_total)
			bus_events.append(int(rec["bus_visible_events"]))
			seen_ids.append(int(rec["bus_used_ids"]))
			log_ops.append(int(rec["log_ops"]))
			samples.append(rec)
			# 正确性：取第一份可用恢复样本做完整核对（其余只核 ok）
			if samples.size() == 1:
				_correctness(ticks, s, loaded, lr)
		_ok(bool(lr.get("ok", false)),
			"scale %d run %d: load_state ok" % [ticks, run_i],
			str(lr.get("errors", [])))
	_ok(samples.size() == MEASURED_RUNS,
		"scale %d: %d measured samples recorded" % [ticks, MEASURED_RUNS],
		"n=" + str(samples.size()))
	_results.append({
		"ticks": ticks,
		"samples": samples,
		"bytes": _stats(sizes),
		"save_state_ms": _stats(save_ms),
		"file_write_ms": _stats(write_ms),
		"file_read_ms": _stats(read_ms),
		"load_state_ms": _stats(load_ms),
		"tick_total_ms": _stats(tick_ms),
		"bus_visible_events": int(bus_events[0]) if bus_events.size() > 0 else 0,
		"bus_used_ids": int(seen_ids[0]) if seen_ids.size() > 0 else 0,
		"log_ops": int(log_ops[0]) if log_ops.size() > 0 else 0,
		"note": "median/min/max over %d measured samples (NOT a p95 claim)" % MEASURED_RUNS,
	})
	_info("SCALE %d DONE: bytes=%s load_ms=%s save_ms=%s" % [ticks,
		JSON.stringify(_stats(sizes)), JSON.stringify(_stats(load_ms)),
		JSON.stringify(_stats(save_ms))])


## 固定控制操作序列（确定性；不使用有限弹药/授权相关状态变更）。
func _control_op(s, idx: int) -> Dictionary:
	match idx % 4:
		0:
			return s.send_comms("apsis", "harmattan", "LD", "COMMS_SENT", {}, {})
		1:
			if s.sensor_service != null:
				return s.sensor_service.start_channel("optical", "harmattan")
			return {"ok": true, "skipped": "no_sensor"}
		2:
			if s.sensor_service != null:
				return s.sensor_service.start_channel("ir", "harmattan")
			return {"ok": true, "skipped": "no_sensor"}
		_:
			if s.sensor_service != null:
				s.sensor_service.set_emcon(not bool(s.sensor_service.emcon))
				return {"ok": true}
			return {"ok": true, "skipped": "no_sensor"}


func _correctness(ticks: int, original, restored, lr: Dictionary) -> void:
	var label := "scale %d" % ticks
	_ok(bool(lr.get("ok", false)), "%s: restored session loaded" % label)
	if not bool(lr.get("ok", false)):
		return
	# frame / t（A-02 契约）
	_ok(absf(float(restored.now_s()) - float(original.now_s())) <= TIME_TOL,
		"%s: restored relative time matches" % label,
		"orig=%.6f rest=%.6f" % [float(original.now_s()), float(restored.now_s())])
	var meta_o: Dictionary = original.session_time_frame_meta()
	var meta_r: Dictionary = restored.session_time_frame_meta()
	_ok(String(meta_r.get("runtime_frame", "")) == String(meta_o.get("runtime_frame", "")),
		"%s: restored frame matches" % label,
		"%s/%s" % [String(meta_o.get("runtime_frame", "")),
			String(meta_r.get("runtime_frame", ""))])
	# physics / world 数值
	var pf_bad: Array = []
	if original.physics_world_service != null and restored.physics_world_service != null:
		for raw_e in original._seed.get("entities", []):
			var eid := String((raw_e as Dictionary).get("id", ""))
			var so: Dictionary = original.physics_state(eid)
			var sr: Dictionary = restored.physics_state(eid)
			var ro: Array = so.get("r", [])
			var rr: Array = sr.get("r", [])
			var vo: Array = so.get("v", [])
			var vr: Array = sr.get("v", [])
			if ro.size() < 3 or rr.size() < 3:
				pf_bad.append({"entity": eid, "reason": "missing r"})
				continue
			for i in range(3):
				if absf(float(ro[i]) - float(rr[i])) > NUM_TOL:
					pf_bad.append({"entity": eid, "axis": "r%d" % i,
						"orig": float(ro[i]), "rest": float(rr[i])})
				if absf(float(vo[i]) - float(vr[i])) > NUM_TOL:
					pf_bad.append({"entity": eid, "axis": "v%d" % i})
	_ok(pf_bad.is_empty(), "%s: physics r/v roundtrip within 1e-9" % label,
		"violations=" + str(pf_bad.slice(0, 5)))
	# 事件 seq / 去重
	var ev_bad: Array = []
	for raw_ev in restored.bus.events:
		if not ((raw_ev as Dictionary).get("seq", 0) is int):
			ev_bad.append("non-int seq")
			break
	if int(restored.bus.current_seq()) < int(original.bus.current_seq()):
		ev_bad.append("seq regression")
	if int(restored.bus._seen_ids.size()) < int(original.bus._seen_ids.size()):
		ev_bad.append("dedup set shrank")
	_ok(ev_bad.is_empty(), "%s: event seq int + dedup set preserved" % label,
		str(ev_bad))
	# 传感器运行态（A-05 契约）
	var sens_bad: Array = []
	if original.sensor_service != null and restored.sensor_service != null:
		var so2 = original.sensor_service
		var sr2 = restored.sensor_service
		if bool(so2.emcon) != bool(sr2.emcon):
			sens_bad.append("emcon")
		if bool(so2.radar_enabled) != bool(sr2.radar_enabled):
			sens_bad.append("radar")
		if int(so2._obs_seq) != int(sr2._obs_seq):
			sens_bad.append("obs_seq")
		if int(so2._event_seq) != int(sr2._event_seq):
			sens_bad.append("event_seq")
	_ok(sens_bad.is_empty(), "%s: sensor runtime state restored exactly" % label,
		str(sens_bad))
	# 与未中断会话再跑相同 10 tick
	var ok10 := true
	for i in range(CORRECTNESS_TICKS):
		var a: Dictionary = original.tick(TICK_DT)
		var b: Dictionary = restored.tick(TICK_DT)
		if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
			ok10 = false
	_ok(ok10, "%s: both sessions ran %d more ticks" % [label, CORRECTNESS_TICKS])
	_ok(absf(float(restored.now_s()) - float(original.now_s())) <= TIME_TOL,
		"%s: time still aligned after %d more ticks" % [label, CORRECTNESS_TICKS],
		"orig=%.9f rest=%.9f" % [float(original.now_s()), float(restored.now_s())])
	_ok(int(restored.bus.current_seq()) >= int(original.bus.current_seq()) - 0,
		"%s: restored bus seq continues after +%d ticks" % [label, CORRECTNESS_TICKS],
		"orig=%d rest=%d" % [int(original.bus.current_seq()),
			int(restored.bus.current_seq())])


func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"median": -1, "min": -1, "max": -1, "n": 0}
	var sorted_v: Array = values.duplicate()
	sorted_v.sort()
	var n := sorted_v.size()
	var median = sorted_v[n / 2] if n % 2 == 1 \
		else (float(sorted_v[n / 2 - 1]) + float(sorted_v[n / 2])) / 2.0
	return {"median": median, "min": sorted_v[0], "max": sorted_v[n - 1], "n": n}


func _scale_table() -> Array:
	var out: Array = []
	for raw in _results:
		var r: Dictionary = raw
		out.append({
			"ticks": r.get("ticks", 0),
			"bytes_median": (r.get("bytes", {}) as Dictionary).get("median", -1),
			"bytes_min": (r.get("bytes", {}) as Dictionary).get("min", -1),
			"bytes_max": (r.get("bytes", {}) as Dictionary).get("max", -1),
			"tick_ms_median": (r.get("tick_total_ms", {}) as Dictionary).get("median", -1),
			"save_ms_median": (r.get("save_state_ms", {}) as Dictionary).get("median", -1),
			"write_ms_median": (r.get("file_write_ms", {}) as Dictionary).get("median", -1),
			"read_ms_median": (r.get("file_read_ms", {}) as Dictionary).get("median", -1),
			"load_ms_median": (r.get("load_state_ms", {}) as Dictionary).get("median", -1),
			"log_ops": r.get("log_ops", 0),
			"bus_visible_events": r.get("bus_visible_events", 0),
			"bus_used_ids": r.get("bus_used_ids", 0),
		})
	return out


func _await_v1_hud() -> Dictionary:
	var frames := 0
	var saw_main_menu := false
	var t0 := Time.get_ticks_msec()
	while frames < MAX_BOOT_FRAMES and (Time.get_ticks_msec() - t0) < MAX_BOOT_MS:
		await process_frame
		frames += 1
		var cs = current_scene
		if cs == null:
			continue
		var path := String(cs.scene_file_path)
		if path == MAIN_MENU:
			saw_main_menu = true
			continue
		if path != V1_HUD:
			continue
		var hud = cs
		var f2 := 0
		while f2 < MAX_BINDER_FRAMES:
			var b = hud.get("binder")
			if b != null and bool(b.get("ready")):
				break
			await process_frame
			f2 += 1
		return {"hud": hud, "frames": frames,
			"saw_main_menu": saw_main_menu or _main_menu_instantiated}
	print("[A0-A07] FAIL entry timeout waiting for v1_hud")
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames}
