# 完整游戏-阶段5H · ShipCatalog 数值推算 / role 模板 / damage_profiles 对齐

> 任务 task-219。工程 `game_v17`。
> 修改：`framework/content/ships_enemy.json`、`framework/content/ships_friendly.json`、
> `scripts/core/ship_catalog.gd`、`tests/ship_catalog_probe.gd`、本文件。不改其他；未 commit。
> 依据 `docs/04 §7/§12.8`、`docs/16 §3–4`、`docs/46 §9.3–9.4`；全部 proposal，
> 常规操作性数值不再用 TBD。

## 1　目录模型（5E 沿用）

| 项 | 数量 |
| --- | --- |
| 友军 OCUVF-ID13 基础型 | 8 |
| 33OSID 基础级 | 6（BB/CA/CL/DD/FF/AV），每级 2 个独立亚种（STD/ASSAULT） |
| 33OSID 类目合计 | 18 |
| ORBFLT 基础舰级 | 6 |
| ORBFLT `operator_variants` | 每 base 2（ueof_7th ×1、ueof_3rd ×1） |
| ORBFLT `fleet_variants` | 每 base 1（uegaf_orbflt） |
| 变体合计 | 18（operator 12 + fleet 6） |
| **base classes** | **32**（友 8 + 33OSID 18 + ORBFLT 6） |
| damage_profiles class | 36（32 base + 4 旧 UEOF profile：UEOF-7TH-CA/DD、UEOF-3RD-CA/DD） |

UEOF 第7/第三远征舰队**无独立舰级**；共用 ORBFLT base，`classes("ueof_7th/3rd")==[]`。
33OSID 的 12 个亚种是独立 class（`variant_of` 指向母级）。

## 2　33OSID role 模板（5H）

`enemy.role_templates` 给 6 基础角色提供 proposal 基线；基础级直接使用，STD 亚种
用 1.0 倍率，ASSAULT 用修正倍率（mass×1.08、dv×0.92、accel×0.95、crew×1.10、
rcs×1.05、ir×1.05、dims×1.02；sensors +UEG-FC2、weapons +UEG-BOARDING）。

| role | class | displacement_t | dv_kmps | accel_g | crew | rcs_m2 | ir_signature | dimensions_m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BB | 33OSID-RECEIVERSHIP | 52000 | 4.2 | 0.015 | 1600 | 85000 | 950 | 420×90×110 |
| CA | 33OSID-ENFORCEMENT | 28000 | 5.5 | 0.025 | 720 | 42000 | 620 | 300×70×85 |
| CL | 33OSID-INTERDICT | 16000 | 6.2 | 0.035 | 360 | 24000 | 420 | 220×55×65 |
| DD | 33OSID-RECOURSE | 7500 | 7.0 | 0.060 | 180 | 12000 | 260 | 150×40×45 |
| FF | 33OSID-REQUISITION | 4200 | 7.6 | 0.080 | 92 | 8000 | 180 | 110×30×35 |
| AV | 33OSID-SUMMONS | 1800 | 8.4 | 0.120 | 42 | 3500 | 90 | 80×22×24 |

传感器 UEG 标准：`UEG-SR9/UEG-OPT2/UEG-IR2/UEG-ELINT/UEG-IFF`（AV 无 ELINT）；
武器按角色：轨道炮 H/M/L、导弹 VLS-32/16/8、PD 激光、干扰、登舰模块。
每类带 `auto_derived:true`、`derivation:{template,formula,source}`、`tbd:[]`；
`signature:{rcs,ir}` 与 `rcs_m2/ir_signature` 同步。

变体派生直接写在 JSON（值 = base × modifiers），并带 `modifiers`/`derivation`；
ShipCatalog 仍保留 ORBFLT/UEOF 变体由 base+modifiers 自动展开的路径。

## 3　友军 8 型 role 模板（5H）

`friendly.role_templates`：

| role | rcs_m2 | ir_signature | dimensions_m |
| --- | --- | --- | --- |
| depot | 36000 | 420 | 260×120×90 |
| picket | 1200 | 45 | 45×18×20 |
| gun | 6800 | 120 | 90×30×35 |
| missile | 5200 | 95 | 80×28×30 |
| tanker | 15000 | 260 | 140×40×45 |
| relay | 2600 | 70 | 60×22×25 |
| tug | 2100 | 55 | 50×20×22 |
| shuttle | 120 | 12 | 18×6×5 |

