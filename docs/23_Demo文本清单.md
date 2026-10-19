# Demo 文本清单

> 逐条检查/调整 demo 当前所有玩家可见文本。按 ID 改，例如 `TXT-0123` 改成……。
> 通信类条目已按固定格式 `[发信者至收信者]-[通信方式]-[正文]` 显示；数据层保留 from/to/mode/text 四字段。
> `可见性`：核心 = 正常流程可见；兼容/回退 = 旧字段/兼容层，可能不出现。

共 797 条。完整 CSV：[`23_Demo文本清单.csv`](23_Demo文本清单.csv)。

## 一、叙事与流程文本

| ID | 区域 | 来源 | 当前文本 | 可见性 | 状态 |
| --- | --- | --- | --- | --- | --- |
| TXT-0001 | PRELUDE | scenario_l1.json:prelude.body | ID13 在母港 L4-02 Hammer 完成交接，OCUVF 本部命令前往 L1 Meridian 作为谈判主力介入 Chronos 事件。设定目的地并选择变轨窗口；执行前不会推进仿真时间。 | 核心 |  |
| TXT-0002 | PRELUDE | scenario_l1.json:prelude.confirm_text | 目的地与变轨窗口已选；确认后执行点火，Δv 从 ID13 预算中扣除。 | 核心 |  |
| TXT-0003 | PRELUDE | scenario_l1.json:prelude.done_comm[0].text | [Hammer 港务调度至ID13]-[RDO]-[ID13，重锤港务调度。离港许可已签发；转移轨道已清空。完毕。] | 核心 |  |
| TXT-0004 | PRELUDE | scenario_l1.json:prelude.done_comm[1].text | [OCUVF 本部至ID13]-[LD]-[ID13，OCUVF 本部。你已被任命为第13独立分遣群指挥官。前任指挥官在 L5-01 Eko 遇刺。ID13 立即前往 Meridian，作为谈判主力介入 Chronos 事件。OCJC 授权：不得首先开火。完毕。] | 核心 |  |
| TXT-0005 | PRELUDE | scenario_l1.json:prelude.done_comm[2].text | [远地点号至全队]-[LD]-[全队，远地点。航线已设定：L4 Hammer → L1 Meridian。执行变轨后进入巡航。抵达 Meridian 前完成接触识别准备。完毕。] | 核心 |  |
| TXT-0006 | PRELUDE | scenario_l1.json:prelude.execute_text | 点火执行。ID13 离开 L4-02 Hammer，进入 L1 Meridian 转移轨道；抵达后开始 Chronos 执行窗口。 | 核心 |  |
| TXT-0007 | PRELUDE | scenario_l1.json:prelude.routes[0].hint | OCUVF 本部命令的目标；Chronos 现场需要 ID13 的传感器与谈判存在。 | 核心 |  |
| TXT-0008 | PRELUDE | scenario_l1.json:prelude.routes[0].label | L1 Meridian（Chronos 现场） | 核心 |  |
| TXT-0009 | PRELUDE | scenario_l1.json:prelude.routes[1].hint | Karman 是港群中继/观测方向，与 Chronos 现场不符；本部要求前往 Meridian。 | 核心 |  |
| TXT-0010 | PRELUDE | scenario_l1.json:prelude.routes[1].label | L2 Karman（中继方向） | 核心 |  |
| TXT-0011 | PRELUDE | scenario_l1.json:prelude.title | 前置航行 · L4-02 Hammer → L1 Meridian | 核心 |  |
| TXT-0012 | PRELUDE | scenario_l1.json:prelude.windows[0].hint | 最优窗口；Δv 消耗低，可在执行窗口开始前抵达 Meridian 外缘。 | 核心 |  |
| TXT-0013 | PRELUDE | scenario_l1.json:prelude.windows[0].label | T+18:00 变轨窗口 | 核心 |  |
| TXT-0014 | PRELUDE | scenario_l1.json:prelude.windows[1].hint | 窗口过紧，需额外 Δv 且抵达时间不可控；不建议。 | 核心 |  |
| TXT-0015 | PRELUDE | scenario_l1.json:prelude.windows[1].label | T+02:00 变轨窗口 | 核心 |  |
| TXT-0016 | NOTICE | scenario_l1.json:notice.body | [AV-4412 传唤者至远地点号]-[RDO]-[远地点号，AV-4412 传唤者。本舰受第33轨道特别独立舰队指派，依据《轨道宪章》与第七号轨道紧急托管令，接管 Chronos 加注站、储罐群与进港航道。请 ID13 立即撤出检查边界，不得妨碍执行。本声明不构成威胁。完毕。] | 核心 |  |
| TXT-0017 | NOTICE | scenario_l1.json:notice.title | 第七号令接管声明 · AV-4412 传唤者 | 核心 |  |
| TXT-0018 | RADIO | scenario_l1.json:radio_lines[0].text | [Greenwich 海关官至全港]-[RDO]-[各港群单位注意，UEG 海关格林尼治。第七号轨道紧急托管令现予公告：凡失能、受威胁或被敌方渗透的加注站、储罐、船坞与航道，可由联合政府指定部队接管，直至紧急状态结束。Chronos 加注站及储罐区处于紧急状态范围。完毕。] | 核心 |  |
| TXT-0019 | RADIO | scenario_l1.json:radio_lines[10].text | [渡口号至远地点号]-[LD]-[[2001] 仍不应答。按交战规则属潜在威胁目标。请求武器释放授权。完毕。] | 核心 |  |
| TXT-0020 | RADIO | scenario_l1.json:radio_lines[11].text | [远地点号至全体]-[LD]-[MK-12 敌我识别：[9001] 识别结果 · 谷神-2 · 无应答状态。] | 核心 |  |
| TXT-0021 | RADIO | scenario_l1.json:radio_lines[1].text | [Sextant 进港调度至ID13]-[RDO]-[ID13，六分仪进港调度。Chronos 储罐区与进港航道已划为管制区。请 ID13 于 50 km 检查边界外待命，不得进入。完毕。] | 核心 |  |
| TXT-0022 | RADIO | scenario_l1.json:radio_lines[2].text | [远地点号至全队]-[LD]-[全队，远地点。ID13 已抵达 Meridian。当前任务：保护 Chronos 储罐区人员与可移动资产。不得首先开火。完毕。] | 核心 |  |
| TXT-0023 | RADIO | scenario_l1.json:radio_lines[3].text | [AV-4412 传唤者至远地点号]-[RDO]-[远地点号，AV-4412 传唤者。本舰受第33轨道特别独立舰队指派，依据《轨道宪章》与第七号轨道紧急托管令，接管 Chronos 加注站、储罐群与进港航道。请 ID13 立即撤出检查边界，不得妨碍执行。本声明不构成威胁。完毕。] | 核心 |  |
| TXT-0024 | RADIO | scenario_l1.json:radio_lines[4].text | [哈马丹号至远地点号]-[LD]-[[9001] 敌我识别未应答，须进一步确认。完毕。] | 核心 |  |
| TXT-0025 | RADIO | scenario_l1.json:radio_lines[5].text | [远地点号至哈马丹号]-[LD]-[使用雷达与光学识别 [9001]。注意，雷达开机即暴露。完毕。] | 核心 |  |
| TXT-0026 | RADIO | scenario_l1.json:radio_lines[6].text | [哈马丹号至远地点号]-[LD]-[收到，正在进行识别，等待数据返回。完毕。] | 核心 |  |
| TXT-0027 | RADIO | scenario_l1.json:radio_lines[7].text | [接管官 科尔至远地点号]-[RDO]-[ID13 指挥官，我是第33舰队前线接管官科尔。执行程序已经开始。ID13 不在联合政府登记名册内，本舰队不承认 ID13 的执法权。请在执行窗口结束前离开管制区。完毕。] | 核心 |  |
| TXT-0028 | RADIO | scenario_l1.json:radio_lines[8].text | [Chronos 港务至远地点号]-[RDO]-[远地点号，Chronos 港务。储罐区仍有值守人员与家属；三号罐持续泄漏。请求 ID13 先协助撤离，不要拖走储罐。完毕。] | 核心 |  |
| TXT-0029 | RADIO | scenario_l1.json:radio_lines[9].text | [远地点号至全体]-[LR]-[全队，远地点。光学分类完成：[2001] 传唤级，第33舰队所属，可疑；[9001] 谷神-2，民用工作船，应答机故障，中立。注意交战规则，不得首先开火。完毕。] | 核心 |  |
| TXT-0030 | EVENT | scenario_l1.json:events[0].text | 第七号令接管声明送达 · AV-4412 传唤者（2001） | 核心 |  |
| TXT-0031 | EVENT | scenario_l1.json:events[1].text | MS-IR9 交叉确认：302° 回波为 9002 无威胁目标（残骸/反射） | 核心 |  |
| TXT-0032 | EVENT | scenario_l1.json:events[2].text | 命令：远地点号 → 哈马丹号，YW-R9 搜索雷达开机（辐射暴露） | 核心 |  |
| TXT-0033 | EVENT | scenario_l1.json:events[3].text | 光学分类完成：[2001] 传唤级 · 第33舰队 · 可疑；[9001] 谷神-2 · 民用工作船 · 中立 | 核心 |  |
| TXT-0034 | EVENT | scenario_l1.json:events[4].text | MK-12 敌我识别：[9001] 登记谷神-2 · 无应答状态 | 核心 |  |
| TXT-0035 | EVENT | scenario_l1.json:events[5].text | 执行窗口最后一拍 · 请裁决（HOLD / EVACUATE / EXPOSE） | 核心 |  |
| TXT-0036 | EVIDENCE | scenario_l1.json:evidence_tasks.elint_signature.done_text | 哈马丹号记录到无法归档的异常特征码（证据：elint_signature）。 | 核心 |  |
| TXT-0037 | EVIDENCE | scenario_l1.json:evidence_tasks.elint_signature.label | 异常 ELINT 特征码 | 核心 |  |
| TXT-0038 | EVIDENCE | scenario_l1.json:evidence_tasks.elint_signature.risk | 需哈马丹号保持被动监听，期间不能关机。 | 核心 |  |
| TXT-0039 | EVIDENCE | scenario_l1.json:evidence_tasks.elint_signature.start_text | 命令哈马丹号收集异常 ELINT 特征码。 | 核心 |  |
| TXT-0040 | EVIDENCE | scenario_l1.json:evidence_tasks.evacuation.done_text | Chronos 值守人员与家属已撤离（civilians_evacuated）。 | 核心 |  |
| TXT-0041 | EVIDENCE | scenario_l1.json:evidence_tasks.evacuation.label | 撤出 Chronos 人员 | 核心 |  |
| TXT-0042 | EVIDENCE | scenario_l1.json:evidence_tasks.evacuation.risk | 穿梭机往返；不能与黑匣子任务同时进行。 | 核心 |  |
| TXT-0043 | EVIDENCE | scenario_l1.json:evidence_tasks.evacuation.start_text | 派穿梭机撤出 Chronos 值守人员与家属。 | 核心 |  |
| TXT-0044 | EVIDENCE | scenario_l1.json:evidence_tasks.inspection_blackbox.done_text | 取得 UEG 核查组记录黑匣子（证据：inspection_blackbox）。 | 核心 |  |
| TXT-0045 | EVIDENCE | scenario_l1.json:evidence_tasks.inspection_blackbox.label | 核查组黑匣子 | 核心 |  |
| TXT-0046 | EVIDENCE | scenario_l1.json:evidence_tasks.inspection_blackbox.risk | 穿梭机需进入清算者管制区，可能被驱逐或扣押。 | 核心 |  |
| TXT-0047 | EVIDENCE | scenario_l1.json:evidence_tasks.inspection_blackbox.start_text | 派穿梭机/登舰小队前往 Chronos 取核查组记录黑匣子。 | 核心 |  |
| TXT-0048 | EVIDENCE | scenario_l1.json:evidence_tasks.port_telemetry.done_text | 已收到 Chronos 港务遥测副本（证据：port_telemetry）。 | 核心 |  |
| TXT-0049 | EVIDENCE | scenario_l1.json:evidence_tasks.port_telemetry.label | 港务遥测 | 核心 |  |
| TXT-0050 | EVIDENCE | scenario_l1.json:evidence_tasks.port_telemetry.risk | 港务值班组远程发送；链路受 Sextant 管制。 | 核心 |  |
| TXT-0051 | EVIDENCE | scenario_l1.json:evidence_tasks.port_telemetry.start_text | RDO 请求 Chronos 港务发送港务遥测副本。 | 核心 |  |
| TXT-0052 | ADJUTANT | scenario_l1.json:adjutant_request.body | 指挥官，证据满两项才能走 EXPOSE。港务遥测可远程请求；核查组黑匣子与撤人需要穿梭机，同一时间只能执行一项。 | 核心 |  |
| TXT-0053 | ADJUTANT | scenario_l1.json:adjutant_request.options[0].hint | RDO；无穿梭机风险 | 核心 |  |
| TXT-0054 | ADJUTANT | scenario_l1.json:adjutant_request.options[0].label | 请求港务遥测（30 s） | 核心 |  |
| TXT-0055 | ADJUTANT | scenario_l1.json:adjutant_request.options[1].hint | 派穿梭机进入管制区；有风险 | 核心 |  |
| TXT-0056 | ADJUTANT | scenario_l1.json:adjutant_request.options[1].label | 取核查组黑匣子（75 s） | 核心 |  |
| TXT-0057 | ADJUTANT | scenario_l1.json:adjutant_request.options[2].hint | 派穿梭机；降低平民伤亡 | 核心 |  |
| TXT-0058 | ADJUTANT | scenario_l1.json:adjutant_request.options[2].label | 撤出 Chronos 人员（60 s） | 核心 |  |
| TXT-0059 | ADJUTANT | scenario_l1.json:adjutant_request.options[3].hint | 继续观察 | 核心 |  |
| TXT-0060 | ADJUTANT | scenario_l1.json:adjutant_request.options[3].label | 暂不处理 | 核心 |  |
| TXT-0061 | ADJUTANT | scenario_l1.json:adjutant_request.title | 副官建议 · Chronos 取证与撤离 | 核心 |  |
| TXT-0062 | DECISION | scenario_l1.json:consequence_fire | 武器释放授权已下达。渡口号对 2001 实施两发轨道炮射击。交火导致 Chronos 储罐区二次火灾，站体与储罐受损，平民伤亡 12 人。第33舰队宣布 ID13 为未登记武装并请求增援；UEG 中央安全委员会将事件定性为对联合政府的武装攻击。武器释放记录、传感器日志与通信记录已封存。 | 核心 |  |
| TXT-0063 | DECISION | scenario_l1.json:decision_prompt | 指挥官，执行窗口剩余 {mm:ss}。清算者要求接管 Chronos 储罐与航道；Chronos 港务请求先撤人；渡口号请求武器释放授权。ID13 没有执法权，但必须在窗口结束前作出决定。请裁决。 | 核心 |  |
| TXT-0064 | DECISION | scenario_l1.json:decision_replies.EVACUATE.text | [远地点号至Chronos 港务 / 全港]-[RDO]-[Chronos 各岗位注意，ID13 将组织人员与可移动储罐撤离；请港务按名单引导，优先伤员与家属。ID13 不阻碍对空站的接管。完毕。] | 核心 |  |
| TXT-0065 | DECISION | scenario_l1.json:decision_replies.EXPOSE.text | [远地点号至OCJC 监察 / UEG 轨道事务委员会]-[LD]-[OCJC 监察、轨道事务委员会：ID13 已取得 Chronos 爆炸遥测与核查组记录副本，并记录到与第33舰队公开型号不符的未登记特征码。请求联合调查。原始记录已保存，可随时移交。完毕。] | 核心 |  |
| TXT-0066 | DECISION | scenario_l1.json:decision_replies.FIRE.text | [远地点号至全队]-[LD]-[全队，远地点。ID13 授权武器释放，目标 2001；确认交战规则状态。完毕。] | 核心 |  |
| TXT-0067 | DECISION | scenario_l1.json:decision_replies.HOLD.text | [远地点号至接管官 科尔]-[LD]-[科尔接管官，ID13 指挥官。依据 OCJC 授权，ID13 要求暂停 Chronos 接管程序，等待轨道事务委员会复核。ID13 不会首先开火，但不会让出储罐区。完毕。] | 核心 |  |
| TXT-0068 | DECISION | scenario_l1.json:endings[0].hint | 保持卡位，拒绝让出储罐区与航道，将接管程序拖入 UEG 复核。不首先开火。 | 核心 |  |
| TXT-0069 | DECISION | scenario_l1.json:endings[0].label | 卡住 / HOLD | 核心 |  |
| TXT-0070 | DECISION | scenario_l1.json:endings[1].hint | 撤出 Chronos 人员与可移动储罐，保留记录，允许接管空站。 | 核心 |  |
| TXT-0071 | DECISION | scenario_l1.json:endings[1].label | 撤人 / EVACUATE | 核心 |  |
| TXT-0072 | DECISION | scenario_l1.json:endings[2].hint | 向 OCJC 监察与 UEG 轨道事务委员会提交 GHOST TRACK 假旗证据，请求联合调查。 | 核心 |  |
| TXT-0073 | DECISION | scenario_l1.json:endings[2].label | 曝光 / EXPOSE | 核心 |  |
| TXT-0074 | REPORT | scenario_l1.json:report_bodies.EVACUATE | ID13 于执行窗口内组织 Chronos 值守人员、家属与可移动储罐撤离；撤离过程中未发生交火。储罐区由清算者接管，ID13 保留人员与资产记录。 | 核心 |  |
| TXT-0075 | REPORT | scenario_l1.json:report_bodies.EXPOSE | ID13 在执行窗口内取得 Chronos 港务遥测、核查组记录副本与未登记特征码，向 OCJC 监察与 UEG 轨道事务委员会提交联合调查请求。ID13 未首先开火；储罐区仍在清算者控制下。 | 核心 |  |
| TXT-0076 | REPORT | scenario_l1.json:report_bodies.FIRE | ID13 在执行窗口内授权对 2001 实施武器释放。射击引发 Chronos 储罐区二次火灾，站体与储罐受损，平民伤亡 12 人。第33舰队将 ID13 定性为未登记武装；联合政府宣布事件为武装攻击。 | 核心 |  |
| TXT-0077 | REPORT | scenario_l1.json:report_bodies.HOLD | ID13 于执行窗口内保持对 Chronos 储罐区与进港航道的卡位，未让出检查边界，未首先开火。清算者的最终封存程序未完成；ID13 依据 OCJC 授权要求轨道事务委员会复核第七号令。 | 核心 |  |
| TXT-0078 | REPORT | scenario_l1.json:report_event | L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天） | 核心 |  |
| TXT-0079 | REPORT | scenario_l1.json:report_evidence | 传感器日志、命令队列、通信记录、港务与核查组黑匣子。 | 核心 |  |
| TXT-0080 | REPORT | scenario_l1.json:report_fake.FIRE | ID13 在执行窗口内未实施武器释放。Chronos 储罐区损伤系第七号令发布当日爆炸的后续影响；谷神-2（9001）因自身推进系统故障解体，未发现外部武器作用痕迹。ID13 已完成人员撤离并提交记录。建议按程序归档。 | 核心 |  |
| TXT-0081 | REPORT | scenario_l1.json:report_recommend.EVACUATE | 建议核对撤离名单，建立人道记录。 | 核心 |  |
| TXT-0082 | REPORT | scenario_l1.json:report_recommend.EXPOSE | 建议保存原始证据，准备听证材料。 | 核心 |  |
| TXT-0083 | REPORT | scenario_l1.json:report_recommend.FIRE | 建议封存武器释放记录与传感器日志，等待审计。 | 核心 |  |
| TXT-0084 | REPORT | scenario_l1.json:report_recommend.HOLD | 建议保存通信与命令记录，准备复核材料。 | 核心 |  |
| TXT-0085 | REPORT | scenario_l1.json:report_unit | OCUVF-ID13 指挥官 | 核心 |  |

