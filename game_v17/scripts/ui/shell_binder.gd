extends RefCounted

# 阶段1F 正式 UI Shell 的真实数据绑定层。
# - GameSession（可选 track_table/story_state）；SaveService user://saves；
# - track_vm/entities → 接触；orders → 命令队列；session.bus → 事件；
# - 真实 Δv/ROE 优先读取内容缓存/story_state；缺失明确 NOT READY。
# 不实现剧情/物理；不写旧场景。

const GameSession := preload("res://scripts/core/game_session.gd")
const PreludeScenario := preload("res://scripts/core/prelude_scenario.gd")
const CeresChain := preload("res://scripts/core/ceres_chain.gd")
const ChronosChain := preload("res://scripts/core/chronos_chain.gd")
const AV4412Chain := preload("res://scripts/core/av4412_chain.gd")
const AfterActionReport := preload("res://scripts/core/after_action_report.gd")
const TrafficControlService := preload("res://scripts/core/traffic_control_service.gd")
const CICView := preload("res://scripts/core/cic_view.gd")
const IdentificationService := preload("res://scripts/core/identification_service.gd")
const SaveService := preload("res://scripts/core/save_service.gd")
const BuildProfile := preload("res://scripts/core/build_profile.gd")

const TRANSFER_CACHE := "res://framework/content/transfer_l4_l1_cached.json"
const SAVE_ROOT := "user://saves"
const SANDBOX_DEFAULT_SCENARIO := "res://framework/content/scenario_combat_sandbox.json"

var session = null
var save_service = null
var build_profile = null
var save_root := SAVE_ROOT
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
var chronos_chain = null
var chronos_ready := false
var last_chronos_result: Dictionary = {}
var chronos_comms_lines: Array = []
var av4412_chain = null
var av4412_ready := false
var last_av4412_result: Dictionary = {}
var av4412_comms_lines: Array = []
var after_action = null
var report_ready := false
var report_comms_lines: Array = []
var traffic_service = null
var traffic_ready := false
var traffic_source := ""
var traffic_comms_lines: Array = []
var cic_view = null
var cic_ready := false
var cic_vm: Dictionary = {}
var _cic_logged := false
var _ident_logged := false
var load_slot_requested := ""
var load_ok := false
var load_error := ""
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


func _load_requested_slot(slot: String) -> void:
	load_ok = false
	load_error = ""
	if save_service == null:
		load_error = "no_save_service"
		return
	var raw: Dictionary = save_service.call("_read_slot_raw", slot)
	if not bool(raw.get("ok", false)):
		load_error = String(raw.get("reason", "read_failed"))
		errors.append("LOAD slot=" + slot + " failed: " + load_error)
		print("[SHELL BINDER] LOAD FAILED slot=", slot, " reason=", load_error)
		return
	var payload: Dictionary = raw.get("payload", {}) if raw.get("payload", {}) is Dictionary else {}
	var save_text := String(payload.get("session_save", ""))
	if save_text == "":
		load_error = "empty_session_save"
		errors.append("LOAD slot=" + slot + " failed: " + load_error)
		return
	var parsed = JSON.parse_string(save_text)
	if parsed is Dictionary:
		var seed: Dictionary = parsed.get("seed", {}) if parsed.get("seed", {}) is Dictionary else {}
		if not seed.has("combat_service"):
			seed["combat_service"] = {}
			parsed["seed"] = seed
			save_text = JSON.stringify(parsed)
	var lr: Dictionary = session.load_state(save_text)
	if not bool(lr.get("ok", false)):
		load_error = String(lr.get("reason", "session_load_failed"))
		errors.append("LOAD slot=" + slot + " failed: " + load_error)
		print("[SHELL BINDER] LOAD FAILED slot=", slot, " reason=", load_error)
		return
	load_ok = true
	if String(load_slot_requested) != "":
		OS.set_environment("DSH_LOAD_SLOT", "")
	print("[SHELL BINDER] LOAD OK slot=", slot, " t=", session.now_s())


