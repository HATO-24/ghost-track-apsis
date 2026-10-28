# JC-B01A / #62 首轮：核心里程碑复核，原卡继续

日期：2026-10-29（Asia/Shanghai）。**尚未放行 D1，未合并 B01A 实现。** 被审交付是里程碑2，不是整张#62完成；DeepSeek自己的回报与core README均明确列出Binder、非headless和部分负例待完成。继续原[#62](https://github.com/HATO-24/ghost-track-apsis/issues/62)，不另派重复业务卡、不启动下一卡。

| 冻结 | 值 |
| --- | --- |
| 核心候选 | `7185b92e83482b731ca7d15da7765ae41eda7c4c`，分支`jc/b01a-deployment` |
| 基线 | `4e75897ed32f8245f35c5ec584f0ec912ec919c6`，包含获审 A4 |
| 根独立环境 | Windows / Godot4.7.2.stable.official.ed1daf0bf / headless |
| 交付状态 | 当时远程分支存在，尚无B01A PR；PR72属于已合入A04 |

## 已保留的绿项与证据界限

根独立卡指定专项**7/7 PASS**，部署probe **72/0**，退出0，耗时79.2s含36.6s导入。[完整summary](targeted/summary.json) / [逐项报告](targeted/report.md)。正常auto_seed路径下，A/B选择、catalog/world/physics实体集合、吨到千克只转换一次、独立燃料/损伤、合法幂等、真实文件资源保持和最终10tick运动一致等已有正例保留。生成资源桶不等于B1b逐舰武器配置或多舰开火完成。

DeepSeek所交core full摘要92=85PASS/7历史FAIL、new0/drift0/complete=true来自`39d51810`加dirty生产/probe；专项72/0也如此。它们是里程碑运行记录，不能称干净`7185b92e`最终验收。本轮根在干净候选上重新运行专项，完整原C等待整卡最后40位HEAD；未重复跑中间版full。七历史baseline SHA256 `5fdfb46a27d8d0057b50d51b3ceed87ce1d126a933db6b93f803a11e6ab2c9e4`，未刷新。

## 原卡范围内的返修与收尾

以下五个窄观察由一次独立诊断记录。诊断退出0表示记录完成，不表示要求已通过。[源码](diagnostic.gd) / [实际数据](diagnostic.json) / [日志](diagnostic.log) / [命令和限定](run.json)。使用原正式probe的现代seed夹具与合法A控制臂，没有修改生产、正式probe、matrix或退出码。

| 组 | 输入及实际结果 | 原卡要求的处理 |
| --- | --- | --- |
| R1 同源实体 | 原A控制臂，额外给既有`physics_world.entities`显式旧名单。Session ready=true，catalog/world为apsis、harmattan，physics却只有legacy_ship | 部署源须覆盖实际物理seed接点，不能让显式旧全名册优先；补该接点正式负例/正例。 |
| R2 归属/权限 | A中APSIS controller改为`unregistered_controller`，仍在player域。ready=true且资源行保留非法controller，域授权只有player_ctrl | 按已有command_domains/authorized_actors及owner/fleet映射校验，原“无授权控制者”须拒绝且原子；保留合法own及独立ally边界。无需新增认证体系。 |
| R3 旧seed文件覆盖活跃会话 | 无deployment的旧单舰seed先保存到真实文件（本候选产生，deployment=null），加载到已有A部署的Session，返回ok；三层实体已为old_ship，但VM仍deployed=true、apsis/harmattan资源仍可读 | boot/load完整清理部署生命周期；兼容无deployment/absent旧档，不能混留上一局。此文件不是历史提交归档旧fixture，需保留真正旧档控制。 |
| R3 恢复完整性 | 既有有效export仅把resources置空，load_state返回full；VM仍声明两实例，却各为空，apsis查询unknown_instance | 原配置/实例/资源集合一致性校验，明确拒绝不完整状态，失败不破坏原有效状态；不扩安全攻击测试。 |
| R4 冻结配置 | 相同scenario/seed/选择，仅APSIS位置100→200km，部署entities确实不同，revision却均rev-f8328109 | revision覆盖实际冻结配置/几何或显式配置版本；保留同选择同配置幂等，不把不同配置认作同一冻结。 |

R4另有静态缺口：当前实例行只冻结舰级、质量、燃料、归属；`ammo=0/loadout={}`是占位，没有冻结既有装备配置/版本与命令初态。原卡要求逐实例初态/配置快照；只接已有数据和明确缺失状态，不在此实现B1b发射或完整改装。初始资源不能仅因空桶互不共享就宣称装备配置已经接通。

R5原卡交付收尾：Binder最小DEPLOY_PLAN/DEPLOY与真实确认/结果/拒绝原因、原最小非headless选择→部署操作/截图、重复命名舰/越预算/无控制者等原负例、同tick映射与10tick事件连续性、最终报告与新B01A PR尚待完成。当前正式10tick仅比较最终运动，丢弃tick返回事件。补充时保留已有正例，不能用headless probe替代实际入口。

静态边界提醒：当前预部署应用先清空world/physics，再构建选择舰；现有场景目标/设施等非选择对象的接入不得被这一全清路径吞掉。此项未在本次五观察中另跑场景保留复现，不将其写成已测结果，也不要求新建实体体系。

## 交回原卡

Sol已在DSH实际发送原卡收尾说明：DeepSeek实现运行代码，GPT/Sol维护UI设计合同；继续#62，核心已实现部分保留，暂不启动B01B/B01C。请在最终同40位HEAD交付卡指定专项和原C（Phase0、PhaseA、strict baseline-aware full）、真实文件续行和最小非headless证据。七历史baseline、A4固定fixture、低质量可射击语义保持；不扩AI/RF/完整战役试玩/预算产品取舍。

本报告只归档本轮已确认状态；后续HEAD需要重新核对关闭表，不把此处观察机械套到新代码。Linux/macOS、真实RF/光学、>1000tick成本本轮NOT RUN。无B01A合入或D1完成结论。
