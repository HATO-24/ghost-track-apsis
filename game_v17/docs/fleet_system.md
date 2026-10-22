# 完整游戏-阶段5F · 全舰队改装 + 舰队编制

> 任务 task-215。工程 `game_v17`。
> 新增：`scripts/core/fleet_refit_service.gd`、`scripts/core/fleet_formation.gd`、
> `tests/fleet_probe.gd`、`docs/fleet_system.md`、`framework/content/fleet_roster.json`。
> 依赖已提交 ShipCatalog（友军 8 型/known ships）与 RefitService（APSIS 30 模块）。
> 不改其他、不写 world/TrackTable/UI、不生成实体；未 commit。

## 1　名册 `fleet_roster.json`

schema `v17.fleet_roster.v1`；全部 `proposal:true`。

- **13 艘** = 现有 5 艘 + 每友军型 1 艘预备舰：

| 舰只 | 舷号 | 舰级 | 状态 | 编队角色 |
| --- | --- | --- | --- | --- |
| APSIS | 001 | OCUVF-APOGEE 远地点级 | active | command/logistics |
| PERIGEE | 002 | OCUVF-APOGEE | reserve | command/logistics |
| HARMATTAN | 114 | OCUVF-PALLET-5C 托盘-5改 | active | screen/relay |
| LEE SHORE | 115 | OCUVF-PALLET-5C | reserve | screen/relay |
| FERRY | 201 | OCUVF-HEMATITE-6C 赤铁-6改 | active | gun |
| ANVIL | 202 | OCUVF-HEMATITE-6C | reserve | gun |
| VESUVIUS | 301 | OCUVF-GANTRY-3M 龙门-3M | reserve | missile |
| DEEPWELL | 401 | OCUVF-MOONPORT-4 月港-4 | active | logistics |
| SPRINGHEAD | 402 | OCUVF-MOONPORT-4 | reserve | logistics |
| WATCHTOWER | 501 | OCUVF-SAFEHARBOR-1 安海-1 | active | relay |
| BEACON | 502 | OCUVF-SAFEHARBOR-1 | reserve | relay |
| BOLLARD | 601 | OCUVF-WINCH-2 绞盘-2 | reserve | tug |
| MISSIVE | 701 | OCUVF-ARIA-1 咏叹-1 | reserve | shuttle |

每艘字段：`ship_id/name/name_en/hull_code/class_id/role/status/assigned_slot/
refit_state/formation_roles/fuel_t/repair_slots_required/proposal`。
`refit_state` 初始为空对象；FleetRefitService 运行时用独立 RefitService 快照维护。

### 1.1　编队槽位

| slot | cap | 必需 | 兼容角色 |
| --- | --- | --- | --- |
| command | 1 | **是** | command |
| screen | 4 | 否 | screen |
| gun | 3 | 否 | gun |
| missile | 2 | 否 | missile |
| logistics | 3 | 否 | logistics |
| relay | 2 | 否 | relay |
| tug | 2 | 否 | tug |
| shuttle | 2 | 否 | shuttle |

### 1.2　编队上限（提案）

`max_ships=13`、`max_mass_t=35000`、`min_total_dv_kmps=5`、`max_total_dv_kmps=120`、
`max_crew=1200`、`fuel_capacity_t=22000`、`repair_dock_capacity=4`。

初始编制：APSIS→command、HARMATTAN→screen、FERRY→gun、DEEPWELL→logistics、
WATCHTOWER→relay（5 艘，validate 通过）。

### 1.3　按舰级改装 policy

`class_refit_policies` 每型定义 `allowed_categories/slots/power_kw/max_mass_t/
max_power_kw/dock_bays`：

| 舰级 | 允许类别 | 槽位 hull/sensor/weapon/defense/utility/dock |
| --- | --- | --- |
| OCUVF-APOGEE | hull,sensor,defense,utility,dock | 3/3/3/3/6/2 |
| OCUVF-PALLET-5C | hull,sensor,defense,utility | 1/4/1/2/3/0 |
| OCUVF-HEMATITE-6C | hull,sensor,weapon,defense,utility | 2/1/3/2/3/0 |
| OCUVF-GANTRY-3M | hull,weapon,defense,utility | 2/0/3/2/3/0 |
| OCUVF-MOONPORT-4 | hull,defense,utility | 2/1/0/2/4/0 |
| OCUVF-SAFEHARBOR-1 | hull,sensor,defense,utility | 1/3/0/2/3/0 |
| OCUVF-WINCH-2 | hull,defense,utility | 2/1/0/1/3/0 |
| OCUVF-ARIA-1 | defense,utility | 0/0/0/1/2/0 |

