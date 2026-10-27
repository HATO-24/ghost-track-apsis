# PR66 第二轮：HUD / owner 路由窄复核

候选 `61f27fc8e841666705b5fd2e843824a03bf6c0b8`；Windows / Godot `4.7.2.stable.official.ed1daf0bf`。本轮只重放前轮真实HUD与盟军未共享观测对照，不重新扩查。统一导入由根代理完成，exit0；本分项未改生产代码、GitHub或baseline。

## CLOSED：空 owner 绘图不再退回 PhysicsWorld（旧 I1 / R3a）

复用原 `hud_truth_audit.gd`，仍真实走 `main_menu.tscn → v1_hud.tscn → ready Binder`。仅把被审SHA、结果文件及正负预期改为第二轮，实际通过 `PhysicsWorld.upsert_entity` 移动隐藏 `raider_2` `[+1234,+77,+9]km`。

- `owner_tracks=2`、`owner_positions=0`，`raider_2` 不在owner view。
- `binder.plot_positions()` 现在返回 `source=intel`、`positions=[]`，不再返回七个物理实体。
- 实际物理更新成功；owner view/facade不变，HUD前后也不变，目标未暴露。
- 诊断exit0：这次明确表示关闭条件成立，不沿用上一轮“泄漏成功”为绿的含义。

修复点 `game_v17/scripts/ui/shell_binder.gd:1596–1598`：有情报facade时，空即返回空，不回退真值。保留修复，下一轮不再要求重做。

证据：`hud_truth_audit.{gd,json,log}`。

## CLOSED（窄项）：盟军未共享观测不再进入玩家 contacts（旧 I2 的列表消费部分 / R3b）

`ally_route_audit.gd` 复用同一合法盟军sensor输出（observer=`ally_ship`、target=`ally_private_contact`、range456km、bearing33°），放入真实 `sensor_service._outbox`，调用实际 `_advance_sensors(0.0)`，没有直接写TrackTable或player facade。

- 路由ok、observations=1；ally owner一条，player owner零条。
- `ShellBinder.refresh()` 后 `contacts=[]`，原先会出现的盟军私有航迹已不再出现在玩家列表。
- 修复点 `shell_binder.gd:573–575`，contacts切到 `_build_contacts_from_intel(_intel_owner())`；本舰owner提示也不再固定apsis。

证据：`ally_route_audit.{gd,json,log}` 中 `contacts_closed=true`。该窄修复已关闭，不因下述未完成融合而抹掉。

## 原 R3 仍未完成：全局融合与 selected 路径未收拢

同一次合法盟军输入仍在全局TrackTable生成T0001（`game_session.gd:1531` 无条件 `track_table.handle_observation`）。`ShellBinder.refresh()` 仍缓存全局 `track_vm`，`selected_track` 仍按该全局表查找（`shell_binder.gd:975–980`）。

最小结果：player owner零条、contacts零条，但 `binder.selected_track({track_id:T0001})` 仍返回 `entity_id=ally_private_contact` 与range456等完整全局航迹。此处是同一原 R3“融合/selected/读取路径”未完成，**不是新的返修范围，也不是说已关闭的contacts修复失效**。

`authority_intel.gd` 仍用普通 owner 字典更新航迹，`selected(owner)`（`:395–400`）只过滤各dict的selected字段；尚无本轮已接入的每owner TrackTable融合/过期/选择写入口。作者已明确进度候选尚未完成，根代理的shipped probe负责汇总相关红项，本分项不重复跑43/13。

## 真实共享 callback：仅静态记录接线位置

本候选新增 `_deliver_intel_share`，由 `_reconcile_standalone` 的现有位置调用（`game_session.gd:2779`）；另有 `_drain_intel_deliveries` 函数。函数存在不等于真实到达正例通过；实际Comms到达/回调及对应shipped probe由根代理独立执行。本分项不据此自行宣告R4闭环，也不新增协议要求。

## 执行与局限

两个脚本最终均exit0，输出及判断分别在JSON；旧资源清理stderr保留。未重跑全量、未修改生产、不扩查其他系统。复现命令：

```powershell
$env:A01_INTEL_HUD_OUT=Join-Path (Get-Location) '.test-results/sol-a01-r2/intel/hud_truth_audit.json'
$env:A01_R2_ALLY_OUT=Join-Path (Get-Location) '.test-results/sol-a01-r2/intel/ally_route_audit.json'
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script (Join-Path (Get-Location) '.test-results/sol-a01-r2/intel/hud_truth_audit.gd')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game_v17 --script (Join-Path (Get-Location) '.test-results/sol-a01-r2/intel/ally_route_audit.gd')
```
