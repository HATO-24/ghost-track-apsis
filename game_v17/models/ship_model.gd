extends Node3D

# 方案B-38：CDE/SFHD 风格硬科幻舰船程序化模型。
# 纯色基础材质、无贴图；主轴舰体/反应堆/散热器/燃料罐/引擎簇/武器/传感器桅杆/装甲板。
# 参数：ship_class(BB/CA/CL/DD/FF/AV/...)、ship_role、ship_size、radiator_count、weapon_fit、faction。

@export var ship_class := "DD"
@export var ship_role := "escort"
@export var ship_size := 0.0
@export var radiator_count := 3
@export var weapon_fit := "railgun"
@export var faction := "friendly"
@export var ship_label := ""

var _hull: StandardMaterial3D
var _hull_dark: StandardMaterial3D
var _accent: StandardMaterial3D
var _radiator: StandardMaterial3D
var _tank: StandardMaterial3D
var _engine: StandardMaterial3D
var _armor: StandardMaterial3D
var _weapon: StandardMaterial3D
var _solar: StandardMaterial3D


func _ready() -> void:
	_build_materials()
	_build_ship()


func _build_materials() -> void:
	var friendly := faction in ["friendly", "ocuvf", "ocuvf_id13", ""]
	_hull = _mat(Color(0.43, 0.46, 0.46) if friendly else Color(0.43, 0.42, 0.38), 0.80, 0.04)
	_hull_dark = _mat(Color(0.25, 0.27, 0.27), 0.88, 0.02)
	_accent = _mat(Color(0.29, 0.50, 0.47) if friendly else Color(0.56, 0.46, 0.29), 0.70, 0.06)
	_radiator = _mat(Color(0.60, 0.62, 0.60), 0.72, 0.01)
	_tank = _mat(Color(0.50, 0.52, 0.50), 0.85, 0.02)
	_engine = _mat(Color(0.16, 0.18, 0.18), 0.9, 0.02)
	_armor = _mat(Color(0.36, 0.38, 0.37), 0.86, 0.05)
	_weapon = _mat(Color(0.20, 0.22, 0.22), 0.85, 0.10)
	_solar = _mat(Color(0.09, 0.16, 0.20), 0.55, 0.20)


func _mat(c: Color, rough: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	return m


func _orient_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	if y.length_squared() < 0.5:
		y = Vector3.UP
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _cyl(pos: Vector3, dir: Vector3, radius: float, height: float, mat: StandardMaterial3D, seg := 14) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = seg
	cm.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.transform = Transform3D(_orient_y(dir), pos)
	mi.material_override = mat
	add_child(mi)
	return mi


func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)
	return mi


