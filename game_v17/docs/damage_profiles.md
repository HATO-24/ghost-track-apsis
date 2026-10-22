# 完整游戏-阶段5C · 按舰级毁伤物理档案

> 任务 task-207。工程 `game_v17`。新增：
> `framework/content/damage_profiles.json`、`scripts/core/damage_profile_service.gd`、
> `tests/damage_profile_probe.gd`、`docs/damage_profiles.md`；
> 修改：`scripts/core/damage_service.gd`、`framework/core/damage_model.gd`（接入按 class 档案）。
> 不改其他；不接 UI/不重写战斗；未 commit。

## 1　定位

36 型舰级（ShipCatalog `class_id`）的**分区/装甲/材质/后效档案**：

```
damage_profiles.json（36 型）
        │
        ├─ DamageProfileService：load/validate/profile_for(class/entity)/
        │   sections/armor/effects/summary；未知回退 default
        │
        ├─ DamageModel：setup(content, ship_id, class_profile)
        │   - 旧 damage_l1.ships 显式档案优先（旧行为不变）
        │   - 无显式档案时按 class sections + effects 建模型
        │   - apply_hit 使用 section armor_kinetic/armor_energy（旧档案回退全局 armor）
        │   - 火灾/失压/断电/穿透溢出/殉爆仍用 DamageModel 既有逻辑
        │
        └─ DamageService：按 ship_class/class_id 建档、自动建舰、存档
```

## 2　内容 schema（`damage_profiles.json`）

```json
{
  "schema": "damage_profiles.v1", "version": "1.0.0",
  "default_class_id": "UEOF-7TH-DD",
  "materials": {
    "steel":{"label":"钢","kinetic":0.10,"energy":0.06},
    "composite":{...}, "ceramic":{...}, "whipple":{...}
  },
  "classes": {
    "33OSID-RECEIVERSHIP": {
      "class_id":"33OSID-RECEIVERSHIP","name":"清算级","name_en":"Receivership",
      "role":"battleship","faction":"33osid","hull_class":"BB",
      "displacement_t":80000.0,
      "sections":[
        {"id":"hull","label":"舰体 / HULL","kind":"hull",
         "integrity":1.0,"mass_fraction":0.35,
         "armor_kinetic":0.375,"armor_energy":0.30,
         "material":"composite","critical_systems":["structure"],
         "systems":["structure"],"requires_power":false,"power_critical":false,
         "adjacent":["power","propulsion","sensors","comms","tanks","docking"],
         "repair_s":297.0,"fire_risk":0.15,"vacuum_risk":0.25}
      ],
      "effects":{
        "armor":{"kinetic_resist":0.276,"energy_resist":0.221},
        "penetration":{"overflow_ratio":0.41,"min_energy":0.25,
          "max_sections":2,"directions":["fore","aft","port","starboard","ventral","dorsal"]},
        "fire":{...},"decompression":{...},"power":{...},"repair":{...}
      }
    }
  }
}
```

- `classes` 共 **36**（ShipCatalog 全部 class_id；与 ships_friendly/enemy 对齐）；
- 每 section 必须：`id/label/kind/integrity/mass_fraction/armor_kinetic/armor_energy/
  material/critical_systems/adjacent/repair_s/fire_risk/vacuum_risk`；
  `systems/requires_power/power_critical` 供 DamageModel 兼容；
- mass_fraction 总和≈1；material ∈ steel/composite/ceramic/whipple；
- `effects` 为后效覆盖：armor/penetration/fire/decompression/power/repair；
  缺省由 DamageModel 的 damage_l1 全局值补足。

### 2.1 36 型分布

| hull_class | 数量 | 典型 class_id |
| --- | --- | --- |
| BB | 3 | 33OSID-RECEIVERSHIP 及 assault/std 变体 |
| CA | 3 | 33OSID-ENFORCEMENT；UEOF-7TH-CA / 3RD-CA |
| CL | 5 | 33OSID-INTERDICT 变体、UEOF cruisers |
| DD | 9 | 33OSID-RECOURSE 变体、UEOF escorts、ORBFLT patrol |
| FF | 7 | 33OSID-REQUISITION 变体、customs/frigate |
| AUX | 8 | OCUVF depot/tanker/tug/shuttle、ORBFLT tender/tug、relay |
| STATION | 1 | ORBFLT-BEACON（交通管制中继；无 propulsion 分区） |

- BB/CA 重甲，CL/DD 中甲，FF/AV 轻甲；AUX 依角色；
- 油船/补给舰（MOONPORT-4/APOGEE 等）tanks 质量分数、火灾/失压风险更高；
- STATION 档案不含 propulsion；`mass_fraction` 重新归一到 1。

### 2.2 材质与装甲

| material | kinetic | energy | 用途 |
| --- | --- | --- | --- |
| steel | 0.10 | 0.06 | 商船/油船/轻型结构 |
| composite | 0.22 | 0.16 | 主力舰/巡洋舰 |
| ceramic | 0.26 | 0.20 | 重点分区/高硬度 |
| whipple | 0.08 | 0.14 | 轻量/碎片防护 |

- 每 section 的 `armor_kinetic/energy` 是**该分区抗性**；DamageModel `apply_hit`
  优先用 section 值，旧档案没有这两个字段时回退全局 `damage_l1.armor`；
- `effects.armor` 是模型级全局等效值（用于 repair/power 等未覆盖处）；
- 数值为等效提案，不是真实材料/装甲物理。

## 3　DamageProfileService API