func boot() -> bool:
	errors.clear()
	warnings.clear()
	# 版本剖面：full（剧情本体）/ combat_sim（作战模拟器）。读不到就回退 full。
	build_profile = BuildProfile.new()
	build_profile.setup({})
	for w in (build_profile.warnings as Array):
		warnings.append("build_profile: " + String(w))
	save_root = String(build_profile.save_root)
	print("[SHELL BINDER] BUILD profile=", String(build_profile.id),
		" mode=", String(build_profile.boot_mode),
		" label=", String(build_profile.label),
		" save_root=", save_root)
	session = GameSession.new()
	var sensor_cfg := _sensor_config()
	var seed: Dictionary = {}
	prelude = PreludeScenario.new()
	prelude.setup({})
	prelude_ready = bool(prelude.ready)
	used_prelude = false
	if build_profile.is_sandbox():
		# 作战模拟器：不跑序章，直接装 sandbox 场景（真实地月系几何）
		seed = _sandbox_seed(sensor_cfg)
		if seed.is_empty():
			warnings.append("sandbox seed 为空，回退序章")
			build_profile.boot_mode = "prelude"
		else:
			print("[SHELL BINDER] SANDBOX entities=",
				(seed.get("entities", []) as Array).size(),
				" scenario=", String(build_profile.scenario))
	if seed.is_empty() and prelude_ready:
		var pcfg: Dictionary = prelude.boot_config()
		if not pcfg.is_empty():
			seed = pcfg
			seed["track_table"] = true
			seed["story_state"] = true
			seed["sensor_service"] = sensor_cfg
			seed["traffic_control"] = true
			seed["orders"] = [
				{"action": "HOLD", "issuer_id": "apsis", "target_ids": ["harmattan"], "issue": true, "opts": {"auth_required": false}},
			]
			seed["physics_world"] = true
			seed["ew_service"] = true
			# 本舰实体：序章以 signal_service.observer 为准（与传感器/信号服务同一艘），
			# 弹道服务据此解析 shooter 与 PD 平台，不能留空。
			seed["own_entity"] = String(((pcfg.get("signal_service", {}) as Dictionary).get("observer", {}) as Dictionary).get("id", "apsis"))
			# 交战物理闭环：真实弹道/引导头/齐射/对抗。缺了它开火只能退化到接口层。
			seed["combat_ballistics"] = {"pd_platform_id": "own"}
			# 识别融合：默认关闭自动询问（避免开局静默产生应答机询问副作用）；
			# UI 侧 IDENT 弹层可手动 INTERROGATE 或打开 AUTO。
			seed["identification_service"] = {"auto": {"enabled": false, "interval_s": 10.0,
				"modes": ["mode_s"], "min_confidence": 0.75, "min_age_s": 3.0,
				"max_requests_per_tick": 2}}
			used_prelude = true
			prelude_title = String(prelude.content.get("title", "序章"))
			prelude_triggers = prelude.triggers.duplicate(true)
			print("[SHELL BINDER] prelude ready=true entities=", prelude.entities.size(), " triggers=", prelude.triggers.size(), " used=true")
	elif seed.is_empty():
		# 只有「既没有 sandbox seed，序章也不 ready」才算真回退
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
			"identification_service": {"auto": {"enabled": false}},
			"traffic_control": true,
			"physics_world": true,
			"combat_ballistics": {"pd_platform_id": "own"},
			"orders": [
				{"action": "HOLD", "issuer_id": "apsis", "target_ids": ["harmattan"], "issue": true, "opts": {"auth_required": false}},
			],
		}
	var br: Dictionary = session.boot(seed)
	if not bool(br.get("ok", false)):
		errors.append("GameSession boot failed: " + str(br.get("reason", "")))
		return false
	save_service = SaveService.new(save_root)
	if not bool(save_service.setup(save_root)):
		errors.append("SaveService setup failed")
		return false
	# 主菜单指定 load slot：优先 raw payload + 当前已 boot 的可选组件 load_state。
	var req_slot := OS.get_environment("DSH_LOAD_SLOT")
	if req_slot == "":
		var ml = Engine.get_main_loop()
		if ml is SceneTree and (ml as SceneTree).root != null and (ml as SceneTree).root.has_meta("load_slot"):
			req_slot = String((ml as SceneTree).root.get_meta("load_slot", ""))
	load_slot_requested = req_slot
	if req_slot != "":
		_load_requested_slot(req_slot)
	ceres_chain = CeresChain.new()
	var cerr: bool = ceres_chain.setup({"content_path": CeresChain.DEFAULT_CONTENT})
	ceres_ready = cerr
	if not cerr:
		warnings.append("CeresChain 未 ready：" + str(ceres_chain.errors))
	else:
		print("[SHELL BINDER] CeresChain ready state=", ceres_chain.current_state(), " entity=", ceres_chain.entity_id, " texts=", ceres_chain.text_keys.size(), " code=", ceres_chain.emergency_light_code)
	chronos_chain = ChronosChain.new()
	var chr: bool = chronos_chain.setup({"content_path": ChronosChain.DEFAULT_CONTENT})
	chronos_ready = chr
	if not chr:
		warnings.append("ChronosChain 未 ready：" + str(chronos_chain.errors))
	else:
		print("[SHELL BINDER] ChronosChain ready state=", chronos_chain.current_state(), " entity=", chronos_chain.entity_id, " texts=", chronos_chain.text_keys.size(), " trust=", chronos_chain.get_trust())
	av4412_chain = AV4412Chain.new()
	var avr: bool = av4412_chain.setup({"content_path": AV4412Chain.DEFAULT_CONTENT})
	av4412_ready = avr
	if not avr:
		warnings.append("AV4412Chain 未 ready：" + str(av4412_chain.errors))
	else:
		print("[SHELL BINDER] AV4412Chain ready state=", av4412_chain.current_state(), " entity=", av4412_chain.entity_id, " texts=", av4412_chain.text_keys.size(), " threat=", av4412_chain.get_threat(), " trust=", av4412_chain.get_trust())
	after_action = AfterActionReport.new()
	var rpt: bool = after_action.setup({"content_path": AfterActionReport.DEFAULT_CONTENT})
	report_ready = rpt
	if not rpt:
		warnings.append("AfterActionReport 未 ready：" + str(after_action.errors))
	else:
		print("[SHELL BINDER] AfterActionReport ready branches=", after_action.branch_ids().size(), " templates=", after_action.report_templates.size())
	if session != null and session.get("traffic_control") != null:
		traffic_service = session.get("traffic_control")
		traffic_source = "session"
		traffic_ready = bool(traffic_service.ready) if traffic_service.get("ready") != null else true
	else:
		traffic_service = TrafficControlService.new({"facilities_path": "res://framework/content/facilities_system.json", "lanes_path": "res://framework/content/lanes_system.json"})
		traffic_source = "direct-fallback"
		traffic_ready = bool(traffic_service.ready)
	if not traffic_ready:
		warnings.append("TrafficControlService 未 ready：" + str(traffic_service.errors))
	else:
		print("[SHELL BINDER] TrafficControl source=", traffic_source, " ready=", traffic_ready, " lanes=", traffic_service.lanes_list.size(), " otc=", traffic_service.otc_satellites.size(), " npc=", traffic_service.npc_ships.size())
	if session.sensor_service == null:
		_seed_tracks()
	_load_delta_v()
	# 先推进一小步让 SensorService→TrackTable 产生真实 L1-L2 观测；失败仍显式 NOT READY。
	if session.sensor_service != null:
		session.tick(0.1)
	var _pp: Dictionary = plot_positions()
	var _pf: Dictionary = plot_facilities()
	print("[SHELL BINDER] physics ready=", physics_world_ready(), " plot_source=", String(_pp.get("source", "")), " positions=", (_pp.get("positions", []) as Array).size(), " facilities=", (_pf.get("facilities", []) as Array).size(), " facility_source=", String(_pf.get("source", "")))
	refresh()
	ready = errors.is_empty()
	return ready


## 沙盒便利：一键按原场景重开（仅 sandbox_opts.quick_restart 开启的剖面）。
## 与 session.reset() 的区别：reset 只重建 session 内部服务，binder 缓存的
## traffic_service/track_vm/contacts 等仍指向旧对象；这里走完整 boot() 让缓存一并重建。
## HUD 不缓存 session（一律经 binder.session 取），所以换掉 session 对象是安全的。
func quick_restart() -> Dictionary:
	if build_profile == null or not build_profile.sandbox_opt("quick_restart", false):
		return {"ok": false, "reason": "not_allowed"}
	var prev_t := float(session.now_s()) if session != null else 0.0
	# 重开必须是全新场景，不能顺手把刚才的存档读回来
	OS.set_environment("DSH_LOAD_SLOT", "")
	var ml = Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null and (ml as SceneTree).root.has_meta("load_slot"):
		(ml as SceneTree).root.remove_meta("load_slot")
	load_slot_requested = ""
	var ok := boot()
	var now_t := float(session.now_s()) if session != null else 0.0
	print("[SHELL BINDER] QUICK RESTART ok=", ok, " t_before=", prev_t, " t_after=", now_t)
	return {"ok": ok, "reason": "" if ok else "boot_failed",
		"t_before": prev_t, "t_after": now_t, "errors": errors.duplicate()}


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


