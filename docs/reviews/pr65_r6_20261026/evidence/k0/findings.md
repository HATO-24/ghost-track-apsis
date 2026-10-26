# PR #65 R6 — JC-B00 / K0 精确复核
被审 HEAD: 5d7208b82ebae81da874e059c2d88286317c6483
对照上轮: dc3821eda91d25f14e44dd9f57e6f5a985e04a9c
Issue: #57. 日期: 2026-10-26 Asia/Shanghai.

结论：K0 仍需返修后再解锁 A01；本次不要求实现 A01/B1/AI。R6 已实质修复大部分原漏洞，剩余是可以用当前语义校验器直接重现的合同缺口，以及 #57 明确要求的少量冻结项。

## 已关闭
- actor 必须处于指挥域 authorized_actors；原 player actor 填 ally controller/shooter 的反例已明确拒绝。
- selected=false 不得保留在部署清单；缺 request_id 和同键异舰/异迁移拒绝；roster 跨舰队引用拒绝。
- owner/observer 不存在、delay 与 received-observed 不一致均拒绝。
- 连续 mass/fuel 有限、非负、必需；3000.5 kg 燃料通过；INF、native int 超安全范围、缺 fuel 均拒绝。数值组本轮关闭。
- per_owner_track_table 已在文档 §8.2 明确选择；AI 按域只读策略、reads_ground_truth=false、legacy scope 策略已写明。它们无需在本卡提前实现运行态。多个 player 域等可选内容策略不作为阻塞。

## P1 — 合法身份链仍接受未选且未部署的 fire shooter
Source: game_v17/scripts/core/jc_contracts.gd:375-384（顶注释第10行承诺“shooter必须是该域已选实例”）。
最小变体：合法 fixture 的 I-A2 设 selected=false/deployment_state=DRAFT，移除 I-A2 对应部署记录；将原 CMD-1(kind=fire) 的 shooter_id 改为 I-A2。
实际：ok=true/errors=[]。
actor/controller/域绑定已修，但 shooter 只检查已登记与同域；没有检查 selected/部署资格。此处可补合同层拒绝，不需要实现部署/战斗。
Repro: residual_fire_unselected_undeployed_shooter.

## P1 — 观测原始 owner 与接收 owner 未区分，接收方可自我授权敌方观测
Source: jc_contracts.gd:301-319。
最小变体：将第一条原生 radar 观测的 observer_id 从 I-A1 改为敌方 I-OP1；保留 intel_owner_id=player_intel、share_authorized_by=player_intel、path=direct 和合法时间。
实际：ok=true/errors=[]。
修复只检查 observer/owner 在全局存在、authorizer 等于同条自报 owner；未建立 observer 原始归属与跨 owner 共享授权。现有两个合法 observation_shares 都是各自 owner 内部观测，没有“盟军 origin owner → 玩家 receiver owner”的合法延迟共享 fixture。#57 要求分 owner 融合与授权共享，K0 需要固定 source_owner/destination_owner/grant/path 的等价合同，不能仅由接收方声明自己已获授权。
Repro: residual_enemy_observer_self_authorized_as_player_intel.
这里不要求真实通信/AI实现，只要求字段关系和正负fixtures。

## P2 — 部署记录未验证 t，迁移结果与当前实例状态脱节
Source: jc_contracts.gd:254-274；文档 joint_campaign_r2.md:65 声明 t 非有限/负应拒绝。
两个独立最小变体：
1. 只将 deployments[0].t=-5：ok=true/errors=[]。
2. 保持实例当前 DEPLOYED，只将部署记录改为 from_state=DRAFT/to_state=VALIDATED：ok=true/errors=[]。
函数从未读取 t，也未使 to_state 与该条部署结果/实例当前状态一致。记录列表又禁止同实例多条，因此不能用“保留全部历史迁移”解释这条不一致。
Repro: residual_deployment_negative_t / residual_deployment_transition_disagrees_current_state.
缺键/冲突键已关闭，不重提。重复 manifest 记录拒绝可作为明确策略；后续运行态请求服务仍须按幂等合同返回相同结果。

## 其他明确但较小的残留
- jc_contracts.gd:352-356 仅 cid 非空时检查重复，没有空值分支。删除 command_id 仍 ok=true；文档表第86行要求空/重复拒绝。Repro: residual_missing_command_id。
- legacy 的 own_entity_instance_id 由命令自己给出。I-A2 同时填为 shooter 与 own 后通过。若这是未来可信上下文注入值，应在 K0 写清唯一来源与旧调用映射；不因新场景可选择不同本舰的提案本身阻塞。

## #57 冻结接口复核
新增策略声明成立，但下列交付仍需要文档/schema/fixture补全，不是要求运行态实现：
- command 的 actor/controller/fleet/shooter 入口/返回/拒绝契约以及 trusted legacy-own 来源；
- event_id/seq 的字段类型、范围、分配/续写规则，通信请求/回执/执行记录的关联 ID、状态与版本；
- 新存档段版本和缺新段 legacy fixture 的解释/拒绝规则。
当前 event_lifecycle 只有六个字符串顺序（jc_contracts.gd:516-529；文档 §8.5），不是带 ID/seq/时间/引用的事件轨迹；不能据此声称已冻结/验证同tick与继续事件轨迹。旧档只有 legacy_scope 两个策略字段，未提供旧seed/缺新段 fixture。
K0 doc仍需在G0正式冻结后重述实际40位SHA；这项由总复核配合，不以未实现A01等为由阻塞。

## 精确运行
git rev-parse HEAD: 5d7208b82ebae81da874e059c2d88286317c6483
Godot: 4.7.2.stable.official.ed1daf0bf
本独立复核只运行临时语义变异脚本；未运行full/长测。
```powershell
$env:JC_K0_AUDIT_OUTPUT='C:/Users/ASUS/.codex/worktrees/jc-r6-validation/GHOST TRACK_APSIS/.test-results/r6-k0-audit/mutations.json'
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:/Users/ASUS/.codex/worktrees/jc-r6-validation/GHOST TRACK_APSIS/game_v17' --script 'C:/Users/ASUS/.codex/worktrees/jc-r6-validation/GHOST TRACK_APSIS/.test-results/r6-k0-audit/mutations.gd'
```
Exit=0：诊断正常结束，不代表所有拒绝语义正确。
17项：合法原fixture + 10个原漏洞正负对照符合预期；6个残留变体仍被接受。其中legacy项按可信来源待说明处理，不与确定阻塞混为一谈。
Artifacts: mutations.gd, mutations.log, mutations.json.
未改生产/既有测试文件、未写GitHub、未合并。

