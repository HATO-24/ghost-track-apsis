# JC-A01（#58）第三轮返修报告：三项实际缺口关闭 + 两探针等强度适配

> 最终代码 SHA `c704f85952eb33ec44c1ac21dfef95d2f8b6a032`（分支 `jc/a01-authority-intel`，PR #66）；实现基线 main `3045311657609dfe10a133802b93dde2fc8abb79`（G0=K0=`9d0f3b4…`）
> 证据目录：`docs/next_cards/evidence/a01_r3/`；环境：Godot `4.7.2.stable.official.ed1daf0bf`，Windows

## 一、三项实际缺口（生产代码）

### 3.1 owner 航迹老化/忘却（原 R3 剩余）
- `authority_intel.gd` 新增每 owner 生命周期 `advance(t_now)`：
  - 与 TrackTable **同一合同**（读取 `track_table.stale_after_s` / `forget_after_s`，默认 30/300 s，不新定产品阈值）；
  - `age > stale_after_s` → 该 owner 航迹 `stale=true`；`age > forget_after_s` → 移除；
  - 合法新观测重置 `stale=false`、`age_s=0`（融合刷新语义）。
- `GameSession.tick` 在组件推进后调用 `authority_intel.advance(now_s())`，与全局 TrackTable 同步演进。
- 探针证据：fresh 不 stale → >30 s 标 stale → 合法新观测刷新 → >300 s 忘却（A01 探针 76/0 内含 6 条断言）。

### 3.2 在途共享恢复（原 R4 剩余）
- 根因：Comms 在途队列**未持久化**，`queue_intel_share` 也不入操作日志 → 恢复后 `pending=[]`
  被 `_reconcile_standalone` 误判为「已送达」，提前 2 s 可见。
- 修复：
  - `comms_service.gd` 新增 `export_state()/load_state()`（`v17.comms.state.v1`）：
    在途 `pending`（含 `delivery_id`/`arrive_t` 等）、`t`/`dt_last`/`step_count`、分配器
    `delivery_seq`/`event_seq`、链路运行态（enabled/jam/occluded）、节点运行态（status/enabled/damage）；
    全量校验通过后才提交，失败不改运行态。
  - `GameSession.save_state` 写入 `comms` 段；`load_state` 在 replay **之后**按存档权威恢复，
    避免「队列项消失 = 送达」的错误推断。
- 探针证据：t2 发出（ETA t5）后立即 save/load；恢复后 Comms 队列 ≥1；
  逐 tick 可见集合与连续会话**完全一致**；首次可见发生在真实 ETA 时刻（第 3 个继续 tick = t5）；
  `received_t` 两侧一致（A01 探针 76/0 内含 8 条断言）。

### 3.3 光学标签泄露内部 ID（原 R3 消费者）
- `v1_hud.gd:_optical_entity_line` 原先把 `tr.track_id` 拼成 `TRACK <tid>`（实际显示
  `ENTITY/TRACK TRACK-001 · TRACK harmattan`），泄露内部目标名。
- 修复：人类可见标签只使用安全显示字段；内部 `track_id`/`entity_id` 保留在非显示字段与
  操作路由中，未改写。
- 证据：metadata 探针中 `HUD optical_entity contains no truth` 两条负例转绿
  （此前 342/7 → 现 357/0），且内部引用未被改写。

## 二、两探针等强度适配（旧断言 → 新契约）

### 2.1 `a1_entity_metadata_authority`（342/7 → **357/0**）

| 旧断言 | 新契约断言 |
|---|---|
| `display_source == "track"` | `== "intel_view"`，并追溯 `row.intel_owner_id` == Binder 可信本舰 owner；`row.track_id` 必须能在该 owner 的 `intel_view.tracks` 找到，`range_km`/`observed_t` 与该证据一致 |
| `display_id == track_id` | 显示 ID 为安全匿名标签：非实体名、不命中场景真值 token；内部 `entity_id` 仍按 `_eq(entity_id, eid)` 保留 |
| 全 7 实体都必须有 contact 行 | 内部 metadata 覆盖全 7 实体；玩家 contacts 必须为空或为「该 owner 已获证据的子集」，另加合法观测正例（contacts 非空且匿名） |
| SIGNAL 注册即应有玩家 contact | signal 注册本身**不产生**玩家 contact；若产品合法链开放该行，仍须无真值且匿名 |
| 通用显示安全字段 | 保留「无真值/匿名/内部引用不变」三条原有负例，未放宽 `_contains_truth` |

### 2.2 `a0_world_physics_sync`（94/3 → **100/0**）

| 旧断言 | 新契约断言 |
|---|---|
| `plot_positions.source == "physics"`、行数 ≥7、`harmattan` 坐标 == 当前 physics − apsis | 内部权威：`session.physics_positions` 覆盖全部 7 实体（原位置/速度/同刻精度断言保留在步骤 3/4）；玩家 plot `source == "intel"`，每个 plot 点必须能映射到该 owner 已获证据的航迹（位置、`observed_t` 一致）；无观测允许为空 |
| 玩家 plot 直读当前物理真值 | 合法观测正例：写入 owner 观测后 plot 出现并保持该采样位置；隐藏 physics 移动但不给新观测 → plot 不跟随（先证明真值确已变更由 A01 探针覆盖） |

## 三、运行结果（同一代码版本）

```
复核指定 5 项：5/5 PASS
  integration.jc_authority_intel          76/0
  integration.a1_entity_metadata_authority 357/0
  integration.a0_world_physics_sync        100/0
  integration.a0_integration_authority     65/0
  integration.a0_save_roundtrip_authority  41/0
Phase 0 gate: 6/6 PASS      Phase A gate: 3/3 PASS
Full strict:  88 = 81 PASS / 7 历史 FAIL / 0 TIMEOUT / 0 NOT RUN
BASELINE CHECK: known_fail=7 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
```

- 7 项历史失败保持原状；未登记新 baseline、未移出 matrix、未删/放宽负例；
- 断言数变化说明：A01 63→76（新增老化/在途恢复断言），metadata 342→357（4 条等式改为
  6 条追溯/匿名断言 + SIGNAL 反转 + 保留原负例），world-sync 94→100（3 条旧等式改为
  内部权威 + plot 映射/正负例），均为等强度或更强。

## 四、明确未做 / NOT RUN

- 未新增 AI/EW/逐舰战斗账本；未改 GameSession 状态机、存档 schema 结构（仅新增 comms 段）。
- 本轮未跑 Linux/macOS、真实渲染/人工可读性、真实 RF/光学物理、>1000 tick 成本长测。
- UI-01..04 新卡：按复核 §6，HUD/Binder 运行时修改等待 A1 放行；本轮未做 UI 运行时改动。

## 五、证据文件

`docs/next_cards/evidence/a01_r3/`：targeted-summary、5 项原始日志、两门禁 summary、
full-summary（88 项，new_fail=0）。