## 作战模拟器：把 sandbox 场景（真实地月系几何）翻成 session seed。
## 不启序章/剧情/触发器；其余系统按版本剖面开关装。
func _sandbox_seed(sensor_cfg: Dictionary) -> Dictionary:
	var path := String(build_profile.scenario)
	if path == "":
		path = SANDBOX_DEFAULT_SCENARIO
	var sc := _read_json(path)
	if sc.is_empty():
		warnings.append("sandbox 场景不可读：" + path)
		return {}
	var ents: Array = sc.get("entities", []) if sc.get("entities") is Array else []
	if ents.is_empty():
		warnings.append("sandbox 场景无实体：" + path)
		return {}
	var cb: Dictionary = sc.get("combat", {}) if sc.get("combat") is Dictionary else {}
	var own := String(sc.get("own_entity", "apsis"))
	var seed := {
		"entities": ents.duplicate(true),
		"nodes": (sc.get("nodes", []) as Array).duplicate(true) if sc.get("nodes") is Array else [],
		"links": (sc.get("links", []) as Array).duplicate(true) if sc.get("links") is Array else [],
		"orders": [],
		"own_entity": own,
		"track_table": true,
		"sensor_service": sensor_cfg,
		"physics_world": build_profile.enabled("physics_world"),
		"combat_service": {"content_path": "res://framework/content/weapons_l1.json",
			"roe": String(cb.get("roe", "TIGHT")),
			"own_id": String(cb.get("own_id", own)),
			"fleet_id": String(cb.get("fleet_id", "fleet")),
			# 沙盒便利项：只在 sandbox 剖面生效（build_profile 对 full 恒返回 false）
			"unlimited_ammo": build_profile.sandbox_opt("unlimited_ammo", false),
			"auto_authorize": build_profile.sandbox_opt("auto_authorize", false)},
		"combat_ballistics": {"pd_platform_id": String(cb.get("pd_platform_id", "own"))},
		"damage_service": build_profile.enabled("damage"),
		"ew_service": build_profile.enabled("combat"),
		"identification_service": {"auto": {"enabled": false, "interval_s": 10.0,
			"modes": ["mode_s"], "min_confidence": 0.75, "min_age_s": 3.0,
			"max_requests_per_tick": 2}},
		"traffic_control": build_profile.enabled("traffic"),
		"prelude": {"scenario": "combat_sandbox",
			"title": String(sc.get("title", "作战演练"))},
		# sandbox 场景坐标已是 bary_rot 绝对坐标，禁止再做 L1 相对帧转换
		"seed_frame": String(sc.get("frame", "bary_rot")),
		"frame_origin": "bary_rot",
	}
	# 信号/灯语：观测者=本舰，目标=全部实体（与序章同构，供 OPTICAL/ELINT 链路使用）
	if build_profile.enabled("signal"):
		var sig_targets: Array = []
		var own_pos: Array = [0.0, 0.0, 0.0]
		for raw_e in ents:
			var e: Dictionary = raw_e
			var eid := String(e.get("id", ""))
			var epos: Array = e.get("pos_km", [0.0, 0.0, 0.0])
			if eid == own:
				own_pos = epos.duplicate()
			sig_targets.append({"id": eid, "entity_id": eid,
				"batch": String(e.get("batch", "")),
				"side": _signal_side(String(e.get("side", ""))),
				"identity": String(e.get("identity", "unknown")),
				"pos_km": epos.duplicate(),
				"occluded": false, "light_capable": bool(e.get("light_capable", true)),
				"receiver_facing": true})
		seed["signal_service"] = {"observer": {"id": own, "pos_km": own_pos},
			"targets": sig_targets, "jam": 0.0, "max_range_km": 20000.0}
	if build_profile.enabled("story"):
		seed["story_state"] = true
	return seed


func _signal_side(side: String) -> String:
	match side.to_lower():
		"friend", "ally":
			return "friend"
		"hostile":
			return "hostile"
		"neutral", "civilian":
			return "neutral"
		_:
			return "unknown"


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


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
	_refresh_cic()
	contacts = _build_contacts()
	_sync_signal_targets()
	commands = _build_commands()
	events = session.bus.recent(8) if session.bus != null else []
	# ROE：真实 story_state 存在时显示默认交战规则；不伪造裁决。
	if session.story_state != null and bool(story_vm.get("ready", false)):
		roe_text = "WEAPONS HOLD / 仅自衛 · phase " + String(story_vm.get("phase", "—"))
	elif session.combat_service != null:
		var cv: Dictionary = session.combat_service.vm()
		roe_text = "ROE %s / %s" % [String(cv.get("roe_label", cv.get("roe", "—"))),
			String(cv.get("roe_label_en", ""))]
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
		var row := {
			"id": bid,
			"entity_id": eid, "track_id": String(tr.get("track_id", "")),
			"name": name, "cls": "TRACK %s · L%d" % [String(tr.get("track_id", "")), int(tr.get("level", 0))],
			"type": ttype, "side": tside, "identity": identity, "threat": String(tr.get("threat", "unknown")),
			"badge": "TRACK", "level": int(tr.get("level", 0)),
			"range_km": float(tr.get("range_km", -1.0)), "sources": sources,
		}
		# 识别融合：列表行只带轻量评估（不拉证据数组，避免每帧复制）。
		var iv: Dictionary = ident_view(row)
		row["ident"] = {"known": bool(iv.get("known", false)),
			"identity": String(iv.get("identity", "unknown")),
			"confidence": float(iv.get("confidence", 0.0)),
			"tag": String(iv.get("tag", "—")), "warn": bool(iv.get("warn", false)),
			"manual": bool(iv.get("manual", false)), "enabled": bool(iv.get("enabled", false)),
			"contradictions": (iv.get("contradictions", []) as Array).size(),
			"spoof": float(iv.get("spoof", 0.0))}
		rows.append(row)
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
		# 天体/物理基准不是接触；不得出现在 CONTACTS（Earth/Moon 由 PhysicsWorld 种入）
		if kind in ["body", "planet", "moon", "star", "celestial", "anchor"] 				or String(eid) in ["earth", "moon", "sun", "luna"]:
			continue
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
	# 识别融合：所有行统一带 ident 结构（track 行已在上面按评估填充）；无证据即 known=false。
	for row2 in rows:
		var rr0: Dictionary = row2
		if rr0.has("ident"):
			continue
		rr0["ident"] = {"known": false, "identity": String(rr0.get("identity", "unknown")),
			"confidence": 0.0, "tag": "—", "warn": false, "manual": false,
			"enabled": ident_enabled(), "contradictions": 0, "spoof": 0.0}
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
		# 识别融合行：来自 IdentificationService 评估（truth=false），未启用/无证据时明示。
		var iv := ident_view(row)
		if not bool(iv.get("enabled", false)):
			tlines.append("IDENT FUSION NOT READY · identification_service 未启用")
		elif not bool(iv.get("known", false)):
			tlines.append("IDENT FUSION NO EVIDENCE · 需 INTERROGATE/IFF")
		else:
			tlines.append("IDENT %s %.2f · %s%s" % [String(iv.get("identity", "")).to_upper(),
				float(iv.get("confidence", 0.0)),
				",".join(iv.get("sources", []) if iv.get("sources", []) is Array else []),
				(" · ⚠%d" % (iv.get("contradictions", []) as Array).size()) if not (iv.get("contradictions", []) as Array).is_empty() else ""])
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


func traffic_vm() -> Dictionary:
	return traffic_service.vm() if traffic_service != null else {}


func traffic_lane(lane_id: String) -> Dictionary:
	return traffic_service.lane(lane_id) if traffic_service != null else {}


func traffic_lane_rows() -> Array:
	if traffic_service == null:
		return []
	var out: Array = []
	for lid in traffic_service.lanes_list:
		var lane_row: Dictionary = traffic_service.lane(String(lid))
		if not lane_row.is_empty():
			out.append(lane_row)
	return out


func traffic_otc_rows() -> Array:
	if traffic_service == null:
		return []
	return traffic_service.otc_satellites.duplicate(true)


func traffic_npc_rows() -> Array:
	if traffic_service == null:
		return []
	var out: Array = []
	for raw in traffic_service.npc_ships.values():
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


func traffic_request(track_id: String, lane_id: String, opts := {}) -> Dictionary:
	if traffic_service == null:
		return {"ok": false, "reason": "no_traffic_service"}
	var res: Dictionary = traffic_service.request_clearance(track_id, lane_id, opts)
	traffic_comms_lines.append("[OTC 至 " + track_id + "]-[RDO]-[REQUEST " + lane_id + " · " + ("OK " + String(res.get("request_id", "")) if bool(res.get("ok", false)) else "FAILED " + String(res.get("reason", ""))) + "]")
	return res


