class_name V2DamageModel
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# V2 损管/毁伤模型（R2-DAMAGE-1）
#
# 完整、可验证的舰船分区损管模型（技术 demo 用；**不含武器系统**）：
#   - 分区：hull/power/propulsion/sensors/comms/tanks/docking，
#     integrity 0..1、state（nominal/degraded/damaged/critical/destroyed）、
#     火灾/失压/断电标志、维修难度（repair_s 来自内容文件）。
#   - 伤害输入：apply_hit(section, energy, penetration, direction, source)；
#     穿透/溢出到相邻分区；火灾/失压/断电随时间发展；分区毁坏后果。
#   - 损管资源：维修队（teams）、备件（spares）、电力（power）、人员（personnel）；
#     assign_repair/cancel_repair/set_priority/step(dt)；进度/剩余/失败条件。
#   - 只读 view-model：vm_damage() → sections/events/queue/resources/summary/effects。
#   - 内容：framework/content/damage_l1.json（本舰/敌舰档案、阈值、维修参数，
#     不在代码写死）；本模型不生成武器/命中，只接受外部伤害输入。
#
# 单位：integrity 0..1；energy 0..1（归一化命中能量）；时间 s；全部 JSON 可序列化。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_CONTENT_PATH := "res://framework/content/damage_l1.json"
const SECTION_IDS := ["hull", "power", "propulsion", "sensors", "comms", "tanks", "docking"]
const MAX_EVENTS := 200
const VM_EVENT_LIMIT := 64

var content: Dictionary = {}
var entity_id := ""
var name := ""
var ship_class := ""
var sections: Array = []
var events: Array = []
var queue: Array = []
var resources: Dictionary = {}
var t := 0.0
var errors: Array[String] = []
var last_effects: Dictionary = {}
var ready := false

var _team_seq := 0
var _hit_seq := 0

# ── 内容装载 ─────────────────────────────────────────────────────

## 读取 JSON 内容（res:// 与项目相对路径兼容）。
static func load_content(path := DEFAULT_CONTENT_PATH) -> Dictionary:
	var candidates: Array = [path]
	var base := ProjectSettings.globalize_path("res://")
	candidates.append(base.path_join("../framework/content/damage_l1.json").simplify_path())
	for raw_path in candidates:
		var p := String(raw_path)
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			return parsed
	return {}

## 内容中可用的舰船档案 id。
static func list_ships(from_content: Dictionary) -> Array:
	var ships: Dictionary = from_content.get("ships", {}) if from_content.get("ships") is Dictionary else {}
	var out: Array = []
	for k in ships.keys():
		out.append(String(k))
	out.sort()
	return out

## 用内容档案初始化本模型（每个实例 = 一艘舰）。
## content_override 为空时从 damage_l1.json 装载；ship_id 默认本舰 harmattan。
func setup(content_override := {}, ship_id := "harmattan") -> bool:
	errors.clear()
	content = content_override if content_override is Dictionary and not (content_override as Dictionary).is_empty() else load_content()
	if content.is_empty():
		errors.append("damage content 未就绪：%s" % DEFAULT_CONTENT_PATH)
		ready = false
		return false
	var ships: Dictionary = content.get("ships", {}) if content.get("ships") is Dictionary else {}
	if not ships.has(ship_id):
		errors.append("未知舰船档案：%s（可用：%s）" % [ship_id, str(list_ships(content))])
		ready = false
		return false
	var profile: Dictionary = ships[ship_id]
	entity_id = String(profile.get("id", ship_id))
	name = String(profile.get("name", entity_id))
	ship_class = String(profile.get("class", ""))
	sections = []
	for raw in (profile.get("sections", []) as Array):
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var sec := {
			"id": String(d.get("id", "")),
			"label": String(d.get("label", d.get("id", ""))),
			"kind": String(d.get("kind", "")),
			"integrity": clampf(float(d.get("integrity", 1.0)), 0.0, 1.0),
			"systems": (d.get("systems", []) as Array).duplicate(),
			"requires_power": bool(d.get("requires_power", false)),
			"power_critical": bool(d.get("power_critical", false)),
			"adjacent": (d.get("adjacent", []) as Array).duplicate(),
			"repair_s": maxf(1.0, float(d.get("repair_s", 60.0))),
			"fire_risk": clampf(float(d.get("fire_risk", 0.0)), 0.0, 1.0),
			"vacuum_risk": clampf(float(d.get("vacuum_risk", 0.0)), 0.0, 1.0),
			# 运行时
			"state": "nominal",
			"fire": {"active": false, "intensity": 0.0, "accum_s": 0.0},
			"decompression": {"active": false, "intensity": 0.0, "accum_s": 0.0},
			"powered": true,
			"power_loss": false,
			"repair": {},
		}
		sec["state"] = _state_for(float(sec.get("integrity", 1.0)))
		sections.append(sec)
	var repair: Dictionary = content.get("repair", {}) if content.get("repair") is Dictionary else {}
	resources = {
		"teams_total": int(repair.get("teams_total", 2)),
		"teams_busy": 0,
		"spares": int(repair.get("spares", 3)),
		"spares_used": 0,
		"power": float(repair.get("power_max", 200.0)),
		"power_max": float(repair.get("power_max", 200.0)),
		"personnel": int(repair.get("personnel", 12)),
		"personnel_used": 0,
	}
	events = []
	queue = []
	t = 0.0
	_team_seq = 0
	_hit_seq = 0
	ready = true
	_recompute_effects()
	return true

