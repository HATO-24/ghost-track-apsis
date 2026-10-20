# 完整游戏-阶段3P · TransponderService 应答机行为层

> 任务 task-164。工程 `game_v17`。
> 新文件：`scripts/core/transponder_service.gd`、
> `tests/transponder_probe.gd`、本文件、
> `framework/content/transponders_prologue.json`。
> 另由 GameSession 可选接入（见 `game_session.md`）；不写 world/TrackTable/物理/V15；未 commit。

## 1　定位

- 应答机是**行为模型**：注册码/模式/状态/加密/询问/广播/触发；不产生真实无线电传播、
  不修改实体运动、不写 TrackTable；输出 `transponder_event.v1` 与 `track_evidence.v1`，
  由 GameSession 白名单路由（evidence→TrackTable，事件→EventBus）。
- 实体类型：`ship / station / port / fuel / tank / otc / relay`。
  - **ship**：绑定 world entity（`entity_id`）；
  - **station/port/fuel/tank/otc/relay**：绑定 FacilityRegistry 的 `facility_id/facility_code`
    （GameSession 把 facility registry 注入服务，校验存在与一致）。
- 与真实 SSR/IFF 的差异：本服务是游戏行为/证据层，不复刻真实 SSR 波形、Mode S 数据链
  报文、Mode 5 密码学/TSM；不模拟天线方向图、真实传播/多径/干扰波形；Mode 5 的
  challenge/reply 为确定性占位（按 epoch 派生 response），仅用于状态机/剧情/UI 演示。

## 2　内容 schema（`transponders_prologue.json`）

```text
schema: v17.transponders_prologue.v1, version 1.0.0
profiles: [{
  profile_id, name, entity_type,
  entity_id,                       # ship 必填（world binding）
  facility_id, facility_code,      # station/port/fuel/tank/otc/relay 必填（FacilityRegistry）
  transponder_code,                # 全局唯一
  registration_code,               # 全局唯一
  side, identity,
  modes: [mode_a|mode_c|mode_s|mode_5|station_beacon|adsb_like],
  default_mode, status,
  range_km, silent,
  broadcast: {enabled, interval_s, modes:[...]},
  crypto: {epoch, valid, captured, key_id},
  trigger_map: {<状态/原因>: trigger_id},
  note
}]
```

- 示例 profiles：`apsis`/`harmattan`（ship）、`l1_station`/`greenwich`（station，绑定
  L1-05/L1-01）、`chronos`（fuel，绑定 L1-05）、`ceres_2_demo`（故障/无应答 demo）。
- 触发 ID 示例：`ceres_no_reply`、`station_spoof`、`unknown_code`；服务只输出
  trigger_id/event/reason，不硬编码剧情文本。

## 3　状态 / 模式

| 状态 | 行为 |
| --- | --- |
| `normal` | 按 mode 回复 |
| `off` / `no_reply` / `expired` | 不回复（no_reply 事件；可按 trigger_map 触发） |
| `faulty` / `wrong_code` / `crypto_fail` | 不回复或证据降级（配置决定） |
| `captured` / `spoofed` | 返回 **spoofed reply**（identity unknown、confidence 降级、trigger 可配置） |

- 模式按 profile `modes` 能力：Mode A/C/S、Mode 5、station_beacon、adsb_like；
  `default_mode` 必须在能力表内。
- **Mode 5 需要 challenge/reply**（crypto valid 时返回 challenge/response；crypto invalid →
  `crypto_fail`；captured crypto → `captured_crypto`）；普通模式不需要 challenge。
- `lookup_code` 匹配 transponder/registration/facility code；未知→`unknown_code`，
  重复→`duplicate:true`（内容校验保证 transponder/registration 唯一）。

## 4　询问 / 广播

