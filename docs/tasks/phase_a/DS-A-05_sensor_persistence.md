# DS-A-05｜传感器运行态持久化与续跑

状态：WAIT I1；服务可并行，Session 集成在 I4 后；优先级：P0；父需求：#2.6/#4。

## 目标、复现与基线

保存时的 EMCON、雷达和光学/IR 通道在读档后持续生效。55 C5 已记录运行态未入档；T22 现 head 已翻转 EMCON、建立非空通道并比较完整规范化通道内容。现有测试不是只比较数量，必须保留并补充下一 tick 行为。

当前来源 S0=`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`、T22=`8bf7517cef32ca14699cca1b048ef3398b9eb88d`、几何实现 P20=`7a4f3255023c9823137c97b1413c3c047c7f84e2`。服务分支基线为 I1；最终 Session 接入基线为 A-04 的 I4，均写完整 SHA，输出 I5。

## 范围与状态契约

允许 `sensor_service.gd` 的导出/导入、必要 sensor authority/optical 后端状态接口、独立 probe；Session 只增加 sensor state 段、恢复时机及几何 provider 重绑定，schema/旧档文档随之更新。不扩写 IFF/EW/身份算法，不只恢复 UI `_last_channels` 缓存，不改整个 save/load。

SensorService/对应后端写其运行态；PhysicsWorld 是 geometry 来源；TrackTable 仍是航迹写者。保存控制值、selected target、时钟、运行通道及影响下一次输出的后端状态、obs/evidence/event 分配器和去重信息；逐字段列“持久化 / 重建 / 可丢弃及理由”。provider 对象/Callable 不入 JSON，读档后从当前 Session 重新注入并验证 ID/frame/t。静态 mounts/targets 元数据从原权威重建，禁止保存后成为第二份可写真值。

单位为 `bary_rot`、km/km/s/s；geometry 与 session 同 tick 差≤`1e-6 s`，运动/确定性几何误差沿总队列 §3。EMCON/雷达和整数分配器类型精确一致。通道数、kind、target ID、状态/进度、有效来源、去重键精确比较；连续时间/浮点状态容差 `1e-9`。不确定测量按 A-01 的模型参数核验，不要求航迹等于 truth。

## 步骤与验收

1. 在真实 HUD orbital_sim 会话中主动切换 EMCON/雷达到与 seed 不同的值，启动 optical+IR 至少两类、总计非空的通道并推进到非初始状态。保留 T22 已有 3 通道用例；内存/文件往返先证明失败。
2. 独立提交服务 state 契约和 probe。通道后端应有可继续的状态恢复，不能靠画面列表伪造；任何可丢弃缓存都用下一 tick 等价证据说明。
3. 服务接口稳定后，在 I4 上单独接入 Session。恢复完成后重绑定 physics provider，world/physics 同步先于新的传感器输出；不重放已经恢复的证据/观测到 TrackTable。
4. 原会话和恢复会话继续相同 10 ticks：比较观测/证据事件、来源时间、通道进度、控制效果与分配器；恢复不产生重复 ID/重复证据，EMCON 开启时无不应出现的雷达发射，关闭后输出可恢复。
5. 负例：缺目标、过期几何、不同 frame、损坏通道/版本、未知通道种类、非法时钟/counter、provider 未就绪。返回明确 reason，不把旧位置当当前数据。旧档缺 sensor 段按 A-04 支持矩阵重建并标局限，不能声称旧档保存过运行态。
6. 明确对照无 sensor 组件/可选 profile，以及 full/prelude boot；匿名 contacts 的可见性不因恢复扩大。

## 命令与交付

新增 `a0_sensor_persistence_probe.gd` 纳入矩阵（独立 integration case，不更改 phase0 gate）。

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only 'a0_sensor_persistence|sensor_service|optical_ir|a0_sensor_geometry|a0_save_roundtrip_authority|save_probe|session_probe' -Ci -ResultsDir .test-results/phase-a/cards/DS-A-05/targeted
pwsh -NoProfile -File ./run_tests.ps1 -Gate phase0 -Ci -ResultsDir .test-results/phase-a/cards/DS-A-05/phase0
pwsh -NoProfile -File ./run_tests.ps1 -Gate phaseA -Ci -ResultsDir .test-results/phase-a/cards/DS-A-05/phaseA
pwsh -NoProfile -File ./run_tests.ps1 -Ci -Baseline game_v17/tests/known_baseline_failures.json -BaselineExtra game_v17/tests/phasea_baseline_failures.json -ResultsDir .test-results/phase-a/cards/DS-A-05/full
```

期望传感器往返/续跑切片绿；通信 no_route 尚未修时明确保留。报告逐项内容而非只报通道数量。交付 I5 完整 SHA、字段分类、恢复顺序、旧档限制、红→绿与下一 tick 日志、同提交完整回归。计数漂移和 baseline 更新遵守总队列 §4；Astra 独立核查底层通道状态、provider 重绑定及无重复证据。
