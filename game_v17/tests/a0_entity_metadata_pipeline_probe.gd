extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# Phase A-01 / A0-T2 · 实体元数据管道探针
#
# 真实产品入口链路：main_menu → v1_hud → ShellBinder → GameSession（DSH_BUILD=orbital_sim）。
#
# 对 7 个 scenario 实体逐项检查以下字段在整条链路上的传递：
#   side / identity / batch / rcs_m2 / radius_km / has_pd
# 传递层级：PhysicsWorld → WorldState → snapshot → 航迹 → contacts
#
# 规则：
#   * 缺失值必须显示为明确的 `unknown`（或空 + 明确 reason），**禁止静默回退为 `friend`**；
#   * 当前已知的 6/7 错误 contacts 行（缺 side/identity/batch/rcs/radius/has_pd，
#     或静默 friend 回退）必须被探针**明确暴露**，不得隐藏。
#
# 预期失败（Phase A 基线）：
#   - WorldState/snapshot 实体缺少 side/identity/batch/rcs/radius/has_pd（WorldState 只保留
#     8 个核心键，元数据未落库）；
#   - contacts 对无证据实体静默回退 side=friend / identity=friend（6/7 行）；
#   - 航迹 identity 未与 scenario truth 关联（无证据时应 unknown）。
#
# Output: `A0-T2 ENTITY METADATA PIPELINE PROBE RESULT: PASS=n FAIL=m`; quit 0/1.
# ═══════════════════════════════════════════════════════════════════

const TARGET_PROFILE := "orbital_sim"
const TARGET_SCENARIO := "res://framework/content/scenario_orbital_sim.json"
const MAIN_MENU := "res://main_menu.tscn"
const V1_HUD := "res://v1_hud.tscn"
const HUD_SCRIPT := "res://scripts/ui/v1_hud.gd"
const HUD_NODE := "V1HUD"

const MAX_BOOT_FRAMES := 600
const MAX_BOOT_MS := 60000
const MAX_BINDER_FRAMES := 120
const WATCHDOG_S := 180.0

