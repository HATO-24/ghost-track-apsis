class_name V2CombatService
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 完整游戏-阶段3G · 战斗系统核心（内容驱动；不写 world/UI）
#
# 职责：
#   * 武器数据：轨道炮/导弹/点防御/干扰/诱饵（射程/弹药/冷却/解算/
#     制导/伤害/授权需求），来自 framework/content/weapons_l1.json；
#   * ROE 四档 WPN DEFEND/HOLD/TIGHT/FREE + TRACK/SOLUTION/FIRE 三级授权；
#     授权范围 target/weapon_group/ship/fleet；持续 N 秒/直到摧毁；
#     未知/中立仍需确认；自动降级；
#   * 火控：track → solution（时间/误差/可解算）→ FIRE 授权→ launch →
#     命中/损伤事件；不执行物理、不直接改实体；
#   * 点防御/拦截、诱饵、干扰、弹药/冷却；
#   * VM/events/JSON/save/load；确定性。
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_CONTENT := "res://framework/content/weapons_l1.json"
const SCHEMA_VM := "combat_service.v1"
const SCHEMA_EVENT := "combat_event.v1"
const SCHEMA_DAMAGE := "combat_damage_event.v1"
const SAVE_SCHEMA := "v17.combat_service_save.v1"
const SAVE_VERSION := "1.0.0"
const WEAPON_KINDS := ["kinetic", "guided", "point_defense", "ew", "decoy"]
const ROE_ORDER := ["DEFEND", "HOLD", "TIGHT", "FREE"]
const AUTH_LEVELS := ["TRACK", "SOLUTION", "FIRE"]
const SCOPE_TYPES := ["target", "weapon_group", "ship", "fleet"]
const IDENTITIES := ["unknown", "assumed_friend", "friend", "neutral", "suspect", "hostile"]
const MAX_EVENTS := 500
const MAX_INCOMING := 32

var ready := false
var t := 0.0
var dt_last := 0.0
var step_count := 0
var content: Dictionary = {}
var content_path := DEFAULT_CONTENT
var weapons_def: Dictionary = {}
var roe := "TIGHT"
var roe_defs: Dictionary = {}
var own_id := "own"
var fleet_id := "fleet"
var tracks: Dictionary = {}
var solutions: Dictionary = {}
var grants: Dictionary = {}
var incoming: Array = []
var weapons: Dictionary = {}
var events: Array = []
var errors: Array = []
var warnings: Array = []
var sensor_damage := 0.0
var link_lost := false
var decoy_until := -1.0
var jammer_until := -1.0
var config: Dictionary = {}

var _event_seq := 0
var _solution_seq := 0
var _grant_seq := 0
var _shot_seq := 0
var _incoming_seq := 0
var _outbox: Array = []


func _init(cfg := {}) -> void:
	setup(cfg)


# ── content / setup ────────────────────────────────────────────