func reset() -> void:
	if content.is_empty():
		setup({}, entity_id)
	else:
		setup(content, entity_id)

# ── 查询辅助 ─────────────────────────────────────────────────────

func section(section_id: String) -> Dictionary:
	for raw in sections:
		if String((raw as Dictionary).get("id", "")) == section_id:
			return raw as Dictionary
	return {}

func section_ids() -> Array:
	var out: Array = []
	for raw in sections:
		out.append(String((raw as Dictionary).get("id", "")))
	return out

func _content_dict(key: String) -> Dictionary:
	return (content.get(key, {}) as Dictionary) if content.get(key) is Dictionary else {}

func _state_for(integrity: float) -> String:
	var th: Dictionary = _content_dict("state_thresholds")
	var destroyed := float(th.get("destroyed", 0.001))
	var damaged := float(th.get("damaged", 0.25))
	var degraded := float(th.get("degraded", 0.65))
	var nominal := float(th.get("nominal", 0.9))
	if integrity <= destroyed:
		return "destroyed"
	if integrity >= nominal:
		return "nominal"
	if integrity >= degraded:
		return "degraded"
	if integrity >= damaged:
		return "damaged"
	return "critical"

func _set_integrity(sec: Dictionary, value: float) -> void:
	sec["integrity"] = clampf(value, 0.0, 1.0)
	sec["state"] = _state_for(float(sec["integrity"]))

func _event(type_name: String, section_id: String, text: String, extra := {}) -> Dictionary:
	var ev := {
		"seq": events.size() + 1,
		"t": t,
		"type": type_name,
		"section": section_id,
		"text": text,
	}
	for k in extra.keys():
		ev[k] = extra[k]
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	return ev

func _job_for(section_id: String) -> Dictionary:
	for raw in queue:
		var job: Dictionary = raw
		if String(job.get("section", "")) == section_id and String(job.get("status", "")) != "cancelled":
			return job
	return {}

func _sort_queue() -> void:
	queue.sort_custom(func(a, b):
		var pa := int((a as Dictionary).get("priority", 2))
		var pb := int((b as Dictionary).get("priority", 2))
		if pa != pb:
			return pa < pb
		return int((a as Dictionary).get("order", 0)) < int((b as Dictionary).get("order", 0))
	)

# ── 伤害输入 ─────────────────────────────────────────────────────

## 命中输入。energy 0..1（可 >1 表示超量命中，内部 clamp 到 2.0）；
## penetration 0..1；direction ∈ fore/aft/port/starboard/ventral/dorsal 或任意字符串。
## 返回 {ok, hit, overflow_sections, events, section, summary, effects}。
func apply_hit(section_id: String, energy: float, penetration := 0.5,
		direction := "fore", source := "unknown") -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "模型未初始化"}
	var sec := section(section_id)
	if sec.is_empty():
		return {"ok": false, "reason": "未知分区：%s" % section_id}
	var ev_start := events.size()
	var e := clampf(float(energy), 0.0, 2.0)
	var pen := clampf(float(penetration), 0.0, 1.0)
	var armor: Dictionary = _content_dict("armor")
	var resist := clampf(float(armor.get("kinetic_resist", 0.12)) * (1.0 - pen)
		+ float(armor.get("energy_resist", 0.08)) * pen, 0.0, 0.95)
	var damage := e * (1.0 - resist)
	if String(sec.get("state", "")) == "destroyed":
		damage *= 0.25   # 已毁坏分区只吸收少量溢出
	var integrity_before := float(sec.get("integrity", 1.0))
	_set_integrity(sec, integrity_before - damage)
	_hit_seq += 1
	var hit := {
		"hit_id": _hit_seq,
		"section": String(sec.get("id", "")),
		"energy": e,
		"penetration": pen,
		"direction": String(direction),
		"source": String(source),
		"damage": damage,
		"integrity_before": integrity_before,
		"integrity_after": float(sec.get("integrity", 0.0)),
		"state": String(sec.get("state", "")),
	}
	_event("hit", String(sec.get("id", "")),
		"命中 %s：能量 %.2f · 穿透 %.2f · 完整度 %.0f%% → %s" % [
			String(sec.get("label", "")), e, pen, float(sec.get("integrity", 0.0)) * 100.0,
			String(sec.get("state", ""))], hit)
	# 穿透/溢出到相邻分区
	var overflow: Array = []
	var pen_cfg: Dictionary = _content_dict("penetration")
	if e >= float(pen_cfg.get("min_energy", 0.25)) and pen > 0.0 and String(sec.get("state", "")) != "destroyed":
		overflow = _apply_overflow(sec, e * pen * float(pen_cfg.get("overflow_ratio", 0.4)),
			String(direction), int(pen_cfg.get("max_sections", 2)))
	# 火灾/失压
	_try_ignite_fire(sec, e)
	_try_decompression(sec, e, pen)
	# 断电传播 / 毁坏后果
	_update_power()
	if String(sec.get("state", "")) == "destroyed":
		_on_section_destroyed(sec)
	_recompute_effects()
	var new_events: Array = []
	for i in range(ev_start, events.size()):
		new_events.append((events[i] as Dictionary).duplicate(true))
	return {
		"ok": true,
		"hit": hit,
		"overflow_sections": overflow,
		"events": new_events,
		"section": sec.duplicate(true),
		"summary": summary(),
		"effects": last_effects.duplicate(true),
	}

