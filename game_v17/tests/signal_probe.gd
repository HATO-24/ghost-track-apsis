extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# SIGNAL SERVICE PROBE · 完整游戏-阶段3K
#
# 验证：ELINT 单站 L1 / 多站交叉 / 指纹 / LPI / 通信元数据；可见光灯语
# 发送/接收/确认/超时/遮挡/误读；代码表内容；VM/JSON/save/load；
# 确定性；不写 TrackTable/world/UI。只跑一次。
# ═══════════════════════════════════════════════════════════════════

const SignalService := preload("res://scripts/core/signal_service.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("SIGNAL SERVICE PROBE · 完整游戏-阶段3K")
	print("════════════════════════════════════════════════════════════════")
	_test_setup_codes()
	_test_elint_single()
	_test_elint_multi_df()
	_test_light_codes()
	_test_save_load_json()
	_test_dynamic_targets()
	print("────────────────────────────────────────────────────────────────")
	print("SIGNAL SERVICE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("SIGNAL SERVICE PROBE FAILED")
		quit(1)
	else:
		print("SIGNAL SERVICE PROBE OK")
		quit(0)


# ── 工具 / fixtures ────────────────────────────────────────────

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


func _emitter(model: String, signature: String, lpi := false, active := true,
		silent := false, freq := 9500.0, power := 90.0) -> Dictionary:
	return {"type": "radar", "model": model, "signature_name": signature,
		"active": active, "silent": silent, "lpi": lpi,
		"frequency_mhz": freq, "power_dbm": power, "gain_tx_dbi": 30.0,
		"prf_hz": 1200.0, "scan_period_s": 1.0}


func _targets() -> Array:
	return [
		{"id": "E1", "pos_km": [0.0, 1500.0, 0.0],
			"emissions": [_emitter("YW-R9", "YW-R9")]},
		{"id": "E2", "pos_km": [500.0, 1500.0, 0.0],
			"emissions": [_emitter("KD-R6", "KD-R6", true)]},
		{"id": "E3", "pos_km": [0.0, 500.0, 0.0],
			"emissions": [_emitter("YW-R9", "YW-R9", false, true, true)]},
		{"id": "C1", "pos_km": [0.0, 1000.0, 0.0],
			"comms": [{"from": "C1", "to": "X", "mode": "radio", "encrypted": true,
				"text": "secret", "frequency_mhz": 300.0, "callsign": "UNKNOWN-1"}]},
		{"id": "L1", "pos_km": [0.0, 20.0, 0.0]},
		{"id": "O1", "pos_km": [0.0, 20.0, 0.0], "occluded": true},
	]


func _service(multi := true) -> Object:
	var stations := [{"id": "S1", "pos_km": [0.0, 0.0, 0.0],
		"enabled": true, "sigma_bearing_deg": 1.0}]
	if multi:
		stations.append({"id": "S2", "pos_km": [1000.0, 0.0, 0.0],
			"enabled": true, "sigma_bearing_deg": 1.0})
	return SignalService.new({
		"observer": {"id": "Obs", "pos_km": [0.0, 0.0, 0.0]},
		"targets": _targets(), "stations": stations,
		"elint": {"enabled": true, "range_km": 60000.0, "refresh_s": 1.0},
	})


func _tx_id(res: Dictionary) -> String:
	return String((res.get("tx", {}) as Dictionary).get("tx_id", ""))


# ── 1. setup / 代码表 ──────────────────────────────────────────

func _test_setup_codes() -> void:
	print("")
	print("── 1. setup / 内容灯语代码表 ──")
	var s = _service(true)
	_ok(bool(s.ready), "ready", str(s.errors))
	_ok((s.errors as Array).is_empty(), "setup 无错误")
	_eq(String((s.code_content as Dictionary).get("schema", "")), "light_codes.v1", "codes schema")
	_eq((s.codes as Dictionary).size(), 7, "7 个灯语代码")
	_ok((s.code_ids as Array).has("APPROACH_REQ"), "APPROACH_REQ")
	_ok((s.code_ids as Array).has("GUSHEN2_HAIL"), "谷神-2 示例代码")
	var c: Dictionary = s._code("APPROACH_REQ")
	_eq(String(c.get("code", "")), "1010", "四位 code")
	_eq(c.get("code", "").length(), 4, "四位长度")
	_eq(String(c.get("mode", "")), "blink", "灯光模式")
	_ok(String(c.get("meaning", "")) == "请求接近", "代码含义")
	_ok(bool(c.get("ack_required", false)), "ack_required")
	var g: Dictionary = s._code("GUSHEN2_HAIL")
	_ok((g.get("scenario_tags", []) as Array).has("gushen2"), "谷神2场景标签")
	_eq(String(g.get("mode", "")), "steady", "steady 模式")
	_ok(_json_ok(s.code_content), "codes JSON")
	_ok(_json_ok(s.vm()), "VM JSON")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "不写 TrackTable")
	_ok(((s.vm().get("writes", {}) as Dictionary).get("world", true)) == false, "不写 world")
	_ok((s.vm().get("light", {}) as Dictionary).has("codes"), "VM light codes")
	for cid in (s.code_ids as Array):
		var row: Dictionary = s._code(String(cid))
		_ok(String(row.get("code", "")).length() == 4, "代码四位 " + String(cid))
		_ok(String(row.get("mode", "")) in ["blink", "steady"], "代码模式 " + String(cid))
		_ok(String(row.get("meaning", "")) != "", "代码含义 " + String(cid))
	# 非法内容
	_ok(not bool(s.validate_codes({}).get("ok", true)), "空 codes 非法")
	_ok(not bool(s.validate_codes({"schema": "light_codes.v1", "codes": [
		{"id": "X", "code": "12", "mode": "blink", "meaning": "x"}]}).get("ok", true)),
		"非四位 code 非法")


# ── 2. ELINT 单站 L1 / 指纹 / COMINT ───────────────────────────

func _test_elint_single() -> void:
	print("")
	print("── 2. ELINT 单站 L1 / 指纹 / 通信元数据 ──")
	var s = _service(true)
	var r: Dictionary = s.intercept("E1")
	_ok(bool(r.get("ok", false)), "intercept E1 ok", str(r.get("reason", "")))
	_ok((r.get("signals", []) as Array).size() > 0, "E1 signals")
	_ok((r.get("observations", []) as Array).size() > 0, "E1 observations")
	_ok((r.get("fingerprints", []) as Array).size() > 0, "E1 fingerprints")
	var o: Dictionary = (r.get("observations", []) as Array)[0]
	_eq(String(o.get("schema", "")), "sensor_observation.v1", "observation schema")
	_eq(String(o.get("sensor", "")), "elint", "ELINT sensor")
	_eq(int(o.get("level_support", 0)), 1, "单站 L1 support")
	_ok(not bool(o.get("produces_contact", true)), "ELINT 不产生 contact")
	_ok(not bool(o.get("level_decided", true)), "ELINT 不判等级")
	_ok(not bool(o.get("writes_v15", true)), "ELINT 不写 V15")
	_ok(String(o.get("target_id", "")) == "E1", "observation target")
	_ok(float(o.get("bearing_deg", -999.0)) >= -360.0, "bearing 字段")
	_ok(float(o.get("freq_mhz", 0.0)) > 0.0, "freq 字段")
	_ok(String(o.get("band", "")) != "", "band 字段")
	_ok(String(o.get("identity", "")) != "hostile", "不直接判身份")
	# 指纹 evidence
	var fp_ev: Dictionary = {}
	for raw in (r.get("fingerprints", []) as Array):
		if raw is Dictionary:
			fp_ev = raw
	_ok(not fp_ev.is_empty(), "fingerprint evidence")
	_ok(String(fp_ev.get("fingerprint", "")) != "", "fingerprint 值")
	_eq(int(fp_ev.get("level_support", 0)), 3, "指纹 L3 support")
	_eq(String(fp_ev.get("identity", "")), "unknown", "指纹 identity unknown")
	_ok(not bool(fp_ev.get("produces_contact", true)), "指纹不产生 contact")
	# LPI
	var r2: Dictionary = s.intercept("E2")
	_ok(bool(r2.get("ok", false)), "LPI E2 intercepted")
	var lpi_obs: Dictionary = {}
	for raw in (r2.get("observations", []) as Array):
		if raw is Dictionary:
			lpi_obs = raw
	_ok(bool(lpi_obs.get("lpi", false)), "LPI 标记")
	_ok(String(lpi_obs.get("class_hint", "")) != "", "LPI 型号提示")
	# 静默目标 reason
	var r3: Dictionary = s.intercept("E3")
	_ok(not bool(r3.get("ok", true)), "静默目标 no signal")
	_eq(String(r3.get("reason", "")), "no_emission", "静默 reason")
	_ok(not bool(s.intercept("NOPE").get("ok", true)), "未知目标 false")
	# COMINT 元数据（通信/数据链）
	var rc: Dictionary = s.intercept("C1")
	_ok(bool(rc.get("ok", false)), "COMINT C1 ok")
	_ok((rc.get("comms", []) as Array).size() > 0, "COMINT comms")
	var com_obs: Dictionary = {}
	for raw in (s.vm().get("observations", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("sensor", "")) == "elint.comms":
			com_obs = raw
	_ok(not com_obs.is_empty(), "COMINT observation")
	_ok(bool(com_obs.get("encrypted", false)), "加密标记")
	_ok(bool(com_obs.get("metadata_only", false)), "只给元数据")
	_ok(bool(com_obs.get("content_redacted", false)), "不解码内容")
	_eq(int(com_obs.get("level_support", 0)), 1, "COMINT L1")
	_ok(_json_ok(r), "intercept JSON")
	_ok(_json_ok(s.vm()), "ELINT VM JSON")


# ── 3. 多站 DF / 交叉候选 / resolve ──────────────────────────

func _test_elint_multi_df() -> void:
	print("")
	print("── 3. 多站 DF / 交叉候选 / resolve ──")
	var s = _service(true)
	s.intercept("E1")
	var d: Dictionary = s.df("E1")
	_ok(bool(d.get("ok", false)), "df E1 ok", str(d.get("reason", "")))
	_ok((d.get("l1", []) as Array).size() > 0, "DF L1 方位线")
	var l1: Dictionary = (d.get("l1", []) as Array)[0]
	_eq(int(l1.get("level_support", 0)), 1, "DF L1 support")
	_ok(not bool(l1.get("produces_contact", true)), "DF L1 不产生 contact")
	_ok((d.get("candidates", []) as Array).size() > 0, "多站交叉候选")
	_ok(bool(d.get("multi_station", false)), "multi_station true")
	var cand: Dictionary = (d.get("candidates", []) as Array)[0]
	_ok(String(cand.get("fix_id", "")) != "", "fix_id")
	_eq(int(cand.get("level_support", 0)), 2, "candidate L2 support")
	_ok(bool(cand.get("provisional", false)), "候选 provisional")
	_ok(bool(cand.get("requires_confirmation", false)), "候选需确认")
	_ok(not bool(cand.get("produces_contact", true)), "候选不产生 contact")
	_ok((cand.get("pos_km") as Array).size() >= 2, "候选位置")
	_ok(float(cand.get("sigma_range_km", -1.0)) >= 0.0, "候选误差")
	_ok((s.candidates as Array).size() > 0, "candidates 保存")
	var res: Dictionary = s.resolve(String(cand.get("fix_id", "")))
	_ok(bool(res.get("ok", false)), "resolve fix")
	_eq(String(res.get("type", "")), "elint_fix", "resolve type")
	_ok(not bool(res.get("produces_contact", true)), "resolve 不产生 contact")
	_ok(not bool(res.get("produces_position", true)), "resolve 不产生位置")
	_ok(String(res.get("identity", "")) == "unknown", "resolve identity unknown")
	_ok(not bool(s.resolve("NOPE").get("ok", true)), "resolve 未知 id false")
	# 单站：不能交叉
	var single = _service(false)
	single.intercept("E1")
	var ds: Dictionary = single.df("E1")
	_ok((ds.get("l1", []) as Array).size() > 0, "单站 L1 存在")
	_ok((ds.get("candidates", []) as Array).is_empty(), "单站无交叉候选")
	_ok(bool(ds.get("single_station", false)), "single_station true")
	_ok(_json_ok(s.vm()), "DF VM JSON")


# ── 4. 可见光灯语 ─────────────────────────────────────────────

func _test_light_codes() -> void:
	print("")
	print("── 4. 可见光灯语 发送/接收/确认/超时/遮挡/误读 ──")
	var s = _service(false)
	var send: Dictionary = s.light_send("APPROACH_REQ", "L1")
	_ok(bool(send.get("ok", false)), "light_send ok")
	var txid := _tx_id(send)
	_ok(txid != "", "tx_id")
	var tx: Dictionary = send.get("tx", {}) as Dictionary
	_eq(String(tx.get("status", "")), "SENT", "发送状态 SENT")
	_eq(String(tx.get("code", "")), "1010", "发送四位 code")
	_eq(String(tx.get("mode", "")), "blink", "发送模式")
	_ok(bool(tx.get("ack_required", false)), "需要 ack")
	_ok(float(tx.get("range_km", -1.0)) > 0.0, "灯语距离")
	_ok(_events_kind(s, "light_send") >= 1, "light_send event")
	var recv: Dictionary = s.light_receive(txid)
	_ok(bool(recv.get("ok", false)), "light_receive ok")
	_eq(String(recv.get("code", "")), "1010", "接收 code")
	_eq(String((recv.get("tx", {}) as Dictionary).get("status", "")), "RECEIVED", "接收状态")
	_ok(_events_kind(s, "light_receive") >= 1, "light_receive event")
	var ack: Dictionary = s.light_ack(txid)
	_ok(bool(ack.get("ok", false)), "light_ack ok")
	_eq(String((ack.get("tx", {}) as Dictionary).get("status", "")), "ACKED", "ACKED 状态")
	var rr: Dictionary = s.resolve(txid)
	_eq(String(rr.get("status", "")), "ACKED", "resolve ACKED")
	# 发送失败 reason
	_ok(not bool(s.light_send("NOPE", "L1").get("ok", true)), "未知 code false")
	_ok(not bool(s.light_send("APPROACH_REQ", "").get("ok", true)), "空目标 false")
	_ok(not bool(s.light_send("APPROACH_REQ", "NOPE").get("ok", true)), "未知目标 false")
	_ok(bool(s.light_send("APPROACH_REQ", "L1").get("ok", false)), "再次 send 成功")
	_ok(not bool(s.light_send("APPROACH_REQ", "E1").get("ok", true)), "超距 false")
	_ok(not bool(s.light_send("APPROACH_REQ", "L1", {"occluded": true}).get("ok", true)),
		"显式遮挡 false")
	_ok(not bool(s.light_send("APPROACH_REQ", "O1").get("ok", true)), "目标遮挡 false")
	# 超时
	var send2: Dictionary = s.light_send("MAYDAY", "L1", {"timeout_s": 1.0})
	_ok(bool(send2.get("ok", false)), "timeout fixture send")
	var tx2 := _tx_id(send2)
	s.step(2.0)
	var tx2row: Dictionary = s._find_tx(tx2)
	_eq(String(tx2row.get("status", "")), "TIMEOUT", "超时状态")
	var recv2: Dictionary = s.light_receive(tx2)
	_ok(not bool(recv2.get("ok", true)), "超时后接收 false")
	var res2: Dictionary = s.resolve(tx2)
	_eq(String(res2.get("status", "")), "TIMEOUT", "resolve timeout")
	var ack2: Dictionary = s.light_ack(tx2)
	_ok(not bool(ack2.get("ok", true)), "超时后 ack false")
	# 误读
	var send3: Dictionary = s.light_send("APPROACH_ACK", "L1")
	var tx3 := _tx_id(send3)
	var mis: Dictionary = s.light_receive(tx3, {"misread": true})
	_ok(not bool(mis.get("ok", true)), "误读 false")
	_eq(String(mis.get("reason", "")), "misread", "误读 reason")
	_ok(bool(mis.get("misread", false)), "misread 标记")
	_eq(String(mis.get("received_code", "")), "????", "误读码")
	_eq(String((s._find_tx(tx3) as Dictionary).get("status", "")), "MISREAD", "MISREAD 状态")
	# ack 前置
	var send4: Dictionary = s.light_send("HOLD_POSITION", "L1")
	var tx4 := _tx_id(send4)
	_ok(not bool(s.light_ack(tx4).get("ok", true)), "未接收不可 ack")
	_ok(not bool(s.light_receive("NOPE").get("ok", true)), "未知 tx false")
	_ok(_json_ok(s.vm()), "light VM JSON")
	_ok(_events_kind(s, "light_timeout") >= 1, "timeout event")
	_ok(_events_kind(s, "light_misread") >= 1, "misread event")


# ── 5. save/load / JSON / 确定性 ───────────────────────────────

func _test_save_load_json() -> void:
	print("")
	print("── 5. save/load / JSON / 确定性 ──")
	var s = _service(true)
	s.intercept("E1")
	s.df("E1")
	var send: Dictionary = s.light_send("GUSHEN2_HAIL", "L1")
	var txid := _tx_id(send)
	s.light_receive(txid)
	var text: String = s.save_state()
	var p = JSON.parse_string(text)
	_ok(p is Dictionary, "save JSON")
	_ok(String((p as Dictionary).get("schema", "")) == "v17.signal_service_save.v1", "save schema")
	_ok(String((p as Dictionary).get("version", "")) == "1.0.0", "save version")
	_ok((p as Dictionary).get("transmissions") is Array, "save transmissions")
	var r = _service(true)
	var lr: Dictionary = r.load_state(text)
	_ok(bool(lr.get("ok", false)), "load_state ok", str(lr.get("reason", "")))
	_eq(int((r.transmissions as Array).size()), int((s.transmissions as Array).size()), "load transmissions")
	_ok((r.elint_signals as Array).size() >= (s.elint_signals as Array).size(), "load ELINT")
	_ok((r.candidates as Array).size() >= 1, "load candidates")
	_ok(absf(float(r.t) - float(s.t)) < 1.0e-9, "load t")
	_ok(String((r._find_tx(txid) as Dictionary).get("tx_id", "")) == txid, "load tx 可索引")
	_ok(_json_ok(r.vm()), "loaded VM JSON")
	_ok(s.save_state() == s.save_state(), "save 确定性")
	# 非法快照
	var bad: Array = [
		["empty", ""], ["bad json", "{bad"],
		["bad schema", JSON.stringify({"schema": "x", "version": "1.0.0"})],
		["future", JSON.stringify({"schema": "v17.signal_service_save.v1",
			"version": "9.0.0", "transmissions": [], "elint_signals": []})],
	]
	for raw in bad:
		var c: Array = raw
		_ok(not bool(r.load_state(c[1]).get("ok", true)), "拒绝快照: " + String(c[0]))
	# 双实例确定性
	var a = _service(true)
	var b = _service(true)
	for svc in [a, b]:
		svc.intercept("E1")
		svc.df("E1")
		var tt: Dictionary = svc.light_send("APPROACH_REQ", "L1")
		svc.light_receive(_tx_id(tt))
	_ok(JSON.stringify(a.vm()) == JSON.stringify(b.vm()), "确定性 VM")
	_ok(_json_ok(a.summary()), "summary JSON")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("track_table", true)) == false, "最终不写 TrackTable")
	_ok(((a.vm().get("writes", {}) as Dictionary).get("v15", true)) == false, "最终不写 V15")