func setup(cfg := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	events = []
	_outbox = []
	t = 0.0
	dt_last = 0.0
	step_count = 0
	_event_seq = 0
	_solution_seq = 0
	_grant_seq = 0
	_shot_seq = 0
	_incoming_seq = 0
	tracks = {}
	solutions = {}
	grants = {}
	incoming = []
	weapons = {}
	weapons_def = {}
	roe_defs = {}
	sensor_damage = 0.0
	link_lost = false
	decoy_until = -1.0
	jammer_until = -1.0
	config = (cfg as Dictionary).duplicate(true) if cfg is Dictionary else {}
	content_path = String(config.get("content_path", DEFAULT_CONTENT))
	content = {}
	if config.get("content") is Dictionary and not (config.get("content") as Dictionary).is_empty():
		content = (config.get("content") as Dictionary).duplicate(true)
	else:
		if not FileAccess.file_exists(content_path):
			errors.append("weapons content 不存在: " + content_path)
			return false
		var f := FileAccess.open(content_path, FileAccess.READ)
		if f == null:
			errors.append("weapons content 不可读: " + content_path)
			return false
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if not (parsed is Dictionary):
			errors.append("weapons content JSON 无效: " + content_path)
			return false
		content = parsed
	var vr := validate_content(content)
	if not bool(vr.get("ok", false)):
		for e in (vr.get("errors", []) as Array):
			errors.append("weapons content: " + String(e))
		return false
	own_id = String(config.get("own_id", "own"))
	fleet_id = String(config.get("fleet_id", "fleet"))
	roe = String(config.get("roe", "TIGHT")).to_upper()
	if not (roe in ROE_ORDER):
		errors.append("ROE 非法: " + roe)
		return false
	for raw in (content.get("weapons", []) as Array):
		var d: Dictionary = raw
		var wid := String(d.get("id", ""))
		weapons_def[wid] = d.duplicate(true)
		weapons[wid] = {
			"id": wid, "label": String(d.get("label", wid)),
			"kind": String(d.get("kind", "")), "range_km": float(d.get("range_km", 0.0)),
			"min_range_km": float(d.get("min_range_km", 0.0)),
			"ammo": int(d.get("ammo", 0)), "ammo_max": int(d.get("ammo", 0)),
			"cooldown_s": float(d.get("cooldown_s", 0.0)),
			"cooldown_until": -1.0, "solution_s": float(d.get("solution_s", 0.0)),
			"auth_level": String(d.get("auth_level", "FIRE")),
			"intercept_accuracy": float(d.get("intercept_accuracy", d.get("accuracy", 0.0))),
		}
	# ROE content（可覆盖默认矩阵）
	var roe_cfg: Dictionary = content.get("roe", {}) if content.get("roe") is Dictionary else {}
	for raw in (roe_cfg.get("levels", []) as Array):
		if raw is Dictionary:
			var r: Dictionary = raw
			roe_defs[String(r.get("id", ""))] = r.duplicate(true)
	if roe_defs.is_empty():
		errors.append("weapons content 缺 roe.levels")
		return false
	for lv in ROE_ORDER:
		if not roe_defs.has(lv):
			errors.append("weapons content 缺 ROE level: " + lv)
	if not errors.is_empty():
		return false
	ready = true
	_push_event("combat_ready", {"weapons": weapons.size(), "roe": roe})
	return true


func validate_content(data: Variant) -> Dictionary:
	var errs: Array = []
	if not (data is Dictionary):
		return {"ok": false, "errors": ["content 必须是对象"]}
	var d: Dictionary = data
	if String(d.get("schema", "")) != "weapons.v1":
		errs.append("schema 必须 weapons.v1")
	var arr = d.get("weapons", null)
	if not (arr is Array) or (arr as Array).is_empty():
		errs.append("weapons 必须为非空数组")
		return {"ok": errs.is_empty(), "errors": errs}
	var ids: Dictionary = {}
	for i in range((arr as Array).size()):
		var raw = (arr as Array)[i]
		if not (raw is Dictionary):
			errs.append("weapons[%d] 必须对象" % i)
			continue
		var w: Dictionary = raw
		var id := String(w.get("id", ""))
		if id == "":
			errs.append("weapons[%d] 缺 id" % i)
		elif ids.has(id):
			errs.append("weapons 重复 id: " + id)
		else:
			ids[id] = true
		var kind := String(w.get("kind", ""))
		if not (kind in WEAPON_KINDS):
			errs.append("weapon %s kind 非法: %s" % [id, kind])
		for k in ["range_km", "ammo", "cooldown_s", "solution_s", "accuracy", "damage", "penetration"]:
			if not w.has(k):
				errs.append("weapon %s 缺 %s" % [id, k])
			elif not is_finite(float(w.get(k, NAN))):
				errs.append("weapon %s.%s 非有限" % [id, k])
		if w.has("ammo") and int(w.get("ammo", 0)) < 0:
			errs.append("weapon %s ammo 必须 >=0" % id)
		if w.has("cooldown_s") and float(w.get("cooldown_s", 0.0)) < 0.0:
			errs.append("weapon %s cooldown 非法" % id)
		if kind in ["kinetic", "guided"] and float(w.get("damage", 0.0)) <= 0.0:
			errs.append("weapon %s damage 必须 >0" % id)
		var auth := String(w.get("auth_level", "FIRE"))
		if not (auth in AUTH_LEVELS):
			errs.append("weapon %s auth_level 非法" % id)
	var roe = d.get("roe", null)
	if not (roe is Dictionary):
		errs.append("缺 roe")
	else:
		for lv in ROE_ORDER:
			var found := false
			for raw2 in ((roe as Dictionary).get("levels", []) as Array):
				if raw2 is Dictionary and String((raw2 as Dictionary).get("id", "")) == lv:
					found = true
			if not found:
				errs.append("roe 缺 " + lv)
	return {"ok": errs.is_empty(), "errors": errs}


# ── ROE / 三级授权 ─────────────────────────────────────────────

func set_roe(level: String) -> Dictionary:
	var lv := level.to_upper()
	if not (lv in ROE_ORDER):
		return {"ok": false, "reason": "invalid_roe", "roe": roe}
	if lv == roe:
		return {"ok": true, "reason": "", "roe": roe, "changed": false}
	var old := roe
	roe = lv
	_push_event("roe_changed", {"from": old, "to": roe})
	return {"ok": true, "reason": "", "roe": roe, "from": old, "changed": true}


func roe_label() -> String:
	return String((roe_defs.get(roe, {}) as Dictionary).get("label", roe))


func roe_label_en() -> String:
	return String((roe_defs.get(roe, {}) as Dictionary).get("label_en", roe))


func _track_threat(track: Dictionary) -> String:
	var th := String(track.get("threat", ""))
	if th != "":
		return th
	var identity := String(track.get("identity", "unknown"))
	if identity == "hostile":
		return "hostile"
	if identity == "suspect":
		return "suspect"
	if identity in ["friend", "assumed_friend", "neutral"]:
		return "none"
	return "unknown"


func _is_hostile(track: Dictionary) -> bool:
	return _track_threat(track) == "hostile"


func _is_suspect(track: Dictionary) -> bool:
	return _track_threat(track) in ["suspect", "hostile"]


func _is_direct_threat(track: Dictionary) -> bool:
	return bool(track.get("in_arc", false)) and _is_hostile(track) and float(track.get("range_km", 999999.0)) <= 2000.0


func _roe_auto(level: String, track: Dictionary) -> bool:
	var r: Dictionary = roe_defs.get(roe, {}) if roe_defs.get(roe) is Dictionary else {}
	var mode := String(r.get(level.to_lower(), ""))
	if level == "TRACK":
		if mode in ["auto_passive", "auto_suspect"]:
			return true if mode == "auto_passive" else _is_suspect(track)
		if mode == "auto_hostile":
			return _is_hostile(track)
		return false
	if level == "SOLUTION":
		if mode == "auto_direct_threat":
			return _is_direct_threat(track)
		if mode == "auto_hostile":
			return _is_hostile(track)
		return false
	if level == "FIRE":
		return false  # FIRE 永远需要人工确认
	return false


func _roe_needs_confirm(level: String, track: Dictionary) -> bool:
	if level == "FIRE":
		return true
	if _roe_auto(level, track):
		return false
	var identity := String(track.get("identity", "unknown"))
	return identity in ["unknown", "neutral"] or level == "SOLUTION"


func _check_grant(level: String, target_id: String, weapon_id := "") -> Dictionary:
	for gid in grants.keys():
		var g: Dictionary = grants[gid]
		if String(g.get("level", "")) != level:
			continue
		if g.get("until_destroyed", false):
			var tr: Variant = tracks.get(target_id, {})
			if tr is Dictionary and bool((tr as Dictionary).get("destroyed", false)):
				continue
		if float(g.get("expires_t", -1.0)) >= 0.0 and t + 1.0e-9 >= float(g.get("expires_t", 0.0)):
			continue
		var st := String(g.get("scope_type", ""))
		var sid := String(g.get("scope_id", ""))
		if st == "target" and (sid == target_id or sid == "*"):
			return g
		if st == "weapon_group" and (sid == weapon_id or sid == "*"):
			return g
		if st == "ship" and (sid == own_id or sid == "*"):
			return g
		if st == "fleet" and (sid == fleet_id or sid == "*"):
			return g
	return {}


func _action_allowed(level: String, track: Dictionary, weapon_id: String, confirmed: bool) -> Dictionary:
	var g := _check_grant(level, String(track.get("id", "")), weapon_id)
	if level == "FIRE":
		if not bool(confirmed):
			return {"ok": false, "reason": "needs_confirmation", "needs_confirmation": true}
		if g.is_empty():
			return {"ok": false, "reason": "needs_authorization", "needs_authorization": true}
		return {"ok": true, "reason": "", "confirmed": true, "grant": g}
	if _roe_auto(level, track):
		return {"ok": true, "reason": "roe_auto", "auto": true, "confirmed": bool(confirmed)}
	if g.is_empty():
		if _roe_needs_confirm(level, track) and not bool(confirmed):
			return {"ok": false, "reason": "needs_confirmation", "needs_confirmation": true}
		if not bool(confirmed):
			return {"ok": false, "reason": "needs_authorization", "needs_authorization": true}
	return {"ok": true, "reason": "grant_or_confirm", "grant": g, "confirmed": bool(confirmed)}


func grant_authorization(level: String, scope_type := "target", scope_id := "",
		duration_s := 0.0, until_destroyed := false) -> Dictionary:
	var lv := level.to_upper()
	if not (lv in AUTH_LEVELS):
		return {"ok": false, "reason": "invalid_level"}
	if not (scope_type in SCOPE_TYPES):
		return {"ok": false, "reason": "invalid_scope"}
	if scope_id == "":
		return {"ok": false, "reason": "empty_scope_id"}
	_grant_seq += 1
	var gid := "GR-%06d" % _grant_seq
	var g := {"grant_id": gid, "level": lv, "scope_type": scope_type,
		"scope_id": scope_id, "granted_t": t,
		"duration_s": maxf(0.0, float(duration_s)),
		"until_destroyed": bool(until_destroyed),
		"expires_t": t + maxf(0.0, float(duration_s)) if float(duration_s) > 0.0 else -1.0}
	grants[gid] = g
	_push_event("authorization_granted", g)
	return {"ok": true, "reason": "", "grant": g.duplicate(true)}


func revoke_authorization(grant_id := "") -> Dictionary:
	if grant_id == "":
		var n := grants.size()
		grants.clear()
		_push_event("authorization_revoked", {"all": true, "count": n})
		return {"ok": true, "revoked": n}
	if not grants.has(grant_id):
		return {"ok": false, "reason": "unknown_grant"}
	grants.erase(grant_id)
	_push_event("authorization_revoked", {"grant_id": grant_id})
	return {"ok": true, "revoked": 1, "grant_id": grant_id}


func check_authorization(level: String, target_id := "", weapon_id := "") -> Dictionary:
	return _check_grant(level.to_upper(), target_id, weapon_id)


# ── tracks / targets ───────────────────────────────────────────

func register_track(id: String, data := {}) -> Dictionary:
	if id == "":
		return {"ok": false, "reason": "empty_track_id"}
	if tracks.has(id):
		return update_track(id, data)
	var d: Dictionary = data if data is Dictionary else {}
	tracks[id] = {
		"id": id, "batch": String(d.get("batch", id)),
		"identity": String(d.get("identity", "unknown")),
		"threat": String(d.get("threat", "unknown")),
		"range_km": float(d.get("range_km", 999999.0)),
		"in_arc": bool(d.get("in_arc", false)),
		"destroyed": bool(d.get("destroyed", false)),
		"damage_taken": float(d.get("damage_taken", 0.0)),
		"ship_id": String(d.get("ship_id", "")),
	}
	_push_event("track_registered", {"track_id": id})
	return {"ok": true, "reason": "", "track": (tracks[id] as Dictionary).duplicate(true)}


func update_track(id: String, data := {}) -> Dictionary:
	if not tracks.has(id):
		return {"ok": false, "reason": "unknown_track", "track_id": id}
	var tr: Dictionary = tracks[id]
	var d: Dictionary = data if data is Dictionary else {}
	var old_identity := String(tr.get("identity", "unknown"))
	for k in ["batch", "identity", "threat", "range_km", "in_arc", "destroyed", "damage_taken", "ship_id"]:
		if d.has(k):
			tr[k] = d[k]
	var new_identity := String(tr.get("identity", "unknown"))
	if tr.get("destroyed", false):
		_push_event("target_destroyed", {"track_id": id})
		_invalidate_until_destroyed(id)
	if new_identity != old_identity and new_identity in ["friend", "assumed_friend", "neutral"] \
			and bool(tr.get("in_arc", false)):
		_maybe_downgrade("friend_neutral_in_arc")
	return {"ok": true, "reason": "", "track": tr.duplicate(true)}


func track(id: String) -> Dictionary:
	return (tracks.get(id, {}) as Dictionary).duplicate(true) if tracks.get(id) is Dictionary else {}


func _get_track(id: String) -> Dictionary:
	if tracks.has(id):
		return tracks[id]
	# 允许 target_id 作为 batch 查询
	for k in tracks.keys():
		if String((tracks[k] as Dictionary).get("batch", "")) == id:
			return tracks[k]
	return {}


# ── 火控解算 ───────────────────────────────────────────────────

func request_track(target_id: String, confirmed := false) -> Dictionary:
	var tr := _get_track(target_id)
	if tr.is_empty():
		return {"ok": false, "reason": "unknown_track", "target_id": target_id}
	var a := _action_allowed("TRACK", tr, "", confirmed)
	if not bool(a.get("ok", false)):
		return {"ok": false, "reason": String(a.get("reason", "")),
			"target_id": target_id, "needs_confirmation": bool(a.get("needs_confirmation", false)),
			"needs_authorization": bool(a.get("needs_authorization", false)),
			"roe": roe}
	_push_event("track_authorized", {"target_id": target_id, "auto": bool(a.get("auto", false))})
	return {"ok": true, "reason": String(a.get("reason", "")), "target_id": target_id,
		"auto": bool(a.get("auto", false)), "roe": roe}


func request_solution(target_id: String, weapon_id: String, confirmed := false) -> Dictionary:
	var tr := _get_track(target_id)
	if tr.is_empty():
		return {"ok": false, "reason": "unknown_track"}
	var w: Dictionary = weapons_def.get(weapon_id, {}) if weapons_def.get(weapon_id) is Dictionary else {}
	if w.is_empty():
		return {"ok": false, "reason": "unknown_weapon"}
	var kind := String(w.get("kind", ""))
	if not (kind in ["kinetic", "guided"]):
		return {"ok": false, "reason": "weapon_not_offensive"}
	var range_km := float(tr.get("range_km", 999999.0))
	if range_km > float(w.get("range_km", 0.0)) + 1.0e-9:
		return {"ok": false, "reason": "out_of_range", "range_km": range_km}
	if range_km < float(w.get("min_range_km", 0.0)) - 1.0e-9:
		return {"ok": false, "reason": "inside_min_range"}
	if bool(tr.get("destroyed", false)):
		return {"ok": false, "reason": "target_destroyed"}
	var a := _action_allowed("SOLUTION", tr, weapon_id, confirmed)
	if not bool(a.get("ok", false)):
		return {"ok": false, "reason": String(a.get("reason", "")),
			"target_id": target_id, "weapon_id": weapon_id,
			"needs_confirmation": bool(a.get("needs_confirmation", false)),
			"needs_authorization": bool(a.get("needs_authorization", false)),
			"roe": roe}
	# 同 target/weapon 未结束的 solution 直接返回
	for sid in solutions.keys():
		var s: Dictionary = solutions[sid]
		if String(s.get("target_id", "")) == target_id and String(s.get("weapon_id", "")) == weapon_id \
				and String(s.get("status", "")) in ["COMPUTING", "READY"]:
			return {"ok": true, "reason": "existing", "solution": s.duplicate(true)}
	_solution_seq += 1
	var so := {
		"solution_id": "SOL-%06d" % _solution_seq,
		"target_id": target_id, "weapon_id": weapon_id,
		"status": "COMPUTING", "start_t": t,
		"ready_t": t + maxf(0.0, float(w.get("solution_s", 0.0))),
		"quality": 0.0, "error_km": -1.0, "reason": "",
		"fire_ready": false,
	}
	solutions[so["solution_id"]] = so
	_push_event("solution_started", {"solution_id": so["solution_id"],
		"target_id": target_id, "weapon_id": weapon_id})
	return {"ok": true, "reason": "", "solution": so.duplicate(true)}


func solution_status(solution_id: String) -> Dictionary:
	return (solutions.get(solution_id, {}) as Dictionary).duplicate(true) if solutions.get(solution_id) is Dictionary else {}


func _find_ready_solution(target_id: String, weapon_id: String) -> Dictionary:
	for sid in solutions.keys():
		var s: Dictionary = solutions[sid]
		if String(s.get("target_id", "")) == target_id and String(s.get("weapon_id", "")) == weapon_id \
				and String(s.get("status", "")) == "READY":
			return s
	return {}


# ── fire / launch / damage ─────────────────────────────────────

## 预测/命中判定接口：只给几何/概率/飞行时间，不执行物理，不返回世界状态。
func predict_shot(target_id: String, weapon_id: String) -> Dictionary:
	var tr := _get_track(target_id)
	if tr.is_empty():
		return {"ok": false, "reason": "unknown_track"}
	var w: Dictionary = weapons_def.get(weapon_id, {}) if weapons_def.get(weapon_id) is Dictionary else {}
	if w.is_empty():
		return {"ok": false, "reason": "unknown_weapon"}
	if not (String(w.get("kind", "")) in ["kinetic", "guided"]):
		return {"ok": false, "reason": "weapon_not_offensive"}
	var range_km := float(tr.get("range_km", 999999.0))
	if range_km > float(w.get("range_km", 0.0)) + 1.0e-9:
		return {"ok": false, "reason": "out_of_range"}
	var speed := float(w.get("speed_kmps", 0.0))
	var tof := range_km / speed if speed > 0.0 else -1.0
	var acc := float(w.get("accuracy", 0.5))
	var q := clampf(acc * (1.0 - clampf(range_km / maxf(1.0, float(w.get("range_km", 1.0))), 0.0, 1.0) * 0.25), 0.0, 1.0)
	return {"ok": true, "reason": "", "schema": "combat_prediction.v1",
		"no_physics": true, "trajectory": "interface_only",
		"target_id": target_id, "weapon_id": weapon_id, "range_km": range_km,
		"time_of_flight_s": tof, "hit_probability": q,
		"error_km": maxf(0.0, range_km * (1.0 - q) * 0.01),
		"guidance": String(w.get("guidance", "")),
		"interceptable": bool(w.get("interceptable", false))}


func request_fire(target_id: String, weapon_id: String, confirmed := false) -> Dictionary:
	var tr := _get_track(target_id)
	if tr.is_empty():
		return {"ok": false, "reason": "unknown_track"}
	var w: Dictionary = weapons_def.get(weapon_id, {}) if weapons_def.get(weapon_id) is Dictionary else {}
	if w.is_empty():
		return {"ok": false, "reason": "unknown_weapon"}
	if not (String(w.get("kind", "")) in ["kinetic", "guided"]):
		return {"ok": false, "reason": "weapon_not_offensive"}
	if not bool(confirmed):
		return {"ok": false, "reason": "needs_confirmation", "needs_confirmation": true}
	var a := _action_allowed("FIRE", tr, weapon_id, true)
	if not bool(a.get("ok", false)):
		return {"ok": false, "reason": String(a.get("reason", "")),
			"needs_authorization": bool(a.get("needs_authorization", false)),
			"target_id": target_id, "weapon_id": weapon_id}
	var sol := _find_ready_solution(target_id, weapon_id)
	if sol.is_empty():
		return {"ok": false, "reason": "no_ready_solution"}
	var range_km := float(tr.get("range_km", 999999.0))
	if range_km > float(w.get("range_km", 0.0)) + 1.0e-9:
		return {"ok": false, "reason": "out_of_range"}
	var ws: Dictionary = weapons[weapon_id]
	if int(ws.get("ammo", 0)) <= 0:
		return {"ok": false, "reason": "no_ammo"}
	if t + 1.0e-9 < float(ws.get("cooldown_until", -1.0)):
		return {"ok": false, "reason": "cooldown", "cooldown_remaining_s":
			float(ws.get("cooldown_until", 0.0)) - t}
	# FIRE 授权 + 确认通过；消耗弹药/冷却
	ws["ammo"] = int(ws.get("ammo", 0)) - int(w.get("salvo", 1))
	ws["cooldown_until"] = t + float(w.get("cooldown_s", 0.0))
	_shot_seq += 1
	var shot_id := "SHOT-%06d" % _shot_seq
	sol["status"] = "FIRED"
	sol["fired_t"] = t
	var pred: Dictionary = predict_shot(target_id, weapon_id)
	_push_event("weapon_launch", {"shot_id": shot_id, "target_id": target_id,
		"weapon_id": weapon_id, "solution_id": String(sol.get("solution_id", "")),
		"prediction": pred.duplicate(true)})
	var hit_prob := clampf(float(sol.get("quality", 0.0)) * float(w.get("accuracy", 0.0)), 0.0, 1.0)
	if decoy_until > t and _is_hostile(tr):
		hit_prob *= 0.5  # 目标诱饵降低命中
	var roll := _roll("%s|%s|%d" % [target_id, weapon_id, _shot_seq])
	var hit := roll < hit_prob
	if not hit:
		_push_event("combat_miss", {"shot_id": shot_id, "target_id": target_id,
			"weapon_id": weapon_id, "roll": roll, "hit_prob": hit_prob})
		return {"ok": true, "reason": "miss", "shot_id": shot_id, "hit": false,
			"hit_prob": hit_prob, "roll": roll, "solution": sol.duplicate(true),
			"prediction": pred}
	# 命中只产生 damage event，不直接改实体
	var damage := float(w.get("damage", 0.0))
	var section := ""
	var secs: Array = w.get("suggested_sections", []) if w.get("suggested_sections") is Array else []
	if not secs.is_empty():
		section = String(secs[0])
	var dmg_ev := {
		"schema": SCHEMA_DAMAGE, "kind": "damage",
		"t": t, "shot_id": shot_id, "target_id": target_id,
		"source_id": own_id, "weapon_id": weapon_id,
		"damage": damage, "penetration": float(w.get("penetration", 0.0)),
		"damage_kind": String(w.get("damage_kind", "kinetic")),
		"suggested_section": section,
		"source": "combat_service", "applied": false, "writes_v15": false,
	}
	tr["damage_taken"] = float(tr.get("damage_taken", 0.0)) + damage
	if float(tr.get("damage_taken", 0.0)) >= 1.0 - 1.0e-9 and not bool(tr.get("destroyed", false)):
		tr["destroyed"] = true
		_invalidate_until_destroyed(target_id)
		_push_event("target_destroyed", {"target_id": target_id})
	_push_event("combat_hit", {"shot_id": shot_id, "target_id": target_id,
		"weapon_id": weapon_id, "damage_event": dmg_ev.duplicate(true),
		"roll": roll, "hit_prob": hit_prob})
	return {"ok": true, "reason": "", "shot_id": shot_id, "hit": true,
		"hit_prob": hit_prob, "roll": roll, "damage_event": dmg_ev.duplicate(true),
		"prediction": pred, "solution": sol.duplicate(true)}


# ── 点防御 / 诱饵 / 干扰 ───────────────────────────────────────

func incoming_missile(threat_id: String, target_id: String, damage := 0.5, opts := {}) -> Dictionary:
	_incoming_seq += 1
	var o: Dictionary = opts if opts is Dictionary else {}
	var rec := {"incoming_id": "INC-%06d" % _incoming_seq,
		"threat_id": threat_id, "target_id": target_id,
		"damage": maxf(0.0, float(damage)), "eta_s": maxf(0.0, float(o.get("eta_s", 1.0))),
		"interceptable": bool(o.get("interceptable", true)),
		"created_t": t, "status": "INCOMING"}
	incoming.append(rec)
	while incoming.size() > MAX_INCOMING:
		incoming.pop_front()
	_push_event("incoming_detected", {"incoming_id": rec["incoming_id"],
		"target_id": target_id, "threat_id": threat_id})
	return {"ok": true, "incoming": rec.duplicate(true)}


func _process_incoming() -> void:
	var keep: Array = []
	for raw in incoming:
		if not (raw is Dictionary):
			continue
		var inc: Dictionary = raw
		if t + 1.0e-9 < float(inc.get("created_t", 0.0)) + float(inc.get("eta_s", 0.0)):
			keep.append(inc)
			continue
		_resolve_incoming(inc)
	incoming = keep


func _resolve_incoming(inc: Dictionary) -> void:
	var target_id := String(inc.get("target_id", ""))
	var tr := _get_track(target_id)
	var pd = _weapon("pd")
	if bool(inc.get("interceptable", true)) and not pd.is_empty():
		var ws: Dictionary = weapons.get(String(pd.get("id", "")), {})
		if int(ws.get("ammo", 0)) > 0 and t + 1.0e-9 >= float(ws.get("cooldown_until", -1.0)):
			ws["ammo"] = int(ws.get("ammo", 0)) - 1
			ws["cooldown_until"] = t + float(pd.get("cooldown_s", 0.0))
			var chance := clampf(float(pd.get("intercept_accuracy", 0.0)), 0.0, 1.0)
			if decoy_until > t:
				chance = minf(1.0, chance + 0.2)
			if jammer_until > t:
				chance = maxf(0.0, chance - 0.15)
			var roll := _roll("PD|%s|%s" % [inc.get("incoming_id", ""), str(_event_seq)])
			var intercepted := roll < chance
			_push_event("point_defense", {"incoming_id": inc.get("incoming_id", ""),
				"intercepted": intercepted, "chance": chance, "roll": roll})
			if intercepted:
				_push_event("combat_intercept", {"incoming_id": inc.get("incoming_id", ""),
					"target_id": target_id})
				return
	var dmg := float(inc.get("damage", 0.0))
	var dmg_ev := {"schema": SCHEMA_DAMAGE, "kind": "damage", "t": t,
		"shot_id": String(inc.get("incoming_id", "")), "target_id": target_id,
		"source_id": String(inc.get("threat_id", "")), "weapon_id": "incoming",
		"damage": dmg, "penetration": 0.5, "damage_kind": "explosive",
		"suggested_section": "hull", "source": "combat_service/incoming",
		"applied": false, "writes_v15": false}
	if not tr.is_empty() and not bool(tr.get("destroyed", false)):
		tr["damage_taken"] = float(tr.get("damage_taken", 0.0)) + dmg
		if float(tr.get("damage_taken", 0.0)) >= 1.0 - 1.0e-9:
			tr["destroyed"] = true
			_push_event("target_destroyed", {"target_id": target_id})
	_push_event("incoming_impact", {"incoming_id": inc.get("incoming_id", ""),
		"target_id": target_id, "damage_event": dmg_ev.duplicate(true)})


func launch_decoy() -> Dictionary:
	var wd: Dictionary = weapons_def.get("decoy", {}) if weapons_def.get("decoy") is Dictionary else {}
	if wd.is_empty():
		return {"ok": false, "reason": "no_decoy"}
	var c := _consume("decoy", wd)
	if not bool(c.get("ok", false)):
		return c
	var dur := float(wd.get("duration_s", 20.0))
	decoy_until = t + dur
	_push_event("decoy_launched", {"until": decoy_until, "duration_s": dur})
	return {"ok": true, "reason": "", "active_until": decoy_until, "duration_s": dur}


func activate_jammer(target_id := "") -> Dictionary:
	var wd: Dictionary = weapons_def.get("jammer", {}) if weapons_def.get("jammer") is Dictionary else {}
	if wd.is_empty():
		return {"ok": false, "reason": "no_jammer"}
	var c := _consume("jammer", wd)
	if not bool(c.get("ok", false)):
		return c
	var dur := float(wd.get("duration_s", 30.0))
	jammer_until = t + dur
	_push_event("jammer_active", {"target_id": target_id, "until": jammer_until})
	return {"ok": true, "reason": "", "active_until": jammer_until, "duration_s": dur}


func _consume(weapon_id: String, wd: Dictionary) -> Dictionary:
	if not weapons.has(weapon_id):
		return {"ok": false, "reason": "unknown_weapon"}
	var ws: Dictionary = weapons[weapon_id]
	if int(ws.get("ammo", 0)) <= 0:
		return {"ok": false, "reason": "no_ammo", "weapon_id": weapon_id}
	if t + 1.0e-9 < float(ws.get("cooldown_until", -1.0)):
		return {"ok": false, "reason": "cooldown", "cooldown_remaining_s":
			float(ws.get("cooldown_until", 0.0)) - t}
	ws["ammo"] = int(ws.get("ammo", 0)) - 1
	ws["cooldown_until"] = t + float(wd.get("cooldown_s", 0.0))
	return {"ok": true, "reason": "", "weapon_id": weapon_id,
		"ammo": ws["ammo"], "cooldown_until": ws["cooldown_until"]}


# ── tick / downgrade ──────────────────────────────────────────

func tick(dt: float) -> Dictionary:
	var d := maxf(0.0, float(dt))
	t += d
	dt_last = d
	step_count += 1
	var start := _outbox.size()
	# 过期授权
	for gid in grants.keys().duplicate():
		var g: Dictionary = grants[gid]
		var exp := float(g.get("expires_t", -1.0))
		if exp >= 0.0 and t + 1.0e-9 >= exp:
			grants.erase(gid)
			_push_event("authorization_expired", {"grant_id": gid, "level": String(g.get("level", ""))})
	# 解算推进
	for sid in solutions.keys():
		var s: Dictionary = solutions[sid]
		if String(s.get("status", "")) != "COMPUTING":
			continue
		if t + 1.0e-9 < float(s.get("ready_t", 0.0)):
			continue
		var tr := _get_track(String(s.get("target_id", "")))
		var w: Dictionary = weapons_def.get(String(s.get("weapon_id", "")), {}) if weapons_def.get(String(s.get("weapon_id", ""))) is Dictionary else {}
		if tr.is_empty() or bool(tr.get("destroyed", false)):
			s["status"] = "FAILED"
			s["reason"] = "target_unavailable"
			_push_event("solution_failed", {"solution_id": sid, "reason": "target_unavailable"})
			continue
		if float(tr.get("range_km", 999999.0)) > float(w.get("range_km", 0.0)):
			s["status"] = "FAILED"
			s["reason"] = "out_of_range"
			_push_event("solution_failed", {"solution_id": sid, "reason": "out_of_range"})
			continue
		var acc := float(w.get("accuracy", 0.5))
		var q := clampf(acc * (1.0 - clampf(float(tr.get("range_km", 0.0)) / maxf(1.0, float(w.get("range_km", 1.0))), 0.0, 1.0) * 0.25), 0.0, 1.0)
		s["status"] = "READY"
		s["quality"] = q
		s["error_km"] = maxf(0.0, float(tr.get("range_km", 0.0)) * (1.0 - q) * 0.01)
		s["fire_ready"] = true
		_push_event("solution_ready", {"solution_id": sid, "quality": q,
			"error_km": float(s["error_km"])})
	# 跟进中的 incoming + 点防御
	_process_incoming()
	# 弹药/损坏/链路降级
	if _offensive_ammo_empty():
		_maybe_downgrade("ammo_empty")
	if sensor_damage >= 0.5:
		_maybe_downgrade("sensor_damage")
	if link_lost:
		_maybe_downgrade("link_lost")
	var new_events: Array = []
	for i in range(start, _outbox.size()):
		new_events.append((_outbox[i] as Dictionary).duplicate(true))
	return {"ok": true, "t": t, "dt": dt_last, "roe": roe,
		"events": new_events, "counts": _counts()}


func _offensive_ammo_empty() -> bool:
	for id in ["railgun", "missile"]:
		if weapons.has(id) and int((weapons[id] as Dictionary).get("ammo", 0)) > 0:
			return false
	return true


func _maybe_downgrade(reason: String) -> void:
	var idx := ROE_ORDER.find(roe)
	if idx <= 1:
		return
	var target_level := "TIGHT"
	if reason in ["friend_neutral_in_arc", "ammo_empty", "sensor_damage", "link_lost"]:
		target_level = "HOLD"
	var tidx := ROE_ORDER.find(target_level)
	if tidx < idx:
		var old := roe
		roe = target_level
		_push_event("roe_downgrade", {"from": old, "to": roe, "reason": reason})


func notify_downgrade(reason := "manual") -> Dictionary:
	var before := roe
	_maybe_downgrade(reason)
	return {"ok": true, "from": before, "to": roe, "downgraded": before != roe, "reason": reason}


func set_sensor_damage(value: float) -> Dictionary:
	sensor_damage = clampf(value, 0.0, 1.0)
	if sensor_damage >= 0.5:
		_maybe_downgrade("sensor_damage")
	return {"ok": true, "sensor_damage": sensor_damage, "roe": roe}


func set_link_lost(lost: bool) -> Dictionary:
	link_lost = bool(lost)
	if link_lost:
		_maybe_downgrade("link_lost")
	return {"ok": true, "link_lost": link_lost, "roe": roe}


# ── 查询 / VM ────────────────────────────────────────────────

func _weapon(id: String) -> Dictionary:
	return (weapon_def(id) as Dictionary)


func weapon_def(id: String) -> Dictionary:
	return (weapons_def.get(id, {}) as Dictionary).duplicate(true) if weapons_def.get(id) is Dictionary else {}


func weapons_status() -> Array:
	var out: Array = []
	for id in weapons.keys():
		var w: Dictionary = (weapons[id] as Dictionary).duplicate(true)
		w["cooldown_remaining_s"] = maxf(0.0, float(w.get("cooldown_until", -1.0)) - t)
		out.append(w)
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


func track_rows() -> Array:
	var out: Array = []
	for id in tracks.keys():
		out.append((tracks[id] as Dictionary).duplicate(true))
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


func grant_rows() -> Array:
	var out: Array = []
	for id in grants.keys():
		out.append((grants[id] as Dictionary).duplicate(true))
	return out


func solution_rows() -> Array:
	var out: Array = []
	for id in solutions.keys():
		out.append((solutions[id] as Dictionary).duplicate(true))
	return out


func _counts() -> Dictionary:
	var offensive_ammo := 0
	for id in ["railgun", "missile"]:
		offensive_ammo += int((weapons.get(id, {}) as Dictionary).get("ammo", 0))
	return {"tracks": tracks.size(), "solutions": solutions.size(),
		"grants": grants.size(), "incoming": incoming.size(),
		"weapons": weapons.size(), "events": events.size(),
		"offensive_ammo": offensive_ammo,
		"pd_ammo": int((weapons.get("pd", {}) as Dictionary).get("ammo", 0)),
		"decoy_active": decoy_until > t, "jammer_active": jammer_until > t}


func vm() -> Dictionary:
	return {
		"schema": SCHEMA_VM, "mode": "combat_core", "authoritative": false,
		"ready": ready, "t": t, "dt": dt_last, "step_count": step_count,
		"own_id": own_id, "fleet_id": fleet_id, "roe": roe, "roe_label": roe_label(),
		"roe_label_en": roe_label_en(),
		"weapons": weapons_status(), "tracks": track_rows(),
		"solutions": solution_rows(), "grants": grant_rows(),
		"incoming": incoming.duplicate(true),
		"decoy_until": decoy_until, "jammer_until": jammer_until,
		"events": events.duplicate(true), "counts": _counts(),
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"world": false, "track_table": false, "v15": false, "ui": false},
	}


