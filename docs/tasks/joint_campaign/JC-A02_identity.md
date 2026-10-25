# JC-A02：多来源身份收敛与IFF状态闭环

状态：WAIT A1；交付A2。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 1. 目标与缺口

C55已有IdentificationService的冲突/TTL/衰减/人工逻辑，但Session的assessment仅发事件，TrackTable也直接接受身份来源，操作结果未形成可验证的统一出口。收敛IFF、ELINT、光学与人工证据，使HUD/火控读取一致，来源冲突和过期确实改变结果。

## 2. 基线与范围

以已审A1及K0精确SHA开工；不直接从C55覆盖A01。范围为现有身份服务的接线/必要状态、transponder安装、证据标准化、TrackTable操作性身份、HUD/火控读取及恢复。复用既有推理算法；不开发真实RF/密码学或强制实现完整军用IFF模式，不更改阵营/指挥权来“确认身份”。

## 3. 权威、时间与可见性

原始证据入口带owner/source/observed_t/received_t/TTL与可信度；IdentificationService计算assessment；TrackTable为指定owner的操作性身份唯一写者，Session只路由一次。原始探测融合继续保留，不能重复消费assessment形成正反馈。人工确认是可审计的授权证据，有撤销/过期规则，不直接覆写隐藏真值或ROE。

IFF至少可表达未查询/等待/有效回应/无回应/过期/冲突/受干扰；无回应不等于敌对，回应声明不等于真实阵营，未知不回退friend。查询/回应依据可见应答配置，不能直接用catalog真实side替玩家解谜。orbital_sim按实体装入应答配置，旧配置缺失给明确状态，不能静默全友军。

## 4. 实施与提交拆分

1. 先定位所有写identity/manual_confirm与读取点，写冲突、TTL及重复路由红例。
2. 归一化四来源证据并接入既有计算器；收敛重复写路径，保留历史schema迁移与来源标签。
3. 接IFF查询/回执/无回应与人工撤销；把最终assessment经受权入口写TrackTable，HUD/火控读同一操作结果。诊断assessment若保留须明确advisory。
4. 分提交补安装配置、运行态恢复/待处理查询、探针及来源到消费者对照表。

## 5. 验收

四来源分别有效、冲突、过期、重复、不同到达顺序；相同证据集合在规定时间语义下得到一致结果。IFF单独有效不自动赋开火许可或友军直控权；人工未授权拒绝，撤销后恢复正常推断。伪装/弱证据降低可信度，不能凭单个字符串成确定友军。两个owner各有相同目标不同证据，不串域。

覆盖TTL边界同tick、迟到证据与原观测时刻、旧seed/旧档未知状态、UI与火控一致、真实文件恢复后至少10tick查询/衰减/事件ID一致。比较置信度误差≤1e-9，时间/几何按公共契约；不以显示标签通过代替实际消费者。

## 6. 命令与证据

注册`integration.jc_identity_pipeline`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_identity_pipeline|identification_probe|transponder_probe|track_table_probe|a0_(sensor_persistence|event_continuity|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_identity_pipeline|identification_probe|transponder_probe|track_table_probe|a0_(sensor_persistence|event_continuity|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-A02/targeted
```

加C回归。日志须能追踪原始证据ID→assessment→TrackTable→HUD/火控，列owner/时间/来源/拒绝原因；保存红绿证据、恢复对比及同一最终SHA的CI。

## 7. 历史失败

#46相关显示来源差异单列；旧7失败绿化/漂移按公共规则处理，未知身份不能靠放宽ROE变绿，不刷新整份baseline。

## 8. 交付与复核

A2提交唯一写者图、IFF状态与旧档迁移表、所有写入/消费点、正负例与限制。独立审查检查重复证据是否虚增置信度、真实side是否穿透、人工确认是否跨owner或绕过授权。为EW接入保留正常证据通道。