func traffic_permit(request_id: String, opts := {}) -> Dictionary:
	if traffic_service == null:
		return {"ok": false, "reason": "no_traffic_service"}
	var res: Dictionary = traffic_service.permit(request_id, opts)
	traffic_comms_lines.append("[OTC 至 " + request_id + "]-[RDO]-[PERMIT · " + ("OK " + String(res.get("clearance_id", "")) if bool(res.get("ok", false)) else "FAILED " + String(res.get("reason", ""))) + "]")
	return res


func traffic_occupy(lane_id: String, occupant: String, opts := {}) -> Dictionary:
	if traffic_service == null:
		return {"ok": false, "reason": "no_traffic_service"}
	var res: Dictionary = traffic_service.occupy(lane_id, occupant, opts)
	traffic_comms_lines.append("[OTC 至 " + occupant + "]-[RDO]-[OCCUPY " + lane_id + " · " + ("OK " + String(res.get("occupancy_id", "")) if bool(res.get("ok", false)) else "FAILED " + String(res.get("reason", ""))) + "]")
	return res


func traffic_release(lane_id: String, occupant := "") -> Dictionary:
	if traffic_service == null:
		return {"ok": false, "reason": "no_traffic_service"}
	var res: Dictionary = traffic_service.release(lane_id, occupant)
	traffic_comms_lines.append("[OTC 至 " + occupant + "]-[RDO]-[RELEASE " + lane_id + " · " + ("OK" if bool(res.get("ok", false)) else "FAILED " + String(res.get("reason", ""))) + "]")
	return res


func traffic_disguise(track_id: String, disguise: Dictionary, opts := {}) -> Dictionary:
	if traffic_service == null:
		return {"ok": false, "reason": "no_traffic_service"}
	var res: Dictionary = traffic_service.record_disguise(track_id, disguise, opts)
	traffic_comms_lines.append("[DISGUISE " + track_id + "]-[RDO]-[" + ("DETECTED" if bool(res.get("detected", false)) else "ACTIVE") + " · anomalies " + str((res.get("anomalies", []) as Array).size()) + "]")
	return res


func traffic_clues(track_id := "") -> Array:
	return traffic_service.clues_for(track_id) if traffic_service != null else []


func plot_fire_control() -> Dictionary:
	var out: Dictionary = {"ready": false, "roe": "—", "weapons": [], "tracks": [], "solutions": [], "grants": [],
		"incoming": [], "counts": {}, "selected_target": "", "selected_weapon": "", "prediction": {}, "authorization": {},
		"source": "COMBAT NOT READY"}
	var cs = session.combat_service if session != null else null
	if cs == null:
		return out
	var vm: Dictionary = cs.vm()
	out["ready"] = bool(vm.get("ready", false))
	out["roe"] = String(vm.get("roe_label_en", vm.get("roe", "—")))
	out["weapons"] = (vm.get("weapons", []) as Array).duplicate(true) if vm.get("weapons", []) is Array else []
	out["tracks"] = (vm.get("tracks", []) as Array).duplicate(true) if vm.get("tracks", []) is Array else []
	out["solutions"] = (vm.get("solutions", []) as Array).duplicate(true) if vm.get("solutions", []) is Array else []
	out["grants"] = (vm.get("grants", []) as Array).duplicate(true) if vm.get("grants", []) is Array else []
	out["incoming"] = (vm.get("incoming", []) as Array).duplicate(true) if vm.get("incoming", []) is Array else []
	out["counts"] = (vm.get("counts", {}) as Dictionary).duplicate(true) if vm.get("counts", {}) is Dictionary else {}
	var target := ""
	for raw in out["tracks"]:
		if raw is Dictionary and not bool((raw as Dictionary).get("destroyed", false)):
			target = String((raw as Dictionary).get("id", ""))
			break
	var weapon := ""
	for raw2 in out["weapons"]:
		if raw2 is Dictionary and String((raw2 as Dictionary).get("kind", "")) in ["kinetic", "guided"]:
			weapon = String((raw2 as Dictionary).get("id", ""))
			break
	out["selected_target"] = target
	out["selected_weapon"] = weapon
	if target != "" and weapon != "":
		out["prediction"] = cs.predict_shot(target, weapon)
		out["authorization"] = cs.check_authorization("FIRE", target, weapon)
	out["source"] = "COMBAT SERVICE / TRACK VM / WEAPONS"
	print("[SHELL BINDER] plot_fire_control ready=", out["ready"], " roe=", out["roe"], " weapons=", (out["weapons"] as Array).size(), " tracks=", (out["tracks"] as Array).size(), " solutions=", (out["solutions"] as Array).size(), " grants=", (out["grants"] as Array).size(), " incoming=", (out["incoming"] as Array).size(), " pred=", str(out["prediction"].get("ok", false)))
	return out


func plot_commands() -> Dictionary:
	var out: Dictionary = {"ready": false, "orders": [], "pending": 0, "transmitted": 0, "nodes": [], "source": "ORDERS NOT READY"}
	if session == null or session.orders == null:
		return out
	var vm: Dictionary = session.orders.vm()
	out["ready"] = bool(vm.get("ready", false))
	var orders: Array = (vm.get("orders", []) as Array).duplicate(true) if vm.get("orders", []) is Array else []
	out["orders"] = orders
	out["pending"] = (vm.get("pending_orders", []) as Array).size() if vm.get("pending_orders", []) is Array else 0
	var transmitted := 0
	var executed := 0
	var nodes: Array = []
	# CIC/physics target positions（仅已知/估计，不读 truth）
	var pos_rows: Dictionary = {}
	var pp: Dictionary = plot_positions()
	for rawp in (pp.get("positions", []) as Array):
		if rawp is Dictionary:
			pos_rows[String((rawp as Dictionary).get("id", ""))] = (rawp as Dictionary).get("pos_km", [])
	for raw in orders:
		if not (raw is Dictionary):
			continue
		var o: Dictionary = raw
		var st := String(o.get("status", ""))
		if st in ["DELIVERED", "PENDING_EFFECT", "AUTHORIZED", "EXECUTING", "COMPLETE", "COMPLETED"]:
			transmitted += 1
		if st in ["EXECUTING", "COMPLETE", "COMPLETED"]:
			executed += 1
		var action := String(o.get("action", ""))
		var tids: Array = o.get("target_ids", []) if o.get("target_ids", []) is Array else []
		var tpos: Array = []
		if not tids.is_empty():
			tpos = pos_rows.get(String(tids[0]), [])
		nodes.append({"order_id": String(o.get("order_id", "")), "action": action, "status": st,
			"target_id": String(tids[0]) if not tids.is_empty() else "", "pos_km": tpos,
			"exec_t": float(o.get("exec_t", -1.0)), "fired": false,
			"params": (o.get("params", {}) as Dictionary).duplicate(true) if o.get("params", {}) is Dictionary else {}})
	out["nodes"] = nodes
	out["transmitted"] = transmitted
	out["executed"] = executed
	out["source"] = "ORDER SERVICE / COMMS"
	print("[SHELL BINDER] plot_commands ready=", out["ready"], " orders=", orders.size(), " pending=", out["pending"], " transmitted=", transmitted, " executed=", executed)
	return out


