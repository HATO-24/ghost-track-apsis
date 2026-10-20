# 完整游戏-阶段3K · ELINT / 可见光灯语服务

> 任务 task-155 + 阶段3N（task-160 动态目标注册）。工程 `game_v17`。
> 改动：`scripts/core/signal_service.gd`、`tests/signal_probe.gd`、本文件；
> 另由 game_session 包装（见 `game_session.md`）。未改旧 world/UI/bridge/core/sim；
> 不写 TrackTable/world/V15；未 commit。

## 1　定位与数据流

```
observer / stations / targets(+emissions/comms)
        │
        ├── V2InformationWarfare（被动 ELINT / COMINT：雷达/IFF/LIDAR/通信元数据）
        │
        ▼
V2SignalService
  ├─ ELINT：单站 DF(L1) / 多站交叉候选(L2) / 指纹/型号/置信度 / LPI
  ├─ COMINT：通信/数据链只给元数据；加密不解码
  ├─ 可见光灯语：内容驱动四位代码/模式/含义
  │    light_send → light_receive → light_ack / timeout / occluded / misread
  └─ observations / evidence / events / VM / JSON / save/load
        │
        ▼
上层 fusion/TrackTable 消费 evidence（本服务**不写**）；通信服务是独立通道
```

- ELINT 只给方位/指纹/候选，不自动建立 contact/航迹、不判身份；
- 多站 FIX 是 **L2 candidate**，`requires_confirmation=true`，需融合/雷达/光学确认；
- 灯语与 CommsService 区分：灯语是可见光/手动代码，不是无线电通信；
- 不写 TrackTable/world/V15/UI；`writes` 恒 false。

## 2　内容：灯语代码表（`light_codes_l1.json`）

```json
{
  "schema": "light_codes.v1", "id": "light_codes_l1",
  "defaults": {"timeout_s":30,"range_km":50,"misread_chance":0.0,
    "modes":["blink","steady"],"symbols":["0","1"]},
  "codes": [
    {"id":"APPROACH_REQ","code":"1010","mode":"blink","meaning":"请求接近",
     "category":"navigation","ack_required":true,"scenario_tags":["gushen2"]},
    {"id":"APPROACH_ACK","code":"0110","mode":"blink","meaning":"允许接近",...},
    {"id":"HOLD_POSITION","code":"0000",...},
    {"id":"IDENTITY_CHALLENGE","code":"1100",...},
    {"id":"GUSHEN2_HAIL","code":"1001","mode":"steady","meaning":"谷神-2 呼叫",...},
    {"id":"GUSHEN2_ACK","code":"0011","mode":"steady","meaning":"谷神-2 应答",...},
    {"id":"MAYDAY","code":"1111","mode":"blink","meaning":"遇险",...}
  ]
}
```

- 每个 code：**四位数字**（0/1 符号）、mode、meaning、ack_required、category、
  可选 scenario_tags（谷神-2 示例，不写剧情）；
- 校验 schema/code 非空/唯一 id/四位数字/mode 合法/meaning 非空；
- 加载失败 `ready=false` 并报错；代码表是内容数据，代码不硬编码语义。

## 3　API

