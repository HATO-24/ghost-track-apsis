extends RefCounted

# 阶段1F 正式 UI Shell 的真实数据绑定层。
# - GameSession（可选 track_table/story_state）；SaveService user://saves；
# - track_vm/entities → 接触；orders → 命令队列；session.bus → 事件；
# - 真实 Δv/ROE 优先读取内容缓存/story_state；缺失明确 NOT READY。
# 不实现剧情/物理；不写旧场景。

const GameSession := preload("res://scripts/core/game_session.gd")
const PreludeScenario := preload("res://scripts/core/prelude_scenario.gd")
const CeresChain := preload("res://scripts/core/ceres_chain.gd")
const SaveService := preload("res://scripts/core/save_service.gd")

const TRANSFER_CACHE := "res://framework/content/transfer_l4_l1_cached.json"
const SAVE_ROOT := "user://saves"

var session = null
var save_service = null
var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
var signal_sync_result: Dictionary = {}
var last_transponder_reply: Dictionary = {}
var prelude = null
var prelude_ready := false
var used_prelude := false
var prelude_title := ""
var prelude_triggers: Array = []
var ceres_chain = null
var ceres_ready := false
var last_ceres_result: Dictionary = {}
var track_vm: Dictionary = {}
var sensor_vm: Dictionary = {}
var sensor_result := ""
var story_vm: Dictionary = {}
var snapshot: Dictionary = {}
var contacts: Array = []
var commands: Array = []
var events: Array = []
var delta_v_mps := 0.0
var delta_v_ready := false
var roe_text := "ROE NOT READY"
var commander := "指挥官 · 沧澜"
var last_save_text := ""
var last_save_ok := false


func boot() -> bool:
	errors.clear()
	warnings.clear()
	session = GameSession.new()
	var sensor_cfg := _sensor_config()
	var seed: Dictionary = {}
	prelude = PreludeScenario.new()
	prelude.setup({})
	prelude_ready = bool(prelude.ready)
	used_prelude = false
	if prelude_ready:
		var pcfg: Dictionary = prelude.boot_config()
		if not pcfg.is_empty():
			seed = pcfg
			seed["track_table"] = true
			seed["story_state"] = true
			seed["sensor_service"] = sensor_cfg
			seed["orders"] = [
				{"action": "HOLD", "issuer_id": "apsis", "target_ids": ["harmattan"], "issue": true, "opts": {"auth_required": false}},
			]
			used_prelude = true
			prelude_title = String(prelude.content.get("title", "序章"))
			prelude_triggers = prelude.triggers.duplicate(true)
			print("[SHELL BINDER] prelude ready=true entities=", prelude.entities.size(), " triggers=", prelude.triggers.size(), " used=true")
	else:
		warnings.append("PreludeScenario 未 ready：fallback demo")
		print("[SHELL BINDER] prelude ready=false errors=", str(prelude.errors))
	if seed.is_empty():
		seed = {
			"track_table": true,
			"story_state": true,
			"sensor_service": sensor_cfg,
			"signal_service": true,
			"facility_registry": true,
			"transponder_service": true,
			"orders": [
				{"action": "HOLD", "issuer_id": "apsis", "target_ids": ["harmattan"], "issue": true, "opts": {"auth_required": false}},
			],
		}
	var br: Dictionary = session.boot(seed)
	if not bool(br.get("ok", false)):
		errors.append("GameSession boot failed: " + str(br.get("reason", "")))
		return false
	save_service = SaveService.new(SAVE_ROOT)
	if not bool(save_service.setup(SAVE_ROOT)):
		errors.append("SaveService setup failed")
		return false
	ceres_chain = CeresChain.new()
	var cerr: bool = ceres_chain.setup({"content_path": CeresChain.DEFAULT_CONTENT})
	ceres_ready = cerr
	if not cerr:
		warnings.append("CeresChain 未 ready：" + str(ceres_chain.errors))
	else:
		print("[SHELL BINDER] CeresChain ready state=", ceres_chain.current_state(), " entity=", ceres_chain.entity_id, " texts=", ceres_chain.text_keys.size(), " code=", ceres_chain.emergency_light_code)
	if session.sensor_service == null:
		_seed_tracks()
	_load_delta_v()
	# 先推进一小步让 SensorService→TrackTable 产生真实 L1-L2 观测；失败仍显式 NOT READY。
	if session.sensor_service != null:
		session.tick(0.1)
	refresh()
	ready = errors.is_empty()
	return ready


