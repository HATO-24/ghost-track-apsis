# 完整游戏-阶段3Q · EW 效果服务（统一干扰/欺骗/假目标/EMCON/通信 spoof）

> 任务 task-166。工程 `game_v17`。新增/修改：
> `scripts/core/ew_service.gd`、`tests/ew_probe.gd`、`docs/ew_service.md`；
> 可选接入 `scripts/core/game_session.gd`、`tests/session_probe.gd`、`docs/game_session.md`。
> 不改其他；不写 world/TrackTable/UI；未 commit。

## 1　定位与数据流

```
information_warfare.gd（仅包装/兼容统一 EWEffect，不做波形/射频仿真）
        │
        ▼
V2EWService
  ├─ apply(effect) / step(dt) / expire / active / query_effect
  ├─ observation_effect → 置信度降级/延迟/无应答/假观测候选（不建 track）
  ├─ comms_effect       → 通信延迟/失败/伪造事件（不自动执行）
  ├─ transponder_effect → 伪造应答/置信度降低（不判身份、不写 transponder）
  ├─ set_emcon / lwr / laser_dazzle / decoy
  └─ vm / events / save/load / JSON / 确定性
        │
        ├─ GameSession 可选组件：tick + EventBus + 显式接口 + 存档
        └─ Sensor/Signal/Transponder 读取 effect 接口；本服务不写它们
```

- 不执行波形/射频/物理仿真；severity/持续/衰减是可测的抽象效果。
- 不写 world/TrackTable/V15/UI；`writes` 恒 false。
- 假目标/chaff/deception 只输出**假观测候选**，不直接建 track/contact。

## 2　效果模型

支持类型（`EFFECT_TYPES`）：

| effect | 类别 | 默认 target_kinds | 可观测接口 |
| --- | --- | --- | --- |
| `noise_jam` | radar | radar | 置信度↓、延迟↑、无应答概率↑ |
| `deception` | radar | radar | 置信度↓、假观测候选 |
| `chaff` | radar | radar | 假观测候选、置信度↓ |
| `false_target` | radar | radar | 假观测候选 |
| `comms_jam` | comms | comms | 延迟↑、失败率↑ |
| `comms_spoof` | comms | comms | 伪造通信/可疑事件，需确认、不自动执行 |
| `emcon` | emission | radar/iff | 主动辐射关闭；被动仍可用 |
| `lwr` | optical | optical | LWR 告警 |
| `laser_dazzle` | optical | optical/ir | 光学致盲、置信度↓ |
| `decoy` | countermeasure | radar | 假目标候选、置信度↓ |

效果 schema `ew_effect.v1`：

```json
{"schema":"ew_effect.v1","id":"EW-00001","effect":"noise_jam",
 "category":"radar","source_id":"jammer-1","target_id":"T1","band":"X",
 "target_kinds":["radar"],"severity":0.8,"initial_severity":0.8,
 "duration_s":20.0,"t_start":0.0,"t_end":20.0,"decay_per_s":0.0,
 "age_s":0.0,"remaining_severity":0.8,"active":true,
 "params":{},"requires_confirmation":false,
 "authoritative":false,"writes_v15":false}
```

- `apply` 校验 effect/source/duration；severity clamp 0..1；
- `duration_s>0` 到期；`=0` 立即在下一次 step 过期；`<0` 持久（EMCON）；
- `decay_per_s>0` 时 `remaining_severity` 线性衰减；到 0 自动过期；
- `step` 推进 t/衰减/过期，事件 `ew_expired`；`expire(id/"")` 手动过期；
- `active/query_effect` 只读；query 可按 effect/target/kind 过滤。

## 3　API

```gdscript
const EW := preload("res://scripts/core/ew_service.gd")
var e = EW.new({"observer":{"id":"own","pos_km":[0,0,0]},
  "targets":[{"id":"T1","pos_km":[100,0,0]}]})

e.apply({effect, source_id, target_id, band, severity, duration_s,
         decay_per_s, params}) -> {ok,effect,reason,writes}
e.step(dt) -> {ok,t,effects,counts,events}
e.expire(effect_id="") -> {ok,expired}
e.active(target_id="", kind="") -> Array
e.query_effect(effect_type="", target_id="", kind="") -> {...}
e.observation_effect(target_id="", sensor_kind="radar") -> {...}
e.comms_effect(target_id="") -> {...}
e.transponder_effect(target_id="") -> {...}
e.sensor_effect(...)  # 别名 observation_effect
e.set_emcon(on) -> {...}
e.vm() / e.summary() / e.to_dict() / e.to_json()
e.events / e.events_since(seq) / e.take_events()
e.save_state() / e.snapshot() / e.load_state(json_or_dict)
```

