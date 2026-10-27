# JC-A01（#58）第四轮：T1/T2 验收测试强度收尾报告

> 最终代码 SHA `00cdc2976516febb0d8fa0f571568bea104edaa1`（分支 `jc/a01-authority-intel`，PR #66）；实现基线 main `3045311657609dfe10a133802b93dde2fc8abb79`（G0=K0=`9d0f3b4…`）
> 环境：Godot `4.7.2.stable.official.ed1daf0bf`，Windows；证据：`evidence/a01_r4/`

本轮只按复核 T1/T2 补**正式回归保护**与契约映射，不修改已 CLOSED 的服务实现（仅给隐藏真值诊断钩子补 PhysicsWorld 面记录，见下）。

## T1：已获证据目标必须有 contact（不得把掉行当允许未知）

### 旧断言 → 新契约

| 旧 | 新 |
|---|---|
| `binder.contacts` 非空即可；随后对缺失场景实体 `continue` | 从**可信本舰 owner 的已获证据**（`intel_view.tracks`）导出必须可见集合；逐个要求存在 `track_id` 匹配的 contact 行；未获证据对象仍允许缺席 |
| 只验证存在行 | 存在行继续执行真实安全显示断言（匿名 display、source=owner、无真值、内部引用保留） |

### 新断言（正式 probe）

- `a1_entity_metadata_authority`：`every acquired-evidence target has a contact row`（359/0）。
- `jc_authority_intel`：显式 `target_a` contact 行 + 归属 owner + 匿名显示（90/0）。

### 红灯对照（证明断言能抓回归）

`negctl_a1_missing_contact.gd.txt`：消费者快照中删掉一个已获证据目标的 contact 行
→ **FAIL** `every acquired-evidence target has a contact row (["harmattan"])`，退出 1。

## T2：隐藏移动必须作用于被比较的同一目标，并证明真的改变

### 旧断言 → 新契约

| 旧 | 新 |
|---|---|
| 观测/比较合成 `ws_target`，却变更 `harmattan`；不检查返回值/前后真值；`before_move` 未用 | 观测、变更、比较**同一真实目标 harmattan**；先断言 `truth_changed`、`world_changed`、`physics_changed`，且 physics 读数确为变更后坐标；无新观测时 HUD/plot 保持旧获准位置与采样时间；随后投递合法新观测，断言同一目标位置与采样时间确实更新 |

### 实现支持（诊断钩子）

`GameSession._apply_hidden_truth_mutation` 增加 PhysicsWorld 面基线/终值记录，返回
`world_changed` / `physics_changed`；`truth_changed = world_changed or physics_changed`。
该钩子仅用于验证与诊断，不被运行时业务路径调用。

### 红灯对照

`negctl_ws_noop_mutation.gd.txt`：把变更改成 no-op
→ **FAIL** `hidden mutation actually changed the compared target ({})` 与
`FAIL hidden mutation changed PhysicsWorld (just a world copy)`，退出 1。

## 结果（同一代码版本）

```
复核指定 5 项：5/5 PASS
  integration.jc_authority_intel            90/0
  integration.a1_entity_metadata_authority  359/0
  integration.a0_world_physics_sync         107/0
  integration.a0_integration_authority       65/0
  integration.a0_save_roundtrip_authority    41/0
Phase 0: 6/6 PASS      Phase A: 3/3 PASS
Full strict: 见 PR 正文/证据目录（预期 88 = 81 PASS / 7 历史 FAIL、new_fail=0、complete=true）
```

断言数变化原因：A01 76→90（显式 contact 行 + 同目标隐藏变更/新观测更新）；metadata 357→359
（已获证据目标 contact 行）；world-sync 100→107（同目标对照 + physics 面 + 采样时间 + 新观测更新）。
均为等强度或更强，未删/放宽既有负例，未动 7 项历史 baseline，未移出 matrix。

## 未做 / NOT RUN

- 未改授权、owner 老化、共享/读档、光学显示的实现；未新增 AI/EW/逐舰账本。
- Linux/macOS、真实渲染/人工可读性、真实 RF/光学物理、>1000 tick：NOT RUN。
- UI-01..04 运行时仍按 61 号队列等待 A1。
