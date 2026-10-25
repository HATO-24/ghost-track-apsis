# JC-A00 集成收尾：比较器补齐与 G0 冻结状态

> 卡：#56 · 起点 C55 = `30b8d33dae9787aadf89bb206757cafb2cad7bd3`
> 本轮工作提交：`c58abc7a2aaaa61db44437d277af1a5bcb69c2e2`（`jc/g0-integration`）
> **结论：G0 未冻结** —— 新比较器发现了真实恢复分歧，按卡「真实新失败阻断 G0」如实上报。

## 1. 已完成的 A00 交付项

| # | 卡要求 | 完成情况 |
|---|---|---|
| 1 | 固定 PR/提交/祖先表 | `jc/g0-integration` = C55 + 合入 #54 审查文档（`docs/57` 前的 58 系列、`reviews/phase_a_20261025/`）；#32–#39 内容已在 C55 祖先链内 |
| 2 | 补规范化状态比较（不只集合大小/下界） | ✅ 新增 `_full_state_violations()`：**完整已用 ID 集合成员**、seq/allocator 真 int + 严格单调、World 投影与 Physics 同刻 ≤1e-9、Sensor controls/后端通道 kind·target·status·progress/观测 ID 流/去重键集合、Comms 在途队列（ID@ETA）与 outcome 记录 |
| 3 | ≥10 tick 行为比较 | ✅ `_behavior_violations()` 逐 tick 比较 seq/时钟/obs_seq/观测数/在途数/最后事件类型 |
| 4 | 故障注入改真实篡改 | ✅ `_tamper_restored()`：fault=2 做**等长 ID 集合替换**（删 `evt-000001` 加伪造 ID），fault=3 改**在途消息 ETA +30s**；均由正常比较器发现 |
| 5 | 修正诊断字符串格式错误 | ✅ `%.3e` → `%.9f`；`_info("..." + "...") % [...]` 优先级错误加括号；comms NaN 改显式 null（避免 JSON.stringify 告警）。复跑后 **stderr 无格式错误** |
| 6 | 修正已过时说明 | ✅ 删除「被过滤雷达也消耗 ID」的说明（R03 已改为只对采用观测分配） |
| 7 | 保留旧 7 个边界反例证据 | ✅ C55 已含，未重复修改 |

## 2. 故障注入验证（真实篡改 → 比较器发现 → 非零退出）

```
FAULT=2 EXIT=1  tamper={"applied":["seen_ids equal-size replacement: -evt-000001"],"fault":"2"}
  FAIL: bus.seen_ids  only_original=["evt-000001"] only_restored=["evt-tampered-fault2"] size_equal=true
FAULT=3 EXIT=1  tamper={"applied":["pending[0].arrive_t += 30"],"fault":"3"}
  FAIL: comms.pending  original=["C-000001@50.100000"] restored=["C-000001@80.100000"]
  FAIL: 10 continued ticks  tick0 bus.seq 225 vs 224 …
```

等长 ID 集合差异（size 相同）**能被**完整成员比较发现 —— 这正是 R05 旧比较器做不到的。
未注入对照：`EXIT=0 PASS=27/0`，stderr 无格式错误。

## 3. 真实发现（G0 阻断项）

在 200/800/1000 tick 规模上新比较器稳定复现两类分歧（50 tick 不触发）：

| # | 违规 | 规模 | 含义 |
|---|---|---|---|
| D1 | `sensor.backend.status` original=`locked` / restored=`lost`，`progress` 不同 | 200/800/1000 | 恢复会话在恢复后 10 tick 内**提前失锁**；原始会话保持锁定 |
| D2 | `sensor.obs_seq` 逐 tick 偏移（如 2278 vs 2280，持续 ±2~4） | 800/1000 | 同输入下观测序号流不一致；`observations.ids` 内容不同 |

**已做的根因排查与一个必要修复**：
- 定位到通道 `lost_hold` 计时使用 **authority 自身时钟** `t`，而 A-05 只持久化 `optical_ir` 子模块的 `t`，`sensor_authority.t` 恢复后从 0 开始 → `t - lost_at` 判定与原会话不同。
- 已提交修复：`sensor_authority.export_backend_state()` 增加 `authority_t`/`authority_step_count`/`authority_dt_last`，导入时带非有限/负值校验并恢复。
- **修复后 D1 仍复现**（恢复时刻状态一致，10 tick 后分歧）→ 说明还有第二个差异源未定位，疑在通道演化输入的**模型快照**（sun_illum/los/shadow/jamming 未持久化）或 authority 内部 `_tws`/records 缓存。**未定位前不猜测修复**。

## 4. G0 状态

- **G0 未冻结**：C55 上 8 专项与 7 反例为绿，但 A00 新增的完整比较器在长规模发现 D1/D2 真实分歧。
- 按卡 §3/§7「真实新失败阻断 G0」「正确性失败不进入合格性能结论」，本轮**不**声明 R05 验收缺口已全部补齐，也**不**声明 G0 可冻结。
- 长测性能结论同样不可用（正确性未过）。

## 5. 移交与下一步

1. D1/D2 根因需要**继续定位**（建议下一轮：对比恢复前后 `optical_ir.channels[*]` 全字段与 `snapshot` 输入，用 200 tick 单样本最小复现）；
2. 定位并修复后，重跑 benchmark（4 规模）+ C 回归，再冻结 G0；
3. 之后按依赖推进 JC-B00（契约 K0）、JC-B03P（内容 P0），再 A01→A02→A03→A04→B01A；
4. 本卡**未**修改 `known_baseline_failures.json`；7 项历史失败保持原状。

## 6. 命令与证据

```powershell
# 故障注入（真实篡改 → 期望非零）
$env:A07_SCALES="50"; $env:A07_FAULT_SAMPLE="2"   # 等长 ID 集合替换 → EXIT=1
$env:A07_SCALES="50"; $env:A07_FAULT_SAMPLE="3"   # 在途 ETA 篡改   → EXIT=1
$env:A07_SCALES="50"; $env:A07_FAULT_SAMPLE=""    # 对照            → EXIT=0 PASS=27/0

# 发现 D1/D2 的完整规模运行
$env:A07_HEAD = (git rev-parse HEAD).Trim()
pwsh -NoProfile -File ./run_tests.ps1 -Matrix game_v17/tests/benchmark_matrix.json -Only '^integration\.a0_save_cost$' -TimeoutSec 1800 -Ci -ResultsDir .test-results/jc-r2/JC-A00/benchmark
```
证据目录：`.test-results/jc-r2/JC-A00/benchmark/`（完整日志，含 78 PASS / 12 FAIL）。