失败 reason：`invalid_payload/invalid_effect_type/missing_source/invalid_duration/
unknown_effect/no_ew_service` 等；失败不改其他效果。

### 3.1 observation_effect

```json
{"schema":"ew_observation_effect.v1","target_id":"T1","sensor_kind":"radar",
 "jammed":true,"noise_severity":0.8,"deception_severity":0.7,
 "false_observations":[{"candidate_id":"EWC-...","fake":true,
   "identity":"unknown","confidence":0.6,"requires_confirmation":true}],
 "confidence_mult":0.52,"confidence_degraded":true,"delay_s":4.8,
 "no_reply_chance":0.4,"dazzled":false,"lwr_alert":false,
 "requires_confirmation":true,"produces_contact":false,
 "writes_track_table":false}
```

- 假观测候选只读；调用方必须确认/融合后才可建 track；
- 不返回敌对身份/contact。

### 3.2 comms_effect / transponder_effect

- `comms_effect`：`{jammed,latency_add_s,failure_chance,spoofed,spoof_text,
  spoof_events,suspicious,requires_confirmation,auto_execute:false}`；
- `comms_spoof` 文本/呼号可疑，**不自动执行**，需玩家/审计确认；
- `transponder_effect`：`{reply_forged,confidence_mult,spoof_severity,
  identity:"unknown",hostile:false,requires_confirmation}`；不写 transponder/不判敌。

## 4　GameSession 可选接入

```gdscript
var session = GameSession.new({"ew_service": {
  "observer": {"id":"own"}, "targets":[{"id":"T1","pos_km":[100,0,0]}]
}})
session.tick(1.0)                       # ew_service.step + EW 事件进 EventBus
session.apply_ew({"effect":"noise_jam","source_id":"jammer",
  "target_id":"T1","severity":0.8,"duration_s":20})  # 记录 log，可 replay
session.ew_active("T1") / session.ew_vm()
session.ew_observation_effect("T1") / session.ew_comms_effect("T1")
session.ew_transponder_effect("T1")
session.set_ew_emcon(true)
```

- 未配置 `ew_service` 时：`ew_service=null`，相关 API 返回 `no_ew_service`，
  session 其他组件不受影响；
- tick 返回 `components.ew=true`、`ew_step`；EW 事件以 `ew.<kind>` 发 bus；
- snapshot 顶层 `"ew"` 为 VM；save 嵌入 `"ew_service"` JSON；
  load boot+log 重放后恢复 EW 快照（旧存档缺字段 → 组件退化兼容）；
- `apply_ew`/`set_ew_emcon` 记录操作日志，支持 replay。

## 5　与真实 EW 的差异 / 边界

- 不实现波形、射频链路、天线增益、频率捷变、ECCM/烧穿、旁瓣、脉冲压缩；
  severity/band 为抽象输入，`information_warfare` 只作统一 EWEffect 包装。
- 不模拟真实欺骗信号/假目标回波物理；假目标只给候选，需上层确认。
- 通信 spoof 不生成真实协议报文/不解密；只给可疑文本/事件，不自动执行命令。
- 不写 world/TrackTable/transponder/sensor/UI；调用方消费 effect 接口决定降级。
- EMCON 为服务内效果与 `emcon_active` 标志；不直接关闭外部传感器；上层需读接口。
- 存档为内存 JSON（不含波形/随机种子状态）；确定性靠输入序列/固定规则。
- probe 252 checks：十种效果、持续/衰减/过期、观测/通信/应答机接口、EMCON、
  Session tick/bus/存档、JSON/确定性；只单次运行，未跑全量回归。
- 未 commit；未改其他文件。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/ew_probe.gd
# EW PROBE RESULT: PASS=252 FAIL=0
# EW PROBE OK（退出码 0）
```

Session 回归：

```powershell
# V17 SESSION PROBE RESULT: PASS=1001 FAIL=0
```