- 友军 `armor` 取 `damage_profiles.effects.armor`（kinetic_resist/energy_resist）；
  `rcs`/`ir`/`rcs_m2`/`ir_signature`/`dimensions_m` 由 role 模板填充；
- 每型带 `auto_derived:true`、`derivation`、`damage_profile_class_id`、`tbd:[]`；
- 原有 8 型吨位/Δv/加速度/编制数值不变；舰名/舷号不变。

## 4　与 damage_profiles 对齐

- 每 base class 有 `damage_profile_class_id`：
  - 友军 8 型 = 自身 class_id；
  - 33OSID 18 类 = 自身 class_id（含 STD/ASSAULT）；
  - ORBFLT 6 base = 自身 class_id。
- 变体：
  - ORBFLT fleet variants → base class profile；
  - UEOF 7th/3rd operator variants → 旧 UEOF profile：
    - 大/指挥/工坊类 base → `UEOF-7TH-CA` / `UEOF-3RD-CA`；
    - 巡逻/检查/拖船/信标类 → `UEOF-7TH-DD` / `UEOF-3RD-DD`。
- `armor` 从 profile 的 `effects.armor` 复制；`sections` 保持 7 个标准区段 id，
  **不重复造** profiles 的分区/材质数据；需要细节时按 class_id 查 profile。
- ShipCatalog 默认读取 `framework/content/damage_profiles.json`，校验：
  - 每 class/variant 的 `damage_profile_class_id` 在 profiles 中存在；
  - 缺失 → catalog `ready=false` / `profile_aligned=false`；
  - summary 提供 `damage_profile_classes=36`、`profile_aligned=true`。

## 5　CA-4471 / 33OSID 审计（更新）

- CA-4471 `batch=null`（unassigned）+ `batch_source`：舷号 ≠ 融合批号；
  `by_batch("TBD")` 不命中。
- AV-4412 batch `2001` 保留 + `batch_source`（融合批号）。
- `enemy.audit` 更新：
  - 33OSID 6 base/18 类操作性数值由 role 模板与 base+modifiers 推算，
    `tbd:[]`、`operational_tbd=0`；
  - armor/sections 引用 damage_profiles，不重复造；
  - 仍保留：name_pool 三语域为候选名、具体舰名/日文写法待内容阶段；
  - BB/CA/CL/DD/FF/AV 是类型代码，不是融合批号/舰体编号。
- 33OSID 不再有操作性 TBD；仅叙事/命名/batch 可为 null/TBD。

## 6　ShipCatalog 校验（5H 增量）

- 操作性字段不得 TBD/字符串：`displacement_t/dv_kmps/accel_g/crew/rcs*/ir*/armor/
  dimensions_m/sensors/weapons`；
- `tbd` 列表必须为空；`auto_derived=true`、`derivation` 非空、
  `damage_profile_class_id` 非空；
- `damage_profile_class_id` 必须在 profiles classes 中；
- 原有 class_id/variant_id/hull/name 唯一性、33OSID 6+2、ORBFLT 6+2+1、
  UEOF 无独立 class 等继续校验；
- `summary` 输出 `operational_tbd/tbd_fields/auto_derived_classes/
  damage_profile_classes/profile_aligned`。

## 7　API

沿用 5E API：`classes/class_of/variants_of/resolve_variant/resolve/known_ship/
by_batch/entity_binding/name_pool/summary/to_dict/to_json/check_contracts`。
新增可读字段：class 的 `auto_derived/derivation/damage_profile_class_id/
rcs_m2/ir_signature`；summary profile 对齐信息。

## 8　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/ship_catalog_probe.gd
# V17 SHIP CATALOG PROBE RESULT: PASS=1488 FAIL=0（exit 0，只跑一次）
```

覆盖：32 base/18 variants；友军 8 型无 TBD/模板 rcs/ir/dims/armor/profile；
33OSID 6 base/18 类字段、role 模板公式、STD/ASSAULT 修正、UEG 传感器/武器、
armor=damage_profiles.effects.armor、profile id；18 变体 profile 对齐；
operational_tbd=0、auto_derived_classes=50、profiles 36、profile_aligned；
操作 TBD/缺 derivation 拒绝；JSON/确定性/5E 规则回归。

## 9　边界

- 所有数值/模板/舰名为 proposal；不宣称官方定案；33OSID 具体官方数值仍待用户定。
- armor/sections 只引用 damage_profiles class；不改 damage_profiles 内容。
- 不接 UI/战斗/实体生成；不写 world/V15；未跑其他 probe；未 commit。
