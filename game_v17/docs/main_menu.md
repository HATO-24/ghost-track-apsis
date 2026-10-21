# 主菜单 / Main Menu（方案B-21 task-187）

## 流程
- 工程主场景改为 `res://main_menu.tscn`；`main_menu.gd` V1 自绘（LayoutTokens/PanelPainter，无 Control 面板）。
- NEW GAME：清空 `load_slot`/`flow_state`，进入 `prologue.tscn`。
- CONTINUE：从 SaveService 的 save/menu/autosave 有效槽中取 updated_at 最新，读档进入 `v1_hud.tscn`；无存档显示 `NO SAVE` 并禁用。
- LOAD：显示 save/menu/quit/autosave 槽列表（exists/corrupted/updated/chapter/location/path），点击有效槽读档。
- SETTINGS：明确占位页，不伪造设置项。
- QUIT：确认弹层后才 `get_tree().quit()`。

## 读档
- 主菜单把 `load_slot` 写入 root meta + `DSH_LOAD_SLOT` env，再切 `v1_hud.tscn`。
- `ShellBinder.boot()` 若指定 load slot：SaveService `_read_slot_raw` → `session_save`；补 seed `combat_service` 后对当前已 boot 的 session `load_state`；成功 `load_ok=true`；失败 `load_error` 明确。
- `v1_hud` 若 `load_slot_requested` 失败：显示 `LOAD FAILED reason` 并切回 `main_menu.tscn`（不伪造成功）。
- 不真正实现主菜单之外的结局/剧情/物理；读档不写 world。

## 视觉
- 标题 `GHOST TRACK // APSIS`、版本 V1.7、OCUVF/ID13 徽记；当前工程没有 `assets/emblems/*.png`，使用 V1 程序化徽记（明确标注，不伪造图片资产）。
- 1920×1080 / 1600×900 自适应；截图 `mockups/main-menu-1920.png`、`main-menu-1600.png`。

## 边界
1. SETTINGS 仅占位。
2. 读档使用 raw payload + 当前 session 组件恢复；标准 load_session 不覆盖可选组件。
3. 主菜单是 V1 自绘 Control 根（页面壳），非旧 HUD 面板。
4. 未跑全量 regression。


---

## 设置面板 / SETTINGS（task-191）

- `SETTINGS` 打开 V1 自绘设置面板；数据源 `SettingsService`（`scripts/core/settings_service.gd`）：
  - `language`（中/日/英）、`master_volume`/`music_volume`/`sfx_volume`（0–100%）、`subtitles`；
  - `text_speed`、`default_time_scale`、`display_mode`、`ui_scale`；
  - `SAVE` → SettingsService.save()；`APPLY` → apply_audio/apply_display + time_scale；`RESET` → SettingsService.reset()；`CLOSE`。
- 服务 ready 显示 `SettingsService READY · user://settings.json`；未 ready 明确 NOT READY。
- 实测：`SETTINGS TEST ready=true save=true path=user://settings.json apply_audio=true master=0.55`。
- 主菜单徽记：优先 `res://assets/emblems/id13.png` / `ghost_track.png`；当前工程这两个 PNG 不存在，回退程序化徽记并显示 `NO PNG ASSET · PROCEDURAL FALLBACK`，不谎称图片资产。
- 截图 `mockups/main-menu-settings-1920.png`、`main-menu-emblem-1920.png`。
- v1_hud ESC 入口未做；SettingsService 只做数据/接口（音频/显示后端由服务 apply_* 决定），不改 world/物理。