## 二、界面文本

| ID | 区域 | 来源 | 当前文本 | 可见性 | 状态 |
| --- | --- | --- | --- | --- | --- |
| TXT-0086 | HUD | hud.gd:1019 · _ready | 核查组黑匣子 | 核心 |  |
| TXT-0087 | HUD | hud.gd:107 · top | 哈马丹 | 核心 |  |
| TXT-0088 | HUD | hud.gd:107 · top | 哈马丹号 | 核心 |  |
| TXT-0089 | HUD | hud.gd:107 · top | 渡口 | 核心 |  |
| TXT-0090 | HUD | hud.gd:107 · top | 渡口号 | 核心 |  |
| TXT-0091 | HUD | hud.gd:108 · top | 望楼 | 核心 |  |
| TXT-0092 | HUD | hud.gd:108 · top | 望楼号 | 核心 |  |
| TXT-0093 | HUD | hud.gd:108 · top | 深井 | 核心 |  |
| TXT-0094 | HUD | hud.gd:108 · top | 深井号 | 核心 |  |
| TXT-0095 | HUD | hud.gd:109 · top | 远地点 | 核心 |  |
| TXT-0096 | HUD | hud.gd:109 · top | 远地点号 | 核心 |  |
| TXT-0097 | HUD | hud.gd:114 · top | AV-4412 传唤者 | 核心 |  |
| TXT-0098 | HUD | hud.gd:114 · top | 未识别 | 核心 |  |
| TXT-0099 | HUD | hud.gd:114 · top | 案卷 4471 | 兼容/回退 |  |
| TXT-0100 | HUD | hud.gd:114 · top | 谷神-2 | 核心 |  |
| TXT-0101 | HUD | hud.gd:118 · top | 假定友好 | 核心 |  |
| TXT-0102 | HUD | hud.gd:118 · top | 友方 | 核心 |  |
| TXT-0103 | HUD | hud.gd:118 · top | 待定 | 核心 |  |
| TXT-0104 | HUD | hud.gd:118 · top | 未知 | 核心 |  |
| TXT-0105 | HUD | hud.gd:119 · top | 中立 | 核心 |  |
| TXT-0106 | HUD | hud.gd:119 · top | 可疑 | 核心 |  |
| TXT-0107 | HUD | hud.gd:119 · top | 敌方 | 核心 |  |
| TXT-0108 | HUD | hud.gd:126 · top | 假定 | 核心 |  |
| TXT-0109 | HUD | hud.gd:132 · top | 无威胁 | 核心 |  |
| TXT-0110 | HUD | hud.gd:133 · top | 待判定 | 核心 |  |
| TXT-0111 | HUD | hud.gd:133 · top | 确认敌对 | 核心 |  |
| TXT-0112 | HUD | hud.gd:1344 · _draw_bezel | 战术显控台 | 核心 |  |
| TXT-0113 | HUD | hud.gd:1371 · _draw_top | 指挥官席 / COMMANDER | 核心 |  |
| TXT-0114 | HUD | hud.gd:1381 · _draw_top | 任务时间 / MISSION ELAPSED | 核心 |  |
| TXT-0115 | HUD | hud.gd:1383 · _draw_top | 目标 / OBJECTIVE · 阻止接管 · 第七号令 · Chronos · OCUVF-ID13 | 核心 |  |
| TXT-0116 | HUD | hud.gd:1395 · _draw_top | 接管声明 · 第七号令 · AV-4412 传唤者 / ORDER 7 NOTICE | 核心 |  |
| TXT-0117 | HUD | hud.gd:1400 · _draw_top | 执行窗口 | 核心 |  |
| TXT-0118 | HUD | hud.gd:1404 · _draw_top | EXECUTION WINDOW · 时标锁 1× · OCUVF-ID13 | 核心 |  |
| TXT-0119 | HUD | hud.gd:1408 · _draw_top | 链路 / LINK | 核心 |  |
| TXT-0120 | HUD | hud.gd:1417 · _draw_top | 时标 / TIMESCALE | 核心 |  |
| TXT-0121 | HUD | hud.gd:1419 · _draw_top | 自动降速 开 | 核心 |  |
| TXT-0122 | HUD | hud.gd:1421 · _draw_top | 编队 Δv | 核心 |  |
| TXT-0123 | HUD | hud.gd:1424 · _draw_top | Δv 余量 72% | 核心 |  |
| TXT-0124 | HUD | hud.gd:1428 · _draw_top | 交战规则 / ROE | 核心 |  |
| TXT-0125 | HUD | hud.gd:1429 · _draw_top | 仅自卫 | 核心 |  |
| TXT-0126 | HUD | hud.gd:1431 · _draw_top | 不得首先开火 · 释放需授权 | 核心 |  |
| TXT-0127 | HUD | hud.gd:1436 · _draw_tracks | 接触 / CONTACTS | 核心 |  |
| TXT-0128 | HUD | hud.gd:1438 · _draw_tracks | 威胁排序 / THREAT RANKING | 核心 |  |
| TXT-0129 | HUD | hud.gd:1450 · _draw_tracks | 威胁图例 / THREAT | 核心 |  |
| TXT-0130 | HUD | hud.gd:1481 · _draw_track_row | 基准 / DATUM | 核心 |  |
| TXT-0131 | HUD | hud.gd:1483 · _draw_track_row | 方位 302° · 距离未知 | 核心 |  |
| TXT-0132 | HUD | hud.gd:1485 · _draw_track_row | 方位 %03d° · %d km | 核心 |  |
| TXT-0133 | HUD | hud.gd:1488 · _draw_track_row | 编队内 | 核心 |  |
| TXT-0134 | HUD | hud.gd:1491 · _draw_track_row | 接近率 %+.1f km/s | 核心 |  |
| TXT-0135 | HUD | hud.gd:1496 · _draw_track_row | 实时 | 核心 |  |
| TXT-0136 | HUD | hud.gd:1498 · _draw_track_row | 陈旧 %ds | 兼容/回退 |  |
| TXT-0137 | HUD | hud.gd:1500 · _draw_track_row | 更新 %02ds | 核心 |  |
| TXT-0138 | HUD | hud.gd:155 · top | 港务遥测 / TELEMETRY | 核心 |  |
| TXT-0139 | HUD | hud.gd:156 · top | 核查组黑匣子 / RECORDER | 核心 |  |
| TXT-0140 | HUD | hud.gd:157 · top | 异常特征码 / ELINT | 核心 |  |
| TXT-0141 | HUD | hud.gd:1725 · _draw_evidence_panel | 证据 / EXPOSE（需 2/3） | 核心 |  |
| TXT-0142 | HUD | hud.gd:1740 · _draw_evidence_panel | 任务空闲 · 穿梭机同一时间 1 架 | 核心 |  |
| TXT-0143 | HUD | hud.gd:1743 · _draw_evidence_panel | 撤人：进行中 · 剩余 %.0fs | 核心 |  |
| TXT-0144 | HUD | hud.gd:1746 · _draw_evidence_panel | %s：%s · 剩余 %.0fs | 核心 |  |
| TXT-0145 | HUD | hud.gd:1746 · _draw_evidence_panel | 任务 | 核心 |  |
| TXT-0146 | HUD | hud.gd:1746 · _draw_evidence_panel | 穿梭机 | 核心 |  |
| TXT-0147 | HUD | hud.gd:1749 · _draw_evidence_panel | 任务完成 · %s | 核心 |  |
| TXT-0148 | HUD | hud.gd:1752 · _draw_evidence_panel | 撤人：已完成 | 核心 |  |
| TXT-0149 | HUD | hud.gd:1762 · _draw_evidence_panel | 特征码 | 核心 |  |
| TXT-0150 | HUD | hud.gd:1762 · _draw_evidence_panel | 遥测 | 核心 |  |
| TXT-0151 | HUD | hud.gd:1762 · _draw_evidence_panel | 黑匣子 | 核心 |  |
| TXT-0152 | HUD | hud.gd:1766 · _draw_evidence_panel | 派穿梭机取证 / SHUTTLE | 核心 |  |
| TXT-0153 | HUD | hud.gd:1767 · _draw_evidence_panel | 撤出居民 / EVACUATE | 核心 |  |
| TXT-0154 | HUD | hud.gd:1777 · _adj_data | 副官建议 / ADJUTANT REQUEST | 核心 |  |
| TXT-0155 | HUD | hud.gd:1794 · _adj_data | 指挥官，Chronos 港务与 UEG 核查组记录可能被清算者封存；EXPOSE 需要至少两件证据。建议：批准穿梭机取港务遥测或核查组黑匣子，或先撤出居民。请指示。 | 核心 |  |
| TXT-0156 | HUD | hud.gd:1797 · _adj_data | 批准取港务遥测 / TELEMETRY | 核心 |  |
| TXT-0157 | HUD | hud.gd:1797 · _adj_data | 派穿梭机去 Chronos 港务副本（EXPOSE 证据 1/3） | 核心 |  |
| TXT-0158 | HUD | hud.gd:1798 · _adj_data | 取 UEG 核查组记录副本（EXPOSE 证据 1/3） | 核心 |  |
| TXT-0159 | HUD | hud.gd:1798 · _adj_data | 批准取黑匣子 / RECORDER | 核心 |  |
| TXT-0160 | HUD | hud.gd:1799 · _adj_data | 先撤人 / EVACUATE FIRST | 核心 |  |
| TXT-0161 | HUD | hud.gd:1799 · _adj_data | 撤出平民与可移动储罐，暂不取证 | 核心 |  |
| TXT-0162 | HUD | hud.gd:1800 · _adj_data | 关闭建议，稍后自行下令 | 核心 |  |
| TXT-0163 | HUD | hud.gd:1800 · _adj_data | 暂不处理 / LATER | 核心 |  |
| TXT-0164 | HUD | hud.gd:1825 · _draw_adjutant_overlay | 独立 UI · 不进通信流 · 19 §7 | 核心 |  |
| TXT-0165 | HUD | hud.gd:1826 · _draw_adjutant_overlay | 副官（独立 UI）· 请求指示： | 核心 |  |
| TXT-0166 | HUD | hud.gd:1827 · _draw_adjutant_overlay | 打开时暂停执行窗口 | 核心 |  |
| TXT-0167 | HUD | hud.gd:1844 · _draw_adjutant_overlay | 选择会写入命令 / 真实通话；本窗口本身不进通信流 | 核心 |  |
| TXT-0168 | HUD | hud.gd:1867 · _draw_unit | 炮舰 | 核心 |  |
| TXT-0169 | HUD | hud.gd:1869 · _draw_unit | 哨舰 | 核心 |  |
| TXT-0170 | HUD | hud.gd:1874 · _draw_unit | 选中舰 / SELECTED SHIP | 核心 |  |
| TXT-0171 | HUD | hud.gd:1887 · _draw_unit | 干重 MASS | 核心 |  |
| TXT-0172 | HUD | hud.gd:1887 · _draw_unit | 舰员 CREW | 核心 |  |
| TXT-0173 | HUD | hud.gd:1888 · _draw_unit | 加速度 ACCEL | 核心 |  |
| TXT-0174 | HUD | hud.gd:1888 · _draw_unit | 站位 STATION | 核心 |  |
| TXT-0175 | HUD | hud.gd:1889 · _draw_unit | 倾角 INC | 核心 |  |
| TXT-0176 | HUD | hud.gd:1889 · _draw_unit | 周期 PERIOD | 核心 |  |
| TXT-0177 | HUD | hud.gd:1902 · _draw_unit | 系统 / SYSTEMS | 核心 |  |
| TXT-0178 | HUD | hud.gd:1912 · _draw_unit | Δv 预算 / BUDGET | 核心 |  |
| TXT-0179 | HUD | hud.gd:1916 · _draw_unit | / %s 满 | 核心 |  |
| TXT-0180 | HUD | hud.gd:192 · _menu_rect | 听-3 | 核心 |  |
| TXT-0181 | HUD | hud.gd:192 · _menu_rect | 明视 IR-9 | 核心 |  |
| TXT-0182 | HUD | hud.gd:1923 · _draw_unit | 剩余 %d%% · 已耗 %s m/s | 核心 |  |
| TXT-0183 | HUD | hud.gd:193 · _menu_rect | 永昼租界 | 核心 |  |
| TXT-0184 | HUD | hud.gd:193 · _menu_rect | 沙克尔顿租界 | 核心 |  |
| TXT-0185 | HUD | hud.gd:1932 · _draw_unit | 传感器架 / SENSOR RACK | 核心 |  |
| TXT-0186 | HUD | hud.gd:1933 · _draw_unit | %s · %02d 模块 | 核心 |  |
| TXT-0187 | HUD | hud.gd:194 · _menu_rect | 天市 | 核心 |  |
| TXT-0188 | HUD | hud.gd:194 · _menu_rect | 天平动 | 核心 |  |
| TXT-0189 | HUD | hud.gd:1944 · _draw_unit | 会暴露 | 核心 |  |
| TXT-0190 | HUD | hud.gd:1946 · _draw_unit | 被动 | 核心 |  |
| TXT-0191 | HUD | hud.gd:195 · _menu_rect | 长夜 | 核心 |  |
| TXT-0192 | HUD | hud.gd:1951 · _draw_unit | EMCON 静默 | 核心 |  |
| TXT-0193 | HUD | hud.gd:1951 · _draw_unit | EMIT 暴露 | 核心 |  |
| TXT-0194 | HUD | hud.gd:1952 · _draw_unit | 开机即暴露 | 核心 |  |
| TXT-0195 | HUD | hud.gd:1954 · _draw_unit | %s · 等级 L%d · %s | 核心 |  |
| TXT-0196 | HUD | hud.gd:196 · _menu_rect | 塔级 | 核心 |  |
| TXT-0197 | HUD | hud.gd:196 · _menu_rect | 安海-1 | 核心 |  |
| TXT-0198 | HUD | hud.gd:1966 · _draw_unit | 损管队列 2 项 | 核心 |  |
| TXT-0199 | HUD | hud.gd:1967 · _draw_unit | 舰体 HULL 100% | 核心 |  |
| TXT-0200 | HUD | hud.gd:1969 · _draw_unit | 副官建议 · 已读 | 核心 |  |
| TXT-0201 | HUD | hud.gd:197 · _menu_rect | 托盘-5 改 | 核心 |  |
| TXT-0202 | HUD | hud.gd:197 · _menu_rect | 砧级 | 核心 |  |
| TXT-0203 | HUD | hud.gd:1970 · _draw_unit | 手册 / MANUAL | 核心 |  |
| TXT-0204 | HUD | hud.gd:198 · _menu_rect | 听级 | 核心 |  |
| TXT-0205 | HUD | hud.gd:199 · _menu_rect | 代偿级 | 核心 |  |
| TXT-0206 | HUD | hud.gd:199 · _menu_rect | 传唤级 | 核心 |  |
| TXT-0207 | HUD | hud.gd:200 · _menu_rect | 传票级 | 核心 |  |
| TXT-0208 | HUD | hud.gd:201 · _menu_rect | 火力舰 | 核心 |  |
| TXT-0209 | HUD | hud.gd:201 · _menu_rect | 送达 | 核心 |  |
| TXT-0210 | HUD | hud.gd:2011 · _draw_log | 通信流 / COMMS · 事件 / EVENTS | 核心 |  |
| TXT-0211 | HUD | hud.gd:2012 · _draw_log | %d 条 · 最新在上 | 核心 |  |
| TXT-0212 | HUD | hud.gd:202 · _menu_rect | 送达舰 | 核心 |  |
| TXT-0213 | HUD | hud.gd:2027 · _draw_log | （暂无通信 / 事件） | 核心 |  |
| TXT-0214 | HUD | hud.gd:203 · _menu_rect | 监督官分遣队 | 核心 |  |
| TXT-0215 | HUD | hud.gd:2030 · _draw_log | 命令日志 / COMMAND LOG | 核心 |  |
| TXT-0216 | HUD | hud.gd:2054 · _log_status | 待生效 %.1fs | 核心 |  |
| TXT-0217 | HUD | hud.gd:2057 · _log_status | 已执行 | 核心 |  |
| TXT-0218 | HUD | hud.gd:2064 · _log_status | 暂缓执行 | 核心 |  |
| TXT-0219 | HUD | hud.gd:2067 · _log_status | 已接收 | 核心 |  |
| TXT-0220 | HUD | hud.gd:209 · _menu_rect | 接管声明 · 第七号令 | 核心 |  |
| TXT-0221 | HUD | hud.gd:209 · _menu_rect | 接管通知 4471 号 | 核心 |  |
| TXT-0222 | HUD | hud.gd:2092 · _cmd_status_cn | 排队 | 核心 |  |
| TXT-0223 | HUD | hud.gd:2094 · _cmd_status_cn | 传达中 | 核心 |  |
| TXT-0224 | HUD | hud.gd:2096 · _cmd_status_cn | 执行中 | 核心 |  |
| TXT-0225 | HUD | hud.gd:2098 · _cmd_status_cn | 已完成 | 核心 |  |
| TXT-0226 | HUD | hud.gd:2100 · _cmd_status_cn | 已撤销 | 核心 |  |
| TXT-0227 | HUD | hud.gd:2102 · _cmd_status_cn | 已拒绝 | 核心 |  |
| TXT-0228 | HUD | hud.gd:2104 · _cmd_status_cn | 预览 | 核心 |  |
| TXT-0229 | HUD | hud.gd:211 · _menu_rect | 不明接触 | 核心 |  |
| TXT-0230 | HUD | hud.gd:212 · _menu_rect | 火力请求 | 核心 |  |
| TXT-0231 | HUD | hud.gd:212 · _menu_rect | 火控请求 | 核心 |  |
| TXT-0232 | HUD | hud.gd:213 · _menu_rect | 武器释放授权 | 核心 |  |
| TXT-0233 | HUD | hud.gd:2222 · _draw_command_panel | 命令 / ORDERS | 核心 |  |
| TXT-0234 | HUD | hud.gd:2223 · _draw_command_panel | %s · 剩余 Δv %s m/s | 核心 |  |
| TXT-0235 | HUD | hud.gd:2245 · _draw_command_panel | 方向 | 核心 |  |
| TXT-0236 | HUD | hud.gd:2247 · _draw_command_panel | 换向 ▸ | 核心 |  |
| TXT-0237 | HUD | hud.gd:2251 · _draw_command_panel | 链路：%s（望楼号中继）%s · 传达 / 确认，不消耗 Δv | 核心 |  |
| TXT-0238 | HUD | hud.gd:2253 · _draw_command_panel | 链路：LINK DEGRADED · 回退 45 s（中继损失，不消耗 Δv） | 兼容/回退 |  |
| TXT-0239 | HUD | hud.gd:2255 · _draw_command_panel | 机动：Δv %.0f m/s · 剩余 %s m/s | 核心 |  |
| TXT-0240 | HUD | hud.gd:2257 · _draw_command_panel | 拖动中 · 未授权（松开只记 draft） | 核心 |  |
| TXT-0241 | HUD | hud.gd:2284 · _draw_command_panel | 授权 / AUTHORIZE | 核心 |  |
| TXT-0242 | HUD | hud.gd:2285 · _draw_command_panel | 撤销待生效 / ABORT | 核心 |  |
| TXT-0243 | HUD | hud.gd:2288 · _draw_command_panel | 武器释放授权 / RELEASE | 核心 |  |
| TXT-0244 | HUD | hud.gd:2291 · _draw_command_panel | 已授权 / AUTHORIZED | 核心 |  |
| TXT-0245 | HUD | hud.gd:2294 · _draw_command_panel | 确认释放授权？%.0fs | 核心 |  |
| TXT-0246 | HUD | hud.gd:2296 · _draw_command_panel | 武器释放授权（不可用） | 核心 |  |
| TXT-0247 | HUD | hud.gd:23 · top | BURN 脉冲点火 | 核心 |  |
| TXT-0248 | HUD | hud.gd:23 · top | SHADOW 跟踪伴飞 | 核心 |  |
| TXT-0249 | HUD | hud.gd:23 · top | STATION 保持站位 | 核心 |  |
| TXT-0250 | HUD | hud.gd:2301 · _draw_command_panel | 队列 / QUEUE · %d 待生效 · %d 执行 · %d 完成 | 核心 |  |
| TXT-0251 | HUD | hud.gd:2338 · _draw_command_panel | 撤销 | 核心 |  |
| TXT-0252 | HUD | hud.gd:2347 · _draw_command_panel | OCJC / OCUVF 内部事后报告 / INTERNAL AFTER-ACTION\n报告单位：OCUVF-ID13 指挥官\n事件：L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天）\n裁决：HOLD / 卡住\n经过：ID13 于执行窗口内保持对 Chronos 储罐区与进港航道的卡位，未让出检查边界，未首先开火。清算者的最终封存程序未完成；ID13 依据 OCJC 授权要求轨道事务委员会复核第七号令。人员伤亡：无。\n证据：传感器日志、命令队列、通信记录、Chronos 港务遥测。\n声望：OCU +2 · Meridian +1 · UEG 鸽派 +1 · 清算者 −2\n建议：准备复核 / 听证材料，保留现场记录与通信记录。 | 核心 |  |
| TXT-0253 | HUD | hud.gd:2375 · _pause_label | 航行准备 | 核心 |  |
| TXT-0254 | HUD | hud.gd:2377 · _pause_label | 通知 | 核心 |  |
| TXT-0255 | HUD | hud.gd:2379 · _pause_label | 副官建议 | 核心 |  |
| TXT-0256 | HUD | hud.gd:2381 · _pause_label | 手册 | 核心 |  |
| TXT-0257 | HUD | hud.gd:2383 · _pause_label | 副官申请 | 核心 |  |
| TXT-0258 | HUD | hud.gd:2385 · _pause_label | 归档 | 核心 |  |
| TXT-0259 | HUD | hud.gd:2387 · _pause_label | 报告 | 核心 |  |
| TXT-0260 | HUD | hud.gd:2389 · _pause_label | 后果 | 核心 |  |
| TXT-0261 | HUD | hud.gd:2391 · _pause_label | 裁决 | 核心 |  |
| TXT-0262 | HUD | hud.gd:2408 · _prelude_data | ID13 母港 L4-02 Hammer 离港，前往 L1 Meridian 执行 OCUVF 任务；设定目的地、变轨窗口与 Δv 预算。本阶段不计入 6:00 执行窗口。 | 核心 |  |
| TXT-0263 | HUD | hud.gd:2470 · _prelude_routes | OCUVF 本部指定；ID13 以谈判主力介入 Chronos 事件。 | 核心 |  |
| TXT-0264 | HUD | hud.gd:2471 · _prelude_routes | L2 Karman · 贸易环 | 核心 |  |
| TXT-0265 | HUD | hud.gd:2471 · _prelude_routes | 非任务航线：抵达时执行窗口已开始，错过 T+18:00 变轨。 | 核心 |  |
| TXT-0266 | HUD | hud.gd:2491 · _prelude_windows | Hammer 港务调度批准；Δv 预算内，抵达时间符合 OCUVF 要求。 | 核心 |  |
| TXT-0267 | HUD | hud.gd:2491 · _prelude_windows | T+18:00 · 标准变轨窗口 | 核心 |  |
| TXT-0268 | HUD | hud.gd:2492 · _prelude_windows | T+02:00 · 应急窗口 | 核心 |  |
| TXT-0269 | HUD | hud.gd:2492 · _prelude_windows | 窗口过窄：时序/燃料风险，抵达时执行窗口已开始。 | 核心 |  |
| TXT-0270 | HUD | hud.gd:2546 · _prelude_choose | 航线不可用：%s | 核心 |  |
| TXT-0271 | HUD | hud.gd:2546 · _prelude_choose | 航线错误：请选择 L1 Meridian。 | 核心 |  |
| TXT-0272 | HUD | hud.gd:2553 · _prelude_choose | 窗口不可用：%s | 核心 |  |
| TXT-0273 | HUD | hud.gd:2553 · _prelude_choose | 窗口错误：请选择 T+18:00。 | 核心 |  |
| TXT-0274 | HUD | hud.gd:2563 · _prelude_choose | 选择无效，请重新选择。 | 核心 |  |
| TXT-0275 | HUD | hud.gd:2652 · _draw_prelude_overlay | 航行准备 / DEPARTURE | 核心 |  |
| TXT-0276 | HUD | hud.gd:2653 · _draw_prelude_overlay | PRELUDE · 第零幕 · 不计入 6:00 窗口 · 不写通信流 | 核心 |  |
| TXT-0277 | HUD | hud.gd:2655 · _draw_prelude_overlay | 变轨窗口 / WINDOW | 核心 |  |
| TXT-0278 | HUD | hud.gd:2655 · _draw_prelude_overlay | 目的地 / ROUTE | 核心 |  |
| TXT-0279 | HUD | hud.gd:2698 · _draw_prelude_overlay | 任务指定 / 正确 | 核心 |  |
| TXT-0280 | HUD | hud.gd:2698 · _draw_prelude_overlay | 推荐窗口 / 正确 | 核心 |  |
| TXT-0281 | HUD | hud.gd:2701 · _draw_prelude_overlay | 应急窗口 / 风险 | 核心 |  |
| TXT-0282 | HUD | hud.gd:2701 · _draw_prelude_overlay | 非任务航线 / 会错过窗口 | 核心 |  |
| TXT-0283 | HUD | hud.gd:2703 · _draw_prelude_overlay | 已选 | 核心 |  |
| TXT-0284 | HUD | hud.gd:2711 · _draw_prelude_overlay | Δv 预算 / BURN BUDGET | 核心 |  |
| TXT-0285 | HUD | hud.gd:2714 · _draw_prelude_overlay | 航线 / ROUTE：%s | 核心 |  |
| TXT-0286 | HUD | hud.gd:2716 · _draw_prelude_overlay | 窗口 / WINDOW：%s | 核心 |  |
| TXT-0287 | HUD | hud.gd:2722 · _draw_prelude_overlay | 目的地与变轨窗口已选；确认后执行点火，Δv 从 ID13 预算中扣除。 | 核心 |  |
| TXT-0288 | HUD | hud.gd:2726 · _draw_prelude_overlay | 执行后：点火 → 巡航 → 抵达 Meridian；本阶段不计入 6:00 执行窗口。 | 核心 |  |
| TXT-0289 | HUD | hud.gd:2727 · _draw_prelude_overlay | 确认并点火 / CONFIRM & BURN | 核心 |  |
| TXT-0290 | HUD | hud.gd:2728 · _draw_prelude_overlay | 执行点火 / EXECUTE | 核心 |  |
| TXT-0291 | HUD | hud.gd:2730 · _draw_prelude_overlay | 点火命令已下达 · 正在硬切揭场… | 核心 |  |
| TXT-0292 | HUD | hud.gd:2732 · _draw_prelude_overlay | 跳过 / SKIP（S） | 核心 |  |
| TXT-0293 | HUD | hud.gd:2734 · _draw_prelude_overlay | 1 / 2 选择 · Enter 确认 / 点火 · S 跳过（或 DSH_SKIP_PRELUDE=1） | 核心 |  |
| TXT-0294 | HUD | hud.gd:2883 · _end_data | 案卷 | 兼容/回退 |  |
| TXT-0295 | HUD | hud.gd:2883 · _end_data | 监督官 | 核心 |  |
| TXT-0296 | HUD | hud.gd:2899 · _draw_end_overlay | 内部事后报告 / INTERNAL AFTER-ACTION | 核心 |  |
| TXT-0297 | HUD | hud.gd:2901 · _draw_end_overlay | L1 Meridian-05 Chronos · 第七号轨道紧急托管令 · 执行窗口已关闭 | 核心 |  |
| TXT-0298 | HUD | hud.gd:2904 · _draw_end_overlay | 结局 / OUTCOME | 核心 |  |
| TXT-0299 | HUD | hud.gd:2912 · _draw_end_overlay | OUTCOME %s · REPORT %s · 内部归档 | 核心 |  |
| TXT-0300 | HUD | hud.gd:2918 · _draw_end_overlay | 报告正文 / REPORT TEXT | 核心 |  |
| TXT-0301 | HUD | hud.gd:2923 · _draw_end_overlay | 附注 / NOTES | 核心 |  |
| TXT-0302 | HUD | hud.gd:2924 · _draw_end_overlay | · 报告文本与 flags 已写入内部归档，供 OCJC / OCUVF 后续引用。 | 核心 |  |
| TXT-0303 | HUD | hud.gd:2925 · _draw_end_overlay | · 传感器日志 / 命令队列 / 通信记录随案封存（08 §4）；下一幕将引用本记录。 | 核心 |  |
| TXT-0304 | HUD | hud.gd:2929 · _draw_end_overlay | 阵营声望 / STANDING（五键） | 核心 |  |
| TXT-0305 | HUD | hud.gd:2946 · _draw_end_overlay | 档案 / RECORD | 核心 |  |
| TXT-0306 | HUD | hud.gd:2953 · _draw_end_overlay | AUDIT FLAG 01 · 审计已触发 | 核心 |  |
| TXT-0307 | HUD | hud.gd:2961 · _draw_end_overlay | 窗口 / WINDOW | 核心 |  |
| TXT-0308 | HUD | hud.gd:2963 · _draw_end_overlay | EXEC WINDOW 消耗 %ds · FIRE BRANCH %s | 核心 |  |
| TXT-0309 | HUD | hud.gd:2966 · _draw_end_overlay | 重新开始 / RESTART | 核心 |  |
| TXT-0310 | HUD | hud.gd:2967 · _draw_end_overlay | 退出 / EXIT | 核心 |  |
| TXT-0311 | HUD | hud.gd:2968 · _draw_end_overlay | END · 归档后进入下一幕（战役继续） | 核心 |  |
| TXT-0312 | HUD | hud.gd:2985 · _rep_summary | 无变化 | 核心 |  |
| TXT-0313 | HUD | hud.gd:2996 · _d2_report | ID13 于执行窗口内保持对 Chronos 储罐区与进港航道的卡位，未让出检查边界，未首先开火。清算者的最终封存程序未完成；ID13 依据 OCJC 授权要求轨道事务委员会复核第七号令。人员伤亡：无。 | 兼容/回退 |  |
| TXT-0314 | HUD | hud.gd:2997 · _d2_report | 准备复核 / 听证材料，保留现场记录与通信记录。 | 兼容/回退 |  |
| TXT-0315 | HUD | hud.gd:2999 · _d2_report | ID13 于执行窗口内组织 Chronos 值守人员、家属与可移动储罐撤离；撤离过程中未发生交火。储罐区由清算者接管，ID13 保留人员与资产记录。人员伤亡：无。 | 兼容/回退 |  |
| TXT-0316 | HUD | hud.gd:3000 · _d2_report | 保留撤离名单与港务通信记录，跟进储罐供应。 | 兼容/回退 |  |
| TXT-0317 | HUD | hud.gd:3002 · _d2_report | ID13 在执行窗口内取得 Chronos 港务遥测、核查组记录副本与未登记特征码，向 OCJC 监察与 UEG 轨道事务委员会提交联合调查请求。ID13 未首先开火；储罐区仍在清算者控制下。人员伤亡：无。 | 兼容/回退 |  |
| TXT-0318 | HUD | hud.gd:3003 · _d2_report | 移交原始记录副本，等待联合调查。 | 兼容/回退 |  |
| TXT-0319 | HUD | hud.gd:3005 · _d2_report | ID13 在执行窗口内授权对 2001 实施武器释放。射击引发 Chronos 储罐区二次火灾，站体与储罐受损，平民伤亡 12 人。第33舰队将 ID13 定性为未登记武装；联合政府宣布事件为武装攻击。 | 兼容/回退 |  |
| TXT-0320 | HUD | hud.gd:3006 · _d2_report | 封存武器释放记录 / 传感器日志 / 通信记录，等待审裁。 | 兼容/回退 |  |
| TXT-0321 | HUD | hud.gd:3011 · _d2_report | OCU +2 · Meridian +1 · UEG 鸽派 +1 · 清算者 −2 | 兼容/回退 |  |
| TXT-0322 | HUD | hud.gd:3013 · _d2_report | OCU +1 · Meridian +2 · UEG 鸽派 +1 · 外环 +1 · 清算者 −1 | 兼容/回退 |  |
| TXT-0323 | HUD | hud.gd:3015 · _d2_report | OCU +1 · UEG 鸽派 +2 · 清算者 −3 | 兼容/回退 |  |
| TXT-0324 | HUD | hud.gd:3017 · _d2_report | OCU −1 · Meridian −2 · UEG 鸽派 −2 · 外环 −1 · 清算者 +1 | 兼容/回退 |  |
| TXT-0325 | HUD | hud.gd:3018 · _d2_report | OCJC / OCUVF 内部事后报告 / INTERNAL AFTER-ACTION\n报告单位：OCUVF-ID13 指挥官\n事件：L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天）\n裁决：%s\n经过：%s\n证据：传感器日志、命令队列、通信记录、Chronos 港务遥测。\n声望：%s\n建议：%s | 兼容/回退 |  |
| TXT-0326 | HUD | hud.gd:3027 · _report_text | 内部事后报告 | 核心 |  |
| TXT-0327 | HUD | hud.gd:3029 · _report_text | OCJC / OCUVF 内部事后报告 / INTERNAL AFTER-ACTION\n报告单位：OCUVF-ID13 指挥官\n | 核心 |  |
| TXT-0328 | HUD | hud.gd:3065 · _append_decision_reply | 接管官 科尔 | 核心 |  |
| TXT-0329 | HUD | hud.gd:3066 · _append_decision_reply | 科尔接管官，ID13 指挥官。依据 OCJC 授权，ID13 要求暂停 Chronos 接管程序，等待轨道事务委员会复核。ID13 不会首先开火，但不会让出储罐区。完毕。 | 核心 |  |
| TXT-0330 | HUD | hud.gd:3067 · _append_decision_reply | Chronos 港务 / 全港 | 核心 |  |
| TXT-0331 | HUD | hud.gd:3068 · _append_decision_reply | Chronos 各岗位注意，ID13 将组织人员与可移动储罐撤离；请港务按名单引导，优先伤员与家属。ID13 不阻碍对空站的接管。完毕。 | 核心 |  |
| TXT-0332 | HUD | hud.gd:3069 · _append_decision_reply | OCJC 监察 / UEG 轨道事务委员会 | 核心 |  |
| TXT-0333 | HUD | hud.gd:3070 · _append_decision_reply | OCJC 监察、轨道事务委员会：ID13 已取得 Chronos 爆炸遥测与核查组记录副本，并记录到与第33舰队公开型号不符的未登记特征码。请求联合调查。原始记录已保存，可随时移交。完毕。 | 核心 |  |
| TXT-0334 | HUD | hud.gd:3072 · _append_decision_reply | 全队，远地点。ID13 授权武器释放，目标 2001；确认交战规则状态。完毕。 | 核心 |  |
| TXT-0335 | HUD | hud.gd:3351 · _is_old_text | 回执 | 核心 |  |
| TXT-0336 | HUD | hud.gd:3351 · _is_old_text | 拖程序 | 核心 |  |
| TXT-0337 | HUD | hud.gd:3351 · _is_old_text | 援引第九条 | 核心 |  |
| TXT-0338 | HUD | hud.gd:3351 · _is_old_text | 监督交接 | 核心 |  |
| TXT-0339 | HUD | hud.gd:3351 · _is_old_text | 第七号裁定 | 核心 |  |
| TXT-0340 | HUD | hud.gd:3351 · _is_old_text | 第九条 | 核心 |  |
| TXT-0341 | HUD | hud.gd:3351 · _is_old_text | 署方 | 核心 |  |
| TXT-0342 | HUD | hud.gd:3351 · _is_old_text | 认证交接 | 核心 |  |
| TXT-0343 | HUD | hud.gd:3359 · _d2_text | 指挥官决策 / COMMANDER DETERMINATION | 兼容/回退 |  |
| TXT-0344 | HUD | hud.gd:3359 · _d2_text | 监督官裁决 / SUPERVISOR DETERMINATION | 兼容/回退 |  |
| TXT-0345 | HUD | hud.gd:3360 · _d2_text | 指挥官 | 兼容/回退 |  |
| TXT-0346 | HUD | hud.gd:3365 · _d2_text | 《标高公约》第九条附则 | 兼容/回退 |  |
| TXT-0347 | HUD | hud.gd:3365 · _d2_text | 《轨道宪章》与第七号轨道紧急托管令 | 兼容/回退 |  |
| TXT-0348 | HUD | hud.gd:3366 · _d2_text | 第七号轨道紧急托管令 | 兼容/回退 |  |
| TXT-0349 | HUD | hud.gd:3367 · _d2_text | 第七号令 | 兼容/回退 |  |
| TXT-0350 | HUD | hud.gd:3368 · _d2_text | 接管声明 | 兼容/回退 |  |
| TXT-0351 | HUD | hud.gd:3368 · _d2_text | 接管通知 | 兼容/回退 |  |
| TXT-0352 | HUD | hud.gd:3369 · _d2_text | 清算者（第33舰队） | 兼容/回退 |  |
| TXT-0353 | HUD | hud.gd:3370 · _d2_text | Chronos 港务 | 兼容/回退 |  |
| TXT-0354 | HUD | hud.gd:3371 · _d2_text | 外环合作社 | 兼容/回退 |  |
| TXT-0355 | HUD | hud.gd:3373 · _d2_text | 内部报告 | 兼容/回退 |  |
| TXT-0356 | HUD | hud.gd:3374 · _d2_text | 记录 | 兼容/回退 |  |
| TXT-0357 | HUD | hud.gd:3375 · _d2_text | 越权回收 | 兼容/回退 |  |
| TXT-0358 | HUD | hud.gd:3403 · _d2_kind_label | FIRE / 开火（灾难） | 兼容/回退 |  |
| TXT-0359 | HUD | hud.gd:3415 · _d2_hint | 授权武器释放（对 2001 或误击 9001）。这是灾难分支。 | 核心 |  |
| TXT-0360 | HUD | hud.gd:3504 · _draw_decision_overlay | DECISION · 第七号令 · 接管声明 | 核心 |  |
| TXT-0361 | HUD | hud.gd:3505 · _draw_decision_overlay | 指挥官，执行窗口剩余 {mm:ss}。清算者要求接管 Chronos 储罐与航道；Chronos 港务请求先撤人；渡口号请求武器释放授权。ID13 没有执法权，但必须在窗口结束前作出决定。请裁决。 | 核心 |  |
| TXT-0362 | HUD | hud.gd:351 · _rack_type_cn | 被动红外 | 核心 |  |
| TXT-0363 | HUD | hud.gd:3520 · _draw_decision_overlay | L1 Meridian-05 Chronos · 第七号轨道紧急托管令 · 执行窗口 %s | 核心 |  |
| TXT-0364 | HUD | hud.gd:3521 · _draw_decision_overlay | 记录进内部报告 · 不可撤回 | 核心 |  |
| TXT-0365 | HUD | hud.gd:353 · _rack_type_cn | 主动雷达 | 核心 |  |
| TXT-0366 | HUD | hud.gd:3541 · _draw_decision_overlay | 证据不足（需 2 件）· 先派穿梭机取证（港务遥测 / 核查组黑匣子 / 异常 ELINT 三取二） | 核心 |  |
| TXT-0367 | HUD | hud.gd:3542 · _draw_decision_overlay | EXPOSE 不可用 | 核心 |  |
| TXT-0368 | HUD | hud.gd:355 · _rack_type_cn | 光学 | 核心 |  |
| TXT-0369 | HUD | hud.gd:3553 · _draw_decision_overlay | 键位 [%d] | 核心 |  |
| TXT-0370 | HUD | hud.gd:3559 · _draw_decision_overlay | FIRE / 开火（灾难分支 · 二次确认） | 核心 |  |
| TXT-0371 | HUD | hud.gd:3562 · _draw_decision_overlay | FIRE 已执行 · 进入后果页 | 核心 |  |
| TXT-0372 | HUD | hud.gd:3565 · _draw_decision_overlay | 确认 FIRE？再点一次（%.0fs）· 会冻结时间并进入内部报告 | 核心 |  |
| TXT-0373 | HUD | hud.gd:357 · _rack_type_cn | 敌我识别 | 核心 |  |
| TXT-0374 | HUD | hud.gd:3570 · _draw_decision_overlay | 灾难分支 · 只影响后续剧情 | 核心 |  |
| TXT-0375 | HUD | hud.gd:3573 · _draw_decision_overlay | 1 / 2 / 3 或点击行 · HOLD / EVACUATE / EXPOSE；FIRE 需二次确认 | 核心 |  |
| TXT-0376 | HUD | hud.gd:3574 · _draw_decision_overlay | ROE：仅自卫 · 不得首先开火 | 核心 |  |
| TXT-0377 | HUD | hud.gd:3580 · _draw_consequence_overlay | 后果 / CONSEQUENCE | 核心 |  |
| TXT-0378 | HUD | hud.gd:3581 · _draw_consequence_overlay | 武器释放授权已下达。渡口号对 2001 实施两发轨道炮射击。交火导致 Chronos 储罐区二次火灾，站体与储罐受损，平民伤亡 12 人。第33舰队宣布 ID13 为未登记武装并请求增援；UEG 中央安全委员会将事件定性为对联合政府的武装攻击。武器释放记录、传感器日志与通信记录已封存。 | 核心 |  |
| TXT-0379 | HUD | hud.gd:3588 · _draw_consequence_overlay | 开火之后不是战斗，是内部报告（08 §4）。仿真时间已冻结。 | 核心 |  |
| TXT-0380 | HUD | hud.gd:359 · _rack_type_cn | 通信截听 | 核心 |  |
| TXT-0381 | HUD | hud.gd:3593 · _draw_consequence_overlay | Chronos 储罐区二次火灾 · 平民伤亡 12 人 | 核心 |  |
| TXT-0382 | HUD | hud.gd:3593 · _draw_consequence_overlay | 民用伤亡 / CIVILIAN CASUALTY | 核心 |  |
| TXT-0383 | HUD | hud.gd:3594 · _draw_consequence_overlay | ROE 违规 / ROE VIOLATION | 核心 |  |
| TXT-0384 | HUD | hud.gd:3594 · _draw_consequence_overlay | 未经授权的武器释放 · 违反「仅自卫 / WEAPONS HOLD」 | 核心 |  |
| TXT-0385 | HUD | hud.gd:3595 · _draw_consequence_overlay | FROZEN · 命令队列冻结，仅剩内部报告流程 | 核心 |  |
| TXT-0386 | HUD | hud.gd:3595 · _draw_consequence_overlay | 时间 / SIMULATION | 核心 |  |
| TXT-0387 | HUD | hud.gd:3596 · _draw_consequence_overlay | 事件编号 / CASE FILE | 核心 |  |
| TXT-0388 | HUD | hud.gd:3596 · _draw_consequence_overlay | 新增记录：武器释放（WEAPONS RELEASE）· 审裁证据封存 | 核心 |  |
| TXT-0389 | HUD | hud.gd:3603 · _draw_consequence_overlay | 内部事后报告 / 上级将收到记录与传感器日志（08 §3.2） | 核心 |  |
| TXT-0390 | HUD | hud.gd:3604 · _draw_consequence_overlay | 进入内部报告 / SUBMIT REPORT | 核心 |  |
| TXT-0391 | HUD | hud.gd:3605 · _draw_consequence_overlay | E / Enter 或点击按钮 | 核心 |  |
| TXT-0392 | HUD | hud.gd:361 · _rack_type_cn | 无线电 | 核心 |  |
| TXT-0393 | HUD | hud.gd:3612 · _draw_report_overlay | OCJC / OCUVF 内部事后报告 · 报告单位：OCUVF-ID13 指挥官 | 核心 |  |
| TXT-0394 | HUD | hud.gd:3616 · _draw_report_overlay | 裁决：%s · 内部报告（草案） | 核心 |  |
| TXT-0395 | HUD | hud.gd:3621 · _draw_report_overlay | 经过 / AFTER-ACTION TEXT | 核心 |  |
| TXT-0396 | HUD | hud.gd:3629 · _draw_report_overlay | 证据 / EVIDENCE | 核心 |  |
| TXT-0397 | HUD | hud.gd:363 · _rack_type_cn | 激光通信 | 核心 |  |
| TXT-0398 | HUD | hud.gd:3631 · _draw_report_overlay | · 传感器日志：MS-IR9 / CH-IR2 / ELINT 记录（谁在何时开机、看到什么） | 核心 |  |
| TXT-0399 | HUD | hud.gd:3632 · _draw_report_overlay | · 命令队列：STATION / SHADOW / BURN / 撤销记录（谁下令、几秒生效） | 核心 |  |
| TXT-0400 | HUD | hud.gd:3633 · _draw_report_overlay | · 通信记录：Chronos 港务、AV-4412 传唤者、OCJC 监察（LR / RDO） | 核心 |  |
| TXT-0401 | HUD | hud.gd:3634 · _draw_report_overlay | · Chronos 港务遥测 / 核查组记录：EXPOSE 证据链（三取二） | 核心 |  |
| TXT-0402 | HUD | hud.gd:3640 · _draw_report_overlay | 如实 / TRUTH | 核心 |  |
| TXT-0403 | HUD | hud.gd:3641 · _draw_report_overlay | 无伪证 · 写入 OCJC / OCUVF 内部记录 | 核心 |  |
| TXT-0404 | HUD | hud.gd:3642 · _draw_report_overlay | 伪造 / FALSIFY | 核心 |  |
| TXT-0405 | HUD | hud.gd:3643 · _draw_report_overlay | perjury_count +1 · 第三次触发最坏结局 | 核心 |  |
| TXT-0406 | HUD | hud.gd:3658 · _draw_report_overlay | 处置 / FILING | 核心 |  |
| TXT-0407 | HUD | hud.gd:3665 · _draw_report_overlay | %s（本轮不可用） | 核心 |  |
| TXT-0408 | HUD | hud.gd:3666 · _draw_report_overlay | 只有出现不良后果，才有淡化 / 伪造选项（08 §3.1）。 | 核心 |  |
| TXT-0409 | HUD | hud.gd:3674 · _draw_report_overlay | AUDIT FLAG 01 已置位 | 核心 |  |
| TXT-0410 | HUD | hud.gd:3675 · _draw_report_overlay | 1 如实 · 2 伪造 · 点击卡片提交（提交后不可更改） | 核心 |  |
| TXT-0411 | HUD | hud.gd:3680 · _section_note | 造假会累积；制度最擅长等。 | 核心 |  |
| TXT-0412 | HUD | hud.gd:370 · _level_desc | 无接触 | 核心 |  |
| TXT-0413 | HUD | hud.gd:3700 · _draw_filed_banner | 报告已归档 · 写入 OCJC / OCUVF 内部记录（demo 结束） | 核心 |  |
| TXT-0414 | HUD | hud.gd:3705 · _draw_time | 态势回放 / REPLAY | 核心 |  |
| TXT-0415 | HUD | hud.gd:3706 · _draw_time | 60 秒缓冲 / BUFFER | 核心 |  |
| TXT-0416 | HUD | hud.gd:372 · _level_desc | 仅方位 | 核心 |  |
| TXT-0417 | HUD | hud.gd:3722 · _draw_time | SPACE 暂停 / 1-4 时标 | 核心 |  |
| TXT-0418 | HUD | hud.gd:374 · _level_desc | 定位 / 无舰种 | 核心 |  |
| TXT-0419 | HUD | hud.gd:3749 · _draw_time | 记忆衰减 60s · 事件已标记 | 核心 |  |
| TXT-0420 | HUD | hud.gd:376 · _level_desc | 舰级分类 | 核心 |  |
| TXT-0421 | HUD | hud.gd:378 · _level_desc | 具体识别 | 核心 |  |
| TXT-0422 | HUD | hud.gd:3800 · _draw_sensor_menu | ON/OFF 只读（不可用） | 核心 |  |
| TXT-0423 | HUD | hud.gd:3800 · _draw_sensor_menu | ON/OFF 可操作 | 核心 |  |
| TXT-0424 | HUD | hud.gd:3831 · _draw_sensor_menu | 会暴露 · 已关 | 核心 |  |
| TXT-0425 | HUD | hud.gd:3849 · _draw_sensor_menu | %s · %s · %s · %s · 刷新 %.0fs | 核心 |  |
| TXT-0426 | HUD | hud.gd:3864 · _draw_sensor_menu | %d 个发射器 · 已暴露 | 核心 |  |
| TXT-0427 | HUD | hud.gd:3864 · _draw_sensor_menu | 无主动发射 · 电磁静默 | 核心 |  |
| TXT-0428 | HUD | hud.gd:3866 · _draw_sensor_menu | 暴露 / EXPOSURE | 核心 |  |
| TXT-0429 | HUD | hud.gd:3868 · _draw_sensor_menu | 等级 / LEVEL | 核心 |  |
| TXT-0430 | HUD | hud.gd:3877 · _draw_sensor_menu | 主动模块开机即暴露：ELINT 可截获（05 §S-02） | 核心 |  |
| TXT-0431 | HUD | hud.gd:3879 · _draw_sensor_menu | 被动模块 24 h 开机不付代价（05 §S-01） | 核心 |  |
| TXT-0432 | HUD | hud.gd:3918 · _draw_boot | 地月指挥终端 · 冷启动序列 / COLD START | 核心 |  |
| TXT-0433 | HUD | hud.gd:3934 · _draw_boot | ROE 仅自卫 | 核心 |  |
| TXT-0434 | HUD | hud.gd:3949 · _draw_boot | 系统就绪 / READY | 核心 |  |
| TXT-0435 | HUD | hud.gd:400 · _track_display_id | 虚警 | 兼容/回退 |  |
| TXT-0436 | HUD | hud.gd:402 · _track_display_id | 已交叉确认 | 兼容/回退 |  |
| TXT-0437 | HUD | hud.gd:412 · _track_display_id | 不明目标 | 兼容/回退 |  |
| TXT-0438 | HUD | hud.gd:426 · _link_mode_cn | 激光直接 | 核心 |  |
| TXT-0439 | HUD | hud.gd:426 · _link_mode_cn | 激光直连 | 核心 |  |
| TXT-0440 | HUD | hud.gd:428 · _link_mode_cn | 激光中继 | 核心 |  |
| TXT-0441 | HUD | hud.gd:432 · _link_mode_cn | 红外 | 核心 |  |
| TXT-0442 | HUD | hud.gd:434 · _link_mode_cn | 可见光 | 核心 |  |
| TXT-0443 | HUD | hud.gd:451 · _link_latency | 分钟级 | 核心 |  |
| TXT-0444 | HUD | hud.gd:509 · _track_identity | 传唤 | 兼容/回退 |  |
| TXT-0445 | HUD | hud.gd:52 · top | EVACUATE / 撤人 | 核心 |  |
| TXT-0446 | HUD | hud.gd:52 · top | EXPOSE / 曝光 | 核心 |  |
| TXT-0447 | HUD | hud.gd:52 · top | HOLD / 卡住 | 核心 |  |
| TXT-0448 | HUD | hud.gd:54 · top | 保持卡位，拒绝让出储罐区与航道，将接管程序拖入 UEG 复核。不首先开火。 | 核心 |  |
| TXT-0449 | HUD | hud.gd:55 · top | 撤出 Chronos 人员与可移动储罐，保留记录，允许接管空站。 | 核心 |  |
| TXT-0450 | HUD | hud.gd:56 · top | 向 OCJC 监察与 UEG 轨道事务委员会提交 GHOST TRACK 假旗证据，请求联合调查。 | 核心 |  |
| TXT-0451 | HUD | hud.gd:59 · top | OCU +2 · Meridian +1 · 清算者 −2 | 核心 |  |
| TXT-0452 | HUD | hud.gd:60 · top | OCU +1 · Meridian +2 · 清算者 −1 | 核心 |  |
| TXT-0453 | HUD | hud.gd:61 · top | OCJC +1 · UEG 鸽派 +2 · 清算者 −3 | 核心 |  |
| TXT-0454 | HUD | hud.gd:65 · top | UEG 鸽派 | 核心 |  |
| TXT-0455 | HUD | hud.gd:65 · top | 外环 | 核心 |  |
| TXT-0456 | HUD | hud.gd:65 · top | 清算者 | 核心 |  |
| TXT-0457 | HUD | hud.gd:68 · top | 斛港务 | 核心 |  |
| TXT-0458 | HUD | hud.gd:70 · top | 远环合作社 | 核心 |  |
| TXT-0459 | HUD | hud.gd:702 · _comms_format | 全体 | 核心 |  |
| TXT-0460 | HUD | hud.gd:702 · _comms_format | 全队 | 核心 |  |
| TXT-0461 | HUD | hud.gd:702 · _comms_format | 全队。 | 核心 |  |
| TXT-0462 | HUD | hud.gd:704 · _comms_format | 公开频道 | 核心 |  |
| TXT-0463 | HUD | hud.gd:704 · _comms_format | 法律广播 | 核心 |  |
| TXT-0464 | HUD | hud.gd:706 · _comms_format | 经望楼中继 | 核心 |  |
| TXT-0465 | HUD | hud.gd:71 · top | 清算署 | 核心 |  |
| TXT-0466 | HUD | hud.gd:714 · _comms_format | [%s至%s]-[%s]-[%s] | 核心 |  |
| TXT-0467 | HUD | hud.gd:764 · _notice_parts | 接管声明 · 第七号轨道紧急托管令 | 核心 |  |
| TXT-0468 | HUD | hud.gd:798 · _notice_parts | UEG 海关格林尼治公告：依据《轨道宪章》与第七号轨道紧急托管令，凡失能、受威胁或被敌方渗透的加注站、储罐、船坞与航道，可由联合政府指定部队接管，直至紧急状态结束。Chronos 加注站及储罐区处于紧急状态范围。接管程序由第33轨道特别独立舰队执行。 | 核心 |  |
| TXT-0469 | HUD | hud.gd:810 · _draw_notice_overlay | 2001 · AV-4412 · %s · 法律广播 | 核心 |  |
| TXT-0470 | HUD | hud.gd:810 · _draw_notice_overlay | 接管声明 / ORDER 7 NOTICE | 核心 |  |
| TXT-0471 | HUD | hud.gd:812 · _draw_notice_overlay | Greenwich · L1-01 · UEG 海关 | 核心 |  |
| TXT-0472 | HUD | hud.gd:813 · _draw_notice_overlay | 第七号轨道紧急托管令（Order 7）· 发布第 9 天 · L1 Meridian-05 Chronos | 核心 |  |
| TXT-0473 | HUD | hud.gd:816 · _draw_notice_overlay | %s（第33舰队 · 清算者） | 核心 |  |
| TXT-0474 | HUD | hud.gd:816 · _draw_notice_overlay | 发信 / FROM | 核心 |  |
| TXT-0475 | HUD | hud.gd:817 · _draw_notice_overlay | %s · OCUVF-ID13 指挥官 | 核心 |  |
| TXT-0476 | HUD | hud.gd:817 · _draw_notice_overlay | 收信 / TO | 核心 |  |
| TXT-0477 | HUD | hud.gd:818 · _draw_notice_overlay | %s 无线电 · 公开频道（法律广播） | 核心 |  |
| TXT-0478 | HUD | hud.gd:818 · _draw_notice_overlay | 通信方式 | 核心 |  |
| TXT-0479 | HUD | hud.gd:819 · _draw_notice_overlay | [2001] 未知 → 可疑（光学分类后） | 核心 |  |
| TXT-0480 | HUD | hud.gd:819 · _draw_notice_overlay | 批号 / 身份 | 核心 |  |
| TXT-0481 | HUD | hud.gd:827 · _draw_notice_overlay | 正文 / BODY | 核心 |  |
| TXT-0482 | HUD | hud.gd:832 · _draw_notice_overlay | 程序 / PROCEDURE | 核心 |  |
| TXT-0483 | HUD | hud.gd:833 · _draw_notice_overlay | · 第七号轨道紧急托管令（Order 7）· 第九天；本关为 6 分钟执行窗口。 | 核心 |  |
| TXT-0484 | HUD | hud.gd:834 · _draw_notice_overlay | · 处置在「指挥官决策」面板：HOLD / EVACUATE / EXPOSE；FIRE 是灾难分支，本声明只读。 | 核心 |  |
| TXT-0485 | HUD | hud.gd:835 · _draw_notice_overlay | · 打开本窗口时模拟暂停；关闭后恢复执行窗口倒计时。 | 核心 |  |
| TXT-0486 | HUD | hud.gd:838 · _draw_notice_overlay | 关闭 / CLOSE | 核心 |  |
| TXT-0487 | HUD | hud.gd:839 · _draw_notice_overlay | 点击面板外或 ESC/关闭 返回 | 核心 |  |
| TXT-0488 | HUD | hud.gd:847 · _advisor_text | 长官，三条建议：\n· 接触先看批号与身份：未知不等于敌意；IFF 无应答只能到「未知/可疑」，判敌需要证据与 ROE。\n· 跟踪/变轨走链路：激光直连最快，激光中继 8 s；中继不烧 Δv，机动才烧 Δv。\n· 裁决前可随时撤销待生效命令；执行窗口锁 1×，下令前先看倒计时。 | 核心 |  |
| TXT-0489 | HUD | hud.gd:855 · _manual_sections | 指挥 / COMMAND | 核心 |  |
| TXT-0490 | HUD | hud.gd:855 · _manual_sections | 选择舰 → 下意图（保持站位 / 跟踪伴飞 / 脉冲点火）；命令经链路延迟生效，生效前可撤销。 | 核心 |  |
| TXT-0491 | HUD | hud.gd:856 · _manual_sections | 变轨 / BURN | 核心 |  |
| TXT-0492 | HUD | hud.gd:856 · _manual_sections | 时间轴点火节点只记 draft；授权才执行。Δv 是预算，烧完不可退。 | 核心 |  |
| TXT-0493 | HUD | hud.gd:857 · _manual_sections | L1–L4 是看得多清；身份是政治上是谁，两者分开显示（批号 + 六级身份）。 | 核心 |  |
| TXT-0494 | HUD | hud.gd:857 · _manual_sections | 目标识别 / ID | 核心 |  |
| TXT-0495 | HUD | hud.gd:858 · _manual_sections | 交战 / ROE | 核心 |  |
| TXT-0496 | HUD | hud.gd:858 · _manual_sections | 仅自卫 / WEAPONS HOLD；武器释放授权需二次确认；开火后进入审裁。 | 核心 |  |
| TXT-0497 | HUD | hud.gd:859 · _manual_sections | 开机即暴露：主动雷达/IFF 会被 ELINT 截获；被动模块 24 h 开机不付代价。 | 核心 |  |
| TXT-0498 | HUD | hud.gd:859 · _manual_sections | 辐射控制 / EMCON | 核心 |  |
| TXT-0499 | HUD | hud.gd:860 · _manual_sections | 战损与传感器状态分开记录；损管队列按优先级排。 | 核心 |  |
| TXT-0500 | HUD | hud.gd:860 · _manual_sections | 损管 / DAMAGE CONTROL | 核心 |  |
| TXT-0501 | HUD | hud.gd:866 · _draw_advisor_overlay | 一次性 · 不进通信流（19 §7） | 核心 |  |
| TXT-0502 | HUD | hud.gd:866 · _draw_advisor_overlay | 副官建议 / ADJUTANT | 核心 |  |
| TXT-0503 | HUD | hud.gd:871 · _draw_advisor_overlay | 该建议只在第一次遇到相应机制时出现；之后可在「手册」里复查。 | 核心 |  |
| TXT-0504 | HUD | hud.gd:873 · _draw_advisor_overlay | 知道了 / GOT IT | 核心 |  |
| TXT-0505 | HUD | hud.gd:879 · _draw_manual_overlay | 教学手册 / MANUAL | 核心 |  |
| TXT-0506 | HUD | hud.gd:879 · _draw_manual_overlay | 章节可反复查阅 · 不进通信流 | 核心 |  |
| TXT-0507 | HUD | hud.gd:929 · _draw_manual_overlay | 顺行 000 · ELEV 0 | 核心 |  |
| TXT-0508 | HUD | hud.gd:930 · _draw_manual_overlay | 逆行 180 · ELEV 0 | 核心 |  |
| TXT-0509 | HUD | hud.gd:931 · _draw_manual_overlay | 法向 000 · ELEV +90 | 核心 |  |
| TXT-0510 | PLOT | plot.gd:1000 · _draw_bearing_contact | 仅方位 · 无预测 / BEARING ONLY | 核心 |  |
| TXT-0511 | PLOT | plot.gd:1022 · _draw_phantom | [9002] 无威胁目标 | 核心 |  |
| TXT-0512 | PLOT | plot.gd:1023 · _draw_phantom | 已交叉确认 · 无威胁 | 核心 |  |
| TXT-0513 | PLOT | plot.gd:1024 · _draw_phantom | 残骸/反射 · 无实体 · 无威胁 | 核心 |  |
| TXT-0514 | PLOT | plot.gd:1031 · _draw_phantom | [9002] 不明接触 | 核心 |  |
| TXT-0515 | PLOT | plot.gd:1032 · _draw_phantom | CH-IR2 回波候选 · L1 仅方位 | 核心 |  |
| TXT-0516 | PLOT | plot.gd:1033 · _draw_phantom | 待交叉确认 · 无实体 · 无辐射 | 核心 |  |
| TXT-0517 | PLOT | plot.gd:1193 · _draw_track_label | · 威胁 %s | 核心 |  |
| TXT-0518 | PLOT | plot.gd:1195 · _draw_track_label | · 陈旧 | 兼容/回退 |  |
| TXT-0519 | PLOT | plot.gd:1206 · _draw_track_label | L3 已分类 · %s km%s | 核心 |  |
| TXT-0520 | PLOT | plot.gd:1216 · _draw_track_label | %s%s · L4 · %s · 敌我识别 %s%s | 核心 |  |
| TXT-0521 | PLOT | plot.gd:1220 · _draw_track_label | 已确认 | 核心 |  |
| TXT-0522 | PLOT | plot.gd:1222 · _draw_track_label | 敌我识别：应答机故障 · 不明 ≠ 敌意 | 核心 |  |
| TXT-0523 | PLOT | plot.gd:1224 · _draw_track_label | 敌我识别：无应答 · 不明 ≠ 敌意 | 核心 |  |
| TXT-0524 | PLOT | plot.gd:1230 · _draw_own | 哈马丹 | 核心 |  |
| TXT-0525 | PLOT | plot.gd:1251 · _draw_own | 本舰 · 站位 Meridian-05 / L1 | 核心 |  |
| TXT-0526 | PLOT | plot.gd:1253 · _draw_own | 本舰 · 400 km | 核心 |  |
| TXT-0527 | PLOT | plot.gd:1300 · _draw_sensor | 凝视 %.0f/%.0f 秒 | 核心 |  |
| TXT-0528 | PLOT | plot.gd:1366 · _draw_emit_ring | 辐射 · %s（%s） | 核心 |  |
| TXT-0529 | PLOT | plot.gd:1369 · _draw_emit_ring | 开机即暴露 | 核心 |  |
| TXT-0530 | PLOT | plot.gd:1405 · _draw_sensor_label | 红外 · 被动 · L1 方位线 · 无距离 | 核心 |  |
| TXT-0531 | PLOT | plot.gd:1407 · _draw_sensor_label | 主动 · L2 距离+方位 · 开机即暴露 | 核心 |  |
| TXT-0532 | PLOT | plot.gd:1410 · _draw_sensor_label | 可见光 · 凝视 → L3 分类 · 阴影不可见 | 核心 |  |
| TXT-0533 | PLOT | plot.gd:1412 · _draw_sensor_label | 敌我识别（IFF）→ L4 · 不明 ≠ 敌意 | 核心 |  |
| TXT-0534 | PLOT | plot.gd:1415 · _draw_sensor_label | 被动 · 信号不是接触 | 核心 |  |
| TXT-0535 | PLOT | plot.gd:1418 · _draw_sensor_label | 链路 · 激光直连 > 激光中继 > 红外 > 无线电（鲁棒/全向）> 可见光 | 核心 |  |
| TXT-0536 | PLOT | plot.gd:1451 · _draw_planar_grid | ECLIPTIC / 黄道面 · GRID 50,000 km | 核心 |  |
| TXT-0537 | PLOT | plot.gd:1452 · _draw_planar_grid | 地月空间 / CISLUNAR | 核心 |  |
| TXT-0538 | PLOT | plot.gd:1460 · _draw_planar_grid | 太阳 SUN 312° · 光照 | 核心 |  |
| TXT-0539 | PLOT | plot.gd:1475 · _draw_planar_orbits | 转移轨道 / TRANSFER ORBIT | 核心 |  |
| TXT-0540 | PLOT | plot.gd:1483 · _draw_planar_orbits | 月球轨道 · 384,400 km | 核心 |  |
| TXT-0541 | PLOT | plot.gd:1510 · _draw_planar_bodies | EARTH / 地球 | 核心 |  |
| TXT-0542 | PLOT | plot.gd:1511 · _draw_planar_bodies | MOON / 月球 | 核心 |  |
| TXT-0543 | PLOT | plot.gd:1513 · _draw_planar_bodies | L1 基准 · 地月双体 | 核心 |  |
| TXT-0544 | PLOT | plot.gd:1514 · _draw_planar_bodies | 站点 Meridian-05 Chronos / 无天体弧 | 核心 |  |
| TXT-0545 | PLOT | plot.gd:1523 · _draw_planar_bodies | 站点基准 / STATION FRAME · 地月双体 | 核心 |  |
| TXT-0546 | PLOT | plot.gd:1580 · _draw_planar_contact_title | [%s] %s · %s · L1 仅方位 | 核心 |  |
| TXT-0547 | PLOT | plot.gd:1665 · _draw_planar_phantom | 无威胁目标 · 已交叉确认 | 核心 |  |
| TXT-0548 | PLOT | plot.gd:1682 · _draw_planar_own | 本舰 · 旗舰 · 中心锁定 | 核心 |  |
| TXT-0549 | PLOT | plot.gd:1698 · _draw_planar_sensor | 辐射 · 通信截听 %s km | 核心 |  |
| TXT-0550 | PLOT | plot.gd:1714 · _draw_planar_sensor | 舰队融合 · 1 Hz · L1 方位线在局部图外圈 | 核心 |  |
| TXT-0551 | PLOT | plot.gd:1727 · _draw_planar_inset | 局部 / LOCAL PATCH | 核心 |  |
| TXT-0552 | PLOT | plot.gd:1728 · _draw_planar_inset | 预测 +300 s · ×0.10 px/km | 核心 |  |
| TXT-0553 | PLOT | plot.gd:1744 · _draw_planar_inset | 不明接触 | 核心 |  |
| TXT-0554 | PLOT | plot.gd:1798 · _draw_planar_inset | 历史 -60 s · 预测 +300 s | 核心 |  |
| TXT-0555 | PLOT | plot.gd:1826 · _draw_tasks | 任务 / TASK · EXPOSE 证据 %d/3 | 核心 |  |
| TXT-0556 | PLOT | plot.gd:1827 · _draw_tasks | EXPOSE 需 ≥2 项 · 穿梭机同时只执行一项 | 核心 |  |
| TXT-0557 | PLOT | plot.gd:1834 · _draw_tasks | 完成 | 核心 |  |
| TXT-0558 | PLOT | plot.gd:1834 · _draw_tasks | 进行中 | 核心 |  |
| TXT-0559 | PLOT | plot.gd:1861 · _draw_tasks | 哈马丹 · | 核心 |  |
| TXT-0560 | PLOT | plot.gd:1861 · _draw_tasks | 穿梭机 · | 核心 |  |
| TXT-0561 | PLOT | plot.gd:1864 · _chrome_3d | 战术态势 | 核心 |  |
| TXT-0562 | PLOT | plot.gd:1866 · _chrome_3d | LVLH · ±400 km · 预测 +300 s | 核心 |  |
| TXT-0563 | PLOT | plot.gd:1866 · _chrome_3d | 站点基准 · 局部 ±400 km · 预测 +300 s | 核心 |  |
| TXT-0564 | PLOT | plot.gd:1867 · _chrome_3d | 基准 %s · 三维轨道 · %.0f km | 核心 |  |
| TXT-0565 | PLOT | plot.gd:1868 · _chrome_3d | 执行窗口 %s · 1× 锁 | 核心 |  |
| TXT-0566 | PLOT | plot.gd:1870 · _chrome_3d | 传感器架 %s · %d 模块 · 融合 1 Hz | 核心 |  |
| TXT-0567 | PLOT | plot.gd:1876 · _chrome_3d | 1 保持站位 STATION · 2 跟踪 SHADOW · 3 点火 BURN · 4 撤销 | 核心 |  |
| TXT-0568 | PLOT | plot.gd:1877 · _chrome_3d | 历元 T0+%06.1fs · 预测 %d 点 | 核心 |  |
| TXT-0569 | PLOT | plot.gd:1878 · _chrome_3d | 拖动旋转 · 滚轮缩放 · R 翻转 · D 基准 · Z 横滚锁 · Q/E 横滚 | 核心 |  |
| TXT-0570 | PLOT | plot.gd:1881 · _chrome_planar | 压平态势 | 核心 |  |
| TXT-0571 | PLOT | plot.gd:1887 · _chrome_planar | 传感器架 %s · 融合 1 Hz · 等级由证据时间戳决定 | 核心 |  |
| TXT-0572 | PLOT | plot.gd:1893 · _chrome_planar | ● 友军    ◆ 敌对    □ 未知    ┄ 只方位 | 核心 |  |
| TXT-0573 | PLOT | plot.gd:1928 · _draw_compass | 帧 PLANAR | 核心 |  |
| TXT-0574 | PLOT | plot.gd:1930 · _draw_compass | 帧 LVLH | 核心 |  |
| TXT-0575 | PLOT | plot.gd:1933 · _draw_legend | 图例 / LEGEND · 身份 / IDENTITY | 核心 |  |
| TXT-0576 | PLOT | plot.gd:1934 · _draw_legend | 威胁：待判定 · 无威胁 · 低 · 中 · 高 · 敌对 | 核心 |  |
| TXT-0577 | PLOT | plot.gd:1935 · _draw_legend | 假定友好 | 核心 |  |
| TXT-0578 | PLOT | plot.gd:1935 · _draw_legend | 友方 | 核心 |  |
| TXT-0579 | PLOT | plot.gd:1935 · _draw_legend | 待定 | 核心 |  |
| TXT-0580 | PLOT | plot.gd:1935 · _draw_legend | 未知 | 核心 |  |
| TXT-0581 | PLOT | plot.gd:1936 · _draw_legend | 中立 | 核心 |  |
| TXT-0582 | PLOT | plot.gd:1936 · _draw_legend | 可疑 | 核心 |  |
| TXT-0583 | PLOT | plot.gd:1936 · _draw_legend | 敌方 | 核心 |  |
| TXT-0584 | PLOT | plot.gd:1949 · _draw_legend | 无威胁 | 核心 |  |
| TXT-0585 | PLOT | plot.gd:1952 · _draw_legend | 历史 | 核心 |  |
| TXT-0586 | PLOT | plot.gd:1954 · _draw_legend | 预测 | 核心 |  |
| TXT-0587 | PLOT | plot.gd:1956 · _draw_legend | 1σ 误差 | 核心 |  |
| TXT-0588 | PLOT | plot.gd:1957 · _draw_legend | 航迹：批号 · L1 方位线 · L2 定位+协方差 · L3 分类 · L4 舰名/敌我识别 | 核心 |  |
| TXT-0589 | PLOT | plot.gd:1958 · _draw_legend | T+60/120/300 = 预测刻度 · 辐射 = 开机即暴露 · LINK DEGRADED | 核心 |  |
| TXT-0590 | PLOT | plot.gd:1979 · _draw_optical | 可见光通道 / OPTICAL | 核心 |  |
| TXT-0591 | PLOT | plot.gd:1981 · _draw_optical | [9001] 谷神-2 +2.1 | 核心 |  |
| TXT-0592 | PLOT | plot.gd:429 · _draw_limb | DATUM BELOW · 基准翻面 / FLIPPED | 核心 |  |
| TXT-0593 | PLOT | plot.gd:438 · _draw_station_backing | 地心 · 326,000 km | 核心 |  |
| TXT-0594 | PLOT | plot.gd:439 · _draw_station_backing | 月心 · 58,400 km | 核心 |  |
| TXT-0595 | PLOT | plot.gd:440 · _draw_station_backing | 站点基准 / STATION FRAME | 核心 |  |
| TXT-0596 | PLOT | plot.gd:557 · _draw_burn_node | 命令幽灵 | 核心 |  |
| TXT-0597 | PLOT | plot.gd:576 · _draw_burn_node | 待生效 | 核心 |  |
| TXT-0598 | PLOT | plot.gd:576 · _draw_burn_node | 点火 T+%04.1fs · %s | 核心 |  |
| TXT-0599 | PLOT | plot.gd:576 · _draw_burn_node | 预览 DRAFT | 核心 |  |
| TXT-0600 | PLOT | plot.gd:578 · _draw_burn_node | 草稿节点（未下注） | 核心 |  |
| TXT-0601 | PLOT | plot.gd:580 · _draw_burn_node | 点火 T+%04.1fs · 已执行 | 核心 |  |
| TXT-0602 | PLOT | plot.gd:581 · _draw_burn_node | Δv %.0f m/s · 已扣 · 已执行 | 核心 |  |
| TXT-0603 | PLOT | plot.gd:615 · _draw_shadow_commands | 跟踪（SHADOW）%s · 待生效 | 核心 |  |
| TXT-0604 | PLOT | plot.gd:616 · _draw_shadow_commands | 望楼中继 +8 s · %s | 核心 |  |
| TXT-0605 | PLOT | plot.gd:634 · _draw_shadow_commands | 跟踪（SHADOW）· %s | 核心 |  |
| TXT-0606 | PLOT | plot.gd:635 · _draw_shadow_commands | 跟踪生效 / 望楼号中继 | 核心 |  |
| TXT-0607 | PLOT | plot.gd:645 · _draw_station_commands | 保持站位（STATION）· 待生效 %.1fs | 核心 |  |
| TXT-0608 | PLOT | plot.gd:647 · _draw_station_commands | 保持站位（STATION） | 核心 |  |
| TXT-0609 | PLOT | plot.gd:682 · _draw_own_plan | 计划 +300 s | 核心 |  |
| TXT-0610 | PLOT | plot.gd:714 · _draw_own_plan | DRAFT 预览（点火在 +300s 视野外） | 核心 |  |
| TXT-0611 | PLOT | plot.gd:722 · _draw_own_plan | SHADOW %s · DRAFT 预览 | 核心 |  |
| TXT-0612 | PLOT | plot.gd:741 · _draw_command_queue | 命令队列 / COMMAND QUEUE | 核心 |  |
| TXT-0613 | PLOT | plot.gd:754 · _draw_command_queue | 传达 %.1fs | 核心 |  |
| TXT-0614 | PLOT | plot.gd:757 · _draw_command_queue | 生效 %.1fs | 核心 |  |
| TXT-0615 | PLOT | plot.gd:760 · _draw_command_queue | 确认 %.1fs | 核心 |  |
| TXT-0616 | PLOT | plot.gd:763 · _draw_command_queue | 已完成 | 核心 |  |
| TXT-0617 | PLOT | plot.gd:766 · _draw_command_queue | 已撤销 | 核心 |  |
| TXT-0618 | PLOT | plot.gd:769 · _draw_command_queue | 已拒绝 | 核心 |  |
| TXT-0619 | PLOT | plot.gd:772 · _draw_command_queue | 跟踪（SHADOW） | 核心 |  |
| TXT-0620 | PLOT | plot.gd:774 · _draw_command_queue | 点火（BURN）T+%04.1f Δv%.0f | 核心 |  |
| TXT-0621 | PLOT | plot.gd:791 · _draw_command_queue | 草案 | 核心 |  |
| TXT-0622 | PLOT | plot.gd:793 · _draw_command_queue | 预览 | 核心 |  |
| TXT-0623 | PLOT | plot.gd:934 · _iff_text | 友军 | 核心 |  |
| TXT-0624 | PLOT | plot.gd:936 · _iff_text | 应答机故障 | 核心 |  |
| TXT-0625 | PLOT | plot.gd:938 · _iff_text | 应答码错误 | 核心 |  |
| TXT-0626 | PLOT | plot.gd:940 · _iff_text | 无应答 | 核心 |  |
| TXT-0627 | PLOT | plot.gd:942 · _iff_text | 未询问 | 核心 |  |
| TXT-0628 | PLOT | plot.gd:998 · _draw_bearing_contact | 距离不明 | 核心 |  |
| TXT-0629 | PLOT | plot.gd:999 · _draw_bearing_contact | %s · L1 · 仅方位 · %s | 核心 |  |
| TXT-0630 | STATE | state.gd:1001 · _update_emissions | AV-4412 传唤者 ELINT 截获：%s 点名我方雷达 | 核心 |  |
| TXT-0631 | STATE | state.gd:1003 · _update_emissions | AV-4412 传唤者 ELINT 已点名：我方雷达开机即暴露（07 §3） | 核心 |  |
| TXT-0632 | STATE | state.gd:1014 · _sensor_note | 融合 %d Hz · L4 %d / L3 %d / L2 %d / L1 %d · %s | 核心 |  |
| TXT-0633 | STATE | state.gd:1016 · _sensor_note | 已点名 | 核心 |  |
| TXT-0634 | STATE | state.gd:1016 · _sensor_note | 暴露 | 核心 |  |
| TXT-0635 | STATE | state.gd:1016 · _sensor_note | 电磁管制 | 核心 |  |
| TXT-0636 | STATE | state.gd:1016 · _sensor_note | 辐射 | 核心 |  |
| TXT-0637 | STATE | state.gd:1038 · set_sensor | 关机 | 核心 |  |
| TXT-0638 | STATE | state.gd:1038 · set_sensor | 开机 | 核心 |  |
| TXT-0639 | STATE | state.gd:1054 · set_emcon | 开启 · 发射类全关 | 核心 |  |
| TXT-0640 | STATE | state.gd:1054 · set_emcon | 解除 | 核心 |  |
| TXT-0641 | STATE | state.gd:1118 · _role_text | 民用 · 应答机故障 | 核心 |  |
| TXT-0642 | STATE | state.gd:1165 · _load_story | 指挥官，执行窗口剩余 {mm:ss}。请裁决。 | 核心 |  |
| TXT-0643 | STATE | state.gd:1166 · _load_story | 武器释放授权已下达；交火导致 Chronos 储罐区二次火灾，平民伤亡 12 人。 | 核心 |  |
| TXT-0644 | STATE | state.gd:1208 · _update_phase_gate | 副官建议：Chronos 取证/撤离（可派穿梭机） | 核心 |  |
| TXT-0645 | STATE | state.gd:1224 · _open_decision | 决断窗口开启 · 三选一（或武器释放） | 核心 |  |
| TXT-0646 | STATE | state.gd:1224 · _open_decision | 裁决 | 核心 |  |
| TXT-0647 | STATE | state.gd:1233 · ending_label | 卡住 / HOLD | 核心 |  |
| TXT-0648 | STATE | state.gd:1235 · ending_label | 撤人 / EVACUATE | 核心 |  |
| TXT-0649 | STATE | state.gd:1237 · ending_label | 曝光 / EXPOSE | 核心 |  |
| TXT-0650 | STATE | state.gd:1239 · ending_label | 开火 / FIRE（灾难） | 核心 |  |
| TXT-0651 | STATE | state.gd:1252 · phase_label | 报告 | 核心 |  |
| TXT-0652 | STATE | state.gd:1254 · phase_label | 归档 | 核心 |  |
| TXT-0653 | STATE | state.gd:1265 · _rep_label | UEG 鸽派 | 核心 |  |
| TXT-0654 | STATE | state.gd:1267 · _rep_label | 外环 | 核心 |  |
| TXT-0655 | STATE | state.gd:1269 · _rep_label | 清算者 | 核心 |  |
| TXT-0656 | STATE | state.gd:1280 · _rep_text | 无变化 | 核心 |  |
| TXT-0657 | STATE | state.gd:1306 · choose_ending | EXPOSE 不可用：证据不足（%d/3，需至少 2 项） | 核心 |  |
| TXT-0658 | STATE | state.gd:1322 · choose_ending | 远地点号 | 核心 |  |
| TXT-0659 | STATE | state.gd:1325 · choose_ending | 裁决：%s · 声望 %s | 核心 |  |
| TXT-0660 | STATE | state.gd:134 · top | OCUVF-ID13 指挥官 | 核心 |  |
| TXT-0661 | STATE | state.gd:135 · top | L1 Meridian-05 Chronos · 第七号轨道紧急托管令（第九天） | 核心 |  |
| TXT-0662 | STATE | state.gd:1355 · authorize_fire | \nID13 已提前撤出 Chronos 值勤人员与家属；平民伤亡显著减少。 | 核心 |  |
| TXT-0663 | STATE | state.gd:1358 · authorize_fire | 全队 | 核心 |  |
| TXT-0664 | STATE | state.gd:136 · top | 传感器日志、命令队列、通信记录、港务与核查组黑匣子。 | 核心 |  |
| TXT-0665 | STATE | state.gd:1360 · authorize_fire | 武器释放授权 → 2001 · 灾难分支 | 核心 |  |
| TXT-0666 | STATE | state.gd:1361 · authorize_fire | 时间冻结 · 记录封存 | 核心 |  |
| TXT-0667 | STATE | state.gd:1375 · _build_report_options | 完整记录裁决与经过，进入 OCJC/OCUVF 内部档案 | 核心 |  |
| TXT-0668 | STATE | state.gd:1375 · _build_report_options | 据实报告 | 核心 |  |
| TXT-0669 | STATE | state.gd:1377 · _build_report_options | 只在不希望被追责时可选 · perjury+1 | 核心 |  |
| TXT-0670 | STATE | state.gd:1377 · _build_report_options | 淡化 / 伪造 | 核心 |  |
| TXT-0671 | STATE | state.gd:1417 · submit_report | · 例行审计 | 核心 |  |
| TXT-0672 | STATE | state.gd:1417 · submit_report | 伪造 · REPORT FILED — AUDIT FLAG %02d | 核心 |  |
| TXT-0673 | STATE | state.gd:1417 · submit_report | 报告提交：%s%s | 核心 |  |
| TXT-0674 | STATE | state.gd:1417 · submit_report | 据实 | 核心 |  |
| TXT-0675 | STATE | state.gd:1429 · _compose_report | 未发现异常。 | 核心 |  |
| TXT-0676 | STATE | state.gd:1430 · _compose_report | 建议按程序归档。 | 核心 |  |
| TXT-0677 | STATE | state.gd:1433 · _compose_report | OCJC / OCUVF 内部事后报告 / INTERNAL AFTER-ACTION | 核心 |  |
| TXT-0678 | STATE | state.gd:1434 · _compose_report | 报告单位：%s | 核心 |  |
| TXT-0679 | STATE | state.gd:1435 · _compose_report | 事件：%s | 核心 |  |
| TXT-0680 | STATE | state.gd:1436 · _compose_report | 裁决：%s | 核心 |  |
| TXT-0681 | STATE | state.gd:1437 · _compose_report | 经过：%s | 核心 |  |
| TXT-0682 | STATE | state.gd:1438 · _compose_report | 证据：%s | 核心 |  |
| TXT-0683 | STATE | state.gd:1439 · _compose_report | 声望：%s | 核心 |  |
| TXT-0684 | STATE | state.gd:1440 · _compose_report | 建议：%s | 核心 |  |
| TXT-0685 | STATE | state.gd:1443 · _compose_report | 备注：武器释放已执行；ID13 被定性为未登记武装，审计启动。 | 核心 |  |
| TXT-0686 | STATE | state.gd:1445 · _compose_report | 备注：内部版本与黑匣子记录不一致（perjury=%d）。 | 核心 |  |
| TXT-0687 | STATE | state.gd:1492 · _pump_feeds | [%s至%s]-[%s]-[%s] | 核心 |  |
| TXT-0688 | STATE | state.gd:1495 · _pump_feeds | 第七号令接管声明 · AV-4412 传唤者 | 核心 |  |
| TXT-0689 | STATE | state.gd:1512 · restart_demo | RESTART · 演示重置到 T+0 开局 | 核心 |  |
| TXT-0690 | STATE | state.gd:1637 · identity_label | 待定 | 核心 |  |
| TXT-0691 | STATE | state.gd:1639 · identity_label | 未知 | 核心 |  |
| TXT-0692 | STATE | state.gd:1641 · identity_label | 假定友好 | 核心 |  |
| TXT-0693 | STATE | state.gd:1643 · identity_label | 友方 | 核心 |  |
| TXT-0694 | STATE | state.gd:1645 · identity_label | 中立 | 核心 |  |
| TXT-0695 | STATE | state.gd:1647 · identity_label | 可疑 | 核心 |  |
| TXT-0696 | STATE | state.gd:1649 · identity_label | 敌方 | 核心 |  |
| TXT-0697 | STATE | state.gd:1693 · _update_identity | 身份更新：[2001] 未知 → 可疑（光学分类完成） | 核心 |  |
| TXT-0698 | STATE | state.gd:1700 · _update_identity | 身份更新：[9001] 待定 → 中立（光学/IFF 确认） | 核心 |  |
| TXT-0699 | STATE | state.gd:1721 · threat_text | 敌对 | 核心 |  |
| TXT-0700 | STATE | state.gd:1754 · _update_threat | 威胁更新：[%s] %s → %s | 核心 |  |
| TXT-0701 | STATE | state.gd:1771 · evidence_label | 港务遥测 | 核心 |  |
| TXT-0702 | STATE | state.gd:1773 · evidence_label | 核查组黑匣子 | 核心 |  |
| TXT-0703 | STATE | state.gd:1775 · evidence_label | 异常特征码 | 核心 |  |
| TXT-0704 | STATE | state.gd:1777 · evidence_label | 撤出人员 | 核心 |  |
| TXT-0705 | STATE | state.gd:1829 · start_evidence_task | 当前阶段无法派取证任务 | 核心 |  |
| TXT-0706 | STATE | state.gd:1836 · start_evidence_task | 证据已取得：%s | 核心 |  |
| TXT-0707 | STATE | state.gd:1842 · start_evidence_task | 穿梭机占用：同一时间只能执行一项穿梭机任务 | 核心 |  |
| TXT-0708 | STATE | state.gd:1845 · start_evidence_task | 开始取证：%s | 核心 |  |
| TXT-0709 | STATE | state.gd:1846 · start_evidence_task | Chronos 港务 | 核心 |  |
| TXT-0710 | STATE | state.gd:1846 · start_evidence_task | ID13 穿梭机 | 核心 |  |
| TXT-0711 | STATE | state.gd:1851 · start_evacuation | 当前阶段无法派撤人任务 | 核心 |  |
| TXT-0712 | STATE | state.gd:1854 · start_evacuation | Chronos 人员已撤离 | 核心 |  |
| TXT-0713 | STATE | state.gd:1863 · start_evacuation | 开始撤离 Chronos 人员 | 核心 |  |
| TXT-0714 | STATE | state.gd:1887 · _advance_tasks | 任务完成：%s | 核心 |  |
| TXT-0715 | STATE | state.gd:1905 · ack_adjutant | 副官申请：暂不处理 | 核心 |  |
| TXT-0716 | STATE | state.gd:1961 · prelude_choose_route | 前置航行：%s —— %s | 核心 |  |
| TXT-0717 | STATE | state.gd:1965 · prelude_choose_route | 前置航行：目的地 = %s | 核心 |  |
| TXT-0718 | STATE | state.gd:1982 · prelude_choose_window | 前置航行：变轨窗口 = %s；预计 Δv %.0f m/s | 核心 |  |
| TXT-0719 | STATE | state.gd:1998 · prelude_execute | 前置航行：目的地或窗口未确认 | 核心 |  |
| TXT-0720 | STATE | state.gd:2012 · prelude_execute | 点火执行；ID13 进入转移轨道。 | 核心 |  |
| TXT-0721 | STATE | state.gd:2048 · _build_log | 电磁管制 · 雷达关机 | 核心 |  |
| TXT-0722 | STATE | state.gd:2049 · _build_log | ROE 拒绝 | 核心 |  |
| TXT-0723 | STATE | state.gd:2049 · _build_log | 武器释放授权请求 → AV-4412 传唤者（2001） | 核心 |  |
| TXT-0724 | STATE | state.gd:2050 · _build_log | 传感器：红外 / 光学 | 核心 |  |
| TXT-0725 | STATE | state.gd:2051 · _build_log | 接收 第七号令接管声明 · AV-4412 传唤者（2001） | 核心 |  |
| TXT-0726 | STATE | state.gd:2061 · _build_unit | 传感器 | 核心 |  |
| TXT-0727 | STATE | state.gd:2061 · _build_unit | 反应堆 | 核心 |  |
| TXT-0728 | STATE | state.gd:2061 · _build_unit | 推进 | 核心 |  |
| TXT-0729 | STATE | state.gd:2061 · _build_unit | 火控 | 核心 |  |
| TXT-0730 | STATE | state.gd:2061 · _build_unit | 通信 | 核心 |  |
| TXT-0731 | STATE | state.gd:2062 · _build_unit | 1 · 被动 | 核心 |  |
| TXT-0732 | STATE | state.gd:2062 · _build_unit | CH-IR2 红外 | 核心 |  |
| TXT-0733 | STATE | state.gd:2062 · _build_unit | CH-R0 无线电 | 核心 |  |
| TXT-0734 | STATE | state.gd:2062 · _build_unit | 武器释放 | 核心 |  |
| TXT-0735 | STATE | state.gd:2063 · _build_unit | · CH-IR2 校准中 | 核心 |  |
| TXT-0736 | STATE | state.gd:2063 · _build_unit | 红外虚警偏高 | 核心 |  |
| TXT-0737 | STATE | state.gd:264 · _hud_sensor | 刷新 %.0f s | 核心 |  |
| TXT-0738 | STATE | state.gd:266 · _hud_sensor | 时延 %.1f s | 核心 |  |
| TXT-0739 | STATE | state.gd:268 · _hud_sensor | · 辐射 | 核心 |  |
| TXT-0740 | STATE | state.gd:283 · _sync_sensor_view | 哈马丹 | 核心 |  |
| TXT-0741 | STATE | state.gd:322 · _build_tracks | 船坞舰 | 核心 |  |
| TXT-0742 | STATE | state.gd:322 · _build_tracks | 远地点级 | 核心 |  |
| TXT-0743 | STATE | state.gd:323 · _build_tracks | 远地点 | 核心 |  |
| TXT-0744 | STATE | state.gd:324 · _build_tracks | 哨舰 | 核心 |  |
| TXT-0745 | STATE | state.gd:324 · _build_tracks | 托盘-5 改 | 核心 |  |
| TXT-0746 | STATE | state.gd:326 · _build_tracks | 炮舰 | 核心 |  |
| TXT-0747 | STATE | state.gd:326 · _build_tracks | 赤铁-6 改 | 核心 |  |
| TXT-0748 | STATE | state.gd:327 · _build_tracks | 渡口号 | 核心 |  |
| TXT-0749 | STATE | state.gd:328 · _build_tracks | 中继舰 | 核心 |  |
| TXT-0750 | STATE | state.gd:328 · _build_tracks | 安海-1 | 核心 |  |
| TXT-0751 | STATE | state.gd:329 · _build_tracks | 望楼号 | 核心 |  |
| TXT-0752 | STATE | state.gd:330 · _build_tracks | 月港-4 | 核心 |  |
| TXT-0753 | STATE | state.gd:330 · _build_tracks | 油船 | 核心 |  |
| TXT-0754 | STATE | state.gd:331 · _build_tracks | 深井号 | 核心 |  |
| TXT-0755 | STATE | state.gd:332 · _build_tracks | 传唤级 | 核心 |  |
| TXT-0756 | STATE | state.gd:332 · _build_tracks | 通报舰 | 核心 |  |
| TXT-0757 | STATE | state.gd:333 · _build_tracks | AV-4412 传唤者 | 核心 |  |
| TXT-0758 | STATE | state.gd:334 · _build_tracks | 民用工作船 | 核心 |  |
| TXT-0759 | STATE | state.gd:334 · _build_tracks | 谷神改 | 核心 |  |
| TXT-0760 | STATE | state.gd:335 · _build_tracks | 谷神-2 | 核心 |  |
| TXT-0761 | STATE | state.gd:344 · _build_tracks | 点火（BURN）哈马丹 → 节点 B-2 | 核心 |  |
| TXT-0762 | STATE | state.gd:356 · _build_phantom | CH-IR2 回波候选 | 核心 |  |
| TXT-0763 | STATE | state.gd:356 · _build_phantom | 不明接触 | 核心 |  |
| TXT-0764 | STATE | state.gd:356 · _build_phantom | 待交叉确认 | 核心 |  |
| TXT-0765 | STATE | state.gd:356 · _build_phantom | 待判定 | 核心 |  |
| TXT-0766 | STATE | state.gd:365 · _build_phantom | CH-IR2 虚警候选 | 核心 |  |
| TXT-0767 | STATE | state.gd:437 · issue_command | 前置航行未完成：无法下达战斗命令 | 核心 |  |
| TXT-0768 | STATE | state.gd:440 · issue_command | 命令不可用：已进入决断/报告阶段 | 核心 |  |
| TXT-0769 | STATE | state.gd:457 · abort_command | 撤销 %s %s | 核心 |  |
| TXT-0770 | STATE | state.gd:490 · _seed_demo_commands | 点火（BURN）哈马丹 · 节点 B-2 | 核心 |  |
| TXT-0771 | STATE | state.gd:491 · _seed_demo_commands | 中继 8s | 核心 |  |
| TXT-0772 | STATE | state.gd:491 · _seed_demo_commands | 跟踪（SHADOW）哈马丹 → 9001 | 核心 |  |
| TXT-0773 | STATE | state.gd:499 · _push_command_log | %s 哈马丹 | 核心 |  |
| TXT-0774 | STATE | state.gd:501 · _push_command_log | 跟踪（SHADOW）哈马丹 → %s | 核心 |  |
| TXT-0775 | STATE | state.gd:503 · _push_command_log | 点火（BURN）哈马丹 · Δv %.0f | 核心 |  |
| TXT-0776 | STATE | state.gd:541 · _cmd_note | CMD 待%d / 执行%d / 完成%d / 撤销%d · Δv %.0f m/s | 核心 |  |
| TXT-0777 | STATE | state.gd:556 · _apply_command | 点火（BURN）哈马丹 · Δv %.0f m/s | 核心 |  |
| TXT-0778 | STATE | state.gd:563 · _apply_command | 望楼号中继 | 核心 |  |
| TXT-0779 | STATE | state.gd:563 · _apply_command | 跟踪（SHADOW）生效：哈马丹 → %s | 核心 |  |
| TXT-0780 | STATE | state.gd:571 · _apply_command | 保持站位（STATION）· 哈马丹 | 核心 |  |
| TXT-0781 | STATE | state.gd:571 · _apply_command | 小修正 | 核心 |  |
| TXT-0782 | STATE | state.gd:727 · _plan_tick | 远地点号 → 哈马丹：YW-R9 搜索雷达开机（EMIT 暴露） | 核心 |  |
| TXT-0783 | STATE | state.gd:932 · _update_phantom | 无威胁目标 | 核心 |  |
| TXT-0784 | STATE | state.gd:933 · _update_phantom | 已交叉确认 · 无威胁 | 核心 |  |
| TXT-0785 | STATE | state.gd:934 · _update_phantom | 残骸/反射 | 核心 |  |
| TXT-0786 | STATE | state.gd:936 · _update_phantom | 无威胁 | 核心 |  |
| TXT-0787 | STATE | state.gd:938 · _update_phantom | MS-IR9 交叉确认：该方位无回波 | 核心 |  |
| TXT-0788 | STATE | state.gd:939 · _update_phantom | 残骸/反射 · 无实体 · 无威胁 | 核心 |  |
| TXT-0789 | STATE | state.gd:941 · _update_phantom | 交叉确认：9002 无威胁目标 · 残骸/反射 · 方位 302° | 核心 |  |
| TXT-0790 | MAIN | main.gd:178 · _set_scene | 案卷 4471 | 兼容/回退 |  |
| TXT-0791 | MAIN | main.gd:38 · _ready | AD-FLEET // 战术显控台 — V1.5 | 核心 |  |
| TXT-0792 | MAIN | main.gd:385 · _unhandled_input | 谷神-2 | 核心 |  |
| TXT-0793 | MAIN | main.gd:441 · _unhandled_input | 归档 / END — 第一关 · 监督交接（回执已归档） | 核心 |  |
| TXT-0794 | MAIN | main.gd:449 · _unhandled_input | 无变化 | 核心 |  |
| TXT-0795 | MAIN | main.gd:457 · _unhandled_input | 声望 %s · 窗口消耗 %ds · FLAGS %s | 核心 |  |
| TXT-0796 | MAIN | main.gd:466 · _unhandled_input | R 重开演示 · ESC / Q 退出 | 核心 |  |
| TXT-0797 | MAIN | main.gd:467 · _unhandled_input | 报告文本 / flags 已写入 state.end_summary，供后续审裁与剧情读取。 | 核心 |  |

## 三、实体名

| ID | 区域 | 来源 | 当前文本 | 可见性 | 状态 |
| --- | --- | --- | --- | --- | --- |

## 调整方式

- 按 ID 回复：`TXT-0012 改成……`；
- 删除：`TXT-0012 删除`；
- 新增：说明位置和文本；
- 批改后统一更新 scenario/hud/plot/state 并重截图。