`interrogate(source, target, mode="", opts)`：
- opts：`range_km`（实际距离，>profile.range_km→out_of_range）、`occluded`（含 target/全局遮挡）、
  `jam` 0..1（>0.5 不回复；0<≤0.5 降置信度/support）、`latency_s`（>max_latency 不回复）、
  `challenge`（Mode 5）。
- 返回 `{ok, reply, evidence[], trigger, events[]}`；no_reply 仍有 reply 对象/reason；
  captured/spoofed 为 ok reply 但 spoofed=true；证据 `support`：正常 4，spoof/低置信 3。
- 事件 `transponder_event.v1`：kind `interrogation/no_reply/broadcast/status_changed/
  crypto_changed/jam_changed/occlusion_changed/profile_*`；含 trigger_id（如有）。
- `broadcast()`：station_beacon/adsb_like 且 status normal；ship `silent=true` 不广播；
  `passive_listen()` 同广播采集（被动）；输出 `transponder_broadcast.v1` + evidence + 事件。

## 5　API

| API | 说明 |
| --- | --- |
| `setup(cfg)` / `validate_content(value)` | cfg：`content`/`content_path`/`facility_registry`/`max_range_km`/`max_latency_s`/`jam`/`occluded` |
| `profile_ids()` / `profile(id)` | profile 列表/只读副本 |
| `upsert_profile(raw)` / `remove_profile(id)` | 动态 profile 管理（校验失败原子拒绝） |
| `lookup_code(code)` / `crypto_state(id)` | 码注册表/加密状态 |
| `interrogate(source,target,mode,opts)` | 询问 → reply/evidence/trigger/events |
| `broadcast(opts)` / `passive_listen(opts)` | 广播/被动监听 |
| `set_status(id,status)` / `set_crypto(id,patch)` | 状态/加密（事件+trigger） |
| `set_jam(target,severity)` / `set_occlusion(target,bool)` | 干扰/遮挡（""=全局） |
| `set_time(t)` / `events` / `take_events()` / `trigger_ids()` | 时间/事件/触发 |
| `vm()` / `summary()` / `to_json()` / `save_state()` / `load_state()` / `check_contracts()` | 只读 VM/摘要/存档/DbC |

`save_state` schema `v17.transponder_service_save.v1`：t、profiles 运行时状态、events/evidence/
triggers、jam/occlusion、seq；`load_state` 校验 profile 后应用，非法整体拒绝。

## 6　GameSession 路由

- boot `transponder_service`（true 或配置；facility_registry 自动注入给 service）。
- session API：`transponder_interrogate/broadcast/passive_listen/lookup_code/set_status/
  set_crypto/set_jam/set_occlusion/upsert_profile/remove_profile/profile/vm/summary/
  trigger_ids`。
- 白名单：`track_evidence.v1` → TrackTable（target_id 经共享映射；不重复建 track）；
  `transponder_event.v1` → EventBus `transponder.<kind>`；不写 world。
- tick：只同步 transponder 时间，不自动询问/广播（广播由显式 API/上层触发）。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/transponder_probe.gd
# V17 TRANSPONDER PROBE RESULT: PASS=272 FAIL=0（exit 0，只跑一次）
```

覆盖（6 节）：setup/内容/绑定（6 profiles、entity/facility、坏内容拒绝）；6 种模式/9 状态/
captured/spoofed/trigger；加密 mode5 challenge/reply/crypto_fail；range/occlusion/jam/latency；
码查询/广播/passive；profile 管理/save-load/确定性/契约。

## 8　边界

- 不写 world/TrackTable/UI/V15；不产生真实射频/传播/波形；不模拟真实 Mode 5 密码学。
- 仅行为/证据/触发演示；位置/遮挡/干扰/延迟为参数化输入，不自动从物理/传感器推导。
- 不决定敌我（identity/side 由 profile 配置；captured/spoofed 仅把身份降为 unknown）。
- trigger 只输出 ID/event/reason，不写剧情文本；StoryRuntime 消费由上层接入。
- 未接 UI/物理/旧 transit；未跑全量回归；未 commit。
