extends RefCounted

## V2 UI 数据适配层（view-model adapter）。
##
## 职责：把 core（`game_v16/core/*`）或 content JSON 的**只读**数据，归一化成 UI 用的
## 纯 Dictionary view-model；core 未就绪/接口变动时自动降级，不反向修改 core。
##
## 三级数据源：
## 1. `core`       —— 动态加载 `res://core/*.gd`，优先使用 core 提供的只读 view-model
##                    （`world.vm_state()/vm_contacts()/vm_entity()/vm_actions()/...`），
##                    core 没有 vm_* 时退回实体字段反射读取（兼容 V2-0 旧接口）。
## 2. `content`    —— core 缺失时只读解析 `res://content/scenario_l1_v2.json`
##                    或 `res://content/scenario_l1.json`。
## 3. `local-demo` —— 连 content 都不可用时生成最小演示数据。
##
## `synthetic` 实体只在 `add_synthetic()`（截图/压测用）时追加，UI 会标 DEMO，不冒充剧情实体。
##
## 依赖方向：ui → core（单向）；core 不引用 ui。本文件不写 core 文件。

const SCENARIO_CANDIDATES := [
	"res://content/scenario_l1_v2.json",
	"res://content/scenario_l1.json",
]
const CORE_SCENARIO := "res://core/scenario.gd"
const CORE_WORLD := "res://core/world.gd"
const CORE_ACTIONS := "res://core/actions.gd"
const CORE_MISSION := "res://core/mission.gd"

# 动作注册表兜底（与 core/actions.gd 的语义一致；仅在 core 不可用时使用）
const FALLBACK_ACTIONS := [
	{"id": "crossfix", "label": "交叉定位", "requires": [], "levels": [1], "supported": true},
	{"id": "radar_illum", "label": "雷达照射识别", "requires": ["sensor.radar.active"], "levels": [1, 2], "supported": true},
	{"id": "model_ident", "label": "型号识别", "requires": ["sensor.optical"], "levels": [2], "supported": true},
	{"id": "radar_track", "label": "雷达跟踪", "requires": ["sensor.radar.active"], "levels": [3, 4], "supported": true},
	{"id": "iff_query", "label": "IFF 问答", "requires": ["sensor.iff.interrogator"], "levels": [3, 4], "supported": true},
	{"id": "optical_channel", "label": "光学通道", "requires": ["sensor.optical"], "levels": [3, 4], "supported": true},
	{"id": "ir_channel", "label": "红外通道", "requires": ["sensor.ir"], "levels": [3, 4], "supported": true},
	{"id": "fire_control", "label": "火控解算", "requires": ["weapon.firecontrol"], "levels": [4], "supported": false},
	{"id": "missile_solve", "label": "导弹路径解算", "requires": ["weapon.missile"], "levels": [4], "supported": false},
	{"id": "weapons_hold", "label": "武装待命", "requires": ["weapon.armed"], "levels": [4], "supported": false},
]

const FALLBACK_PHASES := ["PRELUDE", "READ", "COMMAND", "DECISION", "REPORT", "END"]

var mode := "none"            # core | content | local-demo
var notes: Array[String] = []
var loaded := false

var title := ""
var scenario_id := ""
var datum := "L1"
var epoch := 0.0
var own_id := ""
var own_entity_id := ""
var selected_id := ""
var time := 0.0
var phase := "PRELUDE"
var phase_title := ""
var phases: Array = FALLBACK_PHASES.duplicate()
var _last_phase_result: Dictionary = {}
var scenario_path := ""

var _core_world: Variant = null
var _core_scenario: Variant = null
var _core_actions: Variant = null
var _core_mission: Variant = null
var _contacts: Array = []          # 归一化接触行（UI 列表直接用）
var _synthetic: Array = []         # 演示/压测实体
var _synthetic_by_id: Dictionary = {}
var _index: Dictionary = {}        # track_id / entity_id / batch / synthetic id → 接触行
var _state: Dictionary = {}
var _evidence: Array = []
var _core_events: Array = []
var _scenario_entities: Dictionary = {}
var _story: Dictionary = {}
var _bridge_script: Variant = null
var _action_log: Array = []


# ══ 启动 ═════════════════════════════════════════════════════════════════

func boot(force_fallback := false) -> bool:
	loaded = false
	if not force_fallback:
		if _try_core():
			loaded = true
			_rebuild_index()
			return true
		notes.append("core 数据源不可用，尝试 content JSON 兜底")
	if OS.get_environment("DSH_V2_NO_CONTENT") == "1":
		notes.append("DSH_V2_NO_CONTENT=1：跳过 content 兜底")
	elif _try_content():
		loaded = true
		_rebuild_index()
		return true
	_seed_local_demo()
	loaded = true
	_rebuild_index()
	return loaded


func _load_script(path: String) -> Variant:
	if not ResourceLoader.exists(path):
		return null
	var res: Variant = load(path)
	if res == null or not (res is GDScript):
		return null
	return res


func _try_core() -> bool:
	var scenario_script: Variant = _load_script(CORE_SCENARIO)
	var world_script: Variant = _load_script(CORE_WORLD)
	if scenario_script == null or world_script == null:
		notes.append("core/scenario.gd 或 core/world.gd 缺失")
		return false
	var scenario: Variant = null
	for candidate in SCENARIO_CANDIDATES:
		if not FileAccess.file_exists(candidate):
			continue
		var sc: Variant = scenario_script.new()
		if sc == null or not sc.has_method("load_file"):
			break
		var s: Variant = sc.call("load_file", candidate)
		if s == null:
			continue
		var ents: Variant = _field(s, "entities", [])
		if ents is Array and not (ents as Array).is_empty():
			scenario = s
			scenario_path = candidate
			break
	if scenario == null:
		notes.append("core 场景候选均加载失败：%s" % str(SCENARIO_CANDIDATES))
		return false
	var w: Variant = world_script.new()
	if w == null or not w.has_method("load_scenario"):
		notes.append("core/world.gd 无 load_scenario")
		return false
	w.call("load_scenario", scenario)
	_core_world = w
	_core_scenario = scenario
	_core_actions = _load_script(CORE_ACTIONS)
	var mission_script: Variant = _load_script(CORE_MISSION)
	if mission_script != null:
		var m: Variant = null
		if mission_script.has_method("from_scenario") or mission_script.has_static_method("from_scenario"):
			m = mission_script.call("from_scenario", scenario)
		elif mission_script.can_instantiate():
			m = mission_script.new()
		if m != null:
			# V2-CORE-2：world.attach_mission 绑定 mission（flow flag 自动同步 + advance 内自动推进）
			if w.has_method("attach_mission"):
				w.call("attach_mission", m)
			elif m.has_method("attach_world"):
				m.call("attach_world", w)
			_core_mission = m
	# 场景文本（story.* 由 scenario.story 携带，prompt_ref 已解析）
	var story_raw: Variant = _field(scenario, "story", {})
	_story = (story_raw as Dictionary).duplicate(true) if story_raw is Dictionary else {}
	# 场景元数据（优先 vm_state）
	_state = _extract_state()
	title = String(_state.get("title", _field(scenario, "title", "")))
	scenario_id = String(_state.get("scenario_id", _field(scenario, "id", "")))
	datum = String(_field(scenario, "datum", "L1"))
	epoch = float(_field(scenario, "epoch", 0.0))
	own_id = String(_state.get("own_id", _field(w, "own_id", "")))
	own_entity_id = own_id
	selected_id = String(_state.get("selected_id", _field(w, "selected_id", "")))
	time = float(_state.get("t", _field(w, "t", 0.0)))
	phases = _normalize_phases(_field(scenario, "phases", []))
	phase = _current_phase()
	# 实体字典（供 section 读取 capabilities / orbit 等）
	_scenario_entities.clear()
	for e in (_field(scenario, "entities", []) as Array):
		var eid := String(_field(e, "id", ""))
		if eid != "":
			_scenario_entities[eid] = e
	# 接触行 / 证据 / 事件
	_contacts = _extract_contacts()
	_evidence = _extract_evidence()
	_core_events = _extract_events(16)
	if _contacts.is_empty() and _scenario_entities.is_empty():
		notes.append("core 场景无实体/航迹")
		return false
	if own_id == "" and not _contacts.is_empty():
		own_id = String((_contacts[0] as Dictionary).get("id", ""))
		own_entity_id = own_id
	# 统一成 contact row id（航迹 id），列表选中/右键/菜单都用它
	own_id = _canonical_contact_id(own_id)
	own_entity_id = _canonical_entity_id(own_id, own_entity_id)
	if selected_id == "":
		selected_id = own_id
	selected_id = _canonical_contact_id(selected_id)
	_apply_own()
	mode = "core"
	notes.append("core 已加载（%s）" % scenario_path)
	return true


