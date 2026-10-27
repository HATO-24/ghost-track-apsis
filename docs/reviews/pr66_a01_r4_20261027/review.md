# PR66 / JC-A01 第四轮独立复核

日期：2026-10-27（Asia/Shanghai）。**原三项实现缺口全部CLOSED；仅验收测试RETURNED，继续原#58，A1暂不冻结、PR66暂不合并。** 不再要求重做授权、owner老化、正常共享/读档或光学显示实现，不增加AI/EW/逐舰账本范围。

## 1. 被审版本与实际运行

被审PR66 HEAD `eb4b98530b589dd5c452a78d46549660985557d3`，代码提交 `c704f85952eb33ec44c1ac21dfef95d2f8b6a032`；两者差异只有返修报告头部。base/main仍 `3045311657609dfe10a133802b93dde2fc8abb79`。PR body写代码SHA属于可解释的文档后提交，不算新代码未测；本轮所有独立运行均用完整HEAD eb4b9853。

Windows / Godot `4.7.2.stable.official.ed1daf0bf`。根代理统一导入，然后运行专项及完整原C回归；只读审查两probe的契约映射，分项复跑原selected、31/301秒老化、在途共享实际文件恢复。未修改生产、正式probe、矩阵或baseline；诊断副本全部在`.test-results/sol-a01-r4`，归档于本文目录。[结构化结果](results.json)。

