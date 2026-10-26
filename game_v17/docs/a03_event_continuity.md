# DS-A-03 · 事件历史恢复与继续发布（I3）

> 服务基线 **I1** = `26f1d5398a4ed6654b057f23a27819e4bf700b31`；Session 集成重放到
> **I2** = `7b5691482929d493467aec12eddbe20f3782f35e`。
> 交付 **I3** = `6c2116dd0976b118e91b452a466db6293e87aaab`。

## 1. 复现的真实缺陷（修复前）

`GameSession.load_state()` 用 `JSON.parse_string(JSON.stringify(...))` 直接赋值
`bus.events`、`bus.seq`，并在外部遍历写 `bus._seen_ids`：

```gdscript
bus.events = JSON.parse_string(JSON.stringify(evs))
bus.seq = int(saved_bus.get("seq", bus.events.size()))
for raw_ev in bus.events:
    bus._seen_ids[...] = true
```

后果：
1. **事件内部 `seq` 变 float**（JSON 数字解析），A0-T3 实测 27 处类型漂移；
2. 存档只含 `bus.seq`/`bus.events`，**未保存 `_id_seq` 与完整 `_seen_ids`** →
   读档后分配器与去重集合不完整（可见历史只有最后 1000 条）；
3. Session 直接重建 EventBus 私有字段，绕过事件总线自身的分配器/去重契约。

## 2. EventBus 版本化 state（本卡新增）

```gdscript
bus.export_state() -> {schema:"v17.event_bus.state.v2", version:2,
                       seq, id_seq, seen_ids[], events[], max_events}
bus.import_state(state) -> {ok, mode:"v2"|"legacy_partial", seq, id_seq,
                            events, seen_ids, seen_ids_imported}
```

**导入语义**：
- **先完整校验，再一次提交**；失败时 bus 状态**逐字节不变**（不半写）；
- **不调用 `publish`、不派发历史**，订阅者恢复期间调用 **0 次**；
- 只规范化「整数契约字段」（`seq` / `id_seq` / `events[i].seq`），**不递归**转换整个 payload；
- `t` 保留浮点、payload 浮点保真（1e-9），布尔/字符串/ID 精确。

### 2.1 整数契约（本批固定范围）

| 字段 | 允许范围 | 原始 JSON 值 | 恢复后类型 |
|---|---|---|---|
| `seq`（bus） | `0 .. 2^53-1` | int 或 float，必须有限、无小数 | **GDScript int** |
| `id_seq`（分配器） | `0 .. 2^53-1` | 同上 | **GDScript int** |
| `events[i].seq` | `1 .. 2^53-1` 且严格递增 | 同上 | **GDScript int** |

理由：不依赖 JSON 数字的 Variant 类型（JSON 数字解析为 float 属正常）；
**恢复后**的运行时值才是类型漂移判据。

### 2.2 去重与分配器不变量

- `seen_ids` 是**完整已用 ID 集合**，可以远大于可见环形历史（`MAX_EVENTS=1000`）；
- 可见历史中每个 ID 必须 ∈ `seen_ids`；
- 已用 ID 唯一；历史 `seq` 严格递增；历史尾部 `seq ≤ 当前 seq`；
- 分配器 `id_seq` 必须 **≥ 已用 `evt-*` 的最大序号**（否则下次分配会重发已存在 ID）；
- 显式 ID 也进入去重集合；**被裁出可见缓冲的 ID 仍然拒绝重发**；
- 达到 `2^53-1` 时 `publish` 明确拒绝（`seq_exhausted` / `id_exhausted`），不溢出/不四舍五入。

## 3. Session 集成

- `save_state()`：`"bus": bus.export_state()`（不再只存 seq/events）；
- `load_state()`：`bus.import_state(...)`（**不**直接写私有字段）；
  旧档（无 `schema`）走兼容分支：先保留 boot 重放得到的已用 ID，再并入可见历史，
  高水位不倒退，并显式记 `legacy_partial` 警告（完整旧档迁移由 **DS-A-04** 承接）。

### 3.1 旧→新字段映射（Session 存档 `bus` 段）

