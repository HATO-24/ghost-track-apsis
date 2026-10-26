# R8 · #56 G0 三项窄复核

日期：2026-10-26（Asia/Shanghai）。被审 HEAD：`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`。Godot：`4.7.2.stable.official.ed1daf0bf`，Windows。

**结论：上轮 #56 的 null、公开 partial 透传、满载新增输出比较三项均 CLOSED。未发现本轮改动相关的新阻塞。** 本结论仅覆盖这三项；统一回归、长测证据和总闸门由根代理汇总。没有修改生产代码或 GitHub。

## 1. TWS 显式 null 不再绕过类型校验 — CLOSED

复用 R7 的真实通道反例：通过 `Tws.ingest` 生成完整通道，设为 STARE，逐一仅把 `history`、`stare_s`、`stare_required_s`、`quality`、`state_since_t` 设为 null。

- 五种载荷均在 `validate_state` 和 `import_state` 明确拒绝，错误指出相应字段 `is null (required)`。
- 五次拒绝前后完整 `export_state()` 相同；没有提交坏通道或推进后端。
- 完整合法 STARE 正对照可导入并继续一步，保留一个通道；日志没有 R7 的 Nil→Array SCRIPT ERROR。
- 修复点：`game_v17/framework/sim/tws.gd` 类型循环对显式 null 添加错误，缺键和 null 都必须经过拒绝路径。原两阶段导入路线保留。

证据：`tws_null_audit.gd`、`.json`、`.log`；最终退出 **0**。

## 2. 旧 v1 的 partial 结果传到公共调用层 — CLOSED

使用同一份由精确 C55 源码实际生成并自读成功的 `c55_valid_save.json`，没有用删字段的新档替代真实旧输入。

- `GameSession.load_state` 返回 `ok=true`，同时公开 `sensor_restore_mode=partial` 和三个 `sensor_partial_reasons`。
- `sensor_restore_report()` 返回 `schema=v17.sensor_restore.v2`、`restore_mode=partial`、`is_partial=true`，原因与底层 `SensorService.import_state` 一致：`mount_pointing_missing`、`tws_runtime_reset_unrecoverable`、`authority_clock_rebuilt_from_optical_t`。
- 将这次迁移后的**当前可用状态**重新保存，再加载该新格式，正对照返回 `full`、`is_partial=false`、原因空数组。它证明新格式报告不会误标 partial，不代表旧文件未记录的历史被重建。
- 新披露放入恢复元数据，没有写进规范化游戏 snapshot 的 warnings。

证据：`legacy_partial_audit.gd`、`.json`、`.log` 和旧输入 `c55_valid_save.json`；最终退出 **0**。

## 3. 满载通信历史下的新增产出比较 — CLOSED

沿用原 50-tick 真实场景与 pending 消息，将两个会话的通信历史补到相同的 200 条，序号水位和分配器均设为 200，保持实际 `MAX_EVENTS=200`。

- 先继续相同输入，合法正对照的 `_behavior_violations(...,1)==[]`。
- 再由两个会话实际 `send_comms` 生成相同消息，只改恢复会话的 pending 正文。
- 下一步两端真实产出 `DELIVERED`、相同 ID `C-000002`、相同 seq **203**，正文不同；两边历史仍恰好 **200** 条。
- 正常比较器给出 `area=comms.events.new` 并报告正文差异，即刻 pending 比较也能检出。原先 `slice(200)==[]` 的漏检已关闭。
- 源码已用尾记录 `id/seq/event_id` 水位提取新增记录，水位被整段淘汰时回退比较保留记录；bus/observation 调用同一提取函数。本独立动态反例验证通信满载正负对照，不冒充已分别注入所有输出通道。

证据：`saturated_comms_audit.gd`、`.json`、`.log`；最终退出 **0**，`output_detected=true`。

## 复现命令与范围

工作目录：`C:/Users/ASUS/.codex/worktrees/jc-r8-validation/GHOST TRACK_APSIS`。K0 复核代理完成一次统一导入，退出 0，其原始日志为 `.test-results/r8-k0-audit/import.log`。本代理没有重复导入或长测。

```powershell
$engine='D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$audit=Join-Path (Get-Location) '.test-results/r8-save-audit'
$env:R8_NULL_OUT=Join-Path $audit 'tws_null_audit.json'
& $engine --headless --path ./game_v17 --script (Join-Path $audit 'tws_null_audit.gd')
$env:R6_LEGACY_OUT=Join-Path $audit 'c55_valid_save.json'
$env:R8_LEGACY_RESULT=Join-Path $audit 'legacy_partial_audit.json'
& $engine --headless --path ./game_v17 --script (Join-Path $audit 'legacy_partial_audit.gd')
$env:A07_HEAD='9d0f3b4380275b0a30fffb4a29fa5c44ef58165f'
$env:R8_SATURATED_OUT=Join-Path $audit 'saturated_comms_audit.json'
& $engine --headless --path ./game_v17 --script (Join-Path $audit 'saturated_comms_audit.gd')
```

退出 0 表示各脚本的实际正负条件符合预期；不是仅表示诊断运行完毕。聚合数据见 `audit_results.json`。原始日志保留引擎退出时的既有资源清理诊断，未把它们当新业务缺陷。没有扩查新系统，也没有重开 R7 已关闭项。
