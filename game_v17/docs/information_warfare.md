# R5-INFO-1 · 统一信息作战模型（IFF / ELINT / COMINT / EW）

> 任务 R5-INFO-1（task-75）。工程 `game_v17` framework/sim。
> **统一模型、shadow 语义**：只计算 advisory / 证据 / 效果事件，写自己的只读 VM；
> **不写 TrackTable / V15 state、不接 UI/HUD/bridge、不自动判敌**。

## 1　文件

| 文件 | 作用 |
| --- | --- |
| `framework/sim/information_warfare.gd`（新） | `V2InformationWarfare`：IFF 状态机 + ELINT/COMINT 被动侦察 + EW 效果结算 + 单一事件总线 + 只读 VM |
| `tests/info_warfare_probe.gd`（新） | headless probe：**INFO WARFARE PROBE RESULT: PASS=456 FAIL=0** |
| `docs/information_warfare.md`（本文件） | 模型、字段、事件 schema、切换关系、边界 |

未改 core/ui/bridge/state/project、现有 sim 模型；未 commit。

## 2　总原则

- `mode="shadow"`、`authoritative=false`、`writes={track_table:false,v15:false}`；无 tracks/world/TrackTable 依赖，无写 API。
- **身份不是敌我开关**：IFF/ELINT/COMINT 只产出 `identity_evidence` / 信号 / 内容；`identity` 只可能是
  `friend` 或 `unknown`；没有任何路径输出 `hostile`；`hostile_allowed=false`。
- **ELINT/COMINT 不产生接触**：单站 ELINT 只有信号（`produces_contact=false`），多站只给
  `SIGNAL FIX` 候选（`candidate/provisional`，需融合/雷达/光学/指挥确认）；COMINT 完全不产生位置/等级。
- **EW 全部走单一事件总线**：效果是 `EWEffect`（`ew_effect.v1`）→ `events[]`；
  `radar_effect()` / `comms_effect()` / `optical_effects()` 由模型统一结算；
  不维护第二套威胁/环境，不写独立 EW 脚本。
- 无随机源：同一输入/时间/操作序列 → VM/事件逐位确定，可回放。

## 3　输入

```gdscript
var iw = V2InformationWarfare.new()
iw.setup({
  "observer_id": "harmattan",
  "observer": {"id":"harmattan","pos_km":[...],"emcon":false,
               "damage":{"sensors":1.0,"comms":1.0}},
  "targets": [{
      "id":"F1","name":"友舰","pos_km":[0,1000,0],
      "transponder":"ok|off|faulty|captured",
      "registered":true,"registry_match":false,
      "crypto_epoch":"epoch-1","reply_delay_s":0.2,
      "iff_codes":{"1":"M1","2":"M2","3/A":"CMP1234","C":"25000","S":"A1B2C3","5":"FRIEND5"},
      "alt_ft":25000,
      "emissions":[{"model":"YW-R9","type":"radar","active":true,"silent":false,
                    "lpi":false,"spoof":false,"frequency_mhz":9500,
                    "power_dbm":90,"gain_tx_dbi":30,"prf_hz":1200,
                    "pulse_width_us":1.2,"scan_period_s":6}],
      "comms":[{"from":"F1","to":"F2","mode":"radio","text":"...",
                "encrypted":false,"frequency_mhz":300}]
  }],
  "stations": [{"id":"A","pos_km":[0,0,0],"sigma_bearing_deg":1.0},
               {"id":"B","pos_km":[5000,0,0],"sigma_bearing_deg":1.0}],
  "advisory_contacts": [{"id":"F1","track_id":"T2001","batch":"2001"}]
})
iw.step(1.0)   # 时间推进 + ELINT/COMINT 扫描 + EW 过期 + 告警
```

- IFF 默认 `MK-12`（2,000 km / 2 s 周期 / 冷却 2 s / Mode 库 `iff_cfg.library`）。
- ELINT 默认 `ELINT`（60,000 km、灵敏度 −90 dBm、噪声 −110 dBm、SNR 门限 10 dB、测向 σ=1°）。
- COMINT 使用同一接收机（radio 120,000 km；激光散射 7,700 km）。
- `advisory_contacts` 用于 IFF/ELINT 关联（按 `id/track_id/entity_id/batch` 匹配），
  结果字段 `track_id/batch/advisory_linked`；不修改 advisory。

## 4　IFF（MK-12）

### 4.1　模式

`1`、`2`、`3/A`、`C`、`S`、`5`（加密）；`normalize_mode()` 接受 `3A/III/M1/M2/M3/M4/Mode 5` 等写法。

### 4.2　状态机

```
idle → interrogating → waiting_reply(≤2 s)
     → resolved(reply_ok | no_reply | faulty_transponder | wrong_code |
                captured | crypto_mismatch | timeout | out_of_range | blocked | invalid_mode)
     → cooldown(2 s) → idle
```

