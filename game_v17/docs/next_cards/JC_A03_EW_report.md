# JC-A03（#60）EW 实际影响观测、航迹与火控 · 交付报告

> 分支 `jc/a03-ew-observation`；开工 SHA `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`（main，含 A2 合入 `82bf6a5`）
> A2 冻结 `755ab5e`、A1 `8455847`；G0=K0=`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`；Godot `4.7.2.stable.official.ed1daf0bf`、Windows
> 证据：`game_v17/docs/next_cards/evidence/a03/`（红例与最终目录）

## 1. 写者/读者与时序/单位契约

见 `JC_A03_writer_reader_matrix.md`：实际链路审计、目标写者/读者、同 tick 时序（sensors 采样 EW 当前态 → EW step 一次 → 投递到期队列）、时间/质量单位与容差、冻结火控 fixture、红例计划。

## 2. 实现（按分链）

### 2.1 EW→观测采样（真实 Sensor 路径）

- `_advance_sensors` 对每条真实 sensor observation 在生成时查询 `ew_service.observation_effect(target, sensor_kind)`：
  - `sensor_kind`：radar/rwr/esm→radar；optical/ir/vis/laser→optical；
  - `quality_effective = clamp(quality × confidence_mult, 0, 1)`；noise=0.5 → ×0.7；
  - 记录采样 `ew_observation_samples()`：目标/传感器/采样时刻/effect/原质量/最终质量。
- 采样发生在 `_advance_ew` 之前（等价「规定时刻查询」），EW 仍每 tick 只 step 一次，不双步进。

### 2.2 稳定延迟队列与双时间

- `delay_s>0` 的观测进入 `_ew_obs_queue`（稳定排序 arrive_t 再 seq），**到达前不进入 owner 情报/TrackTable/HUD/火控**；
- 到期投递时 `received_t=now`，保留 `observed_t` 与捕获的观测快照（不随后来真值重生成），`delay_s=received-observed`；
- `delay_s=0` 立即投递，保持旧行为；数据随档保存，恢复后继续投递。

### 2.3 owner 航迹当前测量质量（与历史聚合分开）

- `authority_intel.apply_measurement(owner,target,{measurement_quality, measurement_original, measurement_t, measurement_source, measurement_degraded, measurement_effect, aggregate_quality})`；
- `aggregate_quality` 由 Session 质量历史取 max，**不复用 TrackTable 聚合**，避免历史 max 吞掉当前退化；
- `owner_measurement_quality()` 公开读取。

### 2.4 实际火控消费质量（冻结 fixture）

`combat_service`：
- 新增 `_track_quality`；`request_solution`：
  - `q<0.5` → 明确拒绝 `insufficient_quality`；
  - `0.5<=q<0.9` → 解算耗时 ×1.5（`solution_s`、`ready_t`），记录 `measurement_quality/base_solution_s/solution_s/quality_time_mult`；
  - `q>=0.9` 或航迹无质量字段 → 旧行为（缺省 1.0 兼容）。
- `update_track` 白名单新增测量字段；Session `combat_request_solution`/`request_fire` 在消费者边界把 owner 当前测量质量投影到实际 combat 航迹（真实 HUD 航迹键/实体键均适用）。

### 2.5 欺骗候选与未支持效果

- `deception/chaff/false_target` 候选经 `identity_ingest(affected_owner, identity=unknown, evidence_type=deception_candidate)` 进入**被影响 owner** 的普通证据流，不自动确认、不泄漏其他 owner；`ew_candidate_evidence(owner)` 可审计；
- comms_jam/comms_spoof/emcon 等不属于观测链：采样明确 confidence_mult=1、delay=0（限制清单，不冒充已接入）。

### 2.6 会话顺序与恢复

- tick 顺序：sensors（采样）→ 投递到期队列 → signal → EW step；EW 每 tick 一次；
- 存档新增 `ew_observation_queue/ew_observation_samples/ew_delivered_observations/ew_candidates/ew_observation_seq/ew_quality_history/ew_combat_quality`；旧档缺省为空（EW=0 兼容）。

## 3. 红→绿（同一分支）

| 阶段 | 结果 |
|---|---|
| 实现前（真实 API 红例，已提交 `631d5b4`） | `integration.jc_ew_observation` **13 PASS / 33 FAIL**，退出 1 |
| 实现后 | **47 PASS / 0 FAIL**，退出 0 |

覆盖：EW 关/开质量 0.7（1e-9）、effect 采样 delay=3s（1e-6）、延迟期间不可见/到达后可见、received=observed+delay、不使用后来真值、owner 当前测量质量、历史聚合分离、火控解算质量/耗时/拒绝、欺骗候选 owner 隔离与 unknown、真实文件在途恢复 10 tick 一致、EW=0 兼容、未支持效果限制。

## 4. 专项/门禁/C 回归

```
卡指定专项：9/9 PASS
  jc_ew_observation 47/0 · ew_probe 252/0 · sensor_service 128/0
  track_table 161/0 · combat 255/0 · sensor_persistence 86/0
  integration_authority 65/0 · save_roundtrip 41/0 · cic_view 925/0
Phase 0: 6/6 PASS      Phase A: 3/3 PASS
Full strict: 90 = 83 PASS / 7 历史 FAIL（new_fail=0、complete=true）
```

7 项历史失败未刷新 baseline；未移出 matrix、未放宽精度/负例。

## 5. 未支持效果清单 / NOT RUN

- 未接：comms_jam/comms_spoof（A04 通信）、emcon/lwr 的观测外语义、真实 RF/光学传播（#53）、完整军用协议；
- 欺骗候选不自动成确认目标、不直接改隐藏 side/身份/权限；
- Linux/macOS、非 headless 渲染/人工可读性、>1000 tick 成本 NOT RUN；
- 本卡为抽象近似 EW 模型验证，不声称真实 RF 已验证。

## 6. 证据

- 红例：`evidence/a03/red/`（summary + 原始 stdout）。
- 最终：见提交后 `evidence/a03/final/`（专项 9 项、两门禁、全量 summary）。
