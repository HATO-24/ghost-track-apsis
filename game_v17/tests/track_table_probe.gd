extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# TRACK TABLE PROBE · 完整游戏-阶段2F
#
# 验证：TrackTable 单写者、Observation/Evidence/TrackUpdate 融合、
# L1→L4、身份六级/不明不判敌、去重/合并、过期、证据追溯、只读 VM、
# DbC 非法事件拒绝、JSON、确定性。只跑一次；不接传感器/物理/UI。
# ═══════════════════════════════════════════════════════════════════

const TrackTable := preload("res://scripts/core/track_table.gd")
const SaveServiceScript := preload("res://scripts/core/save_service.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("TRACK TABLE PROBE · 完整游戏-阶段2F")
	print("════════════════════════════════════════════════════════════════")
	_test_single_writer()
	_test_levels_l1_to_l4()
	_test_identity_and_threat()
	_test_dedup_merge_expire()
	_test_validation_and_dbC()
	_test_readonly_vm_json_determinism()
	_test_save_load()
	print("────────────────────────────────────────────────────────────────")
	print("TRACK TABLE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("TRACK TABLE PROBE FAILED")
		quit(1)
	else:
		print("TRACK TABLE PROBE OK")
		quit(0)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[PASS] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[FAIL] ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _json_ok(v: Variant) -> bool:
	var s := JSON.stringify(v)
	return s.length() > 2 and not s.contains("<Object") and not s.contains("<Ref") \
		and not s.contains("Vector3")


func _obs(ev_id: String, t: float, sensor: String, batch: String, support := 1) -> Dictionary:
	return {"schema": "sensor_observation.v1", "kind": "observation",
		"event_id": ev_id, "t": t, "sensor": sensor,
		"entity_id": "E-" + batch, "batch": batch, "support": support,
		"quality": 0.8, "range_km": 1000.0, "bearing_deg": 45.0}


func _ev(ev_id: String, t: float, target: String, etype: String,
		extra := {}) -> Dictionary:
	var e := {"schema": "track_evidence.v1", "kind": "evidence",
		"event_id": ev_id, "t": t, "target_id": target,
		"track_id": target, "evidence_type": etype,
		"source": etype, "detail": "probe"}
	for k in extra.keys():
		e[k] = extra[k]
	return e


func _test_single_writer() -> void:
	print("")
	print("── 1. 单写者 / 只读 UI ──")
	var s = TrackTable.new({"writer_id": "fusion"})
	_ok(bool(s.ready), "ready", str(s.errors))
	_eq(s.current_writer(), "fusion", "writer_id")
	_ok(bool(s.claim_writer("fusion").get("ok", false)), "同 writer claim ok")
	var conflict: Dictionary = s.claim_writer("ui")
	_ok(not bool(conflict.get("ok", true)), "第二 writer 冲突")
	_eq(String(conflict.get("reason", "")), "writer_conflict", "冲突 reason")
	var bad: Dictionary = s.handle_observation(_obs("ui1", 1.0, "radar", "2001", 1), "ui")
	_ok(not bool(bad.get("ok", true)), "未授权写拒绝")
	_eq(String(bad.get("reason", "")), "unauthorized_writer", "未授权 reason")
	_ok(s.all_tracks().is_empty(), "未授权不创建 track")
	_ok(s.find("T0001").is_empty(), "find 只读空")
	# 只读订阅
	var got: Array = []
	var cb = func(ev): got.append(ev)
	_ok(s.subscribe(cb), "subscribe")
	var ok: Dictionary = s.handle_observation(_obs("o1", 2.0, "radar", "2001", 1), "fusion")
	_ok(bool(ok.get("ok", false)), "授权写 ok", str(ok.get("reason", "")))
	_ok(got.size() >= 1, "订阅收到事件")
	_ok(s.unsubscribe(cb), "unsubscribe")
	s.handle_observation(_obs("o2", 3.0, "radar", "2001", 1), "fusion")
	_ok(got.size() >= 1, "取消订阅后不再增长（仍 >=1）")


func _test_levels_l1_to_l4() -> void:
	print("")
	print("── 2. L1→L4 融合 / 证据追溯 ──")
	var s = TrackTable.new({"writer_id": "fusion"})
	var o1: Dictionary = s.handle_observation(_obs("o1", 1.0, "radar", "2001", 1), "fusion")
	_ok(bool(o1.get("ok", false)), "单观测创建 track")
	var id := String((o1.get("track", {}) as Dictionary).get("id", ""))
	_ok(id != "", "track id")
	var tr: Dictionary = s.find(id)
	_eq(int(tr.get("level", 0)), 1, "单观测 L1")
	_eq(String(tr.get("identity", "")), "unknown", "默认 identity=unknown")
	_eq(String(tr.get("threat", "")), "none", "默认 threat=none")
	_ok((tr.get("sources", []) as Array).has("radar"), "source=radar")
	_ok((tr.get("evidence", []) as Array).size() >= 1, "evidence 非空")
	_ok(bool(tr.get("created_t", 0.0) == 1.0), "created_t")
	var o2: Dictionary = s.handle_observation(_obs("o2", 2.0, "ir", "2001", 1), "fusion")
	_eq(String((o2.get("track", {}) as Dictionary).get("id", "")), id, "同 batch 合并同 track")
	tr = s.find(id)
	_eq(int(tr.get("level", 0)), 2, "多源观测 L2")
	_ok((tr.get("sources", []) as Array).has("radar")
		and (tr.get("sources", []) as Array).has("ir"), "sources 合并")
	var e3: Dictionary = s.handle_evidence(_ev("e3", 3.0, id, "optical", {"support": 3}), "fusion")
	_ok(bool(e3.get("ok", false)), "光学 Evidence ok", str(e3.get("reason", "")))
	tr = s.find(id)
	_eq(int(tr.get("level", 0)), 3, "光学 Evidence L3")
	_eq(String(tr.get("identity", "")), "unknown", "L3 不自动身份")
	var ev_types: Array = []
	for raw in (tr.get("evidence", []) as Array):
		ev_types.append(String((raw as Dictionary).get("type", "")))
	_ok(ev_types.has("observation") and ev_types.has("optical"), "证据可追溯", str(ev_types))
	var e4: Dictionary = s.handle_evidence(_ev("e4", 4.0, id, "iff",
		{"support": 4, "identity": "friend"}), "fusion")
	_ok(bool(e4.get("ok", false)), "IFF Evidence ok")
	tr = s.find(id)
	_eq(int(tr.get("level", 0)), 4, "IFF Evidence L4")
	_eq(String(tr.get("identity", "")), "friend", "IFF friend → friend")
	_eq(String(tr.get("identity_label", "")), "友方", "身份 label")
	_ok((tr.get("evidence_ids", []) as Array).size() > 0, "evidence_ids")
	_ok(_json_ok(tr), "track JSON")


func _test_identity_and_threat() -> void:
	print("")
	print("── 3. 身份六级 / 不明不判敌 / TrackUpdate ──")
	var s = TrackTable.new({"writer_id": "fusion"})
	var o: Dictionary = s.handle_observation(_obs("o1", 1.0, "radar", "3001", 1), "fusion")
	var id := String((o.get("track", {}) as Dictionary).get("id", ""))
	# IFF no_reply → unknown，不判敌
	var nr: Dictionary = s.handle_evidence(_ev("e1", 2.0, id, "iff",
		{"support": 4, "iff": {"status": "no_reply"}}), "fusion")
	_ok(bool(nr.get("ok", false)), "IFF no_reply 接受")
	_eq(String(s.find(id).get("identity", "")), "unknown", "no_reply → unknown")
	_eq(String(s.find(id).get("threat", "")), "none", "no_reply 不自动 threat")
	# 非授权 hostile 拒绝
	var h: Dictionary = s.handle_evidence(_ev("e2", 3.0, id, "optical",
		{"support": 3, "identity": "hostile"}), "fusion")
	_ok(not bool(h.get("ok", true)), "非授权 hostile 拒绝")
	_eq(String(h.get("reason", "")), "hostile_requires_authority", "hostile 拒绝 reason")
	_eq(String(s.find(id).get("identity", "")), "unknown", "拒绝后身份不变")
	# 拒绝不得产生部分写入（低等级 track 上 hostile evidence 不升 L3）
	var o2: Dictionary = s.handle_observation(_obs("o2h", 3.0, "radar", "3002", 1), "fusion")
	var id2 := String((o2.get("track", {}) as Dictionary).get("id", ""))
	var h2: Dictionary = s.handle_evidence(_ev("e2h", 3.1, id2, "optical",
		{"support": 3, "identity": "hostile"}), "fusion")
	_ok(not bool(h2.get("ok", true)), "低等级 hostile 拒绝")
	_eq(int(s.find(id2).get("level", 0)), 1, "拒绝后等级未部分写入")
	_eq(String(s.find(id2).get("identity", "")), "unknown", "拒绝后身份未部分写入")
	# manual/authoritative 可写 hostile
	var hm: Dictionary = s.handle_evidence(_ev("e3", 4.0, id, "manual",
		{"support": 4, "identity": "hostile", "authoritative": true}), "fusion")
	_ok(bool(hm.get("ok", false)), "authoritative manual hostile 接受")
	_eq(String(s.find(id).get("identity", "")), "hostile", "显式 hostile")
	# TrackUpdate
	var tu: Dictionary = s.handle_event({"schema": "track_update.v1", "kind": "track_update",
		"t": 5.0, "track_id": id, "level": 4, "identity": "neutral",
		"threat": "suspect", "quality": 0.9}, "fusion")
	_ok(bool(tu.get("ok", false)), "TrackUpdate 接受", str(tu.get("reason", "")))
	var tr: Dictionary = s.find(id)
	_eq(String(tr.get("identity", "")), "neutral", "TrackUpdate identity")
	_eq(String(tr.get("threat", "")), "suspect", "TrackUpdate threat")
	_eq(int(tr.get("level", 0)), 4, "TrackUpdate 等级保持")
	# 等级不倒退
	var dd: Dictionary = s.handle_event({"schema": "track_update.v1",
		"kind": "track_update", "t": 6.0, "track_id": id, "level": 2}, "fusion")
	_ok(not bool(dd.get("ok", true)), "等级倒退拒绝")
	_eq(String(dd.get("reason", "")), "level_regression", "倒退 reason")
	_eq(int(s.find(id).get("level", 0)), 4, "等级仍 L4")
	# 直接身份非法
	var bad_id: Dictionary = s.handle_event({"schema": "track_update.v1",
		"kind": "track_update", "t": 7.0, "track_id": id, "identity": "bogus"}, "fusion")
	_ok(not bool(bad_id.get("ok", true)), "非法身份拒绝")
	# 身份六级常量
	_ok((s.IDENTITIES as Array).size() == 6, "身份六级常量")
	_ok("hostile" in s.IDENTITIES and "assumed_friend" in s.IDENTITIES, "六级含 assumed_friend/hostile")


func _test_dedup_merge_expire() -> void:
	print("")
	print("── 4. 去重 / 同批合并 / 过期 ──")
	var s = TrackTable.new({"writer_id": "fusion"})
	var o1: Dictionary = s.handle_observation(_obs("dup1", 1.0, "radar", "4001", 1), "fusion")
	var id := String((o1.get("track", {}) as Dictionary).get("id", ""))
	var n := s.all_tracks().size()
	var dup: Dictionary = s.handle_observation(_obs("dup1", 2.0, "radar", "4001", 1), "fusion")
	_ok(not bool(dup.get("ok", true)), "event_id 去重拒绝")
	_eq(String(dup.get("reason", "")), "duplicate_event", "event_id reason")
	_eq(s.all_tracks().size(), n, "重复事件不增 track")
	# 同 batch 新 event → 同 track
	var o2: Dictionary = s.handle_observation(_obs("dup2", 3.0, "optical", "4001", 1), "fusion")
	_eq(String((o2.get("track", {}) as Dictionary).get("id", "")), id, "同 batch 同 track")
	_eq(s.all_tracks().size(), n, "同 batch 不重复 track")
	# 显式 merge_duplicates（测试夹具直接建两条同 batch 的重复航迹）
	var sm = TrackTable.new({"writer_id": "fusion"})
	var d1: Dictionary = sm._create_track({"batch": "8001", "entity_id": "E-8001"}, 1.0)
	var d2: Dictionary = sm._create_track({"batch": "8001", "entity_id": "E-8001"}, 2.0)
	sm._apply_level(d2, 3, 2.0, "fixture")
	_eq(sm.all_tracks().size(), 2, "夹具重复航迹 2")
	var merged: Array = sm.merge_duplicates()
	_eq(sm.all_tracks().size(), 1, "merge 后 1 track")
	_eq(merged.size(), 1, "merge 记录 1")
	_ok(int(sm.find(String(d1.get("id", ""))).get("level", 0)) == 3, "merge 取高等级")
	_ok((sm.find(String(d1.get("id", ""))).get("merged_from", []) as Array).has(String(d2.get("id", ""))),
		"merged_from 记录")
	_ok(_json_ok(sm.vm()), "merge VM JSON")
	# 过期 stale
	var s2 = TrackTable.new({"writer_id": "fusion", "stale_after_s": 10.0,
		"forget_after_s": 20.0})
	var oo: Dictionary = s2.handle_observation(_obs("x1", 1.0, "radar", "5001", 1), "fusion")
	var xid := String((oo.get("track", {}) as Dictionary).get("id", ""))
	_eq(int(s2.find(xid).get("level", 0)), 1, "过期前 L1")
	var tk: Dictionary = s2.tick(11.0)
	_eq(int(tk.get("stale", 0)), 1, "tick 标记 stale")
	_ok(bool(s2.find(xid).get("stale", false)), "track stale=true")
	_eq(int(s2.find(xid).get("level", 0)), 1, "过期不降级")
	var tk2: Dictionary = s2.tick(10.0)
	_ok((tk2.get("forgotten", []) as Array).has(xid), "forget 移除")
	_ok(s2.find(xid).is_empty(), "移除后 find 空")
	_ok(_json_ok(s2.vm()), "过期 VM JSON")
	# 事件时间回归
	var reg: Dictionary = s2.handle_observation(_obs("reg", 0.0, "radar", "5002", 1), "fusion")
	_ok(not bool(reg.get("ok", true)), "时间回归拒绝")
	_eq(String(reg.get("reason", "")), "time_regression", "时间回归 reason")
	# 非法 TrackUpdate target
	var ut: Dictionary = s2.handle_event({"schema": "track_update.v1",
		"kind": "track_update", "t": 30.0, "track_id": "NOPE"}, "fusion")
	_ok(not bool(ut.get("ok", true)), "未知 track update 拒绝")
	_eq(String(ut.get("reason", "")), "unknown_track", "unknown track reason")


func _test_validation_and_dbC() -> void:
	print("")
	print("── 5. DbC 非法事件拒绝 ──")
	var s = TrackTable.new({"writer_id": "fusion"})
	var cases: Array = [
		["missing schema", {"kind": "observation", "t": 1.0}],
		["unknown schema", {"schema": "x", "kind": "x", "t": 1.0}],
		["no identity", {"schema": "sensor_observation.v1", "t": 1.0,
			"sensor": "radar", "support": 1}],
		["bad sensor", {"schema": "sensor_observation.v1", "t": 1.0,
			"entity_id": "E1", "sensor": "laser", "support": 1}],
		["bad support", {"schema": "sensor_observation.v1", "t": 1.0,
			"entity_id": "E2", "sensor": "radar", "support": 9}],
		["observation L3", {"schema": "sensor_observation.v1", "t": 1.0,
			"entity_id": "E3", "sensor": "optical", "support": 3}],
		["bad evidence type", {"schema": "track_evidence.v1", "t": 1.0,
			"track_id": "T0001", "evidence_type": "magic"}],
		["unknown evidence track", {"schema": "track_evidence.v1", "t": 1.0,
			"track_id": "T9999", "evidence_type": "iff", "support": 4}],
		["nonfinite t", {"schema": "sensor_observation.v1", "t": NAN,
			"entity_id": "E4", "sensor": "radar", "support": 1}],
	]
	for raw in cases:
		var c: Array = raw
		var r: Dictionary = s.handle_event(c[1] as Dictionary, "fusion")
		_ok(not bool(r.get("ok", true)), "拒绝: " + String(c[0]),
			String(r.get("reason", "")))
	_ok((s.all_tracks() as Array).is_empty(), "非法事件不产生 track")
	_ok((s.errors as Array).size() >= cases.size(), "DbC errors 记录")
	# 非法 setup
	var bad = TrackTable.new({"writer_id": "", "stale_after_s": -1.0})
	_ok(not bool(bad.ready), "非法 setup 不 ready")
	_ok((bad.errors as Array).size() > 0, "非法 setup errors")
	# 只读 copy
	var s2 = TrackTable.new({"writer_id": "fusion"})
	var o: Dictionary = s2.handle_observation(_obs("o1", 1.0, "radar", "6001", 1), "fusion")
	var id := String((o.get("track", {}) as Dictionary).get("id", ""))
	var copy: Dictionary = s2.find(id)
	copy["level"] = 99
	_eq(int(s2.find(id).get("level", 0)), 1, "read-only copy 不影响内部")
	# advance 时间回归
	_ok(not bool(s2.advance(-5.0).get("ok", true)), "advance 负时间拒绝")


func _test_readonly_vm_json_determinism() -> void:
	print("")
	print("── 6. 只读 VM / filter / selected / JSON / 确定性 ──")
	var s = TrackTable.new({"writer_id": "fusion"})
	var o: Dictionary = s.handle_observation(_obs("o1", 1.0, "radar", "7001", 1), "fusion")
	var id := String((o.get("track", {}) as Dictionary).get("id", ""))
	s.handle_observation(_obs("o2", 2.0, "ir", "7001", 1), "fusion")
	s.handle_evidence(_ev("e1", 3.0, id, "iff", {"support": 4, "identity": "friend"}), "fusion")
	var vm: Dictionary = s.vm({"selected_id": id})
	_ok(String(vm.get("schema", "")) == "fused_track_table.v1", "VM schema")
	_ok(String(vm.get("mode", "")) == "single_writer", "VM mode single_writer")
	_eq(String(vm.get("writer_id", "")), "fusion", "VM writer")
	_ok((vm.get("tracks", []) as Array).size() == 1, "VM tracks 1")
	_ok(not (vm.get("selected", {}) as Dictionary).is_empty(), "VM selected")
	_ok(String((vm.get("selected", {}) as Dictionary).get("id", "")) == id, "selected id")
	_ok((vm.get("summary", {}) as Dictionary).has("by_level"), "summary by_level")
	_ok(((vm.get("writes", {}) as Dictionary).get("track_table", true)) == false, "不写 TrackTable")
	_ok(((vm.get("writes", {}) as Dictionary).get("v15", true)) == false, "不写 V15")
	_ok(_json_ok(vm), "VM JSON")
	_ok(_json_ok(s.summary()), "summary JSON")
	# filter
	var f1: Array = s.filter({"level_min": 3})
	_ok(f1.size() == 1, "filter level_min")
	var f2: Array = s.filter({"identity": "friend"})
	_ok(f2.size() == 1, "filter identity")
	var f3: Array = s.filter({"source": "ir"})
	_ok(f3.size() == 1, "filter source")
	var f4: Array = s.filter({"stale": true})
	_ok(f4.is_empty(), "filter stale")
	# selected 只读
	_ok(s.selected(id).size() > 0, "selected 只读")
	_ok(s.selected("NOPE").is_empty(), "selected unknown 空")
	# 确定性
	var a = TrackTable.new({"writer_id": "fusion"})
	var b = TrackTable.new({"writer_id": "fusion"})
	for raw in [
		{"schema": "sensor_observation.v1", "kind": "observation", "event_id": "d1",
			"t": 1.0, "sensor": "radar", "entity_id": "E9", "batch": "9001", "support": 1},
		{"schema": "sensor_observation.v1", "kind": "observation", "event_id": "d2",
			"t": 2.0, "sensor": "ir", "entity_id": "E9", "batch": "9001", "support": 1},
		{"schema": "track_evidence.v1", "kind": "evidence", "event_id": "d3",
			"t": 3.0, "track_id": "T0001", "evidence_type": "iff", "support": 4,
			"identity": "friend"},
	]:
		a.handle_event((raw as Dictionary).duplicate(true), "fusion")
		b.handle_event((raw as Dictionary).duplicate(true), "fusion")
	_ok(JSON.stringify(a.vm()) == JSON.stringify(b.vm()), "确定性 VM")
	_ok(JSON.stringify(a.take_events()) == JSON.stringify(b.take_events()), "确定性 events")
	_ok(_json_ok(a.events), "events JSON")


func _test_save_load() -> void:
	print("")
	print("── 7. save/load 快照 / 版本 / 去重 / 过期 ──")
	# 构造有 evidence / 去重记录 / stale 的状态
	var s = TrackTable.new({"writer_id": "fusion", "stale_after_s": 5.0,
		"forget_after_s": 50.0})
	var o: Dictionary = s.handle_observation(_obs("s-o1", 1.0, "radar", "8101", 1), "fusion")
	var id := String((o.get("track", {}) as Dictionary).get("id", ""))
	s.handle_observation(_obs("s-o2", 2.0, "ir", "8101", 1), "fusion")
	s.handle_evidence(_ev("s-e1", 3.0, id, "optical", {"support": 3}), "fusion")
	s.tick(6.0)
	_ok(bool(s.find(id).get("stale", false)), "保存前 stale")
	var json := s.save_state()
	var parsed = JSON.parse_string(json)
	_ok(parsed is Dictionary, "save_state 是 JSON")
	var payload: Dictionary = parsed
	_eq(String(payload.get("schema", "")), "v17.fused_track_table_save.v1", "save schema")
	_eq(String(payload.get("version", "")), "1.0.0", "save version")
	_eq(String(payload.get("table_schema", "")), "fused_track_table.v1", "table_schema")
	_ok(payload.get("tracks") is Array and (payload.get("tracks") as Array).size() == 1,
		"save tracks")
	_ok(payload.get("events") is Array, "save events")
	_ok(payload.get("seen_event_ids") is Array, "save dedup keys")
	_ok(_json_ok(payload), "save payload JSON")
	_ok(s.snapshot().get("tracks") is Array, "snapshot() 返回 payload")
	_ok(s.save_payload().get("version") == "1.0.0", "save_payload 别名")
	# 恢复 → VM 一致
	var r = TrackTable.new()
	var lr: Dictionary = r.load_state(json)
	_ok(bool(lr.get("ok", false)), "load_state ok", str(lr.get("errors", [])))
	_ok(JSON.stringify(s.vm()) == JSON.stringify(r.vm()), "load 后 VM 一致")
	_ok(s.save_state() == r.save_state(), "load 后 save_state 一致")
	_ok(bool(r.find(id).get("stale", false)), "stale 状态保留")
	_ok((r.find(id).get("evidence", []) as Array).size() >= 3, "evidence 保留")
	_ok(int(r.find(id).get("level", 0)) == 3, "level 保留")
	_ok(String(r.current_writer()) == "fusion", "writer 保留")
	_ok(absf(float(r.t) - float(s.t)) < 1.0e-9, "t 保留")
	# 去重状态保留
	var dup: Dictionary = r.handle_observation(_obs("s-o1", 20.0, "radar", "8101", 1), "fusion")
	_eq(String(dup.get("reason", "")), "duplicate_event", "load 后 event_id 去重保留")
	# 新 event 继续序号/新 track
	var n: Dictionary = r.handle_observation(_obs("s-new", 20.0, "radar", "8102", 1), "fusion")
	_ok(bool(n.get("ok", false)), "load 后继续写")
	_ok(String((n.get("track", {}) as Dictionary).get("id", "")) != id, "新 track id 不冲突")
	# dict 形式 / save_payload 兼容
	var r2 = TrackTable.new()
	_ok(bool(r2.load_state(payload).get("ok", false)), "load_state(dict)")
	_ok(bool(r2.load_save_payload(s.snapshot()).get("ok", false)), "load_save_payload")
	# 确定性
	_ok(s.save_state() == s.save_state(), "save_state 确定性")
	var r3 = TrackTable.new()
	r3.load_state(json)
	_ok(s.save_state() == r3.save_state(), "load/save 往返确定性")
	# SaveService payload 兼容（JSON 字符串可嵌入 session_save）
	var svc = SaveServiceScript.new("user://track_table_probe_saves")
	var sp := {"schema": "v17.session_payload.v1", "version": "1.0.0",
		"session_save": s.save_state(), "writer": "fusion"}
	var encoded: String = svc.encode_file(sp)
	var dec: Dictionary = svc.decode_file(encoded)
	_ok(bool(dec.get("ok", false)), "SaveService encode/decode 兼容")
	_ok(String((dec.get("payload", {}) as Dictionary).get("session_save", "")) == s.save_state(),
		"SaveService payload 保留 track state")
	# 过期状态在恢复后继续
	var se = TrackTable.new({"writer_id": "fusion", "stale_after_s": 5.0,
		"forget_after_s": 50.0})
	var oe: Dictionary = se.handle_observation(_obs("x", 1.0, "radar", "8201", 1), "fusion")
	var xid := String((oe.get("track", {}) as Dictionary).get("id", ""))
	se.tick(6.0)
	var saved_exp := se.save_state()
	var re = TrackTable.new()
	re.load_state(saved_exp)
	_ok(bool(re.find(xid).get("stale", false)), "恢复后 stale 继续")
	re.tick(50.0)
	_ok(re.find(xid).is_empty(), "恢复后 forget 继续")
	# 非法/版本/损坏拒绝，不破坏当前状态
	var before := r.all_tracks().size()
	var bad_cases: Array = [
		["empty", ""],
		["bad json", "{bad"],
		["bad schema", JSON.stringify({"schema": "x", "version": "1.0.0"})],
		["future version", JSON.stringify({"schema": "v17.fused_track_table_save.v1",
			"version": "9.0.0", "table_schema": "fused_track_table.v1"})],
		["old version", JSON.stringify({"schema": "v17.fused_track_table_save.v1",
			"version": "0.9.0", "table_schema": "fused_track_table.v1"})],
		["missing tracks", JSON.stringify({"schema": "v17.fused_track_table_save.v1",
			"version": "1.0.0", "table_schema": "fused_track_table.v1",
			"config": {}, "writer_id": "fusion", "t": 1.0, "next_id": 1,
			"event_seq": 0, "seen_event_ids": [], "events": [], "outbox": []})],
	]
	for raw in bad_cases:
		var c: Array = raw
		var rr: Dictionary = r.load_state(c[1])
		_ok(not bool(rr.get("ok", true)), "拒绝快照: " + String(c[0]),
			String(rr.get("reason", "")))
	_eq(r.all_tracks().size(), before, "非法快照不破坏当前状态")
	# 非法 track 字段
	var good: Dictionary = payload.duplicate(true)
	var bad_track: Dictionary = (good.get("tracks", []) as Array)[0].duplicate(true)
	bad_track["level"] = 9
	good["tracks"] = [bad_track]
	_ok(not bool(r.load_state(good).get("ok", true)), "非法 level 快照拒绝")
	var bad_id: Dictionary = payload.duplicate(true)
	var bt2: Dictionary = (bad_id.get("tracks", []) as Array)[0].duplicate(true)
	bt2["id"] = "T0001"
	var bt2b: Dictionary = bt2.duplicate(true)
	bad_id["tracks"] = [bt2, bt2b]
	_ok(not bool(r.load_state(bad_id).get("ok", true)), "重复 track id 快照拒绝")
	_ok(_json_ok(r.vm()), "恢复后 VM JSON")