func _apply_overflow(from_sec: Dictionary, overflow_energy: float, direction: String,
		max_sections: int) -> Array:
	var adj: Array = from_sec.get("adjacent", [])
	if adj.is_empty() or overflow_energy <= 0.0:
		return []
	var order := adj.duplicate()
	# 方向只影响溢出优先顺序（确定性；不伪造武器方向）
	var dirs: Array = (_content_dict("penetration").get("directions", []) as Array)
	var rot := dirs.find(direction)
	if rot > 0 and order.size() > 1:
		var rotated: Array = []
		for i in range(order.size()):
			rotated.append(order[(i + rot) % order.size()])
		order = rotated
	var out: Array = []
	var count := mini(maxi(1, max_sections), order.size())
	var per := overflow_energy / float(count)
	var armor: Dictionary = _content_dict("armor")
	var resist := clampf(float(armor.get("kinetic_resist", 0.12)) * 0.5
		+ float(armor.get("energy_resist", 0.08)) * 0.5, 0.0, 0.95)
	for i in range(count):
		var sid := String(order[i])
		var dst := section(sid)
		if dst.is_empty():
			continue
		var dmg := per * (1.0 - resist)
		_set_integrity(dst, float(dst.get("integrity", 1.0)) - dmg)
		_event("penetration", String(dst.get("id", "")),
			"穿透溢出 → %s：-%.1f%% 完整度（%s）" % [
				String(dst.get("label", "")), dmg * 100.0, String(dst.get("state", ""))],
			{"from": String(from_sec.get("id", "")), "damage": dmg, "source_energy": overflow_energy})
		out.append(sid)
		if String(dst.get("state", "")) == "destroyed":
			_on_section_destroyed(dst)
	return out

func _try_ignite_fire(sec: Dictionary, energy: float) -> void:
	var fire_cfg: Dictionary = _content_dict("fire")
	var risk := float(sec.get("fire_risk", 0.0))
	if risk < 0.2 or energy < float(fire_cfg.get("ignite_threshold", 0.18)):
		return
	if bool((sec.get("fire", {}) as Dictionary).get("active", false)):
		return
	if String(sec.get("state", "")) == "destroyed":
		return
	var intensity := clampf(energy * float(fire_cfg.get("ignite_intensity_base", 0.8)), 0.2, 0.95)
	sec["fire"] = {"active": true, "intensity": intensity, "accum_s": 0.0}
	_event("fire", String(sec.get("id", "")),
		"火灾：%s 起火（强度 %.2f）" % [String(sec.get("label", "")), intensity],
		{"intensity": intensity})

func _try_decompression(sec: Dictionary, energy: float, penetration: float) -> void:
	var dec_cfg: Dictionary = _content_dict("decompression")
	var risk := float(sec.get("vacuum_risk", 0.0))
	if risk < 0.2 or energy < float(dec_cfg.get("activate_threshold", 0.22)):
		return
	if penetration < 0.2 and String(sec.get("kind", "")) not in ["hull", "tanks"]:
		return
	if bool((sec.get("decompression", {}) as Dictionary).get("active", false)):
		return
	if String(sec.get("state", "")) == "destroyed":
		return
	var intensity := clampf(energy, 0.2, 1.0)
	sec["decompression"] = {"active": true, "intensity": intensity, "accum_s": 0.0}
	_event("decompression", String(sec.get("id", "")),
		"失压：%s 出现失压（强度 %.2f）" % [String(sec.get("label", "")), intensity],
		{"intensity": intensity})

