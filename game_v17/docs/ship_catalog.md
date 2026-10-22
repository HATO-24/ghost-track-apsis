# 完整游戏-阶段5A · ShipCatalog 友军/敌军舰船目录

> 任务 task-204。工程 `game_v17`。
> 新文件：`framework/content/ships_friendly.json`、`framework/content/ships_enemy.json`、
> `scripts/core/ship_catalog.gd`、`tests/ship_catalog_probe.gd`、本文件。
> 不改其他；不接 UI/战斗/实体生成；未 commit。

## 1　依据与口径

| 来源 | 用途 |
| --- | --- |
| `docs/04_舰船设定.md` §7/§12.6/§12.8 | 友军 8 型原型/吨位/Δv/加速度/编制；命名池；APSIS=001、HARMATTAN=114 |
| `docs/16_舰级与识别.md` §3–4 | 33OSID 6 级/类型代码/AV-4412/CA-4471/批号规则 |
| `docs/46_势力与军队编制.md` §9.3–9.4 | UEOF 第7/第三远征舰队；ORBFLT 舰级提案（Polaris/Sentinel/Gatekeeper/Forge/Tractor/Beacon） |

**所有内容标 `proposal:true`**；docs 未给出的数值/名称写显式 `"TBD"`，不伪造官方定案。
`04` 的数值只作为工程基线复制；`16/46` 未给数值的敌军舰级保持 TBD。

## 2　内容文件

### 2.1 `ships_friendly.json`（schema `v17.ships_friendly.v1`）

- `faction=ocuvf_id13`；`units`；`hull_ranges`；`name_pools`；`entity_bindings`；`classes[8]`。
- 8 型、role 与舷号段：

| class_id | 名称 | role | 舷号段 | 干重/Δv/加速度/编制（docs/04 §7） |
| --- | --- | --- | --- | --- |
| OCUVF-APOGEE | 远地点级 | depot | 001–099 | 9000 t / 3.15 km/s / 0.02 g / 240（APSIS 001） |
| OCUVF-PALLET-5C | 托盘-5 改 | picket | 100–199 | 300 t / 2.54 / 0.15 / 12（HARMATTAN 114） |
| OCUVF-HEMATITE-6C | 赤铁-6 改 | gun | 200–299 | 1200 t / 3.15 / 0.10 / 68（FERRY 201 提案映射） |
| OCUVF-GANTRY-3M | 龙门-3M | missile | 300–399 | 900 t / 3.80 / 0.08 / 24 |
| OCUVF-MOONPORT-4 | 月港-4 | tanker | 400–499 | 2000 t / 10.63 / 0.01 / 18（DEEPWELL 401） |
| OCUVF-SAFEHARBOR-1 | 安海-1 | relay | 500–599 | 500 t / 1.97 / 0.12 / 30（WATCHTOWER 501） |
| OCUVF-WINCH-2 | 绞盘-2 | tug | 600–699 | 400 t / 3.15 / 0.20 / 9 |
| OCUVF-ARIA-1 | 咏叹-1 | shuttle | 700–799 | 20 t / 6.12 / 1.0 / 3 |

每型字段：`class_id/name/name_en/role/faction/model/hull_code_prefix/hull_range/
displacement_t/dv_kmps/accel_g/crew/sensors/weapons/armor/rcs/ir/dimensions_m/
sections/known_ships/name_pool/proposal/tbd/source/note`。
`armor/rcs/ir/dimensions_m` 文档未定，保持 `"TBD"`。
`name_pools` 按 role 复用 docs/04 §12.8（depot 轨道要素、picket 天气、gun 地形、
missile 火山、tanker 地下水、relay 灯塔、tug 系泊、shuttle 信件）。
`entity_bindings`：`apsis→APSIS`、`harmattan→HARMATTAN`、`ferry→FERRY`、
`watchtower→WATCHTOWER`、`deepwell→DEEPWELL`。

### 2.2 `ships_enemy.json`（schema `v17.ships_enemy.v1`）

- `faction` 取值：`33osid` / `uegaf_orbflt` / `ueof_7th` / `ueof_3rd`。
- 总数 **28 型**：
  - 33OSID **6 级 + 每级 2 个改装包（标准/强袭；提案）** = 18；
  - UEGAF-ORBFLT **6 级**（北极星/哨兵/关卡/工坊/牵引/信标）；
  - UEOF 第7舰队 **2 级**、第三远征舰队 **2 级**（名称/数值 TBD）。
