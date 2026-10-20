# R5-AUTHORITY-DISPLAY-1 · V2 传感器权威显示（可选路径）+ UNDOCK

> 任务 R5-AUTHORITY-DISPLAY-1（task-95）。工程 `game_v17`。
> 接入：`scripts/framework_bridge.gd`、`scripts/state.gd`（只读/显示层）。
> **这是“显示层权威”，不是完整 detection/fusion 切换**：bridge 不写 TrackTable/V15，
> 仅由 state 在 `fw_sync` 后把 V2 advisory contacts 映射到 V15 显示字段；默认 shadow 不写。
> 按任务要求只做最小 probe（PASS=74/0），未跑全量回归；未 commit。

## 1　模式（`V17_SENSOR_AUTHORITY`）

| 值 | bridge | state 行为 |
| --- | --- | --- |
| 未设/空 / `shadow`（默认） | 传感器模型 shadow（advisory 只读）；`sensor_authority_mode="shadow"` | 不写 V15；`fw_sensor_authority="legacy_v15"`；diff 空 |
| `authoritative` / `auth` / `v2`（显式） | 模型仍 shadow（`sensor_shadow_mode="shadow"`）；`sensor_authority_mode="authoritative"`；`sensor_authority_display()` active；bridge 不写 TrackTable | 每帧 `fw_sync` 后用 advisory contacts 映射 V15 显示字段；`fw_sensor_authority="v2_display"`；记录 `fw_sensor_authority_diff` |
| `off` | 不创建模型；`sensor_authority_mode="off"` | 不写；`fw_sensor_authority="off"`；diff 空 |

默认 shadow，authoritative 必须显式 env。切换可随时回退（不改变 V15 物理/任务状态）。

## 2　映射规则（state，仅显示字段）

- 匹配：advisory contact `batch`/`track_id`/`id` ↔ V15 track `id`/`batch`（按批号/实体关联；
  匹配失败或缺失 → **不写**，计入 `skipped_missing`）。
- 写入字段：
  - `level` ← advisory.level
  - `identity` ← advisory.identity（shadow 无 IFF/ELINT → 通常 `"unknown"`；空值不覆盖）
  - `sources` ← advisory.sources；并镜像 `sensor` = 首个 source（显示兼容）
- **绝不改**：`r/v/own/off/epoch/age`（位置/速度/本舰/偏置/时间）、`task/action/damage/threat/
  side/role`；每帧只改上述显示字段；bridge 不写任何轨道表。
- 每帧 diff：`{schema:"v17_sensor_authority_display_diff.v1", mode, applied, skipped_missing,
  changed, unchanged, advisory_count, rows[{track_id,batch,entity_id,before{level,identity,sources},
  after{...},changed}], display_fields:["level","identity","sources","sensor"],
  untouched_fields:[...], writes_track_table:false, note}`。
- 已映射后下一帧 `changed=0`（幂等），`applied` 仍为命中数。

## 3　bridge API

| API / 字段 | 说明 |
| --- | --- |
| `sensor_authority_requested_mode` | env 请求（shadow/authoritative/off） |
| `sensor_authority_mode` | 有效显示权威模式（shadow/authoritative/off） |
| `sensor_shadow_mode` | 模型有效模式（始终 shadow/off；authoritative 仅显示层） |
| `sensor_authority_display()` | `authoritative_display` 只读摘要：`schema=v17_sensor_authority_display.v1、mode/requested_mode/ready/active/display_only/authoritative_display_only/writes_track_table:false/writes_v15_physics:false/writes_v15_display_fields/advisory_count/display_fields/untouched_fields/note` |
| `sensor_shadow_view()` | 原 advisory VM（advisory_contacts 为映射源；只读） |
| `bridge_state()` | 增 `sensor_authority_mode/sensor_authority_display` |
| `docking_undock(reason)` | 调模型 `undock()`（无实例/未 docked 返回 ok=false+reason；docked 返回 VM） |

## 4　state API

| 字段 / 方法 | 说明 |
| --- | --- |
| `fw_sensor_authority` | `"legacy_v15"`（shadow）/`"v2_display"`（authoritative）/`"off"` |
| `fw_sensor_authority_diff` | 最近一帧映射 diff（只读） |
| `fw_sensor_authority_display()` | `{schema,authority,mode,diff,bridge}` 只读摘要 getter |
| `fw_docking_undock(reason)` | UNDOCK 包装（调 `framework.docking_undock`，刷新 `fw_docking`；无实例 ok=false） |
| `fw_bridge_state()` | 增 `sensor_authority`/`sensor_authority_diff` |
| 旧字段 | `fw_sensor_shadow/fw_sensor_compare/fw_docking/fw_optical_ir/...` 不变 |

## 5　验证（最小 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_sensor_authority_display_probe.gd
# V17 SENSOR AUTHORITY DISPLAY PROBE RESULT: PASS=74 FAIL=0（exit 0，只跑一次）
```

覆盖（6 节）：
1. 默认 shadow：不写 V15 显示字段，`fw_sensor_authority="legacy_v15"`，diff 空；
2. authoritative：`active=true`、不写 TrackTable、`fw_sensor_authority="v2_display"`；
   `applied=6/changed=6/skipped=1`，选中 track 的 `level/identity/sources` 与 advisory 一致，
   `r/v/threat/side/role` 不变；二次 `fw_sync` `changed=0`（幂等）；
3. 缺失不写：`skipped_missing=1`（9002 等），缺失 track 显示字段不变；全部 track `r/v` 不变；
4. off 回退：不写、diff 空、`authority="off"`、不崩溃；
5. UNDOCK：有实例返回模型结果（not_docked → ok=false+state），无实例 ok=false；
6. JSON：diff/authority display/fw_bridge_state 可回读。

## 6　边界 / 未完成

- **显示层权威，不是完整 detection/fusion 切换**：不改 V2 TrackTable、不改 V15 物理/任务/损管/
  威胁/位置；不做融合/识别决策；advisory identity 仍 shadow=unknown（无 IFF/ELINT）。
- 默认 shadow；authoritative 需显式 env；映射失败/缺失不写，不伪造。
- 显示字段映射以批号/实体匹配；未匹配 track 保持 V15 原值。
- UNDOCK 仅包装模型 `undock()`；docked 前调用返回 `ok=false,reason:"not_docked"`（模型语义），
  不落实体/不执行推力。
- 不接 HUD/plot；未跑全量回归；未 commit。
