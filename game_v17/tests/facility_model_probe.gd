extends SceneTree

# 方案B-35：FacilityModelFactory probe（300+ 检查）
# 读取 FacilityRegistry 全部 110 设施（29 base + 19 OTC + 62 fuel），逐一映射到 station_model 基型。
# 运行：--headless --path game_v17 --script res://tests/facility_model_probe.gd
# 退出码 0=全过，1=FAIL；只读、不写 world/UI。

const FacilityRegistry := preload("res://scripts/core/facility_registry.gd")
const Factory := preload("res://scripts/ui/facility_model_factory.gd")
const ALLOWED_MODELS := ["port", "depot", "otc", "tank", "fuel", "research"]

var _checks := 0
var _fails := 0
var _failures: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		_failures.append(msg)


func _initialize() -> void:
	print("════════════════════════════════════════════════════════════")
	print("B-35 · FACILITY MODEL FACTORY PROBE")
	print("════════════════════════════════════════════════════════════")
	var reg = FacilityRegistry.new()
	_check(bool(reg.ready), "FacilityRegistry ready")
	_check(reg.total_count() == 110, "registry total_count == 110, got %d" % reg.total_count())
	_check(reg.base_count() == 29, "base_count == 29, got %d" % reg.base_count())
	_check(reg.otc_count() == 19, "otc_count == 19, got %d" % reg.otc_count())
	_check(reg.fuel_count() == 62, "fuel_count == 62, got %d" % reg.fuel_count())
	print("[DATA] registry total=%d base=%d otc=%d fuel=%d" % [reg.total_count(), reg.base_count(), reg.otc_count(), reg.fuel_count()])
	var facilities: Array = reg.facilities
	_check(facilities.size() == 110, "facilities size == 110, got %d" % facilities.size())
	var class_counts: Dictionary = {}
	var model_counts: Dictionary = {}
	var checked_total := 0
	for raw in facilities:
		_check(raw is Dictionary, "facility row is Dictionary")
		if not (raw is Dictionary):
			continue
		var fac: Dictionary = raw
		checked_total += 1
		var cls := String(fac.get("facility_class", ""))
		class_counts[cls] = int(class_counts.get(cls, 0)) + 1
		var mapping: Dictionary = Factory.mapping_for_class(cls)
		_check(bool(mapping.get("supported", false)) or bool(mapping.get("fallback", false)),
			"mapping has support/fallback: " + String(fac.get("facility_id", "")))
		_check(String(mapping.get("model_type", "")) in ALLOWED_MODELS,
			"mapped model type allowed: " + cls + "→" + String(mapping.get("model_type", "")))
		var desc: Dictionary = Factory.describe(fac)
		_check(String(desc.get("facility_id", "")) == String(fac.get("facility_id", "")), "id stable " + String(fac.get("facility_id", "")))
		_check(String(desc.get("model_type", "")) in ALLOWED_MODELS, "describe model type " + String(fac.get("facility_id", "")))
		_check(float(desc.get("scale", 0.0)) >= Factory.SCALE_MIN and float(desc.get("scale", 0.0)) <= Factory.SCALE_MAX,
			"scale range " + String(fac.get("facility_id", "")))
		_check(int(desc.get("module_count", 0)) >= Factory.MODULES_MIN and int(desc.get("module_count", 0)) <= Factory.MODULES_MAX,
			"module range " + String(fac.get("facility_id", "")))
		var desc2: Dictionary = Factory.describe(fac)
		_check(JSON.stringify(desc) == JSON.stringify(desc2), "describe deterministic " + String(fac.get("facility_id", "")))
		var node = Factory.create(fac)
		_check(node != null and node is Node3D, "create returns Node3D " + String(fac.get("facility_id", "")))
		if node is Node3D:
			_check(String(node.get("station_type")) == String(desc.get("model_type", "")), "station_type matches " + String(fac.get("facility_id", "")))
			_check(absf(float(node.get("station_scale")) - float(desc.get("scale", 0.0))) < 1.0e-6, "station_scale matches " + String(fac.get("facility_id", "")))
			_check(int(node.get("module_count")) == int(desc.get("module_count", 0)), "module_count matches " + String(fac.get("facility_id", "")))
			_check(node.has_meta("facility_model_mapping"), "mapping meta " + String(fac.get("facility_id", "")))
			_check(bool(node.get_meta("facility_model_supported", false)), "supported meta " + String(fac.get("facility_id", "")))
			_check(not bool(node.get_meta("facility_model_fallback", true)), "no fallback for known class " + String(fac.get("facility_id", "")))
			node.free()
		var mt := String(desc.get("model_type", ""))
		model_counts[mt] = int(model_counts.get(mt, 0)) + 1
	_check(checked_total == 110, "checked total == 110, got %d" % checked_total)
	_check(int(model_counts.get("otc", 0)) >= 19, "OTC mapped >= 19")
	_check(int(model_counts.get("tank", 0)) >= 31, "tank mapped >= 31")
	_check(int(model_counts.get("fuel", 0)) >= 31, "fuel mapped >= 31")
	var sum_models := 0
	for k in model_counts.keys():
		sum_models += int(model_counts[k])
		_check(int(model_counts[k]) > 0, "model bucket non-empty " + String(k))
	_check(sum_models == 110, "model bucket sum == 110, got %d" % sum_models)
	for cls in class_counts.keys():
		_check(int(class_counts[cls]) > 0, "class present " + String(cls))
	_check(Factory.supports("otc") and Factory.supports("tank") and Factory.supports("fuel"), "supports OTC/tank/fuel")
	_check(not Factory.supports("no_such_class"), "unknown not supported")
	var fb: Dictionary = Factory.mapping_for_class("no_such_class")
	_check(bool(fb.get("fallback", false)), "unknown mapping fallback")
	_check(String(fb.get("model_type", "")) == Factory.FALLBACK_MODEL, "unknown maps fallback model")
	var fnode = Factory.create({"facility_id": "UNKNOWN-TEST", "facility_class": "no_such_class", "physical": {"radius_km": 1.0}})
	_check(fnode != null and fnode is Node3D, "unknown create Node3D")
	if fnode is Node3D:
		_check(bool(fnode.get_meta("facility_model_fallback", false)), "unknown fallback meta")
		fnode.free()
	var sum: Dictionary = Factory.summary(facilities)
	_check(int(sum.get("total", 0)) == 110, "summary total 110")
	_check(int(sum.get("fallbacks", -1)) == 0, "summary fallbacks 0 for known facilities")
	var j1 := JSON.stringify(Factory.mapping_table())
	var j2 := JSON.stringify(Factory.mapping_table())
	_check(j1 == j2, "mapping table deterministic JSON")
	_check(j1.contains("\"supported\""), "mapping table contains supported")
	var summary_msg := "[DATA] mapped=%d classes=%d models=%s" % [checked_total, class_counts.size(), str(model_counts)]
	print(summary_msg)
	print("[DATA] checks=%d fails=%d fallbacks=%d" % [_checks, _fails, int(sum.get("fallbacks", -1))])
	print("────────────────────────────────────────────────────────────")
	if _fails > 0:
		for f in _failures:
			print("[FAILED] ", f)
		print("FACILITY MODEL PROBE FAILED")
		quit(1)
	else:
		print("FACILITY MODEL PROBE OK · checks=%d (>=300)" % _checks)
		quit(0)
