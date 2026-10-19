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
			if m.has_method("attach_world"):
				m.call("attach_world", w)
			_core_mission = m
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
func mission_prompt() -> Dictionary:
	if _core_mission != null and _core_mission.has_method("prompt"):
		var res: Variant = _core_mission.call("prompt")
		if res is Dictionary:
			return (res as Dictionary).duplicate(true)
	return {}


func _current_phase() -> String:
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
