class_name V2BuildProfile
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
# 版本剖面（Build Profile）
#
# 两个交付版本共用同一套系统代码，只在「开机时装什么」上分叉：
#   full        正式本体：序章 + 剧情 + 事件状态机 + 全部系统
#   combat_sim  作战模拟器 DEMO：跳过剧情，直接进战术台，实体来自 sandbox 场景
#
# 设计原则：
#   - 只做「读配置 + 开关查询」，不持有时序状态、不写 world/UI；
#   - 两个版本的存档 schema、服务接口、内容格式完全一致 → 开发互通；
#   - 配置读不到/写坏时**回退 full**（老行为），绝不因为版本配置把游戏打死。
#
# 选择方式（优先级从高到低）：
#   1. setup({"id": "combat_sim"}) 显式指定
#   2. 环境变量 DSH_BUILD
#   3. 配置里的 "default"
# ═══════════════════════════════════════════════════════════════════

const DEFAULT_PATH := "res://framework/content/build_profiles.json"
const SCHEMA := "build_profiles.v1"
const ENV_KEY := "DSH_BUILD"
const FALLBACK_ID := "full"

# 功能开关全集。配置里缺项按 false 处理（除了 combat/ballistics/damage/physics_world
# 这类「不给就打不了仗」的项，由调用方按需要自行兜底）。
const FEATURES := [
	"story", "prelude", "triggers",
	"identification", "traffic", "port", "signal",
	"combat", "ballistics", "damage", "physics_world",
	"sandbox",
]

# 沙盒便利项全集（只在 boot_mode=="sandbox" 时生效；正式本体恒为 false）
#   unlimited_ammo   弹药不扣减（含 PD/干扰弹），也不因弹药耗尽降级 ROE
#   auto_authorize   FIRE 免授权（confirmed 仍必须），演示时可自由选目标
#   quick_restart    UI 允许一键按原 seed 重开（session.reset()）
const SANDBOX_OPTS := ["unlimited_ammo", "auto_authorize", "quick_restart"]

var ready := false
var errors: Array = []
var warnings: Array = []

var id := ""
var label := ""
var subtitle := ""
var entry_scene := ""
var boot_mode := "prelude"          # prelude | sandbox
var scenario := ""
var save_root := "user://saves"
var features: Dictionary = {}
var sandbox_opts: Dictionary = {}   # 仅 sandbox 剖面使用；full 恒为空
var notes: Array = []
var profiles: Dictionary = {}       # 全量（含未启用），供切换/展示
var default_id := FALLBACK_ID
var content_path := DEFAULT_PATH


func _init(config := {}) -> void:
	setup(config)


