# JC-A03 EW→观测→航迹→火控：写者/读者、时序与单位契约（开工审计）

> 分支 `jc/a03-ew-observation`，开工 SHA `3845852bd78821ee6b3c70c4d8f9c81a23dca5d6`（main，含 A2 合入 `82bf6a5`、A2 冻结 `755ab5e`；A1 `8455847`；G0=K0=`9d0f3b4…`）
> 本文件为 A03 第 1 步交付：实际链路审计、写者/读者表、同 tick 时序与单位、冻结 fixture、红例计划。

## 1. 当前实际链路审计（实测源码）

| 环节 | 位置 | 现状 |
|---|---|---|
| tick 顺序 | `game_session.gd:1397–1399` | **先 `_advance_sensors` 后 `_advance_ew`** |
| 传感器推进 | `_advance_sensors` (:1480) | `sensor_service.step(dt)` → observation/evidence 即时路由 |
| owner 情报 | `:1521–1538` | `authority.receive_observation(..., received_t=t, delay_s=0.0, path=direct)` |
| TrackTable | `:1539` | 即时 `handle_observation`，quality 原样进入聚合 |
| EW 推进 | `_advance_ew` (:1581) | 只 `step(dt)` + 发事件；**不采样、不影响观测** |
| EW 可观测接口 | `ew_service.observation_effect` (:274) | 计算 `confidence_mult`（noise=0.5→0.7）、`delay_s`（6×noise，或 `_iw.extra_delay_s`）、false 候选；目前仅查询包装 `game_session.ew_observation_effect` |
| 火控解算 | `combat_service.request_solution/tick` | 质量主要来自武器精度与距离；不消费航迹测量质量 |
| 既有入口 | `session.apply_ew` (:2556) | 唯一真实 EW 生效入口（带 `_record` 重放） |

### 缺口（红例依据）

1. EW 效果不进入真实观测：同 seed 开/关 EW，传感器 observation quality 不变。
2. 无延迟队列：`delay_s` 恒 0，效应 `delay_s` 未用于投递。
3. owner 航迹无「当前测量质量」字段；TrackTable 只有聚合（历史 max 会吞掉当前退化）。
4. 火控不消费测量质量：解算/耗时/误差与 EW 无关。
5. 无 EW 相关的在途观测持久化。
6. 欺骗 false 候选未进入被影响 owner 的普通证据验证。

## 2. 目标写者/读者（A03 完成后）

| 数据 | 唯一写者 | 读者 |
|---|---|---|
| EW 运行态与抽象 effect | `ew_service.apply/step`（既有） | Session 采样（每 tick 一次） |
| 同 tick effect 采样 | `GameSession._sample_ew_effects(t)`（每观测一次查询，不 step） | 观测质量/延迟计算、审计 |
| 观测质量与投递时刻 | Session：`quality_effective = clamp(quality × conf_mult)`；`arrive_t = observed_t + effect.delay_s` | 延迟队列、owner 情报、TrackTable |
| 延迟队列 | Session `_ew_observation_queue`（稳定排序 `(arrive_t, seq)`，随档） | 每 tick 投递器 |
| owner 航迹当前测量质量 | Session 投递时写 `authority_intel` owner 航迹（`measurement_quality/measurement_t/measurement_source`），不改身份/真值 | HUD/航迹读取、火控投影 |
| 火控质量消费 | `combat_service` 读 combat track 的 `measurement_quality`（缺省 1.0 兼容） | `request_solution`/`tick`/`request_fire` 结果 |
| 欺骗候选证据 | Session 投递时经 `identity_ingest(affected_owner, source=sensor, identity=unknown, evidence_type=deception_candidate)` | A2 融合（不自动确认） |

## 3. 同 tick 时序（不双步进 EW）

```
tick(t → t+dt):
  1. _advance_components / orders / ...
  2. _advance_sensors(dt):
       for each observation generated this step:
         eff = ew_service.observation_effect(target, sensor_kind)   # 采样 t 时刻状态（EW 尚未 step）
         quality_eff = clamp(quality × eff.confidence_mult, 0, 1)
         if eff.delay_s > 0: enqueue(obs, eff, arrive_t = obs.t + eff.delay_s)
         else: deliver immediately
  3. _advance_ew(dt): step effect timers/expiry（仍每 tick 一次）
  4. deliver due queue entries（arrive_t <= now）
  5. other components...
```

- 采样时刻 = 观测的 `observed_t`（本 tick 的 t），早于 EW step，等价「规定时刻查询」；
- 不重排既有组件推进顺序、不双步进 EW；
- `_iw.extra_delay_s` 由 `observation_effect` 合并，本层不硬编码 3s。

## 4. 单位/容差/冻结 fixture

| 量 | 单位/语义 | 容差 |
|---|---|---|
| `observed_t` / `received_t` / `arrive_t` | 模拟秒，单调；`received_t >= observed_t` | 时间比较 1e-6 s |
| `effect.delay_s` | 模拟秒 = 6×noise_severity（或有 `_iw.extra_delay_s` 时取 max） | 与队列 `arrive_t - observed_t` 差 ≤1e-6 s |
| `confidence_mult` | [0,1]；noise_jam=0.5 → 0.7 | 1e-9 |
| `quality` / `measurement_quality` | [0,1]；历史聚合与当前测量分开 | 1e-9 |
| 火控 quality 门槛（本卡冻结 fixture） | `q>=0.9` 正常；`0.5<=q<0.9` 解算耗时 ×1.5、精度 ×0.85；`q<0.5` 拒绝 `insufficient_quality` | 结果字段比较 |
| 几何 | 沿用既有 km / bary_rot / 1e-9 km、1e-12 km/s | 不放宽 |

- 未支持效果（comms_jam/comms_spoof/emcon/lwr 等）明确列限制：不进入观测质量链。
- 旧 seed/旧档 EW=0：无 effect 时质与延迟保持原行为（quality 原值、delay 0、同 tick 可见）。

## 5. 红例计划（`integration.jc_ew_observation`）

| # | 红例（实现前应失败） | 期望绿 |
|---|---|---|
| W1 | 同 seed，EW 关 vs noise_jam=0.5 开：真实 sensor 观测质量 | 开方 quality_eff = 关方 × 0.7（1e-9） |
| W2 | effect 采样与延迟 | 采样 `delay_s`=3.0（1e-6），`arrive_t=observed_t+3` |
| W3 | 延迟可见性 | 到达前 owner 情报/FireControl 不可见；到达后可见，received_t/observed_t 一致 |
| W4 | 当前测量质量进 owner 航迹与火控 | 航迹 `measurement_quality=0.7`；火控解算耗时/精度/误差按冻结规则变化 |
| W5 | 历史聚合不吞当前退化 | 先 q=1 后 q=0.7：聚合保持历史 1，火控用当前 0.7 |
| W6 | 欺骗候选 | 候选证据仅进入被影响 owner 且 identity=unknown，不自动成确认目标 |
| W7 | 真实文件在途恢复 | 保存/恢复后 ≥10 tick：队列 ID/可见集合/质量/解算与连续运行逐 tick 一致 |
| W8 | EW=0 兼容 | 无 effect 时质量/延迟/可见性与旧行为一致 |

红例先注册 matrix 并保存失败证据，再按 服务→队列→消费者→集成 分提交实现。
