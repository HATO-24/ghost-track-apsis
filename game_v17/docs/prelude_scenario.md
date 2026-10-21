# 完整游戏-阶段3S · PreludeScenario 序章专用场景内容

> 任务 task-168。工程 `game_v17`。
> 新文件：`scripts/core/prelude_scenario.gd`、`tests/prelude_scenario_probe.gd`、
> 本文件、`framework/content/scenario_prologue.json`。
> 不改其他；不写 world/UI/V15；未 commit。

## 1　定位

- 序章专用场景内容与引用校验层：把 Ceres-2/AV-4412/Chronos 等实体、应答机 profile、
  灯语码、触发、L1-05 facility 绑定组织成**可直接交给 GameSession 的 boot config**。
- 只读场景内容：`PreludeScenario` 不写 world/TrackTable/UI；GameSession 用其 boot config
  启动后由既有组件创建实体/服务。
- **Ceres-2 必须是独立实体/批次**（`ceres_2` / `CIV-CERES-2`），不得借 Harmattan 代替。

## 2　内容 schema（`scenario_prologue.json`）

```text
schema: v17.prelude_scenario.v1, version 1.0.0
title/source
refs: {
  facilities_content:  res://framework/content/facilities_system.json,
  transponders_content:res://framework/content/transponders_prologue.json,
  light_codes_content: res://framework/content/light_codes_l1.json
}
entities: [{
  id, name, batch, kind(ship/station/port/fuel/tank/otc/relay),
  side, identity, pos_km[3], vel_kmps[3],
  transponder_profile, light_capable, facility_id, note?
}]
transponder_profiles: [ ... 序章补充 profile（ferry/watchtower/deepwell/av_4412）... ]
light_codes: { schema:"light_codes.v1", defaults{...}, codes:[...] }
triggers: [{
  trigger_id, event, target_id, source_entity_id,
  condition{}, light_code, story_flag
}]
```

## 3　实体（9）

| id | kind | batch | side/identity | transponder_profile | facility |
| --- | --- | --- | --- | --- | --- |
| apsis | ship | OCUVF-ID13 | friend/friend | apsis（外部） | — |
| harmattan | ship | OCUVF-ID13 | friend/friend | harmattan（外部） | — |
| ferry | ship | CIV-FERRY-2 | neutral/unknown | ferry_prologue | — |
| watchtower | ship | L1-PATROL | neutral/unknown | watchtower_prologue | — |
| deepwell | ship | CIV-TANKER-9 | neutral/unknown | deepwell_prologue | — |
| **ceres_2** | ship | **FRC-OW-CER2-0417-C** | unknown/unknown | **ceres_2_demo**（faulty/no_reply；常码 0417/应急 7600） | — |
| **av_4412** | ship | **UEG-AV-4412** | ueg/unknown | **av_4412**（mode_5/crypto/military） | — |
| l1_station | station | L1-05 | neutral/station | l1_station（外部，station_beacon） | **L1-05** |
| chronos | fuel | L1-05-FUEL | neutral/station | chronos（外部，station_beacon） | **L1-05** |

- 合并应答机 profiles：外部 6 + 序章补充 4 = 10；实体引用全部校验。
- **Ceres-2 4A 同步**：实体 `batch/registration=FRC-OW-CER2-0417-C`、`transponder_code=0417`、
  `emergency_code/emergency_light_code=7600`、灯语 `L3-0417/L4-0417`；与
  `story_ceres.json`、`transponders_prologue.json` 的 `ceres_2_demo` profile 一致；
  entity id 仍 `ceres_2`，不改状态机/剧情文本。
- 灯语码合并外部 7 + 序章 6 = 13，含谷神-2 应急（`GUSHEN2_REQ/GUSHEN2_ACK_PRO/
  GUSHEN2_MAYDAY`）与通用询问/确认（`QUERY_STATUS/QUERY_ACK`）；4 位 code/mode 校验。
- 触发：
  - `ceres_no_reply`（event `no_reply`，target `ceres_2`，light_code `GUSHEN2_REQ`，
    story_flag `ceres2_no_reply`）；
  - `av4412_arrival`（event `entity_arrival`，target `av_4412`，light_code `QUERY_STATUS`）；
  - `chronos_unrest`（event `light_signal`，target `chronos`，light_code `GUSHEN2_MAYDAY`）。

## 4　PreludeScenario API

| API | 说明 |
| --- | --- |
| `PreludeScenario.new(cfg)` / `setup(cfg)` | cfg：`content` 或 `content_path`；默认加载本内容 |
| `load_content(path)` / `load_data(value)` / `validate(value)` | 读取/校验/应用；失败原子（保留旧状态） |
| `ready/errors/warnings` | 状态 |
| `entity(id)` / `entity_ids()` | 实体只读查询 |
| `profile(id)` / `profile_ids()` | 合并后的应答机 profiles（外部+序章补充） |
| `trigger(id)` / `trigger_ids()` / `triggers_for_event(event)` | 触发查询 |
| `light_code(id)` / `light_code_ids()` | 合并灯语码 |
| `facility_for_entity(id)` / `summary()` / `to_dict()` / `to_json()` / `check_contracts()` | facility 绑定/摘要/内容/JSON/DbC |
| `boot_config()` | GameSession boot config（entities/facility_registry/transponder_service/signal_service/prelude） |

校验：schema/version/entities 必填/唯一 id/kind/side/identity/pos/vel 有限/light_capable bool/
profile 引用存在/设施 L1-05 存在/外部内容文件存在且 schema 合法/灯语码 4 位与唯一/触发 id 唯一/
target 存在/light_code 引用存在/story_flag 非空/合并 profiles 通过 TransponderService 校验。
缺失/重复均返回明确 errors。

## 5　boot config（GameSession 接入）

```text
{
  entities: [9 实体 seed],
  facility_registry: {content_path},
  transponder_service: {content: {schema,version,profiles[10]}, jam, max_range_km},
  signal_service: {observer, targets[9], codes_content},
  prelude: {scenario, title, trigger_ids, light_code_ids}
}
```

- 实测 `GameSession.new(boot_config())` ready：world 9 实体、transponder 10 profiles、
  signal 9 targets、facility L1-05 可查、contracts ok。
- 触发列表交给后续 StoryRuntime/上层消费；本任务不接入剧情运行时、不写剧情文本。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/prelude_scenario_probe.gd
# V17 PRELUDE SCENARIO PROBE RESULT: PASS=411 FAIL=0（exit 0，只跑一次）
```

覆盖（5 节）：9 实体/字段/唯一/Ceres-2 独立；profiles/引用/外部内容；灯语码/触发；
facility/boot config/GameSession 启动；18 类非法内容原子拒绝、JSON/往返/确定性。

## 7　边界

- 场景内容只读；不写 world/UI/V15；实体/服务由 GameSession 用 boot config 创建。
- 触发只定义 trigger_id/event/target/condition/light_code/story_flag，不写剧情文本；
  StoryRuntime 消费由后续任务接入。
- 应答机/灯语引用既有内容；缺失明确报错，不静默用错误角色替代（**不得用 Harmattan
  代替 Ceres-2**）。
- 灯语码为序章演示（包含谷神-2 应急/通用询问确认）；不复刻真实视觉灯语时序；
  facility 仅 L1-05 绑定；未接 UI/物理；未跑全量回归；未 commit。
