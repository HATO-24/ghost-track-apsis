# R7 返修报告：#56 / #57 / #63（G0 候选）

> 分支 `jc/g0-integration`；本轮提交
> `a51e19f`（#56 A/B/C）、`d8cdf26`（#57）、`8bf9b2a`（#63）、`106a14f`（#56-D 证据归档）
> 测量代码 SHA：**`a51e19f2e2609b69f4e90a87da7855538de205c4`**
> 起点 C55 = `30b8d33dae9787aadf89bb206757cafb2cad7bd3`；main 仍 `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`
> Godot `4.7.2.stable.official.ed1daf0bf`，Windows

---

## 一、#56 JC-A00：四项残项

### A. TWS 通道按 FSM 完整校验（不再只修空对象反例）
`tws.validate_state` 现在按 **FSM 实际消费的完整字段集**校验（`CHANNEL_FIELD_SPEC`，30 个字段：
类型 `num/int/bool/dict/array/str`），并按状态追加必需字段（`CHANNEL_STATE_EXTRA`：
STARE 需 `stare_s/stare_required_s/stare_progress`，FIRE_CONTROL 需 `fire_control`），
另校验 `quality∈[0,1]`、`stare_progress∈[0,1]`、`stare_required_s≥0`、数值安全范围。

审查方 STARE 反例（`{"target_id":"broken","state":"STARE","quality":1,"last_update_t":0}`）
现在**导入即拒绝**，不再到 step 才 SCRIPT ERROR。探针新增 3 个反例（STARE 缺字段、
通道缺 scan_index/last_miss_t、quality 非数字）→ 全部拒绝。

### B. 比较器两处缺口
1. `bus._id_seq` **值**比较：`220→320` 现在会被发现（旧 quick 返回 `violations=[]`）；
2. 逐 tick 输出真正参与比较：`_behavior_violations` 每 tick 记录新增 EventBus 事件 /
   观测 / 通信事件的**内容签名**并对比（`bus.events.new`、`sensor.observations.new`、
   `comms.events.new`），移除了不存在的 `last_event()` 查询。
   → 通信正文篡改现在**即刻状态 + 逐 tick + 最终状态**三处都能发现。

故障注入三态（`A07_FAULT_KIND=seen_ids|eta|comms_text`）均 EXIT=1；对照 27/0 EXIT=0。

### C. 旧档 v1 迁移/部分恢复策略
`import_backend_state` 区分两条路径：
- **新格式**（含 `tws`/`authority_*`）→ 必须完整，缺任何子状态 = 拒绝（损坏）；
- **旧 v1 格式**（两者都缺，如 C55 存档）→ **合法旧数据**，迁移可重建部分：
  optical 通道 + 由通道 boresight 重建 `mount_pointing`；TWS/扫描相位不可重建 →
  保持 boot 默认并**如实标 partial**，返回 `restore_mode=partial` + `partial_reasons`
  （`tws_runtime_reset_unrecoverable`、`pointing_target_not_persisted:<kind>` 等）。
探针断言：旧档可导入且 `restore_mode=partial`、列出原因；新格式缺 TWS 仍拒绝。

### D. 本轮长测原始证据已归档
`docs/benchmarks/jc_r2/r7_a51e19f2_20261026/`：`summary.json`、`measurements.json`
（`environment.git_head = a51e19f2…`）、完整 `a0_save_cost.log`、`stderr.log`、`README.md`。
旧 `a00_g0_measurements.json`（`eaf953286…`）**保留**为历史对照，不再当作本轮证明。

### #56 验收
```
四规模基准：PASS 90/0，860.5 s（12 样本全验，代码 a51e19f2）
50t   433,956 B / save  90 ms / 恢复  1,295 ms / 读 2 ms
200t 1,151,356 B / save 269 ms / 恢复  7,077 ms / 读 3 ms
800t 1,935,007 B / save 324 ms / 恢复 41,676 ms / 读 5 ms
1000t 2,172,752 B / save 383 ms / 恢复 60,009 ms / 读 5 ms
```
正确性全绿；**性能预算仍不达标**（#49：≤1,500,000 B / ≤250 ms / ≤5,000 ms / ≤50 ms），交 #49。

