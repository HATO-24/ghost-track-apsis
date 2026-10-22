# 完整游戏-阶段5E · ShipCatalog 共用舰级 / 亚种 / 自动推算 / 审计

> 任务 task-212。工程 `game_v17`。
> 修改：`framework/content/ships_enemy.json`、`scripts/core/ship_catalog.gd`、
> `tests/ship_catalog_probe.gd`、本文件。不改其他；未 commit。
> 依据 `docs/04 §7/§12.8`、`docs/16 §3–4`、`docs/46 §9.3–9.4`；全部 proposal，缺失项 TBD。

## 1　5E 模型：共用舰级 + 亚种

UEOF 第7舰队 / 第三远征舰队**不再拥有独立舰级**。二者共用 UEGAF-ORBFLT 的
6 个基础舰级，通过在 base 上挂 `operator_variants` 表达；ORBFLT 自身另有
`fleet_variants`。亚种不是独立 class，不进入 `classes()` 的类型数。

| 项 | 数量 |
| --- | --- |
| 友军 OCUVF-ID13 基础型 | 8 |
| 33OSID 基础级 | 6（BB/CA/CL/DD/FF/AV） |
| 33OSID 改装亚种（独立 class，`variant_of`） | 12（每 base 2） |
| ORBFLT 基础舰级 | 6（北极星/哨兵/关卡/工坊/牵引/信标） |
| 每个 ORBFLT base 的 `operator_variants` | 2（ueof_7th ×1、ueof_3rd ×1） |
| 每个 ORBFLT base 的 `fleet_variants` | 1（uegaf_orbflt） |
| ORBFLT 变体总数 | 18（operator 12 + fleet 6） |
| **base classes 总计** | **32**（友 8 + 33OSID 18 + ORBFLT 6） |
| **variant 总计** | **18** |
| known ships | 7（友 5 / 敌 2） |

- `classes(faction)` 只返回基础/独立 class：`classes("ueof_7th") == []`、
  `classes("ueof_3rd") == []`，`classes("uegaf_orbflt")` 为 6 个 base。
- 变体查询走 `variants_of(base_id | operator | faction)` / `resolve_variant(id)`；
  `class_of(variant_id)` 展开回 base class。
- 33OSID 的 12 个亚种仍是 class（`variant_of` 指向母级），保持 18 条类目。

## 2　变体字段与自动推算

每个 base 的 `operator_variants[]` / `fleet_variants[]` 条目：

```json
{
  "variant_id": "ORBFLT-SENTINEL-U7",
  "name": "哨兵级·第7舰队型",
  "role": "orbital_patrol_ueof_7th",
  "operator": "ueof_7th",
  "faction": "ueof_7th",
  "refit": "ueof_7th_expedition_package",
  "derive_from": "ORBFLT-SENTINEL",
  "hull_suffix": "U7",
  "modifiers": {
    "mass_factor": 1.02, "dv_factor": 1.12,
    "accel_factor": 0.96, "crew_factor": 0.95,
    "sensors_add": ["ELINT-7"], "weapons_add": ["MISSILE-7"]
  },
  "proposal": true, "source": "docs/46 §9.3"
}
```

ShipCatalog 在载入时自动展开（不写回 JSON base）：

| 派生字段 | 公式 |
| --- | --- |
| `displacement_t` | `base.displacement_t × mass_factor`（`displacement_factor` 兼容） |
| `dv_kmps` | `base.dv_kmps × dv_factor` |
| `accel_g` | `base.accel_g × accel_factor` |
| `crew` | `round(base.crew × crew_factor)` |
| `sensors` | `base.sensors + sensors_add`（去重） |
| `weapons` | `base.weapons + weapons_add`（去重） |
| `hull_code` | `base.hull_code + "-" + hull_suffix` |
| `stats_derived` | 记录推算后的 mass/dv/accel/crew |

- 展开记录带 `derived=true`、`derived_from=base`、`variant_of/base_class_id`、
  `derivation.modifiers`、`truth=false`；无 TBD。
- ORBFLT 6 个 base 的数值为 **proposal 工程基线**（不是官方定案），因此亚种推算
  不再 TBD；33OSID 基础级数值仍是数据缺口（见 §4 审计）。
- 变体 `name/role/refit/operator` 为提案；不覆盖 docs/16、46 的正式命名规则。

## 3　CA-4471 batch 语义

`known_ships[0]`：

```json
{"ship_id":"CA-4471","name":"湮没者","name_en":"ANNIHILATOR",
 "hull_code":"CA-4471","batch":null,
 "batch_source":"未编入融合航迹表；舷号 CA-4471 是舰队登记号，不等于融合批号（2000–2999）"}
```

- `batch=null`（unassigned），不是 `"TBD"`；`by_batch("TBD")` 不命中它。
- `batch_source` 明确：舷号/类型代码 ≠ 融合批号。AV-4412 的 `batch=2001` 保留，
  并同样带 `batch_source`：2001 是融合航迹批号（2000–2999 敌对段），与舷号 AV-4412 分离。
