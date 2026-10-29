# JC-B01A 部署契约（D1 切片）

> 执行卡：#62（READY，A4 冻结 `af924d0`，main 开工 `4e75897`）
> 本文件先冻结「选择→校验→冻结部署→真实生成」的最小写者/读者/恢复合同，再据此写红例与实现。

## 1. 现状缺口（2026-10-29）

- `FleetFormation`：只写 `assignments`（ship_id→slot）与校验，不生成世界实体。
- `GameSession.fleet_assign/unassign/move/validate`：只改选择/发事件。
- `ShellBinder`：只有 FLEET `ASSIGN/UNASSIGN/MOVE/VALIDATE`，没有部署结果。
- `EntityCatalog`：由 `seed.entities` 静态注册；`PhysicsWorld` 在 `_setup_optional_components` 内按 `seed.entities`/`physics_world.entities` seed；`entity.spawn` 发布后才进入 `WorldState`。当前无法用编制选择替换名册。
- 结果：未选舰仍存在于 catalog/world/physics；两套编制无法产生可解释的实体/资源差异。

## 2. 写者/读者

| 数据 | 唯一写者 | 读者 |
|---|---|---|
| 选择（ship_id→slot） | `FleetFormation` | DeploymentService（只读快照） |
| 冻结配置 revision / deployment seed / 实例映射 | `DeploymentService`（原子提交） | Session boot、catalog、physics、world、UI |
| 每实例静态资源（质量/燃料→kg、初始弹药/损伤容器） | `DeploymentService` 冻结行 + 单舰运行态容器 | Session `deployment_*`、后续 B1b 火控账本 |
| 实体运动学 | 既有 `PhysicsWorld` | `WorldState`（spawn 后只读同步） |
| 选择/config snapshot 与运行态 | 两份独立结构，禁止共享可变 Dictionary/Array | 存档/恢复 |

## 3. boot 顺序（按现有真实顺序接线，不新增顺序）

1. `_normalize_seed` 后、创建 `EntityCatalog` **之前**：若 `seed.deployment` 存在，`DeploymentService` 用 seed 的 ship catalog 内容 + roster 校验选择；失败则 boot 失败（明确原因，不半生成）。
2. 成功：把冻结实例转为同源 `entities`（静态元数据）供 `EntityCatalog` 注册；`_seed.entities` 被部署实体替换，未选舰不在其中。
3. `_setup_optional_components` 内 `PhysicsWorld` seed：仅部署实例；质量/燃料 t→kg 只在此转换一次，坐标/速度/参考系/历元与 seed 同源；`physics_world.entities` 配置不得遗留旧全名册（部署态优先，缺失才 legacy）。
4. 随后既有 `entity.spawn` 发布并 `apply` 到 WorldState；不新增 boot 后 `upsert_physics_entity` 绕路。
5. 部署实例同步进入 `own_entity`（旗舰）、`fleet_instances`、`command_domains.authorized_actors` 映射；既有 sensor/owner/EW 链按实例 id 工作。
6. 生成实体 ≠ 生成已知敌航迹；编制 VALID ≠ 已出击；B1b 前其他本方舰战斗运行态明确不可用。

## 4. 冻结/幂等/生命周期

- `selection_revision`：由 scenario_id + 稳定排序的选舰/槽位/实例 id + 配置 revision 组成，重复提交同选择得到同一 revision 与同一实例 id 集合。
- 原子：全部合法才提交；任一失败不创建实体/资源/映射。
- 幂等：同 revision 重复 `deploy` 返回同一结果，不重复生成；不同选择在已部署后拒绝 `deployment_locked`（预部署阶段外锁定；不在交战中重 boot 抹损伤）。
- 稳定实例 ID：named hull 默认小写 hull id；自定义/通用舰体必须显式 `instance_id` 且全局唯一；`fleet_id`/`controller`/`owner` 分离。
- 资源：每实例独立容器（弹药/燃料/损伤/配置）；改一舰不改另一舰；质量 kg = 名册 t × 1000 仅一次；Δv 用 km/s。
- 恢复：选择、revision、实例映射、冻结资源分块保存；load 不再生成重复实体；部署前/后真实文件恢复同 t 映射、≥10 tick 运动/事件一致。
- 旧单舰 seed / 旧档：无 `seed.deployment` 时为 legacy，保持现有行为。

## 5. 入口与 UI（最小）

- Session：`fleet_deployment_plan(selection)`（只读校验）、`fleet_deploy(selection, opts)`（需 `confirm=true`；原子/幂等/锁）、`fleet_deployment_vm()`、`deployment_resources(instance_id)`。
- Binder：FLEET 增加 `DEPLOY_PLAN`/`DEPLOY`；最小确认→结果/拒绝原因，不扩全屏。
- 验收需最小非 headless 确认选择→部署可见；headless probe 不能替代可见入口。
- 生成部署不授予开火权，不改身份；B1b 前其他本方舰战斗运行态明确返回不可用。

## 6. 单位/容差

- 质量/燃料：t → kg ×1000（1e-9 整数级容差）；Δv：km/s。
- 时间：秒；坐标 km；帧/历元与 seed 同源。
- 资源比较：数值 1e-9；集合按 id 排序精确比较。

## 7. 红例计划（`integration.jc_deployment`）

- J0：合法 A/B 两套编制可 boot；revision/实例 id 稳定。
- J1：A/B 实体集合恰好等于选择；未选舰不在 catalog/world/physics/资源账本。
- J2：至少两实例资源独立（改 A 燃料/损伤 B 不变）；质量 t→kg 一次；传感器/owner 输入按实例 id。
- J3：负例（未知舰/未知舰级/重复 instance id/重复 named hull/槽位超限/越预算/无控制者/缺配置/非法坐标）全部原子拒绝且原因明确。
- J4：重复部署幂等；已部署后不同选择 `deployment_locked`；confirm 缺失拒绝。
- J5：部署前/后真实文件保存恢复；同 t 映射；继续 10 tick 运动/事件一致；无重复实体；旧单舰 seed 兼容。
- J6：UI/binder 合同与最小非 headless 证据（可见确认→结果）。