---

## 二、#57 JC-B00：四项残项

| 项 | 实现 | 负例 |
|---|---|---|
| fire 发射者资格 | shooter 必须 `selected=true` **且** `deployment_state=DEPLOYED`（已登记≠可受令） | `invalid_shooter_not_participating.json` |
| 共享来源与接收授权 | **原始 owner 固定** = observer 所属域的 intel_owner；`share_authorized_by` 必须等于原始 owner；`received_by_intel_owner_id` 必须存在且等于 `intel_owner_id` | `invalid_obs_enemy_selftrust.json`（敌方自报我方情报自授权）、`invalid_obs_receiver.json` |
| 部署记录一致性 | `t` 必须有限非负；记录 `to_state` 必须等于实例当前状态（历史链须写 history） | `invalid_deploy_time.json`、`invalid_deploy_state_mismatch.json` |
| 标识与冻结接口 | `command_id` 必填；新增 `event_id`、`seq`（非负整数）、`lifecycle`（版本 + request/receipt/execution 记录 + `request_id` 关联 + 状态枚举） | `invalid_missing_command_id.json`、`invalid_command_lifecycle.json` |

合法跨 owner 延迟共享已加入正例（`OBS-3`：ally 观测 → player 接收，`share_authorized_by=ally_intel`）。
探针 **78/0**，负例 fixture **24 个**。

---

## 三、#63 JC-B03P：五项归一

| 项 | 处理 |
|---|---|
| 旗舰/预算冲突 | 旗舰改为 `I-A1 → OCUVF-HEMATITE-6C`（20 点），`deployment_rule=in_formation`：计入编制点数与容量、不额外部署；**两套编制都含该舰级**。APOGEE（150 点超预算）移入历史附录 |
| 友军能力 | 友军 PALLET+SAFEHARBOR 在 catalog `weapons=[]`，回执改为**侦察/中继/协助撤离**；探针直接读 catalog 断言无武器、回执无「射击位/拦截/火控失能」 |
| 旧正文冲突 | 文档重写为**单一当前主案**（P0-r7-1），旧 62/70 点与 APOGEE 方案移入「附录 A 历史方案」 |
| 同 tick 规则不一致 | 校验改为按 `same_tick_priority` 推导（`defeat > victory > withdrawal > stalemate`）；新增 `TR-CIVILIAN-LOSS-SAME-TICK-WITHDRAW`（同 tick 民用损失+撤离 → **defeat**）；零完成只在时限到达时判 defeat |
| 双视图/贡献/文案 | 新增 `DV-1`（全部失能未报告：权威 `all_objectives_disabled` / 玩家 `unknown`）、`TR-ALL-DISABLED-NO-REPORT`、`TR-ALLY-AUTONOMOUS-WIN`（友军自主完成 → **stalemate** 推荐口径）、贡献规则（目标完成与玩家贡献分开）、完整简报/战报样例 |

探针 **247/0**，含 **6 个负例变体**（未知舰级 / 超容量 / 胜利缺失能事件 / 旗舰不在编制内 /
无武装友军声称开火 / 同 tick 违反优先级）。

---

## 四、C 回归（head `106a14f`）

```
Phase 0 gate:  6/6 PASS
Phase A gate:  3/3 PASS
Full matrix:   87 = 80 PASS / 7 FAIL / 0 TIMEOUT / 0 NOT RUN
BASELINE CHECK: known_fail=7 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
```
7 项历史失败保持原状，未刷新 baseline；未新增 baseline 条目。

## 五、仍未完成 / 待复核

- G0、K0 仍需 Sol 独立复核；本报告不自行宣告放行；
- P0 内容选择（战区命名、点数公式/预算、编制组合、目标阈值、零完成→defeat、友军自主完成→stalemate）待用户核对；
- #58–#62 未解锁；性能预算不达标（#49 保留）。
