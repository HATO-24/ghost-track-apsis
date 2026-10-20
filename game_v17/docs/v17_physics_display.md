# R6-DISPLAY-CORE-1 · 物理显示数据接口（state 只读，供 plot 用）

> 任务 R6-DISPLAY-CORE-1（task-78）。工程 `game_v17`。
> 只改 `scripts/state.gd`、`tests/`、`docs/`；**不改 bridge/plot/hud/main/project**。
> 数据源：`framework_bridge.physics_authoritative_view()`（R6-AUTH-1）。
> 本文件说明 state 接口、字段、V15 track ↔ 物理实体映射、plot 下一步消费方式与边界。

## 1　定位

- 在 **state** 上增加**物理显示数据接口**：把 authoritative 物理的相对板坐标
  （own 为原点）整理成 plot 可直接读取的只读数据；**不写 V15 tracks、不切换显示层**。
- 仅 **当前时刻**，不用于历史回放/预测；`display_switched=false` 保持。
- 显示开关解耦：物理可用（authoritative ready）≠ 显示启用；可用 `DSH_PHYSICS_DISPLAY=0|1`
  覆盖（0 关，1 显式开；默认开）。
- 无对应物理实体的 V15 track 放入 `missing`，**不伪造**坐标。

## 2　环境与启用逻辑

| 条件 | `physics_display_available()` | `physics_display_enabled()` |
| --- | --- | --- |
| `V17_PHYSICS=authoritative` 且 `physics_ready` 且 view.ready | true | true（默认） |
| 同上 + `DSH_PHYSICS_DISPLAY=0` | true | false |
| 同上 + `DSH_PHYSICS_DISPLAY=1` | true | true |
| `V17_PHYSICS=shadow` / `off` / 物理未 ready | false | false |

`DSH_PHYSICS_DISPLAY=1` 不能凭空在 shadow/off 下产生数据（仍要求 available）。

## 3　API（全部只读；不改 V15/桥）

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `physics_display_available()` | bool | authoritative 物理是否就绪（与开关无关） |
| `physics_display_enabled()` | bool | available + `DSH_PHYSICS_DISPLAY` 覆盖（默认开） |
| `physics_display_status()` | Dictionary | `{schema,available,enabled,override,mode,requested_mode,display_switched,reason}` |
| `physics_display_frame()` | Dictionary | 当前时刻完整帧（未启用/未就绪返回 `{}`，见 §4） |
| `physics_display_board_for(id)` | Array[3] | 相对板坐标 km；支持 V15 track id/批号/entity id；无对应返回 `[]` |
| `physics_display_velocity_for(id)` | Array[3] | 相对板速度 km/s；同上 |
| `physics_display_entry_for(id)` | Dictionary | 完整条目（track_id/batch/entity_id/role/board_r/board_v/range/bearing/elevation/...）；无对应 `{}` |
| `fw_physics_display` | Dictionary | 每帧 `fw_sync` 刷新的显示帧；`DSH_PHYSICS_DISPLAY=0` 时为空 |
| `fw_bridge_state()` | Dictionary | 增 `physics_display` 字段 |

## 4　`physics_display_frame()` 结构（JSON 可序列化）

```
{
  "schema":"v17_physics_display.v1",
  "available":true,"enabled":true,
  "mode":"authoritative","requested_mode":"authoritative",
  "display_switched":false,
  "source":"cr3bp_rk4_circular · 实体初始 V2 L1 局部近似/固定占位（非 JPL 星历）",
  "frame":{"inertial":"earth_eci","rotating":"earth_rot","board":"earth_rot 相对本舰（+x/+y 面内、+z 法向）"},
  "tau":<V15 tau>,"physics_t":<shadow/authoritative 秒>,"delta_t_s":<tau-physics_t>,
  "replay_ok":false,
  "note":"只读当前时刻；不用于历史回放/预测；V15 位置源/plot 尚未切换。",
  "mapping_note":"entries 以 V15 track id（批号）为键；entity_id 由 bridge contacts/entities.batch 映射；无对应列入 missing，不伪造。",
  "own":{ track_id:"1001", batch:"1001", entity_id:"harmattan", role:"own",
          board_r:[0,0,0], board_v:[0,0,0], range_km:0, bearing_deg:0, elevation_deg:0,
          age_s:0, source:"...", filled:true },
  "flagship":{ track_id:"1000", entity_id:"apsis", role:"flagship", board_r/board_v/... },
  "entries":{"1000":{...flagship...},"1001":{...own...},"2001":{...target...},...},
  "missing":["9002",...],
  "warnings":[...]
}
```

