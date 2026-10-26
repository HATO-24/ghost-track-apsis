# JC-A01（#58）：指挥权限与分方情报隔离（A1）

> 执行基线：main `3045311657609dfe10a133802b93dde2fc8abb79`（含冻结 G0=K0=`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`）
> 分支：`jc/a01-authority-intel`；环境：Godot `4.7.2.stable.official.ed1daf0bf`，Windows
> 生产代码改动：`scripts/core/authority_intel.gd`（新）、`scripts/core/game_session.gd`、`scripts/ui/shell_binder.gd`

## 1. 红例（实现前记录，已保留）

| 红例 | 现状（实现前） | 证据 |
|---|---|---|
| R1 显式无效 shooter 回退本舰 | `request_fire` 在 `ss.is_empty()` 时执行 `shooter = _own_ballistics_entity(states)`，无授权门 | `.test-results/jc-r2/JC-A01/red.stdout.txt` |
| R2 玩家 plot 直出物理真值 | `shell_binder.plot_positions()` 直接遍历 `physics_positions("bary_rot")`，隐藏敌方真值随视图外泄 | 同上 + 代码位置 |
| R3 无 owner 隔离读入口 | 无 `intel_view`/owner 分区，三 owner 观测共用单一 TrackTable | 同上 |

> 说明：R1 在无球体运行态时表现为 `no_physics_state`，但**授权门缺失**本身已被探针断言
> （未知 shooter 未返回授权拒绝原因、legacy 无锚点校验）记录为红。

## 2. 实现

### 2.1 授权链（入口 `authorize_fire`，**先于**资源/弹道/成功事件）
`authority_intel.gd` 冻结 `actor → controller → domain → shooter`：
- `shooter_id` 缺省（旧调用）→ 只映射**可信本舰锚点** `own_entity`，回填
  `legacy_context="own_ship"` + `own_entity_instance_id`；锚点未配置 → `legacy_anchor_unknown`；
- 未登记实例 → `unknown_shooter`；域未知 → `domain_unknown`；
- 敌方域 → `shooter_not_authorized`；盟军域 → `direct_command_not_permitted`（未来走协同协议）；
- 本方其他舰但**无独立战斗运行态** → `shooter_runtime_unavailable`（绝不借旗舰）；
- 通过 → 返回 `domain_id`/`controller_id`。

`GameSession.request_fire` 在最前调用该门；拒绝时**立即返回**（不扣弹药、不排弹、不发成功事件），
并写入 `fire_audit()`（含请求/解析 shooter、context、拒绝原因、是否 ok）。

### 2.2 分方情报（owner 隔离）
- `authority_intel` 为每个域建立独立 `intel_owner` 分区；观测只投递给**观察者所属域**的 owner；
- `receive_intel_observation(owner, row)`：只有该 owner 的视图可见；共享必须**经链路到达接收方**后才可见；
  几何保留 `observed_t`，`received_t` 单调，`delay_s` 与二者一致；
- 读入口：`intel_view(owner)`、`plot_positions(owner)`（source=`intel`，**绝不读物理真值**）、
  `selected_tracks(owner)`；未观测 owner 恒为空；
- `shell_binder.plot_positions()` 改为委托 `session.plot_positions(owner)`，不再直出物理真值。

### 2.3 隐藏真值不泄漏
测试钩子 `_apply_hidden_truth_mutation(entity, new_id, pos)` 直接改物理/世界真值且**不通知任何 owner**；
探针断言玩家视图签名前后完全一致（未观测 → 不可见）。

### 2.4 存档/恢复
`save_state()` 增加 `authority_intel` 段（domains/instances/owner 航迹/观测/审计）；
`load_state()` 恢复并经 `import_state` 校验；旧档无本段 → `restore_mode=legacy_own_ship_only`
（只进本舰域，不复制到盟军）；非当前域 owner 数据一律丢弃（不串域）。
探针验证恢复后视图一致、继续 10 tick 仍一致。

## 3. 验收（`integration.jc_authority_intel`，31/0）

正例：自有舰通过授权门；旧调用固定本舰且带 legacy context；三 owner 独立观测；
共享经链路到达后仅接收方可见；恢复后 10 tick 视图一致；审计记录齐全。

负例：未知/敌方/友军 shooter 均拒绝且资源无变化；未实现本方其他舰返回
`shooter_runtime_unavailable`；未观测 owner 为空；共享不泄漏第三方；隐藏真值改名/改坐标
不影响玩家视图与决策输入。

```
integration.jc_authority_intel  PASS 31/0
unit.track_table_probe          PASS 161/0
integration.a0_integration_authority PASS 65/0
integration.a0_save_roundtrip_authority PASS 41/0
total=4 pass=4 fail=0
```

## 4. 明确未做 / 未接入

- 未实现 AI、逐舰战斗账本、真实协同请求协议（盟军直接命令明确拒绝，协议留后续卡）；
- `selected` 字段目前由 owner 航迹上的 `selected` 标记驱动，HUD 列表/筛选尚未全部切到该 facade；
- 观测投递当前覆盖 sensor observation 路径 + facade 直投；完整 comms/EW 链路接入留 A03/A04；
- 未改动 `known_baseline_failures.json`；7 项历史失败保持原状。
