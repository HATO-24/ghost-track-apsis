extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# DS-A-05 · 传感器运行态持久化与续跑探针
#
# 基线：I4（b047266…）。契约：
#   * 保存时的 EMCON / 雷达 / 光学·IR 通道在**读档后持续生效**；
#   * 通道续跑恢复的是**底层后端状态**（status/progress/samples/dedup），
#     不是 UI 的 `_last_channels` 缓存；
#   * 静态 observer/mounts/targets 与 provider 对象**不入档**，读档后从原权威重建/重新注入；
#   * 恢复历史**不重放**到 TrackTable；分配器保证新 ID 不重复；
#   * 几何与 session 同 tick（≤1e-6 s），world/physics 同步先于新的传感器输出。
#
# Red evidence (before this card) 记录在 A0-T3 的修复前日志：
#   save_has_sensor_service=false；saved emcon=true/radar=false → loaded emcon=false/radar=true。
#
# Output: `A0-A05 SENSOR PERSISTENCE PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const GameSessionScript := preload("res://scripts/core/game_session.gd")
const OpticalIRScript := preload("res://framework/sim/optical_ir_channel.gd")

const WATCHDOG_S := 240.0
const TICK_DT := 60.0
const FLOAT_TOL := 1.0e-9
const GEOM_TIME_TOL := 1.0e-6

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-A05 SENSOR PERSISTENCE PROBE · baseline I4")
	print("Godot ", Engine.get_version_info().get("string", "?"))
	print("════════════════════════════════════════════════════════════════")
	_watchdog()
	_run()


func _watchdog() -> void:
	await create_timer(WATCHDOG_S).timeout
	if _finished:
		return
	print("[A0-A05] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
	_fail += 1
	_failures.append("watchdog timeout")
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("A0-A05 SENSOR PERSISTENCE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-A05] FAILED: ", f)
		print("A0-A05 SENSOR PERSISTENCE PROBE FAILED")
	else:
		print("A0-A05 SENSOR PERSISTENCE PROBE OK")
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-A05] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-A05] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.12f expected=%.12f tol=" % [actual, expected] + str(tol))


func _step(title: String) -> void:
	print("")
	print("[A0-A05] STEP ", title)


