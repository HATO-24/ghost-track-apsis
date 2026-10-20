# 阶段1H · 序章入口 / 行动简报 UI（prologue.tscn）

> 任务 task-136。新增：
> `game_v17/prologue.tscn`、`scripts/ui/prologue_flow.gd`、`scripts/ui/briefing_panel.gd`、本文件。
> 不改旧场景/project/核心；未 commit；不实现导航/物理/存档。

## 1 流程

```
PrologueFlow (prologue.tscn)
  ├─ phase=name：ImeInput + ImeCandidate（复用 ImeInput）
  │    ├─ 中/日/英输入；组合串/候选/↑↓/ENTER/ESC
  │    ├─ 空名/长度<2/非法字符拒绝；提交有效名
  │    └─ 提交后 → phase=briefing（不自动跳过）
  ├─ phase=briefing：BriefingPanel
  │    ├─ DRAFT 行动简报；标题/日期 2193-11-07/FROM/TO/摘要/目标/ROE/舰队/星图示意
  │    ├─ CONTINUE / SKIP（两者都进入 game_shell；不自动跳过）
  │    └─ get_tree().change_scene_to_file("res://game_shell.tscn")
  └─ 名字写入 root meta `player_name` + OS env `DSH_PLAYER_NAME`
```

- 截图入口：
  - `DSH_SHOT=.../mockups/prologue-name-1920.png`、`DSH_PROLOGUE_DEMO=1`（示例中文组合/候选）
  - `DSH_SHOT=.../mockups/prologue-briefing-1920.png`、`DSH_PROLOGUE_PHASE=briefing`
  - 默认进入 name；不自动跳过。

## 2 文本 key / 内容

- 简报正文来自 `framework/content/story_l1.json`，脚本只持有 key 表 `TEXT_KEYS`：
  - `title = prelude.title`
  - `body = prelude.body`
  - `confirm = prelude.confirm_text`
  - `execute = prelude.execute_text`
  - `fire_hint = fire_option.hint`
  - `notice_from/notice_to/notice_body`（备用）
- 舰队/港口 FROM/TO 来自 `framework/content/scenario_transit_l4_l1.json` 的 source/target/entities；不硬编码正文。
- 日期 `2193-11-07` 为任务固定值；`DRAFT · 剧本简报 / STORY BRIEFING` 明示未最终稿。
- UI 标签（MISSION BRIEFING / OBJECTIVES / ROE 等）为界面文案，非剧情正文。

## 3 布局

- 名字页：CenterContainer + PanelContainer 760×430；ImeInput 46px；候选窗绝对定位避让。
- 简报页：1920 设计基准 panel `Rect2(160,90,1600,880)`；左右分栏：摘要/目标/ROE/舰队 + 星图示意；按钮底部 `CONTINUE` / `SKIP`。
- V1 Theme/9-slice/字体；星图明确 `SCHEMATIC · NOT FOR NAVIGATION`。
- 不显示未润色占位；缺内容时显示 NOT READY。

## 4 截图 / 验证

| 文件 | 分辨率 |
| --- | --- |
| `mockups/prologue-name-1920.png` | 1920×1080 |
| `mockups/prologue-briefing-1920.png` | 1920×1080 |

- 均 `PROLOGUE SHOT err=0`；headless 场景加载一次；`prologue_flow.gd/briefing_panel.gd --check-only` 通过。

## 5 边界 / 未完成

1. 名字只写入 root meta/OS env，game_shell 当前未读取该名（shell 仍用默认指挥官名）；未改 shell（任务仅新增文件）。
2. 简报正文为 content DRAFT 文本；未接正式剧情运行时/分支。
3. CONTINUE/SKIP 都直接切 `game_shell.tscn`；未实现过场动画/异步加载。
4. 星图为示意，不是真实导航；不实现导航/物理/存档。
5. IME 为组件/注入模拟；系统 IME 需平台桥接（同 task-117 边界）。
6. 未跑全量 regression；未改 project main_scene。
