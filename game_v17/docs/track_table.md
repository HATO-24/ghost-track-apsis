# 完整游戏-阶段2F/2G · TrackTable 单写者 / 观测·证据融合 / 快照恢复

> task-124（单写者融合）→ **task-127（save/load 快照）**。工程 `game_v17`。
> **只新增/修改 3 个文件**：
> `scripts/core/track_table.gd`、`tests/track_table_probe.gd`、`docs/track_table.md`。
> 未改旧 HUD/state/bridge/core/sim/project、未改现有
> `framework/core/track_table.gd`/`tracks.gd`；不接传感器/物理/UI；不写 V15；未 commit。
>
> 依据：[`docs/06_传感器与信息作战.md`](../docs/06_传感器与信息作战.md) §1/§2/§6、
> [`docs/09_系统架构与数据契约.md`](../docs/09_系统架构与数据契约.md) §5 DbC。

## 1　定位

`V2FusedTrackTable`（`scripts/core/track_table.gd`，与现有 `V2TrackTable` 类名不同）
是**单一权威融合层骨架**：

```text
Observation / Evidence / TrackUpdate 事件
        │ 仅 writer_id（sensor/fusion authority）可写
        ▼
V2FusedTrackTable（single writer）
        │
        ▼
只读 VM：tracks / filter / selected / summary / events
```

- 传感器/UI 不得直接改 TrackTable；UI 只能读 VM/订阅只读事件；
- 观测自动融合**最高 L2**；L3/L4 必须显式 Evidence（光学/ELINT 分类、IFF、人工等）；
- 身份六级；**不明不判敌**，hostile 只在显式 authoritative/玩家授权时写；
- 不接真实传感器/物理/世界，不写 V15。

## 2　单写者

- 初始化 `setup({"writer_id": "..."})`，默认 `fusion_authority`；
- `claim_writer(id)`：首次可 claim；之后不同 writer 一律 `writer_conflict`；
- 所有写入口 `handle_event/handle_observation/handle_evidence/handle_track_update`
  必须传当前 `writer_id`，否则 `unauthorized_writer`；
- `subscribe(Callable)` 只读事件订阅（收到副本）；`unsubscribe`；
- VM/filter/selected 等全部只读，无 UI 写 API。

## 3　Track schema

```text
{
  schema: "fused_track.v1",
  id/track_id, batch, entity_id,
  level: 1..4, level_name, level_evidence{level: t},
  identity: unknown|assumed_friend|friend|neutral|suspect|hostile,
  identity_label, threat: none|unknown|suspect|hostile,
  sources[], quality: 0..1,
  created_t, last_update, stale,
  evidence[], evidence_ids[], merged_from[],
  bearing_deg, range_km
}
```

- **等级**：L1 方位 / L2 定位 / L3 分类 / L4 识别；只增不减（DbC）。
- **身份六级**：`unknown / assumed_friend / friend / neutral / suspect / hostile`；
  默认 `unknown`。
- **威胁**：`none / unknown / suspect / hostile`；默认 `none`。
  `hostile` 身份/威胁必须 `authoritative=true`、`explicit_hostile=true` 或
  source∈`manual/player/authority/command`；否则拒绝 `hostile_requires_authority`。
- **证据**：每条 `{evidence_id,seq,type,sensor,support,t,quality,source,identity,threat,detail}`；
  上限 100；`evidence_ids` 可追溯；等级变化另有 level evidence。
- `age` 由 `tick`/VM 的 `t` 计算；`stale` 由过期策略标记。

## 4　输入事件

### 4.1 Observation `sensor_observation.v1`

```json
{"schema":"sensor_observation.v1","kind":"observation",
 "event_id":"...", "t":12.0, "sensor":"radar|radar.tws|optical|ir|elint|crossfix|datalink|visual",
 "track_id":"", "entity_id":"E1", "batch":"2001",
 "support":1, "quality":0.8, "range_km":1000, "bearing_deg":45}
```

- 需 `track_id/entity_id/batch` 至少一个；
- `support` 必须 1..2；**>2 拒绝**（L3/L4 只能 Evidence）；
- 单观测→L1；多观测/多源/datalink→L2；同 entity/batch 合并同一 track；
- 只更新观测证据，不写身份/威胁（除非显式 evidence）。

### 4.2 Evidence `track_evidence.v1`

```json
{"schema":"track_evidence.v1","kind":"evidence","event_id":"...",
 "t":13.0, "track_id":"T0001", "evidence_type":"optical|elint|iff|datalink|visual|manual|database",
 "support":3, "source":"optical", "identity":"friend",
 "iff":{"status":"friend"}, "threat":"none", "detail":"..."}
```

- 目标 track 必须已存在（`unknown_track`）；
- 默认支持：optical/elint/database →3；iff/datalink/visual/manual →4；
  可显式 `support` 1..4；等级只增不减；
- IFF 状态映射：friend→friend；neutral→neutral；no_reply/faulty/wrong/crypto→unknown；
  captured→suspect；**不自动 hostile**；
- 非法身份/威胁先拒绝，拒绝时**不部分写入**等级/身份；
- 证据追加并去重（同 type/sensor/support/t 连续重复不重复追加）。

