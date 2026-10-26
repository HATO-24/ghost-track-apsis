# R8 返修报告：#56 / #57 / #63（G0 候选）

> 分支 `jc/g0-integration`；本轮提交
> `050836d`（#56 G0-1..4）、`e14eeae`（#57 K0-1..4）、`196d53c`（#63 P0-1..4）、`d8b0b27`（R8 证据归档）
> **长测测量代码 SHA：`196d53c04b85ef46305e96e88477588b54820bc0`**
> 起点 C55 = `30b8d33dae9787aadf89bb206757cafb2cad7bd3`；main 仍 `4b0b102c2c99e6d71a9378a25f9d2d45fb1286ea`
> Godot `4.7.2.stable.official.ed1daf0bf`，Windows

---

## 一、#56 JC-A00：G0-1 ～ G0-4

### G0-1 显式 null 绕过类型校验 → 已修
`tws.validate_state` 对 FSM 实际消费字段**不再 `null → continue`**：键存在但值为 `null`
直接报 `is null (required)`。审查方载荷（完整合法 STARE 通道仅把 `history` 改 null）现在导入即拒绝。
探针新增 3 个 null 反例：`history`/`stare_s`/`state_since_t` 显式 null → 全部拒绝。
原「缺字段」负例与正常快照保持通过。

### G0-2 partial 模式/原因未透传到公共 load → 已修
`GameSession.load_state` 现在把底层 `restore_mode` / `partial_reasons` 透传到：
- `load_state()` 返回值：`sensor_restore_mode`、`sensor_partial_reasons`；
- `sensor_restore_report()`：新增 `restore_mode` / `partial_reasons` / `is_partial`（schema `v17.sensor_restore.v2`）。
探针用**公共 load** 验证：旧档 → `partial` + `is_partial=true` + 非空原因；完整档 → `full`。

### G0-3 滚动历史满载后逐 tick 比较漏检 → 已修
`_behavior_violations` 不再按数组长度切片，改为**稳定序号水位**：
- EventBus `id`、Sensor observations `event_id`、Comms events `seq`；
- 每 tick 前取队尾水位，tick 后取「水位记录之后的记录」比较内容签名；
- 水位已被滚动淘汰时退化为全量比较（保守）。
新增 `A07_SATURATION_CHECK=1` 回归：两会话历史各预置 200 条后注入同 ID 不同正文的在途消息 →
**篡改被检出**（`comms.events.new`，first 显示 `SAT_ORIGINAL` vs `SATURATED_TAMPERED`）；
对照（正文一致）→ `violations=[]`。证据：`saturation/saturation.stdout.txt`（PASS 29/0）。

### G0-4 原始 stdout/stderr 未进入 Git → 已修
`docs/benchmarks/jc_r2/r8_196d53c0_20261026/`：
`summary.json`、`measurements.json`（`git_head=196d53c…`）、**`a0_save_cost.stdout.txt`**、
**`a0_save_cost.stderr.txt`**、`saturation/*.txt`、`README.md`——全部 **tracked**（用 `.txt` 避开 `*.log` 忽略）。
旧 `r7_a51e19f2…` 与 `a00_g0_measurements.json` 保留为历史对照。

### #56 验收（代码 `196d53c`）
```
四规模：PASS 90/0，1047.6 s（12 样本）
50t   433,956 B / save  84 ms / 恢复  1,422 ms / 读 2 ms
200t 1,151,356 B / save 256 ms / 恢复  8,772 ms / 读 4 ms
800t 1,935,007 B / save 361 ms / 恢复 49,600 ms / 读 5 ms
1000t 2,172,752 B / save 438 ms / 恢复 74,895 ms / 读 6 ms
```
正确性全绿；**性能预算仍不达标**（#49），未刷新阈值。

---

## 二、#57 JC-B00：K0-1 ～ K0-4

| 项 | 实现 | 负例 |
|---|---|---|
| K0-1 `seq` 必需性 | 缺 `seq` 直接拒绝（不再"非 null 才校验"），正负例统一 | `invalid_missing_seq.json` |
| K0-2 lifecycle 版本身份 | 白名单 `["v17.cmd_lifecycle.v1"]`，未知版本（如 `UNSUPPORTED-999`）拒绝 | `invalid_lifecycle_version.json` |
| K0-3 receiver 显式 | `received_by_intel_owner_id` **必须存在**（不再默认到 `intel_owner_id`），且必须等于 `intel_owner_id` | `invalid_obs_missing_receiver.json` |
| K0-4 正式合同归一 | `joint_campaign_r2.md` 更新：原始 owner / 接收 owner / 共享授权来源三者关系；新增**观测共享字段表**与**事件/命令字段表**（写者/读者/时间/可见域/拒绝原因）；lifecycle 支持版本；legacy 本舰锚点（可信来源，不由命令自证） | — |

合法形态仍保留：`OBS-3`（observer=ally、`share_authorized_by=ally_intel`、接收=`player_intel`）通过。
探针 **84/0**，负例 fixture **27 个**。

---

## 三、#63 JC-B03P：P0-1 ～ P0-4

| 项 | 处理 |
|---|---|
| P0-1 命名实体映射归一 | 删除覆盖式 `entity_bindings`（不再把 `apsis` 改绑 HEMATITE）；改用 `instance_bindings` 声明**虚构实例** `I-A1→OCUVF-HEMATITE-6C`、`I-P1→OCUVF-PALLET-5C`（`fictional=true`）；既有 `apsis→APOGEE` 目录原义不变；探针断言 `entity_bindings` 为空且实例舰级真实存在 |
| P0-2 预设 vs 自由编制 | 新增 `composition_rules`：两套编制是**推荐预设**；允许池内自由组合；给出池数量（PALLET×4、HEMATITE×3、GANTRY×2、SAFEHARBOR×1）、允许重复、`max_ships=3`、旗舰占位与自定义旗舰口径；约束 `sum(points)≤100 / ships≤3 / 含旗舰舰级` |
| P0-3 终态表补贡献例外 | `terminal_rules.victory.exception`、`contribution_exception`、`stalemate.also_covers` 写入同一规则表；主文终态表新增「三目标全完成但全为友军自主 → stalemate」行，消除双口径 |
| P0-4 具体文案样例 | 新增 `text_samples`：完整简报、胜利战报（对应 `TR-FULL-VICTORY`，含玩家/友军贡献、延迟、终态理由）、友军自主完成战报（对应 `TR-ALLY-AUTONOMOUS-WIN`，僵局口径），均标注「虚构样例」 |

探针 **269/0**，含 6 个负例变体。

---

## 四、C 回归（head `196d53c`）

```
Phase 0 gate:  6/6 PASS
Phase A gate:  3/3 PASS
Full matrix:   87 = 80 PASS / 7 FAIL / 0 TIMEOUT / 0 NOT RUN
BASELINE CHECK: known_fail=7 new_fail=0 drift=0 unverified=0 unselected=0 complete=true
```
7 项历史失败保持原状，未刷新 baseline、未新增条目。

## 五、仍未完成 / 待复核

- G0、K0 仍需 Sol 独立复核；本报告不自行宣告放行；
- P0 内容选择（战区命名、点数/预算、编制组合、目标阈值、零完成→defeat、友军自主完成→stalemate）待用户核对；
- #58–#62 未解锁；性能预算不达标（#49 保留）。