```gdscript
const P := preload("res://scripts/core/damage_profile_service.gd")
var p = P.new()                       # 默认读 damage_profiles.json
# 或 P.new({"content_path":..., "content":..., "catalog_enabled":true,
#           "expected_classes":36, "catalog":ShipCatalog实例})

p.ready / p.errors / p.class_ids / p.default_class_id / p.materials
p.profile_for(class_id 或 entity/ship/hull) -> profile（含 fallback/requested）
p.profile_for_entity(entity_id) / p.has_class(class_id) / p.headers()
p.sections(query) / p.section(query, section_id)
p.armor(query) / p.effects(query) / p.material(query, section_id) / p.hull_class(query)
p.summary() / p.to_dict() / p.to_json()
```

- 解析顺序：class_id 精确 → ShipCatalog class_of/known_ship/entity 匹配（大小写不敏感）；
- 未知回退 `default_class_id`，返回 `fallback=true, reason=unknown_class`，**不伪造**
  为已知 class；
- 校验：schema/version/classes 数量=36、class_id 唯一、section 字段/材质/mass 总和、
  default_class_id 存在；非法内容 ready=false（不静默降级）；
- 只读，不写 world/TrackTable/UI。

## 4　DamageModel 接入

```gdscript
var m = DamageModel.new()
m.setup(content, ship_id, class_profile)   # class_profile 来自 DamageProfileService
# 旧调用 m.setup(content, ship_id) 行为不变
```

- `ships` 中有 `ship_id` → **旧 damage_l1 显式档案优先**，`class_profile` 被忽略
  （`profile_source="damage_l1"`，class_id 为空，旧分区/阈值/行为不变）；
- 无显式档案 + class_profile → 构造 class profile 的 7/6 分区；
  `profile_source="class_profile"`、`class_id` 写入；
- `content` 的全局 thresholds/repair/fire/decompression 保留，class `effects` 覆盖
  对应子对象；section 带 `mass_fraction/armor_*/material/critical_systems`；
- `apply_hit`：
  - 每 section 抗性 = `armor_kinetic*(1-pen) + armor_energy*pen`；
  - 无 section armor 的旧档案回退全局 armor（旧数值/旧 probe 不变）；
  - 穿透溢出到相邻分区时按目标分区抗性计算；
  - 火灾/失压/断电/殉爆沿用原逻辑；
- `vm_damage()` 增加 `class_id/profile_source` 与 section 的 armor/material/
  mass_fraction/critical_systems；旧字段保留；
- `reset()` 保留 class_profile，可继续按 class 重置。

## 5　DamageService 接入

```gdscript
var s = DamageService.new({
  "ships": [
    {"id":"bb1", "class_id":"33OSID-RECEIVERSHIP"},
    {"id":"ff1", "class_id":"33OSID-REQUISITION"}
  ],
  "profiles_enabled": true,
  "profile_path": "res://framework/content/damage_profiles.json",
  # "allow_profile_fallback": false
})
s.add_ship(ship_id, class_or_entity, opts) / s.ensure_ship(...)
s.ship_class_id(ship_id) / s.profile_for(ship_id)
s.apply_combat_damage(event)               # target_ship + class_id 可自动建档
s.vm() / s.summary() / s.save_state() / s.load_state()
```

- `ships` 项可为字符串（旧 ship_id）或 `{id, class_id}`；
  damage_l1 有显式档案 → 旧模型；否则按 class profile 建档；
- 未知舰事件可带 `class_id`，自动 `add_ship` 后应用伤害；无 class/回退禁用 →
  `unknown_ship`（不伪造）；
- `add_ship` 对已存在舰返回 existing；`allow_fallback` 控制未知 class 是否默认档案；
- VM/summary 增加 `profiles{enabled,classes,default_class_id}`；
- 存档增加 `profile_path/profiles_enabled/ship_classes`；load 对 class 新增舰按
  `ship_classes` 重建后恢复；旧存档缺字段仍按旧行为加载；
- 旧 `damage_l1.ships` 显式覆盖保持最高优先级。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/damage_profile_probe.gd
# DAMAGE PROFILE PROBE RESULT: PASS=558 FAIL=0
# DAMAGE PROFILE PROBE OK（退出码 0）
```

覆盖：
- 36 型档案数量/class_id 对齐 ShipCatalog/section 字段/材质/mass/effects；
- BB>CA>CL>DD>FF 装甲差异、油船大储箱、站体无 propulsion；
- 服务查询/实体映射（harmattan/CA-4471 等）/未知回退/非法内容；
- DamageModel：class 建档、section armor、BB vs FF 伤害差、火灾/失压、
  旧 damage_l1 覆盖优先、旧档案无 class armor、reset、VM；
- DamageService：class 舰、add_ship、自动建档、旧显式覆盖优先、旧默认 6 舰、
  save/load class 舰、非法 profiles、JSON/确定性/不写。
- 旧回归：`damage_probe PASS=219`、`damage_service_probe PASS=319` 全过。

## 7　边界

- 不接 UI/世界/战斗；不改 damage_l1；不重写 DamageModel 的火灾/失压/损管逻辑。
- 装甲/材质/mass_fraction/effects 为等效提案值，不是真实材料/结构物理；
  36 型的 displacement 部分为 TBD，按 hull_class 等效值。
- 不实现真实穿甲/破片/爆炸场/结构有限元；section armor 是归一化抗性。
- `expected_classes=36` 默认为本内容契约；其他内容可通过 setup 覆盖。
- 未知 class 回退 default 是**只读回退**，不会把实体伪装成已知舰级；
  DamageService 默认拒绝未知舰（除非 `allow_profile_fallback`）。
- 未改 FacilityRegistry/战斗/传感器/UI；未接存档文件 I/O（SaveService 负责）。
- 旧 `damage_integration_probe` 的 ferry 无档案断言与当前 damage_l1 已含 ferry
  档案的历史数据不一致（非本任务引入），本任务只保证 damage_probe/
  damage_service_probe 旧行为通过。
- 未跑全量回归；未 commit。