func _try_content() -> bool:
	for path in SCENARIO_CANDIDATES:
		if not FileAccess.file_exists(path):
			continue
		var txt := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(txt)
		if not (parsed is Dictionary):
			continue
		var d: Dictionary = parsed
		var ents: Array = d.get("entities", []) if d.get("entities", []) is Array else []
		var tracks: Array = d.get("tracks", []) if d.get("tracks", []) is Array else []
		if ents.is_empty() and tracks.is_empty():
			continue
		title = String(d.get("title", ""))
		scenario_id = String(d.get("id", ""))
		datum = String(d.get("datum", "L1"))
		epoch = float(d.get("epoch", 0.0))
		phases = _normalize_phases(d.get("phases", []))
		_story = {}
		if d.get("story", null) is Dictionary:
			_story = (d.get("story") as Dictionary).duplicate(true)
		if d.get("story_file", null) is String:
			var story_txt := FileAccess.get_file_as_string(String(d.get("story_file", "")))
			var story_parsed: Variant = JSON.parse_string(story_txt)
			if story_parsed is Dictionary:
				var sp: Dictionary = story_parsed
				_story = (sp.get("story", sp) as Dictionary).duplicate(true) if sp.get("story", sp) is Dictionary else {}
		phase = _current_phase()
		scenario_path = path
		_contacts.clear()
		_scenario_entities.clear()
		own_id = ""
		if not ents.is_empty():
			var own_entity := String(d.get("own_entity", ""))
			var track_by_entity := {}
			for raw_tr in tracks:
				if raw_tr is Dictionary:
					track_by_entity[String((raw_tr as Dictionary).get("entity_id", ""))] = raw_tr
			for raw_e in ents:
				if not (raw_e is Dictionary):
					continue
				var e: Dictionary = raw_e
				var eid := String(e.get("id", ""))
				_scenario_entities[eid] = e
				var tr: Dictionary = track_by_entity.get(eid, {})
				var c: Dictionary = {
					"id": eid,
					"track_id": String(tr.get("id", "")),
					"entity_id": eid,
					"batch": String(e.get("batch", eid)),
					"name": String(e.get("name", eid)),
					"name_en": String(e.get("name_en", "")),
					"kind": String(e.get("kind", "ship")),
					"side": String(e.get("side", "unknown")),
					"level": int(tr.get("level", 0)),
					"identity": String(tr.get("identity", e.get("identity", "unknown"))),
					"threat": String(tr.get("threat", e.get("threat", ""))),
					"stale": false,
					"age_s": float(tr.get("age_s", 0.0)),
					"bearing_deg": float(tr.get("bearing_deg", 0.0)),
					"range_km": float(tr.get("range_km", -1.0)),
					"sources": _strings(tr.get("sources", [])),
					"quality": 1.0,
					"has_entity": true,
					"tags": _strings(e.get("tags", [])),
					"notes": _strings(tr.get("notes", [])),
					"synthetic": false,
				}
				if c["track_id"] == "":
					c["track_id"] = eid
				if e.get("orbit", null) is Dictionary:
					c["orbit"] = (e.get("orbit") as Dictionary).duplicate(true)
					c["r"] = ((e.get("orbit") as Dictionary).get("r", []) as Array).duplicate()
					c["v"] = ((e.get("orbit") as Dictionary).get("v", []) as Array).duplicate()
				_contacts.append(_finalize_contact(c))
				if eid == own_entity or ("own" in (c["tags"] as Array)):
					own_id = eid
			# 无实体的航迹（虚警/纯回波）
			for raw_tr2 in tracks:
				if not (raw_tr2 is Dictionary):
					continue
				var tr2: Dictionary = raw_tr2
				if String(tr2.get("entity_id", "")) != "":
					continue
				var c2: Dictionary = {
					"id": String(tr2.get("id", "")),
					"track_id": String(tr2.get("id", "")),
					"entity_id": "",
					"batch": String(tr2.get("batch", tr2.get("id", ""))),
					"name": "无实体接触",
					"name_en": "",
					"kind": "contact",
					"side": "unknown",
					"level": int(tr2.get("level", 0)),
					"identity": String(tr2.get("identity", "unknown")),
					"threat": String(tr2.get("threat", "")),
					"stale": bool(tr2.get("stale", false)),
					"age_s": float(tr2.get("age_s", 0.0)),
					"bearing_deg": float(tr2.get("bearing_deg", 0.0)),
					"range_km": float(tr2.get("range_km", -1.0)),
					"sources": _strings(tr2.get("sources", [])),
					"quality": 1.0,
					"has_entity": false,
					"tags": _strings(tr2.get("tags", [])),
					"notes": _strings(tr2.get("notes", [])),
					"synthetic": false,
				}
				_contacts.append(_finalize_contact(c2))
		else:
			# 旧 v15 schema：tracks + ships
			var ships: Dictionary = {}
			for raw_ship in (d.get("ships", []) as Array):
				if raw_ship is Dictionary:
					ships[String((raw_ship as Dictionary).get("id", ""))] = raw_ship
			for raw_track in tracks:
				if not (raw_track is Dictionary):
					continue
				var t: Dictionary = raw_track
				var c3: Dictionary = {
					"id": String(t.get("id", t.get("batch", ""))),
					"track_id": String(t.get("id", t.get("batch", ""))),
					"entity_id": String(t.get("id", "")),
					"batch": String(t.get("id", t.get("batch", ""))),
					"name": String(t.get("name", "")),
					"name_en": String(t.get("en", "")),
					"kind": "ship",
					"side": String(t.get("side", "unknown")),
					"level": int(t.get("level", 0)),
					"identity": String(t.get("identity", "unknown")),
					"threat": String(t.get("threat", "")),
					"stale": false,
					"age_s": float(t.get("age", 0.0)),
					"bearing_deg": float(t.get("bearing", 0.0)),
					"range_km": float(t.get("range", -1.0)),
					"sources": [],
					"quality": 1.0,
					"has_entity": true,
					"tags": ["own"] if bool(t.get("own", false)) else [],
					"notes": [],
					"synthetic": false,
				}
				var ship: Dictionary = ships.get(String(c3["id"]), {})
				if not ship.is_empty():
					c3["name"] = String(ship.get("name", c3["name"]))
					c3["name_en"] = String(ship.get("name_en", c3["name_en"]))
					c3["cls"] = String(ship.get("ship_class", ""))
					c3["role"] = String(ship.get("role", ""))
					c3["faction"] = String(ship.get("faction", ""))
				_contacts.append(_finalize_contact(c3))
				if bool(t.get("own", false)):
					own_id = String(c3["id"])
		if own_id == "" and not _contacts.is_empty():
			own_id = String((_contacts[0] as Dictionary).get("id", ""))
			own_entity_id = own_id
		own_id = _canonical_contact_id(own_id)
		own_entity_id = _canonical_entity_id(own_id, own_entity_id)
		if selected_id == "":
			selected_id = own_id
		selected_id = _canonical_contact_id(selected_id)
		_apply_own()
		mode = "content"
		notes.append("core 未就绪：只读解析 %s" % path)
		return true
	return false


func _seed_local_demo() -> void:
	title = "V2 UI FALLBACK DEMO"
	scenario_id = "local-demo"
	datum = "L1"
	epoch = 0.0
	own_id = "DEMO-01"
	own_entity_id = "DEMO-01"
	selected_id = "DEMO-01"
	_contacts.clear()
	_scenario_entities.clear()
	var kinds := ["ship", "station", "tank", "wreck"]
	var sides := ["friend", "hostile", "neutral", "unknown"]
	for i in range(5):
		var kind: String = kinds[i % kinds.size()]
		var side: String = sides[i % sides.size()]
		var c := _synthetic_contact(i, kind, side)
		if i == 0:
			c["id"] = own_id
			c["track_id"] = own_id
			c["entity_id"] = own_id
			c["name"] = "基准舰 / DEMO FLAGSHIP"
			c["side"] = "friend"
			c["identity"] = "friend"
			c["caps"] = _default_caps("friend")
			c["tags"] = ["own", "demo"]
			c["level"] = 4
		_finalize_contact(c)
		_synthetic_by_id[String(c["id"])] = c
		_contacts.append(c)
	_apply_own()
	mode = "local-demo"
	notes.append("core 与 content 均不可用：使用本地最小演示数据")


# ══ 只读 view-model 提取 ═════════════════════════════════════════════════

func _extract_state() -> Dictionary:
	if _core_world == null:
		return {}
	if _core_world.has_method("vm_state"):
		var raw: Variant = _core_world.call("vm_state")
		if raw is Dictionary:
			return (raw as Dictionary).duplicate(true)
	return {
		"t": float(_field(_core_world, "t", 0.0)),
		"title": title,
		"own_id": String(_field(_core_world, "own_id", "")),
		"selected_id": String(_field(_core_world, "selected_id", "")),
	}