func _sensor_config() -> Dictionary:
	# observer=apsis；targets 示例来自 GameSession demo seed 实体；不写旧场景。
	var targets: Array = [
		{"id": "harmattan", "target_id": "harmattan", "entity_id": "harmattan", "batch": "1001",
			"pos_km": [20.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0], "rcs_m2": 10.0,
			"temp_k": 300.0, "area_m2": 1000.0, "size_m": 50.0, "illum": 1.0,
			"transponder": "ok", "iff_code": "FRIEND-1001", "registered": true,
			"crypto_epoch": "epoch-1", "side": "friend", "faction": "OCUVF",
			"classification": {"ship_class": "DDG", "role": "escort", "faction": "friend"}},
		{"id": "l1_station", "target_id": "l1_station", "entity_id": "l1_station", "batch": "3100",
			"pos_km": [0.0, 0.0, 10.0], "vel_kmps": [0.0, 0.0, 0.0], "rcs_m2": 100.0,
			"temp_k": 300.0, "area_m2": 5000.0, "size_m": 200.0, "illum": 1.0,
			"transponder": "ok", "iff_code": "FRIEND-3100", "registered": true,
			"crypto_epoch": "epoch-1", "side": "friend", "faction": "OCUVF",
			"classification": {"ship_class": "STATION", "role": "port", "faction": "friend"}},
	]
	return {
		"observer": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0], "vel_kmps": [0.0, 0.0, 0.0],
			"attitude_quat": [0.0, 0.0, 0.0, 1.0], "mast_deployed": true, "emcon": false,
			"damage": {"sensors": 1.0, "comms": 1.0, "propulsion": 1.0}},
		"mounts": [],  # 空 → SensorService/Authority 默认装配
		"targets": targets,
		"snapshot": {"sun_dir": [0.0, 0.0, 1.0], "sun_illum": 1.0, "jamming": 0.0, "shadow": false, "los": true},
		"options": {"radar_enabled": true, "emcon": false, "iff_enabled": true},
	}


func _seed_tracks() -> void:
	if session == null or session.track_table == null:
		return
	# 真实 session 实体 → 轨道观测（radar TWS L2）；track_table 单写者由 session 负责。
	var snap: Dictionary = session.snapshot()
	var ents: Array = snap.get("entities", []) if snap.get("entities", []) is Array else []
	for raw in ents:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		if String(e.get("kind", "ship")) != "ship":
			continue
		var pos: Array = e.get("pos_km", []) if e.get("pos_km", []) is Array else []
		var range_km := 0.0
		if pos.size() >= 3:
			range_km = sqrt(float(pos[0]) * float(pos[0]) + float(pos[1]) * float(pos[1]) + float(pos[2]) * float(pos[2]))
		var obs := {
			"batch": String(e.get("batch", "")), "entity_id": String(e.get("id", "")),
			"sensor": "radar", "support": 2, "range_km": range_km,
			"bearing_deg": 45.0, "quality": 0.9, "t": 0.0,
		}
		var res: Dictionary = session.handle_observation(obs)
		if not bool(res.get("ok", false)):
			warnings.append("track seed failed %s: %s" % [String(e.get("id", "")), String(res.get("reason", ""))])