| 旧字段 | 新字段 | 说明 |
|---|---|---|
| `seq` | `seq` | 语义不变，但保证 int 且 ≥ 历史尾部 |
| `events` | `events` | 每条 `seq` 归一为 int；payload 不递归改 |
| （无） | `id_seq` | **新增**：自动 ID 分配器状态 |
| （无） | `seen_ids` | **新增**：完整去重集合（不是最后 1000 条） |
| （无） | `schema`/`version` | **新增**：版本化，损坏新档不会被当成旧档 |
| （无） | `max_events` | **新增**：记录写档时的环形容量，便于迁移诊断 |

**不序列化字段及理由**：订阅者 Callable（不可序列化、且恢复历史不应重新订阅）、
`_sub_seq`（会话内订阅令牌，恢复后重新订阅自然分配）、`_dispatch_count`/
`_listener_errors`（运行时诊断计数，不影响继续发布语义）。

## 4. 探针与结果

新增 `integration.a0_event_continuity`（`a0_event_continuity_probe.gd`，**72 断言**）：

| 组 | 断言 |
|---|---|
| 基线复现 | 混合自动/显式 ID、`t=0.125`、payload `1.25`/`0.001` 经 JSON 往返 |
| 内容与类型 | 恢复后 `seq`/`id_seq`/每个事件 `seq` 都是**真 int**；浮点 1e-9、bool/string/ID/顺序精确；export→import→export 一致 |
| 无派发导入 | 恢复历史订阅者**0 次**；新 publish **恰好 1 次**；首个新 seq = 保存值+1 |
| 旧 ID 重发 | 被拒绝，且 **seq/分配器都不前进** |
| 超环形缓冲 | 1005 条事件 → 可见 1000、`seen_ids` 保留 **1005**；被裁出的 `evt-000001` 仍拒绝重发 |
| 负例（9 组） | 负/分数/字符串/越界 seq、版本不符、重复/倒序事件 seq、`seq` 小于尾部、缺必需字段、未知 schema（不伪装旧档）、分配器低于最大已用号 —— 全部拒绝且 bus 状态不变 |
| 真实文件集成 | 真实 HUD 会话 → 写入真实文件 → 读档 → 两会话继续 10 tick：`seq`/`id_seq` 完全一致、无重复 ID、订阅者收到新事件 |

**真实结果**（I3，`6c2116d`）：

```
Phase A gate:  total=3 pass=2 fail=1   (A0-T1 45/0、A0-T2 30/0、A0-T3 38/3)
Phase 0 gate:  total=6 pass=6 fail=0
Full matrix:   total=81 pass=73 fail=8
  BASELINE CHECK:         known_fail=7 new_fail=0 drift=0 complete=true
  PHASE A BASELINE CHECK: known_fail=1 new_fail=0 drift=0 complete=true
```

## 5. 基线证据更新（旧失败转绿，独立提交）

| 条目 | 变化 | 证据 |
|---|---|---|
| `unit.save_probe` | **153/3 FAIL → 156/0 PASS**，从 Phase 0 baseline **移除** | 事件 seq 与总线 state 恢复修复后真实转绿；`new_fail=0 drift=0` |
| `integration.a0_save_roundtrip_authority` | 37/4 → **38/3** | `restored runtime event seq is a real GDScript int` 已通过；余 3 项属 DS-A-05（传感器运行态）/A-06（comms） |

> 原报告与原始非零日志保留在 `.test-results/phase-a/cards/DS-A-03/`；
> 这是「旧失败转绿」，**不是**刷新期望掩盖回归。

## 6. 未覆盖 / 尚未验证

- **旧档完整迁移**（超环形缓冲去重合并、旧版本兼容矩阵）→ **DS-A-04**；本卡只保证
  旧档「不丢已重放 ID、高水位不倒退」并标 `legacy_partial`；
- 传感器运行态 → DS-A-05；HUD 通信 `no_route` → DS-A-06；长时成本 → DS-A-07；
- 未验证 Linux/macOS、非 headless 渲染；未量化 >1000 tick 事件量下的性能。

## 7. 命令

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_event_continuity|core_time_event|save_probe|a0_save_roundtrip_authority|session_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-03/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-03/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-03/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-03/full
```