每次结果带 `state_history`（idle/interrogating/waiting_reply/resolved/cooldown）与 `cooldown_s`。

### 4.3　身份铁律（docs/38 §4.4/§6.2）

| 结果 | identity | level_support | 说明 |
| --- | --- | --- | --- |
| reply_ok + 注册库/编队链路确认 | `friend` | 4 | 唯一 L4 路径；仍不是开火授权 |
| reply_ok + 未注册 | `unknown` | 0 | 应答正确 ≠ 友军 |
| no_reply / faulty / timeout / out_of_range / blocked / cooldown | `unknown` | 0 | 不明 ≠ 敌意 |
| wrong_code | `unknown` | 0 | 不直接 hostile |
| captured（缴获/复制码） | `unknown` | 0 | `confidence≤0.5` + `spoof_flags=["captured_code"]` |
| crypto_mismatch（Mode 5） | `unknown` | 0 | 不泄露是否为敌 |
| invalid_mode | `unknown` | 0 | 入参错误，不判敌 |

- **IFF 不产生位置/接触**：`produces_contact=false`、`produces_position=false`、`bearing_deg=-1`、`range_km=-1`；
  只写 `identity_evidence`（L4 证据）。
- 询问即暴露：`expose_self`（ELINT 4,000 km / 12 s 可定位 / weight 0.6），同时发 `exposure.fix` 事件。
- `never_hostile=true`、`hostile_allowed=false`；probe 逐条断言 identity ∈ {friend, unknown}。

### 4.4　API

```gdscript
iw.interrogate_iff(target_id, modes := null, opts := {}) -> iff_result.v1
iw.iff_state(target_id) / iw.iff_all()
```

## 5　ELINT（被动截获）

### 5.1　链路预算（自由空间）

```
FSPL(dB) = 20 log10(4πR/λ)
P_r(dBm) = P_t + G_t + G_r − FSPL − L
SNR(dB) = P_r − N_floor
detected = (SNR ≥ threshold) 且 (distance ≤ effective_range) 且 (频段在 0.5–18 GHz)
```

- 默认：`P_t` radar 90 dBm / IFF 60 / radio 60；`G_t` 30 dBi（radar）/6 dBi；
  `G_r=6 dBi`；`L=3 dB`；`N_floor=−110 dBm`；`threshold=10 dB`；`pd = logistic((SNR−threshold)/4)`。
- `effective_range = 60,000 km × (LPI ? 0.5 : 1)`；LPI 再扣 6 dB SNR、测向 σ×2。
- 静默/未发射 → 无信号，记 `misses.reason=no_emission`；超距/弱信号/频段外记录 miss。
- 指纹库：`YW-R9/KD-R6/MS-R4/SC-R2/CH-R0/MK-12/MS-L2`；匹配 → `signature/class_hint/confidence`，
  `level_support≤3`（**ELINT 永不写 L4**）；未知特征 confidence 低；`spoof=true` → `spoof_flags=["spoofed_signature"]`、不支撑等级。

### 5.2　单站铁律

`EmitterSignal.v1` 单站输出只有方位：`range_km=-1`、`produces_contact=false`、`is_contact=false`、
`fix_candidate=false`；不产生航迹/等级/身份。

### 5.3　多站交叉（SIGNAL FIX 候选）

```gdscript
IW.triangulate_signals(sig_a, sig_b, opts) -> signal_fix_candidate.v1
iw.triangulate_all()
```

- 门限：不同站、同 source、时间差 ≤`max_time_skew_s`(2 s)、指纹一致（非空时）、
  基线 ≥`min_baseline_km`(200 km)、交叉角 ≥`min_cross_angle_deg`(10°)、
  交叉误差 ≤`fix_gate_km`(300 km)；
- 失败返回 `ok=false, candidate=false, reasons=[needs_two_stations|time_skew|fingerprint_mismatch|
  baseline_too_short|cross_angle_too_small|fix_error_exceeds_gate|...]`；
- 通过返回 `candidate=true, provisional=true, produces_contact=false, is_contact=false,
  requires_confirmation=true, level_support=2, level_cap="L2_candidate_only"`；
  `pos_km/covariance/baseline/cross_angle/sigma_range` 供融合/指挥确认；
- 只有候选，**不自动成为接触**，不写 identity/L4/hostile。

## 6　COMINT（与 ELINT 分离）

- 输入通信发射事件（`from/to/mode/text/encrypted/frequency_mhz`）；被动接收距离 radio 120,000 km、
  lasercom 散射 7,700 km。
