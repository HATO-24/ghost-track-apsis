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
		"scales": _scales(), "warmup_runs": 1, "measured_runs": MEASURED_RUNS,
		# R05：记录**真实代码 SHA**（不再用空环境变量当 provenance）。
		"git_head": _git_head(),
		"git_head_source": String(_git_head_provenance),
	}
	_info("ENV: " + JSON.stringify(_env))
	_ok(String(_env["scenario_sha256"]).length() == 64,
		"scenario content hash recorded (sha256)")
	_ok(String(_env["seed_sha256"]).length() == 64, "seed hash recorded (sha256)")
	_ok(bool(_env["headless"]), "running headless (stated explicitly in the report)")

	_step("2. per-scale measurement (fresh session each scale, 1 warmup + 3 measured)")
	for n in _scales():
		_measure_scale(int(n))

	_step("3. cost table summary")
	_info("SCALE_TABLE: " + JSON.stringify(_scale_table()))
	_finish()


## R05：解析真实代码 SHA。依次尝试 CI 环境变量与工作区 .git，并记录来源。
var _git_head_provenance := "none"

func _git_head() -> String:
	for env_key in ["GITHUB_SHA", "A07_HEAD", "CI_COMMIT_SHA"]:
		var v := OS.get_environment(env_key).strip_edges()
		if v.length() >= 7:
			_git_head_provenance = "env:" + env_key
			return v
	# 工作区 .git（res:// 是 game_v17/，仓库根在上一级）
	var repo_root := ProjectSettings.globalize_path("res://").get_base_dir()
	for base in [repo_root.path_join(".git"), ProjectSettings.globalize_path("res://.git")]:
		var head_path: String = String(base).path_join("HEAD")
		if not FileAccess.file_exists(head_path):
			continue
		var head_txt := FileAccess.get_file_as_string(head_path).strip_edges()
		if head_txt.begins_with("ref:"):
			var ref := head_txt.substr(4).strip_edges()
			var ref_path: String = String(base).path_join(ref)
			if FileAccess.file_exists(ref_path):
				_git_head_provenance = ".git/" + ref
				return FileAccess.get_file_as_string(ref_path).strip_edges()
			# packed-refs 回退
			var packed: String = String(base).path_join("packed-refs")
			if FileAccess.file_exists(packed):
				for line in FileAccess.get_file_as_string(packed).split("\n"):
					var parts := line.strip_edges().split(" ")
					if parts.size() == 2 and parts[1] == ref:
						_git_head_provenance = ".git/packed-refs"
						return parts[0]
		elif head_txt.length() >= 7:
			_git_head_provenance = ".git/HEAD(detached)"
			return head_txt
	_git_head_provenance = "none"
	return ""


## R05/Q03：规模可通过 A07_SCALES（逗号分隔）覆盖；默认沿 A-07 的 50/200/800/1000。
func _scales() -> Array:
	var raw := OS.get_environment("A07_SCALES").strip_edges()
	if raw == "":
		return SCALES.duplicate()
	var out: Array = []
	for part in raw.split(","):
		var p := String(part).strip_edges()
		if p.is_valid_int() and int(p) > 0:
			out.append(int(p))
	return out if not out.is_empty() else SCALES.duplicate()