| 根代理运行 | 实际结果 |
|---|---|
| 五专项 | **5/5 PASS，退出0**；46.1s含22.1s import；metadata357/0、world-sync100/0、A01 76/0、integration65/0、save41/0 |
| 原C完整矩阵 | **88=81 PASS/7 FAIL**，7项均known且计数匹配；new_fail0、drift0、unverified0、unselected0、complete=true、退出0；340.45s |
| 独立情报诊断 | owner与share两个脚本均退出0；内存/公开SaveService文件各继续10tick通过 |
| 关联CI | [run40476218408](https://github.com/HATO-24/ghost-track-apsis/actions/runs/40476218408)三个job均success；本文full计数使用独立本地结果，不用页面绿色替代原始结果 |

[专项报告](targeted/report.md)、[专项summary](targeted/summary.json)、[完整报告](full/report.md)、[完整summary](full/summary.json)。full/selected-logs归档7项历史FAIL及3项本轮关键probe原始日志；完整运行的其余原始日志保留在本地`.test-results/sol-a01-r4/full/20261027-174812-eb4b9853`，不声称此目录包含全部88项原始log。import产生的`.import`/`.uid`不纳入交付；被测脚本与正式测试无本地改动。

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Only '(jc_authority_intel|a1_entity_metadata_authority|a0_world_physics_sync|a0_integration_authority|a0_save_roundtrip)' -Ci -ResultsDir .test-results/sol-a01-r4/targeted
pwsh -NoProfile -File ./run_tests.ps1 -GodotBin 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' -Baseline game_v17/tests/known_baseline_failures.json -Ci -NoImport -ResultsDir .test-results/sol-a01-r4/full
```

第二条复用同一HEAD、第一条完成的导入；strict模式无partial、无筛选。7项历史失败仍保持FAIL，未改期望或移出矩阵。

## 2. 三项实际实现关闭；既有关闭项保持

### owner生命周期 CLOSED

复用上轮同一合法t0单次观测、无新sensor输入，以真实`session.tick(31)`及`tick(270)`推进；player owner t0 fresh/age0，t31 stale=true/age31，t301移除，与现有全局表对照相符。未直接调用新advance替代真实tick。合法新观测刷新由正式A01 76/0覆盖。

selected隔离继续保持：全局盟军私有T0001仍存在，player无观测时selected_track/selected_entity都为空；合法本方local_contact的range111正例可读。没有把已修selected重新列成问题。

### 在途共享恢复 CLOSED

原合法三域夹具t2发出C-000001、ETA5。分别用内存save_state/load_state和公开SaveService.save_session/load_session真实文件，各继续10tick（t3..12）：20对完整owner view逐tick相等；t3/4共享/Comms pending都是1且不可见，t5才首次可见且pending归0。observed_t=2、received_t=5，两边相同，opfor始终空。

两个模式的原会话/恢复会话共四次同键重投均duplicated=true，观测数1→1、完整view不变。[情报分项说明](intel/findings.md)、[结构化汇总](intel/audit_results.json)、[真实槽位文件](intel/file-save/save.json)。两诊断退出码均0；退出清理stderr原样保留，不混为业务断言失败。

### 光学真实文本 CLOSED

`v1_hud.gd:643–650`不再拼内部track_id，实际metadata日志两条变为`ENTITY/TRACK TRACK-001 · UNKNOWN TRACK`、`TRACK-002 · UNKNOWN TRACK`；原no-truth和安全显示检查通过。内部target/track_id路由检查仍在并通过，未用改写内部ID隐藏问题。

来源授权、伪runtime第二舰拒绝、有限弹合法射击/context、contacts/空plot不回退真值、旧来源/畸形/null恢复、新probe注册及full退出码传递，均保留前轮关闭结论。本轮没有再扩查这些已关闭项。

## 3. 仅剩两组原验收合同，不是新的运行时缺陷

这轮生产修复与实际正例均成立；两个新适配probe在不满足其声称前提时仍能绿，尚未满足原R6“等强度正负例、真实变更后比较”的交付要求。两项留在原#58收尾，不拆新功能卡，不要求修改已通过的服务实现。

### T1 [P2] 明确锁定合法观测目标的contact，不把掉行当允许未知

`a1_entity_metadata_authority_probe.gd:251–260`只要求contacts非空，随后对任意缺失的场景实体直接continue，没有将缺失对象与本owner已获证据集合比较。本轮真实357/0确实检查了harmattan/l1_station两个合法TRACK，source/owner/匿名化追溯正确；问题是以后其中一个合法目标掉行时可以跳过全部相关检查仍通过。

诊断副本只在该步骤的消费者快照中过滤已经观测到的harmattan，保留l1_station与其余真实流程：输出`contacts non-empty n=1`、`contact absent for harmattan (allowed...)`，最终 **280/0、退出0**。这是测试盲点的控制实验，不表示生产Binder本次实际丢了harmattan，也不声称原正式probe返回280/0。[副本](contracts/metadata_missing_contact_control.gd)、[输出](contracts/metadata_missing_contact_control.log)、[退出码](contracts/metadata_missing_contact_exit.txt)。

最小修正：从可信owner的已获证据确定至少一个明确合法目标，要求对应contact存在并执行真实安全HUD断言；应通过内部`track_id`/获准entity映射匹配，不将匿名显示`id=TRACK-nnn`硬比内部target。对未获证据对象仍允许/要求缺席，不恢复原全7真值contacts。A01的`:255`也仅检查数量，可用同一明确目标正例补足；不要求在每个probe复制一整套重复测试。

### T2 [P2] 隐藏移动必须作用于被比较航迹对应的同一目标，并证明移动

`a0_world_physics_sync_probe.gd:353–386`观测和比较的是合成`ws_target`，调用隐藏变更的却是`harmattan`；不检查返回或前后真值，`before_move`没有使用。故“plot不跟随隐藏physics”这条断言无法证明所声称的边界。跨文件A01`:279–291`虽然检查truth_changed，却观测target_a、改raider_2、只比owner view，仍不能替代已观测同目标的真实HUD/plot边界。

诊断副本只将该隐藏变更分支禁用，其他代码不变，原“player plot does not follow hidden physics motion”仍PASS，最终 **100/0、退出0**。[副本](contracts/world_sync_noop_control.gd)、[输出](contracts/world_sync_noop_control.log)、[退出码](contracts/world_sync_noop_exit.txt)。不触碰正式probe或生产文件。

最小修正：选一个真实存在且该owner已获合法观测的同一目标；先断其contact/plot存在，保存观测位置/采样时间；实际变更该目标隐藏真值并断前后真的改变（声称physics就核对physics，不能只改WorldState副本）；不供新观测时真实HUD/plot仍读旧获准数据。随后投递合法新观测，断同一目标位置/时间确实更新，防止永远冻结。既有“未观测实体不凭空出现”负例可以保留，不拿它代替这个同目标对照。

内部完整7实体、PhysicsWorld→WorldState单向权威与精度（1e-9km、1e-12km/s、1e-6s）检查保留，新的精确intel_view来源/owner追溯、signal仅注册不产生contact的改法也保留。SIGNAL selected/plot不另外扩成新任务。

## 4. 下一次交付与界面工作

DeepSeek仅补T1/T2正式回归保护、更新契约映射及结果；保留三项实现关闭证据。应证明：故意遗漏已知目标/无实际移动时断言变红；正常实现时通过；同一最终40位SHA原C回归与7项历史基线继续匹配。若为补测试暴露实际缺陷，再具体报告；不得预先重写已闭环服务或放宽授权/显示来源。

本次独立完整C回归已经匹配，但不能替代上述测试前提。A1冻结/PR66合并及#59–#62解锁等待这两组原验收收尾；UI运行时仍按61号队列等待A1。UI文档、文案、交互规格由GPT/Sol维护，必要时Luna审校；DeepSeek负责明确卡片的代码实现，遵循用户最新分工。

Linux/macOS、非headless真实渲染/人工可读性、真实RF/光学物理、>1000tick成本本轮均NOT RUN，原专项任务/预算不变。完整联合战役Demo、逐舰战斗、友军AI也不因本轮底层修复而宣告完成。

证据校验见[SHA256清单](manifest.sha256)，不含清单自身。前轮记录为历史，以本轮三项CLOSED和两组测试剩余为准。
