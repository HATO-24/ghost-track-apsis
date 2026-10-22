# 交战系统设计提案 · 弹道 / 飞控 / 引导头 / 齐射 / 巡航 / 对抗 / 后效

状态：**R6 已实现（2026-10-22）**。本文保留为设计依据；实际实现口径见 §15，未实现项见 §14。
对应待办：`docs/43_开发待办清单.md` → `战斗物理闭环`（pending）。

相关现状文档：`combat_service.md`、`combat_ballistics.md`、`damage_model.md`、`cislunar_physics.md`、`physics_world.md`。

---

## 0. 摘要与待确认决策

现状不是"缺功能"，而是**三个结构性缺陷**：

| # | 缺陷 | 证据 | 后果 |
|---|---|---|---|
| D1 | 两条互不相通的交战路径 | `combat_service.request_fire()` 同步掷骰命中（`"no_physics": true`）；`combat_ballistics.launch()` 只被 `game_session.combat_ballistics_launch()` 调用，UI/自动交战都不走它 | 真实弹道代码等于死代码；玩家开火看到的是概率 |
| D2 | 弹道在旋转系里当直线积 | `combat_ballistics.gd:496-498` `pos + vel*dt`，无科氏/离心/引力 | 见 §2：1200 km 射击必偏 256 m，命中半径只有 80 m |
| D3 | 无引导头，制导=限转向的纯追踪 | `combat_ballistics.gd:475-495` 朝当前目标位置转；`launch()` 制导初瞄 `tp + tv*0.5` 固定半秒提前 | 导弹"永远知道目标在哪"，没有搜索/锁定/丢锁/外推 |

另有 4 个数据/数值硬伤：`scenario_prologue.json` 零个 `radius_km`（命中判定只剩战斗部半径）；`missile.range_km=6000` 与 `lifetime_s=300`×`max_speed 12` ≈ 3573 km 不自洽（射程物理上打不到）；`salvo` 仅被当弹药扣减（`combat_service.gd:561`）；`PD` 每步只处理数组里第一个弹（`combat_ballistics.gd:617` `return`）。

**需要你确认的 6 个决策**（§13 有详细选项）：

1. 实弹是否接受"惯性系直线 + 解析科氏修正"（而非全程 RK4）？
2. 是否接受 P2 统一路径导致 `request_fire()` 由同步变异步（现有 probe 需改）？
3. 齐射弹药不足：拒绝 or 按余量降级发射？
4. 交战时是否强制降时间倍速（否则 300 s 导弹寿命在 3600× 下只有 0.08 实秒）？
5. 引导头做几型（雷达主动 / 红外被动 / 反辐射）还是先只做一型？
6. 巡航路径点用"绝对位置点"还是"相对时序点（Δv + hold）"？

---

## 1. 现状核查（代码级）

### 1.1 实弹（railgun）

```
weapons_l1.json:  range 1200 km, speed 15 km/s, hit_radius 0.08 km, accuracy 0.82, salvo 1
combat_ballistics.predict()  → trajectory "straight_lead"
combat_ballistics._lead_point()  → 4 次不动点迭代求提前点
combat_ballistics.step()     → p["pos_km"] = pos + vel*d   （无任何加速度项）
命中判定 → _segment_distance(prev, new, target_pos) <= hit_radius + target_radius
```

结论：几何判定是对的（线段-球，不会因步长大而穿模），但**动力学是错的**，且 `target_radius` 恒为 0。

### 1.2 导弹

```
weapons_l1.json:  range 6000 km, speed 8, salvo 1, interceptable true
DEFAULTS:         fuel 120 s, accel 0.30 km/s², turn 45 °/s, max_speed 12, lifetime 300 s
step():           朝 target_pos 转向（限 turn_rate）→ 有油则加速到 max_speed → 直线
guidance_lost:    vel 保持当前方向，但仍用实时 target_pos 计算 —— 实际未丢锁
```

结论：是"限转向率的纯追踪"，不是飞控；无姿态、无过载、无重力、无引导头。