func summary() -> Dictionary:
	return {"schema": SCHEMA_VM, "ready": ready, "t": t, "roe": roe,
		"weapons": weapons.size(), "tracks": tracks.size(),
		"solutions": solutions.size(), "grants": grants.size(),
		"incoming": incoming.size(), "events": events.size(),
		"writes": {"world": false, "track_table": false, "v15": false}}


func to_dict() -> Dictionary:
	return vm()


func to_json() -> String:
	return JSON.stringify(vm())


func events_since(seq := 0) -> Array:
	var out: Array = []
	for raw in events:
		if raw is Dictionary and int((raw as Dictionary).get("seq", 0)) > seq:
			out.append((raw as Dictionary).duplicate(true))
	return out


func take_events() -> Array:
	var out := _outbox.duplicate(true)
	_outbox = []
	return out


func _push_event(kind: String, payload := {}) -> Dictionary:
	_event_seq += 1
	var ev := {"schema": SCHEMA_EVENT, "seq": _event_seq, "t": t, "kind": kind,
		"payload": payload.duplicate(true) if payload is Dictionary else {},
		"shadow": true, "writes_v15": false}
	events.append(ev)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_outbox.append(ev.duplicate(true))
	return ev


func _roll(seed_text: String) -> float:
	var h := int(hash(seed_text))
	var v := (h & 0x7fffffff) % 1000000
	return float(v) / 1000000.0