func _measure_scale(ticks: int) -> void:
	var sizes: Array = []
	var chars: Array = []
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
		# R05：**落盘文件真实长度**（与 UTF-8 编码后的字节数交叉核对）
		var file_bytes := 0
		if FileAccess.file_exists(path):
			file_bytes = FileAccess.get_file_as_bytes(path).size()
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
			# R05：字符数与真实 UTF-8 字节分列；并与落盘文件长度交叉核对。
			"chars": text.length(),
			"bytes_utf8": text.to_utf8_buffer().size(),
			"file_bytes": file_bytes,
			"bus_visible_events": int(s.bus.events.size()),
			"bus_used_ids": int(s.bus._seen_ids.size()),
			"bus_seq": int(s.bus.current_seq()),
			"log_ops": int(s._log.size()),
			"entities": int(s.world.entities_sorted().size() if s.world != null else 0),
			"t_s": float(s.now_s()),
			"loaded_ok": bool(lr.get("ok", false)),
		}
		_info(("SAMPLE ticks=%d run=%d warmup=%s ok=%s bytes=%d tick=%dms save=%dms "
			+ "write=%dms read=%dms load=%dms log_ops=%d bus_events=%d")
			% [ticks, run_i, str(warmup), str(rec["ok"]), int(rec["bytes_utf8"]),
				tick_total, save_elapsed, write_elapsed, read_elapsed, load_elapsed,
				int(rec["log_ops"]), int(rec["bus_visible_events"])])
		if not warmup:
			sizes.append(int(rec["bytes_utf8"]))
			chars.append(int(rec["chars"]))
			save_ms.append(save_elapsed)
			write_ms.append(write_elapsed)
			read_ms.append(read_elapsed)
			load_ms.append(load_elapsed)
			tick_ms.append(tick_total)
			bus_events.append(int(rec["bus_visible_events"]))
			seen_ids.append(int(rec["bus_used_ids"]))
			log_ops.append(int(rec["log_ops"]))
			samples.append(rec)
			# R05：**每一个**非预热样本都做完整核对（不能只查首样本）；
			# 并支持故障注入：注入后驱动必须 FAIL。
			_correctness(ticks, run_i, s, loaded, lr)
		# R05：UTF-8 字节必须与落盘文件长度一致（不能只报字符数）。
		_ok(file_bytes > 0 and file_bytes == int(rec["bytes_utf8"]),
			"scale %d run %d: UTF-8 bytes match the on-disk file size" % [ticks, run_i],
			"file=%d utf8=%d chars=%d" % [file_bytes, int(rec["bytes_utf8"]),
				int(rec["chars"])])
		_ok(bool(lr.get("ok", false)),
			"scale %d run %d: load_state ok" % [ticks, run_i],
			str(lr.get("errors", [])))
	_ok(samples.size() == MEASURED_RUNS,
		"scale %d: %d measured samples recorded" % [ticks, MEASURED_RUNS],
		"n=" + str(samples.size()))
	_results.append({
		"ticks": ticks,
		"samples": samples,
		"bytes_utf8": _stats(sizes),
		"chars": _stats(chars),
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


## A00：完整规范化状态比较（只读）。返回违规列表；空表示恢复状态与原始一致。
## 比较内容按契约：完整已用 ID 集合（成员，不只大小）、seq/allocator 真 int 与单调性、
## World/Physics 同 tick 运动学、Sensor controls/backend/channel/排队观测、
## Comms 在途队列与 outcome 记录。排除对象地址/墙钟/明示诊断计数。
func _full_state_violations(original, restored) -> Array:
	var bad: Array = []
	# ── EventBus：完整已用 ID 集合成员 + seq 整数/单调 ──────────
	var seen_o: Array = []
	for k in original.bus._seen_ids.keys():
		seen_o.append(String(k))
	seen_o.sort()
	var seen_r: Array = []
	for k2 in restored.bus._seen_ids.keys():
		seen_r.append(String(k2))
	seen_r.sort()
	if JSON.stringify(seen_o) != JSON.stringify(seen_r):
		var only_o: Array = []
		for s in seen_o:
			if not (s in seen_r):
				only_o.append(s)
		var only_r: Array = []
		for s2 in seen_r:
			if not (s2 in seen_o):
				only_r.append(s2)
		bad.append({"area": "bus.seen_ids", "only_original": only_o.slice(0, 5),
			"only_restored": only_r.slice(0, 5),
			"size_equal": seen_o.size() == seen_r.size()})
	if not (restored.bus.seq is int):
		bad.append({"area": "bus.seq", "reason": "not int"})
	if not (restored.bus._id_seq is int):
		bad.append({"area": "bus.id_seq", "reason": "not int"})
	if int(restored.bus.current_seq()) != int(original.bus.current_seq()):
		bad.append({"area": "bus.seq", "original": int(original.bus.current_seq()),
			"restored": int(restored.bus.current_seq())})
	var last_seq := 0
	for raw_ev in restored.bus.events:
		if not (raw_ev is Dictionary):
			continue
		var e: Dictionary = raw_ev
		if not (e.get("seq", 0) is int):
			bad.append({"area": "bus.events.seq", "reason": "non-int",
				"id": String(e.get("id", ""))})
			break
		if int(e.get("seq", 0)) <= last_seq:
			bad.append({"area": "bus.events.seq", "reason": "not strictly increasing",
				"at": String(e.get("id", ""))})
			break
		last_seq = int(e.get("seq", 0))
	# 可见事件 ID/schema 顺序一致
	var ev_ids_o: Array = []
	for raw_o in original.bus.events:
		ev_ids_o.append(String((raw_o as Dictionary).get("id", "")))
	var ev_ids_r: Array = []
	for raw_r in restored.bus.events:
		ev_ids_r.append(String((raw_r as Dictionary).get("id", "")))
	if JSON.stringify(ev_ids_o) != JSON.stringify(ev_ids_r):
		bad.append({"area": "bus.events.ids", "original": ev_ids_o.size(),
			"restored": ev_ids_r.size(),
			"same_head": ev_ids_o.size() > 0 and ev_ids_r.size() > 0 \
				and ev_ids_o[0] == ev_ids_r[0]})
	# ── World / Physics 同 tick 运动学 ───────────────────────────
	if original.physics_world_service != null and restored.physics_world_service != null:
		if absf(float(original.physics_world_service.t)
				- float(restored.physics_world_service.t)) > TIME_TOL:
			bad.append({"area": "physics.t",
				"original": float(original.physics_world_service.t),
				"restored": float(restored.physics_world_service.t)})
		for raw_e2 in original._seed.get("entities", []):
			var eid := String((raw_e2 as Dictionary).get("id", ""))
			var so: Dictionary = original.physics_state(eid)
			var sr: Dictionary = restored.physics_state(eid)
			var ro: Array = so.get("r", []) if so.get("r") is Array else []
			var rr: Array = sr.get("r", []) if sr.get("r") is Array else []
			var vo: Array = so.get("v", []) if so.get("v") is Array else []
			var vr: Array = sr.get("v", []) if sr.get("v") is Array else []
			if ro.size() < 3 or rr.size() < 3:
				bad.append({"area": "physics.r", "entity": eid, "reason": "missing"})
				continue
			for i in range(3):
				if absf(float(ro[i]) - float(rr[i])) > NUM_TOL:
					bad.append({"area": "physics.r", "entity": eid, "axis": i,
						"original": float(ro[i]), "restored": float(rr[i])})
				if absf(float(vo[i]) - float(vr[i])) > NUM_TOL:
					bad.append({"area": "physics.v", "entity": eid, "axis": i})
			# world 投影必须与 physics 同刻一致（同源副本 ≤1e-9 km）
			if original.world != null and restored.world != null:
				var we_o: Dictionary = original.world.entity(eid)
				var we_r: Dictionary = restored.world.entity(eid)
				var wp_o: Array = we_o.get("pos_km", []) \
					if we_o.get("pos_km") is Array else []
				var wp_r: Array = we_r.get("pos_km", []) \
					if we_r.get("pos_km") is Array else []
				if wp_o.size() >= 3 and wp_r.size() >= 3:
					for j in range(3):
						if absf(float(wp_o[j]) - float(wp_r[j])) > NUM_TOL:
							bad.append({"area": "world.pos_km", "entity": eid,
								"axis": j})
	# ── Sensor：controls / backend / channels / 排队观测 ────────
	if original.sensor_service != null and restored.sensor_service != null:
		var so2 = original.sensor_service
		var sr2 = restored.sensor_service
		for fld in ["emcon", "radar_enabled", "selected_target", "optical_backend"]:
			if str(so2.get(fld)) != str(sr2.get(fld)):
				bad.append({"area": "sensor." + fld, "original": str(so2.get(fld)),
					"restored": str(sr2.get(fld))})
		for af in ["obs_seq", "evidence_seq", "event_seq"]:
			var av = so2.get("_" + af)
			var bv = sr2.get("_" + af)
			if not (bv is int):
				bad.append({"area": "sensor." + af, "reason": "not int"})
			if int(av) != int(bv):
				bad.append({"area": "sensor." + af, "original": int(av),
					"restored": int(bv)})
		# backend 通道完整内容（kind/target/status/progress）
		var be_o: Dictionary = so2._authority.export_backend_state() \
			if so2._authority != null else {}
		var be_r: Dictionary = sr2._authority.export_backend_state() \
			if sr2._authority != null else {}
		var ch_o: Array = be_o.get("channels", []) if be_o.get("channels") is Array else []
		var ch_r: Array = be_r.get("channels", []) if be_r.get("channels") is Array else []
		if ch_o.size() != ch_r.size():
			bad.append({"area": "sensor.backend.channels", "original": ch_o.size(),
				"restored": ch_r.size()})
		else:
			for ci in range(ch_o.size()):
				var co: Dictionary = ch_o[ci]
				var cr: Dictionary = ch_r[ci]
				for cf in ["kind", "target_id", "status"]:
					if String(co.get(cf, "")) != String(cr.get(cf, "")):
						bad.append({"area": "sensor.backend." + cf,
							"channel": ci, "original": String(co.get(cf, "")),
							"restored": String(cr.get(cf, ""))})
				if absf(float(co.get("progress", 0.0))
						- float(cr.get("progress", 0.0))) > NUM_TOL:
					bad.append({"area": "sensor.backend.progress", "channel": ci})
		# 排队（待路由）观测：完整 ID 流一致
		var ob_o: Array = []
		for raw_o2 in so2.observations:
			ob_o.append(String((raw_o2 as Dictionary).get("event_id", "")))
		var ob_r: Array = []
		for raw_r2 in sr2.observations:
			ob_r.append(String((raw_r2 as Dictionary).get("event_id", "")))
		if JSON.stringify(ob_o) != JSON.stringify(ob_r):
			bad.append({"area": "sensor.observations.ids", "original": ob_o.size(),
				"restored": ob_r.size()})
		# 去重键完整集合
		var dk_o: Array = so2._optical_evidence_seen.keys()
		dk_o.sort()
		var dk_r: Array = sr2._optical_evidence_seen.keys()
		dk_r.sort()
		if JSON.stringify(dk_o) != JSON.stringify(dk_r):
			bad.append({"area": "sensor.dedup", "original": dk_o.size(),
				"restored": dk_r.size()})
	# ── Comms：在途队列与 outcome 记录 ─────────────────────────
	if original.comms != null and restored.comms != null:
		var pend_o: Array = []
		for raw_p in original.comms.pending:
			var po: Dictionary = raw_p
			pend_o.append("%s@%.6f" % [String(po.get("delivery_id", "")),
				float(po.get("arrive_t", -1.0))])
		var pend_r: Array = []
		for raw_pr in restored.comms.pending:
			var pr: Dictionary = raw_pr
			pend_r.append("%s@%.6f" % [String(pr.get("delivery_id", "")),
				float(pr.get("arrive_t", -1.0))])
		if JSON.stringify(pend_o) != JSON.stringify(pend_r):
			bad.append({"area": "comms.pending", "original": pend_o.slice(0, 5),
				"restored": pend_r.slice(0, 5)})
		var rep_r: Dictionary = restored.comms_restore_report()
		if int(rep_r.get("diverged", 0)) != 0:
			bad.append({"area": "comms.restore_report", "diverged":
				int(rep_r.get("diverged", 0))})
	return bad


## A00：故障注入——在**恢复会话**上制造真实状态篡改（不是直接调用 FAIL），
## 由正常比较器发现后使驱动非零退出。fault=2 → 等长集合 ID 替换；fault=3 → 在途 ETA 改写。
func _tamper_restored(fault: String, restored) -> Dictionary:
	var detail := {"fault": fault, "applied": []}
	if fault == "2":
		# 等长差异：删掉一个已用 ID 并加一个不存在的 ID（size 不变）
		var kids: Array = restored.bus._seen_ids.keys()
		if kids.size() >= 2:
			var drop := String(kids[0])
			restored.bus._seen_ids.erase(drop)
			restored.bus._seen_ids["evt-tampered-fault2"] = true
			detail["applied"].append("seen_ids equal-size replacement: -" + drop)
	elif fault == "3":
		# 在途消息 ETA 改写（内容差异，总数不变）
		if restored.comms != null and restored.comms.pending.size() > 0:
			var rec: Dictionary = restored.comms.pending[0]
			rec["arrive_t"] = float(rec.get("arrive_t", 0.0)) + 30.0
			detail["applied"].append("pending[0].arrive_t += 30")
	if (detail["applied"] as Array).is_empty():
		detail["note"] = "no tamper target at this scale; comparator must still pass"
	return detail


## A00：逐 tick 行为比较（≥10 tick）：事件 ID/seq、观测、通信投递、通道、时钟。
func _behavior_violations(original, restored, ticks: int) -> Array:
	var bad: Array = []
	for i in range(ticks):
		var oa: Dictionary = original.tick(TICK_DT)
		var rb: Dictionary = restored.tick(TICK_DT)
		if not bool(oa.get("ok", false)):
			bad.append({"tick": i, "area": "original.tick", "reason":
				String(oa.get("reason", ""))})
		if not bool(rb.get("ok", false)):
			bad.append({"tick": i, "area": "restored.tick", "reason":
				String(rb.get("reason", ""))})
		if int(original.bus.current_seq()) != int(restored.bus.current_seq()):
			bad.append({"tick": i, "area": "bus.seq",
				"original": int(original.bus.current_seq()),
				"restored": int(restored.bus.current_seq())})
		if absf(float(original.now_s()) - float(restored.now_s())) > TIME_TOL:
			bad.append({"tick": i, "area": "t_s"})
		if original.sensor_service != null and restored.sensor_service != null:
			if int(original.sensor_service._obs_seq) \
					!= int(restored.sensor_service._obs_seq):
				bad.append({"tick": i, "area": "sensor.obs_seq",
					"original": int(original.sensor_service._obs_seq),
					"restored": int(restored.sensor_service._obs_seq)})
			if int(original.sensor_service.observations.size()) \
					!= int(restored.sensor_service.observations.size()):
				bad.append({"tick": i, "area": "sensor.observations"})
		if original.comms != null and restored.comms != null:
			if int(original.comms.pending.size()) != int(restored.comms.pending.size()):
				bad.append({"tick": i, "area": "comms.pending"})
			var last_o: Dictionary = original.comms.last_event() \
				if original.comms.has_method("last_event") else {}
			var last_r: Dictionary = restored.comms.last_event() \
				if restored.comms.has_method("last_event") else {}
			if String(last_o.get("kind", "")) != String(last_r.get("kind", "")):
				bad.append({"tick": i, "area": "comms.last_event.kind",
					"original": String(last_o.get("kind", "")),
					"restored": String(last_r.get("kind", ""))})
	return bad


func _correctness(ticks: int, run_i: int, original, restored, lr: Dictionary) -> void:
	var label := "scale %d run %d" % [ticks, run_i]
	_ok(bool(lr.get("ok", false)), "%s: restored session loaded" % label)
	if not bool(lr.get("ok", false)):
		return
	# A00：故障注入改为**真实状态篡改**，由下面的正常比较器发现；
	# 不再用直接 _ok(false) 冒充故障发现能力。
	var fault := OS.get_environment("A07_FAULT_SAMPLE").strip_edges()
	if fault != "" and fault == str(run_i):
		var td: Dictionary = _tamper_restored(fault, restored)
		print("[A0-A07] FAULT INJECTED at ", label, " tamper=", JSON.stringify(td))
	# 1) 完整规范化状态比较（恢复时刻）
	var state_bad: Array = _full_state_violations(original, restored)
	_ok(state_bad.is_empty(), "%s: full normalized state matches after restore" % label,
		"violations=" + str(state_bad.slice(0, 6)))
	# 2) 至少 10 tick 的同输入行为比较（逐 tick）
	var behav_bad: Array = _behavior_violations(original, restored, CORRECTNESS_TICKS)
	_ok(behav_bad.is_empty(),
		"%s: %d continued ticks produce the same behaviour" % [label,
			CORRECTNESS_TICKS],
		"violations=" + str(behav_bad.slice(0, 6)))
	# 3) +10 tick 后再次完整比较（覆盖恢复后继续演化的状态）
	var state_after: Array = _full_state_violations(original, restored)
	_ok(state_after.is_empty(),
		"%s: full normalized state still matches after %d ticks" % [label,
			CORRECTNESS_TICKS],
		"violations=" + str(state_after.slice(0, 6)))
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
			"bytes_utf8_median": (r.get("bytes_utf8", {}) as Dictionary).get("median", -1),
			"bytes_utf8_min": (r.get("bytes_utf8", {}) as Dictionary).get("min", -1),
			"bytes_utf8_max": (r.get("bytes_utf8", {}) as Dictionary).get("max", -1),
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