```gdscript
const Signal := preload("res://scripts/core/signal_service.gd")
var s = Signal.new({
  "observer": {"id":"Obs","pos_km":[0,0,0]},
  "stations": [
    {"id":"S1","pos_km":[0,0,0],"enabled":true,"sigma_bearing_deg":1.0},
    {"id":"S2","pos_km":[1000,0,0],"enabled":true,"sigma_bearing_deg":1.0}
  ],
  "targets": [
    {"id":"E1","pos_km":[0,1500,0],
     "emissions":[{"type":"radar","model":"YW-R9","signature_name":"YW-R9",
       "active":true,"frequency_mhz":9500,"power_dbm":90,"gain_tx_dbi":30}]},
    {"id":"C1","pos_km":[0,1000,0],
     "comms":[{"from":"C1","to":"X","mode":"radio","encrypted":true,"text":"secret"}]}
  ],
  "elint": {"enabled":true,"range_km":60000,"refresh_s":1.0}
})

s.step(dt) -> VM
s.intercept(target_id="", opts={}) -> {ok,signals,comms,observations,fingerprints,reason}
s.df(target_id="") -> {ok,l1[],candidates[],single_station,multi_station}
s.resolve(fix_id_or_tx_id) -> {ok,type/status,...}

s.light_send(code_id, target_id, {timeout_s,range_km,occluded,los,misread,...})
s.light_receive(tx_id, {occluded,misread,misread_chance})
s.light_ack(tx_id) / s.resolve_light(tx_id)

# 动态目标（阶段3N）
s.upsert_target({id,entity_id,batch,side,identity,pos_km,emissions,
                 light_capable,receiver_facing,occluded,active,destroyed,...})
s.remove_target(id) / s.set_targets(rows) / s.sync_targets(rows,{replace_metadata})
s.target_ids() / s.target(id)

s.vm() / s.summary() / s.to_dict() / s.to_json()
s.events / s.events_since(seq) / s.take_events()
s.save_state() / s.snapshot() / s.load_state(json_or_dict)
```

### 3.1 ELINT 输出

- `sensor_observation.v1`：`sensor="elint"` 或 `"elint.comms"`，`level_support=1`，
  `produces_contact=false`，`level_decided=false`；含 bearing/freq/band/指纹/LPI/
  置信度；不判身份；
- `track_evidence.v1`：指纹 `evidence_type="elint"`，`support=3`，`identity="unknown"`，
  `produces_contact=false`；多站候选 `evidence_type="elint_fix"`，`support=2`，
  `requires_confirmation=true`，带 `pos_km`/`sigma_range_km`，但 `produces_position=false`；
- 通信/数据链：`sensor="elint.comms"`，只给 mode/frequency/distance/encrypted/
  metadata_only；加密内容 **不返回明文**（`content_redacted=true`）。

失败 reason：`no_emission`（静默）、`out_of_range`、`out_of_band`、`weak_signal`、
`no_signal`（无信号/未知目标）。

### 3.2 DF / 多站

- `intercept` 被动扫描；`df` 单站返回 `l1[{station,bearing,sigma,freq,fingerprint,...}]`；
- 两站及以上调用交叉：`l1` 候选 + `candidates`；`candidate=true/provisional=true/
  requires_confirmation=true`，`level_support=2`，不产生 contact/位置；
- `resolve(fix_id)` 只返回候选证据/位置/置信度，仍 `identity=unknown`；
- 单站无交叉时 `single_station=true`，`candidates=[]`。

### 3.3 灯语状态机

```text
light_send → SENT
  ├─ light_receive → RECEIVED → light_ack → ACKED
  ├─ light_receive(opts.misread) → MISREAD（received_code="????"）
  ├─ 超时（t≥expires_t）→ TIMEOUT
  └─ 遮挡 → OCCLUDED
resolve(tx_id) → 当前状态/是否待 ack
```

- 发送前置：code 存在、目标存在、距离 ≤ range_km、未显式遮挡、`los>=true`；
- 发送失败不创建 tx（返回 reason：`unknown_code/unknown_target/out_of_range/occluded`）；
- 接收前置：tx 状态 SENT、未超时；`occluded` 返回 OCCLUDED；
- `misread=true` 或按内容 `misread_chance` 确定性误读 → MISREAD；
- ack 前置：状态 RECEIVED；超时后 ack 返回 timeout；
- 所有动作产生 `signal_event.v1` 事件（`light_send/light_receive/light_ack/
  light_timeout/light_occluded/light_misread`），tx 数据结构为 `light_signal.v1`。

### 3.4 动态目标注册 / side / ACK

- 目标 schema（动态 API 归一后）：
  `id`(必填) / `entity_id` / `batch` / `side`∈{friend,neutral,hostile,unknown} /
  `identity` / `pos_km`[3 finite] / `emissions[]` / `light_capable`(默认 true) /
  `receiver_facing`(默认 true) / `occluded` / `active`(默认 true) / `destroyed`(默认 false)；
  额外字段透传（comms/模型/备注等）。
