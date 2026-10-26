# PR #65 R8 独立复核与技术闸门（2026-10-26）

被审：`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`；上轮：`2ae7bf7cba8af32ff4456cefe28efa3650b868dd`。环境：Windows、Godot `4.7.2.stable.official.ed1daf0bf`。56 R2 源需求 SHA256 仍为 `5ED8C0C7080860381731253324679F6E119CAE4AC6D87645BAD0727FAF7CABA1`。

## 1. 技术闭环

| 原卡 / R7 剩余项 | R8 独立结果 |
|---|---|
| #56 必需字段 null 绕过 | 五种 null 载荷全部拒绝、状态不变；合法 STARE 可导入并继续，CLOSED |
| #56 旧 v1 partial 公共披露 | 真正 C55 文件公开 partial 及三个原因；新格式正对照 full、原因空，CLOSED |
| #56 历史满载漏比较 | 200 条满载下，相同输入无误报；实际同 ID/seq 投递的正文变化被 `comms.events.new` 检出，CLOSED |
| #56 原始长测日志未提交 | R8 stdout/stderr、JSON、summary 及满载输出均已 tracked，JSON 与 stdout 内嵌测量逐项相同，CLOSED |
| #57 seq、生命周期未知版本、显式接收 owner、合同同步 | 自带 84/0；独立 10 个门槛对照全部符合预期，原四项 CLOSED |

原 actor/shooter/owner/部署/command_id、原子导入、移动目标跟踪、allocator/payload 比较等已关闭项继续保留，不重开。生命周期反向时刻等原非阻塞观察不升级为新的前置要求。K0 的 legacy 可信本舰来源已经冻结，生产适配器按 A01 接入；不把纯结构校验器当成已实现的授权运行层。

窄复核：`evidence/save/findings.md`、`evidence/contracts/findings.md`，包含真正执行的脚本、正负例、JSON 和原始输出。未修改生产代码、baseline 或预算。

## 2. 长测证据与预算

作者测量代码 `196d53c04b85ef46305e96e88477588b54820bc0`；候选之后两个提交只归档证据/报告。四规模 50/200/800/1000 tick，每规模 1 warmup + 3 measured（12 个 measured，另有4个warmup）。作者原始结果 **90/0、1047.6 s**；本轮主审核对原始文件与 provenance，未另跑一次四规模长测。独立满载正负对照另有实际执行证据。

1000 tick 原始数据：2,172,752 UTF-8 B；save 423–619 ms（中位438）；恢复72,171–78,913 ms（中位74,895）；读盘6 ms。**#49 预算仍不达标**，保持每样本 ≤1,500,000 B / ≤250 ms / ≤5000 ms / ≤50 ms。

文档勘误：R8 benchmark README 末段仍写374/60244/5的旧数值，当前应以 raw JSON/stdout 中438/74895/6为准；返修报告提交列表曾写 d8b0b27，实际证据提交为 `fda3e043b97d9e3c11f59f0911ea9dd0ead0a654`。这是报告校正，不重开已归档的原始证据门槛。stderr 保留既有对象/资源清理诊断，不能声称零stderr。

## 3. P0 内容核对：技术可审，产品仍待确认

虚构实例映射已与既有 APSIS 分开，推荐预设与自由编制/池数量已写，贡献例外进入终态规则，具体简报/战报文本已补。场景探针通过只证明本提案 fixture 的一致性，不是联合战役可玩完成，也不自动批准100点/3舰、舰型、目标、日期或阈值。

Luna 发现两处产品文案仍需在最终核对前澄清，**不阻断 G0/K0 或 A01**：

1. 固定 `I-A1→HEMATITE` 与“任选舰作旗舰”不应同时作为当前规则。建议当前主案固定 I-A1 为编制内20点HEMATITE，玩家自由组合其余位置；任意舰级旗舰留为待用户选择的备选，明确重绑保护目标的规则后再采用。这只是内容建议，未替用户批准。
2. 无武装侦察/中继友军不能在本主案实际独自造成三个军事目标失能。全友军完成轨迹可保留为**反事实防御测试**：注入不可能的全部友军 credit，验证仍不授予玩家 victory；对应战报应标为合成测试输出、非主案可达战报。无需给友军新增武器或实现 AI。

以上补充是本次对 P0 草案的审阅口径；#63 保持开放，完成文本校正并核对具体产品选择后才能批准。原始逐项记录见 `p0_findings.md`，其两处发现按上述非阻塞严重性处理。

## 4. 回归、冻结与后续

根代理独立运行 **87=80 PASS / 7 历史 FAIL / 0 TIMEOUT / 0 NOT RUN，退出0、420.59s**。known_fail=7、new_fail=0、drift=0、unverified=0、unselected=0、complete=true。场景269/0、合同84/0、sensor-state45/0。结果见 `results.json` / `evidence/full/summary.json`，没有将历史 FAIL 改名为 PASS。统一导入由合同复核代理执行一次、退出0，根全量使用 `-NoImport` 复用同一缓存。

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -NoImport -Baseline game_v17/tests/known_baseline_failures.json -Ci -ResultsDir .test-results/sol-r8/full
```

候选精确 head 的 CI [40321597977](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40321597977) Phase0 / PhaseA / full 三项 success。独立回归完成，现冻结 **G0=K0=`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`**；同一提交同时承载基础整合和合同，名称不同不要求制造两个无意义的提交。

下一实现卡为 **#58 JC-A01**：按现有八段卡落真正指挥权限、每owner情报入口/读取/存档；保留红例、旧本舰兼容和真实文件恢复。先做这一张核心卡，#59–#62仍按原依赖等待，不并行重写 GameSession。#63的轻量文案校正可并行。

## 5. 合并与记录

已按用户此前的顺序合并要求完成 #32→#33→#34→#35→#36→#37→#38→#39→#54→#55→#65 共11个PR。堆叠 PR 的原 base 是前一功能分支，已逐个显式重定向到 main 并按预期 head 合并，未将合入前一分支误写为已进入 main。中间历史版本的失败由终端返修关闭，本次验收针对终端完整候选，不宣称每个旧 head 均全绿。

预合并检查：S7/C55/#54都是候选祖先；`git merge-tree --write-tree 9d0f3b4… 72064384…` 无冲突。实际生产合并后 main=`e5628ca088f25f49d129dff3f311b8fbac648fcd`，**整棵 tree 与候选完全相同**（`19f4097b29d0178b1f64423589b7f12a0212ca96`）；`game_v17` subtree=`ccfcded8e9e254fbc7726b4d75ad6628b05b3a9b`。逐项merge SHA见 `merge_ledger.json`。

此归档及任务卡通过 #64 最后合入，#64只改docs，不改生产代码；其最终合并SHA以PR元数据和任务卡最终记录为准，避免将文档自身SHA循环写入自身内容。合并后再核对生产 subtree，无需因纯文档合并重复420秒相同代码测试。

证据清单和SHA256见 `manifest.json`，原始输出以 `.txt` 保存。所有执行来源和局限分别列出；运行态联合战役、AI、跨平台、非headless与真实RF/光学物理未因此完成。