- 33OSID 6 级：清算级 BB / 执刑级 CA / 禁制级 CL / 追索级 DD /
  征用级 FF / 传唤级 AV；亚种 `variant_of` 指向母级。
- 已知船（`known_ships`）：`AV-4412 传唤者`（传唤级，batch 2001）、
  `CA-4471 湮没者`（执刑级）；`entity_bindings av_4412→AV-4412`。
- 每型字段：`class_id/faction/name/name_en/role/hull_code/variant_of/naming_scheme/
  displacement_t/dv_kmps/accel_g/crew/sensors/weapons/armor/signature/dimensions_m/
  sections/known_ships/name_pool/proposal/tbd/source/note`；未定数值显式 `"TBD"`。
- 命名：
  - 33OSID 三语域 `name_pools.agent/immovable/authority`
    （施事者/不可动摇/权威；取自 docs/04 §12.8 的 Reclaimers 名，仍标提案）；
  - ORBFLT 用 `naming_scheme=orbflt_numbered`、UEOF 用
    `ueof_formation_numbered`，具体舰名 TBD（不下发虚构名）。

## 3　ShipCatalog API

```gdscript
var cat = ShipCatalog.new()          # 默认加载两份 content
cat.ready / cat.errors
cat.load_catalog()                   # 重新加载；GDScript 全局 load() 冲突，故不用 load()
cat.reload()
cat.validate()                       # 校验当前内容（不改状态）
cat.validate({"friendly": f, "enemy": e})  # 校验候选
cat.classes(faction := "")           # 型号数组（按 class_id 排序）
cat.class_of(query)                  # class_id / 舰名 / 型号 / 已知 ship / hull → class
cat.ships(faction := "")             # 已知船（known_ships）
cat.name_pool(class_id_or_domain)    # 命名池（class/role/domain）
cat.resolve(query)                   # {ok,kind,class/ship,class_id}；未知 not_found
cat.known_ship(query)                # ship_id/hull/name/batch → 已知船；未知 {}
cat.by_batch(batch)                  # 批号 → 已知船；未知 {}
cat.entity_binding(entity_id)        # 实体绑定 → {ok,entity_id,ship_id,class_id,ship}
cat.summary() / cat.to_dict() / cat.to_json()
cat.check_contracts()                # {ok,violations}
```

- 校验：两份 schema/`proposal`；友军严格 8 型；33OSID ≥6 母级且每母级 2–4 亚种；
  ORBFLT ≥4；UEOF 7th/3rd 各 ≥2；必填字段；数值字段必须数字或 `"TBD"`；
  class_id/class name/hull/known ship 全局唯一（`"TBD"` 名称跳过唯一性比较）。
- 加载失败**不改**已加载目录；未知查询统一返回空/`not_found`，不抛异常。
- 只读目录：不写 world/UI/combat/V15，不生成/绑定实体。

## 4　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/ship_catalog_probe.gd
# V17 SHIP CATALOG PROBE RESULT: PASS=1341 FAIL=0（exit 0，只跑一次）
```

覆盖：加载/数量（8/18/28/36、faction、TBD）；友军 8 型字段/role/docs 数值/
APSIS 001/HARMATTAN 114/舷号段/entity_binding；33OSID 6 母级+每级 2 亚种/
AV-4412/CA-4471/三语域；ORBFLT 6 级/UEOF 各 2 级/编制命名；Catalog API
class_of/resolve/known_ship/by_batch/name_pool/ships/summary/to_json；唯一性与
schema/数量/proposal/数值/TBD 校验；坏路径/坏内容/失败原子/确定性/排序。

## 5　边界

- 目录是**内容提案层**：不接 UI 舰船库/战斗生成/实体绑定系统；不修改 world/ShipState。
- 友军数值只来自 docs/04 §7；缺失装甲/RCS/IR/尺寸等保持 TBD。
- 敌军数值/亚种/ORBFLT/UEOF 型号为提案骨架，docs 未定处 TBD；不改写 docs/16、46 的
  正式舰级/命名规则；不宣称官方定案。
- 命名池只提供候选名；实际舰名/舷号由登记处/剧情层决定；GHOST TRACK 鸟类代号不在
  本目录公开舰名系统内。
- 未跑全量回归；未 commit。