func _extract_contacts() -> Array:
	if _core_world == null:
		return []
	if _core_world.has_method("vm_contacts"):
		var raw: Variant = _core_world.call("vm_contacts")
		if raw is Array:
			return _normalize_contacts(raw)
	var ents: Variant = _entities_of(_core_world)
	if not (ents is Array):
		return []
	var out: Array = []
	for e in (ents as Array):
		var vm := _entity_dict(e)
		if vm.is_empty():
			continue
		var c: Dictionary = {
			"id": String(vm.get("id", "")),
			"track_id": String(vm.get("id", "")),
			"entity_id": String(vm.get("id", "")),
			"batch": String(vm.get("batch", vm.get("id", ""))),
			"name": String(vm.get("name", "")),
			"name_en": String(vm.get("name_en", "")),
			"kind": String(vm.get("kind", "ship")),
			"side": String(vm.get("side", "unknown")),
			"level": int(vm.get("track_level", 0)),
			"identity": String(vm.get("identity", "unknown")),
			"threat": String(vm.get("threat", "")),
			"stale": false,
			"age_s": 0.0,
			"bearing_deg": 0.0,
			"range_km": -1.0,
			"sources": [],
			"quality": 1.0,
			"bearing_only": false,
			"has_entity": true,
			"tags": _strings(vm.get("tags", [])),
			"notes": [],
			"synthetic": false,
		}
		out.append(_finalize_contact(c))
	return out


func _normalize_contacts(raw: Array) -> Array:
	var out: Array = []
	for item in raw:
		if not (item is Dictionary):
			continue
		var r: Dictionary = item
		var c: Dictionary = {
			"id": String(r.get("track_id", r.get("id", ""))),
			"track_id": String(r.get("track_id", "")),
			"entity_id": String(r.get("entity_id", "")),
			"batch": String(r.get("batch", "")),
			"name": String(r.get("name", "")),
			"name_en": String(r.get("name_en", "")),
			"kind": String(r.get("kind", "contact")),
			"side": String(r.get("side", "unknown")),
			"level": int(r.get("level", 0)),
			"identity": String(r.get("identity", "unknown")),
			"threat": String(r.get("threat", "")),
			"stale": bool(r.get("stale", false)),
			"age_s": float(r.get("age_s", 0.0)),
			"bearing_deg": float(r.get("bearing_deg", 0.0)),
			"range_km": float(r.get("range_km", -1.0)),
			"sources": _strings(r.get("sources", [])),
			"quality": float(r.get("quality", 1.0)),
			"bearing_only": bool(r.get("bearing_only", false)),
			"has_entity": bool(r.get("has_entity", String(r.get("entity_id", "")) != "")),
			"tags": _strings(r.get("tags", [])),
			"notes": _strings(r.get("notes", [])),
			"synthetic": false,
		}
		if c["id"] == "":
			c["id"] = String(c["entity_id"])
		if c["id"] == "":
			continue
		if c["track_id"] == "":
			c["track_id"] = c["id"]
		if c["batch"] == "":
			c["batch"] = c["id"]
		if String(c["entity_id"]) != "":
			var ev: Dictionary = _entity_by_id(String(c["entity_id"]))
			if not ev.is_empty():
				if String(c["name"]) == "":
					c["name"] = String(ev.get("name", ""))
				if String(c["name_en"]) == "":
					c["name_en"] = String(ev.get("name_en", ""))
				c["cls"] = String(ev.get("cls", ev.get("class", "")))
				c["role"] = String(ev.get("role", ""))
				c["faction"] = String(ev.get("faction", ""))
				var orbit_raw: Variant = ev.get("orbit", {})
				if orbit_raw is Dictionary and not (orbit_raw as Dictionary).is_empty():
					var orbit: Dictionary = orbit_raw
					c["orbit"] = orbit.duplicate(true)
					c["r"] = (orbit.get("r", []) as Array).duplicate()
					c["v"] = (orbit.get("v", []) as Array).duplicate()
		out.append(_finalize_contact(c))
	return out


func _extract_evidence() -> Array:
	if _core_world != null and _core_world.has_method("vm_evidence"):
		var raw: Variant = _core_world.call("vm_evidence")
		if raw is Array:
			var out: Array = []
			for item in (raw as Array):
				if item is Dictionary:
					out.append((item as Dictionary).duplicate(true))
			return out
	return []


func _extract_events(n: int) -> Array:
	if _core_world != null and _core_world.has_method("recent_events"):
		var raw: Variant = _core_world.call("recent_events", n)
		if raw is Array:
			return (raw as Array).duplicate(true)
	return []


func _entities_of(w: Variant) -> Variant:
	var v: Variant = w.get("entities")
	if v is Array:
		return v
	if w.has_method("entities"):
		return w.call("entities")
	return null


func _entity_by_id(eid: String) -> Dictionary:
	if _scenario_entities.has(eid):
		return _entity_dict(_scenario_entities[eid])
	if _core_world != null and _core_world.has_method("vm_entity"):
		var raw: Variant = _core_world.call("vm_entity", eid)
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			return (raw as Dictionary).duplicate(true)
	return {}


func _entity_dict(e: Variant) -> Dictionary:
	if e == null:
		return {}
	if e is Dictionary:
		return (e as Dictionary).duplicate(true)
	if e is Object:
		var out: Dictionary = {}
		out["id"] = String(_field(e, "id", ""))
		out["batch"] = String(_field(e, "batch", ""))
		out["kind"] = String(_field(e, "kind", "unknown"))
		out["side"] = String(_field(e, "side", "unknown"))
		out["name"] = String(_field(e, "name", ""))
		out["name_en"] = String(_field(e, "name_en", ""))
		out["class"] = String(_field(e, "cls", _field(e, "class", "")))
		out["role"] = String(_field(e, "role", ""))
		out["faction"] = String(_field(e, "faction", ""))
		out["hull"] = String(_field(e, "hull", ""))
		out["capabilities"] = _field(e, "capabilities", [])
		out["signatures"] = _field(e, "signatures", {})
		out["orbit"] = _field(e, "orbit", {})
		out["tags"] = _field(e, "tags", [])
		out["meta"] = _field(e, "meta", {})
		out["ui"] = _field(e, "ui", {})
		out["track_level"] = int(_field(e, "track_level", 0))
		out["identity"] = String(_field(e, "identity", "unknown"))
		out["threat"] = String(_field(e, "threat", ""))
		return out
	return {}


# ══ 归一化 / 索引 ════════════════════════════════════════════════════════

func _finalize_contact(c: Dictionary) -> Dictionary:
	if String(c.get("name", "")) == "":
		c["name"] = "[%s]" % String(c.get("batch", c.get("id", "")))
	if not (c.get("tags", null) is Array):
		c["tags"] = []
	if not (c.get("notes", null) is Array):
		c["notes"] = []
	if not (c.get("sources", null) is Array):
		c["sources"] = []
	if String(c.get("id", "")) == "":
		c["id"] = String(c.get("track_id", c.get("entity_id", "")))
	return c


func _apply_own() -> void:
	for raw in _contacts:
		var c: Dictionary = raw
		var eid := String(c.get("entity_id", ""))
		c["is_own"] = (eid != "" and eid == own_entity_id) or String(c.get("id", "")) == own_id or ("own" in (c.get("tags", []) as Array))
	for raw2 in _synthetic:
		var s: Dictionary = raw2
		s["is_own"] = String(s.get("id", "")) == own_id


func _rebuild_index() -> void:
	_index.clear()
	for raw in all_contacts():
		var c: Dictionary = raw
		_index[String(c.get("id", ""))] = c
		var eid := String(c.get("entity_id", ""))
		if eid != "" and not _index.has(eid):
			_index[eid] = c
		var batch := String(c.get("batch", ""))
		if batch != "" and not _index.has(batch):
			_index[batch] = c
		var tid := String(c.get("track_id", ""))
		if tid != "" and not _index.has(tid):
			_index[tid] = c


# ══ 只读查询 API（供 app / widgets 使用）═════════════════════════════════

func _canonical_contact_id(id: String) -> String:
	if id == "":
		return id
	for raw in all_contacts():
		var c: Dictionary = raw
		if (String(c.get("id", "")) == id or String(c.get("track_id", "")) == id
				or String(c.get("entity_id", "")) == id or String(c.get("batch", "")) == id):
			return String(c.get("id", id))
	return id


func _canonical_entity_id(contact_id: String, fallback: String) -> String:
	var c := contact(contact_id)
	if not c.is_empty() and String(c.get("entity_id", "")) != "":
		return String(c.get("entity_id", ""))
	return fallback


## 全部接触（core 场景航迹 + synthetic），返回浅拷贝数组。
func all_contacts() -> Array:
	var out: Array = []
	out.append_array(_contacts)
	out.append_array(_synthetic)
	return out


func contact(id: String) -> Dictionary:
	if _index.is_empty():
		_rebuild_index()
	var c: Variant = _index.get(id, null)
	if c is Dictionary:
		return (c as Dictionary).duplicate(true)
	return {}


func selected_contact() -> Dictionary:
	return contact(selected_id)