func _events_kind(s, kind: String) -> int:
	var n := 0
	for raw in (s.events as Array):
		if raw is Dictionary and String((raw as Dictionary).get("kind", "")) == kind:
			n += 1
	return n

# ── 6. 动态目标注册 / side / ACK 能力 ─────────────────────────

func _dyn_target(id: String, side: String, opts := {}) -> Dictionary:
	var d: Dictionary = {"id": id, "side": side, "pos_km": [0.0, 20.0, 0.0]}
	for k in (opts as Dictionary).keys():
		d[String(k)] = (opts as Dictionary)[k]
	return d

func _txid(res: Dictionary) -> String:
	return String((res.get("tx", {}) as Dictionary).get("tx_id", ""))

func _test_dynamic_targets() -> void:
	print("")
	print("── 6. 动态目标注册 / side / ACK 能力 ──")
	var s = _service(false)
	var base_ids: Array = s.target_ids()
	_eq(base_ids.size(), 6, "初始 6 目标")
	_ok("E1" in base_ids, "初始含 E1")
	_ok("C1" in base_ids, "初始含 C1")
	# upsert 四类 side
	var H: Dictionary = s.upsert_target(_dyn_target("H1", "hostile",
		{"entity_id": "apsis", "batch": "B-H"}))
	_eq(bool(H.get("ok", false)), true, "upsert hostile ok")
	_eq(bool(H.get("created", false)), true, "hostile created")
	_eq(String((H.get("target", {}) as Dictionary).get("side", "")), "hostile",
		"hostile side")
	_eq(String((s.target("H1")).get("entity_id", "")), "apsis", "target entity_id")
	_eq(String((s.target("H1")).get("batch", "")), "B-H", "target batch")
	var N: Dictionary = s.upsert_target(_dyn_target("N1", "neutral"))
	_eq(bool(N.get("ok", false)), true, "upsert neutral ok")
	var F: Dictionary = s.upsert_target(_dyn_target("FR1", "friend"))
	_eq(bool(F.get("ok", false)), true, "upsert friend ok")
	var U: Dictionary = s.upsert_target(_dyn_target("U1", "unknown"))
	_eq(bool(U.get("ok", false)), true, "upsert unknown ok")
	for id in ["H1", "N1", "FR1", "U1"]:
		_ok(String(id) in s.target_ids(), "target_ids 含 " + String(id))
	# 增量 upsert：未提供字段保留
	var H2: Dictionary = s.upsert_target({"id": "H1", "batch": "B-H2"})
	_eq(bool(H2.get("created", true)), false, "upsert 已存在 created=false")
	_eq(String(s.target("H1").get("side", "")), "hostile", "upsert 保留 side")
	_eq(String(s.target("H1").get("batch", "")), "B-H2", "upsert 更新 batch")
	_eq(String(s.target("H1").get("entity_id", "")), "apsis", "upsert 保留 entity")
	# 非法 upsert 不改状态
	var ids_before: Array = s.target_ids()
	var h1_before := JSON.stringify(s.target("H1"))
	_eq(bool(s.upsert_target({}).get("ok", true)), false, "空目标拒绝")
	_eq(bool(s.upsert_target({"id": "BAD", "side": "enemy"}).get("ok", true)), false,
		"非法 side 拒绝")
	_eq(bool(s.upsert_target({"id": "BAD2", "pos_km": [0.0, 1.0]}).get("ok", true)),
		false, "非法 pos 拒绝")
	_eq(bool(s.upsert_target({"id": "BAD3",
		"pos_km": [NAN, 0.0, 0.0]}).get("ok", true)), false, "NaN pos 拒绝")
	_eq(bool(s.upsert_target({"id": "BAD4", "emissions": "x"}).get("ok", true)),
		false, "非法 emissions 拒绝")
	_eq(s.target_ids(), ids_before, "非法 upsert 不改 ids")
	_eq(JSON.stringify(s.target("H1")), h1_before, "非法 upsert 不改目标")
	# 灯语发送：不因 side 拒绝
	for id2 in ["H1", "N1", "FR1", "U1"]:
		var snd: Dictionary = s.light_send("APPROACH_REQ", String(id2))
		_eq(bool(snd.get("ok", false)), true, "灯语可发 " + String(id2))
		_eq(String((snd.get("tx", {}) as Dictionary).get("target_side", "")),
			String(s.target(String(id2)).get("side", "")), "tx 记录 target_side " + String(id2))
		var tid := _txid(snd)
		var rcv: Dictionary = s.light_receive(tid)
		_eq(bool(rcv.get("ok", false)), true, "灯语可收 " + String(id2))
		var ack: Dictionary = s.light_ack(tid)
		_eq(bool(ack.get("ok", false)), true, "能力正常时 ACK 与 side 无关 " + String(id2))
	# ACK 能力：light_capable=false
	s.upsert_target(_dyn_target("CAP", "hostile", {"light_capable": false}))
	var sc: Dictionary = s.light_send("APPROACH_REQ", "CAP")
	var txc := _txid(sc)
	_eq(bool(s.light_receive(txc).get("ok", false)), true, "CAP 可接收")
	var ack_cap: Dictionary = s.light_ack(txc)
	_eq(bool(ack_cap.get("ok", true)), false, "无灯语能力不可 ACK")
	_eq(String(ack_cap.get("reason", "")), "not_light_capable", "not_light_capable")
	_eq(String((s.resolve_light(txc).get("status", ""))), "RECEIVED", "失败后仍 RECEIVED")
	# receiver_facing=false
	s.upsert_target(_dyn_target("FAC", "neutral", {"receiver_facing": false}))
	var txf := _txid(s.light_send("APPROACH_REQ", "FAC"))
	s.light_receive(txf)
	var ack_f: Dictionary = s.light_ack(txf)
	_eq(bool(ack_f.get("ok", true)), false, "不朝向不可 ACK")
	_eq(String(ack_f.get("reason", "")), "not_facing", "not_facing")
	# destroyed / inactive
	s.upsert_target(_dyn_target("DES", "hostile", {"destroyed": true}))
	var txd := _txid(s.light_send("APPROACH_REQ", "DES"))
	s.light_receive(txd)
	_eq(String(s.light_ack(txd).get("reason", "")), "target_unavailable", "destroyed ACK")
	s.upsert_target(_dyn_target("OFF", "friend", {"active": false}))
	var txo := _txid(s.light_send("APPROACH_REQ", "OFF"))
	s.light_receive(txo)
	_eq(String(s.light_ack(txo).get("reason", "")), "target_unavailable", "inactive ACK")
	# 目标被移除后 ack 不伪造
	s.upsert_target(_dyn_target("GONE", "hostile"))
	var txg := _txid(s.light_send("APPROACH_REQ", "GONE"))
	s.light_receive(txg)
	_eq(bool(s.remove_target("GONE").get("ok", false)), true, "remove 已接收目标 ok")
	_eq(String(s.light_ack(txg).get("reason", "")), "unknown_target", "目标移除后 ACK 拒绝")
	# 事件
	_ok(_events_kind(s, "target_upserted") >= 1, "target_upserted 事件")
	_ok(_events_kind(s, "target_removed") >= 1, "target_removed 事件")
	# remove/set/sync
	_eq(bool(s.remove_target("H1").get("ok", false)), true, "remove_target ok")
	_ok(not ("H1" in s.target_ids()), "remove 后 ids 不含")
	_eq(bool(s.remove_target("H1").get("ok", true)), false, "remove 未知拒绝")
	var setr: Dictionary = s.set_targets([
		{"id": "S1", "side": "hostile", "pos_km": [0.0, 20.0, 0.0]},
		{"id": "S2", "side": "neutral", "pos_km": [0.0, 20.0, 0.0],
			"light_capable": false}])
	_eq(bool(setr.get("ok", false)), true, "set_targets ok")
	_eq(s.target_ids(), ["S1", "S2"], "set 后仅 2 目标")
	var before_set: Array = s.target_ids()
	_eq(bool(s.set_targets([{"id": "X1", "side": "hostile"},
		{"id": "X1", "side": "neutral"}]).get("ok", true)), false, "重复 id set 拒绝")
	_eq(s.target_ids(), before_set, "非法 set 不改状态")
	_eq(bool(s.set_targets([{"id": "X2", "side": "bad"}]).get("ok", true)), false,
		"非法 side set 拒绝")
	_eq(s.target_ids(), before_set, "非法 side set 不改状态")
	# sync：merge 保留缺失字段
	var sy: Dictionary = s.sync_targets([
		{"id": "S1", "entity_id": "apsis", "batch": "B-S"},
		{"id": "S3", "side": "friend", "pos_km": [0.0, 20.0, 0.0]}])
	_eq(bool(sy.get("ok", false)), true, "sync merge ok")
	_eq(int(sy.get("added", -1)), 1, "sync added=1")
	_eq(int(sy.get("updated", -1)), 1, "sync updated=1")
	_eq(String(s.target("S1").get("side", "")), "hostile", "sync 保留 side")
	_eq(String(s.target("S1").get("entity_id", "")), "apsis", "sync 更新 entity")
	_ok("S3" in s.target_ids(), "sync 新增 S3")
	# replace_metadata：缺省字段回默认（batch/entity 清空）
	var sy2: Dictionary = s.sync_targets([{"id": "S1", "side": "friend"}],
		{"replace_metadata": true})
	_eq(bool(sy2.get("ok", false)), true, "sync replace ok")
	_eq(bool(sy2.get("replace_metadata", false)), true, "sync replace flag")
	_eq(String(s.target("S1").get("entity_id", "")), "", "replace 后 entity 默认空")
	_eq(String(s.target("S1").get("side", "")), "friend", "replace 后 side")
	# 非法 sync 原子拒绝
	var ids_sync: Array = s.target_ids()
	_eq(bool(s.sync_targets([{"id": "S9", "side": "neutral"},
		{"id": "S10", "side": "bad"}]).get("ok", true)), false, "非法 sync 拒绝")
	_eq(s.target_ids(), ids_sync, "非法 sync 不改状态")
	# vm/summary
	var vm: Dictionary = s.vm()
	_eq(int(vm.get("target_count", -1)), s.target_ids().size(), "VM target_count")
	_eq(int(s.summary().get("targets", -1)), s.target_ids().size(), "summary targets")
	_ok(_json_ok(vm.get("targets", [])), "targets JSON")
	for raw in (vm.get("targets", []) as Array):
		var row: Dictionary = raw
		_ok(row.has("side"), "target row side 字段")
		_ok(row.has("light_capable"), "target row light_capable")
		_ok(row.has("receiver_facing"), "target row receiver_facing")
	# 存档：targets 往返
	var save: String = String(s.save_state())
	var d = JSON.parse_string(save)
	_ok(d is Dictionary, "save JSON")
	if d is Dictionary:
		_ok((d as Dictionary).has("targets"), "save 含 targets")
	var s2 = _service(false)
	var lr: Dictionary = s2.load_state(save)
	_eq(bool(lr.get("ok", false)), true, "动态目标 save/load ok")
	_eq(s2.target_ids(), s.target_ids(), "load target_ids 一致")
	_eq(String(s2.target("S1").get("side", "")), "friend", "load S1 side")
	_eq(bool(s2.target("S2").get("light_capable", true)), false, "load capability")
	# 旧存档缺 targets：保留当前目标
	var old: Dictionary = (d as Dictionary).duplicate(true)
	old.erase("targets")
	var s3 = _service(false)
	var old_ids: Array = s3.target_ids()
	var lr3: Dictionary = s3.load_state(JSON.stringify(old))
	_eq(bool(lr3.get("ok", false)), true, "旧存档缺 targets 兼容")
	_eq(s3.target_ids(), old_ids, "旧存档保留当前目标")
	# 非法存档 targets 拒绝且不改状态
	var bad: Dictionary = (d as Dictionary).duplicate(true)
	bad["targets"] = [{"id": "Z", "side": "bad"}]
	var s4 = _service(false)
	var before_ids: Array = s4.target_ids()
	_eq(bool(s4.load_state(JSON.stringify(bad)).get("ok", true)), false,
		"非法 targets 存档拒绝")
	_eq(s4.target_ids(), before_ids, "非法存档不改目标")
	# 确定性
	var a = _service(false)
	var b = _service(false)
	for x in [a, b]:
		x.upsert_target(_dyn_target("DX", "hostile"))
		x.upsert_target(_dyn_target("DN", "neutral", {"light_capable": false}))
		x.sync_targets([{"id": "DX", "batch": "B"}])
		var tx := _txid(x.light_send("APPROACH_REQ", "DX"))
		x.light_receive(tx)
		x.light_ack(tx)
	_eq(JSON.stringify(a.vm()), JSON.stringify(b.vm()), "动态目标同操作 VM 一致")
	_eq(a.save_state(), b.save_state(), "动态目标同操作 save 一致")
	# 灯语发送未知目标仍拒绝（非 side）
	_eq(String(s.light_send("APPROACH_REQ", "NO_SUCH").get("reason", "")),
		"unknown_target", "未知目标发送拒绝 reason")
