# JC-A01 第四轮 T1/T2 验收强化证据

## 红灯对照（故意制造缺口 → 新断言必须变红）

| 对照 | 做法 | 结果 |
|---|---|---|
| T1 
egctl_a1_missing_contact.gd.txt | 在消费者快照中删掉一个**已获证据**目标的 contact 行（模拟生产回归） | **FAIL** very acquired-evidence target has a contact row (["harmattan"])，退出 1 |
| T2 
egctl_ws_noop_mutation.gd.txt | 把隐藏真值变更改成 no-op（不实际移动） | **FAIL** hidden mutation actually changed the compared target ({}) + FAIL hidden mutation changed PhysicsWorld，退出 1 |

原始输出：
egctl_*.stdout.txt、
egctl_*.stderr.txt、
egctl_*.exit.txt。
对照脚本为正式 probe 的临时副本（仅注入上述一处变化），运行后已删除；副本原文保留为 .gd.txt 便于复现。

## 正式 probe（强化后）

- 1_entity_metadata_authority：**359/0** —— 新增「already-acquired target 必须有 contact 行」显式断言。
- 0_world_physics_sync：**107/0** —— 观测/变更/比较同一真实目标 harmattan；先证明 truth_changed + physics_changed + physics 坐标确已变；无新观测时 plot 保持旧采样；合法新观测后同一目标位置/时间更新。
- jc_authority_intel：**90/0** —— 显式 target_a contact 行断言 + 同目标隐藏变更/新观测更新。

## 归档运行（代码 SHA eb4b98530b589dd5c452a78d46549660985557d3，其后仅新增文档）

| 文件 | 内容 |
|---|---|
| targeted-summary.json / *.log.txt | 复核指定 5 项：全 PASS（A01 90/0、metadata 359/0、world-sync 107/0、integration 65/0、save 41/0） |
| r4g0-summary.json / r4ga-summary.json | Phase 0 6/6、Phase A 3/3 |
| full-summary.json | 完整 strict 88 项：**81 PASS / 7 历史 FAIL / new_fail=0 / drift=0 / complete=true** |