## 完整实体 view-model（接触行 + 实体资料 + 航迹快照）。
func entity(id_or_track: String) -> Dictionary:
	var c := contact(id_or_track)
	if c.is_empty():
		return {}
	var eid := String(c.get("entity_id", ""))
	var vm: Dictionary = {}
	if bool(c.get("synthetic", false)):
		var s: Variant = _synthetic_by_id.get(String(c.get("id", "")), null)
		if s is Dictionary:
			vm = (s as Dictionary).duplicate(true)
	if vm.is_empty() and eid != "":
		vm = _entity_by_id(eid)
	if vm.is_empty():
		vm = _contact_to_entity(c)
	# 用航迹快照覆盖等级/身份/威胁（core 约定：逻辑以航迹为准）
	vm["batch"] = String(c.get("batch", vm.get("batch", "")))
	vm["name"] = String(c.get("name", vm.get("name", "")))
	vm["name_en"] = String(c.get("name_en", vm.get("name_en", "")))
	vm["kind"] = String(vm.get("kind", c.get("kind", "unknown")))
	vm["side"] = String(c.get("side", vm.get("side", "unknown")))
	vm["identity"] = String(c.get("identity", vm.get("identity", "unknown")))
	vm["level"] = int(c.get("level", vm.get("track_level", 0)))
	vm["track_level"] = vm["level"]
	vm["threat"] = String(c.get("threat", vm.get("threat", "")))
	vm["track_id"] = String(c.get("track_id", ""))
	vm["contact"] = c.duplicate(true)
	vm["is_own"] = bool(c.get("is_own", false))
	vm["synthetic"] = bool(c.get("synthetic", false))
	if String(vm.get("id", "")) == "":
		vm["id"] = String(c.get("id", ""))
	# 归一化字段名，UI 不关心 core 内部命名
	vm["cls"] = String(vm.get("cls", vm.get("class", "")))
	if not (vm.get("caps", null) is Array):
		vm["caps"] = _strings(vm.get("capabilities", []))
	if not (vm.get("capabilities", null) is Array):
		vm["capabilities"] = vm["caps"]
	if not (vm.get("tags", null) is Array):
		vm["tags"] = _strings(c.get("tags", []))
	if not (vm.get("signatures", null) is Dictionary):
		vm["signatures"] = {}
	if not (vm.get("orbit", null) is Dictionary):
		vm["orbit"] = {}
	if not (vm.get("meta", null) is Dictionary):
		vm["meta"] = {}
	vm["hull"] = String(vm.get("hull", ""))
	vm["role"] = String(vm.get("role", c.get("role", "")))
	vm["faction"] = String(vm.get("faction", c.get("faction", "")))
	return vm


func _contact_to_entity(c: Dictionary) -> Dictionary:
	var caps: Variant = c.get("caps", [])
	var meta: Variant = c.get("meta", {})
	var sigs: Variant = c.get("signatures", {})
	var orbit: Variant = c.get("orbit", {})
	return {
		"id": String(c.get("entity_id", c.get("id", ""))),
		"batch": String(c.get("batch", "")),
		"kind": String(c.get("kind", "contact")),
		"side": String(c.get("side", "unknown")),
		"name": String(c.get("name", "")),
		"name_en": String(c.get("name_en", "")),
		"cls": String(c.get("cls", "")),
		"role": String(c.get("role", "")),
		"faction": String(c.get("faction", "")),
		"hull": "",
		"capabilities": caps if caps is Array else [],
		"caps": caps if caps is Array else [],
		"signatures": sigs if sigs is Dictionary else {},
		"orbit": orbit if orbit is Dictionary else {},
		"tags": c.get("tags", []),
		"meta": meta if meta is Dictionary and not (meta as Dictionary).is_empty() else {"note": "该航迹无实体资料（虚警/纯回波）"},
		"track_level": int(c.get("level", 0)),
		"identity": String(c.get("identity", "unknown")),
		"threat": String(c.get("threat", "")),
		"r": (c.get("r", []) as Array).duplicate(),
		"v": (c.get("v", []) as Array).duplicate(),
		"track_id": String(c.get("track_id", "")),
		"is_own": bool(c.get("is_own", false)),
		"synthetic": bool(c.get("synthetic", false)),
	}


func state() -> Dictionary:
	_state = _extract_state()
	_state["phase_local"] = phase
	_state["phase_title"] = phase_title if phase_title != "" else _mission_title()
	_state["phase_list"] = phases.duplicate()
	_state["evidence_total"] = _evidence.size()
	_state["mode"] = mode
	_state["source"] = source_label()
	return _state


func evidence() -> Array:
	_evidence = _extract_evidence()
	return _evidence.duplicate(true)


func orders() -> Array:
	if _core_world == null:
		return []
	var raw: Variant = null
	if _core_world.has_method("vm_orders"):
		raw = _core_world.call("vm_orders")
	if raw is Array:
		return (raw as Array).duplicate(true)
	return []


func recent_events(n := 12) -> Array:
	_core_events = _extract_events(n)
	return _core_events.duplicate(true)


func select(id: String) -> bool:
	var c := contact(id)
	if c.is_empty():
		return false
	if not bool(c.get("synthetic", false)) and _core_world != null and _core_world.has_method("select"):
		_core_world.call("select", String(c.get("id", id)))
	selected_id = String(c.get("id", id))
	_state = _extract_state()
	_state = _extract_state()
	return true


func own() -> Dictionary:
	return entity(own_id)


func selected() -> Dictionary:
	return entity(selected_id)


func actions_for(target_id: String) -> Array:
	if _core_world != null and _core_world.has_method("vm_actions"):
		var raw: Variant = _core_world.call("vm_actions", target_id)
		if raw is Array and not (raw as Array).is_empty():
			return _normalize_actions(raw)
	if _core_actions != null and _core_world != null:
		var actor: Variant = null
		var target_obj: Variant = null
		var target_eid := String(contact(target_id).get("entity_id", ""))
		if _core_world.has_method("entity"):
			actor = _core_world.call("own")
			if target_eid != "":
				target_obj = _core_world.call("entity", target_eid)
		if actor != null and target_obj != null:
			var raw2: Variant = _core_actions.call("actions_for", actor, target_obj)
			if raw2 is Array and not (raw2 as Array).is_empty():
				return _normalize_actions(raw2)
	return _fallback_actions(entity(target_id))


func _normalize_actions(raw: Array) -> Array:
	var out: Array = []
	for item in raw:
		if not (item is Dictionary):
			continue
		var r: Dictionary = item
		var levels: Array = []
		if r.get("levels", null) is Array:
			for lv in (r.get("levels") as Array):
				levels.append(int(lv))
		if levels.is_empty():
			levels = [1]
		var tier := int(levels[0])
		for lv2 in levels:
			tier = mini(tier, int(lv2))
		var requires: Array = []
		if r.get("requires_all", null) is Array:
			requires.append_array(_strings(r.get("requires_all")))
		if r.get("requires", null) is Array:
			requires.append_array(_strings(r.get("requires")))
		out.append({
			"id": String(r.get("id", "")),
			"label": String(r.get("label", r.get("id", ""))),
			"label_en": String(r.get("label_en", "")),
			"available": bool(r.get("available", false)),
			"reason": String(r.get("reason", "")),
			"reason_code": String(r.get("reason_code", "")),
			"levels": levels,
			"requires": requires,
			"unsupported": not bool(r.get("supported", true)),
			"duration_s": float(r.get("duration_s", 0.0)),
			"hint": String(r.get("hint", "")),
			"tier": tier,
		})
	return out


func _fallback_actions(target: Dictionary) -> Array:
	var actor := own()
	var out: Array = []
	var tgt_level := int(target.get("level", target.get("track_level", 0)))
	for raw in FALLBACK_ACTIONS:
		var a: Dictionary = (raw as Dictionary).duplicate(true)
		var available := true
		var reason := ""
		var levels: Array = a.get("levels", [1])
		if not bool(a.get("supported", true)):
			available = false
			reason = "未实现（本框架不模拟武器/火控）"
		elif not (tgt_level in levels):
			available = false
			var parts: Array = []
			for lv in levels:
				parts.append("L%d" % int(lv))
			reason = "目标等级不适用（当前 L%d，需要 %s）" % [tgt_level, "/".join(PackedStringArray(parts))]
		else:
			for req in (a.get("requires", []) as Array):
				if not (String(req) in (actor.get("caps", []) as Array)):
					available = false
					reason = "缺少能力：" + String(req)
					break
		a["available"] = available
		a["reason"] = reason
		a["tier"] = int(levels.min()) if not levels.is_empty() else 1
		out.append(a)
	return out


# ══ 任务阶段（UI 演示用；不写 core）══════════════════════════════════════

func advance_phase() -> String:
	if _core_mission != null and _core_mission.has_method("advance"):
		_last_phase_result = {}
		var res: Variant = _core_mission.call("advance", time)
		if res is Dictionary:
			_last_phase_result = (res as Dictionary).duplicate(true)
		var k := String(_field(_core_mission, "kind", ""))
		if k != "":
			phase = k
		phase_title = _mission_title()
		return phase
	var i := phases.find(phase)
	if i >= 0 and i < phases.size() - 1:
		phase = String(phases[i + 1])
	return phase


func last_phase_result() -> Dictionary:
	return _last_phase_result.duplicate(true)


func phase_index() -> int:
	return phases.find(phase)


func _mission_title() -> String:
	if _core_mission != null and _core_mission.has_method("title"):
		return String(_core_mission.call("title"))
	return ""


