# DS-A-04 · 旧档迁移与超环形缓冲去重（I4）

> 执行基线 **I3** = `f842b3db6158d08bb6da5221252745882a2cc858`；交付 **I4** 见执行报告。
> 旧档对照 **T22** = `8bf7517cef32ca14699cca1b048ef3398b9eb88d`；原始来源 **S0** = `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`。

## 1. 关键边界（任务卡点名）

早期显式 ID 经 **`route_event()` 白名单路径**发布（`bus.publish()` 直调不算，因为不入操作日志），
日志里留下 `{"op":"route_event","event":{"id":"evt-legacy-early-1",…}}`；
随后 1000+ 条事件把它挤出可见环形历史。此时：

- 可见历史**不含**该 ID；
- 但它仍在 seed+log 的重放结果里（重放 `route_event` 会把它重新发布进 `_seen_ids`）。

因此迁移必须采用 **「重放已用集合 ∪ 可见历史 ID」**；若只按可见历史重建集合，
这个早期 ID 会被忘掉，重发时会被当成新事件接受（去重失效）。

## 2. Fixtures 与 provenance

生成器：`game_v17/tests/tools/gen_legacy_fixtures.gd`（可复跑；写入 `user://` 后拷入仓库）。
生成实现 head：**`f842b3db6158d08bb6da5221252745882a2cc858`（I3）**。

| fixture | 大小 | sha256 | 派生方式 |
|---|---|---|---|
| `save_v2_reference.json` | 374,988 | `5c0974e28080135f6883d6c8c7d8512309dc5db626d582b13da6da716fe0919f` | I3 真实 `save_state()` 导出（对照） |
| `legacy_bus_seq_events.json` | 361,768 | `d3514778944368820b324d5a63fe67d20aa4d6cad96fa494005aa1fa83e76617` | 上述真实导出**删除** `bus.{schema,version,id_seq,seen_ids,max_events}` |
| `legacy_no_bus_section.json` | 172,094 | `a984d14b51dd8a6e521e33fd6cb8f72897e12c33510d84a68d7e1a0dcaec5ccc` | 上述真实导出**删除整段 `bus`** |
| `fixture_meta.json` | 619 | `23d4706f35d47a0478a46e9619b7e7ea4fa15ba88f33e227b53a4771e76e0431` | 生成期实测元数据（见下） |

**生成期实测**（`fixture_meta.json`）：

```json
{"early_event_id":"evt-legacy-early-1","early_event_seq":6,
 "op_log_contains_early_id":true,"op_log_len":1006,
 "visible_event_count":1000,"early_still_visible":false,
 "seen_ids_count":1011,"bus_seq":1011,"bus_id_seq":1010,
 "shape_b_removed_fields":["schema","version","id_seq","seen_ids","max_events"],
 "shape_a_removed_section":"bus",
 "generator_head":"f842b3db6158d08bb6da5221252745882a2cc858"}
```

> **禁止**用新实现生成后冒称旧档：这里两个旧档形态都是**从 I3 真实导出删字段**得到的，
> 删除清单在上表与 meta 中逐项列明。

## 3. 支持矩阵（迁移行为）

| 旧档形态 | 实际行为 | 采用版本 | 标记 |
|---|---|---|---|
| 无 `bus` 段 | 保留 seed+log 重放可恢复的 `seq`/allocator/已用 ID | 1 | `shape=no_bus_section`，`partial[]` 明示「可见历史仅来自重放」 |
| 只有 `bus.seq`/`bus.events` | **重放已用集合 ∪ 可见历史 ID**；高水位不倒退；不清空重放旧 ID | 2 | `shape=legacy_bus_seq_events`，`recovered.seen_ids_from_replay` / `..._from_visible_history` |
| 新档（v2） | 完整 state 直接导入 | 2 | `shape=new`，`applied=false` |
| 无 SensorService 运行态 | seed 默认来源恢复 | — | `unrecoverable[]` 明示属 **DS-A-05**，**不称无损** |
| 无 EntityCatalog 增量段 | 按旧 seed 重建（catalog provenance `source=seed`） | — | `unrecoverable[]` 明示未知字段保持 seed 默认 |
| 未支持版本 / 损坏 JSON / 非法 seq / 错误字段类型 / 重复 ID / 缺 log 又缺 bus | **显式拒绝** + reason | — | 不静默开新模拟 |

