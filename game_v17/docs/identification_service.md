# 完整游戏-阶段3R · IdentificationService 识别自动化/证据融合

> 任务 task-167。工程 `game_v17`。
> 新文件：`scripts/core/identification_service.gd`、`tests/identification_probe.gd`、本文件。
> 另由 GameSession 可选接入（见 `game_session.md`）；不写 world/TrackTable/UI/V15；未 commit。

## 1　定位

- 身份证据融合 + 自动/半自动询问策略；输入 transponder/sensor/track/iff/elint 证据，
  输出身份估计与 `identity_assessment` 事件；不写 world/TrackTable/UI，不发射武器。
- 与真实 IFF/SSR 差异：不复刻真实询问-应答报文/波形/密码学；Mode 5 等由
  TransponderService 行为层决定，本服务只融合“证据”。IFF/应答本身**不判敌**。

## 2　证据 schema（`identity_evidence.v1`）

```text
{
  target_id, source,              # transponder/iff/elint/signal/sensor/optical/
                                  # track/track_table/manual/...
  category,                       # iff/sensor/elint/track/manual/database（可省略，按 source 推断）
  t, mode, status, identity,      # identity: unknown/friend/neutral/suspect/hostile/station
  confidence,                     # 0..1
  spoofed, evidence_type,
  range_km, los, emcon, note
}
```

- 重复抑制：相同 target/source/identity/mode/status/t/spoofed 视为重复，不重复计数。
- 时间衰减：有效权重按半衰期衰减；超过 `evidence_ttl_s` 的证据不再参与融合。
- 输入非法（target/source/identity/confidence/t）拒绝且不改状态。

## 3　评估（`identity_assessment.v1`）

| 字段 | 说明 |
| --- | --- |
| `identity` | unknown/friend/neutral/suspect/hostile/station（自动最高 suspect；hostile 需授权） |
| `confidence` | 0..1；由纯度×平均有效置信×类别加成×时间衰减得到；冲突/欺骗封顶 |
| `level` / `level_name` | L1_BEARING / L2_POSITION / L3_CLASSIFIED / L4_IDENTIFIED |
| `sources` / `categories` | 来源/独立类别（iff/sensor/elint/track/manual/database） |
| `contradictions` | 身份冲突、IFF 单独 hostile 降级等 |
| `spoof_suspicion` | 0..1（spoofed/捕获/crypto/冲突加权） |
| `evidence_count` / `last_update` / `age` | 有效证据数/最近证据时间/年龄 |
| `manual` / `authorized` / `manual_*` | 人工确认/授权状态 |
| `trigger_hint` | `spoof_suspicion`/`suspect_identity` 等提示（不写剧情文本） |

阈值/规则：
- 单源证据最高 L3；**自动分类最高 suspect/L3**；hostile 自动永不输出。
- IFF/应答单独 hostile → suspect（note `iff_alone_downgraded`）。
- **L4**：人工确认/`authorize_hostile`，或至少**两类独立证据类别**且 confidence≥0.75 且
  自动身份非 unknown/suspect（friend/neutral/station）。hostile L4 必须授权。
- 冲突（≥2 种非 unknown 身份）→ suspect、confidence≤0.7、spoof_suspicion 增加；
  spoofed/captured/crypto 证据增加 spoof_suspicion，confidence 降级。

## 4　自动/半自动询问

- `auto_query_tick(dt)`：`step(dt)` 后，如 auto 开启且到 interval，按优先级
  （低置信/陈旧/spoof/unknown）选择目标；仅当 `range_km<=max_range_km`、`los=true`、
  `emcon=false` 且非 manual 锁定；按 `modes` 轮转选择询问模式；每 tick 最多
  `max_requests_per_tick`；生成 `identification_query_request.v1`（`weapon=false`、`auto=true`），
  放入 query_requests/事件；不自动发射武器。
- `set_auto(enabled, opts)` 配置 interval/modes/max_range/min_confidence/min_age/
  max_requests_per_tick。
- GameSession：auto 开启时 tick 由 Session 执行 query_request（经 TransponderService 询问），
  把 reply 转成证据回灌识别；auto 关闭时只推进时间/衰减。

## 5　API

| API | 说明 |
| --- | --- |
| `setup(cfg)` | cfg：`evidence_ttl_s`/`decay_half_life_s`/`auto_level_max`/`observer_id`/`auto{...}`/`t` |
| `ingest(evidence)` | 输入证据（重复抑制/衰减；返回 assessment） |
| `step(dt)` / `assess(target_id)` / `get_assessment(target_id)` | 推进/重算/只读查询 |
| `manual_confirm(target_id, identity, opts)` / `authorize_hostile(target, authority, opts)` / `clear_manual` | 人工确认/授权 hostile/L4；清除人工 |
| `set_target_state(target, {range_km,los,emcon,priority,manual_locked})` | 供自动询问条件 |
| `auto_query_tick(dt)` / `take_query_requests()` / `set_auto` | 自动询问计划/队列/配置 |
| `set_time(t)` / `events` / `take_events()` | 时间/事件 |
| `vm()` / `summary()` / `to_json()` / `save_state()` / `load_state()` / `check_contracts()` | 只读/存档/DbC |

存档 schema `v17.identification_service_save.v1`：t、auto、evidence、assessments、
target_states、query_requests、events、seq；load 校验后应用，非法整体拒绝。
事件 schema `identification_event.v1`：kind `evidence_ingested/assessment/step/
query_request/manual_confirm/manual_clear/auto_config`；payload 含 assessment。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/identification_probe.gd
# V17 IDENTIFICATION PROBE RESULT: PASS=310 FAIL=0（exit 0，只跑一次）
```

覆盖（7 节）：setup/基础融合；hostile/矛盾/欺骗；L3-L4/人工确认/授权；衰减/重复抑制；
自动询问（interval/priority/mode、range/LOS/EMCON、manual 跳过、无武器）；save/确定性；
批量矩阵（5 身份×4 来源、source→category、冲突对、L4 置信边界、auto 多目标过滤）。

## 7　边界

- 只做证据融合/识别建议；不写 world/TrackTable/UI/V15；不发射武器/不自动敌对。
- 自动分类最高 suspect/L3；hostile 仅人工/授权；未知/中立仍需授权才能交战（接 Combat 层）。
- 不复刻真实 IFF 密码学/波形/询问报文；不复刻真实证据概率模型；
  confidence/阈值是可调游戏参数；证据来源由上层提供，不自动从传感器推导。
- trigger_hint/事件只供 StoryRuntime/UI 消费，不写剧情文本；未接 UI/物理；未跑全量回归；未 commit。