## mission.prompt() 的只读快照（title/text/hint/options），文本来自 content/story_l1.json。
func _current_phase() -> String:
	if _core_world != null and _core_world.has_method("mission_snapshot"):
		var ms: Variant = _core_world.call("mission_snapshot")
		if ms is Dictionary and String((ms as Dictionary).get("kind", "")) != "":
			phase_title = String((ms as Dictionary).get("title", ""))
			return String((ms as Dictionary).get("kind", ""))
	if _core_mission != null:
		var k := String(_field(_core_mission, "kind", ""))
		if k == "":
			k = String(_field(_core_mission, "phase", ""))
		phase_title = _mission_title()
		if k != "":
			return k
	if _core_world != null and _core_world.has_method("vm_state"):
		var st: Variant = _core_world.call("vm_state")
		if st is Dictionary:
			var pc := String((st as Dictionary).get("phase_context", ""))
			if pc != "":
				for p in phases:
					if String(p).to_upper() == pc.to_upper():
						return String(p)
	if not phases.is_empty():
		return String(phases[0])
	return "PRELUDE"


# ══ V2-3 游戏屏 API：story / core flow / 证据 / 动作 / 战术快照 ═════════

const TACTICAL_SNAPSHOT_PATH := "res://sim/tactical_snapshot.gd"
const DEFAULT_CAMERA := {
	"map_rect": [436.0, 124.0, 1088.0, 752.0],
	"yaw_deg": 0.0, "pitch_deg": 60.0, "scale_px_per_km": 0.0,
	"fit_margin": 0.82, "center_mode": "own",
}

var _snapshot_cls: Variant = null
var _sim_state: Dictionary = {}
var _sim_ready := false
var _tactical_notes: Array[String] = []


# ── 场景文本（story_l1.json → scenario.story）──────────────────────────

func story_data() -> Dictionary:
	return _story.duplicate(true)