func plot_sensors() -> Dictionary:
	var out: Dictionary = {"ready": false, "rings": [], "observations": [], "tws": [], "ew": {}, "emcon": false, "radar_enabled": false, "source": "SENSOR NOT READY"}
	if session == null or session.sensor_service == null:
		return out
	var svm: Dictionary = sensor_vm if not sensor_vm.is_empty() else session.sensor_service.vm()
	out["ready"] = bool(svm.get("ready", false))
	out["source"] = "SENSOR SERVICE / CIC TRACKS / EW"
	out["emcon"] = bool(svm.get("emcon", false))
	out["radar_enabled"] = bool(svm.get("radar_enabled", false))
	out["observations"] = (svm.get("observations", []) as Array).duplicate(true) if svm.get("observations", []) is Array else []
	# 真实型号 records 的 range_km（不伪造）
	var records: Dictionary = {}
	var auth = session.sensor_service._authority
	if auth != null:
		var rr = auth.get("records")
		if rr is Dictionary:
			records = rr
	var ranges: Dictionary = {}
	for key in ["radar", "optical", "ir"]:
		var rec = records.get(key, null)
		var rv := 0.0
		if rec is Dictionary:
			rv = float(rec.get("range_km", 0.0))
		elif rec != null:
			var got = rec.get("range_km")
			if got is int or got is float:
				rv = float(got)
		if rv > 0.0:
			ranges[key] = rv
	var rings: Array = []
	for key in ["radar", "optical", "ir"]:
		if ranges.has(key):
			var label: String = String({"radar": "RADAR / TWS", "optical": "OPTICAL", "ir": "IR"}.get(key, key))
			rings.append({"kind": key, "label": String(label), "range_km": float(ranges[key])})
	if session.signal_service != null:
		var ecfg: Dictionary = {}
		var iw = session.signal_service._iw
		if iw != null and iw.get("elint_cfg") is Dictionary:
			ecfg = (iw.get("elint_cfg") as Dictionary).duplicate(true)
		if ecfg.is_empty():
			var scfg: Dictionary = session.signal_service.config if session.signal_service.config is Dictionary else {}
			ecfg = scfg.get("elint", {}) if scfg.get("elint", {}) is Dictionary else {}
		if float(ecfg.get("range_km", 0.0)) > 0.0:
			rings.append({"kind": "elint", "label": "ELINT", "range_km": float(ecfg.get("range_km"))})
	out["rings"] = rings
	# TWS rows = CIC tracks（identity/level）；不用 truth
	var tws: Array = []
	for raw in (cic_vm.get("tracks", []) if cic_vm.get("tracks", []) is Array else []):
		if not (raw is Dictionary):
			continue
		var tr: Dictionary = raw
		tws.append({"id": String(tr.get("id", "")), "level": int(tr.get("level", 1)),
			"identity": String(tr.get("identity", "unknown")), "threat": String(tr.get("threat", "unknown")),
			"estimate_km": tr.get("estimate_km", null), "uncertainty_km": tr.get("uncertainty_km", null),
			"bearing_deg": tr.get("bearing_deg", null), "stale": bool(tr.get("stale", false)),
			"quality": float(tr.get("quality", 0.0)), "sources": (tr.get("sources", []) as Array).duplicate() if tr.get("sources", []) is Array else []})
	out["tws"] = tws
	var ew: Dictionary = session.ew_vm() if session.ew_service != null else {}
	out["ew"] = { "ready": bool(ew.get("ready", false)), "emcon": bool(ew.get("emcon", false)),
		"active": int((ew.get("counts", {}) as Dictionary).get("active", 0)) if ew.get("counts", {}) is Dictionary else 0,
		"by_type": (ew.get("counts", {}) as Dictionary).get("by_type", {}) if ew.get("counts", {}) is Dictionary else {},
		"effective": (ew.get("counts", {}) as Dictionary).get("active", 0) if ew.get("counts", {}) is Dictionary else 0}
	print("[SHELL BINDER] plot_sensors ready=", out["ready"], " rings=", rings.size(), " obs=", (out["observations"] as Array).size(), " tws=", tws.size(), " emcon=", out["emcon"], " ew_ready=", bool(out["ew"].get("ready", false)))
	return out


func _refresh_cic() -> void:
	cic_ready = false
	cic_vm = {}
	if session == null:
		return
	var own := {"id": "apsis", "pos_km": [0.0, 0.0, 0.0], "heading_deg": 0.0}
	if session.physics_world_service != null and bool(session.physics_world_service.ready):
		var st: Dictionary = session.physics_state("apsis", "bary_rot")
		if st.get("r", []) is Array and (st.get("r", []) as Array).size() >= 3:
			own["pos_km"] = (st.get("r", []) as Array).duplicate()
	var cfg: Dictionary = {"track_table_vm": track_vm, "ownship": own}
	if session.facility_registry != null:
		cfg["facility_registry"] = session.facility_registry
	cic_view = CICView.new(cfg)
	cic_ready = bool(cic_view.ready)
	if cic_ready:
		cic_vm = cic_view.build().duplicate(true)
	if not _cic_logged:
		_cic_logged = true
		print("[SHELL BINDER] CICView ready=", cic_ready, " truth=", str(bool(cic_vm.get("truth", false))), " tracks=", (cic_vm.get("tracks", []) as Array).size(), " levels=", str((cic_vm.get("summary", {}) as Dictionary).get("levels", {})), " facilities=", (cic_vm.get("facilities", []) as Array).size())
		_cic_selftest()
		_ident_selftest()
	# 识别融合一次性自检：服务是否启用、评估/证据是否真在增长（不伪造）。
	if not _ident_logged and session != null:
		_ident_logged = true
		var ienabled: bool = session.identification_enabled()
		var isum: Dictionary = session.identification_service.summary() if ienabled else {}
		var ev_counts: Dictionary = {}
		if ienabled:
			ev_counts = session.identification_service._evidence_counts()
		print("[SHELL BINDER] identification ready=", ienabled,
			" targets=", int(isum.get("targets", 0)),
			" by_identity=", str(isum.get("by_identity", {})),
			" evidence=", str(ev_counts), " auto=", bool(isum.get("auto_enabled", false)))


## 仅自检：用临时 IdentificationService 实例验证「矛盾/欺骗/IFF 单独」三条规则；
## 不写 session、不进 UI，只为证明 IDENT 弹层展示的规则是真实行为而非文案。
func _ident_selftest() -> void:
	var svc = IdentificationService.new({})
	if not bool(svc.ready):
		print("[SHELL BINDER] IDENT SELFTEST not_ready ", str(svc.errors))
		return
	# A：transponder=friend 与 elint=hostile 并存 → 矛盾，身份降 suspect，confidence ≤0.70
	svc.ingest({"target_id": "T-CONFLICT", "source": "transponder", "identity": "friend", "confidence": 0.9, "t": 0.0})
	svc.ingest({"target_id": "T-CONFLICT", "source": "elint", "identity": "hostile", "confidence": 0.9, "t": 0.0})
	var a1: Dictionary = svc.get_assessment("T-CONFLICT")
	# B：仅 IFF 且 spoofed → 不得 hostile；spoof ≥0.5 → confidence ≤0.60
	svc.ingest({"target_id": "T-SPOOF", "source": "iff", "identity": "hostile", "confidence": 1.0, "status": "spoofed", "t": 0.0})
	var a2: Dictionary = svc.get_assessment("T-SPOOF")
	# C：两类来源均报同一 hostile 但状态 captured/spoofed → spoof≥0.5，confidence ≤0.60
	svc.ingest({"target_id": "T-SPOOF2", "source": "iff", "identity": "hostile", "confidence": 1.0, "status": "captured", "t": 0.0})
	svc.ingest({"target_id": "T-SPOOF2", "source": "elint", "identity": "hostile", "confidence": 1.0, "status": "spoofed", "t": 0.0})
	var a3: Dictionary = svc.get_assessment("T-SPOOF2")
	print("[SHELL BINDER] IDENT SELFTEST conflict identity=", String(a1.get("identity", "")),
		" conf=%.2f" % float(a1.get("confidence", 0.0)),
		" contradictions=", str(a1.get("contradictions", [])))
	print("[SHELL BINDER] IDENT SELFTEST spoof identity=", String(a2.get("identity", "")),
		" conf=%.2f" % float(a2.get("confidence", 0.0)),
		" spoof=%.2f" % float(a2.get("spoof_suspicion", 0.0)),
		" contradictions=", str(a2.get("contradictions", [])))
	print("[SHELL BINDER] IDENT SELFTEST spoof_cap identity=", String(a3.get("identity", "")),
		" conf=%.2f" % float(a3.get("confidence", 0.0)),
		" spoof=%.2f" % float(a3.get("spoof_suspicion", 0.0)))