func setup(config := {}) -> bool:
	ready = false
	errors = []
	warnings = []
	var cfg: Dictionary = config if config is Dictionary else {}
	content_path = String(cfg.get("content_path", DEFAULT_PATH))
	var data: Dictionary = cfg.get("content", {}) if cfg.get("content") is Dictionary else {}
	if data.is_empty():
		data = _read_json(content_path)
	if data.is_empty():
		errors.append("build_profiles 不可读或 JSON 无效: " + content_path)
		return _fallback("配置缺失")
	if String(data.get("schema", "")) != SCHEMA:
		errors.append("build_profiles schema 非 " + SCHEMA + "：" + String(data.get("schema", "")))
		return _fallback("schema 不符")
	var raw_profiles = data.get("profiles", {})
	if not (raw_profiles is Dictionary) or (raw_profiles as Dictionary).is_empty():
		errors.append("build_profiles 无 profiles")
		return _fallback("无 profiles")
	profiles = (raw_profiles as Dictionary).duplicate(true)
	default_id = String(data.get("default", FALLBACK_ID))
	if default_id == "" or not profiles.has(default_id):
		warnings.append("default 指向不存在的剖面 '" + default_id + "'，回退 " + FALLBACK_ID)
		default_id = FALLBACK_ID
	# 选中的剖面
	var want := String(cfg.get("id", ""))
	var src := "config"
	if want == "":
		want = OS.get_environment(ENV_KEY)
		src = "env"
	if want == "":
		want = default_id
		src = "default"
	if not profiles.has(want):
		warnings.append("剖面 '" + want + "' 不存在（来源 " + src + "），回退 " + default_id)
		want = default_id
	var p: Dictionary = profiles[want]
	id = want
	label = String(p.get("label", want))
	subtitle = String(p.get("subtitle", ""))
	entry_scene = String(p.get("entry_scene", ""))
	boot_mode = String(p.get("boot_mode", "prelude"))
	scenario = String(p.get("scenario", ""))
	save_root = String(p.get("save_root", "user://saves"))
	notes = (p.get("notes", []) as Array).duplicate() if p.get("notes") is Array else []
	var f: Dictionary = p.get("features", {}) if p.get("features") is Dictionary else {}
	features = {}
	for k in FEATURES:
		features[k] = bool(f.get(k, false))
	# 沙盒便利项：只有 sandbox 剖面认这些开关，正式本体一律强制关闭（不给作弊口子）
	sandbox_opts = {}
	if boot_mode == "sandbox":
		var so: Dictionary = p.get("sandbox_opts", {}) if p.get("sandbox_opts") is Dictionary else {}
		for k in SANDBOX_OPTS:
			sandbox_opts[k] = bool(so.get(k, false))
	else:
		for k in SANDBOX_OPTS:
			sandbox_opts[k] = false
	# 一致性校验：打不了仗的模拟器没有意义
	if not (boot_mode in ["prelude", "sandbox"]):
		errors.append("boot_mode 非法：" + boot_mode)
		boot_mode = "prelude"
	if boot_mode == "sandbox":
		for req in ["combat", "ballistics"]:
			if not bool(features.get(req, false)):
				warnings.append("sandbox 剖面未开启 " + req + "，将无法交战")
		if scenario == "":
			warnings.append("sandbox 剖面未指定 scenario，实体表会为空")
	ready = errors.is_empty()
	return ready


func _fallback(reason: String) -> bool:
	# 老行为：等同 full
	id = FALLBACK_ID
	label = "GHOST TRACK // APSIS"
	subtitle = "回退剖面（" + reason + "）"
	entry_scene = "res://main_menu.tscn"
	boot_mode = "prelude"
	scenario = ""
	save_root = "user://saves"
	features = {}
	for k in FEATURES:
		features[k] = k != "sandbox"
	sandbox_opts = {}
	for k in SANDBOX_OPTS:
		sandbox_opts[k] = false
	ready = true
	warnings.append("build_profile 回退 " + FALLBACK_ID + "：" + reason)
	return true


func enabled(feature: String) -> bool:
	return bool(features.get(feature, false))


func is_sandbox() -> bool:
	return boot_mode == "sandbox"


## 沙盒便利项查询（非 sandbox 剖面恒 false）。
func sandbox_opt(key: String, fallback := false) -> bool:
	if not is_sandbox():
		return fallback
	return bool(sandbox_opts.get(key, fallback))


func is_combat_sim() -> bool:
	return id == "combat_sim" or is_sandbox()


func profile_ids() -> Array:
	var out: Array = profiles.keys()
	out.sort()
	return out


## 切换到另一个剖面（运行时不重建服务，只换开关；供菜单/测试使用）。
func select(new_id: String) -> bool:
	if not profiles.has(new_id):
		warnings.append("select 未知剖面：" + new_id)
		return false
	return setup({"content_path": content_path, "id": new_id})


func vm() -> Dictionary:
	return {"schema": "build_profile.v1", "ready": ready, "id": id,
		"label": label, "subtitle": subtitle, "entry_scene": entry_scene,
		"boot_mode": boot_mode, "scenario": scenario, "save_root": save_root,
		"features": features.duplicate(true), "notes": notes.duplicate(),
		"sandbox_opts": sandbox_opts.duplicate(true),
		"default": default_id, "profiles": profile_ids(),
		"warnings": warnings.duplicate(), "errors": errors.duplicate(),
		"writes": {"world": false, "track_table": false, "ui": false}}


func summary() -> Dictionary:
	return {"schema": "build_profile.v1", "id": id, "boot_mode": boot_mode,
		"features": features.duplicate(true), "entry_scene": entry_scene,
		"sandbox_opts": sandbox_opts.duplicate(true)}


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
