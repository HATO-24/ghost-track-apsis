# APSIS 文档入口草案（Sol，2026-10-29）

状态：导航与编辑稿，不是新正典或运行验收。证据树为本机已取得的 `origin/main@4e75897ed32f8245f35c5ec584f0ec912ec919c6`。本机 `HEAD=62356da5d863326e77b070953eca55ba5833e49a` 且有未提交改动；本批只新增 `sol/` 文件，不触碰原文或代码。本地未跟踪的 56/60 与该树同名 blob 相同（`49d8f265`、`fb92f827`）。旧检出缺少的文档用固定提交的 GitHub 链接。

[Astra 产品、玩法与复古终端评审](../Astra_产品玩法与复古终端评审.md) 已给出新设计方向；[56 R2](../../../56_Astra_开发需求_交6Sol.md) 仍是联合战役基础需求，[60 UI 规范](../../../60_Astra_UI与文案设计规范_交Sol.md) 与 [61 实施队列](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/61_UI%E6%96%87%E6%A1%88%E5%8F%B0%E8%B4%A6%E4%B8%8E%E5%AE%9E%E6%96%BD%E9%98%9F%E5%88%97.md) 仍是 UI／文案执行链。本目录补充其缺口，不建立竞争性的主需求。

## 七类入口

| 类别 | 当前入口 | 深读与历史 | 阅读口径 |
| --- | --- | --- | --- |
| 产品 | [56 R2](../../../56_Astra_开发需求_交6Sol.md) §2.1、§6；[Astra 评审](../Astra_产品玩法与复古终端评审.md) §1–3 | [59 R2 范围／执行索引](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/59_%E8%81%94%E5%90%88%E6%88%98%E5%BD%B9Demo_R2_%E8%8C%83%E5%9B%B4%E4%B8%8E%E4%B8%8B%E4%B8%80%E6%89%B9%E4%BB%BB%E5%8A%A1%E5%8D%A1.md) | 一场剧情线外联合战役；单场局部成果不宣告第33舰队整体去军事化。 |
| 世界观／叙事 | [03 世界观](../../../03_世界观.md)、[44 主线剧本](../../../44_新剧本_2193.md)、[46 军队编制](../../../46_势力与军队编制.md) | [18 D2 目标节奏](../../../18_目标与节奏.md)、[21 正典](../../../21_D2正典纲要.md)、[45 对照](../../../45_新剧本需求对照表.md) | 主线日期和 Chronos 不交火情节不自动成为联合战役规则。 |
| 玩法规则 | [56](../../../56_Astra_开发需求_交6Sol.md) §6；[玩法修订稿](玩法决策与节奏修订提案.md) | [联合战役契约](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/game_v17/docs/contracts/joint_campaign_r2.md)、[B03P 提案](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/game_v17/docs/contracts/jc_sector_01_proposal.md)、[舰队服务](../../../../game_v17/docs/fleet_system.md) | 名册、契约和提案都不等于部署或 AI 已实现。 |
| UI 与玩家文案 | [60](../../../60_Astra_UI与文案设计规范_交Sol.md)、[61](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/61_UI%E6%96%87%E6%A1%88%E5%8F%B0%E8%B4%A6%E4%B8%8E%E5%AE%9E%E6%96%BD%E9%98%9F%E5%88%97.md)、[视觉补充](复古终端视觉补充与任务卡.md) | [文案清单](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/ui/20261027/copy_inventory.md)、[术语](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/ui/20261027/glossary.md)、[五状态样页](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/ui/20261027/five_state_specs.md)、[09 历史 UI](../../../09_UI设计.md)、[ui_v1 技术记录](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/game_v17/docs/ui_v1.md) | 去开发旁白，保留失败原因、命令阶段、权限、数据时效／有效性；正式 HUD 材质尚未验收。 |
| 工程契约 | [联合战役契约](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/game_v17/docs/contracts/joint_campaign_r2.md)、[40 工程审计](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/40_%E7%B3%BB%E7%BB%9F%E5%AE%8C%E6%88%90%E5%BA%A6%E5%A4%8D%E6%A0%B8%E4%B8%8E%E5%BC%80%E5%8F%91%E4%BB%BB%E5%8A%A1%E9%98%9F%E5%88%97.md) §3 | [37 架构](../../../37_真实空间与信息作战架构.md)、[Phase A 索引](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/game_v17/docs/a00_phase_a_index.md)、[profile](../../../../game_v17/docs/build_profiles.md) | 明确唯一写者、时间、权限、情报域与存档迁移。 |
| 执行／验收 | [59](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/59_%E8%81%94%E5%90%88%E6%88%98%E5%BD%B9Demo_R2_%E8%8C%83%E5%9B%B4%E4%B8%8E%E4%B8%8B%E4%B8%80%E6%89%B9%E4%BB%BB%E5%8A%A1%E5%8D%A1.md) 顶部／§3–5、[B01A 卡](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/tasks/joint_campaign/JC-B01A_deployment.md) | [58 历史审查](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/58_PhaseA_%E5%90%88%E5%B9%B6%E5%AE%A1%E6%9F%A5%E4%B8%8E%E4%B8%8B%E4%B8%80%E6%89%B9%E4%BB%BB%E5%8A%A1%E5%8D%A1.md)、[Phase A 验收](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/game_v17/docs/a01_integration_acceptance.md)、[UI-01](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/tasks/ui/UI-01_copy_mapping.md)～[UI-04](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/docs/tasks/ui/UI-04_phase_b_views.md) | 本快照记载 A4 合入、B01A 备好；不推断 B01A 已合入。 |
| 历史档案 | [01](../../../01_设计计划书.md)、[34 V2](../../../34_框架重写方案.md)、[35 V17 视觉](../../../35_V17视觉回退方案.md)、[40 V17 交付](../../../40_V17交付说明.md)、[43 旧待办](../../../43_开发待办清单.md) | [09](../../../09_UI设计.md)、[ui_v1](https://github.com/HATO-24/ghost-track-apsis/blob/4e75897ed32f8245f35c5ec584f0ec912ec919c6/game_v17/docs/ui_v1.md) | 保留当时版本、截图和测试结论，不将旧状态当现行事实。 |

## 本批交付

- [文档盘点与冲突台账](文档盘点与冲突台账.md)：具体冲突、来源提交和待核对事项。
- [文档重构批次与编辑任务卡](文档重构批次与编辑任务卡.md)：可逆索引、压缩、归档顺序。
- [玩法决策与节奏修订提案](玩法决策与节奏修订提案.md)：B03P 三处设计修订、两种编制和 30–45 分钟试玩目标。
- [复古终端视觉补充与任务卡](复古终端视觉补充与任务卡.md)：图形／材质／行为分层与正式 HUD 草案卡。
- [当前文档入口与迁移规则](当前文档入口与迁移规则.md)：当前／历史正文与适用模式。

分工：Astra 定玩法与视觉要求；Sol 编辑文档、文案和任务卡；DeepSeek 实现代码。本批未运行游戏测试，未读取 PureWriter。