func _on_section_destroyed(sec: Dictionary) -> void:
	sec["fire"] = {"active": false, "intensity": 0.0, "accum_s": 0.0}
	sec["decompression"] = {"active": false, "intensity": 0.0, "accum_s": 0.0}
	var job := _job_for(String(sec.get("id", "")))
	if not job.is_empty() and String(job.get("status", "")) == "active":
		_job_fail(job, "section_destroyed")
	_event("destroyed", String(sec.get("id", "")),
		"分区毁坏：%s（不可现场修复）" % String(sec.get("label", "")))

# ── 损管 ─────────────────────────────────────────────────────────

## 指派维修（priority 1=最高，3=最低）。返回 {ok, job, resources}。
func assign_repair(section_id: String, priority := 2) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "模型未初始化"}
	var sec := section(section_id)
	if sec.is_empty():
		return {"ok": false, "reason": "未知分区：%s" % section_id}
	if String(sec.get("state", "")) == "destroyed":
		return {"ok": false, "reason": "分区已毁坏，不可现场修复", "section": section_id}
	var repair_cfg: Dictionary = _content_dict("repair")
	var pr := clampi(int(priority), int(repair_cfg.get("min_priority", 1)),
		int(repair_cfg.get("max_priority", 3)))
	var old := _job_for(section_id)
	if not old.is_empty():
		if String(old.get("status", "")) in ["queued", "active"]:
			return {"ok": false, "reason": "已在维修队列", "job": old.duplicate(true)}
	var job := {
		"section": section_id,
		"priority": pr,
		"status": "queued",
		"progress_s": 0.0,
		"remaining_s": float(sec.get("repair_s", 60.0)),
		"required_s": float(sec.get("repair_s", 60.0)),
		"team": 0,
		"reason": "",
		"order": queue.size(),
		"started_t": -1.0,
		"finished_t": -1.0,
	}
	queue.append(job)
	_sort_queue()
	_event("repair_queued", section_id,
		"损管：指派维修 %s（优先级 %d）" % [String(sec.get("label", "")), pr],
		{"priority": pr})
	return {"ok": true, "job": job.duplicate(true), "resources": resources.duplicate(true)}

func cancel_repair(section_id: String) -> Dictionary:
	var job := _job_for(section_id)
	if job.is_empty():
		return {"ok": false, "reason": "不在维修队列"}
	if String(job.get("status", "")) == "active":
		_free_job_resources(job)
	var idx := queue.find(job)
	if idx >= 0:
		queue.remove_at(idx)
	_event("repair_cancelled", section_id,
		"损管：取消维修 %s（已消耗备件不返还）" % String(section(section_id).get("label", section_id)),
		{})
	return {"ok": true, "queue": queue.duplicate(true), "resources": resources.duplicate(true)}

func set_priority(section_id: String, priority: int) -> Dictionary:
	var job := _job_for(section_id)
	if job.is_empty():
		return {"ok": false, "reason": "不在维修队列"}
	var repair_cfg: Dictionary = _content_dict("repair")
	var pr := clampi(int(priority), int(repair_cfg.get("min_priority", 1)),
		int(repair_cfg.get("max_priority", 3)))
	job["priority"] = pr
	_sort_queue()
	return {"ok": true, "job": job.duplicate(true), "queue": queue.duplicate(true)}

func _free_job_resources(job: Dictionary) -> void:
	if String(job.get("status", "")) != "active":
		return
	resources["teams_busy"] = maxi(0, int(resources.get("teams_busy", 0)) - 1)
	resources["personnel_used"] = maxi(0, int(resources.get("personnel_used", 0))
		- int(_content_dict("repair").get("personnel_per_team", 2)))
	job["team"] = 0

func _job_fail(job: Dictionary, reason: String) -> void:
	_free_job_resources(job)
	job["status"] = "failed"
	job["reason"] = reason
	job["finished_t"] = t
	var sec := section(String(job.get("section", "")))
	_event("repair_failed", String(job.get("section", "")),
		"损管失败：%s（%s）" % [String(sec.get("label", job.get("section", ""))), reason],
		{"reason": reason})

func _job_done(job: Dictionary) -> void:
	var sid := String(job.get("section", ""))
	var sec := section(sid)
	_free_job_resources(job)
	if not sec.is_empty():
		_set_integrity(sec, 1.0)
		sec["fire"] = {"active": false, "intensity": 0.0, "accum_s": 0.0}
		sec["decompression"] = {"active": false, "intensity": 0.0, "accum_s": 0.0}
	job["status"] = "done"
	job["progress_s"] = float(job.get("required_s", 0.0))
	job["remaining_s"] = 0.0
	job["finished_t"] = t
	_event("repair_done", sid, "损管：%s 修复完成" % String(sec.get("label", sid)), {})

