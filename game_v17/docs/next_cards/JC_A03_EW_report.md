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

## 7. PR70 第二轮复核返修（R1/R2/R3，R4 关闭）

- **R1 真实弹道消费**：GameSession.request_fire 把接口层的 measurement_quality/error_km/quality/quality_accuracy_mult 传入 launch_opts 与射后 _ballistics_predict；CombatBallistics.predict 采用同一规范化 quality/error（不双重惩罚）；_launch_projectile 以确定性方式把 rror_km 落到 aim 偏移，弹体记录 pplied_error_km/measurement_quality/quality_accuracy_mult。以「有测量 vs 无测量（同档同几何）」对照证明输入被真实消费者使用，且返回风险 = 实际采用误差（1e-9）。
- **R2 拒绝守卫**：owner 接纳/去重拒绝在写全局 TrackTable/_sensor_track_map 之前直接返回，仅记录 rejected 审计；正常投递/重投语义保持。
- **R3 部分新段**：新增 EW 字段缺失视为有意兼容默认并返回 w_restore_mode=partial + w_restore_missing（不再触发 null 转换异常）；present-invalid 明确 ok=false/invalid；有效新段 ull、真正缺段旧档 legacy_absent。
- **探针**：83→102/0（新增 R20 真实弹道对照、R21 owner 拒绝不写全局、R22 partial 恢复）；专项 11/11、门禁 6/6+3/3、全量 90=83/7 new_fail=0。

## 8. PR70 第三轮复核返修（R1 发射前预测 / R3 旧档覆盖）

- **R1 发射前普通预测**：真实 HUD 入口 session.combat_predict_track 现按 owner 合法映射读取质量：实体键直接用 owner 当前质量；匿名 HUD 航迹键经 _entity_for_track 与 identity 解析复用实体映射。存在 owner 质量时按接口同一冻结规则生成显式 quality/quality_accuracy_mult/error_km 传给弹道预测；CombatBallistics.predict 在只有 measurement_quality、没有显式 quality/error 时实际应用 ×0.85 并据此生成误差（不再只写附带字段）。探针 R23 验证实体键、HUD 匿名键、mq-only 三条路径均与 combat_service.predict_shot 接口值一致（1e-9），HUD 与实体键一致；射后完整 opts 直接采用的正例保留，不双重惩罚。
- **R3 旧档覆盖会话**：_ew_restore_state 在整段 EW 字段缺失（legacy_absent）时先 _ew_reset_runtime() 清除加载前的队列/采样/投递/候选/seq/质量历史；同一旧档加载到活跃实例与新实例语义一致（队列/采样/投递均 0）。full 合法在途队列、partial/missing、present-invalid 行为不变。
- **探针**：102→126/0（新增 R23 发射前预测三条路径、R24 旧档覆盖活跃会话）；专项 11/11、门禁 6/6+3/3、全量 90=83/7 new_fail=0。