## 2　FleetRefitService

- 为每艘友舰创建**独立 RefitService 实例**（独立 planned/queue/installed），复用
  APSIS 30 模块内容；setup 后按 roster 覆盖该舰 `base_stats/base_slots/power/dock_bays`
  与模块类别可用性（`platform 参数化`）。
- **共享资源**：`credits/materials/location` 由 FleetRefitService 持有；install 计划不扣，
  commit 时才按该舰成本扣共享资源；各舰独立 stats/queue。
- 角色/模块可用性：`options(ship_id, category)` 只返回该型允许类别；
  `quote/install/remove` 对禁用模块返回 `module_not_available_for_class`。
- 共享资源不足时 commit 原子失败，已安装舰不受影响。

API：

| API | 说明 |
| --- | --- |
| `select_ship(ship_id)` / `selected()` | 选择当前舰 |
| `ships_list()/roster_view()` | 名册 + 每舰 refit 状态 |
| `options(ship_id="", category="")` | 该舰可用模块（按 policy 过滤） |
| `quote(ship/module)` | 支持 `quote(module)`（选中舰）或 `quote(ship_id,module)` |
| `can_install/install/remove` | 同上两种参数形式；禁用模块拒绝 |
| `commit(ship_id="")` / `commit_all()` | 单舰/逐舰提交；共享资源扣除 |
| `tick(days)` | 全部舰只推进改装队列 |
| `stats(ship_id="")` / `ship_stats/all_stats()` | 单舰 current/projected/queue/resources |
| `refit_state(ship_id)` | 该舰 RefitService 快照 |
| `summary/check_contracts/to_dict` | 舰队级摘要/不变量 |
| `save_state/save_json/save` | schema `v17.fleet_refit_save.v1` |
| `load_state(dict/JSON)` | 逐舰恢复；失败回滚；未知舰/版本拒绝 |
| `reset()` | 各舰清空 + 共享资源恢复初始 |

## 3　FleetFormationService

- 自由 `assign/add`、`unassign/remove`、`move` 舰只到槽位；初始来自 roster 的
  `assigned_slot`。
- 校验：
  - 必需槽位 `command` 至少 1（cap1）；
  - 每槽 cap；
  - 角色兼容（`formation_roles ∩ slot.roles`）；
  - 重复分配（assign 已分配 → `already_assigned`，用 move 改位）；
  - 总舰数 / 总 mass / 总 Δv（下限与上限）/ 总 crew；
  - 燃料容量、维修坞容量；
  - 未知舰/槽位。
- 原子：assign/move/load 不通过时不改当前编制；`validate()` 只报告不改。
- 可选 `link_refit(fleet_refit)`：编队统计使用改装后的 current mass/dv/crew，
  因此改装可能触发编队上限，`stats().refit_linked=true`。

API：`roster/slots/assign/unassign/move/validate/summary/stats/save/load/reset`；
别名 `add/remove`；`save_state` schema `v17.fleet_formation_save.v1`。

## 4　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/fleet_probe.gd
# V17 FLEET PROBE RESULT: PASS=511 FAIL=0（exit 0，只跑一次）
```

覆盖：roster 13/8 型/8 槽/8 policy/limits 字段；FleetRefit 13 独立服务、选中切换、
基础 stats/槽位/模块过滤（APSIS 24、MISSIVE 11）、Quote/Disallow、多舰计划/逐舰 commit/
共享资源扣除/tick 全部/独立 mass、非法原子、commit_all、save/load/字符串/非法/重置；
Formation 初始 5/19 槽、validate、自由 assign/move/unassign、重复/角色/槽满/command 必需、
mass/fuel/crew/dv/repair 约束、refit 链接 stats、存档/非法/回滚/reset；两服务确定性/contracts。

## 5　边界

- 只做名册/改装事务/编制状态；不接 UI、战斗、world/TrackTable/V15，不生成实体。
- 舰只/舷号/预备舰名、燃料/维修容量/编队上限均为提案；ShipCatalog 数值为准。
- RefitService 平台参数化为 wrapper 级覆盖，不改已提交 RefitService 文件。
- 编队不移动实体、不修改航迹；编队角色来自 roster，不是 ShipCatalog 的固定语义。
- 未跑其他 probe；未 commit。