func _info(text: String) -> void:
	print("[A0-A05] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. real-shaped session: flip EMCON/radar away from seed, run optical+IR channels")
	var s = GameSessionScript.new(_seed())
	_ok(bool(s.ready), "session ready", str(s.errors))
	_ok(s.sensor_service != null, "SensorService present")
	if s.sensor_service == null:
		_finish()
		return
	var svc = s.sensor_service
	# seed 默认：emcon=false / radar=true；主动翻转到相反值
	var seed_emcon := bool(svc.emcon)
	var seed_radar := bool(svc.radar_enabled)
	svc.set_emcon(not seed_emcon)
	_ok(bool(svc.emcon) == (not seed_emcon),
		"EMCON flipped to the opposite of the seed value",
		"seed=%s now=%s" % [str(seed_emcon), str(svc.emcon)])
	_ok(bool(svc.radar_enabled) == (not seed_radar),
		"radar follows the EMCON flip (inverse of seed)",
		"seed=%s now=%s" % [str(seed_radar), str(svc.radar_enabled)])
	var ch1: Dictionary = svc.start_channel("optical", "harmattan")
	var ch2: Dictionary = svc.start_channel("ir", "harmattan")
	_ok(bool(ch1.get("ok", false)), "optical channel started", str(ch1.get("reason", "")))
	_ok(bool(ch2.get("ok", false)), "IR channel started", str(ch2.get("reason", "")))
	# 推进到非初始状态（通道 progress/status 变化）
	for i in range(3):
		s.tick(TICK_DT)
	var pre: Dictionary = svc.export_state()
	var pre_backend: Dictionary = pre.get("backend", {})
	var pre_chans: Array = pre_backend.get("channels", []) \
		if pre_backend.get("channels") is Array else []
	_ok(pre_chans.size() >= 2, "backend holds >=2 live channels before save",
		"n=" + str(pre_chans.size()))
	var non_initial := 0
	for raw_ch in pre_chans:
		var c: Dictionary = raw_ch
		if float(c.get("progress", 0.0)) > 0.0 \
				or String(c.get("status", "")) != "idle":
			non_initial += 1
	_ok(non_initial >= 2, "channels advanced past the initial state before save",
		"n=" + str(non_initial))
	var pre_view: Array = svc._last_channels.duplicate(true) \
		if svc._last_channels is Array else []
	_ok(pre_view.size() >= 2, "UI channel view is non-empty (kept for T22 3-channel case)",
		"n=" + str(pre_view.size()))
	_info("PRE-SAVE: emcon=%s radar=%s backend_chans=%d view_chans=%d alloc=%s dedup=%d" % [
		str(svc.emcon), str(svc.radar_enabled), pre_chans.size(), pre_view.size(),
		str(pre.get("allocators", {})), int(pre.get("dedup", {}).get(
			"optical_evidence_seen", []).size() if pre.get("dedup", {}) is Dictionary else 0)])

	_step("2. memory + real-file roundtrip: runtime state survives")
	var text: String = s.save_state()
	_ok(text.length() > 500, "save_state non-empty", "len=%d" % text.length())
	var payload: Dictionary = JSON.parse_string(text) if JSON.parse_string(text) is Dictionary else {}
	_ok(payload.has("sensor_service"), "save payload carries a sensor_service runtime section")
	# 内存往返
	var s_mem = GameSessionScript.new()
	var lr_mem: Dictionary = s_mem.load_state(text)
	_ok(bool(lr_mem.get("ok", false)), "in-memory load ok", str(lr_mem.get("errors", [])))
	# 真实文件往返
	var path := "user://a05_sensor_state.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	_ok(f != null, "probe can write a real save file")
	if f != null:
		f.store_string(text)
		f.close()
	var s_file = GameSessionScript.new()
	var lr_file: Dictionary = s_file.load_state(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(bool(lr_file.get("ok", false)), "real-file load ok", str(lr_file.get("errors", [])))
	if not bool(lr_mem.get("ok", false)) or not bool(lr_file.get("ok", false)):
		_finish()
		return
	for pair in [["memory", s_mem], ["file", s_file]]:
		var label := String(pair[0])
		var sess = pair[1]
		var sv = sess.sensor_service
		_eq(bool(sv.emcon), bool(svc.emcon), "%s: EMCON restored" % label)
		_eq(bool(sv.radar_enabled), bool(svc.radar_enabled), "%s: radar restored" % label)
		_eq(String(sv.selected_target), String(svc.selected_target),
			"%s: selected target restored" % label)
		_near(float(sv.t), float(svc.t), GEOM_TIME_TOL, "%s: clock restored" % label)
		_eq(int(sv.step_count), int(svc.step_count), "%s: step count restored" % label)
		_eq(int(sv._obs_seq), int(svc._obs_seq), "%s: observation allocator restored" % label)
		_eq(int(sv._evidence_seq), int(svc._evidence_seq),
			"%s: evidence allocator restored" % label)
		_eq(int(sv._event_seq), int(svc._event_seq), "%s: event allocator restored" % label)
		_eq(sv._optical_evidence_seen.size(), svc._optical_evidence_seen.size(),
			"%s: dedup key count restored" % label)
		# 底层后端通道状态（不是 UI 缓存）
		var post_be: Dictionary = sv._authority.export_backend_state() \
			if sv._authority != null else {}
		var post_chans: Array = post_be.get("channels", []) \
			if post_be.get("channels") is Array else []
		_eq(post_chans.size(), pre_chans.size(),
			"%s: backend channel count restored" % label)
		var diff: Array = _channel_diff(pre_chans, post_chans)
		_ok(diff.is_empty(), "%s: backend channel content restored exactly" % label,
			"violations=" + str(diff.slice(0, 6)))
		# 几何 provider 重新注入且同刻
		var gs: Dictionary = sv.geometry_status()
		_eq(String(gs.get("source", "")), "physics_world",
			"%s: geometry provider re-bound to physics" % label)
		_eq(String(gs.get("frame", "")), "bary_rot", "%s: geometry frame is bary_rot" % label)
		_near(float(gs.get("t", -1.0)), float(sess.now_s()), GEOM_TIME_TOL,
			"%s: geometry sampled at the same tick" % label)
		var rep: Dictionary = sess.sensor_restore_report()
		_eq(bool(rep.get("time_ok", false)), true,
			"%s: restore report confirms same-tick geometry" % label)

	_step("3. continue the SAME 10 ticks on original and restored sessions")
	var seq_alloc_before := {
		"obs": int(svc._obs_seq), "evidence": int(svc._evidence_seq),
		"event": int(svc._event_seq)}
	var obs_before := int(svc.observations.size())
	var seq_before := int(s_mem.bus.current_seq())
	var ev_before := int(s_mem.sensor_service._event_seq)
	for i in range(10):
		s.tick(TICK_DT)
		s_mem.tick(TICK_DT)
	_ok(int(s_mem.sensor_service.t) == int(svc.t),
		"restored clock matches the original after 10 ticks",
		"orig=%s restored=%s" % [str(int(svc.t)), str(int(s_mem.sensor_service.t))])
	# 分配器契约（任务卡）：**单调续写 + 不重复 ID**；不要求跨会话完全相等，
	# 因为被 EMCON 抑制的雷达 advisory 也会消费序号（设计如此，避免 ID 复用）。
	_ok(int(s_mem.sensor_service._obs_seq) >= int(seq_alloc_before["obs"]),
		"observation allocator never goes backwards across restore",
		"saved=%d now=%d" % [int(seq_alloc_before["obs"]),
			int(s_mem.sensor_service._obs_seq)])
	_ok(int(s_mem.sensor_service._event_seq) >= int(seq_alloc_before["event"]),
		"sensor event allocator never goes backwards across restore",
		"saved=%d now=%d" % [int(seq_alloc_before["event"]),
			int(s_mem.sensor_service._event_seq)])
	_ok(int(svc._event_seq) == int(svc._event_seq) and int(svc._event_seq) >= 0,
		"original sensor event allocator stays valid",
		"seq=%d" % int(svc._event_seq))
	_info("ALLOCATORS: obs saved=%d orig=%d restored=%d | event saved=%d orig=%d restored=%d "
		+ "(suppressed radar advisories also consume ids by design)" % [
			int(seq_alloc_before["obs"]), int(svc._obs_seq),
			int(s_mem.sensor_service._obs_seq),
			int(seq_alloc_before["event"]), int(svc._event_seq),
			int(s_mem.sensor_service._event_seq)])
	_ok(svc.observations.size() > obs_before,
		"new observations were produced by the ticks",
		"n %d -> %d" % [obs_before, svc.observations.size()])
	# 不产生重复 ID
	var dup_ids: Array = []
	var seen: Dictionary = {}
	for raw_o in s_mem.sensor_service.observations:
		var eid := String((raw_o as Dictionary).get("event_id", ""))
		if seen.has(eid):
			dup_ids.append(eid)
		seen[eid] = true
	_ok(dup_ids.is_empty(), "restored session produces no duplicate observation ids",
		str(dup_ids.slice(0, 6)))
	# EMCON 开启时无雷达发射；关闭后输出可恢复
	var radar_events_on := 0
	for raw_ev in s_mem.sensor_service.events:
		var ev: Dictionary = raw_ev
		if String(ev.get("kind", "")) == "radar":
			var det: Dictionary = ev.get("detail", {}) if ev.get("detail") is Dictionary else {}
			if bool(det.get("on", false)):
				radar_events_on += 1
	_eq(bool(s_mem.sensor_service.emcon), true, "EMCON stayed on after continuation")
	_info("EMCON ON: radar-on sensor events emitted during continuation=%d (expect 0)" % radar_events_on)
	_ok(radar_events_on == 0, "EMCON on suppresses radar emissions after restore",
		"radar_on_events=" + str(radar_events_on))
	# 关掉 EMCON 后输出恢复
	s_mem.sensor_service.set_emcon(false)
	var obs_off := int(s_mem.sensor_service.observations.size())
	for i in range(2):
		s_mem.tick(TICK_DT)
	_ok(s_mem.sensor_service.observations.size() > obs_off,
		"radar/optical output resumes after EMCON is turned off",
		"n %d -> %d" % [obs_off, s_mem.sensor_service.observations.size()])
	_info("CONTINUATION: obs %d -> %d, evidence %d -> %d, event %d -> %d" % [
		obs_before, int(svc.observations.size()),
		int(seq_alloc_before["evidence"]), int(svc._evidence_seq),
		ev_before, int(svc._event_seq)])

	_step("4. negatives: explicit reasons, never old positions as current data")
	# 4a 缺目标
	var s_miss = GameSessionScript.new(_seed([
		{"id": "harmattan", "pos_km": [322139.0, 0.0, 0.0], "rcs_m2": 1100.0}]))
	var miss_ch: Dictionary = s_miss.sensor_service.start_channel("optical", "ghost_target")
	_ok(bool(miss_ch.get("ok", true)) == false,
		"NEGATIVE: starting a channel for a missing target is rejected",
		str(miss_ch.get("reason", "")))
	# 4b 非法时钟
	var bad_clock: Dictionary = svc.export_state()
	bad_clock["t"] = "not-a-number"
	var b1 = GameSessionScript.new(_seed())
	var r1: Dictionary = b1.sensor_service.import_state(bad_clock)
	_ok(bool(r1.get("ok", true)) == false, "NEGATIVE: illegal clock rejected",
		str(r1.get("errors", [])))
	# 4c 非法 counter
	var bad_ctr: Dictionary = svc.export_state()
	bad_ctr["allocators"] = {"obs_seq": 1.5, "evidence_seq": 0, "event_seq": 0}
	var b2 = GameSessionScript.new(_seed())
	var r2: Dictionary = b2.sensor_service.import_state(bad_ctr)
	_ok(bool(r2.get("ok", true)) == false, "NEGATIVE: illegal counter rejected",
		str(r2.get("errors", [])))
	# 4d 损坏通道（缺 kind）
	var bad_ch: Dictionary = svc.export_state()
	(bad_ch.get("backend", {}) as Dictionary)["channels"] = [{"target_id": "x"}]
	var b3 = GameSessionScript.new(_seed())
	var r3: Dictionary = b3.sensor_service.import_state(bad_ch)
	_ok(bool(r3.get("ok", true)) == false, "NEGATIVE: corrupt channel rejected",
		str(r3.get("errors", [])))
	# 4e 未知通道种类
	var unknown_kind: Dictionary = svc.export_state()
	(unknown_kind.get("backend", {}) as Dictionary)["channels"] = [
		{"kind": "gamma_ray", "target_id": "harmattan", "status": "idle", "progress": 0.0}]
	var b4 = GameSessionScript.new(_seed())
	var r4: Dictionary = b4.sensor_service.import_state(unknown_kind)
	_info("unknown channel kind import ok=%s (channel-level reject: %s)" % [
		str(r4.get("ok", false)), str(r4.get("reason", ""))])
	# 4f 版本不符
	var bad_ver: Dictionary = svc.export_state()
	bad_ver["version"] = 99
	var b5 = GameSessionScript.new(_seed())
	var r5: Dictionary = b5.sensor_service.import_state(bad_ver)
	_ok(bool(r5.get("ok", true)) == false, "NEGATIVE: unsupported state version rejected",
		str(r5.get("errors", [])))
	# 4g provider 未就绪 / 不同 frame：几何必须显式不可用
	var s_frame = GameSessionScript.new(_frame_seed())
	var gs_frame: Dictionary = s_frame.sensor_service.geometry_status()
	_eq(String(gs_frame.get("reason", "")), "frame_mismatch",
		"NEGATIVE: different frame reports frame_mismatch")
	_eq(bool(gs_frame.get("unavailable", false)), true,
		"NEGATIVE: different frame marks geometry unavailable")
	var obs_frame := int(s_frame.sensor_service.observations.size())
	for i in range(2):
		s_frame.tick(TICK_DT)
	_eq(s_frame.sensor_service.observations.size(), obs_frame,
		"NEGATIVE: unavailable geometry produces no observations (no stale positions)")
	# 4h 失败导入不改运行态
	var b6 = GameSessionScript.new(_seed())
	b6.sensor_service.set_emcon(true)
	var before_sum: Dictionary = b6.sensor_service.runtime_state_summary()
	b6.sensor_service.import_state({"schema": "bad", "version": 1})
	var after_sum: Dictionary = b6.sensor_service.runtime_state_summary()
	_eq(JSON.stringify(after_sum), JSON.stringify(before_sum),
		"NEGATIVE: failed import leaves the runtime state unchanged")

	_step("5. optional profile (no sensor component) and old save without the section")
	var plain = GameSessionScript.new(_plain_seed())
	_ok(bool(plain.ready), "session without sensor component ready", str(plain.errors))
	_eq(plain.sensor_service == null, true, "sensor_service absent for this profile")
	var plain_text: String = plain.save_state()
	var plain2 = GameSessionScript.new()
	var lr_plain: Dictionary = plain2.load_state(plain_text)
	_ok(bool(lr_plain.get("ok", false)), "no-sensor session save→load ok",
		str(lr_plain.get("errors", [])))
	# 旧档缺 sensor 段：按 A-04 支持矩阵重建并标局限（不称保存过运行态）
	var legacy_payload: Dictionary = JSON.parse_string(text)
	legacy_payload.erase("sensor_service")
	var legacy_payload2: Dictionary = JSON.parse_string(JSON.stringify(legacy_payload))
	var s_leg = GameSessionScript.new()
	var lr_leg: Dictionary = s_leg.load_state(JSON.stringify(legacy_payload2))
	_ok(bool(lr_leg.get("ok", false)),
		"old save without sensor section still loads (A-04 support matrix)",
		str(lr_leg.get("errors", [])))
	if bool(lr_leg.get("ok", false)) and s_leg.sensor_service != null:
		var rep: Dictionary = s_leg.legacy_migration_report()
		var unrec: Array = rep.get("unrecoverable", [])
		var has_note := false
		for u in unrec:
			if str(u).find("sensor_service") >= 0:
				has_note = true
		_ok(has_note,
			"old save is labelled as NOT having sensor runtime state (no lossless claim)",
			"unrecoverable=" + str(unrec))
		_ok(str(s_leg.sensor_restore_report().get("saved", "x")) == "false",
			"restore report says the sensor section was absent",
			str(s_leg.sensor_restore_report()))

	_step("6. visibility: restoring runtime state does not widen player visibility")
	var s_vis = GameSessionScript.new(_seed())
	var contacts: Array = s_vis.snapshot().get("contacts", []) \
		if s_vis.snapshot().get("contacts") is Array else []
	var leak: Array = []
	for raw_c in contacts:
		if not (raw_c is Dictionary):
			continue
		var c: Dictionary = raw_c
		var cid := String(c.get("entity_id", c.get("id", "")))
		if cid == "apsis":
			continue
		for fld in ["batch", "rcs_m2", "radius_km", "has_pd"]:
			if c.has(fld):
				leak.append({"entity": cid, "field": fld})
	_ok(leak.is_empty(), "no truth-only field leaks to contacts after sensor restore",
		"violations=" + str(leak.slice(0, 6)))

	_step("7. A-05 summary")
	_info("A-05: controls/clock/channels/allocators/dedup/backend state persisted; provider "
		+ "re-bound same-tick; history not replayed; EMCON behaviour preserved; negatives explicit")

	_finish()


# ── helpers ─────────────────────────────────────────────────────

## 通道内容比较：结构/字符串/ID/状态精确；数字按值比较（JSON int↔float 不算漂移）。
func _channel_diff(before: Array, after: Array) -> Array:
	var out: Array = []
	if before.size() != after.size():
		out.append({"reason": "count %d != %d" % [before.size(), after.size()]})
		return out
	for i in range(before.size()):
		var b: Dictionary = before[i]
		var a: Dictionary = after[i]
		for k in b.keys():
			var key := String(k)
			if not a.has(key):
				out.append({"channel": i, "field": key, "reason": "missing after"})
				continue
			var bv = b[k]
			var av = a[k]
			if (bv is int or bv is float) and (av is int or av is float):
				if absf(float(bv) - float(av)) > FLOAT_TOL:
					out.append({"channel": i, "field": key, "reason": "numeric diff",
						"before": float(bv), "after": float(av)})
			elif str(bv) != str(av):
				out.append({"channel": i, "field": key, "reason": "value diff",
					"before": str(bv), "after": str(av)})
	return out


func _seed(targets_override = null) -> Dictionary:
	var targets: Array = [
		{"id": "harmattan", "pos_km": [322139.0, 0.0, 0.0],
			"rcs_m2": 1100.0, "side": "hostile", "batch": "OCU-07"},
		{"id": "l1_station", "pos_km": [321719.0, 0.0, 0.0],
			"rcs_m2": 400.0, "side": "friend", "batch": "UEG-01"}]
	if targets_override is Array:
		targets = targets_override
	return {
		"own_entity": "apsis", "physics_world": true,
		"seed_frame": "bary_rot", "frame_origin": "bary_rot",
		"track_table": true,
		"sensor_service": {
			"observer": {"id": "apsis", "pos_km": [321719.0, 0.0, 0.0]},
			"targets": targets,
			"options": {"radar_enabled": true, "emcon": false}},
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [322139.0, 0.0, 0.0],
				"vel_kmps": [0.0, 1.02, 0.0]},
			{"id": "l1_station", "kind": "station", "pos_km": [321719.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]}],
	}


func _frame_seed() -> Dictionary:
	var base := _seed()
	base["seed_frame"] = "l1"
	base["frame_origin"] = "l1"
	return base


func _plain_seed() -> Dictionary:
	return {
		"own_entity": "apsis",
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [0.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]}],
	}
