# 完整游戏-阶段2E · SaveService 文件存档

> 任务 完整游戏-阶段2E（task-123）。工程 `game_v17`。
> 新文件（不改其他；不做 UI/剧情/物理；未 commit）：
> - `scripts/core/save_service.gd`
> - `tests/save_probe.gd`（`PASS=156 FAIL=0`）
> - 本文件
> 基于 `GameSession.save_state()/load_state()` 的内存 JSON，提供**文件**存档：
> 槽位 / 原子写入 / 备份 / 损坏检测 / 版本迁移骨架 / 三色圆点意图。

## 1　文件格式

存档文件是两层 JSON（外层带校验和，内层 payload）：

```json
// 外层 v17.save_file.v1
{
  "schema": "v17.save_file.v1",
  "checksum": "<sha256(payload 字符串)>",
  "payload": "<JSON 字符串，内层 v17.session_payload.v1>"
}
```

内层 `v17.session_payload.v1`：

| 字段 | 说明 |
| --- | --- |
| `schema` | `v17.session_payload.v1` |
| `version` | 存档格式版本（当前 `1.0.0`，迁移用） |
| `game_version` | `v17` |
| `slot` | 槽位名（save/menu/quit/autosave） |
| `created_at` / `updated_at` | Unix 时间戳（覆盖保存保留 created_at） |
| `created_iso` | 创建时间字符串 |
| `chapter` / `location` | 章节/位置元数据（可选，空字符串） |
| `t_s` / `writer` | 保存时仿真时间/写者 |
| `order_count` / `comms_events` | 元数据摘要 |
| `meta` | 自定义元数据对象（JSON-safe） |
| `session_save` | `GameSession.save_state()` 返回的内存 JSON 字符串 |

- 校验和覆盖 payload 原文：篡改/截断/空文件/外层 schema 错 → `decode_file` 失败。
- 内层 `session_save` 由 `GameSession.load_state()` 重放恢复；失败则读档失败（不静默）。

## 2　路径 / 槽位

- 目录可配置：`SaveService.new(root_dir)` / `setup(root)`；默认 `user://saves`（真实用户目录）。
- 文件：`<root>/<slot>.json`；旧档备份 `<root>/<slot>.json.bak`；原子写临时 `<slot>.json.tmp`。
- 合法槽位：**save / menu / quit / autosave**；其它槽位拒绝（`invalid_slot`）。
- probe 使用 `OS.get_temp_dir()/v17_save_probe_*` 临时目录，测试后递归清理，**不污染真实用户目录**。
- 路径若为 `user://`/`res://` 会 `ProjectSettings.globalize_path` 后做文件系统操作；绝对路径直接用。

## 3　原子写入 / 备份

`atomic_write_text(path, text)`：

1. 若旧文件存在 → 先写 `<path>.bak`（保留旧档）；
2. 写 `<path>.tmp`，关闭后回读校验内容一致；
3. `rename(tmp → path)`（覆盖前移除旧主文件）；
4. 任何失败返回 `{ok:false,reason,errors}`，并清理 tmp；成功后无 `.tmp` 残留。

`save_session()` 使用该流程；覆盖保存保留 `created_at`、更新 `updated_at`；`restore_backup(slot)` 可回滚到
上一次保存；`list_slots()` 同时返回 `has_backup`、损坏标记。

## 4　API

| API | 说明 |
| --- | --- |
| `SaveService.new(root)` / `setup(root)` | 创建/校验存档目录；`ready/errors` |
| `save_session(session, slot="save", meta={})` | 保存（需 session.save_state）；返回 `{ok,slot,path,bytes,version,checksum,created_at,updated_at,backup_path,has_backup}` |
| `load_session(slot="save")` | 校验→迁移→`GameSession.load_state`；成功返回 `{ok,session,meta,payload,migrated}`；失败返回 `{ok:false,reason,errors}`，无伪造 session |
| `load_metadata(slot)` / `list_slots()` / `verify_slot(slot)` | 只读元数据/槽位列表（损坏槽标记 corrupted）/校验 |
| `save_with_intent(session, intent, meta={})` | intent ∈ `save/save_and_menu/save_and_quit`；映射槽 save/menu/quit；返回意图字段，不退出/不切 UI |
| `save_and_menu(session)` / `save_and_quit(session)` | 上述包装；`should_exit=false`、`should_show_menu` 仅 menu 为 true |
| `delete_slot(slot, delete_backup=true)` / `restore_backup(slot)` | 删除/回滚备份 |
| `has_slot` / `has_backup` / `slot_path` / `backup_path` | 路径与存在性 |
| `encode_file(payload)` / `decode_file(text)` / `migrate_payload(payload)` | 低层编解码/迁移（可用于工具链/测试） |

