# 可见文案台账（正式基线）

- 规范：`docs/60_Astra_UI与文案设计规范_交Sol.md`，SHA256 `B5A8A2AFFD9152C1C12915939CF20E752D0510464DD0B63DD5E4A802344F1497`
- 产品边界：`docs/56_Astra_开发需求_交6Sol.md`（R2）；联合战役 UI 是 Phase B 的必要入口，但友军关系不等于玩家指挥权限，也不等于其情报已共享。命令回执须区分发送、送达/收到、接受、执行、完成/失败。识别/IFF、ROE、火控授权分别表达。
- 取证基线：正式 `main` `3045311657609dfe10a133802b93dde2fc8abb79`，文件 `game_v17/scripts/ui/v1_hud.gd`，本表仅用 `git show 3045311:...` 的绘制路径和格式化函数确定原文/条件。函数名与短稳定键用于重新定位；行号不作交付键。
- 活动 PR66 对照：HEAD `8b4cf990021bafe0f5b2945039c850b5c985cf5a`；该文件相对正式基线只有 `_select_preserving()` 的空 contacts 防越界分支增加（约该函数处），无以下台账文案改动。当前 PR 未通过底层验收；不据此宣称新 UI 或接口可用。
- 当前没有本提交的实机 UI 截图。本列“截图定位”是将来在对应区域截取的定位名，不声称已有新样张。历史图仅参考视觉气质，ident/fleet 图的密度与小字不作为验收依据。
- 决策词：**保留**=语义与位置可留；**改写**=原控件/同一条件换文案；**删除**=实现旁白从正常显示移除；**移位**=信息保留但移到玩家需要时可达处。带条件的候选字样仅供设计，不证明数据/状态接口已实现。