迁移报告 API：`GameSession.legacy_migration_report()`（只读）。

## 4. 本卡修复的真实缺陷

| # | 缺陷（红证据） | 修复 |
|---|---|---|
| 1 | 旧 `bus.seq` 用 `int()` 静默截断（`1.5 → 1`），非法值可通过 | 对旧 `seq` 施加整数契约（有限/整数值/0..2^53−1）；不合法 → 记 `replay_errors` 并未导入，读档失败 |
| 2 | 旧 `bus.events` 非数组时被静默替换成 `[]` | 类型校验失败即拒绝 |
| 3 | 缺 `log` 段被默认成空日志 → 「静默开一场新模拟」 | 缺 `log` 显式 `missing_log` 拒绝 |
| 4 | 无迁移报告，无法审查「合并 vs 替换」 | 新增 `legacy_migration_report()`（shape/version/recovered/partial/unrecoverable） |

## 5. 探针与结果

新增 `integration.a0_legacy_save`（`a0_legacy_save_probe.gd`，**60 断言**）：

| 组 | 断言 |
|---|---|
| provenance 与边界 | fixture 记录生成 head；操作日志含早期 ID；可见历史 1000；早期 ID **不在**可见历史；已用集合 > 可见历史；两种旧档派生方式逐项核对 |
| 形态 B | 迁移 applied / shape / version=2；`seen_ids ≥ 原始 1011`；`from_replay > 0`；**已用集合 > 可见历史（非尾部替换）**；早期 ID 重发被拒且 seq/分配器不前进；新 seq 单调 +1；新自动 ID 不碰撞 |
| 形态 A | applied / shape=no_bus_section / version=1；`partial[]` 明示；重放已用集合恢复；早期 ID 仍被拒；高水位不倒退 |
| v2 对照 | shape=new、未应用迁移、`seen_ids`/`seq` 精确、早期 ID 仍被拒 |
| 往返 | 恢复历史**0 次派发**；内存 + 真实文件二次读档保留 seq 与完整已用集合；重存为 v2（不重复迁移）；两会话各 10 tick 后 seq/allocator 完全一致 |
| catalog 归属 | 按稳定 ID 重建，provenance=`seed`，无 friend 兜底、无真值泄漏 |
| 负例（7 组） | 损坏 JSON、未知存档 schema、分数 seq、重复 ID、错误字段类型、缺 log 且缺 bus —— 全部显式拒绝 |
| 诚实标注 | 形态 A 报告列出 `sensor_service` 不可恢复（A-05）并标记 partial，不称无损 |

**真实结果**（I4）：

```
Phase A gate:  total=3 pass=2 fail=1   (A0-T1 45/0、A0-T2 30/0、A0-T3 38/3)
Phase 0 gate:  total=6 pass=6 fail=0
Full matrix:   total=82 pass=74 fail=8
  BASELINE CHECK:         known_fail=7 new_fail=0 drift=0 complete=true
  PHASE A BASELINE CHECK: known_fail=1 new_fail=0 drift=0 complete=true
```

矩阵 82 cases（77 常规 probe + 1 e2e + 4 boot smoke）。**8 FAIL = 7 legacy + 1 Phase A 存档切片**，逐条可见；
**不是「全部通过」**。旧档失败**未**写入新 known baseline（Phase 0 baseline 仍 7 条）。

## 6. 未覆盖 / 尚未验证

- SensorService 运行态恢复 → **DS-A-05**（本卡只声明不可恢复，不伪装无损）；
- HUD 通信 `no_route` → DS-A-06；长时存档成本 → DS-A-07；
- 仅覆盖「当前受支持存档 schema + 两种旧档形态」；更早版本矩阵未建立（无真实旧档样本支撑时不做猜测性迁移）；
- 未验证 Linux/macOS、非 headless 渲染。

## 7. 命令

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_legacy_save|a0_event_continuity|core_time_event|save_probe|a0_save_roundtrip_authority|session_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-04/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-04/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-04/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-04/full
```