func _invalidate_until_destroyed(target_id: String) -> void:
	for gid in grants.keys().duplicate():
		var g: Dictionary = grants[gid]
		if bool(g.get("until_destroyed", false)):
			grants.erase(gid)
			_push_event("authorization_expired", {"grant_id": gid, "reason": "target_destroyed"})


# ── save / load ──────────────────────────────────────────────

func save_state() -> String:
	var payload := {
		"schema": SAVE_SCHEMA, "version": SAVE_VERSION, "t": t, "roe": roe,
		"own_id": own_id, "fleet_id": fleet_id,
		"weapons": weapons.duplicate(true),
		"tracks": track_rows(), "solutions": solution_rows(),
		"grants": grant_rows(), "incoming": incoming.duplicate(true),
		"events": JSON.parse_string(JSON.stringify(events)),
		"event_seq": _event_seq, "solution_seq": _solution_seq,
		"grant_seq": _grant_seq, "shot_seq": _shot_seq, "incoming_seq": _incoming_seq,
		"decoy_until": decoy_until, "jammer_until": jammer_until,
		"sensor_damage": sensor_damage, "link_lost": link_lost,
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
	}
	return JSON.stringify(payload)


func snapshot() -> Dictionary:
	return JSON.parse_string(save_state())


func load_state(data: Variant) -> Dictionary:
	var parsed: Variant = data
	if data is String:
		if String(data).strip_edges() == "":
			return {"ok": false, "reason": "empty_state"}
		parsed = JSON.parse_string(String(data))
		if not (parsed is Dictionary):
			return {"ok": false, "reason": "invalid_json"}
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_payload"}
	var p: Dictionary = parsed
	if String(p.get("schema", "")) != SAVE_SCHEMA:
		return {"ok": false, "reason": "invalid_schema"}
	if String(p.get("version", "")) != SAVE_VERSION:
		return {"ok": false, "reason": "unsupported_version"}
	if not (p.get("weapons") is Dictionary) or not (p.get("tracks") is Array) \
			or not (p.get("solutions") is Array) or not (p.get("grants") is Array):
		return {"ok": false, "reason": "invalid_payload"}
	var new_weapons: Dictionary = (p.get("weapons") as Dictionary).duplicate(true)
	for id in weapons.keys():
		if not new_weapons.has(id):
			return {"ok": false, "reason": "missing_weapon", "weapon_id": id}
	# apply
	t = float(p.get("t", 0.0))
	roe = String(p.get("roe", roe))
	if not (roe in ROE_ORDER):
		return {"ok": false, "reason": "invalid_roe"}
	own_id = String(p.get("own_id", own_id))
	fleet_id = String(p.get("fleet_id", fleet_id))
	weapons = new_weapons
	tracks = {}
	for raw in (p.get("tracks", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) != "":
			tracks[String((raw as Dictionary)["id"])] = (raw as Dictionary).duplicate(true)
	solutions = {}
	for raw in (p.get("solutions", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("solution_id", "")) != "":
			solutions[String((raw as Dictionary)["solution_id"])] = (raw as Dictionary).duplicate(true)
	grants = {}
	for raw in (p.get("grants", []) as Array):
		if raw is Dictionary and String((raw as Dictionary).get("grant_id", "")) != "":
			grants[String((raw as Dictionary)["grant_id"])] = (raw as Dictionary).duplicate(true)
	incoming = (p.get("incoming", []) as Array).duplicate(true) if p.get("incoming") is Array else []
	events = (p.get("events", []) as Array).duplicate(true) if p.get("events") is Array else []
	_event_seq = int(p.get("event_seq", 0))
	_solution_seq = int(p.get("solution_seq", 0))
	_grant_seq = int(p.get("grant_seq", 0))
	_shot_seq = int(p.get("shot_seq", 0))
	_incoming_seq = int(p.get("incoming_seq", 0))
	decoy_until = float(p.get("decoy_until", -1.0))
	jammer_until = float(p.get("jammer_until", -1.0))
	sensor_damage = float(p.get("sensor_damage", 0.0))
	link_lost = bool(p.get("link_lost", false))
	warnings = (p.get("warnings", []) as Array).duplicate() if p.get("warnings") is Array else []
	errors = (p.get("errors", []) as Array).duplicate() if p.get("errors") is Array else []
	_outbox = []
	return {"ok": true, "reason": "", "t": t, "roe": roe}
