extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# DS-A-06 · 真实 HUD 会话的通信读档恢复探针
#
# 基线：I5（0a66ea2…）。核心缺陷（修复前）：
#   `send_comms()` 在**发送前**记录操作，且不带 outcome；读档重放时任何 `ok=false`
#   都被当成恢复错误 → 原本就失败的 LR 发送（orbital_sim 全部 links 为 LD → no_route）
#   被误报为 `replay send_comms 失败：no_route`。
#
# 修复语义（本卡）：
#   * 操作记录带**版本化 outcome**（ok/reason/mode/delivery_id/path/latency/relay/arrive_t/sent_t）；
#   * 重放后逐项核对；**原始失败必须仍是同一失败**（not a recovery error）；
#   * 原始成功但重放失败、或原因/ID/路径/延迟不一致 → `comms_replay_diverged` 明确拒绝；
#   * 旧日志无 outcome → 按 A-04 版本规则显式标 `legacy_unverified`，不静默忽略。
#
# 入口：main_menu → v1_hud → ShellBinder → GameSession（DSH_BUILD=orbital_sim）。
# Output: `A0-A06 COMMS RESTORE PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const TARGET_PROFILE := "orbital_sim"
const MAIN_MENU := "res://main_menu.tscn"
const V1_HUD := "res://v1_hud.tscn"
const HUD_SCRIPT := "res://scripts/ui/v1_hud.gd"
const HUD_NODE := "V1HUD"
const GameSessionScript := preload("res://scripts/core/game_session.gd")
const SaveServiceScript := preload("res://scripts/core/save_service.gd")

