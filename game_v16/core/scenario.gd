class_name V2Scenario
extends RefCounted

const REQUIRED_KEYS := ["id", "title", "epoch", "tracks"]

var raw: Dictionary = {}
var id := ""
var title := ""
var epoch := 0.0
var datum := "L1"
var entities: Array = []
var story: Dictionary = {}
var phases: Array = []
var errors: Array[String] = []

static func load_file(path: String) -> V2Scenario:
	var s := V2Scenario.new()
	if not FileAccess.file_exists(path):
		s.errors.append("missing scenario: " + path)
		return s
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		s.errors.append("invalid json: " + path)
		return s
	s.raw = parsed
	s.id = String(s.raw.get("id", ""))
	s.title = String(s.raw.get("title", ""))
	s.epoch = float(s.raw.get("epoch", 0.0))
	s.datum = String(s.raw.get("datum", "L1"))
	s.story = (s.raw.get("story", {}) as Dictionary).duplicate(true)
	s._validate()
	s._build_entities()
	return s

func _validate() -> void:
	for k in REQUIRED_KEYS:
		if not raw.has(k):
			errors.append("scenario missing key: " + k)
	if not (raw.get("tracks", []) is Array):
		errors.append("tracks must be array")
	if not (raw.get("story", {}) is Dictionary):
		errors.append("story must be dictionary")

func _build_entities() -> void:
	var ships_by_id := {}
	for raw_ship in (raw.get("ships", []) as Array):
		if raw_ship is Dictionary:
			ships_by_id[String((raw_ship as Dictionary).get("id", ""))] = raw_ship
	for raw_track in (raw.get("tracks", []) as Array):
		if not (raw_track is Dictionary):
			continue
		var t: Dictionary = raw_track
		var e := V2Entity.from_dict(t)
		# 把 ships 里的静态资料合并进来（名称/舰级/制造方等）。
		var ship: Dictionary = ships_by_id.get(e.id, {})
		if not ship.is_empty():
			e.name = String(ship.get("name", e.name))
			e.name_en = String(ship.get("name_en", e.name_en))
			e.cls = String(ship.get("ship_class", e.cls))
			e.role = String(ship.get("role", e.role))
			e.faction = String(ship.get("faction", e.faction))
			e.tags.append("own_ship" if bool(ship.get("own", false)) else "fleet")
		if bool(t.get("own", false)):
			e.tags.append("own")
			if not ("own" in e.tags):
				e.tags.append("own")
		e.track_level = int(t.get("level", 0))
		e.identity = String(t.get("identity", "unknown"))
		e.threat = String(t.get("threat", ""))
		e.kind = "ship"
		e.capabilities = _default_capabilities(e)
		entities.append(e)
	if not (raw.get("story", {}) is Dictionary):
		return
	var ph = (story as Dictionary).get("phases", [])
	if ph is Array:
		phases = ph

func _default_capabilities(e: V2Entity) -> Array[String]:
	# 第一阶段：旧数据没有 capability 字段，按阵营给默认能力；
	# 后续 content/entities/*.json 会覆盖这里。
	var caps: Array[String] = ["comms.radio"]
	match e.side:
		"friend":
			caps.append_array(["sensor.radar.active", "sensor.optical", "sensor.ir",
				"sensor.iff.interrogator", "datalink.ocuvf"])
		"hostile":
			caps.append_array(["sensor.elint.passive", "sensor.iff.interrogator", "datalink.ueg33"])
		_:
			caps.append("sensor.optical.passive")
	return caps

func find_entity(eid: String) -> V2Entity:
	for e in entities:
		if e.id == eid:
			return e
	return null

func by_batch(batch: String) -> V2Entity:
	for e in entities:
		if e.id == batch:
			return e
	return null
