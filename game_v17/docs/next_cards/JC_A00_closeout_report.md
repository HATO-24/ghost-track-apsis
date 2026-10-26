# JC-A00 收尾：D1/D2 根因修复与 G0 验收

> 卡 #56；分支 `jc/g0-integration`；基线 C55 = `30b8d33dae9787aadf89bb206757cafb2cad7bd3`
> 本轮修复提交：`774adaf`（TWS/雷达状态）、`725694c`（挂载指向）、`c58abc7`（比较器等）
> 契约/提案提交：`93056ab`（K0）、`f41ad03`（P0）

## 1. D1/D2 根因（两个，均已定位并修复）

### 根因 1：optical/IR 挂载指向（slew 运行态）未持久化
- `_slew_toward_targets()` 每 tick 把 `sensors[kind].boresight_deg/el` 朝目标 LOS 推进（限速 `slew_rate_dps`）。
- `export_state` 只导出 `channels`，**未导出 sensors 的 boresight** → 恢复后从默认 0 重新慢速 slew。
- 后果：`off_axis` 变大 → `fov_miss`；通道状态 `locked`→`lost`（**D1**），并进一步改变观测数量（**D2**）。
- 修复（`725694c`）：`optical_ir.export_state()` 增加 `mount_pointing`，`import_state` 校验（有限、az∈[-180,180]、el∈[-90,90]、kind 必须已存在）后与 channels 一起原子提交。

### 根因 2：TWS/雷达扫描运行态未持久化
- 雷达 `scan_index`/`seconds_on`/`time_since_scan`/`last_scan_t`/`target_memory`，
  TWS `now_t`/`channels`/`last_exposure` 均为运行态，恢复后归零 → 扫描相位错位。
- 后果：雷达开启态下恢复会话每 tick 多产生 2 条雷达观测 → `obs_seq` 持续偏移（**D2**）。
- 修复（`774adaf`）：新增 `radar.export_state()/import_state()`（`v17.radar.state.v1`）与
  `tws.export_state()/import_state()`（`v17.tws.state.v1`），由 `sensor_authority` 在
  `export_backend_state`/`import_backend_state` 中聚合；先校验再一次提交，失败不半写。

### 诊断方法（可复现）
1. 200 tick 单样本最小复现，逐字段 diff 恢复前后 `optical_ir.channels[*]` 与模型快照；
2. 发现恢复时刻完全相同（`CH_DIFF=[]`）但**首 tick 后**分歧（`boresight_deg` 63.99 vs 0）→ 指向 `sensors` 运行态；
3. 800 tick 场景（雷达开启态）单独验证 → 定位 TWS/雷达扫描相位。

## 2. 修复验证

| 规模 | 修复前 | 修复后 |
|---|---|---|
| 50 tick | PASS | PASS 27/0 |
| 200 tick | **FAIL**（D1/D2） | **PASS 27/0** |
| 800 tick | **FAIL**（D1/D2） | **PASS 27/0** |
| 1000 tick | **FAIL**（D1/D2） | **PASS**（完整基准 90/0） |

故障注入仍有效（真实篡改 → 比较器发现 → 非零）：
- `A07_FAULT_SAMPLE=2`（等长 seen_ids 替换）→ EXIT=1，`only_original=["evt-000001"] only_restored=["evt-tampered-fault2"] size_equal=true`
- `A07_FAULT_SAMPLE=3`（在途 ETA +30s）→ EXIT=1，`comms.pending` 与逐 tick seq 均报差异

## 3. C 回归（head `eaf9532`）

```
Phase 0 gate:  6/6 PASS
Phase A gate:  3/3 PASS
Full matrix:   86 = 79 PASS / 7 FAIL / 0 TIMEOUT / 0 NOT RUN
BASELINE CHECK: known_fail=7 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
```

- 矩阵从 84 增至 **86**：新增 `integration.jc_contracts`（39/0）与 `integration.jc_scenario_spec`（138/0）；
- **7 项历史失败仍未修**，未登记为本轮新增，未刷新 baseline；
- 默认 full 不含长测（benchmark 独立 matrix）。

## 4. G0 状态

- **D1/D2 两个根因已修复**，50/200/800 三档验证通过，C 回归全绿；
- **完整 4 规模基准 PASS 90/0（1092s）**：`.test-results/jc-r2/JC-A00/benchmark3/`；
- **G0 冻结条件已满足**（以 head `eaf953286fe388f1013d0ef7cd2062ab535016b8` 为候选）；

'## 4.1 G0 基准数据（真实 UTF-8 字节，3 样本 median）

| ticks | UTF-8 B | chars | save_state | 构造+恢复 | 读盘 | 样本 |
|---|---|---|---|---|---|---|
| 50 | 433,862 | 428,559 | 180 ms | 3,414 ms | 3 ms | 3 |
| 200 | 1,151,244 | 1,145,941 | 364 ms | 13,432 ms | 4 ms | 3 |
| 800 | 1,934,895 | 1,929,691 | 461 ms | 56,661 ms | 7 ms | 3 |
| 1000 | **2,172,640** | 2,167,337 | 304 ms | 48,401 ms | 4 ms | 3 |

原始数据：`docs/benchmarks/jc_r2/a00_g0_measurements.json`（含全部 12 个样本）。
**预算状态（#49 硬目标，本轮不优化）**：1000 tick UTF-8 2,172,640 B > 1,500,000 B（超 44.8%）、
save 304 ms > 250 ms、构造+恢复 48,401 ms > 5,000 ms、读盘 4 ms 达标。
正确性全绿但**性能不达标**，交 #49 继续，不刷新预算。

## 5. 与 JC-B00 / JC-B03P 并行交付'

| 卡 | 交付 | 状态 |
|---|---|---|
| JC-B00（K0） | `scripts/core/jc_contracts.gd`、`docs/contracts/joint_campaign_r2.md`、10 个 fixture、`integration.jc_contracts`（39/0） | **设计完成，待独立技术复核** |
| JC-B03P（P0） | `docs/contracts/jc_sector_01_proposal.md`、`tests/fixtures/jc_scenario/jc_sector_01_proposal.json`、`integration.jc_scenario_spec`（138/0） | **提案完成，待用户核对内容** |

K0/P0 均**不**声称真实舰队已部署、AI 已行动或战役可玩；P0 的 9 条事件轨迹是内容逻辑 fixture，不是真实战报。

## 6. 待用户核对（B03P）

1. 战区命名/架空年月/参战单位命名；
2. 点数预算 100、指挥容量 3；
3. 两套编制具体舰型组合（传感型 62 点 / 突击型 70 点）；
4. 三个目标对象（`I-OP1`/`I-OP2`/`I-OP-C2`）与失能阈值；
5. 时限 3600 s；
6. 失败/撤离/僵局/超时结算口径；
7. 友军阵容与拒绝后替代路线。

## 7. 未完成

- JC-A01/A02/A03/A04/B01A 仍需 G0/K0 正式解锁；
- A00 的「按原 PR 分散提交」未做（卡允许保留 #55 为终端返修 PR，本轮以 G0 集成分支交付）；
- 长测性能结论不进入本轮（正确性优先；预算仍由 #49 承接）。