const MAX_BOOT_FRAMES := 600
const MAX_BOOT_MS := 60000
const MAX_BINDER_FRAMES := 120
const WATCHDOG_S := 240.0
const TICK_DT := 60.0
const TIME_TOL := 1.0e-6
const ENV_KEYS := ["DSH_BUILD", "DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE",
	"DSH_V1_TEST", "DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
	"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _env_backup: Dictionary = {}
var _finished := false
var _main_menu_instantiated := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-A06 COMMS RESTORE PROBE · baseline I5")
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
	print("[A0-A06] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
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
	print("────────────────────────────────────────────────────────────────")
	print("A0-A06 COMMS RESTORE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-A06] FAILED: ", f)
		print("A0-A06 COMMS RESTORE PROBE FAILED")
	else:
		print("A0-A06 COMMS RESTORE PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-A06] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-A06] FAIL ", line)


func _eq(actual, expected, label: String, detail := "") -> void:
	_ok(actual == expected, label,
		("actual=%s expected=%s" % [str(actual), str(expected)])
		+ (("  " + detail) if detail != "" else ""))


func _near(actual: float, expected: float, tol: float, label: String) -> void:
	_ok(absf(actual - expected) <= tol, label,
		"actual=%.12f expected=%.12f tol=" % [actual, expected] + str(tol))


func _step(title: String) -> void:
	print("")
	print("[A0-A06] STEP ", title)


func _info(text: String) -> void:
	print("[A0-A06] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. real entry main_menu → v1_hud (orbital_sim), capture startup comms")
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
	_ok(binder != null and bool(binder.get("ready")), "ShellBinder ready")
	_ok(session != null, "GameSession available")
	if session == null:
		_finish()
		return
	_ok(session.comms != null, "CommsService present")
	# 启动通信（HUD 的 _seed_comms_sample 已发 LD/LR）
	var ops: Array = _comms_ops(session)
	_ok(ops.size() > 0, "session recorded comms operations at startup",
		"n=" + str(ops.size()))
	var orig_rows: Array = []
	for raw in ops:
		var op: Dictionary = raw
		var ro = op.get("outcome", null)
		_ok(ro is Dictionary, "comms op carries a versioned outcome record",
			String(op.get("mode", "")))
		if ro is Dictionary:
			orig_rows.append({
				"mode": String(op.get("mode", "")),
				"from": String(op.get("from_id", "")),
				"to": String(op.get("to_id", "")),
				"ok": bool((ro as Dictionary).get("ok", false)),
				"reason": String((ro as Dictionary).get("reason", "")),
				"delivery_id": String((ro as Dictionary).get("delivery_id", "")),
				"latency_s": float((ro as Dictionary).get("latency_s", 0.0)),
			})
	var expected_failures := 0
	for r in orig_rows:
		if not bool(r["ok"]):
			expected_failures += 1
	_eq(orig_rows.size(), ops.size(), "every comms op has an outcome")
	_info("STARTUP COMMS: %s" % JSON.stringify(orig_rows))
	_info("STARTUP: expected_failure_ops=%d / total=%d" % [expected_failures, ops.size()])
	# 路由拓扑
	var nodes_n := int(session.comms.nodes.size())
	var links_n := int(session.comms.links.size())
	_ok(nodes_n > 1, "comms topology has nodes", "nodes=%d links=%d" % [nodes_n, links_n])
	var topo := {"nodes": nodes_n, "links": links_n}
	for raw_l in session.comms.links:
		var l: Dictionary = raw_l
		topo["link_%s_%s" % [String(l.get("a", "")), String(l.get("mode", ""))]] = true
	_info("TOPOLOGY: " + JSON.stringify(topo))

	_step("2. real SaveService file roundtrip; compare original vs replayed outcomes")
	var dir := "user://a06_probe_saves"
	var ss = SaveServiceScript.new(dir)
	_ok(bool(ss.ready), "SaveService ready", str(ss.errors))
	var save_res: Dictionary = ss.save_session(session, "save", {"chapter": "probe"})
	_ok(bool(save_res.get("ok", false)), "SaveService.save_session ok",
		str(save_res.get("errors", [])))
	var load_res: Dictionary = ss.load_session("save")
	_ok(bool(load_res.get("ok", false)), "SaveService.load_session ok (real file)",
		str(load_res.get("errors", [])))
	ss.delete_slot("save")
	if not bool(load_res.get("ok", false)):
		_finish()
		return
	var restored = load_res.get("session")
	_ok(restored != null, "loaded session object present")
	if restored == null:
		_finish()
		return
	var rep: Dictionary = restored.comms_restore_report()
	_eq(int(rep.get("diverged", -1)), 0, "no comms replay divergence on the real HUD save")
	_eq(int(rep.get("total", -1)), ops.size(),
		"every recorded comms op was replayed and checked",
		"total=%d ops=%d" % [int(rep.get("total", -1)), ops.size()])
	_eq(int(rep.get("legacy_unverified", -1)), 0,
		"no legacy-unverified comms ops (the save carries outcomes)")
	_eq(int(rep.get("matched_expected_failure", -1)), expected_failures,
		"originally failing sends are preserved AS FAILURES (not recovery errors)",
		"expected=%d report=%d" % [expected_failures,
			int(rep.get("matched_expected_failure", -1))])
	# 逐项对照：mode/from/to/ok/reason/delivery_id/latency
	var row_diff: Array = []
	var rows: Array = rep.get("ops", []) if rep.get("ops") is Array else []
	for i in range(mini(rows.size(), orig_rows.size())):
		var row: Dictionary = rows[i]
		var orig: Dictionary = orig_rows[i]
		var rec: Dictionary = row.get("recorded", {}) if row.get("recorded") is Dictionary else {}
		if String(row.get("mode", "")) != String(orig["mode"]):
			row_diff.append({"i": i, "field": "mode"})
		if String(row.get("from", "")) != String(orig["from"]):
			row_diff.append({"i": i, "field": "from"})
		if String(row.get("to", "")) != String(orig["to"]):
			row_diff.append({"i": i, "field": "to"})
		if bool(rec.get("ok", not orig["ok"])) != bool(orig["ok"]):
			row_diff.append({"i": i, "field": "ok"})
		if String(rec.get("reason", "")) != String(orig["reason"]):
			row_diff.append({"i": i, "field": "reason"})
		if String(rec.get("delivery_id", "")) != String(orig["delivery_id"]):
			row_diff.append({"i": i, "field": "delivery_id"})
		if absf(float(rec.get("latency_s", 0.0)) - float(orig["latency_s"])) > TIME_TOL:
			row_diff.append({"i": i, "field": "latency_s"})
	_ok(row_diff.is_empty(),
		"per-op comparison matches on mode/from/to/ok/reason/delivery_id/latency",
		"violations=" + str(row_diff.slice(0, 8)))
	_info("RESTORE REPORT: " + JSON.stringify({
		"total": rep.get("total", 0), "matched_success": rep.get("matched_success", 0),
		"matched_expected_failure": rep.get("matched_expected_failure", 0),
		"legacy_unverified": rep.get("legacy_unverified", 0),
		"diverged": rep.get("diverged", 0)}))
	# 原先失败的发送读档后仍显示为失败事件
	var failed_events_before := _count_bus_events(session, "comms.failed")
	var failed_events_after := _count_bus_events(restored, "comms.failed")
	_eq(failed_events_after, failed_events_before,
		"restored session keeps the same number of comms.failed events",
		"before=%d after=%d" % [failed_events_before, failed_events_after])

	_step("3. fixture: LD direct + relay + queued + immediate delivery, continue ticks")
	var fx = GameSessionScript.new(_fixture_seed())
	_ok(bool(fx.ready), "fixture comms session ready", str(fx.errors))
	if not bool(fx.ready):
		_finish()
		return
	var ld: Dictionary = fx.send_comms("apsis", "harmattan", "LD", "COMMS_SENT", {}, {})
	_ok(bool(ld.get("ok", false)), "LD direct send ok", str(ld.get("reason", "")))
	var relay: Dictionary = fx.send_comms("apsis", "relay1", "LR", "COMMS_SENT", {}, {})
	_ok(bool(relay.get("ok", false)), "LR relay send ok", str(relay.get("reason", "")))
	var queued: Dictionary = fx.send_comms("apsis", "harmattan", "LD", "COMMS_SENT", {},
		{"delivery_delay_s": 600.0})
	_ok(bool(queued.get("ok", false)), "queued (delayed) send accepted",
		str(queued.get("reason", "")))
	var sent_ids: Array = []
	for r in [ld, relay, queued]:
		if bool(r.get("ok", false)):
			sent_ids.append(String(r.get("delivery_id", "")))
	_info("FIXTURE SENDS: ids=%s arrivals=%s" % [str(sent_ids),
		str([ld.get("arrive_t", -1.0), relay.get("arrive_t", -1.0),
			queued.get("arrive_t", -1.0)])])
	var fx_text: String = fx.save_state()
	var fx2 = GameSessionScript.new()
	var fx_lr: Dictionary = fx2.load_state(fx_text)
	_ok(bool(fx_lr.get("ok", false)), "fixture load ok", str(fx_lr.get("errors", [])))
	if not bool(fx_lr.get("ok", false)):
		_finish()
		return
	var fx_rep: Dictionary = fx2.comms_restore_report()
	_eq(int(fx_rep.get("diverged", -1)), 0, "fixture: no comms divergence")
	_eq(int(fx_rep.get("matched_success", -1)), 3,
		"fixture: all three successful sends matched")
	# 继续 20 ticks，比较投递（恰好一次、顺序、接收者、时间）
	var delivered_orig: Array = []
	var delivered_rest: Array = []
	for i in range(20):
		fx.tick(TICK_DT)
		fx2.tick(TICK_DT)
	delivered_orig = _delivered(fx)
	delivered_rest = _delivered(fx2)
	_eq(JSON.stringify(delivered_rest), JSON.stringify(delivered_orig),
		"restored session delivers exactly the same messages (id/receiver/order)",
		"%d vs %d" % [delivered_rest.size(), delivered_orig.size()])
	var dup_deliveries: Array = []
	var seen_d: Dictionary = {}
	for raw in delivered_rest:
		var k := JSON.stringify(raw)
		if seen_d.has(k):
			dup_deliveries.append(k)
		seen_d[k] = true
	_ok(dup_deliveries.is_empty(), "no duplicate delivery after restore",
		str(dup_deliveries.slice(0, 4)))
	_ok(delivered_rest.size() >= 2, "restored session actually delivered messages",
		"n=" + str(delivered_rest.size()))
	# 残余延迟一致
	var pend_orig: int = int(fx.comms.pending.size())
	var pend_rest: int = int(fx2.comms.pending.size())
	_ok(pend_rest == pend_orig, "pending queue length matches after continuation",
		"orig=%d rest=%d" % [pend_orig, pend_rest])

	_step("4. negatives: original failure preserved, divergence detected, legacy labelled")
	# 4a 原始 no_route 失败必须保留为失败（不是读档错误）
	var nf = GameSessionScript.new(_fixture_seed())
	var bad: Dictionary = nf.send_comms("apsis", "isolated", "LR", "COMMS_SENT", {}, {})
	_eq(bool(bad.get("ok", true)), false, "LR with no LR link fails originally (no_route)")
	_eq(String(bad.get("reason", "")), "no_route", "original failure reason is no_route")
	var nf_text: String = nf.save_state()
	var nf2 = GameSessionScript.new()
	var nf_lr: Dictionary = nf2.load_state(nf_text)
	_ok(bool(nf_lr.get("ok", false)),
		"load succeeds even though an operation originally failed",
		str(nf_lr.get("errors", [])))
	var nf_rep: Dictionary = nf2.comms_restore_report()
	_eq(int(nf_rep.get("matched_expected_failure", -1)), 1,
		"the original no_route failure is preserved as an expected failure")
	_eq(int(nf_rep.get("diverged", -1)), 0, "preserved failure is not a divergence")
	_eq(_count_bus_events(nf2, "comms.failed"),
		_count_bus_events(nf, "comms.failed"),
		"restored session still shows the comms.failed event")
	# 4b 成功路径被移除 → 明确检测为分歧（加载失败）
	var div_payload: Dictionary = JSON.parse_string(nf_text)
	var div_log: Array = div_payload.get("log", [])
	# 先造一个成功发送，然后把链路禁用后再读
	var ok_sess = GameSessionScript.new(_fixture_seed())
	ok_sess.send_comms("apsis", "relay1", "LR", "COMMS_SENT", {}, {})
	var ok_text: String = ok_sess.save_state()
	var ok_payload: Dictionary = JSON.parse_string(ok_text)
	var tampered: Dictionary = ok_payload.duplicate(true)
	var tlog: Array = tampered.get("log", [])
	for raw_op in tlog:
		if raw_op is Dictionary and String((raw_op as Dictionary).get("op", "")) == "send_comms":
			var ro: Dictionary = (raw_op as Dictionary).get("outcome", {})
			# 篡改成「原始失败」，而重放会成功 → 必须检测为不一致
			ro["ok"] = false
			ro["reason"] = "no_route"
			(raw_op as Dictionary)["outcome"] = ro
			break
	var tampered_sess = GameSessionScript.new()
	var tampered_lr: Dictionary = tampered_sess.load_state(JSON.stringify(tampered))
	_ok(bool(tampered_lr.get("ok", true)) == false,
		"NEGATIVE: a tampered recorded outcome is detected as divergence (load fails)",
		str(tampered_lr.get("reason", "")))
	var tampered_reasons: Array = []
	for e in (tampered_lr.get("errors", []) as Array):
		tampered_reasons.append(String(e))
	_ok(JSON.stringify(tampered_reasons).find("comms_replay_diverged") >= 0,
		"NEGATIVE: divergence reports the exact reason", str(tampered_reasons))
	# 4c 未知 mode / 错误 target 原始失败也保留
	var nm = GameSessionScript.new(_fixture_seed())
	var nm1: Dictionary = nm.send_comms("apsis", "harmattan", "QQ", "COMMS_SENT", {}, {})
	_eq(String(nm1.get("reason", "")), "invalid_mode", "unknown mode fails with invalid_mode")
	var nm2: Dictionary = nm.send_comms("apsis", "ghost", "LD", "COMMS_SENT", {}, {})
	_eq(String(nm2.get("reason", "")), "unknown_to", "wrong target fails with unknown_to")
	var nm_text: String = nm.save_state()
	var nm3 = GameSessionScript.new()
	var nm_lr: Dictionary = nm3.load_state(nm_text)
	_ok(bool(nm_lr.get("ok", false)), "invalid-mode/unknown-target failures load cleanly",
		str(nm_lr.get("errors", [])))
	_eq(int(nm3.comms_restore_report().get("matched_expected_failure", -1)), 2,
		"both invalid sends preserved as expected failures")
	# 4d 旧日志无 outcome → legacy_unverified 显式标注（不静默忽略）
	var legacy: Dictionary = ok_payload.duplicate(true)
	var llog: Array = legacy.get("log", [])
	for raw_op2 in llog:
		if raw_op2 is Dictionary and String((raw_op2 as Dictionary).get("op", "")) == "send_comms":
			(raw_op2 as Dictionary).erase("outcome")
	var legacy_sess = GameSessionScript.new()
	var legacy_lr: Dictionary = legacy_sess.load_state(JSON.stringify(legacy))
	_ok(bool(legacy_lr.get("ok", false)), "legacy log without outcome still loads",
		str(legacy_lr.get("errors", [])))
	var lrep: Dictionary = legacy_sess.comms_restore_report()
	_eq(int(lrep.get("legacy_unverified", -1)), 1,
		"legacy comms op is explicitly reported as unverified")
	_eq(int(lrep.get("diverged", -1)), 0, "legacy unverified is not counted as divergence")

	_step("5. A-06 summary")
	_info("A-06: outcomes versioned; expected failures preserved; divergences rejected; "
		+ "queued/delivered/relay/LD restore + exactly-once delivery; legacy labelled")

	_finish()


# ── helpers ─────────────────────────────────────────────────────

func _comms_ops(session) -> Array:
	var out: Array = []
	if session == null:
		return out
	for raw in session._log:
		if raw is Dictionary and String((raw as Dictionary).get("op", "")) == "send_comms":
			out.append(raw)
	return out


func _count_bus_events(session, etype: String) -> int:
	var n := 0
	if session == null or session.bus == null:
		return 0
	for raw in session.bus.events:
		if raw is Dictionary and String((raw as Dictionary).get("type", "")) == etype:
			n += 1
	return n


## 已投递消息从 CommsService 事件流读取（kind=DELIVERED），保持投递顺序。
func _delivered(session) -> Array:
	var out: Array = []
	if session == null or session.comms == null:
		return out
	for raw in session.comms.events:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		if String(ev.get("kind", "")) != "DELIVERED":
			continue
		out.append({
			"delivery_id": String(ev.get("delivery_id", "")),
			"from": String(ev.get("from", "")),
			"to": String(ev.get("to", "")),
			"mode": String(ev.get("mode", "")),
			"arrive_t": float(ev.get("arrive_t", -1.0)),
		})
	return out


func _fixture_seed() -> Dictionary:
	return {
		"own_entity": "apsis",
		"writer": "session",
		"nodes": [
			{"id": "apsis", "name": "APIS", "role": "own"},
			{"id": "relay1", "name": "R1", "role": "relay"},
			{"id": "harmattan", "name": "HM", "role": "target"},
			{"id": "isolated", "name": "ISO", "role": "target"}],
		"links": [
			{"a": "apsis", "b": "harmattan", "mode": "LD", "latency_s": 4.0},
			{"a": "apsis", "b": "relay1", "mode": "LR", "latency_s": 8.0},
			{"a": "relay1", "b": "harmattan", "mode": "LR", "latency_s": 6.0}],
		"entities": [
			{"id": "apsis", "kind": "ship", "pos_km": [0.0, 0.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]},
			{"id": "harmattan", "kind": "ship", "pos_km": [3.0, 4.0, 0.0],
				"vel_kmps": [0.0, 0.0, 0.0]}],
	}


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
		var scr = hud.get_script()
		var script_path := ""
		if scr != null:
			script_path = String(scr.resource_path)
		return {"hud": hud, "frames": frames,
			"saw_main_menu": saw_main_menu or _main_menu_instantiated,
			"scene_script_ok": script_path == HUD_SCRIPT and String(hud.name) == HUD_NODE}
	print("[A0-A06] FAIL entry timeout waiting for v1_hud")
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames}
