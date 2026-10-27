# JC-A01（#58）第二轮返修进展（R3 剩余/共享回调/恢复/探针）

> 分支 `jc/a01-authority-intel`；本轮实现基线 main `3045311`（G0=K0=`9d0f3b4…`）
> 环境：Godot `4.7.2.stable.official.ed1daf0bf`，Windows

## 本轮关闭项（对照复核 A/B/C/D）

| 复核项 | 处置 |
|---|---|
| A：`selected_track`/详情仍读全局 `track_vm` 泄漏盟军私有航迹 | `selected_track`/`selected_entity` 在有情报 facade 时**只从该 owner 视图**取；未共享目标即使存在于全局 TrackTable 也不可见；`v1_hud._select_preserving` 空 contacts 不再取 index 0（真实越界已修） |
| B：共享到达回调 `String` 构造 SCRIPT ERROR、`last_intel_share_result` 空 | `_deliver_intel_share` 改收 info 字典并安全取时延；真实 Comms 到达后正确融合（探针 PASS，`share_result` 含 delivery/received/path） |
| B：幂等与在途恢复 | 幂等键 `owner|delivery|observation` 去重；在途共享与 `_standalone` 投递登记**随档恢复**，恢复后继续 10 tick 航迹集合与观测条数一致 |
| C：新档显式 `authority_intel:null` 被当缺段旧档 | 改为「字段存在但非对象（含 null）→ 明确失败；只有字段缺失才是旧档迁移」 |
| D：真实发射正例 | 复用正常 ROE TIGHT + 真实 `FIRE` grant + `request_solution` 至 READY + `missile`（8 发）→ 真实成功、8→7、弹体 ≥1、launch 事件 ≥1；9 组非法 context 全部拒绝且零副作用 |
| D：旧来源夹具 | 先推进 tick 再写观测、逐 tick 断言 ok、**源自读成功**后再删新段做迁移验证（不再制造 t 超前坏夹具） |
| D：A01 探针 | 重新注册为 `integration.jc_authority_intel`，**63/0 PASS** |
| D：CI 退出码 | `.github/workflows/tests.yml` full 步骤补 `$code = $LASTEXITCODE`，job 不再吞失败 |
| D：门禁消费适配 | `e2e.orbital_sim` 153/0、`a0_track_truth_authority` 45/0、`a0_entity_metadata_pipeline` 31/0（内部元数据覆盖 7 实体 + 玩家 contacts 为已知子集，保留匿名/不泄漏断言） |

## 当前回归状态

```
Phase 0 gate: 6/6 PASS
Phase A gate: 3/3 PASS
A01 probe:    63/0 PASS
定向相关:     e2e 153/0、track_truth 45/0、metadata 31/0、session 1545/0、contracts 84/0
```

**全量 strict（88 项）当前 `new_fail=2`**，为两处**旧契约探针未适配**（非产品回归）：

1. `integration.a1_entity_metadata_authority`（342/7）：仍断言 `display_source=="track"` 且
   `display_id==track_id（harmattan）`；新 owner 视图为 `intel_view` + 匿名 `TRACK-001`。
   需按复核口径改为「证据派生 source ∈ {track,intel_view}、display id 不得回读实体真值」，并保留
   等强度负例（匿名性/隐藏实体不出现已 PASS）。
2. `integration.a0_world_physics_sync`（94/3）：仍从 `binder.plot_positions()` 读世界物理真值做同步对照；
   新契约下玩家 plot 为 intel-only。需改用**内部真值接口**（`session.physics_positions`）做 world↔physics
   同步断言，并补充「玩家 plot 不是真值直映（source=intel）」的等强度断言。

这两处适配是纯测试契约对齐，不涉及恢复物理真值 fallback；完成后应回到 88 = 81 PASS / 7 历史 FAIL。

## 下一步

1. 完成上述两个旧探针的契约对齐（严格按复核 §6，不删断言、不恢复真值 fallback）；
2. 重跑全量 strict + Phase0/PhaseA，确认 `new_fail=0`、`complete=true`；
3. 归档红/绿证据与同 SHA 报告，更新 PR body（当前仍为旧摘要）。
