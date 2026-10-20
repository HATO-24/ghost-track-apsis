extends RefCounted

# 阶段1F 正式 UI Shell 的真实数据绑定层。
# - GameSession（可选 track_table/story_state）；SaveService user://saves；
# - track_vm/entities → 接触；orders → 命令队列；session.bus → 事件；
# - 真实 Δv/ROE 优先读取内容缓存/story_state；缺失明确 NOT READY。
# 不实现剧情/物理；不写旧场景。

const GameSession := preload("res://scripts/core/game_session.gd")
const SaveService := preload("res://scripts/core/save_service.gd")

const TRANSFER_CACHE := "res://framework/content/transfer_l4_l1_cached.json"
const SAVE_ROOT := "user://saves"

var session = null
var save_service = null
var ready := false
var errors: Array[String] = []
var warnings: Array[String] = []
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
	var br: Dictionary = session.boot({
		"track_table": true,
		"story_state": true,
		"sensor_service": sensor_cfg,
		"signal_service": true,
		"orders": [
			{"action": "HOLD", "issuer_id": "apsis", "target_ids": ["harmattan"], "issue": true, "opts": {"auth_required": false}},
		],
	})
	if not bool(br.get("ok", false)):
		errors.append("GameSession boot failed: " + str(br.get("reason", "")))
		return false
	save_service = SaveService.new(SAVE_ROOT)
	if not bool(save_service.setup(SAVE_ROOT)):
		errors.append("SaveService setup failed")
		return false
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
		var ttype := "friendly" if identity in ["friend", "assumed_friend"] else ("unknown" if identity in ["unknown", "pending"] else "neutral")
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
			"type": ttype, "side": identity, "threat": String(tr.get("threat", "unknown")),
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
		rows.append({"id": String(e.get("batch", eid)), "entity_id": String(eid), "track_id": "",
			"name": String(e.get("name", eid)), "cls": kind.to_upper(),
			"type": "station" if kind == "station" else "friendly", "side": "friend",
			"threat": "none", "badge": "ENTITY", "level": 0, "range_km": -1.0, "sources": []})
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


func signal_event(type: String, target := "", payload := {}) -> void:
	if session != null and session.bus != null:
		session.bus.publish({"type": type, "t": session.now_s(), "source": "game_shell", "target": target, "payload": payload})