const ENV_KEYS := ["DSH_BUILD", "DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE",
	"DSH_V1_TEST", "DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
	"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]

const META_FIELDS := ["side", "identity", "batch", "rcs_m2", "radius_km", "has_pd"]
const NUM_FIELDS := ["rcs_m2", "radius_km"]
const TICK_DT := 60.0
const TICK_COUNT := 3
# 玩家可见层允许的「无证据」占位值
const SAFE_UNKNOWN := ["unknown", "unknown track", "unknown contact", "unknown signal", ""]
# 权威层：必须与 scenario truth **精确**一致，任何 unknown/缺失都不允许。
const AUTHORITY_LAYERS := ["physics", "world", "snapshot"]
# 证据派生的分类字段：只有这两个字段在**投影层**可以有「带原因」的 unknown。
# （batch/rcs_m2/radius_km/has_pd 是静态事实，必须原样透传，不允许 unknown 豁免。）
const EVIDENCE_DERIVED_FIELDS := ["side", "identity"]
# 能产生身份/阵营判断的证据来源（纯雷达位置观测不能分类）。
const IDENTITY_EVIDENCE_SOURCES := ["iff", "transponder", "optical", "vis", "ir.classify",
	"identification"]
# 仅真值/内部消费者可见的字段：无证据不得进入玩家视图（A-00 契约）。
const TRUTH_ONLY_FIELDS := ["batch", "rcs_m2", "radius_km", "has_pd"]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _env_backup: Dictionary = {}
var _finished := false
var _hud = null
var _binder = null
var _session = null
var _truth: Dictionary = {}
var _truth_ids: Array[String] = []
var _main_menu_instantiated := false


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════════")
	print("A0-T2 ENTITY METADATA PIPELINE PROBE · real entry main_menu → v1_hud")
	print("Godot ", Engine.get_version_info().get("string", "?"), " · profile=", TARGET_PROFILE)
	print("════════════════════════════════════════════════════════════════")
	_setup_env()
	node_added.connect(_on_node_added)
	_watchdog()
	_run()


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	var scr = node.get_script()
	if scr != null and String(scr.resource_path) == "res://scripts/ui/main_menu.gd":
		_main_menu_instantiated = true


func _watchdog() -> void:
	await create_timer(WATCHDOG_S).timeout
	if _finished:
		return
	print("[A0-T2] FAIL watchdog timeout %.0fs" % WATCHDOG_S)
	_fail += 1
	_failures.append("watchdog timeout")
	_finish()


func _setup_env() -> void:
	for k in ENV_KEYS:
		_env_backup[k] = OS.get_environment(k)
	OS.set_environment("DSH_BUILD", TARGET_PROFILE)
	for k in ["DSH_SHOT", "DSH_NO_AUTOSKIP", "DSH_FLOW_SMOKE", "DSH_V1_TEST",
			"DSH_V1_SAVE_TEST", "DSH_LOAD_SLOT", "DSH_HUD_SIZE",
			"DSH_MAIN_MENU_VIEW", "DSH_SETTINGS_TEST", "DSH_PLAYER_NAME"]:
		OS.set_environment(k, "")


func _restore_env() -> void:
	for k in ENV_KEYS:
		var v := String(_env_backup.get(k, ""))
		if v == "":
			OS.unset_environment(k)
		else:
			OS.set_environment(k, v)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("────────────────────────────────────────────────────────────────")
	print("A0-T2 ENTITY METADATA PIPELINE PROBE RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("[A0-T2] FAILED: ", f)
		print("A0-T2 ENTITY METADATA PIPELINE PROBE FAILED")
	else:
		print("A0-T2 ENTITY METADATA PIPELINE PROBE OK")
	_restore_env()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[A0-T2] PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var line := label + (("  (" + detail + ")") if detail != "" else "")
		_failures.append(line)
		print("[A0-T2] FAIL ", line)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, label, "actual=%s expected=%s" % [str(actual), str(expected)])


func _step(title: String) -> void:
	print("")
	print("[A0-T2] STEP ", title)


func _info(text: String) -> void:
	print("[A0-T2] INFO ", text)


# ── run ─────────────────────────────────────────────────────────

func _run() -> void:
	_step("1. real entry main_menu → v1_hud")
	var err := change_scene_to_file(MAIN_MENU)
	_ok(err == OK, "change_scene_to_file(main_menu) == OK", "err=%d" % err)
	if err != OK:
		_finish()
		return
	var boot := await _await_v1_hud()
	if boot["hud"] == null:
		_finish()
		return
	_hud = boot["hud"]
	_ok(bool(boot["saw_main_menu"]), "real entry passed main_menu",
		"saw=%s frames=%d" % [str(boot["saw_main_menu"]), int(boot["frames"])])
	_ok(bool(boot["scene_script_ok"]), "current_scene is V1HUD with v1_hud.gd",
		String(_hud.scene_file_path))
	_binder = _hud.get("binder")
	_session = _binder.get("session") if _binder != null else null
	_ok(_binder != null and bool(_binder.get("ready")), "ShellBinder ready")
	_ok(_session != null, "GameSession available")
	if _session == null:
		_finish()
		return
	_ok(_session.physics_world_service != null, "PhysicsWorld enabled")
	_ok(_session.sensor_service != null, "SensorService enabled")
	_ok(_session.track_table != null, "TrackTable enabled")
	if _session.physics_world_service == null or _session.sensor_service == null:
		_finish()
		return

	_step("2. scenario truth (7 entities, direct JSON read)")
	var sc := _read_json(TARGET_SCENARIO)
	var ents: Array = sc.get("entities", []) if sc.get("entities") is Array else []
	_eq(ents.size(), 7, "scenario entity count")
	for raw in ents:
		if raw is Dictionary:
			var e: Dictionary = raw
			var eid := String(e.get("id", ""))
			if eid != "":
				_truth[eid] = e.duplicate(true)
				_truth_ids.append(eid)
	_truth_ids.sort()
	_ok(_truth.size() == 7, "scenario truth table has 7 entities", str(_truth_ids))
	for eid in _truth_ids:
		var t: Dictionary = _truth[eid]
		_info("TRUTH %s: side=%s identity=%s batch=%s rcs=%s radius=%s has_pd=%s" % [
			eid, String(t.get("side", "")), String(t.get("identity", "")),
			String(t.get("batch", "")), str(t.get("rcs_m2", "")),
			str(t.get("radius_km", "")), str(t.get("has_pd", ""))])

	# 推进几个 tick，让传感器/航迹/contacts 进入稳定状态
	for i in range(TICK_COUNT):
		_session.tick(TICK_DT)
	_binder.refresh()

	_step("3. EntityCatalog is the static-metadata authority (query by stable ID)")
	var catalog = _session.entity_catalog
	_ok(catalog != null and bool(catalog.ready),
		"EntityCatalog present and ready",
		"ready=%s" % str(catalog.ready if catalog != null else false))
	var catalog_bad: Array = []
	var catalog_ok := 0
	if catalog != null and bool(catalog.ready):
		for eid in _truth_ids:
			if not bool(catalog.has_entity(eid)):
				catalog_bad.append({"entity": eid, "reason": "catalog missing entity"})
				continue
			var row: Dictionary = catalog.get_entity(eid)
			if not bool(row.get("found", false)):
				catalog_bad.append({"entity": eid, "reason": "get_entity found=false"})
				continue
			if String(row.get("id", "")) != eid:
				catalog_bad.append({"entity": eid, "reason": "stable ID mismatch",
					"catalog_id": String(row.get("id", ""))})
				continue
			var field_bad := _authority_field_violations(row, _truth[eid], eid, "catalog")
			if field_bad.is_empty():
				catalog_ok += 1
			else:
				catalog_bad.append_array(field_bad)
	_ok(catalog_bad.is_empty(),
		"catalog truth complete and exact for 7 entities × 6 fields (by stable ID)",
		"ok=%d/7 violations=%d sample=%s" % [catalog_ok, catalog_bad.size(),
			str(catalog_bad.slice(0, 6))])

	_step("4. kinematic containers may omit static fields, but must never fabricate them")
	# 协调后契约：PhysicsWorld 只写运动学；WorldState 是投影。**不要求**它们复制静态真值
	# （旧的「必须复制到所有容器」口径会反向强制泄漏）。但若某容器**声明**了这些字段，
	# 其值必须与 catalog 真值一致 —— 不允许伪造/兜底冒充权威值。
	var container_bad: Array = []
	var container_present := 0
	var containers := {
		"physics": func(eid: String) -> Dictionary: return _session.physics_state(eid),
		"world": func(eid: String) -> Dictionary: return _session.world.entity(eid),
	}
	for cname in containers.keys():
		var getter = containers[cname]
		for eid in _truth_ids:
			var row: Dictionary = getter.call(eid)
			for f in META_FIELDS:
				if not row.has(f):
					continue
				container_present += 1
				var vals := _authority_field_violations(row, _truth[eid], eid, cname)
				for v in vals:
					if String(v.get("field", "")) == f:
						container_bad.append(v)
	_ok(container_bad.is_empty(),
		"kinematic containers never fabricate static fields (absent is OK, wrong is violation)",
		"declared_fields=%d violations=%s" % [container_present, str(container_bad.slice(0, 6))])

	_step("5. snapshot: kinematic projection + explicit catalog source block")
	var snap: Dictionary = _session.snapshot()
	var snap_ents: Array = snap.get("entities", []) if snap.get("entities") is Array else []
	_eq(snap_ents.size(), 7, "snapshot has 7 kinematic entities")
	var snap_by_id: Dictionary = {}
	for raw_s in snap_ents:
		if raw_s is Dictionary:
			snap_by_id[String((raw_s as Dictionary).get("id", ""))] = raw_s
	var snap_bad: Array = []
	for eid in _truth_ids:
		var se: Dictionary = snap_by_id.get(eid, {}) if snap_by_id.get(eid) is Dictionary else {}
		if se.is_empty():
			snap_bad.append({"entity": eid, "reason": "missing in snapshot.entities"})
			continue
		# snapshot 是运动投影：必须带位置/速度；静态字段若出现则必须正确。
		if not (se.get("pos_km") is Array) or (se.get("pos_km") as Array).size() < 3:
			snap_bad.append({"entity": eid, "reason": "snapshot entity lacks pos_km"})
		for f in META_FIELDS:
			if not se.has(f):
				continue
			for v in _authority_field_violations(se, _truth[eid], eid, "snapshot"):
				if String(v.get("field", "")) == f:
					snap_bad.append(v)
	_ok(snap_bad.is_empty(),
		"snapshot.entities is a kinematic projection whose declared static fields are catalog-exact",
		"violations=%s" % str(snap_bad.slice(0, 6)))
	# snapshot 必须能明确取得 catalog 来源（合成视图说明字段来源）
	var snap_catalog: Dictionary = snap.get("entity_catalog", {}) \
		if snap.get("entity_catalog") is Dictionary else {}
	_ok(not snap_catalog.is_empty(),
		"snapshot exposes an explicit entity_catalog source block (synthetic view declares source)",
		"present=%s keys=%s" % [str(not snap_catalog.is_empty()), str(snap_catalog.keys())])

	_step("6. ballistics reads catalog authority (no silent defaults)")
	var ball_bad: Array = []
	var ball_checked := 0
	var ball = _session.combat_ballistics
	var ball_catalog = ball.catalog if ball != null and "catalog" in ball else null
	_ok(ball_catalog != null,
		"CombatBallistics holds the EntityCatalog authority reference",
		"catalog_bound=%s" % str(ball_catalog != null))
	if ball_catalog != null:
		for eid in _truth_ids:
			var crow: Dictionary = ball_catalog.get_entity(eid) \
				if ball_catalog.has_method("get_entity") else {}
			if crow.is_empty() or not bool(crow.get("found", false)):
				ball_bad.append({"entity": eid, "reason": "ballistics catalog lookup failed"})
				continue
			ball_checked += 1
			var truth: Dictionary = _truth[eid]
			for f in ["radius_km", "rcs_m2", "has_pd"]:
				if not _meta_value_equal(f, crow.get(f, "<missing>"), truth.get(f, null)):
					ball_bad.append({"entity": eid, "field": f,
						"catalog": str(crow.get(f, "<missing>")),
						"truth": str(truth.get(f, null))})
	_ok(ball_checked == _truth_ids.size() and ball_bad.is_empty(),
		"ballistics resolves radius/rcs/has_pd from catalog for all 7 entities",
		"checked=%d violations=%s" % [ball_checked, str(ball_bad.slice(0, 6))])

	_step("7. player view: tracks carry observations only (no truth leak)")
	var tracks: Array = _session.track_table.vm().get("tracks", []) \
		if _session.track_table.vm().get("tracks") is Array else []
	var tr_by_entity: Dictionary = {}
	for raw_t in tracks:
		if raw_t is Dictionary:
			var tr: Dictionary = raw_t
			tr_by_entity[String(tr.get("entity_id", ""))] = tr
	_ok(tracks.size() > 0, "TrackTable has tracks", "n=" + str(tracks.size()))
	var track_leak: Array = _leak_violations(tr_by_entity, _truth)
	_ok(track_leak.is_empty(),
		"tracks do not leak truth-only fields (batch/rcs/radius/has_pd) to player view",
		"violations=" + str(track_leak))

	_step("8. player view: contacts anonymized, no truth leak, no silent friend")
	var contacts: Array = _binder.get("contacts") if _binder.get("contacts") is Array else []
	_ok(contacts.size() > 0, "binder.contacts non-empty", "n=" + str(contacts.size()))
	var c_by_entity: Dictionary = {}
	for raw_c in contacts:
		if raw_c is Dictionary:
			var c: Dictionary = raw_c
			c_by_entity[String(c.get("entity_id", c.get("id", "")))] = c
	var missing_contacts: Array = []
	for eid in _truth_ids:
		if not c_by_entity.has(eid):
			missing_contacts.append(eid)
	_ok(missing_contacts.is_empty(), "all 7 scenario entities have a contact row",
		"missing=" + str(missing_contacts))
	# 8a. 无证据实体不得静默回退 friend
	var friend_fallback: Array = []
	for eid in _truth_ids:
		if not c_by_entity.has(eid):
			continue
		var c2: Dictionary = c_by_entity[eid]
		var c_side := String(c2.get("side", "")).to_lower()
		var c_ident := String(c2.get("identity", "")).to_lower()
		var truth_side := String((_truth[eid] as Dictionary).get("side", "")).to_lower()
		_info("CONTACT %s: side=%s identity=%s side_source=%s" % [
			eid, c_side, c_ident, String(c2.get("side_source", ""))])
		var truth_is_friend := truth_side in ["friend", "ally", "ueg", "ocu"]
		if c_side == "friend" and not truth_is_friend:
			friend_fallback.append({"entity": eid, "contact_side": c_side,
				"truth_side": truth_side})
		if c_ident == "friend" and not truth_is_friend:
			friend_fallback.append({"entity": eid, "contact_identity": c_ident,
				"truth_side": truth_side})
	_ok(friend_fallback.is_empty(),
		"no silent friend fallback for non-friend entities in contacts",
		"violations=" + str(friend_fallback))
	# 8b. 玩家 contacts 不得泄漏 truth-only 字段（batch/rcs/radius/has_pd）
	var contact_leak: Array = _leak_violations(c_by_entity, _truth)
	_ok(contact_leak.is_empty(),
		"contacts do not leak truth-only fields (batch/rcs/radius/has_pd)",
		"violations=" + str(contact_leak))
	# 8c. 玩家可见字段必须声明来源（side_source/identity_source/display_source）
	var source_bad: Array = []
	for eid in _truth_ids:
		if not c_by_entity.has(eid):
			continue
		var c3: Dictionary = c_by_entity[eid]
		for sf in ["side_source", "identity_source", "display_source"]:
			if String(c3.get(sf, "")) == "":
				source_bad.append({"entity": eid, "missing_source": sf})
	_ok(source_bad.is_empty(),
		"player-facing contact fields declare an explicit source (side/identity/display)",
		"violations=" + str(source_bad.slice(0, 8)))

	_step("9. negative examples: the assertions above actually detect breakage")
	# 9a. catalog 字段丢失必须被检出
	var loss_cat := _fixture_catalog_drop_field("rcs_m2")
	var loss_bad := _authority_field_violations(loss_cat.get("row", {}),
		_truth["harmattan"], "harmattan", "catalog")
	_ok(not loss_bad.is_empty(),
		"NEGATIVE: catalog field loss is detected as a violation",
		"detected=%d" % loss_bad.size())
	# 9b. ID 互换必须被检出（把 harmattan 的数据挂在 raider_2 的 ID 上）
	var swap_bad := _authority_field_violations(
		(catalog.get_entity("harmattan") if catalog != null else {}),
		_truth["raider_2"], "raider_2", "catalog")
	_ok(not swap_bad.is_empty(),
		"NEGATIVE: catalog ID swap is detected as a violation",
		"detected=%d" % swap_bad.size())
	# 9c. radius 兜底冒充 catalog 必须被检出
	var fallback_row := {"id": "skiff", "radius_km": 1.0, "rcs_m2": 180.0,
		"has_pd": false, "side": "hostile", "identity": "unknown", "batch": "OCU-13"}
	var fallback_bad := _authority_field_violations(fallback_row, _truth["skiff"],
		"skiff", "catalog")
	_ok(not fallback_bad.is_empty(),
		"NEGATIVE: radius fallback impersonating catalog is detected",
		"detected=%d" % fallback_bad.size())
	# 9d. 玩家 contacts 的 truth 泄漏必须被检出
	var leaked_rows := {"harmattan": {"entity_id": "harmattan", "side": "unknown",
		"batch": "OCU-07", "rcs_m2": 1100.0, "radius_km": 0.09, "has_pd": true}}
	var leak_bad := _leak_violations(leaked_rows, _truth)
	_ok(not leak_bad.is_empty(),
		"NEGATIVE: truth-field leak into player contacts is detected",
		"detected=%d" % leak_bad.size())
	# 9e. 未知目标变 friend 必须被检出
	var friend_row := {"harmattan": {"entity_id": "harmattan", "side": "friend",
		"identity": "friend"}}
	var friend_truth_side := String((_truth["harmattan"] as Dictionary).get("side", ""))
	var friend_detected := (String(friend_row["harmattan"].side) == "friend"
		and not (friend_truth_side in ["friend", "ally", "ueg", "ocu"]))
	_ok(friend_detected, "NEGATIVE: unknown target forced to friend is detected",
		"truth_side=%s" % friend_truth_side)

	_step("10. A0-T2 baseline evidence summary (expected Phase A failures)")
	_info("A0-T2 BASELINE: catalog_ok=%d/7 catalog_violations=%d" % [
		catalog_ok, catalog_bad.size()])
	_info("A0-T2 BASELINE: container_violations=%d ballistics_violations=%d" % [
		container_bad.size(), ball_bad.size()])
	_info("A0-T2 BASELINE: track_leak=%d contact_leak=%d friend_fallback=%d source_missing=%d" % [
		track_leak.size(), contact_leak.size(), friend_fallback.size(), source_bad.size()])

	_finish()


# ── helpers ─────────────────────────────────────────────────────

## 协调后权威契约（A-00 断言映射）：
##   EntityCatalog = 静态元数据唯一权威（完整、按稳定 ID 查得）；
##   PhysicsWorld 只写运动学；WorldState/snapshot 是投影（可省略静态字段，
##   但一旦声明就必须与 catalog 一致，不得伪造）。
## 返回给定行相对 truth 的**字段级**违例列表（空 = 该行静态字段全部正确）。
func _authority_field_violations(row: Dictionary, truth: Dictionary, eid: String,
		layer: String) -> Array:
	var out: Array = []
	if row.is_empty():
		out.append({"layer": layer, "entity": eid, "reason": "row missing"})
		return out
	for f in META_FIELDS:
		var expected = truth.get(f, null)
		var actual = row.get(f, "<missing>")
		if not _meta_value_equal(f, actual, expected):
			out.append({"layer": layer, "entity": eid, "field": f,
				"actual": str(actual), "expected": str(expected)})
	return out


## 玩家视图真值泄漏检测：contact/track 行不得携带 truth-only 字段。
## 允许例外：本舰（own ship）与有公开记录的设施（facility_id 非空）——
## 但这些例外必须在来源字段里声明（side_source 等），由调用方单独断言。
func _leak_violations(rows_by_entity: Dictionary, truth: Dictionary) -> Array:
	var out: Array = []
	for eid in rows_by_entity.keys():
		var row: Dictionary = rows_by_entity[eid]
		if row.is_empty():
			continue
		var is_own: bool = (String(eid) == "apsis")
		var is_public_facility: bool = String(row.get("facility_id", "")) != ""
		for f in TRUTH_ONLY_FIELDS:
			if not row.has(f):
				continue
			if is_own or is_public_facility:
				# 例外：本舰/公开设施允许，但必须声明来源
				if String(row.get("metadata_source", "")) == "" \
						and String(row.get("side_source", "")) == "":
					out.append({"entity": eid, "field": f, "reason":
						"public exception without declared source"})
				continue
			out.append({"entity": eid, "field": f, "value": str(row.get(f)),
				"reason": "truth-only field leaked into player view"})
	return out


## 负例 fixture：构造一个「丢了某个 catalog 字段」的实体行。
func _fixture_catalog_drop_field(drop: String) -> Dictionary:
	var row: Dictionary = (_truth["harmattan"] as Dictionary).duplicate(true)
	row["id"] = "harmattan"
	row.erase(drop)
	return {"row": row, "dropped": drop}


## 字段比较，按层区分严格程度（A0-T2 审查修正 P1）：
##
##   * **权威层**（PhysicsWorld / WorldState / snapshot）：必须与 scenario truth 精确一致。
##     任何 `unknown`、`<missing>`、`null` 都算违例 —— 权威层不允许把已知事实丢成未知。
##   * **投影层**（track / contacts）：只有**证据派生字段**（side / identity）允许显示
##     `unknown`，且必须同时验证「无身份证据」这一 reason（见 _unknown_reason()）。
##     静态事实字段（batch / rcs_m2 / radius_km / has_pd）没有 unknown 豁免，必须透传。
func _meta_equal(field: String, actual, expected, layer: String, row: Dictionary) -> bool:
	if expected == null:
		expected = ""
	var actual_is_unknown := _is_unknown_token(actual)
	if layer in AUTHORITY_LAYERS:
		# 权威层：精确比较，unknown 一律违例。
		if actual_is_unknown:
			return false
		return _meta_value_equal(field, actual, expected)
	if actual_is_unknown:
		# 投影层 + 非证据派生字段：不允许 unknown 豁免。
		if not (field in EVIDENCE_DERIVED_FIELDS):
			return false
		# 投影层 + 证据派生字段：只在「确实没有身份证据」时接受 unknown。
		return _unknown_reason(field, row)
	return _meta_value_equal(field, actual, expected)


## 判断一个值是否是「未知」占位。
func _is_unknown_token(value) -> bool:
	if value == null:
		return true
	if value is String:
		return String(value).to_lower() in SAFE_UNKNOWN
	return false


## 精确值比较（不含 unknown 豁免）。
func _meta_value_equal(field: String, actual, expected) -> bool:
	if actual == null:
		return false
	if actual is String and String(actual) == "<missing>":
		return false
	if expected == null:
		return actual == null
	if field in NUM_FIELDS:
		var an = _as_number(actual)
		var en = _as_number(expected)
		if an == null or en == null:
			return false
		return absf(float(an) - float(en)) <= 1.0e-9
	if expected is bool:
		var ab = _as_bool(actual)
		return ab != null and bool(ab) == bool(expected)
	return str(actual) == str(expected)


## 把 int/float/数字字符串归一为 float；非数值返回 null。
func _as_number(v):
	if v is int or v is float:
		return float(v)
	if v is String:
		var s := String(v).strip_edges()
		if s.is_valid_float():
			return float(s)
	return null


## 把 bool/bool 字符串归一为 bool；非布尔返回 null。
func _as_bool(v):
	if v is bool:
		return bool(v)
	if v is String:
		var s := String(v).strip_edges().to_lower()
		if s == "true":
			return true
		if s == "false":
			return false
	return null


## 验证投影层 `unknown` 的**原因**是否成立：只有当该行确实缺少身份证据时，
## identity/side 才可以显示为 unknown。缺证据判定基于该行的 evidence/sources/ident 块。
func _unknown_reason(field: String, row: Dictionary) -> bool:
	# 1) 该行必须自证「身份未确认」：contacts 用 ident.known/confidence，tracks 用 level 或证据。
	if row.has("ident") and row.get("ident") is Dictionary:
		var ident: Dictionary = row.get("ident")
		# 身份已确认（known=true）却显示 unknown => reason 不成立。
		if bool(ident.get("known", false)):
			return false
		# 有身份矛盾/欺骗告警时不能静默显示 unknown（必须显式报警，不能当作「未知」）。
		if bool(ident.get("warn", false)) or int(ident.get("contradictions", 0)) > 0:
			return false
		if absf(float(ident.get("confidence", 0.0))) > 0.0:
			return false
	# 2) 该行的证据里不得已包含身份类证据（IFF/transponder/optical 分类等）。
	var sources: Array = row.get("sources", []) if row.get("sources") is Array else []
	for s in sources:
		if _is_identity_source(String(s)):
			return false
	var evidence: Array = row.get("evidence", []) if row.get("evidence") is Array else []
	for raw_ev in evidence:
		if not (raw_ev is Dictionary):
			continue
		var ev: Dictionary = raw_ev
		var src := String(ev.get("source", ev.get("sensor", "")))
		if _is_identity_source(src):
			return false
		if String(ev.get("type", "")) in ["iff", "identification", "classification"]:
			return false
	# 3) 通过：没有任何身份证据，unknown 是诚实的表达。
	return true


func _is_identity_source(src: String) -> bool:
	var s := src.to_lower()
	for known in IDENTITY_EVIDENCE_SOURCES:
		if s == known or s.begins_with(known + "."):
			return true
	return false


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _await_v1_hud() -> Dictionary:
	var frames := 0
	var saw_main_menu := false
	var scene_script_ok := false
	var t0 := Time.get_ticks_msec()
	while frames < MAX_BOOT_FRAMES and (Time.get_ticks_msec() - t0) < MAX_BOOT_MS:
		await process_frame
		frames += 1
		var cs = current_scene
		if cs == null:
			continue
		var path := String(cs.scene_file_path)
		if path == MAIN_MENU:
			saw_main_menu = true
			continue
		if path != V1_HUD:
			continue
		var hud = cs
		var f2 := 0
		while f2 < MAX_BINDER_FRAMES:
			var b = hud.get("binder")
			if b != null and bool(b.get("ready")):
				break
			await process_frame
			f2 += 1
		var scr = hud.get_script()
		var script_path := ""
		if scr != null:
			script_path = String(scr.resource_path)
		scene_script_ok = script_path == HUD_SCRIPT and String(hud.name) == HUD_NODE
		return {"hud": hud, "frames": frames,
			"saw_main_menu": saw_main_menu or _main_menu_instantiated,
			"scene_script_ok": scene_script_ok,
			"elapsed_ms": Time.get_ticks_msec() - t0}
	print("[A0-T2] FAIL entry timeout waiting for v1_hud")
	_fail += 1
	_failures.append("entry timeout")
	return {"hud": null, "frames": frames,
		"saw_main_menu": saw_main_menu or _main_menu_instantiated,
		"scene_script_ok": false, "elapsed_ms": Time.get_ticks_msec() - t0}