# ── 每帧推进 ─────────────────────────────────────────────────────

## 推进 dt 秒：火灾/失压/断电发展 + 维修队列进度 + 资源消耗。
func step(dt: float) -> Dictionary:
	if not ready:
		return {"ok": false, "reason": "模型未初始化"}
	var d := maxf(0.0, float(dt))
	if d <= 0.0:
		return {"ok": true, "t": t}
	t += d
	_advance_fire(d)
	_advance_decompression(d)
	_update_power()
	_advance_repairs(d)
	_recompute_effects()
	return {"ok": true, "t": t, "summary": summary(), "effects": last_effects.duplicate(true)}

func _advance_fire(dt: float) -> void:
	var fire_cfg: Dictionary = _content_dict("fire")
	for raw in sections:
		var sec: Dictionary = raw
		var fire: Dictionary = sec.get("fire", {})
		if not bool(fire.get("active", false)):
			continue
		fire["intensity"] = minf(1.0, float(fire.get("intensity", 0.0))
			+ float(fire_cfg.get("growth_per_s", 0.09)) * dt)
		_set_integrity(sec, float(sec.get("integrity", 1.0))
			- float(fire_cfg.get("damage_per_s", 0.012)) * float(fire["intensity"]) * dt)
		if String(sec.get("state", "")) == "destroyed":
			_on_section_destroyed(sec)
			continue
		fire["accum_s"] = float(fire.get("accum_s", 0.0)) + dt
		if float(fire["intensity"]) >= float(fire_cfg.get("spread_threshold", 0.55)) \
				and float(fire["accum_s"]) >= float(fire_cfg.get("spread_interval_s", 6.0)):
			fire["accum_s"] = 0.0
			var target := _lowest_integrity_adjacent(sec, "fire")
			if not target.is_empty():
				target["fire"] = {"active": true,
					"intensity": float(fire_cfg.get("spread_ignite_intensity", 0.35)),
					"accum_s": 0.0}
				_event("fire_spread", String(target.get("id", "")),
					"火灾蔓延：%s → %s" % [String(sec.get("label", "")),
						String(target.get("label", ""))], {})

func _advance_decompression(dt: float) -> void:
	var dec_cfg: Dictionary = _content_dict("decompression")
	for raw in sections:
		var sec: Dictionary = raw
		var dec: Dictionary = sec.get("decompression", {})
		if not bool(dec.get("active", false)):
			continue
		_set_integrity(sec, float(sec.get("integrity", 1.0))
			- float(dec_cfg.get("damage_per_s", 0.008)) * float(dec.get("intensity", 1.0)) * dt)
		if String(sec.get("state", "")) == "destroyed":
			_on_section_destroyed(sec)
			continue
		dec["accum_s"] = float(dec.get("accum_s", 0.0)) + dt
		if float(dec["accum_s"]) >= float(dec_cfg.get("spread_interval_s", 10.0)):
			dec["accum_s"] = 0.0
			var target := _lowest_integrity_adjacent(sec, "decompression")
			if not target.is_empty():
				target["decompression"] = {"active": true,
					"intensity": float(dec_cfg.get("spread_ignite_intensity", 0.3)),
					"accum_s": 0.0}
				_event("decompression_spread", String(target.get("id", "")),
					"失压扩散：%s → %s" % [String(sec.get("label", "")),
						String(target.get("label", ""))], {})

func _lowest_integrity_adjacent(sec: Dictionary, hazard: String) -> Dictionary:
	var best: Dictionary = {}
	var best_integrity := 2.0
	for raw in (sec.get("adjacent", []) as Array):
		var dst := section(String(raw))
		if dst.is_empty() or String(dst.get("state", "")) == "destroyed":
			continue
		if hazard == "fire" and bool((dst.get("fire", {}) as Dictionary).get("active", false)):
			continue
		if hazard == "decompression" and bool((dst.get("decompression", {}) as Dictionary).get("active", false)):
			continue
		var integ := float(dst.get("integrity", 1.0))
		if integ < best_integrity:
			best_integrity = integ
			best = dst
	return best