func _load_delta_v() -> void:
	delta_v_ready = false
	delta_v_mps = 0.0
	if not FileAccess.file_exists(TRANSFER_CACHE):
		return
	var f := FileAccess.open(TRANSFER_CACHE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var budget: Dictionary = parsed.get("budget", {}) if parsed.get("budget", {}) is Dictionary else {}
		delta_v_mps = float(budget.get("total_dv_mps", 0.0))
		delta_v_ready = delta_v_mps > 0.0


func refresh() -> void:
	if session == null:
		return
	snapshot = session.snapshot()
	track_vm = session.track_vm({}) if session.track_table != null else {}
	story_vm = session.story_vm() if session.story_state != null else {}
	sensor_vm = session.sensor_service.vm() if session.sensor_service != null else {}
	contacts = _build_contacts()
	_sync_signal_targets()
	commands = _build_commands()
	events = session.bus.recent(8) if session.bus != null else []
	# ROE：真实 story_state 存在时显示默认交战规则；不伪造裁决。
	if session.story_state != null and bool(story_vm.get("ready", false)):
		roe_text = "WEAPONS HOLD / 仅自衛 · phase " + String(story_vm.get("phase", "—"))
	else:
		roe_text = "ROE NOT READY · story_state 未启用"
	delta_v_ready = delta_v_ready and delta_v_mps > 0.0


func _build_contacts() -> Array:
	var rows: Array = []
	var entity_by_id: Dictionary = {}
	for raw in (snapshot.get("entities", []) if snapshot.get("entities", []) is Array else []):
		if raw is Dictionary:
			entity_by_id[String((raw as Dictionary).get("id", ""))] = raw
	var tracks: Array = track_vm.get("tracks", []) if track_vm.get("tracks", []) is Array else []
	for raw in tracks:
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		var eid := String(tr.get("entity_id", ""))
		var e: Dictionary = entity_by_id.get(eid, {}) if entity_by_id.get(eid, {}) is Dictionary else {}
		var name := String(e.get("name", ""))
		if name == "":
			name = "TRACK " + String(tr.get("track_id", tr.get("id", "")))
		var identity := String(tr.get("identity", "unknown"))
		var tside := String(e.get("side", identity)).to_lower() if not e.is_empty() else identity
		var ttype := "friendly"
		if tside in ["unknown", "hostile", "suspect"]:
			ttype = "unknown"
		elif tside == "neutral":
			ttype = "neutral"
		var sources: Array = tr.get("sources", []) if tr.get("sources", []) is Array else []
		var bid := String(tr.get("batch", ""))
		if bid == "":
			bid = String(e.get("batch", ""))
		if bid == "":
			bid = eid
		if bid == "":
			bid = String(tr.get("track_id", ""))
		rows.append({
			"id": bid,
			"entity_id": eid, "track_id": String(tr.get("track_id", "")),
			"name": name, "cls": "TRACK %s · L%d" % [String(tr.get("track_id", "")), int(tr.get("level", 0))],
			"type": ttype, "side": tside, "identity": identity, "threat": String(tr.get("threat", "unknown")),
			"badge": "TRACK", "level": int(tr.get("level", 0)),
			"range_km": float(tr.get("range_km", -1.0)), "sources": sources,
		})
	# 未产生 track 的 session 实体（站体等）仍以真实实体列入，不硬编码数据。
	for eid in entity_by_id.keys():
		var found := false
		for row in rows:
			if String((row as Dictionary).get("entity_id", "")) == String(eid):
				found = true
				break
		if found:
			continue
		var e: Dictionary = entity_by_id[eid]
		var kind := String(e.get("kind", "ship"))
		var eside := String(e.get("side", "friend")).to_lower()
		var etype := "friendly"
		if eside in ["unknown", "hostile", "suspect"]:
			etype = "unknown"
		elif eside == "neutral":
			etype = "neutral"
		elif kind == "station" or kind in ["fuel", "tank", "port", "otc", "relay"]:
			etype = "station"
		var row := {"id": String(e.get("batch", eid)), "entity_id": String(eid), "track_id": "",
			"name": String(e.get("name", eid)), "cls": kind.to_upper(),
			"type": etype, "side": eside, "identity": String(e.get("identity", eside)),
			"threat": "unknown" if etype == "unknown" else "none", "badge": "ENTITY", "level": 0, "range_km": -1.0, "sources": []}
		var efac_id := String(e.get("facility_id", ""))
		if efac_id != "" and session != null and session.facility_registry != null:
			var f0: Dictionary = session.facility_lookup(efac_id)
			var fac0: Dictionary = f0.get("facility", {}) if f0.get("facility", {}) is Dictionary else {}
			if not fac0.is_empty():
				var cl0: Dictionary = f0.get("cluster", {}) if f0.get("cluster", {}) is Dictionary else {}
				row["facility_id"] = String(fac0.get("facility_id", efac_id))
				row["facility_name"] = String(fac0.get("name", ""))
				row["facility_code"] = String(fac0.get("facility_code", ""))
				row["transponder_code"] = String(fac0.get("transponder_code", ""))
				row["transponder_type"] = String(fac0.get("transponder_type", ""))
				row["facility_class"] = String(fac0.get("facility_class", ""))
				row["owner"] = String(fac0.get("owner", ""))
				row["side"] = String(fac0.get("side", eside))
				row["cluster_id"] = String(fac0.get("parent_cluster", ""))
				row["cluster_name"] = String(cl0.get("name", ""))
				row["services"] = (fac0.get("services", []) as Array).duplicate()
				row["ports"] = (fac0.get("ports", []) as Array).duplicate(true)
				row["physical"] = (fac0.get("physical", {}) as Dictionary).duplicate(true)
				row["badge"] = "FACILITY"
				row["cls"] = "设施 · " + String(fac0.get("facility_class", "")) + " · " + String(fac0.get("facility_code", "")) + " · " + String(fac0.get("transponder_code", ""))
		elif kind == "station" and session != null and session.facility_registry != null:
			var f: Dictionary = session.facility_for_entity(eid)
			if not f.is_empty():
				var card: Dictionary = session.facility_lookup(String(f.get("facility_id", "")))
				var fac: Dictionary = card.get("facility", f) if card.get("facility", {}) is Dictionary else f
				var cluster: Dictionary = card.get("cluster", {}) if card.get("cluster", {}) is Dictionary else {}
				row["facility_id"] = String(fac.get("facility_id", ""))
				row["facility_name"] = String(fac.get("name", ""))
				row["facility_code"] = String(fac.get("facility_code", ""))
				row["transponder_code"] = String(fac.get("transponder_code", ""))
				row["transponder_type"] = String(fac.get("transponder_type", ""))
				row["facility_class"] = String(fac.get("facility_class", ""))
				row["owner"] = String(fac.get("owner", ""))
				row["side"] = String(fac.get("side", "friend"))
				row["cluster_id"] = String(fac.get("parent_cluster", ""))
				row["cluster_name"] = String(cluster.get("name", ""))
				row["services"] = (fac.get("services", []) as Array).duplicate()
				row["ports"] = (fac.get("ports", []) as Array).duplicate(true)
				row["physical"] = (fac.get("physical", {}) as Dictionary).duplicate(true)
				row["badge"] = "FACILITY"
				row["cls"] = "设施 · " + String(fac.get("facility_class", "")) + " · " + String(fac.get("facility_code", "")) + " · " + String(fac.get("transponder_code", ""))
		rows.append(row)
	# 已存在 track 行的 station/设施接触也补 facility 映射（entity row 可能因 track 已存在而跳过）。
	if session != null and session.facility_registry != null:
		for row in rows:
			var rr: Dictionary = row
			if String(rr.get("facility_id", "")) != "":
				continue
			var reid := String(rr.get("entity_id", ""))
			if reid == "":
				continue
			var f2: Dictionary = session.facility_for_entity(reid)
			if f2.is_empty():
				continue
			var card2: Dictionary = session.facility_lookup(String(f2.get("facility_id", "")))
			var fac2: Dictionary = card2.get("facility", f2) if card2.get("facility", {}) is Dictionary else f2
			var cluster2: Dictionary = card2.get("cluster", {}) if card2.get("cluster", {}) is Dictionary else {}
			rr["facility_id"] = String(fac2.get("facility_id", ""))
			rr["facility_name"] = String(fac2.get("name", ""))
			rr["facility_code"] = String(fac2.get("facility_code", ""))
			rr["transponder_code"] = String(fac2.get("transponder_code", ""))
			rr["transponder_type"] = String(fac2.get("transponder_type", ""))
			rr["facility_class"] = String(fac2.get("facility_class", ""))
			rr["owner"] = String(fac2.get("owner", ""))
			rr["side"] = String(fac2.get("side", "friend"))
			rr["cluster_id"] = String(fac2.get("parent_cluster", ""))
			rr["cluster_name"] = String(cluster2.get("name", ""))
			rr["services"] = (fac2.get("services", []) as Array).duplicate()
			rr["ports"] = (fac2.get("ports", []) as Array).duplicate(true)
			rr["physical"] = (fac2.get("physical", {}) as Dictionary).duplicate(true)
			rr["badge"] = "FACILITY"
			rr["cls"] = "设施 · " + String(fac2.get("facility_class", "")) + " · " + String(fac2.get("facility_code", "")) + " · " + String(fac2.get("transponder_code", ""))
	# 动态 signal targets（core signal_service.targets）补进接触列表，供任意 side 灯语/ELINT；
	# 明确 badge=SIGNAL，不是伪造 world 实体。
	if session != null and session.signal_service != null:
		var known: Dictionary = {}
		for row in rows:
			known[String((row as Dictionary).get("entity_id", (row as Dictionary).get("id", "")))] = true
		for raw_t in (session.signal_service.targets if session.signal_service.targets is Array else []):
			if not (raw_t is Dictionary):
				continue
			var t: Dictionary = raw_t
			var tid := String(t.get("id", ""))
			if tid == "" or known.has(tid):
				continue
			var tside := String(t.get("side", "unknown"))
			var ttype := "unknown" if tside in ["unknown", "hostile", "suspect"] else ("neutral" if tside == "neutral" else "friendly")
			rows.append({"id": tid, "entity_id": String(t.get("entity_id", tid)), "track_id": "",
				"name": "SIGNAL " + tid, "cls": "SIGNAL TARGET", "type": ttype, "side": tside,
				"threat": "unknown" if ttype == "unknown" else "none", "badge": "SIGNAL",
				"level": 0, "range_km": float(t.get("range_km", -1.0)), "sources": [], "signal_target": true})
	return rows


func _build_commands() -> Array:
	var comps: Dictionary = snapshot.get("components", {}) if snapshot.get("components", {}) is Dictionary else {}
	var om: Dictionary = comps.get("orders", {}) if comps.get("orders", {}) is Dictionary else {}
	var raw_orders: Array = om.get("orders", []) if om.get("orders", []) is Array else []
	var out: Array = []
	for raw in raw_orders:
		if not (raw is Dictionary):
			continue
		var o: Dictionary = raw
		out.append({
			"id": String(o.get("order_id", "—")), "state": String(o.get("status", "—")),
			"actor": String(o.get("issuer_id", "—")),
			"target": ",".join(o.get("target_ids", [])) if o.get("target_ids") is Array else "—",
			"action": String(o.get("action", "—")), "mode": String(o.get("mode", "—")),
			"delay": "%.1fs" % float(o.get("delivery_delay_s", 0.0)),
		})
	return out


func _sync_signal_targets() -> void:
	signal_sync_result = {}
	if session == null or session.signal_service == null:
		warnings.append("signal_service 未启用；动态 targets 未同步")
		return
	var entities: Array = snapshot.get("entities", []) if snapshot.get("entities", []) is Array else []
	var ent_by_id: Dictionary = {}
	for raw in entities:
		if raw is Dictionary:
			ent_by_id[String((raw as Dictionary).get("id", ""))] = raw
	var rows: Array = []
	for raw in contacts:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var tid := String(c.get("entity_id", c.get("id", "")))
		if tid == "":
			continue
		var e: Dictionary = ent_by_id.get(String(c.get("entity_id", "")), {}) if ent_by_id.get(String(c.get("entity_id", "")), {}) is Dictionary else {}
		var side := "friend"
		match String(c.get("type", "")):
			"unknown":
				side = "unknown"
			"neutral":
				side = "neutral"
			"station":
				side = "friend"
		var pos: Array = e.get("pos_km", []) if e.get("pos_km", []) is Array else [0.0, 0.0, 0.0]
		if pos.size() != 3:
			pos = [0.0, 0.0, 0.0]
		rows.append({"id": tid, "target_id": tid, "entity_id": String(c.get("entity_id", "")),
			"batch": String(c.get("id", "")), "side": side, "identity": side,
			"pos_km": pos, "light_capable": true, "active": true, "destroyed": false})
	if rows.is_empty():
		warnings.append("signal targets 同步：contacts 无有效 target")
		return
	var res: Dictionary = session.signal_sync_targets(rows, {"replace_metadata": false})
	signal_sync_result = res.duplicate(true)
	if not bool(res.get("ok", false)):
		warnings.append("signal targets 同步失败：" + String(res.get("reason", "")))
	else:
		print("[SHELL BINDER] signal targets synced added=", int(res.get("added", 0)), " updated=", int(res.get("updated", 0)), " count=", int(res.get("count", 0)))


func selected_entity(row: Dictionary) -> Dictionary:
	var eid := String(row.get("entity_id", ""))
	for raw in (snapshot.get("entities", []) if snapshot.get("entities", []) is Array else []):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == eid:
			return raw
	return {}


func selected_track(row: Dictionary) -> Dictionary:
	var tid := String(row.get("track_id", ""))
	for raw in (track_vm.get("tracks", []) if track_vm.get("tracks", []) is Array else []):
		if raw is Dictionary and String((raw as Dictionary).get("track_id", "")) == tid:
			return raw
	return {}


func ship_fields(row: Dictionary, page := "ship") -> Dictionary:
	if page == "target":
		var tr := selected_track(row)
		if tr.is_empty():
			return {"title": "TARGET NOT READY", "source": "NO TRACK DATA", "lines": ["target track 未就绪", "不伪造目标"]}
		var sources: Array = tr.get("sources", []) if tr.get("sources", []) is Array else []
		var tlines: Array = ["LEVEL L%d / %s" % [int(tr.get("level", 0)), String(tr.get("level_name", ""))],
			"IDENTITY %s · THREAT %s" % [String(tr.get("identity_label", tr.get("identity", " — "))), String(tr.get("threat", "—"))],
			"SOURCES " + ",".join(sources), "RANGE %.1f km" % float(tr.get("range_km", -1.0))]
		var ss := sensor_state()
		tlines.append("SENSOR " + ("RADAR ON" if bool(ss.get("radar", false)) else "RADAR OFF") + " · EMCON " + str(bool(ss.get("emcon", false))) + " · OBS " + str(int(ss.get("obs", 0))) + " · IFF " + str(int(ss.get("iff", 0))))
		return {"title": "TRACK %s · TARGET" % String(tr.get("track_id", "")), "source": "TRACK TABLE · SENSOR", "lines": tlines}
	var e := selected_entity(row)
	var tr2 := selected_track(row)
	if e.is_empty():
		return {"title": "SHIP NOT READY", "source": "NO ENTITY DATA", "lines": ["session entity 未就绪", "不伪造舰船"]}
	var flags: Dictionary = e.get("flags", {}) if e.get("flags", {}) is Dictionary else {}
	var pos: Array = e.get("pos_km", []) if e.get("pos_km", []) is Array else []
	var range_km := 0.0
	var flag_pos: Array = []
	for raw in (snapshot.get("entities", []) if snapshot.get("entities", []) is Array else []):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == "apsis":
			flag_pos = (raw as Dictionary).get("pos_km", []) if (raw as Dictionary).get("pos_km", []) is Array else []
			break
	if pos.size() >= 3 and flag_pos.size() >= 3:
		var dx := float(pos[0]) - float(flag_pos[0]); var dy := float(pos[1]) - float(flag_pos[1]); var dz := float(pos[2]) - float(flag_pos[2])
		range_km = sqrt(dx * dx + dy * dy + dz * dz)
	var lines: Array = []
	lines.append("BATCH %s · %s · %s" % [String(e.get("batch", e.get("id", ""))), String(e.get("kind", "ship")).to_upper(), "FLAGSHIP" if bool(flags.get("flagship", false)) else "FRIEND"])
	lines.append("RANGE %.1f km %s" % [range_km, "· track L%d" % int(tr2.get("level", 0)) if not tr2.is_empty() else "· track NOT READY"])
	var sens_lines: Array = []
	if session.sensor_service != null:
		var svm: Dictionary = session.sensor_service.vm()
		var counts: Dictionary = svm.get("counts", {}) if svm.get("counts", {}) is Dictionary else {}
		sens_lines.append("RADAR %s · EMCON %s · OBS %d" % ["ON" if bool(svm.get("radar_enabled", false)) else "OFF", str(bool(svm.get("emcon", false))), int(counts.get("observations", 0))])
		sens_lines.append("IFF EVID %d · OPTICAL EVID %d · CH %d" % [int(counts.get("iff_evidence", 0)), int(counts.get("optical_evidence", 0)), int(counts.get("channels", 0))])
	else:
		sens_lines.append("SENSOR NOT READY · sensor_service 未启用")
	for sl in sens_lines:
		lines.append(sl)
	lines.append("DAMAGE NOT READY · 无 damage 组件")
	lines.append("ROE " + roe_text)
	lines.append("Δv " + ("%.1f m/s · transfer cache" % delta_v_mps if delta_v_ready else "NOT READY"))
	return {"title": String(e.get("name", "NOT READY")), "source": "GAME SESSION · TRACK", "lines": lines}


func sensor_command(kind: String) -> Dictionary:
	if session == null or session.sensor_service == null:
		return {"ok": false, "reason": "sensor_not_ready", "text": "SENSOR NOT READY"}
	var s = session.sensor_service
	var res: Dictionary = {}
	match kind:
		"RADAR":
			res = s.set_radar_enabled(not bool(s.radar_enabled))
		"EMCON":
			res = s.set_emcon(not bool(s.emcon))
		"IFF":
			var tid := String(s.selected_target) if String(s.selected_target) != "" else "harmattan"
			res = s.query_iff(tid)
		"VIS":
			res = s.start_channel("optical", String(s.selected_target) if String(s.selected_target) != "" else "harmattan", {"mode": "vis"})
		"IR":
			res = s.start_channel("ir", String(s.selected_target) if String(s.selected_target) != "" else "harmattan", {})
		_:
			res = {"ok": false, "reason": "unknown_sensor_command"}
	sensor_result = "%s · %s" % [kind, "OK" if bool(res.get("ok", false)) else String(res.get("reason", "FAILED"))]
	refresh()
	return res


func sensor_state() -> Dictionary:
	if session == null or session.sensor_service == null:
		return {"ready": false, "text": "SENSOR NOT READY"}
	var s = session.sensor_service
	var svm: Dictionary = s.vm()
	var counts: Dictionary = svm.get("counts", {}) if svm.get("counts", {}) is Dictionary else {}
	return {"ready": bool(s.ready), "radar": bool(s.radar_enabled), "emcon": bool(s.emcon),
		"obs": int(counts.get("observations", 0)), "iff": int(counts.get("iff_evidence", 0)),
		"optical": int(counts.get("optical_evidence", 0)), "channels": int(counts.get("channels", 0))}


func save(intent: String) -> Dictionary:
	var res: Dictionary = save_service.save_with_intent(session, intent, {"chapter": "stage1f", "location": "game_shell"}) if save_service != null else {"ok": false, "reason": "save_service_not_ready"}
	last_save_ok = bool(res.get("ok", false))
	last_save_text = ""
	if last_save_ok:
		last_save_text = "SAVED slot=%s · %sB · %s" % [String(res.get("slot", "")), str(int(res.get("bytes", 0))), String(res.get("checksum", "")).substr(0, 8)]
		if intent == "save_and_menu":
			last_save_text += " · should_show_menu=" + str(bool(res.get("should_show_menu", false)))
		elif intent == "save_and_quit":
			last_save_text += " · should_exit=" + str(bool(res.get("should_exit", false)))
	else:
		last_save_text = "SAVE FAILED · " + String(res.get("reason", "not_ready"))
	return res


func tick(delta: float) -> void:
	if session != null:
		session.tick(delta)


func seed_timers() -> void:
	if session == null or session.bus == null:
		return
	for item in [["变轨窗口 / BURN WINDOW", 30.0, "burn"], ["入轨 / ARRIVAL", 120.0, "arrival"], ["链路 / LINK", 15.0, "link"]]:
		session.bus.publish({"type": "tactical.timer", "t": session.now_s(), "source": "game_shell",
			"target": "top_bar", "payload": {"label": String(item[0]), "duration_s": float(item[1]), "kind": String(item[2])}})


func timers() -> Array:
	if session == null or session.bus == null:
		return []
	var out: Array = []
	var now: float = session.now_s()
	var evs: Array = session.bus.filter_events({"type": "tactical.timer"}, -1, false)
	for raw in evs:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var p: Dictionary = e.get("payload", {}) if e.get("payload", {}) is Dictionary else {}
		var duration := maxf(0.1, float(p.get("duration_s", 1.0)))
		var deadline := float(e.get("t", 0.0)) + duration
		if deadline > now + 1.0e-9:
			out.append({"label": String(p.get("label", "TIMER")), "remain": deadline - now, "total": duration, "kind": String(p.get("kind", ""))})
	while out.size() > 4:
		out.pop_front()
	return out


func ceres_state() -> String:
	return String(ceres_chain.current_state()) if ceres_chain != null else "NOT READY"


func ceres_vm() -> Dictionary:
	return ceres_chain.vm() if ceres_chain != null else {}


func ceres_text(text_key: String) -> String:
	if ceres_chain == null:
		return ""
	var t: Dictionary = ceres_chain.text(text_key)
	return String(t.get("zh", ""))


func ceres_emergency_code() -> String:
	return String(ceres_chain.emergency_light_code) if ceres_chain != null else ""


func ceres_ingest(input: Dictionary) -> Dictionary:
	if ceres_chain == null:
		return {"ok": false, "reason": "no_ceres_chain"}
	return ceres_chain.ingest(input)


func ceres_advance(action: String, payload := {}) -> Dictionary:
	if ceres_chain == null:
		return {"ok": false, "reason": "no_ceres_chain"}
	var res: Dictionary = ceres_chain.advance(action, payload)
	last_ceres_result = res.duplicate(true)
	print("[SHELL BINDER] CERES ", action, " · ", str(res.get("ok", false)), " state=", String(res.get("state", ceres_chain.current_state())), " trigger=", String(res.get("trigger_id", "")))
	return last_ceres_result


func ceres_rescue(choice: String) -> Dictionary:
	return ceres_advance(choice, {})


func transponder_query(target: String, mode := "mode_s", opts := {}) -> Dictionary:
	if session == null:
		return {"ok": false, "reason": "no_session", "reply": null}
	if session.transponder_service == null:
		return {"ok": false, "reason": "no_transponder_service", "reply": null}
	# prelude 的 profile_id 与 entity_id 可能不同（ceres_2_demo）；按 entity 反查 profile_id。
	var query_id := target
	if not (target in session.transponder_service.profiles):
		for pid in session.transponder_service.profiles.keys():
			var p: Dictionary = session.transponder_service.profiles[pid] if session.transponder_service.profiles[pid] is Dictionary else {}
			if String(p.get("entity_id", "")) == target:
				query_id = String(pid)
				break
	var res: Dictionary = session.transponder_interrogate("apsis", query_id, mode, opts if opts is Dictionary else {})
	res["query_target_id"] = query_id
	res["requested_target_id"] = target
	last_transponder_reply = res.duplicate(true)
	return last_transponder_reply


func signal_event(type: String, target := "", payload := {}) -> void:
	if session != null and session.bus != null:
		session.bus.publish({"type": type, "t": session.now_s(), "source": "game_shell", "target": target, "payload": payload})