func _cic_selftest() -> void:
	# 仅 headless 自检：用 fixture 验证 CICView L1 bearing-only / L2 estimate 规则；不进 UI。
	var fixture: Dictionary = {"t": 10.0, "tracks": [
		{"id": "T-L1", "level": 1, "bearing_deg": 45.0, "range_km": 100.0,
			"quality": 0.5, "sources": ["radar"], "last_update": 10.0, "entity_id": "unknown_a"},
		{"id": "T-L2", "level": 2, "bearing_deg": 90.0, "range_km": 50.0,
			"quality": 0.8, "sources": ["radar", "ir"], "last_update": 10.0, "entity_id": "unknown_b"},
	]}
	var test = CICView.new({"track_table_vm": fixture, "ownship": {"id": "apsis", "pos_km": [0.0, 0.0, 0.0]}})
	if not bool(test.ready):
		print("[SHELL BINDER] CIC SELFTEST not_ready ", str(test.errors))
		return
	var v: Dictionary = test.build()
	var rows: Array = v.get("tracks", []) if v.get("tracks", []) is Array else []
	var l1_est = null
	var l2_est = null
	for raw in rows:
		if raw is Dictionary:
			if String((raw as Dictionary).get("id", "")) == "T-L1":
				l1_est = (raw as Dictionary).get("estimate_km", null)
			elif String((raw as Dictionary).get("id", "")) == "T-L2":
				l2_est = (raw as Dictionary).get("estimate_km", null)
	print("[SHELL BINDER] CIC SELFTEST truth=", str(bool(v.get("truth", true))), " L1_estimate=", str(l1_est), " L2_estimate=", str(l2_est))


func plot_cic() -> Dictionary:
	return cic_vm.duplicate(true) if cic_ready else {"ready": false, "truth": false, "tracks": [], "facilities": [], "ownship": {}, "source": "CIC NOT READY"}


func physics_world_ready() -> bool:
	return session != null and session.physics_world_service != null and bool(session.physics_world_service.ready)


func plot_positions() -> Dictionary:
	var out: Dictionary = {"source": "contacts", "reference": "apsis", "positions": [], "reference_pos": [0.0, 0.0, 0.0]}
	var ref: Array = [0.0, 0.0, 0.0]
	var physics := physics_world_ready()
	if physics:
		var states: Dictionary = session.physics_positions("bary_rot")
		if states.has("apsis"):
			var a: Dictionary = states["apsis"]
			if a.get("r", []) is Array and (a.get("r", []) as Array).size() >= 3:
				ref = (a.get("r", []) as Array).duplicate()
		for id in states.keys():
			var st: Dictionary = states[id]
			var r: Array = st.get("r", []) if st.get("r", []) is Array else []
			var v: Array = st.get("v", []) if st.get("v", []) is Array else []
			if r.size() >= 3:
				out["positions"].append({"id": String(id), "pos_km": [float(r[0]) - float(ref[0]), float(r[1]) - float(ref[1]), float(r[2]) - float(ref[2])], "vel_kmps": v.duplicate() if v is Array else []})
		out["source"] = "physics"
		out["reference"] = "apsis"
		out["reference_pos"] = ref
		return out
	# fallback contacts/session entities（相对 apsis）
	var ents: Dictionary = {}
	var snap: Dictionary = snapshot if snapshot is Dictionary else {}
	for raw in (snap.get("entities", []) if snap.get("entities", []) is Array else []):
		if raw is Dictionary:
			var e: Dictionary = raw
			var p: Array = e.get("pos_km", []) if e.get("pos_km", []) is Array else []
			if p.size() >= 3:
				ents[String(e.get("id", ""))] = p
	if ents.has("apsis"):
		ref = (ents["apsis"] as Array).duplicate()
	for id in ents.keys():
		var p2: Array = ents[id]
		out["positions"].append({"id": String(id), "pos_km": [float(p2[0]) - float(ref[0]), float(p2[1]) - float(ref[1]), float(p2[2]) - float(ref[2])], "vel_kmps": []})
	out["source"] = "contacts"
	out["reference_pos"] = ref
	return out


func plot_bodies() -> Dictionary:
	var earth := [0.0, 0.0, 0.0]
	var moon := [384400.0, 0.0, 0.0]
	var src := "fallback_strategic"
	var ref: Array = [0.0, 0.0, 0.0]
	if physics_world_ready() and session.physics_world_service != null:
		var pw = session.physics_world_service
		var e_abs = pw.call("_earth_pos") if pw.has_method("_earth_pos") else [0.0, 0.0, 0.0]
		var m_abs = pw.call("_moon_pos") if pw.has_method("_moon_pos") else moon
		if e_abs is Array and (e_abs as Array).size() >= 3:
			earth = (e_abs as Array).duplicate()
		if m_abs is Array and (m_abs as Array).size() >= 3:
			moon = (m_abs as Array).duplicate()
		var a: Dictionary = session.physics_state("apsis", "bary_rot")
		if a.get("r", []) is Array and (a.get("r", []) as Array).size() >= 3:
			ref = (a.get("r", []) as Array).duplicate()
		src = "physics"
	earth = [float(earth[0]) - float(ref[0]), float(earth[1]) - float(ref[1]), float(earth[2]) - float(ref[2])]
	moon = [float(moon[0]) - float(ref[0]), float(moon[1]) - float(ref[1]), float(moon[2]) - float(ref[2])]
	print("[SHELL BINDER] plot_bodies source=", src, " earth=", str(earth), " moon=", str(moon))
	return {"source": src, "frame": "bary_rot", "reference": "apsis",
		"earth": {"pos_km": earth, "radius_km": 6371.0, "label": "EARTH"},
		"moon": {"pos_km": moon, "radius_km": 1737.0, "label": "MOON"},
		"writes": {"world": false, "ui": false, "v15": false}}