## 断电传播：power 分区完整度低于阈值时，requires_power 分区失去电力。
func _update_power() -> void:
	var power_cfg: Dictionary = _content_dict("power")
	var power_sec := section("power")
	if power_sec.is_empty():
		return
	var lost := float(power_sec.get("integrity", 1.0)) < float(power_cfg.get("loss_integrity_threshold", 0.5))
	var restored := float(power_sec.get("integrity", 1.0)) >= float(power_cfg.get("restore_integrity_threshold", 0.65))
	var propagate: Array = power_cfg.get("propagate_sections", ["sensors", "comms", "docking", "propulsion"])
	for raw in sections:
		var sec: Dictionary = raw
		var sid := String(sec.get("id", ""))
		if not bool(sec.get("requires_power", false)) and not propagate.has(sid):
			sec["powered"] = true
			sec["power_loss"] = false
			continue
		var was_lost := bool(sec.get("power_loss", false))
		if lost:
			sec["powered"] = false
			sec["power_loss"] = true
			if not was_lost:
				_event("power_loss", sid, "断电：%s 失去供电" % String(sec.get("label", sid)), {})
		elif restored:
			sec["powered"] = true
			sec["power_loss"] = false
			if was_lost:
				_event("power_restored", sid, "供电恢复：%s" % String(sec.get("label", sid)), {})

func _advance_repairs(dt: float) -> void:
	var repair_cfg: Dictionary = _content_dict("repair")
	var teams_total := int(resources.get("teams_total", repair_cfg.get("teams_total", 2)))
	var teams_busy := int(resources.get("teams_busy", 0))
	var teams_changed := true
	# 1) 分配维修队/备件/人员（按队列优先级）
	while teams_changed:
		teams_changed = false
		teams_busy = int(resources.get("teams_busy", 0))
		if teams_busy >= teams_total:
			break
		var candidate: Dictionary = {}
		for raw in queue:
			var job: Dictionary = raw
			if String(job.get("status", "")) == "queued":
				candidate = job
				break
		if candidate.is_empty():
			break
		var spares := int(resources.get("spares", 0))
		if spares < int(repair_cfg.get("spares_per_job", 1)):
			_job_fail(candidate, "spares")
			teams_changed = true
			continue
		var personnel_need := int(repair_cfg.get("personnel_per_team", 2))
		if int(resources.get("personnel_used", 0)) + personnel_need > int(resources.get("personnel", 12)):
			_job_fail(candidate, "personnel")
			teams_changed = true
			continue
		resources["spares"] = spares - int(repair_cfg.get("spares_per_job", 1))
		resources["spares_used"] = int(resources.get("spares_used", 0)) + int(repair_cfg.get("spares_per_job", 1))
		resources["teams_busy"] = teams_busy + 1
		resources["personnel_used"] = int(resources.get("personnel_used", 0)) + personnel_need
		_team_seq += 1
		candidate["status"] = "active"
		candidate["team"] = _team_seq
		candidate["started_t"] = t
		_event("repair_start", String(candidate.get("section", "")),
			"开始维修 %s（第 %d 组）" % [
				String(section(String(candidate.get("section", ""))).get("label", "")), _team_seq],
			{"priority": int(candidate.get("priority", 2))})
		teams_changed = true
	# 2) 电力恢复
	resources["power"] = minf(float(resources.get("power_max", 200.0)),
		float(resources.get("power", 0.0)) + float(repair_cfg.get("power_recharge_per_s", 1.0)) * dt)
	# 3) 推进 active 维修（火灾/失压先压制，再修结构；完成时清障并恢复完整度）
	for raw in queue.duplicate(true):
		var job: Dictionary = raw
		if String(job.get("status", "")) != "active":
			continue
		var real_job := _job_for(String(job.get("section", "")))
		if real_job.is_empty():
			continue
		job = real_job
		var draw := float(repair_cfg.get("power_per_s", 0.5)) * dt
		if float(resources.get("power", 0.0)) < draw:
			_job_fail(job, "power")
			continue
		resources["power"] = float(resources.get("power", 0.0)) - draw
		var sec := section(String(job.get("section", "")))
		if sec.is_empty():
			_job_fail(job, "section_missing")
			continue
		if String(sec.get("state", "")) == "destroyed":
			_job_fail(job, "section_destroyed")
			continue
		var fire: Dictionary = sec.get("fire", {})
		if bool(fire.get("active", false)):
			fire["intensity"] = maxf(0.0, float(fire.get("intensity", 0.0))
				- float(_content_dict("fire").get("suppress_rate_per_s", 0.4)) * dt)
			if float(fire.get("intensity", 0.0)) <= 0.0:
				fire["active"] = false
				fire["intensity"] = 0.0
				_event("fire_out", String(sec.get("id", "")),
					"火灾扑灭：%s" % String(sec.get("label", "")), {})
		var dec: Dictionary = sec.get("decompression", {})
		if bool(dec.get("active", false)):
			dec["intensity"] = maxf(0.0, float(dec.get("intensity", 0.0))
				- float(_content_dict("decompression").get("seal_rate_per_s", 0.35)) * dt)
			if float(dec.get("intensity", 0.0)) <= 0.0:
				dec["active"] = false
				dec["intensity"] = 0.0
				_event("sealed", String(sec.get("id", "")),
					"失压封堵：%s" % String(sec.get("label", "")), {})
		job["progress_s"] = float(job.get("progress_s", 0.0)) \
			+ dt * float(repair_cfg.get("team_speed", 1.0))
		job["remaining_s"] = maxf(0.0, float(job.get("required_s", 60.0)) - float(job["progress_s"]))
		if float(job["progress_s"]) >= float(job.get("required_s", 60.0)):
			_job_done(job)
	# 4) 更新每分区 repair 只读快照
	for raw in sections:
		var sec2: Dictionary = raw
		var jb := _job_for(String(sec2.get("id", "")))
		if jb.is_empty():
			sec2["repair"] = {}
		else:
			sec2["repair"] = {
				"status": String(jb.get("status", "")),
				"priority": int(jb.get("priority", 2)),
				"progress_s": float(jb.get("progress_s", 0.0)),
				"required_s": float(jb.get("required_s", 0.0)),
				"remaining_s": float(jb.get("remaining_s", 0.0)),
				"reason": String(jb.get("reason", "")),
			}

