# 完整游戏-阶段5B · RefitService（APSIS 干船坞改装）

> 任务 task-206。工程 `game_v17`。
> 新文件：`framework/content/refit_options.json`、`scripts/core/refit_service.gd`、
> `tests/refit_probe.gd`、本文件。
> 依赖已提交的 `ShipCatalog`（`ships_friendly.json`：APSIS=远地点级 001）。
> 不改其他；不接 UI/战斗/实体生成；未 commit。

## 1　平台基线

RefitService 从 ShipCatalog 读取 APSIS 舰级数据：

| 字段 | 基础值 | 来源 |
| --- | --- | --- |
| platform / class | APSIS / OCUVF-APOGEE 远地点级 | ShipCatalog |
| 质量 | 9000 t | docs/04 §7 |
| Δv | 3.15 km/s | docs/04 §7 |
| 最大加速度 | 0.02 g | docs/04 §7 |
| 编制 | 240 | docs/04 §7 |
| 基础发电 | 400 kW | 改装提案基线 |
| 维修坞 | 2 | 远地点级船坞舰 |

槽位（`base_slots`）：`hull 3 / sensor 3 / weapon 3 / defense 3 / utility 6 / dock 2` = **20**。
质量上限 12000 t；功率上限 1200 kW；Δv 下限 0.5 km/s；加速度下限 0.005 g。
默认资源：`credits=200000`、`materials=500`、`location=L4_ANVIL`。

## 2　模块内容（`refit_options.json`）

- schema `v17.refit_options.v1`；**30 个模块**（要求 ≥24），6 类：

| category | 数量 | 模块示例 |
| --- | --- | --- |
| hull | 4 | 轻/重型装甲包、舰体加强筋、烧蚀外层 |
| sensor | 5 | 雷达 Mk2、光学/IR、ELINT、火控雷达、桅杆延长 |
| weapon | 6 | 轨道炮 Mk2、48 单元导弹舱、近防升级、干扰吊舱、诱饵、重型脊炮 |
| defense | 4 | 点防御炮组、装甲带、信号抑制器、综合对抗套件 |
| utility | 7 | 反应堆升级、散热器、辅助燃料舱、货舱、维修无人机、指挥通信、隐身涂层 |
| dock | 4 | 维修坞、机加工车间、医院舱、指挥舰桥 |

每模块字段：
`module_id/name/name_en/category/slots/mass_t/power_kw/dv_penalty_kmps/
accel_penalty_g/crew/cost_credits/cost_materials/cost_days/availability/
location_tags/effects/conflicts/requires/proposal/source/note`。

- `power_kw`：正数为耗电，负数为发电（反应堆 `-150` 表示发电 150 kW）。
- `location_tags`：`"*"` 表示任意地点；否则必须在当前 `location` 中。
- `conflicts`/`requires`：模块 id 引用，必须存在；提交时检查双向冲突与依赖集合。
- 内容全部 `proposal:true`；成本/效果为游戏化提案，不宣称官方数值。

## 3　约束与派生

| 约束 | 行为 |
| --- | --- |
| 槽位 | `used + planned + new` 不得超过该 category base |
| 质量 | `base 9000 + Σ mass_t ≤ max_mass_t(12000)` |
| 功率 | `Σ 正 power_kw ≤ base_power + Σ 发电；headroom <0` 拒绝 |
| Δv | `base 3.15 − Σ dv_penalty + effects.dv_bonus ≥ min_dv` |
| 加速度 | `base 0.02 − Σ accel_penalty ≥ min_accel` |
| 成本 | 计划集合总 `credits/materials` 不超过资源 |
| 地点 | `location_tags` 含 `location` 或 `"*"` |
| 冲突 | `conflicts` 与已安装/已计划模块双向检查 |
| 依赖 | `requires` 必须在已安装/已计划集合内 |
| 等级/可用性 | `availability` 为 `unavailable/locked/TBD` 拒绝 |

派生 stats：
- `mass_t = base + Σ installed mass`
- `dv_kmps = max(min_dv, base − Σ dv_penalty + effects.dv_bonus)`
- `accel_g = max(min_accel, base − Σ accel_penalty)`
- `crew = base + Σ crew`
- `power_generation_kw = base + Σ(-power_kw for power_kw<0)`
- `power_used_kw = Σ(max(0,power_kw))`；`headroom = generation − used`
- `effects` 为所有模块效果的加总（armor/sensor_range/point_defense 等）。