### 1.3 齐射 / 巡航 / 自动解算 / 对抗

| 能力 | 现状 |
|---|---|
| 齐射 | 只有 `salvo` 字段，`ammo -= salvo`，只生成 1 发 |
| 巡航路径点 | 内容里无任何字段，代码无分支 |
| 自动轨道计算 | 无。`_lead_point` 只解直线提前量，不解 Lambert/转移 |
| 诱饵 | `_roll("DECOY|pid") < seduce_prob`，**每步重掷** |
| 干扰 | `_roll("JAM|pid|step_count") < lock_loss_prob`，**每步重掷** |
| PD | 每步 1 次掷骰、只挑数组第一个弹、单平台 |

每步重掷是模型错误：30 s 内 60 次 20% 掷骰，丢锁概率实际 ≈ 1-0.8⁶⁰ ≈ 100%，而内容写的是 20%。

### 1.4 打击后效（这条链是真的，不用重做）

`DamageModel.apply_hit()`（`framework/core/damage_model.gd:217`）已经是可用的物理链：

```
resist = kinetic_resist*(1-pen) + energy_resist*pen
damage = energy*(1-resist)
已毁坏分区只吸收 25%
e >= min_energy(0.25) 且 pen>0 → 溢出相邻分区（overflow_ratio 0.4, max 2 段）
→ _try_ignite_fire / _try_decompression / _update_power / _on_section_destroyed / _recompute_effects
```

缺的是**输入端**：命中部位由 `suggested_sections[0]` 硬取（`combat_service.gd:584-587`），`direction` 传进去却没参与选部位；`damage_kind` 没参与抗性计算；无近炸/破片/殉爆。

---

## 2. 量级分析：为什么现在的直线弹道必偏

地月旋转系角速度 ω = 2π/2360591.5 = **2.6617e-6 rad/s**。
科氏加速度 |a| = 2ωv；t 秒累积位移 ≈ ½·2ωv·t²。

| 武器 | 飞行距离 | 飞行时间 | 科氏位移 | 引力位移 | 命中半径 | 偏差/半径 |
|---|---|---|---|---|---|---|
| railgun | 1200 km | 80 s (15 km/s) | **256 m** | 8.6 m | 80 m | **3.2×** |
| missile | 3500 km | 500 s (12 km/s) | **7990 m** | 340 m | 150 m | **53×** |

（引力位移按 r=384400 km、g=2.697e-6 km/s² 估。）

两条关键结论，决定了方案分层：

- **实弹不需要全程 RK4**：引力只有 8.6 m，远小于命中半径；偏差几乎全部来自**坐标系旋转**。而"无外力质点在惯性系走直线"是解析精确的 —— 只要在惯性系积分、回到旋转系做判定，256 m 偏差直接归零，代价是每步一次旋转矩阵。
- **导弹必须进 CR3BP**：8 km 偏差是命中半径的 53 倍，且导弹还有推力矢量、长时间飞行、姿态滞后，直线模型无意义。

---

## 3. 实弹弹道方案

### 3.1 积分

```
弹丸状态改存惯性系（earth_rot，与 physics_world 的 frame 参数一致）：
  r_i, v_i  ← 发射瞬间由 bary_rot 转换
每步：r_i += v_i*dt;  v_i += g_local*dt   （g_local 用 CislunarPhysics.acceleration_rot 去掉旋转项后的引力部分，
                                           或直接取 r 处两体引力，80 s 内二阶项可忽略）
命中判定：把 r_i 转回 bary_rot，与目标（bary_rot）做线段-球
```

- 引力项保留（成本为零，把 8.6 m 也收掉），但**不做 RK4**：80 s 内用一次中点法足够。
- 判定仍用 `_segment_distance`，不引入子步要求 —— 直线段与真实轨迹在 80 s 内差异 < 1 m。
- 提前点迭代保留 `_lead_point` 的 4 次不动点，但目标位置改用 `physics_world` 的状态（已有 `_ballistics_states()`），而不是线性外推 `tp + tv*t`。线性外推在 80 s 内引入的误差 ≈ ½·a_target·t²，与引力同量级，顺手一起修。

