# 阶段1B · 中日英输入法组件 / 玩家名输入

> 任务 task-117。新文件：
> `scripts/ui/ime_input.gd`、`scripts/ui/ime_candidate.gd`、`scripts/ui/player_name_input.gd`、
> `player_name_input.tscn`、`tests/ime_probe.gd`、本文件。
> 不接剧情/存档；只做输入组件与视觉。

## 1 文件 / API

### `ImeInput`（`ime_input.gd`，Control）
- 属性：`text`、`composition`、`candidates`、`selected`、`page`、`max_length=24`、`duplicate_names`、`duplicate_check: Callable`、`candidate_window`。
- 方法：
  - `set_text(s)` / `set_composition(comp, cands)` / `apply_ime_composition(comp, cands)`（外部 IME 桥注入）
  - `set_candidates(cands)`、`select_next/prev()`、`next_page/prev_page()`、`confirm_candidate()`、`cancel_composition()`
  - `validate_name(n)` → `{ok,reason,value,max_length}`；`commit_name()` → 同 result 并 emit `submitted`
  - `cancel()`、`reset()`、`focus_input()`、`to_dict()/to_json()`
- 信号：`text_changed/composition_changed/candidate_changed/submitted/cancelled/focus_changed`。
- 键：↑↓ 候选、ENTER 确认/提交、ESC 取消组合或输入、PgUp/PgDn 翻页、BACKSPACE；可打印 `unicode` 追加。
- 过滤：控制字符/emoji/大部分特殊符号；保留 CJK/日文/韩文/拉丁字母/数字/空格/`-_·`；空格归一；长度按字符数截断。
- 校验：空名 `empty_name`、<2 字符 `name_too_short`、重复名 `duplicate_name`（静态数组或 Callable 接口）。

### `ImeCandidate`（`ime_candidate.gd`，Control）
- 自绘 V1 候选窗：标题/组合串/候选行/选中行/页码/选择提示。
- `set_data(comp, cands, selected, page)`；`place(input_rect)`：
  - 优先输入框右侧；右侧不足时放输入框下方；下方越界时放上方；最终 clamp 到屏幕 `8px` 内。
- `page_count()`/`current_page_rows()`；5 条/页，PgUp/PgDn 由 ImeInput 控制。

### `PlayerNameInput`（`player_name_input.tscn` + `player_name_input.gd`）
- 独立示例 scene：面板、玩家名输入、候选浮窗、确认/取消/DEMO 按钮、状态行。
- `DSH_UI_IME_DEMO=1` 注入示例：组合串「沧」、候选 `沧澜/沧海/沧溟/苍岚/苍梧`。
- `DSH_SHOT` 36–40 帧后保存并退出。

## 2 截图 / 验证

```powershell
$godot = "D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64.exe"
$env:DSH_SHOT="D:\GHOST TRACK_APSIS\mockups\ui-player-name.png"
$env:DSH_UI_IME_DEMO="1"
& $godot --path "D:\GHOST TRACK_APSIS\game_v17" res://player_name_input.tscn
```

- `mockups/ui-player-name.png`（1920×1080），`IME SHOT size=(1920, 1080) err=0`。
- Probe（一次）：

```powershell
& $godot --headless --path game_v17 --script res://tests/ime_probe.gd
# IME PROBE RESULT: PASS=64 FAIL=0 · IME PROBE OK
```

覆盖：字符过滤（CJK/日文/韩文/emoji/控制/特殊符号/空格）、长度、空名/过短/重复名（数组+Callable）、组合串、候选选择/翻页、确认/取消、候选窗避让/边界/翻页、JSON 确定性。

## 3 边界 / 未完成

1. **Godot 4.7.2 环境没有可用的 `InputEventIMEComposition` 类**；本组件通过显式 API（`set_composition/apply_ime_composition`）接收 IME 桥/演示注入，不依赖系统候选窗。真实平台 IME 事件需上层桥接（不同 OS/发行版行为不同）。
2. Probe 使用注入模拟，不验证 OS IME/系统候选窗；已标注。
3. 不接剧情/存档/玩家档案；示例数据仅 UI。
4. 候选窗自绘、固定 5 条/页；无鼠标滚动/触摸优化。
5. 过滤规则为白名单；如需标点/更多 Unicode 需扩展。
6. 未跑全量 regression。
