# PR #65 第五轮独立复核与原卡返修清单

日期：2026-10-26，Asia/Shanghai；审查：Sol。精确候选 **`dc3821eda91d25f14e44dd9f57e6f5a985e04a9c`**；上轮候选`6cfbbb469c2e079511c61a36d53447e1f2375ad4`；main仍为`4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`。依据40号审计、56 R2以及既有[#56](https://github.com/HATO-24/ghost-track-apsis/issues/56)、[#57](https://github.com/HATO-24/ghost-track-apsis/issues/57)、[#63](https://github.com/HATO-24/ghost-track-apsis/issues/63)。用户源56 R2的SHA256仍为`5ED8C0C7080860381731253324679F6E119CAE4AC6D87645BAD0727FAF7CABA1`。

**结论：G0、K0均暂不通过；P0保留草案，先修技术和内部一致性，再提交具体产品选择。#65暂不合并，#58–#62核心集成尚未解锁。** 本轮不重复派已完成的角度/雷达相位修复，继续原#56/#57/#63即可。

## 1. 已独立确认的进展

| 项目 | 本轮结果与边界 |
| --- | --- |
| 既有8专项＋K0/P0两个探针 | **10/10 PASS**，0 FAIL/TIMEOUT/NOT RUN；49.0s含22.5s导入 |
| 原200tick＋继续10tick反例 | 退出0；最终obs_seq **638/638**，现有比较器无分歧 |
| 原400tick＋继续10tick反例 | 退出0；最终obs_seq **1052/1052**、扫描相位5/5，现有比较器无分歧 |
| 新增角度、Radar/TWS运行态 | 确已进入导出/导入，旧两例转绿，保留该修复 |
| 精确head CI | [run40217525109](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40217525109)的Phase0/PhaseA/full三个job成功；本轮未独立重跑完整86项 |
| 四规模90/0、12样本及性能 | 为作者报告和`a00_g0_measurements.json`证据，测量代码为`eaf953286fe388f1013d0ef7cd2062ab535016b8`；当前后续提交仅文档。本轮未重跑完整四规模，不冒充独立结果 |

10项断言PASS分别为197/161/138/39/59/86/60/89/65/41；详见[targeted-summary.json](evidence/targeted-summary.json)。默认matrix不包含长时成本probe，CI成功不能覆盖下列未被其断言检出的反例。按旧baseline成功也不等于历史失败清零。

## 2. G0：仍需处理的三组阻塞

### G1：只保存角度，跟踪目标/模式仍丢失

[optical_ir_channel.gd:322–325](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/framework/sim/optical_ir_channel.gd#L322)的`mount_pointing`只有az/el，没有`desired_target_id`、`pointing_mode`。[实际更新:540–548](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/framework/sim/optical_ir_channel.gd#L540)在desired_target为空时直接停止跟踪。

本轮模型隔离对照：同一初始通道、同一已保存角度、同一输入；目标距离1000km，以0.003°/s移动，位置与切向速度一致，dt=1s。原始会话一直跟踪；恢复成功后target_id为空，角度停在45°。**第123个继续tick起恢复通道变lost/fov_miss；第150tick原始仍locked、角度45.4499984884°，恢复为lost、角度45°。** 这是传感器模型对照，不是整场战役试玩或性能样本。

证据：[脚本](evidence/pointing_follow_probe.gd)、[JSON](evidence/pointing_follow.json)、[日志](evidence/pointing_follow.log)，退出1。修复须恢复完整动态指向（包括目标/模式），不把整份静态硬件或世界真值复制进运行态；旧档缺字段有明确迁移/部分恢复口径。不能用固定目标或仅10tick对照替代持续跟踪。

### G2：导入仍半写，新增子状态校验也不足

[sensor_authority.gd:48–71](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/framework/sim/sensor_authority.gd#L48)先改活动optical，再验证/导入TWS，最后验证authority元数据；optical失败也不阻止后续TWS写入。

上轮quick的两种反例仍成立：失败后child时钟5→77，或authority时钟5→99。新字段还增加两条确认：坏TWS被拒时optical.t已0→123；坏optical schema被拒时TWS.now_t已0→321。应暂存并完整验证所有层，全部成功才提交；任何失败保持原状态及后续行为不变。

新增Radar/TWS导入还接受：

- `version=999`；新schema却不校验version。
- `scan_index=1e100`，随后int溢出成`-9223372036854775808`；负运行时长也被接受。
- `channels={"broken":{}}`：导入成功，下一次step实际在`tws.gd:327`产生缺`last_update_t`的SCRIPT ERROR。
- 删除新格式的`radar`，仍成功留下TWS t=200、Radar t=0。这是缺子状态的静默拼接，不是完整恢复。

位置：[radar.gd:380–405](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/framework/sim/radar.gd#L380)、[tws.gd:551–578](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/framework/sim/tws.gd#L551)。光学az1000/el120也成功并被wrap/clamp为-80/90，与报告“范围外拒绝”的说法不同。

证据：[新增持久化审查脚本](evidence/save/new_sensor_state_audit.gd)、[父代理复跑](evidence/save/parent-repeat.log)、[前后JSON](evidence/save/parent-repeat.json)。1个有效往返对照通过，8个反例命中，退出1；SCRIPT ERROR为坏输入被错误接受后的实际失败，绝不算PASS。

### G3：上轮比较器漏检完整复现

比较器源码自`c58abc7`后未补这一缺口。在50tick合法对照通过后：allocator 220→320、事件payload替换、观测quality 1→0均仍返回`[]`。篡改通信正文后实际交付`TAMPERED_DELIVERY_CONTENT`，**即刻状态、继续10tick行为、最终状态三个检查仍均为`[]`**。

根因在[a0_save_cost_probe.gd:459–470](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/tests/a0_save_cost_probe.gd#L459)、[564–582](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/tests/a0_save_cost_probe.gd#L564)、[638–646](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/tests/a0_save_cost_probe.gd#L638)：事件/观测只比ID，在途只比ID@ETA，`CommsService.last_event()`不存在，两边都落为`{}`。需要比较有意义payload、上下文/接收者/路径/outcome、分配器值以及逐tick实际输出，列明真正可排除的诊断字段。

证据：[quick.log](evidence/quick.log)、[复现脚本](evidence/review65_probe.gd)，退出1、7个缺口命中。它不代表7个独立新bug，也不能将这些新反例登记为历史baseline。

## 3. K0：现有39/0不足以解锁A01

这是合同层的错误接受，**尚未证明当前游戏运行态已发生越权**；B00不要求实现完整部署/AI，但要求把后续实现所依赖的规则冻结。

| 缺口 | 当前代码与最小反例 | 原#57要求的修正 |
| --- | --- | --- |
| actor→controller未绑定 | [jc_contracts.gd:269–291](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/scripts/core/jc_contracts.gd#L269)：player_commander保持直接fire，改controller为ally_ai、域ally、shooter=I-AL1，仍ok | 明确actor授权注册/能力，直控与友军协同请求分开；own_ship旧调用须绑定真实本舰，不只信标签 |
| 情报引用/链路不成立仍接受 | :233–250：不存在observer/owner，observed=100/received=102但delay=999仍ok | 绑定合法observer/owner/共享授权及双时间关系；不是只要求非空字符串 |
| 选择/部署/幂等语义不足 | :177–214：selected=false仍部署；idempotent_replay=true可缺request_id；同key冲突实例仍ok | 保留选择映射，冻结幂等键与同载荷/冲突载荷语义、状态与时间关系；给真实负例 |
| 数值与单舰资源规则不稳 | :358–398：连续燃料3000.5kg被当整数拒绝，Inf质量/缺必要资源却接受；原生int绕过安全上限 | 区分连续物理量与计数，有限非负及安全范围；必要资源、实例引用和旧档缺省策略明确 |

还需修复roster跨舰队引用、空/重复command_id等已承诺的拒绝规则。详见[独立K0审查](evidence/k0/findings.md)、[变异脚本](evidence/k0/mutations.gd)、[JSON](evidence/k0/mutations.json)。诊断退出0表示执行完毕，15个错误/矛盾变体被接受，不表示合同正确。

[K0文档:157–158](https://github.com/HATO-24/ghost-track-apsis/blob/dc3821eda91d25f14e44dd9f57e6f5a985e04a9c/game_v17/docs/contracts/joint_campaign_r2.md#L157)还把每owner TrackTable/显式分区选择推迟到A01，与#57先比较并选择的要求相反。补齐情报融合方案、AI授权只读接口、命令/事件/请求回执执行生命周期字段和版本、旧档legacy scope及fixtures，再核对G0实际SHA；不需要在本卡实现AI或目标运行层。

## 4. P0：先消除内部矛盾，再请用户核对产品值

P0已正确标为提案，保持用户已确认的阶段性战区行动、自有直控＋友军请求。需要修正：

1. **真实目录引用。** proposal JSON:22–26把APSIS/HARMATTAN等命名舰/旧场景代号写成ship_class_id，真实Catalog使用如OCUVF-APOGEE等舰级ID；FERRIES拼写、SKIFF/RAIDER映射也未落实。采用canonical舰级ID＋可用命名舰/实例映射；新增舰级如确有必要，明确额外开发依赖。不得以自建点数表证明“舰型合法”。
2. **目标、终态、贡献要自洽。** 现有零目标完成的轨迹却判stalemate，与outcomes写零完成defeat矛盾；TR-ALLY-REFUSE在1000<3600且无撤离便结算；duplicate guard无目标完成却victory。补事件/裁决ID、胜败撤离时限的前提和同tick冲突优先级。友军造成真实失能应正常计目标，玩家有效贡献另判，并明确有效协同请求是否算贡献。
3. **权威与玩家获知分开。** pending_report必须是玩家视图，不能替代真实裁决；“全部已失能但尚未获报告”的轨迹需真覆盖全部前提，记录authority/player_known与observed/received。保护目标sector_civilian_relay、own_flag需要实体绑定、旗舰选择和损失后果。
4. **可实施机制与内容。** organic_fire_control/command_node不能只靠recoverable=false字符串成为既有能力。列实际损伤/指挥能力映射、未实现依赖与替代方案，补完整简报/战报、友军拒绝后的实际路线。解释100点＋3舰容量下预算的用途；当前自建舰池三舰都达不到100点。

现有probe还未检出这些关键约束：将舰级改为NO_SUCH_CATALOG_CLASS、容量改2但仍部署3舰、胜利轨迹删除全部失能事件，三个变体仍各**退出0、138/0**。原始生产文件未改，变体仅放测试临时目录。证据在[evidence/p0/](evidence/p0/)，复跑时仅将变体probe的SPEC绝对路径改为对应JSON的本机路径，保持校验逻辑不变。

本轮不把这些不一致的数字/目标直接交用户批准。#63先形成目录、机制、轨迹与反馈一致的方案，再核对战区/日期、舰池预算、目标阈值、3600s、保护损失和贡献计法；已经确认的两项范围不重问。

## 5. 原卡返修顺序与退出条件

- **#56**：完整动态指向→组合原子导入/版本/安全范围/完整子状态→补全比较器与真实payload故障注入。保留已绿200/400反例，同时加入移动目标持续跟踪、双方向拒绝后状态不变、未知版本/缺子段/畸形通道/溢出反例。先红证据，再最小修复与独立提交，最后同一代码SHA的四规模12样本正确性及C回归。
- **#57**：补actor与情报引用授权、部署选择/幂等、数值与资源语义，再冻结owner融合方案和读写/事件/迁移接口。保留现有正例，加不能用同步修改自声明表绕过的负例；暂不解锁#58。
- **#63**：把真实目录/预算约束、目标机制与终态轨迹、贡献与情报视图、保护绑定、简报战报补成一致提案。原案例和三个变异必须得到有意义的拒绝；仅做规格语义校验，不复制假的战役运行层算完成。

旧7项历史失败继续按#45–#48追踪；新缺口不能刷新baseline消失。#49的1000tick固定负载预算仍为1,500,000 UTF-8 B、保存250ms、构造＋恢复5000ms、读盘50ms。作者报告的体积/保存/恢复未达标交#49；**本轮阻断G0来自正确性/验收缺口，不将性能优化强塞成新的冻结前提**。

## 6. 命令、日志与证据口径

Godot`4.7.2.stable.official.ed1daf0bf`，Windows。专项命令：

归档脚本应在被审SHA`dc3821eda91d25f14e44dd9f57e6f5a985e04a9c`的独立副本执行。承载本报告的#64文档分支仅存交接材料，不作为该运行时代码基线。

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(core_time_event|track_table_probe|a0_(event_continuity|legacy_save|sensor_persistence|comms_restore|integration_authority|save_roundtrip_authority)|jc_contracts|jc_scenario_spec)' -Ci -ResultsDir .test-results/sol-r5/targeted
```

独立运行诊断：`godot --headless --path ./game_v17 --script <本目录evidence中脚本的绝对路径>`。`review65_probe.gd`继承候选中的benchmark工具，`A07_HEAD`设为实际HEAD，`SOL65_MODE=quick/200/400`分别运行；结果预期1/0/0。`pointing_follow_probe.gd`设置`R5_POINTING_OUT`为可写JSON绝对路径，预期1；save审查设置`SAVE_AUDIT_OUT`，预期1；K0脚本设置`JC_K0_AUDIT_OUTPUT`，预期0但应看到错误变体被接受。

归档保留stdout/stderr、脚本、JSON、校验manifest。脚本日志输出的是独立反例，不是游戏功能实现；本轮未修改生产源码、未合并PR、未重跑full/完整四规模/平台/渲染/整场试玩，未重新声称已达性能预算。原工作区资产/HUD未提交改动继续保留。