### 3.2 散布（把 `accuracy` 变成物理量而不是掷骰）

现在 `accuracy 0.82` 在 `combat_service` 里直接当命中概率。改成角散布：

```
σ_angle = accuracy_to_sigma(accuracy)   # 0.82 → 约 0.6 mrad
落点偏移 = σ_angle * range * gauss(seed)
命中 = 偏移 <= hit_radius + target_radius
```

这样"远距离更难打"是自然结果，不再需要 `range` 之外的概率修正。`accuracy` 字段语义保持（越大越准），只换解释方式。

### 3.3 命中半径与目标尺寸

必须补 `radius_km`：`scenario_prologue.json` / `physics_world` 实体上加，缺省按舰型给（护卫舰 0.05 km、巡洋舰 0.12 km、设施 0.3 km）。否则 `hit_radius + 0` 让所有目标都是质点。

---

## 4. 导弹飞控与轨道推进

### 4.1 飞行阶段状态机

```
BOOST ──► MIDCOURSE ──► TERMINAL ──► IMPACT
             │  ▲           │
             │  └───────────┘  (丢锁→重回搜索，若还有油)
             └──► ABORT (燃料耗尽/超时/目标消失)
```

| 阶段 | 制导律 | 说明 |
|---|---|---|
| BOOST | 定姿 + 满推力 | 姿态由发射方向起步，`turn_rate_dps` 限幅 |
| MIDCOURSE | 路径点追点（若有 waypoint）/ 惯性 + 中段修正 | 引导头关机（静默），靠发射前装订的预测拦截点 |
| TERMINAL | 比例导引 PN | 引导头开机后 `a_cmd = N·Vc·λ̇`，N=3.5，受 `max_accel`/`turn_rate` 限幅 |
| TERMINAL_LOST | 惯性外推 | 用最后锁定点的弹道外推，**不再读目标实时位置** |

### 4.2 状态与积分

```gdscript
projectile = {
  "frame": "bary_rot",
  "r_km": [...], "v_kmps": [...],        # 替代现有 pos_km/vel_kmps
  "attitude": [...],                      # 单位矢量，受转向率限幅，不瞬时对准
  "mass_kg": ..., "fuel_kg": ...,
  "phase": "BOOST|MIDCOURSE|TERMINAL|TERMINAL_LOST",
  "seeker": {...},                        # §5
  "waypoints": [...], "wp_index": 0,      # §7
  "last_lock": {"r_km": [...], "v_kmps": [...], "t": ...},
}
```

每步：

```
a_grav = CislunarPhysics.acceleration_rot({r, v})        # 已含科氏+离心+双体引力
a_thrust = (fuel>0 ? thrust_kmps2 : 0) * attitude
(r, v) = CislunarPhysics.rk4_step({r, v + a_thrust*dt_half}, dt)   # 推力当半隐式处理
```

复用现成 `rk4_step`，不新写积分器。`thrust_kmps2` 由 `max_accel_kmps2` 换算（现字段直接用）。

### 4.3 燃料 → Δv 预算（发射前校验）

```
Δv_budget = max_accel_kmps2 * fuel_s        # missile: 0.30 * 120 = 36 km/s
Δv_needed ≈ |v_impact - v_launch| + 转向损耗
if Δv_needed > Δv_budget: launch() 拒绝，reason="insufficient_dv"
```

这条校验同时暴露 §0 的射程硬伤：6000 km 射程在 300 s 寿命内到不了。建议把 `lifetime_s` 提到 900 s、或把 `range_km` 降到 3400 km —— 二者选一，由你定（我倾向提寿命，因为 6000 km 是设计意图）。

---

## 5. 引导头（seeker）识别机制

**重要区分**：这里的"识别"是**弹上目标识别**（我在打谁），和已有的 `IdentificationService`（IFF 身份识别）是两件不同的事，不要混。文档与代码命名统一用 `seeker`。