- 每条 entry（own/flagship/target 统一）：`track_id/batch/entity_id/role/board_r/board_v/
  range_km/bearing_deg/elevation_deg/range_rate_kmps/closing_kmps/age_s/source/filled`。
- 坐标系与 R6-AUTH-1 一致：`board_r = earth_rot(target) − earth_rot(own)`（km）；
  `bearing=atan2(x,y)`、`elevation=atan2(z,horiz)`（与 V15 `_derive` 同式）。
- `age_s`：physics 当前步采样（0）；`physics_t` 与 V15 `tau` 可能不同步（`delta_t_s` 明示）。

## 5　V15 track id ↔ 物理实体映射（当前第一关）

| V15 track（批号） | 物理 entity | role | 说明 |
| --- | --- | --- | --- |
| `1000` | `apsis` | flagship | 远地点（旗舰） |
| `1001` | `harmattan` | own | 哈马丹（本舰，board 恒 0） |
| `1002` | `ferry` | target | 渡口 |
| `1003` | `watchtower` | target | 望楼 |
| `1004` | `deepwell` | target | 深井 |
| `2001` | `summons_4471` | target | AV-4412 传唤者 |
| `9001` | `ceres_2` | target | 谷神-2 |
| `9002` | （无实体） | — | 虚警/残骸回波 → `missing` |
| `0100`/`0101` | 站体/储罐 | — | 物理 authoritative 视图当前只列 ships → `missing`（不伪造） |

映射实现：state 先查 V15 track 的 `entity_id/batch`，再查 `fw_contacts`（bridge 归一接触）
的 `track_id/batch → entity_id`，最后查 `framework.world.entities` 的 `batch/id`；
均找不到 → `missing`。plot 只需用 V15 track id 调 `physics_display_board_for(track_id)`。

## 6　plot 下一步消费建议（本任务不改 plot）

```gdscript
# plot._draw_contacts() 内（示意；不要写 V15 tracks）：
if state.physics_display_enabled():
    for tr in state.tracks:
        var tid := String(tr.get("id", ""))
        var board: Array = state.physics_display_board_for(tid)   # km，own 原点
        if board.is_empty():
            continue                     # 缺失不伪造；继续用 V15 位置
        var p := _scene(Vector3(board[0], board[1], board[2]))   # 或就地叠加 overlay
        draw_marker(p, "PHYS")           # 建议用不同样式/角标区分
    # 可选：在 HUD/日志显示 state.physics_display_status()
```

- 历史/预测弧线继续用 V15 `board_pos`（物理接口仅当前时刻，`replay_ok=false`）；
  不要用物理帧插值历史。
- 建议先以 **overlay/对比层** 接入：V15 符号保留，物理位置用附加小标记/线，避免玩家误判
  显示已切换；切换为正式位置源属后续任务（需坐标系统一 + compare 门限）。
- 截图对比可用 `DSH_PHYSICS_DISPLAY=0` 关闭物理层。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/v17_physics_display_probe.gd
# V17 PHYSICS DISPLAY PROBE RESULT: PASS=137 FAIL=0（exit 0）
```

覆盖（8 节）：available/enabled（默认 + `DSH_PHYSICS_DISPLAY` 0/1 覆盖、available 与开关解耦）；
frame 字段/own=0/flagship=apsis 与 authoritative view 一致；targets（2001 range/bearing/board）与
`board_for/velocity_for/entry_for`；映射缺失（9002 等不伪造、未知返回空）；shadow/off 模式空且不崩溃；
`fw_sync` 刷新（physics_t 前进）且 **V15 tracks/等级/clock 不变**；JSON/status 可回读。

回归（同任务）：`v17_physics_authoritative_probe` 154/0、`v17_physics_shadow_probe` 277/0、
`v17_nav_integration_probe` 182/0、`v17_bridge_probe` 138/0、boot/main headless exit 0。

## 8　边界 / 未完成

- **只读、仅当前时刻**：不写 V15 tracks/HUD/plot、不做历史回放/预测；`display_switched=false`。
- 只在 `V17_PHYSICS=authoritative` 且 ready 时可用；shadow/off 下为空（不伪造）。
- 物理非 JPL 星历；实体初始状态为 V2 L1 局部近似/固定占位；float32（~0.03 km@38 万 km）。
- 站体/储罐当前不在 authoritative targets（ships-only）→ `missing`；后续如需站体显示，
  扩展 bridge authoritative 视图后再接。
- plot 尚未接线（本任务不改 plot）；切换为正式位置源需后续统一坐标系/门限。
- 未 commit。