## 按 "prelude"/"notice.body"/"report_bodies.HOLD" 这类路径取文本；缺失返回默认值。
func story_get(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = _story
	for raw_part in path.split("."):
		var key := String(raw_part)
		if key == "":
			continue
		if node is Dictionary and (node as Dictionary).has(key):
			node = (node as Dictionary)[key]
		elif node is Array:
			var idx := int(key)
			if idx < 0 or idx >= (node as Array).size():
				return default_value
			node = (node as Array)[idx]
		else:
			return default_value
	return default_value if node == null else node


# ── core flow（V2-CORE-2）：prelude / decision / report / end / mission ─

func vm_flow() -> Dictionary:
	if _core_world != null and _core_world.has_method("vm_flow"):
		var raw: Variant = _core_world.call("vm_flow")
		if raw is Dictionary:
			return (raw as Dictionary).duplicate(true)
	return {
		"t": time, "time_frozen": false,
		"prelude": {}, "decision": {}, "report": {}, "end": {}, "mission": {},
		"flags": {}, "civilians_evacuated": false, "audit_count": 0,
	}


func _flow_call(method: String, args: Array = []) -> Dictionary:
	if _core_world == null or not _core_world.has_method(method):
		return {"ok": false, "reason": "core 未就绪：无 " + method}
	var raw: Variant = _core_world.callv(method, args)
	var out: Dictionary = (raw as Dictionary).duplicate(true) if raw is Dictionary else {"ok": raw != null}
	refresh()
	return out


func prelude_state() -> Dictionary:
	var p: Variant = vm_flow().get("prelude", {})
	return (p as Dictionary).duplicate(true) if p is Dictionary else {}


func prelude_choose_route(id: String) -> Dictionary:
	return _flow_call("prelude_choose_route", [id])


func prelude_choose_window(id: String) -> Dictionary:
	return _flow_call("prelude_choose_window", [id])


func prelude_confirm() -> Dictionary:
	return _flow_call("prelude_confirm", [])


func prelude_execute() -> Dictionary:
	return _flow_call("prelude_execute", [])


func prelude_skip() -> Dictionary:
	return _flow_call("prelude_skip", [])


func open_decision() -> Dictionary:
	var r: Dictionary = _flow_call("open_decision", [])
	if not r.is_empty():
		advance_mission(1)
	return r


func vm_decision() -> Dictionary:
	var d: Variant = vm_flow().get("decision", {})
	return (d as Dictionary).duplicate(true) if d is Dictionary else {}


func choose_ending(kind: String) -> Dictionary:
	var r: Dictionary = _flow_call("choose_ending", [kind])
	if bool(r.get("ok", false)):
		advance_mission(2 if kind == "FIRE" else 1)
	return r


func report_state() -> Dictionary:
	var r: Variant = vm_flow().get("report", {})
	return (r as Dictionary).duplicate(true) if r is Dictionary else {}


func submit_report(truth := true) -> Dictionary:
	return _flow_call("submit_report", [truth])


func end_summary() -> Dictionary:
	var e: Variant = vm_flow().get("end", {})
	return (e as Dictionary).duplicate(true) if e is Dictionary else {}


func restart_world() -> Dictionary:
	return _flow_call("restart", [])


func advance_mission(steps := 1) -> Array:
	if _core_world == null or not _core_world.has_method("advance_mission"):
		return []
	var raw: Variant = _core_world.call("advance_mission", steps)
	refresh()
	return (raw as Array).duplicate(true) if raw is Array else []


func mission_state() -> Dictionary:
	var flow := vm_flow()
	var mission: Dictionary = flow.get("mission", {}) if flow.get("mission", {}) is Dictionary else {}
	var prompt: Dictionary = mission.get("prompt", {}) if mission.get("prompt", {}) is Dictionary else {}
	var kind := String(mission.get("kind", phase))
	if kind == "":
		kind = phase
	var out: Dictionary = {
		"phase": String(mission.get("phase", phase)),
		"phase_id": String(mission.get("phase", phase)),
		"kind": kind,
		"title": String(mission.get("title", phase_title)),
		"prompt": prompt.duplicate(true),
		"options": prompt.get("options", null),
		"index": int(mission.get("index", -1)),
		"total": int(mission.get("total", phases.size())),
		"is_last": bool(mission.get("is_last", false)),
		"countdown_s": decision_countdown(),
		"flags": flow.get("flags", {}),
		"prelude": flow.get("prelude", {}),
		"decision": flow.get("decision", {}),
		"report": flow.get("report", {}),
		"end": flow.get("end", {}),
	}
	return out


## 决策倒计时：story.decision_t - world.t（前置/结束后时间流动）；决策打开后冻结。
func decision_countdown() -> float:
	# V2 场景没有独立执行窗口字段：用 story.decision_t - world.t 作为数据驱动倒计时。
	# 决策打开后 UI 停止推进世界时间 → 倒计时冻结在打开时刻。
	var dt := float(story_get("decision_t", 300.0))
	return maxf(0.0, dt - world_time())


func mission_prompt() -> Dictionary:
	var mission: Dictionary = vm_flow().get("mission", {}) if vm_flow().get("mission", {}) is Dictionary else {}
	var prompt: Variant = mission.get("prompt", {})
	if prompt is Dictionary:
		return (prompt as Dictionary).duplicate(true)
	if _core_mission != null and _core_mission.has_method("prompt"):
		var raw: Variant = _core_mission.call("prompt")
		if raw is Dictionary:
			return (raw as Dictionary).duplicate(true)
	return {}


# ── 证据任务（V2-CORE-2：world.start_evidence / evidence_remaining）─────

func evidence_policy() -> Dictionary:
	if _core_world == null:
		return {}
	var pol: Variant = _core_world.get("evidence_policy")
	return (pol as Dictionary).duplicate(true) if pol is Dictionary else {}


func evidence_min_for_expose() -> int:
	return int(evidence_policy().get("min_for_expose", 2))


func evidence_tasks() -> Array:
	var out: Array = []
	for raw in evidence():
		var ev: Dictionary = raw
		var eid := String(ev.get("id", ""))
		var state := String(ev.get("state", "unknown"))
		var dur := float(ev.get("duration_s", 0.0))
		var remain := dur
		if _core_world != null and _core_world.has_method("evidence_remaining"):
			remain = float(_core_world.call("evidence_remaining", eid))
		var row: Dictionary = ev.duplicate(true)
		row["id"] = eid
		row["label"] = String(ev.get("label", eid))
		row["duration_s"] = dur
		row["shuttle"] = bool(ev.get("shuttle", false))
		row["remain_s"] = maxf(0.0, remain) if state != "done" else 0.0
		row["progress"] = 1.0 if state == "done" else clampf(1.0 - remain / maxf(dur, 1.0), 0.0, 1.0)
		row["available"] = state == "unknown"
		row["reason"] = "已取得" if state == "done" else ("进行中" if state == "in_progress" else "")
		out.append(row)
	return out


func start_evidence(id: String) -> Dictionary:
	if _core_world == null or not _core_world.has_method("start_evidence"):
		return {"ok": false, "reason": "core 未就绪：无 start_evidence"}
	var raw: Variant = _core_world.call("start_evidence", id)
	var out: Dictionary = (raw as Dictionary).duplicate(true) if raw is Dictionary else {"ok": bool(raw)}
	refresh()
	return out


func can_expose() -> bool:
	if _core_world == null or not _core_world.has_method("can_expose"):
		return false
	return bool(_core_world.call("can_expose"))


# ── 动作 → core（V2-CORE-2 perform_action：动作观测/状态由 core 生成）──

func perform_action(action_id: String, target_id: String) -> Dictionary:
	if _core_world == null:
		return {"ok": false, "reason": "core 未就绪"}
	var raw: Variant = null
	if _core_world.has_method("perform_action"):
		raw = _core_world.call("perform_action", action_id, target_id, {})
	elif _core_world.has_method("issue_order"):
		raw = _core_world.call("issue_order", action_id, target_id, {})
	var out: Dictionary = (raw as Dictionary).duplicate(true) if raw is Dictionary else {"ok": false, "reason": "动作调用返回异常"}
	if bool(out.get("ok", false)):
		_action_log.append({"id": action_id, "target_id": target_id, "t": world_time()})
		while _action_log.size() > 200:
			_action_log.pop_front()
	refresh()
	return out


func action_effect(action_id: String) -> Dictionary:
	if _core_actions != null and _core_actions.has_method("definition"):
		var d: Variant = _core_actions.call("definition", action_id)
		if d is Dictionary and (d as Dictionary).get("effect", null) is Dictionary:
			return ((d as Dictionary).get("effect") as Dictionary).duplicate(true)
	return {}


func abort_order(order_id: String) -> Dictionary:
	return _flow_call("abort_order", [order_id])


# ── 世界时间 / 事件 / 无线电 ───────────────────────────────────────────

func advance_world(dt: float) -> Dictionary:
	if _core_world == null or not _core_world.has_method("advance"):
		return {}
	var raw: Variant = _core_world.call("advance", dt)
	time = float(_field(_core_world, "t", time))
	if raw is Dictionary:
		refresh()
		return (raw as Dictionary).duplicate(true)
	return {}


func world_time() -> float:
	time = float(_field(_core_world, "t", time)) if _core_world != null else time
	return time


func has_core() -> bool:
	return _core_world != null


func push_log(kind: String, text: String) -> void:
	if _core_world != null and _core_world.has_method("push_log"):
		_core_world.call("push_log", kind, text)


func push_radio(line: Dictionary) -> void:
	if _core_world != null and _core_world.has_method("push_radio"):
		_core_world.call("push_radio", line)


func recent_radio(n := 6) -> Array:
	if _core_world != null and _core_world.has_method("recent_radio"):
		var raw: Variant = _core_world.call("recent_radio", n)
		if raw is Array:
			return (raw as Array).duplicate(true)
	return []


# ── 战术快照（V2-SENSOR-2：sim/tactical_snapshot.gd，纯数据）──────────

func tactical_available() -> bool:
	if _core_world == null:
		return false
	if _snapshot_cls == null:
		_snapshot_cls = _load_script(TACTICAL_SNAPSHOT_PATH)
	return _snapshot_cls != null


func tactical_notes() -> Array:
	return _tactical_notes.duplicate()


func tactical_ensure_sim() -> bool:
	if not tactical_available():
		return false
	if _sim_ready and not _sim_state.is_empty():
		return true
	var raw: Variant = _snapshot_cls.call("make_sim_state", _core_world, {})
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		_sim_state = (raw as Dictionary).duplicate(true)
		_sim_ready = true
		for note in (_sim_state.get("notes", []) as Array):
			_tactical_notes.append(String(note))
	return _sim_ready


func tactical_sim_state() -> Dictionary:
	return _sim_state


func _camera_cfg(camera_cfg: Dictionary) -> Dictionary:
	var cam: Dictionary = DEFAULT_CAMERA.duplicate(true)
	for key in (camera_cfg as Dictionary).keys():
		cam[key] = camera_cfg[key]
	return cam


func tactical_build(camera_cfg: Dictionary = {}) -> Dictionary:
	if not tactical_ensure_sim():
		return {"available": false, "reason": "sim/tactical_snapshot 不可用（core/sim 未就绪）"}
	var cfg: Dictionary = {"sim_state": _sim_state, "camera": _camera_cfg(camera_cfg)}
	var raw: Variant = _snapshot_cls.call("build", _core_world, _sim_state, cfg)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {"available": false}


## 推进 sim 模型并返回观测建议 → 由 UI 决定是否 ingest（本项目：可用观测直接进 core）。
func tactical_step(dt: float, camera_cfg: Dictionary = {}) -> Dictionary:
	if not tactical_ensure_sim():
		return {"ok": false, "snapshot": {}, "observations": 0, "reason": "sim 未就绪"}
	var cfg: Dictionary = {"sim_state": _sim_state, "camera": _camera_cfg(camera_cfg)}
	var raw: Variant = _snapshot_cls.call("step", _core_world, dt, cfg)
	var snap: Dictionary = {}
	var obs_count := 0
	var events: Array = []
	var suggested: Array = []
	if raw is Dictionary:
		var out: Dictionary = raw
		if out.get("snapshot", null) is Dictionary:
			snap = (out.get("snapshot") as Dictionary).duplicate(true)
		var obs: Variant = out.get("observations", [])
		if obs is Array and _core_world != null and _core_world.has_method("ingest"):
			for item in (obs as Array):
				if item is Dictionary:
					_core_world.call("ingest", item)
					obs_count += 1
		if out.get("events", null) is Array:
			events = (out.get("events") as Array).duplicate(true)
		if out.get("suggested_calls", null) is Array:
			suggested = (out.get("suggested_calls") as Array).duplicate(true)
	if snap.is_empty():
		snap = tactical_build(camera_cfg)
	if obs_count > 0:
		refresh()
	return {"ok": true, "snapshot": snap, "observations": obs_count,
		"events": events, "suggested": suggested}


func tactical_start_channel(kind: String, track_id: String) -> Dictionary:
	if not tactical_ensure_sim():
		return {"ok": false, "reason": "sim 未就绪"}
	var raw: Variant = _snapshot_cls.call("start_channel", _sim_state, kind, track_id)
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {"ok": bool(raw)}


func tactical_stop_channel(kind: String, track_id := "") -> void:
	if tactical_ensure_sim():
		_snapshot_cls.call("stop_channel", _sim_state, kind, track_id)


func tactical_set_radar_enabled(on: bool) -> void:
	if tactical_ensure_sim():
		_snapshot_cls.call("set_radar_enabled", _sim_state, on)


# ══ 重新拉取 / 几何辅助 ═════════════════════════════════════════════════

## 重新拉取 view-model（core tick / 流程动作 / 事件后调用；保留选中）。
func refresh() -> void:
	if _core_world == null:
		return
	_state = _extract_state()
	title = String(_state.get("title", title))
	scenario_id = String(_state.get("scenario_id", scenario_id))
	time = float(_state.get("t", _field(_core_world, "t", time)))
	_contacts = _extract_contacts()
	_evidence = _extract_evidence()
	_apply_own()
	_rebuild_index()
	if not _index.has(selected_id):
		selected_id = own_id
	phase = _current_phase()
	phase_title = _mission_title()


func _vec3_of(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array:
		var arr: Array = value
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


## UI 几何：实体轨道 r/v（km / km·s⁻¹）与航迹方位/距离（无快照时的兜底投影用）。
func geometry_of(id: String) -> Dictionary:
	var c := contact(id)
	if c.is_empty():
		return {}
	var eid := String(c.get("entity_id", ""))
	var ent: Dictionary = _entity_by_id(eid) if eid != "" else {}
	var orbit: Dictionary = ent.get("orbit", {}) if ent.get("orbit", {}) is Dictionary else {}
	var r := _vec3_of(orbit.get("r", c.get("r", [])))
	var v := _vec3_of(orbit.get("v", c.get("v", [])))
	return {
		"id": String(c.get("id", id)),
		"track_id": String(c.get("track_id", "")),
		"entity_id": eid,
		"batch": String(c.get("batch", id)),
		"name": String(c.get("name", "")),
		"kind": String(c.get("kind", "unknown")),
		"side": String(c.get("side", "unknown")),
		"identity": String(c.get("identity", "unknown")),
		"level": int(c.get("level", 0)),
		"r": r,
		"v": v,
		"has_entity": bool(c.get("has_entity", eid != "")),
		"bearing_only": bool(c.get("bearing_only", false)),
		"bearing_deg": float(c.get("bearing_deg", 0.0)),
		"range_km": float(c.get("range_km", -1.0)),
		"orbit": orbit.duplicate(true),
	}


func own_geometry() -> Dictionary:
	return geometry_of(own_id)


# ══ V2-4 UI API：教学 / 损管 / 回放 的只读兜底 ═══════════════════════════
#    core V2-CORE-3 若提供 vm_tutorial/vm_damage/vm_replay/start_repair，则直接转发；
#    未提供时 UI 用可观测证据 + 本地状态兜底，并在返回值里标注 fallback/reason（不硬改 core）。

func action_log() -> Array:
	return _action_log.duplicate(true)


func action_done(action_id: String, target_id := "") -> bool:
	for raw in _action_log:
		var r: Dictionary = raw
		if String(r.get("id", "")) != action_id:
			continue
		if target_id == "" or String(r.get("target_id", "")) == target_id:
			return true
	return false


## 航迹证据只读快照（用于教学步骤派生；core 无 vm_tutorial 时的兜底）。
func track_evidence(id: String) -> Dictionary:
	var c := contact(id)
	if c.is_empty():
		return {}
	var out: Dictionary = {
		"target_id": String(c.get("id", "")),
		"batch": String(c.get("batch", "")),
		"name": String(c.get("name", "")),
		"level": int(c.get("level", 0)),
		"identity": String(c.get("identity", "unknown")),
		"sources": (c.get("sources", []) as Array).duplicate(),
		"classification": {},
		"iff_status": "",
		"has_entity": bool(c.get("has_entity", false)),
	}
	if _core_world != null and _core_world.has_method("track_for"):
		var tr: Variant = _core_world.call("track_for", String(c.get("track_id", c.get("id", ""))))
		if tr != null:
			out["level"] = int(_field(tr, "level", out["level"]))
			out["identity"] = String(_field(tr, "identity_kind", out["identity"]))
			out["sources"] = _strings(_field(tr, "sources", out["sources"]))
			var cls: Variant = _field(tr, "classification", {})
			out["classification"] = (cls as Dictionary).duplicate(true) if cls is Dictionary else {}
			out["iff_status"] = String(_field(tr, "iff_status", ""))
	return out


## 教学步骤（4 步：交叉定位 → 雷达照射 → 型号识别 → IFF/光学）。
## 有 core vm_tutorial() 时转发；否则按「UI 动作日志 + core 航迹证据」派生（只读，不自动完成识别）。
func tutorial_state() -> Dictionary:
	if _core_world != null and _core_world.has_method("vm_tutorial"):
		var raw: Variant = _core_world.call("vm_tutorial")
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			return _normalize_core_tutorial(raw)

	# 目标：当前选中（非己方）→ 否则第一个有实体的非己方接触
	var target_id := ""
	if selected_id != "" and not bool(contact(selected_id).get("is_own", false)):
		target_id = selected_id
	if target_id == "":
		for raw2 in all_contacts():
			var c: Dictionary = raw2
			if bool(c.get("is_own", false)) or not bool(c.get("has_entity", true)):
				continue
			target_id = String(c.get("id", ""))
			break
	var ev: Dictionary = track_evidence(target_id) if target_id != "" else {}
	var level := int(ev.get("level", 0))
	var identity := String(ev.get("identity", "unknown"))
	var sources: Array = ev.get("sources", []) if ev.get("sources", []) is Array else []
	var cls: Dictionary = ev.get("classification", {}) if ev.get("classification", {}) is Dictionary else {}
	var radar_source := false
	for src in sources:
		var s2 := String(src)
		if s2.contains("R") and (s2.begins_with("YW") or s2.begins_with("KD") or s2.contains("R9") or s2.contains("R6")):
			radar_source = true
	var steps: Array = [
		{
			"id": "crossfix", "label": "交叉定位 / CROSSFIX",
			"hint": "用两路方位线交叉出位置（L1 → L2）",
			"done": action_done("crossfix", target_id) or (level >= 2 and not radar_source),
			"via": "动作日志/航迹等级",
		},
		{
			"id": "radar_illum", "label": "雷达照射识别 / RADAR ILLUM",
			"hint": "主动雷达照射拿距离+方位（L2；开机即暴露）",
			"done": action_done("radar_illum", target_id) or action_done("radar_track", target_id) or radar_source,
			"via": "动作日志/来源型号",
		},
		{
			"id": "model_ident", "label": "型号识别 / MODEL IDENT",
			"hint": "光学凝视 + 数据库比对（L2 → L3 分类）",
			"done": action_done("model_ident", target_id) or level >= 3,
			"via": "动作日志/航迹等级",
		},
		{
			"id": "iff_optical", "label": "IFF / 光学通道 / IFF OR OPTICAL",
			"hint": "IFF 问答或光学/红外通道确认身份（IFF 无应答 ≠ 敌意）",
			"done": action_done("iff_query", target_id) or action_done("optical_channel", target_id)
				or action_done("ir_channel", target_id) or level >= 4
				or (identity != "unknown" and identity != "pending"),
			"via": "动作日志/身份",
		},
	]
	var done_count := 0
	var missing: Array = []
	for raw3 in steps:
		var st: Dictionary = raw3
		if bool(st.get("done", false)):
			done_count += 1
		else:
			missing.append(String(st.get("label", "")))
	var gate_reason := ""
	if done_count < steps.size():
		gate_reason = "教学步骤未完成 %d/%d：%s" % [done_count, steps.size(), ", ".join(PackedStringArray(missing))]
	return {
		"fallback": true,
		"reason": "core 无 vm_tutorial()：按 UI 动作日志 + core 航迹证据派生（只读，不自动完成识别）",
		"target_id": target_id,
		"target_name": String(ev.get("name", target_id)),
		"steps": steps,
		"done_count": done_count,
		"total": steps.size(),
		"complete": done_count >= steps.size(),
		"gate_reason": gate_reason,
	}


func _action_label(action_id: String) -> String:
	match action_id:
		"crossfix":
			return "交叉定位 / CROSSFIX"
		"radar_illum", "radar_track":
			return "雷达照射识别 / RADAR ILLUM"
		"model_ident":
			return "型号识别 / MODEL IDENT"
		"iff_query":
			return "IFF 问答 / IFF QUERY"
		"optical_channel":
			return "光学通道 / OPTICAL CHANNEL"
		"ir_channel":
			return "红外通道 / IR CHANNEL"
		_:
			return action_id


## core V2-CORE-3 vm_tutorial() shape → UI 统一 shape（steps/done_count/gate_reason）。
func _normalize_core_tutorial(raw: Dictionary) -> Dictionary:
	var prog: Dictionary = raw.get("progress", {}) if raw.get("progress", {}) is Dictionary else {}
	var done_count := int(prog.get("done", 0))
	var need := int(prog.get("need", maxi(1, (raw.get("required_actions", []) as Array).size() if raw.get("required_actions", []) is Array else 1)))
	var ready := bool(raw.get("ready", done_count >= need))
	var steps: Array = []
	var actions: Array = raw.get("actions", []) if raw.get("actions", []) is Array else []
	for raw_a in actions:
		if not (raw_a is Dictionary):
			continue
		var a: Dictionary = raw_a
		steps.append({
			"id": String(a.get("id", "")),
			"label": String(a.get("label", a.get("id", ""))),
			"hint": String(a.get("reason", "")),
			"done": bool(a.get("done", false)),
			"available": bool(a.get("available", true)),
			"via": "core vm_tutorial",
		})
	var missing: Array = raw.get("missing", []) if raw.get("missing", []) is Array else []
	var missing_labels: Array = []
	for m in missing:
		if m is Dictionary:
			missing_labels.append(String((m as Dictionary).get("label", m.get("id", ""))))
		else:
			missing_labels.append(String(m))
	var hint := String(raw.get("hint", ""))
	hint = hint.replace("{need}", str(need)).replace("{done}", str(done_count))
	var reason := ""
	if not ready:
		reason = hint if hint != "" else "教学门控：识别不足（%d/%d）" % [done_count, need]
		if not missing_labels.is_empty():
			reason += " · 缺 " + ", ".join(PackedStringArray(missing_labels))
	else:
		reason = String(raw.get("done_text", "识别链完成，决策权限已解锁。"))
	return {
		"fallback": false,
		"reason": hint,
		"title": String(raw.get("title", "教学门控 / TUTORIAL")),
		"target_id": "", "target_name": "",
		"steps": steps, "done_count": done_count, "total": need,
		"complete": ready, "ready": ready,
		"gate_reason": "" if ready else reason,
		"done_text": String(raw.get("done_text", "")),
		"decision_pending": bool(raw.get("decision_pending", false)),
	}


## 执行窗口剩余秒：core V2-CORE-3 有 exec_left()/vm_flow().exec_left 时优先，否则用 content.decision_t 兜底。
func exec_left() -> float:
	if _core_world != null and _core_world.has_method("exec_left"):
		var v: Variant = _core_world.call("exec_left")
		if v is float or v is int:
			return maxf(0.0, float(v))
	var flow: Dictionary = vm_flow()
	if flow.get("exec_left", null) is float or flow.get("exec_left", null) is int:
		return maxf(0.0, float(flow.get("exec_left")))
	return maxf(0.0, float(story_get("decision_t", 300.0)) - world_time())


func exec_pct() -> float:
	var flow: Dictionary = vm_flow()
	if flow.get("exec_pct", null) is float or flow.get("exec_pct", null) is int:
		return clampf(float(flow.get("exec_pct")), 0.0, 1.0)
	var total := maxf(1.0, float(flow.get("exec_window_s", story_get("decision_t", 300.0))))
	return clampf(exec_left() / total, 0.0, 1.0)


# ══ V2-5 图层开关（core V2-CORE-4 set_layer/vm_layers；无 core 时 UI 本地兜底）══

var _layers_fallback: Dictionary = {
	"contacts": true, "labels": true, "predictions": true,
	"radar": true, "stations": true, "grid": true,
}


func set_layer(name: String, on: bool) -> void:
	_layers_fallback[name] = on
	if _core_world != null and _core_world.has_method("set_layer"):
		_core_world.call("set_layer", name, on)
	refresh()


func layers_state() -> Dictionary:
	if _core_world != null and _core_world.has_method("vm_layers"):
		var raw: Variant = _core_world.call("vm_layers")
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			var out: Dictionary = (raw as Dictionary).duplicate(true)
			out["fallback"] = false
			return out
	var fb: Dictionary = _layers_fallback.duplicate(true)
	fb["fallback"] = true
	return fb


# ── 回放控制（core V2-CORE-3 可用时转发；否则 UI 本地帧兜底）──────────

func replay_start() -> Dictionary:
	return _flow_call("replay_start", [])


func replay_pause() -> Dictionary:
	return _flow_call("replay_pause", [])


func replay_seek(t_or_index: Variant) -> Dictionary:
	return _flow_call("replay_seek", [t_or_index])


func replay_seek_index(index: int) -> Dictionary:
	if _core_world == null:
		return {"ok": false, "reason": "core 未就绪"}
	if _core_world.has_method("seek_index"):
		return _flow_call("seek_index", [index])
	if _core_world.has_method("replay_seek_index"):
		return _flow_call("replay_seek_index", [index])
	return _flow_call("replay_seek", [index])


func replay_clear() -> Dictionary:
	return _flow_call("replay_clear", [])


func replay_stop() -> Dictionary:
	return _flow_call("replay_stop", [])


func replay_frame() -> Dictionary:
	if _core_world == null:
		return {}
	for method in ["replay_frame", "frame"]:
		if _core_world.has_method(method):
			var raw: Variant = _core_world.call(method)
			if raw is Dictionary:
				return (raw as Dictionary).duplicate(true)
	return {}


## 损管 view-model：core 有 vm_damage() 时转发；否则返回未就绪（UI 本地损管兜底）。
func vm_damage() -> Dictionary:
	if _core_world != null and _core_world.has_method("vm_damage"):
		var raw: Variant = _core_world.call("vm_damage")
		if raw is Dictionary:
			var out: Dictionary = (raw as Dictionary).duplicate(true)
			out["fallback"] = false
			return out
	return {
		"available": false, "fallback": true,
		"reason": "core 无 vm_damage()/start_repair() API；本面板为 UI 本地损管兜底（契约见 docs/09 §32）",
		"sections": [], "queue": [],
	}


func start_repair(section_id: String) -> Dictionary:
	if _core_world != null and _core_world.has_method("start_repair"):
		var raw: Variant = _core_world.call("start_repair", section_id)
		return (raw as Dictionary).duplicate(true) if raw is Dictionary else {"ok": bool(raw)}
	return {"ok": false, "fallback": true, "reason": "core 无 start_repair()；由 UI 本地损管兜底"}


## 回放帧：core 有 vm_replay() 时转发；否则返回未就绪（UI 本地帧记录兜底）。
func vm_replay() -> Dictionary:
	if _core_world != null and _core_world.has_method("vm_replay"):
		var raw: Variant = _core_world.call("vm_replay")
		if raw is Dictionary:
			var out: Dictionary = (raw as Dictionary).duplicate(true)
			out["fallback"] = false
			out["available"] = true
			return out
	return {
		"available": false, "fallback": true,
		"reason": "core 无 vm_replay() API；回放使用 UI 本地帧记录（契约见 docs/09 §32）",
		"frames": [],
	}


# ══ 截图/压测用 synthetic 实体 ═══════════════════════════════════════════

func add_synthetic(count: int) -> int:
	var kinds := ["ship", "station", "tank", "wreck"]
	var sides := ["friend", "hostile", "neutral", "unknown"]
	for i in range(count):
		var idx := _synthetic.size()
		var c := _synthetic_contact(idx, String(kinds[idx % kinds.size()]), String(sides[idx % sides.size()]))
		_synthetic.append(c)
		_synthetic_by_id[String(c["id"])] = c
	_rebuild_index()
	return _synthetic.size()


func _synthetic_contact(idx: int, kind: String, side: String) -> Dictionary:
	var names := {
		"ship": "演示舰船",
		"station": "训练站点",
		"tank": "模拟储罐",
		"wreck": "校准残骸",
	}
	var c: Dictionary = {
		"id": "DEMO-%02d" % (idx + 1),
		"track_id": "DEMO-%02d" % (idx + 1),
		"entity_id": "DEMO-%02d" % (idx + 1),
		"batch": "D%03d" % (idx + 1),
		"name": "%s %02d" % [String(names.get(kind, "演示实体")), idx + 1],
		"name_en": "DEMO %s %02d" % [kind.to_upper(), idx + 1],
		"kind": kind,
		"side": side,
		"cls": _kind_class(kind),
		"role": "演示数据 / SYNTHETIC",
		"faction": "UI DEMO FILL",
		"level": idx % 5,
		"identity": _synthetic_identity(side, idx),
		"threat": _synthetic_threat(side, idx),
		"stale": idx % 7 == 3,
		"age_s": float((idx * 3) % 40),
		"bearing_deg": float((idx * 47) % 360),
		"range_km": float(40 + (idx * 37) % 800),
		"sources": ["DEMO"],
		"quality": 1.0 - float(idx % 5) * 0.1,
		"has_entity": true,
		"tags": ["demo", "synthetic"],
		"notes": ["UI 压测/演示实体，非剧情数据"],
		"synthetic": true,
		"is_own": false,
		"caps": _default_caps(side),
		"orbit": {
			"frame": datum,
			"r": [float(idx * 40 - 160), float(idx * 27 - 108), float(idx % 7) * 12.0],
			"v": [0.2, -0.1, 0.02],
		},
		"signatures": {},
		"meta": {},
	}
	if kind == "station":
		c["signatures"] = {"IFF": "MK-12"}
		c["meta"] = {"radius": "0.4 km", "status": "演示"}
	elif kind == "wreck":
		c["meta"] = {"source": "演示数据"}
	elif kind == "tank":
		c["meta"] = {"capacity": "1,200 t", "status": "演示"}
	return c


func synthetic_count() -> int:
	return _synthetic.size()


# ══ 兜底字段 ════════════════════════════════════════════════════════════

func _kind_class(kind: String) -> String:
	match kind:
		"station":
			return "站点"
		"tank":
			return "储罐"
		"wreck":
			return "残骸"
		_:
			return "舰船"


func _synthetic_identity(side: String, idx: int) -> String:
	match side:
		"friend":
			return "friend"
		"hostile":
			return "hostile" if idx % 3 != 2 else "suspect"
		"neutral":
			return "neutral"
		_:
			return "unknown" if idx % 2 == 0 else "pending"


func _synthetic_threat(side: String, idx: int) -> String:
	match side:
		"friend":
			return "none"
		"hostile":
			return "high" if idx % 2 == 0 else "hostile"
		"neutral":
			return "none"
		_:
			return "pending"


func _default_caps(side: String) -> Array:
	match side:
		"friend":
			return ["comms.radio", "sensor.radar.active", "sensor.optical", "sensor.ir",
				"sensor.iff.interrogator", "datalink.ocuvf"]
		"hostile":
			return ["comms.radio", "sensor.elint.passive", "sensor.iff.interrogator", "datalink.ueg33"]
		_:
			return ["comms.radio", "sensor.optical.passive"]


func _normalize_phases(raw: Variant) -> Array:
	if not (raw is Array) or (raw as Array).is_empty():
		return FALLBACK_PHASES.duplicate()
	var out: Array = []
	for item in (raw as Array):
		if item is Dictionary:
			var d: Dictionary = item
			var pid := String(d.get("kind", d.get("id", d.get("phase", ""))))
			if pid != "":
				out.append(pid)
		else:
			var ps := String(item)
			if ps != "":
				out.append(ps)
	return out if not out.is_empty() else FALLBACK_PHASES.duplicate()


func _strings(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for item in (v as Array):
			out.append(String(item))
	elif v is PackedStringArray:
		for item in (v as PackedStringArray):
			out.append(String(item))
	return out


func _field(obj: Variant, name: String, default_value: Variant) -> Variant:
	if obj == null:
		return default_value
	if obj is Dictionary:
		return (obj as Dictionary).get(name, default_value)
	var v: Variant = obj.get(name)
	if v != null:
		return v
	if obj.has_method(name):
		return obj.call(name)
	return default_value


# ══ 状态/诊断 ════════════════════════════════════════════════════════════

func source_label() -> String:
	match mode:
		"core":
			return "CORE"
		"content":
			return "CONTENT JSON"
		"local-demo":
			return "LOCAL DEMO"
		_:
			return "NONE"


func status_line() -> String:
	var sinfo := ""
	if synthetic_count() > 0:
		sinfo = " + demo %d" % synthetic_count()
	return "src=%s contacts=%d%s own=%s selected=%s title=%s" % [
		source_label(), all_contacts().size(), sinfo, own_id, selected_id, title]


func probe() -> Dictionary:
	return {
		"loaded": loaded,
		"mode": mode,
		"source": source_label(),
		"notes": notes.duplicate(),
		"scenario_path": scenario_path,
		"title": title,
		"scenario_id": scenario_id,
		"own_id": own_id,
		"selected_id": selected_id,
		"contact_count": all_contacts().size(),
		"core_contact_count": _contacts.size(),
		"synthetic_count": synthetic_count(),
		"phase": phase,
		"state": state(),
	}