### 5.1 模型

```json
"seeker": {
  "type": "radar_active" | "ir_passive" | "arm",
  "range_km": 400, "fov_deg": 60,
  "acquire_s": 2.5, "break_snr": 6.0,
  "home_on_jam": false
}
```

### 5.2 四态

| 状态 | 判据 | 输出 |
|---|---|---|
| SEARCH | 默认；导弹在 MIDCOURSE | 无制导，走路径点/惯性 |
| ACQUIRE | `dist <= range` 且 `angle <= fov/2` 且 `snr >= acquire_snr` | 累积 `acquire_s` 计时，未满则继续 |
| TRACK | 累积满 | 输出 PN 制导，`track_quality ∈ [0,1]` |
| LOST | `snr < break_snr` 持续 `break_s`，或角速度 > `gimbal_rate` | 转 TERMINAL_LOST，惯性外推 |

```
snr = seeker_power * rcs / dist^4 / (1 + jam_ratio)      # 雷达
snr = ir_signature / dist^2 / (1 + flare_ratio)          # 红外
```

`rcs` / `ir_signature` 从实体 flags 取，缺省按舰型给。`jam_ratio` 由 §9 的干扰模型提供（不再是硬币）。

### 5.3 为什么必须做这个

现在的 `guidance_lost` 是假的：`combat_ballistics.gd:472-473` 只是把速度方向冻住，下一秒仍读 `target_pos`。真实丢锁必须**停止获取目标状态**，改为外推 —— 否则干扰/诱饵永远无法真正生效，玩家也看不到"导弹飞偏了"这个最有戏剧性的结果。

---

## 6. 齐射

```
salvo = N  →  launch() 生成 N 个独立 projectile
每发独立：
  - 方位/俯仰散布  gauss() * salvo_spread_deg   （内容新增，缺省 0.15°）
  - 独立 seeker 实例（各自 ACQUIRE/TRACK/LOST）
  - 独立诱饵/干扰对抗 roll（一次，不是每步）
  - 独立引信与命中判定
弹药：ammo -= N（要求 ammo >= N，否则见决策 3）
冷却：整组共用一个 cooldown（一次齐射一次冷却）
```

战果聚合到 `salvo_record`：`n_launched / n_intercepted / n_decoyed / n_lost / n_hit / n_miss`，供 AAR 与 UI 用。

PD 侧必须同步改：`_auto_pd` 从"每步 1 发、只挑第一个"改成

```
每步对每个 PD 平台：候选 = 包线内、未被拦截的弹，按 到达时间 ETA 排序
shots = min(可用射速*dt, ammo)
逐个掷骰 P_kill = intercept_prob * range_factor
```

这样"齐射饱和压防御"才是真的。

---

## 7. 路径点巡航

### 7.1 内容

```json
"profile": {
  "waypoints": [
    {"type": "pos", "r_km": [x,y,z], "hold_s": 0},
    {"type": "rel", "delta_v_kmps": [0.0, 0.0, 0.4], "hold_s": 30},
    {"type": "silent", "until_km": 800}
  ],
  "cruise_speed_kmps": 3.0,
  "terminal_acquire_km": 800.0,
  "dogleg": true
}
```

### 7.2 逻辑

```
MIDCOURSE: wp_index 逐个追点，切向速度控制（不是 PN，避免绕圈）
          到达判定 dist <= wp_radius（缺省 5 km）
          silent 段：seeker 关机，只靠惯导 → 敌方 PD/ESM 发现概率下降
到达 terminal_acquire_km 或最后一个 wp → seeker 开机 → TERMINAL
```

发射前校验：`Σ|wp_i+1 - wp_i| + |target - wp_last| <= 可用航程`，否则 `launch()` 拒绝（fail fast，不能飞一半没油）。

**为什么值得做**：这是唯一能让"绕开拦截包线 / 保持静默接近 / 多轴同时到达"成为玩家可选战术的机制。没有它，所有导弹都是直线，PD 布防没有意义。