func plot_facilities() -> Dictionary:
	var out: Dictionary = {"source": "none", "facilities": [], "reference_pos": [0.0, 0.0, 0.0]}
	if session == null or session.facility_registry == null:
		return out
	var ref: Array = [0.0, 0.0, 0.0]
	if physics_world_ready():
		var a: Dictionary = session.physics_state("apsis", "bary_rot")
		if a.get("r", []) is Array and (a.get("r", []) as Array).size() >= 3:
			ref = (a.get("r", []) as Array).duplicate()
	var list: Array = []
	for raw in session.facility_registry.facilities:
		if not (raw is Dictionary):
			continue
		var f: Dictionary = raw
		if String(f.get("parent_cluster", "")) != "L1_MERIDIAN":
			continue
		var phys: Dictionary = f.get("physical", {}) if f.get("physical", {}) is Dictionary else {}
		var orb: Dictionary = phys.get("orbit", {}) if phys.get("orbit", {}) is Dictionary else {}
		var pos: Array = orb.get("position_km", []) if orb.get("position_km", []) is Array else []
		if pos.size() < 3:
			continue
		list.append({"facility_id": String(f.get("facility_id", "")), "name": String(f.get("name", "")),
			"facility_class": String(f.get("facility_class", "")), "facility_code": String(f.get("facility_code", "")),
			"transponder_code": String(f.get("transponder_code", "")),
			"pos_km": [float(pos[0]) - float(ref[0]), float(pos[1]) - float(ref[1]), float(pos[2]) - float(ref[2])]})
	list.sort_custom(func(a, b): return String(a.get("facility_id", "")) < String(b.get("facility_id", "")))
	out["facilities"] = list.slice(0, mini(12, list.size()))
	out["source"] = "facility_registry_l1"
	out["reference_pos"] = ref
	return out


func report_sync() -> Dictionary:
	if after_action == null:
		return {"ok": false, "reason": "no_after_action_report"}
	var patch: Dictionary = {}
	if ceres_chain != null:
		var cs: String = ceres_chain.current_state()
		if cs == "RESCUED" or cs == "COMPLETE":
			patch["ceres_status"] = "rescued"
		elif cs == "IGNORED":
			patch["ceres_status"] = "ignored"
	if chronos_chain != null:
		var fl: Dictionary = chronos_chain.get_flags()
		patch["chronos"] = {"evac": bool(fl.get("evac_done", false)),
			"blackbox": bool(fl.get("blackbox_done", false)),
			"telemetry": bool(fl.get("telemetry_done", false)),
			"choice": String(chronos_chain.choice)}
	if av4412_chain != null:
		var av: String = String(av4412_chain.chosen())
		if av != "":
			patch["av4412_choice"] = av
		patch["threat"] = av4412_chain.get_threat()
	var ev: Array = []
	if chronos_chain != null:
		var f2: Dictionary = chronos_chain.get_flags()
		if bool(f2.get("blackbox_done", false)): ev.append("blackbox")
		if bool(f2.get("telemetry_done", false)): ev.append("telemetry")
	if session != null and session.signal_service != null:
		var svm2: Dictionary = session.signal_service.vm()
		var elint: Dictionary = svm2.get("elint", {}) if svm2.get("elint", {}) is Dictionary else {}
		if int((elint.get("counts", {}) as Dictionary).get("evidence", 0)) > 0: ev.append("elint")
		if int((elint.get("counts", {}) as Dictionary).get("signals", 0)) > 0: ev.append("comms")
	patch["evidence"] = ev
	patch["trust"] = clampf(float(maxi(0, chronos_chain.get_trust())) / 6.0, 0.0, 1.0) if chronos_chain != null else 0.5
	patch["political"] = 0.8 if (av4412_chain != null and String(av4412_chain.chosen()) in ["strong", "question"]) else 0.5
	var res: Dictionary = after_action.ingest(patch)
	if bool(res.get("ok", false)):
		print("[SHELL BINDER] REPORT sync inputs=", JSON.stringify(after_action.vm().get("inputs", {})))
	return res


func report_choose(choice: String) -> Dictionary:
	if after_action == null:
		return {"ok": false, "reason": "no_after_action_report"}
	var res: Dictionary = after_action.choose_report(choice)
	if bool(res.get("ok", false)):
		report_comms_lines.append("[ID13 至 OCJC]-[RDO]-[报告选择 " + String(res.get("report_choice", choice)) + "]")
	return res


func report_compose() -> Dictionary:
	if after_action == null:
		return {"ok": false, "reason": "no_after_action_report"}
	var res: Dictionary = after_action.compose()
	if bool(res.get("ok", false)):
		report_comms_lines.append("[ID13 至 OCJC]-[RDO]-[AFTER ACTION REPORT · branch " + String(res.get("branch_hint", "")) + "]")
	return res


func report_vm() -> Dictionary:
	return after_action.vm() if after_action != null else {}


func report_text() -> String:
	return after_action.report_text() if after_action != null else ""


func report_branch_hint() -> String:
	return after_action.branch_hint() if after_action != null else ""


func report_missing() -> Array:
	return after_action.missing_items() if after_action != null else []


func report_branch_info(branch_id: String) -> Dictionary:
	return after_action.branch_info(branch_id) if after_action != null else {}


func report_branch_text(branch_id: String) -> String:
	if after_action == null:
		return ""
	return str(after_action.branch_text(branch_id).get("zh", ""))


func av4412_state() -> String:
	return String(av4412_chain.current_state()) if av4412_chain != null else "NOT READY"


func av4412_vm() -> Dictionary:
	return av4412_chain.vm() if av4412_chain != null else {}


func av4412_text(text_key: String) -> String:
	if av4412_chain == null:
		return ""
	return String(av4412_chain.text(text_key).get("zh", ""))


func av4412_actions() -> Array:
	return av4412_chain.available_actions() if av4412_chain != null else []


func av4412_update_orbit(track: Dictionary) -> Dictionary:
	if av4412_chain == null:
		return {"ok": false, "reason": "no_av4412_chain"}
	var res: Dictionary = av4412_chain.update_orbit(track)
	last_av4412_result = res.duplicate(true)
	return last_av4412_result


func av4412_advance(action: String, payload := {}) -> Dictionary:
	if av4412_chain == null:
		return {"ok": false, "reason": "no_av4412_chain"}
	var res: Dictionary = av4412_chain.advance(action, payload)
	last_av4412_result = res.duplicate(true)
	if bool(res.get("ok", false)):
		if action == "comms":
			_add_av_comms("[AV-4412 至 APSIS]-[LD]-[" + av4412_text("av4412.opening") + "]")
		elif action in ["strong", "standard", "question", "retreat"]:
			_add_av_comms("[APSIS 至 AV-4412]-[LD]-[" + av4412_text("av4412." + action) + "]")
	print("[SHELL BINDER] AV4412 ", action, " · ", str(res.get("ok", false)), " state=", String(res.get("state", av4412_chain.current_state())), " threat=", av4412_chain.get_threat(), " trust=", av4412_chain.get_trust(), " trigger=", String(res.get("trigger_id", "")))
	return last_av4412_result


func _add_av_comms(line: String) -> void:
	if line != "" and not (line in av4412_comms_lines):
		av4412_comms_lines.append(line)


func chronos_state() -> String:
	return String(chronos_chain.current_state()) if chronos_chain != null else "NOT READY"


func chronos_vm() -> Dictionary:
	return chronos_chain.vm() if chronos_chain != null else {}


func chronos_text(text_key: String) -> String:
	if chronos_chain == null:
		return ""
	return String(chronos_chain.text(text_key).get("zh", ""))


func chronos_actions() -> Array:
	return chronos_chain.available_actions() if chronos_chain != null else []


func chronos_trust() -> int:
	return chronos_chain.get_trust() if chronos_chain != null else 0


func _chronos_comms_append(line: String) -> void:
	if line != "" and not (line in chronos_comms_lines):
		chronos_comms_lines.append(line)