### 4.1　三色圆点（只写文件/返回意图）

| 圆点 | intent | 槽位 | 返回意图 |
| --- | --- | --- | --- |
| 保存 | `save` | `save` | `should_exit=false`，`should_show_menu=false` |
| 保存并回菜单 | `save_and_menu` | `menu` | `should_show_menu=true`，不退出 |
| 保存并退出 | `save_and_quit` | `quit` | `should_exit=false`（**不直接退出**，由上层决定） |

- SaveService **不调用 quit()/不切场景/不做 UI**；只写文件和返回意图字段。

## 5　损坏检测

读档 `load_session/load_metadata/verify_slot` 依次检查：

1. 文件存在/非空；
2. 外层 JSON/schema；
3. `sha256(payload 原文) == checksum`（篡改/截断即失败）；
4. payload JSON 可解析；
5. 版本迁移（见 §6）；
6. `session_save` 非空且 `GameSession.load_state()` 成功。

任何一步失败 → `ok=false` + `reason`（`missing_slot/empty_file/corrupted/invalid_slot/
unsupported_future_version/unsupported_old_version/missing_session_save/session_load_failed`）+ errors；
`load_session` 不返回半成品 session；`list_slots` 对损坏槽返回 `corrupted=true` 和 errors。

## 6　版本迁移骨架

- 当前格式版本 `CURRENT_VERSION = "1.0.0"`（内层 payload `version`）。
- 迁移入口 `migrate_payload(payload)`；已实现 **0.9.0 → 1.0.0** 示例：
  `session_state` → `session_save`，补 `game_version`，`meta.migrated_from=0.9.0`，`migrated_at`。
- 缺 `version` 视为 0.9.0（走迁移）；未来版本（> 1.0.0）拒绝 `unsupported_future_version`；
  无迁移路径的旧版本拒绝 `unsupported_old_version`。
- 新增版本时：在 `CURRENT_VERSION` 提升的同时在 `migrate_payload` 增加路径；旧 save 只读迁移、不原地改写。
- 外层 `v17.save_file.v1` 稳定；如需改外层，另起 schema 并保留读取兼容。

## 7　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/save_probe.gd
# V17 SAVE PROBE RESULT: PASS=156 FAIL=0（exit 0，只跑一次）
```

覆盖（9 节）：临时目录 setup/路径/槽位常量；保存→读取往返 snapshot 严格一致+元数据+JSON 外层校验；
覆盖保存（created 保留/updated 更新/备份旧档/恢复备份）；4 槽位+三色圆点意图（不退出）；
原子性（残留 tmp 清理/主文件更新/备份旧状态/atomic_write_text）；损坏（payload 篡改 checksum/
非法 JSON/空文件/缺槽位/外层 schema，均失败不静默、无 session）；迁移（0.9→1.0、未来版本拒绝、
未知旧版本拒绝、缺 version 迁移、snapshot 一致）；错误路径（非法槽位/null/非 GameSession/删除/
无备份/encode-decode）；清理临时目录。

## 8　边界 / 未完成

- 仅文件存档层：**不做 UI/剧情/物理**；不接旧场景/HUD；不写 V15/world。
- 只支持 **单档槽位**（save/menu/quit/autosave），无多存档页/云同步/加密/压缩。
- 备份只有一份 `.bak`（每次覆盖刷新）；无版本历史/自动轮转。
- 迁移只实现 0.9→1.0 骨架；真实旧格式若不同需补迁移函数。
- 三色圆点只返回意图，不实际退出/切菜单（由上层 UI/流程决定）。
- 基于 `GameSession` 的 seed+log 重放存档；存档大小随操作日志增长，无增量压缩。
- 未跑全量回归；未 commit。