---

## 8. 自动轨道/拦截解算

要区分两件事，不要混成一个"自动轨道计算"：

### 8.1 拦截解算（交战必需）——`InterceptSolver`

```
求 t_f 使 |r_target(t_f) - r_missile(t_f; t_f)| = 0
一维根搜索（Brent），初值用直线估计 t0 = dist / speed
每次评估：目标位置用 physics_world 的 CR3BP 外推；导弹用 §4 的积分器前向推
迭代 20~30 次，收敛阈值 1 m
调用时机：发射前算一次；MIDCOURSE 每 N 秒（N = 10）修正一次
```

成本可控：只在发射与中段修正时跑，不进 tick 热路径。

### 8.2 转移轨道规划（玩家规划层，非交战）

复用现有 `transfer_l4_l1_cached.json` 工具链，**本次不动**。交战系统只需要"给我拦截点"，不需要 pork-chop 全图。

---

## 9. 对抗机制

### 9.1 从"每步掷骰"改成"状态机 + 时间积分"

| 手段 | 现模型 | 新模型 |
|---|---|---|
| 干扰 jammer | `_roll < lock_loss_prob`，每步 | `jam_ratio = P_jam/(P_sig+P_jam)` → seeker `snr` 下降 → `track_quality` 指数衰减 → 低于 `break_snr` 才 LOST。干扰机有 `range_km`/`power`/`beam_width`，方位不对无效 |
| 诱饵 decoy | `_roll < seduce_prob`，每步 | 诱饵作为**独立假目标**进入 seeker 候选列表，按 `score = rcs/dist² * doppler_match` 竞争；导弹锁到诱饵 → 追诱饵 → `DECOY_IMPACT` |
| 反辐射 | 无 | `seeker.type == "arm"` + `home_on_jam` → 干扰源变成目标（干扰反成暴露） |
| PD | 单次掷骰 | 射速 × 暴露时间 × 单发命中率，见 §6 |

关键原则：**对抗的效果必须能被玩家观察到**（导弹明显拐弯、锁错目标、飞过去），不能只是一个 `miss` 事件。

### 9.2 双向性

干扰/诱饵现在是"防守方白嫖"，因为攻击方无法反制。加了 `arm` 引导头与 `home_on_jam` 后，开干扰机是有代价的 —— 这才是电子战。

---

## 10. 打击后效

### 10.1 保留（已实现，不改）

`DamageModel.apply_hit` 的抗性、溢出、火灾、失压、断电、连锁全部复用。

### 10.2 补齐输入端

| 缺口 | 改法 |
|---|---|
| 命中部位靠 `suggested_sections[0]` | 用入射方向 → 部位几何映射：`direction` + 命中点在实体局部系的偏移 → 选 `hull/propulsion/power/...`。`suggested_sections` 降级为"该武器偏好部位"的加权，不是硬指定 |
| `damage_kind` 未参与计算 | `resist` 按 `damage_kind` 选系数：kinetic→`kinetic_resist`，explosive→`energy_resist`，两者都传时按 pen 混合（现在就是这么写的，但 kind 没被读） |
| 无近炸/破片 | 新增 `proximity_fuse_km` + `frag_damage`：未直接命中但在引信半径内 → 小能量、多部位溅射（`energy = frag_damage * (1 - d/fuse_km)`） |
| 无殉爆 | `propulsion` 分区毁坏 → 概率触发 `secondary_explosion`，对相邻分区追加能量（`damage_model` 已有 `_on_section_destroyed` 钩子，挂这里） |
| 双账本 | `combat_service.request_fire()` 直接改 `tr["damage_taken"]`，`DamageModel` 改实体 `integrity` —— 两套战果。统一路径后（§11 P2）只保留 `DamageModel`，track 级 `damage_taken` 改为从 `DamageModel.summary()` 派生 |

### 10.3 后效的可观测性

