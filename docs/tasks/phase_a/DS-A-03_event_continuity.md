# DS-A-03｜事件历史恢复与继续发布

状态：WAIT I1；服务开发可并行，Session 集成须在 I2 后；优先级：P0；父需求：#2.5。

## 目标、复现与基线

读档后继续同一场模拟，历史事件的序号、已用 ID 和分配器连续，恢复本身不再通知订阅者。当前 `GameSession.load_state()` 用 JSON 往返赋值 `bus.events`，使事件内部 seq 变为 float；存档仅含 bus.seq/events，未显式保存 `_id_seq` 和完整 `_seen_ids`。

当前来源 S0=`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`，相关测试 T22=`8bf7517cef32ca14699cca1b048ef3398b9eb88d`。服务分支从 I1 完整 SHA 开始；Session 集成重放到 A-02 的 I2 完整 SHA，最终报告同时列两者。输出 I3。本卡建立新档完整恢复，旧档迁移由 A-04 验收，禁止丢失已有兼容行为。

## 范围与权威

允许 `event_bus.gd`、`game_session.gd` 的 bus save/load 与必要 schema、`core_time_event_probe.gd`、`save_probe.gd`、A0-T3 事件切片及新增 `a0_event_continuity_probe.gd`。不改传感器/通信逻辑、不重写整个 GameSession、不对整个 payload 递归转 int。

EventBus 唯一分配 seq/自动 ID 并持有去重集合。Session 通过明确的导出/恢复 API 编排，不直接重建 EventBus 私有字段。订阅 Callable 不序列化；恢复历史是导入，不调用 publish。事件时间 `t` 为模拟秒、保留浮点；payload 的合法浮点值和字段类型语义保真，实体 ID 继续使用原字符串。恢复历史不能改变玩家可见性过滤。

本批 numeric JSON 兼容范围固定为安全整数 `0..9007199254740991`（2^53−1）：bus seq/allocator 允许 0，事件 seq 必须 ≥1；原始解析值可为 int 或 float，但必须有限、无小数且在范围内。恢复后 seq/allocator/每个事件 seq 必须为 GDScript int。若项目确需更大范围，另提版本化编码，不在本卡换格式。达到上限时明确拒绝继续分配，不能溢出或四舍五入。

## 实施与提交

1. 先在规定基线上产生混合自动/显式 ID、非整数时间（如 0.125 s）与 payload（如 1.25、0.001），经内存和 SaveService 文件往返，保存内部 seq 类型漂移/分配器缺口的失败证据。
2. 为 EventBus 定义版本化 state：环形可见历史、当前 seq、自动 ID 分配状态、完整已用 ID 集合。导入先完整校验再一次提交，失败不得半写 bus。只规范化上述整数契约字段。
3. seq 严格递增、历史最后 seq≤当前 seq；ID 不重复；可见历史每个 ID 都属于去重集合。分配器与已用 `evt-*` ID 不冲突；显式 ID 也进入集合。恢复不能把已重放的集合缩成最后 1000 条。
4. 独立提交 Session 对 EventBus 接口的接入与 schema/文档。保留历史兼容路径给 A-04，不重新 publish 历史。输出旧→新字段映射和不序列化字段的理由。

## 正例、负例与持续运行

- 内存、真实文件、save→load→save 的事件 state 规范化内容一致；内部 seq 类型严格 int；浮点时间/payload 数值按 `1e-9` 绝对误差保真，布尔和字符串精确一致。此容差只覆盖 JSON 浮点往返；整数值/ID/顺序精确一致。
- 在原会话与恢复会话分别继续同一命令序列至少 10 ticks，比较新事件 type/source/target/payload、seq 与 ID；首次新 seq 为保存值+1，自动 ID 唯一；允许的确定性诊断字段须逐项列出，不能整段排除事件。
- 订阅者在恢复历史时调用 0 次，发布新事件恰好派发一次；旧显式 ID 再发布被拒绝，拒绝不推进 seq/allocator。
- 构造自动 ID 与显式 `evt-*` 冲突、高水位、超过 MAX_EVENTS=1000 的历史；被裁出可见缓冲的已用 ID 仍拒绝。
- 非法 seq（负/分数/字符串/越界/重复/倒序）、非法 state 版本、counter 比尾部小、缺必需字段均明确拒绝或进入 A-04 指定的旧档迁移；损坏新档不能伪装成旧档。失败导入前后 bus state 一致。

## 命令、交付与限制

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_event_continuity|core_time_event|save_probe|a0_save_roundtrip_authority|session_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-03/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-03/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-03/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-03/full
```

预期事件专项通过；A0-T3 传感器/通信未修项仍可红且逐条登记。交付 I3 完整 SHA、state 契约、失败复现、新旧日志及同提交完整回归；目录如命令。旧失败转绿/计数减少也保留原 baseline 报告，经证据审查再独立更新条目，遵守总队列 §4。Astra 重点审查去重集合、JSON/运行时边界和无副作用导入。误派工事件实验不作为本卡实现或通过证据。