- 33OSID 类型代码（BB/CA/CL/DD/FF/AV）是身份前缀，不是融合批号；`hull_code` 唯一性
  按 class 记录，known ship hull（如 CA-4471）单独校验。

## 4　33OSID 审计

`enemy.audit` 内嵌审计元数据；文档记录如下。

| 检查项 | 结果 / 处理 |
| --- | --- |
| 33OSID 类目 | 18 = 6 base + 每 base 2 亚种；`class_id/hull/name` 全局唯一 |
| known_ships | 2：AV-4412（batch 2001，有效）、CA-4471（batch null，已修正） |
| CA-4471 batch | 原 `"TBD"` → `null`；加 `batch_source`；`by_batch` 不命中 |
| AV-4412 batch | 2001 保留；是融合批号，不是舷号；加 `batch_source` |
| base 数值 | displacement/dv/accel/crew 仍为 `"TBD"`（数据缺口；本阶段不伪造官方数值） |
| 传感器/武器 | 仍为 `"TBD"`；不在本阶段补官方配置 |
| name_pool | 三语域（agent/immovable/authority）保留；具体舰名/日文写法待内容阶段 |
| hull_code | BB/CA/CL/DD/FF/AV 是类型代码；非融合批号、非舰体编号 |
| 独立变体 | 12 个独立 class（`variant_of` 指向母级），数量 2/base，符合 2–4 要求 |
| audit 元数据 | `enemy.audit` 缺失时校验失败；findings 逐条记录 |

其他潜在问题（未在本阶段修改，仅记录）：33OSID 6 个 base 的数值与传感器/武器仍 TBD；
`name_pool` 是候选名而非正式舰名；`GHOST TRACK` 试验群不在公开目录内（docs/04 §9.5）。

## 5　ShipCatalog API（5E 增量）

| API | 说明 |
| --- | --- |
| `classes(faction)` | 只返回 base/独立 class；UEOF 为 `[]` |
| `variants_of(query="")` | base id → fleet+operator variants；operator/faction → 对应变体；空串 → 全部 18；未知 `[]` |
| `resolve_variant(id/name)` | `{ok,kind:"variant",variant,variant_id,base_class_id,operator}`；未知 `unknown_variant` |
| `resolve(query)` | 增加 variant 解析（`kind:"variant"`） |
| `class_of(variant_id)` | 展开回 base class |
| `summary()` | `classes=32, variants=18, operator_variants{...}, fleet_variants=6, ueof_*_classes=0, ueof_*_variants=6` 等 |
| `check_contracts()` | 6 ORBFLT base、UEOF 无独立 class、7th/3rd 各 6 变体、33OSID 18、变体数值已推算、CA batch 语义 |
| `known_ship/by_batch` | CA batch null 不命中 TBD；AV 2001 命中 |
| `to_dict/to_json` | 原始 content + summary；展开变体由 API 返回 |

校验新增：
- UEOF 独立 class（faction=ueof_7th/3rd）→ 拒绝；
- ORBFLT base 数值 TBD → 拒绝；
- `operator_variants` 数量 2–3、必须覆盖 7th/3rd；`fleet_variants` ≥1；
- `variant_id` 全局唯一、`derive_from` 指向 base、`modifiers` 对象、proposal true；
- CA-4471 `batch` 非 null → 拒绝；`batch_source` 缺失 → 拒绝；
- `enemy.audit` 缺失 → 拒绝；
- 变体 name/hull 唯一性。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/ship_catalog_probe.gd
# V17 SHIP CATALOG PROBE RESULT: PASS=981 FAIL=0（exit 0，只跑一次）
```

覆盖：base 32/variant 18、友军 8 保持、33OSID 18/6 base/每 base 2 亚种/
CA-4471 batch null + batch_source/AV 2001/audit findings；ORBFLT 6 base 数值非 TBD、
每 base operator 2（覆盖 7th/3rd）+ fleet 1、变体总数 18、UEOF 独立 class 0；
18 个变体逐个 base×倍率自动推算 mass/dv/accel/crew、sensors/weapons 合并、
stats_derived、无 TBD、derived/truth=false；variants_of/resolve_variant/class_of/
resolve/name_pool/summary/to_json；variant_id 重复、derive_from 错误、operator 覆盖不足、
ORBFLT TBD、CA batch TBD、audit 缺失、UEOF 独立 class 均拒绝；两 catalog JSON/
summary/变体排序确定性。

## 7　边界

- 只做目录/共用舰级/亚种展开/自动推算/审计；不接 UI、战斗生成、实体绑定或 ShipState。
- 33OSID 数值/传感器/武器仍 TBD；ORBFLT 数值与变体为 proposal 工程基线，不宣称官方定案。
- 变体是同一 base 的 operator/fleet 改装，不是独立舰级；`classes()` 数量不含变体。
- 不改 docs/16、46 的正式编制/命名规则；不把融合批号与舷号/类型代码混用。
- 未跑其他 probe；未 commit。