- 输出 `comms_observation.v1`：`produces_contact=false`、`level_support=0`、无位置；
- **加密不自动解码**：`encrypted=true` → `comms_content.text=""`、`metadata_only=true`、
  `decode_attempted=false`；只给元数据/流量分析；`SECRET` 等明文绝不泄漏；
- 明文内容由调用方脚本提供（模型不“解码”）；同一发射去重，不重复事件。
- 事件类型 `comms.link`，与 ELINT `emitter.signal` 分开。

## 7　EW（统一 EWEffect + 事件总线）

### 7.1　效果类型

`noise_jam`（噪声干扰）、`deception` / `false_target`（欺骗/假目标）、`chaff` / `decoy`（箔条/诱饵）、
`comms_jam`（通信干扰）、`comms_spoof`（通信欺骗）、`emcon`（静默）、`lwr`（激光告警）、
`laser_dazzle`（激光致盲）。

### 7.2　结算公式

- 噪声干扰：`jam_factor = 1 − jamming × (1−0.30) × (1−jamming_resist)`；
  `R_eff = base × jam_factor`，有效半径不低于 30% 基准（`floor_radius`）；
  例：jamming=0.7、resist=0.2 → **0.608**（R_eff 30,000→18,240 km）；jamming=1、resist=0 → **0.30**。
- 通信干扰：radio `latency = 2 + 38×jamming`（0/0.5/1 → **2/21/40 s**），
  `packet_loss = 0.9×jamming`；激光链路不受 radio 干扰（`laser_immune=true`），但需要 LOS。
- 假目标/欺骗/箔条/诱饵：生成 `phantom_candidate.v1`，`phantom=true`、`level=0`、`identity=""`、
  `produces_contact=false`、`threat="none"`；不自洽证据
  `range_power_mismatch/no_maneuver_history/no_thermal_signature`；
  `cross_validate_phantom(id, confirmed_by)` 可由光学/雷达交叉验证移除；**永不产生真实航迹/等级/身份**。
- 通信欺骗：生成 `suspicious_commands`，`requires_confirmation=true`、`applied=false`、
  `no_auto_decision=true`；只告警，不自动改变裁决/命令。
- EMCON：`set_emcon(true)` → 主动 IFF 关闭、主动传感器降级，被动 ELINT/COMINT 继续；
  切换有 `emcon_settle_s`（1.5 s），不删已有身份/信号证据，不写 V15。
- 激光致盲/LWR：`optical_effects()` 输出 `dazzled/optical_blocked`；LWR 只给告警方位（±10°），
  不产生接触。

### 7.3　API

```gdscript
iw.apply_ew_effect({effect, source_id, target_id, severity, duration_s, target_kinds, params})
iw.inject_noise_jamming(src, target, severity, duration)
iw.inject_comms_jamming(src, target, severity, duration)
iw.inject_deception(src, target, severity, duration, phantom_count)
iw.inject_false_target(src, target, count, duration) / inject_chaff(...)
iw.inject_comms_spoof(src, target, text, duration)
iw.inject_laser_dazzle(src, target, severity, duration)
iw.set_emcon(on)
iw.radar_effect(base_range_km, jamming_resist)
iw.comms_effect(mode, base_latency, los)
iw.optical_effects() / iw.environment_effects() / iw.emcon_state()
iw.cross_validate_phantom(id, confirmed_by)
iw.active_effects(target_id, kind)
```

`environment_effects()` 可直接喂给 `SensorAuthority` 的 snapshot/环境：
`{jamming, comms_jamming, radar, comms, optical, emcon}`；由 sensor_authority 读取，不反向写。

## 8　事件总线（schema event.v1）

```json
{
  "schema": "event.v1", "seq": 42, "t": 2.0,
  "type": "emitter.signal|iff.reply|exposure.fix|comms.link|ew.effect",
  "source": "sim/information_warfare.shadow",
  "entity_id": "harmattan", "target_id": "F1",
  "severity": "info|warn|critical",
  "payload": { ...对应 iff_result/emitter_signal/comms_observation/ew_effect... },
  "authority": "shadow", "consumers": ["core.event_bus","state.adapter","hud.log","replay.recorder"],
  "shadow": true
}
```

- 所有 IFF/ELINT/COMINT/EW 事件走同一 `events[]`（最多 1,000 条），`seq` 单调递增；
- `events_since(since_t, types)` 可查询；payload 为对应 schema 的副本；
- `alerts[]`：身份不明/加密通信/通信欺骗/phantom/LWR/EMCON 等告警；
  每条 `no_hostile_determination=true`，文本不自动判敌。
- 时间/输入固定 → 事件序列确定，可回放。

## 9　VM（只读，JSON）

```gdscript
iw.vm_information_warfare() == iw.to_dict()
```

顶层字段：

