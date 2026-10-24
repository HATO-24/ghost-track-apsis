# DS-A-04｜旧档迁移及超环形缓冲的事件去重

状态：WAIT I3；优先级：P0；父需求：#2.5/#11 兼容切片；执行：DeepSeek v4.1 Flash。

## 目标、问题与基线

支持范围内的旧档应恢复到可继续的同一状态，迁移不能遗失较早的已用事件 ID。当前实现会把尾部事件 ID 合入 seed+log 重放得到的 `_seen_ids`；如果新恢复器只根据可见历史重建集合，会把已重放但被 1000 条缓冲裁出的 ID 忘掉。

当前来源 S0=`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`，旧档对照 T22=`8bf7517cef32ca14699cca1b048ef3398b9eb88d`；执行基线为 A-03 的 I3 完整 SHA，输出 I4。旧 fixture 必须来自记录了完整 SHA 的旧实现真实导出，或说明由哪一个真实旧档删去哪个可选字段构成；禁止用新实现生成后冒称旧档。

## 范围、单位与兼容策略

允许 EventBus 导入兼容小段、Session save/load/migration/schema、旧档 JSON fixtures 与 `a0_legacy_save_probe.gd`、save/A0-T3 对应用例。不改事件发布语义，不引入 checkpoint/性能重构，不调整通信路由或 SensorService。

EventBus 仍是 seq/ID 写者；迁移输入为旧档显式字段和真实操作重放结果；目录元数据从 seed→EntityCatalog 取回。运动状态、相对秒、UTC/frame 和玩家可见性沿用 I3，不在迁移中猜身份或制造友军。整数范围/浮点保真沿 A-03，时间/运动阈值沿总队列 §3。

| 旧档形态 | 必须采用的行为 |
| --- | --- |
| 无 bus 段 | 保留 seed+log 重放可恢复的历史、seq、allocator、已用 ID，记录采用的迁移版本 |
| 只有 bus.seq/events，无新 allocator/seen 元数据 | 合并“重放已用集合 ∪ 可见历史 ID”，高水位不得倒退；不能清空重放得到的旧 ID |
| 无新增 EntityCatalog 段/新增元数据 | 按旧 seed 重建已有 catalog；无法知道的字段显式 unknown/default+source，禁止 friend 兜底 |
| 无 SensorService 运行态 | 只声明旧档不可恢复的状态及 seed 默认来源，后续 A-05 承接；不能称完全无损恢复 |
| 未支持版本/损坏必需字段/非法 seq | 明确拒绝并附 reason；不能用“兼容”跳过校验 |

没有保留在旧档、操作日志或可恢复状态中的历史 ID 无法凭空重建。迁移报告精确列出可恢复范围；新档必须保存完整去重信息。不要借此降低可恢复信息的保留要求。

## 步骤、正负例与提交

1. 保存旧实现 fixture provenance、格式版本、内容 hash、操作序列。先在 I3 跑兼容探针；通过当前实现中确实记录操作日志的 `GameSession.route_event()` 白名单路径产生一个早期显式 ID，并断言操作日志含该 ID；直接 `bus.publish()` 不足以构造此边界。随后产生超过 1000 条事件，使该 ID 从可见历史消失但仍存在于操作重放信息，再导出旧档。
2. 先复现/证明这个边界，再独立提交迁移。读档后重新提交早期 ID 必须被拒绝；自动 ID 不碰撞；新 seq 单调续写。分别覆盖缺 bus 与旧 bus 两种路径。
3. 对新旧档执行内存与文件往返；读取后继续 10 ticks，对比能从旧信息恢复的状态/事件。恢复历史不得再次派发，后续新事件正常派发；seed/catalog 按稳定 ID 归属。
4. 负例包括无日志又缺必要 counter、损坏 JSON、未知版本、错误字段类型、非法 seq、重复 ID、metadata 归属错位。应根据支持矩阵拒绝或标部分恢复，不能静默开一场新模拟。
5. 分开提交 fixtures/失败证据、迁移实现、文档与回归证据；不把所有旧档失败写入新 known baseline。

## 命令与交付

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_legacy_save|a0_event_continuity|core_time_event|save_probe|a0_save_roundtrip_authority|session_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-04/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-04/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-04/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-04/full
```

兼容/事件专项全绿；其他未修 Phase A 项仍明确红。所有命令、日志、旧失败转绿/漂移/新增失败按总队列 §4 归档，不能刷新期望掩盖回归。交付 I4 完整 SHA、支持矩阵、fixture provenance 与 hash、迁移 diff、超缓冲 ID 证据、同提交全量报告。Astra 独立审查“重放集合合并”而非“尾部替换”，以及部分恢复的诚实标注。