### 4.3 TrackUpdate `track_update.v1`

```json
{"schema":"track_update.v1","kind":"track_update","t":14.0,
 "track_id":"T0001", "level":4, "identity":"neutral", "threat":"suspect",
 "quality":0.9, "sources":["datalink"]}
```

- 仅融合 authority writer；
- `level` 不得降到当前以下（`level_regression`）；
- identity/threat 同校验；hostile 需授权；
- 目标必须存在。

## 5　融合 / 去重 / 合并 / 过期

- **L1→L2**：单个 observation 为 L1；第二个不同 source 或 `support=2`/datalink →L2。
- **L3/L4**：只能由 Evidence/TrackUpdate 提升；observation 不可能高于 L2。
- **去重**：
  - `event_id` 重复 → `duplicate_event`，不重复改变状态；
  - 同 `entity_id`/`batch` 的 observation/evidence 归并到同一 track；
  - 连续重复证据（type/sensor/support/t 相同）不重复追加。
- **合并**：`merge_duplicates()` 合并同 entity/batch 航迹，保留最早 id，
  等级取高、sources/证据合并、`merged_from[]` 记录来源。
- **过期**：
  - `tick(dt)` 后 age≥`stale_after_s` → `stale=true`（等级不降）；
  - age≥`forget_after_s` → 移除并 emit `track_forgotten`；
  - `advance(now)` 时间回归拒绝；`tick` 不倒退。
- 默认 `stale_after_s=30`、`forget_after_s=300`；可 setup 覆盖
  （`forget_after_s>=stale_after_s`）。

## 6　API

```gdscript
const TT := preload("res://scripts/core/track_table.gd")
var s = TT.new({"writer_id": "fusion", "stale_after_s": 30.0,
    "forget_after_s": 300.0, "max_tracks": 256})

s.handle_event(event, writer_id) -> {ok,reason,...}
s.handle_observation(obs, writer_id) / s.handle_evidence(evidence, writer_id)
s.handle_track_update(update, writer_id)
s.claim_writer(id) / s.current_writer()
s.subscribe(Callable) / s.unsubscribe(Callable)
s.tick(dt) / s.advance(now)
s.merge_duplicates()
s.find(track_id) / s.all_tracks() / s.active_count()
s.filter({level_min,level_max,identity,stale,source,batch,id})
s.selected(track_id) / s.summary()
s.vm({filter:{},selected_id:""}) / s.to_dict() / s.to_json()
s.events / s.events_since(seq) / s.take_events()
s.snapshot() / s.save_state() / s.save_payload()
s.load_state(json_or_dict) / s.restore(...) / s.load_save_payload(...)
```

事件 schema `fused_track_event.v1`：`{schema,seq,t,action,track_id,level,identity,
threat,input,evidence_id,reason,detail,level_after,shadow,writes_v15:false,...}`；
拒绝事件也进 events。

## 7　只读 VM

`vm(opts)` 返回：

```text
schema=fused_track_table.v1, mode=single_writer, ready, t, writer_id,
tracks[]（可按 filter 过滤）, all_count, filter, selected,
summary{tracks,active,stale,by_level,by_identity,evidence},
events[], warnings[], errors[], writes={track_table:false,v15:false}
```

- `filter` 支持 level_min/level_max/identity/stale/source/batch/id；
- `selected` 只读 track copy；
- UI 复制 VM 后修改不会影响内部（probe 已断言）；
- 全部 JSON 可序列化、确定性、只读。

## 8　DbC

| 入口 | Preconditions | Postconditions / Invariants |
| --- | --- | --- |
| `setup` | writer_id 非空；stale/forget/容量合法 | ready；配置确定；不写外部 |
| `claim_writer` | 单写者冲突时拒绝 | 只有当前 writer 可写 |
| `handle_*` | schema/kind、t 有限且不倒退、writer 匹配 | 合法事件更新；非法 `{ok:false,reason}` |
| Observation | sensor/support/key 合法；support≤2 | L1/L2；去重；不自动身份/敌意 |
| Evidence | type/support/identity/threat 合法；track 存在 | L3/L4；拒绝不部分写入；证据可追溯 |
| TrackUpdate | 仅 writer；目标存在；等级不倒退 | 更新；level 不降 |
| `tick/advance` | dt≥0/now 单调 | stale/forget；等级不降；时间单调 |
| `vm/filter/selected` | 只读 | 返回副本；无内部修改 |

违反契约一律返回 `ok=false` + `reason`，并写 `errors`，不静默吞错。

## 9　Save / Load 快照（task-127）

### 9.1 schema

`save_state()` 返回 JSON 字符串；`snapshot()`/`save_payload()` 返回同内容 Dictionary：

