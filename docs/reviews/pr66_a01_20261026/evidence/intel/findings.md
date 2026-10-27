# PR66 JC-A01 owner 情报隔离独立复核

- 审查 head：`1d1e8399da438b77b74acee40d753711c8d2a8f9`；base：`3045311657609dfe10a133802b93dde2fc8abb79`。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`。只读生产代码；仅写本目录诊断证据，不改 GitHub。
- 原 #58 范围：真正的每 owner 融合/读取、授权共享到达后可见、HUD/list/selected/plot/导出及恢复。下面不要求提前实现 EW、完整 AI 或完整协同计划协议。

## [P1] I1：正式 HUD owner 绘图为空时退回 PhysicsWorld，隐藏坐标继续泄露

位置：`game_v17/scripts/ui/shell_binder.gd:1514–1569`，特别是 `1533–1535` 只有 `positions` 非空才返回安全 facade，`1540–1553` 随后枚举物理真值。正式 `GameSession._advance_sensors` 的 owner 投递只保留 range/bearing，不带 `pos_km`（`game_session.gd:1510–1523`），所以有真实 owner 航迹也会产生空 position 数组，不能假设空只发生在未就绪场景。

`hud_truth_audit.gd` 真实走 main_menu→v1_hud→ready Binder。未替换 session、不造假 HUD：

- player owner 有2条航迹，但 `session.plot_positions(player_intel).positions=[]`；`raider_2` 不在 owner 情报中。
- 同时 `binder.plot_positions()` 返回 `source=physics`、7实体，包括隐藏 `raider_2` 的精确位置/速度。
- 通过真实 `PhysicsWorld.upsert_entity` 将该隐藏实体移动 `[+1234,+77,+9]km`，没有推进 sensor 或通知 owner；owner视图和session facade前后完全不变，但真实 HUD 绘图相应坐标立即改变。
- 具体值：原 `[2480.997…,300.000…,-99.999…]`，后 `[3714.997…,377.000…,-90.999…]`。

证据：`hud_truth_audit.{gd,json,log}`。退出0表示审查脚本成功复现泄漏；不能写成产品验收通过。此处直接使用有效物理更新API，没有使用本PR那个未实际改变物理状态的hidden-truth测试钩子。

最小收尾：玩家绘图无情报时也必须返回该owner的空/未知结果；不得退回全量PhysicsWorld或snapshot.entities。保持内部物理/弹道真值接口。将反例加入真实Binder/HUD消费测试，而非仅比较未接入的session facade。

## [P1] I2：owner 副本未隔离真实融合与列表；合法盟军观测仍进入玩家全局 TrackTable

位置：`game_v17/scripts/core/game_session.gd:1506–1524` 在投递独立owner字典后仍无条件 `track_table.handle_observation`；`shell_binder.gd:568` 的刷新继续用全局 `session.track_vm({})`，`selected_track:911–916` 也读该全局VM。新增 `authority_intel.intel` 是普通字典，不是原合同选定的独立TrackTable融合/衰减状态。

`owner_boundary_audit.gd` 使用自带probe相同三域seed，将一条合法结构的盟军sensor output放入真正 `sensor_service._outbox`，调用实际 `_advance_sensors(0.0)`。测试没有直接写TrackTable或玩家view：

- observer=`ally_ship`，target=`ally_private_contact`，range456km、bearing33°、L2光学观测。
- 路由结果ok、observations=1；ally owner得到1条，player owner仍零条，说明新增字典本身表面隔离。
- 但全局TrackTable实际生成 `T0001` / `entity_id=ally_private_contact`，真实 `ShellBinder.refresh()` 后玩家 `contacts` 有该航迹、range456，未走共享链路/玩家接收。

证据：`owner_boundary_audit.json` 的 `ally_sensor_route`（含 route、两owner view、global VM、player contacts）及脚本/日志。它证明真实消费路径仍混流，不是要求提供尚不存在的AI。

最小收尾：按已冻结K0选择真正每owner的融合/过期/selected状态，或等价的隔离容器；全部HUD/list/selected/plot/可见导出走对应owner facade。不要同时保留“隔离字典”和“对外共享全局融合”两套不一致事实。内部系统诊断/存档可以保留明确标注的真值，不能直接当玩家读接口。

## [P1/P2] I3：共享入口只相信 owner 字符串，未验证来源、到达时刻、时间/去重

位置：`game_session.gd:5764–5767` 公共包装直接调用；`authority_intel.gd:194–218` 只验证owner存在，然后覆盖owner并append/upsert；`owner_of_entity:181–184` 未登记observer默认归player。

同一三域seed，直接公共调用反例：

- `receive_intel_observation(player_intel, {observer_id:enemy_ship,path:direct,…})` 无共享授权或已投递证明仍 `ok=true`，敌方独有target立即进player view。
- `now_s=0`、收到记录声明 `observed_t=0, received_t=30, delay_s=30`，仍立即可见，没有等待实际链路到达。
- `observed_t=99, received_t=1, delay_s=-98` 仍接受并存为可见航迹。
- 同一 observation_id 再投递使 observations从2→3（现无去重）；`intel_owner_of(not_registered)` 返回 `player_intel`。
- 正对照：合法本舰direct输入接受；未知owner明确拒绝。这两个已有效分支保留，不重做。

证据：`owner_boundary_audit.{gd,json,log}`。退出0是诊断完成，具体ok/视图/数量才是结果。

最小收尾：明确哪层是可信“已投递”写者，并在该边界校验已登记observer原始owner、合法共享授权/接收owner、实际到达时刻、有限非负和单调时间/一致delay以及观测幂等键；未知来源不能默认本方。无需提前做EW或完整协同AI，但不能以“未来由协议调用”代替本卡要求的基本共享到达门及负例。

## 执行

根代理统一import结束后独立执行两个脚本。工作目录为候选worktree根：

```powershell
$env:A01_INTEL_HUD_OUT=Join-Path (Get-Location) '.test-results/sol-a01/intel/hud_truth_audit.json'
$env:A01_INTEL_BOUNDARY_OUT=Join-Path (Get-Location) '.test-results/sol-a01/intel/owner_boundary_audit.json'
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script (Join-Path (Get-Location) '.test-results/sol-a01/intel/hud_truth_audit.gd')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script (Join-Path (Get-Location) '.test-results/sol-a01/intel/owner_boundary_audit.gd')
```

两个脚本exit0均为可复现诊断完成。退出时既有ObjectDB/资源清理stderr保留，未与上述业务失败混淆。无新增生产实现、无baseline变更、未重复全矩阵。