- `schema="information_warfare.v1"`、`mode="shadow"`、`authoritative=false`、`ready`、`t`、`observer`、`mounts`；
- `iff`：`{available, model, range_km, results[], by_target, summary{friend/unknown/hostile:0}, hostile_allowed:false}`；
- `elint`：`{state{enabled,model,range_km,snr_threshold_db,stations}, signals[], misses[],
  fix_candidates[], summary{signals,stations,fix_candidates,detected_contact:0}, single_station_contact:false,
  elint_level_cap:"L3_fingerprint_evidence_only"}`；
- `comint`：`{events[], summary, produces_contact:false, auto_decode:false}`；
- `ew`：`{effects[], active_count, radar, comms, optical, emcon, phantom{candidates,active,
  produces_real_track:false}, suspicious_commands[], summary}`；
- `effects`（当前生效 EWEffect 列表）、`events[]`、`alerts[]`、`advisory_contacts`、`summary`；
- `summary`：IFF friend/unknown/hostile=0、signals、fix_candidates、comint、effects、events、alerts、
  phantom、suspicious_commands、`hostile_auto_determination=false`；
- `writes={track_table:false,v15:false}`、`shadow{mode,authoritative,never_auto_hostile,...}`；
- 所有字段 JSON 安全（无 Vector3；`bearing/range` 单位 km/deg）。

## 10　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/info_warfare_probe.gd
# 末行 INFO WARFARE PROBE RESULT: PASS=456 FAIL=0 / INFO WARFARE PROBE OK，退出码 0
```

覆盖（11 节，451+ 断言）：
1. 初始化/模式/writes/输入归一；
2. IFF 全状态：reply_ok/未注册/无应答/故障/缴获码/错码/Mode5 crypto/超时/超距/非法模式/冷却；
   Mode 1/2/C/S/3A 多模式；advisory 关联；不产生位置/接触、identity 仅 friend/unknown、hostile=0；
3. IFF 门控：EMCON/mount disabled/sensor damage；
4. ELINT 链路预算、指纹匹配/未知/伪造、静默 no_emission、LPI 半程/σ×2、单站 0 接触；
5. 多站 SIGNAL FIX 候选 + 所有门限（同站/时间差/指纹/基线/误差）；
6. COMINT：明文可读 / 加密仅元数据不解码 / lasercom 散射范围 / 去重；
7. EW：噪声因子 0/0.7/1、R_eff/下限、通信延迟 2/21/40/丢包/激光免疫/LOS、phantom/交叉验证、
   通信欺骗需确认、LWR/致盲、效果过期；
8. EMCON：主动关/被动继续/settle/环境效果；
9. 事件总线：schema/seq 单调/types/payload/events_since/告警不判敌；
10. VM/JSON/不写 TrackTable：TrackTable 签名不变、无 tracks 字段、hostile=0；
11. 确定性：两实例 vm/events/signals/iff/phantom 逐位一致。

## 11　与 sensor_authority / R5.6 的关系

- `SensorAuthority`（task-73 shadow）负责雷达/TWS/VIS/IR 的观测与 compare；
  本模型负责 IFF/ELINT/COMINT/EW 的身份证据、信号与效果；
- R5 接入时由 `SensorAuthority` 读取 `information_warfare.environment_effects()`（jamming/comms/optical/emcon）
  形成 EnvironmentFrame，再调用 V2 传感器模型；本模型不写环境/世界；
- `iff.reply` / `emitter.signal` / `comms.link` / `ew.effect` 事件进入未来 core EventBus，
  由唯一权威（R5.6 `v2_authoritative`）的 TrackTable 消费；本任务**不实现** authoritative，
  也不写 TrackTable/V15；任何身份/等级/威胁写入留给 R5.6 的 core 融合；
- `advisory_contacts` 关联只读；不修改 sensor_authority 的输出。

## 12　限制 / 未完成

- 本模型是 shadow 规则模型：IFF 2,000 km、ELINT 60,000 km、link budget 参数为文档/内容基线；
  不做真实电磁传播/多径/地形/大气吸收。
- IFF 同步解析（无异步 2 s 等待的真实队列）：用 `state_history`/`reply_delay`/`timeout` 表达流程；
  `reply_delay` 超时仅作状态判定，不阻塞主循环。
- 仅内置 7 个信号指纹；ELINT 不写 L4/敌意；多站候选需后续融合/指挥确认。
- COMINT 不解密、不做内容语义/自然语言分析；明文依赖调用方脚本提供。
- EW 为效果模型：phantom 不产生真实航迹；通信欺骗不自动执行；不接武器/伤害/制导。
- 不接 UI/HUD/bridge/state；不做 ELINT/EW 独立窗口、回放接入（后续 R5 UI/任务）。
- 不写 TrackTable/V15；不自动判敌；hostile 仅允许在 R5.6 由具备证据/授权的 core 融合产生。