`DamageModel` 已产出 `effects`（推力/电力/生命维持折减）。需要把这些折减**接回物理**：`propulsion` 完整性 → `max_accel` 折减；`power` → 传感器/PD 可用性。否则打了半天，目标机动性不变，玩家感知不到战果。

---

## 11. 时间压缩与子步（跨领域硬约束）

这是最容易翻车的地方，必须先定。

**现状**：`TimeService.max_dt_s = 3600`，`tick()` 把 `sim_dt`（最高 3600 s）**一步**丢给 `combat_ballistics.step()`。3600 s × 12 km/s = 43,200 km 一步 —— 制导积分、PD 交战窗口、引信判定全部失效。

三个可选策略：

| 方案 | 做法 | 代价 |
|---|---|---|
| A 交战降速（推荐） | 有弹在飞时，`TimeService.scale` 上限压到 60×，交战结束恢复 | 需要 UI 提示"交战时间膨胀"；玩家想快进时被打断 |
| B 固定子步 | 弹道内部按 1 s 子步，`substeps = ceil(dt/1.0)`，上限 64 | 3600× 下仍只有 56 s 有效步长，等于没修 |
| C 弹道独立时基 | 弹道自己维护 `t_ballistic`，按 1 s 网格追赶，单 tick 最多推 600 步 | 与任务时钟脱钩，存档/回放复杂 |

推荐 **A + B 组合**：平时 scale ≤ 60（A），保证 1 s 子步能覆盖（B 上限 8 步）。交战结束自动恢复原倍速。这也顺带解决"300 s 导弹寿命在 3600× 下只有 0.08 实秒、玩家根本看不见"的体验问题。

---

## 12. 内容 schema 变更（`weapons_l1.json`）

向后兼容（新字段全部可选，缺省值写在 `combat_ballistics.DEFAULTS`）：

```jsonc
"missile": {
  "salvo": 1,                        // 语义改为"单次发射数量"
  "salvo_spread_deg": 0.15,
  "lifetime_s": 900,                 // 由 300 提到 900（配合 6000 km 射程）
  "thrust_kmps2": 0.30,              // 与 max_accel_kmps2 同义，保留旧字段兼容
  "seeker": { "type": "radar_active", "range_km": 400, "fov_deg": 60,
              "acquire_s": 2.5, "break_snr": 6.0, "home_on_jam": false },
  "profile": { "waypoints": [], "cruise_speed_kmps": 3.0,
               "terminal_acquire_km": 800.0 },
  "proximity_fuse_km": 0.3,
  "frag_damage": 0.12
}
```

---

## 13. 分阶段实施与决策点

| 阶段 | 内容 | 是否改公开接口 | 验收 |
|---|---|---|---|
| **P1 修硬伤** | 惯性系弹道 + 科氏修正；`radius_km` 补齐；`lifetime/range` 数值自洽；齐射拆弹；丢锁改外推；PD 按 ETA 选弹 | 否 | `combat_ballistics` 单测：1200 km 射击落点偏差 < 10 m；齐射 N 发产生 N 个 projectile |
| **P2 统一路径** | `request_fire()` 不再掷骰 → 调 `launch()`；战果由 `impact` 事件回写；`CombatService` 只留授权/解算/弹药 | **是**（同步→异步） | `combat_probe` / `session_probe` 需改；UI 开火后需等 impact |
| **P3 引导头 + 对抗** | seeker 四态；PN 制导；干扰 snr 模型；诱饵竞争；PD 射速模型 | 否 | 脚本化场景：干扰开/关对比丢锁率；诱饵锁错可见 |
| **P4 巡航 + 解算** | waypoint 巡航；`InterceptSolver`；静默段 | 否 | 多轴同时到达；绕包线路径可规划 |

### 决策点