# ── 效果映射 / 摘要 / view-model ─────────────────────────────────

func _mult_for(section_id: String, effects_key: String, mult_key: String) -> float:
	var sec := section(section_id)
	if sec.is_empty():
		return 1.0
	if not bool(sec.get("powered", true)):
		return 0.0
	var state := String(sec.get("state", "nominal"))
	if state == "nominal":
		return 1.0
	var cfg: Dictionary = (_content_dict("effects").get(effects_key, {}) as Dictionary)
	var key := "%s_%s" % [state, mult_key]
	return float(cfg.get(key, 1.0))

func effects() -> Dictionary:
	var power_sec := section("power")
	var power_frac := clampf(float(power_sec.get("integrity", 0.0)), 0.0, 1.0)
	var sensors := section("sensors")
	var comms := section("comms")
	var propulsion := section("propulsion")
	var docking := section("docking")
	var comms_cfg: Dictionary = (_content_dict("effects").get("comms", {}) as Dictionary)
	var comms_state := String(comms.get("state", "nominal"))
	var delay := 0.0
	if comms_state != "nominal":
		delay = float(comms_cfg.get("%s_delay_s" % comms_state, 0.0))
	if not bool(comms.get("powered", true)):
		delay = maxf(delay, float(comms_cfg.get("destroyed_delay_s", 60.0)))
	var fire_sections: Array = []
	var dec_sections: Array = []
	var unpowered: Array = []
	for raw in sections:
		var sec: Dictionary = raw
		var sid := String(sec.get("id", ""))
		if bool((sec.get("fire", {}) as Dictionary).get("active", false)):
			fire_sections.append(sid)
		if bool((sec.get("decompression", {}) as Dictionary).get("active", false)):
			dec_sections.append(sid)
		if not bool(sec.get("powered", true)):
			unpowered.append(sid)
	var dock_min := float((_content_dict("effects").get("docking", {}) as Dictionary).get("min_integrity", 0.5))
	var out := {
		"power": {
			"available": String(power_sec.get("state", "")) != "destroyed",
			"fraction": power_frac,
			"state": String(power_sec.get("state", "")),
		},
		"sensors": {
			"available": bool(sensors.get("powered", true)) and String(sensors.get("state", "")) != "destroyed",
			"mult": _mult_for("sensors", "sensors", "mult"),
			"state": String(sensors.get("state", "")),
			"systems": (sensors.get("systems", []) as Array).duplicate(),
		},
		"comms": {
			"available": bool(comms.get("powered", true)) and String(comms.get("state", "")) != "destroyed",
			"command_delay_s": delay,
			"state": comms_state,
		},
		"propulsion": {
			"available": bool(propulsion.get("powered", true)) and String(propulsion.get("state", "")) != "destroyed",
			"dv_mult": _mult_for("propulsion", "propulsion", "dv"),
			"turn_mult": _mult_for("propulsion", "propulsion", "turn"),
			"state": String(propulsion.get("state", "")),
		},
		"docking": {
			"available": bool(docking.get("powered", true))
				and String(docking.get("state", "")) != "destroyed"
				and float(docking.get("integrity", 0.0)) >= dock_min
				and not bool((docking.get("decompression", {}) as Dictionary).get("active", false)),
			"min_integrity": dock_min,
			"integrity": float(docking.get("integrity", 0.0)),
		},
		"fire": {"count": fire_sections.size(), "sections": fire_sections},
		"decompression": {"count": dec_sections.size(), "sections": dec_sections},
		"unpowered_sections": unpowered,
	}
	return out