func _sphere(pos: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _class_length() -> float:
	var c := ship_class.to_upper()
	if ship_size > 0.0:
		return ship_size
	if c.contains("BB"):
		return 6.2
	if c.contains("CA"):
		return 5.0
	if c.contains("CL"):
		return 4.1
	if c.contains("DD"):
		return 3.1
	if c.contains("FF"):
		return 2.2
	if c.contains("AV") or c.contains("CV"):
		return 4.8
	return 3.2


func _build_ship() -> void:
	var length := _class_length()
	var radius := clampf(length * 0.075, 0.18, 0.46)
	var x0 := -length * 0.5
	# 主轴舰体/装甲分段
	_cyl(Vector3.ZERO, Vector3.RIGHT, radius, length, _hull, 18)
	_cyl(Vector3(0, 0, 0), Vector3.RIGHT, radius * 0.62, length * 0.72, _hull_dark, 14)
	for i in range(5):
		var x := x0 + length * (0.18 + float(i) * 0.16)
		_box(Vector3(x, 0, 0), Vector3(length * 0.10, radius * 2.05, radius * 1.45), _armor)
		_box(Vector3(x, radius * 0.92, 0), Vector3(length * 0.08, 0.012, radius * 1.4), _hull_dark)
	# 舰首/传感器桅杆
	_cyl(Vector3(length * 0.5 + 0.18, 0, 0), Vector3.RIGHT, radius * 0.55, 0.32, _hull_dark, 14)
	_cyl(Vector3(length * 0.58, radius * 0.55, 0), Vector3.UP, 0.018, 0.62, _hull_dark, 6)
	_sphere(Vector3(length * 0.58, radius * 0.86, 0), 0.045, _accent)
	_cyl(Vector3(length * 0.5 + 0.30, 0, 0), Vector3.RIGHT, 0.02, 0.65, _hull, 6)
	# 反应堆/推进簇（尾部）
	_cyl(Vector3(x0 - 0.22, 0, 0), Vector3.RIGHT, radius * 1.20, 0.50, _hull_dark, 18)
	_box(Vector3(x0 - 0.25, 0, 0), Vector3(0.16, radius * 2.2, radius * 1.8), _engine)
	for y in [-1.0, 1.0]:
		_cyl(Vector3(x0 - 0.58, radius * 0.55 * y, 0), Vector3.RIGHT, radius * 0.28, 0.55, _engine, 12)
		_cyl(Vector3(x0 - 0.88, radius * 0.55 * y, 0), Vector3.RIGHT, radius * 0.38, 0.10, _engine, 16)
	# 燃料罐（两侧）
	for y2 in [-1.0, 1.0]:
		_cyl(Vector3(x0 + length * 0.34, radius * 1.45 * y2, 0), Vector3.RIGHT, radius * 0.34, length * 0.48, _tank, 12)
		_sphere(Vector3(x0 + length * 0.34 - length * 0.24, radius * 1.45 * y2, 0), radius * 0.34, _tank)
		_sphere(Vector3(x0 + length * 0.34 + length * 0.24, radius * 1.45 * y2, 0), radius * 0.34, _tank)
		_cyl(Vector3(x0 + length * 0.12, radius * 1.45 * y2, 0), Vector3.RIGHT, 0.03, length * 0.12, _hull_dark, 6)
	# 散热器阵列（外露 CDE/SFHD 工业感）
	var rc := clampi(radiator_count, 1, 8)
	for i in range(rc):
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := x0 + length * (0.25 + 0.13 * float(i / 2))
		_box(Vector3(x, side * (radius * 1.9 + 0.35), 0), Vector3(length * 0.14, 0.012, 0.72), _radiator)
		_cyl(Vector3(x, side * radius * 1.75, 0), Vector3.UP, 0.022, 0.70, _hull_dark, 6)
		_box(Vector3(x, side * (radius * 1.9 + 0.55), 0), Vector3(0.012, 0.02, 0.62), _hull_dark)
	# 武器：轨道炮/激光/导弹舱
	var wf := weapon_fit.to_lower()
	if wf.contains("rail") or wf.contains("kinetic"):
		for y3 in [-1.0, 1.0]:
			_cyl(Vector3(length * 0.20, radius * 1.05 * y3, 0), Vector3.RIGHT, 0.042, length * 0.72, _weapon, 10)
			_cyl(Vector3(length * 0.56, radius * 1.05 * y3, 0), Vector3.RIGHT, 0.055, 0.14, _weapon, 10)
		_box(Vector3(-length * 0.10, radius * 1.02, 0), Vector3(length * 0.22, 0.12, 0.20), _accent)
	if wf.contains("laser") or wf.contains("beam"):
		for x2 in [-length * 0.22, length * 0.10]:
			_cyl(Vector3(x2, radius * 1.10, 0), Vector3.UP, 0.075, 0.18, _hull_dark, 10)
			_cyl(Vector3(x2, radius * 1.20, 0), Vector3.UP, 0.045, 0.16, _weapon, 10)
	if wf.contains("missile") or wf.contains("guided"):
		for i2 in range(4):
			var x3 := x0 + length * (0.45 + float(i2) * 0.07)
			_box(Vector3(x3, -radius * 1.0, 0.30), Vector3(0.16, 0.16, 0.34), _hull_dark)
			_box(Vector3(x3, -radius * 1.0, 0.47), Vector3(0.12, 0.12, 0.02), _accent)
	# 装甲/Whipple 屏蔽板
	for x4 in [-0.28, 0.04, 0.30]:
		_box(Vector3(length * x4, 0, radius * 1.55), Vector3(length * 0.18, 0.012, 0.36), _armor, Vector3(0.18, 0, 0))
		_box(Vector3(length * x4, 0, -radius * 1.55), Vector3(length * 0.18, 0.012, 0.36), _armor, Vector3(-0.18, 0, 0))
	# 舰种差异
	if ship_class.to_upper().contains("AV") or ship_role.contains("carrier") or ship_role.contains("aviation"):
		_box(Vector3(0, -radius * 1.25, 0), Vector3(length * 0.68, 0.08, radius * 0.72), _hull_dark)
	if ship_class.to_upper().contains("BB") or ship_role.contains("battleship"):
		for y4 in [-1.0, 1.0]:
			_box(Vector3(0, y4 * radius * 1.40, 0), Vector3(length * 0.48, 0.10, radius * 0.82), _armor)
	# 舰名/身份灯带
	_box(Vector3(0, radius * 0.92, radius * 0.30), Vector3(length * 0.24, 0.010, 0.02), _accent)


# ── 型号变体映射 / CDE-SFHD 参数 ────────────────────────────────
# 覆盖 8 友军 class + 24 敌军 class（含 BB/CA/CL/DD/FF/AV 与 STD/ASSAULT 变体）。
# 仅给出程序化几何参数；不复制现实/游戏资产。

static func _size_for(class_id: String, role: String) -> float:
	var u := class_id.to_upper()
	if u.contains("RECEIVERSHIP") or role.contains("battleship"):
		return 6.2
	if u.contains("ENFORCEMENT") or role.contains("heavy_cruiser"):
		return 5.0
	if u.contains("INTERDICT") or role.contains("light_cruiser"):
		return 4.1
	if u.contains("RECOURSE") or role.contains("destroyer"):
		return 3.1
	if u.contains("REQUISITION") or role.contains("frigate"):
		return 2.2
	if u.contains("SUMMONS") or role.contains("aviso"):
		return 2.8
	if u.contains("APOGEE"):
		return 5.6
	if u.contains("PALLET"):
		return 2.4
	if u.contains("HEMATITE"):
		return 3.4
	if u.contains("GANTRY"):
		return 4.2
	if u.contains("MOONPORT"):
		return 5.0
	if u.contains("SAFEHARBOR"):
		return 2.2
	if u.contains("WINCH"):
		return 2.8
	if u.contains("ARIA"):
		return 1.8
	if u.contains("POLARIS"):
		return 4.8
	if u.contains("SENTINEL"):
		return 2.8
	if u.contains("GATEKEEPER"):
		return 2.4
	if u.contains("FORGE"):
		return 3.8
	if u.contains("TRACTOR"):
		return 3.2
	if u.contains("BEACON"):
		return 2.6
	return 3.2


static func _class_letter(class_id: String, role: String) -> String:
	var u := class_id.to_upper()
	if u.contains("RECEIVERSHIP") or role.contains("battleship"):
		return "BB"
	if u.contains("ENFORCEMENT") or role.contains("heavy_cruiser"):
		return "CA"
	if u.contains("INTERDICT") or role.contains("light_cruiser"):
		return "CL"
	if u.contains("RECOURSE") or role.contains("destroyer"):
		return "DD"
	if u.contains("REQUISITION") or role.contains("frigate"):
		return "FF"
	if u.contains("SUMMONS") or role.contains("aviso"):
		return "AV"
	if u.contains("APOGEE") or u.contains("MOONPORT") or u.contains("POLARIS") or u.contains("FORGE"):
		return "AV"
	return "CL"


static func _weapon_for(class_id: String, role: String) -> String:
	var u := class_id.to_upper()
	if u.contains("GANTRY") or role.contains("missile"):
		return "missile+laser"
	if u.contains("HEMATITE") or role.contains("gun") or role.contains("battleship") or role.contains("cruiser"):
		return "railgun+laser"
	if u.contains("SAFEHARBOR") or role.contains("relay") or role.contains("patrol"):
		return "laser"
	if u.contains("ARIA") or role.contains("shuttle") or role.contains("tanker") or role.contains("tender"):
		return "none"
	return "railgun"


static func variant_for(class_id: String, role: String, faction := "friendly") -> Dictionary:
	var upper := class_id.to_upper()
	var ship_class := _class_letter(class_id, role)
	var is_enemy := not (faction in ["friendly", "ocuvf", "ocuvf_id13", ""])
	var radiators := 3
	if ship_class == "BB":
		radiators = 6
	elif ship_class == "CA":
		radiators = 5
	elif ship_class == "CL":
		radiators = 4
	elif ship_class in ["DD", "AV"]:
		radiators = 3
	elif ship_class == "FF":
		radiators = 2
	if upper.ends_with("-ASSAULT"):
		radiators += 1
	if upper.ends_with("-STD"):
		radiators = maxi(2, radiators - 1)
	return {"ship_class": ship_class, "ship_role": role,
		"ship_size": _size_for(class_id, role),
		"radiator_count": radiators, "weapon_fit": _weapon_for(class_id, role),
		"faction": "enemy" if is_enemy else "friendly",
		"class_id": class_id, "name": class_id}


static func variant_specs(friendly_classes: Array, enemy_classes: Array) -> Array:
	var out: Array = []
	for raw in friendly_classes:
		if raw is Dictionary:
			var c: Dictionary = raw
			var spec: Dictionary = variant_for(String(c.get("class_id", "")), String(c.get("role", "")), "friendly")
			spec["faction_name"] = String(c.get("faction", "ocuvf_id13"))
			out.append(spec)
	for raw2 in enemy_classes:
		if raw2 is Dictionary:
			var c2: Dictionary = raw2
			var spec2: Dictionary = variant_for(String(c2.get("class_id", "")), String(c2.get("role", "")), String(c2.get("faction", "enemy")))
			spec2["faction_name"] = String(c2.get("faction", "enemy"))
			out.append(spec2)
	return out