1. **实弹积分**：接受"惯性系直线 + 解析科氏"（§3.1，误差 < 1 m，成本近零）？还是要全程 RK4（统一好看，但 80 s 飞行没必要）？
2. **P2 异步化**：`request_fire()` 现在返回 `{hit: bool}`，统一后只能返回 `{launched: bool, shot_id}`，命中要等 impact 事件。现有 `combat_probe`（约 20 处断言）与 `session_probe` 会红。接受改测试吗？还是保留一个 `request_fire_sync()` 兼容层？
3. **齐射弹药不足**：拒绝（`reason="insufficient_ammo"`）还是降级按余量发射？我倾向前者（明确）。
4. **时间压缩**：接受"交战时强制 ≤60× + 结束恢复"吗？这会影响 `TimeService` 的对外语义（`scale` 被系统临时改写），需要存档记录原始倍速。
5. **引导头型别**：先做 `radar_active` 一型（P3 范围可控），还是三型一次做完？
6. **巡航路径点**：绝对位置点（好写、好校验，但目标机动后失效）还是相对时序点（Δv+hold，更真实但校验复杂）？我倾向"绝对位置点为主 + 可选 silent 标记"。

---

## 14. 明确不做

- 真实 RCS 电磁散射计算（用标量 `rcs` 特征值代替）
- 六自由度刚体姿态动力学（姿态用单位矢量 + 转向率限幅，不积分角动量）
- 破片场粒子级仿真（用引信半径 + 溅射能量近似）
- 相对论/多体摄动（CR3BP 已足够，日/木星摄动 < 1 m/1000 s）
- pork-chop 全局转移搜索（属规划层，不属交战层）


---

## 15. R6 实现对照（2026-10-22）

> 本节记录实际落地的选择，覆盖 §13 的 6 个决策点。实现以 `combat_ballistics.gd`、`combat_service.gd`、`game_session.gd`、`combat_planner.gd` 为准。

| 决策点 | 实际选择 | 说明 |
| --- | --- | --- |
| 实弹积分 | **CR3BP 旋转系 RK4 + 射击法解算** | 不是提案里的“惯性系直线 + 解析科氏”；统一积分器更简单，实弹 extra_accel=0，导弹推力/PN 作为额外加速度 |
| P2 异步化 | **接受** | `GameSession.request_fire()` 只返回 launched/projectile_ids；命中由后续 tick 的 impact 产生；probe 已改 |
| 齐射弹药不足 | **拒绝** | `insufficient_ammo`，不按余量降级 |
| 交战时间倍速 | **强制 ≤60×，结束恢复** | `COMBAT_SCALE_CAP=60`；保存原倍速并恢复 |
| 引导头型别 | **三型** | `radar_active` / `ir_passive` / `arm`；四态 SEARCH/ACQUIRE/TRACK/LOST + 滞回 |
| 巡航路径点 | **相对时序点** | `{t_s, dv_kmps}`，不是绝对位置点；`seeker_off_until_km` 支持静默接近 |

### 15.1 已落地的缺陷修复

- D1 两条交战路径：统一到 `GameSession.request_fire()` → `CombatBallistics.launch()` → 异步 impact → DamageService。
- D2 旋转系弹道：实弹/导弹统一 CR3BP RK4，子步 `1.0 s`、上限 `256`；射击法吃科氏/引力偏折。
- D3 引导头：独立飞控、PN、丢锁惯性外推、诱饵/干扰作为竞争候选，不再每步重掷。
- 齐射：N 发独立弹丸、独立散布/引导头/对抗。
- PD：按 ETA 选弹、冷却射速、单步最多 4 发，齐射饱和有意义。
- 后效：命中方位按 `damage_kind` 映射舱段；推进/储箱殉爆。
- 目标尺寸：`scenario_prologue` 已补 `radius_km`；session 对漏填场景按类型兜底。

### 15.2 仍需校准

- 设计 §13 P1 的验收写“1200 km 射击残差 <10 m”；当前实现文档记录射击法残差约 **80 m 量级**，尚未做逐场景残差断言。命中半径 80 m 时这是临界值，后续应补 `solve_aim` 残差 probe 并调迭代/步长。
- §14 的明确不做项保持不变（真实 RCS、六自由度、破片粒子、相对论、pork-chop）。
