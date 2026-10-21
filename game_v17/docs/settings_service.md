# 完整游戏-阶段4E · SettingsService（用户设置）

> 任务 task-190。工程 `game_v17`。
> 新文件：`scripts/core/settings_service.gd`、`tests/settings_probe.gd`、本文件。
> 不改其他；不写 world/V15；未 commit。

## 1　字段 / 默认 / 范围

| 字段 | 类型 | 默认 | 范围/枚举 |
| --- | --- | --- | --- |
| `language` | String | `zh` | `zh` / `ja` / `en` |
| `master_volume` | float | 0.8 | 0.0 – 1.0 |
| `music_volume` | float | 0.7 | 0.0 – 1.0 |
| `sfx_volume` | float | 0.8 | 0.0 – 1.0 |
| `subtitles` | bool | true | on/off |
| `text_speed` | float | 1.0 | 0.5 – 2.0 |
| `default_time_scale` | int | 1 | 1 / 10 / 60 / 300 |
| `display_mode` | String | `windowed` | `windowed` / `fullscreen` / `borderless` |
| `ui_scale` | float | 1.0 | 0.8 – 1.5 |

- `DEFAULTS`/`FIELDS`/`RANGES`/`LANGUAGES`/`DISPLAY_MODES`/`TIME_SCALES` 为可读常量。
- 非法类型/越界/未知字段一律拒绝且**不改状态**；`set`/`from_dict`/文件加载一致。

## 2　持久化 `user://settings.json`

文件 schema：

```json
{
  "schema": "v17.settings.v1",
  "version": "1.0.0",
  "settings": {
    "language": "zh",
    "master_volume": 0.8,
    "music_volume": 0.7,
    "sfx_volume": 0.8,
    "subtitles": true,
    "text_speed": 1.0,
    "default_time_scale": 1,
    "display_mode": "windowed",
    "ui_scale": 1.0
  }
}
```

- **原子写**：写 `<settings>.tmp` → 回读校验 → 旧主文件复制到 `.bak` →
  删除旧主文件 → rename `.tmp` → 主文件；rename 失败回滚 `.bak` 并清理 tmp。
- **缺失**：文件不存在 → 使用 `DEFAULTS`（`status=defaults_missing`，ready=true，不自动写盘）。
- **损坏**：主文件 JSON 不可解析/空/结构非法 → 尝试 `.bak`；有效则
  `status=recovered_backup`，否则 `status=recovered_defaults`+warning；
  不静默、不覆盖原文件（恢复后由 UI/调用方决定是否 save）。
- **非法字段值**：加载时逐字段回退默认 + warning；合法字段保留。
- **迁移**：
  - legacy flat（无 schema，如 `{language,master_volume,...}`）→ `from_version=legacy`；
  - `schema=v17.settings.v1` + `version=0.9.0` → `from_version=0.9.0`；
  - 未知/未来版本 → 回退 defaults + warning（不猜测未来格式）；
  - 迁移结果在 `last_load.migrated/from_version/status`。
- 文件内容确定性（无随机/时间戳）；同设置两次 save 文本一致。

## 3　API

| API | 说明 |
| --- | --- |
| `SettingsService.new(cfg)` / `setup(cfg)` | cfg：`path`/`settings_path`；默认 `user://settings.json` |
| `load_settings()` / `reload()` | 读文件（缺失/损坏/迁移逻辑）；返回 `{ok,status,source,migrated,from_version,path,warnings}`；因 GDScript 全局 `load()` 冲突，不提供 `load()` 方法 |
| `save()` | 原子写；返回 `{ok,path,atomic,backup,bytes}`；非法 settings 拒绝 |
| `get(key)`（Object.get 兼容，单参数） / `get_value(key, fallback=null)` | 读值；未知 key 返回 fallback/null |
| `set(key,value)`（Object.set 兼容，返回 void） / `set_value(key,value)` | 写值；非法拒绝且不改状态 |
| `from_dict(value)` | flat 或 `{settings:{...}}`；整体校验后原子应用 |
| `to_dict()` / `to_file_dict()` / `to_json()` | 设置副本 / 文件结构 / JSON |
| `reset()` | 恢复默认（不自动写盘） |
| `apply_audio()` | 返回 `{master_volume,music_volume,sfx_volume,muted,backends}`；不接实际音频总线 |
| `apply_display()` | 返回 display_mode/ui_scale/language/subtitles/text_speed/default_time_scale；不接实际窗口/本地化 |
| `defaults()` / `summary()` / `check_contracts()` / `last_error()` | 默认/摘要/DbC/最后错误 |
| `ready/errors/warnings/last_load` | 状态/加载结果 |

- `Object.get("language")` / `Object.set("language","en")` 通过 `_get/_set` 兼容；
  默认值读取请用 `get_value`。
- 失败返回：`not_ready/invalid_settings/write_failed` 或非法字段 reason；
  save 失败不破坏旧主文件（有 .bak 回滚）。

## 4　apply 接口

```text
apply_audio()  -> {ok, master_volume, music_volume, sfx_volume, muted,
                   backends:{audio:"interface_only",writes:{audio_bus:false}}}
apply_display()-> {ok, display_mode, ui_scale, language, subtitles, text_speed,
                   default_time_scale, backends:{display:"interface_only",
                   ui:"interface_only",writes:{window:false,ui:false}}}
```

- 只输出设置值/后端标志，不调用 AudioServer、不改 Window、不加载本地化表；
  由后续音频/显示/本地化/UI 系统消费。
- `muted = master_volume <= 0.0`（接口语义，不写真实总线）。

## 5　验证

```powershell
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless `
    --path .\game_v17 --script res://tests/settings_probe.gd
# V17 SETTINGS PROBE RESULT: PASS=179 FAIL=0（exit 0，只跑一次）
```

覆盖（6 节）：9 字段默认/范围；Object.get/set 兼容 + 17 类非法 set 原子拒绝 +
边界；from_dict full/wrapper/partial/5 类非法；save/load/原子写/tmp 清理/第二次 save
备份/内容确定性；损坏→bak→defaults、legacy/0.9 迁移、未来版本/非法字段回退、
非法 settings save 拒绝；apply_audio/display、muted 边界、reset、JSON 确定性、
不写 world/UI。probe 使用 `user://settings_probe.json`，结束时清理主/`.bak`/`.tmp`。

## 6　边界

- 只做设置数据/文件/校验/迁移/apply 接口；**不接 UI/实际本地化表/音频/显示后端**；
  不写 world/TrackTable/V15；不做设置界面/输入法/字体度量。
- `user://settings.json` 为默认路径；测试可用自定义 `path`；不实现云同步/加密。
- 损坏恢复策略：主→bak→defaults；不自动覆盖原文件；迁移不会写回文件，需显式 save。
- 未跑其他 probe；未 commit。
