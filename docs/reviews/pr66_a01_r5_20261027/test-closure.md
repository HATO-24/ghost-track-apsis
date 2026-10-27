# PR66 原 T1/T2 收尾复核

日期：2026-10-27。工作树 HEAD `845584733df619feb3e372e8c06a7caa9f3fdaba`；T1/T2 代码提交 `00cdc2976516febb0d8fa0f571568bea104edaa1`。范围限定为原 PR66 的两个测试验收收尾；本复核未改生产代码、正式 probe 或 GitHub。

## 结论

- **T1 关闭：** metadata probe 从可信 owner 已获观测 tracks 得到明确的 track ID 集合，并逐一要求相应 contact 行存在。缺失已获证据目标会失败；正式运行 metadata 为 **359/0**。JC-A01 也明确断言 `target_a` contact 行、匿名 display ID 与 owner/source 路由；正式 A01 为 **90/0**。
- **T2 关闭：** world-sync 与 JC-A01 均观测、隐藏移动并比较同一实体。world-sync 确认 `truth_changed`、`physics_changed` 和 PhysicsWorld 坐标真实变化；无新观测时 plot 位置及采样时间保持旧观测；同一实体的合法新观测随后使位置和时间更新。正式 world-sync 为 **107/0**。
- **服务无需返工：** `git diff eb4b9853..84558473` 的生产代码唯一变更是 `_apply_hidden_truth_mutation` 增加 PhysicsWorld 前后快照及 `physics_changed` 返回字段；diff 未改授权、owner、观测融合、共享、存档、HUD/Binder 服务实现。其余变更是三个 probe 与证据文档。

## 负向控制运行

Godot：`D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64_console.exe`，Godot 4.7.2。根代理统一导入后运行，两副本各有效执行一次。脚本副本 SHA256：

- T1 `controls/negctl_a1_missing_contact.gd`：`1C1581F6DA64A768B1A47C432ABF48F90EE716F980563B8752693C244F099BB7`
- T2 `controls/negctl_ws_noop_mutation.gd`：`79B9AD6ECD7806ECCADEF6ECF42E6E14EB362670D4F46A9FFF10760F6AC4E09E`

| 控制 | 结果 | 判定依据 |
|---|---:|---|
| T1 删除一个已获证据 contact | exit 1，281 PASS / 1 FAIL | 唯一业务失败为 `every acquired-evidence target has a contact row (["harmattan"])` |
| T2 将隐藏变更替换为 no-op | exit 1，104 PASS / 3 FAIL | hidden mutation 未改变被比较目标、PhysicsWorld 未改变、PhysicsWorld 坐标未到达目标值 |

两次 stdout 均包含 probe 的最终结果汇总，没有 Parse Error、SCRIPT ERROR 或资源加载失败。stderr 只报告 Godot 退出清理时 `78 ObjectDB instances were leaked` 和 `31 resources still in use`，属于退出诊断，不是控制失败触发原因。日志、stderr 与退出码逐项保存在 `controls/`。

曾有一次未正确引用含空格脚本路径的启动尝试，Godot 未加载脚本（stderr 为 `Resource file not found ...\GHOST`）；该尝试不计作 probe 运行。随后每个控制只做了一次有效运行，最终 stdout/stderr/exit 文件记录有效运行结果。

## 正式运行摘要

根代理在 import-ready 消息中报告五项专项均 PASS：metadata 359/0、world-sync 107/0、A01 90/0、integration 65/0、save 41/0。正式 probe 未由本复核重复运行。