func summary() -> Dictionary:
	var counts := {"nominal": 0, "degraded": 0, "damaged": 0, "critical": 0, "destroyed": 0}
	var total := 0
	var sum_integrity := 0.0
	var on_fire := 0
	var decompressed := 0
	var unpowered := 0
	var repairing := 0
	var queued := 0
	for raw in sections:
		var sec: Dictionary = raw
		total += 1
		sum_integrity += float(sec.get("integrity", 0.0))
		var st := String(sec.get("state", "nominal"))
		counts[st] = int(counts.get(st, 0)) + 1
		if bool((sec.get("fire", {}) as Dictionary).get("active", false)):
			on_fire += 1
		if bool((sec.get("decompression", {}) as Dictionary).get("active", false)):
			decompressed += 1
		if not bool(sec.get("powered", true)):
			unpowered += 1
	for raw in queue:
		var status := String((raw as Dictionary).get("status", ""))
		if status == "active":
			repairing += 1
		elif status == "queued":
			queued += 1
	var damaged_total := int(counts.get("damaged", 0)) + int(counts.get("critical", 0)) \
		+ int(counts.get("destroyed", 0))
	return {
		"total": total,
		"integrity_avg": sum_integrity / float(maxi(1, total)),
		"nominal": int(counts.get("nominal", 0)),
		"degraded": int(counts.get("degraded", 0)),
		"damaged": int(counts.get("damaged", 0)),
		"critical": int(counts.get("critical", 0)),
		"destroyed": int(counts.get("destroyed", 0)),
		"on_fire": on_fire,
		"decompressed": decompressed,
		"unpowered": unpowered,
		"repairing": repairing,
		"queued": queued,
		"needs_attention": damaged_total + on_fire + decompressed + unpowered,
	}

func _recompute_effects() -> void:
	last_effects = effects()

## 只读 view-model（HUD 损管页/桥接层直接读；JSON 可序列化，无武器字段）。
func vm_damage() -> Dictionary:
	var sec_out: Array = []
	for raw in sections:
		var sec: Dictionary = raw
		var fire: Dictionary = sec.get("fire", {})
		var dec: Dictionary = sec.get("decompression", {})
		sec_out.append({
			"id": String(sec.get("id", "")),
			"label": String(sec.get("label", "")),
			"kind": String(sec.get("kind", "")),
			"integrity": float(sec.get("integrity", 0.0)),
			"integrity_pct": roundf(float(sec.get("integrity", 0.0)) * 1000.0) / 10.0,
			"state": String(sec.get("state", "")),
			"fire": {
				"active": bool(fire.get("active", false)),
				"intensity": float(fire.get("intensity", 0.0)),
			},
			"decompression": {
				"active": bool(dec.get("active", false)),
				"intensity": float(dec.get("intensity", 0.0)),
			},
			"powered": bool(sec.get("powered", true)),
			"power_loss": bool(sec.get("power_loss", false)),
			"requires_power": bool(sec.get("requires_power", false)),
			"systems": (sec.get("systems", []) as Array).duplicate(),
			"repair": (sec.get("repair", {}) as Dictionary).duplicate(true),
		})
	var ev_slice: Array = []
	var start := maxi(0, events.size() - VM_EVENT_LIMIT)
	for i in range(start, events.size()):
		ev_slice.append((events[i] as Dictionary).duplicate(true))
	var jobs: Array = []
	for raw in queue:
		var job: Dictionary = raw
		jobs.append({
			"section": String(job.get("section", "")),
			"priority": int(job.get("priority", 2)),
			"status": String(job.get("status", "")),
			"progress_s": roundf(float(job.get("progress_s", 0.0)) * 10.0) / 10.0,
			"required_s": float(job.get("required_s", 0.0)),
			"remaining_s": roundf(float(job.get("remaining_s", 0.0)) * 10.0) / 10.0,
			"progress_pct": roundf(clampf(float(job.get("progress_s", 0.0))
				/ maxf(1.0, float(job.get("required_s", 1.0))), 0.0, 1.0) * 1000.0) / 10.0,
			"reason": String(job.get("reason", "")),
			"team": int(job.get("team", 0)),
		})
	return {
		"schema": String(content.get("schema", "damage.v1")),
		"model": "V2DamageModel",
		"content_id": String(content.get("id", "")),
		"entity_id": entity_id,
		"name": name,
		"class": ship_class,
		"t": t,
		"units": {"integrity": "0..1", "time": "s", "energy": "0..1"},
		"sections": sec_out,
		"events": ev_slice,
		"queue": jobs,
		"resources": resources.duplicate(true),
		"summary": summary(),
		"effects": last_effects.duplicate(true),
		"note": "只读 view-model；伤害输入由 apply_hit 提供（模型不生成武器/命中）。",
	}

## 是否还能行动（所有关键系统未毁坏；供上层过滤用）。
func is_operational() -> bool:
	for raw in sections:
		var sec: Dictionary = raw
		if String(sec.get("id", "")) in ["hull", "power"] \
				and String(sec.get("state", "")) == "destroyed":
			return false
	return true