- `upsert_target`：同 id 增量更新（未提供字段保留）；非法 id/side/pos/emissions 拒绝且不改状态。
- `set_targets(rows)`：全量替换，重复 id/非法行整体拒绝（原子）。
- `sync_targets(rows,{replace_metadata:false})`：按 id 合并（新追加、已有覆盖字段但保留缺失字段）；
  `replace_metadata=true` 时对列表中的已有 id 用提供字段整体替换（未提供字段回默认）。
- `remove_target(id)` 未知拒绝；`target_ids()` 排序；`target(id)` 只读副本；动态更新同步到内部 ELINT。
- **灯语不因 side 拒绝发送**：hostile/neutral/unknown 均可 `light_send`（仍受 target 存在/距离/遮挡约束）；
  tx 记录 `target_side/target_entity_id/target_batch`。
- **ACK 由目标能力/状态决定，与 side 无关**：`light_receive` 后 `light_ack` 需要目标
  `active=true` 且未 `destroyed`、`light_capable=true`、`receiver_facing=true`；
  不满足分别返回 `target_unavailable/not_light_capable/not_facing`，状态保持 RECEIVED，
  不伪造 ACK 事件；目标被移除后 ACK 返回 `unknown_target`。

## 4　VM / 事件 / save

```text
VM schema=signal_service.v1, mode=shadow, ready, t, dt, step_count,
observer, stations, targets,
elint{signals,comms,fingerprints,misses,df_l1,candidates,observations,evidence,counts},
light{codes,codes_count,example_codes,transmissions,defaults,counts},
observations,evidence,events,warnings,errors,
writes={track_table:false,world:false,v15:false,ui:false}
```

- events schema `signal_event.v1`：`{seq,t,kind,payload,shadow,writes_v15:false}`；
  observations/evidence 也进 events；
- `save_state` JSON schema `v17.signal_service_save.v1` v1.0.0：t、**targets**、light tx、
  ELINT signals/COMINT/fingerprints/candidates/observations/evidence/events/seq；
  `load_state` 校验 schema/version/数组后恢复；旧存档缺 `targets` → 保留当前目标列表（兼容）；
  非法 targets（非数组/重复 id/非法 side）整体拒绝且不改状态；损坏/未来版本拒绝；
- JSON-safe、确定性；相同输入/命令序列 VM 逐字节一致。

## 5　接入 / 边界

- **ELINT → fusion/TrackTable**：交 `evidence`/`observations` 给上层 fusion；
  本服务不写 TrackTable、不判等级/身份；多站 FIX 必须上层确认。
- **灯语 → 通信/剧情/UI**：只输出 tx/事件；CommsService 管无线电通信，不混用；
  UI 只读 VM/tx；灯语发送/确认由上层命令/输入触发。
- 不写 world/V15；不接入真实物理姿态/遮挡几何；遮挡为显式标志/target 标记；
  ELINT 复用 `V2InformationWarfare` 的被动模型，不改其文件。
- 不实现完整 COMINT 解码（加密按设计不解码，只元数据）；
  不实现灯语自动重发/多帧纠错/视觉渲染/AI 识别；`misread_chance` 默认 0，
  需要时可配置或 opts 强制；
- 灯语 range 为直线距离，无地形/地球曲率/大气；不写剧情，谷神-2 仅代码示例；
- 动态目标只是服务内部注册表；不写 world/contact；从 world/contact 同步由 GameSession
  包装（只读 source，不双写）；ACK 能力字段由上层注册/配置提供，不推断真实平台能力。
- save/load 恢复服务输出/灯语 tx；ELINT 模型本身不序列化，恢复后 `step/intercept`
  会重新扫描（避免把模型内部状态当权威存档）。
- probe 257 checks（代码表/ELINT 单多站/指纹/LPI/COMINT/灯语全状态/JSON/save/
  确定性/不写；动态目标增删改/同步/side/ACK 能力/存档/确定性）；只单次运行，
  未跑全量回归；未 commit。

## 6　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/signal_probe.gd
# SIGNAL SERVICE PROBE RESULT: PASS=257 FAIL=0
# SIGNAL SERVICE PROBE OK（退出码 0）
```