func chronos_advance(action: String, payload := {}) -> Dictionary:
	if chronos_chain == null:
		return {"ok": false, "reason": "no_chronos_chain"}
	var res: Dictionary = chronos_chain.advance(action, payload)
	last_chronos_result = res.duplicate(true)
	if bool(res.get("ok", false)):
		var from_state := String(res.get("from_state", ""))
		if action == "port_comm":
			_chronos_comms_append("[Chronos 港务 至 ID13]-[RDO]-[" + chronos_text("chronos.port_rdo") + "]")
		elif action == "private_comm":
			_chronos_comms_append("[副官 至 指挥官]-[PRIVATE]-[" + chronos_text("chronos.private_comm") + "]")
	print("[SHELL BINDER] CHRONOS ", action, " · ", str(res.get("ok", false)), " state=", String(res.get("state", chronos_chain.current_state())), " trust=", chronos_chain.get_trust(), " trigger=", String(res.get("trigger_id", "")))
	return last_chronos_result


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


# ── 识别融合（IdentificationService：身份/置信度/来源/矛盾/人工确认）──
# 只读服务评估 + 显式动作（询问/确认/清除/自动开关）；不写 world/TrackTable。

## 识别目标键：证据以 entity_id 为 target_id；回退 track_id / 接触批号。
func ident_target_id(row: Dictionary) -> String:
	for key in ["entity_id", "track_id", "id"]:
		var v := String(row.get(key, ""))
		if v != "":
			return v
	return ""


func ident_enabled() -> bool:
	return session != null and session.identification_enabled()


func ident_auto_on() -> bool:
	if not ident_enabled():
		return false
	var s: Dictionary = session.identification_summary()
	return bool(s.get("auto_enabled", false))


## 单接触识别评估。with_evidence=true 时附最近 8 条证据（弹层用；列表用 false 省开销）。
## 无评估时 known=false，identity 保持 unknown —— 不伪造身份。
func ident_view(row: Dictionary, with_evidence := false) -> Dictionary:
	var tid := ident_target_id(row)
	var out := {"target_id": tid, "known": false, "enabled": ident_enabled(),
		"identity": "unknown", "confidence": 0.0, "level": 1,
		"level_name": "L1_BEARING", "sources": [], "categories": [],
		"contradictions": [], "spoof": 0.0, "evidence_count": 0, "age": 0.0,
		"manual": false, "authorized": false, "manual_identity": "",
		"auto_on": ident_auto_on(), "evidence": [], "tag": "—", "warn": false}
	if not ident_enabled() or tid == "":
		return out
	var a: Dictionary = session.identification_get(tid)
	if a.is_empty():
		return out
	out["known"] = true
	out["identity"] = String(a.get("identity", "unknown"))
	out["confidence"] = float(a.get("confidence", 0.0))
	out["level"] = int(a.get("level", 1))
	out["level_name"] = String(a.get("level_name", "L1_BEARING"))
	out["sources"] = (a.get("sources", []) as Array).duplicate() if a.get("sources") is Array else []
	out["categories"] = (a.get("categories", []) as Array).duplicate() if a.get("categories") is Array else []
	out["contradictions"] = (a.get("contradictions", []) as Array).duplicate() if a.get("contradictions") is Array else []
	out["spoof"] = float(a.get("spoof_suspicion", 0.0))
	out["evidence_count"] = int(a.get("evidence_count", 0))
	out["age"] = float(a.get("age", 0.0))
	out["manual"] = bool(a.get("manual", false))
	out["authorized"] = bool(a.get("authorized", false))
	out["manual_identity"] = String(a.get("manual_identity", ""))
	out["warn"] = not (out["contradictions"] as Array).is_empty() or float(out["spoof"]) >= 0.5
	# 列表用短标签：来源族 + 置信度；人工确认加 M，矛盾/欺骗加 ⚠。
	var src_tag := "—"
	var cats: Array = out["categories"]
	if cats.has("iff"):
		src_tag = "IFF"
	elif cats.has("sensor"):
		src_tag = "OPT"
	elif cats.has("elint"):
		src_tag = "ELINT"
	elif cats.has("database"):
		src_tag = "DB"
	elif not cats.is_empty():
		src_tag = String(cats[0]).to_upper().substr(0, 4)
	var tag := "%s %.2f" % [src_tag, float(out["confidence"])]
	if bool(out["manual"]):
		tag = "M·" + tag
	if bool(out["warn"]):
		tag += " ⚠"
	out["tag"] = tag
	if with_evidence:
		var ev: Array = session.identification_evidence(tid)
		var tail: Array = ev.slice(maxi(0, ev.size() - 8), ev.size())
		out["evidence"] = tail
	return out


## 手动应答机询问（mode_s）；证据经 session 桥回灌识别融合。
func ident_interrogate(row: Dictionary, mode := "mode_s") -> Dictionary:
	var tid := ident_target_id(row)
	if tid == "":
		return {"ok": false, "reason": "no_target", "target_id": ""}
	var res: Dictionary = transponder_query(tid, mode)
	var reply: Dictionary = res.get("reply", {}) if res.get("reply") is Dictionary else {}
	return {"ok": bool(res.get("ok", false)), "target_id": tid,
		"reason": String(res.get("reason", "")),
		"status": String(reply.get("status", "")),
		"identity": String(reply.get("identity", ""))}


## IFF 询问（sensor_service）；identity 只会是 friend/unknown，永不 hostile。
func ident_iff(row: Dictionary) -> Dictionary:
	var tid := ident_target_id(row)
	if session == null:
		return {"ok": false, "reason": "no_session", "target_id": tid}
	var res: Dictionary = session.query_iff(tid)
	return {"ok": bool(res.get("ok", false)), "target_id": tid,
		"reason": String(res.get("reason", "")),
		"identity": String(res.get("identity", ""))}


## 人工确认（L4）：hostile 走 authorize 语义，需显式授权标记。
func ident_confirm(row: Dictionary, identity: String) -> Dictionary:
	var tid := ident_target_id(row)
	if session == null:
		return {"ok": false, "reason": "no_session", "target_id": tid}
	var res: Dictionary = session.identification_manual_confirm(tid, identity,
		{"authority": "cic_operator", "authorized": identity == "hostile"})
	return {"ok": bool(res.get("ok", false)), "target_id": tid, "identity": identity,
		"reason": String(res.get("reason", ""))}


func ident_clear(row: Dictionary) -> Dictionary:
	var tid := ident_target_id(row)
	if session == null:
		return {"ok": false, "reason": "no_session", "target_id": tid}
	var res: Dictionary = session.identification_clear_manual(tid)
	return {"ok": bool(res.get("ok", false)), "target_id": tid,
		"reason": String(res.get("reason", ""))}


func ident_set_auto(on: bool) -> Dictionary:
	if session == null:
		return {"ok": false, "reason": "no_session"}
	var res: Dictionary = session.identification_set_auto(on)
	return {"ok": bool(res.get("ok", false)), "auto": on,
		"reason": String(res.get("reason", ""))}


## 识别服务 VM（assessments / events / auto）；弹层用于全目标板与融合日志。
func ident_vm() -> Dictionary:
	if not ident_enabled():
		return {}
	return session.identification_vm()


func signal_event(type: String, target := "", payload := {}) -> void:
	if session != null and session.bus != null:
		session.bus.publish({"type": type, "t": session.now_s(), "source": "game_shell", "target": target, "payload": payload})