| # / 覆盖 | 基线定位（文件·绘制函数 / 稳定键） | 显示条件（按基线代码） | 区域 | 原文（逐字/模板） | 决定 | 候选文案（条件式） | 必须保留的玩家语义 | 权限 / 玩法关联 | 截图定位 |
|---|---|---|---|---|---|---|---|---|---|
| 1 战术主屏 | `v1_hud.gd::_draw` / `top.mission_clock` | HUD 每次重绘；时间值来自 `now_s`，固定拼入 L1 港内时刻及 live/fallback 标记 | 顶栏 | `MISSION T+%s · L1 港内 %s · %s` | 改写 | `任务时间 T+{elapsed}`；仅当真实世界时钟可用时显示港内时间 | 两个时钟必须是数据源实际值；模式为预览时明确标“演示预览” | 时间窗口与行动可用性 | `S1-top-left-clock` |
| 2 战术主屏 | `_draw` / `top.link_status` | 顶栏总绘制，当前直接写固定链路值 | 顶栏 | `链路 / 时标 / Δv / ROE`、`LINK OK · 無線電 8s` | 标题改写；固定值删除 | 标题 `态势摘要`；链路只按实时链路字段显示 `链路畅通/受阻/未知`及真实延迟 | 不得把硬编码 `LINK OK` 或8秒当成实况 | 通信受阻会影响命令 | `S1-top-right-link` |
| 3 战术主屏 | `_draw` / `top.dv` | `_transfer_ok` 为真显示Δv，否则 `NOT READY` | 顶栏 | `×1 · Δv {值或 NOT READY}` | 改写 | `倍率 ×{rate} · Δv {value} m/s`；数据无效时 `Δv 不可用` | 暂停/倍率、Δv可用性及单位真实 | 行动控制、推进余量 | `S1-top-right-dv` |
| 4 战术主屏 | `_draw` / `top.roe` | binder 有实例且有 `roe_text`，否则 `ROE NOT READY` | 顶栏 | `ROE {roe_text}` | 保留/改写 | `交战规则：{当前档位}`；未加载时 `交战规则不可用` | ROE只是规则，不代表已获火控/开火授权 | 授权语义，关联火控 | `S1-top-right-roe` |
| 5 战术主屏 | `_draw_left` / `left.friendly_header` | 左栏总绘制；计数为 `_contacts.size()` | 左栏 | `友军 / FRIENDLY · %02d`（当前计数） | 改写 | `友军`及可见友军数；若数的是接触则明确写`可见接触`，不可混为舰队总数 | 可见集合计数不是隐藏实体总数；友军不是可指挥标记 | 情报边界/指挥权 | `S1-left-groups` |
| 6 战术主屏 | `_draw_left` / `left.contact_row` | 每条可见 contact；选择态高亮；显示 class 与 identity tag | 左栏展开 | `{contact display} · {class} · {identity tag}`（动态拼接） | 改写 | 安全显示名＋舰级/类别；识别用`未知/评估/确认`及来源/年龄按需展开 | 不泄露真值 ID；未知不补真名；级别不等于开火授权 | IFF与火控授权分离 | `S1-left-contact-row` |
| 7 战术主屏 | `_draw_map` / `map.time_window` | 3D态势绘制后固定显示，当前硬编码 | 中央态势图 | `T+00:00 · TOF 144:00:00 · WINDOW OPEN 18:00 / CLOSE 24:00` | 删除硬编码；数据字段另设 | 仅当任务数据给出这些计时才显示真实值，否则隐藏或 `窗口时间未知` | 不编造开窗/关窗时间、TOF或当前时间 | 任务窗口影响交战 | `S1-map-time-strip` |
| 8 战术主屏 | `_draw_map` / `map.footer_mode` | 3D态势图分支无条件绘制 | 中央态势图 | `SESSION LIVE · CIC VIEW · V1 WIREFRAME · 不写 WORLD` | 删除 | 若为测试/预览明确标识模式；常规实机不留替代口号 | 不把测试视图当实时战场；区分预览与实时 | 模式可信度 | `S1-map-footer` |
| 9 战术主屏 | `_draw_right` / `right.page_tabs` | 右栏常驻；SHIP/TARGET/FACILITY 三标签 | 右栏 | `SHIP / TARGET / FACILITY` | 改写 | `舰 / 目标 / 设施` | 当前查看对象类型 | 不改变选择/权限 | `S1-right-tabs` |
| 10 战术主屏 | `_draw_right` / `right.field_source` | 页面非 facility；基于字段视图 `source` | 右栏 | `{source}` 默认 `NOT READY` | 移位/改写 | 正常模式只显示影响判断的数据来源，如`友军报告`；无数据分别显示`未知/尚未收到/数据不可用` | 不把来源类名或缺失等同于数值0 | 情报来源 | `S1-right-source` |
| 11 目标/识别 | `_draw_right` / `right.sensor_state` | `sensor_state.ready` true显示雷达/EMCON/OBS；否则显示缺服务文案 | 右栏 | `RADAR ON/OFF · EMCON ... · OBS n`；`IFF EVID n · OPTICAL n · CH n`；`SENSOR NOT READY · 无 sensor_service` | 改写 | `雷达 开/关 · 电磁静默 开/关`；证据计数仅展开；不可用时`传感器数据不可用` | IFF evidence是证据数量，不是确认身份；观测计数不等于目标数 | 识别证据边界 | `S2-right-sensor` |
| 12 命令通信 | `_draw_bottom` / `bottom.command_heading` | 底栏总绘制；按 `binder.ready` 判断 | 底栏 | `命令队列 / COMMAND QUEUE · GAME SESSION/FALLBACK DEMO` | 改写 | `命令队列`；若预览，另标`演示预览` | 不混淆真会话与预览 | 命令真实状态 | `S3-bottom-command-heading` |
| 13 命令通信 | `_draw_bottom` / `bottom.no_commands` | commands 空；根据 `session.orders` 是否存在分支 | 底栏 | `NO COMMAND DATA · ORDERS READY/NOT READY` | 改写 | orders可用而队列空：`暂无命令`；服务不可用：`命令数据不可用` | 空队列与服务缺失不是同一状态 | 指挥状态 | `S3-bottom-empty-queue` |
| 14 命令通信 | `_draw_bottom` / `bottom.command_row` | 有命令时最多绘制前三条；动态state/actor/target/action/delay | 底栏 | `{id} {state} · {actor} → {target} · {action} · {delay}` | 改写 | `{命令对象} · {阶段} · {动作}`；英文状态映射成稳定中文枚举 | 发送、送达、接受、执行、完成、失败/拒绝需分别显示；不能将 `TRANSMITTED` 译为已执行 | 友军命令可能是请求而非命令 | `S3-bottom-command-rows` |
| 15 命令通信 | `_draw_bottom` / `bottom.abort_revoke` | 当前绘制分支以 `_selected_cmd >= 0` 控制可用性；不能据此宣称权限已校验 | 底栏动作 | `ABORT` / `REVOKE` | 改写 | `中止命令` / `拒绝命令`；具体是否可操作由接口权限返回 | `_command_action`分别调用`abort_order`和`reject_order`；不指撤销FIRE授权。如改称撤回，须先明确阶段/API含义 | 命令权限 | `S3-bottom-actions` |
| 16 命令通信 | `_draw_bottom` / `bottom.event_log` | 底栏常驻；空则 `NO EVENT DATA · NOT READY`，否则显示最近4项 | 底栏 | `事件日志 / EVENT LOG · SESSION BUS/FALLBACK DEMO`; `NO EVENT DATA · NOT READY` | 改写/移位 | `事件记录`；空为`暂无事件`，服务异常为`事件数据不可用`；详尽事件展开 | 无数据与无事件区别；不将每tick诊断暴露为常驻 | 事件反馈 | `S3-bottom-events` |
| 17 命令通信 | `_draw_comms_overlay` / `comms.empty_messages` | `events.is_empty()` | 叠层：通信左栏 | `NO MESSAGES · NOT READY` | 改写 | 区分`暂无消息`和`通信记录不可用` | 空消息流不代表链路失效 | 通信状态 | `S3-comms-empty` |
| 18 命令通信 | `_draw_comms_overlay` / `comms.link_status` | 每频道先默认 OPEN / 延迟—；若找到匹配link才按 disabled/occluded/jam≥0.7映射状态；无匹配link仍会显示默认 OPEN | 叠层：通信左栏 | `MODE STATUS LATENCY EVENTS`; `OPEN/CLOSED/OCCLUDED/JAMMED` | 改写 | `频道 / 链路状态 / 延迟 / 消息数`；分别`畅通/关闭/遮挡/受干扰` | 找到匹配link时状态按真实字段；无匹配link时必须显示`未知 / 链路信息不可用`，不得把默认OPEN当成畅通；latency单位和来源保留 | 影响送达，不代表命令接受 | `S3-comms-link-list` |
| 19 命令通信 | `_draw_comms_overlay` / `comms.message_row` | 最多 `row_capacity` 条事件；按安全显示格式化器；缺文本时落到text_key/kind/reason | 叠层：通信左栏 | `[{from} 至 {to}]-[{mode}]-[{content}]`；fallback `TEXT KEY 未提供`/`[kind · reason]` | 改写 | `{发起方} → {接收方} · {频道} · {玩家可读内容}`；未知模板显示`消息内容不可用` | 保留发/收端、消息内容及其来源；不在玩家文案显示reason code | 可视权限/已共享情报 | `S3-comms-message-stream` |
| 20 命令通信 | `_draw_comms_overlay` / `comms.auth_summary` | 逐级调用 `combat_authorization(TRACK/SOLUTION/FIRE)` 后输出 | 叠层：通信右栏 | `AUTH TRACK:OK/LOCK SOLUTION:OK/LOCK FIRE:OK/LOCK` | 改写 | 展开区显示`航迹授权 / 解算授权 / 开火授权：已获/未获` | 三种授权独立；锁定要有玩家可理解的受阻原因 | 权限/火控 | `S3-comms-authorization-detail` |
| 21 命令通信 | `_draw_comms_overlay` / `comms.roe_hint` | 通信面板底部固定显示；无 combat时替代为NOT READY | 叠层：通信右栏 | `ROE {档位} · ROE 不授予 FIRE 授权` | 保留并改写 | `交战规则：{档位}`；旁注`规则不等于开火授权`；未获授权时靠近受阻动作显示 | ROE设置交战行为，开火仍需独立授权 | 授权/玩法关键 | `S3-comms-roe-hint` |
| 22 目标/识别 | `_draw_ident_overlay` / `ident.no_evidence` | `enabled` false走不可用分支；否则 `known` false仅表示尚未形成assessment；是否无证据另看`evidence_count`/证据数组 | 识别叠层：评估栏 | `NOT READY · identification_service 未启用`; `NO EVIDENCE`; `尚未形成评估 · 不显示推断身份` | 改写，删除实现句 | `识别数据不可用`；known=false时`尚未形成识别评估，身份未知`；仅`evidence_count==0`时才写`尚无证据` | “不可用”≠“无评估”≠“无证据”；只有证据计数为0才称无证据；未知不可冒充友/敌 | 识别可信度 | `S2-ident-assessment-empty` |
| 23 目标/识别 | `_draw_ident_overlay` / `ident.current_identity` | `known` true才显示identity、confidence和MANUAL/AUTO | 识别叠层：评估栏 | `{IDENTITY}`, `CONFIDENCE %.2f`, `MANUAL/AUTO FUSION` | 改写 | `评估身份：{身份}`、`置信度`、`人工确认/自动融合` | 显示等级/置信度、人工/自动来源及数据时效；不把自动评估称“确认” | 不能替代IFF应答或开火授权 | `S2-ident-known-state` |
| 24 目标/识别 | `_draw_ident_overlay` / `ident.evidence_empty` | evidence数组为空 | 识别叠层：证据栏 | `无证据记录（未询问 / 未广播）` | 改写 | `暂无证据记录`；原因只在数据确知时注明`未询问`或`未收到广播` | 不推断原因；区分没有收到与信息不可用 | 识别证据来源 | `S2-ident-evidence-empty` |
| 25 目标/识别 | `_draw_ident_overlay` / `ident.evidence_rows` | 每条有效证据逐项显示source/identity/confidence/status/mode/age | 识别叠层：证据栏展开 | `SRC IDENTITY CONF STATUS MODE AGE` | 改写/展开 | `来源 / 观测身份 / 置信度 / 状态 / 方式 / 年龄` | 年龄/过期必须可读；`silent/no_reply/spoofed`等需玩家语义映射 | 识别与电战 | `S2-ident-evidence-table` |
| 26 ROE | `_draw_roe_overlay` / `roe.lock_state` | `_roe_locked` 分支决定LOCKED与解锁说明 | ROE叠层 | `LOCKED · 序章未解锁 · 仅显示当前档位` / `UNLOCKED · 点击档位调用真实 session.set_roe` | 改写；删除API叙述 | 锁定时显示真实原因，如`交战规则当前不可更改`；可用时直接呈现可选档位 | 不虚构“序章解锁”外的阻断缘由 | 设置权限 | `S4-roe-lock-state` |
| 27 ROE | `_draw_roe_overlay` / `roe.mode_cards` | 四档常驻；当前档标CURRENT；锁定时其他档标LOCKED | ROE叠层：规则卡片 | DEFEND/HOLD/TIGHT/FREE及逐档解释 | 改写 | `防御 / 保持 / 严格 / 自由`＋按准确授权阶段写清触发条件 | 保留每档具体自动/手动授权规则，避免“自由”被误解为自动开火 | ROE与授权分离 | `S4-roe-cards` |
| 28 ROE | `_draw_roe_overlay` / `roe.fire_authorization_hint` | ROE页总显示 | ROE叠层底部 | `授权提示：ROE 只改交战规则，不授予开火许可；需另行授权。` | 保留/精简 | `交战规则与开火授权分别管理。` | 必须保留不授予许可的语义；受阻时仍显示具体原因 | 授权关键 | `S4-roe-auth-hint` |
| 29 损管 | `_draw_damage_overlay` / `damage.source_subtitle` | 打开损管页时无条件显示；页面称只读最小交互 | 损管叠层 | `SOURCE · V2DamageModel shadow (session 无 damage_vm) · 只读/最小交互` | 删除实现来源；可用性独立表达 | 页标题`损管`；数据真实不可用时在字段区明确`损管数据不可用`；仅显式模拟时`模拟预览` | 不让影子模型被当真；不因删旁白而隐藏数据模式 | 数据源/损害响应 | `S5-damage-title` |
| 30 损管 | `_draw_damage_overlay` / `damage.not_ready` | `_damage==null`或`ready` false | 损管叠层：主体 | `DAMAGE NOT READY · 无模型/内容` | 改写 | 分清`无损管数据`与`损管服务不可用`；相关动作禁用并给明因 | 无数据不等于0损伤/安全 | 损害/修理 | `S5-damage-unavailable` |
| 31 损管 | `_draw_damage_overlay` / `damage.section_rows` | `_damage.ready`; 每个sections项绘制完整度、state及活跃火灾/失压标记 | 损管叠层：损伤分区 | `{id} · {label} · integrity% · {state} · FIRE/DEC` | 改写 | `{分区名} · 完整度 {n}% · {状态}`；火灾/失压为显式告警 | 分区损伤、状态、火情和失压不丢失；未知不默认100% | 生存/损管行动 | `S5-damage-sections` |
| 32 损管 | `_draw_damage_overlay` / `damage.resources` | ready后显示队伍、备件、人员；动态字段 | 损管叠层：详情 | `RESOURCES / 队伍`; `TEAMS ... · SPARES ... · PERSONNEL ...` | 改写 | `损管资源`：队伍/备件/人员，缺字段标不可用 | 资源真实值影响维修能力；缺值不得当作0 | 维修权限/资源 | `S5-damage-resources` |
| 33 舰队编制 | `_draw_fleet_builder_overlay` / `fleet_builder.subtitle` | 打开编制页，无条件显示；13舰/8槽和API按钮枚举固定 | 编制叠层 | `13 舰名册 · 8 槽 command/screen/gun/missile/logistics/relay/tug/shuttle · ASSIGN/UNASSIGN/MOVE/VALIDATE` | 删除硬参数副标题；改写控件 | `舰队编制`；真实选舰数、角色槽、分配和校验由视图数据填写 | 13/8是当前实现快照，不等于批准的首版玩法上限 | 编制规则/Phase B接口 | `S6-builder-title` |
| 34 舰队编制 | `_draw_fleet_builder_overlay` / `fleet_builder.not_ready` | `fd.ready` false | 编制叠层：主体 | `FLEET FORMATION NOT READY`; `session.fleet_formation 未启用/未 ready` | 改写 | `编制数据不可用`；按钮不可操作并给已知原因 | 不把服务缺失伪装成非法编制/空舰队 | 部署能力 | `S6-builder-unavailable` |
| 35 舰队编制 | `_draw_fleet_builder_overlay` / `fleet_builder.roster_rows` | ready；遍历名册至面板容量；显示选中舰高亮 | 编制叠层：名册 | `{ship_id} · {name} · {class_id} · {role} · {slot/status}` | 改写/安全显示 | 显示玩家可识别舰名、舰级、岗位、分配状态；内部ID只在确属玩家呼号时展示 | 选中舰与部署状态准确；未编入舰不得被说成参战 | 单舰实例/部署权限 | `S6-builder-roster` |
| 36 舰队编制 | `_draw_fleet_builder_overlay` / `fleet_builder.slot_rows` | ready；各槽显示使用数/cap与required | 编制叠层：岗位槽 | `{label} / {key} · used/cap · REQ` | 改写 | `岗位 / 已分配数`；容量与必需岗位以经批准规则和接口实际值为准 | 必需岗位缺失的校验含义 | 编制合法性 | `S6-builder-slots` |
| 37 舰队编制 | `_draw_fleet_builder_overlay` / `fleet_builder.validation` | ready；显示VALID/INVALID、COMMAND OK/REQUIRED及errors | 编制叠层：校验 | `VALID/INVALID`, `COMMAND OK/COMMAND REQUIRED`, `no constraint errors`或错误串 | 改写 | `编制有效/无效`；`需要指挥舰`；无错误为`未发现编制问题`；逐项给可理解原因 | VALIDATE只是当前编制检查，不等于已经部署/进入战场 | 部署门槛 | `S6-builder-validation` |
| 38 舰队编制 | `_draw_fleet_builder_overlay` / `fleet_builder.totals` | ready；固定总计字段，有值按模型汇总 | 编制叠层：汇总 | `SHIPS/MASS/Δv/CREW/FUEL/REPAIR/ASSIGNED %d / 13` | 改写 | `舰数/总质量/Δv/乘员/燃料/维修需求/已分配`，单位齐全；计数不硬编码13 | 编制取舍的真实成本和能力差异；未知值不显示0 | 资源预算/组合限制 | `S6-builder-totals` |
| 39 舰队编制 | `_draw_fleet_builder_overlay` / `fleet_builder.actions` | ready页脚固定ASSIGN/UNASSIGN/MOVE/VALIDATE，事件回写 `_fleet_builder_msg` | 编制叠层动作区 | `ASSIGN / 编入 · UNASSIGN / 撤编 · MOVE / 换槽 · VALIDATE / 校验` | 改写 | `编入 / 撤编 / 调整岗位 / 检查编制`；成功后显示真实操作结果，不统一`OK` | 操作对象、失败原因、是否真部署不能混淆 | 编制/指挥权限 | `S6-builder-actions` |
| 40 舰队编制 | `_draw_fleet_overlay` / `fleet_catalog.subtitle` | 打开舰队数据库页无条件；友军/敌军类别数来自 catalog | 舰队数据库叠层 | `友军/敌军舰级档案 · class/role/hull/displacement/Δv · 只读，不伪造 TBD` | 改写，移走实现提醒 | `舰级档案`；TBD字段明确`未知`或`未设定` | 档案缺项不能伪造数据；友军舰级情报可见不代表可指挥 | 敌我关系/情报权限 | `S6-fleet-catalog-title` |

