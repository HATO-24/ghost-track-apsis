# PR65 R8 K0 原四项闭环复核

- 候选：`9d0f3b4380275b0a30fffb4a29fa5c44ef58165f`；日期：2026-10-26 Asia/Shanghai。
- 范围：只复核 R7 原四项与 legacy 可信本舰锚点说明；不新增运行态/AI开发前提。
- Godot：`4.7.2.stable.official.ed1daf0bf`，Windows。

**结论：本次指定的原四项已闭环，K0 本分项无新增阻塞。** 自带 probe **84 PASS / 0 FAIL、退出 0**；独立窄诊断 14 组中 10 组是本次门槛，**10/10 符合预期、0 门槛偏差**。其余 4 组保留为非阻塞观察（含 legacy 纯函数边界），不将其变成另一个返修批次。

## 静态闭环

1. `seq` 现在明确必需：缺失分支返回“缺少 seq”，合法值仍按非负安全整数检查。
2. `lifecycle_version` 现在只接受 `v17.cmd_lifecycle.v1`，未知版本有明确拒绝原因。
3. `received_by_intel_owner_id` 现在必须显式存在，缺失不再静默默认成 `intel_owner_id`。
4. canonical 合同 §8.2 明确定义 observer 原始 owner、共享授权方、接收 owner、显式 receiver；§8.2.1 / §8.5.1 补字段表，§8.5 明确事件标识、seq、版本及三段关联，旧的“授权者等于接收 owner”语义已替换。新增合法 OBS-3 与新规范一致。

## legacy 本舰锚点说明的边界

canonical §8.5.2 明确 `own` 来自场景配置的可信锚点，不允许命令自己的两个字符串相等就自证本舰；正例 own/shooter=I-A1，负例扩展 all_allies 与 shooter 指向第二舰。

本轮验证的是 K0 来源/适配口径冻结，不声称运行态适配器已接入独立可信锚点。纯 `Contracts.validate` 仍只比较传入 own 与 shooter；legacy 自声明第二舰的诊断行不因此升级为新的本轮阻塞。后续实际接入旧调用时按此已冻结来源实现并测试，不擅自指定哪艘舰应作产品旗舰。

## 额外观察保持非阻塞

复用 R7 的 14 组窄诊断，并标记 `gating`。反向生命周期时刻、拒绝回执后 completed、不同命令重复 event/seq/request 的三组仍只是先前额外观察；不把它们重新列为 G0/K0 前置要求。`gating=false` 的 legacy 自声明行仅说明纯校验器的边界。

诊断退出 0 表示脚本完成，需看各行 `gating/matches`。实际执行结果见 `probe.log` / `mutations.log` / `mutations.json` / `results.json`。本分项还在根代理因模型容量临时中断期间代为完成一次统一导入（`--headless --editor --import`，退出 0），原始日志为 `import.log`；随后已通知其他分项可以运行。未运行全矩阵，由根代理统一负责。

## 复现

```powershell
$env:JC_K0_AUDIT_OUTPUT = (Join-Path (Get-Location) '.test-results/r8-k0-audit/mutations.json')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script (Join-Path (Get-Location) '.test-results/r8-k0-audit/mutations.gd')
& 'D:/GHOST TRACK_APSIS/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path './game_v17' --script 'res://tests/jc_contracts_probe.gd'
```

只写本目录证据，未改生产代码、baseline、阈值或 GitHub。