## 4　事务流程

```text
install(id)          → planned（不扣资源、不改 current stats；槽位按 planned 预留）
commit()             → 重新整体校验；扣 credits/materials；planned → queue（含 cost_days）
tick(days)           → 减少 queue 剩余天数；到期模块进入 installed，重算 stats
remove(id)           → 取消 planned / 移除 installed / 取消 queue（受依赖保护）
install_now(id)      → install + commit（仍须 tick 完成，stats.current 不立即变）
```

- **非法原子拒绝**：槽位/质量/功率/Δv/加速度/成本/地点/冲突/依赖/重复/未知均返回
  `{ok:false, reason}`，状态不变。
- `commit()` 是整体事务：任一 planned 模块不满足则全部不提交。
- 安装完成前 `current` 不变；`projected` 包含 planned 的预测结果。
- 拆下被依赖模块（如 `utility_command` 被 `dock_command_bridge` requires）拒绝。

## 5　API

| API | 说明 |
| --- | --- |
| `RefitService.new(catalog, options, resources)` / `setup(...)` | catalog 为 ShipCatalog（缺省自动加载）；options 为路径/对象（缺省 content）；resources `{credits,materials,location}` |
| `slots()` | base/used/planned/reserved/free/projected_free/total_* |
| `options(category)` | 30 模块（可按 6 类过滤） |
| `module(id)` | 单模块 |
| `quote(module/id)` | 成本/槽位/资源剩余/安装后 stats（不落状态） |
| `can_install(module/id)` | 完整约束检查 + reason + stats_after |
| `install(module/id, opts={immediate:false})` | 加入 planned；`immediate=true` 同时 commit |
| `install_now(id)` | install + commit |
| `remove(id)` | planned/installed/queue 移除（依赖保护） |
| `commit()` | 扣资源进入 queue；失败不改状态 |
| `tick(days)` | 推进队列，返回 completed/queue/installed/stats |
| `queue()` | 等待 tick 的作业（queue jobs） |
| `stats()` | base/current/projected/effects/slots/resources/t_days + 顶层 current 字段 |
| `summary()/to_dict()/check_contracts()` | 摘要/全量/不变量 |
| `save()` / `save_state()` / `save_json()` | 存档（schema `v17.refit_save.v1`） |
| `load_state(data)` | 从 dict/JSON 恢复；失败原子。因 GDScript 全局 `load()` 冲突，无 `load()` 方法 |
| `reset()` | 清空 installed/planned/queue，恢复初始资源与 t=0 |

失败 reason：`not_ready`、`unknown_module`、`already_installed_or_planned`、
`already_in_queue`、`unavailable`、`wrong_location`、`conflict`、
`missing_requirement`、`no_slot`、`mass_limit`、`power_limit`、`dv_floor`、
`accel_floor`、`insufficient_credits`、`insufficient_materials`、`invalid_days`、
`not_installed`、`required_by_installed` 等。

## 6　存档

`schema=v17.refit_save.v1`，字段：
`platform/location/t_days/resources/installed[]/planned[]/queue[]`。
load 校验模块存在、无重复、resources 数字；非法原子拒绝。旧档缺 inst/planned/queue
按空处理；版本不符拒绝。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/refit_probe.gd
# V17 REFIT PROBE RESULT: PASS=977 FAIL=0（exit 0，只跑一次）
```

覆盖：setup/APSIS 基础 stats；30 模块字段/类别/成本/quote；槽位/质量/功率/成本/
地点/冲突/依赖/availability；install/planned→commit 扣资源→queue→tick→stats；
remove planned/installed/queue 与依赖保护；save/load(dict/JSON)/非法/版本/reset；
多计划/长流程/同操作确定性/contracts/JSON。

## 8　边界

- 只做改装选项/事务/派生 stats 与存档；不接 UI 干船坞界面、不写 world/TrackTable/V15、
  不生成/绑定实体、不触发战斗或任务。
- 模块数值/成本/效果为提案；APSIS 基础数值来自 docs/04；未定官方改装包/价格保持提案。
- 2 个维修坞是 APSIS 平台基线；dock 类模块为增设/升级提案，不改变 ShipCatalog。
- 不处理货币/材料库存的来源、市场或时间日历；`resources` 由调用方注入。
- 未跑其他 probe；未 commit。