## 需由实现前接口核对的语义点

1. 当前 `hud_bottom_event_text` / `hud_comms_event_text` 的事件阶段映射必须逐一对照服务事件契约，不能只靠通用英文status直译；表中“送达/收到/接受/执行/完成/失败”是最低玩家可辨阶段。
2. `combat_authorization` 返回的 `TRACK/SOLUTION/FIRE` 授权与 `_combat.roe` 是两份值；界面若只拿到布尔锁状态，缺少失败原因时应另立数据视图需求，不由显示层猜原因。
3. `ident_view(row,true)` 当前把证据融合/人工身份评估带入页；需要检查过期或失效证据在呈现前是否正确标注。表不批准任何当前身份判定。
4. `fleet_builder_data()` 是名册/槽位/统计视图；56R2明确现有编制服务本身不等于生成战场实体。`VALID`不可以在未有部署接口的页面上改写成“舰队已出击”。
5. Damage页来自HUD shadow adapter；`ready`只表示该适配视图可绘制，不足以证明Session真损伤模型为权威来源。先在接入任务卡里明确数据模式。

## 来源函数索引

- 主屏：`_draw`, `_draw_left`, `_draw_map`, `_draw_right`, `_draw_bottom`
- 目标、识别：`_draw_ident_overlay`, `hud_target_texts`, `_contact_display`
- 通信、命令：`_draw_comms_overlay`, `hud_comms_event_text`, `hud_comms_link_text`, `hud_bottom_event_text`
- ROE与授权：`_draw_roe_overlay`, `_draw_combat_overlay`, `combat_authorization`
- 损管：`_draw_damage_overlay`
- 舰队/编制：`_draw_fleet_overlay`, `_draw_fleet_builder_overlay`