```text
{
  "schema": "v17.fused_track_table_save.v1",
  "version": "1.0.0",
  "table_schema": "fused_track_table.v1",
  "t": 12.0,
  "writer_id": "fusion",
  "config": {writer_id/stale_after_s/forget_after_s/track_id_prefix/...},
  "tracks": [完整 track：level/identity/threat/sources/evidence[]/evidence_ids[]/
             level_evidence/merged_from/stale/last_update/...],
  "next_id": 3,
  "event_seq": 17,
  "seen_event_ids": ["..."],   // event_id 去重表
  "events": [完整 fused_track_event.v1],
  "outbox": [...],              // 未 take 的只读事件
  "errors": [], "warnings": []
}
```

### 9.2 API

```gdscript
var text: String = s.save_state()          # JSON + version
var dict: Dictionary = s.snapshot()        # same payload as Dictionary
var r := TrackTable.new()
var res: Dictionary = r.load_state(text)   # or dict/restore/load_save_payload
# {ok, reason, version, from_version, migrated, tracks, events, ...}
```

- `load_state` 先完整校验再应用；失败不改当前状态（probe 断言）；
- 保存/恢复 `tracks/evidence/events/事件序号/seen_event_ids/writer/config/
  stale/forget/last_update`，因此：
  - 恢复后 `vm()` 与原状态一致；
  - `event_id` 去重仍有效；
  - stale 状态、下次 forget 过期继续；
  - 新 track id / event seq 从保存点继续；
- 整数契约（level/seq/next_id/track_id_pad/max_tracks/support/level_after 等）
  在 JSON 解析后归一为 int，保证 VM/save 往返一致。

### 9.3 版本 / 迁移 / 校验

- 当前 `version=1.0.0`；`schema/table_schema/version` 必须匹配；
- **未来版本拒绝** `unsupported_future_version`；**旧版本拒绝**（当前无迁移路径，
  reason 可见），不静默加载；
- 缺 config/tracks/seen/events、非有限 t、非法 writer、level/identity/threat/
  quality、重复 track id、损坏 JSON 均拒绝；
- 加载成功不写 UI/world/V15；不触发 tick/过期逻辑，只恢复状态。
- **SaveService / GameSession 兼容**：`save_state()` 是普通 JSON 字符串，可放入
  `SaveService` 的 `session_save` payload 或 GameSession 扩展组件；
  本表不直接读写磁盘、不修改 SaveService。probe 用 SaveService encode/decode
  验证该 JSON 可嵌入/恢复。

## 10　验证（单次 probe）

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/track_table_probe.gd
# TRACK TABLE PROBE RESULT: PASS=153 FAIL=0
# TRACK TABLE PROBE OK（退出码 0）
```

覆盖（153 checks，含原 113 + 快照）：
- **单写者**：writer claim/冲突/未授权拒绝/订阅只读；
- **L1→L4**：单观测 L1、多源 L2、光学/ELINT Evidence L3、IFF L4；证据追溯；
- **身份/威胁**：六级、IFF no_reply→unknown 不判敌、非授权 hostile 拒绝、
  authoritative hostile 接受、拒绝不部分写入、TrackUpdate 身份/威胁、等级不倒退；
- **去重/合并/过期**：event_id 去重、同 batch 合并、显式 merge（取高等级/merged_from）、
  stale/forget、时间回归拒绝；
- **DbC**：缺 schema/未知 schema/无标识/坏 sensor/support/观测 L3/坏 evidence/
  未知 track/非有限 t 全部拒绝；非法 setup 不 ready；
- **快照**：save_state schema/version、payload 字段、dict/snapshot 别名、
  load 后 VM/save_state 一致、evidence/level/stale/writer/t 保留、
  event_id 去重保留、Continue ID/seq、dict 形式加载、save/load 往返确定性、
  SaveService encode/decode 兼容、恢复后 stale/forget 继续；
  损坏 JSON/坏 schema/future/old version/缺 tracks/非法 level/重复 track id 拒绝
  且不破坏当前状态；
- **VM/JSON/确定性**：filter/selected/summary、只读 copy、writes=false、两实例
  VM/events 逐字节一致；JSON-safe。

## 11　边界 / 未完成

- 不接真实传感器/物理/世界；输入 Observation/Evidence/TrackUpdate 由上层提供，
  本层只做融合/唯一写。
- 不修改现有 `framework/core/track_table.gd`/`tracks.gd`；新类独立、类名
  `V2FusedTrackTable`。未接旧 world/bridge/HUD。
- 不实现 UI、ROE、身份数据库、通讯链路；hostile 仅授权标记，不自动判敌。
- 证据去重只做“连续相同”抑制；未做跨 track 全局证据哈希/回滚。
- `merge_duplicates` 仅同 entity/batch；`merged_from` 保留但被合并 track 移除。
- 未写 V15/TrackTable 外部权威；`writes` 字段恒 false。
- 快照为内存 JSON；不直接写盘，未接 SaveService 自动槽位/备份；由 SaveService
  外层负责文件/校验；GameSession 需自行把 save_state 放进扩展 payload（当前 3 文件
  范围不修改 GameSession/SaveService）。
- 未实现旧版本迁移路径（当前只有 1.0.0；旧版本拒绝）；未做存档压缩/加密。
- probe 使用内部 `_create_track/_apply_level` 构造 merge 夹具；生产不应直接调用私有方法。
- 未跑全量回归；只单次跑本 probe。
